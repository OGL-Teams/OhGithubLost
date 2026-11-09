/// L2 中枢级 · OAuth Device Flow 的数据类型（与平台实现分文件，避免循环导入）。
library;

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

  /// 用户打开的授权页。
  final String verificationUri;

  /// 轮询间隔（秒，GitHub 返回）。
  final int interval;
}

/// Device Flow 各阶段。
enum GhOAuthStatus {
  /// 已拿到用户码，等待用户授权。
  pending,

  /// 授权成功。
  granted,

  /// 用户码过期。
  expired,

  /// 用户拒绝授权。
  denied,

  /// 网络或服务端错误。
  failed,
}
