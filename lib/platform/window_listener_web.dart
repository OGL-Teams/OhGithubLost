/// L1 硬件层 · Web 侧：`WindowListener` 的**空实现**。
///
/// 签名与 `package:window_manager` 的 `WindowListener` **逐个对齐**，
/// 这样调用点在两个平台都能编译通过。Web 上没有真实窗口系统，
/// 永远不会有人触发这些回调（标题栏的调用点以
/// `ogLIsDesktopPlatform` 短路），空实现即为正确行为。
library;

/// 窗口事件监听（Web 上永不触发；方法体刻意为空）。
abstract class WindowListener {
  /// 窗口获得焦点。
  void onWindowFocus() {}

  /// 窗口失去焦点。
  void onWindowBlur() {}

  /// 窗口被关闭。
  void onWindowClose() {}

  /// 窗口最小化。
  void onWindowMinimize() {}

  /// 窗口还原（从最小化）。
  void onWindowRestore() {}

  /// 窗口最大化。
  void onWindowMaximize() {}

  /// 窗口取消最大化。
  void onWindowUnmaximize() {}

  /// 窗口尺寸/位置变化。
  void onWindowResize() {}

  /// 窗口移动。
  void onWindowMove() {}

  /// 窗口进入全屏。
  void onWindowEnterFullScreen() {}

  /// 窗口离开全屏。
  void onWindowLeaveFullScreen() {}

  /// 窗口进入置顶（macOS）。
  void onWindowEnterAlwaysOnTop() {}

  /// 窗口离开置顶（macOS）。
  void onWindowLeaveAlwaysOnTop() {}

  /// 系统主题/外观变化。
  void onWindowThemeChanged() {}

  /// 系统菜单打开（macOS）。
  void onWindowMenuOpened() {}

  /// 系统菜单关闭（macOS）。
  void onWindowMenuClosed() {}
}
