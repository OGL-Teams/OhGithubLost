# UI 深度复审 v2 · 批 1-B · 排版与字体复审

> **文档戳**：2026-11-24 22:29:16 (Asia/Shanghai) · **v15.0.0**
> **席次**：1-B（主题与视觉基座 · 排版字体）｜**只读审计**，不修改任何代码。
> **证据基准**：`/root/OhGithubLost` 当前工作树；所有 file:line 均可用 `rg` 复现。
> **规则依据**：`/var/minis/skills/material-3/references/typography-and-shape.md`（MD3 Type Scale / Component Type Usage）、`/var/minis/skills/sota-frontend-design/rules/01-typography-and-color.md`（§1/§2/§3b）。
> **纪律**：禁读 Flutter SDK（未读取 `/root/flutter`、`/opt/flutter`、pub 缓存源码）；本地 dart 仅用于版本查询，未格式化/编译任何项目文件。

---

## A. 闭环核对：旧确证中属排版的条目逐条判定

| # | 旧确证（出处） | 判定 | 当前证据 / 说明 |
|---|---|---|---|
| C1 | `MD3_AUDIT.md:40` 扣分点：`theme.dart` 6 处字面 fontSize（dialog 20/14、appBar 18、snackBar 14、navBar 12、chip 12、按钮 14×4），未从 textTheme 派生，主题字体调整不联动 | **已修（修法有问题，见 B 节）** | `theme.dart:202` `final TextTheme tt = ThemeData(brightness: brightness).textTheme`；派生点 `:259/:265/:291/:316/:343/:402/:465/:477/:490/:454`。字面值已全部消除（仅 `:343` 保留 `?? 12` 作 null 兜底）。但派生**目标档位**存在层级错误 → B2/B4。 |
| C2 | `MD3_AUDIT_V2.md:42–50` Fix #1 自评「6 处全部派生、门禁 0 处字面值」 | **已修（自评成立，但结论过宽）** | `rg 'fontSize\s*:' lib/surface/theme.dart` 确实仅 `:343` 一处且为令牌派生；但「全站联动」不成立：`navigationRailTheme`、分段控件仍走继承默认（B5/B6），6 处等宽文本无字号令牌（D3）。 |
| C3 | SZ-06 / `audit_ui_full.md:125`：等宽正文 `fontSize:12/13` 裸值 26 处无语义 | **已修** | `lib/surface/util/og_l_font.dart:9–14` `monoSm=12 / monoMd=13`；`rg 'fontSize\s*:' lib/` 中 26 处走 `OgLFont.*`。26→2 档收敛成立。 |
| C4 | B20 / `audit_spec_b.md:150,197`：notifications mono `fontSize:12` const 样式不随 TextScaler 放大 | **已修** | `lib/surface/pages/notifications_page.dart:370` 已改 `fontSize: OgLFont.monoSm`（抽象 sp 值，受 TextScaler 缩放）。 |
| C5 | `UX_CROSS_AUDIT/1-B-shell-appbar.md:245`：顶栏标题用 `titleLarge`（22sp）符合 M3 large top app bar | **已修并保持** | `theme.dart:316` `tt.titleLarge`；`centerTitle:false`（`:284`）——未见回潮。 |
| C6 | `UX_CROSS_AUDIT/5-B-a11y.md:198–203` A-M6：2.0x 下 release 资产键 72dp 固定列挤成竖条 | **未修** | `lib/surface/pages/release_detail_page.dart:429` 仍 `SizedBox(width: 72, child: Text(key))`；修复指令（ConstrainedBox+IntrinsicWidth 或 Wrap）未落地。见 B8。 |
| C7 | 5-B A-M7：38dp 固定桌面标题栏在 2.0x 裁切标题 | **修法有问题（风险已缓解、根因未除）** | `desktop_window.dart:43` `kOgLTitleBarHeight = 38` 仍在；但标题样式当前是 `theme.textTheme.labelMedium`（12sp，`:157`），2.0x=24px<38dp，**标题不再被裁**。真正遗留是窗口按钮 46×46<48（触控目标，归 5-C）。 |
| C8 | 5-B A-L2：README 图片固定 `maxHeight:320` 在 2.0x 裁掉 alt 文字 | **未修** | `lib/surface/widgets/readme_view.dart:579` 仍 `const BoxConstraints(maxHeight: 320)`。见 B9。 |
| C9 | 5-B A-L3：日志搜索面板 `maxHeight:420` 不随缩放 | **未修** | `lib/surface/pages/action_log_page.dart:540` 仍 `const BoxConstraints(maxHeight: 420)`。见 B9。 |
| C10 | `UX_STABILITY_PLAN.md:257–258`：README 行高 1.5→1.35、blockSpacing 12→8、h1/h2 降一档 | **未修（v15 计划未落地）** | `readme_view.dart:385` 仍 `p: body.copyWith(height: 1.5)`、`:386–387` 仍 `headlineSmall/titleLarge`。属排版核心 → B10。 |
| C11 | 5-C C-L4：编辑器缩放用 `Icons.remove/add` 与其它页 `text_decrease/increase` 不一致 | **未修** | `lib/surface/widgets/code_editor_toolbar.dart:159/168` 仍 `Icons.remove / Icons.add`。图标语义归 3-A，此处仅登记。 |

**闭环小结**：排版旧确证 11 条 → 已修 5（C1/C2/C3/C4/C5）、修法有问题 2（C1 的目标档位 / C7）、未修 4（C6/C8/C9/C10）+ 跨席 1（C11）。**C1 的「已修」仅限「裸值消除」，不等于「层级正确」。**

---

## B. 回归：textTheme 派生后各组件字号层级逐项核对

对照 MD3 Component Type Usage（skill reference 行 56–72）：

| 组件 | M3 应有档位（sp） | 当前实现（theme.dart） | 判定 |
|---|---|---|---|
| Dialog 标题 | Headline Small（24） | `:259` `tt.titleLarge`（22） | ❌ **P1 层级偏差（B2）** |
| Dialog 正文 | Body Medium（14） | `:265` `tt.bodyMedium` ✅ `height:1.5` | ✅ |
| AppBar 标题 | Title Large（22） | `:316` `tt.titleLarge` ✅ | ✅ |
| SnackBar 文本 | Body Medium（14） | `:291` `tt.bodyMedium` ✅ `height:1.4` | ✅ |
| NavBar 标签 | Label Medium（12） | `:343` `fontSize:(tt.labelMedium?.fontSize ?? 12)` ✅ | ✅ |
| Chip 标签 | **Label Large（14）** | `:402` `tt.labelSmall`（**11**） | ❌ **P1 过小（B3）** |
| 按钮（filled/text/outlined） | Label Large（14） | `:465/:477/:490` `tt.labelLarge` ✅ | ✅ |
| 输入框 hint | Body Medium（14，floating label Body Small） | `:454` `tt.bodyMedium` ✅ 但与输入值 Body Large(16) 不同档（B7） | ⚠ P2 |
| NavRail 标签 | Label Medium（12） | `:365–366` 仅 color，**无 fontSize** | ⚠ P2（B5） |
| SegmentedButton 标签 | Label Large（14） | `:412–414` `const TextStyle(fontWeight:w500)` **无 fontSize** | ⚠ P2（B6） |
| 页面正文/列表标题 | M3 Body Large/Medium | 无主题级 titleTextStyle；页面走 `textTheme.bodyLarge/bodyMedium`（全库 rg 已核） | ✅ 统一走 textTheme，无裸值 |

### B2 · P1 · Dialog 标题档位低于 M3 规范
- **症状**：所有 AlertDialog 标题（settings_page.dart 十余处、issue_page/repo_page 等）比 M3 规范小一档，弹窗缺乏「层级压制感」。
- **证据**：`theme.dart:259` `tt.titleLarge?.copyWith(...)`（22sp / w600 / height1.3）；M3 Dialog headline = Headline Small 24sp（skill reference :65）。历史值 20sp（旧 `:224`）→ v15 改 22sp，方向对但没到规范档。
- **根因**：Fix #1 只做「字面值→textTheme 的结构替换」，未做「目标档位与 M3 Component Type Usage 的语义核对」。
- **修复指令**：`lib/surface/theme.dart:259` 将 `tt.titleLarge?.copyWith` 改为 `tt.headlineSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600, height: 1.3)`；同步把 `height:1.3` 调为 1.25（24sp×1.25=30sp，贴近 M3 headlineSmall 32sp 行高）。注意 30 个 i18n 分片的长标题弹窗需回归一次换行。

### B3 · P1 · Chip 标签降到 Label Small（11sp），明显过小
- **症状**：筛选胶囊/状态标签文字在 1.0x 下仅 11sp，中文标签比周边正文（bodyMedium 14）小三档，需凑近看；这正是用户点名质疑的「chip labelSmall 变 11 过小」。
- **证据**：`theme.dart:402` `labelStyle: tt.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: w500)`；旧值为 12sp（旧 `:355`），Fix #1 把它从「12 的近似值」映射到了「11 的精确小档」，反而**变小**。`rg 'labelSmall' lib/surface/theme.dart` 可复现。
- **根因**：M3 spec 的 Chip label 是 **Label Large（14sp）**，而 Fix #1 按「12≈labelSmall」做数字近似映射，选错语义档。违反 sota 01 §1「任何持续阅读文本不低于 14px」。
- **修复指令**：`lib/surface/theme.dart:402` 改为 `tt.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)`；同时检查 `ChipThemeData.padding`（`:405–408`，当前 x=sm/y=xxs）在 14sp 下不挤压，必要时 vertical→sm。

### B4 · P1 ·（与 B2/B3 同源）派生映射未经语义校验
- 一个修复动作（Fix #1）同时引入两处档位错误（Dialog 低一档、Chip 低两档），说明「从 textTheme 派生」不是充分条件；建议在 `tool/ui_audit.py` 增加一条静态规则：`chipTheme.labelStyle` 不得引用 `labelSmall`、`dialogTheme.titleTextStyle` 不得引用 `titleMedium/titleLarge`，防止回潮。

### B5 · P2 · NavRail 标签未派生，与 NavBar 的 12/12 一致但脱钩
- **证据**：`theme.dart:365–366` `selectedLabelTextStyle: TextStyle(color: scheme.onPrimaryContainer)` / `unselected...` 均无 fontSize；NavBar `:343` 显式 12。当前 M3 默认 labelMedium=12，二者显示一致，**但 rail 不随 `tt` 调整**。
- **修复指令**：两处改为 `tt.labelMedium?.copyWith(color: ..., fontWeight: w600/w500)`，与 NavBar 同源。

### B6 · P2 · SegmentedButton 用 const TextStyle，字号继承默认
- **证据**：`theme.dart:410–414` `textStyle: const WidgetStatePropertyAll<TextStyle>(TextStyle(fontWeight: FontWeight.w500))`——无 fontSize、无 fontFamily。缩放走框架默认 labelLarge 14，**没有变成 14 的裸值问题**，但与本文件其余 10 处的派生策略不一致。
- **修复指令**：把 `const` 属性改为 `WidgetStatePropertyAll<TextStyle>(tt.labelLarge!.copyWith(fontWeight: FontWeight.w500))`；注意 `tt` 是运行时值，不能 const。

### B7 · P2 · 输入框 hint（14）与输入值（16）字号不同档
- **证据**：`theme.dart:454` `hintStyle: tt.bodyMedium`（14）；`InputDecorationTheme` 未设 `style`，`TextField` 默认走 `textTheme.bodyLarge`（16）。字号跨越 M3 Body 两档，占位文字与用户输入值大小不一。
- **修复指令**：若希望 hint 与值同档，改 `hintStyle: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)`；若刻意弱化，保持现状但在注释写明「hint 刻意比值小一档」，并确认 3-C 席的 placeholder-as-label 治理不受影响。

### B8 · P1 · 2.0x 下 Release 资产键列 72dp 固定（旧 A-M6 未修）
- **症状**：用户把字号拉到 200% 后，键名折成 3–4 行、值列大片空白，扫读断裂（WCAG 1.4.4 Reflow 风险）。
- **证据**：`release_detail_page.dart:429` `SizedBox(width: 72, child: Text(key))`；缩放夹紧上界 2.0 在 `og_l_app.dart:113`。72dp 不随 TextScaler 增长。
- **修复指令**：改 `ConstrainedBox(constraints: const BoxConstraints(minWidth: 72), child: IntrinsicWidth(child: Text(key)))`，或窄屏/大字体切 Column；加 2.0x golden test。

### B9 · P2 · 两处固定 maxHeight 在 2.0x 裁切（旧 A-L2/A-L3 未修）
- **证据**：`readme_view.dart:579` `const BoxConstraints(maxHeight: 320)`；`action_log_page.dart:540` `const BoxConstraints(maxHeight: 420)`。
- **修复指令**：分别改为 `maxHeight: 320 * MediaQuery.textScalerOf(context).scale(1)` / `420 * ...`（去掉 `const`），或去掉上限由内容撑开。

### B10 · P2 · README 行高与标题层级修复未落地（旧计划未兑现）
- **证据**：`readme_view.dart:385` `p: body.copyWith(height: 1.5)`（计划 1.35）、`:386–387` `h1: headlineSmall / h2: titleLarge`（计划 titleLarge/titleMedium）、`:404` `blockSpacing: 12`（计划 8）。
- **影响**：长 README 正文行高 1.5 偏松（sota 01 §2 正文 1.5–1.7 合规但偏上限），标题比正文大 2 档导致密度低——与用户「空、漂浮」判词同向。
- **修复指令**：按 `UX_STABILITY_PLAN.md:257–258` 落地三处改动；`height:1.35` 仍在 WCAG 1.4.12 的 1.5 之下，需补一条 `textSpacing` 覆写测试确保不裁字（或直接取 1.5 保持合规、仅降标题档）。

### B11 · P2 · 代码查找面板行高固定 40dp（新发现，缩放破版）
- **证据**：`code_editor_field.dart:733` `static const double _kRowHeight = 40`；`:756/:758` 用固定 `SizedBox(height: _kRowHeight)` 承载行内 TextField（`:785` `fontSize: OgLFont.monoMd`=13），2.0x 下 26sp + `InputDecoration(isDense:true)` 内边距逼近/超过 40dp。
- **修复指令**：`_kRowHeight` 改为按 `MediaQuery.textScalerOf(context).scale(1)` 计算（`max(40, 20*scale)`），或去掉固定 `SizedBox(height:)` 由内容决定；`preferredSize` 同步。

---

## C. 新发现（一）：页面层裸 fontSize 全量核对

`rg -n 'fontSize\s*:' lib/` 共 **36 处**（含 1 处文档注释行 `og_l_font.dart:3`，实际代码 **35 处**）。按语义分类：

| 类别 | 处数 | 判定 |
|---|---|---|
| `OgLFont.monoSm/monoMd` 等宽令牌 | 26 | ✅ 合规（SZ-06 已闭环） |
| 用户设置驱动（`settings.fontSize` / `widget.fontSize` / `codeFontSize` / `codeStyle.fontSize`） | 5 | ✅ 合规（数据，不是设计漂移） |
| 主题令牌派生 / 兜底（`theme.dart:343`） | 1 | ✅ 合规 |
| 图标度量（`notifications_page.dart:74` `OgLIconSize.lg`） | 1 | ✅ 合规（图标尺寸不是文本字号） |
| **真·裸字号字面值** | **2** | ⚠ 见下 |

### C1 · P2 · 冷启动屏 `boot_splash.dart:58` 裸 `fontSize: 18`
- **证据**：`lib/surface/app/boot_splash.dart:58–62` `fontSize: 18, fontWeight: w600, letterSpacing: 0.5`。文件头明确「零依赖，主题尚未编译」，所以不能取 `textTheme`；但**能取 `ThemeData(brightness).textTheme.titleMedium`**（与 `theme.dart:202` 同样的纯计算、零磁盘/内核依赖）。
- **用户感受**：系统字号开 200% 时，启动屏上的「OhGithubLost」仍钉死 18px，随后被 OgLApp 顶替时标题突然变大/变小 → 冷启动首帧与首屏之间可见一次「字号跳变」，与 G-06「不闪白」的锚定目标同类问题。
- **修复指令**：改为 `style: ThemeData(brightness: brightness).textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600, letterSpacing: 0.5)`；保持零依赖（只 import material.dart）。若坚持 18 的视觉档，至少取 `titleSmall` 并接受 14sp 的缩放语义。

### C2 · P2 · `main.dart:405` 裸 `fontSize: 12`（ErrorWidget 兜底）
- **证据**：`lib/main.dart:405` `style: const TextStyle(color: Color(0xFFFFDAD6), fontSize: 12)`；`_OgLErrorBox` 在 `Directionality` 下直接 `Container`，无 Theme 可用。
- **判定**：**合理例外**。`tool/ui_audit.py` 只扫 `lib/` 的 rglob 且对 `main.dart` 无 ALLOW，但 fontSize=12 属兜底画幅的最小可读档；建议仅在注释中标注「无 Theme 上下文，const 兜底」，不强制改（若改，需自建 `MediaQuery.textScalerOf` 传入，收益低）。**不计入需要修的裸字号。**

### C3 · P1 · 等宽字体场景字号与 UI 正文体系割裂（旧审计漏报的**用户可感知**问题）
- **证据链**：
  - `theme.dart:202` 组件文字从 `ThemeData(brightness).textTheme` 派生 → 字号 11/12/14/16/22sp，走系统 TextScaler + 用户 fontScale（0.8–1.6，最终夹紧 `og_l_app.dart:113` 到 [0.85, 2.0]）。
  - `og_l_font.dart:9–14` 等宽字号是**两个独立常量** `monoSm=12 / monoMd=13`，不属于 M3 15 档 typescale 中任何一档（13 介于 12/14 之间）。它们作为 sp 值同样经过全局 TextScaler（`og_l_app.dart:113`），但**不参与 textTheme 档位体系**——注释「随 TextScaler 缩放行为不变（仍是抽象像素值）」说的正是这一点：只吃缩放系数、不吃档位语义联动。
  - 代码编辑器字号另有独立用户设置 `codeFontSize=13`（`settings.dart:135`，范围 10–22 `:168–169`），`code_editor_page.dart:377/:634`、`file_preview_page.dart:335`、`code_editor_field.dart:611/708` 用它覆盖 token；同一份代码在「代码查看器」（受 codeFontSize 控制）与「diff/日志/提交信息」（受 OgLFont.monoSm/Md 固定）里**字号不一致**。
  - 31 处 `kOglMonoFamily` 使用中，6 处连 fontSize 都不写（`login_page.dart:488/503`、`code_editor_page.dart:441`、`readme_view.dart:305`、`og_l_app.dart:207`、`gist_detail_page.dart:415`），走平台默认 14sp → 与 monoSm/monoMd 又形成第三档。
- **用户感受**：从 README 正文（bodyMedium 14）切到代码块（monoMd 13）几乎同大；切到日志（monoSm 12）小一档；切到令牌输入（`login_page.dart:488` 平台默认 14）又变大；打开代码查看器则取决于另一套 codeFontSize 设置。用户说不清「代码为什么忽大忽小」，也找不到一个统一开关——这正是「工具稳定感」的缺失点。
- **根因**：等宽体系（og_l_font.dart + codeFontSize 设置）与 UI 体系（textTheme）是**两套并行字号源**，没有语义桥接；Fix #1 只统一了控件，没有统一 mono。
- **修复指令**（按优先级，不要求一次性做完）：
  1. `lib/surface/util/og_l_font.dart`：把 `monoSm=12/monoMd=13` 改为从 M3 档位派生的常量表达（如 `monoSm = 12` 保留为 Body Small 等价、`monoMd = 14` 对齐 Body Medium），并在注释里写明「与 textTheme.bodySmall/bodyMedium 同档」；把 6 处无 fontSize 的 mono 样式显式取 `OgLFont.monoSm/Md`，消除第三档。
  2. `lib/surface/pages/settings.dart:135` 的 `codeFontSize` 默认值从 13 改为 `OgLFont.monoMd`（需 L1 不依赖 L3 的约束 → 在设置层保留数值 14 并注明与 OgLFont 对齐），让用户可调档与阅读档同源。
  3. `lib/surface/theme.dart` 增一条 `textTheme` 的 mono 语义映射（若产品希望 monospaced UI 全站联动）：当 `uiFontId==ubuntuMono` 时，`bodySmall/bodyMedium` 的 fontFamily 已是 OgLMono（`surface_bridge.dart:571–575`），但 `title/label` 刻意不覆写（注释 `:557–560`）；保持该决策，仅在文档 `docs/fonts.md` 补一张「mono 字号 ↔ M3 档位」对照表，避免后续再引入 13 这类中间值。
  4. `tool/ui_audit.py` 增加规则：`const TextStyle(fontFamily: kOglMonoFamily)` 无 fontSize 时告警（当前 ALLOW 按文件豁免，检测不到）。

---

## D. 回归专项：TextScaler 夹紧 [0.85, 2.0] 下的破版核查

### D1 · 夹紧逻辑本身：✅ 正确
- `og_l_app.dart:103–121`：在 `MaterialApp.builder` 内取 `query.textScaler.scale(1.0)`，乘 `current.fontScale`（设置层已夹到 0.8–1.6，`settings.dart:164–165/186–190/978–983`），再 `.clamp(0.85, 2.0)`，以 `TextScaler.linear(scale)` 覆写 MediaQuery——位于 WidgetsApp 自建 MediaQuery **之内**，层级正确（与旧审计 C 组结论一致）。`OgLBootFailureApp`（`:137–216`）不套该夹紧，但走系统默认 TextScaler，兜底页有 `SingleChildScrollView` + `maxWidth:640`（G-06 已修），安全。

### D2 · 破版点（按严重度）
| 级别 | 位置 | 2.0x 症状 | 归属 |
|---|---|---|---|
| P1 | `release_detail_page.dart:429` `SizedBox(width:72)` | 键名竖条化、值列空白 | B8（旧 A-M6 未修） |
| P1（条件性） | `code_editor_field.dart:733` `_kRowHeight=40` 固定 | 查找/替换行 TextField 与按钮挤在一起 | B11 |
| P2 | `readme_view.dart:579` `maxHeight:320` | 图片 alt 文字被裁 | B9（旧 A-L2 未修） |
| P2 | `action_log_page.dart:540` `maxHeight:420` | 日志结果只露上半截 | B9（旧 A-L3 未修） |
| P2 | `boot_splash.dart:58` 钉死 18 | 启动屏→首屏字号跳变 | C1 |
| ⚠ 不成立 | `desktop_window.dart:43` 标题栏 38dp | 旧 A-M7 预判「22sp×2=44>38 裁切」；当前标题样式为 `labelMedium`(12sp)，2.0x=24<38，**不裁**。窗口按钮 46×46 属触控目标问题，非排版 | C7 |

### D3 · 1.3x（130%）专项
- 用户设置滑杆范围 80%–160%（`settings_page.dart:613–619`，divisions:16），130% 是中间档；系统 1.3× × 用户 1.0 同样落在该区间。当前没有 1.3x 专属破版点：固定宽度列（72/120）在 1.3x 下中文键名约折 2 行，仍在可接受范围；真正恶化发生在 ≥1.8x。
- 建议补一条 golden/集成测试：以 `TextScaler.linear(2.0)` 渲染 release 资产页、代码查找面板、README 错误图，断言无 `RenderFlex overflow` 且 `maxHeight` 内容完整（旧 A-L4 指出全库零 a11y 测试）。

---

## E. 用户满意度：「可读但不累」核查

| 维度 | 结论 | 证据 / 说明 |
|---|---|---|
| 行高 | ⚠ 基本合格但两处偏松 | Dialog 正文 `height:1.5`（`theme.dart:268`）、SnackBar `1.4`（`:296`）、Dialog 标题 `1.3`（`:263`）、README 正文 `1.5`（`readme_view.dart:385`，旧计划要 1.35）、日志 `1.4`（`log_body.dart:174/187`）、代码 `fontHeight:1.5`（`code_editor_field.dart:613`）。M3 bodyMedium 标准行高 20/14≈1.43、sota 正文 1.5–1.7 → 均在合规带内；README 1.5 偏上限，叠加 blockSpacing 12 造成「空」。标题 1.3 在 1.1–1.25 之上，24sp×1.25=30 更贴 M3。 |
| 字重 | ✅ 克制 | 主题层只用 w500/600（`:263/:300/:343/:403/:466`），无 w700 滥用；代码高亮 keyword w600、strong w700（`code_editor_field.dart:236/253`）属语法强调，合理。 |
| 对比 | ⚠ 有设计取舍但需动态复核 | 组件文字色全部走 `scheme.onSurface/onSurfaceVariant`（`theme.dart:261/267/294/318/344/404/455`），M3 明/暗配对默认满足正文 4.5:1；hint 用 `onSurfaceVariant` 在浅色 dynamic color 下可能接近 4.5:1 边界（归 1-A 对比席复核）。`outlineVariantStrong`（`:109–111`）只管边界，不承载文字。 |
| 缩放 | ❌ 关键链路有两处旧债未修 | 夹紧本身正确（D1），但 B8/B9/B11 的固定宽/高在 2.0x 破版；等宽体系与 UI 体系割裂（C3）让「调大字号」这一用户动作在代码/日志页失效感强。 |
| 长期使用 | ⚠ 密度可调但 mono 档位混乱 | 设置提供 density（compact/standard，`theme.dart:161`）与 fontScale（80–160%）、codeFontSize（10–22）三个独立旋钮；控制力足够，但用户需要理解「界面字号 / 代码字号」的区别，且 13 这个非标准档是认知噪音（C3）。 |

**一句话**：字重与色阶已具备「工具感」，但 **Chip 11sp 太小、Dialog 标题不够层级、代码/日志字号与正文不同体系、2.0x 下三处固定尺寸破版**，是「可读但不累」尚未达标的主要原因。

---

## 本席对三问的回答

**Q1 闭环核对**：旧排版确证 11 条——已修 5（C1/C2/C3/C4/C5）、修法有问题 2（C1 派生对了档位错 → Dialog/Chip；C7 标题栏风险缓解但根因未除）、未修 4（C6/C8/C9/C10）+ 跨席登记 1（C11）。**核心结论：Fix #1「裸值→textTheme」的结构修复确实完成，但「目标档位正确性」没人核对，反而把 Chip 从 12sp 改成了 11sp、Dialog 停在 22sp。**

**Q2 回归**：textTheme 派生后，按钮 labelLarge(14)、NavBar labelMedium(12)、SnackBar/输入框/正文 bodyMedium(14)、AppBar titleLarge(22) 均落在 M3 规范档；**没有**按钮变 14 的错误（14 本就是 labelLarge 正确值）、**确实**出现 chip 变 11 的错误（B3）、导航标签 12 与 rail 默认 12 显示一致但未派生（B5）。TextScaler 夹紧逻辑正确；130% 无专属破版；200% 下有 4 处固定宽/高破版（B8/B9/B11）+ 启动屏字号跳变（C1）；旧 A-M7 的标题栏裁切**不成立**（标题已改 labelMedium 12sp）。

**Q3 新发现**：新增 **6 条**（B2 Dialog 标题档位、B3 Chip 11sp、B11 查找面板固定行高、C1 启动屏裸 18、C3 等宽字号体系割裂、B5/B6/B7 合并的派生遗漏组），其中 P1 三条（B2/B3/C3）。裸 fontSize 字面值全库仅 **2 处**（`boot_splash.dart:58`、`main.dart:405`），后者属无 Theme 兜底的合理例外；**真正需要修的裸字号只有 1 处**。

---

## 已检查清单（全覆盖声明，非抽样）

- [x] `docs/UI_AUDIT_V2_BRIEF.md` 全文（任务书/纪律/三问）
- [x] `/var/minis/skills/material-3/SKILL.md` Typography 节 + `references/typography-and-shape.md` Type Scale / Component Type Usage 表
- [x] `/var/minis/skills/sota-frontend-design/rules/01-typography-and-color.md` §1/§2/§3b/审计清单
- [x] `lib/surface/theme.dart` **全文 505 行**：14 类组件主题逐项（card/dialog/sheet/snackBar/appBar/navBar/navRail/listTile/divider/chip/segmented/input/filled+text+outlined+iconButton），所有 `tt.*` 派生点（10 处）与唯一裸兜底（`:343`）
- [x] `lib/surface/util/og_l_font.dart` 全文（两档 mono 令牌）
- [x] `lib/surface/app/og_l_app.dart` 全文 250 行（TextScaler 夹紧段 `:103–121`、`OgLBootFailureApp` 兜底样式）
- [x] `lib/surface/surface_bridge.dart:520–605`（themeFor 缓存键、`textTheme` 的 body* 字体覆写与 title/label 不覆写策略）
- [x] `rg -n 'fontSize\s*:' lib/` → **36 处逐条分类**（26 token / 5 用户配置 / 1 派生 / 1 图标度量 / 2 裸值）；`rg -n 'kOglMonoFamily' lib/` → 31 处（含 6 处无 fontSize）
- [x] `rg -n 'textTheme|fontFamily|Typography\(' lib/surface lib/main.dart`（全量字号源扫描）
- [x] `rg -n 'height:\s*1\.|fontHeight|StrutStyle|maxHeight:\s*(320|420)|SizedBox\(width: 72' lib/surface`（行高/固定尺寸扫描）
- [x] `tool/ui_audit.py` 的 fontSize 规则与 ALLOW 表（确认门禁「0 处」结论的边界：按文件豁免，检测不到 mono 体系割裂）
- [x] 旧确证文档：`docs/MD3_AUDIT.md`、`docs/MD3_AUDIT_V2.md`、`docs/audit_ui_full.md`(SZ-06)、`docs/audit_spec_b.md`(B20)、`docs/UX_STABILITY_PLAN.md`、`docs/UX_CROSS_AUDIT/1-B-shell-appbar.md`、`5-B-a11y.md`、`5-C-consistency.md` 中与排版/缩放相关的每一条
- [x] `docs/fonts.md` 字体加载与家族策略（确认自包含 OgLMono，无 CDN）
- [ ] **未做**（诚实声明）：真机/模拟器 130%/200% 渲染截图与 golden test（本席只读审计，不运行 UI）；dynamic color 下 hint 对比度的像素测量（交 1-A 对比席）；dialog 长标题在 30 个 i18n 分片下的换行实测（需运行环境）。
