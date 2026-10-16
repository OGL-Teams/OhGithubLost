/// L1 底座级 · 日志目录候选链的**实现**（真实文件系统）。
///
/// 由 `log_dirs.dart` 导入；可以放心用 `dart:io` 与 `package:path_provider`。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../disk/app_dirs.dart';

/// 按优先级给出日志目录候选（未去重、未规整；去重由调用方完成）。
Future<List<String>> platformLogCandidates() async {
  final List<String> out = <String>[];

  // ① 应用根目录下的 logging（默认 <sdcard>/ogl/logging）。
  try {
    out.add(await OgLAppDirs.logging());
  } catch (_) {
    // 解析失败：继续走后面的兜底候选。
  }

  // ② 应用文档目录（桌面平台是 ~/Documents，用户看得见）。
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    out.add('${docs.path}/logging');
  } catch (_) {
    // 忽略。
  }

  // ③ 应用支持目录：一定可写，保底。
  try {
    final Directory support = await getApplicationSupportDirectory();
    out.add('${support.path}/logging');
  } catch (_) {
    // 忽略。
  }

  return out;
}
