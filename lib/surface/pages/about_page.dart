/// L3 展示级 · 关于（项目信息 + 启动诊断）。
///
/// ## 它展示什么
/// - 项目名称、主要开发者、版本、仓库地址（事实来自 [OgLProjectInfo]）；
/// - 未来扩展位（贡献者名单、致谢等预留，后续追加不必改布局）；
/// - 启动诊断（启动报告 / 信任告警 / 依赖图 / 启动阶段），来自 [KernelReport]。
///
/// ## 它不展示什么
/// 日志与开源许可已归入设置页，便于集中查看；关于页保持"一个身份页"的定位。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../kernel/kernel.dart';
import '../app/animations.dart';
import '../app/permission_selftest.dart';
import '../app/permissions.dart';
import '../app/project_info.dart';
import '../i18n/og_l_i18n.dart';

/// 取 `about_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('about_page', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 关于页。
class AboutPage extends StatelessWidget {
  /// 创建页面。
  ///
  /// [report] 可为 `null`（例如未启动内核的预览场景）：此时不展示启动诊断段。
  const AboutPage({this.report, super.key});

  /// 启动报告（内核在启动时定格的快照）。
  final KernelReport? report;

  /// 打开仓库页面（赞助 = 给仓库加星，落在 GitHub 上完成）。
  Future<void> _openSponsor(BuildContext context) async {
    final Uri uri = Uri.parse(OgLProjectInfo.repositoryUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('copied', {'label': Uri.decodeFull(uri.toString())}))),
        );
      }
    }
  }

  Future<void> _copy(BuildContext context, String text, String label) async {
    if (!await ogLCopyText(text, tag: 'About')) {
      // 已写通知中心 + 日志；UI 不重复弹"已复制"。
      return;
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('copied', {'label': label}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KernelReport? snapshot = report;
    return Scaffold(
      appBar: AppBar(title:  Text(_t('title'))),
      // 根级子项逐个挂入场动画（[OgLRevealList] 自动错峰）；不再用整页
      // `OgLReveal` 包住整个列表 —— 那会与路由过渡叠加成双重动画。
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: OgLRevealList.of(context, <Widget>[
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: Text(
                    '${OgLProjectInfo.name}（${OgLProjectInfo.abbreviation}）',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(_t('version', {
                    'version': snapshot?.appVersion ??
                        OgLI18n.instance.t('common', 'unknown'),
                  })),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title:  Text(_t('developer')),
                  subtitle: Text(OgLProjectInfo.mainDeveloper),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title:  Text(_t('repo')),
                  subtitle: Text(OgLProjectInfo.repositoryUrl),
                  trailing: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    tooltip: _t('copyRepoUrl'),
                    onPressed: () => _copy(
                      context,
                      OgLProjectInfo.repositoryUrl,
                      _t('repoUrl'),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title:  Text(_t('license')),
                  subtitle: Text(
                    '${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 设置页另有「加星」入口，此处为赞助跳转（用户已拍板两个入口都保留）。
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Icon(Icons.favorite, color: theme.colorScheme.error),
              title: Text(OgLI18n.instance.t('shell', 'donateHeart')),
              subtitle: Text(
                OgLI18n.instance.t('shell', 'donateTileDesc', args: <String, String>{
                  'repo': OgLProjectInfo.repoFullName,
                }),
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openSponsor(context),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title:  Text(_t('futureExt')),
                  subtitle:  Text(_t('futureExtDesc')),
                ),
                const Divider(height: 1),
                 ListTile(
                  dense: true,
                  leading: Icon(Icons.people_outline),
                  title: Text(_t('contributors')),
                  subtitle: Text(_t('contributorsDesc')),
                ),
                 ListTile(
                  dense: true,
                  leading: Icon(Icons.favorite_outline),
                  title: Text(_t('thanks')),
                  subtitle: Text(_t('thanksDesc')),
                ),
              ],
            ),
          ),
          if (snapshot != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_t('bootDiagnostics'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _diagnosticTile(
              title: _t('bootReport'),
              subtitle: snapshot.bootSummary,
              children: <Widget>[
                for (final MapEntry<String, String> entry
                    in snapshot.moduleStates.entries)
                  _KeyValueRow(label: entry.key, value: entry.value),
                _KeyValueRow(
                  label: _t('layerBridges'),
                  value: snapshot.bridges.join('、'),
                ),
                _KeyValueRow(
                  label: _t('services'),
                  value: _t('servicesCount', {'count': snapshot.services.length}),
                ),
              ],
            ),
            _diagnosticTile(
              title: _t('trustWarnings'),
              subtitle: snapshot.trustWarnings.isEmpty
                  ? _t('trustOk')
                  : _t('trustCount', {'count': snapshot.trustWarnings.length}),
              children: <Widget>[
                if (snapshot.trustWarnings.isEmpty)
                   ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text(_t('trustChainOk')),
                  )
                else
                  for (final Object warning in snapshot.trustWarnings)
                    ListTile(
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(warning.toString()),
                    ),
              ],
            ),
            _diagnosticTile(
              title: _t('dependencyGraph'),
              subtitle: _t('dependencyGraphDesc'),
              children: <Widget>[
                SelectableText(
                  snapshot.moduleGraph,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            _diagnosticTile(
              title: _t('bootStages'),
              subtitle: _t('stagesCount', {'count': snapshot.stages.length}),
              children: <Widget>[
                for (final Object stage in snapshot.stages)
                  SelectableText(
                    stage.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            _permissionSelfTestTile(theme),
          ],
          const SizedBox(height: 24),
          Text(
            _t('logsAndLicenseHint'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  /// 诊断折叠组（默认收起）。
  Widget _diagnosticTile({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          title: Text(title),
          subtitle: Text(subtitle),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      );

  /// 权限自检折叠组（**每次启动都实测**的结果，见 `OgLPermissionSelfTestReport.last`）。
  ///
  /// 在这里摊开是为了让「为什么日志写不进外部目录 / 为什么没有通知」有据可查：
  /// 用户与排查者看到的是**实测状态 + 事件码**，不是一句“可能没权限”。
  Widget _permissionSelfTestTile(ThemeData theme) {
    final OgLPermissionSelfTestReport? last = OgLPermissionSelfTestReport.last;
    final String subtitle;
    if (last == null) {
      subtitle = OgLI18n.instance.t('shell', 'permSelfTestPending');
    } else if (last.allReady) {
      subtitle = OgLI18n.instance.t('shell', 'permSelfTestAllReady', args: <String, String>{
        'ready': '${last.readyCount}',
        'total': '${last.infos.length}',
        'ms': '${last.duration.inMilliseconds}',
      });
    } else {
      subtitle = OgLI18n.instance.t('shell', 'permSelfTestProblems', args: <String, String>{
        'count': '${last.actionable.length}',
      });
    }
    return _diagnosticTile(
      title: OgLI18n.instance.t('shell', 'permSelfTest'),
      subtitle: subtitle,
      children: <Widget>[
        if (last == null)
          ListTile(
            leading: const Icon(Icons.hourglass_empty),
            title: Text(OgLI18n.instance.t('shell', 'permSelfTestPending')),
          )
        else ...<Widget>[
          _KeyValueRow(label: OgLI18n.instance.t('shell', 'permPlatform'), value: last.platform),
          for (final OgLPermissionInfo info in last.infos)
            ListTile(
              dense: true,
              leading: Icon(
                info.actionable
                    ? Icons.error_outline
                    : (info.ready
                        ? Icons.check_circle_outline
                        : Icons.help_outline),
                color: info.actionable ? theme.colorScheme.error : null,
              ),
              title: Text(info.permission.name),
              subtitle: Text(info.actionable
                  ? '${info.status.name} · '
                      '${OgLPermissionSelfTestReport.codeOf(info.permission)}'
                  : info.status.name),
            ),
        ],
      ],
    );
  }
}

/// 键值一行（左列标签、右列等宽值）。
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}