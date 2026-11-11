/// 展示层 · **真机 UI 反馈**的回归锁（三处布局契约）。
///
/// 背景：一次真机反馈暴露三处 UI 问题，逐像素比对真机截图后定位到根因，
/// 这里把「为什么坏」的**结构性原因**钉成测试，避免下次重构再犯。
///
/// 1. **编辑器工具栏漏缝**：工具栏与代码区背景同色了，但工具栏**没铺满
///    宽度**——横向滚动视图里的 `Row(mainAxisSize: min)` 只有图标那么宽，
///    Material 于是按内容收缩，真机实测灰带只覆盖 x=43..978，两端各露
///    一条 surface 白缝，而下方代码区满宽 x=0..1038。
/// 2. **动态整页空白**：动态行用 `Row(crossAxisAlignment: stretch)` 撑满
///    行高，而纵向 ListView 的子项高度是**无界**的 → release 下断言被剥掉，
///    整行不绘制 → 整个 tab 一个像素都不剩（连空态都没有）。
/// 3. **Issues 筛选胶囊文字溢出**：胶囊行被写死 32dp 高，ListView 上下
///    padding 就吃掉 16dp，标签文字被挤到胶囊背景之外（真机实测底色
///    y=319..341、文字 y=352..374）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/widgets/code_editor_toolbar.dart';
import 'package:ohgithublost/surface/widgets/discover_rows.dart';

/// 取装饰框的左侧边框（[BoxBorder] 基类没有 `left`，需先收窄成 [Border]）。
BorderSide _leftSide(DecoratedBox box) {
  final BoxBorder border = (box.decoration as BoxDecoration).border!;
  return (border as Border).left;
}

// ★ 批 9 · B14：上面三组测试都只 new 组件，页面若弃用它们测试照样绿。
//   这里用源码静态断言把「页面确实接线」也钉住 —— 不做 widget 渲染
//   （页面依赖 SurfaceBridge，测试环境构造成本高），只查真实引用。
String _readSource(String relative) =>
    File('lib/surface/pages/$relative').readAsStringSync();

void main() {
  group('页面接线（组件必须真的被页面使用）', () {
    test('发现页接入 OgLFeedRow 与 OgLIssuesFilterChips', () {
      final String source = _readSource('search_page.dart');
      expect(source, contains('OgLFeedRow('),
          reason: '发现页动态 tab 必须复用 OgLFeedRow');
      expect(source, contains('OgLIssuesFilterChips('),
          reason: '发现页 Issues tab 必须复用 OgLIssuesFilterChips');
      expect(source, contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
          reason: 'Issues 筛选行满宽契约');
    });

    test('代码编辑器页接入 OgLCodeEditorToolbar 且 body 满宽', () {
      final String source = _readSource('code_editor_page.dart');
      expect(source, contains('OgLCodeEditorToolbar('),
          reason: '编辑器页必须复用 OgLCodeEditorToolbar');
      expect(source, contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
          reason: '工具栏与代码区同宽契约');
    });

    test('下拉刷新统一走 OgLRefreshIndicator（不留裸 RefreshIndicator）', () {
      final Directory pages = Directory('lib/surface/pages');
      final List<File> files = pages
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      int wrapped = 0;
      for (final File f in files) {
        final String text = f.readAsStringSync();
        wrapped += 'OgLRefreshIndicator('.allMatches(text).length;
        // 允许包装器自身文件与注释里出现，但页面源码不许裸用。
        final String stripped = text.replaceAll('OgLRefreshIndicator(', '');
        expect(stripped, isNot(contains('RefreshIndicator(')),
            reason: '${f.path} 仍有裸 RefreshIndicator');
      }
      expect(wrapped, greaterThan(0), reason: '包装器没有被任何页面使用');
    });
  });

  group('异步 Sliver 四态（批 9 · B1）', () {
    test('空/错误/加载三态统一走 OgLSurfaceSwitch，data 态保持懒加载', () {
      final String source =
          File('lib/surface/app/async.dart').readAsStringSync();
      final String sliver =
          source.substring(source.indexOf('class OgLAsyncSliver'));
      expect(sliver, contains('OgLSurfaceSwitch('),
          reason: 'AsyncSliver 三态不能是硬切');
      expect(sliver, contains("ValueKey<String>(state)"),
          reason: '状态切换必须带 Key，AnimatedSwitcher 才能识别');
      expect(sliver, contains('SliverList.builder'),
          reason: '数据态必须保留按需构建，不能套动画容器一次建全表');
    });
  });

  group('动态行（OgLFeedRow）', () {
    testWidgets('在无界高度里渲染不抛异常、且内容可见', (WidgetTester tester) async {
      // ★ 无界高度正是 ListView 子项的真实约束；此前 stretch 竖条在此崩掉。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                OgLFeedRow(
                  unread: true,
                  title: '标题行',
                  meta: '仓库 · Issue · 3 小时前',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('标题行'), findsOneWidget);
      expect(find.text('仓库 · Issue · 3 小时前'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未读与已读都有状态竖条（宽度恒定，行不跳动）', (WidgetTester tester) async {
      Widget build(bool unread) => MaterialApp(
            home: Scaffold(
              body: OgLFeedRow(
                unread: unread,
                title: 'T',
                meta: 'M',
                onTap: () {},
              ),
            ),
          );

      await tester.pumpWidget(build(true));
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final BorderSide side = _leftSide(box);
      expect(side.width, greaterThan(0), reason: '未读行必须有状态竖条');

      await tester.pumpWidget(build(false));
      final DecoratedBox box2 = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final BorderSide side2 = _leftSide(box2);
      expect(side2.width, greaterThan(0), reason: '已读行宽度恒定，行不跳动');
    });
  });

  group('Issues 筛选胶囊行（OgLIssuesFilterChips）', () {
    testWidgets('三个胶囊都在、文字落在胶囊内（不被压扁）', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OgLIssuesFilterChips(
              selected: 0,
              labels: const <String>['全部', '我提出的', 'Star 仓库'],
              onSelect: (int index) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('我提出的'), findsOneWidget);
      expect(find.text('Star 仓库'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ★ 文字必须落在胶囊的垂直范围内（此前文字掉到胶囊外面）。
      for (final String label in <String>['全部', '我提出的', 'Star 仓库']) {
        final Rect chip = tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FilterChip),
          ),
        );
        final Rect text = tester.getRect(find.text(label));
        expect(
          text.top >= chip.top - 0.5 && text.bottom <= chip.bottom + 0.5,
          isTrue,
          reason: '「$label」的文字超出了胶囊的垂直范围',
        );
      }
    });

    testWidgets('点击胶囊回调对应下标', (WidgetTester tester) async {
      final List<int> picked = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OgLIssuesFilterChips(
              selected: 0,
              labels: const <String>['全部', '我提出的', 'Star 仓库'],
              onSelect: picked.add,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Star 仓库'));
      await tester.pump();
      expect(picked, <int>[2]);
    });
  });

  group('代码编辑器工具栏（OgLCodeEditorToolbar）', () {
    testWidgets('背景条铺满宽度（不露白缝）', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                OgLCodeEditorToolbar(
                  backgroundColor: const Color(0xFFE2E2E9),
                  canUndo: true,
                  canRedo: false,
                  wrap: false,
                  onUndo: () {},
                  onRedo: () {},
                  onToggleFind: () {},
                  onToggleWrap: () {},
                  onFontSmaller: () {},
                  onFontLarger: () {},
                  onPreview: () {},
                  undoTooltip: '撤销',
                  redoTooltip: '重做',
                  findTooltip: '查找',
                  wrapOnTooltip: '自动换行',
                  wrapOffTooltip: '取消换行',
                  fontSmallerTooltip: '缩小',
                  fontLargerTooltip: '放大',
                  previewTooltip: '预览',
                ),
                const Expanded(
                  child: ColoredBox(
                    color: Color(0xFFE2E2E9),
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // ★ 工具栏背景条必须与下方代码区**同宽**（真机上曾窄一截、两端露白缝）。
      final double screen = tester.getSize(find.byType(Scaffold)).width;
      final double toolbar =
          tester.getSize(find.byType(OgLCodeEditorToolbar)).width;
      expect(toolbar, screen, reason: '工具栏没有铺满宽度，两端会露白缝');
      expect(tester.takeException(), isNull);
    });
  });
}
