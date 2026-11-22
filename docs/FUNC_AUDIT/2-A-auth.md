# 功能审计 2-A · 认证登录链路

> 更新时间：2026-11-23 06:45:18 · 版本 v15.0.0 · 批次 2-A（认证登录）
> 只读审计，未改动任何代码。证据均 file:line 可 rg 复现。

## 审计范围
- lib/domain/gh/gh_auth.dart（423 行）
- lib/domain/gh/gh_oauth.dart / gh_oauth_io.dart / gh_oauth_webflow_io.dart / gh_oauth_stub.dart / gh_oauth_types.dart
- lib/surface/pages/login_page.dart（536 行）
- lib/surface/settings.dart 令牌相关部分（实际无令牌逻辑，注销收口在 lib/surface/surface_bridge.dart:198 forgetAccount，一并核对）

## 问题清单

### P0

**P0-1 · Web Flow 回调 state 无加密随机性，CSRF 防护名存实亡**
- 症状：`lib/domain/gh/gh_oauth_webflow_io.dart:29-31` —— `state = 'ogl-${DateTime.now().millisecondsSinceEpoch}-$port'`，完全可预测（时间戳 + 本机端口）。任何本机进程/恶意页面可推算或枚举出 state，向 `http://127.0.0.1:<port>/callback?code=<攻击者code>&state=<推算值>` 发起伪造回调（localhost 上任意程序/页面均可发 GET），把**攻击者自己的 code**注入正在等待的授权流程，受害者最终登录的是攻击者的账号（code/state 均有效，校验全通过）。
- 根因：用「可观测值拼接」替代随机 nonce；state 的存在意义（绑定发起方）被架空。校验逻辑本身（webflow_io.dart:82-94 的 `gotState != state` 分支、err 优先分支、缺 code 分支）严密，但输入可预测。
- 修复指令：在 gh_oauth_webflow_io.dart 中改用 `Random.secure()` 生成 ≥128bit 随机 state（如 22 字符 base64Url，dart:math 已在本仓库 platform_io_impl.dart:190 有 `Random.secure()` 先例）；不再把 port/时间戳编入 state。

### P1

**P1-1 · 登录成功后未采集 scopes，`canWrite` 恒真 → 无 repo 权限账号误判可写**
- 症状：login_page.dart `_finishLogin` 转正时 `GhAccount(id:'user-${me.id}', ...)` 不带 scopes（login_page.dart 约 300 行）；gh_api.dart:127 `currentUser()` 只解析 body，丢弃 `x-oauth-scopes` 响应头。GhAccount.canWrite（gh_auth.dart:112-113）`scopes.isEmpty || contains('repo')` → 空 scopes 恒 true。
- 根因：验证链没有从 `GET /user` 的 `X-OAuth-Scopes` 头（Web Flow/Device Flow 令牌）或 PAT 创建时已知 scopes 回填账号元数据。
- 修复指令：gh_api.dart `currentUser()` 返回 scopes（从响应头读，注意 1-A 域的 GhResponse 需暴露 headers；若响应头不可得则标注「scope 未知」，并把 gh_auth.dart canWrite 的空-scope 短路改为「未知 → 不判定可写」，写操作以 403 兜底提示）。

**P1-2 · 登录中断（杀进程）残留 pending 账号 + 其令牌，重启后假登录**
- 症状：login_page.dart `_finishLogin` 第 1 步即 `saveAccount(pending-…)` 并 `switchTo(pendingId)`；若进程在验证完成前被杀（无任何清理机会），磁盘上留下 activeKey→pending 账号 + 保险库里的临时令牌。重启 `refreshState()`（gh_auth.dart:191-200）看到 metadata+token 均在 → signedIn，且 accounts() 枚举出 login 为占位符的 pending 账号；全仓库 rg 'pending-' 仅 login_page.dart 一处，无启动清理。
- 根因：临时账号无生命周期标记，启动时无孤儿清理。
- 修复指令：① GhAccount 增加 `pending` 标记（或约定 id 前缀）持久化；② 启动装配时对 pending 账号执行 `removeAccount`（gh_auth 已保证先删令牌再删元数据，不会残留）；③ 或改为验证成功后才落库（先用内存暂存令牌），把回滚从「删已落库账号」简化为「什么都不留」。

**P1-3 · 轮询一次瞬时网络错误即终止整个 Device Flow**
- 症状：gh_oauth_io.dart:105-110 —— 轮询循环里非 GhAuthException 的异常（`TimeoutException`、`SocketException`、JSON 解析失败）直接 `throw`，15 分钟窗口内一次网络抖动就宣告登录失败，`authorization_pending` 的容忍性没有延伸到网络层。
- 根因：catch 块把「可重试的传输错误」与「终态错误」同等处理。
- 修复指令：gh_oauth_io.dart 轮询循环内对 `TimeoutException/SocketException/FormatException` 计数（如连续 3 次或累计 5 次才失败），否则 `continue` 等下一轮；保留 deadline 约束。

### P2

**P2-1 · Web Flow「错误即当用户取消」判定过宽**
- 症状：webflow_io.dart:76 把 GitHub 回调的任意 `error` 参数映射为 statusCode 401；login_page.dart（`userCancelled = error.statusCode == 401`）据此回落 Device Flow。`redirect_uri_mismatch`、`application_suspended` 等配置类错误会被误当成「用户取消」而转入抄码流程，掩盖真实配置故障。同理 openExternalLink 失败抛的 401 GhAuthException 也被归为取消（属可接受但同路径混淆）。
- 修复指令：err 分支按 error 名细分：`access_denied` → 401（取消/拒绝，可回落）；其余 → 400 直接报错给用户，不回落。

**P2-2 · Device Flow UI 状态只区分 granted/等待，expired/denied/failed 不展示**
- 症状：login_page.dart 末尾卡片文案 `_oauthStatus == granted ? oauthGranted : oauthWaiting`（约 520 行）；`expired/denied/failed` 都显示「等待授权」，与 `_oauthError` 文字并存但语义含糊（尤其 P1-3 修复引入重试后 failed ≠ 终止时更混乱）。
- 修复指令：为每个 GhOAuthStatus 配 i18n 文案并全量映射展示。

**P2-3 · activeKey 指向已删账号时状态误报「expired」**
- 症状：gh_auth.dart refreshState:191-200 —— 若 activeKey 存在但元数据已被外部手段清掉（非 removeAccount 路径，如手动清 KV），`hasToken=false` → expired（reason 令牌缺失）；语义上应为 signedOut。gh_auth.dart:200-206 的 `hasToken ? signedIn : expired` 三元把「账号不存在」与「令牌丢失」混为一谈。
- 修复指令：refreshState 先判 `activeAccount() == null` → signedOut；仅当账号在而令牌缺才 expired。

**P2-4 · slow_down 增量按规范应读响应 `interval` 字段**
- 症状：gh_oauth_io.dart:91-93 固定 +5 秒。RFC 8628 / GitHub 文档要求 slow_down 响应携带新的 interval 值；固定 5s 在服务端提高要求时会持续 5 秒差额直至失败。
- 修复指令：slow_down 分支优先读 `decoded['interval']` 覆盖本地 interval，缺省再 +5s。

## 已检查清单（本席逐项）
- gh_auth.dart：GhAuthState 全枚举、GhToken.looksValid/masked/toString、GhAccount.fromJson/canWrite/toJson、_setState 短路（B7-A-01）、accounts 损坏隔离（B5-A-14）、saveAccount 写序（令牌先行）、refreshState、markExpired 幂等、switchTo 令牌前置校验、removeAccount 删序与自动切换、removeAll —— 除 P1-1/P2-3 外通过。
- gh_oauth.dart：kOgLGitHubClientId 注入与空校验、条件导入 facade、Web Flow onStatus 转发 —— 通过。
- gh_oauth_io.dart：startDeviceFlow 参数/interval 默认 5、poll 状态机（pending/slow_down/expired_token/access_denied/超时 408）—— P1-3/P2-4。
- gh_oauth_webflow_io.dart：端口随机 bind(0)、state 生成/校验时机/err/code/state 三分支、favicon 404、timeout 10min、finally sub.cancel+server.close(force)、_exchangeToken 无 secret（loopback 规范）、HttpClient 关闭 —— P0-1/P2-1，其余通过。
- gh_oauth_stub.dart：Web 端三函数 UnsupportedError —— 通过。
- gh_oauth_types.dart：GhOAuthCode/GhOAuthStatus —— 通过。
- login_page.dart：PAT 空值/形态校验、_busy 防重入（按钮+Enter 同闸 LG-05）、_finishLogin 四步（暂存→验证→转正→保险库回读门）、pending 回滚顺序（先恢复激活再删）、失败清理 —— P1-2，其余通过。
- gh_client.dart 401 出口（755-775）：carriedToken 判据保持 B5-A-09 教训（游客 401 不 markExpired）——通过。
- settings.dart：全文扫描确认无令牌/账号逻辑；注销实际收口 surface_bridge.dart forgetAccount(198)（先删账号+令牌再清全部缓存）——通过。
- surface_bridge.dart downloadAuthHeaders(336)：令牌仅入 authorization 头、异常吞掉返回空表 —— 通过。
- 保险库合约：kernel/contract/disk_store.dart DiskVault 三方法；SecureDiskVault（platform_io_impl.dart:444-460，flutter_secure_storage + `ogl.vault.` 前缀）—— 通过（实现走平台 Keystore/DPAPI/libsecret）。

## 本席结论
认证链路整体设计质量高：令牌进保险库、写序（令牌先行）、删除序（先令牌后元数据）、401 唯一出口与游客区分（B5-A-09 保持）、登录四步验证含保险库回读门、pending 回滚顺序均正确。核心缺口是 **Web Flow state 可预测（P0，安全）**、**scopes 从未采集导致 canWrite 恒真（P1，功能）**、**中断残留 pending 假登录（P1，一致性）**。共 7 条：P0×1、P1×3、P2×4。修复全部限定在上述文件内，互不耦合，可独立实施。
