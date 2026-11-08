# 审计 B3-B · GitHub API 层：安全与数据（v12.0.0 LTS）

> 视角：安全与数据完整性。只审不改，未写任何 lib/ 文件。
> 裁决依据：docs/QUALITY_STANDARD.md（原则 10/11/12/39/40/41/42/44/52）、AGENTS.md（令牌安全 / 重定向守卫 / D1–D7）、docs/CONSISTENCY.md、docs/NETWORK.md。
> 范围内全部文件已 file_read 完整阅读（非 rg 抽样）。涉及端点实测的条目标「待议」。

---

## 确证发现

### B3-B-01 · P1 · updateIssueLabels / updateIssueAssignees 全量替换可静默删除他人设置（确证）
- 位置：`lib/domain/gh/gh_api.dart:1717–1745`（PATCH `/repos/{o}/{r}/issues/{n}` body `{labels}` / `{assignees}`）；调用点 `lib/surface/pages/issue_page.dart:288 / 324`。
- 问题：PATCH 语义是**全量替换**（文档自认「传空列表 = 清空全部」），而 UI 以页面加载时快照 `_labels` / `_assignees` 为基线计算目标集合；Issue 端点无任何乐观锁（无 If-Match / expectedSha），页面打开后他人新增的标签或指派人在保存时被无提示删除。
- 用户可见后果：协作场景下他人的标签/指派人被悄悄抹掉，无任何冲突提示——数据丢失且不可感知（违反原则 8/10：并发写没有被看见就被覆盖）。
- 证据：`gh_api.dart` 注释「全量替换 Issue 标签（PATCH 语义：传什么就是什么，删除项直接消失）」；`issue_page.dart` 直接 `updateIssueLabels(labels: target)`，target 来自 `Set.from(_labels)`（页面加载时快照），中间无重读当前远端状态。
- 建议（不改代码，仅记录）：写前重读 issue 当前 labels/assignees 合并，或提交前 diff 提示。

### B3-B-02 · P1 · GhApi.rawText 对任意 URL 第一跳携带 Authorization，且不经令牌出设备警告（确证[代码]/待议[可达性]）
- 位置：`lib/domain/gh/gh_api.dart:1794–1799`（`rawText(String url)` → `GhRequest(path: url)`）；`gh_client.dart` send() 对 `path.startsWith('http')` 的请求照常注入 `authorization: Bearer …`。
- 问题：rawText 接受任意完整 URL 并把当前账号令牌发给该 URL 的第一跳主机；令牌出设备警告（`token_exit_warning.dart`）只挂在下载链路，rawText / getObject 等读路径无任何主机白名单校验。传输层守卫只保证**跨主机重定向不外泄**，第一跳本身不受保护。
- 用户可见后果：任何未来调用点传入非 GitHub URL（或当前 gist raw_url 被指向第三方域）即令牌外泄给第三方；凭证风险等级 P1。
- 现状：唯一调用点 `gist_detail_page.dart:142` 用的是 GitHub API 返回的 `raw_url`（当前为 `gist.githubusercontent.com`），故实际可达性「待议」；但域层 API 无防线是结构性缺口（原则 40「令牌只在必要的跳使用」没有在 API 层强制）。
- 建议：GhClient 对非 `*.github.com` / `*.githubusercontent.com` 的第一跳同样要求显式确认或直接拒绝。

### B3-B-03 · P2 · 读路径 _isAbsentStatus 把 409/422 折叠为「不存在」（确证，语义边界有注释但仍有误判面）
- 位置：`gh_api.dart:2180–2184`（`_isAbsentStatus = 404||409||422`），用于 `_contentNetwork`（返回 null）与 `commits`（返回空列表）。
- 问题：写场景已正确区分（注释明确「写场景不走这条」），但读场景 422（参数/校验错误，如非法 ref 名）也被折成「没有」：用户输错分支名看到的是空目录/空提交列表而非报错。`_listDirectoryNetwork` 已修复此问题（只认"repository is empty"原文），`_contentNetwork` / `commits` 未同步。
- 用户可见后果：特定 422 场景下「请求被拒」被显示为「没有内容」，违反原则 52（空、无、未启用是三种不同的没有）——不一致但影响面小（P2）。

### B3-B-04 · P2 · RepoFileService._probePath 同样把 409/422 折成 missing（确证，有服务端乐观锁兜底）
- 位置：`repo_file_service.dart:1743–1756`。
- 问题：probe 返回 409/422 时按「目标不存在」处理；随后 create 会发无 sha 的 PUT。GitHub 服务端「无 sha 即拒绝覆盖已有路径」的乐观锁兜住了误覆盖（最坏 422 而非覆盖），故降 P2；但 probe 阶段的 422（如 ref 非法）会表现为「目标不存在 → 尝试创建 → 服务端报错」的错误链，用户看到错误码而非真实原因。
- 不算 409 误折成「不存在而发无基线 PUT」的 P0 复发：PUT 路径始终走服务端 sha 乐观锁，且有 `test/domain/gh_submit_e2e_test.dart` 守卫。

### B3-B-05 · P2 · transferRepo / deleteRepo 的 202 / 二次确认与错误文案（确证代码事实，守卫存在）
- 位置：`gh_api.dart:237–243`（transferRepo，`.then((_) {})` 吞掉 202 响应体）；`repo_page.dart:3906–3960`（转移：输入目标名 + 二次确认对话框 ✅）；`repo_page.dart:4143–4180`（删除：二次确认 ✅）。
- 结论：危险确认守卫在 UI 层**存在且生效**（原则 12 满足）；API 层 202 语义按「已接受、仓库换址」处理，UI 转移成功后 pop 刷新，符合注释约定。
- 发现两个小问题：① `_deleteRepo` 失败分支文案复用了 `_t('branchDeleteFailed')`（删除仓库失败显示"删除分支失败"，误导，违反原则 38）；② transferRepo 返回 void，202 与 200 无法区分，但 GitHub transfer 仅回 202，当前无实际影响。

### B3-B-06 · P2 · dispatchWorkflow 无二次确认（确证）
- 位置：`gh_api.dart:1948–1963`；`workflow_dispatch_page.dart:311–345`（`_submit` 校验输入后直接 POST，无确认对话框）。
- 问题：workflow_dispatch 是写端点，会立即消耗 Actions 分钟数并执行仓库内工作流（可能触发部署、通知第三方）。同页的 deleteBranch / lockIssue 都有确认弹窗，此处没有；原则 12「危险操作必须显式确认」的边界判断存疑（按 AGENTS.md「四线新增写端点的权限判定」标准，此端点依赖 canWrite 之外缺一道确认）。
- 用户可见后果：误触即触发 CI 运行（消耗额度 / 副作用）。P2。

### B3-B-07 · P2 · 重定向守卫：IPv6 长形式回环未覆盖 + 死代码分支（确证）
- 位置：`io_net_transport.dart:113–152`（`_ogLIsSafeRedirectTarget`）、`:370–382`（`_carriesSensitiveHeader` 的 if/else 两分支返回值相同）。
- 问题：① IPv6 只拦 `::1` / `::` / `fe80*` / `fc*` / `fd*` 前缀，长形式回环 `0:0:0:0:0:0:0:1` 与 `::ffff:127.0.0.1` 映射地址不在列（IPv4 正则只匹配点分十进制）；需 DNS 把 Location 解析到该地址才可利用，标待议利用性，代码缺口确证。② `_sendWithGuardedRedirect` 中 `if (_carriesSensitiveHeader(...)) { return response; } return response;` 两分支等价——防御注释与代码不符，属原则 55 的死代码形态（应合并为一句并更新注释）。
- 正面确证（重点确证点通过）：Authorization 只在第一跳；跨主机 3xx 一律不跟随、凭证不重发（`io_net_transport.dart:344–368`）；https→http 降级、回环/私网/169.254.169.254 字面量全拒；302/303 仅 POST 降 GET 且剔除 body 绑定头（B1-A-30）。**四线新增写端点的令牌不出设备语义成立。**

### B3-B-08 · P2 · 只读缓存对 200 但截断的响应体不设完整性校验（确证机制，触发条件待议）
- 位置：`gh_client.dart:637–649`（`statusCode != 206 && isSuccess` 即 `put`）；`gh_read_cache.dart:120–140`（put 原样存 body）。
- 结论：206 拒收已落地（B1-C-08 修复有效），D1 读路径（`CacheRemote.read`）对非 JSON 体抛异常不折 null（B2-A-05 有效）。剩余缺口：中间代理对 GET 回 200 但 body 被截断时，残缺 JSON 仍会写入 GhReadCache 并在 TTL 窗口内污染分页/列表（jsonObject → null → 上层空列表）。底座 RepositoryCache 有完整性校验，GhReadCache 没有。触发需中间人/代理异常，待议；机制缺口确证。P2。
- 附带确证（通过）：缓存键含 accountId + epoch（`gh_read_cache.dart:60–68`），账号隔离成立；写请求后整体失效（`gh_client.dart:651–654`）。

### B3-B-09 · P2 · 409/422 未声明 conflictsAsRemoteConflict 时被折成 GhAuthException（确证）
- 位置：`gh_client.dart:771–777`。
- 问题：类型化异常 `GhAuthException`（语义=认证/权限）被复用于携带 409/422 的「请求被拒绝」，调用方若按异常类型分支处理（如 auth → 登录门）会误判。当前主要写路径（putContent/deleteContent/refs PATCH）都设了 `conflictsAsRemoteConflict: true`，剩余暴露面为 updateRepo / updateIssue* / gists PATCH 等；其 422 属用户输入校验错误，被显示为「请求被拒绝（HTTP 422）」+服务端片段，尚可读，但类型语义错位（原则 17：用类型表达失败）。P2。

### B3-B-10 · P2 · token_exit_warning 守卫只识别 authorization 头（确证，当前无暴露）
- 位置：`token_exit_warning.dart:71–99`（`headers['authorization']` 判定 carriesToken）。
- 问题：白名单主机逻辑本身正确（`.github.com` 整域 + 三个官方 githubusercontent 子域）；但若未来调用点的 headers 携带其它凭证头（cookie / api-key），不触发警告即放行。传输层 `_kSensitiveHeaders` 已堵六种，此处门禁只认一种，两层口径不一致（原则 3：例外应可枚举）。当前生产调用点只用 authorization，无现实暴露。P2。

### B3-B-11 · 确证通过 · OAuth Device Flow 令牌落库与脱敏（无发现，正面确认）
- 位置：`gh_oauth_io.dart`（全程不打印 token；仅错误对象入日志）、`gh_auth.dart:262–284`（saveAccount：令牌只进 `_vault.writeSecret`，KV 只存元数据；诊断 data 只含 `token.masked`）。
- 核对项全部通过：`GhToken.toString()` 只输出 `ghp_****abcd`（脱敏从 toString 开始，原则 39 ✅）；账号删除先删令牌后删元数据（防"看不见但还在"的令牌 ✅）；switchTo 校验令牌存在 ✅；`GhAccount.toJson` 不含令牌 ✅。device_code 不展示、不入日志 ✅。小瑕疵：poll 超时固定 15 分钟、未使用响应中的 `expires_in`，仅影响体验（不计级）。

### B3-B-12 · 确证通过 · repo_file_service 路径编码 #/? 截断（无发现，正面确认）
- 位置：`gh_api.dart:30`（`_ghPath` 逐段 `Uri.encodeComponent`）、`repo_file_service.dart:336–340`（`encodeForUrl` 同款）、`_validate`/`_segmentProblem`（用户输入直接禁 `?`/`#`/`%`/空格，仅 `A-Za-z0-9._-`）。
- 重点确证点结论：**截断向量已封死**——新输入路径字符集白名单天然无 `#/?`；历史路径（中文等）经逐段百分号编码后进入 URL，不会截断；提交 JSON 体使用原始路径（不被编码污染）。派生路径校验拒绝 `..` / 空段 / 反斜杠 / 控制字符 ✅。tree.truncated 拒绝执行（不搬一半）✅；>200 自动分批 + expectedHeadSha 链式推进 ✅；`_ensureTargetFree` 拒绝静默覆盖 ✅。唯一残留：`_probePath` 的 409/422 折叠（见 B3-B-04）。

### B3-B-13 · 确证通过 · 私有仓库加速警告 / 批量 confirmed 类型强制（无发现，正面确认）
- 私有 raw 加速：`NETWORK.md §四` 与 `settings_page.dart:1662/1678`（`_showPrivateAccelWarning` / `_setPrivateAccelAccepted`）对应；「关闭问询 = 拒绝加速」语义有文档与开关位背书；`token_exit_warning.dart` 为下载链路提供不可关闭三重保证（barrierDismissible:false + PopScope canPop:false + 无计时器）并留痕 TOKEN-EXIT-01 ✅。
- 批量 confirmed：`disk_cache.dart:603` `if ((intent.dangerous || intent.force) && !confirmed)` 类型上强制；裸写路径 `deleteContentLocked`（gh_api.dart:960–968）未确认时返回 `needsConfirmation` 不发 DELETE（B2 三方命中修复有效）✅；`IxTaskRunner` 无 `IxBatchDecision` 抛 `IxConfirmationRequired`（ix_task.dart:363）✅。

---

## 覆盖文件清单（全部 file_read 完整阅读）

| 文件 | 行数 | 结论 |
|---|---|---|
| lib/domain/gh/gh_api.dart | 2222 | B3-B-01/02/03/12 |
| lib/domain/gh/gh_client.dart | 812 | B3-B-02/08/09 |
| lib/domain/gh/gh_auth.dart | 406 | B3-B-11（通过） |
| lib/domain/gh/gh_models.dart | 983 | 已读，无新增发现 |
| lib/domain/gh/gh_draft.dart | 56 | 已读，无发现 |
| lib/domain/gh/gh_read_cache.dart | 184 | B3-B-08 |
| lib/domain/gh/gh_oauth.dart / gh_oauth_io.dart / gh_oauth_stub.dart / gh_oauth_types.dart | 58/113/18/43 | B3-B-11（通过） |
| lib/domain/gh/repo_file_service.dart | 2042 | B3-B-04/12 |
| lib/base/net/io_net_transport.dart | 552 | B3-B-07 |
| lib/surface/app/token_exit_warning.dart | 170 | B3-B-10/13 |
| docs/NETWORK.md / QUALITY_STANDARD.md / CONSISTENCY.md / AGENTS.md | 154/93/60/95 | 裁决依据 |
| 佐证（抽样 shell 查看调用点，未代替阅读范围文件） | — | issue_page.dart / repo_page.dart / workflow_dispatch_page.dart / disk_cache.dart / ix_task.dart 相关片段 |

## 整体评价

GitHub API 层的安全基本面**扎实**：令牌不出设备（第一跳白名单 + 跨主机重定向全拒 + 凭证头集合 6 种）、SSRF 字面量拦截、OAuth 令牌只进保险库且脱敏一致、D1/D7 的历史 P0（409 误折不存在、confirmed 未读、206 污染缓存）均有修复代码与注释可查，且修复注释引用了审计编号、可追溯。主要残余风险集中在两处：**Issue labels/assignees 全量替换缺并发保护**（B3-B-01，唯一可能真实丢数据的点，P1）与 **rawText 的第一跳令牌无主机约束**（B3-B-02，结构性缺口，当前调用点安全）。其余为语义折叠与文案级 P2。未发现伪造成功、静默降级或防线开关类 P0。
