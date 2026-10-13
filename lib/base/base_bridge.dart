/// L1 底座级 · 层桥：把"网络连接"与"硬盘逻辑"合成为对外唯一通道。
///
/// 架构要求（见 `docs/ARCHITECTURE.md（该文件未落地，以源码为准）`）：**每层只有一座桥**。
/// 因此 `base.net` 与 `base.disk` 各自注册服务后，由 [BaseLayerModule]
/// 把它们合成 [BaseBridge]，并以层级键 `base` 注册到内核桥表。
/// 上层（中枢）只允许 `resolve('base')` 拿桥，绝不允许直接 import 底座内部文件。
library;

import '../kernel/bridge_registry.dart';
import '../kernel/contract/module.dart';
import 'disk/disk_bridge.dart';
import 'net/net_bridge.dart';

/// 底座层桥（L1 唯一出口）。
class BaseBridge {
  /// 创建桥。
  const BaseBridge({required this.net, required this.disk});

  /// 网络连接门面。
  final NetBridge net;

  /// 硬盘逻辑门面。
  final DiskBridge disk;

  /// 从内核桥表解析底座桥（中枢层的标准取用方式）。
  static BaseBridge of(KernelBridgeRegistry bridges) =>
      bridges.resolve<BaseBridge>(ModuleLayer.base.key);

  @override
  String toString() => 'BaseBridge(net=$net, disk=$disk)';
}

/// 底座层装配模块（`base.layer`）。
///
/// 依赖：`base.net`、`base.disk`（拓扑保证在二者之后注册）。
/// 提供：`base.bridge`。
class BaseLayerModule extends OgLModule {
  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'base.layer',
        layer: ModuleLayer.base,
        version: '0.1.0',
        requires: <String>['base.net', 'base.disk'],
        provides: <String>['base.bridge'],
        description: '底座·层桥装配（网络连接 + 硬盘逻辑 → 单一出口）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final bridge = BaseBridge(
      net: context.di.resolve<NetBridge>(),
      disk: context.di.resolve<DiskBridge>(),
    );
    context.bridges.register(ModuleLayer.base.key, bridge);
    context.diagnostics.info(
      'BASE',
      '底座桥已注册',
      code: 'OGL-BASE-001',
      data: <String, Object?>{'layer': ModuleLayer.base.key},
    );
  }
}

/// 组装 L1 全部模块（供 `main` 一行接入）。
List<OgLModule> baseLayerModules({
  NetModule? net,
  DiskModule? disk,
}) =>
    <OgLModule>[
      net ?? NetModule(),
      disk ?? DiskModule(),
      BaseLayerModule(),
    ];
