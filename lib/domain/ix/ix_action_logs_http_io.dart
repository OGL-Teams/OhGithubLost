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
      // 原则 40（令牌只在必要的跳使用一次）：日志接口是「302 → 签名 URL」
      // 结构，第二跳在**另一台主机**上且不需要任何令牌。dart:io 的自动重定向
      // 会原样重发全部请求头（含 Authorization）——跨主机 302 等于把令牌送出
      // 设备。改为手动跟随：第一跳带令牌、不跟随；拿到 Location 校验后
      // **不带凭证**请求签名地址。
      request.followRedirects = false;
      request.maxRedirects = 0;
      // 不用连接复用（与底座传输保持同一策略）。
      request.persistentConnection = false;
      headers.forEach((String key, String value) {
        request.headers.set(key, value);
      });
      HttpClientResponse response =
          await request.close().timeout(_receiveTimeout);
      var hops = 0;
      while (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          hops < 5) {
        final String? location =
            response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          break;
        }
        final Uri? next = Uri.tryParse(location);
        if (next == null ||
            (next.scheme != 'http' && next.scheme != 'https')) {
          throw IxActionLogsException(
            '日志重定向目标不安全（$location）',
            statusCode: response.statusCode,
          );
        }
        final HttpClientRequest followUp =
            await client.getUrl(next).timeout(_connectTimeout);
        followUp.persistentConnection = false;
        // 重定向后续跳**不携带任何凭证头**（签名地址自带授权）。
        followUp.headers.set('accept', '*/*');
        response = await followUp.close().timeout(_receiveTimeout);
        hops++;
      }
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
