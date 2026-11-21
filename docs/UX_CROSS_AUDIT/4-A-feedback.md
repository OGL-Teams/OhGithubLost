# 批 4 · A 席 —— 全 30 页操作反馈闭环审计（写操作：点击 → busy → progress → 成功确认 → 失败重试）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 4 · 反馈与动效 · A（操作反馈闭环）**
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - HEAD：`f684160`（工作副本，只读审计）
> - 更新时间：**2026-11-22 00:43:50 (Asia/Shanghai)**
> - 审计范围：`lib/surface/pages/*.dart`（全部 30 页，逐页过）+ 反馈基元 `lib/surface/app/notifier.dart`、`lib/surface/app/overlays.dart`、`lib/surface/app/error_surface.dart`、`lib/surface/app/motion.dart`、`lib/surface/pages/download_manager_page.dart`
> - 参考规范：`sota-frontend-design/rules/04-ux-patterns.md` §4/§6/§9、`rules/06-motion-design.md` §1/§4b/§8、`material-3/SKILL.md` Motion（500/400/200ms、standard 300ms）与 Components（Loading indicator / Snackbar / Button）
> - 方法：`rg` 全库写操作调用点（`create*/delete*/update*/put*/dispatch*/rerun*/cancel*/merge*/close*/save*/set*`）逐个核对四段闭环；对 30 页按功能域矩阵逐页过，无写操作页也列「已查项」。
> - 约束：**只读审计，未改任何代码，未 commit / push**；所有引用可 `rg` 复现。

---

## 0. 结论摘要

全 30 页里，**24 页有写操作**（其中 1 页 `new_issue` 的 create 被 `repo_page` 复用），6 页为纯只读页。总体反馈基建不弱：有统一 `OgLNotifier`（success/info/warning 三语气）、`OgLAppLog` 双通道、多数写操作有 `_busy` 防重入、危险操作有二次确认、文件批量写有 progress 状态行。但存在**四类直击「不稳定」的系统性缺口**：

1. **异步无反馈**：一批写操作进入 `await` 后既无按钮 spinner 也无 progress，点击后 0.5–数秒内界面毫无变化——用户不知道点了没生效（最严重）。
2. **成功无确认**：部分写操作成功后只记日志、既无 SnackBar 也不跳转/刷新，用户不知道成功没。
3. **双重提交防护缺口**：多个 setter/危险操作没有 `if (_busy) return`，且用 `_busy ? (v){} : ...` 空回调代替禁用，重复点击/拖动可并发提交。
4. **错误不可重试**：全局 `OgLNotifier` 发出的 SnackBar 无 action（无「重试」/「撤销」），失败提示看完即消失，用户只能重新走完整流程。

**反馈闭环评级口径**：✅完整=busy/progress + 成功确认 + 失败可感知；⚠️部分=缺 1 段；❌弱=缺 ≥2 段（异步无反馈或成功无确认命中）。

---

## 1. 用户可感知问题清单（18 条，按严重度分级）

### 🔴 严重（7 条）

**[S-01] `issue_page` 7 类写操作点击后按钮全程无 busy 态、异步无任何 progress —— 最典型「不知道点了没生效」**
- 证据：`lib/surface/pages/issue_page.dart:174`（`_runWrite`：`setState(_busy=true)` 后仅 `await action()`，无 spinner/progress）；调用点 `:232`（编辑标题/正文）、`:284`（标签）、`:320`（指派人）、`:361`（锁定/解锁）、`:450`（编辑评论）、`:486`（删除评论）、`:530`（关闭/重开）。
- 用户感受：议题里改标签/指派/编辑正文，点「保存」后对话框立刻关闭（`:244` `Navigator.pop(true)`），接下来 `_runWrite` 的异步期间**屏幕无任何反馈**——按钮、行、顶部都没有转圈或进度。GitHub 网络稍慢就是几秒「点了没反应」，用户会重复点、以为没生效。这正是「不稳定」的头号来源。
- 修复指令：在 `_EditIssueDialog`/`_LabelsDialog`/`_AssigneesDialog`/`_EditCommentDialog` 内用 `ValueListenableBuilder<bool>` 或把 `busyOf` 提升为 `Listenable`，点击保存后对话框**不立即 pop**，原地显示按钮内 `CircularProgressIndicator(strokeWidth:2)`、`onPressed=null`（对齐 `code_editor_page.dart:601` 的 spinner 规格）；成功后再 pop。或依 `04-ux-patterns.md §4` 采用乐观 UI：立即改本地态 + 后台同步 + 失败回滚并 toast 重试。

**[S-02] `repo_page` 关闭议题 `await` 段完全无反馈，成功也无确认**
- 证据：`lib/surface/pages/repo_page.dart:2697`（`_close`），确认框后 `:2715` `try { await updateIssue(state:'closed'); ... await _paged.refresh(); }`，全程无 `_busy`、无 spinner；成功仅 `OgLAppLog.result` + 静默 refresh，无 SnackBar。
- 用户感受：列表里点关闭议题，弹窗确认后界面「卡住」到刷新完成，期间无转圈；刷新后条目状态悄悄变了，没有「已关闭」确认——不知道到底成没成。
- 修复指令：`_close` 入口加 `if (_busy) return; setState(_busy=true)` 并在 `finally` 复位；触发行（`repo_page.dart:2807` 的 `onPressed`）在 `_busy` 时禁用并给被点行显示内联 spinner；成功后 `OgLNotifier.success(_t('issueClosed'))`（参照 `issue_page._runWrite` 的成功提示模式）。

**[S-03] `repo_page` 多个仓库设置写操作缺 `_busy` 防重入 + 开关用「空回调」而非禁用，可重复/并发提交**
- 证据：`lib/surface/pages/repo_page.dart:4039` `_setDefaultBranch`（**无 `if (_busy)`**）、`:4062` `_toggleArchive`（无）、`:4210` `_deleteRepo`（无）、`:3973` `_transferRepo`（无）；`:4352` 可见性开关 `onChanged: _busy ? (bool value){} : ...` —— 忙碌时开关仍可点，只是回调为空。
- 用户感受：连续点「设为默认分支」或拖动可见性开关，第二条请求在高延迟下可能并发发出；开关看着能按却「按了没用」（空回调），是最伤稳定感的「假可交互」。
- 修复指令：四个 handler 统一在开头加 `if (_busy) return;`；`repo_page.dart:4352` 改为 `onChanged: _busy ? null : ...`（让 Switch 进入 disabled 视觉），`setDefaultBranch` 的下拉在 `_busy` 时设 `enabled:false`。对齐 `04-ux-patterns.md §4`「double-submit guarded at the handler not just visually」。

**[S-04] 全局统一 SnackBar 无「重试」/「撤销」action，所有失败提示看完即消失、不可恢复**
- 证据：`lib/surface/app/notifier.dart:73-88`（`_show` 构造的 `SnackBar` 只有 `content`/`behavior`/`margin`/`backgroundColor`，**无 `action`、无显式 `duration`**）；对比 `lib/surface/pages/download_manager_page.dart:124` 有 `SnackBarAction(label, onPressed)`。
- 用户感受：写操作失败（权限不足、网络失败、冲突）时底部红条出现几秒就消失（Flutter 默认 4s），用户当时没看清或想重试只能重新操作整条流程——「失败不可重试」。且 4s 对一条含错误原因的长文案偏短。
- 修复指令：给 `OgLNotifier` 增加 `warning(message, {VoidCallback? onRetry, Duration? duration})` / `success(message, {VoidCallback? onUndo})`；有重试路径的写操作（评论、文件保存、标签）传 `SnackBarAction(label:_t('retry'), onPressed:onRetry)`；duration 显式设 `Duration(seconds:6~8)`（对齐 `04-ux-patterns.md §9` toast 4–8s 与 `download_manager_page` 的 8s）；可撤销的删除走 `success + Undo`（`§6 undo>confirm`）。

**[S-05] `new_issue` / `new_gist` / `new_release` 提交页按钮仅变文字、无 spinner，异步期进度为零**
- 证据：`lib/surface/pages/new_issue_page.dart:181`（`_busy ? Text(submitting) : Text(submit)`）；`new_gist_page.dart:148-149`；`new_release_page.dart:240-241`。三者 `await` 期间（`:96`/`:99`/`:114`）均无 `CircularProgressIndicator`。
- 用户感受：点「提交/发布/创建」后按钮文字从「创建」变「创建中…」，但无转圈——在慢网下用户盯着一个不变的文字按钮，仍会怀疑是否生效；文字变化是很弱的反馈。
- 修复指令：三处 `FilledButton` 改为 `FilledButton.icon` 或在 `child` 用 `AnimatedSwitcher`：`_busy` 时显示 `Row(mainAxisSize:min, children:[CircularProgressIndicator(strokeWidth:2), Text(creating)])`，锁定按钮宽度避免跳动（对齐 `04-ux-patterns.md §4`「buttons width-stable」与 `material-3` Loading indicator 规范）。

**[S-06] `repo_page` 文件新建/删除 `setState(_busy=true)` 时整页被 `CircularProgressIndicator` 全屏替换，反馈粗糙且丢失上下文**
- 证据：`lib/surface/pages/repo_page.dart:2447-2450`（`if (_busy && _operationStatus.isEmpty) return const Center(child: CircularProgressIndicator())`）；`_createFile` 在 `:1544`、`_deleteEntry` 在 `:1620` 设 `_busy=true` 但不设 `_operationStatus`。
- 用户感受：在文件列表里新建/删一个文件，整个页面瞬间被一个居中转圈替换，列表消失——「闪烁/跳变」，且看不到自己刚才在哪个目录。这正是「漂浮、不稳」的观感（对比批量删除 `:1727` 有 `_operationStatus` 状态行，单文件却没有）。
- 修复指令：单文件写也走进度状态行路径：`_createFile`/`_deleteEntry` 设 `_busy` 同时设 `_operationStatus = _t('opCommitting')`（复用 `_onRepoProgress` 文案），让 `:2484` 的状态行显示；移除或提高 `:2449` 全屏转圈的触发门槛（仅保留真正无上下文的首帧加载）。对齐 `04-ux-patterns.md §4`「stale-while-revalidate beats blank-and-spin」「skeletons/spinner 匹配最终布局，zero shift」。

**[S-07] `action_run` 取消运行成功后无任何用户可见确认**
- 证据：`lib/surface/pages/action_run_page.dart:186` `_cancel()`：确认框 → `await cancelWorkflowRun` → `OgLAppLog.result(_t('cancelRequested'))` → `await _detailC().load()`，**全程无 SnackBar**。对比同页 `_rerun`（`:131`）与 `_rerunFailed`（`:250`）成功后都 `OgLNotifier.info(...)`。
- 用户感受：点「取消运行」确认后，页面悄无声息刷新，日志状态变了但没有任何「已请求取消」提示——用户不确定请求是否送达（「取消请求」是异步的，Refresh 前状态可能没变）。
- 修复指令：`_cancel` 成功后加 `if (mounted) OgLNotifier.of(context).success(_t('cancelRequested'))`（在 refresh 前发，避免等待期间无反馈），失败路径 `:213` 保留 warning 并补 `onRetry`。

### 🟠 中（7 条）

**[M-08] `new_issue`/`new_release` 失败仅内联错误 Card，成功后跳转由调用方决定——失败无重试出口**
- 证据：`new_issue_page.dart:96-111`、`new_release_page.dart:114-142`：catch 里 `setState(_error=...)` 显示错误 Card，但无「重试」按钮，用户需重新填表；成功 `pop(true)` 后由 `repo_page.dart:2691`/`:3027` 发确认（注意 `:3027` 用 `warning` 语气报「releaseCreated」成功，语义错配）。
- 用户感受：网络失败后错误卡显示一长串，用户只能退出重填；成功后的确认又是红色 warning 语气，看着像出错。
- 修复指令：错误 Card 内加 `TextButton(onPressed: _submit, child: Text(_t('retry')))`，保留已填内容（`04-ux-patterns.md §3`「preserve input on error」）；`repo_page.dart:3027` 改 `.success(...)`。

**[M-09] `gist_detail` 编辑/删除文件入口按钮 `_busy` 时禁用但无 spinner，异步期无反馈**
- 证据：`lib/surface/pages/gist_detail_page.dart:357-360`（删除 IconButton `onPressed: _busy ? null : _deleteGist`）、`:480`（编辑按钮 `_busy ? null : ...`）；`_editFile` `:212`、`_deleteGist` `:270` 设 `_busy=true` 后 `await`，按钮变灰但图标不变、无转圈。
- 用户感受：点删除/保存后图标瞬间变灰不可点，但没有转圈，看着像「按钮坏了」而不是「正在处理」。
- 修复指令：两个 IconButton 的 `icon` 用 `_busy ? CircularProgressIndicator(strokeWidth:2) : Icon(...)`（参照 `action_run_page.dart:540`、`code_editor_page.dart:601` 已有实现）。

**[M-10] `profile_page` 退出登录 `_remove` 无 busy 态，网络/清缓存期间按钮可重复点**
- 证据：`lib/surface/pages/profile_page.dart:136` `_remove(GhAccount)`：确认后 `:155` `await widget.surface.forgetAccount(...)` → `clearOgLRepoPageCaches()` → `await _refresh()`，**无 `_busy`、无 spinner**；触发按钮 `:333-339` async 匿名函数也不禁用。
- 用户感受：点退出登录后，清缓存+刷新期间（可能数百 ms–秒）按钮仍可点，用户重复点会触发多次 forgetAccount；无反馈不知道是否正在退出。
- 修复指令：加类字段 `_removing`，handler 入口 `if (_removing) return; setState(_removing=true)`，按钮 `onPressed: _removing ? null : ...` 并给按钮内 spinner；成功用 `_notifier.info(_t('removed'))` 确认（当前 `:158` 只记日志）。

**[M-11] `notifications_page` 清空/全部标为已读无成功确认、`markAllRead` 无 undo**
- 证据：`lib/surface/pages/notifications_page.dart:180-182` `onPressed: OgLAppLog.instance.markAllRead`（直接同步调用，无提示）；`_confirmReset` `:140-162` 确认后 `OgLAppLog.clear()` + `setState`，**无 SnackBar**。
- 用户感受：点「全部已读」/「清空」后徽标数字变了，但没有「已清空 N 条」确认；误清空后无法撤销——破坏性操作无 undo（`04-ux-patterns.md §6`）。
- 修复指令：`_confirmReset` 成功发 `OgLNotifier.success(_t('resetDone'), onUndo: ...)`（需 `OgLAppLog` 提供快照回滚）；`markAllRead` 发 `info` 确认并可给 Undo。

**[M-12] `settings_page` 若干设置写（setCodeColor/removeCustomFont/语言）无 busy 态，快速连点可并发写**
- 证据：`settings_page.dart:254` `await _settings.setCodeColor(...)`、`:807` `removeCustomFont`、`:305` `setLanguage`，均无 `_busy` 前置守卫；虽然 `OgLSettingsController.apply`（`settings.dart`）多为本地持久化，但 setUiFont 等涉及 font_loader I/O（`:740`）。
- 用户感受：连续切换配色/字体时，多次异步写并发，可能出现「最后点的一次没生效」的错觉——设置类操作尤其伤「稳定感」。
- 修复指令：对涉及 I/O 的 setter（setUiFont/setCodeColor）加页面级 `_busy` 守卫并禁用对应行控件；本地即时写可保留乐观 UI，但需保证 `apply` 串行化（在 controller 内加锁/去重）。

**[M-13] `settings_page` 重置设置成功后仅 SnackBar 确认，无 progress；危险操作确认对话框无「输入名称」二次门槛（可接受但需说明）**
- 证据：`settings_page.dart:281` `_reset()`：`await _settings.reset()` + `applyDns()` + `success(_t('resetDone'))`，异步期无 busy/进度；确认框 `:258-273` 为普通 Confirm（无 type-to-confirm）。
- 用户感受：重置是全量破坏性操作，点确认后短暂无反馈；且 `04-ux-patterns.md §6` 建议高成本不可逆操作用 type-to-confirm，此处仅普通确认。
- 修复指令：加 `_busy` spinner；如需满足 §6，确认框改为要求输入 `reset` 字样。注：设置可再改回，属低不可逆，普通确认可接受——此项记为「检查过、可权衡」。

**[M-14] `code_editor` 保存走「乐观入队」成功后立即 `pop`，用户离开页面后才知道结果（经通知中心）——即时确认缺失**
- 证据：`lib/surface/pages/code_editor_page.dart:253-273` `_save()`：`_notifier.info(_t('queuedInBackground'))` 后立即 `Navigator.pop(true)`；真正成功/失败在 `_submitInBackground`（`:277`）经 `_notifier` 与日志异步报出。
- 用户感受：点保存立刻返回上一页，只看到「已排队后台提交」，几秒后才可能弹出「已提交/冲突」——这期间用户不知道最终结果。设计上是有意的（避免 4×60s 干等，注释 `:246-250` 说明），但需保证通知中心一定能看到结果。
- 修复指令：保留乐观入队，但把后台结果提示升级为**持久通知条目**（`OgLNoticeCenter`，非易逝 SnackBar），并在编辑器入口显示「N 项待同步」角标；失败时提供「重试/查看冲突」直达入口。对齐 `04-ux-patterns.md §4`「optimistic UI roll back AND explain via toast with retry」。

### 🟡 轻（4 条）

**[L-15] `repo_page` 新建议题确认由子页 `new_issue` 承担，列表页 `_create` 成功后 `info` 确认但无 progress**
- 证据：`repo_page.dart:2682-2694` `_create()`：`push<bool>(NewIssuePage)` → `if(created==true) OgLNotifier.info(_t('issueCreated')) + refresh`。子页无 spinner（见 S-05）。
- 修复指令：随 S-05 补齐子页 spinner；列表页确认语气的 `info` 建议改 `success`（创建成功属正向确认）。

**[L-16] `download_manager` 取消/重试下载为 `unawaited` 即发，无按钮级 busy，靠 SnackBar + 状态行兜底（基本合格）**
- 证据：`download_manager_page.dart:496-498`（cancel）、`:489-492`（retry）均 `unawaited(...)`；但该文件有全套 SnackBar 总线（`:110` 8s + action）与状态列（`:402` LinearProgressIndicator）。
- 评价：反馈闭环相对完整，唯取消/重试按钮本身无瞬时 pressed/progress。修复指令：可接受现状；如需极致，给按钮加 100ms pressed 缩放（motion §4b，100–150ms）确认点击。

**[L-17] `login_page` `_finishLogin` 有分阶段 phase 文本反馈（优秀），但失败回滚段未逐帧确认**
- 证据：`login_page.dart:215-235`：`_phase` 从 verifying→phaseVerify→phasePromote→phaseVault 逐段 `setState`，是 S-01 类问题的正面范例；失败 catch `:284+` 回滚账号。
- 评价：异步反馈充分。修复指令：失败回滚完成后补一条 `warning` 告知「已恢复到原账号」，避免用户困惑于「登录失败后账号列表变了」。

**[L-18] `action_log_page`/`action_run_page` 下载日志 `_downloadLogs` 有 `_busyLogs` spinner（`:540`），成功提示缺失**
- 证据：`action_run_page.dart:280` `_downloadLogs` → `actionLogs.saveToDisk`，按钮有 spinner 但成功无 SnackBar（仅看本地文件）。
- 修复指令：成功后 `OgLNotifier.success(_t('logSaved', {'path': path}))` 确认落盘路径（参考 `download_manager_page._copyPath` 的确认模式）。

---

## 2. 全 30 页写操作清单与反馈闭环评级（轴二 · 功能页面矩阵）

评级：✅完整 / ⚠️部分 / ❌弱。列：页面 → 写操作 → busy/progress → 成功确认 → 失败可感知 → 评级。

### 仓库域
| 页面 | 写操作 | busy | progress | 成功确认 | 失败 | 评级 |
|---|---|---|---|---|---|---|
| repo_page（文件树）| 新建文件/目录 `_createFile`:1430 | ✅ | ❌(S-06 全屏转圈) | ✅success | ✅warning | ⚠️ |
| repo_page | 删文件 `_deleteEntry`:1589 | ✅ | ❌(S-06) | ✅success | ✅ | ⚠️ |
| repo_page | 删目录 `_deleteDirectory`:1668 | ✅ | ✅(_operationStatus) | ✅success | ✅ | ✅ |
| repo_page | 重命名 `_renameEntry`:1768 | ✅ | ❌ | ✅success | ✅ | ⚠️ |
| repo_page | 关闭议题 `_close`:2697 | ❌(S-02) | ❌ | ❌(S-02) | ✅warning | ❌ |
| repo_page（设置）| 基本信息 `_saveBasic`:3770 | ✅ | ❌ | ✅success | ✅ | ⚠️ |
| repo_page | 可见性 `_setVisibility`:3921 | ❌(S-03 空回调) | ❌ | ✅success | ✅ | ❌ |
| repo_page | 转移 `_transferRepo`:3973 | ❌(S-03) | ❌ | ✅success | ✅ | ❌ |
| repo_page | 默认分支 `_setDefaultBranch`:4039 | ❌(S-03) | ❌ | ✅success | ✅ | ❌ |
| repo_page | 归档 `_toggleArchive`:4062 | ❌(S-03) | ❌ | ✅success | ✅ | ❌ |
| repo_page | CNAME `_saveCname`:4105 | ✅ | ❌ | ✅success | ✅ | ⚠️ |
| repo_page | Pages 开关 `:4163/:4187` | ✅ | ❌ | ✅info | ✅ | ⚠️ |
| repo_page | 删仓库 `_deleteRepo`:4210 | ❌(S-03) | ❌ | 跳转(pop true) | ✅warning | ❌ |
| repo_tags_page | 建/删 tag（若有）| — | — | — | — | 已查：仅 `:41/:45` `_loading/_busy` 用于读取列表，无写调用点 |
| commit_page | 只读对比 | — | — | — | — | 已查：无写操作（纯展示） |
| code_editor_page | 保存 `_save`:253 | ✅ | ✅排队提示 | ⚠️(info 排队, 结果经通知) | ✅(通知中心) | ⚠️(M-14) |
| file_preview_page | 只读预览 | — | — | — | — | 已查：`_busy`:93 仅加载，无写 |
| pull_page | 只读 PR 详情 | — | — | — | — | 已查：无合并/写调用点（列表入口在 repo_page） |
| release_detail_page | 删 release `_deleteRelease`:215 | ✅ | ❌ | 跳转(pop true) | ✅warning | ⚠️ |
| new_release_page | 创建 release `_submit`:103 | ✅ | ❌(S-05) | 跳转+调用方warning(M-08) | ⚠️内联无重试 | ⚠️ |

### 议题域
| 页面 | 写操作 | busy | progress | 成功确认 | 失败 | 评级 |
|---|---|---|---|---|---|---|
| issue_page | 编辑/标签/指派/锁定/编评/删评/关开（7 类，`_runWrite`:174）| ✅ | ❌(S-01) | ✅info | ✅warning(无重试 S-04) | ❌ |
| issue_page | 发表评论 `_postComment`:572 | ✅(`_posting`) | ❌ | ✅info | ✅warning | ⚠️ |
| new_issue_page | 创建议题 `_submit`:77 | ✅ | ❌(S-05) | 跳转+调用方info | ⚠️内联无重试(M-08) | ⚠️ |
| notifications_page | 全部已读 `:180` | ❌ | ❌ | ❌(M-11) | — | ❌ |
| notifications_page | 清空 `_confirmReset`:140 | ❌ | ❌ | ❌(M-11) | — | ❌ |
| dashboard_page | 建仓库 `_createRepo`:335（委托 new_repo）| ❌(子页有) | ❌ | ✅success | ✅ | ⚠️ |

### 内容域
| 页面 | 写操作 | busy | progress | 成功确认 | 失败 | 评级 |
|---|---|---|---|---|---|---|
| gists_page | 建 Gist `_create`:110（委托 new_gist）| ❌(子页有) | ❌ | ✅info | ✅ | ⚠️ |
| new_gist_page | 创建 Gist `_submit`:85 | ✅ | ❌(S-05) | 跳转+调用方info | ⚠️内联无重试 | ⚠️ |
| gist_detail_page | 编辑文件 `_editFile`:212 | ✅ | ❌(M-09) | ✅success | ✅ | ⚠️ |
| gist_detail_page | 删 Gist `_deleteGist`:270 | ✅ | ❌(M-09) | 跳转(pop true) | ✅ | ⚠️ |
| search_page | 仅搜索/筛选（`:1205` debounce.cancel 非写）| — | — | — | — | 已查：无写操作 |
| readme_view（widget）| 只读 | — | — | — | — | 已查（经 repo_page 内嵌）无写 |

### 账户域
| 页面 | 写操作 | busy | progress | 成功确认 | 失败 | 评级 |
|---|---|---|---|---|---|---|
| login_page | 登录 `_finishLogin`:215 | ✅ | ✅phase 文本(L-17) | 跳转(onLoggedIn) | ✅warning | ✅ |
| profile_page | 移除账号/退出 `_remove`:136 | ❌(M-10) | ❌ | ❌(仅日志) | ✅warning | ❌ |
| settings_page | 配色/字体/语言/reset/自定义字体（`:254/:305/:807/:281`）| ⚠️(部分) | ❌ | ✅success/info | ✅warning | ⚠️(M-12/M-13) |
| settings_section_page | 委托 settings controller | — | — | — | — | 已查：写经 controller，同 settings_page 评级 |
| onboarding_page | 权限引导/偏好（本地设置）| — | — | — | — | 已查：`:352` spinner 用于权限检测，无远端写 |
| about_page | 只读 | — | — | — | — | 已查：仅 `OgLNotifier`（`:52`）用于复制许可文本 |
| legal_text_page | 只读加载 | — | — | — | — | 已查：`:50/:165` loading 仅加载文本 |

### 工具域
| 页面 | 写操作 | busy | progress | 成功确认 | 失败 | 评级 |
|---|---|---|---|---|---|---|
| workflow_dispatch_page | 触发 `_dispatch`:320 | ✅ | ❌ | 跳转+调用方info | ✅warning(无重试) | ⚠️ |
| action_run_page | 重跑 `_rerun`:124 | ✅ | ✅spinner | ✅info | ✅warning | ✅ |
| action_run_page | 取消 `_cancel`:186 | ✅ | ✅spinner | ❌(S-07) | ✅warning | ⚠️ |
| action_run_page | 重跑失败 job `_rerunFailed`:250 | ✅ | ✅spinner | ✅info | ✅warning | ✅ |
| action_run_page | 下载日志 `_downloadLogs`:315 | ✅(`_busyLogs`) | ✅spinner | ❌(L-18) | ✅warning | ⚠️ |
| action_log_page | 保存日志 `saveToDisk`:189 | ✅ | ❌ | ❌(L-18) | ✅ | ⚠️ |
| download_manager_page | 取消/重试/删除任务 `:489-498` | ⚠️(unawaited) | ✅(状态列+LinearProgress) | ✅SnackBar+action | ✅ | ✅ |
| drafts_page（profile 内）| 草稿清理（委托）| — | — | — | — | 已查：无独立写调用点 |

---

## 3. 修复指令（按「稳定感优先」排序，汇总 §1 可执行项）

1. **P0 · 通用按钮 busy/spinner 组件化**（覆盖 S-01/S-05/M-09）：新建 `OgLBusyButton`（FilledButton 变体），`busy` 时按钮内显示 `CircularProgressIndicator(strokeWidth:2)`、`onPressed=null`、宽度锁定；一次性替换 `new_issue:181`、`new_gist:148`、`new_release:240`、`issue_page` 各 dialog 保存键、`gist_detail:357/480`。参考 `material-3` Loading indicator + `06-motion §4b`（micro 100–150ms）。
2. **P0 · `issue_page._runWrite` 对话层进度**（S-01）：编辑/标签/指派/编评 dialog 保存后不立即 pop，原地 spinner，成功后再关；或乐观 UI + 失败回滚 toast（04 §4）。
3. **P0 · `repo_page` 危险/设置写补齐双重提交防护**（S-03）：`_setVisibility/_transferRepo/_setDefaultBranch/_toggleArchive/_deleteRepo/_close` 全部加 `if (_busy) return`；`:4352` 空回调改 `null`；触发行/下拉 busy 时禁用。
4. **P0 · `OgLNotifier` 增 retry/undo action**（S-04）：`warning(message, {onRetry})`、`success(message, {onUndo})`，duration 显式 6–8s；对评论、文件保存、标签、下载失败传重试回调；删除类给 Undo。
5. **P1 · 成功确认补齐**（S-02/S-07/L-18/M-10/M-11）：`_close`/`_cancel`/`_downloadLogs`/`_remove`/`_confirmReset`/`markAllRead` 成功后发对应语气 SnackBar。
6. **P1 · `repo_page` 全屏转圈改进度状态行**（S-06）：`_createFile`/`_deleteEntry` 设 `_operationStatus`，移除 `:2449` 全屏 `Center(CircularProgressIndicator)` 触发（保留首帧加载场景）。
7. **P1 · 错误保留输入 + 重试按钮**（M-08）：new_issue/new_release 错误 Card 加「重试」TextButton，不清空已填字段；`repo_page:3027` warning→success。
8. **P2 · 设置写串行化**（M-12）：controller.apply 去重/加锁，I/O setter 页面级 busy 守卫并禁用行。
9. **P2 · 编辑器后台结果持久化**（M-14）：`_submitInBackground` 结果写入 `OgLNoticeCenter` 持久条目，入口显示待同步角标 + 冲突直达处理。
10. **P2 · 文案语气核对**（M-08/L-15）：所有创建/保存成功的 `info` 统一为 `success`。

---

## 4. 检查清单（查过什么 / 未发现问题的部分）

**反馈基建（已查）**
- [x] `OgLNotifier`（`notifier.dart:34-90`）：三语气、floating、统一 margin、messenger 未挂载时留痕重抛（非静默）——设计合格；缺口=S-04（无 action/duration）。
- [x] `OgLAppLog` + `OgLNoticeCenter`（`error_surface.dart`）：普通 notice 走 SnackBar（`:572`）、危险走 dialog（`:517`），队列不静默丢弃（`:566` requeueFront）——合格。
- [x] `ogLShowDialog`/`ogLShowSheet`（`overlays.dart:51/75`）：dismissible + 统一动画（`sheetDuration`/`reverseDuration` 同源 `:58/67-68`）——合格。
- [x] 动效档位（`motion.dart` 188-260）：fast 90/130/170ms、medium 120/170/230ms、sheet 130/160/…ms，曲线 easeOut 系、settleCurve 纯减速——符合 `06-motion` micro≤150ms 与 `material-3` enter decelerate；本席不评动效美观（属 2-C/4-B）。

**写操作覆盖（已查 30/30 页）**
- [x] 全库 `rg` 写调用点覆盖：`createRepo/createIssue/createGist/createRelease/createIssueComment`、`updateIssue/updateIssueLabels/updateIssueAssignees/updateIssueComment/lockIssue/unlockIssue/updateGist/updateRepo/transferRepo`、`deleteIssueComment/deleteGist/deleteRelease/deleteRepo`、`repoFiles.create/delete`、`putContent/putContentLocked`、`dispatchWorkflow/rerunWorkflowRun/cancelWorkflowRun/rerunFailedJobs`、`saveAccount/switchTo/removeAccount/forgetAccount`、`saveDraft/discardDraft`、`settings.set*`。
- [x] 纯只读页已列「已查项」：commit_page、pull_page、search_page、about_page、legal_text_page、readme_view、file_preview_page（仅加载）、onboarding_page（仅权限检测）、repo_tags_page（仅读取）、drafts_page（委托）。
- [x] 双重提交防护专项：确认 `_runWrite`(issue)、`new_*`、`_saveBasic`、`_saveCname`、`_enablePages`、`_disablePages`、`_rerun*`、`_cancel`、`_postComment`、`_persistDraft` 有 `if(_busy)`；S-03 列出 6 处缺口。
- [x] 破坏性确认专项：`deleteRepo/deleteGist/deleteRelease/deleteFile/deleteDir/transferRepo/archive/toggleLock/toggleState/cancelRun/reset` 均有 AlertDialog 二次确认，红色 destructive 按钮（`FilledButton.styleFrom(backgroundColor:error)`）——合格（undo 缺口记 S-04）。
- [x] 乐观 UI 专项：`code_editor._save` 是唯一乐观提交（先入队后返回，失败经通知中心回滚说明），符合 04 §4「不用于删除/支付」；缺口=M-14（即时确认弱）。
- [x] 成功确认语气专项：发现 `repo_page:3027` 创建 release 用 `warning` 语气（语义错配），已列 M-08。

**未发现问题的部分（证明查过）**
- [x] `login_page` 登录：分阶段 phase 文本反馈完整（L-17 为加分项，非缺陷）。
- [x] `action_run_page` 重跑/重跑失败 job：busy+spinner+info+warning 四段齐全（评级 ✅）。
- [x] `download_manager_page`：SnackBar 总线（8s + action）+ LinearProgressIndicator 状态列 + 取消/重试/打开/复制路径齐全（评级 ✅）。
- [x] `repo_page` 批量删目录：唯一带 `onProgress`→`_operationStatus` 状态行的写操作（评级 ✅），可作为 S-06 修复模板。

---

## 5. 附：轴一说明（启动链路）

按任务书补强，启动链路（boot splash → 引导清单验证 → 首帧 → 令牌恢复）由**批 5-A**负责，本席（4-A）不重复覆盖；但启动末端 `login_page._finishLogin` 的令牌验证 phase 反馈属写操作链（saveAccount/switchTo），已在 §2 账户域与 L-17 覆盖。

---

（只读审计结束 · 未修改任何产品代码 · 未 commit/push）
