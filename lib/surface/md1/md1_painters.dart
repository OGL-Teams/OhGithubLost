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

import 'dart:math' as math;

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
        CrossAxisAlignment,
        CustomPaint,
        EdgeInsets,
        EdgeInsetsDirectional,
        Expanded,
        Focus,
        FocusNode,
        GestureDetector,
        GlobalKey,
        HitTestBehavior,
        Key,
        MainAxisSize,
        MainAxisAlignment,
        Padding,
        RawKeyboardListener,
        Row,
        Semantics,
        SingleTickerProviderStateMixin,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        TapDownDetails,
        DragUpdateDetails,
        Text,
        TextAlign,
        TextEditingController,
        TextOverflow,
        TextStyle,
        ValueChanged,
        VoidCallback,
        Widget,
        withValues;

import '../app/animations.dart' show OgLAnim;
import 'md1_tokens.dart' show OgMd1Colors, OgMd1Elevation, OgMd1Size, OgMd1Type;

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
    final double height = twoLines
        ? OgMd1Size.listRowDouble
        : OgMd1Size.listRowSingle;
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

  String get _visibleText => widget.obscureText
      ? '•' * _controller.text.length
      : _controller.text;

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
        Rect.fromLTWH(0, (size.height - trackHeight) / 2, size.width, trackHeight),
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
    final Color thumb = value
        ? palette.accent
        : (enabled ? palette.card : palette.divider);
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
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track..color = inactive);
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
    final RenderBox? box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return 0;
    }
    return globalDx - box.localToGlobal(Offset.zero).dx;
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onChanged == null) {
      return;
    }
    final RenderBox? box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) {
      return;
    }
    _emitProgress(details.localPosition.dx / box.size.width);
  }

  void _onDrag(DragUpdateDetails details) {
    if (widget.onChanged == null) {
      return;
    }
    final RenderBox? box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
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
