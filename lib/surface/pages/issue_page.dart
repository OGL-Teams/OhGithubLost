/// L3 展示级 · 议题详情（正文 + 评论 + 关闭 / 重开）。
///
/// - 正文与评论都按 Markdown 渲染（README 同一条渲染管线）；
/// - 关闭 / 重开是**状态切换**：二次确认，失败可见（横幅 + 日志）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
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

  /// 评论输入。
  final TextEditingController _comment = TextEditingController();
  bool _posting = false;

  int get _number => ghInt(widget.issue, 'number');

  @override
  void initState() {
    super.initState();
    _commentsC().loadIfNeeded();
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

  Future<void> _toggleState() async {
    if (_busy) {
      return;
    }
    final bool closing = _state == 'open';
    final bool? confirmed = await showDialog<bool>(
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
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.updateIssue(
        widget.fullName,
        _number,
        state: closing ? 'closed' : 'open',
      );
      OgLAppLog.instance.result(
        '议题',
        closing ? _t('closed') : _t('reopened'),
        '#$_number',
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = closing ? 'closed' : 'open');
    } catch (error) {
      OgLAppLog.instance.add(
        '议题',
        _t('toggleFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('actionFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _postComment() async {
    final String body = _comment.text.trim();
    if (body.isEmpty) {
      OgLNotifier.of(context).info(_t('commentRequired'));
      return;
    }
    // 护栏：GitHub 对评论正文有长度上限；本地先拦，避免把超大负载发出去
    // 后被服务端拒绝（浪费一次往返，且错误信息不如本地清晰）。
    if (body.length > _kMaxCommentChars) {
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

  String _initialOf(String name) {
    final String trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = ghStr(widget.issue, 'title');
    final String body = ghStrOrNull(widget.issue, 'body') ?? '';
    final bool open = _state == 'open';
    return Scaffold(
      appBar: AppBar(
        title: Text('#$_number', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: OgLReveal(
          delay: Duration.zero,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: <Widget>[
              // 头部（常量级）：标题 / 状态 / 正文 / 操作按钮 /「评论」标题。
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: OgLSpace.sm),
                      Text(
                        'by ${ghLogin(widget.issue)} · '
                        '${ghDate(widget.issue, 'created_at')} · '
                        '${open ? _t('openNow') : _t('closed')}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: OgLSpace.md),
                      if (body.trim().isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: ReadmeView(
                              markdown: body,
                              onOpenLink: (Uri uri) {
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
                      const Divider(height: 32),
                      Text(_t('comments'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: OgLSpace.sm)
                    ],
                  ),
                ),
              ),
              // 评论：按需构建（评论可以很多）。
              OgLAsyncSliver<List<Map<String, dynamic>>>(
                controller: _commentsC(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Divider(height: 32),
                      Text(_t('postComment'),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: OgLSpace.sm),
                      TextField(
                        controller: _comment,
                        minLines: 3,
                        maxLines: 8,
                        enabled: !_posting,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
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
