# UI 深度复审 · 批 5-A · 首次使用旅程

> 文档戳：更新时间 2026-11-24 14:57:11 (Asia/Shanghai) · v15.0.0
> 审计范围：lib/surface/app/boot_splash.dart、permission_selftest.dart、client_shell.dart；lib/surface/pages/login_page.dart、onboarding_page.dart、dashboard_page.dart（首帧链路 + 登录门 + 引导 + 首页），辅证 main.dart、og_l_app.dart、async.dart、i18n 词条。
> 纪律：只读；引用可 `rg` 复现；未读任何 Flutter SDK / pub 缓存源码。

## 一、闭环核对（旧确证 · 旅程相关逐条）

| 旧条目 | 判定 | 证据 / 说明 |
|---|---|---|
| D-05 空态无动作、dashboard 半屏占位 | **已修（本席范围内）** | `OgLAsyncEmptyPane` 已支持 `subtitle`+`action` 且 maxWidth:320（async.dart:450-490）；dashboard 空态带 CTA：我的→「新建仓库」FilledButton、星标→「去搜索仓库」tonal（dashboard_page.dart:449-462），半屏 SizedBox 已删，空态外包 OgLRefreshIndicator 可下拉刷新（dashboard_page.dart:442-445）。注：其它 13 页的空态 CTA 属 3-B 席范围，本席不背书。 |
| D-14 空态文案无首次使用引导、游客/筛选混用 | **修法有问题** | 文案已改「还没有 X —— 说明」（zh/dashboard_page.json:3-4）✓。但**游客态差异化文案未做**：游客在首页「我的」tab 得到的是与未登录用户完全相同的 emptyMine（dashboard_page.dart:453-461 无 `_guest` 分支），提示他「点新建仓库」——游客没有令牌，创建必然失败，属误导性 CTA。全库游客词条只有 shell.json:43 `"guest":"游客"` 一个，未见任何界面引用。 |
| G-06 启动锚点闪白 | **已修** | boot_splash.dart:36-41 用与主题同源 `ColorScheme.fromSeed(0xFF0969DA)` 的 surface/onSurfaceVariant，明暗随 platformBrightness；图标+标题+进度环构成首帧锚点。剩余瑕疵见 N-1（跟随系统而非用户强制主题，属二阶）。 |
| F-4（旧 5-A）登录 4 步 phase 只是灰小字 | **未修** | login_page.dart:479-482 `_phase` 仍是 `bodySmall` 灰小字（425-429 旧行号即今 479-482 同构）；修复指令中的 LinearProgressIndicator(step/4) 未落地。且 `phaseDone / progressTitle / stepStage…` 词条（zh/login.json:10-30）**定义了但页面从未引用**（rg `t('login','phaseDone')` 等全 0 命中）——向导进度卡是半成品。按钮内复用 'verifying'（login_page.dart:421）与 phase 行（220）信息重复的问题也照旧。 |
| G-11 语义图标 | **已修** | client_shell.dart:441-466 四个 NavigationDestination 全部 icon+label；dashboard AppBar 三个 IconButton 均带 tooltip（dashboard_page.dart:356/367/380）；登录页引导 IconButton 有 tooltip「引导」（login_page.dart:355）。本席范围内未见裸图标。 |
| 深链缺失（F-9） | **未修** | rg 'pushNamed\|onAppLink\|initialLink\|goRouter' 全 lib 0 命中；外部 GitHub 链接仍无法落回应用内对应页。属旅程「从外部进入」口子，仍未闭合。 |

## 二、回归（v15 四批大改 × 新用户路径）

**路径实测（代码级走查）**：boot_splash（首帧有品牌+进度）→ 壳 `_checked=false` 裸转圈（client_shell.dart:134-137，**B-2 未修**：仍是 `Center(CircularProgressIndicator())`，比 splash 更空，中段退化帧仍在）→ 首次引导 3 步（PageView）→ 登录门 → Dashboard。

- 骨架屏：dashboard 首屏 loading 仍是裸 `CircularProgressIndicator`（dashboard_page.dart:440），未换骨架；但列表尾部 loadMore 处已有结构（483-490）。可接受但首屏等待无内容锚点。
- 空态 CTA 回归正常：segment 切换不重拉已有数据（dashboard_page.dart:231-237），不会"一切回白一下"✓；滚动到底 300px 自动加载 + 防重入✓（189-199）。
- 按钮 busy：登录 FilledButton spinner+文案（login_page.dart:416-423）、回车与按钮同闸（373-382）✓；onboarding 权限按钮 `_busyPermission` 单飞✓（109-112）。
- 切 tab 弹簧位移封顶 2%、[0,1] 夹紧（client_shell.dart:458-504）✓，首次旅程中切 tab 无过冲。
- **回归结论**：v15 改动未在旅程路径上引入新破坏；最卡点（B-2 裸转圈、F-4 灰小字 phase）都是**旧账未随 v15 清**，不是新引入。

## 三、新发现

### N-1（P2）· boot_splash 不读用户强制主题
boot_splash.dart:26 只随 `platformBrightness`；用户强制深色+系统浅色时首帧仍浅色、顶替帧跳深色（幅度已比旧 0xFF101418 小很多，故降级 P2）。
修复指令：main.dart 在第二次 runApp 前已能读 settings，把用户 mode 传给 `OgLBootSplash`（加 `brightness` 参数），与 og_l_app 的 `themeFor` 同源。

### N-2（P1）· 登录页 tokenHint/howTo/pasteToken 词条齐备但整块未上屏
zh/login.json:4-13 定义了「怎么拿令牌」四步 + tokenHint + pasteToken，页面零引用（见第一节 F-4 行 rg 证据）。新用户面对「个人访问令牌」输入框，**页面上没有任何一条告诉他去哪拿令牌、勾什么权限**——这是 PAT 路径最大的断点，文案已写好只是没接线。
修复指令：login_page.dart 在 tokenLabel 输入框下补一张 Card 引用 howToTitle/howToWeb/howToAvatar/howToDeveloper/howToScope 五条；TextField `hintText` 改用 `tokenHint`。

### N-3（P1）· Device Flow 有效期无倒计时、expired/denied 状态机未接 UI
GhOAuthCode 无 expiresIn 字段（lib/domain/gh/gh_oauth_types.dart:9-24）；GhOAuthStatus 有 expired/denied 枚举但 login_page.dart:185-189 的 onStatus 只写 `_oauthStatus`，UI 只有 granted/waiting 两态（login_page.dart:503-507）。用户码过期后表现为白等→报错。
修复指令：① domain 层 GhOAuthCode 增 `expiresIn`（GitHub 响应自带），卡片加 LinearProgressIndicator 倒计时；② onStatus 里 expired/denied 立即置 `_oauthError` 并停止轮询提示「重新获取」。

### N-4（P1）· 游客模式无差异化空态与「去登录」路径
见 D-14 行。游客（login_page.dart:339-345 onSkip 一点即入，无确认——旧 F-2 也未修）在首页得到「新建仓库」CTA，点击进 NewRepoPage 必然 401/报错。
修复指令：DashboardPage 增 `isGuest`（surface.domain.auth 状态即可判），游客空态文案改「游客模式只读浏览公开内容 —— 登录后可见你的仓库」+ FilledButton「去登录」（回调交壳层 `_guest=false` 回登录门）。

### N-5（P2）· 引导第 1 步留白仍偏大、无跳过
onboarding 3 步已收敛（旧 B-10 的 6 步问题已大修）✓，可手势滑页（physics 默认）也符合「或保留滑动」的倾向；但第 1 步只有 icon+标题+一句话+平台卡（onboarding_page.dart:373-400），ListView 全屏约 70% 空白；无「跳过引导」入口（NavBar 只有 上一步/1/3/下一步）。语言/外观选择器**并不在引导第 1 步**——注释宣称「语言与外观放第一步」（onboarding_page.dart:8, 369-371）但 `_welcomeStep` 实现里没有任何语言/主题控件，注释与实现不符，宣称的"先定语言再看懂文案"实际没发生。
修复指令：① `_welcomeStep` 真正补上语言/明暗选择（复用 settings 词条，i18n 已就绪）；② 或改注释如实描述；③ 第 1 步底部补一行「可随时在设置中修改」。跳过可不做（3 步成本低，可接受）。

### N-6（P2）· `_checked` 中间态仍是裸转圈（旧 B-2 未清，归入新发现账面因为是本席走查到的旅程帧）
client_shell.dart:134-137。首帧有锚点（boot_splash）、首屏前反而最空。
修复指令：改为复用 boot_splash 结构（icon+应用名+「正在恢复会话…」小字），用 `shell` 分片加 key `restoringSession`。

### N-7（P2）· 权限自检告警只进通知中心，登录门前用户未必看到
permission_selftest.dart 自检设计良好（真探针、事件码、不阻塞启动）✓；但 warn 级经通知中心呈现，新用户旅程中注意力在引导/登录页，首页 AppBar 的铃铛 Badge（dashboard_page.dart:361-372）是唯一可见入口——路径成立但弱。可接受，仅建议：权限缺失时在 Dashboard 首帧顶部叠一条可关闭的 info 卡（现有 OgLNotifier 体系可承载）。

### 走查全链路无问题项（已查 ✓）
- 启动失败页：SingleChildScrollView+maxWidth:640（og_l_app.dart:184-189）已修 B-3 ✓（但「复制日志/重试」动作仍无、仍硬编码深色 error seed——属 2-A 席范围，本席只记不判）。
- 登录失败回滚到登录前激活账号（login_page.dart:291-304）✓；保险库回读作为门（266-277 + vaultReadBackFailed 文案）✓。
- 引导权限请求：真探针、busy 防重入、失败弹窗可跳系统设置、绝不自称已授权（onboarding_page.dart:109-167）✓；探测中只禁权限页的下一步并给出「正在检测权限…」原因文案（onboarding_page.dart:335-345）✓。
- 许可条款折叠全文、权威声明分层（onboarding_page.dart:425-477）✓。
- 返回键：登录门/引导阶段不误触退出（client_shell.dart:177-190 atHome 判定）✓；maybePop 接力✓。
- 搜索空态带 query 回显（search_page.dart:1392-1403）——但 emptyAction 的按钮 `onPressed: null` 且注释自认「待核实」（search_page.dart:1395-1400）：**一个永远点不动的死 CTA 挂在搜索空态上**（P1，移交 5-B 席亦可）。游客动态空态文案「暂无新动态；关注仓库后有发布会显示在这里」（zh/search_page.json:16）对游客同样是误导（游客不能关注）。
- OAuth Web Flow 优先 + 取消回落 Device Flow（login_page.dart:99-155）✓；oauthClientMissing 空态如实（139-144）✓。

## 四、用户满意度：5 分钟内「登录并看到自己的仓库」？

**结论：能，但 PAT 路径靠用户自己懂 GitHub；OAuth 路径顺。**
- 最顺路径：安装 → 引导 3 步（约 30s，权限一步可跳）→ 「使用 GitHub 授权登录」（Web Flow 浏览器点一次 Continue）→ 首页列表。全程约 1–2 分钟，每步有反馈。✓
- PAT 路径：页面上无「怎么拿令牌」指引（N-2，词条躺在 zh/login.json 里没接线），不懂 GitHub 的新用户第一步就会卡住去 Google。
- 登录中 2–4s 只有灰小字 phase（F-4 未修），观感「没反应」但不阻塞。
- 游客不被硬拦（可跳过只读浏览）✓，但游客看到的 CTA 有误导（N-4）。

## 五、分级汇总

**P0**：无。

**P1**
1. N-2 登录页 PAT 无获取指引，howTo 词条已写好未接线（login_page.dart + zh/login.json:4-13）。
2. N-4 游客空态 CTA 误导（新建仓库必失败）、无「去登录」路径（dashboard_page.dart:449-462；旧 F-2/D-14 残留）。
3. N-3 Device Flow 无过期倒计时、expired/denied 未接 UI（gh_oauth_types.dart:9-24、login_page.dart:185-189/503-507）。
4. search_page.dart:1395-1400 搜索空态死 CTA（onPressed:null 且注释自认待裁决）。

**P2**
1. F-4/旧账：登录 phase 仍灰小字、无步骤条；phaseDone/stepStage/progressTitle 词条未使用（login_page.dart:479-482、zh/login.json:10-30）。
2. B-2/旧账：`_checked` 裸转圈帧（client_shell.dart:134-137）。
3. N-1 boot_splash 不随用户强制主题（boot_splash.dart:26）。
4. N-5 引导第 1 步注释宣称语言/外观选择但实现里没有；留白 ~70%（onboarding_page.dart:369-400）。
5. 深链缺失（F-9 延续）：外部 GitHub 链接无应用内落点。
6. N-7 权限告警仅通知中心弱可见（permission_selftest.dart + dashboard_page.dart:361）。

## 本席对三问的回答

1. **闭环**：D-05 已修（本席范围）；G-06 已修；G-11 已修；D-14 修法有问题（首用文案好，游客态未差异化且 CTA 误导）；F-4（phase 灰小字）未修；深链未修。
2. **回归**：v15 骨架/空态/busy/转场在新用户路径上未引入新破坏；最卡的两处（裸转圈中间态、phase 弱呈现）是旧账未清而非回归。
3. **新发现**：N-2（PAT 指引词条未接线，文案已就绪只差 UI）、N-4（游客误导 CTA）、N-3（Device Flow 过期无感）、N-5（引导第 1 步宣称与实现不符）、N-6、N-1、N-7、搜索死 CTA。

## 已检查清单

- [x] lib/surface/app/boot_splash.dart 全文（75 行）
- [x] lib/surface/app/permission_selftest.dart 全文（187 行）
- [x] lib/surface/app/client_shell.dart 全文（509 行：登录门、引导优先级、四页导航、返回链、切 tab 弹簧）
- [x] lib/surface/pages/login_page.dart 全文（536 行：PAT + Web Flow + Device Flow + 四步验证链 + 错误回滚）
- [x] lib/surface/pages/onboarding_page.dart 全文（517 行：3 步、权限真请求、许可折叠）
- [x] lib/surface/pages/dashboard_page.dart 全文（639 行：四态、分页、空态 CTA、游客视角）
- [x] assets/i18n/zh/login.json、onboarding.json、dashboard_page.json、shell.json、common.json、search_page.json（旅程相关词条逐一与页面引用比对）
- [x] lib/main.dart 启动段（超时 5s 权限自检）、og_l_app.dart 启动失败页
- [x] lib/domain/gh/gh_oauth_types.dart（Device Flow 类型，是否带 expiresIn）
- [x] 闭环核对依据：docs/UX_STABILITY_PLAN.md D-05/D-14、docs/UX_CROSS_AUDIT/5-A-flows.md（B-1..B-10、F-1..F-9、S-1）
- 未查项（如实声明）：Android 原生 launch_background 衔接色（仓库无 android/ 目录）；`lib/surface/pages/settings_page.dart` 内的引导回顾入口（属 5-B/5-C 范围）；六语言译文质量抽查（仅核 zh）。
