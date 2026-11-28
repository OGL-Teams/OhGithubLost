/// L3 展示级 · MD1 经典（2014）五控件自绘外观（CustomPainter 层）。
///
/// ## 纪律
/// 本文件里的每个可见外观都由 [CustomPainter] 绘制；不使用任何 Material
/// 控件（ElevatedButton / TextButton / ListTile / Card / AppBar 等）。
/// 布局只用 Row / Column / Stack / Padding / SizedBox / GestureDetector / Text。
/// 色值 / 尺寸 / 字阶 / 阴影全部取 [md1_tokens.dart] 的令牌，零裸值。
///
/// ## 控件清单（第一批）
/// `OgMd1Button` / `OgMd1Card` / `OgMd1ListRow` / `OgMd1Ripple` / `OgMd1AppBar`。
library;

import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show
        LogicalKeyboardKey,
        RawKeyDownEvent,
        RawKeyEvent,
        TextEditingValue,
        TextSelection;
import 'package:flutter/widgets.dart'
    show
        AnimatedBuilder,
        AnimationController,
        BuildContext,
        ClipRect,
        Colors,
        Column,
        ConstrainedBox,
        CrossAxisAlignment,
        CustomPaint,
        Duration,
        EdgeInsets,
        EdgeInsetsDirectional,
        Expanded,
        Focus,
        FocusNode,
        GestureDetector,
        GlobalKey,
        HitTestBehavior,
        IgnorePointer,
        Key,
        MainAxisSize,
        MainAxisAlignment,
        Padding,
        Positioned,
        RawKeyboardListener,
        Row,
        Semantics,
        SingleTickerProviderStateMixin,
        SizedBox,
        Stack,
        State,
        StatefulWidget,
        StatelessWidget,
        TapDownDetails,
        DragUpdateDetails,
        Text,
        TextAlign,
        TextDirection,
        TextEditingController,
        TextOverflow,
        TextSpan,
        TextStyle,
        ValueChanged,
        VoidCallback,
        Widget,
        withValues;

import '../app/animations.dart' show OgLAnim;
import 'md1_tokens.dart'
    show
        OgMd1Colors,
        OgMd1Elevation,
        OgMd1Size,
        OgMd1Type,
        _md1BadgeDot,
        _md1BadgeSize,
        _md1ChipHeightMax,
        _md1ChipHeightMin,
        _md1ChipPadding,
        _md1ChipVisual,
        _md1DialogActionGap,
        _md1DialogGap,
        _md1DialogPadding,
        _md1DividerPx,
        _md1SnackbarGap,
        _md1SnackbarHeight,
        _md1SnackbarPadding;

/// 按钮样式：flat（透明底）与 raised（primary 底 + 投影）。
enum OgMd1ButtonStyle {
  /// 无底色、无投影，文字用 primary。
  flat,

  /// primary 底 + 2dp 投影，文字用 onPrimary。
  raised,
}

/// 把 [BoxShadow] 列表逐层画到画布上（MD1 阴影是真投影，不用 Material 壳）。
///
/// 不用 `MaskFilter.blur`：它会触发 saveLayer 离屏合成（perf_audit 确定的
/// 卡顿源）。改用**同心 RRect 阶梯**近似高斯模糊——每层扩大半径并降低
/// alpha，3 层叠加视觉上等价于 MD1 的 box-shadow，且全程零 saveLayer。
void _paintShadows(Canvas canvas, RRect shape, Iterable<BoxShadow> shadows) {
  const int layers = 3;
  for (final BoxShadow shadow in shadows) {
    final double spread = shadow.blurRadius / 2;
    for (int i = layers; i >= 1; i--) {
      final double t = i / layers;
      canvas.drawRRect(
        shape.shift(shadow.offset * t).inflate(spread * t),
        Paint()
          ..color = shadow.color.withValues(
            alpha: shadow.color.a / (layers * 1.6),
          )
          ..style = PaintingStyle.fill,
      );
    }
  }
}

/// 按钮外观 painter：底色（raised）+ 2dp 圆角 + ripple 遮罩。
class _OgMd1ButtonPainter extends CustomPainter {
  const _OgMd1ButtonPainter({
    required this.color,
    required this.rippleColor,
    required this.raised,
    required this.rippleProgress,
    required this.rippleCenter,
  });

  final Color color;
  final Color rippleColor;
  final bool raised;
  final double rippleProgress;
  final Offset? rippleCenter;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    if (raised) {
      _paintShadows(canvas, rect, OgMd1Elevation.dp2);
    }
    canvas.drawRRect(rect, Paint()..color = color);
    if (rippleCenter != null) {
      final Offset center = rippleCenter!;
      final double maxRadius = math.max(
        math.max(center.dx, size.width - center.dx),
        math.max(center.dy, size.height - center.dy),
      );
      canvas.save();
      canvas.clipRRect(rect);
      canvas.drawCircle(
        center,
        maxRadius * rippleProgress,
        Paint()
          ..color = rippleColor.withValues(alpha: 0.22 * (1 - rippleProgress))
          ..blendMode = BlendMode.srcOver,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OgMd1ButtonPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.rippleColor != rippleColor ||
      oldDelegate.raised != raised ||
      oldDelegate.rippleProgress != rippleProgress ||
      oldDelegate.rippleCenter != rippleCenter;
}

/// MD1 flat / raised 按钮：36dp 高、2dp 圆角、按压 ripple。
class OgMd1Button extends StatefulWidget {
  /// 创建按钮。
  const OgMd1Button({
    required this.label,
    required this.onPressed,
    this.style = OgMd1ButtonStyle.flat,
    super.key,
  });

  /// 按钮文字（调用方传已本地化文案；MD1 约定英文全大写由调用方给出）。
  final String label;

  /// 点击回调；为 null 时按钮不可用。
  final VoidCallback? onPressed;

  /// flat（默认）/ raised。
  final OgMd1ButtonStyle style;

  @override
  State<OgMd1Button> createState() => _OgMd1ButtonState();
}

class _OgMd1ButtonState extends State<OgMd1Button>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OgLAnim.fast(context),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startRipple(TapDownDetails details) {
    if (widget.onPressed == null) {
      return;
    }
    _center = details.localPosition;
    _controller
      ..reset()
      ..forward();
  }

  Offset? _center;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool raised = widget.style == OgMd1ButtonStyle.raised;
    final Color background = raised ? palette.primary : Colors.transparent;
    final Color foreground = raised ? palette.onPrimary : palette.primary;
    final Color ripple = raised ? palette.onPrimary : palette.primary;
    final bool enabled = widget.onPressed != null;
    final TextStyle textStyle = TextStyle(
      fontSize: OgMd1Type.button,
      fontWeight: OgMd1Type.buttonWeight,
      color: enabled ? foreground : palette.textSecondary,
    );

    return GestureDetector(
      onTapDown: _startRipple,
      onTap: widget.onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: OgMd1Size.buttonHeight,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) => CustomPaint(
            painter: _OgMd1ButtonPainter(
              color: enabled ? background : palette.divider,
              rippleColor: ripple,
              raised: raised && enabled,
              rippleProgress: _controller.value,
              rippleCenter: _center,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OgMd1Size.buttonPadding,
              ),
              child: child,
            ),
          ),
          child: Text(
            widget.label,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// 卡片外观 painter：card 底色 + 2dp 圆角 + 2dp elevation。
class _OgMd1CardPainter extends CustomPainter {
  const _OgMd1CardPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    _paintShadows(canvas, rect, OgMd1Elevation.dp2);
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1CardPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// MD1 卡片：2dp 投影、2dp 圆角，内容由 [child] 提供。
class OgMd1Card extends StatelessWidget {
  /// 创建卡片。
  const OgMd1Card({required this.child, super.key});

  /// 卡片内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OgMd1CardPainter(color: OgMd1Colors.of(context).card),
      child: child,
    );
  }
}

/// 列表行外观 painter：card 底色 + 1px 底部分割线（无 elevation）。
class _OgMd1ListRowPainter extends CustomPainter {
  const _OgMd1ListRowPainter({
    required this.color,
    required this.dividerColor,
    required this.divider,
  });

  final Color color;
  final Color dividerColor;
  final bool divider;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    if (divider) {
      canvas.drawLine(
        Offset(0, size.height - 1),
        Offset(size.width, size.height - 1),
        Paint()..color = dividerColor,
      );
    }
  }

  @override
  bool shouldRepaint(_OgMd1ListRowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dividerColor != dividerColor ||
      oldDelegate.divider != divider;
}

/// MD1 列表行：双行 72dp / 单行 56dp，leading 40dp、主文 16sp、副文 14sp。
class OgMd1ListRow extends StatelessWidget {
  /// 创建列表行。
  const OgMd1ListRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    this.divider = true,
    super.key,
  });

  /// 主文（16sp）。
  final String title;

  /// 副文（14sp）；为空即为单行 56dp 行。
  final String? subtitle;

  /// 前置图形，约束在 40dp 方块内。
  final Widget? leading;

  /// 点按回调。
  final VoidCallback? onTap;

  /// 是否画 1px 底部分割线。
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool twoLines = subtitle != null;
    final double height =
        twoLines ? OgMd1Size.listRowDouble : OgMd1Size.listRowSingle;
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null)
          SizedBox(
            width: OgMd1Size.listLeading,
            height: OgMd1Size.listLeading,
            child: leading,
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: OgMd1Type.subhead,
                  fontWeight: OgMd1Type.bodyWeight,
                  color: palette.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (twoLines)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: OgMd1Type.body,
                    fontWeight: OgMd1Type.bodyWeight,
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _OgMd1ListRowPainter(
            color: palette.card,
            dividerColor: palette.divider,
            divider: divider,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OgMd1Size.buttonPadding,
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// Ripple 外观 painter：从触点扩散的半透明圆（MD1 经典按压反馈）。
class _OgMd1RipplePainter extends CustomPainter {
  const _OgMd1RipplePainter({
    required this.color,
    required this.progress,
    required this.center,
  });

  final Color color;
  final double progress;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final double maxRadius = math.max(
      math.max(center.dx, size.width - center.dx),
      math.max(center.dy, size.height - center.dy),
    );
    canvas.drawCircle(
      center,
      maxRadius * progress,
      Paint()
        ..color = color.withValues(alpha: 0.3 * (1 - progress))
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_OgMd1RipplePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.center != center;
}

/// MD1 独立 ripple：按下从触点扩散，抬手/取消后归零。
///
/// 圆心取当前控件中心（外接半径保证覆盖整个控件）；时长走 [OgLAnim] 档位表。
class OgMd1Ripple extends StatefulWidget {
  /// 创建 ripple。
  const OgMd1Ripple({
    required this.color,
    required this.active,
    this.child,
    super.key,
  });

  /// 波纹颜色。
  final Color color;

  /// 是否正在按压。
  final bool active;

  /// 被覆盖的内容（可为 null，仅画波纹）。
  final Widget? child;

  @override
  State<OgMd1Ripple> createState() => _OgMd1RippleState();
}

class _OgMd1RippleState extends State<OgMd1Ripple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OgLAnim.medium(context),
  );

  @override
  void didUpdateWidget(covariant OgMd1Ripple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _controller.forward(from: 0);
      } else {
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(from: 0),
      onTapUp: (_) => _controller.reset(),
      onTapCancel: () => _controller.reset(),
      behavior: HitTestBehavior.deferToChild,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) => CustomPaint(
            painter: _OgMd1RipplePainter(
              color: widget.color,
              progress: _controller.value,
              center: const Offset(0, 0),
            ),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// AppBar 外观 painter：纯 primary 底 + 4dp 真投影（无 Material AppBar）。
class _OgMd1AppBarPainter extends CustomPainter {
  const _OgMd1AppBarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _paintShadows(
      canvas,
      RRect.fromRectAndRadius(Offset.zero & size, Radius.zero),
      OgMd1Elevation.dp4,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1AppBarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// MD1 AppBar：56dp 高、纯 primary、elevation 4、白字 20sp。
class OgMd1AppBar extends StatelessWidget {
  /// 创建 AppBar。
  const OgMd1AppBar({required this.title, this.leading, super.key});

  /// 标题文字（20sp / w500 / onPrimary）。
  final String title;

  /// 左侧图形（如返回箭头），约束在 48dp 触控目标内。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null)
          SizedBox(
            width: OgMd1Size.touchTarget,
            height: OgMd1Size.touchTarget,
            child: leading,
          ),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: OgMd1Type.title,
              fontWeight: OgMd1Type.titleWeight,
              color: palette.onPrimary,
            ),
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
    return SizedBox(
      height: OgMd1Size.appBar,
      child: CustomPaint(
        painter: _OgMd1AppBarPainter(color: palette.primary),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: OgMd1Size.buttonPadding,
          ),
          child: row,
        ),
      ),
    );
  }
}

/// TextField 外观 painter：48dp 高、底边 1px（focus 2px primary）、浮动 label（12sp）。
class _OgMd1TextFieldPainter extends CustomPainter {
  const _OgMd1TextFieldPainter({
    required this.dividerColor,
    required this.focused,
    required this.primary,
    required this.labelColor,
    required this.label,
    required this.floating,
  });

  final Color dividerColor;
  final bool focused;
  final Color primary;
  final Color labelColor;
  final String label;
  final bool floating;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = focused ? primary : dividerColor
        ..strokeWidth = focused ? 2 : 1,
    );
    if (floating) {
      TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: OgMd1Type.caption, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset.zero);
    }
  }

  @override
  bool shouldRepaint(_OgMd1TextFieldPainter oldDelegate) =>
      oldDelegate.dividerColor != dividerColor ||
      oldDelegate.focused != focused ||
      oldDelegate.primary != primary ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.label != label ||
      oldDelegate.floating != floating;
}

/// MD1 经典输入框：48dp 高、底边 1px（focus 2px primary）、label 浮动 12sp。
///
/// 键盘走 [RawKeyboardListener] + [Focus]：可打印字符追加、Backspace 删除、
/// 方向键移动插入点；[Semantics] 暴露 textField / value。
class OgMd1TextField extends StatefulWidget {
  /// 创建输入框。
  const OgMd1TextField({
    required this.label,
    this.controller,
    this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    super.key,
  });

  /// 字段标签（浮动态 12sp）。
  final String label;

  /// 可选的文本控制器（调用方可读取/预置文本）。
  final TextEditingController? controller;

  /// 文本变化回调。
  final ValueChanged<String>? onChanged;

  /// 是否可编辑。
  final bool enabled;

  /// 是否以圆点遮蔽输入（密码场景）。
  final bool obscureText;

  @override
  State<OgMd1TextField> createState() => _OgMd1TextFieldState();
}

class _OgMd1TextFieldState extends State<OgMd1TextField> {
  late final FocusNode _focusNode = FocusNode();
  late final FocusNode _keyboardNode = FocusNode();
  late TextEditingController _controller;
  bool _ownsController = false;
  bool _focused = false;
  int _caret = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _caret = _controller.text.length;
    _focusNode.addListener(_onFocus);
  }

  void _onFocus() {
    if (!mounted || _focused == _focusNode.hasFocus) {
      return;
    }
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void didUpdateWidget(covariant OgMd1TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == oldWidget.controller) {
      return;
    }
    _focusNode.removeListener(_onFocus);
    if (_ownsController) {
      _controller.dispose();
    }
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _caret = _controller.text.length;
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    _keyboardNode.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  String get _visibleText =>
      widget.obscureText ? '•' * _controller.text.length : _controller.text;

  void _emit() {
    if (widget.onChanged != null) {
      widget.onChanged!(_controller.text);
    }
  }

  void _replaceText(String text, int caret) {
    _controller.value = _controller.value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _emit();
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || !widget.enabled) {
      return;
    }
    final String text = _controller.text;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      if (_caret > 0) {
        _replaceText(
          text.substring(0, _caret - 1) + text.substring(_caret),
          _caret - 1,
        );
      }
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _caret = _caret > 0 ? _caret - 1 : 0);
      return;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _caret = _caret < text.length ? _caret + 1 : text.length);
      return;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _caret = 0);
      return;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => _caret = text.length);
      return;
    }
    final String character = event.character ?? '';
    if (character.isNotEmpty &&
        !event.isControlKey &&
        !event.isMetaKey &&
        !event.isAltKey) {
      _replaceText(
        text.substring(0, _caret) + character + text.substring(_caret),
        _caret + character.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool floating = _focused || _controller.text.isNotEmpty;
    final Color labelColor = _focused
        ? palette.primary
        : (widget.enabled ? palette.textSecondary : palette.divider);
    final String visible = _visibleText;
    final int visibleCaret = widget.obscureText ? visible.length : _caret;
    final TextStyle valueStyle = TextStyle(
      fontSize: OgMd1Type.subhead,
      fontWeight: OgMd1Type.bodyWeight,
      color: widget.enabled ? palette.textPrimary : palette.textSecondary,
    );
    return Semantics(
      textField: true,
      label: widget.label,
      value: _controller.text,
      enabled: widget.enabled,
      child: GestureDetector(
        onTap: widget.enabled ? () => _focusNode.requestFocus() : null,
        behavior: HitTestBehavior.opaque,
        child: Focus(
          focusNode: _focusNode,
          child: RawKeyboardListener(
            focusNode: _keyboardNode,
            onKey: _onKey,
            child: SizedBox(
              height: OgMd1Size.field,
              child: CustomPaint(
                painter: _OgMd1TextFieldPainter(
                  dividerColor: palette.divider,
                  focused: _focused && widget.enabled,
                  primary: palette.primary,
                  labelColor: labelColor,
                  label: widget.label,
                  floating: floating,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    if (floating)
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: OgMd1Type.caption,
                          color: labelColor,
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: OgMd1Type.caption),
                        child: Text(
                          visible.substring(0, visibleCaret),
                          style: valueStyle,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch 外观 painter：MD1 经典轨道 + 圆钮，激活态 accent。
class _OgMd1SwitchPainter extends CustomPainter {
  const _OgMd1SwitchPainter({
    required this.trackColor,
    required this.thumbColor,
    required this.on,
  });

  final Color trackColor;
  final Color thumbColor;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final double trackHeight = size.height / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            0, (size.height - trackHeight) / 2, size.width, trackHeight),
        Radius.circular(trackHeight / 2),
      ),
      Paint()..color = trackColor,
    );
    final double radius = size.height * 0.4;
    canvas.drawCircle(
      Offset(on ? size.width - radius : radius, size.height / 2),
      radius,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_OgMd1SwitchPainter oldDelegate) =>
      oldDelegate.trackColor != trackColor ||
      oldDelegate.thumbColor != thumbColor ||
      oldDelegate.on != on;
}

/// MD1 经典开关：轨道 + 圆钮（accent 激活），触控目标 48dp。
class OgMd1Switch extends StatelessWidget {
  /// 创建开关。
  const OgMd1Switch({
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });

  /// 是否开启。
  final bool value;

  /// 状态切换回调；null 表示禁用。
  final ValueChanged<bool>? onChanged;

  /// 无障碍标签（可选）。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool enabled = onChanged != null;
    final Color track = value
        ? palette.accent.withValues(alpha: 0.5)
        : palette.divider.withValues(alpha: enabled ? 1 : 0.5);
    final Color thumb =
        value ? palette.accent : (enabled ? palette.card : palette.divider);
    return Semantics(
      switch_: true,
      checked: value,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: OgMd1Size.touchTarget,
          height: OgMd1Size.touchTarget,
          child: CustomPaint(
            painter: _OgMd1SwitchPainter(
              trackColor: track,
              thumbColor: thumb,
              on: value,
            ),
          ),
        ),
      ),
    );
  }
}

/// Checkbox 外观 painter：18dp 方框 + 自绘勾选路径。
class _OgMd1CheckboxPainter extends CustomPainter {
  const _OgMd1CheckboxPainter({
    required this.color,
    required this.checked,
    required this.borderColor,
  });

  final Color color;
  final bool checked;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(OgMd1Size.radius),
      ),
      Paint()
        ..color = checked ? color : borderColor
        ..style = checked ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (checked) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.25, size.height * 0.52)
          ..lineTo(size.width * 0.43, size.height * 0.7)
          ..lineTo(size.width * 0.76, size.height * 0.3),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_OgMd1CheckboxPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.checked != checked ||
      oldDelegate.borderColor != borderColor;
}

/// MD1 复选框：18dp 方框、勾选路径自绘，触控目标 48dp。
class OgMd1Checkbox extends StatelessWidget {
  /// 创建复选框。
  const OgMd1Checkbox({
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });

  /// 是否勾选。
  final bool value;

  /// 切换回调；null 表示禁用。
  final ValueChanged<bool>? onChanged;

  /// 右侧文字（可选，14sp 正文）。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool enabled = onChanged != null;
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: OgMd1Size.touchTarget,
          height: OgMd1Size.touchTarget,
          child: CustomPaint(
            size: const Size(
              OgMd1Type.subhead + OgMd1Type.overline,
              OgMd1Type.subhead + OgMd1Type.overline,
            ),
            painter: _OgMd1CheckboxPainter(
              color: enabled ? palette.accent : palette.divider,
              checked: value,
              borderColor: enabled
                  ? palette.textSecondary
                  : palette.divider.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (label != null)
          Text(
            label!,
            style: TextStyle(
              fontSize: OgMd1Type.body,
              color: enabled ? palette.textPrimary : palette.textSecondary,
            ),
          ),
      ],
    );
    return Semantics(
      checkbox: true,
      checked: value,
      enabled: enabled,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}

/// Radio 外观 painter：20dp 圆环 + 实心点。
class _OgMd1RadioPainter extends CustomPainter {
  const _OgMd1RadioPainter({
    required this.color,
    required this.selected,
    required this.borderColor,
  });

  final Color color;
  final bool selected;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      size.width / 2 - 1,
      Paint()
        ..color = selected ? color : borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (selected) {
      canvas.drawCircle(center, size.width / 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_OgMd1RadioPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.borderColor != borderColor;
}

/// MD1 单选按钮：20dp 圆环 + 实心点（accent 选中），触控目标 48dp。
class OgMd1Radio extends StatelessWidget {
  /// 创建单选按钮。
  const OgMd1Radio({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
    super.key,
  });

  /// 本项的值。
  final Object value;

  /// 当前组选中的值。
  final Object? groupValue;

  /// 选中回调；null 表示禁用。
  final ValueChanged<Object>? onChanged;

  /// 右侧文字（可选，14sp 正文）。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool selected = value == groupValue;
    final bool enabled = onChanged != null;
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: OgMd1Size.touchTarget,
          height: OgMd1Size.touchTarget,
          child: CustomPaint(
            size: const Size(OgMd1Size.listLeading, OgMd1Size.listLeading),
            painter: _OgMd1RadioPainter(
              color: enabled ? palette.accent : palette.divider,
              selected: selected,
              borderColor: enabled
                  ? palette.textSecondary
                  : palette.divider.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (label != null)
          Text(
            label!,
            style: TextStyle(
              fontSize: OgMd1Type.body,
              color: enabled ? palette.textPrimary : palette.textSecondary,
            ),
          ),
      ],
    );
    return Semantics(
      radio: true,
      checked: selected,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled && !selected ? () => onChanged!(value) : null,
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}

/// Slider 外观 painter：轨道 + 已选段 + 拇指（MD1 accent）。
class _OgMd1SliderPainter extends CustomPainter {
  const _OgMd1SliderPainter({
    required this.inactive,
    required this.active,
    required this.thumb,
    required this.progress,
  });

  final Color inactive;
  final Color active;
  final Color thumb;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final double end = size.width * progress;
    final Paint track = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(0, y), Offset(size.width, y), track..color = inactive);
    if (progress > 0) {
      canvas.drawLine(Offset(0, y), Offset(end, y), track..color = active);
    }
    canvas.drawCircle(Offset(end, y), OgMd1Type.body, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_OgMd1SliderPainter oldDelegate) =>
      oldDelegate.inactive != inactive ||
      oldDelegate.active != active ||
      oldDelegate.thumb != thumb ||
      oldDelegate.progress != progress;
}

/// MD1 滑块：轨道 + 拇指（accent），拖动/点击/键盘可调，触控目标 48dp。
class OgMd1Slider extends StatefulWidget {
  /// 创建滑块。
  const OgMd1Slider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.label,
    super.key,
  });

  /// 当前值（须在 [min] 与 [max] 之间）。
  final double value;

  /// 数值变化回调；null 表示禁用。
  final ValueChanged<double>? onChanged;

  /// 最小值（默认 0）。
  final double min;

  /// 最大值（默认 1，须大于 [min]）。
  final double max;

  /// 无障碍标签（可选）。
  final String? label;

  @override
  State<OgMd1Slider> createState() => _OgMd1SliderState();
}

class _OgMd1SliderState extends State<OgMd1Slider> {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _keyboardNode = FocusNode();
  final GlobalKey _boxKey = GlobalKey();

  double get _progress {
    final double span = widget.max - widget.min;
    if (span <= 0) {
      return 0;
    }
    return ((widget.value - widget.min) / span).clamp(0.0, 1.0);
  }

  void _emitProgress(double progress) {
    final double clamped = progress.clamp(0.0, 1.0);
    widget.onChanged!(widget.min + clamped * (widget.max - widget.min));
  }

  double _localDx(double globalDx) {
    final RenderBox? box =
        _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return 0;
    }
    return globalDx - box.localToGlobal(Offset.zero).dx;
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onChanged == null) {
      return;
    }
    final RenderBox? box =
        _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) {
      return;
    }
    _emitProgress(details.localPosition.dx / box.size.width);
  }

  void _onDrag(DragUpdateDetails details) {
    if (widget.onChanged == null) {
      return;
    }
    final RenderBox? box =
        _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) {
      return;
    }
    _emitProgress(_localDx(details.globalPosition.dx) / box.size.width);
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || widget.onChanged == null) {
      return;
    }
    final double span = widget.max - widget.min;
    if (span <= 0) {
      return;
    }
    final double step = 1 / OgMd1Type.display;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      _emitProgress(_progress - step);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      _emitProgress(_progress + step);
    } else if (key == LogicalKeyboardKey.home) {
      _emitProgress(0);
    } else if (key == LogicalKeyboardKey.end) {
      _emitProgress(1);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _keyboardNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool enabled = widget.onChanged != null;
    return Semantics(
      slider: true,
      value: widget.value.toStringAsFixed(OgMd1Type.overline.toInt()),
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onHorizontalDragUpdate: _onDrag,
        behavior: HitTestBehavior.opaque,
        child: Focus(
          focusNode: _focusNode,
          child: RawKeyboardListener(
            focusNode: _keyboardNode,
            onKey: _onKey,
            child: SizedBox(
              key: _boxKey,
              height: OgMd1Size.touchTarget,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: OgMd1Type.body),
                child: CustomPaint(
                  painter: _OgMd1SliderPainter(
                    inactive: enabled
                        ? palette.divider
                        : palette.divider.withValues(alpha: 0.5),
                    active: enabled ? palette.accent : palette.divider,
                    thumb: enabled ? palette.accent : palette.divider,
                    progress: _progress,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 批 3：反馈类五控件（Dialog / Snackbar / Chip / Badge / Divider）
// ─────────────────────────────────────────────────────────────────────────────

/// 单个对话框动作：文案 + 回调（文案由调用方本地化后传入）。
@immutable
class OgMd1DialogAction {
  /// 创建动作。
  const OgMd1DialogAction({required this.label, this.onPressed});

  /// 按钮文案。
  final String label;

  /// 点击回调；null 时按钮禁用。
  final VoidCallback? onPressed;
}

/// 对话框外观 painter：card 底 + 2dp 圆角 + elevation24 真投影。
class _OgMd1DialogPainter extends CustomPainter {
  const _OgMd1DialogPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    _paintShadows(canvas, shape, OgMd1Elevation.dp24);
    canvas.drawRRect(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1DialogPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 对话框内的自绘 flat 按钮：36dp 高、2dp 圆角、primary 大写文字。
class _OgMd1DialogActionButton extends StatelessWidget {
  const _OgMd1DialogActionButton({required this.action, required this.palette});

  final OgMd1DialogAction action;
  final OgMd1Colors palette;

  @override
  Widget build(BuildContext context) {
    final bool enabled = action.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: action.label,
      child: GestureDetector(
        onTap: action.onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: OgMd1Size.buttonHeight,
          child: CustomPaint(
            painter: _OgMd1ActionPainter(
              pressed: enabled,
              color: enabled ? palette.primary : palette.divider,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OgMd1Size.buttonPadding,
              ),
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: OgMd1Type.button,
                  fontWeight: OgMd1Type.buttonWeight,
                  color: enabled ? palette.primary : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 动作按钮的极简底（透明；仅按压态给一层 2dp 圆角提示）。
class _OgMd1ActionPainter extends CustomPainter {
  const _OgMd1ActionPainter({required this.pressed, required this.color});

  final bool pressed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!pressed) {
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(OgMd1Size.radius),
      ),
      Paint()..color = color.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_OgMd1ActionPainter oldDelegate) =>
      oldDelegate.pressed != pressed || oldDelegate.color != color;
}

/// MD1 经典对话框：2dp 圆角、elevation24、宽 ≥280dp、标题 + 内容 + 动作区。
///
/// 本控件是**内容外壳**（不含模态遮罩与路由），调用方把它放进
/// `PopupRoute`/`Navigator` 即可；内部所有可见外观均由 CustomPainter 绘制。
class OgMd1Dialog extends StatelessWidget {
  /// 创建对话框。
  const OgMd1Dialog({
    this.title,
    required this.content,
    this.actions = const <OgMd1DialogAction>[],
    super.key,
  });

  /// 标题（20sp，可选）。
  final String? title;

  /// 正文内容（14sp）。
  final String content;

  /// 动作按钮（最多通常 2–3 个；末尾按钮靠右排列）。
  final List<OgMd1DialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    return Semantics(
      explicitChildNodes: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: OgMd1Size.dialogMinWidth),
        child: CustomPaint(
          painter: _OgMd1DialogPainter(color: palette.card),
          child: Padding(
            padding: const EdgeInsets.all(_md1DialogPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: _md1DialogGap),
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontSize: OgMd1Type.title,
                        fontWeight: OgMd1Type.titleWeight,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: OgMd1Type.body,
                    fontWeight: OgMd1Type.bodyWeight,
                    color: palette.textSecondary,
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: _md1DialogGap),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        for (int i = 0; i < actions.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: _md1DialogActionGap),
                          _OgMd1DialogActionButton(
                            action: actions[i],
                            palette: palette,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Snackbar 外观 painter：深色底 + 2dp 圆角 + elevation6 + 1px 描边。
class _OgMd1SnackbarPainter extends CustomPainter {
  const _OgMd1SnackbarPainter({
    required this.color,
    required this.border,
  });

  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    _paintShadows(canvas, shape, OgMd1Elevation.dp6);
    canvas.drawRRect(shape, Paint()..color = color);
    canvas.drawRRect(
      shape.deflate(_md1DividerPx / 2),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = _md1DividerPx,
    );
  }

  @override
  bool shouldRepaint(_OgMd1SnackbarPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.border != border;
}

/// Snackbar 动作按钮（自绘透明底 + primary/accent 文字，≥48dp 触控）。
class _OgMd1SnackbarActionButton extends StatelessWidget {
  const _OgMd1SnackbarActionButton({
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OgMd1Size.buttonPadding,
          ),
          child: SizedBox(
            height: OgMd1Size.touchTarget,
            child: Text(
              label,
              style: TextStyle(
                fontSize: OgMd1Type.button,
                fontWeight: OgMd1Type.buttonWeight,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// MD1 底部 Snackbar：深色条 + 动作按钮 + 时长。
///
/// [duration] 到点触发 [onDismissed]（外部据此移除本控件）；
/// [actionLabel] / [onAction] 同时给出时显示动作按钮，点击后先执行动作再Dismiss。
class OgMd1Snackbar extends StatefulWidget {
  /// 创建 Snackbar。
  const OgMd1Snackbar({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismissed,
    this.duration = const Duration(seconds: 4), // Timer( 展示时长（等待非动画）

    super.key,
  });

  /// 消息文本。
  final String message;

  /// 动作文案（可选）。
  final String? actionLabel;

  /// 动作回调（与 [actionLabel] 配套）。
  final VoidCallback? onAction;

  /// 显示时长到点 / 动作点击后的回收回调。
  final VoidCallback? onDismissed;

  /// 显示时长（默认 4s，MD1 常规提示时长）。
  final Duration duration;

  @override
  State<OgMd1Snackbar> createState() => _OgMd1SnackbarState();
}

class _OgMd1SnackbarState extends State<OgMd1Snackbar> {
  Timer? _timer;

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    widget.onDismissed?.call();
  }

  void _onActionTap() {
    widget.onAction?.call();
    _dismiss();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void didUpdateWidget(OgMd1Snackbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _timer?.cancel();
      _timer = Timer(widget.duration, _dismiss);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool hasAction =
        widget.actionLabel != null && widget.onAction != null;
    return Semantics(
      liveRegion: true,
      label: widget.message,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _md1SnackbarPadding,
          vertical: _md1SnackbarPadding / OgMd1Size.radius,
        ),
        child: CustomPaint(
          painter: _OgMd1SnackbarPainter(
            color: palette.primaryDark,
            border: palette.divider.withValues(alpha: 0.35),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _md1SnackbarHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _md1SnackbarPadding,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: OgMd1Type.body,
                        fontWeight: OgMd1Type.bodyWeight,
                        color: palette.onPrimary,
                      ),
                    ),
                  ),
                  if (hasAction)
                    _OgMd1SnackbarActionButton(
                      label: widget.actionLabel!,
                      onPressed: _onActionTap,
                      color: palette.accent,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip 外观 painter：2dp 圆角、填充底 + 1px 描边、可选删除叉自绘。
class _OgMd1ChipPainter extends CustomPainter {
  const _OgMd1ChipPainter({
    required this.fill,
    required this.border,
    required this.deleteColor,
    required this.deletable,
  });

  final Color fill;
  final Color border;
  final Color deleteColor;
  final bool deletable;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    canvas.drawRRect(shape, Paint()..color = fill);
    canvas.drawRRect(
      shape.deflate(_md1DividerPx / 2),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = _md1DividerPx,
    );
    if (deletable) {
      final Offset center =
          Offset(size.width - OgMd1Size.buttonPadding, size.height / 2);
      final double arm = _md1BadgeDot / OgMd1Size.radius;
      final Paint cross = Paint()
        ..color = deleteColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _md1DividerPx
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + Offset(-arm, -arm),
        center + Offset(arm, arm),
        cross,
      );
      canvas.drawLine(
        center + Offset(arm, -arm),
        center + Offset(-arm, arm),
        cross,
      );
    }
  }

  @override
  bool shouldRepaint(_OgMd1ChipPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.border != border ||
      oldDelegate.deleteColor != deleteColor ||
      oldDelegate.deletable != deletable;
}

/// MD1 Chip：18–32dp 高、2dp 圆角、可选删除按钮。
///
/// [label] 由调用方本地化；[onDeleted] 非空时右侧显示自绘删除叉，
/// 点按删除区触发 [onDeleted]，点按其它区域触发 [onTap]。
class OgMd1Chip extends StatelessWidget {
  /// 创建 Chip。
  const OgMd1Chip({
    required this.label,
    this.onTap,
    this.onDeleted,
    super.key,
  });

  /// 文案。
  final String label;

  /// 主体点按回调（可选）。
  final VoidCallback? onTap;

  /// 删除回调；非空时显示删除叉。
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool deletable = onDeleted != null;
    // 删除叉中心距右边缘 16dp（与 painter 的 center 计算一致）。
    final Widget label = Text(
      label,
      style: TextStyle(
        fontSize: OgMd1Type.body,
        fontWeight: OgMd1Type.bodyWeight,
        color: palette.textPrimary,
      ),
    );
    final Widget inner = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        label,
        if (deletable) const SizedBox(width: OgMd1Size.buttonPadding),
      ],
    );
    return Semantics(
      chip: true,
      enabled: onTap != null || deletable,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _md1ChipHeightMin,
            maxHeight: _md1ChipHeightMax,
          ),
          child: CustomPaint(
            painter: _OgMd1ChipPainter(
              fill: palette.divider.withValues(alpha: 0.22),
              border: palette.divider,
              deleteColor: palette.textSecondary,
              deletable: deletable,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _md1ChipPadding,
                vertical: _md1ChipPadding / OgMd1Size.radius,
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  inner,
                  if (deletable)
                    Positioned(
                      right: -_md1ChipPadding,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: onDeleted,
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox(
                            width: OgMd1Size.touchTarget / 2,
                            height: OgMd1Size.touchTarget,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge 外观 painter：红点 / 数字角标（accent 色，优先于主题 primary）。
class _OgMd1BadgePainter extends CustomPainter {
  const _OgMd1BadgePainter({
    required this.color,
    required this.textColor,
    required this.isDot,
    required this.count,
  });

  final Color color;
  final Color textColor;
  final bool isDot;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    if (isDot) {
      // 红点：正圆，直径取短边。
      final double radius =
          math.min(size.width, size.height) / OgMd1Size.radius;
      canvas.drawCircle(
        Offset(size.width / OgMd1Size.radius, size.height / OgMd1Size.radius),
        radius,
        fill,
      );
      return;
    }
    final RRect shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    canvas.drawRRect(shape, fill);
    final String text = count > 99 ? '99+' : count.toString();
    final TextPainter label = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: OgMd1Type.caption,
          fontWeight: OgMd1Type.buttonWeight,
          color: textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(
        (size.width - label.width) / OgMd1Size.radius,
        (size.height - label.height) / OgMd1Size.radius,
      ),
    );
  }

  @override
  bool shouldRepaint(_OgMd1BadgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.textColor != textColor ||
      oldDelegate.isDot != isDot ||
      oldDelegate.count != count;
}

/// MD1 Badge：红点 / 数字角标，可叠在任意 [child] 右上角。
///
/// [count] 为 null 表示红点；0 不绘制；≥1 显示数字（>99 显示 99+）。
class OgMd1Badge extends StatelessWidget {
  /// 创建角标。
  const OgMd1Badge({
    required this.child,
    this.count,
    this.label,
    super.key,
  });

  /// 被角标覆盖的控件。
  final Widget child;

  /// 数字；null = 红点，0 = 不显示。
  final int? count;

  /// 无障碍标签（可选，例如「3 条未读」）。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool dot = count == null;
    final bool visible = dot || count! > 0;
    final double width = dot ? _md1BadgeDot : _md1BadgeSize;
    return Semantics(
      label: label ?? (dot ? null : count.toString()),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          child,
          if (visible)
            Positioned(
              right: -_md1BadgeDot / 2,
              top: -_md1BadgeDot / 2,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(width, _md1BadgeSize),
                  painter: _OgMd1BadgePainter(
                    color: palette.accent,
                    textColor: palette.onPrimary,
                    isDot: dot,
                    count: count ?? 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Divider 外观 painter：1px 分割线（MD1 2014 #E0E0E0 / 暗色 #555555）。
class _OgMd1DividerPainter extends CustomPainter {
  const _OgMd1DividerPainter({required this.color, required this.indent});

  final Color color;
  final double indent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(
        indent,
        size.height - _md1DividerPx,
        size.width - indent,
        _md1DividerPx,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OgMd1DividerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.indent != indent;
}

/// MD1 1px 分割线：[height] 为占位高度（默认 1px），[indent] 为左缩进。
class OgMd1Divider extends StatelessWidget {
  /// 创建分割线。
  const OgMd1Divider({
    this.indent = 0,
    this.height = _md1DividerPx,
    super.key,
  });

  /// 左侧缩进（dp）。
  final double indent;

  /// 占位高度（dp），默认 1px。
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      divider: true,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _OgMd1DividerPainter(
            color: OgMd1Colors.of(context).divider,
            indent: indent,
          ),
        ),
      ),
    );
  }
}
