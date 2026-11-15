# MD3 Compliance Audit Report

Target: `/root/OhGithubLost`（Flutter 多平台 GitHub 客户端，v12.6.9，HEAD `40b7831`）
Date: 2026-11-15
Method: 只读源码审计（grep 证据 + 关键文件通读 + 运行 `tool/motion_audit.py` / `tool/motion_coverage_audit.py`）
Overall Score: **90/100**

> **前置约束（用户最高指令，本报告不因此扣分）**：用户明确要求「设置 / 关于 / 用户页零气泡、单层平铺、仅分类」。这三页使用 `ListTile` + `Divider` + `OgLFlatTile` / `ogLFlatRows`（`lib/surface/widgets/flat_list.dart:20-63`）而非 M3 Card / 分组容器，是**有意偏离 skill 默认建议的用户约束**，详见下方「合法项目约束」一节。

## Scores by Category

| Category | Score | Status |
|---|---|---|
| Color tokens | 9/10 | pass |
| Typography | 8/10 | pass |
| Shape | 9/10 | pass |
| Elevation | 10/10 | pass |
| Components | 9/10 | pass |
| Layout | 9/10 | pass |
| Navigation | 9/10 | pass |
| Motion | 10/10 | pass |
| Accessibility | 8/10 | pass |
| Theming | 9/10 | pass |

## 逐类证据

### 1. Color tokens — 9/10 pass
- `lib/surface/theme.dart:220-223`：`ColorScheme.fromSeed(seedColor, brightness)` 唯一生成路径；页面零字面色（`rg "Colors\." lib/surface/pages lib/surface/widgets` 仅命中 `settings_page.dart:584` 对 `kOgLSeedColors` 的遍历）。
- `lib/surface/theme.dart:97-151`：`OgLSemanticColors extends ThemeExtension`，补齐 M3 缺失的 success/warning/info 语义色，含 `copyWith`/`lerp`，明暗随主题插值。
- Tonal 配对正确：卡片 `surfaceContainerLow`+`outlineVariant`（theme.dart:243-253）、导航栏 `surfaceContainer`+`primaryContainer` indicator（theme.dart:334-360）、SnackBar `inverseSurface/onInverseSurface`（theme.dart:296-318）。
- 残余裸色值（均为可辩护场景）：`lib/surface/util/file_icons.dart:29-165` 约 60 处 `Color(0xFF…)` —— 文件类型图标的**GitHub 品牌语言色**（TS 蓝、Rust 橙等），非 UI 表面色；`lib/main.dart:369,375` `Color(0xFF4A1D1F)/0xFFFFDAD6` —— `ErrorWidget` 兜底盒，位于 `MaterialApp` 之外拿不到 Theme（error 容器色 `#4A1D1F`/`#FFDAD6` 恰是 M3 errorContainer 配方）。
- 未扣满：无 Android 12+ dynamic color（`rg dynamic` 无命中），未利用 Wallpaper 动态取色。

### 2. Typography — 8/10 pass
- 页面大量走 `textTheme.*`（`rg -c "textTheme\." lib/surface/pages` 10+ 文件，settings_page 21 处）；`lib/surface/app/og_l_app.dart:170-177` 明确用 `titleLarge` 替代裸 22/w6 并注明原因。
- 等宽字号令牌化：`lib/surface/util/og_l_font.dart:15-16` `OgLFont.monoSm=12 / monoMd=13`（对应审查项 SZ-06，26 处裸值收敛为两档）。
- 页面层裸 `fontSize` 仅剩**用户可配置项**：`file_preview_page.dart:334`、`code_editor_page.dart:377,637`、`code_editor_field.dart:611,708`（代码编辑器字号由设置驱动，不是设计令牌范畴）。
- 扣分点：`theme.dart` 组件主题里 6 处字面 `fontSize`（20/18/14/12：dialogTheme:262,272、appBarTheme:326、snackBar:311、navigationBar:353、chip:407、按钮组 425/443/461/478）——值本身即 MD3 规范值（Title-Medium 16~20、Body-Medium 14、Label-Small 12 附近），但未从 `textTheme` 派生，改主题字体缩放时不会联动。另 `lib/main.dart:375` 有裸 `fontSize: 12`（ErrorWidget 兜底，无 Theme 可用）。

### 3. Shape — 9/10 pass
- `lib/surface/util/og_l_radius.dart:27-43`：xs4/sm8/md12/lg16/xl24/pill 六档，与 MD3 shape scale（extra-small 4 → extra-large 28、full）基本对齐（xl=24 对应 large 系，pill 对应 full）。
- `theme.dart:226-241` 统一 shapeSm/Md/Lg/Xl/Pill 分发到 14 类组件；底部弹层 `verticalTopXl`（theme.dart:283-284）对应 bottom-sheet extra-large。
- 文件头注释（og_l_radius.dart:6-9）记录了此前裸值 2/6/8/12/24 并存的治理史；现状 `rg "BorderRadius\.circular\("` 全部传入 `OgLRadius.*` 常量（如 `settings_page.dart:214,2319`），无裸数字。
- 扣 1 分：MD3 弹层建议 28dp，此处 xl=24；且 `circular(value)` 工厂保留了写任意值的口子。

### 4. Elevation — 10/10 pass
- 全仓 `rg "BoxShadow"` **零命中**；`rg "shadowColor|ElevationOverlay"` 零命中。全部深度用 tonal surface 表达：卡片 elevation 0 + containerLow + 描边（theme.dart:239-253）、弹层 elevation 0（theme.dart:281）、SnackBar elevation 0（theme.dart:299）、AppBar `scrolledUnderElevation: 0`（theme.dart:324）。
- `og_l_app_bar.dart:1-30`：把 MD2 式的「滚动色阶跃」改为 surface→surfaceContainer 的连续插值，1% 步进节流——比规范更进一步。

### 5. Components — 9/10 pass
- `theme.dart:32-38` 自述并实现 **14 类组件主题**：card / dialog / bottomSheet / snackBar / appBar / navigationBar / listTile / divider / chip / segmentedButton / inputDecoration / filledButton / textButton+outlinedButton / iconButton（实际文件内逐一可数，均落 `OgLRadius`+`OgLSpace`）。
- MD2 组件零残留：`rg "RaisedButton|FlatButton\b"` 零命中；SnackBar 统一经 `OgLNotifier`（`notifier.dart:22-31`，7 份私有 `_toast` 已删除；直接 `showSnackBar` 仅剩 `error_surface.dart:572`、`download_manager_page.dart:110` 两处系统级场景）。
- 按钮 pill 形、最小尺寸 44/64（theme.dart:223-224 `minTouch/minButton`）；输入框 `surfaceContainerHighest` 填充 + primary 聚焦描边（theme.dart:437-466）。
- 扣 1 分：`filledButton/textButton/outlinedButton` 三类 `textStyle` 重复写了同一套 `fontSize:14`，可并入 `textTheme`。

### 6. Layout — 9/10 pass
- `client_shell.dart:419-426`（SZ-02）：宽屏 `Center + ConstrainedBox(maxWidth: 720)` 限宽，手机 <600 全宽；`og_l_app.dart:207-211` 兜底页 maxWidth 640。
- 8dp 体系：`og_l_space.dart:27-35` 4/8/12/16/24/32/48/64，注释明确「间距与字体解耦」的取舍（缩放时只变字号不变间距）。
- Insets/安全区：`overlays.dart:70-90` 弹层 `useSafeArea` 默认 true 并解释底部例外；键盘 inset 守卫 `og_l_app.dart:104-110`。
- 扣 1 分：600/1200 是手写宽度断点而非 Flutter 官方 `WindowSizeClass`/breakpoint 包；无 foldable hinge 处理（`rg -i hinge` 无命中）——多平台客户端可接受但未达标。

### 7. Navigation — 9/10 pass
- `client_shell.dart:434-495`：<600 `NavigationBar`（4 destination，设置升一级 U1），≥600 `NavigationRail`，≥1200 `extended` + labelType 切换——与 MD3 bar/rail/drawer-adaptive 模式一致。
- 返回链：`client_shell.dart:194-248` `PopScope(canPop:false) + onPopInvokedWithResult`（Android 预测性返回兼容 API），双击退出状态机 `OgLBackGuard`，重入闸门防连按穿层。
- 懒挂载 + `TickerMode` 停表（client_shell.dart:381-397），切 tab 状态保留（IndexedStack）。
- 扣 1 分：宽屏只有 rail，无标准/模态 NavigationDrawer 的 list-detail 双栏（master-detail）形态；drawer 分支代码自述不可达（client_shell.dart:175-179）。

### 8. Motion — 10/10 pass
- 档位→质量表唯一事实源：`motion.dart:178-330` `OgLOAnimQuality.of(level)`（0-3，含时长/位移/缩放/模糊/曲线/弹簧全参数，`isNotHeavierThan` 把「降档=降质量」钉成可测单调性）。
- 物理弹簧（client_shell.dart:483 `OgLSpring.run`，ζ 1.00→0.80→0.63 逐档回弹）契合 MD3 Expressive spring-based motion；曲线统一 ease-out 阶梯，禁 `Curves.linear`。
- CI 门禁实测通过：`tool/motion_audit.py` → 「扫描 79 文件，违规 0 处」；`tool/motion_coverage_audit.py` → 「0 处」（裸 Animated* 组件被禁，33+ 处档位消费点下限 10）。
- 页面过渡自建 `_OgLSlideFadeTransitionsBuilder`（motion.dart:395-493），`transitionWindow` 视觉窗口技巧 + RepaintBoundary + 替换 `CurvedAnimation` 修死监听泄漏。
- 静默档尊重系统：`og_l_app.dart:100` `disableAnimations: OgLMotion.disableAnimations(...)`，主题切换动画也走档位（og_l_app.dart:91-93）。

### 9. Accessibility — 8/10 pass
- 文字缩放：`og_l_app.dart:92-103` `TextScaler.linear(systemScale * userScale).clamp(0.85, 2.0)`，且注释说明必须在 `builder` 内覆盖才不被 WidgetsApp 覆写；档位关闭动效联动系统减少动效。
- 语义化：`settings_page.dart:203-215` 色板 `Semantics(button, selected, inMutuallyExclusiveGroup, label)`；全 surface `Semantics(` 11 处、`tooltip:` 67 处。
- 触控目标：theme.dart:222-224 `minTouch 44×44`；`settings_page.dart:222-227` 明确「视觉 34dp、命中区 48dp」的自查。
- 扣分：① 44dp 低于 WCAG/Material 推荐的 48dp（自述「视觉更紧凑」——是明知的妥协）；② 无系统性对比度自查工具/测试（语义色 success `#2E7D32` 在暗色 surfaceContainer 上的对比度未验证）；③ Semantics 覆盖集中于设置页色板，其它自定义绘制行未见审计记录。

### 10. Theming — 9/10 pass
- `og_l_app.dart:81-90`：明暗 × 7 种子色（theme.dart:41-50 `kOgLSeedColors`）× 密度，经 `surface.themeFor(motionLevel:)` 缓存编译，唯一编译点；`ThemeExtension` 挂语义色；`themeAnimationDuration/curve` 走档位。
- 启动失败兜底主题 `OgLBootFailureApp`（og_l_app.dart:150-160）也用 `useMaterial3 + fromSeed(kOgLErrorSeedColor)`，不裸奔。
- 扣 1 分：无 dynamic color（同 Color 项）；兜底页硬编码 `Locale('zh','CN')` 不随系统。

## 合法项目约束（单列说明，不扣分）

用户明确要求设置 / 关于 / 用户页「零气泡、单层平铺、仅分类」：

- 实现：`lib/surface/widgets/flat_list.dart:1-19` 文件头写明「全宽行 + 1px 分隔线 + 统一内边距，没有卡片、没有折叠头、没有组间圆角容器」；`ogLFlatRows`（:47-57）行间只插 `Divider(height:1)`，`kOgLFlatRowPadding` 与 `settings_group.dart:22-27` 的 `kOgLSettingsRowPadding` 同源（lg/lg-md 对称）。
- 三页验证：`rg "\bCard\(" settings_page/about_page/profile_page` **零命中**；设置页 27 处 Divider、关于页 11 处、用户页 ListTile+OgLFlatTile 平铺。
- 结论：这是对 M3「卡片分组」惯例的**知情偏离**（flat-list 文件头记录了此前卡片混用的病史）。skill 的默认建议（分组用 Card/SurfaceContainer）**不覆盖用户指令**；且实现本身（统一行高、统一 padding、outlineVariant 分隔线）仍完全在 MD3 令牌体系内，仅组件形态不同。设置页内保留的 `OgLSettingsGroup` 折叠卡片与 `OgLSettingsDangerCard`（`settings_group.dart:8-19`）属于设置页自身的分层需要，与「零气泡」约束的边界由产品定义，不在本次扣分范围。

## Critical Issues（0–3 分）

无。10 类最低 8 分。

## Warnings（4–6 分）

无。

## Passing（7–10）

- **Elevation 10**：全仓零 `BoxShadow`，纯 tonal 分层，OgLAppBar 连续插值是亮点。
- **Motion 10**：档位质量表 + 单调性测试 + 双 CI 门禁（实测 0 违规）+ 弹簧物理 + `CurvedAnimation` 监听泄漏修复，工程化程度超出常规。
- **Color 9 / Shape 9 / Components 9 / Layout 9 / Navigation 9 / Theming 9**：令牌体系（OgLSpace/OgLRadius/OgLFont + ThemeExtension）完整，页面层几乎无字面值逃逸。
- **Typography 8 / Accessibility 8**：见上，问题均为小项。

## Recommended Fixes（按影响排序，均尊重零气泡约束）

1. **`theme.dart` 组件字号改从 `textTheme` 派生**（影响 Typography/Theming）：6 处字面 `fontSize`（dialogTheme 20/14 :262,272、appBarTheme 18 :326、snackBar 14 :311、navigationBar 12 :353、chip 12 :407、按钮 14 :425/443/461）改为 `scheme`+`textTheme` 的 copyWith，主题级字体调整即可全站联动。页面零改动，不影响平铺约束。
2. **Android 12+ 接入 dynamic color**（Color/Theming 各 +1 的最大单项）：`surface.themeFor` 增加可选 `dynamicLight/DarkColorScheme` 分支（用 `dynamic_color` 包），保留 7 种子色为手动档。纯主题层改动。
3. **触控目标 44→48**（Accessibility）：theme.dart:222 `minTouch` 提到 48；`minButton` 高度同步。若坚持 44 视觉密度，至少给 icon-only 交互保证 48 命中区（参照 settings_page.dart:222 的做法全局化）。
4. **宽度断点对齐官方 WindowSizeClass**（Layout）：600/720/1200 手写值可保留行为，但建议收敛到一个 `OgLWindowWidths` 常量类并注释与 compact/medium/expanded 的映射，为后续 foldable/list-detail 留口。
5. **`OgLRadius.circular(value)` 工厂收紧**（Shape）：加 lint 或重命名 `circularByToken`，防止回潮裸值；xl=24 可评估上探 28 对齐弹层 extra-large。
6. **file_icons.dart 品牌色集中注释**（Color 收尾）：在文件头声明「这些是 GitHub 语言品牌色，非 UI 表面色，不参与 ColorScheme」，避免后续审计误判回潮。

---
*审计为只读：未修改除本文件外任何源码/文档，未执行 git 写操作。所有结论均可在上列 file:line 用 rg 复现。*
