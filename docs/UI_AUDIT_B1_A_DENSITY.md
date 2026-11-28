# 十批全面审计 · 批 1「UI 视觉与布局」· A 席 —— 布局与信息密度审计

> **文档戳 / Doc Stamp**
> - 审计席位：**十批 · 批 1 · A 席（布局与信息密度）**；与主 skill `sota-frontend-design` / `frontend-design` 的 density / hierarchy 判据对齐
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD **`62c5383`**
> - 更新时间：**2026-11-28 17:27:10 (Asia/Shanghai)**
> - 审计对象：`lib/surface/pages/*.dart` **30 页全覆盖**（`find lib/surface/pages -name '*_page.dart' | wc -l` = 30）；交叉参考 `lib/surface/app/async.dart`、`lib/surface/widgets/flat_list.dart`、`lib/surface/widgets/settings/settings_group.dart`、`lib/surface/util/og_l_space.dart`
> - 体系基准：**MD2**（`docs/MD2_MIGRATION_BRIEF.md`、`docs/TEN_BATCH_AUDIT_PLAN.md`）；MD3 不作验收标准
> - 方法：① Vision 接口返回 **503（Deepseek-V4.1-Flash 全部账号暂不可用）**，按任务书回退到 **Pillow 13.0 像素统计**（`/tmp/uishots/` 31 张 `*_light_390x844.png`，2× 图 780×1688，统计非背景行带、左右 gutter、底部空白、墨迹分布）；② 逐页 `nl -ba` 读码取 `file:line` 证据；③ 静态分析脚本 `/tmp/density_a_static.py` 扫 30 页构造
> - 纪律：**只读审计，未改任何代码、未 commit / 未 push**；禁读 Flutter SDK、pub 缓存（未触碰 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`）；报告独立落在 `docs/UI_AUDIT_B1_A_DENSITY.md`，不占用 B 席的 `TEN_BATCH_AUDIT_REPORT.md`
> - 边界：只报**布局密度**（一屏可见条目数 / 行高 / gutter / 空态占屏比 / 首屏信息完整度），不重复 B 席色彩投影与 C 席跨页一致性；AppBar 实现分裂等问题仅在直接影响首屏高度时提及

---

## 0. 结论速览

**一句话结论：MD2 的令牌层（OgLSpace 8dp 节奏）本身干净，但「密度策略」没有分层——全库共用一个 60dp×6 行的通用骨架、空态一律 `Center` 垂直居中、列表页首屏被头部/筛选/居中留白吃掉 30%–67%，导致 30 页里只有 `notifications` / `search_results` / `settings` 三页首屏给出 ≥6 条有效信息，其余 27 页首屏有效条目 ≤5 条。**

| 密度维度 | 实测 | 判定 |
|---|---|---|
| 一屏可见条目数（390×844 竖屏） | 通知 9 条 / 搜索结果 6 条 / 设置 7 条；其余列表页首屏 **0 条**（截图停在骨架或居中空态） | ❌ 大面积不达标 |
| 行高 | 通用骨架 60dp + 12dp 间隔 = **72dp 步距**；通知行实测 **85dp**（最坏 104dp）；MD2 单行 56 / 双行 72 | ❌ 偏松且无分型 |
| Gutter 一致性 | 页面级左边距 12 / 16 / 17 / 0 / 28 五种并存；`EdgeInsets.md`=12 与 `lg`=16 混用；`Divider(height: 28)` 脱离 8dp 刻度 | ⚠️ P1 |
| 空态占屏比 | 登录 62%、Release 详情 67%、下载管理 41%、标签 42%、首页 37% 纯空白；空态统一 `Center` 造成上方 190–310dp 无信息 | ❌ P1 |
| 首屏信息完整度 | 议题首条评论在 **362dp**（43% 屏高）、PR 274dp、提交 207dp；profile/network 首帧仅 1–2 个文字带 | ❌ P0/P1 |
| 截图矩阵可信度 | 31 张中 **12 张出现完全相同的 6 段 72dp 骨架带**，截屏仅等 40ms 异步 → 视觉回归无法覆盖稳态布局 | ❌ P1（审计基础设施） |

**问题总数：18 条（P0: 2 / P1: 11 / P2: 5）**。全部带 `file:line` 证据、用户可感知影响、可执行的修复指令。30 页已检查清单见 §3。

---

## 1. 量化基线（Pillow 像素统计，390×844 竖屏 light）

> `active_row_ratio` = 非背景行占比；`空带` = 连续无内容区域；带高为逻辑 px（设备 px ÷ 2）。截图矩阵由 `test/screenshots/screenshot_matrix_test.dart:711-715` 生成，异步等待仅 40ms + 2×200ms pump，**多数页面冻结在加载骨架或空态首帧**，这正是本席能直接观测到的「首屏」。

| 页面截图 | 内容带数 | 非背景行占比 | 底部空白 | 首屏有效条目 | 备注 |
|---|---:|---:|---:|---:|---|
| profile | 1 | 1.9% | 808dp | **0** | 仅 AppBar 标题带，整屏近全白 |
| network | 2 | 2.4% | 757dp | **0** | 仅 AppBar + 一条短标题 |
| download_manager | 5 | 8.6% | 345dp | 0 | 空态居中，无 CTA |
| repo_tags | 3 | 8.2% | 354dp | 0 | 空态为裸 `Text` |
| release_detail | 6 | 13.5% | 567dp | 0 | 资产空态后整屏空白 |
| file_preview | 4 | 13.4% | 326dp | 0 | 首帧骨架 |
| login | 4 | 26.9% | 520dp | 3 块 | 无页脚 |
| onboarding | 7 | 25.8% | 16dp | 3 块 | 中段 900 设备 px 空白 |
| dashboard / home | 6 | 26.2% | 10dp | **0** 仓库行 | 筛选条与空态间 310dp 空白 |
| action_log | 8 | 33.6% | 162dp | 6（骨架） | 4px 状态条不可见 |
| notifications | 19 | 49.5% | 0dp | **9 条** | 全库密度冠军 |
| settings | 8 | 28.9% | 68dp | **7 入口** | 行距 190dp |
| issue | 17 | 44.4% | 0dp | 5 评论 | 首评论起点 362dp |
| search_results | 9 | 36.3% | 138dp | **6 条** | 达标样本 |

---

## 2. 问题清单（按严重度 × 用户可感知度排序）

### P0-1 · profile 页首屏几乎全白：0 个可见条目，账号/草稿/Gist 入口全部看不到

**Where**
- 截图：`/tmp/uishots/profile__light_390x844.png`（Pillow：非背景行占比 **1.9%**，仅 `[40,71]` 设备 px 一个文字带 = AppBar 标题；底部空白 **808dp**；首屏可见条目 **0**）
- 代码：`lib/surface/pages/profile_page.dart:216-223`（`AsyncView` 加载/空态）、`:224-340`（数据态 builder）、`:234-274`（账号用 `Column` 全量构建，非懒加载）

**Impact**：用户点「我的」后看到一张空白页，既看不到当前账号，也看不到草稿/我的 Gist/退出登录入口。这不是"密度不够"而是**首屏信息为零**，在 390×844 上是阻断性的。账号行用 `Column` 一次构建，10+ 账号还会拖慢首帧。

**Root cause**：`AsyncView` 在 `data == null` 时统一返回 `Center(child: OgLAsyncSkeleton())`（`async.dart:315-330`），而该 `Center` 在 `Scaffold.body` 的无界高度下无法稳定给出可见骨架；数据态又把全部条目塞进一个 `Column`，首帧无法增量呈现。

**Fix**：
1. 把 `:234-274` 的 `Column(children: [for … ListTile])` 改为 `OgLAsyncSliver` 或 `ListView.separated`，账号行懒构建，行高固定 72dp（MD2 双行）。
2. 加载态不用通用 6 行骨架：在 `profile_page.dart:224` 前加 `accounts` 专用骨架（1 个标题 + 2 个 72dp 账号行 + 2 个 56dp 入口行），总高 ≤360dp 且**顶部对齐**（`padding: OgLSpace.pageHorizontalTop`），不再 `Center`。
3. 空态 `OgLAsyncEmptyPane` 加 `action`（复用已有 `FilledButton.tonal`，`:220-223`），并把整个状态区限制在首屏上 60%，底部留给页脚。
4. 验收：截图矩阵 profile 首屏非背景行占比 ≥12%、可见条目 ≥3。

---

### P0-2 · network 设置页首屏 97.6% 白：只有一个标题，任何网络项都看不到

**Where**
- 截图：`/tmp/uishots/network__light_390x844.png`（非背景行 **2.4%**，内容带仅 `[46,65]` 与 `[154,173]` 设备 px，底部空白 **757dp**，右 gutter 258.5dp 说明内容只占左侧一小截）
- 代码：`lib/surface/pages/network_page.dart:41-57`（`ListView` 里只有 `builder(context, settings)` + `SizedBox(height: OgLSpace.xl)`，**没有标题、说明、加载态、空态、错误态**）

**Impact**：用户从设置点进「网络」，看到的是一张几乎空白的页，无法判断 DNS / 下载并发 / Release 加速通道是否可改、改在哪里。首屏信息完整度为 0。

**Root cause**：页面自称"只负责壳"（`:6-7`），把全部内容委托给外部 `builder`，但没有为 builder 尚未产出内容或产出为空时提供任何兜底；`ListView` 本身也没有 padding 约束（`EdgeInsets.all(lg)` 只作用于 ListView 整体，内部子项无标题）。

**Fix**：
1. 在 `:50-53` 的 children 前插入常驻页头：`Text(_t('network'))` 的 `OgLFlatSectionLabel` + 一行说明（复用 `settings` 分片已有文案键，不新增 i18n）。
2. 包一层状态判断：`surface.settings` 未就绪时显示顶部对齐的 3 行骨架；`builder` 返回空内容时显示 `OgLAsyncEmptyPane` 并给出「返回设置」动作。
3. 把 `builder` 内容包进 `Padding(padding: OgLSpace.pageHorizontal)`，避免右 gutter 258dp 的异常瘦长排版。
4. 验收：首屏可见网络设置项 ≥2，非背景行占比 ≥10%。

---

### P1-1 · 通用骨架 60dp×6 行与真实行高脱节：全库 12 页首屏长同一副样子

**Where**
- `lib/surface/app/async.dart:376-384`（`rows = 6`、`height: 60` 注释写"落在 56-64dp 区间"）、`:404-418`（`SizedBox(height: OgLSpace.md)` 间隔 12dp）、`:423-449`（单行 36dp 圆块 + 0.7/0.45 宽文字条）
- 命中页：`dashboard_page.dart:488`、`file_preview_page.dart:223`、`legal_text_page.dart:177`、`onboarding_page.dart:364`、`repo_page.dart:832,2571`、`repo_tags_page.dart:201,226`、`search_page.dart:1389`，以及 `AsyncView` 默认加载态的 `action_log / drafts / gist_detail / gists / workflow_dispatch`

**Impact**：Pillow 统计显示 `action_log / action_run / drafts / gist_detail / gists / workflow_dispatch` 六页出现**完全一致**的 6 段 72dp 步距带（如 `[504,575]、[648,719]、[792,863]…`）。用户从不同页面感知到的是"同一张假列表"，而不是即将出现的真实内容；加载→数据的形变在通知页（85dp）、下载页（卡片 ~100dp）、Gist 详情页（Card + 文件头）都会跳变。

**Fix**：给 `OgLAsyncSkeleton` 增 `rowHeight`、`leadingSize`、`rows` 三个命名参（默认保持 60/36/6 兼容），每页按真实行型传值：通知 72dp、下载卡片 104dp、Gist 文件 88dp、设置/关于 56dp；骨架行数按 `viewportHeight / rowHeight` 计算而非固定 6。验收：12 页骨架带步距不全相同，且骨架→数据的行首 y 偏差 ≤8dp。

---

### P1-2 · 截图矩阵只等 40ms，12/31 张停在骨架态 —— 密度回归无眼睛

**Where**：`test/screenshots/screenshot_matrix_test.dart:711-715`（`await tester.pump(); await tester.runAsync(() => Future.delayed(40ms)); await tester.pump(200ms); await tester.pump(200ms);`）；`:805-822`、`:846-921` 矩阵遍历

**Impact**：A 席本次能给出的"首屏可见条目数"多数其实是**骨架态条目数**。修复代理按本报告改完后，CI artifact 仍会拍到同一批骨架，P0/P1 的密度回归无法被截图核验——这是"审计→修复→验证"闭环的断点，用户最终看到的密度问题会复发。

**Fix**：在 `_pumpScreen` 里把固定 40ms 改为**条件等待**：循环 `pump(Duration(milliseconds: 50))` 直到页面内不再存在 `OgLAsyncSkeleton`（用 `find.byWidgetPredicate` 判定），上限 3s，超时在截图文件名加 `_skeleton` 后缀并计数告警；对确实无数据的页面走 `pumpAndSettle` 后落盘稳态。同时保留一张 `_firstframe` 图做首屏空窗对照。

---

### P1-3 · 空态统一 `Center` 垂直居中：190–310dp 上方空白，首屏像"没加载出来"

**Where**
- 通用：`lib/surface/app/async.dart:540-566`（`OgLAsyncEmptyPane` 用 `Center` + `ConstrainedBox(maxWidth:320)`）、`:332-341`、`:694-700`
- 页面：`dashboard_page.dart:496-520`（`Expanded` 内直接返回空态）、`notifications_page.dart:208-221`、`search_page.dart:828-829`（`Center(child: Text(...))`）、`repo_page.dart:4355-4358`

**Impact**：Pillow 实测 dashboard 首屏内容带 `[144,207]`（筛选条）之后直接跳到 `[826,893]`，中间 **310dp 无任何像素**；用户向下扫视时先看到半屏白，才看到"暂无仓库"。MD2 列表空态应贴近内容区顶部，让"这里本该有什么"与"下一步做什么"同屏出现。

**Fix**：给 `OgLAsyncEmptyPane` 增 `alignment`/`topPadding` 可选参，列表类页面一律传 `Alignment.topCenter` + `padding: EdgeInsets.only(top: OgLSpace.huge)`（48dp）；仅详情页/全屏错误保留居中。验收：空态图标顶边距 AppBar ≤64dp，空态下方空白 ≥40% 首屏。

---

### P1-4 · 通知行 85dp（最坏 104dp）超过 MD2 72dp：全库最密的一页也在浪费纵向空间

**Where**：`lib/surface/pages/notifications_page.dart:311-343`（`EdgeInsets.fromLTRB(lg, md, sm, md)` = 上下各 12dp；`Text(entry.message, maxLines: 3, …)` `:326-329`；`SizedSpace(xxs)` + `bodySmall` 元信息 `:334-343`）

**Impact**：截图 19 个内容带、9 条通知 / 屏，行距 **85dp**（带 `[265,331]→[435,501]`，间隔 170 设备 px）。三行消息封顶时行高可达 12+60+4+16+12 = **104dp**，一屏仅 7 条。通知中心是"扫读优先"页面，用户要的是条数不是字数。

**Fix**：`maxLines` 由 3 降为 2（超长用省略号，详情可点开）；垂直 padding 由 `OgLSpace.md`(12) 降为 `OgLSpace.sm`(8)；保留 `expanded` 时全文（`maxLines: null`）。目标行高 72dp、一屏 ≥10 条。验收：截图带步距由 170 设备 px 降至 ≤144 设备 px。

---

### P1-5 · 议题页首条评论起点 362dp：43% 首屏被头部吃掉

**Where**：`lib/surface/pages/issue_page.dart:795-845`（头部 `SliverPadding(fromLTRB(lg, lg, lg, 0))` + 标题 `:802` + 元信息 `:804-810` + `_labelsRow` `:812` + `_assigneesRow` `:814` + `Card(padding: md)` 的 `ReadmeView` `:816-828` + `OutlinedButton` `:830-838` + `SizedBox(lg)` + `Divider` + 评论标题 `:839-842`）

**Impact**：截图首评论内容带从 **724 设备 px = 362dp** 才开始（前 17 个带全属头部），844dp 屏上只剩约 480dp 给评论，可见 5 条。用户点进议题第一眼看到的是元信息与按钮墙，评论区要滑半屏才见。

**Fix**：
1. 把标签/指派人行收进一个 `ExpansionTile`（默认折叠，"标签 3 · 指派 1" 一句话摘要），省 ~80dp。
2. 正文 `Card` padding 由 `md`(12) 改 `sm`(8)，正文 `ReadmeView` 首屏限高 160dp（`ConstrainedBox(maxHeight:160)` + 内部可滚），省 ~60dp。
3. 开/关按钮移入 AppBar overflow（与 PR/提交页一致），省 ~56dp。
4. 目标首评论起点 ≤200dp。验证：截图第一个评论带 y ≤400 设备 px。

---

### P1-6 · PR / Commit 页头部同样侵占首屏（274dp / 207dp），且与议题页三套密度

**Where**
- PR：`lib/surface/pages/pull_page.dart:122-155`（`SliverPadding(lg,lg,lg,0)` + 标题 `:129` + 元信息 `:131-136` + `Card(md)` `ReadmeView` `:138-149` + `SizedBox(lg)` + Divider + 变更标题 `:150-154`）
- Commit：`lib/surface/pages/commit_page.dart:106-142`（`Card(padding: md)` `:113-137` + 头部间距与标题 `:138-142`）
- 对照：`issue_page.dart:795-845`

**Impact**：三种"详情 + 文件/评论列表"页给出三种首屏起始 y（362 / 274 / 207dp），用户在同一次浏览里需要重新适应"列表从哪里开始"。PR 页只剩约 570dp 给文件列表，提交页正文 card 常把变更文件推到屏外。

**Fix**：抽 `OgLDetailHeader` 共用件（`lib/surface/widgets/`），统一：标题 → 一行元信息（单行省略）→ 正文限高 120dp → 12dp 间距 → 分隔线 → 列表标题；三页都改用它，目标列表首项起点 ≤200dp ±16dp。文件/评论行高统一 72dp。

---

### P1-7 · 页面级水平 gutter 12/16/0/28 四种口径混用

**Where**
- 16dp：`dashboard_page.dart:465-466`、`profile_page.dart:230-231`、`settings_page.dart:428-429`、`onboarding_page.dart:286-287`（`OgLSpace.xl`=24 用于 nav）
- 12dp：`notifications_page.dart:183-184`、`action_log_page.dart:327-328,342,353`、`download_manager_page.dart:259`、`legal_text_page.dart:141-142`
- 0dp（全出血）：`code_editor_page.dart:627-648`、`legal_text_page.dart:104-138`（横幅）
- 28dp：Pillow 实测 `onboarding__light_390x844.png` 左 gutter 28dp / 右 24.5dp（`:286-287` 用 `xl`=24 加上 SafeArea 偏差）

**Impact**：从 gists（左 16dp）划到通知（左 12dp）或 onboarding（左 28dp）时，文字起始线肉眼可见地跳；像素统计给出的左右 gutter 在 31 张图里出现 12 / 16 / 17 / 0 / 28 / 107.5 / 154.5 / 258.5 共 8 种数值（后三种是内容缺失导致的假 gutter，同样说明首屏异常）。

**Fix**：统一 `OgLSpace.pageHorizontal`（16dp）为**所有列表/表单/详情正文**的唯一左右边距；横幅、代码编辑区、图片预览允许全出血，但必须在页面文件头注释写明理由。把 `notifications_page.dart:183`、`action_log_page.dart:327,342,353`、`download_manager_page.dart:259`、`legal_text_page.dart:141` 的 `md` 改 `lg`。验收：`rg 'EdgeInsets\.(fromLTRB|symmetric).*OgLSpace\.md' lib/surface/pages` 仅保留卡片内部，不含页面级。

---

### P1-8 · `Divider(height: 28)` 脱离 OgLSpace 8dp 刻度，制造 28dp 非节奏间隙

**Where**：`lib/surface/pages/settings_page.dart:473`、`:1821`；对照 `lib/surface/util/og_l_space.dart:35-45`（合法刻度 4/8/12/16/24/32/48/64）

**Impact**：设置首页 7 个入口的带间距在截图里是 203→400→589→784→978→1177→1422 设备 px（约 190–245 设备 px 不等），危险区前的 28dp 分隔比其它组间隔大一档且不是 8 的整数倍，页面底部节奏"突然松一下"。这是用户能感知但说不出原因的间距漂移。

**Fix**：`const Divider(height: 28)` → `const Column(children: [SizedBox(height: OgLSpace.xl), Divider(height: 1), SizedBox(height: OgLSpace.xxs)])`（24+1+4=29）或直接 `SizedBox(height: OgLSpace.xxl)`（32）配 1px 线；两处保持一致。验收：`rg 'height: 28' lib/surface/pages` → 0。

---

### P1-9 · 登录页底部 520dp（62%）纯空白，首屏没有版本/隐私/引导入口

**Where**：`lib/surface/pages/login_page.dart:350-407`（`ListView` 从 `Card(vaultNote)` → `SizedBox(lg)` → 令牌输入 → `SizedBox(md)` → 按钮）；截图带只到 `[552,647]` 设备 px = 323dp

**Impact**：用户在小屏手机上打开登录页，输入区停在上 1/3，下面 2/3 全白，既没有"忘记令牌怎么办"也没有版本/隐私/引导说明；键盘弹出时更看不到任何上下文。首屏信息完整度差。

**Fix**：把 `ListView` 改为 `Column` + `Expanded` 的可滚内容 + 底部 `SafeArea` 页脚（版本号取 `kOgLAppVersion`、隐私/许可证入口走已有路由、引导按钮复用 `:331-336` 的 `_openOnboarding`）；页脚高度 ≤80dp，空白压到 ≤35%。

---

### P1-10 · Release 详情页底部 567dp（67%）空白，资产空态只有一行小字

**Where**：`lib/surface/pages/release_detail_page.dart:482-553`（`ListView(padding: all(lg))`；`:527-531` 资产为空时仅 `Padding(vertical: md) + Text(_t('noAssets'))`）；截图带止于 553 设备 px = 276dp

**Impact**：用户打开一个无附件 Release，看到标题、日期、"0 assets" 一行，然后整屏空白。既看不到"如何下载源码"（zip 链接），也没有回到标签/编辑的入口；首屏像加载失败。

**Fix**：资产空区替换为 `OgLAsyncEmptyPane(icon: Icons.inventory_2_outlined, text: noAssets, action: FilledButton.tonal(打开浏览器/复制 zip 地址))`，顶边限制在 header 后 24dp；资产非空时用 `SliverList.builder` 懒构建卡片（当前 `:533+` 的 `for` 会全量构建）。验收：空态首屏非背景行占比 ≥10%。

---

### P1-11 · 设置首页 7 个入口行距 190dp：一屏只能看到 4 个分类

**Where**：`lib/surface/pages/settings_page.dart:427-489`（`ListView` 里 7 个 `_entry` + `Divider(height:28)`），`:499+` `_entry` 带 icon/title/subtitle；截图 8 个带、底部空白 68dp

**Impact**：设置是"找开关"的高频路径，但副标题 + 大图标把每行撑到约 95dp，390×844 首屏只露出 4 个分类，"存储与网络 / 关于帮助 / 日志 / 危险区"要滑两屏。截图带间距 189–245 设备 px，行高明显偏松。

**Fix**：`_entry` 改 `OgLFlatTile` 风格：图标 20dp、副标题 `maxLines: 1` + `TextOverflow.ellipsis`、垂直 padding 由 `md`(12) 改 `sm`(8)，目标行高 64dp、一屏 ≥7 个入口；危险区用 `SizedBox(24) + Divider(1)` 分隔而非 28dp。

---

### P2-1 · 下载管理空态 41% 底部空白且无 CTA

**Where**：`lib/surface/pages/download_manager_page.dart:240-256`（`Center(Column(icon 48 + 12 + Text + 4 + hint))`）；截图底部空白 345.5dp

**Impact**："暂无下载"下方什么都没有，用户不知道从哪里开始下载。空态占屏比合理但信息不完整。

**Fix**：改用 `OgLAsyncEmptyPane(icon: Icons.download_outlined, text: empty, subtitle: emptyHint, action: FilledButton.tonal('去发现页'))`，action 复用首页路由；状态区顶部对齐、上下留白 ≤32dp。

### P2-2 · 仓库标签空态是裸 `Text`，42% 底部空白

**Where**：`lib/surface/pages/repo_tags_page.dart:203-209`（`Center(Padding(all: lg, child: Text(_t('empty'))))`）；截图底部空白 354dp

**Impact**：有写权限的用户看不到"创建标签"按钮，空态不给出下一步。

**Fix**：改 `OgLAsyncEmptyPane(icon: Icons.local_offer_outlined, text: empty, action: widget.canWrite ? FilledButton('创建') : null)`，action 调用已有 `_create()`。

### P2-3 · 新建表单三页底部空白 29%–54%，提交按钮藏在不同位置

**Where**
- `new_gist_page.dart:153-201`（提交在 **AppBar** `:147-150`，正文止于 `:200`，底部空白 329.5dp）
- `new_issue_page.dart:137-181`（提交在正文末尾 `:176-179`，底部空白 432dp）
- `new_release_page.dart:163-235+`（提交用 `ScrollAwareAction` 跟随滚动 `:229-235`，底部空白 248dp）

**Impact**：同类"新建"表单三套主操作位置，用户从 gist 表单切到 issue 表单会找不到提交按钮；且两页首屏内容止于 380–410dp，下面全白。

**Fix**：统一为 `AppBar` 右侧 `TextButton` 提交 + 底部 `SafeArea` 辅助说明；`new_gist_page.dart:177-187` 的 8 行代码框在 844 屏上占 368 设备 px，可降 `minLines: 6`；`new_issue_page.dart` 的按钮改为固定底部栏避免滚到底才见。

### P2-4 · 发现页推荐/议题 tab 空态退化为 `Center(Text)`，无骨架无 CTA

**Where**：`lib/surface/pages/search_page.dart:828-829`（`Center(child: Text(_t('recommendedEmpty')))`）；对照同页 `:811-826` 的错误态有 `FilledButton.tonal`

**Impact**：网络无结果时用户看到孤零零一行字，无法重试；与同页其它 tab 的空态规格不一致。

**Fix**：改 `OgLAsyncEmptyPane(icon: Icons.explore_off_outlined, text: recommendedEmpty, action: FilledButton.tonal('重试' → `_loadMoreRepos()`))`。

### P2-5 · 关于页 16 个内容带间距 67–194 设备 px，分组间隙无统一规则

**Where**：`lib/surface/pages/about_page.dart:351-371`（`_contributorsRows` 每行后 `Divider(1)`）、`:376-389`（`_diagnosticTile` 的 `tilePadding` 上下 `sm`=8、`childrenPadding` 底 `lg`=16）

**Impact**：Pillow 带起点 207→401→582→802→984→1184→1357→1552 设备 px，间隔从 67 到 194 设备 px 不等；用户扫读时分组边界忽近忽远。

**Fix**：统一走 `OgLFlatSectionLabel`（`flat_list.dart:20-36`，上 16 下 8）作为唯一分组头，ExpansionTile 的 `tilePadding`/`childrenPadding` 与之一致；去掉行尾多余 `Divider`（`ogLFlatRows` 已负责，`:42-51`）。

---

## 3. 30 页已检查清单（全部逐页读码 + 对照截图）

> 标记：✅ 达标 / ⚠️ 可改进 / ❌ 问题页；`首屏条目` 为截图矩阵首帧可见的有效信息块（骨架/空态不计为有效条目）

| # | 页面文件 | 布局类型 | 首屏条目 | 行/块高 | 页级 gutter | 空态占屏 | 结论 | 关联问题 |
|---:|---|---|---:|---|---|---|---|---|
| 1 | `about_page.dart` | 平铺列表 + ExpansionTile | 9 | 约 56–96dp | 16dp | — | ⚠️ | P2-5 |
| 2 | `action_log_page.dart` | 搜索条 + 分组日志 | 6（骨架） | 72dp 骨架 | 12dp | — | ⚠️ | P1-1/P1-7 |
| 3 | `action_run_page.dart` | 详情 + 作业列表 | 6（骨架） | 72dp 骨架 | 16dp | — | ⚠️ | P1-1 |
| 4 | `code_editor_page.dart` | 全屏编辑器 + 工具栏 | ~25 代码行 | 行高由字号定 | 0（设计全出血） | — | ✅ | —（合理例外） |
| 5 | `commit_page.dart` | 头卡 + 文件列表 | 6（骨架） | 头 207dp / 行 72dp | 16dp | — | ⚠️ | P1-6 |
| 6 | `dashboard_page.dart` | 分段筛选 + 仓库列表 | **0** | 空态居中 | 17dp | 37% | ❌ | P0-1 同类 / P1-3 |
| 7 | `download_manager_page.dart` | 任务卡片列表 | 0 | 卡片 ~104dp | 12dp | 41% | ❌ | P2-1 / P1-7 |
| 8 | `drafts_page.dart` | 草稿列表 | 6（骨架） | 72dp 骨架 | 16dp | — | ⚠️ | P1-1 |
| 9 | `file_preview_page.dart` | 预览（图/文/音频） | 0（骨架） | 骨架 60dp | 16dp | 39% | ⚠️ | P1-1 |
| 10 | `gist_detail_page.dart` | 详情 + 文件卡 | 6（骨架） | 72dp 骨架 | 16dp | — | ⚠️ | P1-1 |
| 11 | `gists_page.dart` | Gist 列表 | 6（骨架） | ListTile 56dp | 16dp | — | ⚠️ | P1-1 |
| 12 | `issue_page.dart` | 头 + 评论 sliver | 5 评论 | 头 362dp / 行 72dp | 16dp | — | ❌ | P1-5 |
| 13 | `legal_text_page.dart` | 横幅 + 长文 | ~14 行文本 | 17 设备 px 行距 | 0/12dp 混用 | — | ⚠️ | P1-7 |
| 14 | `login_page.dart` | 表单 + 安全说明 | 3 块 | 卡 114dp | 16dp | **62%** | ❌ | P1-9 |
| 15 | `network_page.dart` | 设置壳 + 外部 builder | **0** | — | 17/258dp | **90%** | ❌ | **P0-2** |
| 16 | `new_gist_page.dart` | 表单 | 4 块 | 代码框 184dp | 16/12.5dp | 39% | ⚠️ | P2-3 |
| 17 | `new_issue_page.dart` | 表单 | 3 块 | 正文框 216dp | 16dp | 51% | ⚠️ | P2-3 |
| 18 | `new_release_page.dart` | 表单 | 5 块 | 正文框 168dp | 16dp | 29% | ⚠️ | P2-3 |
| 19 | `new_repo_page.dart` | 表单 | 3 块 | 192dp 卡 | 16dp | 54% | ⚠️ | P2-3 |
| 20 | `notifications_page.dart` | 筛选 + 通知列表 | **9** | 85dp（最坏 104） | 12dp | — | ⚠️ | P1-4 / P1-7 |
| 21 | `onboarding_page.dart` | PageView 三步 | 3 块 | 进度 4dp、导航 48dp | 28/24.5dp | 中段 54% | ⚠️ | P1-7 |
| 22 | `profile_page.dart` | 账号 + 入口平铺 | **0** | ListTile 56dp | 16dp | **96%** | ❌ | **P0-1** |
| 23 | `pull_page.dart` | 头 + 文件 sliver | 6 文件 | 头 274dp / 行 72dp | 16dp | — | ⚠️ | P1-6 |
| 24 | `release_detail_page.dart` | 头 + 资产列表 | 0 资产 | 头 276dp | 16dp | **67%** | ❌ | P1-10 |
| 25 | `repo_page.dart` | TabBar + 多 tab | 0（骨架/头） | 分支条 56dp + Tab 48dp | 0/16dp | 29% | ⚠️ | P1-1 / P1-3 |
| 26 | `repo_tags_page.dart` | 标签列表 | 0 | 平铺行 72dp | 16/154dp | 42% | ❌ | P2-2 |
| 27 | `search_page.dart` | 三 tab（动态/推荐/议题） | 0（骨架） | 72dp 骨架 / 卡 96dp | 0/16dp | — | ⚠️ | P1-1 / P2-4 |
| 28 | `settings_page.dart` | 7 分类入口 | **7** | ~95dp/入口 | 16dp | 8% | ⚠️ | P1-8 / P1-11 |
| 29 | `settings_section_page.dart` | 分组平铺子页 | 无独立截图 | 由 `settings_group.dart` 决定 | 16dp | — | ⚠️ | P1-8（共享组件） |
| 30 | `workflow_dispatch_page.dart` | 工作流选择 + 输入 | 6（骨架） | 72dp 骨架 | 16/12.5dp | 23% | ⚠️ | P1-1 |

**补充截图（非独立页面）**：`home__light_390x844.png` 与 dashboard 完全一致；`search_results__light_390x844.png` 为 `search_page.dart` 的搜索结果态（6 条 / 屏，全库第二好样本）。

---

## 4. 修复优先级与验收口径

| 阶段 | 必做项 | 量化验收 |
|---|---|---|
| P0（阻断） | P0-1 profile 首屏、P0-2 network 首屏 | 两页首屏非背景行占比 ≥12%、可见条目 ≥3 |
| P1（本批闭环） | P1-1~P1-11 骨架分型、截图等待、空态顶对齐、通知行高、三详情头统一、gutter、28dp 分隔、登录/release 页脚、设置密度 | 列表页首屏有效条目 ≥6 的比例由 3/30 提升到 ≥15/30；通知 ≥10 条/屏；议题首评论 ≤200dp；页面级 gutter 仅 16dp |
| P2（记录） | P2-1~P2-5 空态 CTA 与表单一致性 | 空态页 100% 带可操作 CTA；三张新建表单提交位置统一 |
| 回归 | 截屏矩阵等待稳态后重跑；`ui_audit.py --fatal` / `perf_audit.py --fatal` / `gate_of_gates.py --fatal` 全绿；`dart format --output=none lib` 0 changed | 与本报告 §0 表格逐项对照 |

**审计边界声明**：本报告为 A 席只读产出，不含任何代码改动；`file:line` 均指向 HEAD `62c5383` 的工作副本。视觉接口 503 的回退方法已完整记录，像素数据可复算（`/tmp/density_a_pixels.py`、`/tmp/density_a_static.py`）。
