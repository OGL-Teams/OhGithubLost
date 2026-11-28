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

/// 进程内缓存：候选链解析结果。
///
/// 为什么要记：目录探测要走平台通道 + 真实写入探针（每个候选 3 次 I/O），
/// 而进程生命周期内文件系统布局不会变——重复探测纯属浪费启动时间。
/// 首次调用照常探测，之后直接复用（组合根与权限自检等后续探测共享）。
List<String>? _cachedCandidates;

/// 解析日志目录候选清单（去重、规整为正斜杠路径）。
///
/// 返回的**第一个**可写目录会被 `OgLLogFile` 采用；结果按进程缓存
/// （权限变化后需要重新探测的场景由 `OgLAppDirs.invalidate()` 覆盖，
/// 本处复用同一探测链，缓存随首次解析一次性建立）。
Future<List<String>> ogLLogDirectoryCandidates() async {
  final List<String>? cached = _cachedCandidates;
  if (cached != null) {
    return cached;
  }
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

  _cachedCandidates = List<String>.unmodifiable(out);
  return out;
}
