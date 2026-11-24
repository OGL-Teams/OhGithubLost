# UI 深度复审 V2 · 批 2-A · 首屏与启动链路视觉

> **文档戳 / Doc Stamp**
> - 更新时间：**2026-11-24 22:48:12 (Asia/Shanghai)**
> - 复审对象版本：**v15.0.0**（HEAD `46981c0`；启动相关提交 `07c93f6`「3-1 外壳锚定——AppBar 全宽/切tab 0.94/滚动融合修复/启动底色与失败页滚动」）
> - 仓库：`/root/OhGithubLost`；**只读审计**：未改代码、未 commit / push；唯一产出本文件
> - 规范依据：`material-3/SKILL.md` Layout / App Shell / 8dp spacing / 宽屏限宽 anti-pattern + `sota-frontend-design/rules/02-layout-spacing-responsive.md` §1/§2/§3b/§4/§10
> - 证据纪律：每条 `file:line` 均可 `rg -n` 复现；只读 `lib/` 项目自身代码，未读 Flutter SDK / pub 缓存，未运行 dart（纪律要求只许 `dart format`）
> - 审计边界：原生 Android/iOS 启动图不在本仓库（`rg --files -uuu` 无 `android/`、`ios/`、`styles.xml`），原生层白屏无法从代码证实，本报告从 Flutter 首帧起算
> - **已否决候选**：曾怀疑 `boot_splash.dart:33` / `og_l_app.dart:72/113` 在 `runApp` 根部读 `MediaQuery.platformBrightnessOf` 会因无 MediaQuery 祖先而抛错；复核 Flutter 3.10+ 的 `runApp` 由 `View` 向根提供 MediaQuery、本项目 `pubspec.yaml:29` 要求 `flutter >=3.24.0`，**该候选不成立，不计入发现**。但其「只跟平台亮度」的语义缺陷仍成立（2-A-02）。

---

## 0. 结论速览

**最严重两条**：
1. **2-A-01（P1）** 首屏加载帧仍是「空白内容区 + 一枚裸转圈」（`dashboard_page.dart:435-436`）：v15 的骨架只落在 `AsyncView`（`async.dart:325/371`），首页自己的状态分支完全没接上，D-06 在最重要的一帧未闭环。
2. **2-A-02（P1）** 占位屏 → 主题帧仍闪变：v15「启动底色跟随」只跟了平台明暗（`boot_splash.dart:33/37-39`），用户强制 dark/light 与 Material You 都不跟（`surface_bridge.dart:499-503`、`og_l_app.dart:65-84`）；B-1 只修了一半。

| 维度 | 结果 |
|---|---|
| 旧确证闭环（6 条） | **已修 2 / 修法有问题 3 / 未修 1** |
| v15 首帧链路回归 | **4 条**（2-A-01～2-A-04） |
| 新发现 | **6 条**（2-A-05～2-A-10） |
| 分级统计 | **P0 × 0 / P1 × 5 / P2 × 5**（无「完全无法使用/数据丢失/安全」级问题） |
| 冷启动到可操作的空白/无锚点帧 | **2 帧**（回访：`_checked` 裸转圈 + 首页加载裸转圈）；首装用户 **1 帧**（首页加载），另有 1–2 次主题跳变帧 |
| 首屏锚定现状 | 有品牌图标 + 应用名 + 欢迎标题，但**等待帧退化为纯转圈**；首装引导首屏留白约 **45–50%** |

---

## 1. 闭环核对（旧确证逐条判）

> 编号口径：`docs/UX_STABILITY_PLAN.md:150`（G-06）、`:219`（D-05）、`:225`（D-06）、`docs/UX_CROSS_AUDIT/5-A-flows.md:13-25`（B-1/B-2/B-3）。

| 编号 | 判定 | 证据与理由 |
|---|---|---|
| **D-05** 空态占位（半屏空白 + 无 CTA） | **已修（首屏范围内）** | `dashboard_page.dart:443-467` 空态走 `OgLAsyncEmptyPane` + `FilledButton`（新建仓库 / 去发现），旧的 `SizedBox(height: screen*0.5)` 已删；统一出口 `async.dart:450-499` 已有 `maxWidth:320`、图标 `OgLIconSize.xl`、可选 `subtitle`、`action`。保留意见：`action` 仍是可选参数，14 页中未传 action 的调用点依旧无 CTA，但首屏确已修。 |
| **D-06** 骨架屏 / 裸转圈 | **修法有问题** | 统一出口 `async.dart:325` 的 loading 已换 `OgLAsyncSkeleton`，但 `:371-405` 的骨架是**两根固定矩形条（160/220dp）装在 `Center`**，形不成列表结构；更关键的是首页自身两处裸转圈原样保留：`dashboard_page.dart:435-436`（首屏首帧）、`:484`（列表尾部）。对首屏判「修法有问题」。 |
| **G-06** 启动链路锚定（总项） | **修法有问题** | B-1 部分修（只跟平台明暗，见 2-A-02）；B-2 **未修**（`client_shell.dart:278-280` 仍是纯转圈）；B-3 部分修（加了滚动，缺复制/重试且仍强制深色 + zh_CN，见 2-A-06/07）。计划要求的三态 `AnimatedSwitcher`（`UX_STABILITY_PLAN.md:152`）全库 `rg` 无命中，`client_shell.dart:272/278/285` 三分支直接换树 → 未落地（2-A-04）。 |
| **5-A · B-1** 占位屏配色脱节 → 闪白/闪黑 | **修法有问题** | `boot_splash.dart:37-39` 已用 `ColorScheme.fromSeed(seedColor: 0xFF0969DA, brightness: platformBrightness)`，与 `theme.dart:31/175` 同 seed，硬编码黑白已消除；但 `:33` 只读平台明暗，真实主题取 `surface.themeFor(brightnessFor(...))`（`og_l_app.dart:113`、`surface_bridge.dart:499-503`）且动态色由 `og_l_app.dart:65-84` 决定 → 用户强制 dark/light 或开 Material You 时首帧底色仍不同，顶替帧闪变依旧。另 `:58` 标题钉死 `fontSize:18`（2-A-09）。 |
| **5-A · B-2** `_checked` 裸转圈中间态 | **未修** | `client_shell.dart:278-280` 逐字仍是旧代码 `Scaffold(body: Center(child: CircularProgressIndicator()))`，无图标、无标题、无「正在恢复会话…」文案。该帧在 `refreshState()` + `activeAccount()`（`:111-114`）真实读盘期间显示，回访用户每次冷启动都过；首装用户因 `:272` 引导优先而跳过。计划「禁止任何只有转圈的帧」未达成。 |
| **5-A · B-3** 失败页长堆栈溢出 | **修法有问题（溢出已修，页面仍不完整）** | `og_l_app.dart:183-186` 已加 `SingleChildScrollView > ConstrainedBox(maxWidth:640)`，长堆栈不再 RenderFlex overflow，`:198` 标题改 `textTheme.titleLarge`。但计划同条要求的「复制日志」「重试启动」两个动作**没有**（`:188-209` 仅三段 Text/SelectableText），失败页仍是死胡同（2-A-06）；且启动早于 i18n 装载时文案退化成裸键（2-A-07）。 |

---

## 2. v15 回归：首帧链路新问题

### 2-A-01【P1】首页首帧是裸转圈，v15 骨架没接上

- **症状**：进入首页后，AppBar / 分段控件 / FAB / 底栏齐全，中间内容区约 90% 空白，正中一枚转圈；首次拉仓库列表要等网络往返，这段时间没有「在加载什么」的结构。
- **根因**：`dashboard_page.dart:435-436` 的 `if (p.items.isEmpty && p.loading) return const Center(child: CircularProgressIndicator())` 未随第二批改造；`async.dart:371-405` 的 `OgLAsyncSkeleton` 只服务 `AsyncView`。首页用自己的 `_RepoPaged + ListenableBuilder`（`:430`），不在 `AsyncView` 覆盖范围内。
- **修复指令**：`dashboard_page.dart:435-436` 换列表骨架（行高 56/72dp 对齐 ListTile，色 `surfaceContainerHighest`、`OgLRadius.cSm`），`async.dart:371-405` 骨架升级为 `itemCount/itemBuilder` 可复用形态；`dashboard_page.dart:484` 尾部转圈同步换 3 行行内骨架。

### 2-A-02【P1】占位屏 → 主题帧闪变：用户主题设置与动态配色都没跟

- **症状**：用户选「暗色」但系统是浅色 → 首帧白底、第二帧黑底；开启 Material You → 首帧种子蓝灰、第二帧壁纸色，两次可见跳变。
- **根因**：`boot_splash.dart:33/37-39` 只按平台明暗取 seed surface；真实主题由 `surface_bridge.dart:499-503` 的 `brightnessFor`（用户 mode 优先）与 `og_l_app.dart:65-84` 的 `dynamicScheme` 决定。seed 还被硬编码在 `boot_splash.dart:38`，用户改 `seedColorId` 后首帧不跟。
- **附带回归**：`og_l_app.dart:95` 的 `themeAnimationDuration: OgLAnim.slow` 让这次底色切换变成缓慢可见的变色，比 v14 的硬切更惹眼。
- **修复指令**：`main.dart:82` 之前先做最小 KV 读拿到 mode / seedColorId / dynamicColor（`surface_bridge.dart:669-676` 的 settings 读取可提前），传给 `OgLBootSplash(background:, foreground:)`；`boot_splash.dart:38` 删硬编码 seed。动态色在首帧拿不到壁纸色时，宁可多显示一帧占位屏，不要先显示错误底色。

### 2-A-03【P2】动态配色晚到造成的二次变色

- **症状**：Material You 开启时，即便 2-A-02 修好平台明暗，`DynamicColorBuilder`（`og_l_app.dart:65`）回调先 null 后非 null，主题再编译一次（`themeFor` 缓存键含 `dynamicScheme`，`surface_bridge.dart:540-545`），叠加 `themeAnimationDuration` 形成第二段变色。
- **修复指令**：`DynamicColorBuilder` 回调拿到结果后再执行第二次 `runApp`（即把 `runApp(OgLApp)` 从 `main.dart:303` 挪到配色就绪时），或首次装载时禁用主题动画、稳定后再开。

### 2-A-04【P1】三态切换无过渡，品牌锚点被硬切抹掉

- **症状**：占位屏（有图标有标题）→ 裸转圈（什么都没有）→ 引导/首页，三次硬切；v15 第三批「去整页缩放」只处理了 tab 切换（`client_shell.dart:414-508` 的 `_OgLShellSlide`），启动链路一个都没接。
- **根因**：`client_shell.dart:272/278/285` 三个 `return` 直接换树，没有 `AnimatedSwitcher`；`UX_STABILITY_PLAN.md:152` 要求的三态过渡未实现。
- **修复指令**：把 `:270-289` 的三分支包进 `AnimatedSwitcher(duration: OgLAnim.medium(context), switchInCurve: OgLAnim.curve(context))`，每个分支加 `ValueKey`；同时把 `:278-280` 换成带品牌图标/标题的恢复屏（与 B-2 同改）。

---

## 3. 新发现：启动每一帧用户看到什么

### 3.1 逐帧清单（回访用户，设置已完成）

| # | 帧 | 用户看到 | 空白？ | 证据 |
|---|---|---|---|---|
| 0 | 进程 → Flutter 首帧 | 原生启动图（本仓库无原生配置，**不可审**） | 未知 | `rg --files -uuu` 无 `android/`、`ios/` |
| 1 | `runApp(OgLBootSplash)` | hub 图标(56dp) + 「OhGithubLost」(18px) + 22dp 转圈，底色 seed surface | **有锚点，但无「在做什么」文案** | `main.dart:82`、`boot_splash.dart:49-68` |
| 2 | 日志落盘 / 平台存储 / 内核引导 await 区间 | 同一占位屏，转圈空转 | 非空但**干等** | `main.dart:84-245`，分阶段耗时在 `:264-269` 才记录 |
| 3 | 第二次 `runApp(OgLApp)` | 主题换装帧；强制主题 / Material You 下**闪白或变色** | 非空，跳变 | `main.dart:303`、`og_l_app.dart:65-118` |
| 4 | `_checked == false` | `Scaffold + 居中裸转圈` | **空白帧 ①** | `client_shell.dart:278-280`，等 `refreshState()+activeAccount()` `:111-114` |
| 5 | 首页 `p.loading` | AppBar / 分段 / FAB / 底栏齐全，内容区 ~90% 空白 + 一枚转圈 | **空白帧 ②** | `dashboard_page.dart:435-436`，首帧后发起 `_bootstrap()` `:122` |
| 6 | 数据落地 | 仓库列表（ListTile 56/72dp） | 有内容 | `dashboard_page.dart:467-509` |
| F | 启动失败分支 | 错误页：标题 + 数据未改动 + 等宽堆栈 | 有文字但**无动作** | `og_l_app.dart:183-209` |

**首装用户**：第 4 帧被引导页替代（`client_shell.dart:272-275`），引导页有品牌图标 + 欢迎标题；第 5 帧仍要过。**结论：冷启动到可操作共 2 个空白/无锚点帧（回访）/1 帧（首装），外加 1–2 次主题跳变帧。**

### 3.2 首装引导页留白量化

- **假设**：360×640dp、系统字号 100%、无 AppBar（`onboarding_page.dart:227` 仅 review 模式有）。
- 可用高度 ≈ 640 − SafeArea 上下 ≈ 40 − 进度条区 ≈ 24 − 底部导航区 ≈ 72 = **~504dp**。
- 欢迎步内容（`onboarding_page.dart:324-352`）：顶部 24 + hero 56 + 16 + 标题 ~32 + 8 + 正文 2 行 ~40 + 16 + 平台 Card ~72 = **~264dp**。
- **留白 ≈ 240dp ≈ 内容区 45–50%**，全部集中在卡片下方到导航条之间——视觉上就是「孤零零的图标 + 一张小卡」漂在中上部，与用户判词「空、漂浮感」一致。`02-layout-spacing-responsive.md` §1 要求相关项更近、无关项更远，但这里没有可聚拢的内容，纯粹是**信息量不足**。
- 文件头注释（`:3-10`）承诺「语言与外观放第一步，必须在用户看懂任何文案之前定下来」，实际 `_welcomeStep` 只有平台卡片（`:324-352`），**语言/外观一步都没有**，首装用户无法先定语言，也看不到偏好入口。

### 3.3 其余新发现

- **2-A-05【P1】内核启动无超时——无限裸转圈没有出口**：`main.dart:222` 的 `await kernel.boot(...)` 无 `.timeout`；全文件唯一 timeout 是 `main.dart:343` 对权限自检的 5s，而权限自检已被移出关键路径（`:259-266`），不是会挂住首屏的那一步。计划中的 15s 超时（`UX_STABILITY_PLAN.md:152`）未实现。修复：`main.dart:222` 加 `.timeout(const Duration(seconds:15), onTimeout: () => throw KernelBootException('启动超时…'))`，走已有失败页；`boot_splash.dart` 进度环下补一行阶段文案，超 5s 再叠「仍在启动，可重启应用」。
- **2-A-06【P1】失败页是死胡同**：`og_l_app.dart:188-209` 只有标题 / 数据未改动 / 等宽堆栈三段文字，没有「复制日志」「重试启动」或回首页入口；长堆栈虽可滚动（`:184`），用户读完唯一动作是手动杀进程。
- **2-A-07【P2】失败页 i18n 与主题双重脱节**：`og_l_app.dart:166` 硬编码 `Locale('zh','CN')`、`:177` 硬编码 `Brightness.dark` + error seed（旧 B-4 未修）；若启动在 `SurfaceLayerModule.onRegister` 装载 i18n 之前失败（`surface_bridge.dart:668-688`），`OgLI18n._raw` 返回**裸键名**（`og_l_i18n.dart:265-275`），失败页直接显示「bootRejected」「dataUntouched」——最不该出错的一页反而最不可读。修复：失败页文案改传字面量兜底，亮度/语言跟随平台。
- **2-A-08【P2】转圈规格不一**：占位屏 22dp / stroke 2.2（`boot_splash.dart:66-67`）、首页 24dp（`dashboard_page.dart:436`）、引导权限步默认 CircularProgressIndicator（`onboarding_page.dart:364`）、`OgLIconSize` 体系 16/18/20/24，四套并存；旧 B-6 要求二选一统一，至今未做。
- **2-A-09【P2】占位屏标题字号不跟缩放**：`boot_splash.dart:57-61` 硬编码 `fontSize:18` + `letterSpacing:0.5`，不随 `TextScaler`；用户 130%/200% 字号下，首帧→`OgLApp` 的夹紧缩放（`og_l_app.dart:100-108`）之间有一次字号跳变（1-B 席同发现，本席回链确认在首帧链路可见）。
- **2-A-10【P2】空态按钮文案与落点不符**：`dashboard_page.dart:460-466` 星标空态按钮文案「去搜索」，点击 `_goDiscover()`（`:151-158`）push 的是**发现页**；首页 AppBar 已有一步直达仓库搜索（`:169-177`）。新用户被「去搜索」带到发现页，与同名入口语义冲突。改 `_goDiscover` 为 `_openRepoSearch`，或把文案改成「去发现」。

---

## 4. 用户满意度：新用户第一印象

- **有内容锚点吗？** 部分有。占位屏 hub 图标 + 应用名（`boot_splash.dart:52-61`）与引导首屏同款图标（`onboarding_page.dart:328-341`）一致，锚定设计本身正确；但锚点在**第 4/5 帧被裸转圈抹掉**，而这两帧恰是用户判断「靠不靠谱」的时刻。
- **知道下一步做什么吗？** 引导页有 1/3 进度条与「下一步」按钮（`onboarding_page.dart:257-310`），首步即启用，这部分合格；但欢迎步只有一句「你的文件只属于你…」+「当前平台」卡（`:334-350`），**没有说明 3 步分别做什么、为什么要授权**，也没有跳过入口；等待帧完全没有文案。
- **等待有结构吗？** 没有。启动 await 区间无阶段文案，恢复会话帧是纯转圈，首页首帧是纯转圈；v15 的骨架改造**恰好没覆盖首屏**。
- **出错可读/可恢复吗？** 可读但不可恢复（2-A-06/07）；最坏情况显示裸键名。
- **综合判词**：v15 把「品牌首帧」立住了，但**从品牌首帧到可操作内容之间又挖了两个空洞**，主题换装帧的闪变抵消了首帧建立的一致感。第一印象仍是「闪一下 → 转两圈 → 才看到东西」。

---

## 5. 修复优先级（具体到文件与值）

| 级别 | 编号 | 修复落点 |
|---|---|---|
| **P1** | 2-A-01 | `dashboard_page.dart:435-436 / :484` 换列表骨架；`async.dart:371-405` 骨架升级为 `itemCount/itemBuilder`，行高 56/72dp、色 `surfaceContainerHighest` |
| **P1** | 2-A-02 | `main.dart:82` 前读设置 → `OgLBootSplash(background/foreground/mode/dynamic)`；`boot_splash.dart:38` 删硬编码 seed |
| **P1** | 2-A-04 | `client_shell.dart:270-289` 三态包 `AnimatedSwitcher(duration: OgLAnim.medium(context))`，同时把 `:278-280` 换成带图标/标题的恢复屏 |
| **P1** | 2-A-05 | `main.dart:222` `kernel.boot(...).timeout(const Duration(seconds:15))`；占位屏补阶段文案 |
| **P1** | 2-A-06 | `og_l_app.dart:188-209` 加「复制日志」`FilledButton.tonal`（写 clipboard）与「重启应用」入口 |
| **P2** | 2-A-03 | `runApp(OgLApp)` 延到 `DynamicColorBuilder` 配色就绪后，或首次装载禁用主题动画 |
| **P2** | 2-A-07 | `og_l_app.dart:166/177` 亮度/语言跟随平台；失败页文案用字面量兜底 |
| **P2** | 2-A-08/09 | `boot_splash.dart:57-61/:66-67` 进度环统一 24dp/stroke 2、标题改 `titleMedium` 或传 `TextScaler` |
| **P2** | 2-A-10 | `dashboard_page.dart:151-158` `_goDiscover` 改 `_openRepoSearch`，或按钮文案改「去发现」 |

---

## 6. 本席对三问的回答

**问 1 · 闭环核对**：6 条里 **已修 2 / 修法有问题 3 / 未修 1**。D-05 首屏空态（含 CTA）确已修；D-06 统一出口换了骨架但首页两处裸转圈原封不动，判修法有问题；G-06 总项里溢出（B-3 一半）与硬编码黑白（B-1 一半）修了，但 `_checked` 裸转圈（B-2）、15s 超时、三态 AnimatedSwitcher、失败页动作全没落地；B-1 因不跟用户 mode / Material You 仍会闪变，B-3 因无恢复动作与裸键名退化仍算修法有问题。

**问 2 · 回归**：有，**4 条**：首页首帧没接骨架（第二批改造范围缺口）；占位屏只跟平台亮度、不跟用户 mode / 种子色，顶替帧仍闪变；Material You 晚到造成二次变色；三态切换无过渡（第三批只做了 tab 切换）。另占位屏 18px 硬编码标题在字号缩放下仍是跳变点。曾怀疑的根部 MediaQuery 崩溃已复核否决（见文档头）。

**问 3 · 新发现**：**6 条**（无启动超时、失败页死胡同、失败页裸键名/强制深色、转圈规格四套并存、标题字号不跟缩放、空态按钮文案与落点不符），加上 §3.1 逐帧清单与 §3.2 留白量化（首装引导首屏约 45–50% 空白）。**冷启动到可操作：回访 2 个空白帧、首装 1 个，外加 1–2 次主题跳变帧。**

---

## 7. 已检查清单（全覆盖声明）

- [x] `docs/UI_AUDIT_V2_BRIEF.md` 全文（纪律 / 三问 / 收口格式）
- [x] `material-3/SKILL.md` Layout / App Shell 示例 / 8dp spacing / 宽屏限宽 anti-pattern；`sota-frontend-design/rules/02-layout-spacing-responsive.md` §1/§2/§3b/§4/§10（逐节读完）
- [x] `lib/main.dart`（1-418 全文件）：两次 runApp 时序、await 链、错误 handler 挂载顺序、失败分支、超时缺口
- [x] `lib/surface/app/boot_splash.dart`（1-75 全文件）：背景/前景来源、context 层级、图标/标题/进度环尺寸、间距令牌
- [x] `lib/surface/app/og_l_app.dart`（1-250 全文件）：ListenableBuilder + DynamicColorBuilder 层级、themeFor 调用、builder 内缩放、失败页完整结构
- [x] `lib/surface/app/client_shell.dart`（1-509 全文件）：`_checked` 中间态、三态分支、登录门、懒挂载、限宽下沉、tab 过渡
- [x] `lib/surface/pages/onboarding_page.dart`（1-517 全文件）：三步结构、进度条、欢迎步、权限步骨架、许可步、导航条
- [x] `lib/surface/pages/dashboard_page.dart`（1-639 全文件）：AppBar、分段、首屏加载/空/错/数据四分支、列表尾部、空态 CTA 与落点
- [x] `lib/surface/app/async.dart`（45-124、290-502）：300ms 防抖/最小显示、`AsyncView` 四态、`OgLAsyncSkeleton`、`OgLAsyncEmptyPane`
- [x] `lib/surface/theme.dart:160-214` + `lib/surface/surface_bridge.dart:490-545/665-688`：seed、brightnessFor、themeFor 缓存与 i18n 装载时序
- [x] `lib/surface/i18n/og_l_i18n.dart:246-275`：文案三级兜底（当前语言→英文→裸键）
- [x] `lib/surface/util/og_l_space.dart`、`og_l_radius.dart`：尺寸令牌实值（xl=24、hero=56 等）
- [x] `docs/UX_STABILITY_PLAN.md:150/219/225/474-482/499`、`docs/UX_CROSS_AUDIT/5-A-flows.md:9-41/131` 及旧审计命中项
- [x] `assets/i18n/zh/{shell,onboarding,dashboard_page}.json` 关键键存在性与中文措辞
- [x] `test/surface/smoke_test.dart:46-70`：现有启动测试覆盖面（仅失败页 + AsyncView，无 boot splash）
- [x] `changed/_posts/2026-11-22-v15.0.0.md`：v15 四批声明，用于核对「声明已修」与代码实际
- [x] 原生启动图配置：`rg --files -uuu` 确认仓库内无 `android/`/`ios/`/`styles.xml`，已在报告边界声明不可审
- [x] 未读 Flutter SDK / `/opt/flutter` / `/root/flutter` / `/tmp/dart-sdk` / pub 缓存；未运行 dart；未改代码、未 commit/push；仅写入本报告一个文件
