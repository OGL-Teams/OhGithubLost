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
///   不可操作、写回失败、参数校验不通过（error 配色）。
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
  void info(String message) => _show(message);

  /// 成功提示。
  void success(String message) => _show(message);

  /// 失败 / 风险提示（error 配色）。
  void warning(String message) => _show(message, isError: true);

  void _show(String message, {bool isError = false}) {
    if (!_messenger.mounted) {
      // 页面已退出 / 组件已卸载：丢弃提示，不再向已销毁的树写状态。
      return;
    }
    final ColorScheme scheme = Theme.of(_messenger.context).colorScheme;
    _messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: isError ? TextStyle(color: scheme.onError) : null,
        ),
        // 悬浮样式：不压住底部导航栏（也符合 Material 3 的默认推荐）。
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? scheme.error : null,
      ),
    );
  }
}
