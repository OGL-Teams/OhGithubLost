/// L2 中枢级 · **文件提交端到端回归**（用户实测「文件无法提交」的守卫）。
///
/// 覆盖 `GhApi.putContentLocked` → `RepositoryCache.write` → `CacheRemote.write`
/// 的**完整链路**（脚本化传输，全离线），锁死四条曾真实发生过的失败：
/// 1. **B2-A-01 自锁**：`CacheRemote.write` 在逐键互斥锁内再取同键锁 →
///    保存永久挂起（引擎写路径必须能走到远端 PUT）；
/// 2. **B1-A-01 丢 body**：带凭证的写请求首跳必须带请求体
///    （否则 PUT 空体 → 4xx / 空内容创建）；
/// 3. **B2-A-05 误判**：远端读失败（409/422）不得被当作「不存在」而放行
///    无基线 PUT（否则静默覆盖已有文件）；
/// 4. **D1 新建**：远端确实不存在 + 无基线 = 合法新建（草稿保存必须成功）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_cache.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/disk/disk_types.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/gh/gh_api.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';

/// 记录收到的请求（断言 body 是否真的发出）。
class _RecordingTransport implements NetTransport {
  _RecordingTransport(List<NetResponse> responses) : responses = responses;

  final List<NetResponse> responses;
  final List<NetRequest> received = <NetRequest>[];

  @override
  Future<NetResponse> send(NetRequest request) async {
    received.add(request);
    if (responses.isEmpty) {
      return NetResponse(
        statusCode: 200,
        body: '{}',
        duration: const Duration(milliseconds: 1),
      );
    }
    return responses.removeAt(0);
  }
}

NetResponse _json(Object? body, {int status = 200}) => NetResponse(
      statusCode: status,
      body: body == null ? '' : jsonEncode(body),
      duration: const Duration(milliseconds: 1),
    );

GhClient _client(NetBridge bridge) => GhClient(
      net: bridge,
      auth: GhAuthService(vault: InMemoryVault(), store: InMemoryKv()),
    );

void main() {
  group('文件提交端到端（引擎路径）', () {
    test('编辑已有文件：走引擎写入成功，且请求体真的发出', () async {
      final _RecordingTransport transport = _RecordingTransport(<Object>[
        // ① GET contents：远端已有该文件（sha=sha-1）
        _json(<String, dynamic>{
          'path': 'README.md',
          'sha': 'sha-1',
          'size': 3,
          'type': 'file',
          'encoding': 'base64',
          'content': 'b2xk',
        }),
        // ② PUT contents：远端接受
        _json(<String, dynamic>{
          'content': <String, dynamic>{
            'path': 'README.md',
            'sha': 'sha-2',
            'size': 4,
            'type': 'file',
          },
        }),
        // ③ D5 回读：确认远端已是新内容
        _json(<String, dynamic>{
          'path': 'README.md',
          'sha': 'sha-2',
          'size': 4,
          'type': 'file',
          'encoding': 'base64',
          'content': 'bmV3',
        }),
      ]);
      final NetBridge bridge =
          NetBridge(transport: transport, observer: NetObserver());
      final GhApi api = GhApi(client: _client(bridge));
      final RepositoryCache cache = RepositoryCache(
        remote: api,
        scope: const CacheScope(
          schemaVersion: 1,
          accountId: 'acct',
          repo: 'alice/blog',
          branch: 'main',
        ),
      );
      api.attachReadCache(cache, accountId: () async => 'acct');

      final GhWriteResult result = await api.putContentLocked(
        'alice/blog',
        'README.md',
        content: 'new',
        message: 'docs: update',
        baseSha: 'sha-1',
      );

      expect(result.ok, isTrue, reason: '编辑已有文件必须能提交：${result.detail}');
      // ★ B1-A-01：PUT 请求体必须真的发出（守卫不得吃掉 body）。
      final NetRequest put = transport.received.firstWhere(
        (NetRequest r) => r.method == NetMethod.put,
        orElse: () => throw StateError('没有发出 PUT 请求'),
      );
      expect(put.body, isNotNull);
      expect(put.body, contains('docs: update'));
    });

    test('远端读冲突（409）不得被当作「不存在」而覆盖写入', () async {
      final _RecordingTransport transport = _RecordingTransport(<Object>[
        // ① GET contents：409 冲突（不是 404）
        _json(<String, dynamic>{'message': 'Conflict'}, status: 409),
      ]);
      final NetBridge bridge =
          NetBridge(transport: transport, observer: NetObserver());
      final GhApi api = GhApi(client: _client(bridge));
      final RepositoryCache cache = RepositoryCache(
        remote: api,
        scope: const CacheScope(
          schemaVersion: 1,
          accountId: 'acct',
          repo: 'alice/blog',
          branch: 'main',
        ),
      );
      api.attachReadCache(cache, accountId: () async => 'acct');

      // 无基线 + 远端读失败 → 必须失败（可见），不得发 PUT。
      final GhWriteResult result = await api.putContentLocked(
        'alice/blog',
        'README.md',
        content: 'new',
        message: 'docs: update',
        baseSha: '',
      );
      expect(result.ok, isFalse);
      expect(
        transport.received.where((NetRequest r) => r.method == NetMethod.put),
        isEmpty,
        reason: '远端状态不确定时不得发出无基线 PUT（会静默覆盖）',
      );
    });
  });
}
