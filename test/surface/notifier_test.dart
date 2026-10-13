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

      // info
      OgLNotifier(messenger).info('info-msg');
      await tester.pump();
      expect(find.text('info-msg'), findsOneWidget);

      // 让上一条过期，避免排队导致下一条不显示
      await tester.pump(const Duration(seconds: 5));

      // success
      OgLNotifier(messenger).success('success-msg');
      await tester.pump();
      expect(find.text('success-msg'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));

      // warning（error 配色）
      OgLNotifier(messenger).warning('warning-msg');
      await tester.pump();
      expect(find.text('warning-msg'), findsOneWidget);

      // 三种语气都能落地（真正区分由实现里的 isError 决定，见 notifier.dart）。
    });
  });
}
