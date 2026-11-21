# 批 4 · B 席 —— 页面转场与手势语义交叉审计

> **文档戳 / Doc Stamp**
> - 审计批次：**批 4 · 反馈与动效 · B（页面转场与手势语义）**
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `f684160`（2026-11-21 16:27:57 +0800）
> - 更新时间：**2026-11-22（Asia/Shanghai）**
> - 审计对象：`lib/surface/app/motion.dart`（`_OgLSlideFadeTransitionsBuilder` / `pageTransitions`）、`lib/surface/app/client_shell.dart`（`PopScope` 返回链 / `_OgLShellSlide` 切 tab）、`lib/surface/app/overlays.dart`（sheet / dialog）、`lib/surface/surface_bridge.dart`（主题注入）、`lib/surface/app/og_l_app.dart`、`lib/surface/pages/*`（TabBar / push / 弹层 / 引导页 / 表单返回拦截）
> - 基准文档：`docs/UX_CROSS_AUDIT_BRIEF.md`（含双轴补强）、`/var/minis/skills/sota-frontend-design/rules/06-motion-design.md`（§3 方向语义、§7b 手势规格、§2 时长/缓动、§6 reduced motion）、`/var/minis/skills/material-3/SKILL.md` §Motion / `references/navigation-patterns.md`（平级目的地 vs 层级导航、Adaptive 导航）
> - 性质：**只读审计**。未修改任何业务代码，未 commit / 未 push。
> - 复现方式：全部证据为 `file:line`，`rg -n "<片段>" <路径>` 可复现。
>
> **跨席边界（避免与 2-C 重复）**：批 2-C 已就**档位参数本身**（`transitionOffset` 0.012/0.03/0.05、缩放 0.99/0.975、`transitionWindow` 死等、切 tab 透明度 0.70、弹簧刚度/过冲、`blurSigma` 死参数等）出报告。本席**不重复报参数数值**，只从**语义与手势**维度切入：方向隐喻是否一致、返回链是否连续、手势是否被吞、平台映射是否错配、弹层/对话框出口手势是否统一。凡与 2-C 相接处均在条目内显式标注「跨席边界」。

---

## 0. 结论摘要

按 rules/06 §1 的「每个动画必须回答取向 / 反馈 / 连续性 / 状态」逐条对照，本库转场与手势层的问题不是「动得太多」，而是**方向不编码层级、返回链没有接力、手势被全局 PopScope 吞掉、平台共用一套隐喻**。用户可感知的后果：进页像「从下往上冒」、返回像「往下沉」而不是「往回走」；切 tab 是「新页盖上来」而不是「两页对向换位」；Android 手势返回滑到一半弹回；跨页 Hero 飞到一半消失。

| # | 结构性语义问题 | 用户感受 | 级别 |
|---|---|---|---|
| B-01 | 页级转场不消费 `secondaryAnimation` → 旧页无退场、返回无接力 | 「新页冒出来、旧页凭空不见」 | 严重 |
| B-02 | push 与 pop 同为纵向单向下沉，方向不编码前进/后退 | 「像上下呼吸，看不出在往回走」 | 严重 |
| B-03 | 全局 `PopScope(canPop:false)` + 多处拦截 → 预测性返回手势被吞 | 「滑一半弹回去、返回失灵」 | 严重 |
| B-04 | 壳层 `navigator.pop()` 绕过表单页 dirty 确认链 | 「返回手势直接丢掉没保存的内容」 | 中 |
| B-13 | 共享元素只有起点没有终点 → Hero 不成立 | 「标题飞一半消失」 | 中 |

**一句话结论**：本库的页面转场是「一套参数打天下」——不区分 push/pop、不区分平台、不区分层级与平级切换，手势返回被一个全局闸门统一代管。它传达不了「我从哪来、我往哪去」，这是漂浮感与不稳定感在导航层的直接来源。

---

## 1. 用户可感知问题清单（18 条）

### 严重（3 条）

#### B-01 · 转场完全不消费 `secondaryAnimation`：旧页无退场，返回链不连续
- **证据**：`lib/surface/app/motion.dart:423` 的 `buildTransitions<T>` 签名里收了 `Animation<double> secondaryAnimation`（`:427`），但函数正文（`:452-469`）只用它之外的 `animation`/`moved`/`faded`，`secondaryAnimation` **零次被使用**；`rg -n 'secondaryAnimation' lib/` 只命中 `:371/:427` 两处签名。
- **用户感受**：push 时新页纵向滑入淡入，旧页**原地不动**；pop 时新页退场，旧页**凭空出现**（没有对向滑回）。两页不是一次「接力」，而是两次「单方面出现/消失」。用户看到的是页面在原地闪现而不是空间里被推走/拉回 → 空间感断裂、漂浮。
- **规范依据**：rules/06 §3「Enter and exit run together when swapping views（交叉淡化 + 轻微滑动），exit 略快，incoming 可重叠 outgoing 末 30–50%」；§1「continuity = 这两个视图是同一个对象」。
- **修复指令**：在 `motion.dart:423-469` 的 `buildTransitions` 里增加 secondary 分支——用 `secondaryAnimation` 给当前页（作为被推入/被返回的旧页）叠一段 `SlideTransition` + `FadeTransition` 的**反向**退场，方向与主 `animation` 相反，时长用 `OgLOAnimQuality.of(level).fast`（出屏比进屏短），曲线用 `Curves.easeIn`（M3 emphasized accelerate 200ms）。改写后用 `RepaintBoundary` 包住两支避免旧页重绘。**跨席边界**：不改 `offset`/`scaleFrom` 参数（2-C 已审），只补 secondary 通道。
- **检查清单项**：验证 push / pop 两条路径都能看到「一页进、一页出」同帧发生；验证 pop 结束时旧页恰好落位、无闪白。

#### B-02 · push 与 pop 同向纵移：方向不编码「前进 / 返回」
- **证据**：`lib/surface/app/motion.dart:457` → `Tween<Offset>(begin: Offset(0, offset), end: Offset.zero)`，Y 轴单向；`buildTransitions` 对 push 与 pop 使用**同一个** `animation` 正向映射，没有按 route 方向取负号。
- **用户感受**：进页「从下方升上来」，返回时旧页也是「从下方升上来 / 往下沉」，两次动作同向串联，观感像页面在上下呼吸而非「走进去 / 退回来」。用户丧失「我在往回走」的方向反馈 → 信息层级感消失、漂浮。
- **规范依据**：rules/06 §3「Direction encodes meaning consistently：forward slides left (in LTR), back slides right；up = expand / down = dismiss，不混用隐喻」；MD3 层级导航用 horizontal shared-axis。
- **修复指令**：`motion.dart:457` 改为 shared-axis X 语义：进页从右 `Offset(1, 0)*offsetScale → 0`，返回旧页从左 `Offset(-1, 0)*offsetScale → 0`；判断方向用 `route` 的 push/pop（可从 `secondaryAnimation.status` 或 `route.isCurrent`/自定义 route 的 `pushDirection` 传入，勿改全局参数）。同时保留「上=展开、下=关闭」给**弹层**（见 B-09），让页面导航与弹层各用一套不混用的隐喻。**跨席边界**：方向语义属本席；位移幅度/缩放值仍归 2-C，不改数值。
- **检查清单项**：逐屏验证 push 方向一致向右进、系统返回键与手势返回时旧页向左回；验证 RTL locale 下自动镜像（当前 `supportedLocales` 仅 zh/en，镜像预留即可）。

#### B-03 · Android 预测性返回手势被全局 `PopScope(canPop:false)` 吞掉
- **证据**：`lib/surface/app/client_shell.dart:246-253` 根 `PopScope(canPop: false, onPopInvokedWithResult: ...)` 接管所有返回；同类拦截还有 `lib/surface/app/token_exit_warning.dart:127`、`lib/surface/app/error_surface.dart:537`、`lib/surface/pages/settings_page.dart:1732`（均 `canPop:false`）；`rg -n -i 'predictive|PredictiveBack|enableOnBackInvokedCallback' lib/ android/` **无命中**（仓库未含 `android/` 平台目录，无法在 manifest 侧启用 `android:enableOnBackInvokedCallback="true"`，也无 Flutter 3.24+ `onPopInvokedWithResult` 的预测性阶段联动）。
- **用户感受**：Android 14+ 边缘右滑返回时，页面跟手滑到一半，因为 `canPop:false` 手势被取消、页面**弹回原位**，随后才执行壳层逻辑（切 tab 或提示「再按一次退出」）。用户看到「滑了没走 / 返回失灵」——这是「不稳定」最直接的触感来源。
- **规范依据**：MD3 `references/navigation-patterns.md`「predictive back where applicable」；rules/06 §7b「手势必须可中断、1:1 跟手、有边界橡皮筋」。
- **修复指令**：① 在平台层（若有 `android/app/src/main/AndroidManifest.xml`）为 targeting Android 13+ 设置 `android:enableOnBackInvokedCallback="true"`；② 把根 `client_shell.dart:246-253` 的 `canPop:false` 改为**条件式**：仅当 shell 处于 `_handleBack` 需要接管的分支（非首页、弹窗打开、待退出）才设 false，其余返回交给 Navigator 自身 pop，让系统预测性动画生效；③ 对必须拦截的弹窗（`token_exit_warning.dart` / `error_surface.dart` / `settings_page.dart:1732`）接受「手势被拒」但要给**视觉回弹说明**（如警告框轻微左右抖动 + `OgLNotifier` 提示「请先完成确认」），不要静默吞掉。
- **检查清单项**：真机 Android 14 边缘滑返回验证跟手位移、松手后是「完成返回」而非「弹回」；验证 `canPop:false` 场景有明确拒绝反馈而非无声。

### 中（12 条）

#### B-04 · 壳层 `navigator.pop()` 绕过表单页 dirty 确认，手势返回会丢数据
- **证据**：`lib/surface/app/client_shell.dart:167-170` → `if (navigator != null && navigator.canPop()) { navigator.pop(); return; }`；被 push 的 dirty 表单页各自有确认链，如 `lib/surface/pages/new_issue_page.dart:123-133`、`workflow_dispatch_page.dart:399-412`、`code_editor_page.dart:544-552`，均以 `PopScope(canPop: !_dirty, onPopInvokedWithResult: ...)` 拦截。
- **用户感受**：在有未保存内容的编辑页做返回手势，壳层的全局 gate 抢先 `navigator.pop()`，表单页的「放弃修改？」确认可能不会被触发，内容被静默丢弃 → 「返回把我的东西弄没了」的强烈不稳定感。
- **规范依据**：rules/06 §7b「每个手势面必须提供非手势等价路径」；MD3 破坏性操作须可撤销/确认。
- **修复指令**：`client_shell.dart:167-170` 不要直接 `navigator.pop()`，改为 `Navigator.of(context).maybePop()`（让目标路由自己的 `PopScope` 决定），或先检查 `navigator.canPop()` 且不越过当前 route 的 `PopScope.canPop`；在 `onPopInvokedWithResult` 里处理 `didPop==false` 的分支时不重复调用 pop。**跨席边界**：这是返回**语义链**问题，不是 PopScope 参数表本身（2-C 未审）。
- **检查清单项**：逐个 dirty 页（new_issue / new_repo / new_gist / new_release / workflow_dispatch / code_editor / repo settings 标签）用系统返回键和边缘手势各测一次，必须弹确认且不丢内容。

#### B-05 · 异步闸门吞掉返回手势：快速二次返回「无响应」
- **证据**：`lib/surface/app/client_shell.dart:151` `_backHandling` 闸门；`:249-253` `onPopInvokedWithResult` 用 `unawaited(_handleBack())`；`:159-162` 处理中直接 `if (_backHandling) return;`；`:209` finally 才复位。
- **用户感受**：第一次返回弹出确认框或切 tab 的异步窗口内，用户再次手势返回被闸门直接丢弃，没有任何反馈（既不返回也不提示）→ 「按了没反应、系统卡了」。闸门防「连按穿两层」是对的，但缺**被拒反馈**。
- **规范依据**：rules/06 §1 反馈目的；§7b 手势应有明确结果（dismiss / spring back）。
- **修复指令**：在 `client_shell.dart:159-162` 命中 `_backHandling` 时给一次轻量反馈——`OgLNotifier.of(context).info(...)` 或让警告框做 100ms 小幅 shake（rules/06 §4b invalid shake ≤2 cycles），而不是静默 return；同时把 `_handleBack` 的 await 段尽量收窄（只在真正需要异步确认处 await）。
- **检查清单项**：连续两次快速返回验证第二次有可见反馈；验证闸门不会导致应用无法退出。

#### B-06 · 切 tab 只有新页入场、没有旧页退场：平级切换被做成「覆盖」而非「换位」
- **证据**：`lib/surface/app/client_shell.dart:472-480` 只更新 `_from` 并跑弹簧；`:504-507` `FractionalTranslation(translation: Offset(_from*(1-t),0), child: child)` 只作用于 `IndexedStack` 整体（即当前页），旧页随 stack 切换**瞬时消失**、无对向位移。
- **用户感受**：点底栏切 tab 时，新页从侧面滑入盖上来，旧页没有「往相反方向让位」的过程，两个平级目的地之间不像「换位」而像「盖章覆盖」→ 层级关系混乱、不稳。
- **规范依据**：rules/06 §3「tab indicator slide + panel cross-fade 150ms（平级切换）」；MD3 NavigationBar 是平级 destination（不是栈）。
- **修复指令**：`client_shell.dart:414-511` 把 `_OgLShellSlide` 改为同时保留前一页的 `FractionalTranslation`（方向相反）做退场，或用 `AnimatedSwitcher` + `SlideTransition` 成对进出；位移方向仍按 index 序（B-07 会改语义），但让两页对向接力。**跨席边界**：2-C C-09/C-18/C-19 已审弹簧过冲/透明度/可中断，本条只报「缺旧页退场的换位语义」，不改弹簧参数。
- **检查清单项**：相邻 tab 与跨多 tab 切换都验证「一进一出」对向；验证 TickerMode 停表仍生效（隐藏页不烧帧）。

#### B-07 · 平级底栏切换套用「层级前进/返回」的横向隐喻，跨多格幅度不变
- **证据**：`lib/surface/app/client_shell.dart:477` `_from = widget.index > oldWidget.index ? distance : -distance`，只用 index 大小定方向、不看跨越格数；`:344-370` `NavigationBar` / `:382-405` `NavigationRail` 的 4 个 destination 是平级入口（MD3 navigation-patterns 定义为 3–5 个平级目的地用 Bar/Rail）。
- **用户感受**：从「设置」(index 3) 直接点「首页」(index 0)，动画幅度和相邻切一格一样、方向按「向左 returns」，暗示「后退了一级」，但首页与设置是平级关系 → 用户得到错误的层级暗示；快速连点跨格时方向来回翻转 → 「晃」。
- **规范依据**：MD3 `navigation-patterns.md`「Navigation Bar 3–5 平级 destinations，active item 用 indicator pill」；平级切换应用 fade + 轻微位移，不编码层级前后。
- **修复指令**：`client_shell.dart:477` 改为平级语义——所有 tab 切换统一用**短距 fade + 微移**（位移取 `OgLAnim.shellOffset(context)` 的固定小值，方向可按 index 序但幅度不随「前进/返回」语义放大），并让 `NavigationBar` 的 indicator pill 自己承担 200ms 的选中态滑动（框架默认即可，勿叠加整页横滑误导）。若产品坚持横滑，则需在文档注明「Bar 实为层级栈」并改为真实导航栈。
- **检查清单项**：验证跨格切换与相邻切换幅度一致、无「返回了一级」错觉；验证 indicator 与内容过渡节奏一致。

#### B-08 · 两处一级 TabBar 转场策略不统一，且均未接档位时长
- **证据**：`lib/surface/pages/repo_page.dart:616` `TabBar(` 与 `:624` `body: TabBarView(children: tabViews)`——无 controller / 无 physics 配置，随框架默认；`lib/surface/pages/search_page.dart:718-727` `TabBar(controller: _tab)` 与 `:728-737` `TabBarView(controller: _tab, physics: OgLAnim.enabled(context) ? AlwaysScrollableScrollPhysics() : NeverScrollableScrollPhysics())`。两处同为一级 tab，一处强制可滑一处默认；`rg -n 'indicatorAnimDuration|AnimationStyle' lib/surface/pages/` 无命中 → indicator 滑动与面板切换均未接 `OgLAnim` 档位。
- **用户感受**：在仓库页与发现页之间切换 tab，手感却不同（一个能跟手滑、一个按设置走），且档位调到 0 时仓库页的 tab 面板仍可能有残余过渡 → 「同一个 App 两套节奏、降档没完全生效」。
- **规范依据**：rules/06 §8「motion tokens 一处定义全局消费」；§4b「tab indicator slide 200ms + panel cross-fade 150ms」。
- **修复指令**：统一两处 TabBarView 的 physics 策略（建议都按 `OgLAnim.enabled(context)` 决定，仓库页 `repo_page.dart:624` 补上同 search 页的条件）；给两处 TabBar 的 `indicatorColor`/label 动画接 `OgLAnim.medium`/`fast`，或至少确保档位 0 下 `TabBarView` 的 `physics: NeverScrollableScrollPhysics()` 生效。**跨席边界**：只统一策略与接档位，不改具体位移/时长数值（2-C 已审参数）。
- **检查清单项**：逐页（repo / search）验证手势滑动与点击切换在档位 0/1/3 下节奏一致。

#### B-09 · 底部弹层出场与入场等长，手势下拉关闭「拖泥带水」
- **证据**：`lib/surface/app/overlays.dart:66-69` → `AnimationStyle(duration: duration, reverseDuration: duration)`，出场=入场；`enableDrag` 沿用默认 true（文件头 `:44-52` 注释确认未覆盖），即下拉手势关闭也走这段等长反向动画。
- **用户感受**：手指下拉面板到阈值松手后，面板用与打开同样长的时间才消失，用户已决定关掉却还要等 → 「关不掉、黏手」。
- **规范依据**：rules/06 §2「exit = enter 的 60–80%（150–200ms）」；§7b 手势释放应干脆。
- **修复指令**：`overlays.dart:66-69` 把 `reverseDuration` 改为 `duration * 0.7`（或 `OgLAnim.fast(context)`），出场曲线用 `Curves.easeIn`。**跨席边界**：2-C C-14 已报曲线缺失与 `sheetDuration` 数值偏短，本条只补「出场应短于入场」的**退出语义**，不重复报线性曲线/数值。
- **检查清单项**：验证手势下拉关闭比点击打开明显更快；验证 0 档下出场仍瞬时。

#### B-10 · 弹层手势入口不一致：统一入口给 drag handle，绕过调用点没有
- **证据**：`lib/surface/app/overlays.dart:61-70` 默认 `showDragHandle: true`，`isScrollControlled` 显式传入；`lib/surface/pages/search_page.dart:937-940` 直接 `showModalBottomSheet<String>(context: context, builder: ...)`，未走 `ogLShowSheet`、未给 drag handle、未接档位时长。
- **用户感受**：同为长按卡片的动作菜单，有的面板顶部有小横条提示「可下拉关闭」，有的没有，用户不知道哪些能滑 → 手势可发现性不一致、「有时能滑有时不能」的不稳定感。
- **规范依据**：rules/06 §7b「每个手势面声明入口与退出路径，提供非手势等价」；MD3 sheet 可发现手势提示。
- **修复指令**：`search_page.dart:937` 改为调用 `ogLShowSheet<String>`（保留 builder 内容），其它直接 `showModalBottomSheet` 的调用点同样收口；统一 `showDragHandle` 策略（矮菜单也建议给 handle 或统一不给，但全库一致）。
- **检查清单项**：`rg -n 'showModalBottomSheet' lib/` 逐点核对全部走统一入口；验证无 drag handle 时仍有点击遮罩/返回键退出路径。

#### B-11 · 多个对话框绕过统一入口：档位 0 下仍走框架默认动画
- **证据**：绕过 `ogLShowDialog` 直接 `showDialog` 的调用点：`lib/surface/pages/settings_page.dart:760`、`:831`，`lib/surface/app/font_pick.dart:28`，`lib/surface/pages/code_editor_page.dart:427`；统一入口在 `lib/surface/app/overlays.dart:75-82`（仅 `showDialog`，无时长/曲线）。
- **用户感受**：把动效调到 0（「静默」）后，底部面板立刻出现，但这些对话框仍以框架默认的缩放淡入弹出 → 同一次操作里两套节奏，用户觉得「设置没生效、粗糙」。
- **规范依据**：rules/06 §8「duration/easing 从同一 token 读」；§6 reduced motion 全局生效。
- **修复指令**：把上述 4 处 `showDialog` 全部改为 `ogLShowDialog`（保留各自 `barrierDismissible` / builder），并由 `overlays.dart:75-82` 统一在档位 0 下用 `transitionDuration: Duration.zero` / 档位>0 用 `OgLAnim.medium(context)` + `curve`。**跨席边界**：2-C C-15 已报 `ogLShowDialog` 自身未接档位，本条报的是**绕过统一入口的调用点**，二者互补。
- **检查清单项**：`rg -n 'showDialog' lib/` 逐点确认只剩 `overlays.dart` 内一处；档位 0 下弹全部对话框验证零时长。

#### B-12 · 引导页前进/后退同长同向：手势右滑返回与上一步按钮节奏不分
- **证据**：`lib/surface/pages/onboarding_page.dart:193` `nextPage(duration: OgLAnim.pageViewDuration(context))`、`:202-204` `previousPage(duration: OgLAnim.pageViewDuration(context))`——前进与后退同长；`:230` `onPageChanged` 同时接收手势滑动与按钮翻页，二者都走同一时长，无方向区分。
- **用户感受**：引导页右滑「返回上一步」和点「下一步」用完全一样的速度与方向感，手势与按钮的层级关系（前进=深入、后退=回退）没有视觉区分 → 「滑来滑去分不清在第几步」。
- **规范依据**：rules/06 §3「方向承载语义」；§2「exit 比 enter 短」。
- **修复指令**：`onboarding_page.dart:202-204` 的 `previousPage` 用更短的 `OgLAnim.fast(context)` 或 `pageViewDuration * 0.75`；`onPageChanged` 中按 `value < _step` 判断为回退时避免重复动画（手势已自带跟手位移，按钮再叠一次会「双重滑动」）。
- **检查清单项**：手势右滑与按钮「上一步」各测一次，验证回退比前进快、无双重动画。

#### B-13 · 共享元素 Hero 只有起点没有终点：连续性动画根本不成立
- **证据**：`lib/surface/pages/dashboard_page.dart:499` 使用 `OgLSharedTitle(tag: ...)`；`rg -n 'OgLSharedTitle' lib/` 仅此 1 处调用 + 定义（`lib/surface/app/animations.dart:364-385`）。仓库详情页（`lib/surface/pages/repo_page.dart`）**没有**对应同 tag 的 `OgLSharedTitle`。
- **用户感受**：从首页仓库卡片点进详情时，标题名义上要「飞」过去，但目标端没有同名 Hero，飞行到一半就消失/闪回，比不做动画更突兀 → 「东西飞丢了」的不稳定感。
- **规范依据**：rules/06 §1 continuity（shared-element 必须首尾同 tag）；§4c View Transitions「names must be unique per snapshot/assigned dynamically」。
- **修复指令**：在仓库详情页 AppBar 标题处包 `OgLSharedTitle(tag: 'ogl-repo:${fullName}', child: ...)`，tag 与 `dashboard_page.dart:499` 完全一致；若详情页标题由 `Text` 直接渲染，用 `OgLSharedTitle` 包裹并保持 `Hero` 的 `flightShuttleBuilder` 避免字体跳变。若产品不做共享元素，则**删除** `dashboard_page.dart:499` 的半截 Hero（避免飞丢），并同步 `animations.dart:79` 的 `sharedElement` 开关说明。
- **检查清单项**：验证首页→仓库详情的 Hero 首尾同 tag、飞行连续；档位 <2 时 Hero 关闭、退回普通转场不闪。

#### B-14 · 新建/编辑页用普通层级 push，成功与取消返回无语义区分
- **证据**：新建页均以普通 `MaterialPageRoute` push（无 `fullscreenDialog: true`）：`lib/surface/pages/repo_page.dart:2684-2690`（NewIssuePage）、`:3017-3023`（NewReleasePage）、`lib/surface/pages/dashboard_page.dart:338-341`（NewRepoPage）、`lib/surface/pages/gists_page.dart:112-115`（NewGistPage）；`rg -n 'fullscreenDialog' lib/` 无命中。
- **用户感受**：「新建 issue / 仓库 / gist」在语义上是覆盖当前任务的模态创作页，应与「查看 issue」的层级 push 不同；现在都用同一种纵向滑入，且保存后 pop 与点取消 pop 的转场完全一样 → 用户分不清「我完成了」还是「我退出了」。
- **规范依据**：MD3 navigation-patterns（模态/全屏目的地用不同呈现）；rules/06 §3「up = expand/open, down = dismiss」用于模态。
- **修复指令**：4 个新建页的 `MaterialPageRoute` 加 `fullscreenDialog: true`，让其从底部上升（与层级 push 的横向前进区分）；保存成功返回时可经 `OgLNotifier` 给一条 snackbar（属 4-A 范围，此处只用视觉语义），取消则返回直接用 dismiss 方向。若产品坚持层级 push，则在 4 处 route 加统一 tag 注释说明「新建=层级前进」并在文档统一，避免混用。
- **检查清单项**：验证新建页与查看页转场方向不同；验证保存/取消的返回出口清晰。

#### B-15 · 桌面平台无转场适配：全平台共用一套 builder，Rail 切换仍整页横滑
- **证据**：`lib/surface/app/motion.dart:348-352` → `for (final TargetPlatform platform in TargetPlatform.values) platform: builder`，`android/iOS/macos/windows/linux/web/fuchsia` 全部映射到同一个 `_OgLSlideFadeTransitionsBuilder`；`lib/surface/app/client_shell.dart:377-405` 宽屏用 `NavigationRail` + `VerticalDivider`，但 `:504-507` body 仍是整页 `FractionalTranslation` 横滑。
- **用户感受**：在桌面宽窗口里点左侧 Rail，整个内容区横向滑动一下，像手机翻页被硬搬到桌面；桌面语义应是「选中态高亮 + 内容淡入」，没有触控手势时这下横滑显得多余且「晃眼」。
- **规范依据**：MD3 `navigation-patterns.md`「prefer expressive/adaptive scaffolds per device class，而非一个手机模型放大」；rules/06 §3「不要 per screen 混用隐喻」。
- **修复指令**：`motion.dart:348-352` 改为按平台分发——`TargetPlatform.android`/`iOS` 用 shared-axis 横滑（B-02），`macos/windows/linux/web` 用 `FadeTransition` + 极短位移（或无位移）的桌面转场；`client_shell.dart:504-507` 在 `width >= OgLWindowWidths.compact`（已有 `body` 分支 `:321-332`）时禁掉整页横滑，只留 indicator 状态与内容 fade。
- **检查清单项**：桌面 1280×800 与手机 412×915 各验证转场方向/幅度符合平台语义；验证宽屏横滑已移除。

### 轻（3 条）

#### B-16 · 档位 0 的「静默」在手势返回链路上失效
- **证据**：`lib/surface/app/motion.dart:363-373` `_OgLInstantTransitionsBuilder` 直接 `return child`（页级转场瞬时），但 route pop 的系统侧动画由平台 Interpolator 驱动，不受 `pageTransitionsTheme` 控制；`lib/surface/app/og_l_app.dart:118-140` 把 `disableAnimations` 注入 MediaQuery，但未覆盖 route pop 的系统动画。
- **用户感受**：调成「无动画」后，push 进页确实瞬间出现，但手势返回仍能看到系统默认的滑动/半透明过渡 → 「关了动画还动」，无障碍承诺打折。
- **规范依据**：rules/06 §6「prefers-reduced-motion 全局生效，movement 替换为 fade，非 0 直接删除」。
- **修复指令**：在 `og_l_app.dart:55-60` 的 `themeFor` 注入处，档位 0 时同时设置平台侧的 window animation scale（移动端需平台通道；若无法控制则至少在文档明确「系统返回动画不受应用档位控制」并在根 `PopScope` 的 `canPop:false` 分支用瞬时 `Navigator.pop` 跳过过渡）。
- **检查清单项**：档位 0 + 系统「移除动画」双开关下，验证 push/pop 两条路径都无明显位移。

#### B-17 · 改档位后，已在导航栈中的页面返回时仍用旧转场
- **证据**：`lib/surface/app/motion.dart:331-356` `pageTransitions(level)` 按 level 缓存 `PageTransitionsTheme`，`lib/surface/surface_bridge.dart:565/576` 以 motion 为缓存键重建 ThemeData；但 route 的 transitions builder 在 `MaterialPageRoute` push 时确定，改变档位只影响**后续** push 的路由，栈中旧路由返回时仍用它 push 时的 builder。
- **用户感受**：在设置里把动效从档位 3 调到 0，返回上一页时仍看到旧的缩放滑入 → 「设置改了但这一页没变」，跨页一致性断裂。
- **规范依据**：rules/06 §8「两个 duration 真相源会漂移」，此处是「同一栈两套 builder 漂移」。
- **修复指令**：文档明确「档位改变仅对后续导航生效」，或在 `OgLMotionScope` 变化时对当前栈做一次 `Navigator` rebuild（复杂，建议先文档化）；若需强一致，改为让 `buildTransitions` 内每次从 `OgLAnim.quality(context)` 读档位（当前 builder 构造时固定参数 `offset/scaleFrom/curve/window`，改为运行时读取会牺牲缓存，需评估）。
- **检查清单项**：档位 3→0 后返回上一页验证表现并在文档标注生效范围。

#### B-18 · 返回手势后接「回首页」横滑：方向与手势意图冲突
- **证据**：`lib/surface/app/client_shell.dart:203-205` `case OgLBackAction.goHome: _select(OgLShellTab.home);`；`:477` `_from` 按 index 大小定方向。从任意 tab 返回首页时走的是「index 变小 → 从左侧入场」，视觉像「向左翻页」。
- **用户感受**：用户手势意图是「回到起点」，但动画给的是「横向翻到左边一页」；从设置(3) 回首页(0) 跨 3 格仍只滑一小段，方向感与「回到根」的层级感不一致 → 返回链没有「回家」的收敛感。
- **规范依据**：rules/06 §3「方向编码层级；返回应回到来源」；MD3 预测性返回应返回**上一个**目的地而非固定首页。
- **修复指令**：`client_shell.dart:203-205` 维护一个 tab 访问栈（或用 `_visited` 顺序的逆序），`goHome` 改为返回**上一个** tab 而非固定 home；动画方向按实际返回目标决定，并在回首页时用 fade 收敛（无横滑）表达「回到根」。
- **检查清单项**：从设置→发现→首页链路验证返回按原路逐级回退；验证回首页动画为收敛 fade。

---

## 2. 双轴补强（与本席相关的转场/手势切面）

### 轴一 · 启动路线（转场切面）
- 进程启动 → boot splash（`lib/surface/app/boot_splash.dart`）→ `OgLBootFailureApp`（`lib/surface/app/og_l_app.dart:166+`）：失败兜底页为独立 `MaterialApp`，**不继承** `pageTransitionsTheme`，其内无导航；无转场可审，未见问题。
- 首帧 → 登录门（`client_shell.dart:270-277` LoginPage）→ shell：`_buildShell` 在 `_onboardingDone`/`_checked`/登录门三态之间是**直接 return 不同 widget**（`client_shell.dart:260-280`），没有过渡动画 → 「登录成功瞬间硬切到首页」的视觉跳变（与 5-A 启动链路交叉，本席只记转场切面）。**修复指令**：三态切换处包 `AnimatedSwitcher(duration: OgLAnim.medium(context))`。
- 引导清单失败 → 失败页：`OgLBootFailureApp` 独立主题（无 `useMaterial3` 之外的转场注入），未见可审转场。
- 令牌验证态恢复：shell 的 `_checked=false` 态是 `Scaffold(body: Center(CircularProgressIndicator()))`（`client_shell.dart:263-266`），到首页同样是硬切，建议同上 `AnimatedSwitcher`。

### 轴二 · 功能页面矩阵（转场/手势切面逐域已查项）
- **仓库域**（repo_page / repo_tags / commit / pull / release_detail / code_editor / file_preview）：`repo_page.dart:624` TabBarView 无 physics（B-08）；`repo_page.dart:4255-4267` repo settings 标签 dirty PopScope（B-04 覆盖）；新建 issue/release 普通 push（B-14）；code_editor `showDialog` 绕过统一入口（B-11）；其余子页无独立转场策略，复用全局主题。
- **议题域**（issue / new_issue / notifications / dashboard）：new_issue 普通 push（B-14）与 dirty 拦截（B-04）；issue_page 的 sheet/dialog 均走 `ogLShowSheet`/`ogLShowDialog`（已查无绕过）；dashboard 首页 Hero 半截（B-13）、新建仓库普通 push（B-14）。
- **内容域**（gists / gist_detail / new_gist / readme_view / search）：new_gist 普通 push（B-14）；search 的 TabBarView 强制 AlwaysScrollable（B-08）、sheet 绕过统一入口（B-10）。
- **账户域**（login / onboarding / profile / settings 系 / about / legal_text）：onboarding PageView 前后同长（B-12）；settings 两处 showDialog 绕过（B-11）、`settings_page.dart:1731` PopScope 拦截（B-03）；login→shell 硬切（轴一）；about/legal_text 无独立转场，复用全局。
- **工具域**（download_manager / workflow_dispatch / action_log / action_run）：workflow_dispatch dirty PopScope（B-04）；其余页 push/pop 复用全局主题，未发现独立转场分叉。
- **未发现问题的部分**：全库页面均未使用 `Hero` 之外的自定义 `PageRouteBuilder` / `fullscreenDialog`（除 B-14 建议），转场策略确实集中在 `motion.dart` 一处——**策略集中本身是优点**，问题在集中策略的语义与平台分发（B-01/B-02/B-15）。

---

## 3. 修复优先级（供 UX_STABILITY_PLAN 收口）

| 优先级 | 条目 | 理由 |
|---|---|---|
| P0 | B-01 / B-02 / B-03 | 返回链断裂、方向无语义、手势被吞——直接造成「不稳定/漂浮」的触感 |
| P1 | B-04 / B-05 / B-06 / B-13 | 数据丢失风险、返回无反馈、切换无换位、Hero 飞丢 |
| P2 | B-07 ~ B-15 | 平台分发、Tab 统一、弹层手势语义、跨页一致性 |
| P3 | B-16 ~ B-18 | 档位边界与返回链细节 |

---

## 4. 检查清单（查过什么 / 未发现问题的部分）

**已逐条核对并确认无问题的项：**
- [x] `motion.dart:331-356` 的 `_transitionCache` 有界（4 档）+ 只增到 4 就停，缓存策略正确；越界档位现算不写缓存✅（非本席问题，仅确认）。
- [x] `motion.dart:363-373` `_OgLInstantTransitionsBuilder` 档位 0 直接 `return child`，页级转场瞬时✅（问题仅在系统返回链路，见 B-16）。
- [x] `motion.dart:415-419` `_movedTween`/`_fadedTween` 用 `CurveTween.animate` 不注册死监听，规避每帧 `CurvedAnimation` 累积✅（2-C 已审，本席确认未引入手势侧回归）。
- [x] `client_shell.dart:477` 切 tab 的 index 方向判断在「相邻平级切换」语境下方向自洽（问题在跨格/层级语义，见 B-07）✅。
- [x] `client_shell.dart:288-300` 隐藏页用 `TickerMode(enabled:false)` 停表 + `OgLAnimPreloadBoundary` 分组，切 tab 不会让隐藏页烧帧✅。
- [x] `overlays.dart:44-52` 明确 `enableDrag` 沿用默认 true、且不注册 secondary tap，与右键返回不冲突✅（问题在入口一致性 B-10，非手势抢占）。
- [x] `overlays.dart:59-70` sheet 时长由框架控制器管理，避免 pop 同帧 dispose 掐断闭场✅（2-C 已审，本席确认）。
- [x] 全库 `rg -n 'showDialog|showModalBottomSheet'` 的调用点已逐一列出并分类（统一入口覆盖 / 4+1 处绕过见 B-10/B-11）✅。
- [x] `rg -n -i 'predictive|enableOnBackInvokedCallback'` 在 `lib/` 无命中，确认预测性返回未适配（B-03），且仓库未含 `android/` 目录——该项修复需在有平台目录的构建侧完成，本席只能给指令✅。
- [x] `rg -n 'OgLSharedTitle' lib/` 仅 1 处调用 + 定义，确认 Hero 缺目标端（B-13）✅。
- [x] 全部 30 页按五域逐一过转场/手势切面（见轴二），除已列问题外无独立转场分叉✅。
- [x] 本席未重复报告 2-C 已审的 `transitionOffset`/`transitionScaleFrom`/`transitionWindow`/切 tab 透明度/弹簧参数/`blurSigma` 数值问题；所有交叉条目均标注边界✅。
- [x] 只读审计：未修改任何业务代码，未 commit / 未 push；报告文件写入 `docs/UX_CROSS_AUDIT/4-B-transitions.md`✅。

---

> 交付：严重 3 条 + 中 12 条 + 轻 3 条 = **18 条可感知问题**，每条含 `file:line` 证据、用户感受、规范依据、修复指令；检查清单 12 项。跨席边界已显式写明，未与 2-C 重复参数层报告。
