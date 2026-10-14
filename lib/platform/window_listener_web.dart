/// L1 硬件层 · Web 侧：`WindowListener` + `windowManager` 的**空实现**。
///
/// 与 `package:window_manager` 的签名**逐个对齐**（`WindowListener` 是
/// **mixin**、`windowManager` 是全局单例），这样调用点在两平台都编译通过。
/// Web 上无窗口系统，标题栏调用点已被 `ogLIsDesktopPlatform` 短路，
/// 这些空实现永远不会真正触发。
library;

/// 窗口事件监听（Web 上永不触发；方法体刻意为空）。
///
/// ★ 必须是 `mixin`（不是 abstract class）：`desktop_window.dart` 里
///   `class _OgLTitleBarState extends State<...> with WindowListener`。
mixin WindowListener {
  void onWindowFocus() {}
  void onWindowBlur() {}
  void onWindowClose() {}
  void onWindowMinimize() {}
  void onWindowRestore() {}
  void onWindowMaximize() {}
  void onWindowUnmaximize() {}
  void onWindowResize() {}
  void onWindowMove() {}
  void onWindowEnterFullScreen() {}
  void onWindowLeaveFullScreen() {}
  void onWindowEnterAlwaysOnTop() {}
  void onWindowLeaveAlwaysOnTop() {}
  void onWindowThemeChanged() {}
  void onWindowMenuOpened() {}
  void onWindowMenuClosed() {}
}

/// 窗口管理器单例的**空占位**（Web 上所有方法都是空操作）。
///
/// 契约对齐 `window_manager` 的全局 `windowManager`：提供
/// `addListener` / `removeListener`（标题栏用到）以及若干常用方法，
/// 全部空实现。原生侧由 `window_listener_native.dart` 导出真实单例。
class _NoopWindowManager {
  void addListener(Object? listener) {}
  void removeListener(Object? listener) {}
  Future<void> ensureInitialized() async {}
  Future<void> setTitle(String title) async {}
  Future<void> setTitleBarStyle(Object style,
      {Object? windowButtonVisibility}) async {}
  Future<bool> isMaximized() async => false;
  Future<void> maximize() async {}
  Future<void> unmaximize() async {}
  Future<void> minimize() async {}
  Future<void> close() async {}
  Future<void> startDragging() async {}
}

/// Web 侧的全局窗口管理器占位。
final _NoopWindowManager windowManager = _NoopWindowManager();
