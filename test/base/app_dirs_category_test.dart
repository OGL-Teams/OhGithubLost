/// L1 跨层一致性与 L1/L2 落盘可见性 · 两道护栏。
///
/// ## ① 分类 → 目录名的防漂移
/// 映射在两处各写了一份（底座 `OgLAppDirs.categoryFolder` 收字符串、中枢
/// `IxDownloadCategory.folder` 出字符串）。底座不能反向依赖中枢
/// （`layer_audit` 会拦向上依赖），所以只能各写一份、再用测试钉在一起。
/// 历史上底座那份**漏过 `artifact`**（Action 构建产物），一旦被用到就会静默
/// 落到 `other/` —— 用户看不到任何异常，只是分类目录不对。
///
/// ## ② 可见性判定只能有一套
/// 曾有两套定义：`OgLStoragePlan.userVisible`（按档位）与
/// `OgLAppDirs.isUserVisible`（按路径分级）。它们在「桌面文档目录不可写、
/// 最终落到应用支持目录」时会给出**相反结论**。界面当时接的是前者、
/// 测试锁的是后者，所以谁也没发现。现在统一成后者（路径分级是唯一来源），
/// 这几条把「不得再分叉」钉成回归。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/app_dirs.dart';
import 'package:ohgithublost/base/disk/og_l_storage.dart';
import 'package:ohgithublost/domain/ix/ix_download.dart';

void main() {
  group('分类 → 目录名', () {
    test('每个下载分类在中枢与底座两侧都映射到同一个目录名', () {
      for (final IxDownloadCategory category in IxDownloadCategory.values) {
        expect(
          OgLAppDirs.categoryFolder(category.folder),
          category.folder,
          reason: '分类 ${category.name} 两侧映射不一致',
        );
      }
    });

    test('已知分类名都被显式覆盖（未知的才落到 other）', () {
      for (final String name in <String>[
        'release',
        'repo',
        'gist',
        'artifact',
      ]) {
        expect(
          OgLAppDirs.categoryFolder(name),
          name,
          reason: '$name 不应被折叠到 other',
        );
      }
    });

    test('未知分类回落到 other', () {
      expect(OgLAppDirs.categoryFolder('whatever'), 'other');
      expect(OgLAppDirs.categoryFolder(''), 'other');
    });
  });

  group('落盘可见性只有一套判定', () {
    test('② SAF 档只要用户授权过就算可见（root 是应用内回退路径）', () {
      const OgLStoragePlan plan = OgLStoragePlan(
        mode: OgLStorageMode.safDir,
        root: '/data/user/0/com.example/files/ogl',
        safTreeUri: 'content://tree/primary%3ADownload',
      );
      expect(plan.userVisible, isTrue);
    });

    test('① 公共目录可见；③ 应用内部目录不可见', () {
      const OgLStoragePlan pub = OgLStoragePlan(
        mode: OgLStorageMode.publicDir,
        root: '/storage/emulated/0/ogl',
      );
      expect(pub.userVisible, isTrue);

      const OgLStoragePlan inner = OgLStoragePlan(
        mode: OgLStorageMode.internal,
        root: '/data/user/0/com.example/files/ogl',
      );
      expect(inner.userVisible, isFalse);
    });

    test('★ 无论什么档位，可见性都等于按路径分级的结论（两套定义不得分叉）', () {
      for (final OgLStorageMode mode in OgLStorageMode.values) {
        for (final String root in <String>[
          '/storage/emulated/0/ogl',
          '/storage/emulated/0/Android/data/com.example/files/ogl',
          '/data/user/0/com.example/files/ogl',
          '/home/user/Documents/ogl',
        ]) {
          final OgLStoragePlan plan = OgLStoragePlan(mode: mode, root: root);
          final bool expected =
              mode == OgLStorageMode.safDir || OgLAppDirs.isUserVisible(root);
          expect(
            plan.userVisible,
            expected,
            reason: '档位 $mode · 路径 $root',
          );
        }
      }
    });
  });
}
