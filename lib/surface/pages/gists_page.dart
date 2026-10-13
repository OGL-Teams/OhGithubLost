/// L3 展示级 · Gist 列表。
///
/// - 一行一条：描述（缺省用首个文件名）/ 文件数 / 可见性 / 更新时间；
/// - 点击进入详情页（详情页支持查看、编辑、删除）；
/// - 右上角可新建；也可用系统浏览器打开。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import 'gist_detail_page.dart';
import 'new_gist_page.dart';
import '../app/notifier.dart';

/// 取 `gists_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'gists_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// Gist 列表页。
class GistsPage extends StatefulWidget {
  /// 创建页面。
  const GistsPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<GistsPage> createState() => _GistsPageState();
}

class _GistsPageState extends State<GistsPage> {
  AsyncController<List<Map<String, dynamic>>>? _gists;

  @override
  void initState() {
    super.initState();
    _gistsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _gists?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _gistsC() {
    final existing = _gists;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: 'Gist',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.gists(),
    );
    _gists = controller;
    return controller;
  }

  /// 描述缺省时用文件名（GitHub 网页端也是这个行为）。
  String _titleOf(Map<String, dynamic> gist) {
    final Object? description = gist['description'];
    if (description is String && description.trim().isNotEmpty) {
      return description.trim();
    }
    final Object? files = gist['files'];
    if (files is Map<Object?, Object?> && files.isNotEmpty) {
      return '${files.keys.first}';
    }
    return _t('noDescription');
  }

  int _fileCountOf(Map<String, dynamic> gist) {
    final Object? files = gist['files'];
    return files is Map<Object?, Object?> ? files.length : 0;
  }

  Future<void> _openDetail(Map<String, dynamic> gist) async {
    final String id = ghStr(gist, 'id');
    if (id.isEmpty) {
      if (mounted) {
        OgLNotifier.of(context).info(_t('missingId'));
      }
      return;
    }
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => GistDetailPage(
          surface: widget.surface,
          gistId: id,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _gistsC().load();
    }
  }

  Future<void> _create() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => NewGistPage(surface: widget.surface),
      ),
    );
    if (created == true && mounted) {
      OgLNotifier.of(context).info(_t('created'));
      await _gistsC().load();
    }
  }

  Future<void> _openInBrowser(Map<String, dynamic> gist) async {
    final String url = ghStr(gist, 'html_url');
    if (url.isEmpty) {
      if (mounted) {
        OgLNotifier.of(context).info(_t('noOpenLink'));
      }
      return;
    }
    await openLinkOrCopy(context, url, tag: 'Gist');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(_t('new')),
      ),
      body: AsyncView<List<Map<String, dynamic>>>(
        controller: _gistsC(),
        emptyIcon: Icons.article_outlined,
        emptyText: _t('empty'),
        builder: (
          BuildContext context,
          List<Map<String, dynamic>> gists,
        ) =>
            RefreshIndicator(
          onRefresh: () => _gistsC().load(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: gists.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> gist = gists[index];
              final bool isPublic = gist['public'] == true;
              return OgLReveal(
                delay: OgLAnim.staggerOf(context, index),
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(
                    _titleOf(gist),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_t('fileCount', {'count': _fileCountOf(gist)})}'
                    '${isPublic ? _t('public') : _t('private')} · '
                    '${ghDate(gist, 'updated_at')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: _t('openInBrowser'),
                    onPressed: () => unawaited(_openInBrowser(gist)),
                  ),
                  onTap: () => unawaited(_openDetail(gist)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
