/// L3 展示级 · 发现页（紧凑行式信息流 + 三个左右滑动子标签）。
///
/// - **动态**：GitHub 官方 `/notifications` 通知流，紧凑行式布局——
///   左侧 4px 状态竖条（未读 primary / 已读透明），一行标题 + 一行
///   元信息（仓库 · 类型 · 相对时间），条目间 Divider，行高 ≤64；
/// - **推荐**：热门仓库双列网格（≥600px 两列 / 窄屏单列），含描述 /
///   折叠的 README 切片 / 星数·语言·最新版本号 meta 行；
/// - **Issues**：聚合「我提出的」与「star 仓库新提出的」open issue，
///   紧凑行式，FilterChip 横滑筛选行；
/// - 搜索入口在仓库页右上角（搜索图标）与首页空态；本页不再承担搜索框。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../kernel/log/og_l_log_file.dart';
import '../app/animations.dart';
import '../app/async.dart';
import '../app/notifier.dart';
import '../app/og_l_app_bar.dart';
import '../app/refresh_indicator.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/clipboard_x.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/discover_rows.dart';
import 'issue_page.dart';
import 'repo_page.dart';

/// 取 `search_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
      'search_page',
      key,
      args:
          args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')),
    );

/// ISO 8601 时间 → 相对时间（人眼扫信息流时「3 小时前」比「2026-07-14」省力）。
///
/// 现有 `gh_format` 只有绝对日期（[ghDate]），没有相对时间，这里就地补一个
/// 页面级实现：只到天（>30 天回落绝对日期），避免引入新依赖。
String _relativeTime(String iso) {
  final DateTime? time = DateTime.tryParse(iso)?.toLocal();
  if (time == null) {
    return '';
  }
  final Duration delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) {
    return _t('timeJustNow');
  }
  if (delta.inMinutes < 60) {
    return _t('timeMinutesAgo', {'count': delta.inMinutes});
  }
  if (delta.inHours < 24) {
    return _t('timeHoursAgo', {'count': delta.inHours});
  }
  if (delta.inDays < 30) {
    return _t('timeDaysAgo', {'count': delta.inDays});
  }
  return iso.split('T').first;
}

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
          borderRadius: OgLRadius.cSm,
        ),
      );
}

/// 统一加载骨架行（三 tab 共用）：与紧凑行式对齐——
/// 左侧状态条占位 + 标题行 + 元信息行。
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OgLSpace.lg,
          vertical: OgLSpace.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SkeletonBox(height: OgLSpace.xxl, width: OgLSpace.xxs),
            const SizedBox(width: OgLSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SkeletonBox(height: OgLSpace.md),
                  const SizedBox(height: OgLSpace.xxs),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        flex: 3,
                        child: _SkeletonBox(height: OgLSpace.sm),
                      ),
                      const SizedBox(width: OgLSpace.sm),
                      Expanded(
                          flex: 2, child: _SkeletonBox(height: OgLSpace.sm)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 统一加载骨架列表（三 tab 共用）。
///
/// ★ 与真实列表的节奏对齐：动态 / Issues 的数据态用 `ListView.separated`
///   的 `Divider(height: 1)` 分隔行，骨架态此前的 `ListView.builder` 没有
///   分隔符——加载完成时每行间多出 1px，整列累计 5px 的闪跳。
///   这里同样用 `separated` 补上等高分隔符，行块总高与数据态一致。
class _SkeletonList extends StatelessWidget {
  const _SkeletonList({super.key});

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: OgLSpace.sm),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) =>
            _SkeletonRow(key: ValueKey<String>('skeleton-$index')),
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

/// 推荐仓库卡（网格单元）：仓库名 + 两行描述 + 折叠的 README 切片 +
/// meta 行（★数 · 语言 · 版本号）。README 默认折叠，点击展开。
class _RepoCard extends StatefulWidget {
  const _RepoCard({
    required this.repo,
    required this.excerpt,
    required this.version,
    required this.onOpen,
    required this.onActions,
    super.key,
  });

  final GhRepo repo;
  final String excerpt;
  final String? version;
  final Future<void> Function(GhRepo) onOpen;
  final Future<void> Function(BuildContext, GhRepo) onActions;

  @override
  State<_RepoCard> createState() => _RepoCardState();
}

class _RepoCardState extends State<_RepoCard> {
  bool _readmeExpanded = false;

  /// ★ 数紧凑记法：12345 → 12.3k；1234567 → 1.2M。不足 1 万原样。
  /// 星标数是推荐卡最重的信号，裸数字在双列网格里会把 meta 行挤满。
  static String _compactCount(int n) {
    if (n >= 1000000) {
      final double v = n / 1000000;
      return '${v.toStringAsFixed(v < 10 ? 1 : 0)}M';
    }
    if (n >= 10000) {
      final double v = n / 1000;
      return '${v.toStringAsFixed(v < 100 ? 1 : 0)}k';
    }
    return '$n';
  }

  String get _subtitle {
    final String? desc = widget.repo.description;
    return (desc == null || desc.isEmpty) ? (widget.repo.language ?? '') : desc;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GhRepo repo = widget.repo;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        // ★ 批 9 · B18：Card 有圆角，水波纹必须同圆角裁剪，
        //   否则按下时方角溢出卡片轮廓。
        borderRadius: OgLRadius.cMd,
        onTap: () => unawaited(widget.onOpen(repo)),
        onLongPress: () => unawaited(widget.onActions(context, repo)),
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                repo.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: OgLSpace.xxs),
              Text(
                _subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              // README 切片：默认折叠（点击展开 / 再点收起），长文本不刷屏。
              if (widget.excerpt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: OgLSpace.xxs),
                  child: InkWell(
                    onTap: () =>
                        setState(() => _readmeExpanded = !_readmeExpanded),
                    borderRadius: OgLRadius.cXs,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: OgLSpace.xxs,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              widget.excerpt,
                              maxLines: _readmeExpanded ? null : 2,
                              overflow: _readmeExpanded
                                  ? null
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: OgLSpace.xxs),
                          Icon(
                            _readmeExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: OgLIconSize.sm,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: OgLSpace.sm),
              // meta 行：★数 · 语言 · 版本号。
              // ★ 批 11 信息密度：★ 数用紧凑记法（12.3k），语言与版本
              //   都折叠省略——此前语言占 Expanded、版本不折叠，长版本号
              //   （如 v1.2.3-beta.1+build）会把语言挤没。
              Row(
                children: <Widget>[
                  Icon(
                    Icons.star_border,
                    size: OgLIconSize.sm,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: OgLSpace.xxs),
                  Text(_compactCount(repo.stars),
                      style: theme.textTheme.bodySmall),
                  if (repo.language != null && repo.language!.isNotEmpty)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: OgLSpace.xxs),
                        child: Text(
                          ' · ${repo.language!}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  if (widget.version != null && widget.version!.isNotEmpty)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: OgLSpace.xxs),
                        child: Text(
                          widget.version!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
  }
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

  /// ★ B6-A-01：推荐 tab 的世代计数——分类切换 / 下拉刷新时自增，
  ///   在途 `_loadMoreRepos()` 回写前校验，防止旧分类数据混入新列表。
  int _repoGeneration = 0;
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
        // ★ 修复「动态不可用」：不用 auth.state 判登录——它由壳的
        //   _check 异步填充，发现页初始化时可能仍是 unknown，且同值
        //   短路后不再有通知。直接探测登录事实（activeAccount 非空，
        //   读的是保险库元数据，结果可靠），未登录返回空（如实显示
        //   「暂无动态」，不发注定 401 的请求）。
        final account = await widget.surface.domain.auth.activeAccount();
        if (account == null) {
          return <Map<String, dynamic>>[];
        }
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
    final int myGeneration = _repoGeneration;
    if (mounted) {
      setState(() {});
    }
    try {
      final List<GhRepo> page = await widget.surface.domain.api.searchRepos(
        _kCategoryQueries[_repoCategory],
        perPage: 10,
        page: _repoPage,
      );
      // ★ B6-A-01：请求期间分类可能已切换 / 刷新可能已重置——旧世代
      //   的一切回写（列表、页码、README/版本缓存）全部丢弃。
      if (myGeneration != _repoGeneration) {
        return;
      }
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
          if (myGeneration != _repoGeneration) {
            return;
          }
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
        List<Map<String, dynamic>> starred = const <Map<String, dynamic>>[];
        try {
          starred = starredQuery == null
              ? const <Map<String, dynamic>>[]
              : await widget.surface.domain.api.searchIssues(
                  'is:issue is:open $starredQuery',
                  sort: 'created',
                );
        } on Object catch (error) {
          // ★ B6-A-05：starred 请求失败时**保留 mine 的筛选集**——此前
          //   `_mineUrls` 已被覆盖成空，筛选行与数据版本不一致。
          OgLLogFile.line(
            'GH',
            'starred 议题聚合失败（仅保留 mine）：$error',
            level: 'ERR',
          );
        }
        _mineUrls
          ..clear()
          ..addAll(mine.map((Map<String, dynamic> e) => ghStr(e, 'html_url')));
        _starUrls
          ..clear()
          ..addAll(
            starred.map((Map<String, dynamic> e) => ghStr(e, 'html_url')),
          );
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
      final List<GhRepo> repos = await widget.surface.domain.api.starredRepos(
        perPage: 20,
      );
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

  /// 点击通知行：issue/PR → IssuePage；release → 仓库页；
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
        // 行的浏览器入口仍是兜底）。
      }
    }
    if (subjectUrl.isNotEmpty && mounted) {
      await openLinkOrCopy(context, subjectUrl, tag: 'Feed');
    }
  }

  /// 通知流条目 → 可读类型（元信息行用）。
  String _feedTypeOf(Map<String, dynamic> item) {
    final String type = _feedSubjectTypeOf(item);
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
        builder: (BuildContext context) =>
            RepoPage(surface: widget.surface, repo: repo),
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
        // ★ 批 9 · B2：TabBarView 的滑动由框架动画驱动（没有公开的
        //   duration 参数，再包 AnimatedSwitcher 只会双重动画）。
        //   档位 0 / 系统减少动效时禁用**拖拽换页的物理动画**，
        //   但点击 Tab 标签换页仍然可用 —— 降档 = 降质量，不砍功能。
        physics: OgLAnim.enabled(context)
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        children: <Widget>[
          _buildFeedTab(),
          _buildRecommendedTab(),
          _buildIssuesTab(),
        ],
      ),
    );
  }

  // ── tab 1：动态（官方通知流，紧凑行式信息流）────────────────────────

  /// 单条动态的紧凑行：4px 状态竖条（未读 primary / 已读透明）+
  /// 一行标题 + 一行元信息（仓库 · 类型 · 相对时间），行高 ≤64。
  ///
  /// ★ 行渲染委托给 [OgLFeedRow]：状态竖条若用
  ///   `Row(crossAxisAlignment: stretch)` 撑满行高，纵向 ListView 的
  ///   **无界**子项高度会让整行在 release 下不绘制（动态 tab 整页空白）。
  ///   详见 [OgLFeedRow] 的文档注释与回归测试。
  Widget _buildFeedRow(BuildContext context, Map<String, dynamic> item) {
    final String repoName = _feedRepoOf(item);
    final Object? subject = item['subject'];
    final String title = subject is Map<Object?, Object?>
        ? ghStr(Map<String, dynamic>.from(subject), 'title')
        : '';
    return OgLFeedRow(
      unread: _feedUnreadOf(item),
      title: title.isEmpty ? _t('feedRelease') : title,
      meta: '$repoName · ${_feedTypeOf(item)} · '
          '${_relativeTime(ghStr(item, 'updated_at'))}',
      onTap: () => unawaited(_openFeedItem(item)),
    );
  }

  Widget _buildFeedTab() => _feed == null
      ? _SkeletonList(key: const ValueKey<String>('feed-skeleton'))
      : OgLRefreshIndicator(
          onRefresh: () => _feed!.load(),
          child: AsyncView<List<Map<String, dynamic>>>(
            controller: _feed!,
            emptyIcon: Icons.notifications_none,
            emptyText: _t('feedEmpty'),
            builder: (BuildContext context, List<Map<String, dynamic>> items) =>
                ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: OgLSpace.sm),
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) =>
                  _buildFeedRow(context, items[index]),
            ),
          ),
        );

  // ── tab 2：推荐（双列网格 + 无限下拉）────────────────────────────────

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
                child: Text(_t('categoryRetry')),
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
        // ★ 批 11：改用 FilterChip 横滑行（复用 OgLIssuesFilterChips）——
        //   SegmentedButton 五档在窄屏接近临界溢出（audit_spec_b B17），
        //   且语言档此前是硬编码英文字面量（i18n 缺口）。两个 tab 的
        //   筛选控件统一为同一种行型，视觉语言一致、宽度永远自适应。
        Padding(
          padding: const EdgeInsets.symmetric(vertical: OgLSpace.sm),
          child: OgLIssuesFilterChips(
            selected: _repoCategory,
            labels: <String>[
              _t('catHot'),
              _t('catType'),
              _t('catDart'),
              _t('catFlutter'),
              _t('catRust'),
            ],
            onSelect: (int category) {
              if (category != _repoCategory) {
                setState(() {
                  _repoCategory = category;
                  _repoGeneration++; // ★ B6-A-01：作废在途旧分类请求
                  _repos.clear();
                  _readmeOf.clear();
                  _versionOf.clear();
                  _repoPage = 1;
                  _repoDone = false;
                  _repoError = null;
                  // ★ 修复「选语言后永远空」：在途旧请求仍占着 _repoLoading，
                  //   新分类的 _loadMoreRepos 会被防重入闸门直接 return，
                  //   列表已清空 → 永远「暂无推荐」。旧请求已被世代作废，
                  //   它的 finally 只复位自己的标志，这里同步解锁。
                  _repoLoading = false;
                });
                unawaited(_loadMoreRepos());
              }
            },
          ),
        ),
        Expanded(
          child: OgLRefreshIndicator(
            onRefresh: () async {
              _repoGeneration++; // ★ B6-A-01：作废在途旧页请求
              _repos.clear();
              _readmeOf.clear();
              _versionOf.clear();
              _repoPage = 1;
              _repoDone = false;
              await _loadMoreRepos();
            },
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // ★ 宽屏（≥600）双列拉满信息密度；窄屏单列。
                final int columns = constraints.maxWidth >= 600 ? 2 : 1;
                final int rows = (_repos.length + columns - 1) ~/ columns;
                return ListView.builder(
                  key: ValueKey<String>('repos-$_repoCategory-$columns'),
                  controller: _repoScroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    OgLSpace.md,
                    OgLSpace.sm,
                    OgLSpace.md,
                    OgLSpace.lg,
                  ),
                  // +1 尾行：加载中骨架或空占位。
                  itemCount: rows + 1,
                  itemBuilder: (BuildContext context, int row) {
                    if (row == rows) {
                      return _repoDone
                          ? const SizedBox.shrink()
                          : const Padding(
                              padding: EdgeInsets.all(OgLSpace.md),
                              child: _SkeletonRow(
                                key: ValueKey<String>('repos-more'),
                              ),
                            );
                    }
                    return Row(
                      key: ValueKey<String>('repos-row-$row-$columns'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (int col = 0; col < columns; col++)
                          Expanded(
                            child: row * columns + col < _repos.length
                                ? Padding(
                                    padding: const EdgeInsets.all(OgLSpace.xxs),
                                    child: _RepoCard(
                                      key: ValueKey<String>(
                                        'repo-${_repos[row * columns + col].fullName}',
                                      ),
                                      repo: _repos[row * columns + col],
                                      excerpt: _readmeOf[
                                              _repos[row * columns + col]
                                                  .fullName] ??
                                          '',
                                      version: _versionOf[
                                          _repos[row * columns + col].fullName],
                                      onOpen: _openRepo,
                                      onActions: _showRepoActions,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                      ],
                    );
                  },
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
        if (context.mounted) {
          OgLNotifier.of(context).info(_t('cloneCopied'));
        }
      case 'browser':
        if (!context.mounted) {
          return;
        }
        await openLinkOrCopy(
          context,
          'https://github.com/${repo.fullName}',
          tag: 'Repo',
        );
    }
  }

  // ── tab 3：Issues（紧凑行式 + FilterChip 横滑筛选）────────────────────

  /// Issues 筛选档 → chip 文案。
  String _issuesFilterLabel(int filter) => switch (filter) {
        1 => _t('issuesMine'),
        2 => _t('issuesStar'),
        _ => _t('issuesAll'),
      };

  Widget _buildIssuesTab() => Column(
        // ★ 修复「胶囊文字溢出」：Column 默认 crossAxisAlignment.center，
        //   子项按内容宽度收缩并居中——横向 ListView 于是按内容宽度定位，
        //   超出屏幕宽的部分被裁掉（实测首个胶囊左缘 x=28 被切）。
        //   stretch 让筛选行满宽。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 分类筛选：FilterChip 横滑行（比 SegmentedButton 省宽度，可扩档）。
          // ★ 高度由内容决定（此前写死 32dp，把标签文字挤到了胶囊之外）。
          OgLIssuesFilterChips(
            selected: _issuesFilter,
            labels: <String>[
              _issuesFilterLabel(0),
              _issuesFilterLabel(1),
              _issuesFilterLabel(2),
            ],
            onSelect: (int filter) {
              setState(() => _issuesFilter = filter);
            },
          ),
          Expanded(
            child: _issues == null
                ? _SkeletonList(key: const ValueKey<String>('issues-skeleton'))
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
                        padding:
                            const EdgeInsets.symmetric(vertical: OgLSpace.sm),
                        itemCount: shown.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> item = shown[index];
                          final bool mine = _mineUrls.contains(
                            ghStr(item, 'html_url'),
                          );
                          final bool mine = _mineUrls.contains(
                            ghStr(item, 'html_url'),
                          );
                          final ThemeData theme = Theme.of(context);
                          // ★ 批 11 信息密度：行首加状态色点（open=主色 /
                          //   closed=次色），一眼区分议题状态；"我提出的"
                          //   用 meta 前缀标注（原 person 图标语义不清）。
                          final String state = ghStr(item, 'state');
                          final Color stateColor = state == 'closed'
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary;
                          return InkWell(
                            key: ValueKey<String>(
                              'issue-${ghStr(item, 'html_url')}',
                            ),
                            onTap: () => unawaited(_openIssue(item)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: OgLSpace.lg,
                                vertical: OgLSpace.sm,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: OgLSpace.xxs,
                                    height: OgLSpace.xxs,
                                    decoration: BoxDecoration(
                                      color: stateColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: OgLSpace.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          ghStr(item, 'title'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: OgLSpace.xxs),
                                        Text(
                                          '${mine ? '@me · ' : ''}'
                                          '${_repoFullOf(item)} '
                                          '#${ghInt(item, 'number')} · '
                                          '${ghLogin(item)} · '
                                          '${_relativeTime(ghStr(item, 'created_at'))}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: OgLSpace.sm),
                                  // 右侧：评论数 + 进入箭头。
                                  Semantics(
                                    label: _t('issuesComments', {
                                      'count': ghInt(item, 'comments'),
                                    }),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          size: OgLIconSize.sm,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: OgLSpace.xxs),
                                        Text(
                                          '${ghInt(item, 'comments')}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(width: OgLSpace.xxs),
                                        Icon(
                                          Icons.chevron_right,
                                          size: OgLIconSize.md,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
              .map(
                (GhRepo repo) => _SearchHit(
                  title: repo.fullName,
                  subtitle: _repoSubtitle(repo),
                  repo: repo,
                ),
              )
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
          final String text = ghStr(
            Map<String, dynamic>.from(match),
            'fragment',
          ).trim();
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
              OgLSpace.lg,
              OgLSpace.md,
              OgLSpace.lg,
              OgLSpace.xxs,
            ),
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
                          leading: Icon(
                            hit.initialPath == null
                                ? Icons.folder_outlined
                                : Icons.description_outlined,
                          ),
                          title: Text(
                            hit.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            hit.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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
