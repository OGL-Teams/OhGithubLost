/// L3 展示级 · 发现页（搜索 + 星标动态 + 仓库推荐）。
///
/// - 搜索框下方展示「我 star 的仓库」与「热门推荐」，未登录时如实提示；
/// - 提交搜索 → push 到 [SearchResultsPage] 显示结果（结果不挤在本页）；
/// - 数据来自 GitHub REST：/user/starred 与 /search/repositories（高星排序）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/gh_format.dart';
import '../util/og_l_space.dart';
import 'repo_page.dart';

/// 取 `search_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'search_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 一条搜索命中（把两种结果形态收敛成同一种展示）。
class _SearchHit {
  const _SearchHit({
    required this.title,
    required this.subtitle,
    required this.repo,
    this.initialPath,
  });

  final String title;
  final String subtitle;
  final GhRepo? repo;
  final String? initialPath;
}

/// 搜索页。
class DiscoverPage extends StatefulWidget {
  /// 创建页面。
  const DiscoverPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TextEditingController _input = TextEditingController();

  /// 星标动态（最近 star 的仓库）。
  AsyncController<List<GhRepo>>? _starred;

  /// 推荐仓库（按星数排序的热门仓库）。
  AsyncController<List<GhRepo>>? _recommended;

  @override
  void initState() {
    super.initState();
    _starred = AsyncController<List<GhRepo>>(
      label: _t('starred'),
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.starredRepos(perPage: 5),
    );
    _recommended = AsyncController<List<GhRepo>>(
      label: _t('recommended'),
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      // 不登录也能看：搜索端点对匿名开放（GitHub Web 首页同理）。
      loader: () => widget.surface.domain.api.searchRepos(
        'stars:>10000',
        perPage: 10,
      ),
    );
    unawaited(_starred!.load());
    unawaited(_recommended!.load());
  }

  @override
  void dispose() {
    _input.dispose();
    _starred?.dispose();
    _recommended?.dispose();
    super.dispose();
  }

  /// 提交搜索：结果交给独立页面，不把本页的发现内容挤掉。
  Future<void> _submit(String query) async {
    final String q = query.trim();
    if (q.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SearchResultsPage(
          surface: widget.surface,
          query: q,
          mode: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('discover'))),
      body: ListView(
        padding: const EdgeInsets.all(OgLSpace.lg),
        children: <Widget>[
          TextField(
            controller: _input,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: _t('queryHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: (String value) => unawaited(_submit(value)),
          ),
          const SizedBox(height: OgLSpace.lg),
          Text(_t('starred'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: OgLSpace.sm),
          _repoSection(_starred!, empty: _t('starredEmpty')),
          const SizedBox(height: OgLSpace.lg),
          Text(_t('recommended'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: OgLSpace.sm),
          _repoSection(_recommended!, empty: _t('recommendedEmpty')),
        ],
      ),
    );
  }

  /// 仓库卡片区：加载 / 错误 / 空 / 数据四态都由 AsyncView 收敛。
  Widget _repoSection(
    AsyncController<List<GhRepo>> controller, {
    required String empty,
  }) =>
      SizedBox(
        height: 260,
        child: AsyncView<List<GhRepo>>(
          controller: controller,
          fill: false,
          emptyIcon: Icons.star_border,
          emptyText: empty,
          builder: (BuildContext context, List<GhRepo> repos) =>
              ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: repos.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: OgLSpace.sm),
            itemBuilder: (BuildContext context, int index) {
              final GhRepo repo = repos[index];
              return SizedBox(
                width: 220,
                child: Card(
                  child: InkWell(
                    onTap: () => unawaited(_openRepo(repo)),
                    child: Padding(
                      padding: const EdgeInsets.all(OgLSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(repo.fullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: OgLSpace.xxs),
                          Text(_repoSubtitle(repo),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                          const Spacer(),
                          Row(
                            children: <Widget>[
                              const Icon(Icons.star, size: 14),
                              const SizedBox(width: OgLSpace.xxs),
                              Text('${repo.stars}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

  Future<void> _openRepo(GhRepo repo) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RepoPage(
          surface: widget.surface,
          repo: repo,
        ),
      ),
    );
  }

  String _repoSubtitle(GhRepo repo) {
    final String? desc = repo.description;
    return (desc == null || desc.isEmpty) ? (repo.language ?? '') : desc;
  }
}

/// 搜索结果页（独立路由）：仓库 / 代码两种模式，输入即搜（300ms 防抖）。
class SearchResultsPage extends StatefulWidget {
  /// 创建结果页。
  const SearchResultsPage({
    required this.surface,
    required this.query,
    required this.mode,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 初始查询词。
  final String query;

  /// 初始模式（0 仓库 / 1 代码）。
  final int mode;

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  late final TextEditingController _input =
      TextEditingController(text: widget.query);
  int _mode = widget.mode;
  String _query = widget.query;
  AsyncController<List<_SearchHit>>? _results;
  Timer? _debounce;

  static const Duration _debounceWindow = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _results?.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, () {
      if (mounted) {
        unawaited(_run());
      }
    });
  }

  Future<void> _run() async {
    final String q = _input.text.trim();
    if (q.isEmpty || q == _query && _results != null) {
      return;
    }
    _query = q;
    final AsyncController<List<_SearchHit>> controller =
        AsyncController<List<_SearchHit>>(
      label: _t(_mode == 0 ? 'repoSearch' : 'codeSearch'),
      isEmpty: (List<_SearchHit> value) => value.isEmpty,
      loader: () async {
        if (_mode == 0) {
          final List<GhRepo> repos =
              await widget.surface.domain.api.searchRepos(q, perPage: 30);
          return repos
              .map((GhRepo repo) => _SearchHit(
                    title: repo.fullName,
                    subtitle: _repoSubtitle(repo),
                    repo: repo,
                  ))
              .toList();
        }
        final List<Map<String, dynamic>> items =
            await widget.surface.domain.api.searchCode(q, perPage: 30);
        return items.map(_hitFromCode).toList();
      },
    );
    final AsyncController<List<_SearchHit>>? old = _results;
    setState(() => _results = controller);
    old?.dispose();
    unawaited(controller.load());
  }

  _SearchHit _hitFromCode(Map<String, dynamic> item) {
    final String path = ghStr(item, 'path');
    final String name = ghStr(item, 'name');
    final Object? matches = item['text_matches'];
    String fragment = '';
    if (matches is List<Object?>) {
      for (final Object? match in matches) {
        if (match is Map<Object?, Object?>) {
          final String text =
              ghStr(Map<String, dynamic>.from(match), 'fragment').trim();
          if (text.isNotEmpty) {
            fragment = text.replaceAll(RegExp(r'\s+'), ' ').trim();
            break;
          }
        }
      }
    }
    final Object? repoRaw = item['repository'];
    final GhRepo repo = repoRaw is Map<Object?, Object?>
        ? GhRepo.fromJson(Map<String, dynamic>.from(repoRaw))
        : GhRepo.fromJson(const <String, dynamic>{});
    return _SearchHit(
      title: path.isEmpty ? name : path,
      subtitle: fragment.isEmpty ? _t('openFileHint') : fragment,
      repo: repo.fullName.isEmpty ? null : repo,
      initialPath: path.isEmpty ? null : path,
    );
  }

  String _repoSubtitle(GhRepo repo) {
    final List<String> meta = <String>[
      if (repo.language != null && repo.language!.isNotEmpty) repo.language!,
      _t('starsCount', {'count': repo.stars}),
      if (repo.isPrivate) _t('private'),
    ];
    final String? desc = repo.description;
    return desc == null || desc.isEmpty
        ? meta.join(' · ')
        : '${meta.join(' · ')} — $desc';
  }

  Future<void> _open(_SearchHit hit) async {
    final GhRepo? repo = hit.repo;
    if (repo == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RepoPage(
          surface: widget.surface,
          repo: repo,
          initialPath: hit.initialPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncController<List<_SearchHit>>? controller = _results;
    return Scaffold(
      appBar: AppBar(title: Text(_t('searchResults'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs),
            child: Column(
              children: <Widget>[
                SegmentedButton<int>(
                  segments: <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 0, label: Text(_t('tabRepos'))),
                    ButtonSegment<int>(value: 1, label: Text(_t('tabCode'))),
                  ],
                  selected: <int>{_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<int> selection) {
                    if (selection.isNotEmpty && selection.first != _mode) {
                      setState(() {
                        _mode = selection.first;
                        _query = '';
                      });
                      unawaited(_run());
                    }
                  },
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _input,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _t('queryHint'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (String _) => _scheduleSearch(),
                  onSubmitted: (String _) => unawaited(_run()),
                ),
              ],
            ),
          ),
          Expanded(
            child: controller == null
                ? const Center(child: CircularProgressIndicator())
                : AsyncView<List<_SearchHit>>(
                    controller: controller,
                    emptyIcon: Icons.search_off,
                    emptyText: _t('noResults', {'query': _query}),
                    builder: (BuildContext context, List<_SearchHit> hits) =>
                        ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final _SearchHit hit = hits[index];
                        return ListTile(
                          leading: Icon(hit.initialPath == null
                              ? Icons.folder_outlined
                              : Icons.description_outlined),
                          title: Text(hit.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(hit.subtitle,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => unawaited(_open(hit)),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
