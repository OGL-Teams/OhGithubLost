# 第4批 · 视角A：下载管理链路实现正确性审计（B4-A）

> 审计对象：OhGithubLost v12.0.0 LTS 下载链路（ix_download* / presign / range_download / download_manager_page / surface_bridge 装配段）。
> 只审不改。逐文件完整阅读，非 rg 摘要。裁决依据：docs/QUALITY_STANDARD.md、AGENTS.md、docs/CONSISTENCY.md（均已完整读）。
> 每条含：编号 / 文件:行号 / 问题 / 用户可见后果 / 级别 / 原则编号 / 确证情况与代码证据。

---

## 发现

### B4-A-01 · Web 平台整条下载链路不可编译 / 不可用（无 Web 后端）
- **位置**：lib/domain/ix/ix_download.dart:23（`import 'ix_download_backend_io.dart';` 无条件导入）；`createDownloadBackend()` 仅存在于 ix_download_backend_io.dart:17（`import 'dart:io'`）。
- **问题**：全仓库不存在 `ix_download_backend_web.dart` 或任何条件导入分支（`grep "if (dart.library"` 仅命中 gh_oauth 与 ix_action_logs_save 两处，均非下载）。而 ix_download.dart 契约注释（~200–260 行）通篇描述 Web 后端行为（`canReadLocalFile=false`、`supportsRanged=false`、"Web 上返回下载地址本身"），download_manager_page.dart:358 也按 Web 语义写分支——这些代码路径没有任何实现可到达。
- **后果**：Web 构建编译失败（dart:io 不可用），或（若 CI 只跑移动/桌面）AGENTS.md 宣称支持的四平台之一完全没有下载能力；文档与实现互相撒谎。
- **级别**：P1（若 Web 仍在发布矩阵内则 P0）
- **原则**：4（平台差异唯一裁决处）、42（失败如实，不伪造能力声明）、57（文档引用符号必须真实存在）
- **确证**：是。证据如上；`ls lib/domain/ix/` 无 *_web.dart。

### B4-A-02 · 私有仓库归档（ZIP）下载经加速通道时绕过 TOKEN-EXIT-01 弹窗门禁
- **位置**：lib/surface/pages/repo_page.dart:270–300（`_downloadZip`，enqueue 在 :286）
- **问题**：`_repo.isPrivate` 时构造 `authorization: Bearer …` 头（:282–283），若用户开启 `repoArchive` 加速并知情接受私有 raw 族，`ogLAccelCandidates` 返回 `前缀 + github.com/…zip`（第三方主机）。该函数**没有调用 `ogLGuardTokenExitDownload`**，enqueue 直接把令牌发给代理。对比：repo_page.dart:1858、file_preview_page.dart:586、release_detail_page.dart:265、action_run_page.dart:404 四个入口全部有门禁。
- **后果**：用户令牌在无任何"不可关闭警告"的情况下被发送到非 GitHub 主机——恰恰是 TOKEN-EXIT-01 机制存在的目的（原则 12：危险操作必须用户显式确认）。
- **级别**：P0
- **原则**：12（类型化确认）、40（令牌只在必要跳使用）
- **确证**：是。代码证据如上；repo_page.dart:286 enqueue 前仅有 try，无 guard。

### B4-A-03 · `_applyRangeProgress` 不做回合校验，旧轮进度可覆盖新轮状态
- **位置**：lib/domain/ix/ix_download.dart:1002–1028（对照 :732–735 的回合设计意图）
- **问题**：`_runRanged` 的成功/取消/Unsupported/失败四条分支都有 `if (_roundOf[id] != myRound) return;`（:853, :863, :876, :884），但 `onProgress` 回调（:845 → `_applyRangeProgress`）**没有**回合校验，也不检查 token 是否已被 cancel。旧一轮 fetch 在被 cancel 后到协程真正退出之间的迟到 onProgress 仍会执行 `_snapshots[id] = snap.copyWith(status: running, …)`（:1020），把新一轮刚写入的 paused / canceled / queued 打回 running。
- **后果**：用户点暂停/取消后进度条"复活"继续走，界面状态与实际相反（A-4 注释里库路径已修的同一类 bug，分片路径仍在）。
- **级别**：P1
- **原则**：22（过期回调必须丢弃）、26
- **确证**：是。逐行阅读 :845 与 :1002–1028，无任何 round/token 检查。

### B4-A-04 · `resume` 对仍在运行的分片任务会先写 running 再重入 `_runRanged`，配合 B4-A-03 造成状态跳变
- **位置**：lib/domain/ix/ix_download.dart:1064–1076（resume）
- **问题**：resume 无条件 `_applyStatus(id, running)` 后 `await _runRanged(...)`；`_runRanged` 内部（:812–820）检查 `beforeRun.status` 时看到的是刚被 resume 自己写成的 running，于是"探测期间状态已变更"的 A-1 守卫对"对 running 任务误点 resume"完全失效（守卫只能拦 paused/failed 等终态写法，拦不住 resume 自己造成的假 running）。真正的单飞保护只剩"取消旧 token + 回合 +1"，但结合 B4-A-03，旧轮进度回调仍能写状态。
- **后果**：双击"继续"会并发两个引擎 fetch 指向同一 targetPath 的竞态窗口（旧 token cancel 到旧协程检查 isCancelled 之间），界面出现来回跳的进度。
- **级别**：P2（有回合+取消令牌兜底，需 B4-A-03 才放大）
- **原则**：22、23（闸门成对且同属一处）
- **确证**：是（静态阅读）；并发窗口实际影响**待议**（需运行时实测协程退出时序）。

### B4-A-05 · `retry` 在任务已移除（`_specs[id] == null`）时静默返回，页面"撤销移除"失效无任何留痕
- **位置**：lib/domain/ix/ix_download.dart:1104–1108（`if (spec == null) { return; }`）；lib/surface/pages/download_manager_page.dart:271–279（`_undoRemove` 调 `retryDownload`）
- **问题**：`remove()`（:1139）清掉 `_specs`，此后 `retry` 直接静默 return，无日志、无诊断码、无通知。而下载管理页的"撤销移除"（undo bar，:168–176 → :271）正是靠 `retryDownload` 恢复——undo 条在页面上还挂着，点击却毫无反应。
- **后果**：用户误删任务后点"撤销"，界面无任何反馈，撤销功能形同虚设（静默降级，原则 15/16 直指）。
- **级别**：P1
- **原则**：15（静默降级最严重）、16（不吞异常/不吞路径）、38
- **确证**：是。download_manager_page.dart 的 `_undoRemove` 不清 `_lastRemoved`、不提示失败；ix_download.dart:1106 无任何留痕。

### B4-A-06 · `IxDownloadCategory.label` / `IxDownloadStatus.label` 硬编码中文进 domain 层
- **位置**：lib/domain/ix/ix_download.dart:57–71（label getter，含"仓库文件""构建产物""排队中"等）
- **问题**：domain 层存在面向用户的界面文案。download_manager_page.dart:386–396 注释明确说"不能直接显示在界面上"，改走 i18n——但这两个 getter 仍是公开 API，任何新调用点都会踩中；与文件头"页面不碰实现、只读快照"的契约相比，label 属于诱导误用的死重。
- **后果**：非中文用户界面可能被渲染成中文（若未来调用点漏用 `_categoryLabel`）；门禁（i18n_scan 只扫 surface）抓不到。
- **级别**：P2
- **原则**：35（文案零硬编码）、36
- **确证**：是。

### B4-A-07 · probe 对"HEAD 失败且 Range 复核也失败"返回 `supportsRange:false` 而不是失败——不可达地址与"不支持分片"混为一谈
- **位置**：lib/base/net/range_download_io.dart:67–76（catch 内兜底 `return const DownloadProbe(supportsRange: false);`）
- **问题**：DNS 失败 / 断网时 probe 返回"正常但不支持 Range"，`_runRanged`（ix_download.dart:797–804）据此**回退单连接**去 `_backend.enqueue(spec)`——用同一条不可达地址再撞一次墙。虽然日志里留了 WARN（符合 B1-A-15 的部分要求），但对用户而言：分片失败被折算成"已回退排队中"的乐观状态，随后单连接同样失败才显示 failed。二次失败窗口内任务显示 queued（假象）。
- **后果**：断网时用户先看到"多线程→排队中"，过几秒才失败；失败信息比真实故障晚一拍且多绕一跳。
- **级别**：P2
- **原则**：42（失败如实报错）、15
- **确证**：是（静态）；端点实测（服务端 404/403 与网络错误是否可区分）**待议**。

### B4-A-08 · `ogs://` 之外：`_fetchPart` 的 200/206 判定不含重定向——加速代理 3xx 时分片全部失败而非回退
- **位置**：lib/base/net/range_download_io.dart:221–232（`if (response.statusCode != HttpStatus.partialContent)` 一步到位抛 `DownloadHttpException`）
- **问题**：dart:io HttpClient 默认跟随重定向，但若加速通道回 302 且 Dart 未跟随（或代理把 206 降为 200），抛出的 `DownloadHttpException(statusCode: 302/200)` 中 200 分支会被 ix_download.dart:886–891 识别为"服务端忽略 Range"回退单连接，302/3xx 则直接进失败分支（:893+）——分片失败后**候选地址不轮换**（`_urlCandidates` 探测阶段已锁死 uri），失败信息是"分片 0-1048575 返回 302"这类对用户不可读的文本。
- **后果**：用户看到技术性错误串；而同一地址单连接路径（background_downloader 自带跟随重定向）本可成功。
- **级别**：P2
- **原则**：38（错误信息面向用户）、17（类型表达失败——类型有了，但路由不全）
- **确证**：是（静态阅读）；代理实际回包行为**待议**。

### B4-A-09 · 完整性校验失败路径：`deleteFile` 抛错会把"校验不匹配"误升级为 unknown 失败，且 `verified` 未落 false
- **位置**：lib/domain/ix/ix_download.dart:1284–1311（`_finishTaskInner` 的 `!ok` 分支）
- **问题**：`await _backend.deleteFile(id, path: snap.savePath)`（:1292）位于置 failed **之前**；IoDownloadBackend.deleteFile 虽然自身吞了 IO 错（backend_io.dart:236–238），但契约允许实现抛出（FakeDownloadBackend 也不保证）。一旦抛出，进入 `_finishTask` 的顶层兜底（:1243–1260），置为 `IxDownloadErrorKind.unknown`——把已确诊的 integrity 失败降级成"未知"，且 `verified` 字段保持 null（"未校验"），诊断信息反而变差。
- **后果**：坏文件场景下用户看到的是笼统"下载失败"而非"完整性校验未通过"；事件码从 OGL-DL-403 变成 OGL-DL-407，排查方向被带偏。
- **级别**：P2
- **原则**：16、18（catch 精确性：顶层兜底吞掉更精确的语义）
- **确证**：是（静态，控制流明确）。

### B4-A-10 · `_verifyIntegrity` 无摘要 / 无法读回时返回 `true`，调用方把"未校验"当"通过"
- **位置**：lib/domain/ix/ix_download.dart:1201–1236（两处 `return true`：:1210 无摘要、:1225 Web/无法读回）
- **问题**：注释与 `IxDownloadTask.verified` 三态设计（:445–455）都说"null = 未校验，不谎称验过"，方向正确；但 `_finishTaskInner`（:1272）拿到 `true` 后径直 `_applyStatus(completed)`——`verified` 仍是 null。这本身自洽，可接受；**真正的缺口**是 :1227 的 `actual == null → return false` 分支：读不到文件（如外部删除）会被当成"校验不匹配"处理，错误文案却是 integrity「integrityMismatch」——文件不存在和内容被替换是两种故障，混为一谈。
- **后果**：成品被杀毒软件/用户先行移走时，界面报"完整性校验未通过，坏文件已删除"——与事实不符（文件本来就不在）。
- **级别**：P2
- **原则**：42（失败如实）、52（端点/状态语义细分）
- **确证**：是。

### B4-A-11 · download_manager_page 用 `print` 做日志（2 处），违反项目 lint（avoid_print 升级纪律）
- **位置**：lib/surface/pages/download_manager_page.dart:252、:521（均带 `// ignore: avoid_print`）
- **问题**：AGENTS.md §3 明确 `avoid_print` 在追加 lint 清单；工程已有 OgLAppLog / KernelDiagnostics 两套留痕通道，这里用 `// ignore` 绕过。
- **后果**：批量重试失败、打开文件失败的留痕进的是 stdout，用户与「关于页」日志环都看不到——留痕通道断裂。
- **级别**：P2
- **原则**：15、16
- **确证**：是。

### B4-A-12 · Gist 下载入口无 TOKEN-EXIT-01 门禁（当前无令牌，属"隐性契约"缺口）
- **位置**：lib/surface/pages/gist_detail_page.dart:293–318（`_downloadFile` 直接 enqueue）
- **问题**：gist raw 当前匿名可取、headers 恒空，`ogLGuardTokenExitDownload` 对空 authorization 本就放行，所以**今天无实害**。但同文件的注释自己写明"无令牌参与"依赖的是 Gist raw 匿名这一外部事实——若 GitHub 收紧或未来给 gist 加私有语义，这里没有门禁兜底，将成为第五个无闸入口（参照 B4-A-02 的模式）。
- **后果**：暂无；属防线"靠外部事实而非代码保证"。
- **级别**：P2（记录性）
- **原则**：11（防线没有开关——此处防线缺失而非开关）、27（并发/前提假设写进注释——已写，记 P2）
- **确证**：是（静态）；GitHub 端点行为**待议**。

### B4-A-13 · `_runRanged` 失败分支中 `notifications?.push` 与快照写入均不做 disposed 检查之外的快照覆盖竞态
- **位置**：lib/domain/ix/ix_download.dart:895–915
- **问题**：失败分支 `final IxDownloadTask? current = _snapshots[id]; _snapshots[id] = current.copyWith(status: failed, …)` 之间无 await，原子性 OK；但该分支未校验 `current.status` 是否已是 terminal（如用户在错误发生与回调之间点了"重新入队"重建了新 queued 快照——新实例场景由回合制保护，**但同实例下** enqueue→remove→enqueue 的重建是替换实例，回合制可拦）。复核后判定：回合制覆盖到位，唯 B4-A-03 的进度回调例外。
- **结论**：不构成独立缺陷，**撤销**；本条仅留档说明该分支已逐一核对（成功/取消/Unsupported/失败/finally 五路回合校验齐全，仅进度回调漏网，即 B4-A-03）。

### B4-A-14 · `presign.resolve` 第一跳 200 时不 drain 的资源说明成立，但 3xx Location 为**同主机相对路径**时被 `safeRedirectTarget` 放行而携带的 Authorization 不会自动重放——逻辑正确，记录佐证
- **位置**：lib/domain/ix/ix_presign_io.dart:30–46、ix_presign.dart:127–141
- **结论**：核验通过：followRedirects=false、maxRedirects=0、令牌只发第一跳、目标经 SSRF 校验（回环/私网/169.254/整数 IPv4/IPv4-mapped IPv6 均覆盖，ix_presign.dart:150–215），与 ix_download_test.dart:118–156 的测试一致。**无缺陷**，留档。

### B4-A-15 · Content-Range 强制校验链完整，但 `probe` 的 `_probeByRange` 未做同样严格的区间校验
- **位置**：lib/base/net/range_download_io.dart:84–113（`_probeByRange` 只验状态码 206 与 total 提取，不验 `bytes 0-0` 是否真的回的是 0-0）
- **问题**：分片路径 `_fetchPart`（:233–258）对 Content-Range 做了"必须存在、逐字节对齐、总量一致"三重校验（B1-A-16/B1-B-02 修复到位），但探测路径只要 206 就采信 `total`。恶意/错配代理可在 probe 时回"0-1/总长=巨大值"骗过分片启动，再在真正分片时被逐片拒绝——结果仍是失败，只是用户先看到假进度条（total 被写成探测值，:826–830）。
- **后果**：错位代理场景下先展示错误的大分母进度，随后整批分片失败。
- **级别**：P2
- **原则**：42、44（对外部目标保持怀疑）
- **确证**：是（静态）；实机行为**待议**。

### B4-A-16 · `background_downloader` 后端 `pause` 对**分片探测期间**的任务传错对象语义（`_tasks[id]` 为 null 时静默无操作）
- **位置**：lib/domain/ix/ix_download_backend_io.dart:118–124（pause/resume/cancel：`task == null` 时直接跳过）
- **问题**：`enqueue` 先 `_tasks[spec.id] = task` 再 `await _downloader.enqueue(task)`（:100–103）；但 `_runRanged` 回退单连接路径（`_fallbackToSingle` :942–985）调用 `_backend.enqueue(fallback)` 会**覆盖** `_tasks[id]`——若旧库任务仍在重试窗口（waitingToRetry 映射 queued，backend_io.dart:268–270），旧 DownloadTask 对象被替换，库队列里那个旧任务从此失去句柄：pause/cancel 都作用于新对象，旧任务成为孤儿继续跑，可能与新任务写同一文件。
- **后果**：罕见但真实的双下载竞态（分片回退 × 库自动重试叠加时），界面只显示一条任务，磁盘出现两个写入者。
- **级别**：P1
- **原则**：23（互斥闸门成对且同属一处）、25、22
- **确证**：是（静态推演确定：enqueue 无条件覆盖 `_tasks[id]`，无旧任务清理——`_downloader.cancelTaskWithId` 只清库内终态记录，不等待运行中任务退出）。实际触发需库任务处于重试窗口，运行时概率**待议**。

### B4-A-17 · `clearFinished` 不取消"已取消/失败"任务在库内可能残留的终态记录，与 remove 的清理口径不同
- **位置**：lib/domain/ix/ix_download.dart:1145–1183（clearFinished 逐表对齐了辅助表但未调 `_backend.cancel`）
- **问题**：remove()（:1135–1147）会 `await _backend.cancel(id)` 清库记录；clearFinished 只清内存表。对终态任务这是**设计上说得通**的（io 后端 enqueue 前已先 cancelTaskWithId 重置，:93–100）。复核后**不构成缺陷**，留档说明已核对（后端入口自清）。

---

## 覆盖文件清单

| 文件 | 状态 |
|---|---|
| lib/domain/ix/ix_download.dart | 完整读（1533 行分 4 段） |
| lib/domain/ix/ix_download_backend_io.dart | 完整读（279 行） |
| lib/domain/ix/ix_download_error.dart | 完整读（59 行） |
| lib/domain/ix/ix_presign.dart | 完整读（241 行） |
| lib/domain/ix/ix_presign_io.dart | 完整读（98 行） |
| lib/domain/ix/ix_session.dart | 完整读（355 行）——与下载链路无耦合，未发现问题 |
| lib/domain/ix/ix_task.dart | 完整读（445 行）——确认门禁类型化（IxConfirmationRequired）实现正确 |
| lib/domain/ix/ix_conflict.dart | 完整读（271 行）——与下载链路无直接耦合 |
| lib/domain/ix/ix_action_logs.dart | 完整读（162 行）——日志下载不走加速（与 download_proxy 声明一致） |
| lib/base/net/range_download.dart | 完整读（97 行） |
| lib/base/net/range_download_io.dart | 完整读（345 行） |
| lib/surface/pages/download_manager_page.dart | 完整读（537 行） |
| lib/surface/surface_bridge.dart | 完整读 download 装配段（280–479 行） |
| lib/surface/util/download_proxy.dart | 完整读（118 行） |
| lib/surface/app/token_exit_warning.dart | 完整读（170 行） |
| lib/surface/pages/{release_detail,repo,action_run,file_preview,gist_detail}_page.dart 下载入口段 | 分段精读（B4-A-02/12 取证） |
| lib/kernel/contract/download_engine.dart | 完整读（149 行） |
| test/base/range_download_test.dart | 完整读（122 行） |
| test/domain/ix_download_test.dart | 完整读（199 行） |
| test/domain/ix_download_manager_test.dart | 完整读（376 行） |
| docs/QUALITY_STANDARD.md / AGENTS.md / docs/CONSISTENCY.md | 完整读 |

（ix_download_backend_web 不存在——本身即 B4-A-01。）

## 整体评价

链路的**主干设计成熟度高于多数同类项目**：回合制守卫、双入口完成收口幂等（`_finishTask`）、`pathFor` 异步窗口的"实例同一性"判据、分片失败清理（等所有分片结束再删 + 合并失败清 target + Content-Range 三重校验）、presign 的 SSRF 防护（含整数 IPv4 与 IPv4-mapped 写法归一化）都属认真修复过的痕迹，且测试把纯函数边界钉得较死。

但存在一条贯穿性裂缝：**防线在"写代码的人想到的分支"上密不透风，在"没被当成下载入口的入口"上为零**——B4-A-02（私有归档加速绕过 TOKEN-EXIT-01）是本批唯一 P0，也是四入口有门禁、第五入口没有的典型；B4-A-01（Web 后端整体缺席但文档/页面按 Web 语义写了大量分支）说明"平台差异唯一裁决处"的原则（原则 4）在下载链路实际是口头的。回合制守卫覆盖了终态写入却漏了高频的进度回调（B4-A-03），说明 A-2 的纪律是"打补丁时逐分支加的"，不是结构性的（进度回调应统一携带 round 或在入口统一判定）。

建议优先级：B4-A-02（P0，令牌安全）→ B4-A-16/B4-A-03/B4-A-05（P1，正确性与静默失败）→ 其余 P2。
