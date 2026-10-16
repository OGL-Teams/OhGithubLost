/// L1 底座级 · **日志目录候选链**（"日志到底写到哪儿"的唯一答案处）。
///
/// 日志统一写入应用根目录下的 `logging/`（默认 `<sdcard>/ogl/logging`，
/// 平台不可写时自动退到应用可见目录，见 `disk/app_dirs.dart`）。
///
/// 顺序即优先级：越靠前越"用户看得见"。
///
/// 平台侧的 `dart:io` / `path_provider` 全部收敛到实现文件
/// `log_dirs_platform_io.dart`。
library;

import 'log_dirs_platform_io.dart';

/// 解析日志目录候选清单（去重、规整为正斜杠路径）。
///
/// 返回的**第一个**可写目录会被 `OgLLogFile` 采用。
Future<List<String>> ogLLogDirectoryCandidates() async {
  final List<String> out = <String>[];
  void add(String? path) {
    if (path == null || path.isEmpty) {
      return;
    }
    final String normalized = path.replaceAll(r'\', '/');
    if (!out.contains(normalized)) {
      out.add(normalized);
    }
  }

  for (final String candidate in await platformLogCandidates()) {
    add(candidate);
  }

  return out;
}
