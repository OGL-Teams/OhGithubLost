# 4-C · 微交互与手感（v15 之后真实状态复审）

> 文档戳：2026-11-24 22:53:44 (Asia/Shanghai) · 基线版本 **v15.0.0**
> 席位：批 4 · 4-C 微交互与手感 · 只读审计（未改任何代码）
> 规范：`/var/minis/skills/sota-frontend-design/rules/06-motion-design.md`（§2 时长缓动 / §4b 微交互目录 / §5 合成器契约 / §6 减弱动效 / §7b 手势规格）
> 主审文件：`lib/surface/app/motion.dart`、`lib/surface/app/animations.dart`、`lib/surface/app/client_shell.dart`、`lib/surface/widgets/scroll_aware_action.dart`、`lib/surface/widgets/anim/anim_preload.dart`、`lib/surface/app/overlays.dart`、`lib/surface/app/og_l_app.dart`、`lib/surface/app/og_l_app_bar.dart`
> 旧确证来源：`docs/UX_STABILITY_PLAN.md`（F-14 / F-15 / F-16 / G-09）、`docs/UX_CROSS_AUDIT/2-C-motion.md`、`4-B-transitions.md`

---

## 0. 一句话结论

**动效"制度"建得不错（档位表 + CI 双门禁 + 单一事实来源是真的落地了），但"接线"只接了一半**：档位表里的六个关键数值一个没动（F-15 基本原样），路由 / 对话框 / 主题 / Hero 四条动画完全在档位之外跑（F-14 未修），切 tab 仍是"只有入场、没有接力"（F-16 未修），而"顶栏静止"承诺从未实现（G-09 修法有问题）。用户侧体感：**界面不算躁动（无弹跳、无呼吸灯、无多余装饰），但"跟手"只做到一半**——按下有水波纹（✅）、滚动收边能收（✅）、但切 tab 连点会朝错的方向滑（❌），收边 FAB 的"再点弹出"是全应用唯一带 10% 过冲的动作（❌ 躁动源）。

---

## 1. 闭环核对（属微交互范畴的旧确证）

| 编号 | 旧确证摘要 | 判定 | 证据（可 rg 复现） |
|---|---|---|---|
| **F-15** | 档位表数值越界：错峰末项 ~806ms、`fast` 170ms 超 150、`settle` 10% 过冲、淡入先于位移结束 | **修法有问题（6 项中仅 1 项修好）** | ✅ 已修：`motion.dart:463-465` `_fadedTween` 改为 `Interval(0.0, _windowEnd, easeOut)`，淡入与位移**同窗结束**（旧 `_windowEnd*0.8` 已无）。❌ 未修：`:244-245` `staggerStep 36ms × staggerMaxIndex 16 = 576ms`（末项入场 ≈ 806ms，规则 §2 要求交互类 ≤ 500ms）；`:241` `fast: 170ms`（微反馈上限 150ms）；`:254` `settleCurve: Curves.easeOutBack`（≈10% 过冲，规则 §2 要求 ≤ 2–3%）；`:253` `largeCurve: Curves.easeOutQuint` / `:227` `easeOutQuart`（整页"窜出去"）；`:248` `revealScaleFrom: 0.985` + `:247` `revealOffset: 0.04`（计划要求逐控件位移/缩放归零）；`:196` 档位 1 `transitionOffset: 0.012`（计划写 0.02）。**六项里五项与 v14 逐字相同。** |
| **G-09** | 切 tab 整页含 AppBar 横移 + 半透明鬼影（opacity 0.70） | **修法有问题** | ✅ 已修：`client_shell.dart:498` `Opacity(0.94 + 0.06*t)`、`:499` `t` 夹紧 `[0,1]`、`:473` 位移封顶屏宽 2%、`motion.dart` 控制器上下界收回（`client_shell.dart:436-441` 注释）。❌ 未做：计划原文"**顶栏由壳层持有保持静止，只对内容层做位移**"——`_OgLShellSlide` 包住的是**整个 `IndexedStack`**（`client_shell.dart:325-328`），而每个页面自带 `Scaffold(appBar: OgLAppBar(...))`（`repo_page.dart:539+`、`search_page.dart:729+`），**AppBar 仍在 `FractionalTranslation` 子树内**，仍随页横移（只是从"横飞"缩到 2%）。且 0.94 的透明度下限作用在**整页含顶栏**上 → 切 tab 瞬间整页（含顶栏）对底色"透"一下，形成一层极淡的鬼影（与 2-B 席结论一致）。 |
| **F-14** | 页级路由时长恒 300ms、主题切换恒 160ms、档位 0 在主题/对话框/系统返回处失效 | **未修（三处子项全部维持 v14）** | ① 路由：`rg -n "transitionDuration\|reverseTransitionDuration" lib/` → **0 命中**；39 处 `MaterialPageRoute`（`rg -c MaterialPageRoute lib/` = 39）全用框架默认 300ms，`transitionWindow`（0.42/0.55/0.7）只压缩"运动段"，**时间线本身没压缩** → 档位 1 仍有 ~174ms 死等。② 主题：`og_l_app.dart:96-97` `themeAnimationDuration: OgLAnim.slow(context)`，该 `context` 来自 `og_l_app.dart:64` 的**外层** builder（`OgLMotionScope` 挂在 `MaterialApp.builder` 内，`og_l_app.dart:110-121`）→ `OgLMotionScope.levelOf` 回落 **1** → **恒 160ms**，且**档位 0 也不静默**、系统 reduce-motion 也不静默（外层 MediaQuery 未被改写）。③ 对话框：`overlays.dart:76-84` `ogLShowDialog` 未传 `transitionDuration`/`AnimationStyle` → 框架默认 150ms 缩放淡入，**档位 0 仍动**。④ 附加：**Hero 飞行**（`animations.dart:379` `OgLSharedTitle` → `Hero`）用框架默认 300ms，同样在档位之外，且**系统 reduce-motion 下照飞**。 |
| **F-16** | 切 tab 只有新页入场无旧页退场；平级切换套层级横滑隐喻；跨多格幅度不变；连点被吞 | **未修（仅借 G-09 顺带收敛了幅度）** | ① 无成对接力：`_OgLShellSlide` 仍是"单个 `IndexedStack` + 一次性 `FractionalTranslation`"（`client_shell.dart:494-505`），旧页**没有**对向退场（对比 `motion.dart:487-500` 的 `secondaryAnimation` 分支——路由层有、壳层没有）。② 方向仍由 `index` 大小决定（`client_shell.dart:474`），4 个 tab 平级切换一律横滑，跨 3 格与跨 1 格**同幅度**。③ 连点仍被吞：`client_shell.dart:468-470` `if (_controller.isAnimating) return;` —— 且这不只是"让它跑完"：`IndexedStack` 的 index **已经切到新页**，而 `_from` 仍是**上一次**的方向 → 新页会朝**错的方向**滑入（详见 §3 P1-1）。④ `shellDuration`（档位 110/150/190ms）在壳层**从未被使用**（壳层用弹簧），档位表里三个字段实际是死参数。 |

**闭环小结**：4 条里 **0 条完全修好**；G-09 修法有问题（F-14 / F-15 / F-16 未修）。

---

## 2. 回归核对（v15 去掉整页缩放、切页位移收敛 2%）

| 回归项 | 结论 | 证据 |
|---|---|---|
| 按压反馈 / 水波纹是否还在 | ✅ **还在，未被禁** | `rg -n "splashFactory\|ripple" lib/` → 0 处禁用；`rg -n "MaterialStateProperty" lib/` → 0 处用于关水波纹（仅 `theme.dart:332/340/412-419` 的 icon/listTile 状态色）。框架 `InkWell` 原生水波纹保留，圆形 FAB / 卡片行按压即出墨迹（`repo_page.dart:638` 明确用 M3 `ListTile` 承接行壳）。 |
| 滚动收边回弹是否自然 | ⚠️ **收得干净，但"弹回"过冲** | `scroll_aware_action.dart:170-183`：收边用 `quality.curve`（纯 ease-out），**展开（反向）用 `quality.settleCurve`**——档位 3 是 `Curves.easeOutBack`（`motion.dart:254`，≈10% 过冲）。展开位移量 = 元素尺寸的 75%（圆形 FAB 56dp → 42dp），10% 过冲即**越过落位约 4.2dp 再回弹**。这是全库唯一肉眼可见的"弹一下"，与 F-15 同一根因。阻尼方面：收边本身是曲线（无过冲），**不算过大也不算过小**；档位 1/2 分别为 `easeOut`/`easeOutCubic`，无过冲。 |
| 列表吸顶是否存在 | ⚠️ **顶栏/标签吸顶有，列表内分节吸顶无** | AppBar 走 `OgLAppBar`（`og_l_app_bar.dart:135-152`），未设 `floating`/`pinned` → 使用 AppBar 默认 `pinned: true` → **顶栏吸顶成立**；`repo_page.dart:617` / `search_page.dart:732` 的 `TabBar` 挂在 AppBar `bottom` → **随 AppBar 一起吸顶**（但 `repo_page` 的 `bottom` 高 96dp，含分支条 + TabBar，吸顶占位偏重）。**列表内分节吸顶（`SliverPersistentHeader`）全库 0 处**（`rg -n "SliverPersistentHeader" lib/` → 0），5 个 `CustomScrollView`（`repo_page:2550` / `pull_page:118` / `action_run_page:578` / `commit_page:102` / `issue_page:787`）都用普通 `SliverList`，长列表下"我滚到哪一段了"没有锚点。 |
| 页面转场在低端机是否可能掉帧（重光栅化是否已消除） | ⚠️ **整页重光栅化已消除，页面级缩放确已去掉；但仍有三处遗留** | ✅ 整页缩放确已去掉：`motion.dart:195/222/275` 三档 `transitionScaleFrom` 全为 **1**；`motion.dart:499` 转场强制包 `RepaintBoundary`（过渡期间只重合成）。❌ 遗留 1：档位 3 的**逐项** `AnimatedScale(0.985→1)`（`animations.dart:288-295`，作用于每个 `OgLReveal` 列表项，最多 16 项错峰）→ 每项一次重光栅化，低端机上正是"列表滑动发涩"的来源。❌ 遗留 2：`Hero` 飞行（`animations.dart:379`）自带 shuttle 重光栅化。❌ 遗留 3：主题切换动画 160ms（`og_l_app.dart:96`）会让**整棵树的 ThemeData 变更**逐帧重绘。 |

---

## 3. 新发现（旧审计没抓到、本席范围内）

### P1-1 · 切 tab 连点 → **新页朝错方向滑入 + 起点跳变**（最严重的微交互缺陷）
- **症状**：快速连点两个不同 tab，第二个页面从**上一次的方向**滑入（回退时甚至从左侧滑入），且起点有一个明显"跳"。
- **根因**：`client_shell.dart:468-470` `if (_controller.isAnimating) return;` 直接返回，但此时 `IndexedStack` 的 `index`（`:325-328`）**已经换成新页**；`_from`（`:474`）仍是上一次的方向值；`_controller` 仍带着上一次未跑完的位移 → 新页从旧方向、旧偏移处起滑。
- **修复指令**：`client_shell.dart:455-478` 改为**可中断**：删除 `isAnimating` 早退；取 `_controller.value` 与 `_controller.velocity` 作为弹簧初值（`OgLSpring.run` 已支持 `velocity` 参数，`animations.dart:157-159`），`from` 用当前 `value` 而非硬编码 0，`_from` 始终按**本次** index 差更新；或直接改用 `AnimatedSwitcher` 做旧页/新页成对接力（F-16 的正解）。

### P1-2 · "系统减少动效"对**页级转场、主题切换、对话框、Hero 完全无效**
- **症状**：系统开启「移除动画 / 动画缩放 0」后，页面向左滑入、对话框缩放淡入、主题渐变、标题 Hero 飞行**照常发生**（只有列表入场、收边、弹层时长被关掉）。
- **根因**：`motion.dart:335-370` `OgLMotion.pageTransitions(level)` **只读档位、不读 `MediaQuery.disableAnimations`**；`og_l_app.dart:96` 的主题动画取自外层 context（既拿不到真实档位、也拿不到被改写的 `MediaQuery`）；`overlays.dart:76-84` 对话框完全用框架默认。系统开关只在 `og_l_app.dart:120-121` 写进了 `MediaQuery.disableAnimations`，而**框架级的页面转场 / 主题动画不吃这个字段**。
- **修复指令**：`OgLMotion.pageTransitions` 增加 `systemReduce` 参数（`surface_bridge.dart` 构造主题时传 `MediaQuery.disableAnimationsOf`），为真时返回 `_OgLInstantTransitionsBuilder`；`og_l_app.dart:96-97` 改用 `OgLOAnimQuality.of(current.motionLevel).slow` + 同一 `systemReduce` 短路；`overlays.dart:76-84` 改用 `showGeneralDialog`/自建 `DialogRoute` 并传 `transitionDuration: OgLAnim.medium(context)`（`OgLAnim.quality` 已含 disable 判定 → 档位 0 / reduce 下自然为 0）。

### P1-3 · 悬浮按钮"让路"只覆盖 **1/6 个 FAB**，其余页面 FAB 仍压住内容
- **症状**：在「我的 Gists」「概览」以及仓库页的 3 个 extended FAB 上，滚到底部时 FAB 依然盖住最后几行。
- **根因**：`ScrollAwareAction` 全库**只接入 1 处**（`repo_page.dart:2474-2482`）；`gists_page.dart:137`、`dashboard_page.dart:405`、`repo_page.dart:2768/3074/3324` 的 FAB 均为裸 `FloatingActionButton`。
- **修复指令**：上述 5 处按 `repo_page.dart:2474` 的写法包 `ScrollAwareAction(controller: <该页滚动控制器>, child: <FAB>)`（组件已具备 controller 共享、阈值、近底部强制收起、语义合并，改造为 S 级工作量）。

### P1-4 · 圆形 FAB 的"收边"实际只收到 **57%**（文档承诺 1/4），仍压内容
- **症状**：仓库页圆形「新建」FAB 收边后仍有一多半留在屏内，覆盖最后一行。
- **根因**：`scroll_aware_action.dart:230-247` 的 `_peek`：FAB 直径 56dp，`minVisibleExtent 48 − edgeInset 16 = 32dp` → `floorValue = 32/56 = 0.571`（≤ 0.6 于是取 floor 而非 `peekFactor 0.25`）→ 实际只收走 43%，而文件头与 `repo_page.dart:2472` 的注释都写"只露 1/4"。
- **修复指令**：`scroll_aware_action.dart` 把 `minVisibleExtent` 的语义从"**屏上可见**"改为"**命中区**"（命中区可以由屏幕外 + 边缘留白凑出），或直接给圆形 FAB 传 `peekFactor: 0.25, minVisibleExtent: 32`；并同步修正 `repo_page.dart:2472` 的注释，避免文档与实现漂移。

### P1-5 · 展开回弹用 `easeOutBack`，FAB 会越过落位再弹回（≈4dp 过冲）
- **症状**：滚动收边 FAB 被"点开"时，元素冲过原位一下再回落，读起来像"抖"。
- **根因**：`scroll_aware_action.dart:180` 把 `quality.settleCurve`（档位 3 = `Curves.easeOutBack`，`motion.dart:254`）用作 `CurvedAnimation` 的 `reverseCurve`，而展开位移量是 75% 元素尺寸。
- **修复指令**：`scroll_aware_action.dart:173-183` 展开方向改用 `quality.curve`（纯 ease-out），把 `settleCurve` 只留给"入场位移/缩放"类；同时把 `motion.dart:254` 档位 3 `settleCurve` 从 `easeOutBack` 换为过冲 ≈3% 的自定义 `Cubic`（F-15 计划原文即如此），一并解决 §1 的 F-15 残留。

### P1-6 · 路由转场 300ms 死等 + 位移 3%（与"收敛到 2%"的口径不一致）
- **症状**：推进二级页时，新页在 ~126ms 就滑到位，随后约 170ms **页面静止不动**，期间再点返回会有"迟一下才退"的迟滞；且页级位移实际是屏宽 3%（档位 2/3，`motion.dart:224/249`），不是对外口径的 2%（2% 只落在 tab 切换 `client_shell.dart:473`）。
- **根因**：`transitionDuration` 全库 0 命中 → 框架默认 300ms；`transitionWindow` 只压缩运动段不压缩时间线；`transitionOffset` 与 `shellOffset` 各自独立、未统一上限。
- **修复指令**：在 `MaterialPageRoute` 的统一工厂（建议新增 `lib/surface/app/og_l_route.dart`：`OgLPageRoute extends MaterialPageRoute`，`transitionDuration: OgLAnim.medium(context)` / `reverseTransitionDuration: OgLAnim.fast(context)`）里一次收口 39 处调用点；把 `transitionOffset` 统一夹到 ≤0.02，或在文档里把"切页位移 2%"改成"tab 2% / 路由 3%"。

### P2-1 · `OgLAppBar` 的滚动渐变每 ~1.2px 就重建**整个 AppBar**
- **症状**：滚动时顶栏偶有轻微跳帧（低端机更明显）。
- **根因**：`og_l_app_bar.dart:53-56` `_kStep = 0.01` / `_kRange = 120` → 每滚 1.2px 触发一次 `ValueNotifier`，而 `ValueListenableBuilder` 包住的是**整个 `AppBar`**（`:137-152`），标题/操作按钮/底栏一并重建——文件头注释"只让包着背景色的那层重建"与实现不符。
- **修复指令**：把 `AppBar` 拆成"静态部分"与"背景层"两层，只让背景层（`Container(color: merged)`）监听 `_progress`；或把 `_kStep` 提到 0.05。

### P2-2 · 档位 3 的错峰末项 ≈ 806ms，用户等的是"页还在动"
- **症状**：档位 3 下列表最后一批项入场拖到 ~0.8s，滑到底时列表还在轻微闪。
- **根因**：`motion.dart:244-245`（36ms × 16）。
- **修复指令**：`staggerStep → 24ms`、`staggerMaxIndex → 6`（计划原文，合计 ≤ 374ms），或对超限项改为 `staggerOf` 返回 `Duration.zero` 的"零延迟同时入场"。

### P2-3 · `fast = 170ms`（档位 3）超出微反馈 150ms 上限
- **症状**：按钮/开关类短反馈偏"黏"。
- **根因**：`motion.dart:241`。
- **修复指令**：`fast → 150ms`（计划原文）。

### P2-4 · `shellOffset` 在两处被"二次封顶"，档位表失去唯一事实来源
- **症状**：档位 3 的 `shellOffset 0.05` 永远不生效（实际 0.02），用户改档位看不到差别 → "降档/升档无感"。
- **根因**：`client_shell.dart:473` `.clamp(0.0, 0.02)`；档位表本身仍写 0.05（`motion.dart:252`），`isNotHeavierThan` 单调性测试测不出来。
- **修复指令**：把 2% 上限直接写进档位表（档位 1/2/3 = 0.012/0.02/0.02），删除 `client_shell.dart:473` 的 clamp；`shellDuration` 若确实不用，从档位表删除并更新 `isNotHeavierThan` 与单测。

### P2-5 · 档位 0 并非"全静默"：框架水波纹、对话框、路由时间线仍在动
- **症状**：选"最低档位"后仍有对话框缩放、页面切换时间线（虽然无位移）、按钮水波纹。
- **根因**：档位 0 只让**我们自己的**动画归零（`motion.dart:266-289` 全部 `Duration.zero`），框架内置动画（水波纹 ~200ms、对话框 150ms、路由 300ms）不受档位表约束。
- **修复指令**：`og_l_app.dart:110-121` 在档位 0 时给 `MaterialApp.theme` 装 `splashFactory: NoSplash.splashFactory`（保留 100ms 透明度反馈更佳：见规则 §6 "reduced ≠ none"），并把 F-14 的路由/对话框时长接档位后，档位 0 才真正静默。

### P2-6 · 全库零触感反馈
- **症状**：写操作成功、切换、收边等动作没有任何触觉确认。
- **根因**：`rg -n "HapticFeedback" lib/` → 0 命中。
- **修复指令**：在统一的成功/危险操作出口（`overlays.dart` 的 `ogLConfirm` 成功分支、`notifier.dart` 的 success SnackBar）加 `HapticFeedback.mediumImpact()` / `selectionClick()`，需在设置里跟随"触感反馈"总开关。

### P2-7 · 收边态的点击层无任何按压反馈
- **症状**：点收边 FAB 时"没有按下感"，只看到元素弹出来。
- **根因**：`scroll_aware_action.dart:366-372` 用的是 `GestureDetector(onTap:)`，无墨迹 / 无 `InkWell`。
- **修复指令**：该层改用 `InkWell`（`onTap` 保留，`customBorder` 跟随原控件圆角），或在 `GestureDetector` 外再叠一层 `AnimatedOpacity` 的 60ms 压暗反馈。

### P2-8 · 搜索输入有 300ms 防抖，输入后结果"迟一拍"
- **症状**：输入后 300ms 才开始出结果，快速连打有明显的滞后感。
- **根因**：`search_page.dart:1217` `_debounceWindow = 300ms`（属等待语义、不在动效门禁内）。
- **修复指令**：改为 200ms，并在输入框内加一个"已输入、检索中"的轻量状态（与 `async.dart:56` 的 `loadDebounce` 统一成一个常量）。

### P2-9 · 阻尼/过冲在壳层被夹紧"吃掉"，档位 3 的弹簧回弹不可见
- **症状**：档位 3 的切 tab 弹簧（`springDamping 35`，ζ≈0.63）本应轻微回弹，实际被 `client_shell.dart:497` 的 `t.clamp(0,1)` 完全抹平 → 升到档位 3 与档位 2 手感几乎相同。
- **根因**：夹紧是为解决 G-09 过冲，但把"回弹"也一并夹没了。
- **修复指令**：不再对 `t` 夹紧，改为对**位移结果**夹紧（`translation = _from * (1 - t)` 允许 t 略超 1 时位移略微越过 → 视觉 1–2% 的回弹），同时保证不越出屏幕。

### P3（记录，不建议本轮改）
- `client_shell.dart:447-452` 注释声称"提前建好控制器 = 切 tab 的预加载"，但 `AnimationController(duration: Duration.zero)` 本身几乎不耗资源，真正的预加载在 `anim_preload.dart`；注释语义与实现不符，易误导后续维护者。
- `anim_preload.dart` 本身无时长/曲线硬编码，全部按档位策略表（`kOgLAnimPreloadPolicies`），`disabledAnimations` 时降为 0 级不预加载（`:769-772`）——**这块是全库动效纪律的正面样板**。

---

## 4. 反馈延迟专项（点击 → 视觉响应）

| 交互 | 视觉响应延迟 | 判定 |
|---|---|---|
| 按钮 / 列表行按压 | 框架 `InkWell` 墨迹在指针按下同帧出现（无自定义 splashFactory，rg 0 命中） | ✅ < 100ms |
| 卡片行 / 发现行（`search_page:221`、`discover_rows:66`） | 同上 | ✅ |
| 收边 FAB 轻点展开 | 无按压反馈；展开动画 `medium` 120–230ms 后才有位移 | ⚠️ 0ms 但无"按下"确认 |
| 切 tab | 位移在 `didUpdateWidget` 同帧起手（弹簧） | ✅ 跟手 |
| 页面前进 | 路由 300ms 时间线，运动只占前 126–210ms；**实际"看到变化"延迟 ≈ 0ms（淡入同窗）**，但"完全可交互"要等 300ms | ⚠️ 中等 |
| 对话框 | 框架默认 150ms 缩放淡入 | ✅ 在 200ms 内 |
| 底部弹层 | `OgLAnim.sheetDuration` 130–200ms | ✅ |
| 搜索输入 → 结果 | 300ms 防抖 + 网络 | ❌ > 100ms（且非动画，是节流） |
| 主题切换 | 160ms 恒定（不随档位） | ⚠️ |

**结论**：纯点击→视觉响应链路 **没有超过 100ms 的情况**；唯一的 >100ms 是搜索防抖（属节流，不是动画延迟）。

---

## 5. 动效一致性（同类操作是否一致）

| 操作族 | 实际时长/曲线 | 一致？ |
|---|---|---|
| 页面前进/返回 | 框架 300ms + `largeCurve`（档位 3 = `easeOutQuint`） | ❌ 与其它所有族不同源 |
| tab 切换 | 弹簧（档位无关时长，`shellDuration` 死参数） | ❌ 与路由族不同源 |
| 列表项入场 | `medium` 170–230ms + `settleCurve`（档位 3 带 10% 过冲） | ✅ 内部一致 |
| 大体积内容切换（loading→data） | `stateSwapDuration` 110–180ms | ✅ |
| 底部弹层 | `sheetDuration` 130–200ms，**出/入等长且未设曲线**（`overlays.dart:66-70` `AnimationStyle` 只有 duration/reverseDuration，曲线走框架默认 ≈ linear） | ❌ 弹层"机械匀速"，与全库 ease-out 阶梯不一致（F-17 残留） |
| 对话框 | 框架 150ms 缩放淡入 | ❌ 与弹层不同族 |
| 引导页翻页 | `pageViewDuration` 160–260ms | ✅ 自身一致 |
| 收边/展开 | `fast` 90–170 / `medium` 120–230ms | ✅ 自身一致，但展开带过冲 |

**判定**：全库存在 **4 套并行的时长来源**（档位表 / 框架路由 / 框架对话框 / 框架弹层曲线），同类操作（"进入一个更深的层"：路由 vs 弹层 vs 对话框）时长与曲线各不相同 → 这是"躁动"与"不一致"的根因，且全部指向 F-14 / F-17。

---

## 6. 档位 0 与"减少动效"专项

- **档位 0 自有动画**：确实全静默。`motion.dart:266-289` 全部 `Duration.zero` / `offset 0` / `scale 1` / `spring null`；`animations.dart:96-101` `quality()` 在 `enabled()==false` 时回落档位 0；`client_shell.dart:461-465` 档位 0 直接 `_controller.value = 1`（无位移无淡入）。
- **绕过档位的硬编码动画（rg 结果）**：**4 处 + 1 类**
  1. `og_l_app.dart:96` 主题动画 160ms（context 取错层级，恒档位 1）；
  2. 路由转场 300ms（39 处 `MaterialPageRoute` 无 `transitionDuration`）；
  3. `overlays.dart:76-84` 对话框 150ms（框架默认）；
  4. `animations.dart:379` Hero 飞行 300ms（框架默认）；
  5. （类）框架内建水波纹 ~200ms —— 我们没有 `splashFactory` 干预，档位 0 下仍播。
  - 非动画类硬编码时长（不算绕过档位）：`search_page.dart:1217` 防抖 300ms、`async.dart:56/61` 300ms、`code_editor_page.dart:153` 900ms 草稿定时。
  - `lib/surface/**` 内**动画时长硬编码 = 0 处**（`rg -n "Duration\(milliseconds:" lib/surface/` 只命中 `motion.dart` 档位表、`async.dart` 等待语义、`code_editor_page.dart` 定时器），**CI 门禁 `tool/motion_audit.py` + `tool/motion_coverage_audit.py` 双保险真实有效**（本席复核了两条规则的白名单与豁免逻辑，未发现放大豁免）。
- **系统 reduce-motion 是否全局生效**：❌ **不全局**。生效范围 = 列表入场、收边、弹层、tab 弹簧（`OgLAnim.enabled` → `MediaQuery.disableAnimationsOf`）；**不生效** = 页级转场、主题切换、对话框、Hero、框架水波纹（见 P1-2）。另外 `main.dart:152-166` 启动时会提示"系统已关闭动画"，但提示承诺的是"过渡与反馈动画将不可见"——**与实际不符**（页级过渡仍可见），属误导性文案（P1-2 的连带项）。

---

## 7. 用户满意度视角

**「跟手」吗？—— 一半跟手。**
- 跟得上的部分：按下有水波纹（框架原生，未被禁）；切 tab 位移同帧起手；列表项入场不阻塞交互（`OgLReveal` 用 `Timer` 而非 `Future.delayed`，`animations.dart:190-215` 已修掉闭包持有型泄漏）；滚动收边的方向判定用"累积同向位移 + 换向清零 + 忽略 <1px 抖动 + 忽略 >一屏瞬移"（`scroll_aware_action.dart:270-330`），**不抽搐**。
- 跟不上的部分：① 快速连点 tab 时新页朝错方向滑入（P1-1）；② 收边 FAB 点击无按压反馈（P2-7）；③ 搜索输入 300ms 防抖（P2-8）；④ 页面推进后还有 174ms 死等（P1-6）。

**「安静」还是「躁动」？—— 偏安静，但有 3 处躁动源。**
- 安静的部分：没有装饰性动效（无视差、无无限循环、无自动轮播）、列表错峰有上限、隐藏页 `TickerMode(enabled: false)` 停表（`client_shell.dart:295-320`，避免"看不见的页面偷偷烧帧"）、`OgLReveal` 的错峰延时可取消不泄漏。
- 躁动源：① 档位 3 的 `easeOutBack`（10% 过冲）被用在**每一个**控件的入场位移与收边 FAB 的展开上（P1-5）；② 档位 3 的逐项缩放 0.985（16 项错峰）导致列表滑动期重光栅（§2 遗留 1）；③ 切 tab 瞬间整页（含顶栏）透明度掉到 0.94 再回升——一个极淡的"整页透一下"，是用户最容易捕捉到的"躁"（G-09 残留）。
- 一句话给用户：**这个应用的动效"制度"是干净的，"接线"是漏的**；用户看到的界面安静，但按下→变化之间有几处该到未到、该止不止。

---

## 8. 本席对三问的回答

**问一 · 闭环核对**：属微交互的 4 条旧确证——**F-15 修法有问题**（6 项仅"淡入与位移同窗"修好，错峰 576ms / fast 170ms / settle 10% 过冲 / largeCurve easeOutQuint / 逐控件位移缩放 5 项原样未动）、**G-09 修法有问题**（透明度下限与 2% 位移已落，"顶栏静止"从未实现：AppBar 仍在位移子树内）、**F-14 未修**（路由 300ms / 主题恒 160ms / 对话框 150ms / 系统返回四处子项全部维持 v14）、**F-16 未修**（无成对接力、方向仍由 index 决定、跨格幅度不变、连点被吞且方向错乱）。**0 条完全修好。**

**问二 · 回归**：v15"去整页缩放"**成功**（三档 `transitionScaleFrom` 全为 1、转场强制 `RepaintBoundary`），但"去缩放"只做到页面级，档位 3 的逐项 `AnimatedScale(0.985)` 与 Hero 飞行仍会重光栅化；"切页位移收敛 2%"**只覆盖 tab 切换**，页级路由位移仍是 3%。按压反馈与水波纹**未被禁用**（0 处 `splashFactory` / 0 处禁用水波纹的 `MaterialStateProperty`）。滚动收边**收得干净但弹得过头**（展开用 `easeOutBack`，越位 ≈4dp）。列表吸顶**只有 AppBar/TabBar 吸顶，列表内分节吸顶 0 处**。低端机掉帧风险**未完全消除**（逐项缩放 + Hero + 主题动画三处）。

**问三 · 新发现**：最严重两条——①**切 tab 连点朝错方向滑入**（P1-1，`client_shell.dart:468-470` 的 `isAnimating` 早退与已切换的 index 竞态）；②**系统"减少动效"对页级转场/主题/对话框/Hero 完全无效**（P1-2），且 `main.dart:152-166` 的提示文案与实际不符。其余为：FAB 让路只覆盖 1/6 处（P1-3）、圆形 FAB 实际只收 57%（P1-4）、展开回弹过冲（P1-5）、路由 300ms 死等与 3% 位移口径不一（P1-6）、AppBar 滚动渐变整栏重建（P2-1）、档位 3 错峰末项 806ms（P2-2）、`fast 170ms`（P2-3）、`shellOffset` 二次封顶致升档无感（P2-4）、档位 0 非全静默（P2-5）、零触感反馈（P2-6）、收边点击无按压反馈（P2-7）、搜索 300ms 防抖（P2-8）、壳层弹簧回弹被夹紧吃掉（P2-9）。

---

## 9. 已检查清单（覆盖声明）

**已完整阅读的文件**（逐行）：`lib/surface/app/motion.dart`（525 行全文）、`lib/surface/app/client_shell.dart`（509 行全文）、`lib/surface/widgets/scroll_aware_action.dart`（395 行全文）、`lib/surface/app/animations.dart`（全文）、`lib/surface/app/overlays.dart`（弹层/对话框段）、`lib/surface/app/og_l_app.dart`（主题与 builder 段 + `OgLScrollBehavior`）、`lib/surface/app/og_l_app_bar.dart`（全文）、`lib/surface/widgets/anim/anim_preload.dart`（头部策略表 + `OgLAnimPreloadBoundary`）、`lib/surface/settings.dart`（档位解析段）、`lib/main.dart`（reduce-motion 检测段）、`lib/surface/pages/repo_page.dart`（FAB / TabBar 段）、`lib/surface/pages/search_page.dart`（TabBar / 列表行段）、`lib/surface/pages/download_manager_page.dart`（AnimatedSwitcher 段）、`lib/surface/pages/onboarding_page.dart`（PageView 段）。

**已 rg 全库核查**：`Duration(milliseconds:/seconds:)` 硬编码（lib/ 与 lib/surface/）、`splashFactory|ripple|MaterialStateProperty|WidgetStateProperty`（水波纹禁用）、`transitionDuration|reverseTransitionDuration`（路由时长）、`MaterialPageRoute|PageRouteBuilder|Navigator.push`（39 处）、`AnimationController(|animateTo(|animateWith(|Tween<`（全部动画控制器）、`ScaleTransition|AnimatedSwitcher|AnimatedOpacity|AnimatedSlide|AnimatedScale`、`Curves.linear`、`SliverPersistentHeader|PersistentHeaderDelegate|CustomScrollView|slivers:`（吸顶）、`ScrollPhysics|overscroll|BouncingScrollPhysics`、`ScrollAwareAction`（接入点）、`Draggable|onPanUpdate|onLongPressDraggable|ReorderableListView`（拖拽）、`HapticFeedback|SystemSound`（触感）、`Hero(`、`TabBar|TabController`、`FloatingActionButton`（6 处）、`InkWell|InkResponse|GestureDetector`（14 处）、`disableAnimations|reduceMotion`、`themeAnimationDuration`、`AnimationStyle`。

**已核查的工具与测试**：`tool/motion_audit.py`（时长/隐式动效/缩放/模糊/匀速五条规则 + 白名单 + 逐行豁免）、`tool/motion_coverage_audit.py`（裸动效 + 消费点下限）。

**未覆盖（超出本席范围或需真机）**：真机帧率与低端机实测、屏幕阅读器实际播报顺序、触觉马达实测、iOS 端表现、动效相关的既有单测（`test/` 下若有 motion 单测未逐一执行——本席为只读审计，未运行测试套件）。
