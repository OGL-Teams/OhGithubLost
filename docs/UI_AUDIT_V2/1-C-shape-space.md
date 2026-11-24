# 批 1 · C 席 —— 形状与间距复审（v15 之后）

> **文档戳 / Doc Stamp**
> - 更新时间：**2026-11-24 22:36:59 +0800（LCL）** · 版本戳：**v15.0.0**
> - 审计对象：`docs/UI_AUDIT_V2_BRIEF.md` 指定的 3 个令牌文件（`lib/surface/util/og_l_radius.dart` / `og_l_space.dart` / `og_l_window_widths.dart`）+ v15 消费面 + 页面层裸值 rg 统计 + 跨页一致性抽查；参照 `material-3/SKILL.md` Shape Tokens 节（none 0 / extra-small 4 / small 8 / medium 12 / large 16 / extra-large 28 / full 9999，Expressive 另有 large-increased 20 / extra-large-increased 32 / extra-extra-large 48）
> - 仓库：`/root/OhGithubLost`，v15 HEAD 工作副本；**只读审计，未改代码、未 commit/push**；唯一产出即本文件
> - 复现：所有结论均有 `file:line`，可用 `rg -n` 复现；证据基于 `lib/` 全库 rg + 逐点读取，无 SDK 读取（禁读纪律已遵守）

---

## 1. 令牌自身复审（逐项「对齐 / 偏离 / 建议」）

### 1.1 `OgLRadius` 六档 ↔ M3 shape scale

| 令牌 | 本项目值 | M3 对应 | 判定 | 证据 |
|---|---|---|---|---|
| `xs` | 4 | extra-small 4 | **对齐** | `og_l_radius.dart:29` |
| `sm` | 8 | small 8 | **对齐** | `:32` |
| `md` | 12 | medium 12 | **对齐** | `:35` |
| `lg` | 16 | large 16 | **对齐** | `:38` |
| `xl` | 28 | extra-large 28 | **对齐（v15 由 24 修正）** | `:41` + commit `0851f7f` |
| `pill` | 999 | full 9999px | **对齐（语义）** | `:44`，999 在 Flutter 侧等价全圆，够用 |
| — | 缺 0（none）档 | none 0 | **偏离（轻）** | 全文件无 none；业务用 `BorderRadius.zero` 可解，不必补 |

- 附带表达力缺口：M3 Expressive 的 20 / 32 / 48 三档没有令牌，但当前无消费点，判为**不偏离（暂不需要）**。
- 结构性建议（P2）：`og_l_radius.dart:16` 已明令「业务代码不写 `BorderRadius.circular(8)`」，但库内仍有 **10 处** `BorderRadius.circular(OgLRadius.*)`（见 §3）。数值已令牌化、无裸值风险，只差表达统一；建议统一改用 `OgLRadius.cSm` 等常量工厂，或把文档那句改成「不写裸数字」。

### 1.2 `OgLSpace` 8 点体系

| 令牌组 | 值 | 判定 | 证据 |
|---|---|---|---|
| `xxs/sm/md/lg/xl/xxl/huge/mega` | 4 / 8 / 12 / 16 / 24 / 32 / 48 / 64 | **对齐**：除 4（M3 允许的最小粒度）与 12（过渡档）外均为 8 的整数倍；文件 `:3-10` 已声明此语义 | `og_l_space.dart:33-40` |
| `gapSm/gapMd/gapLg/gapXl` 别名 | 8 / 12 / 16 / 24 | **对齐** | `:43-47` |
| SizedBox / EdgeInsets 工厂 | vXs…vXxl / hXs…hLg / pageHorizontal… | **对齐（覆盖偏少）**：只有 6 档 v、4 档 h，无 `hXxl/vHuge` 工厂，大留白仍需裸 `SizedBox(height: OgLSpace.huge)`；判**轻偏离** | `:50-69` |

- 刻度**没有** 10 / 18 / 20 / 28 这类中间值；页面层出现的 18 / 20 / 24 / 28 主要是 spinner 直径、Divider 高度和触控圆尺寸，不是 padding 刻度缺口（见 §3.2）。判 **对齐**。

### 1.3 `OgLWindowWidths` ↔ M3 canonical 断点

| 常量 | 值 | M3 | 判定 | 证据 |
|---|---|---|---|---|
| `compact` | 600 | compact/medium 边界 600 | **对齐** | `og_l_window_widths.dart:8`；消费 `client_shell.dart:330`、`search_page.dart:886` |
| `expanded` | 1200 | medium/expanded 边界 1200 | **对齐** | `:12`；消费 `client_shell.dart:366` |
| 注释中的 840 | medium/large 边界 840 | M3 canonical | **对齐（仅注释）** | `:2-3`；未定义常量，项目只做三档，合理 |
| `contentMax` | 720 | M3 无此 canonical 断点（是阅读宽度策略） | **偏离（语义，非数值）**：文件名叫 WindowWidths 却装了一个内容限宽值；且 `client_shell.dart:318-322` 确认 720 限宽下沉尚未做，常量当前零消费 | `:9` |

---

## 2. v15 改动回归

### 2.1 `xl` 24→28 消费面（rg `cXl` / `verticalTopXl` / `OgLRadius.xl`）

| 用点 | 角色 | 28 的影响 | 判定 |
|---|---|---|---|
| `theme.dart:190-191` `shapeXl`（`RoundedRectangleBorder(cXl)`） | 对话框统一形状 | 对话框圆角 24→28，**符合 M3 extra-large**；对角半径只占对话框短边（典型 ≥280dp）的 10%，视觉不会「太圆」 | 对齐 |
| `theme.dart:252` `dialogTheme.shape: shapeXl` | 所有标准对话框 | 同上，`insetPadding` 仍是 24/24（`theme.dart:256-257`），对话框尺寸不变，只有角更圆 | 对齐 |
| `theme.dart:273-276` `bottomSheetTheme.shape = verticalTopXl` | 全库底部弹层上沿 | 上沿圆角 24→28，M3 extra-large 正是 dialog / bottom sheet；drag handle 保留（`:278`） | 对齐 |
| `theme.dart:188-195` 其它 shapeSm/Md/Lg/Pill | 卡片/列表/pill | 不受影响 | 对齐 |
| `settings_page.dart:214` `BorderRadius.circular(OgLRadius.xl)` | 取色对话框内 48dp 色块点击区 | **唯一需关注点**：48dp 见方元素用 28 半径 → 两角几乎相切，接近圆形；而它包着一个 34dp 的圆形色样本，视觉上「圆里套圆」，与方色板语义不符。建议改为 `OgLRadius.cLg`（16）或 `cMd`（12） | **P2 局部过大** |

- 全库 `cXl` / `verticalTopXl` 无其它消费点（rg 已列全）。**结论：28 未让对话框/弹层整体过大，只有 `settings_page.dart:214` 一处小元素过度圆化。**

### 2.2 `OgLRadius.circular` 工厂删除回归

- `rg -n 'OgLRadius\.circular' .`（排除 docs）：**0 处**，删除干净。
- `rg -n 'BorderRadius\.circular\(\s*[0-9]' lib --glob '*.dart'`：命中 **0 处**（唯一输出是 `og_l_radius.dart:16` 的文档注释文字）。
- 全库 `BorderRadius.circular` 共 **11 处**（含 1 处文档注释），10 处实参均为 `OgLRadius.*` 令牌：`readme_view.dart:394`、`settings_page.dart:214/2364`、`pull_page.dart:209`、`onboarding_page.dart:272/438/453`、`commit_page.dart:202`、`notifications_page.dart:364`、`action_log_page.dart:544`。**无裸圆角数值回归。**

---

## 3. 页面层裸值统计（rg 全库，不逐页深挖）

### 3.1 `EdgeInsets` 裸数字：**0 处**

- `rg -n 'EdgeInsets.*\b[0-9]+\b' lib/surface/pages --glob '*.dart'` → 排除 `OgLSpace.*` / `0` 后 0 命中；163 处 `EdgeInsets` 全部使用 `OgLSpace` 令牌或 `EdgeInsets.zero`。页面级裸 padding 已在 v14/v15 清零。
- 推论：§1.2 的「刻度缺口」在 padding 语义下**不成立**；页面出现的 18/20/28 都是别的用途（见 §3.2）。

### 3.2 `SizedBox` 裸数字：**23 处**（`lib/` 全库），其中页面层 **18 处**

| 分类 | 处数 | 代表 `file:line` | 性质 |
|---|---|---|---|
| spinner 容器 16/18/22dp + `strokeWidth: 2` | 7 | `action_run_page.dart:537-539`、`readme_view.dart:593-594`、`login_page.dart:415`、`workflow_dispatch_page.dart:489`、`issue_page.dart:771/986`、`boot_splash.dart:64` | 控件内部尺寸，非 spacing 刻度；轻微偏离（18 可用 `OgLIconSize.md`） |
| 比例高度 `MediaQuery * 0.5/0.6/0.8` | 4 | `gist_detail_page.dart:484`、`repo_page.dart:701`、`code_editor_page.dart:372` | 布局策略，非裸间距 |
| 固定宽度 46/72/120/320/480 | 5 | `desktop_window.dart:213`（46 = 38 标题栏 + 8）、`release_detail_page.dart:429`(72)、`about_page.dart:488`(120)、`issue_page.dart:1083`(320)、`gist_detail_page.dart:185`(480) | 内容区宽度，与 spacing 无关；46 与标题栏常量有隐式耦合，建议提为常量 |
| 触控/色块 48/34/32 | 4 | `settings_page.dart:218`、`discover_rows.dart:15`、`code_editor_toolbar.dart:109` | 48 是 M3 触达下限，语义正确；34 是视觉圆，注释已解释 |
| 其它 | 3 | `code_editor_page.dart:598` 等 | 同上 spinner |

- **「10 / 18 / 20 / 28 大量使用 → 刻度缺口」判定：否。** 页面层 `SizedBox` 无 10/18/20/28 用作间距；但 `Divider(height:)` 有一组裸中间值：`settings_page.dart:473/1828`(28)、`:1909`(20)、`:1557/1822`(24)、`repo_page.dart:4412/4485/4541`(32)，共 **8 处**——这些是分隔线的**占位高度**（= 线 + 上下留白），属于 spacing 语义，是本席发现的最明确刻度裸值。建议引入 `OgLSpace.sectionDivider = 24` 常量或统一用 `OgLSpace.xl/xxl`。

### 3.3 裸 `BorderRadius.circular`：**0 处**（数值意义上）

- 10 处 `BorderRadius.circular(OgLRadius.*)` 已令牌化（见 §2.2），表达风格建议见 §1.1。

---

## 4. 跨页一致性抽查（3–4 个同类页面）

| 角色 | 页面与证据 | 结论 |
|---|---|---|
| 列表行内边距（设置 / 关于 / 用户） | `settings_group.dart:29-31` `kOgLSettingsRowPadding = symmetric(horizontal: lg, vertical: md)`；`flat_list.dart:16-17` `kOgLFlatRowPadding = kOgLSettingsRowPadding`（旧审计 M-06 的 12 vs 4 已统一） | **一致（已修）** |
| 列表行内边距（数据页 ListTile） | `theme.dart:371-375` `contentPadding = symmetric(horizontal: lg(16), vertical: xxs(4))` + `minVerticalPadding: sm(8)`；`search_page.dart:224` 卡片 `all(md)`；`repo_page.dart:816` `all(md)` | **主题层一致，但自绘行仍分叉**：`discover_rows.dart:74-78` 用 horizontal md(12)/vertical sm(8)（旧 M-07 未修，动态 Tab 与搜索结果 Tab 左边线差 4dp） |
| 页头内边距（同构详情页） | `issue_page.dart:791-794` 与 `pull_page.dart:122-125` 均为 `EdgeInsets.fromLTRB(lg, lg, lg, 0)` | **一致** |
| 页头内边距（同一仓库页内） | `repo_page.dart:2499-2501` 筛选框 `fromLTRB(md, sm, md, xxs)`、`:2488` 状态条 `fromLTRB(md, sm, md, 0)`；下方列表行走主题 `horizontal: lg(16)`（旧 M-08/M-09 现象仍在：输入框左边 12dp vs 列表 16dp） | **偏离 4dp（未修）** |
| 卡片圆角 | `theme.dart:238-241` `cardTheme.shape = shapeLg(16)`；`search_page.dart:224` 卡片 `OgLRadius.cMd(12)` 局部覆写；`issue_page.dart:815` 评论卡走主题 16；全库 38 处 `Card(` 无一裸圆角 | **基本一致的局部覆写**：卡片主题 16，搜索卡 12 是有意的密度选择，但同屏出现时会读出两种卡片口音，建议搜索页也用 `shapeLg` 或把覆写理由写进注释 |

- 页级 gutter（旧 1-A 报告的「5 种内容起始位置」）当前以 `OgLSpace.lg(16)` 为主、`OgLSpace.xl(24)` 用于 onboarding / release_detail 等少数页，仍有 12/16/24/32 四档并存；本轮收窄范围不逐页深挖，交 2-A/2-C 席复核。

---

## 5. 分级问题清单（P0 / P1 / P2）

**P0**：无。形状与间距令牌本身对齐 M3，无数据丢失/不可用问题。

**P1（明显影响一致性，建议修）**

- **P1-1 · 动态流行左边距与其它列表行差 4dp（旧 M-07 未闭环）**：`discover_rows.dart:74-78` 的 horizontal `OgLSpace.md(12)` vs `theme.dart:371-373` 的 `OgLSpace.lg(16)`。症状：搜索/发现页切 Tab 时文字左边线左右跳 4dp。修复指令：把 `discover_rows.dart:75` 的 `horizontal: OgLSpace.md` 改为 `OgLSpace.lg`，与 ListTile 主题同源。
- **P1-2 · repo 页筛选框/状态条与列表行未共线（旧 M-08/M-09 未闭环）**：`repo_page.dart:2488-2501` 用 `md(12)`，列表行 `theme.dart:371` 用 `lg(16)`。症状：输入框比文件名列左缩进少 4dp。修复指令：两处 `fromLTRB(OgLSpace.md, …)` 的左右值改为 `OgLSpace.lg`。

**P2（打磨）**

- **P2-1 · Divider 占位高度 8 处裸值**：`settings_page.dart:473/1557/1822/1828/1909`、`repo_page.dart:4412/4485/4541`（20/24/28/32）。修复指令：在 `og_l_space.dart` 增 `sectionDivider = 24`，统一替换为 `Divider(height: OgLSpace.sectionDivider)`。
- **P2-2 · 取色对话框 48dp 色块过度圆化**：`settings_page.dart:214` 用 `OgLRadius.xl(28)`，改为 `OgLRadius.cLg`（16）。
- **P2-3 · `OgLWindowWidths.contentMax` 语义混装且零消费**：`og_l_window_widths.dart:9` + `client_shell.dart:318-322` 的 TODO。建议 2-C 席把 720 阅读限宽下沉到各页后删除该常量或改名 `OgLLayout.contentMaxWidth`。
- **P2-4 · 圆角工厂表达不统一**：10 处 `BorderRadius.circular(OgLRadius.*)` 建议改用 `OgLRadius.c*` 常量；或把 `og_l_radius.dart:16` 的注释改为「不写裸数字值」。
- **P2-5 · RTL 隐患（跨界提示）**：`verticalTopXl` 是四角对称，本身 RTL 安全；但项目有 ar/he 等 30 语言文案，`settings_group.dart:29` 用的是 `EdgeInsetsDirectional` 而 `theme.dart:372` 用 `EdgeInsets.symmetric`（物理对称，此处无碍）。仅提示 5-C 席关注非对称 padding 的 RTL 化，本席无 P1 级 RTL 问题。

---

## 6. 本席对三问的回答

**问 1 · 闭环核对（旧 61 条里本席范围内的问题修好了吗？）**

| 旧条目 | 状态 | 依据 |
|---|---|---|
| 1-A「同一 App 出现 5 种 gutter」 | **部分修**：令牌化已完成（页面层 `EdgeInsets` 裸数字 0），但 12/16/24/32 四档仍并存（onboarding 24、file_preview 32 等） | §3.1、§4 末段；交 2-A/2-C 深挖 |
| 1-C M-06「FlatTile 12 vs 主题 4」 | **已修**：`kOgLFlatRowPadding = kOgLSettingsRowPadding`（16/12）统一 | `flat_list.dart:16-17` |
| 1-C M-07「同页两 Tab 左边距 12 vs 16」 | **未修**：`discover_rows.dart:74-78` 仍 md(12) | P1-1 |
| 1-C M-08 / M-09「repo 双重缩进 / 输入框不齐」 | **未修**：`repo_page.dart:2488-2501` 仍 md(12) vs 主题 lg(16) | P1-2 |
| 2-B「卡片/弹层边界、卡片比弹层方」 | **已修（形状部分）**：`cardTheme = shapeLg(16)`、`dialog = shapeXl(28)`、sheet `verticalTopXl`，层级形状递进成立；描边/投影属 1-A 席 | `theme.dart:238-241/251-257/273-278` |
| v14 前「圆角 2/6/8/12/24 五种裸值并存」 | **已修**：裸数值圆角 0 处；工厂删除干净 | §2.2 |

**问 2 · 回归（v15 四批大改有没有引入新问题？）**

- xl 24→28：**未引入全局问题**；M3 对齐正确，唯一副作用是 `settings_page.dart:214` 的 48dp 小色块过度圆化（P2-2）。
- 删除 `OgLRadius.circular`：**无遗漏、无裸值回潮**（0/0）。
- 新增 `OgLWindowWidths`：**数值对齐，语义混装**（`contentMax=720` 零消费 + 未下沉，P2-3）。
- theme.dart 形状/卡片/列表主题改动：卡片从旧的 `surfaceContainerLow` + 失效描边改成 `shapeLg` + `outlineStrong` + elevation 1，形状层级更清晰；`listTileTheme.shape = shapeMd` 让行圆角与卡片不同档，没有引入新的视觉冲突。
- 结论：**v15 形状与间距改动无 P0/P1 级新回归。**

**问 3 · 新发现（旧审计没抓到的用户可感知问题？）**

1. **Divider 高度裸值 8 处（20/24/28/32）**：旧审计只查了 Divider 的 `height:1` 与描边，没查「分隔线兼留白」的大高度值；它们在设置页与 repo 页制造了 4 种不同的段间距节奏（P2-1）。
2. **取色器色块 28dp 圆角**：xl 从 24→28 后，48dp 方形触控区被圆成近圆形，而内部样本已是圆形——「圆里套圆」，工具感减弱（P2-2）。
3. **`BorderRadius.circular(OgLRadius.*)` 10 处**：令牌值对了但与文件自定的「一律用 c* 工厂」纪律不一致，属于可维护性缺口，非用户可感知缺陷（P2-4）。
4. **`OgLWindowWidths.contentMax` 与窗口断点语义混装且零消费**：文件注释承诺的「限宽下沉」仍是 TODO，宽屏阅读宽度策略实际未落地（P2-3）。

---

## 7. 已检查清单（收窄范围内全覆盖声明）

- [x] `/root/OhGithubLost/docs/UI_AUDIT_V2_BRIEF.md` 全文（强制纪律、三问、覆盖要求）
- [x] `/var/minis/skills/material-3/SKILL.md` **仅 Shape Tokens 节**（Design Token System → Shape Tokens 表，含 Expressive 扩展档）
- [x] `lib/surface/util/og_l_radius.dart` 全文（94 行，六档 + 工厂 + IconSize 附注）
- [x] `lib/surface/util/og_l_space.dart` 全文（70 行，八刻度 + 别名 + 工厂）
- [x] `lib/surface/util/og_l_window_widths.dart` 全文（13 行，三常量 + 注释）
- [x] `git log -p` 中 v15 (`0851f7f`) 对 `og_l_radius.dart` 的改动（xl 24→28、工厂删除）
- [x] `rg cXl|verticalTopXl|OgLRadius.xl` → 全库用点列全（theme 4 处 + settings 1 处 + 定义 2 处），并逐点读取上下文判断尺寸影响
- [x] `rg 'OgLRadius\.circular'` → 0 处；`rg 'BorderRadius\.circular\(\s*[0-9]'` → 0 处；`rg 'BorderRadius\.circular'` → 11 行（10 用点 + 1 文档注释）
- [x] `EdgeInsets` 裸数字扫描（`lib/surface/pages/` 30 文件，163 处 → 0 裸值）
- [x] `SizedBox` 裸数字扫描（`lib/` 全库 23 处 → 分类表 + 中间值缺口判定）
- [x] `Divider(height:)` 全库扫描（20/24/28/32 共 8 处裸值）
- [x] 跨页一致性抽查：列表行（设置/关于/用户 + 数据页 ListTile + 动态流）、页头（issue/pull/repo）、卡片圆角（theme + 38 处 Card 中的覆写点）
- [x] 旧审计 `docs/UX_CROSS_AUDIT/1-A-layout-density.md` / `1-C-list-density.md` / `2-B-borders.md` 相关条目逐条比对当前代码（闭环核对表）
- [x] 文档戳、P0/P1/P2、三问回答、已检查清单齐备
