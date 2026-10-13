/// OGL 内核契约：层级、模块、状态与内核上下文。
///
/// 本文件只定义"内核认识世界的方式"，不包含任何实现细节。
/// 所有层级模块都必须实现 [OgLModule]，并声明不可变的 [ModuleDescriptor]。
library;

import '../boot/trust_warnings.dart';
import '../bridge_registry.dart';
import '../di.dart';
import '../diagnostics.dart';
import '../environment.dart';

/// 层级标识（L0–L3，见 `docs/NAMING.md（该文件未落地，以源码为准）`）。
enum ModuleLayer {
  /// L0 内核级（总线段）。
  kernel('kernel'),

  /// L1 底座级（网络连接 / 硬盘逻辑）。
  base('base'),

  /// L2 中枢级（API 逻辑 / 交互逻辑）。
  domain('domain'),

  /// L3 消费级（界面 / Mod / 主题包）。
  surface('surface');

  const ModuleLayer(this.key);

  /// 稳定键：用于桥注册、日志标签与引导清单匹配。
  final String key;

  /// 由稳定键解析层级；未知键返回 `null`（容错，不抛异常）。
  static ModuleLayer? fromKey(String? key) {
    for (final layer in ModuleLayer.values) {
      if (layer.key == key) {
        return layer;
      }
    }
    return null;
  }
}

/// 模块生命周期状态。
enum ModuleState {
  /// 已注册（尚未开始注册回调）。
  registered,

  /// 正在执行注册回调。
  registering,

  /// 已就绪（启动完成）。
  ready,

  /// 正在执行启动回调。
  starting,

  /// 正在执行停止回调。
  stopping,

  /// 已停止。
  stopped,

  /// 失败（注册或启动阶段异常）。
  failed;

  /// 是否为终态（终态模块不会再被调度）。
  bool get isFinal => this == ready || this == stopped || this == failed;
}

/// 模块描述符：内核据此构建依赖图、对照引导清单并输出诊断报告。
///
/// 该对象必须稳定：模块 ID、依赖与能力声明不允许在运行时变化。
class ModuleDescriptor {
  /// 创建描述符。
  const ModuleDescriptor({
    required this.id,
    required this.layer,
    required this.version,
    this.requires = const <String>[],
    this.provides = const <String>[],
    this.description = '',
  });

  /// 全局唯一模块 ID，命名为 `<layer>.<name>`（如 `base.net`）。
  final String id;

  /// 所属层级。
  final ModuleLayer layer;

  /// 语义化版本。
  final String version;

  /// 依赖的模块 ID 列表（必须早于本模块启动）。
  final List<String> requires;

  /// 对外提供的能力标识列表（用于依赖与装配校验）。
  final List<String> provides;

  /// 人类可读的模块说明（用于诊断报告）。
  final String description;

  /// 描述符是否满足命名规范与字段完整性。
  bool get isWellFormed {
    if (id.isEmpty || version.isEmpty || description.isEmpty) {
      return false;
    }
    if (!id.startsWith('${layer.key}.')) {
      return false;
    }
    return id.length > layer.key.length + 1;
  }

  @override
  String toString() => 'ModuleDescriptor($id@$version, layer=${layer.key}, '
      'requires=$requires, provides=$provides)';
}

/// 内核上下文：模块在注册阶段获得的唯一接线入口（由内核注入）。
///
/// 约定：模块通过 [di] 注册服务、通过 [bridges] 注册本层桥，
/// 绝不允许直接 `new` 其他层的实现（见 `docs/ARCHITECTURE.md（该文件未落地，以源码为准）` 依赖规则）。
class KernelContext {
  /// 创建上下文。
  const KernelContext({
    required this.di,
    required this.diagnostics,
    required this.bridges,
    required this.warnings,
    this.probes,
  });

  /// 类型化依赖容器。
  final KernelDi di;

  /// 诊断中枢（日志 / 阶段耗时 / 模块状态）。
  final KernelDiagnostics diagnostics;

  /// 桥注册表（每层注册且仅注册一座桥）。
  final KernelBridgeRegistry bridges;

  /// 信任告警收集器（装载第三方扩展时必须上报，见 `docs/BOOT.md（该文件未落地，以源码为准）`）。
  final TrustWarningCollector warnings;

  /// 环境自检注册表（可空：内核未传入时为 `null`，模块需容错）。
  ///
  /// 有了它，各层就能在**注册阶段**把自己的自检项挂上去
  /// （如底座的 DNS 自检、中枢的设备信息自检），而内核仍然不认识这些概念。
  final KernelProbeRegistry? probes;
}

/// OGL 模块契约：所有层级模块的统一生命周期入口。
abstract class OgLModule {
  /// 模块描述符（必须稳定）。
  ModuleDescriptor get descriptor;

  /// 注册阶段：注册服务与桥。
  ///
  /// 约定：禁止耗时操作、禁止网络与磁盘 IO；异常将终止启动流程。
  Future<void> onRegister(KernelContext context) async {}

  /// 启动阶段：异步初始化（按依赖拓扑顺序调用）。
  Future<void> onStart() async {}

  /// 停止阶段：按启动逆序调用，且必须幂等。
  Future<void> onStop() async {}
}
