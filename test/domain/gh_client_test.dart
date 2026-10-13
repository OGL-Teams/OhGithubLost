/// L2 中枢级 · GitHub 客户端与端点封装测试。
///
/// 全程离线：`NetBridge` 里塞的是脚本化传输，一个字节都不发到网络。
///
/// 重点验证四件事：
/// 1. **限流避让**：已知额度耗尽时**不再发请求**；
/// 2. **错误映射**：401/403/404/409/422 → 类型化异常（409 要变成远端冲突）；
/// 3. **分页**：`Link` 头驱动，且有安全上限；
/// 4. **CacheRemote 适配**：底座的一致性引擎接到真实 API 后语义不变
///    （尤其 `>1 MB` 走 Blobs、拿不到内容不返回空串）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/disk/disk_types.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/gh/gh_api.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';

/// 构造一个"回放脚本"的 NetBridge。
NetBridge _bridge(List<NetResponse> responses) => NetBridge(
      transport: ScriptedTransport(List<Object>.of(responses)),
      observer: NetObserver(),
    );

NetResponse _json(
  Object? body, {
  int status = 200,
  Map<String, String>? headers,
}) =>
    NetResponse(
      statusCode: status,
      body: body == null ? '' : jsonEncode(body),
      duration: const Duration(milliseconds: 5),
      headers: headers ?? const <String, String>{},
    );

const CacheScope _scope = CacheScope(
  schemaVersion: 1,
  accountId: 'acct',
  repo: 'alice/blog',
  branch: 'main',
);

const CacheKey _key = CacheKey(scope: _scope, path: 'src/main.dart');

/// 未登录客户端（不带 Authorization 头，便于断言）。
GhClient _client(NetBridge bridge) => GhClient(
      net: bridge,
      auth: GhAuthService(vault: InMemoryVault(), store: InMemoryKv()),
    );

void main() {
  group('请求构造与认证头', () {
    test('已登录时自动带上 Bearer 令牌', () async {
      final vault = InMemoryVault();
      final store = InMemoryKv();
      final auth = GhAuthService(vault: vault, store: store);
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'alice'),
        const GhToken('ghp_testtoken123456'),
      );
      await auth.switchTo('1');

      final holding = ScriptedTransport(
          <Object>[_json(<String, dynamic>{}), _json(<String, dynamic>{})]);
      final bridge = NetBridge(transport: holding, observer: NetObserver());
      final client = GhClient(net: bridge, auth: auth);
      await client.getObject('/user');

      expect(holding.received.first.headers['authorization'],
          'Bearer ghp_testtoken123456');
      expect(holding.received.first.headers['accept'],
          'application/vnd.github+json');
    });

    test('查询参数会被编码进 URL', () async {
      final holding = ScriptedTransport(<Object>[_json(<String, dynamic>{})]);
      final client = _client(NetBridge(
        transport: holding,
        observer: NetObserver(),
      ));
      await client.getObject(
        '/search/repositories',
        query: <String, String>{'q': 'a b&c', 'page': '2'},
      );
      final url = holding.received.first.url;
      expect(url, contains('q=a%20b%26c'));
      expect(url, contains('page=2'));
    });
  });

  group('错误映射', () {
    test('401 → GhAuthException', () async {
      final client = _client(_bridge(<NetResponse>[_json(null, status: 401)]));
      await expectLater(
        client.getObject('/user'),
        throwsA(isA<GhAuthException>()),
      );
    });

    test('404 → GhNotFoundException', () async {
      final client = _client(_bridge(<NetResponse>[_json(null, status: 404)]));
      await expectLater(
        client.getObject('/repos/x/y'),
        throwsA(isA<GhNotFoundException>()),
      );
    });

    test('403 且额度耗尽 → GhRateLimitException（主限流）', () async {
      final reset =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final client = _client(_bridge(<NetResponse>[
        _json(null, status: 403, headers: <String, String>{
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '$reset',
        }),
      ]));
      await expectLater(
        client.getObject('/user'),
        throwsA(isA<GhRateLimitException>().having(
            (GhRateLimitException e) => e.secondary, 'secondary', false)),
      );
    });

    test('403 且带 retry-after → 次要限流', () async {
      final client = _client(_bridge(<NetResponse>[
        _json(null, status: 403, headers: <String, String>{
          'retry-after': '30',
        }),
      ]));
      await expectLater(
        client.getObject('/user'),
        throwsA(isA<GhRateLimitException>().having(
            (GhRateLimitException e) => e.secondary, 'secondary', true)),
      );
    });

    test('403 无任何限流信号 → 权限不足', () async {
      final client = _client(_bridge(<NetResponse>[_json(null, status: 403)]));
      await expectLater(
        client.getObject('/user'),
        throwsA(isA<GhAuthException>()),
      );
    });

    test('409/422 默认不当冲突（普通写），显式开启才转成远端冲突', () async {
      final plain = _client(_bridge(<NetResponse>[_json(null, status: 422)]));
      await expectLater(
        plain.send(const GhRequest(
          path: '/repos/a/b/contents/x',
          method: NetMethod.put,
        )),
        throwsA(isA<GhAuthException>()),
      );

      final conflicting = _client(_bridge(<NetResponse>[
        _json(null, status: 409, headers: <String, String>{
          'content-type': 'application/json',
        }),
      ]));
      await expectLater(
        conflicting.send(const GhRequest(
          path: '/repos/a/b/contents/x',
          method: NetMethod.put,
          conflictsAsRemoteConflict: true,
        )),
        throwsA(isA<RemoteConflictException>()),
      );
    });

    test('成功响应返回结构化 GhResponse（含分页与额度）', () async {
      final client = _client(_bridge(<NetResponse>[
        _json(<Map<String, dynamic>>[
          <String, dynamic>{'login': 'alice'},
        ], headers: <String, String>{
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '10',
          'x-ratelimit-reset': '9999999999',
        }),
      ]));
      final response = await client.send(const GhRequest(path: '/user'));
      expect(response.isSuccess, isTrue);
      expect(response.jsonAsList.length, 1);
      expect(response.rateLimit?.remaining, 10);
    });
  });

  group('限流避让', () {
    test('已知额度耗尽 → 不再发请求，直接报何时恢复', () async {
      final reset =
          DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
              1000;
      final holding = ScriptedTransport(<Object>[
        _json(<String, dynamic>{
          'ok': true
        }, headers: <String, String>{
          'x-ratelimit-limit': '5000',
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '$reset',
        }),
      ]);
      final client = _client(
        NetBridge(transport: holding, observer: NetObserver()),
      );

      // 第一次：请求成功，但把"额度已耗尽"记下来。
      await client.getObject('/user');
      expect(holding.received.length, 1);
      expect(client.lastRateLimit?.isExhausted, isTrue);

      // 第二次：必须在**发出请求之前**就失败。
      await expectLater(
        client.getObject('/user'),
        throwsA(isA<GhRateLimitException>()),
      );
      expect(
        holding.received.length,
        1,
        reason: '额度耗尽时不该再浪费一次注定 403 的往返',
      );
    });
  });

  group('分页', () {
    test('按 Link 头翻页，无 next 即停', () async {
      final client = _client(_bridge(<NetResponse>[
        _json(<Map<String, dynamic>>[
          <String, dynamic>{'full_name': 'a/1'},
        ], headers: <String, String>{
          'link': '<https://api.github.com/user/repos?page=2>; rel="next"',
        }),
        _json(<Map<String, dynamic>>[
          <String, dynamic>{'full_name': 'a/2'},
        ]),
      ]));

      final pages = <List<Map<String, dynamic>>>[];
      await for (final page in client.paginate('/user/repos')) {
        pages.add(page);
      }
      expect(pages.length, 2);
      expect(pages.first.first['full_name'], 'a/1');
      expect(pages.last.first['full_name'], 'a/2');
    });

    test('空页立即结束', () async {
      final client = _client(_bridge(<NetResponse>[
        _json(<Map<String, dynamic>>[]),
      ]));
      final pages = <List<Map<String, dynamic>>>[];
      await for (final page in client.paginate('/user/repos')) {
        pages.add(page);
      }
      expect(pages, isEmpty);
    });
  });

  group('GhApi · 基础端点', () {
    test('仓库列表容错解析（缺字段 / 类型漂移）', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[
          _json(<Map<String, dynamic>>[
            <String, dynamic>{
              'full_name': 'alice/blog',
              'name': 'blog',
              'stargazers_count': '7',
              'owner': <String, dynamic>{'login': 'alice'},
            },
          ]),
        ])),
      );
      final repos = await api.myRepos();
      expect(repos.length, 1);
      expect(repos.first.stars, 7);
      expect(repos.first.ownerLogin, 'alice');
    });

    test('读取 404 内容返回 null（而不是抛）', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[_json(null, status: 404)])),
      );
      expect(await api.content('alice/blog', 'missing.txt'), isNull);
    });

    test('目录列表为空时返回空列表', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[_json(null, status: 404)])),
      );
      expect(await api.listDirectory('alice/blog', 'src'), isEmpty);
    });

    test('批量提交：先校验基线，再建 blob，最后成树成提交移引用', () async {
      final holding = ScriptedTransport(<Object>[
        // 1) 取分支顶端（**必须在建 blob 之前**）
        _json(<String, dynamic>{
          'object': <String, dynamic>{'sha': 'head1'},
        }),
        // 2) 取该提交的 tree
        _json(<String, dynamic>{
          'tree': <String, dynamic>{'sha': 'basetree'},
        }),
        // 3) 建 blob
        _json(<String, dynamic>{'sha': 'blob1'}),
        // 4) 建 tree
        _json(<String, dynamic>{'sha': 'tree1'}),
        // 5) 建 commit
        _json(<String, dynamic>{'sha': 'commit1'}),
        // 6) 移动引用
        _json(<String, dynamic>{'ok': true}),
      ]);
      final api = GhApi(
        client: _client(NetBridge(transport: holding, observer: NetObserver())),
      );

      final sha = await api.commitFiles(
        'alice/blog',
        branch: 'main',
        upserts: <String, String>{'a.txt': 'hello'},
        message: 'batch',
      );

      expect(sha, 'commit1');
      expect(holding.received.length, 6);
      expect(
        holding.received[0].url,
        contains('/git/ref/heads/main'),
        reason: '基线校验必须排在第一位，避免白建孤儿 blob',
      );
      expect(holding.received[2].url, contains('/git/blobs'));
      final treeBody = jsonDecode(holding.received[3].body! as String);
      expect(treeBody['base_tree'], 'basetree');
      expect(treeBody['tree'][0]['path'], 'a.txt');
      expect(holding.received[5].url, contains('/git/refs/heads/main'));
    });

    test('批量提交前校验期望 sha，分支已前进则拒绝（且不建任何 blob）', () async {
      final holding = ScriptedTransport(<Object>[
        // 只有"取分支顶端"这一次调用——校验失败就不该继续。
        _json(<String, dynamic>{
          'object': <String, dynamic>{'sha': 'moved'},
        }),
      ]);
      final api = GhApi(
        client: _client(NetBridge(transport: holding, observer: NetObserver())),
      );
      await expectLater(
        api.commitFiles(
          'alice/blog',
          branch: 'main',
          upserts: <String, String>{'a.txt': 'x'},
          message: 'm',
          expectedHeadSha: 'old',
        ),
        throwsA(isA<RemoteConflictException>()),
      );
    });
  });

  group('★ CacheRemote 适配（一致性引擎接真实 API）', () {
    test('read：base64 内容 + 指纹', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[
          _json(<String, dynamic>{
            'path': 'src/main.dart',
            'sha': 'shaA',
            'size': 5,
            'type': 'file',
            'encoding': 'base64',
            'content': base64Encode(utf8.encode('hello')),
          }),
        ])),
      );
      final document = await api.read(_key);
      expect(document, isNotNull);
      expect(document!.content, 'hello');
      expect(document.sha, 'shaA');
    });

    test('read：>1 MB 的文件自动改走 Blobs API', () async {
      final holding = ScriptedTransport(<Object>[
        // Contents API 对超大文件省略内容
        _json(<String, dynamic>{
          'path': 'big.bin',
          'sha': 'shaBig',
          'size': 5 * 1024 * 1024,
          'type': 'file',
          'encoding': 'none',
          'content': '',
        }),
        // Blobs API 补齐
        _json(<String, dynamic>{
          'encoding': 'base64',
          'content': base64Encode(utf8.encode('BIG')),
        }),
      ]);
      final api = GhApi(
        client: _client(NetBridge(transport: holding, observer: NetObserver())),
      );

      final document = await api.read(_key);
      expect(document, isNotNull, reason: '绝不能因为内容被省略就当读失败');
      expect(document!.content, 'BIG');
      expect(document.sha, 'shaBig');
      expect(holding.received.length, 2);
      expect(holding.received.last.url, contains('/git/blobs/shaBig'));
    });

    test('read：内容拿不到时返回 null，绝不返回空串', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[
          _json(<String, dynamic>{
            'path': 'x',
            'sha': 'shaX',
            'size': 123,
            'type': 'file',
            'encoding': 'none',
            'content': '',
          }),
          // Blobs 也拿不到
          _json(null, status: 404),
        ])),
      );
      expect(
        await api.read(_key),
        isNull,
        reason: '空串被写回远端就是数据事故',
      );
    });

    test('read：404 → null', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[_json(null, status: 404)])),
      );
      expect(await api.read(_key), isNull);
    });

    test('write：把期望 sha 作为乐观锁基线提交', () async {
      final holding = ScriptedTransport(<Object>[
        _json(<String, dynamic>{
          'content': <String, dynamic>{'sha': 'newSha'},
        }),
      ]);
      final api = GhApi(
        client: _client(NetBridge(transport: holding, observer: NetObserver())),
      );

      final document = await api.write(
        _key,
        'new content',
        message: 'update',
        expectedSha: 'oldSha',
      );

      final body = jsonDecode(holding.received.first.body! as String);
      expect(body['sha'], 'oldSha', reason: '基线必须随请求发出，否则乐观锁失效');
      expect(body['branch'], 'main');
      expect(body['message'], 'update');
      expect(document.sha, 'newSha');
    });

    test('write：远端已变化 → RemoteConflictException（交给 D2/D3）', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[
          _json(<String, dynamic>{'sha': 'theirs'}, status: 409),
        ])),
      );
      await expectLater(
        api.write(_key, 'mine', message: 'm', expectedSha: 'stale'),
        throwsA(
          isA<RemoteConflictException>()
              .having((RemoteConflictException e) => e.isStale, 'isStale', true)
              .having((RemoteConflictException e) => e.currentSha, 'currentSha',
                  'theirs'),
        ),
      );
    });
  });

  group('模型与分页解析联动', () {
    test('树响应里 truncated 会被保留', () async {
      final api = GhApi(
        client: _client(_bridge(<NetResponse>[
          _json(<String, dynamic>{
            'sha': 't',
            'truncated': true,
            'tree': <Map<String, dynamic>>[
              <String, dynamic>{'path': 'a', 'type': 'blob', 'sha': '1'},
            ],
          }),
        ])),
      );
      final tree = await api.tree('alice/blog', branch: 'main');
      expect(tree.truncated, isTrue);
      expect(tree.entries.length, 1);
    });

    test('GhPage 从响应头解析（端到端）', () async {
      final client = _client(_bridge(<NetResponse>[
        _json(<String, dynamic>{
          'ok': true
        }, headers: <String, String>{
          'link': '<https://api.github.com/x?page=3>; rel="next"',
        }),
      ]));
      final response = await client.send(const GhRequest(path: '/x'));
      expect(response.page.hasNext, isTrue);
      expect(GhPage.pageOf(response.page.next), 3);
    });
  });
}
