/// L1 底座级 · 破坏性测试（Chaos / 故障注入）。
///
/// ## 为什么需要它
/// 前面所有测试都回答"**正常流程对不对**"；本文件回答另一个问题：
/// **"把它弄死之后，它还能不能守住数据？"**
///
/// 覆盖四类破坏：
/// 1. **崩溃注入**（模拟 `kill -9`）：入队后崩 / 远端已写但本地未确认；
/// 2. **磁盘故障注入**：磁盘满导致日志落盘失败、内容被截断（撕裂写）；
/// 3. **状态机注入**：损坏日志、未确认的危险操作；
/// 4. **并发风暴 + 模糊输入**：500 路并发写同一键、随机垃圾串喂解析器。
///
/// ## 断言的核心不变式（"12306 级"的那句话）
/// > **要么成功，要么可解释地失败；绝不存在"静默错"。**
///
/// 其中 [WriteConflict.server] 的语义是"**基础设施性失败**（网络 / 磁盘），
/// 可稍后重试"——它不是"未分类的异常"，
/// 而是所有非预期异常**收敛后的唯一出口**。
/// 所以本文件对"可解释"的判定是：
/// **失败必须落在有限的枚举里，且不得把数据写歪**。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_cache.dart';
import 'package:ohgithublost/base/disk/disk_journal.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/disk/disk_types.dart';

/// 可控远端：能按脚本抛错、能让"别人同时提交"。
class ChaosRemote implements CacheRemote {
  /// 远端内容库。
  final Map<String, RemoteDocument> store = <String, RemoteDocument>{};

  /// 成功写入次数（也用于生成唯一 sha）。
  int writeCount = 0;

  /// 下一次写入抛出的异常（一次性）。
  Object? failNextWrite;

  /// 写入成功后，远端被"别人"改成另一份内容（一次性，用于制造回读不一致）。
  bool swapAfterWrite = false;

  /// 预置远端文档。
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
      throw RemoteConflictException(
        statusCode: 409,
        currentSha: current?.sha,
        message: '基线过期',
      );
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
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    writeCount++;
    final document = RemoteDocument(content: content, sha: 'sha-$writeCount');
    store[key.encode()] = document;
    if (swapAfterWrite) {
      swapAfterWrite = false;
      store[key.encode()] =
          const RemoteDocument(content: '别人的提交', sha: 'sha-other');
    }
    return document;
  }
}

/// 可注入故障的键值存储（模拟磁盘满 / 写失败）。
class FlakyKv extends InMemoryKv {
  /// 下一次写入抛出的异常（一次性）。
  Object? failNextWrite;

  @override
  Future<void> write(String key, String value) async {
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    return super.write(key, value);
  }
}

/// 可注入"撕裂写"的文件存储（下一次读指定后缀时返回被截断的内容）。
class TruncatingFileStore extends InMemoryFileStore {
  /// 命中该后缀的路径，下一次读取时内容被截半（一次性）。
  String? truncateSuffix;

  @override
  Future<String?> readText(String path) async {
    final result = await super.readText(path);
    final suffix = truncateSuffix;
    if (result == null || suffix == null || !path.endsWith(suffix)) {
      return result;
    }
    truncateSuffix = null;
    return result.substring(0, result.length ~/ 2);
  }
}

CacheKey _key([String path = 'lib/main.dart']) => CacheKey(
      scope: const CacheScope(
        schemaVersion: 1,
        accountId: 'acct-1',
        repo: 'alice/blog',
        branch: 'main',
      ),
      path: path,
    );

WriteIntent _intent({
  String content = 'void main() {}',
  String? baseSha,
  bool dangerous = false,
  bool force = false,
}) =>
    WriteIntent(
      key: _key(),
      content: content,
      message: 'chaos',
      baseSha: baseSha,
      dangerous: dangerous,
      force: force,
    );

void main() {
  group('崩溃注入（kill -9 场景）', () {
    test('入队后进程被杀 ⇒ 重启重放必须完成，且不重复入队', () async {
      final kv = InMemoryKv();
      final blobs = InMemoryFileStore();
      final journal = WriteJournal(store: kv);

      // 第一次：远端在"写请求已发出但未落地"时挂掉。
      final dying = ChaosRemote()..seed(_key(), 'old', 'sha-old');
      dying.failNextWrite = StateError('进程被杀（模拟）');
      final first = RepositoryCache(
        remote: dying,
        index: kv,
        blobs: blobs,
        readbackDelay: Duration.zero,
      )..attachJournal(journal);

      final crashed =
          await first.write(_intent(content: 'new', baseSha: 'sha-old'));
      expect(crashed.ok, isFalse);
      expect(await journal.pendingCount(), 1, reason: '崩溃窗口内必须留下待同步记录');

      // 重启：全新实例，共用同一份"磁盘"。
      final healthy = ChaosRemote()..seed(_key(), 'old', 'sha-old');
      final revived = RepositoryCache(
        remote: healthy,
        index: kv,
        blobs: blobs,
        readbackDelay: Duration.zero,
      )..attachJournal(WriteJournal(store: kv));

      final results = await revived.replayPending(confirmed: true);
      expect(results.length, 1, reason: '重放不得重复入队（否则会越滚越多）');
      expect(results.single.ok, isTrue);
      expect(await WriteJournal(store: kv).pendingCount(), 0);
      expect(healthy.store[_key().encode()]!.content, 'new');
    });

    test('远端已写入但回读不一致 ⇒ 重放必须以冲突收尾，绝不覆盖他人提交', () async {
      final kv = InMemoryKv();
      final journal = WriteJournal(store: kv);
      final remote = ChaosRemote()..seed(_key(), 'old', 'sha-old');
      remote.swapAfterWrite = true; // 我们刚写完，别人又推了一版。

      final cache = RepositoryCache(
        remote: remote,
        index: kv,
        blobs: InMemoryFileStore(),
        readbackAttempts: 2,
        readbackDelay: Duration.zero,
      )..attachJournal(journal);

      final outcome =
          await cache.write(_intent(content: 'mine', baseSha: 'sha-old'));
      expect(outcome.ok, isFalse);
      expect(outcome.conflict, WriteConflict.verificationFailed);

      final results = await cache.replayPending(confirmed: true);
      expect(results.single.conflict, WriteConflict.staleSha);
      expect(
        remote.store[_key().encode()]!.content,
        '别人的提交',
        reason: '数据无价：宁可失败，也绝不覆盖他人提交',
      );
      expect(await journal.pendingCount(), 0, reason: '语义冲突应被标记为已放弃');
    });
  });

  group('磁盘故障注入', () {
    test('日志落盘失败 ⇒ 必须返回失败而非抛出，且绝不发出写请求', () async {
      final kv = FlakyKv();
      final remote = ChaosRemote()..seed(_key(), 'old', 'sha-old');
      final journal = WriteJournal(store: kv);
      final cache = RepositoryCache(
        remote: remote,
        index: kv,
        blobs: InMemoryFileStore(),
        readbackDelay: Duration.zero,
      )..attachJournal(journal);

      kv.failNextWrite = StateError('磁盘满（模拟）');

      final outcome =
          await cache.write(_intent(content: 'new', baseSha: 'sha-old'));

      expect(outcome.ok, isFalse);
      expect(
        outcome.conflict,
        WriteConflict.server,
        reason: '磁盘故障属于"基础设施性失败"，可稍后重试——而不是未分类异常',
      );
      expect(outcome.detail, contains('磁盘满'), reason: '失败原因必须可追溯');
      expect(await journal.pendingCount(), 0, reason: '没落盘的记录不能出现在待同步里');
      expect(
        remote.writeCount,
        0,
        reason: 'D8 的意义：日志没落盘，就绝不能先把请求发出去',
      );
    });

    test('撕裂写注入 ⇒ 坏内容必须被丢弃并回源，绝不交给上层', () async {
      final kv = InMemoryKv();
      final blobs = TruncatingFileStore();
      final remote = ChaosRemote()
        ..seed(_key(), 'good-content-0123456789', 'sha-1');
      final cache = RepositoryCache(
        remote: remote,
        index: kv,
        blobs: blobs,
        readbackDelay: Duration.zero,
      );

      expect((await cache.read(_key()))!.content, 'good-content-0123456789');

      blobs.truncateSuffix = '.txt'; // 下一次读内容时截半（掉电留下的半截写）
      final again = await cache.read(_key());

      expect(again!.content, 'good-content-0123456789',
          reason: '坏内容被丢弃后必须回源重取');
      expect(await cache.localCount(), 1, reason: '索引与内容必须重新自洽，不留脏状态');
    });
  });

  group('状态机注入', () {
    test('日志条目损坏 ⇒ 必须自愈清理，不得让每次启动都报错', () async {
      final kv = InMemoryKv();
      await kv.write('ogl.journal.broken', '{"id": 这不是合法 JSON');

      final journal = WriteJournal(store: kv);
      expect(await journal.records(), isEmpty);
      expect(
        (await kv.keys()).where((String k) => k == 'ogl.journal.broken'),
        isEmpty,
        reason: '损坏条目应被清掉',
      );
    });

    test('未确认的危险操作在重放时必须保持 pending（绝不静默放弃）', () async {
      final kv = InMemoryKv();
      final journal = WriteJournal(store: kv);
      final remote = ChaosRemote()..seed(_key(), 'old', 'sha-old');
      final cache = RepositoryCache(
        remote: remote,
        index: kv,
        blobs: InMemoryFileStore(),
        readbackDelay: Duration.zero,
      )..attachJournal(journal);

      // 用户已确认过一次，但远端挂了 ⇒ 记录留在队列里。
      remote.failNextWrite = StateError('断网（模拟）');
      final first = await cache.write(
        _intent(content: 'danger', baseSha: 'sha-old', dangerous: true),
        confirmed: true,
      );
      expect(first.ok, isFalse);
      expect(await journal.pendingCount(), 1);

      // 重启后用户还没点头：重放**不能**把它当成语义冲突丢掉。
      final results = await cache.replayPending();
      expect(results.single.conflict, WriteConflict.needsConfirmation);
      expect(
        await journal.pendingCount(),
        1,
        reason: '未确认 ≠ 放弃：用户排队的意图必须保住，等他点头',
      );
    });
  });

  group('并发风暴与模糊输入', () {
    test('同一键 500 路并发写 ⇒ 不串味、不留幽灵状态、无异常逃逸', () async {
      final kv = InMemoryKv();
      final journal = WriteJournal(store: kv);
      final remote = ChaosRemote()..seed(_key(), 'v0', 'sha-0');
      final cache = RepositoryCache(
        remote: remote,
        index: kv,
        blobs: InMemoryFileStore(),
        readbackDelay: Duration.zero,
      )..attachJournal(journal);

      final outcomes = await Future.wait(<Future<WriteOutcome>>[
        for (var i = 0; i < 500; i++)
          cache.write(_intent(content: 'v$i', baseSha: 'sha-0')),
      ]);

      expect(outcomes.where((WriteOutcome o) => o.ok).length, 1,
          reason: 'D2 之后只有第一个能成功，其余必须被拦下');
      expect(await cache.localCount(), 1, reason: '同一键只能有一个缓存条目');
      expect(remote.store.length, 1);
      expect(await journal.pendingCount(), 0, reason: '被 D1/D2 拦下的意图不得污染待同步队列');
      for (final outcome in outcomes.where((WriteOutcome o) => !o.ok)) {
        expect(
          outcome.conflict,
          WriteConflict.staleSha,
          reason: '失败必须**可解释**，不允许出现未分类异常级失败',
        );
      }
    });

    test('模糊测试：随机垃圾输入不得让解析器抛异常', () {
      final random = Random(20261001);
      for (var round = 0; round < 500; round++) {
        final buffer = StringBuffer();
        for (var i = 0; i < random.nextInt(80); i++) {
          buffer.writeCharCode(random.nextInt(0x2FFF));
        }
        final junk = buffer.toString();

        expect(
          () => JournalRecord.fromJson(<String, dynamic>{'id': junk}),
          returnsNormally,
        );
        expect(() => CacheKey.decode(junk), returnsNormally);
        expect(() => CacheKey.decode(junk), returnsNormally);
      }
    });

    test('模糊测试：合法键编码往返必须恒等', () {
      final random = Random(7);
      for (var round = 0; round < 300; round++) {
        final key = CacheKey(
          scope: CacheScope(
            schemaVersion: 1 + random.nextInt(3),
            accountId: 'acct-${random.nextInt(9)}',
            repo: 'org${random.nextInt(9)}/repo',
            branch: 'b${random.nextInt(9)}',
          ),
          path: 'lib/f${random.nextInt(1000)}.dart',
        );
        final decoded = CacheKey.decode(key.encode());
        expect(decoded, isNotNull);
        expect(decoded!.encode(), key.encode(), reason: '编解码必须是无损往返');
      }
    });
  });
}
