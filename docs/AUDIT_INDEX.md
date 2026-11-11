# 审计总索引（九批 + 规范专项）

> 方法与批次约定见 [`AUDIT_PLAN.md`](AUDIT_PLAN.md)：每批 A/B/C 三视角并行、只审不改，主会话交叉裁决。
> 本索引是九批审计的唯一总账；**新增任何审计报告必须同时更新本文件**。

## 汇总表

| 批次 | 范围 | A / B / C 报告 | 交叉报告 | 状态 |
|---|---|---|---|---|
| 1 | 网络传输层 | [`audit_b1_a.md`](audit_b1_a.md) / [`b`](audit_b1_b.md) / [`c`](audit_b1_c.md) | [`audit_b1_cross.md`](audit_b1_cross.md) | 已收口 |
| 2 | 磁盘一致性层 | [`audit_b2_a.md`](audit_b2_a.md) / [`b`](audit_b2_b.md) / [`c`](audit_b2_c.md) | [`audit_b2_cross.md`](audit_b2_cross.md) | 已收口 |
| 3 | GitHub API 层 | [`audit_b3_a.md`](audit_b3_a.md) / [`b`](audit_b3_b.md) / [`c`](audit_b3_c.md) | [`audit_b3_cross.md`](audit_b3_cross.md) | 已收口 |
| 4 | 下载管理链路 | [`audit_b4_a.md`](audit_b4_a.md) / [`b`](audit_b4_b.md) / [`c`](audit_b4_c.md) | [`audit_b4_cross.md`](audit_b4_cross.md) | 已收口 |
| 5 | 认证 / 会话 / 权限 | [`audit_b5_a.md`](audit_b5_a.md) / [`b`](audit_b5_b.md) / [`c`](audit_b5_c.md) | [`audit_b5_cross.md`](audit_b5_cross.md) | 部分（G1 测试缺口列为专项） |
| 6 | UI 层与状态管理 | [`audit_b6_a.md`](audit_b6_a.md) / [`b`](audit_b6_b.md) / [`c`](audit_b6_c.md) | [`audit_b6_cross.md`](audit_b6_cross.md) | 已收口（切号失效链路 P1 记录） |
| 7 | 主题 / 字体 / 令牌警告 | [`audit_b7_a.md`](audit_b7_a.md) / [`b`](audit_b7_b.md) / [`c`](audit_b7_c.md) | [`audit_b7_cross.md`](audit_b7_cross.md) | 已收口 |
| 8 | i18n 与门禁体系 | [`audit_b8_a.md`](audit_b8_a.md) / [`b`](audit_b8_b.md) / [`c`](audit_b8_c.md) | [`audit_b8_cross.md`](audit_b8_cross.md)（事后补写） | 部分（批 9 修 7 项，余 8 项按 P2 排队） |
| 9 | 规范专项审查（分层桥接 / UI 动效 / 门禁契约） | [`audit_spec_a.md`](audit_spec_a.md) / [`b`](audit_spec_b.md) / [`c`](audit_spec_c.md) | [`audit_spec_cross.md`](audit_spec_cross.md) | 已交叉（修复按 `audit_spec_cross.md` 第五节队列推进） |

## 各批 P0 / P1 口径

P0/P1 计数取自各交叉报告**确证并裁决后**的口径（原始发现数见各 cross 文件头部，普遍大于确证数；候选经复读否决的不计入）：

| 批次 | 确证 P0 | 确证 P1 | 备注 |
|---|---|---|---|
| 1 | 0（2 个 P0 候选复核降级为 P1） | 多组确证 | 206 回执、凭证头集合、DoH 降级等 |
| 2 | 2（B2-A-01 / B2-A-05；1 个 P0 候选降级待议） | 6 组 | 53 条原始发现 |
| 3 | 1（`lockIssue` 用 PATCH） | 7 组确证中含 | 48 条原始发现，已修 7 组（含 1 P0），G4 经 CI 裁决否决 |
| 4 | 1（归档下载绕过令牌门禁） | 3 | 41 条原始发现 |
| 5 | 0 确证（G1 测试缺口 C-11 标 P0 未修，列专项） | 多组（guest 状态机、401 误标、KV 损坏等） | 37 条原始发现 |
| 6 | 2（四线新增 UI 绕过 generation 防线） | 1（另 1 P0 候选否决） | 65 条原始发现 |
| 7 | 1（refreshState 通知自激回归） | 多组（主题 TextStyle、字体缓存等） | — |
| 8 | 2（B8-A-01 i18n dict 值、B8-C-01 门禁死描述）——**均由批 9 修复** | 含 B8-C-02 门禁 CWD（批 9 修复） | 可核对 15 项：已修 7 / 未修 8 |
| 9 | 1 确证（X-01 门禁在错误 CWD 静默全绿，批 9 已修） | 报告分布 P1×16（A4/B5/C7） | 53 条原始发现（A13/B23/C17） |

> 批 1–7 的逐条 P0/P1 编号以各 cross 报告正文的裁决表为准；本表只给量级与要点。
> 批 8 遗留缺口（供应链、i18n 插值转义、runtime 接线）见 `audit_b8_cross.md`「批 9 仍明确留下的缺口」。

## 批外专项审计（一次性，同样需登记）

| 报告 | 主题 |
|---|---|
| [`audit_206.md`](audit_206.md) | 206 分段响应回执专项 |
| [`audit_submit_download.md`](audit_submit_download.md) | 提交 / 下载链路专项 |
| [`audit_ui.md`](audit_ui.md) | UI 层专项 |
| [`audit_net_data.md`](audit_net_data.md) | 网络 + 数据层专项 |
| [`audit_debug_empty_fail.md`](audit_debug_empty_fail.md) | 启动空白排查 |
| [`5layer-audit-todo.md`](5layer-audit-todo.md) | 五层审计遗留待办 |

## 纪律

1. 新增审计报告（无论批次还是专项）落盘当天，必须在「汇总表」或「批外专项」登记，给出范围、三份报告与交叉结论路径、状态。
2. 交叉报告状态变化（收口 / 部分修 / 新增遗留）要回写状态列。
3. 本索引只登记事实与路径，不复制结论；结论以各 cross 文件为准。
