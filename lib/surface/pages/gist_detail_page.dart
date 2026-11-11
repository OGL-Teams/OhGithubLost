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
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../types.dart';
import '../util/accel.dart';
import '../util/clipboard_x.dart';
import '../util/download_proxy.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/code_editor_field.dart';

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
    required this.rawUrl,
  });

  final String name;
  final String language;
  final String content;
  final int size;

  /// raw 附件地址（`raw_url`；Gist 的 raw 是**匿名可取**的公开地址）。
  final String rawUrl;

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
            final String rawUrl = ghStr(f, 'raw_url');
            // 服务端标了截断（或内容为空）→ 回退 raw 拉全文。
            // 拉不到就把"可能被截断"如实带进 `_GistFile`：卡片会标注
            // 「内容可能被截断」，**绝不把被截断的内容当完整展示**。
            bool truncatedUnresolved = truncated;
            if (truncated || content.isEmpty) {
              if (rawUrl.isNotEmpty) {
                try {
                  content = await widget.surface.domain.api.rawText(rawUrl);
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
              rawUrl: rawUrl,
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
    final String? updated = await ogLShowDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('editFileName', {'name': file.name})),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 20,
            style: const TextStyle(fontFamily: kOglMonoFamily, fontSize: 13),
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
    final bool? confirmed = await ogLShowDialog<bool>(
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

  /// 下载 Gist 文件（raw 附件）。
  ///
  /// Gist 的 raw 地址匿名可取（无令牌参与），所以这里的加速**不涉及令牌出口**；
  /// 是否走通道由 `OgLAccelScope.gistFile`（默认关）与 `ogLAccelCandidates`
  /// 统一判定：命中就只给 `前缀 + raw` 这一项 —— **没有降级、没有兜底**，
  /// 失败如实报错。
  Future<void> _downloadFile(BuildContext context, _GistFile file) async {
    final List<String> prefixes = widget.surface.settings.settings
        .accelPrefixesFor(OgLAccelScope.gistFile);
    final List<String> candidates = ogLAccelCandidates(
      url: file.rawUrl,
      prefixes: prefixes,
      family: OgLAccelFamily.raw,
      bytes: file.size <= 0 ? null : file.size,
      // Gist raw 是公开地址：repoPrivate 恒 false，不涉及私有令牌。
      repoPrivate: false,
    );
    try {
      await widget.surface.domain.downloads.enqueue(
        url: candidates.first,
        fallbackUrls: candidates.skip(1).toList(),
        fileName: file.name,
        category: IxDownloadCategory.gist,
        connections: widget.surface.settings.settings.downloadConnections,
      );
      if (!context.mounted) {
        return;
      }
      OgLNotifier.of(context).info(_t('downloadQueued', {'name': file.name}));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      OgLNotifier.of(context).warning(
        _t('downloadFailed', {'name': file.name, 'error': '$error'}),
      );
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
          padding: const EdgeInsets.all(OgLSpace.lg),
          children: <Widget>[
            Text(
              detail.description.isEmpty
                  ? _t('noDescription')
                  : detail.description,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: OgLSpace.xxs),
            Text(
              '${detail.isPublic ? _t('public') : _t('private')} · '
              '${_t('fileCount', <String, Object?>{
                    'count': detail.files.length
                  })}',
              style: theme.textTheme.bodySmall,
            ),
            if (detail.htmlUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: OgLSpace.sm),
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
            const SizedBox(height: OgLSpace.lg),
            const Divider(height: 1),
            for (final _GistFile file in detail.files)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          OgLSpace.md, OgLSpace.sm, OgLSpace.xxs, OgLSpace.sm),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.description_outlined,
                              size: OgLIconSize.md),
                          const SizedBox(width: OgLSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kOglMonoFamily,
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
                                    padding: const EdgeInsets.only(
                                        top: OgLSpace.xxs),
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: OgLIconSize.xs,
                                          color: theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: OgLSpace.xxs),
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
                          // 下载 raw 附件：加速与否由 `OgLAccelScope.gistFile`
                          // 决定（默认关；没有 raw_url 时按钮不出现）。
                          if (file.rawUrl.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.download_outlined),
                              tooltip: _t('downloadFile'),
                              onPressed: () =>
                                  unawaited(_downloadFile(context, file)),
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
                        padding: EdgeInsets.all(OgLSpace.lg),
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
            const SizedBox(height: OgLSpace.xl),
          ],
        ),
      ),
    );
  }
}
