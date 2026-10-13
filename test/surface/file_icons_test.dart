/// 展示层 · 文件类型视觉纯函数检查。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/util/file_icons.dart';

void main() {
  group('ogLExtension / ogLBaseName', () {
    test('取 basename 与扩展名（点开头不算扩展名）', () {
      expect(ogLBaseName('lib/main.dart'), 'main.dart');
      expect(ogLExtension('lib/main.dart'), 'dart');
      expect(ogLExtension('.gitignore'), '');
      expect(ogLExtension('README'), '');
      expect(ogLExtension('a/b/c.PNG'), 'png');
    });
  });

  group('ogLFileVisualFor', () {
    test('目录使用文件夹视觉', () {
      expect(
        ogLFileVisualFor('src', isDirectory: true).icon,
        Icons.folder,
      );
    });

    test('不同语言使用不同图标', () {
      final IconData dart = ogLFileVisualFor('lib/main.dart').icon;
      final IconData python = ogLFileVisualFor('a.py').icon;
      final IconData md = ogLFileVisualFor('README.md').icon;
      expect(dart, isNot(equals(python)));
      expect(python, isNot(equals(md)));
    });

    test('未知扩展名回落通用图标', () {
      expect(
        ogLFileVisualFor('weird.qqq').icon,
        kOgLGenericFileVisual.icon,
      );
    });

    test('无扩展名特殊文件名可识别（Dockerfile）', () {
      expect(
        ogLFileVisualFor('Dockerfile').icon,
        Icons.terminal,
      );
    });
  });
}
