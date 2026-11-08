# 第 3 批 · 视角 C：GitHub API 层契约与规范审计（v12.0.0 LTS）

> 只审不改：未改动 `lib/`，仅写本文件。范围 29 个文件全部 `file_read` 完整读（清单见文末），不以 rg 正则代替阅读；行号以当前工作区为准。原则编号取自 `docs/QUALITY_STANDARD.md`（59 条）。每条均标注是否确证；运行期/线上推断一律标明「未确证」。文档风格偏好不算缺陷。优先级分布：P0×2 / P1×11 / P2×7 = 20 条。
>
> **审计时点说明（跨批合并时请对齐）**：本报告依据各文件在本批 `file_read` 完成时刻的内容。收尾复核时观察到共享工作区被其它批次并发改动：`lib/domain/gh/gh_api.dart` 的 `lockIssue` 头注释与方法由 `NetMethod.patch` 改为 `NetMethod.put`，并新增 `test/domain/gh_write_endpoints_test.dart`；`docs/audit_b3_a.md` / `audit_b3_b.md` 亦被并行写入。这些改动**不是本视角所做**（本任务只写 `docs/audit_b3_c.md`，未写 `lib/`），且未在本批范围内完整阅读，**不并入本批结论、不据此改判**。故 B3-C-05（lockIssue 头注释）与 B3-C-09（测试覆盖缺口）的证据与行号以各自读取时点快照为准；若其它批次已补端点测试，请将该条理解为「本批读取时点无断言」，不要当成对最终工作区的断言。

---

### B3-C-01 [P1] CONSISTENCY.md 的 206 回执描述落后于实现
- **文件:行号**：`docs/CONSISTENCY.md:45-48`；对照 `lib/domain/gh/gh_api.dart:813-817`。
- **问题**：规范写「`written.sha` 为空时回读远端确认」，实现是「状态码 == 206 **或** sha 为空」都一律回读；206 且回执恰好带 sha 时也必须回读。
- **后果**：规范自称外部基线且「改实现必须同步改本文」，读者会误判 `receiptIncomplete` 分支多余并删掉它，退回截断写回执缺陷。
- **违反原则**：54、57、53。
- **证据（确证·静态）**：CONSISTENCY.md:47 原文；gh_api.dart:816 `final bool receiptIncomplete = response.statusCode == 206;`、:817 `if (receiptIncomplete || written.sha.isEmpty)`；:813-815 注释「只要状态码是 206，就一律回读远端确认」。

### B3-C-02 [P1] gh_api.dart 仍写「D1–D7 / D2/D10」，与 D1 新语义及 D8/D9 不符
- **文件:行号**：`lib/domain/gh/gh_api.dart:7`、`:71`、`:840`、`:845`；对照 `docs/CONSISTENCY.md:1,11,23`、`AGENTS.md:63`。
- **问题**：文件头与 `putContentLocked` 方法头把一致性引擎称为「D1–D7」、用「D2/D10」指代三方差异；规范已扩为 D1–D9，D1 已改为「远端不存在+无基线=合法新建」，且明说 D10 不是独立防线。
- **后果**：写链路入口的注释按旧 D1 描述，评审者会误判「无基线合法新建」是防线被绕过，或把 D8 提交日志/D9 草稿漏出一致性范围。
- **违反原则**：54、55、57。
- **证据（确证·静态）**：gh_api.dart:7/71/840 三处「D1–D7」、:845「D2/D10」；CONSISTENCY.md:1 标题「D1–D9」、:11 D1 新语义、:23「D10…**不是独立防线**」；AGENTS.md:63 已写 D8/D9。

### B3-C-03 [P2] GhClient 注释「只拒收 GET 的 206」，写侧失效分支却仍按 206 成功清理缓存
- **文件:行号**：`lib/domain/gh/gh_client.dart:625-632`、`:645-646`；对照 `lib/domain/gh/gh_api.dart:816-829`。
- **问题**：`!= 206` 只包住缓存回填，紧随的 `if (request.method != NetMethod.get && response.isSuccess)` 对 206 仍执行 `_readCache?.clear()`；注释与实现边界不一致。
- **后果**：206 是「实体不完整、写回执未知」，却在 `putContent` 随后抛「无法确认远端状态」之前已按成功全局失效只读缓存并留成功日志。
- **违反原则**：54、42、53。
- **证据（确证·静态代码路径）**：:631 注释、:632 条件、:645-646 无 206 排除；`isSuccess` 见 :311（200–299）；gh_api.dart:824-828 抛 `GhAuthException`。用户是否实际看到误导属运行期，**未确证**。

### B3-C-04 [P1] 四线新增危险端点把二次确认推给注释，类型上无表达
- **文件:行号**：`lib/domain/gh/gh_api.dart:275-276`（deleteRepo）、`:294-299`（transferRepo）、`:1041-1049`（deleteContent）；对照 `:992`。
- **问题**：三个危险写方法签名均无 `confirmed`/决策类型参数，仅靠「调用方必须先二次确认」注释；同文件 `deleteContentLocked` 裸写路径却已有 `confirmed` 兜底，同层不一致。
- **后果**：任何新调用方（含四线新增 transferRepo）可直接发 DELETE/POST，无编译期/类型期拦截；UI 漏确认即不可逆数据损失，且无离线断言（见 B3-C-09）。
- **违反原则**：12、59、11。
- **证据（确证·静态签名 + 同文件对照）**：:276 `Future<void> deleteRepo(String fullName)`、:299 `transferRepo(String fullName, {required String newOwner})`、:1042-1049 `deleteContent(...)` 均无 confirmed；:992 `if (!confirmed)`；:275/:294 注释要求调用方确认。展示层确认框**不作为本批确证依据**（超出范围，不冒充完整阅读）。

### B3-C-05 [P2] 四线新增 `updateIssue*` / `lockIssue` 头注释未声明 204 空体语义
- **文件:行号**：`lib/domain/gh/gh_api.dart:1690-1695`、`:1697-1715`、`:1717-1722`、`:1724-1737`、`:1739-1755`。
- **问题**：新增写方法均 `Future<void>` + `.then((_) {})`，头注释只讲端点语义（如「全量替换」），未说明「不消费响应体、只靠 `_throwIfFailed` 判成败」及空体/解析失败如何区分。
- **后果**：契约读者误以为会返回更新后资源或校验响应形状；「传空列表=清空」的破坏性无可观测结果，后续「容错」改造易把 204 空体与错误体混同。
- **违反原则**：54、17、52、59。
- **证据（确证·静态）**：上述签名均 `Future<void>`；`GhResponse.jsonObject` 在 gh_client.dart:326-332 解析失败返回 `null`；`_throwIfFailed` 在 :729-731 只按状态码判定。GitHub 实际返回 204 属外部语义，**未在本仓库离线确证**，只报契约注释缺失。

### B3-C-06 [P2] L2 文件头硬惯例未被门禁真正检查
- **文件:行号**：`lib/domain/gh/gh_oauth.dart:1`；对照 `tool/contract_audit.py:34,94-108`、`AGENTS.md:56`。
- **问题**：约定为 `/// L2 中枢级 · …`，本文件写 `/// L2 · …`；`HEADER_RE = re.compile(r'^///\s*(L[0-3])\b')` 只取 `L2` 两字符，不校验称谓与分隔格式。
- **后果**：domain/gh 出现不一致样板且门禁报 0 违规，给评审者错误安全感；后续任意 `/// L2 xxx` 都能通过。本条报的是**硬惯例未被检查器覆盖**，不是排版偏好。
- **违反原则**：6、53、45/57 类比。
- **证据（确证·静态 + 实跑）**：:1 原文；同目录其余 10 文件均为 `/// L2 中枢级 ·`；contract_audit.py:101-107 只比较 `m.group(1)` 与 `want[lay]`；`python3 tool/contract_audit.py` 实测 4 节全 0、exit=0。

### B3-C-07 [P1] 转发门面 `surface/types.dart` 的 hide/show 名单与注释不符
- **文件:行号**：`lib/surface/types.dart:18-27`；对照 `lib/domain/gh/gh_client.dart:27,233,289,406`、`lib/domain/gh/gh_oauth.dart:25`。
- **问题**：注释称「仅暴露异常类型，隐藏 `GhClient` 与限流快照的内部构造」，实际 :21 只 `hide GhClient`，把 `GhRateLimit`/`GhRequest`/`GhResponse` 一并 re-export；:24 连 `gh_oauth.dart` 的二级 `export` 一起透出；:23 `gh_models.dart` 全量导出无 `show`。
- **后果**：页面可经门面直接构造 `GhRequest`/`GhResponse`、拿到请求客户端形状，绕过「页面只 import 门面因而拿不到 domain 服务类」的架构保证。
- **违反原则**：1、2、5、59、57。
- **证据（确证·静态）**：types.dart:20-21 注释与 `hide GhClient;`；gh_client.dart 公共声明 :27/:233/:289/:406；types.dart:24 + gh_oauth.dart:25 二级转发；types.dart:23 无 show/hide；`layer_audit.ALLOW`（:34）整文件放行、不查导出内容。

### B3-C-08 [P1] OAuth 条件 import + export 不被任一门禁的可达性解析覆盖
- **文件:行号**：`lib/domain/gh/gh_oauth.dart:22-25`、`gh_oauth_io.dart:1-8`、`gh_oauth_stub.dart:1-4`；对照 `tool/layer_audit.py:38`、`tool/contract_audit.py:81`。
- **问题**：`import 'gh_oauth_stub.dart' if (dart.library.io) 'gh_oauth_io.dart' as impl;` 与 `export 'gh_oauth_types.dart';`：layer_audit 的 `IMPORT_RE` 只匹配 `^import '…'`，contract_audit 遇 `'if ('` 直接 `continue`，真实实现 `gh_oauth_io.dart` 的依赖不进入解析。
- **后果**：唯一直接 new `HttpClient` 的 domain/gh 文件（:17/:61）不经 `NetBridge → ResilientTransport`，门禁全绿不代表该出口被契约覆盖；平台实现命名/依赖错了也不会被结构检查发现。
- **违反原则**：4、2、43、53。
- **证据（确证·静态 + 门禁源码）**：gh_oauth.dart:22/:25；gh_oauth_io.dart:6 `import 'dart:io';`、:17/:61 `HttpClient()`；layer_audit.py:38 正则；contract_audit.py:81 `'if (' in imp: continue`。是否真有 SSRF/重定向隐患**未确证**（未审 HttpClient 的代理/重定向配置），只报契约与门禁盲区。

### B3-C-09 [P0] 206 回读/四线新增端点/404 严格解析/裸写路径全无 `test/domain/` 离线断言
- **文件:行号**：`test/domain/gh_client_test.dart:1-535`、`gh_submit_e2e_test.dart:1-143`、`gh_absent_test.dart:1-120`；对照 `lib/domain/gh/gh_api.dart:813-829,299-311,1627-1755,690-761,849-928`、`docs/audit_206.md:79-111`。
- **问题**：完整读完 11 个测试文件后，`206`/`transferRepo`/`updateIssue`/`updateIssueLabels`/`updateIssueAssignees`/`lockIssue`/`unlockIssue`/`deleteContentLocked`/`cacheBypass`/`GhReadCache` 均无引用；目录「非数组严格解析」只断言 404 抛出（gh_absent_test.dart:68-74），未断言 200+对象/坏 JSON 抛 `FormatException`；`docs/audit_206.md` 声明的修复没有回归守卫。
- **后果**：曾定级 P0 的 206 回读兜底与四线 6 个新增写端点可在任何离线测试都不失败的情况下被改坏；`AGENTS.md:63` 点名「改动 gh_api.dart 写路径后必跑 `gh_submit_e2e_test.dart`」，该守卫实际只有 2 个用例（:60/:111）。
- **违反原则**：49、50、51、52、53。
- **证据（确证·全文阅读 + 关键词复核）**：11 文件逐个 `file_read` 完整读；`rg -l -F` 上述 10 个关键词在 `test/domain/` 均 `<NONE>`；gh_submit_e2e_test.dart 仅 2 个 test；audit_206.md:79-111 自述「本文档不改动任何 lib/ 代码」且未补测试。`test/base/cache_consistency_test.dart` 存在但**未在本范围全文阅读，不冒充**它覆盖 206。

### B3-C-10 [P1] `_isAbsentStatus` 把 409/422 折成「读不到」，与同文件 `read()` 的 P0 裁决相反
- **文件:行号**：`lib/domain/gh/gh_api.dart:630-639`、`:1199-1206`、`:2171-2176`；对照 `:2070-2080`、`gh_client.dart:783-790`。
- **问题**：头注释称「404/409/422 在读场景都表示『这里没有东西』」，但 `CacheRemote.read` 明写「409/422 属冲突态，绝不能折成 null…读不确定时放行=静默覆盖」并 `rethrow`；`_contentNetwork`/`commits` 仍把 409/422 折成 `null`/空列表。
- **后果**：`putContentLocked` 裸写 force 分支（:876）与 206 回读（:819）都调 `_contentNetwork`；冲突态被折成 `notFound` 或「没有提交」，D1「读不确定不得放行」在两条读路径被绕过。
- **违反原则**：8、9、15、16、52、54。
- **证据（确证·静态代码路径）**：:2175-2176 `404||409||422`；:636-637 `return null`；:1203-1204 `const <GhCommit>[]`；:2074-2080 `rethrow` 且注释点名 B2-A-05 P0。409/422 在 `conflictsAsRemoteConflict=false` 时被折成 `GhAuthException`（gh_client.dart:783-790），故分支可达；线上是否触发**未确证**。

### B3-C-11 [P1] `putContentLocked` 头注释「永不抛」在裸写路径不成立
- **文件:行号**：`lib/domain/gh/gh_api.dart:848`；对照 `:849-928`。
- **问题**：方法头写「**永不抛**：失败以 [WriteOutcome.conflict] 返回」，但裸写分支只捕获 `RemoteConflictException`（:917），`putContent` 的 206 回读失败会抛 `GhAuthException`（:824），`cache.write`（:929）也不在本方法内兜底。
- **后果**：UI 按「GhWriteResult 永不抛」编写不会包 try/catch，未绑定缓存的装配降级下用户看到未捕获异常而非可重试冲突结果。
- **违反原则**：16、17、42、54。
- **证据（确证·静态）**：:848 注释；:888 `try {`、:917 `} on RemoteConflictException catch`；:889 调 `putContent`（:824 抛）；:929 外层无 try。`deleteContentLocked` 同类（:1000-1015）但头注释未写「永不抛」，故不单列。

### B3-C-12 [P0] contract_audit.py 不检查语义，且 docstring 宣称的第 5 项「204/206 回归测试弱提示」根本未实现
- **文件:行号**：`tool/contract_audit.py:1-20,33-36,74-92,121-137,139-153`；对照 `AGENTS.md:29,66`、`docs/CONSISTENCY.md:54`。
- **问题**：docstring :13 列出第 5 项检查，但 `main()` 的 `sections` 只有 4 项，全文无状态码/测试检查函数；`check_exports` 只验路径存在与「向上导出」，不解析 `show`/`hide` 名单是否含真实符号；`DOC_REF_RE` 只匹配 `docs/*.md` 字面串，不校验反引号内符号。
- **后果**：`AGENTS.md:29/66` 宣称它「查 export 指向 / 文档契约引用」，CI 当结构门禁用；实测输出「合计：0 处 / exit=0」，B3-C-01/02/06/07/09 等全部漏过。docstring 的「弱提示」是死描述，误导维护者以为 206 已有守卫。
- **违反原则**：53、55、57、45/49 类比。
- **证据（确证·静态 + 实跑）**：:13 docstring 第 5 项；:142-146 `sections` 恰 4 键；`def check_` 全文仅 4 个（:74/:94/:111/:121）；:36 `DOC_REF_RE`；`python3 tool/contract_audit.py` 实跑 4 节各 0、exit=0。

### B3-C-13 [P1] layer_audit.py 不解析 export，KNOWN/ALLOW 文本过时
- **文件:行号**：`tool/layer_audit.py:32-36,38,46-50,75-90`；对照 `docs/CONSISTENCY.md:54`、`AGENTS.md:10,19`。
- **问题**：`IMPORT_RE` 只匹配 `import`，全项目 19 条 `export`（`surface/types.dart` 13 条跨层 re-export）不进入违规判定；`KNOWN` 仍写「5.0 清单 / 下一批」，`ALLOW` 把整个 `surface/types.dart` 放行而不查导出名单。
- **后果**：CONSISTENCY.md:54 自述的盲区至今属实，而 AGENTS.md:10 写「CI 强制、当前基线违规 0」；两支脚本叠加使 B3-C-07/08 的门面穿透在 CI 全绿下共存，白名单文本停留 5.0 给收敛工作错误进度。
- **违反原则**：2、3、53、55、57。
- **证据（确证·静态 + 实跑）**：:38 正则；:46-50 注释含「5.0 清单」；`rg -n "^\s*export\s" lib/` = 19 条；`python3 tool/layer_audit.py` 实测「文件总数 152 / 已知待收敛（5.0 清单）2 处 / 违规 0 / exit=0」。注：contract_audit.py:33 的 `IMPORT_RE` 确实含 `export`，本条只针对 layer_audit，不重复记。

### B3-C-14 [P2] AGENTS.md 版本头与规模统计停留在 v11.4.0
- **文件:行号**：`AGENTS.md:3-4`；对照 `pubspec.yaml:21`、`lib/main.dart:46`。
- **问题**：导读头写「v11.4.0」「lib/ 197 个 Dart 文件…测试 44 文件」，实际 `pubspec.yaml:21` = `12.0.0+120000`、`main.dart:46` = `kOgLAppVersion = '12.0.0'`，实测 `rg --files lib -g '*.dart'` = 159、`test` = 47（test/domain = 11）。
- **后果**：第一入口的版本/规模错报，使「改动前必读」的读者按旧基线判断门禁与测试覆盖面；与原则 45 冲突（version_sync.py 只管 main.dart × pubspec，文档自述版本即第二处真相）。
- **违反原则**：45、47、57、56。
- **证据（确证·静态 + 计数）**：:3/:4 原文；pubspec.yaml:21；main.dart:46；`rg --files … | wc -l` 结果。行数未按统一口径复核，**不冒充**行数确证。

### B3-C-15 [P1] NETWORK.md 出口清单漏两个 OAuth 端点且指错代码位置
- **文件:行号**：`docs/NETWORK.md:16-22`（:21）；对照 `lib/domain/gh/gh_oauth_io.dart:12-13,17,61`、`gh_oauth.dart:22`、`gh_client.dart:411`。
- **问题**：:21 把「`github.com` | 令牌校验、OAuth Device Flow」的代码位置写成 `gh_client.dart`，实际两个 POST 端点常量在 `gh_oauth_io.dart:12-13`（`/login/device/code`、`/login/oauth/access_token`）并由 :22 条件 import 分派；`gh_client.dart` 只有 `baseUrl = 'https://api.github.com'`。
- **后果**：NETWORK.md 自述「回答应用向哪些主机发起请求」「所引用符号必须真实存在」（:9-10），漏掉带 `client_id`/`device_code` 的真实出口且指错文件，安全评审会漏审不经 NetBridge 的 OAuth 轮询链（见 B3-C-08）。四线新增端点（transfer/issue/actions）都在 `api.github.com` 行内、**未新增主机**，故不记为清单遗漏。
- **违反原则**：57、43、2/4、53。
- **证据（确证·静态）**：NETWORK.md:21；gh_oauth_io.dart:12-13 两个 URL、:17/:61 `HttpClient()`；gh_client.dart:411，全文无 `github.com/login`；`rg -n 'login/device|access_token|github.com' lib/domain/gh/gh_client.dart` 仅命中 :411 的 api.github.com。

### B3-C-16 [P2] NETWORK.md 的 `IxPresign.resolve` 写法与实例方法不符，且待办链接不可达
- **文件:行号**：`docs/NETWORK.md:72,150`；对照 `lib/domain/ix/ix_presign.dart:59,82`。
- **问题**：`IxPresign` 是 `class`，`Future<IxPresignResult> resolve(String url)` 为实例方法，文档写 `[`IxPresign.resolve`]` 易读成静态调用；待办链接 `../../../_setup/ogl_sync.py` 在本工作区解析后不存在。
- **后果**：违反文档自身 :9 的「符号必须真实存在」；`docs/` 只收持续有效手册，指向仓库外一次性同步脚本的待办既不可验证也不可执行。
- **违反原则**：57、56、47。
- **证据（确证·静态 + 路径核验）**：ix_presign.dart:59 `class IxPresign {`、:82 `resolve(String url)`（无 `static`）；`rg -n 'IxPresign.resolve' lib/` 无命中；`os.path.normpath('docs/'+r)` 后 `os.path.exists` = false，`ls /root/_setup/ogl_sync.py` = No such file。若脚本属仓库外私有工具则**未确证**，故只报「本工作区链接不可达」，不冒充「脚本不存在」。

### B3-C-17 [P2] ARCHITECTURE.md 同文档内 D1–D9 / D1–D7 并存，修订史未覆盖 v12
- **文件:行号**：`docs/ARCHITECTURE.md:55,123,145-148`；对照 `docs/CONSISTENCY.md:1,20-21`、`AGENTS.md:63`。
- **问题**：§3.2 写「D1–D9 一致性，权威描述见 CONSISTENCY.md」，§8.1 术语表却写「D1–D7 一致性…详见 `RepositoryCache`」；修订历史末行是 v9.0.0（2026-10），未记录 v12.0.0 的四线端点与 206 回执契约变更。
- **后果**：架构文档给贡献者两个防线编号、术语表指向实现类而非 CONSISTENCY.md，D8/D9 在架构视角被漏掉；修订史不更新使待办看似仍停留 v9。术语表可解释为早期等级遗留，故定 P2、不冒充「实现缺防线」。
- **违反原则**：47、57、56、3。
- **证据（确证·静态）**：:55 `D1–D9`、:123 `D1–D7`、:147 `v9.0.0`；CONSISTENCY.md:1/:20-21 列 D8/D9；`git log --oneline -1` = `08e5814 release: v12.0.0 LTS`。

### B3-C-18 [P1] readmeExcerpt / latestVersionOf 用 `on Object` 把一切失败静默降级
- **文件:行号**：`lib/domain/gh/gh_api.dart:1402-1435,1437-1466`；对照 `gh_client.dart:647-660,652-659`。
- **问题**：两个推荐卡片读取方法用 `on Object { return ''; }` / `on Object { return null; }` 兜底一切异常（含 401/429/编程错误），头注释还写「失败返回空串（卡片仍可展示，不阻断）」，无日志/诊断，不区分「没有/限流/解析坏」。
- **后果**：令牌失效、限流、代理截断都被渲染成「无 README 切片 / 无版本号」，用户与日志都看不到失败；与同层 :652-659「失败要看得见」、:779「只有 404 降级 WARN」的策略相反。
- **违反原则**：15、16、18、19、20、42、52。
- **证据（确证·静态）**：:1432-1434 `on Object { return ''; }`、:1437-1466 三处 `on Object { return null; }`、:1399-1401 头注释；同文件 `_listDirectoryNetwork` :749-750 对 `FormatException` 会 `OgLLogFile.line(... 'ERR')` + `rethrow`，形成对照。线上卡片是否受影响**未确证**，只报代码契约。

### B3-C-19 [P1] CacheRemote.read 无差别吞 404，与 GhNotFoundException 头注释相反
- **文件:行号**：`lib/domain/gh/gh_api.dart:2070-2073`；对照 `gh_client.dart:132-141,779`、`gh_api.dart:320-327,690-721,2074-2080`。
- **问题**：`GhNotFoundException` 注释明确「上层据此区分『仓库确实为空』与『分支/路径不存在 / 令牌无权限』，**不允许把一切 404 都当空目录**」，`isRepoStarred` 也声明无权私有仓库的 404 属「无法判定」；但 `read()` 的 `on GhNotFoundException { return null; }` 无差别交给 D1 判「远端不存在」，注释只写「权限不足返回 403」。
- **后果**：D1 用 `latest == null` 放行无基线 PUT（:2076-2079 自述风险）；若 404 来自分支失效/路径错/无权而非确实不存在，读不确定被折成覆盖风险，与对 409/422 的严格处置不对称。
- **违反原则**：9、15、16、52、54、57。
- **证据（确证·静态）**：gh_client.dart:136-137 注释；gh_api.dart:2070-2073 `return null`；:320-327「无法判定的猜测」；:690-721 对 404 用 `_isEmptyRepositoryMessage(error.body ?? '')` 严格解析后才当空并 WARN + rethrow。GitHub 对无权私有仓库是否必返 404 属**外部语义，未在本仓库离线确证**，只报「契约未区分」，不冒充线上事故。

### B3-C-20 [P2] `_contentNetwork` 的 `__list` 目录判分支不可达
- **文件:行号**：`lib/domain/gh/gh_api.dart:611-628`；对照 `gh_client.dart:326-333,668-677`。
- **问题**：`_contentNetwork` 用 `object.containsKey('__list')` 判目录，但 `getObject()` 走 `GhResponse.jsonObject`，对 JSON 数组（`decoded is Map ? … : null`）恒返回 `null`；`__list` 键在完整读过的 gh_client.dart / gh_models.dart 中不存在。
- **后果**：目录路径实际由 `if (object == null) return null;` 兜底，`content()` 对目录变成「读不到(null)」而非「这是目录」；死分支给后人假情报，数组响应被静默当 null。
- **违反原则**：55、54、17、20、52。
- **证据（确证·静态）**：gh_api.dart:623-626 `object.containsKey('__list')`；gh_client.dart:326-332 `jsonObject`、:668-676 `getObject` 直接返回；`rg -n '__list' lib/domain/gh/` 仅 :623 一处。`_listDirectoryNetwork` 已自己严格判数组（:733-749），故本条只报 `_contentNetwork`，不重复 B3-C-09。

---

## 覆盖文件清单（29 个，全部 `file_read` 完整读；大文件分段且段间重叠，全文覆盖）

`lib/domain/gh/`：`gh_api.dart`(2222)、`gh_auth.dart`(406)、`gh_client.dart`(812)、`gh_draft.dart`(56)、`gh_models.dart`(983)、`gh_oauth.dart`(58)、`gh_oauth_io.dart`(113)、`gh_oauth_stub.dart`(18)、`gh_oauth_types.dart`(43)、`gh_read_cache.dart`(184)、`repo_file_service.dart`(2042)。
`docs/`：`CONSISTENCY.md`(60)、`NETWORK.md`(154)、`ARCHITECTURE.md`(149)、`QUALITY_STANDARD.md`(93)；根目录 `AGENTS.md`(95)。
`test/domain/`：`gh_absent_test.dart`(120)、`gh_auth_service_test.dart`(127)、`gh_client_test.dart`(535)、`gh_models_decode_test.dart`(48)、`gh_submit_e2e_test.dart`(143)、`gh_test.dart`(413)、`ix_conflict_test.dart`(250)、`ix_download_manager_test.dart`(376)、`ix_download_test.dart`(199)、`ix_test.dart`(571)、`sys_test.dart`(396)。
`tool/`：`contract_audit.py`(161)、`layer_audit.py`(106)。

合计约 10,931 行（`wc -l` 口径，分段重叠不影响覆盖）。辅助只读材料（仅用于版本/引用/门禁实跑核验，**不计入范围全覆盖、不冒充完整阅读**）：`docs/audit_206.md` 全文、`lib/surface/types.dart` 全文、`pubspec.yaml:21`、`lib/main.dart:46`、`lib/domain/ix/ix_presign.dart:29-92` 片段、`git log`/`git show` 提交信息、`rg --files` 计数与关键词复核、`python3 tool/contract_audit.py` 与 `python3 tool/layer_audit.py` 实跑。

## 整体规范符合度评价

- **结构（原则 1–7）**：基本符合，门面与门禁脱节。domain/gh 11 文件均带 `/// L2 …` 前缀、实测文件头 0 违规；`gh_auth.dart`/`gh_read_cache.dart` 只用 `kernel/contract/*` 抽象、装配期注入，符合原则 5；`gh_api.dart → disk_cache.dart`、`gh_client.dart → net_bridge.dart` 两处具体依赖已被 `layer_audit.KNOWN` 显式登记（原则 3 可枚举成立），与 `AGENTS.md:19`/`ARCHITECTURE.md:76` 一致。不符合点：B3-C-06（前缀格式）、B3-C-07（hide/show 名单）、B3-C-08/13（条件 import + export 未解析）——契约门面目前靠注释自觉，不靠脚本强制。
- **数据可靠性与错误处理（8–21）**：核心写链路符合度高，读/降级路径有裂缝。`CacheRemote.read`(:2056-2132) 对 409/422/截断/空文件/>1MB 的处置、D1 新语义、`deleteContentLocked` 裸写 D7 兜底(:992)、`_listDirectoryNetwork` 严格数组解析(:733-760) 是本批最严谨部分。不符合点集中在 B3-C-10/11/18/19/20：同一种失败在不同端点被不同处理，而非单点 bug。
- **网络与安全（39–44）**：主链路符合（统一 NetBridge、按资源类别限流、幂等重试在 base 层、`GhToken.toString` 脱敏、令牌只进 vault，均有离线断言），例外是 `gh_oauth_io.dart` 直接 `HttpClient` 发两个 `github.com/login/*` POST，不经门面、不被 NETWORK.md 收录（B3-C-15）、不被门禁可达性解析（B3-C-08）。是否构成 SSRF/重定向隐患**未确证**，不冒充。
- **测试与验证（49–53）**：最弱一环。测试全部离线、用 `ScriptedTransport`/`InMemoryVault`/`InMemoryKv`，符合 49/50；`gh_submit_e2e_test.dart` 锁死 B1-A-01/B2-A-01/B2-A-05 与 D1 新建。但 206 回读（曾定级 P0）、四线 6 个新增写端点、`transferRepo`、`deleteContentLocked`、`updateIssue*`、404 body 严格解析、`GhReadCache` 的 bypass/TTL/Link 头**全部无 test/domain 断言**（B3-C-09）；`AGENTS.md:63` 宣称的守卫实际只有 2 个用例，`docs/audit_206.md` 自述只补文档未补测试，原则 51/52 未落实。
- **门禁可信度（53）**：脚本自述能力 > 实际能力，是本次最需纠正的规范问题。两支脚本实跑均 exit=0 / 违规 0，但 docstring 第 5 项「204/206 回归测试弱提示」未实现（B3-C-12）、layer_audit 不解析 19 条 export（B3-C-13）、`HEADER_RE` 只取 `L0–L3` 两字符（B3-C-06）。原则 53 允许「脚本只守语法与结构、语义靠人读」，前提是**如实声明守了什么**；当前 `contract_audit.py` docstring 与 `AGENTS.md:29/66` 越过了这条线。故 2 条 P0（B3-C-09 / B3-C-12）都指向「CI 全绿但语义无守卫」。
- **文档与可维护性（45/47/54–59）**：失效引用较多且均可静态确证：B3-C-01/02/14/15/16/17。四线新增方法头注释**本身有**端点语义说明（transferRepo 的 202 与 `full_name` 变更、updateIssueLabels 的全量替换、lockIssue 的枚举校验），符合原则 54；问题在于危险操作没有类型化确认（B3-C-04）、void 写方法未声明 204 空体语义（B3-C-05）——「注释解释了 why，但契约没把义务变成类型」。
- **总体结论**：**实现质量高于契约质量**。GitHub API 层核心写链路与模型容错解析达到 59 条原则的多数要求，注释普遍解释 why；但「文档基线、门面名单、门禁自述、测试守卫」四者未随 v12.0.0 四线功能与 206 修复同步收口，形成 20 条确证问题（P0 = 09/12；P1 = 01/02/04/07/08/10/11/13/15/18/19；P2 = 03/05/06/14/16/17/20；2+11+7 = 20）。**未把任何文档风格偏好算作缺陷**：B3-C-06 报硬惯例未被检查器覆盖，B3-C-17 报同文档自相矛盾，均非排版/措辞偏好。所有「未确证」项已逐条标注，不含线上行为推断。
