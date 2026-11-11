/// L2 · 重名文件处理（**自动改名不覆盖**）回归测试。
///
/// 背景：旧实现把「目标路径已存在同名文件」直接交给下载器合并覆盖 ——
/// 用户自己放在下载目录里的 `a.zip` 会被静默替换（数据无价）。
///
/// 本组测试注入一个**真实临时目录**后端，钉死三条语义：
/// 1. 不同任务：同目录已有 `a.zip` → 入队后实际落盘 `a (1).zip`；
/// 2. 同 id 重试（移除后重新下载同一条）：仍写 `a.zip`（覆盖自己上一轮
///    的成品是正确语义）；
/// 3. 多个同名并存：`a (1).zip` 也被占用 → 顺延到 `a (2).zip`。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ix/ix_download.dart';
import 'package:ohgithublost/domain/ix/ix_download_backend_io.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ogl_dedup_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('IoDownloadBackend.resolveUniqueSavePath', () {
    test('目标不存在 → 原样返回', () async {
      final IoDownloadBackend backend = IoDownloadBackend();
      addTearDown(backend.dispose);
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
      final IoDownloadBackend backend = IoDownloadBackend();
      addTearDown(backend.dispose);
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
      final IoDownloadBackend backend = IoDownloadBackend();
      addTearDown(backend.dispose);
      const IxDownloadSpec spec = IxDownloadSpec(
        id: 'other:a.zip#u',
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
        folder: 'other',
      );
      final String path = '${tmp.path}${Platform.pathSeparator}a.zip';
      File(path).writeAsStringSync('x');
      File('${tmp.path}${Platform.pathSeparator}a (1).zip')
          .writeAsStringSync('y');
      final String resolved = await backend.resolveUniqueSavePath(
        spec,
        intendedPath: path,
      );
      expect(resolved, '${tmp.path}${Platform.pathSeparator}a (2).zip');
    });
  });

  group('IxDownloadManager.enqueue 重名裁决', () {
    // 真后端 + 落盘目录指向测试临时目录（绕开 background_downloader
    // 的平台通道），专测中枢层与 `resolveUniqueSavePath` 的协作。
    late IoDownloadBackend backend;
    late IxDownloadManager manager;
    late Directory downloadDir;

    setUp(() {
      downloadDir = Directory.systemTemp.createTempSync('ogl_dedup_dl');
      backend = _TempDirBackend(downloadDir.path);
      manager = IxDownloadManager(backend: backend);
    });

    tearDown(() {
      manager.dispose();
      downloadDir.deleteSync(recursive: true);
    });

    test('同目录已有 a.zip 时入队 → 实际落盘 a (1).zip', () async {
      final String existing =
          '${downloadDir.path}${Platform.pathSeparator}other';
      Directory(existing).createSync(recursive: true);
      File('$existing${Platform.pathSeparator}a.zip')
          .writeAsStringSync('user-data');

      final IxDownloadTask task = await manager.enqueue(
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
      );
      expect(
        task.savePath.endsWith('a (1).zip'),
        isTrue,
        reason: '实际 savePath=${task.savePath}',
      );
      expect(task.fileName, 'a (1).zip');
      // 用户已有文件未被触碰。
      expect(
        File('$existing${Platform.pathSeparator}a.zip').readAsStringSync(),
        'user-data',
      );
    });

    test('同 id 重试（移除后重新下载同一条）→ 仍保持 a.zip', () async {
      final String folder = '${downloadDir.path}${Platform.pathSeparator}other';
      Directory(folder).createSync(recursive: true);
      // 上一轮成品已落盘（同 id 同路径）。
      File('$folder${Platform.pathSeparator}a.zip')
          .writeAsStringSync('previous-round');

      final IxDownloadTask first = await manager.enqueue(
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
      );
      // 第一轮：目录里已有同名文件（上一轮成品）→ 若无豁免会改名。
      // 移除（模拟「重试前清记录」的既有口径）→ 重新入队。
      await manager.remove(first.id);
      final IxDownloadTask second = await manager.enqueue(
        url: 'https://example.com/a.zip',
        fileName: 'a.zip',
      );
      expect(
        second.savePath.endsWith('a.zip'),
        isTrue,
        reason: '同 id 重试必须保持原文件名（覆盖自己上一轮的成品）；'
            '实际=${second.savePath}',
      );
      expect(second.fileName, 'a.zip');
    });
  });
}

/// 真后端 + 落盘目录指向测试临时目录（绕开平台通道）。
class _TempDirBackend extends IoDownloadBackend {
  _TempDirBackend(this.root);

  final String root;

  @override
  Future<String> pathFor(IxDownloadSpec spec) async =>
      '$root${Platform.pathSeparator}${spec.folder}'
      '${Platform.pathSeparator}${spec.fileName}';
}
