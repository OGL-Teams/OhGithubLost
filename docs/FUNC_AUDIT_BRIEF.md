# 全仓库功能交叉审计任务书（15 席 × 5 批）

> 用户指令（2026-11-22）：用 15 席子代理审查**全部仓库功能**。UI 已在 v15 完成 15 席审计，本轮对象是**功能正确性**（不是视觉）。
> 仓库 /root/OhGithubLost，v15.0.0，171 dart / 59.5k 行 / 56 测试 / 34 门禁工具 / 6 workflow。

## 全局纪律（每席任务书必须原样带上）
1. **禁读 Flutter SDK**：禁止读取/下载/复制 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码；只用项目自身 lib/ 已验证代码；需要框架 API 事实就跳过并标「待核实（交主会话/CI 裁决）」；本地 dart 仅用 `/opt/dart/bin/dart format`。违反即取消+全量清理。
2. **只读审计**：不改代码、不 commit / 不 push；唯一产出是指定报告文件（docs/FUNC_AUDIT/<批>-<席>.md）。
3. **证据**：每条问题必须 file:line 可 rg 复现；给出「症状 → 根因 → 修复指令（具体到改哪个文件什么逻辑）」。
4. **覆盖**：每席必须列「已检查清单」（查过哪些文件/函数，无问题也要列），禁止抽样后声称全覆盖。
5. **报告格式**：开头带文档戳（更新时间精确到秒 + v15.0.0）；问题按 严重(P0 数据丢失/崩溃/安全) / 中(P1 功能失效/不一致) / 轻(P2 打磨) 分级；末尾给「本席结论」。

## 功能域地图（5 批 × 3 席）
- **批 1 · 数据层**：1-A `lib/domain/gh/` API 正确性（端点/方法/参数/分页/错误映射）；1-B `lib/base/disk/` + `gh_read_cache.dart` 缓存一致性（TTL/失效/冲突/原子写）；1-C `lib/kernel/boot/` + `tool/boot_manifest.py` 引导信任链（Ed25519 签名/失败路径/平台差异）。
- **批 2 · 认证与网络**：2-A `gh_auth/gh_oauth*` 登录链路（PAT/Device Flow/Web Flow/state CSRF/令牌保险库/401 markExpired）；2-B `lib/base/net/` 传输层（重定向/429 Retry-After/DoH/IP 白名单/超时/206 缓存）；2-C `gh_client.dart` 请求编排（限流避让/缓存命中/诊断/并发/错误出口）。
- **批 3 · 任务与下载**：3-A `lib/domain/ix/` 下载（resume 分片/重名落盘/presign/后端切换/并发）；3-B `ix_task/session/notify/action_logs` 任务与通知（状态机/幂等/交叉同步）；3-C `lib/base/disk/` + 平台通道文件操作（路径规则/权限/跨桌面平台差异）。
- **批 4 · 展示层逻辑**：4-A `lib/surface/app/` 外壳状态机（启动/认证门/导航/返回链/窗口服务）；4-B `lib/surface/settings.dart` + 设置页配置持久化（白名单/默认值迁移/写盘风暴）；4-C 30 页 `lib/surface/pages/` 业务逻辑（表单校验/busy/分页/空态/深链——不看视觉，只看功能正确性）。
- **批 5 · 工程与发布**：5-A 测试覆盖（56 测试覆盖了什么、哪些关键路径零测试）；5-B 34 个 tool/ 门禁脚本判据有效性（是否纸面白名单、能否拦注入缺陷）；5-C 6 个 workflow + 发布/归档链路（build dispatch/release-verify/stats/pages 的正确性与幂等性）。

## 收口
15 份报告齐 → 主会话交叉汇总（多席同报=确证；P0 单独列出）→ docs/FUNC_AUDIT_REPORT.md（总报告：按严重度排序的修复清单 + 按域索引）→ 向用户一次性汇报。修复是否执行由用户决定（本轮只审计）。
