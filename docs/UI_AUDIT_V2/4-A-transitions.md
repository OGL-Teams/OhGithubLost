# 批 4 · 动效与反馈 · A 席 —— 页面转场复审（v15.0.0 之后）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 4 · 动效与反馈 · A（转场复审）**
> - 审计对象：`lib/surface/app/motion.dart`（档位质量表 + `_OgLSlideFadeTransitionsBuilder` + `_OgLInstantTransitionsBuilder` + `OgLMotion.pageTransitions` + `OgLMotion.disableAnimations`）、`lib/surface/app/client_shell.dart`（`PopScope` 返回链 + `_OgLShellSlide` 切页动画 + `_buildShell` 三态）、`lib/surface/app/og_l_app.dart`（`themeAnimationDuration` + `MediaQuery.disableAnimations` 注入）、`lib/surface/app/animations.dart`（`OgLAnim` / `OgLSpring` / `OgLReveal` / `OgLSharedTitle`）、`lib/surface/app/overlays.dart`（sheet / dialog）、`lib/surface/surface_bridge.dart:578`（`pageTransitionsTheme` 注入）、`lib/main.dart:155`（系统动画关闭提示）
> - 仓库：`/root/OhGithubLost`，HEAD = `46981c0`（2026-11-24 21:28:42 +0800），`pubspec.yaml:21` version = **15.0.0+150000**
> - 审计时间：**2026-11-24 22:52:10 (LCL)**　语言：zh-Hans
> - 参照规范：`sota-frontend-design/rules/06-motion-design.md`（§1 目的检验 / §2 时长缓动 / §3 方向语义与编排 / §5 合成器契约 / §6 减弱动效 / §7b 手势规格）、`docs/UX_CROSS_AUDIT/2-C-motion.md`（v14 C-01…C-20）、`docs/UX_CROSS_AUDIT/4-B-transitions.md`（v14 B-01…B-18）、`docs/UX_STABILITY_PLAN.md`（F-12…F-15）
> - **只读审计**：未改动任何代码，未 commit / push。唯一产出即本文件。
> - 禁读纪律遵守：全程只读项目 `lib/`、`docs/`、`tool/`；**未读取** `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk` 或 pub 缓存包源码；未调用 dart（本席为纯静态审计，无需 format）。

---

## 0. 方法与基线（全部 rg 可复现）

| 指标 | v14 实测 | **v15 实测（本席复核）** | 期望 |
|---|---|---|---|
| 转场是否消费 `secondaryAnimation` | 0 次（仅签名） | **1 处实质消费**：`motion.dart:481-496`（旧页对向退场） | ≥1 |
| 转场方向 | Y 轴单向（`Offset(0, offset)`） | **X 轴 shared-axis**：`motion.dart:476` `Offset(offset,0)` / `:491` `Offset(-offset,0)` | 左右 |
| 整页缩放（`transitionScaleFrom`） | 0.99 / 0.975 | **三档全 1**（`motion.dart:197/224/250`），`buildTransitions` 内无 `ScaleTransition` | 1 |
| 切 tab 最低透明度 | 0.70 | **0.94**（`client_shell.dart:498`） | ≥0.94 |
| 切 tab 位移 | `shellOffset` 0.05 未封顶 | **clamp 到 0.02**（`client_shell.dart:473`） | ≤2% 屏宽 |
| 路由时长接档位 | 0 处 | **仍 0 处**：`rg -n "transitionDuration" lib/` 无命中；`MaterialPageRoute` **39 处** | 全部接档位 |
| 主题动画接档位 | 恒 160ms | **仍恒 160ms**：`og_l_app.dart:96` 用 `OgLAnim.slow(context)`，该 context 在 `OgLMotionScope` 之外 → `OgLMotionScope.levelOf` 回退 **1**（`motion.dart:487` 语义） | 按真实档位 |
| 页级转场读系统 `disableAnimations` | 0 命中 | **仍 0 命中**：`surface_bridge.dart:578` 只由 `settings.motionLevel` 决定 | 必须读 |
| 档位 0 静默 | 主题/对话框失效 | 页面转场 ✓（`motion.dart:341-342` → `_OgLInstantTransitionsBuilder`）／切 tab ✓／sheet ✓／**对话框 ✗**／**主题 ✗** | 全链路静默 |
| 档位 3 错峰末项可见时刻 | ≈806ms | **仍 ≈806ms**（`motion.dart:244-245`：`36ms × 16` + `230ms`） | ≤400ms |
| 档位 3 `fast` | 170ms | **仍 170ms**（`motion.dart:241`） | ≤150ms |
| 档位 3 `settleCurve` | `easeOutBack`（≈10% 过冲） | **仍 `easeOutBack`**（`motion.dart:254`） | 过冲 ≤3% |
| 档位 3 `largeCurve` | `easeOutQuint` | **仍 `easeOutQuint`**（`motion.dart:253`） | M3 emphasized decelerate |
| 统一入口外的 `showDialog` | 4 处 | **仍 4 处**（`settings_page.dart:763/834`、`code_editor_page.dart:427`、`font_pick.dart:28`） | 0 处 |
| 统一入口外的 `showModalBottomSheet` | 1 处 | **仍 1 处**（`search_page.dart:951`） | 0 处 |
| Hero 首尾同 tag | 仅起点 | **仅起点**：`dashboard_page.dart:496-497` 有 `OgLSharedTitle`，`repo_page.dart` 无同 tag 终点 | 首尾同 tag |
| `TabBarView` 档位化 | 1/2 处 | **1/2 处**：`search_page.dart:742` 有 `physics` 档位，`repo_page.dart:625` 无 | 2/2 |

---

## 1. 闭环核对（旧确证逐条判定）

| 编号 | 旧问题 | 判定 | 依据与残留 |
|---|---|---|---|
| **F-12** 转场不消费 `secondaryAnimation`、push/pop 同向纵移 | **已修** | `motion.dart:481-496` 新增旧页对向退场：push 时 `secondaryAnimation` 0→1 → 旧页 `Offset.zero → Offset(-offset, 0)` 且透明度 1→0.65；pop 时 1→0 → 旧页滑回原位。方向改为 **shared-axis X**：`motion.dart:476` 入场 `Offset(offset,0)→0`，`:491` 退场 `0→Offset(-offset,0)`；push 时新页从右入、旧页向左让位，pop 时两者同时向右 —— 前进=向左、返回=向右，方向语义成立。**残留**：① 退出分支对 `secondaryAnimation` 无保护（见 4-A-P2-09）；② 旧页退场终点 0.65 透明度与新页 0→1 淡入**叠加**，交叉瞬间出现"两层半透明"的灰帧（见 4-A-P2-08）。 |
| **F-13** 返回链吞手势 / 壳层 `pop()` 绕过 dirty 确认 | **已修（有残留）** | `client_shell.dart:256-258` 改为**条件式** `canPop: navigatorCanPop`（上方有可退路由才 true），`:178-180` 用 `navigator.maybePop()` 让目标路由自己的 `PopScope`（dirty 表单确认）决定。系统预测性返回手势在有子路由时可 1:1 跟手。**残留**：`_backHandling` 闸门（`:151/:170-173`）在异步确认窗口内把**第二次返回静默丢弃**，无任何反馈（旧 4-B B-05 未修，见 4-A-P2-01）。 |
| **F-14** 档位接线失效（路由时长恒 300ms / 主题恒 160ms / 档位 0 在主题·对话框·系统返回失效） | **未修** | ① 路由时长：`rg -n "transitionDuration\|reverseTransitionDuration" lib/` **0 命中**，39 处 `MaterialPageRoute` 全用框架默认 300ms；`transitionWindow`（0.42/0.55/0.7）只压缩了"运动段"，**时间线本身没压缩** → 每级仍留 90–174ms 死等。② 主题：`og_l_app.dart:96-97` 仍是 `OgLAnim.slow(context)`，而该 `context` 在 `MaterialApp.builder`（`og_l_app.dart:110` 挂 `OgLMotionScope`）**之外** → `OgLMotionScope.levelOf` 回落 1 → 恒 160ms，**档位 0 也不静默**。③ 对话框：`overlays.dart:80-83` 的 `ogLShowDialog` 未传 `transitionDuration` → 恒用框架默认（150ms 缩放淡入），**档位 0 仍动**。④ 系统返回：见 F-13 残留。**三条子项全部维持 v14 状态。** |
| **F-15** 时长/位移失配（错峰越界 / fast 170ms / settle 10% 过冲 / 淡入先于位移结束） | **修法有问题（部分修）** | ✅ 已修：「淡入先于位移结束」——`motion.dart:433` 的 `_fadedTween` 已改为 `Interval(0.0, _windowEnd)`，与位移同窗结束（旧 C-11）。❌ 未修：`motion.dart:244-245` 错峰 36ms×16 = 576ms（末项 ≈806ms）；`:241` `fast: 170ms`；`:254` `settleCurve: Curves.easeOutBack`（≈10% 过冲，套在**每个**控件上）；`:253` `largeCurve: Curves.easeOutQuint`（整页"窜出去"）。另 `:196` 档位 1 `transitionOffset` 仍是 0.012（计划写 0.02）。 |
| **C-01** 整页转场含全页缩放（0.99 / 0.975） | **已修** | `motion.dart:197/224/250` 三档 `transitionScaleFrom: 1`；`buildTransitions`（`:437-501`）内**无 `ScaleTransition`**，只有 `SlideTransition` + `FadeTransition` + `RepaintBoundary`；`tool/motion_audit.py:75` 的门禁禁止 `ScaleTransition(` 出现在 `motion.dart` / `animations.dart` 之外（白名单 `motion_audit.py:32-35`）。全页缩放与"重新光栅化导致页面级卡顿"的根因已消除。 |
| **C-05** 切 tab 时整页透明度压到 0.70（半透明鬼影） | **已修** | `client_shell.dart:498` → `opacity: (0.94 + 0.06 * t)`，最低 0.94（仅 6% 亮度变化，且与位移同窗结束）。"漂"的直接来源已去除。 |

**闭环小结**：6 条中 **3 条已修（F-12、C-01、C-05）**、**1 条已修有残留（F-13）**、**1 条修法有问题（F-15，仅淡入同窗一项修好）**、**1 条完全未修（F-14：路由时长 / 主题动画 / 对话框 / 系统返回四处档位接线）**。

---

## 2. 回归（v15 转场四项大改的实际观感）

### 2.1 「有方向、无漂浮」是否成立

| 观感维度 | v15 现状 | 判定 |
|---|---|---|
| **方向感** | 前进=新页自右向左入 + 旧页向左让位；返回=新页向右退 + 旧页向右滑回。方向恒定、不随 push/pop 混淆（`motion.dart:469-476`） | ✅ **成立**。用户能读出"往里走 / 往回走" |
| **漂浮感** | 整页缩放已删（C-01）；切 tab 最低透明度 0.94（C-05）；`RepaintBoundary` 包住转场（`:499`）只重合成不重绘 | ✅ **基本消除**。剩余的"灰感"来自新页淡入与旧页退场淡出的**叠加**（4-A-P2-08） |
| **退场是否接力** | `secondaryAnimation` 被实质消费（`:481-496`）：旧页被推走并降到 0.65，pop 时**回弹归位** | ✅ **接力成立**（一次 push = 一进一出同时发生，不再是"旧页凭空消失"） |
| **位移量是否在合理范围** | 页面转场 `transitionOffset` 0.012/0.03/0.03 = **屏宽 1.2% / 3.0% / 3.0%**（412dp 手机 ≈ 5dp / 12dp / 12dp）；切 tab 被 `clamp(0.0, 0.02)`（`client_shell.dart:473`）= **屏宽 2.0%** | ⚠️ **切 tab 在 2% 边界上（合规但已顶格）**；页面转场 3.0% **略超 2%** 判据，但绝对值仅 ≈12dp，观感不可察觉，可接受 |
| **档位 0 是否完全无动画** | 页面转场 → `_OgLInstantTransitionsBuilder`（`motion.dart:341-342/369-381`，直接 `return child`）✅；切 tab → `OgLAnim.enabled` 为 false 时 `_from=0` 且 `value=1` ✅；sheet → `sheetDuration=0` ✅；**对话框 ✗**（`overlays.dart:80` 无档位）；**主题切换 ✗**（`og_l_app.dart:96` 恒 160ms） | ⚠️ **仅页面/切页/sheet 静默；对话框与主题仍动** |

### 2.2 回归引入的新风险

1. **切 tab 的档位差异被 clamp 抹平**：`shellOffset` 档位 1/2/3 = 0.02/0.035/0.05，但 `client_shell.dart:473` 一律 clamp 到 0.02 → **三档在切页上完全等价**，"降档=降质量"的承诺在切页这一高频动作上失效（档位 3 的弹簧过冲也被 `:492` 的 `clamp(0,1)` 吃掉）。观感上不是"错"，但**档位表在说谎**。
2. **弹簧"丝滑"兑现不了**：档位 3 刚度 784 / 阻尼 35（ζ≈0.63，理论过冲 8.1%），但位移只有屏宽 2% ≈ 8dp，且被 clamp → 可见过冲 <0.2px。**用户看到的仍只是"滑一下"，不是"弹一下"**（旧 C-09 未修）。
3. **`CurveTween` 替换 `CurvedAnimation` 是纯收益**：`motion.dart:429-433` 用 `CurveTween.animate(parent)` 替代 `CurvedAnimation`，避免每帧新建永不 `dispose` 的 statusListener（7.4.1 资源修复），且曲线取值逐点一致。**这是 v15 在转场层最扎实的一处改动，无回归。**

---

## 3. 新发现（本轮旧审计未抓到 / 未闭环）

> 分级：**P0** = 用户完全无法使用 / 数据丢失 / 安全；**P1** = 明显影响使用体验或一致性；**P2** = 打磨。
> 本席范围内 **无 P0**（转场不导致数据丢失或不可用）。以下 P1 5 条、P2 11 条。

### P1

#### 4-A-P1-01 · 页级转场完全无视系统「移除动画」与 App 内 reduceMotion —— 且启动横幅还宣称它已被静默
- **症状**：系统开启「开发者选项 → 动画时长 0」或「无障碍 → 移除动画」后，页面切换**照样滑入滑出**；而 `main.dart:155-163` 主动弹出横幅告诉用户"应用内的页面切换与控件反馈动画将不可见" —— **提示与实际相反**。
- **根因**：`surface_bridge.dart:578` → `pageTransitionsTheme: OgLMotion.pageTransitions(motionLevel)`，**只吃设置里的档位**；系统信号只写进了 `og_l_app.dart:120-121` 的 `MediaQuery.disableAnimations`，而 `_OgLSlideFadeTransitionsBuilder.buildTransitions`（`motion.dart:437-501`）**从不读** `MediaQuery.disableAnimationsOf(context)`。同理 App 内 `reduceMotion`（`settings.dart:429`）→ `OgLMotion.disableAnimations`（`motion.dart:300-305`）只改 MediaQuery，**页级转场同样不受影响**。
- **规范依据**：rules/06 §6「减弱动效是 WCAG 2.3.3 非可选项」「集中化覆盖，不能漏」。
- **修复指令**：
  1. `motion.dart:332` 改签名 → `static PageTransitionsTheme pageTransitions(int level, {bool systemReduce = false})`；`systemReduce` 为真时返回 `const _OgLInstantTransitionsBuilder()` 对应的 theme（注意 `_transitionCache` 的键要带上该标志，否则缓存会串档）。
  2. `surface_bridge.dart:525-529` 的 `themeFor` 增加 `bool systemReduce = false` 参数并入缓存键（`_cacheMotion` 旁边加 `_cacheSystemReduce`），`:578` 传下去。
  3. `og_l_app.dart:100-104` 调用 `surface.themeFor(..., systemReduce: MediaQuery.disableAnimationsOf(context) || current.reduceMotion)`。
  4. `main.dart:155-163` 的横幅文案在 ①③ 落地前**必须**改成"系统动画已关闭：控件反馈已静默，**页面转场仍会播放**"——**先改文案，再改行为**，避免继续误导。

#### 4-A-P1-02 · 主题切换动画永远 160ms，档位 0 也不静默（档位表与用户设置脱节）
- **症状**：把动效调到 0（静默）后切明暗主题仍有 160ms 的颜色过渡；调到档位 3 也只有 160ms（比页面转场还快）。
- **根因**：`og_l_app.dart:96-97` 的 `OgLAnim.slow(context)` 里那个 `context` 位于 `MaterialApp` **之外**，而 `OgLMotionScope` 挂在 `MaterialApp.builder` 内部（`og_l_app.dart:110`）→ `OgLMotionScope.levelOf`（`motion.dart:487`）取不到作用域，回落 **档位 1** → 恒 `slow = 160ms`。
- **修复指令**：`og_l_app.dart:96-97` 改为直接读设置（`current` 已在作用域内）：
  ```dart
  themeAnimationDuration: OgLOAnimQuality.of(current.motionLevel).slow,
  themeAnimationCurve: OgLOAnimQuality.of(current.motionLevel).curve,
  ```
  档位 0 时 `slow = Duration.zero` → 主题硬切（静默）；档位 3 时 290ms（与"影响面大用慢档"的设计意图一致）。

#### 4-A-P1-03 · 路由时间线恒 300ms，动效只占前 42–70% —— 每一次导航都有 90–174ms 的"死等"
- **症状**：点进详情页，内容 126ms（档位 1）就到位了，但路由还要再"空转"174ms 才算完成；连续操作时这段空窗叠成「点一下、停一下、再出来」。
- **根因**：`rg -n "transitionDuration" lib/` **0 命中** → 39 处 `MaterialPageRoute` 全用框架默认 300ms 进 / 300ms 退；`motion.dart` 的 `transitionWindow`（0.42/0.55/0.7）只压缩了**运动段**，没有压缩**时间线**。
- **修复指令**：新增统一路由工厂（放 `lib/surface/app/motion.dart` 或新建 `lib/surface/app/page_route.dart`）：
  ```dart
  class OgLPageRoute<T> extends MaterialPageRoute<T> {
    OgLPageRoute({required this.builder, super.settings});
    final WidgetBuilder builder;
    @override
    Widget buildPage(BuildContext context, Animation<double> a, Animation<double> s) =>
        builder(context);
    @override
    Duration get transitionDuration => OgLAnim.medium(context);   // 120/170/230ms
    @override
    Duration get reverseTransitionDuration => OgLAnim.fast(context); // 90/130/170ms
  }
  ```
  并把 39 处 `MaterialPageRoute` 全部替换；注意 `motion_audit.py` 的"硬编码时长"规则不会被触发（时长来自档位表）。若短期不改 39 处，退而求其次：把 `transitionWindow` 提到 1.0，让整条 300ms 都有运动，消掉"到位后还在空转"的错位感。

#### 4-A-P1-04 · 档位 3 的逐控件错峰让最后一个控件 ~806ms 后才出现（"等动画而不是用工具"）
- **症状**：档位 3 进任意长列表页，第 17 个控件要等 576ms 才开始自己的 230ms 入场 → 末项 ≈806ms 后才可见。
- **根因**：`motion.dart:244-245`（`staggerStep: 36ms` × `staggerMaxIndex: 16`）+ `animations.dart:130-136`（`revealAll` 档位超出上限的项**仍然参与动画**，只是不错峰）。
- **修复指令**：`motion.dart:245` → `staggerMaxIndex: 6`；`:244` → `staggerStep: Duration(milliseconds: 24)`。合计 6×24 + 230 = **374ms ≤ 400ms**（rules/06 §3 封顶）。档位 2 维持 8×24 = 192ms 即可。

#### 4-A-P1-05 · 对话框转场与页面完全不是一套节奏，且档位 0 仍在动
- **症状**：底部面板在档位 0 下"啪"地瞬现，而对话框仍以框架默认的缩放淡入弹出 —— 同一次操作里两套节奏；切 tab / 页面转场是"横滑"，对话框是"居中缩放"，方向隐喻也冲突。
- **根因**：`overlays.dart:80-83` 的 `ogLShowDialog` 未传 `transitionDuration` / `reverseTransitionDuration`；另有 **4 处直接 `showDialog` 绕过统一入口**（`settings_page.dart:763`、`:834`、`code_editor_page.dart:427`、`font_pick.dart:28`）。
- **修复指令**：
  1. `overlays.dart:80-83` → `showDialog<T>(context: context, barrierDismissible: barrierDismissible, transitionDuration: OgLAnim.medium(context), reverseTransitionDuration: OgLAnim.fast(context), builder: builder)`。
  2. 4 处旁路 `showDialog` 改走 `ogLShowDialog`（保留各自 `barrierDismissible` / builder / `Navigator.of(dialogContext).pop(...)` 语义）。
  3. 弹层的方向隐喻保持"上=展开 / 下=关闭"，与页面的"左右=层级"**刻意分开**（rules/06 §3 允许两套隐喻，但不得混用），在 `overlays.dart` 头部注释写明。

### P2

#### 4-A-P2-01 · 返回闸门把第二次返回静默丢弃（无任何反馈）
- **症状**：第一次返回弹出确认框的异步窗口内再按一次返回 → 什么都不发生，用户以为应用卡死。
- **根因**：`client_shell.dart:170-173`（`if (_backHandling) return;`）+ `:259-263`（`unawaited(_handleBack())`）。
- **修复指令**：在 `:171` 的早退分支加一次轻量反馈：`OgLNotifier.of(context).info(...)` 或让确认框做 100ms 的 ±4dp 抖动（rules/06 §4b invalid shake ≤2 cycles）；并把 `_handleBack` 里的 `await` 收窄到真正需要异步确认的那一段。

#### 4-A-P2-02 · 底部弹层出场 = 入场（拖拽关闭拖沓）
- **症状**：下拉面板到阈值松手后，面板要用和打开一样长的时间才消失。
- **根因**：`overlays.dart:68` → `reverseDuration: duration`（与入场等长）。
- **修复指令**：`overlays.dart:68` → `reverseDuration: OgLAnim.fast(context)`，出场曲线用 `Curves.easeIn`。

#### 4-A-P2-03 · 一处底部面板绕过统一入口（档位不生效、无拖拽提示条）
- **症状**：长按卡片弹出的动作菜单没有拖拽提示条、且不受动效档位控制 → 「有的能滑有的不能滑」。
- **根因**：`search_page.dart:951` 直接 `showModalBottomSheet<String>`，未走 `ogLShowSheet`。
- **修复指令**：`search_page.dart:951` 改走 `ogLShowSheet<String>`（保留 builder）。

#### 4-A-P2-04 · 共享元素只有起点没有终点（首页 → 仓库详情没有连续性）
- **症状**：首页仓库卡片的标题名义上要"飞"到详情页，但详情页没有同名 Hero → 标题飞一半消失 / 闪回。
- **根因**：`dashboard_page.dart:496-497` 有 `OgLSharedTitle(tag: 'ogl-repo:${repo.fullName}')`，`rg -n "OgLSharedTitle" lib/surface/pages/` 仅此 1 处，`repo_page.dart` 无同 tag 终点。
- **修复指令**：在 `repo_page.dart` 的 AppBar 标题处包 `OgLSharedTitle(tag: 'ogl-repo:${fullName}', child: ...)`（tag 必须逐字符一致）；或若产品不做共享元素，则**删掉** `dashboard_page.dart:496` 的半截 Hero（避免"飞丢"）。二选一，不要留着半截。

#### 4-A-P2-05 · 登录门 / 引导页 / 主壳之间是硬切，没有任何转场
- **症状**：首启时"引导页 → 登录页 → 主壳"三次整屏替换都是瞬时闪变，是首屏观感里最"跳"的三下。
- **根因**：`client_shell.dart:_buildShell` 按 `_onboardingDone` / `_checked` / `_accountId` 直接 `return` 不同 Widget（条件渲染），**不是路由**，因此不经过 `pageTransitionsTheme`。
- **修复指令**：把三态改成**同一个 Scaffold 内的内容切换**，用 `OgLSurfaceSwitch`（`animations.dart:294-330`，已接档位）包裹状态内容，而不是换整棵子树。

#### 4-A-P2-06 · `repo_page` 的 TabBarView 未做档位化，与 `search_page` 节奏不一致
- **症状**：档位 0（静默）时，仓库页的 tab 面板仍可手势滑动并带框架默认过渡；发现页则已禁用 → 同一个 App 两套节奏。
- **根因**：`repo_page.dart:625` → `TabBarView(children: tabViews)` 无 `physics`；`search_page.dart:742-746` 已按 `OgLAnim.enabled(context)` 设 `physics`。
- **修复指令**：`repo_page.dart:625` 补 `physics: OgLAnim.enabled(context) ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics()`，与 `search_page` 对齐。

#### 4-A-P2-07 · 平台不区分：桌面宽窗也做整页横滑
- **症状**：1280px 桌面窗口里点左侧 Rail，整个内容区横向滑一下，像手机翻页被搬到桌面，显得多余且晃眼。
- **根因**：`motion.dart:354-358` 对 `TargetPlatform.values` 全部映射到同一个 `_OgLSlideFadeTransitionsBuilder`。
- **修复指令**：`motion.dart:352-357` 按平台分发：桌面（macOS / windows / linux）用纯淡入 builder（新增 `_OgLFadeTransitionsBuilder`，无位移）；移动端保留 shared-axis X。桌面端壳体的 `_OgLShellSlide`（`client_shell.dart:440+`）在宽屏下也应改为淡入。

#### 4-A-P2-08 · 新页淡入与旧页淡出叠加 → 交叉瞬间出现"两层半透明"的灰帧
- **症状**：push 的中段（约 40–60% 处）新页只半透明、其后的旧页又被压到 0.65 → 合成出来一发灰，整屏像蒙了一层雾（旧"漂浮 / 鬼影"观感的残余来源）。
- **根因**：`motion.dart:500` 外层 `FadeTransition(opacity: faded)`（0→1）与 `:493-494` 内层旧页 `FadeTransition(1→0.65)` 同时作用。
- **修复指令**：旧页退场**只保留位移、不再压暗**（把 `:494` 的 `Tween(begin: 1, end: 0.65)` 改为 `Tween(begin: 1, end: 1)`，或直接去掉该 `FadeTransition`），把"让位"的表达交给位移；新页入场透明度曲线改陡（前 60% 完成）以缩短灰帧。

#### 4-A-P2-09 · 退出分支对 `secondaryAnimation` 无保护（新页可能被误推走）
- **症状**：若框架在某种路由状态下把非零 `secondaryAnimation` 交给**当前**路由，当前实现会把它推到 `-offset` 并压暗到 0.65 —— 表现为"新页一进来就偏左、半透明"。
- **根因**：`motion.dart:486-497` 的退出分支只判断 `offset > 0 && exitWindow > 0`，不判断"我是不是被覆盖的那个路由"。
- **修复指令**：`motion.dart:486` 的条件加保护：`if (offset > 0 && exitWindow > 0 && route.isCurrent == false)`，或在分支内读 `route.isCurrent` 决定是否叠加退场；同时在 Android 真机上确认"新页入场期间无横向偏移、无半透明"（列入下节清单）。

#### 4-A-P2-10 · 引导页前进 / 后退同长同向
- **症状**：右滑回退与点"下一步"速度完全一样，分不清在第几步。
- **根因**：`onboarding_page.dart:202-204`（`nextPage(duration: OgLAnim.pageViewDuration)`）与 `:212-213`（`previousPage(duration: OgLAnim.pageViewDuration)`）同长。
- **修复指令**：`onboarding_page.dart:212` 改用 `OgLAnim.fast(context)`（后退比前进短，符合 rules/06 §2「exit ≈ 60–80% of enter」）。

#### 4-A-P2-11 · `transitionOffset` 的字段语义与实现不符（占页高 → 实为占页宽）
- **症状**：调档位表的人按注释"占页高比例"去估算位移，实际是**屏宽**比例；两者的绝对值差 2 倍以上，极易误判。
- **根因**：`motion.dart:91` 注释「页面过渡位移（占页高比例）」，而 `:476` 用 `Offset(offset, 0)`（X = 页宽比例）。
- **修复指令**：`motion.dart:91` 注释改为「页面过渡横向位移（占页**宽**比例；shared-axis X 语义）」，并在 `motion.dart:310-318` 的类注释里同步说明"位移方向为横向"。

---

## 4. 用户满意度视角（本席负责的三段）

### 4.1 「点下去到新页面出现」有没有方向感？

**有。** v15 把转场改成了 shared-axis X：前进=新页自右向左入 + 旧页向左让位（`motion.dart:476/491`），返回=两者同时向右；旧页不再是"凭空消失"而是**被推走并在你返回时滑回原位**（`secondaryAnimation` 被真正消费）。这一段是 v15 在转场层最成功的改动，用户能读出"往里走 / 往回走"，"漂浮感"的直接来源（整页缩放、半透明鬼影）都已清除。

### 4.2 有没有速度感？会不会觉得慢？

**页面级：够快**——运动只占 300ms 时间线的前 42–70%（档位 1：126ms 动完；档位 3：210ms），且 `CurveTween` 替换 `CurvedAnimation` 后没有每帧分配与监听泄漏，翻页越多不会越卡。

**但有两处会让用户觉得"慢"**：
1. **路由时间线恒 300ms**（4-A-P1-03）：内容 126ms 就到位，路由还要空转 174ms；连续操作时叠成「点一下、停一下」。
2. **档位 3 的逐控件错峰 806ms**（4-A-P1-04）：这是"等动画而不是用工具"最重的一条 —— 末项要等 0.8 秒才出现。

**切页级：偏"闷"而非"飘"**——切 tab 位移被 clamp 到屏宽 2%，档位 3 的弹簧过冲（ζ≈0.63，8.1%）作用在 8dp 上只有 <0.2px 可见 → 用户看到的是"滑一下"而非"弹一下"；同时三档位移被 clamp 抹平成同一值（4-A-P2 的第 2 条回归项），"降档=降质量"的承诺在切页上不成立。

### 4.3 会不会让人觉得"飘"？

**整体已不飘**（无缩放、无 0.70 鬼影、切页 0.94）。残余的"灰/飘"来自两处细节：push 交叉瞬间新旧两层半透明叠加的灰帧（4-A-P2-08），以及首启三段硬切（4-A-P2-05）。两者都不是"缩放"级别的漂浮，属打磨项。

---

## 5. 本席对三问的回答

**Q1 · 闭环核对（旧确证逐条）**
- **已修（3/6）**：F-12（消费 `secondaryAnimation` + 改 shared-axis X + 旧页对向退场）、C-01（三档 `transitionScaleFrom` 全 1、转场无 `ScaleTransition`、CI 门禁已加）、C-05（切 tab 透明度 0.70 → 0.94）。
- **已修有残留（1/6）**：F-13（条件式 `canPop` + `maybePop` 已落地；残留 `_backHandling` 闸门静默吞第二次返回 → 4-A-P2-01）。
- **修法有问题（1/6）**：F-15（仅"淡入与位移同窗"修好；错峰 576ms、`fast 170ms`、`settleCurve easeOutBack` 10% 过冲、`largeCurve easeOutQuint` 四项未动）。
- **未修（1/6）**：F-14 —— 路由时长恒 300ms（39 处 `MaterialPageRoute` 未接档位）、主题切换恒 160ms（`OgLMotionScope` 作用域错位）、`ogLShowDialog` 未接档位、档位 0 在对话框/主题处**仍不静默**；另系统「移除动画」对页级转场**完全无效**（4-A-P1-01）。

**Q2 · 回归（v15 四项大改是否引入新问题）**
- 「有方向、无漂浮」：**达成**。shared-axis X + 对向退场 + 无整页缩放 + 切页 0.94，四项合起来确实把"漂浮感"的主要来源清掉了。
- 位移量：切 tab **恰好 2.0% 屏宽**（顶格合规）；页面转场 **3.0% 屏宽**（略超 2% 判据，但绝对值 ≈12dp，可接受）。
- 退场接力：**成立**（`secondaryAnimation` 被消费，旧页被推走并在 pop 时滑回归位）。
- 低档位 0：页面转场 / 切 tab / sheet **完全无动画**；**对话框与主题切换仍动** → 「档位 0 不静默」未闭环。
- **新引入的风险（2 条）**：① 切 tab 的位移被 clamp 到 0.02，使档位 1/2/3 在切页上完全等价（档位表"说谎"）；② 档位 3 的弹簧过冲被 `clamp(0,1)` 吃掉，"丝滑"承诺未兑现（旧 C-09 仍在）。另 `CurveTween` 化改造是纯收益，无回归。

**Q3 · 新发现（本席范围内旧审计未抓到 / 未闭环）**
共 **16 条**：**P1 5 条**（系统 reduce-motion 对页级转场无效且横幅文案相反 / 主题动画恒 160ms / 路由时长恒 300ms 死等 90–174ms / 档位 3 错峰 806ms / 对话框转场与档位脱节且 4 处旁路）、**P2 11 条**（返回闸门静默吞第二次返回 / sheet 出场等长 / 1 处 sheet 旁路 / Hero 无终点 / 首启三段硬切 / repo TabBarView 未档位化 / 桌面仍横滑 / 新旧页半透明叠加灰帧 / 退出分支缺 secondary 保护 / 引导页前后同长 / `transitionOffset` 语义与注释不符）。**本席范围内无 P0**。

---

## 6. 已检查清单（禁抽样，覆盖声明）

**读全文的文件（6）**
1. `lib/surface/app/motion.dart`（525 行，全文）— 档位质量表 4 档全部字段、`isNotHeavierThan` 单调性、`pageTransitions` 缓存与有界性、`_OgLInstantTransitionsBuilder`、`_OgLSlideFadeTransitionsBuilder`（含 `CurveTween`/`RepaintBoundary`/secondary 退场）、`OgLMotionScope`。
2. `lib/surface/app/client_shell.dart`（509 行，全文）— `_handleBack` 返回链、`_backHandling` 闸门、`PopScope` 条件式 `canPop`、`_buildShell` 三态与懒挂载/`TickerMode`、`_OgLShellSlide`（clamp / 弹簧 / 透明度 0.94）。
3. `lib/surface/app/og_l_app.dart`（250 行，全文）— `themeAnimationDuration/Curve`、`OgLMotionScope` 挂载位置、`MediaQuery.disableAnimations` 注入、`MaterialApp.builder` 层级。
4. `lib/surface/app/animations.dart`（386 行，全文）— `OgLAnim` 全部 getter、`OgLSpring`、`OgLReveal`、`OgLRevealList`、`OgLSurfaceSwitch`、`OgLSharedTitle`。
5. `lib/surface/app/overlays.dart`（`ogLShowSheet` / `ogLShowDialog` / `ogLConfirm` 全文段）。
6. `lib/surface/surface_bridge.dart`（`themeFor` 与 `pageTransitionsTheme` 段）。

**逐点核对（rg 全量扫描，非抽样）**
7. `rg -n "transitionDuration|reverseTransitionDuration" lib/` → **0 命中**（39 处 `MaterialPageRoute` 全部未接档位）。
8. `rg -n "MaterialPageRoute" lib/` → 39 处，逐处确认均未带 `fullscreenDialog`、未带自定义 `transitionDuration`。
9. `rg -n "showDialog" lib/` → 5 处调用（`settings_page.dart:763/834`、`code_editor_page.dart:427`、`font_pick.dart:28`、`overlays.dart:80`）→ **4 处旁路**。
10. `rg -n "showModalBottomSheet|ogLShowSheet" lib/` → **1 处旁路**（`search_page.dart:951`）。
11. `rg -n "Hero\(|OgLSharedTitle" lib/` → 定义 1 + 调用 1（`dashboard_page.dart:496`），**终点缺失**。
12. `rg -n "PageRouteBuilder|extends PageRoute|extends ModalRoute|routes:|onGenerateRoute" lib/` → **0 命中**（无自定义路由/嵌套 Navigator，转场无旁路实现）。
13. `rg -n "TabBarView\(|TabBar\(" lib/surface/pages/` → 4 处（`repo_page.dart:617/625`、`search_page.dart:732/742`），逐处核对 `physics` 档位化。
14. `rg -n "ScaleTransition|AnimatedScale" lib/` → 3 处，**全部在 `animations.dart`（白名单文件）**，页面级转场无缩放。
15. `rg -n "disableAnimations" lib/` → 7 处，逐处确认**无一处进入 `pageTransitions`** 链路。
16. `rg -n "Curves.linear" lib/` → 仅 `motion.dart:280/281`（档位 0 的无动画曲线，允许）。
17. `rg -n "transitionScaleFrom" lib/` → 3 处，**全部为 1**。
18. `rg -n "nextPage|previousPage" lib/surface/pages/onboarding_page.dart` → 前 202 / 后 212，同长。
19. `tool/motion_audit.py` 全文（146 行）— 确认门禁范围：禁硬编码时长、禁隐式动效组件、禁 `ScaleTransition`/`AnimatedScale`、禁 `Curves.linear`；**不覆盖** `transitionScaleFrom` 取值、不覆盖路由时长、不覆盖 `pageTransitions` 的系统 reduce 接线（这正是 4-A-P1-01/02/03 能长期存在的原因）。
20. `docs/UX_CROSS_AUDIT/2-C-motion.md`（C-01…C-20）、`docs/UX_CROSS_AUDIT/4-B-transitions.md`（B-01…B-18）、`docs/UX_STABILITY_PLAN.md`（F-12…F-15 原文）— 用于逐条闭环判定。

**未做（明确声明）**
- 未在真机 / 模拟器上跑动（无设备与运行基座），所有"观感"结论均为**代码级推导**；4-A-P2-09 的 secondary 语义与 4-A-P2-08 的灰帧需要真机确认，已列入修复后的验收清单。
- 未运行 `dart analyze` / 测试（本席为只读审计；且纪律限定本地 dart 仅用于 `format`，本文件为 Markdown，无需 format）。
