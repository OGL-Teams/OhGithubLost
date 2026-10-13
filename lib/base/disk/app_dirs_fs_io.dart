/// L1 底座级 · 应用目录规划的**实现**（真实文件系统 + path_provider）。
///
/// 由 `app_dirs.dart` 导入；可以放心用 `dart:io` 与 `package:path_provider`。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 平台文件系统侧：目录探测 / 真实写入探针 / 根目录候选链。
abstract final class AppDirsFs {
  /// **期望的公共根目录**（用户可见的那个）；无法确定时返回 `null`。
  ///
  /// - Android：`/storage/emulated/0/<folder>`；
  /// - 桌面：文档目录下的 `<folder>`。
  static Future<String?> publicRoot(String folder) async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/$folder';
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final Directory docs = await getApplicationDocumentsDirectory();
        return '${docs.path.replaceAll(r'\', '/')}/$folder';
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 真实写入探针：能建目录、能写入并删除探针文件，才算可写。
  static Future<bool> writable(String dir) async {
    try {
      final Directory d = Directory(dir);
      await d.create(recursive: true);
      final File probe = File('$dir/.ogl_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 解析应用根目录（含候选链，逐级退让；返回绝对路径）。
  ///
  /// 顺序：① 外部可见目录 → ② 应用外部目录 → ③ 文档目录 → ④ 支持目录。
  static Future<String> resolveRoot(String folder) async {
    if (Platform.isAndroid) {
      // ① 外部可见目录（Android 11+ 通常写不动 → 探针会失败）。
      final String visible = '/storage/emulated/0/$folder';
      if (await writable(visible)) {
        return visible;
      }
      // ② 应用外部目录：无需任何权限即可写，是 ① 失败后的首选退路。
      //    ⚠️ 但它**不算用户可见**（见 app_dirs.dart 的 `isUserVisible`）。
      try {
        final Directory? ext = await getExternalStorageDirectory();
        if (ext != null) {
          final String candidate = '${ext.path.replaceAll(r'\', '/')}/$folder';
          if (await writable(candidate)) {
            return candidate;
          }
        }
      } catch (_) {
        // 某些定制 ROM 会抛：忽略，继续退。
      }
    }
    // ③ 文档目录（桌面为 ~/Documents，用户可见；其余平台兜底）。
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final String candidate = '${docs.path.replaceAll(r'\', '/')}/$folder';
      if (await writable(candidate)) {
        return candidate;
      }
    } catch (_) {
      // 忽略。
    }
    // ④ 支持目录：一定可写，保底。
    final Directory support = await getApplicationSupportDirectory();
    final String candidate = '${support.path.replaceAll(r'\', '/')}/$folder';
    if (await writable(candidate)) {
      return candidate;
    }
    return support.path.replaceAll(r'\', '/');
  }
}
