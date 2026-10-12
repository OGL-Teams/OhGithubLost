/// L1 底座级 · 硬盘逻辑：**Web 实现**（浏览器目标，本分支唯一实现）。
///
/// 由 `platform_io.dart` 直接导出；公开 API（`PlatformStorage` /
/// `PlatformDiskPaths` / `IoDiskFileStore` / `IoDiskKv` / `SecureDiskVault`）
/// 保持既有名字不变，`DiskKv` / `DiskVault` / `DiskFileStore` 三大契约
/// （见 `kernel/contract/disk_store.dart`）按下面如实写明的差异实现。
///
/// ## 浏览器下的真实语义（**不假装**）
/// - **没有文件系统**：`IoDiskFileStore` 是**进程存活期内有效**的内存文件表。
///   刷新页面即清空；`sweepTemp()` 无残骸可扫，恒返回 0。
///   —— 注释即约定：这里**不假装**能把文件持久化。
/// - **KV 走 `localStorage`**：`IoDiskKv` 把值写进浏览器 `localStorage`
///   （键按应用根前缀隔离），因此键值在刷新后仍在。若 `localStorage`
///   不可用（隐私模式 / 禁用存储），自动降级为进程内存，绝不抛。
///   但**绝不静默吞** —— 配额满（`QuotaExceededError`）或被禁用
///   （`SecurityError`）必须上报到用户可见的层：base 层走 `KernelDiagnostics`
///   （`code = OGL-DISK-1xx`，落盘后可在关于页 / 磁盘日志里 grep），
///   同时经 [OgLStorageFailureCallback] 回调把消息交给组合根，
///   由 `main.dart` 转成 `OgLAppLog` / 通知中心的用户可见告警
///   （详见 `surface/app/error_surface.dart`）。**base 不 import surface**。
/// - **安全保险库无系统密钥库**：浏览器没有 Keystore / DPAPI / libsecret。
///   为避免把长期令牌**明文**留在 `localStorage`，Web 端保险库**仅内存持有**
///   （刷新后需重新登录）。这是一处**如实的能力缺失**，不是静默降级。
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../../kernel/diagnostics.dart';
import 'disk_bridge.dart';
import 'disk_cache.dart';
import 'disk_draft.dart';
import 'disk_journal.dart';
import 'disk_store.dart';

// ── localStorage 互操作（dart:js_interop）──────────────────────────────

@JS('localStorage')
external _WebStorage get _localStorage;

/// 浏览器 `Storage` 的最小接口（只声明用到的成员）。
extension type _WebStorage._(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// 浏览器 `Navigator.storage`（仅实现 [persist] 与 [estimate] 两个用到的成员）。
///
/// `persist()` 返回 `Promise<bool>` —— `true` 表示浏览器愿意把数据当作
/// "持久"（不在配额压力下清空）；`false` 表示会按普通规则清。
extension type _WebStorageManager._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> persist();
  external JSPromise<_StorageEstimate> estimate();
}

/// 全局 `navigator.storage`（Navigator Storage API）。
@JS('navigator.storage')
external _WebStorageManager get _navigatorStorage;

/// 请求浏览器把本地存储标记为"持久"。
///
/// Web 平台独有：返回 `'granted'` / `'denied'` / `'unsupported'` /
/// `'error: …'`；非 Web 平台调用方保证不会调到这里（`base_bootstrap.dart`
/// 已在 web 分支内才 await 本函数）。
///
/// 浏览器里默认存储是"尽力而为"（best-effort）—— 配额压力下浏览器可以
/// 直接清掉 `localStorage`。调用 `navigator.storage.persist()` 请求浏览器
/// 把用户当前 origin 标记为"持久"，清空优先级会大幅下降。
Future<String> ogLRequestPersistentStorage() async {
  try {
    final JSBoolean granted = await _navigatorStorage.persist().toDart;
    return granted.toDart ? 'granted' : 'denied';
  } catch (error) {
    return 'error: $error';
  }
}

/// `navigator.storage.estimate()` 的结果结构（只用到两个字段）。
extension type _StorageEstimate._(JSObject _) implements JSObject {
  external JSNumber? get quota;
  external JSNumber? get usage;
}

/// 基于内存文件表 + `localStorage` KV 的存储（浏览器）。
///
/// ## 两条硬规则（与 io 实现对齐的**契约**）
/// 1. **路径安全**：所有相对路径落表前经 [abs]：归一化前导 `/`（绝对路径因此
///    落在根内，不会逃逸）、**拒绝** `..`。空串是合法入参（`list('')` = 列根）。
/// 2. **删/写幂等**：不存在时删除静默、覆盖写入替换——上层无需区分实现。
class IoDiskFileStore implements DiskFileStore {
  /// 创建文件存储（`root` 仅作虚拟前缀 / 诊断展示，浏览器下不落真实目录）。
  IoDiskFileStore({required String root}) : _root = _normalizeRoot(root);

  final String _root;

  /// 根目录（浏览器下的**虚拟**前缀，如 `web/files`）。
  String get root => _root;

  /// 内存文件表：键 = 归一化后的**根内相对路径**，值 = 文本内容。
  /// 进程存活期内有效；页面刷新即清空（浏览器无持久文件系统）。
  final Map<String, String> _files = <String, String>{};

  static String _normalizeRoot(String root) {
    var value = root.replaceAll(r'\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 触发长路径处理的门槛（Win32 的 MAX_PATH 是 260）。
  ///
  /// Web 无 Win32，保留常量只为与 io 实现**公开 API 对齐**。
  static const int kWinPathSoftLimit = 240;

  /// Windows 长路径前缀。Web 不存在 Win32，原样返回。
  static String winLong(String posixAbs) => posixAbs;

  /// 把仓库相对路径解析为绝对路径，并执行安全校验（与 io 实现同一条规则）。
  ///
  /// `relative` 为空表示根目录本身（仅 [list] 允许）。
  String abs(String relative) {
    final path = InMemoryFileStore.normalize(relative);
    if (path.split('/').contains('..')) {
      throw ArgumentError.value(relative, 'path', '路径不得包含 ..（防目录穿越）');
    }
    return path.isEmpty ? _root : '$_root/$path';
  }

  /// 取内存表的归一化键（空路径是非法文件路径）。
  String _key(String relative) {
    final path = InMemoryFileStore.normalize(relative);
    if (path.isEmpty) {
      throw ArgumentError.value(relative, 'path', '文件路径不能为空');
    }
    return path;
  }

  @override
  Future<String?> readText(String path) async => _files[_key(path)];

  @override
  Future<void> writeText(String path, String content) async {
    _files[_key(path)] = content;
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(_key(path));
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(_key(path));

  @override
  Future<List<String>> list(String directory) async {
    final prefix = InMemoryFileStore.normalize(directory);
    final scope = prefix.isEmpty ? '' : '$prefix/';
    final names = <String>{};
    for (final key in _files.keys) {
      if (!key.startsWith(scope)) {
        continue;
      }
      final rest = key.substring(scope.length);
      if (rest.isEmpty) {
        continue;
      }
      names.add(rest.contains('/') ? rest.substring(0, rest.indexOf('/')) : rest);
    }
    return names.toList()..sort();
  }

  /// 清扫中断残留的临时文件。浏览器下**没有文件系统**，也就没有残骸——恒 0。
  Future<({int removed, List<String> failed})> sweepTemp() async =>
      (removed: 0, failed: const <String>[]);
}

/// 错误回调：把 localStorage 故障上报到 surface 层（**注入式**，非 import）。
///
/// 由组合根（`main.dart` → `baseLayerModulesOnPlatform` → `PlatformStorage.open()`）
/// 注入；L1（base 层）**不直接** import surface 层（违反分层），
/// 通过回调反转依赖：`surface` 知道 `base`，`base` 不知道 `surface`。
typedef OgLStorageFailureCallback = void Function(String message);

/// 基于 `localStorage` 的键值存储（浏览器）。
///
/// 键按应用根前缀隔离（`ogl.kv.<root>.<key>`），因此刷新后仍在；
/// `localStorage` 不可用时自动降级为进程内存（绝不抛）。
///
/// ## 失败**绝不静默**
/// 配额满（`QuotaExceededError`）与被禁用（`SecurityError`）是浏览器
/// 通知用户的两大典型场景 —— 旧代码 `catch (_)` 一吞了之，用户重启发现
/// 设置全没了也找不到原因。
/// 现在：失败时把可读原因**逐条**写进 [lastFailure]（供上层展示），
/// 经 [KernelDiagnostics] 记一条 `OGL-DISK-1xx` 警告（base 层自己的通道），
/// 并通过 [onFailure] 回调（注入式）派发到组合根 → surface 层
/// `OgLAppLog.instance.add('存储', message, severity: warning)`；
/// 如果没注入回调（测试 / 早期启动），仍有 [lastFailure]、诊断日志与
/// `debugPrint`。注入方由 `main.dart` 的装配根完成（不破坏分层）。
///
/// ## 镜像（[_mirror]）只保存"**没落上去**"的值
/// 之前的写法是"写之前先把值放进镜像"，于是镜像里既有真值也有兜底值，
/// 且**永不失效**：另一个标签页删掉 / 浏览器清掉 `localStorage` 之后，
/// `read()` 仍会从镜像里把旧值捞回来（`has()` / `keys()` 同罪）——
/// 表现为"设置删了又活过来 / 退出登录后令牌还在内存里读得到"。
/// 现在：镜像只在**真实写失败**时填充，真实写成功即丢弃该键的镜像副本；
/// 真实存储里没有、镜像里也没有 ⇒ 如实返回"不存在"。
class IoDiskKv implements DiskKv {
  /// 创建键值存储。
  IoDiskKv({required String root, OgLStorageFailureCallback? onFailure})
      : _prefix = 'ogl.kv.${IoDiskFileStore._normalizeRoot(root)}.',
        _store = IoDiskFileStore(root: '$root/kv'),
        _onFailure = onFailure;

  final String _prefix;
  final IoDiskFileStore _store;
  final OgLStorageFailureCallback? _onFailure;

  /// 底层文件存储（诊断用；浏览器下为内存文件表，不参与 KV 读写）。
  IoDiskFileStore get store => _store;

  /// 降级镜像：**只在 `localStorage` 写 / 删失败时**填充。
  ///
  /// 它是"没真存上"的值的唯一去处（本会话读得到，刷新即丢），
  /// **不是**真实存储的缓存 —— 真值永远以 `localStorage` 为准。
  /// 否则会出现"镜像里复活已被删除的键"（详见类注释）。
  static final Map<String, String> _mirror = <String, String>{};

  /// base 层自己的诊断通道（与 `disk_draft` / `disk_journal` 同一套做法：
  /// base 不 import surface；用户可见的告警由 [onFailure] 回调带出去）。
  static final KernelDiagnostics _diag = KernelDiagnostics();

  /// 事件码：读失败。
  static const String kCodeRead = 'OGL-DISK-101';

  /// 事件码：写失败。
  static const String kCodeWrite = 'OGL-DISK-102';

  /// 事件码：删失败。
  static const String kCodeRemove = 'OGL-DISK-103';

  /// 事件码：存在性判断失败。
  static const String kCodeHas = 'OGL-DISK-104';

  /// 事件码：枚举键失败。
  static const String kCodeKeys = 'OGL-DISK-105';

  /// 最近一次失败原因（供上层展示用）。
  ///
  /// **保留最近一次**，不堆栈 —— 浏览器环境下 localStorage 不可用基本是
  /// "整会话不可用"，重复上报只会刷屏；上层重置/重建本对象即可清零。
  /// `null` = 这次会话内没有失败。
  String? _lastFailure;

  /// 最近一次失败的可读描述（`QuotaExceededError` / `SecurityError` /
  /// `Disabled`）。组合根据此决定要不要弹"存储失败"横幅。
  String? get lastFailure => _lastFailure;

  /// 清零失败标记（消费完成调用方手动清）。
  void clearLastFailure() {
    _lastFailure = null;
  }

  /// 记录一次失败：`lastFailure` + 内核诊断 + 注入式回调（三条路都走）。
  ///
  /// 绝不静默：配额满 / 被禁用这类"整会话不可用"的故障必须留下可查痕迹。
  void _report(String message, Object error, String code) {
    _lastFailure = message;
    debugPrint('OGL 存储：$message / $error');
    _diag.warn(
      'DISK',
      message,
      code: code,
      data: <String, Object?>{'error': '$error'},
    );
    _onFailure?.call(message);
  }

  @override
  Future<String?> read(String key) async {
    final String name = '$_prefix$key';
    try {
      final String? value = _localStorage.getItem(name);
      if (value != null) {
        // 真值在真实存储里 —— 顺手丢掉镜像里的旧副本，防两套值分叉。
        _mirror.remove(name);
        return value;
      }
      // 真实存储里没有这条：可能是别的标签页删的、也可能是浏览器清过站点数据，
      // 也可能是本会话写失败后的兜底。只有**确实写失败过**的键才会落在镜像里
      // （见 [write]），所以这里返回 `_mirror[name]` 既保住了兜底，
      // 又不会"复活"已被真实删除的键。
      return _mirror[name];
    } catch (error) {
      // ★ 读失败也要上报 —— 之前静默返镜像，用户连"我读不到我刚写的设置"
      //   这种真相都不知道；现在落 lastFailure + 内核诊断 + 注入回调。
      _report(
        'localStorage 读失败：${error.runtimeType}（键 $name）',
        error,
        kCodeRead,
      );
      return _mirror[name];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final String name = '$_prefix$key';
    try {
      _localStorage.setItem(name, value);
      // 落上了真实存储 → 丢弃镜像兜底副本（镜像只留"没落上去"的值）。
      _mirror.remove(name);
    } catch (error) {
      // 写失败（配额满 / 被禁用）：值只留在内存镜像里（本会话读得到），
      // 但必须如实告诉上层"没真存上" —— 刷新即丢，绝不假装成功。
      _mirror[name] = value;
      _report(
        'localStorage 写失败：${error.runtimeType}（键 $name）',
        error,
        kCodeWrite,
      );
    }
  }

  @override
  Future<void> remove(String key) async {
    final String name = '$_prefix$key';
    // 先清镜像：调用方要的语义是"这条已经没有了"，无论真实删除成功与否，
    // 都不该再从兜底副本里读出来。
    _mirror.remove(name);
    try {
      _localStorage.removeItem(name);
    } catch (error) {
      _report(
        'localStorage 删失败：${error.runtimeType}（键 $name）',
        error,
        kCodeRemove,
      );
    }
  }

  @override
  Future<bool> has(String key) async {
    final String name = '$_prefix$key';
    try {
      if (_localStorage.getItem(name) != null) {
        return true;
      }
    } catch (error) {
      // 读不到真实存储 → 只能按镜像判断；失败原因如实上报。
      _report(
        'localStorage has 失败：${error.runtimeType}（键 $name）',
        error,
        kCodeHas,
      );
    }
    return _mirror.containsKey(name);
  }

  @override
  Future<List<String>> keys() async {
    final names = <String>{};
    try {
      final int n = _localStorage.length;
      for (var i = 0; i < n; i++) {
        final String? name = _localStorage.key(i);
        if (name != null && name.startsWith(_prefix)) {
          names.add(name.substring(_prefix.length));
          // 真实存储里有的键 → 镜像副本作废（同一根键不该有两套值）。
          _mirror.remove(name);
        }
      }
    } catch (error) {
      // 存储不可用：只从镜像取；失败原因如实上报。
      _report(
        'localStorage keys 失败：${error.runtimeType}',
        error,
        kCodeKeys,
      );
    }
    for (final String name in _mirror.keys) {
      if (name.startsWith(_prefix)) {
        names.add(name.substring(_prefix.length));
      }
    }
    final result = names.toList()..sort();
    return result;
  }
}

/// 安全保险库：**Web 端仅内存持有**。
///
/// 浏览器没有 Keystore / DPAPI / libsecret；为不把长期令牌**明文**写进
/// `localStorage`，这里只保存在进程内存中——刷新页面即失效（用户需重新登录）。
/// 这是**如实的能力缺失**，不是静默降级：调用方拿到的仍是 [DiskVault] 契约。
class SecureDiskVault implements DiskVault {
  /// 创建保险库（Web 端无系统密钥库，构造不接收存储后端）。
  SecureDiskVault();

  static final Map<String, String> _secrets = <String, String>{};

  static const String _prefix = 'ogl.vault.';

  @override
  Future<String?> readSecret(String key) async => _secrets['$_prefix$key'];

  @override
  Future<void> writeSecret(String key, String value) async {
    _secrets['$_prefix$key'] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    _secrets.remove('$_prefix$key');
  }
}

/// 平台目录规划（浏览器下的虚拟前缀）。
class PlatformDiskPaths implements DiskPaths {
  /// 创建路径规划。
  const PlatformDiskPaths({required this.root});

  /// 根目录（虚拟前缀，如 `web`）。
  final String root;

  @override
  Future<String> cacheRoot() async => '$root/cache';

  @override
  Future<String> configRoot() async => '$root/config';

  @override
  Future<String> logRoot() async => '$root/logs';
}

/// 平台存储装配（Web）：解析虚拟根目录，构建内存文件表 + `localStorage` KV。
///
/// `folder` 仅为与 io 实现保持**同一签名**（浏览器无多档目录，恒用虚拟根 `web`）。
class PlatformStorage {
  /// 创建装配结果。
  const PlatformStorage({
    required this.root,
    required this.paths,
    required this.files,
    required this.kv,
    required this.vault,
  });

  /// 根目录（虚拟前缀）。
  final String root;

  /// 路径规划。
  final DiskPaths paths;

  /// 用户文件存储（内存文件表）。
  final DiskFileStore files;

  /// 键值存储（`localStorage`）。
  final DiskKv kv;

  /// 安全保险库（内存）。
  final DiskVault vault;

  /// 打开平台存储。
  ///
  /// [folder] 在 Web 端**不参与**目录解析（浏览器只有一档虚拟根），
  /// 仅为与 io 实现签名一致而保留；[rootOverride] 可覆盖虚拟根（测试 / 预览）。
  /// [onFailure] 由装配根注入，用于把 localStorage 故障上报到 surface 层
  /// `OgLAppLog` —— `base` 不直接 import `surface`（违反分层），通过回调反转。
  static Future<PlatformStorage> open({
    String folder = 'ohgithublost',
    String? rootOverride,
    OgLStorageFailureCallback? onFailure,
  }) async {
    final root = IoDiskFileStore._normalizeRoot(rootOverride ?? 'web');

    final files = IoDiskFileStore(root: '$root/files');
    // 启动清扫：浏览器无残骸，调用只为对齐 io 的启动流程（恒 0）。
    await files.sweepTemp();

    return PlatformStorage(
      root: root,
      paths: PlatformDiskPaths(root: root),
      files: files,
      kv: IoDiskKv(root: root, onFailure: onFailure),
      vault: SecureDiskVault(),
    );
  }

  /// 组装成 L1 硬盘模块（KV 走 `localStorage`，文件类落在内存表，日志见 `log_dirs` 的 web 分支）。
  DiskModule toDiskModule() {
    final indexKv = kv;
    return DiskModule(
      kv: kv,
      vault: vault,
      files: files,
      paths: paths,
      cache: RepositoryCache(
        index: indexKv,
        blobs: IoDiskFileStore(root: '$root/cache'),
      ),
      journal: WriteJournal(store: indexKv),
      drafts: DraftStore(store: indexKv),
    );
  }

  @override
  String toString() => 'PlatformStorage(root=$root, web=true)';
}
