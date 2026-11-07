/// L3 展示级 · **滚动渐变融合 AppBar**。
///
/// ## 它解决什么
/// Material 默认 AppBar 在内容滚动时用 `scrolledUnderElevation` 加
/// surfaceTintColor——颜色是**阶跃**的，与页面背景之间有一条硬边。
/// 这里改为随滚动进度**连续插值**：0 → 与页面同色（融合），滚深 →
/// surfaceContainer（可辨识），颜色全程渐变、无硬边。
///
/// ## 原理
/// `Scaffold` 的 body 通常是 `ListView` / `CustomScrollView`，其
/// PrimaryScrollController 由 Scaffold 注入；本组件用
/// `PrimaryScrollController.maybeOf` 拿到**同一条**控制器（与 body 共享），
/// 直接监听偏移，不需要每个页面自己传 controller。
///
/// ## 用法
/// ```dart
/// appBar: OgLAppBar(title: _t('home')),
/// appBar: OgLAppBar(title: ..., bottom: TabBar(controller: _tab, ...)),
/// ```
///
/// ## 边界
/// - body 用**自建** ScrollController（不走 Primary）的页面拿不到偏移——
///   此时 AppBar 恒为融合态（与顶部同色），不报错、不闪变；
/// - TabBar 页（TabBarView 多控制器）同理：恒融合。这类页面本来就该
///   恒融合，因为 TabBarView 的滚动不属于 AppBar。
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// 与页面背景滚动融合的应用栏。
class OgLAppBar extends StatefulWidget implements PreferredSizeWidget {
  /// 创建应用栏。
  const OgLAppBar({required this.title, this.actions, this.bottom, super.key});

  /// 标题。
  final String title;

  /// 右侧动作。
  final List<Widget>? actions;

  /// 底部（如 TabBar）。
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  State<OgLAppBar> createState() => _OgLAppBarState();
}

class _OgLAppBarState extends State<OgLAppBar> {
  ScrollController? _primary;

  /// 渐变进度 0..1（120px 滚完；短距离看起来"快而稳"，长距离更从容）。
  static const double _kRange = 120;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ScrollController? next = PrimaryScrollController.maybeOf(context);
    if (!identical(_primary, next)) {
      _primary?.removeListener(_onScroll);
      _primary = next;
      _primary?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _primary?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    // 逐帧通知即可：插值后的颜色只在跨台阶时真正变化，
    // 但 setState 开销极小（只重建一个 AppBar），不做复杂节流。
    if (mounted) {
      setState(() {});
    }
  }

  double _progress() {
    final ScrollController? controller = _primary;
    if (controller == null || !controller.hasClients) {
      return 0; // 拿不到滚动 → 恒融合（见文件头"边界"）。
    }
    // 多视图（TabBarView 已切走等）取第一个可见位置。
    final ScrollPosition? position =
        controller.positions.isEmpty ? null : controller.positions.first;
    if (position == null || !position.hasPixels) {
      return 0;
    }
    return (position.pixels / _kRange).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double t = _progress();
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
  }
}
