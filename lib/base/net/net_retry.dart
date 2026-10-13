/// L1 底座级 · 网络连接：重试与退避策略。
///
/// 设计要点：
/// - **纯函数化**：给定"已试次数 + 失败原因"⇒ "要不要再试 / 等多久"，
///   不发请求、不持有状态，因此可以在离线环境精确断言每一条分支；
/// - **尊重服务端**：`Retry-After` 优先于本地指数退避（限流场景必须听话）；
/// - **抖动**：退避带 ±ratio 抖动，避免大量客户端在同一秒集中重连。
library;

import 'dart:math';

import 'net_types.dart';

/// 重试策略。
class RetryPolicy {
  /// 创建策略。
  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(seconds: 8),
    this.jitterRatio = 0.25,
    this.retryableStatuses = const <int>{408, 429, 500, 502, 503, 504},
  }) : assert(maxAttempts >= 1, 'maxAttempts 至少为 1');

  /// 最大尝试次数（含首次）。
  final int maxAttempts;

  /// 首次退避基准。
  final Duration baseDelay;

  /// 退避上限。
  final Duration maxDelay;

  /// 抖动比例（0 表示不抖动）。
  final double jitterRatio;

  /// 触发重试的状态码。
  ///
  /// 注意：只有 4xx/5xx **不代表请求语义已生效**时才应列入；
  /// 例如 PUT 已成功但响应丢失的情况由上层幂等策略处理。
  final Set<int> retryableStatuses;

  /// 是否还允许再试（[attemptsDone] 为已完成的尝试次数）。
  bool canRetry(int attemptsDone) => attemptsDone < maxAttempts;

  /// 计算下次重试等待时长；返回 `null` 表示**不应重试**。
  ///
  /// - [attemptsDone]：已完成的尝试次数（1 表示刚失败第一次）；
  /// - [statusCode]：若失败来自响应状态码；
  /// - [kind]：若失败来自异常分类；
  /// - [retryAfter]：服务端给出的等待时长；
  /// - [jitter]：注入随机源（测试传 `() => 0.5` 可得到确定性结果）。
  Duration? delayFor(
    int attemptsDone, {
    int? statusCode,
    NetErrorKind? kind,
    Duration? retryAfter,
    double Function()? jitter,
  }) {
    if (!canRetry(attemptsDone)) {
      return null;
    }
    if (statusCode != null && !retryableStatuses.contains(statusCode)) {
      return null;
    }
    if (kind != null && !kind.isRetryable) {
      return null;
    }

    // 服务端说了算，但不超过本地上限（避免被异常头拖死）。
    if (retryAfter != null && retryAfter > Duration.zero) {
      return retryAfter > maxDelay ? maxDelay : retryAfter;
    }

    final exponential =
        baseDelay.inMilliseconds * pow(2, attemptsDone - 1).toDouble();
    final capped = min(exponential, maxDelay.inMilliseconds.toDouble());
    if (jitterRatio <= 0) {
      return Duration(milliseconds: capped.round());
    }
    final random = jitter ?? _defaultJitter;
    final factor = 1 + (random() * 2 - 1) * jitterRatio;
    return Duration(milliseconds: (capped * factor).round());
  }

  static final Random _random = Random();
  static double _defaultJitter() => _random.nextDouble();

  @override
  String toString() =>
      'RetryPolicy(max=$maxAttempts, base=${baseDelay.inMilliseconds}ms, '
      'cap=${maxDelay.inMilliseconds}ms, jitter=$jitterRatio)';
}
