/// L3 展示级 · 全局动效策略（档位 → **质量**，而不是"有/无"）。
///
/// ## 设计原则（5.2 调整）
/// 用户反馈：整体动画仍偏卡。因此把思路从"低档直接砍掉效果"改成
/// **逐级降低质量**：
///
/// - 档位 `0`：**静默**（时长归零、无位移、无缩放）——无障碍 / 省电场景；
/// - 档位 `1`：**最保守**（只淡入、最短时长、错峰只覆盖前几项、无缩放）；
/// - 档位 `2`：**标准**（淡入 + 小位移、中等时长、错峰适度、仍不缩放）；
/// - 档位 `3`：**拉满**（淡入 + 较大位移 + 轻微缩放、最长时长、错峰最广）。
///
/// 关键约定：**1 < 2 < 3 逐级更"重"**，即每一档的时长 / 位移 / 参与动画的项数
/// 都**不减少**、缩放只可能出现在更高档。这样"降档"=降质量，而不是丢功能。
///
/// 任何动画都**不应硬编码时长/位移/缩放**：一律经 [OgLAnim]（见 `animations.dart`）
/// 读取本表；`tool/motion_audit.py` 会在 CI 里卡住硬编码。
library;

import 'package:flutter/material.dart';

import '../settings.dart';

/// 动效质量档（某档位下的**全部**动画参数）。
///
/// 纯数据 + 纯函数：可单测（逐级单调性），不依赖任何运行时环境。
@immutable
class OgLOAnimQuality {
  /// 创建。所有时长/系数都由档位表给出，业务代码不要自己造。
  const OgLOAnimQuality({
    required this.level,
    required this.fast,
    required this.medium,
    required this.slow,
    required this.staggerStep,
    required this.staggerMaxIndex,
    required this.revealAll,
    required this.revealOffset,
    required this.revealScaleFrom,
    required this.transitionOffset,
    required this.transitionScaleFrom,
    required this.blurSigma,
    required this.curve,
    required this.largeCurve,
    required this.settleCurve,
    required this.springStiffness,
    required this.springDamping,
    required this.transitionWindow,
    required this.shellDuration,
    required this.shellOffset,
    required this.stateSwapDuration,
    required this.pageViewDuration,
    required this.sheetDuration,
  });

  /// 档位（0–3）。
  final int level;

  /// 短反馈时长。
  final Duration fast;

  /// 中等时长（入场 / 状态变化）。
  final Duration medium;

  /// 较大范围变化的时长。
  final Duration slow;

  /// 列表错峰步长。
  final Duration staggerStep;

  /// 参与"错峰"的最大序号（超出者不再错峰，见 [revealAll]）。
  final int staggerMaxIndex;

  /// **覆盖面**：是否**每个控件都参与**入场动画。
  ///
  /// - `false`（档位 1）：只有主要区域 + 前 [staggerMaxIndex] 项动，
  ///   更省、更保守；
  /// - `true`（档位 2 / 3）：**所有控件都有动画**——这正是"倒数第二档
  ///   （档位 2）用最简单的动画保证每个控件都有"的落点。
  ///
  /// 注意它只决定**覆盖面**，不决定效果强弱（效果强弱由
  /// [revealOffset] / [revealScaleFrom] 等决定）。
  final bool revealAll;

  /// 入场位移（占自身高度比例；0 = 只淡入，不动位置）。
  final double revealOffset;

  /// 入场缩放起点（1 = 不缩放）。
  final double revealScaleFrom;

  /// 页面过渡位移（占页高比例）。
  final double transitionOffset;

  /// 页面过渡缩放起点（1 = 不缩放）。
  final double transitionScaleFrom;

  /// 允许的最大模糊半径（0 = 不允许任何模糊，模糊是最贵的效果之一）。
  final double blurSigma;

  /// 统一缓动：一律用**自然减速**（ease-out 阶梯），
  /// 越保守的档位越轻、越高的档位越"果断"；**任何档位都不用匀速**。
  final Curve curve;

  /// **大体积动画**（整页 / 半页）统一用的"快速起步"曲线：
  /// 起步快、收尾柔，观感更灵动。
  final Curve largeCurve;

  /// **收尾曲线**（"Q弹"基础版）：只有**拉满档**才带轻微回弹
  /// （`Curves.easeOutBack`），其余档位都是纯减速、不回弹。
  ///
  /// 注意：回弹只作用在**位移 / 缩放**上；透明度插值必须单调，绝不回弹。
  final Curve settleCurve;

  /// 物理弹簧 · 刚度（质量固定为 1）：越大越"紧致"、收得越快。
  /// 档位 `0` 为 0（无弹簧）。
  final double springStiffness;

  /// 物理弹簧 · 阻尼：越小越"弹"（回弹 / 振荡越明显）。
  final double springDamping;

  /// 物理弹簧描述；档位 `0`（无动画）返回 `null`。
  SpringDescription? get spring => springStiffness <= 0
      ? null
      : SpringDescription(
          mass: 1,
          stiffness: springStiffness,
          damping: springDamping,
        );

  /// 全页过渡的**视觉窗口**：实际运动只占用路线时间线的前这么一小段
  /// （0.42 = 300ms 的路由里，真正"动"的只有约 126ms）。
  ///
  /// 这样**不必改动任何路由创建点**，也不会破坏系统的返回手势语义，
  /// 但肉眼观感快一倍以上。
  final double transitionWindow;

  /// 切 tab 的滑动时长。
  final Duration shellDuration;

  /// 切 tab 的位移比例。
  final double shellOffset;

  /// 整页 / 半页内容切换（loading → data）时长。
  final Duration stateSwapDuration;

  /// 整页翻页（引导页）时长。
  final Duration pageViewDuration;

  /// 半页弹层（底部面板）时长。
  final Duration sheetDuration;

  /// 是否允许动画。
  bool get animates => level > 0;

  /// 是否允许缩放类效果（整页 / 整项缩放会触发重新光栅化）。
  bool get hasScale => revealScaleFrom < 1 || transitionScaleFrom < 1;

  /// 是否允许模糊。
  bool get hasBlur => blurSigma > 0;

  /// 逐档单调：本档是否**不比** [other] 更重（时长更短 / 位移更小 / 项数更少）。
  ///
  /// 用它把"降档 = 降质量"钉成测试。
  bool isNotHeavierThan(OgLOAnimQuality other) =>
      fast <= other.fast &&
      medium <= other.medium &&
      slow <= other.slow &&
      staggerStep <= other.staggerStep &&
      staggerMaxIndex <= other.staggerMaxIndex &&
      (!revealAll || other.revealAll) &&
      revealOffset <= other.revealOffset &&
      revealScaleFrom >= other.revealScaleFrom &&
      transitionOffset <= other.transitionOffset &&
      transitionScaleFrom >= other.transitionScaleFrom &&
      blurSigma <= other.blurSigma &&
      transitionWindow <= other.transitionWindow &&
      shellDuration <= other.shellDuration &&
      shellOffset <= other.shellOffset &&
      stateSwapDuration <= other.stateSwapDuration &&
      pageViewDuration <= other.pageViewDuration &&
      sheetDuration <= other.sheetDuration;

  /// 档位 → 质量表（**唯一事实来源**）。
  static OgLOAnimQuality of(int level) {
    switch (level) {
      case 1:
        return const OgLOAnimQuality(
          level: 1,
          fast: Duration(milliseconds: 90),
          medium: Duration(milliseconds: 120),
          slow: Duration(milliseconds: 160),
          staggerStep: Duration(milliseconds: 12),
          staggerMaxIndex: 3,
          revealAll: false, // 只覆盖主要区域 + 前 3 项（最保守）
          revealOffset: 0,
          revealScaleFrom: 1,
          transitionOffset: 0.012,
          transitionScaleFrom: 1,
          blurSigma: 0,
          // 自然减速（ease-out 阶梯）：**绝不用匀速**——匀速是"机械/死板"的根源。
          curve: Curves.easeOut,
          largeCurve: Curves.easeOutCubic,
          settleCurve: Curves.easeOut,
          springStiffness: 1225,
          springDamping: 70, // ζ=1.00：临界阻尼，不振荡（最保守）
          transitionWindow: 0.42,
          shellDuration: Duration(milliseconds: 110),
          shellOffset: 0.02,
          stateSwapDuration: Duration(milliseconds: 110),
          pageViewDuration: Duration(milliseconds: 160),
          sheetDuration: Duration(milliseconds: 130),
        );
      case 2:
        return const OgLOAnimQuality(
          level: 2,
          fast: Duration(milliseconds: 130),
          medium: Duration(milliseconds: 170),
          slow: Duration(milliseconds: 220),
          staggerStep: Duration(milliseconds: 24),
          staggerMaxIndex: 8,
          revealAll: true, // 每个控件都动（最简：纯淡入）
          revealOffset: 0,
          revealScaleFrom: 1,
          transitionOffset: 0.03,
          transitionScaleFrom: 0.99,
          blurSigma: 0,
          curve: Curves.easeOutCubic,
          largeCurve: Curves.easeOutQuart,
          settleCurve: Curves.easeOutCubic,
          springStiffness: 1024,
          springDamping: 51, // ζ≈0.80：轻微回弹
          transitionWindow: 0.55,
          shellDuration: Duration(milliseconds: 150),
          shellOffset: 0.035,
          stateSwapDuration: Duration(milliseconds: 140),
          pageViewDuration: Duration(milliseconds: 200),
          sheetDuration: Duration(milliseconds: 160),
        );
      case 3:
        return const OgLOAnimQuality(
          level: 3,
          fast: Duration(milliseconds: 170),
          medium: Duration(milliseconds: 230),
          slow: Duration(milliseconds: 290),
          staggerStep: Duration(milliseconds: 36),
          staggerMaxIndex: 16,
          revealAll: true, // 每个控件都动（且效果拉满）
          revealOffset: 0.04,
          revealScaleFrom: 0.985,
          transitionOffset: 0.05,
          transitionScaleFrom: 0.975,
          blurSigma: 6,
          curve: Curves.easeOutQuart,
          largeCurve: Curves.easeOutQuint,
          settleCurve: Curves.easeOutBack,
          springStiffness: 784,
          springDamping: 35, // ζ≈0.63：回弹最明显（拉满档）
          transitionWindow: 0.7,
          shellDuration: Duration(milliseconds: 190),
          shellOffset: 0.05,
          stateSwapDuration: Duration(milliseconds: 180),
          pageViewDuration: Duration(milliseconds: 260),
          sheetDuration: Duration(milliseconds: 200),
        );
      case 0:
      default:
        return const OgLOAnimQuality(
          level: 0,
          fast: Duration.zero,
          medium: Duration.zero,
          slow: Duration.zero,
          staggerStep: Duration.zero,
          staggerMaxIndex: 0,
          revealAll: false,
          revealOffset: 0,
          revealScaleFrom: 1,
          transitionOffset: 0,
          transitionScaleFrom: 1,
          blurSigma: 0,
          curve: Curves.linear,
          largeCurve: Curves.linear,
          settleCurve: Curves.linear,
          springStiffness: 0,
          springDamping: 0,
          transitionWindow: 0,
          shellDuration: Duration.zero,
          shellOffset: 0,
          stateSwapDuration: Duration.zero,
          pageViewDuration: Duration.zero,
          sheetDuration: Duration.zero,
        );
    }
  }
}

/// 动效策略：把设置里的档位翻译成控件层能直接用的值。
abstract final class OgLMotion {
  /// 是否关闭动效。
  ///
  /// 档位 `0` 强制关闭；其余档位尊重系统"减少动效"与旧键 [OgLSettings.reduceMotion]。
  static bool disableAnimations(MediaQueryData query, OgLSettings settings) {
    if (settings.motionLevel <= 0) {
      return true;
    }
    return query.disableAnimations || settings.reduceMotion;
  }

  /// 页面过渡主题（按档位质量生成）。
  ///
  /// ## 为什么不用整页缩放（5.0 的结论）
  /// Flutter 默认过渡是**整页缩放 + 位移 + 淡入**（`ZoomPageTransitionsBuilder`）：
  /// 缩放要求**整页**在过渡期间反复重新光栅化 —— 页面越重越卡，
  /// 而小控件动画不受影响，于是表现为"只有页面过渡卡"。
  ///
  /// ## 5.2：按档位给**质量**
  /// - 位移距离逐档增大（`0.012 → 0.035 → 0.06`）；
  /// - **只有拉满档**允许 0.99 的轻微缩放，且同样包在 `RepaintBoundary` 里；
  /// - 过渡始终包 `RepaintBoundary`：过渡期间只重合成、不重绘页面内容。
  ///
  /// ## 7.4.1：**有界**记忆化
  /// 档位只有 `0–3` 四个值，这里为它们各缓存一份过渡主题（**最多 4 项，
  /// 只增到 4 就停**——它不是"随时间累积"的缓存）。这样 `ThemeData` 重建时
  /// 不会每次都新造一批过渡构建器对象（`ThemeData` 比较过渡主题时也才能命中
  /// 同一个实例）。**越界档位一律现算、不写缓存**：缓存规模与档位表的语义都
  /// 不变（`OgLOAnimQuality.of(level)` 对越界值的处理保持原样）。
  static final Map<int, PageTransitionsTheme> _transitionCache =
      <int, PageTransitionsTheme>{};

  /// 缓存规模上限（档位 `0–3`），仅用于自检与注释说明。
  static const int transitionCacheLimit = 4;

  static PageTransitionsTheme pageTransitions(int level) {
    final bool cacheable = level >= 0 && level < transitionCacheLimit;
    if (cacheable) {
      final PageTransitionsTheme? hit = _transitionCache[level];
      if (hit != null) {
        return hit;
      }
    }
    final OgLOAnimQuality quality = OgLOAnimQuality.of(level);
    final PageTransitionsBuilder builder = level <= 0
        ? const _OgLInstantTransitionsBuilder()
        : _OgLSlideFadeTransitionsBuilder(
            offset: quality.transitionOffset,
            scaleFrom: quality.transitionScaleFrom,
            curve: quality.largeCurve,
            window: quality.transitionWindow,
          );
    final PageTransitionsTheme built = PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        for (final TargetPlatform platform in TargetPlatform.values)
          platform: builder,
      },
    );
    if (cacheable) {
      _transitionCache[level] = built;
    }
    return built;
  }
}

/// 即时过渡：不做任何动画（档位 0）。
class _OgLInstantTransitionsBuilder extends PageTransitionsBuilder {
  /// 创建。
  const _OgLInstantTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// 统一页面过渡：淡入（+ 可选轻微缩放）+ 可选轻位移，**强制 `RepaintBoundary`**。
class _OgLSlideFadeTransitionsBuilder extends PageTransitionsBuilder {
  /// 创建。
  ///
  /// 注意：本类**不是** `const` 构造 —— 它缓存两条"被动曲线求值器"
  ///（见 [_movedTween]）；实例本身由 [OgLMotion.pageTransitions] 的**有界**
  /// 缓存在每个档位上复用一份。
  _OgLSlideFadeTransitionsBuilder({
    required this.offset,
    required this.scaleFrom,
    required this.curve,
    required this.window,
  });

  /// 起始垂直位移（占页高比例；0 = 不位移）。
  final double offset;

  /// 起始缩放（1 = 不缩放；仅拉满档 < 1）。
  final double scaleFrom;

  /// 缓动。
  final Curve curve;

  /// 视觉窗口（占路线时间线的比例）：运动在 `window` 处就已结束、随后保持。
  final double window;

  /// 视觉窗口的终点（`window` 越界时按"整条时间线"处理）。
  double get _windowEnd => window <= 0 || window > 1 ? 1.0 : window;

  /// **被动**曲线求值器（`CurveTween`）。
  ///
  /// `CurveTween.animate(parent)` 返回 `_AnimatedEvaluation`：它只在 `value`
  /// 上做一次求值转发，**不给 parent 注册任何监听**（`AnimationWithParentMixin`
  /// 只是把 add/removeListener 转发出去）。因此它可以在多次
  /// [buildTransitions] 之间安全复用——这正是**取代 `CurvedAnimation`** 的
  /// 关键（原因见 [buildTransitions] 的注释）。
  ///
  /// 这两条曲线与"路线"无关（只由档位决定），所以在实例上算一次即可。
  late final CurveTween _movedTween =
      CurveTween(curve: Interval(0.0, _windowEnd, curve: curve));

  /// 淡入比落位再早一点结束（"先亮起来、再落定"），观感更灵动。
  late final CurveTween _fadedTween =
      CurveTween(curve: Interval(0.0, _windowEnd * 0.8, curve: Curves.easeOut));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 把"实际运动"压进路线时间线的前 window 段：观感快、但不改路由时长，
    // 也不影响系统返回手势的语义。
    //
    // ★ 这里**刻意不用 `CurvedAnimation`**（7.4.1 资源修复）：
    // `CurvedAnimation` 的构造函数会给 `parent` 注册一个 `statusListener`，
    // 而**只有 `dispose()` 才会把它摘掉**（见 Flutter
    // `packages/flutter/lib/src/animation/animations.dart`：构造函数里
    // `parent.addStatusListener(_updateCurveDirection)`，`dispose()` 里
    // `parent.removeStatusListener(...)`）。而 `buildTransitions` 会被框架
    // **反复调用**——`_ModalScopeState.build` 把它放进路线动画的
    // `ListenableBuilder`（见 Flutter `packages/flutter/lib/src/widgets/routes.dart`
    // 的 `_buildFlexibleTransitions` 调用点），于是**过渡期间每帧重建一次**，
    // 路线状态（canPop / offstage / userGestureInProgress…）变化时也会重建。
    // 每帧新造两个从不 `dispose` 的 `CurvedAnimation`，等于给这条路由的
    // `AnimationController` 每帧挂一个**永远不会摘除**的死监听者（一次翻页
    // ≈ 18 帧 ≈ 36 个，翻得越多挂得越多；它们在每次状态变化时被逐个唤醒，
    // 也让这一整条对象链迟迟无法回收）。这是"反复翻页后动画越来越卡、
    // 而且不随时间回落"的一处**每帧分配 + 监听累积**来源。
    //
    // 换成 `CurveTween(...).animate(animation)`（见 [_movedTween]）后：不注册
    // 监听、不留死对象；曲线取值与 `CurvedAnimation`（未传 `reverseCurve` 时）
    // **逐点一致**，所以各档位的窗口 / 位移 / 缩放 / 曲线观感零变化。
    final Animation<double> moved = _movedTween.animate(animation);
    final Animation<double> faded = _fadedTween.animate(animation);
    Widget result = child;
    if (offset > 0) {
      result = SlideTransition(
        position: Tween<Offset>(begin: Offset(0, offset), end: Offset.zero)
            .animate(moved),
        child: result,
      );
    }
    if (scaleFrom < 1) {
      result = ScaleTransition(
        scale: Tween<double>(begin: scaleFrom, end: 1).animate(moved),
        child: result,
      );
    }
    return RepaintBoundary(
      child: FadeTransition(opacity: faded, child: result),
    );
  }
}

/// 动效档位作用域：把当前档位暴露给控件层。
///
/// 挂点：`OgLApp` 的 `builder`（位于 `MaterialApp` 之内，随设置变化重建）。
/// 控件据此读 [OgLOAnimQuality]（时长 / 位移 / 缩放 / 错峰项数都随档位变化）。
class OgLMotionScope extends InheritedWidget {
  /// 创建作用域。
  const OgLMotionScope({required this.level, required super.child, super.key});

  /// 当前动效档位（0–3）。
  final int level;

  /// 读取当前档位（未挂载作用域时按 1 处理）。
  static int levelOf(BuildContext context) {
    final OgLMotionScope? scope =
        context.dependOnInheritedWidgetOfExactType<OgLMotionScope>();
    return scope?.level ?? 1;
  }

  @override
  bool updateShouldNotify(OgLMotionScope oldWidget) => oldWidget.level != level;
}
