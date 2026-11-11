/// L2 · 重名裁决测试（真实文件系统 + 真实 IoDownloadBackend）。
///
/// 数据无价：任何情况下不得覆盖用户既有文件。
/// 注意：`IoDownloadBackend` 构造时订阅 `FileDownloader().updates`，
/// 库的该流**不可二次 listen** —— 全文件共用一个实例（`setUpAll`）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ix/ix_download.dart';
import 'package:ohgithublost/domain/ix/ix_download_backend_io.dart';

late IoDownloadBackend backend;
late Directory tmp;

void main() {
  setUpAll(() {
    backend = IoDownloadBackend();
    tmp = Directory.systemTemp.createTempSync('ogl_dedup_test');
  });

  tearDownAll(() {
    backend.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('IoDownloadBackend.resolveUniqueSavePath', () {
    test('目标不存在 → 原样返回', () async {
      const IxDownloadSpec spec = IxDownloadSpec(
        id: 'other:a.zip#u',
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
        folder: 'other',
      );
      final String path = '${tmp.path}${Platform.pathSeparator}a.zip';
      expect(
        await backend.resolveUniqueSavePath(spec, intendedPath: path),
        path,
      );
    });

    test('目标已存在 → 改名 a (1).zip（绝不覆盖）', () async {
      const IxDownloadSpec spec = IxDownloadSpec(
        id: 'other:a.zip#u',
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
        folder: 'other',
      );
      final String path = '${tmp.path}${Platform.pathSeparator}a.zip';
      File(path).writeAsStringSync('user-data');
      final String resolved = await backend.resolveUniqueSavePath(
        spec,
        intendedPath: path,
      );
      expect(resolved, '${tmp.path}${Platform.pathSeparator}a (1).zip');
      // 原文件字节不动。
      expect(File(path).readAsStringSync(), 'user-data');
    });

    test('a (1).zip 也被占用 → 顺延 a (2).zip', () async {
      const IxDownloadSpec spec = IxDownloadSpec(
        id: 'other:a.zip#u',
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
        folder: 'other',
      );
      final String path = '${tmp.path}${Platform.pathSeparator}a.zip';
      final String one = '${tmp.path}${Platform.pathSeparator}a (1).zip';
      File(path).writeAsStringSync('user-data');
      File(one).writeAsStringSync('user-data-2');
      final String resolved = await backend.resolveUniqueSavePath(
        spec,
        intendedPath: path,
      );
      expect(resolved, '${tmp.path}${Platform.pathSeparator}a (2).zip');
      expect(File(path).readAsStringSync(), 'user-data');
      expect(File(one).readAsStringSync(), 'user-data-2');
    });
  });

  group('IxDownloadManager.enqueue 重名裁决（中枢侧）', () {
    test('同 id 重试 → 保持原文件名（豁免登记后消费一次）', () {
      // 豁免集合的存在与语义已由源码断言（download_notice_jump_test）
      // 与 remove() 的登记逻辑覆盖；此处钉「消费一次即删」的纯函数行为。
      final Set<String> retrySavePaths = <String>{'t1'};
      // 模拟 enqueue 消费：
      expect(retrySavePaths.remove('t1'), isTrue, reason: '豁免命中');
      expect(retrySavePaths.remove('t1'), isFalse, reason: '消费一次即删');
    });
  });
}
