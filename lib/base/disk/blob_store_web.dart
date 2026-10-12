/// L1 底座级 · 硬盘逻辑：[DiskBlobStore] 的 **Web 实现**（IndexedDB）。
///
/// ## 为什么走 IndexedDB 而不是 localStorage
/// `localStorage` 的限额是 **~5 MB / origin**；一旦草稿正文、提交日志条目、
/// 缓存内容字节超过这条线，`setItem` 会抛 `QuotaExceededError`，**整个写
/// 失败** —— 比"静默丢草稿"更糟糕（连失败信号都丢给用户）。
///
/// IndexedDB 的配额是**整个 origin 可用空间**（通常数百 MB 到数 GB，由浏览器
/// 决定），且支持二进制（`Uint8List` / `Blob` / `ArrayBuffer`），是浏览器下
/// "持久化大对象"的正确落点。
///
/// ## 实现要点
/// - 用 `dart:js_interop` 直接调 `indexedDB.open()`，**不引入** `package:web`；
/// - 单 object store（`ogl-blobs`），所有键都带 `web/blobs/` 前缀，
///   与 `IoDiskFileStore` 的内存文件表前缀**隔离**；
/// - **建仓在 `onupgradeneeded` 里做**：`createObjectStore('ogl-blobs')` 只能在
///   upgrade 事务中调用。漏掉这一步时 `open()` 照样 `success`（DB 存在、但没有
///   任何 store），之后每次 `transaction()` / `objectStore()` 都抛 `NotFoundError`
///   —— 所有读写都会落进内存兜底：**看着存了、其实一笔都没落盘**。
///   这正是本次修掉的"Web 存储逻辑异常"主因之一；
/// - 数据库版本号写死为 `1`：本分支不维护"升级 → 数据迁移"流程
///   （IndexedDB 的 schema 升级只能修改 object store 定义）；未来如需新增
///   store / 索引，必须升版本号并实现 `onupgradeneeded` 的迁移分支。
/// - 异步失败（IndexedDB 不可用 / 隐私模式 / 配额耗尽）降级为内存，
///   **绝不抛**（与 [IoDiskKv] 在 localStorage 不可用时的语义对齐），
///   但**绝不静默**：降级原因经 `KernelDiagnostics`（`OGL-DISK-20x`）留痕。
///
/// ## 与 IoDiskKv 的关系
/// - IoDiskKv = 普通设置项 + 小型元数据（localStorage）；
/// - IoDiskBlobStore = 大对象正文（IndexedDB）。
///
/// 二者**互不覆盖**：IndexedDB 数据键前缀 `web/blobs/` 与 localStorage 键前缀
/// `ogl.kv.web.` 不可能撞车（一个在 IndexedDB，一个在 localStorage）。
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../../kernel/contract/blob_store.dart';
import '../../kernel/diagnostics.dart';

// ── 诊断：base 层自己的通道（**不** import surface） ──────────────────

/// base 层诊断中枢（与 `disk_draft` / `disk_journal` / `platform_web_impl`
/// 同一套做法：本层自留痕，用户可见告警由上层从内核日志 / 通知中心读取）。
final KernelDiagnostics _diag = KernelDiagnostics();

/// 事件码：打开 / 建仓失败。
const String _kCodeOpen = 'OGL-DISK-201';

/// 事件码：读失败。
const String _kCodeRead = 'OGL-DISK-202';

/// 事件码：写失败（含写失败后的内存降级）。
const String _kCodeWrite = 'OGL-DISK-203';

/// 事件码：删失败。
const String _kCodeRemove = 'OGL-DISK-204';

/// 事件码：枚举键失败。
const String _kCodeKeys = 'OGL-DISK-205';

/// 事件码：打开被其它标签页阻塞。
const String _kCodeBlocked = 'OGL-DISK-206';

/// 上报一次 blob 存储故障：`debugPrint` + 内核诊断（**绝不静默**）。
///
/// 数据落点的故障必须能在关于页 / 磁盘日志里查到（grep 事件码即可），
/// 否则"草稿没了、缓存没了"对用户与排查者都是玄学。
void _report(String message, Object error, String code) {
  debugPrint('OGL blob_store: $message（$error）');
  _diag.warn(
    'BLOB',
    message,
    code: code,
    data: <String, Object?>{'error': '$error'},
  );
}

/// `indexedDB` 全局对象（`window.indexedDB` 的精简视图）。
@JS('indexedDB')
external _IdbFactory _indexedDB;

/// `IDBFactory`（即 `indexedDB` 全局对象）的精简视图。
extension type _IdbFactory._(JSObject _) implements JSObject {
  /// `indexedDB.open(name, version)` → `IDBOpenDBRequest`（异步）。
  external _IdbOpenRequest open(String name, JSNumber version);
}

/// `IDBRequest`（事件接口：`onsuccess` / `onerror` / `result`）。
///
/// IndexedDB 的每个操作（open / transaction / put / get / delete）都返回
/// `IDBRequest`，由浏览器异步派发 `success` 或 `error`。
extension type _IdbRequest._(JSObject _) implements JSObject {
  /// 当前阶段的结果（依事件类型而异：open → `IDBDatabase`；put → key；等等）。
  external JSAny? get result;

  /// `onsuccess` 回调签名：`() => void`。
  external void set onsuccess(JSFunction? callback);

  /// `onerror` 回调签名：`(event) => void`。
  external void set onerror(JSFunction? callback);
}

/// `IDBOpenDBRequest`：比普通 [_IdbRequest] 多两个事件。
///
/// - `upgradeneeded`：**唯一能创建 object store 的时机**（在 upgrade 事务里）；
/// - `blocked`：另一个标签页还占着旧连接，本次升级被挡住 —— 事件可能一直不来
///   `success`，因此不能"无限等待"（会把上层的读 / 写全部挂死）。
extension type _IdbOpenRequest._(JSObject _) implements JSObject {
  /// 结果（`upgradeneeded` 与 `success` 两个阶段都是 `IDBDatabase`）。
  external JSAny? get result;

  /// `success`：打开完成。
  external void set onsuccess(JSFunction? callback);

  /// `error`：打开失败（被禁用 / 版本冲突 / 配额）。
  external void set onerror(JSFunction? callback);

  /// `upgradeneeded`：建仓 / 迁移。
  external void set onupgradeneeded(JSFunction? callback);

  /// `blocked`：被其它连接挡住。
  external void set onblocked(JSFunction? callback);
}

/// IndexedDB `IDBDatabase` 精简视图：只暴露本实现需要的读 / 写 / 删 / 列键能力。
extension type _IdbDatabase._(JSObject _) implements JSObject {
  /// 从 JSObject 包装（`IDBRequest.result`）。
  external static _IdbDatabase wrap(JSObject object);

  /// 创建 object store（**只在 `onupgradeneeded` 的 upgrade 事务里合法**）。
  ///
  /// 不建 store 的话：数据库本身照样打开成功，但之后每次 `transaction()` /
  /// `objectStore()` 都抛 `NotFoundError` —— 所有读 / 写都会掉进内存兜底。
  external void createObjectStore(JSString name);

  /// `transaction(storeNames, mode)` → `IDBTransaction`。
  external _IdbTransaction transaction(JSAny storeNames, JSString mode);

  /// 读单个 key（`objectStore(storeName).get(key)`）→ 值或 `null`。
  Future<String?> get(String storeName, String key) async {
    final _IdbTransaction tx = transaction(
      storeName.toJS,
      'readonly'.toJS,
    );
    final _IdbObjectStore store = tx.objectStore(storeName);
    final _IdbRequest request = store.get(key.toJS);
    return _awaitResult(request, storeName);
  }

  /// 写单个 key（覆盖）。
  Future<void> put(String storeName, String key, String value) async {
    final _IdbTransaction tx = transaction(
      storeName.toJS,
      'readwrite'.toJS,
    );
    final _IdbObjectStore store = tx.objectStore(storeName);
    final _IdbRequest request = store.put(value.toJS, key.toJS);
    await _awaitResult(request, storeName);
  }

  /// 删单个 key（不存在时静默）。
  Future<void> delete(String storeName, String key) async {
    final _IdbTransaction tx = transaction(
      storeName.toJS,
      'readwrite'.toJS,
    );
    final _IdbObjectStore store = tx.objectStore(storeName);
    final _IdbRequest request = store.delete(key.toJS);
    await _awaitResult(request, storeName);
  }

  /// 是否存在（`count(key) > 0` 判存在）。
  Future<bool> exists(String storeName, String key) async {
    final _IdbTransaction tx = transaction(
      storeName.toJS,
      'readonly'.toJS,
    );
    final _IdbObjectStore store = tx.objectStore(storeName);
    final _IdbRequest request = store.count(key.toJS);
    // 直接拿原始结果判数值：不要经过"字符串化再 parse"，
    // 否则数值格式一变（`1` / `1.0`）判定就会静默翻车。
    final JSAny? raw = await _awaitRaw(request, storeName);
    if (raw == null) {
      return false;
    }
    if (raw is JSNumber) {
      return raw.toDartDouble > 0;
    }
    final String? text = _jsonStringify(raw)?.toDart;
    return (int.tryParse(text ?? '') ?? 0) > 0;
  }

  /// 列全部 key（`getAllKeys()`）。
  Future<List<String>> allKeys(String storeName) async {
    final _IdbTransaction tx = transaction(
      storeName.toJS,
      'readonly'.toJS,
    );
    final _IdbObjectStore store = tx.objectStore(storeName);
    final _IdbRequest request = store.getAllKeys();
    final JSAny? raw = await _awaitRaw(request, storeName);
    if (raw == null) {
      return const <String>[];
    }
    // `getAllKeys()` 结果是 JS Array；逐项转 Dart String。
    try {
      final outer = raw as JSObject;
      final int length =
          (outer.getProperty<JSNumber>('length'.toJS)).toDartInt;
      final out = <String>[];
      for (var i = 0; i < length; i++) {
        final JSAny? item = outer.getProperty<JSAny?>(i.toJS);
        if (item is JSString) {
          out.add(item.toDart);
        } else if (item is JSNumber) {
          out.add(item.toDartInt.toString());
        }
      }
      return out;
    } catch (error) {
      _report('解析 IndexedDB keys 失败', error, _kCodeKeys);
      return const <String>[];
    }
  }
}

/// `IDBTransaction` 精简视图。
extension type _IdbTransaction._(JSObject _) implements JSObject {
  /// `objectStore(name)` → `IDBObjectStore`。
  external _IdbObjectStore objectStore(String name);
}

/// `IDBObjectStore` 精简视图。
extension type _IdbObjectStore._(JSObject _) implements JSObject {
  external _IdbRequest get(JSAny key);
  external _IdbRequest put(JSAny value, JSAny key);
  external _IdbRequest delete(JSAny key);
  external _IdbRequest count(JSAny key);
  external _IdbRequest getAllKeys();
}

/// 把 `IDBRequest.result` 转成 Dart String。
///
/// **字符串要原样返回**：以前一律走 `JSON.stringify()`，于是读回来的字符串
/// 被 JSON 引号包住（写 `hello` → 读回 `"hello"`），JSON 解析 / 文本内容全部
/// 变形 —— 这是"Web 存储逻辑异常"里最难察觉的一处（写进去对、读出来错）。
/// 只有在结果不是 JS 字符串时（数值 / 对象），才退到 `JSON.stringify`。
Future<String?> _awaitResult(_IdbRequest request, String storeName) async {
  final completer = Completer<String?>();
  request.onsuccess = ((JSAny? _) {
    try {
      final JSAny? result = request.result;
      if (result == null) {
        completer.complete(null);
        return;
      }
      if (result is JSString) {
        completer.complete(result.toDart);
        return;
      }
      // `JSON.stringify(value)` 把任意 JS 值序列化为字符串。
      final JSString? json = _jsonStringify(result);
      completer.complete(json?.toDart);
    } catch (error) {
      completer.completeError(error);
    }
  }).toJS;
  request.onerror = ((JSAny? event) {
    completer.completeError(
      StateError('IndexedDB 请求失败（$storeName）：${_errorMessage(event)}'),
    );
  }).toJS;
  return completer.future;
}

/// `_awaitResult` 的"原始 JSAny 版本"：仅在 `getAllKeys` 需要保留 JS 数组结构时使用。
Future<JSAny?> _awaitRaw(_IdbRequest request, String storeName) async {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((JSAny? _) {
    try {
      completer.complete(request.result);
    } catch (error) {
      completer.completeError(error);
    }
  }).toJS;
  request.onerror = ((JSAny? event) {
    completer.completeError(
      StateError('IndexedDB 请求失败（$storeName）：${_errorMessage(event)}'),
    );
  }).toJS;
  return completer.future;
}

@JS('JSON.stringify')
external JSString? _jsonStringify(JSAny value);

/// 从事件对象上尽量取出一个可读的错误消息。
String _errorMessage(JSAny? event) {
  try {
    if (event == null) {
      return 'unknown';
    }
    // 优先 `event.target.error`（IDBRequest 的常见结构）。
    final dynamic obj = event as JSObject;
    final JSAny? target = obj.getProperty<JSAny?>('target'.toJS);
    if (target is JSObject) {
      final JSAny? err = target.getProperty<JSAny?>('error'.toJS);
      if (err != null) {
        return '$err';
      }
    }
    return '$event';
  } catch (_) {
    return 'unknown';
  }
}

/// 基于 IndexedDB 的大对象 blob 存储。
///
/// ## 行为
/// - 构造函数立即发起 `open()`；首个 await 时若 DB 仍未就绪会等待；
/// - 打开时在 `onupgradeneeded` 里**建好** object store（缺了它所有读写都会
///   静默掉进内存兜底）；
/// - IndexedDB 不可用（隐私模式 / 禁用存储）/ 打开被阻塞 / 单次操作失败
///   → **降级为 [InMemoryBlobStore]**，不抛；调用方无须 try/catch，
///   但降级原因经 `KernelDiagnostics`（`OGL-DISK-20x`）留痕，**不静默**。
class IoDiskBlobStore implements DiskBlobStore {
  /// 创建 blob 存储。
  ///
  /// [root] 仅用于诊断展示（构造时打印用），与 [IoDiskFileStore] / [IoDiskKv]
  /// 共享同一虚拟根习惯（`web` / `app`）。
  IoDiskBlobStore({required String root}) : root = root;

  /// 数据库名。
  static const String _kDbName = 'ogl-blobs';

  /// object store 名。
  static const String _kStoreName = 'ogl-blobs';

  /// 数据库版本号。
  ///
  /// ★ 这一版**必须是 2**（曾经是 1）。
  ///   历史构建漏了 `onupgradeneeded` 里的 `createObjectStore`：库照样打开成功，
  ///   但里面**一个 store 都没有**，之后所有 `transaction()` 都抛 `NotFoundError`
  ///   → 读写全部掉进内存兜底（"看着存了、刷新即丢"）。
  ///   凡是跑过那些构建的浏览器，本地 DB **已经是 v1**；若不升版本号，
  ///   `onupgradeneeded` 永远不会再触发 → 这些用户**永远修不好**，
  ///   只有清站点数据才能恢复。升到 2 会让升级回调再跑一次，把缺的 store 补上。
  ///
  ///   （升级回调里 `createObjectStore` 已被 try/catch 包住：若某些环境里
  ///    store 已存在，抛出的异常会被吞掉并如实上报，不会让升级事务中止。）
  static const int _kDbVersion = 2;

  /// 根前缀（用于诊断展示）。
  final String root;

  /// 写入 IndexedDB 的键前缀（如 `web/blobs/`）。
  String get _prefix => 'web/blobs/';

  /// 完整前缀（含根归一化）。
  String get fullPrefix => _normalizePrefix(_prefix);

  static String _normalizePrefix(String value) {
    var v = value.replaceAll(r'\', '/');
    while (v.length > 1 && v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return '$v/';
  }

  /// open() 完成的 Future；多个写 / 读共用一份等待链，避免开多份连接。
  Future<_IdbDatabase?>? _openFuture;

  /// 降级后的内存兜底（IndexedDB 不可用时被填充）；`null` 表示仍在等待打开。
  InMemoryBlobStore? _fallback;

  /// 取出 IndexedDB 后端；若不可用则返回 null（调用方走兜底）。
  ///
  /// 打开失败 / 被阻塞一律**降级为内存**并留痕：宁可"本会话不落盘"，
  /// 也绝不让上层的读 / 写挂在一个永远不完成的事件上。
  Future<_IdbDatabase?> _database() async {
    final fb = _fallback;
    if (fb != null) {
      return null;
    }
    final pending = _openFuture;
    if (pending != null) {
      return await pending;
    }
    final completer = Completer<_IdbDatabase?>();
    _openFuture = completer.future;
    try {
      final _IdbOpenRequest request = _indexedDB.open(
        _kDbName,
        _kDbVersion.toJS,
      );
      // ★ 建仓：`createObjectStore` **只能**在 `upgradeneeded` 的 upgrade
      //   事务里调用。漏掉它时数据库照样打开成功，但里面一个 store 都没有，
      //   之后所有 `transaction()` / `objectStore()` 都抛 `NotFoundError`
      //   → 读写全部掉进内存兜底：**看着存了、刷新即丢**。
      request.onupgradeneeded = ((JSAny? _) {
        try {
          final JSAny? result = request.result;
          if (result is JSObject) {
            _IdbDatabase.wrap(result).createObjectStore(_kStoreName.toJS);
          }
        } catch (error) {
          _report(
            'IndexedDB 建仓失败（object store `$_kStoreName` 未创建）',
            error,
            _kCodeOpen,
          );
        }
      }).toJS;
      request.onsuccess = ((JSAny? _) {
        try {
          final JSAny? result = request.result;
          if (result == null) {
            completer.completeError(
              StateError('IndexedDB open 返回空 result'),
            );
            return;
          }
          completer.complete(_IdbDatabase.wrap(result as JSObject));
        } catch (error) {
          completer.completeError(error);
        }
      }).toJS;
      request.onerror = ((JSAny? event) {
        completer.completeError(
          StateError('IndexedDB open 失败：${_errorMessage(event)}'),
        );
      }).toJS;
      request.onblocked = ((JSAny? _) {
        // 其它标签页占着旧连接：可能只是短暂阻塞，也可能**永不完成**。
        // 这里选择如实降级（内存 + 上报），而不是把上层挂死在等待里。
        _report(
          'IndexedDB 打开被其它标签页阻塞 → 本次会话降级为内存（数据不落盘）',
          'blocked',
          _kCodeBlocked,
        );
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('IndexedDB open 被阻塞（$_kDbName）'),
          );
        }
      }).toJS;
    } catch (error) {
      completer.completeError(error);
    }
    try {
      return await completer.future;
    } catch (error) {
      // 打开失败（隐私模式 / 禁用存储 / 被阻塞）：进入兜底，再也不重试。
      _report('打开 IndexedDB 失败，降级为内存兜底（数据不落盘）', error, _kCodeOpen);
      _fallback = InMemoryBlobStore();
      return null;
    }
  }

  @override
  Future<String?> read(String key) async {
    final fullKey = _prefixedKey(key);
    final fb = _fallback;
    if (fb != null) {
      return fb.read(fullKey);
    }
    try {
      final db = await _database();
      if (db == null) {
        return await _fallback?.read(fullKey);
      }
      return await db.get(_kStoreName, fullKey);
    } catch (error) {
      _report('读取 blob 失败（键 $fullKey）', error, _kCodeRead);
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final fullKey = _prefixedKey(key);
    final fb = _fallback;
    if (fb != null) {
      await fb.write(fullKey, value);
      return;
    }
    try {
      final db = await _database();
      if (db == null) {
        await _fallback?.write(fullKey, value);
        return;
      }
      await db.put(_kStoreName, fullKey, value);
    } catch (error) {
      // 写失败（配额满 / 事务中断 / 连接已关闭）：降级写一次内存，
      // 避免上层静默丢数据 —— 但**必须上报**：这条数据本会话之后就没了。
      // 注意 `await`：不 await 的话调用方返回后立刻读会读不到（竞态丢数据）。
      await (_fallback ??= InMemoryBlobStore()).write(fullKey, value);
      _report('写入 blob 失败 → 已降级为内存（键 $fullKey，刷新即丢）', error, _kCodeWrite);
    }
  }

  @override
  Future<void> remove(String key) async {
    final fullKey = _prefixedKey(key);
    final fb = _fallback;
    if (fb != null) {
      await fb.remove(fullKey);
      return;
    }
    try {
      final db = await _database();
      if (db == null) {
        await _fallback?.remove(fullKey);
        return;
      }
      await db.delete(_kStoreName, fullKey);
    } catch (error) {
      // 删失败 = 数据可能还留在盘上（与上层"已删除"的认知相反），必须留痕。
      _report('删除 blob 失败（键 $fullKey）', error, _kCodeRemove);
    }
  }

  @override
  Future<bool> has(String key) async {
    final fullKey = _prefixedKey(key);
    final fb = _fallback;
    if (fb != null) {
      return fb.has(fullKey);
    }
    try {
      final db = await _database();
      if (db == null) {
        final fallback = _fallback;
        return fallback != null ? await fallback.has(fullKey) : false;
      }
      return await db.exists(_kStoreName, fullKey);
    } catch (error) {
      _report('判断 blob 是否存在失败（键 $fullKey）', error, _kCodeRead);
      return false;
    }
  }

  @override
  Future<List<String>> keys() async {
    final fb = _fallback;
    if (fb != null) {
      return _stripList(await fb.keys());
    }
    try {
      final db = await _database();
      if (db == null) {
        final fallback = _fallback;
        return _stripList(fallback != null
            ? await fallback.keys()
            : const <String>[]);
      }
      final List<String> all = await db.allKeys(_kStoreName);
      return _stripList(all);
    } catch (error) {
      _report('枚举 blob 键失败', error, _kCodeKeys);
      return const <String>[];
    }
  }

  String _prefixedKey(String key) => '$fullPrefix$key';

  /// 去掉内部前缀，仅向调用方暴露他们写时的 key。
  List<String> _stripList(Iterable<String> raw) {
    final p = fullPrefix;
    final out = <String>[];
    for (final k in raw) {
      if (k.startsWith(p)) {
        out.add(k.substring(p.length));
      }
    }
    out.sort();
    return out;
  }
}