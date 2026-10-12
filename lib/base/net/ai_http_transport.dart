/// AI 独立传输：不经 GitHub 镜像，不允许携带密钥的请求重定向。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 每次请求独立关闭连接；错误只含状态码，禁止响应体和密钥进入日志。
class AiHttpTransport {
  Future<Map<String, dynamic>> send(
    String url,
    Map<String, String> headers,
    Map<String, Object?>? body,
  ) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      throw const FormatException('HTTPS API endpoint required');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          uri,
        );
        request.followRedirects = false;
        request.persistentConnection = false;
        headers.forEach(request.headers.set);
        request.headers.contentType = ContentType.json;
        if (body != null) {
          request.add(utf8.encode(jsonEncode(body)));
        }
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('AI HTTP ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 4000000) {
            throw const FormatException('AI response too large');
          }
        }
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      })().timeout(const Duration(seconds: 180));
    } finally {
      client.close(force: true);
    }
  }
}
