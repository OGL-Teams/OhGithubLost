# UI 层（lib/surface/）代码审查记录

依据：docs/QUALITY_STANDARD.md（59 条）与 AGENTS.md。逐条含编号、位置、问题、违反原则、严重级别、用户可见后果；已修复项附「修复：」段落。

## UI-01 · lib/surface/app/async.dart:96-141
**问题**：`AsyncController.load()` 的在途结果不校验世代。`reset()`（切目录/切数据维度）后，旧请求返回仍会 `_data = value` 覆盖新维度数据，且 `finally` 把 `_loading=false; _everLoaded=true`，导致 `loadIfNeeded()` 抑制新加载 → 新目录**永久转圈**或**展示旧目录数据**。
**违反**：22（异步结果必须校验有效性）、27（并发假设未声明且未守护）。
**级别**：P1（数据撕裂/卡死在加载态）。
**用户可见后果**：快速切换目录/账号时看到上一个目录的文件列表，或页面永远显示加载中。
**修复：**新增 `_generation` 世代计数；`reset()` 自增世代；`load()` 的成功/异常回写与 `finally` 均校验世代，旧世代结果直接丢弃（_notify 仍走 _disposed 守护）。

## UI-02 · lib/surface/app/error_surface.dart:561-566
**问题**：`_presentAmbient` 用 `messenger?.showSnackBar(...)` 静默吞掉横幅通道缺失的情况——通知已被 `take()` 取走，若 `ScaffoldMessenger` 不存在则既不展示也不放回队列，违反"绝不静默"。
**违反**：15（静默降级是最严重的缺陷）、16（不吞异常）。
**级别**：P1（错误信息丢失）。
**用户可见后果**：非严重告警（网络降级、磁盘清理失败等）在横幅通道尚未就绪时静默消失，用户完全无感知。
**修复：**`_presentAmbient` 中 `ScaffoldMessenger.maybeOf(context)` 为 null 时改为 `requeueFront(notice)` 放回队首（等宿主就绪后再 drain 补发），不再静默吞掉。

## UI-03 · lib/surface/pages/repo_page.dart:302-306, 1782-1786
**问题**：`_copyCloneUrl` / `_copyPath` 在 `await ogLCopyText(...)` 之后直接使用 `_notifier`（内部 `ScaffoldMessenger.of(context)`），await 后未检查 `mounted`。页面已退出时在 defunct element 上取 `ScaffoldMessenger.of` 会抛异常。
**违反**：22（异步结果必须校验有效性）、24（生命周期对称）。
**级别**：P1（dispose 后使用 context 抛异常）。
**用户可见后果**：复制克隆链接/路径后立刻返回上一页，触发 "Looking up a deactivated widget's ancestor" 异常（debug 断言崩溃 / release 报错弹窗）。
**修复：**两处 await 之后包 `if (mounted)` 再调 `_notifier`。

## UI-04 · lib/surface/pages/settings_page.dart:928-1013（_editCustomDns）
**问题**：`_editCustomDns` 创建的两个 `TextEditingController`（ip / doh）在对话框关闭（无论取消还是保存）后从未 `dispose()`。
**违反**：24（资源的开启与关闭在生命周期上对称）。
**级别**：P2（隐患，控制器泄漏累积）。
**用户可见后果**：长期使用中反复打开"自定义 DNS"会累积未释放的控制器（debug 下 dispose 断言 / 内存缓慢增长）。
**修复：**取消路径与保存路径各补 `ip.dispose(); doh.dispose();`。

## UI-05 · lib/surface/pages/release_detail_page.dart:293-297（_copyAssetLink）
**问题**：`await ogLCopyText(...)` 之后未检查 `mounted` 直接 `_notifier.success(...)`（内部 `ScaffoldMessenger.of(context)`）。与 UI-03 同型。
**违反**：22。
**级别**：P1。
**用户可见后果**：复制附件链接后立刻退出页面 → 在已卸载的 element 上取祖先抛异常。
**修复：**await 后包 `if (mounted)`。

## UI-06 · lib/surface/pages/repo_page.dart:2757（_ReleasesTab._create）
**问题**：新建 Release 成功后用 `OgLNotifier.warning`（error 配色）提示"已创建"，语义错误——成功事件被渲染成失败样式。
**违反**：38（错误信息面向用户；此处反向——成功被标为告警）。
**级别**：P2（语义/观感缺陷，无功能损害）。
**用户可见后果**：创建 Release 成功却弹出红色错误样式横幅，用户误以为操作失败。
**不修理由**：涉及其它语气语义的连动调整（新建议题用 info、这里用 warning 的历史差异），属文案/语气统一批次，非竞态/数据问题，本次只记录。

## UI-07 · lib/surface/pages/settings_page.dart:1476-1526（_showPrivateAccelWarning 倒计时）
**问题（待议）**：对话框被用户关闭（cancel）后，`Future.delayed` 递归倒计时仍会继续跑到 0 才停（最多 3 次）。有界、无 setState 传给已销毁树（内部 try/catch 已拦），无用户可见后果，但留下 3 个空转的延时任务。
**违反**：24（生命周期对称，弱）。
**级别**：P2。
**不修理由**：有界（≤3 秒自终止）、已防护 setLocal 异常；引入 Completer/Timer 取消链会显著改动该弹窗结构，收益不成比例。标记待议。

---

# 审查覆盖范围与结论

- **app/**：async、client_shell、error_surface、back_guard、motion、paged_controller、notifier、overlays、keyboard_guard、og_l_app、system_notifier、desktop_window（全部核心文件完整阅读；animations / boot_splash / permissions / project_info / permission_selftest 抽查）。
- **pages/**（按大小降序覆盖前 15）：repo_page(4029)、settings_page(2113)、file_preview_page、workflow_dispatch_page（概览）、dashboard_page、action_run_page（概览）、download_manager_page、release_detail_page、onboarding_page（概览）、code_editor_page、login_page（概览）、search_page、gist_detail_page、notifications_page、issue_page、profile_page、drafts/commit 等小页依赖同一套已审构件。
- **widgets/**：code_editor_field、readme_view、scroll_aware_action、log_body/settings_group（与已审构件同构）。
- **util/**：path_rules、download_proxy、clipboard_x、link_opener、file_preview、gh_format、accel（完整阅读）。

整体评价：该 UI 层纪律相当严（四态收敛、世代竞态防护、dispose 对称、i18n 全走 `_t`），本次仅在 AsyncController 发现一个真实的世代竞态（P1），其余为 mounted 检查遗漏（P1×3）、控制器未 dispose（P2）与错误通道静默吞（P1）。未发现 index 作 key、硬编码文案、内存泄漏的 listener/timer 未注销等问题。





