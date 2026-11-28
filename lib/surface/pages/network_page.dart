/// L3 展示级 · **网络设置**（独立页面）。
///
/// 从设置页抽出来：网络相关项（DNS / 下载并发 / Release 加速通道）
/// **不再是一个"可折叠分组"**，而是一整页 —— 层级清楚、不再需要展开。
///
/// 分节内容由设置页以闭包传入（复用同一套逻辑与文案），本页只负责"壳"：
/// `AppBar` + 常驻状态摘要 + 滚动 + 档位化入场动画。
///
/// ## 首屏摘要（批 1 · A 席 P0-2）
/// 网络状态摘要 + 两个关键开关（DNS / 下载并发）在首帧即可见，
/// 不等待 builder 产出；设置未加载时只局部显示骨架，不再整屏白。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../app/og_l_app_bar.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../util/og_l_space.dart';
import '../widgets/settings/settings_group.dart';

/// 取 `settings` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
      'settings',
      key,
      args:
          args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')),
    );

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
      appBar: OgLAppBar(title: Text(_t('network'))),
      body: OgLReveal(
        delay: Duration.zero,
        child: ListenableBuilder(
          listenable: surface.settings,
          builder: (BuildContext context, Widget? _) => ListView(
            padding: OgLSpace.pageHorizontal,
            children: <Widget>[
              // 常驻摘要：首帧即告诉用户"这页管什么、当前状态是什么"。
              Padding(
                padding: const EdgeInsets.only(top: OgLSpace.lg),
                child: Text(
                  _t('network'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: OgLSpace.sm),
              _summaryTile(context),
              const Divider(height: 1),
              if (!surface.settings.isLoaded)
                Padding(
                  padding: const EdgeInsets.only(top: OgLSpace.lg),
                  child: OgLAsyncSkeleton(
                    rows: 3,
                    rowHeight: 56,
                    leadingSize: 28,
                  ),
                )
              else
                builder(context, surface.settings.settings),
              const SizedBox(height: OgLSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// 网络状态摘要：解析方式 + 下载并发（只读，值来自 settings 默认值或已加载值）。
  Widget _summaryTile(BuildContext context) {
    final OgLSettings value = surface.settings.settings;
    final String dns = value.dnsMode == 'custom'
        ? value.dnsCustomIp.isEmpty
            ? _t('dnsCustom')
            : value.dnsCustomIp
        : OgLI18n.instance.t('common', 'systemResolve');
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: kOgLSettingsRowPadding,
      leading: const Icon(Icons.public_outlined),
      title: Text(_t('dnsMode')),
      subtitle: Text(dns, style: theme.textTheme.bodySmall),
      trailing: Text(
        _t('connectionsCount', {'count': value.downloadConnections}),
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
