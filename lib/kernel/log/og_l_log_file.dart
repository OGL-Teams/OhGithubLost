/// L0 内核级 ·**日志落盘**（把"看不见的失败"变成磁盘上的事实）。
///
/// ## 为什么必须有它
/// 此前的日志只在内存里环形保留 200 条：进程一退、一崩、被杀，
/// 现场**全部消失**；而且只记"出错"，不记"做成了什么"——
/// 于是排查时手里什么都没有，只能猜。
///
/// 现在：
/// - **每条日志立刻写文件**（写入后排队 flush，崩溃也不丢已写入的行）；
/// - 目录按候选链**逐个尝试**（`sdcard/logging` → 应用外部目录 → 应用文档/支持目录），
///   全部失败时**自己把原因记下来**，由界面展示（绝不静默）；
/// - 文件按天切分、超限滚动（实际名形如 `ogl-20261008.log` / `.1.log`，
///   日期是紧凑写法，没有分隔符）；
/// - 与 Flutter / path_provider **零耦合**：候选目录由组合根注入，
///   因此本文件是纯 Dart。
///
/// ## 平台分层
/// 本文件是**门面**，只负责时间戳 / 级别拼接 / 候选遍历与诊断；
/// 真正的落盘（`dart:io`）收敛到实现文件 `og_l_log_file_io.dart`
/// （真实文件：原子追加 / 按天切分 / 滚动）。
library;

import 'og_l_log_file_io.dart';

/// 日志落盘器（单例；组合根在 `runApp` 之前 `init`）。
abstract final class OgLLogFile {
  /// 单文件大小上限（超出即滚动到 `.1.log`）。
  static const int maxBytes = 2 * 1024 * 1024;

  static final OgLLogBackend _backend = OgLLogBackend(maxBytes: maxBytes);

  static String? _lastError;
  static final List<String> _tried = <String>[];

  /// 是否已成功落盘。
  static bool get isEnabled => _backend.isEnabled;

  /// 当前日志文件的绝对路径（未落盘时为 `null`）。
  static String? get filePath => _backend.filePath;

  /// 当前日志目录（未落盘时为 `null`）。
  static String? get dirPath => _backend.dirPath;

  /// 最后一次失败原因（未落盘时给界面看）。
  static String? get lastError => _lastError;

  /// 试过的候选目录（按顺序），供界面如实展示"为什么没写到 sdcard"。
  static List<String> get triedDirectories => List<String>.unmodifiable(_tried);

  /// 初始化：按候选顺序找**第一个可写**的目录。
  ///
  /// [candidates] 由 `base` 层解析（`sdcard/logging` → 外部目录 → 文档 → 支持目录）；
  /// 全部不可写时如实进入"无可写候选"状态
  /// （`isEnabled == false`、`lastError == '没有可写的候选目录'`）。
  static Future<void> init({
    required List<String> candidates,
    String prefix = 'ogl',
    String appVersion = '',
    String buildMode = '',
    String platform = '',
  }) async {
    _tried.clear();
    _lastError = null;
    // 后端把跨天切换 / 写入失败的原因回调回来，统一记入 lastError。
    _backend.onError = (String error) {
      _lastError = error;
    };
    final String stamp = _stamp(DateTime.now());
    for (final String raw in candidates) {
      _tried.add(raw);
      final String dir = raw.replaceAll(r'\', '/');
      final String? error =
          await _backend.openDir(dir, prefix: prefix, stamp: stamp);
      if (error == null) {
        line(
          '日志',
          '日志落盘已启用：${_backend.filePath}（平台=$platform 版本=$appVersion 构建=$buildMode）',
        );
        return;
      }
      _lastError = '$raw → $error';
    }
    _lastError ??= '没有可写的候选目录';
  }

  /// 写一行（自动加时间戳与级别；`level` 取 `INFO/WARN/ERR`）。
  static void line(String area, String message, {String level = 'INFO'}) {
    raw('${_iso(DateTime.now())} [$level] [$area] $message');
  }

  /// 写一行原始文本（**已带时间戳的完整行**）。
  ///
  /// 已落盘 → 写入文件；未落盘 → 走后端兜底（控制台），
  /// 因此"日志永远留下痕迹"，而不是被静默丢弃。
  static void raw(String text) {
    if (_backend.isEnabled) {
      _backend.write(text);
    } else {
      _backend.fallback(text);
    }
  }

  /// 等所有已排队的写入落盘（退出前 / 崩溃上报时用）。
  static Future<void> flush() => _backend.flush();

  /// 关闭落盘（退出前调用）。
  static Future<void> close() => _backend.close();

  /// 测试用：绑定一个任意 sink（不做目录探测）。
  static void bindForTest(String path) => _backend.bindForTest(path);

  /// 跨天时自动切到新文件（每次写入前检查，代价可忽略）。
  ///
  /// 实现细节在平台后端。
  static void ensureCurrentDay() => _backend.ensureCurrentDay();

  static String _iso(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}.${three(at.millisecond)}';
  }

  static String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}';
  }
}
