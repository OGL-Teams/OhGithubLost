/// L3 · AI 聊天页。
///
/// - 回复以**纯文本**渲染（`SelectableText`，**不使用 markdown** —— 见下）；
/// - 每次收发都写入 `OgLAppLog`（即接入日志 + 通知中心）；
/// - 会话与工具操作由 `AiService` 持久化（会话走 `DiskKv`，操作走审计落盘）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';

/// 取 `ai` 分片文案。
String _t(String key, [Map<String, String>? args]) => OgLI18n.instance.t('ai', key, args: args);

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

  AiConversation _conversation = AiConversation(id: '', accountId: '', repo: null);
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
        _conversation = AiConversation(id: '', accountId: accountId, repo: widget.repo);
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
    if (_conversation.id.isEmpty) {
      _conversation.id = 'c${DateTime.now().microsecondsSinceEpoch}';
    }
    _conversation = AiConversation(
      id: _conversation.id,
      accountId: accountId,
      repo: widget.repo,
      title: _conversation.title ?? (text.length > 24 ? '${text.substring(0, 24)}…' : text),
      messages: messages,
      createdAt: _conversation.createdAt,
      updatedAt: DateTime.now(),
    );
    setState(() {
      _sending = true;
      _lastError = null;
    });

    OgLAppLog.instance.add('AI', text, severity: OgLNoticeSeverity.info);

    try {
      final List<AiMessage> transcript = await _ai.complete(
        messages,
        accountId: accountId,
      );
      _conversation = AiConversation(
        id: _conversation.id,
        accountId: accountId,
        repo: widget.repo,
        title: _conversation.title,
        messages: transcript,
        createdAt: _conversation.createdAt,
        updatedAt: DateTime.now(),
      );
      await _ai.saveConversation(_conversation);
      OgLAppLog.instance.add('AI', _t('operationFinished'), severity: OgLNoticeSeverity.info);
    } on AiException catch (e) {
      _lastError = _describeError(e);
      OgLAppLog.instance.add(
        'AI',
        '${_t('error')}：${e.code}',
        severity: OgLNoticeSeverity.warning,
      );
    } on Object catch (e) {
      _lastError = '$e';
      OgLAppLog.instance.add('AI', '${_t('error')}：$e', severity: OgLNoticeSeverity.warning);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      final List<AiConversation> convos = await _ai.conversations(accountId);
      if (mounted) {
        setState(() => _history = convos);
      }
    }
  }

  String _describeError(AiException e) {
    switch (e.code) {
      case 'noKey':
        return _t('noKey');
      case 'disabled':
        return _t('enabled');
      case 'httpError':
        return '${_t('error')}（HTTP ${e.detail}）';
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
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          m.content.isEmpty ? (mine ? text : _t('working')) : m.content,
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
                builder: (BuildContext _) => AiSettingsPage(surface: widget.surface),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                        padding: const EdgeInsets.all(16),
                        itemCount: _conversation.messages.length,
                        itemBuilder: (BuildContext _, int i) =>
                            _bubble(_conversation.messages[i]),
                      ),
          ),
          if (_lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _lastError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(onPressed: _send, child: Text(_t('retry'))),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _t('inputHint'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: _t('send'),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward),
                    onPressed: _sending ? null : _send,
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
      builder: (BuildContext sheetContext) => ListView(
        shrinkWrap: true,
        children: <Widget>[
          for (final AiConversation c in _history)
            ListTile(
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
            ),
          if (_history.isEmpty)
            ListTile(title: Text(_t('empty'))),
        ],
      ),
    );
  }
}
