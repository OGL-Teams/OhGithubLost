/// L1 底座级 · 网络自检的**平台实现**（非 Web）。
///
/// 完整自检：DNS 解析（A / AAAA）→ 逐地址 TCP 连接 → 两条"原生栈"探针
/// （裸 TLS 与 `HttpClient`）。这是 `NetSelfTest.run` 在原生平台上的实现。
///
/// Web 对应文件为 `net_self_test_impl_web.dart`（只做 HTTP 可达性，
/// 不做 DNS / UDP 探测——浏览器里没有这些 API）。
///
/// 本文件允许 `import 'dart:io'`：它只在非 Web 构建里参与编译
/// （由 `net_self_test.dart` 的条件导入选定）。
library;

import 'dart:io';

/// 平台自检实现（非 Web）。
abstract final class NetSelfTestImpl {
  /// 运行自检，返回单行报告。
  static Future<String> run(
    String host, {
    int port = 443,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final lines = <String>['$host:$port'];
    final v4 = await _lookupSafe(host, InternetAddressType.IPv4, timeout);
    final v6 = await _lookupSafe(host, InternetAddressType.IPv6, timeout);
    lines.add('DNS-A(IPv4): ${v4.text}');
    lines.add('DNS-AAAA(IPv6): ${v6.text}');
    final addresses = <InternetAddress>[...v4.addrs, ...v6.addrs];
    if (addresses.isEmpty) {
      return lines.join(' | ');
    }
    for (final address in addresses) {
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(address, port, timeout: timeout);
        sw.stop();
        lines.add('TCP[${address.address}]: OK ${sw.elapsedMilliseconds}ms');
        socket.destroy();
      } on Object catch (error) {
        sw.stop();
        lines.add(
          'TCP[${address.address}]: 失败 ${sw.elapsedMilliseconds}ms → $error',
        );
      }
    }
    // ── 追加：两条"原生栈"探针（定位故障层：TLS？HttpClient？）──
    final ipv4s =
        v4.addrs.where((a) => a.type == InternetAddressType.IPv4).toList();
    if (ipv4s.isNotEmpty) {
      final addr = ipv4s.first;
      final swT = Stopwatch()..start();
      try {
        final raw = await Socket.connect(addr, port, timeout: timeout);
        final tls = await SecureSocket.secure(raw, host: host).timeout(timeout);
        tls.write(
          'GET /zen HTTP/1.1\r\nHost: $host\r\n'
          'User-Agent: ogl-selftest\r\n'
          'accept: application/vnd.github+json\r\n'
          'x-github-api-version: 2022-11-28\r\n'
          'Connection: close\r\n\r\n',
        );
        final first = await tls.first.timeout(timeout);
        swT.stop();
        final line1 = String.fromCharCodes(first).split('\r\n').first;
        lines.add('TLS(原生): $line1 · ${swT.elapsedMilliseconds}ms');
        await tls.close();
      } on Object catch (error) {
        swT.stop();
        lines.add('TLS(原生): 失败 ${swT.elapsedMilliseconds}ms → $error');
      }
      final swH = Stopwatch()..start();
      HttpClient? hc;
      try {
        hc = HttpClient()..connectionTimeout = timeout;
        final req =
            await hc.getUrl(Uri.parse('https://$host/zen')).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        swH.stop();
        lines.add(
          'HTTP(dart原生): ${resp.statusCode} · ${swH.elapsedMilliseconds}ms',
        );
        // 追加：带「凭据头」的 /user 探测（复刻登录请求的头部形状，假令牌）。
        try {
          final req2 =
              await hc.getUrl(Uri.parse('https://$host/user')).timeout(timeout);
          req2.headers.set('accept', 'application/vnd.github+json');
          req2.headers.set('x-github-api-version', '2022-11-28');
          req2.headers.set('authorization', 'Bearer selftest-fake');
          final resp2 = await req2.close().timeout(timeout);
          lines.add('HTTP(带凭据头 /user): ${resp2.statusCode}');
        } on Object catch (error) {
          lines.add('HTTP(带凭据头 /user): 失败 → $error');
        }
      } on Object catch (error) {
        swH.stop();
        lines.add('HTTP(dart原生): 失败 ${swH.elapsedMilliseconds}ms → $error');
      } finally {
        // 成败都要释放连接池（旧实现只在成功路径关闭，失败一次泄漏一组连接）。
        hc?.close(force: true);
      }
    }
    return lines.join(' | ');
  }

  /// 单类型解析（**绝不抛**：失败以文本返回，便于日志直读）。
  static Future<({List<InternetAddress> addrs, String text})> _lookupSafe(
    String host,
    InternetAddressType type,
    Duration timeout,
  ) async {
    try {
      final addrs =
          await InternetAddress.lookup(host, type: type).timeout(timeout);
      return (
        addrs: addrs,
        text: addrs.isEmpty ? '空' : addrs.map((a) => a.address).join(','),
      );
    } on Object catch (error) {
      return (addrs: const <InternetAddress>[], text: '失败($error)');
    }
  }
}
