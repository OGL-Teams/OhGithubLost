/// 平台实现层 · Windows 窗口能力（**纯 Dart**）。
///
/// ## 关键点：不再需要 patch C++
/// 原生窗口标题原先靠 `tool/inject_desktop_shell.py` 改 `Runner.rc` 与
/// `main.cpp`。实际上 `windowManager.setTitle()` 就是 Dart API，且它写的
/// 正是 Windows 窗口管理器读的那个标题（任务栏 / Alt-Tab / 任务管理器）。
/// 因此**原生标题已经由 Dart 保证**，C++ 注入是重复劳动，予以删除。
library;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'window_capability.dart';

/// Windows 窗口能力实现。
class OgLWindowsWindow implements OgLWindowCapability {
  /// 创建实现。
  const OgLWindowsWindow();

  @override
  bool get isDesktop => true;

  @override
  String get platformLabel => 'Windows';

  /// 应用在任务栏 / Alt-Tab / 任务管理器里显示的原生标题。
static const String appTitle = 'OhGithubLost';

@override
Future<void> init({required OgLWindowDecoration decoration}) async {
await windowManager.ensureInitialized();
await applyDecoration(decoration);
}

  @override
  Future<void> applyDecoration(OgLWindowDecoration decoration) async {
    if (decoration == OgLWindowDecoration.custom) {
      // 保留系统阴影 / 圆角 / 贴边（Aero Snap），只是**不画标题栏**——
      // 这正是 Windows 的原生做法（全屏按钮仍可用）。
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

  /// 静默执行（桌面环境千差万别，绝不外抛）。
  static Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('OGL Windows 窗口：操作失败（已忽略）：$error');
    }
  }
}