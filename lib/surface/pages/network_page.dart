/// L3 展示级 · **网络设置**（独立页面）。
///
/// 从设置页抽出来：网络相关项（DNS / 下载并发 / Release 加速通道）
/// **不再是一个"可折叠分组"**，而是一整页 —— 层级清楚、不再需要展开。
///
/// 分节内容由设置页以闭包传入（复用同一套逻辑与文案），本页只负责"壳"：
/// `AppBar` + 滚动 + 档位化入场动画。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../util/og_l_space.dart';

/// 取 `settings` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'settings', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 网络设置页。
class NetworkSettingsPage extends StatelessWidget {
  /// 创建页面。
  const NetworkSettingsPage({
    required this.surface,
    required this.builder,
    super.key,
  });

  /// 表面桥（与设置页同一个）。
  final SurfaceBridge surface;

  /// 由设置页提供的网络分节（保证逻辑 / 文案只有一份）。
  final Widget Function(BuildContext context, OgLSettings value) builder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('network'))),
      body: OgLReveal(
        delay: Duration.zero,
        child: ListenableBuilder(
          listenable: surface.settings,
          builder: (BuildContext context, Widget? _) => ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              builder(context, surface.settings.settings),
              const SizedBox(height: OgLSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
