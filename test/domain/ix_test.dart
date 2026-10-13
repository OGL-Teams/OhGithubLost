/// L2 中枢级 · 交互逻辑测试（会话 / 批量任务 / 冲突编排 / 通知）。
///
/// 三条主线：
/// 1. **批量必须追问**：没有确认就执行 → 必须被拦下；
/// 2. **通道必须在第一个请求前生效**：否则用户以为走了镜像，其实走了直连；
/// 3. **冲突必须可解释**：基线过期时先给"查看差异"，覆盖必须标危险。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/disk/disk_types.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';
import 'package:ohgithublost/domain/ix/ix_conflict.dart';
import 'package:ohgithublost/domain/ix/ix_notify.dart';
import 'package:ohgithublost/domain/ix/ix_session.dart';
import 'package:ohgithublost/domain/ix/ix_task.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

GhAuthService _auth() => GhAuthService(
      vault: InMemoryVault(),
      store: InMemoryKv(),
    );

IxBatchPlan _plan({bool destructive = false}) => IxBatchPlan(
      title: '批量上传',
      repo: 'alice/blog',
      branch: 'main',
      estimatedRequests: 3,
      items: <IxBatchItem>[
        const IxBatchItem(id: 'a', label: 'a.txt', bytes: 10),
        IxBatchItem(
          id: 'b',
          label: 'b.txt',
          bytes: 20,
          destructive: destructive,
        ),
      ],
    );

WriteOutcome _staleOutcome({String? base, String? remote, String? local}) =>
    WriteOutcome.failure(
      WriteConflict.staleSha,
      detail: '本地基线已过期（D2）',
      sha: 'remote9999',
      baseSha: 'base1111',
      threeWay: ConflictThreeWay(
        local: local ?? '我的内容',
        base: base,
        remote: remote,
      ),
    );

void main() {
  group('会话：上下文与偏好', () {
    late InMemoryKv store;
    late IxSession session;

    setUp(() {
      store = InMemoryKv();
      session = IxSession(auth: _auth(), store: store);
    });

    test('进入仓库 / 目录 / 返回上级', () async {
      await session.enterRepo('alice/blog', branch: 'main');
      expect(session.context.repo, 'alice/blog');
      expect(session.context.path, isEmpty);

      await session.enterDirectory('src/components');
      expect(session.context.breadcrumbs, <String>['src', 'components']);
      expect(await session.goUp(), isTrue);
      expect(session.context.path, 'src');
      expect(await session.goUp(), isTrue);
      expect(session.context.path, isEmpty);
      expect(await session.goUp(), isFalse, reason: '根目录再上不去');
    });

    test('切分支默认回到根目录（不同分支结构可能不同）', () async {
      await session.enterRepo('alice/blog', branch: 'main');
      await session.enterDirectory('deep/path');
      await session.setBranch('dev');
      expect(session.context.branch, 'dev');
      expect(session.context.path, isEmpty);
    });

    test('偏好持久化并可恢复（模拟重启）', () async {
      await session.setViewMode(IxViewMode.grid);
      await session.setSort(IxSortBy.size, order: IxSortOrder.descending);
      await session.rememberSearch('react');
      await session.rememberSearch('vue');
      await session.rememberSearch('react'); // 去重并前置

      final restored = IxSession(auth: _auth(), store: store);
      await restored.restore();
      expect(restored.viewMode, IxViewMode.grid);
      expect(restored.sortBy, IxSortBy.size);
      expect(restored.sortOrder, IxSortOrder.descending);
      expect(restored.searchHistory, <String>['react', 'vue']);
    });

    test('损坏的偏好被清理且不影响启动', () async {
      await store.write('ogl.ix.prefs', '{{{ 不是 JSON');
      await store.write('ogl.ix.context', '也不是');
      final restored = IxSession(auth: _auth(), store: store);
      await restored.restore();
      expect(restored.viewMode, IxViewMode.list);
      expect(store.snapshot.containsKey('ogl.ix.prefs'), isFalse);
      expect(store.snapshot.containsKey('ogl.ix.context'), isFalse);
    });

    test('文件夹置顶 + 排序方向', () async {
      final entries = <GhTreeEntry>[
        const GhTreeEntry(
          path: 'z.txt',
          type: GhTreeEntryType.blob,
          sha: '1',
          size: 100,
        ),
        const GhTreeEntry(path: 'src', type: GhTreeEntryType.tree, sha: '2'),
        const GhTreeEntry(
          path: 'a.txt',
          type: GhTreeEntryType.blob,
          sha: '3',
          size: 5,
        ),
      ];
      final sorted = session.sortEntries(entries);
      expect(sorted.first.path, 'src', reason: '文件夹置顶');
      expect(sorted[1].path, 'a.txt');
      expect(sorted[2].path, 'z.txt');

      await session.setSort(IxSortBy.name, order: IxSortOrder.descending);
      final descending = session.sortEntries(entries);
      expect(descending.first.path, 'src', reason: '置顶优先于方向');
      expect(descending[1].path, 'z.txt');
    });
  });

  group('批量任务：必须先追问用户', () {
    test('没有决策 → 抛 IxConfirmationRequired，且一个请求都不发', () async {
      final diagnostics = KernelDiagnostics();
      final runner = IxTaskRunner(diagnostics: diagnostics);
      var called = 0;

      await expectLater(
        runner.run(
          plan: _plan(),
          work: (IxBatchItem item) async {
            called++;
            return IxTaskResult.success(item.id, item.label);
          },
        ),
        throwsA(isA<IxConfirmationRequired>()),
      );
      expect(called, 0, reason: '未确认前绝不能开工');
      expect(
        diagnostics.logTail.any((e) => e.code == 'OGL-IX-102'),
        isTrue,
        reason: '拦截必须留审计',
      );
    });

    test('显式未确认的决策同样被拦', () async {
      final runner = IxTaskRunner();
      await expectLater(
        runner.run(
          plan: _plan(),
          decision: const IxBatchDecision(
            confirmed: false,
            channel: IxChannel.direct,
          ),
          work: (IxBatchItem item) async =>
              IxTaskResult.success(item.id, item.label),
        ),
        throwsA(isA<IxConfirmationRequired>()),
      );
    });

    test('确认后执行，结果逐条汇报', () async {
      final runner = IxTaskRunner();
      final report = await runner.run(
        plan: _plan(destructive: true),
        decision: const IxBatchDecision(
          confirmed: true,
          channel: IxChannel.auto,
        ),
        work: (IxBatchItem item) async => item.id == 'b'
            ? IxTaskResult.skipped(item.id, item.label, '已存在')
            : IxTaskResult.success(item.id, item.label),
      );

      expect(report.results.length, 2);
      expect(report.succeeded, 1);
      expect(report.skipped, 1);
      expect(report.failed, 0);
      expect(report.allOk, isFalse);
      expect(report.summary, contains('成功 1'));
      expect(report.channel, IxChannel.auto);
    });

    test('单项抛异常不中断整批', () async {
      final runner = IxTaskRunner();
      final report = await runner.run(
        plan: _plan(),
        decision: const IxBatchDecision(
          confirmed: true,
          channel: IxChannel.direct,
        ),
        work: (IxBatchItem item) async {
          if (item.id == 'a') {
            throw StateError('网络炸了');
          }
          return IxTaskResult.success(item.id, item.label);
        },
      );
      expect(report.results.length, 2, reason: '第二项仍要执行');
      expect(report.failed, 1);
      expect(report.succeeded, 1);
      expect(report.results.first.message, contains('网络炸了'));
    });

    test('取消后如实汇报已完成部分', () async {
      final runner = IxTaskRunner();
      final report = await runner.run(
        plan: _plan(),
        decision: const IxBatchDecision(
          confirmed: true,
          channel: IxChannel.direct,
        ),
        work: (IxBatchItem item) async {
          runner.cancel(); // 第一项执行中就取消
          return IxTaskResult.success(item.id, item.label);
        },
      );
      expect(report.cancelled, isTrue);
      expect(report.results.length, 1, reason: '第二项不再执行，但已完成的要留下');
      expect(report.summary, contains('已取消'));
    });

    test('通道切换必须发生在第一个请求之前', () async {
      final runner = IxTaskRunner();
      final sequence = <String>[];

      await runner.run(
        plan: _plan(),
        decision: const IxBatchDecision(
          confirmed: true,
          channel: IxChannel.mirror,
          mirrorId: 'ghproxy',
        ),
        applyChannel: (IxBatchDecision decision) async {
          sequence.add('channel:${decision.mirrorId}');
        },
        work: (IxBatchItem item) async {
          sequence.add('work:${item.id}');
          return IxTaskResult.success(item.id, item.label);
        },
      );

      expect(sequence.first, 'channel:ghproxy');
      expect(sequence[1], 'work:a');
    });

    test('运行器自带通道落地实现时，未显式传 applyChannel 也会生效', () async {
      final applied = <String>[];
      final runner = IxTaskRunner(
        channelApplier: (IxBatchDecision decision) async {
          applied.add('${decision.channel.name}:${decision.mirrorId}');
        },
      );
      expect(runner.hasChannelApplier, isTrue);

      await runner.run(
        plan: _plan(),
        decision: const IxBatchDecision(
          confirmed: true,
          channel: IxChannel.mirror,
          mirrorId: 'ghproxy',
        ),
        work: (IxBatchItem item) async =>
            IxTaskResult.success(item.id, item.label),
      );

      expect(
        applied,
        <String>['mirror:ghproxy'],
        reason: '默认接线也必须真的切通道，不能只写在 UI 上',
      );
    });

    test('运行中不允许再开一批', () async {
      final runner = IxTaskRunner();
      final first = runner.run(
        plan: _plan(),
        decision: const IxBatchDecision(
          confirmed: true,
          channel: IxChannel.direct,
        ),
        work: (IxBatchItem item) async =>
            IxTaskResult.success(item.id, item.label),
      );
      await expectLater(
        runner.run(
          plan: _plan(),
          decision: const IxBatchDecision(
            confirmed: true,
            channel: IxChannel.direct,
          ),
          work: (IxBatchItem item) async =>
              IxTaskResult.success(item.id, item.label),
        ),
        throwsA(isA<StateError>()),
      );
      await first;
    });
  });

  group('冲突编排：必须讲得清', () {
    test('基线过期 → 第一选项必须是"查看差异"，且含"拉取远端"', () {
      final prompt = IxConflictResolver.describe(
        _staleOutcome(base: '基线内容', remote: '别人的内容'),
        subject: 'main.dart',
      );
      expect(prompt, isNotNull);
      expect(
        prompt!.options.map((IxConflictOption o) => o.action).toList(),
        <ConflictAction>[
          ConflictAction.viewDiff,
          ConflictAction.pullRemote,
          ConflictAction.forceOverwrite,
        ],
        reason: '顺序即推荐顺序',
      );
      expect(prompt.options.first.recommended, isTrue);
      expect(
        prompt.options.first.destructive,
        isFalse,
        reason: '危险项绝不能排在首位',
      );
      expect(
        prompt.options.last.destructive,
        isTrue,
        reason: '覆盖必须被标成危险',
      );
      expect(prompt.message, contains('main.dart'));
    });

    test('强制覆盖标记为危险，且二次确认前不许放行', () {
      final prompt = IxConflictResolver.describe(_staleOutcome())!;
      final force = prompt.options.firstWhere(
        (IxConflictOption o) => o.action == ConflictAction.forceOverwrite,
      );
      expect(force.destructive, isTrue);
      expect(prompt.hasDestructive, isTrue);

      const unconfirmed = IxConflictResolution(
        action: ConflictAction.forceOverwrite,
      );
      const confirmed = IxConflictResolution(
        action: ConflictAction.forceOverwrite,
        confirmed: true,
      );
      expect(unconfirmed.allowed, isFalse);
      expect(confirmed.allowed, isTrue);
      expect(
        const IxConflictResolution(action: ConflictAction.viewDiff).allowed,
        isTrue,
        reason: '只读动作无需确认',
      );
    });

    test('三方分歧时文案明确警告"会丢掉对方修改"', () {
      final prompt = IxConflictResolver.describe(
        _staleOutcome(base: 'base', remote: 'remote', local: 'local'),
      )!;
      expect(prompt.diverged, isTrue);
      expect(prompt.message, contains('丢掉'));
      expect(prompt.previewBase, 'base');
      expect(prompt.previewRemote, 'remote');
      expect(prompt.previewLocal, 'local');
    });

    test('拿不到基线时如实说"未知"，不假装知道', () {
      final prompt = IxConflictResolver.describe(_staleOutcome())!;
      expect(prompt.previewBase, isNull);
      expect(prompt.message, contains('你的基线'));
    });

    test('成功结果没有冲突提示', () {
      final ok = WriteOutcome.success(
        entry: CacheEntry(
          key: const CacheKey(
            scope: CacheScope(
              schemaVersion: 1,
              accountId: 'a',
              repo: 'o/r',
              branch: 'main',
            ),
            path: 'x.txt',
          ),
          content: 'c',
          sha: 's',
          fetchedAt: DateTime.now(),
          revision: 1,
        ),
        attempts: 1,
      );
      expect(IxConflictResolver.describe(ok), isNull);
    });

    test('服务端错误可自动重试，不需要用户决策', () {
      expect(
        IxConflictResolver.isAutoRecoverable(WriteConflict.server),
        isTrue,
      );
      expect(
        IxConflictResolver.isAutoRecoverable(WriteConflict.staleSha),
        isFalse,
        reason: '基线过期必须让用户决定',
      );
    });

    test('权限不足只给"重新授权"', () {
      final prompt = IxConflictResolver.describe(
        WriteOutcome.failure(WriteConflict.forbidden, detail: '403'),
      )!;
      expect(prompt.options.length, 1);
      expect(prompt.options.first.action, ConflictAction.reauthorize);
      expect(prompt.message, contains('repo'));
    });
  });

  group('通知中心', () {
    test('同 ID 合并计数而不是堆叠', () {
      final center = IxNotificationCenter();
      for (var i = 0; i < 3; i++) {
        center.push(
          level: IxNotificationLevel.warning,
          title: '写入失败',
          message: 'CACHE',
          code: 'OGL-CONS-202',
          source: 'CACHE',
          subject: 'k1',
        );
      }
      expect(center.items.length, 1);
      expect(center.items.first.count, 3);
      expect(center.items.first.suppressedCount, 2);
    });

    test('不同对象不合并', () {
      final center = IxNotificationCenter();
      center.push(
        level: IxNotificationLevel.warning,
        title: '写入失败',
        message: 'CACHE',
        code: 'OGL-CONS-202',
        source: 'CACHE',
        subject: 'k1',
      );
      center.push(
        level: IxNotificationLevel.warning,
        title: '写入失败',
        message: 'CACHE',
        code: 'OGL-CONS-202',
        source: 'CACHE',
        subject: 'k2',
      );
      expect(center.items.length, 2);
    });

    test('错误级不可关闭，清空时保留', () {
      final center = IxNotificationCenter()
        ..push(
          level: IxNotificationLevel.danger,
          title: '回读校验失败',
          message: 'CACHE',
          code: 'OGL-CONS-205',
          source: 'CACHE',
          dismissible: false,
        )
        ..push(
          level: IxNotificationLevel.info,
          title: '普通提示',
          message: 'IX',
        );
      expect(center.hasDanger, isTrue);
      expect(center.clearDismissible(), 1);
      expect(center.items.length, 1);
      expect(center.items.first.level, IxNotificationLevel.danger);
    });

    test('dismiss 后可查询"曾被关闭"', () {
      final center = IxNotificationCenter()
        ..push(
          level: IxNotificationLevel.warning,
          title: 't',
          message: 'm',
          code: 'C1',
          source: 'S',
        );
      final id = center.items.first.id;
      center.dismiss(id);
      expect(center.items, isEmpty);
      expect(center.wasDismissed(id), isTrue);
    });

    test('从内核诊断导入：只收 warn/error，且遵守水位', () {
      final center = IxNotificationCenter();
      final base = DateTime.now();
      final entries = <KernelLogEntry>[
        KernelLogEntry(
          timestamp: base.subtract(const Duration(minutes: 5)),
          level: KernelLogLevel.info,
          tag: 'KERNEL',
          message: '内核就绪',
        ),
        KernelLogEntry(
          timestamp: base.subtract(const Duration(minutes: 4)),
          level: KernelLogLevel.warn,
          tag: 'CACHE',
          message: '冲突重定基',
          code: 'OGL-CONS-204',
        ),
        KernelLogEntry(
          timestamp: base,
          level: KernelLogLevel.error,
          tag: 'CACHE',
          message: '写后回读不一致',
          code: 'OGL-CONS-205',
        ),
      ];

      expect(center.ingestDiagnostics(entries), 2);
      expect(center.items.length, 2);
      expect(center.hasDanger, isTrue);
      expect(
        center.ingestDiagnostics(entries, since: base),
        0,
        reason: '水位之后的才算新',
      );
    });

    test('超过上限时优先淘汰可关闭条目', () {
      final center = IxNotificationCenter(maxEntries: 3);
      center.push(
        level: IxNotificationLevel.danger,
        title: '安全告警',
        message: 'BOOT',
        code: 'OGL-BOOT-1',
        source: 'BOOT',
        dismissible: false,
      );
      for (var i = 0; i < 5; i++) {
        center.push(
          level: IxNotificationLevel.info,
          title: '提示$i',
          message: 'IX',
          code: 'C$i',
          source: 'IX',
        );
      }
      expect(center.items.length, 3);
      expect(
        center.items.any((IxNotification n) => n.code == 'OGL-BOOT-1'),
        isTrue,
        reason: '安全告警永不被淘汰',
      );
    });
  });
}
