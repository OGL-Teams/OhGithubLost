/// L3 展示级 · Gist 详情（查看 / 编辑 / 删除文件）。
///
/// 单文件内容可能被服务端截断（`truncated: true`）；此时回退用
/// `raw_url` 拉全文，**绝不把"被截断的内容"当成完整内容展示**。
/// 拉全文失败时如实降级：卡片上标注「内容可能被截断」
/// （见 `_GistFile.truncated`），而不是静默展示残缺内容。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/clipboard_x.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/code_editor_field.dart';
import '../app/notifier.dart';

/// 取 `gist_detail_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'gist_detail_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 一个 Gist 文件（内容已解析）。
class _GistFile {
  const _GistFile({
    required this.name,
    required this.language,
    required this.content,
    required this.size,
    required this.truncated,
  });

  final String name;
  final String language;
  final String content;
  final int size;

  /// 内容**可能被截断**：服务端标了 `truncated` 且 raw 拉全文失败。
  /// 界面据此在卡片上标注，绝不把它当完整内容展示。
  final bool truncated;
}

/// 一个 Gist（文件已解析）。
class _GistDetail {
  const _GistDetail({
    required this.description,
    required this.isPublic,
    required this.htmlUrl,
    required this.files,
  });

  final String description;
  final bool isPublic;
  final String htmlUrl;
  final List<_GistFile> files;
}

/// Gist 详情页。
class GistDetailPage extends StatefulWidget {
  /// 创建页面。
  const GistDetailPage({
    required this.surface,
    required this.gistId,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// Gist ID。
  final String gistId;

  @override
  State<GistDetailPage> createState() => _GistDetailPageState();
}

class _GistDetailPageState extends State<GistDetailPage> {
  AsyncController<_GistDetail>? _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _detailC().loadIfNeeded();
  }

  @override
  void dispose() {
    _detail?.dispose();
    super.dispose();
  }

  AsyncController<_GistDetail> _detailC() {
    final existing = _detail;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<_GistDetail>(
      label: _t('title'),
      isEmpty: (_GistDetail value) => value.files.isEmpty,
      loader: () async {
        final Map<String, dynamic>? gist =
            await widget.surface.domain.api.gist(widget.gistId);
        if (gist == null) {
          throw StateError(_t('notFound'));
        }
        final Object? filesRaw = gist['files'];
        final List<_GistFile> files = <_GistFile>[];
        if (filesRaw is Map<Object?, Object?>) {
          for (final Object? value in filesRaw.values) {
            if (value is! Map<Object?, Object?>) {
              continue;
            }
            final Map<String, dynamic> f = Map<String, dynamic>.from(value);
            final String name = ghStr(f, 'filename');
            String content = ghStr(f, 'content');
            final bool truncated = f['truncated'] == true;
            // 服务端标了截断（或内容为空）→ 回退 raw 拉全文。
            // 拉不到就把"可能被截断"如实带进 `_GistFile`：卡片会标注
            // 「内容可能被截断」，**绝不把被截断的内容当完整展示**。
            bool truncatedUnresolved = truncated;
            if (truncated || content.isEmpty) {
              final String raw = ghStr(f, 'raw_url');
              if (raw.isNotEmpty) {
                try {
                  content = await widget.surface.domain.api.rawText(raw);
                  truncatedUnresolved = false; // 拿到全文：解除标注。
                } catch (_) {
                  // raw 拉全文失败：**显式**置位（不看服务端 flag）——
                  // 回退失败本身就意味着手上这份内容不能保证完整，
                  // 由卡片标注「内容可能被截断」，绝不冒充完整内容。
                  truncatedUnresolved = true;
                }
              }
            }
            files.add(_GistFile(
              name: name,
              language: ghStr(f, 'language'),
              content: content,
              size: ghInt(f, 'size'),
              truncated: truncatedUnresolved,
            ));
          }
        }
        return _GistDetail(
          description: ghStr(gist, 'description'),
          isPublic: gist['public'] == true,
          htmlUrl: ghStr(gist, 'html_url'),
          files: files,
        );
      },
    );
    _detail = controller;
    return controller;
  }

  Future<void> _editFile(_GistFile file) async {
    final TextEditingController controller =
        TextEditingController(text: file.content);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('editFileName', {'name': file.name})),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 20,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(_t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.updateGist(
        widget.gistId,
        files: <String, String?>{file.name: updated},
      );
      OgLAppLog.instance.result('Gist', _t('updated'), file.name);
      if (mounted) {
        OgLNotifier.of(context).success(_t('saved'));
      }
      // 控制器可能在 `updateGist` 期间随页面一起被释放（用户退了出去）：
      // 释放后不再 `_detailC().load()` —— 这既避免无谓请求，也避免在已
      // dispose 的 State 上**重建**一个再也不会有界面消费的控制器。
      if (mounted) {
        await _detailC().load();
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Gist',
        _t('updateFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('saveFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteGist() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('deleteTitle')),
        content: Text(_t('deleteDesc')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.deleteGist(widget.gistId);
      OgLAppLog.instance.result('Gist', _t('deleted'), widget.gistId);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Gist',
        _t('deleteFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('deleteFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy(_GistFile file) async {
    await ogLCopyText(file.content, tag: 'Gist 文件');
    if (mounted) {
      OgLNotifier.of(context).success(_t('copiedFile', {'name': file.name}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: _t('deleteTitle'),
            onPressed: _busy ? null : _deleteGist,
          ),
        ],
      ),
      body: AsyncView<_GistDetail>(
        controller: _detailC(),
        emptyIcon: Icons.article_outlined,
        emptyText: _t('noFiles'),
        builder: (BuildContext context, _GistDetail detail) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              detail.description.isEmpty
                  ? _t('noDescription')
                  : detail.description,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${detail.isPublic ? _t('public') : _t('private')} · '
              '${_t('fileCount', <String, Object?>{
                    'count': detail.files.length
                  })}',
              style: theme.textTheme.bodySmall,
            ),
            if (detail.htmlUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    unawaited(
                      openLinkOrCopy(context, detail.htmlUrl, tag: 'Gist'),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(_t('openInBrowser')),
                ),
              ),
            ],
            const Divider(height: 32),
            for (final _GistFile file in detail.files)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.description_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  ghSizeText(file.size),
                                  style: theme.textTheme.bodySmall,
                                ),
                                // 内容可能被截断（服务端截断 + raw 回退失败）：
                                // 在卡片上如实标注，绝不冒充完整内容。
                                if (file.truncated)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 14,
                                          color: theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            _t('truncatedWarning'),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_all_outlined),
                            tooltip: _t('copyContent'),
                            onPressed: () => unawaited(_copy(file)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: _t('edit'),
                            onPressed:
                                _busy ? null : () => unawaited(_editFile(file)),
                          ),
                        ],
                      ),
                    ),
                    if (file.content.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(_t('emptyOrUnreadable')),
                      )
                    else
                      // 每个文件给定**确定高度**：re_editor 的 `_CodeField`
                      // 在无界高度（ListView 直接子项）里会触发布局断言。
                      // 半屏高兼顾「一屏内能看到内容」与「多个文件不会一次撑爆」。
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: OgLCodeViewer(
                          code: file.content,
                          path: file.name,
                          language: file.language,
                          showLineNumbers: false,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
