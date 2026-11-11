/// L0 内核级 · 桥注册表封存守卫（批 9 交叉 X-04）。
///
/// 此前 `seal()` 只置位，某层漏注册桥不报错，要到运行期 `resolve()`
/// 才炸；现在装配根声明期望键集合，封存即校验。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/bridge_registry.dart';

void main() {
  group('KernelBridgeRegistry.seal', () {
    test('期望键齐全时封存成功', () {
      final KernelBridgeRegistry bridges = KernelBridgeRegistry();
      bridges.register('base', Object());
      bridges.register('domain', Object());
      bridges.register('surface', Object());
      bridges.seal(expected: const <String>{'base', 'domain', 'surface'});
      expect(bridges.isSealed, isTrue);
      expect(
          bridges.snapshot.keys.toSet(), <String>{'base', 'domain', 'surface'});
    });

    test('漏注册任一桥 → 封存被拒绝并抛出明确错误', () {
      final KernelBridgeRegistry bridges = KernelBridgeRegistry();
      bridges.register('base', Object());
      bridges.register('surface', Object());
      expect(
        () =>
            bridges.seal(expected: const <String>{'base', 'domain', 'surface'}),
        throwsA(isA<KernelBridgeError>().having(
          (KernelBridgeError e) => e.message,
          'message',
          contains('domain'),
        )),
      );
      expect(bridges.isSealed, isFalse, reason: '校验失败不得置封存位');
    });

    test('封存后禁止再注册（原有语义不变）', () {
      final KernelBridgeRegistry bridges = KernelBridgeRegistry();
      bridges.seal();
      expect(
        () => bridges.register('base', Object()),
        throwsA(isA<KernelBridgeError>()),
      );
    });

    test('未传 expected 时保持旧行为（单测最小注册表可用）', () {
      final KernelBridgeRegistry bridges = KernelBridgeRegistry();
      bridges.seal();
      expect(bridges.isSealed, isTrue);
    });
  });
}
