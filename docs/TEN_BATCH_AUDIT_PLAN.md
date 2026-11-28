# 十批全面审计·修复规划（v15 后 / MD2 体系）

> 用户指令（2026-11-28）：每批 3 子代理检查 + 3 子代理修复，共十批；覆盖 UI、功能、健壮性、质量、社区要求、文档、说明文档、开发文档。
> 当前体系：**MD2**（非 MD3）——material-3 skill 不再作为验收标准，仅参考其审计方法论。

## 绝对纪律（每轮每代理必带）
1. **禁读 Flutter SDK**：禁止读取/下载/复制 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码；只用项目自身 `lib/` 已验证代码；本地 dart 仅用 `/opt/dart/bin/dart format`。
2. **层级原则最高**：L0 kernel → L1 base → L2 domain → L3 surface 单向依赖，层桥唯一入口；`layer_audit.py --fatal` 必须 0 违规。
3. **代码洁癖**：无死代码、无空回调、无 TODO 分支、无残留旧体系（MD3）痕迹。
4. **报告纪律**：先读全文再 append，禁止 file_write 覆盖整文件。
5. **修复纪律**：审计代理只读不改代码；修复代理产出必须过门禁（`gate_of_gates --fatal` / `i18n_scan --check` / `dart format 0 changed` / CI + ui-shots 截图核验）。
6. **批次节奏**：每批 = 3 审计 → 交叉汇总 → 3 修复 → 全门禁 → CI → 截图 → 提交 → 下一批。审计与修复不得并行（修复依赖审计结论）。

## Skill 映射（已确认全部可用）
| Skill | 用途 | 用在哪些批 |
|---|---|---|
| `sota-frontend-design` | 前端设计审查（规则/UX 模式） | 批 1/2 |
| `frontend-design` | 视觉方向/排版/非模板化 | 批 1 |
| `sota-ux-writing` | UX 文案审计（字典/微文案） | 批 3 |
| `humanizer-zh` / `humanizer` | 中英文去模板化润色 | 批 3/9/10 |
| `andrew-translate` | 三步式翻译（源值快照） | 批 3 |
| `sota-copywriting` | README/品牌文案 | 批 9 |
| `sota-docs-workflow` | 技术文档 Diátaxis | 批 9/10 |
| `sota-cli-ux` | CLI/开发者体验 | 批 8/10 |
| `material-3` | *仅参考审计方法论，不作标准* | — |
| `skill-creator` / `hyperframes*` / `promo-creator` | 与本项目无关 | 不用 |

## 十批内容

| 批 | 主题 | 3 审计席 | 3 修复席 | 主 skill |
|---|---|---|---|---|
| 1 | **UI 视觉与布局**（MD2 一致性） | 布局密度 / 色彩投影 / 跨页一致 | 布局修正 / 令牌收编 / 截图回归 | sota-frontend-design, frontend-design |
| 2 | **UI 交互与反馈** | 状态四态 / 动效档位 / 触控可达 | 状态补齐 / 动效修正 / a11y | sota-frontend-design, sota-cli-ux |
| 3 | **UX 文案与国际化** | zh 文案 / en 文案 / 30 语言一致性 | zh 重写 / en 重写 / 增量翻译 | sota-ux-writing, humanizer, andrew-translate |
| 4 | **功能·数据层** | GH API / 缓存一致性 / 同步写 | API 修正 / 缓存边界 / 写后失效 | 自定义任务书 |
| 5 | **功能·业务层** | 页面状态机 / 任务流 / 设置持久化 | 状态机修正 / 任务流修复 / 设置修复 | 自定义任务书 |
| 6 | **健壮性·错误处理** | 异常边界 / 重试策略 / 用户可恢复性 | 异常收口 / 重试接线 / 错误 UI | 自定义任务书 |
| 7 | **健壮性·网络与存储** | 传输层 / 磁盘 I/O / 缓存降级 | 传输修正 / I/O 收编 / 降级路径 | 自定义任务书 |
| 8 | **质量·架构与门禁** | 分层纯度 / 门禁判据有效性 / 测试覆盖 | 越级清理 / 门禁修复 / 测试补齐 | sota-cli-ux |
| 9 | **社区要求** | README / 贡献与许可证 / 发布物 | README 重写 / 贡献文档 / 发布说明 | sota-copywriting, sota-docs-workflow |
| 10 | **文档体系** | docs/ 说明文档 / 开发文档 / 索引与链接 | 说明文档重写 / 开发文档重写 / 索引修复 | sota-docs-workflow, humanizer-zh |

## 每批验收标准
- 审计：3 份报告齐备（file:line 证据 + P0/P1/P2 + 已检查清单），交叉汇总去重
- 修复：所有 P0 必须闭环；P1 ≥80% 闭环；P2 记录不修理由
- 门禁：12 支门禁 + 元验证 + format 0 changed + i18n_scan + CI + ui-shots 截图核验
- 提交：每批独立提交；CI 绿才进下一批

## 执行状态
- [ ] 批 1 UI 视觉与布局
- [ ] 批 2 UI 交互与反馈
- [ ] 批 3 UX 文案与国际化
- [ ] 批 4 功能·数据层
- [ ] 批 5 功能·业务层
- [ ] 批 6 健壮性·错误处理
- [ ] 批 7 健壮性·网络与存储
- [ ] 批 8 质量·架构与门禁
- [ ] 批 9 社区要求
- [ ] 批 10 文档体系
