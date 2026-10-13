/// 展示层格式化纯函数的检查（GitHub 字段 → 人话）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';
import 'package:ohgithublost/surface/util/gh_format.dart';
import 'package:ohgithublost/surface/widgets/readme_view.dart';

void main() {
  // 这些纯函数的中文来自 `common` 分片，测试里把 zh 分片注入内核。
  setUpAll(() {
    final Map<String, String> common = <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (jsonDecode(File('assets/i18n/zh/common.json').readAsStringSync())
                  as Map<Object?, Object?>)
              .entries)
        '${e.key}': '${e.value}',
    };
    OgLI18n.instance.debugInject('zh', <String, Map<String, String>>{
      'common': common,
    });
  });

  group('gh_format', () {
    test('字符串 / 整数容错', () {
      final Map<String, dynamic> node = <String, dynamic>{
        's': 'ok',
        'n': 3,
        'n2': '4',
        'bad': <int>[1],
      };
      expect(ghStr(node, 's'), 'ok');
      expect(ghStr(node, 'n'), '');
      expect(ghStrOrNull(node, 'bad'), isNull);
      expect(ghInt(node, 'n'), 3);
      expect(ghInt(node, 'n2'), 4);
      expect(ghInt(node, 'bad'), 0);
    });

    test('user.login 与日期', () {
      final Map<String, dynamic> node = <String, dynamic>{
        'user': <String, dynamic>{'login': 'octocat'},
        'created_at': '2026-01-02T03:04:05Z',
      };
      expect(ghLogin(node), 'octocat');
      expect(ghDate(node, 'created_at'), '2026-01-02');
      expect(ghDate(node, 'missing'), '');
    });

    test('状态 / 短 sha / 路径名 / 大小', () {
      expect(ghFileStatusText('added'), '新增');
      expect(ghFileStatusText('removed'), '删除');
      expect(ghFileStatusText('whatever'), 'whatever');
      expect(ghFileStatusText(''), '变更');
      expect(ghShortSha('0123456789abcdef'), '0123456');
      expect(ghShortSha('abc'), 'abc');
      expect(ghPathName('lib/main.dart'), 'main.dart');
      expect(ghSizeText(512), '512 B');
      expect(ghSizeText(2048), '2.0 KB');
    });
  });

  group('simplifyReadme', () {
    test('徽章行整行删除；默认保留图片语法供渲染层加载', () {
      const String src = '# 标题\n'
          '[![badge](https://img.shields.io/x.svg)](https://x)\n'
          '正文 ![logo](logo.png) 结束';
      final String md = simplifyReadme(src);
      expect(md.contains('badge'), isFalse, reason: '徽章行必须整行消失');
      expect(md.contains('![logo](logo.png)'), isTrue,
          reason: '图片语法默认保留，由渲染层真正加载');
      expect(md.contains('（图：logo）'), isFalse);
      expect(md.contains('正文'), isTrue);
    });

    test('keepImages: false 时图片退化为占位文本', () {
      const String src = '正文 ![logo](logo.png) 结束';
      final String md = simplifyReadme(src, keepImages: false);
      expect(md.contains('（图：logo）'), isTrue);
      expect(md.contains('![logo]'), isFalse);
    });

    test('HTML 注释与标签被清除，代码块内部原样保留', () {
      const String src = '<!-- 隐藏 -->\n<div align="center">标题</div>\n'
          '```\n<div>代码里的标签不动</div>\n```';
      final String md = simplifyReadme(src);
      expect(md.contains('隐藏'), isFalse);
      expect(md.contains('<div align="center">'), isFalse);
      expect(md.contains('<div>代码里的标签不动</div>'), isTrue);
    });

    test('超长按行截断并给出说明', () {
      final String line = 'x' * 100;
      final String src = '$line\n$line';
      final String md = simplifyReadme(src, maxChars: 120);
      expect(md.length < 200, isTrue);
      expect(md.contains('已截断'), isTrue);
    });
  });
}
