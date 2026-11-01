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

import 'gh_oauth_stub.dart' if (dart.library.io) 'gh_oauth_io.dart' as impl;

export 'gh_oauth_types.dart';

/// Device Flow 配置（Client ID 由构建注入；空串 = 功能未启用）。
const String kOgLGitHubClientId = String.fromEnvironment(
  'OGL_GITHUB_CLIENT_ID',
  defaultValue: '',
);

/// GitHub OAuth Device Flow 客户端。
///
/// 实现按平台条件导入：`dart:io` 平台走真实 HTTP；Web 版暂不支持
/// （浏览器端需要另一套 CORS 通道，后续单独实现），调用会抛出明确异常，
/// 而不是让整个 web 目标编译不过。
class GhOAuthDeviceFlow {
  /// 创建流程。`clientId` 为空抛 [ArgumentError]（未注入构建参数）。
  GhOAuthDeviceFlow({required this.clientId}) {
    if (clientId.isEmpty) {
      throw ArgumentError('缺少 OGL_GITHUB_CLIENT_ID（--dart-define 注入）');
    }
  }

  /// OAuth App 的 Client ID。
  final String clientId;

  /// 发起：申请用户码。
  Future<GhOAuthCode> start() => impl.startDeviceFlow(clientId);

  /// 轮询换取 token；返回 `gho_…` 原始令牌（调用方交由 GhAuth 保存）。
  Future<String> poll(
    GhOAuthCode code, {
    void Function(GhOAuthStatus status)? onStatus,
  }) =>
      impl.pollDeviceFlow(clientId, code, onStatus: onStatus);
}
