/// 平台实现层 · **窗口能力**（契约 + 平台选型）。
///
/// ## 这一层存在的理由
/// 过去窗口能力散在 `surface/app/desktop_window.dart`：一个文件里同时有
/// `Platform.isWindows` / `isLinux` / `isMacOS` 的平台分支，又有 Dart 调用。
/// 于是"改一个窗口标题"要去 patch C++（`tool/inject_desktop_shell.py`），
/// 逻辑被迫分散在两处。
///
/// 现在改为：
/// - **能力**写在本文件（契约），上层只认它；
/// - **每个平台一份真实 Dart 实现**（`window_windows.dart` / `window_linux.dart` …）；
/// - **选平台只在这一处**完成，`surface/app/desktop_window.dart` 退化为桥接。
///
/// ## 纪律
/// 平台实现里**不允许**再出现 `Platform.isXxx` 分支——那是本层存在的意义。
/// 需要新的平台能力时：加契约方法 → 各平台实现 → 门面选型，三步走。
library;

/// 窗口装饰模式。
enum OgLWindowDecoration {
  /// 自绘标题栏（默认，外观与 App 一致）。
  custom,

  /// 交还系统默认窗口装饰（用户可在设置里切回）。
  system,
}

/// 窗口能力契约（每个平台一份实现）。
abstract interface class OgLWindowCapability {
  /// 该平台是否为**桌面**（需要自绘标题栏 / 原生窗口控制）。
  bool get isDesktop;

  /// 平台展示名（诊断用）。
  String get platformLabel;

  /// 首次初始化：标题、装饰模式、最小尺寸。
  Future<void> init({required OgLWindowDecoration decoration});

  /// 应用（或回退）窗口装饰。切换即时生效。
  Future<void> applyDecoration(OgLWindowDecoration decoration);

  /// 是否已最大化。
  Future<bool> isMaximized();

  /// 最大化 / 还原。
  Future<void> setMaximized(bool value);

  /// 最小化。
  Future<void> minimize();

  /// 关闭。
  Future<void> close();

  /// 开始拖拽窗口（按住标题栏拖动）。
  Future<void> startDragging();
}
