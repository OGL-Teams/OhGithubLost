# 5 层架构审计 · 待办（5layer-audit-todo.md）

> 本文件为本仓库「5 层架构 + 兼容性 + 错误捕获」全面审计的待办清单。
> 当前已落地机械门禁（layer_audit.py / motion_audit.py / perf_audit.py / i18n_scan.py）
> 但**仅证语法 / 导入 / 分层规范**，不证语义设计的严密性。

## 已观察（来自机械门禁，不代表设计严密）

- `tool/layer_audit.py` 输出：`违规：0 处`（main 144 文件 / web 151 文件）
- `tool/motion_audit.py --fatal` 输出：0 违规
- `tool/perf_audit.py` 输出：0 违规
- `tool/i18n_scan.py --check` 输出：通过

## 待查（按优先级）

### 1. domain → base 下穿点
- KNOWN 列表当前 2 项：`RepositoryCache` / `NetBridge`
- **问题**：是否仍被上层直接 import？是否已被新设施替代却残留在 KNOWN 列表里（白名单烂账）？

### 2. 契约层 vs 实现层覆盖
- `lib/kernel/contract/` 下 10 个文件
- **问题**：每个是否都有 `io/` 与 `web/` 两套实现？哪些只有 `io/` 端，
  靠 stub 在 web 上跑（是否静默降级 / 抛 NotImplementedError）？

### 3. 错误捕获
- `on Object catch (e)` 出现频次？是否吞错？
- `unawaited(...)` 是否漏错误回调（dart:async 的 unhandled exception 出口）？
- `try { ... } catch (e, st) { debugPrint(...) }` 后无 rethrow 的位置（用户消息丢失）？

### 4. 平台兼容性
- `dart:io` 在 web 后端的隔离（condition_import 覆盖是否完备）
- Plugin（permission_handler / window_manager / path_provider / flutter_local_notifications）
  在 Web 上的降级路径是否完备，是否有空降（用 `defaultTargetPlatform` 判断后直接
  return 而无任何提示 / 兜底）？

### 5. 跨平台一致性
- 5 平台 vs 1 平台（web）分支覆盖——哪些是 5 平台同样的代码，哪些是 web-only 退化？
- CI 矩阵是否真的覆盖全平台（`pubspec.yaml` 的 platforms 字段 vs `.github/workflows/` 的 build matrix）？

## 启动审计信号后

- 按本大纲逐项展开
- **不重做已写内容**：kernel/contract 实现、layer_audit 规则等如已通过机械门禁，
  只核查语义；不重写文件除非真的不合规
- 审计报告输出到 `docs/5layer-audit-YYYY-MM-DD.md`，本占位文件归档

## 不阻塞本任务

- 本轮（8.2.0）**未启动**全面审计，仅落占位清单
- 机械门禁已在 CI 中作为 fast-fail
