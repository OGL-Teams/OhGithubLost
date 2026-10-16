/// L2 中枢级 · Actions 日志的**字节获取**（`dart:io HttpClient`）。
///
/// 只做一件事：带令牌 GET 一段字节（自带超时与"不复用连接"策略）。
/// 解压仍由 `ix_action_logs.dart` 统一负责。
library;

import 'dart:io';

import 'ix_action_logs.dart';

/// 日志字节获取。
abstract final class IxActionLogsHttp {
  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _receiveTimeout = Duration(minutes: 5);

  /// 发起 GET，返回响应字节；非 2xx/3xx 抛 [IxActionLogsException]。
  static Future<List<int>> fetchBytes(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final HttpClient client = _defaultClient();
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(_connectTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      // 不用连接复用（与底座传输保持同一策略）。
      request.persistentConnection = false;
      headers.forEach((String key, String value) {
        request.headers.set(key, value);
      });
      final HttpClientResponse response =
          await request.close().timeout(_receiveTimeout);
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw IxActionLogsException(
          '拉取日志失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in response) {
        bytes.addAll(chunk);
      }
      return bytes;
    } on IxActionLogsException {
      rethrow;
    } on Object catch (error) {
      throw IxActionLogsException('拉取日志异常：$error');
    } finally {
      // 即用即关：不复用、不泄漏。
      client.close(force: true);
    }
  }

  static HttpClient _defaultClient() {
    final HttpClient client = HttpClient();
    // 空闲连接存活时间压短（是否复用由每个请求的 persistentConnection 决定）。
    client.idleTimeout = const Duration(seconds: 3);
    client.connectionTimeout = _connectTimeout;
    client.userAgent = 'OhGithubLost';
    return client;
  }
}
