/// L3 展示级 · 代码显示与编辑（**统一库实现**：`re_editor` + `re_highlight`）。
///
/// ## 为什么换库
/// 此前是自研：`CodeView` 自带词法器 + "高亮图层 + 透明输入层"叠加的编辑区 +
/// 自研查找替换。问题很实在：词法规则与社区标准不一致、语言覆盖少；叠加层在
/// 自动换行 / 长行 / 滚动下会与输入层错位；查找替换、撤销重做、折叠、快捷键
/// 全部要自己维护。
///
/// 现在编辑与高亮都交给 [Re-Editor]（编辑器内核）与 [Re-Highlight]
/// （highlight.js 的 Dart 移植），本项目只保留"项目语义"这一薄层：
/// - **语言识别**：由文件路径推断语言 id（[ogLDetectLanguage]）；
/// - **配色**：把设置里的预设 / 自定义颜色翻译成 highlight.js 的主题表；
/// - **字段封装**：[OgLCodeField]（可编辑 / 只读）与 [OgLCodeViewer]（只读）。
///
/// ## 超大文本
/// 不再自研"字符数护栏"，改用库自带的限制（[CodeHighlightThemeMode.maxSize] /
/// [CodeHighlightThemeMode.maxLineLength]）：超过阈值自动跳过高亮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../i18n/og_l_i18n.dart';
import '../util/og_l_space.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'common', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 高亮语言注册的上限（超过即跳过高亮，避免超大文件拖垮渲染）。
const int kOgLHighlightMaxChars = 400 * 1024;

// ─────────────────────────────────────────────────────────────────────────────
// 配色（项目语义：设置页的预设与自定义颜色都在这里收口）
// ─────────────────────────────────────────────────────────────────────────────

/// 预设：跟随应用主题（默认）。
const String kOgLCodePresetTheme = 'theme';

/// 预设：高对比（深底亮字，色相分离明显）。
const String kOgLCodePresetHighContrast = 'high_contrast';

/// 预设：柔和（浅底低饱和）。
const String kOgLCodePresetSoft = 'soft';

/// 预设：自定义（用户自选每个 token 的颜色）。
const String kOgLCodePresetCustom = 'custom';

/// 全部预设（id → `common` 分片键）。
const Map<String, String> kOgLCodePresetLabels = <String, String>{
  kOgLCodePresetTheme: 'codePresetTheme',
  kOgLCodePresetHighContrast: 'codePresetHighContrast',
  kOgLCodePresetSoft: 'codePresetSoft',
  kOgLCodePresetCustom: 'codePresetCustom',
};

/// 预设展示名（`common` 分片）。
String ogLCodePresetLabel(String id) =>
    OgLI18n.instance.t('common', kOgLCodePresetLabels[id] ?? id);

/// 代码配色方案。
@immutable
class OgLCodeTheme {
  /// 创建配色。
  const OgLCodeTheme({
    required this.background,
    required this.foreground,
    required this.keyword,
    required this.typeName,
    required this.string,
    required this.comment,
    required this.number,
  });

  /// 从应用主题派生（默认预设）。
  factory OgLCodeTheme.fromScheme(ColorScheme scheme) => OgLCodeTheme(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurface,
        keyword: scheme.primary,
        typeName: scheme.tertiary,
        string: scheme.tertiary,
        comment: scheme.outline,
        number: scheme.secondary,
      );

  /// 背景。
  final Color background;

  /// 普通文本。
  final Color foreground;

  /// 关键词。
  final Color keyword;

  /// 类型 / 内置名。
  final Color typeName;

  /// 字符串。
  final Color string;

  /// 注释。
  final Color comment;

  /// 数字。
  final Color number;
}

/// 高对比预设。
const OgLCodeTheme kOgLCodeThemeHighContrast = OgLCodeTheme(
  background: Color(0xFF101418),
  foreground: Color(0xFFF0F6FC),
  keyword: Color(0xFFFF7B72),
  typeName: Color(0xFF79C0FF),
  string: Color(0xFFA5D6FF),
  comment: Color(0xFF9BA7B4),
  number: Color(0xFFFFA657),
);

/// 柔和预设。
const OgLCodeTheme kOgLCodeThemeSoft = OgLCodeTheme(
  background: Color(0xFFF6F8FA),
  foreground: Color(0xFF24292F),
  keyword: Color(0xFFCF222E),
  typeName: Color(0xFF0550AE),
  string: Color(0xFF0A3069),
  comment: Color(0xFF6E7781),
  number: Color(0xFF953800),
);

/// 根据设置解析配色（**唯一入口**，编辑器 / 查看器 / 设置页共用）。
OgLCodeTheme ogLCodeThemeFor({
  required String preset,
  required ColorScheme scheme,
  required int customBackground,
  required int customForeground,
  required int customKeyword,
  required int customTypeName,
  required int customString,
  required int customComment,
  required int customNumber,
}) {
  switch (preset) {
    case kOgLCodePresetHighContrast:
      return kOgLCodeThemeHighContrast;
    case kOgLCodePresetSoft:
      return kOgLCodeThemeSoft;
    case kOgLCodePresetCustom:
      return OgLCodeTheme(
        background: Color(customBackground),
        foreground: Color(customForeground),
        keyword: Color(customKeyword),
        typeName: Color(customTypeName),
        string: Color(customString),
        comment: Color(customComment),
        number: Color(customNumber),
      );
    default:
      return OgLCodeTheme.fromScheme(scheme);
  }
}

/// 把项目配色翻译成 highlight.js 的**主题表**。
///
/// 键名必须与库实际发出的 class 名一致（与 `re_highlight` 自带主题同一套键）。
Map<String, TextStyle> ogLHighlightThemeOf(OgLCodeTheme palette) {
  final TextStyle plain = TextStyle(color: palette.foreground);
  final TextStyle keyword =
      TextStyle(color: palette.keyword, fontWeight: FontWeight.w600);
  final TextStyle type = TextStyle(color: palette.typeName);
  final TextStyle str = TextStyle(color: palette.string);
  final TextStyle comment =
      TextStyle(color: palette.comment, fontStyle: FontStyle.italic);
  final TextStyle number = TextStyle(color: palette.number);
  return <String, TextStyle>{
    'root': plain,
    'comment': comment,
    'quote': comment,
    'doctag': comment,
    'keyword': keyword,
    'formula': keyword,
    'section': keyword,
    'name': keyword,
    'selector-tag': keyword,
    'deletion': keyword,
    'subst': keyword,
    'literal': keyword,
    'string': str,
    'regexp': str,
    'addition': str,
    'attribute': str,
    'meta-string': str,
    'variable': str,
    'template-variable': str,
    'attr': type,
    'type': type,
    'selector-class': type,
    'selector-attr': type,
    'selector-pseudo': type,
    'selector-id': type,
    'symbol': type,
    'bullet': type,
    'link': type,
    'meta': type,
    'title': type,
    'title.class_': type,
    'class-title': type,
    'built_in': type,
    'number': number,
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.w700),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 语言识别（项目语义）
// ─────────────────────────────────────────────────────────────────────────────

/// 由文件路径推断语言标识（小写；未知返回空串）。
String ogLDetectLanguage(String path) {
  final int slash = path.lastIndexOf('/');
  final String base =
      (slash >= 0 ? path.substring(slash + 1) : path).toLowerCase();
  final int dot = base.lastIndexOf('.');
  final String ext = dot <= 0 ? '' : base.substring(dot + 1);
  switch (ext) {
    case 'dart':
      return 'dart';
    case 'js':
    case 'mjs':
    case 'cjs':
      return 'javascript';
    case 'jsx':
      return 'jsx';
    case 'ts':
      return 'typescript';
    case 'tsx':
      return 'tsx';
    case 'py':
      return 'python';
    case 'java':
      return 'java';
    case 'kt':
    case 'kts':
      return 'kotlin';
    case 'go':
      return 'go';
    case 'rs':
      return 'rust';
    case 'c':
    case 'h':
      return 'c';
    case 'cpp':
    case 'cc':
    case 'cxx':
    case 'hpp':
    case 'hh':
      return 'cpp';
    case 'cs':
      return 'csharp';
    case 'rb':
      return 'ruby';
    case 'php':
      return 'php';
    case 'swift':
      return 'swift';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'shell';
    case 'json':
    case 'jsonc':
      return 'json';
    case 'yaml':
    case 'yml':
      return 'yaml';
    case 'toml':
      return 'toml';
    case 'ini':
    case 'cfg':
    case 'conf':
    case 'properties':
      return 'ini';
    case 'sql':
      return 'sql';
    case 'xml':
    case 'html':
    case 'htm':
    case 'svg':
      return 'xml';
    case 'css':
    case 'scss':
    case 'less':
      return 'css';
    case 'md':
    case 'markdown':
      return 'markdown';
    case 'lua':
      return 'lua';
    default:
      break;
  }
  switch (base) {
    case 'dockerfile':
    case 'containerfile':
      return 'dockerfile';
    case 'makefile':
    case 'gnumakefile':
      return 'makefile';
    default:
      return '';
  }
}

/// 语言标识 → `re_highlight` 的高亮规则；未知返回 `null`（不高亮）。
Mode? ogLHighlightModeOf(String language) {
  switch (language) {
    case 'dart':
      return langDart;
    case 'javascript':
    case 'jsx':
      return langJavascript;
    case 'typescript':
    case 'tsx':
      return langTypescript;
    case 'python':
      return langPython;
    case 'java':
      return langJava;
    case 'kotlin':
      return langKotlin;
    case 'go':
      return langGo;
    case 'rust':
      return langRust;
    case 'c':
      return langC;
    case 'cpp':
      return langCpp;
    case 'csharp':
      return langCsharp;
    case 'ruby':
      return langRuby;
    case 'php':
      return langPhp;
    case 'swift':
      return langSwift;
    case 'shell':
      return langBash;
    case 'json':
      return langJson;
    case 'yaml':
      return langYaml;
    case 'toml':
    case 'ini':
      return langIni;
    case 'sql':
      return langSql;
    case 'xml':
      return langXml;
    case 'css':
      return langCss;
    case 'markdown':
      return langMarkdown;
    case 'lua':
      return langLua;
    case 'dockerfile':
      return langDockerfile;
    case 'makefile':
      return langMakefile;
    default:
      return null;
  }
}

/// 组装 [CodeEditor] 的高亮配置；`highlight=false` 或语言未知时返回 `null`。
CodeHighlightTheme? ogLHighlightThemeFor({
  required String language,
  required bool highlight,
  required OgLCodeTheme palette,
}) {
  if (!highlight) {
    return null;
  }
  final Mode? mode = ogLHighlightModeOf(language);
  if (mode == null) {
    return null;
  }
  return CodeHighlightTheme(
    languages: <String, CodeHighlightThemeMode>{
      language: CodeHighlightThemeMode(mode: mode),
    },
    theme: ogLHighlightThemeOf(palette),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 字段封装
// ─────────────────────────────────────────────────────────────────────────────

/// 编辑器 / 查看器共用的代码字段（库 [CodeEditor] 的项目薄封装）。
class OgLCodeField extends StatefulWidget {
  /// 创建字段。
  const OgLCodeField({
    required this.controller,
    this.path = '',
    this.language = '',
    this.fontSize = 13,
    this.wrap = false,
    this.highlight = true,
    this.showLineNumbers = true,
    this.codeTheme,
    this.readOnly = false,
    this.findController,
    this.focusNode,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });

  @override
  State<OgLCodeField> createState() => _OgLCodeFieldState();

  /// 内容控制器（由调用方持有，便于保存 / 撤销）。
  final CodeLineEditingController controller;

  /// 文件路径（用于推断语言）。
  final String path;

  /// 显式语言（非空时优先于路径推断）。
  final String language;

  /// 字号。
  final double fontSize;

  /// 是否自动换行（关闭则横向滚动）。
  final bool wrap;

  /// 是否启用语法高亮。
  final bool highlight;

  /// 是否显示行号。
  final bool showLineNumbers;

  /// 配色（`null` = 从应用主题派生）。
  final OgLCodeTheme? codeTheme;

  /// 是否只读（查看器）。
  final bool readOnly;

  /// 查找 / 替换控制器（可编辑场景传入）。
  final CodeFindController? findController;

  /// 焦点节点。
  final FocusNode? focusNode;

  /// 内容内边距。
  final EdgeInsetsGeometry padding;

  static Widget _lineNumbers(
    BuildContext context,
    CodeLineEditingController editingController,
    CodeChunkController chunkController,
    CodeIndicatorValueNotifier notifier,
  ) =>
      DefaultCodeLineNumber(
        controller: editingController,
        notifier: notifier,
      );

  static PreferredSizeWidget _findPanel(
    BuildContext context,
    CodeFindController controller,
    bool readOnly,
  ) =>
      OgLCodeFindPanel(controller: controller, readOnly: readOnly);
}

/// 字段的状态：**持有长按菜单控制器**。
///
/// ## 为什么必须有它
/// `re_editor` 的 `CodeEditor` **没有 `contextMenuBuilder`**：它只接受一个
/// `SelectionToolbarController`，而那是抽象类 —— 不传就**不会出现任何菜单**，
/// 这正是「长按没有复制菜单」的根因。
///
/// 控制器必须跨重建存活：编辑器每次输入都会 `setState`，若在 `build` 里现建
/// 实例，正在显示的浮动菜单会与新实例脱钩（残留或闪烁）。
class _OgLCodeFieldState extends State<OgLCodeField> {
  late final SelectionToolbarController _toolbar =
      MobileSelectionToolbarController(builder: _selectionMenu);

  /// 长按选择时的浮动菜单。
  ///
  /// ## 文案为什么不用新增 i18n 键
  /// 四项标签全部取自 `MaterialLocalizations`（`cutButtonLabel` 等），由 Flutter
  /// 官方提供本地化，与系统菜单口径一致 —— 既不必手工翻译，也不会与系统行为
  /// 不一致。
  ///
  /// ## 为什么这里不必担心语种收敛
  /// v6.4.0 把界面语言由 15 种收敛到 6 种，但这份菜单**不受影响**：它走的是
  /// Flutter 自己的本地化委托，覆盖范围由 Flutter 决定，与本项目的语言清单无关。
  /// 这也是当初不自己写这四条文案的真正收益。
  Widget _selectionMenu({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    final bool readOnly = widget.readOnly;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: <ContextMenuButtonItem>[
        // 只读时不提供"剪切/粘贴"：给了也没意义，反而误导。
        if (!readOnly)
          ContextMenuButtonItem(
            label: l10n.cutButtonLabel,
            onPressed: () {
              controller.cut();
              onDismiss();
            },
          ),
        ContextMenuButtonItem(
          label: l10n.copyButtonLabel,
          onPressed: () {
            unawaited(controller.copy());
            onDismiss();
          },
        ),
        if (!readOnly)
          ContextMenuButtonItem(
            label: l10n.pasteButtonLabel,
            onPressed: () {
              controller.paste();
              onDismiss();
            },
          ),
        ContextMenuButtonItem(
          label: l10n.selectAllButtonLabel,
          onPressed: () {
            controller.selectAll();
            // 选中范围变化 → 让菜单按新范围重算位置。
            onRefresh();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OgLCodeTheme palette =
        widget.codeTheme ?? OgLCodeTheme.fromScheme(theme.colorScheme);
    final String lang = widget.language.isNotEmpty
        ? widget.language
        : ogLDetectLanguage(widget.path);
    return CodeEditor(
      controller: widget.controller,
      readOnly: widget.readOnly,
      showCursorWhenReadOnly: false,
      wordWrap: widget.wrap,
      focusNode: widget.focusNode,
      findController: widget.findController,
      padding: widget.padding,
      // ★ 长按选择菜单：库只认这个控制器，不传就完全没有菜单
      //   （`CodeEditor` 没有 `contextMenuBuilder`）。
      toolbarController: _toolbar,
      style: CodeEditorStyle(
        fontSize: widget.fontSize,
        fontFamily: 'monospace',
        fontHeight: 1.5,
        backgroundColor: palette.background,
        textColor: palette.foreground,
        cursorColor: theme.colorScheme.primary,
        cursorLineColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        selectionColor: theme.colorScheme.primary.withValues(alpha: 0.24),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.38),
        codeTheme: ogLHighlightThemeFor(
          language: lang,
          highlight: widget.highlight,
          palette: palette,
        ),
      ),
      indicatorBuilder:
          widget.showLineNumbers ? OgLCodeField._lineNumbers : null,
      findBuilder:
          widget.findController == null ? null : OgLCodeField._findPanel,
    );
  }
}

/// 只读代码查看器：内部自建控制器，交给 [OgLCodeField] 渲染。
class OgLCodeViewer extends StatefulWidget {
  /// 创建查看器。
  const OgLCodeViewer({
    required this.code,
    this.path = '',
    this.language = '',
    this.fontSize = 13,
    this.wrap = false,
    this.highlight = true,
    this.showLineNumbers = true,
    this.codeTheme,
    super.key,
  });

  /// 源码。
  final String code;

  /// 文件路径（用于推断语言）。
  final String path;

  /// 显式语言（非空时优先）。
  final String language;

  /// 字号。
  final double fontSize;

  /// 是否自动换行。
  final bool wrap;

  /// 是否启用高亮。
  final bool highlight;

  /// 是否显示行号。
  final bool showLineNumbers;

  /// 配色。
  final OgLCodeTheme? codeTheme;

  @override
  State<OgLCodeViewer> createState() => _OgLCodeViewerState();
}

class _OgLCodeViewerState extends State<OgLCodeViewer> {
  late CodeLineEditingController _controller =
      CodeLineEditingController.fromText(widget.code);

  @override
  void didUpdateWidget(OgLCodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _controller.dispose();
      _controller = CodeLineEditingController.fromText(widget.code);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OgLCodeField(
        controller: _controller,
        path: widget.path,
        language: widget.language,
        fontSize: widget.fontSize,
        wrap: widget.wrap,
        highlight: widget.highlight,
        showLineNumbers: widget.showLineNumbers,
        codeTheme: widget.codeTheme,
        readOnly: true,
      );
}

/// 查找 / 替换面板（`re_editor` 只提供逻辑与控制器，面板 UI 由使用方实现）。
class OgLCodeFindPanel extends StatelessWidget implements PreferredSizeWidget {
  /// 创建面板。
  const OgLCodeFindPanel({
    required this.controller,
    required this.readOnly,
    super.key,
  });

  /// 查找控制器。
  final CodeFindController controller;

  /// 是否只读（只读时不显示替换行）。
  final bool readOnly;

  /// 单行高度。
  static const double _kRowHeight = 40;

  @override
  Size get preferredSize => Size(
        double.infinity,
        controller.value == null
            ? 0
            : _kRowHeight *
                ((controller.value!.replaceMode && !readOnly) ? 2 : 1),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CodeFindValue?>(
        valueListenable: controller,
        builder: (BuildContext context, CodeFindValue? value, Widget? _) {
          if (value == null) {
            return const SizedBox.shrink();
          }
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(height: _kRowHeight, child: _findRow(context, value)),
                if (value.replaceMode && !readOnly)
                  SizedBox(height: _kRowHeight, child: _replaceRow(value)),
              ],
            ),
          );
        },
      );

  Widget _findRow(BuildContext context, CodeFindValue value) {
    final String result = value.result == null
        ? '0/0'
        : '${value.result!.index + 1}/${value.result!.matches.length}';
    return Row(
      children: <Widget>[
        const SizedBox(width: OgLSpace.sm),
        Expanded(
          child: TextField(
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: _t('findHint'),
              border: InputBorder.none,
            ),
          ),
        ),
        _toggle(
          label: 'Aa',
          checked: value.option.caseSensitive,
          tooltip: _t('matchCase'),
          onPressed: controller.toggleCaseSensitive,
        ),
        _toggle(
          label: '.*',
          checked: value.option.regex,
          tooltip: _t('useRegex'),
          onPressed: controller.toggleRegex,
        ),
        Text(result, style: const TextStyle(fontSize: 12)),
        IconButton(
          icon: const Icon(Icons.arrow_upward, size: 18),
          tooltip: _t('prevMatch'),
          onPressed: value.result == null ? null : controller.previousMatch,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_downward, size: 18),
          tooltip: _t('nextMatch'),
          onPressed: value.result == null ? null : controller.nextMatch,
        ),
        if (!readOnly)
          IconButton(
            icon: const Icon(Icons.swap_vert, size: 18),
            tooltip: value.replaceMode ? _t('findOnly') : _t('replaceMode'),
            onPressed: value.replaceMode
                ? controller.findMode
                : controller.replaceMode,
          ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: _t('close'),
          onPressed: controller.close,
        ),
      ],
    );
  }

  Widget _replaceRow(CodeFindValue value) => Row(
        children: <Widget>[
          const SizedBox(width: OgLSpace.sm),
          Expanded(
            child: TextField(
              controller: controller.replaceInputController,
              focusNode: controller.replaceInputFocusNode,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: _t('replaceWithHint'),
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.done, size: 18),
            tooltip: _t('replaceMode'),
            onPressed: value.result == null ? null : controller.replaceMatch,
          ),
          IconButton(
            icon: const Icon(Icons.done_all, size: 18),
            tooltip: _t('replaceAll'),
            onPressed:
                value.result == null ? null : controller.replaceAllMatches,
          ),
          const SizedBox(width: OgLSpace.sm),
        ],
      );

  Widget _toggle({
    required String label,
    required bool checked,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: checked ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
}
