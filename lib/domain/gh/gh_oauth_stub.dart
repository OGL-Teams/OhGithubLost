/// L2 中枢级 · Web / 未知平台：Device Flow 暂不支持（浏览器端需要独立 CORS 通道）。
library;

import 'gh_oauth_types.dart';

/// 发起设备码请求（Web 版不支持）。
Future<GhOAuthCode> startDeviceFlow(String clientId) async {
  throw UnsupportedError('OAuth 登录暂不支持网页版，请使用令牌登录');
}

/// 轮询换取令牌（Web 版不支持）。
Future<String> pollDeviceFlow(
  String clientId,
  GhOAuthCode code, {
  void Function(GhOAuthStatus status)? onStatus,
}) async {
  throw UnsupportedError('OAuth 登录暂不支持网页版，请使用令牌登录');
}
