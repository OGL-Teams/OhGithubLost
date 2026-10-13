/// L3 展示级 · 通用分页控制器（首屏 + 加载更多 + 下拉刷新）。
///
/// ## 来源
/// 原为 `pages/repo_page.dart` 的私有 `_Paged<T>`（约 :534-698）。
/// Phase 5 架构收敛把它提取为 app 层公共控件 —— 页面层不再各自持有
/// 一份分页 + 快照 + 竞态防护的实现，统一从本文件引用。
///
/// ## 语义清单（提取时逐条保留，勿在别处"顺手改"）
/// - **快照**：按 `cacheKey` 隔离、TTL 6 秒；命中即展示、不发请求；
///   失效由 [PagedController.clearCaches] 统一执行（切号必须调用）。
/// - **刷新排队**：刷新请求在途时重放（不静默丢弃）。
/// - **请求代次**：刷新 +1，过期响应一律丢弃（防重复条目 / 第一页缺失）。
/// - **释放保护**：`dispose` 之后不再通知、不再回写快照。
///
/// ## 用法
/// ```dart
/// late final PagedController<GhBranch> _paged = PagedController<GhBranch>(
///   loader: (int page) => api.branches(name, perPage: kPagedPageSize, page: page),
///   cacheKey: 'branches:$name',
///   onManualRefresh: () => api.invalidateReadCache(),
/// );
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 默认每页条数（调用方未显式传 [PagedController.pageSize] 时生效）。
///
/// **必须与调用方实际请求的 `per_page` 一致**。
/// 30 与仓库页的统一每页条数（`_kPageSize`）相同。
const int kPagedPageSize = 30;

// ─────────────────────────────────────────────────────────────────────────────
// 分页快照缓存（进程内共享）
// ─────────────────────────────────────────────────────────────────────────────

/// 一次成功的分页快照（供同目标的标签页重建后"秒开"，避免重复请求）。
class _CachedPage {
  const _CachedPage(this.at, this.items, this.done, this.page);

  final DateTime at;
  final List<Object?> items;
  final bool done;
  final int page;
}

/// 分页快照缓存（按 `cacheKey` 隔离）。
///
/// **保持文件级（= 进程内共享）而非实例级**：快照的意义就是跨实例 ——
/// `TabBarView` 会销毁不可见标签，切回来时重建的是**新的**控制器实例，
/// 只有实例之间共享同一份快照，重建才能"秒开"、不再重复请求；
/// 失效由 [PagedController.clearCaches] 统一执行（切号必须调用）。
final Map<String, _CachedPage> _recentPage = <String, _CachedPage>{};

/// 快照有效期：过期即回源。
const Duration _kPageCacheTtl = Duration(seconds: 6);

// ─────────────────────────────────────────────────────────────────────────────
// 分页控制器
// ─────────────────────────────────────────────────────────────────────────────

/// 通用分页控制器（首屏 + 加载更多 + 下拉刷新）。
///
/// 原为 `pages/repo_page.dart` 的私有 `_Paged<T>`（Phase 5 架构收敛时
/// 提取为 app 层公共控件，供各列表页统一使用）。语义逐条保留：
/// 快照（TTL / cacheKey）/ 刷新排队与请求代次 / 释放保护。
class PagedController<T> extends ChangeNotifier {
  PagedController({
    required this.loader,
    this.pageSize = kPagedPageSize,
    this.cacheKey,
    this.onManualRefresh,
  });

  /// 清空所有"按目标缓存"的分页快照。
  ///
  /// **切换账号时必须调用**：快照里可能含上一个账号可见的私有数据
  /// （用户要求：切号清除所有缓存）。
  static void clearCaches() => _recentPage.clear();

  /// 加载器：按页码取一页数据（页码从 1 开始）。
  final Future<List<T>> Function(int page) loader;

  /// 每页条数：必须与 [loader] 实际请求的 `per_page` 相同。
  ///
  /// 否则 [done] 的判定（`list.length < pageSize`）会失真：
  /// 提前结束（拉不到后续页）或永不结束（每页都判成"还有更多"）。
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
