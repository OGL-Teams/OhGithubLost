/// 展示层 · i18n 语言包一致性检查。
///
/// 这些断言直接读**磁盘上的 JSON 分片**（测试工作目录即仓库根），
/// 因此能真正防住"漏了一个分片 / 少了一个键 / 中文把 Issue 翻译掉了"。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';

const String kI18nRoot = 'assets/i18n';

Map<String, Map<String, String>> _loadLocale(String code) {
  final Map<String, Map<String, String>> pages =
      <String, Map<String, String>>{};
  for (final String page in OgLI18n.pages) {
    final File file = File('$kI18nRoot/$code/$page.json');
    expect(file.existsSync(), isTrue, reason: '缺少分片：$code/$page.json');
    final Object? decoded = jsonDecode(file.readAsStringSync());
    pages[page] = <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (decoded as Map<Object?, Object?>).entries)
        '${e.key}': '${e.value}',
    };
  }
  return pages;
}

void main() {
  group('语言包完整性', () {
    test('2 种语言 × 全部页面分片全部存在且可解析', () {
      expect(OgLI18n.locales.length, 2);
      for (final OgLLocale locale in OgLI18n.locales) {
        _loadLocale(locale.code);
      }
    });

    test('每种语言的键集合与英文基线一致（无漏翻导致的缺键）', () {
      final Map<String, Map<String, String>> en = _loadLocale('en');
      for (final OgLLocale locale in OgLI18n.locales) {
        final Map<String, Map<String, String>> data = _loadLocale(locale.code);
        for (final String page in OgLI18n.pages) {
          expect(
            data[page]!.keys.toSet(),
            en[page]!.keys.toSet(),
            reason: '${locale.code}/$page.json 的键与 en/$page.json 不一致',
          );
        }
      }
    });

    test('中文语境保留 GitHub 术语英文（issue / release / action / pr）', () {
      final Map<String, Map<String, String>> zh = _loadLocale('zh');
      // repo 分片：Issues / Releases / Actions 必须保持英文。
      expect(zh['repo']!['issues'], 'Issues');
      expect(zh['repo']!['releases'], 'Releases');
      expect(zh['repo']!['actions'], 'Actions');
      expect(zh['repo']!['pulls'], 'Pull requests');
      // 其它词该翻还是要翻。
      expect(zh['repo']!['branches'], '分支');
      expect(zh['shell']!['settings'], '设置');
    });
  });

  group('OgLI18n 兜底', () {
    test('缺失键回落英文基线，再回落键名（绝不返回空串）', () {
      final OgLI18n i18n = OgLI18n.instance;
      i18n.debugInject('zh', <String, Map<String, String>>{
        'shell': <String, String>{},
      });
      i18n.debugInject('en', <String, Map<String, String>>{
        'shell': <String, String>{'home': 'Home'},
      });
      expect(i18n.t('shell', 'home'), 'Home');
      // 两边都没有 → 返回键名。
      expect(i18n.t('shell', 'missing'), 'missing');
    });
  });
}
