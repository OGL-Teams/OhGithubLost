/// L3 展示级 · 文件预览类型判定测试。
///
/// 判定的意义在于**点击文件的默认行为**：位图与音频当文本看是乱码，必须直接
/// 进预览；SVG / XML 的源码本身有意义，保持进查看器，渲染由「打开方式」提供。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/util/file_preview.dart';

void main() {
  group('扩展名提取', () {
    test('取小写末段扩展名', () {
      expect(ogLExtensionOf('a/b/README.md'), 'md');
      expect(ogLExtensionOf('IMAGE.PNG'), 'png');
      expect(ogLExtensionOf('a/b/.gitignore'), '');
      expect(ogLExtensionOf('noext'), '');
      expect(ogLExtensionOf('trailing.'), '');
      expect(ogLExtensionOf(''), '');
      expect(ogLExtensionOf('dir.with.dots/file'), '');
    });
  });

  group('预览类型判定', () {
    test('位图', () {
      for (final String p in <String>[
        'a.png',
        'a.JPG',
        'a.jpeg',
        'a.gif',
        'a.webp',
        'a.bmp',
        'a.ico',
        'a.avif',
      ]) {
        expect(ogLPreviewKindOf(p), OgLPreviewKind.image, reason: p);
      }
    });

    test('音频', () {
      for (final String p in <String>[
        'a.mp3',
        'a.m4a',
        'a.wav',
        'a.ogg',
        'a.flac'
      ]) {
        expect(ogLPreviewKindOf(p), OgLPreviewKind.audio, reason: p);
      }
    });

    test('SVG 单列（可渲染也可看源码）', () {
      expect(ogLPreviewKindOf('assets/icon.svg'), OgLPreviewKind.svg);
    });

    test('XML 家族', () {
      for (final String p in <String>[
        'a.xml',
        'a.xsd',
        'a.xsl',
        'a.plist',
        'a.csproj',
        'a.vcxproj',
        'a.xaml',
      ]) {
        expect(ogLPreviewKindOf(p), OgLPreviewKind.xml, reason: p);
      }
    });

    test('未知类型不提供预览', () {
      for (final String p in <String>[
        'a.dart',
        'a.md',
        'a.json',
        'noext',
        ''
      ]) {
        expect(ogLPreviewKindOf(p), OgLPreviewKind.unknown, reason: p);
      }
    });
  });

  group('默认行为与可渲染性', () {
    test('位图与音频直接进预览', () {
      expect(ogLPreviewFirst(OgLPreviewKind.image), isTrue);
      expect(ogLPreviewFirst(OgLPreviewKind.audio), isTrue);
    });

    test('SVG / XML / 未知保持既有流程（不抢占）', () {
      expect(ogLPreviewFirst(OgLPreviewKind.svg), isFalse);
      expect(ogLPreviewFirst(OgLPreviewKind.xml), isFalse);
      expect(ogLPreviewFirst(OgLPreviewKind.unknown), isFalse);
    });

    test('位图与 SVG 可内置渲染；音频与 XML 不可', () {
      expect(ogLCanRenderInline(OgLPreviewKind.image), isTrue);
      // SVG 由 flutter_svg 渲染（纯 Dart，无原生依赖）。
      expect(ogLCanRenderInline(OgLPreviewKind.svg), isTrue);
      // 音频受接口限制无法内置播放；XML 走文本查看器而非「渲染」。
      expect(ogLCanRenderInline(OgLPreviewKind.audio), isFalse);
      expect(ogLCanRenderInline(OgLPreviewKind.xml), isFalse);
    });

    test('每种类型都有对应的 i18n 键（不留空白项）', () {
      for (final OgLPreviewKind kind in OgLPreviewKind.values) {
        expect(ogLPreviewKindKey(kind), isNotEmpty, reason: '$kind');
      }
    });
  });
}
