/// L1 底座级 · 硬盘逻辑：缓存一致性引擎（七道防线 D1–D7 + 完整性 + 有界淘汰）。
///
/// 这是全项目**最危险**的一段代码：它决定了用户的代码会不会被悄悄覆盖。
/// 因此这里的每一条规则都对应 `docs/CONSISTENCY.md（该文件未落地，以源码为准）` 的一道防线，
/// 并且**不提供任何"绕过"开关**——想绕过必须显式传 `force` / `dangerous`
/// **且**经过二次确认，且全程留痕。
///
/// | 防线 | 含义 | 落点 |
/// | --- | --- | --- |
/// | D1 | 写前必读 | 缺少 `baseSha` 直接拒绝（`requiresRead`） |
/// | D2 | SHA 乐观锁 | `baseSha != 远端 sha` ⇒ `staleSha` |
/// | D3 | 409/422 冲突重试 | 仅在提供 `rebase` 时按上限重试，否则上报 |
/// | D4 | 本地写队列串行化 | 逐键互斥，**读写一并纳入** |
/// | D5 | 写后失效 + 回读 | 回读带少量重试；仍不一致即 `verificationFailed` |
/// | D6 | 失败可感知 | 一切失败都**返回结果 + 记审计**，绝不外抛 |
/// | D7 | 危险操作二次确认 | `dangerous` **或** `force` 未确认 ⇒ `needsConfirmation` |
///
/// 除七道防线外，本文件还负责三件"数据无价"的前提：
/// 1. **完整性**：索引保存内容长度与 SHA-256，读取时校验，损坏即丢弃；
/// 2. **有界**：支持 TTL 与条目上限，并提供 [RepositoryCache.prune] / [RepositoryCache.purge]；
/// 3. **审计**：诊断中枢可绑定（[RepositoryCache.attachDiagnostics]），D6 不落空。
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../kernel/diagnostics.dart';
import 'disk_draft.dart';
import 'disk_journal.dart';
import 'disk_store.dart';
import 'disk_types.dart';

/// 远端读写抽象（真实实现由 API 中枢通过底座桥注入）。
///
/// 底座**不认识** GitHub：它只要求"给我 sha + 内容"、"按期望 sha 写"。
abstract class CacheRemote {
  /// 读取远端文档；不存在返回 `null`。
  Future<RemoteDocument?> read(CacheKey key);

  /// 按 [expectedSha] 写入；版本不符必须抛 [RemoteConflictException]。
  ///
  /// [expectedSha] 为 `null` 表示新建（远端不应存在该路径）。
  Future<RemoteDocument> write(
    CacheKey key,
    String content, {
    required String message,
    String? expectedSha,
  });

  /// 按 [expectedSha] 删除；版本不符必须抛 [RemoteConflictException]。
  ///
  /// 删除同属"可能顶掉别人提交"的操作，因此同样需要基线（D1/D2）。
  Future<void> delete(
    CacheKey key, {
    required String message,
    required String expectedSha,
  });
}

/// 未绑定远端时的占位实现（启动早期 / 纯离线）。
///
/// 有意让它**抛异常而不是静默成功**——静默成功等于把用户数据丢掉。
class UnavailableCacheRemote implements CacheRemote {
  /// 创建占位实现。
  const UnavailableCacheRemote();

  @override
  Future<RemoteDocument?> read(CacheKey key) async =>
      throw StateError('缓存远端未绑定（等待 API 中枢注入）');

  @override
  Future<RemoteDocument> write(
    CacheKey key,
    String content, {
    required String message,
    String? expectedSha,
  }) async =>
      throw StateError('缓存远端未绑定（等待 API 中枢注入）');

  @override
  Future<void> delete(
    CacheKey key, {
    required String message,
    required String expectedSha,
  }) async =>
      throw StateError('缓存远端未绑定（等待 API 中枢注入）');
}

/// 逐键互斥：保证**同一目标**的读写按提交顺序串行执行（D4）。
///
/// 为什么读也要进来：写已落远端、本地尚未刷新时，一次并发读会把
/// **旧内容写回本地**，本地版本随之倒退。看起来只是"显示旧了"，
/// 但它会成为下一次写的基线来源——所以必须同锁串行。
class _KeyedMutex {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  Future<T> run<T>(String key, Future<T> Function() action) async {
    final previous = _tails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    _tails[key] = completer.future;
    try {
      await previous;
    } catch (_) {
      // 前序任务的成败不影响本任务的执行顺序。
    }
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_tails[key], completer.future)) {
        _tails.remove(key);
      }
    }
  }

  /// 当前仍在排队的键数量（诊断用）。
  int get pendingKeys => _tails.length;
}

/// 本地索引元数据（用于淘汰扫描）。
typedef _LocalMeta = ({String encoded, DateTime fetchedAt});

/// 仓库缓存（一致性引擎）。
class RepositoryCache {
  /// 创建缓存。
  ///
  /// [defaultMaxAge] 为条目存活时长（`<= Duration.zero` 表示不设 TTL）；
  /// [defaultMaxEntries] 为条目上限（`<= 0` 表示不设上限）；
  /// [readbackAttempts] 为 D5 回读校验的尝试次数（抵御读路径的瞬时陈旧）。
  RepositoryCache({
    CacheRemote? remote,
    DiskKv? index,
    DiskFileStore? blobs,
    KernelDiagnostics? diagnostics,
    this.maxConflictRetries = 2,
    this.defaultMaxEntries = 512,
    this.defaultMaxAge = const Duration(days: 30),
    this.readbackAttempts = 2,
    this.readbackDelay = const Duration(milliseconds: 150),
  })  : _remote = remote ?? const UnavailableCacheRemote(),
        _index = index ?? InMemoryKv(),
        _blobs = blobs ?? InMemoryFileStore(),
        _diagnostics = diagnostics ?? KernelDiagnostics();

  static const String _indexPrefix = 'ogl.cache.meta.';
  static const String _blobPrefix = 'cache/';

  final DiskKv _index;
  final DiskFileStore _blobs;

  /// D3 冲突重试上限。
  final int maxConflictRetries;

  /// 条目数量上限。
  final int defaultMaxEntries;

  /// 条目存活时长。
  final Duration defaultMaxAge;

  /// D5 回读校验尝试次数。
  final int readbackAttempts;

  /// D5 回读重试间隔。
  final Duration readbackDelay;

  KernelDiagnostics _diagnostics;
  CacheRemote _remote;
  WriteJournal? _journal;
  DraftStore? _drafts;
  int _revision = 0;

  /// 绑定提交日志（D8：写前落盘，崩溃可恢复）。
  void attachJournal(WriteJournal journal) {
    _journal = journal;
  }

  /// 绑定草稿仓库（D9：提交成功后自动清草稿）。
  void attachDrafts(DraftStore drafts) {
    _drafts = drafts;
  }

  /// 当前提交日志（未绑定为 `null`）。
  WriteJournal? get journal => _journal;

  /// 当前草稿仓库（未绑定为 `null`）。
  DraftStore? get drafts => _drafts;

  /// 绑定诊断中枢（装配阶段调用）。
  ///
  /// 不绑定也"能用"，但 D6 的审计链会断——数据事故后无从追溯。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 绑定远端实现（API 中枢在装配阶段调用）。
  void bindRemote(CacheRemote remote) {
    _remote = remote;
  }

  /// 当前远端实现。
  CacheRemote get remote => _remote;

  /// 读取：优先本地（未过期），缺失 / 过期 / 强制刷新时回源。
  ///
  /// [maxAge] 覆盖默认 TTL：调用方可为"变化快的浏览数据"设更短的有效期
  /// （例如目录列表 1 分钟），而不用改全局默认。
  ///
  /// **永不同步抛出**：失败以 Future 异常形式返回（非法键则抛
  /// [CacheScopeException] / [CacheKeyException]），调用方可统一 try/catch。
  Future<CacheEntry?> read(
    CacheKey key, {
    bool refresh = false,
    Duration? maxAge,
  }) async {
    _ensureKey(key);
    return _mutex.run(
      key.encode(),
      () => _readLocked(key, refresh: refresh, maxAge: maxAge),
    );
  }

  /// 写入：完整走 D1–D7。
  ///
  /// **永不外抛**（除非法键这一编程错误外）：一切失败都体现在
  /// [WriteOutcome.conflict] 与 [WriteOutcome.detail] 上。
  ///
  /// [recordJournal] 为 `false` 时**不写提交日志**——仅供
  /// [replayPending] 使用（它自己负责原记录的收尾，避免重复入队）。
  Future<WriteOutcome> write(
    WriteIntent intent, {
    bool confirmed = false,
    bool recordJournal = true,
  }) async {
    _ensureKey(intent.key);
    return _mutex.run(intent.key.encode(), () async {
      try {
        return await _writeLocked(
          intent,
          confirmed: confirmed,
          recordJournal: recordJournal,
        );
      } on CacheScopeException {
        rethrow;
      } on CacheKeyException {
        rethrow;
      } catch (error) {
        // D6：任何非预期异常（网络 / 磁盘 / 解析）都必须变成可感知的失败结果。
        // D8：队列里那条 pending 要同步标注，否则 UI 的"待同步"会失真。
        const detail = '写入异常终止';
        await _journal?.failByKey(intent.key, '$detail：$error');
        return _fail(
          intent,
          WriteConflict.server,
          '$detail：$error',
          code: 'OGL-CONS-206',
        );
      }
    });
  }

  /// 仅失效本地缓存（D5 的"写后失效"也可独立调用）。
  Future<void> invalidate(CacheKey key) async {
    _ensureKey(key);
    return _mutex.run(key.encode(), () => _evictEncoded(key.encode()));
  }

  /// 删除（**危险操作**）：完整走 D1 / D2 / D7。
  ///
  /// 为什么**不入提交日志**：日志记录会被 [replayPending] 还原成 [WriteIntent]
  /// 重放，而删除无法用 WriteIntent 表达——强行入队，重放会把它当成"写入空内容"，
  /// 反而制造数据事故。因此删除只做**在线加锁**，失败如实返回、由用户重试。
  Future<WriteOutcome> delete(
    CacheKey key, {
    required String message,
    required String baseSha,
    bool confirmed = false,
  }) async {
    _ensureKey(key);
    return _mutex.run(key.encode(), () async {
      final WriteIntent intent = WriteIntent(
        key: key,
        content: '',
        message: message,
        baseSha: baseSha,
        dangerous: true,
      );
      // D7：危险操作必须二次确认。
      if (!confirmed) {
        return _fail(
          intent,
          WriteConflict.needsConfirmation,
          '删除属于危险操作，需二次确认（D7）',
          code: 'OGL-CONS-208',
        );
      }
      try {
        // D1/D2：删除前确认目标仍在，且基线未过期。
        final RemoteDocument? latest = await _remote.read(key);
        if (latest == null) {
          return await _fail(
            intent,
            WriteConflict.notFound,
            '目标已不存在（可能已被删除）',
            code: 'OGL-CONS-210',
          );
        }
        if (latest.sha != baseSha) {
          return await _fail(
            intent,
            WriteConflict.staleSha,
            '本地基线已过期：期望 ${shortSha(baseSha)}，'
            '远端 ${shortSha(latest.sha)}（D2）',
            sha: latest.sha,
            baseSha: baseSha,
            threeWay: ConflictThreeWay(
              local: '',
              base: null,
              remote: latest.content,
            ),
            code: 'OGL-CONS-202',
          );
        }
        await _remote.delete(key, message: message, expectedSha: baseSha);
        await _evictEncoded(key.encode());
        _diagnostics.info(
          'CACHE',
          '删除成功',
          code: 'OGL-CONS-005',
          data: <String, Object?>{
            'key': key.encode(),
            'sha': shortSha(baseSha),
          },
        );
        return WriteOutcome(
          ok: true,
          conflict: WriteConflict.none,
          baseSha: baseSha,
        );
      } on RemoteConflictException catch (error) {
        return _fail(
          intent,
          _classify(error),
          '远端冲突未解决（HTTP ${error.statusCode}）',
          sha: error.currentSha,
          baseSha: baseSha,
          code: 'OGL-CONS-203',
        );
      } catch (error) {
        return _fail(
          intent,
          WriteConflict.server,
          '删除异常终止：$error',
          code: 'OGL-CONS-206',
        );
      }
    });
  }

  /// 本地有效条目数（诊断）。
  Future<int> localCount() async {
    final metas = await _scanMetas();
    return metas.length;
  }

  /// 按上限与 TTL 淘汰本地缓存，返回清理条目数。
  ///
  /// **磁盘是有界的**。没有淘汰策略的缓存，最终会写满磁盘，
  /// 之后连"保存用户刚写的文件"都会失败——那才是真的事故。
  Future<int> prune({int? maxEntries, Duration? maxAge}) async {
    final limit = maxEntries ?? defaultMaxEntries;
    final age = maxAge ?? defaultMaxAge;
    final now = DateTime.now();
    final survivors = <_LocalMeta>[];
    var removed = 0;

    for (final meta in await _scanMetas()) {
      if (age > Duration.zero && now.difference(meta.fetchedAt) > age) {
        if (await _evictIfStale(meta.encoded, meta.fetchedAt)) {
          removed++;
        }
      } else {
        survivors.add(meta);
      }
    }

    if (limit > 0 && survivors.length > limit) {
      survivors.sort((a, b) => a.fetchedAt.compareTo(b.fetchedAt));
      // 从最旧开始淘汰。`_evictIfStale` 可能因"刚被并发写刷新"而**拒绝**淘汰，
      // 那种条目绝不能从 `survivors` 里丢掉：丢了就会虚报"已腾位"（计数与
      // `remaining` 都不再真实），而且下一次扫描又从头来 —— 表现为缓存
      // 长期超出上限、淘汰永远"做完一半"。
      var index = 0;
      while (survivors.length > limit && index < survivors.length) {
        final _LocalMeta victim = survivors[index];
        if (await _evictIfStale(victim.encoded, victim.fetchedAt)) {
          removed++;
          survivors.removeAt(index);
          continue; // 同一下标现在是下一个候选。
        }
        index++; // 这次没删成（热数据）：跳过，宁可暂时超限。
      }
    }

    if (removed > 0) {
      _diagnostics.info(
        'CACHE',
        '缓存淘汰完成',
        code: 'OGL-CONS-002',
        data: <String, Object?>{
          'removed': removed,
          'remaining': survivors.length
        },
      );
    }
    return removed;
  }

  /// 重放待完成提交（启动 / 网络恢复 / 用户点「重试」时调用）。
  ///
  /// 重放会**完整重走 D1–D7**：基线过期的记录仍会被拦下并返回冲突，
  /// 绝不会因为"它来自队列"就降低标准。
  ///
  /// 每条记录的重放都**不重复入队**（[write] 的 `recordJournal: false`），
  /// 由本方法按结果对**原记录**收尾，避免队列出现"重影"。
  Future<List<WriteOutcome>> replayPending({bool confirmed = false}) async {
    final journal = _journal;
    if (journal == null) {
      return const <WriteOutcome>[];
    }

    final outcomes = <WriteOutcome>[];
    for (final record in await journal.records(status: JournalStatus.pending)) {
      final outcome = await write(
        record.toIntent(),
        confirmed: confirmed,
        recordJournal: false,
      );
      final reason = outcome.detail ?? outcome.conflict.name;
      if (outcome.ok) {
        await journal.complete(record.id);
      } else if (outcome.conflict == WriteConflict.needsConfirmation) {
        // D7 未确认：**必须保持 pending**。
        // 若按"语义冲突"放弃，用户已经在队列里排好的危险操作会被静默丢掉。
        // 正确语义是"等用户点头，再继续"。
      } else if (_isRetryable(outcome.conflict)) {
        await journal.fail(record.id, reason);
      } else {
        // 语义性冲突：不自动重放，交回用户重新决策。
        await journal.abandon(record.id, reason);
      }
      outcomes.add(outcome);
    }

    _diagnostics.info(
      'JOURNAL',
      '待完成提交已重放',
      code: 'OGL-JOURNAL-004',
      data: <String, Object?>{
        'total': outcomes.length,
        'succeeded': outcomes.where((WriteOutcome o) => o.ok).length,
      },
    );
    return outcomes;
  }

  /// 清空全部本地缓存（schema 升级 / 用户手动清理），返回清理条目数。
  Future<int> purge() async {
    var removed = 0;
    for (final meta in await _scanMetas()) {
      if (await _evictIfStale(meta.encoded, meta.fetchedAt)) {
        removed++;
      }
    }
    // 补一刀：清掉一切"没有索引引用"的孤儿内容文件——
    // 它们来自 `_saveLocal` / `_evictEncoded` 中断在半路（blob 已写、索引未动）
    // 或坏索引被清理的时刻。没有这一步，这些文件会永远占着磁盘。
    removed += await purgeOrphans();
    _diagnostics.info(
      'CACHE',
      '缓存已清空',
      code: 'OGL-CONS-003',
      data: <String, Object?>{'removed': removed},
    );
    return removed;
  }

  /// 清掉孤儿 blob（无索引引用的内容文件），返回删除数量。
  ///
  /// 与 [purge] 的区别：本方法**只删孤儿**，不触碰仍被索引引用的有效缓存。
  /// 判定依据是"文件名是否出现在现存索引集合中"——反向（索引在、文件丢）
  /// 由 [_loadLocal] 在读取时自愈。
  Future<int> purgeOrphans() async {
    final referenced = <String>{
      for (final meta in await _scanMetas()) blobNameOf(meta.encoded),
    };
    var removed = 0;
    for (final name in await _blobs.list('cache')) {
      if (!name.endsWith('.txt')) {
        continue; // 只认 blob 的命名习惯，其它文件一律不动（保守）。
      }
      if (referenced.contains(name)) {
        continue;
      }
      await _blobs.delete('$_blobPrefix$name');
      removed++;
    }
    if (removed > 0) {
      _diagnostics.info(
        'CACHE',
        '孤儿缓存文件已清理',
        code: 'OGL-CONS-004',
        data: <String, Object?>{'removed': removed},
      );
    }
    return removed;
  }

  // ───────────────────────── 内部实现 ─────────────────────────

  final _KeyedMutex _mutex = _KeyedMutex();

  Future<CacheEntry?> _readLocked(
    CacheKey key, {
    required bool refresh,
    Duration? maxAge,
  }) async {
    if (!refresh) {
      final cached = await _loadLocal(key);
      if (cached != null) {
        if (_isExpired(cached, maxAge)) {
          // 过期即清理，随后回源——宁可多一次请求，也不给上层陈旧数据。
          await _evictEncoded(key.encode());
        } else {
          _diagnostics.debug(
            'CACHE',
            '本地命中',
            data: <String, Object?>{
              'key': key.encode(),
              'sha': shortSha(cached.sha),
            },
          );
          return cached;
        }
      }
    }

    final document = await _remote.read(key);
    if (document == null) {
      await _evictEncoded(key.encode());
      return null;
    }
    final entry = _entryOf(key, document);
    await _saveLocal(entry);
    return entry;
  }

  Future<WriteOutcome> _writeLocked(
    WriteIntent intent, {
    required bool confirmed,
    required bool recordJournal,
  }) async {
    // D7：危险操作与强制覆盖都必须二次确认。
    // force 会跳过 D2 对"本地基线"的校验，等价于放宽覆盖条件——
    // 它与删除同属"可能顶掉别人提交"的操作，必须同等对待。
    if ((intent.dangerous || intent.force) && !confirmed) {
      return _fail(
        intent,
        WriteConflict.needsConfirmation,
        intent.force ? '强制覆盖需二次确认（D7）：将跳过本地基线校验' : '危险操作需二次确认（D7）',
        code: 'OGL-CONS-207',
      );
    }

    // D1：写前必读——没有基线就不允许写。
    final latest = await _remote.read(intent.key);
    if (intent.baseSha == null && !intent.force) {
      return _fail(
        intent,
        WriteConflict.requiresRead,
        '缺少基线 SHA，请先读取目标（D1）',
        code: 'OGL-CONS-201',
      );
    }

    // D2：SHA 乐观锁——本地基线必须与远端一致。
    if (!intent.force && latest != null && intent.baseSha != latest.sha) {
      return _fail(
        intent,
        WriteConflict.staleSha,
        '本地基线已过期：期望 ${shortSha(intent.baseSha)}，'
        '远端 ${shortSha(latest.sha)}（D2）',
        sha: latest.sha,
        baseSha: intent.baseSha,
        threeWay: await _threeWayFor(intent, latest),
        code: 'OGL-CONS-202',
      );
    }

    // D2′：基线存在、远端却已消失——大概率是**他人删除了它**。
    // 这不是"可以写"的情形：带着旧 sha 去覆盖一个已不存在的目标，
    // 轻则被服务端拒绝，重则在"删除又重建"的竞态里把新内容写歪。
    // 必须拦下并交回用户（新建请显式传 baseSha = null）。
    if (!intent.force && intent.baseSha != null && latest == null) {
      return _fail(
        intent,
        WriteConflict.staleSha,
        '本地基线仍在，但远端目标已不存在（可能被他人删除）：'
        '${shortSha(intent.baseSha)}（D2）',
        baseSha: intent.baseSha,
        threeWay: ConflictThreeWay(
          local: intent.content,
          base: null,
          remote: '',
        ),
        code: 'OGL-CONS-209',
      );
    }

    // D8：写前落盘。只有"真正要发出去的写"才入队——
    // D1/D2/D7 拦下的意图不产生待办，避免污染用户看到的"待同步"列表。
    final journalRecord = (!recordJournal || _journal == null)
        ? null
        : await _journal!.enqueue(intent);

    var content = intent.content;
    // force 仍然以"刚读到的远端版本"为期望值：既不盲写，也不放行并发覆盖。
    var expectedSha = intent.force ? latest?.sha : intent.baseSha;
    var attempt = 0;

    while (true) {
      attempt++;
      try {
        final written = await _remote.write(
          intent.key,
          content,
          message: intent.message,
          expectedSha: expectedSha,
        );

        // D5：写后失效 + 回读校验。
        await _evictEncoded(intent.key.encode());
        final verified = await _verifyReadback(intent.key, written.sha);
        if (verified == null) {
          return await _fail(
            intent,
            WriteConflict.verificationFailed,
            '写后回读不一致：期望 ${shortSha(written.sha)}（D5）',
            sha: written.sha,
            baseSha: intent.baseSha,
            code: 'OGL-CONS-205',
            attempts: attempt,
            journalId: journalRecord?.id,
          );
        }

        final entry = _entryOf(intent.key, verified);
        await _saveLocal(entry);

        // D9：提交成功 → 草稿必须清空，否则旧草稿会盖住刚提交的新内容。
        await _drafts?.discard(intent.key);

        // D8：提交落定 → 移出待同步队列。
        if (journalRecord != null) {
          await _journal!.complete(journalRecord.id);
        }

        _diagnostics.info(
          'CACHE',
          '写入成功',
          code: 'OGL-CONS-001',
          data: <String, Object?>{
            'key': intent.key.encode(),
            'sha': shortSha(entry.sha),
            'attempts': attempt,
          },
        );
        return WriteOutcome.success(entry: entry, attempts: attempt);
      } on RemoteConflictException catch (error) {
        // D3：仅当调用方提供了重定基函数时才自动重试。
        if (!error.isStale ||
            attempt > maxConflictRetries ||
            intent.rebase == null) {
          return _fail(
            intent,
            _classify(error),
            '远端冲突未解决（D3, HTTP ${error.statusCode}）'
            '${intent.rebase == null ? '：未提供重定基函数，拒绝自动覆盖' : ''}',
            sha: error.currentSha,
            baseSha: intent.baseSha,
            code: 'OGL-CONS-203',
            attempts: attempt,
            journalId: journalRecord?.id,
          );
        }

        final fresh = await _remote.read(intent.key);
        content = intent.rebase!(fresh?.content ?? '', intent.content);
        expectedSha = error.currentSha ?? fresh?.sha;
        _diagnostics.warn(
          'CACHE',
          '检测到冲突，已重定基后重试',
          code: 'OGL-CONS-204',
          data: <String, Object?>{
            'key': intent.key.encode(),
            'attempt': attempt,
            'base': shortSha(expectedSha),
          },
        );
      }
    }
  }

  /// D5：回读校验（带少量重试，抵御读路径的瞬时陈旧，避免误报失败）。
  Future<RemoteDocument?> _verifyReadback(
    CacheKey key,
    String expectedSha,
  ) async {
    for (var index = 0; index < readbackAttempts; index++) {
      final document = await _remote.read(key);
      if (document != null && document.sha == expectedSha) {
        return document;
      }
      if (index < readbackAttempts - 1) {
        await Future<void>.delayed(readbackDelay);
      }
    }
    return null;
  }

  static WriteConflict _classify(RemoteConflictException error) {
    if (error.statusCode == 404) {
      return WriteConflict.notFound;
    }
    if (error.statusCode == 403) {
      return WriteConflict.forbidden;
    }
    return error.isStale ? WriteConflict.staleSha : WriteConflict.server;
  }

  /// 统一失败出口：**先记账，再返回**。
  ///
  /// 这里同时承担 D8 的队列状态机：
  /// - 可重试的失败（网络 / 回读校验）→ 保留 `pending`，等待重放；
  /// - 语义性冲突（基线过期 / 权限 / 目标不存在）→ 标记 `abandoned`，
  ///   **绝不自动重放**——因为重放它就意味着覆盖别人。
  Future<WriteOutcome> _fail(
    WriteIntent intent,
    WriteConflict conflict,
    String detail, {
    required String code,
    String? sha,
    String? baseSha,
    int attempts = 1,
    ConflictThreeWay? threeWay,
    String? journalId,
  }) async {
    _diagnostics.error(
      'CACHE',
      '写入失败：${conflict.name}',
      code: code,
      data: <String, Object?>{
        'key': intent.key.encode(),
        'detail': detail,
        if (journalId != null) 'journalId': journalId,
      },
    );

    final journal = _journal;
    if (journalId != null && journal != null) {
      if (_isRetryable(conflict)) {
        await journal.fail(journalId, detail);
      } else {
        await journal.abandon(journalId, detail);
      }
    }

    return WriteOutcome.failure(
      conflict,
      detail: detail, // D6：失败必须可感知（返回 + 日志双通道）。
      sha: sha,
      baseSha: baseSha,
      attempts: attempts,
      threeWay: threeWay,
    );
  }

  /// 该冲突是否值得重放（只有"可能因为外部原因失败"的才重放）。
  static bool _isRetryable(WriteConflict conflict) =>
      conflict == WriteConflict.server ||
      conflict == WriteConflict.verificationFailed;

  /// D10：组装冲突三方信息。
  ///
  /// base 只在"本地缓存仍持有用户基线那一版"时才敢给出；
  /// 若本地已被刷新过，就如实返回 `null`——**不知道就说不知道**。
  Future<ConflictThreeWay> _threeWayFor(
    WriteIntent intent,
    RemoteDocument latest,
  ) async {
    final localBase = await _loadLocal(intent.key);
    return ConflictThreeWay(
      local: intent.content,
      base: (localBase != null && localBase.sha == intent.baseSha)
          ? localBase.content
          : null,
      remote: latest.content,
    );
  }

  CacheEntry _entryOf(CacheKey key, RemoteDocument document) => CacheEntry(
        key: key,
        content: document.content,
        sha: document.sha,
        fetchedAt: DateTime.now(),
        revision: ++_revision,
        contentHash: _hashOf(document.content),
      );

  bool _isExpired(CacheEntry entry, [Duration? maxAge]) {
    final limit = maxAge ?? defaultMaxAge;
    if (limit <= Duration.zero) {
      return false;
    }
    return DateTime.now().difference(entry.fetchedAt) > limit;
  }

  void _ensureKey(CacheKey key) {
    if (!key.scope.isWellFormed) {
      throw CacheScopeException(
        '缓存作用域非法（拒绝进入缓存层，防止错位覆盖）: ${key.scope.encode()}',
      );
    }
    if (!key.isPathWellFormed) {
      throw CacheKeyException(
        '缓存路径非法（拒绝进入缓存层）: ${key.path}',
      );
    }
  }

  static String _hashOf(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  String _metaKeyOf(String encoded) => '$_indexPrefix$encoded';

  /// blob 文件名 = `sha256(编码键)` + `.txt`。
  ///
  /// **为什么必须摘要（而不是直接拼键）**：编码键形如 `scope|path`，
  /// 其中的 `|` 在 Windows 上是**非法文件名字符** —— 直接拼名字会让
  /// 整块本地缓存写不进去（`FileSystemException`）。
  /// 摘要顺带解决了两件事：路径过长、以及 Windows 大小写不敏感导致的碰撞。
  static String blobNameOf(String encoded) =>
      '${sha256.convert(utf8.encode(encoded))}.txt';

  String _blobPathOf(String encoded) => '$_blobPrefix${blobNameOf(encoded)}';

  Future<List<_LocalMeta>> _scanMetas() async {
    final result = <_LocalMeta>[];
    for (final key in await _index.keys()) {
      if (!key.startsWith(_indexPrefix)) {
        continue;
      }
      final meta = await _readMeta(key);
      if (meta == null) {
        // 索引损坏：直接清掉（内容由 _loadLocal / purge 兜底）。
        await _index.remove(key);
        continue;
      }
      result.add(meta);
    }
    return result;
  }

  Future<_LocalMeta?> _readMeta(String indexKey) async {
    final raw = await _index.read(indexKey);
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return (
        encoded: indexKey.substring(_indexPrefix.length),
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocal(CacheEntry entry) async {
    final encoded = entry.key.encode();
    await _blobs.writeText(_blobPathOf(encoded), entry.content);
    await _index.write(_metaKeyOf(encoded), jsonEncode(entry.toJson()));
  }

  Future<CacheEntry?> _loadLocal(CacheKey key) async {
    final encoded = key.encode();
    final meta = await _index.read(_metaKeyOf(encoded));
    if (meta == null) {
      return null;
    }
    final content = await _blobs.readText(_blobPathOf(encoded));
    if (content == null) {
      // 索引在、内容丢：视为未命中并清掉脏索引。
      await _evictEncoded(encoded);
      return null;
    }
    try {
      final decoded = jsonDecode(meta) as Map<String, dynamic>;
      final expectedLength = decoded['len'] as int;
      final expectedHash = decoded['hash'] as String;

      // 完整性校验：长度 + SHA-256，任一不符即判定损坏并丢弃。
      // 撕裂写（掉电 / 中断）在这里被挡住，坏内容绝不会流向上层或远端。
      if (content.length != expectedLength ||
          _hashOf(content) != expectedHash) {
        _diagnostics.error(
          'CACHE',
          '本地内容完整性校验失败，已丢弃',
          code: 'OGL-CONS-208',
          data: <String, Object?>{
            'key': encoded,
            'expectedLen': expectedLength,
            'actualLen': content.length,
          },
        );
        await _evictEncoded(encoded);
        return null;
      }

      return CacheEntry(
        key: key,
        content: content,
        sha: decoded['sha'] as String,
        fetchedAt: DateTime.parse(decoded['fetchedAt'] as String),
        revision: decoded['revision'] as int,
        contentHash: expectedHash,
      );
    } catch (_) {
      // 结构不兼容（旧 schema / 损坏）：静默丢弃，下次回源重建。
      await _evictEncoded(encoded);
      return null;
    }
  }

  Future<void> _evictEncoded(String encoded) async {
    await _index.remove(_metaKeyOf(encoded));
    await _blobs.delete(_blobPathOf(encoded));
  }

  /// 在键锁内**复核之后再淘汰**，返回是否真的删掉了。
  ///
  /// 扫描（`_scanMetas`）与淘汰之间存在时间窗：这期间用户可能刚打开文件、
  /// 缓存刚被刷新过。若照扫描结果无脑删，就会把**刚刚取回来的热数据**删掉，
  /// 下一次读又要回源——在弱网下这就是"越用越慢"的根源。
  ///
  /// 判定依据是 `fetchedAt` 是否**晚于**扫描时看到的那一版：
  /// 晚了 ⇒ 数据已更新 ⇒ 放弃本次淘汰。
  Future<bool> _evictIfStale(String encoded, DateTime scannedAt) async {
    var removed = false;
    await _mutex.run(encoded, () async {
      final decoded = CacheKey.decode(encoded);
      if (decoded != null) {
        final fresh = await _loadLocal(decoded);
        if (fresh != null && fresh.fetchedAt.isAfter(scannedAt)) {
          return; // 已被并发写刷新 —— 不淘汰。
        }
      }
      await _evictEncoded(encoded);
      removed = true;
    });
    return removed;
  }
}
