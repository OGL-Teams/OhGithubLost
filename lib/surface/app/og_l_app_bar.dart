/// L3 展示级 · **滚动渐变融合 AppBar**（统一应用栏，走设计令牌）。
///
/// ## 它解决什么（MD2 形态）
/// MD2 下 AppBar 边界 = elevation 4 真投影 + surface→surfaceContainerHighest 的
/// **连续色阶插值**：顶部与页面同色（完全融合），滚深渐变到可辨识的
/// surfaceContainerHighest，全程无硬边。`scrolledUnderElevation`/`surfaceTint`
/// 等 M3 语义已随迁移移除。
///
/// ## 与主题令牌的关系
/// `theme.dart` 的 `appBarTheme.backgroundColor = surface`、
/// `elevation = 4`（真投影）。本组件叠加的连续插值两端色
/// （surface / surfaceContainerHighest）都来自 `ColorScheme`。
///
/// ## 滚动进度来源（G-02 / B-01：无 Primary 兜底）
/// 本项目**没有任何地方**注入 `PrimaryScrollController`（Scaffold 只读不写），
/// 该兜底分支是死代码——已删除。两条路径：
/// 1. **默认**：M2 下 AppBar 的 elevation 阴影本身提供滚动边界，
///    未接控制器的页面也有稳定的顶栏分隔；
/// 2. **显式直连**：body 自建 ScrollController 的页把它传给
///    `scrollController:`，获得连续色阶插值（dashboard 已如此）。
/// - 节流：进度写入 `ValueNotifier`，只让包着背景色的那层重建（1% 步进）。
/// - 取竖直 position、减 minScrollExtent，并对 pixels 做有界夹紧。
library;

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

  /// 连续插值滚完的像素距离。
  static const double _kRange = 120;

  /// 通知步进（1% = 颜色变化肉眼可辨的最小单位，避免逐帧重建）。
  static const double _kStep = 0.01;

  /// 标题。
  final String title;

  /// 右侧动作。
  final List<Widget>? actions;

  /// 底部（如 TabBar）。
  final PreferredSizeWidget? bottom;

  /// 页面滚动控制器（可选，显式直连路径）。
  ///
  /// body 用自建 ScrollController 的页面把它传进来即可获得连续色阶插值；
  /// 不传时由 M3 原生 `scrolledUnderElevation` 提供滚动态边界（所有页面）。
  /// 本项目**不存在** PrimaryScrollController 注入，不要依赖它。
  final ScrollController? scrollController;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  State<OgLAppBar> createState() => _OgLAppBarState();
}

class _OgLAppBarState extends State<OgLAppBar> {
  ScrollController? _controller;

  /// 连续插值进度 0..1；只在跨过 [_kStep] 台阶时通知。
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // ★ G-02：只认显式传入的控制器；删除 PrimaryScrollController.maybeOf
    //   兜底假设（本项目从未注入 Primary，那条分支是死代码）。
    _controller = widget.scrollController;
    _controller?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant OgLAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scrollController, widget.scrollController)) {
      _controller?.removeListener(_onScroll);
      _controller = widget.scrollController;
      _controller?.addListener(_onScroll);
      if (_controller == null && _progress.value != 0) {
        _progress.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onScroll);
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ScrollController? controller = _controller;
    double next = 0;
    if (controller != null &&
        controller.hasClients &&
        controller.positions.isNotEmpty) {
      // ★ B-15：取竖直 position、减 minScrollExtent（消除绝对偏移），
      //   pixels 有界夹紧，避免异常负值/超大值。
      for (final ScrollPosition position in controller.positions) {
        if (position.axis == Axis.vertical && position.hasPixels) {
          final double offset = (position.pixels - position.minScrollExtent)
              .clamp(0.0, 1 << 20)
              .toDouble();
          next = (offset / OgLAppBar._kRange).clamp(0.0, 1.0).toDouble();
          break;
        }
      }
    }
    if ((next - _progress.value).abs() >= OgLAppBar._kStep ||
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
        final double progress = t.clamp(0.0, 1.0);
        final Color merged = Color.lerp(
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainerHighest,
          progress,
        )!;
        return AppBar(
          title: Text(widget.title),
          actions: widget.actions,
          bottom: widget.bottom,
          // ★ G-02 + MD2：elevation 4 真投影承担滚动/常态边界（M3 tonal
          //   体系已移除）；surfaceTintColor 关闭避免滚动染色。
          elevation: 4,
          backgroundColor: merged,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: theme.appBarTheme.titleTextStyle,
        );
      },
    );
  }
}
