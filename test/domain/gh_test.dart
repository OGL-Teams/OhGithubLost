/// L2 中枢级 · GitHub 领域模型与认证测试。
///
/// 重点验证三件事：
/// 1. **容错解析**：服务端少字段 / 类型漂移 / 未知枚举，都不能崩；
/// 2. **>1 MB 内容识别**：Contents API 静默省略内容时必须被识别出来；
/// 3. **令牌安全**：明文永不进 `toString`，删除顺序正确，元数据不含令牌。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

void main() {
  group('容错解析', () {
    test('缺字段不崩，类型漂移能接受', () {
      final repo = GhRepo.fromJson(<String, dynamic>{
        'full_name': 'o/r',
        'name': 'r',
        'stargazers_count': '42', // 字符串数字
        'private': 1, // 数字布尔
        'updated_at': 'not-a-date', // 非法时间 → null
        'future_field': '服务端新加的', // 未知字段
      });
      expect(repo.fullName, 'o/r');
      expect(repo.stars, 42);
      expect(repo.isPrivate, isTrue);
      expect(repo.updatedAt, isNull);
      expect(repo.defaultBranch, isEmpty,
          reason: '不猜默认分支：猜 main 会让默认分支是 master 的仓库整页 404，'
              '留空后由 GET /repos/{full} 兜底补齐');
      expect(repo.raw['future_field'], '服务端新加的', reason: '未知字段必须保留');
    });

    test('空对象也能构造（全部走默认值）', () {
      final repo = GhRepo.fromJson(<String, dynamic>{});
      expect(repo.fullName, isEmpty);
      expect(repo.stars, 0);
      expect(repo.owner.login, isEmpty);
      expect(repo.ownerLogin, isEmpty);
    });

    test('未知树节点类型落到 unknown 而不是抛', () {
      final entry = GhTreeEntry.fromJson(<String, dynamic>{
        'path': 'a/b.txt',
        'type': 'blob-v2', // 假设服务端新增类型
        'sha': 'abc',
      });
      expect(entry.type, GhTreeEntryType.unknown);
      expect(entry.isFile, isFalse);
      expect(entry.name, 'b.txt');
      expect(entry.parentPath, 'a');
    });

    test('根目录节点 parentPath 为空串', () {
      final entry = GhTreeEntry.fromJson(<String, dynamic>{
        'path': 'README.md',
        'type': 'blob',
      });
      expect(entry.parentPath, isEmpty);
      expect(entry.name, 'README.md');
    });

    test('toJsonWithRaw 带上原始 JSON', () {
      final user = GhUser.fromJson(<String, dynamic>{'login': 'x', 'id': 1});
      expect(user.toJsonWithRaw()['raw'], isA<Map<String, dynamic>>());
    });
  });

  group('目录树（truncated 是一等公民）', () {
    test('解析截断标志与子项筛选', () {
      final tree = GhTree.fromJson(<String, dynamic>{
        'sha': 't1',
        'truncated': true,
        'tree': <Map<String, dynamic>>[
          <String, dynamic>{'path': 'src', 'type': 'tree', 'sha': 'a'},
          <String, dynamic>{
            'path': 'src/main.dart',
            'type': 'blob',
            'sha': 'b',
            'size': 10
          },
          <String, dynamic>{'path': 'src/ui', 'type': 'tree', 'sha': 'c'},
          <String, dynamic>{
            'path': 'README.md',
            'type': 'blob',
            'sha': 'd',
            'size': 5
          },
        ],
      });

      expect(tree.truncated, isTrue, reason: '必须暴露截断，否则会静默少文件');
      expect(tree.files.length, 2);
      expect(tree.directories.length, 2);
      expect(
        tree.childrenOf('src').map((GhTreeEntry e) => e.path),
        <String>['src/main.dart', 'src/ui'],
        reason: 'childrenOf 返回的是"该目录的子项"，不含目录自身',
      );
      expect(
        tree.childrenOf('').map((GhTreeEntry e) => e.path),
        <String>['src', 'README.md'],
      );
      expect(tree.toString(), contains('TRUNCATED'));
    });

    test('缺 tree 字段 → 空列表而不是异常', () {
      final tree = GhTree.fromJson(<String, dynamic>{'sha': 't'});
      expect(tree.entries, isEmpty);
      expect(tree.truncated, isFalse);
    });
  });

  group('内容（>1 MB 必须被识别）', () {
    test('正常 base64 内容可解码', () {
      final content = GhContent.fromJson(<String, dynamic>{
        'path': 'a.txt',
        'sha': 's1',
        'size': 5,
        'type': 'file',
        'encoding': 'base64',
        'content': base64Encode(utf8.encode('hello')),
      });
      expect(content.text, 'hello');
      expect(content.isTooLarge, isFalse);
      expect(content.isDirectory, isFalse);
    });

    test('服务端省略内容（>1MB）→ isTooLarge=true，绝不当作空文件', () {
      final content = GhContent.fromJson(<String, dynamic>{
        'path': 'big.bin',
        'sha': 's2',
        'size': 5 * 1024 * 1024,
        'type': 'file',
        'encoding': 'none',
        'content': '',
      });
      expect(content.isTooLarge, isTrue);
      expect(content.text, isNull);
      expect(content.toString(), contains('TOO LARGE'));
    });

    test('空文件（size=0）不算过大', () {
      final content = GhContent.fromJson(<String, dynamic>{
        'path': 'empty.txt',
        'sha': 's3',
        'size': 0,
        'type': 'file',
        'content': '',
      });
      expect(content.isTooLarge, isFalse);
    });

    test('目录不被当作过大', () {
      final content = GhContent.fromJson(<String, dynamic>{
        'path': 'src',
        'sha': 's4',
        'size': 0,
        'type': 'dir',
      });
      expect(content.isDirectory, isTrue);
      expect(content.isTooLarge, isFalse);
    });

    test('非法 base64 返回 null 而不抛', () {
      expect(GhContent.decodeContent('!!!not-base64!!!', 'base64'), isNull);
      expect(GhContent.decodeContent('aGVsbG8=', 'utf-8'), isNull);
      expect(GhContent.decodeContent('', 'base64'), isNull);
    });

    test('带换行的 base64 也能解码', () {
      final encoded = base64Encode(utf8.encode('hello world'));
      final wrapped = encoded.replaceAllMapped(
        RegExp(r'.{4}'),
        (Match m) => '${m.group(0)}\n',
      );
      expect(GhContent.decodeContent(wrapped, 'base64'), 'hello world');
    });
  });

  group('提交与仓库判定', () {
    test('提交取首行作为 subject', () {
      final commit = GhCommit.fromJson(<String, dynamic>{
        'sha': 'c1',
        'commit': <String, dynamic>{
          'message': 'feat: 第一行\n\n详细说明',
          'author': <String, dynamic>{
            'name': '张三',
            'date': '2026-10-01T00:00:00Z',
          },
        },
        'author': <String, dynamic>{'login': 'zhangsan'},
        'parents': <Map<String, dynamic>>[
          <String, dynamic>{'sha': 'p1'},
        ],
      });
      expect(commit.subject, 'feat: 第一行');
      expect(commit.authorName, '张三');
      expect(commit.authorLogin, 'zhangsan');
      expect(commit.parentShas, <String>['p1']);
      expect(commit.date, isNotNull);
    });

    test('主站判定只认 用户名.github.io', () {
      final main = GhRepo.fromJson(<String, dynamic>{
        'full_name': 'alice/alice.github.io',
        'name': 'alice.github.io',
        'owner': <String, dynamic>{'login': 'alice'},
      });
      final normal = GhRepo.fromJson(<String, dynamic>{
        'full_name': 'alice/blog',
        'name': 'blog',
        'owner': <String, dynamic>{'login': 'alice'},
      });
      expect(main.canBeMainSite, isTrue);
      expect(normal.canBeMainSite, isFalse);
    });
  });

  group('分页（Link 头）', () {
    test('解析 next / last / prev', () {
      const header = '<https://api.github.com/r?page=2>; rel="next", '
          '<https://api.github.com/r?page=5>; rel="last", '
          '<https://api.github.com/r?page=1>; rel="first"';
      final page = GhPage.parse(header);
      expect(page.hasNext, isTrue);
      expect(GhPage.pageOf(page.next), 2);
      expect(GhPage.pageOf(page.last), 5);
      expect(GhPage.pageOf(page.first), 1);
      expect(page.prev, isNull);
    });

    test('只有 next 时也能解析', () {
      final page = GhPage.parse(
        '<https://api.github.com/r?page=3>; rel="next"',
      );
      expect(GhPage.pageOf(page.next), 3);
      expect(page.last, isNull);
    });

    test('空 / 畸形头返回空分页而不抛', () {
      expect(GhPage.parse(null).hasNext, isFalse);
      expect(GhPage.parse('').hasNext, isFalse);
      expect(GhPage.parse('garbage').hasNext, isFalse);
      expect(GhPage.parse('<no-closing-bracket; rel="next"').hasNext, isFalse);
    });

    test('带 rel 引号与空格的变体也能解析', () {
      final page = GhPage.parse(
        '<https://api.github.com/r?page=9>;  rel = "next" ',
      );
      expect(page.hasNext, isTrue);
    });
  });

  group('认证：令牌安全', () {
    test('toString 只暴露脱敏形态', () {
      const token = GhToken('ghp_abcdefghijklmnop');
      expect(token.toString(), 'GhToken(ghp_****mnop)');
      expect(token.toString().contains('abcdefghij'), isFalse);
      expect(token.masked, 'ghp_****mnop');
    });

    test('短令牌全部打码', () {
      expect(const GhToken('abc').masked, '****');
    });

    test('令牌形态校验', () {
      expect(const GhToken('ghp_x').looksValid, isTrue);
      expect(const GhToken('github_pat_x').looksValid, isTrue);
      expect(const GhToken('随便写的').looksValid, isFalse);
    });

    test('账号序列化不含任何令牌痕迹', () {
      const account =
          GhAccount(id: '1', login: 'alice', scopes: <String>['repo']);
      final json = jsonEncode(account.toJson());
      expect(json.contains('token'), isFalse);
      expect(account.canWrite, isTrue);
      expect(
          const GhAccount(id: '2', login: 'b', scopes: <String>['public_repo'])
              .canWrite,
          isFalse);
    });
  });

  group('认证：存取与顺序', () {
    late InMemoryVault vault;
    late InMemoryKv store;
    late KernelDiagnostics diagnostics;
    late GhAuthService auth;

    setUp(() {
      vault = InMemoryVault();
      store = InMemoryKv();
      diagnostics = KernelDiagnostics();
      auth =
          GhAuthService(vault: vault, store: store, diagnostics: diagnostics);
    });

    test('保存后令牌进保险库、元数据进 KV（互不混杂）', () async {
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'alice'),
        const GhToken('ghp_secret_value_1234'),
      );

      expect(vault.snapshot.containsKey('gh.token.1'), isTrue);
      expect(store.snapshot['ogl.gh.account.1'], isNotNull);
      expect(
        store.snapshot['ogl.gh.account.1']!.contains('secret'),
        isFalse,
        reason: '明文令牌绝不能落普通 KV',
      );
      expect(diagnostics.logTail.any((e) => e.code == 'OGL-AUTH-001'), isTrue);
      expect(
        diagnostics.logTail.any((e) => '${e.data}'.contains('secret_value')),
        isFalse,
        reason: '审计日志也不能出现明文令牌',
      );
    });

    test('切换账号前必须已存在令牌', () async {
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'alice'),
        const GhToken('ghp_a'),
      );
      expect(await auth.switchTo('1'), isTrue);
      expect(await auth.activeAccountId(), '1');

      // 只写元数据、不写令牌 → 切换必须被拒绝。
      await store.write(
        'ogl.gh.account.2',
        jsonEncode(const GhAccount(id: '2', login: 'bob').toJson()),
      );
      expect(await auth.switchTo('2'), isFalse);
      expect(await auth.activeAccountId(), '1', reason: '拒绝后不应改变当前账号');
      expect(
        diagnostics.logTail.any((e) => e.code == 'OGL-AUTH-102'),
        isTrue,
      );
    });

    test('删除账号：令牌与元数据一起消失，当前账号被清空', () async {
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'alice'),
        const GhToken('ghp_a'),
      );
      await auth.switchTo('1');
      await auth.removeAccount('1');

      expect(await auth.hasToken('1'), isFalse);
      expect(vault.snapshot.containsKey('gh.token.1'), isFalse);
      expect(await auth.activeAccountId(), isNull);
      expect(await auth.accounts(), isEmpty);
    });

    test('removeAll 清空全部账号', () async {
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'a'),
        const GhToken('ghp_a'),
      );
      await auth.saveAccount(
        const GhAccount(id: '2', login: 'b'),
        const GhToken('ghp_b'),
      );
      expect(await auth.removeAll(), 2);
      expect(await auth.accounts(), isEmpty);
      expect(vault.snapshot, isEmpty);
    });

    test('令牌读取失败（保险库为空）返回 null 而不是抛', () async {
      expect(await auth.tokenFor('missing'), isNull);
      expect(await auth.activeToken(), isNull);
    });

    test('损坏的账号元数据被清理，不拖垮列表', () async {
      await store.write('ogl.gh.account.bad', '{{{ 不是 JSON');
      await auth.saveAccount(
        const GhAccount(id: '1', login: 'good'),
        const GhToken('ghp_a'),
      );
      final list = await auth.accounts();
      expect(list.length, 1);
      expect(list.first.login, 'good');
      expect(store.snapshot.containsKey('ogl.gh.account.bad'), isFalse);
    });

    test('账号按添加时间排序', () async {
      await auth.saveAccount(
        GhAccount(
          id: '2',
          login: 'second',
          addedAt: DateTime.parse('2026-10-02T00:00:00Z'),
        ),
        const GhToken('ghp_b'),
      );
      await auth.saveAccount(
        GhAccount(
          id: '1',
          login: 'first',
          addedAt: DateTime.parse('2026-10-01T00:00:00Z'),
        ),
        const GhToken('ghp_a'),
      );
      final list = await auth.accounts();
      expect(list.map((GhAccount a) => a.login), <String>['first', 'second']);
    });
  });
}
