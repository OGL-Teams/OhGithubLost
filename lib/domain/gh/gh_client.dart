/// L2 中枢级 · API 逻辑：GitHub 请求客户端。
///
/// ## 它负责的五件事（其余一概不管）
/// 1. **认证头**：从保险库取当前账号令牌，注入 `Authorization`；
/// 2. **限流避让**：解析 `x-ratelimit-*`，**剩余为 0 时不发请求**，直接告知何时恢复；
/// 3. **并发上限**：批量操作排队，避免触发 Secondary Rate Limit；
/// 4. **分页**：解析 `Link` 头，提供安全上限的流式遍历；
/// 5. **错误映射**：把 HTTP 语义翻译成**类型化异常**（401/403/404/409/422/限流）。
///
/// ## 不做的事
/// 不做缓存、不做业务模型、不做重试（重试在底座 [ResilientTransport] 里）。
library;

import 'dart:async';
import 'dart:convert';

import '../../base/net/net_bridge.dart';
import '../../kernel/contract/disk_types.dart';
import '../../kernel/contract/net_types.dart';
import '../../kernel/diagnostics.dart';
import '../../kernel/log/og_l_log_file.dart';
import 'gh_auth.dart';
import 'gh_models.dart';
import 'gh_read_cache.dart';

/// 限流额度快照。
class GhRateLimit {
  /// 创建额度。
  const GhRateLimit({
    required this.limit,
    required this.remaining,
    required this.resetAt,
    this.resource = 'core',
  });

  /// 上限。
  final int limit;

  /// 剩余。
  final int remaining;

  /// 恢复时间。
  final DateTime resetAt;

  /// 资源类别（`core` / `search` / `graphql`）。
  final String resource;

  /// 是否已耗尽。
  bool get isExhausted => remaining <= 0;

  /// 距恢复还有多久。
  Duration get untilReset {
    final delta = resetAt.difference(DateTime.now());
    return delta.isNegative ? Duration.zero : delta;
  }

  /// 从响应头解析（缺头时返回 `null`）。
  static GhRateLimit? fromHeaders(Map<String, String> headers) {
    final limit = int.tryParse(headers['x-ratelimit-limit'] ?? '');
    final remaining = int.tryParse(headers['x-ratelimit-remaining'] ?? '');
    final resetEpoch = int.tryParse(headers['x-ratelimit-reset'] ?? '');
    if (limit == null || remaining == null || resetEpoch == null) {
      return null;
    }
    return GhRateLimit(
      limit: limit,
      remaining: remaining,
      resetAt: DateTime.fromMillisecondsSinceEpoch(
        resetEpoch * 1000,
        isUtc: true,
      ),
      resource: headers['x-ratelimit-resource'] ?? 'core',
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'limit': limit,
        'remaining': remaining,
        'resetAt': resetAt.toIso8601String(),
        'resource': resource,
      };

  @override
  String toString() =>
      'GhRateLimit($remaining/$limit, reset in ${untilReset.inMinutes}min)';
}

/// 未认证 / 令牌失效。
class GhAuthException implements Exception {
  /// 创建异常。
  const GhAuthException(this.message, {this.statusCode});

  /// 说明。
  final String message;

  /// 状态码。
  final int? statusCode;

  @override
  String toString() => 'GhAuthException(${statusCode ?? '-'}): $message';
}

/// 限流（含 Secondary Rate Limit）。
class GhRateLimitException implements Exception {
  /// 创建异常。
  const GhRateLimitException({
    required this.message,
    this.resetAt,
    this.retryAfter,
    this.secondary = false,
  });

  /// 说明。
  final String message;

  /// 主限流恢复时间。
  final DateTime? resetAt;

  /// 次要限流的退避建议。
  final Duration? retryAfter;

  /// 是否为次要限流（短时高频触发）。
  final bool secondary;

  @override
  String toString() =>
      'GhRateLimitException(${secondary ? 'secondary' : 'primary'}): $message';
}

/// 资源不存在 / 无权限。
class GhNotFoundException implements Exception {
  /// 创建异常。
  const GhNotFoundException(this.path);

  /// 请求路径。
  final String path;

  @override
  String toString() => 'GhNotFoundException($path)';
}

/// 写冲突分类（**领域层投影**）。
///
/// 底座 `WriteConflict` 属于 L1，展示层不得直接依赖；
/// 这里做一层同构投影，让 UI 只认识领域类型。
enum GhWriteConflict {
  /// 无冲突。
  none,

  /// 缺少基线，需先读。
  requiresRead,

  /// 基线过期（远端已被别人改动）——**最常见的误覆盖风险**。
  staleSha,

  /// 危险 / 强制操作需二次确认。
  needsConfirmation,

  /// 目标不存在。
  notFound,

  /// 权限不足。
  forbidden,

  /// 服务端错误。
  server,

  /// 写后回读校验失败。
  verificationFailed,
}

/// 一次加锁写入的结果（供展示层消费；**永不抛**）。
class GhWriteResult {
  /// 创建结果。
  const GhWriteResult({
    required this.ok,
    required this.conflict,
    this.sha,
    this.baseSha,
    this.detail,
    this.remoteContent,
    this.baseContent,
    this.localContent,
  });

  /// 是否成功。
  final bool ok;

  /// 冲突分类。
  final GhWriteConflict conflict;

  /// 成功后的新版本指纹（冲突时为远端最新指纹）。
  final String? sha;

  /// 本次写入所基于的基线指纹。
  final String? baseSha;

  /// 失败说明（D6：必须可感知）。
  final String? detail;

  /// 冲突时的远端内容（可能为 `null` = 未取到）。
  final String? remoteContent;

  /// 冲突时的基线内容（本地缓存仍持有才给）。
  final String? baseContent;

  /// 冲突时用户要写入的本地内容。
  final String? localContent;

  /// 是否允许"查看差异"（三方内容任一可用）。
  bool get canViewDiff =>
      conflict == GhWriteConflict.staleSha ||
      remoteContent != null ||
      baseContent != null;

  /// 是否允许"强制覆盖"（仅基线过期时提供）。
  bool get canForceOverwrite => conflict == GhWriteConflict.staleSha;

  @override
  String toString() => 'GhWriteResult(ok=$ok, conflict=${conflict.name}'
      '${detail == null ? '' : ', detail=$detail'})';
}

/// 一次请求。
class GhRequest {
  /// 创建请求。
  const GhRequest({
    required this.path,
    this.method = NetMethod.get,
    this.query = const <String, String>{},
    this.body,
    this.label,
    this.headers = const <String, String>{},
    this.conflictsAsRemoteConflict = false,
    this.cacheBypass = false,
  });

  /// 路径（`/repos/...`）或完整 URL。
  final String path;

  /// 方法。
  final NetMethod method;

  /// 查询参数。
  final Map<String, String> query;

  /// 请求体（会被 JSON 编码）。
  final Object? body;

  /// 诊断标签。
  final String? label;

  /// **额外请求头**（覆盖同名默认头）。
  ///
  /// 默认头已含 `accept` / `x-github-api-version` / `authorization`；
  /// 需要特殊媒体类型时（例如代码搜索的
  /// `application/vnd.github.text-match+json`）从这里显式覆盖。
  final Map<String, String> headers;

  /// 409/422 是否翻译成 [RemoteConflictException]（内容读写场景需要）。
  final bool conflictsAsRemoteConflict;

  /// 本次请求是否**绕过只读缓存**（下拉刷新 / 写后重读时置真）。
  final bool cacheBypass;

  /// 拼出完整 URL。
  String toUrl(String base) {
    final buffer = StringBuffer(path.startsWith('http') ? path : '$base$path');
    if (query.isEmpty) {
      return buffer.toString();
    }
    final parts = query.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .toList();
    return '$buffer${buffer.toString().contains('?') ? '&' : '?'}${parts.join('&')}';
  }
}

/// 一次响应。
class GhResponse {
  /// 创建响应。
  const GhResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    this.rateLimit,
  });

  /// 状态码。
  final int statusCode;

  /// 原始文本。
  final String body;

  /// 响应头。
  final Map<String, String> headers;

  /// 限流快照。
  final GhRateLimit? rateLimit;

  /// 是否成功。
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// 分页信息。
  GhPage get page => GhPage.parse(headers['link']);

  /// 解析为对象 Map（失败返回 `null`）。
  Map<String, dynamic>? get jsonObject {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析为对象列表（失败返回空列表）。
  List<Map<String, dynamic>> get jsonList {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        return const <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// 解析列表或单个对象（GitHub 部分端点两种都可能返回）。
  List<Map<String, dynamic>> get jsonAsList {
    final asList = jsonList;
    if (asList.isNotEmpty) {
      return asList;
    }
    final asObject = jsonObject;
    return asObject == null
        ? const <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[asObject];
  }

  @override
  String toString() => 'GhResponse($statusCode, ${body.length}B)';
}

/// 并发闸门（信号量）。
///
/// **许可转交语义**：`release` 时若有等待者，直接把"许可"转交给队首等待者，
/// 期间 `_used` **保持不变** —— 这样从"释放"到"等待者恢复执行"的时间窗里，
/// 新来的 `acquire` 不会把同一个许可二次放行（否则并发上限会被击穿）。
class _Semaphore {
  _Semaphore(this.permits);

  final int permits;
  int _used = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> acquire() async {
    if (_used < permits) {
      _used++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    // 许可由 release() 直接转交（它未被归还到计数池），这里不再自增。
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // 转交：许可从释放者交给等待者，`_used` 不变。
      _waiters.removeAt(0).complete();
      return;
    }
    if (_used > 0) {
      _used--;
    }
  }

  /// 当前在用数量（诊断）。
  int get inUse => _used;
}

/// GitHub 客户端。
class GhClient {
  /// 创建客户端。
  GhClient({
    required NetBridge net,
    required GhAuthService auth,
    this.baseUrl = 'https://api.github.com',
    int maxConcurrent = 4,
    KernelDiagnostics? diagnostics,
  })  : _net = net,
        _auth = auth,
        _semaphore = _Semaphore(maxConcurrent),
        _diagnostics = diagnostics;

  /// 默认 API 根。
  final String baseUrl;

  final NetBridge _net;
  final GhAuthService _auth;
  final _Semaphore _semaphore;
  KernelDiagnostics? _diagnostics;

  /// 只读端点缓存（装配期由 `domain_bridge` 注入；未注入则不缓存）。
  GhReadCache? _readCache;

  /// 绑定只读端点缓存。
  void attachReadCache(GhReadCache cache) {
    _readCache = cache;
  }

  /// 让只读缓存整体失效（切换账号 / 用户手动清缓存）。
  Future<void> invalidateReadCache() async {
    await _readCache?.clear();
  }

  /// 按路径给出只读缓存 TTL；`null` 表示**不缓存**。
  ///
  /// 原则：只缓存"变化慢、可容忍短暂陈旧"的只读列表 / 详情；
  /// 内容端点（含 `/contents`）交给底座 [RepositoryCache]，搜索与
  /// 用户 / 限流端点**不缓存**（必须新鲜）。
  static Duration? ttlForPath(String path) {
    if (path.startsWith('http')) {
      return null;
    }
    if (path.startsWith('/search/')) {
      return null;
    }
    if (path.contains('/rate_limit')) {
      return null;
    }
    // 内容读写由底座一致性缓存负责，这里不重复缓存。
    if (path.contains('/contents')) {
      return null;
    }
    // 仅放行明确的只读端点前缀。
    if (path.startsWith('/user/repos') || path.startsWith('/user/starred')) {
      return const Duration(seconds: 30);
    }
    if (path.startsWith('/user')) {
      return null;
    }
    if (RegExp(r'^/(users|orgs)/[^/]+/repos$').hasMatch(path)) {
      return const Duration(seconds: 60);
    }
    if (path.contains('/actions/runs')) {
      return const Duration(seconds: 30);
    }
    if (path.contains('/releases') ||
        path.contains('/branches') ||
        path.contains('/commits') ||
        path.contains('/issues') ||
        path.contains('/pulls') ||
        path.contains('/readme') ||
        path.contains('/labels') ||
        path.contains('/actions/workflows')) {
      return const Duration(seconds: 60);
    }
    // 仓库详情：`/repos/{owner}/{repo}`（恰好两段）。
    if (RegExp(r'^/repos/[^/]+/[^/]+$').hasMatch(path)) {
      return const Duration(seconds: 60);
    }
    return null;
  }

  GhRateLimit? _lastRateLimit;

  /// 按资源类别维护的最近额度（`core` / `search` / `graphql`…）。
  ///
  /// **为什么不是单槽**：GitHub 对不同资源独立计数。若只存"最近一条"，
  /// search 额度耗尽会把 core 请求一并拦下（误伤）；core 耗尽后，
  /// 一次 search 响应又会把判断覆盖成"有额度"——两个方向都会出错。
  final Map<String, GhRateLimit> _rateLimits = <String, GhRateLimit>{};

  /// 最近一次已知额度（供仪表盘展示）。
  GhRateLimit? get lastRateLimit => _lastRateLimit;

  /// 某资源类别是否已知耗尽（诊断用）。
  bool isResourceExhausted(String resource) {
    final known = _rateLimits[resource];
    return known != null &&
        known.isExhausted &&
        known.untilReset > Duration.zero;
  }

  /// 由请求路径推导限流资源类别（与 GitHub 的分类一致）。
  static String resourceOfPath(String path) {
    if (path.startsWith('/search/')) {
      return 'search';
    }
    if (path.startsWith('/graphql')) {
      return 'graphql';
    }
    return 'core';
  }

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 发送请求。
  ///
  /// 抛：[GhAuthException] / [GhRateLimitException] / [GhNotFoundException] /
  /// [RemoteConflictException]（按需）。
  Future<GhResponse> send(GhRequest request) async {
    // ── 只读缓存（R4）：命中即返回，不打网络、不占额度 ──────────────────
    // 仅对白名单内的 GET 生效；被显式 bypass（下拉刷新 / 写后重读）时跳过。
    final Duration? cacheTtl =
        (request.method == NetMethod.get && !request.cacheBypass)
            ? ttlForPath(request.path)
            : null;
    if (cacheTtl != null) {
      final ({String body, String link})? cached =
          await _readCache?.get(request.path, request.query, cacheTtl);
      if (cached != null) {
        _diagnostics?.debug(
          'CACHE',
          '${request.method.verb} ${request.path} → 只读缓存命中',
          data: <String, Object?>{'ttlSeconds': cacheTtl.inSeconds},
        );
        // 回填 Link 头（有的话），否则分页会停在第一页。
        return GhResponse(
          statusCode: 200,
          body: cached.body,
          headers: cached.link.isEmpty
              ? const <String, String>{}
              : <String, String>{'link': cached.link},
        );
      }
    }

    // 限流避让：**按资源类别**判断已知耗尽，省下一次注定 403 的往返；
    // search 的额度耗尽**不会**阻塞 core 请求（各自独立计数）。
    final resource = resourceOfPath(request.path);
    final known = _rateLimits[resource];
    if (known != null &&
        known.isExhausted &&
        known.untilReset > Duration.zero) {
      throw GhRateLimitException(
        message: '$resource 额度已耗尽，将在 ${known.untilReset.inMinutes} 分钟后恢复',
        resetAt: known.resetAt,
      );
    }

    await _semaphore.acquire();
    try {
      final token = await _auth.activeToken();
      final headers = <String, String>{
        'accept': 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
        if (token != null) 'authorization': 'Bearer ${token.value}',
        // 显式请求头最后合并（同名覆盖默认值——例如代码搜索的
        // `application/vnd.github.text-match+json`）。
        ...request.headers,
      };
      OgLLogFile.line(
        '网络',
        '→ ${request.method.verb} ${request.path}'
            '${request.query.isEmpty ? '' : '?${request.query.entries.map((e) => '${e.key}=${e.value}').join('&')}'}',
      );
      final netResponse = await _net.send(NetRequest(
        method: request.method,
        url: request.toUrl(baseUrl),
        headers: headers,
        body: request.body == null ? null : jsonEncode(request.body),
        timeout: const Duration(seconds: 30),
        label: request.label ?? '${request.method.verb} ${request.path}',
      ));

      final rateLimit = GhRateLimit.fromHeaders(netResponse.headers);
      if (rateLimit != null) {
        _lastRateLimit = rateLimit;
        _rateLimits[rateLimit.resource] = rateLimit;
      }
      final response = GhResponse(
        statusCode: netResponse.statusCode,
        body: netResponse.body,
        headers: netResponse.headers,
        rateLimit: rateLimit,
      );
      _diagnostics?.debug(
        'GH',
        '${request.method.verb} ${request.path} → ${response.statusCode}',
        data: <String, Object?>{
          if (rateLimit != null) 'remaining': rateLimit.remaining,
        },
      );

      OgLLogFile.line(
        '网络',
        '← ${response.statusCode} ${request.method.verb} ${request.path}'
            '（${netResponse.bodyLength} 字符 / ${netResponse.duration.inMilliseconds}ms'
            '${rateLimit == null ? '' : ' / 余量 ${rateLimit.remaining}'}'
            '${netResponse.fromMirrorId == null ? '' : ' / 镜像 ${netResponse.fromMirrorId}'}）',
      );
      // ── 只读缓存回填 / 失效（R4）──────────────────────────────────────
      if (response.isSuccess) {
        if (request.method == NetMethod.get && cacheTtl != null) {
          await _readCache?.put(
            request.path,
            request.query,
            response.body,
            link: response.headers['link'] ?? '',
          );
        }
      }
      if (request.method != NetMethod.get && response.isSuccess) {
        // 写操作让只读缓存整体失效：陈旧列表 = 错误信息。
        await _readCache?.clear();
      }
      try {
        _throwIfFailed(response, request);
        return response;
      } catch (error) {
        // 失败要**看得见**：状态码 + 映射后的异常类型 + 服务端原话。
        // 404 属"语义性不存在"——很多读取就是把 404 当"没有"（仓库没有
        // README / CNAME / Pages），故降级为 WARN：否则日志会被正常缺省刷屏，
        // 也容易把"没有"误读成故障。
        final String level = error is GhNotFoundException ? 'WARN' : 'ERR';
        OgLLogFile.line(
          '网络',
          '${request.method.verb} ${request.path} -> ${response.statusCode}：$error',
          level: level,
        );
        rethrow;
      }
    } finally {
      _semaphore.release();
    }
  }

  /// 便捷：GET 对象。
  Future<Map<String, dynamic>?> getObject(
    String path, {
    Map<String, String> query = const <String, String>{},
    String? label,
  }) async {
    final response =
        await send(GhRequest(path: path, query: query, label: label));
    return response.jsonObject;
  }

  /// 便捷：GET 列表（含单对象兼容）。
  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, String> query = const <String, String>{},
    String? label,
  }) async {
    final response =
        await send(GhRequest(path: path, query: query, label: label));
    return response.jsonAsList;
  }

  /// 分页遍历。
  ///
  /// [maxPages] 是**安全上限**：GitHub 某些端点会返回极大的 `last`，
  /// 无上限遍历会烧光额度。默认 10 页足够仓库管理场景。
  Stream<List<Map<String, dynamic>>> paginate(
    String path, {
    Map<String, String> query = const <String, String>{},
    int perPage = 100,
    int maxPages = 10,
  }) async* {
    var page = 1;
    while (page <= maxPages) {
      final response = await send(GhRequest(
        path: path,
        query: <String, String>{
          ...query,
          'per_page': '$perPage',
          'page': '$page',
        },
        label: 'GET $path (page $page)',
      ));
      final items = response.jsonAsList;
      if (items.isEmpty) {
        return;
      }
      yield items;
      final next = response.page.next;
      if (next == null) {
        return;
      }
      page++;
    }
    _diagnostics?.warn(
      'GH',
      '分页达到安全上限 $maxPages，已停止（避免烧光额度）',
      code: 'OGL-GH-101',
      data: <String, Object?>{'path': path},
    );
  }

  void _throwIfFailed(GhResponse response, GhRequest request) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return;
    }
    switch (status) {
      case 401:
        // ★ 认证失效的**全局唯一出口**：标记状态，外壳据此自动回登录门。
        _auth.markExpired('令牌无效或已过期，请重新授权');
        throw const GhAuthException(
          '令牌无效或已过期，请重新授权',
          statusCode: 401,
        );
      case 403:
      case 429:
        final retryAfter = _retryAfterOf(response);
        final remaining = response.rateLimit?.remaining;
        if (remaining != null && remaining <= 0) {
          throw GhRateLimitException(
            message: '额度耗尽',
            resetAt: response.rateLimit?.resetAt,
          );
        }
        // 429 或带 Retry-After 的 403 = 限流（次要限流）。
        // 注意：429 即使没有 Retry-After 头也**必须**归为限流——
        // 此前会掉到下面的"权限不足"，把限流误报成权限问题（误导排查方向）。
        if (status == 429 || retryAfter != null) {
          throw GhRateLimitException(
            message: '触发次要限流，建议退避后重试',
            retryAfter: retryAfter,
            secondary: true,
          );
        }
        throw GhAuthException(
          '权限不足（缺少 repo 等作用域）',
          statusCode: 403,
        );
      case 404:
        throw GhNotFoundException(request.path);
      case 409:
      case 422:
        if (request.conflictsAsRemoteConflict) {
          throw RemoteConflictException(
            statusCode: status,
            currentSha: _currentShaOf(response),
            message: '远端版本已变化',
          );
        }
        throw GhAuthException(
          '请求被拒绝（HTTP $status）：${_snippet(response.body)}',
          statusCode: status,
        );
      default:
        throw GhAuthException(
          '请求失败（HTTP $status）：${_snippet(response.body)}',
          statusCode: status,
        );
    }
  }

  static Duration? _retryAfterOf(GhResponse response) {
    final raw = response.headers['retry-after'];
    final seconds = int.tryParse(raw ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static String? _currentShaOf(GhResponse response) {
    final object = response.jsonObject;
    final sha = object?['sha'];
    return sha is String ? sha : null;
  }

  static String _snippet(String body) =>
      body.length <= 160 ? body : '${body.substring(0, 160)}…';
}
