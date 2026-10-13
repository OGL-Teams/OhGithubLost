/// L0 · AI 传输契约。
///
/// 只定义「裸 HTTP + 流式」能力，**不感知任何 provider 协议**（OpenAI /
/// Claude / Gemini 的差异是 `domain/ai/ai_provider.dart` 的职责）。
///
/// ## 分层
/// - 本文件属 `kernel`（契约层），由 `base`（`ai_http_client_io.dart` /
///   `ai_http_client_web.dart`）实现、`domain`（`domain/ai/`）依赖；
/// - `domain` **不得** import `base` 的实现，只能依赖这里的抽象，
///   实现经 DI（`domain_bridge`）注入。
///
/// ## 安全约定（与 GitHub 镜像隔离）
/// AI 请求携带密钥，**绝不**走 GitHub 镜像 / 加速通道 / 代理 —— 只能直连
/// 用户在设置里填写的 HTTPS 端点；实现层必须：
/// 1. 拒绝非 HTTPS、带 userInfo、带 query/fragment 的地址；
/// 2. `followRedirects = false`（防密钥随重定向外泄）；
/// 3. 日志只记状态码，不记响应体、不记请求头里的密钥。
library;

/// 一次非流式 HTTP 响应的最小表示。
class AiHttpResponse {
  const AiHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// 一个 SSE 事件帧（已按空行切分、剥掉 `data:` / `event:` / `id:` 前缀）。
///
/// OpenAI 兼容流里一帧通常形如 `data: {"choices":[...]}`，`data` 字段即该
/// JSON 文本；`data: [DONE]` 为结束哨兵。
class AiSseEvent {
  const AiSseEvent({this.event, this.data, this.id});

  final String? event;
  final String? data;
  final String? id;

  bool get isDone => data == '[DONE]';

  @override
  String toString() =>
      'AiSseEvent(event: $event, id: $id, data: ${data?.length} chars)';
}

/// 传输层异常：**不携带响应体与密钥**，只含状态码与安全摘要。
///
/// 与 `AiException`（domain 层的业务错误）区分开：本异常表示「网络 / 超时 /
/// 非 2xx」，`detail` 只允许出现脱敏后的信息。
class AiTransportException implements AiException {
  const AiTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// 兼容 [AiException.code]：调用方用同一套 `on AiException` 捕获。
  @override
  String get code => 'transport';

  @override
  String get detail => message;

  @override
  String toString() => 'AiTransportException(${statusCode ?? '-'})：$message';
}

/// AI 供应商的裸 HTTP 传输。**不自动重试**——AI 请求非幂等，超时重试会重复计费 /
/// 重复产生副作用。
abstract class AiHttpClient {
  /// 非流式请求。失败抛 [AiTransportException]。
  Future<AiHttpResponse> send(
    String url, {
    Map<String, String> headers = const <String, String>{},
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 180),
  });

  /// SSE 流式请求。返回一个可取消的事件流（取消 = 关连接、中止解析）。
  ///
  /// 首个事件前若出错（连接失败 / 非 2xx / 超时），错误从流里抛出。
  Stream<AiSseEvent> stream(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 300),
  });
}
