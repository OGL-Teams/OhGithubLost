/// 平台实现层 · macOS 窗口能力（**纯 Dart**）。
///
/// macOS 的隐藏标题栏策略与 Windows 同源（`TitleBarStyle.hidden` +
/// 隐藏窗口按钮），保留系统阴影与全屏手势。
library;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'window_capability.dart';

/// macOS 窗口能力实现。
class OgLMacosWindow implements OgLWindowCapability {
  /// 创建实现。
  const OgLMacosWindow();

  @override
  bool get isDesktop => true;

  @override
  String get platformLabel => 'macOS';

  /// 原生窗口标题（Dock / 窗口菜单读它）。
  static const String appTitle = 'OhGithubLost';

  @override
  Future<void> init({required OgLWindowDecoration decoration}) async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(appTitle);
    await applyDecoration(decoration);
  }

  @override
  Future<void> applyDecoration(OgLWindowDecoration decoration) async {
    if (decoration == OgLWindowDecoration.custom) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    } else {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
    }
    await windowManager.setTitle(appTitle);
  }

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> setMaximized(bool value) =>
      value ? windowManager.maximize() : windowManager.unmaximize();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  /// 静默执行（macOS 沙箱下部分窗口操作可能失败，绝不外抛）。
  static Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('OGL macOS 窗口：操作失败（已忽略）：$error');
    }
  }
}