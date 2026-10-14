/// 平台实现层 · Linux 窗口能力（**纯 Dart**）。
///
/// ## 与 Windows 的差别
/// Linux 走 GTK，去掉 CSD 由 `setAsFrameless()` 整体接管；回退则用
/// `setTitleBarStyle(normal)`。
///
/// 注：`setAsFrameless()` 在 window_manager 0.5.x **不接受参数**，所以回退
/// 只能靠 `setTitleBarStyle(normal)`（它才是跨平台可控的开关）。
library;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'window_capability.dart';

/// Linux 窗口能力实现。
class OgLLinuxWindow implements OgLWindowCapability {
  /// 创建实现。
  const OgLLinuxWindow();

  @override
  bool get isDesktop => true;

  @override
  String get platformLabel => 'Linux';

  /// 原生窗口标题（GTK 读它显示在任务栏）。
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
      // 整体去掉 GTK 的 CSD，由我们完全自绘。
      await windowManager.setAsFrameless();
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

  /// 静默执行（平铺 WM / 精简会话可能不支持，绝不外抛）。
  static Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('OGL Linux 窗口：操作失败（已忽略）：$error');
    }
  }
}