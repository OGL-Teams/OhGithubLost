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
/// - 数据库版本号写死为 `1`：本分支不维护"升级 → 数据迁移"流程
///   （IndexedDB 的 schema 升级只能修改 object store 定义）；未来如需新增
///   store / 索引，必须升版本号并实现 `onupgradeneeded` 的迁移分支。
/// - 异步失败（IndexedDB 不可用 / 隐私模式 / 配额耗尽）一律降级为内存，
///   **绝不抛**（与 [IoDiskKv] 在 localStorage 不可用时的语义对齐）。
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

/// `indexedDB` 全局对象（`window.indexedDB` 的精简视图）。
@JS('indexedDB')
external _IdbFactory _indexedDB;

/// `IDBFactory`（即 `indexedDB` 全局对象）的精简视图。
extension type _IdbFactory._(JSObject _) implements JSObject {
  /// `indexedDB.open(name, version)` → `IDBRequest`（异步）。
  external _IdbRequest open(String name, JSNumber version);
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

/// IndexedDB `IDBDatabase` 精简视图：只暴露本实现需要的读 / 写 / 删 / 列键能力。
extension type _IdbDatabase._(JSObject _) implements JSObject {
  /// 从 JSObject 包装（`IDBRequest.result`）。
  // ignore: unused_element
  external static _IdbDatabase wrap(JSObject object);

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

  /// 是否存在（count > 0 判存在）。
  Future<bool> exists(String storeName, String key) async {
    final _IdbTransaction tx = transaction(
      storeName.toJS,
      'readonly'.toJS,
    );
    final _IdbObjectStore store = tx.objectStore(storeName);
    final _IdbRequest request = store.count(key.toJS);
    final String? value = await _awaitResult(request, storeName);
    if (value == null) {
      return false;
    }
    final int? n = int.tryParse(value);
    return (n ?? 0) > 0;
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
      debugPrint('OGL blob_store: 解析 keys 失败（$error）');
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

/// 把 `IDBRequest` 的 `result` 通过 `JSON.stringify` 转成 String。
///
/// 之所以走 JSON：避免再多引入一套 JS 互操作接口（Dart 端拿到 String 就能用）。
Future<String?> _awaitResult(_IdbRequest request, String storeName) async {
  final completer = Completer<String?>();
  request.onsuccess = ((JSAny? _) {
    try {
      final JSAny? result = request.result;
      if (result == null) {
        completer.complete(null);
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
/// - IndexedDB 不可用（隐私模式 / 禁用存储）→ **自动降级为 [InMemoryBlobStore]**，
///   不抛；调用方无须 try/catch。
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
      final _IdbRequest request = _indexedDB.open(
        _kDbName,
        1.toJS,
      );
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
    } catch (error) {
      completer.completeError(error);
    }
    try {
      return await completer.future;
    } catch (error) {
      // 打开失败（隐私模式 / 禁用存储）：进入兜底，再也不重试。
      debugPrint('OGL blob_store: 打开 IndexedDB 失败（$error），降级为内存兜底');
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
      final String? value = await db.get(_kStoreName, fullKey);
      return value;
    } catch (error) {
      debugPrint('OGL blob_store: read 失败（$error）');
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
      debugPrint('OGL blob_store: write 失败（$error）');
      // 失败时降级写一次内存，避免上层静默丢数据。
      (_fallback ??= InMemoryBlobStore()).write(fullKey, value);
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
      debugPrint('OGL blob_store: remove 失败（$error）');
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
      final bool ok = await db.exists(_kStoreName, fullKey);
      return ok;
    } catch (error) {
      debugPrint('OGL blob_store: has 失败（$error）');
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
      debugPrint('OGL blob_store: keys 失败（$error）');
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