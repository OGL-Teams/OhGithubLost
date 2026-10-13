/// L3 展示级 · **半页以上的动态弹层**（底部面板）的统一定速入口。
///
/// ## 为什么需要它
/// `showModalBottomSheet` 的入场时长由**它自己的动画控制器**决定
/// （Flutter 默认约 250ms），散落在各页调用时无法统一定速；
/// 而底部面板常常占掉半屏以上，属于"大体积动画"，用户对它的**手感**最敏感。
///
/// 这里注入一个**按动效档位给时长**的控制器，并把所有权收回来（关闭后释放）：
/// - 档位 `0`（静默）→ 时长 0，面板直接出现（不闪、也不拖）；
/// - 档位 `1 → 3` → 130 / 160 / 200ms（比 Flutter 默认更快）。
///
/// ## 用法
/// ```dart
/// final String? picked = await ogLShowSheet<String>(
///   context: context,
///   isScrollControlled: true,
///   builder: (BuildContext sheetContext) => const _MySheet(),
/// );
/// ```
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'animations.dart';

/// 按档位加速的底部弹层（半页以上的动态面板）。
Future<T?> ogLShowSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) {
  final Duration duration = OgLAnim.sheetDuration(context);
  // vsync 借用 Navigator（本身就是 TickerProvider），避免额外包一层 StatefulWidget。
  final AnimationController controller = AnimationController(
    vsync: Navigator.of(context),
    duration: duration,
    reverseDuration: duration,
  );
  final Future<T?> result = showModalBottomSheet<T>(
    context: context,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    transitionAnimationController: controller,
    builder: builder,
  );
  // 控制器所有权在调用方：面板结束后释放，避免泄漏（也避免测试里留下计时器）。
  unawaited(result.whenComplete(controller.dispose));
  return result;
}
