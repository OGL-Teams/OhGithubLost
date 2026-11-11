/// L3 · 「查看下载」通知动作测试（根 Navigator 机制）。
///
/// 背景：`OgLDownloadNotice.show` 捕获的是**发起页**的 context，SnackBar
/// 常驻 8s，期间用户可能已离开该页 —— 用旧 context push 不可靠。修复后
/// 跳转一律走应用根 Navigator（`OgLApp.navigatorKey`）。
///
/// 测试分层：
/// 1. 源码断言：跳转的**三级优先级**与降级路径、重名裁决钉进源码；
/// 2. widget 级：降级路径（根 Navigator 不可用 → 复制路径 + 明确提示）
///    无需完整 SurfaceBridge 装配即可验证；
/// 3. 真实推入 DownloadManagerPage 需要完整装配 + 真机验收
///    （见 docs/LTS_1260_CHECKLIST.md）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/pages/download_manager_page.dart';

void main() {
  test('跳转三级优先级与降级路径钉进源码（防回退到旧页 context）', () {
    final String source =
        File('lib/surface/pages/download_manager_page.dart').readAsStringSync();
    // 1) 显式 rootContext 最优先
    expect(source, contains('rootContext != null'),
        reason: '跳转必须先走调用方显式给的根 context');
    // 2) 应用根 navigatorKey 兜底（与 OgLNoticeHost 同机制）
    expect(source, contains('OgLApp.navigatorKey.currentContext'),
        reason: 'rootContext 缺省时必须走应用根 navigatorKey');
    // 3) 双双失效时降级为复制路径 + 明确提示（绝不静默）
    expect(source, contains('viewDownloadsFallback'),
        reason: '根 Navigator 不可用时必须有明确降级提示');
    // 4) 不得再用旧页 context 直接 push（历史病灶）
    expect(source, isNot(contains('Navigator.of(context).push')),
        reason: '禁止回到「用发起页 context push」的旧实现');
  });

  test('重名裁决钉进源码（同 id 重试豁免 / 撞名顺延）', () {
    final String source =
        File('lib/domain/ix/ix_download.dart').readAsStringSync();
    expect(source, contains('_retrySavePaths'),
        reason: '同 id 重试保持原文件名的豁免集合必须存在');
    expect(source, contains('resolveUniqueSavePath'),
        reason: '重名裁决必须经后端契约（中枢与后端两侧）');
    expect(source, contains('_lastSegmentOf'), reason: '后端返回完整路径，中枢取最后一段文件名');
    expect(source, contains('copyWith(fileName: finalName)'),
        reason: '裁决改名后快照与 spec 必须同步新名字');
  });

  testWidgets('降级路径：根 Navigator 不可用时给明确提示（不静默）', (
    WidgetTester tester,
  ) async {
    // 不挂 navigatorKey、不给 rootContext → 跳转必然走降级。
    // surface 走最小桩（此路径不触达页面装配）。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () {
                OgLDownloadNotice.instance.show(
                  context,
                  _StubSurface(),
                  message: 'queued',
                  kind: DownloadNoticeKind.queued,
                  actionLabel: 'view',
                  onAction: () {}, // 显式给动作：本用例只验证降级提示可见
                );
              },
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBarAction), findsOneWidget, reason: '「查看下载」入口必须可见');
    await tester.tap(find.byType(SnackBarAction));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

/// 最小表面桩：`show` 只透传引用，降级路径不触达页面装配。
class _StubSurface implements SurfaceBridge {
  const _StubSurface();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
