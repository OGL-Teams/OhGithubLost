# UI 深度复审任务书（15 席 × 5 批 · v15 之后）

> 用户指令（2026-11-24）：全面深度检查 UI，准备做得让用户满意。
> 背景：v14 前做过 15 席 UI 审计（docs/UX_CROSS_AUDIT/，61 条确证，编号 B-/G-/D-/F-），
> v15 按 docs/UX_STABILITY_PLAN.md 修了四批（主题层/骨架状态/外壳转场/反馈闭环）。
> **本轮审的是 v15 之后的真实状态**，不是重跑旧审计。

## 本轮三问（每席都要回答）
1. **闭环核对**：旧 61 条确证里，本席负责范围内的问题**修好了吗**？逐条给「已修 / 未修 / 修法有问题（说明问题）」。
2. **回归**：v15 四批的大改（theme.dart 14 项、async.dart 骨架屏、client_shell 限宽与转场、motion 去缩放、图标层）**有没有引入新问题**？
3. **新发现**：本席范围内还有哪些**旧审计没抓到**的用户可感知问题？

## 用户满意度视角（本轮新增重点）
用户对 v14 的判词是「空、漂浮感、没有作为工具的稳定感」。本轮必须回答：
- **首次打开**：首屏有没有内容锚点？启动每帧是否空白/闪变？
- **等待**：任何等待都有结构（骨架/进度/文案）还是干等？
- **操作后**：每个动作都有反馈闭环吗？
- **出错**：错误可读、可恢复、不误导吗？
- **长期使用**：信息密度是否支持高效浏览（不是空，也不是挤）？
- **跨页一致性**：同类页面看着像同一产品吗？

## 全局纪律（每席必带）
1. **禁读 Flutter SDK**：禁止读取/下载/复制 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码；只用项目自身 lib/ 已验证代码；本地 dart 仅用 `/opt/dart/bin/dart format`；违反即取消+全量清理。
2. **只读审计**：不改代码、不 commit/push；唯一产出 docs/UI_AUDIT_V2/<批>-<席>.md。
3. **证据**：每条 file:line 可 rg 复现；给「症状→根因→修复指令（具体到改哪个文件什么值）」。
4. **覆盖**：每席列「已检查清单」，禁止抽样后声称全覆盖。
5. **报告格式**：文档戳（更新时间精确到秒 + v15.0.0）；按 P0(用户完全无法使用/数据丢失/安全) / P1(明显影响使用体验或一致性) / P2(打磨) 分级；结尾必须含「本席对三问的回答」。

## 批次与席位（5 批 × 3 席）
- **批 1 · 主题与视觉基座**（skill: material-3 SKILL.md 的 Color/Typography/Shape/Elevation/Theming 节 + sota-frontend-design/rules/01-typography-and-color.md）
  1-A 主题层复审：theme.dart 14 项改动的实际效果与新风险（outlineVariantStrong 对比是否够、卡片投影是否过重、navRailTheme 是否与 navbar 一致、disabled 色是否可读）
  1-B 排版与字体复审：textTheme 派生是否让所有控件字号层级正确、有无控件仍用裸字号、缩放 130%/200% 是否破版
  1-C 形状与间距复审：OgLRadius 六档与 M3 shape scale 对齐度、OgLSpace 8dp 体系、页面是否仍有裸值
- **批 2 · 布局与信息密度**（skill: material-3 Layout 节 + sota-frontend-design/rules/02-layout-spacing-responsive.md）
  2-A 首屏与启动链路视觉（boot_splash→首帧→首页→引导页，每一帧是否空白/跳变）
  2-B 列表/详情/表单密度（行高、留白比、一屏信息量、目录/评论行的信息完整度）
  2-C 外壳与自适应（AppBar full-bleed、限宽下沉后各页表现、三态切换的视觉一致）
- **批 3 · 控件与状态**（skill: material-3 Components 节 + sota-frontend-design/rules/03-design-systems-components.md + 04-ux-patterns.md）
  3-A 控件变体与图标语义复审（v15 统一了 8 处图标，全库还有多少语义冲突）
  3-B 四态与骨架复审（骨架屏是否结构化且不跳变、空态是否有 CTA、错误态是否可恢复）
  3-C 表单与输入复审（label 可见性、字段级错误、键盘类型、提交防重）
- **批 4 · 动效与反馈**（skill: sota-frontend-design/rules/06-motion-design.md + rules/04 反馈节）
  4-A 转场复审（去整页缩放后的观感、shared-axis 方向、返回接力）
  4-B 反馈闭环复审（写操作 busy/成功/失败、SnackBar 三语气是否真的可区分）
  4-C 微交互与手感（按压反馈、滚动边界、拖拽、列表吸顶）
- **批 5 · 用户旅程与一致性**（skill: sota-frontend-design/rules/04 全文 + rules/07 + material-3 Accessibility）
  5-A 首次使用旅程（安装→授权→登录→引导→首页，每一步是否知道该做什么）
  5-B 高频任务效率（找仓库/看 issue/下载/改设置，各几步、可否更快）
  5-C 无障碍与一致性终检（48dp、对比度、Semantics、同类页面模式差异）

## 收口
15 份齐 → 主会话交叉汇总（闭环核对表 + 回归清单 + 新发现，按 P0/P1/P2 排序）→ docs/UI_AUDIT_V2_REPORT.md → 向用户汇报并给出「让用户满意」的分批打磨计划（不自动执行修复，等用户确认）。
