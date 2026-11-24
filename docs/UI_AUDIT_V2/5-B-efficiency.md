# UI 深度复审 · 批 5-B · 高频任务效率

> 文档戳：**2026-11-24 23:00:33 (Asia/Shanghai) · v15.0.0**（`pubspec.yaml:21` → `version: 15.0.0+150000`）
> 纪律：只读审计；未改代码、未 commit/push；禁读 Flutter SDK（未读取 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存源码），仅用项目自身 `lib/` 已验证代码与规则文档；本地未运行任何 dart 命令。
> 依据：`/var/minis/skills/sota-frontend-design/rules/04-ux-patterns.md`（§4 等待/§5 空态/§7 导航/§7b 列表/§8b 快捷键）与 `rules/02-layout-spacing-responsive.md`（§10 滚动）。
> 基线：`docs/UI_AUDIT_V2_BRIEF.md`、`docs/UX_STABILITY_PLAN.md`（61 条确证）、`docs/UX_CROSS_AUDIT/`、`docs/UI_AUDIT_V2/2-B-density.md`、`2-C-shell.md`、`3-A-controls.md`。
> 口径：步数＝从 App 已打开、目标已知（仓库/issue 名字在手）起，需要的「导航切换 + 点击 / 输入 / 滑动屏幕」次数；屏幕高按 800dp、底栏 80dp、AppBar 56dp，内容区约 664dp；行高按 M3 `ListTile` 单行 56 / 双行 72dp 估算。`file:line` 均可 `rg` 复现。

---

## 0. 结论速览

| 等级 | 数量 | 摘要 |
|---|---|---|
| P0 | 0 | 无「完全不可用 / 数据丢失 / 安全」级效率缺陷。 |
| P1 | 6 | 找自己的仓库 3 次交互 / 2 层导航且不记得上次位置；看 issue 讨论 2–5 屏、评论输入沉底；4 处空态 CTA 看得见点不动；骨架只画 2 块 + 300ms 强制空等；仓库页手动分页是全 App 唯一的「点按钮翻页」；设置 7 分类无搜索、改一项 3–4 次点击；批量操作（多选/全选）在所有高频页全缺。 |
| P2 | 5 | 深链与滚动恢复全库缺失（F-21）；搜索空态 CTA 禁点且代码结果不能跳代码行、无筛选排序持久化；发布产物下载要 5–7 次点击；无 `/`、Cmd+K 等键盘快路径；通知/列表 meta 稀疏导致扫读慢。 |

**总判：v15 把「空」变成了「有出口」，但没有把「高频任务」变短。** 七个任务里没有一个能一步到位：最短的「改一个设置」也要 3 次点击（底栏→分类→弹层选项），最长的「下载 release 产物」在点击层面叠加了「先开详情再下载」的 R5 反转，达到 5–7 次。效率提升只发生在「等待有形状」（骨架）与「空态有出口」（9/13 真 CTA），却被 4 处假 CTA、300ms 强制空等、评论输入沉底抵消。**用户从 v14 的「空、漂浮」变成 v15 的「看得见、点得到但走不完」——不是变快了，是变明确了。**

---

## 1. 闭环核对（逐条）

判定口径：**已修**＝当前代码无旧根因；**修法有问题**＝形式上改了但引入新症状/只修一半；**未修**＝旧根因逐字仍在。第 1 列沿用任务给定的编号（编号来自分工简述，与 `UX_STABILITY_PLAN.md` 字母编号不完全一一对应，以「描述」为准逐条判定）。

| 编号 | 判定 | 证据（file:line）与说明 |
|---|---|---|
| D-03/D-04/D-07 目录行无信息 / issue 首屏 0 评论 / 评论输入沉底 | **未修（3/3）** | ① 目录行 `repo_page.dart:2599` 仍 `subtitle: shown[index].isDirectory ? null : Text(ghSizeText(...))`——目录行逐字 `null`，只有文件名 1 项信息；② issue 首屏 `issue_page.dart:791-838` 仍是标题+meta+labels+assignees+正文 Card+关闭按钮+分隔线+「评论」标题，第一条评论从 `:864` 才构建；③ 评论输入 `issue_page.dart:925-958` 仍是 `CustomScrollView` 尾部 `SliverPadding`+`SliverToBoxAdapter`，非固定栏；无 AppBar「跳到评论」（`:763-782` 仅状态 spinner + overflow 菜单）。v15 在该文件只加了 `emptyAction`（`onPressed:null`，见 N-2）。 |
| S-02（旧 1-C 席目录行只有标题 / 36% 填充） | **未修** | 同一根因 `repo_page.dart:2599`，见上。旧审计修复指令「目录行补 `12 项 · 3 天前更新`」未落地；`theme.dart:370-377` `minVerticalPadding: OgLSpace.sm(8)` + `contentPadding.vertical=xxs(4)` 未改，无 `dense:true`（`dashboard_page.dart:490`、`repo_page.dart:2585/2806/2934` 均无）。 |
| G-11 语义图标（含 5-C「发现」选中图标不成对） | **修法有问题（层建了、调用点没收编）** | `lib/surface/util/og_l_icons.dart:17-37` 已导出 `OgLIcons.{copy,copyAll,refresh,retryAll,openExternal,delete,share}`（正确方向）；但 `download_manager_page.dart:211` 的重载图标仍是字面量 `Icons.refresh`（已在该页出现 `OgLIcons.retryAll` 用于重试全部，:198 附近），该页同时存在 `Icons.retry`/`Icons.refresh` 两种刷新语义；shell 本轮范围 `client_shell.dart:345/386` 的「发现」目的地仍只有单个 `Icons.search`、无 `selectedIcon`（另三项均成对），底栏/轨两份目的地还是手写副本。结论：抽象建立但存量未收编，与 3-A/2-C 席判词一致。 |
| G-12 分页模式三分（自动无限滚动 vs 手动「加载更多」） | **修法有问题（控制器统一了，交互模式没统一）** | `app/paged_controller.dart:1-21` 已把快照 TTL 6s、刷新排队、代次防竞态、dispose 保护统一提取（这是**数据层**统一）；但**交互层**仍三分：`dashboard_page.dart:129-136` 与 `:480-486` 距底 300px 自动 `_onScroll → loadMore`（尾行裸转圈），`search_page.dart:866/880/899` 滚动回调自动 `_loadMoreRepos`；`repo_page.dart:771-832` 的 `_pagedBody` 仍是 `OutlinedButton(onPressed: paged.loadMore)` 的手动按钮，文件头 `:8` 仍写「统一加载更多」——注释与实现漂移逐字保留。判定不是「已修」：`2-C-shell.md:31` 判「已修」只看控制器，本席看的是用户要不要点按钮。 |
| G-10 分页截断（issue/release 列表被 pageSize 截断） | **已修（`_kHeavyPageSize` 与 pageSize 对齐）** | `repo_page.dart:80` `_kHeavyPageSize = 10`；`:3004-3013` releases loader `perPage: _kHeavyPageSize(10)` 且 `PagedController(pageSize: _kHeavyPageSize)`；`:3491-3503` actions 同；`:3495/3503` 注释写明「必须与 per_page 对齐，避免第一页即判 done」。`:2668/2870/3162/3412` 通用列表 `_kPageSize=30` 与 `kPagedPageSize=30`（`paged_controller.dart:31`）一致。旧「10 条截断且永远不出加载更多」的根因不存在。 |
| F-21 深链与滚动恢复 | **未修** | `rg` 全 `lib/` 无 `initLink`/`getInitialUri`/`uri`  hop/深链解析（唯一命中是 `repo_page.dart:83` 的**预加载作用域名** `route:repo:<fullName>`，非 URL 解析）；`client_shell.dart:228-260` 四个 tab 页由 `_pageFor` 构建，IndexStack 内 `TickerMode`+`OgLAnimPreloadBoundary` 保留了 widget 状态，但 `client_shell.dart:232/237` 的 `ValueKey('dash-${_accountId}')`/`search-${_accountId}` 在**切号后强制造整页重建**，滚动位置与数据归零——旧确证「切号丢滚动与数据」逐字仍在。`repo_page.dart` 多 `ScrollController`（`_scroll` 等）无 `PageStorageKey`；无外部 URL 直达 issue/release 任何内容。 |

**闭环小计**：已修 1（G-10 分页截断）；修法有问题 2（G-11 语义图标、G-12 分页模式）；未修 4（D-03/D-04/D-07 三条、S-02、F-21；按任务分组计 4 行）。**效率相关的旧问题修复率极低：真正解决用户「少点几下 / 少滚几屏」的只有 1 条。**

---

## 2. 回归：v15 四批大改对效率的影响

### 2.1 空态 CTA：9/13 真出口，4 处假出口（负收益）

- 真出口（点击后确有动作）：`dashboard_page.dart:455/461`（新建仓库 / 去发现）、`repo_page.dart:2836`（新建 issue）、`:3123`（新建 release）、`:3377`（新建分支）、`gists_page.dart:146`、`profile_page.dart:220`、`pull_page.dart:171`、`notifications_page.dart:214`、`action_run_page.dart:566`、`action_log_page.dart:379`、`workflow_dispatch_page.dart:426` 等。空态从死路变为「下一步」，**效率正向**。
- 假出口（4 处 `onPressed: null`）：`issue_page.dart:849-855`（写评论）、`commit_page.dart:163-168`（网页查看）、`search_page.dart:1396-1401`（去发现）、`drafts_page.dart:202-207`（新建草稿）。`FilledButton.tonal` 高辨识外形 + 可点手型 + 无效点击 = **比 v14「空」更糟**：用户为「点一下试试」付出一次无效点击，然后靠 SnackBar/无反应才意识到被耍。
- 重复出口：`gists_page.dart:137-149` 同页既有 extended FAB「新建」又有空态「去新建」；`profile_page.dart:205-209` 顶栏 `person_add` 与空态「添加账号」同理。空态面板约 160dp（图标 24 + 文案 20 + 按钮 40 + padding 48 + 间距），没有减少步数，只增加视觉重量。
- 结论：**对效率的净影响约等于零**——省下「不知道下一步做什么」的思考时间，赔上假按钮的试错时间。

### 2.2 骨架屏与 300ms 防抖：等待有形状，但每次切页强制空等

- `async.dart:371-399` 的 `OgLAsyncSkeleton` 仅两块（160×12、220×8）+ 24dp 外边距，总高约 68dp，在 800dp 屏上留白 92%；不是「行高 56/72dp 的列表骨架」，不能作为内容锚点（`rules/04` §4「骨架必须匹配最终布局」）。
- `async.dart:56/61` 的 `loadDebounce=300ms` + `minLoadingDuration=300ms`：快速请求从「瞬开」变为**必现 300ms 空白骨架**。对用户是每次 tab 切换、每次筛选都多交 0.3 秒（一天切 100 次＝30 秒纯等待）。
- `OgLAsyncSliver`（issue 评论、repo 目录/issue/PR 列表）loading 仍是裸转圈（`async.dart:644`），`dashboard_page.dart:484` 尾行、`search_page.dart:1389` 首屏同样裸转圈。骨架只覆盖 `AsyncView`（`async.dart:325-333`）一半页面。
- 结论：等待**从「无结构」变为「有结构但空」**，效率不升反降（强制空等）+ 一半页面没受益。

### 2.3 去限宽 / 去缩放 / 图标层：与效率无直接正向，部分残留

- `client_shell.dart:317-328` 注释明确写着「把 720 阅读限宽下沉到各页 body……本批先保证顶栏锚定」，下沉未做。宽屏正文行超 80 字符，扫读变慢；与本席效率相关但属 2-B/2-C 的主场。
- `client_shell.dart:497-501` 切页位移压到屏宽 2%、透明度 0.94，切页不再「横飞」，但整页（含 AppBar）仍在 `FractionalTranslation` 子树内；对效率只是减少眩晕，不改变步数。
- 图标层 `og_l_icons.dart` 已建但未收编（见 G-11 行），对效率无直接增减。
- **唯一正向**：AppBar 全宽锚定 + 首页 AppBar 搜索按钮（`dashboard_page.dart:365-374`），把「找仓库/搜索」从「埋在发现页」提到首屏 1 次点击——这是本轮唯一可量化的步数减少（旧路径：底栏→发现→搜索入口 3 步，新路径：首页顶栏搜索 1 步）。

### 2.4 回归小表

| v15 改动 | 对高频任务效率 | 依据 |
|---|---|---|
| 空态 CTA | 部分正向（9/13），4 处负向假 CTA | `issue_page.dart:852`、`search_page.dart:1397` 等 `onPressed:null` |
| 骨架屏 + 300ms | 负向：强制空等 0.3s、骨架 92% 留白、sliver 仍裸转圈 | `async.dart:56/61/371-399/644` |
| 去限宽 | 无效率改善（长行难扫） | `client_shell.dart:317-328` TODO 未落地 |
| 去缩放/转场 | 无效率改善（仅减少眩晕） | `client_shell.dart:497-501` |
| 首页搜索入口 | 正向（找仓库/搜索 −2 步） | `dashboard_page.dart:365-374` |

---

## 3. 新发现（逐任务步数 + 量化，P1/P2）

### N-1【P1】任务①：找自己的某个仓库——3 次交互 / 2 层导航，且不记得上次位置

**路径**（名字已知，从 App 已打开起）：`底栏「仓库」`（若不在首页，1 次）→ 首页 `ListTile`（`dashboard_page.dart:490-511`）扫到目标 → 点行 1 次 → 进入 `RepoPage`。**计：在首页时 1 次点击；不在首页时 2 次（切 tab + 点行）。** 若名字不记得：点首页 AppBar 搜索（`dashboard_page.dart:365-374`）→ 输入 → 搜索结果页点行 → 进仓库 = **3 次交互 + 1 次输入**。
- 列表一屏 8–9 条（`dashboard_page.dart:490` 双行 subtitle + chevron，72dp/行，664÷72≈9），仓库多时滚 1–3 屏。
- 无搜索框在首页直接输入（`:615` 的「搜索框样式入口按钮」是跳转按钮，不是输入框）；无最近访问/收藏置顶；无 `/`/Cmd+K 快路径。
- F-21 回归：从仓库 PopScope 返回首页后，`_scroll`（`dashboard_page.dart:106`）未 `PageStorageKey` 恢复，`IndexedStack` 保活虽在，但切号后 `client_shell.dart:232` 的 ValueKey 变化整页重建，**位置归零**。
- 修复指令：① 列表行 `dense:true` + `minVerticalPadding: xxs` 到 ≤64dp（一屏 ≥10）；② 首页加最近访问/置顶仓库卡（数据已有，零新请求）；③ 给 `_scroll` 加 `PageStorageKey('dashboard-repos')` 并把切号 ValueKey 改为只在账号 id **真正变化**时重建。

### N-2【P1】任务②：在仓库里找一个 issue——4 次交互 / 6–9 屏扫读

**路径**：进仓库（任务①）→ 顶栏 `TabBar`（`repo_page.dart:467-475`，issue 是第 2 个 tab，需点 1 次）→ `_IssuesTab` 筛选 `SegmentedButton(open/closed/all)`（`:2784-2793`，默认 open，找 closed 需再点 1 次）→ 列表点行（`:2829`）→ 进 `IssuePage`。
**计：从仓库页起 3 次点击（tab + 可选筛选 + 行），从首页起 4 次；列表需滚 1–3 屏（一屏 ~9 条，72dp/行）。**
- 行 meta 只有 `author·comments·date`（`repo_page.dart:2813-2818`），**无状态标签/labels/相对时间**，扫读判定「是不是我要的 issue」要多看一眼甚至点进去。
- 仓库页无「在 issue 标题内搜索」的就地过滤（顶栏搜索 `:546-548` 打开的是**全局** repo/code 搜索，不搜 issue 标题）；用户只能肉眼扫。
- 修复指令：issue 行加 labels chip + 相对时间（数据已在 issue payload）；TabBar 内加就地搜索框（`isDense:true`，过滤当前列表，零新请求）。

### N-3【P1】任务③：看一个 issue 的全部评论——2–5 屏；输入框沉在末尾需 2.5–3 屏才够到

**量化**（`issue_page.dart`）：
- 首屏头部块 `SliverPadding`+`Column`（`:791-838`）约 328–488dp：标题 24 + 8 + meta 16 + 8 + labels 32 + 8 + assignees 32 + 12 + 正文 Card（视正文，短则 60、长则 200+）+ 8 + 关闭按钮 40 + 12 + Divider + 「评论」标题 20 + 8。664dp 内容区减头部 → **首屏 0 条评论**（D-04 原样）。
- 评论卡 `:864-919` 每条约 120dp（头部色带 56 + Divider + Padding(12) 内 Markdown），一屏 ~5 条。
- 输入框 `:925-958` 是尾部 `SliverToBoxAdapter`：10 条评论 = 2 屏评论 + 头部 0.5 屏 → **滚到输入框要 2.5–3 屏**；100 条评论要 ~20 屏才够到。
- 空评论时 CTA 是假按钮（`:852` `onPressed:null`），连「点一下就跳到输入框」都做不到（代码注释明说「本页评论输入框无 FocusNode，无法安全聚焦」）。
- 修复指令：① 按 D-13 原方案把评论输入提为 `Scaffold.bottomNavigationBar` 固定栏（或 AppBar 加「跳到评论」按钮 + `FocusNode`）；② 评论卡改平铺行（`flat_list.dart` 同源，一屏回 8–10 条）；③ 给 `_comment`（`:77`）配 `FocusNode`，接活 `:852` 的 CTA。

### N-4【P1】任务④：下载一个 release 产物——5–7 次点击，有进度但入口反转

**最短已知路径**（release 列表已有目标版本）：
1. 进仓库（任务①）→ 2. 点「Releases」tab（`:472`，第 4 个）→ 3. 点目标 release 行（`:3092` 附近 `onTap: _openDetail`）→ 4. 进 `ReleaseDetailPage` → 5. 点目标 asset 行（`release_detail_page.dart:533-558`）→ **先弹「资产详情」对话框**（R5：`:557` `onTap: _showAssetDetail`，「不再直接触发下载」）→ 6. 点详情里的 `FilledButton.icon(Icons.download_outlined, "下载")`（`:340-347`）→ 7. 若首次下载私有产物，还有令牌出口确认弹窗（`ogLGuardTokenExitDownload`，`:271`）。
**计：5 次点击（公开库）/ 6–7 次（含长按菜单路径或令牌确认）。** 已知快捷路径：长按 asset（`:558`）→ 操作菜单点「下载」（`:382-386`）——仍是 5 次（含长按）。
- 进度：入队后 SnackBar「已加入下载」（`:297-299`）→ 下载管理器页（`dashboard_page.dart:594-600` 顶栏下载图标 + badge）→ 每条任务 `LinearProgressIndicator(value: task.progress)`（`download_manager_page.dart:381-392`，200ms 一跳，C-11 已修正确）→ 完成/失败状态 + 一键重试全部失败（`:196-201`）/撤销移除（`:227`）。**进度反馈完整，是七任务里最好的**。
- 问题：R5 的「点击先看详情再下载」把 1 次点击变 2 次，为用户高频动作（下载）增加了确认摩擦；无「记住上次的下载版本」/「最近 release 一键下载最新 asset」。
- 修复指令：主 asset（首个/用户上次选的）行尾给常驻 `IconButton(download)` 一步下载；`onTap` 保留详情但详情按钮改主操作；下载管理页入口保留 badge 即可，不必再前置确认。

### N-5【P1】任务⑤：改一个设置——3–4 次点击，有分组定位但无搜索

**路径**（如改主题模式）：底栏「设置」（1 次，U1 已从「我的」二级提为一级，`client_shell.dart:258/403` 附近）→ 根页 7 个分类入口之一（`settings_page.dart:414-488`，如「界面」）点 1 次 → `SettingsSectionPage` 内 `OgLSettingsChoiceTile` 点 1 次 → 弹层选项点 1 次（`settings_group.dart:232-240` `ogLShowSettingsChoice`）= **4 次点击**。开关类（如动态色）少一次 = **3 次**。
- 好消息：批 12 已把设置从「一长串控件」改为**单层进入式 + 7 个分类入口 + 折叠摘要**（`settings_page.dart:401-488`、`:120-135`），比旧版满屏滚动找项效率明显提升；每个入口有 `subtitle` 摘要（如「明暗 · 主题色 · 文字缩放」），不点进去也知道当前值。
- 问题：**无设置搜索框**（全文件 `rg search/Search/搜索` 为空）；分类名与用户心智可能不一致（「存储与网络」含下载，`_storageGroup`）；7 个分类入口一屏可见，但二级分组展开后仍要滚动找目标（如「代码与文件」组有 15+ 行，`settings_page.dart:898-1059`）。改完值走 `onSelected → unawaited(_settings.setXxx)`（`settings_group.dart:240`），无即时 SnackBar 确认（`4-B` 席范围），用户不确定是否生效。
- 修复指令：① 根页 AppBar 加设置搜索（`OgLAppBar` 加 `search` IconButton → 弹层模糊匹配所有 `title` + 直达对应分类并高亮目标行）；② 给高频设置（主题/语言/下载目录）在根页加「常用」入口，省一次分类点击；③ 写后发 `info` SnackBar 确认。

### N-6【P1】任务⑥：搜索仓库/issue——结果可跳，但筛选/排序/空态三缺陷

- **可直接跳转**：`search_page.dart:1420-1426` 结果行 `onTap: _open(hit)` → `_open`（`:1320-1337`）push `RepoPage`（含 `initialPath`，代码搜索结果能打开仓库并定位文件）。**仓库跳转是 1 次点击**。
- **筛选/排序**：
  - 全局结果页只有 `SegmentedButton(仓库/代码)` 两档（`search_page.dart:1355-1363`），**无语言/stars/更新时间筛选、无排序选择**； finder 层的发现页有 `FilterChip`（`:840` `:1025`），但那不是搜索结果页。
  - 搜索页无「搜索历史 / 最近查询」（`rules/04` §7b 要求）；每次重新输入。
  - 结果 `subtitle maxLines:2`（`:1422`）固定两行，长描述被截断；代码命中只显示 fragment 文本，**点击只打开仓库/文件，不定位到命中行**（`initialPath` 是文件路径，没有 line 字段）。
- **空态**：`AsyncView.emptyText: noResults(query)`（`:1393`，会回显查询词 ✓），但 CTA `onPressed:null`（`:1396-1401`），且**无「清空筛选」**（本来也没有筛选可清），无拼写建议/近邻推荐。
- 步数：首页搜索按钮（1）→ 输入查询（1 次输入）→ 结果行点击（1）= **3 次交互**，与任务①相同；若从发现页进入则多 1 步。
- 修复指令：① 接活空态 CTA（pop 回发现 tab）；② 结果页加语言/排序 FilterChip 行并把状态写进 URL/路由参数（项目暂无深链，先做路由内持久化）；③ 代码命中带 line → `RepoPage.initialPath` 支持 `path:line` 定位；④ 加最近查询 chips。

### N-7【P1】任务⑦：批量操作（多选/全选）——高频页全缺

- 全库六个高频页 `rg Checkbox/selectAll/全选/批量/multiSelect/selectionMode` 结果：`dashboard_page.dart`、`repo_page.dart`、`issue_page.dart`、`search_page.dart`、`download_manager_page.dart` **只有 SegmentedButton/FilterChip 的 `selected` 与 issue 标签多选对话框**（`issue_page.dart:1060-1105`，那是编辑 issue 的 labels，不是列表批量），**没有任何列表多选/全选/批量操作**。
- 场景缺口：issue 列表不能「全选当前筛选的 50 个 open issue → 批量关闭」；首页仓库不能「批量加星」；下载管理器只能「重试全部失败」（`download_manager_page.dart:196`）与「清除已完成」（`:202`）——这俩是仅有的一点批量，但粒度是全局状态而非用户勾选。
- 影响：重复操作 N 条要 N 次「点击 + 确认 + 返回」，50 条 issue 关闭 = 至少 150 次交互；这是长期用户最费时的一类操作。
- 修复指令：按 `rules/04` §6/§7b，给列表页加 `selectionMode`（长按/复选框进入，header checkbox +「全选当前筛选 N 项」），批量 destructive 弹层明确数量 + verb 按钮 + `Undo` SnackBar；下载页把「重试全部失败」纳入同一多选模型。

### N-8【P2】深链与滚动恢复（F-21 未修，量化影响）

- 无深链：外部链接/通知点进 App 永远落在首页（root `OgLClientShell._tab` 初始 `home`，`client_shell.dart:64`），要到达某个 issue 需重走 N-1→N-2 全路径（**3–4 次导航 + 1–3 屏**）。
- 滚动丢失：切号后 `client_shell.dart:232/237` ValueKey 变化 → 整页重建 → 列表位置/分页数据归零；`repo_page.dart` 多 `ScrollController` 无 `PageStorageKey`，TabBarView 切 tab 后重建（页面注释 `:150` 承认「TabBarView 会销毁不可见标签页」，靠 6s 快照缓存回数据但**滚动位置不恢复**，`paged_controller.dart:47-50`）。一天在多仓库/多 tab 间来回，这部分是隐性时间税。

### N-9【P2】无键盘快路径（power-user 效率）

- 全库 `shortcuts.dart` 只有返回键守卫（`client_shell.dart:1-28` 导入），搜索无 `/`/Cmd+K 聚焦（`search_page.dart` 无 `FocusNode`/`Shortcuts`/`Actions`），无任何命令面板。
- `rules/04` §8b 指出「Cmd+K 是 2026 生产力工具的默认」。用户每天找仓库/找 issue 数十次，键盘快路径可直接省掉 1–2 次点击 + 一次 tab 切换。当前连桌面端 expanded 导航轨（`client_shell.dart:366-410`）也只是指针操作。
- 修复指令：加全局 `Shortcuts` 层（`/` 聚焦搜索、`g h` 回首页、`g s` 搜索），弹层展示绑定；注意 IME `isComposing` 与输入框焦点判断（§8b）。

---

## 4. 用户满意度：每天用，最影响效率的三个摩擦点

站在「一天开 20 次、每次找 2–3 个仓库/issue」的用户视角排序：

1. **看讨论要滚 2–5 屏，输入框沉在 20 屏之后（N-3 / D-04 / D-13 未修）** —— 这是单个任务里耗时最长的：首屏 0 评论、评论卡 120dp 一屏 5 条、输入框在列表尾。用户每天在这种「进详情先看一半空头部 + 滚半天才够到输入框」上花掉的时间，比任何其它单点都多。评论输入不是固定栏这件事，让「回一句」变成一次短途旅行。**修复收益最大：固定输入栏 + 评论平铺行，一次改完首屏能见讨论、输入零滚动。**
2. **高频页行密度只有 60% 且 meta 缺关键信息（D-03/D-07/S-02 未修）** —— 一屏 8–9 条（目标 12–14）、目录行只有文件名、issue 行无状态/labels。用户找一条具体东西平均多滚 1–2 屏；这还叠加了「同一列表没有就地搜索/筛选」（任务②/⑥），只能肉眼扫。**修复收益最广：所有列表页一次提升，7 个任务里 4 个受益。**
3. **设置无搜索 + 批量操作全缺 + 假 CTA 的试错（N-5/N-7/N-2）** —— 改一项设置要 3–4 次点击且无搜索；50 条 issue 只能一条条关；4 处高辨识按钮点不动。这些不是「慢一点」，是「每次都要重新想路径 / 白点一下」的认知税，长期使用积累成烦躁。**修复收益最直接：设置搜索省 1 次分类点击、批量关闭省 N×2 次交互、假按钮一删就不浪费点击。**

（次一级但值得记：v15 的 300ms 强制空等——一天切 100 次 tab 就是 30 秒纯等待，属于「看不见的税」，排第 4。）

---

## 5. 本席对三问的回答

**问 1 · 旧确证修好了吗？**
效率相关 6 条（D-03/D-04/D-07、S-02、G-11、G-12、G-10、F-21，按任务分组逐条判定）：**已修 1（G-10 分页截断，`pageSize` 与 `per_page` 已对齐）；修法有问题 2（G-11 图标层建了未收编、G-12 控制器统一但交互仍是手动按钮）；未修 4（D-03 行模板 / D-04 issue 首屏 / D-13 评论沉底 / S-02 目录行 / F-21 深链与滚动恢复）**。核心结论：v15 修的是「观感」（空态、骨架、顶栏、图标层），不是「效率」——用户要少点几次、少滚几屏的诉求，一条都没落地；唯一正向是首页 AppBar 把搜索入口从发现页提到首屏（−2 步）。

**问 2 · v15 大改有回归吗？**
有，且直接伤害效率：① `async.dart:56/61` 的 300ms 防抖 + 最小显示让每次切页/筛选强制空等 0.3 秒；② 骨架仅 68dp/92% 留白、sliver 页仍裸转圈，等待有形状但无内容锚点；③ 空态 CTA 4/13 处 `onPressed:null`，从「空」变「假有用」；④ 去限宽未下沉，宽屏长行扫读变慢。正向：返回链防连按穿层（`client_shell.dart:150-157`）、切页鬼影消失、`IndexedStack` 保活（非切号时保留页面数据）。**净评：观感收益明显，效率中性偏负。**

**问 3 · 还有什么旧审计没抓到的？**
新增 9 条量化发现：N-1 找仓库 1–3 次交互/1–3 屏；N-2 找 issue 3–4 次交互/1–3 屏；N-3 看评论 2–5 屏、输入框 2.5–3 屏；N-4 下载 release 5–7 次点击（进度完整，但 R5 反转多一次点击）；N-5 改设置 3–4 次点击且无搜索；N-6 搜索无筛选/排序/历史、代码命中不定位行；N-7 五页全无多选/全选/批量；N-8 深链缺失+切号滚动归零；N-9 无 `/`/Cmd+K 快路径。**最该先修三件：把评论输入提到固定栏 + 评论平铺（N-3）、把列表行降到 ≤64dp 并补 meta（N-1/2）、把设置搜索与列表批量补上（N-5/7）。**

---

## 6. 已检查清单（逐任务步数表）

| # | 任务 | 最短路径（交互分解） | 导航层数 | 点击/交互次数 | 需滚动屏数 | 结果直达 | 进度/筛选/批量 | 判定 |
|---|---|---|---|---|---|---|---|---|
| ① | 找自己的某个仓库 | 首页→点仓库行（或在首页 AppBar 搜索→输入→点结果） | 1–2 层（tab→仓库页） | 1（在首页）/ 3 + 输入（走搜索） | 1–3 屏（一屏 8–9 条） | 是（点行进 RepoPage） | 无就地过滤；无置顶/最近；切号丢滚动 | P1 |
| ② | 在仓库里找一个 issue | 仓库页→点 Issues tab→（可选筛选 open/closed）→点 issue 行 | 2 层（tab→详情页） | 3（含 tab + 筛选 + 行） | 1–3 屏（一屏 ~9 条） | 是（进 IssuePage） | 有 open/closed 筛选；无就地搜索；行 meta 无状态/labels | P1 |
| ③ | 看一个 issue 全部评论 | 进详情→滚过头部（0 评论）→逐条滚评论→滚到末尾输入框 | 1 层（详情页内滚动） | 0（纯滚动）；想输入需滚 2.5–3 屏 | **2–5 屏**（10 条评论约 2.5 屏） | 输入框在末尾，非固定 | 无「跳到评论」；空评论 CTA 禁点（`:852`） | P1 |
| ④ | 下载一个 release 产物 | 仓库→Releases tab→release 行→asset 行→资产详情→下载（→令牌确认） | 2 层（仓库→release 详情→对话框） | **5–7 次**（长按快捷路径仍 5） | 0–1 屏 | 否（R5 强制先看详情） | **有进度**（管理页 LinearProgress 200ms）；一键重试全部失败；无批量勾选 | P1 |
| ⑤ | 改一个设置 | 底栏设置→分类入口→（弹层）选项 | 2 层（设置根→分类子页→弹层） | **3（开关）/ 4（选择）** | 0–1 屏（分类内可滚） | 是（写后立即生效） | **有 7 类分组 + 摘要定位；无搜索**；无写后确认 | P1 |
| ⑥ | 搜索仓库/issue | 首页 AppBar 搜索→输入→点结果行（或发现页进入多 1 步） | 2 层（搜素页→仓库页） | 3（按钮 + 输入 + 行） | 0–2 屏（每页 30 条） | 是（结果→RepoPage，代码带 initialPath） | 有仓库/代码切换；无筛选/排序/历史；空态回显查询但 CTA 禁点 | P1 |
| ⑦ | 批量操作（多选/全选） | —（功能不存在） | — | —（只能逐条操作） | 50 条 = N× 交互 | — | 六页均无多选/全选/批量；仅下载页有「重试全部失败/清除已完成」全局动作 | P1 |

### 已检查文件清单（逐页，非抽样）

| 文件 | 检查范围 | 关键证据 |
|---|---|---|
| `lib/surface/app/client_shell.dart` | 4 tab 导航、底栏/轨目的地、懒挂载、切页动画、ValueKey、返回链 | `:228-260`、`:317-328`、`:342-410`、`:497-501`；「发现」无 selectedIcon、切号 ValueKey 重建 |
| `lib/surface/pages/dashboard_page.dart` | 首页列表/搜索入口/分页/CTA/下载入口 | `:365-374` 搜索按钮、`:490-511` 行、`:129-136` 自动分页、`:484` 尾行裸转圈、`:594-600` 下载入口 |
| `lib/surface/pages/repo_page.dart` | 9 tab、目录行、issue/PR/release 列表、分页按钮、搜索入口 | `:2599` 目录 subtitle:null、`:2813-2818` issue meta、`:771-832` 手动分页、`:3004-3013` pageSize 对齐、`:546-548` 搜索按钮 |
| `lib/surface/pages/issue_page.dart` | 头部、评论卡、评论输入、CTA、AppBar、标签多选 | `:791-838` 头部、`:864-919` 评论、`:925-958` 输入框、`:852` 禁点 CTA、`:763` 原生 AppBar、`:1060-1105` 标签多选 |
| `lib/surface/pages/search_page.dart` | 发现页/结果页、搜索框、筛选、空态、结果跳转 | `:840/1025` FilterChip、`:1355-1363` 两档、`:1373-1382` 输入框、`:1396` 禁点 CTA、`:1320-1337` 跳转、`:1422` 2 行 subtitle |
| `lib/surface/pages/download_manager_page.dart` | 下载列表、进度、重试/清除/撤销 | `:196-201` 重试全部、`:227` 撤销、`:381-392` LinearProgress(200ms)、`:46-120` SnackBar 总线 |
| `lib/surface/pages/settings_page.dart` | 7 分类入口、分组摘要、选择行、网络/代码组 | `:401-488` 分类入口、`:414-488` 摘要、`:540-669` 界面组、`:898-1059` 代码组；无搜索框 |
| `lib/surface/pages/settings_section_page.dart` | 二级设置容器 | `:17-42` 只有 AppBar + ListView，无搜索/定位 |
| `lib/surface/widgets/settings/settings_group.dart` | ChoiceTile 弹层行为 | `:143-240` `ogLShowSettingsChoice` + `onSelected` |
| `lib/surface/app/paged_controller.dart` | 分页控制器统一 + pageSize 契约 | `:1-21` 语义清单、`:31` `kPagedPageSize=30`、`:47-50` 快照 TTL 6s |
| `lib/surface/app/async.dart` | 骨架/空态/300ms 防抖/sliver loading | `:56/61` 300ms、`:325-333` 骨架、`:371-399` 2 块、`:474` maxWidth320、`:644` 裸转圈 |
| `lib/surface/theme.dart` | 列表行模板 | `:370-377` `minVerticalPadding=sm(8)` + `contentPadding.vertical=xxs(4)` |
| `lib/surface/util/og_l_icons.dart` | 语义图标层 | `:17-37` 9 个 `OgLIcons` 常量；收编不全（见 G-11） |
| `lib/surface/pages/release_detail_page.dart` | 资产详情/下载/进度提示 | `:237-302` `_download`、`:309-408` 先详情后下载（R5）、`:533-558` 资产行 |

---

## 7. 修复优先级建议（供主会话汇总，不在本席执行）

| P | 动作 | 具体文件/值 | 预期收益 |
|---|---|---|---|
| P1 | 评论输入固定栏 + 评论平铺 | `issue_page.dart:925-958` → `Scaffold.bottomNavigationBar`；`:864-919` 换 flat row；`:77` 加 `FocusNode` 接活 `:852` | 任务③ 从 2.5–3 屏降到 0 滚动 |
| P1 | 列表行降密度 + meta | `theme.dart:376` `minVerticalPadding sm→xxs` + 各列表 `dense:true`；`repo_page.dart:2599` 目录补 meta、`:2813` issue 补 labels/状态 | 任务①②⑥ 各少 1–2 屏 |
| P1 | 接活 4 处假 CTA | `issue_page.dart:852`、`commit_page.dart:164`、`search_page.dart:1397`、`drafts_page.dart:205`：接真或删按钮 | 消除无效点击 |
| P1 | 设置搜索 + 列表批量 | `settings_page.dart:403` AppBar 加搜索；六个列表加 `selectionMode` + header 全选 | 任务⑤ 省 1 步；任务⑦ 从 N× 降到 1 次 |
| P1 | 分页模式统一 | `repo_page.dart:771-832` 改 `NotificationListener<ScrollNotification>` 距底 300px 自动加载，按钮降为失败兜底；同步改 `:8` 注释 | 仓库 4 个列表省一次点击/次 |
| P2 | 深链 + 滚动恢复 | `client_shell.dart` 加 app-link 解析 + tab/key 路由；各 ScrollController 加 `PageStorageKey` | 任务①② 从首页重走降为直达 |
| P2 | 去掉 300ms 强制空等 | `async.dart:56/61` 改 120ms grace、min 150ms；`OgLAsyncSkeleton` itemCount 8 | 每次切页省 0.15–0.3s |
| P2 | 搜索增强 + 键盘快路径 | `search_page.dart:1355+` 加筛选/排序/历史；全局 `/`/Cmd+K | 任务⑥ 少 1–2 步 |
