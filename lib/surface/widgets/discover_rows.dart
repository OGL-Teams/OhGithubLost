/// L3 展示级 · 发现页的**可测**子组件（动态行 / Issues 筛选胶囊行）。
///
/// ## 为什么单独抽出来
/// 这两个部件都踩过同一个坑：**它们在真机上出过布局事故**，而事故原因
/// 只有把组件单独渲染到测试里才看得见：
///
/// 1. 动态行原来用 `Row(crossAxisAlignment: CrossAxisAlignment.stretch)`
///    撑满行高。纵向 ListView 的子项高度是**无界**的（maxHeight=infinity），
///    stretch 于是把 4px 状态竖条拉到无限高：debug 下抛
///    "BoxConstraints forces an infinite height"，
///    **release 下断言被剥掉 → 整行完全不绘制**，
///    动态 tab 于是整页空白（连空态与转圈都没有——这正是真机看到的现象）。
///    现在状态竖条用**左侧边框**实现：宽度恒定、高度跟随内容，
///    视觉等价且不再依赖无界高度。
/// 2. Issues 筛选胶囊行原来写死 `SizedBox(height: 32)`，而内部 ListView
///    的上下 padding 就吃掉 16dp，标签文字被挤到胶囊背景之外
///    （真机实测：胶囊底色 y=319..341，文字 y=352..374）。
///    现在改用 `SingleChildScrollView + Row`，高度由内容决定。
///
/// 两者都在 `test/surface/ui_regression_test.dart` 里有回归锁。
library;

import 'package:flutter/material.dart';

import '../util/og_l_space.dart';

/// 动态（通知流）的一行：左侧 4px 状态竖条（未读点亮 primary / 已读同背景，
/// 宽度恒定故行不跳动）+ 一行标题 + 一行元信息。
class OgLFeedRow extends StatelessWidget {
  /// 创建。
  const OgLFeedRow({
    required this.unread,
    required this.title,
    required this.meta,
    required this.onTap,
    super.key,
  });

  /// 是否未读（决定状态竖条是否点亮）。
  final bool unread;

  /// 标题（单行省略）。
  final String title;

  /// 元信息行（仓库 · 类型 · 相对时间）。
  final String meta;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color:
                unread ? theme.colorScheme.primary : theme.colorScheme.surface,
            width: OgLSpace.xxs,
          ),
        ),
      ),
      child: Material(
        color: theme.colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OgLSpace.md,
              vertical: OgLSpace.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: unread
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: OgLSpace.xxs),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

/// Issues 分类筛选行：一排 [FilterChip]，**高度由内容决定**（不写死）。
///
/// 此前写死 32dp 高 + 内部 ListView 的上下 padding，把标签文字挤到了
/// 胶囊背景之外。现在用横向 `SingleChildScrollView` + `Row`：
/// 高度自适应、横向可滑、文字始终落在胶囊内。
class OgLIssuesFilterChips extends StatelessWidget {
  /// 创建。
  const OgLIssuesFilterChips({
    required this.selected,
    required this.labels,
    required this.onSelect,
    super.key,
  });

  /// 当前选中的下标。
  final int selected;

  /// 各档文案。
  final List<String> labels;

  /// 选中回调（传入新下标）。
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OgLSpace.lg,
          vertical: OgLSpace.sm,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int index = 0; index < labels.length; index++)
                Padding(
                  padding: const EdgeInsets.only(right: OgLSpace.sm),
                  child: FilterChip(
                    key: ValueKey<String>('issues-chip-$index'),
                    label: Text(labels[index]),
                    selected: selected == index,
                    onSelected: (bool isSelected) {
                      if (isSelected) {
                        onSelect(index);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      );
}
