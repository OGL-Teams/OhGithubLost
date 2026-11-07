/// L3 展示级 · **滚动渐变融合 AppBar**（统一应用栏，走设计令牌）。
///
/// ## 它解决什么（UI 细化）
/// Material 默认 AppBar 用 `scrolledUnderElevation` 加 surfaceTintColor——
/// 颜色是**阶跃**的，与页面背景之间有一条硬边。这里改为随滚动进度**连续
/// 插值**：顶部 → 与页面同色（surface，完全融合），滚深 → surfaceContainer
/// （可辨识的浮起感）。颜色全程渐变、无阶跃、无硬边。
///
/// ## 与主题令牌的关系
/// `theme.dart` 的 `appBarTheme.backgroundColor` 已统一为 `surface`
/// （融合基线）；本组件只是把"滚动浮起"做成**连续插值**——两端颜色
/// （surface / surfaceContainer）都来自 `ColorScheme`，不引入字面色。
///
/// ## 原理与边界
/// - `Scaffold` 的 body 通常是 `ListView` / `CustomScrollView`，其
///   PrimaryScrollController 由 Scaffold 注入；本组件用
///   `PrimaryScrollController.maybeOf` 拿到**同一条**控制器（与 body 共享）。
/// - body 用**自建** ScrollController 的页面拿不到偏移 → 恒融合（顶部态），
///   不报错、不闪变；TabBarView 多控制器页面同理恒融合。
/// - **节流（性能纪律）**：滚动事件不逐帧 `setState`——进度写入
///   `ValueNotifier`，只让 `ValueListenableBuilder` 包着的那层背景色重建；
///   且只在颜色**实际跨过台阶**时通知（1% 步进）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// 与页面背景滚动融合的应用栏。
class OgLAppBar extends StatefulWidget implements PreferredSizeWidget {
  /// 创建应用栏。
  const OgLAppBar({
    required this.title,
    this.actions,
    this.bottom,
    this.scrollController,
    super.key,
  });

  /// 标题。
  final String title;

  /// 右侧动作。
  final List<Widget>? actions;

  /// 底部（如 TabBar）。
  final PreferredSizeWidget? bottom;

  /// 页面滚动控制器（可选）。
  ///
  /// body 用自建 ScrollController 的页面**必须**把它传进来（此时
  /// PrimaryScrollController 不适用）；body 走 Primary 的页面留空即可。
  final ScrollController? scrollController;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  State<OgLAppBar> createState() => _OgLAppBarState();
}

class _OgLAppBarState extends State<OgLAppBar> {
  ScrollController? _primary;

  /// 渐变进度 0..1；只在跨过 [_kStep] 台阶时通知。
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// 120px 滚完渐变：短距离"快而稳"，长距离更从容。
  static const double _kRange = 120;

  /// 通知步进（1% = 颜色变化肉眼可辨的最小单位，避免逐帧重建）。
  static const double _kStep = 0.01;

  /// 渐变去抖（滚动惯性里的高频事件合并到帧末）。
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 优先用页面自建控制器（显式传入）；否则走 Primary（Scaffold 注入）。
    final ScrollController? explicit = widget.scrollController;
    final ScrollController? primary = PrimaryScrollController.maybeOf(context);
    final ScrollController? next = explicit ?? primary;
    if (!identical(_primary, next)) {
      _primary?.removeListener(_onScroll);
      _primary = next;
      _primary?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _primary?.removeListener(_onScroll);
    _debounce?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 惯性滚动里此回调每帧多次；合并到帧末一次计算 + 台阶判重，
    // 不逐帧 setState（整栏 AppBar 重建是能省则省的开销）。
    if (_debounce?.isActive ?? false) {
      return;
    }
    _debounce = Timer(Duration.zero, _applyProgress);
  }

  void _applyProgress() {
    final ScrollController? controller = _primary;
    double next = 0;
    if (controller != null &&
        controller.hasClients &&
        controller.positions.isNotEmpty) {
      final ScrollPosition position = controller.positions.first;
      if (position.hasPixels) {
        next = (position.pixels / _kRange).clamp(0.0, 1.0);
      }
    }
    if ((next - _progress.value).abs() >= _kStep ||
        (next == 0 && _progress.value != 0) ||
        (next == 1 && _progress.value != 1)) {
      _progress.value = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (BuildContext context, double t, Widget? child) {
        final Color merged = Color.lerp(
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainer,
          t,
        )!;
        return AppBar(
          title: Text(widget.title),
          actions: widget.actions,
          bottom: widget.bottom,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: merged,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: theme.appBarTheme.titleTextStyle,
        );
      },
    );
  }
}
