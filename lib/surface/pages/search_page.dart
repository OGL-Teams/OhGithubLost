/// L3 展示级 · 发现页（微博式纵向信息流 + 三个左右滑动子标签）。
///
/// - **动态**：star 仓库的 Release / Tag 发布流，卡片式上下滑动；
/// - **推荐**：热门仓库纵向列表；
/// - **Issues**：聚合「我提出的」与「star 仓库新提出的」open issue，
///   新的在上，支持 全部 / 我的 / Star 三档筛选；
/// - 搜索入口在仓库页右上角（搜索图标）与首页空态；本页不再承担搜索框。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/og_l_app_bar.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/gh_format.dart';
import '../util/og_l_space.dart';
import 'issue_page.dart';
import 'repo_page.dart';

/// 取 `search_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'search_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 一条搜索命中（结果页共用）。
class _SearchHit {
  const _SearchHit({
    required this.title,
    required this.subtitle,
    this.repo,
    this.initialPath,
  });

  final String title;
  final String subtitle;
  final GhRepo? repo;
  final String? initialPath;
}

/// 发现页。
class DiscoverPage extends StatefulWidget {
  /// 创建页面。
  const DiscoverPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with SingleTickerProviderStateMixin {
  /// 三个子标签：**动态 / 推荐 / Issues**（左右滑动，仿仓库页 TabBar）。
  late final TabController _tab = TabController(length: 3, vsync: this);

  /// star 仓库（两个 tab 共用）。
  AsyncController<List<GhRepo>>? _starred;

  /// star 仓库的最新发布（fullName → 摘要）。
  final Map<String, ({String title, String url})> _releases =
      <String, ({String title, String url})>{};
  bool _releasesLoading = false;
  Object? _releasesError;

  /// 推荐（高星热门仓库）。
  AsyncController<List<GhRepo>>? _recommended;

  /// Issues 聚合。
  AsyncController<List<Map<String, dynamic>>>? _issues;

  /// 我提出的 issue 地址集合（筛选「我的」用）。
  final Set<String> _mineUrls = <String>{};

  /// star 仓库 issue 地址集合（筛选「Star」用）。
  final Set<String> _starUrls = <String>{};

  /// 筛选：0 全部 / 1 我提出的 / 2 Star 仓库的。
  int _issuesFilter = 0;

  @override
  void initState() {
    super.initState();
    _starred = AsyncController<List<GhRepo>>(
      label: _t('starred'),
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.starredRepos(perPage: 20),
    );
    _recommended = AsyncController<List<GhRepo>>(
      label: _t('recommended'),
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      // 不登录也能看：搜索端点对匿名开放（GitHub Web 首页同理）。
      loader: () =>
          widget.surface.domain.api.searchRepos('stars:>10000', perPage: 10),
    );
    unawaited(_starred!.load());
    unawaited(_recommended!.load());
    unawaited(_loadReleases());
    unawaited(_loadIssues());
  }

  @override
  void dispose() {
    _tab.dispose();
    _starred?.dispose();
    _recommended?.dispose();
    _issues?.dispose();
    super.dispose();
  }

  /// 逐个 star 仓库取最新发布。
  ///
  /// 没有"批量 latest release"端点，逐仓请求是刻意的；perPage=20 把
  /// 请求次数限制在 20 次内，不做分页追赶。
  Future<void> _loadReleases() async {
    _releasesLoading = true;
    _releasesError = null;
    if (mounted) {
      setState(() {});
    }
    try {
      final List<GhRepo> repos =
          await widget.surface.domain.api.starredRepos(perPage: 20);
      for (final GhRepo repo in repos) {
        final ({
          String title,
          String tagName,
          String publishedAt,
          String url
        })? record = await widget.surface.domain.api.latestReleaseOrTag(
          repo.fullName,
        );
        if (record != null) {
          _releases[repo.fullName] = (title: record.title, url: record.url);
        }
      }
      _releasesLoading = false;
      if (mounted) {
        setState(() {});
      }
    } on Object catch (error) {
      _releasesLoading = false;
      _releasesError = error;
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// Issues 聚合：`author:@me` + star 仓库范围内的 open issue，
  /// 合并去重后按创建时间倒序（新的在上）。
  Future<void> _loadIssues() async {
    _issues = AsyncController<List<Map<String, dynamic>>>(
      label: _t('issuesFeed'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () async {
        final String? starredQuery = await _starredReposQuery();
        final List<Map<String, dynamic>> mine = await widget.surface.domain.api
            .searchIssues('is:issue is:open author:@me', sort: 'created');
        final List<Map<String, dynamic>> starred = starredQuery == null
            ? const <Map<String, dynamic>>[]
            : await widget.surface.domain.api.searchIssues(
                'is:issue is:open $starredQuery',
                sort: 'created',
              );
        _mineUrls
          ..clear()
          ..addAll(mine.map((Map<String, dynamic> e) => ghStr(e, 'html_url')));
        _starUrls
          ..clear()
          ..addAll(
              starred.map((Map<String, dynamic> e) => ghStr(e, 'html_url')));
        final Map<String, Map<String, dynamic>> merged =
            <String, Map<String, dynamic>>{};
        for (final Map<String, dynamic> item in <Map<String, dynamic>>[
          ...mine,
          ...starred,
        ]) {
          final String url = ghStr(item, 'html_url');
          if (url.isNotEmpty) {
            merged[url] = item;
          }
        }
        final List<Map<String, dynamic>> all = merged.values.toList()
          ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
            final DateTime da = DateTime.tryParse(ghStr(a, 'created_at')) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime db = DateTime.tryParse(ghStr(b, 'created_at')) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da); // 新的在上
          });
        return all;
      },
    );
    await _issues!.load();
  }

  /// `repo:a/b repo:c/d ...`（star 仓库聚合查询；上限 20 个防查询超长）。
  Future<String?> _starredReposQuery() async {
    try {
      final List<GhRepo> repos =
          await widget.surface.domain.api.starredRepos(perPage: 20);
      if (repos.isEmpty) {
        return null;
      }
      return repos.map((GhRepo r) => 'repo:${r.fullName}').join(' ');
    } on Object {
      return null;
    }
  }

  /// 从 `repository_url`（`…/repos/{o}/{r}`）还原仓库全名。
  String _repoFullOf(Map<String, dynamic> item) {
    final String url = ghStr(item, 'repository_url');
    final int at = url.indexOf('/repos/');
    if (at < 0) {
      return '';
    }
    return url.substring(at + '/repos/'.length);
  }

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

  Future<void> _openIssue(Map<String, dynamic> item) async {
    final String full = _repoFullOf(item);
    if (full.isEmpty || !mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IssuePage(
          surface: widget.surface,
          fullName: full,
          issue: item,
        ),
      ),
    );
  }

  String _repoSubtitle(GhRepo repo) {
    final String? desc = repo.description;
    return (desc == null || desc.isEmpty) ? (repo.language ?? '') : desc;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: OgLAppBar(
        title: _t('discover'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: <Widget>[
            Tab(text: _t('tabFeed')),
            Tab(text: _t('recommended')),
            Tab(text: _t('tabIssues')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: <Widget>[
          _buildFeedTab(),
          _buildRecommendedTab(),
          _buildIssuesTab(),
        ],
      ),
    );
  }

  // ── tab 1：动态（微博式纵向信息流）─────────────────────────────────

  /// 动态 = star 仓库的 Release / Tag 发布流。
  ///
  /// 每条是一张独立卡片（头像式图标 + 仓库名 + 版本标题 + 时间占位），
  /// 上下滑动浏览；不再用横向卡片。
  Widget _buildFeedTab() {
    if (_releasesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_releasesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.lg),
          child: Text('$_releasesError'),
        ),
      );
    }
    if (_releases.isEmpty) {
      return Center(child: Text(_t('releaseNone')));
    }
    return RefreshIndicator(
      onRefresh: _loadReleases,
      child: ListView.separated(
        padding: const EdgeInsets.all(OgLSpace.lg),
        itemCount: _releases.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: OgLSpace.md),
        itemBuilder: (BuildContext context, int index) {
          final MapEntry<String, ({String title, String url})> entry =
              _releases.entries.elementAt(index);
          final GhRepo? repo = _starred?.data
              ?.where((GhRepo r) => r.fullName == entry.key)
              .firstOrNull;
          return Card(
            child: InkWell(
              onTap: repo == null ? null : () => unawaited(_openRepo(repo)),
              child: Padding(
                padding: const EdgeInsets.all(OgLSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(Icons.new_releases_outlined, size: 18),
                        const SizedBox(width: OgLSpace.sm),
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: OgLSpace.sm),
                    Text(
                      entry.value.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: OgLSpace.xxs),
                    Text(
                      _t('releaseFromStarred'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── tab 2：推荐（纵向信息流）────────────────────────────────────────

  Widget _buildRecommendedTab() => AsyncView<List<GhRepo>>(
        controller: _recommended!,
        emptyIcon: Icons.explore_outlined,
        emptyText: _t('recommendedEmpty'),
        builder: (BuildContext context, List<GhRepo> repos) => RefreshIndicator(
          onRefresh: () => _recommended!.load(),
          child: ListView.separated(
            padding: const EdgeInsets.all(OgLSpace.lg),
            itemCount: repos.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: OgLSpace.sm),
            itemBuilder: (BuildContext context, int index) {
              final GhRepo repo = repos[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.star_border),
                  title: Text(repo.fullName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    _repoSubtitle(repo),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('${repo.stars}'),
                  onTap: () => unawaited(_openRepo(repo)),
                ),
              );
            },
          ),
        ),
      );

  // ── tab 2：Issues ────────────────────────────────────────────────────

  Widget _buildIssuesTab() => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs),
            child: SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text(_t('issuesAll'))),
                ButtonSegment<int>(value: 1, label: Text(_t('issuesMine'))),
                ButtonSegment<int>(value: 2, label: Text(_t('issuesStar'))),
              ],
              selected: <int>{_issuesFilter},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> selection) {
                if (selection.isNotEmpty) {
                  setState(() => _issuesFilter = selection.first);
                }
              },
            ),
          ),
          Expanded(
            child: _issues == null
                ? const Center(child: CircularProgressIndicator())
                : AsyncView<List<Map<String, dynamic>>>(
                    controller: _issues!,
                    emptyIcon: Icons.inbox_outlined,
                    emptyText: _t('issuesEmpty'),
                    builder: (BuildContext context,
                        List<Map<String, dynamic>> items) {
                      final List<Map<String, dynamic>> shown = items
                          .where(
                              (Map<String, dynamic> item) => _matchFilter(item))
                          .toList();
                      if (shown.isEmpty) {
                        return OgLAsyncEmptyPane(
                          icon: Icons.inbox_outlined,
                          text: _t('issuesEmpty'),
                        );
                      }
                      return ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> item = shown[index];
                          final bool mine =
                              _mineUrls.contains(ghStr(item, 'html_url'));
                          return ListTile(
                            leading: Icon(
                              mine ? Icons.person_outline : Icons.star_border,
                            ),
                            title: Text(
                              ghStr(item, 'title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_repoFullOf(item)}'
                              ' #${ghInt(item, 'number')} · '
                              '${ghLogin(item)} · '
                              '${ghDate(item, 'created_at')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => unawaited(_openIssue(item)),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      );

  bool _matchFilter(Map<String, dynamic> item) {
    final String url = ghStr(item, 'html_url');
    return switch (_issuesFilter) {
      1 => _mineUrls.contains(url),
      2 => _starUrls.contains(url) && !_mineUrls.contains(url),
      _ => true,
    };
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
  late final TextEditingController _input;
  late int _mode;
  late String _query;
  AsyncController<List<_SearchHit>>? _results;
  Timer? _debounce;

  static const Duration _debounceWindow = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.query);
    _mode = widget.mode;
    _query = widget.query;
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
    if (q.isEmpty || (q == _query && _results != null)) {
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
      appBar: OgLAppBar(title: _t('searchResults')),
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
