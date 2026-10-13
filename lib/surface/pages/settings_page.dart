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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kernel/kernel.dart';
import '../../kernel/log/og_l_log_file.dart';
import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
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
import '../widgets/settings/settings_group.dart';
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

  // ── 分组折叠状态（**纯界面状态**，与设置数据分开存）────────────────────
  //
  // 为什么落盘：设置页有 6 个分组，用户每次进来都要重新展开自己关心那一组，
  // 是纯粹的重复劳动。状态存在 SurfaceBridge 的界面偏好 KV 里
  // （key = [_groupsKey]，值 = 展开的分组 id 逗号串），重启后仍在。
  // 为什么**不进** `OgLSettings`：它会被"重置设置"清掉 —— 重置不该顺带
  // 把"我刚点开的分组"关上。

  /// 界面偏好键。
  static const String _groupsKey = 'ogl.settings.groupsOpen';

  /// 已知分组 id（落盘的白名单：读到陌生 id 直接忽略，避免脏数据越滚越大）。
  static const List<String> _groupIds = <String>[
    'interface',
    'code',
    'storage',
    'about',
    'logs',
  ];

  /// 当前展开的分组。
  final Set<String> _openGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _accountFuture = widget.surface.domain.auth.activeAccount();
    // 账号增删（登录页 / 用户页）会通知：重建 Future，账户行跟上变化。
    widget.surface.domain.auth.addListener(_refreshAccount);
    unawaited(_loadGroups());
  }

  /// 读取持久化的展开状态（读不到 = 全部收起）。
  Future<void> _loadGroups() async {
    final String? raw = await widget.surface.readUiPref(_groupsKey);
    if (raw == null || !mounted) {
      return;
    }
    final Set<String> open = <String>{
      for (final String id in raw.split(','))
        if (_groupIds.contains(id)) id,
    };
    setState(() {
      _openGroups
        ..clear()
        ..addAll(open);
    });
  }

  /// 展开状态是否已记录（用于区分"用户收起过"与"默认收起"）。
  bool _isOpen(String id) => _openGroups.contains(id);

  /// 切换分组展开状态并落盘。
  void _toggleGroup(String id, bool open) {
    setState(() {
      if (open) {
        _openGroups.add(id);
      } else {
        _openGroups.remove(id);
      }
    });
    unawaited(widget.surface.writeUiPref(_groupsKey, _openGroups.join(',')));
  }

  /// 折叠摘要：明暗模式（分组标题下一行，收起时也知道当前是什么）。
  String _modeLabel(OgLSettings value) => switch (value.mode) {
        OgLThemeMode.system => _t('followSystem'),
        OgLThemeMode.light => _t('light'),
        OgLThemeMode.dark => _t('dark'),
      };

  /// 折叠摘要：界面分组（明暗 · 主题色 · 文字缩放）。
  String _interfaceSummary(OgLSettings value) =>
      '${_modeLabel(value)} · ${ogLSeedColorLabel(value.seedColorId)} · '
      '${(100 * value.fontScale).round()}%';

  /// 折叠摘要：代码分组（高亮主题 · 代码字号）。
  String _codeSummary(OgLSettings value) =>
      '${ogLCodePresetLabel(value.codeThemePreset)} · '
      '${_t('codeFontSize')} ${value.codeFontSize.round()}';

  /// 折叠摘要：存储与网络（解析方式）。
  String _storageSummary(OgLSettings value) => value.dnsMode == 'custom'
      ? '${_t('customDns')} · ${widget.surface.dnsServerChoices[value.dnsServerId] ?? value.dnsServerId}'
      : _tc('systemResolve');

  /// 折叠摘要：关于与帮助（项目名 · 版本）。
  ///
  /// 版本取自启动报告（预览场景没有报告 → 只留项目名，不会显示空占位）。
  String _aboutSummary() {
    final String version = widget.report?.appVersion ?? '';
    return version.isEmpty
        ? OgLProjectInfo.name
        : '${OgLProjectInfo.name} · $version';
  }

  /// 折叠摘要：日志（是否落盘 · 行数）。
  ///
  /// 收起时也要能回答"日志现在到底在不在写"—— 这正是点开这一组的动机；
  /// 只写一句固定说明（`logsDesc`）等于什么都没说。
  String _logsSummary() {
    if (!OgLLogFile.isEnabled) {
      return _t('logDisabled');
    }
    final int count = OgLAppLog.instance.entries.length;
    final String lines = _t('logsLineCount', <String, Object?>{'count': count});
    return '${_t('logsSaving')} · $lines';
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
                      // 否则用户只能靠肉眼分辨哪个被选中；
                      // `inMutuallyExclusiveGroup` 声明"这一组里只会选中一个"。
                      button: true,
                      selected: argb == current,
                      inMutuallyExclusiveGroup: true,
                      label: _t('colorSwatch', <String, Object?>{
                        'color':
                            '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
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

  Future<void> _reset() async {
    final bool? confirmed = await _showOgLDialog<bool>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('resetSettings')),
        content: Text(_t('resetDesc')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('reset')),
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
      _notifier.success(_t('resetDone'));
    }
  }

  /// 设置页文案取用（统一 `settings` 分片）。
  String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
      'settings', key,
      args: args
          ?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

  /// `common` 分片文案（加速协议 / 通用按钮等）。
  String _tc(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
      'common', key,
      args: args
          ?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

  /// 切换界面语言（选择行回调；i18n 立刻重载，提示带回新语言的自称）。
  Future<void> _setLanguage(String code) async {
    if (code == _settings.settings.languageCode) {
      return;
    }
    await widget.surface.setLanguage(code);
    if (mounted) {
      _notifier.info('${_t('language')}: ${OgLI18n.instance.localeLabel}');
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
      _notifier.warning(_t('starLoginFirst'));
      return;
    }
    final bool? confirmed = await _showOgLDialog<bool>(
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('donateHeart')),
        content: Text(
          _t('donateDesc1', {'login': account.login}) +
              _t('donateDesc2', {'repo': OgLProjectInfo.repoFullName}) +
              _t('donateDesc3'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('thinkAgain')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('donateHeart')),
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
          _notifier.info(_t('alreadyStarred'));
        }
        return;
      }
      await widget.surface.domain.api
          .setStarred(OgLProjectInfo.repoFullName, true);
      if (mounted) {
        _notifier.success(_t('starredThanks'));
      }
    } catch (error) {
      if (mounted) {
        _notifier.warning(_t('actionFailed', {'error': error}));
      }
    }
  }

  /// 复制全部日志到剪贴板。
  Future<void> _copyLogs(List<String> lines) async {
    await ogLCopyText(lines.join('\n'), tag: '日志');
    if (!mounted) {
      return;
    }
    _notifier.success(_t('copiedLogLines', {'count': lines.length}));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('title'))),
      // 根级子项逐个挂入场动画（[OgLRevealList] 自动错峰）；不再整页包一层
      // `OgLReveal` —— 那会与路由过渡叠加成双重动画。
      //
      // 顶部 saveError 真的"置顶"：放在 body 顶的 Column 里、ListView 之前，
      // 而不是塞进 ListView 的第一个 child——后者仍受 ListView padding 16
      // 影响，视觉上与分组列表有 16px 间距，看起来不像"系统级告警"。
      // 真正置顶 = 紧贴 AppBar 下方，与下面所有内容**视觉上断开**（无 16
      // 顶部 padding + 自己的 ErrorContainer 配色 + AnimatedSize 过渡）。
      body: ListenableBuilder(
        listenable: _settings,
        builder: (BuildContext context, Widget? _) {
          final OgLSettings value = _settings.settings;
          final String? saveError = _settings.lastError;
          return Column(
            children: <Widget>[
              // 保存失败提示：常驻 `AnimatedSize` 承载条件内容（带过渡；
              // 档位 0 时 `OgLAnim` 给零时长 = 立即展开）。
              AnimatedSize(
                duration: OgLAnim.medium(context),
                curve: OgLAnim.curve(context),
                alignment: Alignment.topCenter,
                child: saveError == null
                    ? const SizedBox(width: double.infinity)
                    : Card(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
              Expanded(
                child: ListView(
                  // 顶部 padding 收紧：saveError 已经占满了顶部视觉，分组
                  // 列表只留 8px 间距即可。
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: OgLRevealList.of(context, <Widget>[
                    // 根级只有「5 个可折叠分组 + 账户条 + 1 个危险区」：
                    // 账户 → 界面 → 代码与文件 → 存储与网络 → 关于与帮助 →
                    // 日志，危险区在最底。一屏正好 5~7 个可点条目。
                    _accountCard(theme),
                    _interfaceGroup(value),
                    _codeGroup(context, theme, value),
                    _storageGroup(theme, value),
                    _aboutGroup(theme),
                    _logsGroup(theme),
                    // 危险区：与上面所有分组**双重拉开**（留白 + 分隔线 + 告警配色），
                    // 免得"收尾顺手点一下"就把设置全清了。
                    const SizedBox(height: 8),
                    Divider(
                        height: 28, color: theme.colorScheme.outlineVariant),
                    OgLSettingsDangerCard(
                      title: _t('dangerZone'),
                      actionTitle: _t('resetSettings'),
                      actionSubtitle: _t('restoreDefaults'),
                      onTap: _reset,
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────── 各分组 ─────────────────────────

  /// **界面**分组：明暗 / 主题色 / 密度 / 文字缩放 / 动效档位 / 减少动效 / 语言。
  ///
  /// ## 为什么合成一组
  /// 原来「外观」（6 个控件平铺）与「语言」（1 行）是两张独立卡片：
  /// 语言只占一行，却要多占一个卡片标题的位置。它们同属"界面观感"，
  /// 合并后一张卡片管完，根级少一个卡片。
  ///
  /// ## 行型统一
  /// 能"选一个"的走**选择行**（右侧显示当前值，点开弹窗），只有连续量
  /// （文字缩放）留滑杆。原来平铺的色板 / 分段按钮会把一屏的可点条目从
  /// 6 个挤到 2 个，而且每换一个值都要在一整张长卡里找目标。
  Widget _interfaceGroup(OgLSettings value) {
    final int motion =
        value.motionLevel.clamp(0, _motionShort.length - 1).toInt();
    return OgLSettingsGroup(
      title: _t('groupInterface'),
      subtitle: _interfaceSummary(value),
      leading: const Icon(Icons.tune),
      expanded: _isOpen('interface'),
      onToggle: (bool open) => _toggleGroup('interface', open),
      expandLabel: _t('expandGroup'),
      collapseLabel: _t('collapseGroup'),
      children: <Widget>[
        OgLSettingsChoiceTile<OgLThemeMode>(
          title: _t('themeMode'),
          subtitle: _t('appearanceDesc'),
          valueLabel: _modeLabel(value),
          current: value.mode,
          options: <OgLSettingsChoice<OgLThemeMode>>[
            OgLSettingsChoice<OgLThemeMode>(
              value: OgLThemeMode.system,
              label: _t('followSystem'),
            ),
            OgLSettingsChoice<OgLThemeMode>(
              value: OgLThemeMode.light,
              label: _t('light'),
            ),
            OgLSettingsChoice<OgLThemeMode>(
              value: OgLThemeMode.dark,
              label: _t('dark'),
            ),
          ],
          onSelected: (OgLThemeMode mode) => unawaited(_settings.setMode(mode)),
        ),
        const Divider(height: 1),
        OgLSettingsChoiceTile<String>(
          title: _t('themeColor'),
          // 色点本身就是最强的选中线索（沿用原色板的取舍：不用勾号）。
          leading: CircleAvatar(
            backgroundColor: ogLSeedColorOf(value.seedColorId),
            radius: 10,
          ),
          valueLabel: ogLSeedColorLabel(value.seedColorId),
          current: value.seedColorId,
          options: <OgLSettingsChoice<String>>[
            for (final MapEntry<String, Color> entry in kOgLSeedColors.entries)
              OgLSettingsChoice<String>(
                value: entry.key,
                label: ogLSeedColorLabel(entry.key),
                leading: CircleAvatar(backgroundColor: entry.value, radius: 10),
              ),
          ],
          onSelected: (String id) => unawaited(_settings.setSeedColor(id)),
        ),
        const Divider(height: 1),
        OgLSettingsChoiceTile<String>(
          title: _t('density'),
          valueLabel:
              value.density == 'compact' ? _t('compact') : _t('comfortable'),
          current: value.density,
          options: <OgLSettingsChoice<String>>[
            OgLSettingsChoice<String>(
              value: 'comfortable',
              label: _t('comfortable'),
            ),
            OgLSettingsChoice<String>(value: 'compact', label: _t('compact')),
          ],
          onSelected: (String id) => unawaited(_settings.setDensity(id)),
        ),
        const Divider(height: 1),
        OgLSettingsSliderRow(
          title: _t('fontScale'),
          value: value.fontScale,
          min: OgLSettings.minFontScale,
          max: OgLSettings.maxFontScale,
          divisions: 16,
          display: (double v) => '${(100 * v).round()}%',
          onCommit: _settings.setFontScale,
        ),
        const Divider(height: 1),
        OgLSettingsChoiceTile<int>(
          title: _t('motionLevel'),
          valueLabel: _motionShort[motion],
          current: motion,
          // 档位语义（"静默 / 保守 / 标准 / 拉满"各是什么）收进选项说明：
          // 平铺时这四行说明是页面变长最大的来源之一。
          options: <OgLSettingsChoice<int>>[
            for (int i = 0; i < _motionShort.length; i++)
              OgLSettingsChoice<int>(
                value: i,
                label: _motionShort[i],
                hint: _motionHints[i],
              ),
          ],
          onSelected: (int level) => unawaited(_settings.setMotionLevel(level)),
        ),
        const Divider(height: 1),
        OgLSettingsSwitchRow(
          title: _t('reduceMotionA11y'),
          subtitle: _t('reduceMotionDesc'),
          value: value.reduceMotion,
          onChanged: (bool on) => unawaited(_settings.setReduceMotion(on)),
        ),
        const Divider(height: 1),
        OgLSettingsChoiceTile<String>(
          title: _t('language'),
          leading: const Icon(Icons.translate),
          subtitle: _t('displayLanguage'),
          valueLabel: OgLI18n.instance.localeLabel,
          current: _settings.settings.languageCode,
          options: <OgLSettingsChoice<String>>[
            for (final OgLLocale item in OgLI18n.locales)
              OgLSettingsChoice<String>(value: item.code, label: item.label),
          ],
          onSelected: (String code) => unawaited(_setLanguage(code)),
        ),
      ],
    );
  }

  /// **代码与文件**分组：高亮 / 高亮主题 / （自定义配色）/ 换行 / 代码字号 / 排序。
  ///
  /// 层级：**依赖主题的子项紧跟父项并缩进** —— 选到"自定义"高亮主题时，
  /// 7 个色值行才出现在父项（高亮主题）正下方，缩进一级
  /// （[OgLSettingsIndent.step]）并用紧凑行，归属一眼可见。
  Widget _codeGroup(
    BuildContext context,
    ThemeData theme,
    OgLSettings value,
  ) =>
      OgLSettingsGroup(
        title: _t('codeAndFiles'),
        subtitle: _codeSummary(value),
        leading: const Icon(Icons.code),
        expanded: _isOpen('code'),
        onToggle: (bool open) => _toggleGroup('code', open),
        expandLabel: _t('expandGroup'),
        collapseLabel: _t('collapseGroup'),
        children: <Widget>[
          // 分组说明：收起态标题下是**当前值**摘要，展开后才给这段解释
          // （原来的固定说明从"标题下的摘要"下移到这里，措辞不变）。
          ListTile(
            dense: true,
            contentPadding: kOgLSettingsRowPadding,
            title: Text(
              _t('codeDesc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          OgLSettingsSwitchRow(
            title: _t('syntaxHighlight'),
            subtitle: _t('codeColorDesc'),
            value: value.codeHighlight,
            onChanged: (bool on) => unawaited(_settings.setCodeHighlight(on)),
          ),
          const Divider(height: 1),
          OgLSettingsChoiceTile<String>(
            title: _t('highlightTheme'),
            valueLabel: ogLCodePresetLabel(value.codeThemePreset),
            current: value.codeThemePreset,
            options: <OgLSettingsChoice<String>>[
              for (final MapEntry<String, String> entry
                  in kOgLCodePresetLabels.entries)
                OgLSettingsChoice<String>(
                  value: entry.key,
                  label: ogLCodePresetLabel(entry.key),
                ),
            ],
            onSelected: (String id) =>
                unawaited(_settings.setCodeThemePreset(id)),
          ),
          // 条件子项：常驻 AnimatedSize 承载（带过渡，档位 0 = 立即插拔）。
          AnimatedSize(
            duration: OgLAnim.medium(context),
            curve: OgLAnim.curve(context),
            alignment: Alignment.topCenter,
            child: value.codeThemePreset == kOgLCodePresetCustom
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
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
                      _codeColorTile(
                        theme,
                        _t('tokenKeyword'),
                        'keyword',
                        value.codeColorKeyword,
                      ),
                      _codeColorTile(
                        theme,
                        _t('tokenType'),
                        'typeName',
                        value.codeColorTypeName,
                      ),
                      _codeColorTile(
                        theme,
                        _t('tokenString'),
                        'string',
                        value.codeColorString,
                      ),
                      _codeColorTile(
                        theme,
                        _t('tokenComment'),
                        'comment',
                        value.codeColorComment,
                      ),
                      _codeColorTile(
                        theme,
                        _t('tokenNumber'),
                        'number',
                        value.codeColorNumber,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          const Divider(height: 1),
          OgLSettingsSwitchRow(
            title: _t('codeWrap'),
            subtitle: _t('codeWrapDesc'),
            value: value.codeWrap,
            onChanged: (bool on) => unawaited(_settings.setCodeWrap(on)),
          ),
          const Divider(height: 1),
          OgLSettingsSliderRow(
            title: _t('codeFontSize'),
            value: value.codeFontSize,
            min: OgLSettings.minCodeFontSize,
            max: OgLSettings.maxCodeFontSize,
            divisions: 12,
            display: (double v) => '${v.round()}',
            onCommit: _settings.setCodeFontSize,
          ),
          const Divider(height: 1),
          OgLSettingsSwitchRow(
            title: _t('foldersFirst'),
            subtitle: _t('foldersFirstDesc'),
            value: value.foldersFirst,
            onChanged: (bool on) => unawaited(_settings.setFoldersFirst(on)),
          ),
        ],
      );

  /// 网络 / DNS / 下载并发 / 加速通道。
  ///
  /// 这些内容渲染在**独立的网络设置页**里（见 `network_page.dart`），
  /// 不再是一个"可折叠分组"。
  ///
  /// ## 行型与设置页同一套零件
  /// 开关走 [OgLSettingsSwitchRow]、可选值走 [OgLSettingsChoiceTile] ——
  /// 子页面不再自造第二种内边距（原来自带默认 16/16，与设置页的 16/12
  /// 不一致），也不再各自手写选择弹窗（选 DNS 的弹窗与设置页的选择行
  /// 是同一个 [ogLShowSettingsChoice]）。
  List<Widget> _networkTiles(
          BuildContext context, ThemeData theme, OgLSettings value) =>
      <Widget>[
        OgLSettingsSwitchRow(
          title: _t('customDns'),
          subtitle: _t('dnsModeDesc'),
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
                    OgLSettingsChoiceTile<String>(
                      title: _t('dnsServer'),
                      dialogTitle: _t('selectDns'),
                      leading: const Icon(Icons.dns_outlined),
                      // 父项（自定义 DNS 开关）的子项：缩进一级，归属一眼可见。
                      indent: OgLSettingsIndent.step,
                      dense: true,
                      valueLabel:
                          widget.surface.dnsServerChoices[value.dnsServerId] ??
                              value.dnsServerId,
                      current: value.dnsServerId,
                      options: <OgLSettingsChoice<String>>[
                        for (final MapEntry<String, String> entry
                            in widget.surface.dnsServerChoices.entries)
                          OgLSettingsChoice<String>(
                            value: entry.key,
                            label: entry.value,
                          ),
                      ],
                      // 一个可选项都没有（预览 / 中枢未起来）时先给一句提示，
                      // 而不是弹一个空气泡。
                      onTap: widget.surface.dnsServerChoices.isEmpty
                          ? () => _notifier.warning(_t('noDnsServers'))
                          : null,
                      onSelected: (String id) => unawaited(_applyDnsServer(id)),
                    ),
                    OgLSettingsSwitchRow(
                      title: _t('doh'),
                      subtitle: _t('dnsServerDesc'),
                      indent: OgLSettingsIndent.step,
                      value: value.dnsPreferDoh,
                      onChanged: (bool on) =>
                          unawaited(widget.surface.setDnsPreferDoh(on)),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 1),
        ..._downloadTiles(value),
        ..._accelTiles(context, theme, value),
      ];

  /// 落盘 DNS 服务器选择（选择弹窗已收口到 [OgLSettingsChoiceTile]）。
  Future<void> _applyDnsServer(String serverId) async {
    await widget.surface.setDnsServer(serverId);
    if (mounted) {
      _notifier.success(_t('dnsSaved'));
    }
  }

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

  /// **存储与网络**分组：存储位置（权限档位 + SAF）/ 网络设置（DNS / 下载 / 加速）。
  ///
  /// 两项各自是"独立设置面"：一个决定文件落到哪里，一个决定请求怎么出去。
  /// 网络那页内容多（DNS / 下载并发 / 加速通道），仍是**独立子页面**，
  /// 这里只留入口，组内不再重复它的条目。
  Widget _storageGroup(ThemeData theme, OgLSettings value) => OgLSettingsGroup(
        title: _t('groupStorageNetwork'),
        subtitle: _storageSummary(value),
        leading: const Icon(Icons.storage_outlined),
        expanded: _isOpen('storage'),
        onToggle: (bool open) => _toggleGroup('storage', open),
        expandLabel: _t('expandGroup'),
        collapseLabel: _t('collapseGroup'),
        children: <Widget>[
          _navTile(
            theme,
            icon: Icons.folder_outlined,
            title: OgLI18n.instance.t('shell', 'storageAccess'),
            subtitle: OgLI18n.instance.t('shell', 'storageGrantDesc1'),
            onTap: _showStorage,
          ),
          const Divider(height: 1),
          _navTile(
            theme,
            icon: Icons.dns_outlined,
            title: _t('network'),
            subtitle: _t('dnsMode'),
            onTap: _openNetwork,
          ),
        ],
      );

  /// 统一的"点开就跑"条目行：内边距 / 箭头 / 说明行数**只有一处定义**。
  ///
  /// 说明一律限一行并省略：长说明文字不该把条目挤出屏幕
  /// （要读全文的点进去看，弹窗 / 子页面里是完整的）。
  Widget _navTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        contentPadding: kOgLSettingsRowPadding,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, size: 24),
        onTap: onTap,
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
        title: Text(OgLI18n.instance.t('shell', 'storageAccess')),
        content: SizedBox(
          width: _dialogWidth(dialogContext),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(modeText,
                    style: Theme.of(dialogContext).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                    '${OgLI18n.instance.t('shell', 'storageWhere')}：${info.path}'),
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
              child: Text(_t('storageOpenAllFiles')),
            ),
          TextButton(
            onPressed: () => unawaited(_pickSafFolder(dialogContext)),
            child: Text(_t('storagePickFolder')),
          ),
          if (saf != null)
            TextButton(
              onPressed: () => unawaited(_clearSafFolder(dialogContext)),
              child: Text(_t('storageClearFolder')),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_tc('close')),
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
    if (status == OgLPermissionStatus.granted) {
      _notifier.success(_t('storageAllFilesGranted'));
    } else {
      // 未拿到授权 → 下载落点受限，属"需要用户留意"，用告警语气而不是普通提示。
      _notifier.warning(OgLI18n.instance.t('shell', 'storageHintModern'));
    }
  }

  /// 选一个文件夹（SAF）并持久化授权。
  Future<void> _pickSafFolder(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    final bool ok = await widget.surface.pickSafDirectory();
    if (!mounted) {
      return;
    }
    if (ok) {
      _notifier.success(_t('storageModeSaf'));
    } else {
      _notifier.warning(OgLI18n.instance.t('shell', 'storageHintModern'));
    }
  }

  /// 取消 SAF 授权。
  Future<void> _clearSafFolder(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    await widget.surface.clearSafDirectory();
    if (mounted) {
      // 授权被撤销 = 下载落点重新受限，属"被拦下"，用告警语气（不是成功）。
      _notifier.warning(_t('storageClearFolder'));
    }
  }

  /// 统一提示入口（Phase 5 后半收敛）：**提示长什么样、什么语气只有一处定义**
  /// （见 [OgLNotifier]，即 `surface/app/notifier.dart`）—— 本页不再自造 SnackBar。
  ///
  /// 语气分工：[OgLNotifier.success] 操作已生效 / [OgLNotifier.info] 普通说明 /
  /// [OgLNotifier.warning] 失败与"被拦下"（权限不足、目标不存在、写回失败…）。
  OgLNotifier get _notifier => OgLNotifier(ScaffoldMessenger.of(context));

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
  ///
  /// 行型用共享的 [OgLSettingsChoiceTile]（原来自己搭 ListTile + 自己写弹窗，
  /// 与设置页的选择行是两套外观）。
  List<Widget> _downloadTiles(OgLSettings value) => <Widget>[
        OgLSettingsChoiceTile<int>(
          title: _t('downloadConnections'),
          subtitle: _t('downloadConnectionsDesc'),
          leading: const Icon(Icons.download_outlined),
          valueLabel: _t('connectionsCount', <String, Object?>{
            'count': value.downloadConnections,
          }),
          current: value.downloadConnections,
          options: <OgLSettingsChoice<int>>[
            for (final int choice in OgLSettings.downloadConnectionChoices)
              OgLSettingsChoice<int>(
                value: choice,
                label: _t('connectionsCount', <String, Object?>{
                  'count': choice,
                }),
              ),
          ],
          onSelected: (int picked) =>
              unawaited(_applyDownloadConnections(picked)),
        ),
      ];

  /// 落盘并发连接数（选择弹窗已收口到 [OgLSettingsChoiceTile]）。
  Future<void> _applyDownloadConnections(int picked) async {
    await widget.surface.setDownloadConnections(picked);
    if (mounted) {
      // 并发数已落盘生效 → 成功语气（不是普通说明）。
      _notifier.success(
        _t('connectionsCount', <String, Object?>{'count': picked}),
      );
    }
  }

  /// ── Release 下载加速（总开关 + 多通道 + 协议同意）────────────────────
  ///
  /// 设计：**只有一个总开关**；下面是通道列表（内置 + 自定义），可多选一。
  /// 开启总开关前若尚未同意当前版本协议，会先弹出协议并要求勾选同意
  /// （同意版本与时间会落盘，作为凭据）。
  List<Widget> _accelTiles(
      BuildContext context, ThemeData theme, OgLSettings value) {
    final List<Widget> tiles = <Widget>[
      OgLSettingsSwitchRow(
        title: _t('accelTitle'),
        subtitle: _t('accelDesc'),
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
                    contentPadding: kOgLSettingsRowPadding,
                    title: Text(
                      _t('accelScopesHint'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  for (final OgLAccelScope scope in OgLAccelScope.values)
                    OgLSettingsSwitchRow(
                      dense: true,
                      title: _t(scope.labelKey),
                      value: value.accelScopeEnabled(scope),
                      onChanged: (bool on) =>
                          unawaited(widget.surface.setAccelScope(scope, on)),
                    ),
                  const Divider(height: 24),
                  _subTitle(theme, _t('accelChannels')),
                  // 说明一行：通道由用户自备，本应用不预置任何通道。
                  ListTile(
                    dense: true,
                    contentPadding: kOgLSettingsRowPadding,
                    title: Text(
                      _tc('accelSelfProvided'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  // 私有仓库加速 = 把令牌交给第三方代理。这里给一个**永久开关**：
                  // 关掉 = 不再询问**且**不再加速（而不是"别问了但照旧送令牌"）。
                  OgLSettingsSwitchRow(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: _t('accelPrivateRepo'),
                    subtitle: _t('accelPrivateRepoDesc'),
                    value: value.accelPrivateRepoAccepted,
                    onChanged: (bool on) =>
                        unawaited(_setPrivateAccelAccepted(on)),
                  ),
                  // 空态 / 通道列表的**增删**都不单独包动画：它们与上面这一整块
                  // 同处外层 `AnimatedSize` 的覆盖内 —— 新增 / 删除通道时整块
                  // 高度变化由它平滑过渡（档位 0 → 零时长 = 立即变化）。
                  if (value.allAccelChannels.isEmpty)
                    // 空态必须说清楚：**本应用不提供通道**，想加速得自己填一个。
                    ListTile(
                      contentPadding: kOgLSettingsRowPadding,
                      leading: const Icon(Icons.info_outline),
                      title: Text(_tc('accelNoChannelTitle')),
                      subtitle: Text(_tc('accelNoChannelBody')),
                      isThreeLine: true,
                    ),
                  for (final OgLAccelChannel channel in value.allAccelChannels)
                    ListTile(
                      // 内边距与设置页同一常量（原来走默认 16/16）。
                      contentPadding: kOgLSettingsRowPadding,
                      // 单选状态进无障碍语义：屏幕阅读器能念出"已选中"，
                      // 而不是只报一个图标（写法对照色板的 Semantics）；
                      // `inMutuallyExclusiveGroup` 声明通道是一组互斥单选。
                      leading: Semantics(
                        selected: channel.id == value.releaseProxySelectedId,
                        inMutuallyExclusiveGroup: true,
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
                    contentPadding: kOgLSettingsRowPadding,
                    leading: const Icon(Icons.add),
                    title: Text(_t('addCustomChannel')),
                    // 说明**不截断**（"需自行确认可信"是安全提示，
                    // 被省略号吃掉就等于没写）。
                    subtitle: Text(_t('accelAddHint')),
                    onTap: _addAccelChannel,
                  ),
                  ListTile(
                    contentPadding: kOgLSettingsRowPadding,
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(_t('viewAccelAgreement')),
                    subtitle: Text(
                      value.accelConsentCurrent
                          ? (value.releaseProxyConsentAt == null
                              ? _t('consented', {
                                  'version':
                                      '${value.releaseProxyConsentVersion}',
                                })
                              : _t('consentedAt', {
                                  'version':
                                      '${value.releaseProxyConsentVersion}',
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
                          padding: const EdgeInsets.only(bottom: 8),
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
                      onChanged: (bool? v) =>
                          setLocal(() => agreed = v ?? false),
                      title: Text(_t('agreeRead')),
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
              child: Text(_t('disagree')),
            ),
            FilledButton(
              onPressed:
                  agreed ? () => Navigator.of(dialogContext).pop(true) : null,
              child: Text(_t('agreeContinue')),
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
        title: Text(_t('addCustomChannel')),
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
              decoration: InputDecoration(
                labelText: _t('channelName'),
                hintText: _t('channelNameHint'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              decoration: InputDecoration(
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
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('add')),
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
      _notifier.warning(error);
      return;
    }
    final String label =
        name.text.trim().isEmpty ? _t('customChannel') : name.text.trim();
    final String id = 'custom-${DateTime.now().millisecondsSinceEpoch}';
    await widget.surface.upsertAccelChannel(
        OgLAccelChannel(id: id, name: label, baseUrl: url.text));
    name.dispose();
    url.dispose();
    if (mounted) {
      _notifier.success(_t('channelAdded', {'label': label}));
    }
  }

  /// **账户**条（常驻，不做成折叠分组）。
  ///
  /// 只有一个分组却要折叠，反而多一次点击；身份信息放在设置页最上方，
  /// 一眼知道"现在是谁登录着"（退出登录在「用户页」，那里才是危险动作的归属地）。
  Widget _accountCard(ThemeData theme) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 卡片小标题：只有一行的卡片也把"这是什么"写出来 ——
            // 否则那只是一个带钥匙图标的 @名字，新用户不知道它指谁。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                _t('account'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AnimatedSize(
              duration: OgLAnim.medium(context),
              curve: OgLAnim.curve(context),
              alignment: Alignment.topCenter,
              // 「读取中 → 已登录 / 未登录」切换的是**高度不同**的行：
              // 用常驻 AnimatedSize 承载这次换挡（档位 0 → 零时长 = 立即跳变）。
              child: FutureBuilder<GhAccount?>(
                future: _accountFuture,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<GhAccount?> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return ListTile(
                      contentPadding: kOgLSettingsRowPadding,
                      leading: const Icon(Icons.key),
                      title: Text(_t('readingAccount')),
                    );
                  }
                  final GhAccount? account = snapshot.data;
                  if (account == null) {
                    return ListTile(
                      contentPadding: kOgLSettingsRowPadding,
                      leading: const Icon(Icons.key),
                      title: Text(_t('notLoggedIn')),
                      subtitle: Text(
                        _t('notLoggedInHint'),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }
                  return ListTile(
                    contentPadding: kOgLSettingsRowPadding,
                    leading: const Icon(Icons.key),
                    title: Text('@${account.login}'),
                    subtitle: Text(
                      _t('accountId', <String, Object?>{'id': account.id}),
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );

  /// **关于与帮助**分组：权限与引导 / 关于 / 捐赠 / 开源许可 / 法律文本。
  ///
  /// 五项原先散在三个卡片里（"维护"里的权限引导、"捐赠"卡片、"关于"卡片、
  /// "许可"卡片）。它们同属"看说明 / 找人帮忙"，合并后根级少三个卡片；
  /// 顺带把危险动作（重置）从"维护"里摘出去 —— 它现在单独在危险区，
  /// 不再和"权限与引导"当邻居。
  Widget _aboutGroup(ThemeData theme) => OgLSettingsGroup(
        title: _t('groupAboutHelp'),
        subtitle: _aboutSummary(),
        leading: const Icon(Icons.help_outline),
        expanded: _isOpen('about'),
        onToggle: (bool open) => _toggleGroup('about', open),
        expandLabel: _t('expandGroup'),
        collapseLabel: _t('collapseGroup'),
        children: <Widget>[
          _navTile(
            theme,
            icon: Icons.privacy_tip_outlined,
            title: _t('permissionsGuide'),
            subtitle: _t('recheckPermissions'),
            onTap: _openOnboarding,
          ),
          const Divider(height: 1),
          _navTile(
            theme,
            icon: Icons.info_outline,
            title: OgLI18n.instance.t('shell', 'about'),
            subtitle: _t('projectInfo'),
            onTap: _openAbout,
          ),
          const Divider(height: 1),
          _navTile(
            theme,
            icon: Icons.favorite_outline,
            title: _t('donateHeart'),
            // 捐赠入口：README 一直承诺此项，实现早已写好却没接线，
            // 这里把它接上（用当前登录令牌给项目仓库加星，含二次确认）。
            subtitle: _t('donateTileDesc', <String, Object?>{
              'repo': OgLProjectInfo.repoFullName,
            }),
            onTap: () => unawaited(_donateStar()),
          ),
          const Divider(height: 1),
          _navTile(
            theme,
            icon: Icons.gavel_outlined,
            title: _t('licenses'),
            subtitle: _t('licensesDesc'),
            onTap: () => unawaited(_showLicenses()),
          ),
          const Divider(height: 1),
          // 法律文本：**逐语言对照查看**。引导页那份面向首次阅读（重点 +
          // 折叠全文），这里面向查阅 —— 可以把全部可用语言逐个调出来。
          // 效力以中文为准的声明在该页顶部常驻。
          _navTile(
            theme,
            icon: Icons.translate,
            title: _t('legalText'),
            subtitle: _t('legalLanguages'),
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
        title:
            Text('${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}'),
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
        title: Text(_t('licenses')),
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
                  title: Text(_t('thirdPartyDeps')),
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
            child: Text(_tc('close')),
          ),
        ],
      ),
    );
  }

  /// **日志**分组（默认收起）：当前文件 + 未落盘原因 + 末尾若干行 + 复制全部。
  ///
  /// 厚度无上限的内容放进折叠组：收起态**不构建**正文
  /// （见 [OgLSettingsGroup]），长日志不拖累首帧。
  ///
  /// 外层再订阅一次日志：收起态的**摘要**要显示"写没写、写了多少行"，
  /// 它随日志增长变化；正文仍由内层 `ListenableBuilder` 承载（收起不构建）。
  Widget _logsGroup(ThemeData theme) => ListenableBuilder(
        listenable: OgLAppLog.instance,
        builder: (BuildContext context, Widget? _) => _logsCard(theme),
      );

  /// 日志分组卡片本体。
  Widget _logsCard(ThemeData theme) => OgLSettingsGroup(
        title: _t('logs'),
        subtitle: _logsSummary(),
        leading: const Icon(Icons.description_outlined),
        expanded: _isOpen('logs'),
        onToggle: (bool open) => _toggleGroup('logs', open),
        expandLabel: _t('expandGroup'),
        collapseLabel: _t('collapseGroup'),
        children: <Widget>[
          // 分组说明：收起时标题下看到的是**当前值**摘要，展开后才给这段解释
          // （原来的固定说明从"标题下的摘要"下移到这里，措辞不变）。
          ListTile(
            dense: true,
            contentPadding: kOgLSettingsRowPadding,
            title: Text(
              _t('logsDesc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: OgLAppLog.instance,
            builder: (BuildContext context, Widget? _) {
              final List<String> allLines = OgLAppLog.instance.entries
                  .map((OgLAppLogEntry entry) => entry.toDisplay())
                  .toList();
              final int shown = allLines.length > _logTailShown
                  ? _logTailShown
                  : allLines.length;
              final List<String> tail =
                  allLines.sublist(allLines.length - shown);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ListTile(
                    contentPadding: kOgLSettingsRowPadding,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_t('currentLogFile')),
                    subtitle: Text(
                      OgLLogFile.filePath ?? _t('logDisabled'),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!OgLLogFile.isEnabled)
                    ListTile(
                      contentPadding: kOgLSettingsRowPadding,
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(_t('logDisabledReason')),
                      subtitle: Text(
                        OgLLogFile.lastError ?? _t('unknown'),
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // 空态 ↔ 正文的切换由常驻 `AnimatedSize` 承载：
                  // 两种状态高度不同，不再瞬间跳变（档位 0 → 零时长 = 立即切换）。
                  AnimatedSize(
                    duration: OgLAnim.medium(context),
                    curve: OgLAnim.curve(context),
                    alignment: Alignment.topCenter,
                    child: tail.isEmpty
                        ? ListTile(
                            contentPadding: kOgLSettingsRowPadding,
                            title: Text(_t('noLogs')),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: SelectableText(
                              tail.join('\n'),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
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
                        label: Text(_t('copyAllLogs')),
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
        // 父项（高亮主题）的子项：缩进一级，归属一眼可见。
        contentPadding: kOgLSettingsRowPadding.copyWith(
          start: kOgLSettingsRowPadding.start + OgLSettingsIndent.step,
        ),
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 色块进无障碍语义：屏幕阅读器能念出当前颜色的十六进制值，
            // 而不是只报一个装饰性容器（写法对照色板的 Semantics）。
            Semantics(
              label: _t('colorSwatch', <String, Object?>{
                'color':
                    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
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
        onTap: () =>
            _pickCodeColor(field, argb, _t('chooseColor', {'label': label})),
      );
}
