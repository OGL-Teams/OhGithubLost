/// L3 展示级 · 日志正文查找条（大小写不敏感 / x/y 计数 / 上下跳转 + 命中高亮）。
///
/// ## 为什么单独一个文件（一件事一个文件）
/// 「在一个可能几百 KB 的日志文本里查找」这件事有自己的状态机：
/// 命中索引、当前命中、跳转时机。塞进页面会把页面状态搅浑；塞进
/// `OgLLogBody` 会让纯渲染构件背上有状态的查找语义。这里只做一件事。
///
/// ## 性能边界
/// 查找**只对当前展开 job 的文本**做（每次输入防抖后跑一次 `toLowerCase` +
/// `indexOf` 扫描），命中位置存行号 + 列偏移；高亮走每行 `TextSpan` 切片，
/// 不做全文 `SelectableText`（几万行一次性排版是性能事故）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/og_l_space.dart';

/// 一次命中：在 [text] 中的字符偏移。
///
/// （行号由渲染侧按偏移折算，这里只存单一真相——偏移。）
class OgLLogMatch {
  /// 创建命中。
  const OgLLogMatch(this.start, this.end);

  /// 起始偏移（含）。
  final int start;

  /// 结束偏移（不含）。
  final int end;
}

/// 查找结果。
class OgLLogSearchResult {
  /// 创建结果。
  const OgLLogSearchResult(this.matches, this.query);

  /// 全部命中（按出现顺序）。
  final List<OgLLogMatch> matches;

  /// 触发本次查找的关键词（小写）。
  final String query;

  /// 是否无命中（含空关键词——空关键词不算"无命中"）。
  bool get isEmpty => query.isEmpty ? false : matches.isEmpty;
}

/// 对 [text] 做大小写不敏感的子串扫描，返回全部命中。
///
/// 纯函数，便于单测；调用方自行防抖（输入时不必每键全扫）。
OgLLogSearchResult ogLLogSearch(String text, String rawQuery) {
  final String query = rawQuery.toLowerCase();
  if (query.isEmpty) {
    return OgLLogSearchResult(const <OgLLogMatch>[], '');
  }
  final String hay = text.toLowerCase();
  final List<OgLLogMatch> matches = <OgLLogMatch>[];
  var cursor = 0;
  while (cursor <= hay.length - query.length) {
    final int hit = hay.indexOf(query, cursor);
    if (hit < 0) {
      break;
    }
    matches.add(OgLLogMatch(hit, hit + query.length));
    cursor = hit + query.length;
  }
  return OgLLogSearchResult(matches, query);
}

/// 把一段文本按 [OgLLogMatch] 切成高亮 `TextSpan` 列表（单行内）。
List<TextSpan> ogLLogHighlightSpans({
  required String text,
  required int lineStart,
  required List<OgLLogMatch> matches,
  required TextStyle? base,
  required TextStyle highlight,
}) {
  if (matches.isEmpty) {
    return <TextSpan>[TextSpan(text: text, style: base)];
  }
  final List<TextSpan> spans = <TextSpan>[];
  var cursor = 0;
  for (final OgLLogMatch m in matches) {
    final int from = (m.start - lineStart).clamp(0, text.length);
    final int to = (m.end - lineStart).clamp(0, text.length);
    if (from >= to) {
      continue;
    }
    if (from > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, from), style: base));
    }
    spans.add(TextSpan(text: text.substring(from, to), style: highlight));
    cursor = to;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return spans;
}

/// 日志查找条：输入框 + `x / y` 计数 + 上一处 / 下一处。
class OgLLogSearchBar extends StatefulWidget {
  /// 创建查找条。
  const OgLLogSearchBar({
    required this.onSubmit,
    required this.onJump,
    required this.total,
    required this.current,
    this.hintText = '',
    super.key,
  });

  /// 关键词变化（调用方自行防抖后回报 [total] / [current]）。
  final ValueChanged<String> onSubmit;

  /// 跳转（`delta` 为 +1 下一处 / -1 上一处）。
  final ValueChanged<int> onJump;

  /// 命中总数。
  final int total;

  /// 当前第几处（1 起；0 表示无命中）。
  final int current;

  /// 输入框提示。
  final String hintText;

  @override
  State<OgLLogSearchBar> createState() => _OgLLogSearchBarState();
}

class _OgLLogSearchBarState extends State<OgLLogSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: widget.hintText,
            ),
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(200),
            ],
            onChanged: widget.onSubmit,
          ),
        ),
        const SizedBox(width: OgLSpace.sm),
        Text(
          widget.total <= 0 ? '0' : '${widget.current} / ${widget.total}',
          style: theme.textTheme.bodySmall,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '↑',
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: widget.total <= 0 ? null : () => widget.onJump(-1),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '↓',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: widget.total <= 0 ? null : () => widget.onJump(1),
        ),
      ],
    );
  }
}

/// 计算命中所在的"块索引"（渲染分块场景下跳转用）。
///
/// [chunkSizes] 为每块字符数的前缀累积；返回第一个包含偏移的块下标。
int ogLLogChunkIndexOf(List<int> chunkEnds, int offset) {
  var lo = 0;
  var hi = chunkEnds.length - 1;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (chunkEnds[mid] <= offset) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}
