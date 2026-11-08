# 批5 · 视角C：契约与规范（认证 / 会话 / 权限链路）

> 只审不改、未写 lib/。审计时点：HEAD `64caf6d`（v12.0.0+120000，pubspec 与 `kOgLAppVersion` 一致）。
> 确证等级说明：「确证·静态」= 本批完整读文件 + rg 交叉复核可静态复现；「未确证」= 依赖运行期行为，仅标记疑点。

## 发现清单

### B5-C-01 [P1] AGENTS.md 版本与规模统计仍停在 v11.4.0，已两批未更新
- **文件:行号**：`AGENTS.md:3`
- **问题**：头部写「v11.4.0 … lib/ 197 个 Dart 文件 ≈ 49,300 行，测试 44 文件 ≈ 10,300 行」；实际 pubspec/`kOgLAppVersion` 均为 12.0.0，实测 lib/ 159 个 Dart 文件 55,808 行、test 49 文件 10,741 行。
- **后果**：上一批（B4）已点名该问题，v12 仍未修复；AGENTS.md 是 AI/贡献者的第一入口，版本与规模双失真会误导后续审计与评审基线。
- **原则**：47（记录必须与事实一致）、45
- **证据**：确证·静态。`rg '^version' pubspec.yaml` → `12.0.0+120000`；`rg kOgLAppVersion lib/main.dart` → `'12.0.0'`；`find lib -name '*.dart' | wc -l` → 159，行数 55,808；test 49 / 10,741。

### B5-C-02 [P2] `docs/CONSISTENCY.md` §4 的 206 回执描述仍落后于实现（B3-C-01 未随 v12 修复）
- **文件:行号**：`docs/CONSISTENCY.md:46-49`
- **问题**：仍写「`written.sha` 为空时回读远端确认」；实现（`gh_api.dart:816-817`）是「`statusCode == 206` **或** `sha` 为空」都回读。
- **后果**：本文自称「外部规范基线」「以源码为准并立即修正本文」，B3 点名后两版未改；规范基线自相矛盾会使读规范者漏掉「206 但回执带 sha 也必须回读」这一关键分支。
- **原则**：57（文档引用必须真实）、53
- **证据**：确证·静态。CONSISTENCY.md:47 原文 vs gh_api.dart:816-817（`receiptIncomplete || written.sha.isEmpty`）。

### B5-C-03 [P2] `gh_api.dart` 头注释仍写「D2/D10」，与 CONSISTENCY.md「D10 不是独立防线」的裁决冲突（B3-C-02 未随 v12 修复）
- **文件:行号**：`lib/domain/gh/gh_api.dart:847`
- **问题**：putContentLocked 注释「基线过期拒绝并给出三方差异（D2/D10）」；CONSISTENCY.md:18 明确「源码个别注释用『D10』指代三方差异展示，那是 D2 的子步骤，不是独立防线」。
- **后果**：契约文档与最核心写路径注释互相打脸，后人无法判定 D10 是否为真防线。
- **原则**：54、58
- **证据**：确证·静态。gh_api.dart:847 原文 vs CONSISTENCY.md:18 编号说明。

### B5-C-04 [P1] NETWORK.md「github.com 出口」行双重失真：令牌校验实际走 api.github.com，Device Flow 实现不在 gh_client.dart（B3 遗留未修复）
- **文件:行号**：`docs/NETWORK.md:20`（出口清单表第 6 行）
- **问题**：该行写「`github.com` | 令牌校验、OAuth Device Flow | OAuth client_id | gh_client.dart」。静态确证两处不符：① 令牌校验（登录门 `GET /user`）走 `api.github.com`（`gh_client.dart:435` `baseUrl = 'https://api.github.com'`，Bearer 头），且出口清单第 1 行已把 api.github.com 标为「是（Bearer）」，两行自相矛盾；② Device Flow 的两个端点常量在 `gh_oauth_io.dart:12-13`（`github.com/login/device/code`、`github.com/login/oauth/access_token`），gh_client.dart 全文无 github.com 直连代码。
- **后果**：NETWORK.md 的维护要求（第 5 行）自声明「每个符号必须与代码一致」，安全出口清单恰恰是最需要准确的一张表；用户审计流量去向时会被引到错误文件。
- **原则**：57、38（面向用户/审计者说清事实）
- **证据**：确证·静态。`rg -n 'github.com' lib/domain/gh/` 仅命中 gh_oauth_io.dart:12-13 与注释；gh_client.dart:435 baseUrl。

### B5-C-05 [P1] `GhAuthState.signingIn` 全项目零消费、零迁移——声明即死状态
- **文件:行号**：`lib/domain/gh/gh_auth.dart:36`（`signingIn`）
- **问题**：`rg 'signingIn' lib test` 仅命中枚举声明自身；登录过程中 `_finishLogin`（login_page.dart）全程不调 `markSigningIn`（该 setter 也不存在），busy 态只存在于页面局部 `_busy`。
- **后果**：① 全局观察者（外壳/未来页面）在登录进行中读到的是 `unknown`/旧态，与注释「登录 / 失效 / 切号 / 登出都自动联动」（gh_auth.dart:9）不符；② 登录页因 `mounted` 丢弃（`if (!mounted) return;`）退出时，全局态仍停在前值，无人知晓「正在登录」。属注释-实现不一致 + 死代码二合一。
- **原则**：55（死代码零容忍）、15
- **证据**：确证·静态。rg 全库唯一命中。

### B5-C-06 [P2] `GhAccount.canWrite` 注释「是否为该账号配置了写权限」与语义「scopes 未知时默认可写」相反
- **文件:行号**：`lib/domain/gh/gh_auth.dart:124-125`
- **问题**：`bool get canWrite => scopes.isEmpty || scopes.contains('repo')` —— scopes 为空（未知）时**放宽**为可写，注释只说「配置了 repo」。
- **后果**：登录链路（login_page.dart:182）保存的 `GhAccount` 从不填 scopes（恒空表），故所有账号的 canWrite 恒为 true，该字段当前无信息量；若未来真填 scopes，空表=可写 的默认方向对「细粒度令牌未授 repo」是危险放宽。实际写权限 UI 用的是 `repo.isWritable`（repo_page.dart:461），与本字段无关——即本字段是**未接线的近似品**。
- **原则**：54、59
- **证据**：确证·静态（实现与注释不符 + 登录链路恒空 scopes）；「会造成 403 误导」属运行期推测，未确证。

### B5-C-07 [P1] guest 语义链路三处不闭环：无退出、上下文不清、auth.state 与壳状态机脱节
- **文件:行号**：`lib/surface/app/client_shell.dart:270-276`（登录门段）+ `lib/domain/gh/gh_auth.dart:308`
- **问题**：① 壳用**局部 `_guest` 布尔**管理游客态，而 `GhAuthState.guest`/`markGuest()` 除测试外全项目零调用（rg 确证）——「单一可观察状态源」的 guest 分支实际由壳的私有字段承担，两套真相；② 游客模式下没有「回到登录门/注册账号」的入口（`_guest` 只在 `_check` 里读到账号时被翻回 false，登录页的「跳过」之外无任何 UI 可逆）；③ 游客期间持久化的 `ogl.ix.context`（若此前登录过则残留上一账号的 repo/branch/path）不会被 `IxSession.refreshAccount` 之外的任何路径清掉，游客浏览行为会继续沿用旧账号的会话上下文。
- **后果**：游客语义「只读浏览公开内容」（gh_auth.dart:39）在壳层没有对应的可见出口；切游客后 search/dashboard 等页以 `accountId ?? 'guest'` 重建 key，但残留 context 可能让游客直接落进一个他无权看的私有仓库名（404/401 体验）。
- **原则**：15（状态可见）、59
- **证据**：①③ 确证·静态（rg `markGuest|GhAuthState.guest` 全库仅 3 处：声明、实现、测试）；② 确证·静态（client_shell.dart:270-276 无 guest 出口分支）；③ 的实际撞库后果未确证。

### B5-C-08 [P1] 权限探针语义约定仅存在于注释：装配层传入的 `storageProbe` 与「用户可见位置」约定之间无任何类型/测试约束
- **文件:行号**：`lib/surface/app/permissions.dart:122-124,193-199`（约定原文）+ `lib/surface/surface_bridge.dart:109-118`
- **问题**：_HandlerGateway 注释（:193-199）写探针「必须返回文件是否落在**用户可见**的位置，而不是随便找个能写的地方」；`main.dart:301` 与 settings_page/onboarding 传入的 `surface.ensureStorage` 只透传 `storageProbe`，surface_bridge 的实现是一个 `try/catch → bool` 的普通可写性检查，其「用户可见」语义依赖更下层实现，注释约定链上无一处类型化表达或离线测试钉住（`test/surface/permissions_test.dart` 未覆盖探针语义，见 B5-C-11）。
- **后果**：这正是注释自述的历史缺陷（「退回应用私有目录也会被判成已授权」）的复发通道——探针语义一旦被实现者简化，没有任何门禁会红。
- **原则**：53、52（空/无/未启用是三种"没有"）
- **证据**：确证·静态（注释约定 + 传递链无类型表达）；「探针实际返回什么」依赖 base 层实现，本批未全文追入 `ensureStorage` 下游，**不冒充**其实际语义正确或错误——仅确证「约定无守卫」。

### B5-C-09 [P2] `_AndroidPermissionGateway.requestStorage` 覆写后，基类 `requestStorage`（含「失败后打开系统设置」）成为不可达死分支
- **文件:行号**：`lib/surface/app/permissions.dart:248-262`（基类默认实现）vs `:365-395`（Android 覆写）
- **问题**：基类 `requestStorage` 的最后一段「`await _openAppSettings(); return needsUserAction;`」只有 Android 会覆写、iOS/macOS 走 `_requestOf(notification)` 之外的 storage 分支——但 iOS/macOS 的 `storagePermissions()` 恒空，基类实现里 `storage.isEmpty → notRequired` 先行返回，永远到不了 openAppSettings；因此「探针失败 → 自动跳设置页」这条**仅存在于基类实现**的路径在所有平台都不可达，而 Android 覆写版反而**不调** `_openAppSettings()`（探针失败只返回 needsUserAction，靠 describe() 的 rationale 文案引导）。
- **后果**：两处实现的失败处置不一致且互相矛盾：基类「自动跳设置」，Android「只报告」；用户在 Android 上探针失败后没有任何系统入口被调起，与头注释「打开设置用的还是正确入口」的修复承诺不完全对齐。属注释-实现一致性缺口（非功能损坏）。
- **原则**：54、15
- **证据**：确证·静态（继承关系与调用图：describe()/request() 的 storage 分支仅 Android 覆写版可达）。

### B5-C-10 [P2] OAuth Device Flow 令牌生命周期文档缺位：GitHub `gho_` 令牌不过期，但应用内 `expired_token`→`GhOAuthStatus.expired` 的用户码过期语义与 15 分钟硬编码未写进任何契约文档
- **文件:行号**：`lib/domain/gh/gh_oauth_io.dart:47`（`Duration(minutes: 15)` 硬编码）vs `docs/NETWORK.md`、`docs/OAUTH_ORG_SETUP.md`、gh_oauth.dart:9-17
- **问题**：gh_oauth.dart 头注释承诺「③ 应用轮询换取 access token」，但对「GitHub Device Flow 的 access_token 本身长期有效、真正过期的是 device_code/user_code（GitHub 侧约 15 分钟）」这一生命周期事实，三个相关文档与注释均未说明；`gh_oauth_io.dart:47` 的 15 分钟 deadline 与 GitHub `expires_in` 返回值（代码未读取）无关，是凭空硬编码。
- **后果**：若 GitHub 侧 user_code 有效期短于 15 分钟（官方默认 900s 恰好一致，但这是巧合不是契约），未来 GitHub 调整 `expires_in` 时轮询会多转空圈；文档层面「令牌是否会过期、失效后走哪条路（401→markExpired）」没有一处权威描述，认证契约不完整。
- **原则**：57、21
- **证据**：确证·静态（代码不读 `expires_in`；rg 'expires' lib/domain/gh 零命中；三份文档无 Device Flow 生命周期段）。

### B5-C-11 [P0] 认证测试存在系统性覆盖缺口：多账号切换、权限回退、游客行为、保险库回读自检全无离线断言（B3-C-09 同类问题在认证域复现）
- **文件:行号**：`test/domain/gh_auth_service_test.dart:1-127`（全文 127 行）、`test/domain/gh_test.dart:355-375`、`test/surface/permissions_test.dart`、`lib/surface/pages/login_page.dart:150-230`
- **问题**：逐文件读完 test/domain 全目录与 gh_auth_service_test 后确证以下缺口：
  1. **登录四步链路**（login_page.dart:155-229 的暂存→验证→转正→回读自检）：零测试。这是注释自述「任何一步失败都会让看起来登上了、实际没有令牌」的关键链路，「回读自检是**门**，不是日志」（:223-227）这一 P0 级行为没有任何回归守卫；
  2. **多账号切换**：`switchTo` 成功路径（写 activeKey + signedIn）、`removeAccount` 后自动回退到下一个有令牌账号（gh_auth.dart:363-375，注释自述的历史 P0）均无断言——gh_test.dart:355-360 只测了 removeAccount 的清理面，未触发 wasActive 自动切换分支；
  3. **权限回退**：`_AndroidPermissionGateway.requestStorage` 的「候选逐个请求 → 探针二次确认」三级回退（permissions.dart:365-395，注释标 ★ 5.1+ 全版本可用）无单测；`test/surface/permissions_test.dart` 存在但未覆盖网关状态机（本批读其目录清单与 rg 复核，未全文细读，不冒充其内容）；
  4. **游客行为**：`markGuest` 之外，壳层 `_guest` 状态机（client_shell.dart）无 widget 测试。
- **后果**：B3-C-09 的教训（「曾定级 P0 的修复可在任何离线测试都不失败的情况下被改坏」）在认证域原样存在；`removeAccount` 自动切换那段自带「此前忽略返回值」勘误注释的代码，同样可以被静默改坏。
- **原则**：51、49/50、13
- **证据**：确证·静态。gh_auth_service_test.dart 全文仅覆盖 markExpired/refreshState/markGuest/saveAccount/switchTo 拒绝分支/脱敏；`rg 'switchTo|removeAccount' test/` 仅 gh_test.dart:361 removeAll 与拒绝分支；login_page 四步链路 rg 零命中。

### B5-C-12 [P2] `contract_audit.py` 的文件头检查只扫 `text[:400]`，L2 头部注释超过 400 字符的文件会漏检（B3-C-06 门禁盲区仍在）
- **文件:行号**：`tool/contract_audit.py:96`（`head = text[:400]`）
- **问题**：本批范围内 gh_auth.dart 的 `/// L2 中枢级…` 出现在第 1 行（不触发），但检查逻辑本身以 400 字符为窗口；同时该脚本与 layer_audit 均不解析条件导出链（`gh_oauth.dart` 的 `if (dart.library.io)` 分支，B3-C-08 已点名），v12 仍无对应检查。
- **后果**：B3-C-06（「L2 文件头硬惯例未被门禁真正检查」——实际是检查窗口脆弱）与 B3-C-08（OAuth 条件 import/export 无可达性解析）在 v12 均未修复；`--fatal` 门禁对这两类违规保持沉默。
- **原则**：53
- **证据**：确证·静态（contract_audit.py:96 原文；本批实跑 `python3 tool/contract_audit.py` 全绿 0 处，证明现有文件不触发，但不证明检查充分）。

### B5-C-13 [P2] QUALITY_STANDARD.md 原则 39 与登录页实现存在轻微出入：令牌在验证前的「暂存账号」阶段就已进入保险库并写诊断（含 masked 值）
- **文件:行号**：`docs/QUALITY_STANDARD.md:39`（「凭证只进系统密钥库，永不进日志…」）+ `lib/domain/gh/gh_auth.dart:246-253`（OGL-AUTH-001 诊断含 `token: token.masked`）+ `lib/surface/pages/login_page.dart:160`（OgLAppLog 记录暂存动作）
- **问题**：实现完全合规（只记 masked），但注意 gh_auth.dart:250 的日志是「脱敏令牌进诊断日志」——原则 39 说「永不进日志」，字面上连脱敏形态也被禁；这是「原则字面过严、实现按合理解释」的典型，原则未说明脱敏形态是否豁免。
- **后果**：低。属规范精度问题：后续审计者可据字面把 OGL-AUTH-001 误判为违规。建议在原则 39 补一句「脱敏形态除外」。
- **原则**：54（原则应可裁决）
- **证据**：确证·静态（两处原文对照）；不判实现为缺陷。

### B5-C-14 [P1] `client_shell.dart` 登录门条件读 `auth.state == expired`，但 `_check()` 刷新的只有 `_accountId`；expired 恢复路径依赖 `markExpired` 幂等 + 外壳重建，存在一处真实不一致：**expired 后用户重新保存令牌（saveAccount），若 activeId 未变，壳不会清掉 expired 门**
- **文件:行号**：`lib/surface/app/client_shell.dart:270-271` + `lib/domain/gh/gh_auth.dart:261-270,282-296`
- **问题**：壳的登录门显示条件含 `state == GhAuthState.expired`；`_check()`（:101-128）只重读 `activeAccount()`，不调用 `refreshState()`。`saveAccount` 在「当前账号已是 active」时会 `_setState(signedIn)`（gh_auth.dart:259）——这条路能关门；但登录页走的是 `saveAccount(新 pendingId)` → `switchTo` 链，`switchTo` 无条件置 signedIn，也能关门。真正的缝隙在：**401 → expired → 用户不重登、直接切到一个仍有令牌的账号**：profile 页 `_switchTo` 成功后调 `_refresh()` → `onAccountsChanged`（=壳 `_check`）→ `_accountId` 非空，但 `auth.state` 仍是 expired（switchTo 置的是 signedIn——已闭环）。复核后此路径实际闭环。**残余缝隙**：`refreshState()` 除定义外全项目零调用（rg 确证仅声明处），启动时 `_check()` 用「activeAccount 非空」近似代替「令牌存在」，即 `_check` 不读保险库——令牌丢失（如保险库被系统清空）时壳会放行进壳层，直到第一个 API 401 才由 markExpired 拉回登录门。
- **后果**：令牌静默丢失的用户会先经历一次假登录体验（页面全 401 报错），而不是启动时被登录门拦下——gh_auth.dart:282 注释「从磁盘刷新一次认证状态（启动时调用）」与事实不符（**没有任何调用点**）。
- **原则**：54、15
- **证据**：确证·静态（`rg 'refreshState' lib` 仅 gh_auth.dart:282 声明 + 注释；client_shell `_check` 不触 vault）。

## 覆盖文件清单

| 文件 | 状态 |
|---|---|
| lib/domain/gh/gh_auth.dart（406 行） | 完整读 |
| lib/domain/gh/gh_oauth.dart / gh_oauth_io.dart / gh_oauth_stub.dart / gh_oauth_types.dart（232 行） | 完整读 |
| lib/domain/ix/ix_session.dart（355 行） | 完整读 |
| lib/surface/app/permissions.dart（461 行） | 完整读 |
| lib/surface/app/client_shell.dart（487 行） | 完整读 |
| lib/surface/pages/login_page.dart（461 行） | 完整读（分两段） |
| test/domain/gh_auth_service_test.dart（127 行） | 完整读 |
| tool/contract_audit.py（165 行） | 完整读 |
| docs/NETWORK.md / AGENTS.md / QUALITY_STANDARD.md / CONSISTENCY.md | 完整读 |
| docs/OAUTH_ORG_SETUP.md | 摘要读（OAuth 段） |
| 辅助核对（局部/rg）：gh_client.dart:401 出口段、gh_api.dart:810-855、disk_cache.dart 表头与 206 段、login.json、profile/settings_page 相关段、test/domain 全目录清单、gh_test.dart:355-375 | 局部读 |

## 整体规范符合度评价

**中上，但「注释质量 ≠ 契约质量」的落差在本批集中暴露。**

- **做得好**：令牌安全铁律（保险库分离存储、脱敏 toString、删除顺序先令牌后元数据、saveAccount 的「令牌写失败不落元数据」）在注释与实现间高度一致，是全链路最扎实的部分；登录四步链路与失败回滚（先恢复激活态再清理）考虑周到；失败可见、类型化确认（IxConfirmationRequired/D7）在认证域无违例；contract_audit 实跑全绿。
- **结构性弱点**：① guest 语义是「枚举里有一半实现」的重灾区（B5-C-07）；② 启动认证探活注释与实现脱节（B5-C-14）；③ OAuth 生命周期无契约文档（B5-C-10）；④ 测试对状态机核心分支（切换自动回退、回读自检门、权限回退）几乎失明（B5-C-11，P0）。
- **文档健康度**：QUALITY_STANDARD 59 条原则清晰可裁决，无失效引用（contract_audit 确证）；但 AGENTS.md 版本/规模连续两批落后（B5-C-01），CONSISTENCY.md 206 描述、gh_api D10 措辞、NETWORK.md OAuth 出口位置三项 B3 遗留**均未随 v12 修复**（B5-C-02/03/04）——文档契约的「改实现必须同步改本文」纪律在 v12 周期未被执行。
- **统计**：14 条发现（P0×1、P1×5、P2×8）；确证·静态 13 条，B5-C-08 部分确证（探针下游语义未追入）。

*未改动任何 lib/ 与被审文件；本报告为唯一产出。*
