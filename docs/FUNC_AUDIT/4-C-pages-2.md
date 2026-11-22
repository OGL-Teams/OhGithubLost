# 功能审计 4-C 后半 · 页面业务逻辑 2/2

文档戳：2026-11-23 00:00:00 (Asia/Shanghai) · v15.0.0
范围：notifications / profile / about / settings(+section) / legal_text / onboarding / login / download_manager / workflow_dispatch / action_log / action_run / drafts / gists（共 13+1 页；"shell 状态衔接"归 4-A，本席仅核对页面侧接线）。
纪律：只读；每条 file:line 可 rg 复现。

## 问题清单

### P1（功能失效/不一致）

1. **action_log_page：job 结论表从未加载，状态点永远是"未知灰"**
   - 症状：日志页每个 job 的结论点全部是灰色（未知），即使 job 明明 success/failure；"失败置顶+默认展开"也因此永不触发。
   - 根因：`_jobsC()` 只在 build 里读 `_jobsC().data`（action_log_page.dart:386），全文件没有任何 `loadIfNeeded()/load()` 调用（initState 只 load 了 _logs，action_log_page.dart:107）。控制器创建后 loader 永不执行。
   - 修复指令：在 `_ActionLogPageState.initState`（action_log_page.dart:106 附近）补 `_jobsC().loadIfNeeded();`，并在 dispose 释放 `_jobs`（当前 dispose 只释放 `_logs`，action_log_page.dart:117-122 —— 顺带修 `_jobs` 泄漏）。

2. **action_log_page：查找"上一处/循环跳转"跳错位置**
   - 症状：点"上一处"实际滚向"下一处"；到达末尾再点"下一处"（回绕到第 1 处）时不滚动或滚错。
   - 根因：页面用单调自增的 `_jumpToken++`（action_log_page.dart:214、231），而 `OgLLogBody._jump` 把 `jumpToken` 解释为**命中绝对序号** `widget.jumpToken - 1`（log_body.dart:127）。倒退时序号该减，回绕时该回 1，token 却一直加。跨 job 时页面序号是全局的、LogBody 的 `_hits` 是单 job 局部的，序号也对不上。
   - 修复指令：把跳转改为传"目标命中序号"而非自增计数：`_jumpTo` 里 `_jumpToken = <全局当前命中序号>`（同时给 OgLLogBody 传入它负责的 job 的**局部序号**，或在 LogBody 内把全局序号折算到本组），并保持"同序号不重复跳"用单独的自增 nonce。

3. **workflow_dispatch_page：脏检查漏掉 choice/boolean 表单，静默丢输入**
   - 症状：改了下拉(choice)或开关(boolean)参数后按返回键，弹窗不出现，输入直接被丢弃。
   - 根因：`_dirty` 只比对 `_ref`、`_inputs`、`_formText`（workflow_dispatch_page.dart:394-404），`_formChoice`/`_formBool` 完全没参与。
   - 修复指令：`_dirty` 增加：任一 `_formChoice[input.name] != (input.defaultValue ?? (options 首项/''))` 或 `_formBool[input.name] != (input.defaultValue == 'true')` 即返回 true。

4. **gists_page：列表只取第一页（per_page=30），无 LoadMore**
   - 症状：Gist 超过 30 个时，第 31 个起在应用内永远看不到（GitHub API 默认/指定 per_page=30，gh_api.dart:1870-1875；页面无分页状态）。
   - 根因：`_gistsC` loader 一次性 `gists()`（gists_page.dart:57-59），无 page 参数、无滚动加载。
   - 修复指令：`GhApi.gists` 增加页码参数并用 Link header 判断 has_next（与其它列表一致），页面加滚动触底加载与"加载中/没有更多"行；或至少 per_page 拉满 100 并提示截断。

### P2（打磨）

5. **action_log_page：命中计数显示 off-by-one**：`current: _search.total > 0 ? _searchIndex + 1 : 0`（action_log_page.dart:346），而 `_searchIndex` 已是 1 起（action_log_page.dart:211）→ 首个命中显示 "2/N"。修复：直接传 `_searchIndex`。
6. **drafts_page：删除/打开草稿异常外泄**：`_delete`（drafts_page.dart:117-124）与 `_openInEditor` 的 `loadDraftRecord`（drafts_page.dart:130-133）无 try/catch，`unawaited` 调用链上抛成未捕获异步异常，用户无任何提示、列表不刷新。修复：包 try/catch → `OgLNotifier.warning` + 日志。
7. **drafts_page：空态 CTA 是死按钮**：`onPressed: null`（drafts_page.dart:165）配"去新建"文案。修复：接真实新建路径（对 repo 文件编辑入口），或换用无动作文案。
8. **login_page：验证晚段失败留下半成品账号**：`_finishLogin` 在 `saveAccount('user-<id>')` 之后失败（如保险库回读失败，login_page.dart:264-271），回滚只删 `pendingId`（login_page.dart:277-283），已转正的 `user-<id>` 残留在账号列表。修复：回滚时同时 `removeAccount('user-${me.id}')`（若本次新建）。
9. **login_page：页面关闭后 OAuth 结果被丢弃**：Device Flow 轮询完成后 `if (!mounted) return;`（login_page.dart:196-198）直接丢弃已取得的令牌，用户在浏览器已授权但应用无账号。修复：即使未 mounted 也走 `auth.saveAccount+switchTo`（不带 UI），或弹全局通知。
10. **settings_page：自定义 DNS 保存无校验反馈**：`_editCustomDns` 保存后无条件提示成功（settings_page.dart:1230-1236）；非法 IP/非 https DoH 由 net 层拒收（net_bridge.dart:93-104）但 UI 仍报"已保存"。修复：保存前本地校验 `ogLNormalizeDnsAddress` / `ogLIsUsableDohEndpoint`，失败 warning 不落盘。
11. **settings_page：`_addFontFromUrl` TextEditingController 未 dispose**（settings_page.dart:829-833 创建、855-870 只 pop 不 dispose）。修复：dialog 返回后 dispose。
12. **about_page：launchUrl 返回 false 时兜底失效**：`_openUrl`/`_openSponsor` 只在**抛异常**时复制链接兜底（about_page.dart:53-73、77-92），而 url_launcher 未命中处理器通常返回 `false` 不抛 → 用户点了没反应也没有复制。修复：`final ok = await launchUrl(...); if (!ok) {…兜底…}`（待核实：交主会话/CI 裁决 url_launcher 版本语义）。
13. **workflow_dispatch_page：改 ref 后表单不重载**：`_loadForm` 用当时 `_ref.text` 拉取（workflow_dispatch_page.dart:225-229），之后改分支输入框，参数表单仍是旧分支的声明；提交时也按旧声明校验。修复：`_ref` 提交/失焦时若 `_selectedPath != null` 重新 `_loadForm`。
14. **download_manager_page：`_undoRemove` 无异常保护**：`restoreDownload` 抛错时（download_manager_page.dart:355-364）未捕获，撤销条已消失、无提示。修复：try/catch + warning + 恢复 `_lastRemoved`。
15. **action_run_page：runId 无防御**：`runId = ghInt(run,'id')`（action_run_page.dart:68-69），异常数据为 0 时直接打 `/runs/0`。修复：runId<=0 时进错误态。
16. **settings_page：删除正在使用的自定义字体无确认/回退**：`_manageCustomFonts` 删除分支（settings_page.dart:793-800）不检查 `value.uiFontId == id`。修复：删除当前字体时提示并回退系统字体。

## 已检查清单

- notifications_page.dart（428 行，全量）：过滤段/展开去重/全部已读/重置确认/copy 兜底/preload 登记 —— 无功能性问题。
- profile_page.dart（352 行）：切换/移除/登录回跳/缓存清理/草稿角标监听与 dispose —— 逻辑闭环，无问题。
- about_page.dart（474 行）：外链/复制兜底/诊断折叠/权限自检/致谢分组 —— 问题 12。
- settings_page.dart（2373 行）：账户行 Future、重置、语言、字体（本地/URL/删除）、DNS（含写入顺序）、存储弹窗（SAF/所有文件）、下载并发、加速总开关/协议/私有警告 3 秒闸/通道增删校验、许可全文、日志分组 —— 问题 10、11、16。
- settings_section_page.dart（42 行）：纯容器透传 —— 无问题。
- legal_text_page.dart（199 行）：语言切换代次守卫、过期响应丢弃、错误重试 —— 无问题。
- onboarding_page.dart（517 行）：权限探测/请求/说明弹窗/设置跳转/完成标志（review 不写）/下一步禁用条件 —— 无功能性问题。
- login_page.dart（536 行）：PAT 校验/防重入（按钮+回车）/四步链/回滚/OAuth Web→Device 回落 —— 问题 8、9。
- download_manager_page.dart（618 行）：提示总线幂等/根导航跳转降级/重试全部/撤销移除/进度锚定/打开本地兜底 —— 问题 14。
- workflow_dispatch_page.dart（610 行）：YAML 解析（on:true 兼容）/表单代次守卫/必选校验/手动 inputs 解析/PopScope 脏检查 —— 问题 3、13。
- action_log_page.dart（568 行）：日志拉取/查找扫描防抖/复制/落盘 —— 问题 1、2、5。
- action_run_page.dart（790 行）：详情聚合/重跑/取消/重跑失败 job/日志下载/产物下载（TOKEN-EXIT 守卫）/job 排序 —— 问题 15。
- drafts_page.dart（247 行）：订阅刷新/删除确认/带 baseSha 进编辑器 —— 问题 6、7。
- gists_page.dart（194 行）：id/url 缺失处理/详情返回刷新/新建刷新 —— 问题 4。
- 交叉核对：gh_api.dart（workflows/dispatch/workflowRun/artifacts/rawFileText/gists/discardDraft）、surface_bridge.dart（DNS/下载/加速）、net_bridge.dart（自定义 DNS 拒收）、async.dart（AsyncController 并发抑制）、log_body.dart（分块/查找/jump）。

## 本席结论

13 页整体质量较高：防重入、代次守卫、异常兜底普遍到位，未发现 P0（无数据丢失/崩溃/安全项）。P1 共 4 条，集中在两处：action_log 的结论数据链路断线（jobs 从未加载）+ 查找跳转语义错位；workflow_dispatch 的脏检查覆盖不全导致静默丢输入；gists 列表无分页属功能缺口。建议优先修 1/2/3（都是小改动、用户可直接感知）。
