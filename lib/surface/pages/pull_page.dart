/// L3 展示级 · PR 详情（描述 + 变更文件）。
///
/// - 描述按 Markdown 渲染；
/// - 文件列表带 `+N / -M` 统计；有补丁文本时可展开查看（等宽）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/readme_view.dart';
import '../util/og_l_space.dart';
import '../util/og_l_radius.dart';

/// 取 `pull_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'pull_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// PR 详情页。
class PullPage extends StatefulWidget {
  /// 创建页面。
  const PullPage({
    required this.surface,
    required this.fullName,
    required this.pull,
    required this.number,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// PR 原始对象（列表接口返回的 Map）。
  final Map<String, dynamic> pull;

  /// PR 编号。
  final int number;

  @override
  State<PullPage> createState() => _PullPageState();
}

class _PullPageState extends State<PullPage> {
  AsyncController<List<Map<String, dynamic>>>? _files;

  @override
  void initState() {
    super.initState();
    _filesC().loadIfNeeded();
  }

  @override
  void dispose() {
    _files?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _filesC() {
    final existing = _files;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: _t('changedFiles'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.api.pullFiles(widget.fullName, widget.number),
    );
    _files = controller;
    return controller;
  }

  /// PR 状态 → 中文（打开 / 已合并 / 草稿 / 已关闭）。
  String _stateText() {
    final String state = ghStr(widget.pull, 'state');
    final bool merged = widget.pull['merged'] == true;
    final bool draft = widget.pull['draft'] == true;
    if (merged) {
      return _t('merged');
    }
    if (state == 'closed') {
      return _t('closed');
    }
    if (draft) {
      return _t('draft');
    }
    return state == 'open' ? _t('open') : state;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = ghStr(widget.pull, 'title');
    final String body = ghStrOrNull(widget.pull, 'body') ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '#${widget.number}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: OgLReveal(
          delay: Duration.zero,
          child: CustomScrollView(
            slivers: <Widget>[
              // 头部：常量级 widget 数量，一次性构建即可；
              // 数据行交给下面的 sliver 懒加载（长列表不再一次性构建）。
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    OgLSpace.lg, OgLSpace.lg, OgLSpace.lg, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: OgLSpace.sm),
                      Text(
                        'by ${ghLogin(widget.pull)} · '
                        '${ghDate(widget.pull, 'created_at')} · '
                        '${_stateText()}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: OgLSpace.md),
                      if (body.trim().isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(OgLSpace.md),
                            child: ReadmeView(
                              markdown: body,
                              onOpenLink: (Uri uri) {
                                unawaited(openExternalLink(uri, tag: 'PR'));
                              },
                            ),
                          ),
                        ),
                      const Divider(height: 32),
                      Text(_t('changedFiles'),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: OgLSpace.sm)
                    ],
                  ),
                ),
              ),
              OgLAsyncSliver<List<Map<String, dynamic>>>(
                controller: _filesC(),
                padding: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
                itemCountOf: (List<Map<String, dynamic>> files) => files.length,
                itemBuilder: (
                  BuildContext context,
                  List<Map<String, dynamic>> files,
                  int index,
                ) =>
                    _fileTile(files[index]),
                emptyIcon: Icons.description_outlined,
                emptyText: _t('noChangedFiles'),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: OgLSpace.xl)),
            ],
          )),
    );
  }

  Widget _fileTile(Map<String, dynamic> file) {
    final String name = ghStr(file, 'filename');
    final int additions = ghInt(file, 'additions');
    final int deletions = ghInt(file, 'deletions');
    final String? patch = ghStrOrNull(file, 'patch');
    final String subtitle =
        '${ghFileStatusText(ghStr(file, 'status'))} · +$additions / -$deletions';
    if (patch == null || patch.trim().isEmpty) {
      return ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
      );
    }
    return ExpansionTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      childrenPadding:
          const EdgeInsets.fromLTRB(OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.lg),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(OgLSpace.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(OgLRadius.sm),
          ),
          child: SelectableText(
            patch,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
