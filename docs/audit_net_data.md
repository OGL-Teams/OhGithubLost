# 网络层 + 数据层 代码审计（audit_net_data.md）

审计范围：lib/base/net/（12 文件）、lib/base/disk/（12 文件）、lib/domain/gh/（gh_api/gh_client/repo_file_service）、lib/domain/ix/（ix_presign/ix_download/ix_conflict）、lib/kernel/contract/。
依据：docs/QUALITY_STANDARD.md（59 条）+ AGENTS.md。

（审计进行中，逐条落盘）

## NET-01 · 重定向泄漏凭证（已修复）
- 文件：lib/base/net/io_net_transport.dart（原 send() 内 `followRedirects = true`，约 145-150 行）
- 问题：dart:io HttpClient 自动跟随重定向时会**原样重发全部请求头**（含 `Authorization`）。GitHub API 会 302 到 raw.githubusercontent.com / codeload 等其他主机——跨主机重定向把令牌送给另一台服务器。
- 违反：原则 40（令牌只在必要的跳使用一次）、39（凭证脱敏）。
- 级别：P0（凭证外泄）。
- 用户可见后果：登录用户访问会被重定向的接口时，Bearer 令牌随 302 跳转发到非 api.github.com 的目标主机，令牌可被中间主机收集。
- 修复：带 `Authorization` 头的请求改用手动重定向跟随（`followRedirects = false`）：同源跳转带原凭证重发（302/303 降级 GET 且丢 body）；跨主机跳转**不跟随**，把 3xx 响应如实交还上层。无凭证头请求行为不变。修复前 vs 修复后：修复前跨主机重定向自动携带凭证完成请求；修复后凭证只发给原目标主机。

## DATA-01 · 分片下载失败分支缺回合校验（已修复）
- 文件：lib/domain/ix/ix_download.dart（`_runRanged` 的 `on DownloadUnsupported` 与通用 `catch` 分支，原约 880-910 行）
- 问题：A-2 回合守卫只加在 `on DownloadCanceled` 分支。用户 retry/resume 启动新一轮分片后，旧一轮 fetch 迟到的 `DownloadUnsupported` 会触发旧轮 `_fallbackToSingle`（与新一轮分片**并发写同一 targetPath**，即文件错位写坏的经典模式）；迟到的网络错误则把新轮刚写的 running 覆盖成 failed。
- 违反：原则 22（每个异步结果都要校验它是否仍然有效；过期的回调必须被丢弃）。
- 级别：P1（功能错误：状态错乱 / 并发写坏文件）。
- 用户可见后果：下载中点"重试"后，界面状态来回跳变（running→failed），或新轮分片与旧轮回退的单连接下载同时写同一个文件，产出错位的坏文件。
- 修复：两个失败分支开头补 `_roundOf[id] != myRound` 回合校验，旧轮迟到回调静默退出。修复前 vs 修复后：修复前旧轮失败/回退无条件执行；修复后仅当前轮的结果能写状态或触发回退。

## NET-02 · Actions 日志下载重定向泄漏凭证（已修复）
- 文件：lib/domain/ix/ix_action_logs_http_io.dart（`fetchBytes`，原 22-25 行 `followRedirects = true`）
- 问题：`IxActionLogs.fetch` 把 `Authorization: Bearer <token>` 放进 headers，而日志接口 `GET .../runs/{id}/logs` 的响应是 302 → `results-receiver.actions.githubusercontent.com`（另一台主机）。dart:io 自动重定向会原样重发全部头——Bearer 令牌随跳转发给第三方主机。
- 违反：原则 40（令牌只在必要的跳使用一次）、39。
- 级别：P0（凭证外泄）。
- 用户可见后果：用户查看 Actions 日志时，GitHub 访问令牌被自动发送到 results-receiver.actions.githubusercontent.com 之外的非预期重定向目标，令牌可能被收集。
- 修复：第一跳 `followRedirects = false` 带令牌请求；对 3xx 手动跟随，后续跳**剥离全部凭证头**（签名地址自带授权），只保留 accept，最多 5 跳，目标协议非法时如实报错。修复前 vs 修复后：修复前令牌随 302 自动转发；修复后令牌只在第一跳出现。

## 待议（记录不修）
- DATA-待议-1 · lib/base/disk/og_l_storage_saf_io.dart / platform_io_impl.dart：多处 `catch (_) {}` 空吞（原则 16/18），但文件头注释声明这是纯静态工具类、无诊断注入点的既定决策（R7 审计），改动涉及装配层重构，风险大于收益，仅记录。
- NET-待议-1 · lib/base/net/net_dns.dart `DnsCache.put` 淘汰为 O(n²) 扫描：条目上限 512，实际访问频率低，热路径影响有限，按原则 32 属可架构化但非确证 bug，仅记录。


---

## 主会话亲自审查补充（下载逻辑 + 仓库 API，2026-11-07）

> 范围：ix_download.dart（1524 行全文）、gh_client.dart（804 行全文）、repo_file_service.dart（2042 行全文）、ix_presign.dart（241 行全文）。
> 结论：**未发现 P0/P1 级新问题**。四份文件防御密度极高（回合制守卫、幂等收尾、哨兵语义、路径逐段编码、tree truncated 拒绝执行、SSRF 校验含整数形式 IPv4 归一化）。以下为 P2 观察项。

### DL-01（P2，仅记录）retry 与 resume 的连接数来源不一致
- **位置**：`lib/domain/ix/ix_download.dart` retry()（约 1440 行）vs resume()（约 1408 行）。
- **问题**：resume() 按 E-1 优先用 `preferredConnections`（用户当前设置）；retry() 仍用入队时快照的 `_rangeConnections[id]` 旧值。
- **违反原则**：34（状态单一来源的精神——同一语义两处取值）。
- **用户可见后果**：用户把并发从 8 改成 2 后，"继续"走 2 连接、"重试"仍走 8 连接，行为不一致但不出错。
- **不修理由**：行为差异轻微且 retry 用旧值并无数据风险；修复需触碰任务书约束的公共行为，留给后续版本。

### API-01（P2，仅记录）_probePath 把任意 422 也当"不存在"
- **位置**：`lib/domain/gh/repo_file_service.dart` _probePath()（约 1600 行）。
- **问题**：`GhAuthException` 的 404/409/422 一律返回 `_Probe.missing()`。404/409 语义正确（空仓库 409 = "没有"），但 422 也可能是校验失败类错误，被折叠成"目标不存在"后，create 会继续走上传并把 GitHub 的原始拒绝原因覆盖为"exists/notFound"方向外的误报。
- **违反原则**：16（捕获后转化为明确结果时不得丢失原语义）。
- **用户可见后果**：极端情形（服务端 422 校验拒绝）下用户看到"目标不存在"而真实原因是路径校验失败，排查方向被误导。
- **不修理由**：GitHub Contents API 对合法路径几乎不回 422；按注释与 `_isAbsentStatus` 同款语义处理是既有设计决策，改动影响 create/delete/rename 全链路，需实测留证后再动（质量原则 52：端点语义必须实测）。

### API-02（P2，仅记录）单文件 rename 丢失可执行位
- **位置**：`repo_file_service.dart` _sourceOfContent()（约 2000 行）。
- **问题**：Contents API 不返回文件 mode，单文件 rename/copy 按 100644 处理，可执行位丢失。代码内已注明"已知限制"。
- **用户可见后果**：对单文件（非目录批量）rename 一个 100755 脚本后，需手动恢复 +x。
- **不修理由**：API 能力限制，已留痕为已知限制；目录批量路径（tree）不受影响。

---

## v10.3.0 发布后深度复审（2026-11-07，主会话亲自完成）

> 范围：main.dart、kernel 全部（kernel/di/module_bus/lifecycle/environment/diagnostics/boot）、base 全部（net 8 文件 / disk 8 文件 / log）、domain_bridge、surface 核心（app 10 文件 / widgets 4 文件 / util 5 文件 / theme / settings / types）、pages 主要 15 个（repo_page 4053 行全文 / settings_page / dashboard / search / profile / login / file_preview / release_detail / action_run / gists / gist_detail / drafts / notifications / issue / commit / pull / new_* / download_manager / workflow_dispatch / about / onboarding / network_page / legal_text）。约 30,000 行全文通读。

### 审查结论
质量显著高于一般开源项目。防线密度、注释纪律、错误处理一致性都经得起逐行对照 QUALITY_STANDARD。以下为本次复审全部发现。

### 深审-01（P1，已修复）settings 语言白名单漏四种新语言
- **位置**：`lib/surface/settings.dart` languageCodes（原 `['zh','en']`）。
- **问题**：v10.3.0 新增四语言后未同步该白名单——用户在设置页选德/法/俄/繁中，`setLanguage` 判非法回落 `zh`，**选择即失效**（选择行显示已选、界面仍是中文，且落盘为 zh）。违反原则 45（版本单一真相的精神：同一事实两处清单不一致）。
- **修复**：白名单补齐 `zh_Hant/de/fr/ru` 并加同步警示注释。设置页语言选择行本身读 `OgLI18n.locales`（正确来源），仅存储白名单漏改。
- **教训**：新增语言改三处（locales / pubspec / 设备 locale）不够，第四处 `OgLSettings.languageCodes` 同样必须同步——建议后续为它加一致性测试。

### 深审-02（P2，仅记录）release_detail 创建成功用 warning 语气
- **位置**：`repo_page.dart` `_ReleasesTab._create`（约 :2775）。
- **问题**：创建 Release 成功提示用 `OgLNotifier.warning`（红色 error 横幅），应为 success/info。代理B曾记录为 UI-06，本次复核确认仍在。
- **不修理由**：语气统一批次问题，无功能影响。

### 深审-03（P2，仅记录）_ReleasesTab 缺 onManualRefresh 的 cacheBypass 传递链
- **位置**：`repo_page.dart` `_ReleasesTab._paged` 已设 `onManualRefresh`；但 `_pagedBody` 的下拉刷新走 `paged.refresh` → `_load(force: _shouldForce, ...)`，force 路径正确调 invalidateReadCache，链路实际闭环——复核后撤销此项，确认无问题。

### 深审-04（P2，仅记录）dashboard `_RepoPaged` 与 PagedController 双实现并存
- **位置**：`dashboard_page.dart` `_RepoPaged`（约 :520-593）vs `app/paged_controller.dart`。
- **问题**：语义几乎相同（世代/排队/释放保护三件套各写一份）。维护风险：竞态修复只改一处时另一处漂移。
- **不修理由**：`_RepoPaged` 少了快照层（首页不需要），行为差异是真实需求；统一属重构批次。

### 深审-05（P2，仅记录）ix_download 的 retry/resume 连接数来源不一致（原 DL-01 确认仍在）
- 与此前记录一致，维持不修理由。

### 复核确认无问题的关键设计（抽查重点）
- **TOKEN-EXIT-01 门禁**：白名单主机判定（`*.github.com` + 三个 githubusercontent 官方子域）、留痕、四接入点 mounted 检查全部正确；取消路径如实提示不入队。
- **async.dart 世代计数**：成功/异常/finally 三处回写全部校验世代，`_notify` 不受世代影响（dispose 语义独立）——UI-01 修复实现正确。
- **PagedController 快照 TTL 6s + 世代 + 刷新排队**：`clearCaches` 静态方法与切号清理链路（profile._switchTo → clearAllCaches + clearOgLRepoPageCaches）闭环。
- **disk_cache 七道防线**：D2′（基线在远端无）分支、D3 rebase 重试上限、D5 回读失败按"已提交待确认"处理（不误报失败）、D8 journal 状态机（fail/abandon 语义分明）、孤儿 blob 清理——逐条与注释一致。
- **net_transport 重试预算**：镜像跳不消耗预算、幂等方法白名单、Retry-After 优先——与文件头承诺完全一致。
- **net_dns RFC1035 编解码**：事务 ID 校验、AAAA 补零、压缩指针、DoH 只认 https——纯函数可单测承诺成立。
- **error_surface 通知管线**：去重 → 落盘 → 队列上限（保 critical）→ 后台转系统通知 → 回前台补发 → messenger 缺失 requeueFront——链条完整无静默路径。
- **og_l_log_file_io 跨天切换**：先装新句柄再关旧句柄的顺序处理正确。
- **ScrollAwareAction**：累积同向位移 + 换向清零 + 瞬移重标定 + opaque 手势层取舍——注释与实现逐字对应。
