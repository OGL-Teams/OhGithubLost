/// L3 展示级 · 代码编辑器的**可测**工具栏。
///
/// ## 为什么单独抽出来
/// 真机反馈过「顶栏漏缝」：工具栏背景色虽然已与代码区一致，但工具栏
/// **本身没铺满宽度**——横向 `SingleChildScrollView` 里的
/// `Row(mainAxisSize: min)` 只有图标那么宽，`Material` 于是按内容收缩，
/// 真机实测灰带只覆盖 x=43..978，两端各露一条 surface 白缝，
/// 而下方代码区满宽（x=0..1038）。
///
/// 这里把「铺满宽度」固化成组件结构（外层 `SizedBox(width: double.infinity)`），
/// 并在 `test/surface/ui_regression_test.dart` 里钉成回归。
///
/// 文案（tooltip）由调用方按分片传入，组件本身不含任何界面文案。
library;

import 'package:flutter/material.dart';

import '../util/og_l_space.dart';

/// 代码编辑器工具栏：一排低频操作（撤销 / 重做 / 查找 / 换行 / 字号 / 预览）。
class OgLCodeEditorToolbar extends StatelessWidget {
  /// 创建。
  const OgLCodeEditorToolbar({
    required this.backgroundColor,
    required this.canUndo,
    required this.canRedo,
    required this.wrap,
    required this.onUndo,
    required this.onRedo,
    required this.onToggleFind,
    required this.onToggleWrap,
    required this.onFontSmaller,
    required this.onFontLarger,
    required this.onPreview,
    required this.undoTooltip,
    required this.redoTooltip,
    required this.findTooltip,
    required this.wrapOnTooltip,
    required this.wrapOffTooltip,
    required this.fontSmallerTooltip,
    required this.fontLargerTooltip,
    required this.previewTooltip,
    super.key,
  });

  /// 背景色（由调用方给：与代码区背景同色 → 视觉连成一体）。
  final Color backgroundColor;

  /// 是否可撤销。
  final bool canUndo;

  /// 是否可重做。
  final bool canRedo;

  /// 当前是否自动换行。
  final bool wrap;

  /// 撤销。
  final VoidCallback onUndo;

  /// 重做。
  final VoidCallback onRedo;

  /// 切换查找面板。
  final VoidCallback onToggleFind;

  /// 切换自动换行。
  final VoidCallback onToggleWrap;

  /// 字号变小。
  final VoidCallback onFontSmaller;

  /// 字号变大。
  final VoidCallback onFontLarger;

  /// 打开预览。
  final VoidCallback onPreview;

  /// 撤销提示。
  final String undoTooltip;

  /// 重做提示。
  final String redoTooltip;

  /// 查找提示。
  final String findTooltip;

  /// 开自动换行提示。
  final String wrapOnTooltip;

  /// 关自动换行提示。
  final String wrapOffTooltip;

  /// 字号变小提示。
  final String fontSmallerTooltip;

  /// 字号变大提示。
  final String fontLargerTooltip;

  /// 预览提示。
  final String previewTooltip;

  @override
  Widget build(BuildContext context) => Material(
        // 背景由调用方的代码配色主题决定（与代码区同色 → 视觉连成一体）。
        color: backgroundColor,
        // ★ 铺满宽度：内容仍可横向滑动，但**背景条**必须与代码区同宽，
        //   否则两端会露出 Scaffold 底色（真机上的「漏缝」）。
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: OgLSpace.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.undo),
                  tooltip: undoTooltip,
                  onPressed: canUndo ? onUndo : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.redo),
                  tooltip: redoTooltip,
                  onPressed: canRedo ? onRedo : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.search),
                  tooltip: findTooltip,
                  onPressed: onToggleFind,
                ),
                const VerticalDivider(width: OgLSpace.lg),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(wrap ? Icons.wrap_text : Icons.notes),
                  tooltip: wrap ? wrapOffTooltip : wrapOnTooltip,
                  onPressed: onToggleWrap,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove),
                  tooltip: fontSmallerTooltip,
                  onPressed: onFontSmaller,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add),
                  tooltip: fontLargerTooltip,
                  onPressed: onFontLarger,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.visibility_outlined),
                  tooltip: previewTooltip,
                  onPressed: onPreview,
                ),
              ],
            ),
          ),
        ),
      );
}
