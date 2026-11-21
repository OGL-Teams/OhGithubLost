# 引导信任链参考 / Boot Trust Chain Reference

> 状态 / Status：参考（Reference） · 面向技术人员 / For engineers
> 范围 / Scope：`lib/kernel/boot/`、`lib/main.dart`、`lib/kernel/kernel.dart`、`tool/boot_manifest.py`、`.github/workflows/build.yml`

> **更新时间 / Last Updated**：2026-11-21 16:14:39　**对应版本 / Version**：v14.0.0

## 1. 组件与符号表 / Components and symbols

| 文件 / File | 类 / 符号 | 职责 / Role |
| --- | --- | --- |
| `lib/kernel/boot/boot_loader.dart` | `BootLoader`、`BootStage`、`BootResult` | 五阶段引导序列；`run()`、`_refuse()`、`evaluateExtension()` |
| `lib/kernel/boot/boot_manifest.dart` | `BootManifest`、`BootModuleEntry`、`canonicalJsonEncode()`、`kSupportedManifestSchema` | 清单模型、容错解析、规范化序列化；`canonicalPayloadBytes()`、`fromJson()`、`isSchemaSupported`、`malformedModuleCount` |
| `lib/kernel/boot/integrity_verifier.dart` | `BootIntegrityVerifier`、`IntegrityReport`、`ModuleIntegrityResult` | `verifySignature()`、`verifyModules()`、`verifyModule()`、`directoryFingerprint()`、`hashBytes()`；`ed25519PublicKeyLength = 32` |
| `lib/kernel/boot/release_trust_root.dart` | `kOgLReleasePublicKey`、`kOgLReleasePublicKeyBase64` | 内嵌 Ed25519 公钥（v2） |
| `lib/kernel/boot/trust_policy.dart` | `BootTrustPolicy`、`ExtensionKind`、`TrustTier`、`TrustDecision` | `evaluate()`：官方核心 locked / 官方扩展 verified / 第三方主题 open / 第三方 Mod warn |
| `lib/kernel/boot/trust_warnings.dart` | `TrustWarningCollector`、`BootTrustWarning`、`BootWarningCodes`、`TrustSeverity` | `report()`、`emit()`、`addSink()`；告警码 `OGL-BOOT-101`…`108` |
| `lib/kernel/boot/boot_fs.dart` | `BootFileSystem`、`InMemoryBootFileSystem` | 抽象文件系统；`readBytes()`、`listFilesRecursive()`、`writeText()` |
| `tool/boot_manifest.py` | `canonical_json()`、`build_payload()`、`directory_fingerprint()`、`sign_payload()`、`main()` | CI 构建期生成清单并 Ed25519 签名 |
| `lib/main.dart` | `kOgLBootManifestJson`、`InMemoryBootFileSystem`、`BootLoader(...)` | 组合根；编译期注入清单、装配引导器、捕获失败 |
| `lib/kernel/kernel.dart` | `KernelBootException`、`OgLKernel.boot()` | `bootResult.succeeded == false` 时抛异常（第 196 行） |
| `lib/surface/app/og_l_app.dart` | `OgLBootFailureApp` | 拒绝启动时的兜底界面（第 155 行） |

## 2. 签名验证流程 / Signature verification flow

### 2.1 构建期 / Build time

1. `.github/workflows/build.yml` 的 `manifest` job 校验 `version_name`（正则 `^[0-9]+\.[0-9]+(\.[0-9]+)?$`）
   与 `version_number`（`^[1-9][0-9]*$`），拒绝空值与 `0.1.0` 默认值回归。
2. 从 GitHub Actions Secret `OGL_BOOT_KEY`（32 字节 seed 的 base64）还原私钥到 `$RUNNER_TEMP/ogl-boot-ed25519.key`。
3. 执行：

```bash
python3 tool/boot_manifest.py \
  --version "$VERSION_INPUT" \
  --build-id "$GITHUB_SHA" \
  --key "$RUNNER_TEMP/ogl-boot-ed25519.key" \
  --out dart_define.json
```

参数（源码 `argparse`）：`--version`（缺省读 `pubspec.yaml` 的 `version:`）、`--build-id`（默认 `local-dev`）、
`--key`（默认 `.github/signing/ogl-boot-ed25519.key`，私钥不在仓库）、`--out`（默认 `dart_define.json`）、
`--repo-root`（默认 `.`）。产物：`boot_manifest.json`（含 `signature`，`.gitignore` 覆盖）、
`dart_define.json`（`{"OGL_BOOT_MANIFEST": "<清单字符串>"}`）。

4. `sign_payload()` 用 `Ed25519PrivateKey.from_private_bytes(seed)` 对 `canonical_json(payload).encode('utf-8')` 签名，
   签完立即用 `private.public_key().verify()` 自检；签名转 base64 加到清单 `signature` 字段。
5. 各构建腿下载 `boot-manifest` artifact，并以 `--dart-define-from-file=dart_define.json` 注入编译。

### 2.2 清单内容 / Manifest fields

`build_payload()` 产出（schema 版本 1，`kSupportedManifestSchema = 1`）：

| 字段 / Field | 来源 / Source | 说明 / Note |
| --- | --- | --- |
| `schema` | 常量 `1` | Dart 侧要求 `1 <= schema <= 1` |
| `appVersion` | `--version` 或 `pubspec.yaml` | 发布时为 `inputs.version_name` |
| `buildId` | `--build-id` | CI 传 `$GITHUB_SHA` |
| `generatedAt` | UTC `%Y-%m-%dT%H:%M:%SZ` | 生成时刻 |
| `modules` | 空列表 `[]` | 核心模块是 AOT 产物，运行时无目录可指纹；逐模块目录指纹机制保留给有真实文件落地的 Mod / 主题 |
| `coreDigest` | `sha256_hex(canonical_json(core).encode())` | `core` 覆盖 `lib/kernel`、`lib/base`、`lib/domain`、`lib/surface`、`lib/platform` 的 `directory_fingerprint()` 与 `lib/main.dart` 的 `sha256_hex()`；B8-B-01 把平台门面与组合根纳入，防止装配被篡改仍验签通过 |
| `signature` | base64 Ed25519 | 覆盖**不含** `signature` 的规范化 payload |

规范化规则 / Canonical rules：键按字典序、无空白、字符串走 `jsonEncode` 转义、数字 `toString()`、数组保序；
Python `canonical_json()` 为 `json.dumps(obj, sort_keys=True, separators=(',', ':'), ensure_ascii=False)`。
两侧必须逐字节一致；改动须同步 `lib/kernel/boot/boot_manifest.dart` 的 `canonicalJsonEncode()` 并跑
`test/kernel/boot_release_chain_test.dart`。

### 2.3 启动期五阶段 / Five boot stages

`BootLoader.run()` 依次产生 `BootStage`（`name` / `ok` / `duration` / `detail`）：

| 阶段 / Stage name | 判据 / Criterion | 失败路径 / Failure |
| --- | --- | --- |
| `boot.manifest` | `fileSystem.readBytes('boot/manifest.json')` 非空且 `jsonDecode` 根节点为 `Map`、`BootManifest.fromJson()` 成功 | `_refuse()`，码 `OGL-BOOT-104`（manifestMissing） |
| `boot.self_check` | `manifest.isSchemaSupported && manifest.malformedModuleCount == 0` | `_refuse()`，码 `OGL-BOOT-104` |
| `boot.signature` | `verifier.verifySignature(manifest)` | 非旁路 → `_refuse()`，码 `OGL-BOOT-103` |
| `boot.modules` | `verifier.verifyModules(manifest, signatureValid:)` 的 `allPassed` | 失败模块进入 `excludedModules` + 安全模式，码 `OGL-BOOT-102`；不拒绝启动 |
| `boot.extensions` | `policy.evaluate(thirdPartyTheme)` / `policy.evaluate(thirdPartyMod)` 登记 | 恒 `ok: true` |
| `boot.ready` | 就绪上报，`diagnostics.info('BOOT', '引导完成', code: 'OGL-BOOT-001', ...)` | 恒 `ok: true` |

`verifySignature()` 细节：签名缺失/空、公钥长度 ≠ 32、base64 解码 `FormatException`、
`_ed25519.verify(manifest.canonicalPayloadBytes(), signature:)` 抛错——任一情况返回 `false`。
公钥来自 `kOgLReleasePublicKey`（base64 `Qaojo9YuV4nQoNbyfDiwoYofhUg/sPrKhOkDyW5DQ8s=`，v2，2026-10-02 起）。
信任根防脱节样本：`test/kernel/fixtures/release_key_signed_manifest.json`，由 `test/kernel/boot_release_chain_test.dart` 校验。

`directoryFingerprint()` 算法（Dart 与 Python 一致）：递归列文件 → 相对路径排序 → 每行
`相对路径 + '\u0000' + sha256(文件内容) + '\n'` → 对拼接结果取 sha256（小写十六进制）。
目录不存在、为空、或列完后读取消失 → 返回 `null`（判失败）。

## 3. 组合根装配与平台差异 / Composition root and platform differences

`lib/main.dart` 第 52 行：`const String kOgLBootManifestJson = String.fromEnvironment('OGL_BOOT_MANIFEST');`
第 174–198 行：创建 `InMemoryBootFileSystem()`；清单非空则 `writeText('boot/manifest.json', kOgLBootManifestJson)`；
`BootLoader(..., verifier: BootIntegrityVerifier(releasePublicKey: kOgLReleasePublicKey),
policy: const BootTrustPolicy(), manifestPath: 'boot/manifest.json',
developmentBypass: !hasSignedManifest && !kReleaseMode)`。
第 219 行 `await kernel.boot(modules, expectedBridges: {base, domain, surface})` 执行信任链。

平台差异 / Platform differences：

- Android / Windows / Linux 共用同一套 `BootLoader` + `InMemoryBootFileSystem`，清单编译期内嵌，不读磁盘；
  `boot_fs.dart` 中曾定义的 `IoBootFileSystem` 已被删除（注释明确：无人使用，避免误以为启动会读磁盘）。
- Windows / Linux 桌面产物为 Skia 渲染，预编译着色器走可选 SkSL bundle；Android 为 Impeller 构建期 AOT，
  两者与信任链本身正交，但共用同一份签名清单注入。
- `.github/workflows/build.yml` 中 macOS / iOS 自 5.6.0 起弃用，最后支持 v5.3.0；故当前发布信任链只在
  Android（arm64-v8a / armeabi-v7a / x86_64 / universal / AAB）、Windows（x64 / arm64）、Linux（x64 / arm64）产物上生效。
- 开发旁路 `developmentBypass` 仅 `!kReleaseMode` 时为真；此时清单缺失或签名无效继续启动，但必然产生
  `OGL-BOOT-107` 告警；发布构建缺清单/签名无效一律拒绝启动。

## 4. 失败路径 / Failure paths

| 条件 / Condition | 结果 / Result | 用户可见表现 / User-visible effect |
| --- | --- | --- |
| 清单缺失且非旁路 / 解析失败 / schema 不支持 / 条目损坏 | `BootResult(succeeded: false, manifest: null, integrity: null, failureReason: ...)`；`OgLKernel.boot()` 抛 `KernelBootException` | `lib/main.dart` 第 331 行 `runApp(OgLBootFailureApp(message: error.toString()))` |
| 签名无效且非旁路 | 同上，码 `OGL-BOOT-103` | 同上；原因文本「引导清单签名校验失败（应用可能被篡改）」 |
| 官方模块指纹不匹配 | `succeeded: true, safeMode: true`，`excludedModules` 列出失败 ID | 不拒绝启动；告警 `OGL-BOOT-102` + 诊断 `data` 含 `path` / `expected` / `actual` / `reason` |
| 未预期装配异常 | `lib/main.dart` 兜底 `catch` | `OgLBootFailureApp(message: '启动流程出现未预期异常：$error\n\n$stackTrace')` |

`_refuse()` 同时 `diagnostics.error('BOOT', ...)` 与 `warnings.report(...)`，返回 `BootResult` 的
`stages` 为不可修改列表、`trustWarnings` 为收集器快照。
`OgLBootFailureApp`（`lib/surface/app/og_l_app.dart:155`）是 `StatelessWidget`，
构造签名 `const OgLBootFailureApp({required this.message, super.key})`，
`build()` 返回 `MaterialApp`（`debugShowCheckedModeBanner: false`，`locale: Locale('zh','CN')`，
`supportedLocales: [Locale('zh','CN'), Locale('en')]`）。

告警码全表（`BootWarningCodes`）：`OGL-BOOT-101` 未签名第三方 Mod 已加载、
`102` 官方模块完整性失败、`103` 清单签名无效、`104` 清单缺失、`105` 第三方主题启用、
`106` 扩展被策略拒绝、`107` 开发旁路、`108` 清单声明模块未被提供。
严重级 `TrustSeverity`：`info` / `warn` / `danger`；接收方异常记入 `TrustWarningCollector.sinkErrors`，不得静默吞掉。

## 5. 信任根与密钥 / Trust root and keys

`OGL_BOOT_KEY`（Actions Secret）保存 Ed25519 私钥 seed 的 base64；仓库内只保留说明
`.github/signing/README.md`，**不存任何私钥**。v1（2026-10-01→10-02）退役，v2（2026-10-02 起）有效。
轮换红线：公钥内嵌于历史版本，轮换 = 新版本新公钥 + 新签名；历史版本各自自洽；
外部签名物（Mod / 主题清单）须用 v2 重签；私钥丢失 = 无法发布能通过启动校验的新版本。

本地演练命令（来自 `.github/signing/README.md`）：

```bash
printf '%s' "$OGL_BOOT_KEY" > /tmp/ogl-boot-ed25519.key
python3 tool/boot_manifest.py --key /tmp/ogl-boot-ed25519.key --build-id local-test
```

聚焦校验（来自 `.github/workflows/build.yml` 的「引导清单注入校验」步骤，仅 Android arm64-v8a 腿）：

```bash
flutter test --dart-define="OGL_BOOT_MANIFEST=$(python3 -c 'import json;print(json.load(open("dart_define.json"))["OGL_BOOT_MANIFEST"])')" \
  test/kernel/boot_define_injection_test.dart
```

## 6. 信任策略表 / Trust policy matrix

来自 `BootTrustPolicy.evaluate()`（`lib/kernel/boot/trust_policy.dart`）：

| 扩展种类 / Kind | 级别 / Tier | 要求签名 / Signature | 放行 / Load | 总线告警 / Warn | 用户确认 / Consent |
| --- | --- | --- | --- | --- | --- |
| `officialCore` | `locked` | 是 | 是 | 否 | 否 |
| `officialExtension` | `verified` | 是 | 是 | 否 | 否 |
| `thirdPartyTheme` | `open` | 否 | 是 | 否 | 否 |
| `thirdPartyMod` | `warn` | 否 | 是 | 是 | 否（danger 级由调用方升级为确认） |
