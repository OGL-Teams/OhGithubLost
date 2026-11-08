/// L1 底座级 · 网络连接：基于 `dart:io HttpClient` 的真实传输实现。
///
/// ## 为什么不再用 Dio（2026-10-03 决策）
/// 设备日志实证：`HttpException: Connection closed before full header was
/// received` 反复出现（`GET /user`、`GET /user/repos` 全部失败），而**同一进程、
/// 同一时刻**的原生自检全绿。两者唯一差别是**是否复用 keep-alive 连接**。
///
/// Dio 替我们封装了 HttpClient，但也把"连接策略"藏进了适配器层：排查时既拿不到
/// 底层对象，也无法直接控制连接复用。因此改为直接持有 `HttpClient`：
/// - **完全可控**：连接复用、自定义 DNS 直连、超时都在本文件一处决定；
/// - **零额外依赖**：`dio` 已从依赖清单移除；
/// - 异常翻译仍然只发生在这里（上层只认识 [NetException]）。
///
/// ## 连接策略
/// 1. `persistentConnection = false`：每个请求都走新连接，从根上消除
///    "复用已被对端关闭的连接"这一类故障（代价：每请求一次握手）；
/// 2. `idleTimeout` 压短（防御性）；
/// 3. 自定义 DNS 模式下用 `connectionFactory` 按解析出的 IP 直连
///    （IPv4 优先；全部失败回退系统解析）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'net_dns.dart';
import 'net_self_test.dart';
import 'net_transport.dart';
import 'net_types.dart';

/// "未指定"哨兵标记（与真实 `null` 区分；`identical` 比较）。
class _UnsetMarker {
  const _UnsetMarker();
}

/// 哨兵实例：`_writeBody` 的 `bodyOverride` 用它区分「未指定」与「显式 null」。
const Object _kUnset = _UnsetMarker();

/// ★ B1-A-17/B1-B-03：跨主机跳转时**不得外泄**的凭证头集合。
///   此前守卫只认 `authorization`——`cookie` / `proxy-authorization` /
///   `x-auth-token` / `api-key` 等会随 dart:io 自动跟随发往第三方。
///   生产调用点当前只用 `authorization`，但契约层必须一次堵住。
/// 与请求体绑定的头：302/303 降级 GET 丢 body 时必须一并剔除
/// （B1-A-30），否则第二跳 `Content-Length: N` 无 body 会挂起 / 400。
const Set<String> _kBodyBoundHeaders = <String>{
  'content-length',
  'content-type',
  'content-md5',
  'transfer-encoding',
  'if-match',
  'if-none-match',
};

const Set<String> _kSensitiveHeaders = <String>{
  'authorization',
  'proxy-authorization',
  'cookie',
  'x-auth-token',
  'api-key',
  'x-api-key',
};

/// 重定向目标安全判定（base 层自足，不向上依赖 domain 的 IxPresign）。
///
/// 交叉审计 B1-A-23/B1-B-04：此前无凭证请求由 dart:io 自动跟随任意
/// Location，可被导向 `http://`（降级）、回环 / 私网 / 云元数据
/// `169.254.169.254`（SSRF）。这里只做**字面量**判定——域名形式的目标
/// 由 TLS 证书校验兜底，不在此处做额外 DNS 解析（避免双解析开销）。
bool _ogLIsSafeRedirectTarget(Uri target) {
  if (target.scheme != 'https' && target.scheme != 'http') {
    return false;
  }
  // https → http 降级一律拒绝（明文传输凭证/内容）。
  if (target.scheme == 'http') {
    return false;
  }
  final String host = target.host.toLowerCase();
  if (host.isEmpty || host == 'localhost' || host.endsWith('.localhost')) {
    return false;
  }
  final RegExpMatch? ipv4 =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (ipv4 != null) {
    final List<int> parts = <int>[
      for (int i = 1; i <= 4; i++) int.tryParse(ipv4.group(i)!) ?? 256,
    ];
    if (parts.any((int p) => p > 255)) {
      return false;
    }
    final int a = parts[0], b = parts[1];
    if (a == 10 ||
        a == 127 ||
        a == 0 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254) ||
        (a == 100 && b >= 64 && b <= 127)) {
      return false;
    }
  }
  // IPv6 字面量：回环 / 未指定 / 链路本地 / 唯一本地一律拒绝。
  if (host.startsWith('[') || host.contains(':')) {
    final String lower = host.replaceAll('[', '').replaceAll(']', '');
    if (lower == '::1' ||
        lower == '::' ||
        lower.startsWith('fe80') ||
        lower.startsWith('fc') ||
        lower.startsWith('fd')) {
      return false;
    }
  }
  return true;
}

/// 基于 `dart:io HttpClient` 的传输实现（Android / Windows / Linux 共用）。
class IoNetTransport implements NetTransport {
  /// 创建传输。
  ///
  /// [dns] 为 `custom` 模式时启用**自定义 DNS**：连接前先按策略解析域名，
  /// 再直连解析出的 IP（TLS 的 SNI 仍用原主机名，证书校验不受影响）。
  IoNetTransport({
    DnsService? dns,
    HttpClient? client,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 60),
  })  : _dns = dns,
        _client = client ?? HttpClient() {
    _applyPolicy(_client);
  }

  final DnsService? _dns;
  final HttpClient _client;

  /// 连接超时。
  final Duration connectTimeout;

  /// 接收超时。
  final Duration receiveTimeout;

  /// 底层客户端（诊断 / 测试用：可断言连接策略）。
  HttpClient get client => _client;

  /// 上一次已应用到客户端的 DNS 模式（`null` = 还没应用过）。
  NetDnsMode? _appliedMode;

  /// 应用连接策略（幂等，可重复调用）。
  void _applyPolicy(HttpClient client) {
    // 空闲连接存活时间压短（防御性）。
    // 注意：**是否复用连接**由每个请求的 `request.persistentConnection = false`
    // 决定（该开关在 HttpClientRequest 上，不在 HttpClient 上）。
    client.idleTimeout = const Duration(seconds: 3);
    client.connectionTimeout = connectTimeout;
    client.userAgent = 'OhGithubLost';
    client.autoUncompress = true;
    client.maxConnectionsPerHost = 8;

    final DnsService? dns = _dns;
    if (dns == null || dns.policy.mode != NetDnsMode.custom) {
      // ★ 撤回：用户从「自定义 DNS」切回「系统 DNS」时，必须把上次装上的
      //   connectionFactory 摘掉，否则旧解析器会一直被用下去。
      client.connectionFactory = null;
      return;
    }
    // 自定义 DNS：接管 connectionFactory，把域名换成我们解析出的 IP。
    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) async {
      const Duration connectTimeout = Duration(seconds: 15);
      if (proxyHost != null && proxyPort != null) {
        return Socket.startConnect(
          proxyHost,
          proxyPort,
        ).timeout(connectTimeout);
      }
      final int port = uri.hasPort && uri.port != 0
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      final List<String> resolved = await dns.resolve(uri.host);
      // IPv4 优先（半死 IPv6 通道场景下先走可达地址）。
      final List<String> v4 =
          resolved.where((String ip) => !ip.contains(':')).toList();
      final List<String> v6 =
          resolved.where((String ip) => ip.contains(':')).toList();
      final List<String> addresses = <String>[...v4, ...v6];
      Object? lastError;
      for (final String address in addresses) {
        try {
          return await Socket.startConnect(
            address,
            port,
          ).timeout(connectTimeout);
        } catch (error) {
          lastError = error;
        }
      }
      // 降级：自定义解析全军覆没 → 交给系统解析再试一次（绝不静默）。
      try {
        return await Socket.startConnect(
          uri.host,
          port,
        ).timeout(connectTimeout);
      } catch (error) {
        lastError = error;
      }
      throw NetException(
        NetErrorKind.connection,
        'DNS 解析后无法连接 ${uri.host}'
        '（自定义 ${addresses.length} 地址 + 系统解析均失败）：$lastError',
      );
    };
  }

  /// 按当前 DNS 策略校正一次客户端（**幂等**，模式没变就什么都不做）。
  ///
  /// ## 为什么必须每次请求前校正
  /// `connectionFactory` 只在**构造时**装过一次，而 DNS 模式的唯一写入点是
  /// `NetBridge.applyDnsSelection` —— 那是模块注册**之后**才调用的。
  /// 于是用户在设置里选「自定义 DNS / DoH 优先」永远改不动真实流量：
  /// 传输层早已按当时的 `system` 建好，此后没有任何时机重装。
  /// 现在把校正放到发送前，模式一变就重装（含切换回系统 DNS 的撤回）。
  void _syncPolicy() {
    final NetDnsMode? mode = _dns?.policy.mode;
    if (mode == _appliedMode) {
      return;
    }
    _applyPolicy(_client);
    _appliedMode = mode;
  }

  @override
  Future<NetResponse> send(NetRequest request) async {
    _syncPolicy();
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final Uri uri = Uri.parse(request.url);
      // ★ 交叉审计 B1-A-17/A-23/B-03/B-04：**所有**请求统一走手动守卫，
      //   不再留「无凭证就自动跟随 5 跳」的旁路（恶意 Location 可打内网/
      //   云元数据 169.254.169.254 或把 https 降级为 http）。
      //   凭证头集合不只 authorization：cookie / x-auth-token / api-key 等
      //   同样不能随跨主机跳转外泄。
      final HttpClientResponse response = await _sendWithGuardedRedirect(
        request.method.verb,
        uri,
        request,
        redirectsLeft: 5,
        receiveTimeout: request.timeout,
      );
      final String text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(request.timeout);
      stopwatch.stop();
      return NetResponse(
        statusCode: response.statusCode,
        body: text,
        duration: stopwatch.elapsed,
        headers: _flattenHeaders(response.headers),
      );
    } on TimeoutException catch (error) {
      stopwatch.stop();
      throw NetException(NetErrorKind.timeout, '请求超时（$error）', cause: error);
    } on HandshakeException catch (error) {
      stopwatch.stop();
      throw NetException(NetErrorKind.tls, '证书校验失败：$error', cause: error);
    } on TlsException catch (error) {
      stopwatch.stop();
      throw NetException(NetErrorKind.tls, 'TLS 握手失败：$error', cause: error);
    } on SocketException catch (error) {
      stopwatch.stop();
      final String report = await _selfTestReport(request);
      throw NetException(
        NetErrorKind.connection,
        '连接失败：$error｜自检: $report',
        cause: error,
      );
    } on HttpException catch (error) {
      stopwatch.stop();
      // "Connection closed before full header / while receiving data" 在
      // dart:io 里是 HttpException：归为**可重试**的连接类（而不是 unknown）。
      final String report = await _selfTestReport(request);
      throw NetException(
        NetErrorKind.connection,
        '连接被对端关闭：$error｜自检: $report',
        cause: error,
      );
    } on NetException {
      // ★ B1-A-18/B1-B-11：内层已翻译过的类型化异常原样上送，
      //   绝不二次包成 unknown（否则明确的 DNS/TLS 失败被误报「未知网络错误」
      //   且因 unknown.isRetryable 被反复重试）。
      stopwatch.stop();
      rethrow;
    } on Object catch (error) {
      stopwatch.stop();
      throw NetException(NetErrorKind.unknown, '未知网络错误（$error）', cause: error);
    }
  }

  /// 手动跟随重定向（仅用于带凭证头的请求）：
  /// - 同源（scheme+host+port 相同）→ 带原凭证重发；
  /// - 跨主机 → 停止跟随，把 3xx 响应原样交还（上层如实报错，凭证不出设备）。
  /// - 302 / 303 把方法降级为 GET 且不携带 body（RFC 7231 §6.4.3）。
  Future<HttpClientResponse> _sendWithGuardedRedirect(
    String verb,
    Uri uri,
    NetRequest request, {
    required int redirectsLeft,
    Object? bodyOverride = _kUnset,
    Duration? receiveTimeout,
  }) async {
    final HttpClientRequest req =
        await _client.openUrl(verb, uri).timeout(connectTimeout);
    req.followRedirects = false;
    request.headers.forEach((String key, String value) {
      req.headers.set(key, value);
    });
    _writeBody(req, request, bodyOverride: bodyOverride);
    final HttpClientResponse response = await req.close().timeout(
          receiveTimeout ?? this.receiveTimeout,
        );
    final int status = response.statusCode;
    final bool isRedirect = status >= 300 && status < 400;
    final String? location = response.headers.value(HttpHeaders.locationHeader);
    if (!isRedirect || location == null || redirectsLeft <= 0) {
      return response;
    }
    final Uri next = uri.resolve(location);
    // ★ B1-A-23/B1-B-04：跟随前校验目标，拒绝协议降级 / 回环 / 私网 /
    //   云元数据地址，防止被改写的 Location 触发 SSRF 或明文传输。
    if (!_ogLIsSafeRedirectTarget(next)) {
      return response;
    }
    final bool sameOrigin = next.scheme == uri.scheme &&
        next.host == uri.host &&
        next.port == uri.port;
    if (!sameOrigin) {
      // 跨主机重定向：**一律不跟随**（B1-A-17/A-23/B-03/B-04）。
      //   · 带凭证请求跨主机 = 凭证外泄（authorization / cookie / api-key …，
      //     见 _kSensitiveHeaders）；
      //   · 无凭证请求跨主机也可能打内网 / 云元数据，或把 https 降级成 http
      //     （_ogLIsSafeRedirectTarget 已拦降级与私网目标）。
      //   3xx 原样交还上层，由 GhClient 映射成显式失败（如实报错，不静默）。
      if (_carriesSensitiveHeader(request.headers)) {
        // 带凭证的跨主机跳转：**明确拒绝**（不跟随、不重发凭证）。
        // 交还 3xx 让上层报错；用户看到的是"该地址要求跨站跳转，已拒绝"。
        return response;
      }
      return response;
    }
    // 同源跟随：RFC 7231 §6.4.3 / §6.4.4 —— 302/303 只对 **POST** 降级为
    // GET 且丢 body；PUT/DELETE/PATCH 必须保持原方法与 body（否则一次保存
    // 会被静默变成空 GET，用户看到"提交成功"其实什么都没写）。
    // 307/308 一律保持原方法与 body（RFC 7231 §6.4.7）。
    final bool switchToGet = (status == HttpStatus.movedTemporarily ||
            status == HttpStatus.seeOther) &&
        request.method == NetMethod.post;
    final Object? nextBody = switchToGet
        ? null
        : (identical(bodyOverride, _kUnset) ? request.body : bodyOverride);
    await response.drain<void>();
    if (switchToGet) {
      // ★ B1-A-30：降级为 GET 且丢 body 时，与 body 绑定的头必须一并剔除
      //   （Content-Length/Content-Type/If-Match …）——否则第二跳带着
      //   "Content-Length: N" 却没有 body，会挂起或直接 400。
      return _sendWithGuardedRedirect(
        NetMethod.get.verb,
        next,
        request.copyWith(headers: _withoutBodyBoundHeaders(request.headers)),
        redirectsLeft: redirectsLeft - 1,
        bodyOverride: nextBody,
        receiveTimeout: receiveTimeout,
      );
    }
    return _sendWithGuardedRedirect(
      verb,
      next,
      request,
      redirectsLeft: redirectsLeft - 1,
      bodyOverride: nextBody,
      receiveTimeout: receiveTimeout,
    );
  }

  /// 请求是否携带凭证头（B1-A-17/B1-B-03）。
  ///
  /// 集合覆盖 authorization / proxy-authorization / cookie / x-auth-token /
  /// api-key / x-api-key —— dart:io 的自动跟随会原样重发全部头，
  /// 跨主机跳转时等于把这些凭证送到第三方。
  static bool _carriesSensitiveHeader(Map<String, String> headers) {
    for (final String key in headers.keys) {
      if (_kSensitiveHeaders.contains(key.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// 剔除与请求体绑定的头（B1-A-30）：降级 GET 且无 body 时必须一起去掉。
  static Map<String, String> _withoutBodyBoundHeaders(
    Map<String, String> headers,
  ) {
    final Map<String, String> out = <String, String>{};
    for (final MapEntry<String, String> entry in headers.entries) {
      if (_kBodyBoundHeaders.contains(entry.key.toLowerCase())) {
        continue;
      }
      out[entry.key] = entry.value;
    }
    return out;
  }

  /// 写请求体（含默认 Content-Type 注入；从 send() 抽出复用）。
  ///
  /// [bodyOverride] 用哨兵区分「未指定」（沿用 [NetRequest.body]）与
  /// 「显式 `null`」（明确无 body）——手动重定向跟随把 302/303 降级为
  /// GET 时正是传 `null` 以丢弃原 body。
  void _writeBody(
    HttpClientRequest req,
    NetRequest request, {
    Object? bodyOverride = _kUnset,
  }) {
    // 核心：**禁用 keep-alive 复用**。复用已被对端（或中间设备）关闭的连接，
    // 只会得到 "Connection closed before full header"；不复用则不会。
    req.persistentConnection = false;
    final Object? body;
    if (!identical(bodyOverride, _kUnset)) {
      body = bodyOverride; // 显式指定（可能是 null = 明确不要 body）。
    } else {
      body = request.body;
    }
    if (body != null) {
      final bool hasContentType = request.headers.keys.any(
        (String key) => key.toLowerCase() == 'content-type',
      );
      if (!hasContentType) {
        req.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
      }
      if (body is List<int>) {
        req.add(body);
      } else {
        req.add(utf8.encode('$body'));
      }
    }
  }

  /// 连接类失败的统一善后：清 DNS 缓存 + 跑自检，把 errno 级真相附进消息。
  ///
  /// 清缓存是为了让**下一次重试重新解析**，避免钉死在某个坏 IP 上。
  Future<String> _selfTestReport(NetRequest request) async {
    _dns?.cache.clear();
    final String host = Uri.tryParse(request.url)?.host ?? '';
    if (host.isEmpty) {
      return '（无主机名，跳过自检）';
    }
    try {
      return await NetSelfTest.cachedOrRun(host);
    } on Object catch (error) {
      return '自检异常: $error';
    }
  }

  static Map<String, String> _flattenHeaders(HttpHeaders headers) {
    final Map<String, String> result = <String, String>{};
    headers.forEach((String name, List<String> values) {
      result[name.toLowerCase()] = values.join(', ');
    });
    return result;
  }
}

/// DoH 所需的**最小** HTTP 能力：基于 `dart:io HttpClient`。
///
/// **刻意不使用自定义 DNS**：如果 DoH 端点自己也要靠自定义解析才能连上，
/// 就成了先有鸡还是先有蛋。DoH 端点域名一律交给系统解析——
/// 这正是 DoH 存在的意义（它走 443，而系统解析通常至少能拿到可连的 IP）。
class IoDnsHttpClient implements DnsHttpClient {
  /// 创建客户端。
  IoDnsHttpClient({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.idleTimeout = const Duration(seconds: 3);
    _client.connectionTimeout = const Duration(seconds: 8);
    _client.userAgent = 'OhGithubLost';
  }

  static const Duration _timeout = Duration(seconds: 8);

  final HttpClient _client;

  @override
  Future<String> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    var uri = Uri.parse(url);
    // ★ B1-A-22/B1-B-09：手动跟随 + 拒绝降级——https DoH 端点被 302 到
    //   http 时，加密查询会变成明文（中间人可篡改 DNS 应答指向任意 IP）。
    //   此前用 `getUrl` 自动跟随 5 跳，降级与跨主机都静默放行。
    for (var hop = 0; hop < 3; hop++) {
      final HttpClientRequest req =
          await _client.openUrl('GET', uri).timeout(_timeout);
      headers.forEach((String key, String value) {
        req.headers.set(key, value);
      });
      req.persistentConnection = false;
      final HttpClientResponse response = await req.close().timeout(_timeout);
      final int status = response.statusCode;
      if (status >= 300 && status < 400) {
        final String? location =
            response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw HttpException('重定向缺少 Location（$url）', uri: uri);
        }
        final Uri next = uri.resolve(location);
        if (next.scheme != 'https') {
          await response.drain<void>();
          throw HttpException(
            '重定向降级（${uri.scheme} → ${next.scheme}），已拒绝',
            uri: uri,
          );
        }
        await response.drain<void>();
        uri = next;
        continue;
      }
      final String text =
          await response.transform(utf8.decoder).join().timeout(_timeout);
      if (status < 200 || status >= 300) {
        throw HttpException('HTTP $status（$uri）', uri: uri);
      }
      return text;
    }
    throw HttpException('重定向次数超限（$url）', uri: uri);
  }
}

/// 装配用工厂：返回 [IoNetTransport]（`net_bridge.dart` 的装配入口）。
NetTransport createPlatformNetTransport(
  DnsService? dns, {
  Duration connectTimeout = const Duration(seconds: 15),
}) =>
    IoNetTransport(dns: dns, connectTimeout: connectTimeout);
