/// L3 · AI 聊天页。
///
/// - 回复以**纯文本**渲染（`SelectableText`，**不使用 markdown** —— 见下）；
/// - 每次收发都写入 `OgLAppLog`（即接入日志 + 通知中心）；
/// - 会话与工具操作由 `AiService` 持久化（会话走 `DiskKv`，操作走审计落盘）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ohgithublost/domain/ai/ai_models.dart';

import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/og_l_space.dart';
import 'ai_settings_page.dart';

/// 取 `ai` 分片文案。
String _t(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('ai', key, args: args);

/// AI 聊天页。
class AiChatPage extends StatefulWidget {
  const AiChatPage({
    required this.surface,
    this.repo,
    super.key,
  });

  final SurfaceBridge surface;

  /// 绑定的仓库（`owner/name`），可空 = 未绑定。
  final String? repo;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  AiConversation _conversation =
      AiConversation(id: '', accountId: '', repo: null);
  List<AiConversation> _history = <AiConversation>[];
  bool _sending = false;
  bool _loading = true;
  String? _lastError;

  AiService get _ai => widget.surface.domain.ai;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String> _accountId() async {
    try {
      final GhAccount? a = await widget.surface.domain.auth.activeAccount();
      return a?.login ?? 'guest';
    } on Object {
      return 'guest';
    }
  }

  Future<void> _init() async {
    final String accountId = await _accountId();
    final List<AiConversation> convos = await _ai.conversations(accountId);
    final AiConversation current = convos.isEmpty
        ? AiConversation(id: '', accountId: accountId, repo: widget.repo)
        : convos.first;
    if (!mounted) {
      return;
    }
    setState(() {
      _history = convos;
      _conversation = current;
      _loading = false;
    });
  }

  Future<void> _newChat() async {
    final String accountId = await _accountId();
    setState(() {
      _conversation = AiConversation(
        id: '',
        accountId: accountId,
        repo: widget.repo,
      );
      _lastError = null;
    });
  }

  Future<void> _openConversation(AiConversation c) async {
    setState(() {
      _conversation = c;
      _lastError = null;
    });
  }

  Future<void> _deleteConversation(AiConversation c) async {
    if (c.id.isNotEmpty) {
      await _ai.deleteConversation(c.id);
    }
    final String accountId = await _accountId();
    final List<AiConversation> convos = await _ai.conversations(accountId);
    if (!mounted) {
      return;
    }
    setState(() {
      _history = convos;
      if (_conversation.id == c.id) {
        _conversation =
            AiConversation(id: '', accountId: accountId, repo: widget.repo);
      }
    });
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    _input.clear();
    final String accountId = await _accountId();
    final AiMessage user = AiMessage(role: AiRole.user, content: text);
    final List<AiMessage> messages = List<AiMessage>.of(_conversation.messages)
      ..add(user);
    final String cid = _conversation.id.isEmpty
        ? 'c${DateTime.now().microsecondsSinceEpoch}'
        : _conversation.id;
    _conversation = AiConversation(
      id: cid,
      accountId: accountId,
      repo: widget.repo,
      title: _conversation.title ??
          (text.length > 24 ? '${text.substring(0, 24)}…' : text),
      messages: messages,
      createdAt: _conversation.createdAt,
      updatedAt: DateTime.now(),
    );
    if (mounted) {
      setState(() {});
    }
    await _run(messages, accountId);
  }

  /// 重试：上一条 user 消息在失败时已写入 [_conversation.messages]，
  /// 直接对同一份消息列表再跑一遍，不重复追加。
  Future<void> _retry() async {
    if (_sending || _conversation.messages.isEmpty) {
      return;
    }
    await _run(_conversation.messages, await _accountId());
  }

  /// 当前订阅的流（用于停止 / dispose 取消）。
  StreamSubscription<String>? _streamSub;

  Future<void> _run(List<AiMessage> messages, String accountId) async {
    setState(() {
      _sending = true;
      _lastError = null;
    });
    OgLAppLog.instance
        .add('AI', messages.last.content, severity: OgLNoticeSeverity.info);

    // 实时流式累积 buffer（与 `_conversation.messages` 的最后一条同步）。
    final StringBuffer buf = StringBuffer();
    try {
      // 先把"用户消息"立刻落进会话，再让服务流式补齐助手回复。
      // ★ 改用 completeStream：每个 SSE 文本帧就 setState 一次，
      //   实现打字机效果；中途可被 `_stop` 取消。
      final Stream<String> stream = _ai.completeStream(
        messages,
        maxTokens: 4096,
      );
      _streamSub = stream.listen(
        (chunk) {
          buf.write(chunk);
          if (!mounted) return;
          setState(() {
            // 把累积的 buffer 写到对话的最后一条助手消息
            // （页面初次建一条空消息占位；这里持续更新它）。
            final List<AiMessage> updated = List<AiMessage>.from(
              _conversation.messages,
            );
            if (updated.isNotEmpty && updated.last.role == AiRole.assistant) {
              updated[updated.length - 1] = AiMessage(
                role: AiRole.assistant,
                content: buf.toString(),
              );
            } else {
              updated.add(AiMessage(
                role: AiRole.assistant,
                content: buf.toString(),
              ));
            }
            _conversation = AiConversation(
              id: _conversation.id,
              accountId: accountId,
              repo: widget.repo,
              title: _conversation.title,
              messages: updated,
              createdAt: _conversation.createdAt,
              updatedAt: DateTime.now(),
            );
          });
        },
        onError: (Object error, StackTrace st) {
          // 流式阶段抛错：把已缓冲部分按"中断"保存，不丢弃。
          if (!mounted) return;
          setState(() {
            _sending = false;
            _streamSub = null;
            _lastError =
                error is AiException ? _describeError(error) : _t('error');
          });
          OgLAppLog.instance.add(
            'AI',
            '流式中断：$error',
            severity: OgLNoticeSeverity.warning,
          );
        },
        onDone: () async {
          // 流完成 → 落盘；后续提示。
          if (!mounted) return;
          try {
            await _ai.saveConversation(_conversation);
          } catch (_) {/* 落盘失败不影响对话已显示在内存中 */}
          setState(() {
            _sending = false;
            _streamSub = null;
          });
          OgLAppLog.instance.add(
            'AI',
            _t('operationFinished'),
            severity: OgLNoticeSeverity.info,
          );
        },
        cancelOnError: true,
      );
    } on Object catch (e) {
      // 仅捕获「订阅前抛出的同步错误」（如设置缺失、密钥缺失抛 AiException），
      // 流式阶段抛错已在 onError 兜底。
      if (!mounted) return;
      setState(() {
        _sending = false;
        _lastError = '$e';
      });
      OgLAppLog.instance.add(
        'AI',
        '${_t('error')}：$e',
        severity: OgLNoticeSeverity.warning,
      );
    }
  }

  /// 主动停止流式输出（用户点「停止」）。

  String _describeError(AiException e) {
    switch (e.code) {
      case 'noKey':
        return _t('noKey');
      case 'disabled':
        return _t('enabled');
      case 'httpError':
        return '${_t('error')}（HTTP ${e.detail}）';
      case 'transport':
        return '${_t('error')}（${e.detail}）';
      default:
        return '${_t('error')}（${e.code}）';
    }
  }

  Widget _bubble(AiMessage m) {
    final ThemeData theme = Theme.of(context);
    if (m.role == AiRole.tool) {
      // 工具结果：收进一条次要样式的卡片。
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: OgLSpace.xs),
          padding: const EdgeInsets.symmetric(
              horizontal: OgLSpace.md, vertical: OgLSpace.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '⚙ ${m.name ?? 'tool'}: ${m.content}',
            style: theme.textTheme.bodySmall,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    final bool mine = m.role == AiRole.user;
    // 空 assistant 消息（工具调用中转轮）不渲染，工具结果单独展示。
    if (!mine && m.content.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: OgLSpace.xs),
        padding: const EdgeInsets.symmetric(
            horizontal: OgLSpace.md, vertical: OgLSpace.sm),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          m.content,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: <Widget>[
          IconButton(
            tooltip: _t('newChat'),
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
          IconButton(
            tooltip: _t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    AiSettingsPage(surface: widget.surface),
              ),
            ),
          ),
          IconButton(
            tooltip: _t('history'),
            icon: const Icon(Icons.history),
            onPressed: () => _showHistory(theme),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (widget.repo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  OgLSpace.lg, OgLSpace.sm, OgLSpace.lg, 0),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.folder_shared_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${_t('contextHint')}：${widget.repo}')),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _conversation.messages.isEmpty
                    ? Center(child: Text(_t('welcome')))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(OgLSpace.lg),
                        itemCount: _conversation.messages.length,
                        itemBuilder: (BuildContext _, int i) =>
                            _bubble(_conversation.messages[i]),
                      ),
          ),
          if (_lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  OgLSpace.lg, OgLSpace.xs, OgLSpace.lg, OgLSpace.xs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _lastError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(onPressed: _retry, child: Text(_t('retry'))),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  OgLSpace.md, OgLSpace.xs, OgLSpace.md, OgLSpace.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _t('inputHint'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: OgLSpace.md, vertical: OgLSpace.sm),
                      ),
                    ),
                  ),
                  const SizedBox(width: OgLSpace.sm),
                  // 发送中 → 变成「停止」按钮（中途可打断，避免长回复浪费 token）
                  _sending
                      ? IconButton.filled(
                          tooltip: _t('stop'),
                          icon: const Icon(Icons.stop_circle_outlined),
                          onPressed: _stop,
                        )
                      : IconButton.filled(
                          tooltip: _t('send'),
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHistory(ThemeData theme) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        builder: (BuildContext _, ScrollController controller) =>
            ListView.builder(
          controller: controller,
          itemCount: _history.length,
          itemBuilder: (BuildContext ctx, int i) {
            final AiConversation c = _history[i];
            return ListTile(
              title: Text(c.title ?? c.id),
              subtitle: Text(c.repo ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_deleteConversation(c));
                },
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_openConversation(c));
              },
            );
          },
        ),
      ),
    );
  }
}
