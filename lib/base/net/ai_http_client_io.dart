/// L1 · AI 传输的原生实现（`dart:io`）。
///
/// 实现 `kernel/contract/ai_client.dart` 的 [AiHttpClient]。特点：
/// - **直连**，不经 GitHub 镜像 / 加速通道（密钥安全）；
/// - 真实 **SSE 流式**（`sendStream` 逐帧 `yield`，不缓冲整段）；
/// - **不自动重试**（AI 请求非幂等）；
/// - 单响应大小上限、连接超时；
/// - 日志零密钥 / 零响应体。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../kernel/contract/ai_client.dart';

/// 原生 AI HTTP 客户端。
class AiHttpClientIo implements AiHttpClient {
  const AiHttpClientIo();

  /// 非流式响应的字节上限（超出即判异常，避免恶意端点打爆内存）。
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

  HttpClient _client(Duration timeout) =>
      HttpClient()..connectionTimeout = timeout;

  @override
  Future<AiHttpResponse> send(
    String url, {
    Map<String, String> headers = const <String, String>{},
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    _validateEndpoint(url);
    final HttpClient client = _client(timeout);
    try {
      final HttpClientRequest req =
          await client.openUrl(body == null ? 'GET' : 'POST', Uri.parse(url));
      req.followRedirects = false;
      req.persistentConnection = false;
      headers.forEach(req.headers.set);
      req.headers.contentType = ContentType.json;
      if (body != null) {
        req.add(utf8.encode(jsonEncode(body)));
      }
      final HttpClientResponse res = await req.close();
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBodyBytes) {
          throw const AiTransportException('AI 响应体超过上限（8 MiB）');
        }
      }
      final Map<String, String> resHeaders = <String, String>{};
      res.headers.forEach((String name, List<String> values) {
        if (values.isNotEmpty) {
          resHeaders[name] = values.first;
        }
      });
      return AiHttpResponse(
        statusCode: res.statusCode,
        body: utf8.decode(bytes, allowMalformed: true),
        headers: resHeaders,
      );
    } on AiTransportException {
      rethrow;
    } on SocketException catch (e) {
      throw AiTransportException('连接失败：${e.message}');
    } on TimeoutException {
      throw const AiTransportException('连接超时');
    } on FormatException catch (e) {
      throw AiTransportException('响应不是合法 JSON：${e.message}');
    } finally {
      client.close(force: true);
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
    final HttpClient client = _client(timeout);
    try {
      final HttpClientRequest req = await client.openUrl('POST', Uri.parse(url));
      req.followRedirects = false;
      req.persistentConnection = false;
      headers.forEach(req.headers.set);
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.add(utf8.encode(jsonEncode(body)));

      final HttpClientResponse res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AiTransportException(
          'AI 端点返回 ${res.statusCode}',
          statusCode: res.statusCode,
        );
      }

      final Stream<String> lines =
          res.transform(utf8.decoder).transform(const LineSplitter());
      String event = '';
      String id = '';
      final List<String> dataLines = <String>[];

      await for (final String raw in lines) {
        final String line =
            raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
        if (line.isEmpty) {
          // 空行 = 一个事件结束，落盘一帧。
          if (dataLines.isNotEmpty) {
            yield AiSseEvent(
              event: event.isEmpty ? null : event,
              id: id.isEmpty ? null : id,
              data: dataLines.join('\n'),
            );
          }
          event = '';
          id = '';
          dataLines.clear();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring('data:'.length).trimLeft());
        } else if (line.startsWith('event:')) {
          event = line.substring('event:'.length).trim();
        } else if (line.startsWith('id:')) {
          id = line.substring('id:'.length).trim();
        }
        // 其它（注释 `:` / `retry:` 等）忽略。
      }
    } on AiTransportException {
      rethrow;
    } on SocketException catch (e) {
      throw AiTransportException('流式连接中断：${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}
