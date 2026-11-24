# 批 4 · B 席 —— 反馈闭环复审（写操作 busy/成功/失败 + SnackBar 三语气可辨性）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 4 · 动效与反馈 · B（反馈闭环复审）**
> - 版本：**v15.0.0**（`pubspec.yaml:21` → `version: 15.0.0+150000`）
> - HEAD：`46981c0`（工作副本，只读审计）
> - 更新时间：**2026-11-24 22:52:13 (Asia/Shanghai)**
> - 审计范围：`lib/surface/app/notifier.dart`、`lib/surface/app/error_surface.dart`、`lib/surface/pages/issue_page.dart`、`lib/surface/pages/repo_page.dart`（全 4612 行过写操作段）+ 全库 24 个写操作页 `rg` 复核
> - 参考规范：`sota-frontend-design/rules/06-motion-design.md`（§1 反馈目的、§8 反馈即时性）、`rules/04-ux-patterns.md` §4（loading/乐观 UI/防重入）、§6（破坏性操作 undo>confirm）、§9（100ms 反馈 / toast 4–8s / 真实进度）
> - 方法：旧确证 F-01/F-02/F-03/F-05/F-18/F-20/4-C C-02 逐条对照 v15 代码；全库 `api.*写调用` 42 个调用点逐个核对四段闭环；三语气 200+ 调用点逐点读语义
> - 约束：**只读审计，未改任何代码，未 commit/push**；所有引用可 `rg` 复现；未读取任何 Flutter SDK / pub 缓存源码。

---

## 0. 结论摘要

v15 的反馈闭环改造**大体落地且质量高**：`OgLNotifier` 三语气实现为「底色 + 前置图标 + 文字色」三重区分（`notifier.dart:124-139`），success=primaryContainer+✓图标、info=secondaryContainer+ℹ图标、warning=error底+⚠图标——**色相差明显（蓝系容器 vs error 红），明暗两档均可辨**，旧 4-C C-02「只差文字色」确已修复。issue_page 七类写操作全部实现「对话框内原地 spinner + 成功才 pop + 失败留在对话框」（F-01 修复），repo_page 关议题/仓库设置写全部补齐 `_busy` 防重入与成功 success 确认（F-02/F-05/F-18 修复）。

**但仍存三类残留**：① **失败提示全库零「重试」出口**（`OgLNotifier.notice` 的 `actionLabel/onAction` 参数已存在，但除下载页「查看下载」外**无任何一处**用它传 retry/undo——S-04 只修了一半）；② **两处成功提示仍用 warning 红语气**（`repo_page.dart:3046` 创建 release、`repo_page.dart:3232/3273/3311/4280` 分支增删改**成功后完全无提示**仅记日志）；③ 约 **9 处写操作无页面级 busy/防重入**（profile 退出登录、notifications 清空/全部已读、drafts 删除、gists/dashboard 创建入口、settings 字体 I/O、repo 分支增删改、issue 锁定/关开确认对话框期间）。

---

## 1. 闭环核对（旧确证逐条判定）

| 编号 | 旧问题 | 判定 | 证据 |
|---|---|---|---|
| **F-01** 写操作零进度 | issue 7 类写操作点击后对话框秒关、异步期屏幕零反馈 | **已修** | `issue_page.dart:69-74` `_dialogBusy` ValueNotifier；`:187-221` `_runWrite(dialogBusy:)` 置位/复位；`:972-990` `_dialogSaveButton` 忙时按钮内 `CircularProgressIndicator(strokeWidth:2)` + `onPressed:null`，成功才 `pop(true)`、失败对话框留着可改重试（`:240-249`）。页面级写（锁定/删评/关开）在 AppBar 显示 spinner（`:768-776`） |
| **F-02** 关议题无 busy/无确认 | repo_page `_close` 全程无反馈 | **已修** | `repo_page.dart:2702-2746`：入口 `if (_busy) return` + `setState(_busy=true)` + 成功 `success(_t('issueClosed'))` + 失败 warning + finally 复位。四段齐全 |
| **F-05** 无防重入 | repo_page 设置写 6 处缺 `if(_busy)`、开关用空回调 | **已修** | `_setVisibility:3941`、`_transferRepo:3996`、`_setDefaultBranch:4065`、`_toggleArchive:4091`、`_saveCname:4137`、`_deleteRepo:4242` 全部有 `if (_busy) return`；`:4385-4395` 可见性开关改 `Opacity+AbsorbPointer`（注释明确弃「空回调假可交互」）；`:4331/4347/4363` 行 onTap `_busy ? () {}` 仍在（P2 残留，见 3-①） |
| **F-03** SnackBar 无统一三语气 | 7 份私有 _toast 各写各的 | **已修** | `notifier.dart:30-31` 枚举三语气；`:118-139` 底色/前景/图标三重映射；文件头注释记录 7 份实现已全部收编。全库 `rg showSnackBar` 仅剩 `error_surface.dart:573`（通知中心横幅，规格同款）一处旁路 |
| **F-18** 成功无确认 | _close/_cancel/_downloadLogs/_remove 等只记日志 | **部分修复** | `_close`✅（`:2735`）、`_downloadLogs`✅（`action_run_page.dart:323` success 带路径）、创建 release ✅语气修复见 F-20；❌ **`action_run_page._cancel` 成功仍只 `OgLAppLog.result`（`:188-192`），无 SnackBar**；❌ profile `_remove` 成功仍只记日志（`profile_page.dart:156-157`） |
| **F-20** 乐观更新无回滚说明 | code_editor 乐观入队后即时确认弱 | **部分修复（残留）** | `code_editor_page.dart:267` 入队有 info「已在后台提交」；失败/冲突经通知中心 warning（`:300-324`）+ 草稿保留。**但**：成功结果也只走易逝 SnackBar（`_submitInBackground` 内 notifier），未入 `OgLNoticeCenter` 持久条目——用户离开页面几秒后回来，成功与否**无持久可查处**（通知中心页只显示 OgLAppLog 条目，可翻到但非主动触达）。M-14 的「持久条目 + 待同步角标」未做 |
| **4-C C-02** 三语气只差文字色 | warning 黑底白字与 success 不可辨 | **已修** | `notifier.dart:118-139`：success=primaryContainer / info=secondaryContainer / warning=scheme.error，色相完全不同；且前置图标 check_circle/info/error_outline 形状也不同。唯一弱点：`error_surface.dart:573` 横幅**未带语气样式**（默认黑底、无图标），系统级告警与业务三语气观感割裂（P2） |

---

## 2. 回归（v15 大改是否引入新问题）

1. **三语气在暗色档可辨性**：warning 底色 = `scheme.error`（暗档约 #F2B8B5 亮红、亮档 #B3261E 深红），与 success/info 的容器色（淡蓝/淡紫灰）对比强烈——**可辨**。但 `error_surface.dart:573` 的横幅走 snackBarTheme 默认色（暗=surfaceContainerHighest、亮=inverseSurface），**无图标无语气色**，与三语气并存时像「第四种未知语气」。修复指令：`_presentAmbient` 改用 `OgLNotifier.of(context).notice(text, tone: severity==critical ? warning : info)` 收口。
2. **busy 期间对话框可被 barrier 关闭**：`ogLShowDialog` 默认 `barrierDismissible: true`（`overlays.dart:62`），issue 编辑对话框在 `_dialogBusy` 期间点遮罩/返回键仍可关——异步写会继续完成但对话框已消失，成功提示照发（`issue_page.dart:258`），闭环不丢数据但「保存中」的视觉锚点没了。属 P2 打磨：`_EditIssueDialog` 等四框应加 `PopScope(canPop: !busy)`。
3. **删发布成功靠 `pop(true)` 无 SnackBar**（`release_detail_page.dart:216-219`）——调用方（repo_page releases tab）有 refresh 但**无「已删除」确认**；删 Gist 同（`gist_detail_page.dart:270` 一带 pop）。与旧 L 系残留一致，P1。
4. **`new_*` 四页提交按钮仍只换文字无 spinner**（`new_issue_page.dart:178`、`new_gist_page.dart:149`、`new_release_page.dart:241`、`new_repo_page.dart:201`）：`onPressed: _busy?null:_submit` + 文字变「创建中…」，按钮内无 `CircularProgressIndicator`——旧 S-05 的核心（异步期进度为零）**未修**，慢网下仍是「文字按钮干等」。P1。
5. **错误 Card 仍无「重试」按钮**（`new_issue_page.dart:160-168`、`new_release_page.dart:213-221`、`new_repo_page.dart:173-181`）：`_error` 显示后用户只能退出重进（输入保留，尚可）。M-08 未修。P1。

---

## 3. 新发现（rg 全库统计 + 逐页核对）

### ① 全库写操作无 busy/防重入清单（9 处）

| # | 位置 | 操作 | 缺什么 |
|---|---|---|---|
| 1 | `profile_page.dart:136-172` `_remove` | 注销账号+清全部缓存 | 无 `_removing` 守卫，`:268/:328` 按钮异步期可重复点；成功只记日志 |
| 2 | `notifications_page.dart:139-150` `_confirmReset` | 清空通知中心 | 本地同步操作（可接受），但无「已清空 N 条」确认 |
| 3 | `notifications_page.dart:171` markAllRead | 全部已读 | 同上，同步、无确认（可接受，P2） |
| 4 | `drafts_page.dart:100-114` `_delete` | 删草稿 | 无 busy；`discardDraft` 为本地 API 快但无防重入；成功有 info✅ |
| 5 | `gists_page.dart:110-120` / `dashboard_page.dart:336-` `_create*` | 跳转创建页入口 | 本身无写；**子页有 _busy**——不构成缺陷（已核，仅列查证） |
| 6 | `settings_page.dart:727-760` `_applyUiFont`/`_downloadNotoSerif` | 字体下载 I/O（可达数十秒） | **无 busy、无取消、无进度**——只有一条 info「加载中」SnackBar（4s 即逝），下载期间设置行仍可点，可重复触发并发下载。P1 |
| 7 | `repo_page.dart:3211-3220`（建分支）/`:3252-3260`（重命名）/`:3292-3305`（删分支）/`:4268-4284`（删仓库回调 tab） | 分支增删改 | **无 `_busy` 守卫**，await 期间可重复点；成功无 SnackBar 仅记日志。P1 |
| 8 | `issue_page.dart:380-400`（锁定/解锁）、`:543-565`（关/开议题） | 确认对话框型写 | 有页面 `_busy`+AppBar spinner✅；但**确认对话框期间**（`ogLShowDialog` 默认 barrier 可关）双击确认钮会 pop 两次返回——低危 P2 |
| 9 | `error_surface.dart:573` `_presentAmbient` | 通知中心横幅 | 无防重入竞态问题（`_showing` 已守），仅样式未收口三语气（P2） |

**仍无 busy 的真实写操作处数：6 处**（#1、#4、#6、#7 四小处、加上 new_* 四页的「有 busy 无 spinner」半残 4 处单列）。

### ② SnackBar 三语气语义混用统计（逐点核对 200+ 调用点）

**混用 2 组、共 6 个调用点**：
- **成功误用 warning**：`repo_page.dart:3046`（创建 release「已创建发布」红底⚠）、旧 M-08 记录过、**未修**；
- **成功误用 info**（低配，语气弱化不算错但「操作已生效」应 success）：`issue_page.dart:258/316/360/412/496/535/626`（编辑/标签/指派/锁定/编评/删评/发评全部 info）、`repo_page.dart:2696`（已创建议题）、`drafts_page.dart:111`（已删除草稿——删除成功更该用 success 且给 Undo）、`gists_page.dart:117`（已创建）。**批量偏弱但语义不反**——按 P2 打磨；
- **拦截误用 info**：`issue_page.dart:238/471/593`（标题/评论为空 → info，应为 warning「被拦下」）；`new_gist_page.dart:89/93` 同。
- **分支增删改成功无提示**（`repo_page.dart:3211/3252/3292`）不算混用，算缺失（归 P1）。

### ③ 失败提示的「重试/撤销」出口：**全库 0 处**

`OgLNotifier.notice` 已支持 `actionLabel/onAction`（`notifier.dart:89-95`）且下载页用它做「查看下载」跳转（`download_manager_page.dart:107`）——基建**已具备**，但：
- **没有任何写操作失败传 retry 回调**（issue 写、文件写、分支写、release 删、设置写全部 `warning(msg)` 裸调）；
- **没有任何删除传 Undo**（`rg onUndo` 全库 0 命中）；唯一接近的是草稿删除（`drafts_page.dart:111`）与评论删除（`issue_page.dart:535`）——本地/远端删后直接 info 收尾。
- 旧 S-04 判「部分修复」：时长修复✅（4s/8s 常量）、action 通道修复✅（参数存在）、**业务接线 0%**。

### ④ 长任务进度可见性

| 任务 | 进度 | 判定 |
|---|---|---|
| 批量删目录（`repo_page.dart:1727-1754`） | `_operationStatus` 状态行 + onProgress 回调（`:1021-1040`） | ✅ 全库最佳 |
| 单文件建/删/改名（`:1550/:1628/:1827`） | `setState(_busy)` 但**不设 `_operationStatus`** → `:2450` 走全屏 `Center(CircularProgressIndicator)`，列表整页消失 | ❌ 旧 S-06 未修；commit 提交通常 1–3s，全屏转圈 + 列表闪变，「不知道自己在哪」 |
| code_editor 后台提交 | 入队 info + 结果经通知 | ⚠️ 不可见进度但有排队提示，可接受 |
| 字体下载（settings） | 仅 4s 即逝 info | ❌ 数十秒任务无进度无取消 |
| GitHub API 写（issue/repo 设置） | 页面 spinner（issue AppBar `:768`）或无（repo 设置 tab） | ⚠️ repo 设置 tab busy 时只有 AbsorbPointer 变暗（`:4391`），无 spinner |

### ⑤ 删除类二次确认 + 危险色核对

| 删除操作 | 二次确认 | 危险色 | Undo |
|---|---|---|---|
| 删仓库 `repo_page.dart:4246-4262` | ✅ ogLShowDialog | ✅ error 按钮 | ❌ |
| 删议题评论 `issue_page.dart:509` | ✅ ogLDangerConfirm | ✅ | ❌ |
| 删文件/目录 `repo_page.dart:1615/:1668` | ✅（ogLDangerConfirm 路径） | ✅ | ❌ |
| 删分支 `repo_page.dart:3285` | ✅ + error 色 | ✅ | ❌ |
| 删发布 `release_detail_page.dart:190` | ✅ + error 色 | ✅ | ❌ |
| 删 Gist `gist_detail_page.dart` | ✅（ogLDangerConfirm） | ✅ | ❌ |
| 删 tag `repo_tags_page.dart:133` | ✅（可经设置关闭确认） | ✅ | ❌ |
| 删草稿 `drafts_page.dart:93` | ✅ ogLDangerConfirm | ✅ | ❌ |
| 注销账号 `profile_page.dart:139` | ✅ ogLDangerConfirm（含后果说明） | ✅ | ❌ |
| 清空通知 `notifications_page.dart:141` | ✅ ogLDangerConfirm | ✅ | ❌ |
| 关闭议题 `repo_page.dart:2708` / `issue_page.dart:548` | ✅ 普通 Confirm（非 danger——关议题可重开，合理） | — | — |
| 锁定讨论 `issue_page.dart:380` | ✅ 普通 Confirm（可解锁，合理） | — | — |

**结论：二次确认 + 危险色全库达标（12/12 可确认项）；Undo 全库 0 处**（rules/04 §6「undo>confirm」原则未落地，属策略选择而非缺陷，记 P2 建议）。

---

## 4. P0 / P1 / P2 分级汇总

**P0（无）**——旧 7 条严重项的核心（零进度、零确认、可并发提交）在 v15 均已修复；本轮未发现「完全无法使用/数据丢失」级新问题。

**P1（6 条）**
1. **失败提示零重试出口**（全库性）：`OgLNotifier.warning` 调用点无一处传 `actionLabel:重试`。修复指令：在 `issue_page._runWrite` catch（`:206-214`）、`repo_page._close` catch（`:2738-2741`）、各 `saveFailed` 处传 `actionLabel: OgLI18n.t('common','retry'), onAction: 重新发起同一写`；基建已在 `notifier.dart:89-95`，纯接线。
2. **创建 release 成功仍红底 warning**：`repo_page.dart:3046` `.warning(_t('releaseCreated'...))` → `.success(...)`（一行改动）。
3. **分支增删改成功无提示 + 无 busy**：`repo_page.dart:3211-3220/3252-3260/3292-3305` 补 `success(_t('branchCreated'/'branchRenamed'/'branchDeleted'))` + `if (_busy) return` 守卫。
4. **new_* 四页提交按钮无 spinner**：`new_issue_page.dart:178`、`new_gist_page.dart:149`、`new_release_page.dart:241`、`new_repo_page.dart:201` 的 child 改 `_busy ? Row([CircularProgressIndicator(strokeWidth:2), Text(creating)]) : Text(submit)`（模板：`issue_page.dart:977-987`）。
5. **action_run 取消运行成功无确认**：`action_run_page.dart:188-192` 补 `OgLNotifier.of(context).info(_t('cancelRequested'))`（旧 S-07 残留）。
6. **字体下载无进度无防重**：`settings_page.dart:727-760` 加页面级 `_fontBusy` 守卫 + 状态行（下载属长 I/O，至少「下载中…」常驻而非 4s 即逝）。
7. **注销账号无 busy + 成功无确认**：`profile_page.dart:136-172` 加 `_removing` 守卫 + 成功 `_notifier.success(_t('removed'))`（旧 M-10 残留）。

**P2（6 条）**
1. issue 编辑/标签/指派/编评成功语气 info→success（7 处，`issue_page.dart:258/316/360/412/496/535/626`）；空校验 info→warning（`:238/471/593`）。
2. `error_surface.dart:573` 横幅收口到 `OgLNotifier.notice`（带语气色+图标）。
3. busy 对话框加 `PopScope(canPop: !busy)` 防中途关（`overlays.dart:62` 默认 barrierDismissible 波及 issue 四对话框）。
4. 单文件写设 `_operationStatus` 走状态行路径，避免 `repo_page.dart:2450` 全屏转圈闪变（旧 S-06）。
5. 删草稿/删评论给 Undo（`drafts_page.dart:111`、`issue_page.dart:535`）——rules/04 §6 undo>confirm 落地首站。
6. `repo_page.dart:4331/4347/4363` 行级 `onTap: _busy ? () {}` 空回调残留（同 tab 内其他控件已用 AbsorbPointer，统一）。

---

## 5. 本席对三问的回答

**问 1（闭环核对）**：7 条旧确证——F-01/F-02/F-03/F-05 已修（修法质量高，`_dialogBusy` + `_dialogSaveButton` 是范本）；4-C C-02 已修（三重区分）；F-18 部分修复（_close/_downloadLogs ✅，_cancel/_remove ❌）；F-20 部分修复（入队提示✅，持久条目/角标未做）。

**问 2（回归）**：三语气三重区分成立、明暗档均可辨；写操作闭环从「点击→busy→确认→失败」主干完整。新引入问题 2 个：①通知中心横幅（error_surface）未接入三语气样式，成为「第四种语气」；②busy 对话框可被 barrier 点击关闭，「保存中」锚点可丢。无「点了没反应」残留（除 repo 设置 tab 无 spinner 半残）；「成功没提示」残留 5 处（分支增删改、取消运行、注销账号、删发布、清通知）；「失败无重试」**全库残留**。

**问 3（新发现）**：无 busy 写操作 6 处（profile#1、drafts#4、settings 字体#6、repo 分支 4 处#7）；三语气混用 6 个调用点（1 处成功用 warning、9 处成功用 info 偏弱、3 处拦截用 info）；删除确认+危险色 12/12 达标但 Undo 0 处；长任务进度仅批量删目录达标，单文件写仍全屏转圈。

**满意度判词**：v15 后每次操作**都**知道发生了什么（主干闭环成立）；失败能知道**原因**（warning 带原始 error），但**不知道怎么补救**——没有重试按钮，只能重新走完整流程；可撤销的删除没有撤销，只能靠确认框兜底。「工具的稳定感」已从 v14 的「漂浮」进步到「可信赖但不可挽回」——最后一步（retry/undo 接线）成本极低（基建全在），是让用户满意的最短路径。

---

## 6. 已检查清单

**反馈基建**
- [x] `notifier.dart` 全文 160 行：三语气映射、action 参数、时长常量、messenger 卸载留痕
- [x] `error_surface.dart` 全文 626 行：OgLNoticeCenter 队列/去重/落盘、NoticeHost drain/前后台/critical 弹窗、`_presentAmbient` 样式缺口
- [x] `overlays.dart`：ogLConfirm/ogLDangerConfirm danger 配色、ogLShowDialog barrierDismissible 默认值
- [x] `theme.dart:284-304` snackBarTheme（floating/shape/明暗底色/对比度注释）
- [x] `async.dart` 错误态 emptyAction 重试按钮（`:336/:631`）

**写操作逐页（24 页有写操作全覆盖）**
- [x] issue_page 1193 行：7 类写 + 发评（`_dialogBusy`/`_busy`/`_posting` 三层守卫、AppBar spinner、语气逐点）
- [x] repo_page 4612 行写段：star/fork/文件建删改名/批量删目录/关议题/分支增删改/基本信息/可见性/转移/默认分支/归档/CNAME/Pages 开关/删仓库/创建议题与 release 入口（逐 handler 核 `if(_busy)`+成功语气+危险确认）
- [x] new_issue/new_gist/new_release/new_repo 四提交页：busy 有、spinner 无、错误卡无重试
- [x] gist_detail / release_detail / repo_tags / workflow_dispatch / action_run（rerun✅ cancel❌确认 downloadLogs✅）/ code_editor（乐观链）/ drafts / profile / notifications / settings / dashboard / gists / login / about / search / commit / pull / file_preview / onboarding / legal_text（后五页只读已核无写）
- [x] 全库 `rg api.(create|update|delete|put|dispatch|rerun|cancel|...)(` 42 调用点 ↔ busy/确认/语气三轴核对
- [x] 全库 `rg "onUndo|onRetry|actionLabel"`：retry/undo 业务接线 0 处（下载页「查看下载」除外）
- [x] i18n 抽查 `assets/i18n/zh/{repo,issue_page}.json` 14 键语气与文案匹配

（只读审计结束 · 未修改任何产品代码 · 未 commit/push）
