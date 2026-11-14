# AGENTS.md — OhGithubLost 工程规范与代码地图

> 面向 AI 助手与贡献者的项目导读。项目：Flutter 多平台 GitHub 客户端（Apache-2.0），
> Android / Windows / Linux / Web。版本号以 `pubspec.yaml` 与
> `tool/version_sync.py` 为准，文件 / 行数 / 测试数量等计量数字一律以
> `find`/`wc` 实测为准；本文不维护任何计数或版本快照
> （避免「文档数字静默腐烂」，见 docs/audit_spec_c.md C-01）。
> 工程底线：**数据可靠性 + 失败如实可见** —— 不静默降级、不预置加速通道、不掩盖版本冲突。

## 1. 五层架构与依赖门禁

依赖方向**只能向下**：`surface(L3) → domain(L2) → base(L1) → kernel(L0)`；`platform/` 仅依赖 kernel。
CI 由 `tool/layer_audit.py --fatal` + `tool/contract_audit.py --fatal` 强制（前者扫分层 import，后者查 export 指向 / 文件头层级 / 平台门面 / 文档契约引用；违规退出 1，当前基线违规 0）。

| 层 | 目录 | 职责 | 关键符号 |
|---|---|---|---|
| kernel L0 | `lib/kernel/` | 契约（`contract/`）、DI、模块总线、生命周期、信任链（Ed25519 引导清单签名）、日志接口、诊断 | `OgLKernel`、`KernelDi`、`KernelModuleBus`、`BootLoader`、`BootIntegrityVerifier` |
| platform | `lib/platform/` | 平台识别 + 窗口能力，**判平台一律走门面，禁止直接用 dart:io / defaultTargetPlatform** | `ogLDetectPlatform()`、`window_capability.dart` |
| base L1 | `lib/base/` | 网络栈（重试/镜像/DoH/分片下载）+ 磁盘栈（一致性引擎/Journal/草稿/SAF 三档） | `BaseBridge`、`ResilientTransport`、`RepositoryCache`、`NetBridge`、`DiskBridge` |
| domain L2 | `lib/domain/` | GitHub API 客户端、OAuth、下载与预签名、冲突编排、设备信息 | `DomainBridge`、`GhApi`、`GhClient`、`RepoFileService`、`IxDownloadManager` |
| surface L3 | `lib/surface/` | 页面、控件、i18n、主题、动效分级、Async 四态构件 | `SurfaceBridge`、`OgLSettingsController`、`AsyncController/AsyncView`、`OgLAnim` |

**桥（bridge）机制**：每层一座层桥（`*bridge.dart`）注册进 `KernelBridgeRegistry`，上层只许 `XxxBridge.of(bridges)` resolve 层桥，禁止直接 import 下层内部文件。合法例外仅 3 文件（layer_audit `ALLOW`）：`domain/domain_bridge.dart`、`surface/surface_bridge.dart`（装配根）、`surface/types.dart`（唯一可 re-export domain DTO/异常的门面）。`KNOWN` 白名单恰 2 项待收敛：`gh_api.dart → base/disk/disk_cache.dart`、`gh_client.dart → base/net/net_bridge.dart`（正解：在 `kernel/contract/` 定义抽象）。

**命名约定**：页面 `*_page.dart`（100% 合规，违者无法被识别为页面）；桥 `*bridge.dart`；平台实现 `*_io.dart` / `*_web.dart`（条件 import，编译期解析 —— 现状：`lib/platform/` 下无条件 import，见 ARCHITECTURE §6.2）；服务 `*service.dart` / `*manager.dart` / `*api.dart` 为**新增时的建议后缀**（不被脚本强制，存量部分不吻合，见 ARCHITECTURE §5）；共用构件放 `surface/app/`（一件事一个文件）。

**非门禁层**：`dart analyze lib/kernel lib/base lib/domain lib/platform` 必须 0 问题（不依赖 Flutter SDK）；surface 无 SDK 环境用 `dart format --output=none lib` 兜底。

## 2. CI 门禁清单（全部量化标准）

1. **layer_audit.py --fatal**：分层 import 检查（见上）。
1a. **contract_audit.py --fatal**：结构契约检查（export/import 真实指向、L0–L3 文件头层级前缀、平台判定必须经 `lib/platform` 门面、docs 引用的契约文档必须存在；组合根与平台适配分派文件已登记白名单）。
2. **perf_audit.py --fatal**（扫 lib/surface/）：fatal 硬规则 —— `shrinkWrap: true`、宽依赖 `MediaQuery.of(context)`（须用 `sizeOf`/`paddingOf`/`textScalerOf`）、四类 saveLayer 着色器源：`BackdropFilter(`、`ImageFilter.blur|BlurStyle`、`ColorFiltered(`、`ShaderMask(`（着色器不受整文件 ALLOW 豁免，SHADER_ALLOW 必须保持为空）。只报告不拦截：ListView(children:[...for]) 急加载长列表、非动画 `Opacity(`。白名单：ALLOW 6 文件 + REVIEWED_BOUNDED 7 文件（以 `tool/perf_audit.py` 内登记为准，文档不另维护计数）。
3. **motion_audit.py --fatal**（扫 lib/surface/**）：禁止硬编码动画/等待时长 `Duration(milliseconds:/seconds:/minutes:/hours:/days: n)`、`ScaleTransition(`/`AnimatedScale(`/`AnimatedXxx(` 隐式动效、`BackdropFilter(`/`ImageFilter.blur(`、`Curves.linear`（一律走 ease-out 阶梯）。行内豁免仅限逐行精确匹配等待语义（`Timer(`、`throttle`、`ttl`、`debounce`、`exitWindow`、`cache` 等提示词所在行），不再整行子串放行全部规则。白名单仅 `app/motion.dart`、`app/animations.dart`。
4. **i18n_scan.py --check**：① lib/ 中文界面文案 0 处未本地化（log 豁免、`// i18n-allow:` 豁免）；② 所有语言分片 key 集合与 zh 完全一致；③ 三处语言清单一致（`OgLI18n.locales` × assets/i18n 目录 × pubspec assets）。
5. **ui_audit.py --fatal**：设计令牌一致性 —— 间距刻度仅 {4,8,12,16,24,32,48,64}（`OgLSpace.*`）；圆角刻度仅 {4,8,12,16,24,999}（`OgLRadius.*`）；`fontSize` 必须走 `textTheme.*`（等宽上下文放行）；字面色禁止（仅放行 `Colors.transparent`、`Colors.entries`），须用 `colorScheme.*` / `OgLSemanticColors`；曲线白名单 = `tool/ui_audit.py` 的 `CURVES_ALLOWED`（ease-out 阶梯 + 特例，与 `app/motion.dart` 档位表一致，以脚本内登记为准）。
6. **sort_imports.py**：`dart:` → `package:` → 相对路径，组间空行、组内字母序；处理 lib/ 与 test/。
7. **version_sync.py**：main.dart `kOgLAppVersion` 必须等于 pubspec `version`，`--fix` 可自动改写。
8. **boot_manifest.py**：四层目录逐文件 sha256 聚合 → coreDigest，Ed25519 签名（私钥仅 CI）；canonical JSON 与 `boot_manifest.dart` 的 `canonicalJsonEncode` 逐字节一致，改动须跑 `test/kernel/boot_release_chain_test.dart`。
9. **inject_platform_spec.py + platform_spec.yaml**：平台私有文件注入（每条必须写 why；**spec 没写的能力必须在 lib/platform/ 用 Dart 实现，注入不是逃生舱**）。
10. **verify_apk_cert.py**：发布后 APK 证书校验。

## 3. 组合根（lib/main.dart）

`lib/main.dart` 是**唯一装配点**，不在四层目录内、不参与 layer_audit 的分层扫描
（`layer_of('main.dart')` 返回 None，属结构性豁免而非漏审 —— 它必须 import 各层
桥与启动模块）。`contract_audit.py` 的 `PLATFORM_ALLOW` 已显式登记它
（组合根诊断展示平台名）。新增跨层装配代码应写进 main.dart 或各层桥，
不应再出现第 5 个跨层点。

## 3. Lint / 代码风格

- 基线 `flutter_lints ^6.0.0`；**strict-casts / strict-inference / strict-raw-types 三项全开**（jsonDecode 结果一律显式 `as`）。
- 5 条升级为 error：`unused_import`、`unused_local_variable`、`dead_code`、`missing_required_param`、`missing_return`。
- 追加 22 条：`always_declare_return_types`、`annotate_overrides`、`avoid_print`、`cancel_subscriptions`、`close_sinks`、`directives_ordering`、`prefer_single_quotes`、`use_super_parameters`、`valid_regexps` 等。
- 有意不启用：`prefer_final_locals`、`sort_pub_dependencies`、`comment_references`（各有理由，勿随手加回）。
- **依赖削减**：只用真实被 import 的包（cryptography、crypto、path_provider、secure_storage、markdown、url_launcher、archive、background_downloader）；展示层只用 Material 3 原生组件，不引视觉框架/状态管理库。dependency_overrides：`connectivity_plus: 6.1.4`。
- **文件头注释是硬惯例**：`/// L1 底座级 · …` 层级前缀 + `library;` + 中文设计说明（含表格/ASCII 图）；事件码 `OGL-BOOT-107`、`OGL-BASE-001` 带层标签。
- **命名**：类前缀 `OgL`（domain 层 `Gh*`/`Ix*`/`Sys*`），私有常量 `kOgL…`，文件名 snake_case。
- **import 顺序**：`dart:` → `package:` → 相对路径按层级从深到浅（kernel → base → 同目录），一律相对 import。
- **错误处理**：一致性引擎返回 `WriteOutcome` 不外抛；网络用类型化异常（`NetException`、`RemoteConflictException`）；内核用 `extends Error`；反序列化永不抛异常（夹紧回落默认）；**失败必留痕（日志/诊断/通知中心），不静默降级**。
- **状态管理**：自研，统一 `ChangeNotifier`（`GhAuthService`、`IxSession`、`OgLSettingsController`、`AsyncController`、`DraftStore`、`OgLI18n`），跨层状态经层桥共享。

## 4. 启动 / 引导流程

`main.dart` 二次 `runApp` 模式：先渲染零依赖 `OgLBootSplash`（不读磁盘/不碰内核），随后四段 await（日志落盘 → 平台存储 → kernel.boot 信任链校验 → 装配）后顶替为 `OgLApp`。全局错误捕获三件套（FlutterError.onError / platformDispatcher.onError / ErrorWidget.builder 局部错误卡）。发布构建经 `--dart-define-from-file` 注入 CI 签名清单，**缺签名清单 = 拒绝启动**；调试构建走 `developmentBypass` + OGL-BOOT-107 告警。

BootLoader 五阶段：清单自检 → Ed25519 验签（公钥内嵌，私钥仅 CI）→ 官方模块目录指纹 → 扩展策略 → 就绪上报。签名无效 → `KernelBootException`；部分模块失败 → 安全模式（safeMode + excludedModules）。

内核启动链：`BootLoader.run → 过滤排除模块 → ModuleBus.register（拓扑排序）→ seal → Lifecycle.registerAll → Di.seal + Bridges.seal → startAll（失败逆序回滚）→ KernelReport`。Di 与 BridgeRegistry 封存后运行期注册即抛错。

## 5. 关键设计（改动前必读）

- **缓存一致性七道防线（disk_cache.dart，约 1030 行；权威描述见 `docs/CONSISTENCY.md`）**：D1 写前必读（**远端已存在且无基线才拒绝；远端不存在且无基线为合法新建**；空串基线归一化为「无基线」）、D2 SHA 乐观锁、D3 409/422 冲突重试、D4 逐键串行互斥、D5 写后回读校验（回读不一致按「已提交待确认」收尾）、D6 失败返回结果不外抛、D7 危险操作二次确认。合法例外（重放不重复入队、force 需用户确认、裸写旁路仍带服务端乐观锁、官方新建）已在 CONSISTENCY.md 界定，不算「防线开关」。D8 = Write Journal（可恢复事务，持久化 force/hadRebase）；D9 = 草稿先落盘（带 baseSha）。
- **提交链路回归守卫**：`test/domain/gh_submit_e2e_test.dart` 锁死「编辑已有文件必须提交成功且 PUT 带 body」「远端 409 不得被当作不存在而发无基线 PUT」。改动 `gh_api.dart` / `io_net_transport.dart` / `disk_cache.dart` 写路径后必跑。历史 P0：守卫首跳丢 body、302/303 错降级 GET、缓存锁内自锁死锁、D1 误判静默覆盖、草稿箱打开即删草稿。
- **网络**：`NetBridge → ResilientTransport → IoNetTransport`；**只重试幂等方法**（默认仅 GET/HEAD，PUT/DELETE 刻意移除）；Retry-After 优先 + jitter（支持 HTTP-date）；换通道不吃重试预算但尊重退避；**所有请求统一走手动重定向守卫**（跨主机一律不跟随、拒绝 http 降级/私网/云元数据，敏感头集合 6 种）；DoH 客户端拒绝 https→http 降级；分片下载每片 ≥1MB。
- **结构契约门禁**：`tool/contract_audit.py --fatal` 解析 export/import 指向、文件头层级前缀、平台门面、文档契约引用；与 layer/ui/motion/perf/i18n 一起在 ci.yml 严格模式汇总，任一失败统一 fail。
- **令牌安全**：令牌只进系统密钥库，toString 脱敏；OAuth Device Flow；预签名第一跳本地完成、**令牌不出设备**；SSRF 防护（拒绝回环/私网/169.254.169.254）。
- **批量操作**：>200 分批且 expectedHeadSha 链式推进；`IxTaskRunner` 在类型上强制 `IxBatchDecision`（用户确认）否则抛 `IxConfirmationRequired`。
- **动效四档**（0 静默 → 3 拉满）：降档=降质量不是丢功能，全部参数进 `OgLOAnimQuality` 数据表，页面禁止硬编码。
- **平台存储失败退回内存但大声上报**（不允许静默丢失登录态）。

## 6. i18n 规范（zh / en 双语）

- 分片 `assets/i18n/<locale>/<page>.json`（一语言一目录一页面一分片），2 空格缩进 + 键排序 + 末尾换行。
- 取文案 `_t(page, key)` / `t(page, key, {args})`；兜底：当前语言 → 英文基线 → 键名，绝不返回空串。
- 新增文案：zh 分片加键 → 代码 `_t('键')`（去掉所在行 const）→ 翻译 en（GitHub/Release/Actions/PR/Token/Commit 等术语**不译**）→ `i18n_scan.py --check` 0 失败。
- 新增页面：文案全走 `_t` → `og_l_i18n.dart` pages 列表注册 → 建 **六语言**分片（zh / zh_Hant / en / de / fr / ru；Web 分支为 zh_TW）→ pubspec 加目录 → `i18n_scan.py --check` 三处清单一致 → 跑 i18n_test.dart。

## 7. 测试规范

- 按四层分目录（kernel/base/domain/surface），命名 `<主题>_test.dart`，**全部离线运行**（接口 + 内存实现两步走，CI 不依赖网络/真机）。
- 重点测试：`boot_release_chain_test.dart`（引导清单契约守卫）、`chaos_test.dart`（破坏性混沌注入）、`durability_test.dart`、`cache_consistency_test.dart`、`i18n_test.dart`、`screenshots/`（`OGL_SCREENSHOTS=1` 落盘）。
- 评审 checklist（.skills/flutter-reviewer）：build() ≤ 80–100 行、`_build*` 助手抽成独立 widget、尽量 const、禁 print、不裸 catch Error、Future 用 await/unawaited()、build() 内禁网络/IO/listen()、列表用 ValueKey。

## 8. 版本与发布

- CHANGELOG.md 新版本在前，条目分"修复/新增/改进"。
- release_notes/v<版本>.md 中英对照，固定小节：新增/变更/修复/已知限制/产物；未发布的版本不建文件。
- `changed/_content/v<版本>.md` 面向使用者的日志（书面语、不写内部实现、350–700 字；规范见 `changed/_content/_STYLE.md`），发布后由 `changed/generate_posts.py` 生成站点文章；`changed/releases.json` 需同步已发布版本的产物。
- 版本一致性门禁：pubspec `version` = `kOgLAppVersion`（version_sync.py）；boot_manifest 的 appVersion 读自 pubspec，buildId = git sha。
- docs/ 只收"持续有效"的手册；文档引用的符号必须真实存在。

## 9. 文档索引

`docs/ARCHITECTURE.md`（五层架构与门禁）、`docs/PERF.md`（性能与动效）、`docs/I18N.md`、`docs/COLD_START.md`（冷启动）、`docs/NETWORK.md`（出口主机与加速通道）、`docs/USAGE.md`、`docs/5layer-audit-todo.md`（语义审计待办）。
