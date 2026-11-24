/// L1 底座级 · 硬盘运行时门禁（把"磁盘开始变坏"变成可见事实）。
///
/// ## 为什么必须有它
/// 硬盘子模块（cache / journal / draft）各自有 [attachDiagnostics]，
/// 失败会**逐条**进诊断中枢；但没有任何一处回答
/// "**硬盘整体现在处于什么状态**"。
/// 于是：
/// - 写失败一次又一次，日志里躺着，用户什么也没看见；
/// - 日志落盘本身挂了（磁盘写满 / 权限被收回），
///   于是"失败的原因"也跟着没了——**最需要证据的时候没有证据**；
/// - 提交日志（journal）pending 越积越多，
///   用户看到的只是"迟迟不成功"，不知道是硬盘撑不住了。
///
/// 本类把这些信号**汇总成一个门禁状态**：
///
/// | 门禁码 | 采集信号 |
/// |---|---|
/// | `OGL-DISK-G01` | 日志落盘不可用（[OgLLogFile.isEnabled] / `lastError`） |
/// | `OGL-DISK-G02` | 写失败累计超阈值（cache 写入失败 error 计数） |
/// | `OGL-DISK-G03` | 提交日志 pending 积压超阈值 |
///
/// ## 自激防护（重要）
/// [DiskGuard] 自己就是 [KernelLogSink]：它写的告警会**回到自己的** [onLog]。
/// 若不防护，一次告警就会把自己记成一次失败，计数自增、告警自激、
/// 最终无限刷屏。两道防线：
/// 1. **代码前缀过滤**：自查日志一律带 `OGL-DISK-G` 前缀，进入 [onLog] 直接丢弃；
/// 2. **重入闸门**：[onLog] 抛出前检查 `_emitting`，自身写日志期间不计数。
library;

import '../../kernel/diagnostics.dart';
import '../../kernel/log/og_l_log_file.dart';
import 'disk_journal.dart';

/// 硬盘运行时门禁（L1 内部件；上层经层桥读取 [snapshot]）。
class DiskGuard implements KernelLogSink {
  /// 创建门禁。
  ///
  /// [writeFailureThreshold] 次写失败即视为降级；
  /// [pendingThreshold] 条 pending 即视为积压；
  /// [cooldown] 是同一门禁码的重复告警冷却时间（防止刷屏）。
  DiskGuard({
    this.writeFailureThreshold = degradedWriteFailures,
    this.pendingThreshold = 10,
    this.cooldown = const Duration(seconds: 60),
  });

  /// 写失败累计阈值。
  final int writeFailureThreshold;

  /// journal pending 积压阈值。
  final int pendingThreshold;

  /// 同一门禁码的重复告警冷却时间。
  final Duration cooldown;

  /// 写失败累计达此值即视为降级门禁。
  static const int degradedWriteFailures = 3;

  /// 自查日志的事件码前缀（`OGL-DISK-G` 开头）：进入 [onLog] 一律丢弃，
  /// 防止"门禁的告警被自己当成失败"而自激。
  static const String selfCodePrefix = 'OGL-DISK-G';

  KernelDiagnostics? _diagnostics;
  WriteJournal? _journal;

  bool _emitting = false;
  int _writeFailures = 0;
  int _warnCount = 0;
  int _errorCount = 0;
  int _journalPending = -1;
  DateTime? _checkedAt;
  final Map<String, DateTime> _lastEmit = <String, DateTime>{};
  final List<String> _activeIssues = <String>[];

  /// 写失败累计次数。
  int get writeFailures => _writeFailures;

  /// 磁盘相关告警（warn）累计次数。
  int get warnCount => _warnCount;

  /// 磁盘相关错误（error）累计次数。
  int get errorCount => _errorCount;

  /// 最近一次巡检时间（未巡检为 `null`）。
  DateTime? get checkedAt => _checkedAt;

  /// 当前处于报警状态的门禁码（空列表 = 健康）。
  List<String> get activeIssues => List<String>.unmodifiable(_activeIssues);

  /// 是否健康（最近一次巡检无门禁报警）。
  bool get isHealthy => _activeIssues.isEmpty;

  /// 注册到诊断中枢：此后硬盘相关日志都会流经 [onLog]。
  void attach(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
    diagnostics.addSink(this);
  }

  /// 绑定提交日志（用于统计 pending 积压）。
  void attachJournal(WriteJournal journal) {
    _journal = journal;
  }

  /// 接收一条日志（只统计**硬盘相关**的 warn / error）。
  ///
  /// 磁盘相关的判定：标签属于 `DISK` / `CACHE` / `JOURNAL` / `DRAFT`，
  /// 或事件码以 `OGL-DISK` / `OGL-CONS` / `OGL-JOURNAL` / `OGL-DRAFT` 开头。
  @override
  void onLog(KernelLogEntry entry) {
    // ① 自查日志回环：直接丢弃（这是**防自激的第一道防线**）。
    final String? code = entry.code;
    if (entry.tag == 'DISK' &&
        code != null &&
        code.startsWith(selfCodePrefix)) {
      return;
    }
    // ② 重入闸门：自身写日志期间不计数（第二道防线）。
    if (_emitting) {
      return;
    }
    if (!_isDiskRelated(entry)) {
      return;
    }
    if (entry.level == KernelLogLevel.warn) {
      _warnCount++;
    } else if (entry.level == KernelLogLevel.error) {
      _errorCount++;
      if (_isWriteFailure(entry)) {
        _writeFailures++;
      }
    }
  }

  /// 巡检：把硬盘运行时降级信号写入诊断中枢（warn + `OGL-DISK-G0x`）。
  ///
  /// 幂等且**有冷却**：同一门禁码在 [cooldown] 内只报一次。
  Future<void> check() async {
    final KernelDiagnostics? diagnostics = _diagnostics;
    _checkedAt = DateTime.now();

    // ── 信号 1：日志落盘不可用（证据链本身断了） ──────────────────
    final bool logFileEnabled = OgLLogFile.isEnabled;
    final String? logFileError = OgLLogFile.lastError;

    // ── 信号 2：journal pending 积压 ─────────────────────────────
    int pending = _journalPending;
    if (_journal != null) {
      try {
        pending = await _journal!.pendingCount();
      } catch (error) {
        pending = -1;
        _emit(
          diagnostics,
          'OGL-DISK-G04',
          '提交日志 pending 统计失败：$error',
          <String, Object?>{'error': '$error'},
        );
      }
    }
    _journalPending = pending;

    final List<String> issues = <String>[];

    if (!logFileEnabled && logFileError != null) {
      issues.add('OGL-DISK-G01');
      _emit(
        diagnostics,
        'OGL-DISK-G01',
        '日志落盘不可用：硬盘故障排查失去证据链',
        <String, Object?>{
          'lastError': logFileError,
          'tried': OgLLogFile.triedDirectories,
        },
      );
    }

    if (_writeFailures >= writeFailureThreshold) {
      issues.add('OGL-DISK-G02');
      _emit(
        diagnostics,
        'OGL-DISK-G02',
        '写失败累计超阈值：$_writeFailures 次（阈值 $writeFailureThreshold）',
        <String, Object?>{
          'writeFailures': _writeFailures,
          'threshold': writeFailureThreshold,
        },
      );
    }

    if (pending >= pendingThreshold) {
      issues.add('OGL-DISK-G03');
      _emit(
        diagnostics,
        'OGL-DISK-G03',
        '提交日志积压超阈值：$pending 条（阈值 $pendingThreshold）',
        <String, Object?>{
          'pending': pending,
          'threshold': pendingThreshold,
        },
      );
    }

    _activeIssues
      ..clear()
      ..addAll(issues);
  }

  /// 门禁状态快照（上层经层桥读取；必须可 JSON 序列化）。
  Map<String, Object?> snapshot() => <String, Object?>{
        'healthy': isHealthy,
        'issues': List<String>.of(_activeIssues),
        'writeFailures': _writeFailures,
        'warnCount': _warnCount,
        'errorCount': _errorCount,
        'journalPending': _journalPending,
        'logFileEnabled': OgLLogFile.isEnabled,
        'logFileError': OgLLogFile.lastError,
        'writeFailureThreshold': writeFailureThreshold,
        'pendingThreshold': pendingThreshold,
        'checkedAt': _checkedAt?.toIso8601String(),
      };

  /// 写一条门禁告警（带 60s 冷却，且**不会**被自己计数）。
  void _emit(
    KernelDiagnostics? diagnostics,
    String code,
    String message,
    Map<String, Object?> data,
  ) {
    if (diagnostics == null) {
      return;
    }
    final DateTime now = DateTime.now();
    final DateTime? last = _lastEmit[code];
    if (last != null && now.difference(last) < cooldown) {
      return;
    }
    _lastEmit[code] = now;
    _emitting = true;
    try {
      diagnostics.warn('DISK', message, code: code, data: data);
    } finally {
      _emitting = false;
    }
  }

  static bool _isDiskRelated(KernelLogEntry entry) {
    const Set<String> tags = <String>{'DISK', 'CACHE', 'JOURNAL', 'DRAFT'};
    if (tags.contains(entry.tag)) {
      return true;
    }
    final String? code = entry.code;
    if (code == null) {
      return false;
    }
    return code.startsWith('OGL-DISK') ||
        code.startsWith('OGL-CONS') ||
        code.startsWith('OGL-JOURNAL') ||
        code.startsWith('OGL-DRAFT');
  }

  static bool _isWriteFailure(KernelLogEntry entry) {
    if (entry.level != KernelLogLevel.error) {
      return false;
    }
    final String? code = entry.code;
    if (code != null && code.startsWith('OGL-CONS')) {
      return true;
    }
    return entry.tag == 'CACHE' || entry.tag == 'DISK';
  }
}
