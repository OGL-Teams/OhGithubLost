/// L1 硬件层 · 原生侧：`window_manager` 的真实 `WindowListener`。
///
/// 仅在**有 window_manager 的平台**（Windows / Linux / macOS）被编译；
/// Web 走 `window_listener_web.dart` 的空实现（见 shim 的说明）。
library;

export 'package:window_manager/window_manager.dart'
    show WindowListener, windowManager;
