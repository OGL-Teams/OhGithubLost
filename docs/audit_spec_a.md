# 审计报告 · 视角 A：分层与桥接制度的实现正确性

- 仓库：/root/OhGithubLost（main，v12.5.2，kOgLAppVersion 与 pubspec 一致）
- 范围：AGENTS.md、docs/ARCHITECTURE.md、docs/QUALITY_STANDARD.md 第一章、tool/layer_audit.py、tool/contract_audit.py，及 lib/ 全部 import/export 边（静态逐边提取，非仅跑脚本）
- 基线实测：`python3 tool/layer_audit.py --fatal` → 文件 154（find 实为 161 个 .dart，见 A-11）、KNOWN 2、违规 0；`contract_audit.py --fatal` → 4 项 0 处，exit 0。

## 发现清单（按确证程度排序）

---

### A-01 · P1【确证】layer_audit.py 不解析 `export`，re-export 可完整绕过跨层门禁

- **文件:行号**：`tool/layer_audit.py:41`（`IMPORT_RE = re.compile(r"^\s*import\s+'([^']+)'", re.M)`）——正则只匹配 `import`。
- **证据**：全仓实际存在 21 条 `export`，其中 15 条由 `surface/types.dart:18-44` 转发 domain 文件、4 条由 `base/disk|net/*_types.dart` 转发 kernel 契约。layer_audit 对这些行零感知；`contract_audit.py:33`（`IMPORT_RE` 匹配 `import|export`）虽解析 export，但它的 `check_exports`（`tool/contract_audit.py:57-75`）只拦 **向上** 导出（`RANK[tlay] > RANK[lay]`），**同层的合法 export 与“下层经 export 间接暴露给更上层”均不拦**。
- **反例（不改动，仅说明）**：若在 `lib/surface/any_page.dart` 写成 `export '../../domain/gh/gh_models.dart' show GhRepo;`（页面文件直接再导出 domain 类型，绕过 types.dart 门面），layer_audit.py 不会拦（不匹配 import），contract_audit.py 也不会拦（L3→L2 是向下导出，`check_exports` 只拦向上）。门禁全绿，但“唯一类型门面”的纪律已被打破——页面间可经任意页面文件互取 domain 符号。
- **建议修法**：layer_audit 的 IMPORT_RE 改为 `(?:import|export)`；contract_audit 增加规则：L3 文件 `export` 指向 L1/L2 时仅放行 `surface/types.dart`（与 layer_audit 的 ALLOW 对齐）。

### A-02 · P1【确证】layer_audit.py 对非 lib 目录下的层级文件不设防（`--lib` 可指空集，且 layer_of 只认四层前缀）

- **文件:行号**：`tool/layer_audit.py:34-36`（`LAYERS`/`RANK` 硬编码）、`layer_of()`（`parts[0] not in LAYERS → None → continue`）。
- **证据**：实测 `python3 tool/layer_audit.py --lib lib/surface` 输出「文件总数：0」（相对路径 `surface/...` 首段不在 LAYERS，被静默跳过）。说明 CI 若被改成其它 `--lib` 或目录重构后，门禁会**静默变成空跑**而非报错。
- **反例**：若 CI 写成 `layer_audit.py --lib .`，所有文件（含 test/）首段均非四层名，违规恒为 0，exit 0——门禁形同虚设且无任何警告。
- **建议修法**：扫描结束时若 `total == 0` 则视为配置错误退出非 0；同时警告「首段不是四层名的 .dart 文件」数量。

### A-03 · P1【确证】KernelBridgeRegistry 按层键注册，但没有任何门禁保证「四座桥都被注册」；L0 无桥、注册表为裸 `Map<String,Object>`

- **文件:行号**：`lib/kernel/bridge_registry.dart:20-56`（`register<T>`/`resolve<T>`，字符串键、无层级校验）；注册点仅 3 处：`lib/base/base_bridge.dart:54`、`lib/domain/domain_bridge.dart:501`、`lib/surface/surface_bridge.dart:650`（`grep -rn "ModuleLayer.kernel.key" lib` → 0 命中）。
- **证据**：四层中 kernel(L0) 本身不注册桥（内核即契约，可辩护）；但 registry 的 `register` 允许注册**任意字符串键**（如 `register('fake', Object())`），`resolve` 仅按 `runtimeType` 校验。没有脚本或测试断言 boot 后 `_bridges` 恰含 {base, domain, surface} 三个键——若某层模块忘记 `bridges.register`，启动不报错，直到上层 `resolve` 才抛 `KernelBridgeError`，且 `BootLoader` 五阶段不覆盖此项。
- **建议修法**：`Bridges.seal()`（kernel.dart 启动链）时断言键集合 == `{'base','domain','surface'}`；或在 boot_report 中列出已注册桥，缺失即 fail。

### A-04 · P1【确证】三个 kernel/contract 文件头层级前缀错误（L1），contract_audit 因「跳过 kernel」放行

- **文件:行号**：`lib/kernel/contract/disk_store.dart:1`（`/// L1 底座级 · 硬盘逻辑：…`）、`lib/kernel/contract/disk_types.dart:1`（同前缀）、`lib/kernel/contract/net_types.dart`（同类）。
- **证据**：文件位于 L0 目录 `kernel/contract/`，却被 contract_audit 的 `check_headers` 识别为 L1——它按**文件头写的层级**回填语义（`tool/contract_audit.py:83-96`：`lay=layer_of(rel)` 为 kernel 时直接 `continue`，不校验头部内容），而我按「文件头前缀 vs 目录层」独立扫描发现这 3 处 L0 文件自称 L1。头前缀与真实层级矛盾，正是「命名即结构」(原则 6) 的反面例证；现有门禁结构上不可能发现此类错误。
- **反例**：把任何 kernel 文件头写成 `/// L3 展示级`，contract_audit 不会拦（kernel 被跳过），layer_audit 不看头。
- **建议修法**：check_headers 去掉 `lay == 'kernel'` 跳过，kernel 一律要求 L0。

### A-05 · P2【确证】layer_audit 的 KNOWN 匹配按「import 原文字符串」，路径改写即可把白名单套用到任意目标

- **文件:行号**：`tool/layer_audit.py:88-96`（`elif rel in KNOWN and imp in KNOWN[rel]`）。
- **证据**：KNOWN 是 `(文件, import字面量)` 二元组精确匹配。若在 `gh_api.dart` 里写成 `import '../../../base/disk/disk_cache.dart'`（上一级目录不存在，编译会失败，威胁有限）；更现实的绕法是：新建 `lib/domain/gh/_re.dart` 写 `export '../../base/disk/disk_cache.dart' show RepositoryCache;`，然后 `gh_api.dart` import `'_re.dart'`——同层 import，layer_audit 0 违规，KNOWN 计数掉到 1（悄悄“收敛”了假象）。与 A-01 同根：export 不在 layer_audit 视野内。
- **建议修法**：KNOWN 收敛前，先修 A-01；KNOWN 命中处应同时断言目标解析路径与登记路径一致（normpath 已做，问题只在 export 旁路）。

### A-06 · P2【确证】文件头层级前缀覆盖有缺口：kernel 层 19 个文件无 L0 前缀（contract_audit 明示跳过 kernel）

- **文件:行号**：`tool/contract_audit.py:86`（`if lay is None or lay == 'kernel' …: continue`）。
- **证据**：独立扫描（`^/// L[0-3]` 前 400 字符）显示缺头文件：`kernel/kernel.dart`、`kernel/di.dart`、`kernel/module_bus.dart`、`kernel/lifecycle.dart`、`kernel/environment.dart`、`kernel/diagnostics.dart`、`kernel/bridge_registry.dart`、`kernel/boot/*`（8 文件）、`kernel/contract/module.dart`，以及 main.dart 与 3 个豁免文件（base/net/net_types.dart 等）。共 19 处（不含已登记 HEADER_EXEMPT 4 项与 main.dart）。“文件头是硬惯例”（AGENTS.md §3）在 kernel 层实际未执行，门禁也明文不管。
- **建议修法**：要么给 kernel 层文件补 L0 头并纳入门禁，要么在 AGENTS.md 明示 kernel 豁免——现状是「文档说硬、代码半空、门禁装聋」三重不一致。

### A-07 · P2【确证】platform/ 的条件 import 实际为零，`*_web.dart` 命名约定全仓 0 文件；条件 import 存在于 domain 层（未按 ARCHITECTURE §6.2 的命名强制）

- **文件:行号**：`grep -rn "dart.library" lib` → 仅 2 处，均在 domain：`lib/domain/gh/gh_oauth.dart:22`（`gh_oauth_stub.dart if (dart.library.io) 'gh_oauth_io.dart'`）、`lib/domain/ix/ix_action_logs.dart:24-25`（save_io / save_stub）。`lib/platform/` 下 6 个文件全部无条件 import，`window_*.dart` 按平台名分文件、由 `platform.dart` 一次性 import（`lib/platform/platform.dart:20-23`）——原生平台编译会携带全平台窗口代码（靠运行时分发，与 §6.2 宣称的「编译期解析、不付运行时成本」相悖）。`stub` 后缀文件（`gh_oauth_stub.dart`、`ix_action_logs_save_stub.dart`）违反 ARCHITECTURE §6.2「违反命名（如 *_web_stub.dart）将无法被识别」的自设规则，但 layer_audit 对非四层前缀文件只按目录判层，stub 文件靠 `*_stub` 不匹配任何命名规则**静默存活**。
- **建议修法**：ARCHITECTURE 应如实记载现状（window_* 全量编译 + domain 层两处条件 import），或按约定收敛；stub 改 `*_io.dart`/`*_web.dart` 命名。

### A-08 · P2【确证】main.dart（组合根）文件头无层级前缀、直用 `defaultTargetPlatform`（已登记 PLATFORM_ALLOW）且 import 跨三层的内部文件——合理但「例外 3 文件」口径与 AGENTS.md 不完全一致

- **文件:行号**：`lib/main.dart:1-3`（`/// OGL 应用入口`，无 L 前缀）；`lib/main.dart:33-35, 39-45`（直接 import `base/base_bootstrap.dart`、`base/log/log_dirs.dart`、`domain/ix/ix_notify.dart`、`surface/app/*`、`surface/surface_bridge.dart` 等十余个跨层内部文件）；`lib/main.dart:297`（`defaultTargetPlatform.name`）。
- **证据**：AGENTS.md 说合法例外「仅 3 文件」（ALLOW），但组合根 main.dart 实际是第 4 个跨层点——layer_audit 对它免疫只因为它 `layer_of('main.dart')` 返回 None（不在四层目录），属于**结构上漏审**而非登记例外。contract_audit 的 PLATFORM_ALLOW 明确登记了 `main.dart`，说明作者知道组合根是例外，但 layer_audit 的 ALLOW 清单未相应文档化。
- **建议修法**：在 AGENTS.md/ARCHITECTURE 的例外清单中明写「组合根 lib/main.dart 免分层审查（唯一装配点）」，消除“仅 3 文件”的字面误导。

### A-09 · P2【确证】surface/types.dart 的 `hide` 黑名单门面模式脆弱：`export 'gh_oauth.dart'`（无 show/hide）把 gh_oauth.dart 的**全部**导出（含其转发的 gh_oauth_types.dart 全量符号）透给页面

- **文件:行号**：`lib/surface/types.dart:24`（`export '../domain/gh/gh_oauth.dart';`，唯一一条裸 export）；`lib/domain/gh/gh_oauth.dart:25`（`export 'gh_oauth_types.dart';`）。
- **证据**：types.dart 其余 11 条 export 都用 `show`/`hide` 收窄，唯独 gh_oauth 整文件透传。gh_oauth.dart 及 gh_oauth_types.dart 中任何未来新增的服务类/单例都会自动进入页面可见面，无需改 types.dart——门面失去「显式列出」的作用（types.dart 自述头注释明确要求“请改这个文件”）。
- **建议修法**：改为 `show` 白名单（仅 DTO/异常类型），或至少 `hide` 全部服务类。

### A-10 · P2【确证】文档漂移（多处）

1. **AGENTS.md:4**：声称「lib/ 159 个 Dart 文件 ≈ 55,800 行」——实测 `find lib -name '*.dart' | wc -l` = **161**，`wc -l` = **56,565**（含 main.dart）。layer_audit 报「文件总数：154」（platform 6 文件 + main.dart 不计）。三处数字三个口径。
2. **lib/base/base_bridge.dart:3、lib/kernel/contract/module.dart:13/121 等 ≥5 处**：引用 `docs/ARCHITECTURE.md（该文件未落地，以源码为准）`、`docs/NAMING.md（该文件未落地…）`——**两份文档都已存在**（docs/ARCHITECTURE.md、docs/NAMING.md 经查：NAMING.md 实际不存在 ✓ 但 ARCHITECTURE.md 存在），代码内“未落地”括注已过时；而 `docs/NAMING.md` 被多处引用为权威出处却**确实不存在**，contract_audit 的 `check_doc_refs` 只扫 docs/ 目录内引用、不扫 lib/ 内引用，故 0 告警。
3. **D1–D9 vs D1–D10**：AGENTS.md/CONSISTENCY.md 权威口径 D1–D9；`lib/domain/domain_bridge.dart:4` 与 `:160` 写「D1–D10」。与历史审计 B2-C-22 呼应，域内编号仍越界。
4. **main.dart:16-17**：注释称「仓库里没有任何 `assets/`」——`assets/` 目录实存（boot/fonts/i18n/icon/mods/theme_packs），零外部资源叙事已过时。
5. **AGENTS.md §2.2 描述 contract_audit 查「L0–L3 文件头层级前缀」**——实际实现跳过 kernel（见 A-04/A-06）。

### A-11 · P2【确证】layer_audit 统计口径与实际文件数不符（154 vs 161）：platform/、main.dart 不入统计也不入审查

- **文件:行号**：`tool/layer_audit.py:57-61`（`lay = layer_of(rel); if lay is None: continue`）。
- **证据**：platform 层（6 文件）在 layer_audit 中完全不可见。platform 目前只依赖 kernel ✓（`grep` 验证 `lib/platform/*.dart` 无 domain/base/surface import），但一旦有人向 platform 引入 base/domain import，**没有任何门禁拦截**——AGENTS.md 明文「platform 仅依赖 kernel」，这条规则没有脚本守。
- **建议修法**：layer_audit 增加 platform 层（rank 介于 kernel 与 base 之间，可被 base/domain/surface 依赖，只能依赖 kernel）。

### A-12 · P2【确证】命名约定「页面 *_page.dart」实际 100% 合规、「桥 *bridge.dart」合规，但「服务 *service/*manager/*api」与实际文件名（gh_auth/gh_client/ix_session…）仅部分吻合——该规则本身不可被脚本识别，属纸面约定

- **证据**：`ls lib/surface/pages` 无非 `_page.dart` 文件 ✓；四座桥（base_bridge/domain_bridge/surface_bridge/disk_bridge/net_bridge）命名合规 ✓、头部 L1/L2/L3 前缀正确 ✓。但 domain/base 下的服务文件大量无 service/manager/api 后缀（gh_auth.dart、gh_client.dart、ix_session.dart、disk_cache.dart…），说明该命名约定从未被强制，仅 gh_api.dart/repo_file_service.dart 偶然吻合。
- **建议修法**：在 ARCHITECTURE §5 标注该行仅为「新增时的建议后缀」，勿宣称可被审计依赖。

### A-13 · P3【推测】装配顺序 L1→L2→L3 正确性依赖模块声明依赖，无独立验证

- **文件:行号**：`lib/main.dart:196-201`（`[...bootstrap.modules, ...domainLayerModules(), surfaceModule]`，注释自述「顺序即拓扑：L1 → L2 → L3」）。
- **证据**：顺序在 main.dart 里正确（bootstrap L1 → domain L2 → surface L3），且 kernel.boot 有拓扑排序兜底（kernel.dart:205 `bus.register(module)` + `ModuleBus` 依赖校验）；BaseLayerModule/DomainModule/SurfaceLayerModule 的 `dependsOn` 是否逐层登记未逐行核对（推测：`GhModule` 头注释「依赖 base.layer」表明有声明）。风险不在现状而在演化：main.dart 无门禁保证新增模块不被插错位置，仅靠 ModuleBus 运行时校验兜底（若有人直接绕过 bus 手动 onRegister 则无守）。标注为推测，建议补一条测试断言 boot report 的模块顺序。

---

## 总体结论

**制度基本成立**：四座桥（base/domain/surface 三座注册 + kernel 即契约层）命名与头部正确、装配顺序 L1→L2→L3 经 ModuleBus 拓扑校验、layer_audit/contract_audit 实跑 0 违规、KNOWN 恰 2 项与文档一致、`*_page.dart` 页面命名 100% 合规、surface 页面未发现绕过 types.dart 直接 import domain 的实例（独立逐边提取确认）。

**最大漏洞是「export 不在 layer_audit 视野内」（A-01/A-05）**：layer_audit 只匹配 `import`，contract_audit 的 export 检查只拦向上导出——任何 lib 文件都可以用一条 `export '../../domain/...'`（向下导出）把下层内部符号转发给更上层，两个门禁全绿通过。types.dart 精心设计的 show/hide 门面因此可被任何页面文件一句 export 击穿。第二档漏洞是 kernel 层整体处于门禁盲区（文件头不查、platform 层不扫、bridge 注册完整性无断言，A-03/04/06/11）。建议按 P1 顺序先补 export 解析与空扫描告警，再收敛 kernel 头前缀与文档漂移（A-10 的 5 处文档失真应一并修正）。
