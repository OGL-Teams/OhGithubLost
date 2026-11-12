/// L3 · 「查看下载」通知动作测试（根 Navigator 机制）。
///
/// 背景：`OgLDownloadNotice.show` 捕获的是**发起页**的 context，SnackBar
/// 常驻 8s，期间用户可能已离开该页 —— 用旧 context push 不可靠。修复后
/// 跳转一律走应用根 Navigator（`OgLApp.navigatorKey`）。
///
/// 测试分层：源码断言把**三级跳转优先级**、降级路径与重名裁决钉进源码。
/// 真实推入 DownloadManagerPage 需要完整 SurfaceBridge 装配 + 真机验收
/// （见 docs/LTS_1260_CHECKLIST.md），不在 widget 测试里模拟。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(source, contains('finalPath = unique'),
        reason: '后端返回完整新路径，snapshot.savePath 必须同步更新');
    expect(source, contains('_retrySavePaths[id] = knownPath'),
        reason: '同 id 重试必须记住上一轮裁决后的路径（只记 id 会退回原名覆盖用户文件）');
    expect(source, contains('retryPath = _retrySavePaths.remove(id)'),
        reason: '再入队时消费并复用上一轮路径');
    expect(source, contains('await _backend.enqueue(finalSpec)'),
        reason: '单连接入队必须用改名后的 spec（旧局部变量会覆盖用户文件）');
    expect(source, contains('finalPath.isNotEmpty'), reason: '分片分支必须用裁决后的路径判定');
    // resume 不得抢跑分片（普通库任务断点续传应走 _backend.resume）
    expect(source, contains('final bool wasRanged'),
        reason: 'resume 必须区分分片任务与库任务');
    expect(source, contains('if (wasRanged && _specs.containsKey(id)'),
        reason: '只有原分片任务才重启分片引擎');
    // 数据无价：不允许任何「直接覆盖既有文件」的旁路
    expect(source, isNot(contains('// motion-allow: overwrite')),
        reason: '重名覆盖不得以任何豁免注释形式潜入');
  });

  test('后端顺延实现钉进源码（stem (i).ext 探测到第一个不存在的序号）', () {
    final String source =
        File('lib/domain/ix/ix_download_backend_io.dart').readAsStringSync();
    expect(source, contains('resolveUniqueSavePath'), reason: '原生后端必须覆写重名裁决');
    expect(source, contains('_resolveDirectory'),
        reason: '_build 与裁决必须共用同一份落盘目录口径');
  });
}
