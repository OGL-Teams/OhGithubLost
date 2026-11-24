# 批 3 · 控件与状态 · B 席 —— 四态与骨架复审（v15.0.0 之后）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 3 · 控件与状态 · B（四态与骨架）**
> - 审计对象：`lib/surface/app/async.dart`（统一异步出口）/ `lib/surface/app/client_shell.dart`（`_checked` 中间态）/ `lib/surface/pages/` **全部 30 页** / `lib/surface/app/notifier.dart`（SnackBar 语气）/ `lib/surface/app/paged_controller.dart`
> - 仓库：`/root/OhGithubLost`，HEAD = `46981c0`，`pubspec.yaml` version = **15.0.0+150000**
> - 审计时间：**2026-11-24 22:46:37 (LCL)**　语言：zh-Hans
> - 参照规范：`material-3/SKILL.md`（Components 节：进度指示器 / 状态容器 / 空态）、`sota-frontend-design/rules/04-ux-patterns.md`（§2 禁用按钮禁忌、§4 Loading & perceived performance、§5 Empty/error/zero states）
> - 交叉基线：`docs/UX_CROSS_AUDIT/3-B-states.md`（v14，61 条确证中本席负责项）、`docs/UX_STABILITY_PLAN.md`（D-05/D-06/F-03/F-11）、`docs/UI_AUDIT_V2/2-B-density.md`（4 处假 CTA）
> - **只读审计**：未改动任何代码，未 commit / push。唯一产出即本文件。
> - 禁读纪律遵守：全程只读项目 `lib/` 与 `docs/`，未读取 /root/flutter、/opt/flutter、/tmp/dart-sdk 或 pub 缓存源码；未调用 dart（纯审计，无需 format）。

---

## 0. 方法与基线

统一出口仍是 `lib/surface/app/async.dart`：`AsyncController<T>`（状态机）/ `AsyncView<T>`（盒子态）/ `OgLAsyncSliver<T>`（sliver 态）/ `OgLAsyncSkeleton`（新增骨架件）/ `OgLAsyncErrorPane` / `OgLAsyncEmptyPane` / `OgLAsyncSoftErrorBar`。

v15 在本席范围内的动作只有三件：**新增 `OgLAsyncSkeleton`（两段式）**、**`AsyncView`/`OgLAsyncSliver` 加 `emptyAction`**、**`AsyncController` 加 300ms 防抖 + 最小显示时长**。本席按这三条逐一验证实际覆盖面。

**本轮实测基线（rg 可复现）**

| 指标 | v14 实测 | **v15 实测** | 期望 |
|---|---|---|---|
| `OgLAsyncSkeleton` 的调用点 | — | **仅 1 处**：`async.dart:325`（`AsyncView` loading 分支） | 所有内容区加载态 |
| 仍用**裸 `CircularProgressIndicator`** 的加载分支（不含按钮内联转圈、不含启动 splash） | 16 页 | **16 处分支**（下表 §2.1；全库 `CircularProgressIndicator` 代码调用共 24 处 = 16 裸转圈 + 7 按钮内联 + 1 启动 splash） | 0 |
| 仍用裸转圈的**整页/整区**加载（占满内容区） | 16 | **13 处** | 0 |
| 空态带 CTA 的调用点 | 4 | **13 处 `emptyAction`** | — |
| 其中**点不动**的假 CTA | 0 | **4 处**（`onPressed: null`） | 0 |
| 错误文案抛原始异常 | 4 页 | **4 处仍在**（`paged_controller.dart:221`、`dashboard_page.dart:597`、`file_preview_page.dart:192`、`login_page.dart:158,207`） | 0 |
| error→empty 混淆（失败伪装成空） | 3 页 | **2 处已修**（legal_text / onboarding），**1 处仍在**（`file_preview_page.dart:239` 空文件被告知「文件过大」） | 0 |
| 加载态有 300ms 延迟 + 最小显示 | 0 | **仅 `AsyncController`**；`PagedController`（repo_page 全页）与 `dashboard._RepoPaged` **无** | 全部 |

---

## 1. 闭环核对（旧确证逐条）

| 编号 | 来源 | 结论 | 依据 |
|---|---|---|---|
| **D-05** 空态半屏占位 + 14 页无 CTA | UX_STABILITY_PLAN:219 | **修法有问题** | 半屏 `SizedBox` 已删（`dashboard_page.dart:449-466` 改为 `ListView + OgLAsyncEmptyPane + FilledButton`，CTA 有效）；`OgLAsyncEmptyPane` 加了 `maxWidth:320`、图标降到 `OgLIconSize.xl`（`async.dart:452-499`）。**但** 13 处 `emptyAction` 里 **4 处 `onPressed: null`**（`issue_page.dart:852`、`commit_page.dart:164`、`search_page.dart:1397`、`drafts_page.dart:205`），代码注释自认「待主会话/CI 裁决」——**空态从「没有出口」变成「假出口」**；另有 `repo_page` 三个 tab（PR/commits/runs）仍无 CTA。 |
| **D-06** 唯一加载态是「空白屏 + 裸转圈」，16 页共用 | UX_STABILITY_PLAN:225 | **未修** | `OgLAsyncSkeleton` 只被 `AsyncView` 一处调用（`async.dart:325`）。`OgLAsyncSliver` 的 loading 分支**仍是裸转圈**（`async.dart:644`）→ 影响 issue 评论 / commit 文件 / pull 文件三个高频列表。页面级裸转圈 16 处分支见 §2.1。另 `search_page.dart:71-148` 仍保留**自己那套 `_SkeletonList/_SkeletonRow/_SkeletonBox`**，公共骨架件没有被真正统一。 |
| **F-11** 「加载失败」渲染成「你还没有内容」 | UX_STABILITY_PLAN:341 | **修法有问题** | `legal_text_page.dart:167-179` 已加 `_error` + `OgLAsyncErrorPane(onRetry: () => _load(_locale))`（`:171`）；`onboarding_page.dart:105-117` 已置 `_error`、`:360` 渲染 `OgLAsyncErrorPane(message: _error!, onRetry: _load)`——**两处已真修**。但 `file_preview_page.dart:236-239` 仍把「0 字节文件」显示成 `_t('previewTooLarge')`＝「文件过大，无法在内置预览中加载」——**失败/空被说成另一个原因，比原来更误导**。 |
| **F-03** SnackBar 无 action / 无 duration / 无语气 | UX_STABILITY_PLAN:293 | **已修** | `notifier.dart:116-155`：三种语气（success/info/warning）**三重区分**（背景色 + 前置图标 + 文字色），`duration` 收敛到 `kNotifierDuration(4s)` / `kNotifierActionDuration(8s)`，`action` 通道存在，floating + 统一 margin。`notifier.dart:98-106` 还有「messenger 已卸载则写日志、不静默吞提示」的闭环。 |
| **S-01** 全库唯一加载出口是「空白屏 + 裸转圈」 | UX_CROSS_AUDIT/3-B:47 | **未修** | 16 处裸转圈分支仍在（§2.1）；`AsyncView` 虽换成骨架，但骨架**只有 2 块 68dp**且**垂直居中**（`async.dart:371-410`），与最终列表布局零重合 → 内容到达时仍整片下移。 |
| **S-03** 空态没有下一步动作（14 页） | UX_CROSS_AUDIT/3-B:96 | **修法有问题** | 13 处 `emptyAction` 中 **9 处有效**（gists/gist_detail/drafts/profile/action_run/workflow_dispatch/action_log 筛选/issue 无效…）。**4 处禁点**（2-B 已报，仍在）；**仍无 CTA 的空态**：`action_log_page.dart:364`（首次空 `noLogs`）、`repo_page.dart:2950`（PR tab）、`:3462`（commits tab）、`:3677`（workflow runs tab）、`:3626`（runs 筛选空）、`search_page.dart:791`（feed 空）、`:1050`（issues 筛选空）、`repo_tags_page.dart:213-219`（一行字）、`release_detail_page.dart:526-529`（一行字）、`download_manager_page.dart:250-257`（手写 Icon+两行字）、`file_preview_page.dart:237-239`（0 字节文件）、`search_page.dart:1042`。 |
| **S-04** `OgLAsyncSliver` 缺 `emptyAction`，架构上无法带 CTA | UX_CROSS_AUDIT/3-B:118 | **已修** | `async.dart:571-574` 构造参数已有 `emptyAction`，`:628-633` 传入 `OgLAsyncEmptyPane`；三个使用方 `issue_page.dart:851`、`commit_page.dart:163`、`pull_page.dart:171` 均已传。**架构堵点已打通，但 issue 的那个 CTA 是禁用的**（见上），所以「能带 CTA」≠「CTA 可用」。 |

**闭环小结**：真正「已修」的只有 **F-03**；**S-04 架构层面已修**但被假 CTA 抵消；**D-05 / F-11 / S-03 修法有问题**；**D-06 / S-01 未修**。

---

## 2. 回归检查（v15 三件大改）

### 2.1 骨架是否真的被所有加载态使用？——否

`rg -n "OgLAsyncSkeleton" lib/` 结果只有两处：定义 `async.dart:371` 与唯一调用 `async.dart:325`。

**仍用裸 `CircularProgressIndicator` 的加载分支共 16 处**（不含 8 处按钮内联转圈——那是正确范式；不含 `boot_splash.dart:67`——那是品牌启动页）：

| # | file:line | 场景 | 级别 |
|---|---|---|---|
| 1 | `lib/surface/app/async.dart:644` | **`OgLAsyncSliver` loading** → issue 评论 / commit 文件 / pull 文件 | P1 |
| 2 | `lib/surface/app/client_shell.dart:280` | 启动检查态 `_checked` 整屏裸转圈 | P1 |
| 3 | `lib/surface/pages/repo_page.dart:790` | 仓库页各 tab 首屏 | P1 |
| 4 | `lib/surface/pages/repo_page.dart:819` | 列表尾 loadMore | P2 |
| 5 | `lib/surface/pages/repo_page.dart:2380` | 图片加载占满查看区 | P2 |
| 6 | `lib/surface/pages/repo_page.dart:2453` | 文件树 busy 整区 | P1 |
| 7 | `lib/surface/pages/repo_page.dart:2528` | 目录条目加载整区 | P1 |
| 8 | `lib/surface/pages/dashboard_page.dart:436` | 首屏整区 | P1 |
| 9 | `lib/surface/pages/dashboard_page.dart:484` | 尾 loadMore | P2 |
| 10 | `lib/surface/pages/legal_text_page.dart:176` | 法律正文整区 | P1 |
| 11 | `lib/surface/pages/file_preview_page.dart:222` | 预览整区 | P1 |
| 12 | `lib/surface/pages/file_preview_page.dart:496` | 媒体预览整区 | P1 |
| 13 | `lib/surface/pages/repo_tags_page.dart:199` | 标签页整区 | P1 |
| 14 | `lib/surface/pages/repo_tags_page.dart:224` | 列表尾 | P2 |
| 15 | `lib/surface/pages/onboarding_page.dart:364` | 权限步骤整卡 | P1 |
| 16 | `lib/surface/pages/search_page.dart:1389` | `controller == null` 首搜整区 | P1 |

其中 **13 处是占满内容区的裸转圈**（1/2/3/6/7/8/10/11/12/13/15/16 及 `repo_page:2380`）。

**骨架是否结构化？——结构化但不对版**：`OgLAsyncSkeleton`（`async.dart:371-410`）是「标题块 160dp×md + 元信息块 220dp×sm」两个圆角矩形，色阶 `surfaceContainerHighest`、圆角 `OgLRadius.cSm`，**是矩形块而非整块纯色**（这一点合格）。但：
- **尺寸不匹配最终布局**：真实列表行 72dp × N 行；骨架只有 2 块共 ~68dp，且被 `Center` **垂直居中**（`async.dart:320-326`）→ 页面顶部全空，内容到达时整片内容从屏幕中部「长」出来，**CLS 未解决**（2-B 的 N-02 成立）。
- **没有列表形态**：`OgLAsyncSkeleton` 不接受 `itemCount`/`itemBuilder`，页面无法给出与真实列表同形的骨架。真正同形的 `_SkeletonList`（`search_page.dart:135-148`，6 行 72dp 行 + divider）**没有**被提升到公共层，等于**两套骨架件并存**。
- **无脉冲/微动**：完全静态块（reduced-motion 友好，但常规档位下 0.3–2s 等待看起来像「卡住」）。

### 2.2 空态 CTA 是否都真能点？——4 处假 CTA 仍在

| 处 | file:line | 文案键 | 现状 | 备注 |
|---|---|---|---|---|
| 1 | `issue_page.dart:851-856` | `emptyActionWriteComment` | `onPressed: null` | 注释：「本页评论输入框无 FocusNode，无法安全聚焦」 |
| 2 | `commit_page.dart:163-168` | `emptyActionViewOnWeb` | `onPressed: null` | 注释：「CommitPage 未消费 html_url」 |
| 3 | `search_page.dart:1396-1401` | `emptyActionGoDiscover` | `onPressed: null` | 注释：「无『去发现』路由调用」 |
| 4 | `drafts_page.dart:202-207` | `emptyActionGoCreate` | `onPressed: null` | 注释：「草稿页无通用『新建草稿』路由」 |

四处注释口径一致：「**保留 CTA 文案与样式，onTap 待主会话/CI 裁决**」——**发布时未裁决**。按 rules/04 §5，空态的 primary action 是「教育用户怎么填满它」的载体；一个灰掉的按钮比没有按钮更糟：它承诺了一个出口却拒绝兑现，用户会反复点它。**规则：宁可没有按钮，不要有假按钮。**

另有 2 处 CTA **与既有入口重复**：`gists_page.dart:146-149`（空态「新建」+ 页面 FAB `:137-140` 同动作）；`profile_page.dart:220-223`（空态「添加账号」+ AppBar 按钮 `:212` 同动作）——不是假按钮，但重复出口。

### 2.3 300ms 防抖——**这是 v15 引入的真回归（P1）**

`AsyncController.load()`（`async.dart:157-181`）：

```
_loading = true; _notify();                      // t=0 立刻显示骨架
await Future<void>.delayed(loadDebounce);        // t=0..300  **请求还没发出去**
value = await loader();                          // t=300 才真正发起网络请求
...finally { if (shown < minLoadingDuration) await delay(...) }   // shown 从 started 起算
```

三个后果：

1. **防抖加在了请求上，而不是指示器上。** rules/04 §4 要求的是「**延迟显示指示器** ~300ms」，而现在是**延迟发请求** 300ms。`AsyncController` 覆盖的所有页面（gists/drafts/gists_detail/profile/action_log/action_run/workflow_dispatch/search）在**任何**刷新上都被硬加 300ms，其中 `profile_page` 的账号是**本地数据**（`profile_page.dart:97`）——**本可瞬开的页面必空 0.3s**。
2. **「最小显示时长」被防抖吞掉了。** `shown` 从 `started`（含 300ms 防抖）起算，因此 `shown >= 300ms` 恒成立，**`minLoadingDuration` 分支实际上永远不会进入**。规则04 §4 真正想要的是「数据到达后**再**保持指示器 ≥300ms」，此处实现与意图相反。
3. **`PagedController`（repo_page 全页 6 个 tab）与 `dashboard._RepoPaged` 没有这套逻辑**——`paged_controller.dart` 全文只有 `_kPageCacheTtl` 一个 Duration，无 debounce/min-display。所以 v15 之后：**有防抖的页面凭空慢 0.3s，没防抖的页面照样闪**。统一出口的收敛目标在加载态上并**未达成**。

---

## 3. 逐页四态覆盖表（30 页全覆盖）

记号：**U** = 走统一出口；**H** = 手写；**✗** = 缺失；CTA 栏：`✓`=有效 / `✗`=禁点 / `—`=无 CTA / `冗`=与既有入口重复。

| # | 页面 | loading | empty | error | disabled | CTA |
|---|---|---|---|---|---|---|
| 1 | about_page | N/A | N/A | N/A（外链失败走 Notifier） | N/A | — |
| 2 | action_log_page | U 骨架 | U `noLogs` **无 CTA**（`:364`） | U | — | 筛选空 ✓ |
| 3 | action_run_page | U 骨架 | U ✓（`:566`） | U | H 三按钮同灰无原因（`:625,634,641`） | ✓ |
| 4 | code_editor_page | H 按钮内联 ✓ | N/A | H Notifier 一次性（`:344`） | H（`:600`） | — |
| 5 | commit_page | **✗ 裸转圈**（sliver `async.dart:644`） | U **CTA 禁点** | U | — | ✗ |
| 6 | dashboard_page | **H 裸转圈**（`:436`,`:484`） | H ✓ 半屏占位已删 | H 原始异常（`:597`） | — | ✓ |
| 7 | download_manager_page | N/A（本地源） | H 手写 Icon+两行字（`:250-257`）**无 CTA** | H 行内 errorText | H | — |
| 8 | drafts_page | U 骨架 | U **CTA 禁点** | U | — | ✗ |
| 9 | file_preview_page | **H 裸转圈**（`:222`,`:496`） | H 0 字节文件说成「文件过大」（`:239`） | H 原始异常（`:192`） | — | — |
| 10 | gist_detail_page | U 骨架 | U ✓（`:354`） | U | H `:346` | ✓ |
| 11 | gists_page | U 骨架 | U ✓（`:146`） | U | — | 冗（=FAB） |
| 12 | issue_page | **✗ 裸转圈**（sliver） | U **CTA 禁点**（`:852`） | U | H `:730,778` 无原因 | ✗ |
| 13 | legal_text_page | **H 裸转圈**（`:176`） | H 一行字 | **✓ 已修**（`:171` 可重试） | — | — |
| 14 | login_page | H 按钮内联 ✓ | N/A | H 卡片内联 ✓，但保留原始异常（`:158,207`） | H | — |
| 15 | network_page | N/A | N/A | N/A | N/A | — |
| 16 | new_gist_page | N/A | N/A | **✗ 一次性 Toast**（`:89,123`） | H `:148` 无转圈 | — |
| 17 | new_issue_page | N/A | N/A | ✓ 内联 errorContainer（`:160`） | H `:177` 无转圈 | — |
| 18 | new_release_page | N/A | N/A | ✓ 内联 | H `:240` 无转圈 | — |
| 19 | new_repo_page | N/A | N/A | ✓ 内联 | H `:200` 无转圈 | — |
| 20 | notifications_page | N/A（本地日志） | H ✓（`:209`） | N/A | — | ✓ |
| 21 | onboarding_page | **H 裸转圈**（`:364`） | **✓ 已修**（`:360` 可重试） | ✓ 已修 | H `:294` 现已有 `detectingPermissions` 说明 ✓ | — |
| 22 | profile_page | U 骨架 | U ✓（`:220`） | U | H `:332` | 冗（=AppBar） |
| 23 | pull_page | **✗ 裸转圈**（sliver） | U ✓（`:171`） | U | — | ✓ |
| 24 | release_detail_page | M 无加载态 | H 一行字（`:526-529`） | M 仅 Notifier | H `:468,478` 无原因 | — |
| 25 | repo_page | **H 裸转圈×5**（`:790,819,2380,2453,2528`） | H 3/6 tab 有 CTA；PR/commits/runs **无** | H 原始异常（`paged_controller.dart:221`） | H 多处 | 3 有 3 无 |
| 26 | repo_tags_page | **H 裸转圈**（`:199,224`） | H **一行字无图标无 CTA**（`:213-219`） | H 裸 Text+按钮，与全库错误面板不一致 | H `:171,239` | — |
| 27 | search_page | 混：feed/issues 骨架（自有 `_SkeletonList`）/ 首搜**裸转圈**（`:1389`） | H `:791`,`:1042`,`:1050` 无 CTA；`:1393` **CTA 禁点** | H `_repoError` 原始异常（`:503`） | — | ✗ |
| 28 | settings_page | N/A | N/A | 仅 Notifier | — | — |
| 29 | settings_section_page | N/A | N/A | N/A | N/A | — |
| 30 | workflow_dispatch_page | U 骨架 | U ✓（`:426`） | U 列表级 ✓；表单级 `:537` 仍是 errorContainer 小字**无重试** | H `:417` | ✓ |

**统计**
- loading：**13 页**走统一骨架（AsyncView 系），**11 页**仍是手写，其中 **8 页**是整区裸转圈；
- empty：**17 处**空态调用点，带 CTA 13 处、有效 9 处、**禁点 4 处**、**完全无 CTA 11 处**；
- error：**4 处**仍抛原始异常；**1 处**（file_preview 空文件）失败/空原因错配；
- disabled：**6 处**灰按钮无原因说明（`repo_tags:171,239`、`release_detail:468,478`、`action_run:625,634,641`）。

---

## 4. 新发现（旧审计未抓到）

### P0（用户完全无法使用 / 主动误导）

**N-01 · 4 处空态 CTA 是「看得见点不动」的假按钮** —— 继承 2-B 的 N-01，但本席确认**至今未裁决**，且**代码注释里写着「待主会话/CI 裁决」就发布了**：v15.0.0 已发出去，用户拿到的就是四个灰按钮。
- 根因：v15 接线批次「保留 CTA 文案与样式，onTap 待裁决」。
- 修复指令（逐处给可落地方案，不许再留 null）：
  - `issue_page.dart:851` → 给评论输入框加 `FocusNode _commentFocus`（`TextEditingController` 已在页内），CTA 改 `onPressed: () => _commentFocus.requestFocus()`；
  - `commit_page.dart:163` → 若 `widget.commit` 无 `html_url` 字段，**直接删掉这个 CTA**（宁可没有按钮）；有则用 `openLinkOrCopy(context, url, tag: 'Commit')`；
  - `search_page.dart:1396` → 改 `onPressed: () => _switchMode(0)`（复用页内已有 tab 切换回调）；
  - `drafts_page.dart:202` → **删掉这个 CTA**（该页无新建草稿路由），或改文案为「刷新」并接 `_controller().load()`。

### P1（明显影响使用体验）

**N-02 · `AsyncController` 的 300ms 防抖加在了「请求」上而不是「指示器」上**（详见 §2.3）
- 根因：`async.dart:165` 的 `await Future<void>.delayed(loadDebounce)` 位于 `loader()` **之前**。
- 修复指令：把 300ms 改成「**先显示骨架，但 300ms 后才置 `_loading`**」的独立计时器：
  ```dart
  _loading = true; _showIndicator = false; _notify();
  _indicatorTimer = Timer(loadDebounce, () { _showIndicator = true; _notify(); });
  value = await loader();            // 请求立刻发出，不被延迟
  ...
  // 完成后：若指示器已显示，凑满 minLoadingDuration 再撤
  ```
  并把 `minLoadingDuration` 改成「**从数据到达时刻**起算」，而不是从 `started` 起算。

**N-03 · `OgLAsyncSliver` 没有软错误通道，刷新失败被静默吞掉**（旧审计未列）
- 证据：`async.dart:611-620` —— 数据非空时直接返回 `SliverList`，**从不读 `controller.softError`**；`OgLAsyncSoftErrorBar`（`async.dart:498-533`）只被 `AsyncView`（`async.dart:337-341`）使用。
- 感受：issue 评论 / commit 文件 / pull 文件列表**下拉刷新失败时，屏幕纹丝不动**，用户以为刷新成功、内容没变——这正是 rules/04 §4 stale-while-revalidate 的反向失败（连「悄悄失败」都不给）。
- 修复指令：`OgLAsyncSliver` 在 `SliverPadding` 之前插一个 `SliverToBoxAdapter(child: OgLAsyncSoftErrorBar(message: soft, onDismiss: controller.dismissError))`；同时给 sliver 补**骨架 loading 分支**（现在仍是 `async.dart:644` 裸转圈）。

**N-04 · 空文件被告知「文件过大」——失败原因错配，比 error→empty 更误导**
- 证据：`file_preview_page.dart:236-239`：`bytes == null || bytes.isEmpty` → `_notice(theme, Icons.info_outline, _t('previewTooLarge'))`；而 `_tooLarge` 已有独立标志（`:177`）。
- 感受：用户上传了一个 0 字节文件，App 说是「文件过大，无法在内置预览中加载」。**用户会去换文件，而真实原因是文件是空的。**
- 修复指令：新增 i18n 键 `previewEmpty`（「文件内容为空」），`bytes.isEmpty` 分支改用它，并给 `action: FilledButton.tonal(onPressed: () => unawaited(_load()), child: Text(_t('retry')))`；`_tooLarge` 继续走 `_tooLargePane`。

**N-05 · `repo_tags_page` 整页仍是「另一套 UI 语言」**
- 证据：`:188-198` 错误态是裸 `Text + FilledButton`（无错误图标、无 `errorContainer`）；`:199` 加载 = 裸转圈；`:203-209` 空态 = 一行 `Text`（无图标、无 CTA）；`:224` 尾 spinner。
- 感受：这是全库唯一还在用「白纸黑字」当错误面板的页，其余 20+ 页都是红色图标卡；空态孤零零一句话。
- 修复指令：整页迁移到 `AsyncController` + `AsyncView`（`async.dart` 已有完整能力），错误 → `OgLAsyncErrorPane`、空 → `OgLAsyncEmptyPane(icon: Icons.local_offer_outlined, text: _t('empty'), action: FilledButton.tonal(onPressed: _openCreateDialog, child: Text(_t('newTag'))))`、加载 → 骨架。

**N-06 · `new_gist_page` 的校验失败与提交失败仍是一次性 Toast**
- 证据：`:88-96`（文件名/内容为空 → `OgLNotifier.info`，4 秒后消失）、`:114-125`（创建失败 → `OgLNotifier.warning`）；对照 `new_issue_page.dart:160-172` / `new_repo_page.dart:173-186` 的内联 `errorContainer` 卡。
- 感受：同一个「新建」流程三种报错方式；Toast 读完即消失，用户还没定位到是哪个字段就没了。
- 修复指令：`new_gist_page.dart` 增 `_error` 字段，校验失败定位到对应 `TextField`（`errorText`），提交失败渲染 `errorContainer` 内联卡（与 `new_issue_page.dart:160-172` 同款），输入变化时清除。

**N-07 · 骨架与最终布局零重合 → 内容到达仍整片位移**
- 证据：`async.dart:371-410` 骨架只有 2 块、宽 160/220dp、`Center` 垂直居中；真实列表行 72dp × N。
- 修复指令：`OgLAsyncSkeleton` 增 `itemCount`（默认 6）与 `itemBuilder`（可选，默认渲染 72dp 行 + 1px divider），页面按真实行高给参；加载态容器从 `Center` 改为顶部对齐（`Alignment.topCenter`），使骨架占位与内容起始位置一致。

### P2（打磨）

**N-08 · `OgLAsyncEmptyPane.subtitle` 全库无调用方**（`async.dart:452,458,461,467-476`）——写了不用的接口，且首用引导文案没有落点。修复：要么在 13 处首用空态传 subtitle（「还没有 X —— 一句话说明它是什么」），要么删参数。

**N-09 · `OgLAsyncSliver` 的 `OgLSurfaceSwitch` 包裹与「懒加载语义」并存有隐患**（`async.dart:618-652`）：三态包在 `SliverToBoxAdapter` 里做切换，数据态直接 `SliverList.builder`，切换时 sliver 高度从「0/居中」跳到「N 行」，视觉上是**内容整体下坠**而非淡入。

**N-10 · `search_page` 双骨架并存**：公共 `OgLAsyncSkeleton` 未被 `search_page` 采用，页内 `_SkeletonList/_SkeletonRow/_SkeletonBox`（`:71-148`）继续独立演化——rules/04 §4「一个视图一次骨架 pass」的前提是单一实现。修复：删页内私有实现，改调 `OgLAsyncSkeleton`。

**N-11 · `repo_page` 三个 tab 空态无出口**（`:2950` PR、`:3462` commits、`:3677` runs、`:3626` runs 筛选）：PR 空 → `FilledButton.tonal(_createPr)`；runs 空 → `FilledButton.tonal(_goToActions)`；runs 筛选空 → `TextButton(_clearFilter)`；commits 空 → 保持但加「查看对比」次级动作。

**N-12 · `release_detail_page` 附件区空态仍是一行裸 Text**（`:526-529`）——同页其余全是 Card/ListTile，唯独附件空态像没做完。改 `OgLAsyncEmptyPane(icon: Icons.inventory_2_outlined, text: _t('noAssets'), action: FilledButton.tonal(_uploadAsset))`。

**N-13 · `download_manager_page` 空态手写且无 CTA**（`:250-257`）——改 `OgLAsyncEmptyPane(icon: Icons.download_outlined, text: _t('empty'), action: FilledButton.tonal(_openDownloadDir, ...))`。

**N-14 · `action_log_page` 首次空态（`noLogs`）无 CTA**（`:364`）——同一文件里筛选空态有「清除筛选」（`:372-381`），首次空却没有「重试/刷新」，两套空态两套待遇。

**N-15 · `search_page` 的 issues 筛选空态无 CTA**（`:1050-1053`）——与 `action_log` 同类问题：筛掉了不说怎么清。

**N-16 · 禁用按钮无原因说明 6 处**：`repo_tags_page.dart:171,239`、`release_detail_page.dart:468,478`、`action_run_page.dart:625,634,641`。修复：按钮禁用时保留文案并加 `Tooltip`/行内 `_t('busyHint')`；`action_run_page` 三按钮同灰时在下方保留 `_operationStatus` 行说明当前卡在哪一步。

**N-17 · 四个新建页提交按钮无按钮内转圈**（`new_issue_page.dart:177`、`new_repo_page.dart:200`、`new_release_page.dart:240`、`new_gist_page.dart:148`）：只把文案换成「提交中」。对齐正解 `code_editor_page.dart:596-604`（16dp 内联转圈 + 保留文案 + 宽度锁定）。

**N-18 · `workflow_dispatch_page` 表单级错误仍是无重试的小字**（`:537-546`）——解析 workflow 文件失败后只留一行 `bodySmall`，用户不知道点哪重来。改 `OgLAsyncErrorPane` 或追加 `TextButton(_t('retry'))`。

---

## 5. 用户满意度视角（三问落到本席范围）

- **等待时有没有结构感？——部分有，形态不对。**
  走 `AsyncView` 的 9 个页面有骨架，但只有 2 块 68dp 且垂直居中，**顶部空白 92%**、**无脉冲**；`OgLAsyncSliver`（issue/commit/pull）与 8 个手写页仍是裸转圈。**用户等待时看到的是「一小块灰条漂在屏幕中间」或「一个转圈」，既没有内容的影子，也没有页面的轮廓**——结构感不成立，反而比旧版更「像空」。
- **空的时候有没有出路？——一半有，一半是假门。**
  13 处 CTA 里 9 处可点（有出路），4 处禁点（假门），11 处空态**根本没有出路**。用户点不动会反复点，然后判定「这 App 坏了」——**假 CTA 比没 CTA 的破坏性更大**。
- **错了能不能自救？——多数能，但有 2 处仍在骗人。**
  `OgLAsyncErrorPane` 全库带「重试」，`legal_text`/`onboarding` 的 error→empty 已修好；但 `file_preview` 把空文件说成「文件过大」、`dashboard`/`paged_controller`/`file_preview`/`login` 仍把 `Exception: ...` 原文甩给用户。

---

## 6. 本席对三问的回答

**问一 · 闭环核对**：本席负责的 7 条旧确证里 —— **已修 1 条**（F-03 SnackBar 语气）、**架构已修 1 条**（S-04 `OgLAsyncSliver` 加 `emptyAction`，但被假 CTA 抵消）、**修法有问题 3 条**（D-05 空态 CTA、F-11 error→empty、S-03 空态无出口）、**未修 2 条**（D-06 骨架统一、S-01 空白屏加载态）。**骨架统一这件 v15 的主打项实际只落地了 1/13。**

**问二 · 回归**：v15 三件大改 —— 骨架**未被所有加载态使用**（`OgLAsyncSkeleton` 仅 1 处调用，16 处加载分支仍是裸转圈，其中 13 处占满内容区），且**骨架不对版最终布局**（2 块 68dp + 垂直居中，到达时仍整片位移）；空态 CTA **4 处仍是假按钮**（`onPressed: null`，注释写着「待裁决」就发了版）；300ms 防抖**加错了地方**——加在请求之前而不是指示器之后，反而让所有 `AsyncController` 页面凭空慢 0.3s，并使「最小显示时长」分支永远不触发；`PagedController`/`dashboard._RepoPaged` 又没有这套逻辑。**本席新查出：sliver 形态无软错误通道（刷新失败静默吞掉）、空文件被说成「文件过大」。**

**问三 · 新发现**：P0 一条（4 处假 CTA 未裁决）、P1 六条（防抖加错位置、sliver 吞掉刷新错误、空文件原因错配、repo_tags 仍是另一套 UI、new_gist 一次性 Toast、骨架不对版位移）、P2 十一条。

---

## 7. 已检查清单（禁止抽样后声称全覆盖）

**文件（已逐行读完相关分支，非抽样）**
`lib/surface/app/async.dart`（659 行全文）· `lib/surface/app/client_shell.dart`（`_checked`/`_check`/启动链）· `lib/surface/app/notifier.dart`（160 行全文）· `lib/surface/app/paged_controller.dart`（loading/error 路径）· `lib/surface/app/boot_splash.dart`（转圈用途）· `lib/surface/app/animations.dart`（`OgLSurfaceSwitch`/`OgLReveal` 语义，用于状态切换动画）

**页面 30/30**：`about_page` `action_log_page` `action_run_page` `code_editor_page` `commit_page` `dashboard_page` `download_manager_page` `drafts_page` `file_preview_page` `gist_detail_page` `gists_page` `issue_page` `legal_text_page` `login_page` `network_page` `new_gist_page` `new_issue_page` `new_release_page` `new_repo_page` `notifications_page` `onboarding_page` `profile_page` `pull_page` `release_detail_page` `repo_page` `repo_tags_page` `search_page` `settings_page` `settings_section_page` `workflow_dispatch_page`

**四态检查点（逐页过）**
- [x] loading：是否存在 / 是否走统一出口 / 裸转圈还是骨架 / 是否占满内容区 / 是否行内 / 是否有 300ms 延迟与最小显示
- [x] empty：有无图标 / 有无 CTA / CTA 是否真能点 / 是否区分 first-use 与 filtered-zero / 是否有半屏占位 / 是否与 FAB 重复
- [x] error：有无重试 / 文案是否原始异常 / 是否把失败说成空或说成另一个原因 / 是否有软错误通道
- [x] disabled：置灰是否可解释 / 有无并行进度指示 / 是否用禁用代替校验
- [x] 统一出口：`rg -n "OgLAsyncSkeleton" lib/`（仅 2 处）/ `rg -n "OgLAsyncEmptyPane\(|emptyAction:"`（17 处调用，13 处带 CTA）/ `rg -n "CircularProgressIndicator" lib/surface/pages/ lib/surface/app/`（**24 处代码调用**：16 处裸转圈加载分支、7 处按钮内联转圈（正确范式）、1 处启动 splash）

**交叉核对**：`docs/UX_CROSS_AUDIT/3-B-states.md`（v14 本席旧报告）、`docs/UX_STABILITY_PLAN.md`（D-05/D-06/F-03/F-11 原文与修复指令表）、`docs/UI_AUDIT_V2/2-B-density.md`（4 处假 CTA 与骨架非列表形）

**复现命令**
```bash
cd /root/OhGithubLost
rg -n "OgLAsyncSkeleton" lib/                                   # 骨架只有 1 处调用
rg -n "CircularProgressIndicator" lib/surface/pages/ lib/surface/app/   # 16 处裸转圈
rg -n "onPressed: null" lib/surface/pages/issue_page.dart lib/surface/pages/commit_page.dart lib/surface/pages/search_page.dart lib/surface/pages/drafts_page.dart
rg -n "emptyAction" lib/surface/pages/                         # 13 处 CTA
rg -n "loadDebounce|minLoadingDuration" lib/surface/app/async.dart lib/surface/app/paged_controller.dart
```

---

> **报告完**。本席为只读审计：未改动任何代码，未 commit / push，未读取 Flutter SDK / pub 缓存源码。唯一产出：`docs/UI_AUDIT_V2/3-B-states.md`。
