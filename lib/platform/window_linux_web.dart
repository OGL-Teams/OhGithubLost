/// L1 硬件层 · **Linux 窗口能力 · Web 占位**。
///
/// ## 为什么需要这个文件
/// `window_linux.dart` 依赖 `package:window_manager`——它的入口库
/// **无条件 `import 'dart:io'`**，且不声明 web 平台。Web 构建里只要它
/// 出现在编译图中，dart2wasm / dart2js 就会因 `dart:io` 不可用而失败。
///
/// ## 契约
/// 与 `linux.dart` 的实现类**同名、同签名**（见 `window_capability.dart`），
/// 全部方法空实现。Web 上没有窗口系统，`platform.dart` 的按平台分发
/// 也永远不会选到这里 —— 存在的意义只是让**编译**通过。
library;

import 'window_capability.dart';

/// Linux 窗口能力（Web 占位实现）。
class OgLLinuxWindow implements OgLWindowCapability {
  /// 创建。
  const OgLLinuxWindow();

  @override
  bool get isDesktop => false;

  @override
  String get platformLabel => 'Linux';

  @override
  Future<void> init({required OgLWindowDecoration decoration}) async {}

  @override
  Future<void> applyDecoration(OgLWindowDecoration decoration) async {}

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> setMaximized(bool value) async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> startDragging() async {}
}
