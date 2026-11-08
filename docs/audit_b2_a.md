# 第2批·视角A：实现正确性审计（磁盘一致性层）

> 依据：docs/QUALITY_STANDARD.md（原则 8–14、15–21、22–29）、AGENTS.md §3/§5。
> 纪律：只审不改；发现一条立即追加。编号 B2-A-xx；含文件:行号、问题描述、修复前 vs 修复后行为差异、用户可见后果、优先级、违反原则编号、确证/待议（附代码证据）。

## B2-A-01 · `putContent` 回退失效 `_cache!.invalidate` 在键锁内自锁（P0，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:816-823`（`putContent` 写成功后"同步失效底座缓存"），配合 `lib/base/disk/disk_cache.dart:686-693`（`_writeLocked` 持锁调用 `_remote.write`）、`lib/domain/gh/gh_api.dart:1993-2007`（`CacheRemote.write → putContent`）、`disk_cache.dart:284-287`（`invalidate` 也进同一把 `_mutex.run`）、`disk_cache.dart:107-123`（`_KeyedMutex.run` 等待前序 `completer.future`）。
- **问题描述**：D4 逐键锁的持有者 `_writeLocked` 在锁内调用 `_remote.write`，真实远端实现是 `GhApi.write → putContent`，而 `putContent` 末尾又调用 `_cache!.invalidate(key)`，`invalidate` 再次 `_mutex.run(key.encode())`，等待**当前这次** `_writeLocked` 所占锁的 `completer` 完成；而 `_writeLocked` 又要等 `putContent` 返回才能结束。构成同一 key 的自等待环：引擎写路径 100% 挂死（PUT 已发出后永不返回，直到上层超时/进程被杀）。`write()` 的通用 catch 也救不了，因为 await 永不返回。
- **修复前 vs 修复后行为差异**：修复前：任何经引擎的保存（`putContentLocked` → `cache.write`）在 `await _remote.write` 处永久挂起，远端可能已提交但本地永远无结果、无日志、无 journal 收尾；修复后：`putContent` 识别自己处于同一键锁调用栈（或失效改为不重入锁的直接 `_evictEncoded` / 由引擎统一失效），`_writeLocked` 正常收到 `written`，继续 D5 失效+回读、D9 清草稿、D8 complete。
- **用户可见后果**：保存假死（"点了保存永远转圈/无提示"），远端写入已生效却被判为未完成；journal 记录滞留 pending，后续 `replayPending` 以旧基线重放造成重复提交/冲突；草稿不被清除，下次进入编辑器旧内容"复活"覆盖所见即新提交内容 → 写歪/数据错乱。
- **优先级**：P0。
- **违反原则**：23（互斥闸门成对且同一所有者）、22（异步结果有效性）、13（写入要么完整生效要么可恢复）、17/15（失败必须可感知，不能静默挂起）。
- **是否确证**：确证。代码证据：`gh_api.dart:818-820` `final CacheKey? key = await _cacheKeyFor(...); if (key != null) { await _cache!.invalidate(key); }`；`disk_cache.dart:284-287` `invalidate(...) => _mutex.run(key.encode(), () => _evictEncoded(...))`；`disk_cache.dart:686` `final written = await _remote.write(...)` 位于 `_mutex.run` 闭包内（`disk_cache.dart:257`）；`_KeyedMutex.run:111` `await previous;`（previous 即本次 `_writeLocked` 尚未 complete 的 future）。同一 `key.encode()` 是同一把锁。`GhApi.write:2001` 直接调 `putContent`。
## B2-A-02 · D5 回读抛异常使「远端已提交」被判失败且草稿/Journal 不收尾（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:690-712`（成功路径顺序）、`disk_cache.dart:758-770`（`_verifyReadback`）、`disk_cache.dart:269-278`（`write()` 外层 catch）、`lib/domain/gh/gh_api.dart:1929-1944`（`GhApi.read` 会抛 `GhAuthException`）。
- **问题描述**：成功路径顺序为 `_remote.write` → `_evictEncoded` → `_verifyReadback` → `_saveLocal` → `_drafts?.discard` → `_journal!.complete`。`_verifyReadback` 内 `await _remote.read(key)` 对网络/认证异常**没有任何 catch**；`_writeLocked` 的 `while` 里只 `on RemoteConflictException`，不捕普通异常，异常一路冒泡到 `write()` 的通用 catch，被折成 `WriteConflict.server`「写入异常终止」并 `failByKey` 保留 pending。此时 PUT 已成功返回（`written` 已拿到），只是回读失败。
- **修复前 vs 修复后行为差异**：修复前：远端已提交 → UI 收到"写入失败/稍后重试"，草稿不清、journal 不 complete、本地缓存已失效；修复后：回读异常与"回读不一致"同等对待（或不改变提交结论），`_drafts.discard` 与 `_journal.complete` 在远端确认后立即执行，本地缓存/回读的失败只留痕不改结论。
- **用户可见后果**：**静默失败**（假报错）；用户据此再点一次保存或等待重放 → 带着旧基线重放被 D2 拦成 `staleSha` 进而 `abandon`，草稿残留旧内容在下次进编辑器"复活"，与实际已提交的远端内容不一致（写歪）。
- **优先级**：P1。
- **违反原则**：13（写入要么完整生效要么可恢复）、16/17（不吞异常、用类型表达失败）、22（过期/失效结果不得当权威）。
- **是否确证**：确证。代码证据：`disk_cache.dart:693` `final RemoteDocument? verified = await _verifyReadback(...)` 无 try；`:763` `final document = await _remote.read(key);` 无 catch；`:686` PUT 已 `await` 成功；`:704`/`:708` 的 discard/complete 位于回读之后；`:272` `await _journal?.failByKey(...)` 把所有异常归入失败。
## B2-A-03 · `deleteContentLocked` 回退路径丢弃 D7 二次确认并外抛异常（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:956-980`（`deleteContentLocked` 的 `cache == null || key == null` 分支）、`lib/base/disk/disk_cache.dart:298-317`（`delete` 的 D7）、`gh_api.dart:999-1017`（裸 `deleteContent`）。
- **问题描述**：引擎路径 `RepositoryCache.delete` 在 `confirmed == false` 时返回 `needsConfirmation`（D7，disk_cache.dart:307-317）。但 `deleteContentLocked` 在缓存未绑定或键构造失败时走"退化为裸删除"分支：`confirmed` 参数**完全未被读取**，直接 `await deleteContent(...)`，随后无条件返回 `ok: true`。同时该分支只 `await deleteContent`，未包 try/catch，`RemoteConflictException`、网络异常、权限异常会**直接外抛**，与 `deleteContentLocked` 文档「失败以 GhWriteResult 返回」及 AGENTS.md「一致性引擎返回 WriteOutcome 不外抛」相反。
- **修复前 vs 修复后行为差异**：修复前：在装配早期/缓存键非法/账号 provider 抛异常时，用户点一次删除即真实发出 DELETE，没有二次确认；409/422 直接把异常抛给 UI。修复后：回退路径同样先判 `confirmed`，未确认返回 `needsConfirmation`；冲突折成结构化 `GhWriteResult`（如 `staleSha`），不外抛。
- **用户可见后果**：**危险操作无二次确认即生效**（数据丢失）；冲突时 UI 未收到结果，删除已失败却可能被当成"没反应"，或异常冒泡造成页面崩溃。
- **优先级**：P1。
- **违反原则**：12（危险操作必须用户显式确认，且在类型上表达）、11（防线没有开关）、17（用类型表达失败）、16（不吞异常/不误抛）。
- **是否确证**：确证。代码证据：`gh_api.dart:962-980` 分支体内无 `confirmed` 字样、无 try/catch；`:974` 硬编码 `ok: true`；对照 `:968-980` 与引擎路径 `disk_cache.dart:307`。触发条件真实存在：`_cacheKeyFor` 在 `_cache == null`（`gh_api.dart:93-95`）或 `accountIdProvider` 异常/默认分支解析不出（`ref.isEmpty`）时返回 `null`（`gh_api.dart:97-116`）。
## B2-A-04 · D1 新建语义 TOCTOU：无基线 + 远端不存在时并发建同路径互相覆盖（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:611-628`（D1 归一化与"远端不存在+无基线=合法新建"放行）、`disk_cache.dart:673`（`var expectedSha = intent.force ? latest?.sha : baselineSha;` → 新建时 `null`）、`disk_cache.dart:686-690`（`_remote.write(expectedSha: null)`）、`lib/domain/gh/gh_api.dart:779-785`（PUT 请求体 `if (baseSha != null && baseSha.isNotEmpty) 'sha': baseSha`，即不带 sha）。
- **问题描述**：D1 刚改成「远端不存在 + 无基线 = 合法新建」，其注释称"GitHub 用'无 sha 即拒绝覆盖'兜底并发创建"。但 GitHub Contents API 的语义是：**不带 `sha` 的 PUT 对已存在文件是覆盖更新**（只有"带了错误 sha"才会 409/422）。因此两个并发新建（两个设备/两个 tab，或 `replayPending` 与用户手动新建交叉）在 `read → write` 之间互相不可见时，两次 PUT 都成功，后者把前者内容静默覆盖。逐键锁 D4 只保护**单进程同一 RepositoryCache 实例**、且按 `key.encode()` 串行，跨进程/跨设备/重建实例后重放均不在保护范围；`force` 分支反而显式带 `latest.sha`，新建分支却是纯盲写。
- **修复前 vs 修复后行为差异**：修复前：无基线的两次 PUT 都当成"新建"成功，先提交的内容被后提交者覆盖且没有任何冲突提示（`ok: true`）；修复后：新建写入必须走幂等/条件创建（例如服务端 `If-None-Match`/先创建再校验 sha 的事务），或读到远端已存在即折为 `staleSha`/`requiresRead` 并要求用户决策。
- **用户可见后果**：**两人同时新建同名文件时一方内容静默丢失**（数据丢失 + 写歪），且双方 UI 都显示"提交成功"。
- **优先级**：P1（并发新建覆盖面窄，故未列 P0；但违反 D1/D2 核心语义）。
- **违反原则**：9（写前必读，不知道当前状态就动手不可信）、10（并发写必须被乐观锁看见，而不是被覆盖）、26（写要么幂等要么防重）、11（防线没有开关）。
- **是否确证**：确证（GitHub 端点语义属外部事实，结合端点实测原则 52 标注为"高置信"；若需 100% 实证可用真机打两次无 sha PUT，这里按代码实现 + 官方语义裁决）。代码证据：`disk_cache.dart:620` `if (baselineSha == null && !intent.force && latest != null) {...}` 只拦"已存在"；`:673` `expectedSha = baselineSha`（null）；`gh_api.dart:781` `if (baseSha != null && baseSha.isNotEmpty) 'sha': baseSha` 无 sha 字段。
## B2-A-05 · D1「远端不存在」判据被 `GhApi.read` 的 409/422/大文件读失败污染 → 误放行无基线覆盖（P0，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:1929-1944`（`GhApi.read` 的异常折叠）、`gh_api.dart:2035-2039`（`_isAbsentStatus` = 404/409/422）、`gh_api.dart:1953-1985`（>1MB 内容读不到 `return null`）、`lib/base/disk/disk_cache.dart:617-628`（D1 以 `latest == null` 判"远端不存在"）、`disk_cache.dart:673`（`expectedSha = baselineSha` → null）、`gh_api.dart:779-785`（不带 `sha` 的 PUT）。
- **问题描述**：刚改过的 D1 把「`latest == null` + 无基线」当作**合法新建**放行。但 `CacheRemote.read` 的真实实现把三类"读不到"都折成 `null`：① `GhAuthException` 的 404/**409/422**（`_isAbsentStatus`，注释明确说读场景 409/422 也算"没有东西"）；② Contents API 对 >1MB 文件省略 content 且 `blobText` 抛 `GhNotFoundException` 时 `text == null` → `return null`；③ 响应体不是 Map 时 `return null`。于是"远端**确实有文件**但暂时读不出来"被 D1 当作"远端不存在"，`expectedSha` 置为 `null`，`putContent` 发出**不带 sha 的 PUT**——GitHub 对已存在路径的无 sha PUT 是**覆盖更新**，不是创建。D1 注释声称的"无 sha 即拒绝覆盖"兜底并不成立（见 B2-A-04）。
- **修复前 vs 修复后行为差异**：修复前：409/422 冲突态、空仓库冲突、>1MB 大文件 blob 读取失败、代理返回异常体时，无基线写入被判合法新建并直接覆盖远端已有内容，`WriteOutcome.success`，无冲突、无确认；修复后：`CacheRemote.read` 必须区分「不存在（404 且语义确认为不存在）」与「读失败/冲突/内容不可得」（抛异常或返回显式状态），D1 只在**确证不存在**时放行新建；任何读不确定一律折成 `requiresRead`/`server` 并阻止写。
- **用户可见后果**：**远端已有文件被静默覆盖（数据丢失 / 写歪）**，UI 显示"提交成功"；服务端 409/422 冲突期间尤其危险（本来最该拒绝写入的时刻反而放行）。同时违反原则 52「空、无、未启用是三种不同的没有」。
- **优先级**：P0。
- **违反原则**：9（写前必读，不知道当前状态就动手不可信）、10（并发写必须被乐观锁看见）、52（端点语义必须实测/严格区分）、11（防线没有开关）、16（不吞异常，409/422 不该在读路径被吞成 null）。
- **是否确证**：确证。代码证据：`gh_api.dart:1939-1943` `} on GhAuthException catch (error) { if (_isAbsentStatus(error.statusCode)) { return null; } rethrow; }`；`:2037-2039` `statusCode == 404 || statusCode == 409 || statusCode == 422`；`:1968-1972` `if (!parsed.isDirectory && parsed.size == 0 ...) { text=''; } else { return null; }`（大文件 blob 失败同样落此分支）；`disk_cache.dart:620-628` `if (baselineSha == null && !intent.force && latest != null) {...}` —— `latest == null` 时不拦；`:673` `var expectedSha = intent.force ? latest?.sha : baselineSha;`。
## B2-A-06 · D8 Journal 状态机缺 `force`/`rebase` 字段，重放时放弃 force 且 D7 永远卡 pending（P1，确证）

- **文件:行号**：`lib/base/disk/disk_journal.dart:82-90`（`JournalRecord.toIntent()`）、`disk_journal.dart:31-39`（`JournalRecord` 字段）、`disk_journal.dart:110-123`（`toJson`）、`disk_journal.dart:178-190`（`enqueue` 只存 baseSha/dangerous）、`lib/base/disk/disk_cache.dart:439-465`（`replayPending`）、`lib/domain/domain_bridge.dart:212-248`（两个生产调用点均 `replayPending()` 不传 confirmed）。
- **问题描述**：① `toIntent()` 只还原 `key/content/message/baseSha/dangerous`，**丢弃 `WriteIntent.force` 与 `rebase`**：用户确认过的强制覆盖在写前落盘后若崩溃，重启重放会变成普通写，D2 拦成 `staleSha` → `_fail` 把记录 `abandon`，用户以为排队的强制覆盖会补交，实际被静默放弃；D3 的 rebase 函数也不可能序列化，重放必然失去自动合并能力（"仅在提供 rebase 时重试"在重放路径恒为 false）。② `dangerous: true` 的记录（`RepositoryCache.delete` 不入 journal，但 `write` 允许 dangerous）重放时 `confirmed` 缺省 `false`，`_writeLocked` 返回 `needsConfirmation`，`replayPending` 刻意保持 pending；而生产装配的两个调用点（`domain_bridge.dart:215`、`:242`）**都从未传 `confirmed: true`**，也没有任何 UI 入口消费 pending 并带确认重放（全仓 `replayPending` 调用仅这两处 + 测试）。结果是危险记录永久挂在"待同步"，每 30s 被重放一次直到定时器空转 3 次自停，用户数据既不提交也不被告知需要确认。
- **修复前 vs 修复后行为差异**：修复前：force/rebase 记录重放语义被篡改（强制覆盖变普通写并被 abandon），dangerous 记录永久 pending 静默失败；修复后：Journal 记录完整保存恢复 D1–D7 所需的状态（或至少显式声明不可序列化字段并禁止入队/给出冲突结果），重放对需确认项产出用户可见的"待确认"通知并有带确认的入口。
- **用户可见后果**：**排队中的用户写入被静默放弃/永久不提交**（数据丢失、静默失败）；强制覆盖后重启，用户看到"已放弃"而非预期内容。
- **优先级**：P1。
- **违反原则**：13（每次写入要么完整生效要么可恢复；重放语义必须与原意图一致）、12（确认在类型上表达）、15/17（失败必须可感知，不能静默挂着）、21（降级路径要有退出条件）。
- **是否确证**：确证。代码证据：`disk_journal.dart:82-90` `toIntent()` 无 force/rebase；`disk_cache.dart:447-450` `write(record.toIntent(), confirmed: confirmed, recordJournal: false)`；`:455-458` needsConfirmation 时注释"必须保持 pending"但不产生任何通知；`domain_bridge.dart:215` `base.disk.cache.replayPending().then(...)`、`:242` 同，全仓 grep 无 `confirmed: true` 的生产调用。
