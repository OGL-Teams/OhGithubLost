# 第2批·视角C：契约与规范一致性审计（磁盘一致性层）

> 审计对象：`/root/OhGithubLost` main 分支（`d9c1487`）磁盘一致性层。
> 视角：**契约与规范一致性**（QUALITY_STANDARD.md 59 条原则逐条对照、分层/契约上提、文件头与命名、D1–D9 注释-实现一致、测试覆盖、CI 门禁盲区、不可变性与序列化往返）。
> 纪律：只审不改；**未修改**任何 `lib/`、`test/`、`docs/ARCHITECTURE.md`；本文件是唯一写入目标。
> 阅读方式：`file_read` 完整读 12 个 `lib/base/disk/*.dart` + 2 个 `lib/kernel/contract/disk_*.dart` + `test/base/` 全部 12 个测试文件 + `docs/ARCHITECTURE.md` + `docs/QUALITY_STANDARD.md` + `AGENTS.md` + `tool/{layer,motion,perf}_audit.py`；辅助阅读 `lib/kernel/diagnostics.dart`、`lib/base/base_bootstrap.dart`、`lib/domain/domain_bridge.dart` 片段、`docs/audit_206.md`、`docs/AUDIT_PLAN.md`、`docs/5layer-audit-todo.md`、`git log`。
> 编号 `B2-C-xx`；每条含文件:行号 / 文档章节、问题描述、**违反的原则编号与文档原话**、P0/P1/P2、是否确证（附证据）。不确定者标「待议」。

## 阅读基线（覆盖文件清单见文末）

- `tool/layer_audit.py --fatal` 实跑：文件总数 147，已知待收敛 2 处，违规 0 处，exit=0。
- `tool/motion_audit.py --fatal` / `tool/perf_audit.py --fatal` 实跑：均 0 违规、exit=0（两者只扫 `lib/surface/`）。
- `lib/base/disk/` 12 文件全有 `/// L1 底座级 · …`（转发文件除外，见 B2-C-03）与 `library;`。
- 7 行转发导出 `disk_store.dart` / `disk_types.dart` 与 `kernel/contract/` 同名文件完全对应：符号无残留、无重复定义、无向上依赖（见 B2-C-02）。

---

## 确证清单

### B2-C-01 · D1 新语义「远端不存在+无基线=合法新建」未同步到文件头表格/规范文档（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:10`（D1 表格行）、`docs/ARCHITECTURE.md:55` / `:123`、`AGENTS.md:62`；对照实现 `lib/base/disk/disk_cache.dart:607-628`。
- **问题描述**：刚改过的 D1 只在 `_writeLocked` 内部注释（`:607-620`）与测试名（`test/base/cache_consistency_test.dart:201`）里写成「远端不存在 + 无基线 → 合法新建；远端已存在 + 无基线 → 拦下」。但作为「七道防线契约表」的文件头仍写 **「D1 写前必读 | 缺少 `baseSha` 直接拒绝（`requiresRead`）」**——这是旧行为的无条件描述，与实现矛盾；`AGENTS.md:62`「D1 写前必读」、`docs/ARCHITECTURE.md:55/123`「D1–D7 一致性」同样没有记录新语义或 D1′/D2′（`disk_cache.dart:645-661`）分支。另外 `lib/domain/gh/gh_api.dart:838` 的 `putContentLocked` doc 仍写「缺基线拒绝（D1）」，与「空串基线=新建、不带 sha」的实现（`:865`、`:779-780`）冲突。注释解释「是什么」且已过时，评审/新调用方按文档写就会把新建误判为失败。
- **违反的原则编号/文档原话**：原则 **54**「注释解释为什么；"是什么"由代码自证」、**57**「文档引用的符号必须真实存在；改名时文档一并改，否则文档在撒谎」、**59**「新增能力先问归属：属于哪一层、经哪个桥、由哪个契约表达」；`docs/ARCHITECTURE.md` 摘要「**本文所引用的符号必须与代码一致且真实存在；符号改名或行为变更时，须同步更新本文**」；`AGENTS.md §3`「文件头注释是硬惯例」。
- **证据**：`git show eaadd65`（提交说明「disk_cache D1 完整语义：远端不存在 + 无基线 = 合法新建」）的 diff **只改了 `disk_cache.dart` 实现与内联注释，未改文件头表格、未改 AGENTS/ARCHITECTURE**；`git log -S"缺少 \`baseSha\` 直接拒绝"` 停在 `e4775c2`（早于 D1 变更）。
- **是否确证**：确证。

### B2-C-02 · 契约上提「彻底性」不足：`RepositoryCache` 实现仍无内核契约抽象，`domain` 直接依赖具体类型（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:17`（`import '../../base/disk/disk_cache.dart'`）、`lib/surface/surface_bridge.dart:20`（同上）、`tool/layer_audit.py:40-49`（`KNOWN` 白名单）、`docs/ARCHITECTURE.md:4.2/4.3/§7`、`AGENTS.md §1`。
- **问题描述**：`disk_store.dart` / `disk_types.dart` 的 7 行转发导出上提**是彻底的**（`lib/base/disk/disk_store.dart:7` → `kernel/contract/disk_store.dart`，`lib/base/disk/disk_types.dart:7` → `kernel/contract/disk_types.dart`；`domain/*` 已普遍改走 `kernel/contract/disk_*.dart`，见 `gh_auth.dart:24`、`gh_client.dart:18`、`ix_conflict.dart:10`、`repo_file_service.dart:49`、`ix_session.dart:14`、`sys_access.dart:19`）。但同属「共享契约」的一致性引擎 `RepositoryCache` / `DiskBridge` 仍留在 `base/disk/` 被 `domain` 与 `surface` 直接 import；`layer_audit.py` 用 `KNOWN` + `ALLOW` 把它豁免成「违规 0」，`ARCHITECTURE.md §4.3` 自己承认「正确做法是在 `kernel/contract/` 定义抽象、由硬件层实现、逻辑层仅依赖抽象」。契约上提只做了一半，且白名单无归零计划（`§7 后续工作` 已写了多个版本仍未动）。
- **违反的原则编号/文档原话**：原则 **2**「层与层之间只经桥通信；直接穿越层边界取内部对象，等于宣布该层不存在」、**3**「例外必须显式登记、可枚举、可归零；没有清单的例外就是漏洞」、**5**「契约先于实现；共享类型上提到最底层，而不是让上层互相看见」；`docs/ARCHITECTURE.md §2 设计目标 3`「跨层访问受控：跨层类型共享须经桥 / 门面，禁止直接导入其他层的实现」；`AGENTS.md §1`「`KNOWN` 白名单恰 2 项待收敛（正解：在 `kernel/contract/` 定义抽象）」。
- **证据**：`python3 tool/layer_audit.py --fatal` 输出「已知待收敛（5.0 清单）：2 处 / 违规：0 处」；`grep` 到 3 处跨层直接 import `disk_cache.dart`；`disk_bridge.dart:39` 直接把 `final RepositoryCache cache` 暴露给上层。
- **是否确证**：确证（属于登记在册的待收敛项，本视角按「契约上提彻底性」记为规范债，非新增违规）。

### B2-C-03 · 两个 7 行转发导出文件缺 `/// L1 底座级 · …` 层级注释，且 `kernel/contract/` 的同名文件头仍自称 L1（P2，确证）

- **文件:行号**：`lib/base/disk/disk_store.dart:1-7`、`lib/base/disk/disk_types.dart:1-7`；`lib/kernel/contract/disk_store.dart:1`、`lib/kernel/contract/disk_types.dart:1`、`lib/kernel/contract/net_types.dart:1`。
- **问题描述**：`AGENTS.md §3` 规定「文件头注释是硬惯例：`/// L1 底座级 · …` 层级前缀 + `library;` + 中文设计说明（含表格/ASCII 图）」。这两个文件有 `library;`（各 `:5`）和两行说明，但**没有层级前缀**，说明内容也不是设计说明而是迁移提示；`kernel/contract/` 下被上提的 `disk_store.dart` / `disk_types.dart` / `net_types.dart` 头部仍写 **「L1 底座级」**，与同目录 `download_engine.dart:1` / `storage_export.dart:1` 的「L0 启动层契约」以及 `ARCHITECTURE.md:53`（kernel L0）、`module.dart:4`「OGL 内核契约」自相矛盾。层级标签在跨文件迁移后未同步，审计脚本按前缀识别层级角色时会把 L0 契约误认成 L1 实现。
- **违反的原则编号/文档原话**：原则 **6**「命名即结构：文件名必须能让审计脚本识别其层级角色；无法识别的名字不得存在」、**57**「改名时文档一并改，否则文档在撒谎」；`AGENTS.md §3`「**文件头注释是硬惯例**：`/// L1 底座级 · …` 层级前缀 + `library;` + 中文设计说明」；`ARCHITECTURE.md §1`「依赖只能向下」。
- **证据**：`head -6` 全部 12 个 disk 文件与 6 个 kernel/contract 文件对照；`lib/base/net/net_types.dart:7` 同为 7 行转发导出，同样缺层级前缀（同族问题）。
- **是否确证**：确证。

### B2-C-04 · D5 文件头表格 / `WriteConflict.verificationFailed` 描述旧行为：回读不一致不再产生失败结果（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:14`（D5 表格「回读带少量重试；仍不一致即 `verificationFailed`」）、`lib/kernel/contract/disk_types.dart:224-226`（枚举注释「写后回读校验失败（D5）」）、`lib/kernel/contract/disk_types.dart:288-293`（`resolveConflictActions(verificationFailed)` 仍给 `retry` / `pullRemote`）、`lib/base/disk/disk_cache.dart:829-834`（`_isRetryable` 仍把它算可重放）；对照实现 `lib/base/disk/disk_cache.dart:686-701`、`:745-758`。
- **问题描述**：实现已改为「PUT 回执 sha 权威；回读只做本地缓存对齐；不一致也**按成功收尾**」，`_verifyReadback` 返回 `null` 时以 `RemoteDocument(content: content, sha: written.sha)` 入缓存并返回 `WriteOutcome.success`。**代码中已不存在任何产出 `WriteConflict.verificationFailed` 的路径**（全仓 grep 仅剩类型定义、映射、UI 文案、测试的枚举比较），但头部 D5 表格与契约枚举注释仍宣称「仍不一致即 verificationFailed」，处置建议表还给它列了两种用户动作。这是「枚举值已成死分支但契约仍承诺」——上层照契约写的冲突 UI/重试逻辑永远不会被触发。
- **违反的原则编号/文档原话**：原则 **54**「注释解释为什么；"是什么"由代码自证」、**55**「死代码零容忍；注释掉的代码与过时的白名单一样，都是给后人的假情报」、**57**「文档引用的符号必须真实存在」；`docs/QUALITY_STANDARD.md` 第三章 **17**「用类型表达失败；让调用方无法忽略错误」——类型里保留一个永不产生的失败态，削弱「类型表达失败」的可信度；`test/base/cache_consistency_test.dart:337-360` 的测试名已写「提交仍按成功收尾（回执权威）」而头部表格未改。
- **证据**：`grep -rn "verificationFailed" lib test` 无任何 `WriteOutcome.failure(WriteConflict.verificationFailed, ...)` 构造点；`disk_cache.dart:686-691` 内联注释明确「此前…判 verificationFailed…现在…按成功收尾」；`git log` 显示该变更（v10.1.0）早于本分支。
- **是否确证**：确证。

### B2-C-05 · `docs/CONSISTENCY.md` 被当作契约出处引用但文件不存在（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:4`、`lib/base/disk/disk_bridge.dart:39`、`test/base/cache_consistency_test.dart:4`；对照 `docs/` 目录清单。
- **问题描述**：全项目「最危险」代码的文件头声称「这里的每一条规则都对应 `docs/CONSISTENCY.md` 中的一道防线」，`DiskBridge` 文档注释把「致命区」指向它，最关键测试的文件头也称「每一条用例都直接对应 `docs/CONSISTENCY.md` 中的一道防线」。前两处自带括号「（该文件未落地，以源码为准）」，**测试文件那一处连这个声明都没有**。七道防线的唯一外部规范不存在，实际规范退化为源码内联表格（而该表格本身已过时，见 B2-C-01/04），CI 与评审没有可对照的契约基线。
- **违反的原则编号/文档原话**：原则 **57**「文档引用的符号必须真实存在；改名时文档一并改，否则文档在撒谎」、**5**「契约先于实现」、**56**「文档只收持续有效的手册」；`ARCHITECTURE.md` 摘要「本文所引用的符号必须与代码一致且**真实存在**；否则文档将失去准确性」；`docs/README.md` 的文档目录索引中无该文件。
- **证据**：`ls docs/` 无 `CONSISTENCY.md`；`grep -rn "CONSISTENCY.md" lib test docs/ARCHITECTURE.md` 只得到上述 3 处引用；`docs/5layer-audit-todo.md` 亦记载「但仅验证语法 / 导入 / 分层规范，尚未验证语义设计的严密性」。
- **是否确证**：确证。

### B2-C-06 · 「防线没有开关」被 `recordJournal: false` / `force` / 裸 `confirmed: true` 打破（P0，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:245-252`（`write(..., {bool confirmed = false, bool recordJournal = true})`）、`:596-604`（`(intent.dangerous || intent.force) && !confirmed` 放行）、`:665-667`（`(!recordJournal || _journal == null) ? null : enqueue`）、`lib/kernel/contract/disk_types.dart:366`（`force` 字段注释「跳过 D2」）。
- **问题描述**：文件头 `:5-6` 宣称「**不提供任何"绕过"开关**」，但公开 API 上存在三个可绕过防线的布尔捷径：
  1. `recordJournal: false` 可**完全关掉 D8 写前落盘**（原则 13/14），且参数没有类型约束，任何调用方都能传；`_journal == null`（未装配日志）也静默跳过 D8 而不是拒绝写入；
  2. `force: true` + `confirmed: true` 跳过 D1/D2/D2′ 全部基线校验（`:622`、`:632`、`:653` 的 `!intent.force` 短路），`confirmed` 只是普通 `bool`，不是「在类型上表达」的确认凭证；
  3. `confirmed: true` 由 `test/base/chaos_test.dart:183` 在 `replayPending` 上整体传给所有待办记录，等于一次性为队列里全部危险操作盖章。
  `Archive.md §5` / `AGENTS.md:62` 都写「**无绕过开关**」，与实现不符。`gh_api.dart:841-920` 的 `putContentLocked` 更存在「`cache == null || key == null` → 退化为裸写」的整条旁路（`:853-857`），D1–D7 一条不走。
- **违反的原则编号/文档原话**：原则 **11**「**防线没有开关。任何"绕过校验"的捷径参数都不允许存在**」、**12**「危险操作必须经过用户显式确认；**确认在类型上表达，不靠调用方自觉**」、**14**「删除前落盘意图，成功后清除记录」、**13**「每次写入要么完整生效，要么可恢复」；`AGENTS.md:62`「**无绕过开关**」、`AGENTS.md §5`「`IxTaskRunner` 在类型上强制 `IxBatchDecision`（用户确认）」——同项目已有「类型表达确认」的范式，磁盘层却用裸 bool。
- **证据**：`grep -rn "recordJournal:\|confirmed:" lib test`；`disk_cache.dart:667` 三元表达式；`gh_api.dart:853` 注释「未绑定缓存 / 无法构造合法键：退化为裸写」。测试只验证了 `force` 未确认被拒（`cache_consistency_test.dart:484-505`），**没有测试 `recordJournal: false` 与裸写旁路**。
- **是否确证**：确证（部分为设计取舍：见 B2-C-14「待议」对 `force` 语义的复核）。

### B2-C-07 · 危险操作「删除」不入提交日志，与「删除前落盘意图」直接冲突（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:288-296`（`delete` doc 注释「为什么**不入提交日志**」）、`:327-377`（`delete` 实现全程无 `enqueue`）；`lib/domain/gh/gh_api.dart:956-985`（`deleteContentLocked` 未绑定缓存时直接裸删）。
- **问题描述**：`WriteJournal` / D8 只覆盖写入。删除路径明确以「删除无法用 `WriteIntent` 表达」为由放弃落盘意图，并在网络异常时只返回 `WriteConflict.server`（`:372-376`），不留任何可重启发现/重放的痕迹；崩溃窗口内用户已确认的删除意图彻底消失。`JournalRecord` 没有删除意图的表达能力（无 `isDelete` / `operation` 字段，`disk_journal.dart:41-83`），契约本身缺一类写操作。
- **违反的原则编号/文档原话**：原则 **14**「**删除前落盘意图**，成功后清除记录；写日志的时间点本身就是恢复的依据」、**13**「半成品状态必须留有痕迹并能被重启发现」、**8**「数据无价…用户写的内容不能丢」；`AGENTS.md §5`「D8 = Write Journal（可恢复事务）」未声明删除例外；`QUALITY_STANDARD.md` 原则 **3**「例外必须显式登记、可枚举、可归零」——此例外只写在源码注释里，未进任何例外清单。
- **证据**：`grep -rn "\.enqueue(" lib` 只有 `disk_cache.dart:667` 一处；`delete` 方法体 `:327-377` 无日志调用；`test/base/*` 无任何 `cache.delete(` 用例（只有 fake remote 的 `delete` 桩）。
- **是否确证**：确证。

### B2-C-08 · 206 回读确认修复无任何离线回归测试（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:765-812`（`putContent` 的 206/截断响应修复）、`docs/audit_206.md`（A-206-01，已修复）；对照 `test/base/`、`test/domain/` 全部测试。
- **问题描述**：`c142b45` 落地的 P0 修复「`written.sha.isEmpty` → 回读远端确认；回读不到则如实抛带状态码异常」在 `test/` 中零覆盖：`grep -rn "206\|putContent\|HTTP 206" test` 唯一命中是 `test/base/cache_consistency_test.dart:529` 的**诊断码 `OGL-CONS-206` 断言**（那是异常出口的事件码，与 HTTP 206 无关，`docs/audit_206.md` 专门强调「二者不可混为一谈」）。`test/domain/gh_absent_test.dart` 虽有 `ScriptedTransport` + `_json(..., status: 206)` 的现成离线回放设施，却未用于此路径。修复的三条分支（空 sha→回读成功 / 空 sha→回读也拿不到抛 `GhAuthException` / 正常回执不回读）都无断言。`docs/audit_206.md` 结尾「门禁」只列了 format 与四个 audit 脚本，**没有测试**。
- **违反的原则编号/文档原话**：原则 **49**「测试离线可跑；依赖网络或真机的测试不属于门禁」、**50**「用接口 + 内存实现替代真实依赖；测试测的是契约，不是巧合」、**51**「破坏性测试与正常路径同等重要」、**42**「失败如实报错；伪造的成功响应比失败本身更难排查」（该修复正是为「残缺 2xx 不能被当成功」而做）；`docs/AUDIT_PLAN.md`「输出格式…确证项附证据」与 `AGENTS.md §7`「重点测试…`chaos_test.dart`（破坏性混沌注入）」。
- **证据**：`git show --stat c142b45` 的 9 个改动文件**不含任何 `test/`**；`grep -rn "putContent" test` 结果为空；`grep -rn "206" test` 仅 1 处诊断码。
- **是否确证**：确证。

### B2-C-09 · 三类 CI 门禁对磁盘层完全无覆盖（P1，确证）

- **文件:行号**：`tool/layer_audit.py:38`（`IMPORT_RE` 只匹配 `import`，不匹配 `export`）、`:76-77`（`ALLOW` 整文件跳过）、`:86-93`（`tlay == 'kernel'` 一律放行、`KNOWN` 免检）；`tool/motion_audit.py:35`（`SURFACE = ROOT/lib/surface`）、`tool/perf_audit.py:36`（同）；`docs/ARCHITECTURE.md §8.2`。
- **问题描述**：
  - `motion_audit.py` / `perf_audit.py` 硬编码只遍历 `lib/surface/`，**对 `lib/base/disk/` 一个字节都不扫**，`--fatal` 全绿与磁盘层质量无关；`ARCHITECTURE.md §8.2` 把二者列进「提交前自检」并宣称「违规 0」，容易误读为全库检查。
  - `layer_audit.py` 是唯一覆盖该层的门禁，但有 3 个盲区：① `export` 指令不进正则（7 行转发导出 `disk_store.dart:7` / `disk_types.dart:7` / `platform_io.dart:12` 的分层方向完全未被校验）；② `ALLOW` 中的 `surface/surface_bridge.dart` **整文件跳过**，该文件 `:20-21` 直接 import `base/disk/disk_cache.dart` 与 `disk_store.dart` 不受审查；③ `KNOWN` 白名单（`:44-49`）把 `gh_api.dart → disk_cache.dart` 计为「已知待收敛」而非违规，且无归零检查（原则 3）。
  - 语义层（D1–D9 注释/实现一致、失败留痕、并发上限、序列化往返）**没有任何脚本守**；`docs/5layer-audit-todo.md` 自认「仅验证语法 / 导入 / 分层规范，尚未验证语义设计的严密性」，`QUALITY_STANDARD.md` 原则 53 也把语义交给「人读」——但本次审计正是人读才发现 B2-C-01/04/06/07。
- **违反的原则编号/文档原话**：原则 **53**「审计脚本只守语法与结构；语义严密性靠人读，读的时候禁止只看 diff」（承认现状，但本条指出现有脚本连结构都没守全）、**3**「例外必须显式登记、可枚举、可归零；没有清单的例外就是漏洞」、**6**「命名即结构：文件名必须能让审计脚本识别其层级角色」；`AGENTS.md §2`「layer_audit.py --fatal：分层 import 检查（见上）…**扫描 lib/ 全部相对 import**」——`export` 与 `ALLOW` 跳过使该描述不完全成立。
- **证据**：实跑三个脚本输出（见阅读基线）；`grep -n "^export " lib` 得 8 处转发导出；`layer_audit.py:38` 正则字面量 `^\s*import\s+'([^']+)'`。
- **是否确证**：确证。

### B2-C-10 · `CacheKey` / `CacheScope` / `WriteIntent` / `WriteOutcome` 无 `toJson`/`fromJson`，「往返稳定性」契约不完整（P1，确证）

- **文件:行号**：`lib/kernel/contract/disk_types.dart:14-75`（`CacheScope`）、`:82-135`（`CacheKey`）、`:342-380`（`WriteIntent`）、`:383-459`（`WriteOutcome`）、`:462-509`（`CacheEntry.toJson`）；`test/base/durability_test.dart:346-353`、`test/base/chaos_test.dart:352-369`。
- **问题描述**：
  - **不可变性**：四个类都是 `const` 构造 + 全 `final` 字段（无可变集合、无 setter），`CacheScope`/`CacheKey` 自定义 `==`/`hashCode` 基于 `encode()`，不可变性成立；但**均未标 `@immutable`**（同目录 `download_engine.dart:19,64` 与 `og_l_storage.dart:41` 有），框架级不变式没有显式表达，也不受 `flutter/foundation` 的静态提示约束。
  - **序列化**：四个类都**没有** `toJson` / `fromJson`。唯一持久化途径是 `encode()` / `decode()` / `parse()`（字符串），且 `CacheKey.encode()/decode()` 对含 `|` 的路径可无损往返（`disk_types.dart:113-123` 只把前四段当作用域，测试 `durability_test.dart:346-350` 已锁）；但 `WriteIntent` / `WriteOutcome` 连编码都没有，`WriteOutcome.actions` / `threeWay` / `entry` 等派生字段无法往返。`CacheEntry` 有 `toJson()`（`:497`）却**没有 `fromJson`**，读取侧在 `disk_cache.dart:961-995` 手写 `jsonDecode` + `as` 强转；`JournalRecord` / `DraftRecord` 的 `toJson`/`fromJson` 只覆盖日志与草稿，**没有 `WriteIntent`/`WriteOutcome` 的往返测试**。
  - 因此「`toJson`/`fromJson` 往返稳定性」这一审计项在该契约层**没有对应实现与测试**，只有字符串 `encode/decode` 的等价物；而 `WriteIntent` 的 `rebase` 是函数字段（`:375`），本质上不可序列化——`JournalRecord.toIntent()`（`disk_journal.dart:85-91`）重放时**丢失 `force` / `rebase`**，与 `toIntent()` 注释「还原为写意图（重放时重新走 D1–D7，绝不跳过任何防线）」不符：原意图若是 `force` 覆盖，重放会退成普通写并被 D1 拦下。
  - **反序列化夹紧**：`DraftRecord.fromJson` / `JournalRecord.fromJson`（`disk_draft.dart:76-91`、`disk_journal.dart:124-147`）用 `try/catch (_) → null` 兜底，调用方直接 `remove` 坏记录且**不记诊断**（`disk_draft.dart:150-157`、`disk_journal.dart:275-281`），与原则 20「坏数据夹紧回默认值**并记录**」、原则 15「失败必须留痕」不符（属于「静默清理」）。
- **违反的原则编号/文档原话**：原则 **20**「外部数据不可信；反序列化永不抛异常，坏数据夹紧回默认值**并记录**」、**15**「静默降级是最严重的缺陷；失败必须以用户可感知的方式留痕」、**17**「用类型表达失败」、**13**「每次写入要么完整生效，要么可恢复；半成品状态必须留有痕迹并能被重启发现」（`toIntent()` 丢字段）；`AGENTS.md §3`「反序列化永不抛异常（夹紧回落默认）；**失败必留痕**，不静默降级」。
- **证据**：`grep -rn "toJson\|fromJson" lib/kernel/contract/disk_types.dart` 仅命中 `CacheEntry.toJson`；`grep -rn "toJson\|fromJson" test/base` 命中 `JournalRecord` 往返（`durability_test.dart:333-344`）与 `CacheKey.decode` 往返，无四类的 JSON 往返断言；`disk_journal.dart:85-91` 字段清单与 `disk_types.dart:346-375` 字段清单对比。
- **是否确证**：确证（不可变性成立；缺口是 `@immutable` 标注、JSON 往返实现/测试、`toIntent` 字段丢失、坏数据静默清理）。

### B2-C-11 · 「所有资源有上限」在磁盘层只做成「可调用但无人调用」的淘汰方法（P1，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:146`（`defaultMaxEntries = 512`）、`:165`、`:391-427`（`prune`）、`lib/base/disk/disk_journal.dart:229`（`maxAttempts = 5`，唯一生效的上限）、`lib/base/disk/disk_draft.dart:111`（`_operations` 无上限、按 key 分格）；`lib/surface/surface_bridge.dart:170`（唯一 `purge()` 调用，需用户手动）。
- **问题描述**：`prune()`（TTL + 条目上限 + 清孤儿 blob）在 `lib/` 内**没有任何调用点**（`grep -rn "\.prune("` 只命中定义与 `test/base/cache_consistency_test.dart:638`），`DiskModule.onRegister`（`disk_bridge.dart:120-159`）也不做启动清扫/淘汰。也就是说 512 条上限与 30 天 TTL 只是「提供能力」，运行时 `RepositoryCache` 会**无界增长**；`WriteJournal.records` 的 `abandoned` 记录除了 `clear()` 无淘汰路径，`DraftStore.all()` 全表扫描无上限，`_operations` 队列按 key 无界扩张。文件头 `:20` 宣称「**有界**：支持 TTL 与条目上限」，注释描述的是能力而非已生效的保证。
- **违反的原则编号/文档原话**：原则 **29**「**所有资源有上限：内存、磁盘、并发数、重试次数；无界增长终将以崩溃收场**」、**27**「并发假设写进注释」；`disk_cache.dart:389-390` 自己的注释「**磁盘是有界的**。没有淘汰策略的缓存，最终会写满磁盘」；`QUALITY_STANDARD.md` 第四章 **22**（过期回调校验）与第五章归属。同层 `net_dns.dart:575/589` 与 `ix_notify.dart:219` 都在写入点即时执行上限，磁盘层缺这一步。
- **证据**：`grep -rn "\.prune(\|\.purge(\|purgeOrphans(" lib test` 全部命中清单；`disk_bridge.dart:120-159` 装配阶段无 `prune()`。
- **是否确证**：确证。

### B2-C-12 · `app_dirs.dart` 直接做平台判定，绕过 platform 层门面（P1，确证）

- **文件:行号**：`lib/base/disk/app_dirs.dart:25`（`import 'package:flutter/foundation.dart'`）、`:86-89`（`defaultTargetPlatform == TargetPlatform.windows/linux/macOS`）；`lib/base/disk/app_dirs_fs_io.dart:17,20,49`、`og_l_storage_saf_io.dart:28,58`、`platform_io_impl.dart:67`、`disk_cache.dart:29,894`；`docs/ARCHITECTURE.md §4.3`、`:86`。
- **问题描述**：`AGENTS.md §1` 明令「**判平台一律走门面，禁止直接用 dart:io / defaultTargetPlatform**」，`ARCHITECTURE.md §2 设计目标 2`「平台判定收敛：所有 `defaultTargetPlatform` 等平台识别调用须经 `platform` 层门面；**新增代码不得直接进行平台判定**」。`app_dirs.dart`（非 `_io` 实现文件）却在 `tierOf()` 里直接判 `defaultTargetPlatform`；4 个实现文件直接 `Platform.is*`；`disk_cache.dart` 直接 `kIsWeb`。`ARCHITECTURE.md §4.3` 把 `base/disk/app_dirs.dart` 列为「已知待收敛」，但**该例外没有进入 `layer_audit.py` 的 `ALLOW`/`KNOWN` 清单**，门禁无法枚举、无法归零。
- **违反的原则编号/文档原话**：原则 **4**「**平台差异在唯一的位置裁决；其余代码面对同一抽象，不感知平台**」、**3**「例外必须显式登记、可枚举、可归零；没有清单的例外就是漏洞」；`AGENTS.md §1`「禁止直接用 dart:io / defaultTargetPlatform」；`ARCHITECTURE.md §4.3`「**新增代码不得直接进行平台判定**，应经 platform 层门面」。
- **证据**：`grep -rn "defaultTargetPlatform\|kIsWeb\|Platform\.is" lib/base/disk` 得 12 处；`python3 tool/layer_audit.py --fatal` 对这些一处都不报（只查相对 import 的层向）。
- **是否确证**：确证（历史上登记在册，但按「规范一致性」仍是未收敛且未进清单的例外）。

### B2-C-13 · `*_io.dart` / `*_web.dart` 平台配对约定在磁盘层不成立（P2，确证）

- **文件:行号**：`lib/base/disk/app_dirs_fs_io.dart`、`og_l_storage_saf_io.dart`、`platform_io.dart:1-12`、`platform_io_impl.dart`；`docs/ARCHITECTURE.md:86`、`AGENTS.md §1 命名约定`。
- **问题描述**：`AGENTS.md` / `ARCHITECTURE.md §5` 规定平台实现按 `*_io.dart`（原生）/ `*_web.dart`（浏览器）**条件 import 配对**，并称「此约定由 `layer_audit.py` 的命名规则强制」。磁盘层实际：`app_dirs.dart:27` / `og_l_storage.dart:26` / `platform_io.dart:12` 都是**无条件** `import`/`export`，全仓 `find lib -name '*_web.dart'` = **0 个**；`platform_io_impl.dart` 用 `_impl` 后缀而非 `_io`，且头部自称「本分支为纯原生构建，原先对 Web 的条件导出已移除」；`disk_cache.dart:29/894` 却仍保留 `kIsWeb` 分支，与「纯原生构建」自相矛盾。`ARCHITECTURE.md:86` 已补注「现无 `*_web.dart`」，但 `:90`「决策记录 6.2」仍宣称「平台层使用 `*_io.dart` 与 `*_web.dart` 的条件 import 约定…由 `layer_audit.py` 的命名规则强制，违反命名（如 `*_web_stub.dart`）将无法被识别」——而 `layer_audit.py` 全文**没有任何文件名后缀规则**（只有 `ALLOW` / `KNOWN` 路径集合）。
- **违反的原则编号/文档原话**：原则 **6**「命名即结构：文件名必须能让审计脚本识别其层级角色；无法识别的名字不得存在」、**57**「文档引用的符号必须真实存在…否则文档在撒谎」、**4**「平台差异在唯一的位置裁决」；`ARCHITECTURE.md §6.2` 与 `AGENTS.md §1` 的命名约定原文。
- **证据**：`find lib -name '*_web.dart' | wc -l` = 0；`grep -rn "if (dart.library" lib/base/disk` 无命中；`grep -n "io\|web\|impl" tool/layer_audit.py` 无命名规则。
- **是否确证**：确证。

### B2-C-14 · 七道防线 / D8 / D9 / 原子写 / chaos 的测试覆盖缺口清单（P1，确证）

- **文件:行号**：`test/base/cache_consistency_test.dart`（652 行）、`durability_test.dart`（367 行）、`chaos_test.dart`（379 行）、`platform_io_test.dart`（219 行）、`base_bootstrap_test.dart`（50 行）；对照 `lib/base/disk/disk_cache.dart:288-377`、`disk_journal.dart:229-245`、`disk_draft.dart:161-200`。
- **问题描述**：三个核心测试**全部离线**（内存 `CacheRemote` / `InMemoryKv` / `InMemoryFileStore` / `FlakyKv` / `TruncatingFileStore` / `ScriptedTransport`），符合原则 49/50/51，且七道防线、D8（成功/断网/409/重放/放弃/损坏自愈）、D9（保存/修订号/基线/丢弃/清空/损坏）、D10、原子写（tmp 清扫/长路径/路径穿越/KV 健壮性）与 chaos（崩溃/kill-9、磁盘满、撕裂写、500 路并发、模糊输入）都有断言——**覆盖主体是好的**。但存在以下确证缺口：
  1. **`test/base` 中没有任何测试断言旧的 D1 行为**（`grep -rn "requiresRead" test` 仅 `cache_consistency_test.dart:199`，且该用例是「远端已存在+无基线→拒绝」的**新语义**），因此「是否有测试仍断言旧的 D1 行为」答案是**否**；新增 D1 语义有对应测试（`:201-208`「远端不存在+无基线→合法新建」），但**空串基线 `baseSha: ''` 的归一化（SD-01 的另一半）在 `test/base` 无用例**，`force` 与「基线存在但远端消失」（D2′, `:645-661`）也无用例。
  2. `RepositoryCache.delete()`（D7 删除确认、D2 删除前基线、`notFound`/`staleSha` 三条分支）**零测试**；`JournalStatus.abandoned` 由 `maxAttempts=5` 触发（`disk_journal.dart:229-245`）**零测试**；`replayPending` 的 `confirmed` 传播、D8 `failByKey`「只标注最近一条」零测试。
  3. `DraftStore` 的 `ChangeNotifier` 可观察性、`_ordered` 串行化（防止旧写覆盖新内容）、`clear()` 并发安全零测试（原则 22/23/24 的生命周期对称未验证）。
  4. `platform_io_test.dart:4-6` 自述 `PlatformStorage.open` / `SecureDiskVault`「在 CI 上无法实例化，属于真机验收清单」——但 `base_bootstrap_test.dart:20-27` 实际用 `rootOverride` 调用了 `PlatformStorage.open` 并断言 `SecureDiskVault`，两处文件头对「离线可跑」的陈述互相矛盾；`SecureDiskVault` 的读写仍无断言。
  5. 原子写「先写 tmp 并 `flush` 再 `rename`」只有「不留 .tmp」的**结果断言**（`platform_io_test.dart:69-77`），没有注入 `rename` 失败 / 写入中断的 chaos 用例；`_packTooLong` 长路径收纳回退与 `_saveIndex` 索引损坏静默吞（`:163-170`）零测试。
  6. `test/base/net_contract_test.dart` 头注明「避开老文件格式器假阳性」而另起文件——说明 `test/base` 存在格式器层面的门禁盲区（与本视角 C 的「CI 盲区」呼应）。
- **违反的原则编号/文档原话**：原则 **49/50/51**（正向已满足）、**22**「每个异步结果都要校验它是否仍然有效；过期的回调必须被丢弃」、**23**「互斥闸门成对出现且属于同一所有者」、**24**「资源的开启与关闭在生命周期上对称」、**52**「端点语义必须实测：空、无、未启用是三种不同的"没有"」；`AGENTS.md §7`「重点测试：`chaos_test.dart`（破坏性混沌注入）、`durability_test.dart`、`cache_consistency_test.dart`」；`docs/QUALITY_STANDARD.md` 第九章三条。
- **证据**：逐文件 `file_read` 全文 + `grep -rn "delete(\|maxAttempts\|failByKey\|addListener\|rename" test/base` 命中清单；`wc -l` 行数如上。
- **是否确证**：确证（含对「旧 D1 测试」这一问的否定答复）。

### B2-C-15 · `OGL-CONS-206` 事件码与 HTTP 206 同名、且事件码在多条分支复用（P2，确证）

- **文件:行号**：`lib/base/disk/disk_cache.dart:277`、`:375`、`:976`（`OGL-CONS-208` 亦在 `:312` 与 `:976` 复用）；`docs/audit_206.md「根因 5」`；`AGENTS.md §3`「事件码 `OGL-BOOT-107`、`OGL-BASE-001` 带层标签」。
- **问题描述**：`OGL-CONS-206` 是 `write` 统一异常出口与 `delete` 异常出口的诊断码，却被 `docs/audit_206.md` 明确指为「**诊断码，不是 HTTP 206**，用户提示里出现的「206」来自 `GhResponse.statusCode`…**二者不可混为一谈**」——同一串数字在同一条写链路上承载两种语义，日志检索必然混淆（本次 `grep -rn "206" test` 就误命中 `cache_consistency_test.dart:529`）。同时 `OGL-CONS-208` 同时用于「删除需二次确认」（`:312`）与「本地内容完整性校验失败」（`:976`），`OGL-CONS-203` 用于 delete/write 两处冲突（`:368`、`:734`），事件码不唯一，违背「事件码带层标签、可定位」的自述惯例。`AGENTS.md §3` 举例的层标签是 `OGL-BASE-001`，磁盘层实际用 `OGL-CONS-*` / `OGL-JOURNAL-*` / `OGL-DRAFT-*`，无统一层标签字典。
- **违反的原则编号/文档原话**：原则 **15**「失败必须以用户可感知的方式留痕」（留痕必须可区分）、**57**「文档引用的符号必须真实存在」；`docs/audit_206.md` 原话「那是**诊断码，不是 HTTP 206**…二者不可混为一谈」；`AGENTS.md §3`「事件码 `OGL-BOOT-107`、`OGL-BASE-001` 带层标签」。
- **证据**：`grep -rn "OGL-CONS" lib/base/disk` 的 19 处清单（见正文统计）；`docs/audit_206.md:36-40`。
- **是否确证**：确证（影响可观测性，非功能故障）。

---

## 待议清单

### B2-C-16 · 文件头「无绕过开关」与 `force` 是否属于「用户显式确认的合法例外」（P1，待议）

- **文件:行号**：`lib/base/disk/disk_cache.dart:5-6` / `:245-252` / `:596-604`、`lib/kernel/contract/disk_types.dart:366`、`AGENTS.md:62`、`QUALITY_STANDARD.md` 原则 11/12。
- **问题描述**：`force` + `confirmed: true` 的语义在产品上可能是「用户在冲突对话框点『强制覆盖』」，属于原则 12 允许的显式确认，而非原则 11 禁止的「绕过校验捷径」。但 `confirmed` 是裸 `bool` 且 `WriteIntent.force` 的注释写「跳过 D2；**必须**搭配 `dangerous` 与二次确认」，实现（`:596`）却是 `dangerous || force` 任一即可，二者不一致；`AGENTS.md §5` 里 `IxBatchDecision` 的「类型上强制确认」范式没有在磁盘层复用。**是否判定为违反原则 11/12，取决于产品对 `force` 的定位**，故不并入 B2-C-06 的确证部分，标待议。
- **违反的原则编号/文档原话**：原则 **11**「防线没有开关」、**12**「确认在类型上表达，不靠调用方自觉」；`disk_types.dart:366` 原话「**必须**搭配 `dangerous` 与二次确认」。
- **证据**：`disk_cache.dart:596` 的 `||` 条件；`disk_types.dart:366-370` 字段注释；`test/base/cache_consistency_test.dart:484-505` 只测 `force` 未确认被拒与已确认放行，未测「`force` 不带 `dangerous`」这一组合。

### B2-C-17 · `DiskModule` 缺省内存实现是否构成「静默降级」（P1，待议）

- **文件:行号**：`lib/base/disk/disk_bridge.dart:70-82`（`kv ?? InMemoryKv()` 等 7 项缺省）、`lib/base/base_bootstrap.dart:22-39`（失败退回内存并回传 `storageError`）、`test/base/base_bootstrap_test.dart:29-43`。
- **问题描述**：`base_bootstrap.dart` 的降级路径「退回内存实现 + 错误原样回传」有触发条件、有观测（`storageError`）、有测试，符合原则 21 与 15；但 `DiskModule` 构造函数**本身**默认全内存（`disk_bridge.dart:73-79`），任何绕过 `baseLayerModulesOnPlatform` 的装配（例如测试或未来的组合根）都会静默丢掉全部持久化能力且无任何告警。`DiskModule.onRegister`（`:120-159`）不检查 `kv.runtimeType`，诊断里只记 `runtimeType` 字符串（`data` 字段），不构成「告警」。是否把它判为「防线可关」/「静默降级」取决于「组合根是唯一装配入口」这一前提能否由门禁保证——目前 `layer_audit.py` 不保证，故标待议。
- **违反的原则编号/文档原话**：原则 **21**「降级路径必须有触发条件、有观测、有退出条件」、**15**「静默降级是最严重的缺陷」；`AGENTS.md §5`「**平台存储失败退回内存但大声上报**（不允许静默丢失登录态）」。
- **证据**：`disk_bridge.dart:73-79` 默认值；`base_bootstrap_test.dart` 两条路径断言；`grep -rn "new DiskModule\|DiskModule(" lib` 只有 `platform_io_impl.dart:545` 与装配根。

### B2-C-18 · 「并发上限」在磁盘层是「串行化」还是「无界排队」（P1，待议）

- **文件:行号**：`lib/base/disk/disk_cache.dart:95-125`（`_KeyedMutex`）、`disk_draft.dart:110-135`（`_ordered`）、`test/base/chaos_test.dart:309-334`（500 路并发）。
- **问题描述**：两处互斥都是「每键一条 Future 链、无队列长度上限、无超时、无取消」，`chaos_test.dart` 用 500 路并发证明「不串味」但没有断言排队有界或过期回调丢弃。原则 29 要求「并发数」有上限，原则 22 要求「过期的回调必须被丢弃」；串行化把并发压成 1，是否即视为满足「并发上限」、以及排队中的旧请求是否应被丢弃（例如用户在编辑框连打 500 次），语义上需要产品定义。故标待议，不并入 B2-C-11。
- **违反的原则编号/文档原话**：原则 **29**「所有资源有上限：内存、磁盘、**并发数**、重试次数」、**22**「每个异步结果都要校验它是否仍然有效；**过期的回调必须被丢弃**」、**27**「并发假设写进注释；没写出来的假设等于没有假设」（`_KeyedMutex` 注释只写了「为什么读也要进来」，未写队列上界与取消假设）。
- **证据**：`_KeyedMutex._tails` 与 `_ordered._operations` 均为无上限 `Map`；`chaos_test.dart:319` 直接 `Future.wait` 500 个写。

### B2-C-19 · 「D10」编号越界：`WriteOutcome.threeWay` 注释称 D10，但规范只定义 D1–D9（P2，待议）

- **文件:行号**：`lib/kernel/contract/disk_types.dart:455`（`/// 冲突三方内容（D10：冲突必须可解释）`）、`lib/base/disk/disk_cache.dart:847`（`/// D10：组装冲突三方信息`）、`test/base/durability_test.dart:2`（标题「D8 / D9 / D10 三方信息」）；对照 `AGENTS.md:62`（只列 D1–D9）、`docs/ARCHITECTURE.md:123`（「D1–D7」）、`disk_cache.dart:1`（「七道防线 D1–D7」）。
- **问题描述**：D10 在源码与测试里被当作既有防线编号使用，但 `AGENTS.md` / `ARCHITECTURE.md` 的防线清单止于 D9；文件头表格止于 D7，D8/D9 在别的文件，D10 无表格、无规范条目。若「七道防线」是契约，D8–D10 属于「附加能力」还是「防线」需要统一编号口径；也可能只是文档滞后（同 B2-C-01）。因不确证是遗漏还是有意扩展，标待议。
- **违反的原则编号/文档原话**：原则 **57**「文档引用的符号必须真实存在；改名时文档一并改」、**54**「注释解释为什么」；`AGENTS.md:62`「**缓存一致性七道防线**…D8 = Write Journal；D9 = 草稿先落盘」。
- **证据**：`grep -rn "D10" lib test docs` 命中清单；三份文档均无 D10 定义。

### B2-C-20 · `AGENTS.md:62` 的「disk_cache.dart，1,016 行」与实际 1,030 行不符（P2，待议）

- **文件:行号**：`AGENTS.md:62`；`lib/base/disk/disk_cache.dart`（`wc -l` = 1030）、`docs/ARCHITECTURE.md:4`（「引用具体文件名或数字的标准不属于本文，见 AGENTS.md」）。
- **问题描述**：`AGENTS.md` 把行数写进「关键设计」条目，作为定位锚点；D1 修复（+14 行）后未同步。`QUALITY_STANDARD.md:4` 明说「引用具体文件名或数字的标准**不属于本文**，见 AGENTS.md 与 docs/ARCHITECTURE.md」，`AGENTS.md` 因此承担数字真相职责却失准。是否按原则 45「版本号只有一个真相」类推为违规、还是仅视为无关紧要的注释漂移，待议（金额/行数不是版本，故不确证）。
- **违反的原则编号/文档原话**：原则 **57**「文档引用的符号必须真实存在；改名时文档一并改，否则文档在撒谎」、**45**「版本号只有一个真相；任何两处不一致都是谎报」（类推，待议）；`QUALITY_STANDARD.md:4` 原话。
- **证据**：`wc -l lib/base/disk/disk_cache.dart` = 1030；`git show eaadd65 -- lib/base/disk/disk_cache.dart` 增 24 删 10（净 +14，1016 → 1030），`AGENTS.md` 未随提交改动。

---

## 覆盖文件清单（全部 `file_read` 完整读；无 `rg` 代替阅读）

**`lib/base/disk/` 12/12**：`app_dirs.dart`(171) · `app_dirs_fs_io.dart`(87) · `disk_bridge.dart`(160) · `disk_cache.dart`(1030，分 3 段读完) · `disk_draft.dart`(241) · `disk_journal.dart`(335) · `disk_store.dart`(7) · `disk_types.dart`(7) · `og_l_storage.dart`(179) · `og_l_storage_saf_io.dart`(118) · `platform_io.dart`(12) · `platform_io_impl.dart`(564，含尾部补读 535-564)。

**契约 2/2**：`lib/kernel/contract/disk_store.dart`(191) · `lib/kernel/contract/disk_types.dart`(534)。

**`test/base/` 全部 12 个测试文件（磁盘相关 + 目录内其余全部读完以核「旧 D1 断言」与离线纪律）**：`cache_consistency_test.dart`(652，分 2 段) · `durability_test.dart`(367) · `chaos_test.dart`(379) · `platform_io_test.dart`(219) · `base_bootstrap_test.dart`(50) · `app_dirs_category_test.dart`(100) · `app_dirs_tier_test.dart`(48) · `net_contract_test.dart` · `net_dns_test.dart` · `net_test.dart` · `net_transport_reconnect_test.dart` · `range_download_test.dart`(102)。

**规范 / 文档**：`docs/QUALITY_STANDARD.md`(93) · `docs/ARCHITECTURE.md`(149) · `AGENTS.md`(91) · `docs/AUDIT_PLAN.md` · `docs/audit_206.md` · `docs/audit_submit_download.md` · `docs/5layer-audit-todo.md` · `docs/audit_b2_a.md` · `docs/audit_b2_b.md`（同类批次文件，交叉参照）。

**CI 门禁 3/3**：`tool/layer_audit.py`(106) · `tool/motion_audit.py`(109) · `tool/perf_audit.py`(195)，并实跑 `--fatal`。

**辅助取证（片段阅读）**：`lib/kernel/diagnostics.dart` · `lib/kernel/contract/{module,download_engine,storage_export,net_types}.dart` · `lib/base/base_bootstrap.dart` · `lib/domain/domain_bridge.dart` · `lib/domain/gh/gh_api.dart` · `lib/surface/surface_bridge.dart` · `test/domain/gh_absent_test.dart` · `git log/show`（`eaadd65` D1 变更、`c142b45` 206 修复、`e4775c2` 契约上提）。

---

## 该层整体规范符合度评价（视角 C）

**结论：结构纪律优秀，契约一致性中等偏低 —— 约 6.5/10，属「代码比文档可靠、实现比契约新」的典型。**

| 维度 | 评价 | 依据 |
| --- | --- | --- |
| 分层与向下依赖 | **良好** | `lib/base/disk/` 12 文件全无向上依赖；相对 import 只指向 `kernel/` 与同目录；`layer_audit.py --fatal` 违规 0。但 `domain`/`surface` 仍直接取 `RepositoryCache` 具体类型（B2-C-02），例外靠 `KNOWN`/`ALLOW` 长期豁免，原则 2/3/5 未收口。 |
| 契约上提 | **形式彻底、实质未完** | 两个 7 行转发导出无残留符号、无重复定义，domain 已普遍改走 `kernel/contract/disk_*.dart`；但一致性引擎本身未上提，且转发文件与上提后契约的文件头层级标签错乱（B2-C-03）。 |
| 文件头 / 命名 | **部分合规** | 12/12 有 `library;`，10/12 有 `/// L1 底座级 · …`；`OgL*` 前缀大体遵守（`AppDirsFs`/`IoDiskKv`/`RepositoryCache`/`CacheKey` 等例外未加 `OgL`，但属既有命名体系，未见门禁强制）；`*_io.dart`/`*_web.dart` 配对约定在磁盘层实际不成立且文档自相矛盾（B2-C-13）。 |
| 「数据无价」「防线没有开关」 | **不达标（P0）** | `recordJournal: false`、`force`+裸 `confirmed`、未绑定日志静默跳过、删除不入日志、裸写旁路（B2-C-06/07）——与 `AGENTS.md`「**无绕过开关**」正面冲突；确认未在类型上表达，原则 11/12/13/14 均有确证缺口。 |
| 「不静默降级」「失败必留痕」 | **主体达标、边角失守** | `WriteOutcome` 类型化失败、`_fail` 先记账再返回、`UnavailableCacheRemote` 抛而非静默成功、`base_bootstrap` 回传 `storageError`，设计正确；但坏数据 `fromJson` 静默删除不记诊断、`_saveIndex`/SAF 失败仅 `debugPrint`、`debug` 级前序失败默认不输出（B2-C-10/17）。 |
| 「用类型表达失败」「过期回调丢弃」「并发上限」 | **类型达标、生命周期未验** | `WriteOutcome` / `WriteConflict` / `ConflictAction` 是完整契约；但 `verificationFailed` 成永不产生的死枚举（B2-C-04），互斥队列无上界/无取消、无过期回调断言（B2-C-11/18）。 |
| D1–D9 注释-实现一致 | **不合格** | D1 新语义只落在内联注释与测试，文件头表格/AGENTS/ARCHITECTURE 未同步（B2-C-01）；D5 表格与契约枚举仍描述旧回读失败语义（B2-C-04）；`docs/CONSISTENCY.md` 根本不存在（B2-C-05）；D10 编号越界（B2-C-19）。**「注释与实现逐条一致」这一审计项答案是：否。** |
| 测试覆盖 | **中上，但关键新语义缺测** | 七道防线、D8、D9、D10、原子写、chaos 注入均有**离线**断言（原则 49/50/51 满足），且**没有测试仍断言旧 D1 行为**、新增 D1 语义有测试；但空串基线归一化、D2′、删除路径、`maxAttempts`、`toIntent` 字段丢失、JSON 往返、206 回读确认修复**零测试**（B2-C-08/10/14）。 |
| CI 门禁 | **有明显盲区** | `motion_audit` / `perf_audit` 只扫 `lib/surface/`，对该层零覆盖；`layer_audit` 不查 `export`、`ALLOW` 整文件跳过、`KNOWN` 白名单免检且无归零；语义一致性全靠人读（B2-C-09），与本次 15 条确证互相印证。 |
| `CacheKey`/`CacheScope`/`WriteIntent`/`WriteOutcome` | **不可变性成立，序列化契约缺失** | 全 `const` + `final`，`encode/decode` 往返有 fuzzy 测试（300 轮）且含 `|` 路径无损；但四类**均无 `toJson`/`fromJson`**、无 `@immutable`、`CacheEntry` 只有 `toJson` 没有 `fromJson`、`WriteIntent.rebase` 不可序列化导致 journal 重放丢 `force`/`rebase`（B2-C-10）。 |

**优先修复建议（按本视角）**：P0 先收 B2-C-06（把 `recordJournal` / `confirmed` 收进类型化凭证、未绑定日志即拒绝写入），随后 P1 同步 D1/D5 文档与死枚举（B2-C-01/04/05）、补 206 与删除/空串基线的离线测试（B2-C-08/14）、给 `WriteIntent`/`WriteOutcome` 补齐（或显式声明「不序列化」的）契约与 `toIntent` 字段对齐（B2-C-10），再处理上提收口与门禁盲区（B2-C-02/09）。

**统计**：确证 15 条（P0 1 / P1 10 / P2 4）、待议 5 条（P1 3 / P2 2）。全程未修改 `lib/`、`test/`、`docs/ARCHITECTURE.md`。
