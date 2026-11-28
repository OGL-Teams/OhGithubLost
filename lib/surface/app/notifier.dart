/// L3 展示级 · 统一用户反馈（SnackBar）。
///
/// ## 为什么要有它
/// 此前每个页面各写一份私有的 `_toast(String message)`（共 7 份实现，
/// 行为一致、各写各的：`mounted` 判断 + 直接 `showSnackBar`）。
/// 统一入口后，「提示长什么样、什么语气」只有一处定义。
///
/// ## 三种语气（页面按语义挑，不再自己拼样式）
/// - [OgLNotifier.success]：操作**已生效**（复制 / 保存 / 提交 / 已加入下载…）；
/// - [OgLNotifier.info]：普通说明（条数、草稿已恢复…）；
/// - [OgLNotifier.warning]：失败与"被拦下"——权限不足、目标不存在 /
///   不可操作、写回失败、参数校验不通过（warning 语义色）。
///
/// 三者在视觉上**三重区分**（不是只改文字色）：`backgroundColor` /
/// `content` 前置图标 / 文字色。下载页那套自建三色 SnackBar 已收编到
/// [OgLNotifier.notice]，颜色映射只留本文件一处。
///
/// ## 时长约定
/// SnackBar 的驻留时长是**等待语义**而非动画（用户需要时间读到提示与操作
/// 按钮），因此不套用 `OgLAnim` 的动画档位；全局唯一常量
/// [kNotifierDuration]（4s，带 action 的下载提示见 [kNotifierActionDuration]）
/// 定义在此，页面侧不再私写裸时长。
///
/// ## 收敛结果（Phase 5 后半已完成）
/// 7 份私有 `_toast` 实现已**全部删除**，各页面在 `_toast` 原位置只留一行入口：
/// ```dart
/// OgLNotifier get _notifier => OgLNotifier(ScaffoldMessenger.of(context));
/// ```
/// 调用点由 `_toast(x)` 改为 `_notifier.<语气>(x)`（页面：`settings_page` ·
/// `repo_page`（两处 State）· `release_detail_page` · `workflow_dispatch_page` ·
/// `action_run_page` · `code_editor_page`）。
///
/// ## 页面侧纪律
/// - 提示一律经本类，不再直接 `showSnackBar`（长什么样只有一处定义）；
/// - **`await` 之后**要提示时，页面仍应先判 `mounted`（与本仓库其它直接取
///   `ScaffoldMessenger.of(context)` 的地方同规矩）；本类内部的
///   `ScaffoldMessengerState.mounted` 判断只是第二道保险。
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/og_l_space.dart';
import 'error_surface.dart';

// motion-allow: 提示驻留时长是等待语义（非动画），全局唯一常量定义处。
const Duration kNotifierDuration = Duration(seconds: 4);

// motion-allow: 带动作按钮的提示驻留时长（用户需要时间点按），非动画。
const Duration kNotifierActionDuration = Duration(seconds: 8);

/// SnackBar 语气：与 [OgLNotifier] 的三种方法一一对应。
///
/// 下载页原有的 `queued/success/warning/info` 四色实现收编后，
/// `queued`/`info` → [OgLNoticeTone.info]，`success` → [OgLNoticeTone.success]，
/// `warning` → [OgLNoticeTone.warning]。
enum OgLNoticeTone { success, info, warning }

/// 统一用户反馈（SnackBar）。
///
/// 替代散落在各页面的 7 份 `_toast` 私有实现。
class OgLNotifier {
  /// 用脚手架信使构造：`OgLNotifier(ScaffoldMessenger.of(context))`。
  OgLNotifier(this._messenger);

  final ScaffoldMessengerState _messenger;

  /// 从 BuildContext 取 messenger 的便捷方法（无 State 时也可用）。
  ///
  /// **不要**在 `await` 之后无 `mounted` 守卫直接调用——必须先判
  /// `context.mounted`（与本仓库其它直接取 ScaffoldMessenger 的地方同规矩）。
  static OgLNotifier of(BuildContext context) =>
      OgLNotifier(ScaffoldMessenger.of(context));

  /// 普通提示。
  void info(String message) => notice(message, tone: OgLNoticeTone.info);

  /// 成功提示。
  void success(String message) => notice(message, tone: OgLNoticeTone.success);

  /// 失败 / 风险提示（warning 语义色）。
  void warning(String message) => notice(message, tone: OgLNoticeTone.warning);

  /// 带语气 / 动作 / 时长的统一出口。
  ///
  /// 下载页等自带配色的调用方一律经此方法，颜色 / 图标 / 时长映射只在本文件
  /// 一处定义。[actionLabel] 与 [onAction] 同时给出时显示动作按钮，时长切到
  /// [kNotifierActionDuration]（需时间让用户点按）；否则 [kNotifierDuration]。
  /// [replace] 为 `true` 时先清掉当前条（下载提示抢占旧提示）。
  void notice(
    String message, {
    OgLNoticeTone tone = OgLNoticeTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    bool replace = false,
  }) {
    if (!_messenger.mounted) {
      // ★ LG-03：页面已退出 / 组件已卸载——不再向已销毁的树写状态，
      //   但**绝不静默**：留痕后重抛给下一帧（操作结果提示丢了 = 用户
      //   以为保存失败或没看见错误原因）。
      OgLAppLog.instance.add(
        'NOTIFY',
        '提示未呈现（messenger 已卸载）：$message',
        severity: OgLNoticeSeverity.warning,
      );
      return;
    }
    if (replace) {
      _messenger.clearSnackBars();
    }
    final ColorScheme scheme = Theme.of(_messenger.context).colorScheme;
    // B-03：三态统一走明暗分档的 OgLSemanticColors；warning 不再错用 error。
    final OgLSemanticColors sem =
        Theme.of(_messenger.context).extension<OgLSemanticColors>() ??
            (scheme.brightness == Brightness.dark
                ? OgLSemanticColors.dark
                : OgLSemanticColors.light);
    final (Color background, Color foreground, IconData icon) = switch (tone) {
      OgLNoticeTone.success => (
          sem.success,
          sem.onSuccess,
          Icons.check_circle_outline
        ),
      OgLNoticeTone.info => (sem.info, sem.onInfo, Icons.info_outline),
      OgLNoticeTone.warning => (
          sem.warning,
          sem.onWarning,
          Icons.warning_amber_rounded
        ),
    };
    final bool hasAction = actionLabel != null && onAction != null;
    _messenger.showSnackBar(
      SnackBar(
        // 三重区分：底色 + 前景色 + 前置图标（不是只改文字色）。
        backgroundColor: background,
        content: Row(
          children: <Widget>[
            Icon(icon, color: foreground, size: OgLSpace.lg),
            SizedBox(width: OgLSpace.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
        // 悬浮样式：不压住底部导航栏（也符合 Material 3 的默认推荐）。
        behavior: SnackBarBehavior.floating,
        // 宽度统一：floating SnackBar 的实际宽度由最近的 Scaffold 决定，
        // 不同页面（发现页 / 设置页）的留隙因此不一致。margin 全局只有
        // 这里一处定义——发现页与设置页同款（左右 16 / 上下 12）。
        margin: const EdgeInsets.symmetric(
            horizontal: OgLSpace.lg, vertical: OgLSpace.md),
        // 时长只从本文件的常量取（等待语义，非动画档位）。
        duration: hasAction ? kNotifierActionDuration : kNotifierDuration,
        action: hasAction
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
    );
  }
}
