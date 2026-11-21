# 批 1 · B 席 —— 外壳三态（底栏 / 侧栏 / 宽屏 extended）与 AppBar 层次审计

> **文档戳 / Doc Stamp**
> - 审计批次：**批 1 · 布局与密度 · B（外壳三态 + AppBar 层次）**
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - 更新时间：**2026-11-22 00:31:07 (Asia/Shanghai)**
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `f684160`；**只读审计，未改任何代码，未 commit / 未 push**
> - 审计对象：`lib/surface/app/client_shell.dart`（515 行）、`lib/surface/app/og_l_app_bar.dart`（151 行）、`lib/surface/theme.dart`（appBarTheme / navigationBarTheme 段）、`lib/surface/util/og_l_window_widths.dart`、`lib/surface/pages/*.dart`（31 个页面文件的 Scaffold/AppBar 使用点）
> - 基准文档：`docs/UX_CROSS_AUDIT_BRIEF.md`（含「补强指令」双轴要求）、`/var/minis/skills/material-3/SKILL.md`（Layout / Components 节）、`/var/minis/skills/sota-frontend-design/rules/02-layout-spacing-responsive.md`（§1 4/8 栅格与 proximity 律、§3c 视口与安全区、§10 滚动与 sticky 纪律）
> - 复现方式：全部证据为 `file:line`，用 `rg -n "<片段>" <路径>` 可复现；Flutter 侧行为用 `/opt/fl/flutter/packages/flutter/lib/src/material/*.dart` 行号佐证。

---

## 0. 结论摘要

**「空 / 漂浮 / 不稳定」在壳与顶栏这一层的根因不是间距，而是"边界系统缺席"**：

| # | 结构性问题 | 量化 | 用户感受 |
|---|---|---|---|
| B-01 | **滚动融合（渐变 AppBar）在 14/15 个使用页从未生效** | 全库 `PrimaryScrollController` 只有 1 处引用（`og_l_app_bar.dart:83`），而 Flutter 的 `Scaffold` **不提供** `PrimaryScrollController`（`/opt/fl/flutter/.../scaffold.dart` 全文只有 2646 行*读取*，无插入）→ 除 dashboard 外恒为 progress=0 | 标题与正文糊在一起，滚到一半没有"浮起"→ 粗糙 |
| B-02 | **AppBar 与内容的边界被显式归零** | `theme.dart:285-286`（`elevation: 0` + `scrolledUnderElevation: 0`）+ `og_l_app_bar.dart:142-143` 同归零 | 内容从标题下穿过，零遮挡、零分割→ 不稳 |
| B-03 | **融合的色阶选得太弱** | `og_l_app_bar.dart:133-136` lerp(surface → surfaceContainer)，两者明度差 ≈L\*4，且 M3 要求的 level-2 elevation 已被去掉 | "浮起"浮不起来→ 漂浮 |
| B-04 | **宽屏时 AppBar 被内容限宽一起裁到 720dp** | `client_shell.dart:321-330` 的 `Center + ConstrainedBox(maxWidth: 720)` 包住整个页面 `Scaffold`（含其 AppBar） | 顶栏不贴窗边，左右两条裸 surface→ 粗糙 |
| B-05 | **底栏与侧栏是两种视觉语言** | `theme.dart` 全文**没有 `navigationRailTheme`**（只有 `navigationBarTheme` 297-326）→ 底栏选中态 primaryContainer 药丸（304），侧栏用 M3 默认 secondaryContainer 圆点 | 跨 600dp 断点时选中标记形状+颜色双跳→ 不一致 |

**一句话结论**：本库做了大量"看不见"的加固（懒挂载、世代号防重入、弹簧档位、令牌化间距），但**外壳与顶栏的"接地"动作一次都没做**——AppBar 不浮起、不投影、不分色、限宽后不贴边、侧栏无底色、导航轨无安全区。因此用户说的"空、漂浮、没有作为工具的稳定感"在壳层是**逐条可复现**的。

---

## 1. 用户可感知问题清单（22 条 · 严重 5 / 中 12 / 轻 5）

### 严重

#### B-01【严重】滚动渐变融合在 14/15 个页面**从未发生**（死代码）
- **证据**：`lib/surface/app/og_l_app_bar.dart:83`（`PrimaryScrollController.maybeOf(context)`）、`og_l_app_bar.dart:15-19` 与 `:50-52` 的注释断言"Scaffold 注入 PrimaryScrollController"；
  全库仅 1 处 `PrimaryScrollController` 引用（`rg -n "PrimaryScrollController" lib/` 只命中 `og_l_app_bar.dart:16,17,52,83`），**没有任何一处把它插入树中**；
  Flutter 侧：`/opt/fl/flutter/packages/flutter/lib/src/material/scaffold.dart` 全文只有 `2646: final ScrollController? primaryScrollController = PrimaryScrollController.maybeOf(context);` —— Scaffold 只**读**、不**提供**；`widgets/app.dart` / `material/app.dart` 亦无 `PrimaryScrollController` 插入。
  显式传参的只有 `lib/surface/pages/dashboard_page.dart:360`（`scrollController: _scroll`）。
- **用户感受**："发现""我的""设置""仓库"等页面往下滚，标题栏和内容**颜色完全一样**，列表文字从标题下方穿过，界面像一张没有厚度的纸 → **粗糙、边界消失**。
- **修复指令**：
  1. `lib/surface/app/og_l_app_bar.dart:83` 改为**从 body 侧取**：在 `Scaffold.body` 内用 `NotificationListener<ScrollNotification>` 或 `PrimaryScrollController` 显式建立，再把控制器回传给 AppBar；或
  2. 把 `OgLAppBar` 换成 Flutter 官方机制：在 `og_l_app_bar.dart:138-149` 去掉 `elevation: 0` / `scrolledUnderElevation: 0`，改用 `scrolledUnderElevation: 2` + `surfaceTintColor: scheme.surfaceTint`（M3 canonical：scrolled-under 时 surfaceContainer + level 2 elevation），完全删除自研插值；
  3. 若保留插值，则**逐页把真实滚动控制器传进来**（见 §3 页面矩阵中标 `✗` 的 14 页），并把 `:83` 的"Primary 兜底"注释改成"本项目不存在 Primary 注入，必须显式传参"，防止下一个人继续误信。

#### B-02【严重】AppBar 与内容之间**没有任何边界**（elevation / scrolledUnderElevation 双双归零）
- **证据**：`lib/surface/theme.dart:285-286`（`elevation: 0, scrolledUnderElevation: 0`）、`lib/surface/theme.dart:287`（`backgroundColor: scheme.surface`）；`lib/surface/app/og_l_app_bar.dart:142-143`（同样 `elevation: 0, scrolledUnderElevation: 0`）。
- **用户感受**：滚动时内容"穿帮"到标题区，字与字叠在一起，既没有阴影也没有分割线 → **不稳定 / 不像工具**。
- **修复指令**：`theme.dart:285-286` 改为 `elevation: 0` + `scrolledUnderElevation: 2`；`og_l_app_bar.dart:142-143` 同步改为 `scrolledUnderElevation: 2`；若坚持"无阴影"的极简风格，则**必须**补一条 `PreferredSize` 高度不变的 1px 底部分割（`theme.dart:283-294` 的 `appBarTheme` 加 `shape: Border(bottom: BorderSide(color: scheme.outlineVariant))`），二者择一，不可皆无。

#### B-03【严重】"浮起"的色阶太弱，且规范要求的 elevation 被去掉 → 浮不起来
- **证据**：`og_l_app_bar.dart:133-136`（`Color.lerp(surface, surfaceContainer, t)`）；`theme.dart:344-348`（`outlineVariant` 为唯一分割色，浅色主题下极淡）。
- **用户感受**：即使 B-01 修好、进度真的走到 1，用户也**看不出**顶栏"浮"起来了 → 仍是"漂浮"。
- **修复指令**：M3 canonical 顶栏滚动态 = `surfaceContainer` 底 + **level 2 elevation（2dp）**；本项目把 elevation 归零后只剩 4 个明度单位的色差。改法：把 `og_l_app_bar.dart:133-136` 的插值终点由 `surfaceContainer` 改为 `surfaceContainerHigh`（明度差 ≈L\*8~10），并按 B-02 恢复 `scrolledUnderElevation: 2`；或改用 `scheme.surfaceTint` 做 M3 官方 tonal elevation。

#### B-04【严重】宽屏时 AppBar 被内容限宽一起裁成 720dp 居中块，两侧露裸底
- **证据**：`lib/surface/app/client_shell.dart:321-330`
  ```
  final Widget body = width < OgLWindowWidths.compact
      ? slide
      : Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: OgLWindowWidths.contentMax), child: slide));
  ```
  `slide`（`:308-311`）是 `IndexedStack` 里的**整个页面**，每个页面自带 `Scaffold` + `appBar`（例：`lib/surface/pages/dashboard_page.dart:357-360`、`profile_page.dart:218-219`）。
- **用户感受**：桌面/平板上顶栏不贴窗口边，左右各有一条"断掉"的 surface 空白，顶栏像一张浮在页面上的卡片 → **漂浮、粗糙**。
- **修复指令**：限宽必须**只作用于内容，不作用于 Scaffold/AppBar**。改法二选一：
  1. 壳层不再包 `ConstrainedBox`，把限宽下沉到各页 `body` 内部（与 1-A 席的"内容居中列"方案对齐）；
  2. 或壳层改为 `Row[ rail | Expanded(Column[ AppBar 区(全宽) , Expanded(限宽内容) ]) ]`，即 AppBar 走**壳层**，内容走限宽列。
  参考 M3：`NavigationRail + 顶层 AppBar` 的 top app bar 属于**窗口级**，必须 full-bleed。

#### B-05【严重】移动端顶栏 + 底栏夹住内容：顶部 64dp、底部 64dp（规范为 80dp）
- **证据**：`client_shell.dart:337`（`bottomNavigationBar: NavigationBar(...)`）、`theme.dart:298`（`height: 64`，M3 `NavigationBar` 规范高度为 **80dp**）、每页自带 64dp 顶栏（`theme.dart` 未设 `toolbarHeight`，默认 `kToolbarHeight=64`）。
- **用户感受**：手机上内容被夹在两条硬边带子中间，可视内容区被压掉 ~20%，标题栏和底栏颜色还不一样 → **空 + 漂浮**。
- **修复指令**：`theme.dart:298` 的 `height: 64` 改回 **80**（M3 spec）；或若产品上坚持紧凑，则**必须**同时把 `labelBehavior` 从 `alwaysShow`（`theme.dart:325`）改为 `onlyShowSelected`，把省下的 16dp 还给内容区，二者只能选一种，不要既压高度又全显标签。

### 中

#### B-06【中】侧栏态**没有任何主题**：底栏与导航轨的选中态是两套语言
- **证据**：`lib/surface/theme.dart` 全文 `rg -n "navigationRail" lib/surface/theme.dart` **零命中**（只有 `theme.dart:297-326` 的 `navigationBarTheme`）；`client_shell.dart:374-402` 的 `NavigationRail` 未指定任何 `NavigationRailTheme` 字段；Flutter 默认见 `navigation_rail.dart:1132-1136`（`indicatorColor` 取默认 `secondaryContainer`）。
- **用户感受**：把窗口从 700 拉到 900，选中项从"品牌色药丸"变成"灰蓝圆点"，导航像换了个 App → **不一致 / 不稳**。
- **修复指令**：在 `theme.dart:297` 前新增 `navigationRailTheme: NavigationRailThemeData(...)`，字段与 `navigationBarTheme` 对齐：`indicatorColor: scheme.primaryContainer`、icon/label 用 `onPrimaryContainer` / `onSurfaceVariant`、`labelType: NavigationRailLabelType.all`、`backgroundColor: scheme.surfaceContainerLow`、`elevation: 0`、`useIndicator: true`。

#### B-07【中】侧栏与内容之间只有一根 1px 极淡分割线，轨面与页面同色 → 轨"浮"在页面上
- **证据**：`client_shell.dart:404`（`const VerticalDivider(width: 1)`）、`theme.dart:344-348`（`dividerTheme.color = scheme.outlineVariant`，浅色主题下对比极低）；`NavigationRail` 未设 `backgroundColor`（B-06）→ 轨面 = 页面 `surface`。
- **用户感受**：侧栏像是贴在页面上的透明胶片，没有"实体轨道" → **漂浮**。
- **修复指令**：给 `NavigationRail` 一个 `backgroundColor: scheme.surfaceContainerLow`（通过 B-06 的 `navigationRailTheme`），并删除 `client_shell.dart:404` 的 `VerticalDivider`（有色轨面后分割线是冗余的"双边界"，M3 参考组件里两者不共存）。

#### B-08【中】导航轨不处理顶部状态栏安全区 → ≥600dp 第一枚图标顶到状态栏
- **证据**：`client_shell.dart:373-374`（`NavigationRail` 位于**外层 Scaffold 的 body** 内，外层 Scaffold 无 `appBar` → 顶部 MediaQuery padding 未被消费）；Flutter 的 `NavigationRail` **不含** `SafeArea`（对比 `navigation_bar.dart:244` 的 `child: SafeArea(...)`）。
- **用户感受**：平板/桌面窗口顶部第一枚图标被状态栏压住，选中态药丸被切掉一半 → **粗糙、不稳**。
- **修复指令**：把 `client_shell.dart:374` 的 `NavigationRail` 包一层 `SafeArea(top: true, child: ...)`（或 `Padding(padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top))`），底部同理按需。

#### B-09【中】导航轨目的地全部顶对齐，下方 70–80% 竖直空间空着
- **证据**：`client_shell.dart:374-402` 未设 `groupAlignment`（Flutter 默认 `-1.0` = 顶部对齐，见 `navigation_rail.dart:1084`/`1135`），且只有 4 个目的地、无底部 FAB/辅助分组。
- **用户感受**：宽屏侧栏像一根"贴左边的空柱子"，底座缺失 → **空 / 不像工具**。
- **修复指令**：`NavigationRail(groupAlignment: 0.0)` 让目的地竖直居中；或在 `client_shell.dart` 的 `NavigationRail` 外包 `Column`，底部补一个"新建仓库"入口（与 `dashboard_page.dart:403-410` 的 FAB 语义对齐），给侧栏一个**底座**。

#### B-10【中】三态切换无过渡、无同构：跨 600dp 选中项从屏幕底跳到屏幕左
- **证据**：`client_shell.dart:337`（`NavigationBar`）与 `client_shell.dart:373-402`（`NavigationRail`）是两种结构完全不同的控件，切换时无任何动画/共享元素；断点来自 `lib/surface/util/og_l_window_widths.dart:5`（`compact = 600`）。
- **用户感受**：旋转平板或拖动窗口时整个导航"啪"地换位置，眼睛要重新找目标 → **不稳**。
- **修复指令**：统一目的地描述（同一个 `List<OgLDestination>` 数据源同时喂给 `NavigationDestination` 与 `NavigationRailDestination`，消除 `client_shell.dart:342-364` 与 `:383-402` 两份手写副本）；断点切换至少给 `AnimatedSwitcher` 或 `FadeTransition`，让指示器位置连续。

#### B-11【中】目的地图标语义不一致："发现"没有选中态图标
- **证据**：`client_shell.dart:347-350`（`NavigationDestination(icon: Icon(Icons.search), ...)` —— **无 `selectedIcon`**）vs `:343-345`（home 有 `selectedIcon`）、`:352-354`（profile 有）、`:358-361`（settings 有）；侧栏同样问题见 `client_shell.dart:388-391`。
- **用户感受**：切到"发现"时图标毫无变化，要靠标签才知道选中了 → **反馈缺失 / 不稳**。
- **修复指令**：为"发现"补 `selectedIcon: const Icon(Icons.search)` 的实心变体（`Icons.manage_search` 或自绘实心版），底栏与侧栏两处同步补齐（`client_shell.dart:347` 与 `:388`）。

#### B-12【中】三态的**内容留白不一致**：底部安全区与左右边距在断点处突变
- **证据**：`client_shell.dart:321`（`< 600` 时**不限宽**，`ConstrainedBox` 只在 `≥600` 生效）→ 手机全宽、平板起突然变成 720 居中列，左右各留大片空白；`client_shell.dart:337` 有 `bottomNavigationBar` → 外层 Scaffold 触发 `removeBottomPadding: true`（Flutter `scaffold.dart:2871`/`2947`）→ 手机态**剥掉**页面底部安全区；而 `≥600` 侧栏态无 `bottomNavigationBar` → 底部内边距保留 → 同一页在两种壳态下末行间距不同。
- **用户感受**：转屏一次，内容的边距和底部呼吸感全变 → **漂浮 / 不像一套东西**。
- **修复指令**：
  1. 限宽阈值与断点解耦：手机（<600）也套 `ConstrainedBox(maxWidth: contentMax)`，只是 `contentMax=720 > 手机宽` 时不生效——即把 `client_shell.dart:321` 改为**无条件**套用限宽，保证左右 gutter 连续；
  2. 底部：手机态由 `NavigationBar` 自身的 `SafeArea`（Flutter `navigation_bar.dart:244`）吃掉系统条，页面不应再依赖被剥掉的 padding；侧栏态则显式给内容底部留 `MediaQuery.paddingOf(context).bottom`，使两态末行间距一致。

#### B-13【中】切 tab 时**整页含 AppBar 一起横向漂移 + 半透明**，顶边锚点被拆掉
- **证据**：`client_shell.dart:503-508`（`Opacity(opacity: (0.7 + 0.3 * t))` + `FractionalTranslation(translation: Offset(_from * (1 - t), 0))`），`_from` 取自 `OgLAnim.shellOffset`（`lib/surface/app/motion.dart:207/233/259` = 0.02/0.035/0.05 屏宽），控制器下界放开到 `[-1, 2]` 允许过冲（`client_shell.dart:474-479`）。
- **用户感受**：AppBar 是"贴在顶边"的锚，它跟着内容横着滑、并降到 70% 不透明 → 标题区能透出上一页的文字，滑动过程中顶边"没有东西扶着" → **漂浮、脏**。
- **修复指令**：把过渡**降级为内容层**：只对 `IndexedStack` 的内容做位移，顶栏由壳层持有并保持静止；或至少把透明度下限从 0.7 提到 **0.94**（`client_shell.dart:503`），使残影不可见；并把 `FractionalTranslation` 的位移量限制在 **≤ 屏宽 2%** 且**禁止过冲**（把 `client_shell.dart:453-454` 的 `lowerBound: -1 / upperBound: 2` 收回 `[0,1]`，或改用 `OgLSpring` 的临界阻尼档）。

#### B-14【中】OgLAppBar 的整栏重建与它自己的注释相矛盾
- **证据**：`og_l_app_bar.dart:139-149` 把 `AppBar(...)` **整体**放进 `ValueListenableBuilder`；而 `og_l_app_bar.dart:24-25` 的注释声称"滚动事件不逐帧 setState——只让 `ValueListenableBuilder` 包着的那层背景色重建"。实际标题、`actions`（含 `Badge`、`IconButton`、`ListenableBuilder`，见 `dashboard_page.dart:362-399`）每 1% 台阶整体重建；`og_l_app_bar.dart:73`（`_kStep = 0.01`）→ 一次滑动 ≈ **100 次**全栏重建。
- **用户感受**：滑动时右上角的角标（Badge）会跟着抖一下，标题字重疑似闪动 → **粗糙**。
- **修复指令**：拆成两层——外层 `AppBar` 只构建一次，内层用 `Container(decoration: BoxDecoration(color: merged))` 或 `Material(color: merged)` 承接 `ValueListenableBuilder`；动作区用 `const` / `RepaintBoundary` 隔离，确保 1% 台阶只重绘背景色。

#### B-15【中】融合进度取 `position.pixels`（绝对值）且只取 `positions.first` → 嵌套滚动页必然错
- **证据**：`og_l_app_bar.dart:115`（`controller.positions.first`）、`og_l_app_bar.dart:117`（`position.pixels / _kRange`，未减 `minScrollExtent`）。
  多控制器页面实例：`lib/surface/pages/repo_page.dart:941/2654/2999/3153`（4 条独立 `_scroll`）、`lib/surface/pages/search_page.dart:380`（`_repoScroll` + `TabBarView` 三套控制器）、`lib/surface/pages/new_repo_page.dart:43`、`new_release_page.dart:55`。
- **用户感受**：某些页面滚了半天顶栏纹丝不动，某些页面一动就瞬间变深 → **反馈不可预期 = 不稳**。
- **修复指令**：改用 `position.pixels - position.minScrollExtent`（消除绝对偏移），并明确"取哪一个 position"的约定（建议取 `controller.positions` 中 `axis == Axis.vertical` 的第一个，或直接由 body 侧把进度值以 `ValueNotifier` 反向喂给 AppBar，而不是 AppBar 去猜）。

### 轻

#### B-16【轻】融合范围硬编码 120px，与页面长度无关
- **证据**：`og_l_app_bar.dart:70`（`static const double _kRange = 120;`）、`:117`。
- **用户感受**：短页面滚 120px 就"用完"了浮起反馈，再滚完全无变化；长页面 120px 内色变就已结束 → 反馈时长不可预期。
- **修复指令**：改为按 `maxScrollExtent` 归一化（`next = (pixels / min(maxScrollExtent, 240)).clamp(0,1)`），或固定 24dp 逻辑高度做 M3 的 `scrolledUnderElevation` 阶跃（推荐后者，行为与 Material 一致）。

#### B-17【轻】去抖用 `Timer(Duration.zero)` 而非帧对齐 → 颜色慢一帧
- **证据**：`og_l_app_bar.dart:100-106`（`_onScroll` → `Timer(Duration.zero, _applyProgress)`）、`:88`（`Timer? _debounce`）。
- **用户感受**：快速滑动时顶栏颜色像"追不上"内容，出现一帧拖影 → **粗糙**。
- **修复指令**：把去抖改为 `SchedulerBinding.instance.scheduleFrameCallback` 或 `addPostFrameCallback` 合并到下一帧；`Timer` 会在微任务里跑，与 vsync 无关。

#### B-18【轻】AppBar 家族二分：16 个页面用裸 `AppBar`，15 个用 `OgLAppBar`（其中 14 个退化）
- **证据**：裸 `AppBar`：`action_log_page.dart:290`、`action_run_page.dart:526`、`code_editor_page.dart:579`、`commit_page.dart:93`、`download_manager_page.dart:205`、`file_preview_page.dart:205`、`gist_detail_page.dart:354`、`issue_page.dart:723`、`legal_text_page.dart:94`、`login_page.dart:326`、`new_gist_page.dart:144`、`notifications_page.dart:170`、`pull_page.dart:109`、`release_detail_page.dart:457`、`workflow_dispatch_page.dart:412`、`onboarding_page.dart:221`（复核态）= **16 处**；`OgLAppBar` = **15 处**（含 `search_page.dart:716` 与 `:1318` 两处）。
- **用户感受**：从"议题详情"返回"仓库列表"，顶栏的阴影/分割/色感一变 → **不像一套东西**。
- **修复指令**：全部统一到 `OgLAppBar`（或统一到裸 `AppBar` + 主题 `scrolledUnderElevation`）。建议后者更省事：**在 `theme.dart:283-294` 一次性修好**，所有裸 `AppBar` 自动获得正确的滚动态，两类页面自然收敛。

#### B-19【轻】顶栏底色（surface）与底栏底色（surfaceContainer）不同 → 内容被夹在两条异色带中间
- **证据**：`theme.dart:287`（`appBarTheme.backgroundColor = scheme.surface`）vs `theme.dart:300`（`navigationBarTheme.backgroundColor = scheme.surfaceContainer`）。
- **用户感受**：页面主体是 surface，顶栏同色（融掉），底栏却是更深的 container → 底部"多出一块"，整体像贴了两条不同色的胶带 → **漂浮**。
- **修复指令**：底栏改 `backgroundColor: scheme.surface` + `scrolledUnderElevation: 2`（或给顶栏也用 container 色），使上下两条带子同族；M3 导航栏规范底色为 `surfaceContainer`，因此更合理的改法是**顶栏滚动态也用 `surfaceContainer`**，两者同族。

#### B-20【轻】侧栏态底部无人消费安全区（轨也不包 SafeArea）
- **证据**：`client_shell.dart:373-374`（`NavigationRail` 无 `SafeArea`），且 `≥600` 时外层 Scaffold 无 `bottomNavigationBar` → `removeBottomPadding` 为 false（Flutter `scaffold.dart:2871`）。
- **用户感受**：窗口贴地时页面末行与系统手势条之间没有稳定间距 → **不稳**。
- **修复指令**：在侧栏态给内容列统一加 `MediaQuery.paddingOf(context).bottom` 的底部留白（B-08 的 `SafeArea` 处理一并做）。

#### B-21【轻】extended rail 起点 1200 与内容限宽 720 不匹配 → 1440 以上左右两侧大空白
- **证据**：`lib/surface/util/og_l_window_widths.dart:17`（`expanded = 1200`）、`:9`（`contentMax = 720`）、`client_shell.dart:326`。
- **用户感受**：2560 宽的桌面上，内容只占中间 720，左右各约 900 空白 → **空**。
- **修复指令**：宽屏改用**多列自适应**（`AutoFill` 式：仓库域两列、列表域三列），或在 expanded 档把 `contentMax` 提到 **960**（M3 阅读宽度上限约 72–80rem ≈ 1152–1280，取 960 保守），并把扩宽只作用于"列表型"页面。

#### B-22【轻】OgLAppBar 不支持 leading / 返回键
- **证据**：`og_l_app_bar.dart:32-42`（构造参数只有 `title / actions / bottom / scrollController`），`:138-141`（`AppBar` 未传 `leading`/`automaticallyImplyLeading`）。
- **用户感受**：需要返回的二级页只能退回裸 `AppBar`（B-18 的成因之一），两套顶栏并存 → **不一致**。
- **修复指令**：给 `OgLAppBar` 增加 `leading` 与 `automaticallyImplyLeading`（默认 true）参数，`client_shell` 内的 `Navigator` 推送页统一使用。

---

## 2. 修复指令汇总（按"稳定感优先"排序）

| 优先级 | 文件:行 | 动作 | 目标值（依据） |
|---|---|---|---|
| P0 | `theme.dart:285-286` | `elevation: 0` + `scrolledUnderElevation: 0` → `elevation: 0` + `scrolledUnderElevation: 2` | M3 top app bar scrolled-under = level 2 |
| P0 | `theme.dart:287` / `og_l_app_bar.dart:144` | 统一滚动态底色为 `surfaceContainer`（与 `navigationBarTheme.backgroundColor` 同族，见 B-19） | M3 surface 角色层级 |
| P0 | `og_l_app_bar.dart:83` | 删除"Primary 兜底"假设，改为**必须显式传参**；或直接删自研插值、改用 M3 原生 `scrolledUnderElevation` | 消除死代码与"看似有边界其实没有" |
| P0 | `theme.dart:298` | `height: 64` → `height: 80`（若不改则 `theme.dart:325` 改 `labelBehavior: onlyShowSelected`） | M3 NavigationBar = 80dp |
| P1 | `theme.dart:297` 前 | 新增 `navigationRailTheme`（`indicatorColor: primaryContainer` / `backgroundColor: surfaceContainerLow` / `labelType: all` / `elevation: 0`） | 与 `navigationBarTheme` 同语言 |
| P1 | `client_shell.dart:404` | 删 `VerticalDivider`，改由轨面底色承担边界 | 避免双边界 |
| P1 | `client_shell.dart:374` | 包 `SafeArea(top: true)`（并按 B-20 处理底部） | 状态栏不压图标 |
| P1 | `client_shell.dart:321-330` | 限宽只作用于**内容**，AppBar 保持 full-bleed（见 B-04 两方案） | M3 顶层 AppBar 属窗口 |
| P1 | `client_shell.dart:321` | 限宽改为无条件套用（手机不触发但语义一致），保证 gutter 连续 | 三态一致 |
| P1 | `client_shell.dart:374` | `groupAlignment: 0.0` 或底部补主操作 | 消除侧栏"空柱" |
| P2 | `og_l_app_bar.dart:139-149` | 拆成"外层 AppBar 只建一次 + 内层背景色随进度"，`actions` 用 `const`/`RepaintBoundary` 隔离 | 消除整栏重建 |
| P2 | `og_l_app_bar.dart:115-117` | `positions.first` → 明确取竖直 position；`pixels` → `pixels - minScrollExtent` | 嵌套滚动正确 |
| P2 | `og_l_app_bar.dart:100-106` | `Timer(Duration.zero)` → `scheduleFrameCallback` | 帧对齐，无拖影 |
| P2 | `client_shell.dart:503-508` | 透明度下限 0.7 → 0.94；`lowerBound/upperBound` 收回 `[0,1]` | 消除残影与过冲漂浮 |
| P2 | `client_shell.dart:342-364` / `:383-402` | 两份目的地副本合并为同一数据源；补"发现"的 `selectedIcon` | 三态一致 + 反馈完整 |
| P3 | `og_l_app_bar.dart:70` | `_kRange` 120 → 归一化到 `maxScrollExtent` 或改用 M3 阶跃 | 反馈可预期 |
| P3 | `og_l_app_bar.dart:32-42` | 增加 `leading` / `automaticallyImplyLeading` | 收敛裸 AppBar 家族 |
| P3 | `og_l_window_widths.dart:9` | expanded 档 `contentMax` 720 → 960（或宽屏多列） | 减少宽屏空白 |

---

## 3. 页面矩阵：每页 AppBar / 滚动融合现状（全 31 个页面文件全覆盖）

图例：**✔** 已接滚动控制器（融合可生效）｜**✗** 未接（融合恒为 progress=0，等价裸 AppBar）｜**裸** 直接使用 Material `AppBar`｜**Tab** 顶栏带 TabBar（多控制器，融合天然不可用）

| 页面 | appBar 位置 | 类型 | 滚动控制器 | 融合 | 该页已查项 / 备注 |
|---|---|---|---|---|---|
| dashboard_page | `:358` | OgLAppBar | `:360` `_scroll`（`:404`/`:476` 使用） | ✔ | 唯一真正生效的页；`:403-410` FAB 位于外层底栏之上，底栏与 FAB 间距 16dp 尚可 |
| profile_page | `:219` | OgLAppBar | 无 | ✗ | body `ListView`（`:236`）不接控制器；账号列表从标题下穿过 |
| search_page（发现） | `:716` | OgLAppBar + TabBar | 无（TabBarView 三控制器） | Tab | TabBar 随顶栏整体染同一色；`:716-727` 底部 TabBar 未与顶栏分离 |
| search_page（搜索结果） | `:1318` | OgLAppBar | 无 | ✗ | 独立 `Scaffold`，与 `:716` 同族但同样未接控制器 |
| repo_page | `:541` | OgLAppBar | 4 条 `_scroll`（`:941/:2654/:2999/:3153`） | ✗ | 多控制器 + Tab 结构，融合无法只靠单一 controller |
| repo_tags_page | `:176` | OgLAppBar | 无 | ✗ | 标签页顶部标题与标签行同色，滚动时标签行穿帮 |
| issue_page | `:723` | 裸 AppBar | — | — | 与 `OgLAppBar` 页视觉不统一（B-18） |
| pull_page | `:109` | 裸 AppBar | — | — | 同上 |
| commit_page | `:93` | 裸 AppBar | — | — | 同上 |
| release_detail_page | `:457` | 裸 AppBar | — | — | 同上；`:316/:376` 的 Sheet 有 SafeArea，底栏无 |
| action_log_page | `:290` | 裸 AppBar | — | — | 同上 |
| action_run_page | `:526` | 裸 AppBar | — | — | 同上 |
| workflow_dispatch_page | `:412` | 裸 AppBar | — | — | 同上 |
| download_manager_page | `:205` | 裸 AppBar | — | — | 同上 |
| notifications_page | `:170` | 裸 AppBar | — | — | 同上 |
| code_editor_page | `:579` | 裸 AppBar | — | — | 编辑器顶栏应**永不滚动**，裸 AppBar 反而正确；但与全局外观不一致 |
| file_preview_page | `:205` | 裸 AppBar | — | — | 同上 |
| gist_detail_page | `:354` | 裸 AppBar | — | — | 同上 |
| new_gist_page | `:144` | 裸 AppBar | — | — | 同上（表单页，滚动少，问题轻） |
| login_page | `:326` | 裸 AppBar | — | — | 登录门，壳未构建（`client_shell.dart:285-299`），不参与三态 |
| legal_text_page | `:94` | 裸 AppBar | — | — | 长文页，最需要边界感却用裸 AppBar |
| onboarding_page | `:221`（复核态） | 裸 AppBar | — | — | 壳未构建（`client_shell.dart:277-282`），独立全屏 |
| gists_page | `:136` | OgLAppBar | 无 | ✗ | `:137` FAB 与外层底栏同屏，间距可 |
| drafts_page | `:211` | OgLAppBar | 无 | ✗ | — |
| settings_page | `:409` | OgLAppBar | 无 | ✗ | 设置列表从标题下穿过，最典型的"糊" |
| settings_section_page | `:31` | OgLAppBar | 无 | ✗ | 二级设置页，返回按钮缺失（B-22） |
| network_page | `:43` | OgLAppBar | 无 | ✗ | — |
| about_page | `:105` | OgLAppBar | 无 | ✗ | — |
| new_issue_page | `:136` | OgLAppBar | 无 | ✗ | 表单页，问题轻 |
| new_repo_page | `:139` | OgLAppBar | 无（页面内有 `_scroll` `:43`） | ✗ | 有控制器却没传给 AppBar —— 典型的"差一步" |
| new_release_page | `:162` | OgLAppBar | 无（页面内 `_scroll` `:55`） | ✗ | 同上 |

**矩阵统计**：使用 `OgLAppBar` 的 15 个页面中，**14 个滚动融合从未生效**；使用裸 `AppBar` 的 16 处（含 onboarding 复核态）全部无边界反馈。**全库 31 个页面中，具备"AppBar 与内容之间可感知边界"的页面数 = 1（dashboard）。**

---

## 4. 检查清单（已查项 / 明确无问题项）

### 4.1 已查且**确认无问题**的项（作为对照，避免重复施工）
- [x] **底栏与内容不重叠**：Flutter `Scaffold` 在有 `bottomNavigationBar` 时会把 body 高度让出底栏高度（`client_shell.dart:337`），未设 `extendBody` → 内容不会被底栏压住。
- [x] **底栏系统手势条安全区**：`NavigationBar` 自带 `SafeArea`（Flutter `navigation_bar.dart:244`），且 `theme.dart:300` `surfaceTintColor: Colors.transparent` 不会叠加色阶 → 底栏不脏。
- [x] **顶栏状态栏内边距**：内层页面的 `AppBar` 由框架处理顶部 MediaQuery padding（`client_shell.dart` 外层无 appBar，padding 未被提前消费）→ 顶栏不顶到状态栏（**注意：侧栏 `NavigationRail` 是反例，见 B-08**）。
- [x] **懒挂载与页面状态保留**：`client_shell.dart:283-300`（`IndexedStack` + `_visited` 集合）→ 切 tab 不丢滚动位置与表单状态；隐藏页 `TickerMode(enabled: false)` 停止动画 → 无隐藏烧帧。
- [x] **切 tab 动效档位**：`_OgLShellSlide` 在 `OgLAnim.enabled(context) == false`（档位 0 / 系统减少动效）时直接瞬时切换（`client_shell.dart:464-468`）→ 尊重减少动效偏好。
- [x] **返回键不误退**：`_handleBack` 的重入闸门 + 世代号（`client_shell.dart:120-215`）→ 无"连按穿层"；登录门阶段 `atHome` 判定正确（`client_shell.dart:196-201`）。
- [x] **断点数值与 M3 canonical 一致**：`og_l_window_widths.dart:5/17`（600 / 1200）映射 compact / expanded，注释亦说明不用 `calculateWindowSizeClass` 的跨平台理由 → 数值本身无误，问题在**限宽与安全区**（B-04 / B-08）。
- [x] **顶栏标题字号**：`theme.dart:289` 用 `titleLarge`（22sp）→ 符合 M3 large top app bar；`centerTitle: false`（`theme.dart:284`）符合大屏左对齐惯例。
- [x] **`OgLAppBar.preferredSize` 计算正确**：`og_l_app_bar.dart:56-57` 正确把 `bottom`（TabBar）高度计入 → TabBar 页不会出现顶栏高度塌陷。

### 4.2 已查但**问题被归到其他席位**（此处仅登记，不重复计数）
- 顶栏与底栏的**色阶/描边强度**（`outlineVariant` 过淡）→ 批 2-B（描边/边界强度）。
- 切 tab 的**弹簧过冲/曲线档位**（`client_shell.dart:453-454` 下界 `[-1,2]`）→ 批 2-C（动效档位）；本报告 B-13 只从"锚点是否漂移"角度记录。
- 页面**正文留白密度**、行高、每屏条目数 → 批 1-A / 1-C。
- 页面**空态/错误态/加载态**覆盖 → 批 3-B。

### 4.3 本报告**未覆盖**的范围（诚实声明）
- 未逐页渲染截图复核色差（只读审计，无运行环境）；所有"明度差 ≈L\*4"为 M3 容器色阶的量级估计，非像素测量。
- 未评估 i18n 长文案（德/俄语）对顶栏标题截断的影响（属批 5-C）。
- 未评估 Web/桌面键盘快捷键与顶栏的交互（属批 5-B）。

---

## 5. 收口建议（供 `docs/UX_STABILITY_PLAN.md` 采纳）

**「边界/接地」类（本席贡献）**：B-01 / B-02 / B-03（AppBar 边界三件套）→ 建议合并为一条 P0 修复："AppBar 滚动态 = surfaceContainer + level 2 elevation，取消双归零"。这一条修完，用户"内容穿过标题"的粗糙感会一次性消失，且**同时覆盖 31 个页面**（因为它落在 `theme.dart` 的 `appBarTheme` 上）。

**「三态一致性」类**：B-06 / B-07 / B-10 / B-11 / B-12 → 建议合并为："外壳三态共用一套目的地数据源 + 一套导航主题（新增 `navigationRailTheme`）+ 统一的安全区与限宽策略"。

**「密度/空」类**：B-05 / B-09 / B-21 → 建议合并为："导航带高度回到 M3 规范（80dp）+ 侧栏竖直居中并给底座 + expanded 档提高阅读列宽或分列"。

**「漂浮」类**：B-04 / B-13 → 建议合并为："顶栏脱离页面内容做 full-bleed，切 tab 时顶栏保持静止"。
