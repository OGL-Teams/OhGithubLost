# 功能交叉审计 · 批 1-B · 缓存一致性

> **更新时间 / Last Updated**：2026-11-23 06:43:01（Asia/Shanghai，设备本地时间）/ 对应版本 **v15.0.0**
> 审计对象：`/root/OhGithubLost` · 审计范围：`lib/base/disk/` 全部 13 文件 + `lib/domain/gh/gh_read_cache.dart` + `lib/kernel/contract/consistency_cache.dart` + `lib/domain/ix/ix_conflict.dart`（连同其依赖的 `kernel/contract/disk_types.dart` / `disk_store.dart` 一并核对）
> 纪律：只读审计（未改任何 `lib/` 代码、未 commit/push）；唯一产出本文件。所有行号均可 `rg -n` 复现。

---

## 问题总览

| 级别 | 数量 | 编号 |
| --- | --- | --- |
| P0（数据丢失 / 崩溃 / 安全） | 1 | 1B-01 |
| P1（功能失效 / 不一致） | 6 | 1B-02 ～ 1B-07 |
| P2（打磨） | 4 | 1B-08 ～ 1B-11 |

---

## 严重（P0）

### 1B-01 · 冲突重试拿「冲突响应 sha」当基线、却用「另一次 read 的 content」重定基，可覆盖他人内容 / 静默损坏

- **文件:行号**：`lib/base/disk/disk_cache.dart:769`（`nextBase = error.currentSha ?? fresh?.sha`）、`:783`（`content = intent.rebase!(fresh?.content ?? '', intent.content)`）、`:784`（`expectedSha = nextBase`）；`lib/kernel/contract/disk_types.dart:195`（422 也算 stale）
- **症状**：D3 冲突重试时，若远端实现抛出的 `RemoteConflictException.currentSha` 与随后 `_remote.read()` 返回的文档**不是同一版本**（GitHub 409/422 回执 sha 与最新内容在并发下常见不一致；`fresh == null` 时更退化成把空串当远端内容），`rebase(fresh.content, myContent)` 合并出的内容基于 A 版，而 PUT 却带 B 版 sha。服务端乐观锁通过，A→B 之间别人的修改被合并结果覆盖。更隐蔽的是：`fresh == null` 但 `currentSha` 存在时，重定基输入是 `''`，用户内容可能被合并函数按「远端已删除」处理（测试里的 `$latest+$my`、`$latest|$my` 会丢掉前缀语义），产生内容损坏且 UI 报成功。
- **根因**：`nextBase` 与 `content` 来自两个独立、未绑定为同一快照的来源，违反乐观锁的「基线必须对应内容」前提。
- **修复指令**：在 `lib/base/disk/disk_cache.dart` 的冲突重试分支只接受「同一次读」的 `(sha, content)`：以 `fresh = await _remote.read(key)` 为准，`nextBase = fresh?.sha`（忽略 `error.currentSha`，或仅当 `fresh == null` 时用它但**禁止重定基、直接返回 staleSha 交用户决策**）；`content = intent.rebase!(fresh!.content, intent.content)` 必须在 `fresh != null && fresh.sha == expectedSha` 的 guard 内执行。补测试：冲突响应 sha 与回读 sha 不一致、回读为 null 两类，断言绝不发出不带匹配基线的 PUT。

## 中（P1）

### 1B-02 · 写后回读异常仍算成功：远端 sha 空/错时本地索引存假基线，草稿却被清，后续提交写歪

- **文件:行号**：`lib/base/disk/disk_cache.dart:704-716`（`_verifyReadback` 结果可空仍按 `written.sha` 造 entry）、`:800-812`（回读任何异常原样外抛）、`:704-720`（先清草稿再 complete journal）、`:281-283`（异常兜底 `failByKey` 保留 pending）；对照 `docs/audit_b2_b.md:89-103` 的同源历史问题
- **症状**：① 历史 B2-B-03（空 sha / 206 残缺回执写进 `CacheEntry.sha`，然后 discard 草稿 + complete journal）在当前代码中依然成立：`written.sha` 未做非空/格式校验，`verified == null` 时用 `RemoteDocument(content: content, sha: written.sha)` 造条目。② 历史 B2-A-02（回读网络异常把「已提交」判失败）修复过头：`_verifyReadback` 里 `_remote.read` 的任何异常冒泡到 `write()` 的通用 catch，把成功提交折成 `server` 失败、保留 journal pending；但这次异常发生在 `_evictEncoded` 之后、`_drafts.discard` / `journal.complete` 之前，于是「远端已写、本地无缓存、草稿还在、journal 还 pending」——30 秒后 `replayPending` 带旧基线重放，被 D2 拦成 staleSha/abandon，用户以为「提交没成功」再点一次，可能写歪。
- **根因**：把「回读确认」与「提交结论」耦合，且回执 sha 未校验；异常路径的收尾顺序错误。
- **修复指令**：在 `_writeLocked` 成功路径先校验 `written.sha` 非空且形如 blob sha（否则回读确认后再决定），把 `_verifyReadback` 整体包在 `try/catch` 里（异常按「未确认」留痕，不改变提交已成功的事实）：先 `_drafts?.discard` + `journal.complete`，再尝试写本地缓存；缓存失败只记诊断。禁止在回读异常时把 journal 标为可重试失败。补测试：回读抛异常时 journal pending==0、草稿已清、返回 ok。

### 1B-03 · 收敛阶段 `prune()` 与并发写/回源竞态，可删掉刚写入的热数据

- **文件:行号**：`lib/base/disk/disk_cache.dart:997-1016`（`_maybePrune` 在 `_saveLocal` 尾部 `unawaited(prune())`）、`:403-430`（`prune` 先 `_scanMetas` 再逐条 `_evictIfStale`）、`:1084-1098`（`_evictIfStale` 只比对 `_loadLocal` 的 `fetchedAt`）；`_scanMetas` 无快照锁
- **症状**：扫描与淘汰不在同一原子窗口。写 A（`fetchedAt=T1`）后触发 prune，scan 收集 A；随后另一写把 A 刷新为 T2 并于 1ms 内完成；prune 的 `_evictIfStale` 发现 T2 晚于扫描时间 T1 本应放弃——但 `_loadLocal` 若此时因完整性失败/并发 `_evictEncoded` 返回 null，`_evictIfStale` 直接删 A（`:1053-1055` 无 fresh 分支的 else 是删除）。更普遍的是：扫描后**回源**写入的新条目（键此前不存在）根本不在 survivors 里，不受保护；以及 `prune` 里的 TTL 淘汰 `now.difference(fetchedAt) > age` 用扫描时刻 `now`，若回源耗时超过 TTL，刚取回的数据被当陈旧删除。后果：弱网下每次写入后 10 分钟内可能把热缓存清掉，下一次读又全量回源（磁盘抖动 + 额度浪费）。
- **根因**：淘汰决策基于过期快照，`_evictIfStale` 对「fresh == null」未区分「并发删除」与「读失败」。
- **修复指令**：把 `prune` 整轮放进专用互斥（与 `_mutex` 的写键互斥协调，例如先取所有键的"世代令牌"再淘汰），或改为「扫描时记录 `(encoded, revision, fetchedAt)`，淘汰前重读索引并比对 `revision` 完全一致才删」；`_loadLocal` 返回 null 时视为已被并发删除/损坏并跳过淘汰（不要删第二次）。TTL 判定改用 `_evictIfStale` 内部的**当下**时间。

### 1B-04 · 只读 GET 缓存键不含 `baseUrl`/环境维度，切换 API 根后旧环境数据被当成新环境命中

- **文件:行号**：`lib/domain/gh/gh_read_cache.dart:39-40`（`_epochKey` / `_prefix`）、`:64-72`（`_key` 只含 account + path + canonical query）、`:171-181`（`clear` 仅写 epoch，注释「无需删除 API」）；`lib/domain/gh/gh_client.dart:112`（`baseUrl` 为构造期字段，可配置为非 GitHub 企业版根）；`lib/domain/domain_bridge.dart:154`（注入 baseUrl）
- **症状**：`GhReadCache` 的 key 只哈希 `accountId + path + query`。同一账号在 `https://api.github.com` 与 GitHub Enterprise / 自建代理（改 `baseUrl`）之间切换时，路径相同即命中旧环境的 releases/issues/commits/`Link` 分页头，用户看到另一个环境的列表数据（企业版→公网、测试→生产方向都可能发生）；`clear()` 只在切账号/手动刷新时调用，切 baseUrl 不触发。
- **根因**：缓存键未覆盖「产生差异的全部维度」（环境/API 根），且 `clear()` 调用点未覆盖 baseUrl 变更。
- **修复指令**：给 `GhReadCache` 构造函数注入 `baseUrl`（或在 `GhClient.attachReadCache` 时把 `baseUrl` 传入），把它加入 `_key` 的哈希原文；同时在 `GhClient` 检测到 baseUrl 变化的唯一入口调用 `_readCache.clear()`。若 baseUrl 运行时不可变，则在 `attachReadCache` 时以 baseUrl 递增 epoch 一次并留注释，避免每次构造都清盘。

### 1B-05 · 长路径收纳索引非原子写且读失败一律返回空 Map → 草稿/日志/缓存索引被当作「不存在」甚至主动删除

- **文件:行号**：`lib/base/disk/platform_io_impl.dart:157-171`（`_index()` 对 IO/JSON 失败 `return {}`）、`:175-180`（`_saveIndex` 直接 `writeAsString(flush:true)` 非 tmp+rename）、`:217-219` / `:265-275`（写包后写索引）、`:389-402`（`IoDiskKv.read` 结构损坏 → `await _store.delete(_nameOf(key))`）、`:301-328`（`exists/list` 依赖索引）；`lib/base/disk/disk_journal.dart:306-313`、`lib/base/disk/disk_draft.dart:204-216`（坏记录直接删）
- **症状**：Windows 长路径收纳的「原路径 → zip」映射完全依赖 `.ogl_toolong.json`。该文件是单文件直写（崩溃可半截）、读失败被吞成空 Map。下一次读普通文件不存在转 `_readPacked`，索引空 ⇒ 返回 null ⇒ 上层把「读失败」 interpretation 成「键不存在」：`DraftStore._loadUnlocked` / `WriteJournal.records` 跳过，`IoDiskKv.read` 的 catch 分支还会主动 `delete` 掉对应键文件。一次瞬时 IO 错误/掉电即可静默销毁用户未提交草稿、待同步记录和缓存索引——历史 B2-A-10 的同源风险在当前代码仍存活。
- **根因**：关键元数据文件没有走同文件 `writeText` 的原子写路径，且「读不出来」与「确认不存在」未区分。
- **修复指令**：`_saveIndex` 改为经 `IoDiskFileStore.writeText` 的 tmp+fsync+rename 写入（复用 `writeText` 的原子性）；`_index()` 读失败必须抛出（或返回带 `ok` 状态的结果），禁止返回空 Map；`IoDiskKv.read` / `DraftStore._loadUnlocked` / `WriteJournal.records` 只在「JSON 结构确证损坏」时删除，且先写诊断/备份，读失败保留数据不删。

### 1B-06 · `GhReadCache.clear()` 只递增 epoch、旧条目永不回收，长期运行磁盘无界增长

- **文件:行号**：`lib/domain/gh/gh_read_cache.dart:37-40`（`_epochKey`/`_prefix`）、`:64-72`（键含 epoch）、`:171-181`（`clear` 仅写 epoch，注释「无需删除 API」）；`gh_read_cache.dart:90-120`（get 只按当前 epoch 拼 key）；`platform_io_impl.dart:419-436`（`IoDiskKv.keys()` 每次全读）
- **症状**：每次写操作（`gh_client.dart:670`）、切账号、手动刷新都调用 `clear()`，epoch 单调递增。旧 epoch 的 `ogl.rc.v1.<old>.*` KV 文件永不被读也永不被删，`IoDiskKv.keys()` 还会每次把它们全部读一遍（`:419-436`）。频繁写操作的应用里，KV 目录持续膨胀，最终拖慢启动/列举，并占用磁盘到影响其它缓存写入（缓存引擎自己的 `prune` 只管 `ogl.cache.meta.` 前缀，不会管这些）。
- **根因**：「换纪元即失效」只解决可见性，没有配套回收；注释把「无需删除 API」当成设计优点，实际是泄漏。
- **修复指令**：在 `GhReadCache.clear()` 里（epoch 递增成功后）遍历 `store.keys()`，删除以 `$_prefix.` 开头且 `epoch < next` 的键；为避免每次 clear 全表扫描，可在 epoch 达到阈值（如 16）时才做一次清扫，但要保证至少一次。

### 1B-07 · `delete()` 失败/成功路径的本地缓存失效与草稿清理不完整，冲突后旧内容可复活

- **文件:行号**：`lib/base/disk/disk_cache.dart:306-373`（成功 `_evictEncoded` 后直接返回，未 `_drafts?.discard`）、`:330-350`（`notFound` / `staleSha` 失败未失效本地缓存）；`lib/domain/gh/gh_api.dart:1040-1075`（`deleteContentLocked` 引擎路径返回 outcome）；`lib/surface/pages/code_editor_page.dart:326-331`（成功才清草稿）
- **症状**：删除目标文件成功后，引擎只清了 `RepositoryCache` 的本地条目，**同 key 的草稿（D9）未清**——若用户此前留下草稿，下次进编辑器恢复出已删除文件的旧内容，再保存就是一次「凭空复活」的无基线写入（并发下可能覆盖同名新文件）。删除失败（远端已不存在 / 基线过期）时，本地缓存条目也没失效，界面仍显示已删除/旧版本的内容，与远端状态不一致。
- **根因**：`delete` 复用了 `write` 的一部分收尾逻辑但漏了草稿收尾；失败分支没有「状态不确定即失效」的兜底。
- **修复指令**：`RepositoryCache.delete` 成功路径在 `_evictEncoded` 后补 `await _drafts?.discard(key)`；`notFound` 与 `RemoteConflictException` 分支也执行 `_evictEncoded`（失败失效是保守正确的，下次读会回源重建）。补测试：删除成功/失败两种情况下 `draftStore.count == 0`、本地 `read` 不返回旧条目。

## 轻（P2）

### 1B-08 · 契约 `ConsistencyCache` 缺少 `prune/purge/localCount/replayPending` 等实际能力，跨层调用者只能依赖具体实现

- **文件:行号**：`lib/kernel/contract/consistency_cache.dart:118-139`（抽象只有 read/write/invalidate/delete/草稿）、`lib/base/disk/disk_cache.dart:394/403/451/493/518`（实现有 `localCount/prune/replayPending/purge/purgeOrphans`）；`lib/domain/domain_bridge.dart:220`（直接依赖 `base.disk.cache.replayPending()` 具体类型）
- **症状**：任务书点名的「RepositoryCache implements ConsistencyCache 是否完整」在此有缺口：实现具备的有界淘汰/重放/清盘能力不在契约里，逻辑层与装配层只能把 `RepositoryCache` 当具体类使用，契约「L2 只依赖抽象」的目标未完全达成，未来替换实现会漏实现这些能力。
- **根因**：契约抽取时只覆盖了 D1–D9 主路径，运维/生命周期能力留在实现类。
- **修复指令**：把 `localCount/prune/purge/replayPending` 加入 `ConsistencyCache` 抽象（`prune/purge` 可选参数签名一致），装配层改为持有 `ConsistencyCache` 类型并调用契约方法。

### 1B-09 · 草稿契约与实现的排序注释相反，且 `DraftStore.discard/save` 失败无诊断留痕

- **文件:行号**：`lib/kernel/contract/consistency_cache.dart:25`（`all()` 注释「按时间倒序」）、`lib/base/disk/disk_draft.dart:195-218`（实现 `updatedAt` 升序）、`lib/base/disk/disk_draft.dart:162-193`（`save/load/discard` 无 `_diagnostics` 调用）、`:189-191`（`discard` 无 try/catch）；`docs/audit_b2_b.md:248-254`（历史 B2-B-08）
- **症状**：契约与实现排序相反，L2 若按契约假设「第一条最新」会展示错误顺序；`DraftStore` 虽有 `_diagnostics` 字段，只有 `clear()` 用它，`save/discard` 的 IO 失败静默（底层 `IoDiskFileStore.delete` 吞失败），与历史 B2-B-08 同源问题仍在。
- **根因**：契约注释抄错方向 + D6「失败可感知」在草稿路径未落实。
- **修复指令**：统一为升序（与 UI「恢复上次编辑」列表一致），修正契约注释；`DraftStore.discard/save` 捕获异常并 `_diagnostics.error('DRAFT', ...)`，让 `ConsistencyCache` 的草稿写入返回值能体现失败。

### 1B-10 · SAF 导出前 `existsSync()` 用在异步路径上，可阻塞 UI 线程并误判

- **文件:行号**：`lib/base/disk/og_l_storage_saf_io.dart:111-117`（`localFileExists` 用 `File(path).existsSync()`）；`lib/base/disk/og_l_storage.dart:160-174`（`exportToSaf` 在 await 链中调用）
- **症状**：`exportToSaf` 是异步方法，但存在性检查用同步 IO；下载完成后在主线程导出大文件时可能卡顿；`existsSync` 抛异常被吞成 false，导出静默放弃，用户以为下载完成但 SAF 目录里没有文件（功能失效但成功提示照发）。
- **根因**：异步路径混入同步 IO + 吞异常无诊断。
- **修复指令**：改为 `await File(path).exists()`，失败由 `exportToSaf` 记诊断并返回 false，UI 对 `exportToSaf == false` 给出「导出失败，文件仍在内部目录」提示。

### 1B-11 · `IxConflictResolver` 未校验描述选项与 `outcome.actions` 的一致性，危险动作可能「允许但无按钮」

- **文件:行号**：`lib/domain/ix/ix_conflict.dart:139-152`（`options = outcome.actions.map(_optionOf)`）、`:114-116`（`allowed` 只判 `_requiresConfirmation`）；`lib/kernel/contract/disk_types.dart:245-286`（actions 来源）；`test/domain/ix_conflict_test.dart:60`（现有测试只校验「常量集合」覆盖，未校验具体 outcome 的选项）
- **症状**：`describe` 完全信任 `outcome.actions`，未来新增 `ConflictAction` 枚举值时 `_optionOf` 的 switch 若不更新，Dart 会在运行时抛 `SwitchError`（`_optionOf` 无 default），导致整个冲突提示无法渲染——用户遇到冲突时页面直接报错而不是看到处置按钮。另外 `IxConflictResolution.allowed` 对 `retryLater` 等非危险动作总为 true，若 UI 传入未出现在 `options` 里的动作也会放行。
- **根因**：纯函数未做前向兼容保护，选项与允许的处置集合未交叉校验。
- **修复指令**：给 `_optionOf` 补 default 分支（返回 `retryLater` 风格的通用选项 + 诊断），并在 `describe` 里断言 `options.map(action).toSet() == outcome.actions.toSet()`；`IxConflictResolution.allowed` 增加 `action` 必须属于当前提示 options 的校验（由 UI 传入提示对象或 action 白名单）。

---

## 已检查清单（逐文件 / 逐函数，无问题亦列出）

| 文件 | 检查的函数 / 区域 | 结论 |
| --- | --- | --- |
| `lib/base/disk/disk_cache.dart`（1099 行，全文） | `_KeyedMutex.run`、`RepositoryCache` 构造/`attach*`、`read/write/delete/invalidate`、`prune/purge/purgeOrphans/replayPending`、`_readLocked/_writeLocked/_verifyReadback/_classify/_fail/_isRetryable/_threeWayFor/_entryOf/_isExpired/_hashOf/blobNameOf/_scanMetas/_saveLocal/_maybePrune/_loadLocal/_evictEncoded/_evictIfStale` | 发现 1B-01/02/03/07；TTL 单位（毫秒比较 `maxAge.inMilliseconds`、`Duration.difference`）与比较方向（`>` 过期）均正确；前缀隔离 `_indexPrefix` 无误删；键锁覆盖读+写+invalidate；D1/D2/D7 方向与空串基线归一正确 |
| `lib/domain/gh/gh_read_cache.dart`（184 行，全文） | `_epoch/_key/_canonicalQuery/get/put/_accountOrGuest/clear` | 发现 1B-04/06；TTL 用 `DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds` 单位/方向正确；`Link` 头已随 body 一起缓存（历史翻页 bug 未复发）；JSON 损坏/异常不阻断读 |
| `lib/kernel/contract/consistency_cache.dart`（140 行，全文） | `DraftRepository`、`DraftRecordView`、`CacheRemote`、`ConsistencyCache` 全部方法 | 发现 1B-08/09（契约方法不全 + 排序注释相反）；`CacheRemote.write/delete` 的 expectedSha 契约完整 |
| `lib/domain/ix/ix_conflict.dart`（271 行，全文） | `IxConflictOption/Prompt/Resolution`、`IxConflictResolver.describe/isAutoRecoverable/_titleOf/_messageOf/_optionOf/_short` | 发现 1B-11；`staleSha` 必带 `viewDiff`、`forceOverwrite`/`createInstead` 需二次确认、三方 `diverged` 判定均符合契约，历史「只给覆盖」未复发 |
| `lib/base/disk/disk_store.dart`、`disk_types.dart`（转发导出） | 转发正确性 | 无误；`disk_types.dart` 本文件无问题，但被其导出的 `kernel/contract/disk_types.dart:195` 参与 1B-01 |
| `lib/base/disk/disk_draft.dart`（241 行，全文） | `DraftRecord.toJson/fromJson`、`DraftStore._ordered/_loadUnlocked/save/load/has/discard/all/count/clear` | 发现 1B-09（诊断缺失）；`_ordered` 串行与「队列内不回调公开方法」正确；历史「草稿瞬间删除」已由 `code_editor_page.dart:176-184` 的 `initialTextIsRemote` 门控修复，本席未发现草稿层复发 |
| `lib/base/disk/disk_journal.dart`（356 行，全文） | `JournalRecord.toIntent/toJson/fromJson`、`WriteJournal.enqueue/complete/fail/failByKey/abandon/records/clear/_nextId` | 无新增问题；`force` 已持久化（`toIntent` 恢复），`failByKey` 只标最新记录正确；`copyWith` 未丢字段，历史 B2-A-06 未复发 |
| `lib/base/disk/platform_io_impl.dart`（571 行，全文） | `IoDiskFileStore.abs/_absFile/readText/writeText/_tempNameOf/_packTooLong/_readPacked/_deletePacked/delete/exists/list/sweepTemp`、`IoDiskKv.read/write/remove/has/keys`、`SecureDiskVault`、`PlatformStorage.open/toDiskModule` | 发现 1B-05；tmp+唯一名+flush+rename 的原子写与启动清扫正确；`..` 目录穿越防护正确 |
| `lib/base/disk/disk_bridge.dart`（160 行，全文） | `DiskBridge`/`DiskModule.onRegister` 的日志/草稿/诊断接线 | 无问题；三条接线完整 |
| `lib/base/disk/app_dirs.dart` + `app_dirs_fs_io.dart`（258 行） | `OgLAppDirs` 全部方法、`AppDirsFs` 全部方法 | 无缓存一致性问题（属 3-C 范围）；`invalidate()` 会清 `_rootCache`，路径缓存失效正确 |
| `lib/base/disk/og_l_storage.dart` + `og_l_storage_saf_io.dart`（297 行） | `OgLStoragePlan.userVisible`、`OgLStorage.plan/exportToSaf`、`OgLSafBridge` 全部方法 | 发现 1B-10；SAF 配置缓存 `_safLoaded` 只在 `setSafTreeUri` 后更新正确 |
| `lib/base/disk/platform_io.dart`、`draft_adapter.dart`（72 行） | 转发导出、`DraftRepositoryAdapter` 五个方法 | 无问题；适配器字段映射完整 |
| `lib/kernel/contract/disk_types.dart`（534 行，依赖核对） | `CacheScope/CacheKey` 编解码与校验、`RemoteConflictException.isStale`、`ConflictAction.resolveConflictActions`、`ConflictThreeWay.diverged`、`WriteIntent/WriteOutcome/CacheEntry.toJson` | 1B-01 的 422 分类来源；分隔符校验、三方分歧判定、冲突动作表正确 |
| 交叉核对（只读，非本席范围） | `lib/domain/gh/gh_client.dart:558-685`（GET 缓存命中/回填/206 拒收/写后 clear）、`gh_api.dart:646-759/890-1128/2140-2210`（content/list/putContentLocked/deleteContentLocked/CacheRemote）、`domain_bridge.dart:150-240`（接线）、`code_editor_page.dart:130-340`（草稿恢复/持久化） | 206 残缺响应不写缓存、读失败落回网络、D5 死锁修复均在；未发现本席范围内的新复发 |

---

## 本席结论

批 1-B 缓存一致性共发现 **11 个问题**（P0 1 / P1 6 / P2 4）。最严重的是 **1B-01**：D3 冲突重试把「冲突响应 sha」和「另一次回读的内容」拼成一次乐观锁写入，理论上可在并发冲突中覆盖他人提交；其次是 **1B-02**（回读异常与空 sha 回执破坏 D5 收尾，草稿/队列状态失真）和 **1B-05**（长路径索引非原子写 + 读错误折叠为空，可静默销毁草稿/日志）。TTL 单位与比较方向、前缀失效、tmp+fsync+rename 原子写、草稿瞬间删除与冲突「只给覆盖」等历史 bug 均未复发；主要风险集中在**「失败/并发/不确定态下的收尾顺序」**——引擎把「远端已提交」与「本地确认完成」混为一谈，以及关键元数据文件未走原子写通道。建议先修 1B-01/02/05（P0/P1 数据安全），再处理失效覆盖与契约完整性。
