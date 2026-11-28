/// L3 展示级 · MD1 经典（2014）导航类五控件自绘外观（CustomPainter 层）。
///
/// ## 纪律
/// 本文件里的每个可见外观都由 [CustomPainter] 绘制；不使用任何 Material
/// 控件（ElevatedButton / TextButton / ListTile / Card / AppBar 等）。
/// 布局只用 Row / Column / Stack / Padding / SizedBox / GestureDetector / Text。
/// 色值 / 尺寸 / 字阶 / 阴影全部取 [md1_tokens.dart] 的令牌，零裸值。
///
/// ## 控件清单
/// 批 4（导航）：`OgMd1BottomNav` / `OgMd1TabBar` / `OgMd1Drawer` /
/// `OgMd1NavigationRail` / `OgMd1Toolbar`。
library;

import 'dart:async' show Timer;
import 'dart:math' as math;
import 'dart:ui' show Image, Path;

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
        Align,
        Alignment,
        AlignmentDirectional,
        AnimatedBuilder,
        Animation,
        AnimationController,
        AnimationStatus,
        BlendMode,
        BuildContext,
        Center,
        Clip,
        ClipRect,
        Colors,
        BoxConstraints,
        Canvas,
        Column,
        ConstrainedBox,
        CrossAxisAlignment,
        CustomPaint,
        CustomPainter,
        Directionality,
        DragStartDetails,
        DragUpdateDetails,
        Duration,
        EdgeInsets,
        EdgeInsetsDirectional,
        Expanded,
        FlutterError,
        Focus,
        FocusNode,
        GestureDetector,
        GlobalKey,
        HitTestBehavior,
        Icon,
        IconData,
        IgnorePointer,
        Key,
        MainAxisAlignment,
        MainAxisSize,
        MediaQuery,
        Navigator,
        NotificationListener,
        Offset,
        Padding,
        Paint,
        PaintingStyle,
        PopupRoute,
        Positioned,
        PositionedDirectional,
        Radius,
        RawKeyboardListener,
        Rect,
        RRect,
        RouteSettings,
        Row,
        ScrollController,
        ScrollNotification,
        Semantics,
        SingleTickerProviderStateMixin,
        Size,
        SizedBox,
        Stack,
        State,
        StatefulWidget,
        StrokeCap,
        StatelessWidget,
        TapDownDetails,
        Text,
        TextAlign,
        TextDirection,
        TextEditingController,
        TextOverflow,
        TextPainter,
        TextPosition,
        TextSpan,
        TextStyle,
        TickerProvider,
        ValueChanged,
        ValueNotifier,
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
// ── 基础控件 · 按钮 / 卡片 / 列表 / 波纹 / 应用栏 ──
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
// ── 表单控件 · 输入框 / 开关 / 复选 / 单选 / 滑杆 ──
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
          0,
          (size.height - trackHeight) / 2,
          size.width,
          trackHeight,
        ),
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
      Offset(0, y),
      Offset(size.width, y),
      track..color = inactive,
    );
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
// ── 反馈控件 · 对话框 / 提示条 / 徽章 / 分割线 ──
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
  const _OgMd1SnackbarPainter({required this.color, required this.border});

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
      final Offset center = Offset(
        size.width - OgMd1Size.buttonPadding,
        size.height / 2,
      );
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
  const OgMd1Chip({required this.label, this.onTap, this.onDeleted, super.key});

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
  const OgMd1Badge({required this.child, this.count, this.label, super.key});

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
  const OgMd1Divider({this.indent = 0, this.height = _md1DividerPx, super.key});

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

/// BottomNav 选中项 primary 指示条高度（MD1 2014 顶部 3dp）。
const double _md1NavIndicator = 3;

/// TabBar 2px 下划线（MD1 2014 写死规格）。
const double _md1TabUnderline = 2;

/// Drawer 面板宽度（MD1 2014 标准 240dp）。
const double _md1DrawerWidth = 240;

/// NavigationRail 选中项的 primary 竖条宽度（MD1 侧栏标识）。
const double _md1RailIndicator = 3;

/// ─────────────────────────────────────────────────────────────────────────
/// 批 4：导航类 5 控件（BottomNav / TabBar / Drawer / NavigationRail / Toolbar）
/// ─────────────────────────────────────────────────────────────────────────

/// BottomNav 项目描述（MD1 经典 3–5 tab；每项 ≥48dp 触控目标）。
@immutable
class OgMd1BottomNavItem {
  /// 创建导航项。
  const OgMd1BottomNavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    this.badge,
  });

  /// 文字标签（12sp caption，大写由调用方决定）。
  final String label;

  /// 图标数据（使用项目图标令牌，不直接写裸 Icons.*）。
  final IconData icon;

  /// 选中态图标（可选；不传则用 [icon]）。
  final IconData? activeIcon;

  /// 角标数字（可选；>0 时画红色小圆点）。
  final int? badge;
}

/// BottomNav 外观 painter：56dp 纯色底（card）+ 选中项 primary 指示条 + 1px 顶分割线。
class _OgMd1BottomNavPainter extends CustomPainter {
  const _OgMd1BottomNavPainter({
    required this.color,
    required this.dividerColor,
    required this.primary,
    required this.selected,
    required this.count,
  });

  final Color color;
  final Color dividerColor;
  final Color primary;
  final int selected;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final double indicatorWidth = size.width / count;
    final double indicatorHeight = _md1NavIndicator;
    canvas.drawRect(
      Rect.fromLTWH(
        selected * indicatorWidth,
        0,
        indicatorWidth,
        indicatorHeight,
      ),
      Paint()..color = primary,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, _md1DividerPx, size.width, _md1DividerPx),
      Paint()..color = dividerColor,
    );
  }

  @override
  bool shouldRepaint(_OgMd1BottomNavPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dividerColor != dividerColor ||
      oldDelegate.primary != primary ||
      oldDelegate.selected != selected ||
      oldDelegate.count != count;
}

/// MD1 BottomNav：56dp 纯色底 + 选中项 primary 指示条（3–5 tab）。
///
/// 每项是一个 56dp 高、宽度均分的触控目标，图标 24dp + 12sp 文字；
/// 键盘左右方向键在项间循环，Enter/Space 触发选择。
// ── 导航控件 · 底栏 / 标签 / 抽屉 / 侧栏 / 工具栏 ──
class OgMd1BottomNav extends StatefulWidget {
  /// 创建底部导航（约束 3–5 项）。
  const OgMd1BottomNav({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    super.key,
  }) : assert(
          items.length >= 3 && items.length <= 5,
          'MD1 BottomNav 经典规格为 3–5 个 tab',
        );

  /// 导航项列表。
  final List<OgMd1BottomNavItem> items;

  /// 当前选中序号。
  final int selectedIndex;

  /// 选择回调。
  final ValueChanged<int> onTap;

  @override
  State<OgMd1BottomNav> createState() => _OgMd1BottomNavState();
}

class _OgMd1BottomNavState extends State<OgMd1BottomNav> {
  late final FocusNode _keyboardNode = FocusNode();
  int? _highlight;

  @override
  void dispose() {
    _keyboardNode.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    widget.onTap(index);
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return;
    }
    final int count = widget.items.length;
    final int current = _highlight ?? widget.selectedIndex;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _highlight = (current - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _highlight = (current + 1) % count);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _select(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final List<Widget> tabs = <Widget>[];
    for (int i = 0; i < widget.items.length; i++) {
      final OgMd1BottomNavItem item = widget.items[i];
      final bool selected = i == widget.selectedIndex;
      final Widget content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            selected ? (item.activeIcon ?? item.icon) : item.icon,
            size: OgMd1Type.title,
            color: selected ? palette.primary : palette.textSecondary,
          ),
          Text(
            item.label,
            style: TextStyle(
              fontSize: OgMd1Type.caption,
              fontWeight:
                  selected ? OgMd1Type.buttonWeight : OgMd1Type.bodyWeight,
              color: selected ? palette.primary : palette.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
      tabs.add(
        Semantics(
          button: true,
          selected: selected,
          label: item.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(i),
            child: SizedBox(height: OgMd1Size.appBar, child: content),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      child: RawKeyboardListener(
        focusNode: _keyboardNode,
        onKey: _onKey,
        child: Focus(
          onFocusChange: (bool focused) {
            if (!focused && mounted) {
              setState(() => _highlight = null);
            }
          },
          child: SizedBox(
            height: OgMd1Size.appBar,
            child: CustomPaint(
              painter: _OgMd1BottomNavPainter(
                color: palette.card,
                dividerColor: palette.divider,
                primary: palette.primary,
                selected: widget.selectedIndex,
                count: widget.items.length,
              ),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(child: tabs[i]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 导航项描述：TabBar / NavigationRail 共用（图标 + 文字）。
@immutable
class OgMd1NavDestination {
  /// 创建导航目标。
  const OgMd1NavDestination({
    required this.label,
    required this.icon,
    this.activeIcon,
    this.badge,
  });

  /// 标签。
  final String label;

  /// 常态图标。
  final IconData icon;

  /// 选中态图标（可选）。
  final IconData? activeIcon;

  /// 角标数字（可选；>0 时画小红点）。
  final int? badge;
}

/// TabBar 外观 painter：48dp 底 + 2px primary 下划线。
class _OgMd1TabBarPainter extends CustomPainter {
  const _OgMd1TabBarPainter({
    required this.color,
    required this.dividerColor,
    required this.primary,
    required this.selected,
    required this.count,
    required this.offset,
  });

  final Color color;
  final Color dividerColor;
  final Color primary;
  final int selected;
  final int count;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final double tabWidth = size.width / count;
    final double left = selected * tabWidth - offset;
    canvas.drawRect(
      Rect.fromLTWH(
        left,
        size.height - _md1TabUnderline,
        tabWidth,
        _md1TabUnderline,
      ),
      Paint()..color = primary,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, _md1DividerPx, size.width, _md1DividerPx),
      Paint()..color = dividerColor,
    );
  }

  @override
  bool shouldRepaint(_OgMd1TabBarPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dividerColor != dividerColor ||
      oldDelegate.primary != primary ||
      oldDelegate.selected != selected ||
      oldDelegate.count != count ||
      oldDelegate.offset != offset;
}

/// MD1 TabBar：48dp 高、2px primary 下划线、选中项 primary 文字。
///
/// [scrollController] 可选：传入时按滚动像素移动下划线，实现跟手滑动。
class OgMd1TabBar extends StatefulWidget {
  /// 创建 TabBar。
  const OgMd1TabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    this.scrollController,
    super.key,
  });

  /// Tab 列表。
  final List<OgMd1NavDestination> destinations;

  /// 当前选中序号。
  final int selectedIndex;

  /// 选择回调。
  final ValueChanged<int> onTap;

  /// 可选滚动控制器（用于下划线跟随）。
  final ScrollController? scrollController;

  @override
  State<OgMd1TabBar> createState() => _OgMd1TabBarState();
}

class _OgMd1TabBarState extends State<OgMd1TabBar> {
  late final FocusNode _keyboardNode = FocusNode();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant OgMd1TabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
      _offset = 0;
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    _keyboardNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ScrollController? controller = widget.scrollController;
    if (controller == null || !controller.hasClients || !mounted) {
      return;
    }
    setState(() => _offset = controller.offset);
  }

  void _select(int index) {
    if (index < 0 || index >= widget.destinations.length) {
      return;
    }
    widget.onTap(index);
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return;
    }
    final int count = widget.destinations.length;
    final int current = widget.selectedIndex;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _select((current - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _select((current + 1) % count);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _select(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final List<Widget> tabs = <Widget>[];
    for (int i = 0; i < widget.destinations.length; i++) {
      final OgMd1NavDestination destination = widget.destinations[i];
      final bool selected = i == widget.selectedIndex;
      tabs.add(
        Semantics(
          selected: selected,
          label: destination.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(i),
            child: Center(
              child: Text(
                destination.label,
                style: TextStyle(
                  fontSize: OgMd1Type.body,
                  fontWeight:
                      selected ? OgMd1Type.buttonWeight : OgMd1Type.bodyWeight,
                  color: selected ? palette.primary : palette.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      child: RawKeyboardListener(
        focusNode: _keyboardNode,
        onKey: _onKey,
        child: Focus(
          child: SizedBox(
            height: OgMd1Size.tab,
            child: CustomPaint(
              painter: _OgMd1TabBarPainter(
                color: palette.card,
                dividerColor: palette.divider,
                primary: palette.primary,
                selected: widget.selectedIndex,
                count: widget.destinations.length,
                offset: _offset,
              ),
              child: Row(
                children: <Widget>[
                  for (final Widget tab in tabs) Expanded(child: tab),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 抽屉面板外观 painter：240dp 纯色 card + elevation 8 真投影（同心阶梯）。
class _OgMd1DrawerPanelPainter extends CustomPainter {
  const _OgMd1DrawerPanelPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.zero);
    _paintShadows(canvas, rect, OgMd1Elevation.dp8);
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1DrawerPanelPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 抽屉遮罩外观 painter：半透明黑（MD1 scrim），点按关闭。
class _OgMd1DrawerScrimPainter extends CustomPainter {
  const _OgMd1DrawerScrimPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, 0.32 * progress),
    );
  }

  @override
  bool shouldRepaint(_OgMd1DrawerScrimPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// MD1 Drawer：240dp 宽抽屉 + 半透明遮罩；内容由 [child] 提供。
///
/// 用 [AnimationController] 按 [OgLAnim] 档位驱动划入滑出；[onDismiss] 在
/// 点遮罩 / Escape 键时触发。Semantics 暴露 drawer 容器与关闭按钮。
class OgMd1Drawer extends StatefulWidget {
  /// 创建抽屉。
  const OgMd1Drawer({
    required this.child,
    required this.open,
    required this.onDismiss,
    super.key,
  });

  /// 抽屉内容。
  final Widget child;

  /// 是否展开。
  final bool open;

  /// 关闭回调（点遮罩 / Escape）。
  final VoidCallback onDismiss;

  @override
  State<OgMd1Drawer> createState() => _OgMd1DrawerState();
}

class _OgMd1DrawerState extends State<OgMd1Drawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FocusNode _keyboardNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: OgLAnim.shellDuration(context),
    );
    _controller.value = widget.open ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant OgMd1Drawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) {
      return;
    }
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _keyboardNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        widget.open) {
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double progress = Curves.easeOut.transform(_controller.value);
        if (progress <= 0) {
          return const SizedBox.shrink();
        }
        return Semantics(
          container: true,
          child: RawKeyboardListener(
            focusNode: _keyboardNode,
            onKey: _onKey,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDismiss,
                    child: Semantics(
                      button: true,
                      label: 'Close drawer',
                      child: CustomPaint(
                        painter: _OgMd1DrawerScrimPainter(progress: progress),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: -_md1DrawerWidth * (1 - progress),
                  top: 0,
                  bottom: 0,
                  width: _md1DrawerWidth,
                  child: Semantics(
                    container: true,
                    child: CustomPaint(
                      painter: _OgMd1DrawerPanelPainter(color: palette.card),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// NavigationRail 外观 painter：72dp 宽侧栏 + 选中项 primary 竖条（3dp）。
class _OgMd1NavigationRailPainter extends CustomPainter {
  const _OgMd1NavigationRailPainter({
    required this.color,
    required this.selectedColor,
    required this.selected,
    required this.count,
  });

  final Color color;
  final Color selectedColor;
  final int selected;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final double itemHeight = size.height / count;
    canvas.drawRect(
      Rect.fromLTWH(0, selected * itemHeight, _md1RailIndicator, itemHeight),
      Paint()..color = selectedColor,
    );
  }

  @override
  bool shouldRepaint(_OgMd1NavigationRailPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selectedColor != selectedColor ||
      oldDelegate.selected != selected ||
      oldDelegate.count != count;
}

/// MD1 NavigationRail：72dp 宽侧栏、选中项 primary 竖条、图标 + 12sp 标签。
class OgMd1NavigationRail extends StatefulWidget {
  /// 创建侧栏。
  const OgMd1NavigationRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    super.key,
  });

  /// 目标列表。
  final List<OgMd1NavDestination> destinations;

  /// 当前选中序号。
  final int selectedIndex;

  /// 选择回调。
  final ValueChanged<int> onTap;

  @override
  State<OgMd1NavigationRail> createState() => _OgMd1NavigationRailState();
}

class _OgMd1NavigationRailState extends State<OgMd1NavigationRail> {
  late final FocusNode _keyboardNode = FocusNode();

  @override
  void dispose() {
    _keyboardNode.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= widget.destinations.length) {
      return;
    }
    widget.onTap(index);
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return;
    }
    final int count = widget.destinations.length;
    final int current = widget.selectedIndex;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _select((current - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _select((current + 1) % count);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _select(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final List<Widget> items = <Widget>[];
    for (int i = 0; i < widget.destinations.length; i++) {
      final OgMd1NavDestination destination = widget.destinations[i];
      final bool selected = i == widget.selectedIndex;
      items.add(
        Semantics(
          button: true,
          selected: selected,
          label: destination.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(i),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  selected
                      ? (destination.activeIcon ?? destination.icon)
                      : destination.icon,
                  size: OgMd1Type.title,
                  color: selected ? palette.primary : palette.textSecondary,
                ),
                Text(
                  destination.label,
                  style: TextStyle(
                    fontSize: OgMd1Type.caption,
                    fontWeight: selected
                        ? OgMd1Type.buttonWeight
                        : OgMd1Type.bodyWeight,
                    color: selected ? palette.primary : palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      child: RawKeyboardListener(
        focusNode: _keyboardNode,
        onKey: _onKey,
        child: Focus(
          child: SizedBox(
            width: _md1RailWidth,
            child: CustomPaint(
              painter: _OgMd1NavigationRailPainter(
                color: palette.card,
                selectedColor: palette.primary,
                selected: widget.selectedIndex,
                count: widget.destinations.length,
              ),
              child: Column(
                children: <Widget>[
                  for (final Widget item in items) Expanded(child: item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Toolbar 操作项描述。
@immutable
class OgMd1ToolbarAction {
  /// 创建操作项。
  const OgMd1ToolbarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// 无障碍标签。
  final String label;

  /// 图标。
  final IconData icon;

  /// 点按回调。
  final VoidCallback onPressed;
}

/// Toolbar 外观 painter：56dp 纯 primary 底 + elevation 4 真投影。
class _OgMd1ToolbarPainter extends CustomPainter {
  const _OgMd1ToolbarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.zero);
    _paintShadows(canvas, rect, OgMd1Elevation.dp4);
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1ToolbarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// MD1 Toolbar：56dp 操作条（primary 底 + 标题 + 操作图标按钮）。
///
/// 每个操作为 48dp 触控目标；键盘 Enter/Space 触发首项，方向键切换焦点。
class OgMd1Toolbar extends StatefulWidget {
  /// 创建 Toolbar。
  const OgMd1Toolbar({
    required this.title,
    this.actions = const <OgMd1ToolbarAction>[],
    super.key,
  });

  /// 标题文字（20sp / onPrimary）。
  final String title;

  /// 操作项列表。
  final List<OgMd1ToolbarAction> actions;

  @override
  State<OgMd1Toolbar> createState() => _OgMd1ToolbarState();
}

class _OgMd1ToolbarState extends State<OgMd1Toolbar> {
  late final FocusNode _keyboardNode = FocusNode();
  int _activeAction = 0;

  @override
  void dispose() {
    _keyboardNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || widget.actions.isEmpty) {
      return;
    }
    final int count = widget.actions.length;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _activeAction = (_activeAction - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _activeAction = (_activeAction + 1) % count);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      widget.actions[_activeAction].onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final List<Widget> actionWidgets = <Widget>[];
    for (int i = 0; i < widget.actions.length; i++) {
      final OgMd1ToolbarAction action = widget.actions[i];
      actionWidgets.add(
        Semantics(
          button: true,
          label: action.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: action.onPressed,
            child: SizedBox(
              width: OgMd1Size.touchTarget,
              height: OgMd1Size.touchTarget,
              child: Icon(
                action.icon,
                size: OgMd1Type.title,
                color: i == _activeAction
                    ? palette.onPrimary
                    : palette.onPrimary.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      child: RawKeyboardListener(
        focusNode: _keyboardNode,
        onKey: _onKey,
        child: Focus(
          child: SizedBox(
            height: OgMd1Size.appBar,
            child: CustomPaint(
              painter: _OgMd1ToolbarPainter(color: palette.primary),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: OgMd1Size.buttonPadding,
                  end: OgMd1Size.radius,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: OgMd1Type.title,
                          fontWeight: OgMd1Type.titleWeight,
                          color: palette.onPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...actionWidgets,
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

// ─────────────────────────────────────────────────────────────────────────────
// 批 5：操作类五控件（Progress / RefreshIndicator / BottomSheet / Menu /
// Dropdown）——全部 CustomPainter 自绘，零 Material 可见控件。
// ─────────────────────────────────────────────────────────────────────────────

/// 进度指示器形态：线性条 / 环形圈（MD1 accent 色）。
enum OgMd1ProgressKind {
  /// 水平线性进度条。
  linear,

  /// 环形进度圈。
  circular,
}

/// 进度条高度：MD1 线性进度 4dp。
const double _md1ProgressTrack = OgMd1Size.radius * 2;

/// 环形进度圈直径 / 轨道宽度（MD1 规范）。
const double _md1ProgressCircle = OgMd1Size.touchTarget;
const double _md1ProgressCircleStroke = OgMd1Size.radius * 2;

/// 环形不确定态旋转一周的扫过角度（弧度）。
const double _md1ProgressArc = math.pi * 1.5;

/// 线性进度外观：card 走轨底 + accent 走条 + 2dp 圆角端头。
class _OgMd1LinearProgressPainter extends CustomPainter {
  const _OgMd1LinearProgressPainter({
    required this.progress,
    required this.active,
    required this.track,
    required this.determinate,
  });

  final double progress;
  final Color active;
  final Color track;
  final bool determinate;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint base = Paint()..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        0,
        size.width,
        size.height,
        const Radius.circular(OgMd1Size.radius),
      ),
      base..color = track,
    );
    final double left = determinate ? 0 : size.width * progress;
    final double right =
        determinate ? size.width * progress : left + size.width / 3;
    if (right <= 0 || left >= size.width) {
      return;
    }
    canvas.drawRRect(
      RRect.fromLTRBR(
        left,
        0,
        math.min(right, size.width),
        size.height,
        const Radius.circular(OgMd1Size.radius),
      ),
      base..color = active,
    );
  }

  @override
  bool shouldRepaint(_OgMd1LinearProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.determinate != determinate;
}

/// 环形进度外观：底圈 + accent 弧；不确定态为旋转的开口弧。
class _OgMd1CircularProgressPainter extends CustomPainter {
  const _OgMd1CircularProgressPainter({
    required this.progress,
    required this.active,
    required this.track,
    required this.determinate,
  });

  final double progress;
  final Color active;
  final Color track;
  final bool determinate;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius =
        math.min(size.width, size.height) / 2 - _md1ProgressCircleStroke / 2;
    if (radius <= 0) {
      return;
    }
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _md1ProgressCircleStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(center, radius, base..color = track);
    const double start = -math.pi / 2;
    final double sweep = determinate
        ? _md1ProgressArc * 2 * progress.clamp(0.0, 1.0)
        : _md1ProgressArc;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      base..color = active,
    );
  }

  @override
  bool shouldRepaint(_OgMd1CircularProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.determinate != determinate;
}

/// MD1 进度指示器：线性 / 环形，accent 色；[value] 为 null 表示不确定态。
///
/// 不确定态用 [AnimationController] 经 [OgLAnim] 档位时长驱动；档位 0
/// 静默停在起始角。Semantics 暴露 progressbar 与数值/标签。
// ── 操作控件 · 进度 / 下拉刷新 / 弹层 / 菜单 / 下拉框 ──
class OgMd1Progress extends StatefulWidget {
  /// 创建进度指示器。
  const OgMd1Progress({
    this.value,
    this.kind = OgMd1ProgressKind.linear,
    this.label,
    this.size = _md1ProgressCircle,
    super.key,
  });

  /// 0–1 的进度；null = 不确定态（循环动画）。
  final double? value;

  /// 线性 / 环形。
  final OgMd1ProgressKind kind;

  /// 无障碍标签（调用方本地化后传入）。
  final String? label;

  /// 环形圈直径（线性形态忽略）。
  final double size;

  @override
  State<OgMd1Progress> createState() => _OgMd1ProgressState();
}

class _OgMd1ProgressState extends State<OgMd1Progress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: OgLAnim.slow(context),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant OgMd1Progress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    } else if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool determinate = widget.value != null;
    final double progress =
        determinate ? widget.value!.clamp(0.0, 1.0) : _controller.value;
    final String? semanticValue =
        determinate ? '${(progress * 100).round()}%' : null;
    final Widget visual = AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double shown = determinate ? progress : _controller.value;
        if (widget.kind == OgMd1ProgressKind.circular) {
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _OgMd1CircularProgressPainter(
                progress: shown,
                active: palette.accent,
                track: palette.divider,
                determinate: determinate,
              ),
            ),
          );
        }
        return SizedBox(
          height: _md1ProgressTrack,
          child: CustomPaint(
            painter: _OgMd1LinearProgressPainter(
              progress: shown,
              active: palette.accent,
              track: palette.divider,
              determinate: determinate,
            ),
          ),
        );
      },
    );
    return Semantics(
      progressBar: true,
      value: semanticValue,
      label: widget.label,
      child: visual,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 下拉刷新圈：手势拉出 → 松手触发 → 圈旋转；自绘 arc + arrow。
// ─────────────────────────────────────────────────────────────────────────────

/// 下拉刷新触发位移（dp）。
const double _md1RefreshTrigger = OgMd1Size.touchTarget + OgMd1Type.body;

/// 下拉刷新最大位移（dp）。
const double _md1RefreshMaxPull = OgMd1Size.listRowDouble;

/// 刷新圈外观：accent 弧 + 下拉箭头，进度由拉动量决定。
class _OgMd1RefreshPainter extends CustomPainter {
  const _OgMd1RefreshPainter({
    required this.progress,
    required this.refreshing,
    required this.angle,
    required this.color,
  });

  final double progress;
  final bool refreshing;
  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius =
        math.min(size.width, size.height) / 2 - _md1ProgressCircleStroke;
    if (radius <= 0) {
      return;
    }
    final Rect box = Rect.fromCircle(center: center, radius: radius);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _md1ProgressCircleStroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: refreshing ? 1 : 0.4 + progress * 0.6);
    canvas.drawArc(box, 0, math.pi * 2, false, paint);
    canvas.drawArc(
      box,
      -math.pi / 2,
      refreshing ? _md1ProgressArc : _md1ProgressArc * progress,
      false,
      paint,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(refreshing ? angle : progress * math.pi);
    final double tip = radius * 0.55;
    final Paint arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _md1ProgressCircleStroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(Offset(0, -tip), Offset(0, tip), arrow);
    canvas.drawLine(Offset(0, tip), Offset(-tip / 2, tip / 2), arrow);
    canvas.drawLine(Offset(0, tip), Offset(tip / 2, tip / 2), arrow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OgMd1RefreshPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.refreshing != refreshing ||
      oldDelegate.angle != angle ||
      oldDelegate.color != color;
}

/// MD1 下拉刷新圈：包在可滚动内容外层；下拉超阈值松手触发 [onRefresh]。
///
/// 只消费竖直下拉手势（不拦截列表正常滚动）；圈与箭头均自绘，位置随拉动量
/// 变化，松手后按 [OgLAnim] 档位回弹。Semantics 暴露刷新动作与进行中状态。
class OgMd1RefreshIndicator extends StatefulWidget {
  /// 创建下拉刷新容器。
  const OgMd1RefreshIndicator({
    required this.child,
    required this.onRefresh,
    super.key,
  });

  /// 被包裹的可滚动内容。
  final Widget child;

  /// 下拉触发后的刷新回调（异步；完成时收起圈）。
  final Future<void> Function() onRefresh;

  @override
  State<OgMd1RefreshIndicator> createState() => _OgMd1RefreshIndicatorState();
}

class _OgMd1RefreshIndicatorState extends State<OgMd1RefreshIndicator>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _pull = ValueNotifier<double>(0);
  late final AnimationController _controller;
  bool _refreshing = false;
  double _startY = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: OgLAnim.shellDuration(context),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pull.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_refreshing) {
      return;
    }
    _startY = details.globalPosition.dy;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_refreshing) {
      return;
    }
    final double delta = details.globalPosition.dy - _startY;
    if (delta <= 0) {
      if (_pull.value != 0) {
        _pull.value = 0;
      }
      return;
    }
    _pull.value = (delta / _md1RefreshMaxPull).clamp(0.0, 1.0);
  }

  Future<void> _onVerticalDragEnd(_) async {
    if (_refreshing || _pull.value <= 0) {
      return;
    }
    if (_pull.value * _md1RefreshMaxPull < _md1RefreshTrigger) {
      _controller.forward(from: _pull.value);
      _pull.value = 0;
      return;
    }
    setState(() => _refreshing = true);
    _controller.value = 0;
    _controller.repeat();
    try {
      await widget.onRefresh();
    } finally {
      if (!mounted) {
        return;
      }
      _controller.stop();
      _controller.reset();
      _pull.value = 0;
      setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    return Semantics(
      container: true,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
            ),
          ),
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_controller, _pull]),
              builder: (BuildContext context, Widget? child) {
                final double shown =
                    _refreshing ? 1 : _pull.value * (1 - _controller.value);
                if (shown <= 0) {
                  return const SizedBox.shrink();
                }
                return Semantics(
                  button: true,
                  enabled: !_refreshing,
                  label: _refreshing ? 'Refreshing' : 'Pull to refresh',
                  child: SizedBox(
                    height: _md1RefreshMaxPull * shown,
                    child: Center(
                      child: SizedBox(
                        width: _md1ProgressCircle,
                        height: _md1ProgressCircle,
                        child: CustomPaint(
                          painter: _OgMd1RefreshPainter(
                            progress: _pull.value,
                            refreshing: _refreshing,
                            angle: _controller.value * math.pi * 2,
                            color: palette.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 底部弹层：2dp 圆角、elevation 近似 16dp（两档 8dp 叠加），遮罩 + 下滑关闭。
// ─────────────────────────────────────────────────────────────────────────────

/// BottomSheet 面板外观：card 底 + 2dp 圆角 + 16dp 层级投影。
class _OgMd1BottomSheetPainter extends CustomPainter {
  const _OgMd1BottomSheetPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect shape = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: const Radius.circular(OgMd1Size.radius),
      topRight: const Radius.circular(OgMd1Size.radius),
    );
    // 16dp = 两档 8dp 叠加；不用 MaskFilter / saveLayer。
    _paintShadows(canvas, shape, <BoxShadow>[
      ...OgMd1Elevation.dp8,
      ...OgMd1Elevation.dp8,
    ]);
    canvas.drawRRect(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1BottomSheetPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// BottomSheet 遮罩：半透明黑，点按关闭。
class _OgMd1SheetScrimPainter extends CustomPainter {
  const _OgMd1SheetScrimPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(0, 0, 0, 0.32 * progress),
    );
  }

  @override
  bool shouldRepaint(_OgMd1SheetScrimPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// MD1 底部弹层：从底部升起，2dp 圆角 / elevation16，遮罩 + 下滑 / Escape 关闭。
///
/// [open] 由调用方控制；[onDismiss] 在遮罩点击、下拉越过阈值或 Escape 时触发。
/// 动画时长 / 曲线来自 [OgLAnim]，内容由 [child] 提供，全部可见外观自绘。
class OgMd1BottomSheet extends StatefulWidget {
  /// 创建底部弹层。
  const OgMd1BottomSheet({
    required this.child,
    required this.open,
    required this.onDismiss,
    super.key,
  });

  /// 面板内容。
  final Widget child;

  /// 是否展开。
  final bool open;

  /// 关闭回调。
  final VoidCallback onDismiss;

  @override
  State<OgMd1BottomSheet> createState() => _OgMd1BottomSheetState();
}

class _OgMd1BottomSheetState extends State<OgMd1BottomSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final FocusNode _keyboardNode = FocusNode();
  double _dragDown = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: OgLAnim.sheetDuration(context),
    );
    _controller.value = widget.open ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant OgMd1BottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) {
      return;
    }
    _dragDown = 0;
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _keyboardNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        widget.open) {
      widget.onDismiss();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta == null) {
      return;
    }
    setState(() {
      _dragDown = (_dragDown + details.primaryDelta!).clamp(
        0.0,
        _md1RefreshMaxPull.toDouble(),
      );
    });
  }

  void _onDragEnd(_) {
    if (_dragDown >= _md1RefreshTrigger) {
      _dragDown = 0;
      widget.onDismiss();
      return;
    }
    setState(() => _dragDown = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && !_controller.isAnimating) {
      return const SizedBox.shrink();
    }
    final OgMd1Colors palette = OgMd1Colors.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final Curve curve = OgLAnim.largeCurve(context);
        final double progress = curve.transform(_controller.value);
        // 入场/退场时面板按屏幕高度滑入滑出；拖动关闭时叠加下拉位移。
        final double slide = (1 - progress) * MediaQuery.sizeOf(context).height;
        return Semantics(
          container: true,
          child: RawKeyboardListener(
            focusNode: _keyboardNode,
            onKey: _onKey,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDismiss,
                    child: Semantics(
                      button: true,
                      label: 'Close sheet',
                      child: CustomPaint(
                        painter: _OgMd1SheetScrimPainter(progress: progress),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -slide - _dragDown,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _md1RefreshMaxPull * 4,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: _onDragUpdate,
                      onVerticalDragEnd: _onDragEnd,
                      child: Semantics(
                        container: true,
                        child: CustomPaint(
                          painter: _OgMd1BottomSheetPainter(
                            color: palette.card,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 弹出菜单 + 遮罩：菜单项自绘、选中态高亮，键盘 / 语义完整。
// ─────────────────────────────────────────────────────────────────────────────

/// 菜单项数据：文案（本地化后传入）+ 可选回调。
@immutable
class OgMd1MenuItem {
  /// 创建菜单项。
  const OgMd1MenuItem({required this.label, this.onSelected});

  /// 显示文案。
  final String label;

  /// 选中回调；null 表示禁用。
  final ValueChanged<int>? onSelected;
}

/// 菜单面板外观：card 底 + 2dp 圆角 + elevation8 真投影（同心阶梯）。
class _OgMd1MenuPainter extends CustomPainter {
  const _OgMd1MenuPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(OgMd1Size.radius),
    );
    _paintShadows(canvas, shape, OgMd1Elevation.dp8);
    canvas.drawRRect(shape, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OgMd1MenuPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 单个菜单项外观：48dp 触控高 + 按压 / 聚焦浅底。
class _OgMd1MenuItemPainter extends CustomPainter {
  const _OgMd1MenuItemPainter({required this.highlight, required this.enabled});

  final bool highlight;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (!highlight || !enabled) {
      return;
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x14000000),
    );
  }

  @override
  bool shouldRepaint(_OgMd1MenuItemPainter oldDelegate) =>
      oldDelegate.highlight != highlight || oldDelegate.enabled != enabled;
}

/// MD1 弹出菜单：贴在 [anchor] 下方的 card 面板 + 全屏透明遮罩。
///
/// [open] 控制显隐，点击遮罩 / 菜单项 / Escape 均关闭。菜单项逐行 48dp，
/// 每项有 Semantics button 与 Focus 节点；上下键移动焦点、Enter 选中。
/// 面板外观全部 CustomPainter 自绘。
class OgMd1Menu extends StatefulWidget {
  /// 创建弹出菜单。
  const OgMd1Menu({
    required this.anchor,
    required this.items,
    required this.open,
    required this.onDismiss,
    super.key,
  });

  /// 触发菜单的锚点控件。
  final Widget anchor;

  /// 菜单项。
  final List<OgMd1MenuItem> items;

  /// 是否展开。
  final bool open;

  /// 关闭回调（遮罩 / 选中 / Escape）。
  final VoidCallback onDismiss;

  @override
  State<OgMd1Menu> createState() => _OgMd1MenuState();
}

class _OgMd1MenuState extends State<OgMd1Menu> {
  final FocusNode _keyboardNode = FocusNode();
  int _focused = -1;

  @override
  void dispose() {
    _keyboardNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || !widget.open) {
      return;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focused = (_focused + 1) % widget.items.length;
      });
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focused = (_focused - 1 + widget.items.length) % widget.items.length;
      });
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      _select(_focused);
    }
  }

  void _select(int index) {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    final OgMd1MenuItem item = widget.items[index];
    if (item.onSelected == null) {
      return;
    }
    item.onSelected!(index);
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    return Semantics(
      container: true,
      child: RawKeyboardListener(
        focusNode: _keyboardNode,
        onKey: _onKey,
        child: Stack(
          fit: StackFit.loose,
          children: <Widget>[
            widget.anchor,
            if (widget.open)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  child: Semantics(
                    button: true,
                    label: 'Close menu',
                    child: CustomPaint(painter: _OgMd1MenuScrimPainter()),
                  ),
                ),
              ),
            if (widget.open)
              PositionedDirectional(
                start: 0,
                top: OgMd1Size.touchTarget,
                child: Semantics(
                  explicitChildNodes: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: OgMd1Size.dialogMinWidth / 2,
                    ),
                    child: CustomPaint(
                      painter: _OgMd1MenuPainter(color: palette.card),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (int i = 0; i < widget.items.length; i++)
                            Semantics(
                              button: true,
                              enabled: widget.items[i].onSelected != null,
                              label: widget.items[i].label,
                              child: Focus(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _select(i),
                                  child: SizedBox(
                                    height: OgMd1Size.touchTarget,
                                    child: CustomPaint(
                                      painter: _OgMd1MenuItemPainter(
                                        highlight: _focused == i,
                                        enabled:
                                            widget.items[i].onSelected != null,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: OgMd1Size.buttonPadding,
                                        ),
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: Text(
                                            widget.items[i].label,
                                            style: TextStyle(
                                              fontSize: OgMd1Type.subhead,
                                              fontWeight: OgMd1Type.bodyWeight,
                                              color:
                                                  widget.items[i].onSelected ==
                                                          null
                                                      ? palette.textSecondary
                                                      : palette.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
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
          ],
        ),
      ),
    );
  }
}

/// 菜单遮罩：全屏透明点击层（不用 ModalBarrier / Material）。
class _OgMd1MenuScrimPainter extends CustomPainter {
  const _OgMd1MenuScrimPainter();

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_OgMd1MenuScrimPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// 下拉选择框：48dp 底线输入框 + 自绘下拉三角 + 选项面板（复用菜单外观）。
// ─────────────────────────────────────────────────────────────────────────────

/// 下拉选择框外观：48dp 高、底边 1px（focus 2px primary）+ 右侧三角。
class _OgMd1DropdownFieldPainter extends CustomPainter {
  const _OgMd1DropdownFieldPainter({
    required this.lineColor,
    required this.lineWidth,
    required this.arrowColor,
    required this.open,
  });

  final Color lineColor;
  final double lineWidth;
  final Color arrowColor;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height - lineWidth / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = lineColor
        ..strokeWidth = lineWidth,
    );
    final double cx = size.width - OgMd1Type.body;
    final double cy = size.height / 2 - OgMd1Type.body / 4;
    final Paint arrow = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _md1DividerPx;
    final double half = OgMd1Type.body / 2;
    final double dy = open ? -half : half;
    canvas.drawLine(Offset(cx - half, cy), Offset(cx, cy + dy), arrow);
    canvas.drawLine(Offset(cx, cy + dy), Offset(cx + half, cy), arrow);
  }

  @override
  bool shouldRepaint(_OgMd1DropdownFieldPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.lineWidth != lineWidth ||
      oldDelegate.arrowColor != arrowColor ||
      oldDelegate.open != open;
}

/// MD1 下拉选择框：48dp 底线输入框 + 右侧三角，点按展开选项面板。
///
/// 选项面板复用 [OgMd1Menu] 的自绘外观（card + elevation8 + 48dp 行），
/// 焦点在字段上；上下键改变高亮项、Enter/Space 展开或确认，Escape 收起。
/// 所有可见外观由 CustomPainter 绘制，零 Material 控件。
class OgMd1Dropdown extends StatefulWidget {
  /// 创建下拉选择框。
  const OgMd1Dropdown({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.label,
    super.key,
  });

  /// 候选项文案（本地化后传入）。
  final List<String> items;

  /// 当前选中索引；-1 表示未选。
  final int selectedIndex;

  /// 选中项回调。
  final ValueChanged<int> onChanged;

  /// 无障碍标签（调用方本地化后传入）。
  final String? label;

  @override
  State<OgMd1Dropdown> createState() => _OgMd1DropdownState();
}

class _OgMd1DropdownState extends State<OgMd1Dropdown> {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _keyboardNode = FocusNode();
  bool _open = false;
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _open) {
      setState(() => _open = false);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _keyboardNode.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= widget.items.length) {
      return;
    }
    widget.onChanged(index);
    setState(() => _open = false);
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _open = false);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _open = true;
        _highlight = (_highlight + 1) % widget.items.length;
      });
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _open = true;
        _highlight =
            (_highlight - 1 + widget.items.length) % widget.items.length;
      });
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      if (_open) {
        _select(_highlight);
      } else {
        setState(() {
          _open = true;
          _highlight = widget.selectedIndex < 0 ? 0 : widget.selectedIndex;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool focused = _focusNode.hasFocus;
    final String shown =
        widget.selectedIndex >= 0 && widget.selectedIndex < widget.items.length
            ? widget.items[widget.selectedIndex]
            : '';
    return Semantics(
      container: true,
      child: RawKeyboardListener(
        focusNode: _keyboardNode,
        onKey: _onKey,
        child: Stack(
          fit: StackFit.loose,
          children: <Widget>[
            Semantics(
              button: true,
              enabled: true,
              label: widget.label,
              value: shown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _focusNode.requestFocus();
                  setState(() {
                    _open = !_open;
                    _highlight =
                        widget.selectedIndex < 0 ? 0 : widget.selectedIndex;
                  });
                },
                child: Focus(
                  focusNode: _focusNode,
                  child: SizedBox(
                    height: OgMd1Size.field,
                    child: CustomPaint(
                      painter: _OgMd1DropdownFieldPainter(
                        lineColor:
                            focused ? palette.primary : palette.textSecondary,
                        lineWidth:
                            focused ? OgMd1Size.radius * 2 : _md1DividerPx,
                        arrowColor:
                            focused ? palette.primary : palette.textSecondary,
                        open: _open,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: OgMd1Type.headline,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            shown,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: OgMd1Type.subhead,
                              fontWeight: OgMd1Type.bodyWeight,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_open)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = false),
                  child: Semantics(
                    button: true,
                    label: 'Close dropdown',
                    child: CustomPaint(painter: _OgMd1MenuScrimPainter()),
                  ),
                ),
              ),
            if (_open)
              PositionedDirectional(
                start: 0,
                top: OgMd1Size.field,
                child: Semantics(
                  explicitChildNodes: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: OgMd1Size.dialogMinWidth / 2,
                    ),
                    child: CustomPaint(
                      painter: _OgMd1MenuPainter(color: palette.card),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (int i = 0; i < widget.items.length; i++)
                            Semantics(
                              button: true,
                              label: widget.items[i],
                              selected: i == widget.selectedIndex,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _select(i),
                                child: SizedBox(
                                  height: OgMd1Size.touchTarget,
                                  child: CustomPaint(
                                    painter: _OgMd1MenuItemPainter(
                                      highlight: _highlight == i,
                                      enabled: true,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: OgMd1Size.buttonPadding,
                                      ),
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Text(
                                          widget.items[i],
                                          style: TextStyle(
                                            fontSize: OgMd1Type.subhead,
                                            fontWeight: OgMd1Type.bodyWeight,
                                            color: i == widget.selectedIndex
                                                ? palette.primary
                                                : palette.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
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
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 批 6A：4 个 CustomPainter 控件（Avatar / Tooltip / Scrollbar / IconButton）。
// 全部可见外观由 CustomPainter 自绘，零 Material 可见控件。

const double _md1AvatarDiameter = OgMd1Size.listLeading;

/// Avatar 外观 painter：圆形/圆角方形底 + 1px 描边；有图时画出图、否则画占位。
class _OgMd1AvatarPainter extends CustomPainter {
  const _OgMd1AvatarPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.placeholderColor,
    required this.circle,
    required this.image,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color placeholderColor;
  final bool circle;
  final Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect shape = RRect.fromRectAndRadius(
      rect,
      circle
          ? Radius.circular(size.shortestSide / 2)
          : const Radius.circular(OgMd1Size.radius),
    );
    canvas.drawRRect(shape, Paint()..color = backgroundColor);
    final Image? avatar = image;
    if (avatar != null) {
      final double scale = math.max(
        size.width / avatar.width,
        size.height / avatar.height,
      );
      final double dw = avatar.width * scale;
      final double dh = avatar.height * scale;
      final Rect src = Rect.fromLTWH(
        0,
        0,
        avatar.width.toDouble(),
        avatar.height.toDouble(),
      );
      final Rect dst = Rect.fromLTWH(
        (size.width - dw) / 2,
        (size.height - dh) / 2,
        dw,
        dh,
      );
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawImageRect(avatar, src, dst, Paint());
      canvas.restore();
    } else {
      final double centerX = size.width / 2;
      final double centerY = size.height / 2;
      final double headR = size.shortestSide / 5;
      final Paint placeholder = Paint()..color = placeholderColor;
      canvas.drawCircle(Offset(centerX, centerY - headR), headR, placeholder);
      canvas.drawArc(
        Rect.fromLTWH(
          centerX - headR * 2,
          centerY + headR,
          headR * 4,
          headR * 4,
        ),
        0,
        math.pi,
        true,
        placeholder,
      );
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _md1DividerPx,
    );
  }

  @override
  bool shouldRepaint(_OgMd1AvatarPainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.placeholderColor != placeholderColor ||
      oldDelegate.circle != circle ||
      oldDelegate.image != image;
}

/// MD1 头像：40dp 圆/圆角方底 + 1px 描边，优先绘制 [image]，否则画占位人形。
// ── 扩展控件 · 头像 / 气泡 / 滚动条 / 图标按钮 ──
class OgMd1Avatar extends StatelessWidget {
  /// 创建头像。
  const OgMd1Avatar({this.image, this.label, this.circle = true, super.key});

  /// 已解码的头像位图；为 null 时画占位。
  final Image? image;

  /// 无障碍标签（调用方本地化后传入）。
  final String? label;

  /// true 圆形（默认），false 为 2dp 圆角方形。
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    return Semantics(
      image: true,
      label: label,
      container: true,
      child: SizedBox(
        width: _md1AvatarDiameter,
        height: _md1AvatarDiameter,
        child: CustomPaint(
          painter: _OgMd1AvatarPainter(
            backgroundColor: palette.divider,
            borderColor: palette.divider,
            placeholderColor: palette.textSecondary,
            circle: circle,
            image: image,
          ),
        ),
      ),
    );
  }
}

/// Tooltip 外观 painter：MD1 暗色气泡 + 三角指针 + elevation2 真投影。
class _OgMd1TooltipPainter extends CustomPainter {
  const _OgMd1TooltipPainter({
    required this.color,
    required this.pointerColor,
    required this.radius,
    required this.pointerX,
    required this.below,
  });

  final Color color;
  final Color pointerColor;
  final double radius;
  final double pointerX;
  final bool below;

  @override
  void paint(Canvas canvas, Size size) {
    final double arrow = OgMd1Type.body;
    final Rect body = below
        ? Rect.fromLTWH(0, arrow, size.width, size.height - arrow)
        : Rect.fromLTWH(0, 0, size.width, size.height - arrow);
    final RRect bubble = RRect.fromRectAndRadius(body, Radius.circular(radius));
    _paintShadows(canvas, bubble, OgMd1Elevation.dp2);
    canvas.drawRRect(bubble, Paint()..color = color);
    final Path pointer = Path();
    if (below) {
      pointer
        ..moveTo(pointerX - arrow, arrow)
        ..lineTo(pointerX + arrow, arrow)
        ..lineTo(pointerX, 0)
        ..close();
    } else {
      pointer
        ..moveTo(pointerX - arrow, size.height - arrow - 1)
        ..lineTo(pointerX + arrow, size.height - arrow - 1)
        ..lineTo(pointerX, size.height - 1)
        ..close();
    }
    canvas.drawPath(pointer, Paint()..color = pointerColor);
  }

  @override
  bool shouldRepaint(_OgMd1TooltipPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.pointerColor != pointerColor ||
      oldDelegate.radius != radius ||
      oldDelegate.pointerX != pointerX ||
      oldDelegate.below != below;
}

/// MD1 Tooltip：暗色气泡 + 三角指针，长按/点击显示、再次点击或移出隐藏。
///
/// [below] 为 true 时指针朝上（气泡在锚点下方），否则指针朝下。
/// 文案由调用方本地化后传入；Semantics 的 tooltip 走同一份文案。
class OgMd1Tooltip extends StatefulWidget {
  /// 创建气泡提示。
  const OgMd1Tooltip({
    required this.message,
    required this.child,
    this.below = false,
    super.key,
  });

  /// 提示文案（本地化后传入）。
  final String message;

  /// 锚点控件。
  final Widget child;

  /// 气泡是否位于锚点下方（指针朝上）。
  final bool below;

  @override
  State<OgMd1Tooltip> createState() => _OgMd1TooltipState();
}

class _OgMd1TooltipState extends State<OgMd1Tooltip> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final double pointerX = OgMd1Size.listLeading / 2;
    final Widget bubble = Semantics(
      tooltip: widget.message,
      child: CustomPaint(
        painter: _OgMd1TooltipPainter(
          color: palette.background,
          pointerColor: palette.background,
          radius: OgMd1Size.radius,
          pointerX: pointerX,
          below: widget.below,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: OgMd1Size.buttonPadding,
            vertical: OgMd1Size.radius,
          ),
          child: Text(
            widget.message,
            style: TextStyle(
              fontSize: OgMd1Type.caption,
              fontWeight: OgMd1Type.bodyWeight,
              color: palette.card,
            ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Semantics(
            tooltip: widget.message,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _visible = !_visible),
              onLongPress: () => setState(() => _visible = true),
              onTapUp: (_) {},
              child: widget.child,
            ),
          ),
          if (_visible)
            PositionedDirectional(
              top: widget.below ? OgMd1Size.touchTarget : null,
              bottom: widget.below ? null : OgMd1Size.touchTarget,
              child: IgnorePointer(child: bubble),
            ),
        ],
      ),
    );
  }
}

/// Scrollbar 外观 painter：MD1 细滚动条（默认轨透明、拇指 4dp 圆角）。
class _OgMd1ScrollbarPainter extends CustomPainter {
  const _OgMd1ScrollbarPainter({
    required this.thumbColor,
    required this.trackColor,
    required this.fraction,
    required this.offset,
    required this.vertical,
  });

  final Color thumbColor;
  final Color trackColor;
  final double fraction;
  final double offset;
  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    if (trackColor.a > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
    }
    final double extent = vertical ? size.height : size.width;
    final double cross = vertical ? size.width : size.height;
    final double thumbExtent = math.max(
      extent * fraction.clamp(0.0, 1.0),
      OgMd1Type.caption,
    );
    final double t = offset.clamp(0.0, 1.0);
    final double start = (extent - thumbExtent) * t;
    final Rect rect = vertical
        ? Rect.fromLTWH(0, start, cross, thumbExtent)
        : Rect.fromLTWH(start, 0, thumbExtent, cross);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(OgMd1Size.radius)),
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_OgMd1ScrollbarPainter oldDelegate) =>
      oldDelegate.thumbColor != thumbColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.fraction != fraction ||
      oldDelegate.offset != offset ||
      oldDelegate.vertical != vertical;
}

/// MD1 细滚动条：自绘拇指 + 拖拽跳转。
///
/// 随 [controller] 的滚动通知更新拇指位置与长度（[fraction] 为可见比例）；
/// 拖拽拇指直接跳转滚动位置。触摸目标不小于 48dp（[OgMd1Size.touchTarget]）。
class OgMd1Scrollbar extends StatefulWidget {
  /// 创建滚动条。
  const OgMd1Scrollbar({
    required this.child,
    required this.controller,
    this.fraction = 0.5,
    this.vertical = true,
    this.label = 'Scrollbar',
    super.key,
  });

  /// 被滚动的内容。
  final Widget child;

  /// 内容滚动控制器。
  final ScrollController controller;

  /// 可见区占总内容比例（0–1）。
  final double fraction;

  /// true 竖向（默认），false 横向。
  final bool vertical;

  /// 无障碍标签（调用方本地化后传入）。
  final String label;

  @override
  State<OgMd1Scrollbar> createState() => _OgMd1ScrollbarState();
}

class _OgMd1ScrollbarState extends State<OgMd1Scrollbar> {
  double _progress = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant OgMd1Scrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      _progress = 0;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final ScrollController controller = widget.controller;
    if (!controller.hasClients) {
      return;
    }
    final double pixels = controller.position.pixels;
    final double range = controller.position.maxScrollExtent;
    final double next = range > 0 ? (pixels / range).clamp(0.0, 1.0) : 0;
    if (next != _progress) {
      setState(() => _progress = next);
    }
  }

  void _jump(DragUpdateDetails details, double extent) {
    if (!widget.controller.hasClients || extent <= 0) {
      return;
    }
    final double position =
        widget.vertical ? details.localPosition.dy : details.localPosition.dx;
    final double thumbExtent = math.max(
      extent * widget.fraction.clamp(0.0, 1.0),
      OgMd1Type.caption,
    );
    final double usable = extent - thumbExtent;
    final double t = usable > 0 ? (position - thumbExtent / 2) / usable : 0;
    widget.controller.jumpTo(
      t.clamp(0.0, 1.0) * widget.controller.position.maxScrollExtent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final Widget bar = Semantics(
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDragStart: (_) => setState(() => _dragging = true),
        onDragUpdate: (DragUpdateDetails details) {
          final RenderBox? box = context.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          _jump(details, widget.vertical ? box.size.height : box.size.width);
        },
        onDragEnd: (_) => setState(() => _dragging = false),
        child: CustomPaint(
          painter: _OgMd1ScrollbarPainter(
            thumbColor: palette.textSecondary.withValues(
              alpha: _dragging ? 0.7 : 0.4,
            ),
            trackColor: Colors.transparent,
            fraction: widget.fraction,
            offset: _progress,
            vertical: widget.vertical,
          ),
        ),
      ),
    );
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _onScroll();
            return false;
          },
          child: widget.child,
        ),
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          child: SizedBox(
            width:
                widget.vertical ? OgMd1Size.touchTarget / 4 : double.infinity,
            height:
                widget.vertical ? double.infinity : OgMd1Size.touchTarget / 4,
            child: bar,
          ),
        ),
      ],
    );
  }
}

/// IconButton 外观 painter：按下 ripple 圆 + 可选 1px 外框（MD1 触控反馈）。
class _OgMd1IconButtonPainter extends CustomPainter {
  const _OgMd1IconButtonPainter({
    required this.rippleColor,
    required this.progress,
    required this.center,
  });

  final Color rippleColor;
  final double progress;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      return;
    }
    final double maxRadius = math.max(
      math.max(center.dx, size.width - center.dx),
      math.max(center.dy, size.height - center.dy),
    );
    canvas.drawCircle(
      center,
      maxRadius * progress,
      Paint()..color = rippleColor.withValues(alpha: 0.22 * (1 - progress)),
    );
  }

  @override
  bool shouldRepaint(_OgMd1IconButtonPainter oldDelegate) =>
      oldDelegate.rippleColor != rippleColor ||
      oldDelegate.progress != progress ||
      oldDelegate.center != center;
}

/// MD1 IconButton：48dp 触控目标，居中图标 + 自绘 ripple。
///
/// 焦点/键盘（Enter/Space）与 Semantics button 齐备；[onPressed] 为 null 时
/// 显示为 [palette.textSecondary] 并不响应手势。
class OgMd1IconButton extends StatefulWidget {
  /// 创建图标按钮。
  const OgMd1IconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// 图标（由调用方经语义图标层传入）。
  final IconData icon;

  /// 无障碍标签（调用方本地化后传入）。
  final String label;

  /// 点击回调；为 null 时禁用。
  final VoidCallback? onPressed;

  @override
  State<OgMd1IconButton> createState() => _OgMd1IconButtonState();
}

class _OgMd1IconButtonState extends State<OgMd1IconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OgLAnim.fast(context),
  );
  late final FocusNode _focusNode = FocusNode();
  Offset _center = Offset.zero;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || widget.onPressed == null) {
      return;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _center = const Offset(
        OgMd1Size.touchTarget / 2,
        OgMd1Size.touchTarget / 2,
      );
      _controller
        ..reset()
        ..forward();
      widget.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgMd1Colors palette = OgMd1Colors.of(context);
    final bool enabled = widget.onPressed != null;
    final Color iconColor =
        enabled ? palette.textPrimary : palette.textSecondary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: _onKey,
        child: Focus(
          focusNode: _focusNode,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails details) {
              if (!enabled) {
                return;
              }
              _center = details.localPosition;
              _controller
                ..reset()
                ..forward();
            },
            onTap: enabled ? widget.onPressed : null,
            child: SizedBox(
              width: OgMd1Size.touchTarget,
              height: OgMd1Size.touchTarget,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) => CustomPaint(
                  painter: _OgMd1IconButtonPainter(
                    rippleColor:
                        enabled ? palette.primary : palette.textSecondary,
                    progress: _controller.value,
                    center: _center,
                  ),
                  child: child,
                ),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: OgMd1Type.title,
                    color: iconColor,
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
