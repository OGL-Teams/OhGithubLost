/// L3 展示级 · 长文本（日志 / 补丁 / 大段输出）的**分块虚拟化**渲染件。
///
/// ## 为什么不用 `SelectableText` 直接塞整份文本
/// Actions 的运行日志动辄上万行：一次性交给 `SelectableText` 会**把每一行都排版一遍**
/// ——展开即卡几秒，滚动也掉帧。本控件把文本按行切块（默认每块 120 行），
/// 交给 `ListView.builder` **按需构建**：只有视口附近的块会排版，长日志秒开。
///
/// 取舍：行内选择仍然可用（每块是独立的 `SelectionArea`），
/// 但跨块连续选择不像单一大文本那样自然——换来的是**打开与滚动不再卡**。
///
/// ## 查找（`query` / `jumpToken`）
/// - `query` 非空时按大小写不敏感扫描**当前文本**，命中片段以 `highlight`
///   背景渲染（按块内切片，不引入全文富文本）；
/// - `jumpToken` 变化时把**第 N 处命中**滚进可视区（N = `jumpToken` 的值）；
///   token 变化才滚动（同一处不重复跳），由调用方维护当前序号。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../theme.dart';

/// 分块日志体。
class OgLLogBody extends StatefulWidget {
  /// 创建。
  const OgLLogBody({
    required this.text,
    this.chunkLines = 120,
    this.query = '',
    this.jumpToken = 0,
    this.highlightColor,
    super.key,
  });

  /// 完整文本（可能很大）。
  final String text;

  /// 每块行数（越小越省内存、越长滚动越顺）。
  final int chunkLines;

  /// 查找关键词（空 = 不查找不高亮；大小写不敏感）。
  final String query;

  /// 跳转令牌：值变化时把"第 `jumpToken` 处命中"滚到可视区。
  final int jumpToken;

  /// 命中高亮背景（缺省取 `secondaryContainer`）。
  final Color? highlightColor;

  @override
  State<OgLLogBody> createState() => _OgLLogBodyState();
}

class _OgLLogBodyState extends State<OgLLogBody> {
  List<String> _chunks = const <String>[];
  final ScrollController _scroll = ScrollController();

  /// 命中偏移列表（全文，按出现顺序）。
  List<int> _hits = const <int>[];
  int _queryLen = 0;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant OgLLogBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.chunkLines != widget.chunkLines ||
        oldWidget.query != widget.query) {
      _rebuild();
    }
    // 跳转令牌变化 → 滚到第 N 处命中（在下一帧布局完成后量位置）。
    if (oldWidget.jumpToken != widget.jumpToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 切片（O(n) 一次；相比"每帧排版全部行"便宜得多）+ 查找扫描。
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
    // 查找扫描（只对当前 job 的文本；O(n)，输入防抖由页面负责）。
    final String needle = widget.query.toLowerCase();
    if (needle.isEmpty) {
      _hits = const <int>[];
      _queryLen = 0;
      return;
    }
    final String hay = widget.text.toLowerCase();
    final List<int> hits = <int>[];
    var cursor = 0;
    while (cursor <= hay.length - needle.length) {
      final int hit = hay.indexOf(needle, cursor);
      if (hit < 0) {
        break;
      }
      hits.add(hit);
      cursor = hit + needle.length;
    }
    _hits = hits;
    _queryLen = needle.length;
  }

  /// 把第 `jumpToken - 1` 处命中滚进可视区（粗定位：按命中所在块的估计高度）。
  void _jump() {
    if (!mounted) {
      return;
    }
    final int index = widget.jumpToken - 1;
    if (index < 0 || index >= _hits.length || !_scroll.hasClients) {
      return;
    }
    // 每块高度 ≈ 该块行数 × 行高（等宽 12pt × 1.4 ≈ 16.8 逻辑像素）。
    const double kLineHeight = 16.8;
    final int size = widget.chunkLines <= 0 ? 120 : widget.chunkLines;
    // 命中前的换行数 = 块序（粗略但不失准：命中按块均匀分布时误差 < 一块）。
    final int lineIndex =
        widget.text.substring(0, _hits[index]).split('\n').length - 1;
    final int block = lineIndex ~/ size;
    final int lineInBlock = lineIndex % size;
    final double target =
        block * size * kLineHeight + lineInBlock * kLineHeight;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: OgLAnim.medium(context),
      curve: OgLAnim.curve(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color hl =
        widget.highlightColor ?? theme.colorScheme.secondaryContainer;
    return ListView.builder(
      controller: _scroll,
      // 关闭"自动加 RepaintBoundary"以外的花活：列表项本身已带绘制边界。
      padding: EdgeInsets.zero,
      itemCount: _chunks.length,
      itemBuilder: (BuildContext context, int index) => SelectionArea(
        child: _chunkText(index, theme, hl),
      ),
    );
  }

  /// 单块内容：无查找 → 纯文本（原路径，零额外成本）；
  /// 有查找 → 命中切片富文本（只在本块内切，成本 O(块长)）。
  Widget _chunkText(int index, ThemeData theme, Color hl) {
    final String chunk = _chunks[index];
    if (_hits.isEmpty) {
      return Text(
        chunk,
        style: const TextStyle(
          fontFamily: kOglMonoFamily,
          fontSize: 12,
          height: 1.4,
        ),
      );
    }
    // 本块的字符区间：前面块字符数之和（含各块间的 '\n'）。
    int blockStart = 0;
    for (int i = 0; i < index; i++) {
      blockStart += _chunks[i].length + 1; // +1 是块间换行
    }
    final int blockEnd = blockStart + chunk.length;
    final TextStyle base = const TextStyle(
      fontFamily: kOglMonoFamily,
      fontSize: 12,
      height: 1.4,
    );
    final TextStyle hlStyle = base.copyWith(backgroundColor: hl);
    final List<InlineSpan> spans = <InlineSpan>[];
    var cursor = blockStart;
    for (final int hit in _hits) {
      if (hit + _queryLen <= blockStart) {
        continue;
      }
      if (hit >= blockEnd) {
        break;
      }
      final int from = hit < blockStart ? blockStart : hit;
      final int to = (hit + _queryLen) > blockEnd ? blockEnd : hit + _queryLen;
      if (from > cursor) {
        spans.add(TextSpan(
            text: chunk.substring(cursor - blockStart, from - blockStart)));
      }
      spans.add(TextSpan(
        text: chunk.substring(from - blockStart, to - blockStart),
        style: hlStyle,
      ));
      cursor = to;
    }
    if (cursor < blockEnd) {
      spans.add(TextSpan(text: chunk.substring(cursor - blockStart)));
    }
    return RichText(
      text: TextSpan(children: spans, style: base),
    );
  }
}
