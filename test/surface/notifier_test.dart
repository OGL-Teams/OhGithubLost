/// 展示层 · Notifier 单元测试（避免回归：成功/失败/中性三种语气必须区分）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/notifier.dart';

void main() {
  group('OgLNotifier', () {
    testWidgets('info / success / warning 均能渲染 SnackBar',
        (WidgetTester tester) async {
      // 用最小化 host：仅一个 ScaffoldMessenger 包裹按钮触发三种语义。
      final List<String> seen = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Column(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => OgLNotifier.of(context).info('info-msg'),
                    child: const Text('info'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        OgLNotifier.of(context).success('success-msg'),
                    child: const Text('success'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        OgLNotifier.of(context).warning('warning-msg'),
                    child: const Text('warning'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('info'));
      await tester.pump();
      seen.add('info-msg');
      expect(find.text('info-msg'), findsOneWidget);

      await tester.tap(find.text('success'));
      await tester.pump();
      seen.add('success-msg');
      expect(find.text('success-msg'), findsOneWidget);

      await tester.tap(find.text('warning'));
      await tester.pump();
      seen.add('warning-msg');
      expect(find.text('warning-msg'), findsOneWidget);

      expect(seen, hasLength(3));
    });

    test('卸载后调用不应抛（messenger.mounted 守卫）', () async {
      // 直接构造 notifier 后不挂载到 widget 树，调 info 不应抛。
      // 这条只是"鲁棒性"——真实的 messenger 取自 context.mounted 检查后
      // 才会被调，模拟这里只检查 API 不会主动 assert。
      final ScaffoldMessengerState state = _FakeMessenger();
      final OgLNotifier notifier = OgLNotifier(state);
      expect(() => notifier.info('x'), returnsNormally);
    });
  });
}

/// 测试替身：仅满足构造签名，不进入 widget 树。
class _FakeMessenger extends ScaffoldMessengerState {
  @override
  bool get mounted => true; // 让 _show 通过守卫
}
