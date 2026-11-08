# 第7批 · 视角A：实现正确性审计 —— 主题与令牌警告子系统（v12.0.0 LTS）

审计方式：全文阅读（无 rg 代替），逐文件核对缓存键、回落链、档位边界、滚动控制器行为与设置传播链。
裁决依据：docs/QUALITY_STANDARD.md、AGENTS.md（均完整读）。只审不改。

---

## 发现清单

### B7-A-01 · P0 · client_shell.dart:105-129 × gh_auth.dart:291-303（确证·代码证据）
**问题一句话**：批5接入的 `refreshState()` 无条件 `_setState`→`notifyListeners()`，而 shell 的 auth 监听者 `_onAuthChanged` 直接回调 `_check()`，`_check` 又调用 `refreshState()`——形成**无终止的异步自激循环**。
**证据**：`gh_auth.dart:199-203` `_setState` 无同值短路（对比 `markExpired` 有 `_state == expired` 判断，`refreshState` 没有）；`client_shell.dart:86-90` `initState` 里先 `addListener(_onAuthChanged)` 再 `_check()`；`_check` 内无重入闸门（有闸门的是 `_handleBack`，另一条路径）。每次循环执行 2 次 KV 读 + 1 次密钥库读，永不停歇；`ProfilePage(onAccountsChanged: _check)`（client_shell.dart:233）同理再添入口。
**用户可见后果**：启动后持续空转 IO/CPU（低端机发热、掉电、日志环被冲刷）；任何一次 notify 都会再触发一轮。属第 22/26 条（异步结果/防重）违反，也是第 27 条"并发假设没写出来"的典型。
**原则**：22、26、27。
**状态**：确证（代码证据闭环；未做运行时实测——建议在测试环境用计数监听器跑 10 秒验证，标「待议」仅限实测数值）。

### B7-A-02 · P1 · surface_bridge.dart:492-540 × theme.dart:261-429（确证）
**问题一句话**：`themeFor` 用 `textTheme.apply(fontFamily:)` 覆写正文族，但 `buildOgLTheme` 内 appBarTheme.titleTextStyle、dialogTheme.titleTextStyle/contentTextStyle、chipTheme.labelStyle、inputDecorationTheme.hintStyle、snackBar contentTextStyle 均为**就地 new 的 TextStyle**，不携带所选 UI 字体。
**证据**：theme.dart 各组件主题段全部 `TextStyle(color:…, fontSize:…)` 无 fontFamily 参数，且在 `themeFor` 的 copyWith 之前已定型，`copyWith(textTheme:)` 传不进去。
**用户可见后果**：用户选思源宋体/私有字体后，应用栏标题、对话框标题与正文、Chip 标签、输入框 hint、SnackBar 文本仍是系统字体——"换字体只换了一半"，与设置项语义不符。
**原则**：34（视觉值一律取自令牌/单一真相）、21（半成品降级路径）。
**状态**：确证。

### B7-A-03 · P1 · font_loader.dart:134-145 + settings_page.dart:854-880（确证）
**问题一句话**：私有字体落盘目录是 `Directory.systemTemp/ogl-fonts`，注释却声称"应用支持目录下 fonts/"——目录选择与文档都不成立。
**证据**：`font_loader.dart:136-144` `final Directory base = Directory.systemTemp;`；注释写"应用支持目录下"。settings_page.dart `_registerPickedFont` 把用户字体文件写进该目录后，settings.dart 的 `customFonts` 持久化 filePath。
**用户可见后果**：Android 磁盘清理/重启后 temp 目录被清空 → 字体文件消失，启动后界面字体静默回落系统字体，设置项仍指向失效路径（选择"还在"但无效）；本地导入的字体源文件路径可能同样失效。第 8 条"数据无价"与第 15 条"静默降级"双违。
**原则**：8、15、54（注释撒谎）。
**状态**：确证（temp 目录清理行为属平台常识，真机复现标「待议」）。

### B7-A-04 · P1 · font_loader.dart:101-129（确证）
**问题一句话**：`ensureNotoSerifSc` 每次冷启动重新从网络下载整只字体：落盘的 `${font.id}.otf` **只写不读**，`isLoaded` 内存集合不跨进程。
**证据**：`ensureNotoSerifSc` 内 `bytesOf(font)`（filePath 为空 → 走 http 分支重新下载）→ 写盘 → 注册；全库无任何"从该 .otf 读回字节"的代码路径。
**用户可见后果**：选了思源宋体的用户每次冷启动后进设置页重新选择/点"下载"都重新下载数十 MB；且启动早期 `_uiFontFamilyOf` 返回未注册 family → 静默回退系统字体直到用户再次手动触发（surface_bridge.dart:522 注释自认"启动早期先回落"）。外部数据直接 `HttpClient` 裸下载也绕开了 ResilientTransport 的重定向/SSRF 防线（本例无令牌，降为 P1）。
**原则**：15、28（缓存键/缓存未覆盖"已落盘"这一维度）、44。
**状态**：确证。

### B7-A-05 · P1 · client_shell.dart:74,129,261（确证·与 B7-A-01 同根的次生面）
**问题一句话**：`_check` 无防重入闸门，登录门回调（`onLoggedIn: _check`）、`onAccountsChanged: _check` 与 auth 监听三路并发触发时 `_checked` 可被乱序覆盖（后完成的旧结果覆盖新结果）。
**证据**：`_check` 内 `setState` 无世代号比对（对比 settings.dart `load()` 的 `_loadGen` 防陈旧模式——同仓库已有正解但此处未用）。
**用户可见后果**：快速登录/切号/登出时账号状态闪回旧值一次；修复 B7-A-01 时应同修（加世代号或 in-flight 去重）。
**原则**：22、26。
**状态**：确证（具体乱序时序标「待议」）。

### B7-A-06 · P2 · animations.dart:175-196（确证）
**问题一句话**：`OgLReveal.didUpdateWidget` 只处理 `delay` 变为 `null` 的情况；`delay` 从非空变非空（档位 2↔3 切换，staggerStep 变化）时不重启 `_delayTimer`。
**证据**：`if (oldWidget.delay != widget.delay && widget.delay == null)`——非空→非空分支缺省，旧 Timer 按旧档延迟触发。
**用户可见后果**：动效档位切换瞬间，尚未入场的列表项按**旧档位**的延迟/是否动画出现（如 3→2 后尾部项本应 Duration.zero 立即显示，却等旧档延迟）；一次性、轻微。
**原则**：24（生命周期对称）、33。
**状态**：确证。

### B7-A-07 · P2 · og_l_app_bar.dart:88-114（待议）
**问题一句话**：`PrimaryScrollController.maybeOf` 拿到的控制器可同时 attach 多个 position（PageView 多子页/嵌套滚动视图共享 primary），`_applyProgress` 固定取 `positions.first`，像素来源不确定。
**证据**：`controller.positions.isNotEmpty → positions.first`，无「属于本 AppBar 所在视图」的甄别；文件头注释只声明了自建控制器与 TabBarView 两个边界，未覆盖 NestedScrollView/多 position。
**用户可见后果**：嵌套滚动页面上 AppBar 底色可能随**错误的那条**滚动位置变化（内层列表滚深、外层未滚 → AppBar 提前浮起，或反之）；不崩溃、不闪变。
**原则**：31（热路径正确性）、32。
**状态**：待议（需运行时实测嵌套视图页面确认取向）。

### B7-A-08 · P2 · anim_preload.dart:795-812（确证）
**问题一句话**：`OgLAnimPreloadBoundary._sync` 以 `_syncedLevel == _level` 短路，`widget.jobs` 内容变化但组名/档位不变时新任务**永不登记**。
**证据**：`didUpdateWidget` 只在 `group` 变化时置 `_syncedLevel = -1`；`jobs` 是同组页面数据刷新（如新头像 URL → 新 job.id）的常见场景。
**用户可见后果**：同页数据更新后新图片不参与预加载（首次出现仍可能卡顿），静默失效、无日志。
**原则**：21、28。
**状态**：确证。

### B7-A-09 · P2 · token_exit_warning.dart:78-80（待议）
**问题一句话**：令牌头判定硬编码小写键 `headers['authorization']`，大小写变体（`Authorization`）会**静默绕过**警告直接放行。
**证据**：`final String? auth = headers['authorization'];`，无大小写归一化；当前唯一生产头来源 gh_client.dart:609 恰用小写，故现网不触发，但该函数是"门禁"，防线依赖调用方的拼写自觉。
**用户可见后果**：当前无；未来调用点若传大写键，令牌外发无警告、无留痕（第 40 条破口）。
**原则**：11（防线没有开关）、40。
**状态**：待议（现网路径确证无害，防御性缺口确证；建议逐键遍历归一化）。

### B7-A-10 · P2 · settings.dart:763-766（确证）
**问题一句话**：`setMotionLevel` 上方一行孤立 doc 注释"便捷：设置全局动效档位（越界夹紧到 0–3）。"错挂在 `setUiFont` 头上。
**证据**：763-766 行注释与下一声明 `setUiFont` 语义不符。
**用户可见后果**：无直接后果；文档误导维护者（第 54/57 条）。
**原则**：54、57。
**状态**：确证。

### B7-A-11 · P2 · keyboard_guard.dart:66-69,82-88（确证）
**问题一句话**：`_textFocused` 对"拿不到 context"返回 true（保守保留 inset，注释自证），但 `FocusManager.instance.addListener(_onFocusChanged)` 在**每次焦点变化**时 `setState` 整棵 builder 子树。
**证据**：`_onFocusChanged → setState(() {})` 无任何状态变化判断（对比本文件 `_lastMetrics` 的节流纪律）。
**用户可见后果**：桌面端高频焦点切换（Tab 遍历表单）引发全树无谓重建，与 PERF.md 的"避免整页重建"相悖；功能正确。
**原则**：31、32。
**状态**：确证。

---

## 重点核对结论（无发现的部分）

- **themeFor 缓存键完整性（surface_bridge.dart:492-540）**：brightness/seed/density/motionLevel/uiFont 五维齐全 ✅；fontScale 不入主题（走 builder 的 MediaQuery 覆盖）正确 ✅；语言变更不换主题正确 ✅。有界缓存合规。
- **动效档位边界**：`OgLOAnimQuality.of` 对越界值 `default` 归 0（少做优先）✅；0 档全静默（时长全零、instant 过渡、spring null、stagger 返回 null）有 animations_test.dart 覆盖 ✅；`isNotHeavierThan` 单调性有测试钉死 ✅；`pageTransitions` 缓存 ≤4 有界且越界不写缓存 ✅。
- **设置变更→主题重建传播链**：`apply → notifyListeners → OgLApp ListenableBuilder → themeFor(motionLevel)` 闭环完整；apply 的世代号防 load 回冲（settings.dart:815-850）是全仓库防陈旧的范本 ✅。
- **back_guard**：状态机纯逻辑、单测覆盖、死枚举已删，无问题 ✅。
- **desktop_window**：平台差异收敛在 platform 门面，_guard 降级带日志留痕，注册/注销对称 ✅。
- **anim_preload 主体**：有界（done LRU 64、额度预扣/归还幂等、_enforceCaps 降档收紧）、不持 BuildContext、detachLater 遵循 precacheImage 同款帧末释放——设计正确，仅 B7-A-08 一处接线缺口。

## 覆盖文件清单

| 文件 | 行数 | 结论 |
|---|---|---|
| docs/QUALITY_STANDARD.md / AGENTS.md | 93 / 95 | 完整读，裁决依据 |
| lib/surface/theme.dart | 429 | B7-A-02 |
| lib/surface/app/font_loader.dart | 145 | B7-A-03/04 |
| lib/surface/app/font_pick.dart | 67 | 无发现 |
| lib/surface/app/motion.dart | 494 | 无发现 |
| lib/surface/app/og_l_app_bar.dart | 151 | B7-A-07 |
| lib/surface/app/animations.dart | 386 | B7-A-06 |
| lib/surface/widgets/anim/anim_preload.dart | 820 | B7-A-08 |
| lib/surface/app/token_exit_warning.dart | 170 | B7-A-09 |
| lib/surface/app/back_guard.dart | 96 | 无发现 |
| lib/surface/app/keyboard_guard.dart | 151 | B7-A-11 |
| lib/surface/app/desktop_window.dart | 278 | 无发现 |
| lib/surface/settings.dart | 1058 | B7-A-10（其余合规） |
| lib/surface/surface_bridge.dart（themeFor 段） | 705 | B7-A-02 关联；缓存键 ✅ |
| lib/surface/app/og_l_app.dart | 222 | 传播链 ✅ |
| lib/surface/app/client_shell.dart（_check 段） | 491 | B7-A-01/05 |
| lib/domain/gh/gh_auth.dart（refreshState/_setState 段） | 415 | B7-A-01 根因 |
| lib/surface/pages/settings_page.dart（字体段） | 2368 | B7-A-03/04 关联 |
| test/surface/animations_test.dart | 287 | 档位边界覆盖良好 |
| test/surface/page_transitions_test.dart | 116 | 过渡约定覆盖良好 |

## 整体评价

动效子系统（motion/animations/anim_preload）是本次审计中质量最高的部分：纯数据档位表、单调性测试、有界缓存、帧末释放纪律一应俱全，几乎无可挑剔。令牌警告弹窗的"三重不可关闭 + 决策留痕"设计合格，但门禁键匹配欠一层防御。真正的 P0 在批5接线的 `refreshState`：`_setState` 无同值短路 + `_check` 无重入闸门，构成启动即自激的通知循环——这是"接线"改动只看了调用点、没看被调方 notify 语义的教科书案例，建议与 B7-A-05 一并修复（同值短路 notify + _check 世代号）。字体子系统的 temp 目录落盘与"只写不读"是数据可靠性铁律（第 8 条）在展示层的失守点。
