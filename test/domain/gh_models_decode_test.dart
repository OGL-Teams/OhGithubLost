/// L2 中枢级 · 内容解码测试：UTF-8（中文 / emoji）必须无损。
///
/// 历史缺陷：`decodeContent` 曾用 `String.fromCharCodes` 处理 UTF-8 字节，
/// 多字节字符全部拆成乱码（"解码错误"）。本测试锁死解码正确性。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';

void main() {
  group('GhContent.decodeContent', () {
    test('中文内容无损解码（历史缺陷回归）', () {
      const text = '# 你好，世界\n这是中文内容，含标点与 `code`。';
      final decoded =
          GhContent.decodeContent(base64Encode(utf8.encode(text)), 'base64');
      expect(decoded, text);
    });

    test('emoji 与混合文本无损解码', () {
      const text = 'OGL 🚀 发布 v0.1.0 ✅';
      final decoded =
          GhContent.decodeContent(base64Encode(utf8.encode(text)), 'base64');
      expect(decoded, text);
    });

    test('base64 含换行（GitHub 风格）也可解码', () {
      const text = 'line break test';
      final encoded = base64Encode(utf8.encode(text));
      final withBreaks =
          '${encoded.substring(0, 8)}\r\n${encoded.substring(8)}\n';
      expect(GhContent.decodeContent(withBreaks, 'base64'), text);
    });

    test('encoding 非 base64 时返回 null（不猜测内容）', () {
      expect(GhContent.decodeContent('aGVsbG8=', 'utf-8'), isNull);
    });

    test('非法 base64 返回 null 而不是抛异常', () {
      expect(GhContent.decodeContent('!!!not-base64!!!', 'base64'), isNull);
    });

    test('空内容返回 null', () {
      expect(GhContent.decodeContent('', 'base64'), isNull);
    });
  });
}
