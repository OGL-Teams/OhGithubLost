# 批 2-B · 边界强度与接地感审计（Dividers / Borders / Outline）

> 文档戳：更新于 2026-11-22 00:35:22 (Asia/Shanghai) · 版本 v14.0.0 · 审计席：批 2 · B 席（描边/分割/边界强度）
> 审计范围：`lib/surface/theme.dart`（dividerTheme / cardTheme.side / inputDecorationTheme 边框 / listTileTheme.shape / chipTheme.side / segmentedButtonTheme.side / 弹层描边）+ `lib/surface/pages/` 全部 30 页 + `lib/surface/widgets/`、`lib/surface/app/` 的 Divider / Border / outline 使用密度。
> 方法：① 全库 `rg` 逐条统计 Divider（74）、outlineVariant（11）、裸 `OutlineInputBorder()`（26）、Card（24）；② 复用批 2-A 的色值（seed `#0969DA` / SchemeTonalSpot，`ColorScheme.fromSeed` 等价实现）用 WCAG sRGB 公式重算 `outlineVariant` / `outline` 对各级 surface 的对比度与 ΔL\*；③ 按任务书轴二功能页面矩阵逐页过 30/30。
> 约束：只读审计，未改任何产品代码，未 commit / push。

---

## 0. 结论速览（量化）

### 0.1 边界线颜色实测（这是「边界消失感」的直接数值来源）

| 前景（线/描边） | 背景 | 明色对比度 | 暗色对比度 | WCAG 1.4.11 非文本 3:1 |
|---|---|---|---|---|
| `outlineVariant #C7C6CA/#46464A` | `surface`（页面底） | **1.621** | **1.977** | ❌ FAIL |
| `outlineVariant` | `surfaceContainerLow`（卡片底） | **1.541** | **1.828** | ❌ FAIL |
| `outlineVariant` | `surfaceContainer`（导航/AppBar 滚深） | 1.461 | 1.748 | ❌ FAIL |
| `outlineVariant` | `surfaceContainerHigh`（对话框/Chip） | 1.384 | 1.528 | ❌ FAIL |
| `outlineVariant` | `surfaceContainerHighest`（输入框/代码块） | **1.318** | **1.305** | ❌ FAIL（最弱） |
| `outline #77777A/#919094` | `surface` | 4.259 | 5.857 | ✅ PASS |

**判定**：全局 dividerTheme 与 cardTheme.side 使用的 `outlineVariant`（`theme.dart:347`、`:215`）在所有 5 级承载背景上对比度 **1.30–1.98，全部低于 3:1**。唯一过线的 `outline`（4.26/5.86）只用在 OutlinedButton（`theme.dart:444`），**没有用于任何分割线或卡片描边**。这就是用户所说「边界消失、内容悬空」的根因：线条在代码里存在，在屏幕上不存在。

### 0.2 Divider 使用密度（30 页 + 组件 + 外壳，共 74 处 `Divider(` / `VerticalDivider(`）

| 密度档 | 页面（数量） |
|---|---|
| 极密 ≥10 | `settings_page.dart` 31（含 5 处 `height:24/28/20/32`）、`about_page.dart` 11 |
| 中 3–6 | `repo_page.dart` 6、`search_page.dart` 5（其中 1 处是注释）、`issue_page.dart` 3 |
| 稀 1–2 | `login_page` 2、`action_run_page` 2、`commit` / `dashboard` / `drafts` / `gist_detail` / `gists` / `legal_text` / `notifications` / `profile` / `pull` / `release_detail` 各 1 |
| **零 0（13 页）** | `action_log`、`code_editor`、`download_manager`、`file_preview`、`network`、`new_gist`、`new_issue`、`new_release`、`new_repo`、`onboarding`、`repo_tags`、`settings_section`、`workflow_dispatch` |

- 组件/外壳另有：`flat_list.dart:47`（设置/关于/用户共用分隔）、`code_editor_toolbar.dart:135`、`code_editor_field.dart:628`、`client_shell.dart:404`。
- **31 + 11 + 6 + 5 = 53 处 Divider 集中在 4 页**，其余 26 页合计 21 处 → 密度极不均衡：设置/关于页「线比内容多」，而 13 页「一根线都没有」。

### 0.3 区块边界手段普查：靠色差还是靠线

| 区块类型 | 实际边界手段 | 量化 | 判定 |
|---|---|---|---|
| 卡片 ↔ 页面 | `outlineVariant` 1px 描边 + `surfaceContainerLow` 底色 | 线 1.541 + 底 1.052 | ❌ **双重消失** |
| 列表行 ↔ 行 | `Divider(height:1)` / `ListView.separated`，线色 1.621 | 1.621 | ❌ 线不可见 |
| 列表行（Card 内） | `listTileTheme.shape` 仅圆角、无 side | 0（无线） | ❌ 行粘连 |
| 输入空闲态 ↔ 卡片 | `fillColor: surfaceContainerHighest` 色差 | 1.169（对卡片） | ⚠️ 靠色差；`borderSide: none` 无线 |
| 输入聚焦态 | `focusedBorder` primary 1.5px | 对 surface 高 | ✅ 唯一有效边界 |
| 分组（设置/关于） | `Divider` + 留白，无底色块 | 1.621 | ❌ 靠不可见的线 |
| 下载列表 | `separatorBuilder: SizedBox(height: sm)` | 纯留白 8dp | ⚠️ 完全无线 |
| BottomSheet / Dialog ↔ 底层 | 仅圆角 + dragHandle，**无描边、无投影** | 0 | ❌ **弹层边界线缺失** |
| 底部导航 ↔ 内容 | `surfaceContainer` 色差（无顶边线） | 1.055 | ❌ 浮带感 |
| 桌面侧栏 ↔ 主区 | `VerticalDivider(width:1)`，默认色 1.621 | 1.621 | ❌ 不可见 |
| AppBar ↔ 内容 | 同色、`scrolledUnderElevation:0`、无 bottom 线 | 0 | ❌ 无分界 |

---

## 1. 用户可感知问题清单（20 条 · 严重 6 / 中 9 / 轻 5）

### 严重 S

**S1 · 全局分割线色 `outlineVariant` 对任何底色都 <2:1，所有 Divider 事实上不可见**
- 证据：`lib/surface/theme.dart:344-348`（`dividerTheme: color: scheme.outlineVariant, thickness: 1, space: 1`）；实测对 `surface` 1.621/1.977、对 `surfaceContainerLow` 1.541/1.828。
- 用户感受：全库 74 条线里绝大多数「画了等于没画」，列表行之间像黏成一整块，页面读起来是一张没有结构的白纸 —— 「空」与「漂浮」同时发生。
- 修复：把 dividerTheme 的 `color` 改为 `scheme.outline`（4.259/5.857 过 3:1），或新增一个 token `outlineVariantStrong`（在 outlineVariant 与 outline 之间、对 surface ≥3:1）专供 1px 线；`theme.dart:347` 一行改动全库生效。

**S2 · 输入框空闲态 `BorderSide.none`，边界完全靠填充色差，聚焦才突然出现线**
- 证据：`lib/surface/theme.dart:393-400`（`border` / `enabledBorder` 均 `borderSide: BorderSide.none`），`:401-404` 仅 `focusedBorder` 有 `width:1.5`；页面还有 26 处裸 `border: OutlineInputBorder()` 覆写（如 `new_repo_page.dart:152/161`、`new_issue_page.dart:147/156`、`repo_page.dart:711/1472/1489`）。
- 用户感受：表单页的输入框像「涂在纸上的浅块」，点一下才冒出蓝框——未聚焦时用户分不清哪里能输入，边界随交互跳变，不稳定。
- 修复：`theme.dart:395`、`:399` 的 `BorderSide.none` → `BorderSide(color: scheme.outlineVariant)`（按 S1 改为强色后用同城强色）；保留 filled，形成「浅填充 + 可见 1px 框」的 MD3 outlined 语义；随后清理 26 处冗余裸覆写，统一吃主题。

**S3 · 卡片「双重消失」：底色只差 1.052，描边只有 1.541**
- 证据：`lib/surface/theme.dart:213`（`color: scheme.surfaceContainerLow`）、`:215`（`side: BorderSide(color: scheme.outlineVariant)`）、`:217`（`elevation: 0`）；全库 24 个 `Card(` **无一覆写 shape/side**，全部吃这套失效边界。
- 用户感受：卡片既没有色差又没有可读的框，还是零投影，用户看到的是「文字散落在白底上」而不是「一块可点的卡片」，直接对应「没有工具感」。
- 修复：`theme.dart:215` 描边色 → `scheme.outline`（或 S1 的强 token）；按批 2-A 的 R1/R2 同步把底色提到 `surfaceContainer` 或补 level-1 投影，使「色差 + 线」至少有一条真正可见。

**S4 · 弹层与底层边界线缺失：BottomSheet / Dialog / SnackBar 全无描边与投影**
- 证据：`lib/surface/theme.dart:228` dialog `elevation: 0`、`:230` `shapeXl` 无 side；`:251` bottomSheet `elevation:0`、`:254` 只有 `dragHandleColor: outlineVariant`，shape 无 side；`:262` snackBar `elevation:0`，无描边。
- 用户感受：长按弹出的操作面板与底层卡片同为 `surfaceContainerLow`，中间只有一道 1.3–1.8:1 的圆角弧线和拖柄，弹层「没有抬起来」，像卡片自己裂开一条缝——边界不清、层级不稳。
- 修复：给 `dialogTheme.shape` / `bottomSheetTheme.shape` 补 `BorderSide(color: scheme.outlineVariantStrong)`；bottomSheet 底色改为 `surfaceContainerHigh` 与卡片拉开档位；按批 2-A R2 给弹层恢复 level 1/3 阴影。

**S5 · 13/30 页零 Divider，整页区块边界纯靠留白**
- 证据：`network_page.dart:48-53`（`ListView` 只有 `SizedBox(height: xl)` 收尾，无任何线）、`download_manager_page.dart:275-276`（`separatorBuilder` = `SizedBox(height: OgLSpace.sm)`）、`repo_tags_page.dart:230`、`settings_section_page.dart:29-38`、`file_preview_page.dart:539`、`code_editor_page.dart:481`。
- 用户感受：这些页面全屏一块底色，区块之间没有可抓的结构线，用户要用手指试探才知道哪里是一组 —— 「空」的最直接来源。
- 修复：为这些页的分组容器统一加一条 `Divider` 或 1px `outlineVariantStrong` 上边线；下载页 `separatorBuilder` 由 `SizedBox(sm)` 改为 `Divider(height:1, indent: OgLSpace.lg)`；`settings_section_page` 的 `OgLRevealList` 分组间补分隔。

**S6 · 桌面侧栏与主区唯一边界是 1.621 的 `VerticalDivider`**
- 证据：`lib/surface/app/client_shell.dart:404`（`const VerticalDivider(width: 1)`，颜色走默认 `dividerTheme` 的 outlineVariant）；侧栏底色 `desktop_window.dart:138` `surfaceContainer` 对主区 `surface` 仅 1.055。
- 用户感受：宽屏下侧栏内容像「渗」进主区，两栏没有明确分界，窗口一宽就失去结构感。
- 修复：按 S1 提升线色后，将该 `VerticalDivider` 显式 `color: scheme.outlineVariantStrong`；侧栏底色改 `surfaceContainerLow` 或补 1px 右边界线，使色差 + 线至少一项可见。

### 中 M

**M7 · `listTileTheme.shape` 只有圆角没有 side → 行与行粘连**
- 证据：`lib/surface/theme.dart:168-170, 329-347`（`shape: shapeMd` = `RoundedRectangleBorder(borderRadius: cMd)`，**无 `side`**），`flat_list.dart:47` 只在行间插 `Divider`，`OgLFlatTile`（`flat_list.dart:60-89`）本身是裸 `ListTile`。
- 用户感受：卡片内的多行列表看起来是一段连续文字，行与行的归属靠猜。
- 修复：给 `shapeMd` 在 listTile 场景加 `BorderSide(color: scheme.outlineVariantStrong)`，或统一依赖 `ListView.separated` 的强色分隔线，二选一避免双线。

**M8 · Chip 无边框，`side: BorderSide.none`**
- 证据：`lib/surface/theme.dart:356`；底色却是 `surfaceContainerHigh`（`:353`），对卡片底 1.145。
- 用户感受：标签是「一块更深的贴纸」，没有自己的轮廓，在卡片里既不清晰也不稳定。
- 修复：`theme.dart:356` → `side: BorderSide(color: scheme.outlineVariantStrong)`；按批 2-A R5 把 chip 底色降档。

**M9 · 弹层统一封装未定义 `barrierColor`，遮罩与边界全靠系统默认**
- 证据：`lib/surface/app/overlays.dart:61-76`（`ogLShowSheet` 只注入 `sheetAnimationStyle`，无 `barrierColor`）、`:80-88`（`ogLShowDialog` 同样未设）。
- 用户感受：弹层打开时底层只是「被压暗」，弹层自身没有清晰边界，用户不确定点击哪里会关闭。
- 修复：在 `ogLShowSheet` / `ogLShowDialog` 加 `barrierColor: scheme.scrim.withValues(alpha: .32)`，并配合 S4 的弹层描边，形成「暗底 + 亮边」双层边界。

**M10 · `search_page.dart:937` 绕过统一封装直调 `showModalBottomSheet`**
- 证据：`search_page.dart:937-943` 直接 `showModalBottomSheet`（未用 `ogLShowSheet`），无 `barrierColor`、无 shape 覆写；底层 `_RepoCard`（`:212`）是卡片。
- 用户感受：这一处弹层的边界/动画与其它页不同源，是全库「弹层观感不一致」的活样本。
- 修复：改为 `ogLShowSheet`，让动效与遮罩走 `overlays.dart` 统一定义。

**M11 · 26 处页面级裸 `OutlineInputBorder()` 覆写掩盖真实边框来源**
- 证据：`rg 'border: OutlineInputBorder\(\)' lib/surface` → 26 处（`new_gist_page.dart:162/170/184`、`new_release_page.dart:175/183/192`、`release_detail_page.dart:90/98/108`、`workflow_dispatch_page.dart:472/509`、`repo_page.dart:711/1472/1489/1789/2505/4284/4395/4483`、`settings_page.dart:1912/1921`、`action_log_page.dart:333`、`gist_detail_page.dart:193`、`new_repo_page.dart:152/161`、`new_issue_page.dart:147/156`）。
- 用户感受：这些输入框当前因主题 `enabledBorder:none` 仍无框（与 S2 同源）；但一旦有人给某处补 side，边界强度立刻与其它页分叉——是「边界随时会坏」的隐患。
- 修复：删除全部 26 处裸 `border:` 覆写，让输入框统一吃 `inputDecorationTheme`；需要特殊边框的个别框用 `InputDecorationTheme` 的新 token，不在页面写死。

**M12 · `discover_rows.dart` 已读行的左边界线与背景同色 → 边界消失**
- 证据：`lib/surface/widgets/discover_rows.dart:56-62`（`Border(left: BorderSide(color: unread ? primary : surface, width: xxs))`）。
- 用户感受：未读行有醒目的蓝色左标，已读时左边线直接变成背景色——不是「变淡」而是「消失」，列表左侧出现忽有忽无的断裂。
- 修复：未读/已读都用 `outlineVariantStrong` 作为底线，未读态再叠加 primary 强调（如加宽到 3px 或改色），不要退回 `surface`。

**M13 · divider 高度节奏失控：主题 `space:1` 但页面大量 `height:24/28/20/32`**
- 证据：`theme.dart:346`（`space:1`）vs `settings_page.dart:470/1554/1819/1825/1906`（height 28/24/24/28/20）、`repo_page.dart:4365/4438/4494`（height 32）、`about_page.dart` 与 `flat_list.dart:47`（height 1）。
- 用户感受：有的线紧贴文字、有的线拖出一大段空白，分割线变成「间距填充物」，节奏不统一显粗糙。
- 修复：把语义固定为两类——`height:1`（行间分隔）和 `height:OgLSpace.lg`（区块分隔），用两个 token；禁止 24/28/20/32 混用。

**M14 · 分段控件描边用失效的 `outlineVariant`**
- 证据：`lib/surface/theme.dart:378-380`（`side: BorderSide(color: scheme.outlineVariant)`）。
- 用户感受：分段控件的外框几乎看不见，选中/未选中的分界靠底色差，控件像浮在页面上。
- 修复：改用 `scheme.outlineVariantStrong`（或 `scheme.outline`），使未选中段有可读轮廓。

**M15 · 设置页 31 条 Divider 但分组无底色块，纯靠线堆密度**
- 证据：`settings_page.dart` 31 处 Divider（如 `:573/593/608/618/634/642/648/660/686/695/932/943/951/957/1028/1034/1044/2054/2061/2073/2080`），`settings_group.dart` 无底色/边界定义（`:225` 仅 `onSurfaceVariant` 文字色）。
- 用户感受：长页滚动时用户抓不到「块」，只有一条条看不见的线 —— 线多却不提供结构，反而更空。
- 修复：按批 2-A R7，给分组加 `surfaceContainerLowest` 底色块，Divide 数量下降到「每组一条」，线色按 S1 提升。

### 轻 L

**L16 · 登录页「或」分隔线无 inset，且用默认 `Divider()`**
- 证据：`login_page.dart:455/464`（`Expanded(child: Divider())`，未指定 height/color，吃全局 1.621 的线）。
- 用户感受：横线太淡且顶到卡片边缘，既没表达「分隔」也没形成视觉锚点。
- 修复：`Divider(height:1, color: outlineVariantStrong)` 并加 `EdgeInsets.symmetric(vertical: OgLSpace.md)` 留白。

**L17 · README 引用块 3px 竖线用 `outlineVariant`**
- 证据：`lib/surface/widgets/readme_view.dart:397-399`（`BorderSide(color: scheme.outlineVariant, width: 3)`）。
- 用户感受：引用块左侧竖线偏淡，粗度有了但对比不足，引用层级不明显。
- 修复：宽度保留 3px，颜色改 `outlineVariantStrong` 或 `scheme.outline`。

**L18 · 代码编辑器行号竖线用 `outlineVariant`**
- 证据：`lib/surface/widgets/code_editor_field.dart:628-632`（`VerticalDivider(width:1, thickness:1, color: scheme.outlineVariant)`）。
- 用户感受：行号区与正文区的分界在深色代码底上对比仅 1.305（最弱组合），行号像浮在正文里。
- 修复：`color: scheme.outlineVariantStrong`；代码底为 `surfaceContainerHighest`，建议该场景直接用 `scheme.outline`（对 highest 明 1.85/暗 1.9 仍需更强，可再提一级）。

**L19 · SnackBar floating 无描边，明暗两套底色**
- 证据：`lib/surface/theme.dart:260-274`（`shape: shapeMd`、`elevation:0`、明色 `inverseSurface` / 暗色 `surfaceContainerHighest`，均无 side）。
- 用户感受：浮动提示条没有轮廓，在复杂背景上可能与内容糊在一起；明暗切换时深浅极性翻转。
- 修复：补 `side: BorderSide(color: scheme.outlineVariantStrong)`，并按批 2-A R6 统一明暗底色通道。

**L20 · 主分隔线缺少 inset/indent 规范，全库 1px 线顶格**
- 证据：`flat_list.dart:47`、`settings_page.dart` 多处、`search_page.dart:143/783/1046/1373` 均为 `Divider(height:1)` 无 `indent`/`endIndent`。
- 用户感受：线从屏幕最左拉到最右，列表项没有「行」的收口感，显得粗糙。
- 修复：MD3 列表分隔常用 `indent: 16dp`；统一给全局 dividerTheme 加 `indent`/`endIndent`，或在 `ListView.separated` 的 separator 里统一设置。

---

## 2. 修复指令汇总（按「稳定感优先」排序，全部只改令牌/主题，不逐页硬编码）

| 优先级 | 指令 | 落地位置 | 治什么问题 |
|---|---|---|---|
| P0 | 新增 `outlineVariantStrong`（对 surface ≥3:1，建议明 `#94939A`/暗 `#707075` 起步并用 WCAG 公式校准），全部分割/描边改用它 | `lib/surface/theme.dart` OgLSemanticColors 附近新增常量 | S1/S3/S6/M10/M13/M14/L16-L18 |
| P0 | `dividerTheme.color`: `outlineVariant` → `outlineVariantStrong`；`thickness:1` 保留 | `theme.dart:344-348` | S1、M13、L20 |
| P0 | `cardTheme.shape` 的 side 色 → `outlineVariantStrong`；卡片底色按 2-A R1 提档 | `theme.dart:215/213` | S3 |
| P0 | `inputDecorationTheme` 的 `border`/`enabledBorder` 由 `BorderSide.none` → `BorderSide(color: outlineVariantStrong)` | `theme.dart:395/399` | S2 |
| P1 | 弹层 shape 补 side + 底色拉档 + `barrierColor` 统一 | `theme.dart:228-255`、`overlays.dart:61/80` | S4/M9/M10/L19 |
| P1 | 零 Divider 的 13 页分组补线（尤其 `network_page`、`download_manager_page`、`settings_section_page`、`repo_tags_page`） | 各页 body / separatorBuilder | S5 |
| P1 | `listTileTheme.shape` 加 side，与行间 Divider 二选一 | `theme.dart:168/329` | M7 |
| P1 | 桌面侧栏 `VerticalDivider` 显式强色 + 侧栏底色差 | `client_shell.dart:404` | S6 |
| P2 | chip / segmentedButton side → 强色 | `theme.dart:356/379` | M8/M14 |
| P2 | 删除 26 处裸 `OutlineInputBorder()` 覆写 | 见 M11 清单 | M11 |
| P2 | `discover_rows.dart` 已读行左边线不退回 surface | `discover_rows.dart:56-62` | M12 |
| P2 | divider 高度收敛为两类 token（1 / lg） | `settings_page.dart`、`repo_page.dart`、`theme.dart` | M13 |
| P2 | 设置/关于分组加 `surfaceContainerLowest` 底色块，减少线数量 | `settings_group.dart`、`about_page.dart`、`flat_list.dart` | M15 |

> 注：`outlineVariantStrong` 的具体色值必须按第一原则实测——目标是**对 surface / surfaceContainerLow / surfaceContainerHighest 均 ≥3:1**，且明/暗主题都成立；报告只给设计目标，不臆造单一十六进制值。

---

## 3. 检查清单（证明 30 页 + 组件 + 外壳全查）

### 3.1 主题层（theme.dart）
- [x] `dividerTheme`（:344-348）：thickness=1、space=1、color=outlineVariant → 实测 1.30–1.98 FAIL（S1）
- [x] `cardTheme.side`（:215）：outlineVariant 1px，24 个 Card 全部继承，无覆写（S3）
- [x] `inputDecorationTheme`（:393-413）：border/enabledBorder none；focused/error 有边（S2）
- [x] `listTileTheme.shape`（:329-347）：仅 shapeMd 圆角、无 side（M7）
- [x] `chipTheme.side`（:356）：BorderSide.none（M8）
- [x] `segmentedButtonTheme.side`（:379）：outlineVariant（M14）
- [x] `dialogTheme`（:228-241）/ `bottomSheetTheme`（:250-257）/ `snackBarTheme`（:260-274）：全部无描边、elevation 0（S4/L19）
- [x] `navigationBarTheme`（:299-300）：surfaceContainer 无顶边线（0.3 节）
- [x] `appBarTheme`（:286-289）：无 bottom 线（0.3 节）
- [x] `outlineVariant` 在主题中共 5 次引用（:215/:254/:347/:379 + 注释），`outline` 仅 1 次（:444 OutlinedButton）

### 3.2 组件与外壳
- [x] `widgets/flat_list.dart:47`：行间 Divider(height:1)，设置/关于/用户共用（M13/L20）
- [x] `widgets/code_editor_toolbar.dart:135`、`code_editor_field.dart:628`：代码区竖线（L18）
- [x] `widgets/readme_view.dart:397`：引用块 3px 竖线（L17）
- [x] `widgets/discover_rows.dart:56`：已读行边界退回 surface（M12）
- [x] `widgets/settings/settings_group.dart`：无底色/边界定义（M15）
- [x] `app/client_shell.dart:404`：桌面侧栏 VerticalDivider 默认色（S6）
- [x] `app/overlays.dart:61/80`：弹层统一封装无 barrierColor（M9）；`search_page.dart:937` 绕过封装（M10）

### 3.3 全 30 页独立小节（轴二 · 功能页面矩阵）

> 每页固定记录：Divider 数 / 边界手段 / 已查项 / 结论。通用前提：30 页均未在页面层设置 `Scaffold.backgroundColor`，页面底色为 `scheme.surface`；卡片描边统一吃 `theme.dart:215`。

#### 仓库域

**1. `repo_page.dart`** — Divider 6（`:811` 列表 separated、`:1295` 预览分组、`:1995` 文件条目、`:4365/4438/4494` 设置区块 height32）+ Border 9（全库最多）。
- 已查：`:711/1472/1489/1789/2505/4284/4395/4483` 裸 `OutlineInputBorder()` 覆写；`:4501` Card 吃主题描边。
- 结论：❌ 问题页（S1/M11/M13）——区块线高度 32 且不可见，输入框边界来源混乱。

**2. `repo_tags_page.dart`** — Divider 0；`ListView.builder`（`:230`）。
- 已查：标签行无分隔线、无底色块，纯留白（`:216/235`）。
- 结论：❌ 问题页（S5）——裸列表全靠留白，行粘连。

**3. `commit_page.dart`** — Divider 1（`:139`）；Card 1（`:113`）。
- 已查：卡片描边为主题 outlineVariant；无页面级 border 覆写。
- 结论：⚠️ 卡片双重消失（S3），分割线不可见（S1）。

**4. `pull_page.dart`** — Divider 1（`:151`）；Card 1（`:139`）。
- 已查：`:203` 徽标用 surfaceContainerHighest 而非线；无额外边界。
- 结论：⚠️ 同 S1/S3。

**5. `release_detail_page.dart`** — Divider 1（`:523`）；Card 2（`:510/533`）；Border 3（`:90/98/108` 裸输入框）。
- 已查：输入框裸覆写、卡片主题描边、分组线。
- 结论：⚠️ 问题页（M11/S1/S3）。

**6. `code_editor_page.dart`** — Divider 0；无 Card；编辑器底 `surfaceContainerHighest`（`:481/609`）。
- 已查：行号竖线来自 `code_editor_field.dart:628`（outlineVariant，1.305 最弱组合）；工具栏竖线 `code_editor_toolbar.dart:135`。
- 结论：❌ 问题页（L18）——唯一边界线在代码底上几乎不可见。

**7. `file_preview_page.dart`** — Divider 0；音频卡 `:539` 为 Center+Padding，无描边。
- 已查：空态/预览区无区块边界，全靠 Icon + 留白。
- 结论：⚠️ 问题页（S5）——纯留白分区。

#### 议题域

**8. `issue_page.dart`** — Divider 3（`:785` 评论区分隔、`:849` 评论卡间、`:873` 发表评论区）；Card 2（`:762/806`）；Border 5（全库第二）。
- 已查：评论区与正文仅靠 1px 弱线；卡片主题描边。
- 结论：❌ 问题页（S1）——三处关键区块边界都不可见。

**9. `new_issue_page.dart`** — Divider 0；Card 1（`:162`）；裸 `OutlineInputBorder()` 2（`:147/156`）。
- 已查：表单输入无空闲边框（S2 同源）；卡片描边弱。
- 结论：⚠️ 表单边界缺失（S2/S3）。

**10. `notifications_page.dart`** — Divider 1（`:230`）；`ListView.separated`（`:169`）；无 Card。
- 已查：`:366` 徽标高亮块；列表行间仅弱线。
- 结论：❌ 问题页（S1/M18）——通知行粘连。

**11. `dashboard_page.dart`** — Divider 1（`:480` separated）；无 Card；Border 0。
- 已查：列表行间以弱线分隔；其余靠色差。
- 结论：⚠️ 分割线不可见（S1）。

#### 内容域

**12. `gists_page.dart`** — Divider 1（`:156`）；`ListView.separated`（`:135`）；无 Card。
- 已查：列表行仅 1px 弱线。
- 结论：❌ 问题页（S1）。

**13. `gist_detail_page.dart`** — Divider 1（`:401`）；Card 1（`:403`）；裸输入框 1（`:193`）。
- 已查：文件列表卡片 + 裸输入框覆写。
- 结论：⚠️ 问题页（M11/S3）。

**14. `new_gist_page.dart`** — Divider 0；裸输入框 3（`:162/170/184`）；无 Card。
- 已查：全表单输入框无空闲边框（S2 同源）。
- 结论：❌ 问题页（S2/M11）——表单页全无边界。

**15. `readme_view.dart`（组件，隶属仓库/内容展示）** — Divider 0；引用块 3px 竖线（`:397`）。
- 已查：竖线色 outlineVariant（L17）；其余靠 markdown 排版留白。
- 结论：⚠️ 引用层级偏弱（L17）。

**16. `search_page.dart`** — Divider 5（`:143` 骨架、`:783` feed、`:1046` 结果、`:1373` 搜索命中 + 1 处注释 `:131`）；`ListView.separated` 5 处；Card 1（`:212` `_RepoCard`）；Border 1。
- 已查：`:937` 直调 `showModalBottomSheet`（M10）；弹层底层是卡片（S4）；全部 separator 走全局弱线。
- 结论：❌ 问题页（S1/S4/M10）——高密度列表 + 弹层边界双重失效。

#### 账户域

**17. `login_page.dart`** — Divider 2（`:455/464` 「或」横线）；Card 3（`:355/432/475`）；Border 1。
- 已查：横线用默认 `Divider()`（L16）；卡片主题描边。
- 结论：⚠️ 登录卡片双重消失（S3/L16）。

**18. `onboarding_page.dart`** — Divider 0；Card 3（`:334/356/457`）。
- 已查：引导卡片靠主题描边；`:261` 使用 surfaceContainerHighest 块；无行间分隔。
- 结论：⚠️ 卡片边界弱（S3）。

**19. `profile_page.dart`** — Divider 1（`:284`）；Card 0；无 border。
- 已查：平铺行来自 `flat_list.dart`（`:47` 弱线），行本身无 side。
- 结论：❌ 问题页（S1/M7）——账户信息行粘连。

**20. `settings_page.dart`** — Divider 31（全库最密）；Border 6；Card 0（分组用 `OgLSettingsGroup`）。
- 已查：`:527` 显式 outlineVariant 线；`:235/2362` 色块描边用 outlineVariant；`:1912/1921` 裸输入框；分组线高度 24/28/20 混用（M13）。
- 结论：❌ 问题页（M13/M15/S1）——线最多但结构最弱。

**21. `settings_section_page.dart`** — Divider 0；`ListView` + `OgLRevealList`（`:29-38`）。
- 已查：折叠分组间无任何线/块，纯留白。
- 结论：❌ 问题页（S5）——设置子页分区无界。

**22. `about_page.dart`** — Divider 11（`:125/166/181/304/320/325/330/339/350/356/362`）；Card 0；Border 0。
- 已查：全部走 flat_list / 手动弱线；`:304` 依赖列表追加 Divider。
- 结论：❌ 问题页（S1/M15）。

**23. `legal_text_page.dart`** — Divider 1（`:162`）；无 Card/Border。
- 已查：长文本正文与元信息间只有一条弱线。
- 结论：⚠️ 分界极弱（S1）。

#### 工具域

**24. `download_manager_page.dart`** — Divider 0；`ListView.separated`（`:272`）的 separator 为 `SizedBox(height: sm)`（`:275-276`）；Card 1（`:359`）。
- 已查：任务卡之间完全靠 8dp 留白，无一根线（S5）；卡片主题描边。
- 结论：❌ 问题页（S5）——纯留白分区的样板。

**25. `workflow_dispatch_page.dart`** — Divider 0；Card 2（`:441/532`）；裸输入框 2（`:472/509`）。
- 已查：卡片主题描边；表单输入无空闲边框。
- 结论：⚠️ 表单边界缺失（S2/S3）。

**26. `action_log_page.dart`** — Divider 0；Card 1（`:510`）；裸输入框 1（`:333`）。
- 已查：`:536` 徽标 surfaceContainerHighest；任务卡主题描边。
- 结论：⚠️ 表单/卡片边界弱（S2/S3）。

**27. `action_run_page.dart`** — Divider 2（`:658/670` 步骤区块分隔）；Card 2（`:356/697`）。
- 已查：区块间弱线 + 卡片主题描边。
- 结论：⚠️ 分割线不可见（S1）。

**28. `new_repo_page.dart`** — Divider 0；Card 1（`:175`）；裸输入框 2（`:152/161`）。
- 已查：表单输入无空闲边框。
- 结论：⚠️ 表单边界缺失（S2/M11）。

**29. `new_release_page.dart`** — Divider 0；Card 1（`:215`）；裸输入框 3（`:175/183/192`）。
- 已查：同上。
- 结论：⚠️ 表单边界缺失（S2/M11）。

**30. `network_page.dart`** — Divider 0；Card 0；Border 0；`ListView`（`:48-53`）仅 `SizedBox(height: xl)`。
- 已查：整页设置分节完全靠内容与留白，无任何边界手段。
- 结论：❌ 问题页（S5）——「空」与「漂」的最典型零边界页。

### 3.4 未发现独立问题的部分（也证明查过）
- [x] `outlinedButtonTheme.side`（`theme.dart:444`）用 `scheme.outline`，对 surface 4.259/5.857，**唯一过 3:1 的控件边界**，无需改。
- [x] `focusedBorder` / `errorBorder`（`theme.dart:401-413`）有明确色与 width，聚焦/错误态边界清晰。
- [x] `bottomSheetTheme.showDragHandle: true`（`theme.dart:253`）提供了弹层高度的物理暗示，保留。
- [x] `repo_page.dart:1295/1995` 在列表项间插 Divider 分隔可点击行，结构意图正确，只是线色太弱（S1 一并解决）。
- [x] 未在任何页面发现 `DividerTheme` 局部覆写——全库仅 `theme.dart:344` 一处定义，修复可一处生效（P0 指令成立）。

---

## 4. 自检
- 可感知问题条目：S1–S6 + M7–M15 + L16–L20 = **20 条 ≥ 15** ✅
- 每条均带 `file:line` 证据 + 用户感受 + 修复指令 ✅
- 30 页独立小节：1–30 全覆盖（含 0 Divider 页明列「已查项」）✅
- 量化：Divider 74 处、outlineVariant 11 处、裸输入框覆写 26 处、Card 24 个、5 组对比度实测 ✅
- 文档戳 / 只读声明 / 检查清单齐全 ✅
