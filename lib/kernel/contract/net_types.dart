/// L1 底座级 · 网络连接：请求 / 响应 / 错误 / 观测 的基础类型。
///
/// 本文件**不含任何传输实现**（不依赖 HTTP 客户端），
/// 目的是让重试、镜像、观测等核心逻辑可以完全离线单测。
library;

/// HTTP 方法（覆盖仓库管理所需）。
///
/// 新增方法时必须同步 `NetMethod`、传输实现与镜像策略。
enum NetMethod {
  /// GET。
  get('GET'),

  /// POST。
  post('POST'),

  /// PUT。
  put('PUT'),

  /// PATCH。
  patch('PATCH'),

  /// DELETE。
  delete('DELETE'),

  /// HEAD。
  head('HEAD');

  const NetMethod(this.verb);

  /// 传输层使用的动词字符串（大写）。
  final String verb;
}

/// 传输错误分类：决定"是否重试"与"给用户看什么"。
enum NetErrorKind {
  /// 连接失败（DNS / 握手 / 断网）。
  connection,

  /// 超时。
  timeout,

  /// 服务端 5xx。
  server,

  /// 限流（403 / 429 且配额耗尽）。
  rateLimited,

  /// 客户端 4xx（不可重试）。
  client,

  /// 证书 / TLS。
  tls,

  /// 调用方主动取消。
  cancelled,

  /// 未能归类。
  unknown;

  /// 是否属于"可重试"类别（幂等语义由调用方保证）。
  ///
  /// [NetErrorKind.unknown] 也列入：`dart:io` 会把"连接在接收中被关闭"等
  /// 场景归为未分类异常，而对幂等方法而言它们只是瞬时失败。真正是否重试
  /// 仍受调用方的幂等集合约束（见 `ResilientTransport.retryableMethods`），
  /// 因此 `POST` 一类非幂等请求依旧不会被自动重试。
  bool get isRetryable =>
      this == NetErrorKind.connection ||
      this == NetErrorKind.timeout ||
      this == NetErrorKind.server ||
      this == NetErrorKind.rateLimited ||
      this == NetErrorKind.unknown;
}

/// 网络层统一异常。
///
/// 约定：**所有** 传输实现都必须把底层异常（HttpClient / Socket / TLS）翻译成本类型，
/// 上层（中枢 / 交互）只认识它——这样重试与提示逻辑只有一处。
class NetException implements Exception {
  /// 创建异常。
  const NetException(
    this.kind,
    this.message, {
    this.statusCode,
    this.cause,
    this.retryAfter,
    this.body,
  });

  /// 错误类别。
  final NetErrorKind kind;

  /// 人类可读说明。
  final String message;

  /// HTTP 状态码（若已拿到响应）。
  final int? statusCode;

  /// 原始异常。
  final Object? cause;

  /// 服务端要求的等待时长（`Retry-After`）。
  final Duration? retryAfter;

  /// 响应体片段（**仅在重试耗尽抛错时**携带，便于上层读取服务端错误说明）。
  final String? body;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' $statusCode';
    return 'NetException(${kind.name}$code): $message';
  }
}

/// 传输请求（不可变）。
class NetRequest {
  /// 创建请求。
  const NetRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
    this.timeout = const Duration(seconds: 30),
    this.label,
  });

  /// 方法。
  final NetMethod method;

  /// 完整 URL。
  final String url;

  /// 请求头。
  final Map<String, String> headers;

  /// 请求体（字符串或字节；`null` 表示无体）。
  final Object? body;

  /// 单次请求超时。
  final Duration timeout;

  /// 诊断标签（如 `GET /repos`），不参与请求。
  final String? label;

  /// 复制并覆盖部分字段（镜像回落、追加头时使用）。
  NetRequest copyWith({
    String? url,
    Map<String, String>? headers,
    String? label,
  }) =>
      NetRequest(
        method: method,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        body: body,
        timeout: timeout,
        label: label ?? this.label,
      );

  @override
  String toString() => 'NetRequest(${method.verb} ${label ?? url}'
      '${headers.isEmpty ? '' : ' headers=${headers.length}'})';
}

/// 传输响应（不可变）。
class NetResponse {
  /// 创建响应。
  const NetResponse({
    required this.statusCode,
    required this.body,
    required this.duration,
    this.headers = const <String, String>{},
    this.fromMirrorId,
  });

  /// HTTP 状态码。
  final int statusCode;

  /// 响应体（UTF-8 文本；二进制场景由上层再解码）。
  final String body;

  /// 端到端耗时。
  final Duration duration;

  /// 响应头（键统一小写）。
  final Map<String, String> headers;

  /// 若经镜像通道返回，记录通道 ID（否则 `null`）。
  final String? fromMirrorId;

  /// 是否 2xx。
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// 响应体字符数（观测指标；UTF-8 字节数由观测层另计）。
  int get bodyLength => body.length;

  /// 实体标签（缓存条件请求用）。
  String? get etag => headers['etag'];

  @override
  String toString() => 'NetResponse($statusCode, ${bodyLength}B, '
      '${duration.inMilliseconds}ms'
      '${fromMirrorId == null ? '' : ', via=$fromMirrorId'})';
}

/// 解析 `Retry-After` 响应头（秒数或 HTTP 日期；无法解析返回 `null`）。
///
/// **唯一实现处**：传输层（异常路径）与韧性层（响应路径）共用同一份逻辑，
/// 不允许各自复制一份再慢慢漂移。
Duration? parseRetryAfterHeader(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final seconds = int.tryParse(raw.trim());
  if (seconds != null) {
    return Duration(seconds: seconds);
  }
  try {
    final target = DateTime.parse(raw);
    final delta = target.difference(DateTime.now());
    return delta.isNegative ? null : delta;
  } catch (_) {
    return null;
  }
}

/// 网络观测快照（诊断报告 / 状态页数据源）。
class NetStats {
  /// 创建快照。
  const NetStats({
    this.requests = 0,
    this.failures = 0,
    this.retries = 0,
    this.mirrorSwitches = 0,
    this.bytesIn = 0,
    this.totalLatency = Duration.zero,
  });

  /// 发起请求总数（含重试）。
  final int requests;

  /// 失败总数。
  final int failures;

  /// 重试次数。
  final int retries;

  /// 镜像切换次数。
  final int mirrorSwitches;

  /// 累计接收字节（按字符计）。
  final int bytesIn;

  /// 累计耗时。
  final Duration totalLatency;

  /// 平均耗时（无请求时为 [Duration.zero]）。
  Duration get averageLatency => requests == 0
      ? Duration.zero
      : Duration(microseconds: totalLatency.inMicroseconds ~/ requests);

  /// 序列化（审计导出 / 状态页）。
  Map<String, Object?> toJson() => <String, Object?>{
        'requests': requests,
        'failures': failures,
        'retries': retries,
        'mirrorSwitches': mirrorSwitches,
        'bytesIn': bytesIn,
        'avgMs': averageLatency.inMicroseconds / 1000,
      };

  @override
  String toString() => 'NetStats(req=$requests, fail=$failures, '
      'retry=$retries, mirror=$mirrorSwitches, in=${bytesIn}B)';
}

/// 网络观测器：**只记账，不决策**。
///
/// 决策（是否重试、是否走镜像）属于 [ResilientTransport] 与策略对象，
/// 观测器保持纯粹，便于在高频路径上零副作用地采集指标。
class NetObserver {
  int _requests = 0;
  int _failures = 0;
  int _retries = 0;
  int _mirrorSwitches = 0;
  int _bytesIn = 0;
  Duration _latency = Duration.zero;

  /// 请求发出前调用。
  void onRequest(NetRequest request) {
    _requests++;
  }

  /// 响应返回后调用（含非 2xx）。
  void onResponse(NetResponse response) {
    _bytesIn += response.bodyLength;
    _latency += response.duration;
  }

  /// 决定重试时调用。
  void onRetry(NetRequest request, int attempt, String reason) {
    _retries++;
  }

  /// 切换到镜像通道时调用。
  void onMirror(NetRequest request, String mirrorId) {
    _mirrorSwitches++;
  }

  /// 请求最终失败时调用。
  void onFailure(NetRequest request, Object error) {
    _failures++;
  }

  /// 清空计数（"重置统计"场景）。
  void reset() {
    _requests = 0;
    _failures = 0;
    _retries = 0;
    _mirrorSwitches = 0;
    _bytesIn = 0;
    _latency = Duration.zero;
  }

  /// 当前快照。
  NetStats snapshot() => NetStats(
        requests: _requests,
        failures: _failures,
        retries: _retries,
        mirrorSwitches: _mirrorSwitches,
        bytesIn: _bytesIn,
        totalLatency: _latency,
      );
}
