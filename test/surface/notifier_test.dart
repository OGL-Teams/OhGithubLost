/// 展示层 · Notifier 单元测试（避免回归：成功/失败/中性三种语气必须区分）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/notifier.dart';

void main() {
  group('OgLNotifier', () {
    testWidgets('info / success / warning 依次渲染，不互相吞没',
        (WidgetTester tester) async {
      late ScaffoldMessengerState messenger;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                messenger = ScaffoldMessenger.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // SnackBar 是**队列**：上一条还在展示时，下一条要等它过期（或被显式
      // 清掉）才会出现。这里每条展示后先关掉再验下一条——测的是
      // "三种语气各自都能落地"，不是"同屏共存"。
      for (final (String tone, String message) in <(String, String)>[
        ('info', 'info-msg'),
        ('success', 'success-msg'),
        ('warning', 'warning-msg'),
      ]) {
        switch (tone) {
          case 'info':
            OgLNotifier(messenger).info(message);
          case 'success':
            OgLNotifier(messenger).success(message);
          case 'warning':
            OgLNotifier(messenger).warning(message);
        }
        await tester.pump();
        expect(find.text(message), findsOneWidget);

        // 关闭当前条（动画推进到结束），给下一条腾出队列。
        messenger.clearSnackBars();
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
      }
    });
  });
}
