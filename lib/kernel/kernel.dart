/// OGL 内核门面：把"引导、装配、生命周期、桥发现、诊断"串成一条启动链。
///
/// 启动链：
/// ```
/// BootLoader.run()         引导（签名 / 指纹 / 信任策略）
///   → 过滤被排除模块      安全模式支持（官方模块校验失败不拖垮整个应用）
///   → ModuleBus.register  模块注册与依赖图校验
///   → ModuleBus.seal      总线封存
///   → Lifecycle.registerAll 注册阶段（接线：DI / 桥）
///   → Di.seal + Bridges.seal 容器封存（杜绝运行期偷偷注册）
///   → Lifecycle.startAll  启动阶段（按依赖拓扑顺序）
///   → KernelReport        就绪上报（UI 安全中心 / 审计）
/// ```
library;

import 'boot/boot_loader.dart';
import 'boot/boot_manifest.dart';
import 'boot/trust_policy.dart';
import 'boot/trust_warnings.dart';
import 'bridge_registry.dart';
import 'contract/module.dart';
import 'di.dart';
import 'diagnostics.dart';
import 'environment.dart';
import 'lifecycle.dart';
import 'module_bus.dart';

/// 内核启动失败（引导被拒绝，或模块注册/启动异常）。
class KernelBootException implements Exception {
  /// 创建异常。
  KernelBootException(this.message, {this.cause});

  /// 失败说明。
  final String message;

  /// 原始异常（模块启动失败时携带）。
  final Object? cause;

  @override
  String toString() =>
      'KernelBootException: $message${cause == null ? '' : '（cause=$cause）'}';
}

/// 内核启动报告（Stage 4 就绪上报的数据源）。
class KernelReport {
  /// 创建报告。
  const KernelReport({
    required this.generatedAt,
    required this.appVersion,
    required this.safeMode,
    required this.bootSummary,
    required this.stages,
    required this.moduleStates,
    required this.moduleGraph,
    required this.bridges,
    required this.services,
    required this.trustWarnings,
    required this.logTail,
  });

  /// 生成时间。
  final DateTime generatedAt;

  /// 应用版本。
  final String appVersion;

  /// 是否处于安全模式。
  final bool safeMode;

  /// 引导摘要（单行）。
  final String bootSummary;

  /// 引导阶段结果。
  final List<BootStage> stages;

  /// 模块状态（`模块 ID → 状态名`）。
  final Map<String, String> moduleStates;

  /// 依赖图（文本）。
  final String moduleGraph;

  /// 已注册桥的层级键。
  final List<String> bridges;

  /// 已注册服务键。
  final List<String> services;

  /// 引导期信任告警（UI **必须**触达）。
  final List<BootTrustWarning> trustWarnings;

  /// 日志尾部。
  final List<KernelLogEntry> logTail;

  /// 序列化（审计导出 / 安全中心展示）。
  Map<String, Object?> toJson() => <String, Object?>{
        'generatedAt': generatedAt.toIso8601String(),
        'appVersion': appVersion,
        'safeMode': safeMode,
        'boot': bootSummary,
        'stages': stages.map((stage) => stage.toJson()).toList(),
        'moduleStates': moduleStates,
        'moduleGraph': moduleGraph,
        'bridges': bridges,
        'services': services,
        'trustWarnings':
            trustWarnings.map((warning) => warning.toJson()).toList(),
        'logTail': logTail.map((entry) => entry.toJson()).toList(),
      };

  @override
  String toString() =>
      'KernelReport(appVersion=$appVersion, safeMode=$safeMode, '
      'modules=${moduleStates.length}, bridges=$bridges, '
      'warnings=${trustWarnings.length})';
}

/// OGL 内核（总线段）。
class OgLKernel {
  /// 创建内核。
  OgLKernel({
    required this.diagnostics,
    required this.bootLoader,
    this.appVersion = '0.0.0',
  });

  /// 诊断中枢。
  final KernelDiagnostics diagnostics;

  /// 启动层。
  final BootLoader bootLoader;

  /// 应用版本（进入报告）。
  final String appVersion;

  /// 依赖容器。
  final KernelDi di = KernelDi();

  /// 桥注册表。
  final KernelBridgeRegistry bridges = KernelBridgeRegistry();

  /// 信任告警收集器。
  final TrustWarningCollector warnings = TrustWarningCollector();

  /// 环境自检注册表。
  ///
  /// 内核不认识 DNS / 代理 / 存储——各层级把自检项注册到这里，
  /// 由 [runProbes] 统一执行（见 `environment.dart`）。
  final KernelProbeRegistry probes = KernelProbeRegistry();

  /// 模块总线。
  late final KernelModuleBus bus = KernelModuleBus(
    di: di,
    diagnostics: diagnostics,
    bridges: bridges,
  );

  /// 生命周期编排。
  late final KernelLifecycle lifecycle =
      KernelLifecycle(diagnostics: diagnostics);

  BootResult? _bootResult;
  KernelReport? _report;

  /// 引导结果（未启动时为 `null`）。
  BootResult? get bootResult => _bootResult;

  /// 启动报告（未启动时为 `null`）。
  KernelReport? get report => _report;

  /// 是否处于安全模式。
  bool get safeMode => _bootResult?.safeMode ?? false;

  /// 是否已启动。
  bool get isRunning => _report != null;

  /// 启动内核：引导 → 装配 → 注册 → 封存 → 启动 → 报告。
  ///
  /// 抛 [KernelBootException]：
  /// - 引导被拒绝（清单缺失/签名失败/schema 不支持）；
  /// - 模块注册或启动失败（已完成模块会先回滚）。
  Future<KernelReport> boot(List<OgLModule> modules) async {
    if (_report != null) {
      throw KernelBootException('内核已启动，禁止重复 boot()');
    }

    final bootResult = await bootLoader.run();
    _bootResult = bootResult;
    if (bootResult.isRefused) {
      throw KernelBootException(bootResult.failureReason ?? '引导被拒绝');
    }

    // 安全模式：被排除的官方模块不参与装配（由引导层裁决）。
    final excluded = bootResult.excludedModules;
    for (final module in modules) {
      final id = module.descriptor.id;
      if (excluded.contains(id)) {
        diagnostics.warn(
          'KERNEL',
          '安全模式：模块被排除',
          code: 'OGL-KERNEL-102',
          data: <String, Object?>{'module': id},
        );
        continue;
      }
      bus.register(module);
    }
    bus.seal();

    // ★ 5.0（探针发现）：**清单 ↔ 运行期模块**交叉校验。
    //   清单声明了某模块、装配时却没提供它 —— 可能是构建裁剪或接线遗漏。
    //   这类不一致以前会静默通过（应用"看起来正常"，实际少了一整层能力），
    //   现在必须留痕：诊断 warn（带事件码）+ 引导信任告警。
    final Set<String> declared = <String>{
      for (final BootModuleEntry entry
          in bootResult.manifest?.modules ?? const <BootModuleEntry>[])
        entry.id,
    };
    final Set<String> provided = <String>{
      for (final OgLModule module in modules) module.descriptor.id,
    };
    for (final String missing in declared.difference(provided)) {
      diagnostics.warn(
        'KERNEL',
        '清单声明的模块未被提供（装配缺失）：$missing',
        code: BootWarningCodes.manifestModuleNotProvided,
        data: <String, Object?>{'module': missing},
      );
      warnings.report(
        code: BootWarningCodes.manifestModuleNotProvided,
        subject: 'module:$missing',
        severity: TrustSeverity.warn,
        message: '引导清单声明了 $missing，但运行期未提供该模块（装配缺失）。',
        data: <String, Object?>{
          'module': missing,
          'declared': declared.length,
          'provided': provided.length,
        },
      );
    }

    final ordered = bus.resolveOrder();
    final context = KernelContext(
      di: di,
      diagnostics: diagnostics,
      bridges: bridges,
      warnings: warnings,
      probes: probes,
    );

    await lifecycle.registerAll(ordered, context);
    di.seal();
    bridges.seal();
    probes.seal();
    await lifecycle.startAll(ordered);

    final report = KernelReport(
      generatedAt: DateTime.now(),
      appVersion: appVersion,
      safeMode: bootResult.safeMode,
      bootSummary: bootResult.toSummary(),
      stages: bootResult.stages,
      moduleStates: lifecycle.states,
      moduleGraph: bus.toDependencyGraph(),
      bridges: bridges.snapshot.keys.toList()..sort(),
      services: di.describe(),
      trustWarnings: bootResult.trustWarnings,
      logTail: diagnostics.logTail,
    );
    _report = report;
    diagnostics.info(
      'KERNEL',
      '内核就绪',
      code: 'OGL-KERNEL-001',
      data: <String, Object?>{'modules': ordered.length},
    );
    return report;
  }

  /// 停止内核（逆序、幂等）。
  Future<void> shutdown() async {
    await lifecycle.stopAll();
    _report = null;
    diagnostics.info('KERNEL', '内核已停止', code: 'OGL-KERNEL-002');
  }

  /// 执行全部环境自检并写入诊断（引导完成后调用）。
  ///
  /// 之所以**不在 `boot()` 里自动执行**：自检会发起真实网络/磁盘动作，
  /// 把它塞进启动关键路径会拖慢冷启动，也会让启动结果依赖外部环境。
  /// 由装配层在合适的时机（首帧之后 / 用户点"诊断"）显式调用。
  ///
  /// **单项失败不影响内核状态**：自检只产出报告，不改生命周期。
  Future<List<KernelProbeReport>> runProbes({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final reports = await probes.runAll(timeout: timeout);
    for (final report in reports) {
      if (report.result.ok) {
        diagnostics.info(
          'PROBE',
          '${report.title}：${report.result.summary}',
          code: 'OGL-PROBE-001',
          data: report.toJson(),
        );
      } else {
        diagnostics.warn(
          'PROBE',
          '${report.title}：${report.result.summary}',
          code: 'OGL-PROBE-101',
          data: report.toJson(),
        );
      }
    }
    return reports;
  }

  /// 对扩展种类作出信任裁决（消费层装载 Mod / 主题时调用）。
  TrustDecision evaluateExtension(ExtensionKind kind) =>
      bootLoader.evaluateExtension(kind);
}
