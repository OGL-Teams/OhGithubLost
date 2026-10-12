/// L1 · AI 传输的浏览器实现（`package:http` 的 `BrowserClient`）。
///
/// 与原生 [AiHttpClientIo] 的差别：
/// - `send` 走 `package:http`（底层是浏览器 fetch / XHR）；
/// - `stream` **非增量**：先缓冲整段响应再解析 SSE（浏览器端拿增量流的
///   `ReadableStream` 需要手写 `dart:js_interop` 的 reader 循环，风险高、
///   收益有限 —— 先保证功能正确，原生端是真流式，web 端退化为整段解析）。
///
/// 安全约定与原生一致：直连、拒非 HTTPS、不重定向、日志零密钥零响应体。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../kernel/contract/ai_client.dart';

/// 浏览器 AI HTTP 客户端。
class AiHttpClientWeb implements AiHttpClient {
  AiHttpClientWeb({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const int _maxBodyBytes = 8 * 1024 * 1024;

  void _validateEndpoint(String url) {
    final Uri uri = Uri.tryParse(url) ?? Uri();
    final bool bad = uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment;
    if (bad) {
      throw AiTransportException('AI 端点必须是纯 HTTPS 地址（不允许 userInfo/query/fragment）');
    }
  }

  @override
  Future<AiHttpResponse> send(
    String url, {
    Map<String, String> headers = const <String, String>{},
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    _validateEndpoint(url);
    try {
      final http.Response res = await _client
          .post(
            Uri.parse(url),
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout);
      return AiHttpResponse(
        statusCode: res.statusCode,
        body: res.body,
        headers: res.headers,
      );
    } on TimeoutException {
      throw const AiTransportException('连接超时');
    } on http.ClientException catch (e) {
      throw AiTransportException('连接失败：${e.message}');
    }
  }

  @override
  Stream<AiSseEvent> stream(
    String url, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 300),
  }) async* {
    _validateEndpoint(url);
    final http.Response res = await _client
        .post(
          Uri.parse(url),
          headers: <String, String>{...headers, 'accept': 'text/event-stream'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiTransportException('AI 端点返回 ${res.statusCode}', statusCode: res.statusCode);
    }
    if (res.bodyBytes.length > _maxBodyBytes) {
      throw const AiTransportException('AI 响应体超过上限（8 MiB）');
    }
    for (final AiSseEvent e in _parseSse(res.body)) {
      yield e;
    }
  }

  /// 把一个完整 SSE 文本体解析成事件列表。
  static List<AiSseEvent> _parseSse(String body) {
    final List<AiSseEvent> out = <AiSseEvent>[];
    String event = '';
    String id = '';
    final List<String> data = <String>[];
    void flush() {
      if (data.isNotEmpty) {
        out.add(AiSseEvent(
          event: event.isEmpty ? null : event,
          id: id.isEmpty ? null : id,
          data: data.join('\n'),
        ));
      }
      event = '';
      id = '';
      data.clear();
    }

    for (final String raw in body.split('\n')) {
      final String line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        flush();
      } else if (line.startsWith('data:')) {
        data.add(line.substring('data:'.length).trimLeft());
      } else if (line.startsWith('event:')) {
        event = line.substring('event:'.length).trim();
      } else if (line.startsWith('id:')) {
        id = line.substring('id:'.length).trim();
      }
    }
    flush();
    return out;
  }
}
