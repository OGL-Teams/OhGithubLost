/// L3 展示级 · 形状与图标尺度令牌（**全栈唯一圆角 / 图标尺寸常量**）。
///
/// ## 为什么需要它
/// 圆角此前完全散落在页面里（裸值 2 / 6 / 8 / 12 / 24 五种并存），
/// 没有任何体系。视觉上"卡片比弹层还方"这种问题，根源就是没有令牌。
///
/// ## 刻度（与 [OgLSpace] 的 8 点节奏对齐，但**不强制相同**）
/// - `xs`(4)  ：极小元素 —— chip、徽标、进度条；
/// - `sm`(8)  ：小控件 —— 输入框、次级按钮、缩略图；
/// - `md`(12) ：默认 —— 卡片、列表项、对话框内块；
/// - `lg`(16) ：大块 —— 主卡片、底部弹层上沿；
/// - `xl`(24) ：浮层 —— 对话框、大圆角面板；
/// - `pill`   ：胶囊 —— 全圆按钮、标签、头像。
///
/// ## 替换原则
/// 业务代码**不写** `BorderRadius.circular(8)`，一律用 `OgLRadius.cSm`；
/// 需要单边圆角时用 `OgLRadius.verticalTop(lg)` 这类工厂。
library;

import 'package:flutter/widgets.dart';

/// 圆角令牌。
abstract final class OgLRadius {
  /// 极小（chip / 徽标 / 进度条）。
  static const double xs = 4;

  /// 小（输入框 / 次级按钮 / 缩略图）。
  static const double sm = 8;

  /// 默认（卡片 / 列表项）。
  static const double md = 12;

  /// 大（主卡片 / 底部弹层上沿）。
  static const double lg = 16;

  /// 浮层（对话框 / 大圆角面板）。
  static const double xl = 24;

  /// 胶囊（全圆）。
  static const double pill = 999;

  // ── 常用 BorderRadius ────────────────────────────────────────────────
  static const BorderRadius cXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius cSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius cMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius cPill = BorderRadius.all(Radius.circular(pill));

  /// 仅上沿圆角（底部弹层最常用）。
  static const BorderRadius verticalTopLg =
      BorderRadius.vertical(top: Radius.circular(lg));

  /// 仅上沿圆角 · 对话框尺寸。
  static const BorderRadius verticalTopXl =
      BorderRadius.vertical(top: Radius.circular(xl));

  /// 按半径取 [BorderRadius]。
  static BorderRadius circular(double value) =>
      BorderRadius.all(Radius.circular(value));
}

/// 图标尺度令牌。
///
/// 此前尺寸散布在 16 / 18 / 20 / 24 之间（18 为主），没有语义。
/// 这里按**用途**固定为四档，业务代码只按用途选：
/// - [sm] 行内小图标（列表 trailing、状态点）；
/// - [md] 默认（按钮内图标、列表 leading）；
/// - [lg] 强调（导航、页头）；
/// - [xl] 特大（空态、引导页）。
abstract final class OgLIconSize {
  /// 行内小图标。
  static const double sm = 16;

  /// 默认图标（Material 默认 24，我们略微收紧到 18 以提高信息密度）。
  static const double md = 18;

  /// 强调图标（导航 / 页头）。
  static const double lg = 20;

  /// 特大图标（空态 / 引导）。
  static const double xl = 24;

  /// 头像 / 大按钮（40）。
  static const double avatar = 40;

  /// 页头主图标（56）。
  static const double hero = 56;
}
