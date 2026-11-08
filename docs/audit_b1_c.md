# 第 1 批 · 视角 C（契约与规范一致性）· 网络传输层审计

- 目标：`/root/OhGithubLost`，main 分支 `dfd867f`（工作区 HEAD 与之一致）
- 范围：`lib/base/net/` 全部 12 文件 + `lib/kernel/contract/net_types.dart` + `test/base/` 网络相关测试
  + `docs/NETWORK.md` + `docs/ARCHITECTURE.md`
- 裁决依据：`docs/QUALITY_STANDARD.md`（59 条原则，下称「原则 N」）· `AGENTS.md` · 两份文档原话
- 纪律：只审不改；**未修改任何 `lib/` 与 `docs/NETWORK.md`**；范围文件全部 `file_read` 完整读取
  （`net_dns.dart` 1,069 行分两段读完）；下文 `grep` 仅用于**核实行号与符号存在性**，
  不代替阅读
- 记录方式：发现一条即刻追加，不攒批；不确定的标「待议」

---

## B1-C-01 · 文档承诺的「主机冷却」在代码中根本不存在

- **文件:行号 / 文档章节**：`docs/NETWORK.md:24`（传输层链路说明）、
  `docs/ARCHITECTURE.md:55`（base 层职责表）；对照 `lib/base/net/net_transport.dart:86-189`
  （`ResilientTransport.send` 全文）、`lib/base/net/io_net_transport.dart:60-135`（`HttpClient` 策略）
- **问题描述**：两份文档都把 `ResilientTransport` 的职责写成
  「重试 / **主机冷却** / DoH 回落」。全库（含 `lib/base/net/` 12 文件）不存在任何
  冷却/惩罚/失败主机记账逻辑：`send` 只有 `triedMirrors`（本次请求内跳过去重，
  `:92`、`:99`），请求结束即丢弃；`advanceHop`（`:96-110`）在镜像用尽后**立即无条件回落直连**，
  没有时间窗、没有失败计数、没有半开状态。`_selfTestReport`（`io_net_transport.dart:320-331`）
  只清 DNS 缓存，不涉及主机惩罚。同时「DoH 回落」也不属于 `ResilientTransport`：
  DoH→明文 UDP 的回落发生在 `DnsService._attemptServer`（`net_dns.dart:934-970`），
  是 DNS 层能力，文档把两层能力挂在了同一个类上。
- **违反的原则编号/文档原话**：原则 **57**「文档引用的符号必须真实存在；改名时文档一并改，
  否则文档在撒谎」；原则 **54**「注释解释为什么；"是什么"由代码自证」；
  原则 **59**「新增能力先问归属：属于哪一层、经哪个桥、由哪个契约表达」。
  文档原话（NETWORK.md:24）：「[`ResilientTransport`]（重试 / 主机冷却 / DoH 回落）」。
- **P1** · **确证**（附证据）：`grep -rn -E '主机冷却|cooldown|Cooldown|冷却' lib/` 返回空；
  文档两处命中（NETWORK.md:24、ARCHITECTURE.md:55）；`ResilientTransport` 的
  `send` 完整代码中唯一的集合是 `triedMirrors`，无任何跨请求状态；`DnsService` 中
  才有 `OGL-DNS-101/103` 回落日志。结论：文档描述的是一个**从未实现**的能力。
- **用户可见后果**：审阅者/运维按文档以为坏主机会被临时隔离，实际每次请求都会重新撞一遍
  故障主机，只靠 `maxAttempts` 与退避兜底；排障时按「冷却」假设排查会走错方向。

---

## B1-C-02 · 加速范围已从 4 类扩到 9 类，`docs/NETWORK.md` 仍写「只有这 4 类」

- **文件:行号 / 文档章节**：`docs/NETWORK.md:33-50`（§二「加速适用范围」表格与
  「枚举定义…（**只有这 4 类**）」）；对照 `lib/surface/util/accel.dart:104-186`
  （`OgLAccelScope` 枚举 9 个值）、`:189-203`（`kOgLAccelAllScopeIds` 9 项，
  注释明写「新增的 5 类」）
- **问题描述**：文档 §二的表格只列 `releaseAsset` / `actionArtifact` / `repoFile` /
  `readmeImage` 四类，并加粗断言「只有这 4 类」，且称「默认**全开**」。
  当前枚举实际为 9 类，新增 `gistFile` / `repoArchive` / `actionLog` /
  `avatarImage` / `readmeExternalImage`；`kOgLAccelDefaultScopeIds`
  （`accel.dart:198-203`）只含既有 4 类，其余 5 类**默认关**。于是文档同时错在
  「类别数量」与「默认全开」两处：新 5 类默认关，且 `actionLog`/`avatarImage`
  在枚举注释里明写「本版**不接入**」。文档的「代码位置」列也漏了 `gist_detail_page.dart`
  / `readme_view.dart` 等新调用点。§四「私有仓库加速」的风险描述同样没有覆盖
  `readmeExternalImage`（外链图床会暴露「你在读哪个仓库」，枚举注释专门写了）。
- **违反的原则编号/文档原话**：原则 **57**（文档符号/事实必须与实现一致）、
  原则 **45**（口径只有一处真相）、原则 **56**「文档只收持续有效的手册」。
  文档原话（NETWORK.md:45）：「枚举定义：[`OgLAccelScope`]（**只有这 4 类**）」、
  （:46）「默认**全开**（与历史行为一致）」；NETWORK.md 开头自述：
  「维护要求：本文所引用的每个符号必须与代码一致且**真实存在**；符号改名或行为变更时
  须一并更新，否则文档将失去准确性」。
- **P1** · **确证**（附证据）：`accel.dart:105-151` 枚举 9 值；
  `:189-196` `kOgLAccelAllScopeIds` 9 项；`:198-203` 默认 4 项；
  `git log --oneline -- lib/surface/util/accel.dart` 显示 `89d83e7 release: v10.4.0
  —— …加速细化…` 引入扩展，而 NETWORK.md 未随之更新（同批未改动）。
- **用户可见后果**：用户按文档以为所有加速范围默认全开/只有 4 类，实际设置页会出现
  9 个开关且 5 个默认关；`readmeExternalImage` 这类**有泄露风险**的新范围完全不在
  文档「知情接受」流程里，用户无从得知其存在与风险。

---

## B1-C-03 · §一出口清单漏记新增官方 API 端点与 Gist / 归档 / 图床出口

- **文件:行号 / 文档章节**：`docs/NETWORK.md:9-19`（§一「出口清单」）、`:33-43`（§二表格）；
  对照 `lib/domain/gh/gh_api.dart:1323-1345`（`/notifications` 官方动态）、
  `lib/surface/pages/search_page.dart:94-97`、`:158-160`（`/notifications` + README 切片）、
  `lib/surface/util/accel.dart:120-151`（`gistFile` / `repoArchive` / `readmeExternalImage`）
- **问题描述**：文档自称「回答**应用向哪些主机发起请求**、每类 GitHub 资源经何种途径获取」，
  但 §一表格仍停在 v6.4.3 时代的 6 行：`api.github.com` / `raw.githubusercontent.com` /
  `github.com` / `objects|release-assets.githubusercontent.com` / DoH / 用户通道。
  新增的官方 API 能力（`/notifications` 通知流、发现页 README 切片 / 推荐分页）
  与新增资源族（Gist raw 附件、仓库归档 ZIP→`codeload`、README 第三方图床）
  均未进表；`readmeExternalImage` 更是让请求**离开 github 主机**到任意外部图床，
  属于出口清单的核心对象，完全缺登记。文档 §五的 CORS 结论也只覆盖旧 4 类，
  没有新增范围在 Web 端的实测结论。
- **违反的原则编号/文档原话**：原则 **57**、原则 **52**「端点语义必须实测：空、无、
  未启用是三种不同的"没有"，混为一谈必出错」、原则 **59**（新增能力三问）。
  文档原话（NETWORK.md:3-4）：「本文回答三个问题：**应用向哪些主机发起请求**、
  **每类 GitHub 资源经何种途径获取**、**浏览器（web）端哪些途径可用**」；
  NETWORK.md:5「本文所引用的每个符号必须与代码一致且真实存在」。
- **P1** · **确证**（附证据）：`grep -n '官方' lib/domain/gh/gh_api.dart` → `:1328`
  「用户要求的"动态走官方 API，不用自己实现信息获取"」；`search_page.dart:3`、
  `:97` 调用 `api.notifications`；`accel.dart:131-151` 三个新增范围及其外部主机说明；
  `docs/NETWORK.md` 全文无 `notifications` / `Gist` / `归档` / `图床` 字样。
- **备注**：外部图床出口与原则 **43**「网络能力没有后门；加速通道由用户显式开启」
  的边界相关，但本视角只登记**文档与实现不一致**，不越界裁决安全实现。

---

## B1-C-04 · 契约上提不彻底：`kernel/contract/net_types.dart` 头注释仍是「L1 底座级」，
## 且 11 处生产/测试引用仍走 `base/net/net_types.dart` 转发门面

- **文件:行号**：`lib/kernel/contract/net_types.dart:1`（文件头）、
  `lib/base/net/net_types.dart:1-7`（7 行转发导出）；
  对照 `lib/base/net/io_net_transport.dart:29`、`:net_bridge.dart:13`、
  `:net_retry.dart:12`、`:net_transport.dart:25`（4 处 base 内部仍 import 转发门面），
  `test/base/net_test.dart:12`、`test/base/net_transport_reconnect_test.dart:19`、
  `test/base/cache_consistency_test.dart:12`、`test/base/durability_test.dart:15`、
  `test/domain/gh_absent_test.dart:18`、`test/domain/gh_client_test.dart:20`、
  `test/screenshots/screenshot_matrix_test.dart:32`（7 处测试仍 import 转发门面），
  `lib/domain/gh/gh_api.dart:19`、`gh_client.dart:19`、`repo_file_service.dart:50`
  （3 处 domain 正确直连 contract）
- **问题描述**：`net_types.dart`（7 行转发）的注释声称「已上提到**启动层契约**」
  「逻辑层（domain）请直接依赖 `kernel/contract/net_types.dart`」，domain 三处确实照做了；
  但被上提到 kernel 的**目标文件**自身仍写着 `/// L1 底座级 · 网络连接…`，
  与同目录 `download_engine.dart:1`（`/// L0 启动层契约 · **下载引擎**`）、
  `storage_export.dart:1`（`/// L0 启动层契约`）口径相反，层级注释自相矛盾。
  同时 base 内部 4 个文件与 7 个测试仍经由 `base/net/net_types.dart` 取契约，
  形成「同一契约两个入口」：转发门面是 L1 产物，却被 L2/L3 的测试和 base 本体长期依赖；
  一旦转发门面被删（它自称是过渡），这 11 处会一起断。注释称「既有引用无需改动」，
  等于把例外**永久化**而没有清单。
- **违反的原则编号/文档原话**：原则 **5**「契约先于实现；共享类型上提到最底层，
  而不是让上层互相看见」、原则 **3**「例外必须显式登记、可枚举、可归零；没有清单的
  例外就是漏洞」、原则 **6**「命名即结构：文件名必须能让审计脚本识别其层级角色」、
  原则 **57**（注释/文档与实现一致）。`AGENTS.md` §3 原话：「**文件头注释是硬惯例**：
  `/// L1 底座级 · …` 层级前缀 + `library;` + 中文设计说明」；
  `AGENTS.md` §1 原话：「共享类型上提到最底层」。
- **P2** · **确证**（附证据）：`kernel/contract/net_types.dart:1` 逐字为
  `/// L1 底座级 · 网络连接：请求 / 响应 / 错误 / 观测 的基础类型。`；
  `download_engine.dart:1` 为 `/// L0 启动层契约 · **下载引擎**…`；
  `grep -rn "base/net/net_types.dart\|'net_types.dart'" lib/ test/` 得到 4+7 处；
  `grep -rn "kernel/contract/net_types.dart" lib/` 仅 3 处 domain + 1 处 export。
- **补充**：`layer_audit.py:64-70` 对 `tlay == 'kernel'` 直接放行、对 `export` 语句
  **完全不扫描**（`IMPORT_RE` 只匹配 `^\s*import`），因此这类「转发门面残留」
  与「层级头注释错标」在门禁里都是盲区（见 B1-C-12）。

---
## B1-C-05 · `library;` 与文件头层级注释口径混乱：range_download 两文件标「L1 硬件层」，
## 5 个 kernel 契约文件里 3 个标「L1 底座级」、1 个无任何层级前缀

- **文件:行号**：`lib/base/net/range_download.dart:1`、
  `lib/base/net/range_download_io.dart:1`（均 `/// L1 硬件层 · …`）；
  `lib/kernel/contract/net_types.dart:1`、`:disk_store.dart:1`、`:disk_types.dart:1`
  （均 `/// L1 底座级 · …`，却位于 `kernel/contract/` L0）；
  `lib/kernel/contract/download_engine.dart:1`、`:storage_export.dart:1`
  （`/// L0 启动层契约 · …`）；`lib/kernel/contract/module.dart:1`
  （`/// OGL 内核契约：…`，**无 `L0`/`L1` 层级前缀**）；
  `lib/base/net/net_types.dart:1`（7 行转发门面，**无任何层级前缀**，只有「已上提到…」）
- **问题描述**：`AGENTS.md` §3 把文件头定为「**硬惯例**：`/// L1 底座级 · …`
  层级前缀 + `library;` + 中文设计说明」。实际 `base/net/` 12 文件里有 10 个写
  「L1 底座级」、2 个写「L1 硬件层」（`range_download*`），两种叫法指同一层；
  kernel 契约目录里 3 个文件反而自称「L1 底座级」，`module.dart` 无前缀。
  也就是说**层级前缀既不能标识层（kernel 文件写 L1），也不能标识子角色
  （同层两种称谓）**。好消息是 `library;` 本身：base/net 12/12 齐全、
  kernel/contract 6/6 齐全，这一条达标。
- **违反的原则编号/文档原话**：原则 **6**「命名即结构：文件名必须能让审计脚本识别
  其层级角色；无法识别的名字不得存在」、原则 **54**（注释应与代码自证一致）、
  原则 **57**。`AGENTS.md` §3 原话：「**文件头注释是硬惯例**：
  `/// L1 底座级 · …` 层级前缀 + `library;` + 中文设计说明（含表格/ASCII 图）」；
  `AGENTS.md` §1 层级表原话 `kernel L0 | lib/kernel/ | 契约（contract/）…`。
- **P2** · **确证**（附证据）：逐个 `head -2 lib/kernel/contract/*.dart` 与
  `head -3 lib/base/net/*.dart` 输出如上；`grep -c '^library;'` 对
  `base/net/` 12 文件与 `kernel/contract/` 6 文件均为 1。
  另注：`layer_audit.py` 的 `IMPORT_RE` 只解析 `import`，**不校验文件头注释**，
  因此这类口径漂移门禁零覆盖（见 B1-C-12）。
- **待议**：`module.dart:1` 的「OGL 内核契约」是历史遗留还是有意例外，仓库无
  「例外清单」可查（原则 3 要求例外可枚举），标「待议」由主会话裁定。

---

## B1-C-06 · 平台实现命名 `*_io.dart` / `*_web.dart` 配对纪律在 base/net 全面失守：
## 4 个跨层入口无条件（非条件 import）直连 `dart:io` 实现，全库 0 个 `*_web.dart`

- **文件:行号**：`lib/base/net/net_self_test.dart:10`
  （`import 'net_self_test_impl_io.dart';` —— 无条件）、
  `lib/base/net/range_download.dart:27`
  （`export 'range_download_io.dart' show OgLRangeDownloader;` —— 无条件）、
  `lib/base/net/net_dns.dart:29`（`import 'net_dns_platform_io.dart';` —— 无条件）、
  `lib/base/net/net_bridge.dart:8`（`import 'io_net_transport.dart';` —— 无条件，
  且文件名是 `io_net_transport.dart` **不是** `net_transport_io.dart`）；
  对照 `lib/base/net/net_self_test.dart:5-7` 自述「本文件只保留**与平台无关**的部分」、
  `range_download.dart:18-21` 自述「本文件只保留**跨平台**的纯逻辑」
- **问题描述**：`AGENTS.md` §1 与 `docs/ARCHITECTURE.md` §5/§6.2 都规定平台实现用
  `*_io.dart` / `*_web.dart` **条件 import 编译期解析**（`ARCHITECTURE.md:6.2` 原话：
  「平台层使用 `*_io.dart`（原生）与 `*_web.dart`（浏览器）的条件 import 约定…
  此约定由 `layer_audit.py` 的命名规则强制」）。实际：`net_self_test.dart` 与
  `range_download.dart` 用**普通 import/export** 直接绑死 `_io` 实现；
  自称「跨平台纯逻辑」的文件因此**在 Web 上根本无法编译**（`dart:io` 传递依赖）。
  全库只有 `lib/domain/gh/gh_oauth.dart:22` 一处条件 import，base/net 一处没有；
  全库 0 个 `*_web.dart`。`docs/NETWORK.md` §五却用整节表格声称「web（浏览器）端的
  限制 —— **均经实测**」，`docs/ARCHITECTURE.md:6.3` 声称「Web 端…落地后已并回主线，
  但 web 专属实现仍以 `_web.dart` 命名隔离」——与 `find lib/ -name '*_web.dart'` 为空矛盾。
  命名上还有 `io_net_transport.dart`（`io_` 前缀）与 `net_dns_platform_io.dart` /
  `net_self_test_impl_io.dart` / `range_download_io.dart`（`_io` 后缀）两种风格并存。
- **违反的原则编号/文档原话**：原则 **4**「平台差异在唯一的位置裁决；其余代码面对
  同一抽象，不感知平台」、原则 **6**（命名即结构）、原则 **3**（例外须登记）、
  原则 **57**（文档符号/事实必须真实存在）、原则 **52**（端点语义须实测）。
  `AGENTS.md` §1 原话：「平台实现 `*_io.dart` / `*_web.dart`（条件 import，编译期解析）」；
  `ARCHITECTURE.md:5` 表格原话：「`base/net/net_dns_platform_io.dart`
  （web 分支已随 Web 支持一并移除，现无 `*_web.dart`；重新引入时按此命名）」——
  该表述与 §6.3「web 专属实现仍以 `_web.dart` 命名隔离」自相矛盾。
- **P1** · **确证**（附证据）：`grep -n "^import\|^export" lib/base/net/*.dart`
  显示上述 4 条均为无条件指令；`find lib/ -name '*_web.dart'` 输出为空；
  `grep -rn "if (dart.library" lib/` 仅 `gh_oauth.dart:22` 一处；
  `net_self_test_impl_io.dart:10` / `range_download_io.dart:9` /
  `net_dns_platform_io.dart:13` 均为 `import 'dart:io';`。
- **用户可见后果**：文档声称 Web 端可用且「均经实测」，但传输层根本无 Web 实现；
  任何按 `*_web.dart` 约定新增 Web 传输的改动都会撞上 4 处硬编码 `_io` 入口。
  （**待议**：Web 产物由 `.github/workflows/web.yml` 独立发布，是否通过
  平台注入器/构建期替换绕开这 4 处，本视角未读 `app/wasm/` 产物，不排除；
  故「Web 一定不可编译」这一推论标待议，**命名/条件 import 纪律失守本身确证**。）

---

## B1-C-07 · 「不静默降级 / 失败必留痕」：`range_download_io.probe` 吞掉全部异常，
## 把「探测失败」与「服务端不支持 Range」混为同一个 `supportsRange: false`

- **文件:行号**：`lib/base/net/range_download_io.dart:62-69`（`catch (error)` 内层
  `catch (inner)` 两个变量**均未使用**，直接 `return const DownloadProbe(supportsRange: false);`）、
  `:87-89`（非 206 一律 `supportsRange: false`，不带原因）；
  对照 `lib/kernel/contract/download_engine.dart:28-33`（`DownloadProbe` 有 `statusCode`
  「诊断用」字段）、`:40`「**失败必须清理**：不允许把半成品当成成功」
- **问题描述**：`probe` 的 catch 是典型的「兜底一切」：任何异常（超时、DNS、TLS、
  SocketException、`HttpClient` 抛错、甚至编程错误）都被翻译成
  `DownloadProbe(supportsRange: false, statusCode: null)`，与「服务端明确回了
  `Accept-Ranges: none` / 405」在类型上**完全无法区分**，且无任何日志、诊断码、
  异常原因保留。`catch (error)` / `catch (inner)` 两个绑定变量未使用正是证据。
  上层 `ix_download.dart:862` 据此回退单连接下载——即一次网络故障被静默降级成
  「服务端不支持」，用户看到的是「用了慢下载」而不是「探测失败」。
  对照同层 `net_dns.dart` 的回退（`:872-881`）会记 `OGL-DNS-101` warn 日志并
  在 `DnsProbe` 里标 `fallback`，说明项目内已有正确范式，此处未遵循。
- **违反的原则编号/文档原话**：原则 **15**「静默降级是最严重的缺陷；失败必须以
  用户可感知的方式留痕」、原则 **16**「不吞异常。捕获后若不重新抛出，必须转化为
  明确的结果或告警」、原则 **18**「捕获范围必须精确到能处理的异常；"兜底一切"的
  catch 是 bug 的藏身处」、原则 **19**「编程错误不降级、不重试、不掩盖」、
  原则 **17**「用类型表达失败」、原则 **52**「空、无、未启用是三种不同的"没有"，
  混为一谈必出错」、原则 **21**「降级路径必须有触发条件、有观测、有退出条件」。
- **P1** · **确证**（附证据）：`range_download_io.dart:62-68` 逐字为两重
  `catch` + `return const DownloadProbe(supportsRange: false);`；
  全文件无 `KernelDiagnostics` / `log` / `code:` 引用；
  `DownloadProbe` 契约虽提供 `statusCode`，catch 路径填的是 `null`。
  `range_download.dart:15-16` 自己的注释还承诺「不支持 Range（或**探测失败**）时抛
  [DownloadUnsupported]」——实现既不抛、也不抛得出原因，注释与实现矛盾（原则 54/57）。
- **备注**：`probe` 注释 `:63` 只解释「HEAD 被禁（405 等）时复核」，
  但 `catch (error)` 实际吞的是 `Object` 全部类型，注释与捕获范围不符（原则 18）。

---

## B1-C-08 · 新增的「206 分段 / Content-Range 区间对齐」与「跨主机重定向剥凭证」
## 均无对应离线测试断言；`test/base/` 网络测试只覆盖纯函数与连接策略

- **文件:行号**：`lib/base/net/range_download_io.dart:196-218`（206 状态码 +
  `_rangeOf` 区间对齐）、`:268-285`（`_rangeOf` 解析）、`:72-96`（`_probeByRange` 206 探测）；
  `lib/base/net/io_net_transport.dart:160-172`（`hasCredential` 分支）、
  `:232-277`（`_sendWithGuardedRedirect` 同源/跨主机判定、302/303 降级 GET、
  `_kUnset` 哨兵）；对照 `test/base/range_download_test.dart:1-102`（**只测
  `OgLChunkPlan.of` 纯函数与 `OgLRangeCancelToken`**，无一处引用 `probe`/`fetch`/
  `_rangeOf`/`OgLRangeDownloader`）、`test/base/net_transport_reconnect_test.dart:1-145`
  （只测 `connection: close` 与连续请求成功）、`test/base/net_test.dart`、`net_dns_test.dart`
- **问题描述**：本层两个**最新、最高风险**的改动完全无测试守卫：
  ① `grep -rn -E '206|partialContent|Content-Range|contentRange|_rangeOf' test/`
  全库唯一命中是 `cache_consistency_test.dart:529` 的**诊断码字符串** `OGL-CONS-206`
  （与 HTTP 206 无关），即 0 条 206/Content-Range 断言；`range_download_io.dart`
  里 `_rangeOf` 是私有静态方法、无测试可达路径，`probe`/`fetch` 也无注入式
  `HttpClient` 假实现测试。
  ② `grep -rni -E 'redirect|跨主机|剥凭证|sameOrigin' test/` 无命中——
  `_sendWithGuardedRedirect` 的同一主机跟随、跨主机不跟随、302/303 丢弃 body、
  凭证头保留/不保留，全部没有离线断言；`net_transport_reconnect_test.dart`
  起的极简 ServerSocket 本来就能发 302，却未用于重定向场景。
  ③ 顺带：`test/base/` 无「主机冷却」测试（该能力不存在，见 B1-C-01）；
  `ogLIsUsableDohEndpoint` / `ogLNormalizeDnsAddress` / `applySelection` 清缓存 /
  `_syncPolicy` 重装 connectionFactory 也都没有测试（DoH 编解码有覆盖，
  见下方覆盖清单）。
- **违反的原则编号/文档原话**：原则 **49**「测试离线可跑」与原则 **50**「用接口 +
  内存实现替代真实依赖；测试测的是契约，不是巧合」（`probe`/`fetch` 依赖真实
  `dart:io HttpClient`，无内存实现）、原则 **51**「破坏性测试与正常路径同等重要；
  混沌注入守住的防线才是真防线」、原则 **52**「端点语义必须实测」、
  原则 **11**「防线没有开关」（防线无测试守卫等于可被无声改坏）、
  原则 **53**「语义严密性靠人读」。`AGENTS.md` §1 原话「测试离线运行…
  重点测试：chaos_test.dart（破坏性混沌注入）」；`docs/AUDIT_PLAN.md` 第 1 批
  已知风险锚点原话：「重定向守卫跨主机剥凭证、206 分段响应、只重试幂等方法、
  DoH 只认 https、Range 错位区间」——这 5 项里至少 2 项零测试。
- **P1** · **确证**（附证据）：`test/base/range_download_test.dart` 全文 102 行，
  import 仅 `range_download.dart` + `flutter_test`，无 `dart:io`/`HttpClient`；
  `net_transport_reconnect_test.dart` 全文 145 行只有 2 个 test；
  `grep -rn 'parseRetryAfterHeader' test/` 无命中（契约里自称「唯一实现处」的
  `net_types.dart:210` 函数无直接测试）；`docs/audit_206.md` 与
  `docs/audit_net_data.md` 记录这两处是**已修复的 P0 缺陷**，但修复未附回归测试。
- **补充（覆盖达标项，供主会话交叉）**：`net_test.dart` 对重试分支/镜像回落/
  幂等铁律/观测计数/`copyWith` 有较完整离线断言；`net_dns_test.dart` 对
  报文编解码（含压缩指针、事务 ID、NXDOMAIN）、DoH JSON、缓存淘汰、
  竞速取先、回退 warn 有离线断言。**缺口集中在 `_io.dart` 真实实现层**。

---
## B1-C-09 · 公共契约「不可变性」名不副实：`NetRequest` / `NetResponse` 的
## `headers` 是可变 `Map` 且无拷贝，`NetRequest.timeout` 是死字段，`fromMirrorId` 从无写入方

- **文件:行号**：`lib/kernel/contract/net_types.dart:116-163`（`NetRequest` 头注释
  「传输请求（**不可变**）」、`:127` `headers = const <String, String>{}`、
  `:130` `timeout = const Duration(seconds: 30)`、`:146-159` `copyWith`）、
  `:166-205`（`NetResponse` 头注释「传输响应（**不可变**）」、`:175` `headers` 默认值、
  `:189` `fromMirrorId`）；对照 `lib/base/net/io_net_transport.dart:154-193`
  （构造 `NetResponse` 时**从不**传 `fromMirrorId`）、`lib/base/net/net_transport.dart:100`
  （`copyWith(url:)` 原样复用 `headers` 引用）
- **问题描述**：三点契约缺陷：
  ① `final Map<String, String> headers` 只保证引用不变，**不保证内容不变**；
  默认值虽是 `const {}`，但调用方可传入普通 `Map` 并在发送后修改。
  `NetRequest.copyWith`（`:154` `headers: headers ?? this.headers`）直接复用同一
  `Map` 实例，`ResilientTransport` 的镜像改写（`:100`）拿到的是**共享可变头**——
  与「不可变」注释、与 `AGENTS.md` 契约先于实现的诉求都不符。
  ② `NetRequest.timeout`（默认 30s）在全库**没有任何读取方**：
  `IoNetTransport.send` 用的是构造参数 `connectTimeout`(15s)/`receiveTimeout`(60s)
  （`io_net_transport.dart:177/184/187`），`gh_client.dart:597` 仍在认真传
  `timeout: const Duration(seconds: 30)`，值被静默忽略。这是契约里的「假开关」。
  ③ `NetResponse.fromMirrorId` 全库**无任何赋值点**（`grep -rn 'fromMirrorId:' lib/ test/`
  为空），但 `gh_client.dart:625` 与 `toString()`（`net_types.dart:203`）都读取它并
  向用户展示「经镜像 X」；因 `defaultMirrorChannels` 为空（B1-C-10），该字段永远
  为 `null`。契约暴露了一个从不会被填充的观测字段。
  ④ `parseRetryAfterHeader`（`net_types.dart:208-225`）自称「**唯一实现处**：
  传输层（异常路径）与韧性层（响应路径）共用同一份逻辑，**不允许各自复制一份**」，
  但 `lib/domain/gh/gh_client.dart:797-801` 的 `_retryAfterOf` 又实现了一份
  （只解析秒数、不解析 HTTP 日期），且**无测试**覆盖契约函数本身
  （`grep -rn 'parseRetryAfterHeader' test/` 为空）。
- **违反的原则编号/文档原话**：原则 **5**「契约先于实现」、原则 **11**「防线没有开关。
  任何"绕过校验"的捷径参数都不允许存在」（`timeout` 是形同虚设的参数）、
  原则 **54/57**（注释「不可变」/「唯一实现处」与代码不符）、原则 **28**
  「缓存键必须覆盖产生差异的全部维度」（共享可变头会让「同一请求」在不同跳
  携带不同头）、原则 **45**「版本号只有一个真相」（引申：同一语义只应有一处实现）。
  契约原话（`net_types.dart:208-209`）：「**唯一实现处**…不允许各自复制一份再慢慢漂移」。
- **P1（不可变/timeout）· P2（fromMirrorId/重复实现）** · **确证**（附证据）：
  `grep -rn 'request\.timeout' lib/` 无命中；`grep -rn 'fromMirrorId:' lib/ test/`
  无命中；`net_types.dart:134/186` 均为裸 `final Map` 且无 `@immutable`
  （对比 `range_download.dart:30` 的 `OgLByteRange` 用了 `@immutable`）；
  `gh_client.dart:797-801` 逐字为 `int.tryParse(raw ?? '')` 的独立实现。
- **用户可见后果**：调用方按契约设置 `timeout` 以为生效，实际由全局 15s/60s 决定，
  慢网络行为与文档承诺不符；镜像通道若被启用，`fromMirrorId` 恒空使
  「到底走没走通道」无法从观测数据判定（与原则 15 的「留痕」诉求相冲）。

---

## B1-C-10 · 「防线无绕过开关」类：`DnsPolicy.fallbackToSystem` 是可关闭的降级开关，
## `MirrorChannel.enabled` / `setAllEnabled(false)` 可整体停用加速通道

- **文件:行号**：`lib/base/net/net_dns.dart:620`（`this.fallbackToSystem = true`）、
  `:647`（可变字段）、`:870`（`if (!policy.fallbackToSystem) rethrow;`）；
  `lib/base/net/net_mirror.dart:14`（`this.enabled = true`）、`:31-33`
  （`apply` 遇 `!enabled` 返回 `null`）、`:91-100`（`setAllEnabled`）、
  `:102-111`（`restrictTo`）；
  `lib/domain/domain_bridge.dart:520-522` 注释「非 IO / 无镜像能力时**静默跳过**
  是可接受的：那本来就等价于"直连"」及 `:532-536` 三个开关调用
- **问题描述**：原则 11 要求「防线没有开关。任何"绕过校验"的捷径参数都不允许存在」。
  本层存在两个语义上等价的旁路：`fallbackToSystem = false` 让「自定义 DNS 失败」
  这条已有明确失败语义的路径改变行为（测试 `net_dns_test.dart:400-425` 就是在断言
  关掉后直接抛，说明它是**设计上的可选项**而非临时退路）；
  `setAllEnabled(false)`（由 `IxChannel.direct` 触发）让整条镜像/加速链路被停用，
  而 `domain_bridge.dart:520` 的注释明写「**静默跳过**是可接受的」——
  与原则 15「静默降级是最严重的缺陷」直接抵触。
  `MirrorSelector.restrictTo(null)` 更是把全部通道一次性停用（`:105`）。
- **违反的原则编号/文档原话**：原则 **11**（防线没有开关）、原则 **3**
  「例外必须显式登记、可枚举、可归零；没有清单的例外就是漏洞」、
  原则 **15**（不静默降级）、原则 **21**「降级路径必须有触发条件、有观测、
  有退出条件」。`AGENTS.md` §5 原话：「**缓存一致性七道防线…无绕过开关**」、
  「**网络**：…镜像通道全部失败回落直连」（回落是允许的，但需可见）。
- **P2** · **待议**：这两处的**语义是否属于「防线条目」**需主会话裁定——
  `fallbackToSystem` 是用户可见的 DNS 策略选项（回退时会记 `OGL-DNS-101` warn，
  满足原则 15 的留痕要求），`IxChannel.direct` 是批量任务的**用户显式选择**
  （`IxBatchDecision` 在类型上表达，符合原则 12）。因此**不判定为缺陷**，
  仅登记为「防线边界待澄清」：建议文档/注释明确「哪些是用户显式选择、
  哪些是不可关闭的防线」，否则下次审计仍会反复命中。
- **证据**：`net_dns.dart:872-881` 回退发 `OGL-DNS-101` warn；
  `net_dns_test.dart:349-372` 断言「回退必须留痕」；
  `domain_bridge.dart:529-537` 三分支均为 `decision.channel` 驱动。

---

## B1-C-11 · 「并发上限」：DNS 竞速会一次性发起全部服务器请求、分片并发数无上限校验，
## 且 `DnsService._lastVia` 是跨请求共享可变状态，竞速落败者的结果可覆写它

- **文件:行号**：`lib/base/net/net_dns.dart:914-925`
  （`_resolveCustom` 在 `raceServers && servers.length > 1` 时把**每台服务器**
  的 `_attemptServer` 一次性全部构造进 List 传给 `_race`）、`:983-1006`
  （`_race` 只 `complete` 首个成功者，**不取消其余 Future**）、
  `:706-707`（`String? _lastVia` 实例字段）、`:836`/`:861`/`:867`/`:881`/`:891`
  （各路径写 `_lastVia`，`_remember` 无请求关联标识）、`:1046-1049`
  （`DnsProbe` 在 `resolve` 返回后读 `service.lastResolvedVia`）；
  `lib/base/net/range_download_io.dart:116-135`（`Future.wait` 一次性发起
  `plan.length` 个 `_fetchPart`，`plan.length` 来自 `request.connections`）、
  `lib/kernel/contract/download_engine.dart:72`（`this.connections = 4` 无断言/夹紧）、
  `lib/base/net/io_net_transport.dart:79`（`maxConnectionsPerHost = 8` 是 HttpClient
  级别，**不覆盖** `range_download_io.dart` 自建的 `HttpClient`）
- **问题描述**：原则 29 要求「所有资源有上限：内存、磁盘、并发数、重试次数」。
  当前 `DnsService` 的竞速 fan-out 受 `policy.servers.length` 间接限制（默认 5，
  但 `DnsPolicy.servers` 是可增删的 `final List`，`add` 无上限）；
  `OgLChunkPlan.of` 虽把分片数夹到 `connections`，但 `connections` 本身在契约里
  无上限断言，也无 `maxConnectionsPerHost` 约束（`range_download_io.dart` 全文无该设置）。
  更贴本视角的是原则 22「每个异步结果都要校验它是否仍然有效；**过期的回调必须被丢弃**」：
  `_race` 的 `onError` 只做计数，成功回调只判断 `completer.isCompleted`，
  **落败的 Future 仍在后台跑**；它们若最终调用 `_remember`（当前 `_race` 路径下
  不直接调，但 `applySelection` 清缓存、`_lastVia` 是共享字段），
  则「最近一次解析由谁完成」这个**观测字段**可能被一次与当前查询无关的
  过期回调改写，`DnsProbe` 随后读到的 `via` / `fallback` 就不属于它刚做的那次解析。
  这不是推测的崩溃，而是「异步结果有效性未校验」的结构缺口。
- **违反的原则编号/文档原话**：原则 **22**（过期回调丢弃）、原则 **27**
  「并发假设写进注释；没写出来的假设等于没有假设」（`_race` 注释只写
  「取最先成功者；全部失败才抛错」，未写「未取消其余请求」这一关键假设）、
  原则 **29**（并发数上限）、原则 **42**「失败如实报错」（观测值被过期结果污染，
  等于报告了不属实的事实）。
- **P2** · **部分确证 / 部分待议**：
  - **确证**：`_race`（`:989-1003`）无任何 `cancel`/`timeout`/世代标识；
    `_lastVia` 是裸实例字段且被 5 处写入；`DnsProbe:1046` 在 `await` 之后才读；
    `range_download_io.dart` 无 `maxConnectionsPerHost`；`grep -rn '并发上限' test/`
    无命中。
  - **待议**：`_lastVia` 是否**实际**会被竞速落败者覆写，取决于
    `_attemptServer` 是否调用 `_remember`（当前实现不调，`_remember` 只在
    `resolve` 主路径）；因此「观测值错报」在**当前调用关系下未构成可复现缺陷**，
    标待议，需主会话结合 A 视角（实现正确性）交叉确认。
    「并发数无硬上限」亦标待议：默认 5 家 DNS / `connections=4` 在工程上可视为
    事实上界，原则 29 是否要求显式夹紧由主会话裁定。

---

## B1-C-12 · CI 门禁对该层存在系统性盲区：三支指定脚本全部不扫 `lib/base/net/`，
## `layer_audit.py` 不解析 `export`、不校验文件头/命名配对，且 Web 分支产物在网关注门外

- **文件:行号**：`tool/motion_audit.py:39-40`（`SURFACE = ROOT/'lib'/'surface'`）、
  `tool/perf_audit.py:33`（同上）；`tool/layer_audit.py:47`
  （`IMPORT_RE = re.compile(r"^\s*import\s+'([^']+)'", re.M)` —— **不含 `export`**）、
  `:88-101`（只按 import 目标层判方向，`tlay == 'kernel'` 直接放行）、
  `ALLOW` 3 项 / `KNOWN` 2 项（`:40-44`、`:57-60`，无 `base/net` 条目）；
  `.github/workflows/ci.yml:52/70/83/115`（门禁与 `flutter test` 清单）
- **问题描述**：用户点名的三支门禁对网络层**零覆盖**：
  ① `motion_audit.py` / `perf_audit.py` 扫描根目录写死为 `lib/surface`，
  `lib/base/net/` 12 文件一行都不会被读——本层的硬编码时长（`net_dns.dart`
  多处 `Duration(seconds: …)`、`range_download_io.dart:39` 15s、
  `net_self_test.dart:32-33` 30s/4s）、跨层 `package:flutter/foundation.dart`
  依赖（`range_download.dart:24`、`net_dns.dart` 间接）都不受约束。
  ② `layer_audit.py` 只认 `import`，因此 `base/net/net_types.dart:7`
  的 `export '../../kernel/contract/net_types.dart'`、
  `range_download.dart:27` 的 `export 'range_download_io.dart'`、
  `surface/types.dart` 的 12 条 `export` **全部不进检查**；
  转发门面残留（B1-C-04）、`*_io.dart` 无条件 export（B1-C-06）、
  文件头层级错标（B1-C-05）都无门禁。
  ③ `KNOWN` 白名单只登记 `gh_api.dart → disk_cache.dart` 与
  `gh_client.dart → net_bridge.dart` 两项，`AGENTS.md` §1 称「KNOWN 白名单恰 2 项
  待收敛」与此一致；但 `net_types.dart` 转发门面这**第三类跨层引用**没有登记，
  原则 3 要求的「例外可枚举、可归零」在脚本里没有对应项。
  ④ 本次实测 `python3 tool/layer_audit.py --fatal` → `违规：0 处 / 已知待收敛 2 处`
  退出 0，即**带着上述全部文档/命名/契约问题全绿**。
  ⑤ `flutter test --reporter expanded`（ci.yml:115）跑全量测试，但新 206/重定向
  行为无用例（B1-C-08），门禁自然也不会失败。
- **违反的原则编号/文档原话**：原则 **53**「审计脚本只守语法与结构；语义严密性
  靠人读，读的时候禁止只看 diff」（本条正是**结构也没守住**）、原则 **3**
  （例外须可枚举）、原则 **6**（命名即结构，应由脚本识别）、原则 **49/51**
  （测试门禁应覆盖破坏性路径）、原则 **57**（文档口径靠脚本强制）。
  `AGENTS.md` §2 原话：「1. **layer_audit.py --fatal**：分层 import 检查」、
  「2. **perf_audit.py --fatal**（扫 lib/surface/）」、「3. **motion_audit.py --fatal**
  （扫 lib/surface/**）」——文档已如实写明只扫 surface，属**已知范围**，
  本条重点在「对 `base/net` 无等价门禁」而非脚本违约。
- **P2** · **确证**（附证据）：三脚本源码行如上；实测 `layer_audit.py --fatal`
  输出 `文件总数：147 / 已知待收敛 2 处 / 违规：0 处`，`exit=0`；
  `grep -rn 'net_types\|base/net' tool/*.py` 无专门规则；
  `grep -rln '206\|redirect' test/` 无网络层命中。
- **补充**：这解释了为什么 B1-C-01/02/04/05/06/08 能在 CI 全绿的
  `dfd867f` 上共存——**本层缺一支契约/文档一致性门禁**，而非单次疏忽。

---

## B1-C-13 · 「端点语义须实测」：§五 CORS 结论与 §二/§六复现命令覆盖不全，
## 且 `docs/NETWORK.md` 自称的「均经实测」无任何测试或脚本可复现

- **文件:行号 / 文档章节**：`docs/NETWORK.md:97-113`（§五表格标题
  「web（浏览器）端的限制 —— **均经实测**」，含 `ACAO=*`、预检 204、
  `raw` 预检 403、通道预检 308、签名地址无 ACAO 等 8 行结论）、
  `:116-134`（§六复现命令，**只有 4 条 curl**：raw Range / 私有 raw /
  签名族 302 / `api.github.com/rate_limit` 的 ACAO）、
  `:28-31`（「自 v6.4.3 起不预置任何代理」）；
  对照 `grep -rni -E 'ACAO|access-control|cors|preflight|预检' test/` →
  仅 `test/domain/ix_download_test.dart:8` 一句注释，**0 条断言**；
  `lib/base/net/net_mirror.dart:165` `defaultMirrorChannels = <MirrorChannel>[]`
- **问题描述**：§五 8 行「实测」结论里，**只有 1 行**（`api.github.com/rate_limit`
  ACAO）在 §六有对应命令；`api.github.com` 预检 204、`raw` 预检 403、
  加速通道预检 308、签名地址无 ACAO、通道+Release 直链 ACAO=* 这 5 项
  没有复现命令，也没有离线断言或脚本。按原则 49「依赖网络的测试不属于门禁」
  这些结论本来就不该进 CI，但原则 52 要求「端点语义必须实测」、
  原则 53 要求「语义严密性靠人读」——**文档应当给出可复现证据或标注实测日期/环境**，
  否则「均经实测」是不可核验的断言。另外「加速通道 GET / 预检」两行的
  被测对象在**当前代码里并不存在**（`defaultMirrorChannels` 为空，
  通道完全由用户在设置里自备，见 `net_mirror.dart:145-165` 与
  `docs/NETWORK.md:144` 待办「镜像机制…属死代码」），文档没有说明
  这行结论是对**哪个具体通道**实测的，与原则 45/57 的「单一真相」冲突。
  §二新增 5 类范围（B1-C-02）在 §五没有任何 Web 端结论，亦属覆盖不全。
- **违反的原则编号/文档原话**：原则 **52**「端点语义必须实测：空、无、未启用
  是三种不同的"没有"，混为一谈必出错」、原则 **49**（离线门禁边界）、
  原则 **53**（语义靠人读、禁止只看 diff）、原则 **57**（文档与实现一致）、
  原则 **56**「文档只收持续有效的手册」。文档原话（NETWORK.md:97）：
  「## 五、web（浏览器）端的限制 —— **均经实测**」。
- **P2** · **确证**（附证据）：§六代码块逐行仅 4 条 `curl` 指令；
  `test/` 中 CORS 相关断言 0 条；`net_mirror.dart:165` 空列表 + `:145-151`
  注释「内置镜像通道列表 —— **v6.4.3 起为空，且刻意保持为空**」；
  NETWORK.md:144 待办自认「镜像机制…当前不生效，属死代码」（原则 55
  「死代码零容忍」，文档自己也登记了）。
- **待议**：「曾实测但证据未随文档留存」与「从未实测」无法从仓库区分，
  因此本条判为「**结论不可复现**」确证、「结论本身错误」标待议，
  请主会话结合 Web 分支实测记录裁定；不修改 `docs/NETWORK.md`。

---
## B1-C-14 · 「失败必留痕」在观测层只留计数不留原因：`NetObserver.onFailure`
## 丢弃 `error` / `reason` / `request`；`NetBridge.applyDnsSelection` 在 `dns == null`
## 时静默 `return`，且「UI 必须展示」的 `dnsSummary` 承诺无强制手段

- **文件:行号**：`lib/kernel/contract/net_types.dart:281-320`（`NetObserver` 全部回调：
  `onRequest(NetRequest request)`、`onRetry(..., String reason)`、
  `onMirror(..., String mirrorId)`、`onFailure(NetRequest request, Object error)`
  的**参数一个都没用**，只 `++` 计数）；`:226-278`（`NetStats` 只有 6 个聚合整数，
  无失败原因/状态码分布）；`lib/base/net/net_bridge.dart:30-33`
  （注释「UI **必须**向用户展示，不得让用户猜」）、`:66-69`
  （`if (service == null) { return; }` 静默返回，注释无任何「为何可静默」说明）；
  对照 `lib/domain/domain_bridge.dart:552-560`（`SysNetworkInfo` 只透传 4 个计数）
- **问题描述**：`NetObserver` 头注释自称「**只记账，不决策**」（`net_types.dart:280`），
  这一点本身符合分层；但整个网络层**没有第二个组件负责记录失败原因**：
  `ResilientTransport.send` 在异常路径只调 `_observer.onFailure(current, error)`
  （`net_transport.dart:126`），`error` 传进去即被丢弃，随后 `rethrow` 给上层；
  中间的重试原因 `reason`、镜像 ID、失败 URL 也全部丢弃。于是
  「失败必留痕」只落成 `stats.failures += 1`，诊断页拿不到
  「哪个 URL / 哪类错误 / 走过哪些通道」，与 `docs/NETWORK.md` §三「无降级、无兜底…
  **失败如实报错**」和 `AGENTS.md` §3「失败必留痕（日志/诊断/通知中心）」的
  「日志/诊断」部分仍有差距（`NetException.message` 里虽有自检报告，
  但那是异常消息，不是可查询的诊断记录）。
  `applyDnsSelection` 在 `dns == null` 时静默吞掉用户的设置变更：
  调用方无返回值、无异常、无日志，`dnsSummary` 仍显示「系统解析」——
  这正是原则 15 禁止的「用户可感知的失败没留痕」。生产装配
  （`net_bridge.dart:187`）总是传 `_dns`，但**测试里 11 处 `NetBridge(...)` 全部
  `dns == null`**，即该静默分支在门禁测试中是常态路径。
- **违反的原则编号/文档原话**：原则 **15**「静默降级是最严重的缺陷；失败必须以
  用户可感知的方式留痕」、原则 **16**「不吞异常。捕获后若不重新抛出，必须转化为
  明确的结果或告警」、原则 **42**「失败如实报错」、原则 **28**
  「缓存键必须覆盖产生差异的全部维度」（观测维度同理）、原则 **54**
  （注释「UI 必须向用户展示」与实现无约束）。`AGENTS.md` §3 原话：
  「**失败必留痕（日志/诊断/通知中心），不静默降级**」；
  `docs/ARCHITECTURE.md:4.3` 提及诊断接口 `KernelDiagnostics`，本层
  `net_dns.dart` 已正确使用，`NetObserver` 却未接入。
- **P2** · **确证（静默 return 与参数丢弃）/ 待议（是否构成缺陷）**：
  - **确证**：`net_types.dart:290-313` 四个回调体逐行只有 `_xxx++`；
    `net_bridge.dart:66-69` 逐字为 `if (service == null) { return; }`；
    `NetStats.toJson()`（`:266-274`）无错误明细字段；
    `grep -rn 'NetBridge(' test/ | wc -l` = 11 处且均不传 `dns`。
  - **待议**：`NetObserver` 被明确设计为「只记账，不决策」，把日志留给
    `KernelDiagnostics` 是**合理的分层选择**；本条真正的问题是
    「没有任何组件接手失败明细」，这属于架构归属未定（原则 59 三问），
    是否判为缺陷请主会话结合 B 视角（失败可见性）交叉确认。

---

## B1-C-15 · 命名纪律：`base/net` 公共符号大面积不带 `OgL`/`Net` 前缀，
## 私有常量 `kOgL…` 约定在本层 0 命中

- **文件:行号**：`lib/base/net/net_dns.dart` 公共类型
  `DnsServer`(:136) / `DnsException`(:186) / `DnsWireCodec`(:196) /
  `DnsUdpChannel`(:338) / `DnsResolver`(:366) / `SystemDnsResolver`(:380) /
  `UdpDnsResolver`(:388) / `DnsHttpClient`(:452) / `DohDnsResolver`(:464) /
  `DnsAnswer`(:513) / `DnsCache`(:548) / `DnsPolicy`(:610) / `DnsService`(:658) /
  `DnsProbe`(:1019) / `NetDnsMode`(:33) / `builtinDnsServers`(:162)；
  `lib/base/net/net_mirror.dart` `MirrorChannel`(:9) / `MirrorSelector`(:71) /
  `defaultMirrorChannels`(:165)；`net_retry.dart` `RetryPolicy`(:14)；
  `net_transport.dart` `ResilientTransport`(:41) / `ScriptedTransport`(:210) /
  `defaultRetryableMethods`(:33)；`net_bridge.dart` `NetBridge`(:12) / `NetModule`(:121)；
  `net_self_test.dart` `NetSelfTest`(:21) / `net_self_test_impl_io.dart` `NetSelfTestImpl`(:15)；
  `kernel/contract/net_types.dart` `NetRequest`/`NetResponse`/`NetException`/
  `NetObserver`/`NetStats`/`NetMethod`/`NetErrorKind`/`parseRetryAfterHeader`
- **问题描述**：`AGENTS.md` §3 原话「**命名**：类前缀 `OgL`（domain 层
  `Gh*`/`Ix*`/`Sys*`），私有常量 `kOgL…`，文件名 snake_case」。
  本层 30+ 公共类中只有 `OgLByteRange` / `OgLChunkPlan` / `OgLRangeCancelToken` /
  `OgLRangeDownloader` 4 个带 `OgL`；其余以 `Net` / `Dns` / `Mirror` / `Io` /
  `Raw` / `Retry` / `Resilient` / `Scripted` 开头（用户口径中的「`Net` 前缀」
  只覆盖 `Net*` 一小部分）。`DnsPlatform`（`net_dns_platform_io.dart:17`）
  是平台原语却不带 `OgL`；私有常量仅 `_kUnset`（`io_net_transport.dart:37`）
  一处，写法为 `_k` 而非 `kOgL`；顶层公共常量 `builtinDnsServers` /
  `defaultMirrorChannels`（且是 **可变 `final List`**，可被 `add` 改写）/
  `defaultRetryableMethods` 均不符合 `kOgL…` 约定。
  另 `ogLIsUsableDohEndpoint` / `ogLNormalizeDnsAddress`（`net_dns.dart:47/76`）
  用的是小驼峰 `ogL` 前缀，与 `OgL` 类前缀、与 `lib/surface/util/accel.dart`
  的 `ogLAccelCandidates` / `ogLValidateAccelBaseUrl` 一致——说明项目实际存在
  「函数用 `ogL`、类用 `OgL`」的**未成文惯例**，AGENTS.md 没有写这条。
- **违反的原则编号/文档原话**：原则 **6**「命名即结构：文件名必须能让审计脚本
  识别其层级角色；无法识别的名字不得存在」、原则 **45**「只有一个真相」、
  原则 **57**（文档约定与实现一致）。`AGENTS.md` §3 原话：「**命名**：类前缀
  `OgL`…私有常量 `kOgL…`」；`AGENTS.md` §1 原话「命名约定（layer_audit
  依赖识别，**违反即无法被识别**）」。
- **P2** · **待议**：`layer_audit.py` 实际只按 `*_page.dart` / `*bridge.dart` /
  `*_io.dart`/`*_web.dart` 等**文件名**识别层级（源码 `:21-33`、`ALLOW`、
  `KNOWN`），**根本不检查类名前缀**；`AGENTS.md` 把「违反即无法被识别」归因于
  layer_audit 也与脚本不符（文档自身失真，原则 57）。考虑到全库同类命名已成
  事实标准（`Gh*`/`Ix*`/`Sys*` 本身也不是 `OgL`），本条**不判为需修改的缺陷**，
  标待议：建议主会话决定是更新 AGENTS.md 成文惯例，还是列入长期收敛，
  而不是要求改 30+ 类名。

---

## B1-C-16 · `base/net` 分层本身达标（无向上依赖），但 `range_download.dart`
## 与 `kernel/contract/download_engine.dart` 都 `import 'package:flutter/foundation.dart'`，
## 与「四个非 UI 层不依赖 Flutter SDK」的文档承诺冲突

- **文件:行号**：`lib/base/net/range_download.dart:24`
  （`import 'package:flutter/foundation.dart';`，仅用于 `@immutable`）、
  `lib/kernel/contract/download_engine.dart:16`（同上）、
  `lib/base/disk/disk_cache.dart:29`（`show kIsWeb`）等 18 处同类；
  对照 `docs/ARCHITECTURE.md:8.2` 与 `:6.1` 原话
- **问题描述**：`ARCHITECTURE.md:8.2` 与 `AGENTS.md` 的门禁说明都写
  「`dart analyze lib/kernel lib/base lib/domain lib/platform` 必须 0 问题
  （**不依赖 Flutter SDK**）」、`ARCHITECTURE.md:6.1` 写「**测试隔离**：低层可
  独立于 Flutter SDK 运行 `dart analyze`，CI 验证周期更短」。
  但 `lib/base/net/range_download.dart` 与 `lib/kernel/contract/` 都直接
  `import 'package:flutter/foundation.dart'`，共 18 处（含 `kIsWeb`、
  `@immutable`、`ChangeNotifier` 等）。也就是说「不依赖 Flutter SDK」的
  承诺对 `base/net` 与 `kernel/contract` 不成立；这些文件必须用
  `flutter pub get` + `flutter analyze` 才能解析。
  **分层方向本身是达标的**：`grep -n "^import\|^export" lib/base/net/*.dart`
  显示全部 12 文件只 import `dart:*`、同目录文件、`../../kernel/*`、
  一个 `package:flutter/foundation.dart`，**无任何 `domain/` / `surface/` / `platform/`
  向上的相对 import**；`python3 tool/layer_audit.py --fatal` 实测 0 违规。
- **违反的原则编号/文档原话**：原则 **1**「依赖只能向下」（此项**达标**）、
  原则 **2**「层与层之间只经桥通信」（base 内部同目录互 import 属同层，达标）、
  原则 **57**（文档与实现一致，`ARCHITECTURE.md:8.2/6.1` 口径失真）、
  原则 **5**（契约应放最底层且不引入上层框架依赖）。
  `AGENTS.md` §1 原话：「**非门禁层**：`dart analyze lib/kernel lib/base
  lib/domain lib/platform` 必须 0 问题（不依赖 Flutter SDK）」。
- **P2** · **确证**（附证据）：`grep -rn "package:flutter/" lib/base/ lib/kernel/
  lib/domain/ lib/platform/` 得 18 处，其中 `base/net/range_download.dart:24`
  与 `kernel/contract/download_engine.dart:16` 在本次范围内；
  `ARCHITECTURE.md:6.1`、`:8.2` 与 `AGENTS.md` §1 三处文档原话如上；
  `layer_audit.py --fatal` 实测 `违规：0 处`（分层方向达标，单独记明，
  避免主会话误判本层有向上依赖）。

---

## 附：本视角确证「达标」项（供交叉时排除误报）

| 项 | 证据 |
|---|---|
| 不预置代理 / 不内置加速通道 | `net_mirror.dart:165` `defaultMirrorChannels = <MirrorChannel>[]`；`:145-163` 完整说明为何删；`accel.dart:1-22` 同口径；`NETWORK.md:28-31` 与实现**一致**（本项文档无误） |
| 无降级无兜底 | `download_proxy.dart:82-118` `ogLAccelCandidates` 至多返回 1 项，`if (prefixes.isEmpty ..) return [url]` 是「未启用」而非「失败后垫直连」；`NETWORK.md:72-80` §3.3 与实现**一致** |
| Action 日志不走加速 | `ix_action_logs.dart:57` 直接请求 `api.github.com`；`accel.dart:108` `actionLog` 枚举注释「本版不接入」；`NETWORK.md:47` 结论**一致**（但「因此没有对应开关」与枚举里已有 `actionLog` 开关位、默认关且设置页可见相冲突，见 B1-C-02 附注，标待议） |
| 只重试幂等方法 | `net_transport.dart:33-36` `defaultRetryableMethods = {get, head}`；`:118-131` 非幂等直接 `rethrow` 且不换镜像；`net_test.dart:281-305/379-420` 有 POST/PATCH 离线断言 |
| DoH 只认 https | `net_dns.dart:47-62` `ogLIsUsableDohEndpoint` 校验 `parsed.isAbsolute` + `scheme == 'https'` + `host.isNotEmpty`；`net_bridge.dart:78-82` 复用同一判定；`net_dns_test.dart:145-157` 有 114 无 DoH 端点断言 |
| 过期回调丢弃 | `net_dns_platform_io.dart:47-77` `udpExchange` 用 `completer.isCompleted` 守卫 + `Timer` + 来源 IP 校验 + `finally` 注销 subscription/timer/socket（原则 22/24 达标）；`net_self_test.dart:35-47` 缓存按 host + TTL 校验 |
| 失败必留痕（DNS 侧） | `net_dns.dart:872-881` 回退记 `OGL-DNS-101` warn；`:838-842` 缓存命中记 debug；`:942-948` DoH→明文记 `OGL-DNS-103`；`:853-859` Web 不支持记 `OGL-DNS-102`；`net_dns_test.dart:349-372` 有断言 |
| 并发/资源上限 | `DnsCache.maxEntries = 512`（`net_dns.dart:549`）+ 淘汰逻辑；`RetryPolicy.maxAttempts = 3`（`net_retry.dart:16`）；`io_net_transport.dart:79` `maxConnectionsPerHost = 8`；`OgLChunkPlan.of` 把分片数夹到 `connections`（`range_download.dart:59-78`）——**部分达标**，硬上限缺口见 B1-C-11 |
| `library;` 齐全 | `base/net/` 12/12、`kernel/contract/` 6/6 均有 `library;`（`grep -c '^library;'`） |
| 测试离线可跑 | `net_dns_test.dart:1-4` / `net_test.dart:1-5` 均声明全离线，用注入式 `_FakeUdpChannel`/`_FakeResolver`/`ScriptedTransport`；`net_transport_reconnect_test.dart` 仅用 `127.0.0.1` 回环 ServerSocket（原则 49 允许的本机桩） |
| 文档符号真实存在 | NETWORK.md 引用的 `ogLAccelCandidates` / `defaultMirrorChannels` / `NetTransport` / `ResilientTransport` / `IoNetTransport` / `OgLRangeDownloader` / `OgLAccelScope` / `planRepoFileDownload` / `IxPresign` / `IxPresignResult` / `_showPrivateAccelWarning` / `_setPrivateAccelAccepted` / `accelPrefixesFor` 全部在 `lib/` 中命中（原则 57 的**符号**部分达标，事实/数量部分不达标见 B1-C-01~03） |
| Web 同源 CanvasKit | `NETWORK.md` 本身**未提** CanvasKit/同源；该承诺在 `docs/COLD_START.md:41`，且 `.github/workflows/web.yml:122-123/131/150` 有 `--no-web-resources-cdn` + `canvaskit/` 目录存在性断言，**实现与 COLD_START.md 一致**（本项不属 NETWORK.md 滞后，标「不适用」） |

---

## 汇总

- **确证问题**：B1-C-01（主机冷却文档虚构）、02（4 类→9 类滞后）、03（出口清单漏新 API/新范围）、
  04（契约上提不彻底 + 层级头错标）、05（层级注释/`library;`口径混乱）、
  06（`*_io`/`*_web` 配对与条件 import 失守）、07（`probe` 吞异常静默降级）、
  08（206/重定向零测试）、09（契约不可变性/死字段/重复实现）、
  12（CI 门禁盲区）、13（CORS 结论不可复现）、16（Flutter SDK 依赖与文档冲突）
  —— 共 **12 条**（P1 × 6：01/02/03/06/07/08；P2 × 6：04/05/09/12/13/16；
  其中 B1-C-09 含 P1 与 P2 混合）
- **待议**：B1-C-10（防线开关边界）、11（并发上限与 `_lastVia` 竞态，部分确证）、
  13（结论本身是否错误）、14（观测层失败明细归属，静默 return 部分确证）、
  15（命名前缀成文惯例）、05（`module.dart` 头注释是否例外）、
  06（Web 是否真的不可编译）
- **纪律复核**：`git status --short` 仅 `?? docs/AUDIT_PLAN.md` / `?? docs/audit_b1_a.md`
  （视角 A 的文件）与本次新增 `?? docs/audit_b1_c.md`；
  **未修改任何 `lib/` 文件，未修改 `docs/NETWORK.md`**。

