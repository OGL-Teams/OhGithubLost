# UI 深度复审 · 批 2-B · 列表/详情/表单信息密度

> 文档戳：**2026-11-24 22:39:31 (Asia/Shanghai) · v15.0.0**（`pubspec.yaml:21` → `version: 15.0.0+150000`）
> 纪律：只读审计；未改代码、未 commit/push；禁读 Flutter SDK（未读取 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存源码），仅用项目 `lib/` 自身代码与规则文档。
> 依据：`/var/minis/skills/material-3/SKILL.md` Layout/Common Patterns、`references/layout-and-responsive.md`、`/var/minis/skills/sota-frontend-design/rules/02-layout-spacing-responsive.md`。
> 基线：`docs/UX_STABILITY_PLAN.md` D-01…D-14（密度 14 条）、S-02/S-03（旧 1-C 席密度行）、G-09（切页透明度/位移）；旧确证原文位于该计划 §3.3 与 `docs/UX_CROSS_AUDIT/1-C-list-density.md`、`2-C-motion.md`。

---

## 0. 结论速览

| 等级 | 数量 | 摘要 |
|---|---|---|
| P0 | 0 | 无「完全不可用 / 数据丢失 / 安全」级密度缺陷。 |
| P1 | 8 | 目录行仍只有标题；issue 详情首屏 0 评论；4 处空态 CTA 点不动；骨架只覆盖一半页面；v15 去限宽后 10/11 页宽屏无阅读限宽；固定半屏代码容器；通知行 3 行技术噪声；表单字段无分组节奏。 |
| P2 | 6 | 搜索两套 gutter 与 2 列阶梯；设置系 28dp 死区/12dp 行距；README 1.5 倍行高；资产行一卡一行；尾行 spinner 与悬浮按钮遮挡；评论输入沉底。 |

**总判**：v15 让「空态有按钮、等待有形状、宽屏不裁切」，但**没有改变列表的行模板与首屏信息量**——D-03/D-04/D-07/D-10/D-11/D-12/D-13/D-14 基本原样保留。用户从「空」变成「有出口」，但离「高效浏览」还有一段：一屏 8 行（目标 12–14）、issue 首屏 0 评论、找一条 issue 要 2–5 屏。

---

## 1. 闭环核对（逐条）

判定口径：**已修**＝当前代码不存在旧根因；**修法有问题**＝形式上改了但引入新症状/只修一半；**未修**＝旧根因逐字仍在。

| 编号 | 判定 | 证据（file:line）与说明 |
|---|---|---|
| D-01 页面 gutter 五档并存 | **修法有问题** | 主列表/详情已统一 16：`repo_page.dart:2500`、`dashboard_page.dart:414`、`search_page.dart:1347`、`release_detail_page.dart:485`、`gist_detail_page.dart:359`。但 `search_page.dart:892` 发现页网格仍用 `OgLSpace.md`(12)、`:1347` 结果页 16；`notifications_page.dart:312` 行内左右 16/8。五档→两档，**跨页跳变未消**。 |
| D-02 卡片套卡片 / 32–48dp 正文边 | **已修** | `commit_page.dart:107-115` = 页面 16 + 卡片内 12；`pull_page.dart:123-141` 同；`release_detail_page.dart:485/512` 页面 16 + 卡内 12。已无双重 16 缩进，最坏 28dp（16+12）。 |
| D-03 行 16–28dp 死区、一屏 11 条 | **未修** | `theme.dart:370-377` 仍 `contentPadding.vertical=xxs(4)` + `minVerticalPadding=sm(8)`；`gists_page.dart:166`、`dashboard_page.dart:490`、`repo_page.dart:2585`、`:2806`、`:2934` 全为无 `dense` 的 `ListTile`。项目已有 `widgets/discover_rows.dart:66-115`（71% 填充/14 条/屏）却未提升复用；`compact_row.dart` 不存在。 |
| D-04 issue 详情首屏 0 评论 | **未修** | `issue_page.dart:791-838` 头部仍是标题+meta+labels+assignees+正文 Card+关闭按钮+分隔线+「评论」标题；`:865` 起才有第一条评论。v15 在该文件只加了 CTA（diff 仅 `emptyAction`），段间距 sm/md/lg 未动。 |
| D-05 半屏空态 / 14 页无 CTA | **修法有问题** | `dashboard_page.dart:449-466` 半屏 `SizedBox` 已删并给 CTA；`async.dart:450-499` 空态 `maxWidth:320` + `OgLIconSize.xl`(24)，13 处 `emptyAction`。但 **4 处 `onPressed: null`**：`issue_page.dart:852`、`commit_page.dart:164`、`search_page.dart:1397`、`drafts_page.dart:205`——按钮看得见点不动；`async.dart:474` 的 `subtitle` 全库无调用方使用。 |
| D-06 裸转圈 / 同页两套加载 | **修法有问题** | `async.dart:371-399` 新增 `OgLAsyncSkeleton`，`async.dart:56/61` 加 300ms 防抖+最小显示，`AsyncView` loading 用骨架（`:330-333`）。但骨架只有「160×12 + 220×8」两个块，不是行骨架；`OgLAsyncSliver` loading 仍裸 `CircularProgressIndicator`（`:640-644`）；`dashboard_page.dart:484` 尾行、`search_page.dart:1389` 首屏仍裸转圈。 |
| D-07 issue/PR meta 缺状态与规模 | **未修** | `repo_page.dart:2813-2818` 仍 author·comments·date；`:2941-2944` PR 仍 `by … · 日期`；`notifications_page.dart:327` 仍 `maxLines: 3`。 |
| D-08 8dp 逃逸 / 字面量间距 | **未修（本席范围）** | `release_detail_page.dart:429` `SizedBox(width: 72)` 裸值仍在；`repo_page.dart:647` 分支条 `contentPadding` vertical `md(12)`→约 80dp；`notifications_page.dart:184/312` 12+8 混用。 |
| D-09 搜索两套 gutter / 通知不对称 | **未修** | `search_page.dart:892`(12) vs `:1347`(16)；`:1422` subtitle `maxLines:2`；`notifications_page.dart:312` `fromLTRB(16,12,8,12)`。 |
| D-10 评论整块 Card / 行距不一致 | **未修** | `issue_page.dart:865-919` 每条评论仍 `Card` + `surfaceContainerHighest` 头块 + Divider + `Padding(all:12)`；`settings_group.dart:30-32` 仍 `vertical: OgLSpace.md(12)`，`flat_list.dart:17` 直接复用它。 |
| D-11 README 一屏读不完章节 | **未修** | `widgets/readme_view.dart:385` `height: 1.5`、`:387` h2=`titleLarge`、`:404` `blockSpacing:12`，三项计划值均未变。属共享组件，本席页面（issue/pull/release/repo）全部继承。 |
| D-12 设置过疏 / 尾部死区 | **未修（顺带核对）** | `settings_page.dart:473`、`:1828` 仍 `Divider(height: 28)`；`settings_group.dart:32` vertical 12；`network_page.dart:52` 仍 `SizedBox(height: OgLSpace.xl)`。 |
| D-13 菜单/分支行高、网格阶梯、评论输入沉底 | **未修** | `repo_page.dart:647` 分支条 vertical 12；`issue_page.dart:925-958` 评论输入仍是尾部 `SliverToBoxAdapter`；`search_page.dart:886` 仍 `maxWidth >= compact ? 2 : 1` 二档阶梯。 |
| D-14 空态文案 / 游客筛选态 / Semantics | **修法有问题** | CTA 文案已入 i18n（`assets/i18n/zh/common.json` 8 个 `emptyAction*` 键），`notifications_page.dart:212-221` 有「未读」差异化文案和 `Semantics`；但 `search_page.dart:1393` 无「游客模式」区分，4 处 CTA 空回调，`dashboard_page.dart:490`/`gists_page.dart:166` 行无 `Semantics` 合并 meta。 |
| S-02 目录行只有标题（填充 36%） | **未修** | `repo_page.dart:2599` 仍 `subtitle: shown[index].isDirectory ? null : Text(ghSizeText(...))`——目录行**逐字仍是 null**，只留 1 项信息（标题）。 |
| S-03 空态半屏占位 | **已修** | `dashboard_page.dart:449-466` 已由 `ListView + OgLAsyncEmptyPane + FilledButton` 取代 `height: MediaQuery…*0.5`；`async.dart:474` 限宽 320、图标 24。残余的「假 CTA」归 D-05 记录。 |
| G-09 切 tab 半透明鬼影 / 整页横移 | **修法有问题** | `client_shell.dart:497-501` opacity 0.94、t 夹紧 [0,1] 已消鬼影；`:474` 位移压到屏宽 2%。但注释（`:489-491`「顶栏由外层持有保持静止」）与实现不符：`pages` 里的每个 `DashboardPage/SearchPage/ProfilePage/SettingsPage` 自带 `Scaffold(appBar:…)`（`:228-260`），而 `_OgLShellSlide` 包住整个 `IndexedStack`（`:325-328`），**AppBar 仍在 FractionalTranslation 子树内**，仍是整页含顶栏横移，只是幅度从「横飞」缩到 2%。 |

**闭环小计**：已修 2（D-02、S-03）；修法有问题 5（D-01、D-05、D-06、D-14、G-09）；未修 10（D-03/04/07/08/09/10/11/12/13 + S-02）。

---

## 2. v15 四项大改的密度回归

### 2.1 空态 CTA：从「空」变成「有出口」，但 4 处是假出口

- **真实有效（9 处）**：`gists_page.dart:146`、`profile_page.dart:220`、`pull_page.dart:171`、`gist_detail_page.dart:354`、`notifications_page.dart:214`、`dashboard_page.dart:455/461`、`repo_page.dart:2836/3123/3377`、`action_run_page.dart:566`、`action_log_page.dart:379`、`workflow_dispatch_page.dart:426`。点击后真的新建/刷新/清筛选/去搜索，空态从「死路」变成「下一步」。
- **假出口（4 处）**：`issue_page.dart:852`（写评论）、`commit_page.dart:164`（网页查看）、`search_page.dart:1397`（去发现）、`drafts_page.dart:205`（新建草稿），全部 `onPressed: null`。用户看到 `FilledButton.tonal` 的高辨识外形却点不动，**比 v14 的「空」更糟**——它承诺了动作却不兑现（对应 3-C/4-B 席的反馈闭环问题，本席从密度/出口角度记 P1）。
- **重复出口**：`gists_page.dart:137-149` 同页已有 extended FAB「新建」+ 空态「去新建」，两个入口指向同一 `_create`；`profile_page.dart:205-209` 顶栏 `person_add` 与空态「添加账号」同理。空态页的按钮没有减少操作步数，只增加了视觉重量（空态面板总高 ≈ 图标 24 + 12 + 文案 20 + 16 + 按钮 40 + 上下 Padding 48 ≈ **160dp**，占 800dp 屏 20%）。
- 结论：**空态从「空」变为「有用」只在 9/13 处成立**；4 处仍是「看着有用」。

### 2.2 骨架屏：结构有了，但不是「列表骨架」

- `async.dart:371-399` 的 `OgLAsyncSkeleton` 只有两个块（160×12、220×8）+ 24dp 外边距，总高 ≈ **12+8+48 = 68dp**，在 800dp 屏上留白 **92%**。旧审计 D-06 的诉求是「行高对齐 56/72dp 的列表骨架、零位移」——现在首帧从「空白 + 转圈」变为「顶部两个小灰块 + 大片空白」，**等待时仍没有内容锚点**。
- 覆盖不全：`AsyncView` 用了骨架（`async.dart:330-333`），但 `OgLAsyncSliver`（issue 评论、pull/commit 变更文件、repo 目录/issue/PR 列表）仍是裸转圈（`:640-644`），`dashboard_page.dart:484` 分页尾行、`search_page.dart:1389` 首屏同样裸转圈。
- 300ms 防抖 + 300ms 最小显示（`async.dart:56/61/129-165`）让快速请求**必现** 300ms 的空白骨架——从效率角度是负收益：原本瞬时出数据，现在每次切 tab 都先空 0.3s。

### 2.3 去限宽：顶栏锚定了，宽屏正文空了

- `client_shell.dart:317-328` 明确写着「待办：把 720 阅读限宽下沉到各页 body 内部……本批先保证顶栏锚定」。**下沉没做**。
- 实测 11 页：只有 `search_page.dart:886` 在发现页用 `LayoutBuilder` 做了 1/2 列（仍是阶梯，不是 auto-fill）；其余 10 页在 ≥1200dp 宽屏上正文全宽拉伸。按 MD3 `layout-and-responsive.md` 的 Large/Extra-large 约束（840–1040dp、正文 ≤80 字符），`issue_page.dart:813-822` 的正文 Card、`repo_page.dart` README、`release_detail_page.dart:511-521` 的说明卡在 1600dp 屏上每行远超 80 字符；同时两侧并不「满」——是**中间拉散、边缘空**的组合，仍不是工具该有的稳定密度感。
- `client_shell.dart:497-501` 2% 位移 + 0.94 透明度使切页不再「横飞」，但 AppBar 仍随页滑动（见 G-09 行），锚点漂移只减轻未消除。

### 2.4 回归结论

| 改动 | 密度变好？ | 说明 |
|---|---|---|
| 空态 CTA | 部分（9/13） | 4 处禁点、2 处与 FAB 重复；空态面板本身高 160dp，未变「紧凑」。 |
| 骨架屏 | 基本没有 | 68dp 的 2 块骨架 + 92% 留白；sliver 页仍裸转圈；300ms 强制等待。 |
| 去限宽 | 顶栏变好、正文变差 | AppBar 全宽锚定有改善，但 10/11 页宽屏正文无 840–1040dp 限制，长行难扫。 |
| 去缩放/图标层 | 与本席无直接密度影响 | 位移 2% 减少切页时的「空帧」，但 AppBar 仍在滑动子树内。 |

---

## 3. 新发现（P1/P2，旧审计未抓到或抓到但未量化）

### P1

**N-01 · 4 处空态 CTA 是「看得见点不动」的假按钮**
- 症状：`issue_page.dart:851-855`、`commit_page.dart:163-168`、`search_page.dart:1396-1401`、`drafts_page.dart:202-207` 显示 `FilledButton.tonal`/`TextButton`，`onPressed: null`。
- 根因：v15 接线批次「保留 CTA 文案与样式，onTap 待主会话/CI 裁决」，但发布时未裁决。
- 修复指令：在对应页接已存在的能力——issue 页给 `_comment` `FocusNode` 后 `onPressed: () => focus.requestFocus()`；commit 页用 `openLinkOrCopy(context, commit.html_url)`（若模型无该字段则直接删 CTA 而非留禁用按钮）；search 页 pop 到发现 tab；drafts 页先删 CTA（无新建草稿路由）。**宁可没有按钮，不要有假按钮。**

**N-02 · 骨架屏不是列表骨架，首帧 92% 留白**
- 症状：`async.dart:377-399` 两个块 160×12 / 220×8，总高 ~68dp；页面其余 730dp 空白。
- 根因：从 `search_page.dart` 抽的是「一个列表项」的骨架，被当成「整页骨架」用。
- 修复指令：给 `OgLAsyncSkeleton` 加 `itemCount`（默认 8）+ `itemHeight`（默认 72）按行重复，`OgLAsyncSliver` loading（`:640-644`）复用同一组件；dashboard 尾行/搜索首屏裸转圈同步替换。

**N-03 · 宽屏 10/11 页无阅读限宽，正文行超 80 字符**
- 症状：`client_shell.dart:317-328` 的 TODO 未落地；仅 `search_page.dart:886` 有 2 列分支。
- 根因：v15 只移除了外层 `ConstrainedBox(maxWidth:720)`，未把限宽下沉到 body。
- 修复指令：在 `lib/surface/app/og_l_page_scaffold.dart`（项目已有此组件族）或各页 body 外层加 `ConstrainedBox(maxWidth: 1040)` + `Center`，列表内容层可放宽到 1200，正文/表单/说明卡保持 840；发现页网格从 `:886` 的 2 档改 `LayoutBuilder` + 按 `maxWidth ~/ 320` 自动列数。

**N-04 · `gist_detail_page.dart:484-488` 每个文件固定 0.5 屏高**
- 症状：`SizedBox(height: MediaQuery.sizeOf(context).height * 0.5)` 包住 `OgLCodeViewer`；单个 12 行片段也吃掉 400dp（800dp 屏），一屏只能看 1.2 个文件卡。
- 根因：为规避 `re_editor` 在无界高度下断言，用了固定高度而非约束高度。
- 修复指令：改 `ConstrainedBox(constraints: BoxConstraints(minHeight: 80, maxHeight: 320))` + 内容自适应；或 `SizedBox(height: min(320, screen*0.32))` 并把 72dp 上限提为 token。直接违反 `02-layout-spacing-responsive.md` §2「Never fix heights on text-bearing containers」。

**N-05 · 通知行 3 行技术噪声 + 左右不对称，一屏仅 ~6 条**
- 症状：`notifications_page.dart:327` `maxLines: 3`；`:312` `fromLTRB(16,12,8,12)`；行高 ≈ 3×20 + 4 + 16 + 24（上下 12）= **104dp**；800dp 屏减 AppBar 56 + 筛选 56 + 底栏 80 → 608dp，可见 **5.8 ≈ 6 条**。meta 虽有 3 项（区域/时间/未读），但正文是日志技术串，扫读价值低。
- 根因：v15 未动 D-07/D-09 的这两行。
- 修复指令：`:327` `maxLines: 3 → 2`，`:312` 改 `symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.sm)`；把 `entry.toDisplay()` 全文留在展开态（已有 `AnimatedSize`），收起态只给一行人话摘要 + 级别色点。

**N-06 · 表单字段无分组节奏，评论输入沉在超长列表尾部**
- 症状：`issue_page.dart:1027-1046` 编辑对话框两字段间距 `SizedBox(12)`；`release_detail_page.dart:99-125` 五个控件（3 输入 + 2 Switch）**等距 12dp**，`SwitchListTile(contentPadding:zero)` 无 section 标签；`issue_page.dart:925-958` 评论输入在全部评论之后。issue 正文较长时，从进详情到输入框需滚 **2.5–3 屏**。
- 根因：间距系统只有单一 `gapMd`，没有「组内 8 / 组间 24」的节奏；输入区未做固定栏。
- 修复指令：release 编辑框把「标签/标题/正文」为一组（gap 12），两个 Switch 前加 `SizedBox(24)` + `Text(draft/prerelease)` 小标题；issue 评论输入提为 `Scaffold.bottomNavigationBar` 固定栏，或在 AppBar 加「跳到评论」按钮（D-13 原修复指令）。

### P2

**N-07 · 搜索页两套 gutter + 2 列固定阶梯**
`search_page.dart:892` 12dp vs `:1347` 16dp；`:886` `columns = maxWidth >= compact ? 2 : 1`，1200dp 仍只 2 列（每卡 ~600dp，README 摘要行超 80 字符）；`:1422` 结果 subtitle 2 行限死。修：统一 `OgLSpace.lg`，列数按 320dp 自动递增，subtitle 拆「meta 行 + 描述行」各 1 行。

**N-08 · 资产/提交/PR 的「一卡一行」放大留白**
`release_detail_page.dart:534-548` 每个 asset 一个 `Card` 包 `ListTile`（卡 margin 16+8 → 行间 ~24dp），6 个资产占 ~570dp；`commit_page.dart:190-205` 与 `pull_page.dart:197-216` 的 `ExpansionTile` 展开后再套 `Padding(12)` 的代码容器，形成「卡片内 12 + 页面 16」两级缩进。修：资产改 `OgLFlatTile` 平铺 + 1px 分隔线；补丁容器 `childrenPadding` 与卡内 padding 只保留一层。

**N-09 · 设置系 28dp 死区 / 12dp 行距仍在**
`settings_page.dart:473/1828` `Divider(height:28)`，`settings_group.dart:32` vertical 12（与 `theme.dart:374` 的 4 矛盾），`network_page.dart:52` 尾部 24dp。一屏设置项约 7 条，低于列表页 8–9。修：`Divider(height: OgLSpace.lg)`，`kOgLSettingsRowPadding` vertical `md→sm`，列表 `dense:true`。

**N-10 · README 行高 1.5 + h2 大字号吞首屏**
`widgets/readme_view.dart:385/387/404`：行高 1.5、h2 `titleLarge`、块距 12。README 区域在 800dp 屏只能读 ~14 行正文，`repo_page.dart` 目录首屏被 `_readmeTile()`（`:2561`）抢占。修：`height:1.35`、h1/h2 各降一档、`blockSpacing:8`。

**N-11 · 分页尾行 spinner + FAB 遮挡末行**
`dashboard_page.dart:480-486` 尾行 `Padding(all:12)+Center(CircularProgressIndicator)` 约 40dp 无文字；`:400-407` `ScrollAwareAction` 的 FAB「下滑收边只露 1/4」仍覆盖列表末行右侧。修：尾行改行内 16dp/strokeWidth:2 的进度 + 「加载更多中」文案；FAB 离列表底 `padding.bottom ≥ 80`。

**N-12 · 空态面板本身没有「首次使用」副标题**
`async.dart:474-497` 支持 `subtitle` 但全库无调用方传入；`gist_detail_page.dart:352-357` 只有 `noFiles` + 刷新按钮，没说「这个片段还没有文件，去新建」。修：按 D-14 原计划给 14 页传 `subtitle`，文案「还没有 X —— <一句话说明>」。

---

## 4. 用户满意度：天天用，够不够快？

**浏览效率判词：不够。** 按 800dp 高、bottom nav 80dp、AppBar 56dp（≈664dp 内容区）实测：

- 首页仓库列表：72dp/行 → **8–9 条/屏**（`dashboard_page.dart:490`，2 行 subtitle + chevron）。
- 仓库目录：目录行 56dp/行 → **~11 条**，但每行只有标题；文件行 72dp → **~9 条**，文件只有大小。
- issue/PR 列表：72dp/行 → **~9 条**（`repo_page.dart:2806/2934`），issue 3 项 meta 但无状态/labels，PR 仅 2 项。
- issue 详情：**首屏 0 条评论**；评论卡 ~120dp → **~5 条/屏**；评论输入框在全部评论之后。

**「找一条 issue 要看几屏」**：从首页算起——首页翻 1–2 屏找到仓库 → 仓库页切 issue tab → 列表若不在首屏再翻 1–3 屏 → 打开详情后首屏 0 评论，需再滑 1–2 屏才读到讨论、2.5–3 屏才到输入框。**合计 2–5 屏（常见 3–4 屏）**。对比项目自己的 `OgLFeedRow`（`discover_rows.dart:66-115`，14 条/屏、含标题+meta 两项），列表页效率只有现有能力的 ~60%。用户要的是「一屏扫完 12 条、点开就看到讨论」，现在是「一屏 8 条、点开还是空一半」。

**首次/等待/操作后/出错/长期/跨页六维中的本席部分**：首屏有 SegmentedButton 和内容锚点（合格）；等待只有 68dp 骨架（不合格）；写操作 CTA 4 处空回调（不合格）；空/错误文案已区分但游客态没有（部分合格）；长期浏览密度 8–9 条/屏（不合格）；11 页中 6 页原生 AppBar、5 页 OgLAppBar，行模板三种（ListTile / OgLFlatTile / 自建 Card），跨页节奏不一致（部分合格）。

---

## 5. 本席对三问的回答

**问 1 · 旧确证修好了吗？**
密度相关 17 条（D-01…D-14 + S-02 + S-03 + G-09）：**已修 2、修法有问题 5、未修 10**。真正落地的只有「删 dashboard 半屏占位」「统一表单/详情页面 gutter」；最核心的 D-03（行模板）、D-04（issue 首屏）、D-07（meta）、D-10（评论卡）、S-02（目录行）**一条都没动**。G-09 的透明度修好了，但注释声称的「顶栏静止」没实现。

**问 2 · v15 大改有回归吗？**
有，且是密度方向的：① 骨架只画 2 个块（68dp），首帧留白 92%，比旧的「空白+转圈」更空；② 300ms 防抖让本可瞬开的页面必空 0.3s；③ 去限宽后 10/11 页宽屏正文无 840–1040dp 约束，长行难扫；④ 空态 CTA 13 处中 4 处 `onPressed:null`，从「空」变成「假有用」，另有 2 处与 FAB 重复。正向效果是 AppBar full-bleed、空态从半屏空白缩到 ~160dp 有出口、切页鬼影基本消失。

**问 3 · 还有什么旧审计没抓到的？**
新增 12 条：4 处假 CTA（N-01）、骨架非列表形（N-02）、宽屏限宽未下沉（N-03）、gist 文件固定半屏高（N-04）、通知行 3 行噪声+一屏 6 条（N-05）、表单等距 12dp 无分组+评论输入沉底（N-06），以及搜索两套 gutter/资产一卡一行/设置 28dp 死区/README 1.5 行高/尾行 spinner+悬浮遮挡/空态 subtitle 全库未用（N-07…N-12）。最该先修的三件：**把 4 个假按钮接真或删掉、把列表行模板降到 ≤64dp、把评论输入从列表尾提到固定栏**。

---

## 6. 已检查清单（逐页实测数据）

> 口径：屏高按 800dp、底栏 80dp、AppBar 56dp，可用内容区约 664dp；行高按 M3 `ListTile` 默认单行 56dp / 双行 72dp、dense 48/56dp 估算，`visualDensity`（`theme.dart:220`）默认 standard。数字为代码推导的静态估算，非设备渲染截帧。

| 页面 | 行模板与行高（file:line） | 一屏可见 | 行内信息完整度 | 首屏内容 / 留白 | 表单/分组 |
|---|---|---|---|---|---|
| `repo_page.dart` | 目录行 56dp 单行 `subtitle:null`（`:2599`）；文件行 72dp（`:2585`）；issue/PR 72dp（`:2806`/`:2934`）；分支条 ~80dp（`:647` vertical 12） | 目录 ~11、文件/issue/PR ~8–9 | 目录 **1 项**（仅标题）；文件 2 项（名+大小）；issue 3 项（作者/评论/日期，无状态）；PR 2 项 | 面包屑+过滤框 ~100dp + README tile 占首屏（`:2558-2561`）；目录空态 ~160dp | 目录过滤框 `isDense:true`（`:2503`）；分支弹层 3 meta 挤 1 行（D-13 未修） |
| `issue_page.dart` | 头部 328–488dp（`:791-838`）；评论卡 ~120dp/条（`:865-919`）；菜单行 56dp | 评论 **~5 条/屏** | 列表行 3 项；评论头 2 项（作者/时间） | **首屏 0 条评论**；空态面板 ~160dp，CTA 禁点（`:852`） | 编辑框 2 字段 gap 12（`:1027-1046`）；标签多选 `CheckboxListTile` 56dp/项（`:1087-1105`）；评论输入 `minLines:3/maxLines:8` 沉底（`:925-958`） |
| `pull_page.dart` | 头 ~122–300dp（`:123-155`）；文件行 72dp / ExpansionTile 72dp 收起（`:191-216`） | 文件 ~7–8 | 文件 2 项（状态/±行）；描述卡有 Markdown | 首屏能看到「变更文件」标题与 1–2 行；空态 CTA 有效（`:171`） | 无编辑表单；补丁容器 12dp 二级缩进（`:201-202`） |
| `commit_page.dart` | 头卡 ~130dp（`:113-136`）；文件行/ExpansionTile 72dp（`:184-207`） | ~7–8 | 文件 2 项；补丁按行分色 | 首屏头卡 + 标题 + 1–2 文件；空态 CTA 禁点（`:164`） | 无表单；补丁 `Padding(all:12)` + `childrenPadding 16`（`:194-199`） |
| `release_detail_page.dart` | 头 80dp + 说明卡；资产 Card + ListTile 72dp（`:534-548`）；`_assetKeyRow` 上下 4dp（`:424-431`） | 资产 ~6–7 | 资产 2 项（大小/下载数）；发布头 3 项（时间/草稿/预发布/资产数） | 首屏有说明或资产锚点；空资产仅一行文字 + 24dp padding（`:527-531`） | 编辑框 5 控件等距 12dp（`:99-125`）；详情 bottom sheet 左右 24dp + 2 个 50% 按钮（`:318-364`） |
| `gists_page.dart` | 双行 `ListTile` 72dp（`:166-187`），分隔线 1px | **~9** | **3 项**（文件数/可见性/更新时间）✅ 本批最完整行 | 首屏 9 条；空态 ~160dp + FAB 重复 CTA（`:137-149`） | 无表单；新建走独立页 |
| `gist_detail_page.dart` | 每文件卡头 ~90dp + `SizedBox(height: screen*0.5)` ≈ 400dp（`:484-488`） | **1.2 个文件/屏（最差）** | 文件头 2–3 项（名/大小/截断警告） | 首屏只能看 1 个文件的上半段；代码区固定半屏留白 | 改文件名对话框 `TextField(maxLines:20)`（`:184-190`） |
| `notifications_page.dart` | 自建行 ~104dp（`:311-320`），3 行正文 `maxLines:3`（`:327`）；筛选条 ~56dp（`:183-186`） | **~6（最差列表页）** | 3 项（级别图标/区域/时间+未读），正文是技术噪声 | 首屏筛选条 + 6 条；空态 CTA 有效（`:214`） | 无表单；展开详情 `AnimatedSize` + 全宽日志块（`:344-390`） |
| `dashboard_page.dart` | 双行 `ListTile` 72dp + chevron（`:490-513`），subtitle 2 行 | **8–9** | 3–4 项（语言/star/私有/描述） | 首屏分段 56dp + 8 条；空态 ~160dp 有 CTA；首帧 68dp 骨架（92% 留白） | 新建仓库走独立页；FAB 遮挡末行（`:400-407`） |
| `search_page.dart` | 发现页 `_RepoCard` 1–2 列（`:886`）+ 12dp gutter（`:892`）；结果 `ListTile` 72dp（`:1409-1424`），subtitle 2 行 | 结果 **~8**；发现 2 列 | 结果 2 行 subtitle（未拆 meta/描述） | 首屏分段 48 + 输入框 56；首帧裸转圈（`:1389`）；空态 CTA 禁点（`:1397`） | 搜索框 gap 12（`:1360`）；分类 chips 高度自适应（`:794`）✅ |
| `profile_page.dart` | 账号行 72dp（`:220-249`）；`OgLFlatTile` 垂直 12dp + divider（`:260-288`） | ~8 | 账号 2 项（登录/当前态）；入口 1–2 项 | 首屏账号 + 2 入口 + 危险区；空态 CTA 有效（`:220`） | 危险区 `kOgLFlatRowPadding` 12dp + 按钮（`:294-317`） |

**最差三页（密度）**：① `gist_detail_page.dart`（1.2 文件/屏，固定半屏高）；② `notifications_page.dart`（6 条/屏，3 行噪声 + 16/8 不对称）；③ `issue_page.dart`（首屏 0 评论、5 条/屏、输入沉底 2.5–3 屏）。

**未读禁区声明**：全程未读取 Flutter SDK 与 pub 缓存源码；`dart format` 未调用（只读审计无格式化需求）；未修改任何项目文件，仅新增本文档。
