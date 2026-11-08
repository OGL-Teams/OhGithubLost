# 第1批 · 交叉结论（网络传输层）

> 基线 `main` @ `831f208`（含 B1-A-01/B1-A-04 两个 P0 修复）。
> 三视角原始记录：`docs/audit_b1_a.md`（A 实现正确性 37 条）、
> `docs/audit_b1_b.md`（B 安全与数据 15 条）、`docs/audit_b1_c.md`（C 契约与规范 16 条）。
> 交叉规则：**三方/两方命中 = 确证或复核**；**单方命中 = 主会话亲自复读**；
> 代理自标「待议/不确证」的不进确证清单。
> 本批 A/B/C 均只审不改，`lib/` 零并发写冲突。

---

## 一、三方命中（最高置信，优先修）

| 主题 | A | B | C | 交叉结论 |
|---|---|---|---|---|
| **206 分段/截断响应被当完整实体** | A-01/… 关联写回执 | **B-01 P1** | C-08（零测试） | ✅ 确证。传输层不校验 Content-Range/Content-Length；`putContent` 已有回读兜底（P0 已修），但**GET 206 仍会被 `_readCache.put` 缓存 30–60s**。→ 需在 `GhClient.send` 缓存回填前拒收 206，并补离线测试 |
| **`NetRequest.timeout` 是死契约** | **A-08 P1** | **B-12 P2** | **C-09 P1** | ✅ 确证。构造器 15s/60s 覆盖调用方 30s；三方独立命中。→ 让 `IoNetTransport.send` 按 `request.timeout` 设 receiveTimeout |
| **重试/重定向/Retry-After 语义** | A-03/06/20（HTTP-date 必失败、换跳跳退避、8s 截断） | B-13（parseRetryAfterHeader 吞错） | C-09（自称唯一实现却被 gh_client 复制一份） | ✅ 确证且互相印证：`parseRetryAfterHeader` 用 `DateTime.parse` 解析 HTTP-date **必失败** → Retry-After 分支永不生效。→ 统一实现 + HTTP-date 解析 + 离线断言 |
| **`range_download_io` 静默失败** | A-15/16（Future.wait 首错删分片、Content-Range 缺头放行、不 drain） | **B-02 P1** | **C-07 P1**（probe 双重 catch 吞异常） | ✅ 确证，三视角各自从不同入口命中同一片「实现层」。→ 等其它分片完成再清理、强制 Content-Range、probe 失败留痕 |
| **无凭证路径重定向无白名单** | A-23（SSRF/降级） | B-04（http/私网/元数据） | C-06（平台配对失守） | ✅ 确证方向一致：dart:io `followRedirects=true` 对无凭证请求完全不设防。→ 统一走守卫路径并加 scheme/host 校验 |
| **文档与代码脱节** | — | B-15（注释仍称「直连兜底」） | **C-01/02/03/13**（NETWORK.md 虚构主机冷却、4类vs9类、漏新API、CORS 结论不可复现） | ✅ 确证（C 单方 + B 佐证）：文档诚实度是结构性问题。→ 本批统一修订 docs/NETWORK.md + 两处误导注释 |

## 二、两方命中（复核后修）

| 主题 | 命中 | 结论 |
|---|---|---|
| **凭证守卫只认 `authorization` 一个头名** | A-17 P0 + B-03 P1 | ⚠️ 复核为 **P1（契约级，非已触发 P0）**：B 实证当前生产调用点只用小写 `authorization`，跨主机 `Authorization` 守卫有效；但 `cookie`/`x-auth-token`/`api-key` 走 `followRedirects=true` 会外泄。→ 扩展凭证头集合，并让所有请求走守卫 |
| **DoH 端点 302 降级 http** | A-22 P0 + B-09 P1 | ⚠️ 复核为 **P1**：`ogLIsUsableDohEndpoint` 初始只认 https 确证，但 `IoDnsHttpClient.get` 未关自动重定向 → 加密 DoH 可被引到明文。→ 关自动重定向 + 校验最终协议 |
| **`fromMirrorId` 永为 null / 可解释性** | A-09 + B-14 + C-09 | ✅ 确证（三方其实都命中，归此档因影响面 P2）：换跳不回填响应、日志恒不显示「经过代理」。→ `advanceHop` 时把 mirror id 带入 `NetResponse` |
| **`on Object catch` 把已翻译异常再包成 unknown** | A-18 + B-11 | ✅ 确证：明确 DNS/TLS/解码错误被误报为「未知网络错误」并被当瞬时故障重试。→ catch 里先判 `error is NetException` 原样 rethrow |
| **DNS 事务 ID 可预测 / 缓存投毒面** | A-10/12/13 + B-09/10 | ✅ 确证：`UdpDnsResolver` 每次新建、TXID 从同一静态起点单调；`_ipv4` 不查 ≤255、不查私网；改自定义 IP 不清缓存。→ TXID 每次随机化、IP 合法性校验、服务器变更清缓存 |
| **自动自检报告陈旧/假令牌** | A-29/32 + B-13 | ✅ 确证（P2）：清 DNS 缓存后取 30s 缓存报告；向 `/user` 发 `Bearer selftest-fake`。→ 先取报告再清缓存；假令牌探针去掉或标注 |
| **`autoUncompress` 头与统计口径** | A-28 + B-11 | ✅ 确证（P2）：gzip 已解压却原样返回 `content-encoding`/压缩 `content-length`；bodyLength 是码元数却标 B。→ 去掉压缩相关头、统计按字节 |
| **失败可见性 / 吞错** | A-18 + B-05/13 + C-07 | ✅ 确证：presign 的 `IxPresignResult.error` 从未被消费；安全拒绝被伪装成普通慢路径。→ `resolveDownloadUrl` 读 error 并留痕（此前已加 warning，需升级为「明确原因」） |

## 三、单方命中但主会话已亲自复读确证（P0，已修）

| 编号 | 结论 | 状态 |
|---|---|---|
| **B1-A-01** | `_sendWithGuardedRedirect` 的 `bodyOverride` 无默认值 → 首跳 `null` 被 `_writeBody` 当「显式无体」→ **所有带 Authorization 的 PUT/POST 首跳丢 body**。这是「提交不可用/空内容创建」的最基础根因，比 206 更前置 | ✅ 已修（`831f208`）：补 `= _kUnset` |
| **B1-A-04** | 302/303 无条件降级 GET → 带凭证 PUT/DELETE 遇同源 302 变空 GET，可伪造保存成功 | ✅ 已修（`831f208`）：按 RFC 只对 POST 降级，307/308 保持原方法 |

## 四、单方命中 → 待议（不进本批修复）

- A：D-01~D-08（304 带 Location、PUT 是否真用 302、startConnect 多 IP、`$0` 二次展开、Web 构建实测、八进制/NAT64 URL 语义、AAAA、假令牌计入滥用统计）
- B：签名 URL 有效期不可见、`isForbiddenHost` 归一化不完备、`IxPresign.resolve` 无主机白名单、`file://` 实际行为、`_fetchPart` 无单次超时、`autoUncompress=false` 对 Range 的影响、持久化加速通道校验链
- C：B1-C-10（防线边界，判**不缺陷**）、C-11（`_race` 不取消落败 Future，未复现）、C-14（观测层参数丢弃，架构归属未定）、C-15（30+ 类不带 OgL 前缀，建议改文档而非改类名）、C-16（Flutter SDK import 与 ARCHITECTURE 冲突，分层方向本身达标）

## 五、第一批修复清单（按优先级）

### P0（已修 2 个，其余复核降级）
- ✅ B1-A-01 首跳丢 body
- ✅ B1-A-04 302/303 错降级
- ⚠️ A-17 / A-22 经 B 交叉复核为「契约级 P1 / 未触发 P0」，不作 P0 处理

### P1（建议本批统一修，共 8 组）
1. 206 GET 不进只读缓存 + 补 206 离线测试（C-08 点名零回归）
2. `NetRequest.timeout` 生效（A-08/B-12/C-09 三方）
3. `parseRetryAfterHeader` 修 HTTP-date + 去重复实现 + 换跳不跳退避（A-03/06/20、C-09）
4. `range_download_io`：等齐分片再清理、强制 Content-Range、probe 失败留痕（A-15/16、B-02、C-07）
5. 重定向统一守卫：`hasCredential` 扩为凭证头集合、无凭证路径也手动跟随 + scheme/host 白名单（A-17/23、B-03/04）
6. DoH 客户端关自动重定向（A-22、B-09）
7. `on Object catch` 不重包 NetException；presign error 消费与留痕（A-18、B-05/11/13）
8. 文档诚实度：NETWORK.md 4 处 + 两处「直连兜底」注释（C-01/02/03/13、B-15）

### P2（记录，择期）
- 镜像 id 回填、DNS TXID/缓存、autoUncompress 头、自检报告、bodyLength 口径、层级头注释/契约上提、CI 门禁扩到 `lib/base/net`、C-12 的 export 解析

### 建议同步补的门禁（C-12 根因）
新增一支 `tool/net_contract_audit.py` 扫 `lib/base/net/`：`export` 解析、平台配对、文件头层级、死字段引用、206/重定向测试存在性——否则同类问题会随下个版本重现。

---

## 六、本批整体评价

| 维度 | 评价 |
|---|---|
| 功能铁律 | **良好**（不预置代理、只重试幂等方法、DoH 初始 https、DNS 回退留痕、udpExchange 过期回调守卫） |
| 实现正确性 | **存在 P0**：守卫自身把带凭证写请求 body 吃掉（已修）；重试/分片状态机有 20+ 处边界缺陷 |
| 安全与数据 | **中上**：跨主机 Authorization 守卫有效；但无凭证路径 SSRF、DoH 降级、缓存投毒、加速改写无校验是真实缺口 |
| 契约与规范 | **偏弱**：文档虚构能力、死字段、零回归测试、门禁完全不扫本层 |
| 交叉有效性 | ✅ 三视角对「206 / timeout / Range / 重试 / 重定向 / 文档」六组主题独立命中同一代码，互相印证；两个 P0 由主会话亲自复读坐实 |

**结论**：第 1 批共 68 条原始发现（A37 + B15 + C16），交叉后 **确证 6 组 + 复核 8 组 + 已修 P0 2 个 + 待议 20 项**。
批 2（磁盘一致性层）在上述 P1 修完、CI 全绿后自动启动。
