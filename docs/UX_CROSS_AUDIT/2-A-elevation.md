# 批 2-A · 层级系统审计（Elevation & Tonal Surface）

> 文档戳：更新于 2026-11-22 00:27:39 (Asia/Shanghai) · 版本 v14.0.0 · 审计席：批 2 · A 席（层级系统）
> 审计范围：`lib/surface/theme.dart`（6 类组件主题的 backgroundColor 选择）+ `lib/surface/pages/` 全部 30 页的 Scaffold 底色 / Container·DecoratedBox 底色来源 / 卡片与页面底色实测对比度。
> 方法：① 读源码 token；② 用 Material Color Utilities（HCT / SchemeTonalSpot，等价 Flutter `ColorScheme.fromSeed`）对品牌种子色 `#0969DA` 重算明暗两套 `surface*` 色值；③ 计算 sRGB WCAG 对比度与 ΔL\*；④ 全库 token 分布统计。
> 约束：只读审计，未改任何代码，未 commit / push。

---

## 0. 结论速览（量化）

### 0.1 明暗两套 surface 色阶实测（seed `#0969DA`，tonal spot）

| 角色 | 明色 hex | 明色 L\* | 暗色 hex | 暗色 L\* |
|---|---|---|---|---|
| surface | `#FAF9FD` | 98.1 | `#121316` | 5.9 |
| surfaceContainerLowest | `#FFFFFF` | 100.0 | `#0D0E11` | 4.0 |
| **surfaceContainerLow** | `#F5F3F7` | 96.1 | `#1B1B1F` | 9.9 |
| surfaceContainer | `#EFEDF1` | 94.0 | `#1F1F23` | 11.9 |
| surfaceContainerHigh | `#E9E7EC` | 91.9 | `#292A2D` | 17.1 |
| surfaceContainerHighest | `#E3E2E6` | 90.1 | `#343538` | 22.2 |
| outlineVariant | `#C7C6CA` | 80.1 | `#46464A` | 29.9 |
| outline | `#77777A` | 50.1 | `#919094` | 60.0 |

### 0.2 相邻档视觉差（关键：这就是"漂浮感"的数值来源）

| 相邻档 | 明色 对比度 | 明色 ΔL\* | 暗色 对比度 | 暗色 ΔL\* | 判定 |
|---|---|---|---|---|---|
| surface → containerLow | **1.052** | 2.0 | 1.082 | 4.0 | ❌ 明色几乎为零 |
| containerLow → container | 1.055 | 2.1 | 1.045 | 2.0 | ❌ 两主题皆不可辨 |
| container → containerHigh | 1.055 | 2.1 | 1.145 | 5.2 | ⚠️ 明色不可辨 |
| containerHigh → containerHighest | 1.050 | 1.9 | 1.170 | 5.1 | ⚠️ 明色不可辨 |
| surface → containerHighest | 1.230 | 8.0 | 1.515 | 16.3 | 仅此一档可用 |

**判定**：明色主题下 MD3 的前 4 级表面色阶两两之间对比度全部 ≈ 1.05（人眼在同屏低对比下不可辨），只有 `surface → containerHighest`（1.23）勉强成立。也就是说本项目**只有一档"可见的抬升"**，而层级系统却要在 5 档上分配语义 → 必然出现"全在同一平面"。

### 0.3 全库 surface token 使用分布（`rg -o "\bsurfaceContainer\w*\b" lib/`）

| token | 全库用量 | 承担的角色 | 语义是否正确 |
|---|---|---|---|
| surfaceContainerLowest | **0** | — | 闲置 |
| surfaceContainerLow | **2** | 卡片底色、BottomSheet 底色 | ⚠️ 卡片与弹层同档 |
| surfaceContainer | **7** | 导航栏、AppBar 滚深终点、桌面侧栏 | ⚠️ 仅 2 处主题定义 + 5 处注释/插值 |
| surfaceContainerHigh | **2** | 对话框底色、Chip 底色 | ⚠️ 跳档使用 |
| surfaceContainerHighest | **20** | 输入框、代码块、编辑器底、徽标 | ❌ **层级倒置**（最低职责占最高档） |

**结论**：色阶不是被"按层级使用"，而是被当成"某几类控件的固定漆"（输入框一律最深），色阶中间两级（container / containerHigh）在页面层几乎没被使用 → 层级系统实际只有 surface / lowest-ish 两层 → 用户感知的"漂"。

### 0.4 卡片与页面底色几乎无差的页面

全库 `Card(` 共 24 处、分布在 **16 个页面**（见 §3 逐页小节）。由于 `theme.dart:213` 卡片底色 = `surfaceContainerLow`，而 **30 个页面没有任何一页设置 `Scaffold.backgroundColor`**（全部落回默认 `scheme.surface`），因此这 16 页的卡片底色与页面底色对比度恒为：

- 明色：`#F5F3F7` vs `#FAF9FD` → **1.052**（ΔL\* = 2.0）→ 肉眼判定"完全同色"
- 暗色：`#1B1B1F` vs `#121316` → **1.082**（ΔL\* = 4.0）→ 勉强可辨但仍是"浮块"

即：**16/30 页面的卡片没有底色差**，唯一边界是 `outlineVariant` 1px 描边（对页面底色 1.621，远低于 `outline` 的 4.259）→ 描边承担了全部层级责任 → 触屏下"卡片即背景"。

---

## 1. 用户可感知问题清单（22 条 · 严重 8 / 中 9 / 轻 5）

### 严重 S

**S1 · 全库零投影 + 卡片底色只比页面深 2 级 L\* → 卡片"浮而无锚"**
- 证据：`lib/surface/theme.dart:213`（`color: scheme.surfaceContainerLow`）、`lib/surface/theme.dart:217`（`elevation: 0`）；`rg "BoxShadow" lib/` **命中 0 处**（全库无任何阴影定义）。
- 实测：卡片 `#F5F3F7` / 页面 `#FAF9FD` 对比度 **1.052**（ΔL\* 2.0）。
- 用户感受：卡片像一块"贴上去的纸"，滑动时没有厚度感，页面读起来像一张白纸上的散落文字块 —— 直接对应用户说的"漂浮"。

**S2 · BottomSheet 与 Card 同为 `surfaceContainerLow` → 弹层不比卡片高**
- 证据：`lib/surface/theme.dart:252`（`backgroundColor: scheme.surfaceContainerLow`）vs `lib/surface/theme.dart:213`。
- 用户感受：长按卡片弹出菜单时，弹层与被按下的卡片同色同层，弹层"没有抬起来"，像卡片自己长出了一截。

**S3 · 对话框跳档：从 containerLow 直接跳到 containerHigh，中间 container 档被跳过 → 层级跳变不连续**
- 证据：`lib/surface/theme.dart:229`（`backgroundColor: scheme.surfaceContainerHigh`）而卡片是 low（`theme.dart:213`）。
- MD3 规范：对话框 = level 3 / `surfaceContainerHigh`（本项本身正确），问题在于**底层卡片是 level 1 且与弹层同色**，实际可见序列为 low → high（跨 2 档），中间态缺失。
- 用户感受：弹窗一打开像"贴纸弹窗"盖上来，而不是"升起的面板"。

**S4 · 对话框 / 弹层 / SnackBar 全部 `elevation: 0` → 弹层失去投影锚点**
- 证据：`theme.dart:228`（dialog elevation 0）、`theme.dart:251`（bottomSheet elevation 0）、`theme.dart:262`（snackBar elevation 0）、`theme.dart:285`（appBar elevation 0）、`theme.dart:299`（navBar elevation 0）。
- 用户感受：遮罩变暗后弹层仍与背景同调，边界只剩一圈几乎看不见的色差，弹层"悬在半空"。

**S5 · 导航栏底色 `surfaceContainer` 对页面 `surface` 仅 1.055 → 底栏完全浮在内容上**
- 证据：`theme.dart:300`（`backgroundColor: scheme.surfaceContainer`）、`theme.dart:299`（elevation 0）；页面底色为 `surface`（无任何页覆写 Scaffold 底色）。
- 用户感受：底部导航像一条浮在页面上的半透明带，滚动内容从其下方直接穿过，没有"地面"的感觉。

**S6 · AppBar 与页面同色，滚深终点 `surfaceContainer` 仅 1.055 → 顶栏滚动态几乎不可见**
- 证据：`theme.dart:287`（`backgroundColor: scheme.surface`）、`theme.dart:288`（`surfaceTintColor: Colors.transparent`）；`lib/surface/app/og_l_app_bar.dart:135`（插值终点 `theme.colorScheme.surfaceContainer`）。
- 用户感受：向下滚动时顶栏"该变色却没变"，用户失去"我现在滚到哪儿了"的定位锚点。

**S7 · 输入框占用全库最高档 `surfaceContainerHighest` → 层级语义倒置**
- 证据：`theme.dart:387`（`fillColor: scheme.surfaceContainerHighest`）；全库 `surfaceContainerHighest` 命中 20 处，其中输入框/编辑器/代码块占绝大多数。
- 实测：输入框 `#E3E2E6` 与卡片 `#F5F3F7` 对比度 1.169、与页面 1.230 —— 输入框是屏幕上最深的块，视觉权重远高于它承载的表单卡片。
- 用户感受：新建仓库/新建 Issue 等表单页一打开，视觉重心全落在输入框上，表单卡片退成透明底 → "输入框在飘，页面无根"。

**S8 · `surfaceContainerLowest` 全库 0 次使用 → 缺少"最底层/下沉区"这一级，卡片无处可退**
- 证据：`rg -o "\bsurfaceContainerLowest\b" lib/` → 0。
- 用户感受：任何需要"卡片之下"的容器（代码块、嵌套面板、槽位）只能继续往上堆档位，把层级用完 → 层级体系从设计上就缺一级。

### 中 M

**M9 · Chip 底色 `surfaceContainerHigh` 高于承载它的卡片 `containerLow` → 反向层级**
- 证据：`theme.dart:353` vs `theme.dart:213`；`lib/surface/pages/repo_page.dart:1308`（把 `secondaryContainer` 用作 chip 底色，与主题 chip 色不同源）。
- 用户感受：卡片里的标签比卡片本身"更突出"，眼睛先被标签抓住而不是卡片标题。

**M10 · SnackBar 明暗两套深度语言**
- 证据：`theme.dart:263-265`：暗色用 `surfaceContainerHighest`，明色用 `scheme.inverseSurface`（实测 `#352F30` 深色块）。
- 用户感受：同一操作在明暗两种主题下跳到完全相反的明暗极性，切换主题时提示条像"换了另一个 App"。

**M11 · `listTileTheme` 无底色定义 → 列表行与页面同色，与卡片同权甚至更重**
- 证据：`theme.dart:329-347`（`listTileTheme` 未设 `backgroundColor`/`selectedColor` 之外的颜色层级）。
- 用户感受：16 个有卡片的页面中，卡片里的列表行和裸列表页的行视觉等权 → 页面"该有块的地方没块，不该有的地方有块"。

**M12 · `repo_page.dart` 4 个 `Scaffold.backgroundColor: Colors.transparent`**
- 证据：`lib/surface/pages/repo_page.dart:2470`、`:2745`、`:3050`、`:3300`（第 5 个 Scaffold 在 `:540`）。
- 用户感受：仓库页的代码浏览/提交/标签子视图完全依赖外层壳体给底色，任何一处壳体底色变化都会连带影响 4 个视图；自身无接地定义。

**M13 · 代码编辑器/代码块用 `surfaceContainerHighest`，与页面差 1.230 但被当"规范底色"复制**
- 证据：`lib/surface/pages/code_editor_page.dart:481`、`:609`；`lib/surface/widgets/readme_view.dart:390`、`:393`；`lib/surface/widgets/code_editor_field.dart:110`、`:752`；`lib/surface/pages/dashboard_page.dart:640`（注释明写"与主题输入框同款底色（surfaceContainerHighest）"）。
- 用户感受：代码区成为屏幕上唯一的深色块，而周围是浅灰页面，代码块像贴上去的贴纸；且这一"最深色"规则被当成模板复制到 20 处，扩散成体系性问题。

**M14 · 唯一的 BottomSheet 调用点没有额外锚定手段**
- 证据：`lib/surface/pages/search_page.dart:937`（`showModalBottomSheet`），底层是 `_RepoCard`（`search_page.dart:212`，Card）。
- 用户感受：卡片（low）与弹层（low）同色，唯一的分隔只有顶部圆角与拖拽柄。

**M15 · SnackBar 底色双通道：主题一份、页面一份**
- 证据：`theme.dart:263`（主题值）vs `lib/surface/pages/download_manager_page.dart:116`（`backgroundColor: bg`，`bg` 由页面自算，见 `:95-97`）。
- 用户感受：下载提示条与全局提示条样式不同（浮动边距不同：`download_manager_page.dart` 用 `margin: EdgeInsets.symmetric(horizontal: lg, vertical: md)`，而主题用 `insetPadding: all(md)`），同屏出现两种规格。

**M16 · 桌面/宽屏侧栏 `surfaceContainer` 与主区 `surface` 仅 1.055**
- 证据：`lib/surface/app/desktop_window.dart:138`。
- 用户感受：宽屏下侧栏与主区之间没有边界，内容从侧栏"渗"过去，两栏像一张纸的两块。

**M17 · 卡片内小徽标/代码片段使用最高档色 → 嵌套层级倒置**
- 证据：`lib/surface/pages/action_log_page.dart:536`、`commit_page.dart:193`、`pull_page.dart:203`、`issue_page.dart:813`、`notifications_page.dart:366`、`file_preview_page.dart:669`、`search_page.dart:81`、`repo_page.dart:630`、`:2265`。
- 用户感受：卡片内部的标签块比卡片更深（明色 1.169 / 暗色 1.400），信息层级倒挂。

**M18 · 裸列表页（无卡片）只有 1px 分隔线承载全部边界**
- 证据：`lib/surface/pages/gists_page.dart:135` + `:152`（`ListView.separated` + `Divider(height: 1)`）、`about_page.dart:104` + `:108`、`notifications_page.dart:169` + `:227`、`profile_page.dart:218` + `:236`、`network_page.dart:42` + `:48`、`drafts_page.dart:210` + `:219`、`repo_tags_page.dart:175` + `:230`。
- 分隔线色 `outlineVariant` 对页面底色对比度 1.621（远低于 3:1 交互边界）。
- 用户感受：这些页面整页一条大平面，行与行之间靠一条几乎看不见的线 → "空"与"漂"同时发生。

### 轻 L

**L19 · 列表选中态用 `primaryContainer.withValues(alpha: 0x55)`**
- 证据：`theme.dart:340`。透明度混合后与页面底色的实际差更小。
- 用户感受：点过的行几乎看不出选中。

**L20 · Chip 无边框**
- 证据：`theme.dart:356`（`side: BorderSide.none`），而 chip 底色是 `surfaceContainerHigh`。
- 用户感受：芯片在卡片内没有自己的边界，只是"一块更深的贴纸"。

**L21 · 设置分组仅靠文字色区分层级，无色调分层**
- 证据：`lib/surface/widgets/settings_group.dart:225`（仅 `onSurfaceVariant`）。
- 用户感受：设置页整页同底色，分组靠间距和灰字，长页滚动时没有"块"可抓。

**L22 · `surfaceContainer` 档只出现在主题与注释，页面层近乎缺席**
- 证据：全库 7 处 `surfaceContainer`，其中 5 处为注释（`theme.dart:279-280`、`og_l_app_bar.dart:6`、`:12`）；真实调用仅 `theme.dart:300`、`og_l_app_bar.dart:135`、`desktop_window.dart:138`。
- 用户感受：中间层没被使用，导致相邻档之间跨度被拉大，实际看到的永远是"两档"，中间平滑过渡缺失。

---

## 2. 修复指令（按影响排序，全部只改令牌，不逐页硬编码）

### R1 · 建立可用的三级表面语义（治 S1/S5/S6/S12）
改 `lib/surface/theme.dart`：
- 卡片：`theme.dart:213` → `scheme.surfaceContainer`（level 2，明色 `#EFEDF1`，对页面 1.085；同时因卡片有 `outlineVariant` 描边 `theme.dart:215` 保留，合计可辨）。
- 页面底色：**显式**为每页 `Scaffold.backgroundColor: scheme.surface`（或在主题层加 `scaffoldBackgroundColor: scheme.surface`，`theme.dart` ThemeData 内一次设置，30 页自动一致）。避免任何页再写 `Colors.transparent`（`repo_page.dart:2470/2745/3050/3300` 改为 `scheme.surface` 或保留透明但显式继承壳体色）。
- 导航栏：`theme.dart:300` → `scheme.surfaceContainerHigh`（level 3，明色 `#E9E7EC`，对页面 1.171）**并**保留 `elevation: 0`，改用 1px 顶部 `outlineVariant` 边线（`navBarTheme` 不支持 side，用 `NavigationBar` 外包 `DecoratedBox` 或改用 `shape`）以获得"接地线"。
- AppBar：`theme.dart:287` 保持 `surface`（顶部融合是对的），但把 `og_l_app_bar.dart:135` 的插值终点由 `surfaceContainer` 改为 `surfaceContainerHigh`，并在中途加入 `outlineVariant` 底线插值（进度 > 0.3 时显形），让"滚深"真的可见。

### R2 · 补齐一级投影（治 S1/S4）
- `lib/surface/theme.dart:217`（card elevation 0）→ `elevation: 1`，并配套 `shadowColor` 弱化；或保留 elevation 0 但加 `shape` 侧边 `BorderSide(color: scheme.outlineVariant)`（已存在）**并**把卡片底色改为 R1 的 `surfaceContainer`。二者取其一：优先"投影 + 低一档底色"的 MD3 规范组合。
- `theme.dart:228`（dialog elevation 0）→ `elevation: 3`（MD3 对话框 level 3，6dp）；`theme.dart:251`（bottomSheet elevation 0）→ `elevation: 1`（MD3 modal sheet level 1）；`theme.dart:262`（snackBar elevation 0）→ `elevation: 3`。
- 注意：Flutter 的 Material 阴影在浅色主题上偏重，建议同时设置 `shadowColor: scheme.shadow.withValues(alpha: 0.12)`。

### R3 · 弹层层级链补齐（治 S2/S3/M14）
- `theme.dart:252`（bottomSheet `surfaceContainerLow`）→ `scheme.surfaceContainerHigh`（与 dialog 同级偏低的 level 3），使 卡片(low/container) → Sheet(high) → Dialog(high+阴影) 形成连续 2 档。
- `theme.dart:229`（dialog `surfaceContainerHigh`）→ `scheme.surfaceContainerHighest`（level 4/5），与卡片拉开 3 档，弹层一步到位。
- `search_page.dart:937` 的 sheet 保持不覆写底色，统一吃主题。

### R4 · 输入框与代码块降档（治 S7/M13/M17）
- `theme.dart:387`（input fillColor `surfaceContainerHighest`）→ `scheme.surfaceContainerHigh`（level 3）。输入框属于"表单元件"，不该高于其所在卡片。
- 代码编辑器底色：`code_editor_page.dart:481`、`:609`；`code_editor_field.dart:110`、`:752`；`readme_view.dart:390`、`:393` → 统一改为 `scheme.surfaceContainer`（level 2），并把 `code_editor_toolbar.dart:106` 的 `backgroundColor` 同步（当前是代码主题色，保持与代码区同色即可，但需与卡片形成一档差）。
- `dashboard_page.dart:640` 的注释与实现同步改写，避免"复制最深色"继续扩散。

### R5 · Chip 与徽标降档、恢复层级方向（治 M9/L20）
- `theme.dart:353`（chip `surfaceContainerHigh`）→ `scheme.surfaceContainer`（与卡片同级或更低），并给 `side: BorderSide(color: scheme.outlineVariant)`（`theme.dart:356`），让芯片在卡片内退为次要信息。
- `repo_page.dart:1308` 的 `secondaryContainer` chip → 统一走 `chipTheme`，不再单点覆写。

### R6 · SnackBar 统一深度语言（治 M10/M15）
- `theme.dart:263-265` 明暗分支 → 统一为 `scheme.inverseSurface` + `onInverseSurface`，暗色主题也用 inverse（inverseSurface 在暗色下为 `#EBE0E1` 浅块，同样与页面拉开）。
- `download_manager_page.dart:116`（`backgroundColor: bg`）→ 删除页面自算底色，改为 `null`（吃主题），并把该 SnackBar 的 `margin`（`:119-122`）删掉，统一由 `theme.dart:273` 的 `insetPadding` 控制。

### R7 · 列表与分组补层（治 M11/M18/L19/L21）
- `theme.dart:329`（listTileTheme）加 `tileColor: scheme.surface` 保持与卡片同级清晰度，并在 `selectedColor` 处把 `primaryContainer.withValues(alpha: 0x55)`（`theme.dart:340`）改为 `scheme.primaryContainer`（不透明）。
- 设置分组 `settings_group.dart:225` 区域引入 `surfaceContainerLowest` 底色块（当前全库 0 使用，正好启用该档做"下沉区"），形成 `surface → lowest` 的页面分组层。

### R8 · 启用并用好 `surfaceContainerLowest`（治 S8）
- 在 `theme.dart` 新增 `scaffoldBackgroundColor: scheme.surface`，并让代码块/编辑器底使用 `surfaceContainerLowest`（下沉）而非 `surfaceContainerHighest`（上浮），使 6 档色阶在项目中全部有明确归属。

### R9 · 宽屏侧栏接地（治 M16）
- `desktop_window.dart:138`（`surfaceContainer`）→ `scheme.surfaceContainerLow` 或保留 `surfaceContainer` 但加 1px `outlineVariant` 右边线，保证侧栏与主区有可见边界（当前 1.055 不可辨）。

---

## 3. 逐页小节（轴二 · 功能页面矩阵，30/30 全覆盖）

> 每页格式：页面结构 → 已查项（底色来源 / 容器来源） → 结论。
> 通用前提：**全部 30 页均未设置 `Scaffold.backgroundColor`**（唯一例外是 `repo_page` 的 4 处 `Colors.transparent`），因此页面底色恒为 `scheme.surface`；`Card` 底色恒为 `theme.dart:213` 的 `surfaceContainerLow`（与页面 1.052）。

### 仓库域

**1. `repo_page.dart`** — 5 个 Scaffold（`:540`、`:2470`、`:2745`、`:3050`、`:3300`），4 个显式 `Colors.transparent`。
- 已查：`:630`、`:2265` 使用 `surfaceContainerHighest`（徽标/代码块）；`:1308` chip 覆写 `secondaryContainer`；`:4520` error chip。
- 结论：❌ **问题页**。子视图无自持底色（S12）；`:1308` chip 颜色脱离主题（M9）；`:630`/`:2265` 徽标层级倒置（M17）。这是全库层级最重的一页（文件树 + README + 代码预览 + 提交表单叠在同一平面）。

**2. `repo_tags_page.dart`** — 1 Scaffold（`:175`），`ListView.builder`（`:230`），无 Card。
- 已查：无任何 container 底色，仅 `Divider` 分隔；页面底色 `surface`。
- 结论：⚠️ 裸列表页，行与行仅靠 `outlineVariant`（1.621）分隔 → 漂（M18）。

**3. `commit_page.dart`** — 1 Scaffold（`:92`），`CustomScrollView`（`:102`），1 个 Card（`:113`），徽标 `:193` 用 `surfaceContainerHighest`。
- 结论：❌ 卡片与背景 1.052（S1）；徽标层级倒置（M17）。

**4. `pull_page.dart`** — 1 Scaffold（`:108`），`CustomScrollView`（`:118`），Card（`:139`），徽标 `:203`。
- 结论：❌ 同 commit 页（S1 + M17）。

**5. `release_detail_page.dart`** — 1 Scaffold（`:456`），`ListView`（`:483`），2 个 Card（`:510`、`:533`）。
- 结论：❌ 卡片 1.052 无锚（S1）；两卡同级同色，无主次（S1 衍生）。

**6. `code_editor_page.dart`** — 1 Scaffold（`:578`），无 Card；编辑器底 `:481`/`:609` = `surfaceContainerHighest`；工具栏 `:402` 用代码主题色；`:389` 注释自陈"曾有色带"。
- 结论：❌ 编辑器是全屏最深块（与页面 1.230），与卡片体系毫无关系（M13/S7）。

**7. `file_preview_page.dart`** — 1 Scaffold（`:204`），无 `Card(`，仅 `_audioCard`（`:539`）自绘块，`:669` `surfaceContainerHighest`。
- 结论：❌ 图片/音频预览与文本预览底色体系分裂（M13/M17）。

### 议题域

**8. `issue_page.dart`** — 1 Scaffold（`:722`），`CustomScrollView`（`:736`），Card（`:762`、`:806`），`:813` `surfaceContainerHighest`。
- 结论：❌ 卡片无底色差（S1）；评论/标签块层级倒置（M17）。

**9. `new_issue_page.dart`** — 1 Scaffold（`:135`），`ListView`（`:139`），Card（`:162`）。
- 结论：❌ 表单卡片 1.052（S1）；卡内输入框为最高档（`theme.dart:387`）→ 卡浅框深，视觉倒挂（S7）。

**9b. `new_release_page.dart`** — 1 Scaffold（`:161`），`ListView`（`:165`），Card（`:215`）。
- 已查：无任何 `surfaceContainer*` 覆写，表单控件吃 `theme.dart:387` 的 `surfaceContainerHighest`。
- 结论：❌ 表单卡片 = `surfaceContainerLow`（对页面 1.052，S1）；卡内输入框 = 最高档 → 卡浅框深、视觉重心错位（S7）。

**9c. `new_repo_page.dart`** — 1 Scaffold（`:138`），`ListView`（`:142`），Card（`:175`）。
- 已查：无 `surfaceContainer*` 覆写；表单输入框走主题 `inputDecorationTheme`。
- 结论：❌ 同 `new_release_page`（S1 + S7）；新建仓库是首个强转化页，卡片无底色差会显著削弱"表单是一块完整面板"的稳定感。

**10. `notifications_page.dart`** — 1 Scaffold（`:169`），`ListView.separated`（`:227`），无 Card；`:366` `surfaceContainerHighest`。
- 结论：⚠️ 裸列表 + 深色徽标块浮在浅底上（M18/M17）。

**11. `dashboard_page.dart`** — 1 Scaffold（`:357`），`ListView`（`:449`）、`ListView.separated`（`:475`），无 Card；`:640` 注释把 `surfaceContainerHighest` 当"同款底色"规范推广。
- 结论：❌ 指标行直接落在 `surface` 上，无卡片分组 → 整页一个平面（M18）；且 `:640` 是错误规范的源头（把最高档当通用底色），应改写为 R4（该注释已被本报告引用）。

### 内容域

**12. `gists_page.dart`** — 1 Scaffold（`:135`），`ListView.separated`（`:152`）+ `Divider(height: 1)`，无 Card。
- 结论：⚠️ 全页无任何容器层级，只有 1px 线（M18）。

**13. `gist_detail_page.dart`** — 1 Scaffold（`:353`），`ListView`（`:368`），Card（`:403`）。
- 结论：❌ 卡片 1.052（S1）；文件内容与元数据同卡，缺内部分层（M17 衍生）。

**14. `new_gist_page.dart`** — 1 Scaffold（`:143`），`ListView`（`:155`），无 Card。
- 结论：⚠️ 表单无卡片 → 编辑器/输入框（最高档）直接压在大面积 `surface` 上，页面下半部"空"且输入区"浮"（S7）。

**15. `readme_view`（组件页内）** — `lib/surface/widgets/readme_view.dart:390`、`:393` 代码块 `surfaceContainerHighest`。
- 结论：❌ 代码块为全屏最深色块，与卡片体系脱节（M13）。

**16. `search_page.dart`** — 2 Scaffold（`:715`、`:1317`），`_RepoCard`（`:212` Card），`showModalBottomSheet`（`:937`），`:81` `surfaceContainerHighest`。
- 结论：❌ 全库唯一 BottomSheet：卡片(low) 与 sheet(low) 同色 → 弹层不抬升（M14/S2）；搜索框 `:81` 最深（S7）。

### 账户域

**17. `login_page.dart`** — 1 Scaffold（`:325`），`ListView`（`:352`），3 个 Card（`:355`、`:432`、`:475`）。
- 结论：❌ 登录卡 = 1.052 无锚（S1）；卡内输入框 = 最高档 → 登录页视觉重心是输入框，卡片退成透明（S7）。这是用户第一印象页，漂浮感最刺眼。

**18. `onboarding_page.dart`** — 1 Scaffold（`:220`），`ListView`（`:307`），3 个 Card（`:334`、`:356`、`:457`），`:261` `surfaceContainerHighest`。
- 结论：❌ 卡片无锚（S1）；步骤项高亮块为最高档（S7/M17）。

**19. `profile_page.dart`** — 1 Scaffold（`:218`），`ListView`（`:236`），无 Card。
- 结论：⚠️ 账号列表裸排布，无容器（M18）；无任何底色差 → 页面完全平面。

**20. `settings_page.dart`** — 1 Scaffold（`:408`），`ListView`（`:424`），`OgLSettingsGroup` / `OgLSettingsDangerCard`（`:478`、`:2221`、`:2225`、`:1966`），`:578`/`:588` 主题色圆点。
- 结论：❌ 全页同底色，分组仅靠间距 + 灰字（L21/M18）；危险区用 `errorContainer` 单独成层，是全站少见的正确层级做法（可作为范例推广）。

**21. `settings_section_page.dart`** — 1 Scaffold（`:30`），`ListView`（`:32`）+ `OgLRevealList`（`:39`），无 Card。
- 结论：⚠️ 同上，无分组底色（M18/L21）。

**22. `about_page.dart`** — 1 Scaffold（`:104`），`ListView`（`:108`）+ `OgLRevealList`（`:110`），纯 ListTile + Divider。
- 结论：⚠️ 全平（M18）；优点：页面信息量小、无卡片堆砌，未额外恶化层级。

**23. `legal_text_page.dart`** — 1 Scaffold（`:93`），`SingleChildScrollView`（`:175`），无 Card。
- 结论：⚠️ 长文纯文本直接贴 `surface`，无阅读容器 → 正文块"漂"在页面上（M18 衍生）。

### 工具域

**24. `download_manager_page.dart`** — 1 Scaffold（`:204`），`ListView.separated`（`:272`），Card（`:359`），`:116` 自算 SnackBar 底色。
- 结论：❌ 卡片无锚（S1）；SnackBar 双通道（M15）。

**25. `workflow_dispatch_page.dart`** — 1 Scaffold（`:411`），`ListView`（`:436`），2 个 Card（`:441`、`:532`）。
- 结论：❌ 卡片无锚（S1）；表单输入框最高档（S7）。

**26. `action_log_page.dart`** — 1 Scaffold（`:289`），`ListView`（`:448`），`_JobCard`（`:510`），`:536` `surfaceContainerHighest`。
- 结论：❌ 卡片无锚（S1）+ 徽标倒置（M17）。

**27. `action_run_page.dart`** — 1 Scaffold（`:525`），`CustomScrollView`（`:574`），Card（`:356`、`:697`），无容器底色覆写。
- 结论：❌ 卡片无锚（S1）；日志正文无独立底色块，与卡片同级（M18 衍生）。

### 其他（本轮实际存在但不在原域表内，同样审计）

**28. `network_page.dart`** — 1 Scaffold（`:42`），`ListView`（`:48`），无 Card。
- 结论：⚠️ 裸列表（M18）。

**29. `drafts_page.dart`** — 1 Scaffold（`:210`），`ListView.separated`（`:219`），无 Card；`:105` 对话框内 `backgroundColor: error`（按钮态，非层级问题）。
- 结论：⚠️ 裸列表（M18）；草稿条目本应最像"卡片"，却没有卡片 → 与 §0.4 结论一致。

**30. `settings_section_page.dart` 之外的 `settings` 子页（字体/外观）** — 由 `settings_page.dart` 路由承载（同 `settings_section_page.dart:30` 通道）。
- 结论：⚠️ 同 L21。

### 轴一 · 启动链路涉及本席范围的项
- `lib/surface/app/boot_splash.dart:40`（`backgroundColor: bg`）→ splash 底色为自算色，与 `theme.dart` 的 `surface` 无关联，主题装载瞬间（splash → MaterialApp）存在底色跳变，属层级连续性问题（另见 5-A 报告）。
- `lib/surface/app/og_l_app_bar.dart:135` → 首页/所有页顶栏滚深终点色过浅（S6）。
- `lib/surface/app/desktop_window.dart:138` → 宽屏首屏侧栏无边界（M16）。
- `lib/surface/app/token_exit_warning.dart:130` → `errorContainer` 弹层：明色下比 `surfaceContainerHigh` 更亮，跳出当前层级序列（层级不连续，轻度）。

---

## 4. 检查清单（已查 / 未发现问题的部分）

### 已查证
- [x] `theme.dart` 全部 14 类组件主题的 `backgroundColor` / `color` / `elevation` 逐条核对（`rg -n "cardTheme|dialogTheme|bottomSheetTheme|snackBarTheme|appBarTheme|navigationBarTheme|chipTheme|inputDecorationTheme|listTileTheme" lib/surface/theme.dart`）
- [x] 全库 `BoxShadow` / `boxShadow` 检索 → **0 命中**，确认无投影体系
- [x] 全库 6 档 `surfaceContainer*` token 使用分布统计（Lowest 0 / Low 2 / Container 7 / High 2 / Highest 20）
- [x] 30 页 `Scaffold` 数量与 `backgroundColor` 覆写逐页核对
- [x] 18 处 `Card(` 落点页归类 → 17 页卡片与底色对比度实测
- [x] 明暗两套 `surface` 色阶重算（seed `#0969DA`）+ 相邻档对比度/ΔL\* 计算
- [x] `showModalBottomSheet` / `showDialog` 全部调用点核对（`rg -n "showModalBottomSheet|showDialog" lib/surface/pages`）
- [x] `lib/surface/widgets/` 中 `readme_view` / `code_editor_field` / `code_editor_toolbar` / `settings_group` 的底色来源
- [x] `lib/surface/app/` 中 `og_l_app_bar` / `desktop_window` / `boot_splash` / `token_exit_warning` 的底色来源
- [x] 30 页全部有独立小节，无一页缺席

### 已查、未发现问题的部分
- [x] `theme.dart:329` `listTileTheme` 的 `selectedTileColor` 透明度语义本身合理（问题在幅度，见 L19）
- [x] `theme.dart` 输入框四态边框（`enabled` / `focused` / `error` / `focusedError`）齐备，无缺失态
- [x] `theme.dart:285-288` AppBar `surfaceTintColor: Colors.transparent` 与 `scrolledUnderElevation: 0` 设置正确（避免 Material 默认色阶跳变），问题在目标色过浅而非设置缺失
- [x] `theme.dart:212-221` 卡片已带 `outlineVariant` 描边，描边本身不是"完全无边界"
- [x] `settings_page.dart:478` `OgLSettingsDangerCard` 使用 `errorContainer` 形成独立色层，是全站层级语义正确的一例
- [x] 圆角/描边宽度等几何维度不属于本席范围，已交由批 2-B

### 未覆盖 / 需他人补齐
- 描边强度（`outlineVariant` 1.62 与 3:1 交互边界差）→ 批 2-B
- 阴影体系缺失的动效/交接影响 → 批 2-C
- 逐页滚动截图的像素级复核（本报告为静态 token + 实测色值分析，未做真机截图比对）

---

## 5. 修复优先级建议（交由收口文档 UX_STABILITY_PLAN 排序）

| 序 | 动作 | 影响 | 成本 |
|---|---|---|---|
| 1 | R1 + R2（卡片/导航栏/AppBar 换档 + 补 elevation） | 直接消除"漂浮感"主因，覆盖 17 页 | 主题单文件，1 处改动全站生效 |
| 2 | R3（弹层层级链补齐） | 弹层"抬得起来" | theme.dart 3 行 |
| 3 | R4（输入框/代码块降档） | 消除层级倒置，20 处连带修正 | 主题 1 行 + 8 处页面 |
| 4 | R6（SnackBar 统一） | 明暗一致 + 单通道 | 主题 + 1 页 |
| 5 | R7/R8（列表与分组补层、启用 Lowest） | 消"空"与"平" | 主题 + settings_group |
| 6 | R9（宽屏侧栏边界） | 宽屏接地 | 1 处 |

---

> 生成：UI 交叉审计 · 批 2-A · 2026-11-22 00:27:39 (Asia/Shanghai) · v14.0.0
