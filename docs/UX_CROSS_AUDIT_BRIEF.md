# UI 全面交叉审计任务书（15 子代理 × 5 批）

> 用户判定：**UI 不满——「空、漂浮感、没有作为工具的稳定感」，全链路细节粗糙**。
> 本轮不是合规打分，是找出用户可感知的粗糙点并给出可执行的修复指令。
> V2 审计（docs/MD3_AUDIT_V2.md，97/100）分数高但用户不满 → **分数不作为豁免**，
> 每批必须交付「用户可感知问题清单」，找不出问题的页面要写明「检查了什么」。

## 背景事实（各批共享）
- Flutter MD3，主题 lib/surface/theme.dart（14 类组件主题 + OgLSemanticColors），
  令牌 OgLSpace/OgLRadius/OgLFont/OgLWindowWidths，动效 lib/surface/app/motion.dart 档位质量表。
- 页面 lib/surface/pages/*.dart（约 30 页）、组件 lib/surface/widgets/、外壳 lib/surface/app/client_shell.dart。
- 仓库 /root/OhGithubLost；输出报告统一写 docs/UX_CROSS_AUDIT/<批号>-<维度>.md（带文档戳）。
- 禁止改代码；禁止 commit/push；引用必须 file:line 可 rg 复现。

## 批次与维度（每批 3 代理，各自读对应 skill）
- **批 1 · 布局与密度**（skill：material-3 SKILL.md Layout/Components 节 + sota-frontend-design/rules/02-layout-spacing-responsive.md）
  A: 全页面网格与间距节奏（8dp 体系偏离、过疏=「空」的直接来源，逐页列 padding/gap 数据）
  B: 外壳三态（底栏/侧栏/宽屏）+ AppBar 层次（滚动插值、分割感、内容与导航的从属关系）
  C: 列表/卡片信息密度（行高、留白比、一屏信息量——「空」的量化：每页平均可见条目数）
- **批 2 · 漂浮感与稳定感**（skill：material-3 Elevation/Color 节 + sota-frontend-design/rules/07-visual-craft-distinctiveness.md）
  A: 层级系统全查（elevation 0 + tonal 是否足以锚定；surfaceContainer 系使用是否过浅造成「漂」）
  B: 描边/分割/边界强度（outlineVariant 过淡=边界消失感；卡片/弹层/输入框的接地感）
  C: 动效档位对稳定感的影响（motion.dart 曲线/位移/缩放——过大位移=漂浮；弹簧阻尼是否过弹）
- **批 3 · 控件与状态**（skill：material-3 Components 节 + sota-frontend-design/rules/03-design-systems-components.md + rules/04-ux-patterns.md）
  A: 控件变体正确性（FilledButton/OutlinedButton/TextButton 用途混用、Chip/Switch/Slider 细节）
  B: 状态完整性（loading/empty/error/disabled 三态覆盖逐页查——空态是否只有一行字=「空」）
  C: 输入与表单（TextField/搜索框/登录表单的 label、错误呈现、键盘交互）
- **批 4 · 反馈与动效**（skill：sota-frontend-design/rules/06-motion-design.md + rules/04 §反馈）
  A: 操作反馈闭环（点击后有无 ripple/progress/snackbar 确认；异步操作无反馈=不稳）
  B: 页面转场与手势（转场方向语义、返回手势、转场时长档位）
  C: SnackBar/Dialog/BottomSheet 统一性（出口一致性、动画、位置、堆叠）
- **批 5 · 全链路体验流**（skill：sota-frontend-design/rules/04-ux-patterns.md 全文 + material-3 Accessibility 节）
  A: 关键任务流走查（登录→搜索→进仓库→看 issue→写评论：每步的状态衔接与视觉锚点）
  B: 可访问性与触达（48dp、对比度、Semantics、焦点）
  C: 一致性总查（同类页面模式差异、图标语义、文案与视觉的配合）

## 每份报告的硬性格式
1. **用户可感知问题**（按 严重/中/轻 分级，每条：页面、file:line 证据、用户感受描述——用「空/漂浮/粗糙/不稳定」语言）
2. **修复指令**（每条问题给具体改法：改哪个文件哪个值、改成什么——参考哪个 M3 规范值）
3. **检查清单**（检查过什么、未发现问题的部分也要列——证明查过）
4. 至少 15 条可感知问题（全库 1272 键 30 页的体量，不可能没有；少于 15 条视为未尽职）

## 收口
主会话汇总 15 份报告 → 三视角交叉 → 产出 docs/UX_STABILITY_PLAN.md（修复计划：按
「稳定感优先」排序：边界/接地/密度/反馈四类）→ 用户确认后分批修复。

## 补强指令（2026-11-21 用户追加）：全链路 × 双重分析

审计必须**双轴**展开，不得只做静态单页检查：

### 轴一 · 启动路线（冷启动→主界面的时间线走查）
由批 5-A「关键任务流」扩展为**启动全链路**逐帧检查：
1. 进程启动 → boot splash（lib/surface/app/boot_splash.dart）：视觉是否空、时长感知、品牌锚定
2. 引导清单验证 → 失败页 OgLBootFailureApp（失败态是否稳定可信）
3. 首帧 → MaterialApp 主题装载 → 首页（首页第一屏信息密度与锚定）
4. 冷启动到可操作的时间线里每一帧的视觉连续性（无「闪白/跳跃/布局跳变」）
5. 令牌验证态恢复（自动登录）路径的中间态呈现（「正在验证令牌」等 phase 提示的视觉）
产出并入 5-A 报告（独立章节「启动链路」），问题计入总数。

### 轴二 · 功能页面矩阵（按页面域逐页过，不是抽样）
以 lib/surface/pages/ 实际页面清单为准（rg -l "Scaffold" 统计），按域分组全覆盖：
- 仓库域：repo_page / repo_tags / commit / pull / release_detail / code_editor / file_preview
- 议题域：issue / new_issue / notifications / dashboard
- 内容域：gists / gist_detail / new_gist / readme_view / search
- 账户域：login / onboarding / profile / settings 系（settings_page + settings_section_page + 字体/外观子页）/ about / legal_text
- 工具域：download_manager / workflow_dispatch / action_log / action_run
每页在对应席位报告中必须有**独立小节**（即使无问题也列「已查项」），最终 15 份报告合并后按页索引可查。任何页面缺席视为审计未尽职。

### 双轴交叉
收口 docs/UX_STABILITY_PLAN.md 时按两个维度组织：
- 按问题类型（边界/接地/密度/反馈）给修复指令
- 按页面矩阵给逐页清单（每页的问题编号回链）
