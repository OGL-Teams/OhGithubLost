/// PoC / 回归：**禁用连接复用**后，对端"响应后即关闭连接"不再是故障。
///
/// 背景（2026-10-03 设备日志）：`Connection closed before full header was
/// received` 反复出现，而同一时刻的原生自检全绿——两者唯一差别是
/// **是否复用 keep-alive 连接**。
///
/// 本测试用一个"宣称 `keep-alive`、响应后立即关闭"的极简服务器复现该环境：
/// - 连接策略断言：每个请求必须声明 `connection: close`（不复用）；
/// - 端到端 PoC：连续多次请求必须全部成功。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/io_net_transport.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';

/// 极简 HTTP 服务器：响应后**立即关闭**连接，但响应头里宣称 `keep-alive`。
///
/// 这正是"对端/中间设备在空闲后回收连接"的最小复现：如果客户端复用这条
/// 已死连接，就会得到 `Connection closed before full header`。
class _ClosingHttpServer {
  _ClosingHttpServer._(this._server);

  final ServerSocket _server;

  /// 已服务的请求数。
  int served = 0;

  /// 最近一次收到的请求原文（用于断言连接策略）。
  String lastRequest = '';

  /// 请求地址。
  String get url => 'http://127.0.0.1:${_server.port}/zen';

  /// 启动。
  static Future<_ClosingHttpServer> start() async {
    final ServerSocket socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final _ClosingHttpServer server = _ClosingHttpServer._(socket);
    server._listen();
    return server;
  }

  void _listen() {
    _server.listen((Socket client) {
      final List<int> buffer = <int>[];
      late final StreamSubscription<Uint8List> sub;
      sub = client.listen(
        (Uint8List chunk) {
          buffer.addAll(chunk);
          final String text = String.fromCharCodes(buffer);
          if (!text.contains('\r\n\r\n')) {
            return;
          }
          lastRequest = text;
          sub.cancel();
          unawaited(_respond(client));
        },
        onError: (Object _) {},
        cancelOnError: true,
      );
    });
  }

  Future<void> _respond(Socket client) async {
    served++;
    const String body = '{"ok":true}';
    client.write(
      'HTTP/1.1 200 OK\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: ${body.length}\r\n'
      'Connection: keep-alive\r\n'
      '\r\n'
      '$body',
    );
    try {
      await client.flush();
    } catch (_) {
      // 已断开。
    }
    // 宣称 keep-alive，却在短暂空闲后关闭（模拟服务端 / 中间设备的空闲回收）。
    // 空闲窗口放宽到 50ms：避免慢机器上"响应未读完就 destroy"与读竞态导致 flaky。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      client.destroy();
    } catch (_) {
      // 已关闭。
    }
  }

  /// 关闭。
  Future<void> close() => _server.close();
}

void main() {
  test('连接策略：每个请求都必须声明 connection: close（禁用 keep-alive 复用）', () async {
    final _ClosingHttpServer server = await _ClosingHttpServer.start();
    addTearDown(server.close);

    final IoNetTransport transport = IoNetTransport();
    addTearDown(() => transport.client.close(force: true));

    await transport.send(NetRequest(method: NetMethod.get, url: server.url));

    final String normalized =
        server.lastRequest.toLowerCase().replaceAll(' ', '');
    expect(
      normalized,
      contains('connection:close'),
      reason: '复用已被对端关闭的连接会导致 '
          '"Connection closed before full header was received"',
    );
  });

  test('PoC：对端响应后即关闭连接，连续请求仍必须全部成功', () async {
    final _ClosingHttpServer server = await _ClosingHttpServer.start();
    addTearDown(server.close);

    final IoNetTransport inner = IoNetTransport();
    addTearDown(() => inner.client.close(force: true));
    final ResilientTransport transport = ResilientTransport(
      inner: inner,
      sleep: (Duration _) async {},
    );

    for (int i = 0; i < 4; i++) {
      final NetResponse response = await transport
          .send(NetRequest(
            method: NetMethod.get,
            url: server.url,
            label: 'poc-$i',
          ))
          .timeout(const Duration(seconds: 10));
      expect(response.statusCode, 200, reason: '第 ${i + 1} 次请求必须成功');
      // 停顿足够久（100ms）以越过服务端"空闲即关闭"的窗口（正是复用的窗口）；
      // 30ms 在慢 CI 上会与 20ms 的服务端关闭时序竞态，抖成 flaky。
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(server.served, greaterThanOrEqualTo(2));
  });
}
