# 八批代码审计计划（2026-11-08）

> 用户规格：**8 个功能范围 × 每批 3 个子代理检查同一功能 × 主会话交叉结果**。
> 基线：main 分支 `dfd867f`（v11.2.0，CI/Build 全绿）；质量依据
> `docs/QUALITY_STANDARD.md`（59 条原则）+ `AGENTS.md`（分层与门禁数字）。

## 机制

| 项 | 约定 |
|---|---|
| 并行度 | 每批 3 个代理同时跑（正好用满并发上限），8 批串行推进 |
| 三视角分工 | **A 实现正确性**（逻辑 bug / 竞态 / 状态机 / 错误分支）· **B 安全与数据**（凭证出口 / SSRF / 原子性 / 失败可见性 / 数据丢失）· **C 契约与规范**（59 条原则 / 分层 / 命名 / 测试覆盖 / 文档一致性） |
| 阅读纪律 | `file_read` 完整读文件，**禁止 rg 正则扫描代替阅读**；大文件分段读完 |
| 只审不改 | 三个代理**都不许改 lib/**（同一批文件并发写必冲突）；发现即落盘到各自的 `docs/audit_bN_<视角>.md` |
| 输出格式 | 编号 `Bn-<视角>-xx` · 文件:行号 · 问题描述 · **用户可见后果** · 严重级别 P0/P1/P2 · 违反原则编号 · 是否确证（附证据） |
| 交叉规则 | 主会话生成 `docs/audit_bN_cross.md`：**三方命中 = 确证项（优先修）**；两方命中 = 复核项；单方命中 = 待议项（需主会话亲自复读确认） |
| 修复 | 交叉完成后由主会话统一最小侵入修复；每条修复写明"修复前 vs 修复后"行为差异；修复后跑全套门禁 + CI |
| 定时检查 | 按用户要求：**不用 sleep**，release/CI 检查一律用 `minis-scheduled` 定时器 |

## 八批功能范围

| 批 | 功能范围 | 核心文件 | 已知风险锚点 |
|---|---|---|---|
| **1** | 网络传输层 | `base/net/` 12 文件（`io_net_transport` / `net_transport` / `net_dns` / `net_retry` / `net_mirror` / `range_download*` / `net_bridge` / `web_net_transport`(web)） | 重定向守卫跨主机剥凭证、206 分段响应、只重试幂等方法、DoH 只认 https、Range 错位区间 |
| **2** | 磁盘一致性层 | `base/disk/` 12 文件（`disk_cache` D1–D7 / `disk_journal` D8 / `disk_draft` D9 / `og_l_storage` 三档 / `platform_io_impl`） | 刚改过的 D1「远端不存在+无基线=合法新建」、回读校验、原子写、孤儿 blob |
| **3** | GitHub API 层 | `domain/gh/gh_api` / `gh_client` / `repo_file_service` / `gh_models` / `gh_read_cache` | 206 回读确认、404 严格数组解析、官方 `/notifications` / `/readme` / `latestVersionOf` 新 API、tree truncated、路径逐段编码 |
| **4** | 下载管理层 | `domain/ix/ix_download` / `ix_download_backend_io` / `ix_presign*` / `ix_conflict` / `ix_task` / `ix_action_logs*` | 回合制守卫、幂等收尾、签名 URL 令牌不出设备、SSRF、完整性校验先于完成宣告 |
| **5** | 认证 · 会话 · 权限 | `gh_auth` / `gh_oauth*` / `ix_session` / `domain/sys/sys_access` / `surface/app/permissions` / `browser_notify*` | 令牌保险库、toString 脱敏、多账号切换清缓存、401 全局出口、Web 通知用户手势 |
| **6** | UI 状态与竞态 | `surface/app/`（`async` / `paged_controller` / `error_surface` / `motion` / `animations` / `anim_preload` / `og_l_app_bar` / `token_exit_warning` / `back_guard` / `keyboard_guard`） | 世代计数、空结果不进快照、通知 requeueFront、动效四档、AppBar 渐变节流、不可关闭弹窗 |
| **7** | 发现页 · 搜索 · 仓库页 | `surface/pages/search_page` / `repo_page` / `dashboard_page` / `client_shell` / `widgets/readme_view` | 官方动态流、推荐分页 README 切片/版本号、`_sortedItems` 内容指纹、TabBarView 物理、搜索预填 `repo:` |
| **8** | i18n · 门禁 · 发布链 | `assets/i18n/` 六语言 / `tool/*.py` / `.github/workflows/*` / `main.dart` 引导链 / `test/` | 键集合与 zh 一致、占位符、三处语言清单、严格模式收集、boot_manifest 签名、版本同步 |

## 交付物

- 每批：`docs/audit_bN_a.md` / `b.md` / `c.md`（三视角原始发现）+ `docs/audit_bN_cross.md`（交叉结论）
- 全 8 批完成：`docs/AUDIT_8BATCH_SUMMARY.md`（确证项总数 / 已修 / 待议 / 各层质量评价）
- 修复后：CI 严格模式全绿 + Release 检查（定时器）

## 推进方式

每批 3 个代理结果返回后，主会话立刻做交叉、统一修复、跑门禁，然后**自动启动下一批**；用户可随时插话调整范围或中止。
