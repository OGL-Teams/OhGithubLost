# 门禁脚本参考 / Gate Scripts Reference

> 状态 / Status：参考（Reference） · 面向技术人员 / For engineers
> 范围 / Scope：`tool/*_audit.py`、`changed/check_content.py`、`tool/gate_of_gates.py` 及配套检查脚本

> **更新时间 / Last Updated**：2026-11-21 16:14:39　**对应版本 / Version**：v14.0.0

本目录逐项给出：名称、扫描对象、判据、退出语义。所有参数取自各脚本 `--help` 与源码；
未实现 `--help` 的脚本（如 `contrast_audit.py`）按源码记录。
Names, scan targets, criteria and exit semantics are extracted from each script's `--help` and source.

## 1. 核心门禁 / Core gates

| 名称 / Name | 命令 / Command | 扫描什么 / Scans | 判据 / Criterion | 退出语义 / Exit |
| --- | --- | --- | --- | --- |
| 分层审计 / layer | `python3 tool/layer_audit.py --fatal` | `lib/**/*.dart`（含 `platform/`），相对 import/export 目标 | `surface→domain→base→kernel` 只许向下；`platform/` 只许 kernel；装配根/类型门面 `domain/domain_bridge.dart`、`surface/surface_bridge.dart`、`surface/types.dart` 豁免；`KNOWN` 白名单为空；`--lib` 可指定根目录 | 违规>0 且 `--fatal`→**1**；扫描 0 文件→**1**（空扫即失败）；否则 0。输出「文件总数：」 |
| 结构契约 / contract | `python3 tool/contract_audit.py --fatal` | `lib/` 四层文件头、相对 export/import、`defaultTargetPlatform`、`docs/` 活文档引用、`main.dart` 装配顺序 | ① 指向不存在文件/向上导出 ② 层级头 L0–L3 与 `platform` 前缀（豁免 `HEADER_EXEMPT`） ③ 平台判定仅 `PLATFORM_ALLOW` ④ 活 docs 中 `docs/[A-Z0-9_.-]+\.md` 引用须存在（跳过 `audit_*.md` 与占位符） ⑤ 模块装配层序单调不减 | 合计>0 且 `--fatal`→1；否则 0。输出「合计：」 |
| 门面类型面 / facade | `python3 tool/facade_audit.py --fatal` | `lib/surface/types.dart`、`surface_bridge.dart`、`domain/domain_bridge.dart` | `types.dart` export 须带 show/hide，`SERVICE_WORDS` 服务类不得新增（基线 `IxPresign`）；bridge 公开字段类型不得越 `LEGACY_BRIDGE_FIELDS`；domain `late final` 实现类不得越 `LEGACY_DOMAIN_FIELDS` | 问题>0 且 `--fatal`→1；否则 0 |
| 门禁之门禁 / gof gating | `python3 tool/gate_of_gates.py --fatal` | 临时空 CWD 下调用 12 支门禁 + 反向注入 | 每支 exit=0 且输出含证据关键字；禁「文件总数：0」空扫；反向验证 `layer_audit --lib <空目录>` 必须失败、`i18n_scan` 对 dict 值必须失败 | 任一问题且 `--fatal`→1；否则 0 |
| i18n 扫描 / i18n | `python3 tool/i18n_scan.py --check` | `lib/**/*.dart` 中文字面量 + `assets/i18n/` + `pubspec.yaml` | 界面文案 0 未本地化；分片键集合与 zh 一致；值必须字符串；locales/目录/pubspec 三处一致。`--allowlist` 文件豁免；`--json` 导出清单 | `--check` 任一失败→1；通过/报告模式→0。输出「语言清单一致」 |
| 版本一致性 / version | `python3 tool/version_sync.py`（`--fix` 用 pubspec 改写 main.dart） | `pubspec.yaml` `version:`、`lib/main.dart` `kOgLAppVersion`、`README.md`/`AGENTS.md` 前 8 行 | 正则 `^version:\s*(\d+\.\d+\.\d+)` 与 `kOgLAppVersion = '...'` 相等；文档头无 `v\d+\.\d+\.\d+` | 不一致或写死→1（有 `--fix` 则先改写再仍返回 1 提示确认）；读不到→**2**；一致→0 |
| 内容门禁 / check_content | `python3 changed/check_content.py --check`（`--fatal` 等价别名） | `changed/_content/*.md`（跳过 `_` 开头） | 禁止行内代码、`.dart`、`lib/`、`test/`、下划线/驼峰标识符、开发流程词（CI/CD/PR/commit 等）、内部机制词（SSE/SDK/token/cache 等）、`v\d+.`、感叹号结尾、人称「我们/你/大家」；`PROPER_NOUNS` 白名单（macOS/iOS/GitHub 等） | 有可疑表述→1；无→0 |
| CI 配置 / ci_config | `python3 tool/ci_config_audit.py --fatal` | `.github/workflows/*.yml`（需 PyYAML，缺→**2**） | YAML 可解析且有 `jobs`；缓存路径不写死绝对路径、不缓存 runner 只读 SDK `/ndk`、`/cmake`；缓存键绑定 `pubspec.yaml` 或 `FLUTTER_VERSION`；cache/save 有 matrix 独占条件；发布压缩并行（有 `&` + `wait`） | 问题>0 且 `--fatal`→1；否则 0 |
| Action 钉版 / action_pin | `python3 tool/action_pin_audit.py --fatal` | workflow 中 `uses:` | 必须有版本、禁 `@main|master|HEAD|latest`、须在 `ALLOWED` 基线（9 项官方 major tag）；本地 action / docker:// 跳过 | 问题>0 且 `--fatal`→1；否则 0 |
| 动效分级 / motion | `python3 tool/motion_audit.py --fatal` | `lib/surface/**/*.dart` | 禁硬编码 `Duration(...)`（仅等待提示词/`motion-allow:` 豁免）、隐式动效组件、缩放/模糊、`Curves.linear`；白名单 `app/motion.dart`、`app/animations.dart` | 违规>0 且 `--fatal`→1；否则 0。输出「扫描」 |
| 动效覆盖 / motion_coverage | `python3 tool/motion_coverage_audit.py --fatal` | `lib/surface/**/*.dart` | 裸 `AnimatedOpacity/Container/Size/...` 的 duration 须走 `OgLAnim`/`Duration.zero`；`OgLReveal(`/`OgLSurfaceSwitch(`/`OgLAnim.enabled(` 消费点 ≥ `MIN_CONSUMERS = 10` | 问题>0 且 `--fatal`→1；否则 0 |
| UI 令牌 / ui | `python3 tool/ui_audit.py --fatal` | `lib/**/*.dart` | 裸 `EdgeInsets`/`SizedBox`/`BorderRadius`/`fontSize` 须在 `SPACE_SCALE`/`RADIUS_SCALE`；字面色须 `colorScheme`/`OgLSemanticColors`；曲线仅 `CURVES_ALLOWED`；`ALLOW` 登记例外须写理由 | 命中>0 且 `--fatal`→1；否则 0 |
| 性能反模式 / perf | `python3 tool/perf_audit.py --fatal` | `lib/surface/**/*.dart` | 报告急加载长列表（含 `for (` 的 `ListView(`）、`shrinkWrap: true`、宽 `MediaQuery.of(context)`、`Opacity(`、四类 saveLayer（`BackdropFilter`/`ImageFilter.blur`/`ColorFiltered`/`ShaderMask`）；**fatal 仅**未登记 `SHADER_ALLOW` 的 saveLayer + 未登记 `ALLOW` 的 shrinkWrap/宽 MediaQuery | 有 fatal 命中且 `--fatal`→1；否则 0 |
| 语义色对比度 / contrast | `python3 tool/contrast_audit.py` | `lib/surface/theme.dart` 的 `OgLSemanticColors` | WCAG 2.1：on*/Container 底 ≥4.5:1；success/warning/info 对 surface ≥3.0:1；信息色缺省按 `#0969DA` 近似 | 问题>0→1（无参数）；否则 0。输出「语义色对比度审计」 |

## 2. 辅助检查与工具 / Supporting checks

| 名称 / Name | 命令 / Command | 扫描什么 / Scans | 判据 / Criterion | 退出语义 / Exit |
| --- | --- | --- | --- | --- |
| import 排序 / sort_imports | `python3 tool/sort_imports.py --dry-run --fatal` | Dart import 分组（`dart:` / `package:` / 相对） | 检测可排序块；`--dry-run` 不写盘，`--fatal` 有待排序块→1 | 0 = 已规范；1 = 需排序 |
| 格式护栏 / dart format | `dart format --language-version=3.6 --set-exit-if-changed --output=none lib test` | `lib/` + `test/` Dart 源文件 | 有格式差异即非零；CI 不读 `analysis_options.yaml` | 0 = 一致；非 0 = 需格式化 |
| 统计图表自检 / stats_chart | `python3 tool/stats_chart.py --selftest` | 坐标系 / 刻度 / 降采样逻辑 | `--selftest` 内置自检；常规参数 `--repo`、`--history`、`--out-dir`、`--max-points` | 自检失败→1；通过→0 |
| 注入器自检 / inject selftest | `python3 tool/inject_platform_spec_selftest.py` | Android/Windows/Linux 平台文件注入 | 幂等性、缺 `why` 拒绝、Kotlin DSL 语法、权限位；无 `argparse` 参数 | 失败→1；通过→0 |
| APK 证书 / verify_apk_cert | `python3 tool/verify_apk_cert.py --apk <apk> --keystore <jks> [--storepass android] [--alias androiddebugkey]` | APK 签名块证书 vs keystore 证书 | 从 `keytool -exportcert -rfc` 取期望 DER，与实际签名块 DER 比对并打印 SHA-256 | 0 = 证书一致；1 = 不一致或解析失败 |
| 静态分析 / analyze | `flutter analyze --fatal-infos --fatal-warnings` | 全仓 Dart | info / warning 即失败 | 0 = 无问题；非 0 = 有诊断 |
| 单元测试 / test | `flutter test --reporter expanded` | `test/` 全量 | 任一测试失败即失败 | 0 = 全通过；非 0 = 有失败 |
| 发版门禁 / generate_posts | `python3 changed/generate_posts.py [--content-dir DIR] [--releases FILE]` | `changed/_content/<tag>.md` + `changed/releases.json` | 只为 `releases.json` 中 `v` 开头版本生成 `_posts`；先清空旧文章；正文缺失打 `[缺失]` | 已发布版本缺正文→1；全部生成→0 |

## 3. CI 实际执行顺序 / CI execution order

`.github/workflows/ci.yml` 的 quality job 按顺序执行上述门禁（每步失败写入 `/tmp/strict_failures.txt`，
终审统一 fail）：`layer_audit` → `contract_audit` → `gate_of_gates` → `facade_audit` →
`action_pin_audit` → `motion_coverage_audit` → `ci_config_audit` → `version_sync` →
`i18n_scan --check` → `motion_audit` → `ui_audit` → `perf_audit` → `stats_chart --selftest` →
`inject_platform_spec_selftest` → `dart format` → `sort_imports --dry-run --fatal` →
`check_content --check` → `flutter analyze` → `flutter test` → 严格模式终审。

`build.yml`（发布构建）额外执行：Android ABI 产物版本号护栏（`aapt dump badging`）、
网络权限护栏（UTF-16LE 扫描 `INTERNET` 等）、`verify_apk_cert.py`、
`test/kernel/boot_define_injection_test.dart`（仅 arm64-v8a 腿）。

本地最小自检 / Minimal local self-check：

```bash
python3 tool/gate_of_gates.py --fatal
python3 tool/version_sync.py
python3 tool/i18n_scan.py --check
python3 changed/check_content.py --check
```

## 4. 已知门禁缺口 / Known gate gaps

- 截至本文戳记时间，`python3 tool/gate_of_gates.py --fatal` 实测 **exit 1**：
  `contract_audit exit=1`（其 `check_doc_refs()` 命中 `docs/DOCS_CONTENT_AUDIT.md` 中 4 处未落地的
  规划文档引用：`ARCHITECTURE_REFERENCE.md`、`BOOT.md`、`GATES.md`、`DURABILITY.md`）。
  其中 `docs/BOOT_TRUST_CHAIN.md`、`docs/RELEASE_RUNBOOK.md`、`docs/GATES_REFERENCE.md` 已在本次文档任务中补齐。
  审计报告中另有 `ARCHITECTURE_REFERENCE.md`、`BOOT.md`、`GATES.md`、`DURABILITY.md`
  四个未落地规划文件名；本文仅在清单中转述文件名，不构成契约引用，避免活文档新增死链。
  本次任务范围限定为「不动其他文档」，故未修改审计报告。复跑命令：`python3 tool/contract_audit.py --fatal`。
- `contrast_audit.py` 无 `argparse`，不接受 `--fatal`；始终按问题数返回 0/1。
- `i18n_shard_check.py` 内 `ROOT='/root/OhGithubLost'` 为绝对路径常量，换路径需改源码（待核实）。
- 审计脚本共 10 支 `*_audit.py`（`action_pin` / `ci_config` / `contract` / `contrast` / `facade` /
  `layer` / `motion` / `motion_coverage` / `perf` / `ui`）；审计所述「25 个门禁脚本」含全部
  `tool/*.py`，非仅 `*_audit.py`。
