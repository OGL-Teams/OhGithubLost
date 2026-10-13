/// L1 底座级 · 装配引导：**把平台存储接进 L1**（组合根专用入口）。
///
/// 为什么需要它：`DiskModule` 缺省走内存实现（可测试）；真机上必须
/// 先解析平台存储（应用私有目录 + 平台密钥库），否则会出现
/// **“登录成功但重启即失忆、设置不落盘”** 的假象——这正是曾发生过的缺陷。
///
/// 约定：
/// - 解析成功 → 全部落真实磁盘（KV / 保险库 / 文件 / 缓存 / 日志 / 草稿）；
/// - 解析失败 → **退回内存实现**并把错误原样回传，由组合根大声上报，
///   绝不静默。
library;

import 'package:flutter/foundation.dart';

import '../kernel/contract/module.dart';
import '../kernel/log/og_l_log_file.dart';
import 'base_bridge.dart';
import 'disk/platform_io.dart';
import 'disk/platform_web_impl.dart';
import 'net/net_bridge.dart';

/// 组装 L1 全部模块（**真机默认路径**）。
///
/// [rootOverride] 供测试注入临时目录；真机保持缺省（应用私有目录）。
///
/// 返回 `(modules, storageError, persistentStorageResult)`：
/// - `modules` —— 装配好的模块列表；
/// - `storageError` —— `PlatformStorage.open` 自身抛出的致命异常
///   （如平台目录不可用、平台通道缺失等）；
/// - `persistentStorageResult` —— `navigator.storage.persist()` 的真实返回值
///   转成的字符串（`'granted'` / `'denied'` / `'unsupported'` / `'error: …'`）。
///   Web 平台独有：只有显式请求过，浏览器才**不会**在配额压力下把
///   `localStorage` 清掉 —— 不请求就等同于"随时可能丢"。
///
/// 三种状态分别处理、绝不互相掩盖，由组合根（`main.dart`）统一上报。
Future<
    ({
      List<OgLModule> modules,
      Object? storageError,
      String? persistentStorageResult,
    })> baseLayerModulesOnPlatform({
  NetModule? net,
  String folder = 'ohgithublost',
  String? rootOverride,
  void Function(String message)? onStorageFailure,
}) async {
  // 启动第一步 —— 请求持久化（Web 平台独有）。
  // 不请求就相当于告诉浏览器"随便清"。结果既回传给组合根供主线程上报，
  // 也立即写一行**内核级日志**（`OgLLogFile`），与 `OgLAppLog` 共享同一
  // 个落盘通道 —— 关于页能直接看到 `persistent=true/false`。
  final String? persistResult = await ogLRequestPersistentStorage();
  if (kIsWeb && persistResult != null) {
    final bool granted = persistResult == 'granted';
    OgLLogFile.line(
      'boot.persist',
      'persistent=$granted ($persistResult)',
      level: granted ? 'INFO' : 'WARN',
    );
    if (!granted) {
      debugPrint('OGL 启动：persistent storage 未授予（$persistResult）—— '
          'localStorage 在配额压力下可能被清空');
    }
  }
  try {
    final storage = await PlatformStorage.open(
      folder: folder,
      rootOverride: rootOverride,
      onFailure: onStorageFailure,
    );
    return (
      modules: baseLayerModules(net: net, disk: storage.toDiskModule()),
      storageError: null,
      persistentStorageResult: persistResult,
    );
  } catch (error) {
    return (
      modules: baseLayerModules(net: net),
      storageError: error,
      persistentStorageResult: persistResult,
    );
  }
}
