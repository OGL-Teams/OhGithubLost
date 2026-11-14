/// L3 展示级 · 设置子页（单层进入式的第二层）。
///
/// 根页只放分类入口；进入本页后才展开各个可折叠分组。
/// 本页不持有任何设置状态：分组控件由 `settings_page.dart` 的状态构造后
/// 传入，避免把控制器复制一份导致两边不同步。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/og_l_app_bar.dart';
import '../util/og_l_space.dart';

/// 设置子页。
class SettingsSectionPage extends StatelessWidget {
  /// 创建。
  const SettingsSectionPage({
    required this.title,
    required this.sections,
    super.key,
  });

  /// 标题（简短）。
  final String title;

  /// 本分类下的可折叠分组。
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: OgLAppBar(title: title),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            OgLSpace.lg,
            OgLSpace.md,
            OgLSpace.lg,
            OgLSpace.xl,
          ),
          children: OgLRevealList.of(context, sections),
        ),
      );
}
