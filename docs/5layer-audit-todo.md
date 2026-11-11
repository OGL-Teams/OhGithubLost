# 架构审计待办 · 历史占位（5layer-audit-todo.md）

> 本文件是 v8.2.0 时期「5 层架构 + 兼容性 + 错误捕获」全面审计的**占位清单**。
> 现行架构自 v12 起为 **四层 L0–L3**（见 `AGENTS.md`、`docs/ARCHITECTURE.md`），
> 本文件保留原始待办供追溯，**不再作为现行规范**。
> 现行审计已由 `docs/AUDIT_PLAN.md` 的九批三视角交叉法与
> `docs/AUDIT_INDEX.md` 统一索引取代。

## 当时的机械门禁快照（v8.2.0，勿当现状）

| 工具 | 当时输出 |
|---|---|
| `tool/layer_audit.py` | `违规：0 处`（main 144 文件 / web 151 文件） |
| `tool/motion_audit.py --fatal` | 0 违规 |
| `tool/perf_audit.py` | 0 违规 |
| `tool/i18n_scan.py --check` | 通过 |

## 现行快照（2026-11-11 实测，仅作对照）

| 工具 | 现行输出 |
|---|---|
| `tool/layer_audit.py --fatal` | **文件总数：154 / 已知待收敛 2 处 / 违规 0 处** |
| `tool/contract_audit.py --fatal` | 5 节检查全 0（含 export / 四层文件头 / 平台门面 / 文档契约 / 装配顺序） |
| `tool/gate_of_gates.py --fatal` | 7 支门禁在临时 CWD 下仍有能力 + 反向注入验证通过 |
| 其余门禁 | ui / motion / perf / i18n / ci_config / version_sync 全绿 |

> 统计口径说明：154 是 `lib/` 下四个层级目录（kernel/base/domain/surface）
> 的 Dart 文件数；`lib/platform/`（平台门面）与 `lib/main.dart`（组合根）
> 不入四层统计，故与 `find lib -name '*.dart'` 的 161 不同。两者都对，
> 不要互相「修正」。

## 原始待办（历史记录，不改）

1. domain → base 下穿点：KNOWN 2 项 `RepositoryCache` / `NetBridge`
   是否仍被直接 import、是否已可移除。
   **现状**：仍为 2 项，由 `tool/layer_audit.py` 的 `KNOWN` 显式登记；
   正解是在 `kernel/contract/` 定义抽象，属独立批次。
2. 契约层 vs 实现层覆盖：当时问 `kernel/contract/` 下 10 个文件是否都有
   io/web 两套实现。**现状**：四层架构下 platform/ 条件 import 实际为零，
   详见 `docs/ARCHITECTURE.md` §6.2 的现状说明。
3. 错误捕获：`on Object catch` 频次、`unawaited(...)` 漏错误回调、
   `catch` 后无 rethrow。
4. 平台兼容性：`dart:io` 在 web 的隔离、各插件降级路径。
5. 跨平台一致性：五平台 vs web 分支覆盖、CI 矩阵覆盖。

上述 3–5 项已在批 1–9 审计中逐项展开，结论见 `docs/AUDIT_INDEX.md`
对应批次报告；本文件不再追加。

## 归档说明

- 当时写「审计报告输出至 `docs/5layer-audit-YYYY-MM-DD.md`，本占位文件随之归档」；
  实际走的是 `audit_b<N>_{a,b,c}.md` + `audit_b<N>_cross.md` 系列，
  故本文件**保留不删**（历史报告里有互链），由 `docs/AUDIT_INDEX.md` 登记为
  「批外专项 · 历史占位」。
- 本版本（v12.5.2）未启动新的「5 层」全面审计；机械门禁已在 CI 中
  作为 fast-fail 常驻。
