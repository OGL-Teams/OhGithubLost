/// L1 底座级 · 装配引导测试：**平台存储接线**与内存兜底。
///
/// 历史缺陷：`PlatformStorage.open()` 从未被调用，真机全部走内存实现，
/// 表现为"登录成功、重启失忆"。本测试锁死两条路径：
/// 1. 成功 → 注入真实实现（IoDiskKv / SecureDiskVault）；
/// 2. 失败 → 退回内存实现，**且错误必须回传**（不允许静默）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/base_bootstrap.dart';
import 'package:ohgithublost/base/disk/disk_bridge.dart';
import 'package:ohgithublost/base/disk/platform_io.dart';

void main() {
  test('成功路径：注入真实平台存储（IoDiskKv / SecureDiskVault）', () async {
    final tmp = await Directory.systemTemp.createTemp('ogl-boot-test');
    addTearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    final result = await baseLayerModulesOnPlatform(rootOverride: tmp.path);
    expect(result.storageError, isNull);

    final disk = result.modules.whereType<DiskModule>().single;
    expect(disk.kv, isA<IoDiskKv>());
    expect(disk.vault, isA<SecureDiskVault>());
  });

  test('失败路径：无法建目录时退回内存，且错误原样带回（不静默）', () async {
    // 用一个"文件"充当根目录 → 目录创建必然失败。
    final tmp = await Directory.systemTemp.createTemp('ogl-boot-fail');
    final asFile = File('${tmp.path}/blocker');
    await asFile.writeAsString('occupied');
    addTearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    final result = await baseLayerModulesOnPlatform(rootOverride: asFile.path);
    expect(result.storageError, isNotNull, reason: '失败必须回传错误（组合根负责大声上报）');

    final disk = result.modules.whereType<DiskModule>().single;
    expect(disk.kv, isNot(isA<IoDiskKv>()), reason: '失败时必须退回内存实现，而不是假装成功');
  });
}
