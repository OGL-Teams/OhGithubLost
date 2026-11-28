/// L3 展示级 · 仓库标签管理（单层平铺 / 零气泡）。
///
/// 数据来源 / Data source: `SurfaceBridge.domain.api.tags`（L2）。
/// 写操作 / Writes: `createTag` / `deleteTag`，删除前按设置二次确认。
library;

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/notifier.dart';
import '../app/og_l_app_bar.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/og_l_icons.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/flat_list.dart';

String _t(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('repo_tags', key, args: args);

/// 标签列表页。
class RepoTagsPage extends StatefulWidget {
  const RepoTagsPage({
    required this.surface,
    required this.fullName,
    this.canWrite = false,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final bool canWrite;

  @override
  State<RepoTagsPage> createState() => _RepoTagsPageState();
}

class _RepoTagsPageState extends State<RepoTagsPage> {
  final List<GhTag> _items = <GhTag>[];
  bool _loading = false;
  bool _more = true;
  int _page = 1;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || _busy) {
      return;
    }
    if (reset) {
      _page = 1;
      _more = true;
      _items.clear();
    }
    if (!_more) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<GhTag> page = await widget.surface.domain.api.tags(
        widget.fullName,
        perPage: widget.surface.settings.settings.tagsPerPage,
        page: _page,
      );
      if (!mounted) {
        return;
      }
      final String sort = widget.surface.settings.settings.tagSort;
      final List<GhTag> sorted = List<GhTag>.of(page);
      if (sort == 'updated') {
        sorted.sort((GhTag a, GhTag b) => b.name.compareTo(a.name));
      } else {
        sorted.sort((GhTag a, GhTag b) => a.name.compareTo(b.name));
      }
      setState(() {
        _items.addAll(sorted);
        _more = page.length >= widget.surface.settings.settings.tagsPerPage;
        _page += 1;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final _TagDraft? draft = await ogLShowDialog<_TagDraft>(
      context: context,
      builder: (BuildContext dialogContext) => const _CreateTagDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.createTag(
        widget.fullName,
        name: draft.name,
        sha: draft.sha,
      );
      if (mounted) {
        await _load(reset: true);
      }
    } on Object catch (error) {
      if (mounted) {
        OgLNotifier.of(context).warning('$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete(GhTag tag) async {
    if (widget.surface.settings.settings.tagDeleteConfirm) {
      final bool ok = (await ogLDangerConfirm(
            context: context,
            title: _t('deleteTitle'),
            body: _t('deleteBody', <String, String>{'name': tag.name}),
            actionText: _t('delete'),
          )) ??
          false;
      if (!ok) {
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.deleteTag(widget.fullName, tag.name);
      if (mounted) {
        await _load(reset: true);
      }
    } on Object catch (error) {
      if (mounted) {
        OgLNotifier.of(context).warning('$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OgLAppBar(
        title: Text(_t('title')),
        actions: <Widget>[
          if (widget.canWrite)
            IconButton(
              tooltip: _t('create'),
              icon: const Icon(Icons.add, size: OgLIconSize.md),
              onPressed: _busy ? null : () => _create(),
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_t('loadFailed')),
              const SizedBox(height: OgLSpace.md),
              FilledButton(
                onPressed: () => _load(reset: true),
                child: Text(OgLI18n.instance.t('common', 'retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty && _loading) {
      // 批 1b：标签列表加载骨架化。
      return const Center(child: OgLAsyncSkeleton());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.lg),
          child: Text(_t('empty')),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
            !_loading &&
            _more) {
          _load();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: _items.length + (_more ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.all(OgLSpace.lg),
              child: Center(child: OgLAsyncSkeleton(rows: 2)),
            );
          }
          final GhTag tag = _items[index];
          return OgLFlatTile(
            title: Text(tag.name),
            subtitle: Text(
                tag.sha.substring(0, tag.sha.length > 7 ? 7 : tag.sha.length)),
            leading:
                const Icon(Icons.local_offer_outlined, size: OgLIconSize.md),
            trailing: widget.canWrite
                ? IconButton(
                    tooltip: _t('delete'),
                    icon: const Icon(OgLIcons.delete, size: OgLIconSize.md),
                    onPressed: _busy ? null : () => _delete(tag),
                  )
                : null,
          );
        },
      ),
    );
  }
}

/// 创建标签的输入结果。
class _TagDraft {
  const _TagDraft({required this.name, required this.sha});
  final String name;
  final String sha;
}

/// 创建弹窗：标签名 + 目标提交 SHA（Git refs 轻量标签）。
class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog();

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _sha = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _sha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_t('createTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: _t('tagName')),
          ),
          const SizedBox(height: OgLSpace.md),
          TextField(
            controller: _sha,
            decoration: InputDecoration(labelText: _t('targetSha')),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(OgLI18n.instance.t('common', 'cancel')),
        ),
        FilledButton(
          onPressed: () {
            final String name = _name.text.trim();
            final String sha = _sha.text.trim();
            if (name.isEmpty || sha.isEmpty) {
              return;
            }
            Navigator.of(context).pop(_TagDraft(name: name, sha: sha));
          },
          child: Text(_t('create')),
        ),
      ],
    );
  }
}
