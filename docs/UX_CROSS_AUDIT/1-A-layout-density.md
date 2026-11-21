# 批 1 · A 席 —— 全页面网格与间距节奏审计（布局密度）

> 文档戳
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`；CHANGELOG 14.0.0 / 2026-11-20）
> - 更新时间：**2026-11-22 00:12:49 (Asia/Shanghai)**
> - 审计范围：`lib/surface/pages/*.dart`（30 个页面文件）+ 页面直接依赖的间距/列表基元（`lib/surface/util/og_l_space.dart`、`lib/surface/widgets/flat_list.dart`、`lib/surface/widgets/settings/settings_group.dart`、`lib/surface/app/client_shell.dart`）
> - 基准文档：`/root/OhGithubLost/docs/UX_CROSS_AUDIT_BRIEF.md`、`/var/minis/skills/material-3/SKILL.md`（Layout / Components 节，8dp 间距体系）、`/var/minis/skills/sota-frontend-design/rules/02-layout-spacing-responsive.md`（§1 4/8 栅格、proximity 律、§2 网格优先）
> - 性质：**只读审计**。本报告未修改任何业务代码，未 commit / 未 push。
> - 复现方式：所有证据均为 `file:line`，可用 `rg -n "<片段>" lib/surface/<路径>` 复现。

---

## 0. 结论摘要（先说「空」从哪来）

用户的「空」**不是** 8dp 体系被大面积破坏 —— 恰恰相反，本库的间距令牌化做得相当彻底（30 页共 **532 处** `OgLSpace.*` 引用，仅 **4 处** 字面量逃逸）。「空」来自三个结构性原因：

| # | 结构性原因 | 量化 | 用户感受 |
|---|---|---|---|
| A | **内容起始内缩叠加**（页面 padding + 卡片 + 卡片内 padding 三层嵌套） | 详情/表单类页面正文距屏幕边 **32–48dp** | 「浮」「飘」「不像贴在屏幕上」 |
| B | **页面级水平内边距四档并存**（12 / 16 / 24 / 32） | 30 页里出现 **4 种** gutter；同一 App 内跨页切换内容宽度跳变 | 「粗糙」「不是一套东西」 |
| C | **首屏被"头部块"吃满**（引导页 / 议题详情 / 协议页 / 登录页） | 议题详情页 **0 条评论**入首屏；引导页 **1 张卡**入首屏 | 「空」「一屏没东西」 |

**全库平均一屏可见条目数 ≈ 5.1 条/屏**（30 页平均；纯数据列表页 8–11 条，纯表单/详情页 1 条）。参考值：GitHub 网页端仓库文件列表 ≈ 18–22 条/屏。

**留白占比估算口径**：`(行块总高 − 文字/图标实际占用高) / 行块总高`，按 M3 默认 `ListTile`（title 24 + subtitle 20 + 垂直内边距 16）与 `Card`（`OgLSpace.md` = 12 内边距）推算；**为估算值，误差 ±5%**，用于排序而非精确断言。

---

## 1. 逐页间距数据表（30 页全覆盖）

符号说明：`gutter` = 页面水平内边距；`row` = 主列表行块；`vis` = 一屏可见条目估算；`gap` = 组内/组间垂直间距；`blank` = 留白占比估算。

| # | 页面（file） | gutter | 主节奏 / 关键间距值（出现次数） | row 高 | vis | blank | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | about_page.dart | 16 | lg×9, xl×2, md, sm×2, xxs×2 | 72（OgLFlatTile） | 10 | 30% | 节奏最健康的一页 |
| 2 | action_log_page.dart | 12 | md×10, sm×3；Card padding md(449) | 88（Card+ExpansionTile） | 9 | 35% | 卡内 12 与列表 12 叠加 |
| 3 | action_run_page.dart | 16 | lg×7, sm×5, md×2, xl | 96（Card lg 内 ListTile） | 2 | 45% | 双层 16 |
| 4 | code_editor_page.dart | 12 | md×4, xxs×4, sm | 编辑区 | ~1 | 15% | 工具栏 md/xxs |
| 5 | commit_page.dart | 16 | lg×8, md×3, sm×2, xl | 1 提交卡 | 1 | 45% | lg 页面 + md 卡内 |
| 6 | dashboard_page.dart | 0（裸 ListTile 16 内建） | md×2, lg×2 | **88**（2 行副标题 509-513） | **6** | **40%** | 一屏仅 6 条仓库 |
| 7 | download_manager_page.dart | 12 | sm×7, md×5, xxs×2, lg | 120（任务卡） | 6 | 38% | 卡内 12/12/8/8 不对称 |
| 8 | drafts_page.dart | 0（裸 ListTile） | —（页面零间距令牌） | 72 | 11 | 28% | 与 repo 页 gutter 不一致 |
| 9 | file_preview_page.dart | **32** | xxl×3(379/541/648), xl×2, md×4 | 内容区 | ~1 | 40% | 三处 32 全向内边距 |
| 10 | gist_detail_page.dart | 16 | lg×3, sm×4, xxs×4, md, xl | 72 | 8 | 35% | |
| 11 | gists_page.dart | 0（裸 ListTile） | —（零令牌） | 72 | 11 | 28% | 分隔线全宽，与别页不齐 |
| 12 | issue_page.dart | 16 | lg×11, sm×19, md×7, xl | **头部块 ~420dp** | **2–3** | **50%** | 首屏 0 条评论 |
| 13 | legal_text_page.dart | 12 | md×4, lg×3, xl, sm | 顶部 3 横幅 ~156dp | 1 | 45% | 正文起点 ≈200dp |
| 14 | login_page.dart | 16 | lg×7, md×8, sm×4 | 1 表单 | 1 | 45% | 16+16=32 叠加 |
| 15 | network_page.dart | 16 | lg, xl（尾部 24 死区） | 72 | 9 | 35% | 底部双重留白 40 |
| 16 | new_gist_page.dart | 16 | lg, md×2, sm×2 | 1 表单 | 1 | 40% | |
| 17 | new_issue_page.dart | 16 | lg×2, md×3 | 1 表单 | 1 | 40% | |
| 18 | new_release_page.dart | 16 | lg×2, md×5 | 1 表单 | 1 | 42% | |
| 19 | new_repo_page.dart | 16 | lg×2, md×4 | 1 表单 | 1 | 40% | |
| 20 | notifications_page.dart | 16 | md×7, sm×4, xxs×2, lg | 104（16/12/8/12） | 7 | 38% | 左右 16 / 右 8 不对称 |
| 21 | onboarding_page.dart | **24** | xl×7, lg×7, sm×12, md×5 | 1 卡 | **1** | **55%** | 全库最"空" |
| 22 | profile_page.dart | 16 | lg×7, md×2, xxs×3, xl, sm | 72 | 9 | 32% | |
| 23 | pull_page.dart | 16 | lg×8, md×3, sm×2, xl | 1 PR 卡 | 1 | 45% | |
| 24 | release_detail_page.dart | **24** | xl×4, lg×4, md×6 | 1 详情 | 1 | 42% | gutter 与 issue 页不一致 |
| 25 | repo_page.dart | 16 | lg×20, sm×20, md×19, xxs×7, xl×3 | 72（文件）/ 56（目录） | **8** | 35% | 一屏仅 8 个文件 |
| 26 | repo_tags_page.dart | 16 | lg×3, md×2 | 72 | 8 | 35% | 两个 ListView 都 all(lg) |
| 27 | search_page.dart | 16 / 12 | xxs×16, sm×14, md×8, lg×6, xxl | 60（议题）/ 120（仓库卡） | 13 / 6 | 30% | 同页两种行密度 |
| 28 | settings_page.dart | 16 | sm×16, lg×10, md×7, xl | 72 | 7 | 35% | 入口列表本可更密 |
| 29 | settings_section_page.dart | 16 | lg×2, xl, md | 72 | 10 | 32% | 尾部 24 死区 |
| 30 | workflow_dispatch_page.dart | 16 | sm×5, lg×4, md×2 | 104（Card lg 包 ListTile） | 6 | 40% | 双层 16 |

### 留白占比排序（Top 10，最"空"）

1. `onboarding_page.dart` 55%
2. `issue_page.dart` 50%
3. `legal_text_page.dart` 45%
4. `login_page.dart` 45%
5. `commit_page.dart` 45% ／ `pull_page.dart` 45%
6. `action_run_page.dart` 45%
7. `release_detail_page.dart` 42%
8. `new_release_page.dart` 42%
9. `file_preview_page.dart` 40%
10. `new_repo_page.dart` 40% ／ `new_gist_page.dart` 40% ／ `new_issue_page.dart` 40% ／ `workflow_dispatch_page.dart` 40% ／ `dashboard_page.dart` 40%

### 水平 gutter（页面级 padding）分布

| gutter | 页数 | 页面 |
|---|---|---|
| **0**（裸 ListTile，无页面级 padding） | 3 | dashboard / gists / drafts |
| 12 (md) | 5 | legal_text / code_editor / action_log / download_manager / notifications(部分) |
| 16 (lg) | 17 | 多数页 |
| **24 (xl)** | 3 | onboarding(249,307) / release_detail(318) |
| **32 (xxl)** | 1 | file_preview(379,541,648) |

**同一 App 内出现 5 种内容起始位置** —— 这是「粗糙」最直接的来源。

---

## 2. 用户可感知问题清单（24 条，按严重度分级）

> 每条：页面 → `file:line` 证据 → 用户感受 → 修复指令（改哪个文件的哪个值、改成什么、依据哪条规范）。
> 规范依据缩写：**M3-8dp** = material-3 SKILL.md「8dp spacing system / Apply spacing tokens」；**R§1** = sota-frontend-design 02 §1（4/8 栅格、proximity：组内 gap ≤ ½ 组间 gap、gap 优于 margin）；**R§2** = 同文件 §2（网格优先、full-bleed 命名网格线、内容限宽 min(72rem,100%)）；**R§10** = 溢出/滚动纪律。

### 严重（S）—— 直接造成「空 / 漂浮」，共 8 条

---

**S1 · 一屏 0 条评论（议题详情页头部块吃满首屏）**
- 页面：`lib/surface/pages/issue_page.dart`
- 证据：`issue_page.dart:741-742`（`SliverPadding` 16/16/16/0）→ `:747` 标题 → `:748` `SizedBox(sm)` → `:749-754` 元信息 → `:756` `SizedBox(sm)` → `:757` 标签行 → `:758` `SizedBox(sm)` → `:759` 指派行 → `:760` `SizedBox(md)` → `:762` 正文 `Card` → `:764` 卡内 `EdgeInsets.all(md)` → `:774` `SizedBox(sm)` → `:776` 状态按钮 → `:784` `SizedBox(lg)` → `:785` `Divider` → `:786` 「评论」标题 → `:787` `SizedBox(sm)`；评论本体从 `issue_page.dart:806` 的 `Card` 才开始。
- 用户感受：进入议题页，**整屏只有标题和一堆按钮，一条评论都看不到**，第一反应是"页面是空的 / 没加载出来"。
- 修复指令：
  1. `issue_page.dart:741-742` 的 `SliverPadding` 顶部由 `OgLSpace.lg` 改为 `OgLSpace.md`；
  2. `:760` 的 `SizedBox(height: OgLSpace.md)` 改为 `OgLSpace.sm`；`:784` 的 `OgLSpace.lg` 改为 `OgLSpace.md`；
  3. `:762` 的正文 `Card` 改为**无卡片的纯文本区**（去掉 `Card` 包裹，保留 `Padding(EdgeInsets.symmetric(vertical: OgLSpace.sm))`），依据 **R§1**「先用间距分层，而不是加卡片/边框」；
  4. 目标：首屏可见 **≥1 条评论标题**（评论头块 ≤ 260dp）。
  - 参考值：M3 **8dp spacing system**（material-3 SKILL.md）；**R§1**。

---

**S2 · 页面 gutter 四档并存，跨页内容宽度跳变**
- 页面：全库
- 证据：`onboarding_page.dart:249` 与 `:307`（24）、`release_detail_page.dart:318`（24）、`file_preview_page.dart:379` / `:541` / `:648`（32）、`legal_text_page.dart:100` / `:124`（12）、`dashboard_page.dart:475`（**无页面级 padding**）、`repo_page.dart:2245`（16）。
- 用户感受：从仓库页（16）切到发布详情（24）再切到文件预览（32），**正文左右边界每次都变**，列表行忽长忽短 —— "这不是一套东西""粗糙"。
- 修复指令：
  1. 在 `lib/surface/util/og_l_space.dart` 增补 `static const EdgeInsets pageGutter = EdgeInsets.symmetric(horizontal: lg);`（或直接复用已有 `OgLSpace.pageHorizontal`）；
  2. `onboarding_page.dart:249/307`、`release_detail_page.dart:318` 的 `xl` → `lg`；`file_preview_page.dart:379/541/648` 的 `xxl` → `lg`；`legal_text_page.dart:100/124` 的 `md` → `lg`；
  3. `dashboard_page.dart:475` / `gists_page.dart:152` / `drafts_page.dart:219` 三处**补上** `padding: OgLSpace.pageHorizontal`（否则分隔线与图标起始位置与其他页不齐）。
  - 参考值：**M3-8dp**（统一间距令牌）；**R§1**（全站单一间距刻度）。

---

**S3 · 卡片套卡片 / 页面 padding 套卡片 padding：正文距屏幕边 32–48dp**
- 页面：`login_page.dart`、`commit_page.dart`、`pull_page.dart`、`legal_text_page.dart`、`workflow_dispatch_page.dart`、`action_run_page.dart`
- 证据：`login_page.dart:353`（`EdgeInsets.all(OgLSpace.lg)`）→ `:357`（`Card` 内又 `all(OgLSpace.lg)`）→ `:477`（第三个 `all(OgLSpace.lg)`）；`commit_page.dart:107-108`（页面 16）+ `:115`（`Card` 内 `all(OgLSpace.md)`）；`pull_page.dart:123-124` + `:141`；`workflow_dispatch_page.dart:437`（`all(lg)`）+ `:441`（内含 `ListTile`）；`legal_text_page.dart:101`（`md`）+ `:169`（`xl`）+ `:176`（`lg`）。
- 用户感受：表单框、提交按钮、文字全部**缩在屏幕中央一小块**，四周大片空 —— "漂浮""空"。
- 修复指令：
  1. `login_page.dart:353` 的 `all(lg)` 改为 `EdgeInsets.symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.md)`；`:357` 与 `:477` 的 `Card` 内 `all(lg)` 改为 `all(OgLSpace.md)`；
  2. `commit_page.dart:115`、`pull_page.dart:141` 的 `all(md)` 保留，但**页面级** `:107`/`:123` 改 `EdgeInsets.fromLTRB(OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.lg)`；
  3. `workflow_dispatch_page.dart:437` 的 `all(lg)` → `EdgeInsets.symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.sm)`（行间距交给 `ListTile` 的 `dense`）；
  4. `legal_text_page.dart:169` 的 `all(xl)` → `all(OgLSpace.md)`。
  - 参考值：**M3-8dp**（间距令牌，单位统一）；**R§1**（父子同源、避免外层 margin 叠加）。

---

**S4 · 引导页首屏只有一张卡，全库最"空"**
- 页面：`lib/surface/pages/onboarding_page.dart`
- 证据：`onboarding_page.dart:307`（`ListView(padding: EdgeInsets.all(OgLSpace.xl))` = 24 四周）→ `:317`（顶部 `SizedBox(height: OgLSpace.xl)` = 24）→ `:318-319`（`Icon(size: OgLIconSize.hero)`）→ `:320`（`SizedBox(height: OgLSpace.lg)` = 16）→ `:321` 标题 → `:326`（`SizedBox(height: OgLSpace.sm)`）；同行 `:249`（进度条 `horizontal: OgLSpace.xl`）与 `:276-277`（导航条 `fromLTRB(xl, sm, xl, lg)`）。
- 用户感受：进 App 第一屏 **24(上) + 24(下) + hero 图标 + 16 + 标题**，正文只露出两三行，**"页面是空的"**；底部按钮离内容很远，滚动区像被掏空。
- 修复指令：
  1. `:307` 的 `all(xl)` → `EdgeInsets.symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.md)`；
  2. `:317` 删除顶部 `SizedBox(height: OgLSpace.xl)`（或降为 `OgLSpace.md`）；
  3. `:320` 的 `lg` → `OgLSpace.md`；`:249` 的 `horizontal: xl` → `lg`；`:276-277` 的 `xl` → `lg`；
  4. hero 图标 `OgLIconSize.hero` 降到 `OgLIconSize.avatar`（`onboarding_page.dart:319`），让首屏能露出完整段落 + 第一个设置块。
  - 参考值：**M3-8dp**；**R§1**（页面级留白属 `gapXl/gapHuge`，但组件内留白不得再叠 24）。

---

**S5 · 仓库文件列表一屏仅 8 个文件（行高 72dp，未用紧凑密度）**
- 页面：`lib/surface/pages/repo_page.dart`（代码页）
- 证据：`repo_page.dart:2584` 起的数据行 `ListTile(...)` 无 `dense` / 无 `visualDensity`；文件行带 `subtitle: Text(ghSizeText(...))`（`repo_page.dart:2600`）→ M3 `ListTile` 双行最小高 **72dp**；同页 `:2497` 面包屑、`:2501` 的过滤框 `TextField`、`:2568` 的 README tile 额外占 ~180dp。
- 用户感受：打开一个 30 文件的仓库，**滚一屏才 8 个文件**，翻找成本高、页面显"空"。
- 修复指令：
  1. `repo_page.dart:2584` 的 `ListTile` 增加 `dense: true`（→ 行高 56dp）或 `visualDensity: VisualDensity.compact`；
  2. 文件大小并入标题行右侧（`title: Row` + `Spacer`），去掉 `subtitle`，行高降至 48–56dp；
 3. `:2497` 面包屑与 `:2501` 过滤框整块**折叠为一个吸顶行**（`SliverPersistentHeader`），让列表从屏幕顶部即开始。
  - 参考值：**M3** List 组件（one-line 56dp / two-line 72dp）；**R§2**（sticky header + 内容优先）。

---

**S6 · 首页仓库列表一屏仅 6 条（两行副标题 + 尾部箭头占位）**
- 页面：`lib/surface/pages/dashboard_page.dart`
- 证据：`dashboard_page.dart:493`（`ListTile`）→ `:507-513` `subtitle: Text(_repoSubtitle(repo), maxLines: 2)` → `:512` `trailing: Icon(Icons.chevron_right)`；副标题本身是 `语言 · 星标数 · 私有 — 描述` 的拼接串（`dashboard_page.dart:522-535` `_repoSubtitle`），必然两行。
- 用户感受：首页是"我的仓库"工作台，**一屏 6 条、每条还要两行副标题 + 一个无信息量的箭头**，一眼看到的仓库太少。
- 修复指令：
  1. `dashboard_page.dart:507-513` 的 `subtitle` 由 2 行改 **1 行**（`maxLines: 1`），描述另起一行由 `Row` 承载；
  2. `:512` 的 `trailing: Icon(Icons.chevron_right)` 删除（整行可点，箭头是冗余指示），把 24dp 还给内容；
  3. 若仍需二级信息，`ListTile` 加 `dense: true`。
  - 参考值：**R§1**（信息密度优先，视觉冗余让位）；**M3** List 组件。

---

**S7 · 宽屏内容限宽 720dp（45rem），两侧大面积空白**
- 页面/外壳（影响全部 30 页的渲染宽度）
- 证据：`lib/surface/app/client_shell.dart:322-328`（`Center` + `ConstrainedBox(maxWidth: OgLWindowWidths.contentMax)`），`lib/surface/util/og_l_window_widths.dart:9`（`contentMax = 720`）。
- 用户感受：桌面/平板上把窗口拖到 2560，**内容只有中间 720，两侧是空墙**，列表行被拉成窄条、右侧全空 —— "空""没有作为工具的稳定感"。
- 修复指令：
  1. `og_l_window_widths.dart:9` 的 `contentMax` 由 `720` 提到 **960–1040**（阅读型页面如 `legal_text_page` 可单独保留 720 限宽）；
  2. `client_shell.dart:322-328` 改为**全出血命名网格**：`Row` 内 `Flexible(child: content)` + 固定右侧 320 的支撑面板（列表-详情布局），而非整体居中限宽；
  3. 列表页（`repo_page`/`search_page`/`settings_page`）在 ≥900 宽度走双列/三列（`search_page.dart:870-873` 已有双列机制，可推广）。
  - 参考值：**R§2**（`min(72rem, 100%)` = 1152px 全出血命名网格线；`auto-fill/minmax` 卡片网格）；**M3** medium/expanded 窗口档。

---

**S8 · 段落间距与组间距几乎相等，层级消失（proximity 律被违反）**
- 页面：`lib/surface/pages/issue_page.dart`
- 证据：`issue_page.dart:748`（标题后 `SizedBox(OgLSpace.sm)` = 8）→ `:756` 元信息后 `sm` → `:758` 标签行前 `sm` → `:760` 指派行后 `md` = 12 → `:774` 正文卡后 `sm` → `:784` 按钮后 `lg` = 16 → `:785` `Divider` → `:786` 「评论」标题 → `:787` 标题后 `sm` = 8。组内（标题—元信息—标签—指派）用 8/8/8/12，组间（到评论区）只有 16 —— **组间 ≈ 组内 × 1.3**，远未达到"组间 ≥ 组内 × 2"。
- 用户感受：所有文字块间距**几乎一样**，页面读不出"分组"，只剩"一盘散沙 + 空"。
- 修复指令：
  1. `issue_page.dart:748/756/758` 的 `sm` → `OgLSpace.xxs`（4，组内元素贴近），`issue_page.dart:760` 的 `md` → `sm`；
  2. `issue_page.dart:784` 的 `lg` → `OgLSpace.xl`（24，组间），`:787` 后的 `sm` → `md`；
  3. 同法核对 `repo_page.dart:2759` / `:2888` / `:3564`（`fromLTRB(lg, md, lg, xxs)` 段）与 `search_page.dart:1043`。
  - 参考值：**R§1**（"组内 gap ≤ ½ 组间 gap"；"间距比线条更便宜地传达层级"）。

### 中（M）—— 明显拖慢节奏 / 破坏一致性，共 10 条

---

**M1 · 8dp 体系逃逸：4 处字面量间距**
- 页面/位置：`download_manager_page.dart:466`（`spacing: 4`）、`repo_page.dart:4465`（`spacing: 8`）、`action_run_page.dart:616`（`spacing: 8`）、`release_detail_page.dart:428`（`SizedBox(width: 72)`）。
- 用户感受：肉眼不可见，但**后续统一调距时会漏改**，页面之间出现"差 4dp 就肉眼可见"的错位（粗糙）。
- 修复指令：分别改为 `OgLSpace.xxs` / `OgLSpace.sm`；`release_detail_page.dart:428` 的 `width: 72` 改为 `SizedBox(width: 72)` → 保持宽度但加注释来源，或改用 `OgLSpace` 组合（`lg * 4.5` 不可取；建议直接常量 `kOgLKeyColumnWidth = 72` 提到 `lib/surface/util/og_l_space.dart` 顶部）。
- 参考值：**M3-8dp**（"业务代码用语义名，不要写 8/12/16" —— `og_l_space.dart:19-24` 原文注释）。

---

**M2 · 同一列表页内两种 gutter（页面级 16 vs 卡片级 12），分隔线与图标起点错开**
- 页面：`lib/surface/pages/search_page.dart`
- 证据：`search_page.dart:94-97`（搜索框区 `horizontal: OgLSpace.lg, vertical: OgLSpace.sm`）→ `:1042-1043`（结果列表 `EdgeInsets.symmetric(vertical: OgLSpace.sm)`，**无水平 padding**）→ `:1066-1068`（行内 `horizontal: OgLSpace.lg, vertical: OgLSpace.sm`）；而仓库卡分支 `:878-882` 用 `fromLTRB(md, sm, md, lg)` + `:905` 卡内 `all(OgLSpace.xxs)`。
- 用户感受：搜索页一半的行**贴着屏幕边**，另一半缩进 12/16，切换 Tab 时左右边界跳 —— "粗糙"。
- 修复指令：`:1042-1043` 改为 `EdgeInsets.fromLTRB(OgLSpace.lg, OgLSpace.sm, OgLSpace.lg, OgLSpace.sm)`；`:878-882` 的 `md` → `lg`；`:905` 的 `all(OgLSpace.xxs)` → `all(OgLSpace.sm)`（仓库卡内 4dp 过紧，标题贴边）。
- 参考值：**R§1**（同一页面一套节奏）；**M3-8dp**。

---

**M3 · 通知行左右内边距不对称（16 / 8），行看起来"歪"**
- 页面：`lib/surface/pages/notifications_page.dart`
- 证据：`notifications_page.dart:316-318`（`EdgeInsets.fromLTRB(OgLSpace.lg, OgLSpace.md, OgLSpace.sm, OgLSpace.md)` = 左 16 / 右 8 / 上 12 / 下 12），右侧计数与箭头因此距屏幕右缘只有 8dp。
- 用户感受：通知列表右侧的"未读标记 / 评论数"**快贴到屏幕边**，与左侧 16 的起始不对称，看着像排版事故。
- 修复指令：`notifications_page.dart:316-318` 改为 `EdgeInsets.symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.sm)`；末行的计数与 chevron 之间 `:324` 的 `SizedBox(width: OgLSpace.md)` → `OgLSpace.sm`。
- 参考值：**R§1**（逻辑对称）；**M3-8dp**。

---

**M4 · 下载任务卡内边距四值不一（12/12/8/8）**
- 页面：`lib/surface/pages/download_manager_page.dart`
- 证据：`download_manager_page.dart:362-366`（`EdgeInsets.fromLTRB(OgLSpace.md, OgLSpace.md, OgLSpace.sm, OgLSpace.sm)`），卡内 `:455` 又叠 `EdgeInsets.only(top: OgLSpace.xxs)`。
- 用户感受：任务卡的标题比正文**更靠左**（12 vs 8），进度条与状态标签**更靠右**，卡内内容呈"斜"的，像没对齐。
- 修复指令：`:362-366` 统一为 `EdgeInsets.all(OgLSpace.md)`；`:455` 的 `only(top: xxs)` 删除（改由父级 `SizedBox(height: OgLSpace.sm)` 控制）。
- 参考值：**R§1**（间距来自单一刻度）；**M3-8dp**。

---

**M5 · 设置页入口行过疏（72dp/行，一屏仅 7 个入口）**
- 页面：`lib/surface/pages/settings_page.dart`
- 证据：`settings_page.dart:425-426`（`ListView` padding `lg, md, lg, xl`）+ `:513-514`（`ListTile(contentPadding: kOgLSettingsRowPadding)`，而 `lib/surface/widgets/settings/settings_group.dart:30-32` 的 `kOgLSettingsRowPadding = EdgeInsetsDirectional.symmetric(horizontal: lg, vertical: md)` = 16/12）→ 双行 `ListTile` 行高 72；`:470` 结尾还有 `Divider(height: 28)`（`:1825` 同款）。
- 用户感受：设置是**扫描型界面**（找一项点一项），却一屏只能看 7 项，且底部 28dp 的分隔线是无意义的死区。
- 修复指令：`settings_page.dart:513` 的 `ListTile` 加 `dense: true`；`settings_group.dart:30-32` 的 `vertical: OgLSpace.md` → `OgLSpace.sm`（行高降至 56–64）；`settings_page.dart:470` 与 `:1825` 的 `Divider(height: 28)` → `Divider(height: OgLSpace.lg)`。
- 参考值：**M3** List 组件（one-line 56dp）；**R§1**。

---

**M6 · 设置子页底部 24dp 死区 + 与根页重复的内边距**
- 页面：`lib/surface/pages/settings_section_page.dart`
- 证据：`settings_section_page.dart:33-37`（`EdgeInsets.fromLTRB(OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xl)`）。
- 用户感受：子页底部凭空多一截空白，滚动到底像"内容被截断了"。
- 修复指令：`:33-37` 的底部 `OgLSpace.xl` → `OgLSpace.lg`；并给 `ListView` 加 `MediaQuery.viewPaddingOf(context).bottom` 的安全区补偿。
- 参考值：**R§3c**（safe-area inset 处理）；**M3-8dp**。

---

**M7 · 网络设置页列表尾部再叠 24dp 留白**
- 页面：`lib/surface/pages/network_page.dart`
- 证据：`network_page.dart:49`（`ListView(padding: EdgeInsets.all(OgLSpace.lg))` = 16 四周）→ `:52`（尾部 `SizedBox(height: OgLSpace.xl)` = 24）。
- 用户感受：页面底部一条 40dp 的空白带，**像是没画完**。
- 修复指令：`network_page.dart:52` 删除尾部 `SizedBox(height: OgLSpace.xl)`；改由 `:49` 的 `EdgeInsets.fromLTRB(OgLSpace.lg, OgLSpace.lg, OgLSpace.lg, 0)` + `MediaQuery.paddingOf(context).bottom` 承担。
- 参考值：**R§3c**；**R§1**（不留无语义死区）。

---

**M8 · 关于页段落间距 48dp（两个 24 连续）**
- 页面：`lib/surface/pages/about_page.dart`
- 证据：`about_page.dart:261` 与 `:266`（连续两个 `SizedBox(height: OgLSpace.xl)`），其间是 `:262-265` 的 `logsAndLicenseHint` 文本；同页 `:293-295` 分组标题用 `fromLTRB(lg, md, lg, xxs)`。
- 用户感受：段落上下各 24，"关于"页读起来**一段话占一屏**，显得空且慢。
- 修复指令：`about_page.dart:266` 的 `xl` → `OgLSpace.md`；`:261` 的 `xl` → `OgLSpace.lg`。
- 参考值：**R§1**（页面级留白 `gapXl/gapHuge` 属于 section 层级，不应用于同组内两段）。

---

**M9 · 协议页顶部三条横幅 + 下拉行占满约 200dp，正文起点被推低**
- 页面：`lib/surface/pages/legal_text_page.dart`
- 证据：`legal_text_page.dart:98-101`（`Container` + `padding: all(OgLSpace.md)` 权威声明条）→ `:122-125`（第二条 `Container` + `all(md)`）→ `:135-136`（语言选择行 `fromLTRB(lg, md, lg, xxs)`）→ `:150`（`Divider(height: 1)`）→ `:171-173`（正文 `SingleChildScrollView(padding: all(OgLSpace.lg))`）。
- 用户感受：进协议页**先看到三条彩色横条**，正文要点往下翻才看到 —— 首屏"没有内容"。
- 修复指令：`:98-101` 与 `:122-125` 两条横幅合并为**一条** `ListTile`（图标 + 单行说明，右侧 `TextButton` 查看），把 `:135-136` 的语言下拉并入同一行；正文起始内缩由 `:171` 的 `all(lg)` → `fromLTRB(lg, md, lg, lg)`。
- 参考值：**M3** List（one-line 56dp）；**R§1**（proximity：同组信息不拆散）。

---

**M10 · 文件预览页三处 32dp 全向内边距**
- 页面：`lib/surface/pages/file_preview_page.dart`
- 证据：`file_preview_page.dart:379`（文件过大态）、`:541`（音频卡）、`:648`（提示态）—— 三处 `EdgeInsets.all(OgLSpace.xxl)` = 32 四周。
- 用户感受：空态/提示态被推到屏幕中央一小块，**图标与文字挤在 348dp 宽的窄条里**，四周全空。
- 修复指令：三处 `xxl` → `OgLSpace.lg`（16）；并给 `:379` 的 `Column` 加 `maxWidth` 约束而非靠内边距收窄。
- 参考值：**R§2**（用 `max-width` 而非 padding 收缩内容）；**M3-8dp**。

### 轻（L）—— 打磨项，共 6 条

---

**L1 · Actions 日志页：列表 12 与卡内 12 叠加，job 卡高 88dp**
- `lib/surface/pages/action_log_page.dart:449`（`ListView(padding: all(OgLSpace.md))`）+ `:510`（`Card` + `ExpansionTile`）+ `:534`（日志块 `all(OgLSpace.md)`）。
- 感受：日志页一屏 9 个 job，**每张卡都要点开才知道有没有内容**。
- 修复：`action_log_page.dart:449` 的 `all(md)` → `fromLTRB(md, md, md, 0)`；`:510` 的 `Card` 改为**平铺行 + 1px 分隔线**（与 `flat_list.dart:42-56` 的 `ogLFlatRows` 同款），行高 56dp，一屏 14 个。

**L2 · 工作流派发页：卡片内再套 ListTile，双层 16**
- `lib/surface/pages/workflow_dispatch_page.dart:437`（`all(OgLSpace.lg)`）+ `:441`（`ListTile`）+ `:440`（`SizedBox(height: OgLSpace.sm)`）。
- 感受：每张卡 104dp，**7 个工作流就撑满一屏**。
- 修复：`:437` 的 `all(lg)` → `EdgeInsets.symmetric(horizontal: OgLSpace.lg, vertical: OgLSpace.xs→不适用，改 sm)`；`:441` 的 `ListTile` 改 `dense: true`。

**L3 · 运行详情页卡片内边距 16 与其他页 12 不齐**
- `lib/surface/pages/action_run_page.dart:579`（`all(OgLSpace.lg)`）、`:688`（`horizontal: OgLSpace.lg`）。
- 感受：与 `workflow_dispatch_page` / `action_log_page`（12）来回切换时**卡片呼吸感不同**。
- 修复：`:579` 的 `all(lg)` → `all(OgLSpace.md)`。

**L4 · 引导页权限步：卡片内 12 + 卡片间距 0，权限条目之间无呼吸**
- `lib/surface/pages/onboarding_page.dart:358`（`Card` + `Padding(all(OgLSpace.md))`），卡片之间**没有 gap**（`for` 直接连续）。
- 感受：多张权限卡**糊成一片**，看不出分条。
- 修复：`:358` 起的 for 循环改用 `Column(spacing: OgLSpace.sm, children: [...])`（或每张卡外包 `Padding(bottom: OgLSpace.sm)`）。

**L5 · 草稿页 / Gist 页零间距令牌（页面级无 padding）**
- `lib/surface/pages/drafts_page.dart:219`、`lib/surface/pages/gists_page.dart:152`（均为裸 `ListView.separated`）。
- 感受：这两页的分隔线**通栏到屏幕边**，而 `repo_page` / `issue_page` 的分隔线内缩 16 —— 切换页面时分隔线"抽动"。
- 修复：两处 `ListView.separated` 加 `padding: OgLSpace.pageHorizontal`（`og_l_space.dart:59` 已提供）。

**L6 · 标签页两个 ListView 各自 `all(lg)`，形成双层 16**
- `lib/surface/pages/repo_tags_page.dart:195` 与 `:216`。
- 感受：标签列表与详情各自缩进 16，**视觉上像两层错位的框**。
- 修复：`:216` 的 `all(lg)` → `EdgeInsets.fromLTRB(OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.lg)`。

---

## 3. 逐页检查清单（证明每一页都查过）

> 标记：✅ 通过 / ⚠️ 有问题（编号见第 2 节） / ➖ 不适用（该页无该结构）。
> 列含义：G=页面 gutter 一致性 / T=8dp 令牌化 / R=行高与密度 / P=父子内边距不叠加 / N=段间距 proximity / C=网格与限宽 / S=安全区与尾部死区。

| 页面 | G | T | R | P | N | C | S | 备注 |
|---|---|---|---|---|---|---|---|---|
| about_page.dart | ✅ | ✅ | ✅ | ✅ | ⚠️ M8 | ➖ | ✅ | 平铺列表节奏最佳 |
| action_log_page.dart | ⚠️ M1 | ⚠️ M1 | ⚠️ L1 | ⚠️ L1 | ✅ | ⚠️ S7 | ✅ | `spacing: 4` 逃逸 |
| action_run_page.dart | ✅ | ⚠️ M1 | ⚠️ L3 | ⚠️ L3 | ✅ | ⚠️ S7 | ✅ | `spacing: 8` 逃逸 |
| code_editor_page.dart | ⚠️ S2 | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ✅ | 编辑区密度合理 |
| commit_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | |
| dashboard_page.dart | ⚠️ S2 | ✅ | ⚠️ S6 | ✅ | ✅ | ⚠️ S7 | ✅ | 一屏 6 条 |
| download_manager_page.dart | ⚠️ S2 | ⚠️ M1 | ⚠️ M4 | ⚠️ M4 | ✅ | ⚠️ S7 | ✅ | 卡内 12/12/8/8 |
| drafts_page.dart | ⚠️ L5 | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ✅ | 零令牌 |
| file_preview_page.dart | ⚠️ S2 | ✅ | ⚠️ S10 | ⚠️ S10 | ✅ | ⚠️ S7 | ✅ | 三处 32 |
| gist_detail_page.dart | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ✅ | |
| gists_page.dart | ⚠️ L5 | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ✅ | 零令牌 |
| issue_page.dart | ✅ | ✅ | ⚠️ S1 | ⚠️ S1 | ⚠️ S8 | ⚠️ S7 | ✅ | 首屏 0 评论 |
| legal_text_page.dart | ⚠️ S2 | ✅ | ⚠️ M9 | ⚠️ M9 | ✅ | ⚠️ S7 | ✅ | 三横幅 |
| login_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | 三层 16 |
| network_page.dart | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ⚠️ M7 | |
| new_gist_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | |
| new_issue_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | |
| new_release_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | |
| new_repo_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | |
| notifications_page.dart | ✅ | ✅ | ⚠️ M3 | ⚠️ M3 | ✅ | ⚠️ S7 | ✅ | 16/8 不对称 |
| onboarding_page.dart | ⚠️ S2 | ✅ | ⚠️ S4 | ⚠️ S4 | ⚠️ L4 | ⚠️ S7 | ✅ | 全库最空 |
| profile_page.dart | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ✅ | |
| pull_page.dart | ✅ | ✅ | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | |
| release_detail_page.dart | ⚠️ S2 | ⚠️ M1 | ⚠️ S3 | ⚠️ S3 | ✅ | ⚠️ S7 | ✅ | `width: 72` 字面量 |
| repo_page.dart | ✅ | ⚠️ M1 | ⚠️ S5 | ✅ | ⚠️ S8 | ⚠️ S7 | ✅ | 一屏 8 文件 |
| repo_tags_page.dart | ✅ | ✅ | ✅ | ⚠️ L6 | ✅ | ⚠️ S7 | ✅ | |
| search_page.dart | ⚠️ M2 | ✅ | ✅ | ⚠️ M2 | ⚠️ S8 | ✅ | ✅ | 同页两 gutter |
| settings_page.dart | ✅ | ✅ | ⚠️ M5 | ✅ | ✅ | ⚠️ S7 | ✅ | 一屏 7 入口 |
| settings_section_page.dart | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ S7 | ⚠️ M6 | |
| workflow_dispatch_page.dart | ✅ | ✅ | ⚠️ L2 | ⚠️ L2 | ✅ | ⚠️ S7 | ✅ | |

**跨页统一检查项（已查）**

| 检查项 | 结论 |
|---|---|
| 全页是否都用 `OgLSpace` 令牌 | ⚠️ **4 处字面量逃逸**（M1），其余 528 处均令牌化 ✅ |
| 是否存在外层 margin 叠加（margin considered harmful） | ⚠️ `search_page.dart:213` `Card(margin: EdgeInsets.zero)` ✅ 已归零；`search_page.dart:905` 卡内 `all(xxs)` 过紧（M2） |
| 8dp 刻度完整性（4/8/12/16/24/32/48/64） | ✅ `lib/surface/util/og_l_space.dart:29-36` 齐备 |
| 固定高度是否用在文本容器上 | ✅ 未发现 `height:` 硬编码文本容器；`release_detail_page.dart:428` 的 `width: 72` 是列宽非文本高度（M1） |
| 一屏信息量（30 页） | ⚠️ 平均 **5.1 条/屏**；数据列表页 8–11 条（GitHub 网页 18–22），详情/表单页 1 条 |
| 网格：是否用 auto-fill/minmax 而非断点阶梯 | ⚠️ `search_page.dart:870-873` 用 `constraints.maxWidth >= compact ? 2 : 1` 的**列数阶梯**，其余页无网格；建议改 `LayoutBuilder` + `minmax`（**R§2**） |
| 逻辑属性 / RTL | ➖ Flutter `EdgeInsetsDirectional` 仅 `settings_group.dart:30` 一处，其余用物理 `EdgeInsets` —— 左右不对称时（如 M3）RTL 会镜像错位（**R§5**） |
| 安全区 / 尾部死区 | ⚠️ `network_page.dart:52`、`settings_section_page.dart:33-37` 存在尾部死区（M7/M6） |
| 宽屏限宽 | ⚠️ 720dp 全局限宽（S7） |
| 卡片网格 / 跨卡对齐（subgrid 等价） | ➖ 本库为 Flutter 非 CSS，无 subgrid；卡片内部行高对齐靠 `Row` + `Expanded` ✅（`search_page.dart:225-234`） |
| 弹层 / 抽屉内边距 | ➖ 不在本页范围（批 1-B / 批 3） |

---

## 4. 修复优先级建议（供主会话汇总 UX_STABILITY_PLAN）

| 优先级 | 问题 | 预期收益（用户可感知） |
|---|---|---|
| P0 | S1 / S4 / S5 / S6（首屏 0 条评论、引导页空、文件列表 8 条、首页 6 条） | 直接消解「空」的主诉 |
| P0 | S2（gutter 四档统一） | 消解「粗糙 / 不是一套东西」 |
| P1 | S3 / S7（内缩叠加、宽屏 720） | 消解「漂浮」与桌面端空墙 |
| P1 | S8（proximity）+ M5 / M9 | 让层级出现、节奏变紧 |
| P2 | M1–M4 / M6–M10 / L1–L6 | 打磨级一致性 |

**量化目标（修复后可达）**
- 全库平均一屏可见条目：**5.1 → 8.5 条**（列表页 8 → 12–14 条）；
- 页面 gutter：**5 档 → 1 档（16dp）**；
- 8dp 体系逃逸：**4 处 → 0 处**；
- 详情页首屏可见评论：**0 → ≥1 条**；
- 引导页首屏可见块：**1 → 2–3 块**。

---

*本报告为只读审计产物：未修改 `lib/` 下任何代码，未执行 commit / push。*
