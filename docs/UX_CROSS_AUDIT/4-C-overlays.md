# 4-C · 弹层一致性审计（SnackBar / Dialog / BottomSheet）

> 批 4 · C 席 · 2026-11-22 · 只读审计，未改任何代码
> 范围：三类弹层的**视觉与出口一致性**（操作闭环时序归 4-A，本席不重复）
> 方法：rg 全库统计 + 逐调用点阅读。数据：showSnackBar 直调 3 处（notifier 之外）、
> showDialog 直调 0 处（全部收口 ogLShowDialog ✅）、showModalBottomSheet 直调 1 处、
> ogLShowSheet 8 处、ogLShowDialog 42+ 处、ogLConfirmDiscardChanges 7 页复用 ✅。

## 一、用户可感知问题（按严重度）

### 严重

**C-01 · 删除类确认框的危险色不统一——一半是普通 FilledButton，一半才是红色**
- 证据：`lib/surface/pages/gist_detail_page.dart:257-262`（删除 gist 用 `FilledButton.styleFrom(backgroundColor: scheme.error)` ✅）；对比 `lib/surface/pages/issue_page.dart:477-480`（删除评论）、`lib/surface/pages/repo_tags_page.dart:139-146`（删除标签）、`lib/surface/pages/profile_page.dart:150-155`（移除账号）——同是**不可逆删除**，确认按钮全是普通主题色 FilledButton，视觉上与「fork」这种可逆操作毫无区别。
- 用户感受：删错东西的风险被 UI 掩盖，危险感不稳定。
- 修复：抽一个 `ogLDangerConfirm(BuildContext, {title, body, actionText})` 进 `lib/surface/app/overlays.dart`，统一「TextButton 取消 + error 底 FilledButton 确认」结构，替换上述 3+ 处手写 AlertDialog。

**C-02 · success / info / warning 三种语气在 SnackBar 上只差一个内容文字色，warning 只给黑底白字**
- 证据：`lib/surface/app/notifier.dart:74-90`——`success()` 与 `info()` 完全同样式（同一 `_show`，无区分）；`warning()` 仅 `backgroundColor: scheme.error`。而 `lib/surface/pages/download_manager_page.dart:80-116` 自建了一套 queued/success/warning 三色 SnackBar（tertiary/onErrorContainer 等），规格与 notifier 不一致（还带 8s 时长 + action）。
- 用户感受：所有提示长得一样，成功和失败靠读字分辨；下载页提示又是另一套样式，同屏出现时像两个 App。
- 修复：notifier._show 里 success 用 `scheme.primary` 容器色 + 左侧 check 图标、warning 加 error 图标（M3 SnackBar 支持 leading icon）；把 download_manager 的通知改为经 OgLNotifier 扩展（如 `OgLNotifier.notice(kind, msg, action:)`），颜色映射只留一处。

**C-03 · search_page 直调 showModalBottomSheet，绕过统一出口——无拖拽把手、无档位定速**
- 证据：`lib/surface/pages/search_page.dart:937`（推荐卡长按菜单）对比 `lib/surface/pages/issue_page.dart:379`（评论长按菜单走 ogLShowSheet）。同一个仓库里「长按弹出操作菜单」这一模式出现两种实现：search 版没有 drag handle、动画时长不走动效档位、也没包 SafeArea(top:false) 的统一规矩。
- 用户感受：同为长按菜单，一个有把手一个没有，弹出速度肉眼可感地不同——不稳定。
- 修复：`search_page.dart:937` 改为 `ogLShowSheet<String>(context: context, builder: …)`（默认 showDragHandle: true），删除直调。

### 中

**C-04 · error_surface.dart 直调 showSnackBar 且无严重度视觉**
- 证据：`lib/surface/app/error_surface.dart:572-580` `_presentAmbient` 直接 `messenger.showSnackBar`，无 backgroundColor / 无 isError——通知中心明确有 `OgLNoticeSeverity.warning`（572 行上游可见），横幅却一律中性灰。对比 `notifier.dart:86` warning 是 error 红底。
- 用户感受：同一类"写回失败/权限不足"，有的页面弹红色、有的弹灰色，严重度语言缺失。
- 修复：`error_surface.dart:572` 按 `notice.severity` 映射：critical/warning → error 底（复用 notifier 的样式），info → 默认。

**C-05 · download_manager 自设 8s 时长 + `hideCurrentSnackBar` 强拆，与全局 4s 默认冲突**
- 证据：`lib/surface/pages/download_manager_page.dart:106`（`messenger.hideCurrentSnackBar`）与 `:110`（`duration: 8s`）。任何页面刚弹的提示会被下载通知瞬间顶掉；反之 8s 驻留遮后续提示。
- 用户感受：提示互相打架，正在读的一条突然消失。
- 修复：时长与抢占逻辑并入统一出口（C-02 的扩展方法带 `duration`/`replace` 参数，全局只有一处定义）；业务默认 8s 仅限带 action 的提示。

**C-06 · 危险 Sheet 动作（删除入口）无 danger 视觉**
- 证据：`lib/surface/pages/issue_page.dart:400-403`——评论 Sheet 里「删除」ListTile 用默认样式；M3 惯例危险动作用 `Icons.delete_outline` + error 色 title。
- 用户感受：菜单里删除和编辑一样无害，误触后才见确认框。
- 修复：issue_page.dart:401-403 给该 ListTile 加 `iconColor: Theme.of(sheetContext).colorScheme.error`、`textStyle: titleMedium.copyWith(color: error)`；repo_page 1977 起的 Sheet 删除项同查同改。

**C-07 · 高度策略不统一：0.6 / 0.8 / 未限高并存，且无共享常量**
- 证据：`lib/surface/pages/code_editor_page.dart:373`（0.8）、`lib/surface/pages/repo_page.dart:701`（0.6）、issue_page 两处 Sheet（379/615）未限高仅靠 isScrollControlled:false 兜底。overlays.dart 头注释承认「分支 60%、预览 80%」是手工约定。
- 用户感受：不同面板弹出高度随手感漂，无稳定预期。
- 修复：overlays.dart 增 `OgLSheetHeight.compact/full`（0.6/0.85），调用点改用常量；矮面板保持默认。

**C-08 · repo_page 5 处 FAB 与 floating SnackBar 的堆叠未验证，`floating` margin horizontal 16 与 FAB 安全区可能重叠**
- 证据：`lib/surface/pages/repo_page.dart`（5 个 FAB）+ `notifier.dart:88-89`（margin horizontal 16）。floating SnackBar 默认让位 FAB，但自定义 margin 覆盖了 Scaffold 的 inset 计算——FAB 页面上 SnackBar 可能盖住 FAB 顶缘。
- 用户感受：提示出现时主操作按钮被压住/遮挡。
- 修复：验证 repo_page/gists_page/dashboard_page（FAB 页）实机表现；若重叠，把 margin 改为 `EdgeInsets.fromLTRB(16,12,16,12) + MediaQuery.padding` 保留 FAB 让位，或改用 `ScaffoldMessenger` 默认行为。

**C-09 · ogLConfirmDiscardChanges 的「放弃修改」是数据丢失操作，确认按钮却是普通 FilledButton（非 danger）**
- 证据：`lib/surface/app/overlays.dart:88-111`——7 个编辑页共用，但确认钮是主题色 FilledButton；与 C-01 同根。
- 修复：并入 C-01 的 ogLDangerConfirm；discarded 动作文案已明确（✅ 好实践），只差视觉。

### 轻

**C-10 · notifier.success/info 无图标区分，黑暗模式下 warning 的 onError 文字与默认文字对比策略不写死**
- 证据：`notifier.dart:74-79`（isError 才设 TextStyle，success/info 走主题 contentTextStyle，inverseSurface 底上 onSurface 色在暗色主题下对比度偏弱——theme.dart snackBarTheme 暗色取 `surfaceContainerHighest`+`onSurface`，非 inverse 配对）。
- 修复：theme.dart snackBarTheme 暗色改为 `inverseSurface`/`onInverseSurface` 配对（与亮色一致），消除暗色下灰底灰字。

**C-11 · token_exit_warning 用 Dialog 承载全屏警示卡，却与普通 AlertDialog 共用 ogLShowDialog（barrierDismissible:false 是唯一差异）**
- 证据：`lib/surface/app/token_exit_warning.dart:118-130`。errorContainer 底色、不可点遮罩——语义接近"关键拦截"，但视觉仍是普通对话框，无 danger 图标位。
- 修复：给它加 error 图标 + 确认钮 danger 化（同 C-01 组件），保持 barrierDismissible:false。

**C-12 · issue_page 三处"保存草稿/发布"确认（211/273/305/424）结构重复手写，未抽公共 confirm**
- 证据：issue_page.dart 4 处 AlertDialog 均 TextButton+FilledButton 手写。与 repo_page 12+ 处确认框合计 16+ 份重复结构。
- 修复：overlays.dart 增 `ogLConfirm(context, {title, body, confirmText, danger: false})`，一次替换。

**C-13 · clipboard_x.dart 文档示例仍在教调用方直调 showSnackBar**
- 证据：`lib/surface/util/clipboard_x.dart:20-23` dartdoc 示例。虽是注释，但会固化错误模式。
- 修复：示例改为 `OgLNotifier.of(context).warning(...)`。

**C-14 · Sheet 内 SafeArea 处理不一致**
- 证据：issue_page.dart:378 `SafeArea(top: false)` ✅；search_page.dart:938 全包 `SafeArea`（顶部也避开，但 useSafeArea 缺省 true 时双重避让）→ 长按菜单顶部多一条空隙；repo_page.dart:1279/1977 需逐个确认底部收控件是否都包了。
- 修复：search_page 改走 ogLShowSheet 后删手写 SafeArea；对 repo_page 两处矮面板补 `SafeArea(top:false)`。

**C-15 · release_detail_page 两处 Sheet（312/373）isScrollControlled:true 但未见限高，可能满屏**
- 证据：release_detail_page.dart:315/376。与 C-07 同根：限高策略无约束。
- 修复：并入 C-07 的 OgLSheetHeight 常量。

**C-16 · repo_page.dart:354 fork 确认与 1441/1601/1696/1779/2698/3260 等确认框：非危险操作也全用 FilledButton，与危险操作无差别（正向问题：确认层级未分级）**
- 修复：ogLConfirm 增加 `danger` 参数后，fork 等"可逆/低风险"操作用 `FilledButton.tonal`，与删除类拉开层级。

## 二、跨席边界（写明，不重复计）

- SnackBar 出现**时序**（await 后 mounted、hideCurrent 的时机竞争）→ 4-A 已覆盖，本席只报样式/出口。
- SnackBar 遮 FAB 的**布局测量**属批 1-A 范畴，C-08 仅报一致性风险。

## 三、检查清单（查过 & 未发现问题）

- ✅ showDialog 直调：**0 处**，全部经 ogLShowDialog（出口统一做得好）。
- ✅ ogLConfirmDiscardChanges：7 个编辑页全复用，文案按钮语义明确。
- ✅ ogLShowSheet 的动效定速（animations.dart:105 → motion.dart 档位表）：8 处调用一致。
- ✅ theme.dart:246-256 bottomSheetTheme：把手颜色/圆角/elevation 0 统一。
- ✅ theme.dart snackBarTheme（floating + 统一 margin）：规格出处唯一（但被 C-02/C-04/C-05 三处旁路削弱）。
- ✅ notifier.dart 的 mounted 双保险 + 日志留痕（★LG-03）：不静默。
- ✅ token_exit_warning 用 errorContainer 而非字面色。
- 已查未列入（无问题）：workflow_dispatch_page、action_run_page、notifications_page、drafts_page、onboarding_page、gist_detail_page 的确认框结构、settings_group.dart:77 弹层出口。

## 四、修复优先级（供收口 UX_STABILITY_PLAN）

1. C-01+C-09+C-12（一个 ogLConfirm/ogLDangerConfirm 组件解决三席问题）
2. C-02+C-04+C-05（SnackBar 严重度视觉收口到 notifier 一处）
3. C-03（search_page 出口回归）
4. C-06/C-07/C-08/C-15（Sheet 危险色、高度常量、FAB 堆叠实测）
