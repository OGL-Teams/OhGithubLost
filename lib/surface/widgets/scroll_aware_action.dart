/// L3 展示级 · **滚动感知悬浮动作**（悬浮元素"让路"给内容）。
///
/// ## 为什么需要它
/// 悬浮按钮（`FloatingActionButton`）固定在右下角，`ListView` 滚到底部时
/// 会**压住最后几行内容**。本组件给悬浮元素加上一套统一的"让路"行为，
/// 一处实现、多处复用，避免每个页面各写一套（迟早行为不一致）。
///
/// ## 五条行为（对每个接入的悬浮元素都成立）
/// 1. **下滑收边**：向下滚动累计超过阈值后，元素贴屏幕边缘滑出，
///    只留 `peekFactor`（默认 **1/4**）可见 —— 收边态靠边、不遮内容；
/// 2. **点击弹出**：点击（或屏幕阅读器激活）收边态元素 → **立即完全展开**，
///    展开前不会误触发原本的主操作；
/// 3. **上滑自动弹回**：向上滚动累计超过阈值 → 自动完全展开；
/// 4. **近底部收起**：滚动位置进入"距底部约 [bottomReserve]（默认半屏）以内"
///    时**强制收起**，让页面尾部内容露出来；离开该区域后按滚动方向恢复；
/// 5. **动画过渡**：收边 / 展开都走 [OgLAnim] 档位质量表的时长与曲线，
///    不跳变；档位 `0`（静默 / 系统"减少动效"）下降级为瞬时切换。
///
/// ## 滚动判定为什么不是"看一帧的 delta"
/// 单帧 `delta` 在惯性滚动、回弹（`ClampingScrollPhysics`）与手指微抖时
/// 方向会**反复横跳**，直接切状态就会看到元素"抽搐"。因此这里：
/// - **累积同向位移**，达到 [scrollThreshold]（默认 28px）才切状态；
/// - **方向反转即清零**累积（换向不需要"先抵消");
/// - `|delta| < 1px` 的抖动直接忽略；
/// - `|delta|` 大于一屏的"瞬移"（重新挂载 / `jumpTo` / 内容收缩修正）视为
///   重新标定基线，不计入方向判定。
///
/// ## 无障碍
/// - 收边态下，元素**仍然可点**：收边时在可见区域内覆盖一层透明手势层
///   （只拦截"点击"，不拦截拖拽 —— 滚动照常交给列表），命中即展开；
/// - 可见部分中"沿屏幕边缘方向"的尺寸由 `peekFactor` 与
///   [minVisibleExtent]（默认 48dp，含 [edgeInset] 边距）共同保证，
///   展开态的主控件本身仍是 ≥ 48dp 的触控目标；
/// - 收边态保留原控件的语义（`tooltip` / `onPressed` / 图标 / 文案一字不改），
///   并额外播报一条 [hint]（见 [hintKey]，走 i18n）。
///
/// ## 用法
/// ```dart
/// floatingActionButton: ScrollAwareAction(
///   controller: _scroll,                       // 同一页面滚动视图的 controller
///   child: FloatingActionButton.extended(...), // 原控件原样传进来
/// ),
/// ```
///
/// [hint]: https://api.flutter.dev/flutter/widgets/SemanticsProperties/hint.html
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/animations.dart';
import '../app/motion.dart';
import '../i18n/og_l_i18n.dart';

/// 取 `common` 分片文案。
String _t(String key) => OgLI18n.instance.t('common', key);

/// 收边态播报的提示文案键（`common` 分片，六语言同步）。
const String kScrollAwareCollapsedHintKey = 'scrollAwareCollapsedHint';

/// 忽略的位移抖动（px）：小于它的单帧 delta 不参与方向判定。
const double _kDeltaEpsilon = 1;

/// 滚动感知悬浮动作（见文件头注释）。
class ScrollAwareAction extends StatefulWidget {
  /// 创建。
  const ScrollAwareAction({
    required this.controller,
    required this.child,
    this.peekFactor = 0.25,
    this.edge = AxisDirection.right,
    this.scrollThreshold = 28,
    this.bottomReserve = 0.5,
    this.edgeInset = 16,
    this.minVisibleExtent = 48,
    super.key,
  });

  /// 页面滚动视图的 `ScrollController`。
  ///
  /// 必须与**本元素所在页面**的滚动视图共用同一个实例（本组件靠它读
  /// `pixels` / `maxScrollExtent` / `viewportDimension`）。为 `null` 或尚未
  /// 挂载时保持展开（例如空态没有滚动视图）。
  final ScrollController? controller;

  /// 原悬浮控件（`FloatingActionButton` / 底部主操作按钮……），原样传入。
  final Widget child;

  /// 收边后**保留可见**的比例（0–1）。`0.25` = 只露 1/4。
  final double peekFactor;

  /// 收边方向：元素向哪一边滑出屏幕。
  ///
  /// - [AxisDirection.right]（默认）/ [AxisDirection.left]：左右收边（`FAB`）；
  /// - [AxisDirection.down] / [AxisDirection.up]：上下收边（底部横条按钮）。
  final AxisDirection edge;

  /// 切换状态所需的**累积同向位移**（px），越小越灵敏、越大越稳。
  final double scrollThreshold;

  /// 近底部收起的比例阈值：距底部 `viewportDimension × bottomReserve`
  /// 以内即强制收起；`0` 表示关闭该规则（用于"按钮本身就是内容尾部"的页面）。
  final double bottomReserve;

  /// 元素与屏幕边缘的固有间距（`FAB` 的 16dp 外边距 / 列表底部内边距）。
  ///
  /// 只用于换算"屏上可见尺寸"，不参与位移计算。
  final double edgeInset;

  /// 收边态在屏幕上的**最小可见尺寸**（dp），保证触控目标够大。
  ///
  /// 换算成"沿滑动轴的可见比例"后，只有它不超过元素自身的 **60%** 时才生效
  /// ——否则收边将名存实亡（此时仍按 [peekFactor] 收边，由 [peekFactor] 调整）。
  /// 例如 56dp 的圆形 `FAB`：1/4 只有 14dp，加上 16dp 外边距也不足 48dp，
  /// 因此按"留 32dp"收边（屏上 48dp 命中区），仍有约六成被收到屏幕外。
  final double minVisibleExtent;

  @override
  State<ScrollAwareAction> createState() => _ScrollAwareActionState();
}

class _ScrollAwareActionState extends State<ScrollAwareAction>
    with SingleTickerProviderStateMixin {
  /// 测量子控件尺寸（把"露 1/4"换算成与命中区约束的比较基准）。
  final GlobalKey _childKey = GlobalKey();

  late final AnimationController _anim = AnimationController(vsync: this);
  CurvedAnimation? _curve;
  Curve? _curveForward;
  Curve? _curveReverse;

  /// 档位质量表给的时长（收边用短、展开用中等）。
  Duration _collapseDuration = Duration.zero;
  Duration _expandDuration = Duration.zero;

  /// 是否收边。
  bool _collapsed = false;

  /// 是否因"近底部"而强制收边。
  bool _pinned = false;

  /// 是否已记录基线位置（重新挂载后重新标定，避免用陈旧的上一帧做差）。
  bool _baseline = false;
  double _lastPixels = 0;

  /// 累积同向位移（px）。
  double _accum = 0;

  /// 子控件沿滑动轴的尺寸（首帧测量后得到）。
  double? _extent;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 时长 / 曲线一律取自档位质量表（`app/motion.dart`），不硬编码。
    final OgLOAnimQuality quality = OgLAnim.quality(context);
    _collapseDuration = quality.fast;
    _expandDuration = quality.medium;
    if (_curveForward != quality.curve || _curveReverse != quality.settleCurve) {
      _curve?.dispose();
      _curve = CurvedAnimation(
        parent: _anim,
        // 正向 = 收边（干脆地"收"进去）。
        curve: quality.curve,
        // 反向 = 展开（略带回弹地"弹"出来）。
        reverseCurve: quality.settleCurve,
      );
      _curveForward = quality.curve;
      _curveReverse = quality.settleCurve;
    }
  }

  @override
  void didUpdateWidget(ScrollAwareAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onScroll);
      widget.controller?.addListener(_onScroll);
      _baseline = false;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onScroll);
    _curve?.dispose();
    _anim.dispose();
    super.dispose();
  }

  // ── 几何 ──────────────────────────────────────────────────────────────────

  /// 滑动轴。
  Axis get _axis => widget.edge == AxisDirection.up || widget.edge == AxisDirection.down
      ? Axis.vertical
      : Axis.horizontal;

  /// 收边方向在轴上的符号（+1 = 正方向滑出）。
  double get _sign => switch (widget.edge) {
        AxisDirection.right || AxisDirection.down => 1,
        AxisDirection.left || AxisDirection.up => -1,
      };

  /// 收边后**保留可见**的比例。
  double get _peek {
    final double base = _clamp01(widget.peekFactor);
    final double extent = _extent ?? 0;
    if (extent <= 0 || widget.minVisibleExtent <= 0) {
      return base;
    }
    // 把"屏上至少可见 N dp"换算成"至少露出多少比例"：
    // 元素本身离屏幕边缘还有 `edgeInset`，那部分也是可见的。
    final double floorValue =
        math.max(widget.minVisibleExtent - widget.edgeInset, 0) / extent;
    if (floorValue <= base || floorValue > 0.6) {
      // 已经够大，或"至少可见 N dp"会把元素遮不到一半（收边名存实亡）—— 按 peekFactor 收边。
      // 0.6 是两者的折中：56dp 的圆形 FAB 收边后仍留 32dp 可见
      // （加 16dp 外边距 = 屏上 48dp 命中区），同时仍有约六成被"收"出屏幕。
      return base;
    }
    return floorValue;
  }

  /// 收边终态的位移（`SlideTransition` 用的是子控件尺寸的比例）。
  Offset get _collapsedOffset {
    final double slide = _sign * (1 - _peek);
    return _axis == Axis.vertical ? Offset(0, slide) : Offset(slide, 0);
  }

  static double _clamp01(double value) =>
      value < 0 ? 0 : (value > 1 ? 1 : value);

  // ── 滚动判定 ──────────────────────────────────────────────────────────────

  void _onScroll() {
    final ScrollController? controller = widget.controller;
    if (controller == null || !controller.hasClients) {
      return;
    }
    if (!controller.positions.every((ScrollPosition p) => p.hasPixels && p.hasContentDimensions)) {
      return;
    }
    final ScrollPosition position = controller.positions.last;
    final double pixels = position.pixels;
    if (!_baseline) {
      _baseline = true;
      _lastPixels = pixels;
      return;
    }
    final double delta = pixels - _lastPixels;
    _lastPixels = pixels;

    final double viewport = position.viewportDimension;
    final double reserve = viewport * widget.bottomReserve;
    // 内容确实"够长"时才启用近底部规则：短列表（几乎不用滚）不把按钮永久收起来。
    final bool nearBottom = widget.bottomReserve > 0 &&
        position.maxScrollExtent > reserve &&
        position.maxScrollExtent - pixels <= reserve;
    if (nearBottom) {
      _pinned = true;
      _accum = 0;
      _setCollapsed(true);
      return;
    }
    if (_pinned) {
      // 刚离开近底部区域：不立刻跳变，交回方向判定（继续上滑才弹回）。
      _pinned = false;
      _accum = 0;
    }
    if (delta.abs() < _kDeltaEpsilon) {
      return;
    }
    if (delta.abs() > viewport) {
      // 重新挂载 / jumpTo / 内容收缩导致的"瞬移"：重新标定基线，不当成滚动方向。
      _accum = 0;
      return;
    }
    if (_accum != 0 && (delta > 0) != (_accum > 0)) {
      // 方向反转：旧的累积作废（换向不需要先"抵消"）。
      _accum = 0;
    }
    _accum += delta;
    if (_accum >= widget.scrollThreshold) {
      _accum = 0;
      _setCollapsed(true);
    } else if (_accum <= -widget.scrollThreshold) {
      _accum = 0;
      _setCollapsed(false);
    }
  }

  void _setCollapsed(bool value) {
    if (_collapsed == value) {
      return;
    }
    // 布局 / 绘制阶段（滚动视图修正 offset）不能直接 setState：推到帧末。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _setCollapsed(value);
        }
      });
      return;
    }
    setState(() => _collapsed = value);
    if (value) {
      _anim.animateTo(1, duration: _collapseDuration);
    } else {
      _anim.animateTo(0, duration: _expandDuration);
    }
  }

  // ── 构建 ──────────────────────────────────────────────────────────────────

  void _measure() {
    if (!mounted) {
      return;
    }
    final RenderObject? render = _childKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) {
      return;
    }
    final double extent =
        _axis == Axis.vertical ? render.size.height : render.size.width;
    if (extent > 0 && _extent != extent) {
      setState(() => _extent = extent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation? curve = _curve;
    final Animation<Offset> slide = curve == null
        ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
        : curve.drive(Tween<Offset>(begin: Offset.zero, end: _collapsedOffset));

    // 收边态：盖一层"只吃点击、不吃拖拽"的透明手势层 ——
    // 点击 = 展开（不会误触原主操作），滚动仍然交给下面的列表。
    final Widget tapLayer = Semantics(
      hint: _t(kScrollAwareCollapsedHintKey),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 只用 onTap（不用 onTapDown）：手指按在收边元素上**拖拽滚动**时，
        // 点击识别器会因超出滑动容差而落败 —— 滚动不会误触发展开。
        onTap: () => _setCollapsed(false),
        child: const SizedBox.expand(),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    return SlideTransition(
      position: slide,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          KeyedSubtree(key: _childKey, child: widget.child),
          if (_collapsed) Positioned.fill(child: tapLayer),
        ],
      ),
    );
  }
}
