/// L3 展示级 · 日志查找条（x/y 计数 + 上一处 / 下一处跳转按钮）。
///
/// 一件事一个文件：[OgLLogSearchBar] 只管"输入关键词 + 报告跳转"，
/// 扫描与高亮在 `log_body.dart`（正文渲染端），页面状态在页面里。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/og_l_space.dart';

/// 日志查找条。
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

  @override
  void dispose() {
    _controller.dispose();
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
            style: theme.textTheme.bodySmall,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
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
