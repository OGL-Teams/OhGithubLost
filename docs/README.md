# docs · 文档目录 / Documentation Index

> 本索引是文档域唯一入口，按 **Diátaxis 四型**组织：**教程 / Tutorial**（照做即成）、
> **操作 / How-to**（完成任务）、**参考 / Reference**（事实查询）、**阐释 / Explanation**（理解设计）。
> 历史审计报告不属四型，归**审计档案**类，全部登记于 [`AUDIT_INDEX.md`](AUDIT_INDEX.md)。
> 状态标注 / Status marks：✅ 现行有效 · 🕒 状态快照（结论有日期，引用前先核对现状）。

> **更新时间 / Last Updated**：2026-11-19 21:32:49　**对应版本 / Version**：v14.0.0

## 规范 / Normative（长期裁决依据，本域最高权威）

| 文件 / File | 类型 / Type | 状态 / Status |
| --- | --- | --- |
| [`DOCUMENT_STYLE.md`](DOCUMENT_STYLE.md) | 文档体例契约 / Style contract | ✅ 自 v12.6.10 生效 |
| [`QUALITY_STANDARD.md`](QUALITY_STANDARD.md) | 质量原则（参考） / Reference | ✅ |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 架构说明（阐释+参考） / Explanation+Reference | ✅ 2026-11-19 修订（KNOWN 归零） |
| [`CONSISTENCY.md`](CONSISTENCY.md) | 缓存一致性 D1–D9（参考） / Reference | ✅ |
| [`I18N.md`](I18N.md) | i18n 维护手册（操作） / How-to | ✅ |
| [`AUDIT_INDEX.md`](AUDIT_INDEX.md) | 审计总账（参考） / Reference | ✅ 持续登记 |
| [`CONVERGENCE_STATUS.md`](CONVERGENCE_STATUS.md) | 待收敛条现状总表（参考） / Reference | 🕒 实测快照 |

## 使用者文档 / User-facing

| 文件 | 类型 / Type | 状态 / Status |
| --- | --- | --- |
| [`USAGE.md`](USAGE.md) | 使用说明（教程+操作） / Tutorial+How-to | ✅ |
| [`NETWORK.md`](NETWORK.md) | 网络出口与加速（参考） / Reference | ✅ |
| [`PERF.md`](PERF.md) | 性能三线现状（阐释） / Explanation | ✅ |
| [`COLD_START.md`](COLD_START.md) | 冷启动路径（阐释） / Explanation | ✅ |
| [`OAUTH_ORG_SETUP.md`](OAUTH_ORG_SETUP.md) | OAuth App 创建指引（操作） / How-to | ✅ |
| [`I18N.md`](I18N.md) | 新增文案与页面（操作） / How-to | ✅ |

## 计划与状态 / Plans & Status（一次性或周期性产物）

| 文件 | 类型 / Type | 状态 / Status |
| --- | --- | --- |
| [`FOUR_RELEASE_ROADMAP.md`](FOUR_RELEASE_ROADMAP.md) | v13.x→v14 发布路线（操作计划） / Plan | 🕒 2026-11-19 |
| [`TAGS_FEATURE_PLAN.md`](TAGS_FEATURE_PLAN.md) | Tags 功能分层计划 / Plan | ✅ 双语正式 |
| [`WEB_LITE_PLAN.md`](WEB_LITE_PLAN.md) | Web 版裁剪方案 / Plan | ✅ |
| [`LTS_1260_CHECKLIST.md`](LTS_1260_CHECKLIST.md) | LTS 12.6.0 验收清单 / Checklist | 🕒 发布前快照 |
| [`CI_BUILD_BASELINE.md`](CI_BUILD_BASELINE.md) | CI 实测基线 / Status snapshot | 🕒 实测快照 |
| [`MD3_AUDIT.md`](MD3_AUDIT.md) | MD3 审计 V1（90/100） / Audit | 🕒 已被 V2 取代 |
| [`MD3_AUDIT_V2.md`](MD3_AUDIT_V2.md) | MD3 审计 V2（97/100，HEAD `03767f4`） / Audit | 🕒 2026-11-19 现行 |
| [`REPO_HYGIENE.md`](REPO_HYGIENE.md) | 文档整理报告 / Historical report | 🕒 含勘误注记 |

## 翻译管线 / Translation pipeline（子代理任务书与报告）

| 文件 | 说明 |
| --- | --- |
| [`INDEX_TRANSLATE_API.md`](INDEX_TRANSLATE_API.md) | B 站 Index-Translate API 契约（机翻管线调用方文档，双语正式） |
| [`I18N_AUTONOMOUS_STATE.md`](I18N_AUTONOMOUS_STATE.md) · [`I18N_DELTA_BRIEF.md`](I18N_DELTA_BRIEF.md) · [`I18N_SHARD_TRANSLATION_BRIEF.md`](I18N_SHARD_TRANSLATION_BRIEF.md) | i18n 迭代状态与子代理任务书（一次性） |
| [`i18n_delta_report.md`](i18n_delta_report.md) · [`i18n_polish_report.md`](i18n_polish_report.md) · [`i18n_shard_report.md`](i18n_shard_report.md) | i18n 增量 / 润色 / 分片翻译报告（一次性，未入总账，见下「删除建议」） |

## 审计档案 / Audit archive（历史记录，按契约不改写）

九批 + 规范专项 + 批外专项：见 [`AUDIT_INDEX.md`](AUDIT_INDEX.md)（`audit_b1_*` … `audit_b8_*`、`audit_spec_*`、`postrelease_*`、`audit_ui_full.md`、`audit_206.md` 等）；
批外修复笔记：[`discover_polish_notes.md`](discover_polish_notes.md)、[`download_fix_notes.md`](download_fix_notes.md)；遗留待办：[`5layer-audit-todo.md`](5layer-audit-todo.md)、[`fonts.md`](fonts.md)。

## 相关文档（仓库根目录）

| 文件 | 内容 |
| --- | --- |
| [`README.md`](../README.md) | 项目介绍与功能清单 |
| [`AGENTS.md`](../AGENTS.md) | 工程总纲（分层、门禁与量化口径） |
| [`CHANGELOG.md`](../CHANGELOG.md) | 完整版本历史（新版本在前） |
| [`release_notes/`](../release_notes) | 每版本一份发布说明，中英对照；索引见 [`release_notes/README.md`](../release_notes/README.md) |
| [`LICENSE`](../LICENSE) · [`NOTICE`](../NOTICE) | Apache-2.0 许可全文与声明（随构建产物分发） |

## 约定

- **发布说明**放在根目录 [`release_notes/`](../release_notes)，每版本一个文件；完整版本历史在根目录 [`CHANGELOG.md`](../CHANGELOG.md)；
- 一次性审计报告**不删除、不移动**（历史链接很多），保留原位并由 [`AUDIT_INDEX.md`](AUDIT_INDEX.md) 统一索引；**新增审计报告必须同时更新该总账**；
- 文档所引用的符号必须**真实存在**（改名时一并更新），路径写成可点击链接；不写死版本 / 计数等量值，以工具实测为准（见 [`DOCUMENT_STYLE.md`](DOCUMENT_STYLE.md)）；
- 新增文档先判定本表归属（含类型标注），再落盘。
