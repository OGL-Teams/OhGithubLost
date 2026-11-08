# 批6 · 视角C：UI 契约与规范（v12.0.0 LTS）

> 只审不改、未写 `lib/`；本文件为唯一产出。审计时点：HEAD `721fbc9`（`pubspec.yaml:21` = `12.0.0+120000`）。
> 裁决依据：`docs/QUALITY_STANDARD.md`（59 条原则）、`AGENTS.md`。
> 确证等级：「确证·静态」= 完整读文件 + rg / 脚本实跑可静态复现；「未确证」= 依赖运行期行为（本环境无 Flutter SDK，未跑 `flutter test`），只标记疑点，不冒充缺陷。
> 风格偏好、措辞偏好一律不计缺陷；「注释已坦白的未接线」按实际影响降级，不重复拔高。
> 本批实跑：四支门禁 `python3 tool/{ui,motion,perf,contract}_audit.py --fatal` 全部 exit=0；另以脚本在**不改仓库文件**的前提下禁用白名单 / 注入合成用例做盲区复验（见 B6-C-06/07/08/09）。

## 发现清单

### B6-C-01 [P0] 四线 UI 的 widget 测试系统性缺口：六个改动页面零 import、零断言（B5 交叉 G1 在 UI 域原样复现）
- **文件:行号**：`test/surface/`（18 文件 / 2656 行）；对照 `lib/surface/pages/{search_page.dart:1-1255, issue_page.dart:1-1087, repo_page.dart:1-4509, release_detail_page.dart:1-557, action_log_page.dart:1-560, action_run_page.dart:1-784}`、`lib/surface/widgets/log_search.dart:1-93`、`docs/audit_b5_cross.md:8`
- **问题**：逐个 `file_read` 读完 `test/surface/` 全部 18 文件后确证：四线改动的六个页面在 `test/` 中**零 import**（rg 全库仅 `test/screenshots/screenshot_matrix_test.dart:50` 引用 `repo_page.dart`，且该文件默认只跑一次冒烟截屏，不是行为断言）；`OgLLogSearchBar` 零测试；`log_body_test.dart:16-66` 的 3 个 widget 用例只覆盖无查询的分块渲染，`query` / `jumpToken` / `highlightColor` 三个查找参数（正是线4新增能力）**零测试**。`test/surface/settings_collapse_test.dart:3-5` 自述「完整 widget 测试需要 flutter test（本环境无 SDK）… 靠 CI 端」，即缺口是已知的、无人补的。
- **后果**：`docs/audit_b5_cross.md` 的 G1 已把「测试对状态机核心分支失明」定 P0 并写明「列批 6 后第一优先（需 widget 测试框架）」；本批复验确认该优先级在 UI 域**未落地**。B6-C-04（jobs 链路未接线）、B6-C-05（查找计数/跳转三套编号不一致）都是「CI 全绿 + 无任何离线断言」下存活的静态可证缺陷，正是这一缺口的直接产物——它们可以在任何测试都不失败的情况下被改坏，反之也不会被测试发现。
- **原则**：51（破坏性/正常路径同等重要、回归守卫）、49/50（离线、接口+内存实现）、53（语义严密性靠人读，但人读不能替代守卫）
- **证据**：确证·静态。`rg -l 'search_page|issue_page|release_detail_page|action_log_page|action_run_page|DiscoverPage|SearchResultsPage|ActionLogPage|ActionRunPage|IssuePage|ReleaseDetailPage' test/` → 零命中；`test/surface/` 18 文件的 import 清单逐个核对（见覆盖清单）；`async_test.dart` / `async_sliver_test.dart` / `smoke_test.dart` 只测 `AsyncController`/`AsyncView`/`OgLAsyncSliver`/`OgLBootFailureApp` 等公共构件，不测任何页面。未跑 `flutter test`（无 SDK），不冒充「线上 widget 会崩」。

### B6-C-02 [P1] `PagedController` 全类零测试：五条自述语义（快照 / 排队 / 代次 / 释放 / 空结果）无任何离线守卫
- **文件:行号**：`lib/surface/app/paged_controller.dart:1-233`；对照 `test/surface/` 全目录、`lib/surface/pages/repo_page.dart:876,2629,2816,2938,3093,3342,3424`（7 个实例）
- **问题**：头注释 :8-13 写「语义清单（提取时逐条保留，**勿在别处顺手改**）」并列出快照 TTL 6 秒 / 刷新排队重放 / 请求代次 / 释放保护；:205-209 另有 ★ 注释「空结果不进快照：一次失败/瞬时空响应不该在 6 秒 TTL 内持续把页面显示成空」。实跑 `rg 'PagedController|paged_controller|clearCaches' test/` → **零命中**：整个类没有单测，四种语义（含 `_recentPage` 进程级共享、`_refreshQueued` 重放、`generation != _generation` 丢弃、空结果不写快照）无一条被断言。唯一沾边的是 `test/surface/settings_test.dart:447` 的「load 世代守卫 S3」，测的是 `OgLSettingsController`，与分页控制器无关。
- **后果**：这是仓库页八个标签共用的分页核心（7 处 `late final PagedController`）。曾修过的竞态（重复条目 / 第一页缺失 / 刷新被静默丢弃）与批3后新增的「空结果不进快照」都可以在**全部离线测试仍绿**的情况下被改坏；`clearCaches()`（切号清快照，防跨账号私有数据残留，`repo_page.dart:760` + `profile_page.dart:118,162` + `login_page.dart:188`）同样零断言。
- **原则**：51、49/50、22/27（并发假设必须被验证）
- **证据**：确证·静态。`paged_controller.dart` 全文（含 `_load` :159-232 的 generation / `_refreshQueued` / `items.isNotEmpty` 分支）；`rg` 全 test 目录零命中；`python3 tool/*_audit.py --fatal` 四支全绿不覆盖任何 Dart 行为。

### B6-C-03 [P1] `AsyncController` 世代计数与 `reset()` 零调用、零测试；注释描述的「切目录撕裂」实际由另一个类承担
- **文件:行号**：`lib/surface/app/async.dart:63-68,123-150,163-176`；对照 `test/surface/async_test.dart:1-168`、`lib/surface/app/paged_controller.dart:123,147,196,218`、`lib/surface/pages/repo_page.dart:1963`（`_goTo`）
- **问题**：:63-68 用 6 行注释解释 `_generation` 的 why（「切目录时旧请求返回会覆盖新目录的数据（撕裂）… 页面在数据被旧数据覆盖或永久转圈之间随机」），:163-167 又给 `reset()` 一段「典型场景：仓库浏览器切换目录」的说明；但 `rg 'reset\(' lib test` 全库只有 `OgLSettingsController.reset`、`OgLBackGuard.reset` 两处，**`AsyncController.reset()` 零调用点**、`_generation` 因此恒为 0；`async_test.dart` 的 7 个用例（空结果/失败/软错/并发抑制/loadIfNeeded/dispose）**无一测世代或 reset**。真实「切目录」走的是 `repo_page.dart:1963` 的 `_entries.refresh()` → `PagedController._generation`，与本类无关。
- **后果**：注释把「防撕裂」的功劳记在一个从未被触发的机制上，而真机制在另一个文件；后人按注释删掉 `async.dart` 的 `_generation` 或反之误以为「切目录已被 AsyncController 保护」都不会有任何测试报警。属注释-实现归属错置 + 未验证的防御性代码（非功能损坏，当前零调用故无线上影响）。
- **原则**：54（注释解释 why，且 why 必须为真）、55（未接线的半成品属死代码）、51
- **证据**：确证·静态。`async.dart:126,136,146,169` 四处世代判定；`rg -n '\.reset\(' lib test` 全量输出；`rg -n '_generation|世代|generation' test/surface` 仅 `back_guard_test.dart:69` 与 `settings_test.dart:283,447`。`async_test.dart:144-167` 的 dispose 守卫测试确证存在且有效（本条不否定它）。

### B6-C-04 [P1] `action_log_page` 的 jobs 控制器从未发起请求：失败置顶 / 结论状态点 / 默认展开整条链路未接线
- **文件:行号**：`lib/surface/pages/action_log_page.dart:104-107,124-143,379,448-462,470-480,514,534-544`；对照 `dispose()` :110-116
- **问题**：`initState`（:104-107）只调 `_logsC().loadIfNeeded()`；`_jobsC()`（:124-143）是惰性构造 `AsyncController`，其 `loader` 调 `workflowRunJobs`，但**全文件没有 `_jobsC().load()` / `.loadIfNeeded()`**（:320 的 `.load()` 是 `_logsC()`）。唯一消费点在 `build` 的 :379 `final ... jobs = _jobsC().data;` —— 因从未加载，`data` 恒 `null`，:379-385 的结论表恒为空。于是：:470-480 `_JobGroupList` 的 `bad = keys.where(failed)` 恒空 → 「失败 job 置顶 + 默认展开」不生效；:490-500 `_dotColor` 恒走 `default` 分支灰点；:514 的 key 里 `$initiallyExpanded` 恒 false。`dispose()`（:110-116）也只 dispose `_logs`/`_query`/`_debounce`，不 dispose `_jobs`（附带的 dispose 不对称）。
- **后果**：文件头 :7-9 承诺「**失败 job 置顶 + 默认展开**，组前的状态点按 job 名对齐运行详情页的 job 结论（本页自取 jobs 接口）」，:124-128 还把「结论缺失按未知灰点，不猜成功」写成**降级设计**——实际是请求从未发出、退化路径变成唯一路径。这是静默降级：用户看到恒灰的状态点与不置顶的失败 job，没有任何痕迹说明「结论接口没被调用」。
- **原则**：15（静默降级是最严重的缺陷）、54（注释-实现一致）、22、24（释放对称）
- **证据**：确证·静态。`rg -n '_jobsC|_jobs|\.load\(|loadIfNeeded' action_log_page.dart` 全量输出仅 :86/:107/:125/:142/:320/:379；:320 明确为 `_logsC().load()`；`_jobs` 名字在全文仅 4 处（声明、exists 读、赋值、build 读 data），无任何 load。这是四线（线4）批3新增代码。不冒充「线上一定显示异常」的观感结论，只确证「链路未接线 + 注释与实现不符」。

### B6-C-05 [P1] 日志查找的「当前第几处」三套编号不一致，且 `OgLLogBody.jumpToken` 契约与调用方不符
- **文件:行号**：`lib/surface/pages/action_log_page.dart:99-102,213-241,346,543`；`lib/surface/widgets/log_body.dart:11-14,44-45,75-78,121-133`；`lib/surface/widgets/log_search.dart:17-30,74-77`
- **问题**：三个静态可证的契约裂缝：
  1. **off-by-one**：`_searchIndex` 定义为「1 起；0 = 无」（:99），`_onSearchChanged` 置 1、`_jumpTo` 循环后仍落在 `1..total`（:221/:235-238），但 :346 传 `current: _search.total > 0 ? _searchIndex + 1 : 0`，`OgLLogSearchBar`（`log_search.dart:75`）直接渲染 `${widget.current} / ${widget.total}`。有 1 处命中时显示 `2 / 1`；往下翻到末处显示 `total+1 / total`。
  2. **token 语义错配**：`log_body.dart:14,44-45,121-133` 的契约是「`jumpToken` 变化时把**第 N 处命中**滚进可视区（N = `jumpToken` 的值）」，`_jump()` 用 `index = widget.jumpToken - 1` 索引 `_hits`；调用方（:222/:239）却把 `_jumpToken` 当作「变化即触发」的递增计数器（与 :102 注释「值变化触发…每次跳转 +1 或 -1」自相矛盾），且 `index >= _hits.length` 时 :127 直接 return，因此第 N 次跳转不会跳到第 N 处命中（它跳到「第 jumpToken 处」）。
  3. **跨 job 跳转无法实现**：`_scan`（:243-267）把命中按 job 名分组计数，`_jumpTo` :228-229 注释承诺「命中分布在多个 job 时循环跨 job」；但每个 `_JobCard`（:543）只在「本组有命中」时把 `jumpToken` 透传给自己的 `OgLLogBody`，而每份 `OgLLogBody` 的 `_hits` 只扫**本 job 的文本**（`log_body.dart:95-118`），全局序号从未折算为组内序号；`searchIndex` 更是透传到 `_JobCard` 后**从未被使用**（`_JobCard` :473-489 声明字段，build 中不读）。
- **后果**：线4 新增的「日志内查找 x/y 计数 + 上一处/下一处跳转」是文件头承诺的核心能力，当前计数显示越界、跳转序号与命中序号无关、跨组跳转无实现；`log_body_test.dart` 只测无查询的分块渲染（见 B6-C-01），这套编号错误离线无任何断言。
- **原则**：53（脚本只守语法、语义靠人读 → 人读发现契约不自洽）、52（空/无/未启用是三种「没有」；此处是 0/1 起编号混用）、54（注释-实现一致）
- **证据**：确证·静态。逐文件全文读 + 上列行号原文；`rg -n 'searchIndex|jumpToken|current:'` 三文件全量输出。跳转的**实际动画落点**依赖 `animateTo` 运行期，未跑 widget 测试，不冒充已观察到的 UI 结果；1、2、3 三条契约不符均为静态可证的编号/字段传递事实。

### B6-C-06 [P1] `ui_audit.py` 的 ALLOW 是整文件豁免：13 条过期/零命中条目 + 3 条理由与命中项不符；批3新增白名单把 560/1255 行页面整体放行
- **文件:行号**：`tool/ui_audit.py:37-61,99-105`（`is_allowed` / `scan` 的 `if reason: continue`）；对照 `AGENTS.md:33`、`docs/QUALITY_STANDARD.md:34`
- **问题**：
  1. **整文件豁免**：`scan()` :101-104 命中 ALLOW 即 `continue`，**跳过该文件全部 7 条规则**。本批以脚本在内存里禁用 ALLOW 重扫（不改仓库文件），实测全库 134 处命中；反过来逐条核对现有 ALLOW：**13 条当前零命中**（`og_l_space.dart`、`og_l_radius.dart`、`og_l_code_palette.dart`、`settings_page.dart`、`file_preview_page.dart`、`about_page.dart`、`commit_page.dart`、`gist_detail_page.dart`、`new_gist_page.dart`、`drafts_page.dart`、`pull_page.dart` 等），其中 `settings_page.dart`（2368 行，理由「含代码字体/字号选择器」）、`repo_page.dart`（4509 行，理由「含代码片段等宽文本」）、`action_log_page.dart`（560 行）、`search_page.dart`（1255 行）四线改动页被整文件放行。
  2. **理由与命中项不符**：`repo_page.dart:1487` 的真实命中是 `TextStyle(fontSize: 12)`（提示文案，非等宽上下文，文件确在 ALLOW 里躲过「裸 fontSize」）；`action_log_page.dart:92` / `search_page.dart:1061` 真实命中是 `Duration(milliseconds: 300)` 防抖常量（理由写「打字节流，非动效时长」——这**不是**设计令牌漂移，本就应由 motion 侧行内豁免处理，见 B6-C-08），批3 提交 `8ca3d41` 正是为 `action_log_page.dart` 新增了这条整文件放行。
  3. **通配符指向不存在的文件**：`'lib/surface/util/og_l_log_file*.dart'`（:60）在 `lib/` 下匹配 0 个文件（真实文件在 `lib/kernel/log/og_l_log_file*.dart`），属过期白名单。
  4. **规则本身漏检**：`RULES[1]` 正则 `SizedBox\((?:height|width): NUM\)` 只匹配「单参数紧跟右括号」；实测 `SizedBox(width: 72, child: ...)`（`release_detail_page.dart:427`，72 不在刻度 {4,8,12,16,24,32,48,64} 内）、`SizedBox(width: 46, height: 38)`（`desktop_window.dart:212`）**均不被检出**；`EdgeInsetsDirectional.only(start: 16, end: 12)`（`settings_group.dart:34,524`）也不在任何规则里。
- **后果**：`AGENTS.md:33` 宣称 ui_audit 是设计令牌门禁（原则 34「字面值每出现一次，主题的单一真相就裂开一道缝」），实际在四线改动最大的四个页面上等于关闭；`python3 tool/ui_audit.py --fatal` 实跑 0 处、exit=0 不代表令牌合规。新代码只要落在已白名单文件里，任何字面色 / 裸 fontSize / 裸圆角都不被检查。
- **原则**：34、55（过时的白名单是给后人的假情报）、53（脚本只守语法与结构，但结构检查本身要如实）
- **证据**：确证·静态 + 脚本实跑。`/tmp/diag.py`、`/tmp/diag2.py`、`/tmp/diag7.py` 复现（ALLOW 禁用 134 处逐条打印、逐条 ALLOW 命中数、`SizedBox`/`EdgeInsetsDirectional` 合成用例）；`git show 8ca3d41 -- tool/ui_audit.py` 显示批3新增 `action_log_page.dart` 条目；`python3 tool/ui_audit.py --fatal` 输出「0 处 / exit=0」。不把「零命中条目」本身当缺陷（可能是历史清理后的良性残留），缺陷是**整文件豁免 + 过期名单未复核 + 3 条理由错配**使门禁语义失真。

### B6-C-07 [P1] `motion_audit.py` 的行内豁免词是子串匹配且含 `ttl` / `cache` / `Cache`：整行四类禁令一并可绕过
- **文件:行号**：`tool/motion_audit.py:42-49`（`ALLOW_LINE_HINTS`）、:90-96（`if any(hint in line ...): continue`）；对照 `AGENTS.md:31`
- **问题**：`ALLOW_LINE_HINTS` 的 docstring（:23-24）说是「非动画的等待时长（节流、缓存 TTL、草稿防抖、双击退出窗口）用行内提示词豁免」，但实现是 `any(hint in line for hint in ...)` 的**整行子串**匹配，且列表含 `ttl`（会命中 `settleCurve`/`settle` 等 16 行）、`cache`（54 行）、`Cache`（64 行，含 `RepositoryCache` 声明/import）、`Timer(`、`debounce`、`exitWindow`。同一行只要出现这些词，四条 PATTERNS（硬编码时长 / `AnimatedScale` / 模糊 / `Curves.linear`）**全部不检查**。本批合成用例实跑：`final cacheLine = AnimatedScale(scale: 0.5, duration: Duration(milliseconds: 999), child: Cache);` 因含 `cache`/`Cache` 被完全放行（禁用提示词后会被「硬编码动画时长」+「硬编码缩放过渡」双命中）。实测当前仓库确有 3 处依赖提示词豁免的 `Duration(milliseconds: …)`：`action_log_page.dart:92`、`search_page.dart:1061`、`code_editor_page.dart:134`；这三处确属防抖/草稿等待，豁免**结论合理**，但豁免机制本身不受约束。
- **后果**：`AGENTS.md:31` 宣称 motion_audit 禁止硬编码动画时长/缩放/模糊/匀速；实际上任何含 `Cache` / `settleCurve` / `Timer(` 的行都能合法私造 `ScaleTransition` 或 `Duration(milliseconds: n)`。原则 33「动效是质量的刻度不是开关」、34「视觉值一律取自设计令牌」在门禁层留了后门；而 ui_audit 又为其中两个页面做了整文件放行（B6-C-06），两支门禁叠加后这两页的时长字面值不受任何检查。
- **原则**：33、34、53、11（防线没有开关：行内提示词是「绕过校验」的捷径）
- **证据**：确证·静态 + 脚本实跑。`/tmp/diag.py` 的「motion_audit with ALLOW_LINE_HINTS disabled」输出 3 处；`/tmp/diag8.py` 打印 :1-25 docstring 与 HINTS；`/tmp/diag5.py` 合成用例确证 `any(hint in line)` 的真值与 PATTERNS 命中；`python3 tool/motion_audit.py --fatal` 实跑「扫描 73 文件（白名单 2）/ 违规 0 / exit=0」。

### B6-C-08 [P2] `perf_audit.py` 的 ALLOW / REVIEWED_BOUNDED 名单过期：整文件 fatal 豁免 + 1 条零命中条目 + 1 条理由与事实相反；`AGENTS.md` 计数不符
- **文件:行号**：`tool/perf_audit.py:25-33`（ALLOW）、:45-53（REVIEWED_BOUNDED）、:172-180（fatal 分支）；对照 `AGENTS.md:30`
- **问题**：
  1. `ALLOW` 里 `'lib/surface/app/error_surface.dart': '通知宿主自身的窄列表'` 经全文读（619 行）与 rg 复核：`ListView|shrinkWrap|MediaQuery.of|Opacity` **零命中**，是过期条目；但该条目同时授予整文件 `shrinkWrap: true` 与 `MediaQuery.of(context)` 的 fatal 豁免（:177 `rel not in ALLOW` 才进 fatal）。
  2. `'lib/surface/pages/action_log_page.dart': 'OgLLogBody 内部已是 builder 虚拟化'` 理由与事实相反：该文件 :448 是 `ListView(children: [for ...])` 的**外层**急加载 job 组列表（`_JobGroupList`），`OgLLogBody` 是每个 `_JobCard` **内部**的正文控件；外层 job 组并未虚拟化。理由把内层能力套到外层列表上。
  3. `REVIEWED_BOUNDED` 只用于报告标注（不影响 fatal，脚本注释已坦白「急加载长列表只报告不拦截」），但 `'release_detail_page.dart': 'Release 附件（通常 < 30）'` 与 `'repo_page.dart': '分支选择弹层（…通常几十条）'` 等都是**无界远端数据**的估计，无任何断言/运行时上限；`repo_page.dart:4220` 的命中实际是仓库设置页（≈300 行表单），不是分支弹层——理由已漂移。
  4. `AGENTS.md:30` 写「白名单：ALLOW 7 文件 + REVIEWED_BOUNDED 7 文件」，实测 ALLOW **6** 文件 / REVIEWED_BOUNDED 7 文件。
- **后果**：`--fatal` 实跑 15 处命中全部被标注「已登记例外 / 已评估」并 exit=0；其中 `error_surface.dart` 的过期整文件豁免与 action_log 的错误理由，使这两条「登记时必须写清理由」的纪律（脚本自身 :24 注释）失去可核性。属白名单健康度与文档计数问题，定 P2（不冒充存在实际性能缺陷）。
- **原则**：55（过时白名单是假情报）、53（门禁自述须如实）、47（记录与事实一致）
- **证据**：确证·静态 + 实跑。`/tmp/diag2.py` 逐条 ALLOW / REVIEWED_BOUNDED 命中清单；`python3 tool/perf_audit.py --fatal` 输出 15 处（含 4 shrinkWrap / 2 MediaQuery / 8 急加载 / 1 Opacity）；`rg -n 'ListView|shrinkWrap|MediaQuery.of|Opacity' lib/surface/app/error_surface.dart` 零命中；`action_log_page.dart:448-452` 原文。

### B6-C-09 [P2] 门禁盲区复验（B5-C-12）：`[:400]` 窗口与条件导入**两项均未处理**，且门禁自述第 5 项仍未实现
- **文件:行号**：`tool/contract_audit.py:33,74-91,94-108,139-153`；对照 `docs/audit_b5_c.md:109-113`（B5-C-12）、`docs/audit_b5_cross.md:29`、`docs/audit_b3_c.md:86-91`（B3-C-12）
- **问题**：
  1. `check_headers` :101 仍是 `head = text[:400]`；本批以合成用例 `{'domain/zz.dart': '//' + 'a'*450 + '\n/// L2 中枢级 · …'}` 调用真实 `check_headers()` → 报「文件头缺 L2 层级前缀」，即**有正确前缀但超过 400 字符窗口的文件会被误报**；反向用例（前 400 字符内出现任意 `/// L3` 之类）也不会区分 L0/L3 语义。当前仓库 `lib/base|domain|surface` 全数通过（4 节 0 处、exit=0），说明只是**未被触发**，不是已修复。
  2. 条件导入仍未解析：`IMPORT_RE` 对 `import 'gh_oauth_stub.dart' if (dart.library.io) 'gh_oauth_io.dart' as impl;`（`lib/domain/gh/gh_oauth.dart:22`，全库唯一一条）只捕获 `'gh_oauth_stub.dart'`；`check_exports` :81 的 `if 'if (' in imp` 判断因捕获串里不含 `if (` 而**不生效**，被检查的只是 stub。合成用例把 io 分支改成不存在的文件，`check_exports` 返回空列表，确证 io 分支不可达解析。
  3. `check_headers` :99 显式 `lay == 'kernel'` 跳过整个 L0；实测 `lib/kernel/` 23 文件中 18 文件**全文任意位置**都没有 `/// L0` 前缀，而 `AGENTS.md:29` 宣称「查 L0–L3 文件头层级前缀」、`AGENTS.md:56` 把文件头层级前缀列为硬惯例。
  4. docstring :13 第 5 项「204/206 等状态码在写回执路径是否有对应的回归测试（弱提示）」**仍未实现**：`def check_` 全文恰 4 个（exports / headers / platform / doc_refs），`sections` 恰 4 键。B3-C-12 已点名，B5-C-12 复点，v12 仍未删该死描述。
- **后果**：`docs/audit_b5_cross.md` 把 B5-C-12 归入「P2 确证记录」而非「已修」，本批复核一致；`AGENTS.md:29` 的「L0–L3」自述越过了脚本实际能力（L0 完全不查），原则 53 要求门禁「如实声明守了什么」。`--fatal` 对头注释窗口 / 条件导入 / L0 三类违规保持沉默。
- **原则**：53、47（记录与事实一致）、57（文档引用的符号/能力必须真实存在）
- **证据**：确证·静态 + 实跑 + 合成用例。`python3 tool/contract_audit.py --fatal` 输出「4 节各 0 / 合计 0 / exit=0」；`/tmp/diag2.py` 的 `check_headers(fake)` / `check_exports(fake)` 输出；`/tmp/diag7.py` 打印 :94-108 源码、kernel 18/23 无 L0、真实条件导入的 `IMPORT_RE.findall` 结果、4 个 `def check_`。

### B6-C-10 [P1] 骨架屏注释与实现不符：`_SkeletonList` 声称「三 tab 共用」，实际只有一 tab 可达，另两处是建设性的死分支
- **文件:行号**：`lib/surface/pages/search_page.dart:37,55,101-119,190,216,289-290,551-552,675,945-947`；对照 `git show 8ca3d41`（批3 提交说明「发现页（线1）：… 骨架屏」）
- **问题**：:55 / :101 两处注释写「**三 tab 共用**」，:37 「加载态统一用主题色圆角块代替转圈」。实际上 `_feed` 在 `initState`（:190）同步构造，`:551` 的 `_feed == null` 恒为假；`_issues` 在 `_loadIssues()`（:289-290）第一条语句同步赋值（initState :216 虽 `unawaited`，但 Dart 在首次 await 前同步执行），`:945` 的 `_issues == null` 同样恒假；唯一可达的是 :675 推荐 tab 的 `_repos.isEmpty && _repoLoading`，以及 :759 的「加载更多」尾行。另两处 `_SkeletonList` 是**不可达分支**（`ValueKey('feed-skeleton')` / `ValueKey('issues-skeleton')` 永不构建）。首屏加载态实际由 `AsyncView` 的 `CircularProgressIndicator`（`async.dart:290-298`）呈现，与「统一用主题色圆角块代替转圈」相反。
- **后果**：批3（线1）新增的骨架屏注释给后人描述了不存在的统一加载语言；动态 / Issues 两个 tab 首屏显示转圈，推荐 tab 显示骨架块，三种 tab 视觉不一致——而注释宣称的「统一」无人复核（B6-C-01：六页零 widget 测试）。属注释-实现一致性 + 死分支，定 P1 而非 P0：不影响数据，只是 UI 契约失真。
- **原则**：54、55（不可达分支属死代码）、34
- **证据**：确证·静态。`rg -n '_feed = |_issues = |_loadIssues\(|_SkeletonList'` 全量输出；`_buildFeedTab` :551 与 `_buildIssuesTab` :945 的 null 判定；Dart 的 `async` 函数在首个 await 前同步执行（`_loadIssues` 的构造在 :290，任何 await 在 :292 之后），故 `_issues` 在首次 build 前已非 null。不依赖运行期，静态可证。

### B6-C-11 [P1] `OgLAsyncSliver` 头注释承诺「与 AsyncView 同语义（… 软错）」，实现不处理软错：`issue_page` 评论区刷新失败会静默丢提示
- **文件:行号**：`lib/surface/app/async.dart:460-465,511-552`（`OgLAsyncSliver.build`）；对照 `lib/surface/app/async.dart:276-305`（`AsyncView` 的 softError 分支）、`lib/surface/pages/issue_page.dart:819-823`
- **问题**：:460 头注释写「与 [AsyncView] 同语义（加载 / 空 / 错 / **软错**），但以 sliver 输出」；`AsyncView` 在 :293-305 确有 `softError` → `OgLAsyncSoftErrorBar` + 保留旧数据；而 `OgLAsyncSliver.build` 的四个分支为「有数据 → 直接 `SliverList.builder`」「空 → 空态」「错 → 错误面板」「加载 → 转圈」，**全文无 softError**（`rg softError` 在 sliver 段零命中），不渲染 `OgLAsyncSoftErrorBar`，也不提供 `onDismiss`。`issue_page.dart:819-823` 的评论区正是用 `OgLAsyncSliver` + `controller.load()` 刷新（`_editComment` / `_deleteComment` / `_postComment` 后均调 `_commentsC().load()`）：刷新失败时 `AsyncController` 保留旧数据并置 `_error`，sliver 走「有数据」分支，**用户看不到失败提示，评论看起来没变**。
- **后果**：原则 15「失败必须以用户可感知的方式留痕」、16「不吞异常」。这里异常没被吞（日志在 `async.dart:138-143` 有 `critical` 记录），但 UI 层的「失败可见」承诺在 sliver 形态下断链；而 `smoke_test.dart:87-121` 只测了 `AsyncView` 的软错保留内容，`OgLAsyncSliver` 的两个测试（`async_sliver_test.dart`）只测懒加载与空态，**软错零断言**（B6-C-01/02）。
- **原则**：15、16、54（注释承诺未在类型/实现上表达）、51
- **证据**：确证·静态。`rg -n 'softError' lib/surface/app/async.dart` 仅 :89-92（getter）/ :293（AsyncView 使用）/ :300-305；sliver 段（:460 起）无命中；`issue_page.dart:458,494,578` 三处 `_commentsC().load()`。是否真的显示「评论未变化」依赖运行期渲染，未跑 widget 测试，只确证「无软错分支 + 注释不符」。

### B6-C-12 [P1] `ActionLogPage._jobs` 控制器在 `dispose()` 中未释放，且 `_loadIssues` 一类「构造控制器后无 setState」造成首帧不同步（dispose 对称性 / 生命周期复核）
- **文件:行号**：`lib/surface/pages/action_log_page.dart:110-116,124-143`；对照 `lib/surface/pages/search_page.dart:216,289-290,945-947`、`lib/surface/app/paged_controller.dart:133-138`、`AGENTS.md` §3「cancel_subscriptions / close_sinks」
- **问题**：`ActionLogPage` 持有两个 `AsyncController`（`_logs` :85 / `_jobs` :86），`dispose()`（:110-116）只 `_logs?.dispose()`、`_query.dispose()`、`_debounce?.cancel()`，**漏掉 `_jobs?.dispose()`**。虽然 `_jobs` 当前因 B6-C-04 从未加载（不会有在途回写），但一旦按注释接线 `load()` 就会形成「dispose 后在途请求回来 `notifyListeners()`」的路径——这正是 `async.dart:56-61` 与 `async_test.dart:144-167` 花整段注释和测试守住的断言崩溃。`AsyncController.dispose()` 只置 `_disposed`，不取消 loader；`_disposed` 检查在 `load()` 入口与 `_notify()`，故漏 dispose 的直接后果是「已卸载控制器仍持有监听者」。
- **后果**：注释-实现一致性（:124-128 把 jobs 链路写成完整设计）+ 资源对称（原则 24「注册了就要注销，监听了就要取消」）双缺口；与 B6-C-04 是同一处未接线代码的两个面，合并记录为一条独立规范问题（B6-C-04 报功能链路，本条报生命周期）。
- **原则**：24、22、55
- **证据**：确证·静态。:110-116 全文；`rg -n '_jobs' action_log_page.dart` 全量 4 处无 dispose；`async.dart:106-112`（dispose 只置位）；`async_test.dart:144-167` 的守卫用途注释。注：`search_page.dart:216` 的 `unawaited(_loadIssues())` 中 `_issues` 构造是同步的（见 B6-C-10），其 `dispose()`（:220-226）**有** `_issues?.dispose()`，对称性合规，本条不指它。

### B6-C-13 [P2] 59 条原则复核：`avoid_print` 有 2 处 `// ignore` 破例、令牌/间距/取消订阅总体合规，但存在 3 处非刻度字面值漏网
- **文件:行号**：`analysis_options.yaml:38`；`lib/surface/pages/download_manager_page.dart:252,521`（范围外，仅作全库复核）；`lib/surface/pages/release_detail_page.dart:427`（`SizedBox(width: 72, …)`）；`lib/surface/app/desktop_window.dart:212`（`SizedBox(width: 46, height: 38,…)`）；`lib/surface/widgets/settings/settings_group.dart:34,395,524`（`EdgeInsetsDirectional.only(start: 16, end: 12)` / `EdgeInsets.only(left: …16, right: 16)`）；`lib/surface/pages/repo_page.dart:1487`（`TextStyle(fontSize: 12)`，非等宽上下文）
- **问题**：按任务点名的四项 59 条纪律逐项复核：
  - **避免 print**：`rg '\bprint\(' lib/surface` 仅 2 处，均在范围外的 `download_manager_page.dart`，且各有 `// ignore: avoid_print` 与说明注释（:251/:520「单条重试失败不能让整批中断；落日志由中枢层处理」/「打不开就走复制路径兜底」）。范围文件（app/ 全部、types/theme、六页、三 widget、test/surface 全部）**零 print**。但原则 15「失败必须留痕」下这 2 处用 `print` 而非 `OgLAppLog`/通知中心，`// ignore` 是 lint 级捷径；属范围外观察，不计入本批缺陷，仅记录。
  - **取消订阅 / dispose 对称**：逐个核对 `addListener/removeListener/addObserver/removeObserver`：`client_shell.dart:89/95`、`keyboard_guard.dart:41/42→49/50`、`error_surface.dart:428/431→437/438`、`desktop_window.dart:99→107`、`og_l_app_bar.dart:86-95`（`didChangeDependencies` 换控制器时先 remove 再 add，`dispose` 再 remove + `_debounce?.cancel()` + `_progress.dispose()`）、`animations.dart:234→222-227`（`Timer` 改用可取消的 `_delayTimer` 并有长注释解释 why）——**全部对称**，是本批最扎实的一环。例外仅 B6-C-12。
  - **ValueKey**：`AGENTS.md` §7「列表用 ValueKey」。范围文件中 `search_page.dart`（9 处）、`issue_page.dart:806,993`、`action_log_page.dart:514` 有；但 `action_run_page.dart` 的 `SliverList.builder` job 卡（:691-700）、`release_detail_page.dart` 的 `for (asset)` 附件卡（:482 起）、`search_page.dart:1200` 的结果 `ListTile` 均无 ValueKey，`rg 'ValueKey'` 在这两页零命中。属清单纪律的部分缺失，但 Flutter 的 `SliverList.builder`/`ListView` 在 index 稳定时可由框架复用，不必然产生错误状态；**不冒充确证缺陷**，只记观察，定 P2 且并入本条。
  - **设计令牌字面值**：上列 4 处非刻度/裸 fontSize 确实存在，且都不被 `ui_audit.py` 检出（B6-C-06 第 4 点正则漏检 + 整文件 ALLOW）。原则 34「视觉值一律取自设计令牌」被违反但门禁沉默。
- **后果**：三条硬纪律（print / 订阅 / dispose）在范围内执行良好，说明 59 条原则不是普遍失守；真正的问题是**门禁与实现之间的盲区**：4 处字面值漂移 + 2 处 `// ignore` 破例都不被任何脚本看见。定 P2（不把「可用 ValueKey 但没加」的风格偏好升级为缺陷）。
- **原则**：34、24、22、AGENTS.md §3/§7
- **证据**：确证·静态。上列行号原文 + `/tmp/diag7.py` 的 `SizedBox`/`EdgeInsetsDirectional` 合成用例；`rg -n 'addListener|removeListener|addObserver|removeObserver|Timer\(' lib/surface/app lib/surface/pages/{search,issue,repo,release_detail,action_log,action_run}_page.dart lib/surface/widgets/{log_body,log_search}.dart lib/surface/widgets/settings/settings_group.dart` 全量清单。

### B6-C-14 [P2] 批3新增代码的三处文档/注释失真：`license_meta_test.dart` 不存在、字体「避免重复下载」的落盘文件从未被读、仓库页尾部注释块重复两遍
- **文件:行号**：`lib/surface/app/project_info.dart:54-59`；`lib/surface/app/font_loader.dart:107-127,131-143`；`lib/surface/pages/repo_page.dart:4498-4509`
- **问题**：
  1. `project_info.dart:57` 写「许可标识、名称、地址三者必须同时改，**由新增测试锁死（见 `test/surface/license_meta_test.dart`）**」；`rg --files test | rg license` → **零结果**，该文件不存在。这是原则 57「文档引用的符号必须真实存在」的直接违反（B3-C-16 同类问题在 UI 域复现），且注释把「无守卫」写成了「有守卫」。
  2. `font_loader.dart:117` 注释「**落盘：下次启动免去重复下载**」，`ensureNotoSerifSc()` :118-120 确实把 `noto-serif-sc.otf` 写入 `ogl-fonts/`；但 `bytesOf()` :59-66 只读 `font.filePath` 或 `http` 来源，而 `ensureNotoSerifSc()` 构造的 `OgLCustomFont`（:111-115）**只有 `source` URL、没有 `filePath`**，且全文没有任何读取 `${font.id}.otf` 的代码（`rg '\.otf|readAsBytes|filePath' font_loader.dart` 只有写盘一处）。启动期 `surface_bridge.dart:546-553` 的 `_uiFontFamilyOf` 只是返回 family 名，不调 `ensureLoaded`；只有用户再次进入设置页点「应用」才会重新下载。落盘文件是**只写不读**的死数据。
  3. `repo_page.dart:4498-4509` 文件尾的「消息面板：Phase 5 后半已收敛…」注释块**逐字重复两遍**（两段 6 行完全相同），属原则 55「死代码零容忍 / 注释掉的代码与过时白名单都是假情报」的轻量实例。
  4. 附带的注释-实现精度问题：`font_loader.dart:131` 写「私有字体落盘目录（**应用支持目录下 `fonts/`**）」，实现 :136-140 用的是 `Directory.systemTemp/ogl-fonts`；:135 注释「复用 app_dirs 已有的支持目录解析」也与 `Directory.systemTemp` 不符。
- **后果**：三处都不影响数据可靠性，但都是「注释承诺了不存在的守卫 / 不存在的复用」——正是本批主题「注释质量 ≠ 契约质量」在批3新增代码上的具体落点；`license_meta_test.dart` 尤其会让许可 URL 改错时无人拦截（B3 曾把许可地址错指 AGPL 定为历史缺陷）。
- **原则**：57、55、54、47
- **证据**：确证·静态。`rg --files test | rg license` 零命中；`font_loader.dart` 全文（:58-66 / :107-127 / :131-143）与 `surface_bridge.dart:546-553`、`settings_page.dart:715-741` 的调用链；`repo_page.dart:4498-4509` 两遍原文比对。不冒充「启动一定重新下载字体」的运行期结论（依赖字体族注册状态时），只确证「落盘文件无读取路径」。
