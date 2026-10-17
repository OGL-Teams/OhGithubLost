/// L3 展示级 · 我的（账户管理）。
///
/// - 账户列表：切换 / 移除（破坏性操作二次确认）；
/// - 新增账户：复用登录页（令牌向导）；
/// - Gist 片段入口（列表、详情、新建、编辑、删除）；
/// - 危险区：退出登录（删除本机令牌，远端数据不受影响）。
library;

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/og_l_space.dart';
import 'drafts_page.dart';
import 'gists_page.dart';
import 'login_page.dart';
import 'repo_page.dart';

/// 取 `profile_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'profile_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 我的页。
class ProfilePage extends StatefulWidget {
  /// 创建页面。
  const ProfilePage({
    required this.surface,
    required this.onAccountsChanged,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 账户变更回调（主壳用它重新过登录门）。
  final Future<void> Function() onAccountsChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  AsyncController<List<GhAccount>>? _accounts;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _accountsC().loadIfNeeded();
    // 草稿变更可观察：编辑保存 / 提交清稿后角标实时刷新。
    widget.surface.domain.api.draftsChanged.addListener(_onDraftsChanged);
  }

  @override
  void dispose() {
    widget.surface.domain.api.draftsChanged.removeListener(_onDraftsChanged);
    _accounts?.dispose();
    super.dispose();
  }

  void _onDraftsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  AsyncController<List<GhAccount>> _accountsC() {
    final existing = _accounts;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhAccount>>(
      label: _t('accounts'),
      isEmpty: (List<GhAccount> value) => value.isEmpty,
      loader: () async {
        final List<GhAccount> list =
            await widget.surface.domain.auth.accounts();
        _activeId = await widget.surface.domain.auth.activeAccountId();
        return list;
      },
    );
    _accounts = controller;
    return controller;
  }

  Future<void> _refresh() async {
    await _accountsC().load();
    // 会话里的账号信息必须跟着切换走，否则中枢层仍认为自己还是旧账号。
    await widget.surface.domain.session.refreshAccount();
    await widget.onAccountsChanged();
  }

  Future<void> _switchTo(GhAccount account) async {
    try {
      final bool ok = await widget.surface.domain.auth.switchTo(account.id);
      if (!mounted) {
        return;
      }
      if (!ok) {
        OgLNotifier.of(context).warning(
          _t('noTokenSwitch', {'login': account.login}),
        );
        return;
      }
      OgLAppLog.instance
          .result(_t('accounts'), _t('switched'), '@${account.login}');
      // 多用户安全：缓存不含账号维度（分页快照 / 仓库缓存都不含），
      // 切换后必须**清空所有缓存**，避免"用 B 账号看到 A 账号的私有数据"。
      await widget.surface.clearAllCaches();
      clearOgLRepoPageCaches();
      await _refresh();
    } catch (error) {
      OgLAppLog.instance.add(
        _t('accounts'),
        _t('switchFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('switchFailed', {'error': error}),
        );
      }
    }
  }

  Future<void> _remove(GhAccount account) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('removeTitle')),
        content: Text(
          _t('removeDesc', {'login': account.login}) + _t('removeDesc2'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('remove')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      // 统一走表面桥：注销 + 清**全部**缓存。
      // 此前这里只清仓库缓存，会留下 DNS 缓存与页面分页快照 ——
      // 多账号下正是「用 B 账号看到 A 账号内容」的串台来源。
      await widget.surface.forgetAccount(account.id);
      clearOgLRepoPageCaches();
      OgLAppLog.instance
          .result(_t('accounts'), _t('removed'), '@${account.login}');
      await _refresh();
    } catch (error) {
      OgLAppLog.instance.add(
        _t('accounts'),
        _t('removeFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('removeFailed', {'error': error}),
        );
      }
    }
  }

  Future<void> _addAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => LoginPage(
          surface: widget.surface,
          onLoggedIn: () async {
            await _accountsC().load();
            await widget.onAccountsChanged();
            if (routeContext.mounted) {
              Navigator.of(routeContext).pop();
            }
          },
        ),
      ),
    );
  }

  void _openGists() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GistsPage(surface: widget.surface),
      ),
    );
  }

  void _openDrafts() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DraftsPage(surface: widget.surface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncController<List<GhAccount>> controller = _accountsC();
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('mine')),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: _t('addAccount'),
            onPressed: _addAccount,
          ),
        ],
      ),
      body: AsyncView<List<GhAccount>>(
        controller: controller,
        emptyIcon: Icons.key_outlined,
        emptyText: _t('notLoggedIn'),
        builder: (BuildContext context, List<GhAccount> accounts) => ListView(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                  OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs),
              child: Text(_t('accounts')),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
              child: Column(
                children: <Widget>[
                  for (final GhAccount account in accounts)
                    ListTile(
                      leading: const Icon(Icons.key),
                      title: Text('@${account.login}'),
                      subtitle: Text(
                        account.id == _activeId
                            ? _t('currentAccount')
                            : _t('switchable'),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (account.id != _activeId)
                            TextButton(
                              onPressed: () => _switchTo(account),
                              child: Text(_t('switch')),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: _t('remove'),
                            onPressed: () => _remove(account),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: OgLSpace.lg),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.xxs),
              child: Text(_t('content')),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(_t('drafts')),
                subtitle: ListenableBuilder(
                  listenable: widget.surface.domain.api.draftsChanged,
                  builder: (BuildContext context, Widget? _) =>
                      FutureBuilder<int>(
                    future: widget.surface.domain.api.draftCount(),
                    builder:
                        (BuildContext context, AsyncSnapshot<int> snapshot) {
                      final int count = snapshot.data ?? 0;
                      return Text(count == 0
                          ? _t('noDrafts')
                          : _t('draftCount', {'count': count}));
                    },
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openDrafts,
              ),
            ),
            const SizedBox(height: OgLSpace.sm),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(_t('gists')),
                subtitle: Text(_t('gistsDesc')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openGists,
              ),
            ),
            const SizedBox(height: OgLSpace.lg),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.xxs),
              child: Text(_t('dangerZone')),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
              child: Padding(
                padding: const EdgeInsets.all(OgLSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_t('logoutDesc')),
                    const SizedBox(height: OgLSpace.md),
                    OutlinedButton(
                      onPressed: accounts.isEmpty
                          ? null
                          : () async {
                              final GhAccount? current = _currentOf(accounts);
                              if (current != null) {
                                await _remove(current);
                              }
                            },
                      child: Text(_t('logout')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: OgLSpace.xl),
          ],
        ),
      ),
    );
  }

  GhAccount? _currentOf(List<GhAccount> accounts) {
    for (final GhAccount account in accounts) {
      if (account.id == _activeId) {
        return account;
      }
    }
    return accounts.isEmpty ? null : accounts.first;
  }
}
