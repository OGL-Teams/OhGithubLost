/// L2 · GitHub OAuth **Device Flow** 登录（无后端方案）。
///
/// ## 为什么用 Device Flow
/// 本应用是纯客户端（无任何服务器）：标准 Authorization Code 流程要求
/// redirect URI 回调，移动端既没有可长期稳定的回调域，也不允许把
/// client secret 打进安装包。Device Flow 恰好为此设计：
/// ① 应用向 GitHub 要一个**一次性用户码**；② 用户在浏览器打开
/// github.com/login/device 输入该码并授权；③ 应用轮询换取 access token。
/// 只需要 **Client ID**（不含 secret，可随包分发），权限只申请 `repo` +
/// `read:user`（最小化）。
///
/// ## 用法
/// ```dart
/// final flow = GhOAuthDeviceFlow(clientId: kOgLClientId);
/// final code = await flow.start();          // 显示 userCode + verificationUri
/// final token = await flow.poll();          // 轮询直至授权完成/过期
/// ```
library;

import 'dart:async';
import 'dart:convert';

import '../../kernel/log/og_l_log_file.dart';
import 'gh_client.dart';

/// Device Flow 配置（Client ID 由构建注入；空串 = 功能未启用）。
const String kOgLGitHubClientId = String.fromEnvironment(
  'OGL_GITHUB_CLIENT_ID',
  defaultValue: '',
);

/// OAuth Device Flow 结果。
class GhOAuthCode {
  /// 创建结果。
  const GhOAuthCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    this.interval = 5,
  });

  /// 轮询用的一次性设备码（**不要**展示给用户）。
  final String deviceCode;

  /// 用户需要输入的码（形如 `XXXX-XXXX`）。
  final String userCode;

  /// 用户打开的授权页（固定 https://github.com/login/device）。
  final String verificationUri;

  /// 轮询间隔（GitHub 返回，秒；默认 5）。
  final int interval;
}

/// Device Flow 各阶段。
enum GhOAuthStatus {
  /// 已拿到用户码，等待用户授权。
  pending,

  /// 授权成功，token 已就绪。
  granted,

  /// 用户码过期（约 15 分钟）。
  expired,

  /// 用户拒绝了授权。
  denied,

  /// 网络或服务端错误。
  failed,
}

/// GitHub OAuth Device Flow 客户端。
class GhOAuthDeviceFlow {
  /// 创建流程。`clientId` 为空抛 [ArgumentError]（未注入构建参数）。
  GhOAuthDeviceFlow({required this.clientId})
      : assert(
          clientId.isNotEmpty,
          '缺少 OGL_GITHUB_CLIENT_ID（--dart-define 注入）',
        );

  /// OAuth App 的 Client ID。
  final String clientId;

  static const String _deviceCodeUrl = 'https://github.com/login/device/code';
  static const String _tokenUrl = 'https://github.com/login/oauth/access_token';

  /// 发起：申请用户码。
  Future<GhOAuthCode> start() async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse(_deviceCodeUrl))
          .timeout(const Duration(seconds: 15));
      request.headers.set('Accept', 'application/json');
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.write(
          'client_id=$clientId&scope=${Uri.encodeComponent('repo read:user')}');
      final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['user_code'] == null) {
        throw StateError('GitHub 未返回 user_code：${decoded['error']}');
      }
      return GhOAuthCode(
        deviceCode: decoded['device_code'] as String? ?? '',
        userCode: decoded['user_code'] as String,
        verificationUri: (decoded['verification_uri'] as String?) ??
            'https://github.com/login/device',
        interval: (decoded['interval'] as num?)?.toInt() ?? 5,
      );
    } finally {
      client.close(forceClose: true);
    }
  }

  /// 轮询换取 token；返回 `gho_…` 原始令牌（调用方交由 GhAuth 保存）。
  ///
  /// [code] 来自 [start]；[onStatus] 用于把状态推进到 UI。
  Future<String> poll(
    GhOAuthCode code, {
    void Function(GhOAuthStatus status)? onStatus,
  }) async {
    onStatus?.call(GhOAuthStatus.pending);
    var interval = Duration(seconds: code.interval);
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse(_tokenUrl))
            .timeout(const Duration(seconds: 15));
        request.headers.set('Accept', 'application/json');
        request.headers
            .set('Content-Type', 'application/x-www-form-urlencoded');
        request.write(
          'client_id=$clientId&device_code=${Uri.encodeComponent(code.deviceCode)}'
          '&grant_type=urn:ietf:params:oauth:grant-type:device_code',
        );
        final response = await request.close().timeout(
              const Duration(seconds: 15),
            );
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final token = decoded['access_token'] as String?;
        if (token != null && token.isNotEmpty) {
          onStatus?.call(GhOAuthStatus.granted);
          return token;
        }
        final error = decoded['error'] as String?;
        if (error == 'authorization_pending') {
          continue; // 用户还没输完码，继续等。
        }
        if (error == 'slow_down') {
          // GitHub 要求放慢：在原间隔上加 5 秒。
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
        throw GhAuthException('授权失败：$error', statusCode: 400);
      } on GhAuthException {
        rethrow;
      } catch (error) {
        OgLLogFile.line('OAUTH', '轮询失败：$error', level: 'WARN');
        onStatus?.call(GhOAuthStatus.failed);
        rethrow;
      } finally {
        client.close(forceClose: true);
      }
    }
    onStatus?.call(GhOAuthStatus.expired);
    throw const GhAuthException('等待授权超时，请重试', statusCode: 408);
  }
}
