# 批 3 · C 席 —— 输入与表单审计（登录 / 新建四页 / dispatch / 编辑器 / 搜索 / 设置）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 3 · 控件与状态 · C（输入与表单）**
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `f684160`（2026-11-21 16:27:57 +0800）
> - 更新时间：**2026-11-22（Asia/Shanghai）**
> - 审计对象：全库 47 处 `TextField`（`rg -n "TextField\(" lib/surface`），重点页
>   `login_page` / `new_issue_page` / `new_gist_page` / `new_repo_page` / `new_release_page`
>   / `workflow_dispatch_page` / `code_editor_page` + `code_editor_field` / `search_page`
>   / `settings_page`（含 dialog 内输入）/ `issue_page`（评论与编辑弹层）/ `repo_page`
>   （分支、新文件、设置、重命名弹层）/ `release_detail_page` / `repo_tags_page`
>   / `gist_detail_page` / `action_log_page` + `log_search.dart` / `font_pick.dart`
> - 基准文档：`docs/UX_CROSS_AUDIT_BRIEF.md`（含双轴补强）、
>   `/var/minis/skills/sota-frontend-design/rules/04-ux-patterns.md` §1–§3（Forms structure /
>   input mechanics / validation & error contract）、
>   `/var/minis/skills/material-3/SKILL.md` §Form Layout + §Anti-Patterns
> - 性质：**只读审计**。未修改任何业务代码，未 commit / 未 push。
> - 复现方式：全部证据为 `file:line`，用 `rg -n "<片段>" <路径>` 可复现。

---

## 0. 结论摘要

全库 **47 个 TextField** 的规范符合度盘点（脚本逐处扫描 `labelText/hintText/errorText/helperText`）：

| 指标 | 数值 | 规范要求（rules/04 §1–§3） | 判定 |
|---|---|---|---|
| 有可见 `labelText` | **29 / 47（62%）** | 每个输入必须有可见 label，placeholder 兼 label 违规 | ✗ |
| 仅 `hintText` 兼 label | **17 处** | 「placeholder 兼 label 违规」——输入后提示消失，上下文丢失 | ✗ |
| 完全无 label 无 hint | **1 处**（gist_detail 编辑正文） | 同上 | ✗ |
| 用 `errorText` 做字段级错误 | **1 / 47（repo_page.dart:1471）** | 错误必须「字段旁 + 具体 + 可行动」，禁止只走 toast | ✗ 全库仅一处 |
| `TextFormField` / `Form` | **0** | M3 Flutter 表单标准件；无 Form 则无统一校验/焦点跳转 | ✗ |
| `keyboardType` | 5 处 | URL/数字类字段必须设 | ✗ 大量缺失 |
| `textInputAction` | **仅 1 处**（search_page.dart:1350） | 每个单行输入都应声明回车动作 | ✗ |
| `autofillHints` | **0** | 令牌字段应 `password`/`one-time-code` 语义 | ✗ |
| `maxLength` / 长度护栏提示 | **0**（仅 1 处 LengthLimiting） | 长度限制要在提交前可见 | ✗ |
| 必填标记 | **仅 workflow_dispatch（`（必选）/（可选）`后缀，workflow_dispatch_page.dart:562）** | 其余全部表单：必填无任何标记 | ✗ |

**一句话结论**：这个 app 的表单是「能提交的输入框集合」，不是表单系统——错误只在 SnackBar/整页 errorCard 里、离字段十万八千里；必填字段不告诉你必填；搜索框、字体 URL、跳转行号等 17 处输入只有会消失的 placeholder；键盘类型几乎全靠默认。用户「粗糙」的判词在表单层完全成立：**每一次校验失败，用户都要自己去猜是哪个框的问题**。

---

## 1. 用户可感知问题（严重 → 轻，含修复指令）

### 严重（直接造成输入丢失 / 误操作 / 无法完成）

**C3-C-01 · 全库错误呈现只有 1 处在字段旁，其余全部离场**
- 页面：全部表单页
- 证据：`rg -n "errorText:" lib/surface` 全库仅 `repo_page.dart:1471` 一处（新文件路径校验，反而是全库最好的一条）。对照：`new_issue_page.dart:160-171`、`new_repo_page.dart:173-186`、`new_release_page.dart:213-227`、`login_page.dart:430-448` 的错误都是**滚动内容里的一张 errorContainer Card**，渲染在出错字段下方若干屏之外；`new_gist_page.dart:117-120`、`workflow_dispatch_page.dart:334/361`、`issue_page.dart:552/562`、`settings_page.dart:1947` 更是只弹 SnackBar（`OgLNotifier.warning`，`lib/surface/app/notifier.dart:58`）——SnackBar 消失后错误信息**无处可查**。
- 用户感受：「点了创建，弹了一句红字又没了，到底哪个框错了？」——典型的**不稳定/粗糙**。
- 修复指令：把校验改为字段级。以 `new_issue_page.dart:142-159` 为例：两处 `TextField` 换 `TextFormField`（配 `GlobalKey<FormState>`），校验失败时 `setState(() => _titleError = _t('titleRequired'))` 并传 `decoration.errorText: _titleError`；提交失败的服务端错误映射回字段（422 类错误映射到 title/body），映射不了的才落底部 Card 且**保持显示不清除**。同法改 `new_repo_page.dart:146-164`、`new_release_page.dart:169-195`。参考实现就在本库：`repo_page.dart:1463-1474`（StatefulBuilder 内实时 errorText）。

**C3-C-02 · 必填字段零标记：必填靠猜**
- 页面：new_issue / new_gist / new_repo / new_release / workflow_dispatch ref / repo_tags / 分支创建 / 新文件
- 证据：`new_issue_page.dart:146`（「标题」必填）与 `:155`（正文可选）的 label **长得一模一样**；`assets/i18n/zh/new_issue_page.json:2` 有「正文（可选，支持 Markdown）」但 `:8`「标题」无任何标记；`new_repo_page.dart:150`「仓库名」必填无标记（`:160` 描述有「（可选）」）；`repo_tags_page.dart:297/302`（tagName/targetSha）双必填双无标记；workflow_dispatch 是全库唯一做对的：`workflow_dispatch_page.dart:562` + `assets/i18n/zh/workflow_dispatch_page.json:13/18` 的`（必选）/（可选）`后缀。
- 用户感受：「到底哪个必须填？点创建才知道」——先撞墙再看提示，rules/04 §1 明确反对。
- 修复指令：统一用 workflow_dispatch 已有的后缀机制。给各页 label 加必填标记（如 zh 文案 `titleLabel: "标题（必填）"`），或更好：抽一个 `OgLRequiredLabel` helper，在 label 后附 M3 语义的 `*`+Semantics（`labelText: '标题 *'`，语义标签注明"必填"）。范围：new_issue/new_repo/new_release/repo_tags/issue_page:932/仓库分支弹层 repo_page.dart:3177。

**C3-C-03 · 字段校验时机错：错误在提交后才第一次出现，且纠错后不即时消失**
- 页面：new_issue（`new_issue_page.dart:88-93` 提交时才查 title 空）、new_gist（`new_gist_page.dart:87-95` 提交时 SnackBar）、new_repo（`new_repo_page.dart:91-94`）、new_release（`new_release_page.dart:107-110`）、workflow_dispatch（`workflow_dispatch_page.dart:321-340` 提交时统一抛）
- 用户感受：填完才发现「标题不能为空」，回去补填后**错误卡还在屏上**（`_error` 只在下次 `_submit` 开头清空，输入过程中不清）——`onChanged` 未联动错误清除。
- 修复指令：按 rules/04 §3「reward early, punish late」：必填字段加 `onChanged` → 该字段已有错误时即时重校验并清除（`if (_titleError != null && _title.text.trim().isNotEmpty) setState(() => _titleError = null)`）；字段失焦（`Focus` onKeyEvent 或 `onSubmitted`）时做首次校验。对齐参照：`repo_page.dart:1466` 的 `onChanged: (_) => setLocal((){})` 已示范了即时校验的写法，全库推广。

**C3-C-04 · 提交防重各页自造、且 AppBar 与 body 双入口不同闸**
- 页面：new_gist / workflow_dispatch / issue_page 评论
- 证据：`new_gist_page.dart:146-152` AppBar 里 `TextButton(onPressed: _busy ? null : _submit)`——**AppBar 的「创建」连按无 handler 级闸**（`_submit` 开头没有 `if (_busy) return`，对比 `new_issue_page.dart:81-83`、`login_page.dart:74-77` 都有）；`workflow_dispatch_page.dart:406-410` 同样是 AppBar TextButton + `_submit` 内 `_busy` 检查在**校验之后**（:336）——连按两下时两次都会通过校验段。
- 用户感受：连点两下 → 两个重复 Gist / 两次 workflow 触发（后者触发 CI 重跑，代价真实）。
- 修复指令：`_submit()` 第一行统一 `if (_busy) return;`（new_gist_page.dart:86 前、workflow_dispatch_page.dart:320 前各加一行）；有 UI 闸的页（issue/repo/release/login 已做）保持不变。

**C3-C-05 · 键盘类型全库近乎裸奔：URL / 数字 / 令牌字段都是默认全键盘**
- 证据：`rg -n "keyboardType" lib/surface` 仅 5 处。缺口：
  - `settings_page.dart:835-839`（字体 URL 输入）有 `keyboardType: url` ✓——但**同页** `font_pick.dart:32-36`（字体本地路径）无；
  - `code_editor_page.dart:434-445`（跳转行号）有 number+digitsOnly ✓——但**同弹层**的确认按钮仍可提交越界行号（`code_editor_page.dart:462` 才 `clamp`，输入 99999 静默跳到最后一行，无任何提示「行号超出范围 1-1200」）；
  - `repo_page.dart:3848-3852` `_promptText` 有 keyboardType 参数——但 `settings_page.dart:1176-1185` DNS IP 输入用 `TextInputType.text`（应 `numberWithOptions(signed:true)` 或至少 url）；`repo_tags_page.dart:300-303` targetSha（40 位 hex）无 `autocorrect:false` + 单行键盘，会触发输入法自动纠错与联想；
  - `login_page.dart:375-407` 令牌输入 `autocorrect: false` ✓ 但无 `enableSuggestions:false`、无 `autofillHints`（密码管理器无法识别这是一枚凭据字段；rules/04 §2 autocomplete 是 WCAG 1.3.5 AA 要求的映射物，Flutter 对应物即 `autofillHints: [AutofillHints.password]`）。
- 修复指令：逐处补齐——`font_pick.dart:33` 加 `keyboardType: TextInputType.url`（或 `textInputAction: done`）；`settings_page.dart:1178` 改 `TextInputType.numberWithOptions()`；`repo_tags_page.dart:295/301` 两处加 `autocorrect:false, enableSuggestions:false`；`login_page.dart:378` 加 `autofillHints: const [AutofillHints.password]` 并给整个 ListView 包 `AutofillGroup`；`code_editor_page.dart:458-462` 把 clamp 改为越界时 `errorText` 提示（「第 N 行不存在，共 1200 行」）。

### 中（高频可见的粗糙）

**C3-C-06 · 搜索框 placeholder 兼 label：限定符语法无处可学**
- 页面：search_page / repo_page 分支过滤 / 文件过滤 / action_log / log_search
- 证据：`search_page.dart:1348-1358` 唯一提示是 `hintText: "关键字（支持 repo:… language:… 等限定符）"`（`assets/i18n/zh/search_page.json:30`）——输入任意字符后 hint 立即消失，限定符语法**整站唯一的教学时刻**没了；`repo_page.dart:707-716`（分支搜索）、`:2501-2510`（文件过滤）、`action_log_page.dart:329-338`、`log_search.dart:59-68` 同构。
- 用户感受：输错限定符 → 「0 结果」空态（`search_page.dart:1367` 只有 `noResults` 一行），不知道自己错在哪。
- 修复指令：搜索框改 `labelText: '搜索'`（浮动 label，输入后仍可见）+ `helperText` 常驻限定符示例（`helperText` 不随输入消失）；或搜索框右侧加一个 info 图标 IconButton 弹限定符速查表。四处搜索框统一（抽 `OgLSearchField` 组件收编 log_search.dart:59 / repo_page.dart:707/2501 / action_log_page.dart:329 / search_page.dart:1348 五份重复实现——五处连 `prefixIcon: Icon(Icons.search)` 都各写一遍）。

**C3-C-07 · new_gist 内容区无 label，仅靠上文一行小字维系**
- 证据：`new_gist_page.dart:177-190`（内容 TextField，只有 `hintText: contentHint`，label 靠 `:175` 手写 `Text(_t('content'))`）——滚动后（ListView）这行小字滚出视口，输入框悬在屏上没有任何名字；`gist_detail_page.dart:187-194` 更是**全文库唯一裸 TextField**（无 label 无 hint，只有弹窗标题「编辑 {文件名}」）。
- 用户感受：滚到内容框时不知道这是「内容」；gist 编辑弹窗里一个匿名大框。
- 修复指令：`new_gist_page.dart:184` 加 `labelText: _t('content'), alignLabelWithHint: true`（与 new_issue/new_release 的多行框一致）；`gist_detail_page.dart:193` 加 `labelText: _t('content')`（label 浮起后不占空间）。

**C3-C-08 · SnackBar 兼校验器：必填校验结果一闪即逝**
- 页面：new_gist / issue_page 评论 / workflow_dispatch
- 证据：`new_gist_page.dart:89/93`（文件名、内容为空 → `OgLNotifier.info`，SnackBar 自动消失，字段边框毫无变化）；`issue_page.dart:552`（评论为空 → info SnackBar）+ `:562`（超过 `_kMaxCommentChars` → warning SnackBar，**且 maxLength 上限对用户完全不可见**——全库 `maxLength: 0`，用户输入到 65536 字符才会被拦）；`workflow_dispatch_page.dart:325-341`（缺必选参数 / JSON 解析失败 → warning SnackBar，高级 JSON 框不标红）。
- 用户感受：「提交没反应？刚才好像弹了句什么」——SnackBar 消失后没有任何可追溯状态。
- 修复指令：三类校验全部改为字段级 `errorText`：new_gist_page.dart:166/184 加 errorText；issue_page.dart:880 评论框加 errorText + `helperText: '0 / 65536'` 计数器（Flutter 原生 `counterText`，`maxLength` + `maxLengthEnforcement: MaxLengthEnforcement.none` 达到「显示但不硬拦」）；workflow_dispatch JSON 框（workflow_dispatch_page.dart:500-513）解析失败时 `errorText` + 保持弹层打开。

**C3-C-09 · 错误消息只报「什么错了」，一半不报「怎么改」**
- 证据（好例子）：`login_page.dart` 用的 `tokenShapeInvalid`（`assets/i18n/zh/login.json:34`「令牌格式不对（应以 ghp_、gho_… 开头）」）——三要素齐全 ✓；`repo_page.dart:1463-1471` pathError 即时具体 ✓。
- 证据（坏例子）：`assets/i18n/zh/new_issue_page.json:9`「请先填写标题」没有下一步；`new_gist_page.json:12`「内容不能为空」；`createFailed: "创建失败：{error}"`（new_issue/new_gist/new_repo/new_release 四页同款）直接把 `error.toString()` 灌进 UI——用户看到的是 API 原文而非可行动指引。
- 修复指令：zh 文案补全三要素——`titleRequired: "标题不能为空，请填写 1-256 字标题"`；`createFailed` 拆分支：401 → 「令牌已失效，请到设置重新登录」、403 → 「没有该仓库的写权限」、422 → 「GitHub 拒绝了内容：{error}」（错误映射见 C3-C-01）。

**C3-C-10 · 对话框内的表单：验证后置、错误后对话框直接关闭吞输入**
- 页面：settings 加速通道
- 证据：`settings_page.dart:1907-1947`（通道名 + URL 两字段）——点击「添加」→ 弹层 `pop(true)` **关闭** → `:1943` 才校验 URL → 失败仅 `_notifier.warning(error)`，**用户已填的通道名一并丢失**，要重开弹窗重输两栏。对比本库自己已经修过同类问题并在注释里写了教训：`repo_page.dart:1450-1453`「校验后置会导致关框才发现非法 → content 已 dispose → 用户多行输入全丢」——同一错误在 settings_page 复发。
- 用户感受：填了名字和一个手滑打错的 URL → 全部重来。
- 修复指令：仿 `repo_page.dart:1448-1523` 的 StatefulBuilder 模式：校验移入 dialog builder 内（`onChanged: setLocal`），`error != null` 时 URL 字段 `errorText` + 「添加」按钮保持可点但 pop 前先拦；或至少校验失败时不 pop、把错误文本显示在弹层内。

**C3-C-11 · 字段宽度语义缺失：宽屏下全部拉满 + 无内容语义宽度**
- 证据：全库表单没有任何 `maxWidth`/字段级宽度约束（`rg -n "maxWidth" lib/surface/pages` 仅 settings 色板与 dialog 限宽，无表单用）；`client_shell.dart:325-331` 一级页限宽 720，但**表单页全是二级 route push**（`repo_page.dart:2685/3018/3504`、`gists_page.dart:113`、`dashboard_page.dart:339`）不在 shell 限宽内——桌面上「新建议题」的标题框可以从 0 拉到 2560dp；反方向：`repo_tags_page.dart:297/302` 的 targetSha（固定 40 hex）与 tag 名都是全宽，语义宽度应为 ~44ch / ~24ch。
- 用户感受：桌面端「一行输入框横贯整个显示器」＝工具感崩塌；rules/04 §1「input width signals expected content」。
- 修复指令：表单页 body 统一包 `Center(ConstrainedBox(maxWidth: OgLWindowWidths.contentMax /* 720 */))`（token 已有：`lib/surface/util/og_l_window_widths.dart:11`，client_shell.dart:329 已示范用法）；逐字段给语义宽度：targetSha `SizedBox(width: 320)`、DNS IP `width: 160`、行号跳转 `width: 120`。

**C3-C-12 · settings 字体 URL 弹窗：hint 兼 label + 无校验反馈路径**
- 证据：`settings_page.dart:835-839`（`hintText: 'https://…'` 无 labelText）；`font_pick.dart:32-36`（路径输入同样 hint 兼 label）；校验错误走 `throw StateError('仅支持 .ttf / .otf 字体文件')`（`font_pick.dart:59-64`）→ 调用方 `_notifier.warning`（settings_page.dart:868）——SnackBar，输入框无 errorText，弹窗已关。
- 修复指令：两处加 `labelText: '字体链接' / '字体路径'`；扩展名校验前移到弹窗内（提交前 `errorText: '仅支持 .ttf / .otf'`）。

**C3-C-13 · workflow_dispatch 的 ref 与 JSON 高级框：hint 兼 label + 无错误锚点**
- 证据：`workflow_dispatch_page.dart:469-475`（ref 框只有 `hintText: 'main'`，section 标题 `:465` 是普通 Text，滚走即失名）；`:500-513`（JSON 框 hint 兼 label）；解析错误显示在**页面顶部表单区**（`:541-549` _formError Card），与底部高级框相隔多屏——用户在 JSON 框输入错误，红字出现在视线外。
- 修复指令：ref 框加 `labelText: _t('refLabel')`；JSON 框加 `labelText: _t('advanced')` + 解析失败时用独立的 `_inputsError` errorText（而非顶部共享 _formError）；_formError 只保留「工作流 YAML 无法读取」这类页面级错误。

**C3-C-14 · 登录页错误块非字段级，但更糟：两套错误（_error / _oauthError）分居两处、视觉语言不一**
- 证据：`login_page.dart:430-448`（PAT 错误 → errorContainer Card 整段长文）vs `:521-531`（OAuth 错误 → 裸 `Text(color: error)` 一行灰底都没有）；同一页面两种错误形态；且 PAT 错误 Card 里塞了 `errorDetail`（zh/login.json:2 `{error}\n（详细原因见应用日志…）`）把原始异常长文直接铺进 Card——登录页首屏被一段 stacktrace 级文本撑开。
- 用户感受：失败一次，页面下半截变成日志查看器。
- 修复指令：统一为字段级 `InputDecoration.errorText`（简短版：`verifyFailedShort: "验证失败：{reason}"`）；原始异常收进「查看详情」ExpansionTile（默认收起）；OAuth 错误块套同一个 errorContainer Card 样式（抽 `OgLErrorCard(message, {detail})` 组件，两处复用）。

**C3-C-15 · OAuth 设备码卡片：userCode 无「复制」按钮，8 位码靠手抄**
- 证据：`login_page.dart:486-505`——`verificationUri` 与 `userCode` 都是 `SelectableText`（长按选择→复制，移动端 4 步操作），device flow 的标准动作「复制代码」没有一键按钮；用户在浏览器授权页要回 app 抄 8 位码。
- 修复指令：userCode 行加 trailing IconButton（`Icons.copy`，`Clipboard.setData` + 成功 SnackBar「已复制」），`verificationUri` 同款；两行代码即可，复用 `lib/surface/util/clipboard_x.dart` 已有工具。

**C3-C-16 · 提交按钮进行中态宽度跳变 + label 换文案造成按钮抖动**
- 证据：`login_page.dart:409-425`（busy 时 Row[spinner 16px + gap + "验证中…"]，空闲时纯「登录」——按钮宽度随态跳）；`new_issue_page.dart:176-179`、`new_release_page.dart:242-245`、`new_repo_page.dart:199-202`（`_busy ? '提交中…' : '创建议题'` 文案变长 → FilledButton 宽度跳变，整行按钮跳一下）。rules/04 §4「width locked」明确要求 pending 态锁宽。
- 修复指令：给提交按钮包固定宽容器（`SizedBox(width: 200, child: ...)`）或 Spinner+label 用 `Stack` 叠加替换而非换文案；最简：文案改等长（「登录中」对「登录」）+ spinner 用 `AnimatedSize` 包裹避免跳变。

**C3-C-17 · 编辑器查找/替换条：输入框 border:none 无边界，placeholder 兼 label**
- 证据：`code_editor_field.dart:781-791`（find 框 `border: InputBorder.none` + hintText）与 `:839-849`（replace 框同款）——在 surfaceContainer 工具条内输入框**完全没有边界**，视觉上是一个裸文本区，与页面其它输入框（全库统一 OutlineInputBorder）语言断裂；激活态/焦点态无从辨认。
- 修复指令：改 `border: OutlineInputBorder(borderRadius: OgLRadius.md)`（与全库一致）或最低限 `isDense + filled: true + fillColor: surfaceContainerHighest` 给出可点区域边界。

**C3-C-18 · repo_tags 新建标签弹窗：无 border 声明继承全局、必填无标记、无校验**
- 证据：`repo_tags_page.dart:294-303` 两处 `InputDecoration(labelText: …)` 无 `border:`（依赖主题默认，行为 OK 但与本库「显式 OutlineInputBorder」惯例不一致）；SHA 为空/格式错直接发请求，错误走外层 SnackBar；tag 名重复也只有服务端报错。
- 修复指令：加显式 `border: OutlineInputBorder()`；提交前本地校验 `[0-9a-f]{40}`，失败 `errorText: "SHA 应为 40 位十六进制"`。

**C3-C-19 · 表单单列结构：新建议题/发布正文 `maxLines` 固定但 minLines 缺失，多行框初始塌缩**
- 证据：`new_issue_page.dart:152`（`maxLines: 8` 无 minLines → 初始 1 行高，正文框与标题框几乎等高，看不出「这里要写长文」）；对照 `new_gist_page.dart:178`（`minLines: 8, maxLines: 20` ✓）和 `issue_page.dart:878-879`（`minLines: 3` ✓）——**同一 app 三种写法**。
- 用户感受：新建议题页看起来像「两行输入框」，正文区被压缩感知，输入到第 2 行开始整体撑高、下方按钮跳动（布局跳变=不稳定感）。
- 修复指令：`new_issue_page.dart:152` 加 `minLines: 6`；`new_release_page.dart:189`（maxLines: 6）加 `minLines: 5`；统一惯例 `minLines: N, maxLines: M`。

**C3-C-20 · SwitchListTile 在「提交型表单」里使用：开关语义说谎**
- 证据：`new_gist_page.dart:192-196`（公开开关，立即生效式 SwitchListTile ✓ 正确）；但 `new_release_page.dart:203-213`（draft/prerelease 两个 SwitchListTile）语义是**提交时才生效**——rules/04 §2b「On/off applied on submit → Checkbox；switch inside a form that needs Save is a lie」。用户拖开关瞬间以为已生效（尤其 draft 开关：以为「已存草稿」）。
- 修复指令：两处 SwitchListTile 改 CheckboxListTile（视觉即「随表单提交的选项」），或保留 Switch 但 subtitle 明示「将随本次提交生效」（zh/new_release_page.json 的 draftDesc/prereleaseDesc 补充说明）——推荐前者，与 `new_repo_page.dart:163-168` 私有开关（同为提交生效）一起统一改 CheckboxListTile。

---

## 2. 逐表单字段清单与规范符合度（量化）

| 表单 | 字段（file:line） | 可见 label | 必填标记 | 字段级错误 | 键盘/action | 判定 |
|---|---|---|---|---|---|---|
| 登录·令牌 | login_page.dart:375 | ✓ | ✗ | 部分（页内 Card，非 errorText） | autocorrect✓ autofillHints✗ | C-01/05/14 |
| 登录·OAuth 区 | login_page.dart:468 | n/a（按钮） | — | 两套错误形态（C-14） | — | C-14/15 |
| 新建议题·标题 | new_issue_page.dart:142 | ✓ | ✗ | ✗（Card） | 未设 action | C-01/02/03/19 |
| 新建议题·正文 | :151 | ✓「（可选）」 | —（可选已标✓） | ✗ | ✗ | C-19 |
| 新建 Gist·描述 | new_gist_page.dart:158 | ✓「（可选）」 | — | ✗（SnackBar） | ✗ | C-01/08 |
| 新建 Gist·文件名 | :166 | ✓（含说明性长 label） | ✗ | ✗（SnackBar） | ✗ | C-08 |
| 新建 Gist·内容 | :177 | ✗（hint 兼） | ✗ | ✗ | ✗ | C-07/08 |
| 新建仓库·名称 | new_repo_page.dart:146 | ✓ | ✗ | ✗（Card） | ✗ | C-01/02 |
| 新建仓库·描述 | :156 | ✓「（可选）」 | — | ✗ | ✗ | C-01 |
| 新建发布·tag | new_release_page.dart:169 | ✓ | ✗ | ✗（Card） | ✗ | C-02 |
| 新建发布·标题 | :179 | ✓「（可选）」 | — | ✗ | ✗ | C-01 |
| 新建发布·说明 | :187 | ✓ | — | ✗ | ✗ | C-19/20 |
| 发布·draft/prerelease | :203/:210 | Switch | — | — | — | C-20 |
| dispatch·ref | workflow_dispatch_page.dart:469 | ✗（hint） | ✗（提交时 SnackBar） | ✗ | ✗ | C-13 |
| dispatch·参数表单 | :563-604 | ✓（含必选/可选后缀——全库唯一） | ✓ | ✗（提交时 SnackBar） | number✓ 其余✗ | 相对最佳 |
| dispatch·高级 JSON | :500 | ✗（hint） | — | ✗（错误显示在页顶） | ✗ | C-13 |
| 搜索框 | search_page.dart:1348 | ✗（hint） | — | — | search action✓ | C-06 |
| 分支过滤 | repo_page.dart:707 | ✗（hint） | — | — | ✗ | C-06 |
| 文件过滤 | repo_page.dart:2501 | ✗（hint） | — | — | ✗ | C-06 |
| 日志过滤 | action_log_page.dart:329 / log_search.dart:59 | ✗（hint） | — | — | ✗ | C-06 |
| 评论框 | issue_page.dart:877 | ✗（hint） | ✗（SnackBar） | ✗ | ✗ | C-08 |
| 编辑议题弹层·标题/正文 | issue_page.dart:929/937 | ✓ | ✗ | ✗ | ✗ | C-02 |
| 指派人弹层 | issue_page.dart:1037 | ✗（hint） | — | ✗ | ✗ | C-06 同类 |
| 编辑评论弹层 | issue_page.dart:1068 | ✗（hint） | — | ✗ | ✗ | C-07 同类 |
| 新文件·路径 | repo_page.dart:1463 | ✓ | ✓（helperText） | ✓ errorText（**全库唯一**） | ✗ | ✓ 标杆 |
| 新文件·内容 | repo_page.dart:1479 | ✓「（必填）」 | ✓ | 部分（canCreate 拦） | ✗ | ✓ |
| 重命名文件 | repo_page.dart:1783 | ✓ | ✗ | ✗ | ✗ | C-02 |
| 新建分支 | repo_page.dart:3177 | ✓ | ✗ | ✗（SnackBar） | ✗ | C-02 |
| 分支重命名 | repo_page.dart:3224 | ✓ | — | ✗ | ✗ | C-02 |
| 仓库设置·名称 | repo_page.dart:4280 | ✓ | — | ✗ | ✗ | C-01 |
| Pages·CNAME | repo_page.dart:4478 | ✓ | — | ✗ | ✗ | C-02/11 |
| 行号跳转 | code_editor_page.dart:434 | ✗（hint） | — | ✗（静默 clamp） | number✓ | C-05 |
| 编辑器查找/替换 | code_editor_field.dart:781/839 | ✗（hint+无边框） | — | — | ✗ | C-17 |
| Gist 编辑正文 | gist_detail_page.dart:187 | ✗✗（全裸） | — | ✗ | ✗ | C-07 最差 |
| 新建标签 | repo_tags_page.dart:294/300 | ✓ | ✗ | ✗ | ✗ | C-18 |
| 编辑发布 | release_detail_page.dart:86/94/102 | ✓ | ✗ | ✗ | ✗ | C-02 |
| 设置·字体 URL | settings_page.dart:835 | ✗（hint） | — | ✗（弹层外 SnackBar） | url✓ | C-12/10 |
| 设置·DNS IP/DoH | settings_page.dart:1176/1186 | ✓ | — | ✗ | IP 用 text 键盘 ✗ | C-05 |
| 设置·加速通道 | settings_page.dart:1907/1916 | ✓ | ✗ | ✗（弹层关后 SnackBar，吞输入） | ✗ | C-10 最差 |
| 字体路径 | font_pick.dart:32 | ✗（hint） | — | ✗ | ✗ | C-05/12 |
| 设置滑杆（fontScale/codeFontSize） | settings_group.dart:433 | ✓（title+label 气泡+semantics） | — | — | divisions✓ | ✓ |

**汇总**：47 字段中「完整符合」仅 3 处（repo_page.dart:1463/1479 新文件、workflow_dispatch 参数表单、settings 滑杆）；1 处全裸（gist_detail.dart:187）；**label 缺失 18 处（38%）**；**必填标记仅 2 个页面覆盖**。

---

## 3. 检查清单（已查项 / 未发现问题的部分）

已逐页覆盖（对应双轴·页面矩阵的输入域）：
- **login_page**：令牌框（label✓/遮蔽切换 tooltip✓/防重✓/错误即时清除✓）、OAuth Web→Device 回落、设备码卡（选中文本✓/复制按钮✗→C-15）、错误两套形态✗、四步 phase 提示（verifying→verify→promote→vault，文案完备✓）。
- **new_issue / new_gist / new_repo / new_release**：结构（单列✓、间距 OgLSpace 一致✓）、脏检查离开确认（PopScope 四页齐备✓，new_gist_page.dart:63-77 等——这是全库亮点）、提交防重（✗ 缺口见 C-04）、错误呈现✗、必填标记✗、minLines 不一致✗。
- **workflow_dispatch**：YAML 解析参数化表单（设计好✓）、代次防过期✓、必选/可选后缀✓（全库唯一）、ref/JSON 两处 hint 兼 label✗、错误锚点错位✗。
- **code_editor_page + code_editor_field**：行号跳转（number 键盘✓/越界静默✗）、查找替换（功能全✓/无边框✗）、脏态「●未保存」标记✓、900ms 防抖草稿自动保存✓（code_editor_page.dart:153，符合 rules/04 §5b）、保存按钮防重✓（:254）。
- **search_page**：300ms 防抖✓（:1191-1200）、textInputAction.search✓（全库唯一）、空态含查询回显✓（noResults {query}）、hint 兼 label✗、结果加载中态✓。
- **settings_page + settings_group**：滑杆组件（草稿态、MergeSemantics、onChangeEnd 落盘一次✓——亮点）、开关行统一✓、危险区卡片✓、字体 URL/路径/通道/DNS 四处输入各有缺口（C-05/10/12）、通道弹窗吞输入✗（C-10 最差单点）。
- **issue_page**：评论框（minLines✓/hint 兼 label✗/长度上限不可见✗）、编辑弹层、指派人弹层。
- **repo_page（输入相关）**：新文件弹窗（**全库标杆**：实时校验+errorText+helperText+防 dispose 注释）、分支搜索/文件过滤、分支创建/重命名、仓库设置名称/CNAME、_promptText 通用弹层（描述/主页 URL）。
- **release_detail_page**（编辑发布三字段）、**repo_tags_page**（新建标签）、**gist_detail_page**（编辑正文全裸框）。
- **action_log_page + log_search**：双搜索框 hint 兼 label、长度限制 200（LengthLimitingTextInputFormatter✓ log_search.dart:69）。
- **font_pick.dart**：路径输入、扩展名校验后置。
- **onboarding_page**：纯展示+按钮，无输入控件——确认无表单问题。
- **settings_section_page / network_page / profile_page / dashboard / gists / commit / pull / notifications / download_manager / action_run / file_preview / about / legal_text**：rg 确认无 TextField/表单控件（download_manager 的 errorText 是任务状态展示，非输入）——缺席合理。

未发现问题（保持现状）的部分： OgLSpace/OgLRadius 令牌在全部表单页使用一致；`OutlineInputBorder` 统一（code_editor_field 与 repo_tags 两处除外）；离开确认（PopScope+脏检查）四页完整；滑杆组件的语义合并是全库可访问性最佳实践。

---

## 4. 修复优先级建议（供 UX_STABILITY_PLAN 收口）

1. **立即**：C3-C-01（错误字段化——触及全部表单，单一模式复用 repo_page.dart:1463 范式）、C3-C-10（加速通道吞输入——数据丢失级）、C3-C-04（提交防重两处缺口——workflow 重跑有真实代价）。
2. **本迭代**：C3-C-02（必填标记，纯文案改动成本最低收益最高）、C3-C-06（搜索框 label+常驻 helper，五处收编成一个组件）、C3-C-09（错误文案三要素）、C3-C-11（宽屏限宽，一行 ConstrainedBox）。
3. **收尾**：C3-C-03/05/07/08/12/13/14/15/16/17/18/19/20。

> 复现锚点：`rg -n "TextField\(" lib/surface | wc -l` → 47；`rg -n "errorText:" lib/surface` → 1；`rg -n "autofillHints" lib/surface` → 0；`rg -n "textInputAction" lib/surface` → 1。
