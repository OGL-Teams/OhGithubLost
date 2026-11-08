# 批7 · 视角C：契约与规范审计（主题与令牌警告子系统）

> 范围：lib/surface/theme.dart、app/font_loader.dart、font_pick.dart、og_l_app_bar.dart、motion.dart、settings.dart（外观段）、widgets/anim/anim_preload.dart、tool/ui_audit.py / motion_audit.py / perf_audit.py、test/surface/ 相关测试、AGENTS.md / docs/QUALITY_STANDARD.md / docs/USAGE.md（外观章节）。
> 只审不改。三个门禁脚本已实际运行：ui_audit 0 处、motion_audit 0 处（扫描 73 文件）、perf_audit 未登记例外 0 处。提交基线 05b683a（v12.0.0+120000）。

---

## 发现清单

### B7-C-01　P1 · 注释-实现不一致（缓存键注释）
- 位置：`lib/surface/surface_bridge.dart:479`（`themeFor` 上方字段区注释）
- 问题：注释写「主题缓存键（**三者**任一变化才重算）」，但实际缓存键是 **五元组**：`_themeCacheBrightness / _themeCacheSeed / _themeCacheDensity / _themeCacheMotion / _themeCacheUiFont`（surface_bridge.dart:479–495、506–512）。
- 后果：读者按「三」理解会漏掉 motion 与 uiFont 两个维度，正是 QUALITY_STANDARD 第 28 条（缓存键必须覆盖全部差异维度）最怕的口径漂移；后来者新增键时可能只改代码不改注释，键注释彻底失真。
- 原则：28（缓存键）、53（语义靠人读）。
- 确证：是。证据：同文件 480–484 声明 5 个缓存字段，512–519 比较 5 项。

### B7-C-02　P2 · 注释错挂（doc 注释指向错误函数）
- 位置：`lib/surface/settings.dart:917–919`
- 问题：`/// 便捷：设置全局动效档位（越界夹紧到 0–3）。` 这行 doc 注释悬挂在 `setUiFont`（切换界面字体）上方，而真正的 `setMotionLevel` 在 941 行、自身无 doc 注释。疑似此前移动函数时注释没有跟着走。
- 后果：`///` 文档生成与 IDE quick-doc 把「设置动效档位」安在字体切换函数上，误导调用者；同时 `setMotionLevel` 反而缺文档。
- 原则：53、6（命名即结构——注释同理）。
- 确证：是。证据：917 行注释后紧跟 `setUiFont` 定义（918–919），`setMotionLevel` 位于 941–945 且无注释。

### B7-C-03　P1 · 注释-实现不一致（字体回落目录）
- 位置：`lib/surface/app/font_loader.dart:129–143`
- 问题：`privateFontsDirectory` / `_privateFontsDir` 的注释声称「私有字体落盘目录（**应用支持目录**下 `fonts/`）」「**复用 app_dirs 已有的支持目录解析**」，实现却写死 `Directory.systemTemp/ogl-fonts`，且注释自己也承认「避免引入 base 层依赖（surface 不得直接 import base/disk）」——即注释描述的机制与代码行为完全相反。
- 后果：系统清理临时目录（Android 可在存储紧张时清 `cache/temp`、桌面端重启清理）后，用户私有字体文件全部丢失；`settings.customFonts` 里 filePath 仍指向已消失文件，下次启动 `ensureLoaded → bytesOf` 抛「字体文件不可读」→ 设置页报错，字体静默失效。这同时触碰第 15 条（静默降级）与第 8 条（用户数据可丢边界）。
- 原则：53、15、29。
- 确证：是。证据：139–140 行 `final Directory base = Directory.systemTemp;`；`lib/base/disk/app_dirs.dart` 存在真实支持目录解析但未被调用。

### B7-C-04　P1 · 契约缺口（内置「思源宋体」声明为内置却依赖网络下载，且回落链注释失真）
- 位置：`lib/surface/app/font_loader.dart:16–44、96–117`；`lib/surface/surface_bridge.dart:543–545`
- 问题：① `OgLBuiltinFonts.isBuiltin` 把 `noto-serif-sc` 归为内置（33–35 行），但它是三个内置 id 中唯一需要**联网下载 ~30MB OTF**（github.com 直链）才可用的；doc 注释只说「链接加载」，未向调用方暴露「离线首次选择必然失败」这一契约。② surface_bridge.dart `_uiFontFamilyOf` 注释（543–545）说「私有字体若尚未注册（启动早期），先回落系统字体」——回落机制成立（返回 `custom:<id>` 但引擎未注册该 family，Flutter 自动回落默认字体），但**没有任何日志或观测**标记这次回落，与「降级路径必须有触发条件、有观测」（第 21 条）不符。③ 下载地址是 `raw/main` 活动分支直链，无版本固定，上游重命名/移动即 404。
- 后果：离线用户选思源宋体得到一条 HTTP 错误提示（有提示算如实），但 `isBuiltin` 语义让测试与 UI 把它当离线可用项对待；上游漂移造成永久性下载失败且无人察觉。
- 原则：20、21、42。
- 确证：①③是（33–35 行 isBuiltin 含 noto-serif-sc；URL 为 `.../raw/main/...`，无 tag 固定）。②为代码事实（`_uiFontFamilyOf` 无日志调用），「无观测」定性确证。

### B7-C-05　P2 · 门禁豁免复核：action_log_page 防抖豁免 —— **仍必要，无过期**
- 位置：`tool/ui_audit.py:50`、`tool/motion_audit.py:49–57`（ALLOW_LINE_HINTS）
- 问题：无实际问题，此处为任务要求的复核记录。`action_log_page.dart:92` 的 `Duration(milliseconds: 300)`（`_debounceWindow`，输入防抖）确实不是动效时长；该行因含子串 `debounce` 已被 motion_audit 行内提示词豁免，ui_audit 则整文件登记——豁免**仍然必要且在工作**。附带确认：ui_audit 对 `action_log_page` / `search_page` 的整文件豁免使该文件内**所有**令牌规则失效（含字面色），属于宽豁免但两个文件当前扫描均无残留命中，不算缺陷。
- 后果：（若无豁免）CI 会把 300ms 打字防抖误报为动效违规。
- 原则：3（例外显式登记）。
- 确证：是。证据：motion_audit 实跑输出「违规：0 处」；`rg -n 'Duration\(milliseconds' lib/surface/pages/action_log_page.dart` 命中 92 行，行内含 `_debounceWindow`。

### B7-C-06　P2 · 门禁豁免复核：kOglMonoFamily 等宽放行 —— **仍必要，无过期**
- 位置：`tool/ui_audit.py:126–130`（fontSize 规则的上下文放行）
- 问题：无实际问题，复核记录。上批修的 `kOglMonoFamily` 放行（上下文含 `monospace` 或 `kOglMonoFamily` 则放行 fontSize 字面量）在 lib/surface/pages/ 下被 10+ 文件实际使用（repo_page / about_page / commit_page 等代码/日志等宽场景，如 repo_page.dart:1960）。等宽场景的 fontSize 属数据而非设计漂移，放行**仍然必要**。运行 ui_audit 0 处，证明放行覆盖面与实际用法吻合。
- 原则：34。
- 确证：是。证据：ui_audit.py 实跑「0 处」；rg 确认 `kOglMonoFamily` + `fontSize:` 同行/近行用法存在于多个页面。

### B7-C-07　P1 · 测试覆盖缺口（themeFor 缓存零测试）
- 位置：`lib/surface/surface_bridge.dart:479–527`；test/ 全目录无对应测试
- 问题：主题缓存的五维键、缓存命中（identical 复用）、键变化后重算，全部无测试。这是全应用「唯一一次主题编译」的最热路径，且 motion.dart 的过渡主题有界缓存（`OgLMotion.pageTransitions`，494 行文件中 363–403 行）同样只被 page_transitions_test.dart 间接覆盖（未测**同一档位两次调用 identical** 的缓存语义，而注释 7.4.1 明确承诺了该行为）。
- 后果：任何人改动键集合（如新增 uiFont 之外的维度，见 B7-C-01 的历史证据）或破坏缓存，无回归护栏；「AnimatedTheme 不把等价主题当变化」这一性能承诺可静默失效。
- 原则：49、51。
- 确证：是。证据：`rg -n 'themeFor|themeCache|identical' test/` 无命中（仅 code_editor_test 的 `ogLHighlightThemeFor` 同名巧合）。

### B7-C-08　P1 · 测试覆盖缺口（字体加载回落链零测试）
- 位置：`lib/surface/app/font_loader.dart` 全文件；test/ 无 OgLFontLoader / OgLCustomFont 测试
- 问题：`bytesOf` 的三级来源链（filePath 存在 → source http 下载 → 抛错）、`ensureLoaded` 幂等、`ensureNotoSerifSc` 落盘复用、`fromJson` 容错、`_uiFontFamilyOf` 的 system/ubuntu/custom 三分支回落，均无测试。settings_test.dart 的全字段落盘回读用例甚至未包含 `uiFontId` / `customFonts` 字段（355–401 行清单逐项核对缺失）。
- 后果：字体子系统是 v11.4 新增、含网络 IO 与文件 IO 的最脆弱外观功能；B7-C-03（临时目录）这类问题正是因为无测试才长期存活。settings 序列化新增字段漏测的模式（v10.3.0 语言键踩坑已发生过一次）正在重演。
- 原则：50、51、49（离线可跑——bytesOf 的 http 分支可用内存实现测）。
- 确证：是。证据：`rg -n 'FontLoader|OgLCustomFont|uiFont' test/` 仅命中 test/screenshots/screenshot_matrix_test.dart；settings_test.dart 355–401 行字段清单无 uiFontId/customFonts。

### B7-C-09　P2 · 测试覆盖缺口（OgLAppBar 滚动渐变与 anim_preload 零测试）
- 位置：`lib/surface/app/og_l_app_bar.dart:104–131`、`lib/surface/widgets/anim/anim_preload.dart` 全文件
- 问题：① OgLAppBar 的台阶通知条件（`_kStep=0.01`、回 0/到 1 的边界分支）与节流 Timer 合并逻辑无测试——这是 perf_audit 注释里点名的性能纪律（「不逐帧 setState」），无护栏。② anim_preload 820 行，档位策略表、幂等、额度预扣/归还、`_done` LRU 上限 64、cancelGroup，全部无测试（`rg -n 'OgLAnimPreload' test/` 无命中），而模块 doc 明说「纯数据 + 纯函数：可单测」。
- 后果：预加载额度（内存上限）与幂等是「不要过了」纪律的执行点，回归无感知；OgLAppBar 台阶逻辑改动（如改成 0.1）会悄悄引入逐帧重建。
- 原则：51、29。
- 确证：是。证据：rg 全 test/ 无 `OgLAnimPreload`、无 `OgLAppBar` 命中。

### B7-C-10　P2 · 动效档位边界：解析端已夹紧，消费端 `OgLOAnimQuality.of` 对越界值语义未测且与档位表 doc 不完全一致
- 位置：`lib/surface/app/motion.dart:449–470`（`case 0: default` 合并）、`lib/surface/settings.dart:245–259、941–945`
- 问题：档位边界由 settings 端双重夹紧（fromJson `_motionLevelOf` 夹 0–3 + `setMotionLevel` 夹紧），这条链有部分测试（settings_test.dart:432–441 测了 1e999 回落 1，但**未测负数与 >3 的夹紧**——`setMotionLevel(-5)` / `fromJson({'motionLevel': 99})`）。消费端 `OgLOAnimQuality.of(level)` 的 `default` 分支把一切越界值映射为档位 0（静默），与 motion.dart 头注释「档位只有 0–3」的假设一致，但 motion.dart 注释同时声称「`OgLOAnimQuality.of(level)` 对越界值的处理保持原样」却没有任何测试钉住这个「原样」。motion.dart 与 anim_preload 的越界策略（后者明确「越界 → off」有 `ogLAnimPreloadPolicyFor` 测试盲区相同）。
- 后果：档位边界语义（负数、4+、NaN 已测）一半有护栏一半没有；`OgLMotion.pageTransitions` 的有界缓存对越界档「现算不缓存」的行为同样未测。
- 原则：51、49。
- 确证：是。证据：settings_test.dart 中 motionLevel 相关仅 366、403、436、441 行；无 99/负数用例；`rg -n 'pageTransitions\(' test/surface/page_transitions_test.dart` 仅 21/109 行（未测 identical/越界）。

### B7-C-11　P1 · 文档失真：USAGE.md 外观章节缺「外观字体」功能（v11.4 已上线）
- 位置：`docs/USAGE.md:265、278`
- 问题：设置页外观分组已含 **界面字体**（system / Ubuntu Mono / 思源宋体 / 私有字体管理：本地文件 + 链接添加、删除，settings_page.dart:700–882 全套 UI），且设置页把它归在外观分组（`_applyUiFont` 等入口在字体分组渲染）；USAGE.md 外观行只列「明暗模式、主题色、界面密度、文字缩放、动效档位」，语言行后直接跳代码与文件，**界面字体与私有字体管理整段缺失**。
- 后果：用户手册与实际界面不符；v11.4 功能在文档层不存在，违反 AGENTS.md「记录必须与事实一致」的发布纪律（第 47 条精神）。
- 原则：47（宁缺毋假——文档漏记同样是不一致）。
- 确证：是。证据：USAGE.md 265 行原文；settings_page.dart 719–740、807、867–881 行字体管理入口存在。

### B7-C-12　P2 · 注释-实现轻微失真：anim_preload 档位表口径与 motion 档位表口径不对照
- 位置：`lib/surface/widgets/anim/anim_preload.dart:44–48、159–190`
- 问题：anim_preload 的档位语义（1=仅当前页、2=预加载最多、3=当前+子层级）与 motion.dart 的档位语义（1=最保守→3=拉满，**2 是「标准」、3 是「拉满」**）是两套独立表：档位 2 预加载额度（24 jobs/16MiB）**大于**档位 3（18 jobs/10MiB）。doc 注释解释了这是用户口径（「倒数第二级预加载最多」），但两表共用同一设置键 `motionLevel`，motion.dart 头部档位表（「1<2<3 逐级更重」）读者会自然推断预加载也单调，实际不单调。注释自身一致，但**跨文件契约无任何一处写明「预加载额度不随档位单调」**，仅靠 anim_preload 单文件注释。
- 后果：调档位语义时极易只改一张表（这正是「唯一事实来源」纪律要防的）；「isNotHeavierThan」单测只覆盖 motion 表，预加载表无单调性测试也无豁免声明。
- 原则：53、27（假设写进注释）。
- 确证：是（数据层面确证：level2 maxJobs=24 > level3 18；motion.dart 头表声称逐级更重）。定性为「跨文件契约缺失」而非缺陷。

### B7-C-13　核对通过项（无缺陷，记录核验结论）
- **AGENTS.md 版本规模**：AGENTS.md:3 标 v12.0.0 LTS；pubspec.yaml:21 `version: 12.0.0+120000`；lib/main.dart:46 `kOgLAppVersion = '12.0.0'`。三者一致，批5修复仍准确。✅
- **theme.dart 注释**：头注「显式定义十四类组件」——实际数一遍 card/dialog/bottomSheet/snackBar/appBar/navigationBar/listTile/divider/chip/inputDecoration/filled/text/outlined/icon 恰 14 类；「令牌唯二来源」（OgLRadius/OgLSpace）与门禁 SPACE_SCALE/RADIUS_SCALE 一致。✅
- **motion.dart 动效四档表**：头注释（0 静默/1 最保守/2 标准/3 拉满、1<2<3 逐级更重、缩放只出现在更高档）与 `OgLOAnimQuality.of` 四个 case 的数据逐项一致（revealAll false→true→true；revealScaleFrom 1/1/0.985；blur 0/0/0/6）；`isNotHeavierThan` 覆盖 17 个字段并被 animations_test.dart:109–110 逐档钉住。档位 0 用 `Curves.linear` 例外已在 motion_audit 注释与白名单中写明。✅
- **OgLAppBar 注释-实现**：PrimaryScrollController/自建控制器回退、1% 台阶、Timer 帧末合并——与代码一致；theme.dart appBarTheme（surface 基线 + scrolledUnderElevation 0）与 og_l_app_bar 的 surface→surfaceContainer 插值口径吻合。✅
- **settings.dart 容错纪律**：fromJson 各字段回落默认、Infinity/NaN 防护有注释有测试（settings_test.dart:432–441）。✅

---

## 覆盖文件清单

| 文件 | 完整读 | 结论入口 |
| --- | --- | --- |
| lib/surface/theme.dart (429L) | ✅ | B7-C-13 |
| lib/surface/app/font_loader.dart (145L) | ✅ | B7-C-03、04、08 |
| lib/surface/app/font_pick.dart (67L) | ✅ | 无缺陷（与 font_loader 分工注释相符） |
| lib/surface/app/og_l_app_bar.dart (151L) | ✅ | B7-C-09、13 |
| lib/surface/app/motion.dart (494L) | ✅ | B7-C-10、13 |
| lib/surface/settings.dart (1058L，外观段逐行) | ✅ | B7-C-02、10、13 |
| lib/surface/surface_bridge.dart（themeFor 段） | ✅ | B7-C-01、04 |
| lib/surface/widgets/anim/anim_preload.dart (820L) | ✅ | B7-C-09、12 |
| lib/surface/app/og_l_app.dart（挂点核对） | 部分（1–120 行 + 挂点） | B7-C-13 |
| lib/surface/pages/settings_page.dart（字体段 700–900） | 部分 | B7-C-04、11 |
| tool/ui_audit.py (194L) / motion_audit.py (108L) / perf_audit.py (195L) | ✅ + 实跑 | B7-C-05、06 |
| test/surface/animations_test.dart、page_transitions_test.dart、settings_test.dart | ✅ | B7-C-07/08/09/10 |
| AGENTS.md、docs/QUALITY_STANDARD.md、docs/USAGE.md（外观章节）、docs/fonts.md | 关键段 | B7-C-11、13 |

## 整体规范符合度评价

**良好（B+ 档）。** 三个静态门禁实跑全绿，说明令牌纪律（第 34 条）、动效档位纪律（第 33 条）与性能反模式门禁执行扎实；motion.dart 四档表、theme.dart 组件级主题、anim_preload 的「有界 + 幂等 + 可取消」三纪律，注释与实现的一致性在同类代码里属上乘，AGENTS 版本三处真相一致。主要短板集中在两处：**字体子系统**——落盘目录名实不符（B7-C-03，唯一可能造成用户数据丢失的一条）、内置字体依赖活动分支直链（B7-C-04）、整个子系统零测试（B7-C-08）；**缓存与边界语义**——themeFor 键注释失真（B7-C-01）与其零测试（B7-C-07）互为因果。P0 为零，P1 五条（01/03/04/07/08），全部可在一个迭代内收口；建议优先级：03 → 07+08（同一组测试文件可一并覆盖 10）→ 01 → 04 → 11。
