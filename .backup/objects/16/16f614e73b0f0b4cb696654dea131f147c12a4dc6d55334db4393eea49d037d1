/// 平台实现层 · **门面**（唯一选平台的地方）。
///
/// ## 全项目只有这一处出现 `Platform.isXxx`
/// 其它地方一律通过 [ogLWindow] 拿能力。新增平台时只改本文件一行。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'window_capability.dart';
import 'window_linux.dart';
import 'window_macos.dart';
import 'window_mobile.dart';
import 'window_windows.dart';

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
/// 注意：这里**先判 `kIsWeb`**——浏览器里 `dart:io` 的 `Platform` 不可靠
/// （在某些编译目标下会抛或返回 unknown），必须走 Flutter 的 `kIsWeb`。
OgLTargetPlatform ogLDetectPlatform() {
  if (kIsWeb) {
    return OgLTargetPlatform.web;
  }
  if (Platform.isAndroid) {
    return OgLTargetPlatform.android;
  }
  if (Platform.isWindows) {
    return OgLTargetPlatform.windows;
  }
  if (Platform.isLinux) {
    return OgLTargetPlatform.linux;
  }
  if (Platform.isMacOS) {
    return OgLTargetPlatform.macos;
  }
  if (Platform.isIOS) {
    return OgLTargetPlatform.ios;
  }
  return OgLTargetPlatform.unknown;
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
