# 功能审计 4-C 前半 · 页面业务逻辑 1（domain 1/2）

> 文档戳：更新时间 2026-11-23 07:07:25 (Asia/Shanghai) · 版本 v15.0.0
> 审计范围：15 页（repo_page / repo_tags_page / issue_page / new_issue_page / pull_page / commit_page / release_detail_page / new_release_page / code_editor_page / file_preview_page / gists_page / gist_detail_page / new_gist_page / search_page / dashboard_page）
> 纪律：只读审计；禁读 Flutter SDK；仅项目 lib/ 代码；每条均可 `rg` 复现。只看功能正确性，不看视觉。

## 问题汇总

| 级别 | 数量 |
| --- | --- |
| P0（数据丢失/崩溃/安全） | 0 |
| P1（功能失效/不一致） | 4 |
| P2（打磨） | 3 |

---

## P1 · 功能失效 / 不一致

### P1-1 DiscoverPage 下拉刷新在途时无声失败（列表清空后不回源）

- **证据**：`lib/surface/pages/search_page.dart:873-880`（`onRefresh` 清 `_repos`/`_repoPage=1`/`_repoDone=false`，但**未**复位 `_repoLoading`）；`lib/surface/pages/search_page.dart:470-472`（`_loadMoreRepos` 首行 `if (_repoLoading || _repoDone) { return; }`）；对照 `lib/surface/pages/search_page.dart:864`（分类切换分支明确写了 `_repoLoading = false;` 并注释「在途旧请求仍占着 _repoLoading → 新分类永远空」）。
- **症状**：推荐 tab 首屏加载尚在途（或滚动刚触发 `_onRepoScroll` → `_loadMoreRepos` 在途）时下拉刷新，列表已被清空但 `_loadMoreRepos` 被防重入闸门直接 return，页面停在「暂无推荐」直到手动切分类/重建。刷新看起来「点了没反应」。
- **根因**：分类切换路径修过同一竞态（世代++ 并解锁 `_repoLoading`），下拉刷新路径漏了同样的解锁；`_repoGeneration++` 只作废旧请求的回写，不能解除旧请求占用的 `_repoLoading` 标志。
- **修复指令**：在 `search_page.dart:873-880` 的 `onRefresh` 内、`_repoDone = false;` 之后补一行 `_repoLoading = false;`（与 `:864` 同语义），再 `await _loadMoreRepos();`。同时在的 `finally`（`:518-521`）中确认只有当前世代才复位该标志，避免旧请求 finally 覆盖新请求状态。

### P1-2 从通知流 / 发现页进入 IssuePage 只传 number，正文、标题、状态全空

- **证据**：`lib/surface/pages/search_page.dart:647`（`issue: <String, dynamic>{'number': int.tryParse(number) ?? 0}`）；`lib/surface/pages/search_page.dart:711-718`（注释称「详情由 IssuePage 自行拉取」，实际 Map 只有 number/title/html_url）；`lib/surface/pages/issue_page.dart:88-92`（`_title`/`_labels`/`_assignees` 全部 `late ... = ghXxx(widget.issue, ...)` 一次性从入参初始化）；`lib/surface/pages/issue_page.dart:64`（`late String _state = ghStr(widget.issue, 'state')`）；`rg -n 'api\.issue\(|\.issue\(' lib/surface/pages/issue_page.dart` 无结果，确认本页**没有**详情请求。
- **症状**：点通知流里的 Issue/PR 或发现页的议题行，进到详情页显示 `#N`、空标题、空正文、无标签/指派人；`_state` 默认空串导致 `open = (_state=='open')` 为 false，页面显示「已关闭」且「重开」按钮对实际 open 的议题误操作。
- **根因**：调用方注释与实现不符——IssuePage 是「列表对象直传型」页面，不自行拉详情；两个入口只给了 number，违反 domain ④ 导航参数契约。
- **修复指令**：二选一。①（推荐）在 `issue_page.dart` 的 `initState`（`:96-102`）增加 `_loadDetail()`：调 `widget.surface.domain.api.issue(widget.fullName, _number)`（若 domain 层无此端点则标「待核实，交主会话/CI 裁决」），成功后 `setState` 同步 `_title/_state/_labels/_assignees/_locked`，并让正文改读本地镜像而非 `widget.issue`；失败时给出可见重试而非空白。②让 `search_page.dart:647` 与 `:711` 在 push 前先拉详情并传完整 Map。同时把 `:711-714` 的误导注释改正。

### P1-3 ReleaseDetailPage 编辑成功不向列表页回传变更标志，发布列表陈旧

- **证据**：`lib/surface/pages/release_detail_page.dart:170`（编辑成功后仅 `setState(() => _release = updated)`，**无** `Navigator.pop(true)`）；对照同文件 `:219`（删除成功才 `Navigator.of(context).pop(true)`）；父页 `lib/surface/pages/repo_page.dart:3051-3061`（`_openDetail` 仅 `if (changed == true && mounted) await _paged.refresh();`）。
- **症状**：在发布详情页改标签/标题/说明/草稿/预发布，返回仓库 Release 列表后仍显示旧标签与旧标题；再次进入详情才可见新值。与同页删除、新建发布（`:3034-3049` pop release 后 refresh）的刷新行为不一致。
- **根因**：详情页只对「删除」回了 true，父页的刷新协议完全依赖 pop 返回值，编辑路径未接入该协议。
- **修复指令**：在 `release_detail_page.dart:170` 的 `setState` 之后（仍在 mounted 检查内）增加 `Navigator.of(context).pop(true);`。若需保留详情页停留体验，则改为维护 `bool _changed`，在编辑成功后置位、用户主动返回时 `pop(_changed)` 并在 PopScope 中处理。

### P1-4 RepoTagsPage 创建/删除成功后刷新被自身 busy 闸门吞掉

- **证据**：`lib/surface/pages/repo_tags_page.dart:54`（`_load` 首行 `if (_loading || _busy) { return; }`）；`:109-118`（`_create` 先 `setState(() => _busy = true);`，随后 `await _load(reset: true);`）；`:143-148`（`_delete` 同结构）；`:124-126`（`_busy=false` 在 `finally`，晚于 `_load` 调用）。
- **症状**：新建标签或删除标签请求成功后，列表不刷新——新标签不出现、被删标签仍在；只有手动下拉或离开重进才看到正确数据。`_busy` 是**写操作**防重入标志，被误用为**读加载**闸门。
- **根因**：`_load` 的防重入条件混用了两个不同语义的标志；写操作进行中调用 `_load` 必然立即返回。
- **修复指令**：把 `repo_tags_page.dart:54` 改为 `if (_loading) { return; }`，写操作防重入由 UI 的 `onPressed: _busy ? null : ...`（`:211`、`:277`）与 `_create`/`_delete` 入口各自保证；或给 `_load` 增加 `bool ignoreBusy` 参数，写后刷新调用 `_load(reset: true, ignoreBusy: true)`。

---

## P2 · 打磨

### P2-1 RepoPage `_fork` 成功后 notifier 未做 mounted 检查，退出后可能抛异常

- **证据**：`lib/surface/pages/repo_page.dart:379`（`await api.fork(...)` 后无条件 `_notifier.success(...)`，无 `if (mounted)`）；对照同页 `:248-250`（`_toggleStar` 有 `if (mounted)`）；`_notifier` getter 定义在 `:236`（`OgLNotifier(ScaffoldMessenger.of(context))`）。
- **症状**：fork 请求在途时用户返回上一页，请求返回后在已 dispose 的 context 上 `ScaffoldMessenger.of(context)`，debug 下抛断言 / 界面异常。catch 分支已做保护，成功分支漏做。
- **根因**：异步成功后漏 mounted 守卫——同页其他写操作均已收敛此模式。
- **修复指令**：将 `repo_page.dart:379` 改为 `if (mounted) { _notifier.success(_t('forkedAs', {'name': forked.fullName})); }`。

### P2-2 CodeEditorPage「跳转到行」对话框的 TextEditingController 未 dispose

- **证据**：`lib/surface/pages/code_editor_page.dart:427-430`（`showDialog<String>` 的 builder 内 `final TextEditingController controller = TextEditingController(text: ...)`，无 `whenComplete` 释放）；全文 `rg -n 'controller.dispose|whenComplete'` 仅命中 `:146` 的主编辑器 `_controller.dispose()`；对照 `lib/surface/pages/repo_page.dart:3885`（同类一次性对话框用 `.whenComplete(controller.dispose)`）。
- **症状**：每次使用「跳转到行」都泄漏一个 TextEditingController 及其注册监听，长期编辑大量文件会累积。属于 dispose 清理域（domain ⑥）。
- **根因**：一次性对话框控制器生命周期未挂到 future 结束点。
- **修复指令**：在 `code_editor_page.dart:427` 的 `showDialog<String>(...)` 调用末尾追加 `.whenComplete(controller.dispose)`；注意 controller 声明需移到 `showDialog` 之前以便闭包捕获，与 `repo_page.dart:3861-3885` 同构。

### P2-3 NewReleasePage / NewGistPage 的开关状态未纳入脏检查，可静默丢失

- **证据**：`lib/surface/pages/new_release_page.dart:67-70`（`_dirty` 仅比较 `_tag/_name/_body` 三个文本控制器，不含 `:56-57` 的 `_draft`/`_prerelease`）；`:151` 用 `canPop: !_dirty`；`new_gist_page.dart:51-54`（`_dirty` 不含 `:42` 的 `_public`），`:133` 为 `canPop`。
- **症状**：用户只切换「草稿 / 预发布 / 公开」开关而没改任何文字时返回，`PopScope.canPop` 仍为 true，直接放行且不弹「放弃修改」确认，设置静默丢失。Switch 的 `onChanged` 虽有 setState，但 `_dirty` getter 没有把开关纳入判据。
- **根因**：脏检查只覆盖 TextEditingController，开关类状态初始值未被记录。对照 `new_issue_page.dart:45-51` 同样只查文本（该页无开关，属正确）。
- **修复指令**：在新发布页记录 `late final bool _initialDraft = _draft;`、`_initialPrerelease` 并在 `_dirty` 中追加 `|| _draft != _initialDraft || _prerelease != _initialPrerelease`；在新 Gist 页记录 `_initialPublic` 并追加 `|| _public != _initialPublic`。注意初始值字段需在对应 bool 字段声明之后、且保持 `late final` 惰性求值到初值确定后。

---

## 已检查清单（15/15 页全覆盖）

| # | 页面 | 检查结论（每页 1–2 行） |
| --- | --- | --- |
| 1 | `repo_page.dart`（4612 行） | 逐段检查 `_RepoPageState`（star/fork/zip/branch）、`_CodeTab`（PagedController 分页、`_loadPage` per_page、草稿写后 `_reload`、`_createFile`/`_deleteEntry`/`_renameEntry` 校验与回滚、控制器 dispose）、`_IssuesTab`/`_PullsTab`/`_ReleasesTab`/`_BranchesTab`/`_CommitsTab`/`_ActionsTab`/`_RepoSettingsTab`。发现 P1-3 关联父页刷新协议、P2-1；其余写操作均 `if (_busy) return` + mounted 守卫 + finally 复位，安全。 |
| 2 | `repo_tags_page.dart` | `_load` 分页/`_more`/`_page`、create/delete、确认弹窗、controller dispose。发现 P1-4；`_CreateTagDialog` 必填校验在弹窗内完成、dispose 完整。 |
| 3 | `issue_page.dart`（1193 行） | 评论分页、6 类写操作（编辑/标签/指派/锁定/开关/评论）的 `_runWrite` 防重入、`_dialogBusy` 进度闸门、60000 字上限、权限收敛、`_comments/_comment/_dialogBusy` dispose。发现 P1-2（入参契约，非本页内部逻辑）；本页内部无缺陷。 |
| 4 | `new_issue_page.dart` | 标题必填、busy 防重入、失败保留输入、脏检查 + dispose、成功后 pop(true)。无问题。 |
| 5 | `pull_page.dart` | `AsyncController` 变更文件加载、retry/emptyAction、dispose；PR 对象由调用方全量传入，number 独立传递正确。无问题。 |
| 6 | `commit_page.dart` | 首提交空 parent 处理、`compare` 参数顺序、dispose；「网页查看」按钮 `onPressed: null` 且源码已标「待核实」，按要求不作为缺陷计入，仅记录为待主会话/CI 裁决项。 |
| 7 | `release_detail_page.dart` | 编辑/删除/下载（预签名与令牌出口门禁）/复制、脏检查。发现 P1-3；编辑校验在 dispose 控制器之后执行、逻辑正确。 |
| 8 | `new_release_page.dart` | 标签必填、默认分支→targetCommitish、busy、dispose、pop(release)。发现 P2-3。 |
| 9 | `code_editor_page.dart` | 草稿防抖落盘、`_restoreDraft` 世代保护、`initialTextIsRemote` 防误清草稿、`_submitInBackground` 乐观提交与冲突处理、PopScope 放弃逻辑、Timer/controller dispose。发现 P2-2；核心写链路无问题。 |
| 10 | `file_preview_page.dart` | `_load` 错误复位与重试、>1MB 双路径、私有仓库 raw 认证头与令牌出口门禁、文本解码缓存、无 controller 泄漏。无问题。 |
| 11 | `gists_page.dart` | `gists()` 列表、详情/新建返回后 `load()` 刷新、id/html_url 空值兜底、下拉刷新、dispose。无问题。 |
| 12 | `gist_detail_page.dart` | `truncated` raw 回退与如实降级、编辑后 `_detailC().load()`、删除 pop(true)、下载加速范围、dispose 后不重建控制器。无问题。 |
| 13 | `new_gist_page.dart` | 文件名/内容必填、busy 放校验后、失败保留输入、finally 复位、dispose。发现 P2-3。 |
| 14 | `search_page.dart`（1435 行） | `DiscoverPage` 三 tab：`_feed`、分页 `_loadMoreRepos` 世代/防重入、`_loadIssues` 聚合去重；`SearchResultsPage` 300ms debounce、模式切换重建 AsyncController 并 dispose 旧实例。发现 P1-1、P1-2；其余正确。 |
| 15 | `dashboard_page.dart` | `_RepoPaged` 分页（generation/refreshQueued/dispose）、分段切换、空态刷新、下拉刷新、预加载幂等键、controller 与 listener dispose。无问题。 |

## 本席结论

本半区 15 页全部检查完毕，共 7 条问题：P0 0 条、P1 4 条、P2 3 条。最严重的三类问题分别是：① 推荐 tab 下拉刷新与分类切换不同步解锁 `_repoLoading`，刷新被吞（P1-1）；② 通知流/发现页到 IssuePage 的导航参数不完整且页面不自行拉详情，导致议题内容空白、状态误判（P1-2）；③ 两处「写后刷新」链路断裂——发布编辑不回传变更标志（P1-3）、标签页写操作把 busy 标志误作加载闸门（P1-4）。

值得肯定的是，这批页面在异步防重入、dispose 清理、错误态与令牌出口门禁上整体已形成统一模式（PagedController / AsyncController / `_runWrite` / `ogLGuardTokenExitDownload`），问题集中在少数「复制既有模式时漏改一行」的路径。建议修复优先级：先 P1-1 / P1-4（改动各 1 行即可恢复核心功能），再 P1-2（需确认 domain 层详情端点是否存在，缺失则标待核实交主会话裁决），最后 P1-3 与 3 条 P2。

**待核实事项（不越权裁决）**：`commit_page.dart:166` 的「网页查看」按钮与 `issue_page.dart:854`、`search_page.dart:1399` 的 CTA 均因无路由调用而 `onPressed: null`，源码已明确标注「待主会话/CI 裁决」，本席按纪律未将其计为功能缺陷。
