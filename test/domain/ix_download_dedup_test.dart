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

const IxDownloadSpec _spec = IxDownloadSpec(
  id: 'other:a.zip#u',
  url: 'https://example.com/a.zip',
  fileName: 'a.zip',
  folder: 'other',
);

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
      final String path = '${tmp.path}${Platform.pathSeparator}a.zip';
      expect(
        await backend.resolveUniqueSavePath(_spec, intendedPath: path),
        path,
      );
    });

    test('目标已存在 → 改名 a (1).zip（绝不覆盖）', () async {
      final String path = '${tmp.path}${Platform.pathSeparator}b.zip';
      File(path).writeAsStringSync('user-data');
      final String resolved = await backend.resolveUniqueSavePath(
        _spec,
        intendedPath: path,
      );
      expect(resolved, '${tmp.path}${Platform.pathSeparator}b (1).zip');
      expect(File(path).readAsStringSync(), 'user-data');
    });

    test('a (1).zip 也被占用 → 顺延 a (2).zip', () async {
      final String path = '${tmp.path}${Platform.pathSeparator}c.zip';
      final String one = '${tmp.path}${Platform.pathSeparator}c (1).zip';
      File(path).writeAsStringSync('user-data');
      File(one).writeAsStringSync('user-data-2');
      final String resolved = await backend.resolveUniqueSavePath(
        _spec,
        intendedPath: path,
      );
      expect(resolved, '${tmp.path}${Platform.pathSeparator}c (2).zip');
      expect(File(path).readAsStringSync(), 'user-data');
      expect(File(one).readAsStringSync(), 'user-data-2');
    });

    test('探测异常 → 失败闭合（绝不返回可覆盖路径）', () async {
      // 指向不存在的目录：writeExclusive 必失败且文件不存在。
      // 旧实现 catch → return base（fail-open 覆盖）。
      final String bad = '${tmp.path}${Platform.pathSeparator}no_such_dir'
          '${Platform.pathSeparator}d.zip';
      expect(
        () => backend.resolveUniqueSavePath(_spec, intendedPath: bad),
        throwsA(isA<FileSystemException>()),
        reason: 'C-03：无法创建占位时必须抛错，不得回退到原路径',
      );
    });
  });

  group('IxDownloadManager 状态机契约（源码断言）', () {
    test('裁决失败/await 窗口/retry 兜底/辅助表/速率', () {
      final String source =
          File('lib/domain/ix/ix_download.dart').readAsStringSync();
      expect(source, contains("'重名裁决失败，拒绝覆盖既有文件"),
          reason: 'C-03 裁决异常必须置 failed + 留痕');
      expect(source,
          contains('if (_disposed || !identical(_snapshots[id], queued))'),
          reason: 'C-07 await 窗口后必须二次守卫');
      expect(source, contains("'重试入队失败"), reason: 'C-15 retry 入队异常必须置 failed');
      expect(source, contains('_retrySavePaths.remove(id);'),
          reason: 'C-16 clearFinished 必须清豁免表');
      expect(source, contains('speed < 0'), reason: 'C-09 速率不得为负');
    });
  });
}
