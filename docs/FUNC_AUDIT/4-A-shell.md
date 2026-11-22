# 功能审计 4-A · 外壳状态机

> 文档戳：更新时间 2026-11-23 07:00:52 +0800 · v15.0.0
> 范围：`lib/surface/app/`（client_shell / og_l_app / og_l_app_bar / boot_splash / overlays / notifier / error_surface / keyboard_guard / shortcuts / animations / motion；附带核对 back_guard / desktop_window / main.dart 接线）。只读审计，未改动任何代码。

---

## P0（数据丢失 / 崩溃 / 安全）

**P0-1 认证门切换不清理导航栈与页面状态，登出/切号后页面残留旧账号数据**
- 位置：`lib/surface/app/client_shell.dart:282-291`（登录门分支）、`client_shell.dart:232-237`（页面 ValueKey）
- 症状：令牌失效（`GhAuthState.expired`）或登出后，壳只把根路由的 child 换成 `LoginPage`。用户在子路由（如 `Navigator.push` 打开的详情页、编辑器）中登出/令牌被 401 拉回登录门时：① 子路由整体被从树中摘除（`_buildShell` 提前 return），编辑器 `PopScope` 的脏表单确认与草稿回写逻辑不会走 `maybePop` 路径；② 更关键的是 `_pageFor` 的 `ValueKey('dash-${_accountId ?? 'guest'}')` 只在 `_accountId` 变化时换 key，**从已登录切到 guest 再登录另一个账号**时，`DashboardPage`/`DiscoverPage` 已挂载的 State（滚动位置、缓存列表、下载面板）不会被强制重建——懒挂载的 `_visited` 集合永不清空，旧账号会话的页面实例直接复用给新账号。
- 根因：登录门只做"显示谁"，没有 ① 在 `_accountId` 变更时重置 `_visited` 与各页 key（页面 key 依赖 `_accountId`，但 `_accountId` 由 `_check` 异步回写，登录瞬间仍是旧值，存在一帧窗口）；② 没有在进入登录门时清空根 Navigator 的历史路由（`navigatorKey.currentState!.popUntil((r) => r.isFirst)`）。
- 修复指令：在 `_check()` 的 `setState` 内比较新旧 `_accountId`，不等时 `_visited..clear()..add(OgLShellTab.home)` 并在登录门分支前调用 `OgLApp.navigatorKey.currentState?.popUntil((r) => r.isFirst)`；登录成功（`onLoggedIn: _check` 回来后 accountId 从 null → 非 null）同样走这条清理。对应文件：`client_shell.dart`。

**P0-2 critical 弹窗依赖 navigatorKey，启动期上报的关键告警可能整批滞留队列（弹窗永不出现）**
- 位置：`lib/surface/app/error_surface.dart:460-478`（_drain）、`error_surface.dart:520-540`（_presentCritical 降级横幅）、`lib/main.dart:101-122`（启动早期 `OgLNoticeCenter.report(critical)`）
- 症状：`_drain()` 是 `take()` + 呈现 + `whenComplete → addPostFrameCallback(_drain)` 的串行泵。启动期（NoticeHost 尚未挂到 `MaterialApp.builder` / navigatorKey 尚未就绪）上报的 critical：若 `_presentAmbient` 里 `ScaffoldMessenger.maybeOf` 为 null 会 `requeueFront`（安全）；但**只要 NoticeHost 已挂而 navigatorKey.currentContext 为 null 的那一次**，`_presentCritical` 会降级为横幅并返回——横幅走了，弹窗语义（"必须被阅读"）丢失。更糟的是 `_emitSystemNotice`（error_surface.dart:494-510）在后台态对 critical 会投系统通知但**不 requeue 也不移出队列之外处理**——该条已被 `take()` 移除，回前台后用户永远看不到应用内弹窗。
- 根因：`_drain()` 对"后台 + critical"分支直接消费掉通知（error_surface.dart:464-469），没有像 info/warning 那样 `requeueFront` 留待回前台补发；回前台的 `_drain()` 只补发仍在队列里的条目。
- 修复指令：`error_surface.dart` `_drain()` 后台分支：critical 投系统通知后改为 `OgLNoticeCenter.instance.requeueFront(notice)` 并 return（去掉消费语义）；或在 notice 上加 `presentedInApp` 标记区分。另在 `_presentCritical` 的 navigatorKey==null 降级路径里保持 `_showing=false` 后的补发泵照常（当前实现已 whenComplete/requeue，核对确认无额外改动）。

---

## P1（功能失效 / 不一致）

**P1-1 快捷键 Ctrl+S/F/R 无输入焦点冲突防护，打字时也会触发页面级动作**
- 位置：`lib/surface/app/shortcuts.dart:36-52`（CallbackShortcuts bindings）、`shortcuts.dart:59-71`（_dispatch）
- 症状：`Ctrl+S` 等绑定是全局的，`_dispatch` 只从 `primaryFocus` 向上找 `OgLShortcutHandler`，**不判断焦点是否在 `EditableText` / 输入框内**。用户在编辑器正文打字时按 Ctrl+S 属预期（保存），但在**其它带输入框的页面**（issue 评论框、搜索框）若该页或祖先注册了 handler，Ctrl+F/Ctrl+R 会在打字中触发 find/刷新语义——`_find.findMode()` 等回调无法区分"用户在输入框里按了 F"。另外 `Esc` 在输入法候选窗/自动补全场景会被全局抢占，输入框内 Esc 无法用于收起 IME 联想。
- 根因：dispatch 缺少"焦点目标是文本输入时放行/仅放行 Esc 给 IME"的白名单判断（`keyboard_guard.dart` 有 `_textFocused` 同类判定可复用）。
- 修复指令：`shortcuts.dart` `_dispatch` 开头：`final focus = FocusManager.instance.primaryFocus; if (focus?.context?.widget is EditableText && intent != OgLShortcutIntent.save) return;`（Esc 仅当 handler 声明消费时才拦，或直接对 EditableText 焦点全放行）。

**P1-2 登录门 guest 模式后真登录，`_guest` 不复位导致登出后直接跳过登录门**
- 位置：`lib/surface/app/client_shell.dart:290`（`onSkip: setState(() => _guest = true)`）、`client_shell.dart:134-138`（`_check` 中仅 accountId != null 时 `_guest=false`）
- 症状：游客进入后登录账号 A（`_check` 置 `_guest=false`，OK）；但游客进入后**未登录**、直接通过其它路径（如设置页"添加账号"成功后 auth notify → `_check`）时accountId 回写为非 null，`_guest=false` 也正确。真正的漏洞是：`ProfilePage` 的 `onAccountsChanged: _check`（client_shell.dart:240）触发 `_check` 时若 `activeAccount()` 因 KV 读取瞬时失败（catch 分支 client_shell.dart:121-130）返回 null，`_guest` 已是 false → **用户被踢回登录门**；反向地，若用户在登录门点过"跳过"（guest=true）之后令牌恢复，`_guest` 复位为 false 但 `_visited` 保留，guest 期间构建的页面实例残留（与 P0-1 同根）。行为不对称：读盘瞬时失败 = 强制登出门，无重试/静默降级区分。
- 根因：`_check` 的 catch 把"读失败"与"确实无账号"同等处理，且 `_guest` 生命周期横跨两种进入路径。
- 修复指令：`client_shell.dart` `_check` catch 分支区分错误类型：KV 损坏才置 null，网络/IO 瞬时错误保持上一次 `_checked` 结果并重试一次（带退避）；`LoginPage.onLoggedIn` 回调里显式 `_guest=false; _visited..clear()..add(home)`。

**P1-3 桌面关闭按钮直接 `windowManager.close()`，绕过"脏草稿/下载中"退出确认**
- 位置：`lib/surface/app/desktop_window.dart:126-131`（close 按钮 → `ogLWindow.close`）、`lib/platform/window_windows.dart:64` / `window_linux.dart:62` / `window_macos.dart:60`（均直通 `windowManager.close()`，无 `setPreventClose`）
- 症状：桌面端点标题栏 ✕ 立即销毁窗口。对比移动端 Android 有 `SystemNavigator.pop()`（client_shell.dart:208）走双击退出，桌面端：① 下载任务进行中无"仍在下载，确认退出？"拦截；② 编辑器脏草稿无丢弃确认；③ 全仓 `rg setPreventClose` 零命中——window_manager 的 `onWindowClose` 拦截完全未接线（`lib/surface/app/token_exit_warning.dart` 只管下载 HTTP 语义，不管窗口关闭）。
- 根因：桌面窗口实现只做了最小化/最大化/关闭直通，没有接 `WindowListener.onWindowClose` + `setPreventClose(true)`。
- 修复指令：三个平台 `window_*.dart` init 时 `windowManager.setPreventClose(true)`；desktop_window.dart `_OgLTitleBarState` 实现 `onWindowClose`：下载队列非空或编辑器脏时弹确认（经 `ogLConfirm`），否则 `windowManager.destroy()`。

**P1-4 窗口装饰切换未持久化回读，`_maximized` 竞态导致按钮态错位**
- 位置：`lib/surface/app/desktop_window.dart:98-115`（`_sync()` / `onWindowMaximize`）
- 症状：`_toggleMaximize`（desktop_window.dart:159-164）`setMaximized` 后立刻 `_sync()`；window_manager 的事件（onWindowMaximize）与 `_sync()` 的 `isMaximized()` 轮询都可能到达，双击拖拽区快速连续触发时 `_maximized` 可能落后一拍，图标显示"还原"却实际是最大化状态。属竞态不一致，非崩溃。
- 根因：无单一事实来源（事件与轮询混用），`_sync` 无代际防护。
- 修复指令：`desktop_window.dart`：`onWindowMaximize/onWindowUnmaximize` 直接 `setState(() => _maximized = true/false)`；`_toggleMaximize` 只调用 `setMaximized(!_maximized)`，不额外 `_sync`（事件回调负责刷新）。

**P1-5 `_handleBack` 的 armExit 提示不重置，2 秒窗口外再按返回永远先走 goHome 分支的边界差异**
- 位置：`lib/surface/app/back_guard.dart:74-88`（decide）、`lib/surface/app/client_shell.dart:186-206`
- 症状：`decide(atHome:true)` 首按 armExit、2 秒内再按 exit。但 **armExit 后用户未在 2 秒内按第二次**，`_armedAt` 残留：下次按返回时 `now.difference(armedAt) > exitWindow`，走 armExit 分支重置——逻辑正确。真正的缺口：`_backGuard.reset()` 只在 `_select`（client_shell.dart:216-218）被调用；**armExit 提示 SnackBar 显示 4 秒（kNotifierDuration）但退出窗口只有 2 秒**——提示还在屏上而窗口已过期，用户按提示"再按一次退出"却回到 armExit 提示重发，观感为"按了没反应/提示骗人"。
- 根因：提示时长常量（notifier.dart:23，4s）与退出窗口（back_guard.dart:31，2s）各自定义、无联动。
- 修复指令：`client_shell.dart` armExit 分支改用带 `Duration(seconds: 2)` 的短提示（`SnackBar(duration:)` 参数化 `notice()`，notifier.dart 加可选 duration 参数），或把 exitWindow 提到 4s 与提示对齐。

**P1-6 预测性返回（Android 14+ Predictive Back）下壳 PopScope 状态切换撕裂**
- 位置：`lib/surface/app/client_shell.dart:254-267`
- 症状：`canPop: navigatorCanPop` 在 build 里取 `Navigator.maybeOf(context)?.canPop()`。该 build 的 context 是壳自身的（Navigator 的**下层**），`maybeOf` 找到的 Navigator 是根 Navigator——正确。但当子路由 push/pop 使 `canPop` 翻转时，壳不会自动 rebuild（push 子路由不触发壳 setState，注释自认 client_shell.dart:253），`PopScope.canPop` 保持旧值：push 子页后 `canPop` 仍是 false → **子页返回手势被壳的 PopScope 拦下转进 `_handleBack`**（它调 `navigator.maybePop()` 也能正确弹栈，功能等效）；pop 回根后 `canPop` 仍是 true → 系统预测性返回动画把壳当可弹路由跟手，松手却走 `_handleBack`，出现动画与结果不一致（跟手预览显示"关闭壳"，实际只是切 tab）。
- 根因：壳 build 依赖的 `canPop` 没有订阅路由栈变化，仅在壳因其它原因 rebuild 时偶然刷新。
- 修复指令：`client_shell.dart` 用 `RouteObserver`/`RouteAware` 或在根 Navigator 包一层 `RestorationScope` 无关的监听：push/pop 后 `setState` 刷新 `navigatorCanPop`；最简做法是给 `MaterialApp.navigatorObservers` 注册 observer 并在壳 State 里 `didPush/didPop` 时 setState。

---

## P2（打磨）

**P2-1 `_onScroll` 通知条件漏掉从中间值直接跳到边界以外的情形**
- 位置：`lib/surface/app/og_l_app_bar.dart:113-118`
- 症状：条件 `(next - value).abs() >= step || next==0&&v!=0 || next==1&&v!=1` 已覆盖 0/1 台阶；中间值步进 <1% 时不通知（有意）。但切控制器（didUpdateWidget og_l_app_bar.dart:57-69）后旧 position 的进度残留由 `_controller==null` 才清零——换成**另一个非空 controller** 时 `_progress.value` 保留旧页进度，新页顶栏初始颜色从错误色阶开始，滚动 1% 后才纠正。
- 修复指令：`og_l_app_bar.dart` didUpdateWidget：控制器非空切换时也 `_progress.value = 0`（或按新 controller 当前 pixels 立即 `_onScroll()` 重算）。

**P2-2 KeyboardGuard 焦点监听全树 setState，无节流**
- 位置：`lib/surface/app/keyboard_guard.dart:44-49`（`FocusManager.instance.addListener(_onFocusChanged)` → `setState((){})`）
- 症状：焦点每变化（含无关焦点移动）都整树 rebuild 一次 KeyboardGuard 子树（实际 rebuild 到 MediaQuery 分支，子树 diff 可短路，成本可控但无必要）；且 `_textFocused` 的 `context == null` 返回 true（keyboard_guard.dart:82）——焦点节点已销毁的瞬间窗口 inset 仍非 0 时会把幽灵键盘当真键盘保留，守卫短暂失效。
- 修复指令：`keyboard_guard.dart` `_onFocusChanged` 先比较 `ignore` 布尔是否翻转再 setState；`context == null` 分支改按"inset 是否超过阈值"保守判断并记 WARN 日志。

**P2-3 OgLAppLog.unreadCount / _recountAlerts 每次写日志 O(n) 扫描**
- 位置：`lib/surface/app/error_surface.dart:395-398`（_recountAlerts）、`error_surface.dart:455-458`（unreadCount getter）
- 症状：`add()` 每次调 `_recountAlerts()` 全表 where 扫描（n≤2000，尚可）；但 `unreadCount` 是 getter，通知中心页 build 期间对每行调用 `isRead`，2000 条 × 行渲染为 O(n²)。注释声称"O(1)"（error_surface.dart:389）仅对 alertCount 成立。
- 修复指令：`error_surface.dart` 维护 `int _unread` 增量计数（markRead/clear/add 同步增减），getter 改 O(1)。

**P2-4 OgLReveal didUpdateWidget 只处理 delay→null，null→delay 会不入场**
- 位置：`lib/surface/app/animations.dart:338-344`
- 症状：档位从 0（delay==null，直接静态渲染）切到档位 2/3 时 `widget.delay` 变非 null，但 `_shown` 已是 true → 不重播（合理，防回弹）；但反向从"已显示"到"新插入项带 delay"（列表复用 State、Element 重挂到新 item）时 `_start` 在 initState 已跑过且 `mounted` 期间不会重跑，新项直接显示无错峰——观感不一致（非功能错误）。
- 修复指令：`animations.dart` didUpdateWidget 增加：`oldWidget.delay == null && widget.delay != null && !_shown` 时调用 `_start()`。

**P2-5 ogLShowDialog 未透传动画档位时长**
- 位置：`lib/surface/app/overlays.dart:61-70`
- 症状：`ogLShowSheet` 经 `sheetAnimationStyle` 注入档位时长（overlays.dart:52-57），但 `ogLShowDialog` 未传 `DialogTheme`/`AnimationStyle`——对话框进出仍是 Flutter 默认 150ms，与"统一弹层定速入口"的设计目标（文件头声明）不符；档位 0 时对话框仍播动画。
- 修复指令：`overlays.dart` `ogLShowDialog` 增加传参：`showDialog(..., )` 无法直接给时长，改用 `PageRouteBuilder`/自定义 `DialogRoute` 注入 `transitionDuration: OgLAnim.medium(context)`（档位 0 为 zero）。

**P2-6 boot_splash 与真实主题 seed 不同源**
- 位置：`lib/surface/app/boot_splash.dart:38-42`（硬编码 `Color(0xFF0969DA)`）
- 症状：注释声称"与 MD3 seed 色板同族"，但设置里用户可改种子色（theme.dart），splash 固定 0969DA；用户换了主题色时冷启动首帧与顶替帧之间仍有色差闪变。
- 修复指令：可接受（首帧零依赖约束）；如要消除，将上次会话的 seed 色写进启动 dart-define 或独立小配置文件，splash 优先读。

---

## 已检查清单（11 个目标文件全读 + 3 个关联文件）

| 文件 | 检查内容 | 结果 |
|---|---|---|
| client_shell.dart（509 行全读） | 启动态机 `_check`（世代号防重入 ✓、读失败降级 ✓）、认证门三态、懒挂载 `_visited`、返回链重入闸门、PopScope canPop、IndexedStack+TickerMode、`_OgLShellSlide` dispose ✓ | P0-1、P1-2、P1-5、P1-6 |
| og_l_app.dart（250 行全读） | MaterialApp 组装、navigatorKey、textScaler 夹紧、builder 层级、DynamicColorBuilder 明暗选择、locale 映射、OgLBootFailureApp 可滚动 ✓ | 无新问题 |
| og_l_app_bar.dart（158 行全读） | didUpdateWidget 控制器切换、dispose removeListener ✓、B-15 夹紧 ✓ | P2-1 |
| boot_splash.dart（75 行全读） | 零依赖约束、锚定色 | P2-6 |
| overlays.dart（158 行全读） | sheetAnimationStyle（不自建控制器 ✓）、danger confirm、discard 确认 | P2-5 |
| notifier.dart（160 行全读） | mounted 二道保险、replace clearSnackBars、时长常量 | P1-5（与 back_guard 联动） |
| error_surface.dart（626 行全读） | 通知中心去重/上限/落盘、_drain 泵、后台补发、critical 弹窗 navigatorKey、双 sink 接线（main.dart:143-144 ✓） | P0-2、P2-3 |
| keyboard_guard.dart（151 行全读） | EditableText/CodeEditor 判定、context==null 保守、节流日志 | P2-2 |
| shortcuts.dart（82 行全读） | 桌面 gate、焦点向上找 handler、编辑器注册点（code_editor_page.dart:563-579 核对） | P1-1 |
| animations.dart（386 行全读） | OgLReveal Timer 取消 ✓、staggerOf、spring、sharedElement | P2-4 |
| motion.dart（525 行全读） | 档位表单调性、过渡缓存上限 4、CurveTween 替代 CurvedAnimation 的监听泄漏论证 | 无问题 |
| back_guard.dart（关联，96 行） | 纯状态机、exitWindow、reset | P1-5 依据 |
| desktop_window.dart（关联，280 行全读） | 标题栏按钮、WindowListener、_sync、窗口 Frame、静默降级 `_guard` ✓ | P1-3、P1-4 |
| main.dart（关联，344 行） | 双 runApp 启动、错误捕获三件套、sink 接线、引导信任链 | 启动机 ✓ |

核对但无问题的专项：`_check` 世代号防重入与 gh_auth.dart:200-202 同值短路形成闭环（无自激循环）；`OgLTitleBar`/`OgLKeyboardGuard`/`OgLNoticeHost` 的 dispose 链均成对 removeListener（无泄漏）；`_OgLShellSlide` controller dispose ✓；`_delayTimer` cancel ✓；设置子页 PopScope（settings_page.dart:1731）正确处理返回确认。

---

## 本席结论

外壳状态机整体工程质量高：世代号防重入、返回重入闸门、CurveTween 资源修复等都是真实缺陷的认真收口。剩余问题集中在三处横切面：**认证门切换不清栈（P0-1）**、**通知泵对后台 critical 的消费语义（P0-2）**、**桌面窗口关闭无拦截（P1-3）**。7 项问题中 2 P0 / 4 P1 / 6 P2（共 12 条编号问题：P0×2、P1×4——P1-5 与 P2-6 为跨文件联动/低危，另 P2×6）。建议修复顺序：P0-1 → P0-2 → P1-3 → P1-1 → 其余。
