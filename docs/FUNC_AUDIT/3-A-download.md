# 功能审计 3-A · 下载子系统

> 更新时间：2026-11-23 06:53:00 · 版本 v15.0.0 · 批次 3-A（下载：resume 分片 / 重名落盘 / presign 回退 / 并发 / 后端切换 / 完成校验 / progress 生命周期）
> 只读审计，未改动任何代码。证据均 file:line 可 rg 复现；审计范围仅 5 个指定文件。
> 禁读 Flutter SDK：未读取任何 Flutter SDK / pub 缓存源码；第三方 `background_downloader` 行为只按本仓库调用面推断，标「待核实」。

## 审计范围（5 个指定文件，全量逐行读完）

| 文件 | 行数 | 覆盖 |
|---|---|---|
| lib/domain/ix/ix_download.dart | 1766 | 全文 1–1766，逐段读完 |
| lib/domain/ix/ix_download_backend_io.dart | 348 | 全文 1–348，逐段读完 |
| lib/domain/ix/ix_presign.dart | 241 | 全文 1–241，逐段读完 |
| lib/domain/ix/ix_presign_io.dart | 98 | 全文 1–98，逐段读完 |
| lib/domain/ix/ix_download_error.dart | 59 | 全文 1–59，逐段读完 |

交叉核对（只读、不算入 5 文件）：`lib/kernel/contract/download_engine.dart`、`lib/base/net/range_download.dart`、`lib/base/net/range_download_io.dart`（resume/206/seek 的落地实现）、`lib/surface/surface_bridge.dart`、`lib/surface/pages/release_detail_page.dart` 与 `action_run_page.dart`（presign 调用方）、`lib/domain/domain_bridge.dart`（后端装配）、`test/domain/ix_download_{manager,dedup}_test.dart`（现有门禁）。

## 已检查清单（逐维度，含无问题项）

- **①resume 分片**：`_runRanged`（851–1054）探测/候选降级/回合制；引擎 `OgLChunkPlan.of`（range_download.dart:62–87）覆盖不重不漏、`_fetchPart`（range_download_io.dart:212–291）206 + Content-Range 逐字节对齐 + 长度校验、`.partN` 独立文件、`finally` 清理半成品。**"暂停/失败后从头下载、不续传"是本模块明确设计**（ix_download.dart:1208–1211、986–989），未发现错位拼接；但"resume 分片"维度仍有 P1（见 3-A-03、3-A-04）。
- **②重名落盘**：`ogLSafeDownloadFileName`（259–304）、`_retrySavePaths`（539–549 / 1348–1351 / 1372）、enqueue 裁决闭合（754–797）、`resolveUniqueSavePath`（backend:105–158）`create(exclusive:true)` 原子占位 + `a (1)` 递增 + 失败闭合 → **v12.6.1/2 修的覆盖路径复测通过**；但与后端 `enqueue` 的命名裁决脱节（3-A-01、3-A-02）。
- **③presign 失败回退**：`IxPresign.resolve`（81–92）、`IxPresignProbe.resolve`（15–88）不跟随重定向 + 目标校验；调用方 `release_detail_page.dart:246–266` 与 `action_run_page.dart:387–405` 在 `presigned=false` 时 `prefixes=[]` + 认证头。**未发现 prefixes=[] 时把 PAT 拼进直连 URL 或发给代理**；`presigned=false` 分支按设计带认证头直连。残留：presign 错误文本丢弃（3-A-08）。
- **④并发连接数**：设置档位 `[1,2,4,8,16,32]`（settings.dart:172）；`_rangeConnections` / `preferredConnections` / `_runRanged` 单飞+回合制（851–1054）；引擎按 `min(connections, floor(total/1MB))` 限制片数，无独立 semaphore（见 3-A-05 待核实项）。
- **⑤后端切换**：`createDownloadBackend()` 当前只有 IO 实现（backend:17）；`IxDownloadBackend` 契约 171–239，`downloadDirProvider` 注入（515–522）；`_mapStatus`（backend:326–347）映射完整。**本仓库无平台通道下载后端**，切换的一致性问题以状态机 P1/P2 记录（3-A-03、3-A-06、3-A-07）。
- **⑥下载完成校验**：`_verifyIntegrity`（1420–1487）、`_finishTask`（1494–1574）、`_fillCompletedSize`（1726–1749）；有 digest → sha256 比对，无 digest → `verified=null` 不谎称验过。**未发现部分文件被当完成**（引擎合并长度校验 + 校验失败删文件）；风险只在"无 digest + `completedSize` 回填"（3-A-06）。
- **⑦disposed 后 progress**：`_safeNotify`（1703–1709）、`_notifyThrottled`（1710–1718）、`_maybeExportToSaf` 入口守卫（1590–1593）、`dispose()` 先立旗并取消令牌（1752–1766）。**notifyListeners 未被 disposed 后调用**；但委托对象在 await 后仍被触碰（3-A-07），且取消后事件可复活已完成快照（3-A-03）。

## 问题清单

> 严重度：P0 数据丢失/崩溃/安全；P1 功能失效/不一致；P2 打磨。

### P0（共 0 条）

本轮在 5 个指定文件内**未发现 P0**。v12.6.1/2 的 `_retrySavePaths` 防覆盖主链（异步窗口守卫 `ix_download.dart:746/786`、原子占位 `backend:126`）与 presign 令牌出设备保护均复测有效。

### P1（共 6 条）

#### 3-A-01　分片引擎写入的成品名与 UI/裁决名脱节，可覆盖用户既有文件
- **位置**：`lib/domain/ix/ix_download.dart:754-810`（`finalName`/`finalPath`/`finalSpec` 只写 `_specs` 与快照，分片分支用 `unawaited(_runRanged(...))` 后直接 return）、`lib/domain/ix/ix_download.dart:950-957`（引擎 `DownloadRequest(targetPath: snap.savePath)`）、`lib/domain/ix/ix_download_backend_io.dart:173-186`（只有 `enqueue` 才调用 `_build(spec)` 按 `spec.fileName` 落盘）。
- **症状**：并发 >1 时任务从不调用 `_backend.enqueue`，后端完全不知道裁决后的 `finalSpec`。若"改名→移除→再下载"曾用过豁免路径（`_retrySavePaths[id]`，1348–1351）或用户手动改过目录文件，分片引擎仍按 `snap.savePath` 写；而 `background_downloader` 的库任务（历史 / 同 `taskId` 的旧任务）按自己的 `filename`/`directory` 落盘。两条落盘口径不共用同一份裁决结果，存在覆盖同名用户文件的窗口（v12.6.1 修的是"UI 名与库文件名一致"，分片路径并未真正走 `finalSpec` 的落盘契约）。
- **根因**：`enqueue` 里计算的 `finalSpec` 只用于单连接分支（817–820），分片分支拿到的 `spec` 仍是入队初值 `_specs[id]` 更新后的对象，但引擎写入路径来自 `snap.savePath`，后端 `resolveUniqueSavePath` 的原子占位又只针对 `intendedPath` 一次性 claim、随即删除（backend:126–130），占位与真正写盘之间无锁。
- **修复指令**：在 `ix_download.dart:806-810` 分片分支同样用裁决后的 `finalSpec`（并把 `targetPath` 从 `finalPath` 派生，而非 `snap.savePath` 隐式带过来）；在 `ix_download_backend_io.dart` 为分片引擎提供与 `_build(spec)` 相同的路径解析（或把 `resolveUniqueSavePath` 的占位保留到引擎写完再释放），确保 UI 名、快照 savePath、引擎 targetPath、库任务 filename 四处同源。补一条"已存在 a.zip → 8 线程下载 → 校验 a.zip 未被改动"的回归测试。

#### 3-A-02　`resolveUniqueSavePath` 的独占占位被立即删除，TOCTOU 仍可覆盖
- **位置**：`lib/domain/ix/ix_download_backend_io.dart:123-158`，关键 `await File(path).create(exclusive: true); await File(path).delete();`（126–127）、循环中的 `claim(next)`（154）。
- **症状**：两个任务（尤其一个走分片、一个走库）并发入队同一路径时，A 的 claim 成功即删除占位；B 的 claim 随后也成功并拿到同名路径；A、B 各自写盘 → 后完成者覆盖先完成者。单进程内 `enqueue` 的 `await` 窗口（819–820）足够让 B 插进来。`create(exclusive:true)` 只保证"判定瞬间"不撞，不保护"判定→写盘"区间。
- **根因**：占位文件被当作一次性探针而非锁；`claim()` 返回 true 后立即 `delete()`，没有把占位权移交给下载器，也没有 per-path 内存锁或保留占位直到写入开始。
- **修复指令**：在 `IoDownloadBackend` 增加 `Map<String, Completer>` / per-path 互斥锁：`resolveUniqueSavePath` 成功后保留占位文件并把"占位→实际写入"的交接交给 `enqueue`/分片引擎（写入前才删除占位），或对同一 `normalizedPath` 的裁决+入队全程加锁。补并发双任务同名的 dedup 测试（当前 `test/domain/ix_download_dedup_test.dart` 只测串行）。

#### 3-A-03　终态事件/取消回调无回合守卫，可复活已完成/已取消快照
- **位置**：`lib/domain/ix/ix_download.dart:1642-1672`（`_onEvent` 的状态分支只在 `snap == null` 时返回；对 `completed` 走 `_finishTask`，对其他状态无条件 `copyWith`），对比 `on DownloadCanceled`（972–981）与 `catch`（1017–1022）都有 `_roundOf` 校验。
- **症状**：分片任务取消/重试后（`_runRanged` 的 `finally` 只在引擎路径清 token，1048–1050），`background_downloader` 的迟到 `failed`/`paused` 事件仍可能通过 `_onEvent` 把刚被 `_finishTask` 置为 `completed` 的任务打回 `failed`（同时残留已 written 的成品），或把 `canceled` 覆盖成 `paused`；`_finishTaskInner:1520-1523` 的幂等守卫只挡 `completed`，挡不住其他终态事件。
- **根因**：库事件通道（`_onEvent`）与分片引擎通道（`_runRanged`）共用同一份 `_snapshots`，但只有引擎回调接入 `_roundOf` 回合制；`cancel()`/`pause()` 对库任务（1238–1248）未写 `_roundOf`，旧库事件无"过期"概念。
- **修复指令**：在 `_onEvent` 的状态分支按终态单向性收敛：`completed/canceled/failed` 为吸收态，除显式 `retry/enqueue` 外不得被其他状态事件覆盖；对取消/重试的库任务同样递增 `_roundOf`，并在 `_onEvent` 中校验事件对应轮次。补"完成后迟到 failed 事件不得改状态"的测试（`test/domain/ix_download_manager_test.dart` 已有类似测试骨架）。

#### 3-A-04　pause/resume 分片从头重下，与"断点续传/偏移一致性"预期不符（行为一致性）
- **位置**：`lib/domain/ix/ix_download.dart:1208-1227`（`resume` 调 `_runRanged`，注释明确"从头发起"）、`986-989`（启动时强制 `received: 0`）、`1213` 的 `wasRanged` 判据；引擎侧 `lib/base/net/range_download_io.dart:127-188`（每次 fetch 都新建 `.partN`、`openWrite()` 截断）。
- **症状**：用户在 90% 处暂停→继续，进度归零、重复下载已收的 90% 流量；对大文件/移动网络是明显功能退化，且"`supportsPauseResume=true`（backend:58）"对外承诺的是"暂停/继续"而非"重下"。用户感知为"续传失效"。
- **根因**：分片引擎无断点状态持久化（不读取已有 `.partN` 的长度决定续传偏移），`resume` 又刻意绕开库任务的真实 `resume()`（`_backend.resume()` 只在非分片分支调用，1229–1230）。
- **修复指令**：在 `DownloadEngine` 契约增加"从已有 `.partN` 续传"能力（`fetch` 前读 `part.length()`，若与计划区间已写长度匹配则从 `bytes=start+len` 续请求，Range 起点与文件 seek 对齐）；或在 `resume` 中对已接近完成的分片任务改为库任务续传（保证同 taskId/路径），并如实更新 UI 文案。若产品上明确不支持续传，应把 `supportsPauseResume` 对分片任务返回 false、隐藏"继续"按钮，避免承诺与行为不一致。

#### 3-A-05　每个任务每轮 probe 串行 N 个候选地址，32 连接下无全局 semaphore（待核实/资源风险）
- **位置**：`lib/domain/ix/ix_download.dart:878-916`（`for (final candidate in candidates) await engine.probe(...)`，每次探测 15s 超时，range_download_io.dart:36–37），`engine.fetch` 在 `range_download_io.dart:111-188` 直接 `Future.wait` 起 `plan.length` 个 `_fetchPart`，无并发闸门；`connections` 仅由 `OgLChunkPlan.of` 的片数上限约束（range_download.dart:66–84）。
- **症状**：多任务同时用 32 连接 → 同时打开 32×任务数 个 socket，无全局上限；任一候选超时串行叠加 15s ×候选数，入队后长时间停在 queued/running 却无可见反馈。
- **根因**：分片引擎只做"每任务片数上限"，没有跨任务/全局的 semaphore；本层也未限制候选探测的并发或总超时。
- **修复指令**：在 `IxDownloadManager` 或 `DownloadEngine` 注入全局 semaphore（上限可配置，如 64），`fetch` 每片 acquire/release；候选探测改为并发竞速 + 总超时（如 15s 整体而非每候选 15s）。**待核实**：第三方 `background_downloader` 内部是否有自己的并发上限（本审计禁读其源码），需交主会话/CI 核实后再决定是否重复限流。

#### 3-A-06　无 digest 时跳过 `completedSize` 比对，"部分文件"可被判完成
- **位置**：`lib/domain/ix/ix_download.dart:1424-1434`（`expected == null` 直接 `return true`，`!canReadLocalFile` 也 `return true`）、`1519-1570`（`_verifyIntegrity` 返回 true 即 `_applyStatus(completed)`）、`1726-1749`（`_fillCompletedSize` 只在完成后回填 received/total，不参与判定）；引擎侧长度校验只在分片路径（`range_download_io.dart:196-206`）。
- **症状**：资源无 `digest`（私有仓库/旧资产常见）时，若走的是库单连接下载且库在连接中断后以短长度回调 `complete`，本层不做 `completedSize` 与 `Content-Length`/`probe.total` 的比对，直接判 completed；`_fillCompletedSize` 之后把 total 也改写成实际（偏小的）长度，UI 显示"100% 完成"但文件是截断的。分片路径有合并长度校验，单连接路径无同等兜底。
- **根因**：完整性校验语义只覆盖 sha256，缺失摘要时没有退化的 size 校验；`completedSize` 被设计成"完成后回填展示"，未作为校验信号。
- **修复指令**：在 `_verifyIntegrity` 无 digest 分支增加"落盘长度 ≥ 期望 total"的兜底（`_backend.completedSize(id, path: snap.savePath)` 对比 `_snapshots[id].total` / spec 中保存的 `Content-Length`），不符则走 403 失败+删除路径；`_fillCompletedSize` 若发现 `size < knownTotal` 应回写 failed 而非把 total 悄悄改小。补单连接截断文件的测试。

### P2（共 2 条）

#### 3-A-07　`dispose()` 后仍可 await 并触碰注入对象/写快照（生命周期收口不完整）
- **位置**：`lib/domain/ix/ix_download.dart:1590-1593`（`_maybeExportToSaf` 只在入口查 `_disposed`，随后 `await exporter.export` 1655–1668）、`1420-1487`（`_verifyIntegrity` 的 `await fileSha256` 后仅检查 `fresh == null || _disposed` 才写回，但 `await` 期间仍调用了后端）、`1726-1749`（`_fillCompletedSize` 的 `await completedSize` 后无 `_disposed` 检查，1463 附近只在 verify 里有）、`onProgress`（964–965 → `_applyRangeProgress` 1130–1176 全程无 `_disposed` 检查）。
- **症状**：管理器 dispose 后（可能伴随对象释放）仍会调用后端 `fileSha256`/`completedSize` 与 `StorageExporter.export`；虽然 `_safeNotify` 拦住了 `notifyListeners`（1703–1709，未发现 disposed 后 notify 崩溃），但注入对象可能已被释放，产生"回收后仍执行导出/校验"的资源与一致性问题。
- **根因**：`_disposed` 只用于通知门与部分 await 守卫，未统一到所有 async 尾部与引擎回调入口。
- **修复指令**：`_applyRangeProgress`、`_fillCompletedSize`、`_verifyIntegrity`、`_maybeExportToSaf` 均在开头与每个 await 之后检查 `_disposed` 并 return；`dispose()` 里同时取消 `_finishTask`/`_maybeExportToSaf` 的在途 future（用 `Set<Future>` 或 token），保证回收后不再触碰注入对象。

#### 3-A-08　presign 失败原因被吞：错误文本未向下游传递，fallback 分支只留日志
- **位置**：`lib/domain/ix/ix_presign_io.dart:80-83`（`on Object catch (error) => IxPresignResult(url:null, error:'$error')`，但 `IxPresignResult.error` 在调用链中从未被展示）、`lib/surface/surface_bridge.dart:315-326`（`resolveDownloadUrl` 返回 `result.url ?? url`，丢弃 `result.error`）、`lib/surface/pages/release_detail_page.dart:246-266`、`action_run_page.dart:387-405`（`presigned=false` 时仅 `prefixes=[]`，无用户可见提示）。
- **症状**：网络故障 / `location` 被安全校验拒绝（ix_presign_io.dart:49–56）导致预签名失败时，用户只看到"下载变慢"，无法知道"加速为何不可用/签名为何失败"，与代码注释"不静默"的承诺不符（surface_bridge.dart:312–313）。**令牌未泄漏**：`prefixes=[]` + 认证头只走直连（已核对 `ogLGuardTokenExitDownload` 与 `download_proxy.dart:76-113`）。
- **根因**：`IxPresignResult.error` 是纯诊断字段，调用方没有把它接入通知/诊断中心；`presigned=false` 也无法区分"公开直链"与"解析失败回退"。
- **修复指令**：`resolveDownloadUrl` 在 `result.error != null` 时用 `KernelDiagnostics`/通知中心投递一条 warning（带 taskUrl 与 error）；`IxPresignResult` 增 `failed` 语义布尔（区分"200 直链"与"失败回退"），调用方据此决定是否显示"加速不可用"提示。注意不要因此把认证头交给代理。

## 待核实（交主会话/CI 裁决，非本席结论）
- `background_downloader` 的 `FileDownloader` 并发/队列上限、同 `taskId` 重入队状态机、`DownloadTask.filePath()` 与 `BaseDirectory.root` 下 `directory` 的绝对路径语义：本审计禁读其源码，仅按本仓库调用面（`backend_io.dart:66-99/173-186/300-316`）推断。
- Web 平台实现：仓库中无 `createDownloadBackend()` 的 web 条件导入版本，文档声称 Web 无后端；`IxPresign.resolve` 文档称 Web 上返回原地址，但 `ix_presign.dart` 无条件 `import 'ix_presign_io.dart'`（`dart:io`）——Web 编译/运行行为需 CI 核实。

## 本席结论
3-A 下载子系统在主防覆盖链（v12.6.1/2 `_retrySavePaths`）、presign 令牌出设备保护、sha256 完整性校验与 `dispose` 后不 notify 四处**复测通过**，未发现 P0。剩余 **6 条 P1 + 2 条 P2**：其中 **3-A-01/3-A-02（分片与库落盘双口径 + 占位即删的 TOCTOU）** 与 **3-A-03（终态事件无回合守卫）** 是最值得优先修的三条；**3-A-04（resume 从头重下）** 属于"设计如此但与对外承诺不符"，需产品定夺。**检查文件 5 个（共 2512 行），全部逐行覆盖；另交叉核对 10 个 lib/test 文件（不计入 5 个）。** 本轮只读，未改代码、未 commit/push。
