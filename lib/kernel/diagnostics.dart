/// 内核诊断中枢：结构化日志、阶段耗时与模块状态。
///
/// 本模块**不依赖**任何层级实现（含契约层），以保证内核可独立单测；
/// 日志落盘由硬盘逻辑层在后续里程碑通过 [KernelLogSink] 接入。
library;

import 'dart:collection';

/// 日志级别。
enum KernelLogLevel {
  /// 追踪（默认关闭，verbose 时输出）。
  trace,

  /// 调试（默认关闭，verbose 时输出）。
  debug,

  /// 常规信息。
  info,

  /// 警告（不阻断流程）。
  warn,

  /// 错误（伴随失败）。
  error,
}

/// 结构化日志条目（审计与问题定位的最小单元）。
class KernelLogEntry {
  /// 创建日志条目。
  const KernelLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.code,
    this.data,
  });

  /// 产生时间（本地时钟）。
  final DateTime timestamp;

  /// 级别。
  final KernelLogLevel level;

  /// 标签（如 `KERNEL` / `BOOT` / `NET`，见 docs/NAMING.md（该文件未落地，以源码为准））。
  final String tag;

  /// 人类可读信息。
  final String message;

  /// 结构化事件码（如 `OGL-BOOT-101`）。
  final String? code;

  /// 结构化补充数据（必须可 JSON 序列化）。
  final Map<String, Object?>? data;

  /// 序列化（审计导出用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'ts': timestamp.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        if (code != null) 'code': code,
        if (data != null) 'data': data,
      };

  @override
  String toString() {
    final codeSuffix = code == null ? '' : ' ($code)';
    return '[$tag] ${level.name.toUpperCase()} $message$codeSuffix';
  }
}

/// 日志接收方（落盘 / 上报 / 测试采集）。
abstract class KernelLogSink {
  /// 接收一条日志。
  void onLog(KernelLogEntry entry);
}

/// 阶段耗时记录（启动报告用）。
class KernelStageTiming {
  /// 创建记录。
  const KernelStageTiming({
    required this.name,
    required this.duration,
    this.ok = true,
    this.detail,
  });

  /// 阶段名（如 `start:base.net`）。
  final String name;

  /// 耗时。
  final Duration duration;

  /// 是否成功。
  final bool ok;

  /// 失败原因或补充说明。
  final String? detail;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'ms': duration.inMicroseconds / 1000,
        'ok': ok,
        if (detail != null) 'detail': detail,
      };

  @override
  String toString() =>
      '$name ${duration.inMilliseconds}ms${ok ? '' : ' FAILED'}';
}

/// 诊断中枢。
class KernelDiagnostics {
  /// 创建诊断中枢。
  KernelDiagnostics({this.appVersion = '0.0.0', this.bufferCapacity = 512});

  /// 应用版本（进启动报告）。
  final String appVersion;

  /// 内存日志容量上限（环形淘汰）。
  final int bufferCapacity;

  final Queue<KernelLogEntry> _buffer = Queue<KernelLogEntry>();
  final List<KernelLogSink> _sinks = <KernelLogSink>[];
  final List<KernelStageTiming> _stages = <KernelStageTiming>[];
  final Map<String, String> _moduleStates = <String, String>{};
  final List<String> _sinkErrors = <String>[];

  /// 是否输出 trace/debug 级日志。
  bool verbose = false;

  /// 日志接收方列表（只读）。
  List<KernelLogSink> get sinks => List<KernelLogSink>.unmodifiable(_sinks);

  /// 接收方抛出的异常记录（**不允许静默吞掉**，见 STANDARDS S2）。
  List<String> get sinkErrors => List<String>.unmodifiable(_sinkErrors);

  /// 阶段耗时列表（按发生顺序）。
  List<KernelStageTiming> get stages =>
      List<KernelStageTiming>.unmodifiable(_stages);

  /// 模块状态快照（`模块 ID → 状态名`）。
  Map<String, String> get moduleStates =>
      Map<String, String>.unmodifiable(_moduleStates);

  /// 日志尾部（最多 [bufferCapacity] 条）。
  List<KernelLogEntry> get logTail =>
      List<KernelLogEntry>.unmodifiable(_buffer);

  /// 错误级日志数量。
  int get errorCount =>
      _buffer.where((entry) => entry.level == KernelLogLevel.error).length;

  /// 注册接收方（重复注册会被忽略）。
  void addSink(KernelLogSink sink) {
    if (!_sinks.contains(sink)) {
      _sinks.add(sink);
    }
  }

  /// 移除接收方。
  void removeSink(KernelLogSink sink) {
    _sinks.remove(sink);
  }

  /// 写入一条日志。
  void log(
    KernelLogLevel level,
    String tag,
    String message, {
    String? code,
    Map<String, Object?>? data,
  }) {
    if ((level == KernelLogLevel.trace || level == KernelLogLevel.debug) &&
        !verbose) {
      return;
    }
    final entry = KernelLogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      code: code,
      data: data,
    );
    if (_buffer.length >= bufferCapacity) {
      _buffer.removeFirst();
    }
    _buffer.add(entry);
    for (final sink in List<KernelLogSink>.of(_sinks)) {
      try {
        sink.onLog(entry);
      } catch (error) {
        _sinkErrors.add('${sink.runtimeType}: $error');
      }
    }
  }

  /// 追踪级日志（verbose 时输出）。
  void trace(String tag, String message,
          {String? code, Map<String, Object?>? data}) =>
      log(KernelLogLevel.trace, tag, message, code: code, data: data);

  /// 调试级日志（verbose 时输出）。
  void debug(String tag, String message,
          {String? code, Map<String, Object?>? data}) =>
      log(KernelLogLevel.debug, tag, message, code: code, data: data);

  /// 信息级日志。
  void info(String tag, String message,
          {String? code, Map<String, Object?>? data}) =>
      log(KernelLogLevel.info, tag, message, code: code, data: data);

  /// 警告级日志。
  void warn(String tag, String message,
          {String? code, Map<String, Object?>? data}) =>
      log(KernelLogLevel.warn, tag, message, code: code, data: data);

  /// 错误级日志。
  void error(String tag, String message,
          {String? code, Map<String, Object?>? data}) =>
      log(KernelLogLevel.error, tag, message, code: code, data: data);

  /// 记录一次阶段耗时。
  void recordStage(
    String name,
    Duration duration, {
    bool ok = true,
    String? detail,
  }) {
    _stages.add(KernelStageTiming(
      name: name,
      duration: duration,
      ok: ok,
      detail: detail,
    ));
  }

  /// 记录模块状态（以状态名保存，避免与契约层产生循环依赖）。
  void recordModuleState(String moduleId, String stateName) {
    _moduleStates[moduleId] = stateName;
  }

  /// 清空全部诊断数据（测试与"重启"场景用）。
  void clear() {
    _buffer.clear();
    _stages.clear();
    _moduleStates.clear();
    _sinkErrors.clear();
  }
}
