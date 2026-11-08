/// L2 中枢级 · 日志文本落盘的 **Web 桩**。
///
/// 浏览器没有应用私有目录可写；这里如实抛 [IxActionLogsException]，
/// 由调用方提示用户（不静默降级、不假装成功）。
library;

import 'ix_action_logs.dart';

/// Web 上不支持直接落盘——永远抛出。
Future<String> ogLActionLogSaveToDisk({
  required String root,
  required String fileName,
  required String text,
}) async {
  throw const IxActionLogsException('当前平台不支持把日志落盘到本地目录');
}
