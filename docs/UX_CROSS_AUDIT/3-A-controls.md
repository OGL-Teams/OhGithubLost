# 批 3-A · 控件变体正确性审计（全 30 页）

> 文档戳：2026-11-22 · 席位 3-A（控件与状态 · 控件变体正确性）
> 依据：material-3 SKILL.md Components 节、sota-frontend-design rules/03-design-systems-components.md、UX_CROSS_AUDIT_BRIEF.md（含双轴补强）
> 方法：rg 全量统计 lib/surface/pages/ 下 FilledButton / OutlinedButton / TextButton / IconButton / Chip 系 / Switch / Slider / Dropdown / PopupMenu / FAB 的分布（见文末清单），逐点核对话境。只读未改代码。
> 结论：变体体系整体有纪律（危险确认已统一 error 底、FAB 收敛于 5 个列表页、AppBar 次要操作收 PopupMenu），但存在 **危险确认 dialog 两种写法并存、新建类主操作权重三级分裂、重试按钮三种变体混用** 三个系统性问题。

## 一、问题清单（严重 / 中 / 轻）

### 严重

**S1. 危险操作确认 dialog 的确认按钮两种写法并存（一半带 error 色、一半纯 primary）**
「删除」类确认框共 9 处，其中 5 处正确用了 error 底（drafts_page.dart:102-107、release_detail_page.dart:199-204、gist_detail_page.dart:256-261、repo_page.dart:4518-4523、repo_page.dart:4221-4226 附近 file/accel 删除），但 **4 处用普通 primary FilledButton**：
- issue_page.dart:476-480 — 删除评论确认（`_deleteComment`），FilledButton 无 error 色
- repo_tags_page.dart:144-148 — 删除 Tag 确认（`_delete`），同上
- profile_page.dart:151-155 — 移除账号确认（清本机令牌+全部缓存），同上
- notifications_page.dart:153-157 — 清空全部日志确认（`_confirmReset`），同上
用户感受：同样是「不可逆删除」，有的框确认键是红色、有的和「保存」「关闭」长得一模一样——不稳定、粗粝。
修复：抽一个 `OglDestructiveConfirmDialog`（或 `ogLShowDestructiveConfirm`），统一 `FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError)`；将上述 4 处改为调用该 helper。

**S2. 「新建/提交」主操作的视觉权重三级分裂**
同为创建类主操作，三种不同控件：
- new_issue_page.dart:176 — 表单内 FilledButton（正确，最重）
- new_gist_page.dart:147 — **AppBar TextButton**（最轻，主操作被降级为文字链）
- workflow_dispatch_page.dart:415 — **AppBar TextButton**（触发 workflow 是写操作，同样最轻）
用户感受：三个「要填表单、要提交」的页面，一个主按钮在最下、两个是右上角一行小字——主次权重颠倒，工具不稳。
修复：new_gist_page.dart:147 与 workflow_dispatch_page.dart:415 的 TextButton 改为 AppBar 内 `FilledButton.tonalIcon`（参照 code_editor_page.dart:595 的 AppBar 内保存按钮做法，带 compact visualDensity），或将提交按钮下沉到表单底部用 FilledButton（与 new_issue 对齐）。二选一并全库统一。

**S3. 重试/加载更多按钮三种变体混用（同类操作不同控件）**
- repo_tags_page.dart:201 — 失败重试用 **FilledButton**（最高权重）
- search_page.dart:805 — 失败重试用 **FilledButton.tonal**
- repo_page.dart:819 — 加载更多用 **OutlinedButton**
- dashboard_page.dart:129-136 / search_page.dart:368-375 — 滚动自动加载，无按钮
用户感受：同样是「网络失败了点一下重试」，有的页是实心大按钮、有的页是浅色次按钮；粗粝且权重语义混乱。
修复：规定「失败重试 = FilledButton.tonal（OgLAsyncErrorPane 已有默认，见 lib/surface/app/async.dart）」；repo_tags_page.dart:201 改为调用 OgLAsyncErrorPane 或 FilledButton.tonal；repo_page.dart:819 的 OutlinedButton 改为 OutlinedButton 保留（加载更多属次要操作，权重正确），但需在 3-A 收口确认 errorPane 重试与手写重试收敛为一处。

### 中

**M4. close/reopen/lock 等有后果的写操作确认框用纯 primary FilledButton，无分级**
issue_page.dart:351（lock/unlock）、issue_page.dart:519（close/reopen）——关闭议题、锁定议题都是对外可见的强操作，确认键与「保存」同款。M3 惯例：可逆/中性写操作可用 primary，但 **close 这类不可静默撤销的对外操作建议至少 OutlinedButton + error 前景色或 warning 提示行**。修复：issue_page.dart:519 确认键改 `FilledButton`（保留）但内容区补「关闭后订阅者仍会收到通知」已有关闭提示文案——若已有则仅统一 S1 helper 的非破坏分支即可；至少要和 S1 的 helper 合并为一个 confirm 入口，避免 9+ 个手写 AlertDialog 各自漂移。

**M5. drafts_page.dart:181-196 查看草稿 dialog 三按钮权重错排**
按钮顺序 `TextButton(复制)` → `FilledButton.tonal(去编辑器)` → `FilledButton(删除草稿)`：删除用最高权重的实心 primary 且无 error 色（真正的删除确认在下一个 dialog 才出现）。用户感受：最危险的「删除」长得最像主操作。修复：drafts_page.dart:189-195 删除按钮降级为 TextButton（前景 error 色），把 FilledButton 权重让给「去编辑器」（这是该 dialog 的真正主操作）。

**M6. login_page.dart:385 密码框 suffixIcon IconButton 每帧新建无语义差异**
核对为可见性切换 IconButton，tooltip 存在（383 行附近已注释说明）；但搜索框/下拉等同页风格一致性——login OAuth 按钮用 OutlinedButton.icon（468）正确。此项转轻，见 L14。（复核项，降级）

**M7. FAB 语义不齐：5 个列表页有 FAB、同类「新建」入口页面缺位**
有 FAB：gists_page.dart:137、dashboard_page.dart:405、repo_page.dart:2749/3055/3305（issues/PR/tag 等）。缺位：repo_tags_page（新建 tag 走 dialog，仅 IconButton 触发，248 行）、issue 列表详情内新建入口走 repo_page FAB（可接受）。用户感受：同为「列表 + 新建」，Gists 有大按钮、Tags 只有列表行尾小图标——入口可见性分裂。修复：repo_tags_page 增加 `FloatingActionButton.extended`（onPressed 打开现有 `_showCreateDialog`），保持 M3「新建类主操作统一 FAB」的项目自述（repo_page.dart:11）。

**M8. ChoiceChip / FilterChip 语义基本正确但档位控件三处三型**
- repo_page.dart:3588 ChoiceChip（单选筛选，正确）
- search_page.dart:826/1011 FilterChip 横滑行（多选/单选筛选，正确）
- notifications_page.dart:196、dashboard_page.dart:416、search_page.dart:1330、repo_page.dart:2760/2889 SegmentedButton（tab 切换，正确）
问题在 search_page.dart 内部：tab 2 用 SegmentedButton（1330）而同页 Issues tab 用 FilterChip（1011），注释自己承认「窄屏临界溢出」——同页同类筛选两种控件。修复：search_page.dart:1330 仓库/代码 tab 的分类档位与 1011 统一为 OgLIssuesFilterChips。

**M9. repo_page.dart:4466-4475 Pages 启用/禁用按钮并排且权重颠倒**
`FilledButton.tonal(启用默认分支)` 与 `OutlinedButton(禁用)` 并排 Wrap——「禁用 Pages」与「启用」是同级的互斥写操作，却一实一空；且 4489 `_saveCname` 也是 tonal。用户感受：设置区按钮权重随机分配。修复：本区统一——当前状态为启用时主按钮显示「禁用」用 FilledButton.tonal（危险降级 OutlinedButton），未启用时显示「启用」tonal；即按状态互斥渲染单按钮，而不是两个永远同时在场。

**M10. DropdownButtonFormField 在 repo_page.dart:4391 未配 labelText，只有裸边框**
对比 workflow_dispatch_page.dart:564 同控件带 labelText + helperText。用户感受：同一表单控件一个有标签一个没有，粗糙。修复：repo_page.dart:4391 decoration 补 `labelText: _t('defaultBranch')`（或现有分支标题文案）。

**M11. legal_text_page.dart:142 裸 DropdownButton 嵌在富文本流中**
非表单语境用裸 DropdownButton（无边框、无 label），与全库 DropdownButtonFormField（Outline 风格）不一致。用户感受：设置/法务页里一个悬浮小箭头，控件无接地感。修复：改 DropdownButtonFormField + OutlineInputBorder + label，或改 MenuItemButton/MenuAnchor（M3 推荐）。

**M12. action_run_page.dart:636 取消运行用 OutlinedButton.icon，但重跑用 FilledButton.tonalIcon**
「取消一个正在运行的 workflow run」比「重跑」更具破坏性，权重却更低。修复：running 分支的取消按钮改 `FilledButton.tonalIcon` + error 前景 icon（或 OutlinedButton + error 色），使破坏性一眼可辨；重跑保持 tonal。

### 轻

**L13. IconButton 密度分布健康，但 repo_page.dart:544/549 AppBar 双 IconButton + PopupMenuButton(554) 结构需核对 48dp**——544/549 tooltip 均存在（抽查通过），列此处仅为清单证明已查。无修复。

**L14. login_page.dart:409 登录主按钮 FilledButton + busy 内嵌 spinner，宽度稳定性核对通过**；唯一缺口：OAuth 分支（468）在 `_busy` 时同步禁用，双按钮 loading 态一致。无修复，仅记录。

**L15. onboarding_page.dart:281 「上一步」TextButton 与 383 权限请求 FilledButton.tonal 并存**——向导页主推进按钮（下一步）在哪一步用了什么变体需统一：下一步=FilledButton、上一步=TextButton 是正确层级，已查合规。无修复。

**L16. download_manager_page.dart:240 撤销 Snackbar 内 TextButton**——正确（Snackbar 动作规范即 TextButton）。无修复。

**L17. SwitchListTile 全库 8 处（workflow_dispatch 580、new_gist 188、new_repo 165、new_release 197/205、release_detail 112/118、issue_page 994 CheckboxListTile）均带 title(+subtitle)，无裸 Switch**——已查合规。settings_page 609/1035 用封装 OgLSettingsSliderRow（widgets/settings/settings_group.dart），Slider 值展示一致性由批 3-C 复核。无修复。

**L18. ActionChip / InputChip 全库 0 使用**——当前语义无「触发动作的 chip」需求，合规；若未来加「@用户 chip」记得用 InputChip 而非 FilterChip。无修复。

**L19. gist_detail_page.dart:389 「在浏览器打开」用 TextButton.icon，而 release_detail/issue 的外链用 IconButton（release_detail_page.dart:464-474）**——外链出口两型并存。修复：正文流内外链统一 TextButton.icon（行内语义），AppBar/行尾外链统一 IconButton；按此规则核 3 处即可，属低优先。

**L20. code_editor_page.dart:595-609 AppBar 内 FilledButton.tonalIcon 双色态切换（dirty→primaryContainer / clean→surfaceContainerHighest）**——变体语义正确且有注释自述，是全库最佳实践样板；建议作为 S2 修复的参照实现。无修复。

## 二、修复指令汇总（按优先序）

1. 新建 `lib/surface/widgets/ogl_destructive_confirm.dart`（或 app/dialogs.dart 内 helper）：`ogLShowDestructiveConfirm(context, {title, body, confirmLabel})`，确认键固定 `FilledButton + error/onError`；替换 S1 的 4 处 + M4/M5 合并调用点，消灭 9 处手写 AlertDialog 的漂移。
2. new_gist_page.dart:147、workflow_dispatch_page.dart:415：AppBar TextButton → FilledButton.tonalIcon（参照 code_editor_page.dart:595），或统一下沉表单底 FilledButton；二选一后全库新建/提交入口一致。
3. repo_tags_page.dart:201 重试按钮改 OgLAsyncErrorPane / FilledButton.tonal，与 search_page.dart:805、async.dart 默认统一。
4. drafts_page.dart:189-195：删除按钮降为 TextButton(error 前景)，FilledButton 让给「去编辑器」。
5. repo_tags_page.dart 增 FloatingActionButton.extended 打开新建 tag dialog（对齐 repo_page.dart:11 自述）。
6. search_page.dart:1330 分类档位改 OgLIssuesFilterChips，与 1011 统一。
7. repo_page.dart:4466-4475 Pages 区按状态互斥渲染单一主按钮；4489 保存 CNAME 保持 tonal。
8. repo_page.dart:4391 DropdownButtonFormField 补 labelText；legal_text_page.dart:142 改 DropdownButtonFormField。
9. action_run_page.dart:636 取消按钮加 error 语义。

## 三、检查清单（已查项，含未发现问题的）

- **统计口径**：FilledButton(直构) pages 内 0 处、FilledButton.icon 4 处 3 文件、FilledButton.tonal(.tonalIcon) 17 处 7 文件、OutlinedButton 10 处 7 文件、TextButton 63 处 16 文件、IconButton 52 处 19 文件、FAB 7 处 3 文件、FilterChip 7 处 1 文件、ChoiceChip 1 处 1 文件、ActionChip/InputChip 0、SwitchListTile 8 处、CheckboxListTile 2 处、裸 Switch/Slider/Checkbox pages 内 0（Slider 经 OgLSettingsSliderRow 封装）、DropdownButton/Form 3 处 3 文件、PopupMenuButton 4 处 1 文件、SegmentedButton 8 处 4 文件。
- 已查无问题：危险色使用（OgLSemanticColors 通路）、Chip 语义（筛选=Filter/Choice，无 Action 误用）、SegmentedButton 均用于 tab 档、Snackbar 动作统一 TextButton、AppBar 次要收 PopupMenu（repo_page 554/2288/3332）、FAB 集中于列表页、SwitchListTile 全带标题。
- 未覆盖（移交 3-B/3-C）：disabled 视觉一致性、TextField label/错误呈现、键盘交互。

## 四、页面矩阵（30 页独立小节；✗=有问题编号）

1. repo_page — ✗ S3(819)、M9(4466-4489)、M10(4391)；✓ dangerZone error 底(4519)、FAB×3、PopupMenu 收纳、ChoiceChip(3588)、删除文件/加速通道确认 error 底(3271/3940/3999)
2. issue_page — ✗ S1(476)、M4(351/519)；✓ 编辑/标签/指派 dialog 规范(950-1082)、CheckboxListTile(994)
3. new_issue_page — ✓ FilledButton 主操作(176)，正确样板
4. new_gist_page — ✗ S2(147)；✓ SwitchListTile(188)
5. new_repo_page — ✓ SwitchListTile(165)、FilledButton(199)
6. new_release_page — ✓ SwitchListTile×2(197/205)、FilledButton(239)
7. gists_page — ✓ FAB.extended(137)、AsyncView 三态
8. gist_detail_page — ✓ 删除确认 error 底(256)；✗ L19(389 外链型)
9. release_detail_page — ✓ 删除确认 error 底(199)、AppBar IconButton 组(464-474)
10. file_preview_page — ✓ FilledButton.icon(406)/OutlinedButton.icon(412) 分级正确
11. code_editor_page — ✓ tonalIcon 双色态保存(595-609)，样板；TextButton(498)
12. search_page — ✗ S3(805)、M8(1330 vs 1011)；✓ FilterChip 横滑、SegmentedButton tab
13. dashboard_page — ✓ FAB(405)、SegmentedButton(416)、滚动自动加载
14. notifications_page — ✗ S1(153-157)；✓ SegmentedButton(196)、IconButton 组带 tooltip
15. login_page — ✓ FilledButton 主登录(409)+busy spinner、OAuth OutlinedButton.icon(468)、guide IconButton 带 tooltip(331)
16. onboarding_page — ✓ 向导层级 TextButton(281)/FilledButton(160 附近 dialog、383)
17. profile_page — ✗ S1(151-155 移除账号)；✓ dangerZone 分区(325 附近)、OutlinedButton 退出登录(331，可逆操作权重正确)
18. settings_page — ✓ IconButton(1610)、CheckboxListTile(1844)、OgLSettingsSliderRow(609/1035)
19. settings_section_page — ✓ 未发现按钮/变体问题（已查 IconButton/TextButton 0 处，走 ListTile 惯例）
20. about_page — ✓ IconButton(139) 带 tooltip
21. legal_text_page — ✗ M11(142 裸 DropdownButton)
22. network_page — ✓ 已查：无按钮类问题（rg 0 命中，纯展示/开关由 settings 系封装）
23. repo_tags_page — ✗ S1(144-148)、S3(201)、M7(缺 FAB)；✓ 删除 IconButton 带 tooltip(248-251)
24. download_manager_page — ✓ Snackbar TextButton 撤销(240)、errorContainer 语义(89)
25. drafts_page — ✗ M5(189-195)；✓ 删除确认 error 底(102)
26. workflow_dispatch_page — ✗ S2(415)；✓ DropdownButtonFormField 带 label(564)、SwitchListTile(580)
27. action_log_page — ✓ IconButton×4 均带 tooltip(294-317)
28. action_run_page — ✗ M12(636)；✓ rerun tonalIcon(620/629)、外链 TextButton.icon(642)
29. commit_page — ✓ 已查：rg 0 按钮命中，操作经 AppBar/封装，无变体问题
30. pull_page — ✓ 已查：rg 0 按钮直构命中，评论操作走 sheet 惯例（与 issue_page 同型）；变体问题随 issue_page 修复联动

## 五、双轴说明
- 轴一（启动链路）：归 5-A；本席仅核对 login/onboarding 控件变体（见 §四 15/16）。
- 轴二（页面矩阵）：30/30 页全覆盖，每页独立小节见上；无问题页均已列「已查项」。

## 六、跨席移交
- 3-B：disabled 态视觉（M9/M12 的 onPressed:null 路径）、loading 三态。
- 3-C：OgLSettingsSliderRow 的 Slider 数值呈现、TextField label 完整性（M10 关联）。
- 收口：S1/S2/S3 建议进「稳定性优先」P0 组（危险语义 + 主操作权重是「工具不稳重」的直接来源）。
