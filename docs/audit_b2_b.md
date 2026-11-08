# 第2批·视角B：安全与数据——磁盘一致性层审计

审计对象：`/root/OhGithubLost`（Flutter GitHub 客户端 main 分支）磁盘一致性层
视角：**安全与数据完整性**（数据无价、原子性、失败可见、凭证与本地数据）
纪律：只审不改，不写 `lib/`；每条含编号 B2-B-xx、文件:行号、问题描述、用户可见后果、优先级、违反原则编号、是否确证（附代码证据）。

---

## B2-B-01 · P0 · 确证 —— 从草稿箱打开草稿的瞬间，草稿被静默删除

**文件:行号**：`lib/surface/pages/drafts_page.dart:157-166` × `lib/surface/pages/code_editor_page.dart:141-155`（`_restoreDraft`）、`:176-192`（`_persistDraft`）、`:105-116`（`dispose`）

**问题**：草稿箱的「在编辑器中打开」把 `initialText: record.content`（草稿正文）传给 `CodeEditorPage`。而编辑器把「当前文本 == initialText」当作「内容与远端一致，应清草稿」的判据：
- `_restoreDraft()` 读到同一份草稿后 `if (draft.content == widget.initialText) { await discardDraft(...); return; }` —— 恒真，**立刻删除草稿**；
- 即便 `_restoreDraft` 被跳过，`dispose()` 中 `_savedText == null` ⇒ `savedClean=false && !_abandon` ⇒ `unawaited(_persistDraft())`，而 `_persistDraft()` 首行同样是 `if (_controller.text == widget.initialText) { await discardDraft(...); return; }` —— 用户什么都不改直接退出，**草稿再被删一次**。

**用户可见后果**：**数据丢失（用户未提交的代码）且完全静默**。用户从草稿箱点「接着改」→ 屏幕上确实看到了草稿内容 → 直接返回 / 杀掉页面 → 本机草稿已被删、远端没有任何提交，用户敲的字彻底消失，既无提示也无日志。这条路径绕过了 D9「草稿先落盘」的全部保护。

**违反原则**：8（数据无价，用户写的内容不能丢）、9（写前必读/知道当前状态）、13（半成品状态必须留痕）、15（静默降级最严重）、16（不吞异常/转化为结果）。

**代码证据**：
```dart
// drafts_page.dart:159-166 —— initialText 就是草稿正文
initialText: record.content,
baseSha: record.baseSha ?? '',

// code_editor_page.dart:148-152 —— 相等即删
if (draft.content == widget.initialText) {
  await widget.surface.domain.api.discardDraft(...);
  return;
}
// code_editor_page.dart:180-186 —— 同一判据再次删除
if (_controller.text == widget.initialText) {
  await widget.surface.domain.api.discardDraft(...);
  return;
}
// code_editor_page.dart:109-113 —— dispose 无条件触发 _persistDraft
final bool savedClean = _savedText != null && _controller.text == _savedText;
if (!savedClean && !_abandon) { unawaited(_persistDraft()); }
```
「与 initialText 相同 = 干净」这个假设只在 initialText 来自**远端**时成立；草稿箱入口把 initialText 换成了草稿本身，假设被破坏。

---

## B2-B-02 · P0 · 确证 —— `putContent` 的 206 回读确认只查「有没有 sha」，不确认「写没写全 / 写对」，且分支参数丢失

**文件:行号**：`lib/domain/gh/gh_api.dart:765-812`（`putContent`），回读段 `:799-810`；`lib/domain/gh/gh_client.dart:311`（`isSuccess` 含 206）、`:326-334`（`jsonObject` 解析失败返回 `null`）；`lib/domain/gh/gh_models.dart:592-617`（`GhContent.fromJson`）

**问题**：写回执不完整（206/代理截断）时，`written.sha.isEmpty` 触发回读 `_contentNetwork(...)`。回读只判定 `confirmed != null && confirmed.sha.isNotEmpty` 就把 `confirmed` 当作本次写的结果返回，**没有比对回读内容是否等于本次提交的 `content`**。三处具体漏洞：
1. **回读本身若也是 206 会不会伪装成功**：会。`GhResponse.isSuccess => statusCode >= 200 && < 300`，206 被视为成功；`_contentNetwork` 用 `client.getObject` → `response.jsonObject`，截断的 JSON 解析失败返回 `null` → `_contentNetwork` 返回 `null` → 抛明确异常（这一支尚可）。但若截断后仍是**语法完整的 JSON**（代理返回了另一个合法对象、或返回了旧的完整 content 对象），`GhContent.fromJson` 会解析出**别人的/旧的 sha 与内容**，条件 `sha.isNotEmpty` 成立 ⇒ 本次写被判「成功并返回该 sha」，D5 回读校验拿这个假 sha 去比对，用户看到「提交成功」而远端可能根本没写入或写的是别人的版本。
2. **回读不校验内容**：即使回读拿到的是**写之前的旧版本**（PUT 实际失败但代理缓存了旧 GET 响应），sha 非空即算确认，静默把旧 sha 当新 sha 交给 D5 / `CacheRemote.write` / 本地索引，后续所有乐观锁基线都建立在这个错误 sha 上。
3. **分支维度丢失**：回读调用 `_contentNetwork(fullName, path, branch: branch)`，而 `_contentNetwork` 只在 `branch != null && branch.isNotEmpty` 时才带 `ref`（`gh_api.dart:597-609`）。`putContent` 的 `branch` 参数是 `String?` 可空，**未指定分支时回读的是默认分支**；若本次 PUT 写到了非默认分支，回读拿默认分支的 sha 冒充成功，键空间的 `branch` 维度与实际写入不一致（原则 28）。

**用户可见后果**：**静默损坏 / 伪造成功**。用户以为已提交，实际远端是旧内容或未写入；编辑器随后 `discardDraft`（`code_editor_page.dart:280-286`）清掉本机唯一副本 ⇒ 数据丢失且不可恢复。错误 sha 进入本地索引后，下一次编辑会以错误基线提交，可能 409 连环失败或被判定为「基线过期」。

**违反原则**：42（失败如实报错，伪造的成功响应比失败更难排查）、28（缓存键必须覆盖产生差异的全部维度）、9（写前必读，不知道状态就动手）、8、13、15。

**代码证据**：
```dart
// gh_api.dart:799-810
if (written.sha.isEmpty) {
  final GhContent? confirmed = await _contentNetwork(fullName, path, branch: branch);
  if (confirmed != null && confirmed.sha.isNotEmpty) {
    written = confirmed;                 // ← 未比对 confirmed.text == content
  } else { throw GhAuthException('提交已发出但响应不完整…'); }
}
// gh_client.dart:311  206 属于 isSuccess
bool get isSuccess => statusCode >= 200 && statusCode < 300;
// gh_api.dart:765-779  PUT 的 branch 可空；回读未强制 ref
if (branch != null) 'branch': branch,
```
`CacheRemote.write`（`gh_api.dart:1993-2006`）直接 `return RemoteDocument(content: content, sha: written.sha)`，把这个 sha 交给 `disk_cache.dart:687-706` 的 D5 `_verifyReadback(intent.key, written.sha)`，形成「假回执 → 假校验」的闭环。

---

## B2-B-03 · P0 · 确证 —— `CacheRemote.write` 把「空 sha」交给 D5：PUT 成功但响应体被截断时，D5 成功路径用空 sha 建本地索引并清草稿

**文件:行号**：`lib/domain/gh/gh_api.dart:1993-2007`（`CacheRemote.write`）、`:765-812`（`putContent`）；`lib/base/disk/disk_cache.dart:687-717`（D5 回读 + 本地条目）、`:732-742`（`_verifyReadback`）、`:857-866`（`_entryOf`）；`lib/kernel/contract/disk_types.dart:381-388`

**问题**：`CacheRemote.write` 的契约是 `Future<RemoteDocument>`（非空）。`putContent` 已对 `written.sha.isEmpty` 做了兜底（B2-B-02），但 **`GhWriteResult` / `putContentLocked` 的退化裸写路径**（`gh_api.dart:861-910`）与 `CacheRemote.write` 之间仍存在「空 sha 流向 D5 的所有分支」：
1. `putContent` 在 `written.sha.isEmpty` 且回读失败时抛 `GhAuthException` —— 该异常不是 `RemoteConflictException`，会冒泡到 `disk_cache.dart:264-276` 的 `catch (error)` → `_fail(server, '写入异常终止…')`，journal 留 pending（这一支是「失败可见」的，尚可）。
2. **但 D5 本身不设防**：`disk_cache.dart:687` 无条件 `await _remote.write(...)`，随后 `:697-706` 用 `written.sha` 作为期望值去回读；`:703-706` 在回读为 `null`（`_verifyReadback` 默认 `readbackAttempts = 1`，`disk_cache.dart:140`）时**直接退化**：
```dart
final CacheEntry entry = await _entryOf(intent.key,
    verified ?? RemoteDocument(content: content, sha: written.sha));
```
`_entryOf` 对 `sha` 不做任何非空/格式校验，直接写进 `CacheEntry.sha` 与索引 `toJson()['sha']`。若 `written.sha` 为空串（或回执是 `dir:` 之类的非 blob sha），本地索引会存一个 **sha 为空的「成功」条目**，接着 `_drafts?.discard()`（`:709`）与 `_journal!.complete()`（`:712`）双双执行 ⇒ 返回 `WriteOutcome.success`。
3. 这条「已提交（待确认）」语义在注释里被声明为有意设计（`:686-693` 说「回读失败 → 视为已提交，按成功收尾」），但**没有任何诊断留痕**：`_verifyReadback` 返回 `null` 时不记 error/warn，`OGL-CONS-001` 写入成功日志里也不带 `verified=false` 标记。D6 声称「失败可感知」，这里唯一的感知渠道（诊断）把「回读失败」伪装成普通成功。

**用户可见后果**：**静默损坏 + 数据丢失**。本地缓存被写入一个 sha 为空/伪造的条目（后续 `CacheEntry.sha` 作为 `baseSha` 参与乐观锁，`_writeLocked:632` 的 `baselineSha != latest.sha` 恒真 ⇒ 用户每次保存都报「基线已过期」，或 force 路径把空 sha 当基线发出）；同时草稿被清、journal 被 complete，用户手上没有任何可恢复副本。用户看到「已提交」通知，远端状态未知。

**违反原则**：42（伪造成功）、13（每次写入要么完整生效要么可恢复）、15（静默降级）、16、17（用类型表达失败，让调用方无法忽略）、20（外部数据不可信，反序列化夹紧并记录）。

**代码证据**：
```dart
// disk_cache.dart:697-717
final RemoteDocument? verified = await _verifyReadback(intent.key, written.sha);
final CacheEntry entry = await _entryOf(intent.key,
    verified ?? RemoteDocument(content: content, sha: written.sha));
await _saveLocal(entry);
await _drafts?.discard(intent.key);
if (journalRecord != null) { await _journal!.complete(journalRecord.id); }
_diagnostics.info(... 'OGL-CONS-001' ...);   // 不含 verified 状态
return WriteOutcome.success(entry: entry, attempts: attempt);
// disk_cache.dart:732-742 —— 失败返回 null，无日志
Future<RemoteDocument?> _verifyReadback(...) async { ... return null; }
// disk_types.dart:381-388 —— toJson 无条件写 sha
'sha': sha, 'hash': contentHash,
```

---

## B2-B-04 · P1 · 确证 —— `putContentLocked`/`deleteContentLocked` 的「未绑定缓存」退化裸写路径丢掉 D7 二次确认与 D2/D5，且 force 可绕过确认

**文件:行号**：`lib/domain/gh/gh_api.dart:841-910`（`putContentLocked` 退化分支 `:859-910`）、`lib/domain/gh/gh_api.dart:956-988`（`deleteContentLocked` 退化分支 `:963-977`）

**问题**：`cache == null || key == null`（缓存未绑定 / 账号 provider 抛错 / 默认分支解析不出 → `_cacheKeyFor` 返回 `null`，`gh_api.dart:88-116`）时，两条「Locked」方法退化为裸 `putContent` / `deleteContent`：
1. **`deleteContentLocked` 完全丢掉 `confirmed`**：`:963-977` 无条件 `await deleteContent(...)` 然后返回 `ok: true`。`confirmed` 参数被声明却在这条分支**从未被读取**（`gh_api.dart:961`）。删除是 `dangerous` 操作，D7 要求二次确认，正常路径 `cache.delete` 在 `disk_cache.dart:311-321` 会拦成 `needsConfirmation`；退化路径直接发 DELETE，且**不入 journal**（B2-B-07）。`confirmed=false` 也照样删除。
2. **`putContentLocked` 的 `force` 在退化路径跳过 D7**：`:865-878` 中 `force == true` 时先 `_contentNetwork` 取最新 sha 再裸写，全程**不检查 `confirmed`**。缓存正常时 `_writeLocked`（`disk_cache.dart:607-614`）对 `(dangerous || force) && !confirmed` 一律拦为 `needsConfirmation`。也就是说：**调用方只需让键构造失败，就能绕过二次确认强制覆盖**。这正是原则 11 禁止的「绕过校验的捷径参数」的等价效果（无需传 confirmed 即生效）。
3. 退化路径没有 D1/D2 校验（`expected` 只是把空串换成 `null`），没有 D5 回读，失败只捕获 `RemoteConflictException`，其它异常直接外抛（与「永不抛」的文档承诺 `:846` 相反），也不入 journal。

**用户可见后果**：**静默损坏 / 覆盖他人提交**。危险删除可在未确认时执行；强制覆盖可在未确认时执行并顶掉别人刚提交的内容。账号 provider 异常（`_cacheKeyFor` 的 `catch (_) { account = 'guest'; }`）虽会退回 `guest` 而非 null，但 `_cache == null`（装配未完成/启动早期/存储降级回内存时 `DiskModule` 仍构造了 cache，故更常见的是 `key == null`：默认分支为空或路径含 `..`）足以触发。`baseSha` 空串 + 无 sha 的 PUT 在目标已存在时会被 GitHub 422 拒绝，但**删除没有这层兜底**。

**违反原则**：11（防线没有开关，任何绕过校验的捷径参数都不允许）、12（危险操作必须经用户显式确认，在类型上表达）、9、13、15、17。

**代码证据**：
```dart
// gh_api.dart:963-977 —— confirmed 未参与判定
if (cache == null || key == null) {
  await deleteContent(fullName, path, message: message, baseSha: baseSha, branch: branch);
  return GhWriteResult(ok: true, conflict: GhWriteConflict.none, baseSha: baseSha);
}
// gh_api.dart:865-879 —— force 裸写，不检查 confirmed
if (force) {
  final GhContent? latest = await _contentNetwork(...);
  expected = latest.sha;
}
final GhContent written = await putContent(...);
return GhWriteResult(ok: true, ...);
// 对照：disk_cache.dart:607-614 正常路径强制拦下
if ((intent.dangerous || intent.force) && !confirmed) {
  return _fail(intent, WriteConflict.needsConfirmation, ...);
}
```

---

## B2-B-05 · P1 · 确证 —— `_saveLocal` 先写 blob 再写 index，中途崩溃留下「旧索引 + 新 blob」撕裂写，`_loadLocal` 会把它当合法数据读出

**文件:行号**：`lib/base/disk/disk_cache.dart:945-949`（`_saveLocal`）、`:951-1002`（`_loadLocal`）、`:1004-1007`（`_evictEncoded`）、`:506-530`（`purgeOrphans`）；`lib/base/disk/platform_io_impl.dart:118-141`（`writeText` 原子写）

**问题**：写入顺序是 `await _blobs.writeText(...)` → `await _index.write(...)`。两次写之间崩溃/掉电，磁盘上是：**旧 index（旧 sha / 旧 len / 旧 hash）+ 新 blob（新内容）**。两处防线都失效：
1. `_loadLocal` 的完整性校验（`:970-990`）比对的是 `content.length != expectedLength` 与 `sha256(content) != expectedHash`。若新旧内容**长度恰好相同**（改一个字符、改版本号数字、大小写替换等极常见），长度校验通过；hash 校验会失败 ⇒ 走 `OGL-CONS-208` 丢弃并回源（这一支是好的）。**但 `IoDiskFileStore.writeText` 用 `rename` 原子替换 blob，`IoDiskKv.write` 也是原子写**，所以「blob 半截」不会发生 —— 真正的问题在于 `InMemoryKv`/`InMemoryFileStore` 实现（CI/降级路径）无任何原子性，以及**更致命的反向情形**：`_evictEncoded` 的清理顺序是「先删 index，再删 blob」（`:1005-1006`）。若删 index 后崩溃，blob 成为孤儿；`purgeOrphans()` 的判定依据是「文件名是否出现在现存索引集合中」（`:507-517`），**它把孤儿一律当作垃圾删除** —— 而孤儿 blob 可能是「刚写成功、index 还没落盘」的那一份用户内容（虽然此时用户已拿到 `WriteOutcome.success`，但重启后本地副本没了，只能回源；若远端写入其实失败，则是真丢失）。
2. **孤儿判定没有时间窗 / 版本信息**：`purgeOrphans` 不区分「中断残留」与「正在写入中的热 blob」，也不检查 blob 内容与任何索引的 hash 是否匹配，仅凭文件名集合差集就删。`purge()`（`clearRepositoryCache` 的入口，`surface_bridge.dart:170`）会在用户切号/清缓存时并发于写入执行 —— `purge()` 在 `:481-495` 先 `_evictIfStale` 再 `purgeOrphans()`，两者都不持有全局部互斥，只有逐键 `_mutex`，而 `purgeOrphans` 完全不进 `_mutex`。
3. `_loadLocal` 的 `catch (_)`（`:996-1001`，见 B2-B-11）把「结构不兼容/损坏」静默丢弃且不留诊断，`_evictEncoded` 又先删 index，使得撕裂痕迹被主动抹掉 —— 违反「半成品状态必须留有痕迹并能被重启发现」。

**用户可见后果**：**静默损坏 / 潜在数据丢失**。撕裂写的本地条目被丢弃后回源，若此时离线则读失败；孤儿清理误删热 blob 会让刚提交的内容在本机不可恢复。重启后没有任何「检测到撕裂写」的痕迹可供用户或排查者发现。

**违反原则**：13（每次写入要么完整生效要么可恢复；半成品状态必须留有痕迹并能被重启发现）、14（删除前落盘意图）、8、15、20（外部数据坏数据夹紧并记录）。

**代码证据**：
```dart
// disk_cache.dart:945-949
Future<void> _saveLocal(CacheEntry entry) async {
  await _blobs.writeText(_blobPathOf(encoded), entry.content);   // ① 先写内容
  await _index.write(_metaKeyOf(encoded), jsonEncode(entry.toJson())); // ② 后写索引
}
// disk_cache.dart:1004-1007 —— 删除顺序相反，且无 journal
Future<void> _evictEncoded(String encoded) async {
  await _index.remove(_metaKeyOf(encoded));
  await _blobs.delete(_blobPathOf(encoded));
}
// disk_cache.dart:507-517 —— 仅凭文件名差集判定孤儿
final referenced = <String>{ for (final meta in await _scanMetas()) blobNameOf(meta.encoded) };
for (final name in await _blobs.list('cache')) {
  if (!referenced.contains(name)) { await _blobs.delete('$_blobPrefix$name'); removed++; }
}
```
注：`platform_io_impl.dart:120-141` 的单文件原子写确实降低了单文件半截风险，但**两步写的跨文件事务**没有任何 WAL / 提交标记 / 版本戳，无法识别「哪一份 blob 属于哪一代 index」。

---

## B2-B-06 · P1 · 确证 —— 缓存键含 accountId 但 blob 文件名是 `sha256(encoded)`，且 `_blobs` 与 `_index` 共用无账号分区的目录；切号只清缓存不清 journal/草稿的账号归属

**文件:行号**：`lib/base/disk/disk_cache.dart:141-142`（`_indexPrefix`/`_blobPrefix`）、`:886-890`（`blobNameOf`）、`:945-949`（`_saveLocal`）；`lib/base/disk/platform_io_impl.dart:546-560`（`toDiskModule`）、`:359-411`（`IoDiskKv`）；`lib/domain/gh/gh_api.dart:88-116`（`_cacheKeyFor`）；`lib/surface/surface_bridge.dart:198-213`（`clearAllCaches`）

**问题**：从**保密性**看，blob 文件名是 `sha256(scope|path)` 的摘要，不含明文路径，这一点是好的；索引 `IoDiskKv` 文件名也是 `sha256(key).json`，但**文件内容明文存 `{"k": 原键, "v": 值}`**（`platform_io_impl.dart:365-371`），其中 `v` 就是 `CacheEntry.toJson()` 的 JSON —— 它不含 content（内容在 blob），但 blob 本身是 **UTF-8 明文**（`writeText` 直接写 `entry.content`），无任何加密/ACL。scope 隔离只在「逻辑键」层面：`_loadLocal` 用 `key.encode()` 反算 blob 名，只要拿到同样的 `CacheKey`（schemaVersion + accountId + repo + branch + path）就能读。因此：
1. **防范跨账号读私有文件内容是「靠调用方诚实」而非类型强制**：`_cacheKeyFor` 在 `accountIdProvider` 抛错或返回空时 `account = 'guest'`（`gh_api.dart:100-108`）。**所有未登录/令牌读取失败/账号 provider 异常的请求共用 `guest` 这一个作用域**。若用户 A 在登录态缓存了私有仓库文件，退出登录或 provider 临时异常后以 guest 身份读同 repo/branch/path，会拿到 `guest` 作用域的缓存（不是 A 的，因为键不同）—— 所以此处**不会**串到 A 的内容。但反过来：多个账号共享 `guest`（例如 provider 异常）时，他们的缓存互相可见；且 `drafts()`（`gh_api.dart:327-340`）**遍历全部草稿、不按当前账号过滤**，草稿箱会显示其它账号的私有文件正文。
2. `GhApi.drafts()` 把 `_cache.drafts.all()` 原样列出，键里的 `accountId` 被拆成 `repo/branch/path` 用于 UI，**没有与当前 activeAccountId 比较**。`clearAllDrafts()`（`:394-401`）虽在切号时调用（`surface_bridge.dart:205`），但 `forgetAccount` 之外的普通「切换账号」（非移除）路径是否调用需另查；且 `WriteJournal.records()` 同样不按账号过滤，`replayPending()`（`disk_cache.dart:439-471`）会把**另一个账号的 pending 写意图**在当前账号令牌下重放 —— 用 B 的令牌向 A 的私有仓库提交 A 起草的内容（键里存着 A 的 accountId，但 `CacheRemote.write` 只用 `key.scope.repo/branch` 与 `key.path`，`gh_api.dart:1993-2006` 完全忽略 accountId，用当前 `_auth.activeToken()` 发请求）。

**用户可见后果**：**凭证/本地数据泄露面 + 跨账号错写**。草稿箱可列出其它账号私有文件的完整正文；journal 重放可能把 A 的草稿用 B 的身份提交到 A 的仓库（越权写入或 403 后莫名失败）。本地磁盘上所有缓存内容以明文落在应用私有目录，任何能读该目录的进程（root/备份/取证）无需凭证即可读到全部私有仓库文件 —— 与「凭证只进系统密钥库」的保护级别不匹配（`DiskVault` 有 Keystore，缓存没有）。

**违反原则**：39（凭证与本地数据安全）、28（缓存键必须覆盖产生差异的全部维度 —— accountId 在重放/草稿列举处被忽略）、12、8、14。

**代码证据**：
```dart
// disk_cache.dart:886-890
static String blobNameOf(String encoded) =>
    '${sha256.convert(utf8.encode(encoded))}.txt';
// platform_io_impl.dart:365-371 —— 值明文落盘
Future<void> write(String key, String value) => _store.writeText(
    _nameOf(key), jsonEncode(<String,Object?>{'k': key, 'v': value}));
// gh_api.dart:327-340 —— 草稿箱不过滤账号
final all = await store.all();
return <GhDraft>[ for (final record in all) GhDraft(repo: record.key.scope.repo, ...) ];
// disk_cache.dart:445-447 —— 重放不校验账号
for (final record in await journal.records(status: JournalStatus.pending)) {
  final outcome = await write(record.toIntent(), confirmed: confirmed, recordJournal: false);
// gh_api.dart:1993-2006 —— CacheRemote.write 完全忽略 key.scope.accountId
```
**「待议」部分**：`forgetAccount` 之外的普通切号是否清草稿/journal 未在本次范围内确证（需读 auth 切号流程），故「切号必然泄露」标待议；「`drafts()` 不过滤账号」与「journal 重放不过滤账号」为**确证**。

---

## B2-B-07 · P1 · 确证 —— `delete` 不入 journal 的语义：删除意图在发出 DELETE 前没有任何落盘痕迹，崩溃即「无人知道发生过」，且成功后不验证

**文件:行号**：`lib/base/disk/disk_cache.dart:288-378`（`delete`），注释 `:291-294`；`lib/domain/gh/gh_api.dart:1009-1017`（`CacheRemote.delete`）、`:1020-1034`（`deleteContent`）；`lib/kernel/contract/disk_types.dart` `WriteJournal` 无 delete 意图类型

**问题**：注释 `:291-294` 给出理由「删除无法用 WriteIntent 表达，重放会当成写入空内容」，因此 `delete` 全程不调用 `_journal.enqueue`。这确实避免了误重放，但**没有给出替代的恢复机制**：
1. `delete` 在执行 `_remote.delete`（`:346`）之前，没有任何落盘意图；`await _remote.delete(...)` 之后立刻 `_evictEncoded`（`:347`）并返回 `ok: true`（`:357-361`）。若 DELETE 已在远端生效但进程在 `_evictEncoded` 前被杀，本地缓存仍持有被删文件的旧内容（30s TTL 内 `content()` 会读出「已删除的文件」），且**没有任何 journal 记录**可以告诉重启后的应用「这次删除发生过」。
2. 删除**没有 D5 回读**：`write` 有 `_verifyReadback`，`delete` 发完 DELETE 就宣布成功，不确认远端目标确已消失。`GhApi.deleteContent`（`gh_api.dart:1020-1034`）用 `.then((_) {})` **丢弃响应体**，连响应状态码之外的信息都不保留。若代理返回 2xx 但删除未生效（伪造成功），用户看到「删除成功」而文件还在。
3. 与 B2-B-04 叠加：退化分支 `deleteContentLocked` 连 `confirmed` 都不检查就裸删，且同样不入 journal。

`WriteJournal` 只有 `pending`/`abandoned` 两态、`JournalRecord.toIntent()` 只能还原 `WriteIntent`（`disk_journal.dart:91-97`），类型上确实无法表达删除 —— 这是**设计缺口**而非「安全地不做」。原则 14「删除前落盘意图，成功后清除记录」被明确违反：注释把它解释成「因此只做在线加锁」，但在线加锁不能替代落盘意图。

**用户可见后果**：**静默损坏 / 失败不可见**。删除请求发出后崩溃，用户重启后既看不到「删除已成功」（文件其实没了），也看不到「删除待确认」；本地缓存可能短暂显示已删除文件的旧内容，用户以为删除失败而重复操作（第二次 `baseSha` 仍指向旧 sha ⇒ `staleSha`/`notFound` 困惑）。伪造成功的 2xx 会让用户认为私有/敏感内容已删除，实际仍在远端。

**违反原则**：14（删除前落盘意图，成功后清除记录；写日志的时间点本身就是恢复依据）、13、42（失败如实报错）、9、12。

**代码证据**：
```dart
// disk_cache.dart:291-294 —— 明确声明不入 journal
/// 为什么**不入提交日志**：日志记录会被 [replayPending] 还原成 [WriteIntent]
/// ... 因此删除只做**在线加锁**，失败如实返回、由用户重试。
// disk_cache.dart:346-361
await _remote.delete(key, message: message, expectedSha: baseSha);
await _evictEncoded(key.encode());
_diagnostics.info('CACHE', '删除成功', code: 'OGL-CONS-005', ...);
return WriteOutcome(ok: true, conflict: WriteConflict.none, baseSha: baseSha);
// gh_api.dart:1025-1034 —— 丢弃响应
}).then((_) {});
```

---

## B2-B-08 · P1 · 确证 —— `discardDraft` 失败无任何可见痕迹（编辑器、草稿箱、后台提交三处均吞掉）

**文件:行号**：`lib/base/disk/disk_draft.dart:171-175`（`discard`，无 try/catch 无诊断）、`:106-108`（`attachDiagnostics` 存在但 `discard`/`save`/`load` 均不用）；`lib/domain/gh/gh_api.dart:403-412`（`discardDraft`，异常直接外抛）；`lib/surface/pages/code_editor_page.dart:280-286`（`catch (_) { // 草稿清理失败不影响"提交已成功"的事实 }`）、`:176-192`（`_persistDraft` 的 `catch (_)`）、`:141-155`（`_restoreDraft` 的 `catch (_)`）、`:384-390`（放弃修改 `unawaited(discardDraft(...))` 无 await 无 catch）；`lib/surface/pages/drafts_page.dart:117-124`（`_delete` 不检查返回值/异常，无条件弹 `deleted`）

**问题**：`DraftStore.discard` 只是 `_ordered(key, () async { await _store.remove(...); notifyListeners(); })`。底层 `IoDiskKv.remove` → `IoDiskFileStore.delete`，该实现在 `platform_io_impl.dart:275-282` 的 `_deletePacked` 里 `catch (_) { // 删不掉就留着，绝不外抛 }`，文件删除失败会被**静默吞掉**（例如权限变化、磁盘只读）。于是：
1. **提交成功即清草稿（D9）可能实际没清**：`disk_cache.dart:709` 的 `await _drafts?.discard(intent.key)` 返回 `void`，引擎无法知道失败，仍 `complete(journal)` + `return success`；`code_editor_page.dart:280-286` 的第二次 `discardDraft` 也把异常吞掉。重启后旧草稿（**提交前的内容**）还在，`_restoreDraft` 会把它恢复到编辑器里，用户看到「我明明提交了，怎么又变回旧内容」，若再保存一次就把**旧内容写回远端**（数据回退/覆盖）。
2. **失败完全不可见**：`DraftStore` 有 `_diagnostics` 字段和 `attachDiagnostics`，但只在 `clear()`（`:224-231`）用了一次；`discard`/`save`/`load`/`all` 的损坏清理与失败路径全是 `catch (_) { ... }` 静默。`code_editor_page.dart` 的注释「草稿清理失败不影响提交已成功的事实」把「失败可见」降级成「不影响主流程」，但没有任何日志/通知。
3. **草稿箱删除**：`drafts_page.dart:117-124` 无条件 `OgLNotifier.info(_t('deleted'))` —— 删除失败也报「已删除」，刷新后草稿还在，用户重复删除。
4. `dispose()` 中 `unawaited(_persistDraft())`（`code_editor_page.dart:113`）与防抖 Timer 均 fire-and-forget，页面销毁后写入失败无人接收（原则 22/24）。

**用户可见后果**：**静默损坏 / 数据丢失**。已提交内容被旧草稿覆盖回退；用户被「已删除/已提交」的假成功误导，且日志里查不到任何痕迹。

**违反原则**：15（静默降级最严重）、16（不吞异常，捕获后必须转化为明确结果或告警）、13、17（用类型表达失败；`discard` 返回 `void` 让调用方无法检查）、8。

**代码证据**：
```dart
// disk_draft.dart:171-175
Future<void> discard(CacheKey key) => _ordered(key, () async {
  await _store.remove(_keyOf(key));
  notifyListeners();
});
// platform_io_impl.dart:278-281 —— 底层删失败静默
} catch (_) { /* 删不掉就留着，绝不外抛。 */ }
// code_editor_page.dart:280-286
try { await ...discardDraft(...); } catch (_) {
  // 草稿清理失败不影响"提交已成功"的事实。
}
// drafts_page.dart:119-123 —— 无 try/catch，无条件报成功
await widget.surface.domain.api.discardDraft(...);
if (mounted) { OgLNotifier.of(context).info(_t('deleted')); await _controller().load(); }
```

---

## B2-B-09 · P1 · 确证 —— `_submitInBackground` 的 `canForceOverwrite` 分支把「可强制覆盖」当成失败却不入 journal，且成功判定只看 `result.ok`

**文件:行号**：`lib/surface/pages/code_editor_page.dart:216-297`（`_submitInBackground`），尤其 `:238-255`；`lib/domain/gh/gh_client.dart:181-...`（`GhWriteResult`）；`lib/domain/gh/gh_api.dart:841-915`（`putContentLocked`）

**问题**：后台提交遇到冲突时，`if (!result.ok && result.canForceOverwrite)` 只发通知/日志并 `return`。此时**用户点保存时已经立刻 `Navigator.pop(true)` 离开页面**（`:228-233`），且 `_save()` 里 `unawaited(_persistDraft())` 是 fire-and-forget —— 若草稿落盘在冲突返回前没完成，或用户按 B2-B-01 的路径进来草稿已被删，则：**冲突内容既不在 journal（D8 只在 `_writeLocked` 里 `enqueue`，冲突被 D2 拦下时按设计不入队，见 `disk_cache.dart:660-664` 注释），也不一定在草稿里**。注释说「草稿保留原内容，重新进入编辑器即可处理」，但没有任何机制保证这一点。
另外 `result.ok` 为 `true` 时**无条件 `discardDraft`**（`:278-286`），而 B2-B-03 已证明 `ok: true` 可能来自「空 sha / 假回执」的 D5 成功路径 —— 即用户内容可能没到远端，草稿却被清掉。
`_save()` 先 `_saved = true; _savedText = text;` 再提交（`:221-224`），`dispose()` 的 `savedClean` 判据因此**不再回写草稿**；这意味着一旦后台写失败，页面已经把「已保存」闩锁置位，**本机副本的自动保护被主动关闭**，只剩那一次 fire-and-forget 的 `_persistDraft()` 兜底。

**用户可见后果**：**数据丢失**。冲突（staleSha）后用户看到一条警告通知，但重新进入编辑器可能发现草稿没了；只能靠通知中心的文字回忆自己写了什么。空 sha 假成功时更糟：用户看到「已提交」且草稿被清，内容永久丢失。

**违反原则**：8、13（失败必须可恢复）、15、17、22（异步结果需校验仍有效）、10（并发写必须被乐观锁看见，冲突应可解而非丢内容）。

**代码证据**：
```dart
// code_editor_page.dart:221-233
_saved = true; _savedText = text;
unawaited(_submitInBackground(text, baseSha));
Navigator.of(context).pop(true);
// code_editor_page.dart:238-255 —— 冲突只通知，草稿/日志无保障
if (!result.ok && result.canForceOverwrite) {
  ... OgLAppLog.instance.add(... severity: warning);
  return;
}
// disk_cache.dart:660-664 —— D1/D2/D7 拦下的意图按设计不入队
// D8：只有"真正要发出去的写"才入队 —— D1/D2/D7 拦下的意图不产生待办
```
`OgLAppLog` 日志仅含冲突文字与 `result.detail`，**不含用户提交的正文 `text`**，无法从日志恢复内容。

---

## B2-B-10 · P1 · 确证 —— D6「失败返回结果」并非都带可读 reason 与诊断码：诊断码只进日志、不进 `WriteOutcome`；`deleteContentLocked` 退化分支与 `WriteOutcome.failure` 的 `detail` 可为 null

**文件:行号**：`lib/kernel/contract/disk_types.dart:352-371`（`WriteOutcome.failure` 的 `detail` 可选）、`:373-410`（类字段）；`lib/base/disk/disk_cache.dart:787-826`（`_fail`）、`:357-361`（`delete` 成功）、`:311-321`（`delete` 未确认）；`lib/domain/gh/gh_api.dart:963-977`（退化删除 `ok: true` 无 detail）、`:859-910`（退化写）

**问题**：
1. **诊断码不随结果返回**：`_fail(intent, conflict, detail, {required String code, ...})` 把 `code`（`OGL-CONS-2xx`）写进 `_diagnostics.error` 的 `data`，但 `WriteOutcome.failure(...)` 只传 `detail`，**从不传 code**。`WriteOutcome` 类型里根本没有 `code` 字段。展示层（`GhWriteResult`）也没有诊断码字段，`ghWriteConflictText` 只能把 `conflict` 枚举转成文字。用户/排查者拿到「写入失败」时无法把界面提示与日志里的 `OGL-CONS-202` 关联起来 —— D6「失败可感知」在结果侧缺了诊断码这一半。
2. **部分失败结果没有可读 reason**：`WriteOutcome.success` / `WriteOutcome` 直接构造时 `detail` 缺省为 `null`（`disk_cache.dart:357-361` 删除成功、`gh_api.dart:963-977` 退化删除成功）。失败侧：`deleteContentLocked` 退化分支在 `deleteContent` 抛异常时**不捕获**，直接外抛（不是「返回结果」）；`putContentLocked` 退化分支只捕获 `RemoteConflictException`，其它异常外抛，违反 `:846` 的「永不抛」承诺。`GhWriteResult` 的 `detail` 来自 `outcome.detail`，可为 `null`，`code_editor_page.dart:246-266` 用 `result.detail ?? ''` / `?? conflict` 兜底 —— **空串会被渲染进通知文案**（「失败原因：」后面什么都没有），违反原则 36（绝不渲染空串）与 38（错误信息面向用户）。
3. `detail` 中确有可读文字的分支（`:272` `'写入异常终止：$error'`、`:614` `'缺少基线 SHA…'`）算合格；但 `_classify` 把 403 映射为 `forbidden`、404 → `notFound` 时，`'远端冲突未解决（D3, HTTP ${error.statusCode}）'` 没有翻译服务端原话（`_snippet` 在 `gh_client.dart:811` 有，但未透传），用户只能看到 HTTP 数字。

**用户可见后果**：**失败不可诊断**。用户看到「提交失败」却不知道原因/能做什么；排查时无法用界面上的信息检索日志。空 detail 时提示残缺。

**违反原则**：15、16、17（用类型表达失败：诊断码应成为结果的一部分而非仅日志）、38（错误信息面向用户：说发生了什么、能做什么）、36、42。

**代码证据**：
```dart
// disk_cache.dart:787-826 —— code 只进日志
_diagnostics.error('CACHE', '写入失败：${conflict.name}', code: code, data: {...});
...
return WriteOutcome.failure(conflict, detail: detail, sha: sha, ...); // 无 code
// disk_types.dart:373-410 —— 类里没有 code 字段
// gh_api.dart:969-976 —— 退化删除 ok:true，detail 缺省 null
return GhWriteResult(ok: true, conflict: GhWriteConflict.none, baseSha: baseSha);
// code_editor_page.dart:246-249 —— detail 为空串
'conflict': conflict, 'detail': result.detail ?? '',
```

---

## B2-B-11 · P1 · 确证 —— 磁盘索引/草稿/日志解析失败一律 `catch (_)` 静默清理，「退回默认值/内存」不告警；平台存储解析失败只上报启动期，运行期损坏无声

**文件:行号**：`lib/base/disk/disk_cache.dart:1004-1007`（`_evictEncoded`）、`:951-1002`（`_loadLocal` 的 `catch (_)` 静默丢弃）、`:920-930`（`_readMeta` 的 `catch (_)`）、`:933-943`（`_scanMetas` 损坏索引直接 remove）；`lib/base/disk/disk_draft.dart:143-155`（`_loadUnlocked` catch 清除）、`:189-214`（`all()` catch 清除）、`lib/base/disk/disk_journal.dart:132-152`（`fromJson` catch 返回 null）、`:271-283`（`records()` 损坏记录直接 remove）；`lib/base/disk/platform_io_impl.dart:375-387`（`IoDiskKv.read` catch 清文件）、`:167-175`（`_index()` catch 返回空 Map）、`:182-188`（`_saveIndex` catch 放弃）、`:231-245`（`_readPacked` catch 当不存在）；`lib/base/disk/og_l_storage_saf_io.dart:91-100`（`loadConfig` catch 当未授权）、`:104-116`（`saveConfig` catch）

**问题**：范围里几乎每个反序列化点都是「结构坏 → 删掉/当不存在 → 继续」，且**没有一处调用 `_diagnostics` 记录**：
- `_loadLocal` 在完整性校验失败时**有** `OGL-CONS-208` 错误日志（好的），但 `catch (_)` 那一路（旧 schema / `jsonDecode` 抛 / 类型不符）**没有日志**，直接 `_evictEncoded` —— 用户本地缓存被静默抹掉，下次回源；若离线则「文件读不到」且无原因。
- `_scanMetas()` 遇到坏索引 `await _index.remove(key)` 无日志；`WriteJournal.records()` 遇到坏记录 `await _store.remove(key)` 无日志 —— **D8 的 pending 提交记录被静默删除**：用户以为「有 N 项未完成」，实际记录已被抹掉，重启后待同步列表凭空少一项，内容无法恢复。这是最严重的一处（journal 是恢复依据，原则 14）。
- `DraftStore.all()` / `_loadUnlocked` 同样静默删除坏草稿 —— **用户写的正文被静默销毁**。
- `IoDiskFileStore._index()`（长路径收纳索引）读失败返回空 Map ⇒ 已收纳的内容「找不到」；`_saveIndex` 写失败只 `catch` 不留痕，注释自己承认「无法自动还原」；`_readPacked` 收纳包损坏当不存在。
- `og_l_storage_saf_io.dart:91-100` `loadConfig` 失败当作「未授权」⇒ 用户**已授权的 SAF 目录被判未授权**，成品导出静默跳过；`saveConfig` 写失败静默，用户下次进来授权丢失。
- 启动期 `storageError` 确实「大声上报」（`main.dart:231-243`，通知中心 critical + 应用日志），这一条**合格**；但「解析失败退回默认值」的运行期路径全不合格。

**用户可见后果**：**静默数据丢失**（journal pending、草稿正文、缓存条目被无声删除）、**静默降级**（SAF 授权/导出失效、长路径内容读不回），且日志里找不到任何线索。

**违反原则**：20（外部数据不可信；坏数据夹紧回默认值**并记录** —— 这里只夹紧不记录）、15、16（不吞异常）、14（写日志的时间点是恢复依据）、13、21（降级路径必须有触发条件、有观测、有退出条件）。

**代码证据**：
```dart
// disk_journal.dart:275-282 —— pending 记录被静默删除
final record = _decode(raw);
if (record == null) { await _store.remove(key); continue; }
// disk_draft.dart:205-212 —— 草稿被静默删除
if (record == null) { await _store.remove(key); continue; }
} catch (_) { await _store.remove(key); }
// platform_io_impl.dart:167-175 / 184-188
} catch (_) { return <String, String>{}; }
} catch (_) { /* 索引写不进去只能放弃：内容仍在包里，只是无法自动还原。 */ }
// 对照：唯一合格的是启动期 main.dart:231-243 的 storageError 上报
```
（`KernelDiagnostics` 在 `DiskModule.onRegister` 里已通过 `attachDiagnostics` 注入到 cache/journal/draft，`disk_bridge.dart:126-128`，所以「无注入点」不是理由；SAF 桥确无注入点，但其注释用 debugPrint 留痕，release 被剥离 ⇒ 仍属静默。）

---

## B2-B-12 · P1 · 确证 —— `prune`/`purge` 的清理顺序与「有界淘汰」边界：`_evictIfStale` 的并发复核用 `fetchedAt.isAfter(scannedAt)`，等于扫描时刻本身的数据一律可删；`maxEntries<0` 无上限且无日志

**文件:行号**：`lib/base/disk/disk_cache.dart:391-428`（`prune`）、`:481-495`（`purge`）、`:1009-1030`（`_evictIfStale`）、`:134-145`（构造函数默认值/`defaultMaxAge`/`readbackAttempts`）；`lib/surface/surface_bridge.dart:170`（`clearRepositoryCache`）

**问题**：
1. **有界淘汰边界（`maxEntries < 0`）**：`prune` 中 `if (limit > 0 && survivors.length > limit)`，`limit = maxEntries ?? defaultMaxEntries`。构造函数注释写「`<= 0` 表示不设上限」（`:131`），因此 `maxEntries = -1` / `0` 会**完全关闭有界淘汰**，缓存可无界增长直到写满磁盘 —— 与原则 29「所有资源有上限」及文件头「磁盘是有界的」（`:389`）矛盾。更关键的是：这个「无上限」是**调用方可传的捷径参数**，等价于原则 11 禁止的「绕过校验的开关」。`Duration maxAge <= Duration.zero` 同理关闭 TTL（`_isExpired:878-885`）。默认值 512 / 30 天是安全的，但边界值没有夹紧、没有告警、没有诊断日志。
2. **淘汰并发复核的边界错误**：`_evictIfStale` 的判据是 `if (fresh != null && fresh.fetchedAt.isAfter(scannedAt)) { return; }` —— 用的是**严格 `isAfter`**。若扫描与淘汰之间有一次写入，其 `fetchedAt` 恰好等于 `scannedAt`（同毫秒、或测试/内存实现用固定时钟），或 `_loadLocal` 因完整性失败返回 `null`（见 B2-B-11），则复核失效，**刚写回来的热数据被删掉**（注释 `:1010-1013` 声称要防的正是这件事）。
3. **清理顺序**：`_evictEncoded` 先删 index 后删 blob（B2-B-05）；`prune` 在 TTL 分支用 `_evictIfStale`（进 `_mutex`），但 `purge` 之后调用的 `purgeOrphans()` **完全不进互斥**（`:491`、`:506-530`），与并发 `_saveLocal` 竞态时可能删掉刚写的 blob。
4. `prune` 只在 `removed > 0` 时记 `OGL-CONS-002`，且 data 里的 `remaining` 用的是 `survivors.length`（TTL 淘汰前的候选数未按实际删除修正），诊断数字可能不准；`purgeOrphans` 删除孤儿**不记录被删文件名**，无法审计误删。

**用户可见后果**：**静默损坏 / 磁盘无界增长**。热缓存被误删 ⇒ 弱网下反复回源「越用越慢」，甚至读到旧内容作为下一次写的基线；`maxEntries<=0` 时磁盘被写满后连「保存用户刚写的文件」都失败（文件头注释自己点名的真事故）。

**违反原则**：29（所有资源有上限）、11（防线没有开关）、13、28、15（降级/边界不告警）、8。

**代码证据**：
```dart
// disk_cache.dart:398-417
final limit = maxEntries ?? defaultMaxEntries;
...
if (limit > 0 && survivors.length > limit) { ... }   // <=0 ⇒ 无上限，无日志
// disk_cache.dart:1019-1026
final fresh = await _loadLocal(decoded);
if (fresh != null && fresh.fetchedAt.isAfter(scannedAt)) { return; }
await _evictEncoded(encoded);   // fresh == null（含校验失败）也照删
// disk_cache.dart:140 默认 readbackAttempts = 1 ⇒ D5 实际「不重试」，与注释「带少量重试」不符
```

---

## B2-B-13 · P2 · 确证 —— `expectedSha256` 下载完整性校验与仓库缓存写入不同源：下载侧允许「无摘要 = 未校验 = 成功」，缓存侧无内容摘要绑定

**文件:行号**：`lib/domain/ix/ix_download.dart:631-705`（`enqueue` 登记 `_expectedSha256`）、`:1194-1240`（`_verifyIntegrity`）；`lib/surface/pages/release_detail_page.dart:292`（摘要来自 `asset.raw['digest']`）；`lib/base/disk/disk_cache.dart:857-866`（`_entryOf` 算 `contentHash`）、`:945-949`（`_saveLocal`）；`lib/kernel/contract/disk_types.dart:381-395`（`CacheEntry.contentHash` 仅本地自算）

**问题**：两套「内容完整性凭据」互不相干：
1. **下载侧**：`expectedSha256` 只在调用方显式传入时登记（`release_detail_page.dart:292` 从 Release 资产的 `digest` 取）；`_verifyIntegrity` 在 `expected == null || expected.isEmpty` 时 `return true`（**当作成功**，仅记 `OGL-DL-401` info 标记「未校验」），`!_backend.canReadLocalFile` 时同样 `return true`（`OGL-DL-406` warn）。仓库文件下载（repo/gist/other 分类、`IxDownloadManager` 的常规入口）**没有传 expectedSha256**，因此绝大多数落盘文件根本没做完整性校验，却以 `completed` 状态展示。
2. **缓存侧**：`CacheEntry.contentHash = sha256(utf8.encode(content))` 是**本地自算自验**（`_loadLocal:977` 拿落盘 blob 再算一遍比对 index 里的 hash），只能发现「落盘后损坏」，**不能发现「网络返回的内容本身就是错的/被替换的」** —— 代理截断或篡改的内容会被照样算出 hash 并写进索引，之后每次读都「校验通过」。`GhApi.read`（`gh_api.dart:1929-1990`）用 `parsed.sha`（GitHub blob sha）作为 `RemoteDocument.sha`，但**从不本地重算 Git blob sha 与 `parsed.sha` 比对**，所以「服务端给的 sha 与正文是否一致」也没有验证。
3. 二者**没有共享凭据**：下载校验过的成品不会把 digest 传给 `RepositoryCache`，缓存写入也不会去查下载侧记录的 digest；`expectedSha256` 存在 `_expectedSha256` 内存 Map（`ix_download.dart:1194`），进程重启即失，落盘成品也没有伴随的 `.sha256` 旁文件。

**用户可见后果**：**静默损坏**。通过加速通道/镜像下载的文件可能是被替换的内容，用户以「已完成」状态打开/安装；缓存里被篡改的私有文件正文会被当作可信基线参与下一次提交，把错误内容写回 GitHub。日志里只有「未校验」的 info，用户很难察觉。

**违反原则**：28（缓存键必须覆盖产生差异的全部维度 / 内容凭据同源）、42（失败如实报错，未校验不应等于成功）、15、20、39、43（加速通道返回内容需验证）、46（发布产物指纹/校验）。

**代码证据**：
```dart
// ix_download.dart:1207-1216
final String? expected = _expectedSha256[id];
if (expected == null || expected.isEmpty) {
  _diagnostics?.info('DL', '...已如实标记为未校验...', code: 'OGL-DL-401');
  return true;                       // ← 未校验 == 成功
}
// disk_cache.dart:857-866
contentHash: await _hashOf(document.content),   // 自算，无外部期望值
// gh_api.dart:1987-1990
return RemoteDocument(content: text, sha: parsed.sha);  // 不校验 text 与 sha 匹配
// release_detail_page.dart:292 —— 只有 Release 附件传了摘要
expectedSha256: IxPresign.normalizeDigest(asset.raw['digest']),
```

---

## B2-B-14 · P2 · 确证 —— `CacheRemote.read`/`write` 完全忽略 `key.scope.accountId`，读回执可能来自共享的只读缓存；`guest` 作用域跨会话复用

**文件:行号**：`lib/domain/gh/gh_api.dart:1929-1990`（`CacheRemote.read`）、`:1993-2007`（`write`）、`:1009-1017`（`delete`）、`:88-116`（`_cacheKeyFor`）；`lib/domain/gh/gh_client.dart:541-559`（只读缓存命中路径）、`:445-495`（`ttlForPath`）

**问题**：`CacheKey.scope.accountId` 是「多账号隔离的第一道闸」（`disk_types.dart:32-34`），但 `GhApi` 的三个 `CacheRemote` 方法只取 `key.scope.repo` / `key.scope.branch` / `key.path`，**从不读取 accountId**，请求用 `client.send` 携带的是 `_auth.activeToken()`（当前会话令牌，非该键所属账号的令牌）：
1. `read(key)` 用当前令牌读 `key.scope.repo` —— 若 journal 里残留另一个账号的 pending 记录（B2-B-06），`replayPending` 会以当前账号身份读/写那个账号的仓库，读到 404 就 `return null`，进而触发 `D2′`「远端目标已不存在」或 `notFound`，把别人的待办标成 `abandoned`。
2. `read` 走 `client.send(GhRequest(...))` 而非 `_contentNetwork`，**未设 `cacheBypass`**；`ttlForPath` 对 `/contents` 显式返回 `null`（`gh_client.dart:455-457`），所以内容读不会被只读缓存污染 —— 这一点是**合格**的（不列为缺陷）。但 `_defaultBranchOf`（`:2043-2053`）与 `GhReadCache` 的其它只读端点带账号维度，与 `CacheRemote` 的无账号维度形成不一致。
3. `_cacheKeyFor` 的 `catch (_) { account = 'guest'; }`（`:106-108`）：账号读取失败不报错、不重试、不留痕，直接把请求**降级到共享 guest 作用域**。所有「provider 异常」的会话共用同一份缓存，可能读到前一个会话（不同账号/未登录）缓存的私有仓库内容 —— 虽然 `guest` 键与登录态键不同，但**guest 本身是一个跨会话、跨身份的公共桶**。

**用户可见后果**：**本地数据泄露面 / 跨账号错写**。journal 重放用错令牌；账号 provider 抖动时缓存身份漂移，用户可能看到不属于当前身份的缓存内容（尤其实在「退出登录后以游客浏览」与「重新登录」之间）。失败可见性为零（catch 无日志）。

**违反原则**：28（键必须覆盖产生差异的全部维度；实现却丢弃 accountId）、39、15、16、21（降级无观测）、9。

**代码证据**：
```dart
// gh_api.dart:1929-1933
final repo = key.scope.repo;
final branch = key.scope.branch;
final String path = key.path;      // ← 无 key.scope.accountId
// gh_api.dart:100-108
var account = 'guest';
try { ... } catch (_) { account = 'guest'; }   // 静默降级，无诊断
// disk_types.dart:32-34
/// 账号标识（多账号隔离的第一道闸）。
```

---

## B2-B-15 · P2 · 确证 —— journal `fail`/`abandon` 的留痕不完整：`fail` 无诊断日志、`_fail` 与 `replayPending` 双重记账、异常路径的 `failByKey` 可能标错记录

**文件:行号**：`lib/base/disk/disk_journal.dart:222-238`（`fail`）、`:241-260`（`failByKey`）、`:262-280`（`abandon`）、`:283-306`（`records`）；`lib/base/disk/disk_cache.dart:264-276`（`write` 的 `catch` → `failByKey`）、`:787-826`（`_fail` → `journal.fail/abandon`）、`:439-471`（`replayPending` → 再次 `fail/abandon`）

**问题**：
1. **`fail()` 没有任何 `_diagnostics` 调用**（对比 `enqueue` 有 `OGL-JOURNAL-001`、`complete` 有 `-002`、`abandon` 有 `-003`）：一次可重试失败只把 `attempts+1` / `lastError` 写进 KV，日志里查不到「这次写为什么没成功」。用户在「待同步」列表看到数字一直涨，却没有时间线。
2. **双重记账**：`_writeLocked` 的冲突分支调用 `_fail(..., journalId: journalRecord?.id)`（`:751-765`），`_fail` 内部 `await journal.fail(journalId, detail)`（`:813`）；而 `write()` 的外层 `catch`（`:264-276`）在同一异常传播路径上又调 `await _journal?.failByKey(intent.key, ...)`。若 `_fail` 里的 `journal.fail` 自身抛错（磁盘故障），异常冒泡到外层 catch ⇒ **同一条 pending 被记两次**（一次按 id、一次按键匹配「最近一条」），`attempts` 虚增，5 次上限被提前触发 ⇒ 记录被 `abandon`，用户待办提前消失。
3. **`failByKey` 选「最近一条」而非「刚发出的那一发」**：注释（`:243-248`）承认按 `createdAt` 取最新，但同一键多次崩溃会留下多条 pending；`_writeLocked` 的 `enqueue` 返回 `journalRecord.id`，而外层 `catch` 拿不到这个 id（它在 `_mutex.run` 之外），只能靠启发式匹配 ⇒ 可能把错误记到另一条 pending 上。这是「用类型表达失败」缺失（原则 17）的直接后果：id 没有随异常/结果传递。
4. `abandon` 把 `status` 改为 `abandoned` 后，`pendingCount()` 不再计入，但 `records()` 默认（不传 status）仍返回；`clear()` 会连 abandoned 一起删。**UI 是否有「已放弃」入口**在本次范围内未确证 ⇒ 标待议；但「abandon 的记录没有恢复为可重试/可查看的明确出口」是确证的语义缺口（原则 13「能被重启发现」只靠 `records()` 枚举，没有主动上报）。

**用户可见后果**：**失败不可见 / 待办静默消失**。用户以为「网络恢复后会自动补交」，实际记录已被 abandon 且不再重放；日志里没有失败原因，排查者无法还原「第几次、为什么失败」。

**违反原则**：15、16、17、13（半成品状态必须留有痕迹并能被重启发现）、14、26（写操作幂等或防重 —— 记账本身不幂等）。

**代码证据**：
```dart
// disk_journal.dart:222-238 —— fail 无 diagnostics
Future<void> fail(String id, String error) async {
  final record = await _read(id);
  if (record == null) { return; }
  final int attempts = record.attempts + 1;
  if (attempts >= maxAttempts) { await abandon(id, '重试 $attempts 次仍未成功：$error'); return; }
  await _write(record.copyWith(attempts: attempts, lastError: error));
}
// disk_cache.dart:272 —— 外层 catch 二次记账
await _journal?.failByKey(intent.key, '$detail：$error');
// disk_cache.dart:813 —— _fail 内一次记账
await journal.fail(journalId, detail);
```

---

## B2-B-16 · P2 · 确证 —— `DiskVault`/`SecureDiskVault` 的令牌密钥无前缀命名空间冲突校验、删除失败被吞；`InMemoryVault` 降级无任何上报

**文件:行号**：`lib/base/disk/platform_io_impl.dart:421-438`（`SecureDiskVault`）、`lib/kernel/contract/disk_store.dart:26-35`（`DiskVault` 接口）、`:82-102`（`InMemoryVault`）；`lib/base/disk/disk_bridge.dart:66-73`（`DiskModule` 缺省 `InMemoryVault()`）；`lib/domain/domain_bridge.dart:166-169`（vault 交给 `GhAuthService`）

**问题**：
1. **接口无失败语义**：`DiskVault.writeSecret` 返回 `Future<void>`，`readSecret` 返回 `Future<String?>`。写入失败（Keystore 不可用、用户锁屏、DPAPI/libsecret 故障）在 `FlutterSecureStorage` 会抛异常，但 `GhAuthService` 侧的处理不在本次范围；接口本身**没有 `bool`/结果类型**表达「写失败」，原则 17「让调用方无法忽略错误」在契约层就缺失。`readSecret` 的 `null` 既表示「不存在」也表示「读失败」，两者不可区分。
2. **`_prefix = 'ogl.vault.'` 是唯一隔离**：`deleteSecret('ai.secret')`（`domain_bridge.dart:174`）这类清理按固定 key 删除；若上层 key 含意外字符或与其它模块共用同一 `FlutterSecureStorage` 实例（默认构造，无指定 `aOptions`/`iOptions`），键空间没有枚举/校验/冲突检测。更重要的是 `SecureDiskVault` **没有 `toString` 脱敏**（`disk_bridge.dart:45-48` 的 `DiskBridge.toString` 只打印 `runtimeType`，不打印值 —— 这一点合格），但 `InMemoryVault.snapshot`（`disk_store.dart:88-90`）返回一个**未加密、可直接读取全部令牌的 Map**，任何拿到该对象的测试/诊断代码都能把令牌打印进日志（原则 39「脱敏从 toString 开始」在此处靠调用方自律）。
3. **降级无上报**：`DiskModule` 缺省 `vault = InMemoryVault()`（`disk_bridge.dart:68`）。若组合根误用 `baseLayerModules(net: net)` 而非 `baseLayerModulesOnPlatform()`（或 `PlatformStorage.open` 失败，`base_bootstrap.dart:35-41` 走的就是这条），**令牌只存在内存、重启即丢**，而 `storageError` 上报只说「登录与设置将无法保存到本机」（`main.dart:236-241`），**没有单独说明「令牌未进系统密钥库」这一凭证安全降级**。`SecureDiskVault` 构造不需要任何能力探测，失败会在首次 `read/write` 时抛 —— 没有启动期校验（原则 25「启动失败必须回滚已启动的部分」）。

**用户可见后果**：**凭证**。令牌可能只驻留内存（重启后静默掉登录态，用户以为被登出）；`InMemoryVault.snapshot` 与未脱敏的调试路径可能把令牌写进日志/通知；密钥库写失败若被调用方吞掉，会出现「登录成功但重启失忆」。

**违反原则**：39（凭证只进系统密钥库，永不进日志、通知与序列化数据；脱敏从 toString 开始）、17（用类型表达失败）、15、16、21（降级路径必须有观测）、25。

**代码证据**：
```dart
// disk_store.dart:26-35 —— 接口无失败类型
abstract class DiskVault {
  Future<String?> readSecret(String key);
  Future<void> writeSecret(String key, String value);
  Future<void> deleteSecret(String key);
}
// disk_store.dart:88-90 —— 内存保险库快照暴露全部明文
Map<String, String> get snapshot => Map<String, String>.unmodifiable(_secrets);
// disk_bridge.dart:68
vault = vault ?? InMemoryVault(),
// main.dart:236-241 —— 上报文案未提「令牌未进系统密钥库」
detail: '平台存储初始化失败，登录与设置将无法保存到本机。\n$storageError',
```
**「待议」部分**：`GhAuthService` 对 `writeSecret` 抛错的实际处理（是否吞掉）不在本次范围内，需读 `lib/domain/gh/gh_auth_service.dart` 才能定级；「接口无失败类型」与「降级上报文案不含凭证风险」为确证。

---

## B2-B-17 · P2 · 确证（待议：达成条件） —— `CacheRemote.read` 裸 `jsonDecode(body)` 未捕获，截断的 206 读回执以异常形式逃逸 D5 与 content() 的兜底

**文件:行号**：`lib/domain/gh/gh_api.dart:1953-1961`（`CacheRemote.read`）、`:585-590`（`content()` 的 `catch (_)` 落回网络）、`:799-810`（`putContent` 的 206 回读）；`lib/domain/gh/gh_client.dart:326-334`（`jsonObject` 才捕获解析异常）

**问题**：`GhApi.read`（CacheRemote 实现）**自己** `final Object? decoded = jsonDecode(body);`（`:1959`），没有 try/catch；而 `GhResponse.jsonObject`（`gh_client.dart:326-334`）是带 `try/catch` 返回 `null` 的。两条路径对「206/代理截断的 body」处理不同：
- `content()` → `_cache.read` → `CacheRemote.read` → `jsonDecode` 抛 `FormatException` ⇒ `content()` 的 `catch (_)`（`:585-587`）落回 `_contentNetwork` ⇒ `GhContent.fromJson` 用 `jsonObject`（返回 null）⇒ 返回 `null`，用户看到「文件不存在/空」，**无报错**（原则 42）。
- `_writeLocked` 的 D5 `_verifyReadback`（`disk_cache.dart:758-768`）调用 `_remote.read(key)`，同样会抛 `FormatException`；该异常**不是 `RemoteConflictException`**，冒泡到 `write()` 的外层 `catch`（`:264-276`）→ `_fail(server, '写入异常终止…')` ⇒ 但此时 **PUT 其实已在远端成功**，返回 `ok: false` 会让 UI 假报错、用户重试造成二次提交（正是 `disk_cache.dart:686-690` 注释声称已经修掉的情形 —— 修的是「回读不一致返回 null」，没修「回读抛异常」）。
- 由于 `_verifyReadback` 默认 `readbackAttempts = 1`（`disk_cache.dart:140`），没有第二次机会；且 `readbackDelay` 永远不会被用到。

**用户可见后果**：**静默损坏 / 伪造失败**。206 截断时用户看到「写入失败」但远端已提交；重试会撞 422 或（在无 baseSha 的新建路径）生成重复提交；`content()` 静默返回 null 让用户以为文件被删了。

**违反原则**：42、20（反序列化永不抛异常，坏数据夹紧回默认值并记录）、16、18（捕获范围精确到能处理的异常）、17（用类型表达失败）、41（只重试幂等方法 —— 假失败诱发用户重试非幂等 PUT）。

**代码证据**：
```dart
// gh_api.dart:1953-1961
final String probe = body.trimLeft();
if (probe.startsWith('[')) { ... }
final Object? decoded = jsonDecode(body);   // ← 无 try/catch
if (decoded is! Map) { return null; }
// 对照 gh_client.dart:326-334 有 catch (_) { return null; }
// disk_cache.dart:758-768 —— 无异常处理
final document = await _remote.read(key);
```
**待议标注**：本条成立需要「206 的 body 是语法不完整的 JSON」这一前提（代理在任意字节截断时通常如此）；若代理返回的是一个完整但内容错误的 JSON，则走 B2-B-02 的「伪造成功」路径而非本条。两条覆盖同一威胁的不同分支，故本条主结论（**`jsonDecode` 无捕获 + D5 未隔离读异常**）为确证，具体触发形态标待议。

---

## B2-B-18 · P2 · 确证（部分待议） —— 写回执源头（传输层）不区分 206：不校验 `Content-Length`/`Content-Range`，截断 body 经 `utf8.decoder` 变成 U+FFFD 或抛异常；3xx 对写方法原样交还上层

**文件:行号**：`lib/base/net/io_net_transport.dart:229-260`（`send` 的 body 读取）、`:262-330`（`_sendWithGuardedRedirect`）、`:48-93`（`_ogLIsSafeRedirectTarget`）；`lib/domain/gh/gh_client.dart:311`（`isSuccess` 含 206）、`:632`（只读缓存才排除 206）

**问题**：这是「206 / 代理截断」写回执的**产生处**，三处缺口向上游一路传导到 B2-B-02/B2-B-03/B2-B-17：
1. `send()` 用 `await response.transform(utf8.decoder).join().timeout(request.timeout)` 读 body，**没有**把 `response.contentLength` 与实际字节数比对，也没有检查 `Content-Range`。206 的片段被当成完整实体交给 `NetResponse.body`；`GhResponse.isSuccess`（`gh_client.dart:311`）把 206 归入成功，`_throwIfFailed`（`:729-733` 的 `status >= 200 && < 300 ⇒ return`）不拦。`gh_client.dart:632` 只在**回填只读缓存**时排除了 206，写回执路径完全没排除。
2. 截断若发生在多字节 UTF-8 中间，`utf8.decoder` 默认产生替换字符 U+FFFD（不抛）⇒ `GhContent.decodeContent` 解出的正文可能与用户提交的不同，但**语法完整的截断**仍能被 `jsonDecode` 解析；若抛 `FormatException`，`send()` 的 `on Object catch`（`:273-275`）把它包成 `NetException(unknown, '未知网络错误…')` —— 一个「连接类」而非「回执不完整」的错误，用户看到的是网络问题，不是「提交状态未知」。
3. **重定向对写方法**：`_sendWithGuardedRedirect` 在跨主机/不安全目标/次数用尽时把 3xx **原样返回**（`:295-312`）。对 PUT/DELETE 而言，`GhClient._throwIfFailed` 会走 `default` 抛 `GhAuthException('请求失败（HTTP 3xx）…')` ⇒ `putContent` 不捕获 ⇒ `disk_cache.dart:264-276` 变成 `server` 失败、journal 留 pending。**若服务端已处理该写请求后才发 3xx（代理/网关常见），这就是「远端已提交但 UI 报失败」**，与 B2-B-17 同型；是否真的会发生取决于服务端行为 ⇒ 标待议。
4. `_ogLIsSafeRedirectTarget` 只做字面量判定（十进制点分 IPv4、`[` 或含 `:` 的 IPv6 前缀），**不覆盖十进制整数 IP（`2130706433`）、八进制/十六进制、IPv4-mapped IPv6（`::ffff:127.0.0.1`）**；注释称「域名形式由 TLS 证书校验兜底」，但证书校验防的是身份冒充，不是「把请求打到本机/内网」这一 SSRF 本身（自定义 DNS `connectionFactory` 会把解析结果直连 IP，`:155-186`）。⇒ 待议（需实测 `dart:io` 对这类 host 的解析与 SNI 行为）。

**用户可见后果**：**静默损坏 / 伪造成功或失败**。截断的写回执被当成权威 sha（B2-B-02）；字节级损坏的正文可能被写进本地索引并成为下次提交基线；3xx 假失败会诱导用户重试非幂等 PUT（原则 41）。

**违反原则**：42、20、18（兜底一切 `on Object catch` 是 bug 藏身处）、41、44（对外部目标保持怀疑，拒绝回环/私网/元数据地址是下限）、15、28。

**代码证据**：
```dart
// io_net_transport.dart:239-247
final String text = await response.transform(utf8.decoder).join().timeout(request.timeout);
return NetResponse(statusCode: response.statusCode, body: text, ...);  // 无 206/长度校验
// io_net_transport.dart:273-275
} on Object catch (error) { throw NetException(NetErrorKind.unknown, '未知网络错误（$error）', cause: error); }
// gh_client.dart:311
bool get isSuccess => statusCode >= 200 && statusCode < 300;
// gh_client.dart:632 —— 只有只读缓存排除了 206
if (response.isSuccess && response.statusCode != 206) { ... }
```
（正面记录：`_sendWithGuardedRedirect` 对 302/303 只对 POST 降级 GET、PUT/DELETE/PATCH 保持方法与 body、跨主机不跟随、拒绝 https→http 降级 —— 这几条修得正确，不属于缺陷。）

---

## B2-B-19 · P1 · 确证 —— 定时重放 `replayPending()` 每 30s 无条件重放 pending，不校验危险操作确认、不等网络恢复、不防重；与 `idleTicks` 自停逻辑叠加导致「待办永久挂着」或「重复提交」

**文件:行号**：`lib/domain/domain_bridge.dart:207-256`（启动重放 + `Timer.periodic`）；`lib/base/disk/disk_cache.dart:439-471`（`replayPending`）、`:660-664`（D8 入队）、`:679-717`（`_writeLocked` 成功路径）；`lib/base/disk/disk_journal.dart:222-238`（`fail` 的 maxAttempts=5 → abandon）

**问题**：
1. **危险/需确认操作被静默吞在队列里**：`replayPending({bool confirmed = false})` 默认 `false`，定时调用处**从不传 `confirmed: true`**。若 `WriteIntent.dangerous/force` 曾入队（`_writeLocked` 在 `confirmed=true` 时入队并写成功；但失败时 journal 记录保留 `dangerous`），重放会命中 `_writeLocked:607-614` 的 `needsConfirmation`，`replayPending:454-457` 的注释说「必须保持 pending，等用户点头」。结果：**没有任何 UI/入口会来点头**（本次范围内未见），定时重放每 30s 撞一次 `needsConfirmation`，`idleTicks` 因 `outcomes` 非空而**永远不增长** ⇒ 定时器永不自停，记录永久 pending，用户看到「待同步」数字一直不变。
2. **重复提交风险（写非幂等）**：后台写链路 `_submitInBackground` 与定时重放可能同时针对**同一个键**在途：`_mutex` 只按 `key.encode()` 串行化同一个 `RepositoryCache` 实例内的操作，但 `journal.complete` 只在 `_writeLocked` 成功路径末尾执行。若第一次写已在远端成功、却在 `complete` 前被 30s 定时重放读取到仍为 pending 的记录，重放会带着**旧 baseSha** 再走 D1/D2；`_remote.read` 此时返回新 sha ⇒ `staleSha` 拦下（这一支安全），但若 `force` 意图或用 `_contentNetwork` 取到旧缓存，则会以「刚读到的远端版本」为期望**再提交一次** ⇒ 生成重复 commit（原则 26/41）。
3. **重放不等网络恢复**：`Timer.periodic` 固定 30s，无网络状态判定、无退避、无 `Retry-After`。离线时每轮把全部 pending 打一遍，每次 `fail()` 使 `attempts+1`，5 轮（约 150s）后**全部转 `abandoned`** ⇒ 用户的待同步提交被静默放弃、不再自动重放，而用户从未看到任何一条「已放弃」通知（`fail()` 无诊断，B2-B-15）。这与「启动/网络恢复自动补交」的承诺（`:204-207` 注释、drafts 页说明）相反。
4. `idleTicks >= 3` 后 `timer.cancel()`：网络恢复后再产生的新 pending **不会再被自动重放**（周期定时器已停），只能等下次启动或用户手动触发（范围内未见手动入口）。

**用户可见后果**：**数据丢失 / 静默失败**。用户以为「网络失败 → 队列保留 → 自动补交」，实际 2.5 分钟内记录被 abandon 且无通知；危险操作永久挂在待同步；网络恢复后新失败不再自动补交；存在重复 commit 风险。

**违反原则**：41（只重试幂等方法；PUT 非幂等）、26（写操作要么幂等要么防重）、21（降级路径必须有触发条件、有观测、有退出条件）、13（可恢复事务）、15、12（危险操作需显式确认 —— 重放绕过确认语义）、17。

**代码证据**：
```dart
// domain_bridge.dart:209-215
Timer.periodic(const Duration(seconds: 30), (Timer timer) {
  if (idleTicks >= 3) { timer.cancel(); return; }
  unawaited(base.disk.cache.replayPending().then(...));   // confirmed 缺省 false
});
// disk_cache.dart:454-457 —— 保持 pending，但无「谁来点头」
} else if (outcome.conflict == WriteConflict.needsConfirmation) {
  // D7 未确认：**必须保持 pending**。
// disk_journal.dart:227-229
if (attempts >= maxAttempts) { await abandon(id, '重试 $attempts 次仍未成功：$error'); return; }
```

---

## B2-B-20 · P2 · 确证 —— SHA-256 索引凭据与 TTL 的三处边界：`contentHash` 可为空串、`_loadLocal` 用 `content.length`（UTF-16 而非字节）、`fetchedAt` 无分区/时钟回拨保护

**文件:行号**：`lib/kernel/contract/disk_types.dart:366-395`（`CacheEntry.contentHash` 默认 `''`、`toJson` 的 `len`）、`lib/base/disk/disk_cache.dart:857-866`（`_entryOf`）、`:951-1002`（`_loadLocal`）、`:876-885`（`_isExpired`）、`:391-428`（`prune`）；`lib/domain/gh/gh_api.dart:556-577`（缓存命中时 `size: utf8.encode(entry.content).length`）

**问题**：
1. **`contentHash` 默认空串且 `_loadLocal` 不拒绝**：`CacheEntry` 构造函数 `this.contentHash = ''`；`_loadLocal` 直接 `final expectedHash = decoded['hash'] as String;` 并比对 `sha256(content) != expectedHash`。若外部构造/旧 schema 写入 `hash: ''`，比对必然不等 ⇒ 丢弃（安全）。但反过来：**`_saveLocal` 不校验 `entry.contentHash` 是否为空就落盘**，任何调用方手工构造 `CacheEntry(contentHash: '')` 都会写入一个「永远读不出来」的索引，且 `_loadLocal` 的 `catch`/失败分支不区分「hash 缺失」与「内容损坏」（B2-B-11）。
2. **长度凭据用 `content.length`（UTF-16 code unit）而非 UTF-8 字节数**：`toJson()['len'] = content.length`，`_loadLocal` 用 `content.length != expectedLength`。同一份内容在 Dart String 里长度是 code unit 数，`utf8.encode` 才是字节数。`gh_api.dart:564-566` 的注释明确说「字节数而非 UTF-16 code unit 数」并**只在展示 size 时**修正了 —— 说明项目已知这个差异，但**完整性凭据仍用 code unit**。后果：含 CJK/emoji 的内容若被替换成等 code-unit 数但不同字节的内容，长度校验放行（hash 仍会拦，故不构成绕过）；但 `hash` 与 `len` 两道凭据本应独立，现在 `len` 与真正的磁盘字节数无关，违反 `disk_types.dart:379-380`「`hash` 与 `len` 是完整性校验的两道凭据，缺一不可」的设计意图。
3. **TTL 用本地墙钟 `DateTime.now()`**：`fetchedAt: DateTime.now()`（`:862`）、`_isExpired` 与 `prune` 都用 `DateTime.now().difference(...)`。设备时钟回拨会让条目「永不过期」；时钟向前跳会让**刚写回的热数据立刻被判过期并淘汰**（B2-B-12 的 `_evictIfStale` 用 `fetchedAt` 比较，同样受时钟影响）。没有单调时钟 / `fetchedAt` 合理性夹紧。
4. `defaultMaxAge = 30 days`（`:138`），但 `_readLocked` 的 `maxAge` 参数可为任意 `Duration`；`GhApi.content()` 传 `_contentMaxAge = 30s`、`listDirectory` 传 `_dirMaxAge = 1min`（`gh_api.dart:48-52`）—— 这些**调用方 TTL 只用于 `_isExpired` 判断，不参与 `prune`**（`prune` 用 `defaultMaxAge`），两套 TTL 语义不一致，诊断里也不记录实际使用的 TTL。

**用户可见后果**：**静默损坏 / 数据陈旧**。时钟跳变时用户读到过期内容并以其为写作基线（覆盖他人提交）；完整性日志里的 `expectedLen/actualLen`（`:983-985`）对含中文的文件显示的是 code unit 数，排查者会误判「长度一致」；`hash` 为空的索引造成无声读失败。

**违反原则**：20（外部数据夹紧回默认值并记录）、28（键/凭据覆盖产生差异的全部维度）、13、15、8。

**代码证据**：
```dart
// disk_types.dart:366-372 / 381-388
const CacheEntry({..., this.contentHash = ''});
'len': content.length, 'hash': contentHash,
// disk_cache.dart:859-864
contentHash: await _hashOf(document.content),   // sha256(utf8.encode(content))
// disk_cache.dart:974-977
final expectedLength = decoded['len'] as int;
if (content.length != expectedLength || (await _hashOf(content)) != expectedHash) {...}
// disk_cache.dart:882-884
return DateTime.now().difference(entry.fetchedAt) > limit;
```

---

