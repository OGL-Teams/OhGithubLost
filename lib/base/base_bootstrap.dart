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

import '../kernel/contract/module.dart';
import 'base_bridge.dart';
import 'disk/platform_io.dart';
import 'net/net_bridge.dart';

/// 组装 L1 全部模块（**真机默认路径**）。
///
/// [rootOverride] 供测试注入临时目录；真机保持缺省（应用私有目录）。
Future<({List<OgLModule> modules, Object? storageError})>
    baseLayerModulesOnPlatform({
  NetModule? net,
  String folder = 'ohgithublost',
  String? rootOverride,
}) async {
  try {
    final storage = await PlatformStorage.open(
      folder: folder,
      rootOverride: rootOverride,
    );
    return (
      modules: baseLayerModules(net: net, disk: storage.toDiskModule()),
      storageError: null,
    );
  } catch (error) {
    return (
      modules: baseLayerModules(net: net),
      storageError: error,
    );
  }
}
