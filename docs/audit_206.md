# 提交 / 保存 HTTP 206 审计（A-206 系列）

> 范围：`main` 分支 v11.2.0，用户实测「所有问题里，提交仍然报 206 错误」。
> 纪律：`lib/domain/gh/gh_client.dart`、`lib/base/net/io_net_transport.dart`、
> `lib/base/net/net_transport.dart`、`lib/base/net/net_types.dart`、
> `lib/base/net/range_download_io.dart`、`lib/surface/app/client_shell.dart`、
> `lib/surface/pages/search_page.dart`、`lib/surface/app/og_l_app_bar.dart`
> 以及写链路 `lib/domain/gh/gh_api.dart` / `lib/base/disk/disk_cache.dart`
> 均已完整 `file_read`（非 rg 摘要）。行号以本工作区当前内容为准。

## A-206-01 · 代理截断写响应体：206 的分段体被当完整 JSON 回执解析（P0，已修复）

### 编号

`A-206-01`（用户口径：提交 / 保存仍报 206）。

### 根因（确证）

1. **206 不是 GitHub 写 API 的正常响应，也不是重定向守卫造出来的。**
   `PUT /repos/{owner}/{repo}/contents/{path}` 的正常回执是 `200/201` +
   完整 JSON（含 `content.sha`）。`206 Partial Content` 是 RFC 7233 的
   **分段响应语义**：本次链路上的代理 / CDN 对写请求回了分段 / 截断的
   响应体并原样透传状态码。项目自己早就观测到同一类中间设备行为：
   `lib/base/net/range_download_io.dart:204-205` 注释明确写着「206 不等于
   "给的就是我要的那一段"：中间设备 / CDN 会回错位的区间」——下载侧因此
   校验 `Content-Range`（`:208-217`），而 **API 写侧没有任何等价校验**。

2. **透传点（状态码 / body / 头原样上送）**：
   `IoNetTransport.send`（`lib/base/net/io_net_transport.dart:154-193`）把
   `HttpClientResponse.statusCode`、解码后的 `text`、扁平化响应头直接构造成
   `NetResponse`（`:186-193`），不检查 `Content-Range` / `Content-Length` /
   实体是否完整。带凭证请求走的 `_sendWithGuardedRedirect`
   （`:241`、`:252-254`）只对 `3xx` 决定「同源跟随 / 跨主机原样交回」，
   对 `2xx`（含 206）不做任何干预：**守卫既不把 3xx 改写成 206，也不重组
   分段体，只是把代理给的 206 如实透传给上层**。

3. **韧性层同样如实返回**：`ResilientTransport.send`
   （`lib/base/net/net_transport.dart:151-152`）中 206 不在
   `retryableStatuses` 里，直接 `return response`；对 PUT 这恰好符合
   「非幂等方法绝不自动重试」（`net_transport.dart:28-33`），不能改成重试。

4. **2xx 判定本身是对的，不是故障源**：`NetResponse.isSuccess`
   （`lib/kernel/contract/net_types.dart:192`；`lib/base/net/net_types.dart`
   只是 7 行转发导出）、`GhResponse.isSuccess`
   （`lib/domain/gh/gh_client.dart:311`）与 `_throwIfFailed`
   （`gh_client.dart:725-729`）都把 206 归入 `200 <= status < 300`，
   **`_throwIfFailed` 不会把 206 当失败抛**。因此用户看到的「提交失败 206」
   并不是 `GhClient` 的 HTTP 错误映射，而是下游把**残缺响应体**当成完整
   回执后产生的假失败（错误信息里带着 206 状态码）。

5. **真正的损坏点**：`GhResponse._decode`（`gh_client.dart:323`）对截断
   JSON 抛 `FormatException`，`jsonObject`（`:326-333`）把它吞成 `null`；
   `GhApi.putContent`（`gh_api.dart:773-793`）于是用空 Map 构造
   `GhContent`，得到 `written.sha == ''`；
   `GhApi.write`（`gh_api.dart:2009`）把空 sha 作为 `RemoteDocument` 交给
   `RepositoryCache._writeLocked` 的 D5 回读校验
   （`lib/base/disk/disk_cache.dart:693-699`）：`expectedSha` 为空串，
   与远端真实 sha 永不相等 → 回读确认失败，引擎只能以「空 sha +
   本次写入内容」落本地缓存（`:697-701`），D2 冲突基线 / D5 校验从此
   失真；若此链路再遇任何异常，`write` / `delete` 的统一异常出口会
   返回 `WriteConflict.server` 并记诊断码 `OGL-CONS-206`
   （`disk_cache.dart:277`、`:375`）——那是**诊断码，不是 HTTP 206**，
   用户提示里出现的「206」来自 `GhResponse.statusCode` 或代理错误文案，
   二者不可混为一谈。而 **PUT 很可能已经在远端生效**；用户按提示
   重试同一请求会撞 409/422（文件已存在 / 基线已变），正是
   `net_transport.dart:28-33` 警告过的重复提交风险。

6. **语义结论**：206 属 2xx **成功语义**，但它的 body 可能只是一个片段，
   不满足「写回执是完整 JSON」这一假设。既不能把 206 当 HTTP 失败抛，
   也不能把残缺 body 当完整 JSON 解析后取 `sha`；正确语义是
   **「写已发出，回执未知」→ 用远端状态确认**。

### 后果

- 用户侧：点保存后报「提交失败 206 / 写入异常终止」，但远端文件其实
  可能已经更新；后台通知与「待同步」队列显示失败，诱导用户重复提交。
- 数据侧：空 sha 进入 D5 回读校验与冲突判定，使 `staleSha` /
  `verificationFailed` 分支失真；重试非幂等 PUT 有覆盖 / 422 冲突风险。
- 排查误导：日志里的 206 让人以为是 `_throwIfFailed` 或重定向守卫
  把 3xx 判错；实际是「2xx 成功 + 不完整实体」未被写链路识别。

### 修复方法（已落地，最小改动，不改公共接口）

由主会话在 `lib/domain/gh/gh_api.dart` 落地；本审计只补文档，不重复改动
`lib/`。

修复落在**唯一消费写回执的地方** `GhApi.putContent`
（`lib/domain/gh/gh_api.dart:795-811`）：

1. 保留 `GhClient` / `NetResponse` 的 2xx 判定：206 仍按成功处理，
   **不**加入失败分支、**不**加入 `retryableStatuses`、**不**重试 PUT。
2. 解析后检查 `written.sha.isEmpty`（`gh_api.dart:799`）：为空即说明
   响应体不完整 / 被改写，**不再把残缺 JSON 当权威回执**，也不伪造 sha。
3. 用 `_contentNetwork(...)` **回读远端确认**（`gh_api.dart:800-803`）：
   远端确实已有该文件且 sha 非空 → 以真实 sha 作为写结果，D5 回读
   校验、D8 队列收尾、D9 清草稿全部按正常成功路径完成；用户看到
   「已提交」而不是「206 失败」。
4. 回读也拿不到时（`:804-810`）**如实抛出**带真实状态码的
   `GhAuthException`：「提交已发出但响应不完整（HTTP 206）；无法确认远端
   状态，请稍后刷新查看」——不静默成功、不自动重放，由 D6 / 通知中心
   呈现，避免把一个状态未知的写伪装成成功。
5. 不改动 `io_net_transport.dart` / `net_transport.dart` /
   `gh_client.dart` 的公共契约；与下载侧
   `range_download_io.dart:204-217` 的「206 必须校验区间」形成同一原则：
   **206 是成功状态，但不是完整实体**。

### 对照（排除项）

- `_throwIfFailed`（`gh_client.dart:725-729`）：2xx 直接 `return`，无缺陷。
- `_sendWithGuardedRedirect`（`io_net_transport.dart:241-273`）：只处理
  3xx，不制造 206；无需改动。
- `ResilientTransport`（`net_transport.dart:151-152`）：206 不重试，正确。
- `OgLRangeDownloader`（`range_download_io.dart:198-217`）：下载分片已经
  对 206 做 `Content-Range` 与长度校验，写 API 链路此前缺的是等价的
  「回执完整性」确认，现已由 `putContent` 的回读兜底。

### 门禁

`dart format --language-version=3.6 lib test` 与
`layer_audit.py / ui_audit.py / motion_audit.py / perf_audit.py`（均
`--fatal`）结果见本次任务返回；本文档不改动任何 `lib/` 代码。
