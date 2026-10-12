/// AI 聊天：本地历史、仓库上下文、写入确认和真实构建产物按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../surface_bridge.dart';
import '../types.dart';
import '../util/link_opener.dart';
import 'ai_confirmation.dart';
import 'ai_settings_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({
    required this.surface,
    this.repo = '',
    this.branch = '',
    super.key,
  });
  final SurfaceBridge surface;
  final String repo;
  final String branch;
  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  AiConversation? _chat;
  List<AiConversation> _history = [];
  bool _loading = true, _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    widget.surface.aiBuildChanges.addListener(_reload);
    widget.surface.domain.auth.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    widget.surface.aiBuildChanges.removeListener(_reload);
    widget.surface.domain.auth.removeListener(_accountChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    if (!_sending) {
      unawaited(_load(keep: true));
    }
  }

  Future<void> _load({bool keep = false, bool fresh = false}) async {
    try {
      final list = await widget.surface.aiConversations();
      AiConversation? chat;
      if (keep) {
        chat = list.where((e) => e.id == _chat?.id).firstOrNull;
      }
      if (chat == null && !fresh) {
        chat = list
            .where(
              (e) =>
                  widget.repo.isEmpty ||
                  (e.repo == widget.repo &&
                      (widget.branch.isEmpty || e.branch == widget.branch)),
            )
            .firstOrNull;
      }
      chat ??= await widget.surface.aiNewChat(
        repo: widget.repo,
        branch: widget.branch,
      );
      if (mounted) {
        setState(() {
          _history = list;
          _chat = chat;
          _loading = false;
        });
      }
      _bottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = aiError(e);
          _loading = false;
        });
      }
    }
  }

  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || _chat == null || text.isEmpty) {
      return;
    }
    _input.clear();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final request = widget.surface.aiSend(
        _chat!,
        text,
        (proposal) => confirmAiProposal(context, proposal),
      );
      setState(() {});
      _bottom();
      await request;
      _history = await widget.surface.aiConversations();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = aiError(e);
          _input.text = text;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _bottom();
      }
    }
  }

  Future<void> _download(Map<String, dynamic> artifact) async {
    try {
      await widget.surface.downloadAiArtifact(artifact);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(aiText('downloadQueued'))));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = aiError(e));
      }
    }
  }

  Future<void> _logs() async {
    try {
      final entries = await widget.surface.aiAudit();
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    aiText('audit'),
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, index) {
                      final e = entries[index];
                      final reversible =
                          e['restoreTree'] is String || e['before'] is Map;
                      return ListTile(
                        title: Text('${e['operation']} · ${e['status']}'),
                        subtitle: Text(
                          '${e['repo']}\n${e['at']}\n${e['commit'] ?? ''}',
                        ),
                        trailing: reversible
                            ? TextButton(
                                child: Text(aiText('rollback')),
                                onPressed: () async {
                                  Navigator.pop(sheet);
                                  try {
                                    await widget.surface.aiRollback(
                                      e,
                                      (p) => confirmAiProposal(context, p),
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                aiText('operationFinished'),
                                              ),
                                            ),
                                          );
                                    }
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = aiError(error));
                                    }
                                  }
                                },
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = aiError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(aiText('title')),
      actions: [
        IconButton(
          tooltip: aiText('newChat'),
          icon: const Icon(Icons.add_comment_outlined),
          onPressed: _sending ? null : () => _load(fresh: true),
        ),
        IconButton(
          tooltip: aiText('audit'),
          icon: const Icon(Icons.history),
          onPressed: _sending ? null : _logs,
        ),
        IconButton(
          tooltip: aiText('settings'),
          icon: const Icon(Icons.tune),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AiSettingsPage(surface: widget.surface),
            ),
          ),
        ),
      ],
    ),
    drawer: Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(title: Text(aiText('history'))),
            Expanded(
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (_, index) {
                  final chat = _history[index];
                  return ListTile(
                    selected: chat.id == _chat?.id,
                    title: Text(
                      chat.messages.isEmpty
                          ? aiText('newChat')
                          : chat.messages.first.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      chat.repo.isEmpty ? aiText('noRepo') : chat.repo,
                    ),
                    onTap: _sending
                        ? null
                        : () {
                            setState(() {
                              _chat = chat;
                              _error = null;
                            });
                            Navigator.pop(context);
                            _bottom();
                          },
                    trailing: IconButton(
                      tooltip: aiText('deleteChat'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _sending
                          ? null
                          : () async {
                              await widget.surface.aiDeleteChat(chat.id);
                              if (context.mounted) {
                                Navigator.pop(context);
                                await _load(fresh: chat.id == _chat?.id);
                              }
                            },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: Text(
                  _chat?.repo.isNotEmpty == true
                      ? '${_chat!.repo} · ${_chat!.branch}'
                      : aiText('contextHint'),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _chat?.messages.isEmpty != false
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            aiText('welcome'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _chat!.messages.length,
                        itemBuilder: (context, index) {
                          final message = _chat!.messages[index];
                          final user = message.role == 'user';
                          return Align(
                            alignment: user
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Card(
                              color: user
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : null,
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      aiText(user ? 'you' : 'title'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    MarkdownBody(
                                      data: message.notice
                                          ? aiText(message.content)
                                          : message.content,
                                      selectable: true,
                                      onTapLink: (text, href, title) {
                                        if (href != null &&
                                            ['https', 'http'].contains(
                                              Uri.tryParse(href)?.scheme,
                                            )) {
                                          unawaited(
                                            openLinkOrCopy(context, href),
                                          );
                                        }
                                      },
                                    ),
                                    for (final artifact in message.artifacts)
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.download),
                                        onPressed: () => _download(artifact),
                                        label: Text(
                                          '${aiText('downloadArtifact')}: ${artifact['name']}.zip',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_sending)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(aiText('working')),
                    ],
                  ),
                ),
              if (_error != null)
                ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(_error!),
                  trailing: IconButton(
                    tooltip: aiText('settings'),
                    icon: const Icon(Icons.tune),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AiSettingsPage(surface: widget.surface),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): () =>
                              unawaited(_send()),
                        },
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 6,
                          decoration: InputDecoration(
                            hintText: aiText('inputHint'),
                            border: const OutlineInputBorder(),
                          ),
                          enabled: !_loading && !_sending,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: aiText('send'),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
