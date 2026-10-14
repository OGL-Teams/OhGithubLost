/// L2 · GitHub 认证状态机测试（内存态，注入 [InMemoryVault] / [InMemoryKv]）。
///
/// 覆盖 [GhAuthService] 的可观察状态迁移：
/// - [GhAuthService.markExpired]：幂等、自定义原因、不重复通知；
/// - [GhAuthService.refreshState]：无账号 → signedOut、有令牌 → signedIn、
///   元数据 / 令牌缺失 → expired；
/// - [GhAuthService.markGuest] / [markSignedOut] / [saveAccount] 等旁路迁移。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/kernel/contract/disk_store.dart';

void main() {
  late InMemoryVault vault;
  late InMemoryKv store;
  late GhAuthService auth;

  setUp(() {
    vault = InMemoryVault();
    store = InMemoryKv();
    auth = GhAuthService(vault: vault, store: store);
  });

  group('markExpired', () {
    test('从未登录态进入 expired，带默认原因', () {
      auth.markExpired();
      expect(auth.state, GhAuthState.expired);
      expect(auth.stateReason, '令牌无效或已过期');
    });

    test('自定义原因', () {
      auth.markExpired('401 拒绝');
      expect(auth.state, GhAuthState.expired);
      expect(auth.stateReason, '401 拒绝');
    });

    test('已是 expired 时幂等：不再通知、原因不被覆盖', () {
      int notified = 0;
      auth.addListener(() => notified++);
      auth.markExpired();
      expect(notified, 1);
      auth.markExpired('再次 401');
      expect(notified, 1);
      expect(auth.stateReason, '令牌无效或已过期');
    });
  });

  group('refreshState', () {
    test('无 active 账号 → signedOut', () async {
      await auth.refreshState();
      expect(auth.state, GhAuthState.signedOut);
    });

    test('有 active 账号且有令牌 → signedIn', () async {
      await store.write(GhAuthService.activeKey, '1');
      await store.write(
        '${GhAuthService.accountPrefix}1',
        jsonEncode({'id': '1', 'login': 'u'}),
      );
      await vault.writeSecret('${GhAuthService.secretPrefix}1', 'ghp_xxx');
      await auth.refreshState();
      expect(auth.state, GhAuthState.signedIn);
      expect(auth.stateReason, isNull);
    });

    test('有 active 账号但令牌缺失 → expired（令牌缺失）', () async {
      await store.write(GhAuthService.activeKey, '1');
      await store.write(
        '${GhAuthService.accountPrefix}1',
        jsonEncode({'id': '1', 'login': 'u'}),
      );
      await auth.refreshState();
      expect(auth.state, GhAuthState.expired);
      expect(auth.stateReason, '令牌缺失');
    });

    test('有 active 账号但元数据缺失 → expired', () async {
      await store.write(GhAuthService.activeKey, '1');
      await auth.refreshState();
      expect(auth.state, GhAuthState.expired);
      expect(auth.stateReason, '令牌缺失');
    });
  });

  group('其它状态迁移', () {
    test('markGuest / markSignedOut', () {
      auth.markGuest();
      expect(auth.state, GhAuthState.guest);
      auth.markSignedOut('用户登出');
      expect(auth.state, GhAuthState.signedOut);
      expect(auth.stateReason, '用户登出');
    });

    test('saveAccount 成为 active 账号 → signedIn', () async {
      await store.write(GhAuthService.activeKey, '1');
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'u'),
        const GhToken('ghp_abc12345'),
      );
      expect(auth.state, GhAuthState.signedIn);
      // 令牌只进保险库，不落 KV（元数据值里也不许出现明文）。
      expect(store.snapshot.values.join(), isNot(contains('ghp_abc12345')));
    });

    test('switchTo 无令牌账号被拒绝，状态不变', () async {
      final bool ok = await auth.switchTo('9');
      expect(ok, isFalse);
      expect(auth.state, GhAuthState.unknown);
    });
  });

  group('GhToken 脱敏', () {
    test('masked 只露首尾，短令牌整体打码', () {
      expect(const GhToken('ghp_abc12345').masked, 'ghp_****2345');
      expect(const GhToken('short').masked, '****');
    });

    test('looksValid 覆盖 GitHub 公开前缀', () {
      expect(const GhToken('ghp_x').looksValid, isTrue);
      expect(const GhToken('github_pat_x').looksValid, isTrue);
      expect(const GhToken('evil_x').looksValid, isFalse);
    });
  });
}
