/// L1 底座级 · 落盘去处的**实现**（SAF 插件 + 配置落盘）。
///
/// 由 `og_l_storage.dart` 导入；这里可以放心 import
/// `dart:io` / `path_provider` / `saf_*` 插件。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

/// SAF（Storage Access Framework）与 SAF 配置的平台侧实现。
abstract final class OgLSafBridge {
  /// SAF 配置文件名（存在**应用支持目录**：一定可写，不需要任何权限）。
  static const String _configFileName = 'ogl_saf_tree.txt';

  static Future<File> _configFile() async {
    final Directory support = await getApplicationSupportDirectory();
    return File('${support.path.replaceAll(r'\', '/')}/$_configFileName');
  }

  /// 选一个文件夹并获得**可持久化**的读写授权；取消 / 失败返回 `null`。
  ///
  /// 只在 Android 上有效；其余平台直接返回 `null`（不触碰插件通道）。
  static Future<String?> pickDirectory() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final Object? picked = await SafUtil().pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (picked == null) {
        return null;
      }
      final Object? uri = (picked as dynamic).uri;
      final String? text = uri?.toString();
      return (text == null || text.isEmpty) ? null : text;
    } catch (error) {
      // 本桥为纯静态工具类、无 KernelDiagnostics 注入点，且底座层不得
      // 引入全局单例；此处失败已如实返回 null，保留 debugPrint 留痕
      // （release 下被剥离不影响功能，见 R7 审计）。
      debugPrint('OGL 存储：选择 SAF 文件夹失败：$error');
      return null;
    }
  }

  /// 把本地文件**粘贴**进 SAF 目录；成功返回 `true`（失败绝不抛）。
  static Future<bool> pasteLocalFile({
    required String srcPath,
    required String treeUri,
    required String fileName,
    String mime = 'application/octet-stream',
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      await SafStream().pasteLocalFile(
        srcPath,
        treeUri,
        fileName,
        mime,
        overwrite: true,
      );
      return true;
    } catch (error) {
      // 纯静态工具类、无 KernelDiagnostics 注入点；失败已如实返回 false，
      // 保留 debugPrint 留痕（release 下被剥离不影响功能，见 R7 审计）。
      debugPrint('OGL 存储：导出到 SAF 失败：$error');
      return false;
    }
  }

  /// 从磁盘加载已授权的 SAF 目录 URI；未授权返回 `null`。
  static Future<String?> loadConfig() async {
    try {
      final File file = await _configFile();
      if (await file.exists()) {
        final String text = (await file.readAsString()).trim();
        return text.isEmpty ? null : text;
      }
    } catch (_) {
      // 读不到就当作未授权。
    }
    return null;
  }

  /// 持久化 SAF 授权（`null` = 清除）。
  static Future<void> saveConfig(String? uri) async {
    try {
      final File file = await _configFile();
      if (uri == null) {
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        await file.writeAsString(uri, flush: true);
      }
    } catch (error) {
      // 纯静态工具类、无 KernelDiagnostics 注入点；写失败不阻断流程，
      // 保留 debugPrint 留痕（release 下被剥离不影响功能，见 R7 审计）。
      debugPrint('OGL 存储：写入 SAF 配置失败：$error');
    }
  }

  /// 本地文件是否存在（导出前的存在性检查）。
  static Future<bool> localFileExists(String path) async {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
