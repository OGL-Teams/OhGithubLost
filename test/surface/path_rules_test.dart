/// L3 展示级测试 · 仓库路径规则 / 加速通道规则。
///
/// 覆盖用户明确要求的行为：
/// 1. 新建文件的路径**禁止中文与特殊字符**；
/// 2. **禁止空文件**（`.gitkeep` 目录占位例外）；
/// 3. 目录用 `.gitkeep` 占位；
/// 4. 加速通道地址必须是 `https://`（明文 http 会被 Android 9+ 拦截）；
/// 5. 加速地址拼接是纯函数、不会二次加前缀。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';
import 'package:ohgithublost/surface/util/accel.dart';
import 'package:ohgithublost/surface/util/download_proxy.dart';
import 'package:ohgithublost/surface/util/path_rules.dart';

/// 把 zh 分片注入 i18n 内核（测试环境读不到 assets）。
void _loadZh() {
  final Map<String, Map<String, String>> pages =
      <String, Map<String, String>>{};
  for (final String page in <String>['common']) {
    final Object? decoded =
        jsonDecode(File('assets/i18n/zh/$page.json').readAsStringSync());
    pages[page] = <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (decoded as Map<Object?, Object?>).entries)
        '${e.key}': '${e.value}',
    };
  }
  OgLI18n.instance.debugInject('zh', pages);
}

void main() {
  setUpAll(_loadZh);
  group('仓库路径规则', () {
    test('合法路径通过', () {
      expect(
          ogLValidateRepoEntryPath('src/main.dart', directory: false), isNull);
      expect(ogLValidateRepoEntryPath('docs/api/', directory: true), isNull);
      expect(ogLValidateRepoEntryPath('.gitignore', directory: false), isNull);
      expect(
          ogLValidateRepoEntryPath('a/b/c_d-e.txt', directory: false), isNull);
    });

    test('禁止中文 / 全角', () {
      expect(
        ogLValidateRepoEntryPath('文档/说明.md', directory: false),
        isNotNull,
      );
      expect(
        ogLValidateRepoEntryPath('src/你好.txt', directory: false),
        isNotNull,
      );
      expect(
        ogLValidateRepoEntryPath('docs（v2）/x.md', directory: false),
        isNotNull,
      );
    });

    test('禁止特殊字符与空格', () {
      for (final String bad in <String>[
        'a b/c.txt',
        'a#b.txt',
        r'a\b.txt',
        'a:b.txt',
        'a*b.txt',
        'a?b.txt',
        'a|b.txt',
        'a<b>.txt',
      ]) {
        expect(
          ogLValidateRepoEntryPath(bad, directory: false),
          isNotNull,
          reason: bad,
        );
      }
    });

    test('结构性错误', () {
      expect(ogLValidateRepoEntryPath('', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('a//b.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('/a.txt', directory: false), isNotNull);
      expect(
          ogLValidateRepoEntryPath('a/../b.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('a /b.txt', directory: false), isNotNull);
      expect(ogLValidateRepoEntryPath('CON', directory: false), isNotNull);
      // 目录必须以 / 结尾；文件不能以 / 结尾。
      expect(ogLValidateRepoEntryPath('docs', directory: true), isNotNull);
      expect(ogLValidateRepoEntryPath('a.txt/', directory: false), isNotNull);
    });

    test('目录占位路径与识别', () {
      expect(ogLGitKeepPathFor('docs/'), 'docs/.gitkeep');
      expect(ogLGitKeepPathFor('docs'), 'docs/.gitkeep');
      expect(ogLGitKeepPathFor(''), '.gitkeep');
      expect(ogLIsGitKeep('docs/.gitkeep'), isTrue);
      expect(ogLIsGitKeep('docs/readme.md'), isFalse);
    });

    test('禁止空文件（.gitkeep 例外）', () {
      expect(ogLValidateFileContent('a.txt', 'hello'), isNull);
      expect(ogLValidateFileContent('a.txt', '   \n  '), isNotNull);
      expect(ogLValidateFileContent('a.txt', ''), isNotNull);
      expect(ogLValidateFileContent('docs/.gitkeep', ''), isNull);
    });
  });

  group('加速通道规则（v6.4.3：无内置通道、无降级兜底）', () {
    test('只接受 https（http 明文会被拦截）', () {
      expect(ogLValidateAccelBaseUrl('http://a.com/'), isNotNull);
      expect(ogLValidateAccelBaseUrl('https://a.com/'), isNull);
      // 只有前缀不算数：`https://` 没有主机名，会被当成"空加速前缀"
      //（`https://` + 原地址 = 原地址），把静默直连伪装成"加速已开"。
      expect(ogLValidateAccelBaseUrl('https://'), isNotNull);
      expect(ogLValidateAccelBaseUrl('https:///'), isNotNull);
    });

    test('地址归一化补 /', () {
      expect(ogLNormalizeAccelBase('https://a.com'), 'https://a.com/');
      expect(ogLNormalizeAccelBase('https://a.com/'), 'https://a.com/');
    });

    test('协议文本非空（只有一种：外来服务自负责任）', () {
      _loadZh();
      expect(ogLAccelAgreement(), isNotEmpty);
    });

    test('自定义通道前缀：单个，没有"链"', () {
      const OgLAccelChannel channel =
          OgLAccelChannel(id: 'c1', name: '我的', baseUrl: 'https://a.com/');
      expect(ogLAccelPrefixesFor(channel), <String>['https://a.com/']);
      expect(ogLAccelPrefixesFor(channel).length, 1);
    });

    test('适用范围清单与枚举一致（防漂移）', () {
      // kOgLAccelAllScopeIds 是**落盘默认值**，写成显式列表；
      // 新增枚举值却忘了加进清单，会让新范围默认关闭 —— 这条断言拦住它。
      expect(kOgLAccelAllScopeIds.toSet(),
          OgLAccelScope.values.map((OgLAccelScope s) => s.id).toSet());
      expect(kOgLAccelAllScopeIds.length, OgLAccelScope.values.length);
      // id 解析往返。
      for (final OgLAccelScope s in OgLAccelScope.values) {
        expect(OgLAccelScope.fromId(s.id), s);
        expect(s.labelKey, startsWith('accelScope'));
      }
      expect(OgLAccelScope.fromId('nope'), isNull);
      expect(OgLAccelScope.fromId(null), isNull);
    });

    test('候选地址：未启用加速 → 直连', () {
      const String target = 'https://github.com/o/r/releases/download/v1/a.zip';
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>[],
          family: OgLAccelFamily.signed,
          bytes: 900 * 1024,
        ),
        <String>[target],
      );
    });

    test('候选地址：加速时**只有一项**（不再垫直连兜底）', () {
      const String target =
          'https://release-assets.githubusercontent.com/x?sig=ab';
      final List<String> out = ogLAccelCandidates(
        url: target,
        prefixes: const <String>['https://proxy.example/'],
        family: OgLAccelFamily.signed,
        bytes: 9 * 1024 * 1024,
      );
      expect(out, <String>['https://proxy.example/$target']);
      // 关键：结果里**不含**原始地址 —— 静默回落直连已按要求移除。
      expect(out.contains(target), isFalse);
    });

    test('候选地址：raw 族（公开仓库）走自定义通道', () {
      const String target = 'https://raw.githubusercontent.com/o/r/main/a.png';
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://proxy.example/'],
          family: OgLAccelFamily.raw,
          bytes: 9 * 1024 * 1024,
          repoPrivate: false,
        ),
        <String>['https://proxy.example/$target'],
      );
    });

    test('私有 + raw：未知情接受时直连；接受后加速', () {
      const String target = 'https://raw.githubusercontent.com/o/r/main/a.png';
      const List<String> prefixes = <String>['https://proxy.example/'];
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: prefixes,
          family: OgLAccelFamily.raw,
          bytes: 9 * 1024 * 1024,
          repoPrivate: true,
          privateAccelAccepted: false,
        ),
        <String>[target],
      );
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: prefixes,
          family: OgLAccelFamily.raw,
          bytes: 9 * 1024 * 1024,
          repoPrivate: true,
          privateAccelAccepted: true,
        ),
        <String>['https://proxy.example/$target'],
      );
    });

    test('候选地址：签名族与仓库公私无关（私有也能加速）', () {
      const String target =
          'https://release-assets.githubusercontent.com/x?sig=ab';
      const List<String> prefixes = <String>['https://proxy.example/'];
      for (final bool priv in <bool>[false, true]) {
        expect(
          ogLAccelCandidates(
            url: target,
            prefixes: prefixes,
            family: OgLAccelFamily.signed,
            bytes: 9 * 1024 * 1024,
            repoPrivate: priv,
          ),
          <String>['https://proxy.example/$target'],
          reason: 'repoPrivate=$priv',
        );
      }
    });

    test('候选地址：≤ 阈值不加速（小文件加速没收益）', () {
      const String target = 'https://release-assets.githubusercontent.com/x';
      expect(kOgLAccelMinBytes, 500 * 1024);
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://a/'],
          family: OgLAccelFamily.signed,
          bytes: kOgLAccelMinBytes,
        ),
        <String>[target],
      );
    });

    test('候选地址：大小未知（Action 日志/产物）按加速处理', () {
      const String target =
          'https://results-receiver.actions.githubusercontent.com/x';
      expect(
        ogLAccelCandidates(
          url: target,
          prefixes: const <String>['https://a/'],
          family: OgLAccelFamily.signed,
        ),
        <String>['https://a/$target'],
      );
    });

    test('候选地址：已是加速地址则不二次加前缀', () {
      const String target = 'https://release-assets.githubusercontent.com/x';
      const String base = 'https://a/';
      expect(
        ogLAccelCandidates(
          url: '$base$target',
          prefixes: const <String>[base],
          family: OgLAccelFamily.signed,
          bytes: 9 * 1024 * 1024,
        ),
        <String>['$base$target'],
      );
    });

    test('候选地址：非 http(s) 原样返回（入队口会拒绝）', () {
      expect(
        ogLAccelCandidates(
          url: 'file:///tmp/a.zip',
          prefixes: const <String>['https://a/'],
          family: OgLAccelFamily.signed,
          bytes: 9 * 1024 * 1024,
        ),
        <String>['file:///tmp/a.zip'],
      );
    });
  });
}
