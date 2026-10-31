/// L2 中枢级 · API 逻辑：GitHub 端点封装（并实现底座要求的 [CacheRemote]）。
///
/// 覆盖面：认证 / 仓库 / 分支 / 内容 / 树 / 批量提交 / Releases / 搜索 /
/// 提交历史 / Pages / 组织 / 星标 / Issues / PR / Gist / Actions / 标签。
///
/// **最关键的一段是文件末尾的 [CacheRemote] 实现**：
/// 它把底座的 D1–D7 一致性引擎接到真实 GitHub API 上——
/// `read` 取 sha+内容，`write` 带 sha 提交，409/422 翻译成 [RemoteConflictException]。
/// 没有它，底座再严密也只是空转。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../base/disk/disk_cache.dart';
import '../../kernel/contract/disk_types.dart';
import '../../kernel/contract/net_types.dart';
import '../../kernel/log/og_l_log_file.dart';
import 'gh_client.dart';
import 'gh_draft.dart';
import 'gh_models.dart';

/// 仓库路径按段编码，保留 `/` 分隔且不会把 `#` / `?` 当成 URL 语法。
String _ghPath(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');

/// GitHub 端点封装。
class GhApi implements CacheRemote {
  /// 创建封装。
  GhApi({required this.client});

  /// 请求客户端。
  final GhClient client;

  static const int _contentSizeLimit = 1024 * 1024; // Contents API 的 1 MB 红线

  /// 目录列表在缓存里的 SHA 标记前缀。
  ///
  /// 目录不是文件、没有 blob sha；用 `dir:` 前缀把"目录列表"与"文件内容"
  /// 在同一套缓存键空间里区分开（GitHub 的文件 sha 是 40 位十六进制，
  /// 不可能以 `dir:` 开头，因此**无歧义**）。
  static const String _dirShaPrefix = 'dir:';

  /// 目录列表缓存 TTL（变化快，给短 TTL；显式刷新可绕过）。
  static const Duration _dirMaxAge = Duration(minutes: 1);

  /// 文件内容缓存 TTL（编辑需要新鲜基线，给较短 TTL）。
  static const Duration _contentMaxAge = Duration(seconds: 30);

  // ───────────────────────── 读穿透缓存（装配期绑定）─────────────────────────

  RepositoryCache? _cache;
  Future<String> Function()? _accountIdProvider;
  final Map<String, String> _defaultBranchMemo = <String, String>{};

  /// 是否已绑定读穿透缓存。
  bool get hasReadCache => _cache != null;

  /// 草稿变更通知（草稿箱 / 角标据此实时刷新）。
  ///
  /// 未绑定缓存时返回一个**永不通知**的占位，便于 UI 无条件订阅。
  Listenable get draftsChanged => _cache?.drafts ?? _neverNotifier;

  static final ChangeNotifier _neverNotifier = ChangeNotifier();

  /// 绑定读穿透缓存（由 `domain_bridge` 在装配阶段调用）。
  ///
  /// 绑定后：目录列表 / 文件内容优先走底座 [RepositoryCache]（TTL + 完整性
  /// 校验 + 有界淘汰），未命中再回源；写路径经 [putContentLocked] 走 D1–D7。
  void attachReadCache(
    RepositoryCache cache, {
    required Future<String> Function() accountId,
  }) {
    _cache = cache;
    _accountIdProvider = accountId;
  }

  int get _cacheSchemaVersion => 1;

  /// 为 `(repo, branch, path)` 构造缓存键（账号维度由 provider 提供）。
  ///
  /// 返回 `null` 表示"不适合缓存"（未绑定 / 分支解析不出 / 键不合法）——
  /// 此时调用方必须**落回网络**，绝不因为缓存问题阻断读取。
  Future<CacheKey?> _cacheKeyFor(
    String fullName,
    String path,
    String? branch,
  ) async {
    if (_cache == null) {
      return null;
    }
    final String ref = (branch != null && branch.isNotEmpty)
        ? branch
        : await _defaultBranchOf(fullName);
    if (ref.isEmpty) {
      return null;
    }
    var account = 'guest';
    try {
      final String? id = await _accountIdProvider?.call();
      if (id != null && id.isNotEmpty) {
        account = id;
      }
    } catch (_) {
      account = 'guest';
    }
    final CacheKey key = CacheKey(
      scope: CacheScope(
        schemaVersion: _cacheSchemaVersion,
        accountId: account,
        repo: fullName,
        branch: ref,
      ),
      path: path,
    );
    return key.isWellFormed ? key : null;
  }

  /// 让**只读端点缓存**整体失效（下拉刷新 / 写后重读 / 切换账号时调用）。
  Future<void> invalidateReadCache() => client.invalidateReadCache();

  // ───────────────────────── 认证 ─────────────────────────

  /// 当前用户。
  Future<GhUser> currentUser() async {
    final object = await client.getObject('/user', label: 'GET /user');
    return GhUser.fromJson(object ?? const <String, dynamic>{});
  }

  /// 额度。
  Future<GhRateLimit?> rateLimit() async {
    final object =
        await client.getObject('/rate_limit', label: 'GET /rate_limit');
    final core = object?['resources'];
    if (core is Map && core['core'] is Map) {
      final coreMap = Map<String, dynamic>.from(core['core'] as Map);
      return GhRateLimit(
        limit: GhJson.integer(coreMap, 'limit'),
        remaining: GhJson.integer(coreMap, 'remaining'),
        resetAt: DateTime.fromMillisecondsSinceEpoch(
          GhJson.integer(coreMap, 'reset') * 1000,
          isUtc: true,
        ),
      );
    }
    return client.lastRateLimit;
  }

  // ───────────────────────── 仓库 ─────────────────────────

  /// 我的仓库。
  Future<List<GhRepo>> myRepos({
    int perPage = 100,
    int page = 1,
    String sort = 'updated',
  }) async {
    final list = await client.getList(
      '/user/repos',
      query: <String, String>{
        'per_page': '$perPage',
        'page': '$page',
        'sort': sort,
        'affiliation': 'owner,collaborator,organization_member',
      },
      label: 'GET /user/repos',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 星标仓库。
  Future<List<GhRepo>> starredRepos({
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/user/starred',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /user/starred',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 某人名下的公开仓库。
  Future<List<GhRepo>> userRepos(
    String login, {
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/users/$login/repos',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /users/$login/repos',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 组织仓库。
  Future<List<GhRepo>> orgRepos(
    String org, {
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/orgs/$org/repos',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /orgs/$org/repos',
    );
    return list.map(GhRepo.fromJson).toList();
  }

  /// 仓库详情。
  Future<GhRepo> repo(String fullName) async {
    final object = await client.getObject('/repos/$fullName',
        label: 'GET /repos/$fullName');
    return GhRepo.fromJson(object ?? const <String, dynamic>{});
  }

  /// 新建仓库。
  Future<GhRepo> createRepo({
    required String name,
    String? description,
    bool private = false,
    bool autoInit = true,
  }) async {
    final response = await client.send(GhRequest(
      path: '/user/repos',
      method: NetMethod.post,
      body: <String, Object?>{
        'name': name,
        if (description != null) 'description': description,
        'private': private,
        'auto_init': autoInit,
      },
      label: 'POST /user/repos',
    ));
    return GhRepo.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 更新仓库设置。
  Future<GhRepo> updateRepo(
    String fullName, {
    String? name,
    String? description,
    bool? private,
    String? defaultBranch,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName',
      method: NetMethod.patch,
      body: <String, Object?>{
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (private != null) 'private': private,
        if (defaultBranch != null) 'default_branch': defaultBranch,
      },
      label: 'PATCH /repos/$fullName',
    ));
    // ★ 默认分支变了就必须作废进程内记忆：缓存键、createBranch、
    //   enablePages 全部走 _defaultBranchOf——留着旧值会整条链路
    //   静默落在旧分支上（显示与实际不符），重启前都不会自愈。
    if (defaultBranch != null && defaultBranch.isNotEmpty) {
      _defaultBranchMemo[fullName] = defaultBranch;
    }
    return GhRepo.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 删除仓库（**危险操作**，调用方必须先二次确认）。
  Future<void> deleteRepo(String fullName) => client
      .send(GhRequest(
        path: '/repos/$fullName',
        method: NetMethod.delete,
        label: 'DELETE /repos/$fullName',
      ))
      .then((_) {});

  /// 复刻。
  Future<GhRepo> fork(String fullName) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/forks',
      method: NetMethod.post,
      label: 'POST /repos/$fullName/forks',
    ));
    return GhRepo.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 加星 / 取消星标。
  Future<void> setStarred(String fullName, bool starred) => client
      .send(GhRequest(
        path: '/user/starred/$fullName',
        method: starred ? NetMethod.put : NetMethod.delete,
        label: '${starred ? 'PUT' : 'DELETE'} /user/starred/$fullName',
      ))
      .then((_) {});

  /// 当前登录用户是否已 star 指定仓库。
  ///
  /// `GET /user/starred/{owner}/{repo}`：已 star 返回 204，未 star 返回 404。
  /// 404 属于**正常结果**（未 star），因此单独处理为 `false`，不当作错误抛出。
  ///
  /// 注意语义边界：对当前令牌**不可见**的仓库（无权私有仓库）GitHub 同样
  /// 返回 404——此时"未星标"是**无法判定**的猜测。调用方（仓库页）只应
  /// 在"仓库本身已可读"的上下文里使用本方法，404 才能可靠地解读为未星标。
  Future<bool> isRepoStarred(String fullName) async {
    try {
      await client.send(GhRequest(
        path: '/user/starred/$fullName',
        method: NetMethod.get,
        label: 'GET /user/starred/$fullName',
      ));
      return true;
    } on GhNotFoundException {
      return false;
    }
  }

  // ───────────────────────── 草稿（D9）─────────────────────────

  /// 列出本机草稿（草稿箱数据源）。
  Future<List<GhDraft>> drafts() async {
    final store = _cache?.drafts;
    if (store == null) {
      return const <GhDraft>[];
    }
    final all = await store.all();
    return <GhDraft>[
      for (final record in all)
        GhDraft(
          repo: record.key.scope.repo,
          branch: record.key.scope.branch,
          path: record.key.path,
          content: record.content,
          revision: record.revision,
          updatedAt: record.updatedAt,
        ),
    ];
  }

  /// 草稿数量（角标数据源）。
  Future<int> draftCount() async => (await drafts()).length;

  /// 读取某文件的草稿内容（无草稿返回 `null`）。
  ///
  /// 键与写入路径完全一致（同一账号 / 仓库 / 分支 / 路径），
  /// 因此编辑器保存的草稿能被草稿箱与"重新进入"读到。
  Future<DraftRecord?> loadDraftRecord(
    String fullName,
    String path, {
    String? branch,
  }) async {
    final key = await _cacheKeyFor(fullName, path, branch);
    final store = _cache?.drafts;
    if (key == null || store == null) {
      return null;
    }
    return store.load(key);
  }

  /// 兼容只读取正文的调用方。
  Future<String?> loadDraft(String fullName, String path,
          {String? branch}) async =>
      (await loadDraftRecord(fullName, path, branch: branch))?.content;

  /// 保存草稿（编辑器防抖调用）。
  Future<void> saveDraft(
    String fullName,
    String path,
    String content, {
    String? branch,
    String? baseSha,
  }) async {
    final key = await _cacheKeyFor(fullName, path, branch);
    final store = _cache?.drafts;
    if (key == null || store == null) {
      return;
    }
    await store.save(key, content, baseSha: baseSha);
  }

  /// 丢弃某文件的草稿（提交成功后缓存引擎也会自动清理）。
  Future<void> discardDraft(
    String fullName,
    String path, {
    String? branch,
  }) async {
    final key = await _cacheKeyFor(fullName, path, branch);
    final store = _cache?.drafts;
    if (key == null || store == null) {
      return;
    }
    await store.discard(key);
  }

  // ───────────────────────── 分支 ─────────────────────────

  /// 分支列表。
  Future<List<GhBranch>> branches(
    String fullName, {
    int perPage = 100,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/repos/$fullName/branches',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET /repos/$fullName/branches',
    );
    return list.map(GhBranch.fromJson).toList();
  }

  /// 创建分支（基于 [fromSha] 或 [fromBranch]）。
  ///
  /// 两者都没给时，以**仓库的实际默认分支**为起点（拿不到就明确报错——
  /// 绝不猜 `main`：默认分支是 `master` 的仓库会因猜测而失败）。
  Future<void> createBranch(
    String fullName, {
    required String name,
    String? fromSha,
    String? fromBranch,
  }) async {
    var sha = fromSha;
    var source = fromBranch ?? '';
    if (sha == null) {
      if (source.isEmpty) {
        source = await _defaultBranchOf(fullName);
      }
      if (source.isEmpty) {
        throw GhAuthException(
          '无法确定起点分支（仓库详情未返回 default_branch），请显式指定 fromBranch / fromSha',
        );
      }
      final found = await _resolveBranchSha(fullName, source);
      if (found.isEmpty) {
        throw GhAuthException(
          '找不到分支「$source」（或分支数超过安全查找上限），无法创建「$name」',
        );
      }
      sha = found;
    }
    if (sha.isEmpty) {
      throw GhAuthException('起点 sha 为空，无法创建「$name」');
    }
    await client.send(GhRequest(
      path: '/repos/$fullName/git/refs',
      method: NetMethod.post,
      body: <String, Object?>{
        'ref': 'refs/heads/$name',
        'sha': sha,
      },
      label: 'POST /repos/$fullName/git/refs',
    ));
  }

  /// 在分支列表中查找某分支的顶端 sha（**跨页**，安全上限 3 页）。
  ///
  /// 旧实现只看第一页（100 条）：分支超过 100 个的仓库会"找不到"——
  /// 分支明明存在却报错。返回空串表示未找到。
  Future<String> _resolveBranchSha(String fullName, String branchName) async {
    const int pageSize = 100;
    for (var page = 1; page <= 3; page++) {
      final list = await branches(fullName, perPage: pageSize, page: page);
      for (final branch in list) {
        if (branch.name == branchName) {
          return branch.sha;
        }
      }
      if (list.length < pageSize) {
        break; // 已是最后一页
      }
    }
    return '';
  }

  /// 重命名分支。
  Future<void> renameBranch(
    String fullName,
    String from,
    String to,
  ) =>
      client
          .send(GhRequest(
            path: '/repos/$fullName/branches/$from/rename',
            method: NetMethod.post,
            body: <String, Object?>{'new_name': to},
            label: 'POST branch rename',
          ))
          .then((_) {});

  /// 删除分支。
  Future<void> deleteBranch(String fullName, String name) => client
      .send(GhRequest(
        path: '/repos/$fullName/git/refs/heads/$name',
        method: NetMethod.delete,
        label: 'DELETE refs/heads/$name',
      ))
      .then((_) {});

  // ───────────────────────── 内容与树 ─────────────────────────

  /// 目录树（`recursive=1`）。
  ///
  /// 返回的 [GhTree.truncated] 为真时表示**结果不完整**，调用方必须处理。
  Future<GhTree> tree(
    String fullName, {
    String? branch,
    bool recursive = true,
  }) async {
    final ref = (branch == null || branch.isEmpty)
        ? await _defaultBranchOf(fullName)
        : branch;
    if (ref.isEmpty) {
      throw GhAuthException(
        '无法确定 $fullName 的默认分支（仓库详情未返回 default_branch），请显式指定分支',
      );
    }
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/git/trees/$ref',
      query: recursive
          ? <String, String>{'recursive': '1'}
          : const <String, String>{},
      label: 'GET tree($ref)',
    ));
    return GhTree.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  /// 读取内容（文件或目录）。
  ///
  /// 绑定缓存后**优先走读穿透缓存**（短 TTL + 完整性校验）；
  /// 缓存异常一律落回网络，绝不让缓存影响"能不能读到"。
  /// [refresh] 为真时绕过本地缓存，直接回源并刷新。
  Future<GhContent?> content(
    String fullName,
    String path, {
    String? branch,
    bool refresh = false,
  }) async {
    final CacheKey? key = await _cacheKeyFor(fullName, path, branch);
    if (key != null) {
      try {
        final CacheEntry? entry =
            await _cache!.read(key, refresh: refresh, maxAge: _contentMaxAge);
        if (entry == null) {
          return null;
        }
        if (entry.sha.startsWith(_dirShaPrefix)) {
          // 目录：`content()` 只回答"它是目录"，条目由 listDirectory 解析。
          return GhContent(
            path: path,
            sha: '',
            isDirectory: true,
            raw: const <String, dynamic>{},
          );
        }
        return GhContent(
          path: path,
          sha: entry.sha,
          // 字节数而非 UTF-16 code unit 数：网络路径用的是 GitHub 的
          // 真实 size，缓存路径不能自己编一个（含 CJK 时明显偏小，
          // 同一文件两次显示不同大小）。
          size: utf8.encode(entry.content).length,
          text: entry.content,
          raw: const <String, dynamic>{},
        );
      } catch (_) {
        // 缓存键非法 / 远端未绑定 / 完整性校验失败：落回网络。
        return _contentNetwork(fullName, path, branch: branch);
      }
    }
    return _contentNetwork(fullName, path, branch: branch);
  }

  Future<GhContent?> _contentNetwork(
    String fullName,
    String path, {
    String? branch,
  }) async {
    try {
      final object = await client.getObject(
        '/repos/$fullName/contents/${_ghPath(path)}',
        query: <String, String>{
          if (branch != null && branch.isNotEmpty) 'ref': branch,
        },
        label: 'GET contents/$path',
      );
      if (object == null) {
        return null;
      }
      // 目录返回数组，这里只取条目信息。
      if (object.containsKey('__list')) {
        return null;
      }
      return GhContent.fromJson(object);
    } on GhNotFoundException {
      return null;
    } on GhAuthException catch (error) {
      // 目录 / 空仓库 / 不存在 ⇒ 都当作"读不到"，不是失败。
      if (_isAbsentStatus(error.statusCode)) {
        return null;
      }
      rethrow;
    }
  }

  /// 列出目录条目。
  ///
  /// 绑定缓存后优先走读穿透缓存（目录列表 TTL 1 分钟，显式 [refresh] 绕过）。
  /// 这是"该加缓存的地方"：目录浏览是最高频、最重复的读取。
  Future<List<GhContent>> listDirectory(
    String fullName,
    String path, {
    String? branch,
    bool refresh = false,
  }) async {
    final CacheKey? key = await _cacheKeyFor(fullName, path, branch);
    if (key != null) {
      try {
        final CacheEntry? entry =
            await _cache!.read(key, refresh: refresh, maxAge: _dirMaxAge);
        if (entry != null && entry.sha.startsWith(_dirShaPrefix)) {
          final Object? decoded = jsonDecode(entry.content);
          if (decoded is List) {
            return decoded
                .whereType<Map<Object?, Object?>>()
                .map((Map<Object?, Object?> m) =>
                    GhContent.fromJson(Map<String, dynamic>.from(m)))
                .toList();
          }
        }
      } catch (_) {
        // 缓存异常：落回网络。
        return _listDirectoryNetwork(fullName, path, branch: branch);
      }
    }
    return _listDirectoryNetwork(fullName, path, branch: branch);
  }

  Future<List<GhContent>> _listDirectoryNetwork(
    String fullName,
    String path, {
    String? branch,
  }) async {
    try {
      final response = await client.send(GhRequest(
        path: '/repos/$fullName/contents/${_ghPath(path)}',
        query: <String, String>{
          if (branch != null && branch.isNotEmpty) 'ref': branch,
        },
        label: 'GET contents/$path',
      ));
      return response.jsonAsList.map(GhContent.fromJson).toList();
    } on GhNotFoundException {
      return const <GhContent>[];
    } on GhAuthException catch (error) {
      // 空仓库（409 "Git Repository is empty."）⇒ 空目录，不是失败。
      if (_isAbsentStatus(error.statusCode)) {
        return const <GhContent>[];
      }
      rethrow;
    }
  }

  /// 读取大文件（>1 MB 时 Contents API 会省略内容，必须走 Blobs）。
  Future<String?> blobText(
    String fullName,
    String sha, {
    String encoding = 'base64',
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/git/blobs/$sha',
      label: 'GET blobs/$sha',
    ));
    final object = response.jsonObject;
    if (object == null) {
      return null;
    }
    final content = GhJson.str(object, 'content');
    return GhContent.decodeContent(
        content, GhJson.str(object, 'encoding', fallback: encoding));
  }

  /// 写入内容（**带基线 sha → 乐观锁**）。
  Future<GhContent> putContent(
    String fullName,
    String path, {
    required String content,
    required String message,
    String? baseSha,
    String? branch,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/contents/${_ghPath(path)}',
      method: NetMethod.put,
      body: <String, Object?>{
        'message': message,
        'content': base64Encode(utf8.encode(content)),
        if (baseSha != null) 'sha': baseSha,
        if (branch != null) 'branch': branch,
      },
      label: 'PUT contents/$path',
      // 关键：让 409/422 变成结构化的远端冲突，交给 D2/D3 处理。
      conflictsAsRemoteConflict: true,
    ));
    final object = response.jsonObject ?? const <String, dynamic>{};
    final contentPart = object['content'];
    final written = GhContent.fromJson(
      contentPart is Map
          ? Map<String, dynamic>.from(contentPart)
          : const <String, dynamic>{},
    );
    // ★ 直接写成功后同步失效底座缓存条目：引擎写路径（_writeLocked）自带
    //   D5 失效，但这条裸写路径不经过引擎——不清的话 30s TTL 内读到旧内容
    //   （"改完再看显示旧值"）。
    final CacheKey? key = await _cacheKeyFor(fullName, path, branch);
    if (key != null) {
      try {
        await _cache!.invalidate(key);
      } catch (error) {
        // 失效是 best-effort：失败只留痕，不改变"写已成功"的事实。
        OgLLogFile.line(
          'GH',
          '写后缓存失效失败（$fullName/$path）：$error',
          level: 'WARN',
        );
      }
    }
    return written;
  }

  /// 按基线 SHA **加锁**写入（走底座 D1–D7 一致性引擎）。
  ///
  /// 与 [putContent] 的区别：
  /// - [putContent] 是**裸网络写**（供 [CacheRemote.write] 使用，不做本地锁）；
  /// - 本方法把写交给 [RepositoryCache]：缺基线拒绝（D1）、基线过期拒绝并
  ///   给出**三方差异**（D2/D10）、危险/强制需二次确认（D7）、写后回读校验
  ///   （D5）、失败进入待同步队列（D8）。
  ///
  /// **永不抛**：失败以 [WriteOutcome.conflict] 返回，供 UI 呈现并可重试。
  Future<GhWriteResult> putContentLocked(
    String fullName,
    String path, {
    required String content,
    required String message,
    required String baseSha,
    String? branch,
    bool force = false,
    bool confirmed = false,
    String Function(String latestContent, String myContent)? rebase,
  }) async {
    final RepositoryCache? cache = _cache;
    final CacheKey? key = await _cacheKeyFor(fullName, path, branch);
    if (cache == null || key == null) {
      // 未绑定缓存 / 无法构造合法键：退化为裸写。
      // 仍带 baseSha —— **服务端 GitHub 会用它做乐观锁**，误覆盖依然被拦。
      //
      // ★ force/confirmed 不能被丢弃：用户在冲突对话框确认"强制覆盖"后，
      //   这条路径若原样带旧 baseSha，服务端 409 会以异常逃逸（UI 无
      //   冲突对话框可走，重试永远失败）。处理：
      //   1) force=true → 先取远端当前 sha，用**当下最新值**做基线
      //      （引擎路径的语义正是"以刚读到的远端版本为期望"）；
      //   2) 409/422 异常折成结构化 staleSha，UI 照常弹冲突对话框。
      String? expected = baseSha;
      if (force) {
        final GhContent? latest =
            await _contentNetwork(fullName, path, branch: branch);
        if (latest == null) {
          return GhWriteResult(
            ok: false,
            conflict: GhWriteConflict.notFound,
            detail: '强制覆盖失败：远端目标不存在（可能已被删除）',
            baseSha: baseSha,
            localContent: content,
          );
        }
        expected = latest.sha;
      }
      try {
        final GhContent written = await putContent(
          fullName,
          path,
          content: content,
          message: message,
          baseSha: expected,
          branch: branch,
        );
        return GhWriteResult(
          ok: true,
          conflict: GhWriteConflict.none,
          sha: written.sha,
          baseSha: expected,
        );
      } on RemoteConflictException catch (error) {
        // 结构化折返：UI 依赖 canForceOverwrite / remoteContent 呈现冲突。
        return GhWriteResult(
          ok: false,
          conflict: GhWriteConflict.staleSha,
          sha: error.currentSha,
          baseSha: baseSha,
          detail: '远端版本已变化（HTTP ${error.statusCode}）',
          localContent: content,
        );
      }
    }
    final WriteOutcome outcome = await cache.write(
      WriteIntent(
        key: key,
        content: content,
        message: message,
        baseSha: baseSha,
        force: force,
        rebase: rebase,
      ),
      confirmed: confirmed,
    );
    return GhWriteResult(
      ok: outcome.ok,
      conflict: _toGhConflict(outcome.conflict),
      sha: outcome.sha,
      baseSha: outcome.baseSha,
      detail: outcome.detail,
      remoteContent: outcome.threeWay?.remote,
      baseContent: outcome.threeWay?.base,
      localContent: outcome.threeWay?.local ?? content,
    );
  }

  /// 把底座冲突分类投影成领域类型（保持分层：展示层不认识 base）。
  static GhWriteConflict _toGhConflict(WriteConflict conflict) {
    switch (conflict) {
      case WriteConflict.none:
        return GhWriteConflict.none;
      case WriteConflict.requiresRead:
        return GhWriteConflict.requiresRead;
      case WriteConflict.staleSha:
        return GhWriteConflict.staleSha;
      case WriteConflict.needsConfirmation:
        return GhWriteConflict.needsConfirmation;
      case WriteConflict.notFound:
        return GhWriteConflict.notFound;
      case WriteConflict.forbidden:
        return GhWriteConflict.forbidden;
      case WriteConflict.server:
        return GhWriteConflict.server;
      case WriteConflict.verificationFailed:
        return GhWriteConflict.verificationFailed;
    }
  }

  /// 按基线 SHA **加锁**删除（走 D1/D2/D7）。
  ///
  /// 与 [deleteContent] 的区别：本方法在删除前确认基线未过期（D2），
  /// 并要求二次确认（D7）；基线过期时**不删除**，如实返回冲突。
  Future<GhWriteResult> deleteContentLocked(
    String fullName,
    String path, {
    required String message,
    required String baseSha,
    String? branch,
    bool confirmed = false,
  }) async {
    final RepositoryCache? cache = _cache;
    final CacheKey? key = await _cacheKeyFor(fullName, path, branch);
    if (cache == null || key == null) {
      await deleteContent(
        fullName,
        path,
        message: message,
        baseSha: baseSha,
        branch: branch,
      );
      return GhWriteResult(
        ok: true,
        conflict: GhWriteConflict.none,
        baseSha: baseSha,
      );
    }
    final WriteOutcome outcome = await cache.delete(
      key,
      message: message,
      baseSha: baseSha,
      confirmed: confirmed,
    );
    return GhWriteResult(
      ok: outcome.ok,
      conflict: _toGhConflict(outcome.conflict),
      sha: outcome.sha,
      baseSha: outcome.baseSha,
      detail: outcome.detail,
      remoteContent: outcome.threeWay?.remote,
      baseContent: outcome.threeWay?.base,
      localContent: outcome.threeWay?.local,
    );
  }

  /// 删除内容（**危险操作**）。
  Future<void> deleteContent(
    String fullName,
    String path, {
    required String message,
    required String baseSha,
    String? branch,
  }) =>
      client
          .send(GhRequest(
            path: '/repos/$fullName/contents/${_ghPath(path)}',
            method: NetMethod.delete,
            body: <String, Object?>{
              'message': message,
              'sha': baseSha,
              if (branch != null) 'branch': branch,
            },
            label: 'DELETE contents/$path',
            conflictsAsRemoteConflict: true,
          ))
          .then((_) {});

  /// 分支顶端提交 SHA（公开只读）。
  ///
  /// 供**写入方**在 [commitFiles] 前解析基线：读与写之间若有人推进了分支，
  /// `expectedHeadSha` 不匹配会以 409 拒绝，而不是盲目再落一次提交。
  /// 解析失败返回空串（调用方决定是否降级为不带基线的写，不在此处猜）。
  Future<String> branchHeadSha(String fullName, String branch) =>
      _headShaOf(fullName, branch);

  /// 批量提交（Git Data API：blob → tree → commit → ref，**原子**）。
  ///
  /// 这是"多文件一次提交"的正路：要么全成、要么全不成，
  /// 不会留下半成品状态。
  Future<String> commitFiles(
    String fullName, {
    required String branch,
    required Map<String, String> upserts,
    List<String> deletions = const <String>[],
    required String message,
    String? expectedHeadSha,
  }) async {
    // ① 先校验基线，**再**创建任何 blob。
    // 顺序很重要：若把 blob 建在前面，一旦期望 sha 不匹配就会白建一堆
    // 永远不会被引用的孤儿对象（虽然 GitHub 最终会回收，但没必要）。
    final headSha = await _headShaOf(fullName, branch);
    if (headSha.isEmpty) {
      throw GhAuthException('无法确定分支 $branch 的顶端提交');
    }
    if (expectedHeadSha != null && headSha != expectedHeadSha) {
      throw RemoteConflictException(
        statusCode: 409,
        currentSha: headSha,
        message: '分支已前进，拒绝批量提交',
      );
    }
    // ② 基线 tree 也在建 blob 之前读出来：**先把所有读做完，再开始写**。
    // 这样一旦中途失败，留在远端的至少有意义的记录，而不是一堆孤儿 blob。
    final baseTree = await _treeShaOfCommit(fullName, headSha);

    final entries = <Map<String, Object?>>[];

    for (final MapEntry<String, String> entry in upserts.entries) {
      final blob = await client.send(GhRequest(
        path: '/repos/$fullName/git/blobs',
        method: NetMethod.post,
        body: <String, Object?>{
          'content': base64Encode(utf8.encode(entry.value)),
          'encoding': 'base64',
        },
        label: 'POST blobs(${entry.key})',
      ));
      final blobSha = GhJson.str(
        blob.jsonObject ?? const <String, dynamic>{},
        'sha',
      );
      entries.add(<String, Object?>{
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': blobSha,
      });
    }
    for (final path in deletions) {
      entries.add(<String, Object?>{
        'path': path,
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      });
    }
    if (entries.isEmpty) {
      // 这是调用方的参数错误（既没有 upserts 也没有 deletions），
      // 用 ArgumentError 而不是"认证异常"——类型要如实反映问题性质。
      throw ArgumentError('批量提交内容为空（upserts 与 deletions 至少需要一个）');
    }

    final tree = await client.send(GhRequest(
      path: '/repos/$fullName/git/trees',
      method: NetMethod.post,
      body: <String, Object?>{
        'base_tree': baseTree,
        'tree': entries,
      },
      label: 'POST trees',
    ));
    final treeSha =
        GhJson.str(tree.jsonObject ?? const <String, dynamic>{}, 'sha');

    final commit = await client.send(GhRequest(
      path: '/repos/$fullName/git/commits',
      method: NetMethod.post,
      body: <String, Object?>{
        'message': message,
        'tree': treeSha,
        'parents': <String>[headSha],
      },
      label: 'POST commits',
    ));
    final commitSha =
        GhJson.str(commit.jsonObject ?? const <String, dynamic>{}, 'sha');

    await client.send(GhRequest(
      path: '/repos/$fullName/git/refs/heads/$branch',
      method: NetMethod.patch,
      body: <String, Object?>{
        'sha': commitSha,
        'force': false,
      },
      label: 'PATCH refs/heads/$branch',
      // 引用移动失败同样是冲突。
      conflictsAsRemoteConflict: true,
    ));
    return commitSha;
  }

  // ───────────────────────── 提交历史 ─────────────────────────

  /// 提交历史。
  Future<List<GhCommit>> commits(
    String fullName, {
    String? path,
    String? branch,
    int perPage = 50,
    int page = 1,
  }) async {
    try {
      final list = await client.getList(
        '/repos/$fullName/commits',
        query: <String, String>{
          'per_page': '$perPage',
          'page': '$page',
          if (path != null && path.isNotEmpty) 'path': path,
          if (branch != null && branch.isNotEmpty) 'sha': branch,
        },
        label: 'GET commits',
      );
      return list.map(GhCommit.fromJson).toList();
    } on GhNotFoundException {
      return const <GhCommit>[];
    } on GhAuthException catch (error) {
      // 空仓库 / 分支不存在 ⇒ "没有提交"，不是失败。
      if (_isAbsentStatus(error.statusCode)) {
        return const <GhCommit>[];
      }
      rethrow;
    }
  }

  /// 两个引用之间的差异（返回 `files` 数组）。
  Future<List<Map<String, dynamic>>> compare(
    String fullName,
    String base,
    String head,
  ) async {
    final object = await client.getObject(
      '/repos/$fullName/compare/$base...$head',
      label: 'GET compare',
    );
    final files = object?['files'];
    if (files is! List) {
      return const <Map<String, dynamic>>[];
    }
    return files
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  // ───────────────────────── Releases ─────────────────────────

  /// 发布列表。
  Future<List<GhRelease>> releases(
    String fullName, {
    int perPage = 30,
    int page = 1,
  }) async {
    final list = await client.getList(
      '/repos/$fullName/releases',
      query: <String, String>{'per_page': '$perPage', 'page': '$page'},
      label: 'GET releases',
    );
    return list.map(GhRelease.fromJson).toList();
  }

  /// 创建发布。
  Future<GhRelease> createRelease(
    String fullName, {
    required String tagName,
    String? name,
    String? body,
    bool prerelease = false,
    bool draft = false,
    String? targetCommitish,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/releases',
      method: NetMethod.post,
      body: <String, Object?>{
        'tag_name': tagName,
        if (name != null) 'name': name,
        if (body != null) 'body': body,
        'prerelease': prerelease,
        'draft': draft,
        if (targetCommitish != null) 'target_commitish': targetCommitish,
      },
      label: 'POST releases',
    ));
    return GhRelease.fromJson(
      response.jsonObject ?? const <String, dynamic>{},
    );
  }

  /// 删除发布。
  Future<void> deleteRelease(String fullName, int releaseId) => client
      .send(GhRequest(
        path: '/repos/$fullName/releases/$releaseId',
        method: NetMethod.delete,
        label: 'DELETE release($releaseId)',
      ))
      .then((_) {});

  /// 更新发布（标题 / 说明 / 草稿 / 预发布 / 标签）。
  Future<GhRelease> updateRelease(
    String fullName,
    int releaseId, {
    String? tagName,
    String? name,
    String? body,
    bool? draft,
    bool? prerelease,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/releases/$releaseId',
      method: NetMethod.patch,
      body: <String, Object?>{
        if (tagName != null) 'tag_name': tagName,
        if (name != null) 'name': name,
        if (body != null) 'body': body,
        if (draft != null) 'draft': draft,
        if (prerelease != null) 'prerelease': prerelease,
      },
      label: 'PATCH release($releaseId)',
    ));
    return GhRelease.fromJson(response.jsonObject ?? const <String, dynamic>{});
  }

  // ───────────────────────── 搜索 ─────────────────────────

  /// 搜仓库。
  Future<List<GhRepo>> searchRepos(
    String query, {
    int perPage = 30,
    int page = 1,
  }) async {
    final object = await client.getObject(
      '/search/repositories',
      query: <String, String>{
        'q': query,
        'per_page': '$perPage',
        'page': '$page',
      },
      label: 'GET /search/repositories',
    );
    final items = object?['items'];
    if (items is! List) {
      return const <GhRepo>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) => GhRepo.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  /// 搜代码（**服务端**，消耗 Search 配额）。
  ///
  /// **必须带 `text-match` 媒体类型**：GitHub 只在 Accept 头声明后才会
  /// 返回 `text_matches`（命中上下文）——没有它，搜索结果只能显示路径，
  /// "命中上下文"功能形同虚设。
  Future<List<Map<String, dynamic>>> searchCode(
    String query, {
    int perPage = 30,
    int page = 1,
  }) async {
    final response = await client.send(GhRequest(
      path: '/search/code',
      query: <String, String>{
        'q': query,
        'per_page': '$perPage',
        'page': '$page',
      },
      headers: const <String, String>{
        'accept': 'application/vnd.github.text-match+json',
      },
      label: 'GET /search/code',
    ));
    final object = response.jsonObject;
    final items = object?['items'];
    if (items is! List) {
      return const <Map<String, dynamic>>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  // ───────────────────────── Pages ─────────────────────────

  /// 查询 Pages 状态（未启用返回 `null`）。
  Future<Map<String, dynamic>?> pagesInfo(String fullName) async {
    try {
      return await client.getObject(
        '/repos/$fullName/pages',
        label: 'GET pages',
      );
    } on GhNotFoundException {
      return null;
    }
  }

  /// 启用 Pages。
  ///
  /// [branch] 为空（或未给）时使用仓库的**实际默认分支**——绝不猜 `main`。
  Future<void> enablePages(
    String fullName, {
    String? branch,
    String path = '/',
  }) async {
    final target = (branch == null || branch.isEmpty)
        ? await _defaultBranchOf(fullName)
        : branch;
    if (target.isEmpty) {
      throw GhAuthException(
        '无法确定 Pages 的源分支（仓库详情未返回 default_branch），请稍后重试或先补齐仓库信息',
      );
    }
    await client
        .send(GhRequest(
          path: '/repos/$fullName/pages',
          method: NetMethod.post,
          body: <String, Object?>{
            'source': <String, Object?>{'branch': target, 'path': path},
          },
          label: 'POST pages',
        ))
        .then((_) {});
  }

  /// 关闭 Pages。
  Future<void> disablePages(String fullName) => client
      .send(GhRequest(
        path: '/repos/$fullName/pages',
        method: NetMethod.delete,
        label: 'DELETE pages',
      ))
      .then((_) {});

  /// 读 CNAME。
  Future<String?> readCname(String fullName) async {
    final content = await this.content(fullName, 'CNAME');
    return content?.text?.trim();
  }

  /// 写 CNAME（自定义域名）。
  Future<void> writeCname(
    String fullName,
    String domain, {
    required String baseSha,
  }) =>
      putContent(
        fullName,
        'CNAME',
        content: '$domain\n',
        message: 'chore: configure custom domain',
        baseSha: baseSha,
      );

  // ───────────────────────── Issues / PR / Gist / Actions ─────────────────────────

  /// Issues 列表（不含 PR）。
  Future<List<Map<String, dynamic>>> issues(
    String fullName, {
    String state = 'open',
    int perPage = 30,
    int page = 1,
  }) =>
      client
          .getList(
            '/repos/$fullName/issues',
            query: <String, String>{
              'state': state,
              'per_page': '$perPage',
              'page': '$page',
              'filter': 'all',
            },
            label: 'GET issues',
          )
          .then((List<Map<String, dynamic>> items) => items
              .where((Map<String, dynamic> item) =>
                  !item.containsKey('pull_request'))
              .toList());

  /// 新建 Issue。
  Future<Map<String, dynamic>> createIssue(
    String fullName, {
    required String title,
    String? body,
    List<String> labels = const <String>[],
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/issues',
      method: NetMethod.post,
      body: <String, Object?>{
        'title': title,
        if (body != null) 'body': body,
        if (labels.isNotEmpty) 'labels': labels,
      },
      label: 'POST issues',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// 更新 Issue（关闭 / 编辑）。
  Future<Map<String, dynamic>> updateIssue(
    String fullName,
    int number, {
    String? state,
    String? title,
    String? body,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/issues/$number',
      method: NetMethod.patch,
      body: <String, Object?>{
        if (state != null) 'state': state,
        if (title != null) 'title': title,
        if (body != null) 'body': body,
      },
      label: 'PATCH issues/$number',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// Issue 评论。
  Future<List<Map<String, dynamic>>> issueComments(
    String fullName,
    int number,
  ) =>
      client.getList(
        '/repos/$fullName/issues/$number/comments',
        label: 'GET issue comments',
      );

  /// 发表评论（Issue 与 PR **共用**同一端点）。
  ///
  /// GitHub 的 PR 也走 `issues/{number}/comments`，因此本方法对二者通用。
  Future<Map<String, dynamic>> createIssueComment(
    String fullName,
    int number, {
    required String body,
  }) async {
    final response = await client.send(GhRequest(
      path: '/repos/$fullName/issues/$number/comments',
      method: NetMethod.post,
      body: <String, Object?>{'body': body},
      label: 'POST issue comment',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// PR 列表。
  Future<List<Map<String, dynamic>>> pulls(
    String fullName, {
    String state = 'open',
    int perPage = 30,
    int page = 1,
  }) =>
      client.getList(
        '/repos/$fullName/pulls',
        query: <String, String>{
          'state': state,
          'per_page': '$perPage',
          'page': '$page',
        },
        label: 'GET pulls',
      );

  /// PR 的文件变更。
  Future<List<Map<String, dynamic>>> pullFiles(
    String fullName,
    int number,
  ) =>
      client.getList(
        '/repos/$fullName/pulls/$number/files',
        label: 'GET pull files',
      );

  /// Gist 列表。
  Future<List<Map<String, dynamic>>> gists({int perPage = 30}) =>
      client.getList(
        '/gists',
        query: <String, String>{'per_page': '$perPage'},
        label: 'GET gists',
      );

  /// 单个 Gist（含文件内容；大文件可能被服务端截断）。
  Future<Map<String, dynamic>?> gist(String id) =>
      client.getObject('/gists/$id', label: 'GET gists/$id');

  /// 新建 Gist（`files`: 文件名 → 内容）。
  Future<Map<String, dynamic>> createGist({
    required Map<String, String> files,
    String? description,
    bool public = false,
  }) async {
    final response = await client.send(GhRequest(
      path: '/gists',
      method: NetMethod.post,
      body: <String, Object?>{
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'public': public,
        'files': <String, Object?>{
          for (final MapEntry<String, String> e in files.entries)
            e.key: <String, Object?>{'content': e.value},
        },
      },
      label: 'POST gists',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// 更新 Gist。
  ///
  /// `files` 中值为 `null` 表示**删除该文件**（GitHub 的语义）。
  Future<Map<String, dynamic>> updateGist(
    String id, {
    String? description,
    Map<String, String?>? files,
  }) async {
    final response = await client.send(GhRequest(
      path: '/gists/$id',
      method: NetMethod.patch,
      body: <String, Object?>{
        if (description != null) 'description': description,
        if (files != null)
          'files': <String, Object?>{
            for (final MapEntry<String, String?> e in files.entries)
              e.key: e.value == null
                  ? null
                  : <String, Object?>{'content': e.value},
          },
      },
      label: 'PATCH gists/$id',
    ));
    return response.jsonObject ?? const <String, dynamic>{};
  }

  /// 删除 Gist。
  Future<void> deleteGist(String id) => client.send(GhRequest(
        path: '/gists/$id',
        method: NetMethod.delete,
        label: 'DELETE gists/$id',
      ));

  /// 读取任意纯文本 URL（Gist `raw_url`、原始文件等）。
  Future<String> rawText(String url) async {
    final response = await client.send(
      GhRequest(path: url, label: 'GET raw'),
    );
    return response.body;
  }

  /// Actions 运行列表。
  Future<List<Map<String, dynamic>>> workflowRuns(
    String fullName, {
    String? branch,
    int perPage = 20,
    int page = 1,
  }) async {
    final object = await client.getObject(
      '/repos/$fullName/actions/runs',
      query: <String, String>{
        'per_page': '$perPage',
        'page': '$page',
        if (branch != null && branch.isNotEmpty) 'branch': branch,
      },
      label: 'GET actions/runs',
    );
    final runs = object?['workflow_runs'];
    if (runs is! List) {
      return const <Map<String, dynamic>>[];
    }
    return runs
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// 仓库工作流列表（用于"手动触发"选择目标）。
  Future<List<Map<String, dynamic>>> workflows(String fullName) async {
    final object = await client.getObject(
      '/repos/$fullName/actions/workflows',
      query: const <String, String>{'per_page': '100'},
      label: 'GET actions/workflows',
    );
    final items = object?['workflows'];
    if (items is! List) {
      return const <Map<String, dynamic>>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// 读取仓库内一个文件的**原始文本**（用于解析工作流 YAML）。
  ///
  /// 走内容接口（`contents`），失败返回 `null`（调用方据此提示，不静默）。
  Future<String?> rawFileText(
    String fullName,
    String path, {
    String? branch,
  }) async {
    try {
      final GhContent? content =
          await this.content(fullName, path, branch: branch);
      return content?.text;
    } on GhNotFoundException {
      return null;
    }
  }

  /// 手动触发工作流（`workflow_dispatch`）。
  ///
  /// [workflowIdOrFile] 可用工作流数字 ID，或文件名（如 `build.yml`）。
  /// GitHub 对**未声明 `workflow_dispatch`** 的工作流会返回 422。
  Future<void> dispatchWorkflow(
    String fullName, {
    required String workflowIdOrFile,
    required String ref,
    Map<String, String> inputs = const <String, String>{},
  }) =>
      client
          .send(GhRequest(
            path:
                '/repos/$fullName/actions/workflows/$workflowIdOrFile/dispatches',
            method: NetMethod.post,
            body: <String, Object?>{
              'ref': ref,
              if (inputs.isNotEmpty) 'inputs': inputs,
            },
            label: 'POST actions/workflows/$workflowIdOrFile/dispatches',
          ))
          .then((_) {});

  /// 单个 Actions 运行详情。
  Future<Map<String, dynamic>?> workflowRun(String fullName, int runId) =>
      client.getObject(
        '/repos/$fullName/actions/runs/$runId',
        label: 'GET actions/runs/$runId',
      );

  /// Actions 运行的作业列表（含步骤）。
  Future<List<Map<String, dynamic>>> workflowRunJobs(
    String fullName,
    int runId,
  ) async {
    final object = await client.getObject(
      '/repos/$fullName/actions/runs/$runId/jobs',
      query: const <String, String>{'per_page': '50'},
      label: 'GET actions/runs/$runId/jobs',
    );
    final jobs = object?['jobs'];
    if (jobs is! List) {
      return const <Map<String, dynamic>>[];
    }
    return jobs
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// 一次运行的日志压缩包地址（302 → zip；需带令牌请求）。
  ///
  /// 由域层服务 `IxActionLogs` 负责带令牌下载并解压（见 `domain/ix/ix_action_logs.dart`）。
  String workflowRunLogsUrl(String fullName, int runId) =>
      '${client.baseUrl}/repos/$fullName/actions/runs/$runId/logs';

  /// 默认 API 根（供域层服务拼日志地址）。
  String get apiBaseUrl => client.baseUrl;

  /// 一次运行的产物（artifacts）列表。
  Future<List<Map<String, dynamic>>> workflowRunArtifacts(
    String fullName,
    int runId,
  ) async {
    final object = await client.getObject(
      '/repos/$fullName/actions/runs/$runId/artifacts',
      query: const <String, String>{'per_page': '100'},
      label: 'GET actions/runs/$runId/artifacts',
    );
    final items = object?['artifacts'];
    if (items is! List) {
      return const <Map<String, dynamic>>[];
    }
    return items
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// 单个产物的下载地址（zip）。
  String artifactDownloadUrl(String fullName, int artifactId) =>
      '${client.baseUrl}/repos/$fullName/actions/artifacts/$artifactId/zip';

  /// 重新运行一次工作流（**写操作**）。
  Future<void> rerunWorkflowRun(String fullName, int runId) =>
      client.send(GhRequest(
        path: '/repos/$fullName/actions/runs/$runId/rerun',
        method: NetMethod.post,
        label: 'POST actions/runs/$runId/rerun',
      ));

  /// 取消一次运行中的工作流（**写操作**）。
  Future<void> cancelWorkflowRun(String fullName, int runId) =>
      client.send(GhRequest(
        path: '/repos/$fullName/actions/runs/$runId/cancel',
        method: NetMethod.post,
        label: 'POST actions/runs/$runId/cancel',
      ));

  /// 标签列表。
  Future<List<Map<String, dynamic>>> labels(String fullName) =>
      client.getList('/repos/$fullName/labels', label: 'GET labels');

  /// README（Markdown 原文）。
  ///
  /// 直接走 GitHub 的 `GET /repos/{o}/{r}/readme`：一次请求就能拿到仓库
  /// 实际的 README（含 `README.rst` 等），**不需要先探测 `README.md`**——
  /// 后者会让"没有 README 的仓库"每次白打一次 404。
  Future<String?> readme(String fullName) async {
    try {
      final object = await client.getObject(
        '/repos/$fullName/readme',
        label: 'GET readme',
      );
      final encoded =
          GhJson.str(object ?? const <String, dynamic>{}, 'content');
      return GhContent.decodeContent(
        encoded,
        GhJson.str(
          object ?? const <String, dynamic>{},
          'encoding',
          fallback: 'base64',
        ),
      );
    } on GhNotFoundException {
      return null;
    }
  }

  // ───────────────────────── ★ CacheRemote 实现 ─────────────────────────

  /// 读取远端文档（给一致性引擎用）。
  ///
  /// 大文件（>1 MB）会经 Blobs API 补齐内容——**绝不返回"空内容"当成功**。
  @override
  Future<RemoteDocument?> read(CacheKey key) async {
    final repo = key.scope.repo;
    final branch = key.scope.branch;
    final String path = key.path;
    String body;
    try {
      final response = await client.send(GhRequest(
        path: '/repos/$repo/contents/${_ghPath(path)}',
        query: <String, String>{
          if (branch.isNotEmpty) 'ref': branch,
        },
        label: 'GET contents/$path',
      ));
      body = response.body;
    } on GhNotFoundException {
      return null;
    } on GhAuthException catch (error) {
      if (_isAbsentStatus(error.statusCode)) {
        return null;
      }
      rethrow;
    }

    // 目录：Contents API 返回数组 → 用 `dir:` 标记，把整份列表 JSON 缓存起来。
    final String probe = body.trimLeft();
    if (probe.startsWith('[')) {
      final String marker = '$_dirShaPrefix${sha1.convert(utf8.encode(body))}';
      return RemoteDocument(content: body, sha: marker);
    }

    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      return null;
    }
    final parsed = GhContent.fromJson(Map<String, dynamic>.from(decoded));
    var text = parsed.text;
    // Contents API 对 >1 MB 的文件会省略 content（且不报错），
    // 这里显式改走 Blobs API —— 否则会"静默拿到空内容"。
    final oversized = parsed.size > _contentSizeLimit;
    if (text == null && (parsed.isTooLarge || oversized)) {
      try {
        text = await blobText(repo, parsed.sha);
      } on GhNotFoundException {
        text = null; // Blobs 也拿不到：如实当作读不到，不编内容。
      }
    }
    if (text == null) {
      // ★ 空文件（GitHub 返回 content==""、size==0）是真实存在的文件：
      //   内容就是空串——必须与"拿不到内容"区分，否则写链路把它当
      //   "远端不存在"，空文件的合法保存走错分支。
      if (!parsed.isDirectory && parsed.size == 0 && parsed.sha.isNotEmpty) {
        text = '';
      } else {
        // 真拿不到：**不返回空串当成功**——空串会被写回远端，是数据事故。
        return null;
      }
    }
    return RemoteDocument(content: text, sha: parsed.sha);
  }

  /// 按期望 sha 写入（给一致性引擎用）。
  ///
  /// 409/422 会被翻译成 [RemoteConflictException]，交由 D2/D3 处理。
  @override
  Future<RemoteDocument> write(
    CacheKey key,
    String content, {
    required String message,
    String? expectedSha,
  }) async {
    final repo = key.scope.repo;
    final branch = key.scope.branch;
    final written = await putContent(
      repo,
      key.path,
      content: content,
      message: message,
      baseSha: expectedSha,
      branch: branch,
    );
    return RemoteDocument(content: content, sha: written.sha);
  }

  /// 按期望 sha 删除（给一致性引擎用）。
  @override
  Future<void> delete(
    CacheKey key, {
    required String message,
    required String expectedSha,
  }) =>
      deleteContent(
        key.scope.repo,
        key.path,
        message: message,
        baseSha: expectedSha,
        branch: key.scope.branch,
      );

  // ───────────────────────── 内部辅助 ─────────────────────────

  /// 404 / 409 / 422 在**读**场景里都表示"这里没有东西"
  /// （不存在 / 仓库为空 / 功能未启用）。
  ///
  /// 写场景不走这条：写冲突必须是冲突，不许被当成"没有"。
  static bool _isAbsentStatus(int? statusCode) =>
      statusCode == 404 || statusCode == 409 || statusCode == 422;

  /// 读取仓库的默认分支（带**进程内记忆**）。
  ///
  /// **不猜 `main`**：拿不到就返回空串，由调用方给出明确错误——
  /// 猜错会让默认分支是 `master` 的仓库整条链路 404。
  /// 记忆化是为了不让缓存键构造每次都多打一次 `/repos/{repo}`。
  Future<String> _defaultBranchOf(String fullName) async {
    final String? memo = _defaultBranchMemo[fullName];
    if (memo != null && memo.isNotEmpty) {
      return memo;
    }
    final object = await client.getObject('/repos/$fullName');
    final String branch =
        GhJson.str(object ?? const <String, dynamic>{}, 'default_branch');
    if (branch.isNotEmpty) {
      _defaultBranchMemo[fullName] = branch;
    }
    return branch;
  }

  Future<String> _headShaOf(String fullName, String branch) async {
    try {
      final object = await client.getObject(
        '/repos/$fullName/git/ref/heads/$branch',
      );
      final target = object?['object'];
      if (target is Map) {
        return GhJson.str(Map<String, dynamic>.from(target), 'sha');
      }
    } on GhNotFoundException {
      return '';
    }
    return '';
  }

  Future<String> _treeShaOfCommit(String fullName, String commitSha) async {
    final object = await client.getObject(
      '/repos/$fullName/git/commits/$commitSha',
    );
    final tree = object?['tree'];
    if (tree is Map) {
      return GhJson.str(Map<String, dynamic>.from(tree), 'sha');
    }
    return '';
  }
}
