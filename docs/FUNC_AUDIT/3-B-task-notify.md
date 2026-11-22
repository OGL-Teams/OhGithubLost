# 功能审计 3-B · 任务与通知状态机（ix_task / ix_session / ix_notify / ix_action_logs*）

> 更新时间：2026-11-23 10:32:41 · 版本 v15.0.0
> 审计席：批 3-B · 只读审计 · 产出仅本文件。

## 审计范围
lib/domain/ix/ix_task.dart(445) / ix_session.dart(355) / ix_notify.dart(229) / ix_action_logs.dart(162) / ix_action_logs_http_io.dart(132) / ix_action_logs_save_io.dart(24) / ix_action_logs_save_stub.dart(16)，及交叉调用点（domain_bridge.dart、main.dart、action_run_page.dart、action_log_page.dart、ix_download.dart、gh_auth.dart）。

## 问题清单

### P1-1 通知「不再提示」永不生效，重复告警复活（ix_notify.dart:133-158, 205-215）
- 症状：`push()` 合并键命中已 dismiss 的 ID 时，`bump()` 直接 `insert(0, merged)` 重新入列，不检查 `_dismissed`；`wasDismissed()` 无任何消费点（rg 全仓 0 调用）。用户关闭过的告警会随下一次同源事件复活。
- 根因：`_dismissed` 只在 `dismiss()` 写入，`push()` 未做闸门，且 `dismiss()` 之外没有任何入口读取它。
- 修复指令：在 ix_notify.dart `push()` 命中 `index >= 0` 分支前加 `if (_dismissed.contains(key) && dismissible) return;`（或仅累加 suppressedCount 不重新入列）；同时给 `_dismissed` 加上限防内存缓涨。

### P1-2 IxSession 持久化上下文无账号维度，跨账号上下文串号窗口存在（ix_session.dart:79-80, 103-126, 288-305）
- 症状：`_contextKey = 'ogl.ix.context'` 是全局单键；`restore()` 直接恢复上次 repo/path，不校验是否属于当前 activeAccount。`refreshAccount()` 只在切号事件（profile_page.dart:99）清 context；若进程直接重启且 activeAccount 已被外部切换（或 auth 存储 activeKey 被改），A 账号的私有仓库名会被恢复进 B 的会话首屏请求。
- 根因：上下文序列化未绑定账号 ID，restore 时无归属校验。
- 修复指令：`toJson()` 写入 `accountId`（restore 前先取 `_auth.activeAccount()` 比对），不匹配则丢弃 context；prefs 可保留全局。

### P1-3 IxTaskRunner 状态机：applier 失败后进度归零但报告丢失、cancel 在通道切换阶段无效（ix_task.dart:335-360, 373-380）
- 症状：① `run()` 中 `applier(decision)` 若抛异常，直接冒出 `run()` 外，`_running` 已在 finally 置 false、无 `_lastReport`，调用方拿不到任何 IxTaskReport，notifyListeners 也不发终态事件（_progress 停留在 0/N）；② 取消只在 item 循环生效（:374），通道切换（可能含多秒测速/请求）期间 `cancel()` 置位但无检查点。
- 根因：applier 调用未纳入 try/finally 的结果上报路径；切换阶段无取消检查。
- 修复指令：把 applier 包进 try/catch，失败时产出单项失败结果并生成 cancelled/failed report；或在 applier await 后检查 `_cancelRequested` 提前 break。

### P2-1 IxNotificationCenter 无持久化与已读水位，刷新后状态全丢（ix_notify.dart:114-116, 162-202）
- 症状：`_items`/`_dismissed` 纯内存，重启后全部丢失；`ingestDiagnostics()`（:164）全仓 0 调用点——诊断告警导入能力是死代码，warn/error 实际只经 main.dart:287 forwardNotifications 转发到 OgLAppLog，通知中心自身收不到内核告警。
- 修复指令：用 DiskKv 持久化 items+dismissed（参照 ix_session 的 key 手法）；装配层调用 ingestDiagnostics 接通内核诊断。

### P2-2 IxNotification.createdAt 合并不更新，排序按插入序而非时间（ix_notify.dart:81-96, 136-141）
- 症状：`bump()` 保留旧 createdAt；合并后条目移到最前，UI 呈现为"最新"，但时间戳是首次出现的旧时间，展示与实际不符。
- 修复指令：bump() 增加 `lastSeenAt` 字段（或合并时更新 createdAt）。

### P2-3 IxActionLogs 无幂等防护：rerun/cancel 可被重复触发（ix_action_logs.dart:100-112）
- 症状：`_post` 无请求去重/单飞（in-flight 锁）。UI 侧靠 `_busy`（action_run_page.dart:226）兜底，但若上层并发调用（多窗口/回调），重复 POST rerun 会叠加触发两次工作流运行，消耗额度。
- 修复指令：在 IxActionLogs 加 `Set<String> _inflight`（key=`path`），进行中重复调用直接返回或抛错。

### P2-4 save_io 与 stub 契约基本一致但 io 实现缺路径净化兜底（ix_action_logs_save_io.dart:11-24）
- 症状：io 版直接 `File('$root/actions/$fileName')` 写盘，不对 fileName 做任何校验（依赖调用方净化）；stub 抛 `IxActionLogsException` 契约一致 ✔。当前调用点（action_run_page.dart:314、action_log_page.dart:188）已用 `RegExp(r'[^A-Za-z0-9._-]')` 净化 ✔，但契约层面 io 版无防御——新增调用方漏净化即可路径穿越（`../`）。
- 修复指令：io 版内再兜底一次 `fileName.replaceAll(RegExp(r'[/\\]'), '-')`。

### P2-5 fetchBytes 手动重定向循环无总超时与字节上限（ix_action_logs_http_io.dart:44-95）
- 症状：重定向最多 5 跳 ✔、每跳有 receive timeout ✔，但整链无总预算，且字节无限累积（`bytes.addAll`），超大日志 zip 可撑爆内存。
- 修复指令：循环外加总耗时检查；`content-length` 超阈值（如 200MB）时中止。

## 已检查清单
- ix_task.dart：IxBatchItem/Plan/Decision/IxConfirmationRequired/IxTaskResult(ok+skipped→failure 语义 ✔)/Progress/Report/IxTaskRunner.run（确认闸门 ✔、单飞 StateError ✔、单项失败不中断 ✔、取消立即生效于下一项 ✔）— 缺陷 P1-3。
- ix_session.dart：IxContext 序列化、restore（容错+清除损坏键 ✔）、enterRepo/setBranch/enterDirectory/goUp/leaveRepo、setSort/rememberSearch(去重+上限20 ✔)、refreshAccount(切号清 context ✔ 但见 P1-2)、sortEntries(folderFirst/降序 ✔)。
- ix_notify.dart：push 去重键(source|code|subject, 空则 title|message ✔)、bump 合并、ingestDiagnostics(warn/error 过滤、since 水位 ✔ 但未接线)、dismiss/clearDismissible/_trim(保护不可关闭告警 ✔)、hasDanger — 缺陷 P1-1/P2-1/P2-2。
- ix_action_logs.dart：_post（Bearer 头 ✔）、fetch（空 zip 返回空 map ✔）、_decodeZip(仅 .txt ✔ allowMalformed ✔)、_labelOf、joinLogs、saveToDisk 条件导入桥 ✔ — 缺陷 P2-3。
- ix_action_logs_http_io.dart：fetchBytes（手动重定向防令牌跨主机泄漏 ✔、scheme 校验 ✔、POST 不跟随 ✔）、超时、即用即关 ✔ — 缺陷 P2-5。
- ix_action_logs_save_io.dart / save_stub.dart：平台契约对照 — 缺陷 P2-4。
- 交叉点：domain_bridge.dart:377-430 装配、main.dart:277-300 通知转发、profile_page.dart:99 切号、action_run_page.dart / action_log_page.dart 文件名净化与 busy 防抖 ✔、ix_download.dart 通知 push 点（840/1037/1552/1567）、gh_auth.dart activeAccount/markExpired（expired 状态与 session 无联动，但 session 只读账号快照，无错误行为）。

## 本席结论
本域整体质量较高：批量确认闸门、令牌不跨主机泄漏、切号清上下文等纪律在类型层强制到位。核心缺口集中在通知中心（「不再提示」失效 + 无持久化 + 内核诊断未接线）与会话上下文的账号归属校验，均为可低成本修复的逻辑漏洞，无 P0。stub/io 契约一致。建议优先修 P1-1、P1-2，其次 P1-3 的 applier 失败上报路径。
