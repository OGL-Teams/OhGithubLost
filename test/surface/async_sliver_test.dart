/// L3 展示级 · 异步数据区的 **Sliver 懒加载**检查（5.2 性能）。
///
/// 之前 PR / commit 的文件列表是 `ListView(children:[...])` 里套
/// `AsyncView(builder: (c, files) => Column(children: [for ...]))`：
/// 改 300 个文件就一次性构建 300 个 ExpansionTile。改用 [OgLAsyncSliver] 后
/// 交给 `SliverList.builder` **按需构建**——这里把"只构建视口附近"钉成测试。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/async.dart';

/// 推进假时钟：越过 300ms 防抖 + 300ms 最小加载时长，让异步状态真正落定。
///
/// 加载态用的是 CircularProgressIndicator（无限动画），`pumpAndSettle` 在加载
/// 期间永远等不到"没有待绘制帧"，只会超时——所以这里只做定长推进。
Future<void> _settleAsync(WidgetTester tester) async {
  // AsyncController 用真实时间判最小显示时长，runAsync 让真实 timer 完成。
  await tester.runAsync<void>(
      () => Future<void>.delayed(const Duration(milliseconds: 650)));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('OgLAsyncSliver：500 行只构建视口附近的少数行', (WidgetTester tester) async {
    final AsyncController<List<int>> controller = AsyncController<List<int>>(
      label: '测试',
      isEmpty: (List<int> rows) => rows.isEmpty,
      loader: () async => List<int>.generate(500, (int i) => i),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              const SliverToBoxAdapter(child: Text('头部')),
              OgLAsyncSliver<List<int>>(
                controller: controller,
                emptyIcon: Icons.inbox,
                itemCountOf: (List<int> rows) => rows.length,
                itemBuilder:
                    (BuildContext context, List<int> rows, int index) =>
                        SizedBox(height: 40, child: Text('行 $index')),
              ),
            ],
          ),
        ),
      ),
    );
    // ★ 300ms 防抖 + 300ms 最小加载时长：假时钟必须显式推进。
    unawaited(controller.load());
    await _settleAsync(tester);

    // 500 行里只应构建视口附近的一小部分（懒加载生效）。
    final int built = tester.widgetList<Text>(find.byType(Text)).length;
    expect(built, lessThan(60), reason: '一次性构建了 $built 行，懒加载失效');
    expect(find.text('头部'), findsOneWidget);
    expect(find.textContaining('行 0'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('OgLAsyncSliver：空数据走空态（不显示空白）', (WidgetTester tester) async {
    final AsyncController<List<int>> controller = AsyncController<List<int>>(
      label: '测试',
      isEmpty: (List<int> rows) => rows.isEmpty,
      loader: () async => <int>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              OgLAsyncSliver<List<int>>(
                controller: controller,
                emptyIcon: Icons.inbox,
                emptyText: '没有内容',
                itemCountOf: (List<int> rows) => rows.length,
                itemBuilder:
                    (BuildContext context, List<int> rows, int index) =>
                        const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
    unawaited(controller.load());
    await _settleAsync(tester);
    expect(find.text('没有内容'), findsOneWidget);

    controller.dispose();
  });
}
