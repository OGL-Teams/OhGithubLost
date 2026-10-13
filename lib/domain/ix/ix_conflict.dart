/// L2 中枢级 · 交互逻辑：冲突编排。
///
/// 一致性引擎（[WriteOutcome]）只回答"是什么冲突、允许做什么"；
/// **本文件回答"怎么讲给用户听、用户点了以后怎么办"**。
///
/// 一条硬规矩来自 [DURABILITY.md](../docs/DURABILITY.md（该文件未落地，以源码为准）)：
/// 基线过期（`staleSha`）时**必须**先给"查看差异"，不得只给"覆盖"。
library;

import '../../kernel/contract/disk_types.dart';

/// 冲突提示里的一个可选项。
class IxConflictOption {
  /// 创建选项。
  const IxConflictOption({
    required this.action,
    required this.label,
    this.description,
    this.destructive = false,
    this.recommended = false,
  });

  /// 对应的一致性问题处置动作。
  final ConflictAction action;

  /// 按钮文案。
  final String label;

  /// 补充说明。
  final String? description;

  /// 是否危险（需二次确认）。
  final bool destructive;

  /// 是否推荐（UI 应高亮）。
  final bool recommended;

  @override
  String toString() => 'IxConflictOption(${action.name}: $label)';
}

/// 给用户看的冲突提示（UI 可直接渲染）。
class IxConflictPrompt {
  /// 创建提示。
  const IxConflictPrompt({
    required this.title,
    required this.message,
    required this.options,
    required this.conflict,
    this.baseSha,
    this.remoteSha,
    this.diverged = false,
    this.previewBase,
    this.previewRemote,
    this.previewLocal,
    this.detail,
  });

  /// 标题。
  final String title;

  /// 正文（人类可读）。
  final String message;

  /// 可选动作（**顺序即推荐顺序**）。
  final List<IxConflictOption> options;

  /// 冲突类型。
  final WriteConflict conflict;

  /// 本地基线指纹。
  final String? baseSha;

  /// 远端最新指纹。
  final String? remoteSha;

  /// 是否真三方分歧。
  final bool diverged;

  /// 三方内容（可能为 `null`，表示拿不到，界面应如实显示"未知"）。
  final String? previewBase;

  /// 远端内容。
  final String? previewRemote;

  /// 本地内容。
  final String? previewLocal;

  /// 原始失败说明（诊断折叠区）。
  final String? detail;

  /// 是否含危险选项。
  bool get hasDestructive => options.any((IxConflictOption o) => o.destructive);

  @override
  String toString() => 'IxConflictPrompt($title, ${options.length} 选项)';
}

/// 用户对冲突的处置。
class IxConflictResolution {
  /// 创建处置。
  const IxConflictResolution({
    required this.action,
    this.confirmed = false,
  });

  /// 选择的动作。
  final ConflictAction action;

  /// 危险动作是否已二次确认。
  final bool confirmed;

  /// 是否可以放行（危险动作必须已确认）。
  bool get allowed => !_requiresConfirmation(action) || confirmed;

  static bool _requiresConfirmation(ConflictAction action) =>
      action == ConflictAction.forceOverwrite ||
      action == ConflictAction.createInstead;

  @override
  String toString() =>
      'IxConflictResolution(${action.name}, confirmed=$confirmed)';
}

/// 冲突编排器（纯函数，便于测试）。
class IxConflictResolver {
  const IxConflictResolver._();

  /// 把写结果翻译成用户可读的提示；不是冲突时返回 `null`。
  static IxConflictPrompt? describe(
    WriteOutcome outcome, {
    String subject = '该项',
  }) {
    if (outcome.ok || outcome.conflict == WriteConflict.none) {
      return null;
    }

    final threeWay = outcome.threeWay;
    final options = <IxConflictOption>[
      for (final action in outcome.actions) _optionOf(action),
    ];

    return IxConflictPrompt(
      title: _titleOf(outcome.conflict, subject),
      message: _messageOf(outcome.conflict, subject, outcome),
      options: options,
      conflict: outcome.conflict,
      baseSha: outcome.baseSha,
      remoteSha: outcome.sha,
      diverged: threeWay?.diverged ?? false,
      previewBase: threeWay?.base,
      previewRemote: threeWay?.remote,
      previewLocal: threeWay?.local,
      detail: outcome.detail,
    );
  }

  /// 冲突是否可以"重试即解决"（无需用户决策）。
  static bool isAutoRecoverable(WriteConflict conflict) =>
      conflict == WriteConflict.server ||
      conflict == WriteConflict.verificationFailed;

  static String _titleOf(WriteConflict conflict, String subject) {
    switch (conflict) {
      case WriteConflict.staleSha:
        return '远端已更新';
      case WriteConflict.requiresRead:
        return '缺少基线版本';
      case WriteConflict.needsConfirmation:
        return '需要你确认';
      case WriteConflict.notFound:
        return '目标不存在';
      case WriteConflict.forbidden:
        return '权限不足';
      case WriteConflict.server:
        return '服务端错误';
      case WriteConflict.verificationFailed:
        return '写入校验未通过';
      case WriteConflict.none:
        return '无冲突';
    }
  }

  static String _messageOf(
    WriteConflict conflict,
    String subject,
    WriteOutcome outcome,
  ) {
    final base = outcome.baseSha;
    final remote = outcome.sha;
    final baseText = base == null ? '未知' : _short(base);
    final remoteText = remote == null ? '未知' : _short(remote);

    switch (conflict) {
      case WriteConflict.staleSha:
        final diverged = outcome.threeWay?.diverged ?? false;
        return diverged
            ? '$subject 在你编辑期间被别人修改过。\n'
                '你的基线：$baseText\n远端最新：$remoteText\n'
                '两边都改了内容，直接覆盖会丢掉对方的修改。'
            : '$subject 的远端版本已经更新。\n'
                '你的基线：$baseText\n远端最新：$remoteText';
      case WriteConflict.requiresRead:
        return '$subject 还没有读取过远端版本，无法安全写入。'
            '请先拉取最新内容再提交。';
      case WriteConflict.needsConfirmation:
        return '这一步会覆盖远端已有的内容，且不可撤销。';
      case WriteConflict.notFound:
        return '$subject 在远端已不存在（可能已被删除或改名）。';
      case WriteConflict.forbidden:
        return '当前令牌没有写入 $subject 的权限，需要 `repo` 作用域。';
      case WriteConflict.server:
        return '写入 $subject 时服务端返回错误，可稍后重试。';
      case WriteConflict.verificationFailed:
        return '$subject 写入后回读校验未通过，本地缓存已作废。'
            '数据可能已写入但被并发修改，请先拉取确认。';
      case WriteConflict.none:
        return '';
    }
  }

  static IxConflictOption _optionOf(ConflictAction action) {
    switch (action) {
      case ConflictAction.viewDiff:
        return const IxConflictOption(
          action: ConflictAction.viewDiff,
          label: '查看差异',
          description: '先看清两边各改了什么',
          recommended: true,
        );
      case ConflictAction.pullRemote:
        return const IxConflictOption(
          action: ConflictAction.pullRemote,
          label: '拉取远端最新',
          description: '放弃本地这份，改为远端版本继续',
        );
      case ConflictAction.retry:
        return const IxConflictOption(
          action: ConflictAction.retry,
          label: '重试',
        );
      case ConflictAction.forceOverwrite:
        return const IxConflictOption(
          action: ConflictAction.forceOverwrite,
          label: '强制覆盖',
          description: '用我的内容覆盖远端（对方的修改会丢失）',
          destructive: true,
        );
      case ConflictAction.reauthorize:
        return const IxConflictOption(
          action: ConflictAction.reauthorize,
          label: '重新授权',
        );
      case ConflictAction.createInstead:
        return const IxConflictOption(
          action: ConflictAction.createInstead,
          label: '改为新建',
          destructive: true,
        );
      case ConflictAction.retryLater:
        return const IxConflictOption(
          action: ConflictAction.retryLater,
          label: '稍后重试',
          description: '放进待同步队列，网络恢复后再试',
        );
    }
  }

  static String _short(String sha) =>
      sha.length <= 8 ? sha : sha.substring(0, 8);
}
