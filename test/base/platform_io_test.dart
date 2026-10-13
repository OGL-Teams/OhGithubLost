/// L1 底座级 · 平台持久化测试（原子写 / 路径安全 / KV 健壮性）。
///
/// 说明：本文件**只测纯 `dart:io` 的部分**（[IoDiskFileStore] / [IoDiskKv]）。
/// [PlatformStorage.open] 与 [SecureDiskVault] 依赖插件通道
/// （`path_provider` / `flutter_secure_storage`），在 CI 上无法实例化，
/// 因此不在单测范围内——它们属于"真机验收"清单。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/platform_io.dart';

void main() {
  late Directory tempRoot;
  late String root;
  late IoDiskFileStore store;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('ogl_platform_io_');
    root = tempRoot.path.replaceAll(r'\', '/');
    store = IoDiskFileStore(root: root);
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  group('IoDiskFileStore · 基本读写', () {
    test('写入后可读，且不存在时返回 null', () async {
      await store.writeText('a/b.txt', 'hello');
      expect(await store.readText('a/b.txt'), 'hello');
      expect(await store.readText('a/missing.txt'), isNull);
      expect(await store.exists('a/b.txt'), isTrue);
      expect(await store.exists('a/nope.txt'), isFalse);
    });

    test('自动创建多级父目录', () async {
      await store.writeText('deep/er/still/file.md', 'x');
      expect(
        Directory('$root/deep/er/still').existsSync(),
        isTrue,
        reason: '父目录必须自动创建',
      );
    });

    test('覆盖写入替换内容', () async {
      await store.writeText('f.txt', 'v1');
      await store.writeText('f.txt', 'v2-longer');
      expect(await store.readText('f.txt'), 'v2-longer');
    });

    test('delete 幂等（不存在时不报错）', () async {
      await store.writeText('f.txt', 'v');
      await store.delete('f.txt');
      expect(await store.exists('f.txt'), isFalse);
      await store.delete('f.txt'); // 第二次不应抛
    });

    test('list 只列一级条目并排序，目录不参与', () async {
      await store.writeText('dir/b.txt', '1');
      await store.writeText('dir/a.txt', '2');
      await store.writeText('dir/sub/deep.txt', '3');
      expect(await store.list('dir'), <String>['a.txt', 'b.txt']);
      expect(await store.list('nope'), isEmpty);
    });
  });

  group('IoDiskFileStore · 原子写', () {
    test('写完不留临时文件', () async {
      await store.writeText('x/y.txt', 'content');
      final leftovers = Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty, reason: '临时文件必须被 rename 消费掉');
    });

    test('list 忽略 .tmp 残骸', () async {
      await store.writeText('real.txt', 'ok');
      // 手工制造一份"上次中断的残骸"。
      await File('$root/half.txt.tmp').writeAsString('partial');
      expect(await store.list(''), <String>['real.txt']);
    });

    test('sweepTemp 清掉残骸且不碰正常文件', () async {
      await store.writeText('keep.txt', 'keep');
      await File('$root/a.tmp').writeAsString('x');
      await File('$root/sub/b.tmp').create(recursive: true);
      await File('$root/sub/b.tmp').writeAsString('y');

      final result = await store.sweepTemp();

      expect(result.removed, 2);
      expect(result.failed, isEmpty);
      expect(File('$root/a.tmp').existsSync(), isFalse);
      expect(File('$root/sub/b.tmp').existsSync(), isFalse);
      expect(await store.readText('keep.txt'), 'keep');
    });

    test('sweepTemp 在根目录不存在时安全返回', () async {
      final missing = IoDiskFileStore(root: '$root/not-created');
      final result = await missing.sweepTemp();
      expect(result.removed, 0);
      expect(result.failed, isEmpty);
    });
  });

  group('IoDiskFileStore · 路径安全边界', () {
    test('拒绝目录穿越', () {
      expect(() => store.abs('../escape.txt'), throwsArgumentError);
      expect(() => store.abs('a/../../escape.txt'), throwsArgumentError);
    });

    test('拒绝空文件路径（读写删）', () async {
      expect(store.abs(''), root, reason: '空路径仅表示根目录');
      expect(() => store.writeText('', 'x'), throwsArgumentError);
      expect(() => store.readText(''), throwsArgumentError);
    });

    test('绝对路径被归一化为根内相对路径（不会逃逸）', () async {
      // normalize 会剥掉前导 '/'，因此 '/etc/passwd' 会落到 root 内的 etc/passwd。
      await store.writeText('/etc/passwd', 'not-really');
      expect(await store.readText('etc/passwd'), 'not-really');
      expect(File('$root/etc/passwd').existsSync(), isTrue);
    });
  });

  group('IoDiskKv · 基本语义', () {
    late IoDiskKv kv;

    setUp(() {
      kv = IoDiskKv(root: root);
    });

    test('写 / 读 / 存在 / 删除', () async {
      await kv.write('k1', 'v1');
      expect(await kv.read('k1'), 'v1');
      expect(await kv.has('k1'), isTrue);
      await kv.remove('k1');
      expect(await kv.read('k1'), isNull);
      expect(await kv.has('k1'), isFalse);
    });

    test('keys 能还原原始键（含斜杠 / 竖线 / 深层路径 / 中文）', () async {
      final keys = <String>[
        'ogl.cache.meta.1|acct|owner/repo|main|src/main.dart.txt',
        'ogl.journal.1699999999999-0',
        'a|b|c',
        '深层/路径/文件.md',
      ];
      for (final key in keys) {
        await kv.write(key, 'v:$key');
      }
      expect(await kv.keys(), equals(keys.toList()..sort()));
      for (final key in keys) {
        expect(await kv.read(key), 'v:$key');
      }
    });

    test('超长键不会撑爆文件名限制', () async {
      final longKey = 'ogl.test.${'x' * 4000}';
      await kv.write(longKey, 'ok');
      expect(await kv.read(longKey), 'ok');
      expect(await kv.keys(), contains(longKey));
    });

    test('文件名是摘要，不含原始键', () async {
      await kv.write('secret/path', 'v');
      final names = await kv.store.list('');
      expect(names.length, 1);
      expect(names.first, contains('.json'));
      expect(names.first.contains('secret'), isFalse);
      expect(
        names.first,
        '${sha256.convert(utf8.encode('secret/path'))}.json',
      );
    });
  });

  group('IoDiskKv · 健壮性（坏数据不得污染）', () {
    test('结构损坏 → 读取返回 null 并自清', () async {
      final kv = IoDiskKv(root: root);
      await kv.write('k', 'v');
      final name = (await kv.store.list('')).first;
      await kv.store.writeText(name, '{{{ 这不是 JSON');

      expect(await kv.read('k'), isNull);
      expect(await kv.store.exists(name), isFalse, reason: '坏文件应被清理');
      expect(await kv.keys(), isEmpty);
    });

    test('文件内存的键与请求键不一致 → 不返回别人的值', () async {
      final kv = IoDiskKv(root: root);
      await kv.write('k', 'v');
      final name = (await kv.store.list('')).first;
      await kv.store.writeText(
        name,
        jsonEncode(<String, Object?>{'k': 'another-key', 'v': '别人的数据'}),
      );

      expect(await kv.read('k'), isNull, reason: '宁可当作不存在，也不能串数据');
      expect(await kv.keys(), <String>['another-key']);
    });

    test('keys 跳过坏文件而不抛异常', () async {
      final kv = IoDiskKv(root: root);
      await kv.write('good', 'v');
      await kv.store.writeText('broken.json', 'not json');

      expect(await kv.keys(), <String>['good']);
    });
  });
}
