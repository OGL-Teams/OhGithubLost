/// L3 展示级 · 下拉刷新的**唯一入口**（档位感知）。
///
/// ## 为什么要包一层
/// 报告 B5 点名：全仓 10 处裸 `RefreshIndicator` 各自写
/// `onRefresh` / `child`，规格容易分叉；更重要的是「档位 0 / 系统减少
/// 动效时功能是否被砍」没有一处能验证。
///
/// 这里明确两件事：
/// 1. **降档 = 降质量，不砍功能**：`OgLAnim.enabled(context)` 为 false
///    时仍然返回 [RefreshIndicator]，`onRefresh` 照常可触发；只是把
///    `strokeWidth` 与 `displacement` 收敛到静态、避免大幅位移。
/// 2. 其余档位沿用 Material 默认进度指示器（它的动画由框架内部管理，
///    没有公开的 duration 参数，不能也不该硬塞 `OgLAnim.fast`）。
///
/// 所有页面统一改用它，规格只有这一处定义。
library;

import 'package:flutter/material.dart';

import 'animations.dart';

/// 档位感知的下拉刷新容器。
class OgLRefreshIndicator extends StatelessWidget {
  /// 创建。
  const OgLRefreshIndicator({
    required this.onRefresh,
    required this.child,
    super.key,
  });

  /// 刷新回调（必须返回 Future）。
  final RefreshCallback onRefresh;

  /// 可滚动的子树。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool animated = OgLAnim.enabled(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      // 档位 0 / 减少动效：只去掉「下拉时的大幅位移」，
      // 刷新功能本身完整保留（绝不 return child 了事）。
      displacement: animated ? 40.0 : 0.0,
      strokeWidth: animated ? 2.0 : 3.0,
      child: child,
    );
  }
}
