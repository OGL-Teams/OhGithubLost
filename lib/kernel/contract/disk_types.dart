/// L1 底座级 · 硬盘逻辑：缓存一致性类型（**致命区**）。
///
/// 为什么这套类型值得单独成文件：
/// 对一个代码仓库应用而言，"版本不一致 / 错位覆盖"是**致命错误**——
/// 用户的一行代码可能被另一账号、另一分支、另一路径的旧内容顶掉。
/// 所以作用域必须是**结构化对象**而不是拼接字符串：
/// 结构化 ⇒ 可校验、可比较、可测试；拼接字符串 ⇒ 迟早漏字段。
library;

/// 缓存作用域：`schemaVersion | accountId | repo | branch`。
///
/// 任何一个维度缺位都会导致跨维度串味（错位覆盖），
/// 因此 [isWellFormed] 是硬性门槛：不合法的作用域**不允许**参与缓存。
class CacheScope {
  /// 创建作用域。
  const CacheScope({
    required this.schemaVersion,
    required this.accountId,
    required this.repo,
    required this.branch,
  });

  /// 缓存结构版本（结构变更时必须递增，用于整体失效旧缓存）。
  final int schemaVersion;

  /// 账号标识（多账号隔离的第一道闸）。
  final String accountId;

  /// 仓库全名（`owner/name`）。
  final String repo;

  /// 分支（`main` / `dev` …）。
  final String branch;

  /// 是否合法（四个维度都有效，且不含编码分隔符）。
  ///
  /// 分隔符校验不是洁癖：字段里混入 `|` 会让 [encode] / [parse] 产生歧义，
  /// 而歧义的后果是**作用域漂移**——即错位覆盖。
  bool get isWellFormed =>
      schemaVersion > 0 &&
      accountId.isNotEmpty &&
      repo.isNotEmpty &&
      branch.isNotEmpty &&
      !accountId.contains('|') &&
      !repo.contains('|') &&
      !branch.contains('|');

  /// 编码为可持久化字符串。
  String encode() => '$schemaVersion|$accountId|$repo|$branch';

  /// 从编码字符串解析；不合法时返回 `null`（绝不抛异常、绝不兜底猜测）。
  static CacheScope? parse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 4) {
      return null;
    }
    final version = int.tryParse(parts[0]);
    if (version == null) {
      return null;
    }
    final scope = CacheScope(
      schemaVersion: version,
      accountId: parts[1],
      repo: parts[2],
      branch: parts[3],
    );
    return scope.isWellFormed ? scope : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CacheScope && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => 'CacheScope(${encode()})';
}

/// 缓存键：作用域 + 仓库内路径。
class CacheKey {
  /// 创建键。
  const CacheKey({required this.scope, required this.path});

  /// 作用域。
  final CacheScope scope;

  /// 仓库内 POSIX 路径（相对、不含前导 `/`、不含 `..`）。
  final String path;

  /// 路径是否合法。
  ///
  /// 拒绝三类路径：空、绝对/反斜杠、含 `..` 段。
  /// 最后一条是**安全边界**：缓存落在真实文件系统上，
  /// 未校验的 `..` 会让写入逃出缓存目录。
  bool get isPathWellFormed {
    if (path.isEmpty || path.startsWith('/') || path.contains(r'\')) {
      return false;
    }
    return !path.split('/').contains('..');
  }

  /// 键是否合法（作用域与路径都合法）。
  bool get isWellFormed => scope.isWellFormed && isPathWellFormed;

  /// 编码为可持久化字符串。
  String encode() => '${scope.encode()}|$path';

  /// 从编码字符串反解键；不合法返回 `null`（绝不猜测、绝不兜底）。
  ///
  /// 注意：路径本身可能含 `|`，因此只把**前四段**当作作用域，其余全部还原为路径。
  static CacheKey? decode(String raw) {
    final parts = raw.split('|');
    if (parts.length < 5) {
      return null;
    }
    final scope = CacheScope.parse(parts.sublist(0, 4).join('|'));
    if (scope == null) {
      return null;
    }
    final key = CacheKey(scope: scope, path: parts.sublist(4).join('|'));
    return key.isWellFormed ? key : null;
  }

  @override
  bool operator ==(Object other) =>
      other is CacheKey && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => 'CacheKey(${encode()})';
}

/// 缓存路径非法（不允许进入缓存层）。
class CacheKeyException implements Exception {
  /// 创建异常。
  const CacheKeyException(this.message);

  /// 说明。
  final String message;

  @override
  String toString() => 'CacheKeyException: $message';
}

/// 作用域非法（不允许进入缓存层）。
class CacheScopeException implements Exception {
  /// 创建异常。
  const CacheScopeException(this.message);

  /// 说明。
  final String message;

  @override
  String toString() => 'CacheScopeException: $message';
}

/// 远端文档（GitHub Contents API 的抽象投影）。
class RemoteDocument {
  /// 创建文档。
  const RemoteDocument({required this.content, required this.sha});

  /// 文本内容。
  final String content;

  /// 内容指纹（GitHub 的 blob SHA）。
  final String sha;

  @override
  String toString() => 'RemoteDocument(sha=${_short(sha)}, ${content.length}B)';
}

/// 远端读写冲突（HTTP 409 / 422 等）。
class RemoteConflictException implements Exception {
  /// 创建异常。
  const RemoteConflictException({
    required this.statusCode,
    this.currentSha,
    this.message,
  });

  /// 状态码。
  final int statusCode;

  /// 冲突时远端的最新指纹。
  final String? currentSha;

  /// 说明。
  final String? message;

  /// 是否属于"基线过期"类冲突（可重定基）。
  bool get isStale => statusCode == 409 || statusCode == 422;

  @override
  String toString() => 'RemoteConflictException($statusCode'
      '${currentSha == null ? '' : ', sha=${_short(currentSha!)}'})';
}

/// 写冲突分类。
enum WriteConflict {
  /// 无冲突。
  none,

  /// 缺少基线 SHA，需先读（D1）。
  requiresRead,

  /// 基线已过期，远端有更新（D2）。
  staleSha,

  /// 危险操作需二次确认（D7）。
  needsConfirmation,

  /// 目标不存在或无权访问。
  notFound,

  /// 权限不足。
  forbidden,

  /// 服务端错误。
  server,

  /// 写后回读校验失败（D5）。
  verificationFailed,
}

/// 冲突处置建议（**给 UI 的契约**，不含任何界面代码）。
///
/// 底座不认识按钮，只回答"这个冲突允许用户做哪几件事"。
/// 展示层照此渲染即可，禁止自行发明处置方式——
/// 尤其禁止在 `staleSha` 时只给"覆盖"而不给"先看看差异"。
enum ConflictAction {
  /// 查看三方差异（base / remote / local）。
  viewDiff,

  /// 先拉取远端最新版本再决定。
  pullRemote,

  /// 重新发起（例如网络恢复后重试）。
  retry,

  /// 用户确认后强制覆盖（必须二次确认，且全程留痕）。
  forceOverwrite,

  /// 需要重新授权 / 提升权限。
  reauthorize,

  /// 目标已不存在，改为「新建」或取消。
  createInstead,

  /// 稍后重试（进入待同步队列）。
  retryLater,
}

/// 给定冲突类型，给出**允许**的处置方式（顺序即推荐顺序）。
List<ConflictAction> resolveConflictActions(WriteConflict conflict) {
  switch (conflict) {
    case WriteConflict.none:
      return const <ConflictAction>[];
    case WriteConflict.requiresRead:
      return const <ConflictAction>[
        ConflictAction.pullRemote,
        ConflictAction.retry
      ];
    case WriteConflict.staleSha:
      return const <ConflictAction>[
        ConflictAction.viewDiff,
        ConflictAction.pullRemote,
        ConflictAction.forceOverwrite,
      ];
    case WriteConflict.needsConfirmation:
      return const <ConflictAction>[
        ConflictAction.forceOverwrite,
        ConflictAction.retryLater
      ];
    case WriteConflict.notFound:
      return const <ConflictAction>[
        ConflictAction.createInstead,
        ConflictAction.pullRemote
      ];
    case WriteConflict.forbidden:
      return const <ConflictAction>[ConflictAction.reauthorize];
    case WriteConflict.server:
      return const <ConflictAction>[
        ConflictAction.retryLater,
        ConflictAction.retry
      ];
    case WriteConflict.verificationFailed:
      return const <ConflictAction>[
        ConflictAction.retry,
        ConflictAction.pullRemote
      ];
  }
}

/// 冲突的三方内容（供 UI 做差异展示）。
///
/// 三者齐备才是"真三方分歧"：远端被别人改了，本地也改了，
/// 两边都基于同一个 base。缺 base 时只能说"基线不明"，不能假装知道。
class ConflictThreeWay {
  /// 创建三方信息。
  const ConflictThreeWay({required this.local, this.base, this.remote});

  /// 用户本地要写入的内容。
  final String local;

  /// 用户编辑所基于的版本内容（本地缓存中若已丢失，则为 `null`）。
  final String? base;

  /// 远端最新内容（冲突时读到）。
  final String? remote;

  /// 是否拿到了基线内容。
  bool get hasBase => base != null;

  /// 是否拿到了远端内容。
  bool get hasRemote => remote != null;

  /// 是否存在真正的三方分歧（本地与远端各改各的）。
  bool get diverged {
    final baseText = base;
    final remoteText = remote;
    if (baseText == null || remoteText == null) {
      return false;
    }
    // 双方都动过，且**结果不同**才算"各改各的"。
    // 两边恰好改成同一内容时不存在可解的分歧，按"远端已更新"提示即可
    // （否则界面会宣称"直接覆盖会丢掉对方的修改"，而实际上对方的修改就是你的修改）。
    return remoteText != baseText && local != baseText && local != remoteText;
  }

  @override
  String toString() => 'ConflictThreeWay(local=${local.length}B, '
      'base=${base == null ? '未知' : '${base!.length}B'}, '
      'remote=${remote == null ? '未知' : '${remote!.length}B'}, '
      'diverged=$diverged)';
}

/// 写意图。
class WriteIntent {
  /// 创建写意图。
  const WriteIntent({
    required this.key,
    required this.content,
    required this.message,
    this.baseSha,
    this.force = false,
    this.dangerous = false,
    this.rebase,
  });

  /// 目标键。
  final CacheKey key;

  /// 期望写入的内容。
  final String content;

  /// 提交信息。
  final String message;

  /// 本地基线指纹（读到的版本；D2 用）。
  final String? baseSha;

  /// 是否强制覆盖（跳过 D2；**必须**搭配 `dangerous` 与二次确认）。
  final bool force;

  /// 是否属于危险操作（删除 / 强制覆盖；D7 需二次确认）。
  final bool dangerous;

  /// 冲突重定基函数（D3）：给定远端最新内容与本地内容，产出合并结果。
  ///
  /// 为 `null` 表示**不做自动合并**——冲突直接上报用户，绝不擅自覆盖。
  final String Function(String latestContent, String myContent)? rebase;

  @override
  String toString() => 'WriteIntent(${key.encode()}, base=$baseSha, '
      'force=$force, dangerous=$dangerous)';
}

/// 写结果。
class WriteOutcome {
  /// 创建结果。
  const WriteOutcome({
    required this.ok,
    required this.conflict,
    this.sha,
    this.baseSha,
    this.attempts = 1,
    this.detail,
    this.entry,
    this.threeWay,
  });

  /// 成功结果。
  factory WriteOutcome.success({
    required CacheEntry entry,
    required int attempts,
  }) =>
      WriteOutcome(
        ok: true,
        conflict: WriteConflict.none,
        sha: entry.sha,
        attempts: attempts,
        entry: entry,
      );

  /// 失败结果。
  factory WriteOutcome.failure(
    WriteConflict conflict, {
    String? detail,
    String? sha,
    String? baseSha,
    int attempts = 1,
    ConflictThreeWay? threeWay,
  }) =>
      WriteOutcome(
        ok: false,
        conflict: conflict,
        sha: sha,
        baseSha: baseSha,
        attempts: attempts,
        detail: detail,
        threeWay: threeWay,
      );

  /// 是否成功。
  final bool ok;

  /// 冲突分类。
  final WriteConflict conflict;

  /// 结果指纹（成功时为新版本；冲突时为远端最新版本）。
  final String? sha;

  /// 本地基线指纹（供 UI 展示"你的基线是哪一个版本"）。
  final String? baseSha;

  /// 实际尝试次数（含冲突重试）。
  final int attempts;

  /// 失败说明（D6：失败必须可感知）。
  final String? detail;

  /// 成功时写入的本地条目。
  final CacheEntry? entry;

  /// 冲突三方内容（D10：冲突必须可解释）。
  final ConflictThreeWay? threeWay;

  /// 本冲突允许的处置方式（**给 UI 的契约**）。
  List<ConflictAction> get actions => resolveConflictActions(conflict);

  @override
  String toString() => 'WriteOutcome(ok=$ok, conflict=${conflict.name}, '
      'sha=${_short(sha)}, attempts=$attempts'
      '${detail == null ? '' : ', detail=$detail'})';
}

/// 缓存条目（本地索引 + 内容 + 版本 + **内容完整性凭据**）。
class CacheEntry {
  /// 创建条目。
  const CacheEntry({
    required this.key,
    required this.content,
    required this.sha,
    required this.fetchedAt,
    required this.revision,
    this.contentHash = '',
  });

  /// 键。
  final CacheKey key;

  /// 内容。
  final String content;

  /// 版本指纹（远端 SHA）。
  final String sha;

  /// 抓取时间。
  final DateTime fetchedAt;

  /// 本地修订号（单调递增，用于诊断排序）。
  final int revision;

  /// 内容的 SHA-256（本地完整性凭据）。
  ///
  /// 落盘内容若因掉电/中断而截断，读取时凭据对不上——
  /// 此时必须**判定为损坏并丢弃**，绝不允许把坏内容当合法数据交给上层。
  final String contentHash;

  /// 序列化（索引持久化；**不含内容**，内容单独存 blob）。
  ///
  /// `hash` 与 `len` 是完整性校验的两道凭据，缺一不可。
  Map<String, Object?> toJson() => <String, Object?>{
        'sha': sha,
        'fetchedAt': fetchedAt.toIso8601String(),
        'revision': revision,
        'len': content.length,
        'hash': contentHash,
      };

  @override
  String toString() =>
      'CacheEntry(${key.encode()}, sha=${_short(sha)}, rv=$revision)';
}

/// 指纹短显示（日志友好；长度不足时原样返回）。
String _short(String? sha) {
  if (sha == null) {
    return 'null';
  }
  return sha.length <= 8 ? sha : sha.substring(0, 8);
}

/// 指纹短显示（跨文件复用）。
String shortSha(String? sha) => _short(sha);

/// 一条草稿的**编辑态快照**：正文 + 起草时的远端版本基线。
///
/// 放在内核契约里，是为了让逻辑层能读到"内容 + 基线"而不必知道
/// 底座草稿存储的实现类型（分层纪律：只能向下依赖**契约**）。
class DraftSnapshot {
  /// 创建快照。
  const DraftSnapshot({required this.content, this.baseSha});

  /// 草稿正文。
  final String content;

  /// 起草时基于的远端版本（乐观锁基线）；缺失表示没有可用基线。
  final String? baseSha;
}
