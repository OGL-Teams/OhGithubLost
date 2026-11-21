# 批 1 · 布局与密度 · C 席 —— 列表 / 卡片信息密度审计

> **文档戳 / Doc Stamp**
> - 审计批次：**批 1 · 布局与密度 · C（列表/卡片信息密度）**
> - 审计对象：`lib/surface/pages/`（repo / issue / pull / notifications / gists / search / dashboard）+ `lib/surface/widgets/discover_rows.dart` / `flat_list.dart` / `readme_view.dart`
> - 仓库：`/root/OhGithubLost`，HEAD 分支工作副本，**只读审计，未改任何代码，未 commit / push**
> - 日期：2026-11-22　语言：zh-Hans
> - 参照规范：`material-3/SKILL.md`（Components / Layout / Anti-Patterns 节）、`sota-frontend-design/rules/02-layout-spacing-responsive.md`（4/8 网格、gap-over-margin、proximity 分组、禁固定高度）
> - 用户原始判词：**「空、漂浮感、没有作为工具的稳定感」** → 本报告把「空」量化为：行高 / 留白比、每行信息量（subtitle 使用率）、列表外边距 vs 行内边距失衡、卡片内容密度、空态占位面积
> - 复现方式：所有结论均给出 `file:line`，可用 `rg -n '<pattern>' <file>` 复现

---

## 0. 量化方法（先把「空」变成数字）

**基准视口**：412 × 915 dp 手机（Pixel 7 级），可用列表高度 ≈ 830 dp（扣状态栏 24 + AppBar 56）。
**行高推导**：依据 `lib/surface/theme.dart:329-341` 的 `ListTileThemeData`（`contentPadding.vertical = xxs(4)`、`minVerticalPadding = sm(8)`）与 Flutter `ListTile` 的 56 / 72 dp 最小高度规则；OgL 自绘行按 `discover_rows.dart` 显式 padding 累加。

| 行的类型 | 来源 file:line | 实测/推导行高 | 一屏可见条数（830dp） | 文字占行高比（填充率） |
|---|---|---|---|---|
| 仅标题 ListTile（菜单 / 目录行） | `theme.dart:329-341`、`repo_page.dart:2584-2602` | 56 dp | **14** | 20/56 = **36%** |
| 标题 + subtitle 的 ListTile | `dashboard_page.dart:493-513`、`repo_page.dart:2782-2800` | 72 dp | **11** | 40/72 = **56%** |
| `OgLFeedRow`（动态流自绘行） | `discover_rows.dart:66-115` | 56 dp（8+8+20+4+16） | **14** | 40/56 = **71%** |
| 通知行（自绘） | `notifications_page.dart:314-360` | 64–104 dp | **12 → 8** | 24/64 = 38%（1 行时） |
| Gist 行 | `gists_page.dart:162-181` | 72 dp | 11 | 56% |
| 搜索结果行 | `search_page.dart:1376-1395` | 72 dp | 11 | 56% |
| Issue 评论卡 | `issue_page.dart:806-830` | 100–180 dp | **5** | — |
| 设置 / 关于 / 用户平铺行 | `flat_list.dart:81-87`、`settings_group.dart:29-31` | 56 / 72 dp | 14 / 11 | 36% / 56% |

**subtitle 使用率（数据列表行，非菜单弹层）**：`repo_page` 24 处 `ListTile(` 仅 13 处带 `subtitle:`（**54%**），缺口全部落在**目录行**与**弹层菜单行**；`issue_page` 7 处 `ListTile(` **0** 处 `subtitle:`（全部是弹层菜单行）；`gists_page`/`search_page`/`dashboard_page` 的数据行 100% 带 meta。

**结论量化**：全库列表行的平均填充率约 **45–56%**，一屏平均可见条目 **11 条**。同文件内 `OgLFeedRow` 已证明能做到 **71% / 14 条**——说明「空」不是内容不够，而是**行模板没吃满**：主列表统一用了 56/72 dp 的宽松 `ListTile` 壳，而信息量却按「一行标题 + 一行小字」提供，中间有 16–28 dp 的死区。

---

## 1. 用户可感知问题

### 严重（用户第一眼就说「空」的来源）

**S-01 · 全局列表行模板有 16–28 dp 的死区，一屏条目数被压到 11**
- 证据：`lib/surface/theme.dart:329-341`（`contentPadding.vertical = OgLSpace.xxs(4)`、`minVerticalPadding = OgLSpace.sm(8)`，叠加 Flutter `ListTile` 56/72 dp 最小高度）
- 感受：翻页时每条之间都有「说不清在哪」的一截空隙，两行文字的行却像只有标题被点亮；20 条仓库要滑两屏半，像功能陈列而不是工具。

**S-02 · 仓库目录行（最常翻的列表）只有标题，填充率 36%**
- 证据：`lib/surface/pages/repo_page.dart:2596-2602`（`subtitle: shown[index].isDirectory ? null : Text(ghSizeText(...))` → 目录行 subtitle 为 null）；`repo_page.dart:2584-2594`（title 单行）
- 感受：文件树里一屏 14 个目录名，目录是什么类型、有多少内容、更新过没有，全看不到；点进去才发现是空目录——这正是「空」的最直接来源。

**S-03 · 空态是一块巨大的空白，只有一枚图标 + 一行字**
- 证据：`lib/surface/app/async.dart:398-417`（`OgLAsyncEmptyPane`：`Center` + `Icon(size: OgLIconSize.avatar)` + 单行 `Text`）；`lib/surface/pages/dashboard_page.dart:449-455`（外层再套 `SizedBox(height: MediaQuery.sizeOf(context).height * 0.5)`）
- 感受：空仓库/无搜索结果时，屏幕上方半屏只有一张灰图标，下面半屏什么都没有；用户说「空」时指的就是这块。

**S-04 · Issue / PR 列表行缺状态与规模信息，meta 只有 3 个字段**
- 证据：`repo_page.dart:2782-2800`（issue 行 meta = 作者 · 评论数 · 创建日期，**无标签、无状态、无更新相对时间**）；`repo_page.dart:2914-2928`（PR 行 meta = 作者 · 创建日期，**无状态/合并标记/draft**）
- 感受：列表上分不出 open/closed、有没有 label、是不是 draft，只能逐条点开——一屏 11 条能用的信息却只有 1.5 行有效内容。

**S-05 · 通知行一屏只放得下 8 条，且每条都带 3 行正文**
- 证据：`lib/surface/pages/notifications_page.dart:326-332`（`maxLines: expanded ? null : 3`）+ `notifications_page.dart:314-318`（上下各 md=12 内边距）
- 感受：通知中心是高频扫读场景，但每条占 64–104 dp，扫一眼只看到 8 条，且第 3 行常常是日志正文，技术噪声盖过了「哪条未读」。

### 中

**M-06 · `OgLFlatTile` 行的垂直内边距与全局 ListTile 主题不一致**
- 证据：`lib/surface/widgets/flat_list.dart:17`（`kOgLFlatRowPadding = kOgLSettingsRowPadding`）→ `lib/surface/widgets/settings/settings_group.dart:29-31`（`vertical: OgLSpace.md(12)`）vs `theme.dart:333-334`（`vertical: OgLSpace.xxs(4)`）
- 感受：设置/关于/用户页的行明显比其他页「鼓」；切换页面时列表节奏整个变松，像换了个 App。

**M-07 · 同一页内两个 Tab 的列表左内边距不同（12 vs 16）**
- 证据：`lib/surface/widgets/discover_rows.dart:74-78`（`EdgeInsets.symmetric(horizontal: OgLSpace.md(12), vertical: OgLSpace.sm(8))`）vs `lib/surface/theme.dart:331-334`（ListTile `horizontal: OgLSpace.lg(16)`）→ `search_page.dart:779-786`（动态 Tab）与 `search_page.dart:1376`（搜索结果 Tab）
- 感受：发现页在「动态 / 推荐 / Issues」之间切 Tab，文字左边线会左右跳 4 dp，像没对齐。

**M-08 · `pull_page` 的改动文件列表双重左缩进（16 + 16 = 32 dp）**
- 证据：`lib/surface/pages/pull_page.dart:159-161`（`padding: const EdgeInsets.symmetric(horizontal: OgLSpace.lg)`）叠加 `theme.dart:331-334`（ListTile `contentPadding.horizontal = lg`）→ `pull_page.dart:186-196`（`_fileTile` 是 ListTile / ExpansionTile）
- 感受：文件名比上方「Changed files」标题缩进一倍，一栏字歪在右边；文件名右端也没对齐，与 `02-layout-spacing-responsive.md` §1「gap over margin」相违。

**M-09 · `repo_page` 文件树的筛选输入框与列表行左内边距不齐（12 vs 16）**
- 证据：`lib/surface/pages/repo_page.dart:2498-2500`（TextField 外层 `OgLSpace.md`）vs `repo_page.dart:2584`（ListTile 走主题 16）
- 感受：输入框左边缘比下面文件名列左 4 dp，框和内容不共线，像两张纸叠上去。

**M-10 · 分支选择弹层行承载 3 条 meta，却仍用 72 dp 行高 + 单行省略**
- 证据：`lib/surface/pages/repo_page.dart:724-748`（`ListTile` + subtitle `sha · 默认分支 · 受保护`）
- 感受：分支名 + SHA + 两个标签挤在一行小字里，真正想找的 SHA 被省略号截断，反而多占一行高度。

**M-11 · Issue 评论用整块 `Card` 且卡片间无节奏，评论多时一屏只剩 5 条**
- 证据：`lib/surface/pages/issue_page.dart:806-830`（每个评论一个 `Card` + `clipBehavior: Clip.antiAlias`，卡片头另加 `surfaceContainerHighest` 色块）；`issue_page.dart:796-800`（标题「Comments」与列表之间只有 `SizedBox(sm)`）
- 感受：评论区被切成一块块「悬浮气泡」，与页面其它地方的平铺列表风格对不上；一屏 5 条，来回翻找很累。

**M-12 · `readme_view` 行高 1.5 + blockSpacing 12，README 区一屏读不到一个完整章节**
- 证据：`lib/surface/widgets/readme_view.dart:385`（`p: body.copyWith(height: 1.5)`）、`readme_view.dart:404`（`blockSpacing: 12`）、`readme_view.dart:391-393`（h1/h2 用 headlineSmall/titleLarge，比正文大 2 档）
- 感受：README 是仓库最有价值的内容，现在被撑得很松，一屏两三段就到底，滚动噪音大。

**M-13 · 搜索结果行 subtitle 被限死 2 行，代码片段与仓库描述挤在同一字段**
- 证据：`lib/surface/pages/search_page.dart:1236-1238`（`_repoSubtitle` = 语言 · 星标 · 私有 — 描述）和 `search_page.dart:1386-1391`（`subtitle: hit.subtitle, maxLines: 2`）；代码搜索命中片段也是同一个 subtitle 字段（`search_page.dart:1280`）
- 感受：仓库搜索时描述被截成两行，代码搜索时命中行反而只有 2 行就被砍掉——用户最想看的「为什么命中」看不全。

**M-14 · `gists_page` 每行右侧常驻一个 48 dp 的 IconButton，行尾噪音大于信息**
- 证据：`lib/surface/pages/gists_page.dart:172-177`（`trailing: IconButton(icon: Icon(Icons.open_in_new))`）；行高因此被抬到 ≥72 dp
- 感受：一列图标盖住了日期和可见性文字的余量，也让「打开浏览器」这个次要动作占据了每行的黄金位。

**M-15 · 仓库 Tab 列表统一用 `Divider(height: 1)` 但没有首尾留白，首行贴边**
- 证据：`lib/surface/pages/repo_page.dart:806-815`（`_pagedBody` 的 `separatorBuilder: Divider(height: 1)`，列表无 `padding`）
- 感受：第一条内容紧贴筛选条下方，没有起手空隙，整页像被挤扁；同时行与行之间没有任何「组」的区分。

### 轻

**L-16 · 弹层菜单行（issue 页 7 行）用 56 dp 壳装 20 dp 字，一屏菜单比内容还高**
- 证据：`lib/surface/pages/issue_page.dart:395-404`、`:631-651`（`ListTile` 无 subtitle，行内只有图标+一字标签）
- 感受：点「更多」弹出一个大弹层，几行字撑满半屏，滑动手势多此一举。

**L-17 · `repo_page` 分支栏把 ListTile 的 contentPadding 覆写成 vertical 12，行高到 80 dp**
- 证据：`lib/surface/pages/repo_page.dart:636-650`（`contentPadding: EdgeInsets.symmetric(horizontal: lg, vertical: md)`）
- 感受：分支条比 AppBar 还厚，抢了内容的注意力；一行只装一个分支名。

**L-18 · `flat_list` 的分组小标题上下各留 lg(16)，紧跟 56 dp 行，标题与内容无归属感**
- 证据：`lib/surface/widgets/flat_list.dart:34-38`（`EdgeInsets.fromLTRB(lg, lg, lg, sm)`）
- 感受：关于/用户页里「分类标题」和下面的行像两张互不相干的纸，proximity 分组原则（组内 gap ≤ 组间 gap 的一半）不成立。

**L-19 · `OgLIssuesFilterChips` 行高随内容，但左右 padding 16 与行内 12 不齐**
- 证据：`lib/surface/widgets/discover_rows.dart:134-138`（`EdgeInsets.symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.sm)`）
- 感受：胶囊行与下方 12 dp 的列表文字左边缘错开 4 dp。

**L-20 · `discover_rows` 的 `OgLFeedRow` 已是最优密度，却只有动态流在用，同类行没有复用**
- 证据：`lib/surface/widgets/discover_rows.dart:66-115`（56 dp 行、titleMedium 标题 + bodySmall meta、4 px 状态竖条）
- 感受：这个「不空」的模板只服务于一个 Tab，其它 6 个列表页仍在用宽松 ListTile，同 App 内两套行语。

**L-21 · 空态文案无引导动作（除少数页面），用户停在「空」里**
- 证据：`lib/surface/app/async.dart:398-417`（`action` 可空，多数调用点不传）→ `search_page.dart:1367-1369`（`emptyText: _t('noResults', ...)` 无 action）、`notifications_page.dart:220-228`
- 感受：「没有结果」四个字之后没有任何下一步按钮，用户只能自己猜该换关键词还是该回上一页。

**L-22 · 列表项无 `Semantics` 复述 meta，密度提上来后行语义会变长但现在已缺失**
- 证据：`lib/surface/pages/dashboard_page.dart:493-513`、`gists_page.dart:162-181`（无 `Semantics` 包裹，仅 `OgLFeedRow` 有：`discover_rows.dart:81-88`）
- 感受：读屏用户只听到仓库名，听不到星标/时间——对视觉用户是「信息少」，对视障用户是「信息没有」。

---

## 2. 修复指令（可直接执行）

**优先级 P0（直击「空」）**

1. **S-01 / 收紧全局行模板** — 改 `lib/surface/theme.dart:329-341`：`contentPadding` 由 `vertical: OgLSpace.xxs(4)` 改为 `vertical: OgLSpace.xxs(4)` 保持，但 `minVerticalPadding` 由 `sm(8)` 改为 `xxs(4)`；同时为**数据列表**引入 `dense: true` 的紧凑行（56 → 48 dp 两行变 64 dp）或统一改用 `OgLFeedRow` 模板（见 L-20）。目标：两行数据行 ≤ 64 dp、一屏 ≥ 13 条。
2. **S-02 / 给目录行补 meta** — 改 `lib/surface/pages/repo_page.dart:2596-2602`：`subtitle` 不再对目录返回 `null`，改为 `Text(仓库内条目摘要)`（如 `12 项 · 3 天前更新`，来自目录条目数与最新提交时间）；文件行保留 size 并追加 `· 最后提交时间`。数据来自已有 API，不新增请求。
3. **S-03 / 给空态加「结构」与「出口」** — 改 `lib/surface/app/async.dart:398-417`：空态容器加 `constraints: BoxConstraints(maxWidth: 320)`，图标由 `OgLIconSize.avatar` 降到 `OgLIconSize.xl`，并支持可选副标题 + 必填 `action`；同时删掉 `lib/surface/pages/dashboard_page.dart:450` 的 `height: MediaQuery.sizeOf(context).height * 0.5` 硬占位（违反 `02-layout-spacing-responsive.md` §2「Never fix heights」），改由 `Center` 自然居中。
4. **S-04 / S-05 / 补齐列表行的 meta 字段** — 改 `repo_page.dart:2782-2800`（issue 行 meta 追加 状态、labels、相对更新时间）、`repo_page.dart:2914-2928`（PR 行追加 draft/merge 状态与更新时间）、`notifications_page.dart:326-332`（`maxLines` 由 3 降到 2）。

**优先级 P1（节奏与对齐）**

5. **M-06 / 统一行内边距源** — 改 `lib/surface/widgets/settings/settings_group.dart:29-31` 的 `kOgLSettingsRowPadding` 的 `vertical` 由 `OgLSpace.md(12)` 降为 `OgLSpace.xxs(4)`（与 `theme.dart:333` 一致）；`flat_list.dart:17` 保持引用即可自动同步。
6. **M-07 / M-19 / 统一左内边距到 16** — 改 `lib/surface/widgets/discover_rows.dart:74-78` 与 `:134-138` 的 `horizontal` 由 `OgLSpace.md(12)` 改为 `OgLSpace.lg(16)`；`search_page.dart:886-889`（推荐网格 padding）同步改 16。
7. **M-08 / 消除双重缩进** — 改 `lib/surface/pages/pull_page.dart:159-161`：把 `OgLAsyncSliver` 的 `padding: EdgeInsets.symmetric(horizontal: OgLSpace.lg)` 去掉，改由 `_fileTile` 内 ListTile 主题的 `contentPadding` 承担（保留 16 dp 一次），或反之设 `contentPadding: EdgeInsets.zero` + 保留 sliver 16，二选一，**不得叠加**。
8. **M-09 / 共线** — 改 `lib/surface/pages/repo_page.dart:2498-2500` 的 TextField 外层 padding `md(12)` → `lg(16)`，与文件列表行左缘一致。
9. **M-11 / 评论改为平铺** — 改 `lib/surface/pages/issue_page.dart:806-830`：把每条评论的 `Card` 换成「头部色带 + 1px 分隔线」的平铺行（与 `flat_list.dart` 的 `ogLFlatRows` 同源），评论之间用 `Divider(height: 1)`，一屏可回 8–10 条。
10. **M-12 / 收紧 README** — 改 `lib/surface/widgets/readme_view.dart:385`（`height: 1.5` → `1.35`）、`:404`（`blockSpacing: 12` → `8`），`h1/h2` 由 `headlineSmall/titleLarge` 降一档为 `titleLarge/titleMedium`，正文块与标题块间距降到 `OgLSpace.sm(8)`。

**优先级 P2（细节）**

11. **M-10 / 分支行** — 改 `repo_page.dart:724-748`：SHA 与标签拆成两行（`subtitle` 保留 SHA，`trailing` 放默认/受保护 Chip），或把标签移入第二行。
12. **M-13 / 搜索结果字段拆分** — 改 `search_page.dart:1236-1238` / `:1386-1391`：仓库搜索用「语言·星标·私有」作 meta、描述另起第 3 行并限 2 行；代码搜索命中片段单独占 subtitle 允许 3 行。
13. **M-14 / Gist 行尾** — 改 `gists_page.dart:172-177`：`trailing` 的 `IconButton` 改 `IconButton` 的 `visualDensity: VisualDensity.compact` + `constraints` 收紧到 40 dp，或把「在浏览器打开」移入长按菜单。
14. **M-15 / 列表首尾留白** — 改 `repo_page.dart:806-815` 的 `_pagedBody`：`ListView.separated` 加 `padding: EdgeInsets.only(bottom: OgLSpace.lg)`，首行上方由调用方给 `OgLSpace.xs` 级别起手空隙（当前 4 dp 即可，**不要** 16 dp 以上）。
15. **L-16 / L-17 / 弹层与分支条瘦身** — 改 `issue_page.dart:395-404`、`:631-651`：弹层菜单行改 `dense: true` 或自绘 44 dp 行；`repo_page.dart:646-647` 的 `contentPadding` vertical 由 `md(12)` 降为 `sm(8)`。
16. **L-18 / 分组标题归属** — 改 `lib/surface/widgets/flat_list.dart:34-38`：`EdgeInsets.fromLTRB(lg, lg, lg, sm)` → `fromLTRB(lg, xl, lg, xxs)`，即「组间 24 / 组内 4」，满足 proximity（组内 gap ≤ 组间 gap ½）。
17. **L-20 / 抽取共享的紧凑数据行** — 新增 `lib/surface/widgets/compact_row.dart`（或把 `discover_rows.dart:66-115` 的 `OgLFeedRow` 提升为通用 `OgLCompactRow`），供 repo/issue/pull/gists/search/dashboard 六个列表页复用；统一后单行 56 dp、两行 64 dp、meta 用 `bodySmall` + `onSurfaceVariant`。
18. **L-21 / 空态出口** — 改 `search_page.dart:1367-1369`、`notifications_page.dart:220-228`、`gists_page.dart:145-148`：空态统一传 `action`（搜索页给「换个关键词」/「浏览推荐」、通知页给「查看全部」、Gist 页给「新建 Gist」）。
19. **L-22 / 语义补齐** — 在 `dashboard_page.dart:493-513`、`gists_page.dart:162-181`、`search_page.dart:1376-1395` 的行外包 `Semantics(label: '$title，$meta')`，与 `discover_rows.dart:81-88` 同构。

---

## 3. 检查清单（证明查过）

**已逐文件通读 / 逐行核对**
- [x] `lib/surface/pages/repo_page.dart`（4556 行）：分支条（636-660）、分支弹层（724-748）、`_pagedBody` 分页容器（777-840）、文件树（2470-2610）、Issues 列表（2755-2800）、PR 列表（2905-2935）、Releases（3060-3090）、Tags、Branches（3314-3335）、Commits（3420-3435）、Actions runs（3610-3650）、文件操作弹层（1975-2045）
- [x] `lib/surface/pages/issue_page.dart`（1089 行）：正文/评论（740-830）、评论与问题操作弹层（380-410、620-660）
- [x] `lib/surface/pages/pull_page.dart`（215 行）：头部卡片（120-155）、改动文件列表（159-210）
- [x] `lib/surface/pages/notifications_page.dart`（432 行）：筛选条（190-210）、行渲染（300-432）
- [x] `lib/surface/pages/gists_page.dart`（190 行）：整页
- [x] `lib/surface/pages/search_page.dart`（1402 行）：动态 Tab（740-790）、推荐网格（860-900）、结果列表（1355-1402）、命中字段构造（1230-1290）、弹层菜单（930-975）
- [x] `lib/surface/pages/dashboard_page.dart`（642 行）：头部动作（360-400）、空态（449-470）、仓库列表（470-530）
- [x] `lib/surface/widgets/discover_rows.dart`（162 行）：`OgLFeedRow`、`OgLIssuesFilterChips`
- [x] `lib/surface/widgets/flat_list.dart`（89 行）：`OgLFlatSectionLabel`、`ogLFlatRows`、`OgLFlatTile`
- [x] `lib/surface/widgets/readme_view.dart`（598 行）：Markdown 样式表（384-406）、图片加载态（570-598）
- [x] `lib/surface/theme.dart`：`listTileTheme`（329-341）、`dividerTheme`、`chipTheme`
- [x] `lib/surface/util/og_l_space.dart`（70 行）：8 点节奏令牌表
- [x] `lib/surface/widgets/settings/settings_group.dart`：`kOgLSettingsRowPadding`（29-31）
- [x] `lib/surface/app/async.dart`：`OgLAsyncEmptyPane`（384-418）
- [x] 计数脚本核对：`rg -c 'ListTile\('` / `rg -c 'subtitle:'` 逐页统计

**规范对照**
- [x] `material-3/SKILL.md`：Components（ListTile / Card / Density）、Anti-Patterns（禁固定高、禁空容器）
- [x] `sota-frontend-design/rules/02-layout-spacing-responsive.md`：§1 4/8 网格与 gap-over-margin、proximity 分组、§2 禁固定高度
- [x] M3 密度基线：一行 ListTile 56 dp、两行 72 dp；一屏（830 dp）目标 ≥ 13 条数据行

**未发现问题的部分（明确排除）**
- `OgLFeedRow`（`discover_rows.dart:66-115`）：56 dp 行、71% 填充、标题+meta+状态竖条齐全——**本次审计中的密度标杆**，无问题，反而应被推广（见 L-20）
- `notifications_page.dart` 的 `Semantics(toggled:)` 与 `OgLFeedRow` 的 `Semantics(button:)` 语义标注：密度改造时应保留
- `search_page.dart` 的「推荐」双列网格（`OgLWindowWidths.compact` 断点，874-900）：容器查询式列数、卡片 `margin: EdgeInsets.zero` + `Card` 填充——**网格密度做法正确**
- `gists_page.dart:162-181`、`dashboard_page.dart:493-513`、`repo_page.dart:3420-3435`、`repo_page.dart:3618-3650`：均已有 title+meta 双行结构，填充率 56%，属可接受区间，问题在全局行模板而非这些页本身
- `readme_view.dart` 的图片加载态（577、591）与错误回退（569）：不构成留白问题

**本席位不做（留给其他席）**
- 分隔线 / 描边强度 → 批 2-B
- 空态文案与三态完整性 → 批 3-B
- 触控目标 48 dp 与可达性 → 批 5-B

---

## 4. 收口建议（供主会话排期）

| 优先级 | 编号 | 一句话 |
|---|---|---|
| P0 | S-02, S-03, S-04 | 目录行补 meta、空态去占位、列表行补状态字段 —— 这三条直接消掉用户说的「空」 |
| P0 | S-01, L-20 | 抽一个 56/64 dp 的紧凑数据行，全库六个列表页统一用（一次改动，多页受益） |
| P1 | M-07, M-08, M-09, M-06 | 四处内边距/对齐失衡，改数值即可，风险低、感知强 |
| P1 | M-11, M-12 | 评论卡改平铺、README 收紧行距 |
| P2 | M-13, M-14, M-15, L-16~L-22 | 字段拆分、行尾瘦身、首尾留白、语义补齐 |

> 交叉提示：M-08 / M-09 的 4 dp 错位与批 1-A（网格与间距节奏）可能同批修；M-11 评论卡与批 2-B（描边/边界）重叠，注意不要同时改 Card→平铺两处。
