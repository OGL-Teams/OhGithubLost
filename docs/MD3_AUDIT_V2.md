# MD3 Compliance Audit Report（V2 · 修后重审计）

Target: `/root/OhGithubLost`（Flutter 多平台 GitHub 客户端，Target = **HEAD `03767f4`**；V1 基线为 v12.6.9 / `40b7831`）
Date: 2026-11-19
Method: 只读源码审计（逐项 `rg` 复现 + `git diff` 核验 V1→V2 修复真伪 + 关键文件通读）；实跑 `tool/ui_audit.py --fatal`、`tool/motion_audit.py`、`tool/motion_coverage_audit.py`、`tool/i18n_scan.py --check`
Overall Score: **97/100**（V1 = 90/100，+7）

> **用户新约束（本条覆盖 V1 报告「合法项目约束」的历史表述，继续有效）**：设置 / 关于 / 用户页「零气泡、单层平铺、仅分类」。三页仍以 `ListTile` + `Divider` + `OgLFlatTile`/`ogLFlatRows` 平铺，不因本报告扣分。本次新增的「跟随系统配色」开关亦以 `OgLSettingsSwitchRow` + `Divider(height: 1)` 平铺接入（`settings_page.dart:635-643`），未引入任何 Card / 分组气泡。

## Scores by Category（V1 → V2 对照）

| Category | V1 | V2 | 变化 | Status |
|---|---|---|---|---|
| Color tokens | 9/10 | **10/10** | +1 | pass |
| Typography | 8/10 | **10/10** | +2 | pass |
| Shape | 9/10 | **10/10** | +1 | pass |
| Elevation | 10/10 | **10/10** | 0 | pass |
| Components | 9/10 | **10/10** | +1 | pass |
| Layout | 9/10 | **9/10** | 0 | pass |
| Navigation | 9/10 | **9/10** | 0 | pass |
| Motion | 10/10 | **10/10** | 0 | pass |
| Accessibility | 8/10 | **9/10** | +1 | pass |
| Theming | 9/10 | **10/10** | +1 | pass |
| **Overall** | **90/100** | **97/100** | **+7** | — |

10 类最低分由 V1 的 8 提升至 9；无任何类落入 warn/fail 区间。

---

## 逐类证据（均可 `rg` 复现）

### 1. Color tokens — 10/10 pass（V1 9 → +1）
- **动态配色闭环（Fix #2 / #6）**：`pubspec.yaml` 新增 `dynamic_color: ^1.7.0`；`lib/surface/app/og_l_app.dart:28,67-84` `DynamicColorBuilder` 取 `dynamicLight/dynamicDark` 并按 `MediaQuery.platformBrightnessOf` 选择；`lib/surface/surface_bridge.dart:538` `overrideScheme: useDynamic ? dynamicScheme?.harmonized() : null`（按 MD3 Color Harmonization 与 primary 调和）；`lib/surface/theme.dart:156-160` `ColorScheme.fromSeed` 仍是唯一手动生成路径，`overrideScheme` 优先。
- 用户开关：`lib/surface/settings.dart:116,184-185,417-420,633-638,685,969-974` `dynamicColor` 默认 false、可持久化、有 `setDynamicColor`；`lib/surface/pages/settings_page.dart:635-643` 平铺开关行；30/30 份 `assets/i18n/*/settings.json` 均含 `dynamicColor` 键（`tool/i18n_scan.py --check`：语言清单与键集合一致，0 处未本地化）。
- 品牌色收尾（Fix #6）：`lib/surface/util/file_icons.dart:10-12` 文件头声明 `Color(0xFF…)` 为 GitHub 语言品牌色、非 UI 表面色、不参与 ColorScheme / 动态配色。
- 既有令牌未回潮：`lib/surface/theme.dart:80` `OgLSemanticColors extends ThemeExtension`；tonal 配对见 `theme.dart:213,252,265`；页面零字面色（`ui_audit.py --fatal` → 0 处）。
- **评分理由**：V1 唯一扣分点「无 dynamic color」已解除；品牌色误判风险由注释消除。

### 2. Typography — 10/10 pass（V1 8 → +2）
- **6 处裸 fontSize 全部从 textTheme 派生（Fix #1）**：`lib/surface/theme.dart:186` `final TextTheme tt = ThemeData(brightness: brightness).textTheme`；派生点逐条可数：
  - dialog 标题 `:234` `tt.titleLarge`、正文 `:240` `tt.bodyMedium`（V1 `:262,:272`）
  - appBar `:289` `tt.titleLarge`（V1 `:326`）
  - snackBar `:266` `tt.bodyMedium`（V1 `:311`）
  - navigationBar label `:316` `fontSize: (tt.labelMedium?.fontSize ?? 12)`（V1 `:353`；字面量仅作 null 兜底，值取自令牌）
  - chip `:361` `tt.labelSmall`（V1 `:407`）
  - filled/text/outlined 按钮 `:422,:433,:445` `tt.labelLarge`（V1 `:425/:443/:461`）
  - inputDecoration hint `:413` `tt.bodyMedium`（V1 未列，同批收敛）
- 门禁复现：`rg -n 'fontSize\s*:' lib/surface/theme.dart` 仅 `:316` 一条且为令牌派生；`python3 tool/ui_audit.py --fatal` → 「0 处令牌外字面值」。
- 残余均属合法例外：等宽字号令牌 `lib/surface/util/og_l_font.dart:11,14` `monoSm=12/monoMd=13`；页面级 `fontSize` 由用户设置驱动（已登记在 `ui_audit.py` ALLOW）；`lib/main.dart:375` ErrorWidget 无 Theme 可用。

### 3. Shape — 10/10 pass（V1 9 → +1）
- **Fix #5 闭环**：`lib/surface/util/og_l_radius.dart:36` `xl = 24 → 28`，注释「对齐 M3 extra-large 28dp」；`og_l_radius.dart` 中 `static BorderRadius circular(double value)` 工厂**已删除**（`git diff` 删除 4 行）；全仓 `rg 'OgLRadius\.circular\(' lib/` → 0 命中；`rg 'BorderRadius\.circular\(\s*[0-9]' lib/surface` 仅命中 `og_l_radius.dart:16` 的文档示例。
- 既有分发未变：`theme.dart:164-178` shapeSm/Md/Lg/Xl/Pill → 14 类组件（`:214,250,261,330,352,376,394-406`）；`og_l_radius.dart` 六档刻度 xs4/sm8/md12/lg16/xl28/pill 与 MD3 shape scale（4/8/12/16/28/full）一致。
- **评分理由**：V1 扣的「xl=24」与「circular(value) 任意值口子」两项均消除。

### 4. Elevation — 10/10 pass（V1 10 → 0）
- 全仓 `rg -c 'BoxShadow' lib/surface` → 0；`shadowColor` 零命中；elevation 全为 0（`theme.dart:217,228,251,262,285,299`、`og_l_app_bar.dart:142`），AppBar `scrolledUnderElevation: 0`（`theme.dart:285`）。
- 深度由 surfaceContainer 色调表达（`theme.dart:213,252,265`），`og_l_app_bar.dart` surface→surfaceContainer 连续插值保持原样。

### 5. Components — 10/10 pass（V1 9 → +1）
- 14 类组件主题完整（`theme.dart:212,226,248,259,283,297,329,344,351,369,385,417,428,439,451`），均落 `OgLRadius`+`OgLSpace`。
- V1 扣分点「三类按钮 textStyle 重复裸 `fontSize:14`」随 Fix #1 一并消除（`theme.dart:422,433,445` 统一走 `tt.labelLarge`）。
- MD2 组件零残留；触控尺寸 `minButton/minTouch` 见 `theme.dart:189-190,420,431,442,453`。

### 6. Layout — 9/10 pass（V1 9 → 0）
- **Fix #4 按建议范围闭环**：新增 `lib/surface/util/og_l_window_widths.dart:1-15` `OgLWindowWidths`（`compact=600 / contentMax=720 / expanded=1200`，文件头注释「对齐 Material 3 WindowSizeClass：compact <600 ≤ medium <840 ≤ expanded <1200 ≤ large」）；5 处断点常量化复现：`client_shell.dart:314,319,326,362`、`search_page.dart:872`（`rg -n 'OgLWindowWidths' lib/surface`）。
- 宽屏限宽 `client_shell.dart:317-320`（maxWidth=contentMax）、兜底页 `og_l_app.dart:181-182`（640）；8dp 体系 `og_l_space.dart`；安全区 `overlays.dart`、键盘守卫 `og_l_app.dart` 未变。
- **未达 10 的理由（V1 遗留、不在 6 项修复范围）**：仍以常量断点 + `LayoutBuilder` 手写判断而非官方 `calculateWindowSizeClass`/adaptive API；无 foldable hinge 处理（`rg -i hinge lib/surface` 零命中）；无 list-detail 双栏。常量类为后续留口，但类别合规性未变。

### 7. Navigation — 9/10 pass（V1 9 → 0）
- `client_shell.dart:246-249` `PopScope(canPop:false) + onPopInvokedWithResult`（预测性返回兼容）；`:143` `OgLBackGuard` 双击退出状态机；`:330` `NavigationBar`（<600）、`:367-390` `NavigationRail` + `extended`（`:362` ≥expanded）+ labelType 切换。
- 未达 10 的理由同 V1：宽屏仅 rail，无标准/模态 `NavigationDrawer` 的 list-detail 双栏；drawer 分支自述不可达（`client_shell.dart:175-179`）。本轮无改动。

### 8. Motion — 10/10 pass（V1 10 → 0）
- 档位唯一事实源 `lib/surface/app/motion.dart:163` `isNotHeavierThan`、`:300-304` `disableAnimations`、`:331-339` `pageTransitions`；消费点 `surface_bridge.dart:561,566-567`、`og_l_app.dart:119-120`。
- 门禁实测：`python3 tool/motion_audit.py` → 「扫描 81 文件，违规 0 处」；`tool/motion_coverage_audit.py` → 「0 处」。与 V1 一致（V1 记 79 文件，本轮因新增文件为 81）。

### 9. Accessibility — 9/10 pass（V1 8 → +1）
- **Fix #3 闭环**：`lib/surface/theme.dart:189-190` `minTouch = Size(48,48)`、`minButton = Size(64,48)`（V1 `:222-224` 为 44），`rg -n 'minTouch|minButton|Size\(48|Size\(44' lib/surface/theme.dart` 可复现；设置页色板命中区 48/视觉 34 的做法保留（`settings_page.dart:219-224`）。
- 文字缩放 `og_l_app.dart:111-118` `TextScaler.linear((systemScale*fontScale).clamp(0.85,2.0))`；`Semantics(` 全 surface 11 处、`tooltip:` 69 处。
- **未达 10 的理由（V1 遗留两项）**：① 无系统性对比度自查测试（语义色如 success 在暗色容器上的对比度未量化）；② Semantics 覆盖仍集中于设置页色板，自定义绘制行未见审计记录。触控目标项已解除。

### 10. Theming — 10/10 pass（V1 9 → +1）
- 唯一编译点 `surface_bridge.dart:506-538`：`themeFor(..., dynamicScheme:)` 参与缓存键 `:499,523`（`useDynamic = current.dynamicColor && dynamicScheme != null && seed == 'github'`），`overrideScheme: dynamicScheme?.harmonized()`；`buildOgLTheme(brightness, overrideScheme:)`（`theme.dart:150-160`）；外观字体仅覆写 body 三档（`surface_bridge.dart:550-558`），组件标题/标签仍取默认 MD3 textTheme，联动正确。
- 明暗 × 7 种子色 × 密度 × 动效档位 × 动态色参与缓存；`AnimatedTheme` 等价主题不误触发。
- 启动兜底 `og_l_app.dart:154-175` 仍 `useMaterial3 + fromSeed(kOgLErrorSeedColor)`。
- **评分理由**：V1 主要扣分「无 dynamic color」已解除；兜底页 `Locale('zh','CN')` 硬编码（`og_l_app.dart:165`）仍存，但仅位于启动失败路径，作为轻微备注不再单独扣分。

---

## 用户新约束复核（覆盖 V1「合法项目约束」表述，不扣分）

- 三页零 Card：`rg '\bCard\(' lib/surface/pages/{settings_page,about_page,profile_page}.dart` → 0 命中。
- 平铺实现：`lib/surface/widgets/flat_list.dart` 全宽行 + 1px `Divider` + 统一 padding；`rg -c 'Divider\('` → settings_page 31 / about_page 11 / profile_page 1。
- 新增开关未破坏约束：`settings_page.dart:635-643` `OgLSettingsSwitchRow` + `Divider(height:1)`，无气泡容器。
- 结论：用户指令优先于 skill 默认卡片分组建议；实现仍在 MD3 令牌体系内（统一行高、outlineVariant 分隔线），仅组件形态不同。

## V1 六项 Recommended Fixes 闭环状态

| # | V1 建议 | 状态 | 验证 |
|---|---|---|---|
| 1 | `theme.dart` 组件字号改从 `textTheme` 派生 | ✅ **已闭环** | `theme.dart:186,234,240,266,289,316,361,413,422,433,445`；`rg fontSize` 仅剩令牌派生兜底；Typography 8→10、Components 9→10 |
| 2 | Android 12+ 接入 dynamic color（`dynamic_color` 包 + `themeFor` 分支 + 保留 7 种子色） | ✅ **已闭环** | `pubspec.yaml` + `og_l_app.dart:28,67-84` + `surface_bridge.dart:538` + `theme.dart:156-160` + 30 语言 i18n；Color 9→10、Theming 9→10 |
| 3 | 触控目标 44→48，`minButton` 同步 | ✅ **已闭环** | `theme.dart:189-190` `Size(48,48)/Size(64,48)`；Accessibility 8→9 |
| 4 | 断点收敛为 `OgLWindowWidths` 常量类 + M3 映射注释 | ✅ **已闭环（按建议字面范围）** | `og_l_window_widths.dart:1-15` + 5 处常量化；Layout 保持 9：官方 adaptive API / foldable 属建议外遗留，未记为未闭环 |
| 5 | `OgLRadius.circular(value)` 收紧 + xl 24→28 | ✅ **已闭环** | `og_l_radius.dart:36` xl=28、任意值工厂删除；全仓无调用；Shape 9→10 |
| 6 | `file_icons.dart` 品牌色集中注释 | ✅ **已闭环** | `file_icons.dart:10-12`；防止后续审计误判回潮 |

**结论：6 项全部闭环，无未闭环项。** 未满分的三类（Layout 9 / Navigation 9 / Accessibility 9）均因 V1 中未被 6 项建议覆盖的遗留项（official WindowSizeClass + foldable、list-detail drawer、对比度自查 + Semantics 覆盖），本轮无新增缺失。

## Critical Issues（0–3 分）

无。10 类最低 9 分。

## Warnings（4–6 分）

无。

## Passing（7–10）

- **Color / Typography / Shape / Components / Theming 10**：6 项修复使 V1 的已知缺口全部关闭；动态配色走 `harmonized()` 且以缓存键隔离，字号全链路联动 textTheme，任意圆角工厂删除。
- **Elevation 10 / Motion 10**：维持 V1 满分；零 BoxShadow、纯 tonal 分层；档位质量表 + 单调性 + 双 CI 门禁实测 0 违规。
- **Layout 9 / Navigation 9 / Accessibility 9**：核心模式合规，残留为 V1 已标注且超出本轮修复范围的小项。

## Overall 分数对比

- V1（v12.6.9 / `40b7831`）：**90/100**
- V2（HEAD `03767f4`）：**97/100**（+7）
- 增量来源：Typography +2（Fix #1，兼带动 Components +1）、Color +1 与 Theming +1（Fix #2）、Shape +1（Fix #5）、Accessibility +1（Fix #3）；Fix #4/#6 已闭环但不改变所属类别分数。

## 自检

- `python3 tool/ui_audit.py --fatal` → 「UI 细节度扫描（lib/）：0 处 / 审计通过」，退出码 **0**。
- `python3 tool/motion_audit.py` → 81 文件 0 违规；`python3 tool/motion_coverage_audit.py` → 0 处。
- `python3 tool/i18n_scan.py --check` → 30 语言键集合一致、0 处未本地化。
- 本审计为只读：除新建本文件外未改动任何源码/文档，未修改 V1 报告 `docs/MD3_AUDIT.md`，未执行任何 git 写操作。

---
*所有结论均可在上列 file:line 用 `rg` 复现；修复真伪以 `git diff`（`40b7831` → HEAD `03767f4`）交叉核验。*
