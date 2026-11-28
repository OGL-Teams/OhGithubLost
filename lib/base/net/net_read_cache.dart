/// L1 底座级 · HTTP 读缓存（传输层装饰器）。
///
/// ## 为什么收在 net 层（席 C · 第三轮修复）
/// 此前「相似且无时效性要求的请求直接返回缓存」这一职责散落在 L2
/// 逻辑层：`GhReadCache`（domain，带 TTL 的端点白名单）+ `GhApi` 的
/// `_cacheKeyFor`/sha 前缀读穿透——每个调用点各自拼键、各自判新鲜度，
/// 重复且易漏。现在把**读路径的缓存命中**下沉到传输层：任何经过
/// [CacheTransport] 的 GET 自动获得命中即返回的能力，调用方无需感知。
///
/// ## 可缓存性判定（保守白名单）
/// - **只缓存 `GET`**：写方法一律直通（绝不缓存任何带副作用的往返）；
/// - **只缓存 2xx**（拒绝 206 截断体入缓存——见 gh_client 历史缺陷）；
/// - **带认证头的请求不缓存**：Authorization 随账号变化，缓存体会造成
///   跨账号内容泄漏；这条由调用方通过 [cacheable] 豁免（GhClient 已把
///   认证语义收敛在自己一侧，才允许对 GitHub API 的 GET 开缓存）；
/// - **缓存键 = method + URL + accept 头**：URL 已含 host/path/query；
///   accept 决定响应形态（JSON vs raw 媒体类型），参与键避免跨端点污染。
///
/// ## 介质选择：纯内存 LRU（进程内）
/// net 层不得依赖 domain（层级铁律），也无法引用 L0 之外的落盘契约；
/// 而本缓存要消除的是**同一次使用会话内的重复请求**（预览页 ↔ 编辑器
/// 来回打开同一文件），持久化交给 L1 `RepositoryCache` / L2 `GhReadCache`
/// 各自的落盘职责（见 docs/CONSISTENCY.md，D1–D9 语义不变）。
/// 内存 LRU 天然有界、无磁盘损坏面、无跨进程一致性问题。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../kernel/contract/net_types.dart';

/// 缓存条目：响应 + 抓取时刻 + 归属 URL（前缀失效用）。
class _CacheEntry {
  _CacheEntry(this.response, this.url, this.at);

  final NetResponse response;
  final String url;
  final DateTime at;
}

/// 读缓存装饰器：包在任意 [NetTransport] 外，命中即返回，未命中穿透。
///
/// 放置位置在 `ResilientTransport` **之外**：命中时连重试 / 镜像 / 观测
/// 都不发生——那才是「第二次打开不打网络」的完整语义。
class CacheTransport implements NetTransport, HttpReadCache {
  /// 创建读缓存传输。
  ///
  /// [maxEntries] 为 LRU 容量上限（有界，防长会话内存膨胀）；
  /// [maxAge] 为条目有效期（**无时效性要求只是"短窗口内可复用"**，
  /// 超时后回源，避免陈旧内容永远滞留）；
  /// [cacheable] 为可缓存判定（默认：GET 且不带 Authorization）。
  CacheTransport({
    required NetTransport inner,
    this.maxEntries = 64,
    this.maxAge = const Duration(minutes: 5),
    bool Function(NetRequest request)? cacheable,
  }) : _cacheable = cacheable ?? _defaultCacheable {
    _inner = inner;
  }

  /// 内层传输（`late final`：初始化列表里要引用 [maxEntries] 做断言，
  /// 故放构造体赋值）。
  late final NetTransport _inner;

  /// LRU 容量上限。
  final int maxEntries;

  /// 条目有效期。
  final Duration maxAge;

  final bool Function(NetRequest request) _cacheable;

  /// 插入序（LRU 淘汰用）：键 → 条目（Map 迭代序 = 插入序）。
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  /// 默认可缓存判定：GET 且请求头不含 Authorization。
  ///
  /// 这是传输层的**保守底线**：任何可能携带账号身份的响应都不入缓存。
  static bool _defaultCacheable(NetRequest request) =>
      request.method == NetMethod.get &&
      !request.headers.keys
          .any((String name) => name.toLowerCase() == 'authorization');

  /// 归一化缓存键：method + URL + accept。
  ///
  /// URL 含 host/path/query；accept 决定响应媒体类型形态
  /// （`application/vnd.github+json` vs `application/vnd.github.raw`），
  /// 不参与键会让"JSON 内容"命中"raw 请求"——跨端点污染。
  static String _keyOf(NetRequest request) {
    final String accept =
        request.headers['accept'] ?? request.headers['Accept'] ?? '';
    final String raw = '${request.method.verb}\n${request.url}\n$accept';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// 主动失效：按 URL 前缀清（写操作后由上层调用）。
  ///
  /// `null` 表示全清。返回清除条数（诊断用）。
  @override
  int invalidate({String? urlPrefix}) {
    if (urlPrefix == null) {
      final int n = _entries.length;
      _entries.clear();
      return n;
    }
    final List<String> doomed = <String>[
      for (final MapEntry<String, _CacheEntry> e in _entries.entries)
        if (e.value.url.startsWith(urlPrefix)) e.key,
    ];
    for (final String key in doomed) {
      _entries.remove(key);
    }
    return doomed.length;
  }

  /// 当前缓存条目数（诊断 / 测试用）。
  int get entryCount => _entries.length;

  @override
  Future<NetResponse> send(NetRequest request) async {
    if (!_cacheable(request)) {
      return _inner.send(request);
    }
    final String key = _keyOf(request);
    final _CacheEntry? hit = _entries[key];
    if (hit != null) {
      if (DateTime.now().difference(hit.at) <= maxAge) {
        // LRU 触碰：移到末尾（重新 put 即完成触碰）。
        _entries.remove(key);
        _entries[key] = hit;
        return hit.response;
      }
      _entries.remove(key); // 过期条目移除。
    }
    final NetResponse response = await _inner.send(request);
    if (response.isSuccess && response.statusCode != 206) {
      _entries[key] = _CacheEntry(response, request.url, DateTime.now());
      while (_entries.length > maxEntries) {
        _entries.remove(_entries.keys.first); // 淘汰最久未使用。
      }
    }
    return response;
  }
}
