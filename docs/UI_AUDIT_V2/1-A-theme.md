# UI 深度复审 V2 · 批 1-A · 主题层复审

> **文档戳 / Doc Stamp**
> - 更新时间：**2026-11-24 22:30:01 (Asia/Shanghai)**
> - 复审对象版本：**v15.0.0**（HEAD `46981c0`；主题层提交 `531bd8a`「第一批主题层根治」）
> - 仓库：`/root/OhGithubLost`；**只读审计**：未改代码、未 commit / push
> - 规范依据：`material-3/SKILL.md` Color / Typography / Shape / Elevation / Theming + `sota-frontend-design/rules/01-typography-and-color.md` §4/§4b/§5/§6/§6b
> - 证据纪律：每条 `file:line` 均可 `rg -n` 复现；色值由 `python3 tool/contrast_audit.py` 实跑 + `python3 /tmp/ogl_theme_contrast.py`（解析 `theme.dart` 源码取色算 WCAG）复算
> - 基线色阶引自 `docs/UX_CROSS_AUDIT/2-A-elevation.md:14-22` 的 `fromSeed(#0969DA)` 实测值；动态配色（Material You）下具体数值随壁纸变化，本报告的结论按该基线评估

---

## 0. 结论速览

**最严重两条**：**T-06** 语义色 `success` 在暗色 diff 正文上 2.39:1（P1）；**T-08** 40 处裸 `OutlineInputBorder()` 吃掉新输入框边框（P1）。

| 维度 | 结果 |
|---|---|
| 旧确证闭环（7 条） | **已修 5 / 修法有问题 2 / 完全未修 0**（B-02 的调用点清理未闭环，见 §1） |
| v15 回归发现 | **5 条**（T-01～T-05，见 §2；T-06/T-09 归入 §3 新发现统计） |
| 分级统计 | **13 编号：P1 × 6 / P2 × 7**（v15 回归 T-01～T-05 + 真新增 T-06～T-13，见 §2/§3） |
| 闭环结论 | B-02 主题默认值已设但 40 处调用点未清、G-07 浅色 60% 仅 4.12–4.44:1 → 2 条修法有问题 |
| 用户满意度判词 | 「像工具」的方向已建立（边界、卡片锚点、导航选中态），但**明暗两套不同步**与**令牌—用法定居差**仍在破坏可预期性（见 §4） |

---

## 1. 闭环核对（旧确证 · 主题层归属逐条判）

> 编号以 `docs/UX_STABILITY_PLAN.md:54-113` 的跨席确证表为准（同名前缀在不同席位文档中复用，本报告只按计划表口径判定）。

| 编号 | 判定 | 证据（file:line）与理由 |
|---|---|---|
| **B-01** 全局描边失效（1.30–1.98:1） | **已修（主题层内）** | 新 token `lightOutlineVariantStrong #6B6A71` / `dark #7F7E85`（`lib/surface/theme.dart:116-117`），并挂载 divider / card side / chip side / segmented side / sheet dragHandle（`:240/279/388/397/420`）。实算明暗对五级 surface **5.10→4.15 / 4.62→3.05，全部 ≥3:1**（§2.1）。页面层仍有 4 处遗留裸 `outlineVariant`，见 T-04。 |
| **B-02** 输入框空闲态无边界 | **修法有问题** | 主题层已给 `border` / `enabledBorder` 设 `BorderSide(color: outlineStrong)`（`theme.dart:434-441`），但**40 处 `border: OutlineInputBorder()` 裸覆写**未删（如 `new_repo_page.dart:152/161`、`new_issue_page.dart:147/156`、`repo_page.dart:712/1473/1490/1790/2506/3874/4323/4442/4530`），另有 `code_editor_field.dart:791/849` 的 `InputBorder.none`。裸 `OutlineInputBorder()` 默认 `BorderSide(color: Color(0), width: 1)`（透明描边），现代 Flutter 下 `enabledBorder` 被 `border` 覆写吃掉 → **表单页仍然无框**。计划表 `:73` 的「删除 26 处覆写」实际只新增了主题默认值，未清调用点。判定：主题修法正确但**未闭环**。 |
| **G-01** 卡片无接地 | **已修（主题层内）** | `cardTheme.color = surfaceContainer`、`elevation = 1`、`side = outlineStrong`（`theme.dart:237-248`），`scaffoldBackgroundColor = scheme.surface`、`shadowColor = shadow12`（`:217-219`）。色阶差按基线仅 1.11:1（明）/1.13:1（暗），但**1px 强描边 + 12% 投影**共同承担锚点，投影本身轻（T-02 仅提示重复强调），不再「浮而无锚」。页面层 4 处 `backgroundColor: Colors.transparent`（`repo_page.dart:2471/2764/3069/3319`）会绕过 scaffold 底色，归布局席。 |
| **G-03** 弹层层级跳变 | **已修（主题层内）** | dialog `surfaceContainerHighest` + elevation 3（`theme.dart:251-254`）、sheet `surfaceContainerHigh` + elevation 1（`:273-277`）、snackbar elevation 3（`:287`），层级顺序 card < sheet < dialog 已恢复。但**弹层边框缺失 + 遮罩未设**（T-05）与**暗色 dialog→sheet 相邻只差 1.17:1**（T-02），故只判「主题层已修，视觉层级仍偏弱」。 |
| **G-04** 输入框底色过深 | **已修** | `fillColor: surfaceContainerHigh`（`theme.dart:428`），与卡片 `surfaceContainer` 同档边界而非跨两档。页面 14 处 `surfaceContainerHighest` 仍在（`search_page.dart:82`、`code_editor_field.dart:110/752`、`readme_view.dart:390/393` 等），属各席页面层收编项，不归本席判失败。 |
| **G-07** 禁用色过淡（onSurface@38%） | **修法有问题** | 四类按钮均设 `disabledForegroundColor: onSurface@60%`（`theme.dart:463/476/489/500`），暗色通过（5.96 / 5.15 / 4.64:1）；但计划表 `:109` 预期「浅色约 4.6:1」**未达成**——按 `fromSeed` 实测 `onSurface #1B1B1F` 混 60% 对 surface 为 **4.44:1**，对 `surfaceContainerHigh` 为 **4.20:1**，对 `surfaceContainerHighest` 为 **4.12:1**；禁用文字通常豁免，但禁用按钮若承载「需读懂的标签」应达 4.5（规则 01 §5）。达 4.5 的最小 alpha 为 61%（surface）/63%（containerHigh）。另 `disabledBackgroundColor` 仅 FilledButton 设（`:464`），OutlinedButton/TextButton 的禁用底色仍随容器，同页禁用态语言不统一。 |
| **B-08** 选中态不可见 | **已修** | `listTileTheme.selectedTileColor = scheme.primaryContainer` 由 55% 透明改不透明（`theme.dart:381`）；`navigationBarTheme` 选中药丸 `primaryContainer` + `onPrimaryContainer`（`:331-349`）；新增 `navigationRailTheme` 同语言（`:358-367`）。三处选中态现在同 token。注意 `settings_page.dart:235` 的主题色选择框仍用 `outlineVariant` 1px 弱线（T-04），属 ColorPicker 控件层而非 ListTile 选中态。 |

**闭环口径说明**：上表 7 条逐条判定为 **5 已修 / 2 修法有问题 / 0 完全未修**。B-02 的主题默认值部分已修，但计划表 `:73` 要求的「删除 26 处裸 border 覆写」未执行，实测残留 40 处（T-08），故判「修法有问题（未闭环）」；G-07 同理（浅色 60% 仅 4.12–4.44:1）。收口表请按本行统计填写。

---

## 2. v15 新增机制的回归检查

### 2.1 outlineVariantStrong — 达标，但**比计划草案更深两级**

`python3 tool/contrast_audit.py` 实跑：`语义色对比度审计：0 处问题 (exit=0)`；`python3 /tmp/ogl_theme_contrast.py` 解析 `theme.dart:116-117` 色值复算：

| 底色 | 明 `#6B6A71` | 暗 `#7F7E85` | 判定 |
|---|---|---|---|
| surface | 5.10:1 | 4.62:1 | ✅ |
| surfaceContainerLow | 4.85:1 | 4.27:1 | ✅ |
| surfaceContainer | 4.60:1 | 4.09:1 | ✅ |
| surfaceContainerHigh | 4.36:1 | 3.57:1 | ✅ |
| surfaceContainerHighest | 4.15:1 | **3.05:1** | ✅（贴线） |

计划表 `:66` / `:453` 建议明 `#94939A` / 暗 `#707075`，实装明 `#6B6A71` / 暗 `#7F7E85`——**比建议更深**，换来达标但付出两个代价：

- **P2 · T-01 边界过重**：暗色描边对最弱底（containerHighest）仅 3.05:1 贴线；明色描边对 surface 达 5.10:1，接近 `outline`（4.26:1）的「重要边界」强度。MD3 中 `outline-variant` 的职责是装饰性分隔，强到 4–5:1 后**所有 74 条分隔线都变成同等强调**，信息层级被压平（`theme.dart:385-389` divider 全库生效）。修复指令：把 divider 单独用 `outlineVariant`（原 1.3–2.0:1）或新设 `outlineVariantMedium ≈3.2:1`，卡片/输入框/Chip/分段保留 strong；强描边 min 3 的口径只需对容器边界成立。
- **P1 · T-02 明暗边缘照顾不对称**：暗色 `outlineStrong #7F7E85` 在 `surfaceContainerHighest` 上 3.05:1，贴 WCAG 下限；若 Material You 动态配色使该容器再抬高 2 个 L\* 即跌破 3:1。修复：`darkOutlineVariantStrong` 上调到 `#8A8990`（对最高档约 3.5:1），或 `outlineVariantStrong` 对动态 scheme 走运行时计算而非硬编码。

### 2.2 卡片 surfaceContainer + elevation 1 + 12% 投影 — 没有「过重」，但 tonal 与 shadow 重复计价

`theme.dart:213/217-219/237-242`：投影 `shadow.withValues(alpha:0.12)`，elevation 1 对应 M3 level 1（1dp），投影量级合规；未发现截图式「重投影」风险。**但**：明色 `surface → surfaceContainer` 1.11:1（几乎同色，见基线表），于是**层级责任全部压在描边和投影上**；暗色 1.13:1 同理。MD3 规范 elevation 主靠 tonal（+5% primary），此处 tonal 差太小 + 额外 12% 阴影 = 两套深度语言叠加。判 **P2 · T-03「接地靠线不靠阶」**：建议把卡片底改为 `surfaceContainerLow`~`surfaceContainer` 之间按明暗分别取值（明色需要 `#EFEDF1`→更接近 `#E9E7EC` 才达 1.15:1，暗色 `#1F1F23` 可保留），或干脆接受「强描边即锚点」并去掉 elevation 1 的重复阴影。

### 2.3 navRailTheme — 与 bar **不完全一致**，新增 rail 未真正接管

`theme.dart:358-367` 的 rail 与 bar（`:324-353`）在**背景/选中药丸/图标/标签色彩**四项同语言 ✅。但：

- **P1 · T-04 Rail 语言不一致**：`client_shell.dart:371-402` 调 `NavigationRail` 时显式传 `labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all`，**覆盖 theme 的 `labelType: all`**，1200dp+ 宽屏下标签全部消失，而 `NavigationBar` 是 `labelBehavior: alwaysShow`（`theme.dart:352`）——同一角色组件在两断点下不同步；`client_shell.dart:401` 仍保留 `VerticalDivider(width:1)`，轨面底色 `surfaceContainerLow` 本应取代这根 1px 线（计划表 `:145` 明确要求删除），且该线使用默认 `outlineVariant` ≈ 1.9:1（暗）——**新 rail 的「接地」被旧弱线稀释**。另 `client_shell.dart:371-402` 无 `SafeArea(top: true)`、无 `groupAlignment`，顶图标仍顶状态栏、目的地仍顶对齐，旧 G-08 未闭环。修复指令照计划表 `:146-149`。
- **P2 · T-05 导航选中态动态配色下未验证**：rail/bar 的 `indicatorColor = primaryContainer`、`onPrimaryContainer` 在动态色下随壁纸生成，选中标签/图标 4.5:1 未做运行期门禁（`tool/contrast_audit.py` 只审计语义色，不含 ColorScheme 全矩阵）。建议把 `contrast_audit.py` 的 pairs 扩到 `onPrimaryContainer/primaryContainer` 与 `onSurfaceVariant/surfaceContainerLow`。

### 2.4 disabled 60% — 暗色通过、浅色差 0.06–0.38

见 §1 G-07 行与 §2 复算表：浅色 **4.44 / 4.20 / 4.12:1**，均低于 4.5。修复指令：`theme.dart:463/476/489/500` 的 `0.60` → 亮度相关 `brightness == dark ? 0.60 : 0.64`（按 `containerHighest` 底需 0.64 才稳过）；同时给 OutlinedButton/TextButton 补与 FilledButton 同族的 disabledBackgroundColor 策略。

### 2.5 scrolledUnderElevation=2 — 主题层生效，但两套顶栏色语言**互相打架**

`theme.dart:313` + `og_l_app_bar.dart:150`：两者同为 2 ✅。但 `theme.dart:314` 的 `backgroundColor = surfaceContainerLow` 与 `og_l_app_bar.dart:138-142` 的插值起点 `surface`（未滚动时）**不是同一个颜色**：`ValueListenableBuilder` 的 `backgroundColor: merged` 直接覆写 theme 值 → 14 页 `OgLAppBar` 顶部是 `surface`，其余页原生 `AppBar` 顶部是 `surfaceContainerLow`（1.05:1 差）；滚到 120px 后 OgLAppBar 到 `surfaceContainerHigh`，而原生栏只由 `scrolledUnderElevation` 做 tonal 抬升——**同类页面顶栏两套色阶语言**。这是 P1 · T-09（跨页一致性），修复：把 `og_l_app_bar.dart:139` 插值起点改 `theme.appBarTheme.backgroundColor ?? scheme.surface`，终点改 `surfaceContainer` 或让主题层统一 surface；或在 `theme.dart` 取消 `backgroundColor` 的硬编码，全权交给 OgLAppBar。另 `theme.dart:315/og_l_app_bar.dart:152` 的 `surfaceTintColor: Colors.transparent` 使 `scrolledUnderElevation=2` 只剩 2dp 阴影而无 tonal 抬升——**G-02 要的「顶栏浮起色阶」实际只有影子**，在 12% shadow 下非常弱；建议去掉 transparent tint 或显式插值到 `surfaceContainerHigh` 时同步给边界线。

### 2.6 投影 / 边界 / 明暗小结（回答 v15 回归四问）

- 投影过重？**否**，1dp + 12% 是 M3 level 1 合规值。
- 边界过重？**是（轻微，P2）**，强描边明色 4–5:1 让装饰线与重要线同强。
- 明暗不一致？**是（P1）**，disabled 浅色不过 4.5；success 语义色在暗色 diff 文字上仅 2.39:1；顶栏两套起点色。
- rail 与 bar 语言不一致？**是（P1）**，labelType 被 call site 覆盖 + 旧 VerticalDivider 未删。

---

## 3. 新发现（旧审计未抓到 · 13 条编号：v15 回归 T-01～T-05 + 真新增 T-06～T-13）

### P1

**T-06 · 同语义色只在明暗其中一套达标 / 暗色 diff 正文不可读**
证据：`theme.dart:223` `success = #2E7D32` 硬编码、明暗共用；`commit_page.dart:228` 把 `sem.success` 用作**加号行 diff 正文**，`action_log_page.dart:502` / `action_run_page.dart:492` 用作状态图标色。实算：`#2E7D32` 对暗色 `surfaceContainerHighest #343538` = **2.39:1**，对暗色 `surfaceContainerHigh #292A2D` = 2.80:1 → 暗色主题下 diff 新增行**近乎不可读**；对暗色 plain surface 3.62:1 仅过图形级。`warning #B26A00` 对白前景 = **4.24:1**（`theme.dart:225-226`），作为 Filled 按钮/徽标文字未达 4.5。`tool/contrast_audit.py` 因容器色近似取值与配对方式漏掉了这两条（实跑报 0 问题）——门禁本身**检查不完整**。
根因：语义色定义不分明暗；`contrast_audit.py:79-110` 只测 on* 对统一容器近似值，不测「色本身作为前景对最深容器」。
修复指令：`OgLSemanticColors` 构造按 `brightness` 注入——明色 success `#2E7D32`、暗色 success `#66BB6A`（对 `#343538` 约 6:1）；warning 暗色保持、明色改 `#8A4F00`（白前景 ≥4.5）；`tool/contrast_audit.py` 扩 `pairs` 为「色本身 vs 四级容器」并分明暗两套。

**T-07 · SnackBar 主题（含 v15 的 actionTextColor 修复）对 2/3 提示完全不生效**
证据：`theme.dart:284-304` 定义了三档 elevation / shape / 明暗 actionTextColor；但 `notifier.dart:129-146` 与 `error_surface.dart:572-578` 都用 `SnackBar(...)` 直接构造并给 `backgroundColor` / `content` 自定义，未给 shape/elevation/actionTextColor；全库 `rg -n 'snackBarTheme' lib` 仅 `theme.dart:284` 一处定义、**零消费**。后果：v15 的「暗色动作色 1.9→9.5:1」修复**在真实提示上没发生**；三语气靠 `notifier.dart:113-126` 的底色/图标区分（实测 contrast 5.5–7.7:1，尚可），但统一 shape（shapeMd）与 3dp elevation 未生效，与 dialog/sheet 的视觉语言脱节。
根因：组件主题只写在 ThemeData，业务用裸构造绕开。
修复指令：`notifier.dart:130` 与 `error_surface.dart:572` 给 `SnackBar` 补 `shape: Theme.of(context).snackBarTheme.shape`、`elevation: Theme.of(context).snackBarTheme.elevation`、`actionTextColor:` 取主题值（若 tone 特殊则显式给 `onError` 等）；或在两处统一走一个 `OgLSnackBar` 包装。

**T-08 · 40 处裸 `OutlineInputBorder()` 覆写使新输入框描边失效**（同 §1 B-02，因覆盖面最广列 P1）
证据：`theme.dart:434-441` 已设强边，但 `rg -n 'border: (const )?OutlineInputBorder\(\)' lib/surface` 得 **40 处**（`new_repo_page.dart:152/161`、`new_issue_page.dart:147/156`、`login_page.dart:383`、`repo_page.dart` 9 处、`settings_page.dart:1185/1195/1915/1924`、`issue_page.dart:942/1033/1043/1145/1181`、`search_page.dart:1378` 等），`code_editor_field.dart:791/849` 用 `InputBorder.none`。用户感知：设置弹窗、新建仓库/issue、搜索框**依旧无边界**，v15 的头号卖点在最常用表单上缺席。
修复指令：批量删除这 40 处 `border:` 覆写，让 `inputDecorationTheme` 生效；仅搜索框/编辑器查找框确需无框时显式 `border: InputBorder.none` 并补 `filled: true` 的可见底/下划线。

**T-09 · 顶栏两套色阶语言（OgLAppBar 与原生 AppBar 起点不同）**（详见 §2.5）
证据：`theme.dart:314` `backgroundColor: surfaceContainerLow` vs `og_l_app_bar.dart:139` 插值起点 `theme.colorScheme.surface`；`og_l_app_bar.dart:152` 与 `theme.dart:315` 双 `surfaceTintColor: transparent` 使 `scrolledUnderElevation` 只剩阴影。用户感知：列表页与详情页滚动时顶栏颜色/浮起观感不同，「不像同一产品」；14 页 `OgLAppBar` 与 30 页原生 AppBar 分布见 `rg -l`。修复：`og_l_app_bar.dart:139` 起点改读 `theme.appBarTheme.backgroundColor`；统一所有页走 OgLAppBar 或统一 theme 起点色；给顶栏滚动态加 1px `outlineStrong` 底线而非只靠 2dp 投影。

### P2

**T-10 · navRail 被 call site 覆盖标签策略 + 未删旧 VerticalDivider**（详见 §2.3）
证据：`client_shell.dart:376-378` 覆盖 `labelType`、`client_shell.dart:401` `const VerticalDivider(width: 1)`；theme 的 `labelType: all`（`theme.dart:362`）在宽屏失效，安全区与 groupAlignment 缺失（旧 G-08 残留）。修复照 `UX_STABILITY_PLAN.md:145-149`。

**T-11 · ColorPicker 仍用 1px `outlineVariant`**
证据：`settings_page.dart:235`（当前主题色选择框 border，1px `outlineVariant`）、`:530` Divider 硬性 `outlineVariant`、`:2365` `Border.all(outlineVariant)`；`code_editor_field.dart:631` 行号竖线、`readme_view.dart:398` 引用竖线同样。这些是计划表 `:66` 明确要替换为 `outlineVariantStrong` 的八类边界中的 4 处，v15 只改了主题默认值，页面硬编码未收编 → 同页出现强弱两种线。修复：这 4 处改读 `Theme.of(context).extension<OgLSemanticColors>()!.outlineVariantStrong`（或直接删硬编码让 dividerTheme 生效）。

**T-12 · `surfaceContainerLowest` 仍全库 0 次使用，降级分组语义缺位**
证据：`rg -n 'surfaceContainerLowest' lib` = 0 命中；`theme.dart` 未给 `listTileTheme.tileColor`（`:370-382`），设置/关于的裸列表页仍靠弱线分组（旧 G-07 的页面部分）。v15 只改了选中态透明度。修复：在 `listTileTheme` 加 `tileColor: scheme.surface`，设置/关于分组容器用 `surfaceContainerLowest` 实装下沉块。

**T-13 · `theme.dart` 强描边用绝对色值，Material You 动态配色下不联动**
证据：`theme.dart:116-117` 硬编码明暗色；`og_l_app.dart:71-78` 在 Android 12+ 传入 `dynamicScheme` 全量替换 ColorScheme，强描边仍是固定灰 → 壁纸偏红/偏绿时中性灰描边与 tonal 表面**色相脱节**，且对比度不再受 §2.1 表格保证。修复：`outlineStrong` 在 `overrideScheme != null` 时改由 `scheme.outline`/`onSurfaceVariant` 派生（如 `Color.lerp(scheme.outline, scheme.surface, 0.15)` 后跑 WCAG 门禁），或在扩展里存函数而非固定值。

---

## 4. 用户满意度：主题层是否让界面「像工具」？

**正面（可确认）**：
- **稳定**：卡片有 1px 可辨强边 + 12% 轻投影 + 显式 scaffold 底色（`theme.dart:217-248`），首屏每个卡片都有锚点，不再「浮在空中」；导航选中态三处统一 token（`:331-367/381`），用户能预测「选中会长什么样」。
- **清晰**：分隔线全库 ≥3:1（实跑 5 组全 PASS），输入框主题默认值有边界；弹层级序 card < sheet < dialog 恢复。
- **可预期（部分）**：圆角/间距统一取 `OgLRadius`（4/8/12/16/28）与 `OgLSpace`（4/8/12/16/24/32/48/64），不写裸值，控件形状全站一致。

**负面（尚未满意）**：
- **明暗两套不同步**：success 语义色暗色 diff 2.39:1、disabled 浅色 4.12–4.44:1、顶栏两套起点色 → 用户切到暗色会遇到「同一工具变了一个版本」。
- **令牌与实际用法脱节**：40 处裸输入框边框、4 处裸弱描边、SnackBar 主题零消费、navRail 标签被 call site 覆盖 → 一次修主题「应该全站生效」的承诺没有兑现，用户会在不同页面看到不同强度的边。
- **层级靠线不靠阶**：明色 surface→container 只差 1.11:1，层级全靠描边/投影支撑；工具感更多来自「画了线」而非「内容有层级」，仍是「线框感」而非「结构感」。

**结论**：v15 主题层把「漂浮感」修掉了大半，方向正确；但要达到用户判词里的「稳定、清晰、可预期」，还需收口**明暗语义色（T-06）**、**输入框调用点（T-08）**、**顶栏一致性（T-09）** 三条 P1，并让主题定义真正被所有出口消费（T-07/T-10/T-11）。

---

## 5. 本席对三问的回答

**问 1 · 闭环核对：旧确证修好了吗？**
按任务给定的 7 条逐条判：**B-01 已修**（强描边明暗五级全过 3:1，`theme.dart:116-117/240/279/388/397/420`）；**B-02 修法有问题**（主题默认值设了，但 40 处裸 `OutlineInputBorder()` 未删，表单仍无框）；**G-01 已修**（卡片 surfaceContainer + elevation 1 + shadow12 + scaffold 底色）；**G-03 已修**（card < sheet < dialog 层级恢复，但边框/遮罩缺失由新发现覆盖）；**G-04 已修**（输入框降为 surfaceContainerHigh）；**G-07 修法有问题**（60% 浅色 4.12–4.44:1 未达计划的 4.6:1，暗色通过）；**B-08 已修**（listTile/navBar/navRail 三处选中态统一）。统计：**5 已修 / 2 修法有问题 / 0 完全未修（但 B-02 的调用点清理未闭环）**。

**问 2 · 回归：v15 大改引入新问题吗？**
引入/暴露 6 项：T-01 边界过重（明色 4–5:1）、T-02 暗色描边贴线 3.05:1、T-04 rail 标签被 call site 覆盖且旧弱线未删、T-05 rail/bar 动态配色无门禁、T-06 语义色暗色 2.39:1、T-09 顶栏两套色阶语言；另 disabled 60% 浅色不达标（G-07 行）。投影本身**不过重**，色阶 + 阴影双计价见 T-03。

**问 3 · 新发现：旧审计未抓到的用户可感知问题？**
真新增 **8 条 / 13 编号（T-01～T-13）**：P1 × 4（T-02 暗色描边贴线、T-06 语义色暗色 2.39:1、T-07 SnackBar 主题零消费、T-08 输入框 40 处裸覆写、T-09 顶栏两套色阶——其中 T-02 与 T-09 在 §2 作为回归发现计），P2 × 4（T-01 边界过重、T-03 接地靠线不靠阶、T-10 rail 覆盖、T-11 页面裸弱线、T-12 最低档未用、T-13 动态配色脱节——归并为 4 条主项，其余为同根因附注）。最该先修的两条：**T-06（暗色 diff 2.39:1）** 与 **T-08（40 处裸边框吃掉新输入框描边）**。

---

## 6. 已检查清单（证明覆盖，非抽样）

- [x] `lib/surface/theme.dart` 全文 1–505 行（含 `git show 531bd8a` 的 14 项 diff 逐条核对）
- [x] `lib/surface/util/og_l_radius.dart` 全文 94 行（xs/sm/md/lg/xl/pill + 图标尺度）
- [x] `lib/surface/util/og_l_space.dart` 全文 70 行（8dp 节奏 / 别名 / SizedBox 工厂）
- [x] `docs/UI_AUDIT_V2_BRIEF.md` 全文、`docs/UX_STABILITY_PLAN.md` §3.1/§3.2/§4 第一批 14 项
- [x] `material-3/SKILL.md` Color/Typography/Shape/Elevation/Theming（Token 表 + §Elevation + §Dark Theme + §Audit）
- [x] `sota-frontend-design/rules/01-typography-and-color.md` §4/§4b/§5/§6/§6b + 审计清单
- [x] 对比度工具：`python3 tool/contrast_audit.py`（0 问题 / exit 0）+ 自建 `python3 /tmp/ogl_theme_contrast.py`（解析 theme.dart 实际色值重算 4 组 20+ 对）
- [x] 令牌使用普查：`rg -n 'outlineVariant|outlineVariantStrong|surfaceContainerHighest|surfaceContainerLowest|withValues\(alpha' lib/surface --glob '*.dart'`（40 处裸输入框边框、4 处裸弱线、0 处最低档）
- [x] 主题出口普查：`rg -n 'snackBarTheme|SnackBar\(' lib`（主题零消费）、`rg -l 'OgLAppBar\(|AppBar\(' lib/surface/pages`（14 / 30 页）
- [x] 顶栏/弹层/Rail 实现：`lib/surface/app/og_l_app_bar.dart:1-156`、`lib/surface/app/overlays.dart:1-95`、`lib/surface/app/client_shell.dart:360-406`、`lib/surface/app/notifier.dart:60-160`、`lib/surface/app/error_surface.dart:560-580`
- [x] 动态配色接入：`lib/surface/app/og_l_app.dart:60-110`（DynamicColorBuilder + overrideScheme 路径）
- [x] 语义色调用点：`rg -n 'extension<OgLSemanticColors>' lib/surface`（4 页 + theme 自身）、`commit_page.dart:224-234` diff 前景、`action_log_page.dart:502` / `action_run_page.dart:492` 状态图标
- [x] 旧审计交叉：`docs/UX_CROSS_AUDIT/2-A-elevation.md` §0.1–0.4、`2-B-borders.md` §0.1、`UX_STABILITY_PLAN.md:54-113` 7 条主题层确证
- [x] 未覆盖声明：页面层逐页视觉（批 2/3 席位）、文本字号层级（1-B）、裸几何值（1-C）、转场/动效（批 4）不在本席范围；本报告只判主题层定义与主题出口的实际效果
