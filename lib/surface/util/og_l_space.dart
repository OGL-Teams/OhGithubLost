/// L3 展示级 · 间距系统（**全栈唯一间距常量**）。
///
/// ## 8 点节奏 + 整数倍
/// - 8/16/24/32 对应「小 / 中 / 大 / 巨」四档；
/// - 4 仅用于**极紧凑**（如 chip 内 padding）；
/// - 12 是 8 与 16 之间的过渡档（卡片内分组间距）；
/// - 48/64 留给「页面级留白」（标题与正文之间）。
///
/// ## 6 语同款 + 不递增 / 不递减
/// 设计语言中**没有**「字大一点所以间距也大一点」——间距与字体大小解耦，
/// 屏幕缩放（系统字号 1.3×）时**只变字号、不变间距**。这一点与 Figma
/// 「按比例缩放」习惯不同，**不要改动**：
/// 改字号的代价是用户自愿的；改间距的代价是用户被强加的。
///
/// ## 替换原则
/// - 业务代码用 `OgLSpace.gapSm` / `.gapMd` 等**语义名**，**不要**写 `8`/`12`/`16`；
/// - `xxs/gapSm`（4/8）→ chip / list-item 内部；
/// - `gapMd`（12）→ 卡片内分组、字段与字段之间；
/// - `gapLg`（16）→ 卡片之间、section 起始；
/// - `gapXl`（24）/ `gapXxl`（32）→ 页面级；
/// - `gapHuge`（48）/ `gapMega`（64）→ 顶部大留白（页面 hero、首次引导）。
library;

import 'package:flutter/material.dart';
import './og_l_space.dart';

/// 间距系统：8 点节奏 + 整数倍。
abstract final class OgLSpace {
  // 极小 / 小 / 中 / 大 / 巨 / 极大 / 超大 / 巨型
  static const double xxs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
  static const double mega = 64;

  // 常用别名（**短名**版，方便使用）
  static const double gapSm = sm; // 8
  static const double gapMd = md; // 12
  static const double gapLg = lg; // 16
  static const double gapXl = xl; // 24

  /// SizedBox 工厂：垂直间距（最常用）。
  static const SizedBox vXs = SizedBox(height: xxs);
  static const SizedBox vSm = SizedBox(height: sm);
  static const SizedBox vMd = SizedBox(height: md);
  static const SizedBox vLg = SizedBox(height: lg);
  static const SizedBox vXl = SizedBox(height: xl);
  static const SizedBox vXxl = SizedBox(height: xxl);

  /// SizedBox 工厂：水平间距。
  static const SizedBox hXs = SizedBox(width: xxs);
  static const SizedBox hSm = SizedBox(width: sm);
  static const SizedBox hMd = SizedBox(width: md);
  static const SizedBox hLg = SizedBox(width: lg);

  /// EdgeInsets 工厂：常用页面边距。
  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets pageAll = EdgeInsets.all(lg);
  static const EdgeInsets pageTop = EdgeInsets.only(top: lg);
  static const EdgeInsets cardInner = EdgeInsets.all(md);
  static const EdgeInsets sectionVertical = EdgeInsets.symmetric(vertical: md);

  /// 单边带间距（最常用组合）。
  static const EdgeInsets pageHorizontalTop =
      EdgeInsets.fromLTRB(lg, lg, lg, 0);
  static const EdgeInsets pageHorizontalBottom =
      EdgeInsets.fromLTRB(lg, 0, lg, lg);
}
