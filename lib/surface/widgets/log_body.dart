/// L3 展示级 · 长文本（日志 / 补丁 / 大段输出）的**分块虚拟化**渲染件。
///
/// ## 为什么不用 `SelectableText` 直接塞整份文本
/// Actions 的运行日志动辄上万行：一次性交给 `SelectableText` 会**把每一行都排版一遍**
/// ——展开即卡几秒，滚动也掉帧。本控件把文本按行切块（默认每块 120 行），
/// 交给 `ListView.builder` **按需构建**：只有视口附近的块会排版，长日志秒开。
///
/// 取舍：行内选择仍然可用（每块是独立的 `SelectionArea`），
/// 但跨块连续选择不像单一大文本那样自然——换来的是**打开与滚动不再卡**。
library;

import 'package:flutter/material.dart';

/// 分块日志体。
class OgLLogBody extends StatefulWidget {
  /// 创建。
  const OgLLogBody({
    required this.text,
    this.chunkLines = 120,
    super.key,
  });

  /// 完整文本（可能很大）。
  final String text;

  /// 每块行数（越小越省内存、越长滚动越顺）。
  final int chunkLines;

  @override
  State<OgLLogBody> createState() => _OgLLogBodyState();
}

class _OgLLogBodyState extends State<OgLLogBody> {
  List<String> _chunks = const <String>[];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant OgLLogBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.chunkLines != widget.chunkLines) {
      _rebuild();
    }
  }

  /// 切片（O(n) 一次；相比"每帧排版全部行"便宜得多）。
  void _rebuild() {
    final List<String> lines = widget.text.split('\n');
    final int size = widget.chunkLines <= 0 ? 120 : widget.chunkLines;
    final List<String> chunks = <String>[];
    for (int start = 0; start < lines.length; start += size) {
      final int end =
          (start + size) < lines.length ? start + size : lines.length;
      chunks.add(lines.sublist(start, end).join('\n'));
    }
    _chunks = chunks.isEmpty ? const <String>[''] : chunks;
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        // 关闭"自动加 RepaintBoundary"以外的花活：列表项本身已带绘制边界。
        padding: EdgeInsets.zero,
        itemCount: _chunks.length,
        itemBuilder: (BuildContext context, int index) => SelectionArea(
          child: Text(
            _chunks[index],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      );
}
