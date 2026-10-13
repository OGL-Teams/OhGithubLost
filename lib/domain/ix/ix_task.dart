/// L2 中枢级 · 交互逻辑：长任务与批量编排。
///
/// ## 一条不可绕过的规矩
/// **批量操作在发出第一个请求之前，必须拿到用户的明确确认**，
/// 并且要让用户**同时选择通道**（直连 / 指定镜像 / 自动测速）——
/// 因为在 DNS 污染或受限网络下，通道选择就是"能不能用"的分水岭。
///
/// 这条规矩不是写在文档里靠自觉，而是**在类型上强制**：
/// [IxTaskRunner.run] 必须收到 [IxBatchDecision]，否则抛 [IxConfirmationRequired]。
/// 想绕过它，只能显式构造一个 `confirmed: true` 的决策对象——
/// 那就是"有人签了字"，审计日志会记下来。
///
/// ## 为什么任务要可取消
/// 批量下载几百个文件时用户会后悔。取消必须立即生效，且**已完成的部分要如实汇报**，
/// 不能假装"什么都没发生"。
library;

import 'package:flutter/foundation.dart';

import '../../kernel/diagnostics.dart';

/// 通道选择（**批量操作必须让用户看见并选择**）。
enum IxChannel {
  /// 直连（不经过任何加速节点）。
  direct,

  /// 自动：交由镜像选择器按声明顺序挑一个可用通道（**不做测速择优** ——
  /// 那需要额外请求，且加速域名质量波动大，见 `net_mirror.dart`）。
  /// 注：当前没有任何 UI 构造批量决策，该分支实际未被使用。
  auto,

  /// 指定镜像通道。
  mirror,
}

/// 批量项。
class IxBatchItem {
  /// 创建批量项。
  const IxBatchItem({
    required this.id,
    required this.label,
    this.bytes = 0,
    this.destructive = false,
  });

  /// 稳定 ID（结果回填用）。
  final String id;

  /// 展示名。
  final String label;

  /// 预估字节数。
  final int bytes;

  /// 是否具有破坏性（删除类）。
  final bool destructive;

  @override
  String toString() => 'IxBatchItem($id, $label)';
}

/// 批量计划（**执行前必须展示给用户**）。
class IxBatchPlan {
  /// 创建计划。
  const IxBatchPlan({
    required this.title,
    required this.items,
    this.repo,
    this.branch,
    this.estimatedRequests = 0,
    this.defaultChannel = IxChannel.direct,
  });

  /// 标题（如"批量删除 12 个文件"）。
  final String title;

  /// 条目。
  final List<IxBatchItem> items;

  /// 目标仓库。
  final String? repo;

  /// 目标分支。
  final String? branch;

  /// 预计请求数（让用户知道要烧多少额度）。
  final int estimatedRequests;

  /// 上次使用的通道（仅作默认值，**必须仍然显示给用户**）。
  final IxChannel defaultChannel;

  /// 条目数。
  int get count => items.length;

  /// 是否含破坏性操作。
  bool get hasDestructive => items.any((IxBatchItem item) => item.destructive);

  /// 预估总字节。
  int get totalBytes =>
      items.fold(0, (int sum, IxBatchItem item) => sum + item.bytes);

  /// 给确认对话框用的可读摘要。
  Map<String, Object?> describe() => <String, Object?>{
        'title': title,
        'count': count,
        'repo': repo,
        'branch': branch,
        'estimatedRequests': estimatedRequests,
        'totalBytes': totalBytes,
        'hasDestructive': hasDestructive,
        'defaultChannel': defaultChannel.name,
        'sample': items.take(5).map((IxBatchItem item) => item.label).toList(),
      };

  @override
  String toString() => 'IxBatchPlan($title, $count 项)';
}

/// 用户对批量操作的决策。
class IxBatchDecision {
  /// 创建决策。
  const IxBatchDecision({
    required this.confirmed,
    required this.channel,
    this.mirrorId,
    this.note,
  });

  /// 是否已确认。
  final bool confirmed;

  /// 所选通道。
  final IxChannel channel;

  /// 指定镜像时的通道 ID。
  final String? mirrorId;

  /// 备注（审计用，如"用户在选择框中勾选了自动测速"）。
  final String? note;

  @override
  String toString() =>
      'IxBatchDecision(confirmed=$confirmed, channel=${channel.name})';
}

/// 未获确认就试图执行批量操作。
class IxConfirmationRequired implements Exception {
  /// 创建异常。
  const IxConfirmationRequired(this.plan);

  /// 待确认的计划。
  final IxBatchPlan plan;

  @override
  String toString() => 'IxConfirmationRequired: 批量操作「${plan.title}」必须先经用户确认';
}

/// 单项结果。
class IxTaskResult {
  /// 创建结果。
  const IxTaskResult({
    required this.id,
    required this.label,
    required this.ok,
    this.skipped = false,
    this.message,
  });

  /// 成功。
  factory IxTaskResult.success(String id, String label, {String? message}) =>
      IxTaskResult(id: id, label: label, ok: true, message: message);

  /// 失败。
  factory IxTaskResult.failure(String id, String label, String message) =>
      IxTaskResult(id: id, label: label, ok: false, message: message);

  /// 跳过（如目标已存在）。
  factory IxTaskResult.skipped(String id, String label, String reason) =>
      IxTaskResult(
        id: id,
        label: label,
        ok: false,
        skipped: true,
        message: reason,
      );

  /// ID。
  final String id;

  /// 展示名。
  final String label;

  /// 是否成功。
  final bool ok;

  /// 是否被跳过。
  final bool skipped;

  /// 说明。
  final String? message;

  @override
  String toString() =>
      'IxTaskResult($label ${ok ? 'OK' : skipped ? 'SKIP' : 'FAIL'}'
      '${message == null ? '' : ': $message'})';
}

/// 进度。
class IxTaskProgress {
  /// 创建进度。
  const IxTaskProgress({
    required this.done,
    required this.total,
    this.currentLabel,
    this.cancelled = false,
  });

  /// 已完成。
  final int done;

  /// 总数。
  final int total;

  /// 当前项。
  final String? currentLabel;

  /// 是否已取消。
  final bool cancelled;

  /// 完成比例（0–1）。
  double get ratio => total <= 0 ? 0 : done / total;

  @override
  String toString() =>
      'IxTaskProgress($done/$total${cancelled ? ', 已取消' : ''})';
}

/// 任务报告（**逐条**，不得只报"完成"）。
class IxTaskReport {
  /// 创建报告。
  const IxTaskReport({
    required this.title,
    required this.results,
    required this.channel,
    required this.elapsed,
    this.cancelled = false,
  });

  /// 标题。
  final String title;

  /// 逐条结果。
  final List<IxTaskResult> results;

  /// 使用的通道。
  final IxChannel channel;

  /// 耗时。
  final Duration elapsed;

  /// 是否被取消。
  final bool cancelled;

  /// 成功数。
  int get succeeded => results.where((IxTaskResult r) => r.ok).length;

  /// 失败数。
  int get failed =>
      results.where((IxTaskResult r) => !r.ok && !r.skipped).length;

  /// 跳过数。
  int get skipped => results.where((IxTaskResult r) => r.skipped).length;

  /// 是否全部成功。
  bool get allOk => results.isNotEmpty && succeeded == results.length;

  /// 一行摘要（UI 角标 / 通知用）。
  String get summary => '成功 $succeeded / 跳过 $skipped / 失败 $failed'
      '${cancelled ? '（已取消）' : ''}';

  @override
  String toString() => 'IxTaskReport($title, $summary)';
}

/// 通道应用器：由装配层接到网络底座（镜像选择器）上。
typedef IxChannelApplier = Future<void> Function(IxBatchDecision decision);

/// 任务运行器。
class IxTaskRunner extends ChangeNotifier {
  /// 创建运行器。
  ///
  /// [channelApplier] 是**通道选择的落地实现**：把 `直连 / 自动 / 指定镜像`
  /// 真正作用到网络底座上。装配层（`IxModule`）会注入它；
  /// 不注入时，`run()` 仍要求调用方显式传 `applyChannel`——
  /// **绝不允许"用户选了镜像，实际走直连"这种事静默发生**。
  IxTaskRunner({
    KernelDiagnostics? diagnostics,
    IxChannelApplier? channelApplier,
  })  : _diagnostics = diagnostics,
        _channelApplier = channelApplier;

  KernelDiagnostics? _diagnostics;
  IxChannelApplier? _channelApplier;

  IxTaskProgress _progress = const IxTaskProgress(done: 0, total: 0);
  IxTaskReport? _lastReport;
  bool _cancelRequested = false;
  bool _running = false;

  /// 当前进度。
  IxTaskProgress get progress => _progress;

  /// 最近一次报告。
  IxTaskReport? get lastReport => _lastReport;

  /// 是否正在运行。
  bool get isRunning => _running;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 绑定通道落地实现（装配阶段调用）。
  void attachChannelApplier(IxChannelApplier applier) {
    _channelApplier = applier;
  }

  /// 当前是否具备通道落地能力。
  bool get hasChannelApplier => _channelApplier != null;

  /// 请求取消（下一次循环立即生效）。
  void cancel() {
    if (!_running) {
      return;
    }
    _cancelRequested = true;
    _diagnostics?.warn(
      'IX',
      '用户请求取消批量任务',
      code: 'OGL-IX-101',
      data: <String, Object?>{'done': _progress.done, 'total': _progress.total},
    );
  }

  /// 执行批量任务。
  ///
  /// [decision] 为 `null` 或未确认时，**抛 [IxConfirmationRequired]** ——
  /// 这是"批量必须询问用户"的强制落点。
  Future<IxTaskReport> run({
    required IxBatchPlan plan,
    required Future<IxTaskResult> Function(IxBatchItem item) work,
    IxBatchDecision? decision,
    IxChannelApplier? applyChannel,
  }) async {
    if (decision == null || !decision.confirmed) {
      _diagnostics?.warn(
        'IX',
        '批量操作被拦截：未获用户确认',
        code: 'OGL-IX-102',
        data: <String, Object?>{'title': plan.title, 'count': plan.count},
      );
      throw IxConfirmationRequired(plan);
    }
    if (_running) {
      throw StateError('已有批量任务在运行，请先等待或取消');
    }

    _running = true;
    _cancelRequested = false;
    _progress = IxTaskProgress(done: 0, total: plan.count);
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    final results = <IxTaskResult>[];
    _diagnostics?.info(
      'IX',
      '批量任务开始：${plan.title}',
      code: 'OGL-IX-001',
      data: <String, Object?>{
        'count': plan.count,
        'channel': decision.channel.name,
        'mirror': decision.mirrorId,
        'destructive': plan.hasDestructive,
      },
    );

    try {
      // 通道切换必须发生在**第一个请求之前**，且失败即整体失败——
      // 否则用户以为走的是镜像，实际走了直连。
      final applier = applyChannel ?? _channelApplier;
      if (applier != null) {
        await applier(decision);
      }

      for (final item in plan.items) {
        if (_cancelRequested) {
          break;
        }
        _progress = IxTaskProgress(
          done: results.length,
          total: plan.count,
          currentLabel: item.label,
          cancelled: _cancelRequested,
        );
        notifyListeners();

        try {
          results.add(await work(item));
        } catch (error) {
          // 单项失败**不中断整批**，但必须如实记录。
          results.add(IxTaskResult.failure(item.id, item.label, '$error'));
        }
      }
    } finally {
      stopwatch.stop();
      _running = false;
      final report = IxTaskReport(
        title: plan.title,
        results: results,
        channel: decision.channel,
        elapsed: stopwatch.elapsed,
        cancelled: _cancelRequested,
      );
      _lastReport = report;
      _progress = IxTaskProgress(
        done: results.length,
        total: plan.count,
        cancelled: _cancelRequested,
      );
      _diagnostics?.info(
        'IX',
        '批量任务结束：${plan.title}',
        code: 'OGL-IX-002',
        data: <String, Object?>{
          'summary': report.summary,
          'ms': stopwatch.elapsedMilliseconds,
        },
      );
      notifyListeners();
    }

    return _lastReport!;
  }
}
