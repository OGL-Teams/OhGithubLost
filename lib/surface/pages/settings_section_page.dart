/// L3 · 设置分区页（第二层 · 折叠式）。
///
/// 设置主页面是「分类入口」（第一层 · 进入式）：每个分类一个可点条目，
/// push 到本页；本页里的**可折叠分组**（第二层 · 折叠式）由 [builders] 现建。
///
/// 折叠状态用 [collapseState]（一个 `ValueNotifier`）与主页面共享：切换展开
/// 时这里重建、重新执行 builder，`OgLSettingsGroup` 的 `expanded` 随之更新。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 设置分区页。
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({
    required this.title,
    required this.collapseState,
    required this.builders,
    super.key,
  });

  final String title;

  /// 与主页面共享的折叠状态。
  final ValueNotifier<Set<String>> collapseState;

  /// 每个 builder 返回一个 `OgLSettingsGroup`（现建，读到最新 `expanded`）。
  final List<Widget Function()> builders;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: collapseState,
        builder: (BuildContext context, Set<String> _, Widget? __) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[for (final Widget Function() b in builders) b()],
        ),
      ),
    );
  }
}
