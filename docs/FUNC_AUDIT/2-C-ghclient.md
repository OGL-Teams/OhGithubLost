# 功能审计报告 · 批 2-C · gh_client 请求编排

> 更新时间：2026-11-22 22:53:15 (Asia/Shanghai) · 版本：v15.0.0
> 范围：`lib/domain/gh/gh_client.dart`（845 行，全文）+ `lib/domain/gh/gh_api.dart`（2308 行，调用编排相关段）+ 交叉核对 `gh_read_cache.dart`、`kernel/diagnostics.dart`、`base/net/net_transport.dart` / `io_net_transport.dart`。只读审计，未改任何代码。

## 已检查清单
- `gh_client.dart`：`GhRateLimit`（fromHeaders/isExhausted/untilReset/toJson/toString）、`GhAuthException` / `GhRateLimitException` / `GhNotFoundException`、`GhWriteConflict` / `GhWriteResult`、`GhRequest`（toUrl/headers 合并/cacheBypass）、`GhResponse`（_decode/jsonObject/jsonList/jsonAsList）、`_Semaphore`（acquire/release/转交语义/inUse）、`GhClient` 构造/attachReadCache/invalidateReadCache/attachDiagnostics、`ttlForPath`（全部分支）、`resourceOfPath`、`isResourceExhausted`、`send`（缓存命中/限流避让/信号量/头注入/日志/回填/写失效/错误出口）、`getObject`/`getList`/`paginate`、`_throwIfFailed`（401/403/429/404/409/422/default）、`_retryAfterOf`/`_currentShaOf`/`_snippet`。
- `gh_api.dart` 编排面：currentUser/rateLimit/myRepos/starredRepos/userRepos/orgRepos/repo/createRepo/updateRepo/deleteRepo/fork/transferRepo/setStarred/isRepoStarred/branches/tags/createTag/deleteTag/createBranch/_resolveBranchSha/renameBranch/deleteBranch/tree/content/_contentNetwork/listDirectory/_listDirectoryNetwork/blobText/putContent/putContentLocked/deleteContentLocked/deleteContent/branchHeadSha/commitFiles/commits/compare/releases/createRelease/updateRelease/searchRepos/searchIssues/notifications/readmeExcerpt/latestVersionOf/searchCode/pagesInfo/enablePages/disablePages/readCname/writeCname/issues/createIssue/updateIssue/issueComments/createIssueComment/updateIssueComment/deleteIssueComment/lockIssue/unlockIssue/updateIssueLabels/updateIssueAssignees/pulls/pullFiles/gists/gist/createGist/updateGist/deleteGist/rawText/workflowRuns/workflows/rawFileText/dispatchWorkflow/workflowRun/workflowRunJobs/workflowRunLogsUrl/workflowRunArtifacts/artifactDownloadUrl/rerunWorkflowRun/cancelWorkflowRun/labels/readme、CacheRemote（read/write/delete）、_defaultBranchOf/_headShaOf/_treeShaOfCommit、drafts 系列、_isAbsentStatus/_isEmptyRepositoryMessage/_ghPath。
- 交叉核对（证据链）：`gh_read_cache.dart`（get/put/clear/纪元/账号隔离）、`kernel/diagnostics.dart`（log 的 sink try/catch）、`base/net/net_transport.dart`（429/Retry-After 重试、超时）、`io_net_transport.dart`（响应头小写化、敏感头日志脱敏）。

全仓 `rg` 证据核对：本报告所有 file:line 均可复现。

---

## P0（数据丢失 / 崩溃 / 安全）

### P0-1 日志脱敏铁律：查询串整行落盘，令牌类 query 参数存在外泄面
- 症状：`gh_client.dart:615-620` 把请求行连同完整 query 写入落盘日志（`OgLLogFile` 落地到 `sdcard/logging`，见 `lib/kernel/log/og_l_log_file.dart` 头注释）；`gh_api.dart:1938-1943` `rawText(String url)` 允许把**任意完整 URL**当作 `path` 传入（`GhRequest.toUrl`，`gh_client.dart:273-281`：`path.startsWith('http')` 时原样作为请求 URL）。Gist raw_url 与"原始文件"场景中，若调用方拼出带 `token`/`access_token` query 的 URL，该 URL 将原文进入落盘日志。
- 根因：`send()` 对 query/URL 一律不打码；`rawText` 是全开 URL 注入口；令牌本体虽在 `Authorization` 头（`io_net_transport.dart:385` 已对 sensitive 头脱敏），但 URL/query 这条通道没有同等防线。
- 修复指令：在 `gh_client.dart` 日志拼接处增加 `Uri` query 键名黑名单（token、access_token、key、secret、client_secret、code）打码；`rawText` 增加 URL host 白名单校验（api.github.com / raw.githubusercontent.com / gist.githubusercontent.com），非法 host 直接拒绝。二者均在 `send()`/`rawText` 内实现，不动调用方。

### P0-2 只读缓存键不含 Accept 头：JSON/raw 双通道互相污染
- 症状：`ttlForPath` 把 `/repos/{o}/{r}/readme` 列入 60s 白名单（`gh_client.dart:507`）。`gh_api.dart:2113-2123` `readme()`（JSON，带 base64 content）与 `gh_api.dart:1481-1490` `readmeExcerpt()`（Accept: raw，`cacheBypass: true`）共用同一路径。`readmeExcerpt` 靠 bypass 自身避免读到 JSON；但**反向**仍成立：60s 内先请求 raw 通道再请求 JSON 通道不受影响，可先请求 JSON 后 bypass 也不受影响——但只要未来任何调用方对 `/readme` **不带 bypass** 且要求 raw（或任何带非默认 Accept 的 GET 命中同一缓存键），缓存返回的就是错误编码的 body。`GhReadCache._key`（`gh_read_cache.dart:63-69`）只混入 `account/path/query`，**不含 headers**。
- 症状根因合一：缓存键对媒体类型不敏感；目前靠调用方纪律（每处手写 `cacheBypass: true`）兜底，新增调用点漏写 bypass 即产生跨端点数据污染（JSON 当正文渲染 / raw 当 JSON 解析失败）。同键风险同样适用于 `/search/code`（text-match Accept，`gh_api.dart:1559-1575`）——幸 search 不在 TTL 白名单，未爆发。
- 修复指令：`GhReadCache._key` 增加 `accept` 头维度（或 `GhClient.send` 在回填/读取缓存时把非默认 accept 作为键的一部分传入）；或更保守：`ttlForPath` 删除 `hasSegment('readme')` 分支（`gh_client.dart:507`），readme 一律不缓存。二选一即可消除污染面。

---

## P1（功能失效 / 不一致）

### P1-1 缓存命中路径把「负数 remaining」压回 — 误判耗尽会自锁到 reset
- 症状：`gh_client.dart:587-597`：命中耗尽判断 `known.isExhausted && known.untilReset > Duration.zero`，其中 `isExhausted => remaining <= 0`（`gh_client.dart:48`）。GitHub 在部分代理/镜像响应里 `x-ratelimit-remaining` 可能缺失或为 `-1`（fromHeaders 允许负值入库）；一旦某次响应携带 `remaining: 0` 但 `reset` 是坏值/过去时间之外的值，`_rateLimits[resource]` 存进耗尽快照后，**后续所有该资源请求在 reset 前全部本地拒绝**，即使真实额度早已恢复（例如 GitHub 的 `/rate_limit` 端点本身不计额度，但它的响应也会更新 `_rateLimits`，见 `gh_api.dart:63-79` + `gh_client.dart:636-640`）。`untilReset` 只挡 reset 已过的情况，不挡「快照本身错误」。
- 根因：额度快照无条件信任最后一条响应头；没有「恢复采样」或对可疑值（负数、reset 时间远大于上限窗口）的防御；也没有任何刷新出口能覆盖坏快照。
- 修复指令：`fromHeaders`（`gh_client.dart:60-77`）对 `remaining < 0` 返回 null（视为缺头）；`send()` 在 `_rateLimits[resource]` 已耗尽但请求 path 含 `/rate_limit` 时强制放行（额度查询必须能穿透自锁）；可选：对 `resetAt` 超过 1 小时窗口的快照视为无效。

### P1-2 `_lastRateLimit` 单槽与 `_rateLimits` 双口径：仪表盘展示可能显示 search 的余量冒充 core
- 症状：`gh_client.dart:633` `_lastRateLimit = rateLimit`（不分资源）；`gh_client.dart:541-544` `lastRateLimit` 注释「供仪表盘展示」。一次 `/search/repositories` 响应后，仪表盘显示的就是 search 余量（search limit=10），用户看到的与 core 真实额度（5000）完全不符。
- 根因：两个存储没有声明口径关系，展示侧拿到的是「最后一次响应的资源」。
- 修复指令：`lastRateLimit` 改为 `_rateLimits['core'] ?? _lastRateLimit`（或暴露 `lastRateLimitFor(resource)`，把展示侧改指 core）。文件：`gh_client.dart:541-544`。

### P1-3 信号量「许可转交」在等待者被弃（never-resumed / 异常弃单）时永久泄漏并发额度
- 症状：`_Semaphore.acquire`（`gh_client.dart:425-433`）在入队等待后只由 `release()` complete；若等待者所在调用链被外层取消/丢弃（Dart 无强制取消，但 zone/超时包装、上层 `Future.any` 竞速都会造成 completer 永不消费），`release()` 仍会把许可转交给一个**永远不会继续执行的 completer**（`gh_client.dart:435-442`），`_used` 不减 —— 并发上限逐次衰减，最终整库请求永久卡死（0 可用许可、队列只增不减）。
- 根因：转交语义假定每个等待者最终都会恢复；没有 completer 被弃（`completer.isCompleted` 检查 / 等待者超时）的兜底。
- 修复指令：`release()` 转交前 `while (_waiters.isNotEmpty && _waiters.first.isCompleted) { _waiters.removeAt(0); _used--; }` 清理已弃等待者；并给等待者加超时兜底（如 60s 未被转交则自减 `_used` 并移出队列）。文件：`gh_client.dart:421-445`。

### P1-4 非 GET（写操作）不经过缓存 TTL 判定，但回填分支漏判「写成功时 cacheTtl 为 null」——写后失效正确，而「写失败」不清缓存，409/422 冲突窗口内列表陈旧
- 症状：`gh_client.dart:664-669`：仅 `method != get && isSuccess` 才 `_readCache?.clear()`。写操作失败（409/422 冲突、429 限流后重试前的中间态）不清缓存，目录/列表缓存（60s TTL）继续返回**写前旧视图**；冲突对话框里的远端 sha 与缓存列表 sha 可能不一致，用户在列表上看到旧文件名/旧文件而实际已被并发写改掉。
- 根因：失效时机绑死在「成功」，未考虑「失败但服务端状态已变」的写语义（GitHub 422 冲突意味着远端已是新状态，缓存更陈旧了）。
- 修复指令：`gh_client.dart:664-669` 条件放宽为「method != get 且状态码 != 5xx 且 != 429」即 clear（409/422/403 说明远端状态参与了判定）；或更简单：所有非 GET 无论成败（除 429/5xx 可重试态）都 clear。

### P1-5 `paginate` 缓存命中回填 Link 头依赖缓存写入时保存了 link；但缓存回填的 `page.next` 是**绝对 URL**，而 `paginate` 续页用「本地拼 query 的 page++」，Link 信息被丢弃 —— `rel="next"` 指示的页号与本地递增可能分叉
- 症状：`paginate`（`gh_client.dart:724-752`）完全忽略 `response.page.next` 指向的 URL（包括其可能携带的 cursor/过滤参数），只做 `page++`（`gh_client.dart:748-750`）。GitHub 对 `/repos/{o}/{r}/commits` 等端点的 next URL 含 `sha`/`since` 等固化参数，本地 page++ 语义上等价，但对未来加入的 cursor 型端点（check-runs 等）会直接翻页错位；同时缓存命中路径返回的 Link 头（`gh_client.dart:573-582`）在 paginate 中**从未被消费**，缓存回填 Link 的价值只剩外部调用方 `response.page` 读取。
- 根因：paginate 未按 Link 续页，靠 page++ 近似；缓存回填 Link 是死代码路径（对 paginate 无效）。
- 修复指令：`paginate` 改为优先解析 `response.page.next`：若是同 host 同 path 的绝对 URL，提取其 query 作为下一页参数发送；否则维持 page++ 并留 WARN 痕。文件：`gh_client.dart:724-752`。

### P1-6 超时与取消不统一：`send` 固定 30s 超时（`gh_client.dart:623`），写操作（如 commitFiles 四连请求）整体可远超 UI 预期且无请求级取消（generation）机制
- 症状：全仓 `rg "generation"` 仅命中 4 个 surface 文件（dashboard_page / paged_controller / client_shell / async.dart），`lib/domain/gh/` 内**零处** generation/cancelToken 与 `GhClient.send` 关联。`commitFiles`（`gh_api.dart:1352-1436`）blob→tree→commit→ref 四步请求串行无取消点；用户离开页面后写流程继续烧额度并可能完成半程提交（ref 未 patch 前，孤儿 blob/tree 已入远端对象库）。`RepoFileService` 有自己的 cancel token（`repo_file_service.dart:267-286`），但它不穿透到 `GhClient.send`。
- 根因：`GhRequest` 没有 generation/cancellationToken 字段；`send` 与传输层都没有"请求开始后可弃"的协议。
- 修复指令：`GhRequest` 增加 `Future<bool> Function()? isCancelled`（或 generation int + client 侧 register）；`send` 在信号量获取前与 `_net.send` 前各查一次，取消则抛 `GhCancelledException`（新增类型）；`commitFiles` 每步 await 后查一次。文件：`gh_client.dart:236-258`（GhRequest 定义）、`gh_api.dart:1352-1436`。

### P1-7 403 权限判断把「资源级 403（私有仓库不可见，GitHub 也回 403 with resource not accessible）」误译为「缺少 repo 作用域」
- 症状：`gh_client.dart:806-810`：非 abuse、无 Retry-After 的 403 一律抛「权限不足（缺少 repo 等作用域）」。GitHub 对 fine-grained PAT 未授权某仓库、或 app 权限缺失也回 403，body 常含 "Resource not accessible by personal access token"/"Not Found"语义。用户据此去检查 token scope 永远查不出问题。
- 根因：错误体 message 未参与分类（只匹配了 abuse 一类）。
- 修复指令：`gh_client.dart:782-810` 在抛 GhAuthException 前对 `body403` 增加 "not accessible" / "resource not accessible" 匹配，提示「令牌未获此资源授权（fine-grained PAT 或 App 权限）」；保留 scope 提示作 fallback。

---

## P2（打磨）

### P2-1 诊断回调不抛异常由内核层兜底，但 `_diagnostics?.debug/warn` 的 `data` map 构造本身可能在调用点抛（如 `cacheTtl.inSeconds` 不会、但未来插值可能）——主流程防护依赖内层实现
- 事实核对：`kernel/diagnostics.dart:183-197` 对每个 sink `try/catch`，sink 抛错只记 `_sinkErrors`，**不会打断主流程**——该维度当前无缺陷。仅提示：`send()` 内诊断调用点（`gh_client.dart:566-572, 646-652`）若未来在 data 参数里写复杂表达式，需保持"纯构造"，内核兜底不覆盖参数求值阶段。无代码改动要求，记录为约束。

### P2-2 `GhResponse.toString` 只含状态码与字节数（`gh_client.dart:417`），错误排查时常需要 URL —— `send` 失败日志（`gh_client.dart:654-664`）已补，双口径可接受
- 无缺陷；建议 `GhResponse` 增加 `requestLabel` 字段统一排查口径。可选。

### P2-3 `ttlForPath` 的 `hasSegment('commits')` 会把 `/repos/{o}/{r}/commits/{sha}` 详情也放入 60s TTL（`gh_client.dart:501-509`），提交详情在 60s 内不反映 force-push 修正——语义上是缓存放大而非缺陷
- 建议：把 commits 白名单收窄为 `hasTail('commits')`（仅列表）。文件：`gh_client.dart:501-509`。

### P2-4 `_snippet`（`gh_client.dart:831-833`）按 UTF-16 code unit 截断 160，CJK 错误消息可能被拦腰截断产生乱码字符
- 修复：改用 runes 截断或截断后过滤孤立代理项。文件：`gh_client.dart:831-833`。

### P2-5 `isRepoStarred`（`gh_api.dart:271-284`）对 404 吞为 false，404 也可能来自「仓库不可见」——注释已自曝边界，调用方约束靠纪律
- 建议加防御：仅在仓库详情已成功获取后调用；无代码强改，记录约束。

---

## 本席结论
`gh_client.dart` 的主干设计（按资源限流避让、信号量转交语义、401 全局唯一出口、206 拒收缓存、写后整体失效、Link 回填）方向正确，此前修复（B5-A-09、B3-A-02）有实证痕迹。本席确认问题 **11 条：P0 × 2、P1 × 6（含 1 条待裁断的框架事实：Dart 无 completer 消费检查的替代写法，P1-3 修复指令中超时兜底属可本地实现方案）、P2 × 5（其中 P2-1/P2-2/P2-5 为无缺陷记录项）**。两条 P0 均为「令牌/凭据相关外泄面 + 缓存键不含 Accept 的跨端点污染」，修复成本低（各一处函数），建议优先处理 P0-1（日志脱敏）与 P0-2（缓存键加头维度）。
