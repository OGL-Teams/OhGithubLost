# 全仓库功能审计 · 批 1-C · 引导信任链

> **文档戳**：更新时间 **2026-11-23 06:40:45 +08:00** · **v15.0.0** · 仓库 `/root/OhGithubLost` · 只读审计（不改代码、不 commit/push）
> 审计范围：`lib/kernel/boot/`（7 文件）+ `lib/main.dart` 启动路径 + `tool/boot_manifest.py` + `.github/workflows/build.yml`（清单生成步骤）+ `.github/signing/README.md`（说明）+ 佐证读取 `lib/kernel/kernel.dart`、`lib/base/base_bootstrap.dart`、`lib/surface/app/og_l_app.dart`、`test/kernel/boot_release_chain_test.dart`、`test/kernel/boot_define_injection_test.dart`、`test/kernel/kernel_test.dart`。

## 问题分级总览

| 级别 | 数量 | 一句话 |
| --- | --- | --- |
| P0（安全/崩溃/数据丢失） | 1 | 发布构建单腿注入校验只覆盖 1/9 腿，且签名样本用占位 `coreDigest` 假锁定信任根 |
| P1（功能失效/不一致） | 6 | PR 私钥 Secret 缺失导致合并门槛永久红、扩展告警码从不触发、失败页泄漏堆栈、修复前已写盘等 |
| P2（打磨） | 3 | 指纹算法未 NFC、解析容错不等于 fail-closed 的边界、可观测性缺口 |

---

## P0（安全/崩溃/数据丢失）

### P0-1 · 信任根样本可验≠构建信任链闭合：签名覆盖的核心目录只被 1/9 构建腿校验，且锁定样本用假摘要
**复现**：`rg -n 'manifestModuleNotProvided|unsignedModLoaded|OGL_BOOT_MANIFEST' .github/workflows/build.yml test/kernel/fixtures/release_key_signed_manifest.json`
**症状**
- `build.yml:608-613` 的“引导清单注入校验”带 `if: matrix.label == 'Android · arm64-v8a'`，9 条构建腿中只跑 1 条；其余 8 条只靠 `--dart-define-from-file=dart_define.json`（build.yml:534、546）把清单编进二进制，没有任何运行前验签。注入件在同一份 artifact 内，若 manifest job 后 dart_define.json 被篡改/污染，8 条腿照常出包，用户启动才拒绝启动。
- `test/kernel/fixtures/release_key_signed_manifest.json` 中 `"coreDigest": "fixture-digest"` 是占位串，`test/kernel/boot_release_chain_test.dart:30-37` 也用同样的假摘要；`tool/boot_manifest.py:74-90` 真实签名覆盖 `lib/kernel`、`lib/base`、`lib/domain`、`lib/surface`、`lib/platform` 五目录指纹及 `lib/main.dart` 摘要。锁定测试证明的是“内嵌公钥能验假 payload”，并未证明“构建合约（真 payload）可被验”。
- `tool/boot_manifest.py:89-90` 把 `coreDigest` 算进 payload，但 `lib/kernel/boot/boot_manifest.dart:115-128` 解析时把它放进 `extra`，`lib/kernel/boot/boot_loader.dart:302-350` 运行时从不比对源码指纹——AOT 产物无法逐文件校验，于是“核心模块 BL 锁”只有在构建期成立。
**根因**：信任链设计把“签名正确”和“被签内容正确”拆成两件事，前者有端到端测试，后者只靠脚本自证；CI 又只在一条腿重复验证前者。
**修复指令**
1. `.github/workflows/build.yml:608-613`：去掉 `if: matrix.label == ...` 限制，改为每条腿构建前都跑 `boot_define_injection_test.dart`（或把验签收进 `tool/boot_manifest.py` 并在所有腿下载后校验 artifact 哈希）；
2. `test/kernel/boot_release_chain_test.dart`：新增“构建合约”测试，用 `tool/boot_manifest.py` 的真实 `build_payload()`（可用固定构建快照）验证 `canonicalJsonEncode` 与 Python `canonical_json` 逐字节一致且 `coreDigest` 非空匹配；
3. `test/kernel/fixtures/release_key_signed_manifest.json`：用真构建参数重签，去除占位 `coreDigest`；轮换记录同步 `.github/signing/README.md`。

---

## P1（功能失效/不一致）

### P1-1 · PR 构建必失败：fork/普通 PR 拿不到仓库 Secret，manifest job 硬退出，合并门槛名存实亡
**复现**：`rg -n 'pull_request:|OGL_BOOT_KEY|needs: \[manifest\]' .github/workflows/build.yml` → 39、115-118、161 行
**症状**：`.github/workflows/build.yml:39` 声明 `pull_request` 全量构建，但 `manifest` job 在 115-118 行把 `secrets.OGL_BOOT_KEY` 缺失当 `exit 1`；GitHub 对来自 fork 的 PR 默认不注入 Secrets，整个 PR 构建在第一步就红，`build` job 因 `needs: [manifest]`（161 行）永不运行。PR 合并门槛实际未执行任何编译/测试。
**根因**：签名私钥注入被设计为“无密钥即全链路失败”，没有给不可信 PR 提供本地临时签名/测试清单的分叉。
**修复指令**：在 `build.yml` 增加 PR 分支路径：`if: github.event_name != 'pull_request'` 用于还原私钥与签名步骤；PR 用测试密钥生成清单（测试公钥只注入测试 target）或让 `manifest` job 产出未签名清单并在 PR 构建中启用 `developmentBypass`，同时把签名验签测试标记为 skip（PR 不验证签名本身）。

### P1-2 · 第三方 Mod 策略承诺的 OGL-BOOT-101 告警从不产生，`evaluateExtension` 只是查表，装载路径零接线
**复现**：`rg -n 'unsignedModLoaded|evaluateExtension|mustWarnBus' lib/kernel/boot/ lib/kernel/kernel.dart lib/domain/sys/sys_access.dart` → 仅定义与查表，无调用点
**症状**
- `lib/kernel/boot/trust_policy.dart:121-129`：第三方 Mod `mustWarnBus: true`，文档（同文件 10 行表）与 `trust_warnings.dart:23-24` 的 OGL-BOOT-101 都承诺“装载 Mod 必须告警”。
- `lib/kernel/boot/boot_loader.dart:166` 与 `lib/kernel/kernel.dart:327-328` 的 `evaluateExtension` 只返回 `TrustDecision`，`boot_loader.dart:355-363` 在 Stage 3 只把策略写进阶段 detail 字符串，**未调用 `warnings.report`**；全仓 `rg 'unsignedModLoaded|untrustedThemeEnabled|extensionRejected'` 只出现在常量定义处。
- 实际 Mod 装载走 `lib/domain/sys/sys_access.dart` 的能力授权，和引导层告警总线没有任何连接。用户装载第三方 Mod 不会收到承诺的总线告警，策略形同虚设——这正是审计维度⑥的绕过点。
**根因**：策略与告警解耦，缺少“消费层装载时调用 `evaluateExtension` 并消费 `mustWarnBus`”的强制接线。
**修复指令**
1. 在 `lib/kernel/kernel.dart` 增加 `Future<void> authorizeExtension(ExtensionKind kind, String modId)`：调 `evaluateExtension(kind)`，若 `mustWarnBus` 则 `warnings.report(code: BootWarningCodes.unsignedModLoaded, subject: 'mod:$modId', severity: TrustSeverity.danger, ...)`；`requiresUserConsent` 为真时阻塞；
2. `lib/domain/sys/sys_access.dart` 的 Mod 授权入口改为先走该内核接口，禁止直接 `capability` 放行；
3. 在 `test/kernel/kernel_test.dart` 加“装载 Mod 必产生 OGL-BOOT-101 且 sink 收到”的回归。

### P1-3 · 失败路径在内核引导**之前**已改动磁盘，却向用户宣称“数据没有被改动”
**复现**：`rg -n 'OgLLogFile.init|baseLayerModulesOnPlatform|kernel.boot|runApp\(OgLBootSplash|dataUntouched' lib/main.dart lib/base/base_bootstrap.dart lib/surface/app/og_l_app.dart`
**症状**：`lib/main.dart:83` 的 `OgLLogFile.init`（写日志文件到 sdcard/外部目录）、`lib/main.dart:205` 的 `baseLayerModulesOnPlatform()`（打开真实 PlatformStorage/密钥库）都发生在 `kernel.boot()`（219 行）之前。`lib/surface/app/og_l_app.dart:203` 的失败页文案来自 i18n `dataUntouched`（“数据没有被改动，也没有上传”），但签名失败时日志已落盘、平台存储已打开，可能触发密钥库访问/目录创建。信任链声明的“不改数据” reputation 承诺与事实不符。
**根因**：`main()` 把“引导必须先于一切数据动作”视为逻辑顺序，但把日志和存储探测排在了引导前面，失败页又复用了绝对化文案。
**修复指令**：把 `kernel.boot` 提到 `OgLLogFile.init` 和 `baseLayerModulesOnPlatform` 之前，失败时只写内存日志；或把失败页文案改为“启动被拒绝，业务数据未被读取或上传（诊断日志可能已写入）”，并同步所有 i18n `shell.json` 的 `dataUntouched` 条目。

### P1-4 · 兜底失败页把完整堆栈直接展示给用户，泄漏内部路径/符号
**复现**：`rg -n 'stackTrace|OgLBootFailureApp' lib/main.dart`
**症状**：`lib/main.dart:332-345` 的兜底 catch 把 `$stackTrace` 拼进 `OgLBootFailureApp(message: ...)`；`lib/surface/app/og_l_app.dart:205-208` 用 `SelectableText` 全文呈现且可复制。启动期异常堆栈含源码路径、文件名、内部类名，安全产品的失败界面不应向旁路攻击者/普通用户提供此类指纹。对比 `KernelBootException` 分支（323/331 行）只传 `error.toString()`，没有堆栈，说明两分支口径不一致。
**根因**：调试诉求（可见堆栈）与用户可见错误信息未分层。
**修复指令**：`main.dart:344-345` 只传 `error.toString()` 或统一错误码（如 `OGL-BOOT-000`）；完整堆栈仅写 `OgLLogFile.line('崩溃', ...)`（336 行已有），并在失败页提供“复制诊断信息需二次确认”入口；`test/kernel/` 增断言失败页 message 不含 `Stack` 关键字。

### P1-5 · 清单解析的“容错”与 fail-closed 语义冲突：单个坏条目会被保留且参与签名，模块列表非 List 被静默清空
**复现**：`rg -n 'fromJson|_asString\(|is! List|canonicalPayloadBytes|signature' lib/kernel/boot/boot_manifest.dart`
**症状**
- `lib/kernel/boot/boot_manifest.dart:254-260`：`_parseModules` 对非 List 的 `modules` 返回空列表；配合 `:257` 的 empty 清单逻辑，`modules` 被改成 `null` 或字符串后，Stage 0 自检（boot_loader.dart:247-260 的 `malformedModuleCount == 0`）仍通过，“没有条目”被当成健康状态。
- `BootModuleEntry.fromJson`（108-127 行）把非字符串 id/path/version 用 `_asString` 强转（如 `123` → `'123'`），只有 `layer` 解析失败会置 null；这些字段既进 `payload` 参与签名，又被强转后参与模块指纹校验。签名覆盖的是“原始坏值”，验证的是“强转后的好值”，存在语义错位。
- `fromJson`（164-179 行）对 JSON 里 `signature: 123` 不报错而是当未签名；若清单同时被篡改，签名校验失败能兜住——但 `developmentBypass` 调试构建（main.dart:196）会放行坏清单。
**根因**：文档（boot_manifest.dart:4-6）主张“缺字段给默认值，永不崩溃”，而信任链要求“损坏即拒绝”；二者未划清边界。
**修复指令**：在 `BootManifest.fromJson` 增加严格模式参数，发布构建传入 `strict: true`，遇到 `modules` 非 List、条目字段类型非 String、`signature` 类型异常直接抛 `FormatException` 触发 `_refuse`；保留 `strict: false` 供开发/测试。把 `_asString` 的强转限制为 `extra` 字段，核心字段必须 `is String`。

### P1-6 · 指纹算法 Python/Dart 两侧均未做 NFC、符号链接与隐藏文件语义对齐，扩展模块指纹可被跨平台差异绕过
**复现**：`rg -n 'listFilesRecursive|sort\(\)|os.walk|rels.sort|normalizePath|followlinks|NFC' lib/kernel/boot/boot_fs.dart lib/kernel/boot/integrity_verifier.dart tool/boot_manifest.py`
**症状**
- `tool/boot_manifest.py:51-56` 用 `os.walk` + `rels.sort()`（Python 按 Unicode 码点），`lib/kernel/boot/boot_fs.dart:89-96` 用 Dart `sort()`（同样按 UTF-16 code unit，BMP 内一致，但含 emoji 路径时 Python 码点序与 Dart UTF-16 代理对序不同），两侧对非 BMP 字符路径的排序可能不同→同一扩展包算出的指纹不一致，产生拒绝装载或误放行。
- 两侧都直接按原始字节/字符串处理路径，未做 Unicode NFC 规范化：`é`（U+00E9）与 `e\u0301`（组合符）在 macOS HFS+/部分同步盘上可指向同一文件但指纹不同（Dart 侧无 `normalizePath` 的 NFC 步骤，Python 侧也无 `unicodedata.normalize`）。
- `os.walk` 默认 `followlinks=False`，而 Dart `InMemoryBootFileSystem.listFilesRecursive` 没有符号链接概念；真实 IO 实现已被删除（boot_fs.dart:41-44），CI 与运行时的差异不再有任何真实路径实现兜底，扩展包目录指纹仅存在于设计文档。
**根因**：`integrity_verifier.dart:7-11` 写明的“确定性算法”契约只在 ASCII 路径下成立；Python 端 `directory_fingerprint` 当前对 `coreDigest` 有效（源码路径均 ASCII），但 `tool/boot_manifest.py:22` 声明“保留给有真实文件落地的扩展包”，届时差异立即暴露。
**修复指令**
1. 两端统一把相对路径转成 NFC 再排序：`tool/boot_manifest.py` 加 `unicodedata.normalize('NFC', rel)`；Dart 侧 `integrity_verifier.dart:185` 前对每个路径做 NFC（可按 `package:unicode` 或自实现规范表，禁止依赖 Flutter SDK）；
2. 改用 `sort((a, b) => a.codeUnits...)` 明确 UTF-16 序，或 Python 端改按 UTF-16BE 字节序 `key=lambda s: s.encode('utf-16-be')`，保证逐字节一致；
3. 明确符号链接规则：两侧都拒绝符号链接入指纹（Python `os.walk` 跳过 `os.path.islink`，Dart 真实现补 `FileSystemEntity.isLink`）并写入契约文档；
4. 在 `test/kernel/kernel_test.dart` 增加非 ASCII+emoji+NFC 路径的交叉向量，断言 Dart 指纹与 `python3 tool/boot_manifest.py` 输出相同。

---

## P2（打磨）

### P2-1 · `coreDigest` 被解析进 `extra` 但从不参与运行时校验，日志也未展示
**复现**：`rg -n 'coreDigest' lib/kernel/boot/ tool/boot_manifest.py`
**症状**：`tool/boot_manifest.py:90` 签入 `coreDigest`，Dart 侧 `BootManifest.extra`（boot_manifest.dart:148-157）保留它却无人读取，`BootLoader.run()`（boot_loader.dart:169-397）的阶段 detail 与 `KernelReport.bootSummary` 均不含该值。审计者无法从启动报告判断“这份清单覆盖的是哪次源码构建”。
**根因**：签名覆盖与可观测性没打通。
**修复指令**：在 `BootManifest` 增加 `String? get coreDigest => payload['coreDigest'] as String?`，Stage 0 detail 追加 `coreDigest=...`，并在 `kernel.dart:270-283` 的 `KernelReport` 里透出。

### P2-2 · 解析失败与签名失败都写 `failureReason`，但堆栈错误直接进 `BootStage.detail` 与信任告警 message
**复现**：`rg -n 'detail: .解析失败|reason: .引导清单解析失败|message: reason' lib/kernel/boot/boot_loader.dart`
**症状**：`boot_loader.dart:231-239` 把 JSON 解码异常的 `$error`（可能含文件内容片段/偏移）写进阶段 detail 与 `failureReason`，`_refuse`（399-414 行）再把 reason 原样送进信任告警 message，最终经由 `main.dart:331` 与 OgLTrustNoticeSink 显示在 UI。虽非完整堆栈，但错误信息外泄面比必要的宽。
**根因**：调试信息与用户可读信息共用一个字段。
**修复指令**：`_refuse` 增加 `userReason` 与 `debugDetail` 两参：告警/`failureReason` 只写固定码（如 `OGL-BOOT-104`），细节只走 `diagnostics.error` 的 data 字段与落盘日志。

### P2-3 · `developmentBypass` 判定只看 `hasSignedManifest`，未绑定 `kReleaseMode` 的反向场景
**复现**：`rg -n 'developmentBypass|hasSignedManifest|kReleaseMode' lib/main.dart:176-196`
**症状**：`main.dart:196` 的表达式 `!hasSignedManifest && !kReleaseMode` 意味着“release 构建即使注入了清单也不会开旁路”（正确），但 profile 构建若注入了无效签名清单，`developmentBypass=false` 直接拒绝启动——profile 构建本应允许调试；反之 debug 构建若注入了 signed manifest，旁路自动关闭，导致本地调试因构建期清单与当前源码不匹配而被拒。行为符合注释，但缺少 profile 的明确定义。
**根因**：旁路与构建模式/签名状态耦合在一个布尔表达式里，没有策略表。
**修复指令**：在 `main.dart` 显式枚举：`developmentBypass = kDebugMode || (kProfileMode && !hasSignedManifest)`，并在启动日志打印 `bootMode/signatureValid/bypass` 三元组；补 `test` 对四种组合的断言。

---

## 已检查清单（逐项，无问题也列出）

### `lib/kernel/boot/`（全部 7 文件）
| 文件 | 检查内容 | 结果 |
| --- | --- | --- |
| `integrity_verifier.dart` | ①公钥长度校验（101-107 行，32 字节长度正确）；②`SimplePublicKey(bytes, type: ed25519)` + `Signature(bytes, publicKey:)` + `_ed25519.verify(canonicalPayloadBytes(), signature:)`（117-125 行，验签方向正确）；③base64 与 catch 的 fail-closed（110-114、126-128 行）；④`directoryFingerprint` 遍历/排序/拼接/二次 sha256（168-195 行） | 签名方向 OK；指纹排序与 NFC 见 P1-6 |
| `boot_manifest.dart` | `canonicalJsonEncode` 全类型分支（41-76 行）、`BootModuleEntry.fromJson/isWellFormed`（86-127 行）、`BootManifest.fromJson/schema/isSchemaSupported/malformedModuleCount`（142-216 行）、`_parseModules`（253-262 行） | 规范化实现与 Python 对齐；容错边界见 P1-5，`coreDigest` 可见性见 P2-1 |
| `boot_loader.dart` | Stage 0 读取/自检、Stage 1 签名、Stage 2 模块指纹、Stage 3 扩展策略、Stage 4 就绪、`_refuse`（169-425 行）；五阶段顺序与 refused/safeMode 语义 | 主流程闭合；扩展告警未接线见 P1-2；解析错误文案见 P2-2 |
| `boot_fs.dart` | 抽象接口、`InMemoryBootFileSystem` 的 normalizePath/read/list/exists 与真实 IO 实现删除说明（1-99 行） | 内存实现排序与 Python 对齐（ASCII 路径）；符号链接/NFC 见 P1-6 |
| `trust_policy.dart` | 四种 ExtensionKind、TrustTier、TrustDecision 字段（allowLoad/requireSignature/mustWarnBus/requiresUserConsent）、`evaluate`（89-133 行） | 策略表本身符合 COLD_START 文档；消费端缺失见 P1-2 |
| `release_trust_root.dart` | 32 字节公钥常量与 base64 对照（`rg` 外部计算确认两者一致，56 行） | OK |
| `trust_warnings.dart` | 8 个告警码、严重级、Collector 的 `emit/report/sinkErrors`（1-181 行） | 收集器逻辑 OK；101/105/106 从不触发见 P1-2 |

### 启动与外围
| 文件 | 检查内容 | 结果 |
| --- | --- | --- |
| `lib/main.dart` | `kOgLBootManifestJson` 注入（52 行）、splash 先行（80-84 行）、日志落盘（83 行）、全局错误捕获（102-130 行）、BootLoader 装配与 `developmentBypass`（176-196 行）、平台存储（205 行）、`kernel.boot`（219 行）、失败分支（323-346 行） | 见 P0-1、P1-3、P1-4、P2-3 |
| `lib/kernel/kernel.dart`（佐证） | `boot()` 拒绝即抛 `KernelBootException`（约 190-198 行）、安全模式排除模块（约 200-212 行）、清单/装配交叉校验（约 214-244 行）、`evaluateExtension` 转发（326-328 行） | 排除/交叉校验 OK；扩展入口见 P1-2 |
| `lib/base/base_bootstrap.dart`（佐证） | `PlatformStorage.open` 失败回退内存并回传 `storageError` | 见 P1-3 |
| `lib/surface/app/og_l_app.dart`（佐证） | `OgLBootFailureApp` 结构与文案（155-220 行） | 见 P1-3、P1-4 |

### 构建与签名
| 文件 | 检查内容 | 结果 |
| --- | --- | --- |
| `tool/boot_manifest.py` | `canonical_json`（38 行）、`directory_fingerprint`（42-63 行）、`build_payload` 五目录+main.dart（74-90 行）、`sign_payload` 自验（93-103 行）、私钥缺失 SystemExit（124-128 行）、输出 list/define（131-139 行） | 算法主体 OK；跨平台排序/NFC/符号链接见 P1-6 |
| `.github/workflows/build.yml` | `on` 触发（19-40 行）、manifest job 参数护栏与私钥还原（84-152 行）、9 腿矩阵与 dart-define 注入（159-195、529-547、608-613 行）、注入校验仅 Android arm64（608-613 行）、release job（648-655 行） | 见 P0-1、P1-1 |
| `.github/signing/README.md` | Secret 名、v2 公钥、轮换记录、本地还原步骤（1-90 行） | 与代码一致，未发现文档错配 |

### 测试（佐证，只读）
| 文件 | 检查内容 | 结果 |
| --- | --- | --- |
| `test/kernel/boot_release_chain_test.dart` | 信任根锁定、临时密钥签验、启动链、篡改拒绝（46-133 行） | 占位摘要问题见 P0-1 |
| `test/kernel/boot_define_injection_test.dart` | 注入存在性/验签（1-49 行） | 只在 CI 一条腿跑，见 P0-1 |
| `test/kernel/kernel_test.dart` | 签名/目录指纹/引导/策略相关测试目录（226-438、688-730 行） | 覆盖合法签名/篡改/schema/模块失败/开发旁路/策略表；缺 P1-2、P1-6 的用例 |

**未读取**：`/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码（全程遵守禁令）；本地 `dart` 未使用（本次审计无需 format）；未改任何代码、未 commit/push。

---

## 本席结论

引导信任链的**核心验签方向、公钥字节、schema 自检与模块失败转安全模式的主路径是正确的**，但链的可信闭合存在 1 项 P0：CI 只在 1/9 构建腿校验注入件，且“信任根锁定”测试用占位 `coreDigest`，并未锁定真实构建合约。P1 层面最危险的是**第三方 Mod 的强制告警从未接线（可被静默装载）**、**PR 构建因 Secret 缺失恒红**，以及**失败页宣称“数据未改动”却已写盘/打开存储并展示完整堆栈**。指纹算法当前仅能保证 ASCII 路径下两侧一致，NFC/非 BMP 排序/符号链接尚需对齐。建议按 P0-1 → P1-2 → P1-1 → P1-3/4 → P1-5/6 顺序修复，并在修复后补跑 `test/kernel/boot_release_chain_test.dart` 与 `test/kernel/boot_define_injection_test.dart` 的全腿注入校验。
