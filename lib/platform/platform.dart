/// 平台实现层 · **门面**（唯一选平台的地方）。
///
/// ## 关于 `Platform.isXxx` 的实际分布
/// 这里是**窗口能力**的唯一选型处，但项目里还有几处按平台分流的地方
/// （目录规划 `base/disk/app_dirs.dart`、权限网关与通知
/// `surface/app/permissions.dart` / `system_notifier.dart`、设备信息
/// `domain/sys/sys_info.dart`）。那句「全项目只有这一处」与实际不符，已更正；
/// 把这几处也收敛到本层是待办（见 docs/NETWORK.md 的待办一节）。
///
/// ## Web 版（本分支）：这些分流**不用 `dart:io`**
/// 判平台一律走 `kIsWeb` + `defaultTargetPlatform`（本文件是这套约定的出处），
/// 因此 `lib/main.dart`、`lib/platform/`、`lib/surface/` 里**一个
/// `import 'dart:io'` 都没有**：浏览器里那个库不存在，任何一处引入都会让整个
/// Web 构建编译不过。真正需要文件系统 / 平台通道的代码全部下移到 `lib/base/`
/// 的 Web 实现（见 `base/disk/app_dirs_fs_web.dart` 等）；
/// 本分支只构建浏览器产物，原生侧实现已移除。
library;

import 'package:flutter/foundation.dart';

import 'window_capability.dart';
// ★ Web 构建隔离：`window_linux.dart` 依赖 window_manager（拖 dart:io）
//   → 走条件导入，Web 侧命中同名空实现。
import 'window_linux.dart' if (dart.library.js_interop) 'window_linux_web.dart';
// ★ Web 构建隔离：`window_macos.dart` 依赖 window_manager（拖 dart:io）
//   → 走条件导入，Web 侧命中同名空实现。
import 'window_macos.dart' if (dart.library.js_interop) 'window_macos_web.dart';
import 'window_mobile.dart';
// ★ Web 构建隔离：`window_windows.dart` 依赖 window_manager（拖 dart:io）
//   → 走条件导入，Web 侧命中同名空实现。
import 'window_windows.dart'
    if (dart.library.js_interop) 'window_windows_web.dart';

/// 当前平台（用于诊断与展示）。
enum OgLTargetPlatform {
  /// Android。
  android,

  /// Windows 桌面。
  windows,

  /// Linux 桌面。
  linux,

  /// macOS 桌面。
  macos,

  /// iOS。
  ios,

  /// 浏览器。
  web,

  /// 其它 / 无法识别。
  unknown,
}

/// 识别当前平台。
///
/// 注意两点：
/// - 这里**先判 `kIsWeb`**：浏览器里 `dart:io` 的 `Platform` 根本不存在，
///   而 `defaultTargetPlatform` 在 Web 上返回的是**宿主系统**
///   （Android / iOS / macOS…），所以必须先看 `kIsWeb` 才能得到 `web`；
/// - 全程只用 Flutter 的 `kIsWeb` + `defaultTargetPlatform`，
///   **不 import `dart:io`**——否则这个文件在 Web 构建里编译不过。
OgLTargetPlatform ogLDetectPlatform() {
  if (kIsWeb) {
    return OgLTargetPlatform.web;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return OgLTargetPlatform.android;
    case TargetPlatform.windows:
      return OgLTargetPlatform.windows;
    case TargetPlatform.linux:
      return OgLTargetPlatform.linux;
    case TargetPlatform.macOS:
      return OgLTargetPlatform.macos;
    case TargetPlatform.iOS:
      return OgLTargetPlatform.ios;
    case TargetPlatform.fuchsia:
      // 未识别的其它平台：如实返回 unknown，不硬塞一个相近的枚举值。
      return OgLTargetPlatform.unknown;
  }
}

/// 平台展示名。
String ogLPlatformLabel(OgLTargetPlatform platform) => switch (platform) {
      OgLTargetPlatform.android => 'Android',
      OgLTargetPlatform.windows => 'Windows',
      OgLTargetPlatform.linux => 'Linux',
      OgLTargetPlatform.macos => 'macOS',
      OgLTargetPlatform.ios => 'iOS',
      OgLTargetPlatform.web => 'Web',
      OgLTargetPlatform.unknown => '未知平台',
    };

/// 当前平台的窗口能力（**全项目唯一的窗口能力入口**）。
///
/// 选型只发生一次（首次访问时缓存），之后所有调用都经由它。
OgLWindowCapability get ogLWindow {
  final OgLTargetPlatform platform = ogLDetectPlatform();
  switch (platform) {
    case OgLTargetPlatform.windows:
      return const OgLWindowsWindow();
    case OgLTargetPlatform.linux:
      return const OgLLinuxWindow();
    case OgLTargetPlatform.macos:
      return const OgLMacosWindow();
    case OgLTargetPlatform.android:
      return const OgLNoWindow('Android');
    case OgLTargetPlatform.ios:
      return const OgLNoWindow('iOS');
    case OgLTargetPlatform.web:
      return const OgLNoWindow('Web');
    case OgLTargetPlatform.unknown:
      return OgLUnknownWindow();
  }
}

/// 当前平台是否为**桌面**（Windows / Linux / macOS）。
bool get ogLIsDesktopPlatform => ogLWindow.isDesktop;
