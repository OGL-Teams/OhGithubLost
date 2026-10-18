/// L2 中枢级 · API 逻辑：GitHub 认证（多账号 + 安全保险库 + **可观察状态**）。
///
/// ## 三条安全铁律
/// 1. **令牌只进保险库**（Android Keystore / Windows DPAPI / Linux libsecret），
///    绝不落普通 KV、绝不进日志、绝不进错误信息；
/// 2. **令牌永不进 `toString()`**：只输出脱敏形态（`ghp_****abcd`）；
/// 3. **元数据与密文分开存**：账号元数据（登录名/头像）可被清理，
///    而令牌必须**显式删除**才消失——避免"清缓存把令牌一起清了"。
///
/// ## 为什么是可观察的（[ChangeNotifier]）
/// 登录态此前只在入口一次性读取，导致：令牌失效（401）后无人全局处理、
/// 切号后各页各自刷新。现在认证是**单一可观察状态源**：
/// 外壳与页面订阅它，登录 / 失效 / 切号 / 登出都自动联动。
///
/// ## 依赖约定（分层规则）
/// 本文件只使用 `base` 层暴露的**接口类型**（[DiskVault] / [DiskKv]）；
/// 实例一律由装配层经 `BaseBridge` 注入，**绝不 `new` 底座实现**。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../kernel/contract/disk_store.dart';
import '../../kernel/diagnostics.dart';

/// 认证状态（**全局单一真相**）。
enum GhAuthState {
  /// 尚未探测。
  unknown,

  /// 未登录。
  signedOut,

  /// 登录流程进行中。
  signingIn,

  /// 已登录（令牌可用）。
  signedIn,

  /// 令牌失效（如 401）。
  expired,

  /// 游客模式（只读浏览公开内容）。
  guest,
}

/// 访问令牌（**刻意不可打印明文**）。
class GhToken {
  /// 创建令牌。
  const GhToken(this.value);

  /// 明文（只允许在构造请求头时短暂使用）。
  final String value;

  /// 脱敏展示。
  String get masked => value.length <= 8
      ? '****'
      : '${value.substring(0, 4)}****${value.substring(value.length - 4)}';

  /// 形态是否像 GitHub 令牌。
  ///
  /// 覆盖 GitHub 当前全部公开前缀：
  /// `ghp_`（个人）/ `gho_`（OAuth）/ `ghu_`（用户到服务器）/
  /// `ghs_`（服务器到服务器）/ `ghr_`（刷新）/ `github_pat_`（细粒度）。
  bool get looksValid =>
      value.startsWith('ghp_') ||
      value.startsWith('gho_') ||
      value.startsWith('ghu_') ||
      value.startsWith('ghs_') ||
      value.startsWith('ghr_') ||
      value.startsWith('github_pat_');

  /// **只暴露脱敏形态**。
  @override
  String toString() => 'GhToken($masked)';
}

/// GitHub 账号（**不含令牌**）。
class GhAccount {
  /// 创建账号。
  const GhAccount({
    required this.id,
    required this.login,
    this.name,
    this.avatarUrl,
    this.scopes = const <String>[],
    this.addedAt,
  });

  /// 由 JSON 构造。
  factory GhAccount.fromJson(Map<String, dynamic> json) => GhAccount(
        id: json['id'] is String ? json['id'] as String : '',
        login: json['login'] is String ? json['login'] as String : '',
        name: json['name'] is String ? json['name'] as String : null,
        avatarUrl:
            json['avatarUrl'] is String ? json['avatarUrl'] as String : null,
        scopes: json['scopes'] is List
            ? (json['scopes'] as List<Object?>).whereType<String>().toList()
            : const <String>[],
        addedAt: json['addedAt'] is String
            ? DateTime.tryParse(json['addedAt'] as String)
            : null,
      );

  /// 稳定 ID（用 GitHub 数字 ID 或登录名的派生值，保证同名不同号可区分）。
  final String id;

  /// 登录名。
  final String login;

  /// 昵称。
  final String? name;

  /// 头像。
  final String? avatarUrl;

  /// 令牌作用域（用于提前告知"缺哪个权限"）。
  final List<String> scopes;

  /// 添加时间。
  final DateTime? addedAt;

  /// 是否为该账号配置了写权限（`repo`）。
  bool get canWrite => scopes.isEmpty || scopes.contains('repo');

  /// 序列化（**不含令牌**）。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'login': login,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'scopes': scopes,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
      };

  /// 复制并覆盖部分字段。
  GhAccount copyWith({
    String? login,
    String? name,
    String? avatarUrl,
    List<String>? scopes,
  }) =>
      GhAccount(
        id: id,
        login: login ?? this.login,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        scopes: scopes ?? this.scopes,
        addedAt: addedAt,
      );

  @override
  String toString() => 'GhAccount($login)';
}

/// 认证服务（**可观察**）。
class GhAuthService extends ChangeNotifier {
  /// 创建服务。
  GhAuthService({
    required DiskVault vault,
    required DiskKv store,
    KernelDiagnostics? diagnostics,
  })  : _vault = vault,
        _store = store,
        _diagnostics = diagnostics;

  /// 账号元数据前缀。
  static const String accountPrefix = 'ogl.gh.account.';

  /// 当前账号键。
  static const String activeKey = 'ogl.gh.active';

  /// 令牌密文前缀（存在保险库里）。
  static const String secretPrefix = 'gh.token.';

  final DiskVault _vault;
  final DiskKv _store;
  KernelDiagnostics? _diagnostics;

  GhAuthState _state = GhAuthState.unknown;
  String? _stateReason;

  /// 当前认证状态。
  GhAuthState get state => _state;

  /// 状态说明（如 401 的原因）。
  String? get stateReason => _stateReason;

  /// 是否已登录（令牌可用）。
  bool get isSignedIn => _state == GhAuthState.signedIn;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  void _setState(GhAuthState next, {String? reason}) {
    _state = next;
    _stateReason = reason;
    notifyListeners();
  }

  /// 全部账号（按添加时间升序）。
  Future<List<GhAccount>> accounts() async {
    final result = <GhAccount>[];
    for (final key in await _store.keys()) {
      if (!key.startsWith(accountPrefix)) {
        continue;
      }
      final raw = await _store.read(key);
      if (raw == null) {
        continue;
      }
      try {
        result.add(GhAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // 结构损坏：清掉，避免每次启动都报错。
        await _store.remove(key);
      }
    }
    result.sort((GhAccount a, GhAccount b) {
      final left = a.addedAt;
      final right = b.addedAt;
      if (left == null || right == null) {
        return a.login.compareTo(b.login);
      }
      return left.compareTo(right);
    });
    return result;
  }

  /// 保存账号与其令牌（令牌进保险库，元数据进 KV）。
  ///
  /// 两个存储是分开写的：即使 KV 写失败，令牌也不会丢；
  /// 反之令牌写失败则**不落元数据**——避免出现"账号在、令牌不在"的假象。
  Future<void> saveAccount(GhAccount account, GhToken token) async {
    await _vault.writeSecret('$secretPrefix${account.id}', token.value);
    await _store.write(
      '$accountPrefix${account.id}',
      jsonEncode(account.toJson()),
    );
    _diagnostics?.info(
      'AUTH',
      '账号已保存',
      code: 'OGL-AUTH-001',
      // 注意：只记登录名与脱敏令牌，绝不记明文。
      data: <String, Object?>{
        'login': account.login,
        'token': token.masked,
        'scopes': account.scopes,
      },
    );
    if (await activeAccountId() == account.id) {
      _setState(GhAuthState.signedIn);
    } else {
      notifyListeners();
    }
  }

  /// 当前账号 ID（未设置返回 `null`）。
  Future<String?> activeAccountId() async => await _store.read(activeKey);

  /// 当前账号（未设置返回 `null`）。
  Future<GhAccount?> activeAccount() async {
    final id = await activeAccountId();
    if (id == null) {
      return null;
    }
    final raw = await _store.read('$accountPrefix$id');
    if (raw == null) {
      return null;
    }
    try {
      return GhAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 从磁盘刷新一次认证状态（启动时调用）。
  Future<void> refreshState() async {
    final id = await activeAccountId();
    if (id == null) {
      _setState(GhAuthState.signedOut);
      return;
    }
    final hasToken = await _store.read('$accountPrefix$id') != null &&
        await _vault.readSecret('$secretPrefix$id') != null;
    _setState(hasToken ? GhAuthState.signedIn : GhAuthState.expired,
        reason: hasToken ? null : '令牌缺失');
  }

  /// 标记为令牌失效（由 401 统一出口调用）。
  void markExpired([String reason = '令牌无效或已过期']) {
    if (_state == GhAuthState.expired) {
      return;
    }
    _diagnostics?.warn(
      'AUTH',
      '令牌已失效：$reason',
      code: 'OGL-AUTH-101',
    );
    _setState(GhAuthState.expired, reason: reason);
  }

  /// 标记为游客模式。
  void markGuest() => _setState(GhAuthState.guest);

  /// 标记为未登录。
  void markSignedOut([String? reason]) =>
      _setState(GhAuthState.signedOut, reason: reason);

  /// 切换当前账号。
  ///
  /// **切换前校验令牌存在**：切到一个没有令牌的账号，
  /// 只会让用户以为"登录了"却处处 401。
  Future<bool> switchTo(String id) async {
    if (!await hasToken(id)) {
      _diagnostics?.warn(
        'AUTH',
        '拒绝切到无令牌的账号',
        code: 'OGL-AUTH-102',
        data: <String, Object?>{'accountId': id},
      );
      return false;
    }
    await _store.write(activeKey, id);
    _diagnostics?.info(
      'AUTH',
      '账号已切换',
      code: 'OGL-AUTH-002',
      data: <String, Object?>{'accountId': id},
    );
    _setState(GhAuthState.signedIn);
    return true;
  }

  /// 取某账号的令牌。
  Future<GhToken?> tokenFor(String id) async {
    final value = await _vault.readSecret('$secretPrefix$id');
    if (value == null || value.isEmpty) {
      return null;
    }
    return GhToken(value);
  }

  /// 当前账号的令牌（最常用）。
  Future<GhToken?> activeToken() async {
    final id = await activeAccountId();
    if (id == null) {
      return null;
    }
    return tokenFor(id);
  }

  /// 是否已保存令牌（**不读取明文**）。
  Future<bool> hasToken(String id) async {
    final value = await _vault.readSecret('$secretPrefix$id');
    return value != null && value.isNotEmpty;
  }

  /// 删除账号：**先删令牌，再删元数据**。
  ///
  /// 顺序很关键：若先删元数据而令牌删除失败，
  /// 就会留下一个"看不见但还在"的令牌——那是安全事故。
  Future<void> removeAccount(String id) async {
    await _vault.deleteSecret('$secretPrefix$id');
    await _store.remove('$accountPrefix$id');
    final wasActive = await activeAccountId() == id;
    if (wasActive) {
      await _store.remove(activeKey);
    }
    _diagnostics?.warn(
      'AUTH',
      '账号已删除',
      code: 'OGL-AUTH-003',
      data: <String, Object?>{'accountId': id},
    );
    if (wasActive) {
      // 还有其它已登录账号时自动切换到第一个，而不是把用户踢回登录门
      // （switchTo 本就支持——删当前账号不该比切账号代价更大）。
      final remaining = await accounts();
      if (remaining.isNotEmpty) {
        await switchTo(remaining.first.id);
        return;
      }
      _setState(GhAuthState.signedOut);
    } else {
      notifyListeners();
    }
  }

  /// 清空所有账号与其令牌（"退出全部"）。
  Future<int> removeAll() async {
    final list = await accounts();
    for (final account in list) {
      await removeAccount(account.id);
    }
    return list.length;
  }
}
