/// L3 展示级 · 异步数据区的 **Sliver 懒加载**检查（5.2 性能）。
///
/// 之前 PR / commit 的文件列表是 `ListView(children:[...])` 里套
/// `AsyncView(builder: (c, files) => Column(children: [for ...]))`：
/// 改 300 个文件就一次性构建 300 个 ExpansionTile。改用 [OgLAsyncSliver] 后
/// 交给 `SliverList.builder` **按需构建**——这里把"只构建视口附近"钉成测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/async.dart';

void main() {
  testWidgets('OgLAsyncSliver：500 行只构建视口附近的少数行', (WidgetTester tester) async {
    final AsyncController<List<int>> controller = AsyncController<List<int>>(
      label: '测试',
      isEmpty: (List<int> rows) => rows.isEmpty,
      loader: () async => List<int>.generate(500, (int i) => i),
    );
    await controller.load();

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
    await tester.pumpAndSettle();

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
    await controller.load();

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
    await tester.pumpAndSettle();
    expect(find.text('没有内容'), findsOneWidget);

    controller.dispose();
  });
}
