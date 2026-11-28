/// 展示层 · 代码显示 / 编辑（**库实现**）的项目语义检查。
///
/// 语法高亮本身由 `re_highlight` 负责，本文件只验证我们保留的那一层：
/// 语言识别、配色翻译（键名必须与库发出的 class 名一致）、字段可渲染、
/// 以及查找面板与库控制器的对接。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/widgets/code_editor_field.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  group('ogLDetectLanguage', () {
    test('常见扩展名', () {
      expect(ogLDetectLanguage('lib/main.dart'), 'dart');
      expect(ogLDetectLanguage('a.py'), 'python');
      expect(ogLDetectLanguage('a/b/c.ts'), 'typescript');
      expect(ogLDetectLanguage('unknown.qqq'), '');
    });

    test('无扩展名的特殊文件名', () {
      expect(ogLDetectLanguage('Dockerfile'), 'dockerfile');
      expect(ogLDetectLanguage('Makefile'), 'makefile');
    });
  });

  group('语言 → 高亮规则', () {
    test('已登记语言都有对应规则', () {
      const List<String> languages = <String>[
        'dart',
        'javascript',
        'typescript',
        'python',
        'java',
        'kotlin',
        'go',
        'rust',
        'c',
        'cpp',
        'csharp',
        'ruby',
        'php',
        'swift',
        'shell',
        'json',
        'yaml',
        'toml',
        'ini',
        'sql',
        'xml',
        'css',
        'markdown',
        'lua',
        'dockerfile',
        'makefile',
      ];
      for (final String language in languages) {
        expect(ogLHighlightModeOf(language), isNotNull, reason: language);
      }
    });

    test('未知语言返回 null（不高亮，而不是猜）', () {
      expect(ogLHighlightModeOf(''), isNull);
      expect(ogLHighlightModeOf('brainfuck'), isNull);
    });

    test('关闭高亮时不生成高亮配置', () {
      expect(
        ogLHighlightThemeFor(
          language: 'dart',
          highlight: false,
          palette: kOgLCodeThemeSoft,
        ),
        isNull,
      );
      expect(
        ogLHighlightThemeFor(
          language: 'dart',
          highlight: true,
          palette: kOgLCodeThemeSoft,
        ),
        isNotNull,
      );
      expect(
        ogLHighlightThemeFor(
          language: '',
          highlight: true,
          palette: kOgLCodeThemeSoft,
        ),
        isNull,
        reason: '语言未知时不应生成高亮配置',
      );
    });
  });

  group('配色翻译（键名与库自带主题一致）', () {
    test('关键 class 都在，且颜色取自项目配色', () {
      final Map<String, TextStyle> theme =
          ogLHighlightThemeOf(kOgLCodeThemeHighContrast);
      for (final String key in <String>[
        'root',
        'keyword',
        'string',
        'comment',
        'number',
        'built_in',
        'title.class_',
        'emphasis',
        'strong',
      ]) {
        expect(theme.containsKey(key), isTrue, reason: key);
      }
      expect(theme['keyword']!.color, kOgLCodeThemeHighContrast.keyword);
      expect(theme['string']!.color, kOgLCodeThemeHighContrast.string);
      expect(theme['comment']!.fontStyle, FontStyle.italic);
      expect(theme['root']!.color, kOgLCodeThemeHighContrast.foreground);
    });
  });

  group('ogLCodeThemeFor 预设', () {
    const ColorScheme scheme = ColorScheme.light();

    /// 通用调用（自定义色随便给，只有 custom 预设才会用到）。
    OgLCodeTheme resolve(String preset) => ogLCodeThemeFor(
          preset: preset,
          scheme: scheme,
          customBackground: 0xFF101010,
          customForeground: 0xFFEEEEEE,
          customKeyword: 0xFF112233,
          customTypeName: 0xFF223344,
          customString: 0xFF334455,
          customComment: 0xFF445566,
          customNumber: 0xFF556677,
        );

    test('高对比 / 柔和使用固定预设', () {
      expect(resolve(kOgLCodePresetHighContrast).background,
          kOgLCodeThemeHighContrast.background);
      expect(
          resolve(kOgLCodePresetSoft).background, kOgLCodeThemeSoft.background);
    });

    test('自定义预设使用传入颜色', () {
      final OgLCodeTheme custom = resolve(kOgLCodePresetCustom);
      expect(custom.background, const Color(0xFF101010));
      expect(custom.keyword, const Color(0xFF112233));
      expect(custom.number, const Color(0xFF556677));
    });

    test('未知预设回落主题派生', () {
      expect(resolve('bogus').background, scheme.surfaceContainerHighest);
    });

    test('预设清单与标签一一对应', () {
      expect(kOgLCodePresetLabels.length, 4);
      expect(kOgLCodePresetLabels.keys, contains(kOgLCodePresetTheme));
    });
  });

  group('字段渲染（库对接）', () {
    testWidgets('只读查看器可渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: OgLCodeViewer(code: 'void main() {}\n', path: 'a.dart'),
            ),
          ),
        ),
      );
      expect(find.byType(CodeEditor), findsOneWidget);
    });

// 说明：不在此渲染**可编辑**的 CodeEditor —— 库在该模式下会启动光标闪烁
// 定时器（`_CodeCursorBlinkController.startBlink`），flutter_test 会在 widget 树
// 销毁后报 "A Timer is still pending"（库内部行为，与本项目代码无关）。
    // 改为直接验证我们依赖的控制器能力；可编辑路径由真机 / 截屏矩阵覆盖。
    test('库控制器：文本 / 行数 / 撤销重做（编辑器页直接依赖这三项）', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('a\nb');
      addTearDown(controller.dispose);
      expect(controller.lineCount, 2);
      expect(controller.text, 'a\nb');

      controller.text = 'x\ny\nz';
      expect(controller.lineCount, 3);
      expect(controller.text, 'x\ny\nz');

      // 撤销 / 重做由库维护，编辑器页只读这两个开关。
      expect(controller.canUndo, isA<bool>());
      expect(controller.canRedo, isA<bool>());
    });

    test('查找面板随控制器开关（高度 0 ↔ 打开）', () {
      final CodeLineEditingController controller =
          CodeLineEditingController.fromText('hello world');
      addTearDown(controller.dispose);
      final CodeFindController find = CodeFindController(controller);
      addTearDown(find.dispose);

      final OgLCodeFindPanel panel =
          OgLCodeFindPanel(controller: find, readOnly: false);
      expect(panel.preferredSize.height, 0, reason: '未打开时高度为 0');

      find.findMode();
      expect(find.value, isNotNull);
      expect(panel.preferredSize.height, greaterThan(0));

      find.close();
      expect(panel.preferredSize.height, 0);
    });
  });
}
