/// L3 展示级 · 议题详情（正文 + 标签 + 指派人 + 评论 + 写操作）。
///
/// - 正文与评论都按 Markdown 渲染（README 同一条渲染管线）；
/// - 写操作统一走「先确认 / 先编辑 → 再请求 → 失败可见（横幅 + 日志）」；
/// - 有权限才显示入口：权限判据唯一为 `repo.permissions.push`（canPush），
///   游客 / 无权限用户不看到点了就 403 的按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/readme_view.dart';

/// 取 `issue_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'issue_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 评论文本上限（字符数）。
///
/// GitHub 对正文有长度限制，这里取一个留有余量的本地阈值：
/// 超限时本地即可给出清晰提示，而不是把请求打出去再被服务端拒绝。
const int _kMaxCommentChars = 60000;

/// 议题详情页。
class IssuePage extends StatefulWidget {
  /// 创建页面。
  const IssuePage({
    required this.surface,
    required this.fullName,
    required this.issue,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// 议题原始对象（列表接口返回的 Map）。
  final Map<String, dynamic> issue;

  @override
  State<IssuePage> createState() => _IssuePageState();
}

class _IssuePageState extends State<IssuePage> {
  AsyncController<List<Map<String, dynamic>>>? _comments;
  late String _state = ghStr(widget.issue, 'state');
  bool _busy = false;
  bool _locked = false;

  /// 评论输入。
  final TextEditingController _comment = TextEditingController();
  bool _posting = false;

  /// 当前登录名（从登录态懒取；取不到视为游客，按空串处理）。
  String _viewerLogin = '';

  /// 写权限：`null` = 尚未判定（详情请求进行中）⇒ 不显示入口；
  /// `true` 才展示。判据唯一：`GET /repos` 的 `permissions.push`。
  bool? _canWrite;

  /// 详情页可变字段的本地镜像（编辑 / 标签 / 指派人成功后刷新）。
  late String _title = ghStr(widget.issue, 'title');
  late List<String> _labels = _labelNamesOf(widget.issue);
  late List<String> _assignees = _loginsOf(widget.issue, 'assignees');

  int get _number => ghInt(widget.issue, 'number');

  @override
  void initState() {
    super.initState();
    _locked = widget.issue['locked'] == true;
    _commentsC().loadIfNeeded();
    _resolveCanWrite();
    _resolveViewerLogin();
  }

  @override
  void dispose() {
    _comments?.dispose();
    _comment.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _commentsC() {
    final existing = _comments;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: _t('comments'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.api.issueComments(widget.fullName, _number),
    );
    _comments = controller;
    return controller;
  }

  /// 判定写权限：`GET /repos/{o}/{r}` 返回 `permissions.push`。
  ///
  /// 请求失败按「不可写」收敛（少显示一个入口，绝不误放行）。
  Future<void> _resolveCanWrite() async {
    try {
      final repo = await widget.surface.domain.api.repo(widget.fullName);
      if (!mounted) {
        return;
      }
      setState(() => _canWrite = repo.isWritable);
    } catch (_) {
      // 权限探测失败不是页面级错误：按不可写收敛即可（入口不出现）。
      if (!mounted) {
        return;
      }
      setState(() => _canWrite = false);
    }
  }

  /// 取当前登录名（用于「自己的评论」判断；失败按游客收敛）。
  Future<void> _resolveViewerLogin() async {
    try {
      final account = await widget.surface.domain.auth.activeAccount();
      if (!mounted) {
        return;
      }
      setState(() => _viewerLogin = account?.login ?? '');
    } catch (_) {
      // 登录态读不出 ⇒ 按游客处理（评论菜单仅对协作者入口开放）。
      if (!mounted) {
        return;
      }
      setState(() => _viewerLogin = '');
    }
  }

  /// 异步回调后的 mounted 校验统一收口。
  static List<String> _labelNamesOf(Map<String, dynamic> issue) =>
      _loginsOf(issue, 'labels');

  /// 取 `key` 下的对象数组里每项的 `name` / `login`。
  static List<String> _loginsOf(Map<String, dynamic> node, String key) {
    final Object? raw = node[key];
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .map((Map<String, dynamic> item) => ghStr(item, 'name').isNotEmpty
            ? ghStr(item, 'name')
            : ghLogin(item))
        .toList();
  }

  // ───────────────────────── 写操作公共收尾 ─────────────────────────

  /// 失败转用户可见提示（横幅 + 日志）；成功记结果日志。
  Future<bool> _runWrite(
    String okLogDomain,
    String okMessage,
    String okTag,
    Future<void> Function() action,
  ) async {
    if (_busy) {
      return false;
    }
    setState(() => _busy = true);
    try {
      await action();
      OgLAppLog.instance.result(okLogDomain, okMessage, okTag);
      return true;
    } catch (error) {
      OgLAppLog.instance.add(
        okLogDomain,
        _t('actionFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(_t('actionFailed', {'error': error}));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ───────────────────────── 编辑标题 / 正文 ─────────────────────────

  Future<void> _editIssue() async {
    final titleController = TextEditingController(text: _title);
    final bodyController =
        TextEditingController(text: ghStrOrNull(widget.issue, 'body') ?? '');
    final bool? saved = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _EditIssueDialog(
        titleController: titleController,
        bodyController: bodyController,
        busyOf: () => _busy,
      ),
    );
    titleController.dispose();
    bodyController.dispose();
    if (saved != true || !mounted || !context.mounted) {
      return;
    }
    final String newTitle = titleController.text.trim();
    final String newBody = bodyController.text.trim();
    if (newTitle.isEmpty) {
      if (context.mounted) {
        OgLNotifier.of(context).info(_t('titleRequired'));
      }
      return;
    }
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      _t('issueEdited'),
      '#$_number',
      () => widget.surface.domain.api.updateIssue(
        widget.fullName,
        _number,
        title: newTitle,
        body: newBody,
      ),
    );
    if (ok && mounted && context.mounted) {
      setState(() => _title = newTitle);
      OgLNotifier.of(context).info(_t('issueEdited'));
    }
  }

  // ───────────────────────── 标签管理 ─────────────────────────

  Future<void> _manageLabels() async {
    List<Map<String, dynamic>> allLabels;
    try {
      allLabels = await widget.surface.domain.api.labels(widget.fullName);
    } catch (error) {
      // 标签清单拉取失败：写日志留痕，不在此处碰 context（lint 的 async gap）。
      OgLAppLog.instance.add(
        'issue',
        '标签清单拉取失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    final List<String> allNames = <String>[
      for (final Map<String, dynamic> label in allLabels)
        if (ghStr(label, 'name').isNotEmpty) ghStr(label, 'name'),
    ];
    final Set<String> selected = Set<String>.from(_labels);
    final bool? saved = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _LabelsDialog(
        allNames: allNames,
        selected: selected,
      ),
    );
    if (saved != true || !mounted || !context.mounted) {
      return;
    }
    final List<String> target = selected.toList();
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      _t('labelsUpdated'),
      '#$_number',
      () => widget.surface.domain.api.updateIssueLabels(
        widget.fullName,
        _number,
        labels: target,
      ),
    );
    if (ok && mounted && context.mounted) {
      setState(() => _labels = target);
      OgLNotifier.of(context).info(_t('labelsUpdated'));
    }
  }

  // ───────────────────────── 指派人 ─────────────────────────

  Future<void> _manageAssignees() async {
    final controller = TextEditingController(text: _assignees.join(', '));
    final bool? saved = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _AssigneesDialog(
        controller: controller,
      ),
    );
    controller.dispose();
    if (saved != true || !mounted || !context.mounted) {
      return;
    }
    final List<String> target = controller.text
        .split(',')
        .map((String token) => token.trim())
        .where((String token) => token.isNotEmpty)
        .toList();
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      _t('assigneesUpdated'),
      '#$_number',
      () => widget.surface.domain.api.updateIssueAssignees(
        widget.fullName,
        _number,
        assignees: target,
      ),
    );
    if (ok && mounted && context.mounted) {
      setState(() => _assignees = target);
      OgLNotifier.of(context).info(_t('assigneesUpdated'));
    }
  }

  // ───────────────────────── 锁定 / 解锁 ─────────────────────────

  Future<void> _toggleLock() async {
    final bool locking = !_locked;
    final bool? confirmed = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(locking ? _t('lock') : _t('unlock')),
        content: Text(locking ? _t('lockConfirm') : _t('unlockConfirm')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(locking ? _t('lock') : _t('unlock')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      locking ? _t('locked') : _t('unlocked'),
      '#$_number',
      () => locking
          ? widget.surface.domain.api.lockIssue(widget.fullName, _number)
          : widget.surface.domain.api.unlockIssue(widget.fullName, _number),
    );
    if (ok && mounted && context.mounted) {
      setState(() => _locked = locking);
      OgLNotifier.of(context).info(locking ? _t('locked') : _t('unlocked'));
    }
  }

  // ───────────────────────── 评论编辑 / 删除 ─────────────────────────

  Future<void> _showCommentActions(Map<String, dynamic> comment) async {
    final String action = await ogLShowSheet<String>(
          context: context,
          builder: (BuildContext sheetContext) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      OgLSpace.lg, OgLSpace.sm, OgLSpace.lg, OgLSpace.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_t('commentMenu'),
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(_t('commentEdit')),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(_t('delete')),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
                const SizedBox(height: OgLSpace.sm),
              ],
            ),
          ),
        ) ??
        '';
    if (!mounted || action.isEmpty) {
      return;
    }
    if (action == 'edit') {
      await _editComment(comment);
    } else if (action == 'delete') {
      await _deleteComment(comment);
    }
  }

  Future<void> _editComment(Map<String, dynamic> comment) async {
    final int commentId = ghInt(comment, 'id');
    final controller = TextEditingController(text: ghStr(comment, 'body'));
    final bool? saved = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => _EditCommentDialog(
        controller: controller,
      ),
    );
    controller.dispose();
    if (saved != true || !mounted || !context.mounted) {
      return;
    }
    final String body = controller.text.trim();
    if (body.isEmpty) {
      if (context.mounted) {
        OgLNotifier.of(context).info(_t('commentRequired'));
      }
      return;
    }
    if (body.length > _kMaxCommentChars) {
      if (!context.mounted) {
        return;
      }
      OgLNotifier.of(context).warning(
        _t('commentTooLong', {'length': body.length, 'max': _kMaxCommentChars}),
      );
      return;
    }
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      _t('commentEdited'),
      '#$_number',
      () => widget.surface.domain.api
          .updateIssueComment(widget.fullName, commentId, body: body),
    );
    if (ok && mounted && context.mounted) {
      OgLNotifier.of(context).info(_t('commentEdited'));
      await _commentsC().load();
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> comment) async {
    final int commentId = ghInt(comment, 'id');
    final bool? confirmed = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('delete')),
        content: Text(_t('commentDeleteConfirm')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      _t('commentDeleted'),
      '#$_number',
      () => widget.surface.domain.api
          .deleteIssueComment(widget.fullName, commentId),
    );
    if (ok && mounted && context.mounted) {
      OgLNotifier.of(context).info(_t('commentDeleted'));
      await _commentsC().load();
    }
  }

  // ───────────────────────── 关闭 / 重开（既有） ─────────────────────────

  Future<void> _toggleState() async {
    if (_busy) {
      return;
    }
    final bool closing = _state == 'open';
    final bool? confirmed = await ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(closing
            ? _t('closeIssue', {'number': _number})
            : _t('reopenIssue', {'number': _number})),
        content: Text(closing ? _t('closeHint') : _t('reopenHint')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(closing ? _t('close') : _t('reopen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final bool closingState = closing;
    final bool ok = await _runWrite(
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      '议题',
      closingState ? _t('closed') : _t('reopened'),
      '#$_number',
      () => widget.surface.domain.api.updateIssue(
        widget.fullName,
        _number,
        state: closingState ? 'closed' : 'open',
      ),
    );
    if (ok && mounted && context.mounted) {
      setState(() => _state = closingState ? 'closed' : 'open');
    }
  }

  // ───────────────────────── 发表评论（既有） ─────────────────────────

  Future<void> _postComment() async {
    final String body = _comment.text.trim();
    if (body.isEmpty) {
      if (context.mounted) {
        OgLNotifier.of(context).info(_t('commentRequired'));
      }
      return;
    }
    // 护栏：GitHub 对评论正文有长度上限；本地先拦，避免把超大负载发出去
    // 后被服务端拒绝（浪费一次往返，且错误信息不如本地清晰）。
    if (body.length > _kMaxCommentChars) {
      if (!context.mounted) {
        return;
      }
      OgLNotifier.of(context).warning(
        _t('commentTooLong', {'length': body.length, 'max': _kMaxCommentChars}),
      );
      return;
    }
    if (_posting) {
      return;
    }
    setState(() => _posting = true);
    try {
      await widget.surface.domain.api.createIssueComment(
        widget.fullName,
        _number,
        body: body,
      );
      // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
      OgLAppLog.instance.result('议题', _t('commentPosted'), '#$_number');
      if (!mounted) {
        return;
      }
      _comment.clear();
      await _commentsC().load();
      if (mounted) {
        OgLNotifier.of(context).info(_t('commentPosted'));
      }
    } catch (error) {
      OgLAppLog.instance.add(
        // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
        '议题',
        _t('commentPostFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('commentFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  // ───────────────────────── 构建辅助 ─────────────────────────

  String _initialOf(String name) {
    final String trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  /// AppBar 的更多操作菜单（有权限才有可选项）。
  Future<void> _showOverflow() async {
    final String action = await ogLShowSheet<String>(
          context: context,
          builder: (BuildContext sheetContext) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      OgLSpace.lg, OgLSpace.sm, OgLSpace.lg, OgLSpace.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_t('menu'),
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(_t('editIssue')),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text('${_t('manage')} · ${_t('labels')}'),
                  onTap: () => Navigator.of(sheetContext).pop('labels'),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('${_t('manage')} · ${_t('assignees')}'),
                  onTap: () => Navigator.of(sheetContext).pop('assignees'),
                ),
                ListTile(
                  leading: Icon(_locked ? Icons.lock_open : Icons.lock_outline),
                  title: Text(_locked ? _t('unlock') : _t('lock')),
                  onTap: () => Navigator.of(sheetContext).pop('lock'),
                ),
                const SizedBox(height: OgLSpace.sm),
              ],
            ),
          ),
        ) ??
        '';
    if (!mounted || action.isEmpty) {
      return;
    }
    switch (action) {
      case 'edit':
        await _editIssue();
        break;
      case 'labels':
        await _manageLabels();
        break;
      case 'assignees':
        await _manageAssignees();
        break;
      case 'lock':
        await _toggleLock();
        break;
    }
  }

  /// 标签 chip 行（无标签时显示占位）。
  Widget _labelsRow(ThemeData theme) {
    if (_labels.isEmpty) {
      return Text(_t('noLabels'), style: theme.textTheme.bodySmall);
    }
    return Wrap(
      spacing: OgLSpace.sm,
      runSpacing: OgLSpace.sm,
      children: <Widget>[
        for (final String label in _labels)
          Chip(
            label: Text(label, style: theme.textTheme.labelMedium),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  /// 指派人行。
  Widget _assigneesRow(ThemeData theme) {
    if (_assignees.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        Icon(Icons.person_outline,
            size: theme.textTheme.bodySmall?.fontSize, color: theme.hintColor),
        const SizedBox(width: OgLSpace.sm),
        Expanded(
          child: Text(
            '${_t('assignees')}: ${_assignees.join(', ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String body = ghStrOrNull(widget.issue, 'body') ?? '';
    final bool open = _state == 'open';
    final bool canWrite = _canWrite == true;
    return Scaffold(
      appBar: AppBar(
        title: Text('#$_number', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: _t('menu'),
              onPressed: _busy ? null : _showOverflow,
            ),
        ],
      ),
      body: OgLReveal(
          delay: Duration.zero,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: <Widget>[
              // 头部（常量级）：标题 / 状态 / 标签 / 指派人 / 正文 / 操作按钮。
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    OgLSpace.lg, OgLSpace.lg, OgLSpace.lg, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(_title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: OgLSpace.sm),
                      Text(
                        'by ${ghLogin(widget.issue)} · '
                        '${ghDate(widget.issue, 'created_at')} · '
                        '${open ? _t('openNow') : _t('closed')}'
                        '${_locked ? ' · ${_t('locked')}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: OgLSpace.sm),
                      _labelsRow(theme),
                      const SizedBox(height: OgLSpace.sm),
                      _assigneesRow(theme),
                      const SizedBox(height: OgLSpace.md),
                      if (body.trim().isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(OgLSpace.md),
                            child: ReadmeView(
                              markdown: body,
                              onOpenLink: (Uri uri) {
                                // i18n-allow: 日志领域标签（开发者上下文，非界面文案）
                                unawaited(openExternalLink(uri, tag: '议题'));
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: OgLSpace.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _toggleState,
                          icon: Icon(open ? Icons.task_alt : Icons.undo),
                          label:
                              Text(open ? _t('closeIssueTitle') : _t('reopen')),
                        ),
                      ),
                      const SizedBox(height: OgLSpace.lg),
                      const Divider(height: 1),
                      Text(_t('comments'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: OgLSpace.sm)
                    ],
                  ),
                ),
              ),
              // 评论：按需构建（评论可以很多）。
              OgLAsyncSliver<List<Map<String, dynamic>>>(
                controller: _commentsC(),
                padding: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
                emptyIcon: Icons.chat_bubble_outline,
                emptyText: _t('noComments'),
                itemCountOf: (List<Map<String, dynamic>> comments) =>
                    comments.length,
                itemBuilder: (
                  BuildContext context,
                  List<Map<String, dynamic>> comments,
                  int index,
                ) {
                  final Map<String, dynamic> comment = comments[index];
                  return Card(
                    key: ValueKey<String>('comment-${ghInt(comment, 'id')}'),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          padding: const EdgeInsets.fromLTRB(OgLSpace.md,
                              OgLSpace.sm, OgLSpace.md, OgLSpace.sm),
                          child: Row(
                            children: <Widget>[
                              CircleAvatar(
                                radius: 13,
                                child: Text(
                                  _initialOf(ghLogin(comment)),
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                              const SizedBox(width: OgLSpace.sm),
                              Expanded(
                                child: Text(
                                  '${ghLogin(comment).isEmpty ? OgLI18n.instance.t('common', 'unknown') : ghLogin(comment)} · '
                                  '${ghDate(comment, 'created_at')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              // 评论操作入口：仅登录用户长按 / 点击图标出现，
                              // 服务端决定能不能改删（客户端不猜权限，
                              // 失败如实提示——这是 GitHub 语义的最小可行）。
                              if (canWrite || ghLogin(comment) == _viewerLogin)
                                IconButton(
                                  icon: const Icon(Icons.more_horiz,
                                      size: OgLIconSize.md),
                                  tooltip: _t('commentMenu'),
                                  onPressed: () =>
                                      unawaited(_showCommentActions(comment)),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(OgLSpace.md),
                          child: ReadmeView(
                            markdown: ghStr(comment, 'body'),
                            onOpenLink: (Uri uri) {
                              unawaited(
                                  openExternalLink(uri, tag: _t('comments')));
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // 发表评论（尾部）：输入框 + 提交按钮。
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: OgLSpace.lg),
                      const Divider(height: 1),
                      Text(_t('postComment'),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: OgLSpace.sm),
                      TextField(
                        controller: _comment,
                        minLines: 3,
                        maxLines: 8,
                        enabled: !_posting,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: _t('commentHint'),
                        ),
                      ),
                      const SizedBox(height: OgLSpace.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _posting ? null : _postComment,
                          icon: const Icon(Icons.send),
                          label: Text(
                              _posting ? _t('posting') : _t('postComment')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: OgLSpace.xl)),
            ],
          )),
    );
  }
}

/// 编辑议题对话框（标题 + 正文）。
class _EditIssueDialog extends StatelessWidget {
  const _EditIssueDialog({
    required this.titleController,
    required this.bodyController,
    required this.busyOf,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final bool Function() busyOf;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('editIssue')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: _t('title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: OgLSpace.md),
            TextField(
              controller: bodyController,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: _t('bodyHint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(_t('cancel')),
        ),
        FilledButton(
          onPressed: busyOf() ? null : () => Navigator.of(context).pop(true),
          child: Text(_t('save')),
        ),
      ],
    );
  }
}

/// 标签多选对话框（PATCH 全量替换语义：勾选集合即目标集合）。
class _LabelsDialog extends StatefulWidget {
  const _LabelsDialog({
    required this.allNames,
    required this.selected,
  });

  final List<String> allNames;
  final Set<String> selected;

  @override
  State<_LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends State<_LabelsDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('labels')),
      content: SizedBox(
        width: 320,
        child: widget.allNames.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(OgLSpace.md),
                child: Text(_t('noLabels')),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final String name in widget.allNames)
                      CheckboxListTile(
                        key: ValueKey<String>('label-$name'),
                        value: widget.selected.contains(name),
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              widget.selected.add(name);
                            } else {
                              widget.selected.remove(name);
                            }
                          });
                        },
                        title: Text(name,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ),
                  ],
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(_t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_t('save')),
        ),
      ],
    );
  }
}

/// 指派人编辑对话框（登录名逗号分隔；PATCH 全量替换）。
class _AssigneesDialog extends StatelessWidget {
  const _AssigneesDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('assignees')),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: _t('assigneesHint'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(_t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_t('save')),
        ),
      ],
    );
  }
}

/// 编辑评论对话框。
class _EditCommentDialog extends StatelessWidget {
  const _EditCommentDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('commentEdit')),
      content: TextField(
        controller: controller,
        minLines: 4,
        maxLines: 10,
        decoration: InputDecoration(
          hintText: _t('bodyHint'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(_t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_t('save')),
        ),
      ],
    );
  }
}
