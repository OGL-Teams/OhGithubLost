/// `dart:io` 平台：GitHub OAuth Device Flow 的真实实现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../kernel/log/og_l_log_file.dart';
import 'gh_client.dart';
import 'gh_oauth_types.dart';

const String _deviceCodeUrl = 'https://github.com/login/device/code';
const String _tokenUrl = 'https://github.com/login/oauth/access_token';

/// 申请用户码。
Future<GhOAuthCode> startDeviceFlow(String clientId) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.postUrl(Uri.parse(_deviceCodeUrl)).timeout(
              const Duration(seconds: 15),
            );
    request.headers.set('Accept', 'application/json');
    request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    request.write(
      'client_id=${Uri.encodeComponent(clientId)}'
      '&scope=${Uri.encodeComponent('repo read:user')}',
    );
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 15));
    final String body = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    final String? userCode = decoded['user_code'] as String?;
    if (userCode == null) {
      throw StateError('GitHub 未返回 user_code：${decoded['error'] ?? body}');
    }
    return GhOAuthCode(
      deviceCode: decoded['device_code'] as String? ?? '',
      userCode: userCode,
      verificationUri: (decoded['verification_uri'] as String?) ??
          'https://github.com/login/device',
      interval: (decoded['interval'] as num?)?.toInt() ?? 5,
    );
  } finally {
    client.close(force: true);
  }
}

/// 轮询换取 token。
Future<String> pollDeviceFlow(
  String clientId,
  GhOAuthCode code, {
  void Function(GhOAuthStatus status)? onStatus,
}) async {
  onStatus?.call(GhOAuthStatus.pending);
  Duration interval = Duration(seconds: code.interval);
  final DateTime deadline = DateTime.now().add(const Duration(minutes: 15));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request =
          await client.postUrl(Uri.parse(_tokenUrl)).timeout(
                const Duration(seconds: 15),
              );
      request.headers.set('Accept', 'application/json');
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.write(
        'client_id=${Uri.encodeComponent(clientId)}'
        '&device_code=${Uri.encodeComponent(code.deviceCode)}'
        '&grant_type=urn:ietf:params:oauth:grant-type:device_code',
      );
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 15));
      final String body = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> decoded =
          jsonDecode(body) as Map<String, dynamic>;
      final String? token = decoded['access_token'] as String?;
      if (token != null && token.isNotEmpty) {
        onStatus?.call(GhOAuthStatus.granted);
        return token;
      }
      final String? error = decoded['error'] as String?;
      if (error == 'authorization_pending') {
        continue;
      }
      if (error == 'slow_down') {
        interval += const Duration(seconds: 5);
        continue;
      }
      if (error == 'expired_token') {
        onStatus?.call(GhOAuthStatus.expired);
        throw const GhAuthException('授权码已过期，请重新发起', statusCode: 400);
      }
      if (error == 'access_denied') {
        onStatus?.call(GhOAuthStatus.denied);
        throw const GhAuthException('授权被拒绝', statusCode: 401);
      }
      throw GhAuthException('授权失败：${error ?? body}', statusCode: 400);
    } on GhAuthException {
      rethrow;
    } on Object catch (error) {
      OgLLogFile.line('OAUTH', '轮询失败：$error', level: 'WARN');
      onStatus?.call(GhOAuthStatus.failed);
      throw GhAuthException('授权失败：$error', statusCode: 500);
    } finally {
      client.close(force: true);
    }
  }
  onStatus?.call(GhOAuthStatus.expired);
  throw const GhAuthException('等待授权超时，请重试', statusCode: 408);
}
