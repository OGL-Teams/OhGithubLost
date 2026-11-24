# 批 3 · C 席 —— 表单与输入复审（v15 后真实状态）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 3 · 控件与状态 · C（表单与输入复审）**
> - 版本：**v15.0.0**（`pubspec.yaml:21` → `version: 15.0.0+150000`）
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `46981c0`（只读审计）
> - 更新时间：**2026-11-24 14:47:21（Asia/Shanghai）**
> - 审计依据：`docs/UI_AUDIT_V2_BRIEF.md`；`/var/minis/skills/sota-frontend-design/rules/04-ux-patterns.md` §1–§3/§4/§5b/§7c；`/var/minis/skills/material-3/SKILL.md` Components（Text field / Button / Switch / Checkbox / Dialog / Form Layout）。
> - 审计对象：全库 **47 处 `TextField`**（`rg -n 'TextField\(' lib | wc -l` → 47），重点页 `new_issue_page` / `new_repo_page` / `new_release_page` / `new_gist_page` / `login_page` / `workflow_dispatch_page` / `code_editor_field`，以及 `search_page` / `settings_page` / `issue_page` / `repo_page` / `repo_tags_page` / `release_detail_page` / `gist_detail_page` / `code_editor_page` / `action_log_page` / `font_pick` / `log_search` 中全部输入控件。
> - 复现方式：每条证据均为 `file:line`，用 `rg -n "<片段>" <路径>` 可复现。
> - 性质：**只读审计**。未改代码、未 commit / push；唯一产出本文。

---

## 0. 结论摘要（给决策者的一句话）

v15 修了按钮 spinner、脏检查确认、代次作废等外围，但**表单内核一处未动**：全库仍只有 1 处字段级 `errorText`、0 个 `Form`/`TextFormField`、**18/47 个输入框无可见 label（17 hint-only + 1 全裸）**、**46/47 处错误不在字段旁**、**2 处提交闸放在校验之后**、`new_gist` 的 busy 闸依然晚于两次 SnackBar 校验；设置页加速通道弹窗仍在 `.pop(true)` 后才校验 URL——**用户填好的通道名照旧被吞**。用户填表单的体验仍是「靠猜：猜哪个必填、猜哪个填错、猜刚才那句红字去哪了」。

### 量化总表（v15.0.0 实测）

| 指标 | v14 旧审计 | v15 实测 | 判定 |
|---|---|---|---|
| `TextField` 总数 | 47 | **47** | 无变化 |
| 有可见 `labelText` | 29/47 | **29/47（62%）** | 与 v14 相同，仍不合规 |
| 仅 placeholder(hint) 兼 label | 17 | **17** | ✗ rules/04 §1 明令禁止 |
| 完全无 label 无 hint（全裸） | 1 | **1**（`gist_detail_page.dart:187`） | ✗ |
| 无可见 label 合计 | 18 | **18** | ✗ |
| 字段级 `errorText` | 1 | **1**（`repo_page.dart:1472`） | ✗ 46 处错误离场 |
| `Form`/`TextFormField` | 0 | **0** | ✗ 无统一校验/焦点跳转 |
| 必填标记 | 2 页 | **2 页**（workflow_dispatch、repo 新文件内容） | ✗ 与 v14 相同 |
| `keyboardType` 显式 | 5 | **5**（`:settings 838/1181/1191`、`:code_editor_page 437`、`:workflow_dispatch 595`；`:repo_page 3871` 为 `_promptText` 参数透传） | ✗ |
| `textInputAction` | 1 | **1**（`search_page.dart:1374`） | ✗ |
| `autofillHints` | 0 | **0** | ✗ WCAG 1.3.5 AA 的 Flutter 映射缺失 |
| busy 闸在校验之后的提交入口 | 3+ | **3**（new_gist、workflow_dispatch、issue 评论） | ✗ |
| 弹窗校验后置吞输入 | 1 | **1**（settings 加速通道，原样复发） | ✗ |

---

## 1. 闭环核对（旧确证逐条判「已修/未修/修法有问题」）

| 旧编号 | 问题 | 判定 | v15 证据（file:line） |
|---|---|---|---|
| **C3-C-01** | 错误只在 SnackBar、不在字段旁 | **未修** | `rg -n 'errorText:' lib` 仍仅 `repo_page.dart:1472`；`new_issue_page.dart:158-171`/`new_repo_page.dart:171-184`/`new_release_page.dart:229-241`/`login_page.dart:430-448` 仍是离场 errorContainer Card；`new_gist_page.dart:89/93/117`、`workflow_dispatch_page.dart:323/327/332/344`、`issue_page.dart:592/600`、`settings_page.dart:1947` 仍是 SnackBar |
| **C3-C-04** | 提交防重缺口 | **未修（修法有问题）** | `new_gist_page.dart:86/93/96` busy 闸位于两次校验 SnackBar **之后**，且 `:148` AppBar 只靠 `onPressed: _busy ? null : _submit` UI 闸；`workflow_dispatch_page.dart:319-340` 闸位于 selection/ref/JSON 三段校验之后；`issue_page.dart:589-611` 同构。UI 禁用 ≠ handler 防重，校验到 setState 之间是可重入窗口 |
| **C3-C-10** | 弹窗校验后置吞输入 | **未修** | `settings_page.dart:1907-1947` 仍先 `pop(true)` → `:1943` 才 `ogLValidateAccelBaseUrl` → 失败仅 `_notifier.warning` 并 dispose 两个 controller；对照标杆 `repo_page.dart:1448-1472` 的 StatefulBuilder 实时校验仍在，未推广 |
| **F-08** | 错误呈现只有 1 处在字段旁 | **未修** | 同 C3-C-01；v15 改的是 SnackBar **语气视觉**（notifier/error_surface），不改变错误的位置与可追溯性——**修法有问题：改了提示长相，没改信息架构** |
| **F-09** | 必填零标记 + 校验时机错 | **未修** | `new_issue_page.dart:142/151`、`new_repo_page.dart:146/156`、`new_release_page.dart:169/179/187` label 文案无必填/可选区分；`new_issue_page.dart:142` 无 `onChanged` 清错；唯一例外仍是 v14 就有的 `workflow_dispatch_page.dart:565` 后缀 |
| **F-10** | new_gist / workflow AppBar 连按重复提交 | **未修** | 与 C3-C-04 同一处代码；`new_gist_page.dart:148`、`workflow_dispatch_page.dart:417` 仍是 AppBar TextButton + handler 闸后置 |

> 旧审计中**已修**的表单相关项：登录 Enter 连按防重（`login_page.dart:397`，LG-05，v15 前已修）、`issue_page` 四类 dialog 保存后原地 busy（`issue_page.dart:194/224/335`）、v15 脏检查确认四页齐备（`new_issue/new_repo/new_release/new_gist` 的 `PopScope`+`_dirty`）。但这些不是上述 6 条确证的范围。

---

## 2. v15 回归核对（任务点名的三处 + 全库统计）

### 2.1 v15 声称修过的地方，实际如何

1. **workflow_dispatch 脏检查** —— **已修且修法正确**。`workflow_dispatch_page.dart:90-96` 的 `_dirty` 已覆盖 `_ref`、`_inputs` 与 `_formText` 全部动态参数；`:100-101` `_onFieldChanged` 通过 controller listener 即时 `setState`（`:105-106` 注册、`:114` dispose 解绑），`:381-390` `PopScope(canPop: !_dirty)` + `ogLConfirmDiscardChanges`。**没有引入新问题**：代次 `_formRequestId`（`:80/188/209`）正确作废过期 YAML 响应，避免切工作流后表单错配。
2. **new_gist 防重** —— **未修好（修法有问题）**。`new_gist_page.dart:96` 确有 `if (_busy) return;`，但位置在 `:89` 文件名校验与 `:93` 内容校验**之后**：连点两下时两次 `_submit()` 都能通过空值校验、两次都看到 SnackBar，之后才分别撞 busy 闸。由于 `setState(_busy=true)` 在闸之后，真正的重复提交窗口是「校验通过 → handler 闸 → setState」之间；配合 AppBar `:148` 只有 UI 禁用闸，语义上仍不符合「handler 第一行防守」。结论：**部分修，顺序错**。
3. **settings 弹窗校验** —— **未修**。`settings_page.dart:1919` URL 字段仍是普通 `TextField` 无 `errorText`，`:1936` 直接 `pop(true)`，`:1943` 才校验，失败走 SnackBar 并 dispose 输入。与 `repo_page.dart:1448-1523` 的正确范式形成同仓对照——**v15 未把标杆推广**。

### 2.2 全库 47 个 TextField 回归数字

- **无可见 label：18 处**（17 处 hint-only + 1 处全裸），与 v14 完全相同，**没有一处是 v15 修的**。
- **错误不在字段旁：46/47**，唯一例外仍是 v14 就存在的 `repo_page.dart:1472`。
- **无有效防重：3 处**（new_gist / workflow_dispatch / issue 评论，均为「闸后置」而非完全没有闸）；其余写入口多为 UI 禁用 + handler 闸，v15 的 `439167a` 对 repo_page / issue dialog 的加固是真实改善。
- **必填标记：2 页**（workflow_dispatch + repo 新文件），其余新建/编辑表单全靠猜。

---

## 3. 新发现（P0 / P1 / P2，含症状 → 根因 → 修复指令）

### P0（数据丢失 / 用户完全无法完成）

**N-01 · settings 加速通道弹窗吞输入（旧 C3-C-10 未闭环，v15 回归确认）**
- 症状：填「通道名 + 手滑打错的 URL」→ 点添加 → 弹窗关闭 → SnackBar「地址不合法」→ 通道名和 URL 全丢，必须重开重填。
- 证据：`settings_page.dart:1910/1919`（两字段、`labelText` 有、校验反馈无）、`:1936`（`Navigator.of(dialogContext).pop(true)`）、`:1943`（`ogLValidateAccelBaseUrl(url.text)`）、`:1944-1947`（warning + dispose）。
- 根因：校验点放在对话框生命周期**之外**；弹窗一旦 pop，controller dispose，输入不可恢复。
- 修复指令：仿 `repo_page.dart:1448-1523` 把 `AlertDialog` 内容包进 `StatefulBuilder`，`onChanged: (_) => setLocal(() {})` 实时算 `ogLValidateAccelBaseUrl`，把 `error` 传给 URL 字段的 `decoration.errorText`；「添加」按钮保持可点，点后若 `error != null` 则 `return` 不 pop；成功才 `pop(true)`。

**N-02 · 提交闸后置造成 CI 重跑 / 重复 Gist 的真实窗口（旧 C3-C-04/F-10 未闭环）**
- 症状：手动触发工作流时连点「触发」，一次点击可落在校验与 busy setState 之间；CI 重跑有真实代价。new_gist 同理可产出两份 Gist。
- 证据：`workflow_dispatch_page.dart:319-340`（闸在 `:340`，校验在 `:322-338`）、`:417`（AppBar TextButton 仅 UI 禁用）；`new_gist_page.dart:86-96`（闸在 `:96`）、`:148`（AppBar）；`issue_page.dart:589-611`（闸在 `:608`）。
- 根因：用 UI 禁用代替 handler 原子闸；校验本身有 SnackBar/FormatException 分支产生 await 前的可重入点。
- 修复指令：三个 `_submit` / `_postComment` 首行统一 `if (_busy) return;`；随后再校验；保留现有 `onPressed: _busy ? null : …`。最低成本改动，6 行。

### P1（明显影响体验 / 一致性）

**N-03 · 字段级错误近乎为零：失败后用户不知道哪个框错了**
- 症状：new_issue 标题空 → 错误 Card 出现在两字段下方；new_repo 名称非法 → errorContainer 在 Switch 之后；登录失败 → 长文 Card 把页面下半截变成日志查看器；new_gist / workflow / 评论错误只闪 SnackBar，消失后无处可查。
- 证据：`new_issue_page.dart:88/158-171`、`new_repo_page.dart:90/171-184`、`new_release_page.dart:109/229-241`、`login_page.dart:430-448/521-531`、`new_gist_page.dart:89/93/117`、`workflow_dispatch_page.dart:323/327/344`、`issue_page.dart:592/600`、`settings_page.dart:1947`；全库 `errorText:` 仅 `repo_page.dart:1472`。
- 根因：从未采用 `Form` + `TextFormField`（全库 0 处），错误状态是页面级 `_error` 或全局 notifier，无法回写字段。
- 修复指令：按 `repo_page.dart:1464-1473` 范式改造五个主表单：各字段 `errorText: _xError`，页级 Card 只留服务端不可映射错误；`new_gist` 增 `_error` 改内联 Card；工作流 JSON 解析失败写回 `_inputsError` 而非顶部 `_formError`（`workflow_dispatch_page.dart:541-549`）；登录两种错误形态抽 `OgLErrorCard(message,{detail})` 归一，原始异常进默认收起的 ExpansionTile。

**N-04 · 18/47 输入框无可见 label（17 hint-only + 1 全裸）**
- 症状：输入几个字后提示消失，用户失去上下文；`gist_detail_page.dart:187` 编辑弹层里一个完全匿名的大文本框。
- 证据（17 处 hint-only）：`font_pick.dart:32`、`action_log_page.dart:329`、`code_editor_page.dart:434`、`issue_page.dart:936/1141/1175`、`new_gist_page.dart:177`、`repo_page.dart:708/2502/3867`、`search_page.dart:1373`、`settings_page.dart:838`、`workflow_dispatch_page.dart:474/505`、`code_editor_field.dart:781/839`、`log_search.dart:59`；全裸：`gist_detail_page.dart:187`。
- 根因：把 `hintText` 当 label 用，或 label 靠字段外的普通 `Text`（`new_gist_page.dart:175`、`workflow_dispatch_page.dart:471/489`）维系，滚动即失。
- 修复指令：15 处全部补 `labelText`（搜索框用「搜索」+ 常驻 `helperText` 展示限定符语法）；`gist_detail_page.dart:187` 补 `labelText: _t('content')`；`new_gist_page.dart:177` 加 `labelText: _t('content'), alignLabelWithHint: true`；`workflow_dispatch_page.dart:474/505` 加 ref / JSON label。MD3 `md-outlined-text-field label=` 是默认件，Flutter 对应 `InputDecoration.labelText`。

**N-05 · 必填标记覆盖率与 v14 相同（2 页）**
- 症状：标题、仓库名、tag、SHA 必填但 label 与可选字段长得一样，用户先撞墙后看提示。
- 证据：`new_issue_page.dart:142/151`、`new_repo_page.dart:146/156`、`new_release_page.dart:169/179/187`、`repo_tags_page.dart:282/288`、`release_detail_page.dart:87/95/103`、`issue_page.dart:936`；对照 `workflow_dispatch_page.dart:565`（`（必选）/（可选）`）与 `repo_page.dart:1481`（「内容（必填）」）。
- 修复指令：抽 `OgLRequiredLabel` 统一在 label 后缀「（必填）/（可选）」+ Semantics；或直接改 zh 文案键，成本最低、收益最高。

**N-06 · 校验时机仍然「punish late」：错误提交后首现、纠错后不消失**
- 症状：填完才被告知标题空；补填后错误 Card 仍在屏上（下一次 `_submit` 才清空）。
- 证据：`new_issue_page.dart:62-68`（listener 只 `setState` 供脏检查，不清 `_error`）、`:88/92`；`new_repo_page.dart:85-90`；`new_release_page.dart:104-109`；`new_gist_page.dart:89/93`；`workflow_dispatch_page.dart:322-334`。
- 修复指令：各必填字段 `onChanged` 中若已有对应 error 且新值合法则即时 `setState(() => _xError = null)`；失焦（`Focus.onFocusChange`）做首次校验；长表单提交失败时 `FocusScope.of(context).requestFocus(firstInvalidFocusNode)`。

**N-07 · 键盘/输入语义栈几乎全空**
- 症状：字体本地路径、DNS IP、SHA、评论、字体 URL 等全都弹默认全键盘；令牌字段无 `autofillHints`，密码管理器识别不了。
- 证据：`rg -n 'keyboardType' lib/surface` → `settings_page.dart:840`(url✓)/`:1181`(IP 用 `TextInputType.text`✗)/`:1191`(url✓)、`code_editor_page.dart:437`(number✓)、`workflow_dispatch_page.dart:595`(条件 number✓)、`repo_page.dart:3871`(参数)；`autofillHints` 全库 0；`login_page.dart:375-389` 仅 `autocorrect:false`；`repo_tags_page.dart:288` SHA 无 `autocorrect:false`/`enableSuggestions:false`。
- 修复指令：`settings_page.dart:1181` 改 `numberWithOptions()`；`font_pick.dart:32`、`:repo_tags 288` 加 `autocorrect:false, enableSuggestions:false`；`login_page.dart:375` 加 `autofillHints: const [AutofillHints.password]` 并包 `AutofillGroup`；单行输入补 `textInputAction`（全库仅 `search_page.dart:1374` 有）。

**N-08 · busy 态按钮宽度跳变（旧 C3-C-16 未闭环）**
- 症状：登录按钮空闲「登录」两字、忙时 spinner + 「验证中…」四个字，整行抖一下；新建四页文案由「创建」变「创建中」同样变宽。
- 证据：`login_page.dart:407-423`、`new_issue_page.dart:176-179`、`new_repo_page.dart:216-219`、`new_release_page.dart:257-260`、`new_gist_page.dart:146-150`。v15 `OgLBusyButton` 只落在部分写操作，没覆盖这些提交按钮。
- 修复指令：给按钮包固定宽 `SizedBox(width: 160…200)` 或 spinner 与文案 `Stack` 叠加；文案换等长版本。

**N-09 · 提交型表单里用 Switch 说谎**
- 症状：拖开「草稿」开关瞬间以为已存草稿，实际要按「发布」才生效。
- 证据：`new_release_page.dart:214/221`（draft/prerelease 两枚 SwitchListTile）、`new_repo_page.dart:163`（private）、`new_gist_page.dart:192`（public 是真即时语义，OK）。
- 修复指令：前三处改 `CheckboxListTile`，或 subtitle 明示「本次提交生效」。rules/04 §2b：on/off applied on submit → Checkbox。

**N-10 · 搜索框 hint 兼 label：限定符语法没有常驻教学点**
- 症状：输入任意字符后「支持 repo:/language:」提示消失；搜错限定符得到 0 结果却不知原因。
- 证据：`search_page.dart:1373-1379`、`repo_page.dart:708/2502`、`action_log_page.dart:329`、`log_search.dart:59`。
- 修复指令：五处收编为 `OgLSearchField`：`labelText: '搜索'` + `helperText` 常驻限定符示例；空态回显 query 并提示支持语法。

**N-11 · 多行框最小高度三种写法、布局跳变**
- 症状：新建议题正文初始只有 1 行高（看起来像两行输入框），输入后整页撑高按钮下移。
- 证据：`new_issue_page.dart:151`（`maxLines:8` 无 minLines）、`new_release_page.dart:187`（`maxLines:6` 无 minLines）、`new_gist_page.dart:177`（`minLines:8,maxLines:20` ✓）、`issue_page.dart:936`（`minLines:3` ✓）。
- 修复指令：`new_issue_page.dart:151` 加 `minLines:6`、`new_release_page.dart:187` 加 `minLines:5`。

**N-12 · 行号跳转越界静默 clamp，无提示**
- 症状：输入 99999，直接跳到最后一行，用户不知道被改了。
- 证据：`code_editor_page.dart:434-445`（number + digitsOnly 键盘 ✓）、`:462`（clamp 无提示）。
- 修复指令：越界时 `errorText: '行号超出范围 1–${total} 行'`，保持弹层打开。

**N-13 · 编辑器查找/替换条无边界、无焦点反馈**
- 症状：`code_editor_field.dart:781/839` 的 `border: InputBorder.none`，在工具条里像裸文本区，与全库 OutlineInputBorder 语言断裂。
- 修复指令：`border: OutlineInputBorder(borderRadius: OgLRadius.md)` 或 `filled:true + fillColor: surfaceContainerHighest`。

**N-14 · 新建议题/发布/标签表单无宽度语义，宽屏下拉满**
- 症状：二级 route 不在 shell 限宽内，桌面 2560dp 下标题框横贯全屏；40 位 SHA 也全宽。
- 证据：`new_issue_page.dart:139`（`ListView` 无 `ConstrainedBox`）、`new_repo_page.dart:135`、`new_release_page.dart:161`、`repo_tags_page.dart:277`；`client_shell.dart` 限宽只覆盖一级页。
- 修复指令：四个表单 body 包 `Center(ConstrainedBox(maxWidth: OgLWindowWidths.contentMax))`；`repo_tags_page.dart:288` 的 SHA 限宽 320、DNS IP 160、行号 120（rules/04 §1「input width signals expected content」）。

**N-15 · 全库表单字段间距等距、无分组节奏**
- 症状：新建发布页 tag / 标题 / 正文 / 两个开关 / 错误卡 / 按钮全部 `SizedBox(height: OgLSpace.md)` 等距；长表单（`workflow_dispatch` 多参数）没有 fieldset/legend 式分组，扫读时找不到结构。
- 证据：`new_issue_page.dart:144/149/155`、`new_release_page.dart:171/177/185/213/221/227`、`workflow_dispatch_page.dart:579-585`（每个参数统一 bottom padding，无分组）。
- 修复指令：用 section 标题 + 分组间距（`OgLSpace.lg`）区分「必填 / 可选 / 高级」，参数表单按 YAML 类型或名称前缀分组；M3 Form Layout 要求 grouped `gap:16dp` + actions 区独立 `margin-top`。

### P2（打磨）

**N-16 · OAuth 设备码无一键复制**：`login_page.dart:486-505` userCode / verificationUri 仅 `SelectableText`，移动端复制需 4 步；加 `Icons.copy` IconButton 复用 `lib/surface/util/clipboard_x.dart`。
**N-17 · 错误文案只说「什么错了」**：`assets/i18n/zh/new_issue_page.json:9`「请先填写标题」、`new_gist_page.json:12`「内容不能为空」、四页 `createFailed: "创建失败：{error}"` 直接外泄 API 原文；改为「原因 + 定位 + 下一步」三要素，401/403/422 分支文案。
**N-18 · repo_tags 新标签无本地 SHA 校验**：`repo_tags_page.dart:282/288` 标签名/targetSha 均无 `errorText`，格式错靠服务端 SnackBar；加 `[0-9a-f]{40}` 本地校验。
**N-19 · 设置字体 URL / 路径弹窗校验后置**：`settings_page.dart:838` 有 url 键盘但无 label；`font_pick.dart:32` 路径 hint-only 且扩展名校验在弹层外 `throw StateError`（`:59-64`）→ SnackBar；按 N-01 同法内移。
**N-20 · 评论长度上限不可见**：`issue_page.dart:602` 超 65536 才 warning SnackBar，`_kMaxCommentChars` 对用户输入不可见；加 `counterText`。

---

## 4. 用户满意度回答

- **填一个表单顺畅吗？** 不顺畅。四个新建页能提交，但必填靠猜（N-05）、错误在提交后才出现且纠错后不消失（N-06）、失败提示闪一下就没（N-03）、设置弹窗失败直接吞输入（N-01）——用户要「先撞墙、再猜哪个框、最后重填」。
- **知道哪个字段错了吗？** 基本不知道。47 个字段里只有 `repo_page.dart:1472` 一处把错误写在字段旁；其余 46 处错误在 SnackBar、离场 Card 或页顶，用户必须自己把红字和输入框对上号。`workflow_dispatch` 在底部 JSON 框手滑、页顶红字——跨屏更明显。
- **v15 让用户更满意了吗？** 外壳、转场、骨架和按钮 spinner 有可见改善；表单内核没有触及，用户「粗糙/没稳定感」的判词在输入场景仍成立。优先级建议：先 N-01/N-02（数据丢失+CI 代价，改动 ≤10 行），再 N-03/N-04（全库统一 label + 字段级错误模式），最后 N-05~N-15 收口。

---

## 5. 「本席对三问的回答」

1. **闭环核对**：点名的 6 条（C3-C-01 / C3-C-04 / C3-C-10 / F-08 / F-09 / F-10）**全部未修**；其中 C3-C-04/F-10 属「修法有问题」（busy 闸后置），F-08 属「修法有问题」（只改 SnackBar 视觉、没改错误位置）。表单相关旧项里真正修好的只有登录 Enter 防重与四页脏检查确认，不属于这 6 条。
2. **回归**：v15 改的 workflow_dispatch 脏检查**修好了且无新风险**；new_gist 防重**部分修、顺序错**；settings 弹窗校验**原样未修**。全库回归：47 个 TextField 中 **18 个无可见 label**（17 hint-only + 1 全裸）、**46 个错误不在字段旁**、**3 个提交入口防重闸后置**。v15 没有引入新的表单类问题，但也没有解决旧问题。
3. **新发现**：20 条（P0×2 / P1×13 / P2×5），核心是「错误无锚点 + label 缺失 + 必填无标记 + 校验时机错 + 键盘/自动填充栈空 + 弹窗吞输入 + 宽屏无语义宽度 + 长表单无分组」。详见 §3，均给出 file:line 与具体修复指令。

## 6. 已检查清单

### 6.1 重点页面逐页核对

| 页面 | 已检查项 | 结论 |
|---|---|---|
| new_issue_page | label、必填标记、错误位置、onChanged、防重、busy 文案、minLines、脏检查、间距 | label✓ 其余 ✗（N-03/05/06/08/11/15）；脏检查✓ |
| new_repo_page | 同上 + Switch 语义 | 防重闸✓（首行）；错误/必填/开关语义 ✗（N-03/05/09） |
| new_release_page | 同上 | 防重✓；错误/必填/开关/间距 ✗（N-03/05/09/15） |
| new_gist_page | 三字段、SnackBar 校验、AppBar 闸、内容 label、swtich、脏检查 | 脏检查✓、public switch✓；闸后置/错误/label ✗（N-02/03/04） |
| login_page | 令牌框、遮蔽切换、Enter 防重、错误双形态、OAuth 码复制、autofill | Enter 防重✓；错误形态/复制/autofill/宽度 ✗（N-03/07/08/16） |
| workflow_dispatch_page | 脏检查、代次作废、ref/JSON label、必选后缀、校验锚点、闸顺序 | 脏检查/代次/后缀✓；label/错误锚点/闸顺序 ✗（N-02/04） |
| code_editor_field / code_editor_page | 行号键盘/clamp、查找替换边框、草稿自动保存、保存防重 | 防重/自动保存✓；clamp/边框 ✗（N-12/13） |
| search_page | 防抖 300ms、action.search、空态 query 回显、hint 兼 label | 前三项✓；label ✗（N-10） |
| settings_page / settings_group | 字体 URL、DNS IP/DoH、加速通道弹窗、滑杆语义 | 滑杆✓；通道弹窗吞输入 P0（N-01）；IP 键盘 ✗（N-07） |
| issue_page | 评论框、四类 dialog、脏态、指派人/编辑评论输入 | dialog busy✓；评论校验/错误/label ✗（N-02/03/04） |
| repo_page | 新文件标杆、重命名、分支、仓库设置、CNAME、_promptText | 新文件 errorText 标杆✓；其余校验后置 ✗（N-18 同类） |
| repo_tags / release_detail / gist_detail / action_log / log_search / font_pick | 新建标签、编辑发布、Gist 编辑、双搜索框、字体路径 | gist_detail 全裸框、各页 hint 兼 label ✗（N-04/18/19） |

### 6.2 47 个 TextField 符合度表

> 列：label（可见 labelText）、err（字段级 errorText）、guard（该输入所属提交入口是否有 handler 首行 busy 闸）、kb（显式 keyboardType）、req（必填标记）。`—` 表示不适用（过滤/只读展示框）。

| # | 字段（file:line） | label | err | guard | kb | req | 判定 |
|---|---|---|---|---|---|---|---|
| 1 | `app/font_pick.dart:32` | ✗ hint | ✗ | ✗（弹层外校验） | ✗ | — | N-04/19 |
| 2 | `pages/action_log_page.dart:329` | ✗ hint | — | — | ✗ | — | N-10 |
| 3 | `pages/code_editor_page.dart:434` | ✗ hint | ✗ | —（clamp） | ✓number | — | N-04/12 |
| 4 | `pages/gist_detail_page.dart:187` | ✗✗ 全裸 | ✗ | ✗ | ✗ | — | N-04 最差 |
| 5 | `pages/issue_page.dart:936`（评论） | ✗ hint | ✗ | ✗（闸后置） | ✗ | ✗ | N-02/03/04 |
| 6 | `pages/issue_page.dart:1029`（编辑标题） | ✓ | ✗ | ✓dialog | ✗ | ✗ | N-05 |
| 7 | `pages/issue_page.dart:1037`（编辑正文） | ✓ | ✗ | ✓dialog | ✗ | — | 基本可用 |
| 8 | `pages/issue_page.dart:1141`（指派人） | ✗ hint | ✗ | ✓dialog | ✗ | — | N-04 |
| 9 | `pages/issue_page.dart:1175`（编辑评论） | ✗ hint | ✗ | ✓dialog | ✗ | — | N-04 |
| 10 | `pages/login_page.dart:375`（令牌） | ✓ | ✗ Card | ✓ | ✗ | — | N-03/07/08 |
| 11 | `pages/new_gist_page.dart:158`（描述） | ✓「可选」 | ✗ | ✗（闸后置） | ✗ | — | N-02/03 |
| 12 | `pages/new_gist_page.dart:166`（文件名） | ✓ | ✗ SnackBar | ✗ | ✗ | ✗ | N-02/05 |
| 13 | `pages/new_gist_page.dart:177`（内容） | ✗ hint | ✗ SnackBar | ✗ | ✗ | ✗ | N-02/04 |
| 14 | `pages/new_issue_page.dart:142`（标题） | ✓ | ✗ Card | ✓ | ✗ | ✗ | N-03/05/06 |
| 15 | `pages/new_issue_page.dart:151`（正文） | ✓「可选」 | ✗ | ✓ | ✗ | — | N-11 |
| 16 | `pages/new_release_page.dart:169`（tag） | ✓ | ✗ Card | ✓ | ✗ | ✗ | N-03/05 |
| 17 | `pages/new_release_page.dart:179`（标题） | ✓「可选」 | ✗ | ✓ | ✗ | — | 基本可用 |
| 18 | `pages/new_release_page.dart:187`（说明） | ✓ | ✗ | ✓ | ✗ | — | N-11 |
| 19 | `pages/new_repo_page.dart:146`（名称） | ✓ | ✗ Card | ✓ | ✗ | ✗ | N-03/05 |
| 20 | `pages/new_repo_page.dart:156`（描述） | ✓「可选」 | ✗ | ✓ | ✗ | — | 基本可用 |
| 21 | `pages/release_detail_page.dart:87`（tag） | ✓ | ✗ SnackBar | ✓ | ✗ | ✗ | N-05/17 |
| 22 | `pages/release_detail_page.dart:95`（标题） | ✓ | ✗ | ✓ | ✗ | — | 基本可用 |
| 23 | `pages/release_detail_page.dart:103`（正文） | ✓ | ✗ | ✓ | ✗ | — | 基本可用 |
| 24 | `pages/repo_page.dart:708`（分支过滤） | ✗ hint | — | — | ✗ | — | N-10 |
| 25 | `pages/repo_page.dart:1464`（新文件路径） | ✓ | **✓** | ✓ | ✗ | ✓helper | **全库标杆** |
| 26 | `pages/repo_page.dart:1480`（新文件内容） | ✓「必填」 | 部分 | ✓ | ✗ | ✓ | 相对最佳 |
| 27 | `pages/repo_page.dart:1784`（重命名） | ✓ | ✗ SnackBar | ✓ | ✗ | ✗ | N-05 |
| 28 | `pages/repo_page.dart:2502`（文件过滤） | ✗ hint | — | — | ✗ | — | N-10 |
| 29 | `pages/repo_page.dart:3196`（建分支） | ✓ | ✗ SnackBar | ✓ | ✗ | ✗ | N-05 |
| 30 | `pages/repo_page.dart:3243`（分支改名） | ✓ | ✗ | ✓ | ✗ | — | 基本可用 |
| 31 | `pages/repo_page.dart:3867`（_promptText） | ✗ hint | ✗ | ✓ | （参数透传） | — | N-04 |
| 32 | `pages/repo_page.dart:4319`（仓库名） | ✓ | ✗ | ✓ | ✗ | ✗ | N-05 |
| 33 | `pages/repo_page.dart:4525`（CNAME） | ✓ | ✗ | ✓ | ✗ | — | N-14 |
| 34 | `pages/repo_tags_page.dart:282`（tag 名） | ✓ | ✗ SnackBar | ✗ | ✗ | ✗ | N-05/18 |
| 35 | `pages/repo_tags_page.dart:288`（targetSha） | ✓ | ✗ SnackBar | ✗ | ✗ | ✗ | N-07/14/18 |
| 36 | `pages/search_page.dart:1373` | ✗ hint | — | — | ✗（action✓） | — | N-10 |
| 37 | `pages/settings_page.dart:838`（字体 URL） | ✗ hint | ✗ SnackBar | ✗ | ✓url | — | N-04/19 |
| 38 | `pages/settings_page.dart:1179`（DNS IP） | ✓ | ✗ | ✓ | ✗text | — | N-07 |
| 39 | `pages/settings_page.dart:1189`（DoH） | ✓ | ✗ | ✓ | ✓url | — | 基本可用 |
| 40 | `pages/settings_page.dart:1910`（通道名） | ✓ | ✗ | ✗（pop 后校验） | ✗ | ✗ | **N-01 P0** |
| 41 | `pages/settings_page.dart:1919`（通道 URL） | ✓ | ✗ SnackBar | ✗ | ✗ | ✗ | **N-01 P0** |
| 42 | `pages/workflow_dispatch_page.dart:474`（ref） | ✗ hint | ✗ SnackBar | ✗（闸后置） | ✗ | ✗ | N-02/04 |
| 43 | `pages/workflow_dispatch_page.dart:505`（高级 JSON） | ✗ hint | ✗ 页顶 Card | ✗ | ✗ | — | N-02/04 |
| 44 | `pages/workflow_dispatch_page.dart:593`（参数字段） | ✓「必选/可选」 | ✗ SnackBar | ✗（闸后置） | 条件✓ | ✓ | N-02/03 |
| 45 | `widgets/code_editor_field.dart:781`（查找） | ✗ hint+无边框 | — | — | ✗ | — | N-13 |
| 46 | `widgets/code_editor_field.dart:839`（替换） | ✗ hint+无边框 | — | — | ✗ | — | N-13 |
| 47 | `widgets/log_search.dart:59` | ✗ hint | — | — | ✗ | — | N-10 |

**汇总**：47 字段中完整符合（label + 字段错误 + 键盘语义 + 必填标记齐备）**0 处**；仅 `repo_page.dart:1464` 一处接近标杆。无 label 18（#1,2,3,4,5,8,9,13,24,28,31,36,37,40,41,45,46,47，即 17 hint-only + 1 全裸）。

### 6.3 扫描命令清单（全部可执行）

```
rg -n 'TextField\(' lib | wc -l                     # 47
rg -n 'errorText:' lib                              # 仅 repo_page.dart:1472
rg -n 'GlobalKey<FormState>|TextFormField|Form\(' lib # 0
rg -n 'labelText:' lib/surface | wc -l              # 29 字段级 label
rg -n 'hintText:' lib/surface | wc -l               # 17 处 hint-only 口径见 §6.2
rg -n 'autofillHints' lib                           # 0
rg -n 'textInputAction' lib/surface                 # 仅 search_page.dart:1375
rg -n 'keyboardType' lib/surface                    # 5 处（+1 参数透传）
rg -n 'if \(_busy\)|if \(_posting\)' lib/surface/pages # 防重闸位置
```

> **纪律声明**：全程禁用 Flutter SDK 读取（`/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存均未触碰）；只用项目自身 `lib/` 与技能规则文档；未运行 dart 编译/格式化；未修改业务代码、未 commit/push。
