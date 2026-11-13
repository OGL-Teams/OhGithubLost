/// L1 底座级 · 网络连接：传输抽象与韧性编排。
///
/// 分层：
/// ```
/// NetBridge（门面）
///   └─ ResilientTransport（重试 + 镜像回落 + 观测）  ← 本文件
///        └─ NetTransport（纯发送，无策略）
///             └─ IoNetTransport（真实 HTTP） / 测试桩
/// ```
/// 这样"策略"与"能力"分离：换 HTTP 客户端不影响重试与观测，
/// 换策略也不影响传输实现。
///
/// ## 两条安全铁律
/// 1. **只重试幂等方法**：`POST` / `PUT` / `PATCH` / `DELETE` 的失败**绝不
///    自动重试**——一次超时重试就可能重复创建 Release、重复提交，或让
///    `PUT /contents` 撞上 422（文件已存在）。需要重试时由调用方通过
///    [retryableMethods] 显式放行，并自行保证幂等键。
/// 2. **失败必须显式**：重试耗尽后不再把 5xx / 429「当作正常响应」返回，
///    而是抛 [NetException]（携带状态码与响应体片段）。
///    语义性响应（4xx 如 404 / 409 / 422）仍照常返回，由上层判断。
library;

import 'dart:math';

import 'net_mirror.dart';
import 'net_retry.dart';
import 'net_types.dart';

/// 字面量 IP 是否为**禁止直连**的地址（私网 / 回环 / 链路本地 /
/// 云元数据 `169.254.169.254` / 运营商级 NAT / 未指定）。
///
/// ## 为什么收在这里（单一事实源）
/// 这份判定此前只存在于 `io_net_transport.dart`（重定向守卫 + DNS 结果过滤），
/// 于是"自定义 DNS 服务器地址校验"（F-13）只能另写一份或反过来依赖 IO 层。
/// 现在它是**传输层的公共契约**：
/// - `net_dns.dart`：自定义 DNS 地址校验 + DNS 应答结果过滤；
/// - `net_transport.dart` 自身：重定向目标校验；
/// - `io_net_transport.dart`：由主会话改为引用本实现（行为等价）。
///
/// 语义保持不变：域名形式的目标**不**在此拦截（由 TLS 证书校验兜底），
/// 这里只判**字面量**。
bool ogLIsBlockedLiteralIp(String host) {
  final String lower =
      host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  final RegExpMatch? ipv4 =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(lower);
  if (ipv4 != null) {
    final List<int> parts = <int>[
      for (int i = 1; i <= 4; i++) int.tryParse(ipv4.group(i)!) ?? 256,
    ];
    if (parts.any((int p) => p > 255)) {
      return true;
    }
    final int a = parts[0], b = parts[1];
    return a == 10 ||
        a == 127 ||
        a == 0 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        (a == 100 && b >= 64 && b <= 127);
  }
  // IPv6 字面量：回环 / 未指定 / 链路本地 / 唯一本地 / IPv4 映射私网。
  if (lower.contains(':')) {
    return lower == '::1' ||
        lower == '::' ||
        lower.startsWith('fe80') ||
        lower.startsWith('fc') ||
        lower.startsWith('fd') ||
        lower.startsWith('::ffff:10.') ||
        lower.startsWith('::ffff:127.') ||
        lower.startsWith('::ffff:192.168.') ||
        lower.startsWith('::ffff:169.254.');
  }
  return false;
}

/// 默认可重试的方法：具备幂等语义，重复执行不会产生额外副作用。
///
/// ★ `PUT` / `DELETE` 曾经在这里，但它们在**本应用的用法下不是幂等的**：
/// `PUT /contents` 新建文件时一次超时重试就会撞 422（文件已经建出来了），
/// `DELETE` 重试撞"目标已不存在"。所以默认集合只留 `GET` / `HEAD`；
/// 确需重试时必须由调用方显式传入 `retryableMethods` 并自行保证幂等键。
const Set<NetMethod> defaultRetryableMethods = <NetMethod>{
  NetMethod.get,
  NetMethod.head,
};

/// 纯发送能力：一次请求一次响应，不做重试、不做镜像。
///
/// ★ 层级倒置（主会话）：契约层 `kernel/contract/net_types.dart` 定义了
///   同名抽象；`net_types.dart` 会把它连同其它类型转发导出，
///   因此本文件**不再重复声明**，既有引用继续编译。
/// 韧性传输：在纯发送之外叠加**重试、镜像回落与观测**。
class ResilientTransport implements NetTransport {
  /// 创建韧性传输。
  ///
  /// [sleep] 可注入（测试传零延迟版本），避免单测真的等待退避时间。
  /// [retryableMethods] 缺省为幂等方法；**不要**为了"多试几次"把 POST 放进来。
  ResilientTransport({
    required NetTransport inner,
    RetryPolicy? policy,
    MirrorSelector? mirrors,
    NetObserver? observer,
    Future<void> Function(Duration duration)? sleep,
    Set<NetMethod> retryableMethods = defaultRetryableMethods,
  })  : _inner = inner,
        _policy = policy ?? const RetryPolicy(),
        _mirrors = mirrors ?? MirrorSelector(),
        _observer = observer ?? NetObserver(),
        _sleep = sleep ?? Future<void>.delayed,
        _retryableMethods = Set<NetMethod>.of(retryableMethods);

  /// 服务端 `Retry-After` 抖动用的随机源（±jitterRatio/2）。
  static final Random _random = Random();

  final NetTransport _inner;
  final RetryPolicy _policy;
  final MirrorSelector _mirrors;
  final NetObserver _observer;
  final Future<void> Function(Duration duration) _sleep;
  final Set<NetMethod> _retryableMethods;

  /// 观测器（读取统计用）。
  NetObserver get observer => _observer;

  /// 重试策略（只读）。
  RetryPolicy get policy => _policy;

  /// 镜像选择器（只读）。
  MirrorSelector get mirrors => _mirrors;

  /// 允许自动重试的方法（只读）。
  Set<NetMethod> get retryableMethods =>
      Set<NetMethod>.unmodifiable(_retryableMethods);

  @override
  Future<NetResponse> send(NetRequest request) async {
    // `original` 永远指向**未经改写的原始 URL**（直连）。
    // 镜像是"附加的一跳"，绝不能把它当成新的基准——
    // 否则第一次换过镜像之后，后续所有匹配都会落在镜像 URL 上而失败，
    // 结果是"配了 3 条通道却只试了 1 条"，且**永远回不到直连**。
    final original = request;
    var current = request;
    final triedMirrors = <String>{};

    /// 推进到下一跳：优先换未试过的镜像；镜像用尽则回落直连。
    /// 返回 `true` 表示 `current` 已改变（这一跳不消耗退避）。
    bool advanceHop() {
      final mirror = _mirrors.mirrorFor(original.url, skip: triedMirrors);
      if (mirror != null) {
        triedMirrors.add(mirror.id);
        current = original.copyWith(url: mirror.url);
        _observer.onMirror(current, mirror.id);
        return true;
      }
      if (current.url != original.url) {
        current = original; // 通道全部不可用 → 回到直连（最后底线）。
        return true;
      }
      return false;
    }

    // 重试预算只统计"**在原地**再试一次"的次数。
    // 换通道（换镜像 / 回落直连）不消耗预算——那是"换一条路"，
    // 不是"同一条路多试一次"。否则配 2 条通道就会把预算吃完，
    // 直连永远轮不到（这正是审计中发现的缺陷）。
    var attempt = 1;
    while (attempt <= _policy.maxAttempts) {
      // 幂等守卫：非幂等方法既不重试、也不换镜像。
      final mayRetry = _retryableMethods.contains(current.method);
      _observer.onRequest(current);

      NetResponse response;
      try {
        response = await _inner.send(current);
      } on NetException catch (error) {
        _observer.onFailure(current, error);

        if (!mayRetry) {
          rethrow;
        }
        // ★ B1-A-05：先判错误类别再决定换跳。TLS / 客户端错误 / 取消类
        //   不可重试错误换镜像重发没有意义（TLS 原因会被最后一次镜像的
        //   错误掩盖；取消后不该继续发请求；凭证会随换跳发往镜像）。
        if (!error.kind.isRetryable) {
          rethrow;
        }
        if (advanceHop()) {
          // ★ B1-A-06：换跳也要尊重服务端节奏（Retry-After 等），
          //   但**不消耗重试预算**（attempt 不递增）——换通道是"换一条路"，
          //   不是"同一条路多试一次"（本文件的核心设计，测试 307 行锚定）。
          final Duration? wait = _policy.delayFor(
            attempt,
            statusCode: error.statusCode,
            kind: error.kind,
            retryAfter: error.retryAfter,
          );
          if (wait != null) {
            _observer.onRetry(current, attempt, error.kind.name);
            // ★ F-10：换跳分支此前用 `Future.delayed` 直等，绕过了注入的
            //   `_sleep`（离线测试会真等）；且服务端给出的等待值没有抖动。
            await _sleep(_withServerJitter(wait, error.retryAfter));
          }
          continue;
        }

        final delay = _policy.delayFor(
          attempt,
          kind: error.kind,
          retryAfter: error.retryAfter,
        );
        if (delay == null) {
          rethrow;
        }
        _observer.onRetry(current, attempt, error.kind.name);
        await _sleep(_withServerJitter(delay, error.retryAfter));
        attempt++;
        continue;
      }

      _observer.onResponse(response);

      // 非"可重试状态码"：属于语义性响应（含 4xx），交还调用方判断。
      if (!_policy.retryableStatuses.contains(response.statusCode)) {
        return response;
      }

      // 5xx / 429 同样先换跳（镜像也可能只是"半死"），再退避重试。
      if (mayRetry && advanceHop()) {
        // ★ B1-A-06：换跳尊重退避但**不消耗预算**（attempt 不递增）。
        final Duration? serverWait =
            _parseRetryAfter(response.headers['retry-after']);
        final Duration? wait = _policy.delayFor(
          attempt,
          statusCode: response.statusCode,
          retryAfter: serverWait,
        );
        if (wait != null) {
          _observer.onRetry(current, attempt, 'HTTP ${response.statusCode}');
          await _sleep(_withServerJitter(wait, serverWait));
        }
        continue;
      }

      // **尊重服务端**：429 / 503 常带 `Retry-After`，优先于本地指数退避
      // （与异常路径共用同一份解析——两处不一致就是缺陷温床）。
      final Duration? serverWait =
          _parseRetryAfter(response.headers['retry-after']);
      final delay = mayRetry
          ? _policy.delayFor(
              attempt,
              statusCode: response.statusCode,
              retryAfter: serverWait,
            )
          : null;
      if (delay == null) {
        // 铁律 2：重试已耗尽（或方法不幂等）——必须显式失败，
        // 绝不把 5xx / 429 当成"正常响应"交给上层。
        throw NetException(
          _kindForStatus(response.statusCode),
          'HTTP ${response.statusCode}：重试已耗尽',
          statusCode: response.statusCode,
          body: _snippet(response.body),
        );
      }
      _observer.onRetry(current, attempt, 'HTTP ${response.statusCode}');
      await _sleep(_withServerJitter(delay, serverWait));
      attempt++;
    }

    // 预算耗尽（或策略配置错误）——绝不允许"静默返回成功"。
    throw const NetException(
      NetErrorKind.unknown,
      '重试预算已耗尽，未取得有效响应（请检查 maxAttempts 配置）',
    );
  }

  /// 解析 `Retry-After` 头（**补 asctime 形态**）。
  ///
  /// 契约层（`kernel/contract/net_types.dart`）已支持 IMF-fixdate 与
  /// RFC 850，但 **asctime**（`Sun Nov  6 08:49:37 1994`）此前直接返回
  /// `null`——那会让服务端明确给出的等待被**静默忽略**，退避改用本地指数值，
  /// 限流场景下等于不听话。asctime 是 HTTP/1.1 允许的三种形态之一，
  /// 这里在传输层补齐（不改动契约层的既有签名）。
  static Duration? _parseRetryAfter(String? raw) {
    final Duration? parsed = parseRetryAfterHeader(raw);
    if (parsed != null) {
      return parsed;
    }
    if (raw == null) {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r'^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+'
      r'(\d{2}):(\d{2}):(\d{2})\s+(\d{4})$',
    ).firstMatch(raw.trim());
    if (match == null) {
      return null;
    }
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final int month = months.indexOf(match.group(1)!);
    if (month < 0) {
      return null;
    }
    final DateTime when = DateTime.utc(
      int.parse(match.group(6)!),
      month + 1,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
    final Duration delta = when.difference(DateTime.now().toUtc());
    if (delta.isNegative) {
      return Duration.zero;
    }
    return delta;
  }

  /// 服务端给出的等待值加**抖动**（避免大量客户端同一秒集中重连）。
  ///
  /// 抖动幅度取 `jitterRatio / 2`（服务端值本身已经是"权威节奏"，
  /// 不宜像本地指数退避那样大幅摆动）。仅在服务端确实给了
  /// `Retry-After` 时生效；本地退避的抖动由 `RetryPolicy` 负责。
  Duration _withServerJitter(Duration wait, Duration? serverValue) {
    if (serverValue == null || serverValue <= Duration.zero) {
      return wait;
    }
    final double ratio = _policy.jitterRatio / 2;
    if (ratio <= 0) {
      return wait;
    }
    final double factor = 1 + (_random.nextDouble() * 2 - 1) * ratio;
    final int millis = (wait.inMilliseconds * factor).round();
    return Duration(milliseconds: millis < 0 ? 0 : millis);
  }

  static NetErrorKind _kindForStatus(int statusCode) {
    if (statusCode == 408) {
      return NetErrorKind.timeout;
    }
    if (statusCode == 429) {
      return NetErrorKind.rateLimited;
    }
    return NetErrorKind.server;
  }

  static String _snippet(String body) =>
      body.length <= 200 ? body : '${body.substring(0, 200)}…';
}

/// 脚本化传输（测试 / 演练用）。
///
/// 按入队顺序返回预设结果：给了 [NetException] 就抛出，给了 [NetResponse] 就返回。
///
/// 注：**生产代码里没有任何实例化**（只有测试构造）。保留是因为它是
/// 传输层契约的可执行样例；若将来要精简，它与 `test/` 里的引用需一起处理。
class ScriptedTransport implements NetTransport {
  /// 创建脚本化传输。
  ScriptedTransport(this._script);

  final List<Object> _script;
  final List<NetRequest> _received = <NetRequest>[];

  /// 实际收到的请求（按顺序，断言镜像改写 / 重试用）。
  List<NetRequest> get received => List<NetRequest>.unmodifiable(_received);

  @override
  Future<NetResponse> send(NetRequest request) async {
    _received.add(request);
    if (_script.isEmpty) {
      throw StateError('ScriptedTransport 脚本已耗尽');
    }
    final next = _script.removeAt(0);
    if (next is NetException) {
      throw next;
    }
    if (next is NetResponse) {
      return next;
    }
    throw StateError('无法识别的脚本项: ${next.runtimeType}');
  }
}
