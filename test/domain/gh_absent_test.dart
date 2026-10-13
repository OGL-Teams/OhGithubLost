/// L2 中枢级 · "没有 / 空 / 未启用"的领域语义（W7 回归）。
///
/// 这三件事在 GitHub 上是**正常状态**，不是错误：
/// - 仓库为空 → git data 端点返回 409（`Git Repository is empty.`）；
/// - 路径 / 资源不存在 → 404；
/// - 功能未启用（Pages / Actions）→ 404。
///
/// 它们必须是"没有"，否则整个标签会变成红条 —— 用户看到的就是"标签失效"。
/// 另外：**未知默认分支绝不能瞎猜**（猜 `main` 会让 `master` 仓库全盘 404）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/gh/gh_api.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';

/// 造一个"回放脚本"的响应。
NetResponse _json(Object? body, {int status = 200}) => NetResponse(
      statusCode: status,
      body: body == null ? '' : jsonEncode(body),
      duration: const Duration(milliseconds: 5),
      headers: const <String, String>{'content-type': 'application/json'},
    );

/// 造一个由脚本驱动的 [GhApi]（一个字节都不出网）。
GhApi _api(ScriptedTransport transport) => GhApi(
      client: GhClient(
        net: NetBridge(transport: transport, observer: NetObserver()),
        auth: GhAuthService(vault: InMemoryVault(), store: InMemoryKv()),
      ),
    );

void main() {
  group('空 / 无 / 未启用 ⇒ "没有"，不是"失败"', () {
    test('空仓库（409）⇒ 空目录', () async {
      final transport = ScriptedTransport(<Object>[
        _json(<String, dynamic>{'message': 'Git Repository is empty.'},
            status: 409),
      ]);
      expect(await _api(transport).listDirectory('a/b', ''), isEmpty);
    });

    test('空仓库（409）⇒ 没有提交', () async {
      final transport = ScriptedTransport(<Object>[
        _json(<String, dynamic>{'message': 'Git Repository is empty.'},
            status: 409),
      ]);
      expect(await _api(transport).commits('a/b'), isEmpty);
    });

    test('不存在（404）⇒ 读不到（null），不抛', () async {
      final transport = ScriptedTransport(<Object>[_json(null, status: 404)]);
      expect(await _api(transport).content('a/b', 'missing.txt'), isNull);
    });

    test('目录不存在（404）⇒ 空列表', () async {
      final transport = ScriptedTransport(<Object>[_json(null, status: 404)]);
      expect(await _api(transport).listDirectory('a/b', 'nope/'), isEmpty);
    });

    test('议题返回空数组 ⇒ 空列表（不是失败）', () async {
      final transport = ScriptedTransport(<Object>[_json(<Object?>[])]);
      expect(await _api(transport).issues('a/b'), isEmpty);
    });

    test('页面信息不存在（404）⇒ null（判为"未启用"）', () async {
      final transport = ScriptedTransport(<Object>[_json(null, status: 404)]);
      expect(await _api(transport).pagesInfo('a/b'), isNull);
    });
  });

  group('未知默认分支不得瞎猜', () {
    test('空分支名 ⇒ 不带 ref 参数（交给 GitHub 用真实默认分支）', () async {
      final transport = ScriptedTransport(<Object>[
        _json(<Object?>[]),
      ]);
      await _api(transport).listDirectory('a/b', '', branch: '');
      final url = transport.received.first.url;
      expect(url.contains('ref='), isFalse,
          reason: '空分支名必须省略 ref；否则 master 仓库会全盘 404');
    });

    test('空分支名 ⇒ 提交接口不带 sha 参数', () async {
      final transport = ScriptedTransport(<Object>[_json(<Object?>[])]);
      await _api(transport).commits('a/b', branch: '');
      final url = transport.received.first.url;
      expect(url.contains('sha='), isFalse);
    });

    test('解析出的仓库在缺 default_branch 时是空串（不再伪装成 main）', () {
      final GhRepo repo = GhRepo.fromJson(<String, dynamic>{
        'full_name': 'a/b',
        'owner': <String, dynamic>{'login': 'a'},
        'name': 'b',
      });
      expect(repo.defaultBranch, isEmpty,
          reason: '猜成 main 会让默认分支是 master 的仓库全盘 404');
    });
  });
}
