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
## B2-A-07 · D3 冲突重试可从 `latest` 读失败/读旧值产生 `expectedSha = null` → 二次 PUT 盲写覆盖（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:721-746`（`on RemoteConflictException` 重试分支）、`lib/domain/gh/gh_client.dart:782-786` + `:804-808`（`RemoteConflictException.currentSha = response.jsonObject?['sha']`，409/422 错误响应通常**无 sha 字段** → null）、`lib/domain/gh/gh_api.dart:1939-1943`（`fresh = await _remote.read` 对 409/422 又返回 `null`）、`gh_api.dart:781`（不带 sha 的 PUT 覆盖）。
- **问题描述**：D3 重试时 `content = intent.rebase!(fresh?.content ?? '', intent.content); expectedSha = error.currentSha ?? fresh?.sha;`。`error.currentSha` 取自 409/422 错误响应体的 `sha`，GitHub 的冲突错误体通常没有该字段（返回 `message`/`errors`），故为 `null`；而 `_remote.read`（`GhApi.read`）又把 409/422 折成 `null`（见 B2-A-05），`fresh?.sha` 也是 `null`。于是第二次 `expectedSha` 为 `null`，`putContent` 不带 `sha` 直接 PUT，且 `content` 是 `rebase('', 用户内容)` 的结果——相当可能以空远端为基线合并。重试上限 `maxConflictRetries = 2`（`disk_cache.dart:141`）+ `attempt > maxConflictRetries` 只限制次数，不校验 `expectedSha != null` 就继续发写。
- **修复前 vs 修复后行为差异**：修复前：D3 冲突重试在拿不到新 sha 时降级为"无基线盲写"并成功覆盖远端，D2 乐观锁在重试路径被彻底绕过；修复后：`expectedSha` 为 null 时不得再次 PUT，应返回 `staleSha`/`server` 并保留三方差异交回用户，或重新读取直到拿到权威 sha。
- **用户可见后果**：**他人提交被覆盖（数据丢失/写歪），且 UI 显示"冲突已重定基后重试成功"**，日志还会打 `OGL-CONS-204`，掩盖事故。
- **优先级**：P1。
- **违反原则**：10（冲突必须被乐观锁看见）、9（写前必读）、11（防线没有开关）、41（只重试幂等方法/非幂等重试必须安全）。
- **是否确证**：确证。代码证据：`disk_cache.dart:741-742` `content = intent.rebase!(fresh?.content ?? '', intent.content); expectedSha = error.currentSha ?? fresh?.sha;`；循环内 `:686-690` 直接用该 `expectedSha` 发 PUT；`gh_client.dart:785` `currentSha: _currentShaOf(response)`、`:805-807` 只取响应体 `object?['sha']`；`gh_api.dart:1941` 409/422 时 `return null`。
## B2-A-08 · D1/D2 空串归一化只贯通 `expectedSha`，`_threeWayFor`、`WriteOutcome.baseSha`、`Journal.enqueue` 仍用原始空串（P2，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:611-615`（局部 `baselineSha` 归一化）、`:630-645`（D2 失败时 `'${shortSha(intent.baseSha)}'`、`baseSha: intent.baseSha`、`threeWay: await _threeWayFor(intent, latest)`）、`:833-840`（`_threeWayFor` 用 `localBase.sha == intent.baseSha` 判定 base）、`:665-668`（`_journal.enqueue(intent)` 原样入队）、`:731-735`（D3 失败 `baseSha: intent.baseSha`）、`lib/base/disk/disk_journal.dart:187`（`baseSha: intent.baseSha` 存盘）。
- **问题描述**：SD-01 把空串视为"无基线"，归一化变量 `baselineSha` 只用于 D1/D2′/`expectedSha`；其余四处仍比较/展示/持久化原始 `intent.baseSha`（`''`）。具体后果：① D2 的三方差异 `_threeWayFor` 用 `localBase.sha == ''` 判基线，永远为假 → `base = null`，冲突 UI 丢失"用户基于哪一版"的解释（`ConflictThreeWay.hasBase=false`、`diverged=false`）；② `WriteOutcome.baseSha` 返回 `''` 而不是 `null`，UI 把空串当"有基线但空"展示；③ Journal 记录 `baseSha: ''`，`toJson` 因 `if (baseSha != null)` 会写出 `'baseSha': ''`，重放时虽然 `_writeLocked` 再归一化能救回 D1，但所有基于 `record.baseSha` 的诊断/展示仍把"无基线"当成一个非法 sha。
- **修复前 vs 修复后行为差异**：修复前：空串基线在一致性管线里**半归一化**，冲突信息、结果契约、队列状态与 D1 的真实决策不一致；修复后：`WriteIntent` 构造即归一化空串为 null（或全链路统一用 `baselineSha`），`_threeWayFor`、`WriteOutcome`、Journal、`_fail` 拿到同一份基线值。
- **用户可见后果**：冲突对话框缺基线内容、"你的基线"显示为空白/异常串；重放记录的诊断信息误导排查。属**解释/可追溯性**缺陷，不直接造成覆盖（D1/D2 判定本身已用归一化值，故不是误放行）。
- **优先级**：P2。
- **违反原则**：9/10（状态表达一致）、17（用类型表达失败/状态，`''` 与 null 混用违反原则 52「三种不同的没有」）、16（诊断信息须如实）。
- **是否确证**：确证。代码证据：`disk_cache.dart:611-614` 定义 `baselineSha` 后，`:635-640` 仍 `shortSha(intent.baseSha)` / `baseSha: intent.baseSha`；`:833-840` `localBase.sha == intent.baseSha`；`disk_journal.dart:113` `if (baseSha != null) 'baseSha': baseSha`（空串会被写出）。
## B2-A-09 · `_saveLocal` 非原子：blob 与索引两步写，索引失败留下孤儿；`purgeOrphans` 生产从不调用（P2，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:946-950`（`_saveLocal`）、`:952-1000`（`_loadLocal` 校验）、`:1002-1005`（`_evictEncoded`）、`:483-525`（`purge`/`purgeOrphans`）、`lib/surface/surface_bridge.dart:170`（唯一生产调用 `cache?.purge()`）、`lib/domain/domain_bridge.dart:212-248`（无 prune 调用）。
- **问题描述**：① 单个文件 `IoDiskFileStore.writeText` 是原子 tmp→rename（`platform_io_impl.dart:115-139`），但 `_saveLocal` 是**两次独立原子写**：先写 blob，再写索引（含 `len`/`hash`）。若第二步失败（磁盘满、进程被杀），blob 内容完整但索引仍是旧版本（旧 `hash`/`len`/`sha`），`_loadLocal` 读到「旧索引 + 新 blob」→ 完整性校验失败 → `_evictEncoded` 把两者全删，本次已成功提交的远端内容本地缓存白写；更坏的是 blob 写完后索引还没写就被 `purgeOrphans` 之外的并发读看到旧索引+新内容，缓存被丢弃（正确性上"回源自愈"可兜底，但违反"完整生效/可恢复"）。② `_evictEncoded` 先删索引再删 blob，中间崩溃同样留下无引用 blob。③ 有 TTL 与条目上限的 `prune()` **全仓只有测试调用**（`test/base/cache_consistency_test.dart:638`），`purgeOrphans()` 只在 `purge()` 内部被调，而 `purge()` 仅由用户手动"清空仓库缓存"触发；`defaultMaxEntries=512` / `defaultMaxAge=30d` 永不生效，`_scanMetas` 之外的孤儿 blob 永久占盘。
- **修复前 vs 修复后行为差异**：修复前：索引/blob 撕裂写导致本地缓存被完整性校验整体丢弃（下次读重新回源，弱网下明显变慢/失败）；条目数与 TTL 上限形同虚设，孤儿文件只在手动 purge 时清理；修复后：`_saveLocal` 采用单一记录（或写临时索引 → 校验引用 → 提交标记）保证"要么都有、要么都无"，启动时/写后按上限执行 `prune` + `purgeOrphans`。
- **用户可见后果**：**静默失败**（缓存被无声清掉，弱网下内容读不出来）；磁盘无界增长最终写不进"用户刚写的文件"（原则 29 警示的场景）。
- **优先级**：P2（撕裂写有回源自愈，不是远端数据丢失；但磁盘有界承诺未兑现）。
- **违反原则**：13（每次写入要么完整生效，要么可恢复）、29（所有资源有上限）、15（静默丢弃须留痕；`_loadLocal` 的 `catch (_)` 静默清索引）。
- **是否确证**：确证。代码证据：`disk_cache.dart:946-950` 两次 `await` 无事务/无临时标记；`:969-980` 校验不符即 `_evictEncoded` 且仅完整性失败分支有 `error` 日志，结构异常 `catch (_)` 分支（`:993-999`）**无任何日志**；全仓 grep `.prune(` 仅 `test/base/cache_consistency_test.dart:638`；`purgeOrphans()` 仅 `disk_cache.dart:491` 被 `purge()` 调用。
## B2-A-10 · `IoDiskFileStore` 长路径收纳链路把「读失败」伪装成「不存在」，KV 索引/Journal/草稿可被静默清空（P1，确证）

- **文件:行号**：`lib/base/disk/platform_io_impl.dart:105-111`（`readText` 失败即 `_readPacked`）、`:168-186`（`_index()` / `_saveIndex` 全 catch 返回空/静默）、`:227-252`（`_readPacked` 所有异常 `catch (_)` 返回 null）、`:175-185`（`_saveIndex` 写失败静默）、`:381-398`（`IoDiskKv.read` 结构损坏 → `await _store.delete(...)` **删文件**）、`lib/base/disk/disk_journal.dart:285-295`（`records()` 解码失败 → `_store.remove(key)` 删记录）、`lib/base/disk/disk_draft.dart:140-153` / `:200-215`（草稿解码失败 → `_store.remove` 删记录）。
- **问题描述**：Windows 长路径回退把内容收进 `TooLongRoad_*.zip`，能否读回**完全依赖 `.ogl_toolong.json` 索引**。该索引本身用普通 `writeAsString`（非原子、无 fsync、无备份），且 `_index()` 对 IO 失败/JSON 坏数据一律返回空 Map，`_saveIndex` 对写失败完全静默，`_readPacked` 对 zip 损坏/UTF-8 错误一律返回 `null`。`readText` 只要普通文件不存在就走 `_readPacked` 并返回 `null`，上层 `IoDiskKv.read` 得到 `null` 后：Journal `records()` 认为"没有这条记录"、DraftStore `_loadUnlocked` 认为"没有草稿"、缓存 `_scanMetas` 认为"没有索引"；更糟的是 `IoDiskKv.read` 的 catch 分支和 Journal/Draft 的损坏分支会**主动 delete 掉对应键**，把一次"读不出来"升级为"数据被删除"。
- **修复前 vs 修复后行为差异**：修复前：磁盘/索引暂时不可读时，用户的**未提交草稿、待同步 Journal 记录、缓存索引被当成损坏而删除**，重启后"待同步"列表空、草稿消失；修复后：读失败必须与"键不存在"区分（抛异常或返回显式状态），任何删除只在确证结构损坏且先留痕/备份后进行，索引写失败大声上报。
- **用户可见后果**：**未提交的用户编辑内容丢失、待同步写入被静默丢弃**（原则 8「缓存、草稿、日志都可以丢，用户写的内容不能丢」），且无告警（静默失败）。
- **优先级**：P1（触发条件较窄：Windows 长路径/索引损坏，但一旦触发丢的是用户内容）。
- **违反原则**：8（用户写的内容不能丢）、15/16（静默降级/不吞异常）、20（外部数据不可信，坏数据夹紧回默认并**记录**）、13（半成品状态必须留痕）。
- **是否确证**：确证。代码证据：`platform_io_impl.dart:105-111` `if (await file.exists()) return ...; return _readPacked(path);`；`:168-174` `catch (_) { return <String,String>{}; }`；`:245-250` `catch (_) { ... } return null;`；`:175-185` `_saveIndex` catch 内空注释无日志；`disk_journal.dart:289-293` `if (record == null) { await _store.remove(key); continue; }`（注释仅称"结构损坏"，实际包含 IO 读失败）。
## B2-A-11 · `sweepTemp().failed` 被丢弃，"失败项不静默吞掉，交由调用方诊断"的契约未兑现（P2，确证）

- **文件:行号**：`lib/base/disk/platform_io_impl.dart:336-359`（`sweepTemp` 返回 `(removed, failed)`，注释明确"失败项不静默吞掉，交由调用方诊断"）、`:519-526`（`PlatformStorage.open` 三处 `await files.sweepTemp();` 均丢弃返回值）。
- **问题描述**：启动清扫对删除失败的 `.tmp` 收集了 `failed` 列表，但 `open()` 三次调用都不读返回值、不写日志、不上报诊断；由于 `PlatformStorage.open` 无 `KernelDiagnostics` 注入点，`baseLayerModulesOnPlatform` 也只在 `open` **抛异常**时才有 `storageError`，清扫失败属于"部分失败"路径，永远不会触发 `main.dart:232` 的告警。残骸 `.tmp` 会留在目录里（虽然 `list()` 过滤 `.tmp`，不影响正确性，但磁盘无界增长且失败不可见）。
- **修复前 vs 修复后行为差异**：修复前：清扫失败完全静默，用户/诊断日志都不知道；修复后：`open` 聚合三次 `failed` 并以返回值/异常/诊断回调上送，组合根按 `storageError` 同等大声上报。
- **用户可见后果**：静默失败（磁盘残骸累积，最终可能占满空间导致写草稿/日志失败），且排障时无线索。
- **优先级**：P2。
- **违反原则**：15（静默降级最严重）、16（捕获异常必须转成结果或告警）、29（资源有界）。
- **是否确证**：确证。代码证据：`:336` 返回类型 `({int removed, List<String> failed})`、注释 `:334`；`:523-525` `await files.sweepTemp();` 三行无赋值；`lib/base/base_bootstrap.dart:28-37` 只有 `catch (error)` 才上报。
## B2-A-12 · `failByKey` 按"最近一条 pending"标注，多 pending 交错时标错记录导致过早 abandon（P2，确证）

- **文件:行号**：`lib/base/disk/disk_journal.dart:243-258`（`failByKey`）、`:217-230`（`fail` 第 5 次转 `abandon`）、`lib/base/disk/disk_cache.dart:265-278`（`write()` 异常路径统一 `failByKey`）、`disk_cache.dart:665-668`（每次 `write` 都先 `enqueue` 一条新 pending）。
- **问题描述**：同一 key 允许存在多条 pending（注释自认："A 崩了、B 又崩了"）。`failByKey` 用 `createdAt.isAfter(newest.createdAt)` 选"最近一条"，但 `_nextId()`（`disk_journal.dart:324`）用的是 `DateTime.now().microsecondsSinceEpoch` + 进程内序号；系统时钟回拨/同一微秒内多条记录时排序不严格。更关键的是 `write()` 的 catch **不区分异常发生在哪一步**：若 `_journal!.enqueue(intent)` 自身抛异常（磁盘满/IO 错误）或 `bindRemote` 前 `UnavailableCacheRemote` 抛 `StateError`，异常发生在**本次 pending 落盘之前**，`failByKey` 仍会给队列里**另一条历史 pending** 记一次失败；累计 5 次后该历史记录被 `abandon`（`fail` 内 `attempts >= maxAttempts`），用户排队的旧写入被静默放弃。反之若本次 enqueue 成功但异常发生在 D5 之后，也可能因时间戳并列标到别的记录。
- **修复前 vs 修复后行为差异**：修复前：一次与某记录无关的失败会消耗另一条记录的"重试次数"，5 次后把用户待同步内容标记 abandoned；修复后：`write()` 只在确知 `journalRecord.id` 时按 ID 标注（`_fail` 已支持 `journalId` 参数），异常发生在入队前则只记诊断、不动队列。
- **用户可见后果**：**排队中的用户写入被静默放弃**（数据丢失/静默失败）；"待同步"计数突然减少且无对应通知。
- **优先级**：P2（需多条 pending + 5 次异常，触发链较长）。
- **违反原则**：13（可恢复事务的记录不能被误标终态）、16（异常归属必须精确，原则 18 捕获范围精确到能处理的异常）、15（放弃必须可感知）。
- **是否确证**：确证。代码证据：`disk_cache.dart:269-273` `await _journal?.failByKey(intent.key, ...)` 无论 `journalRecord` 是否创建；`disk_journal.dart:219-227` `fail` 内 `if (attempts >= maxAttempts) { await abandon(...); return; }`；`:243-258` 仅按 `createdAt` 选一条；`:324` `_nextId()` 无严格单调保证。
## B2-A-13 · D5「回读失败按已提交待确认」把本地缓存写成"未经回读确认"的权威条目（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:686-712`（PUT 成功后 D5）、`:758-770`（`_verifyReadback` 返回 `null`）、`:693-701`（`verified ?? RemoteDocument(content: content, sha: written.sha)` → `_entryOf` → `_saveLocal`）、`lib/domain/gh/gh_api.dart:552-590`（`content()` 读穿透优先用本地缓存，`maxAge: 30s`）。
- **问题描述**：注释声称"回读失败 → 视为已提交（待确认），**缓存失效靠下次读取自愈**"，但代码在 `_verifyReadback` 返回 `null` 时**并未保持缓存失效**，而是立刻用 PUT 响应体 `written.sha` + 本次 `content` 造一个 `CacheEntry` 并 `_saveLocal(entry)`，写入带完整 `len`/`hash` 凭据的本地索引。于是 `_loadLocal` 的完整性校验只会验证"这段内容自洽"，**无法发现它与远端不一致**：若 PUT 实际未生效（206/代理改写响应/服务端异步可见性）、或 `written.sha` 不是远端最终版本，`content()` 在随后 30s TTL 内会优先命中这条伪造条目（`gh_api.dart:558-561`），把未经远端确认的内容当作权威数据展示给用户，并成为下一次编辑的 `baseSha`。注释与实现自相矛盾，"待确认"状态在类型上也不存在（没有 `WriteOutcome.pendingVerification`，仍是 `ok: true`）。
- **修复前 vs 修复后行为差异**：修复前：回读失败时本地被写入"假定成功"的缓存，30 秒内用户读到可能与远端不同的内容并以其 sha 起草下一次写；修复后：回读失败时保持缓存失效（只 `_evictEncoded` + 记 WARN + 返回带"待确认"标记的结果类型），下次 `content()` 回源拿权威版本；提交结论与缓存结论分离。
- **用户可见后果**：**写歪**（编辑器基线来自假 sha，下一次保存被 D2 拦成 `staleSha` 或以错误基线覆盖）、显示与远端不一致却无提示（静默失败）。
- **优先级**：P1。
- **违反原则**：22（每个异步结果都要校验是否仍然有效）、42（失败如实报错，伪造的成功响应更难排查）、15（待确认状态必须可感知）、13。
- **是否确证**：确证。代码证据：`disk_cache.dart:693-701` `verified ?? RemoteDocument(content: content, sha: written.sha)` 后无条件 `:702` `await _saveLocal(entry)`；`:758-770` 回读不一致/异常时返回 null；`gh_api.dart:558-561` `await _cache!.read(key, refresh: refresh, maxAge: _contentMaxAge)` 命中即直接返回 `entry.sha`。
## B2-A-14 · `replayPending` 与在线 `write` 并发重放同一条记录：重复提交 / 记录状态倒退（P1，确证）

- **文件:行号**：`lib/domain/domain_bridge.dart:206-248`（启动一次 `unawaited(replayPending())` + 每 30s `Timer.periodic` 又一次）、`lib/base/disk/disk_cache.dart:439-465`（`replayPending` 先取快照再逐条 await，无"重放中"闸门）、`disk_cache.dart:178-190`（`WriteJournal.enqueue` 无去重/无上限）、`disk_cache.dart:704-708`（成功才 `complete`）。
- **问题描述**：`replayPending` 在 `onRegister` 中同时被"立即启动一次"和 30s 定时器触发，二者之间没有互斥；每次都先 `await journal.records(status: pending)` 拿快照再逐条 `await write(...)`（内含 D1 远端读、PUT、D5 回读，可能耗时数十秒）。两次重放可以对**同一条 record.id** 各自走完整写链路：D4 逐键锁只能保证两次 PUT 串行，不能保证"只有一次成功"——后到的重放仍带着记录里的旧 `baseSha`，若远端已被第一次重放推进，D2 会拦成 `staleSha` 并把**已经 complete（删除）的记录**再 `abandon`/`fail`（`complete` 后 `_read(id)` 为 null，`abandon` 静默返回，尚不致命），但若两次都在 D1 读到旧远端版本前完成读、或第一次因网络失败尚未 complete，就会发出**两次相同 PUT**，产生重复提交。此外 `replayPending` 的 `recordJournal: false` 与"运行中每 30s 重放"叠加，队列在失败时由 `failByKey` 标注的是"最近一条"，可能把重放中的记录误标（与 B2-A-12 叠加）。
- **修复前 vs 修复后行为差异**：修复前：同一 pending 可被并发重放、重复 PUT、重复通知；修复后：重放有进程级/记录级 lease（标记 replaying、完成后再释放），或定时器与启动重放共用一个串行队列并按 id 去重。
- **用户可见后果**：**重复提交**（GitHub 历史里两条相同 commit，或以旧内容二次写歪）、"待同步"角标与通知计数抖动、静默失败。
- **优先级**：P1。
- **违反原则**：26（写要么幂等要么防重）、13（恢复事务不能重复生效）、23（互斥闸门属于同一所有者）、22（过期回调必须丢弃）。
- **是否确证**：确证。代码证据：`domain_bridge.dart:211` `Timer.periodic(...)` 内 `base.disk.cache.replayPending()`；`:240-248` `unawaited(base.disk.cache.replayPending()...)` 在注册阶段立即启动；`disk_cache.dart:444` `for (final record in await journal.records(...))` 快照后 `:447` `await write(...)`；全仓无 `_replaying` / lease 字段。
## B2-A-15 · 跨账号 scope：Journal 重放与草稿清理不校验当前账号，切号后旧账号 pending 被用新账号令牌提交（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:439-465`（`replayPending` 遍历**全部** pending，无账号过滤）、`lib/base/disk/disk_journal.dart:285-300`（`records()` 只按 `namespace` 前缀，无 scope 过滤）、`lib/domain/domain_bridge.dart:206-248`（装配后无条件重放）、`lib/surface/surface_bridge.dart:188-210`（`forgetAccount` / `clearAllCaches` 只 purge 仓库缓存、只读缓存、`clearAllDrafts()`，**不清 Journal**）、`lib/domain/gh/gh_api.dart:2001-2007`（`CacheRemote.write` 只用 `key.scope.repo/branch/path`，令牌来自当前 `GhClient` 的激活账号）。
- **问题描述**：`CacheKey.scope.accountId` 让本地缓存/草稿按账号隔离，但 `WriteJournal` 的记录键是 `ogl.journal.<id>`，重放时不比较 `record.key.scope.accountId` 与当前 `auth.activeAccountId()`；`GhApi.write` 也从不用 `key.scope.accountId` 选择令牌，一律用当前激活账号。于是：账号 A 排队一条写私有仓库 `A/priv/repo` 的 pending（网络断/被杀）→ 用户切到账号 B → 启动/30s 自动重放用 **B 的令牌**去写 A 的仓库：若 B 无权则得到 `forbidden`/`server`（反复重试直到 `maxAttempts=5` 转 abandoned，队列被静默清空），若 B 恰好有协作权限则**用 B 的身份把 A 的内容提交到 A 的仓库**，提交作者与用户预期不符；反之若 A 的草稿/待办在切号后仍显示（`clearAllDrafts` 清的是全部草稿，`forgetAccount` 才调它，普通切号 `switchTo` 路径未清），用户会在 B 的界面里看到 A 的待同步项。
- **修复前 vs 修复后行为差异**：修复前：Journal 记录跨账号"漂"，自动重放使用错误身份；切号/注销不清理属于被移除账号的 pending；修复后：重放前按 scope 过滤（或记录绑定账号并在重放时显式校验/要求用户选择账号），`forgetAccount` 一并废弃该账号的 pending。
- **用户可见后果**：**写歪**（错误身份提交）、静默失败（反复失败后记录被 abandon）、跨账号数据串味（原则 28 缓存键必须覆盖全部差异维度）。
- **优先级**：P1。
- **违反原则**：28（键必须覆盖产生差异的全部维度）、22（过期回调/过期意图必须丢弃）、39/40（凭证只在必要跳使用）、15（跨账号失败必须可感知）。
- **是否确证**：确证。代码证据：`disk_cache.dart:444` `for (final record in await journal.records(status: JournalStatus.pending))` 无账号判断；`gh_api.dart:1993-2007` `write` 直接 `putContent(repo, key.path, ...)`，令牌由 `client`（`domain_bridge.dart:157-161`）按 `auth` 当前态取；`surface_bridge.dart:188-210` `clearAllCaches()` 无 `journal.clear()`（全仓 grep `journal.clear` 无生产调用）。
## B2-A-16 · 平台存储解析失败退回内存但仍照常绑定 API 写远端，本次会话的用户写入/草稿重启即失忆（P1，确证）

- **文件:行号**：`lib/base/base_bootstrap.dart:20-41`（catch 后 `baseLayerModules(net: net)`，DiskModule 缺省 `InMemoryKv`/`InMemoryFileStore`）、`lib/base/disk/disk_bridge.dart:66-80`（`DiskModule` 缺省全内存）、`lib/base/disk/platform_io_impl.dart:546-563`（真实磁盘才是 `toDiskModule()`）、`lib/main.dart:231-244`（仅日志 + 通知中心告警）、`lib/domain/domain_bridge.dart:165-170`（照常 `bindRemote(api)` / `attachReadCache`）、`:206-248`（照常自动重放）。
- **问题描述**：链路确实"大声上报"（`OgLNoticeCenter.instance.report` critical 弹窗 + 应用日志），这一点合格；但从**数据正确性**看，降级后没有任何"拒绝写 / 只读模式"闸门：`RepositoryCache` 用 `InMemoryKv` 索引/内存 blob，`WriteJournal`、`DraftStore` 全部内存实现，`GhApi` 仍被绑定为远端并可正常 `putContentLocked`。用户在这段时间编辑、提交：远端写入可能成功，但 D8 pending（崩溃恢复依据）、D9 草稿（用户敲的字）都在内存里，App 被杀 / 重启即全部消失；若写在 PUT 前被中断，恢复记录根本不在磁盘上。告警文案说"登录与设置将无法保存到本机"，未覆盖"草稿/待同步队列同样不落盘"，用户被告知的后果小于实际后果。
- **修复前 vs 修复后行为差异**：修复前：存储不可用时应用以"内存一致性层"继续接受用户写入，重启后未完成的提交与草稿永久丢失，且用户只看到一次弹窗；修复后：降级时把磁盘依赖的写入能力置为只读/明确拒绝（或在类型上返回"存储不可用"结果），并把告警文案覆盖草稿与待同步队列，退出条件为存储恢复后重新装配。
- **用户可见后果**：**用户写的内容丢失**（原则 8 底线）、静默失败（弹窗关闭后无任何持续标识）。
- **优先级**：P1（链路"大声上报"部分正确，故不是 P0；但降级无退出条件/无写入闸门）。
- **违反原则**：8（用户写的内容不能丢）、13（写入要么完整生效要么可恢复）、21（降级路径必须有触发条件、观测、**退出条件**）、15（失败的用户可见后果必须完整）。
- **是否确证**：确证。代码证据：`base_bootstrap.dart:36-40` `catch (error) { return (modules: baseLayerModules(net: net), storageError: error); }`；`disk_bridge.dart:70-77` `kv ?? InMemoryKv()` 等；`main.dart:236-243` 仅 report 一次；`domain_bridge.dart:167` 无条件 `base.disk.cache.bindRemote(api)`。
## B2-A-17 · D7 force 二次确认在实现上不可达：生产调用从不传 `force: true`/`confirmed: true`，冲突对话框的"强制覆盖"没有落到写链路（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:594-606`（`(intent.dangerous || intent.force) && !confirmed ⇒ needsConfirmation`）、`lib/domain/gh/gh_api.dart:841-921`（`putContentLocked` 的 `force`/`confirmed` 形参）、`lib/kernel/contract/disk_types.dart:243-258`（`resolveConflictActions` 对 `staleSha` 返回 `forceOverwrite`）、`lib/domain/ix/ix_conflict.dart:240-246`（"强制覆盖"选项）、`lib/surface/pages/code_editor_page.dart:232-238`、`lib/surface/pages/repo_page.dart:3812-3818`（两处生产调用均不传 force/confirmed）。
- **问题描述**：契约层把 `forceOverwrite` 作为 `staleSha` 的合法处置（`resolveConflictActions`），UI 也有"强制覆盖（对方的修改会丢失）"选项，但全仓 `putContentLocked` 的两个生产调用点都只传 `content/message/baseSha/branch`，`force` 与 `confirmed` 永远为默认 `false`；`replayPending(confirmed: true)` 只在测试里出现（B2-A-06）。因此 D7 的"确认 → force → 以刚读到的远端 sha 为期望值重提交"这条正路**在生产中从未被走过**：用户点强制覆盖后（若 UI 有接线）要么什么都没发生，要么被再次 D2 拦成 `staleSha`，形成死循环。同时 `force` 分支的语义是"跳过 D2 但仍带 `latest.sha`"（`disk_cache.dart:673`），本身合理，却因无调用者而成为死代码。
- **修复前 vs 修复后行为差异**：修复前：冲突后用户无法完成显式确认的强制覆盖，写入永久失败/重复弹冲突；修复后：冲突编排把用户决策映射为 `putContentLocked(force: true, confirmed: true)`（且确认在类型上表达，见 `IxBatchDecision`/`IxConfirmationRequired`），引擎按 `latest.sha` 提交并全程留痕。
- **用户可见后果**：**静默失败 / 功能不可用**：用户明确选择"覆盖"后内容仍未提交，草稿可能被当成未提交内容反复出现；D7 二次确认形同虚设（另一面：若将来有人只传 `force: true` 而不传 `confirmed`，D7 会正确拦住，故风险主要是"防线不可达"而非"绕过"）。
- **优先级**：P1。
- **违反原则**：12（危险操作确认必须在类型上表达并可达）、17（用类型表达失败，调用方无法忽略）、55（死代码零容忍）、11（防线没有开关——不可达等价于没有）。
- **是否确证**：确证。代码证据：全仓 grep `force: true` / `confirmed: true` 在 `lib/` 中仅 `HttpClient.close(force: true)`、测试中的 `replayPending(confirmed: true)`；`gh_api.dart:907-915` `WriteIntent(... force: force, rebase: rebase)` + `confirmed: confirmed` 是唯一入口，两个 UI 调用点实参不含该字段。
## B2-A-18 · 同一 key 并发写时 `_KeyedMutex` 吞掉前序失败且只在 `read()` 接线诊断；`write()` 路径的失败无留痕（P2，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:98-125`（`_KeyedMutex.run`）、`:237`（`_wireMutexDiagnostics()` **只在 `read()` 内调用**）、`:539-550`（接线实现）、`:257`（`write()` 直接 `_mutex.run`，不接线）、`:286`（`invalidate` 同）、`:301`（`delete` 同）。
- **问题描述**：`_KeyedMutex.run` 在 `await previous` 抛异常时只执行 `onPreviousFailed?.call(...)` 然后继续本任务（注释称"swallow 是有意的，但完全静默会让排查无从下手"）。然而 `onPreviousFailed` 由 `_wireMutexDiagnostics()` 惰性设置，而该方法**仅被 `read()` 调用**。若应用启动后第一次操作是 `write`/`delete`/`invalidate`（或 journal 的重放，`replayPending → write` 发生在 domain 装配阶段、任何 read 之前），`onPreviousFailed` 为 null：前序写失败（如 D6 之外的 `CacheScopeException`/`CacheKeyException` 会 rethrow 出锁）被完全吞掉，后序写照常执行，用户不知道"上一发为什么没生效"。此外 `_diagnostics` 在 `attachDiagnostics()` 之后被替换，但 `_mutexWired` 一旦置 true，回调闭包捕获的是**旧 diagnostics 实例**（闭包内用 `_diagnostics.debug` 读字段，实为动态读取当前字段，这一点不算错，但接线本身只发生一次且依赖 read 先发生）。
- **修复前 vs 修复后行为差异**：修复前：纯写会话/启动重放中的前序失败无审计；修复后：`_wireMutexDiagnostics()` 在构造函数或所有公开入口调用，且前序失败折成 WARN 级事件码（无论首个操作是读还是写）。
- **用户可见后果**：静默失败（后序写以过期状态继续执行，事故后日志无线索），排障困难。
- **优先级**：P2。
- **违反原则**：16（捕获后不重新抛出必须转成结果或告警）、15（静默降级）、27（并发假设写进注释——注释承诺"留痕"却未全路径兑现）。
- **是否确证**：确证。代码证据：`grep _wireMutexDiagnostics` 仅 `:237`（read 内）与 `:539`（定义）；`:113-115` `catch (error) { onPreviousFailed?.call(key, error); }`；`write()` `:257` 之前无接线。
## B2-A-19 · D4 逐键锁只保护"引擎内部"，`prune`/`purge`/`purgeOrphans` 的扫描与 `_evictIfStale` 无全局闸门，且 `prune` 从锁外调用会与自身 `_mutex.run` 冲突（待议，P2）

- **文件:行号**：`lib/base/disk/disk_cache.dart:391-425`（`prune`）、`:483-500`（`purge`）、`:506-525`（`purgeOrphans`）、`:1015-1029`（`_evictIfStale` 内部 `_mutex.run(encoded, ...)`）、`:903-920`（`_scanMetas`）。
- **问题描述（待议）**：① `prune`/`purge` 的 `_scanMetas()` 在**所有键锁之外**枚举 KV；`purgeOrphans()` 直接用 `_blobs.list('cache')` 得到的文件名集合判定孤儿，且在 `_evictEncoded` 之外**直接 `_blobs.delete`**（`:521`），对同一 blob 的并发 `_saveLocal` 无锁保护：若 A 正在 `_saveLocal` 写 blob（索引尚未写）、B 正在 `purgeOrphans`，B 会把 A 刚写的 blob 当孤儿删除，A 随后写索引成功 → 索引在、blob 丢 → `_loadLocal` 自愈清索引（缓存丢失，非远端数据）。② `_evictIfStale` 对每个 encoded 单独加锁，锁的是 `encoded` 字符串，而 `write`/`read` 锁的是 `key.encode()`——两者一致（`encoded` 来自 meta key），这部分正确；但 `prune` 若被从某个键锁内调用（例如未来在 `_readLocked` 里触发淘汰），会因 `_mutex.run` 等待自身而自锁（当前生产无此调用，故标待议）。
- **修复前 vs 修复后行为差异**：修复前：手动清缓存/孤儿与并发读写交错时可能删掉刚写入的 blob，且 `purge()` 会删掉**所有**索引（包括正在写的事务中间态）；修复后：淘汰/清理与写入共用同一把键锁或全局 maintenance 锁，孤儿判定基于"索引集合 + 进行中写集合"。
- **用户可见后果**：本地缓存静默丢失（弱网下内容读不出来/多一次回源），不直接丢用户写的内容（远端/JOURNAL 不受影响）。
- **优先级**：P2。
- **违反原则**：23（互斥闸门成对且属于同一所有者）、22（过期结果须丢弃）、29。
- **是否确证**：**待议** —— 代码层面确证"无锁"（`purgeOrphans` 直接 `_blobs.delete`、`_scanMetas` 锁外），但是否构成用户可见事故取决于调度时序，且 `prune` 生产未接线（B2-A-09），`purge` 仅手动触发；自锁场景当前无调用者，属潜在缺陷而非现网必现。
## B2-A-20 · 生产写路径存在三处「绕过一致性引擎」的裸 `putContent`/`deleteContent`，D1–D9 全被跳过（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:765-830`（`putContent` 裸写，注释自称供 CacheRemote.write 使用）、`lib/domain/gh/repo_file_service.dart:671-677`（create 直接 `api.putContent`，无 `baseSha` 参数）、`repo_file_service.dart:756-761`（delete 直接 `api.deleteContent`，只带 `expectedFileSha`）、`lib/surface/pages/repo_page.dart:3803-3808`（CNAME 新建直接 `putContent`，无 baseSha）、`lib/domain/gh/gh_api.dart:1530-1534`（`writeCname` 裸写）、`gh_api.dart:841-850`（`putContentLocked` 才是 D1–D9 入口）。
- **问题描述**：AGENTS.md §5 声称"缓存一致性七道防线……**无绕过开关**"，但这些公开 API 让 UI/服务层完全绕过 `RepositoryCache.write/delete`：没有 D1 写前必读（create 用一次 `probe` 探测后不带 sha PUT，探测与写入之间仍可被别人创建）、没有 D2 乐观锁（不带 sha 的 PUT 对已存在路径是覆盖）、没有 D3/D4 串行、没有 D5 回读、没有 D7 二次确认（删除无 confirmed）、没有 D8 Journal（崩溃即丢）、没有 D9 草稿收尾（提交成功后不清同 key 草稿）。尤其 `repo_page.dart:3803` 的 CNAME 新建分支与 `writeCname` 都是"无基线创建"，与 D1 刚改的"远端不存在+无基线=合法新建"叠加，正是 B2-A-04/05 所描述的并发覆盖入口。
- **修复前 vs 修复后行为差异**：修复前：创建/删除/CNAME 写入跳过全部防线，失败以异常外抛，崩溃后无法恢复，草稿残留；修复后：所有写统一经 `putContentLocked`/`deleteContentLocked`（或引擎直接暴露 write/delete），裸网络写降为 private 且只由 `CacheRemote.write/delete` 调用。
- **用户可见后果**：**并发写歪/覆盖（数据丢失）**、危险删除无确认、提交后旧草稿复活、崩溃时提交静默丢失。
- **优先级**：P1。
- **违反原则**：11（防线没有开关，无绕过捷径）、9/10（先读后写、乐观锁）、12（危险操作二次确认）、13/14（写前落盘意图、成功后清除记录）。
- **是否确证**：确证。代码证据：`repo_file_service.dart:671` `await api.putContent(... content: content, message: ..., branch: ref)` 实参无 `baseSha`；`repo_file_service.dart:756` `await api.deleteContent(...)` 无 `confirmed`；`repo_page.dart:3803-3808` `await ...api.putContent(_full, 'CNAME', ...)` 无 baseSha；`gh_api.dart:841` 的 `putContentLocked` 是唯一经 `cache.write` 的路径。
## B2-A-21 · D9 草稿 `save()` 的 `baseSha` 缺省沿用旧值：远端已推进/新建→已有后，草稿仍持过期或空基线（P1，确证）

- **文件:行号**：`lib/base/disk/disk_draft.dart:162-178`（`save`：`baseSha: baseSha ?? existing?.baseSha`）、`lib/domain/gh/gh_api.dart:376-390`（`saveDraft` 直接透传）、`lib/surface/pages/code_editor_page.dart:168-189`（`_persistDraft` 传 `_draftBaseSha ?? widget.baseSha`）、`code_editor_page.dart:197-211`（`_save` 用同一 `_draftBaseSha` 作为提交基线）、`lib/base/disk/disk_cache.dart:704`（写成功后 `_drafts?.discard`）。
- **问题描述**：草稿的 `baseSha` 语义应是"起草时基于的远端版本"，但 `DraftStore.save` 在 `baseSha == null` 时**沿用已有草稿的旧基线**。新建文件场景：用户第一次以 `baseSha=''` 编辑并保存草稿，随后文件被他人（或本应用另一入口）创建；用户回来继续编辑，`_restoreDraft` 读到 `draft.baseSha == ''`，`_persistDraft`/`_save` 继续用 `''` 作为无基线提交 → 触发 D1「远端已存在+无基线拒绝」或更糟（若远端读被折成 null，见 B2-A-05）覆盖刚创建的文件。已有文件场景：草稿跨多次会话保留，而远端已被别人推进；编辑器打开时 `widget.baseSha` 是**新的**远端 sha，但 `_restoreDraft` 把 `_draftBaseSha` 覆盖成草稿里的**旧** sha，`_save` 于是用旧基线提交，D2 拦成 `staleSha`（可恢复，但用户被迫手工处理，且三方差异的 base 因 B2-A-08 丢上下文）。此外 `save()` 的 `copyWith` 无法显式把 baseSha 清成 `null`（`baseSha ?? existing` 使 null 表示"沿用"而不是"无基线"）。
- **修复前 vs 修复后行为差异**：修复前：草稿基线可能永久停留在起草那一刻，用户恢复草稿后以过期/空基线提交；修复后：恢复草稿时以当前远端版本为准重新绑定基线（或明确保留旧基线并给出冲突差异/要求用户重新拉取），`save` 区分"未提供"与"显式清空"。
- **用户可见后果**：**写歪/覆盖**（新建→已有）、反复 `staleSha` 提交失败（静默失败感），用户恢复的草稿内容与基线不匹配。
- **优先级**：P1。
- **违反原则**：9（写前必读、基线必须对应当前状态）、10（乐观锁必须看见并发）、22（过期结果必须丢弃）、8（用户写的内容不能因基线错误而丢）。
- **是否确证**：确证。代码证据：`disk_draft.dart:170-175` `baseSha: baseSha ?? existing?.baseSha`；`code_editor_page.dart:145-150` `_draftBaseSha = draft.baseSha;`；`:206` `final String baseSha = _draftBaseSha ?? widget.baseSha;` 与 `:232-238` 传入 `baseSha`。
## B2-A-22 · D8 `abandoned` 是静默终态：无任何 UI/通知消费 Journal，`pendingCount` 生产无调用者（P1，确证）

- **文件:行号**：`lib/base/disk/disk_journal.dart:260-275`（`abandon` 只写 `status: abandoned` + diagnostics.warn）、`:285-300`（`records()` 默认返回全部，UI 可查）、`lib/base/disk/disk_cache.dart:459-462`（`replayPending` 把语义冲突 `abandon`）、`:806-822`（`_fail` 对非 retryable 一律 `journal.abandon`）、`lib/domain/domain_bridge.dart:206-248`（只自动重放 pending，只把结果写 diagnostics.info）、`lib/surface/` 全目录（grep `pendingCount|journal|待同步` 无 UI 消费点）。
- **问题描述**：D8 状态机有 `pending / abandoned`，`complete` 是删除记录。语义性冲突（`staleSha`/`forbidden`/`notFound`/`requiresRead`）发生时，`_fail` 把记录标为 `abandoned` 并**移出 pending 集合**；此后 `replayPending` 只看 pending，30s 定时器不再触碰它；全仓没有任何界面读取 `records(status: abandoned)` 或 `pendingCount()`（后者只在 `disk_bridge.dart:154` 装配日志里出现一次）。诊断中枢有一条 WARN，但 `OgLDiagnosticsNoticeSink` 只在 warn/error 时转通知中心——`abandon` 用的是 `_diagnostics.warn(...)`，理论上能弹横幅，但内容只有"提交已放弃（需用户重新决策）"，**没有提供重新决策的入口**，且用户在编辑器里点保存后已 `Navigator.pop`（`code_editor_page.dart:212`），后台结果只走通知/应用日志（`_submitInBackground`）。结果：用户排队的写入内容仍留在 Journal 记录里，但既不再提交、也不再出现在"待同步"、更没有恢复入口，等于静默丢弃。
- **修复前 vs 修复后行为差异**：修复前：冲突/权限失败后记录进入不可见终态，用户以为"稍后会自动重试"；修复后：abandoned 记录必须有 UI 列表 + 恢复/放弃操作（附带三方差异），或 `abandon` 时把内容转存为草稿并发出可操作通知。
- **用户可见后果**：**用户写的内容静默丢失**（原则 8 底线）；提交失败提示短暂，之后无任何可找回路径。
- **优先级**：P1。
- **违反原则**：13（半成品状态必须留痕并**能被重启发现/用户处理**）、15（失败必须用户可感知）、17（用类型表达失败，让调用方无法忽略）、14（删除前落盘意图、成功后清除记录）。
- **是否确证**：确证。代码证据：全仓 grep `pendingCount` 仅 `disk_journal.dart:303`（定义）、`disk_journal.dart:193`（enqueue 日志）、`disk_bridge.dart:154`（启动日志）、`test/`；`abandon` 后 `records(status: pending)` 不再返回该记录；`disk_cache.dart:459-462` `await journal.abandon(record.id, reason)` 无后续通知。
## B2-A-23 · D6「永不外抛」被 `write()` 的两类异常显式 rethrow 破坏；`delete()` 也不保护 `_remote.read` 的非冲突异常（P2，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:248-278`（`write` 文档承诺"永不外抛（除非法键）"，但 `:264-268` `on CacheScopeException/CacheKeyException { rethrow; }`）、`:301-360`（`delete` 的 `try` 只 `on RemoteConflictException` + 通用 `catch`，没有 D8/诊断接线）、`:365-372`（delete 通用 catch 直接 `_fail` 但无 `_diagnostics`？`_fail` 有记录，故仅记录级别问题）。
- **问题描述**：① `write()` 的注释把"非法键"列为唯一外抛例外，但 `_ensureKey`（`:875-888`）在**锁外**同步抛异常本就属于编程错误（可接受）；真正的问题是 `_writeLocked` 内部 `CacheRemote.read/write` 的实现（`GhApi.read` 在 403/401 抛 `GhAuthException`，不是 `CacheScopeException`）会落进通用 catch → 转 server，符合 D6；但若未来任何远端/存储实现抛 `CacheKeyException`（例如 `IoDiskFileStore.abs()` 的 `ArgumentError` 之外构造的非法键异常），会被 `rethrow` 出引擎，UI 收到未结构化异常，`putContentLocked` 的 `GhWriteResult` 契约破裂。更直接的是 `write()` 的 `await _journal?.failByKey(...)` 若自身抛异常（磁盘故障），**在 catch 块内没有二次保护**，异常直接外抛且 `_fail` 不执行 → 违反 D6。② `delete()` 的 `_remote.read` 抛普通异常时落到通用 `catch` 返回 server，但**不写 Journal**（delete 有意不入 journal）、不记 `lastError`、也不接诊断（仅 `_fail` 的 error 日志），相对写路径少一层留痕。
- **修复前 vs 修复后行为差异**：修复前：Journal 自身故障/特定异常类型时写操作抛异常而非返回 `WriteOutcome`，调用方（`putContentLocked`）不 catch → 异常冒泡到 UI；修复后：所有 catch 分支内的清理动作也包 try/catch 并转成结果，rethrow 只保留真正的编程错误（且文档与实现一致）。
- **用户可见后果**：静默失败/未处理异常（保存流程崩溃、无结果通知），排障困难。
- **优先级**：P2（触发需要 Journal 存储故障或特定异常类型）。
- **违反原则**：17（用类型表达失败，让调用方无法忽略）、16（捕获范围精确）、18（"兜底一切"的 catch 是 bug 藏身处——此处 catch 内又有可抛操作）、AGENTS.md §3「一致性引擎返回 WriteOutcome 不外抛」。
- **是否确证**：确证。代码证据：`disk_cache.dart:272` `await _journal?.failByKey(...)` 位于 `catch` 内且无保护；`:264-268` 两个 `rethrow`；`:273-277` `_fail(...)` 在该 await 之后；`gh_api.dart:841-850` 文档声称"永不抛"但调用 `cache.write` 时未包 try/catch。
