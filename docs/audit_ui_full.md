# UI 全面审查（语义 / 动效 / 操作逻辑 / 屏幕尺寸 / 输入方式适配）

仓库 HEAD `e32cd53`（v12.6.7 已发布）。**只读专项，未修改任何源码 / i18n / 配置**；本报告是本次唯一写入。
方法：完整阅读 `theme.dart`、`app/motion.dart`、`app/animations.dart`、`app/client_shell.dart`、`app/back_guard.dart`、`app/refresh_indicator.dart`、`app/async.dart`（状态切换段）、`app/og_l_app.dart`、`platform/window_capability.dart`；抽查全部 27 个 pages 的关键字段（手势、时长、字号、断点、tooltip、mounted、dispose）；运行 `tool/motion_audit.py`、`tool/ui_audit.py`、`tool/i18n_scan.py` 三个 CI 门禁取基线。严重级别：P1（桌面端核心输入不可用 / 功能不可达）> P2（明显缺陷，可用但有损）> P3（打磨项）。

每条发现给出：文件:行号 → 证据 → 三端影响（📱手机 / 📲平板 / 🖥桌面）。

---

## 一、输入方式适配（桌面 / 键盘 / 鼠标）

### IN-01 · 全应用零键盘快捷键（P1 · 🖥桌面）
**位置**：`rg "Shortcuts\(|CallbackShortcuts|LogicalKeyboardKey|SingleActivator|HardwareKeyboard" lib/` → **0 命中**（全库唯一相关 `FocusNode` 在 `widgets/code_editor_field.dart`）。
**证据**：整个 `lib/surface` 没有任何 `Shortcuts` / `Actions` / `Shortcuts` widget 或按键监听；代码编辑器（`pages/code_editor_page.dart`）没有 Ctrl+S 保存、Ctrl+F 查找（查找面板 `OgLCodeFindPanel` 只能点工具栏按钮 `code_editor_toolbar.dart:120-157` 打开）；Esc 不能关闭弹窗之外的查找面板；全应用无 Ctrl+R 刷新等。
**后果**：桌面端一切操作只能靠鼠标逐个点按钮；对一个含全功能代码编辑器的 GitHub 客户端，Ctrl+S / Ctrl+F / Esc 是桌面用户的肌肉记忆，缺失是最典型的"移动端套壳"信号。
**三端影响**：🖥 高（核心缺陷）；📲 中（外接键盘同样失效）；📱 无。

### IN-02 · 列表行 / 卡片动作仅靠长按，桌面端不可发现（P2 · 🖥/📲）
**位置**：
- `pages/search_page.dart:218` — 发现页仓库卡片 `onLongPress: onActions`，且该卡片**没有任何可见的 ⋯ 按钮**，动作面板唯一入口是长按；
- `pages/release_detail_page.dart:549` — 附件 `onLongPress: _showAssetActions`（`trailing` 是 info 图标，点它走详情不走动作）。
**证据**：Flutter 的 `GestureDetector.onLongPress` 对鼠标按住不放同样触发（功能上不死），但桌面用户没有"长按"的使用习惯，也无任何提示文案；发现页结果卡片无替代入口。
**对照**：`pages/issue_page.dart:838-845` 评论操作就做得对——长按之外还有可见 `IconButton(more_horiz, tooltip: commentMenu)` 双入口。
**后果**：发现页"收藏 / 复制链接 / 取消星标"等动作在桌面端事实不可达（不可发现=不可用）；附件快捷下载同样。
**三端影响**：🖥 高；📲 低（触屏用户习惯长按，但仍偏隐）；📱 低。

### IN-03 · RefreshIndicator 在桌面端无替代刷新入口（P2 · 🖥）
**位置**：`app/refresh_indicator.dart:40-47`（全仓唯一下拉刷新入口，用于 `repo_page.dart:798`、`search_page.dart:756/842`、`gists_page.dart:150`、`profile_page.dart:233`、`drafts_page.dart:215`、`dashboard_page.dart:447`、`action_run_page.dart:572`）。
**证据**：缓解项——`app/og_l_app.dart:210-222` 的 `OgLScrollBehavior` 把 `mouse/trackpad` 加入 `dragDevices`，所以鼠标拖拽理论上能拉出刷新；但这依赖用户"按住列表拖"，桌面惯例是滚轮滚动，滚轮在列表顶部**不会**触发刷新。仓库 / 仪表盘 / 通知四个一级页的 AppBar 均无刷新按钮（`rg "Icons.refresh"` 仅命中 `download_manager_page.dart:489`、`action_run_page.dart:622`、`action_log_page.dart:318` 三处二级页）。
**后果**：桌面端想刷新仓库列表，唯一可靠方式是切走再切回 tab 或重进页面。
**三端影响**：🖥 中高；📲 无；📱 无。**建议**：`OgLScrollBehavior` 已是全局行为收敛点，刷新按钮也可在 `OgLApp` 层统一（如 AppBar actions 约定），不必逐页加。

### IN-04 · 代码编辑器右键菜单依赖 Mobile 工具栏控制器，桌面右键存疑（P2 · 🖥，需真机验证）
**位置**：`widgets/code_editor_field.dart:529` — `late final SelectionToolbarController _toolbar = MobileSelectionToolbarController(builder: _selectionMenu);`；`:607-609` 注释明言 "`CodeEditor` 没有 `contextMenuBuilder`，不传 toolbarController 就完全没有菜单"。
**证据**：`re_editor` 的 `CodeEditor` 不走 Flutter 标准 `EditableText`，因此标准 TextField 在桌面端自带的**右键 SelectionContextMenu** 在这里不生效；菜单完全由 `MobileSelectionToolbarController` 驱动（选择/长按锚点式）。本报告环境无法运行桌面端验证右键是否触发，标记待议。
**后果**：若右键不触发，桌面编辑器只能靠 Ctrl+C/V 系统剪贴板兜底（编辑器自身复制/剪切/粘贴按钮均无）。
**三端影响**：🖥 中；📲 无（长按菜单已修通，见文件头注释）；📱 无。

### IN-05 · hover 反馈：依赖 InkWll 默认实现，无自定义但达标（OK · 🖥）
**位置**：全库 `MouseRegion|onEnter|hoverColor` 自定义 → 0 处；但列表行 / 卡片 / 设置行均为 `ListTile` / `InkWell` / `Card+InkWell`（如 `search_page.dart:212-218`、`repo_page.dart:612-616`），Material 默认提供桌面 hover 高亮，且 `theme.dart` 的 `cardTheme`/`listTileTheme` 不禁用 `hoverColor`。
**结论**：不构成缺陷；唯一注意点是 `search_page.dart:1095` 附近的 `Semantics`+自定义 tap 层若未来脱离 InkWell 需补 `MouseRegion(cursor: SystemMouseCursors.click)`。当前通过。
**三端影响**：🖥 / 📲 / 📱 均无（✅）。

### IN-06 · Tooltip 共 65 处，触屏可达性达标（OK · 📱）
**位置**：`rg "tooltip:"` → 65 处，集中在 AppBar 按钮（`repo_page.dart:537/542`）、编辑器工具栏（`code_editor_toolbar.dart:120-157` 全部带 i18n tooltip）。
**结论**：Flutter `Tooltip` 默认长按（touch）即显示，触屏可达；文案全走 `_t`（i18n_scan 验证 0 待本地化）。✅
**三端影响**：均无。

### IN-07 · 焦点遍历与 Enter 行为：未做任何定制，大体合理但表单缺提交键（P3 · 🖥/📲）
**位置**：`pages/login_page.dart:324`（token 框 `onSubmitted → _login`，✅）、`pages/search_page.dart:1333-1340`（`textInputAction: search` + onSubmitted，✅）、`pages/code_editor_page.dart:441`（查找框提交即跳转，✅）。
**证据**：`new_issue_page` / `new_release_page` / `new_repo_page` 等新建表单的文本框均无 `onSubmitted`（Enter 不能提交，也不能跳下一字段——未设 `textInputAction: next`）。`FocusNode` 全库仅编辑器 1 处，未做 Tab 顺序定制——默认自动遍历顺序与视觉顺序一致，可接受。
**后果**：桌面/外接键盘用户在新建表单里必须全程用鼠标点"发布/创建"按钮。
**三端影响**：🖥 低中；📲 低；📱 无。

### IN-08 · 平台逻辑差异分布：收敛良好（OK，附 1 个 P3）
**位置**：UI 层的平台分支只有 `app/system_notifier.dart:56`、`app/permissions.dart:128/423`（均走 `defaultTargetPlatform`）；窗口能力经 `platform/window_capability.dart` 契约 + 门面选型（`app/desktop_window.dart:40` 仅暴露 `ogLIsDesktopPlatform`），符合 QUALITY_STANDARD 第 4 条"平台差异在唯一的位置裁决"。✅
- 返回键：`app/back_guard.dart` 状态机统一（二级页→弹栈→关抽屉→回首页→双击退出），手机端语义完整；桌面端 PopScope 只拦系统 back（桌面无此输入），窗口关闭走原生按钮（`desktop_window.dart:163-175` 自绘标题栏含最小化/最大化/关闭），互不冲突。✅
- **P3**：`back_guard.dart:33` 的"再按一次退出"提示在桌面端永远不可达也不需要，逻辑无害，仅提示语义属移动端专属。
**三端影响**：均无（✅）。

---

## 二、动效（语义与分级）

### MO-01 · 三个 CI 门禁全绿（基线结论）
`python3 tool/motion_audit.py`：76 文件、白名单 2（motion.dart / animations.dart），**0 违规**——无硬编码时长、无越档 ScaleTransition/AnimatedXxx/BackdropFilter、无 Curves.linear。`tool/ui_audit.py`：0 处令牌外字面值。`tool/i18n_scan.py`：705 处中文字面量全部为"开发者日志·有意保留"，**0 处待本地化**；6 语言 × 27 分片键集合一致。✅

### MO-02 · 时长散点全部有 motion-allow 或语义豁免（OK）
抽查：`download_manager_page.dart:115`（SnackBar 8s，行内有 `motion-allow:` 注释，非动效令牌）；`search_page.dart:1175` / `action_log_page.dart:92`（防抖 300ms，等待语义）；`code_editor_page.dart:152`（草稿防抖 900ms）；`settings_page.dart:1668`（1s 提示轮转）。均非动画语义，处理正确。✅

### MO-03 · 动效"降档=降质量"贯穿到位（OK）
`motion.dart:1-30` 档位表单调（1<2<3）；`app/animations.dart:290-322` `OgLSurfaceSwitch` 低档只淡入；`app/animations.dart:357-386` `OgLSharedTitle` 低档直接返回 child（Hero 关闭但导航不丢）；`app/refresh_indicator.dart:40-47` 档位 0 只收位移不砍功能；`client_shell.dart:277-287` 隐藏 tab `TickerMode(enabled:false)` 停表省帧。全部符合 QUALITY_STANDARD 33 条。✅

### MO-04 · 三态切换动画在 Sliver 分支同样收敛（OK，前次审计遗留项已闭环）
`app/async.dart:527-545`：`OgLAsyncSliver` 空/错/载三态走 `OgLSurfaceSwitch` + ValueKey，数据态保持 `SliverList.builder` 懒加载不套动画容器（性能与动效两全）。✅

### MO-05 · P3：`settings_page.dart:196-197` 色板 `Wrap(spacing: 10, runSpacing: 10)` 用裸 10
非动效但同属"字面值"边界（ui_audit 未拦截因为 Wrap spacing 不在其规则内）；`OgLSpace` 无 10 档，最近是 sm(8)/md(12)。语义上应取 `OgLSpace.sm` 或补令牌。**三端影响**：均无（纯一致性）。

---

## 三、操作逻辑（语义）

### LG-01 · 异步世代防护已全面收敛（OK）
前次 `docs/audit_ui.md` 的 UI-01（AsyncController 世代竞态）、UI-03/05（await 后 mounted）均已修复；本次复核：`client_shell.dart:96-120` `_checkGeneration`、`repo_page.dart:209-216` 等所有 `await + _notifier/_t` 调用点均带 `if (mounted)`。✅

### LG-02 · 成功事件用 error 语义色的问题已在语义色层根治（OK，附残留记录）
`theme.dart:104-112` `OgLSemanticColors`（success/warning/info ThemeExtension）+ `notifier.dart:65-80` success/error 分色；前次 UI-06 记录的 `_ReleasesTab` 创建成功弹 warning 样式问题依前次"语气统一批次待议"结论继续保留，本次未发现新增同类。

### LG-03 · P2：`app/notifier.dart:59-62` messenger 未挂载时静默丢弃提示
```dart
if (!_messenger.mounted) { return; }
```
与 `error_surface.dart:561-566`（前次 UI-02 已修为 requeueFront）不同，`OgLNotifier._show` 在 messenger 不 mounted 时**直接丢**，无放回队列 / 无日志留痕，违反 15 条"静默降级是最严重的缺陷"。实际窗口极窄（shell 未挂载前几乎不会调 notifier），但"绝不静默"标准下应至少 `OgLAppLog.instance.add(...)` 留痕或 requeue。
**三端影响**：三端一致，低概率高危后果（丢失的是操作结果提示）。建议随下次错误通道批次统一。

### LG-04 · 资源对称性抽查通过（OK）
`search_page.dart:421-426`（tab/scroll/feed/issues 四项 dispose）、`repo_page.dart:963-967/2668-2670/3134-3138` 等 8 个 State 的控制器全部成对；`code_editor_page.dart:133-146` timer cancel + 按 `_savedText/_abandon` 语义决定是否回写草稿（不把已提交内容残留成草稿、不救回已放弃改动，语义精确）；`settings_page.dart` 对话框控制器 dispose（前次 UI-04 修复项）复核到位。listener add/remove 计数全部配平（repo 2/2、dashboard 1/1、settings 2/2、search 1/1、code_editor 用 removeListener 显式注销）。✅

### LG-05 · P3：登录页 token 框 `onSubmitted` 在 busy 态未拦截
`login_page.dart:324-326`：`onSubmitted: (_) async { await _login(); }`——按钮在 `_busy` 时禁用，但 Enter 提交路径没有 `_busy` 闸（`_login` 内部是否有防重需进函数确认；若无则违反 26 条"写操作要么幂等要么防重"）。三端影响：🖥/📲（键盘用户）连按 Enter 可能重复提交登录。

---

## 四、屏幕尺寸适配

### SZ-01 · 断点体系唯一且三档清晰（OK）
全库尺寸分支仅 3 处：`client_shell.dart:314`（<600 底栏 / ≥600 NavigationRail）、`:350`（≥1200 Rail 展开标签）、`search_page.dart:855`（≥600 结果两列）。无散落断点。✅

### SZ-02 · 宽屏内容宽度：对话框有界，页面无界（P3 · 🖥/📲）
**位置**：`settings_page.dart:1384-1388` `_dialogWidth = min(0.9×屏宽, max)`（✅ 桌面拖宽窗口对话框不会撑满全宽）；`og_l_app.dart:159` 启动失败兜底页 `maxWidth: 640`（✅）；`action_log_page.dart:533` 日志面板 `maxHeight: 420`（✅）。
**但**：仓库列表 / 发现 / 通知 / 仪表盘等**一级列表页没有任何 maxWidth 约束**——桌面把窗口拖到 2560 宽时，列表行与卡片被拉成 2500+px 长条，一行文字读起来跨全屏，是桌面端观感最大短板。**三端影响**：🖥 高（观感）/功能无损；📲 中（分屏）；📱 无。**建议**：列表页内容包 `Center(ConstrainedBox(maxWidth: ~720))`，可在壳层统一。

### SZ-03 · 窗口 resize 稳定性（OK）
断点切换 <600↔≥600 时 `IndexedStack` 保状态、tab 页不重建（`client_shell.dart:272-289` 懒挂载 + IndexedStack）；`DefaultTabController` 重建问题在 `repo_page.dart:452-458` 有注释与防护（permissions 异步返回不会弹回第一个标签）；`repo_page.dart:695` / `dashboard_page.dart:452` 弹层高度用屏高比例、`_dialogWidth` 用屏宽比例，任意窗口尺寸不溢出。✅

### SZ-04 · 触控目标达标（OK）
`theme.dart` 全局 `minTouch 44×44 / minButton 64×44`；`repo_page.dart:629` 分支条 `minHeight: 48`；`settings_page.dart:214-216` 注释明言色板视觉 34dp 但命中区 48dp。✅

### SZ-05 · 文字缩放链路完整（OK）
`og_l_app.dart:92-101`：系统 textScaler × 用户 fontScale，夹紧 [0.85, 2.0]，且在 WidgetsApp builder 内层覆盖（注释解释了为什么不能外层包 MediaQuery）；`og_l_space.dart:8-14` 明确"间距与字号解耦"（缩放不改间距）——策略一致。侧效应：`fontSize: 12/13` 裸值（见 SZ-06）会随 TextScaler 一起放大，行为正确。✅

### SZ-06 · P3：等宽正文 `fontSize: 12/13` 裸值散布 11 处，无字号令牌
**位置**：`commit_page.dart:122/213`、`repo_page.dart:1479/1489/1962/2271/2431/2453`、`gist_detail_page.dart:190`、`new_gist_page.dart:181`、`about_page.dart:236/249/464`、`pull_page.dart:207`、`drafts_page.dart:174`、`workflow_dispatch_page.dart:505`、`settings_page.dart:2099/2253`。
`OgLRadius.dart` 有 `OgLIconSize` 但**没有 `OgLFontSize` / mono 正文字号令牌**——12 与 13 两种混用无语义（同为 mono 元数据文本，about 用 12、gist 用 13）。违反 34 条精神（视觉值取令牌）；ui_audit 未拦截说明该规则只覆盖颜色/圆角/间距。**三端影响**：均无（一致性债）。**建议**：补 `OgLFont.monoSm(12)/monoMd(13)`。

### SZ-07 · 无横竖屏专项处理（P3 · 📱/📲）
`rg "orientation|landscape"` → 0 处。手机横屏时：底栏 4 tab 变矮但可用；分支弹层 `0.6×屏高` 在横屏 = 约 200px，列表过挤但可滚动。无溢出风险（无固定高度列表）。记为打磨项，非缺陷。

---

## 五、总体结论

| 维度 | 结论 |
|---|---|
| 动效 | **优**。档位表 + CI 门禁双保险，三个门禁全绿，未发现任何越档 |
| 语义/i18n | **优**。0 待本地化、语义色 ThemeExtension、6 语言键集一致 |
| 生命周期/逻辑 | **良**。仅 notifier.dart 静默丢弃（LG-03）与登录 Enter 防重（LG-05）两个小口子 |
| 屏幕尺寸 | **良**。断点唯一、对话框有界、触控/字号缩放达标；一级列表页缺 maxWidth（SZ-02） |
| 输入方式适配 | **最大短板**。桌面端零快捷键（IN-01，P1）、长按唯一入口不可发现（IN-02）、下拉刷新无桌面替代（IN-03）、编辑器右键待验证（IN-04） |

**P1（1 项）**：IN-01。
**P2（3 项）**：IN-02、IN-03、LG-03（IN-04 标记待议，需桌面真机验证右键）。
**P3（6 项）**：IN-07、MO-05、LG-05（并入 IN-01 快捷键批次）、SZ-02、SZ-06、SZ-07。

建议修复批次：① 桌面快捷键骨架（`Shortcuts`+`Actions` 挂在 `OgLApp` 层，先 Ctrl+S/Ctrl+F/Esc，动作经 surface bridge 下发）；② 动作入口双通道（发现页卡片补可见 ⋯ 按钮，对齐 issue_page 模式）；③ 一级列表页 maxWidth 约束（壳层统一）；④ notifier 静默丢弃补留痕/requeue。
