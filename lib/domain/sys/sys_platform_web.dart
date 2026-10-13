/// L2 中枢级 · 本地信息的**平台原语**（Web）。
///
/// ## 浏览器能拿到什么、拿不到什么（如实区分）
/// | 项 | Web 上 |
/// |----|--------|
/// | 区域设置 | **可拿**：`navigator.language` |
/// | 平台名 | **可拿**：固定 `web` |
/// | 系统版本串 | **拿不到**：浏览器不向页面暴露内核版本 → 返回「未知」 |
/// | CPU 逻辑核数 | **拿不到**（本层不引入 `dart:js_interop` 去读
///   `navigator.hardwareConcurrency`）→ 返回 `null` |
/// | 内存总量 / 可用量 | **拿不到**：出于指纹追踪防护，浏览器不提供 → `null` |
/// | 读本地文件 | **不可用**：页面不能读文件系统 → 抛 `UnsupportedError` |
///
/// 结论：Web 上**只返回能拿到的**，其余一律"未知 / null"，
/// 绝不为了填满界面而编造数值（这是本文件的唯一纪律）。
library;

import 'dart:js_interop';

/// 浏览器 `Navigator.language`（BCP-47 标签，如 `zh-CN`）。
///
/// 直接走 `navigator.language`（运行时单值），比走 `PlatformDispatcher` 更轻；
/// 浏览器场景下用户语言并不像 Flutter 那样按"区域 + 脚本"细化，
/// 单值足够覆盖 `OgLI18n` 的"主语言码 / 简体繁体分流"。
@JS('navigator.language')
external String get _navigatorLanguage;

/// 平台原语（Web）。
class SysPlatform {
  const SysPlatform._();

  /// 平台名：Web 固定为 `web`。
  static String get operatingSystem => 'web';

  /// 系统版本串：浏览器不暴露内核版本 —— **如实返回「未知」**。
  static String get operatingSystemVersion => '未知';

  /// 区域设置：由浏览器 `navigator.language` 给出的语言标签（如 `zh-CN`）。
  static String get localeName => _navigatorLanguage;

  /// CPU 逻辑核数：本层不引入浏览器专属互操作 —— **如实返回 `null`（未知）**。
  static int? get numberOfProcessors => null;

  /// Web 上不可能是 Android（供统一判断设备插件探针是否需要跑）。
  static bool get isAndroid => false;

  /// 读取文本文件：**Web 上不可用**（页面不能访问文件系统）。
  static Future<String> readFile(String path) async {
    throw UnsupportedError('Web 平台不能读取本地文件：$path');
  }

  /// 读取 `/proc/meminfo`：**Web 上不存在** → `null`（内存项如实标记不可用）。
  static Future<String?> readMemInfoText() async => null;
}
