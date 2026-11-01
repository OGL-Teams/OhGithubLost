/// L3 展示级 · 首次引导（分步）。
///
/// ## 分步设计
/// 用 `PageView` 把引导拆成 5 步：
/// **语言与外观** → 欢迎 → 权限 → 隐私 → 完成。
///
/// - 「语言与外观」放**第一步**：这两件事必须在用户看懂任何文案之前定下来；
/// - **不含登录**：按商业规范，登录不属于引导流程（登录页左上角可随时重看引导，
///   设置页也有全部设置项）。
///
/// ## 权限是「真请求」
/// 权限获取走 [OgLPermissionGateway]（不同平台不同网关）：
/// - 存储：用真实写入探针**主动获取**；失败则**弹窗**说明并**跳转**系统设置；
/// - 通知：弹窗说明后跳转系统设置（纯 Dart 无法直接申请）。
/// 拿不到就如实告诉用户，绝不自称已授权。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../app/overlays.dart';
import '../app/permissions.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';

/// 取 `onboarding` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'onboarding', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 取 `settings` 分片文案（引导里的「语言 / 外观」直接复用设置页的词条）。
/// 首次引导页。
class OnboardingPage extends StatefulWidget {
  /// 创建引导页。
  const OnboardingPage({
    required this.surface,
    required this.onFinished,
    this.review = false,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 完成回调（首次引导点「开始使用」/ 回顾模式点「完成」）。
  final VoidCallback onFinished;

  /// 是否「回顾模式」（从设置页进入；完成时不改动引导标志）。
  final bool review;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int _stepCount = 3;

  /// 「权限」页在 3 步中的下标（第 2 步）。
  ///
  /// 只有这一步需要等 `_infos`（权限探测结果）；其余步骤不应被它连累。
  static const int _permissionStepIndex = 1;

  late final OgLPermissionGateway _gateway = ogLPermissionGateway(
    storageProbe: widget.surface.ensureStorage,
    storageLocation: widget.surface.appStoragePath,
  );
  final PageController _page = PageController();

  int _step = 0;
  List<OgLPermissionInfo>? _infos;
  OgLPermission? _busyPermission;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<OgLPermissionInfo> infos = await _gateway.describe();
      if (!mounted) {
        return;
      }
      setState(() => _infos = infos);
    } catch (error) {
      OgLAppLog.instance.add(
        _t('title'),
        _t('permissionListFailed', {'error': error}),
        severity: OgLNoticeSeverity.warning,
      );
      if (mounted) {
        setState(() => _infos = const <OgLPermissionInfo>[]);
      }
    }
  }

  Future<void> _request(OgLPermissionInfo info) async {
    if (_busyPermission != null) {
      return;
    }
    setState(() => _busyPermission = info.permission);
    OgLAppLog.instance.add(
      _t('title'),
      _t('requestingPermission',
          {'title': info.title, 'platform': _gateway.platformLabel}),
    );
    OgLPermissionStatus status;
    try {
      status = await _gateway.request(info.permission);
    } catch (error) {
      OgLAppLog.instance.add(
        _t('title'),
        _t('permissionRequestFailed', {'error': error}),
        severity: OgLNoticeSeverity.warning,
      );
      status = OgLPermissionStatus.needsUserAction;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busyPermission = null);
    await _load();
    if (!mounted) {
      return;
    }
    await _explain(info, status);
  }

  /// 请求后的弹窗说明：能自动获取就报喜；否则说明为什么要手动、如何跳转。
  Future<void> _explain(
    OgLPermissionInfo info,
    OgLPermissionStatus status,
  ) async {
    switch (status) {
      case OgLPermissionStatus.granted:
        OgLNotifier.of(context).info(_t('ready', {'title': info.title}));
        return;
      case OgLPermissionStatus.notRequired:
        OgLNotifier.of(context).info(_t('noAuthNeeded', {'title': info.title}));
        return;
      case OgLPermissionStatus.needsUserAction:
      case OgLPermissionStatus.unsupported:
        await ogLShowDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(info.title),
            content: Text(
              status == OgLPermissionStatus.unsupported
                  ? _t('cannotInApp', {'rationale': info.rationale})
                  : _t('enableInSettings', {'rationale': info.rationale}),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(_t('gotIt')),
              ),
              if (_gateway.canOpenSettings)
                FilledButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _gateway.request(info.permission);
                    await _load();
                  },
                  child: Text(_t('openSettings')),
                ),
            ],
          ),
        );
        return;
    }
  }

  Future<void> _next() async {
    if (_step >= _stepCount - 1) {
      await _finish();
      return;
    }
    await _page.nextPage(
      duration: OgLAnim.pageViewDuration(context),
      curve: OgLAnim.largeCurve(context),
    );
  }

  Future<void> _back() async {
    if (_step <= 0) {
      return;
    }
    await _page.previousPage(
      duration: OgLAnim.pageViewDuration(context),
      curve: OgLAnim.largeCurve(context),
    );
  }

  Future<void> _finish() async {
    if (!widget.review) {
      await widget.surface.settings.setOnboardingDone(true);
    }
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: widget.review ? AppBar(title: Text(_t('permissionGuide'))) : null,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: OgLSpace.sm),
            _progress(theme),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (int value) => setState(() => _step = value),
                children: <Widget>[
                  // 简化后的三步：欢迎+偏好合并 → 权限+隐私合并 → 许可+完成。
                  // 原 6 步把"欢迎"与"外观偏好"拆开、又单独一页隐私说明，
                  // 新用户要点 6 次才能开始用——没人读，也没人想读。
                  _welcomeStep(theme),
                  _permissionStep(theme),
                  _licenseStep(theme),
                ],
              ),
            ),
            _navBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _progress(ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: OgLSpace.xl, vertical: OgLSpace.sm),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < _stepCount; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: OgLSpace.xxs),
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(OgLRadius.xs),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _navBar(ThemeData theme) {
    // 仅「权限」页在探测完成前禁用「下一步」，并**说明原因**；
    // 其余步骤不因 `_infos == null` 被莫名禁用（以前是全部步骤一起禁用）。
    final bool permissionPending =
        _step == _permissionStepIndex && _infos == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          OgLSpace.xl, OgLSpace.sm, OgLSpace.xl, OgLSpace.lg),
      child: Row(
        children: <Widget>[
          if (_step > 0)
            TextButton(onPressed: _back, child: Text(_t('previous'))),
          const Spacer(),
          Text('${_step + 1} / $_stepCount', style: theme.textTheme.bodySmall),
          const Spacer(),
          if (permissionPending)
            Padding(
              padding: const EdgeInsets.only(right: OgLSpace.sm),
              child: Text(
                _t('detectingPermissions'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          FilledButton(
            onPressed: permissionPending ? null : _next,
            child: Text(
              _step >= _stepCount - 1
                  ? (widget.review ? _t('finish') : _t('getStarted'))
                  : _t('next'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(ThemeData theme, {required List<Widget> children}) =>
      ListView(padding: const EdgeInsets.all(OgLSpace.xl), children: children);

  /// 第 1 步：**语言与外观**。
  ///
  /// 放在最前面：语言决定用户能不能看懂后面的每一步，外观决定整体观感。
  /// 两者都**即时生效**（改完立刻能看到），并复用设置页的同一套状态与词条。

  Widget _welcomeStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          const SizedBox(height: OgLSpace.xl),
          Icon(Icons.hub_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: OgLSpace.lg),
          Text(
            _t('welcomeTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: OgLSpace.sm),
          Text(
            _t('welcomeDesc') + _t('welcomeDesc2'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: OgLSpace.xl),
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(
                  _t('currentPlatform', {'platform': _gateway.platformLabel})),
              subtitle: Text(_t('platformNote')),
            ),
          ),
        ],
      );

  Widget _permissionStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          Text(_t('permissionIntro'), style: theme.textTheme.titleMedium),
          const SizedBox(height: OgLSpace.sm),
          if (_infos == null)
            const Padding(
              padding: EdgeInsets.all(OgLSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final OgLPermissionInfo info in _infos!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(OgLSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(_statusIcon(info.status), size: 20),
                          const SizedBox(width: OgLSpace.sm),
                          Expanded(
                            child: Text(
                              info.title,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          Chip(
                            label: Text(_statusText(info.status)),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: OgLSpace.sm),
                      Text(info.rationale, style: theme.textTheme.bodySmall),
                      const SizedBox(height: OgLSpace.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: _busyPermission == null && !info.ready
                              ? () => _request(info)
                              : null,
                          child: Text(
                            _busyPermission == info.permission
                                ? _t('fetching')
                                : info.ready
                                    ? _t('readyState')
                                    : _t('fetchOrSettings'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );

  Widget _licenseStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          const SizedBox(height: OgLSpace.sm),
          Row(
            children: <Widget>[
              Icon(Icons.gavel_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: OgLSpace.sm),
              Expanded(
                child: Text(
                  _t('licenseTitle'),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: OgLSpace.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(OgLSpace.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(OgLRadius.sm),
            ),
            child: Text(
              _t('licenseIntro'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(height: OgLSpace.md),
          // ── 定性说明：本文不产生法律效力，唯一生效的是 Apache-2.0 ──
          //    放在最前，因为它是整页的性质界定，读者有权先知道这一点。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(OgLSpace.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(OgLRadius.sm),
            ),
            child: Text(
              _t('legalStatementOnly'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(height: OgLSpace.lg),
          // ── 重点（人话版）：只放要点，不放细节 ──
          Text(
            _t('licenseHighlights'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: OgLSpace.sm),
          SelectableText(
            _t('onboardingLicenseHighlights'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
          ),
          const SizedBox(height: OgLSpace.lg),
          // ── 语言效力声明：必须在正文之前，且视觉上醒目 ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(OgLSpace.md),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(OgLRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.translate,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: OgLSpace.sm),
                Expanded(
                  child: Text(
                    _t('licenseAuthoritative'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OgLSpace.md),
          // ── 完整法律文本：默认折叠，细节一条不少 ──
          Card(
            margin: EdgeInsets.zero,
            child: ExpansionTile(
              // 刻意**不加** `initiallyExpanded`：默认收起。
              leading: Icon(Icons.description_outlined,
                  color: theme.colorScheme.onSurfaceVariant),
              title: Text(
                _t('licenseFullText'),
                style: theme.textTheme.titleSmall,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                  OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.lg),
              children: <Widget>[
                SelectableText(
                  _t('onboardingLicenseBody'),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: OgLSpace.xl),
        ],
      );

  String _statusText(OgLPermissionStatus status) {
    switch (status) {
      case OgLPermissionStatus.granted:
        return _t('stateGranted');
      case OgLPermissionStatus.needsUserAction:
        return _t('stateManual');
      case OgLPermissionStatus.notRequired:
        return _t('stateNotNeeded');
      case OgLPermissionStatus.unsupported:
        return _t('stateUnsupported');
    }
  }

  IconData _statusIcon(OgLPermissionStatus status) {
    switch (status) {
      case OgLPermissionStatus.granted:
        return Icons.check_circle_outline;
      case OgLPermissionStatus.needsUserAction:
        return Icons.privacy_tip_outlined;
      case OgLPermissionStatus.notRequired:
        return Icons.remove_circle_outline;
      case OgLPermissionStatus.unsupported:
        return Icons.block_outlined;
    }
  }
}
