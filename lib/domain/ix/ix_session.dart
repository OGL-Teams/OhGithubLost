/// L2 中枢级 · 交互逻辑：会话（上下文 + 偏好）。
///
/// 会话持有"用户此刻在看什么、以什么方式看"：
/// 当前账号 / 仓库 / 分支 / 路径，以及视图模式、排序、文件夹置顶等偏好。
///
/// **为什么单独成类**：这些状态会被 UI、API、Mod 同时读取，
/// 散在各页面里必然出现"列表页改了排序、仓库页不知道"的经典不一致。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../kernel/contract/disk_store.dart';
import '../../kernel/diagnostics.dart';
import '../gh/gh_auth.dart';
import '../gh/gh_models.dart';

/// 视图模式。
enum IxViewMode {
  /// 详细列表。
  list,

  /// 网格（适合看图）。
  grid,
}

/// 排序方式。
enum IxSortBy {
  /// 名称。
  name,

  /// 大小。
  size,

  /// 修改时间。
  updated,
}

/// 排序方向。
enum IxSortOrder {
  /// 升序。
  ascending,

  /// 降序。
  descending,
}

/// 会话上下文快照（用于恢复上次位置）。
class IxContext {
  /// 创建上下文。
  const IxContext({
    this.repo,
    this.branch,
    this.path = '',
  });

  /// 当前仓库（`owner/name`）。
  final String? repo;

  /// 当前分支。
  final String? branch;

  /// 当前目录（仓库内相对路径，根为 `''`）。
  final String path;

  /// 是否已进入某个仓库。
  bool get inRepo => repo != null && repo!.isNotEmpty;

  /// 面包屑（逐级路径）。
  List<String> get breadcrumbs {
    if (path.isEmpty) {
      return const <String>[];
    }
    return path.split('/').where((String part) => part.isNotEmpty).toList();
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        if (repo != null) 'repo': repo,
        if (branch != null) 'branch': branch,
        'path': path,
      };

  /// 反序列化。
  static IxContext fromJson(Map<String, dynamic> json) => IxContext(
        repo: json['repo'] is String ? json['repo'] as String : null,
        branch: json['branch'] is String ? json['branch'] as String : null,
        path: json['path'] is String ? json['path'] as String : '',
      );
}

/// 会话。
class IxSession extends ChangeNotifier {
  /// 创建会话。
  IxSession({
    required GhAuthService auth,
    DiskKv? store,
    KernelDiagnostics? diagnostics,
  })  : _auth = auth,
        _store = store,
        _diagnostics = diagnostics;

  static const String _contextKey = 'ogl.ix.context';
  static const String _prefsKey = 'ogl.ix.prefs';

  final GhAuthService _auth;
  final DiskKv? _store;
  KernelDiagnostics? _diagnostics;

  IxContext _context = const IxContext();
  IxViewMode _viewMode = IxViewMode.list;
  IxSortBy _sortBy = IxSortBy.name;
  IxSortOrder _sortOrder = IxSortOrder.ascending;
  bool _folderFirst = true;
  List<String> _searchHistory = const <String>[];
  GhAccount? _account;

  /// 当前上下文。
  IxContext get context => _context;

  /// 当前账号（可能为 `null`，表示未登录）。
  GhAccount? get account => _account;

  /// 视图模式。
  IxViewMode get viewMode => _viewMode;

  /// 排序方式。
  IxSortBy get sortBy => _sortBy;

  /// 排序方向。
  IxSortOrder get sortOrder => _sortOrder;

  /// 文件夹是否置顶（默认开启：目录结构更清晰）。
  bool get folderFirst => _folderFirst;

  /// 搜索历史。
  List<String> get searchHistory => List<String>.unmodifiable(_searchHistory);

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 从磁盘恢复会话（启动时调用一次）。
  Future<void> restore() async {
    final store = _store;
    _account = await _auth.activeAccount();
    if (store == null) {
      return;
    }
    final contextRaw = await store.read(_contextKey);
    if (contextRaw != null) {
      try {
        _context = IxContext.fromJson(
          jsonDecode(contextRaw) as Map<String, dynamic>,
        );
      } catch (_) {
        await store.remove(_contextKey);
      }
    }
    final prefsRaw = await store.read(_prefsKey);
    if (prefsRaw != null) {
      try {
        final json = jsonDecode(prefsRaw) as Map<String, dynamic>;
        _viewMode = _enumOf(IxViewMode.values, json['viewMode'], _viewMode);
        _sortBy = _enumOf(IxSortBy.values, json['sortBy'], _sortBy);
        _sortOrder = _enumOf(IxSortOrder.values, json['sortOrder'], _sortOrder);
        _folderFirst = json['folderFirst'] is bool
            ? json['folderFirst'] as bool
            : _folderFirst;
        final history = json['searchHistory'];
        if (history is List) {
          _searchHistory = history.whereType<String>().take(20).toList();
        }
      } catch (_) {
        await store.remove(_prefsKey);
      }
    }
    _diagnostics?.info(
      'IX',
      '会话已恢复',
      code: 'OGL-IX-001',
      data: <String, Object?>{
        'account': _account?.login,
        'repo': _context.repo,
        'path': _context.path,
      },
    );
    notifyListeners();
  }

  /// 进入仓库（会重置路径）。
  Future<void> enterRepo(String fullName, {String? branch}) async {
    _context = IxContext(repo: fullName, branch: branch);
    await _persistContext();
    notifyListeners();
  }

  /// 切换分支（保留路径，但回到根更安全：不同分支目录结构可能不同）。
  Future<void> setBranch(String branch, {bool keepPath = false}) async {
    _context = IxContext(
      repo: _context.repo,
      branch: branch,
      path: keepPath ? _context.path : '',
    );
    await _persistContext();
    notifyListeners();
  }

  /// 进入目录。
  Future<void> enterDirectory(String path) async {
    _context = IxContext(
      repo: _context.repo,
      branch: _context.branch,
      path: path,
    );
    await _persistContext();
    notifyListeners();
  }

  /// 返回上级目录（已在根则不动）。
  Future<bool> goUp() async {
    if (_context.path.isEmpty) {
      return false;
    }
    final index = _context.path.lastIndexOf('/');
    await enterDirectory(index < 0 ? '' : _context.path.substring(0, index));
    return true;
  }

  /// 退出仓库（回到仓库列表）。
  Future<void> leaveRepo() async {
    _context = IxContext(branch: _context.branch);
    await _persistContext();
    notifyListeners();
  }

  /// 设置视图模式。
  Future<void> setViewMode(IxViewMode mode) async {
    if (_viewMode == mode) {
      return;
    }
    _viewMode = mode;
    await _persistPrefs();
    notifyListeners();
  }

  /// 设置排序。
  Future<void> setSort(
    IxSortBy by, {
    IxSortOrder? order,
    bool? folderFirst,
  }) async {
    _sortBy = by;
    if (order != null) {
      _sortOrder = order;
    }
    if (folderFirst != null) {
      _folderFirst = folderFirst;
    }
    await _persistPrefs();
    notifyListeners();
  }

  /// 记录一次搜索。
  Future<void> rememberSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _searchHistory = <String>[
      trimmed,
      ..._searchHistory.where((String item) => item != trimmed),
    ].take(20).toList();
    await _persistPrefs();
    notifyListeners();
  }

  /// 清空搜索历史。
  Future<void> clearSearchHistory() async {
    _searchHistory = const <String>[];
    await _persistPrefs();
    notifyListeners();
  }

  /// 账号切换后刷新会话（由交互层在切换成功后调用）。
  Future<void> refreshAccount() async {
    _account = await _auth.activeAccount();
    // ★ 上下文里可能装着上一个账号的仓库（生命周期审计 L5）：切号必须
    //   一并清掉（内存 + 持久化），否则持久化的 context 会把 A 的私有仓
    //   库名带进 B 的会话——当前虽无直接消费点，这是隐性契约，等第一个
    //   读取点出现就踩中。
    if (_context.repo.isNotEmpty) {
      _context = const IxContext();
      try {
        await _store?.remove(_contextKey);
      } on Object {
        // 持久化清理失败不阻断：内存已清，重启后 restore 会再按需取。
      }
    }
    notifyListeners();
  }

  /// 按当前偏好排序条目。
  List<GhTreeEntry> sortEntries(List<GhTreeEntry> entries) {
    final sorted = List<GhTreeEntry>.of(entries);
    sorted.sort((GhTreeEntry a, GhTreeEntry b) {
      if (_folderFirst && a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      int result;
      switch (_sortBy) {
        case IxSortBy.size:
          result = a.size.compareTo(b.size);
        case IxSortBy.updated:
          // 树节点没有时间字段，退回按名称，避免"看起来随机"。
          result = a.path.compareTo(b.path);
        case IxSortBy.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortOrder == IxSortOrder.descending ? -result : result;
    });
    return sorted;
  }

  Future<void> _persistContext() async {
    await _store?.write(_contextKey, jsonEncode(_context.toJson()));
  }

  Future<void> _persistPrefs() async {
    await _store?.write(
      _prefsKey,
      jsonEncode(<String, Object?>{
        'viewMode': _viewMode.name,
        'sortBy': _sortBy.name,
        'sortOrder': _sortOrder.name,
        'folderFirst': _folderFirst,
        'searchHistory': _searchHistory,
      }),
    );
  }

  static T _enumOf<T extends Enum>(List<T> values, Object? name, T fallback) {
    if (name is! String) {
      return fallback;
    }
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }
}
