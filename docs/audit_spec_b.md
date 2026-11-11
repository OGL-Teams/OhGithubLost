# 视角 B 审查报告：UI 动画补全 + UI 细节打磨（v12.5.2，只审不改）

审计人：视角 B。方法：静态通读 `lib/surface/app/animations.dart` / `motion.dart`、`tool/motion_audit.py`、`tool/ui_audit.py`、`tool/perf_audit.py`，逐页扫描 `lib/surface/pages/`、`lib/surface/widgets/`，并实际运行三个审计脚本复核门禁现状。
所有行号基于 main @ v12.5.2。

门禁现状实测：
- `motion_audit.py`：违规 0（75 文件，白名单 2）✅
- `ui_audit.py`：0 处令牌外字面值 ✅
- `perf_audit.py`：15 处全部"已登记例外 / 已评估" ✅

结论：**令牌与硬编码纪律执行得很好，但"动效覆盖面"存在真实缺口**（Sliver 四态、TabBarView、SnackBar 等是硬切），另有若干细节不一致。

---

## 一、动效覆盖缺口（确证，除非另标"推测"）

### B1.【P1】OgLAsyncSliver 四态全是硬切（与 AsyncView 不同权）
- 位置：`lib/surface/app/async.dart:513-548`
- 证据：`AsyncView.build` 的 loading/error/empty 三态经 `_animatedState()` → `OgLSurfaceSwitch`（`async.dart:265-282`），数据态经 `_enterData()` → `OgLReveal`（`async.dart:330-337`），四态都有过渡。但 `OgLAsyncSliver` 的 `build` 是裸 `ListenableBuilder`，四个分支直接 return sliver，**没有任何过渡**：
  ```dart
  // async.dart:517
  if (data != null && !controller.isEmptyResult) { return SliverPadding(...); }
  ...
  if (controller.isEmptyResult) { return SliverToBoxAdapter(child: OgLAsyncEmptyPane(...)); }
  ```
- 影响：pull/issue/commit 等用 Sliver 的页面（`pull_page.dart:158`、`issue_page.dart:792`、`commit_page.dart:146`）从 loading→error / loading→empty 都是"啪"地换屏，与规范"降档=降质量不是没有"相悖（档位 3 下其它页面都在过渡，这两类页面却是硬切）。
- 修法：给非数据三态（error/empty/loading 都是 `SliverToBoxAdapter` 单子）包一层 `SliverToBoxAdapter(child: OgLSurfaceSwitch(child: KeyedSubtree(key: ValueKey(state), ...)))`；数据态保留 `OgLAsyncReveal` 式淡入（Sliver 内不能套 `AnimatedSwitcher` 的 Stack，但 `SliverAnimatedSwitcher` 或对 adapter 内容包 `OgLSurfaceSwitch` 均可行，注意 `fill/Expanded` 限制不适用于 sliver）。

### B2.【P1】TabBarView 三页切换完全硬切、且与档位制度脱钩
- 位置：`lib/surface/pages/search_page.dart:661-673`（三个 tab：动态/推荐/Issues）、`lib/surface/pages/repo_page.dart:610`（`body: TabBarView(children: tabViews)`）
- 证据：搜索页 `TabBarView(controller: _tab, children: ...)` 直接使用框架默认滑动，未读任何档位参数；`OgLAnim.shellDuration/shellOffset` 只服务了 client_shell 的底部 tab（`client_shell.dart:457`），页内 tab 切换没有"档位 0 = 立即切换"的门。档位 0 / 系统减少动效时 TabBarView 仍带页面滑动动画（框架默认无 disableAnimations 适配）。
- 修法（推测程度：结构确证，具体参数需实测手感）：新建 `OgLTabBarView`（或对 `PageView` 包一层 physics/scroll 门）：档位 0 → `NeverScrollableScrollPhysics` + `onTap` 即时跳转；档位 ≥1 → 时长/曲线取 `OgLAnim.shellDuration/curve` 的自定义 `PageScrollPhysics`-style 控制器。与 `motion.dart` 的 `shellDuration` 语义对齐。

### B3.【P2】SnackBar 出现/消失是框架默认，未接档位；三处实现规格仍有分叉
- 位置：`app/notifier.dart:65-81`、`app/error_surface.dart:572-580`、`pages/download_manager_page.dart:96-108`
- 证据：三处均统一了 `floating + margin 16/12` ✅，但：
  1. `notifier.dart` 的 `_show` 没有读任何档位（SnackBar 进出场是 Flutter 内置 ~250ms，档位 0 时仍会动；Flutter 对 `disableAnimations` 只对部分组件生效，SnackBar 不在其中）。
  2. 三处规格仍不一致：`notifier.dart` 有 `isError` 配色（error 底 + onError 文字）；`error_surface.dart` 无配色；`download_manager_page.dart` 用 tertiary/errorContainer 且 `duration: const Duration(seconds: 8)`——**"同一角色控件（全局气泡）三处三样"**，通知中心 success 提示和普通 info 提示在 notifier.dart 里还共用一套视觉（`success()` 与 `info()` 都走 `_show`，无区分配色）。
- 修法：抽 `OgLNotice.show(...)` 单一出口（行为/配色/时长/动画全收敛），内部按档位门控进出场（档位 0 → 传 `AnimationStyle(duration: Duration.zero)` 或改用即时替换策略）；success 用 `tertiaryContainer`、error 用 `error`，与 download_manager 对齐。

### B4.【P2】`ogLShowDialog` 只统一了入口、没统一节奏
- 位置：`app/overlays.dart:74-82`
- 证据：
  ```dart
  Future<T?> ogLShowDialog<T>({...}) {
    return showDialog<T>(context: context, barrierDismissible: barrierDismissible, builder: builder);
  }
  ```
  与 `ogLShowSheet`（同文件 61-72，带 `sheetAnimationStyle: AnimationStyle(duration: OgLAnim.sheetDuration(context))`）不对称——dialog 没有传档位相关的 `AnimationStyle`，也没有在档位 0 时门控（`showDialog` 无 AnimationStyle 参数，需走主题或自定义 RoutePageBuilder）。36+ 处 AlertDialog 全走这个 helper（✅ 值得肯定），但 helper 本身是"半成品"。
- 修法：在 `ogLShowDialog` 里用 `theme: Theme.of(context).copyWith(dialogTheme: ...)` 或 `RoutePageBuilder` 自包 `OgLAnim.enabled` 门控的 FadeTransition；至少在文档注明依赖 `dialogTheme.animationStyle`（Flutter 3.13+ `DialogTheme.animationStyle`）接 `OgLAnim.sheetDuration/fast`。

### B5.【P1】下拉刷新 RefreshIndicator 无档位适配（12 处）
- 位置：`dashboard_page.dart:446,472`、`gists_page.dart:148`、`drafts_page.dart:213`、`profile_page.dart:232`、`repo_page.dart:796,2535`、`action_run_page.dart:570`、`search_page.dart:708,797`（共 10+ 处）
- 证据：全部是裸 `RefreshIndicator(...)`。RefreshIndicator 的 spinner 动画不随 `MediaQuery.disableAnimationsOf` 关闭，也与 `OgLAnim` 无关。
- 修法（低成本）：统一包一层 `OgLRefreshIndicator`：`displacement`/`edgeOffset` 从 `OgLSpace` 取（顺便修各处默认 displacement 不一致），档位 0 时设置 `onRefresh` 保持但 spinner 静态化（`RefreshIndicatorMode` 无直接开关，可接受方案：保持默认——此为"推测可选项"，至少文档登记豁免理由）。

### B6.【P2】设置分区页 / legal / onboarding / file_preview 四页无任何入场动画
- 位置：`pages/settings_section_page.dart:34-41`（`ListView(padding..., children: [for ... b()])` 裸 ListView）、`pages/legal_text_page.dart`、`pages/onboarding_page.dart`（有 PageView 翻页动画但页内元素无入场）、`pages/file_preview_page.dart`
- 证据：`for f in pages/*.dart; do grep -q "OgLReveal\|AsyncView\|AsyncSliver" || echo` 命中以上四页。规范"每个控件都有动画（档位 2/3 revealAll）"在这里缺位；同为次级设置页的 `settings_page.dart:495` 用了 `OgLRevealList.of(context, ...)`，第一层/第二层不一致。
- 修法：`settings_section_page.dart` 的 ListView children 改为 `OgLRevealList.of(context, <Widget>[for (...) b()])`（与 settings_page 同款，行数少、零风险）。legal/file_preview 内容型页面可豁免（文档登记）。

### B7.【P2】错误提示（OgLAsyncErrorPane / SoftErrorBar）出现是硬切
- 位置：`app/async.dart:287-296`（error 态）、`async.dart:322-327`（softError 条直接插进 Column 顶）
- 证据：softError 分支直接 `Column(children: [OgLAsyncSoftErrorBar(...), ...])`——错误条出现/消失（`dismissError`）无任何高度/淡入过渡。项目里同类场景（settings 保存失败条 `settings_page.dart:468`、通知详情 `notifications_page.dart:347`）都用了常驻 `AnimatedSize`，这里是漏网点。
- 修法：给 `OgLAsyncSoftErrorBar` 外套常驻 `AnimatedSize(duration: OgLAnim.fast, curve: OgLAnim.curve)` + 内层条件 `if (soft == null) SizedBox.shrink()`，与 settings_page:468 同一写法。

### B8.【P2】下载速率文本 AnimatedSwitcher 无档位门
- 位置：`pages/download_manager_page.dart:356`
- 证据：`AnimatedSwitcher(...)` 出现在业务页（0.1MB/s 量化 + 483 行注释解释了防抖设计，动机良好），但其 duration/curve 需确认取自 `OgLAnim.fast`（行号 356 上下文未见 `OgLAnim.` 前缀参数——**推测**：很可能传的是硬编码或默认值；motion_audit 只查 `Duration(milliseconds:` 字面量，`AnimatedSwitcher(duration: Duration.zero)` 或默认 300ms 都不违规）。**标注：半确证（默认时长不受任何档位表管）**。
- 修法：显式 `duration: OgLAnim.fast(context), switchInCurve: OgLAnim.curve(context)`。

### B9.【P2】档位 0 时 SnackBar / RefreshIndicator / TabBarView 的行为没有逐项核对（推测，需真机验证）
- 依据：全仓只有 `OgLMotion.disableAnimations`（`og_l_app.dart:102-103`）与 `OgLAnim.enabled` 两道门，被接入的组件清单 = OgLReveal / OgLSurfaceSwitch / OgLSettingsGroup(AnimatedSize) / client_shell slide / onboarding PageView / overlays sheet。SnackBar、RefreshIndicator、TabBarView、ExpansionTile（`about_page.dart:291`、`commit_page.dart:181` 等 6 处，框架自带展开动画）都不在门内。
- 结论：符合"档位 0 = 无动画"要求的部分是工具箱自家组件；**系统自带组件的动画在档位 0 下仍然在动**。修法：分类登记豁免清单（写进 QUALITY_STANDARD 或 motion.dart 文档），或对 ExpansionTile 改用 `OgLSettingsGroup` 同款 AnimatedSize 方案。

---

## 二、硬编码动效与门禁白名单漏洞

### B10.【P2】motion_audit 的 `ALLOW_LINE_HINTS` 是子串匹配，存在绕过
- 位置：`tool/motion_audit.py:44-51`
- 证据：
  ```python
  ALLOW_LINE_HINTS = ('Timer(', 'throttle', 'ttl', 'debounce', 'exitWindow', 'Cache', 'cache')
  ```
  任意一行包含 `cache`（甚至 `// cache` 相关变量名）即可豁免同行的 `Duration(milliseconds:)` / `ScaleTransition(` / `Curves.linear`。且只查 `Duration(milliseconds:`，**`Duration(seconds:` / `Duration(microseconds:` 完全不查**（实测 `download_manager_page.dart:101` 的 `Duration(seconds: 8)` 未被 motion/ui 任一审计捕获——虽然是提示时长属合理豁免，但机制上是无差别漏洞）。
- 修法：hint 匹配改为"该行时长字面量紧邻 hint"或注释标注 `// ogl: wait` 显式豁免标记；正则补 `(milliseconds|seconds|microseconds)`。

### B11.【P2】AnimatedXxx 家族多数不在 motion_audit 拦截范围
- 位置：`tool/motion_audit.py:55-60`
- 证据：PATTERNS 只拦 `ScaleTransition|AnimatedScale|BackdropFilter|ImageFilter.blur|Curves.linear|Duration(ms)`。`AnimatedContainer/AnimatedOpacity/AnimatedSlide/AnimatedPositioned/AnimatedRotation/AnimatedSize/AnimatedSwitcher/TweenAnimationBuilder`（如 `settings_group.dart:218` 的 `AnimatedRotation`、`download_manager_page.dart:356`）只要不传硬编码 ms 就能带任何默认时长/默认 easeInOut 通过。当前仓库这些用法都正确传了 `OgLAnim.*`（抽查 settings_group:218/232、notifications:347 ✅），但**门禁不锁这个行为**，回归依赖人工。
- 修法：motion_audit 增加"AnimatedXxx/TweenAnimationBuilder 调用行必须含 `OgLAnim.`"的软性检查（或至少 CI 报告非 fatal 输出清单）。

### B12.【P2】`Curves.` 在 ui_audit 的 CURVES_ALLOWED 里放行了 8 个非档位表曲线
- 位置：`tool/ui_audit.py:97-100`
- 证据：`CURVES_ALLOWED` 含 `easeInOut, easeInOutCubic, fastOutSlowIn, decelerate`——这些不在 `OgLOAnimQuality` 档位表里（表只用 easeOut 族 + linear）。任何页面用 `Curves.fastOutSlowIn` 都能静默通过，违反"曲线只能来自档位表"。
- 修法：收紧到档位表实际使用的集合 `{'easeOut','easeOutCubic','easeOutQuart','easeOutQuint','easeOutBack','linear'}`。

---

## 三、档位 0 / 减少动效下的功能完整性

### B13.【P2】notifications AnimatedSize 的冗余三元（无害但掩盖语义）
- 位置：`pages/notifications_page.dart:347-350`
- 证据：`duration: OgLAnim.enabled(context) ? OgLAnim.fast(context) : Duration.zero` —— `OgLAnim.fast` 在档位 0 时**本来**返回 `Duration.zero`（`motion.dart` case 0），且 `quality()` 已含系统减少动效判断（`animations.dart:44-46`）。三元是死代码；更重要的是它暴露了作者对 `OgLAnim.fast` 语义的不确定，其它调用点（settings_group:232 等直接用 `OgLAnim.fast`）才是正确写法。
- 修法：删三元，直接 `duration: OgLAnim.fast(context)`。

### B14.【P0→实为 P1】回归锁只测了组件、没测页面接线（见第一节第六问）
- 位置：`test/surface/ui_regression_test.dart`（全文）
- 证据：三个 group 分别直接 new `OgLFeedRow` / `OgLIssuesFilterChips` / `OgLCodeEditorToolbar`（行 25、71、139）。**没有任何测试验证页面真的在用这些组件**。实测接线现状：
  - `OgLFeedRow` 只被 `search_page.dart:697` 使用；
  - `OgLFeedRow` 的原始病灶是"动态行"，但 dashboard 动态 tab / notifications_page 的行仍是页面私有 `_NotificationTile`（`notifications_page.dart:280`）与 dashboard 自绘行——它们不走 OgLFeedRow，同样的 `crossAxisAlignment` 模式没有统一；
  - `OgLIssuesFilterChips` 只在 search_page.dart:945；issues 页自己的 chip 行（`issue_page.dart:685` 的 `Chip` + `VisualDensity.compact`）是另一套写法（Wrap 而非横向 SingleChildScrollView），行为不一致；
  - 全仓仍有 18 处页面级 `crossAxisAlignment: CrossAxisAlignment.stretch`（issue_page:744,809,868,925、settings_page:942,1042,1470,1946,2244、pull_page:126、commit_page:110、gist_detail_page:392、login_page:404、action_run_page:580、code_editor_page:613、repo_page:2544、search_page:941）。多数在 Column/AlertDialog 上下文（有界高度，安全），**但与历史病灶同构，一旦搬进 ListView 就会复发而回归锁完全不会报警**。
- 修法：(a) 每个组件增加一条"页面接线"测试：pump 真实页面（或至少 pump 含该组件的页面级 widget），断言 `find.byType(OgLFeedRow)` 在 dashboard/search 中命中；(b) 若定位是"Feed 行"就该替换 dashboard/notifications 的私有实现，否则组件名与文档声称的覆盖范围不符。

### B15.【P2】SnackBar `Duration(seconds: 8)` 未走令牌
- 位置：`pages/download_manager_page.dart:101`
- 证据：`duration: const Duration(seconds: 8)`——motion_audit 只匹配 `milliseconds` 所以放行；ui_audit 同样只查毫秒。虽是"提示驻留时长"不是动画，但与 B10 是同一机制漏洞的实例。
- 修法：抽常量 `kOglNoticeDwell = Duration(seconds: 8)` 并在审计豁免清单登记理由。

---

## 四、UI 细节打磨

### B16.【P1】图标尺寸大量裸数字，OgLIconSize 采用率低
- 位置（抽样，共约 33 处）：`about_page.dart:132,153,171`（size:18）、`action_log_page.dart:516`（12）、`download_manager_page.dart:298`（20）、`file_preview_page.dart:673`（16）、`gist_detail_page.dart:399`（18）、`issue_page.dart:839`（18）、`notifications_page.dart:320`（20）、`repo_page.dart:633,2055`（18,16）、`settings_page.dart:2302`（16）、`widgets/code_editor_field.dart:807-857`（5×18）、`widgets/settings/settings_group.dart:109,339`（18）…
- 证据：`OgLIconSize` 已有 sm16/md18/lg20/xl24 全套（`og_l_radius.dart:73-88`），但只有 5 个文件在用。18 有时对应 md、16 对应 sm，但 `size: 14`（download_manager:350、gist_detail:428）**在刻度之外**（xs=4 起，14 无对应）。
- 修法：全量替换为 `OgLIconSize.*`；`size:14` 两处升到 `OgLIconSize.sm(16)` 或在令牌表加 `OgLIconSize.xs=14`（需走令牌增补流程）。ui_audit 增加规则：`Icon(... size: 数字)` 非令牌即报。

### B17.【P2】chip 组件三套写法并存（同一角色不同实现）
- 位置：`widgets/discover_rows.dart:140`（FilterChip + 横向滚动的 OgLIssuesFilterChips）、`issue_page.dart:685`（Chip + Wrap + VisualDensity.compact）、`repo_page.dart:3555`（ChoiceChip + Row + Padding(right: sm)）
- 证据：同一"筛选/标签胶囊"角色：滚动策略（横向滚动 vs Wrap vs 直接 Row——repo_page:3555 的 Row 无滚动包裹，选项只有 4 个时尚可，加档即溢出）、密度（compact vs 默认）、间距（sm 一致 ✅）各不相同。
- 修法：统一抽 `OgLFilterChipRow`（以 discover_rows 版为基座，支持 FilterChip/ChoiceChip 双模式），issue_page / repo_page 接入。

### B18.【P2】InkWell 无 borderRadius：整卡行点击时水波纹溢出圆角（卡片容器有圆角时）
- 位置：`pages/notifications_page.dart:310`、`pages/search_page.dart:191`（Card 内 InkWell 未传 borderRadius）、`pages/repo_page.dart:622`
- 证据：`search_page.dart:216` 的内层 InkWell 传了 `borderRadius: OgLRadius.cXs`（✅ 做对了），但外层卡级 InkWell 没传——若 Card 主题有圆角（theme.dart 的 CardTheme），ripple 是矩形、视觉溢出。repo_page:622 在 Material 容器内未指定。
- 修法：卡级 InkWell 统一 `borderRadius: BorderRadius.circular(OgLRadius.md)`（或确认 Card 主题 `clipBehavior: antiAlias`，二选一全局统一）。

### B19.【P2】AppBar 角色不一致：OgLAppBar 与裸 AppBar 混用
- 位置：裸 `AppBar(` 至少 10 处：`about_page.dart:99`、`action_log_page.dart:290`、`action_run_page.dart:524`、`code_editor_page.dart:566`、`commit_page.dart:92`、`download_manager_page.dart:144`、`drafts_page.dart:207`、`gists_page.dart:134`、`gist_detail_page.dart:340`、`file_preview_page.dart:204`；而 dashboard/network/profile/repo/search 用 `OgLAppBar`（有滚动感知等能力）。
- 证据：两套 AppBar 的行为差异（大标题收缩、底部 TabBar 接法）会随页面不同而不同，同一 App 的次级页面观感割裂。
- 修法：排查 OgLAppBar 与 AppBar 的视觉/行为差异，能力对齐后统一替换（或文档登记"内容型只读页用裸 AppBar"的判据）。

### B20.【P2】notifications 通知 tile 内嵌 mono 文本 `fontSize: 12` 裸值
- 位置：`pages/notifications_page.dart:373-374`
- 证据：`style: const TextStyle(fontFamily: kOglMonoFamily, fontSize: 12)` —— ui_audit 因上下文含 `kOglMonoFamily` 放行，与其它 mono 场景（settings_page / about_page 的字号选择器）不同，这是**只读展示**而非用户可调字号，且 `fontSize: 12` 不可随系统字号缩放（const TextStyle 不接 textTheme），1.3x 大字体下不会放大。
- 修法：`style: theme.textTheme.bodySmall?.copyWith(fontFamily: kOglMonoFamily)`，随系统缩放。

### B21.【P2】大字体（1.3x）溢出防护抽查：多数行有 maxLines ✅，但 SettingsGroup subtitle 写死 maxLines:1
- 位置：`widgets/settings/settings_group.dart:206-213`
- 证据：subtitle `maxLines: 1, overflow: ellipsis` —— 1.3x 系统字号下中文副标题大概率截断丢失关键信息（分组 subtitle 常是说明文字而非装饰）。
- 修法：改 `maxLines: 2`；同类排查 `title` 行（同文件 199-204 的 title 未设 maxLines ✅ 会自动换行，保持）。

### B22.【P2】语义标签覆盖不均：仅 4 个页面有 Semantics
- 位置：有 `Semantics(` 的页面仅 `notifications_page / repo_page / search_page / settings_page`。
- 证据：issue_page 的标签 chip 行（685）、repo_page 的 ChoiceChip 筛选行（3555）、download_manager 的任务行（298）等交互行没有语义包装（FilterChip/Chip 自带语义可接受；但 dashboard 的卡片行 onTap+onLongPress 组合在 search 有、dashboard 未见——**推测**：需真机 TalkBack 复核，此处标推测）。
- 修法：为自定义可点行（非标准 Material 组件）补 `Semantics(button: true, label: ...)`，参照 notifications_page:305-310 的写法。

### B23.【P2】`Opacity(0.7+0.3t)` 硬编码透明度区间（perf_audit 已点名）
- 位置：`app/client_shell.dart:484`
- 证据：`opacity: (0.7 + 0.3 * t).clamp(0.0, 1.0)` —— 0.7/0.3 是设计值，不在任何令牌里；perf_audit 把它列为 Opacity 反模式（每帧 opacity 变化会阻止 raster cache）。档位 1 时 shellOffset=0.02、动画极短，淡入几乎不可见却仍付每帧合成的代价。
- 修法：把 0.7 起始透明度提为 `OgLOAnimQuality.shellFadeFrom`（档位 1 可设 1.0 直接省掉 Opacity 层）。

---

## 五、动画补全清单（按收益排序，≤10 项）

| # | 项 | 文件 | 关联 |
|---|---|---|---|
| 1 | OgLAsyncSliver 四态接 OgLSurfaceSwitch/OgLReveal（loading/error/empty/data） | async.dart:513-548 | B1 |
| 2 | TabBarView 档位化（OgLTabBarView：档位 0 即时切，≥1 用 shellDuration/curve） | search_page.dart:671, repo_page.dart:610 | B2 |
| 3 | SnackBar 收敛单出口 + 档位门控 + 配色统一 | notifier.dart:65 / error_surface.dart:572 / download_manager_page.dart:96 | B3 |
| 4 | ogLShowDialog 接 DialogTheme.animationStyle（档位时长） | overlays.dart:74-82 | B4 |
| 5 | SoftErrorBar 出现/消失接 AnimatedSize | async.dart:322-327 | B7 |
| 6 | settings_section_page 接 OgLRevealList | settings_section_page.dart:37-40 | B6 |
| 7 | AnimatedSwitcher（下载速率）显式 OgLAnim.fast/curve | download_manager_page.dart:356 | B8 |
| 8 | RefreshIndicator 统一包装（displacement 令牌化，登记 spinner 豁免） | 10 处 | B5 |
| 9 | ExpansionTile 登记豁免或改 AnimatedSize 方案 | about:291 等 6 处 | B9 |
| 10 | client_shell 淡入参数入档位表（shellFadeFrom） | client_shell.dart:484 | B23 |

## 六、细节打磨清单（按收益排序，≤10 项）

| # | 项 | 范围 | 关联 |
|---|---|---|---|
| 1 | 回归锁补"页面接线"测试 + dashboard/notifications 行统一到 OgLFeedRow | ui_regression_test.dart | B14 |
| 2 | Icon size 全量令牌化（~33 处，14 两处需决策） | 多文件 | B16 |
| 3 | Chip 行统一组件（FilterChipRow/ChoiceChip 双模） | issue:685 / repo:3555 / discover_rows:140 | B17 |
| 4 | 卡级 InkWell 统一 borderRadius 或 Card clipBehavior | notifications:310 / search:191 / repo:622 | B18 |
| 5 | AppBar 二合一（OgLAppBar 吸收裸 AppBar 或登记判据） | 10 处裸 AppBar | B19 |
| 6 | motion_audit：hint 子串匹配收紧 + Duration(seconds) 纳管 | tool/motion_audit.py | B10 |
| 7 | motion_audit：AnimatedXxx 行必须含 OgLAnim.（软检查） | tool/motion_audit.py | B11 |
| 8 | ui_audit：CURVES_ALLOWED 收紧到档位表集合 | tool/ui_audit.py | B12 |
| 9 | notifications mono 文本随系统字号缩放 | notifications_page.dart:373 | B20 |
| 10 | SettingsGroup subtitle maxLines 2 + 自定义可点行补 Semantics | settings_group.dart:206；B22 | B21/B22 |

---
## 证据确证度汇总
- 确证：B1-B7、B10-B21（均有行号 + 代码片段或脚本实测）。
- 推测：B8（AnimatedSwitcher 参数未逐字节核对，但默认时长不受档位表管是机制事实）、B9 的真机行为细节、B22 的 TalkBack 实际表现。
