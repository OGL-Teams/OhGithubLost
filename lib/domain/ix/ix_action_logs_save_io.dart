/// L2 中枢级 · 日志文本**落盘**的原生实现（`dart:io`）。
///
/// `dart:io` 被隔离在本文件（条件导入），`ix_action_logs.dart` 本体保持
/// Web 可编译——与 `gh_oauth` / `ix_download` 的拆分同一手法。
library;

import 'dart:io';

/// 把文本写入 `<root>/actions/<fileName>`；成功返回完整路径。
Future<String> ogLActionLogSaveToDisk({
  required String root,
  required String fileName,
  required String text,
}) async {
  final Directory dir = Directory('$root/actions');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final File file = File(
    '${dir.path}${Platform.pathSeparator}$fileName',
  );
  await file.writeAsString(text, flush: true);
  return file.path;
}
