/// L3 展示级 · 首页（我的仓库 / 星标仓库，分页）。
///
/// - 分段切换：`SegmentedButton`（我的 / 星标）；
/// - 列表：Material `ListTile` + 下拉刷新 + 「加载更多」；
/// - 四态（载 / 空 / 错 / 有数据）统一收敛；错误可见且可重试。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/og_l_space.dart';
import '../widgets/anim/anim_preload.dart';
import '../widgets/scroll_aware_action.dart';
import 'download_manager_page.dart';
import 'new_repo_page.dart';
import 'notifications_page.dart';
import 'repo_page.dart';

/// 取 `dashboard_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'dashboard_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 每页条数。
const int _kPageSize = 30;

// ── 分级预加载（页面级登记）─────────────────────────────────────────────
// 策略表在 `widgets/anim/anim_preload.dart`：档位 0 不预加载 / 档位 1 仅当前页面 /
// 档位 2 追加"全屏动画"且额度最大 / 档位 3 再追加"下一子层级"。本页只**登记**，
// 准入与拒收全由那张表决定（这里不写任何 `if (level >= n)`）。

/// 首页预加载作用域：**与壳里的 group 逐字一致**（`client_shell.dart` 用
/// `'ogl-tab-${tab.name}'` 包住每个 tab 页）。
///
/// 一致才有意义：切走 tab 时壳会整组取消本页未完成的预加载并归还额度 ——
/// 预加载因此不会"人走了还在偷偷烧"。本页不自己再套一层 boundary。
const String _kPreloadGroup = 'ogl-tab-home';

/// 预登记"列表前几项"的条数。
///
/// **不能逐项登记**：一屏 30 条会在登记时把数量 / 内存额度瞬间打满，
/// 而且和 `OgLReveal` 的**视口驱动**重复（没进视口的行本来就不该提前解码）。
const int _kPreloadLeads = 3;

/// 头像的**估算**内存（GitHub 头像 10–40 KB 量级）。
///
/// 图片项的默认估算是 2 MiB；照默认给，4 项就预扣 8 MiB —— 档位 1 的总额度只有
/// 4 MiB，等于把别的页面的额度挤没了。估算按实际量级给才是"不要过了"。
const int _kAvatarBytes = 96 * 1024;

/// 账号头像的幂等键（同一资源同一 id）。
String _accountAvatarId(String login) => 'avatar:account:$login';

/// 仓库 owner 头像的幂等键。
///
/// ★ 跨文件约定：`repo_page`（子页自己）与 `search_page`（结果行 / push 侧）
/// 用的是**同一个** id —— 同一张头像在整条链路上只解一次。
String _repoAvatarId(String fullName) => 'avatar:repo:$fullName';

/// 子页（仓库页）的路由作用域：`route:repo:<fullName>`。
///
/// ★ 跨文件约定：`repo_page` 的自身登记用同一条规则，push 出来的子页也会被包上
/// **同名**的 `OgLAnimPreloadBoundary`（pop = 整组取消，不留下的在途项）。
String _repoRouteGroup(String fullName) => 'route:repo:$fullName';

/// 通知中心的路由作用域（本页是它的 push 方；`notifications_page` 用同一条）。
const String _kNotificationsRouteGroup = 'route:notifications';

/// 首页。
class DashboardPage extends StatefulWidget {
  /// 创建页面。
  const DashboardPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _segment = 0;

  /// 列表滚动位置：交给 [ScrollAwareAction] 判定"下滑收边 / 上滑弹回 / 近底部收起"。
  final ScrollController _scroll = ScrollController();
  late final _RepoPaged _mine = _RepoPaged(
    loader: (int page) => widget.surface.domain.api
        .myRepos(perPage: _kPageSize, page: page, sort: 'updated'),
  );
  late final _RepoPaged _starred = _RepoPaged(
    loader: (int page) =>
        widget.surface.domain.api.starredRepos(perPage: _kPageSize, page: page),
  );

  _RepoPaged get _active => _segment == 0 ? _mine : _starred;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_bootstrap()));
    // 分级预加载：本页主视觉的图片资源 = 身份头像。
    // - 账号头像 → `currentPage`（档位 ≥1）；
    // - 列表前几项的 owner 头像 → 数据落地后才登记（见 [_preloadRepoAvatars]）。
    // 登记动作本身不碰 UI、不持有 context；档位不够时被策略表**拒收**（不排队）。
    unawaited(_preloadAccountAvatar());
  }

  /// 首帧后拉第一页；数据落地即登记（列表前几项的）owner 头像。
  Future<void> _bootstrap() async {
    await _mine.refresh();
    _preloadRepoAvatars();
  }

  @override
  void dispose() {
    _mine.dispose();
    _starred.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _segmentChanged(int value) {
    setState(() => _segment = value);
    unawaited(_refreshActive());
  }

  /// 刷新当前分段，并按新数据重新登记头像（同 id 幂等，重复调用无成本）。
  Future<void> _refreshActive() async {
    await _active.refresh();
    _preloadRepoAvatars();
  }

  /// 登记当前账号头像（`currentPage`：档位 ≥1 准入，否则被策略表拒收）。
  ///
  /// 头像是本页身份区**唯一的网络图片资源**（`GhAccount.avatarUrl`）；解码结果进
  /// Flutter 自己的 `ImageCache`，键 = 图片地址 —— 与之后真正绘制头像的控件共用
  /// 同一条缓存项。取不到账号（未登录 / 保险库读失败）时**安静跳过**：
  /// 预加载是可选优化，不该反过来打扰用户。
  Future<void> _preloadAccountAvatar() async {
    final GhAccount? account = await _activeAccountOrNull();
    if (account == null) {
      return;
    }
    final String? url = account.avatarUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    if (OgLAnimPreload.register(
      OgLAnimPreloadJob.image(
        id: _accountAvatarId(account.login),
        group: _kPreloadGroup,
        kind: OgLAnimPreloadKind.currentPage,
        image: NetworkImage(url),
        weightBytes: _kAvatarBytes,
      ),
    )) {
      OgLAnimPreload.schedule();
    }
  }

  /// 当前账号；取不到就是 `null`（未登录 / 安全保险库读取失败都算"没有头像可预热"）。
  Future<GhAccount?> _activeAccountOrNull() async {
    try {
      return await widget.surface.domain.auth.activeAccount();
    } catch (_) {
      return null;
    }
  }

  /// 登记列表**前 [_kPreloadLeads] 项**仓库的 owner 头像。
  ///
  /// 档位口径（照抄库文档的判定）：
  /// - 第 1 项是"整页 loading → data"替换完成后首帧里的**第一张图** →
  ///   `fullScreen`（档位 ≥2，本档额度最大，正是为它准备的）；
  /// - 其余项是**列表单项入场**（`OgLReveal`，视口驱动）→ `currentPage`（档位 ≥1）。
  void _preloadRepoAvatars() {
    final List<GhRepo> items = _active.items;
    final int take =
        items.length < _kPreloadLeads ? items.length : _kPreloadLeads;
    bool registered = false;
    for (int i = 0; i < take; i++) {
      final GhRepo repo = items[i];
      final String? url = repo.owner.avatarUrl;
      if (url == null || url.isEmpty) {
        continue;
      }
      registered = OgLAnimPreload.register(
            OgLAnimPreloadJob.image(
              id: _repoAvatarId(repo.fullName),
              group: _kPreloadGroup,
              kind: i == 0
                  ? OgLAnimPreloadKind.fullScreen
                  : OgLAnimPreloadKind.currentPage,
              image: NetworkImage(url),
              weightBytes: _kAvatarBytes,
              // 首屏首图先跑（优先级小的先跑）。
              priority: i == 0 ? -1 : 0,
            ),
          ) ||
          registered;
    }
    if (registered) {
      OgLAnimPreload.schedule();
    }
  }

  /// 为**即将 push** 的子页登记它首帧要用的图（`childLevel`：**仅档位 3** 准入）。
  ///
  /// 用 [OgLAnimPreloadBoundary] 把子页包成 `route:repo:<fullName>` 作用域：
  /// 子页自己（`repo_page`）会用**同一个 group + 同一个 id** 再登记一次 ——
  /// 档位 3 下这一条先跑（子页首帧前就已解码），档位 1 / 2 下它被拒收，
  /// 子页仍会按 `currentPage` 自行登记。**幂等键相同**，所以不会重复解码。
  void _preloadChildRepoRoute(GhRepo repo) {
    final String? url = repo.owner.avatarUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    if (OgLAnimPreload.register(
      OgLAnimPreloadJob.image(
        id: _repoAvatarId(repo.fullName),
        group: _repoRouteGroup(repo.fullName),
        kind: OgLAnimPreloadKind.childLevel,
        image: NetworkImage(url),
        weightBytes: _kAvatarBytes,
        priority: -1,
      ),
    )) {
      OgLAnimPreload.schedule();
    }
  }

  /// 打开仓库页；返回 `true` 表示该仓库**已被删除**，此时刷新当前列表。
  Future<void> _openRepo(GhRepo repo) async {
    _preloadChildRepoRoute(repo);
    final bool? deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => OgLAnimPreloadBoundary(
          group: _repoRouteGroup(repo.fullName),
          // 声明本作用域要参与的两类（子页自己登记 currentPage，父页替它登记
          // childLevel）；真正准入仍由档位策略表决定。
          kinds: const <OgLAnimPreloadKind>[
            OgLAnimPreloadKind.currentPage,
            OgLAnimPreloadKind.childLevel,
          ],
          child: RepoPage(surface: widget.surface, repo: repo),
        ),
      ),
    );
    if (deleted == true && mounted) {
      await _active.refresh();
    }
  }

  void _openDownloads() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            DownloadManagerPage(surface: widget.surface),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        // 子页是 push 出来的路由：包一层路由作用域 `route:notifications`
        //（`notifications_page` 自己也按这条登记），pop 时整组取消未完成项。
        builder: (BuildContext context) => const OgLAnimPreloadBoundary(
          group: _kNotificationsRouteGroup,
          kinds: <OgLAnimPreloadKind>[OgLAnimPreloadKind.currentPage],
          child: NotificationsPage(),
        ),
      ),
    );
  }

  Future<void> _createRepo() async {
    final GhRepo? created = await Navigator.of(context).push<GhRepo>(
      MaterialPageRoute<GhRepo>(
        builder: (BuildContext context) => NewRepoPage(surface: widget.surface),
      ),
    );
    if (created == null || !mounted) {
      return;
    }
    OgLAppLog.instance.result(_t('home'), _t('repoCreated'), created.fullName);
    OgLNotifier.of(context).success(
      _t('repoCreatedName', {'name': created.fullName}),
    );
    await _mine.refresh();
    if (mounted) {
      setState(() => _segment = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('home')),
        actions: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: OgLAppLog.instance.alertCount,
            builder: (BuildContext context, int alerts, Widget? _) =>
                IconButton(
              icon: alerts > 0
                  ? Badge(
                      label: Text('$alerts'),
                      child: const Icon(Icons.notifications_outlined),
                    )
                  : const Icon(Icons.notifications_outlined),
              tooltip: _t('notifications'),
              onPressed: _openNotifications,
            ),
          ),
          ListenableBuilder(
            listenable: widget.surface.domain.downloads,
            builder: (BuildContext context, Widget? _) {
              final int running = widget.surface.domain.downloads.runningCount;
              return IconButton(
                icon: running > 0
                    ? Badge(
                        label: Text('$running'),
                        child: const Icon(Icons.download_outlined),
                      )
                    : const Icon(Icons.download_outlined),
                tooltip: _t('downloads'),
                onPressed: _openDownloads,
              );
            },
          ),
        ],
      ),
      // 首页「新建仓库」：下滑收边（只露 1/4，点击弹出）、上滑弹回、近底部收起。
      floatingActionButton: ScrollAwareAction(
        controller: _scroll,
        child: FloatingActionButton.extended(
          onPressed: _createRepo,
          icon: const Icon(Icons.add),
          label: Text(_t('newRepo')),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs),
            child: SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text(_t('mine'))),
                ButtonSegment<int>(value: 1, label: Text(_t('starred'))),
              ],
              selected: <int>{_segment},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> selection) {
                if (selection.isNotEmpty) {
                  _segmentChanged(selection.first);
                }
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _active,
              builder: (BuildContext context, Widget? _) {
                final _RepoPaged p = _active;
                if (p.items.isEmpty && p.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (p.items.isEmpty && p.error != null) {
                  return OgLAsyncErrorPane(
                    message: p.error!,
                    onRetry: p.refresh,
                  );
                }
                if (p.items.isEmpty) {
                  return OgLAsyncEmptyPane(
                    icon: Icons.folder_outlined,
                    text: _segment == 0 ? _t('emptyMine') : _t('emptyStarred'),
                    action: _segment == 0
                        ? FilledButton(
                            onPressed: _createRepo,
                            child: Text(_t('newRepo')),
                          )
                        : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: p.refresh,
                  child: ListView.separated(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: p.items.length + (p.done ? 0 : 1),
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == p.items.length) {
                        return Padding(
                          padding: const EdgeInsets.all(OgLSpace.md),
                          child: Center(
                            child: p.loading
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: p.loadMore,
                                    child: Text(_t(
                                        'loadMore', {'count': p.items.length})),
                                  ),
                          ),
                        );
                      }
                      final GhRepo repo = p.items[index];
                      return OgLReveal(
                        delay: OgLAnim.staggerOf(context, index),
                        child: ListTile(
                          leading: Icon(
                            repo.isPrivate
                                ? Icons.lock_outline
                                : Icons.folder_outlined,
                          ),
                          title: OgLSharedTitle(
                            tag: 'ogl-repo:${repo.fullName}',
                            child: Text(
                              repo.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          subtitle: Text(
                            _repoSubtitle(repo),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openRepo(repo),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _repoSubtitle(GhRepo repo) {
    final List<String> meta = <String>[
      if (repo.language != null && repo.language!.isNotEmpty) repo.language!,
      _t('starsCount', {'count': repo.stars}),
      if (repo.isPrivate) _t('private'),
    ];
    final String? desc = repo.description;
    if (desc == null || desc.isEmpty) {
      return meta.join(' · ');
    }
    return '${meta.join(' · ')} — $desc';
  }
}

/// 分页仓库源。
class _RepoPaged extends ChangeNotifier {
  _RepoPaged({required this.loader});

  final Future<List<GhRepo>> Function(int page) loader;

  final List<GhRepo> items = <GhRepo>[];
  int _page = 1;
  bool loading = false;
  bool done = false;
  String? error;

  bool _disposed = false;

  /// 刷新排队标记：刷新请求在途时置位，等当前请求结束后**重放**。
  bool _refreshQueued = false;

  /// 请求代次：每次刷新 +1；过期响应（旧代次）一律丢弃。
  ///
  /// 这解决两个真实竞态：快速下拉刷新时「第一页永久缺失」，
  /// 以及切换筛选 / 加载更多交错时的「重复条目、显示与筛选不符的数据」。
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

  Future<void> loadMore() async {
    if (_disposed || loading || done) {
      return;
    }
    final int generation = _generation;
    loading = true;
    error = null;
    _notify();
    try {
      final List<GhRepo> list = await loader(_page);
      if (_disposed || generation != _generation) {
        return;
      }
      items.addAll(list);
      if (list.length < _kPageSize) {
        done = true;
      }
      _page++;
    } catch (e) {
      if (_disposed || generation != _generation) {
        return;
      }
      error = '$e';
    } finally {
      loading = false;
      _notify();
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    }
  }

  Future<void> refresh() async {
    // 先作废在途请求：它的响应属于"上一代"数据（旧筛选 / 旧快照）。
    _generation++;
    if (loading) {
      // 在途请求还没回来：**排队重放**，而不是静默丢弃这次刷新
      // （否则快速操作会表现成"点了没反应 / 第一页缺失"）。
      _refreshQueued = true;
      return;
    }
    items.clear();
    _page = 1;
    done = false;
    error = null;
    await loadMore();
  }
}

// 消息面板：Phase 5 后半已收敛到 `surface/app/async.dart` —— 空态用
// [OgLAsyncEmptyPane]、失败用 [OgLAsyncErrorPane]（自带重试）；原私有
// `_RepoMessage` 与前者实现逐字相同，属重复代码，已删除。
