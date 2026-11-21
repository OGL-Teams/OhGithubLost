/// L3 展示级 · 语义图标层（单一事实来源）。
///
/// 统一"复制 / 刷新 / 打开外部 / 删除 / 分享"等动作图标的选择，避免
/// `Icons.link` 顶替"复制"、`Icons.language` 顶替"外部打开"这类
/// 图文语义冲突（见 docs/UX_STABILITY_PLAN.md G-11）。
///
/// 约定：
/// - 页面里出现动作图标时引用本层常量，不直接写 `Icons.*`；
/// - `Icons.link` 只留给**静态 URL 展示**（不是动作），动作"复制链接"
///   一律用 [copy]；
/// - 全部为 `IconData` 常量，可安全用于 `const Icon(OgLIcons.copy)`。
library;

import 'package:flutter/material.dart';

/// 动作图标语义常量。
abstract final class OgLIcons {
  /// 复制到剪贴板（按钮 / 菜单项文案含"复制""拷贝"时）。
  static const IconData copy = Icons.content_copy;

  /// 批量复制（"复制全部"）。
  static const IconData copyAll = Icons.copy_all_outlined;

  /// 刷新 / 重新拉取（单次、局部刷新）。
  static const IconData refresh = Icons.refresh;

  /// 重试全部（批量重来，与单次 [refresh] 区分）。
  static const IconData retryAll = Icons.restart_alt;

  /// 在外部浏览器 / 系统应用打开（文案含"在浏览器打开""外部打开"）。
  static const IconData openExternal = Icons.open_in_new;

  /// 删除（含批量删除）。
  static const IconData delete = Icons.delete_outline;

  /// 分享。
  static const IconData share = Icons.share;
}
