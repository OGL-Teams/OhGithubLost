/// L3 展示级 · 长日志分块虚拟化 + 5.0 新设置项检查。
///
/// 覆盖用户明确的 5.0 要求：
/// 1. Actions 长日志「懒加载 / 虚拟化 / 分块渲染」——**不能一次性排版全部行**；
/// 2. 下载并发档位只给固定值，非法值回落默认（不因为手改配置而崩）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/settings.dart';
import 'package:ohgithublost/surface/widgets/log_body.dart';

void main() {
  group('OgLLogBody（长日志分块虚拟化）', () {
    testWidgets('1200 行日志只渲染视口附近的分块（不是全部）', (WidgetTester tester) async {
      final String text = List<String>.generate(
        1200,
        (int i) => 'line $i',
      ).join('\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 400, child: OgLLogBody(text: text)),
          ),
        ),
      );
      // 每块 120 行 → 共 10 块；视口只应该构建前几块。
      final int rendered = tester.widgetList<Text>(find.byType(Text)).length;
      expect(rendered, lessThan(10), reason: '虚拟化失效：一次性构建了全部 $rendered 块');
      expect(rendered, greaterThan(0), reason: '至少渲染首屏');
      // 首行必须在（内容没丢）。
      expect(find.textContaining('line 0'), findsOneWidget);
    });

    testWidgets('小文本同样正常（一块内）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: OgLLogBody(text: 'a\nb\nc'),
            ),
          ),
        ),
      );
      expect(find.textContaining('a'), findsOneWidget);
    });

    testWidgets('块大小可配（chunkLines 生效）', (WidgetTester tester) async {
      final String text =
          List<String>.generate(300, (int i) => 'x$i').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: OgLLogBody(text: text, chunkLines: 300),
            ),
          ),
        ),
      );
      expect(find.byType(Text), findsOneWidget, reason: '一整块 → 只一个 Text');
    });
  });

  group('下载并发设置（OgLSettings.downloadConnections）', () {
    test('只允许给定档位', () {
      expect(OgLSettings.downloadConnectionChoices, <int>[1, 2, 4, 8, 16, 32]);
      expect(
        OgLSettings.downloadConnectionChoices
            .contains(OgLSettings.kOgLDefaultDownloadConnections),
        isTrue,
        reason: '默认值必须在允许档位里',
      );
    });

    test('缺字段 → 默认值；非法值 → 默认值；合法值保留', () {
      expect(OgLSettings.fromJson(null).downloadConnections,
          OgLSettings.kOgLDefaultDownloadConnections);
      expect(
          OgLSettings.fromJson(<String, Object?>{'downloadConnections': 3})
              .downloadConnections,
          OgLSettings.kOgLDefaultDownloadConnections);
      expect(
          OgLSettings.fromJson(<String, Object?>{'downloadConnections': 99})
              .downloadConnections,
          OgLSettings.kOgLDefaultDownloadConnections);
      expect(
          OgLSettings.fromJson(<String, Object?>{'downloadConnections': 8})
              .downloadConnections,
          8);
    });

    test('字符串数字也能读（手改配置文件）', () {
      expect(
          OgLSettings.fromJson(<String, Object?>{'downloadConnections': '2'})
              .downloadConnections,
          2);
      expect(
        OgLSettings.fromJson(<String, Object?>{'downloadConnections': 'abc'})
            .downloadConnections,
        OgLSettings.kOgLDefaultDownloadConnections,
      );
    });

    test('序列化 → 反序列化保持', () {
      final OgLSettings custom =
          OgLSettings.defaults.copyWith(downloadConnections: 2);
      expect(custom.encode(), contains('"downloadConnections":2'));
      final Map<String, Object?> round =
          jsonDecode(custom.encode()) as Map<String, Object?>;
      expect(OgLSettings.fromJson(round).downloadConnections, 2);
    });
  });
}
