/// 信任告警：启动层与扩展装载的显式告警通道。
///
/// 设计要点（见 `docs/BOOT.md（该文件未落地，以源码为准）`）：
/// - 告警**不得只落日志**：必须经由收集器分发给 UI（弹窗/安全中心）与审计；
/// - 告警是结构化数据（码 + 主体 + 严重级 + 说明），便于自动化与国际化；
/// - 接收方异常不允许静默吞掉，统一记录到 [TrustWarningCollector.sinkErrors]。
library;

/// 告警严重级。
enum TrustSeverity {
  /// 提示（例行信息）。
  info,

  /// 警告（需用户知晓，不阻断）。
  warn,

  /// 危险（需要用户显式确认，或执行阻断动作）。
  danger,
}

/// 告警码段（见 `docs/NAMING.md（该文件未落地，以源码为准）` §4）。
abstract final class BootWarningCodes {
  /// 未签名第三方 Mod 已加载。
  static const String unsignedModLoaded = 'OGL-BOOT-101';

  /// 清单声明的模块在装配时**未被提供**（构建裁剪 / 接线遗漏）。
  ///
  /// 由 5.0 的一次性一致性探针发现：此前这种不一致会被**静默放过**。
  static const String manifestModuleNotProvided = 'OGL-BOOT-108';

  /// 官方模块完整性校验失败（已拒绝装载并进入安全模式）。
  static const String moduleIntegrityFailed = 'OGL-BOOT-102';

  /// 引导清单签名校验失败（拒绝启动）。
  static const String manifestSignatureInvalid = 'OGL-BOOT-103';

  /// 引导清单缺失（安装损坏或开发旁路）。
  static const String manifestMissing = 'OGL-BOOT-104';

  /// 第三方主题已启用（信任不设限策略，提示性）。
  static const String untrustedThemeEnabled = 'OGL-BOOT-105';

  /// 扩展被策略拒绝。
  static const String extensionRejected = 'OGL-BOOT-106';

  /// 开发旁路已启用（仅调试构建可用）。
  static const String developmentBypass = 'OGL-BOOT-107';
}

/// 一条信任告警。
class BootTrustWarning {
  /// 创建告警。
  const BootTrustWarning({
    required this.code,
    required this.subject,
    required this.severity,
    required this.message,
    required this.at,
    this.data,
  });

  /// 事件码（见 [BootWarningCodes]）。
  final String code;

  /// 告警主体（如 `mod:hidden-tools@1.2.0`、`module:base.net`）。
  final String subject;

  /// 严重级。
  final TrustSeverity severity;

  /// 用户可读说明。
  final String message;

  /// 产生时间。
  final DateTime at;

  /// 结构化补充数据。
  final Map<String, Object?>? data;

  /// 序列化（审计导出用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'subject': subject,
        'severity': severity.name,
        'message': message,
        'at': at.toIso8601String(),
        if (data != null) 'data': data,
      };

  @override
  String toString() => '[$code][${severity.name}] $subject: $message';
}

/// 告警接收方（UI 安全中心 / 审计日志 / 测试采集）。
abstract class TrustWarningSink {
  /// 接收一条告警。
  void onWarning(BootTrustWarning warning);
}

/// 告警收集器（"总线告警"）。
class TrustWarningCollector {
  final List<BootTrustWarning> _warnings = <BootTrustWarning>[];
  final List<TrustWarningSink> _sinks = <TrustWarningSink>[];
  final List<String> _sinkErrors = <String>[];

  /// 已产生的告警（按产生顺序）。
  List<BootTrustWarning> get warnings =>
      List<BootTrustWarning>.unmodifiable(_warnings);

  /// 接收方抛出的异常记录（禁止静默吞掉）。
  List<String> get sinkErrors => List<String>.unmodifiable(_sinkErrors);

  /// 是否存在任何告警。
  bool get hasWarnings => _warnings.isNotEmpty;

  /// 是否存在危险级告警。
  bool get hasDanger =>
      _warnings.any((warning) => warning.severity == TrustSeverity.danger);

  /// 告警数量。
  int get count => _warnings.length;

  /// 最严重的一条告警（无告警时返回 `null`）。
  BootTrustWarning? get mostSevere {
    BootTrustWarning? result;
    for (final warning in _warnings) {
      if (result == null || warning.severity.index > result.severity.index) {
        result = warning;
      }
    }
    return result;
  }

  /// 注册接收方（重复注册忽略）。
  void addSink(TrustWarningSink sink) {
    if (!_sinks.contains(sink)) {
      _sinks.add(sink);
    }
  }

  /// 移除接收方。
  void removeSink(TrustWarningSink sink) {
    _sinks.remove(sink);
  }

  /// 产生一条告警并分发给全部接收方。
  void emit(BootTrustWarning warning) {
    _warnings.add(warning);
    for (final sink in List<TrustWarningSink>.of(_sinks)) {
      try {
        sink.onWarning(warning);
      } catch (error) {
        _sinkErrors.add('${sink.runtimeType}: $error');
      }
    }
  }

  /// 便捷方法：按码与严重级产生告警。
  void report({
    required String code,
    required String subject,
    required TrustSeverity severity,
    required String message,
    Map<String, Object?>? data,
  }) {
    emit(BootTrustWarning(
      code: code,
      subject: subject,
      severity: severity,
      message: message,
      at: DateTime.now(),
      data: data,
    ));
  }

  /// 清空告警与错误记录（测试用）。
  void clear() {
    _warnings.clear();
    _sinkErrors.clear();
  }
}
