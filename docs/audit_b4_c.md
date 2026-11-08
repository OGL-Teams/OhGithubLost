# 第 4 批 · 视角 C（契约与规范一致性）· 下载管理链路审计

- 目标：`/root/OhGithubLost`（v12.0.0 LTS 工作区）
- 范围：`lib/domain/ix/` 全部 13 文件 + `lib/base/net/range_download*.dart`（2 文件）+
  `lib/kernel/contract/download_engine.dart` + `lib/surface/pages/download_manager_page.dart` +
  `lib/surface/app/token_exit_warning.dart` + `test/` 下载相关全部测试（4 文件）+
  `tool/contract_audit.py`（并运行核验）+ `docs/NETWORK.md` / `ARCHITECTURE.md` /
  `AGENTS.md` / `QUALITY_STANDARD.md` / `CONSISTENCY.md`
- 裁决依据：`docs/QUALITY_STANDARD.md`（59 条原则，下称「原则 N」）· `AGENTS.md` · 文档原话
- 纪律：只审不改，未修改任何 `lib/` 文件；范围文件全部完整读取；`rg` 仅用于核实行号与符号存在性
- 记录方式：发现一条即刻追加；不冒充确证——凡未实际执行（如 web 构建）的推断均标明推断边界

---

## B4-C-01 · 「无降级、无兜底」文档承诺与代码内「静默降级」注释同库并存

- **文件:行号**：`docs/NETWORK.md:85-88`（§3.3 无降级、无兜底：`ogLAccelCandidates` 现**至多返回一项**……失败如实报错）；
  `lib/domain/ix/ix_download.dart:122`（`copyWith` 注释「分片探测失败后**静默降级**到其它候选地址时使用」）、
  `:541` / `:671-676`（`_urlCandidates`「其余用于**静默降级**」）、`:757`（探测循环「命中第一个……（**静默降级**）」）
- **问题**：`docs/NETWORK.md` 明文宣告加速链路「无降级、无兜底」，而下载管理器内部为
  `fallbackUrls` 保留了一整条多候选静默降级机制，注释三处自称「静默降级」，与
  原则 15「静默降级是最严重的缺陷」直接冲突。
- **后果**：契约文档与代码注释互相矛盾；一旦任何调用点恢复传入多候选（历史调用点曾
  `skip(1)` 传入），「是否经过通道」将重新变得不可判定，且降级对用户不可见。
- **级别**：P1
- **原则**：15、53、57
- **确证**：确证（静态）。证据：当前全部 6 个调用点（`repo_page.dart:288/1874`、
  `release_detail_page.dart:285`、`gist_detail_page.dart:310`、`file_preview_page.dart:608`、
  `action_run_page.dart:426`）均为 `candidates.skip(1)` 且 `ogLAccelCandidates` 至多返回 1 项，
  故 fallbackUrls 运行时恒为空——机制是**死路径**，与 B1-C 对 `download_proxy.dart` 的结论一致；
  但注释与文档的矛盾是文本可证的事实。另注：探测循环中候选不可用仅写 **debug 级**诊断
  （`ix_download.dart:769-775`，OGL-DL-202-D），回退单连接写 info 级（OGL-DL-201），
  用户在界面上看不到「加速未生效」，属规范允许的边缘（有留痕、不冒充成功），但与 §3.3
  「失败如实报错」的用户可见性预期存在张力。

## B4-C-02 · resume 使用已被清空的连接数快照：分片回退单连接后 resume 会走错通道

- **文件:行号**：`lib/domain/ix/ix_download.dart:1067`（`resume`：`preferredConnections ?? _rangeConnections[id] ?? 1`）、
  `:1122`（`retry`：`_rangeConnections[id]`）、`:951`（`_fallbackToSingle` 开头 `_rangeConnections.remove(id)`）
- **问题**：分片任务因 `DownloadUnsupported` 回退单连接时，`_fallbackToSingle` 立即删除
  `_rangeConnections[id]`；此后用户点「继续」，`resume` 在 `_specs.containsKey(id) && _engine != null`
  成立时（spec 仍在）**仍按分片路径重启**，`connections` 回落到 `preferredConnections ?? 1`。
- **后果**：两点分歧——①用户设置过并发时，一个已证明「服务端不支持 Range」的地址会被
  再次整轮探测+分片+再回退，多付一轮 15s 探测窗口与失败往返；②用户未设置并发时以 1 连接
  走 `_runRanged`，`fetch` 内因分片数 <2 抛 `DownloadUnsupported` 再回退，行为最终正确但
  路径绕远。属逻辑非缺陷的效率/语义瑕疵，注释（resume 的 E-1 段）声称「按当前设置生效」，
  未提这条回退交互。
- **级别**：P2
- **原则**：22、54
- **确证**：确证（静态读全部相关分支）。

## B4-C-03 · `_verifyIntegrity` 三条失败路径静默返回 false，违反「失败必须留痕」

- **文件:行号**：`lib/domain/ix/ix_download.dart:1234`（`fileSha256` 返回 null → `return false;` 无诊断）、
  `:1262-1265`（校验抛异常 → 仅 warn 一条 + `return false;`——warn 有，但任务侧无码）、
  `:1208`（快照消失 → 静默）
- **问题**：`_finishTaskInner`（:1304）把 `false` 一律折叠成 `integrityMismatch`（OGL-DL-403）
  失败并通知「坏文件已删除」——但 :1234 的 `null` 实际含义是「读不到文件」（文件可能根本
  不存在、磁盘被系统清掉），:1264 是「校验本身抛异常」（不是校验不匹配）。三種完全不同的
  故障被同一条「完整性校验未通过，坏文件已删除」通知覆盖，其中「坏文件已删除」对
  :1234 情形还是**假陈述**（deleteFile 对不存在文件是空操作）。
- **后果**：诊断码 OGL-DL-403 语义过载；用户按「可重试」理解，而真实原因（文件丢失）可能
  重试也失败；排查时事件码无法区分。通知文案与事实不符，触碰原则 42「伪造的成功响应比
  失败本身更难排查」的镜像面：伪造的**具体失败原因**。
- **级别**：P2（不丢数据、可重试，但归因失真）
- **原则**：15、16、38、42
- **确证**：确证（逐行读 `_verifyIntegrity` / `_finishTaskInner` / `IoDownloadBackend.fileSha256`
  ——后者 `catch (_) { return null; }`（`ix_download_backend_io.dart:171-176`）确实把一切读失败折叠为 null）。

## B4-C-04 · `clearFinished` 清理表清单缺 `_roundOf`，回合号表无界增长

- **文件:行号**：`lib/domain/ix/ix_download.dart:1163-1172`（`clearFinished` 的 per-id 清理循环：
  清了 tokens/connections/paused/specs/lastSample/sha/candidates/saf 共 8 张表）对照
  `remove()` `:1131-1145`（清 9 张，含 `_roundOf.remove(id)` :1135）
- **问题**：注释自述「与 remove() **逐表对齐**：per-id 的辅助表一个都不能漏」，
  实际 `_roundOf` 恰好漏了。按原则 29「所有资源有上限」，该 Map 随「清完再下」循环无界增长
  （每条目仅 int，量级小）。
- **后果**：功能无错（回合守卫是等值比较，旧回合号永不相等新回合号，见 :853/:869/:882），
  纯属与自身注释不符 + 微量泄漏；但「逐表对齐」是写进代码的契约，门禁与人读都应能据注释判错。
- **级别**：P2
- **原则**：27、29、54
- **确证**：确证（两张清理清单逐项比对）。

## B4-C-05 · `ix_download.dart` 头注释宣称「按平台选下载后端」，实际不存在条件导入与 Web 后端

- **文件:行号**：`lib/domain/ix/ix_download.dart:1`（「**按平台选下载后端**」）、
  `:9-11`（「实现收敛在 `ix_download_backend_io.dart`……`File`/`Directory` 的使用**全部**隔离在该实现里」）、
  `:23`（`import 'ix_download_backend_io.dart';` —— **无条件导入**）、
  `:167`（`IxDownloadBackend` 注释「原生 = `background_downloader`；Web = 浏览器下载」）、
  `:146-147`（`_kindOfFailure` 注释「本层**不 import `dart:io`**（Web 才可编译）」）
- **问题**：`lib/domain/ix/` 全目录检索（`rg "if \(dart.library"`）仅有
  `ix_action_logs.dart:25` 一处条件导入（save 落盘）；`ix_download_backend_io.dart`
  **没有** `_web` 配对文件，也无 `createDownloadBackend` 的条件版本。即：头注释与
  `IxDownloadBackend`/`pathFor`/`cancel` 各方法注释里反复描述的「Web = 浏览器下载后端」
  在代码中不存在；`ix_download.dart` 经 :23 → `dart:io` 的无条件导入链，在 Web 编译目标下
  不可编译，「Web 才可编译」的注释对**本文件自身**不成立。
- **后果**：①按注释理解契约的读者会以为存在双平台后端；②若真做 Web 发布
  （`tool/web_publish.py` 存在），该链路要么编译失败、要么需要补齐条件导入后注释才重新为真；
  ③契约层 `IxDownloadSpec` 注释「不含平台类型，便于 Web/原生共用」（:95-96）同样指向一个
  未落地的 Web 侧。
- **级别**：P1（注释-实现一致性主线命中；不影响当前 Android/iOS/桌面运行）
- **原则**：4、53、54、57
- **确证**：结构部分确证（无条件 import + 全库无 web 配对文件，`rg` 全查）；
  「Web 编译必失败」为基于 Dart 平台库规则的推断，本次未执行 web 构建验证，标注为推断。

## B4-C-06 · 令牌出设备门禁按小写键取头，对非小写 `Authorization` 键失明（潜在）

- **文件:行号**：`lib/surface/app/token_exit_warning.dart:91`（`headers['authorization']`）；
  唯一构造点 `lib/surface/surface_bridge.dart:339`（小写 `'authorization'`）
- **问题**：门禁以字符串精确匹配读取认证头。当前唯一构造点用小写键，恰好成立；但契约上
  `ogLGuardTokenExitDownload` 是「四个下载调用点共用」的收口函数（该文件 :80-82 用法注释），
  未来任何调用点若以 `'Authorization'`（HTTP 惯例大写）自建 headers 传入，门禁将判
  「不带令牌」直接放行——警告被静默跳过，属原则 15 意义上的静默失效。
- **后果**：安全门禁对输入键名大小写脆弱；一旦新调用点手写头部，令牌可无声越过 TOKEN-EXIT-01。
- **级别**：P2（当前无活体触发点；防御性契约缺陷）
- **原则**：12、15、40
- **确证**：确证（`rg -n "authorization" lib/surface` 仅 :339 一处构造；门禁取值逻辑逐行读）。

## B4-C-07 · 「一键重试全部失败」无论成败一律弹成功提示，失败不可见

- **文件:行号**：`lib/surface/pages/download_manager_page.dart`（`_retryAllFailed`：
  循环内单条失败仅 `print`（`ignore: avoid_print`）+ 注释「落日志由中枢层处理」；循环后无条件
  `_t('retriedCount', {n})` + `DownloadNoticeKind.success`）
- **问题**：单条 `retryDownload` 抛错时用户看不到（print 非发布可见，且中枢层 `retry`
  失败路径——如 spec 已被清——并不记诊断，`ix_download.dart:1105-1109` spec==null 直接 return）；
  结尾提示固定 success 文案「已重试 N 个」，即使 N 条全部失败。
- **后果**：违反原则 15（失败以用户可感知方式留痕）与 42（如实报错）；「重试全部」之后
  列表若仍是失败态，通知却宣称成功，用户需自行发现矛盾。
- **级别**：P2
- **原则**：15、42
- **确证**：确证（页面逻辑逐行读；`manager.retry` 失败/空 spec 均无诊断留痕已核对）。

## B4-C-08 · 测试覆盖缺口：206/Content-Range、回合守卫、令牌警告、presign 失败、完整性失败均无测试

- **文件:行号**：`test/base/range_download_test.dart`（仅覆盖 `OgLChunkPlan` 纯函数 + 取消令牌标志位，122 行）；
  `test/domain/ix_download_test.dart`（仅文件名净化 / 协议白名单 / SSRF 主机判定 / 摘要规整，199 行）；
  `test/domain/ix_download_manager_test.dart`（幂等入队 + 状态机，Fake 后端 supportsRanged=false，
  376 行，**从未触达分片引擎路径**）
- **缺口清单**（均为链路内已实现、注释大量着墨的关键行为，测试为零）：
  1. `_fetchPart` 的 206 + Content-Range 逐字节对齐 / 总量一致校验
     （`range_download_io.dart:216-238`）——错位区间拼坏文件的高危防线，无任何回归测试；
  2. 服务端忽略 Range 回 200 → 回退单连接（`ix_download.dart:884-894`，OGL-DL-204）；
  3. 回合制守卫 `_roundOf`（:750-751、:853/:869/:882）——resume/retry 竞态防线，无测试；
  4. 令牌出设备警告 `ogLGuardTokenExitDownload` / `ogLIsGitHubDownloadHost`
     （`token_exit_warning.dart` 全文件；`rg tokenExit test/` 零命中）——白名单、
     不可关闭弹窗、留痕均未测；
  5. presign 失败回退（`surface_bridge.resolveDownloadUrl` 注释自述「此前 catch(_) 吞错」，
     现行为无测试锁定）；`IxPresignProbe.resolve` 本身因直连 dart:io 亦不可离线测试
     （原则 50 视角：传输未抽接口）；
  6. `_verifyIntegrity` 不匹配 → 删文件 + 置失败（:1300-1325）；Fake 后端
     `canReadLocalFile=false`，manager 测试只能走「未校验」分支。
- **后果**：契约层 `DownloadEngine` 明知是「硬件层实现、逻辑层只认接口」（`download_engine.dart:21-26`），
  但测试用假引擎只测了编排的外圈；上述 6 项中任一回归，CI 全绿。
- **级别**：P1（1/3/4 三项为安全或数据正确性防线）
- **原则**：49、50、51
- **确证**：确证（4 个测试文件全文读完 + `rg --files test` 全量核对下载相关仅此 4 个 + ix_test/ix_conflict_test）。

## B4-C-09 · 门禁盲区：`contract_audit.py` 明确跳过条件导入的桩目标；`layer_audit.py` 不解析 `export`

- **文件:行号**：`tool/contract_audit.py:85-88`（`if imp.startswith('package:') or imp.startswith('dart:') or 'if (' in imp: continue`）；
  `tool/layer_audit.py`（全文无 `export` 处理逻辑，`rg -n "export" tool/layer_audit.py` 零命中）
- **问题**：①条件导入 `import 'a.dart' if (dart.library.x) 'b.dart' as t;` 的正则只捕获
  首个引号串（a.dart），`:85-88` 的 `'if (' in imp` 跳过使**桩目标 b.dart 的存在性永不校验**——
  桩路径写错（如 `ix_action_logs_save_stub.dart` 改名）CI 依然全绿；②分层 import 检查
  （layer_audit）不解析 `export`，向上 re-export（如 `range_download.dart:27`
  `export 'range_download_io.dart' show OgLRangeDownloader;`）可绕过分层扫描——当前由
  `contract_audit.check_exports` 兜住（其 `IMPORT_RE` 同时匹配 export），但两脚本各自的
  盲区组合后，仅当两门禁同时被绕过才暴露，属《CONSISTENCY.md:55》自述「待补」的延续。
- **后果**：条件导入配对（本批 B4-C-05 命中的问题类别）与 export 方向均无完整自动裁决；
  「CI 全绿下语义缺陷共存」的结构性风险持续存在。
- **级别**：P2
- **原则**：53、3
- **确证**：确证（两脚本全文读 + 实跑 `contract_audit.py`：4 项检查合计 0 处，与 AGENTS.md:10
  「当前基线违规 0」一致；`'if (' in imp` 行号 :86 核对）。另证：contract_audit 自述
  「只做可静态确证的结构检查」，**不检查语义**——这与其定位一致，不算缺陷，但意味着
  B4-C-01/02/03 这类语义问题全部落在人读区间（原则 53 后半句）。

## B4-C-10 · 注释引用两份未落地文档（自带「未落地」标注），且文档存在性门禁不扫 lib 注释

- **文件:行号**：`lib/domain/ix/ix_conflict.dart:6`（`[DURABILITY.md](../docs/DURABILITY.md（该文件未落地，以源码为准）)`）、
  `lib/domain/ix/ix_notify.dart:4`（`docs/BOOT.md（该文件未落地，以源码为准）`）；
  `tool/contract_audit.py:100-114`（`check_doc_refs` 只扫 `docs/*.md` 内的 `docs/` 引用）
- **问题**：两处 lib 注释引用不存在的契约文档。代码侧已自我标注「未落地，以源码为准」
  （符合原则 58 自我勘误），但门禁对 lib 注释里的文档引用零覆盖，未来新增无标注的死引用
  不会被任何脚本发现。
- **后果**：轻微；主要为门禁盲区的又一实例。
- **级别**：P2
- **原则**：57
- **确证**：确证（`ls docs | rg -i 'durab|boot'` 零命中；`check_doc_refs` 逐行读）。

## B4-C-11 · 沿袭发现：`docs/NETWORK.md:150` 待办链接指向仓库外 `_setup/ogl_sync.py`

- **文件:行号**：`docs/NETWORK.md:150`（`../../../_setup/ogl_sync.py`）
- **问题**：与本工作区路径解析后不存在（`_setup/` 非仓库内容，NETWORK.md:85 亦自述
  「本机脚本，不纳入仓库」）。与 B3-C-xx（audit_b3_c.md:116-119）同一结论，此处仅沿袭登记，
  不重复展开。
- **级别**：P2
- **原则**：57
- **确证**：确证（路径不可达；脚本是否存在于仓库外**未确证**，同 B3-C 的克制口径）。

---

## 已核对且通过的契约点（正面结论，均有证据）

1. **契约层 download_engine.dart**：`DownloadUnsupported` 语义（「调用方应回退到普通单连接下载」，
   :96-101）与 `ix_download.dart:862-877` 的回退实现一致；「失败必须清理」契约
   （:19-20）与 `range_download_io.dart:266-290`（合并失败连 target 一并删除）一致；
   fetch 返回写入字节数、probe/fetch/close/newCancelToken 五要素齐备。
2. **206 / Content-Range 防线实现本身完整**（缺口在测试，不在实现）：`range_download_io.dart:216-238`
   要求 Content-Range 存在、区间逐字节对齐、总量一致，缺一即抛 `DownloadHttpException`；
   「200 而非 206」在 manager 层有独立回退分支（OGL-DL-204）。
3. **回合制守卫实现与注释一致**：`_runRanged` 单飞守卫 + 回合 +1（:745-751），
   三处 catch 均先校验 `_roundOf[id] != myRound` 再写状态（:853/:869/:882），
   `finally` 清 token/paused（:921-924）；`remove` 额外清 `_roundOf`（:1135）。
   注释声称的「旧轮回调一切状态写入静默退出」与实现吻合（`_applyRangeProgress` 的
   状态覆写由 `DownloadCanceled` 之后的守卫覆盖；进度回调本身在 fetch 已取消后不再产生）。
4. **L2/L1 文件头层级前缀全部正确**：`lib/domain/ix/` 13 文件均以「L2 中枢级」开头，
   `range_download.dart` / `range_download_io.dart` 均为「L1 硬件层」，
   `download_engine.dart` 为「L0 启动层契约」；实跑 `contract_audit.py` 文件头检查 0 违规。
5. **条件 import 与 *_io/_stub 配对（存在的一处）成立**：`ix_action_logs.dart:25`
   `if (dart.library.js_interop) 'ix_action_logs_save_stub.dart'`——io 版真实落盘、
   stub 版如实抛 `IxActionLogsException`（不假装成功，`ix_action_logs_save_stub.dart:11-16`），
   两文件均存在且签名一致；`gh_oauth.dart:22` 同款成立。
6. **59 条原则关键项符合度**（逐条核对）：
   - 15/16 失败可见：分片失败 OGL-DL-202 + 通知中心 push、回退失败 OGL-DL-205、
     收尾异常 OGL-DL-407、SAF 导出失败 OGL-DL-301 warn——事件码全覆盖（例外见 B4-C-03/07）；
   - 22 过期回调丢弃：回合守卫 + `_disposed` 旗 + `_safeNotify` + pathFor 窗口
     `identical(_snapshots[id], queued)` 复活守卫（:704-707）+ fileSha256 后重取快照（:1240-1247）；
   - 24 资源对称：`dispose` 先立 `_disposed` 再 cancel 全部 token、退订流、dispose 后端（:1520-1532）；
     `IoDownloadBackend.dispose` 退订 + 关流（:196-200）；`IxActionLogsHttp` finally 即用即关；
   - 40 令牌单跳：presign 显式不跟随重定向（`ix_presign_io.dart:44-46`）、
     action logs 手动重定向且后续跳不带凭证（`ix_action_logs_http_io.dart:40-77`）、
     200 分支不 drain 注释（:60-66）；
   - 12 危险操作类型化确认：`IxTaskRunner.run` 无确认即抛 `IxConfirmationRequired`（ix_task.dart:369-379）
     + TOKEN-EXIT-01 三重不可关闭（barrierDismissible=false / PopScope canPop=false / 无计时器）；
   - 44 SSRF 下限：`isForbiddenHost` 覆盖回环/私网/链路本地/整数 IPv4/IPv4 映射 IPv6/`::1`/`fc00::/7`，
     测试 29 个主机样例钉死（ix_download_test.dart:117-145）。
7. **文档出口清单与符号真实性**：`NETWORK.md` 出口表引用的
   `SurfaceBridge.planRepoFileDownload`（surface_bridge.dart:351）、`IxPresign.resolve`、
   `DnsService`、`ogLAccelCandidates` 均实存；「九类加速范围」（NETWORK.md:55）与
   `accel.dart:85-116` 的 `OgLAccelScope` 逐一对照确为 9 类（releaseAsset/actionArtifact/
   repoFile/readmeImage/gistFile/repoArchive/actionLog/avatarImage/readmeExternalImage），
   其中 actionLog/avatarImage「预留未接入」的说明与 `accel.dart:107-111`、
   `download_proxy.dart:48` 注释一致。

## 覆盖文件清单

| 文件 | 状态 |
|---|---|
| `lib/domain/ix/ix_download.dart`（1533 行） | 完整读（3 段） |
| `lib/domain/ix/ix_download_backend_io.dart`（279） | 完整读 |
| `lib/domain/ix/ix_download_error.dart`（59） | 完整读 |
| `lib/domain/ix/ix_presign.dart`（241）· `ix_presign_io.dart`（98） | 完整读 |
| `lib/domain/ix/ix_task.dart`（445）· `ix_conflict.dart`（271）· `ix_session.dart`（355）· `ix_notify.dart`（229） | 完整读 |
| `lib/domain/ix/ix_action_logs.dart`（162）· `ix_action_logs_http_io.dart`（132）· `ix_action_logs_save_io.dart`（24）· `ix_action_logs_save_stub.dart`（16） | 完整读 |
| `lib/base/net/range_download.dart`（97）· `range_download_io.dart`（345） | 完整读 |
| `lib/kernel/contract/download_engine.dart`（149） | 完整读 |
| `lib/surface/pages/download_manager_page.dart`（537）· `lib/surface/app/token_exit_warning.dart`（170） | 完整读 |
| `test/base/range_download_test.dart`· `test/domain/ix_download_test.dart`· `ix_download_manager_test.dart`· `ix_test.dart`· `ix_conflict_test.dart` | 完整读（前 4）；`ix_conflict_test.dart` 经 `ix_test.dart` 冲突组与 `rg --files test` 核对归属 |
| `tool/contract_audit.py`（161） | 完整读 + 实跑（0 违规） |
| `tool/layer_audit.py` | 定向核验（export 处理缺失） |
| `docs/NETWORK.md`·`ARCHITECTURE.md`·`AGENTS.md`·`QUALITY_STANDARD.md`·`CONSISTENCY.md` | 完整读（前四）+ 定向核对（ARCHITECTURE 下载相关条目） |
| 关联核验（非完整读）：`surface_bridge.dart`（下载方案/桥接段 280-560）、`accel.dart` 枚举段、`download_proxy.dart`/`release_detail_page.dart`/`repo_page.dart`/`gist_detail_page.dart` 调用点、`domain_bridge.dart` import 段 | 定向读 |

## 整体规范符合度评价

下载链路是全库注释-实现一致性最好的子系统之一：契约层
（`download_engine.dart`）语义清晰且回退实现忠实履约；回合制守卫、幂等入队、
复活守卫、SAF 导出去重等并发/生命周期防线与注释逐条对得上，事件码体系
（OGL-DL-1xx~5xx）完整可回溯。主要失分点集中在三处：**①注释体系残留一个
未落地的 Web 后端叙事**（B4-C-05，条件导入缺失使 ix_download 在 Web 目标不可编译，
与其自述矛盾）；**②文档「无降级无兜底」与代码内三处「静默降级」死机制注释并置**
（B4-C-01，当前由调用点收缩而麻痹，机制仍在）；**③测试面严重偏科**——纯函数与
编排外圈覆盖良好，但 206/Content-Range 校验、回合守卫、令牌警告、完整性失败、
presign 失败这些最关键的防线零测试（B4-C-08），门禁又只守结构不守语义
（B4-C-09），这些防线目前完全悬在人读区间。综合：结构契约与原则符合度高
（11 条发现中 P1 仅 3 条，且无一条是当前可触发的数据损坏路径），建议优先级
为 B4-C-08（补测试）> B4-C-05（补 Web 桩或改注释）> B4-C-01（统一降级叙事）。
