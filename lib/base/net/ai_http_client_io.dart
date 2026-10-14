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

  /// 端点校验：**只拒绝真正不安全的形态**，不再强制 `https`。
  ///
  /// 为什么放宽（用户实测的痛点）：本机自建 / 内网反向代理 / 调试用的
  /// OpenAI 兼容端点**普遍是 `http://`**（例如 `http://127.0.0.1:11434`
  /// 的 Ollama、`http://host:8080/v1` 的 one-api）。旧实现一见非 https
  /// 就抛 [AiTransportException]，而设置页只 catch 业务异常 → 表现成
  /// 「未捕获异常 / 直接崩」，用户根本不知道自己填错了什么。
  ///
  /// 现在的分层：
  /// - 协议**不是** http/https（如 `ftp:`、空串）→ 拒绝（必错）；
  /// - 带 `userInfo`（`user:pass@host`，会泄露凭据进日志）/ `query`
  ///   / `fragment`（端点不该带这些）→ 拒绝（构造约定）；
  /// - host 为空 → 拒绝；
  /// - `http://` 且 host 是**本机/回环**（localhost / 127.0.0.1 / ::1）→
  ///   **放行**（本机传输不经过网络，明文可接受）；
  /// - 其它 `http://` → **放行**（跨国/内网场景常见），由调用方（设置页）
  ///   给出"明文传输"的可见提示，但**不阻止用户使用**。
  void _validateEndpoint(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw const AiTransportException(
          'AI 端点地址无效（示例：https://api.openai.com/v1）');
    }
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const AiTransportException('AI 端点协议必须是 http 或 https（不支持 ftp、ws 等）');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const AiTransportException('AI 端点不允许携带用户名与密码（user:pass@）');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const AiTransportException('AI 端点不允许携带 ?查询参数 或 #片段');
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
      final HttpClientRequest req =
          await client.openUrl('POST', Uri.parse(url));
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
