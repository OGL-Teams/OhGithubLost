/// L0 内核级 · **函数追踪**：每次调用、每次返回（含返回值摘要）都入库。
///
/// 用户要求（原话）："对所有函数做日志捕获……记录每次调用和返回数值"。
/// 本文件提供统一原语；各模块按批注入，CI（分析器 + 测试）保证不破坏行为。
///
/// ## 用法
/// ```dart
/// OgLTrace.sync('GhApi.myRepos', () {
///   ...原函数体...
/// }, args: () => 'perPage=$perPage');
///
/// Future<T> foo() => OgLTrace.async('类.foo', () async { ... });
/// ```
///
/// ## 纪律
/// - **失败也要留痕**（✗ + 异常文本），随后原样 rethrow —— 不吞异常；
/// - 返回值只记**摘要**（列表给条数、字符串给长度、其它给类型），
///   避免日志被大对象撑爆；
/// - 缩进随调用深度变化，方便一眼看出调用栈。
library;

import 'og_l_log_file.dart';

/// 追踪原语（静态、零依赖、可关闭）。
abstract final class OgLTrace {
  /// 总开关（测试里可关，避免刷日志）。
  static bool enabled = true;

  static int _depth = 0;

  static String get _pad => '·' * (_depth > 12 ? 12 : _depth);

  /// 同步函数：调用 + 返回 + 异常，三态全记。
  static T sync<T>(
    String name,
    T Function() body, {
    Object? Function()? args,
  }) {
    if (!enabled) {
      return body();
    }
    final Object? argument = args?.call();
    OgLLogFile.line(
      '追踪',
      '$_pad-> $name${argument == null ? '' : '($argument)'}',
    );
    _depth++;
    try {
      final T result = body();
      _depth--;
      OgLLogFile.line('追踪', '$_pad<- $name = ${describe(result)}');
      return result;
    } catch (error) {
      _depth--;
      OgLLogFile.line('追踪', '$_pad x $name：$error', level: 'ERR');
      rethrow;
    }
  }

  /// 异步函数：同上（等待完成后再记返回）。
  static Future<T> async<T>(
    String name,
    Future<T> Function() body, {
    Object? Function()? args,
  }) async {
    if (!enabled) {
      return body();
    }
    final Object? argument = args?.call();
    OgLLogFile.line(
      '追踪',
      '$_pad-> $name${argument == null ? '' : '($argument)'}',
    );
    _depth++;
    try {
      final T result = await body();
      _depth--;
      OgLLogFile.line('追踪', '$_pad<- $name = ${describe(result)}');
      return result;
    } catch (error) {
      _depth--;
      OgLLogFile.line('追踪', '$_pad x $name：$error', level: 'ERR');
      rethrow;
    }
  }

  /// 只记一行"值"（用于没有控制流的短表达式 / 状态变化）。
  static T mark<T>(String name, T value) {
    if (enabled) {
      OgLLogFile.line('追踪', '$_pad• $name = ${describe(value)}');
    }
    return value;
  }

  /// 返回值摘要（防日志爆炸）。
  static String describe(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is List<Object?>) {
      final String head = value.isEmpty ? '' : '，首项 ${value.first.runtimeType}';
      return 'List(${value.length})$head';
    }
    if (value is Map<Object?, Object?>) {
      return 'Map(${value.length})';
    }
    if (value is String) {
      return value.length <= 80
          ? '"${value.replaceAll('\n', r'\n')}"'
          : 'String(${value.length} 字符)';
    }
    if (value is num || value is bool || value is Enum) {
      return '$value';
    }
    return value.runtimeType.toString();
  }
}
