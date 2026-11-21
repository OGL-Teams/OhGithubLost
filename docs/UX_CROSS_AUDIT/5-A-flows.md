# UX 交叉审计 · 批 5-A：关键任务流 + 启动链路

> 文档戳：2026-11-22 · 席位 批5-A（全链路体验流 · A 席）· 审计范围 lib/surface/app/boot_splash.dart、og_l_app.dart、main.dart、client_shell.dart、login_page.dart、onboarding_page.dart、search_page.dart、repo_page.dart（抽样链路）、issue_page.dart、settings_page.dart、async.dart、notifier.dart
> 原则：只读不改；引用均可 `rg` 复现；问题用「空/漂浮/粗糙/不稳定」语言描述。

## 一、启动全链路（独立章节）

### 时间线走查（逐帧）
进程启动 → `runApp(OgLBootSplash)`（main.dart:79）→ 日志落盘/平台存储/内核引导（main.dart:84–287，数百 ms~数秒）→ 第二次 `runApp(OgLApp)`（main.dart:300）→ 壳内 `_checked=false` 裸转圈（client_shell.dart:134–137）→ 登录门/引导/首页。失败路径：`OgLBootFailureApp`（main.dart:331/344，og_l_app.dart:182–240）。

### 启动链路问题

**B-1（严重）· 占位屏配色与真实主题脱节 → 顶替瞬间闪变**
- 证据：boot_splash.dart:26–27 硬编码 `Color(0xFF101418)/Color(0xFFFBFCFE)`，只跟随 `platformBrightness`；而 OgLApp 的实际背景来自 `surface.themeFor`（og_l_app.dart:113–118）+ 用户 `mode`（可为 dark/light 强制）。用户设置「深色模式」但系统为浅色时，启动首帧是白底 → 主题装载后整屏跳黑；浅色种子主题下 0xFFFBFCFE 也未必等于 `scheme.surface`。
- 用户感受：冷启动中段一次明显的闪白/闪黑，即「不稳定」的第一印象。
- 修复指令：把占位屏背景改为读取已持久化设置（settings 在 runApp 前已可加载，main.dart:84 之后即可用）——`OgLBootSplash` 增加 `background/foreground` 参数，在 main.dart:79 处传入与 `themeFor(userMode)` 相同的 surface 色；至少把 0xFF101418 对齐 theme.dart 深色 surface 的实际值。改完后占位屏 → 主界面应为无缝换树。

**B-2（严重）· `_checked` 中间态是全库最空的锚点缺失帧**
- 证据：client_shell.dart:134–137：`return const Scaffold(body: Center(child: CircularProgressIndicator()))` —— 无品牌、无文案、无骨架。占位屏好歹有 icon+标题，这一帧反而退化为纯转圈，二次 `runApp` 后用户先看到「又一个什么都没有的屏」。
- 用户感受：启动过半突然「内容消失，只剩一个圈」，空感峰值。
- 修复指令：client_shell.dart:134–137 改为复用 boot_splash 的锚定结构（同 icon + 标题 + 转圈，居中、用 `theme.colorScheme`），或至少加一行「正在恢复会话…」（`shell` 分片加 key）；禁止在启动链路出现任何「只有转圈」的帧。

**B-3（严重）· 启动失败页无滚动容器 → 长堆栈溢出**
- 证据：og_l_app.dart:204–240：`Column(mainAxisSize: min)` 内放 `SelectableText(message)`，`message` 可能是完整堆栈（main.dart:340–347 传入 `'…\n\n$stackTrace'`）。小屏 + 长堆栈 → RenderFlex overflow，失败页自身崩溃成黄条纹，是最不该出错的一页。
- 修复指令：og_l_app.dart:207 的 `Scaffold` body 改为 `SingleChildScrollView > ConstrainedBox(maxWidth: 640) > Column`，`SelectableText` 保留；并补「复制日志」「重试启动（重启进程）」两个动作按钮（失败页目前是死胡同）。

**B-4（中）· 启动失败页硬编码 zh_CN + 永久深色**
- 证据：og_l_app.dart:186 `locale: const Locale('zh','CN')`；og_l_app.dart:192–197 固定 `Brightness.dark` 且 seed 用 `kOgLErrorSeedColor`。浅色系统用户在崩溃瞬间被强切深红主题，与刚才的界面断裂。
- 修复指令：locale 跟随系统（`WidgetsBinding.instance.platformDispatcher.locale` 取首项，回退 zh_CN）；明暗跟随 `platformBrightness`，seed 仍用品牌色 `kOgLSeedColor`，错误语义只给标题/图标着色，不给整页染色。

**B-5（中）· 占位屏无时长上限 → 卡死时是无限转圈**
- 证据：main.dart:222–287 `kernel.boot` 无超时；boot_splash.dart:61–64 是不确定进度环。引导挂住（如平台存储通道阻塞）时用户面对无限转圈，没有任何出口与提示。
- 修复指令：`kernel.boot(...).timeout(const Duration(seconds: 15))`，超时走 `OgLBootFailureApp(message: '启动超时…')`；占位屏文案区补一行小字（如「正在校验引导清单」）说明在做什么，超 5s 后再叠「仍在启动，再等一会儿或重启」提示。

**B-6（中）· 占位屏只反映系统明暗，不反映用户主题计划 → 品牌锚定色不连续**
- 证据：boot_splash.dart:24–27 仅 `platformBrightness`；图标 `Icons.hub_outlined` 与 onboarding 首页 hero 图标一致（onboarding_page.dart:296–297），锚定本身做了，但颜色/背景与真实主题未对齐（见 B-1）。占位屏进度环 22px 与主界面任何 loading 尺寸不成体系。
- 修复指令：随 B-1 一并修；进度环尺寸/描边改用与 `OgLAsyncErrorPane`/页面 loading 相同规格（16 或 24 二选一统一），进度环颜色取品牌 seed 色。

**B-7（中）· 自动登录/令牌恢复阶段在 `_check` 内不可见**
- 证据：client_shell.dart:106–133：`refreshState()` + `activeAccount()` 是启动时对保险库的真实读盘，期间只有 B-2 的裸转圈；恢复成功/失败（「启动时账户读取失败（按未登录处理）」client_shell.dart:120–126）只进日志，用户不知道「为什么我明明登录过却看到登录页」。
- 修复指令：client_shell.dart:134 中间态改为带语义的恢复屏；`_check` 读失败分支（client_shell.dart:118–127）在登录页顶部补一条 info 卡：「上次会话读取失败，请重新登录（原因已记录在日志）」，把降级摊开，不做静默。

**B-8（轻）· 登录页 `_phase` 是最弱的中间态视觉**
- 证据：login_page.dart:426–429：`Text(_phase, style: bodySmall)` —— 4 步验证链（verifying → phaseVerify → phasePromote → phaseVault，login_page.dart:220/239/248/262）全部只是灰底小字，无步骤指示、无进度条；同时 FilledButton 内又显示一遍 'verifying'（login_page.dart:396–401），同一信息两处弱呈现。
- 用户感受：点登录后 2–4 秒内界面「几乎不动」，不知道进展到第几步，不稳定感。
- 修复指令：把 4 步改为 `LinearProgressIndicator`（确定值 step/4）+ 当前步骤文字（bodyMedium、`primary` 色）；按钮内文字固定为「登录中…」，不再复用 'verifying' 词条造成与 phase 行重复。

**B-9（轻）· Device Flow 授权码无有效期倒计时**
- 证据：login_page.dart:465–495：code 卡片展示 verificationUri + userCode，状态行只有 granted/waiting 两种（login_page.dart:489–492）。GitHub device code 约 15 分钟过期，过期后轮询失败只会以 `GhAuthException` 落到 `_oauthError`（login_page.dart:213–222），用户先白等。
- 修复指令：`GhOAuthCode` 若带 `expiresIn`，在卡片加 `LinearProgressIndicator` 倒计时并在临期 60s 提示「即将过期，请重新获取」；不带则至少在等待行加已等待时长。

**B-10（轻）· 首次引导无跳过，且可被手势滑到最后一页直接完成**
- 证据：onboarding_page.dart:223–239：`PageView` 未禁手势滑动（用户可滑过权限页直接到第 3 步点「开始使用」），`_finish()`（onboarding_page.dart:216–221）不校验权限页是否已看过；导航栏无「跳过」。
- 用户感受：要么被迫走满 3 步（摩擦），要么随手滑过权限说明（信息缺失）——两头粗糙。
- 修复指令：`PageView(physics: NeverScrollableScrollPhysics())` 强制走按钮翻页；或保留滑动但 `_finish` 时若未到过权限页给一次轻提示。二选一，倾向后者。

### 启动链路检查清单（已查无问题项）
- boot_splash 零依赖/零动效约束遵守（boot_splash.dart:1–22 注释与实现一致）✓
- 不做假进度（无百分比）✓
- 权限自检已移出首帧阻塞（main.dart:253–271 fire-and-forget）✓
- 构建期错误用紧凑错误卡 `_OgLErrorBox` 而非整页灰屏（main.dart:353+）✓
- 存储不可用弹窗不静默（main.dart:239–251）✓
- 返回键在登录门/引导阶段不误触退出（client_shell.dart:177–190 atHome 判定）✓
- 未查项：Android 原生 launch_background / windowBackground（仓库无 android/ 目录可验，无法核对系统 splash → Flutter 首帧的衔接色，需在发布仓核对）。

## 二、关键任务流走查：登录 → 搜索 → 进仓库 → 看 issue → 写评论

### 流程 1：登录 → 首页
**F-1（中）· 登录/切号后首页整页重建，滚动与数据全丢**
- 证据：client_shell.dart:211–214：`DashboardPage(key: ValueKey('dash-${_accountId ?? 'guest'}'))`；登录成功回调 `_check`（login_page.dart:289 `widget.onLoggedIn()` → client_shell.dart:97）setState 更新 `_accountId` → 新 key → Dashboard 全新实例，列表从头拉、滚动归零。游客→登录的转换用户感受是「页面整个闪一下重来」。
- 修复指令：key 改为不含账号即可缓存的方案：`ValueKey('dash')` + 页面内部监听 auth 变化自行刷新（已有 `auth.addListener` 模式可抄，client_shell.dart:88）；若必须重建，至少保留滚动偏移（ScrollController 位置存取 PageStorage）。

**F-2（轻）· 游客模式切换无确认，游客状态下所有登录内容呈空态**
- 证据：client_shell.dart:147–151 `onSkip: () => setState(() => _guest = true)`，一点即进，无确认；游客进「动态」tab 得到的是空态「暂无动态」（search_page.dart:437–446 未登录返回空列表），空态文案没说明「因为你是游客」。
- 修复指令：search_page.dart 空态文案区分游客/登录两态（游客：'游客模式不显示个人动态，去登录' + 「登录」按钮 action，`AsyncView.emptyAction` 已支持）。

### 流程 2：搜索
**F-3（中）· 搜索结果点击后详情返回，滚动/筛选状态依赖 IndexedStack 幸存但搜索历史丢失**
- 证据：search_page.dart:1364–1377 结果 ListView 无 PageStorage/RestorationMixin；DiscoverPage 的 `_tab`（search_page.dart:357 TabController）与分类 `_repoCategory`（search_page.dart:374）在壳层活着（IndexedStack 保状态，client_shell.dart:240–253）——tab 内切换 OK；但独立搜索页（搜索输入 `_input`）从详情返回后输入保留（controller 存活）✓，而搜索过程中的 loading 快照 `controller == null ? CircularProgressIndicator`（search_page.dart:1355–1357）在换 tab/重建时会闪现裸转圈帧。
- 修复指令：search_page.dart:1355–1357 的裸 `CircularProgressIndicator` 换成与列表同构的 3–5 行骨架占位（占位卡片高度 ≈ ListTile 56dp），消除「搜索后一瞬间整列空白」。

**F-4（轻）· 搜索空态只有图标+一句话**
- 证据：search_page.dart:1367–1368 `emptyIcon: Icons.search_off, emptyText: 'noResults'`，无「清除关键词」「换个词」动作（`AsyncView.emptyAction` 未用，async.dart:262）。
- 修复指令：加 `emptyAction: OutlinedButton('清空重搜')`。

### 流程 3：进仓库 → 看 issue
**F-5（中）· repo → issue 详情返回后无位置锚定问题，但 repo 页内部 5 个 ScrollController 各自为政**
- 证据：repo_page.dart:941/2654/2999/3153 多个 `_scroll`，无 PageStorageKey；IndexedStack 保住 tab，但从 repo 内二级页（release/file_preview）返回时若二级页中途触发过 repo 刷新（如 star 状态），滚动位置由页面自行 `jumpTo` 与否决定——审计确认：repo_page.dart 无任何滚动位置恢复代码（rg 'PageStorage|restoreOffset' 0 命中）。
- 用户感受：从长列表点进详情、返回后回到列表顶部，「上下文丢失」，不稳定。
- 修复指令：为 repo_page.dart:941 首个主列表 ScrollController 挂 `PageStorageKey('repo-main-scroll')`（用 `PageStorage.writeState` 在 dispose 前存 offset、initState 恢复）；其余 3 个按同样式跟进。

**F-6（轻）· Issue 页评论输入框沉在超长列表底部**
- 证据：issue_page.dart:877–897：评论 TextField 是 `SliverToBoxAdapter` 尾项；issue 正文 + N 条评论都在同一个 CustomScrollView。用户读完第 1 楼想评论，需要滚到列表最底；键盘弹出时依赖默认 `resizeToAvoidBottomInset`，若当前未滚动到底部，输入框不在视口，聚焦后框架未必自动滚到位。
- 用户感受：想评论却「找不到输入框在哪」，任务流断点。
- 修复指令：把评论输入提为 `Scaffold.bottomNavigationBar` 固定栏（`Padding + SafeArea` 包裹），或至少在 AppBar 加「跳到评论」按钮 `Scrollable.ensureVisible`。二选一，前者更稳。

### 流程 4：写评论
**F-7（中）· 评论发送成功后全量重载 + 无乐观插入**
- 证据：issue_page.dart:570–585：`_posting` 期间按钮转文案；成功后 `_comment.clear()` → `_commentsC().load()`（全量重新拉列表）。慢网络下用户看到自己的评论消失 1–3 秒又出现，且列表刷新回到头部渲染位置附近。
- 修复指令：`AsyncController` 若支持 append（否则给 domain 层加本地缓存 append），成功先把新评论 push 进 `controller.data` 再后台静默刷新；按钮成功后 Snackbar 已有（issue_page.dart:585–587）✓ 保留。

**F-8（轻）· 评论失败时输入内容保留 ✓ 但错误只走 SnackBar**
- 证据：issue_page.dart:589–600：失败 `OgLNotifier.warning`，正文未丢 ✓（good）；但 SnackBar 消失后无持久入口查看失败原因（只进日志）。
- 修复指令：失败时在输入框下方加一行 `error` 色小字 + 「重试」按钮（Material 3 表单错误呈现规范），SnackBar 只作即时提示。

### 流程 5：设置修改后生效反馈
**S-1（轻）· 主题/明暗切换有动画（og_l_app.dart:99–101 slow 档）✓，但语言切换等无任何确认反馈**
- 证据：settings_page.dart:1410–1414 注明「本页不自造 SnackBar」，依赖 OgLNotifier；但 rg 未发现语言/明暗切换处调用 `_notifier`（仅写操作用）。改完即时生效本身是反馈，可接受；缺的是「需要重启生效」类项的提示面。
- 修复指令：逐项核对 settings 各开关：即时生效项不加提示；需重启/重新拉数据的项（如动效档位、字体）用 `OgLNotifier.info` 一条确认。字体加载（font_loader.dart）路径建议单独验证生效延迟。

### 流程 6：深链
**F-9（中）· 全库无深链处理**
- 证据：rg 'pushNamed|onAppLink|initialLink|goRouter|RouteInformation' 全 lib 0 命中；GitHub 通知点开只能从通知列表进对应 issue（若有映射），外部浏览器打开 repo/issue URL 无法回到应用内对应页。
- 用户感受：任务流在「从外部进入」这个口子上完全断开——通知/浏览器里的链接与 App 内页面互不相认。
- 修复指令：最小可行：注册 `https://github.com/<owner>/<repo>(/(issues|pull)/\d+)?` 的 app link（Android intent-filter + 各平台等价物），入口解析后 `Navigator.push` 对应 `RepoPage`/`IssuePage`；本期可只做冷启动 initialLink，不做动态 onLink。

### 任务流检查清单（已查无问题项）
- 登录防双重提交（回车/按钮同闸，login_page.dart:73–76/377–382）✓
- 登录失败回滚到登录前激活账号（login_page.dart:290–302）✓
- 令牌保险库回读作为门（login_page.dart:266–277）✓
- IndexedStack 保 tab 状态 + 懒挂载 + 隐藏页停表（client_shell.dart:231–253）✓
- 返回链重入闸门（client_shell.dart:163–172）✓
- AsyncView/AsyncController 四态收敛、失败保留旧数据、重试按钮（async.dart:33–40/340–378）✓
- 评论权限不猜、失败如实提示（issue_page.dart:832–837 注释语义）✓
- 评论长度本地护栏（issue_page.dart:559–566）✓
- 设置折叠摘要（明暗在收起组标题可见，settings_page.dart:120–127）✓
- 未查项：多账号切换中间态（profile_page.dart 未逐行走查，仅确认 `_check` 联动）；通知点击→issue 的映射链路。

## 三、汇总分级

严重 3：B-1（占位屏/主题色闪变）、B-2（`_checked` 裸转圈帧）、B-3（失败页长文本溢出）。
中 8：B-4、B-5、B-7、F-1、F-3、F-5、F-6、F-9。
轻 8：B-6、B-8、B-9、B-10、F-2、F-4、F-7、F-8、S-1。

共 19 条可感知问题。收口建议：启动链路三条严重项与 F-9（深链）优先进入 UX_STABILITY_PLAN「锚定/反馈」两类。
