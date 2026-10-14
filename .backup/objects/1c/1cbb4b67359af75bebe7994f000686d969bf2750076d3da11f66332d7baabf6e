/// 平台实现层 · **移动端 / 无窗口平台**的窗口能力（全空操作）。
///
/// Android / iOS 上没有"自绘标题栏"这回事：窗口由系统全权管理，App 拿不到
/// 也改不了窗口装饰。因此这些方法全是空操作——**显式写出来**而不是让上层
/// 到处 `if (kIsWeb || Platform.isAndroid)`，分支只留在门面选型那一处。
library;

import 'package:flutter/foundation.dart';

import 'window_capability.dart';

/// 无窗口平台（Android / iOS）的空实现。
///
/// `platformLabel` 供引导页展示，让用户知道自己所在的平台。
class OgLNoWindow implements OgLWindowCapability {
  /// 创建实现。
  const OgLNoWindow(this.platformLabel);

  @override
  final String platformLabel;

  @override
  bool get isDesktop => false;

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

/// 兜底实现：平台未知时使用。
///
/// 与 [OgLNoWindow] 的差别是**显式留痕**——平台识别失败是异常情况，
/// 必须让人看得见（而不是静默当成移动端）。
class OgLUnknownWindow extends OgLNoWindow {
  /// 创建兜底实现。
  OgLUnknownWindow()
      : super('未知平台（窗口能力不可用）');

  @override
  Future<void> init({required OgLWindowDecoration decoration}) async {
    debugPrint('OGL 窗口：当前平台不在已支持列表内，窗口能力全部降级为空操作。');
  }
}