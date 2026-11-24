/// L1 底座级 · 网络运行时门禁采集。
///
/// [NetGuard] **只做采集与记账**：它从 [NetObserver] 的快照（以及可选的
/// [DnsService] 降级状态）里读出「网络正在变差」的信号，写进内核诊断中枢，
/// 由上层（通知中心 + 日志报警）负责呈现。
///
/// ## 边界（严格分层）
/// * 纯 L1：只 import kernel 契约 + 同层（`net_dns.dart`）。
/// * **不新增 kernel 文件**：kernel 只是汇总点（KernelDiagnostics）。
/// * 不做决策、不改传输行为、不自愈——它只负责「把降级说出来」。
///
/// ## 为什么要有冷却去重
/// 网络抖动时同一个门禁可能连续命中；每帧都报一次会把通知中心刷爆，
/// 反而淹没真正重要的信息。因此同一门禁在冷却期（默认 60s）内只上报一次，
/// 冷却结束后若仍处于异常状态会再次上报。
library;

import '../../kernel/diagnostics.dart';
import 'net_dns.dart';
import 'net_types.dart';

/// 网络运行时门禁采集器。
///
/// 门禁编号与含义：
/// * `OGL-NET-G01` —— 失败率过高
/// * `OGL-NET-G02` —— 重试风暴
/// * `OGL-NET-G03` —— 镜像切换突增
/// * `OGL-NET-G04` —— DNS 降级（自定义 DNS 回落 / 平台不支持自定义 DNS）
class NetGuard {
  /// 创建采集器。
  ///
  /// 所有阈值都可注入，便于测试与按机型调参；默认值为生产经验值。
  NetGuard({
    this.failureRateThreshold = 0.30,
    this.minRequestsForRate = 10,
    this.retryRatioThreshold = 0.50,
    this.retryBurstThreshold = 20,
    this.mirrorSwitchThreshold = 5,
    this.cooldown = const Duration(seconds: 60),
  });

  /// 失败率阈值（失败 / 请求）。超过即触发 `OGL-NET-G01`。
  final double failureRateThreshold;

  /// 计算失败率所需的最小请求数（样本太小时不判失败）。
  final int minRequestsForRate;

  /// 重试占比阈值（重试 / 请求）。超过即触发 `OGL-NET-G02`。
  final double retryRatioThreshold;

  /// 单个巡检窗口内重试次数绝对值阈值。超过即触发 `OGL-NET-G02`。
  final int retryBurstThreshold;

  /// 单个巡检窗口内镜像切换次数阈值。超过即触发 `OGL-NET-G03`。
  final int mirrorSwitchThreshold;

  /// 同一门禁的冷却期（冷却期内不重复上报）。
  final Duration cooldown;

  KernelDiagnostics? _diagnostics;
  NetObserver? _observer;
  DnsService? _dns;

  /// 上一次巡检时的累计计数（用于算窗口增量）。
  NetStats? _last;

  /// 每个门禁的最近一次上报时间（门禁码 → 时间）。
  final Map<String, DateTime> _lastReport = <String, DateTime>{};

  /// 已知门禁码（供状态刷新用）。
  static const List<String> _knownCodes = <String>[
    'OGL-NET-G01',
    'OGL-NET-G02',
    'OGL-NET-G03',
    'OGL-NET-G04',
  ];

  /// 每个门禁当前是否处于异常状态。
  final Map<String, bool> _active = <String, bool>{};

  /// 绑定诊断中枢与观测器。
  ///
  /// [dns] 可选：给了就能额外采集 DNS 降级信号（`OGL-NET-G04`）。
  void attach(
    KernelDiagnostics diagnostics,
    NetObserver observer, {
    DnsService? dns,
  }) {
    _diagnostics = diagnostics;
    _observer = observer;
    _dns = dns;
  }

  /// 是否已绑定。
  bool get isAttached => _diagnostics != null && _observer != null;

  /// 巡检一次网络运行时状态，命中门禁则写诊断。
  ///
  /// 幂等：同一门禁在冷却期内不重复上报。
  Future<void> check() async {
    final KernelDiagnostics? diagnostics = _diagnostics;
    final NetObserver? observer = _observer;
    if (diagnostics == null || observer == null) {
      return;
    }
    final NetStats now = observer.snapshot();
    final NetStats prev = _last ?? now;
    _last = now;

    // 本轮先清空门禁状态：只有本轮仍然异常的才会留在 [_active] 里。
    for (final String code in _knownCodes) {
      _active[code] = false;
    }

    final int dRequests = now.requests - prev.requests;
    final int dFailures = now.failures - prev.failures;
    final int dRetries = now.retries - prev.retries;
    final int dMirrors = now.mirrorSwitches - prev.mirrorSwitches;

    // ── G01 失败率过高 ─────────────────────────────────────────────
    if (dRequests >= minRequestsForRate) {
      final double rate = dFailures / dRequests;
      if (rate > failureRateThreshold) {
        _report(
          diagnostics,
          'OGL-NET-G01',
          '网络失败率过高：${(rate * 100).toStringAsFixed(1)}%',
          <String, Object?>{
            'failureRate': rate,
            'threshold': failureRateThreshold,
            'windowRequests': dRequests,
            'windowFailures': dFailures,
            'totalRequests': now.requests,
            'totalFailures': now.failures,
          },
        );
      }
    }

    // ── G02 重试风暴 ───────────────────────────────────────────────
    final double retryRatio = dRequests > 0 ? dRetries / dRequests : 0.0;
    if (dRetries >= retryBurstThreshold ||
        (dRequests >= minRequestsForRate && retryRatio > retryRatioThreshold)) {
      _report(
        diagnostics,
        'OGL-NET-G02',
        '网络重试风暴：窗口重试 $dRetries 次',
        <String, Object?>{
          'retries': dRetries,
          'retryRatio': retryRatio,
          'ratioThreshold': retryRatioThreshold,
          'burstThreshold': retryBurstThreshold,
          'windowRequests': dRequests,
          'totalRetries': now.retries,
        },
      );
    }

    // ── G03 镜像切换突增 ───────────────────────────────────────────
    if (dMirrors >= mirrorSwitchThreshold) {
      _report(
        diagnostics,
        'OGL-NET-G03',
        '镜像切换过于频繁：窗口切换 $dMirrors 次',
        <String, Object?>{
          'mirrorSwitches': dMirrors,
          'threshold': mirrorSwitchThreshold,
          'windowRequests': dRequests,
          'totalMirrorSwitches': now.mirrorSwitches,
        },
      );
    }

    // ── G04 DNS 降级 ───────────────────────────────────────────────
    final Map<String, Object?>? dnsIssue = _dnsDegradation();
    if (dnsIssue != null) {
      _report(
        diagnostics,
        'OGL-NET-G04',
        'DNS 降级：${dnsIssue['reason']}',
        dnsIssue,
      );
    }
  }

  /// 检测 DNS 降级状态；无降级返回 `null`。
  Map<String, Object?>? _dnsDegradation() {
    final DnsService? dns = _dns;
    if (dns == null) {
      return null;
    }
    final String? via = dns.lastResolvedVia;
    if (via != null && via.contains('fallback')) {
      return <String, Object?>{
        'reason': '自定义 DNS 已回退到系统解析',
        'via': via,
        'degraded': true,
      };
    }
    if (!dns.supportsCustomDns && dns.policy.mode != NetDnsMode.system) {
      return <String, Object?>{
        'reason': '当前平台不支持自定义 DNS（浏览器限制）',
        'via': via,
        'degraded': true,
      };
    }
    return null;
  }

  /// 上报一次门禁命中（带冷却去重）。
  void _report(
    KernelDiagnostics diagnostics,
    String code,
    String message,
    Map<String, Object?> data,
  ) {
    _active[code] = true;
    final DateTime now = DateTime.now();
    final DateTime? last = _lastReport[code];
    if (last != null && now.difference(last) < cooldown) {
      return;
    }
    _lastReport[code] = now;
    diagnostics.warn('NET', message, code: code, data: data);
  }

  /// 当前门禁状态快照（供高层经层桥读取）。
  ///
  /// 结构：
  /// ```json
  /// {
  ///   "attached": true,
  ///   "degraded": true,
  ///   "gates": {"OGL-NET-G01": true},
  ///   "stats": {"requests": 10, "failures": 1, ...},
  ///   "dns": {"via": "system(fallback)", "degraded": true}
  /// }
  /// ```
  Map<String, Object?> snapshot() {
    final NetObserver? observer = _observer;
    final NetStats stats = observer?.snapshot() ?? const NetStats();
    final Map<String, Object?> gates = <String, Object?>{
      for (final MapEntry<String, bool> entry in _active.entries)
        entry.key: entry.value,
    };
    return <String, Object?>{
      'attached': isAttached,
      'degraded': _active.values.any((bool value) => value),
      'gates': gates,
      'stats': stats.toJson(),
      'dns': <String, Object?>{
        'via': _dns?.lastResolvedVia,
        'degraded': _dnsDegradation() != null,
      },
      'cooldownSeconds': cooldown.inSeconds,
    };
  }
}
