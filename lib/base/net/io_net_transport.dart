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
    client.connectionFactory = (
      Uri uri,
      String? proxyHost,
      int? proxyPort,
    ) async {
      const Duration connectTimeout = Duration(seconds: 15);
      if (proxyHost != null && proxyPort != null) {
        return Socket.startConnect(proxyHost, proxyPort)
            .timeout(connectTimeout);
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
          return await Socket.startConnect(address, port)
              .timeout(connectTimeout);
        } catch (error) {
          lastError = error;
        }
      }
      // 降级：自定义解析全军覆没 → 交给系统解析再试一次（绝不静默）。
      try {
        return await Socket.startConnect(uri.host, port)
            .timeout(connectTimeout);
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
      final HttpClientRequest req = await _client
          .openUrl(request.method.verb, uri)
          .timeout(connectTimeout);
      req.followRedirects = true;
      req.maxRedirects = 5;
      request.headers.forEach((String key, String value) {
        req.headers.set(key, value);
      });
      // 核心：**禁用 keep-alive 复用**。复用已被对端（或中间设备）关闭的连接，
      // 只会得到 "Connection closed before full header"；不复用则不会。
      req.persistentConnection = false;
      final Object? body = request.body;
      if (body != null) {
        final bool hasContentType = request.headers.keys
            .any((String key) => key.toLowerCase() == 'content-type');
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

      final HttpClientResponse response =
          await req.close().timeout(receiveTimeout);
      final String text =
          await response.transform(utf8.decoder).join().timeout(receiveTimeout);
      stopwatch.stop();
      return NetResponse(
        statusCode: response.statusCode,
        body: text,
        duration: stopwatch.elapsed,
        headers: _flattenHeaders(response.headers),
      );
    } on TimeoutException catch (error) {
      stopwatch.stop();
      throw NetException(
        NetErrorKind.timeout,
        '请求超时（$error）',
        cause: error,
      );
    } on HandshakeException catch (error) {
      stopwatch.stop();
      throw NetException(
        NetErrorKind.tls,
        '证书校验失败：$error',
        cause: error,
      );
    } on TlsException catch (error) {
      stopwatch.stop();
      throw NetException(
        NetErrorKind.tls,
        'TLS 握手失败：$error',
        cause: error,
      );
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
    } on Object catch (error) {
      stopwatch.stop();
      throw NetException(
        NetErrorKind.unknown,
        '未知网络错误（$error）',
        cause: error,
      );
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
    final Uri uri = Uri.parse(url);
    final HttpClientRequest req = await _client.getUrl(uri).timeout(_timeout);
    headers.forEach((String key, String value) {
      req.headers.set(key, value);
    });
    req.persistentConnection = false;
    final HttpClientResponse response = await req.close().timeout(_timeout);
    final String text =
        await response.transform(utf8.decoder).join().timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}（$url）', uri: uri);
    }
    return text;
  }
}

/// 装配用工厂：返回 [IoNetTransport]（`net_bridge.dart` 的装配入口）。
NetTransport createPlatformNetTransport(
  DnsService? dns, {
  Duration connectTimeout = const Duration(seconds: 15),
}) =>
    IoNetTransport(dns: dns, connectTimeout: connectTimeout);
