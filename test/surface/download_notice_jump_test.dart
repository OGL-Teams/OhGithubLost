/// L3 · 「查看下载」通知动作跳转测试（根 Navigator 机制）。
///
/// 背景：`OgLDownloadNotice.show` 捕获的是**发起页**的 context，SnackBar
/// 常驻 8s，期间用户可能已离开该页 —— 用旧 context push 不可靠。修复后
/// 跳转一律走应用根 Navigator（`OgLApp.navigatorKey`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/pages/download_manager_page.dart';

void main() {
  testWidgets('通知 action 通过根 navigatorKey 把 DownloadManagerPage 推入', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () {
                OgLDownloadNotice.instance.show(
                  context,
                  _StubSurface(),
                  message: 'queued',
                  kind: DownloadNoticeKind.queued,
                  // 显式给根 context：与 OgLApp.navigatorKey 同一机制的
                  // 测试注入形态（生产路径不传时走 navigatorKey 兜底）。
                  rootContext: key.currentContext,
                );
              },
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump(); // SnackBar 出现
    await tester.pump(); // 动画推进

    // 点「查看下载」动作（label 来自 i18n 的 common/viewDownloads，
    // 测试环境下落到键名或译文 —— 用 SnackBarAction 定位更稳）。
    final Finder action = find.byType(SnackBarAction);
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(
      find.byType(DownloadManagerPage),
      findsOneWidget,
      reason: '「查看下载」必须把下载管理页推入**根** Navigator',
    );
  });
}

/// 最小表面桩：`show` 只需要它引用（跳转时透传给页面），
/// 测试里不触达其成员。
class _StubSurface implements dynamic {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
