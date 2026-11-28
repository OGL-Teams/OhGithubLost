# 十批全面审计 · 批 1「UI 视觉与布局」· C 席 —— 跨页一致性审计

> **文档戳 / Doc Stamp**
> - 审计批次：**十批 · 批 1 · C 席（跨页一致性）**；主 skill：`sota-frontend-design` + `frontend-design`
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `62c5383`（2026-11-28）
> - 更新时间：**2026-11-28 17:10 (Asia/Shanghai)**
> - 审计对象：`lib/surface/pages/*.dart`（**30 页全覆盖**）+ `lib/surface/app/`（外壳/AppBar/状态组件）+ `lib/surface/widgets/` + `lib/surface/theme.dart` + `lib/surface/util/og_l_{space,radius,font,icons}.dart`（令牌层）
> - 依据：`docs/TEN_BATCH_AUDIT_PLAN.md` 绝对纪律与批 1 行；`sota-frontend-design/SKILL.md`（AUDIT 模式、rules/03 §设计令牌、rules/07 §视觉漂移）；`frontend-design/SKILL.md`（同质化检查、视觉结构即信息）；历史基线 `docs/UX_CROSS_AUDIT/5-C-consistency.md`（v14，24 条）与 `docs/UI_AUDIT_V2/5-C-a11y.md`
> - 方法：`rg` 全库扫描 + 逐命中读语境；**只读审计，未改任何代码、未 commit / 未 push**；未读取 Flutter SDK / pub 缓存（禁读铁律遵守）
> - 纪律：先读全文再 append，本报告以 `file_write` 新建（本文件此前不存在），后续修订只 append

---

## 0. 结论速览

批 1 的 A 席查布局密度、B 席查色彩投影，本席（C）查**跨页面视觉一致性**：同一个 App 在不同页面之间，同类元素是否长得像同一套设计语言。

**一句话结论：令牌层已经很干净（间距/圆角/字号/色彩全部收编，零裸值），但"模式层"分裂依旧——最刺眼的是 14 页用滚动融合 `OgLAppBar`、16 页用原生 `AppBar`（顶栏高度行为不同），以及 v15 建的语义图标层 `OgLIcons` 只有 6/30 页采用，35 处动作图标仍裸写 `Icons.*`。这两点在 v14 的 5-C 审计里就列为 C-S1/C-S2，跨过 v15 与 MD2 迁移仍未闭环，正是用户说的「没有工具稳定感」的结构性来源。**

| 一致性维度 | 量化结果 | 判定 |
|---|---|---|
| 设计令牌（间距 OgLSpace / 圆角 OgLRadius / 字号 OgLFont） | 业务代码裸 `BorderRadius.circular(N)` **0 处**；裸 `fontSize:N`（除启动页 1 处）**0 处**；`Colors.*` 仅语义图标配色/语法高亮/透明色合法用法 | ✅ 通过 |
| 主题色 / 明暗分支 | 页面层 `brightness==` / `Colors.white|black` **0 处**，全部走 `ColorScheme` + `OgLSemanticColors` | ✅ 通过 |
| **AppBar 实现** | `OgLAppBar` **14 页** vs 原生 `AppBar` **16 页**（theme 里 `elevation:0`，OgLAppBar 内 `elevation:4`） | ❌ P1 头号裂缝 |
| **语义图标层采用率** | `OgLIcons.*` 全库 **9 次引用 / 6 页**；裸 `Icons.content_copy/copy_all/open_in_new/delete/refresh/restart_alt` **35 次 / 约 18 页** | ❌ P1 半拉子工程 |
| **加载态规格** | `CircularProgressIndicator(strokeWidth:2)` 8 处 + `strokeWidth:2.2` 启动页 1 处 + 无参（默认 4）3 处；`AsyncView` 仅 9 页使用 | ⚠️ P2 |
| **页面级水平留白** | `EdgeInsets.all(OgLSpace.md)` 26 处 / `.all(lg)` 23 处 / `.symmetric(horizontal:lg)` 6 处 等——同类卡片列表页 inner padding 12/16 并存 | ⚠️ P2 |
| 筛选控件 | `SegmentedButton` 4 页 / `FilterChip` 1 页 / `ChoiceChip` 1 页 / `DropdownButton` 3 页（v14 C-S5 仍在） | ⚠️ P2（归批 2 交互） |
| 底栏外壳三态 | `client_shell.dart` 单一实现，所有页经统一外壳 | ✅ 通过 |

**问题总数：6 条（P0: 0 / P1: 2 / P2: 4）**。全部带 `file:line` 证据、根因与修复指令。本席不重复报布局密度（A 席）与色彩投影（B 席），聚焦"跨页是否同一产品"。

---

## 1. 问题清单（按严重度 × 修复杠杆排序）

### P1-1 · 应用栏两套实现并存的跨页裂缝（v14 C-S1 未闭环）

**Where**
- 原生 `AppBar`（16 页）：`action_log_page.dart:290`、`action_run_page.dart:526`、`code_editor_page.dart:585`、`commit_page.dart:93`、`download_manager_page.dart:191`、`file_preview_page.dart:206`、`gist_detail_page.dart:340`、`issue_page.dart:767`、`legal_text_page.dart:100`、`login_page.dart:326`、`new_gist_page.dart:144`、`notifications_page.dart:159`、`pull_page.dart:109`、`release_detail_page.dart:458`、`workflow_dispatch_page.dart:413`（+ onboarding 审阅态）
- `OgLAppBar`（14 页）：`about:349`、`dashboard:...`、`drafts`、`gists`、`network`、`new_issue:135`、`new_release:161`、`new_repo:138`、`profile:205`、`repo:539`、`repo_tags:164`、`search`、`settings`、`settings_section`
- 定义：`lib/surface/app/og_l_app_bar.dart:137-151`；主题：`lib/surface/theme.dart:322-330`（`AppBarTheme(elevation:0, backgroundColor:surface)`）

**Rule**：`sota-frontend-design/rules/03 §1`（组件消费同一令牌契约、单一事实源）；`rules/07 §6`（视觉漂移 auditing）；`frontend-design`（" cohesion and consistency are how people learn their way around"）。

**Impact**：用户从 gists 页（顶栏 elevation 4 真投影 + 滚动时 surface→surfaceContainerHighest 连续插值）滑到 notifications 页（原生 AppBar 吃 theme 的 `elevation:0` + `surfaceTintColor:transparent`，常态无边界、滚动无反馈），顶栏在"活"与"死"之间跳变。MD2 下 AppBar 本应是稳定的 elevated 边界层（elevation 4），两套实现让"同一产品的顶栏"失去统一语义——这是全库最容易被普通用户感知的一致性断裂。

**Root cause**：v14 审计已定此为 C-S1（严重 8 条之首），v15 与 MD2 迁移修了主题层的色值/投影，但**页面级 AppBar 调用点未收编**；`OgLAppBar` 文档注释（`og_l_app_bar.dart:56`）甚至还残留 "M3 原生 scrolledUnderElevation" 的旧语义，与 MD2 现状矛盾。

**Fix**（修复代理执行）：
1. 16 个原生 `appBar: AppBar(title: ..., actions: ...)` 收编为 `appBar: OgLAppBar(title: ..., actions: ...)`；`OgLAppBar` 已支持 `actions`/`bottom`（`og_l_app_bar.dart:34-36`）。对 `code_editor_page.dart:585` 传了 `style: theme.textTheme.titleMedium` 的自定义标题，需在 `OgLAppBar` 增 `titleStyle` 可选参或接受统一 `titleLarge`（后者更一致）。
2. 统一主题基线：`theme.dart` 的 `appBarTheme.elevation` 由 0 改为 4（MD2 规范），`OgLAppBar` 内部不再硬写 `elevation:4`（改为继承主题），消除"主题说 0、组件说 4"的自相矛盾。
3. 清理 `og_l_app_bar.dart:6,10,56,146-149` 中 M3 `scrolledUnderElevation` / `surfaceTint` 的残留注释（代码洁癖：无旧体系痕迹）。
4. 对自建 `ScrollController` 的页（issue/pull/commit 等）显式传 `scrollController:` 启用连续插值；无控制器的页靠主题 elevation 4 提供稳定边界。
5. 验收：`rg -n 'appBar: AppBar\(' lib/surface/pages` → 0 处（login/onboarding 的特殊 leading/bottom 若确需保留，改用 `OgLAppBar` 扩展参或加入白名单并在报告写明理由）；截图矩阵顶栏观感一致。

**Effort**：medium（16 页机械替换 + 主题/组件两行 + 测试断言同步）。

---

### P1-2 · 语义图标层 `OgLIcons` 建了但 80% 页面没接——同类动作图标仍多套并存

**Where**
- 语义层定义：`lib/surface/util/og_l_icons.dart`（v15 建，注释明说"统一复制/刷新/打开外部/删除/分享"）
- 采用者（仅 6 页 / 9 处）：`about:1`、`download_manager:1`（retryAll）、`file_preview:1`、`release_detail:2`、`repo_page:1`、`search:2`
- 裸写动作图标（35 处 / 约 18 页）：`action_log:307(copy_all),318(refresh)`、`about:146,168,184,343(content_copy/open_in_new)`、`login:470`、`repo_tags:240(delete)`、`profile:266(delete)`、`drafts:235(delete)`、`issue:445(delete)`、`settings:771(link),780/1608(delete),2304(content_copy)`、`gists:181(open_in_new)`、`notifications:390(content_copy)`、`download_manager:475,489,494,500`、`gist_detail:344,385,453`、`search:958`、`release_detail:471,476`、`file_preview:214`、`repo_page:599,1330,2041,2077,4620`、`action_run:626,635,656`
- 另有 `Icons.language` 1 处（search 打开外部）、`Icons.link` 4 处（其中 settings:771 静态 URL 合法）

**Rule**：`rules/03 §1`（语义令牌单一事实源）；`rules/07 §6`（图标语义漂移 = 视觉 drift）；`frontend-design`（结构即信息，图标是结构标记）。

**Impact**：用户靠图标形成肌肉记忆——同一个"复制"动作，about:146 是 `Icons.content_copy`、release_detail:471 是 `Icons.copy_all_outlined`、`search` 用 `OgLIcons.copy`，同一"删除"在 8 页裸写 `Icons.delete_outline` 而 `OgLIcons.delete` 几乎没人用。v14 5-C 的 C-S2/C-S3/C-S4（复制四图标、重试两图标、link 跨三义）到今天部分改了具体图标值，但**治理机制（语义层）形同虚设**，老问题换了皮还在。

**Root cause**：v15 建了 `OgLIcons` 但只迁移了少数点，没有全库扫尾；`Icons.copy` 在 v14 审计时仅 1 处，现在涨到 9 处（含 Flutter 内部 API 之外的输入框粘贴等合法用法，需逐点甄别），说明期间新增代码仍在裸写。

**Fix**：
1. 全库"复制 X 到剪贴板"统一 `OgLIcons.copy`（覆盖 `content_copy`/`copy_all_outlined`/`Icons.copy` 三套，批量复制才用 `copyAll`）；"在浏览器打开"统一 `OgLIcons.openExternal`（含 `search` 的 `Icons.language`）；"删除"统一 `OgLIcons.delete`；"刷新/重试"按 v15 约定区分 `OgLIcons.refresh`（单次）与 `OgLIcons.retryAll`（批量，`download_manager:211` 已用✅，但 `action_run:635` 等仍裸写）。
2. `Icons.link` 只保留静态 URL 展示（settings:771 ✅），动作"复制链接"一律不用它。
3. 加门禁：`tool/ui_audit.py` 增一条规则——pages/widgets 中出现 `Icon(Icons.content_copy|copy_all_outlined|open_in_new|delete_outline|refresh|restart_alt)` 即报违规（语义层必须经 `OgLIcons.*`），防止再次漂移。
4. 验收：`rg -n 'Icon\(Icons\.(content_copy|copy_all_outlined|open_in_new|delete_outline|refresh|restart_alt)' lib/surface/pages` → 0 处。

**Effort**：medium（~35 处替换 + 1 条门禁）。

---

### P2-1 · 加载指示器规格三套（strokeWidth 2 / 2.2 / 默认 4）

**Where**：`CircularProgressIndicator(strokeWidth: 2)` 8 处（`action_run:540`、`code_editor:607`、`issue:778,1001`、`login:418`、`repo:4618`、`workflow_dispatch:492`、`readme_view`）；`strokeWidth:2.2` 启动页 1 处（`boot_splash`）；无参（默认 4）3 处（`file_preview:497`、`repo:861,2422,2495`）。

**Rule**：`rules/03 §4`（加载态一致性）；`rules/07 §6`（视觉 drift：同一"等待"符号粗细三种）。

**Impact**：等待态是全局高频状态，同一 App 里 spinner 粗细不同，虽然微小但属于"打磨不够"的范畴；`AsyncView` 只在 9/30 页使用，另外 21 页各自 handle 加载态，是规格漂移的结构原因。

**Fix**：在 `async.dart` 或 `widgets/` 提供 `OgLProgress` 统一封装（`strokeWidth:2`、颜色走 `ColorScheme.primary`），所有页面替换；`boot_splash` 的 2.2 按启动页特殊语境保留但加注释说明为什么不同，或统一为 2。

**Effort**：small。

---

### P2-2 · 页面级水平留白 12/16 混用（同类卡片列表页 inner padding 不统一）

**Where**：全 30 页的 `EdgeInsets.all(OgLSpace.md)` 26 处 vs `.all(OgLSpace.lg)` 23 处 vs `.symmetric(horizontal:OgLSpace.lg)` 6 处；`OgLSpace.cardInner = all(md)` 已定义（`og_l_space.dart:57`）但多数页未使用。

**Rule**：`rules/07 §5`（密度校准、对齐）；`frontend-design`（alignment guidance）。

**Impact**：同为列表卡页面，gists/drafts 卡片内边距 12、profile/notifications 16，跨页视觉节奏忽紧忽松。令牌本身有 `cardInner` 语义常量却闲置，属于"有令牌不消费"。

**Fix**：定义"页面级 padding 语义"——卡片内统一 `OgLSpace.cardInner`（all(md)），页面级左右统一 `OgLSpace.pageHorizontal`（symmetric horizontal lg），section 间统一 `sectionVertical`；逐页收编并在 `ui_audit.py` 加轻量提示。注意与 A 席布局密度结论交叉验证，避免与刻意紧凑的页（代码编辑器）冲突。

**Effort**：medium（~50 处收编，需逐页判断语境）。

---

### P2-3 · 筛选控件四分（v14 C-S5 未闭环，跨页模式漂移）

**Where**：`SegmentedButton` → `notifications:196`、`dashboard:416`、`search:1330`、`repo:2760/2889`；`FilterChip` → `search:826/1011`（注释自承窄屏溢出才改）；`ChoiceChip` → `repo:3588`；`DropdownButton` → `legal_text:142`、`workflow_dispatch:564`、`repo:4391`。

**Rule**：`rules/03 §3`（组件 API 一致性）；`frontend-design`（结构即信息）。

**Impact**：同为"从几个选项中筛选"的场景，四种控件四种交互/视觉；search 页 5 档用了 FilterChip 而 notifications 4 档仍 SegmentedButton，标准不明确。

**Fix**：归批 2（交互一致性）主修。本席只记录：建议统一规则——≤3 档用 SegmentedButton，>3 档用 FilterChip 横滑，单选长列表才用 Dropdown；`search:820` 已有先例可参照。

**Effort**：medium（跨批 2 协同）。

---

### P2-4 · 主题注释与实现自相矛盾（MD2 痕迹残留，代码洁癖）

**Where**：`lib/surface/theme.dart:320-321` 注释 "scrolledUnderElevation=2 由 MD3 原生接管"；`:336` "导航栏（宽屏 Rail，MD2 形态）"与顶栏注释混排；`og_l_app_bar.dart:6,10,56,146-149` M3 `scrolledUnderElevation`/`surfaceTint` 字样；`og_l_radius.dart:8-9,49-54` 仍写 "对齐 M3 extra-large 28dp"、保留 `@Deprecated cXl`。

**Rule**：`TEN_BATCH_AUDIT_PLAN.md` 纪律 3（无残留旧体系 MD3 痕迹）；`rules/03 §1`（命名治理）。

**Impact**：注释误导后续维护者以为还在用 MD3 语义；`OgLRadius` 的 M3 字样与 MD2 迁移任务书（M-1：删 xl=28、cXl）矛盾——MD2_MIGRATION_REPORT 声称 `rg OgLRadius.cXl → 0`，但定义本身还在。

**Fix**：清理上述注释中的 M3 措辞，按 MD2 真实规格重写；`OgLRadius.xl` 已收敛为 12（符合 MD2），但注释仍说"对齐 M3 28dp"，改为"浮层级别，MD2 下与 cMd/cLg 同族"；`@Deprecated cXl` 若确认零引用则删除整个常量（代码洁癖）。

**Effort**：small。

---

## 2. 令牌层通过项（本席已检查、判定一致 ✅）

| 检查项 | 方法 | 结果 |
|---|---|---|
| 裸圆角 `BorderRadius.circular(N)` / `Radius.circular(N)` | `rg` 全 surface，排除令牌/主题定义 | **0 处** ✅ |
| 裸字号 `fontSize:N` | `rg` 全 surface | 仅 `boot_splash.dart:56` 启动页 1 处（特殊语境），其余 0 ✅ |
| 裸色值 `Colors.white/black` / `Color(0x)` 页面级 | `rg` 排除语义图标配色/语法高亮/透明 | 页面层 0 处 ✅ |
| 明暗分支 `brightness==` 页面层 | `rg` | 0 处（仅 theme.dart / boot_splash） ✅ |
| OgLSpace / OgLRadius / OgLFont / OgLSemanticColors | 定义完整、语义清晰 | 通过 ✅ |
| 外壳三态（client_shell） | 单实现贯穿全站 | 通过 ✅ |
| 语义图标层定义 | `og_l_icons.dart` 单一事实源存在 | 通过（采用率见 P1-2） ✅ |

---

## 3. 已检查清单（覆盖声明）

- [x] 30 页 AppBar 实现归类（14 OgLAppBar / 16 原生，逐页 file:line）
- [x] 全 surface 裸 `BorderRadius.circular` / `Radius.circular` 扫描（0 命中）
- [x] 全 surface 裸 `fontSize:N` 扫描（1 命中，启动页）
- [x] 全 surface `Colors.*` / `Color(0x)` 扫描（区分合法图标配色/语法高亮 vs 页面级裸值）
- [x] 全 surface `brightness==` 页面级分支扫描（0 命中）
- [x] 图标语义层采用率扫描（`OgLIcons.*` 9 次 / 裸动作图标 35 次，逐命中读语境）
- [x] 加载态 spinner 规格扫描（strokeWidth 2 / 2.2 / 默认 4 三套）
- [x] `AsyncView` 采用率（9/30 页）
- [x] 页面级 `EdgeInsets` padding 值频次统计（md 26 / lg 23 / 其他）
- [x] 筛选控件四类分布（Segmented/FilterChip/ChoiceChip/Dropdown）
- [x] 主题定义文件全文（`theme.dart` 1-483 行）
- [x] 令牌文件全文（`og_l_space/radius/font/icons.dart`）
- [x] `OgLAppBar` 实现全文（1-155 行）
- [x] 历史基线对照（v14 5-C 24 条 → v15/MD2 后闭环情况）
- [ ] 运行时截图核验（顶栏滚动态、320px、200% 缩放）——本席静态审计，标未验证，交截图回归席
- [ ] 屏幕阅读器 pass ——交 a11y 席

---

## 4. 给交叉汇总与修复席的建议

**P0**：本席无（没有"用户完全无法使用"级别的跨页问题；P1-1 是最接近的体验裂缝）。

**P1 必须闭环（2 条）**：
1. **P1-1 AppBar 统一**——最高杠杆，一处主题 + 16 页机械替换，直接消除最大跨页裂缝；与 MD2 主题收尾（B 席色彩投影）协同。
2. **P1-2 图标语义层全库收编**——v15 半拉子工程收尾，加门禁防漂移。

**P2 记录并排期（4 条）**：加载指示器统一（批 2 状态席可带）、padding 语义收编（与 A 席布局密度协同）、筛选控件统一（批 2 交互席主修）、MD2 注释清理（代码洁癖，0 风险可立即做）。

**跨席移交**：
- P1-1/P1-2 与 v14 5-C 的 C-S1/C-S2/C-S3/C-S4 同源，交叉汇总时合并去重。
- P2-2 padding 与 A 席"布局密度"结论交叉验证后再定收编范围。
- P2-3 筛选控件明确移交批 2 交互席，避免重复修复。
- 所有 P1 修复后需跑截图矩阵（`OGL_SCREENSHOTS=1`）核验顶栏/图标观感。

---

## 5. 本席对纪律的遵守声明

- 禁读 Flutter SDK：未读取 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码 ✅
- 只读审计：未改任何代码、未 commit / 未 push ✅
- 层级原则：本席未越级 import，仅审计 surface 层 ✅
- 报告纪律：先读全文再新建本报告；后续修订仅 append ✅
- 证据可复现：所有 file:line 均可用 `rg` 在本工作副本复现 ✅
