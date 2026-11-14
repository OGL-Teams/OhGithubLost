/// L3 展示级 · 登录页（令牌向导）—— 全客户端的入口门。
///
/// ## 四步为什么必须可见
/// 登录会依次做：① 暂存待验证账户 → ② `GET /user` 验证令牌 →
/// ③ 转正并切换 → ④ **保险库回读自检**（防"存进去读不出来"的往返损坏）。
/// 任何一步失败都会让"看起来登上了、实际没有令牌"，
/// 因此每一步都摊开显示状态，失败时错误原样给用户看（并写日志）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../types.dart';
import '../util/og_l_space.dart';
import 'onboarding_page.dart';
import 'repo_page.dart';

/// 取 `login` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'login', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 登录页。
class LoginPage extends StatefulWidget {
  /// 创建登录页。
  const LoginPage({
    required this.surface,
    required this.onLoggedIn,
    this.onSkip,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 登录成功回调（由宿主决定去留）。
  final Future<void> Function() onLoggedIn;

  /// 可选：游客模式（跳过登录）。
  final Future<void> Function()? onSkip;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _input = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String _phase = '';

  /// OAuth Device Flow 状态（null = 未启动）。
  GhOAuthStatus? _oauthStatus;
  GhOAuthCode? _oauthCode;
  String? _oauthError;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) {
      return; // 回车连按 / 与按钮互斥：防双重提交
    }
    final String raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = OgLI18n.instance.t('login', 'tokenRequired'));
      return;
    }
    final GhToken token = GhToken(raw);
    if (!token.looksValid) {
      setState(
        () => _error = OgLI18n.instance.t('login', 'tokenShapeInvalid'),
      );
      return;
    }
    await _finishLogin(token);
  }

  /// OAuth Device Flow 登录（Client ID 未注入时按钮不显示，见 build）。
  Future<void> _loginWithOAuth() async {
    const String clientId = kOgLGitHubClientId;
    if (clientId.isEmpty) {
      setState(() {
        _oauthError = OgLI18n.instance.t('login', 'oauthClientMissing');
      });
      return;
    }
    setState(() {
      _busy = true;
      _oauthError = null;
      _error = null;
      _phase = '';
      _oauthStatus = GhOAuthStatus.pending;
    });
    try {
      final GhOAuthDeviceFlow flow = GhOAuthDeviceFlow(clientId: clientId);
      final GhOAuthCode code = await flow.start();
      if (!mounted) {
        return;
      }
      setState(() => _oauthCode = code);
      final String raw = await flow.poll(
        code,
        onStatus: (GhOAuthStatus status) {
          if (mounted) {
            setState(() => _oauthStatus = status);
          }
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _oauthCode = null);
      await _finishLogin(GhToken(raw));
    } on GhAuthException catch (error) {
      if (mounted) {
        setState(() {
          _oauthError = error.message;
          _busy = false;
          _oauthCode = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _oauthError = '$error';
          _busy = false;
          _oauthCode = null;
        });
      }
    }
  }

  /// PAT 与 OAuth 共用的验证链：暂存 → 验证 → 转正 → 清缓存 → 回读自检。
  Future<void> _finishLogin(GhToken token) async {
    setState(() {
      _busy = true;
      _error = null;
      _phase = OgLI18n.instance.t('login', 'verifying');
    });

    final auth = widget.surface.domain.auth;
    final api = widget.surface.domain.api;
    final String pendingId = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    // 记住登录前的激活账号：失败回滚时要回到**它**，而不是"最旧的账号"。
    final String? previousActive = await auth.activeAccountId();
    try {
      OgLAppLog.instance.add(_t('signIn'), '1/4 暂存待验证账户（$pendingId）');
      await auth.saveAccount(
          GhAccount(
              id: pendingId,
              login: OgLI18n.instance.t('login', 'pendingSuffix')),
          token);
      await auth.switchTo(pendingId);

      if (mounted) {
        setState(() {
          _phase = OgLI18n.instance.t('login', 'phaseVerify');
        });
      }
      OgLAppLog.instance.add(_t('signIn'), '2/4 验证令牌（GET /user）…');
      final me = await api.currentUser();
      OgLAppLog.instance.add(_t('signIn'), '3/4 验证成功：@${me.login}');

      if (mounted) {
        setState(() {
          _phase = OgLI18n.instance.t('login', 'phasePromote');
        });
      }
      await auth.saveAccount(
        GhAccount(id: 'user-${me.id}', login: me.login, name: me.name),
        token,
      );
      await auth.switchTo('user-${me.id}');
      await auth.removeAccount(pendingId);
      await widget.surface.clearAllCaches();
      clearOgLRepoPageCaches();

      if (mounted) {
        setState(() {
          _phase = OgLI18n.instance.t('login', 'phaseVault');
        });
      }
      final readBack = await auth.activeToken();
      OgLAppLog.instance.add(
        _t('signIn'),
        '4/4 保险库回读：${readBack?.masked ?? "读取失败（令牌可能未落库）"}',
      );
      // 回读自检是**门**，不是日志：读不回来说明令牌没有真正落库，
      // 放行会得到"看起来登上了、处处 401"的假登录。
      if (readBack == null) {
        throw StateError(OgLI18n.instance.t('login', 'vaultReadBackFailed'));
      }
      if (mounted) {
        await widget.onLoggedIn();
      }
    } on Object catch (error) {
      try {
        // 回滚到登录前的激活账号（若有），再清掉本次的临时/半成品账号。
        // 顺序：先恢复激活态，避免 removeAccount 把 activeKey 清成"最旧账号"。
        await auth.removeAccount(pendingId);
        if (previousActive != null && previousActive != pendingId) {
          await auth.switchTo(previousActive);
        }
      } on Object catch (cleanupError) {
        OgLAppLog.instance.add(
          _t('signIn'),
          '清理待验证账户失败：$cleanupError',
          severity: OgLNoticeSeverity.warning,
        );
      }
      if (mounted) {
        setState(() {
          _error = OgLI18n.instance.t('login', 'verifyFailed',
              args: <String, String>{'error': '$error'});
          _phase = '';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 打开引导页（**回顾模式**：不改动"已引导"标志，也不影响登录状态）。
  Future<void> _openOnboarding() async {
    // 先在同步段取好 Navigator：弹层关闭时不再依赖 builder 的 context。
    final NavigatorState navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OnboardingPage(
          surface: widget.surface,
          review: true,
          onFinished: () => navigator.pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Future<void> Function()? skip = widget.onSkip;
    return Scaffold(
      appBar: AppBar(
        title: Text(OgLI18n.instance.t('login', 'title')),
        // 左上角：**重新触发引导**（商业规范：引导只自动弹一次，
        // 之后由用户在这里主动唤起；设置页也有对应入口）。
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.school_outlined),
          // 可点但没有说明的图标，对屏幕阅读器（与普通用户）都是谜：
          // 补 tooltip 说明它打开引导。
          tooltip: OgLI18n.instance.t('common', 'guide'),
          onPressed: _busy ? null : () => unawaited(_openOnboarding()),
        ),
        actions: <Widget>[
          if (skip != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await skip();
                    },
              child: Text(OgLI18n.instance.t('login', 'skip')),
            ),
        ],
      ),
      body: OgLReveal(
          delay: Duration.zero,
          child: ListView(
            padding: const EdgeInsets.all(OgLSpace.lg),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(OgLSpace.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.security,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: OgLSpace.md),
                      Expanded(
                        child: Text(
                          // 保险库说明：`vaultNote`（含平台与域名等专有名词，不译）。
                          OgLI18n.instance.t('login', 'vaultNote'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: OgLSpace.lg),
              TextField(
                controller: _input,
                obscureText: _obscure,
                enabled: !_busy,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: OgLI18n.instance.t('login', 'tokenLabel'),
                  hintText: 'ghp_… / github_pat_…',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    tooltip: _obscure
                        ? OgLI18n.instance.t('login', 'showToken')
                        : OgLI18n.instance.t('login', 'hideToken'),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (String _) async {
                  // ★ LG-05：按钮禁用不等于键盘提交也被拦——连按 Enter
                  //   会重复发起登录。与按钮同一把闸。
                  if (_busy) {
                    return;
                  }
                  await _login();
                },
                onChanged: (String _) {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
              ),
              const SizedBox(height: OgLSpace.md),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: _busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: OgLSpace.sm),
                          Text(OgLI18n.instance.t('login', 'verifying')),
                        ],
                      )
                    : Text(OgLI18n.instance.t('login', 'signIn')),
              ),
              if (_phase.isNotEmpty) ...<Widget>[
                const SizedBox(height: OgLSpace.sm),
                Text(_phase, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: OgLSpace.md),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(OgLSpace.md),
                    child: Text(
                      // 错误详情：保留原始异常 + 引导去「关于」页复制。
                      OgLI18n.instance.t(
                        'login',
                        'errorDetail',
                        args: <String, String>{'error': _error ?? ''},
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              // ── OAuth Device Flow（Client ID 未注入时整块隐藏）──────
              if (kOgLGitHubClientId.isNotEmpty) ...<Widget>[
                const SizedBox(height: OgLSpace.lg),
                Row(
                  children: <Widget>[
                    const Expanded(child: Divider()),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: OgLSpace.md),
                      child: Text(
                        OgLI18n.instance.t('login', 'orDivider'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: OgLSpace.lg),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _loginWithOAuth,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(OgLI18n.instance.t('login', 'oauthButton')),
                ),
                if (_oauthCode != null) ...<Widget>[
                  const SizedBox(height: OgLSpace.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(OgLSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            OgLI18n.instance.t('login', 'oauthStep1'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: OgLSpace.sm),
                          SelectableText(
                            _oauthCode!.verificationUri,
                            style: const TextStyle(fontFamily: kOglMonoFamily),
                          ),
                          const SizedBox(height: OgLSpace.md),
                          Text(
                            OgLI18n.instance.t('login', 'oauthStep2'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: OgLSpace.sm),
                          SelectableText(
                            _oauthCode!.userCode,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontFamily: kOglMonoFamily,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: OgLSpace.md),
                          Text(
                            _oauthStatus == GhOAuthStatus.granted
                                ? OgLI18n.instance.t('login', 'oauthGranted')
                                : OgLI18n.instance.t('login', 'oauthWaiting'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_oauthError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: OgLSpace.md),
                    child: Text(
                      _oauthError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ],
          )),
    );
  }
}
