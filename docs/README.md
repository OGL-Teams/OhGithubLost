# docs · 文档目录

| 文件 | 内容 | 读者 |
| --- | --- | --- |
| [`USAGE.md`](USAGE.md) | 使用说明：安装 / 登录 / 主要功能 | 使用者 |
| [`NETWORK.md`](NETWORK.md) | 网络连接总览：出口主机 / 资源取法 / 加速适用范围 / web 端限制 | 面向使用者的技术说明 |
| [`I18N.md`](I18N.md) | 多语言维护手册：新增文案 / 翻译流程 | 贡献者 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 五层架构：层职责 / 依赖方向 / 命名约定 / 自检命令 | 贡献者 |
| [`QUALITY_STANDARD.md`](QUALITY_STANDARD.md) | 质量标准：十条原则性条款（不谈实现，裁决依据） | 贡献者 |
| [`CONSISTENCY.md`](CONSISTENCY.md) | 缓存一致性 D1–D9 权威描述：各防线语义、合法例外、失效路径 | 贡献者 |
| [`OAUTH_ORG_SETUP.md`](OAUTH_ORG_SETUP.md) | 组织名下 GitHub OAuth App（Device Flow）创建与 Secret 注入指引 | 维护者 |

## 审计记录（一次性批次产物，按批归档）

| 文件 | 内容 |
| --- | --- |
| [`AUDIT_PLAN.md`](AUDIT_PLAN.md) | 八批三视角交叉审计的计划（每批 A 实现 / B 安全 / C 契约，只审不改） |
| [`audit_b1_*.md`](AUDIT_PLAN.md) · [`audit_b2_*.md`](AUDIT_PLAN.md) | 第 1/2 批原始记录与交叉结论（含修复提交号与降级/否决理由） |
| [`audit_206.md`](audit_206.md) · [`audit_submit_download.md`](audit_submit_download.md) · [`audit_ui.md`](audit_ui.md) · [`audit_net_data.md`](audit_net_data.md) · [`audit_debug_empty_fail.md`](audit_debug_empty_fail.md) | 专项审计：206 回执、提交/下载链路、UI 层、网络+数据层、启动空白排查 |

## 相关文档（仓库根目录）

| 文件 | 内容 |
| --- | --- |
| [`README.md`](../README.md) | 项目介绍与功能清单 |
| [`CHANGELOG.md`](../CHANGELOG.md) | 完整版本历史（新版本在前） |
| [`release_notes/`](../release_notes) | 每版本一份发布说明，中英对照；索引见 [`release_notes/README.md`](../release_notes/README.md) |
| [`LICENSE`](../LICENSE) · [`NOTICE`](../NOTICE) | Apache-2.0 许可全文与声明（随构建产物分发） |

## 约定

- **发布说明**放在根目录 [`release_notes/`](../release_notes)，每版本一个文件；
- **完整版本历史**在根目录 [`CHANGELOG.md`](../CHANGELOG.md)；
- 本目录仅收录"持续有效"的手册类文档；一次性规划落地后即移除，不保留失效文档；
- 文档所引用的符号必须**真实存在**（改名时一并更新），路径尽量写成可点击链接。
