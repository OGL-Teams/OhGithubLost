# 功能审计 5-A · 测试覆盖（test/ 全量 56 .dart + CI flutter test）

> 文档戳：更新时间 2026-11-23 07:07:24 (Asia/Shanghai) · v15.0.0
> 范围：test/ 全部 57 个 dart（含 screenshots 目录，56+1）、.github/workflows/{ci,build,release-verify}.yml 测试步骤。只读审计，未改任何代码。

## 一、覆盖地图（对照 lib/ 功能域）

**有实质测试的子系统**（共约 470 用例）：
- gh_api / gh_client：gh_test(30)、gh_client_test(26, 含 401→GhAuthException 映射)、gh_models_decode(6)、gh_tags(6)、gh_absent(10)、gh_list_strict(5)、gh_write_endpoints(2)、gh_submit_e2e(2, 真走写入引擎+409 冲突拦截)。
- auth：gh_auth_service_test(12, markExpired 幂等/令牌缺失/元数据缺失→expired)；gh_oauth_flow_test(3)。
- net：net_test(20)、net_dns(31)、net_dns_guard(4)、net_contract(4)、net_transport_reconnect(2, connection:close + 对端早断 PoC)。
- cache/download/task：cache_consistency(31, 冲突/基线/重定基/TTL/prune/穿越全有)、durability(15, 队列/重放/基线过期)、chaos(9, 进程杀重放/500 路并发写/撕裂写/模糊)、range_download(9)、ix_test(26)、ix_download(19)、ix_download_manager(18)、ix_download_dedup(5)、ix_conflict(21)、sys(28)、platform_io(19)。
- kernel：kernel(24)、boot_release_chain(4, 固定签名样本验签/篡改拒绝)、boot_define_injection(1)、environment(8)、bridge_registry(4)、log_file(5)。
- surface：settings(22, 迁移/世代守卫/Infinity-NaN)、path_rules(20)、i18n(4, 全键集比对)、animations(16)、code_editor(13)、back_guard(8)、permissions/permission_selftest(10)、format/log_body/file_icons/file_preview/async/async_sliver/page_transitions/notifier/settings_collapse/download_notice_jump/ui_regression(11)/smoke(5)。

**零测试（或仅快照渲染无行为断言）的子系统（共 9 个）**：
1. `lib/surface/pages/` 30 个页面中仅 9 个被 ui_regression/screenshot_matrix/download_notice_jump 触及（about/commit/login/profile/settings/dashboard/repo/download_manager），**21 个页面零测试**：issue_page、pull_page、new_issue/new_release/new_repo/new_gist、gist_detail、gists_page、notifications_page、release_detail、repo_tags、search、drafts、action_log、action_run、workflow_dispatch、onboarding、file_preview_page、code_editor_page(有 util 级测试但页面无)、settings_section、legal_text、network_page —— 表单校验/busy/分页/深链全部无 widget 测试。
2. `lib/surface/app/` 外壳状态机 23 文件：启动/认证门/导航返回链仅 back_guard_test 8 例覆盖守卫逻辑，启动序列、窗口服务、tab 栈零测试。
3. `lib/surface/widgets/` 10 文件：仅 async_sliver/async/format 间接覆盖，其余零。
4. `lib/surface/theme/` + `surface/surface_bridge/`：theme 零测试（animations 测的是 motion，不是 theme 落盘/切换）。
5. `lib/base/log/`（2 文件）：log_file_test 测 kernel/log，base/log 零直接测试。
6. `lib/kernel/module_bus/`、`kernel/lifecycle/`、`kernel/diagnostics/`、`kernel/di/`：仅 bridge_registry/environment 间接，本体零测试。
7. `lib/platform/` window_*（5 平台窗口适配）：零测试（可谅解，但 capability 分级逻辑可测未测）。
8. OAuth 真实链路：gh_oauth_flow_test 仅 3 例**纸面契约**（构造参数/GhOAuthCode 常量），Device Flow 轮询、state CSRF、Web Flow、令牌保险库读写（SecureDiskVault）零行为测试。
9. 通知域 `ix_notify`：仅 ix_test 内 7 例（合并/水位），跨任务通知联动、下载完成跳转仅 download_notice_jump 3 例。

## 二、问题清单

### P0（数据丢失/崩溃/安全级零测试）
- **A-1 · 认证失效端到端零测试**
  - 症状：`test/domain/gh_oauth_flow_test.dart:1-35` 自述"真实 HTTP 往返由登录页现场执行"——Device Flow 轮询、间隔退避、state/CSRF、令牌入库（SecureDiskVault）、401 触发 markExpired 后自动登出的全链路无任何测试。
  - 根因：OAuth IO（gh_oauth_io.dart）端点为文件级私有，测试只够到常量层；auth_service_test 只测状态机内存态。
  - 修复指令：新增 `test/domain/gh_oauth_e2e_test.dart`，用脚本化 NetBridge 假件（同 gh_client_test 的 _bridge 模式）驱动 GhOAuthDeviceFlow 全轮询（成功/慢速间隔/授权被拒/网络中断恢复），并断言 token 写入 vault 后可读、明文不落普通 kv；补 401→GhAuthService.markExpired→UI 门联动的集成用例。
- **A-2 · 令牌外泄/保险库行为零测试**
  - 症状：rg "SecureDiskVault" test/ 仅 `test/base/base_bootstrap_test.dart:30` 一行 isA 类型断言；日志脱敏（log_body_test 7 例测的是 body 脱敏，未含 token 字段专项）、诊断上报是否携带 token，均无用例。
  - 根因：保险库被当作平台层信任，无契约测试。
  - 修复指令：新增 vault 契约测试（写后读、删除后读 null、密文落盘断言、token 出现在 GH 日志/诊断时必须被 mask）；在 chaos_test 模糊输入中纳入带 token 的响应体。

### P1（功能失效/覆盖缺口）
- **A-3 · 21 个页面零 widget 测试（覆盖缺口）**
  - 症状：`lib/surface/pages/` 30 页 vs `rg -o "pages/[a-z_]+" test/` 仅命中 9 页。issue/pull/release/gist/notifications/search 等核心编辑与列表页表单校验、分页加载、空态、深链全部零断言。
  - 根因：页面层只有截图冒烟（screenshot_matrix 默认仅 1 次不落盘截屏，无 expect 断言业务状态）。
  - 修复指令：按批 4-C 发现的高风险页（new_issue/new_release 提交 busy 与重复提交、notifications 分页、pull 合并冲突态）每页补 ≥3 个 testWidgets 用假件 bridge 驱动，先补写路径页面。
- **A-4 · 外壳启动/认证门/窗口服务零测试**
  - 症状：`lib/surface/app/` 23 文件无对应测试文件；back_guard 仅测返回拦截。boot_define_injection_test 在 CI 仅 build.yml:613-615 单文件跑，ci.yml 的 `flutter test` 全量跑时若 OGL_BOOT_MANIFEST 缺失该文件可能 skip/失败路径未核（待核实，交 CI 裁决）。
  - 修复指令：新增 surface/app 启动序列测试（引导失败→降级 UI、认证门放行/拦截），并验证 ci.yml 环境下 boot_define_injection 的实际行为。
- **A-5 · 下载 resume/断点续传覆盖薄**
  - 症状：`test/domain/ix_download_manager_test.dart:68` 假件 `resume(String id) async {}` 为空实现；ix_download_test 测 URL/presign 规则，range_download_test 测分片 HTTP 语义，但"分片进度落盘→进程重启→从已收分片续传"的端到端零测试。
  - 修复指令：新增用例：写入部分分片+journal→重建 manager→断言续传 Range 起点与最终文件哈希。
- **A-6 · 平台通道文件操作（SAF）零测试**
  - 症状：`lib/base/disk/og_l_storage_saf_io.dart` 无测试；platform_io_test 19 例均走本地 fs 假件。
  - 修复指令：补 SAF 假件契约测试（权限撤销→写失败不静默、persistable 权限恢复）。
- **A-7 · theme 持久化/切换零测试**
  - 症状：`lib/surface/theme/` 1 文件、设置页主题项的落盘往返在 settings_test 中无主题专项（settings_test 22 例均非 theme 字段）。
  - 修复指令：在 settings_test 补 theme 字段往返 + 动态切换生效用例。

### P2（打磨/轻微）
- **A-8 · 少数纸面/常量测试**：gh_oauth_flow_test 3 例、net_transport_reconnect_test:100 的 "connection: close" 属静态断言式；gh_write_endpoints_test 仅 2 例（锁定/解锁），其余写端点（fork/star/watch 等）靠 gh_client_test 间接。建议扩端点矩阵表驱动。
- **A-9 · 测试时间依赖（flake 源）**：`DateTime.now()` 出现于 net_dns_test:291,301,316（TTL 边界 1 分钟）、gh_client_test:118,200、net_contract_test:28、ix_test:403,510。跨午夜/慢机可能抖动；log_file_test:38 已示范正确做法（校验落盘文件名而非墙钟），建议 TTL 类用例改注入 clock。smoke_test:37 自述依赖真实时间判最小显示时长，可用 fakeAsync。
- **A-10 · 文件命名误导**：test/ 共 57 个 .dart（任务书说 56），其中 test/screenshots/screenshot_matrix_test.dart 默认模式只跑一次不落盘截屏冒烟、有效业务断言少，统计口径需修正。
- **A-11 · net_test 2 处 skip**：`test/base/net_test.dart:132,137` 的 skip 是**测试参数**（mirrorFor(skip: …)）而非 flutter_test skipTag——经核实非掩盖性 skip，标注以正视听。

## 三、CI 是否真跑全部测试
- ci.yml:178 `flutter test --reporter expanded`（全量）+ 严格模式终审（无 continue-on-error；rg 全 workflow 无 continue-on-error、无 test skip 标签）。build.yml:613 仅对 boot_define_injection 单文件补跑（带 dart-define）。release-verify.yml:423 全量 + :430 截屏矩阵。结论：CI 无 skip/continue 掩盖；唯一风险是 ci.yml 全量跑时 boot_define_injection 是否因缺 dart-define 而异常（待核实）。

## 四、已检查清单
- 57 个 test/*.dart 全部统计行数/用例数/skip（见上）。
- 逐文件审阅内容：gh_oauth_flow、gh_auth_service、gh_client、gh_test、cache_consistency、chaos、durability、platform_io、net_test、net_transport_reconnect、net_dns、range_download、ix_test、ix_download(_manager/_dedup)、ix_conflict、sys、kernel(boot_release_chain/environment/bridge_registry/log_file/boot_define_injection/kernel)、settings(_collapse)、i18n、path_rules、animations、back_guard、permissions(_selftest)、format、log_body、file_icons、file_preview、async(_sliver)、page_transitions、notifier、code_editor、smoke、ui_regression、download_notice_jump、screenshot_matrix（头部注释+引用面）。
- CI：ci.yml、build.yml、release-verify.yml 测试步骤；rg continue-on-error/skip。
- lib/ 功能域文件数分布（pages 30/app 23/util 14/ix 13/disk 13/gh 12/net 12/widgets 10…）。
- 关键路径检索：401/markExpired、resume/206、DateTime.now、token/vault、并发、SAF、theme、module_bus。

## 五、本席结论
测试底盘显著优于一般 Flutter 项目：cache/chaos/durability/ix 冲突域是真实行为测试（含 500 路并发、进程杀重放、模糊注入），无 continue-on-error 掩盖。但存在结构性盲区：**OAuth 全链路 + 令牌保险库零行为测试（A-1/A-2，P0）**、21/30 页面与外壳状态机零 widget 测试（A-3/A-4）、下载 resume 端到端缺失（A-5）。纸面测试占比很低（OAuth 契约 3 例为最典型），mock 未发现掩盖 bug 的实锤（假件 resume 空实现使续传用例失真，A-5）。合计 **11 条：P0×2 / P1×5 / P2×4**；零测试子系统 9 个。建议修复顺序：A-1→A-2→A-3→A-5→A-4→其余。
