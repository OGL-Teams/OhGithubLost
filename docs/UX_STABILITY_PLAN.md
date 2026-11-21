# UX 交叉审计汇总与稳定性修复计划 / UX Cross-Audit Consolidation & Stability Remediation Plan

> **文档戳 / Document Stamp**
> - 更新时间 / Last Updated：**2026-11-22 01:32:43 (Asia/Shanghai)**
> - 对应版本 / Version：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - 仓库 / Repository：`/root/OhGithubLost`，工作副本 HEAD `f684160`；本文件为只读汇总产物，未修改 `lib/` 下任何代码，未 commit / 未 push。
>   This file is a read-only consolidation artifact; no code under `lib/` was modified; no commit or push was performed.
> - 输入 / Inputs：`docs/UX_CROSS_AUDIT_BRIEF.md` 及 `docs/UX_CROSS_AUDIT/` 下 1-A 至 5-C 共 15 份报告（全文逐份读取，未抽样）。
>   Fifteen reports (1-A through 5-C) under `docs/UX_CROSS_AUDIT/` plus `docs/UX_CROSS_AUDIT_BRIEF.md`, all read in full.
> - 体例 / Style：遵循 `docs/DOCUMENT_STYLE.md`（中英逐条对照 / line-by-line bilingual; 正式书面语 / formal written register）。
> - 复现 / Reproducibility：全部证据为 `file:line`，可用 `rg -n "<片段>" <路径>` 于 HEAD `f684160` 复现。
>   All evidence is `file:line`, reproducible at HEAD `f684160` via `rg -n "<pattern>" <path>`.

---

## 一、执行摘要 / Executive Summary

用户判词为「空、漂浮感、没有作为工具的稳定感」，全链路细节粗糙。本轮 15 席审计共记录 **309 条原始条目**（任务书估计约 320 条），经同根因合并去重后收敛为 **61 条确证问题**（严重 28 / 中 26 / 轻 7），其中高频系统化根因另以跨席编号回链。三项主诉均获得跨席量化确证，且均可在主题层或统一出口一处修复。

The user's verdict—"empty, floating, lacking the stability of a tool"—is corroborated quantitatively across seats. The fifteen audits recorded **309 raw findings** (brief estimate ≈320); deduplication by root cause yields **61 confirmed issues** (28 severe / 26 medium / 7 minor), with high-frequency systemic root causes cross-linked by stable IDs. All three complaints have cross-seat quantitative confirmation, and each is remediable at a single theme or shared-exit chokepoint.

| 主诉 / Complaint | 量化确证 / Quantitative confirmation | 根因落点 / Root cause | 交叉席 / Cross-seat |
|---|---|---|---|
| 漂浮感 / Floating | 卡片底 `#F5F3F7` 对页面 `#FAF9FD` 对比 **1.052**（ΔL\*2.0）；全库 `BoxShadow` **0 处**，card/dialog/sheet/snackbar/navbar/appbar 五类 elevation **全为 0**；16/30 页卡片与背景无差。Card vs page contrast 1.052; zero `BoxShadow`; five component classes at elevation 0; 16/30 pages show no card contrast. | `theme.dart:213/217/228/251/262` | 2-A S1/S4、2-B S3、1-A S3、5-B A-M1 |
| 空 / Empty | 全库平均一屏 **5.1 条**（列表页 8–11，详情/表单页 1；GitHub 网页 18–22）；issue 详情首屏 **0 条评论**；引导页留白 **55%**；`OgLAsyncEmptyPane` 14 页无下一步动作；dashboard 空态 **半屏 `SizedBox` 占位**。Mean 5.1 items/screen; issue detail shows zero comments above the fold; onboarding 55% whitespace; 14 pages of action-less empty states; a half-screen empty placeholder. | `async.dart:398-417/485-497`、`theme.dart:329-341`、`issue_page.dart:741-787` | 1-A §0、1-C S-01/S-03、3-B S-03/S-07、5-A F-4 |
| 不稳定 / Unstable | **74 处** Divider 中 `outlineVariant` 对任意底色仅 **1.30–2.00:1**（<3:1），形同虚设；**16/30 页**弹层无锚定（卡片与 sheet 同为 `surfaceContainerLow`、弹层零投影零描边）；AppBar 滚动态在 **14/15** 个 `OgLAppBar` 页从未生效，全库 31 页仅 1 页具备可感知顶栏边界。**74 dividers** at 1.30–2.00:1; **16/30 pages** with unanchored overlays; AppBar scroll-fusion dead in **14/15** pages, only 1/31 pages has a perceptible top-bar boundary. | `theme.dart:344-348/228-255`、`og_l_app_bar.dart:83/133-143` | 2-B S1/S4、1-B B-01/B-02、5-B A-M1、4-C C-01 |

**首要结论 / Primary finding**：主题层 `theme.dart` 一处改动即可同时修复卡片对比、分割线强度、输入框边界、SnackBar 动作色四类高频症状，覆盖全部 30 页，为最快见效的第一批。
A single edit cluster in `theme.dart` simultaneously fixes card contrast, divider strength, input borders, and SnackBar action color across all 30 pages; this is the fastest-yield first batch.

---

## 二、合并去重方法 / Deduplication Method

- **确证问题 / Confirmed issue**：同一根因被两席及以上报告，或同一根因的多种表现合并为一条，赋予跨席稳定编号（`B-` 边界 / `G-` 接地 / `D-` 密度 / `F-` 反馈）。
  A confirmed issue is one root cause reported by two or more seats, or multiple manifestations of one root cause, assigned a stable cross-seat ID.
- **同根因不同表现归组 / Grouping**：例如「描边色失效」统合了分割线、卡片 side、Chip side、SegmentedButton side、README 引用线、代码行号线、登录「或」线等 8 项表现（2-B S1/S3/M8/M14/L16/L17/L18 + 5-B A-M1），合并为 B-01。
  E.g. ineffective outline color unifies eight manifestations into B-01.
- **明确不重复计 / Explicitly de-duplicated**：4-B 已声明不重复 2-C 的动效参数；3-B 与 1-C 的空态半屏占位合并（仅 `dashboard_page.dart:452` 一处为真实空态半屏）；5-C C-S8 与 5-A B-4 启动失败页主题合并。
  4-B defers motion parameters to 2-C; the half-screen empty state occurs only once; 5-C C-S8 merges into 5-A B-4.
- **分级 / Severity**：严重（直接造成主诉）/ 中（明显拖慢或不一致）/ 轻（打磨）；多席确证优先。
  Severity: severe (directly causes a complaint) / medium (noticeable inconsistency) / minor (polish); multi-seat confirmation takes precedence.

**四类分布 / Distribution by category**

| 类别 / Category | 确证问题数 / Count | 严重/中/轻 / S/M/L | 主导文件 / Dominant file |
|---|---|---|---|
| 边界 / Borders | 9 | 2 / 4 / 3 | `theme.dart` |
| 接地 / Grounding | 12 | 6 / 6 / 0 | `theme.dart`、`client_shell.dart` |
| 密度 / Density | 14 | 7 / 6 / 1 | `theme.dart`、`async.dart`、各列表页 |
| 反馈 / Feedback | 26 | 13 / 10 / 3 | `async.dart`、`notifier.dart`、`motion.dart` |
| **合计 / Total** | **61** | **28 / 26 / 7** | — |

---

## 三、四类修复计划 / Four-Category Remediation Plan

> 每项格式 / Item format：编号（跨席来源）→ 根因文件:行 → 修复指令 → 影响范围 → 工作量（S/M/L）。
> 工作量口径 / Effort scale：S = ≤10 行且单点；M = 10–50 行或 2–5 文件；L = 跨页重构或新增组件/测试。

### 3.1 边界类 / Borders（边界消失感 / loss of edges）

**B-01【严重】全局描边色 `outlineVariant` 对任意底色 1.30–2.00:1，74 条分隔线形同虚设**
- 跨席 / Sources：2-B S1/S3/S6/M8/M14/L16/L17/L18/L20；5-B A-M1；2-B 0.1–0.3 实测。
- 根因 / Root：`theme.dart:344-348`（`dividerTheme.color = scheme.outlineVariant`）、`:215`（card side）、`:356`（chip side）、`:379`（segmented side）、`:254`（sheet dragHandle）；`readme_view.dart:397`、`code_editor_field.dart:628`、`login_page.dart:455/464`、`discover_rows.dart:56-62`。
- 修复 / Fix：在 `theme.dart` 的 `OgLSemanticColors` 附近新增 `outlineVariantStrong`（设计目标：对 surface / surfaceContainerLow / surfaceContainerHighest 明暗均 ≥3:1，建议明 `#94939A` / 暗 `#707075` 起，按 WCAG 公式校准）；将 `dividerTheme.color`、card side、chip side、segmented side、sheet dragHandle、README 引用竖线、代码行号竖线、登录「或」线统一改用它；`discover_rows.dart:56-62` 已读行左边线不再退回 `surface`，改 `outlineVariantStrong` 底线 + 未读态 primary 加宽。
  新增 token（Add token）；八类描边替换（replace eight edge classes）；一处定义全库生效（one definition, global effect）。
- 影响 / Scope：全部 30 页 + 组件 + 外壳 / all 30 pages, widgets, shell。工作量 / Effort：**S**。

**B-02【严重】输入框空闲态 `BorderSide.none`，26 处裸 `OutlineInputBorder()` 覆写掩盖真实边界来源**
- 跨席 / Sources：2-B S2/M11；3-C C-17/C-18。
- 根因 / Root：`theme.dart:393-400`（`border`/`enabledBorder` 均 `borderSide: BorderSide.none`，仅 `:401-404` focused 有 1.5px）；26 处覆写见 2-B M11 清单（`new_repo_page.dart:152/161`、`new_issue_page.dart:147/156`、`repo_page.dart:711/1472/1489/1789/2505/4284/4395/4483`、`settings_page.dart:1912/1921` 等）；`code_editor_field.dart:781-791/839-849` 查找/替换框 `InputBorder.none`。
- 修复 / Fix：`theme.dart:395/399` 的 `BorderSide.none` → `BorderSide(color: scheme.outlineVariantStrong)`（随 B-01），保留 filled，形成「浅填充 + 可见 1px 框」；删除 26 处裸 `border:` 覆写统一吃主题；查找/替换框改 `OutlineInputBorder(borderRadius: OgLRadius.md)` 或 `filled:true + fillColor: surfaceContainerHighest`。
- 影响 / Scope：全库 47 个 TextField 中的表单/搜索/编辑器输入 / all form, search, editor inputs。工作量 / Effort：**M**。

**B-03【中】13/30 页零 Divider，整页区块边界纯靠留白；divider 高度 24/28/20/32 失控**
- 跨席 / Sources：2-B S5/M13/M15；1-C M-15。
- 根因 / Root：`network_page.dart:48-53`、`download_manager_page.dart:275-276`（separator 为 `SizedBox(height: sm)`）、`repo_tags_page.dart:230`、`settings_section_page.dart:29-38`、`file_preview_page.dart:539`、`code_editor_page.dart:481`；`settings_page.dart:470/1554/1819/1825/1906`、`repo_page.dart:4365/4438/4494`。
- 修复 / Fix：为零线页分组容器补 1px `outlineVariantStrong` 上边线；下载页 separator 改 `Divider(height:1, indent: OgLSpace.lg)`；语义收敛为两类 token——`height:1`（行间）与 `height: OgLSpace.lg`（区块），禁用 24/28/20/32 混用；设置/关于分组加 `surfaceContainerLowest` 底色块（见 G-07），Divide 数降为「每组一条」。
- 影响 / Scope：13 页 + 设置/关于 / 13 pages plus settings & about。工作量 / Effort：**M**。

**B-04【中】弹层 shape 无 side、`barrierColor` 缺失，弹层无「暗底 + 亮边」双层边界**
- 跨席 / Sources：2-B S4/M9/M10；4-C C-14。
- 根因 / Root：`theme.dart:228-241`（dialog shape 无 side）、`:250-257`（sheet shape 无 side）、`:260-274`（snackbar 无 side）；`overlays.dart:61-76`（`ogLShowSheet` / `ogLShowDialog` 无 `barrierColor`）；`search_page.dart:937` 直调 `showModalBottomSheet`。
- 修复 / Fix：给 `dialogTheme.shape` / `bottomSheetTheme.shape` 补 `BorderSide(color: scheme.outlineVariantStrong)`；`ogLShowSheet`/`ogLShowDialog` 加 `barrierColor: scheme.scrim.withValues(alpha:.32)`；弹层 elevation 与底色按 G-04 同步；`search_page.dart:937` 收口 `ogLShowSheet`（并见 F-21）。
- 影响 / Scope：全库弹层 / all overlays。工作量 / Effort：**M**。

**B-05【中】触控目标 11 处被 `VisualDensity.compact` 压到 40×40，桌面标题栏 46×38**
- 跨席 / Sources：5-B A-S2/A-S3/A-M7/A-L5。
- 根因 / Root：`code_editor_toolbar.dart:117/123/129/136/142/148/154`、`log_search.dart:80/86`、`search_page.dart:239`、`release_detail_page.dart:548` 的 `visualDensity: VisualDensity.compact`；`desktop_window.dart:43`（`kOgLTitleBarHeight=38`）、`:215`（`SizedBox(46,38)`）；`theme.dart:454`（`iconSize=20` 低于 M3 默认 24）。
- 修复 / Fix：删除 11 处 `VisualDensity.compact`（主题 `minimumSize: Size(48,48)` 自动生效），工具栏不足时横向滚动而非缩按钮；标题栏高度改 48 并按 `max(48, 38*textScaler)` 缩放，窗口按钮 `SizedBox(48,48)`；`theme.dart:454` `iconSize` 回 24。
- 影响 / Scope：编辑器工具栏、日志搜索、搜索卡、Release、桌面窗口 / editor, log search, search card, release, desktop title bar。工作量 / Effort：**S**。

**B-06【中】暗色 SnackBar 动作文字 `inversePrimary` on `surfaceContainerHighest` = 1.90:1，几乎不可读**
- 跨席 / Sources：5-B A-S1（严重）；4-C C-10；2-A M10。视觉对比归本类，语气/action 归 F-07。
- 根因 / Root：`theme.dart:271`（`actionTextColor: scheme.inversePrimary`）、`:263-265`（暗色 `backgroundColor: surfaceContainerHighest`）。
- 修复 / Fix：`theme.dart:271` 改 `actionTextColor: brightness == Brightness.dark ? scheme.onSurface : scheme.inversePrimary`（深色 9.52:1）；或暗色底色改 `scheme.inverseSurface` 保持 inversePrimary（5.01:1）。二选一，禁止现状。
- 影响 / Scope：全部 SnackBar 动作，暗色主题 / all snackbar actions in dark theme。工作量 / Effort：**S**。

**B-07【轻】已读行左边界线退回 `surface` 而非变淡，列表左侧忽有忽无**
- 跨席 / Sources：2-B M12。
- 根因 / Root：`discover_rows.dart:56-62`（`Border(left: BorderSide(color: unread ? primary : surface, width: xxs))`）。
- 修复 / Fix：未读/已读共用 `outlineVariantStrong` 底线，未读态叠加 primary 并加宽至 3px。
- 影响 / Scope：动态流行 / discover feed rows。工作量 / Effort：**S**。

**B-08【轻】disabled 前景仅 onSurface@38%（浅色 2.28–2.34:1），按钮像被擦掉**
- 跨席 / Sources：5-B A-M3；3-B S-22（静默置灰，归 F-22）。
- 根因 / Root：`theme.dart` 四个按钮 Theme 未定义 `disabledForegroundColor`。
- 修复 / Fix：四类按钮 Theme 加 `disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.60)`（浅色约 4.6:1）、`disabledBackgroundColor: scheme.surfaceContainerHigh`，保留 `onPressed:null` 语义。
- 影响 / Scope：全库禁用控件 / all disabled controls。工作量 / Effort：**S**。

**B-09【轻】主分隔线全库 1px 顶格、无 indent/endIndent**
- 跨席 / Sources：2-B L20。
- 根因 / Root：`flat_list.dart:47`、`settings_page.dart` 多处、`search_page.dart:143/783/1046/1373` 均 `Divider(height:1)` 无缩进。
- 修复 / Fix：全局 `dividerTheme` 加 `indent: OgLSpace.lg`（MD3 列表分隔常用 16dp），或 separator 统一设置。
- 影响 / Scope：全部列表分隔 / all list separators。工作量 / Effort：**S**。

### 3.2 接地类 / Grounding（漂浮感 / lack of anchoring）

**G-01【严重】全库零投影 + 卡片底仅比页面深 2 级 L\*，卡片浮而无锚**
- 跨席 / Sources：2-A S1/S5/S12；2-B S3；1-A S3；5-B A-M1。
- 根因 / Root：`theme.dart:213`（card `color: surfaceContainerLow`，对页面 1.052）、`:217`（`elevation:0`）；`rg "BoxShadow" lib/` 0 命中；30 页均未设 `Scaffold.backgroundColor`（`repo_page.dart:2470/2745/3050/3300` 四处为 `Colors.transparent`）。
- 修复 / Fix：R1——`theme.dart:213` 卡片底改 `scheme.surfaceContainer`（明 `#EFEDF1`，对页面 1.085，+ 描边合计可辨）；ThemeData 加 `scaffoldBackgroundColor: scheme.surface` 一次设置，30 页自动一致，`repo_page.dart` 四处 `Colors.transparent` 改 `scheme.surface`；R2——`:217` card elevation 0→1（或保留 0 但保留/强化 B-01 描边），配 `shadowColor: scheme.shadow.withValues(alpha:.12)`。
  Single theme edit propagates to all pages. 影响 / Scope：16 个含卡片页 + 全库底色 / 16 card pages plus global background。工作量 / Effort：**S**。

**G-02【严重】AppBar 与内容无边界：elevation 与 scrolledUnderElevation 双双归零，滚动融合从未发生**
- 跨席 / Sources：1-B B-01/B-02/B-03/B-14/B-15；2-A S6；5-C C-S1；2-C C-03。
- 根因 / Root：`theme.dart:285-286`（`elevation:0` + `scrolledUnderElevation:0`）、`:287`（`backgroundColor: surface`）、`:288`（`surfaceTintColor: transparent`）；`og_l_app_bar.dart:83`（`PrimaryScrollController.maybeOf` 全库无注入，14/15 页恒 progress=0）、`:115/117`（`positions.first` + `pixels` 未减 minScrollExtent）、`:133-136`（插值终点 `surfaceContainer` 太弱）、`:139-149`（1% 台阶整栏重建）。
- 修复 / Fix：P0——`theme.dart:286` `scrolledUnderElevation:0`→`2`；`og_l_app_bar.dart:133-136` 插值终点 `surfaceContainer`→`surfaceContainerHigh` 并在进度 >0.3 时插值显形 `outlineVariantStrong` 底线；删除「Primary 兜底」假设，改由 body 显式传 `ScrollController` 或由 M3 原生 `scrolledUnderElevation` 接管；`:117` 改 `pixels - minScrollExtent` 并约定取竖直 position；`:139-149` 拆「外层 AppBar 建一次 + 内层背景色重建」，actions 用 `const`/`RepaintBoundary` 隔离。
- 影响 / Scope：全库 31 页顶栏 / all 31 page app bars。工作量 / Effort：**M**。

**G-03【严重】弹层层级链断裂：BottomSheet 与 Card 同为 `surfaceContainerLow`，Dialog 跳档，弹层零 elevation**
- 跨席 / Sources：2-A S2/S3/S4/M14；2-B S4；4-C C-07/C-15。
- 根因 / Root：`theme.dart:228-255`（dialog `surfaceContainerHigh`/elev 0、sheet `surfaceContainerLow`/elev 0）、`:262`（snackbar elev 0）、`:299`（navbar elev 0）；`search_page.dart:937`（唯一 sheet 调用点，底层 `_RepoCard:212`）。
- 修复 / Fix：R3——sheet `theme.dart:252` `surfaceContainerLow`→`surfaceContainerHigh`（与卡片拉开 2 档）；dialog `:229` `surfaceContainerHigh`→`surfaceContainerHighest`；R2——dialog elevation 0→3、sheet 0→1、snackbar 0→3；B-04 补 shape side + barrierColor。
- 影响 / Scope：全库 dialog/sheet/snackbar / all overlays。工作量 / Effort：**S**。

**G-04【严重】输入框占用全库最高档 `surfaceContainerHighest`，卡浅框深、层级倒置**
- 跨席 / Sources：2-A S7/M13/M17；2-B S2；3-C C-11。
- 根因 / Root：`theme.dart:387`（`fillColor: surfaceContainerHighest`，全库该 token 命中 20 处）；`code_editor_page.dart:481/609`、`code_editor_field.dart:110/752`、`readme_view.dart:390/393`、`dashboard_page.dart:640`（注释把最高档当「同款底色」规范推广）；徽标 9 处（2-A M17 清单）。
- 修复 / Fix：R4——`theme.dart:387` → `scheme.surfaceContainerHigh`（level 3）；代码编辑器/代码块/徽标统一 `surfaceContainer`（level 2）或 `surfaceContainerLowest`（下沉，见 G-07），`:640` 注释同步改写；`repo_page.dart:1308` chip 覆写 `secondaryContainer` 收编到 `chipTheme`。
- 影响 / Scope：20 处最高档调用点 / 20 call sites。工作量 / Effort：**M**。

**G-05【严重】宽屏内容 + AppBar 一并裁成 720dp 居中块，两侧空墙；底栏/侧栏夹压内容**
- 跨席 / Sources：1-A S7；1-B B-04/B-05/B-12/B-19/B-21；3-C C-11。
- 根因 / Root：`client_shell.dart:321-330`（`Center + ConstrainedBox(maxWidth: OgLWindowWidths.contentMax)` 包整个页面 Scaffold 含 AppBar）、`:337`（`NavigationBar`）、`:374-402`（`NavigationRail`）；`og_l_window_widths.dart:9`（`contentMax=720`）、`:17`（`expanded=1200`）；`theme.dart:298`（`height:64`，M3 规范 80）、`:300`（navbar `surfaceContainer`，对页面 1.055）、`:287`（appbar `surface`，上下异色带）。
- 修复 / Fix：限宽只作用于内容不作用于 Scaffold/AppBar（两方案择一：限宽下沉各页 body，或壳层 `Row[rail | Column[全宽 AppBar, 限宽内容]]`）；`contentMax` 720→960–1040（阅读型页单独保留 720）；宽屏走多列自适应而非整体居中；`:321` 限宽改为无条件套用以保证 gutter 连续；底栏高度 64→80 或 `labelBehavior` 改 `onlyShowSelected`（二者择一）；navbar 底改与 AppBar 同族或给顶边线。
- 影响 / Scope：全部 30 页渲染宽度 + 外壳 / all pages' render width plus shell。工作量 / Effort：**L**。

**G-06【严重】启动链路三次「空/闪变」：占位屏配色脱节、`_checked` 裸转圈帧、失败页强制深色**
- 跨席 / Sources：5-A B-1/B-2/B-3/B-4/B-5/B-6/B-7；5-C C-S8；4-B §2 轴一切面。
- 根因 / Root：`boot_splash.dart:26-27`（硬编码 `0xFF101418/0xFFFBFCFE`，仅随 platformBrightness）、`:61-64`（不确定进度环）；`main.dart:79/222-287`（内核引导无 15s 超时）；`client_shell.dart:134-137`（`Scaffold(body: Center(CircularProgressIndicator()))`）、`:118-127`（令牌读取失败静默入日志）；`og_l_app.dart:173-178`（失败页写死 `Brightness.dark` + `kOgLErrorSeedColor`）、`:204-240`（长堆栈无滚动容器）。
- 修复 / Fix：`OgLBootSplash` 增 `background/foreground` 参，`main.dart:79` 传 `themeFor(userMode)` 同色；`:134-137` 改复用 boot_splash 锚定结构（icon+标题+转圈）或至少「正在恢复会话…」；失败页 body 改 `SingleChildScrollView > ConstrainedBox(maxWidth:640) > Column` + 「复制日志/重试启动」，brightness 跟随平台、locale 跟随系统；`kernel.boot(...).timeout(15s)`；读失败在登录页顶部补 info 卡；三态切换处（登录门/引导/首页）包 `AnimatedSwitcher(OgLAnim.medium)`。
- 影响 / Scope：冷启动全链路 / cold-start chain。工作量 / Effort：**M**。

**G-07【中】`surfaceContainerLowest` 全库 0 次使用，设置/关于分组仅靠灰字与弱线，列表选中态近乎不可见**
- 跨席 / Sources：2-A S8/M18/L21/L22；2-B M15；1-C M-06；3-B S-05。
- 根因 / Root：`theme.dart:329-347`（listTileTheme 无 tileColor 层级）、`:340`（选中态 `primaryContainer.withValues(alpha:0x55)`）；`settings_group.dart:225`（仅 `onSurfaceVariant`）；`gists/about/notifications/profile/network/drafts/repo_tags` 七页裸列表仅 1px 弱线。
- 修复 / Fix：R7/R8——ThemeData 增 `scaffoldBackgroundColor: scheme.surface`，设置/关于分组引入 `surfaceContainerLowest` 下沉底色块；`theme.dart:340` 选中态改不透明 `scheme.primaryContainer`；listTileTheme 加 `tileColor: scheme.surface`；裸列表页按 B-03 补分组线。
- 影响 / Scope：设置/关于 + 7 裸列表页 / settings, about, 7 bare-list pages。工作量 / Effort：**M**。

**G-08【中】桌面侧栏无接地：轨面与页面同色、仅一根 1.621 的 VerticalDivider、无安全区、目的地顶对齐**
- 跨席 / Sources：1-B B-06/B-07/B-08/B-09/B-10/B-11/B-20；2-A M16；2-B S6。
- 根因 / Root：`theme.dart` 全文无 `navigationRailTheme`（仅 `:297-326` navigationBarTheme）；`client_shell.dart:404`（`const VerticalDivider(width:1)`）、`:374-402`（NavigationRail 无 SafeArea、无 groupAlignment、无 backgroundColor）、`:342-364` 与 `:383-402` 两份目的地副本；`desktop_window.dart:138`（侧栏 `surfaceContainer` 对主区 1.055）。
- 修复 / Fix：新增 `navigationRailTheme`（indicator `primaryContainer`、background `surfaceContainerLow`、labelType all、elevation 0，与 navigationBarTheme 同语言）；删 `client_shell.dart:404` VerticalDivider 改由轨面底色 + 1px 强色右边界承担；包裹 `SafeArea(top:true)`；`groupAlignment:0.0` 或底部补主操作；两份目的地合并为同一 `List<OgLDestination>` 数据源；补「发现」`selectedIcon`；R9 `desktop_window.dart:138` 改 `surfaceContainerLow` 或加 1px 强色边线。
- 影响 / Scope：≥600dp 外壳三态 / shell at ≥600dp。工作量 / Effort：**M**。

**G-09【中】切 tab 时整页含 AppBar 横移 + 半透明鬼影（opacity 0.70），顶边锚点被拆**
- 跨席 / Sources：1-B B-13/B-14；2-C C-05/C-09/C-18/C-19；4-B B-06/B-07。位移/透明度参数归 2-C，换位语义归 4-B（F-17），本条记「锚点漂移」的接地症状。
- 根因 / Root：`client_shell.dart:503-508`（`Opacity(0.7+0.3t)` + `FractionalTranslation`，`lowerBound:-1/upperBound:2` 允许过冲）。
- 修复 / Fix：`client_shell.dart:503` 透明度下限 0.7→0.94 或删 Opacity 包装；位移限 ≤屏宽 2% 且边界收回 `[0,1]`；顶栏由壳层持有保持静止，只对内容层做位移。
- 影响 / Scope：外壳 tab 切换 / shell tab switch。工作量 / Effort：**S**。

**G-10【中】同类页面模式漂移：15 页 `OgLAppBar` vs 15 页原生 `AppBar`，正好对半**
- 跨席 / Sources：5-C C-S1/C-L2/C-L3；1-B B-18。
- 根因 / Root：14 页 + `search_page.dart:716/1318` 两处用 `OgLAppBar`；15 页原生 `AppBar`（`issue_page.dart:723`、`pull_page.dart:109`、`commit_page.dart:93` 等清单见 5-C §0）。
- 修复 / Fix：统一到 `OgLAppBar`（其已支持 `actions`/`bottom`），自建 ScrollController 页显式传 `scrollController:` 以启用渐变；或在 `theme.dart:283-294` 一次修好原生栏滚动态后再统一收敛。
- 影响 / Scope：全部 30 页顶栏 / all 30 app bars。工作量 / Effort：**M**。

**G-11【中】图标语义四类冲突：复制四型、刷新三型、`Icons.link` 三义，缺单一事实源**
- 跨席 / Sources：5-C C-S2/C-S3/C-S4/C-M1/C-M3/C-L1/C-L5；3-A L19。
- 根因 / Root：`release_detail_page.dart:355`/`repo_page.dart:592`（复制配 `Icons.link`）；`search_page.dart:949`（全库唯一 `Icons.copy`）、`:959`（`Icons.language`）；`download_manager_page.dart:211`（`restart_alt`）vs `:489`（`refresh`）；`action_run_page.dart:622/631`。全库 130+ 处内联 `Icon(Icons.*)`，无语义映射层。
- 修复 / Fix：新建 `lib/surface/util/og_l_icons.dart` 导出 `OgLIcons.{copy, copyAll, refresh, retryAll, openExternal, delete, deleteBatch, cancel, overflowTop, overflowRow}`；复制动作统一 `content_copy`，打开外部统一 `open_in_new`，`Icons.link` 仅留静态 URL 展示；状态 `sync` 改进度指示；CI grep 禁止 `Icons.copy|Icons.language|Icons.link` 在复制/打开语境复发。
- 影响 / Scope：全库图标调用 / all icon call sites。工作量 / Effort：**M**。

**G-12【中】分页模式三分：search/dashboard/repo_tags 自动无限滚动，repo_page 仍手动「加载更多」**
- 跨席 / Sources：5-C C-S6；1-A M5。
- 根因 / Root：`repo_page.dart:770-830`（`onPressed: paged.loadMore` 手动按钮）与文件头 `:8` 注释自称「统一加载更多」已漂移；对照 `dashboard_page.dart:129-136`、`search_page.dart:445-449`、`repo_tags_page.dart:221-223`。
- 修复 / Fix：`repo_page.dart:770-830` 改 `NotificationListener<ScrollNotification>` 距底 300px 自动加载，手动按钮降级为失败兜底重试；同步修正 `:8` 注释。
- 影响 / Scope：仓库页主列表 / repo page main lists。工作量 / Effort：**M**。

### 3.3 密度类 / Density（「空」/ emptiness）

**D-01【严重】页面 gutter 五档并存（0/12/16/24/32），跨页内容宽度跳变**
- 跨席 / Sources：1-A S2；5-C C-M4；1-C M-07/M-09。
- 根因 / Root：`onboarding_page.dart:249/307`（24）、`release_detail_page.dart:318`（24）、`file_preview_page.dart:379/541/648`（32）、`legal_text_page.dart:100/124`（12）、`dashboard_page.dart:475`/`gists_page.dart:152`/`drafts_page.dart:219`（无页面级 padding）、`repo_page.dart:2245`（16）。
- 修复 / Fix：`og_l_space.dart` 增 `pageGutter = EdgeInsets.symmetric(horizontal: lg)`；上述 24→16、32→16、12→16，三处裸页补 `pageGutter`；页头筛选外边距统一 `fromLTRB(lg, md, lg, xxs)`（与 5-C C-M4 合并）。
- 影响 / Scope：全部 30 页 / all 30 pages。工作量 / Effort：**M**。

**D-02【严重】卡片套卡片 / 页面 padding 套卡片 padding，正文距屏幕边 32–48dp**
- 跨席 / Sources：1-A S3；1-C M-08。
- 根因 / Root：`login_page.dart:353/357/477`（三层 `all(lg)`）、`commit_page.dart:107/115`、`pull_page.dart:123/141`、`workflow_dispatch_page.dart:437/441`、`legal_text_page.dart:101/169/176`；`pull_page.dart:159-161`（双重 16 缩进）。
- 修复 / Fix：`login_page.dart:353` 改 `symmetric(horizontal: lg, vertical: md)`、`:357/:477` 改 `all(md)`；`commit_page.dart:107`/`pull_page.dart:123` 页面级改 `fromLTRB(lg, md, lg, lg)`；`workflow_dispatch_page.dart:437` 改 `symmetric(horizontal: lg, vertical: sm)` + ListTile `dense:true`；`legal_text_page.dart:169` `all(xl)`→`all(md)`；`pull_page.dart:159-161` 双重缩进二选一保留一次。
- 影响 / Scope：表单/详情类 6 页 / six form-detail pages。工作量 / Effort：**M**。

**D-03【严重】全局列表行模板 16–28dp 死区，填充率 45–56%，一屏仅 11 条；仓库目录行仅标题（36%）**
- 跨席 / Sources：1-C S-01/S-02；1-A S5/S6；1-C L-20。
- 根因 / Root：`theme.dart:329-341`（`contentPadding.vertical=xxs(4)`、`minVerticalPadding=sm(8)` 叠加 ListTile 56/72dp 最小高）；`repo_page.dart:2584-2602`（目录行 subtitle 为 null）、`:2497-2501`（面包屑+过滤框额外占 ~180dp）；`dashboard_page.dart:493-513`（两行 subtitle + 冗余 chevron）；`discover_rows.dart:66-115`（`OgLFeedRow` 已做到 71%/14 条却只用于动态流）。
- 修复 / Fix：`theme.dart:329-341` `minVerticalPadding` sm(8)→xxs(4)，数据列表引入 `dense:true`（两行 ≤64dp、一屏 ≥13）；抽取 `lib/surface/widgets/compact_row.dart`（或把 `OgLFeedRow` 提升为 `OgLCompactRow`）供 repo/issue/pull/gists/search/dashboard 六页复用；`repo_page.dart:2596-2602` 目录行补 meta；`dashboard_page.dart:507-513` subtitle 1 行 + 删 trailing chevron + `dense:true`；面包屑+过滤框改 `SliverPersistentHeader` 吸顶。
  量化目标 / Target：一屏 5.1→8.5 条（列表页 8→12–14）。
- 影响 / Scope：六个列表页 + 主题 / six list pages plus theme。工作量 / Effort：**L**。

**D-04【严重】issue 详情首屏 0 条评论；引导页留白 55%；协议页/登录页头部块吃满首屏**
- 跨席 / Sources：1-A S1/S4/M9；1-C S-03。
- 根因 / Root：`issue_page.dart:741-787`（头部块 ~420dp，评论从 `:806` 才开始）、`:748/756/758/760/774/784/787` 段间距 sm/md/lg 失衡；`onboarding_page.dart:307/317/320/249/276-277`（24 四周 + 顶部 24 + hero 图标）；`legal_text_page.dart:98-101/122-125/135-136/171`（三条横幅 ~200dp）。
- 修复 / Fix：`issue_page.dart:741-742` 顶部 lg→md、`:760/:784` md/lg→sm/md、`:762` 正文 Card 改无卡纯文本、`:748/756/758` sm→xxs、`:787` sm→md（目标首屏 ≥1 条评论）；`onboarding_page.dart:307` all(xl)→symmetric(lg,md)、`:317` 删顶部 xl、`:320` lg→md、`:249/:276-277` xl→lg、`:319` hero→avatar、`:358` 起权限卡加 `Column(spacing: sm)`；`legal_text_page.dart` 两条横幅合并为一条 ListTile + 语言行并入，正文 `:171` all(lg)→fromLTRB(lg,md,lg,lg)。
- 影响 / Scope：issue / onboarding / legal_text 三页 / three pages。工作量 / Effort：**M**。

**D-05【严重】空态是半屏空白 + 一枚图标 + 一行字，14 页无下一步动作；dashboard 半屏占位**
- 跨席 / Sources：1-C S-03/L-21；3-B S-03/S-04/S-07/S-23/S-24；5-A F-4。
- 根因 / Root：`async.dart:398-417`（`OgLAsyncEmptyPane` 默认 `Icon(avatar)` + 单行 Text，`action` 缺省 null）；`async.dart:485-497`（`OgLAsyncSliver` 无 `emptyAction` 参数，三个高频 sliver 空态架构上无法带 CTA）；`dashboard_page.dart:449-455`（外层 `SizedBox(height: screen*0.5)`）；调用点 14 页见 3-B S-03 表。
- 修复 / Fix：`async.dart:398-417` 空态加 `constraints: BoxConstraints(maxWidth:320)`、图标 avatar→xl、支持可选副标题 + 必填 `action`；`async.dart:485-497` 增 `this.emptyAction`（Widget?），`:538-546` empty 分支传 `OgLAsyncEmptyPane(action: emptyAction)`，三个使用方（issue 评论 `:793-798`、commit `:156-159`、pull `:169-171`）补 CTA；删 `dashboard_page.dart:451-453` 半屏 SizedBox；14 页按 3-B S-03 表逐页加 `FilledButton.tonal` CTA（drafts→新建草稿、profile→添加账号、gists→新建、gist_detail→新建文件、notifications→清除筛选、workflow_dispatch→重试等）；搜索空态加「清空重搜」。
- 影响 / Scope：14 页 + 统一出口 / 14 pages plus shared exit。工作量 / Effort：**M**。

**D-06【严重】唯一加载态是「空白屏 + 裸转圈」，16 页共用；同页两套加载视觉**
- 跨席 / Sources：3-B S-01/S-08/S-13/S-14；5-A F-3；1-C S-03。
- 根因 / Root：`async.dart:293-300`（AsyncView loading = `Center(Padding(xxl, CircularProgressIndicator))`）、`:552-560`（OgLAsyncSliver 同款）；`search_page.dart:134-147`（唯一骨架 `_SkeletonList`，仅推荐 tab）vs `:1362-1364` 裸转圈；`async.dart:141-163`（无 300ms 延迟/最小显示时长）；`repo_page.dart:789/2452/2527/818` 四处裸转圈。
- 修复 / Fix：从 `search_page.dart:134-147` 抽 `OgLAsyncSkeleton` 到公共层（`itemCount`+`itemBuilder`），`AsyncView` 增 `skeleton` 参数，loading 改二段式（先骨架，>300ms 再转圈）；骨架块色 `surfaceContainerHighest`、圆角 `OgLRadius`、行高对齐 56/72dp 零位移；`AsyncController` 加 `Timer` 延迟 300ms 置 `_showSpinner` + 完成最小显示 300ms；`search_page.dart:1364` 与 `controller==null` 分支复用同一骨架；`repo_page.dart` 四处裸转圈改行内 16dp/strokeWidth:2。
- 影响 / Scope：21 个有异步页 / 21 async pages。工作量 / Effort：**L**。

**D-07【严重】列表行 meta 信息缺失：issue/PR 无状态与规模，通知一屏 8 条且带 3 行技术噪声**
- 跨席 / Sources：1-C S-04/S-05；1-A S6。
- 根因 / Root：`repo_page.dart:2782-2800`（issue meta 仅作者·评论数·日期）、`:2914-2928`（PR meta 仅作者·日期）；`notifications_page.dart:326-332`（`maxLines: 3`）、`:314-318`（上下各 12）。
- 修复 / Fix：`repo_page.dart:2782-2800` issue meta 追加状态/labels/相对更新时间，`:2914-2928` PR 追加 draft/merge 状态与更新时间；`notifications_page.dart:326-332` maxLines 3→2。
- 影响 / Scope：仓库 issue/PR 列表 + 通知中心 / repo issue/PR lists plus notifications。工作量 / Effort：**S**。

**D-08【中】8dp 体系逃逸：4 处字面量间距；下载/工作流/运行页卡片内边距四值不一**
- 跨席 / Sources：1-A M1/M4/L2/L3/L6。
- 根因 / Root：`download_manager_page.dart:466`（spacing:4）、`:362-366`（fromLTRB 12/12/8/8）、`repo_page.dart:4465`（spacing:8）、`action_run_page.dart:616`（spacing:8）、`release_detail_page.dart:428`（SizedBox width:72）、`workflow_dispatch_page.dart:437/441`、`action_run_page.dart:579`、`repo_tags_page.dart:195/216`。
- 修复 / Fix：字面量改 `OgLSpace.xxs/sm`；`download_manager_page.dart:362-366` 统一 `all(md)`、`:455` 删 `only(top:xxs)`；卡内 `all(lg)`→`all(md)`、ListTile `dense:true`；72dp 常量提 `og_l_space.dart`（与 5-B A-M6 大字体修复合并）；`repo_tags_page.dart:216` 改 `fromLTRB(lg,0,lg,lg)`。
- 影响 / Scope：5 页 / five pages。工作量 / Effort：**S**。

**D-09【中】搜索页两套 gutter（16 vs 12）、结果 subtitle 限死 2 行；通知行左右 16/8 不对称**
- 跨席 / Sources：1-A M2/M3；1-C M-07/M-13。
- 根因 / Root：`search_page.dart:94-97`（16）、`:1042-1043`（无水平 padding）、`:1066-1068`（16）、`:878-882`（12）、`:905`（all xxs）、`:1236-1238`+`:1386-1391`（subtitle maxLines 2）；`notifications_page.dart:316-318`（fromLTRB 16/12/8/12）。
- 修复 / Fix：`search_page.dart:1042-1043` 改 `fromLTRB(lg, sm, lg, sm)`、`:878-882` md→lg、`:905` xxs→sm、`:1236-1238` 拆分 meta/描述、`:1386-1391` 代码命中片段允许 3 行；`notifications_page.dart:316-318` 改 `symmetric(horizontal: lg, vertical: sm)`、`:324` md→sm。
- 影响 / Scope：搜索页 + 通知页 / search plus notifications。工作量 / Effort：**S**。

**D-10【中】Issue 评论用整块 Card 且卡片间无节奏（一屏 5 条）；`OgLFlatTile` 行内边距与全局 ListTile 主题不一致**
- 跨席 / Sources：1-C M-11/M-06/M-15；1-A L1。
- 根因 / Root：`issue_page.dart:806-830`（每评论一个 Card + `surfaceContainerHighest` 头块）、`:796-800`（仅 SizedBox(sm)）；`flat_list.dart:17`（`kOgLFlatRowPadding = kOgLSettingsRowPadding`）；`settings_group.dart:29-31`（`vertical: md(12)`）vs `theme.dart:333-334`（`vertical: xxs(4)`）；`repo_page.dart:806-815`（separator 无首尾留白）。
- 修复 / Fix：`issue_page.dart:806-830` 评论 Card 改「头部色带 + 1px 分隔线」平铺行（与 `flat_list.dart` 同源，一屏回 8–10 条）；`settings_group.dart:29-31` vertical md→xxs（与主题一致）；`repo_page.dart:806-815` 加 `padding: EdgeInsets.only(bottom: lg)` + 起手 4dp。
- 影响 / Scope：issue 评论 + 设置/关于/用户平铺 / issue comments plus flat lists。工作量 / Effort：**M**。

**D-11【中】README 区一屏读不到完整章节**
- 跨席 / Sources：1-C M-12。
- 根因 / Root：`readme_view.dart:385`（`height:1.5`）、`:404`（`blockSpacing:12`）、`:391-393`（h1/h2 用 headlineSmall/titleLarge）。
- 修复 / Fix：`:385` 1.5→1.35、`:404` 12→8、h1/h2 降一档为 titleLarge/titleMedium。
- 影响 / Scope：README 展示（仓库/内容域共享组件） / README renderer。工作量 / Effort：**S**。

**D-12【中】设置页入口过疏（一屏 7 项）、尾部分隔线 28dp 死区；设置子页/网络页尾部 24dp 死区**
- 跨席 / Sources：1-A M5/M6/M7；1-C M-06。
- 根因 / Root：`settings_page.dart:425-426/513-514/470/1825`；`settings_group.dart:30-32`（vertical md）；`settings_section_page.dart:33-37`（底部 xl）；`network_page.dart:49/52`（尾部 SizedBox xl）。
- 修复 / Fix：`settings_page.dart:513` ListTile `dense:true`、`settings_group.dart:30-32` vertical md→sm、`settings_page.dart:470/1825` Divider height 28→lg；`settings_section_page.dart:33-37` 底部 xl→lg + 补 viewPadding.bottom；`network_page.dart:52` 删尾部 SizedBox 改 `fromLTRB(lg,lg,lg,0)` + padding.bottom。
- 影响 / Scope：设置系 + 网络页 / settings family plus network。工作量 / Effort：**S**。

**D-13【中】弹层菜单行/分支条行高过大；推荐网格固定列数阶梯；评论输入沉在超长列表底部**
- 跨席 / Sources：1-C L-16/L-17/M-10；5-A F-6；1-A §跨页网格。
- 根因 / Root：`issue_page.dart:395-404/631-651`（菜单行 56dp 无 subtitle）、`:877-897`（评论输入为 SliverToBoxAdapter 尾项）；`repo_page.dart:636-650`（分支条 contentPadding vertical md=12→80dp）、`:724-748`（分支弹层 3 meta 挤单行省略）；`search_page.dart:870-873`（`constraints.maxWidth >= compact ? 2 : 1` 阶梯）。
- 修复 / Fix：菜单行 `dense:true` 或自绘 44dp；`repo_page.dart:646-647` vertical md→sm，`:724-748` SHA 与标签拆两行；推荐网格改 `LayoutBuilder` + `auto-fill/minmax`；评论输入提为 `Scaffold.bottomNavigationBar` 固定栏（或 AppBar 加「跳到评论」）。
- 影响 / Scope：issue / repo / search / discover 网格 / issue comments。工作量 / Effort：**M**。

**D-14【轻】空态文案无「首次使用」引导；游客/筛选态文案混用；无 Semantics 复述 meta**
- 跨席 / Sources：1-C L-21/L-22；3-B S-16/S-17/S-24；5-A F-2。
- 根因 / Root：`search_page.dart:1367-1369`（noResults 无 action）、`:776-777/:1027-1028`；`notifications_page.dart:219-226`（筛选文案混用）；`action_log_page.dart:369-376`；`gist_detail_page.dart:366-367`、`profile_page.dart:231-232`、`workflow_dispatch_page.dart:423-424`（通用词）；`dashboard_page.dart:493-513`/`gists_page.dart:162-181`（无 Semantics）。
- 修复 / Fix：D-05 已含 CTA；文案改「还没有 X —— <说明>」+ CTA，筛选态给差异化文案（emptyWarning/emptyError）入 i18n zh/en；游客态 search 空态区分「游客模式不显示个人动态，去登录」+ 登录 action；三处行外包 `Semantics(label:'$title，$meta')`（与 `discover_rows.dart:81-88` 同构）。
- 影响 / Scope：多页空态文案与语义 / multi-page empty copy and semantics。工作量 / Effort：**M**。

### 3.4 反馈类 / Feedback（点了没反应 / no response to action）

**F-01【严重】`issue_page` 七类写操作点击后按钮全程无 busy 态、异步无任何 progress**
- 跨席 / Sources：4-A S-01；3-B S-21。
- 根因 / Root：`issue_page.dart:174`（`_runWrite`：`setState(_busy=true)` 后仅 `await action()`，无 spinner/progress）；调用点 `:232/284/320/361/450/486/530`；对话框 `:244` 保存后立即 `Navigator.pop(true)`。
- 修复 / Fix：`_EditIssueDialog`/`_LabelsDialog`/`_AssigneesDialog`/`_EditCommentDialog` 内用 `ValueListenableBuilder<bool>` 或把 `busyOf` 提升为 `Listenable`；点保存后对话框不立即 pop，原地显示按钮内 `CircularProgressIndicator(strokeWidth:2)` + `onPressed=null`（对齐 `code_editor_page.dart:601`），成功后再 pop；或乐观 UI（本地先改 + 后台同步 + 失败回滚 toast 重试）。
- 影响 / Scope：议题编辑/标签/指派/锁定/编评/删评/关开七类 / seven issue write types。工作量 / Effort：**M**。

**F-02【严重】`repo_page` 关闭议题与多个设置写操作缺 `_busy` 防重入，开关用「空回调」代替禁用**
- 跨席 / Sources：4-A S-02/S-03；3-A M9。
- 根因 / Root：`repo_page.dart:2697`（`_close`）、`:4039`（`_setDefaultBranch`）、`:4062`（`_toggleArchive`）、`:4210`（`_deleteRepo`）、`:3973`（`_transferRepo`）无 `if (_busy) return`；`:4352`（可见性开关 `onChanged: _busy ? (bool v){} : ...`）；`:2715` await 段无反馈。
- 修复 / Fix：五个 handler 开头统一 `if (_busy) return; setState(_busy=true)` + `finally` 复位；`:4352` 改 `onChanged: _busy ? null : ...`（进入 disabled 视觉）；`setDefaultBranch` 下拉 busy 时 `enabled:false`；`_close` 成功后 `OgLNotifier.success(_t('issueClosed'))`，触发行 busy 时内联 spinner。
- 影响 / Scope：仓库页设置/危险写 / repo settings and destructive writes。工作量 / Effort：**M**。

**F-03【严重】全局 `OgLNotifier` 的 SnackBar 无 action、无显式 duration，所有失败提示看完即消失、不可重试**
- 跨席 / Sources：4-A S-04；4-C C-02/C-04/C-05；3-B F-8。
- 根因 / Root：`notifier.dart:73-88`（`_show` 构造只有 `content`/`behavior`/`margin`/`backgroundColor`，无 `action`、无 `duration`）；`:52/55/58`（success/info/warning 三种语气样式几乎无差别，warning 仅红底）；`error_surface.dart:572-580`（`_presentAmbient` 直调 `showSnackBar` 且无 severity 视觉）；`download_manager_page.dart:80-116`（自建三色 SnackBar + 8s + action + `hideCurrentSnackBar`）。
- 修复 / Fix：`notifier.dart:60` 扩签名 `warning(message, {VoidCallback? onRetry, Duration? duration})`、`success(message, {VoidCallback? onUndo})`，`_show` 构造 `SnackBarAction(label, onPressed)`、duration 显式 6–8s；success 用 `scheme.primary` 容器色 + check 图标、warning 加 error 图标，语气映射只留一处；`error_surface.dart:572` 按 `notice.severity` 映射；`download_manager_page.dart` 通知收编到统一出口（带 `duration`/`replace` 参），默认 8s 仅限带 action 提示。
- 影响 / Scope：全库 SnackBar 出口 / all SnackBar exits。工作量 / Effort：**M**。

**F-04【严重】新建/Gist/发布提交按钮仅换文字、无 spinner，异步期进度为零且宽度跳变**
- 跨席 / Sources：4-A S-05；3-C C3-C-16；3-B S-21。
- 根因 / Root：`new_issue_page.dart:176-181`、`new_gist_page.dart:148-149`、`new_release_page.dart:240-241`（`_busy ? Text(submitting) : Text(submit)`，无 spinner）；`login_page.dart:409-425`（busy 时 Row 含 spinner 使按钮变宽）。
- 修复 / Fix：新建 `OgLBusyButton`（FilledButton 变体，busy 时按钮内 `CircularProgressIndicator(strokeWidth:2)`、`onPressed=null`、宽度锁定）；替换三处提交按钮 + `issue_page` dialog 保存键 + `gist_detail_page.dart:357/480`；登录按钮用 `SizedBox(width:200)` 锁宽或 Spinner+label 用 `Stack` 叠加（`AnimatedSize` 包裹避免跳变）。
- 影响 / Scope：四个新建页 + 登录 + dialog / four create pages plus login and dialogs。工作量 / Effort：**M**。

**F-05【严重】`repo_page` 单文件写使整页被全屏转圈替换，丢失上下文；状态行机制未复用**
- 跨席 / Sources：4-A S-06；3-B S-14。
- 根因 / Root：`repo_page.dart:2447-2450`（`if (_busy && _operationStatus.isEmpty) return Center(CircularProgressIndicator())`）；`_createFile:1544`、`_deleteEntry:1620` 设 `_busy` 但不设 `_operationStatus`；对照批量删除 `:1727` 有状态行。
- 修复 / Fix：单文件写也走进度状态行：`_createFile`/`_deleteEntry` 设 `_busy` 同时设 `_operationStatus = _t('opCommitting')`；移除或提高 `:2449` 全屏转圈触发门槛（仅保留真正无上下文的首帧加载）；`_pagedBody` 整体复用 `AsyncView`/`OgLAsyncSliver` 语义（与 D-06 合并）。
- 影响 / Scope：仓库文件树写操作 / repo file-tree writes。工作量 / Effort：**M**。

**F-06【严重】危险操作确认框两种写法并存：一半 error 底、一半普通 primary；确认层级未分级**
- 跨席 / Sources：3-A S1/M4/M5；4-C C-01/C-06/C-09/C-11/C-12/C-16。
- 根因 / Root：正确 error 底 5 处（`drafts_page.dart:102-107`、`release_detail_page.dart:199-204`、`gist_detail_page.dart:256-261`、`repo_page.dart:4518-4523/4221-4226`）；普通 primary 4 处（`issue_page.dart:476-480` 删评论、`repo_tags_page.dart:144-148` 删 Tag、`profile_page.dart:151-155` 移除账号、`notifications_page.dart:153-157` 清空日志）；另有 `ogLConfirmDiscardChanges`（`overlays.dart:88-111`，7 页复用）确认钮非 danger；`drafts_page.dart:189-195` 删除按钮最高权重；全库 16+ 份手写确认框。
- 修复 / Fix：在 `overlays.dart` 新建 `ogLConfirm(context, {title, body, confirmText, danger:false})` 与 `ogLDangerConfirm`（统一「TextButton 取消 + error 底 FilledButton 确认」）；替换 S1 的 4 处 + M4/M5 + `ogLConfirmDiscardChanges`；`drafts_page.dart:189-195` 删除降 TextButton(error 前景)；fork 等可逆操作用 `FilledButton.tonal`；Sheet 内删除项（`issue_page.dart:400-403`、`repo_page.dart:1977` 起）加 error 图标与前景色。
- 影响 / Scope：全库确认框 / all confirmation dialogs。工作量 / Effort：**M**。

**F-07【严重】按钮变体与权重分裂：新建主操作三级分裂、重试三型、取消三型**
- 跨席 / Sources：3-A S2/S3/M7/M8/M12；4-C C-16；5-C C-S5/C-S7。
- 根因 / Root：`new_gist_page.dart:147`/`workflow_dispatch_page.dart:415`（AppBar TextButton 作主操作）vs `new_issue_page.dart:176`（FilledButton）；重试 `repo_tags_page.dart:201`（FilledButton）vs `search_page.dart:805`（tonal）vs `repo_page.dart:819`（OutlinedButton）；`action_run_page.dart:636`（取消 Outlined）vs 重跑 tonal；`pull_page.dart:109`（详情页无 actions）。
- 修复 / Fix：主操作统一下沉表单底 FilledButton 或 AppBar `FilledButton.tonalIcon`（参照 `code_editor_page.dart:595`）；失败重试统一 `FilledButton.tonal`（`OgLAsyncErrorPane` 默认）；取消按钮加 error 语义；`pull_page.dart:109` 补「开放浏览器 + 复制链接」操作；同页筛选控件按 5-C C-S5 规则统一（≤3 档 Segmented、>3 档 FilterChip，`notifications_page.dart:196` 4 档改 FilterChip，`search_page.dart:1330` 与 `:1011` 统一为 `OgLIssuesFilterChips`）。
- 影响 / Scope：多页控件变体 / multi-page control variants。工作量 / Effort：**M**。

**F-08【严重】表单错误呈现只有 1 处在字段旁：SnackBar 一次性提示 + 离场 errorCard，错误无处可查**
- 跨席 / Sources：3-C C3-C-01/C3-C-08/C3-C-09/C3-C-14；3-B S-12。
- 根因 / Root：全库 `errorText:` 仅 `repo_page.dart:1471` 一处；`new_issue_page.dart:160-171`/`new_repo_page.dart:173-186`/`new_release_page.dart:213-227`/`login_page.dart:430-448`（错误 Card 在字段下方若干屏外）；`new_gist_page.dart:89/93/117-120`、`workflow_dispatch_page.dart:325-341`、`issue_page.dart:552/562`、`settings_page.dart:1947`（SnackBar）；`login_page.dart:521-531`（OAuth 错误裸 Text 一套、PAT 错误 Card 另一套）。
- 修复 / Fix：TextField→TextFormField + `GlobalKey<FormState>`，校验失败 `setState(_xError=...)` 传 `decoration.errorText`（参照本库标杆 `repo_page.dart:1463-1474`）；服务端 422 类错误映射回字段；`new_gist_page.dart` 增 `_error` 改内联 errorContainer（`new_issue_page.dart:160-172` 同款）；`issue_page.dart:880` 评论框加 errorText + 字数计数器；抽 `OgLErrorCard(message, {detail})` 统一登录两种错误，原始异常收进默认收起的 ExpansionTile 详情；错误文案补三要素（原因+定位+下一步）。
- 影响 / Scope：全部表单页 / all form pages。工作量 / Effort：**L**。

**F-09【严重】必填字段零标记；校验时机错（提交后首次出现、纠错后不即时消失）**
- 跨席 / Sources：3-C C3-C-02/C3-C-03；4-A M-08。
- 根因 / Root：`new_issue_page.dart:142/146/155`、`new_repo_page.dart:146/150/160`、`repo_tags_page.dart:297/302`、`issue_page.dart:932`、`repo_page.dart:3177` 必填无标记（全库唯一正确是 `workflow_dispatch_page.dart:562` 的（必选）/（可选）后缀）；`new_issue_page.dart:88-93` 等五页提交时才校验且 `_error` 只在下次 `_submit` 开头清空。
- 修复 / Fix：抽 `OgLRequiredLabel` helper（label 后附 `*` + Semantics「必填」），或统一 zh 文案后缀；必填字段加 `onChanged` 即时重校验清除（`if (_titleError != null && _title.text.trim().isNotEmpty) setState(() => _titleError = null)`，参照 `repo_page.dart:1466`），失焦时首次校验；错误 Card 内加「重试」TextButton 且不清空已填字段；`repo_page.dart:3027` 成功用 `warning` 语气改 `success`。
- 影响 / Scope：新建/编辑表单 / create/edit forms。工作量 / Effort：**M**。

**F-10【严重】提交防重缺口：`new_gist`/`workflow_dispatch` AppBar 主操作连按可重复提交**
- 跨席 / Sources：3-C C3-C-04；4-A S-03。
- 根因 / Root：`new_gist_page.dart:86/146-152`（`_submit` 内无 `if (_busy) return`，AppBar TextButton 无 handler 级闸）；`workflow_dispatch_page.dart:320/336/406-410`（`_busy` 检查在校验之后）。
- 修复 / Fix：`_submit()` 第一行统一 `if (_busy) return;`（workflow 会触发 CI 重跑，代价真实）；有 UI 闸的页保持不变。
- 影响 / Scope：两页 / two pages。工作量 / Effort：**S**。

**F-11【严重】「加载失败」被渲染成「你还没有内容」——错误态伪装成空态，主动误导**
- 跨席 / Sources：3-B S-02/S-05/S-09/S-10/S-11/S-18/S-19；3-C C3-C-14。
- 根因 / Root：`legal_text_page.dart:72-80`（catch 置 `body=''`→`_body!.isEmpty` 走「法律文本为空」）、`onboarding_page.dart:99-108`（权限拉取失败置 `_infos=[]`）；原始异常外泄 4 处：`paged_controller.dart:221`、`dashboard_page.dart:600`、`file_preview_page.dart:191`、`login_page.dart:158/207`、`search_page.dart:504`；`repo_tags_page.dart:191-208`（手写错误态）；`workflow_dispatch_page.dart:530-537`（错误一行小字无重试）。
- 修复 / Fix：把 `async.dart:215-245` 的 `_describe` 抽顶层 `ogLDescribeError(Object)`，替换全部原始异常赋值；`legal_text_page.dart`/`onboarding_page.dart` 增 `_error` 字段，失败走 `OgLAsyncErrorPane(onRetry: ...)`；`repo_tags_page.dart:190-219` 整页迁移 `AsyncController`/`AsyncView`；`workflow_dispatch_page.dart:530-537` 改 `OgLAsyncErrorPane` 带重试。
- 影响 / Scope：6 页错误态 / six pages' error states。工作量 / Effort：**M**。

**F-12【严重】转场方向不编码前进/返回，旧页无退场：push 与 pop 同为纵向下沉**
- 跨席 / Sources：4-B B-01/B-02/B-15；2-C C-12/C-01。
- 根因 / Root：`motion.dart:423-469`（`buildTransitions` 收了 `secondaryAnimation` 但正文零次使用）、`:457`（`Tween<Offset>(begin: Offset(0, offset), end: Offset.zero)` 仅 Y 轴）、`:449-250`（整页缩放 0.975 + 46dp 纵移）、`:348-352`（全平台共用同一 builder）。
- 修复 / Fix：`motion.dart:423-469` 增加 secondary 分支，用 `secondaryAnimation` 给旧页叠反向 `SlideTransition`+`FadeTransition`（出屏用 `OgLOAnimQuality.of(level).fast` + `Curves.easeIn`）；`:457` 改 shared-axis X（`Offset(offset,0)` 按 push/pop 取 ±），弹层保留「上=展开/下=关闭」；`:249/224` `transitionScaleFrom`→1、`:249/196` `transitionOffset` 0.05→0.03/0.02，删除 `ScaleTransition` 分支；`:348-352` 按平台分发（Android/iOS shared-axis，桌面 fade + 极短位移）。`tool/motion_audit.py` 增门禁限制 `ScaleTransition` 不得作用于整页。
- 影响 / Scope：全库页级转场 / all page transitions。工作量 / Effort：**L**。

**F-13【严重】Android 预测性返回手势被全局 `PopScope(canPop:false)` 吞掉；壳层 `navigator.pop()` 绕过表单 dirty 确认**
- 跨席 / Sources：4-B B-03/B-04/B-05/B-18；5-A §返回链。
- 根因 / Root：`client_shell.dart:246-253`（根 `PopScope(canPop:false)`）、`:167-170`（`navigator.pop()` 直调）、`:151/159-162/209`（`_backHandling` 闸门静默 return）、`:203-205`（goHome 固定回首页）；`token_exit_warning.dart:127`、`error_surface.dart:537`、`settings_page.dart:1732`（均 canPop:false）；`rg predictive` 无命中，仓库无 `android/` 目录。
- 修复 / Fix：平台层（若有 manifest）设 `android:enableOnBackInvokedCallback="true"`；根 `canPop:false` 改条件式（仅非首页/弹窗打开/待退出时拦截，余交 Navigator 自身 pop）；`:167-170` 改 `maybePop()` 让目标路由 PopScope 决定；`:159-162` 命中闸门时给 info 提示或 100ms shake 而非静默；`:203-205` 维护 tab 访问栈，goHome 返回上一个 tab + fade 收敛；必须拦截处给视觉回弹说明。
- 影响 / Scope：全库返回链 / all back navigation。工作量 / Effort：**L**。

**F-14【中】页级路由时长恒 300ms（档位 1 有 174ms 死等），主题切换恒 160ms，档位 0「静默」在主题/对话框/系统返回处失效**
- 跨席 / Sources：2-C C-02/C-03/C-04/C-15/C-16；4-B B-11/B-16。
- 根因 / Root：`rg transitionDuration` 全库 0 命中（框架默认 300ms）；`motion.dart:205/231/257`（`transitionWindow` 只压运动段）；`og_l_app.dart:96`（`themeAnimationDuration: OgLAnim.slow(context)`，context 在 `MaterialApp` 之上取不到 OgLMotionScope→恒档位 1）；`motion.dart:330`（`pageTransitions` 不读 `MediaQuery.disableAnimations`）；`overlays.dart:74-82`（`ogLShowDialog` 无时长/曲线）；`motion.dart:41/97/158/174/251`（`blurSigma` 死参数，`rg ImageFiltered` 0 命中）。
- 修复 / Fix：所有 `MaterialPageRoute` 补 `transitionDuration: OgLAnim.medium(context)` / `reverseTransitionDuration: OgLAnim.fast(context)`（目标进 120–230ms / 退 90–170ms）；`og_l_app.dart:96-97` 改直接读 `current.motionLevel` 经 `OgLOAnimQuality.of(ml)`；`motion.dart:330` 加 `systemReduce` 参数，`surface_bridge.dart:565` 传 `MediaQuery.disableAnimationsOf`；`overlays.dart:74-82` 自建 `DialogRoute`/`PageRouteBuilder` 接档位；删 `blurSigma` 字段及 getter 或注明未启用。
- 影响 / Scope：全库路由与弹层时长 / all routes and overlays。工作量 / Effort：**M**。

**F-15【中】档位表数值越界：错峰末项 ~806ms、fast 170ms 超 150、settle 10% 过冲、淡入先于位移结束**
- 跨席 / Sources：2-C C-06/C-07/C-08/C-10/C-11/C-20；2-C 0 量化表。
- 根因 / Root：`motion.dart:244-245`（staggerStep 36 / staggerMaxIndex 16）、`:241`（fast 170）、`:254`（settleCurve easeOutBack）、`:253/227`（largeCurve easeOutQuint/Quart）、`:420`（fade window `_windowEnd*0.8`）、`:246-248`（revealAll + revealOffset 0.04 + revealScaleFrom 0.985）。
- 修复 / Fix：`motion.dart:245` staggerMaxIndex→6、`:244` staggerStep→24（合计 ≤374ms）；`:241` fast→150；`:254` settleCurve→easeOutCubic 或过冲 ≈3% 的自定义 Cubic；`:253/227` largeCurve→`Cubic(0.05,0.7,0.1,1)`（M3 emphasized decelerate）；`:420` 改 `Interval(0,_windowEnd,easeOut)`；`:247/248` revealOffset→0、revealScaleFrom→1（层级入场交给容器淡入 170ms）。
- 影响 / Scope：动效档位表全局 / motion quality table。工作量 / Effort：**S**。

**F-16【中】切 tab 只有新页入场无旧页退场，平级切换套层级横滑隐喻；跨多格幅度不变**
- 跨席 / Sources：4-B B-06/B-07；2-C C-18（可中断切换）。
- 根因 / Root：`client_shell.dart:472-480`（只更新 `_from` 跑弹簧）、`:504-507`（`FractionalTranslation` 只作用于 IndexedStack 整体）、`:477`（`_from` 按 index 大小定方向，不看跨格数）、`:470-475`（`if (_controller.isAnimating) return` 吞掉连点）。
- 修复 / Fix：`_OgLShellSlide` 改 `AnimatedSwitcher` + 成对 `SlideTransition` 让两页对向接力；`:477` 改平级 fade + 微移（位移取 `shellOffset` 固定小值，幅度不随跨格放大），indicator pill 承担 200ms 选中滑动；`:470-475` 改可中断（以当前 `_controller.value`/`velocity` 为初值继续跑，`_from` 更新为新方向）。
- 影响 / Scope：外壳 tab 切换 / shell tab switching。工作量 / Effort：**M**。

**F-17【中】弹层出口不一致：出场与入场等长、sheet 走 linear 曲线、多个调用点绕过统一入口、高度策略 0.6/0.8/无限高并存**
- 跨席 / Sources：4-B B-09/B-10/B-11/B-12；2-C C-14/C-15；4-C C-03/C-07/C-15。
- 根因 / Root：`overlays.dart:66-70`（`AnimationStyle(duration:duration, reverseDuration:duration)` 无曲线，沿用框架 linear）；`search_page.dart:937`（直调 `showModalBottomSheet` 无 drag handle）；`settings_page.dart:760/831`、`font_pick.dart:28`、`code_editor_page.dart:427`（4 处直调 `showDialog`）；`onboarding_page.dart:193/202-204`（前进后退同长）；`code_editor_page.dart:373`（0.8）、`repo_page.dart:701`（0.6）无限高常量。
- 修复 / Fix：`overlays.dart:66-70` 加 `curve: OgLAnim.curve(context)`、`reverseCurve: Curves.easeIn`、`reverseDuration: duration*0.7`，sheetDuration 调 200/250/300；4 处 `showDialog` + `search_page.dart:937` 收口统一入口（档位 0 零时长）；`onboarding_page.dart:202-204` previousPage 用 `OgLAnim.fast`；overlays 增 `OgLSheetHeight.compact/full`（0.6/0.85）常量，调用点改用常量。
- 影响 / Scope：全库弹层与引导翻页 / all overlays and onboarding paging。工作量 / Effort：**M**。

**F-18【中】成功确认缺失：关闭议题/取消运行/下载日志/退出登录/清空通知均无成功 SnackBar**
- 跨席 / Sources：4-A S-02/S-07/L-18/M-10/M-11/L-15。
- 根因 / Root：`repo_page.dart:2697`（_close 仅日志 + 静默 refresh）、`action_run_page.dart:186`（_cancel 仅 `OgLAppLog.result`）、`:280`（_downloadLogs 成功无提示）、`profile_page.dart:136/158`（_remove 仅日志）、`notifications_page.dart:180-182/140-162`（markAllRead/清空无提示）、`repo_page.dart:2682-2694`（_create info 语气）。
- 修复 / Fix：上述六处成功后发对应语气 SnackBar（取消在 refresh 前发避免等待期无反馈），失败补 onRetry；创建/保存成功的 `info` 统一 `success`；`profile_page.dart` 加 `_removing` 守卫 + spinner（M-10）。
- 影响 / Scope：6 页写操作 / six pages' writes。工作量 / Effort：**M**。

**F-19【中】写操作缺 busy/progress 的其余页：new_* 创建、gist_detail 编辑删除、profile 退出、settings 写**
- 跨席 / Sources：4-A M-09/M-10/M-12/M-13；3-B S-21。
- 根因 / Root：`gist_detail_page.dart:357-360/480`（按钮变灰无 spinner）、`profile_page.dart:136/333-339`（_remove 无 busy）、`settings_page.dart:254/807/305/281`（setCodeColor/removeCustomFont/setLanguage/reset 无守卫）、`action_run_page.dart:621-640`（三按钮同时置灰无原因）。
- 修复 / Fix：gist_detail 两处 IconButton 的 icon 用 `_busy ? CircularProgressIndicator(strokeWidth:2) : Icon(...)`；profile 加 `_removing` 字段 + 按钮 spinner + 成功 info；settings 对 I/O setter（setUiFont/setCodeColor）加页面级 `_busy` 守卫 + controller.apply 串行化；action_run 三按钮下方保留一行 `_operationStatus`。
- 影响 / Scope：4 页 / four pages。工作量 / Effort：**M**。

**F-20【中】`code_editor` 乐观保存即时确认弱：结果离开页面后经通知中心才可见**
- 跨席 / Sources：4-A M-14。
- 根因 / Root：`code_editor_page.dart:253-273`（`_save`：`_notifier.info(queuedInBackground)` 后立即 pop）、`:277`（`_submitInBackground` 经 Notifier 异步报出）。
- 修复 / Fix：保留乐观入队，但后台结果写 `OgLNoticeCenter` 持久通知条目（非易逝 SnackBar），编辑器入口显示「N 项待同步」角标，失败提供「重试/查看冲突」直达入口。
- 影响 / Scope：代码编辑器保存链 / code editor save flow。工作量 / Effort：**M**。

**F-21【中】深链处理全库缺失；登录/切号后首页整页重建丢滚动与数据；repo 多 ScrollController 无位置恢复**
- 跨席 / Sources：5-A F-1/F-5/F-9。
- 根因 / Root：`rg pushNamed|initialLink|goRouter` 全 lib 0 命中；`client_shell.dart:211-214`（`DashboardPage(key: ValueKey('dash-${_accountId}'))` 登录触发新 key→整页重建）；`repo_page.dart:941/2654/2999/3153`（4 个 ScrollController 无 PageStorageKey，`rg PageStorage` 0 命中）。
- 修复 / Fix：注册 `https://github.com/<owner>/<repo>(/(issues|pull)/\d+)?` app link，冷启动 initialLink 解析后 push 对应页；Dashboard key 改不含账号 + 内部监听 auth 自行刷新（或保留 offset）；repo 四个 ScrollController 挂 `PageStorageKey` + dispose 前写 offset、initState 恢复。
- 影响 / Scope：启动/登录/仓库导航 / launch, login, repo navigation。工作量 / Effort：**L**。

**F-22【中】焦点/读屏断点：三处自定义行无 button 语义、三处图片无 semanticLabel、issue 颜色点表达状态、异步 phase 无 live region、令牌框无 autofillHints**
- 跨席 / Sources：5-B A-S4/S5/S6/A-M2/M4/M5/M8/M9/A-L1。
- 根因 / Root：`search_page.dart:214/257/1060`（InkWell 无 Semantics）、`:1053-1104`（颜色点表 open/closed，meta 无状态词）；`readme_view.dart:563`/`file_preview_page.dart:483`/`repo_page.dart:2370`（Image.network 无 semanticLabel，`rg semanticLabel` 0）；`login_page.dart:430-440`（_phase/_error plain Text）、`:375-395`（无 autofillHints，`rg autofillHints` 0）；`og_l_app.dart:127`（OgLNoticeHost 无 live region）；`log_search.dart:79/85`（tooltip 为 '↑'/'↓'）；`search_page.dart:718`/`repo_page.dart:616`（无 tabBarTheme/semanticLabel）；`code_editor_field.dart:876-885`（查找选项 InkWell 无 button/selected 语义）；`settings_page.dart:577/588`、`issue_page.dart:818`（CircleAvatar 无语义）。
- 修复 / Fix：三处 InkWell 包 `Semantics(button:true, label:'<title>，<meta>', excludeSemantics:true)`，README 折叠行加 `expanded`；三处 Image.network 加 `semanticLabel` + i18n「图片：{alt}」；issue 状态词进 meta（`stateOpen`/`stateClosed`）+ 圆点语义化；`og_l_app.dart:127` 加常驻 `Semantics(liveRegion:true)` 由 notifier 统一写入，登录 phase/error 同步；`login_page.dart:376` 加 `autofillHints:[password]` + `enableSuggestions:false` + `AutofillGroup`；log_search tooltip 换 i18n 动作名；theme 加 tabBarTheme + 两处 TabBar `semanticLabel`；code_editor_field 查找选项包 `Semantics(button:true, selected:checked, label)`；头像加/排除语义。
- 影响 / Scope：全库可访问性 / app-wide accessibility。工作量 / Effort：**L**。

**F-23【中】无 a11y 测试与主题回归护城河；`brightness ==`/`Colors.white|black` 页面层 0 处（正面）但无 CI 保护**
- 跨席 / Sources：5-B A-L4；5-C C-L6。
- 根因 / Root：`rg -n "a11y|semantic|tooltip|48|contrast" test -g '*.dart'` 无匹配；页面/widgets 明暗走 `theme.dart:152 buildOgLTheme(brightness)` 统一生成（正面），仅 `theme.dart:263/268` 与 `boot_splash.dart:32` 分支。
- 修复 / Fix：新增 `test/surface/a11y_test.dart`（遍历 30 页 pump 断言 IconButton tooltip 非空非单字符、可点击 Semantics 节点有 label、把对比度表写成 golden 断言）；CI grep `brightness ==|Colors\.(white|black)` 于 `pages/`+`widgets/` 应为空；CI grep `Icons.copy|Icons.language|Icons.link` 于复制/打开语境应为空（配合 G-11）。
- 影响 / Scope：CI 与测试 / CI and tests。工作量 / Effort：**M**。

**F-24【轻】换档后已在导航栈中的页面返回仍用旧转场；档位 0 系统返回动画不受控**
- 跨席 / Sources：4-B B-17/B-16。
- 根因 / Root：`motion.dart:331-356`（_transitionCache 按 level 缓存 PageTransitionsTheme，route push 时确定 builder）；`og_l_app.dart:118-140`（disableAnimations 注入 MediaQuery 但不覆盖 platform 侧 route pop）。
- 修复 / Fix：文档明确「档位改变仅对后续导航生效」；或让 `buildTransitions` 内每次从 `OgLAnim.quality(context)` 读档位（牺牲缓存需评估）；档位 0 系统返回侧若无法控制则文档声明并在根 `PopScope` 分支用瞬时 `Navigator.pop` 跳过过渡。
- 影响 / Scope：档位切换边界 / motion-level change boundary。工作量 / Effort：**S**。

**F-25【轻】SnackBar 遮挡 FAB 未验证；Sheet 内 SafeArea 不一致；clipboard 文档教直调 showSnackBar**
- 跨席 / Sources：4-C C-08/C-14/C-13。
- 根因 / Root：`repo_page.dart`（5 个 FAB）+ `notifier.dart:88-89`（margin horizontal 16 覆盖 Scaffold inset）；`issue_page.dart:378`（SafeArea top:false ✅）vs `search_page.dart:938`（全包 SafeArea 双重避让）；`clipboard_x.dart:20-23`（dartdoc 示例直调 showSnackBar）。
- 修复 / Fix：FAB 页实机验证 SnackBar 堆叠，若重叠改 margin 保留 FAB 让位或用 ScaffoldMessenger 默认；search 走 ogLShowSheet 后删手写 SafeArea，repo 两处矮面板补 `SafeArea(top:false)`；clipboard_x.dart 文档示例改 `OgLNotifier.of(context).warning(...)`。
- 影响 / Scope：SnackBar/Sheet 视觉细节 / snackbar and sheet details。工作量 / Effort：**S**。

**F-26【轻】`repo_page` 一致性细节：复制图标图文冲突、手动分页注释漂移、状态 `sync` 与动作 `refresh` 近似**
- 跨席 / Sources：5-C C-S2/C-S6/C-M8（已并入 G-11/G-12，本条记剩余细节）。
- 根因 / Root：`repo_page.dart:592`（复制克隆地址用 `Icons.link`）、`:8`（注释自称统一加载更多）、`:3537`（状态 `sync`）。
- 修复 / Fix：随 G-11（`Icons.link`→`content_copy`）、G-12（分页统一并修正注释）、F-22（sync 改进度指示）一并处理，不再单独施工。
- 影响 / Scope：仓库页 / repo page。工作量 / Effort：**S**。

> **条目核算 / Item accounting**：边界 B-01…B-09（9：严重 2 / 中 4 / 轻 3）；接地 G-01…G-12（12：严重 6 / 中 6 / 轻 0）；密度 D-01…D-14（14：严重 7 / 中 6 / 轻 1）；反馈 F-01…F-26（26：严重 13 / 中 10 / 轻 3）。合计 **61 条确证问题（28 / 26 / 7）**，与「二、合并去重方法」分布表及执行摘要一致。跨席编号（1-A S1、2-B S1、5-C C-S1 等）为原始报告回链，不计入 61。分类计数以「二、合并去重方法」分布表为准。

---

## 四、分批落地建议 / Batched Rollout

> 排序原则：先主题层根治（一处改全库生效），再统一出口补状态，再外壳与转场，最后反馈闭环与治理。
> Ordering principle: theme-level root fixes first (one edit propagates globally), then shared-exit states, then shell and transitions, finally feedback closure and governance.

### 第一批 · 主题层根治 / Batch 1 — Theme-level root fixes

**目标 / Goal**：`theme.dart` 单文件集中修改，一次生效覆盖全部 30 页，最快见效。All edits concentrated in `theme.dart`; one pass covers all 30 pages.

| 序 | 文件:行 | 动作 / Action | 覆盖问题 / Issues |
|---|---|---|---|
| 1 | `theme.dart:344-348` | `dividerTheme.color`: `outlineVariant` → `outlineVariantStrong`（新增 token，对各级 surface ≥3:1，明暗成立）；`thickness:1` 保留 | B-01 |
| 2 | `theme.dart` OgLSemanticColors 附近 | 新增 `outlineVariantStrong` 常量（明 `#94939A` / 暗 `#707075` 起，按 WCAG 公式校准） | B-01 |
| 3 | `theme.dart:215` | card side `outlineVariant` → `outlineVariantStrong` | B-01 / G-01 |
| 4 | `theme.dart:213` + ThemeData | card `surfaceContainerLow` → `surfaceContainer`；ThemeData 加 `scaffoldBackgroundColor: scheme.surface` | G-01 / G-07 |
| 5 | `theme.dart:217/228/251/262` | card 0→1、dialog 0→3、sheet 0→1、snackbar 0→3；`shadowColor: shadow@12%` | G-01 / G-03 |
| 6 | `theme.dart:252/229` | sheet `surfaceContainerLow`→`surfaceContainerHigh`；dialog `surfaceContainerHigh`→`surfaceContainerHighest` | G-03 |
| 7 | `theme.dart:395/399` | input `border`/`enabledBorder`: `BorderSide.none` → `BorderSide(color: outlineVariantStrong)` | B-02 |
| 8 | `theme.dart:387` | input `fillColor`: `surfaceContainerHighest` → `surfaceContainerHigh` | G-04 |
| 9 | `theme.dart:356/379/254` | chip side、segmented side、sheet dragHandle → `outlineVariantStrong` | B-01 |
| 10 | `theme.dart:271` + `:263-265` | 深色 SnackBar `actionTextColor` → `onSurface`（或底色改 `inverseSurface`）；明暗底色统一 inverse 配对 | B-06 |
| 11 | `theme.dart:285-287` | appBar `scrolledUnderElevation:0`→`2`，底色与 navbar 同族 | G-02 |
| 12 | `theme.dart:298/300` | navbar `height:64`→80（或 labelBehavior→onlyShowSelected）；底色同 AppBar 族或补顶边线 | G-05 |
| 13 | `theme.dart` 按钮 Theme + `:340` | 四个按钮加 `disabledForegroundColor: onSurface@60%`；listTile 选中态 `primaryContainer@55%`→不透明 | B-08 / G-07 |
| 14 | `theme.dart` 前（新增）/ `:451-455` | 新增 `navigationRailTheme`（与 navigationBarTheme 同语言）；按钮 `minimumSize:Size(48,48)` 保持、iconSize 20→24 | G-08 / B-05 |

**预期收益 / Expected yield**：卡片对比 1.052→可辨、74 条分隔线过 3:1、输入框空闲态可见、暗色 SnackBar 动作可读、AppBar/navbar 出现边界与滚动态——覆盖「漂浮感/边界消失」两项主诉的大部分症状。工作量为主题单文件约 14 处改动（S–M）。
Card contrast becomes perceptible, 74 dividers pass 3:1, idle inputs gain visible borders, dark snackbar actions become legible, app bar/navbar gain boundaries—resolving most floating/edge symptoms at S–M effort.

### 第二批 · 骨架与状态 / Batch 2 — Skeletons and states

| 序 | 文件 | 动作 / Action | 覆盖问题 / Issues |
|---|---|---|---|
| 1 | `async.dart:398-417` | `OgLAsyncEmptyPane` 加 `maxWidth:320` 约束、图标 avatar→xl、可选副标题、必填 action | D-05 |
| 2 | `async.dart:485-497/538-546` | `OgLAsyncSliver` 增 `emptyAction` 并传给 EmptyPane；三个 sliver 使用方补 CTA | D-05 |
| 3 | `async.dart:293-300/552-560` | 抽 `OgLAsyncSkeleton`（来自 `search_page.dart:134-147`），`AsyncView`/`OgLAsyncSliver` loading 改二段式骨架 | D-06 |
| 4 | `async.dart:141-163` | `AsyncController` 加 300ms 延迟 + 最小显示时长 | D-06 |
| 5 | `async.dart:215-245` | `_describe` 抽顶层 `ogLDescribeError`，替换 4 页原始异常外泄 | F-11 |
| 6 | 各页（14） | 逐页空态 CTA（`FilledButton.tonal`）+ 首次使用文案 + 筛选差异化文案入 i18n | D-05 / D-14 |
| 7 | `legal_text_page.dart`/`onboarding_page.dart` | error→empty 混淆修复（`_error` + `OgLAsyncErrorPane(onRetry)`） | F-11 |
| 8 | `repo_tags_page.dart:190-219` | 整页迁移 `AsyncController`/`AsyncView` | F-11 |
| 9 | `dashboard_page.dart:451-453`、`search_page.dart:1364` | 删半屏占位、去掉裸转圈改骨架 | D-05 / D-06 |

**预期收益 / Expected yield**：等待与空态从「一片空白 + 一个圈」变为「有结构的骨架 + 明确出口」，直接消解用户所说的「空」。工作量为统一出口 + 14 页（M–L）。
Waiting and empty states shift from blank-and-spin to structured skeletons plus explicit exits; effort M–L across the shared exit plus 14 pages.

### 第三批 · 外壳与转场 / Batch 3 — Shell and transitions

| 序 | 文件 | 动作 / Action | 覆盖问题 / Issues |
|---|---|---|---|
| 1 | `client_shell.dart:321-330` + `og_l_window_widths.dart:9` | 限宽只作用于内容、AppBar full-bleed；`contentMax` 720→960–1040；宽屏多列自适应 | G-05 |
| 2 | `client_shell.dart:342-364/374-402/404` | 外壳三态共用目的地数据源、新增 rail 主题对接、`SafeArea(top:true)`、`groupAlignment:0.0`、补发现 `selectedIcon`、删冗余 VerticalDivider | G-08 |
| 3 | `client_shell.dart:503-508` | 切 tab 透明度下限 0.7→0.94、位移 ≤屏宽 2%、边界收回 `[0,1]`、顶栏静止 | G-09 |
| 4 | `og_l_app_bar.dart:83/115/117/133-136/139-149` | 删除 Primary 兜底假设、显式传 controller、`pixels-minScrollExtent`、插值终点 surfaceContainerHigh、拆整栏重建 | G-02 |
| 5 | 15 页原生 `AppBar` | 统一到 `OgLAppBar` | G-10 |
| 6 | `motion.dart:423-469/457/249/224/348-352` | 补 secondaryAnimation 退场、改 shared-axis X、取消整页缩放、按平台分发 | F-12 |
| 7 | `motion.dart:244-254/420/247-248` | 错峰封顶 374ms、fast 150、settle 去回弹、largeCurve 换 M3 decelerate、淡入与位移同窗、取消逐控件位移 | F-15 |
| 8 | `client_shell.dart:246-253/167-170/159-162/203-205` | 返回链：条件式 `canPop`、`maybePop()`、闸门反馈、tab 访问栈 | F-13 |
| 9 | `boot_splash.dart`/`main.dart`/`og_l_app.dart:173-240`/`client_shell.dart:134-137` | 启动链路锚定、失败页可滚动与主题跟随、15s 超时、三态 AnimatedSwitcher | G-06 |
| 10 | `lib/surface/util/og_l_icons.dart`（新增）+ 各页 | 语义图标层统一复制/刷新/打开/删除图标；分页模式统一 repo_page | G-11 / G-12 |

**预期收益 / Expected yield**：宽屏空墙消失、导航与顶栏有稳定锚点、转场方向有语义、返回不再被吞、启动无闪变。工作量为外壳 + 动效 + 15 页（L）。
Wide-screen empty margins disappear, navigation and app bars gain stable anchors, transitions encode direction, back gestures are no longer swallowed, startup stops flashing; effort L across shell, motion, and 15 pages.

### 第四批 · 反馈闭环 / Batch 4 — Feedback closure

| 序 | 文件 | 动作 / Action | 覆盖问题 / Issues |
|---|---|---|---|
| 1 | `overlays.dart`（新增 helper） | 新增 `ogLConfirm`/`ogLDangerConfirm`，替换 4+ 处危险确认与 16+ 手写确认框 | F-06 |
| 2 | `notifier.dart:60/73-88` | SnackBar 增 `action`/`duration`/语气视觉；`error_surface.dart:572` severity 映射；download_manager 收编 | F-03 |
| 3 | `issue_page.dart:174` 等 | `OgLBusyButton` 组件化 + dialog 层进度 + 成功确认 | F-01 / F-04 |
| 4 | `repo_page.dart:2697/4039/4062/4210/3973/4352/1544/1620/2449` | 写操作补 `if(_busy)return`、空回调改 null、单文件写改进度状态行 | F-02 / F-05 |
| 5 | 各新建页 + `gist_detail`/`profile`/`settings`/`action_run` | busy/spinner 补齐、宽度锁定、禁用原因说明 | F-04 / F-19 |
| 6 | `new_issue`/`new_repo`/`new_release`/`new_gist`/`login` | 字段级 `errorText`、必填标记、`onChanged` 即时校验、错误文案三要素、防重闸 | F-08 / F-09 / F-10 |
| 7 | `code_editor_page.dart:253-277` | 乐观结果写持久通知 + 待同步角标 | F-20 |
| 8 | 6 页写操作 | 成功确认 SnackBar、语气 success 归一 | F-18 |
| 9 | `motion.dart:330`/`og_l_app.dart:96`/`surface_bridge.dart:565`/`overlays.dart:74-82` | 路由时长纳档位、主题动画接真实档位、系统 reduce 接入、对话框接档位 | F-14 |
| 10 | `search_page.dart`/`readme_view.dart`/`file_preview_page.dart`/`repo_page.dart`/`login_page.dart`/`code_editor_field.dart` | a11y 语义补齐（button/semanticLabel/状态词/live region/autofillHints/tooltip） | F-22 |
| 11 | `test/surface/a11y_test.dart`（新增）+ CI | a11y 测试 + 主题/图标 CI grep | F-23 |
| 12 | 深链 + 滚动恢复 | app link 解析、Dashboard key 去账号、repo PageStorageKey | F-21 |

**预期收益 / Expected yield**：每个写操作有「点击→busy→成功确认→失败可重试」闭环，表单错误紧邻字段，读屏链路完整。工作量为跨页组件化 + 测试（L）。
Every write gains a click→busy→confirm→retry loop; form errors sit beside fields; screen-reader paths complete; effort L (cross-page componentization plus tests).

**批次依赖 / Batch dependencies**：第一批为第二批的基底（骨架色/空态边界依赖主题色阶）；第三批依赖第一批的色阶与 elevation 结论；第四批的 busy 按钮与 SnackBar 语气依赖主题 token。建议第一批独立发版验证后再启后续批次。
Batch 1 is the substrate for Batch 2 (skeleton colors and empty-state edges depend on theme tonal levels); Batch 3 depends on Batch 1's color/elevation conclusions; Batch 4's busy button and snackbar tone depend on theme tokens. Recommended: ship and verify Batch 1 independently before starting later batches.

---

## 五、双维度索引 / Dual-Dimension Index

### 5.1 按页面矩阵 / Page Matrix（30 页全覆盖 / all 30 pages）

> 每页列出命中的确证问题编号；「—」表示该页无本轮确证问题（已查但通过）。
> Each page lists the confirmed issue IDs hitting it; "—" means no confirmed issue (audited, passed).

**仓库域 / Repository domain**

| 页面 / Page | 确证问题 / Confirmed issues |
|---|---|
| `repo_page.dart` | B-01/B-02/B-03、G-01/G-04/G-05/G-10/G-11/G-12、D-01/D-02/D-03/D-07/D-08/D-10/D-13、F-02/F-05/F-07/F-08/F-09/F-18/F-19/F-21/F-22/F-26 |
| `repo_tags_page.dart` | B-01/B-03、G-01/G-07、D-08、F-06/F-07/F-11/F-12 |
| `commit_page.dart` | B-01、G-01/G-10、D-02、F-12 |
| `pull_page.dart` | B-01、G-01/G-10、D-02/D-03/D-05、F-07/F-12 |
| `release_detail_page.dart` | B-01/B-02/B-03/B-05/B-07、G-01/G-10/G-11、D-01/D-08、F-06/F-12/F-17/F-22 |
| `code_editor_page.dart` | B-01/B-02/B-03/B-05、G-01/G-04/G-10/G-11、D-08、F-04/F-14/F-17/F-20/F-22 |
| `file_preview_page.dart` | B-01/B-03、G-01/G-04/G-10/G-11、D-01/D-08、F-11/F-22 |

**议题域 / Issue domain**

| 页面 / Page | 确证问题 / Confirmed issues |
|---|---|
| `issue_page.dart` | B-01/B-03/B-06、G-01/G-02/G-04/G-10、D-01/D-03/D-04/D-05/D-10/D-13、F-01/F-03/F-06/F-08/F-09/F-12/F-22 |
| `new_issue_page.dart` | B-01/B-02、G-01/G-10、D-01/D-02、F-04/F-08/F-09/F-10/F-12 |
| `notifications_page.dart` | B-01/B-05、G-01/G-07/G-11、D-01/D-07/D-09/D-14、F-06/F-07/F-18 |
| `dashboard_page.dart` | B-01/B-03、G-01/G-02/G-07/G-10/G-11/G-12、D-01/D-03/D-05/D-06/D-14、F-07/F-12/F-21/F-22 |

**内容域 / Content domain**

| 页面 / Page | 确证问题 / Confirmed issues |
|---|---|
| `gists_page.dart` | B-01/B-03、G-01/G-07/G-10、D-01/D-03/D-05/D-14 |
| `gist_detail_page.dart` | B-01、G-01/G-10/G-11、D-05/D-14、F-04/F-06/F-19 |
| `new_gist_page.dart` | B-01/B-02、G-01/G-04/G-10、D-01/D-02、F-03/F-04/F-07/F-08/F-10/F-12 |
| `readme_view.dart`（共享组件 / shared widget） | B-01、G-04、D-03/D-11、F-22 |
| `search_page.dart` | B-01/B-03/B-05/B-07/B-09、G-01/G-02/G-03/G-04/G-10/G-11/G-12/G-13(无)、D-01/D-02/D-03/D-05/D-06/D-09/D-13/D-14、F-03/F-07/F-12/F-14/F-15/F-17/F-22 |

**账户域 / Account domain**

| 页面 / Page | 确证问题 / Confirmed issues |
|---|---|
| `login_page.dart` | B-01、G-01/G-06/G-10、D-02、F-04/F-08/F-09/F-11/F-22 |
| `onboarding_page.dart` | B-01、G-01/G-06/G-10、D-01/D-04、F-11/F-17 |
| `profile_page.dart` | B-01、G-01/G-07/G-10、D-05/D-14、F-06/F-19 |
| `settings_page.dart` | B-01/B-02/B-03/B-05、G-01/G-07/G-10/G-11、D-01/D-08/D-12、F-03/F-08/F-19/F-22 |
| `settings_section_page.dart` | B-01/B-03、G-01/G-10、D-12 |
| `network_page.dart` | B-01/B-03、G-01/G-10、D-01/D-12 |
| `about_page.dart` | B-01/B-03、G-01/G-07/G-10/G-11、D-08 |
| `legal_text_page.dart` | B-01/B-03、G-01/G-10、D-01/D-02/D-04、F-11 |

**工具域 / Tool domain**

| 页面 / Page | 确证问题 / Confirmed issues |
|---|---|
| `download_manager_page.dart` | B-01/B-03、G-01、D-01/D-08、F-03/F-07/F-11/F-25 |
| `workflow_dispatch_page.dart` | B-01/B-02/B-03、G-01/G-10、D-02/D-08/D-14、F-07/F-10/F-11 |
| `action_log_page.dart` | B-01/B-05、G-01/G-07/G-10/G-11、D-08/D-14、F-22 |
| `action_run_page.dart` | B-01、G-01/G-10/G-11、D-08、F-07/F-18/F-19/F-22 |
| `new_repo_page.dart` | B-01/B-02、G-01/G-10、D-01/D-02、F-08/F-09/F-12 |
| `new_release_page.dart` | B-01/B-02、G-01/G-10、D-01/D-02、F-04/F-08/F-09/F-12 |
| `drafts_page.dart` | B-01、G-01/G-07/G-10、D-01/D-05、F-06 |
| `main.dart` / `boot_splash.dart`（启动链 / startup chain） | G-06、F-14 |

### 5.2 按根因文件 / Root-Cause File Index（热点文件 / Hotspots）

> 按命中确证问题密度排序；「问题编号」为该文件的跨席编号汇总。
> Sorted by density of confirmed issues; IDs are the cross-seat issue numbers for that file.

| 热点文件 / Hotspot | 命中确证问题 / Confirmed issues | 主要类别 / Categories |
|---|---|---|
| `lib/surface/theme.dart` | B-01/B-02/B-05/B-06/B-08/B-09、G-01/G-02/G-03/G-04/G-05/G-07/G-08、D-03 | 边界 + 接地核心 / borders + grounding core |
| `lib/surface/app/async.dart` | D-05/D-06、F-11 | 密度 + 状态 / density + states |
| `lib/surface/app/client_shell.dart` | G-05/G-08/G-09、F-12/F-13/F-16/F-21 | 外壳 + 返回链 / shell + back chain |
| `lib/surface/app/motion.dart` | F-12/F-14/F-15/F-24 | 动效 / motion |
| `lib/surface/app/notifier.dart` | B-06、F-03/F-22 | 反馈 / feedback |
| `lib/surface/app/og_l_app_bar.dart` | G-02/G-10 | 接地 / grounding |
| `lib/surface/app/og_l_app.dart` | G-06、F-14/F-22/F-23 | 启动 + 主题 / startup + theming |
| `lib/surface/app/overlays.dart` | B-04、F-06/F-14/F-17 | 弹层出口 / overlay exits |
| `lib/surface/app/boot_splash.dart` | G-06 | 启动 / startup |
| `lib/surface/app/error_surface.dart` | F-03/F-13 | 反馈 / feedback |
| `lib/surface/widgets/discover_rows.dart` | B-07、D-03/D-14 | 密度 + 边界 / density + borders |
| `lib/surface/widgets/flat_list.dart` | B-03/B-09、D-10 | 边界 + 密度 / borders + density |
| `lib/surface/widgets/settings/settings_group.dart` | D-10/D-12 | 密度 / density |
| `lib/surface/widgets/readme_view.dart` | B-01、D-11、F-22 | 边界 + 密度 / borders + density |
| `lib/surface/widgets/code_editor_field.dart` | B-02、F-22 | 边界 + a11y / borders + a11y |
| `lib/surface/util/og_l_space.dart` | D-01/D-08 | 密度令牌 / spacing tokens |
| `lib/surface/util/og_l_window_widths.dart` | G-05 | 接地 / grounding |
| `lib/surface/util/og_l_icons.dart`（拟新增 / proposed） | G-11 | 接地 / grounding |
| `lib/surface/pages/repo_page.dart` | 见 5.1（命中最多 / highest page count） | 全类 / all categories |
| `lib/surface/pages/issue_page.dart` | 见 5.1 | 全类 / all categories |
| `lib/surface/pages/search_page.dart` | 见 5.1 | 全类 / all categories |
| `test/surface/a11y_test.dart`（拟新增 / proposed） | F-23 | 治理 / governance |

**结论 / Conclusion**：`theme.dart` 与 `async.dart` 两处即覆盖四项主诉中的「漂浮、边界、空」三项的根因；`client_shell.dart` + `motion.dart` 覆盖「不稳定」外壳与转场根因。按第四批顺序落地，可在最低改动面下完成全库稳定性收敛。
`theme.dart` and `async.dart` cover the root causes of "floating, edges, empty"; `client_shell.dart` plus `motion.dart` cover the unstable shell and transitions. Executing the Batch 1–4 order converges app-wide stability at minimal change surface.

---

*本文档为只读审计汇总产物：未修改 `lib/` 下任何代码，未执行 commit / push。所有 `file:line` 证据可在 HEAD `f684160` 复现。*
*This document is a read-only consolidation artifact: no code under `lib/` was modified; no commit or push was performed. All `file:line` evidence is reproducible at HEAD `f684160`.*
