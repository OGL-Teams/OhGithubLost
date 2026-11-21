# docs 文档内容全面审计报告 / docs Documentation Content Audit

> **状态 / Status**：审计结论 / Audit findings（只审不改 / audit-only）
> **审计对象 / Scope**：`docs/` 下全部 81 篇 Markdown（不含根目录 `README.md`、`AGENTS.md`、`CHANGELOG.md`、`release_notes/`）
> **方法 / Method**：逐篇快审（Diátaxis 分类 → 技术细节可复现度 → 符号/路径实测核验 → 与代码对照），只读不改
> **基线 / Baseline**：HEAD `ebbbd25`（2026-11-21 16:01:16 +0800），版本 v14.0.0（`pubspec.yaml` `version: 14.0.0+140000`）

> **更新时间 / Last Updated**：2026-11-21 16:11:14　**对应版本 / Version**：v14.0.0

---

## 一、审计摘要 / Executive Summary (ZH)

本轮审计覆盖 `docs/` 下 **81 篇** Markdown。总体结论：**文档资产"多"而"未生根"——数量充足、可复现度不足、口径脱节、缺口集中**。

- **类型分布 / Mode mix**：参考型 11 篇 · 操作型 4 篇 · 阐释型 4 篇 · 计划/清单/任务书 7 篇 · 一次性审计档案 55 篇 · **教程型 0 篇**。
  真正服务"想学会用"读者的教程（tutorial）完全缺席，是最突出的结构性缺口。
- **混模式 / Mixed-mode**：3 篇明确混模式（`ARCHITECTURE.md`、`NETWORK.md`、`REPO_HYGIENE.md`），另有 4 篇隐性混模式（`I18N.md` 操作+策略、`COLD_START.md` 与 `PERF.md` 职责重叠、`AUDIT_INDEX.md` 总账+结论、`CI_BUILD_BASELINE.md` 实测+清单）。
- **技术细节可复现度 / Reproducibility rating**：**A 22 · B 39 · C 19 · D 1**。D 级仅 1 篇（`fonts.md`，核心事实已被推翻）。最严谨的 4 篇为 `CONSISTENCY.md`、`CONVERGENCE_STATUS.md`、`OAUTH_ORG_SETUP.md`、`INDEX_TRANSLATE_API.md`——均给出文件路径、符号名、参数、边界值与失败语义，可直接照做。
- **准确性 / Accuracy**：完全相符 20 篇 · 部分失准 48 篇 · 明确失准 13 篇。
  **已实测确认的硬错误 13 处**，其中直接误导读者的三处为：`I18N.md` 称"2 种语言"（实为 30 语种、28 分片）、`fonts.md` 称"assets/fonts 目录不存在"（实有 UbuntuMono 字体文件）、`REPO_HYGIENE.md` 勘误称"死链实测 0"（实测 19 处）；其余为路径与登记类硬错误（`audit_b2_b.md` 的 `gh_auth_service.dart`、`audit_b6_a.md` 的 `client_shell.dart`、`audit_layering_principles.md` 三处 `net_client.dart`、`DOCUMENT_STYLE.md` 重复标题、`UX_WRITING_AUDIT.md` 未登记等）。
- **完整性缺口 / Coverage gaps**：**12 个技术主题零文档**（含引导信任链、下载子系统、CI 门禁目录、发布运行手册、Web 发布、凭据与密钥库、主题与设计令牌、通知与权限网关等）。
- **时效性 / Freshness**：抽查 3 篇对照代码，2 篇脱节（`I18N.md`、`fonts.md`），1 篇相符（`PERF.md`/`COLD_START.md` 的启动路径与 `lib/main.dart` 逐行一致）。

---

## 二、Executive Summary (EN)

Audit scope: all **81** Markdown files under `docs/`. Findings are audit-only; no file other than this report was modified.

- **Mode mix**: 11 reference · 4 how-to · 4 explanation · 7 plan/checklist/brief · 55 one-shot audit records · **0 tutorials**.
- **Mixed-mode pages**: 3 explicit (`ARCHITECTURE.md`, `NETWORK.md`, `REPO_HYGIENE.md`), 4 implicit (operation+policy, duplicated scope, ledger+conclusion, measurement+checklist).
- **Reproducibility rating**: **A 22 · B 39 · C 19 · D 1**. The strongest pages (`CONSISTENCY.md`, `CONVERGENCE_STATUS.md`, `OAUTH_ORG_SETUP.md`, `INDEX_TRANSLATE_API.md`) are directly actionable: file paths, symbol names, parameters, boundary values and failure semantics.
- **Accuracy**: 20 fully correct · 48 partly drifted · 13 verifiably wrong; **13 hard errors confirmed by `rg`/filesystem checks**, including "2 languages" vs 30 shipped locales, and a "no fonts directory" claim contradicted by two UbuntuMono TTFs.
- **Coverage gaps**: **12 subsystems have no documentation at all**.
- **Freshness**: of 3 docs compared against code, 2 are stale, 1 is accurate.

---

## 三、逐篇评估表 / Per-file Assessment

列说明 / Columns：**类型** = Diátaxis 判定（混模式标注）；**详细度** = 面向技术人员的可复现细节密度（A 可直接照做 / B 部分可做 / C 仅抽象描述 / D 事实已被推翻）；**准确性** = 与代码现状相符（✓）/ 部分失准（△）/ 明确失准（✗）；**建议** = 该篇首要待办。

| 文件 / File | 类型 / Mode | 详细度 | 准确性 | 建议 / Recommendation |
| --- | --- | --- | --- | --- |
| [`5layer-audit-todo.md`](5layer-audit-todo.md) | 待办 / TODO | C | ✗ | 含 `docs/5layer-audit-YYYY-MM-DD.md` 模板死链；快照已过期 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 阐释+参考 混 / Mixed | A | △ | 分层视图、符号表、门禁命令齐全；但 §1–§3 阐释与 §3.2/§5 参考表混页 |
| [`AUDIT_INDEX.md`](AUDIT_INDEX.md) | 参考（总账）/ Reference | B | △ | 登记纪律明确，但漏登 UX_WRITING_AUDIT.md 等新文件 |
| [`AUDIT_PLAN.md`](AUDIT_PLAN.md) | 阐释（计划）/ Explanation | B | △ | 批次口径清楚；含 `audit_bN_…` 占位路径 |
| [`CI_BUILD_BASELINE.md`](CI_BUILD_BASELINE.md) | 参考（实测）/ Reference | A | △ | run id、秒级数据齐；但复测脚本在 /tmp（仓库外），不可复现 |
| [`COLD_START.md`](COLD_START.md) | 阐释 / Explanation | B | ✗ | 与 PERF.md §一/§三 大段重复；无端到端耗时数据 |
| [`CONSISTENCY.md`](CONSISTENCY.md) | 参考 / Reference | A | ✓ | D1–D9 事件码、边界值、合法例外齐全，最严谨一篇 |
| [`CONVERGENCE_STATUS.md`](CONVERGENCE_STATUS.md) | 参考（状态）/ Reference | A | ✓ | 逐条现状+实测口径，最接近事实的现状表 |
| [`DOCUMENT_STYLE.md`](DOCUMENT_STYLE.md) | 参考（规范）/ Reference | A | ✗ | 「三、目录职责」标题重复出现两次；与「不写死量值」条款自身冲突 |
| [`FOUR_RELEASE_ROADMAP.md`](FOUR_RELEASE_ROADMAP.md) | 计划 / Plan | C | △ | 只有意图与步骤名，无命令与验收判据 |
| [`I18N.md`](I18N.md) | 操作 / How-to | A | ✗ | 称「2 种语言」，实际 assets/i18n 有 30 语种且 pubspec 全部打包；第 3/6 节命令指向 _setup/ 本机脚本（不在仓库） |
| [`I18N_AUTONOMOUS_STATE.md`](I18N_AUTONOMOUS_STATE.md) | 状态 / Status | C | △ | 内部进度快照，无可操作内容 |
| [`I18N_DELTA_BRIEF.md`](I18N_DELTA_BRIEF.md) | 任务书 / Brief | C | △ | 给子代理的任务描述，缺验收标准 |
| [`I18N_SHARD_TRANSLATION_BRIEF.md`](I18N_SHARD_TRANSLATION_BRIEF.md) | 任务书 / Brief | B | △ | 含脚本参数，可执行 |
| [`INDEX_TRANSLATE_API.md`](INDEX_TRANSLATE_API.md) | 参考 / Reference | A | ✓ | 端点、参数、错误码、限流说明齐全 |
| [`LTS_1260_CHECKLIST.md`](LTS_1260_CHECKLIST.md) | 清单 / Checklist | B | △ | 可勾选但缺命令与期望输出 |
| [`MD3_AUDIT.md`](MD3_AUDIT.md) | 审计档案 / Audit | B | △ | 已被 V2 取代但未标失效 |
| [`MD3_AUDIT_V2.md`](MD3_AUDIT_V2.md) | 审计档案 / Audit | B | △ | 评分为自评，缺验证方法 |
| [`NETWORK.md`](NETWORK.md) | 参考+操作 混 / Mixed | A | △ | 出口清单/复现 curl 完整；但夹带「为何」章节与待办清单 |
| [`OAUTH_ORG_SETUP.md`](OAUTH_ORG_SETUP.md) | 操作 / How-to | A | ✓ | URL、字段名、Secret 名、注入方式、验证步骤齐全，可照做 |
| [`PERF.md`](PERF.md) | 阐释 / Explanation | B | △ | 档位/门禁规则具体，但无实测数字与基准来源 |
| [`QUALITY_STANDARD.md`](QUALITY_STANDARD.md) | 参考（规范）/ Reference | B | △ | 59 条原则抽象，缺「原则→实现文件」映射表 |
| [`README.md`](README.md) | 索引 / Index | B | △ | 索引四型齐备；未登记 UX_WRITING_AUDIT.md；I18N 一行被登记两次 |
| [`REPO_HYGIENE.md`](REPO_HYGIENE.md) | 报告 / Report | C | ✗ | 勘误称「当前 71 个 .md、死链实测 0」，实测 81 篇、19 处死链 |
| [`TAGS_FEATURE_PLAN.md`](TAGS_FEATURE_PLAN.md) | 计划 / Plan | B | △ | 层级目标清楚，缺实现落点文件 |
| [`USAGE.md`](USAGE.md) | 操作 / How-to | B | ✓ | 全篇按「前置条件→步骤→预期结果」组织；无命令、无截图路径 |
| [`UX_WRITING_AUDIT.md`](UX_WRITING_AUDIT.md) | 审计档案 / Audit | C | △ | 未登记于 AUDIT_INDEX.md |
| [`WEB_LITE_PLAN.md`](WEB_LITE_PLAN.md) | 计划 / Plan | C | △ | 清单式，未与当前代码对齐 |
| [`audit_206.md`](audit_206.md) | 审计档案 / Audit | B | ✓ | 206 回执专题，结论被 CONSISTENCY.md 采纳 |
| [`audit_b1_a.md`](audit_b1_a.md) | 审计档案 / Audit | A | ✓ | 文件:行号+代码证据+影响+原则编号 |
| [`audit_b1_b.md`](audit_b1_b.md) | 审计档案 / Audit | B | △ | 条目简略，无代码块佐证 |
| [`audit_b1_c.md`](audit_b1_c.md) | 审计档案 / Audit | A | ✓ | 逐条含证据 |
| [`audit_b1_cross.md`](audit_b1_cross.md) | 审计档案 / Audit | B | △ | 含建议中的 tool/net_contract_audit.py 死链 |
| [`audit_b2_a.md`](audit_b2_a.md) | 审计档案 / Audit | A | ✓ | 逐条含证据 |
| [`audit_b2_b.md`](audit_b2_b.md) | 审计档案 / Audit | A | ✗ | 引用 lib/domain/gh/gh_auth_service.dart（实为 gh_auth.dart） |
| [`audit_b2_c.md`](audit_b2_c.md) | 审计档案 / Audit | A | ✓ | 逐条含证据 |
| [`audit_b2_cross.md`](audit_b2_cross.md) | 审计档案 / Audit | B | ✗ | 引用 tool/disk_contract_audit.py（未创建） |
| [`audit_b3_a.md`](audit_b3_a.md) | 审计档案 / Audit | A | ✓ | 对照 GitHub 官方 OpenAPI 实测，证据链完整 |
| [`audit_b3_b.md`](audit_b3_b.md) | 审计档案 / Audit | B | △ | 条目短，缺复现步骤 |
| [`audit_b3_c.md`](audit_b3_c.md) | 审计档案 / Audit | A | ✓ | 逐条含证据 |
| [`audit_b3_cross.md`](audit_b3_cross.md) | 审计档案 / Audit | B | △ | 结论表有效 |
| [`audit_b4_a.md`](audit_b4_a.md) | 审计档案 / Audit | B | △ | 有结论，少量化数据 |
| [`audit_b4_b.md`](audit_b4_b.md) | 审计档案 / Audit | B | △ | 同上 |
| [`audit_b4_c.md`](audit_b4_c.md) | 审计档案 / Audit | B | ✗ | 引用了两个当时规划、未创建的契约文档（耐久性说明与引导链说明） |
| [`audit_b4_cross.md`](audit_b4_cross.md) | 审计档案 / Audit | C | △ | 仅结论速览 |
| [`audit_b5_a.md`](audit_b5_a.md) | 审计档案 / Audit | B | △ | 有文件行号，缺证据块 |
| [`audit_b5_b.md`](audit_b5_b.md) | 审计档案 / Audit | B | △ | 同上 |
| [`audit_b5_c.md`](audit_b5_c.md) | 审计档案 / Audit | B | △ | 同上 |
| [`audit_b5_cross.md`](audit_b5_cross.md) | 审计档案 / Audit | C | △ | 仅结论速览 |
| [`audit_b6_a.md`](audit_b6_a.md) | 审计档案 / Audit | B | ✗ | 引用 lib/surface/pages/client_shell.dart（实际在 lib/surface/app/） |
| [`audit_b6_b.md`](audit_b6_b.md) | 审计档案 / Audit | B | △ | 有定位，缺复现 |
| [`audit_b6_c.md`](audit_b6_c.md) | 审计档案 / Audit | B | △ | 同上 |
| [`audit_b6_cross.md`](audit_b6_cross.md) | 审计档案 / Audit | C | △ | 仅结论速览 |
| [`audit_b7_a.md`](audit_b7_a.md) | 审计档案 / Audit | B | △ | 主题/令牌条目较细 |
| [`audit_b7_b.md`](audit_b7_b.md) | 审计档案 / Audit | A | ✓ | 证据完整 |
| [`audit_b7_c.md`](audit_b7_c.md) | 审计档案 / Audit | B | △ | 有判据，缺示例 |
| [`audit_b7_cross.md`](audit_b7_cross.md) | 审计档案 / Audit | C | △ | 仅结论速览 |
| [`audit_b8_a.md`](audit_b8_a.md) | 审计档案 / Audit | C | ✗ | 篇幅过小，仅结论 |
| [`audit_b8_b.md`](audit_b8_b.md) | 审计档案 / Audit | B | △ | 门禁描述与实现对照尚可 |
| [`audit_b8_c.md`](audit_b8_c.md) | 审计档案 / Audit | B | △ | 同上 |
| [`audit_b8_cross.md`](audit_b8_cross.md) | 审计档案 / Audit | C | △ | 仅结论速览 |
| [`audit_debug_empty_fail.md`](audit_debug_empty_fail.md) | 审计档案 / Audit | B | △ | 排查记录，含现象-原因-验证，但仅限当时快照 |
| [`audit_layering_principles.md`](audit_layering_principles.md) | 审计档案 / Audit | A | ✗ | 3 处引用不存在的 lib/kernel/contract/net_client.dart（实为 net_types.dart） |
| [`audit_net_data.md`](audit_net_data.md) | 审计档案 / Audit | B | △ | 有定位与建议 |
| [`audit_spec_a.md`](audit_spec_a.md) | 审计档案 / Audit | B | ✗ | 示例路径 any_page.dart / _re.dart / NAMING.md 均为占位死链 |
| [`audit_spec_a_c_fixed.md`](audit_spec_a_c_fixed.md) | 审计档案 / Audit | C | △ | 修复清单，无验证证据 |
| [`audit_spec_b.md`](audit_spec_b.md) | 审计档案 / Audit | A | ✓ | 含代码块与量化 |
| [`audit_spec_b_fixed.md`](audit_spec_b_fixed.md) | 审计档案 / Audit | C | △ | 修复清单 |
| [`audit_spec_c.md`](audit_spec_c.md) | 审计档案 / Audit | A | ✓ | 规范一致性核对细致 |
| [`audit_spec_cross.md`](audit_spec_cross.md) | 审计档案 / Audit | B | △ | 结论表有效 |
| [`audit_submit_download.md`](audit_submit_download.md) | 审计档案 / Audit | C | △ | 结论缺复现步骤 |
| [`audit_ui.md`](audit_ui.md) | 审计档案 / Audit | C | △ | 记录过简 |
| [`audit_ui_full.md`](audit_ui_full.md) | 审计档案 / Audit | B | △ | 分类齐全，缺量化 |
| [`discover_polish_notes.md`](discover_polish_notes.md) | 审计档案 / Audit | C | △ | 逐项记录但无判据 |
| [`download_fix_notes.md`](download_fix_notes.md) | 审计档案 / Audit | C | △ | 改动记录，缺复现 |
| [`fonts.md`](fonts.md) | 决策记录 / Decision | D | ✗ | 称 assets/fonts 目录不存在，实际已有 UbuntuMono-*.ttf；「5 处 monospace」已不存在 |
| [`i18n_delta_report.md`](i18n_delta_report.md) | 审计档案 / Audit | B | ✓ | 逐键增量统计 |
| [`i18n_polish_report.md`](i18n_polish_report.md) | 审计档案 / Audit | B | ✓ | 润色前后对照 |
| [`i18n_shard_report.md`](i18n_shard_report.md) | 审计档案 / Audit | A | ✓ | 分片级统计完整 |
| [`postrelease_dns_audit.md`](postrelease_dns_audit.md) | 审计档案 / Audit | B | ✓ | 含实测命令 |
| [`postrelease_download_audit.md`](postrelease_download_audit.md) | 审计档案 / Audit | A | ✓ | 结构完整性与状态机逐条复核，可复算 |

### 3.1 分布统计 / Distribution

| 类型 / Mode | 篇数 | 占比 |
| --- | --- | --- |
| 参考型 / Reference（含规范、实测、状态总账、索引、决策记录） | 11 | 13.6% |
| 操作型 / How-to | 4 | 4.9% |
| 阐释型 / Explanation | 4 | 4.9% |
| 计划 / 清单 / 任务书 / 状态 / 待办 | 7 | 8.6% |
| 一次性审计档案 / Audit archive | 55 | 67.9% |
| **教程型 / Tutorial** | **0** | **0%** |
| **合计 / Total** | **81** | 100% |

| 详细度 / Rating | A | B | C | D |
| --- | --- | --- | --- | --- |
| 篇数 | 22 | 39 | 19 | 1 |
| 占比 | 27.2% | 48.1% | 23.5% | 1.2% |

| 准确性 / Accuracy | ✓ 相符 | △ 部分失准 | ✗ 明确失准 |
| --- | --- | --- | --- |
| 篇数 | 20 | 48 | 13 |

---

## 四、准确性抽查（5 处符号/路径/命令实测）/ Accuracy Spot-Check (5 samples)

核验手段：`rg`（源码符号）、`ls`（路径）、`python3`（目录枚举）、`git log`（时间戳）。以下 5 处为任务指定的抽样点，另附全量扫描结果。

| # | 出处 / Source | 被引用对象 / Claim | 核验命令 / Command | 结果 / Result |
| --- | --- | --- | --- | --- |
| 1 | `ARCHITECTURE.md` §4.3 | `tool/layer_audit.py` 的 `KNOWN` 白名单"现为空" | `rg -n "KNOWN" tool/layer_audit.py` → 第 71 行 `KNOWN: dict[str, set[str]] = {}` | **✅ 相符**（空字典属实，与文档表述一致） |
| 2 | `NETWORK.md` §二 | `OgLAccelScope` "共 9 类" | `rg -n "enum OgLAccelScope" -A 20 lib/surface/util/accel.dart` → 枚举成员计数 9 | **✅ 相符**（9 个枚举值） |
| 3 | `OAUTH_ORG_SETUP.md` §四 | 权限范围 `repo read:user`，写死于 `lib/domain/gh/gh_oauth_io.dart` | `rg -n "scope" lib/domain/gh/gh_oauth_io.dart` → 第 30 行 `'&scope=${Uri.encodeComponent('repo read:user')}'` | **✅ 相符**（字面一致） |
| 4 | `CONSISTENCY.md` 引言 | 权威实现文件 `lib/base/disk/disk_cache.dart` | `ls lib/base/disk/disk_cache.dart` → 存在；`rg -n "class RepositoryCache implements ConsistencyCache"` → 第 116 行 | **✅ 相符** |
| 5 | `REPO_HYGIENE.md` §二勘误 | "当前共 71 个 `.md`，相对链接死链实测 0" | `find docs -name '*.md' \| wc -l` → **81**；死链扫描脚本（该报告自带的 python 片段）→ **19 处死链** | **❌ 不符**（数量与"死链 0"两处均被推翻） |

**全量扫描的补充结论（超出 5 处抽样的部分）**：

- 死链 19 处，逐条清单：`5layer-audit-todo.md:53`（模板占位）、`AUDIT_PLAN.md:18,37`（`audit_bN_*` 变量写法）、`audit_b1_cross.md:83`（`tool/net_contract_audit.py` 未创建）、`audit_b2_b.md:521`（`lib/domain/gh/gh_auth_service.dart` 实为 `gh_auth.dart`）、`audit_b2_cross.md:34`（`tool/disk_contract_audit.py` 未创建）、`audit_b4_c.md:182,183`（两个当时规划的契约文档未创建）、`audit_b6_a.md:128`（`lib/surface/pages/client_shell.dart` 实为 `lib/surface/app/client_shell.dart`）、`audit_layering_principles.md:151,184,524`（`lib/kernel/contract/net_client.dart` 实为 `net_types.dart`）、`audit_spec_a.md:17,43,72`（示例路径）、`postrelease_download_audit.md:467`（引用 `weblite` 分支文件，主线确不存在，属分支语境）。
- 文档登记完整性：`UX_WRITING_AUDIT.md` 未被 `docs/README.md` 与 `docs/AUDIT_INDEX.md` 登记，违反 `AUDIT_INDEX.md` 与 `DOCUMENT_STYLE.md` §五第 4 条。
- 规范内部矛盾：`DOCUMENT_STYLE.md` §三标题 "## 三、目录职责 / Directory Responsibilities" **重复出现两次**；同文件 §一禁止"写死版本、文件数、测试数等量值"，而 `README.md`、`REPO_HYGIENE.md`、`NETWORK.md`、`I18N.md` 大量写死量值（"56 个 .md""71 个 .md""共 9 类""27 页"）。

---

## 五、技术人员视角的详细度评估 / Depth Assessment for Engineers

### 5.1 参考型（Reference）——是否给出可复现细节

| 文档 | 文件路径 | 类名/符号 | 命令 | 参数 | 边界值 | 失败语义 | 判定 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CONSISTENCY.md` | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | **A**（唯一缺门禁命令，可补一行 `python3 tool/…`） |
| `CONVERGENCE_STATUS.md` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **A** |
| `INDEX_TRANSLATE_API.md` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **A** |
| `ARCHITECTURE.md` | ✓ | ✓ | ✓ | ✓ | ✗ | △ | **A−**（无"何时会失败/降级"的表述） |
| `NETWORK.md` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **A**（含可跑的 `curl` 复现段） |
| `CI_BUILD_BASELINE.md` | ✓ | ✓ | ✓ | ✓ | ✓ | △ | **A−**（复测脚本在 `/tmp`，仓库外不可复现） |
| `QUALITY_STANDARD.md` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | **B**（按体例只写原则，但缺「原则→实现文件」索引） |
| `DOCUMENT_STYLE.md` | ✓ | — | — | ✓ | — | — | **A** |
| `AUDIT_INDEX.md` | ✓ | — | — | — | — | — | **B** |
| `fonts.md` | ✗ | ✗ | ✓ | ✓ | — | — | **D**（结论已被推翻） |

### 5.2 操作型（How-to）——命令是否可复制即跑、前置条件是否列全

- `OAUTH_ORG_SETUP.md`：**A**。含组织后台 URL 原文、字段名、Secret 名（`OGL_GITHUB_CLIENT_ID`）、注入方式（`--dart-define-from-file`）、验证步骤与失败分支（未配置时登录页隐藏授权按钮）。前置条件（组织所有者/管理员权限）已列。
- `I18N.md`：**C（事实层面）**。流程步骤（加键 → 改 `_t` → `sort_imports.py` → 补英文 → `i18n_scan.py --check`）结构正确，但两处关键事实错误：语言数（称 2，实为 30）、第 3/6 节命令指向 `_setup/ogl_i18n_translate.py`（**不在仓库**，读者无法执行），且 `assets/i18n/` 有 30 个目录、`og_l_i18n.dart` 声明 30 个 locale、28 个分片，文档三处口径互不一致。
- `USAGE.md`：**B**。全篇按「前置条件 → 步骤 → 预期结果」组织，结构典范；但纯 GUI 步骤，无终端命令、无具体路径/页面路由标识（如 `settings_page.dart` 的具体入口），技术读者无法据此自动化或定位。
- `I18N_SHARD_TRANSLATION_BRIEF.md`：**B**。含脚本参数，可执行；缺验收判据与失败回退。
- `REPO_HYGIENE.md`：**C**。附了可复跑的死链扫描脚本（值得保留），但脚本输出已与文中"0 死链"结论矛盾。

### 5.3 阐释型（Explanation）——是否讲清 why 而非 what

- `PERF.md`：**B**。why 讲得清楚（Impeller 构建期 AOT vs 桌面 Skia 运行时编译、为何不预置 SkSL bundle——与 GPU 驱动强相关）。缺 **what 层面的量化**：无冷启动毫秒数、无帧率/内存基准、无采集方法，读者无法判断"是否达标"。
- `COLD_START.md`：**B**。why 充分，缺 what：启动各阶段无耗时拆分，`OgLAppLog.instance.step/result` 的埋点如何读出未给。
- `ARCHITECTURE.md`：**A−**。§6「为何采用五层」「为何把 Web 推到独立分支」是全仓最好的 why 段落；但 §4.3「已全部收敛」的论证只给结论，未给"收敛前→收敛后"的对比数据。
- `AUDIT_PLAN.md` / `REPO_HYGIENE.md`：**B / C**。前者交代了批次方法论；后者解释性内容被过期数字污染。

### 5.4 混模式清单（最常见的结构缺陷）/ Mixed-mode Inventory

| 文件 | 混入的第二型 | 证据 | 建议 |
| --- | --- | --- | --- |
| `ARCHITECTURE.md` | Explanation + Reference | §1 背景 / §2 设计目标 / §6 决策记录为阐释；§3.2 各层职责表 / §5 命名约定为参考 | 拆为「架构阐释」+「分层符号参考」两篇，或将 §3.2/§5 抽出为独立的分层符号参考章节（本文建议，暂以内联形式保留在 ARCHITECTURE.md） |
| `NETWORK.md` | Reference + Explanation + 任务清单 | §一/§三 为事实表；§三.2「实测依据」为阐释；§七 为待办清单 | 将 §七 待办移入 `AUDIT_INDEX.md` 或 `CONVERGENCE_STATUS.md`；§三.2 归入阐释 |
| `REPO_HYGIENE.md` | 报告 + 索引 + 纪律 | §一 统计、§二 死链、§五 已整理、§七 纪律四种职能并存 | 拆为「现状勘误」与「历史记录」两段，或整体降级为审计档案并入 `AUDIT_INDEX.md` |
| `I18N.md` | How-to + Reference + Policy | §3/§4 步骤为操作；§1 结构表与 §5 门禁表为参考；§5「界面文案判定范围」为策略 | 保留操作型，把 §1/§5 抽为 `I18N_REFERENCE.md` |
| `COLD_START.md` / `PERF.md` | 职责重叠 | 两篇 §一 启动路径逐行相同，§三 着色器表相同 | 二选一：`PERF.md` 留性能，`COLD_START.md` 并入或改写为专项 |
| `CI_BUILD_BASELINE.md` | Reference + Checklist + 复盘 | 末段「验证纪律」为纪律条款 | 纪律条款并入 `AGENTS.md`，正文只留实测数据 |
| `AUDIT_INDEX.md` | 总账 + 结论 | 「各批 P0/P1 口径」含结论 | 结论回指各 cross 报告，只留计数与路径 |

---

## 六、完整性缺口 / Coverage Gaps

以下技术主题在 `docs/` 下**零文档**（仅有散见于审计报告的片段，不构成可查阅文档）：

| # | 缺失主题 | 代码位置（真实存在） | 影响 |
| --- | --- | --- | --- |
| 1 | **引导信任链 / Boot manifest 与 Ed25519 验签** | `lib/kernel/boot/`（`boot_loader.dart`、`integrity_verifier.dart`、`release_trust_root.dart`、`trust_policy.dart`）、`tool/boot_manifest.py` | 最高风险子系统（发布安全）无任何操作/参考文档，无法审计签名产物与信任根轮换 |
| 2 | **下载子系统**（分片、断点、并发、落盘裁决） | `lib/domain/ix/ix_download.dart`（1641 行）、`lib/base/net/range_download.dart`、`lib/kernel/contract/download_engine.dart` | 已有 4 篇审计报告，但无面向工程师的设计/参数文档；`kOgLAccelMinBytes` 等阈值无处可查 |
| 3 | **CI 门禁总目录**（11+ 道门禁各自的判据与白名单） | `tool/` 下 25 个 `*_audit.py`、`gate_of_gates.py`、`ci_config_audit.py` | 门禁是本仓库的核心质量机制，却无「哪道门禁查什么、怎么跑、如何合法豁免」的参考页 |
| 4 | **发布运行手册**（发版 → 校验 → 产物 → 发布说明 → 发布） | `.github/workflows/build.yml`、`release-verify.yml`、`release_notes/sync_releases.py` | 只有 `FOUR_RELEASE_ROADMAP.md`（意图）与 `LTS_1260_CHECKLIST.md`（清单），缺命令级 runbook；事故时无人可依 |
| 5 | **凭据与密钥库**（`DiskVault`、脱敏、退出登录清理） | `lib/base/disk/`（`DiskVault`）、`QUALITY_STANDARD.md` 第 39 条仅原则 | 凭据处理是安全底线，仅在审计报告里被提及 |
| 6 | **通知与权限网关** | `lib/surface/app/permissions.dart`、`system_notifier.dart` | 用户可见的权限失败路径无文档 |
| 7 | **主题与设计令牌**（令牌定义、MD3 映射） | `assets/theme_packs/`、`lib/surface/` 主题层、`assets/mods/` | 令牌是 UI 单一真相，无参考页 |
| 8 | **Web 版发布与限制** | `.github/workflows/web.yml`、`tool/web_publish.py`、`lib/domain/ix/ix_download_backend_io.dart` | `NETWORK.md` 只覆盖浏览器端限制，未覆盖构建/发布 |
| 9 | **缓存 D1–D9 的调用侧接入示例** | `lib/base/disk/disk_cache.dart` | `CONSISTENCY.md` 讲语义不讲「怎么调」 |
| 10 | **数据模型 / 领域对象字典**（DTO、状态枚举、错误码全表） | `lib/domain/`（`ix_task.dart`、`ix_conflict.dart`、`ix_error.dart`） | 无 reference 表，新人无法知道有哪些状态 |
| 11 | **版本号与发布产物追溯**（指纹、签名、证书校验链） | `tool/verify_apk_cert.py`、`tool/version_sync.py`、`lib/kernel/boot/release_trust_root.dart` | `QUALITY_STANDARD.md` 第 46 条要求"可追溯"，但无任何实现说明 |
| 12 | **贡献与社区健康基线**（`SECURITY.md` / `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md`） | 仓库根目录**均不存在** | 文档基线缺失：漏洞私下报告渠道、贡献流程、行为准则三项皆无 |

---

## 七、时效性抽查（3 篇对照代码）/ Freshness Check (3 docs vs code)

| 文档 / Doc | 文档戳 / Stamp | 对照代码 / Code compared | 结论 |
| --- | --- | --- | --- |
| `I18N.md` | 2026-11-02 22:58:45 · v14.0.0 | §1「**2 种语言**：zh / en」；§6「27 页一并处理」 → 实测 `assets/i18n/` **30 个语种目录**，`lib/surface/i18n/og_l_i18n.dart` `locales` 声明 **30** 项、`pages` **28** 项，`pubspec.yaml` 逐项打包 **30** 个语种目录 | **❌ 脱节**：核心事实错误。读者按此操作只会改 zh/en 两个分片，其余 28 语种必然不同步；§3/§6 给出的 `_setup/ogl_i18n_translate.py` 也不在仓库 |
| `fonts.md` | 2026-11-02 22:58:45 · v14.0.0 | §结论「`find assets/fonts -type f` → 无结果（`assets/fonts/` 目录不存在）」、「`fontFamily: 'monospace'`（5 处）」 → 实测 `assets/fonts/` **存在**，含 `UbuntuMono-Bold.ttf`、`UbuntuMono-Regular.ttf`；全仓 `monospace` 字面 **0 处** | **❌ 脱节**：结论与现状相反（已引入自托管字体，CDN 加速议题已自动失效），文档却仍给出 google_fonts 接入方案 |
| `PERF.md` / `COLD_START.md` | 2026-11-02 22:58:45 · v14.0.0 | §一 启动路径 7 步 vs `lib/main.dart` 第 79 `runApp(const OgLBootSplash())` → 83 `OgLLogFile.init` → 205 `baseLayerModulesOnPlatform()` → 219 `kernel.boot` → 300 `runApp(OgLApp…)` → 309-313 `ogLRunPermissionSelfTest(...).timeout(const Duration(seconds: 5))` | **✅ 相符**（顺序、超时 5 秒、fire-and-forget 全部一致）。唯一小瑕：两篇称"`runApp` 之前有四段 `await`"，而代码中权限自检在 `runApp(OgLApp)` **之后**，实为三段 |

补充：文档戳本身合规（81 篇全部带「更新时间（精确到秒）+ 对应版本」引用块，符合 `DOCUMENT_STYLE.md` §一）；但**戳不随内容自动更新**——`I18N.md`、`fonts.md` 戳为 2026-11-02，内容对应的却是 v8.2.0 / 2 语种时代的现实，说明「戳」只反映撰写时刻，未反映内容所描述的代码版本。

---

## 八、Top 10 修复建议（按影响排序）/ Top-10 Remediation (ordered by impact)

| 序 | 目标文件 / Target | 缺什么 / What is missing | 影响 / Impact | 建议动作 / Action |
| --- | --- | --- | --- | --- |
| 1 | `docs/I18N.md` | 语言口径（2 → 30）、分片数（27 → 28）、翻译脚本路径（`_setup/` 在仓库外） | **高**：多语言维护流程按此执行会漏改 28 个语种 | 改写 §1 为「30 语种、28 分片」，§3/§6 的翻译命令改指仓库内 `tool/i18n_translate.py` / `tool/i18n_shard_check.py`（两者已存在），并在 §5 门禁表补 `python3 tool/i18n_shard_check.py` |
| 2 | 新建 `docs/BOOT_TRUST_CHAIN.md` | 引导信任链（Ed25519 验签、信任根、`boot_manifest.py`、发布产物校验）零文档 | **高**：发布安全核心无文档，无法审计也无法应急 | 按「参考」型新建：符号表 + 信任根生成/轮换命令 + 失败模式（验签失败的界面表现 `OgLBootFailureApp`）+ 复现命令 |
| 3 | 新建 `docs/RELEASE_RUNBOOK.md` | 发版流程零 runbook（build → release-verify → 产物 → `release_notes/` → 发布） | **高**：发版是最高频的高风险操作，现有只有意图与清单 | 命令级 runbook：触发方式、产物命名、证书校验（`tool/verify_apk_cert.py`）、`release_notes/sync_releases.py`、回滚与失败处置 |
| 4 | 新建 `docs/GATES_REFERENCE.md` | 25 个门禁脚本的判据、白名单与豁免流程无目录 | **高**：贡献者不知道会被哪道门禁拦、也不知道如何合法豁免 | 逐门禁一表：脚本路径、检查对象、典型失败输出、豁免登记位置；附 `tool/gate_of_gates.py` 的总入口 |
| 5 | `docs/fonts.md` | 核心结论已被推翻（`assets/fonts/` 现有 UbuntuMono 字体） | **中高**：读者按此安装 google_fonts 会与现有字体冲突 | 整篇重写为「字体现状决策」：现用字体文件、加载路径、为何不接 CDN；删除 google_fonts 备查段或明确标注为历史 |
| 6 | `docs/REPO_HYGIENE.md` | 勘误数字错误（71 → 81 篇）、"死链实测 0" 与实测 19 处矛盾 | **中**：该文是文档域的权威入口，其失准会连带误导全库审计 | 按 `DOCUMENT_STYLE.md` §四更新勘误段，改为"链接检查以实测为准"；删除失效数字 |
| 7 | `docs/ARCHITECTURE.md` | 混模式；缺"何时会失败/降级" | **中**：读者拿到分层规则但不知边界 | 将 §3.2 分层职责表与 §5 命名约定抽为独立参考篇（后续补），ARCHITECTURE.md 先保留阐释与决策 |
| 8 | `docs/NETWORK.md` | 混模式；§七 待办混在参考正文 | **中**：待办被当作事实引用 | §七 迁至 `CONVERGENCE_STATUS.md`；§三.2 独立为阐释段并加标题 |
| 9 | `docs/PERF.md` + `docs/COLD_START.md` | 无任何量化（冷启动毫秒、帧率、内存）；两篇内容重复 | **中**：性能文档无法支撑"是否达标"的判断 | 二选一保留一篇；补「指标 → 采集命令 → 当前值 → 目标值」四列表，数值以 `OgLAppLog` 实测填入 |
| 10 | 仓库根目录 | 缺 `SECURITY.md`、`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md` | **中**：文档基线不完整，安全问题无私下报告渠道 | 各新建一篇（`SECURITY.md` 写私下报告邮箱与响应时限；`CONTRIBUTING.md` 写环境、分支、门禁、PR 描述要求；`CODE_OF_CONDUCT.md` 采纳 Contributor Covenant 并指向联系方式） |

---

## 九、审计方法与可复跑命令 / Method and Reproducible Commands

```bash
# 1) 文档清单与数量
find docs -name '*.md' | sort | wc -l

# 2) 死链实测（沿用 REPO_HYGIENE.md 的扫描脚本）
python3 - <<'EOF'
import re, os, glob
pats = re.compile(r'(docs/[\w\-./]+\.md|lib/[\w\-./]+\.dart|tool/[\w\-./]+\.py)')
for f in sorted(glob.glob('docs/*.md')):
    for i, line in enumerate(open(f, encoding='utf-8'), 1):
        for m in pats.findall(line):
            if not os.path.exists(m):
                print(f, i, m)
EOF

# 3) 语种数与分片数（核对 I18N.md 的事实）
ls assets/i18n | wc -l          # 30
ls assets/i18n/zh | wc -l       # 28
rg -c "OgLLocale\('" lib/surface/i18n/og_l_i18n.dart

# 4) 字体现状（核对 fonts.md 的事实）
ls assets/fonts; rg -n "monospace" lib/ -g '*.dart' | wc -l

# 5) 分层白名单现状（核对 ARCHITECTURE.md 的事实）
rg -n "KNOWN: dict|ALLOW" tool/layer_audit.py
```

## 十、审计声明 / Audit Statement

- 本轮为**只读审计**：除新增本文件外，未修改任何 `docs/`、`lib/`、`assets/`、`tool/` 文件；未执行 `git commit` / `git push`。
- 全部结论均来自上述可复跑命令与源码实读，未依据印象判断；抽样之外的扫描结果已单列并标明命令。
- 历史审计报告（`audit_b*`、`audit_spec_*`、`postrelease_*` 等 55 篇）按 `DOCUMENT_STYLE.md` §四「历史分界」不作追溯改写，本报告对其的批评仅用于说明**存量口径**与**当前事实**的差距，不主张批量重写。
- 本报告登记于 `docs/AUDIT_INDEX.md` 与 `docs/README.md` 的义务由后续维护者履行（本次审计不修改索引，以遵守「只审不改」约束）。
