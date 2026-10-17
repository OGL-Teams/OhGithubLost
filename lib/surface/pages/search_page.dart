/// L3 展示级 · 搜索页（仓库 / 代码，服务端搜索）。
///
/// - 模式切换：`SegmentedButton`（仓库 / 代码）；
/// - 回车即搜；空关键字不打扰服务端；
/// - 结果行：仓库 → 仓库页；代码 → 直达所属仓库的该文件。
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
import '../util/gh_format.dart';
import '../widgets/anim/anim_preload.dart';
import 'repo_page.dart';
import '../util/og_l_space.dart';

/// 取 `search_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'search_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

// ── 分级预加载（页面级登记）─────────────────────────────────────────────
// 策略表在 `widgets/anim/anim_preload.dart`：档位 1 仅当前页面 / 档位 2 追加
//"全屏动画" / 档位 3 再追加"下一子层级"。本页只**登记**，准入与拒收全交给那张表。

/// 搜索页预加载作用域：**与壳里的 group 逐字一致**（`client_shell.dart` 用
/// `'ogl-tab-${tab.name}'` 包住每个 tab 页），切走 tab 时由壳整组取消。
const String _kPreloadGroup = 'ogl-tab-search';

/// 预登记结果列表**前几项**的条数。
///
/// **不能逐项登记**：一次搜索 30 条会在登记时把数量 / 内存额度打满，
/// 而且和 `OgLReveal` 的**视口驱动**重复（没进视口的行本来就不该提前解码）。
const int _kPreloadLeads = 2;

/// 头像的**估算**内存（GitHub 头像 10–40 KB 量级）。
///
/// 图片项的默认估算是 2 MiB；照默认给，几项就吃掉大半个内存额度，
/// 把别的页面的额度挤没。估算按实际量级给，才是库文档说的"不要过了"。
const int _kAvatarBytes = 96 * 1024;

/// 仓库 owner 头像的幂等键（同一资源同一 id）。
///
/// ★ 跨文件约定：`dashboard_page`（列表行 / push 侧）与 `repo_page`（子页自己）
/// 用的是**同一个** id —— 同一张头像在整条链路上只解一次。
String _repoAvatarId(String fullName) => 'avatar:repo:$fullName';

/// 子页（仓库页）的路由作用域：`route:repo:<fullName>`。
///
/// ★ 跨文件约定：`dashboard_page` 与 `repo_page` 用同一条规则；push 出来的子页被
/// 包上**同名**的 `OgLAnimPreloadBoundary`（pop = 整组取消，不留下在途项）。
String _repoRouteGroup(String fullName) => 'route:repo:$fullName';

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
class SearchPage extends StatefulWidget {
  /// 创建页面。
  const SearchPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _input = TextEditingController();

  /// 0 = 仓库；1 = 代码。
  int _mode = 0;

  AsyncController<List<_SearchHit>>? _results;
  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    _results?.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final String q = _input.text.trim();
    if (q.isEmpty) {
      return;
    }
    _query = q;
    final AsyncController<List<_SearchHit>> controller;
    if (_mode == 0) {
      controller = AsyncController<List<_SearchHit>>(
        label: _t('repoSearch'),
        isEmpty: (List<_SearchHit> value) => value.isEmpty,
        loader: () async {
          final List<GhRepo> repos =
              await widget.surface.domain.api.searchRepos(q, perPage: 30);
          OgLAppLog.instance.add(
              _t('search'), _t('repoResults', {'q': q, 'count': repos.length}));
          final List<_SearchHit> hits = repos
              .map(
                (GhRepo repo) => _SearchHit(
                  title: repo.fullName,
                  subtitle: _repoSubtitle(repo),
                  repo: repo,
                ),
              )
              .toList();
          if (mounted) {
            // 数据落地即登记本页主视觉图片（结果行的 owner 头像）；
            // 页面已经离开就不登记 —— 不为"人已经走了"的页面预热。
            _preloadHitAvatars(hits);
          }
          return hits;
        },
      );
    } else {
      controller = AsyncController<List<_SearchHit>>(
        label: _t('codeSearch'),
        isEmpty: (List<_SearchHit> value) => value.isEmpty,
        loader: () async {
          final List<Map<String, dynamic>> items =
              await widget.surface.domain.api.searchCode(q, perPage: 30);
          OgLAppLog.instance.add(
              _t('search'), _t('codeResults', {'q': q, 'count': items.length}));
          return items.map(_hitFromCode).toList();
        },
      );
    }
    final old = _results;
    setState(() => _results = controller);
    old?.dispose();
    unawaited(controller.load());
  }

  /// 代码命中 → 展示行（含“直达文件”所需的仓库 + 路径）。
  _SearchHit _hitFromCode(Map<String, dynamic> item) {
    final String path = ghStr(item, 'path');
    final String name = ghStr(item, 'name');
    final String fragment = _fragmentOf(item);
    final Map<String, dynamic>? repoMap = _repoOf(item);
    final GhRepo repo = repoMap == null
        ? GhRepo.fromJson(const <String, dynamic>{})
        : GhRepo.fromJson(repoMap);
    return _SearchHit(
      title: path.isEmpty ? name : path,
      subtitle: fragment.isEmpty ? _t('openFileHint') : fragment,
      repo: repo.fullName.isEmpty ? null : repo,
      initialPath: path.isEmpty ? null : path,
    );
  }

  String _fragmentOf(Map<String, dynamic> item) {
    final Object? matches = item['text_matches'];
    if (matches is! List<Object?>) {
      return '';
    }
    for (final Object? match in matches) {
      if (match is Map<Object?, Object?>) {
        final String fragment =
            ghStr(Map<String, dynamic>.from(match), 'fragment').trim();
        if (fragment.isNotEmpty) {
          return fragment.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      }
    }
    return '';
  }

  Map<String, dynamic>? _repoOf(Map<String, dynamic> item) {
    final Object? repo = item['repository'];
    if (repo is Map<Object?, Object?>) {
      return Map<String, dynamic>.from(repo);
    }
    return null;
  }

  /// 登记结果列表**前 [_kPreloadLeads] 条**命中的 owner 头像。
  ///
  /// 档位口径（照抄库文档的判定）：
  /// - 第 1 条是"起始提示 / 空态 → 结果列表"这次**整页内容替换**完成后首帧里的
  ///   第一张图 → `fullScreen`（档位 ≥2；该档额度最大，正是为它准备的）；
  /// - 第 2 条是**列表单项入场**（`OgLReveal`，视口驱动）→ `currentPage`（档位 ≥1）。
  void _preloadHitAvatars(List<_SearchHit> hits) {
    final int take =
        hits.length < _kPreloadLeads ? hits.length : _kPreloadLeads;
    bool registered = false;
    for (int i = 0; i < take; i++) {
      final GhRepo? repo = hits[i].repo;
      if (repo == null) {
        continue;
      }
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
  /// 子页（`repo_page`）自己会用**同一个 group + 同一个 id** 再登记一次：
  /// 档位 3 下这一条先跑（子页首帧前就已解码），档位 1 / 2 下它被策略表拒收，
  /// 子页仍会按 `currentPage` 自行登记。**幂等键相同**，所以不会重复解码。
  ///
  /// ★ 与 `dashboard_page._preloadChildRepoRoute` 是同一件事（受"只改这四个页面"
  /// 约束，未抽公共函数）；两处的 group / id 必须保持逐字一致。
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

  Future<void> _open(_SearchHit hit) async {
    final GhRepo? repo = hit.repo;
    if (repo == null) {
      OgLNotifier.of(context).info(_t('noRepoForResult'));
      return;
    }
    _preloadChildRepoRoute(repo);
    final bool? deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => OgLAnimPreloadBoundary(
          // 子路由作用域：子页自己按同一条 group 登记（currentPage）；
          // 离开（pop）即整组取消本页替它登记的 childLevel 项并归还额度。
          group: _repoRouteGroup(repo.fullName),
          kinds: const <OgLAnimPreloadKind>[
            OgLAnimPreloadKind.currentPage,
            OgLAnimPreloadKind.childLevel,
          ],
          child: RepoPage(
            surface: widget.surface,
            repo: repo,
            initialPath: hit.initialPath,
          ),
        ),
      ),
    );
    // 仓库被删除：搜索结果里不该再留着它。
    if (deleted == true && mounted) {
      await _results?.load();
    }
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

  @override
  Widget build(BuildContext context) {
    final AsyncController<List<_SearchHit>>? controller = _results;
    return Scaffold(
      appBar: AppBar(title: Text(_t('search'))),
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
                      // 切换模式必须清空旧结果：否则会出现"代码结果留在仓库标签下"。
                      final AsyncController<List<_SearchHit>>? old = _results;
                      setState(() {
                        _mode = selection.first;
                        _results = null;
                        _query = '';
                        _input.clear();
                      });
                      old?.dispose();
                    }
                  },
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _input,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _t('queryHint'),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (String _) async {
                    await _run();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: controller == null
                ? Center(child: Text(_t('startHint')))
                : AsyncView<List<_SearchHit>>(
                    controller: controller,
                    emptyIcon: Icons.search_off,
                    emptyText: _t('noResults', {'query': _query}),
                    builder: (
                      BuildContext context,
                      List<_SearchHit> hits,
                    ) =>
                        ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final _SearchHit hit = hits[index];
                        return OgLReveal(
                          delay: OgLAnim.staggerOf(context, index),
                          child: ListTile(
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
                            onTap: () => _open(hit),
                          ),
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
