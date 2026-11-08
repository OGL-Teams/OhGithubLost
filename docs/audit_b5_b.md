# 审计报告 · 第5批 视角B：安全与数据（认证/会话/权限链路）

> 项目：OhGithubLost v12.0.0 LTS · 只审不改 · 依据 docs/QUALITY_STANDARD.md / AGENTS.md / docs/NETWORK.md
> 审计日期：本批静态审计（未连真机，运行时项标「待议」）。

---

## 发现清单

### B5-B-01 OAuth Device Flow 绕过统一网络栈（io_net_transport 守卫不生效）
- **文件:行号**：`lib/domain/gh/gh_oauth_io.dart:24-52`（startDeviceFlow）、`:65-95`（pollDeviceFlow）
- **问题一句话**：OAuth 两跳直接 `HttpClient()` 裸发，不经 `ResilientTransport → IoNetTransport`，重定向守卫、私网/元数据 SSRF 防护（原则 44）、敏感头管理（原则 40）在这条链路上全部缺席。
- **用户可见后果**：若系统/代理环境把 `github.com` 解析到恶意主机，device_code 换取与 token 轮询无任何防线；与 AGENTS.md「所有请求统一走手动重定向守卫」的宣称不一致。
- **等级**：P1
- **原则**：3（例外须显式登记）、40、44
- **确证**：是。代码证据：两处 `final HttpClient client = HttpClient();` + `client.postUrl(...)`，全程无 NetTransport/守卫调用；gh_oauth_io.dart 仅 import gh_client.dart 与日志，未 import base/net。

### B5-B-02 登录中断会遗留孤儿 pending 令牌，永不清扫
- **文件:行号**：`lib/surface/pages/login_page.dart:158-167`（`saveAccount(id: 'pending-…', token)` + `switchTo`）；回滚仅在同函数 catch 内 `login_page.dart:222-226`
- **问题一句话**：验证流程先把**真实令牌**以 `pending-<毫秒时间戳>` 为 id 写入保险库，若验证途中进程被杀/断电（catch 不会执行），该令牌永久滞留保险库——`GhAuthService.refreshState()`、`accounts()` 均不清理 `pending-` 前缀的孤儿密文（gh_auth.dart:208-228、:113-137 无对应逻辑）。
- **用户可见后果**：被放弃登录的凭据长期留存于系统密钥库；设备易手/备份泄露时攻击面扩大；元数据 KV 侧因 `accounts()` 枚举的是 `ogl.gh.account.*`，这些孤儿**完全不可见**，用户无任何途径发现或删除。
- **等级**：P1
- **原则**：13（半成品必须留痕并能被重启发现）、39
- **确证**：是（静态确证；泄漏是否实际发生依赖中断时机——待议）。

### B5-B-03 `downloadAuthHeaders` 出错时静默返回空表（认证头静默降级）
- **文件:行号**：`lib/surface/surface_bridge.dart:331-343`（`catch (_) { return const <String, String>{}; }`）
- **问题一句话**：保险库读取抛异常时吞掉并返回空认证头，下载将以匿名身份继续，私有资源得到 404，用户误以为「文件不存在」而非「读不出令牌」。
- **用户可见后果**：私有仓库下载失败原因被掩盖；凭据未泄漏但违反「不静默降级」；另注意空表路径也使 TOKEN-EXIT-01 弹窗自然跳过——行为本身安全（无令牌外发），但失败不可见。
- **等级**：P2
- **原则**：15、16
- **确证**：是。

### B5-B-04 OAuth 错误信息把原始响应体透传到 UI 与异常字符串
- **文件:行号**：`lib/domain/gh/gh_oauth_io.dart:47`（`StateError('…：${decoded['error'] ?? body}')`）、`:101`（`GhAuthException('授权失败：${error ?? body}')`）；`lib/surface/pages/login_page.dart:229-234`、`:445-452` 将其原样渲染到登录页错误卡。
- **问题一句话**：GitHub 非 JSON 响应/代理拦截页整段 body 进入异常消息与 UI；当前响应不含令牌，但任何中间层（用户自配代理）注入的响应体会被全量展示，且违反「错误面向用户、堆栈留给日志」（原则 38）。
- **用户可见后果**：无直接凭证泄漏（确证：error 分支响应体不含 access_token/device_code），但存在被中间人页面撑爆 UI/误导用户的风险。
- **等级**：P2
- **原则**：38、20
- **确证**：是。

### B5-B-05 scope `repo` 权限偏大（读写一把抓）
- **文件:行号**：`lib/domain/gh/gh_oauth_io.dart:37`（`scope=repo read:user`）；`lib/domain/gh/gh_oauth.dart:40` 宣称「最小化」
- **问题一句话**：`repo` 同时授予全部私有仓的读写与组织仓库访问，而纯浏览用户只需要读取；经典 OAuth App 无细粒度 scope 是客观限制，但文档称「最小化」名不副实，且 UI 无任何「该令牌可写你全部仓库」的告知。
- **用户可见后果**：授权粒度超出多数场景需要；令牌泄漏时影响面=全部私有仓读写。
- **等级**：P2（受 GitHub OAuth App 机制约束，属知情人决策）
- **原则**：39（凭证最小暴露，外推）、57（文档与事实一致）
- **确证**：是（代码）；影响评估待议。

### B5-B-06 轮询 `slow_down` 后 deadline 不顺延（次要）
- **文件:行号**：`lib/domain/gh/gh_oauth_io.dart:73-99`
- **问题一句话**：`deadline` 固定 15 分钟，`slow_down` 只加间隔不加截止时间，网络抖动累积后可能在 GitHub 侧码未过期时本地先超时。
- **用户可见后果**：偶发「等待授权超时，请重试」误报；非安全问题。
- **等级**：P2
- **原则**：21（降级路径要有准确触发条件）
- **确证**：是（静态）；复现需弱网，待议。

### B5-B-07 会话 `_account` 与 UI 缓存在登出/失效路径上的刷新依赖人工调用
- **文件:行号**：`lib/domain/ix/ix_session.dart:223-241`（`refreshAccount`，含切号清 context 的正确实现）；唯一调用点 `lib/surface/pages/profile_page.dart:97`
- **问题一句话**：`GhAuthService.markExpired`/`markSignedOut` 只通知壳层（client_shell.dart:86-135 回登录门），`IxSession._account` 不随之失效；IndexedStack 懒挂载页（client_shell.dart:280-293）在 expired 短暂窗口仍持有 A 账号数据，仅 Dashboard/Discover 以 `ValueKey('…-$accountId')` 重建，Profile/Settings 未带 key。
- **用户可见后果**：401 后壳立即切登录门，但切回/重登瞬间可能闪现上一账号的缓存行；无跨账号数据写入路径（确证： GhClient 每请求重取 activeToken，gh_client.dart:602），故仅为展示残留而非权限泄漏。
- **等级**：P2
- **原则**：22（过期结果须被丢弃）、28
- **确证**：是（调用点全量 grep）；实际闪现待议。

### B5-B-08 `removeAll` 循环遇单个失败即中断（次要）
- **文件:行号**：`lib/domain/gh/gh_auth.dart:397-405`
- **问题一句话**：`removeAll` 顺序 await `removeAccount`，某个账号的 `deleteSecret` 抛出则后续账号与其令牌均不删，且无汇总留痕。
- **用户可见后果**：「退出全部」后仍有残留令牌在保险库，界面上账号已不可见（元数据也停在中途），与 B5-B-02 同类的不可见残留。
- **等级**：P2
- **原则**：15、16
- **确证**：是（静态）；deleteSecret 实际抛错条件依赖平台密钥库，待议。

---

## 重点项核验结论（无问题侧，留证）

| 关注点 | 结论 | 证据 |
|---|---|---|
| 令牌持久层落点 | 令牌只进 `SecureDiskVault`（Android Keystore/DPAPI/libsecret），**无任何降级到非加密存储的分支**；写失败上抛，登录如实失败 | platform_io_impl.dart:460-480；gh_auth.dart:168-170；PlatformStorage.open 无 fallback vault |
| 元数据/密文分离 | `GhAccount.toJson` 不含令牌，KV 只存登录名/头像/scopes；测试锁定 `store.snapshot` 不含明文 | gh_auth.dart:128-146；gh_auth_service_test.dart:106-110 |
| toString/诊断脱敏 | `GhToken.toString()`=masked（gh_auth.dart:76）、`GhAccount.toString()`=login（:154）、登录日志只记 `token.masked`（:176-181）、4/4 回读日志用 masked（login_page.dart:195-201）——全链一致，无明文落日志点 | 已确证 |
| 令牌删除顺序 | removeAccount **先删令牌后删元数据**，注释阐明理由；删 active 账号后逐个尝试 fallback 切号并正确处理失败（曾修的 bug 有自我勘误注释） | gh_auth.dart:355-394 |
| 多账号隔离 | 令牌键=`gh.token.user-<gid>` 按账号隔离；`switchTo` 拒切无令牌账号（防假登录）；切号时 IxSession 清 context 防跨账号仓库名残留 | gh_auth.dart:290-310；ix_session.dart:227-240 |
| vault 写失败降级 | 无降级：saveAccount 第一步写 vault，失败即整链失败（login_page 捕获并回滚+留痕），不存在落普通 KV 的路径 | gh_auth.dart:167-170、login_page.dart:222-241 |
| OAuth device_code/user_code | device_code 只在请求体出现、不进日志（错误路径仅记 `$error`）；user_code 按设计展示于 UI（SelectableText，Device Flow 标准做法，码本身低敏且有 15min 时限） | gh_oauth_io.dart:84-95；login_page.dart:400-425 |
| 权限探针误授权 | 反向安全：探针异常→`_storageOk`=false→needsUserAction；权限状态读取异常→needsUserAction；`isRestricted`→unsupported。**所有 catch 都朝「更不授权」方向失败**，无误授权路径 | permissions.dart:145-163、:198-206 |
| 登录页令牌 UI | `TextField(obscureText: _obscure)` 默认打码，显隐按钮带 tooltip；令牌不进 SelectableText/剪贴板 | login_page.dart:315-345 |
| 令牌出设备 | TOKEN-EXIT-01 三重不可关闭 + 决策留痕 + GitHub 官方域白名单精确（github.com 整域 + 3 个官方对象子域，无泛解析放行） | token_exit_warning.dart:37-46、:63-96 |
| 401 全局出口 | gh_client.dart:761 唯一出口 `markExpired` → 壳回登录门；令牌本身不清除（保留供重登后无感续用），符合「expired≠删除」语义 | gh_client.dart:757-766 |

## 覆盖文件清单（全部完整读）

裁决依据：docs/QUALITY_STANDARD.md（93 行全文）、AGENTS.md（95 行全文）、docs/NETWORK.md（154 行全文）。
代码：lib/domain/gh/gh_auth.dart(406)、gh_oauth_io.dart(113)、gh_oauth.dart(58)、lib/domain/ix/ix_session.dart(355)、lib/surface/app/permissions.dart(461)、token_exit_warning.dart(170)、client_shell.dart(487)、lib/surface/pages/login_page.dart(461)、lib/base/disk/platform_io_impl.dart(571)、lib/kernel/contract/disk_store.dart(191)、test/domain/gh_auth_service_test.dart(127)。
辅助 grep 取证：domain_bridge.dart、surface_bridge.dart、gh_client.dart（tokenProvider/401 出口/downloadAuthHeaders）、profile_page.dart、settings_page.dart 调用点。

## 整体评价

认证链路的**核心设计是扎实的**：令牌持久层只有一条加密路径且无降级分支、脱敏纪律贯穿 toString/日志/UI、删除顺序正确、多账号键隔离与切号防呆到位、权限网关所有异常都朝「拒绝」方向失败、令牌出设备有类型化门禁与留痕——三条安全铁律在代码层面兑现度高，测试也对脱敏与状态机做了锁定。

主要短板集中在**边界与残留**：OAuth 两跳游离于统一网络栈之外（B5-B-01，唯一 P1 级架构性例外且未登记）、登录中断的孤儿 pending 令牌无清扫机制（B5-B-02）、以及若干「失败吞掉后变成另一种静默」的小口子（B5-B-03/08）。建议优先补：① 启动时清扫 `pending-` 孤儿密钥（含 vault 侧枚举能力）；② OAuth 流程接入 ResilientTransport 或在例外清单显式登记；③ removeAll/downloadAuthHeaders 的失败留痕。scope 问题受平台机制约束，建议至少在授权 UI 如实告知影响面。
