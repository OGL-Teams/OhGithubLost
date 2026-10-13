/// L1 底座级 · 持久性测试（D8 提交日志 / D9 草稿 / D10 三方信息）。
///
/// 覆盖三类"数据会凭空消失"的场景：
/// 1. 点了提交却断网 / 被杀 → 提交必须留在队列里，可恢复；
/// 2. 改了还没提交就崩溃 → 草稿必须还在；
/// 3. 冲突发生时 → 必须能给出 base / remote / local 三方与处置建议。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_cache.dart';
import 'package:ohgithublost/base/disk/disk_draft.dart';
import 'package:ohgithublost/base/disk/disk_journal.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/disk/disk_types.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

/// 内存远端：可注入网络故障与写冲突。
class _FakeRemote implements CacheRemote {
  final Map<String, RemoteDocument> store = <String, RemoteDocument>{};

  /// 写入时抛出的异常（模拟断网）。
  Object? writeError;

  /// 排期的写冲突次数（模拟"刚好在这时被别人抢先提交"）。
  int pendingConflicts = 0;

  int writeCount = 0;

  void seed(CacheKey key, String content, String sha) {
    store[key.encode()] = RemoteDocument(content: content, sha: sha);
  }

  @override
  Future<RemoteDocument?> read(CacheKey key) async => store[key.encode()];

  @override
  Future<void> delete(
    CacheKey key, {
    required String message,
    required String expectedSha,
  }) async {
    final RemoteDocument? current = store[key.encode()];
    if (current == null || current.sha != expectedSha) {
      throw RemoteConflictException(statusCode: 409, currentSha: current?.sha);
    }
    store.remove(key.encode());
  }

  @override
  Future<RemoteDocument> write(
    CacheKey key,
    String content, {
    required String message,
    String? expectedSha,
  }) async {
    writeCount++;
    final failure = writeError;
    if (failure != null) {
      throw failure;
    }
    final current = store[key.encode()];
    if (pendingConflicts > 0) {
      pendingConflicts--;
      throw RemoteConflictException(statusCode: 409, currentSha: current?.sha);
    }
    if (expectedSha != null && current != null && expectedSha != current.sha) {
      throw RemoteConflictException(statusCode: 409, currentSha: current.sha);
    }
    final document = RemoteDocument(content: content, sha: 'sha-r$writeCount');
    store[key.encode()] = document;
    return document;
  }
}

const CacheScope _scope = CacheScope(
  schemaVersion: 1,
  accountId: 'acct',
  repo: 'owner/repo',
  branch: 'main',
);

const CacheKey _key = CacheKey(scope: _scope, path: 'src/main.dart');

void main() {
  late _FakeRemote remote;
  late KernelDiagnostics diagnostics;
  late WriteJournal journal;
  late DraftStore drafts;
  late RepositoryCache cache;

  setUp(() {
    remote = _FakeRemote();
    diagnostics = KernelDiagnostics();
    journal = WriteJournal(store: InMemoryKv(), diagnostics: diagnostics);
    drafts = DraftStore(store: InMemoryKv(), diagnostics: diagnostics);
    cache = RepositoryCache(
      remote: remote,
      index: InMemoryKv(),
      blobs: InMemoryFileStore(),
      diagnostics: diagnostics,
    );
    cache.attachJournal(journal);
    cache.attachDrafts(drafts);
  });

  group('D8 提交日志：提交不再凭空消失', () {
    test('成功提交 → 队列不留待办，且草稿被清空', () async {
      remote.seed(_key, 'v1', 'sha-1');
      await drafts.save(_key, '用户的编辑', baseSha: 'sha-1');

      final outcome = await cache.write(
        const WriteIntent(
          key: _key,
          content: 'mine',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );

      expect(outcome.ok, isTrue);
      expect(await journal.pendingCount(), 0);
      expect(await journal.records(), isEmpty);
      expect(await drafts.load(_key), isNull, reason: '提交成功后草稿必须清空');
    });

    test('网络异常 → 提交仍在队列里（含内容与基线）', () async {
      remote.seed(_key, 'v1', 'sha-1');
      remote.writeError = const NetException(NetErrorKind.connection, '断网');

      final outcome = await cache.write(
        const WriteIntent(
          key: _key,
          content: '重要的改动',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );

      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.server);

      final pending = await journal.records(status: JournalStatus.pending);
      expect(pending.length, 1, reason: '提交必须留在队列，等待恢复');
      expect(pending.first.content, '重要的改动');
      expect(pending.first.baseSha, 'sha-1');
      expect(pending.first.attempts, greaterThan(0));
      expect(pending.first.lastError, isNotNull);
    });

    test('语义冲突（D1/D2 拦下）→ 不产生待办，避免污染列表', () async {
      remote.seed(_key, 'v2', 'sha-2');
      final outcome = await cache.write(
        const WriteIntent(
          key: _key,
          content: 'mine',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );
      expect(outcome.conflict, WriteConflict.staleSha);
      expect(await journal.records(), isEmpty);
    });

    test('写中期冲突（409）→ 标记放弃，绝不自动重放', () async {
      remote.seed(_key, 'v1', 'sha-1');
      remote.pendingConflicts = 1;

      final outcome = await cache.write(
        const WriteIntent(
          key: _key,
          content: 'mine',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );

      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.staleSha);
      expect(await journal.pendingCount(), 0);
      final all = await journal.records();
      expect(all.length, 1);
      expect(all.first.status, JournalStatus.abandoned);
    });

    test('重放：网络恢复后队列清空且不重复入队', () async {
      remote.seed(_key, 'v1', 'sha-1');
      remote.writeError = const NetException(NetErrorKind.connection, '断网');
      await cache.write(
        const WriteIntent(
          key: _key,
          content: 'mine',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );
      expect(await journal.pendingCount(), 1);

      remote.writeError = null; // 网络恢复
      final results = await cache.replayPending();

      expect(results.length, 1);
      expect(results.first.ok, isTrue);
      expect(await journal.records(), isEmpty, reason: '原记录应被收尾，不得留下重影');
      expect(remote.store[_key.encode()]?.content, 'mine');
    });

    test('重放时基线已过期 → 仍被拦下，并标记放弃', () async {
      remote.seed(_key, 'v1', 'sha-1');
      remote.writeError = const NetException(NetErrorKind.connection, '断网');
      await cache.write(
        const WriteIntent(
          key: _key,
          content: 'mine',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );

      // 网络恢复，但期间远端已被别人推进。
      remote.writeError = null;
      remote.seed(_key, '别人的新内容', 'sha-new');

      final results = await cache.replayPending();
      expect(results.length, 1);
      expect(results.first.ok, isFalse);
      expect(results.first.conflict, WriteConflict.staleSha);
      expect(await journal.pendingCount(), 0, reason: '不应无限重放');
      final all = await journal.records();
      expect(all.first.status, JournalStatus.abandoned);
      expect(
        remote.store[_key.encode()]?.content,
        '别人的新内容',
        reason: '绝不能覆盖别人的提交',
      );
    });
  });

  group('D10 冲突三方信息与处置建议', () {
    test('staleSha 给出 base / remote / local，并标记为真分歧', () async {
      remote.seed(_key, '基线内容', 'sha-1');
      await cache.read(_key); // 本地缓存记下 sha-1

      remote.seed(_key, '别人改的内容', 'sha-2'); // 期间远端被推进

      final outcome = await cache.write(
        const WriteIntent(
          key: _key,
          content: '我改的内容',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );

      expect(outcome.conflict, WriteConflict.staleSha);
      expect(outcome.baseSha, 'sha-1');
      expect(outcome.sha, 'sha-2');

      final threeWay = outcome.threeWay;
      expect(threeWay, isNotNull);
      expect(threeWay!.base, '基线内容');
      expect(threeWay.remote, '别人改的内容');
      expect(threeWay.local, '我改的内容');
      expect(threeWay.diverged, isTrue);
    });

    test('本地缓存已被刷新过 → base 如实为 null（不知道就说不知道）', () async {
      remote.seed(_key, 'v2', 'sha-2');
      final outcome = await cache.write(
        const WriteIntent(
          key: _key,
          content: 'mine',
          message: '提交',
          baseSha: 'sha-1',
        ),
      );
      expect(outcome.threeWay, isNotNull);
      expect(outcome.threeWay!.base, isNull);
      expect(outcome.threeWay!.remote, 'v2');
    });

    test('处置建议：staleSha 必须给"先看差异"，不能只给"覆盖"', () {
      final actions = resolveConflictActions(WriteConflict.staleSha);
      expect(actions, contains(ConflictAction.viewDiff));
      expect(actions, contains(ConflictAction.pullRemote));
      expect(actions, contains(ConflictAction.forceOverwrite));
      expect(actions.first, ConflictAction.viewDiff, reason: '顺序即推荐顺序');

      expect(
        resolveConflictActions(WriteConflict.forbidden),
        <ConflictAction>[ConflictAction.reauthorize],
      );
      expect(
        resolveConflictActions(WriteConflict.server),
        contains(ConflictAction.retryLater),
      );
    });
  });

  group('D9 草稿仓库', () {
    test('保存累加修订号，且保留起草基线', () async {
      final first = await drafts.save(_key, '草稿一', baseSha: 'sha-1');
      expect(first.revision, 1);
      final second = await drafts.save(_key, '草稿二');
      expect(second.revision, 2);
      expect(second.baseSha, 'sha-1', reason: '未显式传基线时应沿用');

      final loaded = await drafts.load(_key);
      expect(loaded?.content, '草稿二');
      expect(await drafts.count(), 1);
    });

    test('丢弃与清空', () async {
      await drafts.save(_key, 'a');
      expect(await drafts.has(_key), isTrue);
      await drafts.discard(_key);
      expect(await drafts.has(_key), isFalse);

      await drafts.save(_key, 'b');
      expect(await drafts.clear(), 1);
      expect(await drafts.count(), 0);
    });

    test('结构损坏的草稿被清理，不拖垮读取', () async {
      final kv = InMemoryKv();
      final store = DraftStore(store: kv);
      await kv.write('ogl.draft.${_key.encode()}', '这不是 JSON');
      expect(await store.load(_key), isNull);
      expect(await store.all(), isEmpty);
    });
  });

  group('日志与草稿的结构健壮性', () {
    test('日志记录可序列化往返', () {
      final record = JournalRecord(
        id: 'x1',
        key: _key,
        content: 'c',
        message: 'm',
        createdAt: DateTime.parse('2026-10-01T00:00:00.000Z'),
        baseSha: 'sha-1',
      );
      final restored = JournalRecord.fromJson(
        Map<String, dynamic>.from(record.toJson()),
      );
      expect(restored, isNotNull);
      expect(restored!.key, _key);
      expect(restored.content, 'c');
      expect(restored.baseSha, 'sha-1');
      expect(restored.status, JournalStatus.pending);
    });

    test('键编解码往返（含带竖线的路径）', () {
      const tricky = CacheKey(scope: _scope, path: 'a|b/c.txt');
      expect(CacheKey.decode(tricky.encode()), tricky);
      expect(CacheKey.decode('不合法'), isNull);
    });

    test('损坏的日志记录被清理而非反复报错', () async {
      final kv = InMemoryKv();
      final store = WriteJournal(store: kv);
      await kv.write('ogl.journal.broken', '{{{');
      expect(await store.records(), isEmpty);
      expect(await kv.has('ogl.journal.broken'), isFalse);
    });
  });
}
