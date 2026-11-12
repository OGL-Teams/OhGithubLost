# v12.6.0 LTS 发布后 · DNS / 网络功能专项复核

- 审查对象：HEAD `5c84d6f`（v12.6.0 LTS），只读审查，未修改任何源码/文档（本文件除外），未执行任何 git 写操作。
- 权威口径：`docs/NETWORK.md`、`AGENTS.md` 网络章节、`docs/QUALITY_STANDARD.md` 第七章（§39–44）、批 1 审计（`docs/audit_b1_*.md`）、`docs/audit_debug_empty_fail.md`（DBG-04）、TOKEN-EXIT-01 / B7-B-01。
- 环境限制：本地无 Flutter/Dart SDK，未跑 `flutter test` / `dart analyze`；结论来自静态代码路径核对。凡「库内部行为」类结论一律放入「推测」章节。
- 级别口径：P0 = 凭证外泄 / SSRF / 主功能不可用；P1 = 安全边界缺口或用户可见的功能失真；P2 = 契约偏差、可观测性与边角功能。

---

## 一、确证发现（代码事实，逐条可复现）

### F-01 · P0 · 自定义 DNS 的 UDP 应答完全不校验 owner 与结果 IP，可把流量导向云元数据/内网

`lib/base/net/net_dns.dart:445-455`（`UdpDnsResolver.resolve` 只发 `typeA` 查询并直接返回 `parseAnswers`）：
```dart
final query = DnsWireCodec.buildQuery(host, id: queryId);
final response = await channel.exchange(serverIp, query, timeout: timeout);
if (response == null) { throw DnsException('${server.label} 无响应（超时）'); }
return DnsWireCodec.parseAnswers(response, expectId: queryId);
```
`lib/base/net/net_dns.dart:320-345`（`DnsWireCodec.parseAnswers`）只按 answerCount 遍历、见 `type == typeA && dataLength == 4` 就 `addresses.add(...)`，**不校验 answer.name / CLASS / TTL / 结果 IP 安全性**；相比之下 DoH JSON 路径有 `isSafeIpv4`（`net_dns.dart:560`）。`lib/base/net/io_net_transport.dart:180-196` 的 `connectionFactory` 把 `dns.resolve(uri.host)` 结果直接交给 `Socket.startConnect(address, port)`。于是任一可注入 UDP 应答（或恶意/被劫持的自定义解析器）返回 `169.254.169.254` / `127.0.0.1` / `10.x`，都会让带 `Authorization` 的 HTTPS 请求连到该 IP（SNI 仍是原域名，但请求已打到内网/元数据端点）。`net_dns.dart:915`、`923-936` 的系统回退同样不过滤 `DnsPlatform.lookup` 结果。

**修法**：在 `DnsService._attempt` 出口统一过滤（对每条地址执行 `ogLIsSafeIpv4` 与 IPv6 的 loopback/link-local/ULA 判定，类同 `io_net_transport.dart:86-101`）；`parseAnswers` 增加 owner 名称与查询域名比对、CLASS=IN、TTL 解析；`DnsAnswer` 记录真实 TTL。过滤结果为 `[]` 时抛 `DnsException('解析结果全部为不安全的地址')`，而不是继续直连。

### F-02 · P1 · DoH 查询构造与响应解析只支持 A：无 AAAA / CNAME / DNS64 / TTL

`lib/base/net/net_dns.dart:500-507`：
```dart
final body = await client.get(
  '$endpoint${separator}name=${Uri.encodeQueryComponent(host)}&type=A',
  headers: const <String, String>{'accept': 'application/dns-json'},
).timeout(timeout);
return parseDohJson(body, host: host);
```
`net_dns.dart:536` `if (answer['type'] != DnsWireCodec.typeA) { continue; }` —— AAAA(type 28) 与 CNAME(type 5) 一律丢弃；`net_dns.dart:445-455` 的 UDP 分支同样固定 `buildQuery(host, id: queryId)`（默认 `typeA`）。后果：仅 AAAA / CNAME 链的域名在自定义 DNS 模式下必得空结果 → `_attempt` 抛「返回空结果」→ 回退系统 DNS（`net_dns.dart:923-936`）；IPv6-only / DNS64 网络永远拿不到合成地址（`net_dns.dart:885` 只处理 IPv6 字面量）。缓存 TTL 也不是响应 TTL：`net_dns.dart:952` `expiresAt: DateTime.now().add(policy.cacheTtl)`（固定 5 分钟）。

**修法**：按 `DnsPlatform` 能力同时发 `type=A`/`type=AAAA`（或 `type=255` ANY 后过滤），`parseDohJson` 接受 type 28 并按 `ogLIsSafeIpv4` 的 IPv6 等价规则校验；CNAME 跟随其 `data` 指向的后续 Answer（限制链长 ≤ 8）；解析 `answer['TTL']` 并写入 `DnsAnswer.expiresAt`（夹紧到 `[1s, 1h]`）。

### F-03 · P1 · DoH 应答 owner 校验可被「省略 name」绕过

`lib/base/net/net_dns.dart:539-550`：
```dart
final Object? answerName = answer['name'];
if (host.isNotEmpty && answerName is String) {
  final String normalized = answerName.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  if (normalized.isNotEmpty && normalized != host.toLowerCase()) { continue; }
}
final data = answer['data'];
if (data is String && isSafeIpv4(data)) { result.add(data); }
```
投毒者只需省略 `name`（或给非 String 类型）即可跳过比对；`normalized.isEmpty` 也放行。B1-A-13 的防投毒修复在此分支失效。

**修法**：`host.isNotEmpty` 时要求 `answerName is String && normalized == host.toLowerCase()`，否则 `continue`；同时校验 `answer['TTL']` 与 `Status==0` 且大小写/尾点归一。

### F-04 · P1 · 两次「静默降级」用户不可见（违反 QUALITY §15/§42、AGENTS「失败必留痕」）

1. DoH → 同家明文 UDP：`net_dns.dart:1000-1020`，仅 `_diagnostics?.info(..., code: 'OGL-DNS-103')`，成功后 `return (addresses: ..., serverId: server.id)` —— **返回的 `serverId` 与真 DoH 成功完全相同**，连 `lastResolvedVia` 都无法区分。
2. 自定义全部失败 → 系统 DNS：`net_dns.dart:923-936` 记 `warn OGL-DNS-101` 后 `await _attempt(systemResolver, host)` 并**正常返回成功**，`_remember(host, addresses, 'system(fallback)')`。

而用户侧：`lib/surface/surface_bridge.dart:231-232` 的 `dnsSummary` 只展示策略（`net_bridge.dart:30-46`），`lastResolvedVia`（`net_dns.dart:751`）**全项目唯一消费点是 DnsProbe**（`net_dns.dart:1099`）；`Kernel.runProbes`（`lib/kernel/kernel.dart:302`）在 `lib/` 与 `test/` 中**没有任何生产调用点**（仅 `test/kernel/environment_test.dart` 测注册机制）。网络设置页 `_networkTiles`（`lib/surface/pages/settings_page.dart:1025-1100`）无自检入口、无回退提示。即：用户以为走 DoH/自定义 DNS，实际已回落明文/系统解析，界面显示「N 家 DNS · DoH 优先」，属于规范明令禁止的静默降级。

**修法**：`_attemptServer` 的明文回落返回可区分的 `serverId`（如 `'${server.id}(udp-fallback)'`）并同步 `lastResolvedVia`；`NetBridge.dnsSummary` 追加「最近一次解析：自定义 / 系统回退」；在网络设置页增加 `runProbes()` 按钮并展示 `KernelProbeReport.detail`（`via` / `fallback`），或在回退发生时发一条通知中心告警。

### F-05 · P1 · 网络自检未覆盖 DNS / 直连 / 镜像三路，且结果未接入页面

`lib/base/net/net_self_test_impl_io.dart:20-100` 只做：`InternetAddress.lookup`（**系统** DNS A/AAAA）→ 逐 IP TCP → 裸 TLS `/zen` → `HttpClient /zen` + `/user`（假令牌 `Bearer selftest-fake`，`:80`，**不泄真实 PAT**）。没有：自定义 DNS/DoH 解析结果、镜像/加速通道连通性、直连与通道的对比。`lib/base/net/net_self_test.dart:21-59` 的 `cachedOrRun` 唯一调用点是 `io_net_transport.dart:466-470`（仅 SocketException / HttpException 时把报告拼进异常文本），`DnsProbe` 又因 F-04 的 `runProbes` 无调用点而从未运行。`NetworkSettingsPage`（`lib/surface/pages/network_page.dart:34-58`）只渲染 `_networkTiles` 闭包，无任何自检按钮/结果卡。

**修法**：`NetSelfTestImpl.run` 增加三路探针（自定义 DNS 解析、直连、加速前缀 + 目标 host，均用无凭证 GET/HEAD），结果结构化返回；网络设置页新增「立即自检」并把三路结果 + `lastResolvedVia` 如实渲染；首帧后调用一次 `kernel.runProbes()`。

### F-06 · P1 · 自定义 DoH 端点校验不完整；DoH 客户端允许跨主机 https 重定向

`lib/base/net/net_dns.dart:70-93` `ogLIsUsableDohEndpoint` 只查 `scheme == 'https'`、`host` 非空、`localhost`，以及 **IPv4 字面量** 的私网判定（`if (_ipv4Shape.hasMatch(host) && !ogLIsSafeIpv4(host))`）。IPv6 字面量（`https://[::1]/dns-query`）、域名型回环/元数据（`metadata.google.internal`、`169.254.169.254.nip.io`）、私网域名均被接受。`lib/base/net/net_bridge.dart:70-84` 直接把 `customDohUrl` 透传进 `DnsServer`，`lib/surface/pages/settings_page.dart:1120-1170` 的编辑弹窗保存时不调用 `ogLIsUsableDohEndpoint` 也不报错（非法值被静默丢弃，UI 仍显示「· DoH」）。
`lib/base/net/io_net_transport.dart:520-535` 的 `IoDnsHttpClient` 只拒绝 `next.scheme != 'https'`，**允许 3 跳任意跨主机 https 重定向**，且不复用 `_ogLIsSafeRedirectTarget`：`https://dns.example.com/dns-query` → `https://169.254.169.254/...` 会被跟随。https→http 降级拒绝已正确实现（`:525-531`，批 1 修复完好）。bootstrap 本身正确（`io_net_transport.dart:483-487` 刻意用独立 HttpClient 走系统解析，避免先有鸡还是先有蛋）。

**修法**：`ogLIsUsableDohEndpoint` 复用 `_ogLIsSafeRedirectTarget` 的等价实现（含 IPv6 字面量、端口/UserInfo 拒绝）；保存弹窗对非法 URL 显示错误且不落盘；`IoDnsHttpClient` 每跳调用同一目标白名单，跨主机一律拒绝并抛 `HttpException`。

### F-07 · P1 · 清空自定义 DNS IP 后旧解析器仍继续生效（配置变更窗口）

`lib/base/net/net_dns.dart:790-815` `applySelection`：
```dart
final List<DnsServer> picked = customServer != null ? <DnsServer>[customServer] : builtinDnsServers.where(...).toList();
final bool changed = policy.mode != mode || policy.preferDoh != preferDoh ||
    (picked.isNotEmpty && !_sameServers(policy.servers, picked));
...
if (picked.isNotEmpty) { policy.servers..clear()..addAll(picked); }
if (changed) { cache.clear(); ... }
```
`lib/surface/settings.dart:817-822` 清空 IP 时 `dnsServerId` 保持为 `'custom'`（不是内置 id）→ `picked` 为空 → `changed == false` → **不清缓存、不替换 servers**，`policy.servers` 仍是上一次的自定义 `DnsServer(id:'custom', ip:旧IP, dohUrl:旧端点)`。UI 显示自定义已取消，实际仍向旧 IP/旧端点查询最多 5 分钟（缓存 TTL，`net_dns.dart:952`）。同理「内置 id 拼错」时注释声称「保留原列表不静默清空」，但同样是配置不生效。

**修法**：`picked.isEmpty` 时按 `serverId` 回落到一个明确的内置默认值或抛 `DnsException('未配置任何 DNS 服务器')`；把「自定义字段变化」纳入 `changed` 判定；`applySelection` 无条件在 `customServer == null` 且 `serverId == 'custom'` 时清空 servers。

其余配置变更路径核对**通过**：`applySelection` 逐字段比较 `_sameServers`（`net_dns.dart:826-838`）、变更后 `cache.clear()`（`:813`）、`IoNetTransport._syncPolicy`（`io_net_transport.dart:230-236`）在 mode 切换时重装/撤回 `connectionFactory`（`:171`），且 `connectionFactory` 每次连接都重新 `dns.resolve(uri.host)`（`:180`）、`persistentConnection = false`（`io_net_transport.dart:432`）不复用旧连接 → **未发现「缓存旧 IP 不失效」的额外窗口**。

### F-08 · P1 · DBG-04 仍待决：presign 失败回退把真实 PAT 交给 background_downloader

`lib/surface/pages/release_detail_page.dart:243-265`：
```dart
final String direct = await widget.surface.resolveDownloadUrl(url);
final bool presigned = direct != url;
...
final Map<String, String> headers = presigned ? const <String, String>{}
    : await widget.surface.downloadAuthHeaders();   // 真实 Bearer PAT
...
await widget.surface.domain.downloads.enqueue(url: urls.first, fallbackUrls: ..., headers: headers, ...);
```
`lib/surface/pages/action_run_page.dart:390-405` 同构。`lib/domain/ix/ix_download.dart:656-671` 的 `ogLAssertDownloadUrl` 只校验 scheme；`lib/domain/ix/ix_download_backend_io.dart:74-80` 把 `headers: spec.headers` 原样交给 `DownloadTask`。`ogLGuardTokenExitDownload`（`lib/surface/app/token_exit_warning.dart:88-115`）只比较**首跳 URL 的 host**（此时是 `api.github.com`，白名单命中→直接放行），管不到库内部后续 302。`docs/audit_debug_empty_fail.md:83-137` 明确记录该路径为「❌未修 / P1(安全)」。分片探测 `lib/base/net/range_download_io.dart:26` 也用裸 HttpClient 默认跟随。

**修法**：presign 失败即中止下载并如实报错（首选）；或入队前对 `DownloadTask` 显式禁用跨主机重定向，或由本仓库先解 302 后才允许带凭证入队。切勿把「首跳 host 白名单」当作全链路门禁。

### F-09 · P1 · 加速通道持久化数据绕过 URL 校验；候选去重/白名单为字符串前缀

`lib/surface/util/accel.dart:185-200` `OgLAccelChannel.fromJson` 只要求 `id/baseUrl` 非空，**不调用** `ogLValidateAccelBaseUrl`（`:226-255`）；`lib/surface/settings.dart:277` 反序列化后 `lib/surface/settings.dart:480-486` `activeAccelPrefixes` 直接 `ogLAccelPrefixesFor(channel)`（仅补尾斜杠），无二次校验。`lib/surface/util/download_proxy.dart:95-116` 的协议白名单是 `url.startsWith('http://')||startsWith('https://')` 字符串判断，去重仅 `url.startsWith(base)`。因此被篡改/损坏的持久化配置可产出 `https://` + 原地址（等于伪装成加速的直连）、或把 `prefix` 指向 `https://169.254.169.254/`；`ogLValidateAccelBaseUrl` 本身也不拒绝私网/回环/元数据 IP 与 IPv6 字面量。`ogLAccelCandidates` 返回至多一项、无静默直连兜底（`:108-116`）这一条**核对通过**。

**修法**：`fromJson` 与 `activeAccelPrefixes` 共用 `ogLValidateAccelBaseUrl`（并扩展为 Uri 级校验：scheme 白名单、host 非空、拒绝私网/回环/元数据/IPv6 字面量），校验失败的配置项跳过并在 UI 提示；`ogLAccelCandidates` 改用 `Uri.parse(url).scheme` 判定协议、用 Uri 规范化做去重。

### F-10 · P2 · Retry-After 分支无 jitter、asctime 未实现；异常换跳退避绕过注入的 `_sleep`

`lib/base/net/net_retry.dart:71-74`（服务端值直接返回，未走 `:76-83` 的 jitter 分支）；`lib/kernel/contract/net_types.dart:273` 注释自认「asctime 在此不常见，统一走 ISO 兜底」，但 `_parseHttpDate` 在 `:292` 直接 `return null`（无 ISO 兜底实现）。`lib/base/net/net_transport.dart:148` 异常路径换跳用 `await Future<void>.delayed(wait)`，而响应路径 `:184` 用 `await _sleep(wait)` —— 注入的零延迟 `sleep` 在异常换跳分支失效（离线测试会真等）。`defaultRetryableMethods={get,head}`（`:33-36`）、换跳不 `attempt++`（`:136-151`）、耗尽即抛 `NetException`（`:200-215`）均**完好**。`MirrorSelector.mirrorFor` 无候选返回 `null`（`net_mirror.dart:130-145`），`advanceHop` 回落直连不抛异常 ✓。

**修法**：`retryAfter` 分支也套 ±jitter（比例减半或 configurable）；补 asctime 解析；`net_transport.dart:148` 改用 `_sleep(wait)`。

### F-11 · P2 · DNS 缓存不按 TTL、并发无 in-flight 去重、竞速失败信息丢失

`net_dns.dart:952` 固定 `policy.cacheTtl`；`net_dns.dart:1040-1065` `_race` 对同一 host 的并发 `resolve` 各自发查询（无 single-flight），且全部失败时 `DnsException('并发解析全部失败：$lastError')` 只带最后一个错误（顺序路径 `net_dns.dart:980-990` 反而汇总了 `failures.join('；')`）。

**修法**：`DnsService` 维护 `Map<String, Future<...>> _inFlight`；`_race` 汇总所有错误。

### F-12 · P2 · 仓库图片查看器在私有仓库必然 404（无认证头）

`lib/surface/pages/repo_page.dart:2080-2088` `_rawUrlOf` 返回 `https://raw.githubusercontent.com/...`；`repo_page.dart:2351-2362` `_buildViewer` 直接 `Image.network(url)` **不带 headers**。私有仓库 raw 匿名 404（`docs/NETWORK.md` §3.2），且该路径未走 `planRepoFileDownload` 的 API 取字节分支。注意：B7-B-01 的 README 私有图片路径（`repo_page.dart:2140-2152` 返回 `base:null, proxy:null, headers:null` 退回 API 取字节）与预览页（`file_preview_page.dart:120-126` 私有只返回官方 raw 直连）**已修复且仍完好**，零交互把 PAT 发给第三方的路径不存在。

**修法**：`_buildViewer` 对 `widget.repoPrivate` 改走 `_readImageBytes` → `Image.memory`，或携带 `downloadAuthHeaders()`（目标为官方域名，不触发 TOKEN-EXIT-01）。

### F-13 · P2 · 自定义 DNS 服务器 IP 未校验，可直接填成元数据地址

`lib/base/net/net_bridge.dart:70-84` 任意 `customIp` 字符串构造 `DnsServer`；`net_dns.dart:445-450` 的 `ogLNormalizeDnsAddress` 只判「是否 IP 字面量」，**不判私网/回环**；`net_dns_platform_io.dart:44-70` `udpExchange` 会向该 IP:53 发包。

**修法**：复用 `ogLIsSafeIpv4` / IPv6 等价规则在 `applyDnsSelection` 处拒绝并回显「地址不合法」。

---

## 二、推测 / 需运行时验证（不作为确证结论）

- **S-01（P1 待验证）**：`background_downloader` 当前锁定版本对 302 跨主机是否原样转发 `Authorization`。F-08 的仓库侧事实确证（带真实 PAT 入队 + 首跳白名单放行），库侧行为依赖 `pubspec.lock` 版本与其平台实现；建议在 CI 用本地 `HttpServer` 模拟 `api.github.com → 第三方` 302 实测。若转发属实，F-08 升级为 P0。
- **S-02（P2）**：`io_net_transport.dart:64-105` 的重定向白名单明确「域名形式的目标由 TLS 证书校验兜底」，未解析域名指向私网的情况（DNS rebinding）。在无 pinning 的场景下存在理论 SSRF 窗口。
- **S-03（P2）**：`io_net_transport.dart:466-470` 的自检 host 取自 `request.url`，该 URL 可能已被 `ResilientTransport` 改写成镜像/加速通道 host；自检会向第三方 host 发 `/zen`、`/user`（令牌是 `Bearer selftest-fake`，**不会泄真实 PAT**），但会产生计划外第三方流量。
- **S-04（无回归）**：`NetException.retryAfter` 在 `io_net_transport.dart` 的异常翻译分支未见填充，`net_transport.dart:144/156` 的 `error.retryAfter` 可能恒为 `null`；响应路径（`headers['retry-after']`）已覆盖，需确认是否影响 429 异常场景。

---

## 三、批 1 八组 P0/P1 回归核对（代码仍成立）

| # | 批 1 修复项 | 代码位置（仍成立） | 结论 |
|---|---|---|---|
| 1 | `bodyOverride` 无默认值致带凭证请求首跳丢 body | `io_net_transport.dart:36-37`（`_kUnset` 哨兵）、`:316/:325`（首跳传默认哨兵）、`:428-436`（`identical` 判别） | ✅ |
| 2 | 302/303 不再无条件降 GET | `io_net_transport.dart:362-364`（`status==302||303 && request.method==NetMethod.post`）、`:387`（307/308 保持 verb 与 body） | ✅ |
| 3 | 超时契约（`NetRequest.timeout` 不再是死字段） | `io_net_transport.dart:241-255`（`request.timeout` 用于 body 读取）、`:318/:325`；`net_contract_test.dart:40-47` | ✅ |
| 4 | Retry-After HTTP-date | `kernel/contract/net_types.dart:216-235`（IMF-fixdate）、`:264-290`（RFC 850）；`net_retry.dart:71-74` | ✅（asctime 缺失见 F-10） |
| 5 | DoH 拒绝 https→http 降级 | `io_net_transport.dart:520-531`（`next.scheme != 'https'` 即抛）；`net_dns.dart:70-83`（端点只认 https） | ✅（跨主机缺口见 F-06） |
| 6 | 凭证头集合 6 种 | `io_net_transport.dart:54-60`（authorization / proxy-authorization / cookie / x-auth-token / api-key / x-api-key）、`:395-403` | ✅ |
| 7 | 重定向目标白名单（跨主机不跟随、拒降级/私网/元数据） | `io_net_transport.dart:64-105`、`:330-356`（`_ogLIsSafeRedirectTarget` + `sameOrigin` 双闸） | ✅（域名型目标见 S-02） |
| 8 | 206 不进缓存 | `lib/domain/gh/gh_client.dart:655-659`（`response.isSuccess && statusCode != 206`）、`lib/domain/gh/gh_api.dart:818`（206 强制回读远端） | ✅ |

附加核对：TOKEN-EXIT-01 门禁（`lib/surface/app/token_exit_warning.dart:41-115`，`*.github.com` + 3 个官方对象域白名单）与 B7-B-01（`repo_page.dart:2140-2152`、`file_preview_page.dart:120-126`）仍完好；`net_mirror.dart:159-165` `defaultMirrorChannels` 仍为空、无内置代理；`ogLAccelCandidates` 仍至多一项、无静默降级；`NetSelfTestImpl` 使用假令牌（`:80`）。

---

## 四、总体结论

**DNS/网络功能不健全**：DoH 实现在协议层只覆盖 A 记录、无 TTL/CNAME/DNS64，明文 UDP 分支连应答 owner 与结果 IP 都不校验；自定义 DNS 的两级回退（DoH→明文、自定义→系统）在界面上完全不可见，直接违反「绝不静默降级」的发布底线；网络自检既未覆盖三路、其结果也从未被生产调用。

**最大剩余风险**：F-01（自定义 DNS 结果未过滤私网/元数据 → 带 PAT 的请求被导向内网/云元数据端点）与 F-08/DBG-04（presign 失败回退把真实 PAT 交给第三方下载库的跨主机 302）构成的两条凭证/SSRF 链路；其次是 F-04 的静默降级让用户对「当前到底用没用 DoH」完全失去判断。

**是否建议立即出 12.6.1**：**建议立即出**。至少需带齐 F-01、F-03、F-04、F-06、F-08 五项修复（P0/P1），并在 CI 补上「UDP 应答投毒→私网地址被拒」「DoH 回落如实可见」「presign 失败不得带凭证入队」三组离线回归；F-02/F-05 可同版本或紧随的 12.6.2 完成。若 12.6.1 只能出一个补丁，优先 F-01 + F-08。
