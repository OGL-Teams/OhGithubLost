/// L3 展示级 · 仓库详情页（八标签 + 分支切换）。
///
/// ## 4.1 仓库浏览增强
/// - **分支切换**：AppBar 下方常驻分支栏，切换后代码 / 提交 / 发布 / Actions 同步；
/// - **新建文件**：代码标签提供 FAB 入口；
/// - **目录内筛选**：当前目录按名称过滤；
/// - **图片预览**：图片文件直接在应用内预览（不再显示二进制乱码）；
/// - **分页**：仓库列表与仓库页各列表统一「加载更多」。
///
/// ## 控件规范
/// 全部使用 Material 3；「新建」类主操作统一为 [FloatingActionButton]，
/// 次要操作收进 [PopupMenuButton]，空/错/载三态统一收敛。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/accel.dart';
import '../util/clipboard_x.dart';
import '../util/file_icons.dart';
import '../util/file_preview.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../util/path_rules.dart';
import '../widgets/anim/anim_preload.dart';
import '../widgets/code_editor_field.dart';
import '../widgets/readme_view.dart';
import '../widgets/scroll_aware_action.dart';
import 'action_run_page.dart';
import 'code_editor_page.dart';
import 'commit_page.dart';
import 'file_preview_page.dart';
import 'issue_page.dart';
import 'new_issue_page.dart';
import 'new_release_page.dart';
import 'pull_page.dart';
import 'release_detail_page.dart';
import 'workflow_dispatch_page.dart';

/// 取 `repo` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('repo', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 每页条数（统一）。
const int _kPageSize = 30;

/// 重负载端点（发布 / Actions）每页条数。
///
/// 这两类响应**单条就很大**（发布含全部附件、Actions 含全部作业），
/// 按 30 条一次拉取会产出数百 KB 到数 MB 的响应体——既慢，又容易在弱网下中断。
const int _kHeavyPageSize = 10;

// ── 分级预加载（页面级登记）─────────────────────────────────────────────
// 本页是 **push 出来的路由**（首页 / 搜索页），所以作用域用 `route:repo:<fullName>`：
// push 方会用**同名**的 `OgLAnimPreloadBoundary` 把本页包起来 —— pop 即整组取消、
// 归还额度（见 `dashboard_page._openRepo` / `search_page._open`）。
// 档位口径全在 `widgets/anim/anim_preload.dart` 的策略表里；这里只登记。

/// 本页的路由作用域（`route:repo:<fullName>`）。
///
/// ★ 跨文件约定：`dashboard_page` / `search_page` 的 push 侧用**同一条**字符串 ——
/// 只有逐字一致，父子两层才是同一个作用域。
String _preloadGroupOf(String fullName) => 'route:repo:$fullName';

/// owner 头像的幂等键（同一资源同一 id）。
///
/// ★ 跨文件约定：push 方在跳转前会用 `childLevel` 先登记**同一个 id**
///（档位 3 时抢在本页首帧之前解码）—— 所以这里的重复登记是安全的、无成本的。
String _ownerAvatarId(String fullName) => 'avatar:repo:$fullName';

/// 头像的**估算**内存（GitHub 头像 10–40 KB 量级）。
///
/// 图片项的默认估算是 2 MiB；按默认给会让几项就吃掉大半内存额度。
const int _kAvatarBytes = 96 * 1024;

/// README 图片的**估算**内存：渲染侧把它压到 320 高，但解码出来的是原图，
/// 按截图量级估 512 KiB。
const int _kReadmeImageBytes = 512 * 1024;

/// **子层级**预登记的 README 图片张数。
///
/// 一篇 README 动辄几十张图：整篇登记会瞬间打满数量 / 内存额度，所以只取头两张。
const int _kReadmeImageLeads = 2;

/// README 图片地址的提取正则（形状与渲染层解析 `![alt](url "title")` 一致）。
final RegExp _kReadmeImageSource =
    RegExp(r'!\[[^\]]*\]\(([^)\s]*)(?:\s+"[^"]*")?\)');

/// 仓库详情页。
class RepoPage extends StatefulWidget {
  /// 创建页面。
  const RepoPage({
    required this.surface,
    required this.repo,
    this.initialPath,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库。
  final GhRepo repo;

  /// 初始路径（从代码搜索直达；可空）。
  final String? initialPath;

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  late GhRepo _repo = widget.repo;
  late String _branch = widget.repo.defaultBranch;
  bool _starred = false;
  bool _starBusy = false;
  bool _forkBusy = false;

  String get _full => _repo.fullName;

  /// 代码标签当前目录（**由页面持有**：`TabBarView` 会销毁不可见标签页，
  /// 目录若跟着标签 State 一起消失，切走再切回就回到根目录）。
  String _codePath = '';

  /// 代码搜索直达文件：只在首次交给代码标签，之后由 [_codePath] 接管，
  /// 避免标签页重建时反复跳回初始文件。
  String? _codeInitialPath;

  @override
  void initState() {
    super.initState();
    _codeInitialPath = widget.initialPath;
    unawaited(_loadStarred());
    unawaited(_loadRepoPermissions());
    // 分级预加载：本页主视觉的图片资源 = 仓库 owner 头像（`currentPage`：档位 ≥1）。
    // 只登记**一项** —— 目录 / 列表里的图片交给 `OgLReveal` 的视口驱动，
    // 逐项登记既会打满上限，也和视口驱动重复。
    _preloadOwnerAvatar();
  }

  /// 登记 owner 头像（幂等：同一个 id 只跑一次）。
  ///
  /// 与 push 侧的关系：首页 / 搜索页在跳转前会先按 `childLevel` 登记**同一个 id**。
  /// 档位 3 下那条先跑（本页首帧前就已经在解码）；档位 1 / 2 下那条被策略表拒收，
  /// 于是由本条按 `currentPage` 登记 —— 两种档位各走各的路，且永远不会解两遍。
  void _preloadOwnerAvatar() {
    final String? url = _repo.owner.avatarUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    if (OgLAnimPreload.register(
      OgLAnimPreloadJob.image(
        id: _ownerAvatarId(_full),
        group: _preloadGroupOf(_full),
        kind: OgLAnimPreloadKind.currentPage,
        image: NetworkImage(url),
        weightBytes: _kAvatarBytes,
      ),
    )) {
      OgLAnimPreload.schedule();
    }
  }

  /// 拉取**单仓库详情**（`GET /repos/{owner}/{repo}`）。
  ///
  /// 为什么必须做：`permissions`（写权限）**只有该接口会返回**——
  /// 收藏 / 搜索 / 列表接口都不带它。若只用 `widget.repo`，则 `canPush` 恒为
  /// null → 连自己的仓库也会被判定为"不可写"，写入口全部消失。
  Future<void> _loadRepoPermissions() async {
    try {
      final GhRepo fresh = await widget.surface.domain.api.repo(_full);
      if (!mounted) {
        return;
      }
      setState(() {
        _repo = fresh;
        if (_branch.isEmpty) {
          _branch = fresh.defaultBranch;
        }
      });
    } catch (error) {
      // 拿不到详情**不静默**：留痕（通知中心可见）；此时按"不可写"处理。
      OgLAppLog.instance.add(
        '仓库',
        _t('readFailedWritePerm', {'error': error}),
        severity: OgLNoticeSeverity.warning,
      );
    }
  }

  Future<void> _loadStarred() async {
    try {
      final bool starred = await widget.surface.domain.api.isRepoStarred(_full);
      if (mounted) {
        setState(() => _starred = starred);
      }
    } catch (_) {
      // 未登录 / 无权限：保持未星标状态即可，不打扰用户。
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleStar() async {
    if (_starBusy) {
      return;
    }
    setState(() => _starBusy = true);
    final bool target = !_starred;
    try {
      await widget.surface.domain.api.setStarred(_full, target);
      OgLAppLog.instance.result('仓库', target ? _t('starred') : _t('unstarred'), _full);
      if (mounted) {
        setState(() => _starred = target);
        _toast(target ? _t('starred') : _t('unstarred'));
      }
    } catch (error) {
      _toast(_t('actionFailed', {'error': error}));
    } finally {
      if (mounted) {
        setState(() => _starBusy = false);
      }
    }
  }

  Future<void> _fork() async {
    if (_forkBusy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('forkTitle')),
        content: Text(_t('forkDesc', {'full': _full})),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('fork')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _forkBusy = true);
    try {
      final GhRepo forked = await widget.surface.domain.api.fork(_full);
      OgLAppLog.instance.result('仓库', _t('forked'), forked.fullName);
      _toast(_t('forkedAs', {'name': forked.fullName}));
    } catch (error) {
      _toast(_t('forkFailed', {'error': error}));
    } finally {
      if (mounted) {
        setState(() => _forkBusy = false);
      }
    }
  }

  void _openInBrowser() {
    final String url = _repo.htmlUrl ?? 'https://github.com/${_repo.fullName}';
    unawaited(openLinkOrCopy(context, url, tag: '仓库'));
  }

  Future<void> _copyCloneUrl() async {
    if (!await ogLCopyText('https://github.com/$_full.git',
        tag: 'Repo')) {
      return;
    }
    _toast(_t('cloneUrlCopied'));
  }

  /// 选择分支（Material 底部弹层 + 搜索）。
  Future<void> _pickBranch() async {
    List<GhBranch> branches;
    try {
      branches = await widget.surface.domain.api
          .branches(_full, perPage: 100);
    } catch (error) {
      _toast(_t('branchesFailed', {'error': error}));
      return;
    }
    if (!mounted) {
      return;
    }
    final String? picked = await ogLShowSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _BranchSheet(
        branches: branches,
        current: _branch,
        defaultBranch: _repo.defaultBranch,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    final String next = picked == _kDefaultBranchMark ? _repo.defaultBranch : picked;
    if (next == _branch) {
      return;
    }
    setState(() {
      _branch = next;
      // 换分支后目录回到根：新分支不一定存在同一条路径。
      _codePath = '';
    });
    OgLAppLog.instance.result('仓库', _t('branchSwitched'), next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String branchKey = _branch.isEmpty ? 'default' : _branch;
    // R3：只有对自己有 push 权限的仓库才暴露"写入类"入口（新建文件 / 仓库设置）。
    // 判据唯一：`repo.permissions.push`（缺失 = 不可写，不做降级猜测）。
    final bool canWrite = _repo.isWritable;
    final List<Tab> tabs = <Tab>[
      Tab(text: OgLI18n.instance.t('repo', 'code')),
      Tab(text: OgLI18n.instance.t('repo', 'issues')),
      Tab(text: OgLI18n.instance.t('repo', 'pulls')),
      Tab(text: OgLI18n.instance.t('repo', 'releases')),
      Tab(text: OgLI18n.instance.t('repo', 'branches')),
      Tab(text: OgLI18n.instance.t('repo', 'commits')),
      Tab(text: OgLI18n.instance.t('repo', 'actions')),
      if (canWrite) Tab(text: OgLI18n.instance.t('repo', 'repoSettings')),
    ];
    final List<Widget> tabViews = <Widget>[
      _CodeTab(
        key: ValueKey<String>('code-$branchKey'),
        surface: widget.surface,
        fullName: _full,
        branch: _branch,
        canWrite: canWrite,
        // 这里在 _RepoPageState 内部，`widget.repo` 才是有效的。
        repoPrivate: widget.repo.isPrivate,
        initialPath: _codeInitialPath,
        path: _codePath,
        onPathChanged: (String path) => setState(() => _codePath = path),
        onInitialPathConsumed: () => setState(() => _codeInitialPath = null),
      ),
      _IssuesTab(surface: widget.surface, fullName: _full),
      _PullsTab(surface: widget.surface, fullName: _full),
      _ReleasesTab(
        key: ValueKey<String>('rel-$branchKey'),
        surface: widget.surface,
        fullName: _full,
        branch: _branch,
        canWrite: canWrite,
      ),
      _BranchesTab(
        surface: widget.surface,
        fullName: _full,
        defaultBranch: _repo.defaultBranch,
        onBranchChanged: () => setState(() {}),
        canWrite: canWrite,
      ),
      _CommitsTab(
        key: ValueKey<String>('cmt-$branchKey'),
        surface: widget.surface,
        fullName: _full,
        branch: _branch,
      ),
      _ActionsTab(
        key: ValueKey<String>('act-$branchKey'),
        surface: widget.surface,
        fullName: _full,
        branch: _branch,
      ),
      if (canWrite)
        _RepoSettingsTab(
          surface: widget.surface,
          repo: _repo,
          onRepoChanged: (GhRepo fresh) => setState(() => _repo = fresh),
        ),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: OgLSharedTitle(
            tag: 'ogl-repo:${_repo.fullName}',
            child: Text(_repo.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          actions: <Widget>[
            IconButton(
              icon: Icon(_starred ? Icons.star : Icons.star_border),
              tooltip: _starred ? _t('unstar') : _t('star'),
              onPressed: _starBusy ? null : _toggleStar,
            ),
            PopupMenuButton<String>(
              tooltip: _t('more'),
              onSelected: (String value) {
                switch (value) {
                  case 'fork':
                    unawaited(_fork());
                  case 'browser':
                    _openInBrowser();
                  case 'clone':
                    unawaited(_copyCloneUrl());
                }
              },
              itemBuilder: (BuildContext context) =>
                   <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'fork',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.call_split),
                    title: Text(_t('forkTitle')),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'clone',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.link),
                    title: Text(_t('copyCloneUrl')),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'browser',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.open_in_new),
                    title: Text(_t('openInBrowser')),
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              children: <Widget>[
                _branchBar(theme),
                TabBar(
                  isScrollable: true,
                  tabs: tabs,
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(children: tabViews),
      ),
    );
  }

  Widget _branchBar(ThemeData theme) => Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Semantics(
          // 分支选择条是「打开选择器」的按钮：屏幕阅读器需要可读标签，
          // 否则用户只看到一行分支名，不知道可以点。
          button: true,
          label: _t('selectBranch'),
          child: InkWell(
            onTap: _pickBranch,
            // 触控目标 ≥ 48dp（原 ~34dp，密集点按容易点偏）；
            // 内容垂直居中，视觉上只是略微变高。
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _branch.isEmpty ? _t('defaultBranch') : _branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (_branch == _repo.defaultBranch)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(_t('defaultLabel'), style: theme.textTheme.bodySmall),
                  ),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      ),
    );
  }

/// 分支弹层的「默认分支」标记值。
const String _kDefaultBranchMark = '\u0000default';

/// 分支选择弹层（搜索 + 列表）。
class _BranchSheet extends StatefulWidget {
  const _BranchSheet({
    required this.branches,
    required this.current,
    required this.defaultBranch,
  });

  final List<GhBranch> branches;
  final String current;
  final String defaultBranch;

  @override
  State<_BranchSheet> createState() => _BranchSheetState();
}

class _BranchSheetState extends State<_BranchSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<GhBranch> shown = widget.branches
        .where((GhBranch b) =>
            _filter.isEmpty ||
            b.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              decoration:  InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                hintText: _t('searchBranch'),
              ),
              onChanged: (String value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ?  Center(child: Text(_t('noMatchingBranch')))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (BuildContext context, int index) {
                      final GhBranch branch = shown[index];
                      final bool isCurrent = branch.name == widget.current;
                      final bool isDefault =
                          branch.name == widget.defaultBranch;
                      return ListTile(
                        leading: Icon(
                          branch.isProtected
                              ? Icons.lock_outline
                              : Icons.account_tree_outlined,
                        ),
                        title: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${ghShortSha(branch.sha)}'
                          '${isDefault ? _t('defaultBranchTag') : ''}'
                          '${branch.isProtected ? _t('protectedTag') : ''}',
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check, color: theme.colorScheme.primary)
                            : null,
                        onTap: () => Navigator.of(context).pop(branch.name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 分页控制器与统一列表渲染
// ─────────────────────────────────────────────────────────────────────────────

/// 清空所有"按目标缓存"的分页快照。
///
/// **切换账号时必须调用**：快照里可能含上一个账号可见的私有数据
/// （用户要求：切号清除所有缓存）。
void clearOgLRepoPageCaches() => _recentPage.clear();

/// 一次成功的分页快照（供同目标的标签页重建后"秒开"，避免重复请求）。
class _CachedPage {
  const _CachedPage(this.at, this.items, this.done, this.page);

  final DateTime at;
  final List<Object?> items;
  final bool done;
  final int page;
}

/// 分页快照缓存（按 `cacheKey` 隔离）。
final Map<String, _CachedPage> _recentPage = <String, _CachedPage>{};

/// 快照有效期：过期即回源。
const Duration _kPageCacheTtl = Duration(seconds: 6);

/// 通用分页数据源（首屏 + 加载更多 + 下拉刷新）。
class _Paged<T> extends ChangeNotifier {
  _Paged({required this.loader, this.pageSize = _kPageSize, this.cacheKey, this.onManualRefresh});

  final Future<List<T>> Function(int page) loader;
  final int pageSize;

  /// 用户在"下拉刷新 / 写后重载"（`force` 为真）时回调：
  /// 用于让**只读端点缓存**失效，确保刷新一定回源（R4）。
  final Future<void> Function()? onManualRefresh;

  /// 快照键：同一目标（仓库 / 分支 / 目录 / 滤器）共用一个键。
  ///
  /// 为什么需要：`TabBarView` 会销毁不可见页，切回来时 State 重建 →
  /// 每个标签都会重新拉取，短时间内把同一端点连打数次（配额与带宽白烧）。
  /// 有了快照，重建即秒开、不再重复请求。目录 / 滤器会变化的目标，
  /// 由调用方在加载前更新本键。
  String? cacheKey;

  final List<T> items = <T>[];
  int _page = 1;
  bool loading = false;
  bool done = false;
  bool _everLoaded = false;
  bool _everFailed = false;
  String? error;

  /// 已释放标记（释放后不再通知 / 不再回写）。
  bool _disposed = false;

  /// 刷新排队标记：刷新请求在途时置位，当前请求结束后**重放**。
  bool _refreshQueued = false;

  /// 请求代次：每次刷新 +1；过期响应（旧代次）一律丢弃。
  ///
  /// 修掉两个真实竞态：切「打开 / 已关闭 / 全部」时在途请求未结束 →
  /// 刷新被静默丢弃（按钮与数据不符）；写后重载与在途加载交错 →
  /// 重复条目 / 第一页缺失。
  int _generation = 0;

  /// 释放后不再通知（在途回写静默丢弃）。
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  /// 未显式要求时：首次加载按"自动"处理（可用快照），
  /// 之后一律按"显式"处理（用户下拉刷新 / 写后重载，必须真的回源）。
  bool get _shouldForce => _everLoaded || _everFailed;

  Future<void> loadMore() => _load(force: false);

  Future<void> refresh() {
    // 先作废在途请求：它的响应属于"上一代"（旧筛选 / 旧快照）。
    _generation++;
    if (loading) {
      // 在途请求未结束：**排队重放**，而不是静默丢弃这次刷新。
      _refreshQueued = true;
      return Future<void>.value();
    }
    return _load(force: _shouldForce, reset: true);
  }

  Future<void> _load({required bool force, bool reset = false}) async {
    if (_disposed || loading) {
      return;
    }
    final int generation = _generation;
    final String? key = cacheKey;
    if (!force && reset && key != null) {
      final _CachedPage? cached = _recentPage[key];
      if (cached != null &&
          DateTime.now().difference(cached.at) < _kPageCacheTtl) {
        // 命中快照：直接展示，不发请求（重建的标签页因此"秒开"）。
        items
          ..clear()
          ..addAll(cached.items.whereType<T>());
        done = cached.done;
        _page = cached.page;
        error = null;
        _everLoaded = true;
        _notify();
        return;
      }
    }
    if (reset) {
      // 用户显式刷新 → 让只读端点缓存失效，保证真的回源（R4）。
      // GhReadCache.clear 自身不抛异常，这里无需再包 try。
      if (force && onManualRefresh != null) {
        await onManualRefresh!();
      }
      items.clear();
      _page = 1;
      done = false;
      error = null;
    } else if (done) {
      return;
    }
    loading = true;
    error = null;
    _notify();
    try {
      final List<T> list = await loader(_page);
      if (_disposed || generation != _generation) {
        // 过期响应：期间用户已刷新 / 切换筛选，这份数据不再可信。
        return;
      }
      items.addAll(list);
      if (list.length < pageSize) {
        done = true;
      }
      _page++;
      _everLoaded = true;
      if (key != null) {
        _recentPage[key] = _CachedPage(
          DateTime.now(),
          List<Object?>.of(items),
          done,
          _page,
        );
      }
    } catch (e) {
      if (_disposed || generation != _generation) {
        return;
      }
      error = '$e';
      _everFailed = true;
    } finally {
      loading = false;
      _notify();
      if (_refreshQueued && !_disposed) {
        // 在途请求结束后重放排队中的刷新（快速操作不再被吞掉）。
        _refreshQueued = false;
        unawaited(refresh());
      }
    }
  }
}

/// 统一渲染分页列表（空 / 错 / 载三态 + 加载更多 + 下拉刷新）。
///
/// [items] 为空时渲染 `paged.items` 全量；给了则只渲染该子集
/// （用于**客户端筛选**：筛选只影响展示，不影响分页状态）。
///
/// [controller] 由接入 `ScrollAwareAction` 的标签页传入：收边判定需要读
/// 同一个滚动视图的位置（`pixels` / `maxScrollExtent` / `viewportDimension`）。
Widget _pagedBody<T>(
  BuildContext context,
  _Paged<T> paged,
  Widget Function(BuildContext context, T item, int index) itemBuilder, {
  required String emptyText,
  IconData emptyIcon = Icons.inbox_outlined,
  Widget? emptyAction,
  List<T>? items,
  ScrollController? controller,
}) {
  final List<T> list = items ?? paged.items;
  if (paged.items.isEmpty && paged.loading) {
    return const Center(child: CircularProgressIndicator());
  }
  if (paged.items.isEmpty && paged.error != null) {
    return _MessagePane(
      icon: Icons.error_outline,
      message: paged.error!,
      action: FilledButton.tonal(
        onPressed: paged.refresh,
        child:  Text(_t('retry')),
      ),
    );
  }
  if (paged.items.isEmpty) {
    return _MessagePane(icon: emptyIcon, message: emptyText, action: emptyAction);
  }
  return RefreshIndicator(
    onRefresh: paged.refresh,
    child: ListView.separated(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: list.length + (paged.done ? 0 : 1),
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == list.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: paged.loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: paged.loadMore,
                      child: Text(_t('loadMore', {'count': paged.items.length})),
                    ),
            ),
          );
        }
        return OgLReveal(
          delay: OgLAnim.staggerOf(context, index),
          child: itemBuilder(context, list[index], index),
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 代码标签
// ─────────────────────────────────────────────────────────────────────────────

class _CodeTab extends StatefulWidget {
  const _CodeTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    required this.canWrite,
    required this.repoPrivate,
    required this.path,
    required this.onPathChanged,
    required this.onInitialPathConsumed,
    this.initialPath,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  /// 仓库是否私有 —— 决定仓库文件的取法：私有只能走 API 带认证
  /// （raw 没有签名机制，交给代理等于送令牌）。
  final bool repoPrivate;

  /// 当前用户是否对该仓库有写权限（`permissions.push`，不允许降级猜测）。
  final bool canWrite;

  /// 当前目录（**由 `RepoPage` 持有**，标签页被销毁重建后不丢）。
  final String path;

  /// 目录变化回调（把新目录写回 `RepoPage`）。
  final ValueChanged<String> onPathChanged;

  /// 直达路径（代码搜索）已消费回调（只跳一次，不反复跳回）。
  final VoidCallback onInitialPathConsumed;

  final String? initialPath;

  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab> {
  /// 当前目录：由页面（[RepoPage]）持有 —— 标签页会随 `TabBarView`
  /// 销毁重建，目录必须活在页面级，切走再切回才不会回到根目录。
  String get _path => widget.path;
  late final _Paged<GhContent> _entries = _Paged<GhContent>(
    loader: _loadPage,
    cacheKey: _keyFor(''),
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );
  final TextEditingController _filter = TextEditingController();
  final TextEditingController _newPath = TextEditingController();

  /// 文件列表滚动位置：`ScrollAwareAction` 读它判定「收边 / 弹回 / 近底部」。
  final ScrollController _scroll = ScrollController();

  GhContent? _file;
  bool _busy = false;
  String? _readme;
  bool _readmeTried = false;

  /// 目录列表"是否强制回源"（下拉刷新 / 写操作后置真；平时走缓存）。
  bool _forceList = false;

  String _keyFor(String path) =>
      'code:${widget.fullName}:${widget.branch}:$path';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  @override
  void dispose() {
    _entries.dispose();
    _filter.dispose();
    _newPath.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final String? initial = widget.initialPath;
    if (initial != null && initial.isNotEmpty) {
      // 直达路径只消费一次（否则每次标签页重建都会跳回初始文件）。
      widget.onInitialPathConsumed();
      await _openPath(initial);
      return;
    }
    if (widget.path.isNotEmpty) {
      // 标签页被切走后重建：回到页面持有的目录（不重置到根目录），
      // 快照键跟随目录，避免拿到"上一个目录"的快照。
      _entries.cacheKey = _keyFor(widget.path);
      await _entries.refresh();
      return;
    }
    await _entries.refresh();
    unawaited(_loadReadme());
  }

  /// 目录内容一次性返回（Contents API 不分页），因此第 2 页起即结束。
  ///
  /// 缓存交给底座：默认走缓存（目录 TTL 1 分钟），仅下拉刷新 / 写操作后
  /// （[_forceList]）才强制回源——此前这里恒为 `true`，导致缓存永不命中、
  /// 每次切目录 / 切标签都重新下载。
  Future<List<GhContent>> _loadPage(int page) async {
    if (page > 1) {
      return const <GhContent>[];
    }
    final bool force = _forceList;
    _forceList = false;
    return widget.surface.domain.api.listDirectory(
      widget.fullName,
      _path,
      branch: widget.branch,
      refresh: force,
    );
  }

  /// 重新拉取当前目录（[force] 为真时绕过 HTTP 缓存）。
  Future<void> _reload({bool force = true}) async {
    _forceList = force;
    await _entries.refresh();
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadReadme() async {
    if (_readmeTried) {
      return;
    }
    _readmeTried = true;
    try {
      final String? text =
          await widget.surface.domain.api.readme(widget.fullName);
      if (mounted) {
        setState(() => _readme = text);
      }
      if (mounted && text != null && text.isNotEmpty) {
        // README 正文到手才知道里面有哪些图 —— 于是就在这里做**子层级**登记。
        unawaited(_preloadReadmeImages(text));
      }
    } catch (_) {
      // README 缺失不是错误。
    }
  }

  /// **子层级**预登记：README 面板（`ExpansionTile`，**展开前不构建**子项）里的
  /// 头几张图。
  ///
  /// 为什么按 [OgLAnimPreloadKind.childLevel] 登记：这块内容要用户点开 README 才
  /// 出现 —— 正是库文档里"即将展开的**子层级**"的口径（**仅档位 3** 准入；
  /// 档位 1 / 2 会被策略表拒收，不在这里判档位）。
  ///
  /// 只登记**渲染路径真的会走 `Image.network` 的地址**：
  /// - 第三方绝对地址（`https://…`）本来就直连；
  /// - 仓库内相对路径**只有在加速通道给出代理前缀时**才走 `raw + 代理`
  ///  （见 [_readmeImagePlan]）；否则渲染层退回"API 取字节"（`Image.memory`），
  ///   那条路预加载**命中不了** —— 登记它只是白花钱，所以这里跳过。
  Future<void> _preloadReadmeImages(String markdown) async {
    final List<String> sources = _readmeImageSources(markdown);
    if (sources.isEmpty) {
      return;
    }
    // 与渲染层**同一套**取法参数（基址 / 代理前缀）。
    //
    // ⚠️ 本树（web）的 [_readmeImagePlan] 只返回 `(base, proxy)`、**没有 headers**：
    // 渲染层是 `Image.network(url)`（不带认证头），所以这里登记的 `NetworkImage`
    // 也不带头（`NetworkImage` 的相等性含 headers —— 多传一个空 map 就会变成
    // 另一条缓存条目，等于白解一遍）。
    final ({Uri? base, String? proxy}) plan = _readmeImagePlan('');
    final String proxy = plan.proxy ?? '';
    final Uri? base = plan.base;
    if (!mounted) {
      // 页面已经离开：不为"人已经走了"的页面占额度。
      return;
    }
    bool registered = false;
    int taken = 0;
    for (final String src in sources) {
      if (taken >= _kReadmeImageLeads) {
        break;
      }
      final Uri? direct = Uri.tryParse(src);
      Uri? url;
      if (direct != null && direct.hasScheme) {
        url = resolveReadmeImageUri(src);
      } else if (proxy.isNotEmpty) {
        final Uri? raw = resolveReadmeImageUri(src, base: base);
        if (raw != null) {
          url = Uri.parse('$proxy$raw');
        }
      }
      if (url == null) {
        continue;
      }
      taken++;
      registered = OgLAnimPreload.register(
            OgLAnimPreloadJob.image(
              // 幂等键 = 真正要取的那张图：同一个地址（同一资源）只会登记一次。
              id: 'readme-img:${widget.fullName}:$url',
              group: _preloadGroupOf(widget.fullName),
              kind: OgLAnimPreloadKind.childLevel,
              image: NetworkImage(url.toString()),
              weightBytes: _kReadmeImageBytes,
            ),
          ) ||
          registered;
    }
    if (registered) {
      OgLAnimPreload.schedule();
    }
  }

  /// 从 README 原文里取头几个图片地址。
  ///
  /// 先跑一次与渲染层**完全相同**的净化 [simplifyReadme]：HTML `<img>` 会被规范成
  /// Markdown 图、**徽章行整行删除**（shields.io 之类的装饰图不该占预加载额度）、
  /// 超长按行截断 —— 于是这里取到的地址就是渲染层真会加载的那些。
  List<String> _readmeImageSources(String markdown) {
    final List<String> out = <String>[];
    for (final RegExpMatch match
        in _kReadmeImageSource.allMatches(simplifyReadme(markdown))) {
      final String src = (match.group(1) ?? '').trim();
      if (src.isEmpty || out.contains(src)) {
        continue;
      }
      out.add(src);
      // 多取几个候选：头几个可能落在"API 取字节"那条路上（见上文的跳过规则）。
      if (out.length >= _kReadmeImageLeads * 2) {
        break;
      }
    }
    return out;
  }
  Future<void> _goTo(String path) async {
    setState(() => _file = null);
    // 目录写回页面（标签页重建后仍是这个目录）。
    widget.onPathChanged(path);
    // 快照键跟随目录：否则标签页重建后会拿到"上一个目录"的快照。
    _entries.cacheKey = _keyFor(path);
    await _entries.refresh();
    if (path.isEmpty) {
      _readmeTried = false;
      await _loadReadme();
    }
  }

  Future<void> _openPath(String path) async {
    setState(() => _busy = true);
    try {
      // 走缓存（30 秒 TTL）：同一文件短时间内重复打开不再回源。
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        path,
        branch: widget.branch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        _toast(_t('pathNotFound', {'path': path}));
        return;
      }
      if (content.isDirectory) {
        await _goTo(content.path);
      } else {
        setState(() => _file = content);
      }
    } catch (error) {
      _toast(_t('readFailed', {'error': error}));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 点击文件的**默认行为**。
  ///
  /// 位图与音频「当文本看」毫无意义（二进制是乱码），所以直接进预览；
  /// SVG / XML / 其它文本仍走既有的内联查看 —— 源码本身是有意义的内容，
  /// 想渲染的话从「打开方式」里选。
  void _openEntryDefault(GhContent entry) {
    final OgLPreviewKind kind = ogLPreviewKindOf(entry.path);
    if (ogLPreviewFirst(kind)) {
      unawaited(_openPreview(entry, kind));
      return;
    }
    unawaited(_openFile(entry));
  }

  /// 打开预览页。
  Future<void> _openPreview(GhContent entry, OgLPreviewKind kind) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (BuildContext context) => FilePreviewPage(
          surface: widget.surface,
          fullName: widget.fullName,
          path: entry.path,
          branch: widget.branch,
          kind: kind,
          repoPrivate: widget.repoPrivate,
          size: entry.size,
        ),
      ));

  /// 「打开方式」：同一份文件在不同场景下要用不同方式看。
  ///
  /// 默认项排在最前并标出 —— 图片默认就是渲染出来看，SVG 默认看源码。
  Future<void> _showOpenWith(GhContent entry) async {
    final ThemeData theme = Theme.of(context);
    final OgLPreviewKind kind = ogLPreviewKindOf(entry.path);
    await ogLShowSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(OgLI18n.instance.t('common', 'openWith')),
              subtitle: Text(
                ghPathName(entry.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            // ① 内置预览（默认项）
            ListTile(
              leading: Icon(
                ogLCanRenderInline(kind)
                    ? Icons.image_outlined
                    : Icons.preview_outlined,
              ),
              title: Text(OgLI18n.instance.t('common', ogLPreviewKindKey(kind))),
              trailing: Chip(
                label: Text(_t('defaultAction')),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_openPreview(entry, kind));
              },
            ),
            // ② 编辑器：**仅文本类**可进。位图 / 音频等二进制按文本解码
            //（`allowMalformed`）会产出乱码，保存后就是"用乱码覆盖原文件" ——
            // 这是数据损坏路径，必须拦在入口。
            ListTile(
              enabled: ogLCanEditAsText(kind),
              leading: const Icon(Icons.edit_outlined),
              title: Text(OgLI18n.instance.t('common', 'openInEditor')),
              subtitle: ogLCanEditAsText(kind)
                  ? null
                  : Text(_t('binaryNoEdit')),
              onTap: ogLCanEditAsText(kind)
                  ? () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_openEditor(entry));
                    }
                  : null,
            ),
            // ③ 浏览器
            ListTile(
              leading: const Icon(Icons.public),
              title: Text(_t('openInBrowser')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openFileInBrowser(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(GhContent entry) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      // 走缓存（30 秒 TTL）。
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        entry.path,
        branch: widget.branch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        _toast(_t('readFailedFileGone'));
        return;
      }
      setState(() => _file = content);
    } catch (error) {
      _toast(_t('readFailed', {'error': error}));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openEditor(GhContent file) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CodeEditorPage(
          surface: widget.surface,
          fullName: widget.fullName,
          path: file.path,
          initialText: file.text ?? '',
          baseSha: file.sha,
          branch: widget.branch,
        ),
      ),
    );
    if (mounted) {
      await _refreshFile(file.path);
      await _reload();
    }
  }

  Future<void> _refreshFile(String path) async {
    try {
      // 刚从编辑器写回：必须回源（写路径已失效本地缓存，这里是双保险）。
      final GhContent? fresh = await widget.surface.domain.api.content(
        widget.fullName,
        path,
        branch: widget.branch,
        refresh: true,
      );
      if (mounted && fresh != null) {
        setState(() => _file = fresh);
      }
    } catch (_) {
      // 刷新失败不阻塞（旧内容仍在）。
    }
  }

  /// 新建条目（文件 / 目录）。**单一 "+" 入口**。
  ///
  /// - 路径以 `/` 结尾 → **建目录**（用 `.gitkeep` 占位；Git 不跟踪空目录）；
  /// - 否则 → **建文件**，内容**必填**（禁止空文件）；
  /// - 路径禁止中文 / 全角 / 特殊字符（见 `util/path_rules.dart`）。
  Future<void> _createFile() async {
    if (!widget.canWrite) {
      _toast(_t('noWritePerm'));
      return;
    }
    _newPath.text = _path.isEmpty ? '' : '$_path/';
    final TextEditingController content = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) {
          final bool directory = _newPath.text.trim().endsWith('/');
          return AlertDialog(
            title: Text(directory ? _t('newDirectory') : _t('newFile')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _newPath,
                    autofocus: true,
                    onChanged: (String _) => setLocal(() {}),
                    decoration:  InputDecoration(
                      labelText: _t('pathLabel'),
                      hintText: _t('pathHint'),
                      helperText: _t('pathHintSlash'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (directory)
                     Text(_t('gitkeepHint'))
                  else
                    TextField(
                      controller: content,
                      minLines: 4,
                      maxLines: 8,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration:  InputDecoration(
                        labelText: _t('contentRequired'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 8),
                   Text(
                    _t('pathCharsetHint'),
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child:  Text(_t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child:  Text(_t('create')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) {
      content.dispose();
      return;
    }
    final String raw = _newPath.text.trim();
    final bool directory = raw.endsWith('/');
    final String? pathError =
        ogLValidateRepoEntryPath(raw, directory: directory);
    if (pathError != null) {
      content.dispose();
      _toast(pathError);
      return;
    }
    final String path = directory ? ogLGitKeepPathFor(raw) : raw;
    final String? contentError = ogLValidateFileContent(path, content.text);
    if (contentError != null) {
      content.dispose();
      _toast(contentError);
      return;
    }
    // 同名条目已存在 → 先拦下（GitHub 同名 PUT 会 422，这里给清晰原因）。
    final bool exists =
        _entries.items.any((GhContent e) => e.path == path);
    if (exists) {
      content.dispose();
      _toast(_t('alreadyExists', {'path': path}));
      return;
    }
    try {
      await widget.surface.domain.api.putContent(
        widget.fullName,
        path,
        content: content.text,
        message: directory ? 'chore: add directory $raw' : 'chore: add $path',
        branch: widget.branch,
      );
      OgLAppLog.instance.result(
        '仓库',
        directory ? _t('dirCreated') : _t('fileCreated'),
        path,
      );
      content.dispose();
      _toast(directory ? _t('createdDir', {'path': raw}) : _t('createdPath', {'path': path}));
      await _reload();
    } catch (error) {
      content.dispose();
      _toast(_t('branchCreateFailed', {'error': error}));
    }
  }

  Future<void> _deleteEntry(GhContent entry) async {
    if (!widget.canWrite) {
      _toast(_t('noWritePerm'));
      return;
    }
    if (entry.isDirectory) {
      await _deleteDirectory(entry);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('deleteFileAction')),
        content: Text(_t('deleteFileDesc', {'path': entry.path})),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final GhWriteResult result =
          await widget.surface.domain.api.deleteContentLocked(
        widget.fullName,
        entry.path,
        message: 'chore: delete ${entry.path}',
        baseSha: entry.sha,
        branch: widget.branch,
        confirmed: true,
      );
      if (!result.ok) {
        _toast(_t('branchDeleteFailed', {'error': result.detail ?? result.conflict.name}));
        return;
      }
      OgLAppLog.instance.result('仓库', _t('branchDeleted'), entry.path);
      if (_file?.path == entry.path) {
        setState(() => _file = null);
      }
      _toast(_t('deletedPath', {'path': entry.path}));
      await _reload();
    } catch (error) {
      _toast(_t('branchDeleteFailed', {'error': error}));
    }
  }

  /// 删除**目录**（含其下全部文件，一次原子提交）。
  ///
  /// 为什么单列：Git 不跟踪空目录，目录本身只是一组文件路径的前缀，
  /// 因此"删目录"= 删掉该前缀下的**全部 blob**，必须走 `commitFiles`
  /// 的批量删除才能保证"要么全成、要么全不成"。
  Future<void> _deleteDirectory(GhContent entry) async {
    final String prefix = '${entry.path}/';
    final List<String> paths = <String>[];
    try {
      final GhTree tree = await widget.surface.domain.api.tree(
        widget.fullName,
        branch: widget.branch,
      );
      if (tree.truncated) {
        _toast(_t('dirTooLarge'));
        return;
      }
      for (final GhTreeEntry node in tree.entries) {
        if (node.isFile && node.path.startsWith(prefix)) {
          paths.add(node.path);
        }
      }
    } catch (error) {
      _toast(_t('readDirFailed', {'error': error}));
      return;
    }
    if (paths.isEmpty) {
      _toast(_t('noDeletableFiles'));
      return;
    }
    const int maxBatch = 200;
    if (paths.length > maxBatch) {
      _toast(_t('dirExceedsBatch', {'count': paths.length, 'max': maxBatch}));
      return;
    }
    if (!mounted) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('deleteDirAction')),
        content: Text(
          _t('deleteDirDesc', {'path': entry.path, 'count': paths.length}) +
          _t('deleteDirDesc2'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.commitFiles(
        widget.fullName,
        branch: widget.branch,
        upserts: const <String, String>{},
        deletions: paths,
        message: 'chore: delete directory ${entry.path}',
      );
      OgLAppLog.instance.result('仓库', _t('dirDeleted'), _t('dirDeletedMeta', {'path': entry.path, 'count': paths.length}));
      _toast(_t('dirDeletedPath', {'path': entry.path}));
      await _reload();
    } catch (error) {
      _toast(_t('deleteDirFailed', {'error': error}));
    }
  }

  /// 重命名**文件**（内容不变，一次原子提交：新增新路径 + 删除旧路径）。
  ///
  /// 目录重命名不在此支持：它需要逐个文件搬运内容，代价与风险都高，
  /// 会明确提示用户（不静默失败）。
  Future<void> _renameEntry(GhContent entry) async {
    if (!widget.canWrite) {
      _toast(_t('noWritePerm'));
      return;
    }
    if (entry.isDirectory) {
      _toast(_t('renameDirUnsupported'));
      return;
    }
    final TextEditingController target =
        TextEditingController(text: entry.path);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('renameFileTitle')),
        content: TextField(
          controller: target,
          autofocus: true,
          decoration:  InputDecoration(
            labelText: _t('newPath'),
            helperText: _t('pathCharsetHintShort'),
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('rename')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      target.dispose();
      return;
    }
    final String next = target.text.trim();
    target.dispose();
    if (next == entry.path) {
      return;
    }
    final String? pathError =
        ogLValidateRepoEntryPath(next, directory: false);
    if (pathError != null) {
      _toast(pathError);
      return;
    }
    if (ogLIsGitKeep(next)) {
      _toast(_t('gitkeepNotRenamable'));
      return;
    }
    try {
      final GhContent? current = await widget.surface.domain.api.content(
        widget.fullName,
        entry.path,
        branch: widget.branch,
      );
      final String? text = current?.text;
      if (text == null) {
        _toast(_t('notTextFile'));
        return;
      }
      await widget.surface.domain.api.commitFiles(
        widget.fullName,
        branch: widget.branch,
        upserts: <String, String>{next: text},
        deletions: <String>[entry.path],
        message: 'chore: rename ${entry.path} -> $next',
      );
      OgLAppLog.instance.result('仓库', _t('branchRenamed'), '${entry.path} → $next');
      _toast(_t('renamedTo', {'path': next}));
      await _reload();
    } catch (error) {
      _toast(_t('branchRenameFailed', {'error': error}));
    }
  }

  /// 原始下载直链（路径分段做 URL 编码）。
  Future<void> _downloadEntry(GhContent entry) async {
    if (entry.isDirectory) {
      _toast(_t('noDownloadLink'));
      return;
    }
    try {
      // 取法由表面桥统一决定（见 `SurfaceBridge.planRepoFileDownload`）：
      // 不加速 → API + 认证；加速（公开仓库 + 自备通道）→ 代理 + raw 链接。
      final ({List<String> urls, Map<String, String> headers}) plan =
          await widget.surface.planRepoFileDownload(
        fullName: widget.fullName,
        path: entry.path,
        branch: widget.branch,
        repoPrivate: widget.repoPrivate,
        size: entry.size,
      );
      await widget.surface.domain.downloads.enqueue(
        url: plan.urls.first,
        fallbackUrls: plan.urls.skip(1).toList(),
        headers: plan.headers,
        fileName: ghPathName(entry.path),
        category: IxDownloadCategory.repo,
        connections: widget.surface.settings.settings.downloadConnections,
      );
      _toast(_t('addedToDownload', {'name': ghPathName(entry.path)}));
    } catch (error) {
      _toast(_t('addDownloadFailed', {'error': error}));
    }
  }

  void _showEntryDetails(GhContent entry) {
    final ThemeData theme = Theme.of(context);
    final String url = _rawUrlOf(entry) ?? '';
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(ghPathName(entry.path)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _detailRow(theme, _t('pathLabel'), entry.path),
              _detailRow(theme, _t('typeLabel'), entry.isDirectory ? _t('dir') : _t('file')),
              if (!entry.isDirectory)
                _detailRow(theme, _t('sizeLabel'), ghSizeText(entry.size)),
              _detailRow(theme, 'SHA', entry.sha.isEmpty ? '—' : entry.sha),
              if (url.isNotEmpty) _detailRow(theme, _t('directLink'), url),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              if (!await ogLCopyText(entry.path, tag: 'Repo')) {
                return;
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                _toast(_t('pathCopied'));
              }
            },
            child:  Text(_t('copyPath')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:  Text(_t('close')),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: theme.textTheme.labelSmall),
            SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      );

  Future<void> _showEntryMenu(GhContent entry) async {
    final ThemeData theme = Theme.of(context);
    await ogLShowSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                ogLFileVisualFor(entry.path, isDirectory: entry.isDirectory).icon,
                color:
                    ogLFileVisualFor(entry.path, isDirectory: entry.isDirectory).color,
              ),
              title: Text(ghPathName(entry.path)),
              subtitle: Text(entry.isDirectory ? _t('dir') : _t('file')),
            ),
            const Divider(height: 1),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title:  Text(OgLI18n.instance.t('common', 'openWith')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_showOpenWith(entry));
                },
              ),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title:  Text(_t('download')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_downloadEntry(entry));
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title:  Text(_t('detailInfo')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showEntryDetails(entry);
              },
            ),
            if (widget.canWrite && !entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title:  Text(_t('rename')),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_renameEntry(entry));
                },
              ),
            if (widget.canWrite)
              ListTile(
                leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                title: Text(
                  entry.isDirectory ? _t('deleteDirAction') : _t('deleteFileAction'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_deleteEntry(entry));
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _breadcrumb(BuildContext context) {
    final List<String> parts =
        _path.split('/').where((String p) => p.isNotEmpty).toList();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: <Widget>[
          TextButton(onPressed: () => _goTo(''), child:  Text(_t('rootDir'))),
          for (int i = 0; i < parts.length; i++) ...<Widget>[
            Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            TextButton(
              onPressed:
                  i == parts.length - 1 ? null : () => _goTo(parts.sublist(0, i + 1).join('/')),
              child: Text(parts[i]),
            ),
          ],
        ],
      ),
    );
  }

  /// README / Markdown 里图片的**仓库内相对路径** → 字节。
  ///
  /// 走 **GitHub Contents API**（同一套 DoH / 镜像传输层），
  /// 因此不碰 `raw.githubusercontent.com`，避开 DNS 污染。
  /// 仓库文件的 **raw 直链**（仅用于**展示**：详情弹窗里的"直链"、内联图片兜底）。
  ///
  /// ⚠️ 它**不是**下载用的地址：私有仓库的 raw 直链取不到内容（必须带令牌），
  /// 且内联图片分支在「图片默认进预览页」之后已不可达。真正的下载取法一律走
  /// [SurfaceBridge.planRepoFileDownload]（不加速 → API + 认证；加速 → 代理 + raw）。
  String? _rawUrlOf(GhContent entry) {
    if (entry.isDirectory) {
      return null;
    }
    final String encodedPath =
        entry.path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/${widget.fullName}/'
        '${Uri.encodeComponent(widget.branch)}/$encodedPath';
  }

  /// README 图片的取法参数（基址 + 加速前缀）。
  ///
  /// - **加速（公开仓库 + 用户自备通道）** → 给 `raw` 基址 + 代理前缀，
  ///   图片走 `代理 + raw`：
  ///   raw 不限流，而 Contents API 认证后也只有 5000 次/小时，一次 README
  ///   几十张图很容易吃掉配额。
  /// - **否则** → 两者都不给，界面退回 `imageLoader`（Contents API 取字节）——
  ///   这也是私有仓库唯一可行的取法（raw 没有签名机制，不能交给代理）。
  ({Uri? base, String? proxy}) _readmeImagePlan(String dir) {
    // README 图片是**独立的一类**：很多前缀式代理能转发 Release 附件，
    // 却转发不了仓库内图片，所以它有自己的开关。
    //
    // ★ 私有仓库**一律不走代理**：README 图片由 `Image.network` 加载，
    //   它没有 headers 参数，无法携带 Authorization，而私有 raw 匿名访问
    //   是 404（raw 端点没有签名机制）。让私有仓库走代理只会必然失败，
    //   所以这里直接把私有排除在外，退回下面的 API 取字节路径（那条带令牌）。
    final bool accel = !widget.repoPrivate &&
        widget.surface.repoFileAccelerated(
          repoPrivate: widget.repoPrivate,
          size: null,
          scope: OgLAccelScope.readmeImage,
        );
    final List<String> prefixes = widget.surface.settings.settings
        .accelPrefixesFor(OgLAccelScope.readmeImage);
    if (!accel || prefixes.isEmpty) {
      return (base: null, proxy: null);
    }
    final String encodedDir = dir
        .split('/')
        .where((String seg) => seg.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final String base = 'https://raw.githubusercontent.com/${widget.fullName}/'
        '${Uri.encodeComponent(widget.branch)}/'
        '${encodedDir.isEmpty ? '' : '$encodedDir/'}';
    return (base: Uri.parse(base), proxy: prefixes.first);
  }

  Future<Uint8List?> _readImageBytes(String path) async {
    if (path.isEmpty) {
      return null;
    }
    final String ref = widget.branch;
    try {
      final GhContent? content =
          await widget.surface.domain.api.content(widget.fullName, path, branch: ref);
      if (content == null) {
        return null;
      }
      final String encoding = '${content.raw['encoding'] ?? ''}';
      final String encoded = '${content.raw['content'] ?? ''}';
      // >1 MB 的图片 Contents API 不回内容（isTooLarge），如实退化为替代文本。
      if (encoded.isEmpty) {
        return null;
      }
      if (encoding == 'base64') {
        return base64Decode(encoded.replaceAll('\n', ''));
      }
      return Uint8List.fromList(utf8.encode(encoded));
    } catch (error) {
      OgLAppLog.instance.add('README', '图片取回失败：$path（$error）',
          severity: OgLNoticeSeverity.warning);
      return null;
    }
  }

  /// 相对路径 → 仓库内真实路径（处理 `./`、`../`、查询串与锚点）。
  static String _repoPath(String dir, String raw) {
    final String stripped = raw.split('?').first.split('#').first;
    final List<String> stack = <String>[
      for (final String seg in dir.split('/'))
        if (seg.isNotEmpty) seg,
    ];
    for (final String seg in Uri.decodeComponent(stripped).split('/')) {
      if (seg.isEmpty || seg == '.') {
        continue;
      }
      if (seg == '..') {
        if (stack.isNotEmpty) {
          stack.removeLast();
        }
        continue;
      }
      stack.add(seg);
    }
    return stack.join('/');
  }

  /// 目录部分（`a/b/c.md` → `a/b`）。
  static String _dirOf(String path) {
    final int i = path.lastIndexOf('/');
    return i <= 0 ? '' : path.substring(0, i);
  }

  Widget _readmeTile() {
    final String? md = _readme;
    if (md == null || md.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    // 一次求值：取法判定（含加速范围判断）不该在同一个 build 里跑两遍 ——
    // 两次调用之间若设置变化，会拿到不自洽的 base / proxy 组合。
    final ({Uri? base, String? proxy}) plan = _readmeImagePlan('');
    return ExpansionTile(
      title: const Text('README'),
      subtitle:  Text(_t('expandCollapse')),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: <Widget>[
        ReadmeView(
          markdown: md,
          imageBase: plan.base,
          imageProxyPrefix: plan.proxy,
          imageLoader: (String p) => _readImageBytes(_repoPath('', p)),
          onOpenLink: (Uri uri) {
            unawaited(openExternalLink(uri, tag: 'README'));
          },
        ),
      ],
    );
  }

  Widget _buildFileHeader(GhContent file) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: _t('backToDir'),
            onPressed: () => setState(() => _file = null),
          ),
          Expanded(
            child: Text(
              file.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          if (!file.isTooLarge && widget.canWrite)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: _t('edit'),
              onPressed: () => _openEditor(file),
            ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case 'delete':
                  unawaited(_deleteFromFile(file));
                case 'browser':
                  _openFileInBrowser(file);
                case 'copy':
                  unawaited(_copyPath(file.path));
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
               PopupMenuItem<String>(
                value: 'copy',
                child: Text(_t('copyPath')),
              ),
               PopupMenuItem<String>(
                value: 'browser',
                child: Text(_t('openInBrowser')),
              ),
              // 删除属写操作：仅在有 push 权限时出现（R3）。
              if (widget.canWrite)
                 PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(_t('deleteFileAction')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromFile(GhContent file) => _deleteEntry(file);

  Future<void> _copyPath(String path) async {
    if (!await ogLCopyText(path, tag: 'Repo')) {
      return;
    }
    _toast(_t('pathCopied'));
  }

  void _openFileInBrowser(GhContent file) {
    final String? url = file.htmlUrl;
    if (url == null || url.isEmpty) {
      _toast(_t('noOpenLink'));
      return;
    }
    unawaited(openLinkOrCopy(context, url, tag: _t('file')));
  }

  static bool _isImage(String path) {
    final String lower = path.toLowerCase();
    for (final String ext in <String>[
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico',
    ]) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildViewer(GhContent file, TextStyle codeStyle, OgLCodeTheme theme) {
    if (_isImage(file.path)) {
      final String? url = _rawUrlOf(file);
      if (url == null) {
        return _MessagePane(
          icon: Icons.image_not_supported_outlined,
          message: _t('noImageUrl'),
        );
      }
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (BuildContext context, Widget child,
                    ImageChunkEvent? progress) =>
                progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
            errorBuilder: (BuildContext context, Object error,
                    StackTrace? stack) =>
                _MessagePane(
              icon: Icons.broken_image_outlined,
              message: _t('imageLoadFailed'),
            ),
          ),
        ),
      );
    }
    if (file.isTooLarge) {
      return _MessagePane(
        icon: Icons.warning_amber_rounded,
        message: _t('fileTooLarge'),
        action: FilledButton.tonal(
          onPressed: () => _openFileInBrowser(file),
          child:  Text(_t('openInBrowser')),
        ),
      );
    }
    final String? text = file.text;
    if (text == null) {
      return _MessagePane(
        icon: Icons.help_outline,
        message: _t('noTextContent'),
        action: FilledButton.tonal(
          onPressed: () => _openFileInBrowser(file),
          child:  Text(_t('openInBrowser')),
        ),
      );
    }
    if (file.path.toLowerCase().endsWith('.md')) {
      final ({Uri? base, String? proxy}) plan =
          _readmeImagePlan(_dirOf(file.path));
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ReadmeView(
          markdown: text,
          imageBase: plan.base,
          imageProxyPrefix: plan.proxy,
          imageLoader: (String p) =>
              _readImageBytes(_repoPath(_dirOf(file.path), p)),
          onOpenLink: (Uri uri) {
            unawaited(openExternalLink(uri, tag: _t('file')));
          },
        ),
      );
    }
      // 交给库渲染（自带双向滚动 / 行号 / 高亮），不再自建滚动包裹层。
      return OgLCodeViewer(
        code: text,
        path: file.path,
        fontSize: codeStyle.fontSize ?? 13,
        highlight: true,
        codeTheme: theme,
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GhContent? file = _file;
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (file != null) {
      return Column(
        children: <Widget>[
          _buildFileHeader(file),
          Expanded(
            child: _buildViewer(
              file,
              const TextStyle(fontFamily: 'monospace', fontSize: 13),
              OgLCodeTheme.fromScheme(theme.colorScheme),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 「新建文件 / 目录」悬浮按钮：下滑收边（只露 1/4，点击弹出）、上滑弹回、近底部收起。
      floatingActionButton: widget.canWrite
          ? ScrollAwareAction(
              controller: _scroll,
              child: FloatingActionButton(
                tooltip: _t('newFileOrDir'),
                onPressed: _createFile,
                child: const Icon(Icons.add),
              ),
            )
          : null,
      body: Column(
        children: <Widget>[
          if (_path.isNotEmpty) _breadcrumb(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _filter,
              decoration:  InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_alt_outlined),
                hintText: _t('filterCurrentDir'),
              ),
              onChanged: (String value) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _entries,
              builder: (BuildContext context, Widget? _) {
                final String q = _filter.text.trim().toLowerCase();
                final List<GhContent> sorted = List<GhContent>.of(_entries.items)
                  ..sort((GhContent a, GhContent b) {
                    if (a.isDirectory != b.isDirectory) {
                      return a.isDirectory ? -1 : 1;
                    }
                    return ghPathName(a.path)
                        .toLowerCase()
                        .compareTo(ghPathName(b.path).toLowerCase());
                  });
                final List<GhContent> shown = q.isEmpty
                    ? sorted
                    : sorted
                        .where((GhContent e) =>
                            ghPathName(e.path).toLowerCase().contains(q))
                        .toList();
                if (_entries.items.isEmpty && _entries.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_entries.items.isEmpty && _entries.error != null) {
                  return _MessagePane(
                    icon: Icons.error_outline,
                    message: _entries.error!,
                    action: FilledButton.tonal(
                      onPressed: _entries.refresh,
                      child:  Text(_t('retry')),
                    ),
                  );
                }
                if (sorted.isEmpty) {
                  return _MessagePane(
                    icon: Icons.folder_open,
                    message: _t('dirEmpty'),
                    action: widget.canWrite
                        ? FilledButton.tonal(
                            onPressed: _createFile,
                            child:  Text(_t('newFile')),
                          )
                        : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _reload(),
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: <Widget>[
                      // 头部（常量级）：父目录 / README / 空态提示。
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                          if (_path.isNotEmpty)
                            ListTile(
                              leading: const Icon(Icons.arrow_upward),
                              title:  Text(_t('parentDir')),
                              onTap: () {
                                final int cut = _path.lastIndexOf('/');
                                unawaited(_goTo(cut <= 0 ? '' : _path.substring(0, cut)));
                              },
                            ),
                          if (_path.isEmpty) _readmeTile(),
                          if (shown.isEmpty)
                             Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text(_t('noMatchingEntries'))),
                            )
                          ],
                        ),
                      ),
                      // 数据行：按需构建（长目录不再一次性构建）。
                      SliverList.builder(
                        itemCount: shown.length,
                        itemBuilder: (BuildContext context, int index) =>
                              OgLReveal(
                                delay: OgLAnim.staggerOf(context, index),
                                child: ListTile(
                                  leading: Icon(
                                    ogLFileVisualFor(shown[index].path,
                                            isDirectory: shown[index].isDirectory)
                                        .icon,
                                    color: ogLFileVisualFor(shown[index].path,
                                            isDirectory: shown[index].isDirectory)
                                        .color,
                                  ),
                                  title: Text(
                                    ghPathName(shown[index].path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: shown[index].isDirectory
                                      ? null
                                      : Text(ghSizeText(shown[index].size)),
                                  trailing: shown[index].isDirectory
                                      ? const Icon(Icons.chevron_right)
                                      : null,
                                  onTap: () {
                                    if (shown[index].isDirectory) {
                                      unawaited(_goTo(shown[index].path));
                                    } else {
                                      _openEntryDefault(shown[index]);
                                    }
                                  },
                                  onLongPress: () => unawaited(_showEntryMenu(shown[index])),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 议题 / PR
// ─────────────────────────────────────────────────────────────────────────────

class _IssuesTab extends StatefulWidget {
  const _IssuesTab({required this.surface, required this.fullName});

  final SurfaceBridge surface;
  final String fullName;

  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  String _state = 'open';

  /// 列表滚动位置：`ScrollAwareAction` 读它判定「收边 / 弹回 / 近底部」。
  final ScrollController _scroll = ScrollController();
  late final _Paged<Map<String, dynamic>> _paged =
      _Paged<Map<String, dynamic>>(
    loader: _load,
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );
  Future<List<Map<String, dynamic>>> _load(int page) =>
      widget.surface.domain.api.issues(
        widget.fullName,
        state: _state,
        perPage: _kPageSize,
        page: page,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NewIssuePage(
          surface: widget.surface,
          fullName: widget.fullName,
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('issueCreated'))),
      );
      await _paged.refresh();
    }
  }

  Future<void> _close(int number) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('closeIssue', {'number': number})),
        content:  Text(_t('closeIssueHint')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('close')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .updateIssue(widget.fullName, number, state: 'closed');
      OgLAppLog.instance.result('议题', _t('issueClosed'), '#$number');
      await _paged.refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('closeFailed', {'error': error}))),
        );
      }
    }
  }

  void _openIssue(Map<String, dynamic> item) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IssuePage(
          surface: widget.surface,
          fullName: widget.fullName,
          issue: item,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 「新建议题」悬浮按钮：下滑收边、上滑弹回，近底部收起（不挡列表尾部）。
      floatingActionButton: ScrollAwareAction(
        controller: _scroll,
        child: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add_comment_outlined),
          label:  Text(_t('newIssue')),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments:  <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'open', label: Text(_t('openState'))),
                ButtonSegment<String>(value: 'closed', label: Text(_t('issueClosed'))),
                ButtonSegment<String>(value: 'all', label: Text(_t('all'))),
              ],
              selected: <String>{_state},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> selection) {
                if (selection.isNotEmpty && selection.first != _state) {
                  setState(() => _state = selection.first);
                  unawaited(_paged.refresh());
                }
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _paged,
              builder: (BuildContext context, Widget? _) => _pagedBody<Map<String, dynamic>>(
                context,
                _paged,
                (BuildContext context, Map<String, dynamic> item, int index) {
                  final int number = ghInt(item, 'number');
                  return ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(
                      '#$number ${ghStr(item, 'title')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _t('issueMeta', <String, Object?>{'author': ghLogin(item), 'comments': ghInt(item, 'comments'), 'date': ghDate(item, 'created_at')}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ghStr(item, 'state') == 'open'
                        ? IconButton(
                            icon: const Icon(Icons.task_alt),
                            tooltip: _t('close'),
                            onPressed: () => _close(number),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => _openIssue(item),
                  );
                },
                emptyIcon: Icons.task_alt,
                emptyText: _state == 'all' ? _t('noIssues') : _t('noIssuesFiltered'),
                controller: _scroll,
                emptyAction: FilledButton.tonal(
                  onPressed: _create,
                  child:  Text(_t('newIssue')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PullsTab extends StatefulWidget {
  const _PullsTab({required this.surface, required this.fullName});

  final SurfaceBridge surface;
  final String fullName;

  @override
  State<_PullsTab> createState() => _PullsTabState();
}

class _PullsTabState extends State<_PullsTab> {
  String _state = 'open';
  late final _Paged<Map<String, dynamic>> _paged =
      _Paged<Map<String, dynamic>>(
    loader: _load,
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );
  Future<List<Map<String, dynamic>>> _load(int page) =>
      widget.surface.domain.api.pulls(
        widget.fullName,
        state: _state,
        perPage: _kPageSize,
        page: page,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  void _openPull(Map<String, dynamic> item) {
    final int number = ghInt(item, 'number');
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PullPage(
          surface: widget.surface,
          fullName: widget.fullName,
          pull: item,
          number: number,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments:  <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'open', label: Text(_t('openState'))),
              ButtonSegment<String>(value: 'closed', label: Text(_t('issueClosed'))),
              ButtonSegment<String>(value: 'all', label: Text(_t('all'))),
            ],
            selected: <String>{_state},
            showSelectedIcon: false,
            onSelectionChanged: (Set<String> selection) {
              if (selection.isNotEmpty && selection.first != _state) {
                setState(() => _state = selection.first);
                unawaited(_paged.refresh());
              }
            },
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _paged,
            builder: (BuildContext context, Widget? _) => _pagedBody<Map<String, dynamic>>(
              context,
              _paged,
              (BuildContext context, Map<String, dynamic> item, int index) => ListTile(
                leading: const Icon(Icons.call_merge),
                title: Text(
                  '#${ghInt(item, 'number')} ${ghStr(item, 'title')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'by ${ghLogin(item)} · ${ghDate(item, 'created_at')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPull(item),
              ),
              emptyIcon: Icons.call_merge,
              emptyText: _state == 'all' ? _t('noPulls') : _t('noPullsFiltered'),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 发布
// ─────────────────────────────────────────────────────────────────────────────

class _ReleasesTab extends StatefulWidget {
  const _ReleasesTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    required this.canWrite,
    super.key,
  });
  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  /// 是否有写权限（R3：无 push 权限则不给"新建发布"入口）。
  final bool canWrite;
  @override
  State<_ReleasesTab> createState() => _ReleasesTabState();
}

class _ReleasesTabState extends State<_ReleasesTab> {
  late final _Paged<GhRelease> _paged = _Paged<GhRelease>(
    loader: (int page) => widget.surface.domain.api.releases(
      widget.fullName,
      perPage: _kHeavyPageSize,
      page: page,
    ),
    cacheKey: 'releases:${widget.fullName}',
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );

  /// 列表滚动位置：`ScrollAwareAction` 读它判定「收边 / 弹回 / 近底部」。
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final GhRelease? created = await Navigator.of(context).push<GhRelease>(
      MaterialPageRoute<GhRelease>(
        builder: (BuildContext context) => NewReleasePage(
          surface: widget.surface,
          fullName: widget.fullName,
          defaultBranch: widget.branch,
        ),
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('releaseCreated', {'tag': created.tagName}))),
      );
      await _paged.refresh();
    }
  }

  Future<void> _openDetail(GhRelease release) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReleaseDetailPage(
          surface: widget.surface,
          fullName: widget.fullName,
          release: release,
        ),
      ),
    );
    if (mounted) {
      await _paged.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 「新建 Release」悬浮按钮：下滑收边、上滑弹回，近底部收起。
      floatingActionButton: widget.canWrite
          ? ScrollAwareAction(
              controller: _scroll,
              child: FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.new_releases_outlined),
                label:  Text(_t('newRelease')),
              ),
            )
          : null,
      body: ListenableBuilder(
        listenable: _paged,
        builder: (BuildContext context, Widget? _) => _pagedBody<GhRelease>(
          context,
          _paged,
          (BuildContext context, GhRelease release, int index) {
            final List<String> marks = <String>[
              if (release.isDraft) _t('draft'),
              if (release.isPrerelease) _t('prerelease'),
            ];
            return ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: Text(
                release.tagName +
                    (release.name == null || release.name!.isEmpty
                        ? ''
                        : ' · ${release.name}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                <String>[
                  if (release.publishedAt != null)
                    _t('releasePublishedAt', {
                      'date': release.publishedAt!
                          .toIso8601String()
                          .split('T')
                          .first,
                    }),
                  if (marks.isNotEmpty) marks.join(' / '),
                  _t('releaseAssetsCount', {'count': release.assets.length}),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(_openDetail(release)),
            );
          },
          emptyIcon: Icons.new_releases_outlined,
          emptyText: _t('noReleases'),
          controller: _scroll,
          emptyAction: widget.canWrite
              ? FilledButton.tonal(
                  onPressed: _create,
                  child:  Text(_t('newRelease')),
                )
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 分支
// ─────────────────────────────────────────────────────────────────────────────

class _BranchesTab extends StatefulWidget {
  const _BranchesTab({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    required this.onBranchChanged,
    required this.canWrite,
  });
  final SurfaceBridge surface;
  final String fullName;
  final String defaultBranch;
  final VoidCallback onBranchChanged;

  /// 是否有写权限（R3：无 push 权限则不给"新建 / 重命名 / 删除分支"入口）。
  final bool canWrite;
  @override
  State<_BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends State<_BranchesTab> {
  late final _Paged<GhBranch> _paged = _Paged<GhBranch>(
    loader: (int page) => widget.surface.domain.api.branches(
      widget.fullName,
      perPage: _kPageSize,
      page: page,
    ),
    cacheKey: 'branches:${widget.fullName}',
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );
  final TextEditingController _createName = TextEditingController();
  final TextEditingController _renameName = TextEditingController();

  /// 列表滚动位置：`ScrollAwareAction` 读它判定「收边 / 弹回 / 近底部」。
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    _createName.dispose();
    _renameName.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    _createName.clear();
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('newBranch')),
        content: TextField(
          controller: _createName,
          autofocus: true,
          decoration:  InputDecoration(
            labelText: _t('branchName'),
            hintText: 'feature/xxx',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_createName.text),
            child:  Text(_t('create')),
          ),
        ],
      ),
    );
    final String trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.createBranch(
        widget.fullName,
        name: trimmed,
        fromBranch: widget.defaultBranch,
      );
      OgLAppLog.instance.result(_t('branches'), _t('branchCreated'), trimmed);
      await _paged.refresh();
      widget.onBranchChanged();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('branchCreateFailed', {'error': error}))),
        );
      }
    }
  }

  Future<void> _rename(GhBranch branch) async {
    _renameName.text = branch.name;
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('renameBranch')),
        content: TextField(
          controller: _renameName,
          autofocus: true,
          decoration:  InputDecoration(labelText: _t('newName')),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_renameName.text),
            child:  Text(_t('rename')),
          ),
        ],
      ),
    );
    final String trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == branch.name || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .renameBranch(widget.fullName, branch.name, trimmed);
      OgLAppLog.instance.result(_t('branches'), _t('branchRenamed'), '${branch.name} → $trimmed');
      await _paged.refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('branchRenameFailed', {'error': error}))),
        );
      }
    }
  }

  Future<void> _delete(GhBranch branch) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('deleteBranchTitle')),
        content: Text(_t('deleteBranchDesc', {'name': branch.name})),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.deleteBranch(widget.fullName, branch.name);
      OgLAppLog.instance.result(_t('branches'), _t('branchDeleted'), branch.name);
      await _paged.refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('branchDeleteFailed', {'error': error}))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // 「新建分支」悬浮按钮：下滑收边、上滑弹回，近底部收起。
      floatingActionButton: widget.canWrite
          ? ScrollAwareAction(
              controller: _scroll,
              child: FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.alt_route),
                label:  Text(_t('newBranch')),
              ),
            )
          : null,
      body: ListenableBuilder(
        listenable: _paged,
        builder: (BuildContext context, Widget? _) => _pagedBody<GhBranch>(
          context,
          _paged,
          (BuildContext context, GhBranch branch, int index) {
            final bool isDefault = branch.name == widget.defaultBranch;
            return ListTile(
              leading: Icon(
                branch.isProtected
                    ? Icons.lock_outline
                    : Icons.account_tree_outlined,
              ),
              title: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${ghShortSha(branch.sha)}'
                '${isDefault ? _t('defaultBranchTag') : ''}'
                '${branch.isProtected ? _t('protectedTag') : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (String value) {
                  if (value == 'rename') {
                    unawaited(_rename(branch));
                  } else if (value == 'delete') {
                    unawaited(_delete(branch));
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    enabled: !isDefault,
                    child:  Text(_t('rename')),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    enabled: !isDefault,
                    child:  Text(_t('delete')),
                  ),
                ],
              ),
            );
          },
          emptyIcon: Icons.account_tree_outlined,
          emptyText: _t('noBranches'),
          controller: _scroll,
          emptyAction: FilledButton.tonal(
            onPressed: _create,
            child:  Text(_t('newBranch')),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 提交
// ─────────────────────────────────────────────────────────────────────────────

class _CommitsTab extends StatefulWidget {
  const _CommitsTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  @override
  State<_CommitsTab> createState() => _CommitsTabState();
}

class _CommitsTabState extends State<_CommitsTab> {
  late final _Paged<GhCommit> _paged = _Paged<GhCommit>(
    loader: (int page) => widget.surface.domain.api.commits(
      widget.fullName,
      branch: widget.branch,
      perPage: _kPageSize,
      page: page,
    ),
    cacheKey: 'commits:${widget.fullName}:${widget.branch}',
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _paged,
      builder: (BuildContext context, Widget? _) => _pagedBody<GhCommit>(
        context,
        _paged,
        (BuildContext context, GhCommit commit, int index) => ListTile(
          leading: const Icon(Icons.history),
          title: Text(commit.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${ghCommitAuthor(commit)} · '
            '${commit.date?.toIso8601String().split('T').first ?? ''} · '
            '${ghShortSha(commit.sha)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => CommitPage(
                surface: widget.surface,
                fullName: widget.fullName,
                commit: commit,
              ),
            ),
          ),
        ),
        emptyIcon: Icons.history,
        emptyText: _t('noCommits'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsTab extends StatefulWidget {
  const _ActionsTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  @override
  State<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends State<_ActionsTab> {
  String _filter = 'all';
  late final _Paged<Map<String, dynamic>> _paged =
      _Paged<Map<String, dynamic>>(
    loader: _load,
    cacheKey: 'actions:${widget.fullName}:${widget.branch}',
    onManualRefresh: () => widget.surface.domain.api.invalidateReadCache(),
  );

  Future<List<Map<String, dynamic>>> _load(int page) =>
      widget.surface.domain.api.workflowRuns(
        widget.fullName,
        branch: widget.branch,
        perPage: _kHeavyPageSize,
        page: page,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  Future<void> _dispatch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => WorkflowDispatchPage(
          surface: widget.surface,
          fullName: widget.fullName,
          defaultBranch: widget.branch,
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('workflowTriggered'))),
      );
      await _paged.refresh();
    }
  }

  bool _matches(Map<String, dynamic> run) {
    if (_filter == 'all') {
      return true;
    }
    final String status = ghStr(run, 'status');
    final String conclusion = ghStr(run, 'conclusion');
    switch (_filter) {
      case 'running':
        return status != 'completed';
      case 'success':
        return conclusion == 'success';
      case 'failure':
        return conclusion == 'failure' || conclusion == 'timed_out';
      default:
        return true;
    }
  }

  IconData _iconFor(String status, String conclusion) {
    if (status != 'completed') {
      return Icons.sync;
    }
    switch (conclusion) {
      case 'success':
        return Icons.check_circle;
      case 'failure':
      case 'timed_out':
        return Icons.error;
      case 'cancelled':
      case 'skipped':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _paged,
      builder: (BuildContext context, Widget? _) {
        final List<Map<String, dynamic>> shown =
            _paged.items.where(_matches).toList();
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _dispatch,
                    icon: const Icon(Icons.play_arrow),
                    label:  Text(_t('manualTrigger')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          for (final MapEntry<String, String> entry
                              in  <String, String>{
                            'all': _t('all'),
                            'running': _t('runInProgress'),
                            'success': _t('runSuccess'),
                            'failure': _t('runFailed'),
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(entry.value),
                                selected: _filter == entry.key,
                                onSelected: (bool on) {
                                  if (on) {
                                    setState(() => _filter = entry.key);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty && _paged.items.isNotEmpty
                  ?  _MessagePane(
                      icon: Icons.filter_alt_off_outlined,
                      message: _t('noRunsFiltered'),
                    )
                  : _pagedBody<Map<String, dynamic>>(
                      context,
                      _paged,
                      (BuildContext context, Map<String, dynamic> run, int index) {
                        final String status = ghStr(run, 'status');
                        final String conclusion = ghStr(run, 'conclusion');
                        return ListTile(
                          leading: Icon(
                            _iconFor(status, conclusion),
                            color: conclusion == 'success'
                                ? const Color(0xFF1A7F37)
                                : conclusion == 'failure' ||
                                        conclusion == 'timed_out'
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(
                            ghStr(run, 'display_title').isEmpty
                                ? ghStr(run, 'name')
                                : ghStr(run, 'display_title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${ghStr(run, 'name')} · ${ghStr(run, 'event')} · '
                            '${status.isEmpty ? '—' : status}'
                            '${conclusion.isEmpty ? '' : ' / $conclusion'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => ActionRunPage(
                                surface: widget.surface,
                                fullName: widget.fullName,
                                run: run,
                              ),
                            ),
                          ),
                        );
                      },
                      emptyIcon: Icons.play_circle_outline,
                      emptyText: _t('noWorkflowRuns'),
                      items: shown,
                  ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 仓库设置
// ─────────────────────────────────────────────────────────────────────────────

class _RepoSettingsTab extends StatefulWidget {
  const _RepoSettingsTab({
    required this.surface,
    required this.repo,
    required this.onRepoChanged,
  });

  final SurfaceBridge surface;
  final GhRepo repo;
  final ValueChanged<GhRepo> onRepoChanged;

  @override
  State<_RepoSettingsTab> createState() => _RepoSettingsTabState();
}

class _RepoSettingsTabState extends State<_RepoSettingsTab> {
  late final TextEditingController _name =
      TextEditingController(text: widget.repo.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.repo.description ?? '');
  final TextEditingController _cname = TextEditingController();
  bool _busy = false;
  Future<Map<String, dynamic>?>? _pagesFuture;

  /// 自定义域名的初始值（异步读回后记录，用于脏检查）。
  String? _cnameInitial;

  String get _full => widget.repo.fullName;

  /// 表单是否已输入未保存的内容（对照 [widget.repo] 的真值）。
  bool get _dirty =>
      _name.text != widget.repo.name ||
      _description.text != (widget.repo.description ?? '') ||
      (_cnameInitial != null && _cname.text != _cnameInitial);

  /// 返回前的「放弃确认」（复用 `code_editor_page` 分片的既有文案，语义一致）。
  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          final OgLI18n i18n = OgLI18n.instance;
          return AlertDialog(
            title: Text(i18n.t('code_editor_page', 'discardTitle')),
            content: Text(i18n.t('code_editor_page', 'discardDesc')),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(i18n.t('code_editor_page', 'continueEditing')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(i18n.t('code_editor_page', 'discardChanges')),
              ),
            ],
          );
        },
      );

  @override
  void initState() {
    super.initState();
    _pagesFuture = _loadPages();
    unawaited(_loadCname());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _cname.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadPages() async {
    try {
      return await widget.surface.domain.api.pagesInfo(_full);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCname() async {
    try {
      final String? cname = await widget.surface.domain.api.readCname(_full);
      if (mounted && cname != null) {
        setState(() {
          _cname.text = cname;
          _cnameInitial = cname;
        });
      }
    } catch (_) {
      // 大多数仓库没有自定义域名。
    }
  }

  Future<void> _saveBasic() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final GhRepo updated = await widget.surface.domain.api.updateRepo(
        _full,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        description: _description.text.trim(),
      );
      OgLAppLog.instance.result('仓库', _t('basicInfoUpdated'), _full);
      if (mounted) {
        widget.onRepoChanged(updated);
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('saved'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('saveFailed', {'error': error}))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveCname() async {
    if (_busy) {
      return;
    }
    final String domain = _cname.text.trim();
    if (domain.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('domainRequired'))),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final GhContent? existing = await widget.surface.domain.api
          .content(_full, 'CNAME', branch: widget.repo.defaultBranch);
      if (existing == null) {
        await widget.surface.domain.api.putContent(
          _full,
          'CNAME',
          content: '$domain\n',
          message: 'chore: configure custom domain',
          branch: widget.repo.defaultBranch,
        );
      } else {
        final GhWriteResult result = await widget.surface.domain.api
            .putContentLocked(
          _full,
          'CNAME',
          content: '$domain\n',
          message: 'chore: configure custom domain',
          baseSha: existing.sha,
          branch: widget.repo.defaultBranch,
        );
        if (!result.ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_t('cnameSaveFailed', {'error': result.detail ?? result.conflict.name})),
              ),
            );
          }
          return;
        }
      }
      OgLAppLog.instance.result('仓库', _t('cnameSaved'), domain);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('cnameSavedShort'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('cnameSaveFailed', {'error': error}))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _enablePages() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .enablePages(_full, branch: widget.repo.defaultBranch);
      OgLAppLog.instance.result('仓库', _t('pagesEnabled'), _full);
      if (mounted) {
        setState(() => _pagesFuture = _loadPages());
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('pagesEnabledHint'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('enableFailed', {'error': error}))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disablePages() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.disablePages(_full);
      OgLAppLog.instance.result('仓库', _t('pagesDisabledHint'), _full);
      if (mounted) {
        setState(() => _pagesFuture = _loadPages());
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('pagesDisabledHint'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('disableFailed', {'error': error}))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteRepo() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('deleteRepo')),
        content: Text(_t('deleteRepoDesc', {'full': _full})),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('deleteForever')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.deleteRepo(_full);
      OgLAppLog.instance.add('仓库', _t('repoDeleted', {'full': _full}),
          severity: OgLNoticeSeverity.warning);
      if (mounted) {
        // 带返回值：调用方（首页 / 搜索）据此刷新，已删仓库不再留在列表里。
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('branchDeleteFailed', {'error': error}))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // 返回拦截：表单有未保存内容时先确认再离开（该标签页在仓库页内，
    // 拦截的是整个仓库页的后退，效果与代码编辑器一致）。
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final NavigatorState navigator = Navigator.of(context);
        final bool? leave = await _confirmDiscard();
        if (leave == true && mounted) {
          navigator.pop();
        }
      },
      child: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(_t('basicInfo'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration:  InputDecoration(
            labelText: _t('repoName'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 3,
          decoration:  InputDecoration(
            labelText: _t('description'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _saveBasic,
            child:  Text(_t('saveBasicInfo')),
          ),
        ),
        const Divider(height: 32),
        Text('Pages', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>?>(
          future: _pagesFuture,
          builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>?> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return  Text(_t('reading'));
            }
            final Map<String, dynamic>? info = snapshot.data;
            if (info == null) {
              return  Text(_t('notEnabled'));
            }
            final String url = ghStr(info, 'html_url');
            final String status = ghStr(info, 'status');
            final String statusPart = status.isEmpty ? _t('enabled') : status;
            final String urlPart = url.isEmpty
                ? ''
                : '\n${_t('address', {'url': url})}';
            return Text(_t('statusLabel', {
              'status': '$statusPart$urlPart',
            }));
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton.tonal(
              onPressed: _busy ? null : _enablePages,
              child:  Text(_t('enableDefaultBranch')),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _disablePages,
              child:  Text(_t('disable')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cname,
          decoration:  InputDecoration(
            labelText: _t('customDomain'),
            hintText: 'example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: _busy ? null : _saveCname,
            child:  Text(_t('saveCname')),
          ),
        ),
        const Divider(height: 32),
        Text(
          _t('dangerZone'),
          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                 Text(_t('deleteRepoWarning')),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _deleteRepo,
                  child:  Text(_t('deleteRepo')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 通用
// ─────────────────────────────────────────────────────────────────────────────

/// 简单消息面板（图标 + 文案 + 可选动作）。
class _MessagePane extends StatelessWidget {
  const _MessagePane({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}