/// L2/L3 级 · 仓库 Tags 功能离线回归（v13.0.0 S1/S2/S5）。
///
/// 断言请求方法 / 路径 / 请求体与设置持久化往返；不发网络。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/gh/gh_api.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';
import 'package:ohgithublost/surface/settings.dart';

class _RecordingTransport implements NetTransport {
  final List<NetRequest> received = <NetRequest>[];
  String body = '[]';

  @override
  Future<NetResponse> send(NetRequest request) async {
    received.add(request);
    return NetResponse(
      statusCode: 200,
      body: body,
      duration: const Duration(milliseconds: 1),
    );
  }
}

NetBridge _bridge(_RecordingTransport t) =>
    NetBridge(transport: t, observer: NetObserver());

GhApi _api(_RecordingTransport t) => GhApi(
      client: GhClient(
        net: _bridge(t),
        auth: GhAuthService(vault: InMemoryVault(), store: InMemoryKv()),
      ),
    );

void main() {
  test('GhTag 字段解析 / 序列化', () {
    final GhTag tag = GhTag.fromJson(<String, dynamic>{
      'name': 'v1.0.0',
      'commit': <String, dynamic>{
        'sha': 'abcdef1234567',
        'url': 'https://api/x'
      },
    });
    expect(tag.name, 'v1.0.0');
    expect(tag.sha, 'abcdef1234567');
    expect(tag.toJson()['name'], 'v1.0.0');
  });

  test('tags() 走 GET /repos/{full}/tags 且带分页', () async {
    final _RecordingTransport t = _RecordingTransport()
      ..body = jsonEncode(<Object>[
        <String, Object?>{
          'name': 'v1',
          'commit': <String, Object?>{'sha': 'a'}
        },
      ]);
    final List<GhTag> list = await _api(t).tags('o/r', perPage: 50, page: 2);
    expect(list.single.name, 'v1');
    expect(t.received.single.url, contains('/repos/o/r/tags'));
    expect(t.received.single.url, contains('per_page=50'));
    expect(t.received.single.url, contains('page=2'));
  });

  test('createTag 走 POST git/refs 且 body 为 ref+sha', () async {
    final _RecordingTransport t = _RecordingTransport()
      ..body = jsonEncode(<String, Object?>{
        'ref': 'refs/tags/v2',
        'object': <String, Object?>{'sha': 'deadbeef'},
      });
    final GhTag tag =
        await _api(t).createTag('o/r', name: 'v2', sha: 'deadbeef');
    expect(tag.name, 'v2');
    expect(t.received.single.method, NetMethod.post);
    expect(t.received.single.url, endsWith('/repos/o/r/git/refs'));
    final Map<String, dynamic> body =
        jsonDecode(t.received.single.body as String) as Map<String, dynamic>;
    expect(body['ref'], 'refs/tags/v2');
    expect(body['sha'], 'deadbeef');
  });

  test('deleteTag 走 DELETE git/refs/tags/{name}', () async {
    final _RecordingTransport t = _RecordingTransport();
    await _api(t).deleteTag('o/r', 'v3');
    expect(t.received.single.method, NetMethod.delete);
    expect(t.received.single.url, endsWith('/repos/o/r/git/refs/tags/v3'));
  });

  test('tag() 从 Git ref 取 sha', () async {
    final _RecordingTransport t = _RecordingTransport()
      ..body = jsonEncode(<String, Object?>{
        'object': <String, Object?>{'sha': 'cafebabe'},
      });
    final GhTag? tag = await _api(t).tag('o/r', 'v4');
    expect(tag?.sha, 'cafebabe');
    expect(t.received.single.url, endsWith('/repos/o/r/git/ref/tags/v4'));
  });

  test('Tags 三项设置持久化往返（含 false 与坏值回落）', () {
    final OgLSettings a = OgLSettings.fromJson(<String, Object?>{
      'tagSort': 'updated',
      'tagsPerPage': 100,
      'tagDeleteConfirm': false,
    });
    expect(a.tagSort, 'updated');
    expect(a.tagsPerPage, 100);
    expect(a.tagDeleteConfirm, isFalse);
    final OgLSettings b = OgLSettings.fromJson(a.encode().isEmpty
        ? const <String, Object?>{}
        : jsonDecode(a.encode()) as Object?);
    expect(b.tagSort, 'updated');
    expect(b.tagsPerPage, 100);
    expect(b.tagDeleteConfirm, isFalse);
    final OgLSettings bad = OgLSettings.fromJson(<String, Object?>{
      'tagSort': 'nonsense',
      'tagsPerPage': 999,
      'tagDeleteConfirm': 'not-a-bool',
    });
    expect(bad.tagSort, 'name');
    expect(bad.tagsPerPage, 30);
    expect(bad.tagDeleteConfirm, isTrue);
  });
}
