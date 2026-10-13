/// 内核级 · 环境自检扩展点（Environment Probe）。
///
/// ## 为什么需要它
/// 内核**不认识**"DNS"、"代理"、"存储"、"时区"这些概念——那是底座的事。
/// 但启动报告又必须覆盖这些东西（否则用户遇到 DNS 污染时，
/// 报告里只有一句"网络失败"，无从定位）。
///
/// 于是内核只提供一个**槽位**：
/// ```
/// 任意层级注册自检项 → 引导完成后内核统一执行 → 结果写进诊断与启动报告
/// ```
/// 内核保持零依赖，底座能力照样可观测。
library;

/// 自检结果。
class KernelProbeResult {
  /// 创建结果。
  const KernelProbeResult({
    required this.ok,
    required this.summary,
    this.detail,
  });

  /// 是否通过。
  final bool ok;

  /// 单行摘要（进启动报告，必须可读）。
  final String summary;

  /// 结构化补充（必须可 JSON 序列化）。
  final Map<String, Object?>? detail;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'summary': summary,
        if (detail != null) 'detail': detail,
      };

  @override
  String toString() => '${ok ? 'OK' : 'FAIL'} $summary';
}

/// 环境自检项。
///
/// 约定：
/// - 实现**必须**自己处理异常，宁可返回 `ok: false` 也不要抛；
/// - 实现**不得**超过几秒（它有超时保护，但超时本身就是失败信号）。
abstract class KernelEnvironmentProbe {
  /// 稳定 ID，形如 `<layer>.<area>.<thing>`（如 `base.net.dns`）。
  String get id;

  /// 人类可读名称（进报告）。
  String get title;

  /// 执行自检。
  Future<KernelProbeResult> run();
}

/// 单次自检的执行报告。
class KernelProbeReport {
  /// 创建报告。
  const KernelProbeReport({
    required this.id,
    required this.title,
    required this.result,
    required this.duration,
  });

  /// 自检项 ID。
  final String id;

  /// 名称。
  final String title;

  /// 结果。
  final KernelProbeResult result;

  /// 耗时。
  final Duration duration;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'ms': duration.inMicroseconds / 1000,
        ...result.toJson(),
      };

  @override
  String toString() => '[$id] ${result.ok ? 'OK' : 'FAIL'} ${result.summary} '
      '(${duration.inMilliseconds}ms)';
}

/// 自检注册表错误。
class KernelProbeError extends Error {
  /// 创建错误。
  KernelProbeError(this.message);

  /// 说明。
  final String message;

  @override
  String toString() => 'KernelProbeError: $message';
}

/// 自检注册表。
class KernelProbeRegistry {
  final List<KernelEnvironmentProbe> _probes = <KernelEnvironmentProbe>[];
  bool _sealed = false;

  /// 是否已封存（封存后禁止再注册，保证启动行为可复现）。
  bool get isSealed => _sealed;

  /// 已注册的自检项（只读）。
  List<KernelEnvironmentProbe> get probes =>
      List<KernelEnvironmentProbe>.unmodifiable(_probes);

  /// 注册自检项；ID 必须唯一。
  void register(KernelEnvironmentProbe probe) {
    if (_sealed) {
      throw KernelProbeError('自检注册表已封存，禁止再注册: ${probe.id}');
    }
    if (_probes.any((KernelEnvironmentProbe item) => item.id == probe.id)) {
      throw KernelProbeError('自检项 ID 重复: ${probe.id}');
    }
    _probes.add(probe);
  }

  /// 移除自检项（仅装配阶段）。
  void remove(String id) {
    if (_sealed) {
      throw KernelProbeError('自检注册表已封存，禁止移除: $id');
    }
    _probes.removeWhere((KernelEnvironmentProbe item) => item.id == id);
  }

  /// 封存注册表（`boot()` 时调用）。
  void seal() {
    _sealed = true;
  }

  /// 执行全部自检。
  ///
  /// **单项失败不阻断其余**：一个探测项抛异常，只会让那一项变成 `ok: false`，
  /// 绝不能因为"DNS 探测失败"就让整个启动自检链中断。
  Future<List<KernelProbeReport>> runAll({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final reports = <KernelProbeReport>[];
    for (final probe in List<KernelEnvironmentProbe>.of(_probes)) {
      final stopwatch = Stopwatch()..start();
      KernelProbeResult result;
      try {
        result = await probe.run().timeout(timeout);
      } catch (error) {
        result = KernelProbeResult(
          ok: false,
          summary: '自检异常：$error',
          detail: <String, Object?>{'error': '$error'},
        );
      }
      stopwatch.stop();
      reports.add(KernelProbeReport(
        id: probe.id,
        title: probe.title,
        result: result,
        duration: stopwatch.elapsed,
      ));
    }
    return reports;
  }

  /// 清空（测试 / 重启场景）。
  void clear() {
    _probes.clear();
    _sealed = false;
  }
}
