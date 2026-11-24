# 批 2 · C 席 —— 外壳与自适应复审（v15 之后）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 2 · 布局与信息密度 · C（外壳三态 + AppBar 融合 + 自适应）**
> - 版本：**v15.0.0**（`pubspec.yaml:21` → `version: 15.0.0+150000`）
> - 更新时间：**2026-11-24 22:39:12 (Asia/Shanghai)**
> - 仓库：`/root/OhGithubLost`；**只读审计，未改任何代码，未 commit / 未 push**
> - 审计对象：`lib/surface/app/client_shell.dart`（509 行）、`lib/surface/app/og_l_app_bar.dart`（158 行）、`lib/surface/app/og_l_app.dart`、`lib/surface/app/desktop_window.dart`（280 行）、`lib/surface/theme.dart`（导航/应用栏段）、`lib/surface/util/og_l_window_widths.dart`、`lib/surface/app/paged_controller.dart`
> - 纪律：未读任何 Flutter SDK / pub 缓存源码；证据全部为项目内 `file:line`，`rg -n` 可复现。

---

## 0. 结论摘要

v15 对外壳层的四项大改（AppBar full-bleed 化、限宽标记为待办、滚动融合删死代码改 M3 原生、切页透明度 0.94、导航轨主题化）**方向全部正确，主体已落地**。旧确证外壳条目 7 条中 **5 条已修**、1 条**部分未修**（G-11 语义图标层）、1 条**修法有残留**（G-05 限宽未下沉，宽屏内容层仍无阅读限宽）。

**新暴露的主要缺口集中在两点**：① 宽屏（≥600）下内容完全不限宽，1440p 桌面上一行文字可拉到 200+ 字符，`OgLWindowWidths.contentMax = 720`（og_l_window_widths.dart:9）成为**死常量**；② 侧栏态遗留 B-08/B-09 未修：导航轨无 SafeArea、`groupAlignment` 未设（目的地顶对齐、下方 70% 空柱），且 B-07 修了一半——轨面有色了但 `VerticalDivider(width:1)`（client_shell.dart:401）未删，双边界共存。

---

## 1. 闭环核对（旧确证 · 外壳条目逐条判定）

| # | 旧条目 | 判定 | 证据与说明 |
|---|---|---|---|
| G-02 | AppBar 无边界（elevation/scrolledUnder 双归零） | **已修** | `og_l_app_bar.dart:129-141`：`scrolledUnderElevation: 2`、`surfaceTintColor: Colors.transparent`、背景由 lerp(surface → surfaceContainerHigh) 连续插值；`theme.dart:308-318` `appBarTheme.scrolledUnderElevation: 2`、底色 surfaceContainerLow。双归零已消除，B-03 的插值终点也按要求升到 surfaceContainerHigh |
| G-05 | 宽屏 720 裁整个 Scaffold → 漂浮 | **修法有问题（半修）** | `client_shell.dart:316-324` 已移除外层 `Center+ConstrainedBox(720)`，AppBar full-bleed ✓；但注释自认的"待办：720 阅读限宽下沉到各页 body"**未做**——全库 `rg contentMax` 只剩常量定义一处引用（og_l_window_widths.dart:9），内容层无限宽，见新发现 N-01 |
| G-08 | 侧栏无接地 | **修法有问题（残留）** | 已修部分：`theme.dart:358-369` 新增 `navigationRailTheme`，轨面 surfaceContainerLow、indicatorColor primaryContainer、选中/未选中图标文字色对齐底栏 ✓（B-06 已闭环）。残留：`client_shell.dart:401` `VerticalDivider(width:1)` 未删（双边界）；无 `SafeArea` 包裹（B-08）；无 `groupAlignment`，目的地顶对齐（B-09） |
| G-09 | 切页透明度过冲/鬼影 | **已修** | `client_shell.dart:464-469`：控制器 [0,1]、`Opacity(0.94 + 0.06*t)` 夹紧、位移封顶屏宽 2%（client_shell.dart:443）、动画进行中不叠加反向段（:438）、0 档直切（:428） |
| B-01 | 滚动融合死代码（Primary 兜底恒 0） | **已修** | `og_l_app_bar.dart:96-99` 已删 `PrimaryScrollController.maybeOf`，只认显式控制器；`didUpdateWidget`（:101-112）正确处理控制器替换并回零进度；B-15 竖直 position + minScrollExtent 修正 + 夹紧（:116-128）。全库显式传参仍只有 dashboard（dashboard_page.dart:360），但其余页由 M3 原生 scrolledUnderElevation 兜底——兜底成立 |
| G-11 | 语义图标层（选中/未选中图标不成对） | **未修** | 「发现」目的地在底栏与导航轨均只有单一 `Icons.search`、无 selectedIcon（client_shell.dart:345、:386）——底栏另三项均有成对图标（folder/search?、person、settings），发现页是唯一破洞；宽窄屏切换时该图标无选中形变，选中态只剩药丸色。整块外壳文件无 `Semantics`/`Tooltip` 包装（desktop_window.dart:206 除外） |
| G-12 | 分页模式各自为政 | **已修** | `app/paged_controller.dart` 统一提取：快照 TTL 6s（:46）、刷新排队重放、代次防竞态、dispose 保护（:11-21 语义清单），页面层不再持私有分页实现 |

---

## 2. 回归核对（v15 大改是否引入新问题）

| 检查项 | 结论 | 证据 |
|---|---|---|
| 限宽改 full-bleed 后三态视觉一致？ | **大体一致，留两处不一致** | 导航底栏/轨已同语言（theme.dart:324-369 对齐字段）；① `VerticalDivider` 双边界只在宽屏出现（client_shell.dart:401）；② 底栏高度 80 + alwaysShow 标签（theme.dart:325-327、height:80）vs 轨 labelType 全随 extended 切换——600–1200 区间轨图标+全标签、底栏 80dp，密度感受不同（P2） |
| AppBar 与内容边界滚动时真的出现？ | **是** | 两条路径均通：显式控制器页（dashboard）连续插值到 surfaceContainerHigh（og_l_app_bar.dart:130-141）；其余 14 页走 M3 原生 scrolledUnderElevation=2。`theme.dart` appBarTheme 不再归零。**边界成立** |
| 去整页缩放后切页手感？ | **无回归** | `_OgLShellSlide` 弹簧夹紧（client_shell.dart:425-471）无过冲路径；`TickerMode` 停表 + 预加载边界（:300-313）未破坏懒挂载 |
| 宽屏顶栏贴边后内容显空？ | **是（见 N-01/N-02）** | 720 限宽未下沉，Expanded 全宽直接喂页面 body（client_shell.dart:324-327） |
| 桌面窗口栏（OgLTitleBar） | **无回归，一处打磨** | 拖拽/双击最大化/三键齐全，控件有 Semantics 标签（desktop_window.dart:206-230）；关闭键 danger 色 ✓；但 `_button` 命中区 46×38 < 48dp 无障碍目标（N-07） |
| og_l_app 文字缩放/动态色 | **无回归** | 缩放夹紧 [0.85,2.0] 在 builder 内层（og_l_app.dart builder 段）；DynamicColorBuilder 明暗分发正确 |

---

## 3. 新发现（旧审计未覆盖）

- **N-01【P1】宽屏内容完全无阅读限宽，`contentMax=720` 成死常量**。`rg -n contentMax lib/` 仅命中常量定义（og_l_window_widths.dart:9）；client_shell.dart:322 注释自认待办未做。≥1200 窗口下 issue 正文、列表行拉满全宽，长行 200+ 字符，与 v14 用户判词「空」同源。修复指令：各一级页 body 列表区包 `Center(ConstrainedBox(maxWidth: OgLWindowWidths.contentMax))`（或抽一个 `OgLContentGutter` 公共件）， AppBar 保持 full-bleed 不动。
- **N-02【P1】宽屏两栏结构性留白：rail 顶对齐 + 无底座**。`NavigationRail` 未设 `groupAlignment`（client_shell.dart:373-403），4 个目的地顶对齐，下方约 70% 竖直空柱；dashboard 的「新建仓库」FAB（dashboard_page.dart:384-390）只在手机语义下成立，桌面 rail 无任何底座动作。修复：`groupAlignment: 0.0` 居中，或 rail 底部补悬浮动作入口。
- **N-03【P1】600–1200 区间（平板/小桌面）rail 收窄态信息太素**：`extended` 只在 ≥1200（client_shell.dart:366），600–1200 显示纯图标列 + `labelType: all`；但 `navigationRailTheme.labelType: all`（theme.dart:361）与 client_shell 传入的 `none`（extended 时，client_shell.dart:370）**冲突**——widget 级参数覆盖主题，主题里的 labelType 实际只在别处使用时生效，属配置歧义，建议主题里删掉 labelType 或注释说明优先级。
- **N-04【P2】「发现」图标无选中态 + 语义标签缺失（G-11 残余的另一半）**：底栏/轨两份目的地是**手写副本**（client_shell.dart:342-364 与 :383-402），旧 B-10 建议的单一数据源未落地——新增第五个 tab 时极易漏改一处。同时 IconButton 均有 tooltip（dashboard_page.dart:364-380）✓，但 shell 层无 Semantics 包装。
- **N-05【P2】登录门/启动检查态的外壳断裂**：`!_checked` 时裸 `Scaffold(CircularProgressIndicator)`（client_shell.dart:296-298）无任何文案/骨架结构；登录门阶段返回链已防护（atHome 判定，client_shell.dart:244-250）✓，但该态与登录后外壳视觉完全不同源，首帧体验交给 2-A 席，此处仅记 shell 侧。
- **N-06【P2】桌面最小尺寸/多窗口行为**：desktop_window.dart 只处理装饰与最大化同步，未见 `setMinimumSize` 调用（rg 佐证）；极窄窗口会落进手机态底栏 + 桌面标题栏并存的混合外壳（标题栏三键 + 底栏双导航），窗口拉窄时视觉降级突兀。建议 `ogLWindow.init` 时设最小宽度 ≥ compact 断点。
- **N-07【P2】标题栏窗口控件命中区 46×38（desktop_window.dart:232-234）低于 48dp 无障碍目标；标题文字 labelMedium 无 selectable/长文截断策略（当前固定 'OhGithubLost' 风险低）**。
- **N-08【P2】切 tab 弹簧动画期间 `_controller.isAnimating` 即 return（client_shell.dart:436-439）：快速连点 3 个 tab 时第 2 次切换被静默吞掉，视觉上「点了没反应」，建议改为可中断重定向而非丢弃。

---

## 4. 用户满意度（工具感视角）

外壳现在**给了内容一个稳定的框**：AppBar 贴边、滚动有边界、侧栏有色面、切页不过冲——「漂浮感」在壳层的三要素（锚定/接地/边界）都立住了。剩下的「空」不在壳层代码质量，而在**宽屏密度决策未完成**（N-01/N-02）：窗口级框架越稳，中间一片无限宽的内容就越显空。把 720 限宽下沉 + rail 底座补上，「工具感」即可闭环。

---

## 5. 分级汇总

**P0**：无（外壳层无不可用/数据丢失问题）。

**P1**
1. N-01 宽屏内容无阅读限宽（720 死常量，v15 自认待办未做）
2. N-02 导航轨顶对齐无底座（groupAlignment 缺失 + 桌面无主操作入口）
3. G-11 未修：「发现」目的地无 selectedIcon，底栏/轨手写双副本（B-10 未落地）

**P2**
4. N-03 navigationRailTheme.labelType 与 widget 级参数冲突/歧义
5. G-08 残留：VerticalDivider 双边界、rail 无 SafeArea
6. N-05 启动检查态外壳裸转圈
7. N-06 桌面无最小宽度约束，窄窗混合外壳
8. N-07 标题栏控件命中区 <48dp
9. N-08 快速连点 tab 第二次切换被静默吞
10. 600–1200 档底栏/轨密度差异（回归检查项②）

---

## 6. 本席对三问的回答

1. **闭环**：7 条外壳旧确证——G-02/B-01/G-09/G-12 **已修**（修法正确、证据齐）；G-05 **修法有问题**（AppBar full-bleed 已达成，但承诺的限宽下沉未做，720 成死常量）；G-08 **部分已修**（轨面接地 ✓，双边界/SafeArea/groupAlignment 三处残留）；G-11 **未修**（发现页图标不成对 + shell 层无语义包装）。
2. **回归**：未发现 v15 引入的功能性回归；三态视觉语言已统一（theme.dart:324-369），AppBar 滚动边界两条路径均成立；遗留的是**未完成项**而非新坏点——最刺眼的是宽屏内容无限宽让「框架稳了、中间更空」。
3. **新发现**：8 条（N-01~N-08），其中 2 条 P1（宽屏无限宽、rail 空柱无底座），6 条 P2。满意度结论：外壳已提供稳定框架与锚点，「工具感」达成度约七成，缺口全部集中在宽屏密度与侧栏底座。

---

## 7. 已检查清单

- [x] lib/surface/app/client_shell.dart 全文 509 行（三态构建、PopScope/返回链、_OgLShellSlide、目的地两份副本、VerticalDivider）
- [x] lib/surface/app/og_l_app_bar.dart 全文 158 行（控制器生命周期、didUpdateWidget、进度节流、插值两端色、scrolledUnderElevation）
- [x] lib/surface/app/og_l_app.dart（MaterialApp 组装、文字缩放夹紧、动态色、themeAnimation）
- [x] lib/surface/app/desktop_window.dart 全文 280 行（标题栏、窗口控件、OgLWindowFrame、降级守卫）
- [x] lib/surface/theme.dart appBarTheme / navigationBarTheme / navigationRailTheme / dividerTheme 段
- [x] lib/surface/util/og_l_window_widths.dart（断点与 contentMax 全库引用面：rg contentMax lib/）
- [x] lib/surface/app/paged_controller.dart 头部语义清单（G-12 判定依据）
- [x] dashboard_page.dart 的 OgLAppBar/scrollController/SegmentedButton/FAB 使用点（rg scrollController lib/surface/pages/ → 仅 dashboard）
- [x] 全库 OgLAppBar 使用面（15 文件）、scrollController 显式传参面（仅 dashboard）、Semantics/Tooltip 在 shell 层命中面
- [x] docs/UX_CROSS_AUDIT/1-B-shell-appbar.md（旧 B-01~B-11 原文逐条对照）
- [x] /var/minis/skills/material-3/SKILL.md Layout / Navigation 节（adaptive 布局、app bar / navigation bar / rail 分类）
- [x] 未读任何 Flutter SDK / pub 缓存源码；未改代码、未 commit/push
