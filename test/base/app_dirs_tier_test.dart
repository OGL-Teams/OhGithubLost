/// L1 底座级 · 落盘位置**分级**（决定"用户到底看不看得见"）。
///
/// 背景：以前只要"能写"就算通过，于是**退回应用私有目录也会被判成已授权**，
/// 用户在文件管理器里根本找不到文件。这里把"可见性"钉成回归护栏。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/app_dirs.dart';

void main() {
  test('落盘位置分级：公共 / 应用外部 / 内部', () {
    expect(OgLAppDirs.tierOf('/storage/emulated/0/ogl'), OgLStorageTier.public);
    expect(
      OgLAppDirs.tierOf(
        '/storage/emulated/0/Android/data/com.example/files/ogl',
      ),
      OgLStorageTier.appExternal,
    );
    expect(
      OgLAppDirs.tierOf('/data/user/0/com.example/files/ogl'),
      OgLStorageTier.internal,
    );
    expect(
      OgLAppDirs.tierOf('/data/data/com.example/files/ogl'),
      OgLStorageTier.internal,
    );
  });

  test('只有公共目录才算"用户可见"（应用外部 / 内部都不算）', () {
    expect(OgLAppDirs.isUserVisible('/storage/emulated/0/ogl'), isTrue);
    // ★ 关键回归：`Android/data/...` 在 Android 11+ 起被系统隐藏，
    //   能写≠看得见，**绝不能被判成"用户可见"**。
    expect(
      OgLAppDirs.isUserVisible(
        '/storage/emulated/0/Android/data/com.example/files/ogl',
      ),
      isFalse,
    );
    expect(OgLAppDirs.isUserVisible('/data/user/0/com.example/ogl'), isFalse);
  });

  test('公共根目录候选（非 Android 宿主上允许为 null，但绝不抛）', () async {
    final String? root = await OgLAppDirs.publicRoot();
    if (root != null) {
      expect(root, contains(OgLAppDirs.folderName));
    }
  });
}
