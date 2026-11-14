/// L3 展示级 · 关于（项目信息 + 启动诊断）。
///
/// ## 它展示什么
/// - 项目名称、主要开发者、版本、仓库地址（事实来自 [OgLProjectInfo]）；
/// - 启动诊断（启动报告 / 信任告警 / 依赖图 / 启动阶段），来自 [KernelReport]。
///
/// ## 它不展示什么
/// 日志、开源许可与捐赠入口都在设置页；关于页保持"一个身份页"的定位。
/// 不放任何预留位：没有内容的东西不占屏幕。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../kernel/kernel.dart';
import '../app/animations.dart';
import '../app/notifier.dart';
import '../app/og_l_app_bar.dart';
import '../app/permission_selftest.dart';
import '../app/permissions.dart';
import '../app/project_info.dart';
import '../i18n/og_l_i18n.dart';
import '../theme.dart';
import '../util/clipboard_x.dart';
import '../util/og_l_font.dart';
import '../util/og_l_radius.dart';
import '../widgets/flat_list.dart';
import '../util/og_l_space.dart';

/// 取 `about_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'about_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 关于页。
class AboutPage extends StatelessWidget {
  /// 创建页面。
  ///
  /// [report] 可为 `null`（例如未启动内核的预览场景）：此时不展示启动诊断段。
  const AboutPage({this.report, super.key});

  /// 启动报告（内核在启动时定格的快照）。
  final KernelReport? report;

  /// 统一提示入口（与设置页同一纪律）：提示长什么样、什么语气只有一处定义
  /// （见 [OgLNotifier]）。本页是 `StatelessWidget`，因此入口带 `context` 入参，
  /// 而不是 State 上的 getter。
  OgLNotifier _notifier(BuildContext context) =>
      OgLNotifier(ScaffoldMessenger.of(context));

  /// 打开外链（失败时把链接复制到剪贴板并如实提示，不谎报成功）。
  Future<void> _openUrl(BuildContext context, String url) async {
    if (url.isEmpty) {
      return;
    }
    try {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      await ogLCopyText(url, tag: 'link');
      if (context.mounted) {
        _notifier(context).warning(
          _t('copied', {'label': Uri.decodeFull(url)}),
        );
      }
    }
  }

  /// 打开仓库页面（赞助 = 给仓库加星，落在 GitHub 上完成）。
  Future<void> _openSponsor(BuildContext context) async {
    final String url = OgLProjectInfo.repositoryUrl;
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      // 打不开外部浏览器时的兜底：**先真的把链接写进剪贴板**，再提示「已复制」
      // —— 此前只弹提示不复制，属于谎报成功。
      await ogLCopyText(url, tag: '链接');
      if (context.mounted) {
        _notifier(context).warning(
          _t('copied', {'label': Uri.decodeFull(url)}),
        );
      }
    }
  }

  Future<void> _copy(BuildContext context, String text, String label) async {
    await ogLCopyText(text, tag: label);
    if (!context.mounted) {
      return;
    }
    _notifier(context).success(_t('copied', {'label': label}));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KernelReport? snapshot = report;
    return Scaffold(
      appBar: OgLAppBar(title: _t('title')),
      // 根级子项逐个挂入场动画（[OgLRevealList] 自动错峰）；不再用整页
      // `OgLReveal` 包住整个列表 —— 那会与路由过渡叠加成双重动画。
      body: ListView(
        padding: const EdgeInsets.all(OgLSpace.lg),
        children: OgLRevealList.of(context, <Widget>[
          Column(
            children: <Widget>[
              ListTile(
                contentPadding: kOgLFlatRowPadding,
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
                contentPadding: kOgLFlatRowPadding,
                leading: const Icon(Icons.person_outline),
                title: Text(_t('developer')),
                subtitle: Text(OgLProjectInfo.mainDeveloper),
              ),
              ListTile(
                contentPadding: kOgLFlatRowPadding,
                leading: const Icon(Icons.link),
                title: Text(_t('repo')),
                subtitle: Text(OgLProjectInfo.repositoryUrl),
                // 整行可点：仓库地址是"想去看一眼"的东西，只能复制太别扭。
                onTap: () => _openUrl(context, OgLProjectInfo.repositoryUrl),
                trailing: IconButton(
                  icon: const Icon(Icons.content_copy, size: OgLIconSize.md),
                  tooltip: _t('copyRepoUrl'),
                  onPressed: () => _copy(
                    context,
                    OgLProjectInfo.repositoryUrl,
                    _t('repoUrl'),
                  ),
                ),
              ),
              ListTile(
                contentPadding: kOgLFlatRowPadding,
                leading: const Icon(Icons.gavel_outlined),
                title: Text(_t('license')),
                subtitle: Text(
                  '${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}',
                ),
                // 许可全文有链接却没给出口：点开即看官方原文。
                onTap: OgLProjectInfo.licenseUrl.isEmpty
                    ? null
                    : () => _openUrl(context, OgLProjectInfo.licenseUrl),
                trailing: OgLProjectInfo.licenseUrl.isEmpty
                    ? null
                    : const Icon(Icons.open_in_new, size: OgLIconSize.md),
              ),
            ],
          ),
          const Divider(height: 1),
          // 设置页另有「加星」入口，此处为赞助跳转（用户已拍板两个入口都保留）。
          ListTile(
            contentPadding: kOgLFlatRowPadding,
            leading: Icon(Icons.favorite, color: theme.colorScheme.error),
            title: Text(OgLI18n.instance.t('settings', 'donateHeart')),
            subtitle: Text(
              OgLI18n.instance
                  .t('settings', 'donateTileDesc', args: <String, String>{
                'repo': OgLProjectInfo.repoFullName,
              }),
            ),
            trailing: const Icon(Icons.open_in_new, size: OgLIconSize.md),
            onTap: () => _openSponsor(context),
          ),
          const Divider(height: 1),
          // ★ 真实内容（替代此前删掉的占位卡片）：致谢 / 协议说明 / 贡献者。
          //   依赖列表取自 project_info.dart 的 kOgLDependencyLicenses
          //   （设置页「开源许可」同一份事实源），不手写第二份。
          ..._creditsRows(theme),
          ..._licenseCareRows(context),
          ..._contributorsRows(),
          if (snapshot != null) ...<Widget>[
            const SizedBox(height: OgLSpace.lg),
            Text(_t('bootDiagnostics'), style: theme.textTheme.titleMedium),
            const SizedBox(height: OgLSpace.sm),
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
                  value:
                      _t('servicesCount', {'count': snapshot.services.length}),
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
                    contentPadding: kOgLFlatRowPadding,
                    leading: Icon(Icons.verified_outlined),
                    title: Text(_t('trustChainOk')),
                  )
                else
                  for (final Object warning in snapshot.trustWarnings)
                    ListTile(
                      contentPadding: kOgLFlatRowPadding,
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
                  style: const TextStyle(
                      fontFamily: kOglMonoFamily, fontSize: OgLFont.monoSm),
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
                      fontFamily: kOglMonoFamily,
                      fontSize: OgLFont.monoSm,
                    ),
                  ),
              ],
            ),
            _permissionSelfTestTile(theme),
          ],
          const SizedBox(height: OgLSpace.xl),
          Text(
            _t('logsAndLicenseHint'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: OgLSpace.xl),
        ]),
      ),
    );
  }

  // ── 真实内容三块：致谢 / 协议重要性 / 贡献者 ───────────────────────

  /// 致谢：按协议分组**直接平铺**。
  ///
  /// 旧实现把 18 个依赖全塞进一个 ExpansionTile，用户要先找到折叠头、
  /// 展开、再在长列表里滚动——交互与信息密度都差。这里按协议分成三组，
  /// 每组一个标题 + 若干行，与页面其它行同一套间距。
  List<Widget> _creditsRows(ThemeData theme) {
    final Map<String, List<OgLDependencyLicense>> byLicense =
        <String, List<OgLDependencyLicense>>{};
    for (final OgLDependencyLicense dep in kOgLDependencyLicenses) {
      byLicense
          .putIfAbsent(dep.license, () => <OgLDependencyLicense>[])
          .add(dep);
    }
    final List<Widget> rows = <Widget>[
      OgLFlatSectionLabel(
          '${_t('credits')} · ${kOgLDependencyLicenses.length}'),
    ];
    for (final MapEntry<String, List<OgLDependencyLicense>> group
        in byLicense.entries) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(
            OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs),
        child: Text('${_t('licenseSection')} · ${group.key}',
            style: theme.textTheme.labelMedium),
      ));
      for (final OgLDependencyLicense dep in group.value) {
        rows.add(OgLFlatTile(
          title: Text(dep.name),
          subtitle: Text(dep.purpose),
        ));
        rows.add(const Divider(height: 1));
      }
      if (rows.isNotEmpty) {
        rows.removeLast(); // 组尾不留分隔线（下组标题自带间距）
      }
    }
    return rows;
  }

  /// 协议说明：平铺行，与致谢同一套间距。
  List<Widget> _licenseCareRows(BuildContext context) => <Widget>[
        OgLFlatSectionLabel(_t('licenseCare')),
        OgLFlatTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(_t('licenseWhyApache')),
        ),
        const Divider(height: 1),
        OgLFlatTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(_t('licenseWhyOthers')),
        ),
        const Divider(height: 1),
        OgLFlatTile(
          leading: const Icon(Icons.verified_outlined),
          title: Text(_t('licenseWhyNoCopyleft')),
        ),
        const Divider(height: 1),
        OgLFlatTile(
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('Ubuntu Mono · UFL 1.0'),
          subtitle: Text(_t('viewLicenses')),
          trailing: const Icon(Icons.open_in_new, size: OgLIconSize.md),
          onTap: () =>
              unawaited(_openUrl(context, 'https://design.ubuntu.com/font/')),
        ),
        const Divider(height: 1),
      ];

  /// 贡献者：平铺行（据 git 提交记录，如实列出）。
  List<Widget> _contributorsRows() => <Widget>[
        OgLFlatSectionLabel(_t('contributors')),
        OgLFlatTile(
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text(OgLProjectInfo.mainDeveloper),
          subtitle: Text(_t('developer')),
        ),
        const Divider(height: 1),
        OgLFlatTile(
          leading: const Icon(Icons.smart_toy_outlined),
          title: const Text('OGL Bot'),
          subtitle: Text(_t('contributorAutomation')),
        ),
        const Divider(height: 1),
        OgLFlatTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('yingo-server'),
          subtitle: Text(_t('contributorCommit')),
        ),
        const Divider(height: 1),
      ];

  /// 诊断折叠组：**零气泡**——直接用 ExpansionTile，不加 Card / margin。
  /// tilePadding 与页面 ListView 内边距一致，childrenPadding 同样用
  /// OgLSpace.lg，避免同页两种间距。
  Widget _diagnosticTile({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
            horizontal: OgLSpace.lg, vertical: OgLSpace.sm),
        title: Text(title),
        subtitle: Text(subtitle),
        childrenPadding:
            const EdgeInsets.fromLTRB(OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.lg),
        children: children,
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
      subtitle = OgLI18n.instance
          .t('shell', 'permSelfTestAllReady', args: <String, String>{
        'ready': '${last.readyCount}',
        'total': '${last.infos.length}',
        'ms': '${last.duration.inMilliseconds}',
      });
    } else {
      subtitle = OgLI18n.instance
          .t('shell', 'permSelfTestProblems', args: <String, String>{
        'count': '${last.actionable.length}',
      });
    }
    return _diagnosticTile(
      title: OgLI18n.instance.t('shell', 'permSelfTest'),
      subtitle: subtitle,
      children: <Widget>[
        if (last == null)
          ListTile(
            contentPadding: kOgLFlatRowPadding,
            leading: const Icon(Icons.hourglass_empty),
            title: Text(OgLI18n.instance.t('shell', 'permSelfTestPending')),
          )
        else ...<Widget>[
          _KeyValueRow(
              label: OgLI18n.instance.t('shell', 'permPlatform'),
              value: last.platform),
          for (final OgLPermissionInfo info in last.infos)
            ListTile(
              contentPadding: kOgLFlatRowPadding,
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
      padding: const EdgeInsets.symmetric(vertical: OgLSpace.xxs),
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
              style: const TextStyle(
                  fontFamily: kOglMonoFamily, fontSize: OgLFont.monoSm),
            ),
          ),
        ],
      ),
    );
  }
}
