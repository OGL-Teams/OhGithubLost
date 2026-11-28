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
        GestureDetector,
        HitTestBehavior,
        Key,
        MainAxisAlignment,
        Padding,
        Row,
        SingleTickerProviderStateMixin,
        SizedBox,
        State,
        StatefulWidget,
        StatelessWidget,
        Text,
        TextAlign,
        TextOverflow,
        TextStyle,
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
void _paintShadows(
  Canvas canvas,
  RRect shape,
  Iterable<BoxShadow> shadows,
) {
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
