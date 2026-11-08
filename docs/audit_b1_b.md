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

---

## 补录（B1-B-02 ~ B1-B-15）

> B 视角会话在写入第 1 条后被工具中断；以下 14 条均已在当时通过 `file_read`
> 完整读代码确证，按最终返回的结论原样补录，供交叉报告引用。

- **B1-B-02 P1**：`range_download_io.dart:204-232` 分片 206 缺 `Content-Range` 时 `_rangeOf` 返回 null 直接放行，只校验 `got == range.length`；CDN 等长错位区间会合并成大小正确但内容损坏的文件，repo/gist/归档/artifact 无 sha256 校验。证据确证。
- **B1-B-03 P1**：`io_net_transport.dart:163-165` `hasCredential` 只认 `authorization`；`cookie`/`proxy-authorization`/`x-auth-token`/`api-key` 走 `followRedirects=true` 被重发到跨主机。当前生产调用点只用小写 authorization，故契约级而非已触发。
- **B1-B-04 P1**：`io_net_transport.dart:174-184` 无凭证请求完全自动跟随，Location 不校验 http/https、回环、私网、`169.254.169.254` → SSRF 与明文降级面。
- **B1-B-05 P1**：`ix_presign_io.dart:81-82` `on Object catch` 吞第一跳失败；`surface_bridge.dart:306-315` 不读 `IxPresignResult.error`，401/403/超时/「目标不安全」全静默变成「回退直连 + 重新带令牌」，安全拒绝被伪装成慢路径。
- **B1-B-06 P1**：`repo_page.dart:268-296`（_downloadZip）与 `file_preview_page.dart:447-503`（内联 Image.network）私有令牌经第三方加速通道，但**未过** `ogLGuardTokenExitDownload`；全项目仅 4 处守卫，token_exit_warning.dart 声称的「四个下载调用点共用」与事实不符。
- **B1-B-07 P1**：加速通道可改写响应体（download_proxy.dart:15-22 自陈），但除 Release 外所有 enqueue 均不传 `expectedSha256`；私有 raw 的 Accept 头只在非加速 API 路径存在，加速路径丢头无兼容性探测。
- **B1-B-08 P1（局部确证）**：`accel.dart:174-190` `OgLAccelChannel.fromJson` 不调用 `ogLValidateAccelBaseUrl`；`settings.dart:428-433` 与 `download_proxy.dart:113-117` 直接拼接持久化的 baseUrl，被篡改 KV 可带 `http://` 或内网地址。settings.load() 全文未读，持久化链是否另有校验待议。
- **B1-B-09 P1**：`net_dns.dart` `_ipv4` 正则不查 ≤255/私网、忽略应答 TTL 统一缓存 5 分钟、parseAnswers 不校验 QNAME、DoH `name=$host` 未编码、parseDohJson 不校验 answer name；`io_net_transport.dart:361-377` IoDnsHttpClient 未关自动重定向。恶意 DoH 可投毒/降级。
- **B1-B-10 P2**：`net_dns_platform_io.dart:45-71` 绑定 anyIPv4、源端口不校验、地址字符串精确比较；`net_dns.dart:397-430` TXID 单调可预测。IPv6 DNS 永远超时回退系统解析。
- **B1-B-11 P1**：`io_net_transport.dart:75/186-187/222-224` autoUncompress + 无上限 utf8.decoder.join() + `on Object catch` 把 FormatException 包成 unknown（可重试）→ gzip 炸弹 OOM、损坏响应被误报并重试。
- **B1-B-12 P2**：`kernel/contract/net_types.dart:123` 默认 timeout 30s，全 `lib/base/net/` 零引用；实际用 15s/60s。调用方 `gh_client.dart:597` 传 30s 无效。
- **B1-B-13 P2**：`range_download_io.dart:62-68` 双重 catch 折叠成 supportsRange:false 无日志；`net_types.dart:222-224` parseRetryAfterHeader 吞错；`net_self_test.dart:35-47` 先清 DNS 缓存再取 30s 缓存报告 → 附上旧真相。
- **B1-B-14 P2**：`net_transport.dart:98-107` 换跳不回填响应，`io_net_transport.dart:189-194` 不传 fromMirrorId → `gh_client.dart:625` 的「镜像 X」日志恒不触发；`net_mirror.dart:30-54` 正则改写无 scheme/host 校验。
- **B1-B-15 P2**：`release_detail_page.dart:246`、`file_preview_page.dart:113` 注释仍称「直连兜底」，与 `download_proxy.dart:72-83/112-117` 的「至多一项、无降级」相反，误导排障。

## 复核通过（未列问题）
Authorization 大小写覆盖 · 带凭证跨主机 302 不跟随 · ix_presign 第一跳 followRedirects=false + 令牌只在第一跳 · TLS 无 badCertificateCallback 旁路 · 重试耗尽显式抛 NetException · DoH 初始端点只认 https · 无预置代理。
