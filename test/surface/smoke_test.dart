/// 展示层冒烟测试：关键渲染路径不崩、关键三态可见。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/async.dart';
import 'package:ohgithublost/surface/app/og_l_app.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';
import 'package:ohgithublost/surface/widgets/readme_view.dart';

/// 把 zh 分片注入 i18n 内核（测试环境读不到 assets）。
void _loadZh() {
  final Map<String, Map<String, String>> pages =
      <String, Map<String, String>>{};
  for (final String page in <String>['shell', 'common']) {
    final Object? decoded =
        jsonDecode(File('assets/i18n/zh/$page.json').readAsStringSync());
    pages[page] = <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (decoded as Map<Object?, Object?>).entries)
        '${e.key}': '${e.value}',
    };
  }
  OgLI18n.instance.debugInject('zh', pages);
}

void main() {
  setUpAll(_loadZh);
  testWidgets('启动失败页：原因原样呈现（不静默降级）', (WidgetTester tester) async {
    await tester.pumpWidget(
      const OgLBootFailureApp(message: '引导清单签名校验失败'),
    );
    expect(find.text('启动被拒绝'), findsOneWidget);
    expect(find.textContaining('引导清单签名校验失败'), findsOneWidget);
  });

  testWidgets('AsyncView：加载中转圈 → 数据渲染', (WidgetTester tester) async {
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () async => 42,
      isEmpty: (int value) => false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncView<int>(
            controller: c,
            builder: (BuildContext context, int value) => Text('数据=$value'),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await c.load();
    await tester.pump();
    expect(find.text('数据=42'), findsOneWidget);
  });

  testWidgets('AsyncView：空态文案（不是加载中）', (WidgetTester tester) async {
    final AsyncController<List<int>> c = AsyncController<List<int>>(
      label: '测试',
      loader: () async => const <int>[],
      isEmpty: (List<int> value) => value.isEmpty,
    );
    await c.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncView<List<int>>(
            controller: c,
            emptyText: '空空如也',
            builder: (BuildContext context, List<int> value) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(find.text('空空如也'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('AsyncView：软错误保留内容（嵌入滚动视图不崩）', (WidgetTester tester) async {
    int calls = 0;
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () async {
        calls += 1;
        if (calls == 2) {
          throw Exception('刷新失败演示');
        }
        return 1;
      },
      isEmpty: (int value) => false,
    );
    await c.load();
    await c.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              AsyncView<int>(
                controller: c,
                fill: false,
                builder: (BuildContext context, int value) => Text('内容=$value'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('内容=1'), findsOneWidget);
    expect(find.textContaining('刷新失败演示'), findsOneWidget);
  });

  testWidgets('ReadmeView：Markdown 渲染成组件树', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReadmeView(markdown: '# 标题\n\n正文内容'),
          ),
        ),
      ),
    );
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(ReadmeView), findsOneWidget);
  });
}
