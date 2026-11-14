/// L3 展示级 · 平铺列表容器（设置 / 关于 / 用户页共用）。
///
/// ## 为什么存在
/// 此前三页各自用 `Card` / `ColoredBox` / 不同 `EdgeInsets` 拼分组，
/// 同一页面里出现圆角气泡与不等间距。本组件把布局规则收敛成一条：
/// **全宽行 + 1px 分隔线 + 统一内边距**，没有卡片、没有折叠头、没有
/// 组间额外的圆角容器。分类标题由页面标题栏承担，不在这里重复。
library;

import 'package:flutter/material.dart';

import '../util/og_l_space.dart';
import 'settings/settings_group.dart';

/// 统一行内边距：与设置页 `kOgLSettingsRowPadding` 同源，左右相等。
/// 关于页 / 用户页 / 设置页共用，禁止各页另写 EdgeInsets。
const EdgeInsetsGeometry kOgLFlatRowPadding = kOgLSettingsRowPadding;

/// 分组小标题：单行文字，无容器。
class OgLFlatSectionLabel extends StatelessWidget {
  /// 创建。
  const OgLFlatSectionLabel(this.text, {super.key});

  /// 标题文字。
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            OgLSpace.lg, OgLSpace.lg, OgLSpace.lg, OgLSpace.sm),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      );
}

/// 把若干行拼成「行 → 分隔线 → 行」的平铺列表片段。
///
/// 所有调用方共用它，间距只有一处定义；不会再出现同一页面里 8/12/16
/// 混用或某一组多一圈圆角的情况。
List<Widget> ogLFlatRows(List<Widget> rows) {
  final List<Widget> out = <Widget>[];
  for (int i = 0; i < rows.length; i++) {
    out.add(rows[i]);
    if (i != rows.length - 1) {
      out.add(const Divider(height: 1));
    }
  }
  return out;
}

/// 带说明的平铺行（统一内边距与标题/副标题排版）。
class OgLFlatTile extends StatelessWidget {
  /// 创建。
  const OgLFlatTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// 主标题。
  final Widget title;

  /// 副标题。
  final Widget? subtitle;

  /// 前置图标。
  final Widget? leading;

  /// 行尾控件。
  final Widget? trailing;

  /// 点击。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: kOgLFlatRowPadding,
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
      );
}
