# 批 2 · C 席 —— 动效档位对「稳定感」的影响审计（漂浮感的动效根因）

> **文档戳 / Doc Stamp**
> - 审计批次：**批 2 · 漂浮感与稳定感 · C（动效对稳定感）**
> - 版本：**v14.0.0**（`pubspec.yaml:21` → `version: 14.0.0+140000`）
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `f684160`（2026-11-21 16:27:57 +0800）
> - 更新时间：**2026-11-22（Asia/Shanghai）**
> - 审计对象：`lib/surface/app/motion.dart`（494 行，OgLOAnimQuality 档位表 + `_OgLSlideFadeTransitionsBuilder`）、`lib/surface/app/animations.dart`（OgLAnim / OgLSpring / OgLReveal / OgLSurfaceSwitch）、`lib/surface/app/client_shell.dart`（`_OgLShellSlide` 切 tab 弹簧）、`lib/surface/app/og_l_app.dart`（`themeAnimationDuration`）、`lib/surface/surface_bridge.dart`（`expansionTileTheme`）、`lib/surface/app/overlays.dart`（sheet / dialog）
> - 基准文档：`docs/UX_CROSS_AUDIT_BRIEF.md`（含双轴补强）、`/var/minis/skills/sota-frontend-design/rules/06-motion-design.md`（§1 目的检验、§2 时长/缓动数值表、§3 编排与方向语义、§5 合成器契约、§6 减弱动效）、`/var/minis/skills/material-3/SKILL.md` §Motion（Emphasized 500 / decelerate 400 / accelerate 200；emphasized decelerate = `cubic-bezier(0.05,0.7,0.1,1)`）
> - 性质：**只读审计**。未修改任何业务代码，未 commit / 未 push。
> - 复现方式：全部证据为 `file:line`，用 `rg -n "<片段>" <路径>` 可复现。
> - 参考屏口径（用于 px 量化）：手机 **412 × 915 dp**，桌面 **1280 × 800 dp**。

---

## 0. 结论摘要

「漂浮感」在动效层的根因不是"动得多"，而是**动的方式**：整页被**缩放 + 纵向窜出**、切 tab 时整页**变半透明**、弹簧**回弹幅度不可见但透明度抖动很显眼**、路由时长**恒为 300ms 而内容只动前 126ms**、以及**档位 0 的「静默」承诺在主题/对话框处失效**。

| # | 结构性问题 | 量化 | 用户感受 |
|---|---|---|---|
| C-01 | **整页转场含全页缩放**（0.99 / 0.975） | 档位 3 页面从 **97.5% 缩到 100%**，同时纵移 **46dp**（0.05 × 915dp） | 「页面缩小再长大」= 内容在飘，不是被打开 |
| C-02 | **路由时长恒为 Flutter 默认 300ms**，运动只占前 42–70% | 档位 1：126ms 在动 + **174ms 死等** | 「点了没反应，等一下才出来」 |
| C-03 | **主题切换时长永远 160ms**（作用域未挂载 → 恒按档位 1） | 档位 0 应为 0ms，实际 160ms | 「关了动画还是动」→ 档位不可信 |
| C-04 | **页级转场不理会系统「移除动画」** | `MediaQuery.disableAnimations` 在转场链路上 0 命中 | 前庭敏感用户被迫看整页缩放滑入 |
| C-05 | **切 tab 时整页透明度压到 0.70** | `client_shell.dart:504` | 半透明鬼影 = 「漂」的最直接观感 |
| C-06 | **档位 3 错峰 16 × 36ms = 576ms**（+230ms 入场） | 末项 **~806ms** 后才可见 | 「等动画而不是用工具」 |
| C-09 | **弹簧回弹幅度不可见（1.6px），却被误当"丝滑"** | ζ=0.625 → 过冲 8.1%；实际位移仅 20dp×8.1% ≈ **1.6px** | 「弹了一下但只看到一闪」→ 不稳定 |

**一句话结论**：本库把动效做成了"**档位表驱动的精致动画**"，但**没有一条动效是在解决"稳定感"**：页面以缩放+纵移入场、切页时内容变半透明、等待时间由框架默认 300ms 决定、档位 0 在两个入口处失效。按 rules/06 §1（每个动画必须回答"取向/反馈/连续性/状态"）逐条对表后，**页级转场的 20 个问题里有 14 个找不到目的**。

---

## 1. 量化：档位表 vs M3 建议值

### 1.1 时长（ms）

| 参数 | 档位 0 | 档位 1 | 档位 2 | 档位 3 | M3 / rules-06 建议 | 判定 |
|---|---|---|---|---|---|---|
| `fast` | 0 | 90 | 130 | **170** | 微反馈 ≤ 150（rules §2） | ✗ 档位 3 超 20ms |
| `medium` | 0 | 120 | 170 | 230 | 入场 200–300 | ✓ |
| `slow` | 0 | 160 | 220 | 290 | 大范围 300–500 | 略短（可接受） |
| `staggerStep` | 0 | 12 | 24 | 36 | 20–50/项 | ✓ |
| `shellDuration` | 0 | 110 | 150 | 190 | 切 tab 200 | ✓（**但全库无人使用**，见 C-09） |
| `stateSwapDuration` | 0 | 110 | 140 | 180 | 状态切换 150–250 | ✓ |
| `pageViewDuration` | 0 | 160 | 200 | 260 | 翻页 250–350 | ✓ |
| `sheetDuration` | 0 | 130 | 160 | 200 | 底部面板 250–300 | ✗ 偏快（弹层显得"急"） |
| **页面路由实际占用** | 300（框架默认） | 300 | 300 | 300 | 大屏转场 300–500 | ✗ 未受档位控制 |
| **转场实际运动** | 0 | 126 | 165 | 210 | — | 死等 174 / 135 / 90ms |

### 1.2 位移与缩放（px @ 412×915dp 手机 / 1280×800 桌面）

| 参数 | 档位 1 | 档位 2 | 档位 3 | 折算（手机） | M3 / rules-06 建议 | 判定 |
|---|---|---|---|---|---|---|
| `transitionOffset`（占页高） | 0.012 | 0.030 | **0.050** | 11 / 27 / **46 dp** | shared-axis 位移 ≈ 30dp 上限 | ✗ 档位 3 超 1.5× |
| `transitionScaleFrom` | 1.00 | 0.99 | **0.975** | — | M3 大屏转场**不做缩放**（Flutter 已移除 ZoomPageTransitions） | ✗✗ |
| `revealOffset`（占自身高） | 0 | 0 | 0.04 | 0 / 0 / 8dp | reveal ≤ 20–30dp | ✓（但覆盖面过大，见 C-20） |
| `revealScaleFrom` | 1 | 1 | 0.985 | — | ≤ 0.96–0.98 且只用于小元件 | ⚠ 边界值 |
| `shellOffset`（占页宽） | 0.02 | 0.035 | 0.05 | 8 / 14 / 21 dp | 切 tab 位移 8–24dp | ✓ |
| `blurSigma` | 0 | 0 | **6** | — | — | ✗ **死参数**，无消费者（C-16） |

### 1.3 弹簧参数（mass = 1）

| 档位 | stiffness | damping | ζ = c/(2√k) | 过冲 % | 振荡周期 | 收敛时间(2%) | 观察 |
|---|---|---|---|---|---|---|---|
| 1 | 1225 | 70 | **1.00**（临界） | 0% | — | 114ms | ✓ 但**远超** rules §2 的 170–300 参考刚度 |
| 2 | 1024 | 51 | 0.797 | 1.6% | 325ms | 157ms | ✓ 幅度可接受 |
| 3 | 784 | 35 | **0.625** | **8.1%** | 287ms | 229ms | ✗ 过冲 8.1% > rules §2 的「≤2–3%」 |

> 过冲按 `e^(−ζπ/√(1−ζ²))` 计算。**关键推论**：档位 3 的 8.1% 过冲作用在 21dp 的切 tab 位移上 = **1.7px**，肉眼几乎不可见；而同一段动画里整页透明度却从 1.0 掉到 0.70（**30% 的亮度变化**）。**弹簧带来的"活"被透明度抖动吃掉了，只剩下"闪"。**

### 1.4 曲线对照

| 用途 | 档位 1 | 档位 2 | 档位 3 | M3 emphasized decelerate（进入屏）/ emphasized accelerate（出屏） | 判定 |
|---|---|---|---|---|---|
| `curve`（通用） | easeOut | easeOutCubic | easeOutQuart | `cubic-bezier(0.05,0.7,0.1,1)` | ⚠ 档位 3 偏"急停" |
| `largeCurve`（整页） | easeOutCubic | easeOutQuart | **easeOutQuint** | 同上 | ✗ quint 初始速度极高 → 整页"窜出去" |
| `settleCurve`（收尾） | easeOut | easeOutCubic | **easeOutBack** | 不回弹（decelerate 单调） | ✗ 10% 过冲 |
| 主题切换 | — | — | `curve` | emphasized 500ms | ✗ 时长档位错（见 C-03） |

---

## 2. 用户可感知问题清单（20 条）

### 严重（6 条）

#### C-01 · 整页转场同时做「全页缩放 + 46dp 纵向窜出」——页面在飘，不是在被打开
- 证据：`lib/surface/app/motion.dart:249-250`（`transitionOffset: 0.05`、`transitionScaleFrom: 0.975`）、`motion.dart:463-467`（`ScaleTransition` + `SlideTransition` 套在全页上）
- 用户感受：进页面时整个页面**先缩到 97.5% 再长大**，同时从下方 46dp 窜上来 —— 视觉上像一张卡片在飘浮，而不是"新页面覆盖旧页面"。每天进 30+ 次仓库/议题详情页，这条动效是「漂浮感」的高频来源。
- 规范依据：M3 大屏转场不使用缩放（Flutter 自身已移除 `ZoomPageTransitionsBuilder`）；本文件 `motion.dart:315-330` 自己也写着「整页缩放要求整页在过渡期间反复重新光栅化 —— 页面越重越卡」——**代码却仍然在缩放**，自相矛盾。
- **修复指令**：
  1. `motion.dart:249` → `transitionScaleFrom: 1`；`motion.dart:224` → `transitionScaleFrom: 1`（档位 2 也取消）。
  2. `motion.dart:249` → `transitionOffset: 0.03`（与档位 2 齐平，≈27dp ≤ M3 shared-axis 30dp 上限）；`motion.dart:196` → `0.02`。
  3. `motion.dart:463-467`：删除 `ScaleTransition` 分支，保留 `SlideTransition` + `FadeTransition`。
  4. `tool/motion_audit.py` 增一条门禁：`motion.dart` 之外不得出现 `ScaleTransition`，且 `transitionScaleFrom` 必须为 1（若确需保留，在本文件加注释说明理由）。

#### C-02 · 路由时长恒为 300ms，其中 58%（档位 1）是死等
- 证据：全库 `rg -n "transitionDuration|reverseTransitionDuration" lib/` **0 命中** → `MaterialPageRoute` 使用框架默认 300ms 进 / 300ms 退；`motion.dart:205`（`transitionWindow: 0.42`）只压缩了"运动段"，路由时间线没压缩
- 用户感受：点进去后内容 126ms 就到位了，但**还要再等 174ms** 路由才结束；连续操作时这段空窗叠加成「点一下、停一下、再出来」——用户描述的「等动画而不是用工具」。
- 规范依据：rules/06 §2「大屏转场 300–500ms」是**上限**，不是「必须占满」；高频任务页应 near-instant。
- **修复指令**：
  1. 在所有 `MaterialPageRoute`（`rg -n "MaterialPageRoute" lib/` 全量）构造处补 `transitionDuration: OgLAnim.medium(context)`、`reverseTransitionDuration: OgLAnim.fast(context)`。
  2. 若不便逐处改，退而求其次：把 `motion.dart:205/231/257` 的 `transitionWindow` 提到 **1.0**，让整条 300ms 都有运动，再把路由时长压到 200–230ms（靠上一步）。
  3. 目标值：档位 1 = 进 120ms / 退 90ms；档位 3 = 进 230ms / 退 170ms。

#### C-03 · 主题切换时长永远 160ms：档位 0「静默」在主题切换处失效
- 证据：`lib/surface/app/og_l_app.dart:96` → `themeAnimationDuration: OgLAnim.slow(context)`；此处的 `context` 在 `MaterialApp` **之上**，而 `OgLMotionScope` 挂载在 `MaterialApp.builder` 内（`og_l_app.dart:110` 附近 `OgLMotionScope`）→ `OgLMotionScope.levelOf` 取不到作用域，回落为 **1**（`motion.dart:487` 的 `scope?.level ?? 1`）→ 恒得档位 1 的 `slow = 160ms`
- 用户感受：用户在设置里把动效调到 0（静默），切明暗主题时**仍然有一段 160ms 的颜色过渡** → 「档位不可信 / 不稳定」；反过来调到档位 3，主题切换也只有 160ms（比页面转场还快），与"主题切换影响面大 → 用慢档"的设计意图（`og_l_app.dart:94-95` 注释）完全相反。
- **修复指令**：`og_l_app.dart:96-97` 改为直接用设置里的档位，不依赖作用域：
  ```dart
  final int ml = current.motionLevel; // 来自 OgLSettings
  themeAnimationDuration: OgLOAnimQuality.of(ml).slow,
  themeAnimationCurve: OgLOAnimQuality.of(ml).curve,
  ```
  （`current` 在 `og_l_app.dart:70` 已是 `surface.settings.settings`，可直接取 `current.motionLevel`。）

#### C-04 · 页级转场完全无视系统「移除动画」设置
- 证据：`lib/surface/surface_bridge.dart:565` → `pageTransitionsTheme: OgLMotion.pageTransitions(motionLevel)`；`motion.dart:330-352` 的 `pageTransitions(int level)` **只看设置档位**，从不读 `MediaQuery.disableAnimationsOf(context)`。对照：`lib/surface/widgets/anim/anim_preload.dart:769` 与 `lib/surface/app/motion.dart:311-320`（`OgLMotion.disableAnimations`）都读了该信号 → 说明这是**接线遗漏**而非设计意图
- 用户感受：系统开启「移除动画」（Android 无障碍/前庭敏感用户）后，进入页面依然整页缩放滑入；同样，开启 App 内 `reduceMotion`（`settings.dart:269` 会把档位解析为 0）时**页面转场确实静默**，但**主题切换不静默**（C-03）——两处行为不一致 → 「粗糙」。
- 规范依据：rules/06 §6「减弱动效是 WCAG 2.3.3 非可选项」。
- **修复指令**：
  1. `motion.dart:330` 改签名为 `pageTransitions(int level, {bool systemReduce = false})`；`systemReduce` 为真时直接返回 `const _OgLInstantTransitionsBuilder()`（档位 0 之外的静默路径）。
  2. `surface_bridge.dart:565` 传入 `MediaQuery.disableAnimationsOf(context)`（`surface_bridge.dart` 的 `themeFor` 需要新增该参数，或改由调用方 `og_l_app.dart:100` 传入）。
  3. 同时把 `og_l_app.dart` 的 `MediaQuery` 判定纳入档位：`disableAnimations` 时把传给 `themeFor` 的 `motionLevel` 强制为 0。

#### C-05 · 切 tab 时整页被压到 70% 透明度 —— 半透明鬼影 = 「漂」
- 证据：`lib/surface/app/client_shell.dart:504` → `opacity: (0.7 + 0.3 * t).clamp(0.0, 1.0)`
- 用户感受：切 tab 的一瞬，整个页面**变成半透明的鬼影**再变实；文字与背景短暂"透"出来，视觉上像内容浮在别处之上而不是被换掉。这是最容易被用户描述为「飘」「不实」的一帧。
- 规范依据：rules/06 §5「动画只改 transform / opacity」——opacity 是允许的，但**幅度**应服务于目的；此处 30% 的亮度变化没有传达任何信息（方向已由位移表达）。
- **修复指令**：`client_shell.dart:504` → `opacity: 1.0`（直接删掉 `Opacity` 包装，或下限改为 `0.94`）；位移 + 淡入的信息量由 `FractionalTranslation` 单独承担。若确实想要"轻活"感，改为对**标题/图标**做 0→1 的淡入，而不是整页。

#### C-06 · 档位 3 的错峰让末项 ~806ms 后才出现
- 证据：`lib/surface/app/motion.dart:244-245` → `staggerStep: 36ms`、`staggerMaxIndex: 16`；`lib/surface/app/animations.dart:112-124`（`staggerOf`，`revealAll` 档位超限项返回 `Duration.zero` 但**仍参与动画**）
- 用户感受：档位 3 下页面里第 17 个控件要等 **16×36 = 576ms** 的错峰才开始自己的 230ms 入场 → 最后一项 **~806ms** 后才可见；用户在列表页要等将近一秒才「看全」。这就是「等动画而不是用工具」的直接证据。
- 规范依据：rules/06 §3「错峰 20–50ms/项，但总量封顶 ~400ms、6–8 项」。
- **修复指令**：`motion.dart:245` → `staggerMaxIndex: 6`；`motion.dart:244` → `staggerStep: 24`（档位 3）；档位 2 保持 `8 × 24 = 192ms`（合规）。合计上限 6×24+230 = **374ms ≤ 400ms**。

### 中（11 条）

#### C-07 · 档位 3 的微反馈 170ms 超过 150ms 上限
- 证据：`motion.dart:241` → `fast: Duration(milliseconds: 170)`
- 用户感受：列表项展开/收起、开关、数值变化都带 170ms 的拖尾感，按钮回弹"慢半拍"。
- **修复指令**：`motion.dart:241` → `Duration(milliseconds: 150)`（rules/06 §2 微反馈 100–150ms）。

#### C-08 · `settleCurve = easeOutBack`（10% 过冲）套在**每个**控件上
- 证据：`motion.dart:254`；`lib/surface/app/animations.dart:266`（`AnimatedSlide` 用 settle）、`animations.dart:258`（`AnimatedScale` 用 settle）；`lib/surface/widgets/scroll_aware_action.dart:180`（反向展开用 settle）
- 用户感受：档位 3 下每一行/每一个按钮入场都"多弹一下"，整屏元素各自轻微过冲 → 观感「散、轻飘」，而不是「稳」。
- 规范依据：rules/06 §2「过冲 ≤ 2–3%（playful 场景）；生产力 UI 用临界阻尼」。
- **修复指令**：`motion.dart:254` → `settleCurve: Curves.easeOutCubic`（档位 3）；若确实要一丝弹，用自定义 `Cubic(0.2, 1.35, 0.3, 1)`（过冲 ≈3%）替代 `easeOutBack`（过冲 ≈10%）。

#### C-09 · 弹簧的"丝滑"没有兑现：回弹不可见，且 `shellDuration` 是死参数
- 证据：`motion.dart:255-256`（stiffness 784 / damping 35 → ζ=0.625 → 过冲 8.1%）；`lib/surface/app/client_shell.dart:476-480`（位移只有 `shellOffset` = 0.05×页宽 ≈ 21dp，8.1% 过冲 = **1.7px**，肉眼不可见）；`motion.dart:258` 的 `shellDuration`（110/150/190ms）**全库无消费者**（`rg -n "shellDuration" lib/` 只命中 `motion.dart` 与 `animations.dart:93-94` 的 getter）
- 用户感受：切 tab 的"弹簧感"实际不存在（1.7px 的回弹没人看得见），能看见的只有 C-05 的透明度闪烁；档位表里的时长承诺与真实表现**对不上** → 「不实、不可信」。
- 规范依据：rules/06 §2「弹簧用于手势/可打断的交互；stiffness 参考 170–300」——这里既非手势交互，刚度又高出参考 2.6–7.2 倍。
- **修复指令**：
  1. 若保留弹簧：把刚度降到 300 附近并保持 ζ≈1（档位 2：k=300 → c=2√300≈34.6；档位 3：k=250 → c≈31.6），并把 `shellOffset` 提到 0.08（≈33dp，让位移本身可见），同时**删除** C-05 的透明度动画。
  2. 若不做手势化：改用 `CurvedAnimation` + `shellDuration`（真正用上该字段），删掉 `OgLSpring.run`。
  3. 无论哪种，删除 `client_shell.dart:474-475` 注释中「更跟手 / 丝滑」的表述——当前实现不跟手。

#### C-10 · 档位 3 的整页曲线 `easeOutQuint` —— 整页以最大速度窜出去
- 证据：`motion.dart:253`（档位 3 `largeCurve: Curves.easeOutQuint`）、`motion.dart:227`（档位 2 `easeOutQuart`）；使用点 `motion.dart:344`（`curve: quality.largeCurve`）与 `motion.dart:417-419`（`Interval(0, _windowEnd, curve: curve)`）
- 用户感受：quint 的初始速度极高，整页先"窜"一下再慢慢落定；M3 emphasized decelerate 是**起步慢、收尾柔**（`cubic-bezier(0.05,0.7,0.1,1)`），观感是"从下方稳稳升起来"。当前曲线让页面像被弹射 → 「窜、飘」。
- **修复指令**：`motion.dart:253` → `largeCurve: const Cubic(0.05, 0.7, 0.1, 1)`（M3 emphasized decelerate）；`motion.dart:227` → 同值（档位 2）；档位 1 保留 `Curves.easeOutCubic`。

#### C-11 · 淡入比位移先结束 20%：先"亮"后"滑"，画面像在闪
- 证据：`motion.dart:419-420` → `_fadedTween = CurveTween(curve: Interval(0.0, _windowEnd * 0.8, curve: Curves.easeOut))`
- 用户感受：页面先整体亮起来，再继续滑 20% 的时间 → 用户看到一帧"内容已经在了但还在动"的错位，观感不稳定。
- **修复指令**：`motion.dart:420` → `Interval(0.0, _windowEnd, curve: Curves.easeOut)`（与位移同窗口结束）；若要保留"先亮"的感觉，只把 opacity 曲线提前到 0.7 但**不要**造成位移未完成的空档。

#### C-12 · 转场只有垂直方向，push 与 pop 同向 —— 返回没有"回去"的语义
- 证据：`motion.dart:456-459` → `Tween<Offset>(begin: Offset(0, offset), end: Offset.zero)`（只有 Y 轴）；`buildTransitions` 未使用 `secondaryAnimation`（`motion.dart:422-430` 签名里收了这个参数但正文未用）
- 用户感受：进入页面是"从下方升上来"，返回时旧页**也是往下退**，两段动画同向串联，观感像页面在"上下呼吸"，而不是"前进 / 后退"。用户看不出自己在往回走 → 方向感弱、漂浮感强。
- 规范依据：rules/06 §3「方向承载语义：前推向左、返回向右；上=展开、下=关闭，不得混用隐喻」。
- **修复指令**：改用**横向 shared-axis X**：`Offset(offset, 0)`（`motion.dart:456-459`，`offset` 取 0.03 ≈ 12dp @ 412dp 宽，与 M3 shared-axis 30dp 上限内），并按 `route` 的 push/pop 方向取 ±；同时在 `buildTransitions` 里用 `secondaryAnimation` 给**旧页**加一段 200ms 的退场（对齐 M3 emphasized accelerate 200ms），避免新旧页叠死。

#### C-13 · ExpansionTile 收起与展开等长，且曲线档位错配
- 证据：`lib/surface/surface_bridge.dart:569-572` → `expansionAnimationStyle: AnimationStyle(duration: OgLOAnimQuality.of(motionLevel).medium, curve: OgLOAnimQuality.of(motionLevel).curve)`（**无 `reverseDuration`**，**无 `reverseCurve`**）
- 用户感受：展开 230ms、收起也 230ms；收起时用户已经决定关掉了，却要再等 230ms → 「迟钝」。档位 3 的 `curve = easeOutQuart` 施加在高度动画上，收起时是"猛收"（quint/quart 起步快），与展开的"缓收"不一致 → 同一控件两个方向两种手感。
- 规范依据：rules/06 §2「退出 = 进入的 60–80%」；M3 emphasized accelerate = 200ms。
- **修复指令**：`surface_bridge.dart:569-572` 改为
  ```dart
  expansionAnimationStyle: AnimationStyle(
    duration: q.medium,
    reverseDuration: q.fast,          // 收起更短
    curve: const Cubic(0.05, 0.7, 0.1, 1),
    reverseCurve: const Cubic(0.3, 0, 0.8, 0.15), // M3 emphasized accelerate
  ),
  ```

#### C-14 · 底部面板沿用框架默认 `Curves.linear`（机械匀速），且收起不更快
- 证据：`lib/surface/app/overlays.dart:66-70` → `sheetAnimationStyle: AnimationStyle(duration: duration, reverseDuration: duration)`（**未给 curve** → 沿用 Flutter `showModalBottomSheet` 默认的 `Curves.linear`）
- 用户感受：底部面板匀速升降，没有减速落定 → 机械、廉价；且收起与展开等长。
- 规范依据：rules/06 §2「入场用 ease-out，绝不用 linear」。
- **修复指令**：`overlays.dart:66-70` → 加 `curve: OgLAnim.curve(context)`、`reverseCurve: Curves.easeIn`、`reverseDuration: duration * 0.7`；`sheetDuration` 档位值（`motion.dart:210/236/262` = 130/160/200）上调到 200/250/300（rules §2 面板 250–300ms）。

#### C-15 · 对话框完全没接入档位 —— 档位 0「静默」在对话框处失效
- 证据：`lib/surface/app/overlays.dart:74-82`（`ogLShowDialog` 直接 `showDialog`，无 `barrierColor` / 无时长 / 无曲线）；`lib/surface/app/overlays.dart:58`（sheet 却接了档位）
- 用户感受：把动效调到 0 之后，底部面板立即出现，但对话框还是框架默认的 150ms 缩放淡入 → 同一次操作里两套节奏 → 「不一致、粗糙」。
- **修复指令**：`overlays.dart:74-82` 改用 `showDialog` 的 `transitionDuration`/`reverseTransitionDuration`/`barrierLabel` 并不足以控制曲线；正确做法是自建 `DialogRoute`/`PageRouteBuilder`，并用 `OgLAnim.medium(context)` / `OgLAnim.fast(context)`；档位 0 时直接 `builder` 渲染、`transitionDuration: Duration.zero`。

#### C-16 · `blurSigma = 6` 是死参数：档位 3「更重」里有一项根本不存在
- 证据：`motion.dart:41/97/158/174/251` 是 `blurSigma` 的全部出现处；`rg -n "ImageFiltered|BackdropFilter" lib/` **0 命中** → 没有任何模糊实现
- 用户感受：设置里的档位 3 被描述为"更丰富"，实际没有任何模糊生效；`isNotHeavierThan`（`motion.dart:167-184`）的单调性断言还把它算进"更重"，制造了**虚假的档位语义**（也是「档位不可信」的一部分）。
- **修复指令**：从 `OgLOAnimQuality` 删除 `blurSigma` 字段及 `hasBlur` getter（`motion.dart:41,97,158,174,251`），或真正实现并限制在小面积（rules §5：blur 是 paint 昂贵操作）。若保留，注释必须写明"未启用"。

#### C-17 · 整页缩放与其自述的性能结论矛盾 → 「只有页面过渡卡」
- 证据：`motion.dart:315-330`（注释明确说整页缩放会"反复重新光栅化"，是 5.0 放弃 `ZoomPageTransitionsBuilder` 的原因）vs `motion.dart:249-250 + 463-467`（档位 2/3 仍在做整页缩放）
- 用户感受：低端机上翻页掉帧、页面白闪，而列表滚动（不受影响）很顺 → 用户归纳成"App 卡"；同时画面在缩小/放大之间跳，进一步加重漂浮感。
- **修复指令**：同 C-01（取消 `transitionScaleFrom`）；若未来确需缩放，只允许在**小元件**（FAB → 展开面板）上使用，并在 `tool/motion_audit.py` 里限制 `ScaleTransition` 的作用对象不得为整页 `child`。

### 轻（3 条）

#### C-18 · 快速连点 tab 时切换被丢弃：内容与选中态不同步
- 证据：`lib/surface/app/client_shell.dart:470-475` → `if (_controller.isAnimating) { return; }`（直接吞掉本次 index 变化，`_from` 不更新）
- 用户感受：连续点两个 tab 时，第二个 tab 的内容直接出现（没有滑动），而底栏药丸已经跳到第二个 → 两者短暂对不上 → 「不稳」。
- **修复指令**：`client_shell.dart:470-475` 改为可中断：取当前 `_controller.value` 与 `velocity` 作为弹簧初值继续跑到新 index（`OgLSpring.run(_controller, context, from: _controller.value, velocity: _controller.velocity)`），并把 `_from` 更新为新方向；`client_shell.dart:452-456` 的 `lowerBound/upperBound` 已留有余量，可直接支撑。

#### C-19 · 弹簧过冲时透明度被 clamp、位移不过冲 → 亮度与位移不同步
- 证据：`client_shell.dart:453`（`lowerBound: -1, upperBound: 2` 允许过冲）、`client_shell.dart:504`（`(0.7 + 0.3 * t).clamp(0.0, 1.0)`）
- 用户感受：落位瞬间亮度先到 1.0，位移还在最后一点点 → 最后一帧有"亮度已定、位置未落"的错位。
- **修复指令**：位移与透明度使用同一个归一化进度（例如 `final double t = _controller.value.clamp(0.0, 1.0);` 用于 opacity，位移用未 clamp 的值），或干脆取消透明度通道（C-05）。

#### C-20 · 档位 3「每个控件都动」→ 整屏元素各自飘
- 证据：`motion.dart:246-248`（`revealAll: true`、`revealOffset: 0.04`、`revealScaleFrom: 0.985`）；`lib/surface/app/animations.dart:112-124`（超限项仍参与动画）、`animations.dart:340-352`（`OgLRevealList.of`）
- 用户感受：页面打开时几十个控件**各自**上移 4% 自身高度并轻微放大 → 整屏像在轻微"沸腾"，读起来不稳。
- 规范依据：rules/06 §1「日常高频任务页的动效应 near-instant」；§3「一切都动 = 什么都不传达」。
- **修复指令**：`motion.dart:247` → `revealOffset: 0`（档位 3 也只淡入），`motion.dart:248` → `revealScaleFrom: 1`；把「层级入场」交给**容器**（卡片/区块整体淡入 170ms），不再逐控件位移；配合 C-06 的 `staggerMaxIndex: 6`。

---

## 3. 修复优先级建议（供 UX_STABILITY_PLAN 收口）

| 优先级 | 条目 | 一句话动作 |
|---|---|---|
| P0 | C-01 / C-03 / C-04 / C-05 | 取消整页缩放、修正主题动画档位接线、接入系统减弱动效、去掉整页 0.7 透明度 |
| P1 | C-02 / C-06 / C-07 | 路由时长纳入档位（进 120–230ms / 退 90–170ms）、错峰封顶 374ms、fast ≤150ms |
| P2 | C-08 / C-09 / C-10 / C-11 | settle 去回弹或降到 ≤3%、弹簧降刚度或改曲线驱动、largeCurve 换 M3 emphasized decelerate、淡入与位移同窗口 |
| P3 | C-12 – C-16 / C-18 – C-20 | 转场方向语义、ExpansionTile 反向时长、sheet 曲线、对话框接档位、删死参数 `blurSigma`、可中断切 tab、取消逐控件位移 |

---

## 4. 检查清单（查过什么 / 未发现问题的部分）

**已逐条核对并确认无问题的项：**

- [x] `motion.dart:158-159` `hasScale` / `hasBlur` 门控逻辑本身正确（缩放/模糊确实被档位开关控制）。
- [x] `motion.dart:167-184` `isNotHeavierThan` 的**比较方向**正确（档位越低越轻），逐级单调性语义无误；问题只在 `blurSigma` 是死参数（C-16）。
- [x] `motion.dart:311-320` `OgLMotion.disableAnimations` 正确读取 `MediaQuery.disableAnimations` 与 `settings.reduceMotion`（问题在**转场链路上没接**，见 C-04）。
- [x] `motion.dart:430-449` 用 `CurveTween.animate` 取代 `CurvedAnimation` 的修复**正确且必要**（避免每帧注册永不摘除的 status listener）；本报告不建议回退。
- [x] `motion.dart:427-431` 有界缓存（≤4 项，越界现算）实现正确，无泄漏。
- [x] `motion.dart:468-470` 过渡整体包 `RepaintBoundary` —— 合成层策略正确（缩放取消后仍应保留）。
- [x] `motion.dart:356-374` 档位 0 的 `_OgLInstantTransitionsBuilder` 直接返回 child —— 真正的静默，**没问题**。
- [x] `motion.dart:281-283` 档位 0 的弹簧 stiffness=0 → `spring` getter 返回 `null`（`motion.dart:145-152`）→ `OgLSpring.run` 直接落位 —— 逻辑正确。
- [x] `animations.dart:145-155` `OgLSpring.run` 对 `null` 规格的处理正确（直接 `controller.value = to`）。
- [x] `animations.dart:196-243` `OgLReveal` 用可取消 `Timer` 而非 `Future.delayed`，并在 `dispose` 取消 —— 资源纪律正确，无泄漏。
- [x] `animations.dart:262-277` 透明度插值**未**使用 `settleCurve`（`easeOutBack`）—— 符合"透明度不得回弹"的规范。✅
- [x] `animations.dart:308-326` `OgLSurfaceSwitch` 的 `AnimatedSwitcher` 同样只用 `curve` 做淡入、`settle` 只作用于缩放 —— 正确。
- [x] `client_shell.dart:441-458` 弹簧控制器在 `initState` 提前创建（预加载），避免按下 tab 那一帧才付 Ticker 成本 —— 性能纪律正确。
- [x] `client_shell.dart:498-501` 切 tab 有 `RepaintBoundary` —— 正确。
- [x] `client_shell.dart:379-386` `ScrollAwareAction` 的 `SlideTransition` 位移按**子控件自身尺寸比例**计算并有 `peekFactor`/`minVisibleExtent` 兜底 —— 收边逻辑本身稳定，问题只在曲线（C-08）。
- [x] `client_shell.dart` 的 tab 方向判断 `_from = widget.index > oldWidget.index ? distance : -distance`（`:477`）—— 左右方向语义**正确**（这一项不构成问题）。
- [x] `animations.dart:79` `sharedElement` 在档位 < 2 时关闭 Hero —— 档位降级不丢功能、只降质量，符合降档策略。✅
- [x] `animations.dart:122` 超限项在 `revealAll` 档位返回 `Duration.zero`（不延迟但仍参与）—— 逻辑正确（覆盖面策略本身按设计）。
- [x] `tool/motion_audit.py` 存在（CI 卡硬编码时长/位移）—— 门禁方向正确；本报告所有修复建议均在 `motion.dart` / `animations.dart` 内取值，不会新增硬编码。✅
- [x] `lib/surface/app/overlays.dart:58-70` sheet 时长已接档位（**仅曲线与反向时长缺失**，见 C-14）。
- [x] `lib/surface/app/animations.dart:376-384` Hero 包裹 `Material(type: transparency)` —— 飞行期文字渲染正确。✅

**本席未覆盖 / 需与其它席交叉确认的点：**

- 页内**滚动**相关的动效（`scroll_aware_action.dart` 的收边动画阈值、`FlatList` 的 item 间距动画）主要由 2-A/2-B 席覆盖，本席只评估其曲线与时长。
- `lib/surface/widgets/anim/anim_preload.dart` 的预加载额度与档位的关系（`:769`）属性能范畴，已核对**不影响**本席结论。
- 各页面自身是否使用 `OgLReveal`（19 个文件命中）属于"逐页密度"范畴，已在 C-20 以全局口径处理，未逐页展开（1-A/1-C 席已逐页列出）。

**页面矩阵提示（本席动效相关，页级结论回链 1-A/1-C/2-A/2-B 报告）：**
仓库域（repo_page / repo_tags / commit / pull / release_detail / code_editor / file_preview）：均经统一 `_OgLSlideFadeTransitionsBuilder`（C-01/C-02 全域生效）；议题域（issue / new_issue / notifications / dashboard）、内容域（gists / gist_detail / new_gist / readme_view / search）、账户域（login / onboarding / profile / settings 系 / about / legal_text）、工具域（download_manager / workflow_dispatch / action_log / action_run）同理适用同一批问题，其中 **onboarding** 额外受 `pageViewDuration` 影响（`onboarding_page.dart:193/203`，260ms 在规范内）、**settings** 受 `ExpansionTile` 影响（C-13）、**download_manager** 受 `AnimatedSwitcher`+`TweenAnimationBuilder` 影响（`download_manager_page.dart:394-432`，时长取 `OgLAnim.fast`，合规）、**搜索/通知列表**受 `OgLReveal` 错峰影响（C-06/C-20）。

---

*报告结束 · 批 2 · C 席 · 只读审计 · 未改代码 · 未 commit/push*
