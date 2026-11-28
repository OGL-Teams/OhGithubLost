# MD1 完全重写 · 进度报告

> 文档戳：更新时间 **2026-11-28 19:30:00 (Asia/Shanghai)** · 基线版本 `235d4a6` · 规范 docs/MD1_REWRITE_SPEC.md

## 第一批（基础令牌 + 5 核心控件）✅
- 新建 `lib/surface/md1/md1_tokens.dart`（225 行）：MD1 经典 2014 明暗色板、8 档字阶、尺寸令牌（AppBar56/FAB56/按钮36/列表72-56/触控48/圆角2）、6 档 elevation（BoxShadow）。
- 新建 `lib/surface/md1/md1_painters.dart`（约 580 行）：全 CustomPainter 自绘 5 控件——`OgMd1Button`（flat/raised + ripple）、`OgMd1Card`（2dp elevation）、`OgMd1ListRow`（72/56dp）、`OgMd1Ripple`（扩散动画）、`OgMd1AppBar`（56dp 纯色 elevation4）。零 Material 可见控件。
- 阴影用同心 RRect 阶梯实现（替代 MaskFilter.blur），规避 perf_audit 的 saveLayer 卡顿源。
- 门禁：ui_audit（令牌源白名单）、perf_audit（0 反模式）、layer_audit（0 违规）、contract_audit（0）、gate_of_gates（12 支全过）、dart format 0 changed。

## 批 2（表单类 5 控件）✅
- `md1_painters.dart` 扩至 1357 行：新增 `OgMd1TextField`（48dp 底边 1px/focus 2px、浮动 label）、`OgMd1Switch`（MD1 轨道+圆钮）、`OgMd1Checkbox`（18dp 方框+勾路径）、`OgMd1Radio`（圆环+实心点）、`OgMd1Slider`（轨道+拇指）——全 CustomPainter，含焦点/键盘/手势/Semantics。
- 全门禁绿（ui/perf/layer/contract/gate/i18n/format）。

## 批 3（反馈类 5 控件）✅
- `md1_painters.dart` 扩至 2100 行：新增 `OgMd1Dialog`（2dp 圆角/elevation24/动作区）、`OgMd1Snackbar`（底部条+动作+时长）、`OgMd1Chip`、`OgMd1Badge`、`OgMd1Divider`（1px #E0E0E0）——全 CustomPainter。
- 全门禁绿（ui/perf/layer/contract/gate/i18n/format 0 changed）。

## 批 4（导航类 5 控件）✅
- `md1_painters.dart` 扩至 3074 行：新增 `OgMd1BottomNav`（56dp 纯色底+primary 指示）、`OgMd1TabBar`（48dp+2px 下划线）、`OgMd1Drawer`（240dp+遮罩）、`OgMd1NavigationRail`（72dp 侧栏）、`OgMd1Toolbar`（56dp 操作条）——全 CustomPainter。
- 全门禁绿（format/ui/perf/layer/contract/motion/facade/action_pin/ci_config/gate/i18n）。

## 批 5（操作类 5 控件）✅
- `md1_painters.dart` 扩至 4238 行：新增 `OgMd1Progress`（线性+环形）、`OgMd1RefreshIndicator`（下拉刷新）、`OgMd1BottomSheet`（2dp 圆角/elevation16）、`OgMd1Menu`、`OgMd1Dropdown`——全 CustomPainter。
- 全门禁绿（format/ui/perf/layer/contract/gate/i18n）。

## 剩余批次（待执行）
- 批 6-9：剩余 16 控件 + 逐页迁移（设置→关于→仓库→议题→内容页→其他）
- 批 10：删除全部 Material 可见控件引用，切换 WidgetsApp，截图矩阵按 MD1 重录
