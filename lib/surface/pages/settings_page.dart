/// L3 展示级 · 设置（**根级不折叠，常展开**）。
///
/// ## 为什么折叠
/// 设置项持续增多（外观 / 语言 / 代码与文件 / 网络 / 账户 / 维护 /
/// 许可 / 日志），平铺会让用户在一屏里被几十个控件淹没、找不到目标。
/// 折叠分组让"每一屏只展开一件关心的事"，同时保留全部能力；默认收起，
/// 进入设置页看到的是**分组标题清单**，而不是一长串控件。
///
/// ## 子条目
/// 分组内允许二级结构：先放"开关 / 选择"，再放"依赖它的子项"
/// （例如自定义 DNS 打开后才出现 DNS 服务器与 DoH）。
///
/// ## 关于与捐赠
/// - "关于"是设置页内的**全屏子页面**（不塞进折叠菜单）；
/// - "捐赠一颗心"用**当前登录令牌**给项目仓库加星，含二次确认与已 star 处理。
///
/// ## 只留"真选项"
/// 每个条目都必须**接到真实行为**上（外观→主题/缩放/动效；代码→高亮/字号/
/// 换行/排序；网络→DNS 即时生效；账户→退出；维护→重置/权限引导）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../kernel/kernel.dart';
import '../../kernel/log/og_l_log_file.dart';
import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/permissions.dart';
import '../app/project_info.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../types.dart';
import '../util/accel.dart';
import '../util/clipboard_x.dart';
import '../widgets/code_editor_field.dart';
import 'about_page.dart';
import 'legal_text_page.dart';
import 'network_page.dart';
import 'onboarding_page.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  /// 创建页面。
  ///
  /// [report] 可为 `null`（未启动内核的预览场景）：关于页仍可打开，
  /// 只是不展示启动诊断段。
  const SettingsPage({required this.surface, this.report, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告（透传给关于页）。
  final KernelReport? report;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  OgLSettingsController get _settings => widget.surface.settings;

  /// 日志栏目最多展示的行数（复制仍带走全部）。
  static const int _logTailShown = 80;

  /// 账户行的 Future（**State 持有**，只创建一次）。
  ///
  /// 原实现把 `auth.activeAccount()` 写在 `build` 里：每次重建都会重新发请求，
  /// 账户行因此反复闪「读取中」。账号增删后（见 [_refreshAccount]）重建它即可。
  Future<GhAccount?>? _accountFuture;

  @override
  void initState() {
    super.initState();
    _accountFuture = widget.surface.domain.auth.activeAccount();
    // 账号增删（登录页 / 用户页）会通知：重建 Future，账户行跟上变化。
    widget.surface.domain.auth.addListener(_refreshAccount);
  }

  @override
  void dispose() {
    widget.surface.domain.auth.removeListener(_refreshAccount);
    super.dispose();
  }

  /// 重建账户行 Future（账号状态变化后调用）。
  void _refreshAccount() {
    if (!mounted) {
      return;
    }
    setState(() {
      _accountFuture = widget.surface.domain.auth.activeAccount();
    });
  }

  /// 自定义代码配色的可选色板（ARGB）。
  static const List<int> _kCodePalette = <int>[
    0xFF000000,
    0xFF101418,
    0xFF1E1E1E,
    0xFF2D333B,
    0xFFF6F8FA,
    0xFFFFFFFF,
    0xFFE6EDF3,
    0xFF24292F,
    0xFF79C0FF,
    0xFF0550AE,
    0xFF569CD6,
    0xFF4EC9B0,
    0xFF6A9955,
    0xFFCE9178,
    0xFF953800,
    0xFFFFA657,
    0xFFB5CEA8,
    0xFFCF222E,
    0xFFFF7B72,
    0xFF8250DF,
    0xFFBC8CFF,
    0xFF9BA7B4,
  ];

  /// 动效档位的短标签（与 [OgLSettings.motionLevelIds] 一一对应）。
  ///
  /// 5.2：档位语义改为**质量**（静默 / 保守 / 标准 / 拉满），
  /// 不再复用界面密度的「最小 / 当前 / 标准 / 增强」字样。
  List<String> get _motionShort => <String>[
        _t('motionMin'),
        _t('motionConservative'),
        _t('motionStandard'),
        _t('motionFull'),
      ];

  /// 动效档位的说明（与 [OgLSettings.motionLevelIds] 一一对应）。
  List<String> get _motionHints => <String>[
    _t('motionMinDesc'),
    _t('motionCurrentDesc'),
    _t('motionStandardDesc'),
    _t('motionEnhancedDesc'),
  ];

  Future<void> _pickCodeColor(String field, int current, String title) async {
    final int? picked = await _showOgLDialog<int>(
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(title),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            // 色板宽度：280 保持为**下限**（随字号放大），并受屏宽约束。
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: _dialogWidth(dialogContext, max: 280),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final int argb in _kCodePalette)
                    Semantics(
                      // 色板是「可选项」：屏幕阅读器要能念出颜色名与选中态，
                      // 否则用户只能靠肉眼分辨哪个被选中。
                      button: true,
                      selected: argb == current,
                      label: _t('colorSwatch', <String, Object?>{
                        'color': '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                      }),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => Navigator.of(dialogContext).pop(argb),
                        // 触控命中区 48dp（视觉圆仍 34dp）：34dp 低于 Material
                        // 的最小触控目标，密集点按容易点错。
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Color(argb),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: argb == current
                                      ? Theme.of(dialogContext)
                                          .colorScheme
                                          .primary
                                      : const Color(0x33000000),
                                  width: argb == current ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await _settings.setCodeColor(field, picked);
  }

  Future<void> _pickDnsServer() async {
    final Map<String, String> choices = widget.surface.dnsServerChoices;
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('noDnsServers'))),
      );
      return;
    }
    final String current = _settings.settings.dnsServerId;
    final String? picked = await _showOgLDialog<String>(
      builder: (BuildContext dialogContext) => SimpleDialog(
        title:  Text(_t('selectDns')),
        children: <Widget>[
          for (final MapEntry<String, String> entry in choices.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(entry.key),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(entry.value)),
                  if (entry.key == current)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await widget.surface.setDnsServer(picked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('dnsSaved'))),
      );
    }
  }

  Future<void> _reset() async {
    final bool? confirmed = await _showOgLDialog<bool>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('resetSettings')),
        content:  Text(_t('resetDesc')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('reset')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _settings.reset();
    widget.surface.applyDns();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('resetDone'))),
      );
    }
  }

  /// 设置页文案取用（统一 `settings` 分片）。
  String _t(String key, [Map<String, Object?>? args]) =>
      OgLI18n.instance.t('settings', key,
          args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

  /// `common` 分片文案（加速协议 / 通用按钮等）。
  String _tc(String key, [Map<String, Object?>? args]) =>
      OgLI18n.instance.t('common', key,
          args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

  Future<void> _pickLanguage() async {
    final String current = _settings.settings.languageCode;
    final String? picked = await _showOgLDialog<String>(
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(_t('language')),
        children: <Widget>[
          for (final OgLLocale item in OgLI18n.locales)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(item.code),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(item.label)),
                  if (item.code == current)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == current) {
      return;
    }
    await widget.surface.setLanguage(picked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_t('language')}: ${OgLI18n.instance.localeLabel}'),
        ),
      );
    }
  }

  void _openOnboarding() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OnboardingPage(
          surface: widget.surface,
          review: true,
          onFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// 打开关于页（全屏子页面）。
  void _openAbout() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => AboutPage(report: widget.report),
      ),
    );
  }

  /// 捐赠一颗心：二次确认后，用当前登录令牌给项目仓库加星。
  ///
  /// 已 star 时不重复操作，直接给出提示（幂等，不制造"操作了但没变化"的疑惑）。
  Future<void> _donateStar() async {
    final GhAccount? account = await widget.surface.domain.auth.activeAccount();
    if (!mounted) {
      return;
    }
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('starLoginFirst'))),
      );
      return;
    }
    final bool? confirmed = await _showOgLDialog<bool>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('donateHeart')),
        content: Text(
          _t('donateDesc1', {'login': account.login}) +
          _t('donateDesc2', {'repo': OgLProjectInfo.repoFullName}) +
          _t('donateDesc3'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('thinkAgain')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('donateHeart')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final bool already = await widget.surface.domain.api
          .isRepoStarred(OgLProjectInfo.repoFullName);
      if (already) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(_t('alreadyStarred'))),
          );
        }
        return;
      }
      await widget.surface.domain.api
          .setStarred(OgLProjectInfo.repoFullName, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('starredThanks'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('actionFailed', {'error': error}))),
        );
      }
    }
  }

  /// 复制全部日志到剪贴板。
  Future<void> _copyLogs(List<String> lines) async {
    if (!await ogLCopyText(lines.join('\n'), tag: 'Settings')) {
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('copiedLogLines', {'count': lines.length}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('title'))),
      // 根级子项逐个挂入场动画（[OgLRevealList] 自动错峰）；不再整页包一层
      // `OgLReveal` —— 那会与路由过渡叠加成双重动画。
      body: ListenableBuilder(
        listenable: _settings,
        builder: (BuildContext context, Widget? _) {
          final OgLSettings value = _settings.settings;
          final String? saveError = _settings.lastError;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: OgLRevealList.of(context, <Widget>[
              // 根级顺序**严格固定**（不再随缘排列）：
              // 外观 → 语言 → 代码与文件 → 网络 → Web（仅浏览器）→ 存储位置
              // → 账号 → 维护 → 关于 → 许可 → 日志。
              _appearanceSection(theme, value),
              _languageSection(theme),
              _codeSection(context, theme, value),
              // 网络：**独立子页面**（不折叠）。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.wifi_outlined),
                  title: Text(_t('network')),
                  subtitle:  Text(_t('dnsMode')),
                  titleTextStyle: theme.textTheme.titleMedium,
                  subtitleTextStyle: theme.textTheme.bodySmall,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openNetwork,
                ),
              ),
              // 存储位置：档位 + 选择文件夹（SAF）/ 所有文件访问。
              _storageSection(theme),
              // 保存失败提示：常驻 `AnimatedSize` 承载条件内容（带过渡；
              // 档位 0 时 `OgLAnim` 给零时长 = 立即展开）。
              AnimatedSize(
                duration: OgLAnim.medium(context),
                curve: OgLAnim.curve(context),
                alignment: Alignment.topCenter,
                child: saveError == null
                    ? const SizedBox(width: double.infinity)
                    : Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            saveError,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
              ),
              _accountSection(theme),
              // 捐赠一颗心：README 一直承诺此项，而实现早已写好却**从未接线**
              // （靠 `// ignore: unused_element` 压着 analyze）。这里补上入口。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: Text(_t('donateHeart')),
                  subtitle: Text(_t('donateTileDesc', <String, Object?>{
                    'repo': OgLProjectInfo.repoFullName,
                  })),
                  titleTextStyle: theme.textTheme.titleMedium,
                  subtitleTextStyle: theme.textTheme.bodySmall,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_donateStar()),
                ),
              ),
              _maintenanceSection(theme),
              // 关于：独立于折叠菜单的全屏子页面。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(OgLI18n.instance.t('shell', 'about')),
                  subtitle:  Text(_t('projectInfo')),
                  titleTextStyle: theme.textTheme.titleMedium,
                  subtitleTextStyle: theme.textTheme.bodySmall,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openAbout,
                ),
              ),
              _licenseSection(theme),
              _logsSection(theme),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }

  // ───────────────────────── 各分组 ─────────────────────────

  /// 外观（明暗 / 主题色 / 密度 / 字号 / 动效）。
  Widget _appearanceSection(ThemeData theme, OgLSettings value) => _section(
        theme,
        title: _t('appearance'),
        subtitle: _t('appearanceDesc'),
        children: <Widget>[
          _subTitle(theme, _t('themeMode')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<OgLThemeMode>(
              segments:  <ButtonSegment<OgLThemeMode>>[
                ButtonSegment<OgLThemeMode>(
                  value: OgLThemeMode.system,
                  label: Text(_t('followSystem')),
                ),
                ButtonSegment<OgLThemeMode>(
                  value: OgLThemeMode.light,
                  label: Text(_t('light')),
                ),
                ButtonSegment<OgLThemeMode>(
                  value: OgLThemeMode.dark,
                  label: Text(_t('dark')),
                ),
              ],
              selected: <OgLThemeMode>{value.mode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<OgLThemeMode> selection) {
                if (selection.isNotEmpty) {
                  _settings.setMode(selection.first);
                }
              },
            ),
          ),
          const Divider(height: 24),
          _subTitle(theme, _t('themeColor')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final MapEntry<String, Color> entry
                    in kOgLSeedColors.entries)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: entry.value,
                      radius: 10,
                    ),
                    label: Text(ogLSeedColorLabel(entry.key)),
                    selected: value.seedColorId == entry.key,
                    // 明环境下若沿用 M3 默认的 secondaryContainer，
                    // 勾号（onSecondaryContainer）在浅色芯片上对比度偏低。
                    // 这里改为**确定的 primary / onPrimary 组合**，深浅两态都有足够对比；
                    // 并关掉勾号、保留色点（色点本身就是最强的选中线索）。
                    showCheckmark: false,
                    selectedColor: theme.colorScheme.primary,
                    labelStyle: TextStyle(
                      color: value.seedColorId == entry.key
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (bool on) {
                      if (on) {
                        _settings.setSeedColor(entry.key);
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 24),
          _subTitle(theme, _t('density')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<String>(
              segments:  <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'comfortable',
                  label: Text(_t('comfortable')),
                ),
                ButtonSegment<String>(
                  value: 'compact',
                  label: Text(_t('compact')),
                ),
              ],
              selected: <String>{value.density},
              showSelectedIcon: false,
              onSelectionChanged: (Set<String> selection) {
                if (selection.isNotEmpty) {
                  _settings.setDensity(selection.first);
                }
              },
            ),
          ),
          const Divider(height: 24),
          _OgLSliderRow(
            title: _t('fontScale'),
            value: value.fontScale,
            min: OgLSettings.minFontScale,
            max: OgLSettings.maxFontScale,
            divisions: 16,
            display: (double v) => '${(100 * v).round()}%',
            onCommit: _settings.setFontScale,
          ),
          const Divider(height: 24),
          _motionTile(theme, value.motionLevel),
          SwitchListTile(
            title:  Text(_t('reduceMotionA11y')),
            subtitle:  Text(_t('reduceMotionDesc')),
            value: value.reduceMotion,
            onChanged: _settings.setReduceMotion,
          ),
        ],
      );

  /// 动效档位（四档，横向分段）。
  Widget _motionTile(ThemeData theme, int level) {
    final int index = level.clamp(0, _motionShort.length - 1).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(_t('motionLevel'), style: theme.textTheme.labelLarge),
              ),
              Text(_motionShort[index], style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (int i = 0; i < _motionShort.length; i++)
                ButtonSegment<int>(value: i, label: Text(_motionShort[i])),
            ],
            selected: <int>{index},
            showSelectedIcon: false,
            onSelectionChanged: (Set<int> selection) {
              if (selection.isNotEmpty) {
                _settings.setMotionLevel(selection.first);
              }
            },
          ),
          const SizedBox(height: 4),
          Text(_motionHints[index], style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// 语言。
  Widget _languageSection(ThemeData theme) => _section(
        theme,
        title: _t('language'),
        subtitle: _t('displayLanguage'),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(_t('language')),
            subtitle: Text(OgLI18n.instance.localeLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickLanguage,
          ),
        ],
      );

  /// 代码与文件。
  Widget _codeSection(BuildContext context, ThemeData theme, OgLSettings value) =>
      _section(
        theme,
        title: _t('codeAndFiles'),
        subtitle: _t('codeDesc'),
        children: <Widget>[
          SwitchListTile(
            title: Text(_t('syntaxHighlight')),
            subtitle:  Text(_t('codeColorDesc')),
            value: value.codeHighlight,
            onChanged: _settings.setCodeHighlight,
          ),
          _subTitle(theme, _t('highlightTheme')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final MapEntry<String, String> entry
                    in kOgLCodePresetLabels.entries)
                  ChoiceChip(
                    label: Text(ogLCodePresetLabel(entry.key)),
                    selected: value.codeThemePreset == entry.key,
                    // 同款修正：选中态用 primary 底 + onPrimary 字/勾，确保明环境下的对比度。
                    selectedColor: theme.colorScheme.primary,
                    checkmarkColor: theme.colorScheme.onPrimary,
                    labelStyle: TextStyle(
                      color: value.codeThemePreset == entry.key
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (bool on) {
                      if (on) {
                        _settings.setCodeThemePreset(entry.key);
                      }
                    },
                  ),
              ],
            ),
          ),
          // 自定义配色块：条件内容带**过渡**（不再瞬间插拔）。
          AnimatedSize(
            duration: OgLAnim.medium(context),
            curve: OgLAnim.curve(context),
            alignment: Alignment.topCenter,
            child: value.codeThemePreset == kOgLCodePresetCustom
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Divider(height: 1),
                      _codeColorTile(
                        theme,
                        _t('tokenBackground'),
                        'background',
                        value.codeColorBackground,
                      ),
                      _codeColorTile(
                        theme,
                        _t('tokenForeground'),
                        'foreground',
                        value.codeColorForeground,
                      ),
                      _codeColorTile(theme, _t('tokenKeyword'), 'keyword',
                          value.codeColorKeyword),
                      _codeColorTile(
                        theme,
                        _t('tokenType'),
                        'typeName',
                        value.codeColorTypeName,
                      ),
                      _codeColorTile(theme, _t('tokenString'), 'string',
                          value.codeColorString),
                      _codeColorTile(theme, _t('tokenComment'), 'comment',
                          value.codeColorComment),
                      _codeColorTile(theme, _t('tokenNumber'), 'number',
                          value.codeColorNumber),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          SwitchListTile(
            title: Text(_t('codeWrap')),
            subtitle:  Text(_t('codeWrapDesc')),
            value: value.codeWrap,
            onChanged: _settings.setCodeWrap,
          ),
          _OgLSliderRow(
            title: _t('codeFontSize'),
            value: value.codeFontSize,
            min: OgLSettings.minCodeFontSize,
            max: OgLSettings.maxCodeFontSize,
            divisions: 12,
            display: (double v) => '${v.round()}',
            onCommit: _settings.setCodeFontSize,
          ),
          SwitchListTile(
            title: Text(_t('foldersFirst')),
            subtitle:  Text(_t('foldersFirstDesc')),
            value: value.foldersFirst,
            onChanged: _settings.setFoldersFirst,
          ),
        ],
      );

  /// 网络 / DNS / 下载并发 / 加速通道。
  ///
  /// 这些内容渲染在**独立的网络设置页**里（见 `network_page.dart`），
  /// 不再是一个"可折叠分组"。
  List<Widget> _networkTiles(BuildContext context, ThemeData theme, OgLSettings value) => <Widget>[
          SwitchListTile(
            title: Text(_t('customDns')),
            subtitle:  Text(_t('dnsModeDesc')),
            value: value.dnsMode == 'custom',
            onChanged: (bool on) {
              widget.surface.setDnsMode(on ? 'custom' : 'system');
            },
          ),
          // 自定义 DNS 子项：条件内容带**过渡**（不再瞬间插拔）。
          AnimatedSize(
            duration: OgLAnim.medium(context),
            curve: OgLAnim.curve(context),
            alignment: Alignment.topCenter,
            child: value.dnsMode == 'custom'
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title:  Text(_t('dnsServer')),
                        subtitle: Text(
                          widget.surface.dnsServerChoices[value.dnsServerId] ??
                              value.dnsServerId,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickDnsServer,
                      ),
                      SwitchListTile(
                        title: Text(_t('doh')),
                        subtitle:  Text(_t('dnsServerDesc')),
                        value: value.dnsPreferDoh,
                        onChanged: widget.surface.setDnsPreferDoh,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
const Divider(height: 1),
          ..._downloadTiles(theme, value),
          ..._accelTiles(context, theme, value),
        ];

  /// 打开**网络设置页**（独立页面；不再是可折叠分组）。
  ///
  /// 分节内容仍由本页闭包生成——逻辑与文案只有一份。
  void _openNetwork() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NetworkSettingsPage(
          surface: widget.surface,
          builder: (BuildContext context, OgLSettings value) => Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _networkTiles(context, Theme.of(context), value),
            ),
          ),
        ),
      ),
    );
  }

  /// Web 版（**只在浏览器构建里显示**）。
  ///
  /// ## 为什么只显示在 Web 上
  /// 「打开时询问添加到桌面」在原生平台**没有任何对应行为**。按项目纪律
  /// 「只留真选项」，不显示比显示一个点了不生效的假开关更诚实；
  /// 非 Web 上 [OgLWebStartup.installPromptEnabled] 保持默认值且无人读取，
  /// 因此也不构成"假选项"。
  ///
  /// ## 它接到哪里
  /// 开关读写的 [`OgLWebStartup`]（`surface/app/web_install.dart`）；
  /// 真正弹提示的是 `main.dart` 的启动接线（`_ogLScheduleWebSurface`），
  /// 那里会先看这个开关，再决定要不要询问"添加到桌面"。
  Widget _webSection(ThemeData theme) => _section(
        theme,
        title: _t('webSectionTitle'),
        subtitle: _t('webSectionDesc'),
        children: <Widget>[
          SwitchListTile(
            title: Text(_t('webInstallPrompt')),
            subtitle: Text(_t('webInstallPromptDesc')),
            value: widget.surface.webInstallPromptEnabled,
            onChanged: (bool on) {
              // 立即生效；写盘在后台进行（写失败不影响本次会话）。
              unawaited(widget.surface.setWebInstallPromptEnabled(on));
              setState(() {});
            },
          ),
        ],
      );

  /// 存储位置：三档（公共目录 / 已授权文件夹 / 应用私有目录）。
  ///
  /// 与权限网关同一套裁决（`OgLStorage.plan()`）；这里只负责**如实展示**与
  /// 提供入口：选文件夹（SAF）/ 取消授权 / 打开「所有文件访问」设置。
  Widget _storageSection(ThemeData theme) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(OgLI18n.instance.t('shell', 'storageAccess')),
          subtitle: Text(OgLI18n.instance.t('shell', 'storageGrantDesc1')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showStorage,
        ),
      );

  /// 存储弹窗。
  Future<void> _showStorage() async {
    // 每次都**重新探测**（用户可能刚在系统设置里改过权限）。
    final String mode = await widget.surface.appStorageMode();
    final ({String path, bool visible}) info =
        await widget.surface.appStorageInfo();
    final String? saf = await widget.surface.safTreeUri();
    if (!mounted) {
      return;
    }
    final String modeText = switch (mode) {
      'public' => _t('storageModePublic'),
      'saf' => _t('storageModeSaf'),
      _ => _t('storageModeInternal'),
    };
    await _showOgLDialog<void>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(OgLI18n.instance.t('shell', 'storageAccess')),
        content: SizedBox(
          width: _dialogWidth(dialogContext),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(modeText, style: Theme.of(dialogContext).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text('${OgLI18n.instance.t('shell', 'storageWhere')}：${info.path}'),
                if (!info.visible) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(OgLI18n.instance.t('shell', 'storageHintModern')),
                ],
                if (saf != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    saf,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          if (!info.visible)
            TextButton(
              onPressed: () => unawaited(_requestAllFiles(dialogContext)),
              child:  Text(_t('storageOpenAllFiles')),
            ),
          TextButton(
            onPressed: () => unawaited(_pickSafFolder(dialogContext)),
            child:  Text(_t('storagePickFolder')),
          ),
          if (saf != null)
            TextButton(
              onPressed: () => unawaited(_clearSafFolder(dialogContext)),
              child:  Text(_t('storageClearFolder')),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:  Text(_tc('close')),
          ),
        ],
      ),
    );
  }

  /// 请求「所有文件访问」（Android 11+ 会跳到特殊设置页）。
  Future<void> _requestAllFiles(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    final OgLPermissionGateway gateway = ogLPermissionGateway(
      storageProbe: widget.surface.ensureStorage,
      storageLocation: widget.surface.appStoragePath,
    );
    final OgLPermissionStatus status =
        await gateway.request(OgLPermission.storage);
    if (!mounted) {
      return;
    }
    _toast(status == OgLPermissionStatus.granted
        ? _t('storageAllFilesGranted')
        : OgLI18n.instance.t('shell', 'storageHintModern'));
  }

  /// 选一个文件夹（SAF）并持久化授权。
  Future<void> _pickSafFolder(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    final bool ok = await widget.surface.pickSafDirectory();
    if (!mounted) {
      return;
    }
    _toast(ok ? _t('storageModeSaf') : OgLI18n.instance.t('shell', 'storageHintModern'));
  }

  /// 取消 SAF 授权。
  Future<void> _clearSafFolder(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    await widget.surface.clearSafDirectory();
    if (mounted) {
      _toast(_t('storageClearFolder'));
    }
  }

  /// 轻提示。
  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 统一弹窗入口：所有弹窗都接**动效档位**（时长 / 曲线取自质量表；
  /// 档位 0 为零时长 = 立即打开）。收口后不再各处手写 `showDialog`。
  Future<T?> _showOgLDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) =>
      showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        animationStyle: AnimationStyle(
          duration: OgLAnim.fast(context),
          curve: OgLAnim.curve(context),
        ),
        builder: builder,
      );

  /// 弹窗内容宽度统一收口（原来 460 / 520 两种写法并存）：
  /// 大屏上限 [max]，小屏取 90% 屏宽；色板的 280 是**下限**（随字号放大）。
  double _dialogWidth(BuildContext context, {double max = 520}) {
    final double byScreen = MediaQuery.sizeOf(context).width * 0.9;
    return byScreen < max ? byScreen : max;
  }

  /// ── 下载（并发连接数）──────────────────────────────────────────────
  ///
  /// 只给固定档位（1 / 2 / 4 / 8）：用户不需要理解 TCP，只需要「快一点 / 稳一点」。
  /// 服务端不支持 Range 时中枢层会自动回退单连接，所以调高并发不会把下载搞坏。
  List<Widget> _downloadTiles(ThemeData theme, OgLSettings value) => <Widget>[
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(_t('downloadConnections')),
          subtitle: Text(_t('downloadConnectionsDesc')),
          // 有「选择弹窗」的行带 chevron（与同卡其它可点行一致）。
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _t('connectionsCount', <String, Object?>{
                  'count': value.downloadConnections,
                }),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
          onTap: () => unawaited(_pickDownloadConnections(value)),
        ),
      ];

  Future<void> _pickDownloadConnections(OgLSettings value) async {
    final int? picked = await _showOgLDialog<int>(
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(_t('downloadConnections')),
        children: <Widget>[
          for (final int choice in OgLSettings.downloadConnectionChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(choice),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(_t('connectionsCount', <String, Object?>{
                      'count': choice,
                    })),
                  ),
                  if (choice == value.downloadConnections)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == value.downloadConnections) {
      return;
    }
    await widget.surface.setDownloadConnections(picked);
    if (mounted) {
      _toast(_t('connectionsCount', <String, Object?>{'count': picked}));
    }
  }

  /// ── Release 下载加速（总开关 + 多通道 + 协议同意）────────────────────
  ///
  /// 设计：**只有一个总开关**；下面是通道列表（内置 + 自定义），可多选一。
  /// 开启总开关前若尚未同意当前版本协议，会先弹出协议并要求勾选同意
  /// （同意版本与时间会落盘，作为凭据）。
  List<Widget> _accelTiles(BuildContext context, ThemeData theme, OgLSettings value) {
    final List<Widget> tiles = <Widget>[
      SwitchListTile(
        title:  Text(_t('accelTitle')),
        subtitle:  Text(_t('accelDesc')),
        value: value.releaseProxyEnabled,
        onChanged: (bool on) => unawaited(_toggleAccel(on)),
      ),
    ];
    // 总开关之后的条件内容（约 120 行的插拔）挂**过渡**：开关一拨
    // 不再瞬间撑开 / 收起整块内容。
    tiles.add(
      AnimatedSize(
        duration: OgLAnim.medium(context),
        curve: OgLAnim.curve(context),
        alignment: Alignment.topCenter,
        child: !value.releaseProxyEnabled
            ? const SizedBox(width: double.infinity)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── 适用范围：哪些资源允许走通道 ──────────────────────
                  // 前缀式代理开放的端点有限（有的能转 Release 附件却转不了仓库图片），
                  // 写死"哪些加速"必然有人用不了，所以逐项可关。
                  _subTitle(theme, _t('accelScopes')),
                  ListTile(
                    dense: true,
                    title: Text(
                      _t('accelScopesHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  for (final OgLAccelScope scope in OgLAccelScope.values)
                    SwitchListTile(
                      dense: true,
                      title: Text(_t(scope.labelKey)),
                      value: value.accelScopeEnabled(scope),
                      onChanged: (bool on) =>
                          unawaited(widget.surface.setAccelScope(scope, on)),
                    ),
                  const Divider(height: 24),
                  _subTitle(theme, _t('accelChannels')),
                  // 说明一行：通道由用户自备，本应用不预置任何通道。
                  ListTile(
                    dense: true,
                    title: Text(
                      _tc('accelSelfProvided'),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  // 私有仓库加速 = 把令牌交给第三方代理。这里给一个**永久开关**：
                  // 关掉 = 不再询问**且**不再加速（而不是"别问了但照旧送令牌"）。
                  SwitchListTile(
                    secondary: const Icon(Icons.privacy_tip_outlined),
                    title: Text(_t('accelPrivateRepo')),
                    subtitle: Text(_t('accelPrivateRepoDesc')),
                    value: value.accelPrivateRepoAccepted,
                    onChanged: (bool on) =>
                        unawaited(_setPrivateAccelAccepted(on)),
                  ),
                  if (value.allAccelChannels.isEmpty)
                    // 空态必须说清楚：**本应用不提供通道**，想加速得自己填一个。
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(_tc('accelNoChannelTitle')),
                      subtitle: Text(_tc('accelNoChannelBody')),
                      isThreeLine: true,
                    ),
                  for (final OgLAccelChannel channel in value.allAccelChannels)
                    ListTile(
                      // 单选状态进无障碍语义：屏幕阅读器能念出"已选中"，
                      // 而不是只报一个图标（写法对照色板的 Semantics）。
                      leading: Semantics(
                        selected: channel.id == value.releaseProxySelectedId,
                        label: channel.name,
                        child: Icon(
                          channel.id == value.releaseProxySelectedId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                      ),
                      title: Text(channel.name),
                      subtitle: Text(
                        channel.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: _t('removeChannel'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => unawaited(
                            widget.surface.removeAccelChannel(channel.id)),
                      ),
                      onTap: () => unawaited(
                          widget.surface.setReleaseProxySelected(channel.id)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title:  Text(_t('addCustomChannel')),
                    subtitle: Text(_t('accelAddHint')),
                    onTap: _addAccelChannel,
                  ),
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title:  Text(_t('viewAccelAgreement')),
                    subtitle: Text(
                      value.accelConsentCurrent
                          ? (value.releaseProxyConsentAt == null
                              ? _t('consented', {
                                  'version': '${value.releaseProxyConsentVersion}',
                                })
                              : _t('consentedAt', {
                                  'version': '${value.releaseProxyConsentVersion}',
                                  'at': '${value.releaseProxyConsentAt}',
                                }))
                          : _t('notConsented'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        unawaited(_showAccelAgreement(requireConsent: true)),
                  ),
                ],
              ),
      ),
    );
    return tiles;
  }

  /// 打开总开关：必须先同意当前版本协议。
  Future<void> _toggleAccel(bool on) async {
    if (!on) {
      await widget.surface.setReleaseProxyEnabled(false);
      return;
    }
    final OgLSettings value = widget.surface.settings.settings;
    if (!value.accelConsentCurrent) {
      final bool accepted = await _showAccelAgreement(requireConsent: true);
      if (!accepted) {
        return;
      }
    }
    await widget.surface.setReleaseProxyEnabled(true);
  }

  /// 切换「私有仓库是否允许走加速」。
  ///
  /// ## 两个方向不对称，是刻意的
  /// - **关掉**：直接生效，不再询问。语义是「我不要这个风险」 =
  ///   「不要加速」，所以关掉之后私有仓库回退到 API 直取（不加速）。
  /// - **打开**：必须先过警告弹窗 —— 这是**唯一一次**让人看清
  ///   「令牌会离开设备」的机会，不能一键滑过去。
  Future<void> _setPrivateAccelAccepted(bool on) async {
    if (!on) {
      await widget.surface.setAccelPrivateRepoAccepted(false);
      return;
    }
    final bool ok = await _showPrivateAccelWarning();
    if (ok) {
      await widget.surface.setAccelPrivateRepoAccepted(true);
    }
  }

  /// 私有仓库加速的**知情警告**。
  ///
  /// ## 为什么强制 3 秒
  /// 这不是普通确认框，而是「把令牌交给第三方」这件事的**唯一一道闸门**。
  /// 手滑连点就能通过的话，这道闸门等于没有。前 3 秒按钮禁用，并在按钮上
  /// 显示剩余秒数 —— 让人看得见自己在等什么，而不是干瞪眼。
  ///
  /// ## 文案必须讲清的事实（都是实测结论）
  /// 内置通道会**原样转发** `Authorization` 头给 GitHub（带令牌 200 /
  /// 不带 404），所以这确实是「令牌离开设备」，不是理论风险。
  Future<bool> _showPrivateAccelWarning() async {
    const int holdSeconds = 3;
    int remain = holdSeconds;
    // 本次弹窗是否已启动倒计时（builder 会被 setState 重建，不能每次都起）。
    bool timerStarted = false;
    final bool? ok = await _showOgLDialog<bool>(
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) {
          void tick() {
            Future<void>.delayed(const Duration(seconds: 1), () {
              // setState 在弹窗销毁后会抛，不能让它炸掉。这不是"静默吞错"：
              // 弹窗都没了，再改它的状态没有任何用户可见的意义。
              try {
                if (remain > 0) {
                  setLocal(() => remain -= 1);
                  tick(); // 继续下一秒，直到归零。
                }
              } catch (_) {
                // 弹窗已销毁：停止倒计时。
              }
            });
          }

          // 只在第一次构建时启动（builder 会因 setState 重建，不能每次都起一个）。
          if (remain == holdSeconds && !timerStarted) {
            timerStarted = true;
            tick();
          }
          final bool ready = remain <= 0;
          return PopScope<Object?>(
            canPop: false,
            child: AlertDialog(
              icon: const Icon(Icons.privacy_tip_outlined),
              title: Text(_t('accelPrivateWarnTitle')),
              content: SizedBox(
                width: _dialogWidth(context),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        _t('accelPrivateWarnBody'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      for (final String key in <String>[
                        'accelPrivateWarnPoint1',
                        'accelPrivateWarnPoint2',
                        'accelPrivateWarnPoint3',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('· '),
                              Expanded(child: Text(_t(key))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_t('cancel')),
                ),
                FilledButton(
                  // 没到时间就是禁用 —— 防手滑，也防"不看就点"。
                  onPressed: ready
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: Text(
                    ready
                        ? _t('accelPrivateWarnAccept')
                        : _t('accelPrivateWarnWait', <String, Object?>{
                            'seconds': remain,
                          }),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return ok == true;
  }

  /// 展示协议；[requireConsent] 为真时返回"是否勾选并同意"。
  ///
  /// v6.4.3 起只有**一种**协议（外来服务自负责任）—— 内置通道被删除后，
  /// "本应用自建通道"的声明不复存在。
  Future<bool> _showAccelAgreement({required bool requireConsent}) async {
    bool agreed = false;
    final bool? ok = await _showOgLDialog<bool>(
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: Text(_t('accelThirdPartyTitle')),
          content: SizedBox(
            width: _dialogWidth(context),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 先定性：本文不产生法律效力，唯一生效的是 Apache-2.0。
                  Text(
                    OgLI18n.instance.t('onboarding', 'legalStatementOnly'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  const Divider(height: 24),
                  Text(ogLAccelAgreement()),
                  const Divider(height: 28),
                  // 通道的法律定位：它是**本应用提供的网络服务**，
                  // 不保证可用性、也不保证不收集数据。开启后不再重复提示。
                  Text(
                    _tc('accelServiceTitle'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(_tc('accelServiceBody')),
                  const Divider(height: 28),
                  // 语言效力：以中文文本为准。放在正文最后、勾选之前。
                  Text(
                    _tc('accelLangNote'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    OgLI18n.instance.t('onboarding', 'licenseOfficialCopy'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  // 勾选框紧贴声明文字（阅读顺序：先读文，再勾选）——
                  // 原来塞在 `actions` 里，屏幕阅读器与视觉顺序都是倒的。
                  if (requireConsent) ...<Widget>[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: agreed,
                      onChanged: (bool? v) => setLocal(() => agreed = v ?? false),
                      title:  Text(_t('agreeRead')),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child:  Text(_t('disagree')),
            ),
            FilledButton(
              onPressed: agreed
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child:  Text(_t('agreeContinue')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && agreed) {
      await widget.surface.acceptAccelConsent();
      if (mounted) {
        // v6.4.3：只有一种协议（外来服务自负责任），不再按通道类型区分。
        OgLAppLog.instance.result(_t('title'), _t('agreedAccel'));
      }
      return true;
    }
    return false;
  }

  /// 添加自定义通道（名称 + https 地址）。
  Future<void> _addAccelChannel() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController url = TextEditingController();
    final bool? ok = await _showOgLDialog<bool>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('addCustomChannel')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 先讲清约束再让人填：自定义通道**只支持前缀式代理**
            // （如 GHproxy 项目），且可能缺失部分代理端点。
            Text(
              _tc('accelPrefixOnlyTitle'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              _tc('accelPrefixOnlyBody'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            TextField(
              controller: name,
              decoration:  InputDecoration(
                labelText: _t('channelName'),
                hintText: _t('channelNameHint'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              decoration:  InputDecoration(
                labelText: _t('channelUrl'),
                hintText: 'https://example.com/',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('add')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      name.dispose();
      url.dispose();
      return;
    }
    final String? error = ogLValidateAccelBaseUrl(url.text);
    if (error != null) {
      name.dispose();
      url.dispose();
      _toast(error);
      return;
    }
    final String label = name.text.trim().isEmpty ? _t('customChannel') : name.text.trim();
    final String id = 'custom-${DateTime.now().millisecondsSinceEpoch}';
    await widget.surface
        .upsertAccelChannel(OgLAccelChannel(id: id, name: label, baseUrl: url.text));
    name.dispose();
    url.dispose();
    if (mounted) {
      _toast(_t('channelAdded', {'label': label}));
    }
  }

  /// 账户。
  Widget _accountSection(ThemeData theme) => _section(
        theme,
        title: _t('account'),
        subtitle: _t('currentAccount'),
        children: <Widget>[
          FutureBuilder<GhAccount?>(
            future: _accountFuture,
            builder: (
              BuildContext context,
              AsyncSnapshot<GhAccount?> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return  ListTile(
                  leading: Icon(Icons.key),
                  title: Text(_t('readingAccount')),
                );
              }
              final GhAccount? account = snapshot.data;
              if (account == null) {
                return  ListTile(
                  leading: Icon(Icons.key),
                  title: Text(_t('notLoggedIn')),
                  subtitle: Text(_t('notLoggedInHint')),
                );
              }
              // 危险区（退出登录）已迁到「用户页」，这里只展示身份。
              return ListTile(
                leading: const Icon(Icons.key),
                title: Text('@${account.login}'),
                subtitle: Text(_t('accountId', {'id': account.id})),
              );
            },
          ),
        ],
      );

  /// 维护。
  Widget _maintenanceSection(ThemeData theme) => _section(
        theme,
        title: _t('maintenance'),
        subtitle: _t('guideAndReset'),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(_t('permissionsGuide')),
            subtitle:  Text(_t('recheckPermissions')),
            onTap: _openOnboarding,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(_t('resetSettings')),
            subtitle:  Text(_t('restoreDefaults')),
            onTap: _reset,
          ),
        ],
      );

  /// 开源许可：**合并为一条**，打开时弹窗（本项目 + 第三方依赖）。
  Widget _licenseSection(ThemeData theme) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: Text(_t('licenses')),
              subtitle:  Text(_t('licensesDesc')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showLicenses,
            ),
            const Divider(height: 1),
            // 法律文本：**逐语言对照查看**。引导页那份面向首次阅读（重点 +
            // 折叠全文），这里面向查阅 —— 可以把全部可用语言逐个调出来。
            // 效力以中文为准的声明在该页顶部常驻。
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(_t('legalText')),
              subtitle:  Text(_t('legalLanguages')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        LegalTextPage(surface: widget.surface),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  /// 展示 **Apache-2.0 全文**（从打进资源的 `LICENSE` 读取）。
  ///
  /// 为什么不只显示标识：Apache-2.0 第 4 条要求随分发提供本许可的副本
  /// （并在存在 NOTICE 时一并提供）。只写 `Apache-2.0` 几个字不构成提供副本
  /// —— 许可全文与 NOTICE 现在都随构建产物分发，
  /// 这一层负责把它呈现给用户。
  Future<void> _showFullLicense() async {
    String text = '';
    try {
      text = await rootBundle.loadString('LICENSE');
    } catch (error) {
      debugPrint('OGL 许可：读取 LICENSE 失败：$error');
    }
    if (!mounted) {
      return;
    }
    await _showOgLDialog<void>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}'),
        content: ConstrainedBox(
          // ★ 不写死 `height: 460`：小屏（如 480×800 的设备、被系统放大
          //   字体、或横屏）上 460 会超出 AlertDialog 可用高度，直接溢出。
          //   按视口比例给上限，宽度同样受约束，内容内部自己滚。
          constraints: BoxConstraints(
            maxWidth: _dialogWidth(context),
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: text.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_t('licenseTextMissing')),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_tc('close')),
          ),
        ],
      ),
    );
  }

  /// 许可弹窗：本项目许可 + 第三方依赖清单（**合并为一个入口**）。
  Future<void> _showLicenses() async {
    await _showOgLDialog<void>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('licenses')),
        content: SizedBox(
          width: _dialogWidth(dialogContext),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(_t('licenseSelf', {'name': OgLProjectInfo.name})),
                  subtitle: Text(
                    '${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  // ★ 提供**全文**，而不是只给标识：Apache-2.0 第 4 条要求
                  //   向接收者提供许可副本。此时 `LICENSE` 已打进资源，
                  //   随构建产物一起分发。
                  onTap: () => unawaited(_showFullLicense()),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title:  Text(_t('thirdPartyDeps')),
                  subtitle: Text(
                    _t('depsCount', {'count': kOgLDependencyLicenses.length}),
                  ),
                ),
                for (final OgLDependencyLicense dep in kOgLDependencyLicenses)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(dep.name),
                    subtitle: Text('${dep.license} · ${dep.purpose}'),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:  Text(_tc('close')),
          ),
        ],
      ),
    );
  }

  /// 日志（应用运行日志），默认收起。
  Widget _logsSection(ThemeData theme) => _section(
        theme,
        title: _t('logs'),
        subtitle: _t('logsDesc'),
        children: <Widget>[
          ListenableBuilder(
            listenable: OgLAppLog.instance,
            builder: (BuildContext context, Widget? _) {
              final List<String> allLines = OgLAppLog.instance.entries
                  .map((OgLAppLogEntry entry) => entry.toDisplay())
                  .toList();
              final int shown = allLines.length > _logTailShown
                  ? _logTailShown
                  : allLines.length;
              final List<String> tail = allLines.sublist(allLines.length - shown);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title:  Text(_t('currentLogFile')),
                    subtitle: Text(OgLLogFile.filePath ?? _t('logDisabled')),
                  ),
                  if (!OgLLogFile.isEnabled)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      title:  Text(_t('logDisabledReason')),
                      subtitle: Text(OgLLogFile.lastError ?? _t('unknown')),
                    ),
                  if (tail.isEmpty)
                     ListTile(title: Text(_t('noLogs')))
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SelectableText(
                        tail.join('\n'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: TextButton.icon(
                        onPressed: () => _copyLogs(allLines),
                        icon: const Icon(Icons.content_copy, size: 16),
                        label:  Text(_t('copyAllLogs')),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  // ───────────────────────── 通用零件 ─────────────────────────

  /// 根级分组卡片：标题 + 摘要，**常展开**（层级规范：根级不折叠）。
  Widget _section(
    ThemeData theme, {
    required String title,
    required List<Widget> children,
    String subtitle = '',
  }) =>
      Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              title: Text(title, style: theme.textTheme.titleMedium),
              subtitle: subtitle.isEmpty
                  ? null
                  : Text(subtitle, style: theme.textTheme.bodySmall),
            ),
            ...children,
          ],
        ),
      );

  /// 分组内的二级小标题。
  Widget _subTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: theme.textTheme.labelLarge),
        ),
      );

  /// 自定义配色的一行：名称 + 当前颜色 + 选择入口。
  Widget _codeColorTile(
    ThemeData theme,
    String label,
    String field,
    int argb,
  ) =>
      ListTile(
        dense: true,
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 色块进无障碍语义：屏幕阅读器能念出当前颜色的十六进制值，
            // 而不是只报一个装饰性容器（写法对照色板的 Semantics）。
            Semantics(
              label: _t('colorSwatch', <String, Object?>{
                'color': '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
              }),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(argb),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _pickCodeColor(field, argb, _t('chooseColor', {'label': label})),
      );

}

/// 一条滑块设置行（标题 + 当前值 + 拖动条）。
///
/// ## 为什么要单独抽出来
/// 拖动中的"草稿值"原本放在**整页** State 上：每动一帧整页 `setState` ——
/// 设置页很长，拖动一次要重建几十个卡片。草稿值放进本组件自己的 State 后，
/// 拖动只重建这一行；松手才 `onCommit`（落盘一次，不写盘风暴）。
class _OgLSliderRow extends StatefulWidget {
  /// 创建。
  const _OgLSliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onCommit,
    this.divisions,
  });

  /// 行标题。
  final String title;

  /// 外部真值（未拖动时展示）。
  final double value;

  /// 最小值。
  final double min;

  /// 最大值。
  final double max;

  /// 当前值 → 展示文本（跟随草稿值实时变化）。
  final String Function(double value) display;

  /// 松手后落盘（只调一次）。
  final ValueChanged<double> onCommit;

  /// 分档数（可选）。
  final int? divisions;

  @override
  State<_OgLSliderRow> createState() => _OgLSliderRowState();
}

class _OgLSliderRowState extends State<_OgLSliderRow> {
  /// 拖动中的草稿值（松手清空）。
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double current =
        (_draft ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(widget.title, style: theme.textTheme.labelLarge),
              ),
              Text(widget.display(current), style: theme.textTheme.bodySmall),
            ],
          ),
          Slider(
            value: current,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (double v) => setState(() => _draft = v),
            onChangeEnd: (double v) {
              setState(() => _draft = null);
              widget.onCommit(v);
            },
          ),
        ],
      ),
    );
  }
}