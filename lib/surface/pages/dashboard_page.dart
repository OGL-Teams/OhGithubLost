/// L3 展示级 · 首页（我的仓库 / 星标仓库，分页）。
///
/// - 分段切换：`SegmentedButton`（我的 / 星标）；
/// - 列表：Material `ListTile` + 下拉刷新 + 「加载更多」；
/// - 四态（载 / 空 / 错 / 有数据）统一收敛；错误可见且可重试。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import 'download_manager_page.dart';
import 'new_repo_page.dart';
import 'notifications_page.dart';
import 'repo_page.dart';

/// 取 `dashboard_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('dashboard_page', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 每页条数。
const int _kPageSize = 30;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_mine.refresh()));
  }

  @override
  void dispose() {
    _mine.dispose();
    _starred.dispose();
    super.dispose();
  }

  void _segmentChanged(int value) {
    setState(() => _segment = value);
    unawaited(_active.refresh());
  }

  /// 打开仓库页；返回 `true` 表示该仓库**已被删除**，此时刷新当前列表。
  Future<void> _openRepo(GhRepo repo) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RepoPage(surface: widget.surface, repo: repo),
      ),
    );
    // 返回后无条件刷新（不再依赖 pop 返回值：sheet 的 pop 可能是非 bool 类型）。
    if (mounted) {
      await _active.refresh();
    }
  }

  void _openDownloads() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DownloadManagerPage(surface: widget.surface),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => const NotificationsPage()),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('repoCreatedName', {'name': created.fullName}))),
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
        title:  Text(_t('home')),
        actions: <Widget>[
          ListenableBuilder(
            listenable: OgLAppLog.instance,
            builder: (BuildContext context, Widget? _) {
              final int alerts = OgLAppLog.instance.entries
                  .where((OgLAppLogEntry e) => e.severity != OgLNoticeSeverity.info)
                  .length;
              return IconButton(
                icon: alerts > 0
                    ? Badge(
                        label: Text('$alerts'),
                        child: const Icon(Icons.notifications_outlined),
                      )
                    : const Icon(Icons.notifications_outlined),
                tooltip: _t('notifications'),
                onPressed: _openNotifications,
              );
            },
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRepo,
        icon: const Icon(Icons.add),
        label:  Text(_t('newRepo')),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<int>(
              segments:  <ButtonSegment<int>>[
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
                  return _RepoMessage(
                    icon: Icons.error_outline,
                    message: p.error!,
                    action: FilledButton.tonal(
                      onPressed: p.refresh,
                      child:  Text(_t('retry')),
                    ),
                  );
                }
                if (p.items.isEmpty) {
                  return _RepoMessage(
                    icon: Icons.folder_outlined,
                    message: _segment == 0 ? _t('emptyMine') : _t('emptyStarred'),
                    action: _segment == 0
                        ? FilledButton(
                            onPressed: _createRepo,
                            child:  Text(_t('newRepo')),
                          )
                        : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: p.refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: p.items.length + (p.done ? 0 : 1),
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == p.items.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Center(
                            child: p.loading
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: p.loadMore,
                                    child: Text(_t('loadMore', {'count': p.items.length})),
                                  ),
                          ),
                        );
                      }
                      final GhRepo repo = p.items[index];
                      return OgLReveal(
                        delay: OgLAnim.staggerOf(context, index),
                        child: ListTile(
                          leading: Icon(
                            repo.isPrivate ? Icons.lock_outline : Icons.folder_outlined,
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
    // ★ 入口守卫：刷新是 `Future`，可能在 `_disposed` 之后才被调度到这里
    //   （比如页面已 push 走、`p.refresh` 还被 ListenableBuilder 串着触发）；
    //   不守住就直接 `_generation++` / 走 `loadMore`，留下"幽灵请求"。
    if (_disposed) {
      return Future<void>.value();
    }
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

/// 空/错态面板。
class _RepoMessage extends StatelessWidget {
  const _RepoMessage({required this.icon, required this.message, this.action});

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