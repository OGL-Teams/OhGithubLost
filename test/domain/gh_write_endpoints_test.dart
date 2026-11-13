/// L2 中枢级 · 四线新增写端点的离线回归（B3 交叉审计补充）。
///
/// 只断言「请求方法 / 路径 / 请求体」——端点语义由官方 OpenAPI 裁决，
/// 用脚本化回放即可，无需网络与登录态。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/gh/gh_api.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';

/// 记录所有发出的请求；脚本响应为空时回 200 空对象。
class _RecordingTransport implements NetTransport {
  final List<NetRequest> received = <NetRequest>[];

  @override
  Future<NetResponse> send(NetRequest request) async {
    received.add(request);
    return NetResponse(
      statusCode: 200,
      body: '{}',
      duration: const Duration(milliseconds: 1),
    );
  }
}

NetBridge _bridge(_RecordingTransport transport) => NetBridge(
      transport: transport,
      observer: NetObserver(),
    );

GhClient _client(NetBridge bridge) => GhClient(
      net: bridge,
      auth: GhAuthService(vault: InMemoryVault(), store: InMemoryKv()),
    );

void main() {
  test('锁定讨论必须用 PUT（GitHub issues/lock，PATCH 会 404）', () async {
    final _RecordingTransport net = _RecordingTransport();
    final GhApi api = GhApi(client: _client(_bridge(net)));

    await api.lockIssue('alice/blog', 7, lockReason: 'resolved');

    expect(net.received, hasLength(1));
    final NetRequest request = net.received.single;
    expect(request.method, NetMethod.put);
    expect(request.url, endsWith('/repos/alice/blog/issues/7/lock'));
    final Map<String, dynamic> body =
        jsonDecode(request.body as String) as Map<String, dynamic>;
    expect(body['lock_reason'], 'resolved');
  });

  test('解锁讨论用 DELETE 且不带 body', () async {
    final _RecordingTransport net = _RecordingTransport();
    final GhApi api = GhApi(client: _client(_bridge(net)));

    await api.unlockIssue('alice/blog', 7);

    expect(net.received.single.method, NetMethod.delete);
    expect(net.received.single.body, isNull);
  });
}
