# 批 5 · C 席 —— 30 页一致性总查审计（同类模式 / 图标语义 / 文案视觉 / 明暗主题）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 5 · 全链路体验流 · C（一致性总查）**
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `f684160`（2026-11-21 16:27:57 +0800）
> - 更新时间：**2026-11-22 01:21:28 (Asia/Shanghai)**
> - 页面基数：`rg -l "Scaffold" lib/surface/pages/*.dart | wc -l` = **30**，逐页全覆盖（轴二功能页面矩阵 30/30）
> - 审计对象：`lib/surface/pages/*.dart`（30 页）+ `lib/surface/app/og_l_app_bar.dart`（滚动融合栏）+ `lib/surface/theme.dart`（组件主题 / 明暗）+ `lib/surface/app/og_l_app.dart`（主题装载、启动失败兜底）+ `lib/surface/widgets/`（图标承载组件）
> - 依据：`UX_CROSS_AUDIT_BRIEF.md`（含双轴补强）、`material-3/SKILL.md`（Components / Theming / Anti-Patterns / Audit 节）、`sota-frontend-design/rules/03-design-systems-components.md`（§1 语义令牌 / §1b 命名治理 / §4 状态 / §6c API smells）
> - 方法：`rg` 全库 `Icons.*` 统计 + 逐调用点读语境（区分「删除/取消/状态」语义）+ 逐页 AppBar / 筛选 / 分页 / 操作区模式归类 + 明暗分支检索。**只读审计，未改任何代码，未 commit / 未 push。**

---

## 0. 结论速览

本席做的是**横切总查**。核心结论一句话：**页面级样式纪律很好，页面间"模式治理"很弱**——全库零硬编码色、零页面级明暗分支（这点优于多数同类项目），但**同一个应用里存在两套 AppBar、三套分页、四套筛选控件、四种复制图标**，同类场景不同处理，正是用户所说「粗糙 / 没有工具稳定感」的结构性来源。

| 维度 | 量化结果 | 判定 |
|---|---|---|
| AppBar 模式 | `OgLAppBar`(滚动融合) **15 页** vs 原生 `AppBar` **15 页**，正好对半 | ❌ 最严重模式漂移 |
| 复制图标 | `content_copy` 4 处 / `copy_all_outlined` 3 处 / `Icons.copy` 1 处（全库唯一）/ `Icons.link` 2 处（图文不符） | ❌ 四类并存 |
| 刷新/重试图标 | `refresh` 3 处 / `restart_alt` 3 处 / `sync` 2 处（状态图标） | ❌ 同页同类动作两种图标 |
| 打开外部图标 | `open_in_new` 13 处 / `language` 1 处 / `link` 3 处（含打开语义） | ⚠️ 主流统一、边缘漂移 |
| 删除图标 | `delete_outline` 11 处 / `delete_sweep_outlined` 1 处 / `close`+`cancel_outlined` 2 处（取消≠删除，语义可辨） | ⚠️ 批量删除孤例 |
| 筛选控件 | `SegmentedButton` 5 页 / `FilterChip` 2 页 / `ChoiceChip` 1 页 / `DropdownButton` 3 页 | ❌ 同类筛选四类控件 |
| 分页模式 | 自动无限滚动 3 页（search/dashboard/repo_tags）/ 手动「加载更多」按钮 1 页（repo_page） | ❌ 同类列表两种交互 |
| 明暗主题 | 页面+widgets 中 `brightness ==` / `Colors.white|black` **0 处**；仅 `theme.dart` 与启动页处理 | ✅ 无单主题硬编码 |
| 图标语义一致性总评 | 5 类关键动作中 **4 类存在冲突** | ❌ |

**问题总数：24 条**（严重 8 / 中 10 / 轻 6），全部带 `file:line` 证据与修复指令。

---

## 1. 用户可感知问题清单（24 条 · 严重 8 / 中 10 / 轻 6）

### 🔴 严重（8 条）—— 模式漂移，用户跨页即感到「这不是同一个 App」

**C-S1 · 应用栏两套实现正反对半分裂：15 页滚动渐变融合、15 页原生阶跃栏**
证据：`rg -l "OgLAppBar" lib/surface/pages/*.dart` = 14 页 + `search_page.dart:716`（同页两处）= 15 页；原生 `appBar: AppBar(` = 15 页（`action_log:290`、`action_run:526`、`issue:723`、`pull:109`、`commit:93`、`release_detail:457`、`gist_detail:354`、`file_preview:205`、`download_manager:205`、`new_gist:144`、`notifications:170`、`workflow_dispatch:412`、`legal_text:94`、`code_editor:579`、`login:326`）。`OgLAppBar`（`og_l_app_bar.dart:120-135`）随滚动 0→1 连续插值 surface→surfaceContainer，原生栏靠主题 `scrolledUnderElevation:0`（`theme.dart:286`）恒融合无反馈。
用户感受：从 gists 页滑到 notifications 页，滚动态顶栏行为完全不同——一页顶栏"活"、一页顶栏"死"，**稳定感立刻碎裂**；这是全库最容易被感知的一致性裂缝。
修复：统一到 `OgLAppBar`。把 15 个原生 `appBar: AppBar(` 全部替换为 `OgLAppBar(title: ...)`，其 `actions`/`bottom` 参数已支持（`og_l_app_bar.dart:31-33`）；对 body 自建 ScrollController 的页（issue/pull/commit 的 `CustomScrollView`）显式传 `scrollController:` 以启用渐变。参考 `material-3` App bar 统一角色 + `rules/03 §1` 组件消费同一令牌契约。

**C-S2 · 复制动作四种图标并存，且"复制"配 `Icons.link` 图文直接冲突**
证据：`Icons.content_copy` → `settings:2308`/`notifications:393`/`download_manager:508`/`about:140`；`Icons.copy_all_outlined` → `release_detail:470`/`gist_detail:463`/`action_log:307`；`Icons.copy` → `search:949`（全库唯一一次）；**`Icons.link` 配"复制"文字** → `release_detail:355`（`label: _t('copyLink')`）、`repo_page:592`（`title: _t('copyCloneUrl')`）。
用户感受：同一个"复制链接"操作，在这页是链条图标、那页是两张纸，search 底部操作单里又冒出第三种——用户靠图标形成肌肉记忆的努力被打断，`link` 配"复制"更让人误以为是"打开链接"。**典型「同类场景不同处理=粗糙」**。
修复：全库"复制 X 到剪贴板"统一 `Icons.content_copy`（MD3 content_copy 即标准 copy 图标，M3 语义角色 icon.action.copy）。替换 `release_detail:355`、`repo_page:592` 的 `Icons.link` → `Icons.content_copy`；`search:949` `Icons.copy` → `Icons.content_copy`；`gist_detail:463`/`action_log:307`/`release_detail:470` 的 `copy_all_outlined` 仅在"复制整份/全部"时保留（如 action_log 复制整份日志），单条复制一律 `content_copy`。`about:140` trailing 已是 `content_copy` ✅ 作为样板。

**C-S3 · 刷新/重试同页两种图标：`restart_alt` 与 `refresh` 表达同一"重试"**
证据：`download_manager_page.dart:211` "重试全部失败"用 `Icons.restart_alt`，`:489` "重试单个"用 `Icons.refresh`；`action_run_page.dart:622` "重跑"用 `refresh`、`:631` "重跑失败 job"用 `restart_alt`、`action_log:318` "重载"用 `refresh`。
用户感受：同一个下载管理页，失败项图标是"回转箭头"、顶部一键重试是"重播箭头"，用户无法判断两者差别；**图标语义漂移是维护混乱的直接信号**。
修复：定义全库规则并落到组件：单个"重试/刷新"=`Icons.refresh`（action_log/action_run 单行保留）；批量"重试全部失败"=`Icons.refresh` 即可（`restart_alt` 仅保留给"新一轮/重新开始工作流"这种确实不同的语义）。把 `download_manager:211`、`action_run:631` 改为 `Icons.refresh`，或反过来在 `widgets/` 建 `OgLRetryIcon` 统一出口——二选一，禁止混用。

**C-S4 · 复制/打开语义跨界：`Icons.link` 同时承担"复制链接""打开 URL""使用原始链接"三义**
证据：`Icons.link` 出现在 `release_detail:355`(复制)、`repo_page:592`(复制克隆地址)、`about:134`(打开仓库URL)、`file_preview:408`("使用原始链接"按钮)、`settings:775`("添加URL"输入框)、`release_detail:389`(复制下载链接)。而"打开外部"主流用 `open_in_new`（13 处）。
用户感受：`link` 图标在复制、打开、切换三种动作间横跳，图标彻底失去指示价值。**图文配合失败**：按钮写"复制链接"画链条、`open_in_new` 写"在浏览器打开"画方框箭头，两个"打开"在 search 同一弹层里还用了不同图标（`search:944` open_in_new vs `:959` `Icons.language`）。
修复：`Icons.link` 保留给"静态链接展示/URL 字段"场景（about:134 / settings:775），复制动作改 `content_copy`（见 C-S2），打开动作一律 `open_in_new`。`search:959` 的 `Icons.language` 改 `Icons.open_in_new`，与同弹层 `:944` 对齐。

**C-S5 · 列表筛选控件四分：Segmented / FilterChip / ChoiceChip / Dropdown 各管一摊**
证据：`SegmentedButton` → `notifications:196`(4档)、`dashboard:416`(2档)、`search:1330`(2档)、`repo:2760`(3档)/`:2889`；`FilterChip` 横滑 → `search:826`/`:1011`；`ChoiceChip` → `repo:3588`；`DropdownButton` → `legal_text:142`、`workflow_dispatch:564`、`repo:4391`。`search_page.dart:820-821` 注释自承"SegmentedButton 五档在窄屏接近临界溢出（audit_spec_b B17）"才改 FilterChip，但 notifications 4 档、repo 3 档仍用 SegmentedButton。
用户感受：都是"按状态筛列表"，通知页是分段按钮、搜索页是横滑胶囊、仓库 Actions 页是 ChoiceChip——用户每进一个列表都要重新学筛选交互，**不一致直接转化为操作迟疑**。
修复：确立"筛选档位 → 控件"单一规则并全局执行：≤3 档用 `SegmentedButton`（M3 segmented button，单选）；>3 档或窄屏用横滑 `FilterChip`（M3 filter chip）；`ChoiceChip` 与 `FilterChip` 合并为后者；Dropdown 仅用于"从长列表选一项"的 *选择* 场景，不用于状态筛选。据此把 `notifications:196`（4档）改 FilterChip 横滑，与 `search:1011` 对齐。

**C-S6 · 分页模式三分：两个列表自动无限滚动，仓库页仍是手动"加载更多"按钮**
证据：`search:445-449`（滚动距底 300px 自动 `_loadMoreRepos`）、`dashboard:129-136`（距底 300px 自动 `p.loadMore()`）、`repo_tags:221-223`（`NotificationListener<ScrollNotification>`）；但 `repo_page:820` 仍是 `onPressed: paged.loadMore` 的手动按钮，且 `repo_page.dart:8` 文件头注释明确写"仓库列表与仓库页各列表统一「加载更多」"——注释与现实已漂移。
用户感受：首页/搜索滑到底自动续，仓库页滑到底却停住要找按钮——用户会以为"没内容了"，**这是同类列表页最伤稳定感的一种不一致**。
修复：把 `repo_page:770-830` 的分页渲染统一为 `NotificationListener<ScrollNotification>` + 距底 300px 自动加载（复用 `dashboard:129` 的同款守卫），手动按钮降级为自动加载失败后的兜底重试；同步修正 `repo_page.dart:8` 注释，避免文档继续传播旧模式。

**C-S7 · 详情页标题/操作区布局分裂：AppBar 显示编号 vs 名称、操作平铺 vs 全收起**
证据：AppBar 标题用编号/SHA/tag：`issue:724`(`#$_number`)、`pull:110`、`commit:94`、`action_run:527`、`release_detail:458`(tagName)、`file_preview:206`(pathName)；真实标题放 body `titleLarge`：`issue:747`/`pull:127`/`commit:118`（这一组内部一致 ✅）。但操作区：`issue:728` 收进 `more_vert` 溢出菜单、`release_detail:463` 两个 IconButton 平铺 + `:550` 又用 `more_horiz`、`gist_detail:356` 删除按钮直接平铺、`pull:109` **完全没有 actions**、`file_preview:209` 单 open_in_new 平铺。
用户感受：同为详情页，议题的操作藏进「⋮」，Gist 的删除直接裸露，PR 页找不到任何操作——用户对"操作在哪"没有稳定预期，**粗糙感来自布局无规律**。
修复：制定详情页统一模板：AppBar 标题=对象标识（编号/名称，全库统一为编号放副标题或改用真实标题），actions ≥3 个收 `PopupMenuButton`（`Icons.more_vert`），≤2 个可平铺；`pull_page.dart:109` 补 actions（至少开放浏览器 + 复制 PR 链接，复用 repo 页既有的 `open_in_new`/`content_copy` 组合）。

**C-S8 · 启动失败兜底页强制深色，与用户选定主题断裂**
证据：`og_l_app.dart:173-178` `OgLBootFailureApp` 内 `ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kOgLErrorSeedColor, brightness: Brightness.dark))`——无视系统/用户 `themeMode`。对照主界面 `og_l_app.dart:99` `surface.themeFor(platformBrightness, ...)` 已正确跟随明暗。
用户感受：浅色主题用户冷启动一旦引导校验失败，突然砸出一个全黑错误页再跳回浅色主界面，「闪一下变黑」=启动链路视觉连续性断裂（与 5-A 启动链路交叉）。
修复：`OgLBootFailureApp` 接收 `Brightness` 入参，由 `main()` 读 `MediaQuery.platformBrightnessOf` 传入；`brightness` 用该值而非写死 `Brightness.dark`，`seedColor` 保留 error 色即可。属批 5-A 启动链路共性问题，回链 5-A。

### 🟠 中（10 条）—— 局部不一致，打磨度不足

**C-M1 · 溢出菜单图标 `more_vert` / `more_horiz` 无规则**：`issue:728` AppBar 用 `more_vert`，同页 `:840` 评论行内用 `more_horiz`；`search:240`、`release_detail:550` 行内用 `more_horiz`。修复：确定规则"AppBar/顶栏溢出=more_vert，行内/卡片溢出=more_horiz"并写进组件文档；issue 页两处符合该规则 ✅，但 `release_detail:550` 的 more_horiz 是行内 ✅——实际冲突仅在缺文档导致后续漂移，建议补 lint 注释。

**C-M2 · 批量删除图标孤例**：`notifications:186` "清空通知"用 `Icons.delete_sweep_outlined`，全库其它删除（11 处）用 `delete_outline`。修复：批处理删除保留 `delete_sweep_outlined` 可接受，但须在确认文案明确"全部/批量"（`:144 resetTitle` 已具备 ✅），并统一到 `og_lShowDestructiveConfirm`（回链 3-A S1）。

**C-M3 · 取消动作图标三分**：`download_manager:496` 取消下载用 `Icons.close`，`action_run:638` 取消运行用 `cancel_outlined`，`action_run:480`/`repo:3547` 状态"已取消"用 `Icons.cancel`。修复：动作态"取消"统一 `Icons.close`（进行中项）或 `cancel_outlined`（详情按钮），状态展示保留 `cancel`；download_manager:496 与 action_run:638 二选一，建议都用 `cancel_outlined`。

**C-M4 · 列表页页头 padding 模式不统一**：筛选条外边距 `notifications:193-195` = `fromLTRB(md, md, md, sm)`，`search:1322-1326` = `fromLTRB(lg, xxs...)`，`repo:2757-2760` = `fromLTRB(lg, md, lg, xxs)`。同为筛选条，左右 gutter 在 md(16)/lg(24) 间跳。修复：统一为 `EdgeInsets.fromLTRB(OgLSpace.lg, OgLSpace.md, OgLSpace.lg, OgLSpace.xxs)`，与详情页头部 `lg` 对齐（回链 1-A S2）。

**C-M5 · 详情页副标题格式两套**：`issue:748-755`/`pull:127-135` 用 `'by ${login} · ${date} · ${state}'` 手工拼接（含 `by` 英文前缀），`commit:118`/`release_detail` 无作者行。修复：抽 `OgLDetailMetaRow` 组件统一"作者 · 时间 · 状态"，`by` 前缀走 i18n（UX_WRITING 交叉）。

**C-M6 · 排序入口只有一页有、且藏在设置里**：`settings:919-930` 有全局 tagSort，`repo_tags:78-85` 消费它，其他列表页（gists/dashboard/notifications）无任何排序控件。修复：明确"哪些列表支持排序"清单并在这些列表页 AppBar actions 放统一 `Icons.swap_vert` 排序入口；或反之移除全局 tagSort 改为 repo_tags 页内排序，避免"排序藏在设置里"的隐性逻辑。

**C-M7 · 图标尺寸令牌使用不一致**：`about:140/162/178` 用 `OgLIconSize.md`，`settings:2308` 用 `OgLIconSize.sm`，`code_editor_toolbar:144` 裸 `Icon(Icons.remove)` 无 size，多数 IconButton 用默认 24dp。修复：全库图标统一走 `OgLIconSize` 三档（sm/md/lg），告警图标用 `Icons.warning_amber_rounded`（7 处 ✅ 样板），消除裸 `Icon()` 无 size 写法。

**C-M8 · 状态图标 `sync` 与动作图标 `refresh` 视觉近似易混**：`repo:3537`/`action_run:470` 用 `Icons.sync` 表示"进行中"状态，`refresh` 表示"重试"动作。修复：状态用 `Icons.hourglass_empty` 或带旋转动画的 progress 指示器（回链 3-B 状态），动作才用 `refresh`，避免用户把状态当可点按钮。

**C-M9 · 打开本地文件 vs 打开网页同一图标**：`download_manager:503` "打开本地文件"、`file_preview:213`/`gist_detail:395` "在浏览器打开" 全用 `open_in_new`。修复：`open_in_new` 专用于外部 URL，本地文件用 `Icons.open_in_new` 可接受但 tooltip 必须区分（当前 tooltip 已区分 ✅），建议本地文件改 `Icons.folder_open` 增强区分。

**C-M10 · 空态/错误态图标语义不统一**：`gist_detail:364` emptyIcon=`article_outlined`，`notifications:221` 用 `done_all`（"全部已读"空态），`file_preview:459` 用 `link_off`（文件过大）。修复：抽 `OgLEmptyIconFor(kind)` 按语义（内容空/筛选空/加载失败/权限不足）返回固定图标，避免每页自造（回链 3-B 状态完整性）。

### 🟡 轻（6 条）—— 打磨与治理

**C-L1 · 复制图标 `Icons.copy` 仅出现 1 次（`search:949`）**：全库唯一孤例，见 C-S2，随其修复。

**C-L2 · `search_page` 单页两个 AppBar**：`:716` 主搜索栏 + `:1318` 结果页 `OgLAppBar(title: _t('searchResults'))`，是唯一双 Scaffold 页。修复：确认是 push 新页而非同页重构；若是 push，结果与主搜索页 AppBar 模式需一致（都用 OgLAppBar ✅）。

**C-L3 · Off-stage 页面 onboarding 用原生 AppBar 且可空**：`onboarding:221` `appBar: widget.review ? AppBar(...) : null`，全库唯一条件式 AppBar。修复：引导页整体属特殊流程可豁免，但 review 态建议也切 `OgLAppBar` 以对齐（回链 5-A 启动链路）。

**C-L4 · "编辑器缩放"用 `Icons.remove`/`Icons.add` 表达字号增减**：`code_editor_toolbar:144/148` 用减号/加号图标，语义尚可但与其它页 `Icons.text_decrease`/`text_increase` 惯例不同。修复：统一字体缩放图标，若保留则加 tooltip（当前有 `fontSmallerTooltip` ✅）。

**C-L5 · 图标语义缺单一事实源**：全库 130+ 处 `Icon(Icons.*)` 直接内联，无 `OgLIcons` 语义映射层（对照 `rules/03 §1b` 闭环词表）。这是 C-S2/S3/S4 反复出现的**根因**。修复：新建 `lib/surface/util/og_l_icons.dart`，导出 `OgLIcons.copy / .refresh / .openExternal / .delete / .cancel` 语义常量，各页按语义引用而非直接写 `Icons.x`；配合 CI grep `Icons.copy|Icons.link` 直接引用。

**C-L6 · 明暗主题一致性总体良好但缺回归护城河**：页面+widgets 中 `brightness ==` / `Colors.white|black` 0 处，主题统一由 `buildOgLTheme(brightness)`（`theme.dart:152`）生成，明暗走同一套组件主题（唯一分支在 `theme.dart:263/268` SnackBar 与 `boot_splash.dart:32`）。修复：保持该纪律，补一条 CI grep `brightness ==|Colors\.(white|black)` 于 `lib/surface/pages/` 应为空，防止未来漂移。

---

## 2. 图标语义全库统计（rg Icons. 逐类）

> 方法：`rg -o "Icons\.[A-Za-z0-9_]+" lib/ | sort | uniq -c` 后逐调用点读 tooltip/label 判语义。

| 动作语义 | 出现的图标（file:line） | 一致？ |
|---|---|---|
| **删除** | `delete_outline`×11（profile:275, issue:401, repo_tags:250, gist_detail:358, settings:784/1612, drafts:243, release_detail:475, download:514, repo:2034…）；`delete_sweep_outlined`×1（notifications:186 批量）；`close`(download:496)/`cancel_outlined`(action_run:638) 属"取消"非删除 | ⚠️ 批量孤例（C-M2） |
| **刷新/重试** | `refresh`×3（action_log:318, action_run:622, download:489）；`restart_alt`×3（download:211, action_run:631, 另 1）；`sync`×2（repo:3537, action_run:470，实为状态） | ❌ 冲突（C-S3/C-M8） |
| **分享** | 全库**无 `Icons.share`**；对外发送借 `open_in_new`/`content_copy` 表达 | ⚠️ 无统一分享语义（C-S4/L5） |
| **复制** | `content_copy`×4（settings:2308, notifications:393, download:508, about:140）；`copy_all_outlined`×3（release_detail:470, gist_detail:463, action_log:307）；`Icons.copy`×1（search:949）；`Icons.link`×2 配复制文案（release_detail:355, repo:592） | ❌ 四类并存（C-S2） |
| **打开外部** | `open_in_new`×13（主流 ✅）；`language`×1（search:959）；`link`×3 用于打开（about:134, file_preview:408, settings:775） | ⚠️ 边缘漂移（C-S4） |
| **溢出菜单** | `more_vert`×1（issue:728 AppBar）；`more_horiz`×3（issue:840, search:240, release_detail:550 行内） | ⚠️ 需文档定规则（C-M1） |

---

## 3. 修复指令（按稳定感优先排序，均只给改法不改码）

1. **P0 · 统一 AppBar（治 C-S1/C-L3）**：建 `OgLAppBar` 为唯一应用栏；把 15 页原生 `appBar: AppBar(` 逐一替换，自建 ScrollController 页传 `scrollController:`。参照 `og_l_app_bar.dart:25-45` 的参数签名与 `theme.dart:283` 的融合基线。
2. **P0 · 建语义图标层（治 C-S2/S3/S4/M1/M3/L1/L5 根因）**：新建 `lib/surface/util/og_l_icons.dart`，定义 `OgLIcons.{copy, copyAll, refresh, retryAll, openExternal, delete, deleteBatch, cancel, overflowTop, overflowRow}`；逐页替换内联 `Icons.x`；`Icons.link` 只留静态 URL 展示；CI 加 grep 禁止 `Icons.copy|Icons.language|Icons.link` 在复制/打开语境复发。
3. **P0 · 统一分页交互（治 C-S6）**：`repo_page:770-830` 改 `NotificationListener<ScrollNotification>` 距底 300px 自动加载，与 `dashboard:129`/`search:445` 同构；修正 `repo_page.dart:8` 注释。
4. **P1 · 统一筛选控件规则（治 C-S5/M4）**：≤3 档 `SegmentedButton`、>3 档横滑 `FilterChip`；`notifications:196` 改 FilterChip；页头 padding 统一 `lg/md/lg/xxs`。
5. **P1 · 详情页模板（治 C-S7/M5/M9）**：AppBar 标题统一为对象标识；actions ≥3 收 PopupMenu、`pull:109` 补操作；抽 `OgLDetailMetaRow` 统一副标题。
6. **P1 · 启动兜底主题（治 C-S8，回链 5-A）**：`OgLBootFailureApp` 接收 brightness 入参，替换 `og_l_app.dart:177` 的写死 `Brightness.dark`。
7. **P2 · 状态/空态图标分层（治 C-M8/M10）**：`sync` 状态改 progress；抽 `OgLEmptyIconFor(kind)`。
8. **P2 · 排序入口归位（治 C-M6）**：`tagSort` 从 `settings:919` 下沉到 `repo_tags` 页内，或给所有可排序列表加统一 `swap_vert` 入口。
9. **P2 · 主题回归护城河（治 C-L6）**：CI grep `brightness ==|Colors\.(white|black)` 于 `pages/`+`widgets/` 必须为空。
10. **P3 · 图标尺寸令牌化（治 C-M7/L4）**：全库图标走 `OgLIconSize` 三档，消灭裸 `Icon()` 无 size。

---

## 4. 检查清单（已查项 · 含未发现问题的部分）

- [x] `rg -l "Scaffold" lib/surface/pages/*.dart` = 30，逐页归入 5 域（仓库/议题/内容/账户/工具），**30/30 全覆盖**，见 §5。
- [x] 图标语义：对删除/刷新/分享/复制/打开外部/溢出 6 类逐一 `rg Icons.` 统计并读 tooltip/label 语境（§2），**5 类中 4 类有冲突**。
- [x] 同类页面模式：AppBar 类型（OgLAppBar 15 / 原生 AppBar 15）、筛选控件（4 类）、分页（3 模式）、详情标题/操作区布局——逐页归类计数。
- [x] 文案与视觉配合：重点核 `Icons.link` 配"复制"文案（release_detail:355/repo:592）、search 弹层两个"打开"不同图标（:944/:959）。
- [x] **明暗主题一致性（未发现问题项）**：`rg "brightness ==|Brightness\.(dark|light)|Colors\.(white|black)" lib/surface/pages/ lib/surface/widgets/` = **0 处**；主题统一由 `theme.dart:152 buildOgLTheme(brightness)` 生成，明暗分支仅在 `theme.dart:263/268`（SnackBar）与 `boot_splash.dart:32`。**页面/widgets 无单主题硬编码，此项通过**（唯一例外 C-S8 启动兜底页，已列问题）。
- [x] 页头/筛选外边距、副标题格式、图标尺寸令牌、状态/空态图标——逐页抽查。
- [x] 跨席引用核对：C-S2→3-A S1、C-S6→repo_page.dart:8 注释、C-S7→pull:109、C-S8→5-A 启动链路、C-M2/M10→3-B 状态、C-M4→1-A S2、C-M8→3-B。
- [ ] 未做（超出本席职责）：运行态截图比对明暗双主题像素、真机验证 OgLAppBar 渐变曲线观感——交 5-A 启动链路 + 2-C 动效席。

---

## 5. 30 页逐页独立小节（按域，每页 3-5 行）

> 格式：**页面模式** / **与前页一致性差异** / **最突出问题（编号，file:line）**。域内按任务书轴二顺序。

### 仓库域（7 页）

**1. repo_page.dart**（仓库主页·详情混合体）
- 模式：`OgLAppBar` + PopupMenu 收纳次要操作 + 手动"加载更多"分页 + SegmentedButton/ChoiceChip 双筛选。
- 差异：与 dashboard/search 的自动无限滚动相反，是全库唯一还留手动加载按钮的列表页。
- 问题：❌ **C-S6**（`:820` 手动按钮 vs `:8` 注释自称统一）、**C-S2**（`:592` 复制克隆地址用 `Icons.link`）、**C-M8**（`:3537` 状态 `sync`）。

**2. repo_tags_page.dart**（标签列表页）
- 模式：`OgLAppBar` + `NotificationListener` 自动分页 + 全局 tagSort 排序（消费 settings）。
- 差异：分页模式与 dashboard/search 一致 ✅；但排序入口是全库唯一"藏在设置里"的页。
- 问题：❌ **C-M6**（`:78-85` tagSort 来源）、删除图标 `delete_outline`✅ 统一。

**3. commit_page.dart**（提交详情页）
- 模式：原生 `AppBar` + AppBar 显示短 SHA、body 显示真实标题（titleLarge）+ 无 actions。
- 差异：标题布局与 issue/pull 同构 ✅，但应用栏是原生（C-S1 阵营）。
- 问题：⚠️ **C-S1**（`:93` 原生栏）、**C-M5**（`:118` 副标题格式）。

**4. pull_page.dart**（PR 详情页）
- 模式：原生 `AppBar` + AppBar 显示 `#号`、body 真实标题 + **AppBar 无任何 actions**。
- 差异：与 issue 同为详情页但 issue 有 more_vert 溢出、本页全无操作入口。
- 问题：❌ **C-S7**（`:109` 缺 actions）、**C-S1**（原生栏）、副标题手工拼接（`:127`）。

**5. release_detail_page.dart**（Release 详情页）
- 模式：原生 `AppBar` + 两个 IconButton 平铺 + 行内 more_horiz + 大量 PopupMenu/BottomSheet。
- 差异：操作区一处平铺、一处 more_horiz，与 issue 的"全收起"不同。
- 问题：❌ **C-S2**（`:355` 复制用 `Icons.link`）、**C-S7**（`:463`/`:550` 操作区分裂）、**C-S4**（`:389` link 语义混用）。

**6. code_editor_page.dart**（代码编辑器）
- 模式：原生 `AppBar` + dirty 态 FilledButton.tonalIcon（3-A L20 样板）+ toolbar 裸图标。
- 差异：编辑态控件是全库最佳实践样板 ✅，但 toolbar 图标未走 size 令牌。
- 问题：⚠️ **C-S1**（`:579` 原生栏）、**C-M7/L4**（toolbar:144 裸 `Icons.remove`）。

**7. file_preview_page.dart**（文件预览页）
- 模式：原生 `AppBar` + 单 open_in_new 平铺 + 错误态 `link_off` 图标。
- 差异：与 gist_detail 同为内容预览，但 gist_detail 平铺删除、本页平铺打开。
- 问题：⚠️ **C-S4**（`:408` "使用原始链接"用 `Icons.link`）、**C-M9**（`:213` 本地打开与网页打开同图标）、**C-S1**。

### 议题域（4 页）

**8. issue_page.dart**（议题详情页）
- 模式：原生 `AppBar` + `more_vert` 溢出 + body 头部 titleLarge + 行内 more_horiz 评论操作。
- 差异：操作收起程度与 pull（全无）/release（平铺）都不同；more_vert/more_horiz 同页并用（符合规则但无文档）。
- 问题：⚠️ **C-M1**（`:728` vs `:840`）、**C-M5**（`:748` 副标题 `by` 前缀）、**C-S1**；删除图标 `delete_outline`✅。

**9. new_issue_page.dart**（新建议题）
- 模式：`OgLAppBar` + 表单页，无筛选/分页。
- 差异：新建类页面（new_issue/new_repo/new_release 用 OgLAppBar ✅）与 new_gist（原生栏）不一致。
- 问题：⚠️ 仅 **C-S1** 阵营差异（`:136` OgLAppBar ✅ 无自身问题）。

**10. notifications_page.dart**（通知中心）
- 模式：原生 `AppBar` + 4 档 `SegmentedButton` + done_all/delete_sweep 双操作。
- 差异：同为通知/列表页，dashboard 用 OgLAppBar + 2 档 SegmentedButton，本页原生栏 + 4 档 SegmentedButton。
- 问题：❌ **C-S5**（`:196` 4 档应改 FilterChip）、**C-S1**（`:170`）、**C-M2**（`:186` delete_sweep 孤例）、**C-M4**（页头 padding）。

**11. dashboard_page.dart**（首页）
- 模式：`OgLAppBar` + 2 档 SegmentedButton + 距底 300px 自动分页 + FAB。
- 差异：自动分页与 search/repo_tags 一致 ✅，与 repo_page 相反。
- 问题：⚠️ **C-M4**（页头 padding）、**C-S1** 中本页是正确样板（OgLAppBar ✅）；FAB 与 gists/repo 并存 ✅。

### 内容域（4 页）

**12. gists_page.dart**（Gist 列表）
- 模式：`OgLAppBar` + FAB + 下拉刷新 + 列表卡。
- 差异：与 drafts_page 同为列表卡页，两者都用 OgLAppBar ✅；与 dashboard 的筛选模式不同（无筛选）。
- 问题：✅ 模式无自身冲突；仅归档于 C-S1 统计（正确阵营）。检查了页头/FAB/刷新——未见新增一致性问题。

**13. gist_detail_page.dart**（Gist 详情）
- 模式：原生 `AppBar` + 删除按钮直接平铺 + `copy_all_outlined` + emptyIcon article_outlined。
- 差异：同为详情，issue 用溢出菜单、本页删除裸露（C-S7）。
- 问题：❌ **C-S2**（`:463` copy_all 应改 content_copy）、**C-S7**（`:356` 删除平铺）、**C-M10**（`:364` 空态图标）。

**14. new_gist_page.dart**（新建 Gist）
- 模式：原生 `AppBar` + 表单 + SwitchListTile。
- 差异：新建四页里唯一用原生栏（其余 new_issue/new_repo/new_release 用 OgLAppBar）。
- 问题：⚠️ **C-S1**（`:144` 原生栏，与同组新建页不一致）。

**15. search_page.dart**（搜索）
- 模式：`OgLAppBar`（双 Scaffold）+ FilterChip 横滑 + SegmentedButton + 距底 300px 自动分页 + 双列网格。
- 差异：筛选控件是最规范的 FilterChip 样板 ✅，但底部操作单里 `Icons.copy`/`Icons.language` 是孤例。
- 问题：❌ **C-S2/L1**（`:949` 全库唯一 `Icons.copy`）、**C-S4**（`:959` language 与 `:944` open_in_new 冲突）、**C-L2**（双 AppBar）。

### 账户域（8 页）

**16. login_page.dart**（登录）
- 模式：原生 `AppBar` + 单 `open_in_new` 操作 + 引导型布局。
- 差异：与 onboarding 同属账户入口流程，一个原生栏一个条件栏。
- 问题：⚠️ **C-S1**（`:326`）、**C-S4**（`:470` open_in_new 打开外部 ✅ 语义正确）。

**17. onboarding_page.dart**（引导）
- 模式：条件式 `AppBar`（review 态才有）+ 全库唯一可空 appBar。
- 差异：唯一无统一应用栏的页面。
- 问题：⚠️ **C-L3**（`:221` 条件栏）、`remove_circle_outline`(`:500`) 用于列表移除属删除语义边缘。

**18. profile_page.dart**（个人主页）
- 模式：`OgLAppBar` + 下拉刷新 + 列表卡 + dangerZone（移除账号）。
- 差异：与 settings 同为账户页但前者 OgLAppBar、后者主 OgLAppBar ✅ 一致。
- 问题：✅ 删除图标 `delete_outline`(`:275`) 统一；仅 **C-S1** 统计（正确阵营）。检查了卡片/操作区——未见新增一致性问题。

**19. settings_page.dart**（设置主页）
- 模式：`OgLAppBar` + 大量 ListTile/ChoiceTile + 全局 tagSort 排序 + `content_copy` 日志。
- 差异：排序藏在设置里（C-M6 源），复制日志用 sm 尺寸（C-M7）。
- 问题：❌ **C-M6**（`:919` tagSort）、**C-M7**（`:2308` OgLIconSize.sm）、**C-S4**（`:775` link 用于 URL 字段 ✅ 可接受）。

**20. settings_section_page.dart**（设置分组子页）
- 模式：`OgLAppBar(title: title)` + 无自身状态（由 settings 构造）。
- 差异：与 settings 主页同用 OgLAppBar ✅ 完全一致。
- 问题：✅ 未发现一致性问题。检查了 AppBar/标题传递/无独立筛选分页——干净。

**21. network_page.dart**（网络设置子页）
- 模式：`OgLAppBar` + 设置列表。
- 差异：与 settings_section_page 同为设置子页，模式一致 ✅。
- 问题：✅ 未发现一致性问题。检查了应用栏/列表/无弹层——干净。

**22. about_page.dart**（关于）
- 模式：`OgLAppBar` + 信息 ListTile + 多行 trailing 图标（open_in_new/content_copy 并用）。
- 差异：同页既有 `open_in_new`(打开) 又有 `content_copy`(复制) + `link`(URL 展示)，是图标语义最规范的样板 ✅。
- 问题：✅ 作为 C-S2/S4 修复的**参照样板**；自身无冲突。

**23. legal_text_page.dart**（法律文本）
- 模式：原生 `AppBar` + `DropdownButton` 选文本。
- 差异：Dropdown 用于"选一份文本"（选择语义 ✅），但应用栏原生。
- 问题：⚠️ **C-S1**（`:94`）、Dropdown(`:142`) 属选择非筛选，符合 C-S5 规则 ✅。

### 工具域（7 页）

**24. download_manager_page.dart**（下载管理）
- 模式：原生 `AppBar` + 顶部 restart_alt 批量重试 + 每行 refresh/close/open_in_new/content_copy/delete_outline 五图标。
- 差异：同一行内 refresh(重试) 与 restart_alt(批量重试) 并存，是全库图标语义最密也是最乱的一页。
- 问题：❌ **C-S3**（`:211` vs `:489`）、**C-M3**（`:496` close 取消）、**C-S2**（`:508` content_copy ✅ 正确）。

**25. workflow_dispatch_page.dart**（手动触发工作流）
- 模式：原生 `AppBar` + DropdownButtonFormField + Switch + 表单。
- 差异：与 new_* 表单页同为新建类，但用原生栏。
- 问题：⚠️ **C-S1**（`:412`）、Dropdown(`:564`) 属选择 ✅。

**26. action_log_page.dart**（工作流日志）
- 模式：原生 `AppBar` + search_off/search 切换 + `copy_all_outlined` + refresh + download_outlined。
- 差异：与应用运行详情页同属日志类，操作图标（copy_all/refresh/download）是全库最完整的 ✅。
- 问题：⚠️ **C-S2**（`:307` copy_all——"复制整份日志"属 copyAll 语义可保留）、**C-S1**；图标语义基本正确。

**27. action_run_page.dart**（工作流运行详情）
- 模式：原生 `AppBar` + download/receipt_long 平铺 + 状态 sync + 底部 refresh/restart_alt/cancel_outlined/open_in_new。
- 差异：同页 refresh(重跑) 与 restart_alt(重跑失败) 并存，状态用 sync。
- 问题：❌ **C-S3**（`:622` vs `:631`）、**C-M8**（`:470` sync 状态）、**C-M3**（`:638` cancel_outlined ✅）。

**28. new_release_page.dart**（新建 Release）
- 模式：`OgLAppBar` + 表单 + SwitchListTile（draft/prerelease）。
- 差异：新建四页中的 OgLAppBar 阵营 ✅。
- 问题：✅ 未发现一致性问题。检查了应用栏/表单控件/无筛选分页——干净。

**29. new_repo_page.dart**（新建仓库）
- 模式：`OgLAppBar` + 表单 + SwitchListTile（private）。
- 差异：与 new_release/new_issue 模式一致 ✅。
- 问题：✅ 未发现一致性问题。检查了应用栏/表单/可见性开关——干净。

**30. drafts_page.dart**（草稿箱）
- 模式：`OgLAppBar` + 下拉刷新 + 列表卡 + delete_outline。
- 差异：与 gists_page 同为列表卡页，模式一致 ✅。
- 问题：✅ 删除图标(`:243`)统一；仅归档 C-S1 统计（正确阵营）。检查了页头/刷新/操作区——未见新增一致性问题。

---

## 6. 双轴说明与跨席移交

- **轴一（启动链路）交叉**：C-S8（启动失败兜底强制深色）与 5-A「启动链路」直接重合，已回链；C-L3（onboarding 条件栏）亦属启动后引导流程，建议 5-A 合并走查。
- **轴二（功能页面矩阵）**：本席 30/30 全覆盖，按 5 域分组（仓库 7 / 议题 4 / 内容 4 / 账户 8 / 工具 7），每页独立小节，可与其它 14 席按页索引合并。
- **交叉引用汇总**：C-S2→3-A S1；C-S6→repo_page.dart:8 注释漂移；C-S7→pull:109 缺操作；C-S8→5-A；C-M2/M10→3-B；C-M4→1-A S2；C-M8→3-B；C-M5→UX_WRITING。
- **给收口的建议**：C-S1（AppBar 两套）、C-S2（图标语义四类）、C-S6（分页三分）应进 `UX_STABILITY_PLAN.md` **P0「一致性/稳定感」组**——三者都是"同类场景不同处理"的教科书案例，修复收益（消除跨页认知断裂）远大于成本。C-L5 语义图标层是治本工程，建议与这批一并立项。
- **本席边界**：本席只做横切一致性，页面内密度/层级/动效/反馈细节分别归 1-A/2-A/2-C/4-A，未重复展开；明暗主题经查页面层无单主题硬编码，此项判定通过（见 §4）。
