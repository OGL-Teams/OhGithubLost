/// L3 展示级 · 设置页通用零件（分组卡片 / 条目行 / 选择弹窗）。
///
/// ## 为什么单独抽出来
/// 设置页原先「一张卡片一个分组、且全部常展开」：一屏里能看到的**可点条目**
/// 不到 3 个（其余位置被分组标题、长说明与平铺的色板占满）。重做后统一为
/// 三种固定行型 + 一种分组卡片：
///
/// - [OgLSettingsGroup]：**可折叠**分组卡片。折叠状态由页面持有（并落盘），
///   本组件只管"长什么样"与展开动画（时长 / 曲线跟动效档位）；
/// - [OgLSettingsChoiceTile]：**选择行**（右侧显示当前值，点开弹窗选）；
///   选择项不再平铺成色板 / 分段按钮 —— 那是把一屏挤成两屏的主因；
/// - [OgLSettingsSwitchRow]：开关行；
/// - [OgLSettingsSliderRow]：滑杆行（草稿值在自己 State 里，拖动不重建整页）；
/// - [OgLSettingsDangerCard]：危险区卡片（与普通条目在**颜色 + 间距**上拉开）。
///
/// ## 依赖纪律
/// 本文件只依赖 Flutter 框架与展示层的动效档位（[OgLAnim]），
/// 不认识任何业务对象 —— 页面把值传进来、把回调带回去。
library;

import 'package:flutter/material.dart';

import '../../app/animations.dart';
import '../../app/overlays.dart';
import '../../util/og_l_radius.dart';
import '../../util/og_l_space.dart';

/// 行内统一内边距：左右**相等**（此前 start 16 / end 12 不对称，
/// 同页看起来像歪的）。设置 / 关于 / 用户页共用这一个值。
const EdgeInsetsDirectional kOgLSettingsRowPadding =
    EdgeInsetsDirectional.symmetric(
        horizontal: OgLSpace.lg, vertical: OgLSpace.md);

/// 选项之间的垂直间距（行与行之间只留 1px 分隔线，不再叠 SizedBox）。
/// 选择弹窗内每个选项的上下内边距与此同源。
const double kOgLSettingsRowGap = OgLSpace.md;

/// 子项缩进台阶（"依赖某开关才出现"的条目用）。
abstract final class OgLSettingsIndent {
  /// 一级子项缩进量。
  static const double step = 16;
}

/// 一行选择项（[ogLShowSettingsChoice] 的入参）。
@immutable
class OgLSettingsChoice<T> {
  /// 创建。
  const OgLSettingsChoice({
    required this.value,
    required this.label,
    this.hint,
    this.leading,
  });

  /// 该选项代表的值。
  final T value;

  /// 主标签。
  final String label;

  /// 补充说明（可选，如动效档位的语义解释）。
  final String? hint;

  /// 前置图形（可选，如主题色的色点）。
  final Widget? leading;
}

/// 打开"选择一个值"弹窗；返回选中值（取消 / 点外部返回 `null`）。
///
/// 弹窗动效与设置页其它弹窗同源（[OgLAnim.fast] + 档位曲线；档位 0 为零时长）。
Future<T?> ogLShowSettingsChoice<T>({
  required BuildContext context,
  required String title,
  required List<OgLSettingsChoice<T>> options,
  required T current,
}) =>
    ogLShowDialog<T>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(title),
        children: <Widget>[
          for (final OgLSettingsChoice<T> option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option.value),
              padding: const EdgeInsets.symmetric(
                  horizontal: OgLSpace.lg, vertical: OgLSpace.md),
              child: Row(
                children: <Widget>[
                  if (option.leading != null) ...<Widget>[
                    option.leading!,
                    const SizedBox(width: OgLSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(option.label),
                        if (option.hint != null)
                          Padding(
                            padding: const EdgeInsets.only(top: OgLSpace.xxs),
                            child: Text(
                              option.hint!,
                              style:
                                  Theme.of(dialogContext).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 当前项打勾：弹窗与行内显示的是同一个值，选了之后行内立刻跟上。
                  if (option.value == current)
                    const Icon(Icons.check, size: OgLIconSize.md),
                ],
              ),
            ),
        ],
      ),
    );

/// 设置项分组：**平铺的条目列表**。
///
/// ★ 单层平铺（批 12）：本类不再提供卡片气泡，也不再有可折叠的头部。
/// 子页的 AppBar 标题即分类名，组内条目自带分隔线；根页只列分类入口。
class OgLSettingsGroup extends StatelessWidget {
  /// 创建。
  const OgLSettingsGroup({
    required this.children,
    super.key,
  });

  /// 组内条目（自带分隔线）。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
}

/// 选择行：标题 + （可选）说明 + 当前值 + 箭头；点开 [ogLShowSettingsChoice]。
class OgLSettingsChoiceTile<T> extends StatelessWidget {
  /// 创建。
  const OgLSettingsChoiceTile({
    required this.title,
    required this.options,
    required this.current,
    required this.onSelected,
    this.subtitle,
    this.leading,
    this.valueLabel,
    this.indent = 0,
    this.dense = false,
    this.dialogTitle,
    this.onTap,
    super.key,
  });

  /// 行标题（同时作为弹窗标题）。
  final String title;

  /// 说明（一行；超长省略 —— 说明文字不该把条目挤出屏幕）。
  final String? subtitle;

  /// 前置图标。
  final Widget? leading;

  /// 可选值。
  final List<OgLSettingsChoice<T>> options;

  /// 当前值。
  final T current;

  /// 当前值的展示文本（右对齐）。
  final String? valueLabel;

  /// 选中回调（值未变化时不触发）。
  final ValueChanged<T> onSelected;

  /// 缩进台阶（子项用）。
  final double indent;

  /// 紧凑行（子项用）。
  final bool dense;

  /// 选择弹窗的标题（默认与 [title] 相同）。
  ///
  /// 只在"行标题"与"弹窗标题"本就该不同时使用（如行写「DNS 服务器」、
  /// 弹窗写「选择 DNS 服务器」）——**不新增文案**，沿用原有措辞。
  final String? dialogTitle;

  /// 覆盖默认的点开行为（默认：弹出 [options] 选择）。
  ///
  /// 只在"没得选 / 需要前置检查"时使用（如 DNS 服务器列表为空 → 先给一句提示，
  /// 而不是弹一个空气泡）；正常情况留 `null`，用内置弹窗。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: dense,
      contentPadding: kOgLSettingsRowPadding.copyWith(
        start: kOgLSettingsRowPadding.start + indent,
      ),
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall,
              // ★ 批 9 · B21：大字体下保留两行，避免整句被截。
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (valueLabel != null)
            Text(
              valueLabel!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: OgLSpace.xxs),
          const Icon(Icons.chevron_right, size: OgLIconSize.md),
        ],
      ),
      onTap: onTap ??
          () async {
            final T? picked = await ogLShowSettingsChoice<T>(
              context: context,
              title: dialogTitle ?? title,
              options: options,
              current: current,
            );
            if (!context.mounted || picked == null || picked == current) {
              return;
            }
            onSelected(picked);
          },
    );
  }
}

/// 开关行（与选择行同内边距、同缩进语义）。
/// 可点击的动作行（带缩进层级）：字体管理入口等"点一下做一件事"的行。
@immutable
class OgLSettingsActionRow extends StatelessWidget {
  /// 创建。
  const OgLSettingsActionRow({
    required this.title,
    required this.onTap,
    this.icon,
    this.indent = 0,
    this.dense = false,
    super.key,
  });

  /// 标题。
  final String title;

  /// 点击回调。
  final VoidCallback onTap;

  /// 前置图标（可空）。
  final IconData? icon;

  /// 左侧缩进（层级）。
  final double indent;

  /// 紧凑模式。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: ListTile(
        dense: dense,
        // 与开关行 / 选择行同一内边距常量：同一组内不再出现 16/12 与 16/16
        // 两种视觉；缩进由外层 Padding 承担，内层保持标准起始边。
        contentPadding: kOgLSettingsRowPadding,
        leading: icon == null ? null : Icon(icon),
        title: Text(title, style: theme.textTheme.bodyLarge),
        trailing: const Icon(Icons.chevron_right, size: OgLIconSize.lg),
        onTap: onTap,
      ),
    );
  }
}

class OgLSettingsSwitchRow extends StatelessWidget {
  /// 创建。
  const OgLSettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.indent = 0,
    this.dense = false,
    super.key,
  });

  /// 标题。
  final String title;

  /// 说明（一行；超长省略）。
  final String? subtitle;

  /// 前置图标。
  final Widget? leading;

  /// 当前值。
  final bool value;

  /// 变更回调。
  final ValueChanged<bool> onChanged;

  /// 缩进台阶（子项用）。
  final double indent;

  /// 紧凑行（同一分节里成组的子开关用）。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile(
      dense: dense,
      contentPadding: kOgLSettingsRowPadding.copyWith(
        start: kOgLSettingsRowPadding.start + indent,
      ),
      secondary: leading,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 一条滑块设置行（标题 + 当前值 + 拖动条）。
///
/// ## 为什么要单独抽出来
/// 拖动中的"草稿值"原本放在**整页** State 上：每动一帧整页 `setState` ——
/// 设置页很长，拖动一次要重建几十个卡片。草稿值放进本组件自己的 State 后，
/// 拖动只重建这一行；松手才 `onCommit`（落盘一次，不写盘风暴）。
class OgLSettingsSliderRow extends StatefulWidget {
  /// 创建。
  const OgLSettingsSliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onCommit,
    this.divisions,
    this.indent = 0,
    super.key,
  });

  /// 行标题。
  final String title;

  /// 外部真值（未拖动时展示）。
  final double value;

  /// 最小值。
  final double min;

  /// 最大值。
  final double max;

  /// 当前值 → 展示文本（跟随草稿值实时变化）。
  final String Function(double value) display;

  /// 松手后落盘（只调一次）。
  final ValueChanged<double> onCommit;

  /// 分档数（可选）。
  final int? divisions;

  /// 缩进台阶（子项用）。
  final double indent;

  @override
  State<OgLSettingsSliderRow> createState() => _OgLSettingsSliderRowState();
}

class _OgLSettingsSliderRowState extends State<OgLSettingsSliderRow> {
  /// 拖动中的草稿值（松手清空）。
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double current =
        (_draft ?? widget.value).clamp(widget.min, widget.max).toDouble();
    // 标题 / 当前值 / 滑块合成**一个**无障碍节点：屏幕阅读器读一次
    // "标题 + 当前值"，滑动时也不用在三个节点之间跳（MergeSemantics）。
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: kOgLSettingsRowPadding.start + widget.indent,
          end: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.labelLarge),
                ),
                Text(widget.display(current), style: theme.textTheme.bodySmall),
              ],
            ),
            Slider(
              value: current,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (double v) => setState(() => _draft = v),
              onChangeEnd: (double v) {
                setState(() => _draft = null);
                widget.onCommit(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 危险区卡片：与普通条目**在颜色与间距上双重拉开**。
///
/// 只放"会造成损失、需要二次确认"的操作（当前是"重置设置"）：
/// - 颜色：`errorContainer` / `error`（页面里错误提示已用同一套色，不引入新语言）；
/// - 间距：调用方在它前面留出额外空白 + 一条分隔线（见设置页 build）。
class OgLSettingsDangerCard extends StatelessWidget {
  /// 创建。
  const OgLSettingsDangerCard({
    required this.title,
    required this.actionTitle,
    required this.actionSubtitle,
    required this.onTap,
    this.actionIcon = Icons.settings_backup_restore,
    super.key,
  });

  /// 卡片内标题（"危险区"）。
  final String title;

  /// 危险条目标题（如"重置设置"）。
  final String actionTitle;

  /// 危险条目说明（后果一句话，如"恢复外观 / 代码 / 网络的默认值"）。
  final String actionSubtitle;

  /// 危险条目前置图标。
  final IconData actionIcon;

  /// 点击回调（二次确认由调用方负责）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        ListTile(
          contentPadding: kOgLSettingsRowPadding,
          leading: Icon(
            actionIcon,
            color: theme.colorScheme.error,
          ),
          title: Text(
            actionTitle,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: Text(
            actionSubtitle,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: onTap,
        ),
      ],
    );
  }
}
