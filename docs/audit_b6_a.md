# 第 6 批 · 视角 A：实现正确性审计（UI 层与状态管理）

> 审计对象：v12.0.0 LTS，lib/surface/。只审不改。
> 依据：docs/QUALITY_STANDARD.md（原则编号按条目）、AGENTS.md。
> 每条含：文件:行号、问题、用户可见后果、等级、原则、确证状态。

---

## P0

**B6-A-01** `lib/surface/pages/search_page.dart:633-650`（_buildRecommendedTab 分类切换）+ `:240`（_loadMoreRepos 守卫）
问题：分类切换时只清 `_repos/_repoPage/_repoDone`，**没有 `_repoLoading` 的世代作废**——若切换瞬间上一分类的 `_loadMoreRepos()` 在途（含其内部逐仓库串行 README/version 补充循环），旧循环会把旧分类的仓库 `addAll` 进已清空的 `_repos` 并继续 `_repoPage++`，与新一轮请求交错。
后果：推荐列表混入上一分类的仓库，且页码错乱（后续页重复/缺失）；滚动加载会持续追加错维度数据。
等级：P0（数据撕裂，可见且持续）
原则：22（过期回调必须丢弃）、27（并发假设写进注释——此处假设"切分类时无在途加载"未成立）
确证：已确证。代码证据：`onSelectionChanged` 内仅 `clear() + 置 1 + unawaited(_loadMoreRepos())`；`_loadMoreRepos` 仅检查 `_repoLoading || _repoDone`，新调用因 `_repoLoading==true` 直接 return，而旧调用的 `loader` 结果不受 `_repoCategory` 校验（第 252 行 `searchRepos(_kCategoryQueries[_repoCategory], …)` 发起时已捕获旧值，但**返回后无世代比对**）。对比：同项目 `AsyncController`/`PagedController` 均有 generation 防护，此处缺失。

**B6-A-02** `lib/surface/app/paged_controller.dart:180-186`（_load 成功路径）
问题：跨页拼合的快照记录 `page = _page`（已自增），但命中回放后 `_page` 恢复自快照、`items` 恢复全部条目——快照本身一致；**真正的问题是 loadMore 失败后快照把"半页成功"固化**：loadMore（`reset=false`）第 2 页成功 20/30 条 → `done=false`、快照 items=首页+20 条、page=3；之后 loadMore 再失败（error 置位），快照仍被 `items.isNotEmpty` 刷新为"已含第 2 页 20 条"的中间态。
后果：TabBarView 重建后"秒开"到半页数据，且 `_page=3` 意味着第 2 页剩余 10 条**永久缺失**（页码已推进）；用户看到列表少一段且无感知。
等级：P0（分页数据静默缺段）
原则：13（半成品状态必须留痕）、22（过期结果校验只按 generation，未按"页完整性"）
确证：已确证。证据：`_page++` 在 `done` 判定后无条件执行（第 184 行），快照写入条件仅 `items.isNotEmpty`（第 190-195 行），不区分"当前页是否满页/是否刚失败"。

## P1

**B6-A-03** `lib/surface/app/async.dart:147-152`（load() finally）
问题：`reset()` 在 `loader()` 在途时置 `_loading=false` 并立即返回，若随后立即 `load()`，新请求与旧请求**并发在飞**；旧请求 finally 虽因 `gen != _generation` 不清 `_loading`（正确），但旧请求**成功回写也仅靠 generation 拦截**——逻辑成立。遗留边界：reset 后旧请求**异常分支**（第 134-136 行）有同代次校验，OK；真正的缺口是 `loadIfNeeded()`（第 107-110 行）在 reset 后 `_everLoaded=false`、`_loading` 已被 reset 清 false——此时 loadIfNeeded 与**尚未结束的旧请求**并发，新 loader 与旧 loader 同时打同一端点，双份配额消耗 + 通知交错（新结果先回会被旧结果……否，旧结果被 generation 拦截）。剩余可见问题：**旧请求失败后旧 finally 仍会 `_notify()`**（第 152 行在世代校验之外无条件通知），此时 `_data` 是 null、新请求 loading——多触发一次无害 rebuild。降级为重复通知问题。
后果：轻微多余重建；双请求并发烧配额。
等级：P1
原则：22、26（幂等/防重）
确证：已确证（重复通知部分）；并发双打部分待议（需 runtime 验证 loader 端点语义）。

**B6-A-04** `lib/surface/pages/search_page.dart:289-296`（_loadIssues）
问题：每次 `_loadIssues()` 调用都 **new 一个新 AsyncController 覆盖 `_issues`，旧控制器未 reset 也未复用**；initState 只调一次，但若未来任何路径（如下拉刷新 `_issues!.load()`——RefreshIndicator 走 `controller.load()`，安全）重新进入则泄漏；当前确证的可见缺陷是：`_mineUrls/_starUrls` 在 loader 内闭包赋值（第 300-309 行），loader 与 UI 的 `_matchFilter` 读同一 State 字段，**loader 失败半途（mine 成功、starred 抛错）时 controller 进入错误态，但 `_mineUrls` 已被覆盖为新数据、`_starUrls` 仍为旧数据**，切到"Star"筛选展示的是上一轮数据配本轮 mine 的混合判定。
后果：筛选结果与列表数据版本不一致（“我的/Star”筛选错条目）。
等级：P1
原则：22、10（并发写可见而非覆盖）
确证：已确证。证据：第 301-309 行 `_mineUrls..clear()..addAll(mine…)` 在 `await searchIssues(starred…)` 之前执行；后者抛异常时前者的写入已生效。

**B6-A-05** `lib/surface/pages/profile_page.dart:328-333`（草稿计数 FutureBuilder）+ `:100-104`
问题：`ListenableBuilder(listenable: draftsChanged)` 内嵌 `FutureBuilder(future: api.draftCount())`——**FutureBuilder 的 future 在每次 notifyListeners 重建时重新创建**，且未保存/去重；draftsChanged 每次编辑保存触发，重建即再查一次磁盘；另外 future 无 await 守卫，State 卸载后回调写入已 dispose 的 snapshot（FutureBuilder 自身安全，但配额/IO 重复）。
后果：频繁磁盘 IO；快速连续事件时计数闪变（旧 future 后到覆盖新值——FutureBuilder 后创建者胜出，实际以最新为准，闪变为瞬时）。
等级：P1
原则：31（热路径不分配）、22
确证：已确证（future 每次重建重查）。闪变部分待议。

**B6-A-06** `lib/surface/app/client_shell.dart:152-172`（_check）
问题：`_check()` 无重入保护：`auth` listener 触发 + `ProfilePage.onAccountsChanged` 触发 + `LoginPage.onLoggedIn` 触发可能重叠执行；两次 `refreshState()` 并发期间，两次 `activeAccount()` 结果时序不定，后完成者写 `_accountId`——若一次读到 null（存储瞬态失败）后完成，会把已登录态打回登录门。
后果：极端时序下登录门闪回（已登录 → 登录页一闪）。
等级：P1
原则：26（写操作防重）、27
确证：逻辑确证；实际触发频率**待议**（需 runtime 验证 refreshState 是否可重入安全）。

**B6-A-07** `lib/surface/widgets/log_body.dart:62-70`（didUpdateWidget）
问题：`query` 变化触发 `_rebuild()`（全量 O(n) split+扫描，万行日志在主 isolate 同步执行），而日志还在流式追加（`text` 每 delta 变化）——每次 delta 都全量 rebuild + 全量重扫命中；且 `_jump` 的 `jumpToken` 变化即使 `_hits` 为空也排 postFrame（`_jump` 内部拦截，无害）。
后果：长日志流式输出期间每帧一次 O(n) 字符串切分与扫描，打字/滚动掉帧（大日志 + 查找激活时）。
等级：P1
原则：31（热路径不分配）、30（惰性构建）
确证：已确证。证据：didUpdateWidget 第 63-68 行 `oldWidget.text != widget.text` 即 `_rebuild()`；`_rebuild` 内 `widget.text.split('\n')` + 全文 `toLowerCase()` 双份全量拷贝。

**B6-A-08** `lib/surface/pages/action_log_page.dart:213-242`（查找状态）+ `log_body.dart`
问题：页面扫描把命中按 job 分桶传 `query`，但 `OgLLogBody` **不接收该 job 的命中列表**（仅收 `query` + `jumpToken`），跨 job 循环跳转时（页面注释明言"命中分布在多个 job 时循环跨 job"），展开中的 job 收到 `jumpToken++`，但若当前第 N 处不在本 job，`_jump()` 把 `jumpToken-1 = N` 当作**本 job 命中列表的索引**定位——页面 total 与 body 内 `_hits.length` 是不同集合，跳转会落在错误命中处或越界不跳（体验：上一处/下一处有时"不动"）。
后果：跨 job 跳转定位错位/失灵。
等级：P1
原则：22（无效回调丢弃）、28（键覆盖全部差异维度——jumpToken 语义跨两个不同命中集合混用）
确证：已确证。证据：log_body `_jump()` 第 137-153 行 `index = jumpToken - 1; index >= _hits.length → return`；页面 `_jumpTo` 以全局 total 取模。当前展开 job 的 `_hits` 只是全文命中子集，索引不对应。

## P2

**B6-A-09** `lib/surface/pages/notifications_page.dart:307`
问题：`Semantics.toggled` 绑定的是 `isRead(entry)`，而 onTap 语义是"展开/收起详情"（顺带标已读）——开关语义与实际动作不符（展开态与已读态是两个独立状态）。
后果：屏幕阅读器误导（"已读"却仍可展开）。
等级：P2
原则：35/38（语义如实）
确证：已确证。

**B6-A-10** `lib/surface/app/paged_controller.dart:212-230`（finally 重放）
问题：`_refreshQueued` 重放调用 `refresh()`，而 `refresh()` 再次 `if (loading)`——此时 finally 已置 `loading=false`，正常；但重放路径 `unawaited(refresh())` 使**排队的刷新结果 Future 被丢弃**（首次 refresh 返回的 Future 提前 complete），调用方 `await paged.refresh()`（如 dashboard `_refreshActive`）在数据真正刷新前就返回，随后 `_preloadRepoAvatars()` 读到的是旧 items。
后果：下拉刷新后头像预登记基于旧数据；刷新"看似完成实则未完"。
等级：P2
原则：22、42（如实完成）
确证：已确证（异步语义）；可见影响**待议**（头像预载幂等，实际损害有限）。

**B6-A-11** `lib/surface/pages/search_page.dart:421-427`（通知点击分流）
问题：`subjectUrl.split('/').last` 解析编号对 `/issues/123#issuecomment-456` 形态（URL 含锚点/查询）会得到 `123#issuecomment-456`，`int.tryParse ?? 0` → IssuePage(number: 0) → 打 #0 必 404；PR 分流进 IssuePage 用 issues API（对 PR 可用，此点正确）。
后果：个别通知点击打开 404 页。
等级：P2
原则：20（外部数据不可信，需夹紧/校验而非回落到非法值）
确证：已确证（解析路径）；GitHub 实际返回该形态的频率**待议**。

**B6-A-12** `lib/surface/pages/search_page.dart:1198`（SearchResultsPage 模式切换）
问题：切模式把 `_query=''` 后 `_run()`，但 `_input.text` 未清空——若输入与切模式后相同，`q == _query` 恒 false（_query 已清）会重新搜索，正确；真正问题是**旧 AsyncController 的在途结果**：`_run` 每次 new controller，`old?.dispose()` 靠后于 `setState`——旧控制器 dispose 后其 finally 的 `_notify()` 被 `_disposed` 拦住，正确。遗留：`_query=''` 后若防抖 Timer 已排定（`_scheduleSearch` 在 onChanged），切模式后 300ms 内 Timer 回调再 `_run()`，与切模式触发的那次**竞态**：两次都 new controller，后完成者覆盖——因两个 loader 都是同词同模式结果相同，无可见撕裂，但多一次请求。降级为冗余请求。
等级：P2
原则：26
确证：已确证（逻辑）；可见影响极小。

**B6-A-13** `lib/surface/pages/profile_page.dart:100-104`（loader 内写 `_activeId`）
问题：`_accountsC()` 的 loader 在异步回调里写 `State._activeId`（无 mounted/世代校验）；页面 dispose 后 loader 回来写 State 字段无害（State 不再 build），但**切换账号后 load() 的旧世代结果**（AsyncController 无 reset 调用，只有 load，同代）——切号流程是 `_refresh()` 重新 `load()`，`load()` 的并发抑制会丢弃第二次调用（第一次未返回时），**导致切号后列表不刷新**：`switchTo` → `_refresh` → `load()` 若恰有在途首次加载则静默 return，`_activeId` 仍是旧账号。
后果：切号后"我的"页高亮/切换按钮短暂显示旧账号。
等级：P2
原则：22、9
确证：逻辑确证；触发窗口小，**待议**。

**B6-A-14** `lib/surface/app/notifier.dart:62-73`（_show）
问题：SnackBar 无排队上限/合并：同一错误在循环场景（如批量操作逐项失败）会排队堆积多个相同 SnackBar，ScaffoldMessenger 逐个轮播；`floating` 样式 + 无 duration 定制，错误风暴时底部被占数秒。
后果：错误刷屏式轮播。
等级：P2
原则：29（所有资源有上限）、15（失败留痕——留痕本身正确，缺合并语义）
确证：已确证（无合并逻辑）；实际触发面**待议**。

**B6-A-15** `lib/surface/app/async.dart:96-99`（isFirstLoading）
问题：`isFirstLoading = _data == null && _error == null && !_empty`，但 `reset()` 后 `_empty=false`、`_loading=true`——AsyncView 走 `data==null → loading` 分支，一致；**但 `load()` 失败且此后 `dismissError()`**：`_error=null`、`_data=null`、`_loading=false` → 界面回到"无限转圈"且无重试按钮（error pane 条件 `failure != null && !isLoading` 不再成立，loading 分支的 spinner 是 `const` Center——显示永久加载）。
后果：用户点掉错误提示后页面卡死在转圈，只能下拉（若列表页有 RefreshIndicator；AsyncView 本体无刷新入口）。
等级：P2（需用户主动 dismiss）
原则：15（失败必须可感知）、17
确证：已确证。证据：第 95-98、192-201 行分支组合。

**B6-A-16** `lib/surface/app/overlays.dart:57-63`（ogLShowDialog）
问题：`ogLShowDialog` 未统一 `barrierLabel`/动效，仅透传——文档宣称"避免各页面不同的进出节奏"，但 `showDialog` 本身不受档位控制（无 AnimationStyle 注入，对话框转场未按动效档位定速），与 `ogLShowSheet` 的实现深度不一致；且 `barrierDismissible: true` 默认可点空白关闭**危险确认对话框**（二次确认误触空白即取消——安全侧 OK，但"删除确认"被意外 dismiss 后用户以为确认过）。
后果：对话框转场不随档位；确认对话框语义含糊。
等级：P2
原则：33（动效统一）、12（显式确认）
确证：转场部分已确证（无 AnimationStyle 通道，showDialog 无此参数属框架限制——注释未说明此差异，属文档与实现不符）；语义部分待议。

**B6-A-17** `lib/surface/pages/client_shell.dart:228-231`（_pageFor，ProfilePage/SettingsPage 无 ValueKey）
问题：Dashboard/Discover 用 `ValueKey('dash-$accountId')` 在切号时强制重建，而 `ProfilePage` / `SettingsPage` **无 key**——切号后 ProfilePage 的 `_accounts` AsyncController 是旧实例，靠 `_refresh()` 重新 load 补救（见 B6-A-13 的并发抑制窗口）；IndexedStack 懒挂载下若 ProfilePage 未访问过则无影响，已访问则依赖 `_refresh` 链路。
后果：切号后 Profile 列表闪旧数据的窗口。
等级：P2
原则：28（键覆盖差异维度）
确证：已确证（key 缺失）；实际后果与 B6-A-13 合并观察，待议。

**B6-A-18** `lib/surface/widgets/readme_view.dart:560-580`（_cachePut）
问题：`_cachePut`/`_cache` 为 static（进程级），多仓库并发加载图片时 `_cacheBytes` 累减逻辑依赖 `_cacheOrder[key]` 与 `_cache[key]` 同步——`_cachePut` 对已存在 key 先减旧字节再重放，一致；但 `_load()`（第 516-530 行）无去重：同名 path 的两个 widget 同时 build 会**并发调用 loader 两次**（缓存尚未写入），重复 IO/配额。
后果：README 中重复图片路径或列表滚动重建时同一图并发拉两次。
等级：P2
原则：26（防重）
确证：已确证（无 in-flight 去重表）。

**B6-A-19** `lib/surface/pages/issue_page.dart:237-240`（_editIssue controller 生命周期）
问题：`titleController/bodyController` 在 `ogLShowDialog` 之后读取 `.text` 再 dispose——**读取发生在 await 之后、dispose 之前**，正确；但 `saved != true` 时 controller 文本被读了一次（`final String tagText = tag.text.trim()` 在 dispose 前无条件执行，release_detail_page 同构），无害。真正问题：`_EditIssueDialog.busyOf()` 在 build 中读外部 State 的 `_busy`，但对话框是 `StatelessWidget`，`_busy` 变化**不会触发对话框重建**（保存按钮禁用态不刷新）——用户打开编辑对话框后另一写操作（不可能并发，_busy 已挡入口）——实际不可达。
等级：P2（死路径，属防御代码误导）
原则：55（死代码零容忍的邻近问题）
确证：逻辑确证为不可达路径，无用户可见后果。

**B6-A-20** `lib/surface/app/og_l_app.dart:96`（builder 内 `MediaQuery.of(context)`）
问题：AGENTS.md 门禁 2 规定 surface 层宽依赖 `MediaQuery.of` 须用 `sizeOf` 等；此处 builder 层需要完整 query（copyWith），属**合法例外**但未见 perf_audit 白名单登记说明（builder 拿全 query 是必要形态）。
等级：P2（合规性疑问，非缺陷）
原则：3（例外必须显式登记）
确证：待议——需查 perf_audit.py 是否豁免该文件/该形态。

---

## 覆盖文件清单

| 文件 | 完整读 | 结论 |
|---|---|---|
| lib/surface/app/async.dart | ✅ 553/553 | B6-A-03、15 |
| lib/surface/app/paged_controller.dart | ✅ 233/233 | B6-A-02、10 |
| lib/surface/app/notifier.dart | ✅ 75/75 | B6-A-14 |
| lib/surface/app/overlays.dart | ✅ 108/108 | B6-A-16 |
| lib/surface/app/client_shell.dart | ✅ 491/491 | B6-A-06、17 |
| lib/surface/app/og_l_app.dart | ✅ 222/222 | B6-A-20 |
| lib/surface/types.dart | ✅ 44/44 | 无发现（门面纪律良好） |
| pages/dashboard_page.dart | ✅ 596/596 | _RepoPaged 与 PagedController 同构（generation 齐备，无独立发现） |
| pages/profile_page.dart | ✅ 371/371 | B6-A-05、13 |
| pages/issue_page.dart | ✅ 1087/1087 | B6-A-19 |
| pages/pull_page.dart | ✅ 213/213 | 无发现（复用 OgLAsyncSliver，无本地状态竞态） |
| pages/release_detail_page.dart | ✅ 557/557 | mounted 守卫齐备，无发现 |
| pages/search_page.dart | ✅ 1255/1255 | B6-A-01、04、11、12 |
| pages/notifications_page.dart | ✅ 430/430 | B6-A-09（分类筛选/展开状态管理正确：Set 去重 + markRead 联动） |
| widgets/log_body.dart | ✅ 217/217 | B6-A-07、08（body 侧） |
| widgets/log_search.dart | ✅ 93/93 | 无发现（纯展示，状态由页面持有，符合"一件事一个文件"） |
| pages/action_log_page.dart（log_search 消费端，配合阅读） | 部分（:200-279、:505-560） | B6-A-08（页面侧） |

## 整体评价

**骨架扎实，边缘处有真实竞态。** AsyncController/PagedController 的世代计数、dispose 保护、软错误保留旧数据、空结果不进快照等设计均为同类问题的正解，且注释如实记录假设（符合原则 27、58）。问题集中在三处：

1. **"新 UI 没接进老防线"**（B6-A-01）：发现页推荐 tab 的分类切换是四线新增代码，绕过了项目已成体系的 generation 防护——AsyncController/PagedController 都有，手写的 `_loadMoreRepos` 没有。这是本批最应修的一条（P0）。
2. **快照语义的边界**（B6-A-02）：PagedController"空结果不进快照"修对了一半，"半页结果固化 + 页码推进"是另一半。
3. **跨组件状态契约模糊**（B6-A-08）：日志查找的命中集合在页面（全 job）与正文（单 job）两层各自维护，jumpToken 在两层之间语义不对应。

Notifier/Overlay/types/notifications_page 的状态管理干净、mounted 守卫齐备（通知点击分流的 `_openFeedItem` 各分支均判 mounted，符合重点要求）。待议项共 7 条，需运行时实测确认（并发双打、FutureBuilder 闪变、refreshState 重入、SnackBar 风暴、URL 锚点形态、Profile 切号窗口、perf_audit 豁免）。
