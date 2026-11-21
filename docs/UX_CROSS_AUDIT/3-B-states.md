# 批 3 · 控件与状态 · B 席 —— 状态完整性审计（loading / empty / error / disabled）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 3 · 控件与状态 · B（状态完整性）**
> - 审计对象：`lib/surface/pages/` **全部 30 页**（`rg -l "Scaffold" lib/surface/pages/` = 30）+ 统一异步出口 `lib/surface/app/async.dart` + `lib/surface/app/paged_controller.dart`
> - 仓库：`/root/OhGithubLost`，HEAD = `f684160`；**只读审计，未改任何代码，未 commit / push**
> - 日期：2026-11-22　语言：zh-Hans
> - 参照规范：`material-3/SKILL.md`（Components 节：状态容器 / 进度指示器 / 空态）、`sota-frontend-design/rules/04-ux-patterns.md`（§4 Loading、§5 Empty/error/zero states、§2 禁用按钮禁忌）
> - 用户原始判词：**「空、漂浮感、没有作为工具的稳定感」** → 本席把「空」落到三处：**空态只占一行字没有下一步**、**加载态是裸转圈占满屏（空白屏）**、**错误态没有重试或把失败说成「没有内容」**
> - 复现：所有结论均给 `file:line`，可 `rg -n '<pattern>' <file>` 复现
>
> **与 1-C 的分工**：1-C 已报「空态半屏 `SizedBox` 占位」；本席**逐页复核**该现象（结论见 §3 逐页表 `empty` 列），并把重点放在**加载态是裸转圈还是骨架**、**错误态有无重试**、**空态有没有下一步动作**三件事上。

---

## 0. 量化方法与基线

**统一出口**：`lib/surface/app/async.dart` 提供三件套——`AsyncController<T>`（状态机）/ `AsyncView<T>`（盒子态）/ `OgLAsyncSliver<T>`（sliver 态）+ 两个视觉件 `OgLAsyncErrorPane`（错误 + 重试按钮）、`OgLAsyncEmptyPane`（图标 + 一行字 + 可选动作）。

**基线指标（逐页实测）**：

| 指标 | 实测 | 期望（rules/04） |
|---|---|---|
| 30 页中接入统一出口（AsyncView / OgLAsyncSliver）的页数 | **13** | 全部有异步的页 |
| 自己手写三态的页数 | **9**（dashboard / repo_tags / search 部分 / legal_text / file_preview / onboarding / repo_page 部分 / notifications 部分 / download_manager 部分） | 0 |
| 有「加载中」态的页 | 21 | — |
| 其中**用裸 `CircularProgressIndicator` 占满屏**的页 | **16** | 0（0.3–2s 应骨架屏） |
| 有**骨架屏**的页 | **1**（`search_page.dart:134` `_SkeletonList`，且只用于推荐 tab） | 全部列表页 |
| 空态**只有一行字 + 一枚图标、没有任何下一步动作**的页 | **14** | 0（rules/04 §5：空态必须有 primary action） |
| 空态**有下一步动作按钮**的页 | **4**（dashboard / repo_page 的 issues·releases·branches·dirs） | — |
| 错误态**有重试入口**的页 | **17** | — |
| 错误态**把失败渲染成「没有内容」**（error→empty 混淆）的页 | **3**（legal_text / onboarding / file_preview 空字节） | 0 |
| 错误文案**直接抛原始异常**（`'${e}'`）给用户看的页 | **4**（paged_controller / dashboard / file_preview / login OAuth） | 0（应走 `_describe` 分类） |
| 加载指示器**无 300ms 延迟、无最小显示时长**的页 | 全部 21 页 | 应有 |

**统一出口自身的缺口**（导致页面想统一也统一不了）：
- `OgLAsyncSliver` **没有 `emptyAction` 参数**（`async.dart:485-497`）→ sliver 形态的空态**在架构上不可能带 CTA**。而 issue 评论、commit 文件、pull 文件三个高频空态恰好都用 sliver。
- `AsyncView` 的加载态（`async.dart:293-300`）与 `OgLAsyncSliver` 的加载态（`async.dart:552-560`）都是**裸 `Center(CircularProgressIndicator)`**，统一地「空白」，但统一地错。

---

## 1. 用户可感知问题（严重 / 中 / 轻）

### 严重

**S-01 · 全库唯一的加载态出口是「空白屏 + 一个裸转圈」，16 个页共用**
- 证据：`lib/surface/app/async.dart:293-300`（`AsyncView` loading = `Center(Padding(xxl, CircularProgressIndicator()))`）；`lib/surface/app/async.dart:552-560`（`OgLAsyncSliver` 同款）
- 感受：点进任何列表，屏幕先变成**一大片纯白 + 一个 4dp 的小圈**，看不到任何内容的影子。用户说的「空」在这里最直接：不是内容少，是**等待时整个界面什么都没了**。rules/04 §4 明确：0.3–2s 的等待应当用**匹配最终布局的骨架屏**，避免内容到达时的跳变；现在的实现是典型的 CLS 来源。
- 修复指令：
  1. 在 `lib/surface/app/async.dart` 新增 `OgLAsyncSkeleton`（`itemCount` + `itemBuilder` 两参，仿 `search_page.dart:134-147` 的 `_SkeletonList` 但提到公共层），并在 `AsyncView` 增加 `skeleton` 参数；`AsyncView` loading 分支改为「先渲染骨架，若 `loader` 超过 300ms 再转圈」的二段式。
  2. 提示词建议：把 `search_page.dart:134-147` 的 `_SkeletonList` 直接抽到 `lib/surface/widgets/` 并改名为 `OgLAsyncSkeleton`，`search_page` 改为引用，避免两份实现。
  3. 骨架块颜色用 `colorScheme.surfaceContainerHighest`，圆角用 `OgLRadius`，行高对齐真实列表行（56/72dp），使到达时零位移。

**S-02 · 「加载失败」被渲染成「你还没有内容」——用户被告知错误的事**
- 证据：`lib/surface/pages/legal_text_page.dart:72-80`（catch 里 `body = ''` → 随后 `:164-172` 走 `_body!.isEmpty` 分支 → 显示「法律文本为空」）；`lib/surface/pages/onboarding_page.dart:99-108`（权限列表拉取失败 → `_infos = const []` → 渲染一张空白权限列表，无错误、无重试）
- 感受：加载失败的用户被告知「这里本来就没有东西」，于是不再重试、以为是账号问题。rules/04 §5 明确：**Error-empty 必须与 genuinely empty 区分**，否则主动误导。
- 修复指令：
  1. `legal_text_page.dart`：新增 `String? _error` 字段；catch 中置 `_error = _t('loadFailed')` 而非 `body=''`；`_buildBody` 改为「`_error != null` → `OgLAsyncErrorPane(message: _error, onRetry: () => _load(_locale))`」，且 `OgLAsyncErrorPane` 已在 `lib/surface/app/async.dart:343` 可直接用。
  2. `onboarding_page.dart`：新增 `_loadError`；失败时置位并渲染 `OgLAsyncErrorPane(message: _loadError, onRetry: _load)`，不要把 `_infos` 置空当作「无权限」。

**S-03 · 空态没有下一步动作按钮（14 页），页面在「空」这里彻底停住**
- 证据：`lib/surface/app/async.dart:403-413`（`OgLAsyncEmptyPane` 默认只有 `Icon(40dp) + 一行 Text`，`action` 缺省 null）；实际调用点几乎都不传 action：`gists_page.dart:144-145`、`drafts_page.dart:214-215`、`profile_page.dart:231-232`、`workflow_dispatch_page.dart:423-424`、`action_run_page.dart:564-565`、`gist_detail_page.dart:366-367`、`notifications_page.dart:219-226`、`action_log_page.dart:363-364` 与 `:371-376`、`issue_page.dart:796-798`、`commit_page.dart:156-159`、`pull_page.dart:169-171`、`search_page.dart:776-777` 与 `:1027-1028`
- 感受：屏幕正中一枚灰图标 + 一行「还没有草稿」，**下面什么都没有**。用户要新建草稿，得先知道这页顶部有个什么按钮；这正是「没有作为工具的稳定感」——工具在空的时候不教你怎么用。
- 修复指令（逐页给出 CTA，样式统一用 `FilledButton.tonal`，M3 语义）：
  | 页 | file:line | 应加动作 |
  |---|---|---|
  | drafts | `drafts_page.dart:214-215` | `FilledButton.tonal(onPressed: _openDrafts, child: Text(_t('newDraft')))` |
  | gists | `gists_page.dart:144-145` | `FilledButton.tonal(onPressed: _create, child: Text(_t('new')))`（页面已有 FAB，需同时保留） |
  | profile | `profile_page.dart:231-232` | `FilledButton.tonal(onPressed: _addAccount, child: Text(_t('addAccount')))` |
  | workflow_dispatch | `workflow_dispatch_page.dart:423-424` | `FilledButton.tonal(onPressed: _reload, child: Text(_t('retry')))` |
  | action_log | `action_log_page.dart:363-364` / `:371-376` | 首次空 → `FilledButton.tonal(_reload)`；筛选空 → `TextButton(_clearFilter)` |
  | notifications | `notifications_page.dart:219-226` | `FilledButton.tonal(_clearFilter)` |
  | issue 评论 | `issue_page.dart:796-798` | 需先给 `OgLAsyncSliver` 加 `emptyAction` 参数（见 S-04），再传 `FilledButton.tonal(_focusCommentBox)` |
  | commit / pull | `commit_page.dart:156-159`、`pull_page.dart:169-171` | 属「真的没有变更」，加 `TextButton(_copyDiffUrl)` 之类次级动作即可 |
  | gist_detail | `gist_detail_page.dart:366-367` | `FilledButton.tonal(_createFile)` |

**S-04 · `OgLAsyncSliver` 缺 `emptyAction` 参数 → 三个高频 sliver 空态架构上无法带动作**
- 证据：`lib/surface/app/async.dart:485-497`（构造参数只有 `controller/itemCountOf/itemBuilder/emptyIcon/emptyText/padding`），使用方 `issue_page.dart:793-798`、`commit_page.dart:153-160`、`pull_page.dart:159-171`
- 感受：issue 详情页「还没有评论」是**最需要引导**的位置（用户刚提 issue 就等着看），却只能显示一行字。
- 修复指令：`async.dart` 的 `OgLAsyncSliver` 增加 `this.emptyAction`（`Widget?`），并在 `:538-546` 的 empty 分支传给 `OgLAsyncEmptyPane(action: emptyAction)`；三个使用方补 CTA。

### 中

**S-05 · `repo_tags_page` 完全手写三态，视觉与文案都和全库不一致**
- 证据：`lib/surface/pages/repo_tags_page.dart:191-208`（错误态是**裸 Text + FilledButton**，无错误图标、无 `errorContainer` 底色，与 `async.dart:343` 的 `OgLAsyncErrorPane` 不一致）；`:210-212`（加载 = 裸 `Center(CircularProgressIndicator())`）；`:213-219`（空态 = **只有一行 Text**，无图标、无按钮）；`:236`（列表尾也是裸转圈）
- 感受：标签页的失败提示像一张白纸上的黑字，跟别处红色的错误面板完全不是一套语言；空标签时只有一个孤零零的句子。
- 修复指令：把 `_buildBody`（`repo_tags_page.dart:190-219`）改为直接用 `OgLAsyncErrorPane(message: _error!, onRetry: () => _load(reset: true))`、`OgLAsyncEmptyPane(icon: Icons.label_outline, text: _t('empty'), action: FilledButton.tonal(_create))`，加载态用 S-01 的骨架。删除本地 `_error`/`_loading` 双变量对 UI 的直出，改走 `AsyncController`。

**S-06 · `repo_page` 六个 tab 的空态动作只有三个有，另外三个是「死胡同」**
- 证据：`lib/surface/pages/repo_page.dart:2782-2820`（issues tab **有** `emptyAction: FilledButton.tonal(_create)`）、`:3104-3110`（releases **有**）、`:3358-3363`（branches **有**）；但 `:2911-2935`（PR tab **无** emptyAction）、`:3417-3445`（commits tab **无**）、`:3611-3660`（workflow runs tab **无**）
- 感受：同一个页面的五个标签，空的时候有三个给按钮、三个不给，用户感觉像拼凑的、不是一套产品。
- 修复指令：PR tab 空 → `FilledButton.tonal(_createPr)`；commits tab 空 → 保持但加 `TextButton(_goToCompare)`；workflow runs tab 空 → `FilledButton.tonal(_goToActions)`。

**S-07 · `dashboard_page` 空态被 `SizedBox(height: 屏幕高 × 0.5)` 撑成半屏空白**
- 证据：`lib/surface/pages/dashboard_page.dart:449-470`（`SizedBox(height: MediaQuery.sizeOf(context).height * 0.5, child: OgLAsyncEmptyPane(...))`），`:436`（加载 = 裸转圈），`:487`（尾加载 = 裸转圈）
- 感受：**上半屏灰图标 + 一行字，下半屏什么都没有**——「空」字面意义的半屏留白，1-C 已报，本席逐页复核确认仅此一处采用 `0.5` 屏高占位（另有 `gist_detail_page.dart:495` 的 `0.5` 是弹层高度、非空态）。
- 修复指令：删掉 `dashboard_page.dart:451-453` 的 `SizedBox`，让 `OgLAsyncEmptyPane` 自身 `Center` 居中即可；空态的三个动作（`_createRepo` / `_goDiscover`）已经存在，保留。

**S-08 · `search_page` 同一个页面里两套加载视觉：推荐 tab 骨架、结果 tab 裸转圈**
- 证据：`lib/surface/pages/search_page.dart:793-794`（推荐 tab → `_SkeletonList`）；`:1362-1364`（搜索结果 → `const Center(child: CircularProgressIndicator())`）；`:1291` 附近另有 `controller == null` 分支同样裸转圈
- 感受：搜索时先出现六条灰色骨架行（专业），一切到别的模式又变成一片空白转圈（廉价）。同一屏两种语言。
- 修复指令：`search_page.dart:1364` 与 `controller == null` 分支改用与推荐 tab 同源的骨架（最好直接复用 S-01 提出的 `OgLAsyncSkeleton`），保证同一页面零视觉跳变。

**S-09 · `search_page` 推荐 tab 手写错误态，把原始异常当文案显示给用户**
- 证据：`lib/surface/pages/search_page.dart:796-812`（`Text('$_repoError')`，`_repoError` 在 `:504` 被赋为 `error`（`Object`）→ `'$e'` 风格原文）；同页 `:503-506`
- 感受：屏幕上出现 `Exception: ...` / `SocketException: ...` 这类开发者文本，既不可读也暴露内部结构；与 `AsyncController._describe`（`async.dart:215-245`，会把异常归类成「网络异常/权限不足/不存在/未知」）完全两套。
- 修复指令：`search_page.dart:504` 改为存 `_describe(error)` 同款分类文案（或直接把这块迁到 `AsyncController`），`:803` 的 `Text` 换成 `OgLAsyncErrorPane(message: _repoError!, onRetry: _loadMoreRepos)`，与 `repo_page.dart:2521-2525` 同款。

**S-10 · `dashboard_page` 与 `paged_controller` 的错误文案是原始异常字符串**
- 证据：`lib/surface/pages/dashboard_page.dart:600`（`error = '$e';`）、`lib/surface/app/paged_controller.dart:221`（`error = '$e';`）；二者都被直接塞进 `OgLAsyncErrorPane`（`dashboard_page.dart:438-442`、`repo_page.dart:2521-2525`、`repo_page.dart:2447-2450`）
- 感受：用户看到的是 `Exception: SocketException: Connection failed` 这种原文，而不是「网络异常，请重试」。
- 修复指令：把 `async.dart:215-245` 的 `_describe` 抽成顶层可复用函数 `String ogLDescribeError(Object error)`（放 `lib/surface/app/async.dart` 或 `lib/surface/util/`），`paged_controller.dart:221` 与 `dashboard_page.dart:600` 改用它。

**S-11 · `file_preview_page` 错误文案直接抛原始异常**
- 证据：`lib/surface/pages/file_preview_page.dart:191`（`_error = '$error';`），`:227-230`（错误态用 `OgLAsyncErrorPane` 呈现）
- 感受：错误面板的视觉是对的，但文字是 `Exception: ...`，用户读不懂。
- 修复指令：改用 S-10 抽出的 `ogLDescribeError`，或按场景写明「文件读取失败（$error）」。

**S-12 · `new_gist_page` 的校验与提交失败只用一次性 Toast，另外三个新建页用内联错误卡——两套并存**
- 证据：`lib/surface/pages/new_gist_page.dart:88-95`（文件名/内容为空 → `OgLNotifier.of(context).info(...)` Toast）；`:110-119`（创建失败 → `OgLNotifier...warning(...)` Toast）；对照 `new_issue_page.dart:160-172`（`errorContainer` 内联卡）、`new_repo_page.dart:173-186`、`new_release_page.dart:213-226`（同为内联卡）
- 感受：Toast 4 秒后消失，用户还没读完就没了，还容易和别处的提示撞车；同一个「新建」流程里三种页面三种报错方式。rules/04 §3 要求错误必须持续可见且紧邻来源。
- 修复指令：`new_gist_page.dart` 增 `_error` 字段，把 `:88-95` 的校验失败与 `:110-119` 的提交失败都改为与 `new_issue_page.dart:160-172` 同款 `errorContainer` 内联卡（图标 + 文案 + `TextButton(_t('retry'))`）；`_error` 在输入变化时清除。

**S-13 · 加载指示器没有 300ms 延迟也没有最小显示时长，快速返回时闪一下**
- 证据：`lib/surface/app/async.dart:141-152`（`_loading = true; _notify();` 立即触发；`:157-163` 完成后立刻 `_loading=false`）；`AsyncView`/`OgLAsyncSliver` 无延迟逻辑
- 感受：网快时列表闪一下转圈就跳到内容，像卡顿而不是加载。
- 修复指令：在 `AsyncController` 内加 `Timer` 延迟 300ms 才置 `_showSpinner`（`isLoading` 保留真实值供逻辑用），完成时保证指示器至少显示 300ms 再撤。

### 轻

**S-14 · `repo_page` 三个位置用裸 `Center(CircularProgressIndicator())` 代替统一态**
- 证据：`lib/surface/pages/repo_page.dart:789`（`_pagedBody` 首次加载）、`:2452`（文件树 busy）、`:2527`（目录条目加载）、`:818`（加载更多）
- 感受：仓库页是使用频次最高的页，加载时整屏空白。
- 修复指令：`_pagedBody`（`repo_page.dart:777-830`）整体改为复用 `AsyncView`/`OgLAsyncSliver` 语义或至少复用 S-01 的骨架；`:2452`/`:2527` 的行内转圈改用 16dp `CircularProgressIndicator(strokeWidth: 2)` 嵌入行内，不占满屏。

**S-15 · `release_detail_page` 的附件区空态只有一行 Text，与全库空态视觉不一致**
- 证据：`lib/surface/pages/release_detail_page.dart:526-529`（`if (_release.assets.isEmpty) → Padding(child: Text(_t('noAssets')))`）
- 感受：整页其余部分都是 Card / ListTile，唯独空附件是一行裸文字，像没做完。
- 修复指令：改为 `OgLAsyncEmptyPane(icon: Icons.inventory_2_outlined, text: _t('noAssets'), action: FilledButton.tonal(_uploadAsset))`。

**S-16 · `notifications_page` 空态没有「触发一次通知」的下一步，且筛选维度的空态文案与全量空态混用**
- 证据：`lib/surface/pages/notifications_page.dart:219-226`（`_filter == 1` 用 `emptyUnread`，其余筛选（2=警告、3=错误）全部复用 `_t('empty')`＝「没有符合条件的事件」）
- 感受：切到「错误」筛选看到「没有符合条件的事件」，用户不知道是筛选掉的还是真的没有；且整页没有「怎么产生通知」的引导。
- 修复指令：按筛选维度给差异化文案（`emptyWarning` / `emptyError`，写入 `assets/i18n/zh/notifications_page.json` 与 `en/`），并在 `OgLAsyncEmptyPane` 的 action 位放 `FilledButton.tonal(_clearFilter, Text(_t('clearFilter')))`。

**S-17 · `action_log_page` 的筛选空态没有「清除筛选」动作**
- 证据：`lib/surface/pages/action_log_page.dart:369-376`（`OgLAsyncEmptyPane(icon: Icons.filter_alt_off_outlined, text: _t('noMatchingJob'))`，无 action）
- 感受：日志被搜没了，页面不告诉你怎么把搜索框清空。
- 修复指令：加 `action: TextButton(onPressed: _clearFilter, child: Text(_t('clearFilter')))`，文案写入 `action_log_page.json`。

**S-18 · `login_page` OAuth 失败把原始异常抛给用户**
- 证据：`lib/surface/pages/login_page.dart:158`、`:207`（`_oauthError = '$error';`），`:521-527` 直接渲染
- 感受：OAuth 失败时看到 `Exception: ...`。
- 修复指令：用 `ogLDescribeError` 或写死「授权失败，请重试」+ 保留原文进日志。

**S-19 · `workflow_dispatch_page` 的表单级错误不是可重试的独立错误面**
- 证据：`lib/surface/pages/workflow_dispatch_page.dart:87-88`（`_loadingForm` / `_formError`）、`:530-537`（错误以 `Text(bodySmall)` 呈现，无图标、无重试按钮）；`:189-241` 三条失败分支各自 set `_formError`
- 感受：读 workflow 文件失败后只有一行小字，用户不知道点哪里重来。
- 修复指令：`:530-537` 改为 `OgLAsyncErrorPane`（带 `FilledButton.tonal(_retryParse)`），或至少在文案后加 `TextButton(_t('retry'))`。

**S-20 · `onboarding_page` 的权限步骤加载失败后没有任何错误提示（同 S-02 的另一处），且下一步按钮在 pending 时无解释**
- 证据：`lib/surface/pages/onboarding_page.dart:350-353`（`Center(CircularProgressIndicator())` 裸转圈占整卡）；`:294`（`onPressed: permissionPending ? null : _next` —— 禁用但没有说明为什么）
- 感受：权限列表加载卡住时整块白转；「下一步」变灰时用户不知道是在等权限还是坏了。
- 修复指令：`:350-353` 改骨架或行内小转圈；`:294` 的禁用条件补一条 `Text(_t('waitingPermission'))` 说明。

**S-21 · `code_editor_page` / `login_page` 的按钮内联转圈是全库正解，但没有推广**
- 证据：`lib/surface/pages/code_editor_page.dart:596-604`（保存按钮内 `CircularProgressIndicator(strokeWidth: 2)` + `onPressed: _saving ? null : _save`）；`lib/surface/pages/login_page.dart:410-420`（登录按钮内联转圈）；对照 `new_issue_page.dart:177`、`new_repo_page.dart:200`、`new_release_page.dart:240`、`new_gist_page.dart:148`（仅换文案，无转圈）
- 感受：同一个 App 里两种等待表达。
- 修复指令：把四个新建页的提交按钮统一成 code_editor 的写法（按钮内 16dp 转圈 + 文案保留），并按 rules/04 §4 锁定按钮宽度避免按压时尺寸跳动。

**S-22 · 禁用按钮普遍「静默置灰」，缺原因说明**
- 证据：`lib/surface/pages/repo_tags_page.dart:183`（新建标签 `onPressed: _busy ? null : ...`，禁用时仍写「创建」）、`:251`（删除 `onPressed: _busy ? null : ...`）；`lib/surface/pages/release_detail_page.dart:467`、`:477`（编辑/删除）；`lib/surface/pages/action_run_page.dart:621`、`:630`、`:637`（重跑/重跑失败/取消三个按钮同时置灰，用户不知是哪一步卡住）
- 感受：一片灰按钮，没有一个告诉你为什么灰。rules/04 §2 明确：不能把禁用当唯一机制。
- 修复指令：按钮禁用时保持文案不变并配 `Tooltip` 或行内 `Text(_t('busyHint'))`；`action_run_page.dart:621-640` 至少在下方保留一行 `_operationStatus` 说明当前动作。

**S-23 · `download_manager_page` 空态是手写的，且没有动作**
- 证据：`lib/surface/pages/download_manager_page.dart:254-269`（手写 `Center(Column(Icon + Text + bodySmall))`，未复用 `OgLAsyncEmptyPane`）
- 感受：与其它页的空态视觉不同（图标尺寸 `OgLIconSize.empty`=48 而非 40），且用户看完不知道能做什么。
- 修复指令：改用 `OgLAsyncEmptyPane(icon: Icons.download_outlined, text: _t('empty'), action: FilledButton.tonal(_openDownloadDir, Text(_t('openDownloadDir'))))`。

**S-24 · `gist_detail_page` / `profile_page` / `workflow_dispatch_page` 的空态文案是通用词，无「首次使用」引导**
- 证据：`gist_detail_page.dart:366-367`（`_t('noFiles')`）、`profile_page.dart:231-232`（`_t('notLoggedIn')`）、`workflow_dispatch_page.dart:423-424`（`_t('noWorkflows')`）
- 感受：rules/04 §5 要求 first-use 的空态要「教育 + CTA」；现在只有陈述。
- 修复指令：改文案为「还没有 X —— <一句话说明它是什么>」，并配 S-03 表中的 CTA。

---

## 2. 逐页四态矩阵（30 页全覆盖）

实现方式记号：**U** = 统一出口（`AsyncView` / `OgLAsyncSliver`）；**H** = 手写；**M** = 缺失（N/A 为纯静态页）。

| # | 页面（file） | loading | empty | error | disabled | 实现 |
|---|---|---|---|---|---|---|
| 1 | about_page | N/A | N/A | N/A（外链失败走 Notifier，`about_page.dart:64,80`） | N/A | M（静态页，无异步） |
| 2 | action_log_page | U `action_log_page.dart:361` | H 空态无动作 `:363-364`、`:371-376` | U（AsyncController 自带） | N/A | U/H |
| 3 | action_run_page | U `action_run_page.dart:563` | H 无动作、默认 `inbox` 图标 `:564-565` | U | H 三按钮同时置灰 `:621,630,637` | U/H |
| 4 | code_editor_page | H 保存按钮内联转圈 `:601` | N/A | H 提交失败走 Notifier `:337-344` | H `:600` | H（页面级正确） |
| 5 | commit_page | U（sliver）`commit_page.dart:153` | U 无动作 `:156-159` | U | N/A | U |
| 6 | dashboard_page | H 裸转圈 `:436`、`:487` | H 半屏 SizedBox `:451-453`（**有** CTA） | H 原始异常 `:600` | N/A | H |
| 7 | download_manager_page | N/A（本地源） | H 手写无动作 `:254-269` | H 行内 errorText `:453-461` | H | H |
| 8 | drafts_page | U `drafts_page.dart:212` | U 无动作 `:214-215` | U | N/A | U |
| 9 | file_preview_page | H 裸转圈 `:220-222` | H `_notice` 无 CTA `:237-239` | H 但有重试 `:227-230`；文案原始异常 `:191` | N/A | H |
| 10 | gist_detail_page | U `gist_detail_page.dart:364` | U 无动作 `:366-367` | U | H `:360` | U |
| 11 | gists_page | U `gists_page.dart:142` | U 无动作 `:144-145` | U | N/A | U |
| 12 | issue_page | U（评论 sliver）`issue_page.dart:793` | U 无动作 `:796-798` | U | H `_busy?null` `:730,778` | U |
| 13 | legal_text_page | H 裸转圈 `:164-165` | H 一行字 `:166-173` | **M（失败伪装成空）** `:72-80` | N/A | H/M |
| 14 | login_page | H 按钮内联转圈 `:410-420` | N/A | H `_error`/`_oauthError` `:430-441`、`:521-527`；OAuth 原文 `:158,207` | H | H |
| 15 | network_page | N/A | N/A | N/A | N/A | M（静态壳） |
| 16 | new_gist_page | N/A | N/A | **H 一次性 Toast** `:88-95`、`:110-119` | H `:148` 无转圈 | H |
| 17 | new_issue_page | N/A | N/A | U 内联 errorContainer `:160-172` ✓ | H `:177` 无转圈 | H（较好） |
| 18 | new_release_page | N/A | N/A | U 内联 `:213-226` ✓ | H `:240` 无转圈 | H（较好） |
| 19 | new_repo_page | N/A | N/A | U 内联 `:173-186` ✓ | H `:200` 无转圈 | H（较好） |
| 20 | notifications_page | N/A（本地日志） | H `OgLAsyncEmptyPane` 无动作 `:219-226`；筛选文案混用 | N/A | N/A | H |
| 21 | onboarding_page | H 裸转圈 `:352` | **M（失败伪装成空）** `:99-108` | M（仅进日志） | H `:294` 无说明 | H/M |
| 22 | profile_page | U `profile_page.dart:229` | U 无动作 `:231-232` | U | H `:332` | U |
| 23 | pull_page | U（sliver）`pull_page.dart:159` | U 无动作 `:169-171` | U | N/A | U |
| 24 | release_detail_page | M（无加载态） | H 一行字 `:526-529` | M（仅 Notifier） | H `:467,477` | M/H |
| 25 | repo_page | H 裸转圈 `:789,2452,2527,818` | H 但 3/6 tab 有 CTA `:2817,3104,3358`；3 tab 无 `:2911,3417,3611` | H 原始异常 `paged_controller.dart:221` | H 多处 | H |
| 26 | repo_tags_page | H 裸转圈 `:210-212,236` | H 一行字无图标 `:213-219` | H 裸 Text+按钮 `:191-208` | H `:183,251` | H（最不一致） |
| 27 | search_page | 混合：骨架 `:793` / 裸转圈 `:1364` | H `Center(Text)` 无动作 `:814`；H 无动作 `:776,1027` | H 原始异常 `:803` | N/A | H/U |
| 28 | settings_page | N/A | N/A | H 仅 Notifier `:741-869` | N/A | M（静态设置页） |
| 29 | settings_section_page | N/A | N/A | N/A | N/A | M（纯壳） |
| 30 | workflow_dispatch_page | U `workflow_dispatch_page.dart:421` | U 无动作 `:423-424` | U（列表级）；表单级 H `:530-537` 无重试 | H `:416` | U/H |

**统计**：U（完全统一）= 5 页（commit / drafts / gists / profile / pull）；U+H 混合 = 6 页（action_log / action_run / gist_detail / issue / search / workflow_dispatch）；**纯手写 = 11 页**（code_editor / dashboard / download_manager / file_preview / legal_text / login / new_gist / notifications / onboarding / release_detail / repo_page / repo_tags —— 计 12）；**纯静态 N/A = 4 页**（about / network / settings / settings_section）。

**逐页复核「半屏 SizedBox 空态占位」结论**：全库 `MediaQuery...height * 0.x` 共 5 处（`settings_page.dart:2130` 弹层、`code_editor_page.dart:373` 弹层、`repo_page.dart:701` 分支弹层、`gist_detail_page.dart:495` 弹层、`dashboard_page.dart:452` **空态**）。**只有 `dashboard_page.dart:452` 一处是空态半屏占位**，1-C 结论成立，其余四处是弹层高度，不属本席范畴。

---

## 3. 统一出口使用矩阵（`async.dart` 被谁用了 / 谁自己手写）

| 页 | 用的统一件 | 手写部分 |
|---|---|---|
| action_log / action_run / commit / drafts / gist_detail / gists / issue / profile / pull / workflow_dispatch | `AsyncView` 或 `OgLAsyncSliver` | 空态文案/CTA 各自写（多数不给 CTA） |
| search | `AsyncView` ×3 | 推荐 tab 全套手写（骨架/错误/空态） |
| repo_page | 无（只用 `OgLAsyncEmptyPane` / `OgLAsyncErrorPane` 两个视觉件） | `_pagedBody` 自己实现四态判定 `:777-830` |
| dashboard | 无 | `_RepoPaged` 自建状态机 `:542-624` |
| repo_tags / legal_text / file_preview / onboarding / notifications / download_manager | 无 | 三态全手写 |
| **完全没用统一出口的异步页** | **7 页** | repo_page / dashboard / repo_tags / legal_text / file_preview / onboarding / search(部分) |

**结论**：`async.dart` 是事实上的统一出口，但**覆盖率只有 13/21 个有异步的页**；剩下 7 页各自手写，导致同一个 App 里**错误面板有两种样子**（`repo_tags` 裸 Text vs `OgLAsyncErrorPane` 红色图标卡）、**空态有三种样子**（`OgLAsyncEmptyPane` / 裸 Text / 手写 Icon+Text）、**加载有四种样子**（裸转圈 / 骨架 / 按钮内转圈 / 行内转圈）。

---

## 4. 修复指令汇总（按优先级）

1. **【P0】** 提公共骨架件 `OgLAsyncSkeleton`（从 `search_page.dart:134-147` 抽取），替换 `async.dart:293-300` 与 `:552-560` 的裸转圈，并加 300ms 延迟 + 最小显示时长（`async.dart` 的 `AsyncController`）。
2. **【P0】** 修 error→empty 混淆：`legal_text_page.dart:72-80`+`:164-173`、`onboarding_page.dart:99-108`（补 `OgLAsyncErrorPane` + 重试）。
3. **【P0】** `OgLAsyncSliver` 增加 `emptyAction`（`async.dart:485-497`），给 issue 评论 / commit / pull 的空态加 CTA。
4. **【P1】** 给 14 个无动作空态逐页加 CTA（见 S-03 表）；统一用 `FilledButton.tonal`。
5. **【P1】** `repo_tags_page` 整页迁移到 `AsyncController`/`AsyncView`；`repo_page` 的 PR/commits/runs 三个 tab 补 `emptyAction`。
6. **【P1】** 错误文案统一：把 `async.dart:215-245` 的 `_describe` 抽成 `ogLDescribeError(Object)`，替换 `paged_controller.dart:221`、`dashboard_page.dart:600`、`file_preview_page.dart:191`、`login_page.dart:158,207`、`search_page.dart:504`。
7. **【P1】** `new_gist_page` 改内联错误卡（对齐 `new_issue_page.dart:160-172`）；四个新建页提交按钮改按钮内转圈（对齐 `code_editor_page.dart:596-604`）。
8. **【P2】** 筛选型空态差异化文案 + 「清除筛选」动作（`notifications_page.dart:219-226`、`action_log_page.dart:369-376`）；文案入 `assets/i18n/zh/*.json` 与 `en/`。
9. **【P2】** `release_detail_page.dart:526-529`、`download_manager_page.dart:254-269` 空态改 `OgLAsyncEmptyPane`。
10. **【P2】** 禁用按钮补原因说明（`repo_tags_page.dart:183,251`、`release_detail_page.dart:467,477`、`action_run_page.dart:621-640`、`onboarding_page.dart:294`）。
11. **【P2】** `workflow_dispatch_page.dart:530-537` 表单错误升级为带重试的错误面；`search_page.dart:796-812` 错误态统一为 `OgLAsyncErrorPane`。

---

## 5. 检查清单（已查 / 已确认无问题）

**已逐页检查的文件（30/30）**：`about_page` `action_log_page` `action_run_page` `code_editor_page` `commit_page` `dashboard_page` `download_manager_page` `drafts_page` `file_preview_page` `gist_detail_page` `gists_page` `issue_page` `legal_text_page` `login_page` `network_page` `new_gist_page` `new_issue_page` `new_release_page` `new_repo_page` `notifications_page` `onboarding_page` `profile_page` `pull_page` `release_detail_page` `repo_page` `repo_tags_page` `search_page` `settings_page` `settings_section_page` `workflow_dispatch_page`。

**四态逐项检查点**：
- [x] loading：是否存在 / 统一还是手写 / 裸转圈还是骨架 / 是否占满屏 / 是否行内 / 有无 300ms 延迟 / 有无最小显示时长 —— 21 页有加载态，全部无延迟无最小时长，16 页裸转圈，1 页骨架。
- [x] empty：是否只有一行字 / 有无图标 / 有无下一步动作 / 是否区分 first-use 与 filtered-zero / 是否有半屏占位 —— 14 页无 CTA；3 处文案混淆（action_log 筛选 / notifications 筛选 / search 推荐）；半屏占位仅 `dashboard_page.dart:452` 一处。
- [x] error：有无重试入口 / 错误消息完整度 / 是否抛原始异常 / 是否把失败当空 —— 17 页有重试；4 页抛原始异常；2 页失败伪装成空。
- [x] disabled：置灰语义是否可解释 / 有无并行进度指示 / 是否误用禁用做校验 —— 全部禁用仅靠 `onPressed: null`，4 处未说明原因；无一处用禁用按钮代替校验（新_issue 等均允许提交后再报错）。
- [x] `async.dart` 统一出口被哪些页用了：`rg -l "AsyncView|OgLAsyncSliver|OgLAsyncEmptyPane|OgLAsyncErrorPane" lib/surface/pages/` = 13 页；哪些页自己手写三态 = 12 页。

**已确认无问题的部分**：
- `async.dart` 的 `AsyncController` 状态机本身正确：并发抑制（`:139-143`）、世代计数防撕裂（`:78-83`、`:155-157`）、失败保留旧数据（`softError`，`:112-113` + `OgLAsyncSoftErrorBar` `:441-482`）、错误分类（`_describe` `:215-245`）、释放后不通知（`:118-129`）—— 这套机制是好的，问题在于**页面绕过它**。
- `OgLAsyncErrorPane`（`async.dart:343-380`）视觉与文案合规：错误色图标 + 居中说明 + `FilledButton.tonal` 重试，符合 rules/04 §5。
- `OgLAsyncSoftErrorBar`（`async.dart:441-482`）实现了「刷新失败但保留旧数据」，符合 rules/04 §4 stale-while-revalidate；问题仅在于 sliver 形态没有对应实现。
- `new_issue_page` / `new_release_page` / `new_repo_page` 的内联错误卡（`new_issue_page.dart:160-172` 等）符合 rules/04 §3「错误必须持续可见、紧邻来源」，是全库新建页的正确范式。
- `code_editor_page.dart:596-604` 的按钮内联转圈 + `login_page.dart:410-420` 同样是正确的 pending 范式，应作推广样板。
- `repo_page.dart:2539-2545`（目录空态带「新建文件」CTA）与 `:2817`、`:3104`、`:3358` 的空态动作是全库最佳实践，四处一致。
- `commit_page.dart:157-159` 对「初始提交」与「无变更」做了文案区分（`_t('initialCommit')` vs `_t('noChanges')`），符合 rules/04 §5 的 cause differentiation。
- `pull_page.dart:159-171` 与 `issue_page.dart:793-798` 的 sliver 懒加载正确（性能无问题），仅缺 CTA。
- `download_manager_page.dart:453-461` 的行内任务错误 + `:297-330` 的「重试全部失败」批量入口可用，缺的是页面级空态动作。
- 四个纯静态页（about / network / settings / settings_section）无异步需求，本席不判缺失。

**复现命令**：
```bash
cd /root/OhGithubLost
rg -n "CircularProgressIndicator" lib/surface/pages/ lib/surface/app/async.dart   # 裸转圈分布
rg -n "OgLAsyncEmptyPane\(" -A4 lib/surface/pages/ | rg "emptyText|action"        # 空态有无 CTA
rg -n "error = '\\\$e'|_error = '\\\$error'" lib/surface/                            # 原始异常外泄
rg -l "AsyncView|OgLAsyncSliver" lib/surface/pages/                                # 统一出口覆盖率
```

---

> **报告完**。本席未改动任何代码，未 commit / push；所有结论均可用上述 `file:line` 复现。
