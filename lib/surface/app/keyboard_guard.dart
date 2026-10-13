/// L3 展示级 · 键盘 inset 守卫 + 窗口指标日志。
///
/// ## 它解决两个真实问题
/// 1. **"幽灵键盘"把界面顶残**：Android 上报了巨大的 `viewInsets.bottom`
///    （半屏以上），但屏幕上并没有键盘。`Scaffold` 会照章办事：
///    body 被压扁、底栏被抬到屏幕中间 —— 用户看到的就是
///    "内容全空 + 底栏居中 + 下方一大片黑"。
///    规则很简单：**没有任何文本输入获得焦点时，bottom inset 一律当 0**；
///    真的在打字（`EditableText` 持有焦点）时，原样保留、正常避让键盘。
/// 2. **窗口指标的"黑匣子"**：把每次 metrics 变化（尺寸 / insets / padding）
///    写进日志文件 —— 下次真机复现时，"半屏从哪来"会有第一手数据。
library;

import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';

import '../../kernel/log/og_l_log_file.dart';

/// 键盘 inset 守卫（挂在 `MaterialApp.builder`，包住整棵应用树）。
class OgLKeyboardGuard extends StatefulWidget {
  /// 创建守卫。
  const OgLKeyboardGuard({required this.child, super.key});

  /// 被包裹的应用内容。
  final Widget child;

  @override
  State<OgLKeyboardGuard> createState() => _OgLKeyboardGuardState();
}

class _OgLKeyboardGuardState extends State<OgLKeyboardGuard>
    with WidgetsBindingObserver {
  bool _ignoring = false;
  String _lastMetrics = '';
  DateTime _lastLogAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    // i18n-allow: 开发者日志的上下文标签（启动时的键盘度量），不是界面文案。
    WidgetsBinding.instance.addPostFrameCallback((_) => _logMetrics('初始'));
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  // i18n-allow: 同上 —— 键盘度量变化时的日志标签，不是界面文案。
  void didChangeMetrics() => _logMetrics('变化');

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 当前焦点是不是文本输入（`EditableText` 把自己的 FocusNode 挂在自身上）。
  ///
  /// re_editor（代码编辑器）是**自绘输入**：焦点挂在自己的普通 `Focus` 上
  /// （debugLabel = `CodeEditor`），而不是 `EditableText`。若只认 `EditableText`，
  /// 打字时 bottom inset 会被当成"幽灵键盘"归零 —— 编辑区被键盘遮住。
  /// 拿不到上下文（无法判定）时**保留 inset**：宁可多留，不可遮挡。
  bool get _textFocused {
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    if (focus == null) {
      return false;
    }
    final BuildContext? context = focus.context;
    if (context?.widget is EditableText) {
      return true;
    }
    final String? label = focus.debugLabel;
    if (label != null && label.contains('CodeEditor')) {
      return true;
    }
    return context == null;
  }

  void _logMetrics(String phase) {
    try {
      final FlutterView view =
          WidgetsBinding.instance.platformDispatcher.views.first;
      final double dpr = view.devicePixelRatio;
      final Size logical = view.physicalSize / dpr;
      // 注意：`ViewPadding` 没有 `/` 运算符——必须逐字段换算
      //（键盘关心 bottom、安全区关心 top/bottom，足够定位问题）。
      final double insetsBottom = view.viewInsets.bottom;
      final double padTop = view.padding.top;
      final double padBottom = view.padding.bottom;
      // i18n-allow: 这段只是「窗口指标」日志载荷（随后由 OgLLogFile 落盘），非界面文案。
      final String line = '$phase：窗口 ${logical.width.toStringAsFixed(0)}×'
          '${logical.height.toStringAsFixed(0)} @${dpr.toStringAsFixed(2)}x '
          'insets.b=${(insetsBottom / dpr).toStringAsFixed(1)} '
          'padding.t/b=${(padTop / dpr).toStringAsFixed(1)}/'
          '${(padBottom / dpr).toStringAsFixed(1)}';
      if (line == _lastMetrics) {
        return;
      }
      // 节流：设备上报的 inset 会在 0 与大值之间高频跳动，逐条落盘只会
      // 把日志刷满（且没有新信息）。同一形态至多 1 秒记 1 条。
      final DateTime now = DateTime.now();
      if (now.difference(_lastLogAt) < const Duration(seconds: 1)) {
        _lastMetrics = line;
        return;
      }
      _lastLogAt = now;
      _lastMetrics = line;
      OgLLogFile.line('窗口', line);
    } catch (error) {
      OgLLogFile.line('窗口', '窗口指标读取失败：$error', level: 'WARN');
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData query = MediaQuery.of(context);
    final double bottom = query.viewInsets.bottom;
    final bool ignore = bottom > 0 && !_textFocused;

    if (ignore && !_ignoring) {
      OgLLogFile.line(
        '窗口',
        '检测到无文本焦点的残留键盘 inset=${bottom.toStringAsFixed(0)} '
            '→ 已忽略（防止"底栏被顶到屏幕中间"）',
        level: 'WARN',
      );
    }
    if (!ignore && _ignoring) {
      OgLLogFile.line(
          '窗口', '键盘 inset 恢复生效（bottom=${bottom.toStringAsFixed(0)}）');
    }
    _ignoring = ignore;

    if (!ignore) {
      return widget.child;
    }
    // 只针对"没有文本焦点"的场景把 bottom inset 归零；
    // 真键盘弹出（有 EditableText 焦点）时走上面的正常路径。
    return MediaQuery(
      data: query.removeViewInsets(removeBottom: true),
      child: widget.child,
    );
  }
}
