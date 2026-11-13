# docs · 文档目录

本目录分四类：**规范**（长期有效、裁决依据）、**设计**（结构与方案）、**审计**（一次性产物，全部登记在总索引）、**运维**（CI / 构建 / 发布）。完整审计台账见 [`AUDIT_INDEX.md`](AUDIT_INDEX.md)。

## 规范（长期有效）

| 文件 | 内容 | 读者 |
| --- | --- | --- |
| [`QUALITY_STANDARD.md`](QUALITY_STANDARD.md) | 质量标准：**59 条**原则性条款（不谈实现，裁决依据） | 贡献者 |
| [`CONSISTENCY.md`](CONSISTENCY.md) | 缓存一致性 D1–D9 权威描述：各防线语义、合法例外、失效路径 | 贡献者 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 五层架构：层职责 / 依赖方向 / 命名约定 / 自检命令 | 贡献者 |
| [`I18N.md`](I18N.md) | 多语言维护手册：新增文案 / 翻译流程 | 贡献者 |

## 设计与方案

| 文件 | 内容 | 读者 |
| --- | --- | --- |
| [`NETWORK.md`](NETWORK.md) | 网络连接总览：出口主机 / 资源取法 / 加速适用范围 / web 端限制 | 面向使用者的技术说明 |
| [`WEB_LITE_PLAN.md`](WEB_LITE_PLAN.md) | Web 版裁剪与方案 | 贡献者 |
| [`USAGE.md`](USAGE.md) | 使用说明：安装 / 登录 / 主要功能（含故障排除） | 使用者 |
| [`COLD_START.md`](COLD_START.md) | 冷启动路径说明 | 贡献者 |
| [`OAUTH_ORG_SETUP.md`](OAUTH_ORG_SETUP.md) | 组织名下 GitHub OAuth App（Device Flow）创建与 Secret 注入指引 | 维护者 |

## 审计（一次性产物，按批归档）

| 文件 | 内容 |
| --- | --- |
| [`AUDIT_PLAN.md`](AUDIT_PLAN.md) | 八批三视角交叉审计的计划（每批 A 实现 / B 安全 / C 契约，只审不改） |
| [`AUDIT_INDEX.md`](AUDIT_INDEX.md) | **九批审计总索引**：各批范围、三份报告 + 交叉结论、状态与 P0/P1 口径 |
| [`audit_b1_*.md`](AUDIT_INDEX.md) … [`audit_b8_*.md`](AUDIT_INDEX.md)、[`audit_spec_*.md`](AUDIT_INDEX.md) | 第 1–8 批与规范专项（批 9）原始记录与交叉结论，索引统一见 `AUDIT_INDEX.md` |
| [`audit_206.md`](audit_206.md) · [`audit_submit_download.md`](audit_submit_download.md) · [`audit_ui.md`](audit_ui.md) · [`audit_net_data.md`](audit_net_data.md) · [`audit_debug_empty_fail.md`](audit_debug_empty_fail.md) · [`5layer-audit-todo.md`](5layer-audit-todo.md) · [`fonts.md`](fonts.md) | 批外专项审计与遗留待办（均在 `AUDIT_INDEX.md` 登记） |

## 运维（CI / 构建 / 发布 / 整理）

| 文件 | 内容 |
| --- | --- |
| [`CI_BUILD_BASELINE.md`](CI_BUILD_BASELINE.md) | CI 实测基线（各门禁在当前基线的实测结果） |
| [`REPO_HYGIENE.md`](REPO_HYGIENE.md) | 仓库文档整理报告（2026-11，本次产出） |
| [`CONVERGENCE_STATUS.md`](CONVERGENCE_STATUS.md) | **待收敛条权威现状总表**（分层/门禁/UI/下载/DNS/供应链，实测口径） |
| [`audit_layering_principles.md`](audit_layering_principles.md) | 层级桥接与模块独立原则只读专项审查（2026-11，含路线图） |
| [`LTS_1260_CHECKLIST.md`](LTS_1260_CHECKLIST.md) | LTS 发布前验收清单（真机项留用户执行） |

## 相关文档（仓库根目录）

| 文件 | 内容 |
| --- | --- |
| [`README.md`](../README.md) | 项目介绍与功能清单 |
| [`AGENTS.md`](../AGENTS.md) | 工程总纲（分层、门禁与量化口径） |
| [`CHANGELOG.md`](../CHANGELOG.md) | 完整版本历史（新版本在前） |
| [`release_notes/`](../release_notes) | 每版本一份发布说明，中英对照；索引见 [`release_notes/README.md`](../release_notes/README.md) |
| [`LICENSE`](../LICENSE) · [`NOTICE`](../NOTICE) | Apache-2.0 许可全文与声明（随构建产物分发） |

## 约定

- **发布说明**放在根目录 [`release_notes/`](../release_notes)，每版本一个文件；
- **完整版本历史**在根目录 [`CHANGELOG.md`](../CHANGELOG.md)；
- 一次性审计报告**不删除、不移动**（历史链接很多），保留原位并由 [`AUDIT_INDEX.md`](AUDIT_INDEX.md) 统一索引；
- **新增审计报告必须同时更新 [`AUDIT_INDEX.md`](AUDIT_INDEX.md)**；
- 文档所引用的符号必须**真实存在**（改名时一并更新），路径尽量写成可点击链接。
