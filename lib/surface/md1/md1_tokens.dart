/// L3 展示级 · MD1 经典（2014）基础令牌层。
///
/// ## 纪律
/// 本目录是 MD1 表现层的**唯一视觉事实源**：色板 / 字阶 / 尺寸 / 阴影全部
/// 写死为 MD1 2014 原值，页面与控件只引用这里的常量，不得写裸值。
/// 参照：`docs/MD1_REWRITE_SPEC.md`。
///
/// ## 明暗双主题
/// [OgMd1Colors.of] 按 `context` 的 `ThemeData.brightness` 取同一套角色的
/// 明/暗值；primary / accent 在双主题下保持不变（MD1 原规范）。

/// 对话框最小内边距 / 标题与内容间距 / 动作区间距（MD1 2014 对话框版式）。
const double _md1DialogPadding = OgMd1Size.buttonPadding;
const double _md1DialogGap = OgMd1Type.body;
const double _md1DialogActionGap = OgMd1Type.body;

/// Snackbar 左右/上下内边距、文字与动作间距、最小高度（MD1 底部条）。
const double _md1SnackbarPadding = OgMd1Size.buttonPadding;
const double _md1SnackbarGap = OgMd1Type.body;
const double _md1SnackbarHeight = OgMd1Size.field;

/// Chip 内边距 / 图形直径 / 高度上下界（MD1 18–32dp）。
const double _md1ChipPadding = OgMd1Type.body;
const double _md1ChipVisual = OgMd1Type.subhead;
const double _md1ChipHeightMin = OgMd1Type.overline + OgMd1Type.body;
const double _md1ChipHeightMax = OgMd1Size.buttonHeight - OgMd1Size.radius;

/// Badge 角标直径；文本以 12sp caption 作基线。
const double _md1BadgeSize = OgMd1Type.caption + OgMd1Type.overline;
const double _md1BadgeDot = OgMd1Type.overline;

/// 1px 逻辑像素分割线。
const double _md1DividerPx = 1;
library;

import 'package:flutter/material.dart';

/// MD1 原始色板（明 / 暗双主题的角色值）。
@immutable
class OgMd1Colors {
  /// 创建一组角色色。
  const OgMd1Colors({
    required this.primary,
    required this.primaryDark,
    required this.accent,
    required this.background,
    required this.card,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.onPrimary,
  });

  /// 明亮主题（MD1 2014 原始色板）。
  static const OgMd1Colors light = OgMd1Colors(
    primary: Color(0xFF3F51B5),
    primaryDark: Color(0xFF303F9F),
    accent: Color(0xFFFF4081),
    background: Color(0xFFFAFAFA),
    card: Color(0xFFFFFFFF),
    divider: Color(0xFFE0E0E0),
    textPrimary: Color(0xDE000000),
    textSecondary: Color(0x8A000000),
    onPrimary: Color(0xFFFFFFFF),
  );

  /// 深色主题（primary / accent 不变，表面降为灰阶）。
  static const OgMd1Colors dark = OgMd1Colors(
    primary: Color(0xFF3F51B5),
    primaryDark: Color(0xFF303F9F),
    accent: Color(0xFFFF4081),
    background: Color(0xFF303030),
    card: Color(0xFF424242),
    divider: Color(0xFF555555),
    textPrimary: Color(0xDEFFFFFF),
    textSecondary: Color(0x8AFFFFFF),
    onPrimary: Color(0xFFFFFFFF),
  );

  /// 从 [BuildContext] 当前主题亮度取色板。
  static OgMd1Colors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// AppBar / 主按钮 / FAB / Tab 下划线。
  final Color primary;

  /// 状态栏深一档。
  final Color primaryDark;

  /// FAB / 开关激活 / 进度条。
  final Color accent;

  /// 页面底。
  final Color background;

  /// 卡片 / 列表行底。
  final Color card;

  /// 1px 分割线。
  final Color divider;

  /// 正文（87%）。
  final Color textPrimary;

  /// 副文（54%）。
  final Color textSecondary;

  /// primary 底上的文字。
  final Color onPrimary;
}

/// MD1 字阶（Roboto；字号写死，字重由控件使用处指定）。
abstract final class OgMd1Type {
  /// display 34 / headline 24 / title 20 / subhead 16。
  static const double display = 34;
  static const double headline = 24;
  static const double title = 20;
  static const double subhead = 16;

  /// body 14 / caption 12 / button 14 / overline 10。
  static const double body = 14;
  static const double caption = 12;
  static const double button = 14;
  static const double overline = 10;

  /// 按钮字重 500。
  static const FontWeight buttonWeight = FontWeight.w500;

  /// 标题字重 500。
  static const FontWeight titleWeight = FontWeight.w500;

  /// 正文 / 副文字重 400。
  static const FontWeight bodyWeight = FontWeight.w400;
}

/// MD1 尺寸（dp；触控目标 ≥48dp）。
abstract final class OgMd1Size {
  /// AppBar 高度（桌面 64dp）。
  static const double appBar = 56;
  static const double appBarDesktop = 64;

  /// FAB 直径。
  static const double fab = 56;

  /// flat / raised 按钮高度与左右内边距。
  static const double buttonHeight = 36;
  static const double buttonPadding = 16;

  /// 列表行：单行 56 / 双行 72；leading 40。
  static const double listRowSingle = 56;
  static const double listRowDouble = 72;
  static const double listLeading = 40;

  /// 最小触控目标。
  static const double touchTarget = 48;

  /// 输入框高 / Tab 高。
  static const double field = 48;
  static const double tab = 48;

  /// 对话框最小宽度。
  static const double dialogMinWidth = 280;

  /// 卡片 / 按钮 / 对话框圆角（MD1 经典 2dp，不是方角）。
  static const double radius = 2;
}

/// MD1 elevation（1/2/4/6/8/24dp 的真实投影，原规范数值）。
abstract final class OgMd1Elevation {
  /// 1dp 投影。
  static const List<BoxShadow> dp1 = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 3,
      color: Color(0x3D000000),
    ),
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 2,
      color: Color(0x38000000),
    ),
  ];

  /// 2dp 投影（卡片）。
  static const List<BoxShadow> dp2 = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 2),
      blurRadius: 5,
      color: Color(0x42000000),
    ),
  ];

  /// 4dp 投影（AppBar）。
  static const List<BoxShadow> dp4 = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 4),
      blurRadius: 8,
      color: Color(0x3D000000),
    ),
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 3,
      color: Color(0x38000000),
    ),
  ];

  /// 6dp 投影（FAB）。
  static const List<BoxShadow> dp6 = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 6),
      blurRadius: 12,
      color: Color(0x3D000000),
    ),
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 3,
      color: Color(0x38000000),
    ),
  ];

  /// 8dp 投影。
  static const List<BoxShadow> dp8 = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 8),
      blurRadius: 16,
      color: Color(0x3D000000),
    ),
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 3,
      color: Color(0x38000000),
    ),
  ];

  /// 24dp 投影（对话框）。
  static const List<BoxShadow> dp24 = <BoxShadow>[
    BoxShadow(
      offset: Offset(0, 11),
      blurRadius: 15,
      color: Color(0x33000000),
    ),
    BoxShadow(
      offset: Offset(0, 9),
      blurRadius: 46,
      color: Color(0x1F000000),
    ),
  ];
}
