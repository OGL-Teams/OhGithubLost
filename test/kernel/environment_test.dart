/// L0 内核级 · 环境自检扩展点测试。
///
/// 要点：自检是"只读报告"，**单项失败绝不能拖垮启动**。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/environment.dart';

/// 可控自检项。
class _FakeProbe implements KernelEnvironmentProbe {
  _FakeProbe({
    required this.id,
    this.ok = true,
    this.error,
    this.delay = Duration.zero,
  });

  @override
  final String id;

  final bool ok;
  final Object? error;
  final Duration delay;
  int calls = 0;

  @override
  String get title => '自检-$id';

  @override
  Future<KernelProbeResult> run() async {
    calls++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return KernelProbeResult(
      ok: ok,
      summary: ok ? '正常' : '异常',
      detail: <String, Object?>{'id': id},
    );
  }
}

void main() {
  group('注册与封存', () {
    test('注册后可见，重复 ID 被拒绝', () {
      final registry = KernelProbeRegistry();
      registry.register(_FakeProbe(id: 'a'));
      expect(registry.probes.length, 1);
      expect(
        () => registry.register(_FakeProbe(id: 'a')),
        throwsA(isA<KernelProbeError>()),
      );
    });

    test('封存后禁止注册与移除（保证启动行为可复现）', () {
      final registry = KernelProbeRegistry();
      registry.register(_FakeProbe(id: 'a'));
      registry.seal();
      expect(registry.isSealed, isTrue);
      expect(
        () => registry.register(_FakeProbe(id: 'b')),
        throwsA(isA<KernelProbeError>()),
      );
      expect(
        () => registry.remove('a'),
        throwsA(isA<KernelProbeError>()),
      );
    });

    test('未封存时可移除', () {
      final registry = KernelProbeRegistry();
      registry.register(_FakeProbe(id: 'a'));
      registry.remove('a');
      expect(registry.probes, isEmpty);
    });
  });

  group('执行', () {
    test('按注册顺序执行并记录耗时', () async {
      final registry = KernelProbeRegistry();
      final first = _FakeProbe(id: 'a');
      final second = _FakeProbe(id: 'b', ok: false);
      registry.register(first);
      registry.register(second);

      final reports = await registry.runAll();

      expect(reports.map((KernelProbeReport r) => r.id), <String>['a', 'b']);
      expect(reports.first.result.ok, isTrue);
      expect(reports.first.title, '自检-a');
      expect(reports.last.result.ok, isFalse);
      expect(first.calls, 1);
      expect(second.calls, 1);
      expect(reports.first.toJson()['id'], 'a');
    });

    test('单项抛异常 → 该项 ok=false，其余照常执行', () async {
      final registry = KernelProbeRegistry();
      registry
          .register(_FakeProbe(id: 'boom', error: const FormatException('坏了')));
      final after = _FakeProbe(id: 'after');
      registry.register(after);

      final reports = await registry.runAll();

      expect(reports.length, 2);
      expect(reports.first.result.ok, isFalse);
      expect(reports.first.result.summary, contains('自检异常'));
      expect(after.calls, 1, reason: '前一项失败不得阻断后续');
    });

    test('超时 → 该项 ok=false（自检不得拖死启动）', () async {
      final registry = KernelProbeRegistry();
      registry.register(
        _FakeProbe(id: 'slow', delay: const Duration(seconds: 2)),
      );
      final reports = await registry.runAll(
        timeout: const Duration(milliseconds: 30),
      );
      expect(reports.single.result.ok, isFalse);
      expect(reports.single.result.summary, contains('自检异常'));
    });

    test('clear 可复位（重启场景）', () {
      final registry = KernelProbeRegistry();
      registry.register(_FakeProbe(id: 'a'));
      registry.seal();
      registry.clear();
      expect(registry.probes, isEmpty);
      expect(registry.isSealed, isFalse);
      registry.register(_FakeProbe(id: 'b')); // 复位后能再注册
      expect(registry.probes.length, 1);
    });
  });

  group('结果序列化', () {
    test('带 detail 与不带 detail 都能序列化', () {
      const withDetail = KernelProbeResult(
        ok: true,
        summary: 'ok',
        detail: <String, Object?>{'k': 'v'},
      );
      const without = KernelProbeResult(ok: false, summary: 'bad');
      expect(withDetail.toJson()['detail'], <String, Object?>{'k': 'v'});
      expect(without.toJson().containsKey('detail'), isFalse);
      expect(without.toString(), contains('FAIL'));
    });
  });
}
