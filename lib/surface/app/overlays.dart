/// L3 展示级 · **半页以上的动态弹层**（底部面板）的统一定速入口。
///
/// ## 为什么需要它
/// `showModalBottomSheet` 的入场时长由**它自己的动画控制器**决定
/// （Flutter 默认约 250ms），散落在各页调用时无法统一定速；
/// 而底部面板常常占掉半屏以上，属于"大体积动画"，用户对它的**手感**最敏感。
///
/// 这里经 `sheetAnimationStyle` 注入**按动效档位给的时长**（控制器仍归框架
/// 所有 —— 先前自建控制器再在 `pop` 同帧 `dispose`，会把闭场动画掐断：
/// 出场第一帧控制器就被释放，面板直接跳没）：
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
///
/// ## 系统 UI 让位（[useSafeArea] 默认 `true`）
/// `true` 时内容避开**顶部 / 左右两侧**的系统 UI（状态栏、刘海 / 挖孔、
/// Web 与横屏下的侧边遮挡）。默认值从 `false` 改为 `true`：高面板在
/// 横屏 / Web 上会被状态栏与挖孔压住标题等首屏内容。
///
/// **底部不在其列**：Flutter 的弹层（`ModalBottomSheetRoute`）始终延伸到
/// 屏幕底边、连系统 UI 一起覆盖（源码原话："the bottom sheet extends all
/// the way to the bottom of the screen, including any system intrusions"）。
/// 因此**底部收控件**的内容层要自己包一层 `SafeArea(top: false)`
/// 让开手势条 / 浏览器下沿：两个高面板（分支选择 60%、编辑器预览 80%）
/// 已按此处理，其它内容即收即用的矮面板由自带背景兜住。
///
/// ## 拖拽关闭不与「右键返回」冲突（`enableDrag` 沿用默认 `true`）
/// 下拉关闭由框架的 `onVerticalDrag*` 手势驱动；右键返回走的是另一条路径
/// （桌面 / Web 的 `onSecondaryTapUp` 或系统返回键），本仓库的弹层调用点
/// 均未注册 secondary tap，两种手势不共享识别器、不会互相抢占——
/// 因此这里不覆盖 `enableDrag` 的默认值。
library;

import 'package:flutter/material.dart';

import '../i18n/og_l_i18n.dart';
import 'animations.dart';

/// 按档位加速的底部弹层（半页以上的动态面板）。
///
/// [useSafeArea]：默认 `true`，避让顶部 / 左右的系统 UI（见文件头说明）；
/// 底部始终延伸到屏幕边界，内容层需要时自行 `SafeArea(top: false)`。
Future<T?> ogLShowSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = false,
  bool useSafeArea = true,
}) {
  final Duration duration = OgLAnim.sheetDuration(context);
  // 时长交给框架自带的控制器（`sheetAnimationStyle`）：不再自建
  // `AnimationController`，也就不存在「pop 同帧 dispose 掐断闭场动画」。
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      reverseDuration: duration,
    ),
    builder: builder,
  );
}

/// 按全局动效档位显示对话框，避免各页面出现不同的进出节奏。
Future<T?> ogLShowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
  );
}

/// 所有编辑页共用的放弃修改确认；按钮明确说明结果，不使用泛化的“确定”。
Future<bool?> ogLConfirmDiscardChanges(BuildContext context) =>
    ogLShowDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final OgLI18n i18n = OgLI18n.instance;
        return AlertDialog(
          title: Text(i18n.t('code_editor_page', 'discardTitle')),
          content: Text(i18n.t('code_editor_page', 'discardDesc')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(i18n.t('code_editor_page', 'continueEditing')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(i18n.t('code_editor_page', 'discardChanges')),
            ),
          ],
        );
      },
    );
