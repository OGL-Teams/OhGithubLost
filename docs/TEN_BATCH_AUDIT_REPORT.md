# 十批全面审计 · 批 1「UI 视觉与布局」· B 席 —— 色彩与投影审计

> **文档戳 / Doc Stamp**
> - 审计批次：**十批 · 批 1 · B 席（色彩与投影）**；主 skill：`sota-frontend-design` + `frontend-design`
> - 仓库：`/root/OhGithubLost`，工作副本 HEAD `62c5383`（2026-11-28）
> - 更新时间：**2026-11-28 17:19:33 (Asia/Shanghai)**
> - 审计对象：`lib/surface/theme.dart`（ColorScheme / OgLSemanticColors / 14 类组件主题）、`lib/surface/app/og_l_app_bar.dart`、`lib/surface/app/boot_splash.dart`、`lib/surface/app/notifier.dart`、`lib/surface/app/error_surface.dart`、`lib/surface/pages/*.dart`（30 页逐页抽查字面色）、`lib/surface/widgets/`、`lib/surface/util/og_l_radius.dart`；对照 `/tmp/uishots/` 122 张明暗截图（31 场景 × 亮/暗 × 390×844/844×390，home 仅 2 张）
> - 依据：`docs/TEN_BATCH_AUDIT_PLAN.md` 绝对纪律与批 1 行；MD2 体系（非 MD3）；`docs/MD2_MIGRATION_BRIEF.md` / `docs/MD2_MIGRATION_REPORT.md` 作为迁移基线参考（仅参考其事实陈述，不以其代替源码）
> - 方法：只读审计——全文件读取 + `rg`/`grep` 全库交叉扫描 + WCAG 2.1 对比度数值复算 + 截图像素色直方统计；**未改任何代码、未 commit / 未 push**；未读取 Flutter SDK / pub 缓存源码（禁读铁律遵守）
> - 报告纪律：写入前先检查目标文件存在性（此前不存在），以本报告为首建内容；后续修订只 append，不覆盖
>
> **截图核验说明（诚实交代）**：本轮 Vision Group 对 `/tmp/uishots/*.png` 返回 `503 all accounts are temporarily unavailable`，无法用视觉模型看图。已改用 Pillow 对截图像素做**主色直方 + 分位行取样**核验（统计值见各问题证据），不猜测未看到的细节；视觉模型恢复后建议补一次人工/模型复核。

---

## 0. 结论速览

MD2 迁移把色板从 tonal 体系收回传统 `ColorScheme`，页面层**几乎不存在字面色**（C 席结论一致）：`Colors.*` / `Color(0x…)` 只在主题令牌源、文件类型品牌色、语法高亮数据、启动首帧兜底、用户自定义颜色中出现。但「色彩与投影」本身仍有若干用户可感知断点：**主题色选择只改 1 个字段导致 FilledButton 白字在橙/黄主题上逼近对比度红线**；**语义色 success/warning/info 明暗共用一套值，暗色下对 surface 只有 3.2:1**；**errorContainer 作为前景令牌的配套 `onErrorContainer` 从未显式定义，页面文字走 M3 派生值**；**通知层 success/warning 用 primary/secondaryContainer 而非语义色**；**投影体系文档说卡 2/弹层 16、代码写 1/3**；**强描边 token 与通用 outline token 双轨并存**；**AppBar 两套 elevation 实现**；**启动首帧与首屏、错误兜底与正常的色彩语言断裂**。

| 维度 | 量化 | 判定 |
|---|---|---|
| ColorScheme 色板 | 11 个显式角色 + M3 派生 getter 5 处 | ⚠️ P1×3 |
| OgLSemanticColors | 7 字段；success/warning/on* 明暗恒定，outlineVariantStrong 明暗分档 | ⚠️ P1×2 |
| elevation / 投影 | `Card=1 / Dialog=3 / Sheet=1 / SnackBar=3 / AppBar=4(覆写) / Rail=4`；`shadowColor=黑 26%` | ❌ P1×3 |
| 明暗双主题一致性 | 22 个色值中明暗分档 6 组；其余共用 | ⚠️ P1×2 |
| 页面字面色 | `lib/surface/pages` 中 `Colors.transparent` 4 处、自定义色构造 2 处、主题派生 alpha 1 处，**零裸品牌/状态色** | ✅ 通过（令牌纪律） |
| 截图实证 | 122 张；像素采样确认 surface 亮 `#FFFFFF` / 暗 `#121212`、container `#F6F8FA` / `#1C2128`、primary `#0969DA`、error `#CF222E`/`#F85149` 与源码一致；**无视觉模型结论** | ⚠️ 部分通过 |

**问题总数：17 条（P0: 0 / P1: 10 / P2: 7）**。全部带 `file:line` 证据、用户可感知影响、根因与具体修复指令。与 C 席重叠的 AppBar 双实现问题，本报告只从**投影语义一致性**视角（B-07）陈述，不重复 C-P1-1 的跨页一致性论证。

---

## 1. 问题清单（按用户可感知影响 × 修复杠杆排序）

### B-01 · 主题色选「日落/橙」后主按钮白字对比度逼近红线（P1，色彩令牌）

**Where**
- `lib/surface/theme.dart:44-51`：`'sunset': Color(0xFFE06C00)`、`'rose': Color(0xFFC2185B)` 等 7 套种子色。
- `lib/surface/theme.dart:180-194`：`ColorScheme(primary: const Color(0xFF0969DA), onPrimary: Colors.white, ...)` —— **primary 被硬编码，seedColor 参数未参与编译**。
- `lib/surface/theme.dart:427-437`：`FilledButton.styleFrom(...)` 未显式给 `foregroundColor`，继承 `onPrimary=白`。
- `lib/surface/surface_bridge.dart:538-541`：把 `seedColorId` 解析为颜色传入 `buildOgLTheme`，但该函数只在签名里接收、函数体不用。

**Rule**：WCAG 2.1 SC 1.4.3（正文 ≥4.5:1）；`sota-frontend-design/rules/03`（令牌必须端到端生效）。

**Impact**：设置里选「日落」主题色后，用户期待全站强调色变成橙色，实际主按钮文字仍是白字；复算 `#FFFFFF` on `#E06C00` = **3.33:1**（正文下限 4.5:1 的 74%），长时间阅读「保存」「提交」按钮文字明显发飘。默认蓝 `#0969DA` 白字 5.19:1 合格；7 套主题里仅 sunset 越线。用户切换主题色不生效这件事本身就是可感知的功能-视觉断裂。

**Root cause**：MD2 迁移把 `ColorScheme.fromSeed` 删掉后，`seedColor` 形参成为死参数；`ColorScheme.copyWith(primary: …)` 的旧接线（见 `docs/MD2_MIGRATION_REPORT.md` §一）在重写时漏掉。

**Fix**（修复代理执行）：
1. `buildOgLTheme` 中以 `primary: seedColor` 替换 `const Color(0xFF0969DA)`；`onPrimary` 按种子色亮度选择 `Colors.white` 或近黑（例如 `ThemeData.estimateBrightnessForColor(seedColor)`），确保 ≥4.5:1。
2. 为 `kOgLSeedColors` 每个颜色在映射里补 `onPrimary` 决策表，避免运行时猜测；sunset 建议改深一档（如 `#B85C00`）或 onPrimary 用 `#1F2328`。
3. 补断言测试：遍历 `kOgLSeedColors`，`contrast(onPrimary, primary) >= 4.5`。
4. 重新截「日落主题」矩阵，确认主按钮文字不再发灰。

**Effort**：small（3 行 + 1 张颜色表 + 1 个测试）。

---

### B-02 · 语义色明暗共用：暗色 success 对 surface 只有 3.16:1，信息色对深色底 3.12:1（P1，明暗一致性）

**Where**
- `lib/surface/theme.dart:236-240`（extensions 段）：`success: const Color(0xFF2E7D32)`、`warning: const Color(0xFFB26A00)`、`onSuccess/onWarning: 白` —— **明暗主题无分支**。
- `lib/surface/theme.dart:241-242`：`info: scheme.primary`、`onInfo: scheme.onPrimary` —— 跟随主题色但暗色未单独提亮。
- `lib/surface/theme.dart:113-121`：类注释声称 success/warning 按 WCAG 校准、`outlineVariantStrong` 明/暗分档，实际 success/warning 没有分档。
- `docs/MD2_MIGRATION_REPORT.md` §五：明确写了「亮 success #1A7F37 / 暗 success #3FB950」的明暗分档方案 —— 与当前源码不符（报告说已做，代码没做）。

**Rule**：WCAG 2.1 SC 1.4.11（非文本对比 ≥3:1）、SC 1.4.3（正文 ≥4.5:1）；MD2 明暗双主题一致性。

**Impact**：暗色主题下 `#2E7D32` 深绿状态点/`success` SnackBar 在 `#121212` 背景上几乎融进去；复算：success 对 surface `#121212` = **3.65:1**、对 surfaceContainerHighest `#1C2128` = **3.16:1**（后者刚过 3:1 门槛，稍一换底就失效）；亮色 success 对白底 5.13:1 完全合格。info `#0969DA` 暗色 container 上 **3.12:1**，作为正文级信息图标勉强。用户切暗色后「成功」反馈从清晰变暗淡，明暗主题不是同一套语言。

**Fix**（修复代理执行）：
1. 按明暗拆两套 `OgLSemanticColors`（可仿 `outlineStrong` 的分支写法）：亮色 `success #1A7F37 / warning #9A6700 / info #0969DA`；暗色 `success #3FB950 / warning #D29922 / info #58A6FF`（与 MD2_MIGRATION_REPORT §五一致），`on*` 亮色白 / 暗色 `#121212`。
2. 改 `tool/contrast_audit.py:_extract_colors` 让它分别提取明暗两套（当前 `dark=True` 形参被忽略，注释写「当前为明暗共用值」），对各自 surface/container 校验：文字级 ≥4.5、图形级 ≥3。
3. 截图矩阵重点复核 `action_log`/`action_run`/`commit`/`dashboard` 暗色状态点。

**Effort**：medium（主题段重构 + 门禁脚本小改 + 截图）。

---

### B-03 · warning / dark-success 的 `on*` 白字正文级不达标（P1，可读性）

**Where**
- `lib/surface/theme.dart:238-239`：`warning: #B26A00, onWarning: #FFFFFF`；`:237` `onSuccess: #FFFFFF`。
- `lib/surface/app/notifier.dart:117-125`：`OgLNoticeTone.warning` 的 snackbar 用 `scheme.error/onError`，success 用 `scheme.primary` 淡底 + `scheme.primary` 前景 —— 未用 `onWarning/onSuccess`。

**Rule**：WCAG 2.1 SC 1.4.3（正文 ≥4.5:1）。

**Impact**：亮色 warning `#B26A00` 上白字 **4.24:1**、暗色同样配置在 `#121212` 上 **4.42:1**，都低于 4.5:1。B-02 的分档修复若只改底色不改前景，警告文字仍贴着门槛。当前 notifier 绕开语义色使问题被掩盖，一旦修复代理把 warning 接进语义色，问题会立刻显性化。

**Fix**（修复代理执行）：
1. 随 B-02 一起把 `onWarning` 亮色改 `#1F2328`（对 `#D29922` 暗底仍用 `#121212`），`onSuccess` 暗色改 `#121212`。
2. `lib/surface/app/notifier.dart:112-126` 三态统一用 `OgLSemanticColors` 的 success/warning/info + on*；`OgLNoticeTone.warning` 不要直接复用 `scheme.error`（语义错：警告≠错误）。
3. 在 `tool/contrast_audit.py` 增 `onWarning` 对 `warning`、`onSuccess` 对 `success` 的 ≥4.5 直接校验（当前只验 on* 对容器底，验不出这一对）。

**Effort**：small（色值 + notifier 三行 switch + 门禁多两条断言）。

---

### B-04 · `onErrorContainer` / `errorContainer` 从未显式定义，23 处错误提示文字走 M3 派生值（P1，令牌契约断裂）

**Where**
- `lib/surface/theme.dart:180-194`：`ColorScheme(...)` 只给 11 个角色，**无 `errorContainer` / `onErrorContainer`**。
- 消费点：`lib/surface/app/async.dart:587,593,598,602`；`lib/surface/app/token_exit_warning.dart:130`；`lib/surface/pages/legal_text_page.dart:106,113,120`；`login_page.dart:433,444`；`new_issue_page.dart:163,169`；`new_release_page.dart:216,222`；`new_repo_page.dart:176,182`；`onboarding_page.dart:452,458`；`settings_page.dart:1507,1513,1523`；`workflow_dispatch_page.dart:538`。
- `docs/MD2_MIGRATION_REPORT.md` §二明确要求「这些 M3 getter 全部从 lib/ 移除」——与页面实际用量矛盾。

**Rule**：`sota-frontend-design/rules/03`（单一事实源）；项目自身 `theme.dart:19`「颜色一律走 ColorScheme 或 OgLSemanticColors」。

**Impact**：`ColorScheme` 的 M3 兜底 getter 在 MD2 的任意 `primary/error` 组合上做临时 tonal 混色，意味着同一个「错误卡片」在不同主题色下底色/字色会偷偷漂移；而且 `errorContainer` 与显式 `error=#CF222E/#F85149` 不属于同一视觉族，用户会看到「普通错误红」和「错误卡片红」两套。截图 `settings__light_390x844.png` 主色直方有 `#251,251,251` 等邻近灰说明存在派生色带。

**Fix**（修复代理执行）：
1. 在 `ColorScheme` 构造中显式给 `errorContainer` / `onErrorContainer`（亮底建议 `#FFEBE9` + 字 `#CF222E`；暗底 `#3B1A18` + 字 `#FFB4AB`），与 `error` 同族。
2. 或按 MD2 迁移意图把 23 处改为 `OgLSemanticColors.errorSurface/onErrorSurface` 新字段，彻底移除 `errorContainer` 取用；两方案二选一，全仓不可混用。
3. `rg 'errorContainer|onErrorContainer' lib/` 复核取值来源只有 theme.dart 一处定义。

**Effort**：medium（1 处主题 + 校验 + 可能 23 处机械替换）。

---

### B-05 · `ColorScheme.shadow` 与 `ThemeData.shadowColor` 分裂；MD2 黑影层次自相矛盾（P1，投影体系）

**Where**
- `lib/surface/theme.dart:194`：`shadow: Colors.black`（**100% 不透明**）。
- `lib/surface/theme.dart:228`：`final Color md2Shadow = Colors.black.withValues(alpha: 0.26)`；`:233` `shadowColor: md2Shadow`。
- `lib/surface/theme.dart:254,265,288,299,339`：`Card=1 / Dialog=3 / Sheet=1 / SnackBar=3 / Rail=4`；`:227` 注释却写「卡2/AppBar4/菜单4/弹层16」；`docs/MD2_MIGRATION_REPORT.md` §四写「卡片 2、菜单级 4、弹层 8、对话框 16」。

**Rule**：MD2 elevation 档位单一事实源；`sota-frontend-design/rules/03`。

**Impact**：`ColorScheme.shadow` 是 Material 组件默认阴影来源之一（部分内部组件取 scheme.shadow），而 `ThemeData.shadowColor` 是另一条；两套黑度差 74%（纯黑 vs 26% 黑），同一 App 内可能出现两种强度的投影。文档说「弹层 16」实现是 1，用户看不到承诺中的层级差；实际截图 `dashboard__light_390x844.png` 白底 `#FFFFFF`、卡片边缘只能靠 `#6B6A71` 描边辨别，黑影几乎不可见。

**Fix**（修复代理执行）：
1. `shadow: md2Shadow` 与 `shadowColor: md2Shadow` 取同一个 `Color` 常量；删除 `Colors.black` 裸值。
2. 统一 elevation 档位并让代码/文档/迁移报告一致：建议 `Card=2 / Dialog=16 / BottomSheet=8 / SnackBar=6 / AppBar=4 / Rail=4`；若坚持现值，修正 `:227` 注释和 `docs/MD2_MIGRATION_REPORT.md` §四，避免下一轮修复照错误文档改。
3. 截图复核：亮色卡片在白底上必须同时可见描边与浅阴影；暗色卡片靠描边 + 阴影区分，不得「融进背景」。

**Effort**：small（主题 + 文档同步）。

---

### B-06 · `outlineStrong`（#6B6A71/#7F7E85）与 `scheme.outline`（#D0D7DE/#30363D）双轨描边并存（P1，视觉语言）

**Where**
- `lib/surface/theme.dart:120-121,222-223,243`：引入 `outlineVariantStrong`，明 `#6B6A71` / 暗 `#7F7E85`，声称对 surface ≥3:1。
- `lib/surface/theme.dart:189`：`ColorScheme.outline = 亮 #D0D7DE / 暗 #30363D`；`:464` `OutlinedButton` 用 `scheme.outline`；`lib/surface/pages/*` 大量用 `scheme.outline`。
- 对比度复算：`#D0D7DE` on `#FFFFFF` = **1.45:1**、on `#F6F8FA` = **1.36:1**；`#30363D` on `#121212` = **1.54:1** —— 形同虚设，正是引入 Strong 的理由。

**Rule**：`sota-frontend-design/rules/03`（同一角色只允许一个令牌）；MD2 无 M3 outlineVariant 概念。

**Impact**：同一个「边界」角色，卡片/分割线/输入框/Chip 用深灰 Strong，OutlinedButton 与页面局部用极浅 outline；用户在同一屏里看到深浅两种描边，亮色下 OutlinedButton 几乎消失。项目自己已经论证 outline 对比不足，却留着它承担按钮边界，属于半迁移。

**Fix**（修复代理执行）：
1. 全仓 `scheme.outline` 的边框/描边取用统一改 `Theme.of(context).extension<OgLSemanticColors>()!.outlineVariantStrong`（`theme.dart:464` 的 OutlinedButton 至少）；`ColorScheme.outline` 仅保留给内部组件的非可见用途或删除。
2. 把 `outlineVariantStrong` 重命名为 `outlineStrong`（MD2 无 `outlineVariant` 角色，去掉 M3 遗名），`copyWith`/`lerp`/消费点同步。
3. 门禁 `tool/ui_audit.py` 增规则：禁止 `BorderSide(color: scheme.outline)`，只允许 `outlineStrong`。

**Effort**：medium（主题 1 处 + 页面若干 + 门禁 1 条）。

---

### B-07 · AppBar 主题 `elevation:0` 与 `OgLAppBar` 内 `elevation:4` 打架（P1，投影语义）

**Where**
- `lib/surface/theme.dart:318-330`：`appBarTheme: AppBarTheme(elevation: 0, backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, ...)`。
- `lib/surface/app/og_l_app_bar.dart:137-151`：组件内硬写 `elevation: 4`；`:4-11` 注释仍写「M3 scrolledUnderElevation / surfaceTint 已移除」但 `:56` 写「不传时由 M3 原生 scrolledUnderElevation 提供边界」。
- 16 页用原生 `AppBar`（吃主题 elevation 0）、14 页用 `OgLAppBar`（硬写 4）——与 C 席 P1-1 同一事实。

**Rule**：投影语义单一事实源；代码洁癖（无旧体系残留注释）。

**Impact**：从有投影的顶栏页滑到无投影的顶栏页，顶栏是「浮起」还是「贴平」在跳变；主题声明的 elevation 0 与组件声明的 4 让用户/后续维护者无法判断哪个是设计意图。截图取样 `dashboard__light_390x844.png` y=50 行全为 `#FFFFFF`（顶栏与内容同色无边界），说明 OgLAppBar 的 4dp 投影在静止态几乎不可见。

**Fix**（修复代理执行）：
1. `theme.dart:322` 的 `appBarTheme.elevation` 改为 4；`OgLAppBar:146` 删除硬写 `elevation:4`，改为继承 `theme.appBarTheme.elevation ?? 0`。
2. 清理 `og_l_app_bar.dart:4-11,56,144-148` 的 M3 `scrolledUnderElevation` / `surfaceTint` 残留注释（代码洁癖铁律）；`theme.dart:320-321` 同类残留一并清。
3. 与 C 席 P1-1 联动：16 页原生 AppBar 收编到 OgLAppBar 后，顶栏投影自然统一；验收 `rg 'appBar: AppBar\(' lib/surface/pages` = 0。

**Effort**：medium（与 C 席协同）。

---

### B-08 · 启动首帧锚定色与正式主题亮度绑定来源不同，明暗切换瞬间闪色（P1，明暗一致性）

**Where**
- `lib/surface/app/boot_splash.dart:19` 注释仍写「与 MD3 seed 色板同族 / ColorScheme.fromSeed」（旧体系残留）。
- `lib/surface/app/boot_splash.dart:36-40`：`bg = dark ? #121212 : white`、`fg = dark ? #8B949E : #57606A` —— 硬编码复刻 theme.dart 值。
- `lib/surface/theme.dart:181,190`：`surface = 亮白 / 暗 #121212`；`onSurfaceVariant = #57606A/#8B949E` —— 数字相同但两处独立维护。
- `lib/main.dart:82,308`：先 `runApp(OgLBootSplash())`，初始化后第二次 `runApp(OgLApp(...))` 顶替。

**Rule**：单一事实源；MD2 明暗双主题一致性。

**Impact**：用户切换系统深色模式后在冷启动路径上，首帧取 `MediaQuery.platformBrightnessOf`，正式主题取 `surface.settings.brightnessFor(systemBrightness)`（用户可强制亮/暗）——两者不一致时（例如用户设「始终亮色」但系统是深色），首帧是深色、正式界面立刻翻白，出现一次明显闪白/闪黑。硬编码值一旦主题调色就会漂移。

**Fix**（修复代理执行）：
1. 把锚定色提到 `theme.dart` 的顶层常量 `kOgLSurfaceLight/kOgLSurfaceDark/kOgLOnSurfaceVariantLight/kOgLOnSurfaceVariantDark`，`buildOgLTheme` 与 `boot_splash.dart` 共用；启动页在 `runApp` 前读设置里的 `mode`（`settings.dart` 已提供静态方法则从桥外读，否则保留系统亮度并在文档说明）。
2. 删除 `boot_splash.dart:16-18` 的 MD3/fromSeed 注释，改注 MD2 令牌来源。
3. 截图核验：系统深色 + 用户亮色的组合下，首帧→首页无白/黑闪变。

**Effort**：small（常量提取 + 注释 + 设置读取）。

---

### B-09 · 错误兜底主题不走 `buildOgLTheme`，无投影/边框/语义色，和正常错误界面两个语言（P1，双主题一致性）

**Where**
- `lib/surface/app/og_l_app.dart:154-166`：`OgLBootFailureApp` 自建 `ThemeData(colorScheme: const ColorScheme.dark(primary: kOgLErrorSeedColor, secondary: kOgLErrorSecondary, surface: kOgLErrorSurface, error: kOgLErrorSeedColor))`。
- `lib/main.dart:372,385,411,422`：引导校验失败 / 模块依赖不满足时切到此主题。
- `lib/surface/theme.dart:32-36`：`kOgLErrorSeedColor / kOgLErrorSecondary / kOgLErrorSurface` 常量仅为此页存在。

**Rule**：`sota-frontend-design/rules/07`（同一产品同一视觉语言）；项目「颜色一律走 ColorScheme/OgLSemanticColors」原则。

**Impact**：引导失败是用户最容易慌的场景（「启动被拒」），此时界面字体、卡片、投影、分割线全部回退到 Material 默认（无 `cardTheme`/`dialogTheme`/`appBarTheme`），与正常页的 MD2 视觉断层；且 `ColorScheme.dark()` 只给 4 个角色，其余走 M3 派生，颜色和正常暗色主题（`#121212`/`#E6EDF3`）不共用。

**Fix**（修复代理执行）：
1. 用 `buildOgLTheme(Brightness.dark).copyWith(colorScheme: 基础scheme.copyWith(primary: kOgLErrorSeedColor, error: kOgLErrorSeedColor))` 构造兜底主题，保留组件主题与语义色扩展，只覆盖强调色。
2. 或者显式给 `ColorScheme.dark` 补齐 `onPrimary/onSecondary/onSurface/surfaceContainerHighest/outline/shadow` 与 `extensions: [OgLSemanticColors(...)]`，保证投影/描边一致。
3. 截图补 `boot_failure` 场景（当前 122 张矩阵无此 case），与暗色首页并排复核。

**Effort**：small（主题构造 + 1 张截图）。

---

### B-10 · 卡片/弹层同底色，暗色层级几乎只靠 1dp 阴影与描边（P1，投影可感知性）

**Where**
- `lib/surface/theme.dart:187,251`：`surface = 白/#121212`、`cardTheme.color = scheme.surface` —— 卡片与 scaffold 完全同色。
- `lib/surface/theme.dart:254`：`Card(elevation:1)`；`:288` BottomSheet `elevation:1`；`:265` Dialog `elevation:3`。
- `lib/surface/pages/dashboard_page.dart` 等大量 `Card(` 用默认主题（如 `:517` action_log `_JobCard`）。
- 截图取样：`dashboard__light_390x844.png` 主色第 1 名 `#FFFFFF` 占 1,228,751/1,316,640 ≈93.3%，卡片区与背景同色只能靠 `#6B6A71` 描边分辨；`dashboard__dark_390x844.png` `#121212` 占 1,224,058，另有 `#0D0D0D` 10,248 px 疑似阴影带。

**Rule**：MD2 elevation 语义（层级靠真投影表达）；`frontend-design`（视觉结构即信息）。

**Impact**：用户扫列表时「哪里是一张卡」主要靠细描边；1dp 的黑 26% 阴影在 2× 截图上仅几像素，弱于描边，层级感不足。MD2 标准卡 2dp、弹层 8dp 的层级差在当前实现里被压平（卡 1、弹层 1，相同！）。

**Fix**（修复代理执行）：
1. 配合 B-05：`Card=2 / BottomSheet=8 / Dialog=16`，且 `shadowColor` 统一；卡片与背景同色时描边 + 投影必须同时可辨。
2. 若暗色下阴影不可见（`#0D0D0D` 与 `#121212` 仅差 5/255），给暗色卡片加极轻的 `BorderSide` 提亮（沿用 `outlineStrong` 暗档 `#7F7E85`，已满足 3:1），不要把卡片底色改成 tonal 灰阶（MD2 非 MD3）。
3. 截图矩阵对 `dashboard`/`repo`/`settings` 亮暗各复核一次卡片边界。

**Effort**：small（主题数值 + 截图）。

---

### B-11 · 语义色扩展在 30 页里只有 6 个文件消费，success/warning/info 成为「半接入」令牌（P2，令牌一致性）

**Where**
- 消费 `extension<OgLSemanticColors>()` 的文件仅：`app/async.dart`、`pages/action_log_page.dart:502`、`pages/action_run_page.dart:492`、`pages/commit_page.dart:214`、`pages/repo_page.dart:3685`，加定义/容错文件共 6。
- 语义色 7 字段中 `warning / onWarning / info / onInfo` 的实际业务取用几乎为 0；`OgLNotifier` 成功/警告走 `scheme.primary/error`（见 B-03）。
- 状态点：`action_run_page.dart:492`、`:492-500` 用 `success ?? primary` 的容错回落。

**Rule**：`sota-frontend-design/rules/03`（令牌存在即须被采用）。

**Impact**：用户看到的「成功」在任务日志页是绿色、在 SnackBar 是蓝色主色、在错误卡片是红色；颜色语义不统一，学习成本高。容错回落 `?? primary` 还会让主题扩展缺失时静默变蓝，掩盖装配错误。

**Fix**（修复代理执行）：
1. 随 B-03 把 notifier 三态接语义色；逐页把状态点/状态徽标的 `scheme.primary`/`scheme.error` 替换为 `sem.success/sem.warning` 等。
2. 业务页将 `?? fallback` 改为 `!`（装配错误应在 debug 期暴露，而非静默变色）；`app/async.dart:389-393` 测试兜底可保留并注明仅测试用。
3. 验收：`rg 'Colors\.(green|orange|red|blue)|semantic' lib/surface/pages` 复核。

**Effort**：medium（多页机械替换）。

---

### B-12 · 设置页自定义色拾色器输出任意 ARGB，与 ColorScheme/语义色体系无约束（P2，色彩令牌）

**Where**
- `lib/surface/pages/settings_page.dart:214-235`：`BorderRadius.circular(OgLRadius.xl)` + `Color(argb)` 自定义色 swatch。
- `lib/surface/widgets/code_editor_field.dart:180-190`：`OgLCodeTheme(background: Color(customBackground), ...)` 直接用用户 ARGB 构造。
- `lib/surface/settings.dart:321-332,1039`：允许 preset=custom 与任意 int 色值持久化。

**Rule**：用户自定义属于数据（ui_audit 白名单允许），但应标注与主题色无关，避免误认为令牌。

**Impact**：用户选的「自定义代码高亮背景色」只影响代码区，不影响 App 其余部分——理解上合理，但设置页里它与「主题色」选择器视觉上并列，容易被误认为全站换色。低优先级。

**Fix**（修复代理执行）：
1. 在设置页两组选择器加分组标题/说明文案（走 i18n），明确「主题色＝界面强调色」「代码配色＝仅代码区」。
2. 保持 `Color(argb)` 数据属性，不改令牌纪律；在 `ui_audit.py` ALLOW 理由里补一句「自定义色与 UI 令牌无关」。

**Effort**：small（文案 + 注释）。

---

### B-13 · `FilledButton.tonalIcon` 在 MD2 下语义错位，保存按钮高亮色与全局按钮族不统一（P2，组件色彩）

**Where**
- `lib/surface/pages/code_editor_page.dart:600-618`：保存按钮用 `FilledButton.tonalIcon`，自行 `backgroundColor: _saveHighlighted ? primary@12% : surfaceContainerHighest`。
- `lib/surface/theme.dart:427-437`：`filledButtonTheme` 只定义标准 FilledButton（胶囊 + 主题色底）。
- `lib/surface/theme.dart:373`：`chipTheme.selectedColor = scheme.secondaryContainer`（MD3 角色派生）。

**Rule**：MD2 按钮族（Filled / Outlined / Text）；`sota-frontend-design`（同一角色统一视觉）。

**Impact**：用户在其他页点主按钮是实心蓝底白字，到代码编辑器点「保存」是浅灰底深字 + 高亮时淡蓝底，同一个「主操作」长得不一样；暗色下 `surfaceContainerHighest` 底 + `onSurfaceVariant` 字的对比度依赖派生角色。

**Fix**（修复代理执行）：
1. 保存按钮改用主题统一的 `FilledButton.icon`（或新增 `OgLPrimaryActionButton`），高亮态用 `sem.success`/`outlineStrong` 等明确语义而非 `primary@12%`。
2. `chipTheme.selectedColor` 改用 `scheme.primary.withValues(alpha: .12)` 或语义色，去 `secondaryContainer` 派生。
3. 截图 `code_editor__{light,dark}_390x844.png` 复核保存按钮与其他页主按钮观感一致。

**Effort**：small。

---

### B-14 · MD3 体系残留注释/死参数污染色彩投影文档（P2，代码洁癖）

**Where**
- `lib/surface/theme.dart:1`（「Material 3 + 组件级设计令牌」）、`:4`（`useMaterial3`）、`:78`（「Material 3 的 ColorScheme」）、`:169-171`（`overrideScheme`/`fromSeed`/Android 12 Material You 动态配色 —— 函数签名根本没有该参数）、`:211`（MD3 Typography）、`:218`（MD3 推荐）、`:320-321`（scrolledUnderElevation 由 MD3 原生接管）。
- `lib/surface/app/og_l_app_bar.dart:4-11,56`：旧的 `scrolledUnderElevation` / `surfaceTint` 语义。
- `lib/surface/app/boot_splash.dart:16-18`：`MD3 seed 色板` / `ColorScheme.fromSeed`。
- `docs/MD2_MIGRATION_REPORT.md` §一/§四/§五 与当前源码矛盾（见 B-02/B-05）。

**Rule**：批 1 纪律 3「无残留旧体系（MD3）痕迹」。

**Impact**：不直接产生视觉错误，但修复代理照注释/迁移报告执行会引入错误色值和错误 elevation（B-02/B-05 已实证）。属于「文档误导导致的未来视觉回归」风险。

**Fix**（修复代理执行）：
1. 全局替换上述注释为 MD2 语义；删除 `theme.dart:169-171` 不存在的 `overrideScheme` 段落。
2. `docs/MD2_MIGRATION_REPORT.md` 增「修订说明」段，注明「本文 §一/§四/§五 为 M-1 当期计划，最终以 62c5383 源码为准」，或直接更新到现值。
3. 门禁：加 `rg 'fromSeed|Material You|scrolledUnderElevation|useMaterial3|dynamic color' lib/surface` 必须为 0 条（除历史文档引用）。

**Effort**：small。

---

### B-15 · `outlineVariantStrong` 命名携带 MD3 遗名，且圆角令牌 `xl` 注释/值与 MD2 刻度冲突（P2，令牌体系）

**Where**
- `lib/surface/theme.dart:93,120-121`：`outlineVariantStrong` 字段与注释引用 `ColorScheme.outlineVariant`。
- `lib/surface/util/og_l_radius.dart:16,37-41,49-50,58`：`xl(28)` 注释还在，但值已改 12；`cXl` 标 `@Deprecated`，`verticalTopXl` 仍被 `theme.dart:287` 使用；`settings_page.dart:214` 用 `OgLRadius.xl`（12）画 48dp 触控区圆角。
- `docs/MD2_MIGRATION_REPORT.md` §三声称「xl=28 删除，verticalTopXl 保留」——实际 xl=12 仍在、verticalTopXl 仍在。

**Rule**：MD2 无 M3 `outlineVariant` / extra-large 28dp 概念；代码洁癖。

**Impact**：不影响当下渲染，但消费方照注释以为 `xl=28` 会得到错误圆角；`verticalTopXl`（12）与 `verticalTopLg`（16）大小倒挂，弹层上沿比大卡还方。

**Fix**（修复代理执行）：
1. 随 B-06 重命名 `outlineStrong`；`og_l_radius.dart` 把 `xl` 注释改成「中等浮层 12」，删 `cXl` 废弃常量（全仓 0 引用），`verticalTopXl` 改名为 `verticalTopMd`（12）或并入 `verticalTopLg`。
2. `settings_page.dart:214` 用明确档位（如 `OgLRadius.cMd`），避免依赖语义模糊的 xl。
3. 更新 `docs/MD2_MIGRATION_REPORT.md` §三。

**Effort**：small。

---

### B-16 · 错误提示卡片用 `errorContainer` 大红底 + `onErrorContainer` 字，和 SnackBar 错误语义重复且强度失衡（P2，色彩语义）

**Where**
- `lib/surface/app/async.dart:585-604`：`Material(color: scheme.errorContainer)` 整块错误卡片。
- `lib/surface/app/notifier.dart:120-124`：`warning` SnackBar 用整块 `scheme.error`（高饱和红底白字）。
- `lib/surface/pages/new_issue_page.dart:162-170` 等 4 页用 `Card(color: errorContainer)`。

**Rule**：`sota-ux-writing`/`frontend-design`（视觉强度与信息严重度匹配）。

**Impact**：用户提交失败时，页面里同时出现红底错误卡 + 红底 SnackBar，双重高饱和红色造成「出了大事」的错觉；而实际只是「未填写必填项」这类可恢复提示。与 `og_l_app_bar` 的冷静蓝灰语言反差大。

**Fix**（修复代理执行）：
1. 按 B-04 定下的 `errorContainer` 方案，统一改为浅底（亮 `#FFEBE9` / 暗 `#3B1A18`）+ 深色字 + `Icons.warning_amber_rounded`，与 `theme.dart:373` 的 Chip 层级一致。
2. `notifier.dart` 的 `warning` 从 `scheme.error` 改为 `sem.warning`（见 B-03），只有 `critical` 弹窗才用高饱和 `error`。
3. 截图 `login`/`new_repo`/`settings` 亮暗复核错误态（当前矩阵为成功路径，需补错误态 case）。

**Effort**：medium。

---

### B-17 · 截图矩阵缺少关键色彩状态用例，122 张无法覆盖 B-01~B-16 的多数场景（P2，核验覆盖）

**Where**
- `/tmp/uishots/` 122 张 = 31 场景 × 明暗 × 2 尺寸（其中 `home` 只有 2 张），场景列表见 `test/screenshots/screenshot_matrix_test.dart`。
- 场景集中在静态默认态；无「切换主题色 sunset/forest」「错误提示/警告 SnackBar」「启动失败兜底」「暗色成功状态点」等用例。
- 当前矩阵截图时间 `2026-11-28 07:32:14 +0800`，HEAD commit `2026-11-28 15:30:10 +0800` —— 截图早于当前提交 8 小时，不能作为 HEAD 的最终视觉证据。

**Rule**：批 1 验收「CI + ui-shots 截图核验」。

**Impact**：即使修复代理完成 B-01~B-16，也没有自动截图能证明问题闭环；历史截图与当前代码版本错位，容易误判。

**Fix**（修复代理执行）：
1. 在 `test/screenshots/screenshot_matrix_test.dart` 增加 dynamic case：主题色 `\`sunset\`` + 亮/暗、`OgLBootFailureApp`、notifier success/warning/critical 三态、任务日志 success/failure 状态点。
2. CI 每次生成截图携带 HEAD sha 与时间戳，报告引用时标注版本一致。
3. 本轮 Vision Group 503，恢复后补一次人工/模型视觉复核，不把「像素统计通过」等同于「视觉通过」。

**Effort**：medium。

---

## 2. 已检查清单（Checklist）

### 主题层 / 令牌定义
- [x] 通读 `lib/surface/theme.dart` 全 483 行（分两段读完，无跳读）
- [x] `ColorScheme` 11 个显式角色逐项核对明暗取值 + 11 个 M3 派生 getter 取用点
- [x] `OgLSemanticColors` 7 字段（`success/onSuccess/warning/onWarning/info/onInfo/outlineVariantStrong`）+ `copyWith`/`lerp` 实现
- [x] `kOgLSeedColors` 7 套主题色、`kOgLError*` 兜底色、`ogLSeedColorOf`/`ogLDensityOf`
- [x] 14 类组件主题：Card / Dialog / BottomSheet / SnackBar / AppBar / NavigationRail / ListTile / Divider / Chip / SegmentedButton / InputDecoration / FilledButton / TextButton / OutlinedButton / IconButton
- [x] `shadow: Colors.black` vs `ThemeData.shadowColor: 黑26%` 双轨核对
- [x] elevation 注释（卡2/弹层16）与代码（卡1/弹层1）逐项比对
- [x] `surfaceBridge.themeFor` 缓存键（brightness/seed/density/motion/uiFont）与 `buildOgLTheme` 入参一致性

### 页面 / 组件逐页抽查
- [x] `lib/surface/pages/*.dart` 30 页全覆盖 `Colors.*` / `Color(0x…)` / `withValues(alpha)` / `withOpacity` 扫描
- [x] 重点读 context：`code_editor_page.dart:600-629`、`repo_page.dart:2513/2807/3112/3362`（均 `Colors.transparent` 合法）、`settings_page.dart:205-235`（自定义色数据）
- [x] 逐页确认无页面级 `BoxShadow` / `elevation:` / `shadowColor:` 覆盖（全 lib `BoxShadow` 0 处）
- [x] `lib/surface/util/file_icons.dart` 的 ~55 个品牌色核实为「文件类型数据色」，非 UI 表面色（白名单理由成立）
- [x] `lib/surface/widgets/code_editor_field.dart` 高亮预设（高对比/柔和/fromScheme）核对
- [x] 语义色消费点 6 个文件逐一确认（async / action_log / action_run / commit / repo_page + 定义）

### 明暗双主题一致性
- [x] 明/暗 surface `白 / #121212`、onSurface `#1F2328 / #E6EDF3`、container `#F6F8FA / #1C2128` 源码核对
- [x] 语义色 success/warning/info 明暗是否分档（结论：未分档，B-02）
- [x] 启动首帧 `boot_splash.dart` 与正式主题色值逐一对齐（数值相同、来源独立，B-08）
- [x] 错误兜底主题 `OgLBootFailureApp` 与 `buildOgLTheme` 的结构差异（B-09）
- [x] WCAG 2.1 对比度复算：primary/onPrimary 7 套、semantic on* 4 对、outline 2 档、SnackBar error/success 前景共 20+ 组

### 门禁与截图核验
- [x] 运行 `python3 tool/contrast_audit.py` → 0 处问题（但脚本只检查 M3 容器底，盲区见 B-02/B-03）
- [x] 运行 `python3 tool/ui_audit.py` → 0 处令牌外字面值（白名单覆盖页面，不能证明颜色对比合格）
- [x] `/tmp/uishots/` 122 张文件数/场景分布核对（31 场景，home 只有 2 张；B-17）
- [x] 用 Pillow 对 `dashboard`/`code_editor`/`login`/`settings` 亮暗 8 张做主色直方 + 5 个分位行取样（数值见 B-02/B-05/B-10）
- [x] 尝试 Vision Group 读图 → 503 不可用；已在文档戳说明，不冒充视觉结论
- [x] 未读取 Flutter SDK / pub 缓存源码；未修改任何代码；未 commit / 未 push

### 与其他审计席的边界
- [x] 与 C 席（跨页一致性）重叠的 AppBar 双实现，仅从投影语义角度陈述（B-07），不重复其 16 页清单
- [x] 与 A 席（布局密度）不重叠：不报间距/尺寸/溢出问题
- [x] 所有问题均聚焦色彩、投影、明暗一致性或令牌纪律

---

## 3. 修复优先级建议（供修复代理排期）

| 优先级 | 条目 | 理由 |
|---|---|---|
| 先修（构成同一根因） | B-01 + B-02 + B-03 + B-11 | 全部围绕「主题色 / 语义色端到端生效」，一次重构闭环 |
| 先修（投影语义） | B-05 + B-06 + B-07 + B-10 | 全部围绕「elevation 档位 / 描边 / 投影单一事实源」，与 A/C 席 AppBar 收编协同 |
| 次修（令牌契约） | B-04 + B-08 + B-09 + B-16 | errorContainer 契约、启动/兜底主题对齐、错误态强度 |
| 收尾（洁癖/核验） | B-12 + B-13 + B-14 + B-15 + B-17 | 注释清理、命名、截图用例补齐 |

> 报告完 · B 席审计结束于 2026-11-28 17:19:33 (Asia/Shanghai) · HEAD `62c5383`
