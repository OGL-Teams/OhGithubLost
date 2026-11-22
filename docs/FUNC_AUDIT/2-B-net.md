# 功能审计报告 · 批 2-B · 网络传输层（lib/base/net/）

> 更新时间：2026-11-23 06:52:10 +0800 · v15.0.0
> 审计范围：`lib/base/net/` 全部 12 文件（3353 行）+ 契约层 `lib/kernel/contract/net_types.dart`（415 行）。只读审计，未改动任何代码。

---

## 一、总体印象

传输层核心守卫（重定向白名单、凭证头集合、DoH 降级链、IP 黑名单、Retry-After 三形态解析、幂等重试铁律）经多轮交叉审计（B1-A/B1-C/F-* 编号）后已相当扎实，未发现 P0 级问题。残余问题集中在：**分片下载器绕过了主传输的守卫**、**Retry-After 被本地 8s 上限截断导致限流额度被烧**、**分片 fetch 无任何超时**。

## 二、问题清单

### P1（功能失效 / 不一致）

**P1-1 分片下载器完全绕过重定向守卫，凭证头可随自动重定向外泄**
- 症状：`lib/base/net/range_download_io.dart` 的 `probe`/`_probeByRange`/`_fetchPart` 用 `_client.headUrl/getUrl`（34/87/172 行附近），未设 `followRedirects=false`（全仓库仅 `io_net_transport.dart:307`、`ix_action_logs_http_io.dart:30,98`、`ix_presign_io.dart:26` 三处设置）。dart:io 默认自动跟随最多 5 跳并**原样重发全部请求头**——私有仓库 raw 下载时 `spec.headers` 带 `authorization: Bearer …`（`ix_download.dart:956-960` 透传），若源站或用户自配加速通道 302 到第三方 https 主机，令牌随之送出。主传输 `IoNetTransport._sendWithGuardedRedirect` 已堵死同类问题，Range 引擎却未接入。
- 根因：`OgLRangeDownloader` 自建 `HttpClient`（无 connectionTimeout、无守卫），是主传输之外的"第二条 HTTP 通道"，安全收敛漏掉了它。
- 复现：`rg -n "headUrl|getUrl" lib/base/net/range_download_io.dart`；`rg -n "followRedirects" lib` 对比。
- 修复指令：`range_download_io.dart` 三处请求统一加 `request.followRedirects = false; request.maxRedirects = 0;`；对 3xx + Location 做与 `_ogLIsSafeRedirectTarget` 同等的判定（https-only、拒绝跨主机或剥离 `_kSensitiveHeaders`）；同时给 `_client.connectionTimeout` 赋值（见 P1-3）。

**P1-2 Retry-After 被 maxDelay(8s) 硬截断，限流场景反复撞额度**
- 症状：`net_retry.dart:74-77`——`retryAfter > maxDelay ? maxDelay : retryAfter`。GitHub 次级限流常给 `Retry-After: 60`，客户端会在 8s 后就重发，`maxAttempts=3` 内连撞 2 次，正好违反文件自述的"尊重服务端：限流场景必须听话"，白烧限流恢复窗口（对应任务维度⑥"烧额度"）。响应路径 `net_transport.dart:233-241,249-257` 同样吃这个截断。
- 根因：把"防异常头拖死"实现成无条件截断，而不是区分"合理大值"与"异常值"。
- 复现：`rg -n "retryAfter > maxDelay" lib/base/net/net_retry.dart`。
- 修复指令：将截断上限与 `retryableStatuses` 重试预算联动——服务端 Retry-After ≤ 60s 时**原样遵守**（超出预算允许放弃该次请求并显式失败）；或至少把 `maxDelay` 与截断只应用于本地指数退避，服务端值单独设上限（如 120s）。

**P1-3 分片下载 `_fetchPart` 全程无超时，坏节点可挂死整次下载**
- 症状：`range_download_io.dart` `_fetchPart` 中 `await request.close()`（约 172 行）无 `.timeout`，且 `_client = HttpClient()` 未设 `connectionTimeout`（默认 null = 永等）——probe 阶段有 15s 超时，真正传输阶段反而裸奔。服务端 accept 连接后不发响应/不发数据时，`Future.wait` 永不返回，任务卡 running（对比 `io_net_transport.dart` 的 connectTimeout 15s / receiveTimeout 60s / body join timeout）。
- 根因：实现文件只给 probe 复制了超时常量，fetch 路径遗漏。
- 复现：`rg -n "close\(\)" lib/base/net/range_download_io.dart`；`rg -n "connectionTimeout" lib/base/net/`（Range 引擎零命中）。
- 修复指令：构造器设 `_client.connectionTimeout = 15s`；`_fetchPart` 的 `close()` 与 `await for` 循环外加超时（如 60s 无进展判失败），失败走既有 finally 清理路径。

### P2（打磨）

**P2-1 UDP DNS 应答结果未经 IP 白名单过滤（纵深不一致）**
- 症状：`UdpDnsResolver.resolve`（`net_dns.dart`，`rg "parseAnswers\(response"`）直接返回 `parseAnswers` 结果；DoH 路径逐条过 `ogLIsBlockedLiteralIp`（net_dns.dart:614-617），UDP 路径只在**连接时**（io_net_transport.dart:158-163）兜底。若上层其它消费方直接使用 `DnsService.resolve` 结果（当前仅传输层使用，风险低），被污染的 UDP 应答可携带私网 IP 进缓存。
- 修复：`_attempt` 返回前统一过滤（与 DoH 同一白名单），或在 `DnsService._remember` 入口过滤。

**P2-2 `ogLIsBlockedLiteralIp` IPv6 覆盖不全**
- 症状：`net_transport.dart:57-70` 只拦 `::1`/`::`/fe80/fc/fd 与 4 组 IPv4-mapped（10/127/192.168/169.254）；漏 `::ffff:172.16.x.x`、`::ffff:100.64.x.x`、`::ffff:0.x`、IPv6 组播 ff00::/8。攻击面小（需先骗过 DNS）。
- 修复：mapped 形态改为提取 `::ffff:a.b.c.d` 后复用 IPv4 判定；补 ff02-ff0e 前缀。

**P2-3 `IoDnsHttpClient` 允许任意跨主机 https 重定向**
- 症状：`io_net_transport.dart:474-506`（`rg "hop < 3"`）：只拦降级 http，不拦跨主机——DoH 查询（含被解析域名）可被 302 送往任意第三方 https 主机（无凭证，但查询域名泄露）。修复：跨主机跳转直接拒绝（DoH 端点不应重定向换域）。

**P2-4 跨主机重定向分支为冗余死代码**
- 症状：`io_net_transport.dart:337-341`——`if (_carriesSensitiveHeader(...)) return response; return response;` 两支完全相同。行为正确（一律不跟随），但注释暗示"带凭证才拒绝"，实际无凭证也不跟随；删掉 if 或改注释，避免后人误改出"无凭证可跟随"的回归。

**P2-5 301 对 POST 不降级 GET**
- 症状：`io_net_transport.dart:348-350` 只对 302/303 降级；`301` + POST 按代码保持 POST+body。多数服务端/浏览器按 302 同样降级 GET，行为不一致会导致某些 301 端点挂起或 400。至少补注释说明刻意取舍，或纳入 switchToGet。

**P2-6 `NetResponse.etag` 为死代码，无 304/条件请求实现**
- 症状：`net_types.dart:210` 定义 `etag` getter，全仓库无使用点（`rg -n "\.etag" lib` 仅此一处）；传输层无 HTTP 缓存，无 If-None-Match/If-Match 条件请求。维度⑤结论：**本层不存在 206/304 缓存逻辑，因此不存在相关缺陷**；206 Range 校验在 `range_download_io.dart:197-224`（Content-Range 存在性/对齐/总量三重校验）已到位。若批 1-B 的 `gh_read_cache` 需要 ETag 协商，需另行接通。

**P2-7 `ogLIsUsableDohEndpoint` 放行 `https://[::1]`**
- 症状：`net_dns.dart:64-82` 仅校验 IPv4 形态字面量，IPv6 回环主机名通过；由 `DohDnsResolver.resolve` 的 `ogLIsBlockedLiteralIp(Uri.parse(endpoint).host)` 兜底抛错（net_dns.dart:569-573），但 `DnsServer.supportsDoh` 会误报 true（UI 展示层）。修复：endpoint 校验同样过 `ogLIsBlockedLiteralIp`。

**P2-8 `connectionFactory` 代理分支不过滤代理地址**
- 症状：`io_net_transport.dart:153-158`——`Socket.startConnect(proxyHost, proxyPort)` 前未过 `ogLIsBlockedLiteralIp`。当前应用未配置 HTTP 代理（`proxyHost` 恒 null），属防御性缺口。

**P2-9 观测器 `bytesIn` 按字符数而非字节数计**
- 症状：`net_types.dart` `onResponse` 用 `bodyLength`（`String.length`，UTF-16 code unit 数），中文内容严重低估流量统计；字段名与语义不符。

## 三、已检查清单（全覆盖，非抽样）

| 文件 | 行数 | 结论 |
|---|---|---|
| io_net_transport.dart | 538 | P2-3/4/5/7/8；主守卫（协议白名单 `_ogLIsSafeRedirectTarget`、302/303 bodyOverride 降级、`_kBodyBoundHeaders` 剔除、`_kSensitiveHeaders` 六头集合、DNS 结果过滤、IPv4 优先+系统回退）逐条核过，无 P0/P1 |
| net_bridge.dart | 228 | applyDnsSelection 规格化/拒绝非法自定义地址、dnsSummary 如实降级展示——无新问题 |
| net_dns.dart | 1224 | DoH A/AAAA/CNAME 链/TTL>0/owner 缺失拒绝；UDP 编解码事务 ID+来源 IP 双校验；竞速/顺序/回退留痕；缓存逐字段比较失效——P2-1/7 |
| net_dns_platform_io.dart | 79 | 来源 IP 校验、`isIpLiteral` 区分 host:port——无问题 |
| net_transport.dart | 397 | ResilientTransport 换跳不烧预算、幂等铁律（PUT/DELETE 不自动重试）、异常路径 kind 门控、asctime 补解析、显式失败——P2-2 |
| net_retry.dart | 93 | 指数+抖动纯函数；Retry-After 截断——P1-2 |
| net_mirror.dart | 165 | 机制保留、内置通道为空（合规）；反向引用替换顺序正确——无问题 |
| net_self_test.dart | 60 | 30s 同主机缓存——无问题 |
| net_self_test_impl_io.dart | 119 | DNS/TCP/TLS/HttpClient 四探针、失败路径 close(force:true)——无问题（假令牌探测仅自检用） |
| range_download.dart | 98 | ChunkPlan floor 修正（B1-A-14）、闭区间覆盖——无问题 |
| range_download_io.dart | 345 | 206 Content-Range 三重校验、合并半成品清理、Future.wait 全收敛——P1-1/P1-3 |
| net_types.dart（转发） | 7 | 仅 export——无问题 |
| kernel/contract/net_types.dart | 415 | Retry-After 三形态（IMF/RFC850 + 传输层 asctime 补齐）、NetException.retryAfter 透传、etag getter——P2-6/9 |

死循环核查：重定向 5 跳、DoH HTTP 3 跳、`advanceHop` 收敛于直连、竞速 completer 单次完成、DNS 回退单次——**均无死循环**。超时核查：主传输 connect 15s/receive 60s/body join request.timeout 全覆盖；唯 Range fetch 裸奔（P1-3）。

## 四、本席结论

P0 = 0，P1 = 3，P2 = 9。主传输与 DNS 层经多轮修补已无高危缺口；三条 P1 全部集中在 **Range 分片下载器这条"影子 HTTP 通道"**（绕守卫、无超时）与 **Retry-After 截断烧限流**，修复面小、互不耦合，建议优先级 P1-1 > P1-3 > P1-2。维度①③④⑥核过无高危，维度②仅截断策略争议，维度⑤确认本层无缓存逻辑（无缺陷也无功能），维度⑦凭证头集合完整、跨主机一律不跟随（含 P2-4 注释债）。
