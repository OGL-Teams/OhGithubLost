# 第1批 · 视角 B（安全与数据）审计：网络传输层

> 分支 `main` @ `dfd867f`。范围：`lib/base/net/` 全部 12 文件 + `lib/kernel/contract/net_types.dart`
> + `lib/domain/ix/ix_presign.dart` / `ix_presign_io.dart` + `lib/surface/util/download_proxy.dart`。
> 全部以 `file_read` 完整通读（未以 rg 摘要代替阅读）；跨层后果证据另以 `file_read` 读了
> `gh_client.dart` / `surface_bridge.dart` / `accel.dart` / `token_exit_warning.dart` /
> `release_detail_page.dart` / `file_preview_page.dart` / `repo_page.dart` /
> `ix_download.dart` / `ix_download_backend_io.dart` / `ix_action_logs_http_io.dart` / `domain_bridge.dart` / `gh_api.dart`。
> 依据：`docs/QUALITY_STANDARD.md`（59 条原则）+ `AGENTS.md`。只审不改，未写入任何 `lib/` 文件。
> 行号以本工作区当前内容为准。每条含「编号 / 文件:行号 / 问题 / 用户可见后果 / 级别 / 违反原则 / 是否确证（代码证据）」。

## 覆盖文件清单（16 个，全部完整 file_read）

| # | 文件 | 行数 |
|---|---|---|
| 1 | `lib/base/net/io_net_transport.dart` | 386 |
| 2 | `lib/base/net/net_bridge.dart` | 205 |
| 3 | `lib/base/net/net_dns.dart` | 1069（分两段完整读，含 596 行续读） |
| 4 | `lib/base/net/net_dns_platform_io.dart` | 79 |
| 5 | `lib/base/net/net_mirror.dart` | 165 |
| 6 | `lib/base/net/net_retry.dart` | 93 |
| 7 | `lib/base/net/net_self_test.dart` | 60 |
| 8 | `lib/base/net/net_self_test_impl_io.dart` | 119 |
| 9 | `lib/base/net/net_transport.dart` | 237 |
| 10 | `lib/base/net/net_types.dart` | 7（转发导出） |
| 11 | `lib/base/net/range_download.dart` | 92 |
| 12 | `lib/base/net/range_download_io.dart` | 300 |
| 13 | `lib/kernel/contract/net_types.dart` | 334 |
| 14 | `lib/domain/ix/ix_presign.dart` | 241 |
| 15 | `lib/domain/ix/ix_presign_io.dart` | 98 |
| 16 | `lib/surface/util/download_proxy.dart` | 118 |

---

## B1-B-01 · 206 / 截断响应体被当作完整实体透传，传输层无任何完整性校验（P1，确证）

- **文件:行号**：`lib/base/net/io_net_transport.dart:186-194`（含守卫路径 `:241-253`）；契约 `lib/kernel/contract/net_types.dart:165-203`；韧性层 `lib/base/net/net_transport.dart:150-153`；对照 `lib/base/net/range_download_io.dart:198-217`。
- **问题描述**：`send()` 把 `response.statusCode`、`utf8.decoder` 拼出的 `text`、`_flattenHeaders` 直接构造成 `NetResponse`，**不检查** `Content-Range`、`Content-Length`、`Transfer-Encoding`、`Content-Encoding`，也不校验实体长度与声明是否一致。`NetResponse` 只有 `statusCode / body / duration / headers / fromMirrorId` 五个字段（`:168-189`），**没有任何「实体是否完整 / 是否为分段响应」的标记**；`isSuccess` 只写 `200 <= status < 300`（`:191-192`），206 因此与 200 完全同义。`_sendWithGuardedRedirect`（`:249-253`）只处理 3xx，对 2xx 原样返回。`ResilientTransport` 见 206 不在 `retryableStatuses`（默认 `{408,429,500,502,503,504}`，`net_retry.dart:17`）就直接 `return response`（`net_transport.dart:151-153`）。对照下载侧：`_fetchPart` 明确要求 `statusCode == 206`，解析 `Content-Range` 并与请求区间逐端比对，再校验 `got == range.length`（`range_download_io.dart:199-232`）；`probe` 还要求 `acceptRanges.contains('bytes')`（`:52`）。**API 侧没有任何等价校验**。
- **用户可见后果（含数据/凭证风险）**：代理 / CDN 对写请求（如 `PUT /repos/…/contents/…`）回 `206 Partial Content` 加截断 body 时，状态码与残缺 body 确实被「如实」透传，但上层拿到的是一个**被当成完整 JSON 回执的片段**：`GhResponse.jsonObject`（`lib/domain/gh/gh_client.dart:326-333`）吞掉 `FormatException` 返回 `null`，`GhApi.putContent` 会得到空 `sha`。虽然 `gh_api.dart:795-811` 已加「空 sha → 回读远端确认 / 如实抛错」的下游兜底，**其余 2xx 消费点没有该兜底**：例如 `gh_client.dart:599-606` 对任何 `isSuccess` 的 GET 直接把 `response.body` 回填只读缓存（`_readCache.put`），于是**截断/改写的残缺 JSON 被当作权威数据缓存 30–60 秒并渲染给用户**（列表空/半截、字段缺失）；`GhResponse.jsonAsList` 同样把坏 JSON 折叠成空列表（`:335-346`），用户看到「空仓库/空列表」而不是错误。对写路径，用户看到「提交失败 206」而远端可能已生效，诱导重复提交（非幂等 PUT 撞 409/422）。传输层无法区分「完整 200」与「残缺 206 / 被改写 200」，是这条链的共同根因。
- **级别**：P1。
- **违反原则**：42（失败如实报错；伪造/不完整的成功响应比失败更难排查）、20（外部数据不可信）、8（数据无价）、15（静默降级）。
- **是否确证**：**确证**。代码证据：`io_net_transport.dart:186-194` 无 `Content-Range`/`Content-Length` 校验即返回；`net_types.dart:168-192` 响应类型无完整性字段、`isSuccess` 波段含 206；`net_transport.dart:151-153` 对不在重试集合的状态码原样返回；`range_download_io.dart:204-217` 注释自陈「206 不等于给的就是我要的那一段……中间设备 / CDN 会回错位的区间」并做了区间 + 长度双校验；`docs/audit_206.md` 记载同类截断已在生产链路出现（A-206-01）。
