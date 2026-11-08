/// L3 展示级 · 发现页（微博式纵向信息流 + 三个左右滑动子标签）。
///
/// - **动态**：GitHub 官方 `/notifications` 通知流（Release / Issue / PR），
///   一次请求聚合关注仓库的新事项，卡片式上下滑动；
/// - **推荐**：热门仓库分页信息流（滚动到底自动加载），含描述 / README 切片 /
///   星数·语言·最新版本号微粒子小字；
/// - **Issues**：聚合「我提出的」与「star 仓库新提出的」open issue，
///   新的在上，支持 全部 / 我的 / Star 三档筛选；
/// - 搜索入口在仓库页右上角（搜索图标）与首页空态；本页不再承担搜索框。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/notifier.dart';
import '../app/og_l_app_bar.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../types.dart';
import '../util/clipboard_x.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import 'issue_page.dart';
import 'repo_page.dart';

/// 取 `search_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'search_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 骨架块：加载态统一用主题色圆角块代替转圈。
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(OgLRadius.sm),
        ),
      );
}

/// 统一加载骨架卡片（三 tab 共用）：圆角卡内模拟标题 / 正文 / 元信息。
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required super.key, this.dense = false});

  /// 紧凑模式：Issues tab 的列表行骨架。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Widget body = dense
        ? const Row(
            children: <Widget>[
              _SkeletonBox(height: 16, width: 16),
              SizedBox(width: OgLSpace.md),
              Expanded(child: _SkeletonBox(height: 16)),
              SizedBox(width: OgLSpace.md),
              _SkeletonBox(height: 12, width: 48),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const _SkeletonBox(height: 32, width: 32),
                  const SizedBox(width: OgLSpace.sm),
                  const Expanded(child: _SkeletonBox(height: 16)),
                  const SizedBox(width: OgLSpace.sm),
                  const _SkeletonBox(height: 14, width: 56),
                ],
              ),
              const SizedBox(height: OgLSpace.md),
              const _SkeletonBox(height: 14),
              const SizedBox(height: OgLSpace.sm),
              const _SkeletonBox(height: 12, width: 160),
            ],
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(OgLSpace.md),
        child: body,
      ),
    );
  }
}

/// 统一加载骨架列表（三 tab 共用）。
class _SkeletonList extends StatelessWidget {
  const _SkeletonList({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(OgLSpace.lg),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        itemBuilder: (BuildContext context, int index) => Padding(
          padding: const EdgeInsets.only(bottom: OgLSpace.md),
          child: _SkeletonCard(
            key: ValueKey<String>('skeleton-$index'),
            dense: dense,
          ),
        ),
      );
}

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

  /// **动态**：GitHub 官方 `/notifications` 通知流（一次请求，
  /// 不再是逐 star 仓库轮询 N 次）。
  AsyncController<List<Map<String, dynamic>>>? _feed;

  /// **推荐**：高星仓库分页列表（滚动到底自动加载更多）。
  final List<GhRepo> _repos = <GhRepo>[];
  final Map<String, String> _readmeOf = <String, String>{};
  final Map<String, String?> _versionOf = <String, String?>{};
  int _repoPage = 1;
  bool _repoLoading = false;
  bool _repoDone = false;
  Object? _repoError;
  final ScrollController _repoScroll = ScrollController();

  /// 推荐 tab 的分类筛选（0 热门 / 1 TypeScript / 2 Dart / 3 Flutter / 4 Rust）。
  int _repoCategory = 0;

  /// 分类 → 搜索限定词（热门不给限定符）。
  static const List<String> _kCategoryQueries = <String>[
    'stars:>10000',
    'language:TypeScript stars:>5000',
    'language:Dart stars:>2000',
    'topic:flutter stars:>2000',
    'language:Rust stars:>3000',
  ];

  /// Issues 聚合（保留原有语义）。
  AsyncController<List<Map<String, dynamic>>>? _issues;
  final Set<String> _mineUrls = <String>{};
  final Set<String> _starUrls = <String>{};
  int _issuesFilter = 0;

  @override
  void initState() {
    super.initState();
    _repoScroll.addListener(_onRepoScroll);
    _feed = AsyncController<List<Map<String, dynamic>>>(
      label: _t('tabFeed'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () async {
        // ★ 官方 API：GitHub 自己的通知流，覆盖关注/star/参与仓库的
        //   Release、Issue、PR 等新事项，按 updated_at 倒序（新的在上）。
        final List<Map<String, dynamic>> items =
            await widget.surface.domain.api.notifications(perPage: 30);
        return items
          ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
            final DateTime da = DateTime.tryParse(ghStr(a, 'updated_at')) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime db = DateTime.tryParse(ghStr(b, 'updated_at')) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });
      },
    );
    unawaited(_feed!.load());
    unawaited(_loadMoreRepos());
    unawaited(_loadIssues());
  }

  @override
  void dispose() {
    _tab.dispose();
    _repoScroll.dispose();
    _feed?.dispose();
    _issues?.dispose();
    super.dispose();
  }

  /// 滚动到距底部 300px 时自动加载下一页（**无限下拉刷新**）。
  void _onRepoScroll() {
    if (_repoScroll.position.pixels >=
        _repoScroll.position.maxScrollExtent - 300) {
      unawaited(_loadMoreRepos());
    }
  }

  /// 分页拉推荐仓库，并为每张卡片补 README 切片 + 最新版本号。
  ///
  /// 两项补充都是**按需、限并发、失败不阻断**（小字没有也不影响卡片）。
  Future<void> _loadMoreRepos() async {
    if (_repoLoading || _repoDone) {
      return;
    }
    _repoLoading = true;
    _repoError = null;
    if (mounted) {
      setState(() {});
    }
    try {
      final List<GhRepo> page = await widget.surface.domain.api.searchRepos(
        _kCategoryQueries[_repoCategory],
        perPage: 10,
        page: _repoPage,
      );
      if (page.isEmpty) {
        _repoDone = true;
      } else {
        _repos.addAll(page);
        _repoPage++;
        if (page.length < 10) {
          _repoDone = true;
        }
        // 每页最多 10 个，串行补充即可（避免一次打满 Search 配额）。
        for (final GhRepo repo in page) {
          if (!_readmeOf.containsKey(repo.fullName)) {
            _readmeOf[repo.fullName] =
                await widget.surface.domain.api.readmeExcerpt(repo.fullName);
          }
          if (!_versionOf.containsKey(repo.fullName)) {
            _versionOf[repo.fullName] =
                await widget.surface.domain.api.latestVersionOf(repo.fullName);
          }
          if (mounted) {
            setState(() {});
          }
        }
      }
    } on Object catch (error) {
      _repoError = error;
    } finally {
      _repoLoading = false;
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
        return merged.values.toList()
          ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
            final DateTime da = DateTime.tryParse(ghStr(a, 'created_at')) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final DateTime db = DateTime.tryParse(ghStr(b, 'created_at')) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });
      },
    );
    await _issues!.load();
  }

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

  /// 通知流条目 → 仓库全名（`repository.full_name`）。
  String _feedRepoOf(Map<String, dynamic> item) {
    final Object? repo = item['repository'];
    if (repo is Map<Object?, Object?>) {
      return ghStr(Map<String, dynamic>.from(repo), 'full_name');
    }
    return '';
  }

  /// 通知流条目 → `subject.type`（Release / Issue / PullRequest / Discussion…）。
  String _feedSubjectTypeOf(Map<String, dynamic> item) {
    final Object? subject = item['subject'];
    return subject is Map<Object?, Object?>
        ? ghStr(Map<String, dynamic>.from(subject), 'type')
        : '';
  }

  /// 通知流条目 → `subject.url`。
  String _feedSubjectUrlOf(Map<String, dynamic> item) {
    final Object? subject = item['subject'];
    return subject is Map<Object?, Object?>
        ? ghStr(Map<String, dynamic>.from(subject), 'url')
        : '';
  }

  /// 通知流条目 → 是否未读。
  bool _feedUnreadOf(Map<String, dynamic> item) =>
      ghStr(item, 'unread') == 'true' || item['unread'] == true;

  /// 通知类型 → 徽章（图标 + 颜色）。
  ///
  /// Release 绿（成功色）/ Issue 红（error）/ PR 紫（tertiary）/
  /// 讨论蓝（info）；未知类型回落 neutral + reason 文案。
  ({IconData icon, Color color, bool tinted}) _feedBadgeOf(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final ThemeData theme = Theme.of(context);
    final OgLSemanticColors sem = theme.extension<OgLSemanticColors>()!;
    return switch (_feedSubjectTypeOf(item)) {
      'Release' => (
          icon: Icons.tag,
          color: sem.success,
          tinted: true,
        ),
      'Issue' => (
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
          tinted: true,
        ),
      'PullRequest' => (
          icon: Icons.merge,
          color: theme.colorScheme.tertiary,
          tinted: true,
        ),
      'Discussion' => (
          icon: Icons.forum,
          color: sem.info,
          tinted: true,
        ),
      _ => (
          icon: Icons.notifications_none,
          color: theme.colorScheme.onSurfaceVariant,
          tinted: false,
        ),
    };
  }

  /// 点击通知卡：issue/PR → IssuePage；release → 仓库页；
  /// 都解析不出 → 降级用浏览器打开（openLinkOrCopy 内含复制兜底）。
  Future<void> _openFeedItem(Map<String, dynamic> item) async {
    final String repoName = _feedRepoOf(item);
    final String subjectUrl = _feedSubjectUrlOf(item);
    final String subjectType = _feedSubjectTypeOf(item);
    final String issueNumber =
        subjectUrl.contains('/issues/') || subjectUrl.contains('/pulls/')
            ? subjectUrl.split('/').last
            : '';
    if (subjectType == 'Issue' || subjectType == 'PullRequest') {
      final String number = issueNumber;
      if (repoName.isNotEmpty && number.isNotEmpty && mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => IssuePage(
              surface: widget.surface,
              fullName: repoName,
              issue: <String, dynamic>{'number': int.tryParse(number) ?? 0},
            ),
          ),
        );
        return;
      }
    }
    if (repoName.isNotEmpty && mounted) {
      try {
        final GhRepo repo = await widget.surface.domain.api.repo(repoName);
        if (mounted) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  RepoPage(surface: widget.surface, repo: repo),
            ),
          );
        }
        return;
      } on Object {
        // 仓库拉取失败：降级为浏览器打开 subject 链接（无链接则静默返回，
        // 卡片上的「在浏览器打开」按钮仍是兜底入口）。
      }
    }
    if (subjectUrl.isNotEmpty && mounted) {
      await openLinkOrCopy(context, subjectUrl, tag: 'Feed');
    }
  }

  /// 通知流条目 → 可读类型（微粒子小字用）。
  String _feedTypeOf(Map<String, dynamic> item) {
    final Object? subject = item['subject'];
    final String type = subject is Map<Object?, Object?>
        ? ghStr(Map<String, dynamic>.from(subject), 'type')
        : '';
    return switch (type) {
      'Release' => _t('feedRelease'),
      'Issue' => _t('feedIssue'),
      'PullRequest' => _t('feedPull'),
      _ => ghStr(item, 'reason').isEmpty ? type : ghStr(item, 'reason'),
    };
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
    final int number = ghInt(item, 'number');
    if (full.isEmpty || number <= 0 || !mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IssuePage(
          surface: widget.surface,
          fullName: full,
          // 只带定位所需字段（fullName + number），详情由 IssuePage 自行拉取。
          issue: <String, dynamic>{
            'number': number,
            'title': ghStr(item, 'title'),
            'html_url': ghStr(item, 'html_url'),
          },
        ),
      ),
    );
  }

  String _repoFullOf(Map<String, dynamic> item) {
    final String url = ghStr(item, 'repository_url');
    final int at = url.indexOf('/repos/');
    return at < 0 ? '' : url.substring(at + '/repos/'.length);
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

  // ── tab 1：动态（官方通知流，微博式纵向信息流）────────────────────

  Widget _buildFeedTab() => _feed == null
      ? _SkeletonList(key: const ValueKey<String>('feed-skeleton'))
      : RefreshIndicator(
          onRefresh: () => _feed!.load(),
          child: AsyncView<List<Map<String, dynamic>>>(
            controller: _feed!,
            emptyIcon: Icons.notifications_none,
            emptyText: _t('feedEmpty'),
            builder: (BuildContext context, List<Map<String, dynamic>> items) =>
                ListView.separated(
              padding: const EdgeInsets.all(OgLSpace.lg),
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: OgLSpace.md),
              itemBuilder: (BuildContext context, int index) {
                final Map<String, dynamic> item = items[index];
                final String repoName = _feedRepoOf(item);
                final Object? subject = item['subject'];
                final String title = subject is Map<Object?, Object?>
                    ? ghStr(Map<String, dynamic>.from(subject), 'title')
                    : '';
                final String url = _feedSubjectUrlOf(item);
                final ({IconData icon, Color color, bool tinted}) badge =
                    _feedBadgeOf(context, item);
                return Card(
                  key: ValueKey<String>('feed-$index-${ghStr(item, 'id')}'),
                  child: InkWell(
                    onTap: () => unawaited(_openFeedItem(item)),
                    borderRadius: BorderRadius.circular(OgLRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.all(OgLSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              CircleAvatar(
                                radius: 16,
                                child: Text(
                                  repoName.isNotEmpty
                                      ? repoName[0].toUpperCase()
                                      : 'R',
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ),
                              const SizedBox(width: OgLSpace.sm),
                              Expanded(
                                child: Text(
                                  repoName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              // 类型徽章：图标 + 着色小字。
                              Icon(badge.icon, size: 14, color: badge.color),
                              const SizedBox(width: OgLSpace.xxs),
                              Text(
                                _feedTypeOf(item),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: badge.color),
                              ),
                              // 未读圆点。
                              if (_feedUnreadOf(item)) ...<Widget>[
                                const SizedBox(width: OgLSpace.sm),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: OgLSpace.sm),
                          Text(
                            title.isEmpty ? _t('feedRelease') : title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: OgLSpace.xxs),
                          Text(
                            ghDate(item, 'updated_at'),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          if (url.isNotEmpty)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: () => unawaited(
                                  openLinkOrCopy(context, url, tag: 'Feed'),
                                ),
                                icon: const Icon(Icons.open_in_new, size: 14),
                                label: Text(_t('openInBrowser')),
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
        );

  // ── tab 2：推荐（无限下拉 + 富信息卡片）────────────────────────────

  Widget _buildRecommendedTab() {
    if (_repos.isEmpty && _repoLoading) {
      return _SkeletonList(key: const ValueKey<String>('repos-skeleton'));
    }
    if (_repos.isEmpty && _repoError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('$_repoError', textAlign: TextAlign.center),
              const SizedBox(height: OgLSpace.md),
              FilledButton.tonal(
                onPressed: () => unawaited(_loadMoreRepos()),
                child: Text(_t('retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_repos.isEmpty) {
      return Center(child: Text(_t('recommendedEmpty')));
    }
    return Column(
      children: <Widget>[
        // 分类筛选行：切换时重置分页状态并重新加载（换数据维度）。
        Padding(
          padding: const EdgeInsets.fromLTRB(
              OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.sm),
          child: Semantics(
            label: _t('categoryFilter'),
            child: SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text(_t('catHot'))),
                ButtonSegment<int>(value: 1, label: const Text('TypeScript')),
                ButtonSegment<int>(value: 2, label: const Text('Dart')),
                ButtonSegment<int>(value: 3, label: const Text('Flutter')),
                ButtonSegment<int>(value: 4, label: const Text('Rust')),
              ],
              selected: <int>{_repoCategory},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> selection) {
                if (selection.isNotEmpty && selection.first != _repoCategory) {
                  setState(() {
                    _repoCategory = selection.first;
                    _repos.clear();
                    _readmeOf.clear();
                    _versionOf.clear();
                    _repoPage = 1;
                    _repoDone = false;
                    _repoError = null;
                  });
                  unawaited(_loadMoreRepos());
                }
              },
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _repos.clear();
              _readmeOf.clear();
              _versionOf.clear();
              _repoPage = 1;
              _repoDone = false;
              await _loadMoreRepos();
            },
            child: ListView.separated(
              key: ValueKey<String>('repos-$_repoCategory'),
              controller: _repoScroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  OgLSpace.lg, OgLSpace.xxs, OgLSpace.lg, OgLSpace.lg),
              itemCount: _repos.length + 1,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: OgLSpace.md),
              itemBuilder: (BuildContext context, int index) {
                if (index == _repos.length) {
                  return _repoDone
                      ? const SizedBox.shrink()
                      : Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: OgLSpace.md),
                          child: _SkeletonCard(
                              key: ValueKey<String>('more-$index')),
                        );
                }
                final GhRepo repo = _repos[index];
                final String excerpt = _readmeOf[repo.fullName] ?? '';
                final String? version = _versionOf[repo.fullName];
                return Card(
                  key: ValueKey<String>('repo-${repo.fullName}'),
                  child: InkWell(
                    onTap: () => unawaited(_openRepo(repo)),
                    onLongPress: () => _showRepoActions(context, repo),
                    borderRadius: BorderRadius.circular(OgLRadius.md),
                    child: Padding(
                      padding: const EdgeInsets.all(OgLSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            repo.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: OgLSpace.xxs),
                          Text(
                            _repoSubtitle(repo),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (excerpt.isNotEmpty) ...<Widget>[
                            const SizedBox(height: OgLSpace.sm),
                            // README 切片：小字、次要色，与正文层次拉开。
                            Text(
                              excerpt,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.4,
                                  ),
                            ),
                          ],
                          const SizedBox(height: OgLSpace.sm),
                          // 微粒子小字：星数 / 语言 / 最新版本号。
                          Row(
                            children: <Widget>[
                              const Icon(Icons.star_border, size: 12),
                              const SizedBox(width: OgLSpace.xxs),
                              Text('${repo.stars}',
                                  style:
                                      Theme.of(context).textTheme.labelSmall),
                              if (repo.language != null &&
                                  repo.language!.isNotEmpty) ...<Widget>[
                                const SizedBox(width: OgLSpace.sm),
                                Text(repo.language!,
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                              ],
                              const Spacer(),
                              if (version != null && version.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: OgLSpace.sm,
                                      vertical: OgLSpace.xxs / 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius:
                                        BorderRadius.circular(OgLRadius.xs),
                                  ),
                                  child: Text(
                                    version,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondaryContainer,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 推荐卡片长按菜单：打开仓库 / 复制克隆地址 / 在浏览器打开。
  Future<void> _showRepoActions(BuildContext context, GhRepo repo) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(_t('actionOpenRepo')),
              onTap: () => Navigator.of(sheetContext).pop('open'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(_t('actionCopyClone')),
              subtitle: Text(
                'https://github.com/${repo.fullName}.git',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(sheetContext).pop('clone'),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(_t('actionOpenBrowser')),
              onTap: () => Navigator.of(sheetContext).pop('browser'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case 'open':
        await _openRepo(repo);
      case 'clone':
        await ogLCopyText(
          'https://github.com/${repo.fullName}.git',
          tag: _t('actionCopyClone'),
        );
        if (mounted) {
          OgLNotifier.of(context).info(_t('cloneCopied'));
        }
      case 'browser':
        await openLinkOrCopy(
          context,
          'https://github.com/${repo.fullName}',
          tag: 'Repo',
        );
    }
  }

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
                ? _SkeletonList(
                    key: const ValueKey<String>('issues-skeleton'), dense: true)
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
                            key: ValueKey<String>(
                                'issue-${ghStr(item, 'html_url')}'),
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
                            // 右侧：评论数 + 进入箭头。
                            trailing: Semantics(
                              label: _t('issuesComments', {
                                'count': ghInt(item, 'comments'),
                              }),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(Icons.chat_bubble_outline,
                                      size: 14),
                                  const SizedBox(width: OgLSpace.xxs),
                                  Text('${ghInt(item, 'comments')}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall),
                                  const SizedBox(width: OgLSpace.sm),
                                  const Icon(Icons.chevron_right, size: 18),
                                ],
                              ),
                            ),
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
