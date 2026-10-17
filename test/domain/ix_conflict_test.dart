/// L2 中枢级 · 冲突处置契约测试（**行为断言，不是构造冒烟**）。
///
/// 这一层的价值在于：它是「用户看到什么按钮、能不能点」的唯一契约来源。
/// 底座不认识界面，所以这里一旦退化，界面就会出现
/// 「基线过期时只给覆盖、不给看差异」这类**不可逆的数据损坏风险**。
///
/// 因此本文件断言的不是"能构造出来"，而是四条硬约束：
/// 1. 除「无冲突」外，每种冲突都**必须**给出可执行的处置方式；
/// 2. `staleSha` **必须**包含 `viewDiff`（先看差异再决定，禁止只剩覆盖）；
/// 3. 危险动作（强制覆盖 / 改为新建）**必须**二次确认才放行；
/// 4. 只有服务端错误与回读校验失败可以"重试即自愈"，其余必须人工决策。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ix/ix_conflict.dart';
import 'package:ohgithublost/kernel/contract/disk_types.dart';

void main() {
  group('处置方式契约 · resolveConflictActions', () {
    test('除「无冲突」外，每种冲突都给出至少一种处置方式', () {
      for (final WriteConflict conflict in WriteConflict.values) {
        final List<ConflictAction> actions = resolveConflictActions(conflict);
        if (conflict == WriteConflict.none) {
          expect(actions, isEmpty, reason: '无冲突不应给处置方式');
        } else {
          expect(actions, isNotEmpty, reason: '$conflict 没有任何处置方式');
        }
      }
    });

    test('staleSha 必须可以「查看差异」——禁止只剩覆盖', () {
      final List<ConflictAction> actions =
          resolveConflictActions(WriteConflict.staleSha);
      expect(
        actions,
        contains(ConflictAction.viewDiff),
        reason: '基线过期时若不给看差异，用户只能在"瞎覆盖"与"放弃"之间选',
      );
    });

    test('权限不足只能重新授权——不许给出覆盖选项', () {
      final List<ConflictAction> actions =
          resolveConflictActions(WriteConflict.forbidden);
      expect(actions, <ConflictAction>[ConflictAction.reauthorize]);
      expect(actions, isNot(contains(ConflictAction.forceOverwrite)));
    });

    test('只有 server / verificationFailed 算「重试即自愈」', () {
      for (final WriteConflict conflict in WriteConflict.values) {
        final bool expected = conflict == WriteConflict.server ||
            conflict == WriteConflict.verificationFailed;
        expect(
          IxConflictResolver.isAutoRecoverable(conflict),
          expected,
          reason: '$conflict 的自愈判定不符',
        );
      }
    });

    test('出现过的处置动作与给出的选项一一对应（不丢不多）', () {
      for (final WriteConflict conflict in WriteConflict.values) {
        if (conflict == WriteConflict.none) {
          continue;
        }
        final WriteOutcome outcome = WriteOutcome.failure(conflict);
        final IxConflictPrompt? prompt = IxConflictResolver.describe(outcome);
        expect(prompt, isNotNull);
        expect(
          prompt!.options.map((IxConflictOption o) => o.action).toList(),
          resolveConflictActions(conflict),
        );
      }
    });
  });

  group('危险动作必须二次确认', () {
    test('未确认时 forceOverwrite 不放行', () {
      const IxConflictResolution r =
          IxConflictResolution(action: ConflictAction.forceOverwrite);
      expect(r.allowed, isFalse);
    });

    test('已确认后 forceOverwrite 放行', () {
      const IxConflictResolution r = IxConflictResolution(
        action: ConflictAction.forceOverwrite,
        confirmed: true,
      );
      expect(r.allowed, isTrue);
    });

    test('未确认时 createInstead 不放行', () {
      const IxConflictResolution r =
          IxConflictResolution(action: ConflictAction.createInstead);
      expect(r.allowed, isFalse);
    });

    test('非危险动作无需确认即可放行', () {
      for (final ConflictAction action in <ConflictAction>[
        ConflictAction.viewDiff,
        ConflictAction.pullRemote,
        ConflictAction.retry,
        ConflictAction.reauthorize,
        ConflictAction.retryLater,
      ]) {
        expect(
          IxConflictResolution(action: action).allowed,
          isTrue,
          reason: '$action 不应要求二次确认',
        );
      }
    });
  });

  group('提示生成 · describe', () {
    test('成功结果不产生提示', () {
      expect(
        IxConflictResolver.describe(
          WriteOutcome.failure(WriteConflict.none, detail: '不该显示'),
        ),
        isNull,
      );
    });

    test('必须标记危险选项（覆盖 / 改为新建）', () {
      final IxConflictPrompt? prompt = IxConflictResolver.describe(
        WriteOutcome.failure(WriteConflict.needsConfirmation),
      );
      expect(prompt, isNotNull);
      final IxConflictOption overwrite = prompt!.options.firstWhere(
        (IxConflictOption o) => o.action == ConflictAction.forceOverwrite,
      );
      expect(overwrite.destructive, isTrue, reason: '强制覆盖未标记为危险');
    });

    test('三方内容原样透传给界面（可解释性）', () {
      final WriteOutcome outcome = WriteOutcome.failure(
        WriteConflict.staleSha,
        baseSha: 'base-1',
        sha: 'remote-2',
        detail: '远端有新提交',
        threeWay: const ConflictThreeWay(
          local: '我的改动',
          base: '原始内容',
          remote: '别人的改动',
        ),
      );
      final IxConflictPrompt prompt = IxConflictResolver.describe(outcome)!;
      expect(prompt.baseSha, 'base-1');
      expect(prompt.remoteSha, 'remote-2');
      expect(prompt.previewLocal, '我的改动');
      expect(prompt.previewBase, '原始内容');
      expect(prompt.previewRemote, '别人的改动');
      expect(prompt.detail, '远端有新提交');
    });
  });

  group('三方分歧判定 · ConflictThreeWay.diverged', () {
    test('缺基线 → 不能声称存在真三方分歧', () {
      const ConflictThreeWay t = ConflictThreeWay(local: 'B', remote: 'C');
      expect(t.diverged, isFalse);
    });

    test('远端未改 → 不是分歧', () {
      const ConflictThreeWay t = ConflictThreeWay(
        local: 'B',
        base: 'A',
        remote: 'A',
      );
      expect(t.diverged, isFalse);
    });

    test('本地未改 → 不是分歧', () {
      const ConflictThreeWay t = ConflictThreeWay(
        local: 'A',
        base: 'A',
        remote: 'C',
      );
      expect(t.diverged, isFalse);
    });

    test('本地与远端各改各的 → 是真分歧', () {
      const ConflictThreeWay t = ConflictThreeWay(
        local: 'B',
        base: 'A',
        remote: 'C',
      );
      expect(t.diverged, isTrue);
    });

    test('本地与远端改成一样 → 不是分歧', () {
      const ConflictThreeWay t = ConflictThreeWay(
        local: 'B',
        base: 'A',
        remote: 'B',
      );
      expect(t.diverged, isFalse);
    });
  });

  group('端到端流程 · 三方分歧判定 → 处置', () {
    ConflictThreeWay cw(String? base, String local, String? remote) =>
        ConflictThreeWay(local: local, base: base, remote: remote);

    test('流程 A：远端没动（我改的）→ 无分歧，直接走"远端已同步"路径', () {
      // base == remote：远端与我编辑时的基线一致 → 我的写入不会冲突。
      final ConflictThreeWay c = cw('BASE', '我的改动', 'BASE');
      expect(c.diverged, isFalse);
      expect(c.hasBase, isTrue);
      expect(c.hasRemote, isTrue);
    });

    test('流程 B：双方各改各的 → 判分歧，必须给 viewDiff 且禁止自动覆盖', () {
      final ConflictThreeWay c = cw('BASE\n旧', 'BASE\n我的', 'BASE\n远端');
      expect(c.diverged, isTrue);
      final List<ConflictAction> actions =
          resolveConflictActions(WriteConflict.staleSha);
      expect(actions, contains(ConflictAction.viewDiff));
      // 危险动作（forceOverwrite）必须二次确认才放行。
      expect(
        const IxConflictResolution(
          action: ConflictAction.forceOverwrite,
          confirmed: false,
        ).allowed,
        isFalse,
        reason: '未确认的强制覆盖必须被拦下',
      );
      expect(
        const IxConflictResolution(
          action: ConflictAction.forceOverwrite,
          confirmed: true,
        ).allowed,
        isTrue,
      );
    });

    test('流程 C：两边恰好改成同一内容 → 不是分歧（数据一致的并发写）', () {
      final ConflictThreeWay c = cw('BASE\n旧', 'BASE\n同', 'BASE\n同');
      expect(
        c.diverged,
        isFalse,
        reason: '两边内容一致时宣称"覆盖会丢对方修改"是谎言',
      );
    });

    test('流程 D：拿不到 base 或 remote → 无法判定分歧，保守处理', () {
      expect(cw(null, '我的', '远端').diverged, isFalse);
      expect(cw('BASE', '我的', null).diverged, isFalse);
    });
  });
}
