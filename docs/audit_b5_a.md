# 审计报告 · 第 5 批 · 视角 A：认证 / 会话 / 权限链路实现正确性（B5-A）

> 范围：lib/domain/gh/gh_auth.dart、gh_oauth.dart + _io/_stub/_types、lib/domain/ix/ix_session.dart、
> lib/surface/app/permissions.dart、permission_selftest.dart、client_shell.dart（登录门/权限自检段）、
> lib/surface/pages/login_page.dart、onboarding_page.dart、lib/base/disk/platform_io_impl.dart（SecureDiskVault）、
> test/domain/gh_auth_service_test.dart、test/surface/permissions_test.dart、permission_selftest_test.dart。
> 裁决依据：docs/QUALITY_STANDARD.md、AGENTS.md、docs/CONSISTENCY.md（均已完整读）。
> 只审不改。每条含：文件:行号、一句话问题、用户可见后果、优先级、原则编号、确证状态。

---

## B5-A-01 · client_shell.dart:126-128 — 游客态被 `_check` 的同步段强行保留（_guest 置 false 链条，B3-A-04 同源）
- **问题**：`_check()` 只在 `accountId != null` 时 `_guest = false`；游客点「跳过」后 `_guest = true`，此后任何一次 `_check`（auth 通知、ProfilePage `onAccountsChanged`、登录成功回调）只要 activeAccount 仍为 null 就**不会清掉 `_guest`**，也没有任何入口把 `_guest` 置回 false（`rg` 全 lib/surface 仅 3 处赋值：init 初值 false、_check 置 false、onSkip 置 true）。
- **后果**：用户以游客身份浏览后，若登录流程半途失败（401 → `markExpired` → `_onAuthChanged` → `_check` → accountId 仍 null），登录门**不再出现**，直接落回已解锁的四页壳；此时 `auth.state == expired` 但 UI 呈现"已进入"，各页以无令牌请求 → 二次 401 循环。退出/重新进入登录门的唯一途径是杀进程。
- **P1** · 原则 22（异步结果须校验仍有效）、21（降级路径要有退出条件）。
- **状态**：确证（代码证据如上；`_guest=true` 后无 reset 路径，登录门条件 `client_shell.dart:263-266` 依赖 `!_guest`）。运行时行为复现待实测，标**待议**。

## B5-A-02 · gh_auth.dart:281-290 `refreshState()` — 全 lib/ 无调用点，启动态探测实际未接线
- **问题**：枚举设计里 `unknown` → `signedOut/signedIn/expired` 的迁移靠 `refreshState()`，但 `rg 'refreshState'` 全 lib/ 只命中定义处（gh_auth.dart:282）。启动态实际由 `client_shell._check()` 用 `activeAccount()` 临时判断，auth.state 停留在 `unknown`；`isSignedIn`（唯一被 search_page.dart:197 的 B3-A-04 修复消费）在未登录启动时为 **false**——这是"碰巧正确"（unknown ≠ signedIn）。
- **后果**：任何以 `state == signedIn` 为正判据、或依赖 `stateReason` 的未来消费点都会拿到 `unknown`；`expired` 的 reason「令牌缺失」路径从未在真实启动中触发，启动期"令牌缺失"账号不会被标记，也不会有 OGL-AUTH-101 告警。
- **P1** · 原则 55（死代码零容忍）、17（用类型表达失败，未接线等于失败被吞）。
- **状态**：确证（调用点检索为空；test/domain/gh_auth_service_test.dart 覆盖了该 API 但生产无调用）。

## B5-A-03 · gh_auth.dart:236-242 `saveAccount` — 令牌已落库、元数据未落库时留下"幽灵密钥"，违反自身注释的对称承诺
- **问题**：文件头注释承诺"令牌写失败则不落元数据"，但**反方向**（`_vault.writeSecret` 成功、`_store.write` 失败/中断）会把密文留在保险库里且无任何账号元数据指向它。`accounts()` 枚举靠元数据前缀，永远不会发现该密钥；`removeAll()` 也清不掉（按账号列表遍历）。
- **后果**：孤儿令牌永久滞留系统密钥库（Android Keystore / DPAPI），卸载前无法通过应用内任何路径清除；对"令牌必须显式删除才消失"的安全承诺（文件头第 3 条）构成直接违背。
- **P2**（发生概率低，但性质是安全事故残留）· 原则 13（半成品状态必须留有痕迹并能被重启发现）、39（凭证生命周期）。
- **状态**：确证（saveAccount 两段写之间无 journal/回滚，顺序为先 vault 后 store）。

## B5-A-04 · login_page.dart:185-186 — 转正后 `switchTo('user-…')` 与 `removeAccount(pendingId)` 非原子：中途失败会留下两份登录态
- **问题**：步骤 3「转正」依次执行 `saveAccount(user-…)` → `switchTo(user-…)` → `removeAccount(pendingId)`。若 `removeAccount(pendingId)` 抛出（保险库删除失败等），catch 分支会**再次** `removeAccount(pendingId)`（212 行），此时 pendingId 已不是激活账号、静默成功——但 `user-…` 已存在且是激活账号，catch 仍把 `_error` 设为 verifyFailed、**不调用 onLoggedIn**。结果：壳的 `_check` 会发现 accountId = user-…，用户"已登录"，但登录页仍显示失败。
- **后果**：登录页报错与实际已登录状态自相矛盾；用户重试登录 → `previousActive` 取到 `user-…` → 又存一份 pending。同账号重复登录会产生重复 pending 残骸（由 catch 清理，尚可）。
- **P2** · 原则 42（失败如实报错——这里失败语义与事实不符）、26（写操作要么幂等要么防重）。
- **状态**：确证（代码路径推演；真实触发需 vault 删除失败，标**待议**：需运行时注入验证）。

## B5-A-05 · gh_auth.dart:367-382 `removeAccount` — 删的是**非激活**账号但 switchTo 自动切换时状态通知次序正确；但先删令牌后判断 wasActive 之间存在窗口
- **问题**：`_vault.deleteSecret` 与 `_store.remove` 完成后才读 `activeAccountId()`。单线程 Dart 下无并发写 activeKey 的生产路径，此窗口实际闭合。**但** `wasActive` 分支的自动切换 `switchTo(remaining.first)` 会把 `GhAuthState` 无条件置 `signedIn`（switchTo:331 `_setState(signedIn)`）——若当前壳处于 `_guest = true` 游客态，`_check` 后 accountId 非 null 会清掉游客态，行为合理；反之若 remaining 全部缺令牌，`_setState(signedOut)` 正确。**未发现实际缺陷**，此处记录验证结论。
- **状态**：核验通过（与 gh_auth_service_test.dart 覆盖一致）。

## B5-A-06 · ix_session.dart:288-303 `refreshAccount` — 只在「我的」页 `_refresh()` 调用；登录成功 / 注销路径不经此函数
- **问题**：`refreshAccount()` 是会话账号与 auth 对齐的唯一入口，但调用点全 lib/ 仅 profile_page.dart:97（切号/删除后 `_refresh`）。登录成功走 `widget.onLoggedIn` → client_shell `_check`（**不触发 session.refreshAccount**）；`forgetAccount`（surface_bridge.dart:195-197）也不触发。此时 `IxSession._account` 与 auth 的激活账号**分叉**，且 `context.repo` 不被清空（B 号会话内存里仍挂着 A 的仓库上下文）。
- **后果**：登录新账号（尤其从游客转登录）后，session 上下文（`_contextKey` 持久化的 repo/branch/path）沿用登录前的仓库——刷新仓库页时以 B 的令牌访问 A 留下的 repo 上下文；`DomainBridge.toString`（domain_bridge.dart:105）展示的 account 也错。当前直接消费 session.context 的页面少，故未大面积串号，但这是显性状态分叉而非"碰巧无害"。
- **P1** · 原则 2（层与层之间只经桥通信的一致状态）、9（写前必读——状态机各所有者不同步）。
- **状态**：确证（调用点检索如上）。

## B5-A-07 · ix_session.dart:146-190 `restore()` — 启动恢复的 context 不校验其仓库是否属于当前激活账号
- **问题**：`restore()` 读取持久化 `ogl.ix.context`（含 repo），随后 `_account = await _auth.activeAccount()`，**没有**在 repo 非空时校验账号一致性，也没有清空逻辑（清空只在 `refreshAccount` 的切号分支做）。若上次会话在 A 账号进入过私有仓库后进程被杀（`refreshAccount` 从未跑过），本次启动以 B 账号（或未登录）恢复 A 的 repo/branch/path。
- **后果**：启动后首页/仓库页的隐式上下文指向他人仓库；未登录时以无令牌请求该私有仓库 → 404/401，且 401 会触发 `markExpired` 把从未登录过的用户直接打进 `expired` 态（见 B5-A-09）。
- **P1** · 原则 28（缓存键必须覆盖产生差异的全部维度——账号维度缺失）、20（外部数据不可信）。
- **状态**：确证（代码证据如上；与 refreshAccount 注释自认的"隐性契约"呼应——该注释只覆盖切号路径，漏掉启动路径）。

## B5-A-08 · main.dart:293-315 + permission_selftest.dart:125-137 — 权限自检 fire-and-forget 的异常路径已闭合，但 `describe()` 成功后 `diagnostics.warn/info` 自身抛错无兜底
- **问题**：`main.dart` 的 unawaited 块有 try/catch + 5s timeout，`ogLRunPermissionSelfTest` 对 `describe()` 有 catch → OGL-PERM-000。但 describe 成功后进入 `for` 循环调用 `diagnostics.warn/info`（permission_selftest.dart:139-160）——若诊断中枢的 sink（如通知中心 sink）抛出，该异常会**逃出 for 循环**回到 main 的 catch，表现为"权限自检未完成：…"告警，且 `OgLPermissionSelfTestReport.last` 永不赋值（关于页/设置页读 `last` 拿到上一次或 null）。`stopwatch.stop()` 在 describe 后已调用，但报告构建在循环之后——循环抛错即丢失。
- **后果**：低概率（KernelDiagnostics 内部通常吞），一旦发生：权限自检结果静默半途丢弃，且日志误报为"自检未完成"。文件头承诺"永不抛"，对 describe 兑现、对后半段未兑现。
- **P2** · 原则 16（捕获后须转化为明确结果）、18（捕获范围精确到能处理的异常）。
- **状态**：确证（代码结构；触发依赖 sink 抛错，标**待议**）。

## B5-A-09 · gh_client.dart:759-766 401 全局出口 — 对**无令牌请求**也会 `markExpired`，把 signedOut/guest 用户错误标记为 expired
- **问题**：`_throwIfFailed` 的 401 分支不区分请求是否携带令牌（gh_client.dart:601-603：`token == null` 时不带 authorization 头，但 401 响应仍走同一出口 `markExpired`）。游客/未登录访问任何要求认证的端点（除 search_page.dart:197 已修的 notifications 外，其余未登录入口如直接打开私有仓库链接、profile 端点）都会把状态打成 `expired`。
- **后果**：壳的登录门条件（client_shell.dart:264）含 `state == expired`，本应显示"未登录"的场景显示为"令牌失效"文案；`stateReason` 污染为"令牌无效或已过期"，用户被告知令牌有问题而实际上根本没有令牌。
- **P1** · 原则 38（错误信息面向用户，如实）、42（失败如实报错）。
- **状态**：确证（代码路径：601 行 token 可为 null → 612 行后 401 → 761 行无条件 markExpired）。

## B5-A-10 · gh_oauth_io.dart:57-110 Device Flow 轮询 — 终止条件完备，但 deadline 用 `DateTime.now()` 且轮询前先 sleep：单次网络挂起可越过 15 分钟上限
- **问题**：循环终止条件 `DateTime.now().isBefore(deadline)`，每次请求 15s timeout——最坏情况 deadline 判定后的最后一轮仍可再花 ~15s+interval，可接受。**但** `expired_token` / `access_denied` / 未知 error 的 `GhAuthException` 均正确终止；`slow_down` 递增 interval 无上限（原则 29：所有资源有上限——若 GitHub 持续返回 slow_down，interval 无界增长，`Future.delayed` 最长可挂任意久，仅受外层 deadline 兜底，而 deadline 判定在 sleep 之后——实际上 `delayed(interval)` 的长挂起会推迟 deadline 检查）。综合看行为受限、无实际失控路径。
- **结论**：**核验通过**（终止条件：access_token / expired_token / access_denied / 未知 error / deadline 五类齐备）。唯一残留：`interval` 无上界，依赖 deadline 兜底，记为 P2 观察项 · 原则 29。

## B5-A-11 · gh_oauth_io.dart:66 `jsonDecode(body) as Map<String, dynamic>` — 反序列化可抛，违反"反序列化永不抛异常"（原则 20）
- **问题**：GitHub 网络层偶发返回非 JSON（代理劫持页、HTML 错误页）时，`jsonDecode` 抛 `FormatException` → 落入 `on Object catch` → 转成 `GhAuthException('授权失败：$error')`。**但**该 catch 在轮询循环内对**首次**错误直接 throw（不复试、不给 pending 机会）——网络抖动一次即整个 Device Flow 失败，用户需从头扫码。同文件 startDeviceFlow（41 行）同样裸 as，异常冒泡给调用方显示原始 FormatException 文案。
- **后果**：脆弱失败：一次非 JSON 响应终止整个授权流程，用户重新发起（体验损失，非安全事故）。
- **P2** · 原则 20（反序列化永不抛）、41（只重试幂等方法——poll 是幂等 POST，本可安全重试）。
- **状态**：确证（代码证据）。

## B5-A-12 · platform_io_impl.dart:520-536 `SecureDiskVault` — 无写入回读校验、无平台可用性探测，"写成功"仅指 API 不抛
- **问题**：`writeSecret` 直接透传 `FlutterSecureStorage.write`。Android 上已知故障模式（Keystore 损坏、设备无 Secure Enclave 时部分 ROM 静默丢数据）不会被此层感知；登录页 4/4 的回读自检（login_page.dart:193-203）恰好补上了这一层——**但只覆盖"登录时"**，启动恢复路径（`refreshState`/`_check`）读不到时仅判 `expired`，不会区分"保险库整体损坏"（所有账号全灭）与"单账号令牌失效"，也无对应诊断事件码。
- **后果**：系统升级 / ROM 迁移导致保险库全灭时，用户看到的是 N 个账号各自"令牌缺失"的 expired，没有"密钥库不可用"的根因提示；多账号场景每个账号都要手动重登。
- **P2** · 原则 15（静默降级是最严重的缺陷）、21（降级路径要有观测）。
- **状态**：确证（SecureDiskVault 三个方法均无额外校验/诊断；无任何 OGL-AUTH 事件码在 vault 层产出）。

## B5-A-13 · client_shell.dart:74-79/108 — `_check()` 与 `notifyListeners` 风暴：auth 每次 `_setState` 都触发全量 `activeAccount()` 磁盘读
- **问题**：`_onAuthChanged` → `_check()` → `await auth.activeAccount()`（两次 KV 读）+ setState。`saveAccount` 在"非激活账号"路径也会 `notifyListeners()`（gh_auth.dart:241），登录流程 4 步至少触发 4 次 `_check`，每次都是异步磁盘读 + setState。无并发闸门（无原则 27 要求的并发假设注释），两次 `_check` 交错时后完成者覆盖先完成者——当前写入都是单调的（同一 pending 流程），暂无错序危害。
- **后果**：登录过程中登录门反复重建（`_checked` 已 true 则不闪，但 `_accountId` 从 null→pendingId→userId 的跳变会**更换 DashboardPage/DiscoverPage 的 ValueKey**（220/225 行），两页在登录流程中被整体重建 2 次，浪费但无错误）。
- **P2** · 原则 27（并发假设写进注释）、31（热路径分配）。
- **状态**：确证（时序推演；页面重建可由 ValueKey 变更逻辑直接证明）。

## B5-A-14 · gh_auth.dart:201-206 `accounts()` — 损坏元数据被**静默删除**（catch 内 remove），违反原则 15/16
- **问题**：`jsonDecode` 失败时直接 `await _store.remove(key)`，无日志、无诊断事件、无 notifyListeners。"结构损坏：清掉，避免每次启动都报错"的注释解释了动机，但做法是零痕迹销毁用户账号元数据——该账号的令牌随即成为孤儿（元数据没了，accounts() 不再列出，removeAccount 也无法删除它）。
- **后果**：账号从界面消失但令牌滞留保险库（与 B5-A-03 叠加）；用户困惑"我的账号哪去了"，且无任何日志可排查。
- **P1** · 原则 15（静默降级）、8（数据无价——元数据也是用户数据）、14（删除前落盘意图）。
- **状态**：确证（代码证据如上；对比 IoDiskKv.read 的同类处理同样静默，属系统性模式）。

## B5-A-15 · permissions.dart:160-171 基类 `requestStorage` 与 Android 覆写的循环体在"全候选未授予"时行为不同——基类会**自动跳系统设置**，Android 版不会
- **问题**：`_HandlerGateway.requestStorage`（基类，iOS/macOS 用）在探针失败后**自动调用 `_openAppSettings()`**；`_AndroidPermissionGateway.requestStorage`（覆写）在探针失败后直接返回 `needsUserAction`，不跳设置。设计上 Android 由 onboarding `_explain` 弹窗引导（onboarding_page.dart:150-180），语义可辩护；但同一抽象两个实现行为分叉无注释说明，且 iOS/macOS 用户在**未经确认**的情况下被直接扔进系统设置（原则 12：危险/强操作应经显式动作触发——跳设置不算危险，但违反"平台差异在唯一位置裁决"的精神：分叉无登记）。
- **后果**：iOS/macOS 引导页用户点一次"获取"即被弹到系统设置（若探针失败），无中间说明；两平台行为不一致且无文档。
- **P2** · 原则 4（平台差异唯一位置裁决）、27。
- **状态**：确证（代码对比）。

---

## 运行时实测说明
本环境无 Flutter SDK（`dart`/`flutter` 不可用），无法运行 `flutter test`。所有条目基于完整源码阅读 + 调用点全量检索（rg 辅助定位、逐处人工阅读确认）确证；标注**待议**的条目（B5-A-01、04、08 的触发分支）需运行时注入验证。

## 覆盖文件清单
完整读（逐行）：gh_auth.dart(406)、gh_oauth.dart(58)、gh_oauth_types.dart(43)、gh_oauth_io.dart(113)、gh_oauth_stub.dart(18)、ix_session.dart(355)、permissions.dart(461)、permission_selftest.dart(187)、client_shell.dart(487)、login_page.dart(461)、onboarding_page.dart(391/504 权限自检段)、platform_io_impl.dart(571)、gh_auth_service_test.dart(127)、permissions_test.dart(48)、permission_selftest_test.dart(174)、main.dart 启动段(240-378)、surface_bridge.dart 账号段(170-229)、profile_page.dart 账号段(80-198)、gh_client.dart 令牌与 401 段(580-836 关键行)。裁决依据全文：QUALITY_STANDARD.md(93)、AGENTS.md(95)、CONSISTENCY.md(60)。

## 整体评价
认证链路的**安全设计意图**（令牌只进保险库、脱敏、删除顺序、切号清缓存、Device Flow 终止条件）在代码中落地完整、注释与实现高度一致，测试对状态机的正路径覆盖良好。主要风险集中在**状态机所有者之间的同步缝隙**：`auth.state` / `client_shell._guest,_accountId` / `IxSession._account,_context` 三处状态由不同事件链驱动，存在三处已确证的分叉窗口（B5-A-01/06/07），其中启动恢复路径（B5-A-07）与 401 全局出口对无令牌请求的误标（B5-A-09）是最可能被真实用户踩中的两条。另一系统性模式是 **KV 损坏的静默销毁**（B5-A-14 及 IoDiskKv.read 同型），与项目"失败必留痕"的铁律直接冲突，建议全链路统一改为"隔离 + 告警"而非删除。
