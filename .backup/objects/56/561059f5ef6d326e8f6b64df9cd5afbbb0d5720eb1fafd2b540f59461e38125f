# 更新日志

本项目各版本的变更记录，新版本在前。

## v6.0.1（2026-10-05 · 正式版）

> **主题**：内置加速通道换新代理 + 新增**实验性** Web（wasm）构建管线。
> 加速通道面向所有正式平台；Web 目标为实验性补充，**编译失败不影响发布**。

### 新增 · Added
- **实验性 Web（wasm）构建管线**（`.github/workflows/web.yml` · `tool/web_build.py`）：
  独立工作流，`flutter build web --release --wasm`，产物**发布到仓库 `app/`**。
  - **浏览器 API 守卫（动态注入）**：把 `web_api_guard.js` 写进 `web/` 并把
    `<script>` **注入** `web/index.html`（幂等），在 Flutter 引擎加载**之前**
    逐项检查 `WebAssembly` / `instantiateStreaming` / `fetch` / `ReadableStream` /
    `TextDecoder` / `crypto.getRandomValues` / `indexedDB` / `atob·btoa` / `URL` /
    `Worker` / `performance.now` 与跨源隔离（`SharedArrayBuffer` + COOP/COEP），
    **缺任何一项即抛错并给出可读原因**，绝不静默白屏。
  - **编译期门禁**：`--preflight` 预检已知阻塞 wasm 的依赖（见下"已知限制"），
    `--verify` 核对产物（`index.html` / `flutter_bootstrap.js` / `main.dart.js` /
    `.wasm` / 渲染引擎 / 守卫已注入），缺一即抛错。
  - **`app/` 先清空后重建**：`--publish` 内部 `rmtree` + 重建，每次构建**只保留
    最新**一套 web 文件，旧 wasm / canvaskit 缓存不会残留；提交走 GitHub REST
    （Git Data API），与本机 git 不可用的现状兼容。
  - **与发布完全解耦**：独立工作流 + `continue-on-error`，**不被 `build.yml` 的
    `release` 任务依赖**，web 失败不阻塞也不污染任何正式发布结果（CI 实证）。

### 变更 · Changed
- **内置加速通道改走 `gh.felicity.ac.cn` 转发完整 GitHub 链接**
  （`lib/surface/util/accel.dart`）：
  - 优先前缀由 `https://gh.344977.xyz/` 改为
    **`https://gh.felicity.ac.cn/https://github.com/`**，即拼出
    `https://gh.felicity.ac.cn/https://github.com/…` 这种**转发完整链接**的形式；
  - `https://gh.felicity.ac.cn/` 保留为降级备选，仍按序探测、**静默降级**，
    最后永远保留直连兜底；
  - 对用户仍是**一个**不可删改的「内置通道」；自定义通道与协议同意机制不变。
  - 断言同步更新（`test/surface/path_rules_test.dart`）。

### 变更 · Changed（文档）
- 更新日志站（`changed/`）**全部** Release 下载链接由旧式镜像前缀改为
  `https://gh.felicity.ac.cn/https://github.com/…` 形式；生成器
  `changed/generate_posts.py` 的 `ACCEL_HOST` 同步更新，保证后续重新生成一致。

### 已知限制 · Known limits
- **Web（wasm）当前编译不通过（实验性，预期内）**：`saf_util` / `saf_stream`
  依赖 `jni` 与 `ffi`，而 wasm **不支持 `dart:ffi`**，dart2wasm 因此报
  `Dart library 'dart:ffi' is not available on this platform`（CI 实证）。
  `--preflight` 会在编译前点名这些依赖。**此为已知且被容忍的状态**：该腿失败
  不影响任何正式平台构建与发布；要真正产出 wasm，需为 SAF / 文件系统能力补
  web 实现。
- 加速通道仅作用于 **Release 附件**；仓库文件 / Gist 等下载不经过它。

## v6.0.0（2026-10-05 · 正式版）

> **合并说明**：本版包含 **v5.9.0**（未发布成功 · 构建失败）的全部功能，以及 v5.7.0 / v5.8.0 跳号期间准备的跨平台硬化内容。

- **README 链接可用了**：相对链接（`LICENSE`、`docs/x.md`、`#锚点`、裸域名）先按仓库基址解析成绝对地址再交给系统浏览器；解析不了会明确提示，不再"点了没反应"。
- **README 图片可以显示了**：图片经 **GitHub Contents API** 取字节后用 `Image.memory` 渲染，不经过 `raw.githubusercontent.com`，避开 DNS 污染；`<img src=…>` 也会渲染成图；单次上限 40 张，超出或失败退化为 alt 文本（不静默丢图）。
- **glibc ≥ 2.35**（对应 Ubuntu 22.04 一代及以上；Linux 产物在 `ubuntu-22.04` / `ubuntu-24.04-arm` 宿主上直接构建以锁定该下限）

### 构建与审计 · Build & audit
- **CI 新增 AI 审计**（`ci.yml` → `ai_audit` job）：用 Agnes（`agnes-2.5-flash` 高智能）对架构 / 安全 / i18n / 性能 / 变更记录做**补正则盲区**的复核；密钥走 Secret `AGNES_API_KEY`，缺失则跳过并显式标注（不锁死 CI）。
- **每小时质量审计**（`.github/workflows/quality-audit-hourly.yml`）：cron 每小时触发，`tool/ai_quality_audit.py` **逐个文件**审查 `lib/**/*.dart`（5 rpm 限速，防撞 API 上限），结果 TXT 发布到**独立 tag** `CI-cat-<北京时间>-cst8`。
- **提示词防假阳性**：判定纪律「宁可漏报、不可误报」——只报**可指行号、可证实**的问题，禁止臆测「可能竞态/可能泄漏」，无确凿问题一律 PASS。
- **rpm 压缩级别**：保持 `w9.xzdio`（xz 级别上限 9，`w10` 非法）。
- 发布说明从 `release_notes/v6.0.0.md` 生成（中英对照）。
- **Linux 构建不再套容器**：x64 腿改到 `ubuntu-22.04`、arm64 腿 `ubuntu-24.04-arm`，**宿主直编**。20.04 容器已 EOL、archive 源超时，且容器失败后的回退等于把全量编译跑两遍——曾把 Linux 腿挂死 5h50m；同时给 `build` job 加 `timeout-minutes: 45` 兜底。glibc 下限随之由 2.31 抬到 **2.35**。

## v5.9.0（未发布成功 · 构建失败，内容并入 v6.0.0 / never shipped）

**主题**：**跨平台差异面硬化** —— 直面 Windows / Linux / Android 三系差异，
把"能跑"变成"在真实发行版上也能跑"。

### 新增 · Added
- **Windows 长路径三层处理**：`\\?\` 前缀绕过 MAX_PATH → 仍失败则把超长部分
  收纳为 `TooLongRoad_<8位随机编号>.zip`（落在最近可用父目录，包内保留完整相对路径）
  → 根目录 `.ogl_toolong.json` 索引，`read` / `exists` / `delete` / `list` 全部贯通。
- **桌面原生壳注入**（`tool/inject_desktop_shell.py`）：Windows 出 **256 单帧 ICO**
  并写入 `Runner.rc` 版本信息，Linux 出 **2048 PNG** 母版；两者都把**原生窗口标题**
  写为 `OhGithubLost`（任务栏 / Alt-Tab / 任务管理器读的是它）。
- **零依赖图标光栅化**（`tool/desktop_icon.py`）：直接解析图标几何源 SVG，
  扫描线填充 + 抗锯齿 + 自编码 PNG/ICO，CI 无需 cairo / Pillow。

### 修复 · Fixed
- **Windows 本地缓存完全写不进去**：缓存 blob 文件名原样拼接 `scope|path`，
  而 `|` 在 Windows 是**非法文件名字符** → 一律 `FileSystemException`。
  现改为 `sha256(编码键)`，`purgeOrphans` 同步（否则会误删有效缓存）。

### 已知限制 · Known limits
- **glibc ≥ 2.31**（对应 Ubuntu 20.04 一代及以上；Linux 产物在 `ubuntu:20.04` 容器内构建以锁定该下限）
- Windows 需 **10 1809+**；7 / 8.1 无法运行。
- 桌面**无 32 位**产物（上游 Flutter 不提供 ia32 引擎）。


## v5.8.0（未发布 · 跳过 / skipped）

> 未发布。5.7 → 5.8 之间没有独立变更面，直接进入 **v5.9.0**。
> *Not released. No independent scope between 5.7 and 5.8; the line moved straight to v5.9.0.*

---

## v5.7.0（未发布 · 跳过 / skipped）

> 未发布。版本号被保留但未投入使用（当时正在做跨平台差异面硬化，准备合并成一个大版本）。
> *Not released. The number was reserved but never used — the cross-platform hardening was being prepared as one bigger release.*

---

## v5.6.0（2026-10-04 · 正式版）
**主题**：**存储三档（公共目录 → SAF → 内部）** + 网络独立成页 + 引导页重做（语言/外观前置）+ 加速通道内置优先链。
*Three-tier storage (public dir → SAF → internal), network settings as its own page, reworked onboarding (language & appearance first), and a built-in acceleration priority chain.*

### 新增 · Added（存储 · Storage）
- **三档落盘，前两档算「过」· Three storage tiers**
  | 档 | 条件 | 落点 | 用户可见 | 自检 |
  |---|---|---|---|---|
  | ① 公共目录 | 有「所有文件访问」 | `/storage/emulated/0/ogl` | ✅ | **过** |
  | ② SAF 文件夹 | 用户授权了文件夹 | 私有目录 → **导出粘贴**到该文件夹 | ✅ | **过** |
  | ③ 应用内部 | 两者都没有 | 应用私有目录 | ❌ | **不过**（不阻断） |
- **SAF 落地方式**：下载**照旧**写私有目录（分片 / 断点 / 后台通知零改动），
  完成后用 `SafStream.pasteLocalFile` **粘贴**到用户选的文件夹。新增依赖
  `saf_util` / `saf_stream`（仅 Android 生效）。
- **设置 → 存储位置**：如实显示当前档位与实际路径，并提供
  「选择文件夹（SAF）」「取消文件夹授权」「打开『所有文件访问』设置」。
- 新增事件码 `OGL-DL-301`（已导出到所选文件夹）。

### 变更 · Changed（图标 / 命名 / 平台 / 产物 · Icon, naming, platforms, artifacts）
- **应用图标 = 矢量、背景透明**：几何事实来源 `assets/icon/ogl_icon.svg`；
  Android 用**矢量 XML**（VectorDrawable 前景 + 自适应图标，透明背景）。
- **应用名**：Android = **OGL**；其余平台 = **OhGithubLost**。
- **平台调整**：**弃用 macOS 与 iOS**（最后支持版本 **v5.3.0**）；
  Windows / Linux 补齐 **arm64**（由 best-effort 转为正式腿），
  桌面端无 32 位目标（上游 Flutter 不提供），32 位仅 Android（`armeabi-v7a`）。
- **Release 只提供压缩包**：`.zip` 与 `.7z` 双份、**极限压缩**（`zip -9` / `7z -mx=9`）。

### 变更 · Changed（引导 / 设置 · Onboarding & settings）
- **引导页新增第 1 步「语言与外观」**：语言与明暗模式**在引导里首次设定**、
  即时生效；引导**不含登录**（符合商业规范：登录不属于引导流程）。
- **登录页左上角**新增入口，可随时**重新触发引导**（回顾模式，不改动引导标志）。
- 网络设置**独立成页**（DNS / 下载并发 / 加速通道），不再是一个可折叠分组。
- 开源许可**合并为一条**，打开时弹窗（本项目 + 第三方依赖）。
- 加速通道：内置通道 = `gh.344977.xyz`（**优先**）+ `gh.felicity.ac.cn`（**降级**），
  用户不可调整；下载时逐个探测，**静默降级**，最后永远保留直连兜底。

### 变更 · Changed
- **内置加速通道改为「优先 + 降级」固定链（用户不可调整）**
  内置通道 = `gh.344977.xyz`（**优先**）+ `gh.felicity.ac.cn`（**降级备选**）；
  界面上仍是**一个**「内置通道」（不出地址、不可删、不可改）。
- **静默降级 · Silent fallback**
  下载 Release 附件时按优先级**逐个探测**：命中第一个可用地址即使用；
  前者不可用就自动用下一个；**最后永远保留直连兜底**。全程不弹窗、不打扰用户。
- **网络设置独立成页**
  DNS / 下载并发 / 加速通道不再是一个"可折叠分组"，改为设置页里的
  **单独页面**（`pages/network_page.dart`）。
- **许可入口合并**
  本项目许可与第三方依赖合并为**一条**，打开时**弹窗**展示（不再平铺在设置列表里）。
- 修正内置通道名称的文案分片（应取 `common` 分片），此前可能显示成键名。
- 加速通道**总开关默认保持关闭**（第三方信任边界，需用户显式开启）。

### 修复 · Fixed（权限网关 · 存储位置）
- **"假装已授权"**：存储探针以前探的是**已回退后的目录**，于是退回应用私有
  目录也会被判成"已取得存储权限"——用户在文件管理器里其实**什么都看不到**。
  现在探针改为**探测"用户可见性"**：`Android/data/...`（Android 11+ 起被系统
  隐藏）与内部存储**一律不算可见**，如实报告 `needsUserAction`。
- **"给了所有文件权限还是用内部存储"**：应用根目录结果被**进程级缓存**，
  授权后不会重新解析。现在探针前会 `invalidate()` 并**重新解析**，授权后
  立刻切到系统可见的 `ogl` 目录。
- **按 Android 版本如实说明**：未就绪时，权限说明会追加"为什么"（Android 11+
  需要「所有文件访问」；部分 ROM 只支持逐个授权文件夹）与"现在落在哪"
  （实际路径），不再让用户猜。
- 新增落盘位置分级 `OgLStorageTier`（公共 / 应用外部 / 内部 / 桌面）与
  `isUserVisible()`、`location()`、`invalidate()`。

### 测试 · Tests
- 新增断言：内置优先链（344977 优先 / felicity 降级）、加速前缀链（内置多前缀、
  自定义单前缀）、候选地址（按优先级 + 直连垫底 + 不二次加前缀）；
  以及**落盘位置分级**（`Android/data` / 内部存储一律**不算**"用户可见"）。

## v5.5.0（内部开发版 · 未单独发布 / internal）

**主题 · Theme** — 权限网关与 SAF 三档存储的开发迭代：**未单独发版**，内容全部并入 **v5.6.0**。
*Development iteration for the permission gateway and the three-tier SAF storage. Never released on its own; all of it shipped in v5.6.0.*

### 新增 · Added
- **存储三档 · Three storage tiers**
  公共目录 / SAF 目录 / 应用内部，三级方案由**探针**实测后裁决；设置页新增「存储位置」区块。
  *Public directory / SAF directory / app-internal, decided by a real write probe; a Storage section was added to Settings.*
- **SAF 目录直存 · Paste straight into a SAF tree**
  用户授权目录后可把本地文件**粘贴进 SAF 目录**（`pasteLocalFile`），下载完成自动导出——不必重写下载引擎。
  *After the user grants a directory, local files can be pasted into the SAF tree and downloads are exported automatically.*

### 修复 · Fixed
- **权限探针探错对象 · Probe checked the wrong target**
  原先探的是"已回退后的目录"（内部存储永远可写 → 永远显示"已授权"）；改为探测**用户可见性**。
  *The probe used to test the fallback directory (app-internal is always writable, so it always said "granted"); it now tests user visibility.*
- **根目录结果被进程级缓存 · Root resolution cached process-wide**
  授权成功后不重新解析，导致权限状态"永久过期"；现在授权后会作废并重新解析。
  *After a grant the root was not re-resolved, leaving a permanently stale permission state; it is now invalidated and re-resolved.*

---

## v5.4.0（内部开发版 · 未单独发布 / internal）

**主题 · Theme** — 网络与下载通道改造：**未单独发版**，内容并入 **v5.6.0**。
*Network and download-channel rework. Never released on its own; shipped in v5.6.0.*

### 新增 · Added
- **内置加速通道（优先 + 降级）· Built-in accelerator with fallback**
  `gh.344977.xyz` 优先、`gh.felicity.ac.cn` 降级；**内置通道用户不可调整**，失败时静默降级，不打断浏览。
  *`gh.344977.xyz` first, `gh.felicity.ac.cn` as fallback. Built-in channels are not user-editable and degrade silently on failure.*
- **网络模式独立成页 · Network as its own page**
  网络设置从设置根级拆出，成为独立页面。
  *Network settings were split out of the settings root into a dedicated page.*

### 变更 · Changed
- **加速通道默认关闭 · Accelerator off by default**
  默认走直连，用户显式开启加速才启用通道。
  *Direct connection by default; the accelerator is opt-in.*
- **许可条目合并 · Licences merged**
  两条许可合并为一条，并改为弹窗展示。
  *Two licence entries were merged into one shown in a dialog.*

---

## v5.3.0（2026-10-04 · 正式版）
**主题**：**动效全面升级**（自然减速 + 物理弹簧 + 全覆盖）与**仓库统计曲线重构**。
*Motion overhaul (natural deceleration + physics springs + full coverage) and rebuilt repository stat charts.*
### 变更 · Changed（大体积动画：更快 / 更灵动 · Large-surface motion）
- **全页过渡改为「视觉窗口」压缩 · Page transitions compressed via a visual window**
  页面级过渡**不改路由时长**（保留系统返回手势语义），而是把「实际运动」压进
  路线时间线的前一段（档位 1/2/3 = 42% / 55% / 70%），落位后即保持——观感明显更快。
- **全局提速 · Faster across the board**
  快/中/慢三档整体下调（如标准档 150/220/300 → 120/170/230 ms）；新增的
  「大体积动画」时长同样逐档增加但都 ≤ 200ms：外壳切换 110/150/190ms、
  整页状态切换 110/140/180ms、引导翻页 160/200/260ms、底部弹层 130/160/200ms
  （均快于 Flutter 底部弹层默认 250ms）。
- **新增组件与入口 · New component and entry point**
  `OgLSurfaceSwitch`：大体积内容切换（快速淡入 + 极轻缩放，低档只淡入）；
  `ogLShowSheet<T>()`：底部弹层统一定速入口（`overlays.dart`），
  5 处 `showModalBottomSheet` 已改用它。
- **缩放分级 · Scale tiering**
  最保守档位 1 **不做任何缩放**；档位 2/3 才给 ≤1% 的极轻缩放；模糊仍只在拉满档。
- **曲线全部改为「自然减速」· Natural deceleration everywhere**
  去掉所有匀速（`Curves.linear`）：三档统一走 **ease-out 阶梯**
  （`easeOut` → `easeOutCubic` → `easeOutQuart`，大体积再各进一档到
  `easeOutQuint`）——起手快、落位柔，符合直觉而不再"机械 / 死板"；
  切 tab 的整页位移也从"控制器直驱匀速"改为走档位曲线（曲线只改落位节奏，
  时长不变，因此**对操作的影响不变**）。新增门禁：`tool/motion_audit.py`
  禁止白名单外出现 `Curves.linear`。
- **物理动效（基础版）· Physics-based motion (basic)**
  加入厂商动效的"基础件"，全部按档位分级：
  - **物理弹簧 + 可中断**：新增 `OgLSpring`（`SpringSimulation` 驱动），切 tab
    改用弹簧——由**刚度 / 阻尼**而非固定时长决定运动，天然**可打断 / 可续跑**
    （"跟手"）；阻尼比逐档递减（档位 1 临界阻尼不振荡，档位 2/3 轻微回弹）。
  - **轻微回弹（"Q弹"）**：新增 `settleCurve`，**只作用在位移 / 缩放**上
    （拉满档用 `easeOutBack`）；透明度插值保持单调，绝不回弹。
  - **共享元素（容器变换）**：新增 `OgLSharedTitle`，把仓库列表的**名称**与
    仓库详情的**标题**连成一次 `Hero` 飞行（"空间连续感"）；标准档及以上启用。
- **全覆盖动效 + 覆盖面分档 · Full coverage & coverage tiers**
  - 分档从"效果强弱"扩展为**「覆盖 × 丰富度」**：新增 `revealAll`（覆盖面）。
    - 档位 1：淡入，**只覆盖主要区域 + 前 3 项**（最保守）；
    - **档位 2（倒数第二档）：每个控件都动，但用最简动画——纯淡入**
      （`revealOffset = 0`、不缩放），只保证"每个控件都有动画"；
    - 档位 3：全覆盖，并叠加位移 / 缩放 / 回弹 / 模糊（拉满）。
  - `OgLAnim.staggerOf`：超出错峰范围的项在**全覆盖档位**仍参与动画
    （只是不再错峰），不再是"直接静态渲染"。
  - **`AsyncView` 数据态加入场**：加载 → 数据不再"硬切"，整片内容淡入
    （用单子层的 `OgLReveal`，放进 `Expanded` 也不会无界）。
  - **静态页 / 表单页补齐入场**：`settings` / `about` / `login` / 四个 `new_*`
    / `code_editor` / `issue` / `pull` / `commit` / `release_detail` 的页面内容
    统一包一层入场动画；Gist 列表逐项入场。
  - 新增 `OgLRevealList.of(context, children)`：把一串子控件**逐个**包上入场
    动画（自动错峰），用于整栏 / 整页覆盖。
### 修复 · Fixed（读图会被误导的三处）

- **纵轴不再按极值拉伸 · No more per-series stretching**
  旧实现取各自 `min..max` 满高绘制：3→4 也能画成"垂直暴涨"，且星标图与提交图
  各自满高、**量纲不同却看起来同量级**。现在**从 0 起**、上限取整齐刻度
  （1 / 2 / 2.5 / 5 × 10ⁿ）、5 条刻度线并标注数值。
- **补上坐标系与单位 · Axes and units**
  图内有标题行（`STARS (COUNT)` / `COMMITS (COUNT)`）、纵轴单位、5 条纵轴刻度、
  横轴时间刻度、最新值标记与"来源"说明——不再依赖 README 图注去猜。
- **横轴改为真实时间 · Real time axis**
  旧实现按**索引等距**绘制，采样间隔不均时时间被拉伸/压缩；现在按 **UTC 时间戳**
  线性映射，并标注 `MM-DD HH:MM`（首 / 中 / 尾）。

### 新增 · Added

- **图表自检 `--selftest`**：不联网核对刻度上限（含 1/2/2.5/5 阶梯）、刻度单调、
  时间轴按真实间隔映射、单点落中、降采样保留首尾、历史点容错、字体字符齐全、
  PNG 头部与尺寸正确——已接入 `stats.yml` 与 `ci.yml`。
- **历史点容错**：缺字段 / 坏时间戳的条目**跳过并留痕**，不再因一条坏数据丢掉整段历史；
  读取后按时间排序。
- **降采样**：点数超过像素密度时等距抽样（保留首尾），历史最多保留 2000 点。
- **README 图注重写**：中英对照，明确写出「纵轴从 0 起 / 单位是个 / 横轴是 UTC 时间 /
  两图不可直接比高度 / 更新频率与产物路径」。
- 仍然**零第三方依赖**：zlib 手写 PNG + 内置 5×7 点阵字体（大写字母 / 数字 / 少量符号），
  Actions 里零安装运行。## v5.2.0（2026-10-04 · 正式版）

**主题**：动效**严格按档位分级** —— 降档 = **降质量**，而不是在各处写死或直接砍掉效果。
*Animations are strictly tiered: lowering the tier now **reduces quality** instead of hard-coding or cutting effects.*

### 变更 · Changed

- **档位语义改为「质量」· Tiers now mean quality**
  每一档都有完整的动画，只是**开销逐级更低**（`1 最保守 → 2 标准 → 3 拉满`），
  档位 `0` 为静默（时长归零、无位移/缩放，**内容依旧完整呈现**——不是"功能更少"）：

  | 档位 | 时长（快/中/慢） | 入场效果 | 错峰项数 | 过渡位移 | 缩放 | 模糊 |
  |---|---|---|---|---|---|---|
  | 0 静默 | 0 / 0 / 0 | 无 | 0 | 0 | 无 | 无 |
  | 1 保守 | 110 / 150 / 190 ms | 只淡入 | 前 4 项 | 0.012 | 无 | 无 |
  | 2 标准 | 170 / 220 / 280 ms | 淡入 + 轻位移 | 前 9 项 | 0.035 | 无 | 无 |
  | 3 拉满 | 220 / 300 / 380 ms | 淡入 + 位移 + 轻微缩放 | 前 17 项 | 0.06 | 0.99 / 0.985 | 允许（≤6） |

  *Every tier keeps the full animation vocabulary; only the cost drops with the tier. Tier 0 is silent but still shows all content.*

- **设置项文案随语义更新 · Settings copy updated**
  动效档位标签由「最小 / 当前 / 标准 / 增强」改为 **静默 / 保守 / 标准 / 拉满**，
  说明写清每档**具体做了什么**（15 语言同步）。

### 新增 · Added

- **档位质量表 `OgLOAnimQuality`**：把某档位下的**全部**动画参数
  （时长、错峰步长、错峰项数上限、入场位移/缩放、过渡位移/缩放、模糊上限、缓动）
  收进一张表，成为唯一事实来源；`isNotHeavierThan` 把"降档 = 降质量"钉成可测约束。
- **入场动画按档位限项**：`OgLAnim.staggerOf()` 对超出档位上限的序号返回 `null`，
  `OgLReveal` 见到 `null` **直接静态渲染**。此前长列表的每一项都会挂动画
  （越靠后的项越晚、且同时起跳），是"列表滑动发涩"的常见来源。
- **`OgLReveal` 自带 `RepaintBoundary`**：入场期间每帧只重合成，不重绘列表项内容。
- **动效分级门禁 `tool/motion_audit.py`（已接入 CI）**：`lib/surface/**` 里禁止
  硬编码 `Duration(milliseconds: …)`、`ScaleTransition/AnimatedScale`、
  `BackdropFilter/ImageFilter.blur`（档位表与工具箱白名单除外；
  节流 / 缓存 TTL / 草稿防抖 / 双击退出窗口等**等待类**时长可豁免）。

### 性能深挖（简单、稳定，不做特判）· Performance pass

扫描出 5 类反模式（`tool/perf_audit.py`），按"确定性收益"排序处理：

- **长列表懒加载 · Lazy long lists**
  新增 `OgLAsyncSliver`（`AsyncView` 的 sliver 版）：静态头部留在
  `SliverToBoxAdapter`，**数据行交给 `SliverList.builder` 按需构建**。
  此前 `ListView(children:[…])` 里套
  `AsyncView(builder: (c, files) => Column(children: [for …]))` ——
  一次 PR 改 300 个文件就是**一次性构建 300 个 ExpansionTile**；
  PR 页与提交页已改用它（其余数据驱动列表按同一模式推进）。
  *`ListView(children:)` + `for` 的写法只报告不拦截（循环长度是语义问题，
  硬拦会逼出无意义白名单），门禁只保留客观项。*
- **窄 MediaQuery 选择器 · Narrow selectors**
  `OgLAnim.enabled` 由 `MediaQuery.of(context)` 改为
  `MediaQuery.disableAnimationsOf(context)`：列表项不再因为**键盘弹出 / 旋转 /
  insets 变化**而整列重建（长列表里这条最明显）。
- **隐藏页停表 · Stop offscreen tickers**
  切 tab 时给被隐藏的页面套 `TickerMode(enabled: false)`：不可见页面不再推进动画
  （下载进度、入场动画等），避免"看不见的页面在偷偷烧帧"。
- **主题缓存 · Theme cache**
  `SurfaceBridge.themeFor(brightness, motionLevel:)` 按
  （亮度 + 种子色 + 密度 + 动效档位）缓存 `ThemeData`；键不变就复用同一实例，
  顺带让 `AnimatedTheme` 不再把"等价主题"当成变化（每次 setState 都重建主题是隐性开销）。
- **日志通知合并 · Coalesced notifications**
  `OgLAppLog.add` 批量写日志时把 `notifyListeners` 合并为**最多 200ms 一次**
  （数据仍逐条立即入表，只是通知延后——不改变任何可见内容），
  避免通知中心整表反复重建。

- **更多长列表改懒加载 · More lists made lazy**
  - **仓库文件列表**（`repo_page`）：`ListView(children:[…])` → `CustomScrollView` +
    `SliverList.builder`——目录动辄上百个文件，此前一次性构建全部行；
  - **议题评论**（`issue_page`）→ `OgLAsyncSliver`；
  - **Actions 作业列表**（`action_run_page`）→ `SliverList.builder`（作业 + 步骤）。
  手法统一：**行内容原样保留**，只是移进 `itemBuilder` 闭包并用 `index` 取当前行
  （不抽方法、不改视觉），减少回归面。
- **已评估、数量有界、刻意保持急加载 · Reviewed, bounded, kept eager**：
  「关于」清单、本地账号、Gist 文件、Release 附件、工作流 inputs、分支选择弹层
  （常量级或几十条以内）。这些已在 `perf_audit.py` 的 `REVIEWED_BOUNDED` 里逐条登记
  理由，避免"看起来像待办"。

**门禁**：`tool/perf_audit.py --fatal` 已接入 CI，拦截 `shrinkWrap: true`
与过宽的 `MediaQuery.of(context)`（必要例外逐个登记并写明理由）；
新增 `test/surface/async_sliver_test.dart`（500 行只构建视口附近的行）。

### 修复 · Fixed

- 修掉主题切换动画（固定 260ms）、切 tab 滑动（固定 220ms）、下载进度补间（固定 220ms）、
  引导页翻页（固定 250ms）**绕开档位**的问题——现在全部读档位质量表。

## v5.2.0（2026-10-04 · 正式版）

**主题 · Theme** — 动画**严格按档位分级**（降档 = 降质量、不删效果）、一轮性能优化，以及一次被对抗性探针发现的内核一致性硬化。
*Strictly tiered animations (lowering a tier reduces cost, never removes effects), a performance pass, and a kernel-consistency hardening found by an adversarial probe.*

### 变更 · Changed
- **动效改成「按档位给质量」· Animation tiers now mean quality**
  每档都保留完整动效，只是开销逐级降低；档位 `0` 静默但**内容依旧完整呈现**：

  | 档位 | 快/中/慢 | 入场效果 | 错峰项数 | 过渡位移 | 缩放 | 模糊 |
  |---|---|---|---|---|---|---|
  | 0 静默 | 0 / 0 / 0 | 无 | 0 | 0 | 无 | 无 |
  | 1 保守（默认） | 110 / 150 / 190 ms | 只淡入 | 前 4 项 | 0.012 | 无 | 无 |
  | 2 标准 | 170 / 220 / 280 ms | 淡入 + 轻位移 | 前 9 项 | 0.035 | 无 | 无 |
  | 3 拉满 | 220 / 300 / 380 ms | 淡入 + 位移 + 轻微缩放 | 前 17 项 | 0.06 | 0.99 / 0.985 | ≤ 6 |

  设置项文案随之改为 **静默 / 保守 / 标准 / 拉满**（15 种语言同步）。
  *Every tier keeps the full vocabulary; only cost drops. Tier 0 is silent but shows all content.*
- **入场动画按档位限项 · Bounded entrance animation**
  `OgLAnim.staggerOf()` 对超出档位上限的序号返回 `null`，`OgLReveal` 见到 `null` 直接静态渲染——长列表不再"越靠后越晚"。
- **长列表懒加载 · Lazy long lists**
  5 处数据驱动长列表改用懒加载（其余保持急加载的已在审计里登记理由）：仓库文件列表 / PR 文件 / 提交文件 / 议题评论 / Actions 作业。
- **窄 `MediaQuery` 选择器 · Narrow selectors**
  `OgLAnim.enabled` 改用 `MediaQuery.disableAnimationsOf`：列表项不再因为键盘 / 旋转 / insets 变化整列重建。
- **隐藏页停表 · Offscreen pages stop ticking**
  切 tab 时给隐藏页套 `TickerMode(enabled: false)`。
- **主题缓存 · Theme cache**
  主题按（亮度 + 种子色 + 密度 + 动效档位）缓存，避免每次重建 `ThemeData`。
- **日志通知合并 · Coalesced log notifications**
  批量写日志时把通知合并为同一事件循环一次（微任务，不引入计时器；数据仍逐条入表）。

### 新增 · Added
- **内核一致性硬化：清单 ↔ 运行期模块交叉校验 · Manifest coverage cross-check**
  引导清单声明了某模块、装配时却没提供它，此前既不拒绝也不留痕；现在记为 `OGL-BOOT-108`（warn 级诊断 + 引导信任告警）——**仍可启动，但一定留痕**。附回归用例。
- **CI 门禁扩到四个维度 · Four CI gates**
  `layer_audit`（依赖只能向下）、`i18n_scan`（界面文案 0 遗漏）、`motion_audit`（动画必须走档位）、`perf_audit`（反模式）。
- **对抗性探针分支 · Adversarial probe branch**
  独立 CI 分支上跑一次性探针脚本，专门找"看起来正常但少了整层能力"的静默缺陷。

---

## v5.1.0（2026-10-04 · 正式版）

**主题**：5.x 的第一个正式版 —— 5.0 的交互打磨**全部内容** + 一次被探针发现的内核一致性硬化。
*First stable of the 5.x line: everything from 5.0 plus a kernel-consistency hardening found by an adversarial probe.*

### 与 5.0.0-beta 的关系 · Relationship

- 本版 = `v5.0.0-beta` 的全部内容（多连接分片下载 / 页面过渡修复 / 长日志虚拟化 /
  通知中心去符号 / 返回键统一 / 权限每次启动自检）+ **内核「清单 ↔ 运行期模块」交叉校验**。
- 也就是说：**升级到 5.1.0 即可，无需先装 5.0.0-beta**。
  *Upgrading straight to 5.1.0 is enough; 5.0.0-beta is superseded.*

### 新增 · Added

- **内核一致性硬化：清单 ↔ 运行期模块交叉校验 · Manifest coverage cross-check**
  由一次性对抗性探针（独立分支 CI）发现：**清单里声明了某模块、装配时却没有提供它**，
  此前既不拒绝也不留痕（应用"看起来正常"，实际少了一整层能力）。
  现在 boot 封存总线后会逐一比对，缺失项记为 `OGL-BOOT-108`
  （诊断 warn + 引导信任告警）——**能启动，但一定留痕**，不误伤可用性。
  *Found by a throwaway adversarial probe running on its own CI branch: a module declared
  in the boot manifest but never assembled was previously accepted silently. The kernel now
  cross-checks manifest against runtime modules and records `OGL-BOOT-108` (warn-level
  diagnostic + boot trust warning) — boot still succeeds, but never silently.*
- 该行为带**回归用例**（`test/kernel/kernel_test.dart`：清单声明但未提供 → 必须出现
  `OGL-BOOT-108`）。*Covered by a regression test.*

### 5.0 内容（本版包含）· 5.0 contents included

- **多连接分片下载**：`Range` 并发拉取 + 顺序合并；每片独立临时文件（规避共用句柄错位），
  任一分片失败即清理全部分片（不交付半成品）；不支持 `Range` 自动回退单连接。
  新增「下载并发连接数」设置（1/2/4/8，默认 4）与进度/速度动画。
- **页面过渡卡顿修复**：去掉整页缩放（`ZoomPageTransitionsBuilder` 的整页重光栅化正是根因），
  改为单层淡入 + 轻位移并强制 `RepaintBoundary`。
- **Actions 长日志虚拟化**：按行分块 + `ListView.builder` 按需渲染，显示「共 N 行」。
- **通知中心**：去掉 `✔ / ▶ / ✗ / ★` 等 emoji 风格符号（改由图标与 `level` 承载），
  详情展开带动画。
- **安卓返回键统一**：二级页 / 弹窗 → 抽屉 → 回首页 tab → 双击退出（一次误按不退出）。
- **权限自检（每次启动）**：实测存储（真实写入探针）与通知权限，缺失时带事件码
  （`OGL-PERM-001/002/000`）上报通知中心。

### 已知限制 · Known limitations

- 分片下载的**暂停 = 重新开始**（不假装续传）；单连接库任务的断点续传不受影响。
- 桌面端仍使用库下载（分片引擎按 `Range` 能力判定，不支持则回退）。
- `v5.0.0-beta` 的产物构建于内核硬化之前；如需完整修复请使用本版。

## v5.0.0（2026-10-04 · beta 预发布）

**主题**：交互与体验打磨（不加新功能面）。用户明确的 5.0 范围**已全部实现**，见下。

- [x] 下载管理器**多连接分片**下载（进度 / 速度显示动画优化）
- [x] **页面过渡卡顿**（定位到根因并修掉，附回归测试）
- [x] Actions **长日志**（懒加载 / 虚拟化 / 分块渲染）
- [x] **通知中心**（去掉 emoji 风格符号 + 详情展开动画）
- [x] **安卓返回键**全局统一处理（二级页 / 弹窗 / 抽屉 / tab / 退出）
- [x] 权限网关**每次启动实测**（用户本轮追加要求）

### 下载：多连接分片（5.0 第 1 项）

- **启动层契约** `kernel/contract/download_engine.dart`：把「分片下载能力」写成接口
  （`probe` / `fetch` / 取消令牌 / 失败语义），逻辑层只认契约 —— 依赖方向不破。
- **硬件层实现** `base/net/range_download.dart`：
  - `Range` 请求把文件切成至多 N 片**并发拉取**，最后顺序合并；
  - 每片写**独立临时文件**（`<目标>.partN`）而非共用文件句柄 —— 直接规避项目早期
    "多 worker 共用 `RandomAccessFile` 导致错位写坏"的老问题；
  - 任一分片失败/取消 → **删掉全部分片**，绝不把半成品当成功；
  - 分片长度不符即判失败（宁可从零再来，也不交付坏文件）；
  - `OgLChunkPlan` 是**纯函数**（不重不漏、余数进最后一片、小文件不开一堆连接），
    有 7 条边界用例（含逐字节覆盖校验）。
- **中枢层**：`IxDownloadManager.enqueue(connections:)`；服务端不支持 `Range`
  （或探测失败）**自动回退**到库任务（同一 taskId，页面无感），
  回退与失败分别记 `OGL-DL-201` / `OGL-DL-202`。
  暂停 / 取消 / 重试对分片任务走取消令牌（不留半个文件）。
- **设置项**：设置 → 网络 →「下载并发连接数」（1 / 2 / 4 / 8，默认 4）；
  非法值回落默认（手改配置文件也不会崩）。
- **进度 / 速度动画**：进度条用 `TweenAnimationBuilder` 补间 220ms（不再"跳格子"）；
  速率量化到 0.1 MB/s 后经 `AnimatedSwitcher` 淡入淡出；分片任务在列表里带
  「多连接」图标标记。

### 页面过渡（5.0 第 2 项）

- **根因**：Android 默认过渡是**整页缩放 + 位移 + 淡入**（`ZoomPageTransitionsBuilder`），
  缩放要求整页在过渡期间反复重新光栅化 —— 页面越重越卡，而小控件动画不受影响，
  所以表现为"只有页面过渡卡"。
- 改为**单层**过渡：淡入 + 轻微上移（**不用缩放**），档位只调位移距离；
  过渡强制包 `RepaintBoundary`（过渡期间只重合成、不重绘页面内容）。
- 切 tab 的 `_OgLShellSlide` 同样补上 `RepaintBoundary`（此前整棵页面树每帧重绘）。
- 新增 `test/surface/page_transitions_test.dart`：锁死"必须包 RepaintBoundary、
  不得出现任何缩放、不得回退默认缩放过渡、全平台都要配到"。

### Actions 长日志（5.0 第 3 项）

- 新增 `surface/widgets/log_body.dart`：按行**分块**（默认 120 行/块）交给
  `ListView.builder` 虚拟化渲染；上万行日志不再一次性排版。
- 日志页显示「共 N 行」，并保留行内选择复制（每块独立 `SelectionArea`）。
- 新增 `test/surface/log_body_test.dart`：断言 1200 行时**只渲染视口附近的分块**
  （虚拟化失效会被测出来）。

### 通知中心（5.0 第 4 项）

- **去掉符号字形**：`✔` / `▶` / `✗` / `★` / `→` / `←` 不再出现在用户可见文案里
  （它们在 Android 上会被当 emoji 呈现，正是用户说的"emoji 撕裂"）。
  结构化信息改由 `level` 承载（新增 `STEP` 级别），可见性交给图标。
- 仓库列表的用户可见 "★ N" 改为本地化文案 `{count} 星标`。
- 详情展开带动画（`AnimatedSize`），并新增会旋转的展开指示图标；
  「未读」也走 i18n（不再硬编码中文）。

### 安卓返回键（5.0 第 5 项）

- 新增 `surface/app/back_guard.dart`：把"按一次返回键应该做什么"抽成**纯状态机**
  （可单测）；`ClientShell` 用 `PopScope` 统一接管。
- 优先级：可弹出的二级页 / 弹窗 → 抽屉 → 回到首页 tab → 首页第一次提示
  「再按一次退出」、窗口内第二次才退出（**一次误按绝不退出应用**）。
- 新增 `test/surface/back_guard_test.dart`（7 条时序用例，含窗口过期与状态清理）。

### 权限网关（用户本轮追加）

- 新增 `surface/app/permission_selftest.dart`：**每次启动**都实测权限
  （存储走真实写入探针，通知向系统查询），**只复核不弹窗**，5 秒超时兜底。
- 缺什么 → 诊断 warn + 事件码（`OGL-PERM-001` 存储 / `OGL-PERM-002` 通知 /
  `OGL-PERM-000` 自检失败）→ 通知中心；就绪项只留日志。
- 「关于 → 启动诊断」新增「权限自检」折叠组（平台 / 每项状态 / 事件码）。
- 新增 `test/surface/permission_selftest_test.dart`（含"自检自身失败也不抛"用例）。

## v4.9.0（2026-10-04）

本版本 = **结构与多语言工程**（不含新功能）。

### 四层结构收口（启动 / 硬件 / 逻辑 / 交互）
- 依赖方向固定为 `surface → domain → base → kernel`，只允许向下。
- 新增交互层**类型门面** `lib/surface/types.dart`：UI 只能看到 DTO / 枚举 / 异常，
  服务类（`GhClient` / `GhAuthService` / `IxDownloadManager` / `IxSession` /
  `IxNotificationCenter`）被 `hide`，只能经 `SurfaceBridge` 取用。
- 15 个页面 / 组件改为只 import 门面；导入段按 `directives_ordering` 重排。
- **下载能力上桥**：`SurfaceBridge` 提供 `downloadTasks / downloadsListenable /
  pauseDownload / resumeDownload / retryDownload / cancelDownload /
  removeDownload / clearFinishedDownloads`，下载页不再接触管理器实现。
- 新增 `tool/layer_audit.py`（四层审计）：**当前违规 0**。
- **共享抽象上提到启动层契约**：`disk_store.dart` / `disk_types.dart` /
  `net_types.dart` 移入 `kernel/contract/`（原路径保留**转发导出**，硬件层内部零改动），
  逻辑层改依赖契约 → 待收敛项由 11 处降至 **2 处**（仅剩 `RepositoryCache` /
  `NetBridge` 两个**实现类**，下一批以契约接口收敛）。

### 多语言（R6 · 落地）
- 支持 **15 种语言**：zh / zh_TW / en / ja / ko / fr / de / es / pt / ru / ar / hi /
  th / vi / id；**首次启动跟随系统语言**（繁体系统 → zh_TW），
  设置页可**即时切换**（无需重启），选择落盘、下次启动直接生效。
- 分片结构 `assets/i18n/<locale>/<page>.json`（2 空格缩进 + 键排序）：
  **27 个页面 / 848 条中文文案**由人工按语境撰写；术语（GitHub / Release /
  Actions / Pull request / Token / Pages / Commit…）**不译**，描述不加额外语句。
- 其余 14 种语言用 AI **按语种合并请求**批量生成（一个语种 = 一次 API 调用，
  27 页一起给），带格式校验与「不合格自动打回重翻」；最终校验
  **15 语言 × 27 页面 / 13065 键，问题 0**（键集合一致、占位符完整、
  非 CJK 语言无残留中文、无空值）。
- 页面代码**批量接线**：`t(page, key, {args})` 支持 `{name}` 占位符，
  兜底顺序 = 当前语言 → 英文基线 → 键名（**绝不返回空串**）；
  新增 `tool/i18n_wire.py`（按 zh 分片反查、占位符按位绑定、自动补 import/助手、
  剥掉会失效的 `const`）与 `tool/sort_imports.py`。
- **门禁化**：`tool/layer_audit.py --fatal`（依赖只能向下）与
  `tool/i18n_scan.py --check`（界面文案 0 遗漏 / 分片键集合与 zh 一致）
  已接入 CI —— 结构回退与漏翻会在合并前被挡下。
- 现状：交互层**界面文案 0 处未本地化**；剩余约 405 处中文均为开发者日志 / 诊断
  （按设计保留；个别「先拼字符串再落盘」的日志载荷用 `// i18n-allow` 显式豁免）。
## v4.8.0（2026-10-03）

### 下载加速通道（重做）
- **恢复为独立条目**：设置 → 网络 → 「Release 下载加速」。
- **只有一个总开关**；下面是**通道列表**：内置通道（开发者自建，HTTPS）+ 任意多个
  **自定义通道**，**单选生效**，自定义通道可随时移除（内置不可删）。
- **内置通道地址更新为 `https://server.344977.xyz:9999/`**（HTTPS；此前明文
  `http://…:5000/` 会被 Android 9+ 拦截，正是 4.4.0 那次下载故障的根因）。
- 自定义通道地址**必须是 HTTPS**，且需以 `/` 结尾；明文 http 会被直接拒绝并说明原因。
- 生效条件 = 总开关打开 **且** 已同意当前版本协议；否则一律直连。

### 协议（具法律效力的显式同意）
- 新增两份协议文本与**版本号**（`util/accel.dart`）：
  - **外来服务自负责任协议**（自定义/第三方通道）；
  - **内置通道安全声明**（开发者自建通道）。
- 开启总开关时若未同意当前版本，**必须先勾选"我已阅读并同意上述条款"** 才能继续；
  同意后记录**版本号 + 时间戳**落盘，作为凭据；协议升版需重新同意。

### 其他
- 新增单元测试 `test/surface/path_rules_test.dart`（路径规则 / 空文件 / `.gitkeep` /
  通道地址 / 地址拼接 / 协议区分）。

### 文件操作细节（续）
- **重命名文件**：长按文件 → 重命名（内容不变，**一次原子提交**：新增新路径 + 删除旧路径）；
  新路径同样受"禁中文/特殊字符"校验；`.gitkeep` 不允许重命名。
- **删除目录**：长按目录 → 删除目录，会先枚举其下全部文件并在**一次提交**中删除；
  结果被截断或超过 200 个文件时**拒绝**并提示分批（不静默半删）。

### 系统级通知（接入插件）
- 新增 `flutter_local_notifications`，后台/`allChannels` 通知改为**真正发系统通知**
  （Android / Windows / Linux / macOS / iOS）；失败只留痕并回退到"落盘 + 回前台补发"。
- Android 需 core library desugaring：`tool/inject_android_gradle.py` 现在**幂等注入**
  `compileOptions.isCoreLibraryDesugaringEnabled` 与 `desugar_jdk_libs:2.1.4`，并在自检中校验。

### 动效（R7 续）
- 主题切换带动画（`themeAnimationDuration`）：换明暗 / 主题色不再"硬切"；
  系统关闭动画时自动为 0（与 R11 一致）。
### 本版本未纳入（4.9 排期）
- **多语言（R6）**：继续后延。
- 目录重命名、跨目录批量操作（当前仅支持单文件重命名与目录删除）。

## v4.7.0（2026-10-03）

R3 / 文件细节 / 通知 / 外观修正（**多语言仍留待下一版本**）：

### 文件创建（仓库 · 代码页）
- **单一 "+" 入口**：原来的"新建文件"按钮改为只有加号的 FAB；
  **添加路径 = 建目录**——路径以 `/` 结尾时自动创建 `<目录>/.gitkeep` 占位
  （Git 不跟踪空目录）。
- **禁止空文件**：新建文件必须填写内容（`.gitkeep` 占位例外）。
- **路径规则**（`util/path_rules.dart`，新建/重命名共用）：只允许
  `A-Z a-z 0-9 . _ -` 与 `/`；**禁止中文与全角字符**、空格与特殊字符；
  禁止 `..`、`//`、以 `/` 开头、以点/空格结尾、Windows 保留名、单级 > 100 字符。
- 同名条目存在时**先拦下**并给出原因（不再等 422）。

### R3 越权入口（用 `permissions.push`，不做降级）
- `GhRepo` 新增 `canPush` / `canAdmin`（解析 `permissions`）与 `isWritable`。
- 仓库页在 `initState` **补拉单仓库详情**（只有该接口返回 `permissions`，
  列表/收藏/搜索都没有）；拿不到详情时留痕并按不可写处理。
- 无写权限时隐藏：**仓库设置标签页**、新建文件 FAB 与空态按钮、
  文件编辑/删除、条目删除、新建发布、新建分支。

### 通知（渠道参数 + 前后台分流）
- 新增 `OgLNoticeDelivery{auto, inAppOnly, allChannels}`，`report()` 可指定投递方式。
- `OgLNoticeHost` 接入 `WidgetsBindingObserver`：**后台不弹应用内提示**，
  `allChannels` / critical 走系统通道，其余排队并在**回到前台时补发**（不丢消息）。

### 外观
- 外观页 `ChoiceChip` 选中态改为 `primary/onPrimary`，**明环境下对比度提升**；
  主题色芯片不再用勾号顶掉色点。

## v4.6.0（2026-10-03）

第三阶段（工程与交互）：

- **R10 工作流参数表单**：手动触发工作流时，读取该工作流 YAML 的
  `on.workflow_dispatch.inputs`，把**必选参数 / 默认值 / 选项**渲染成表单
  （字符串 / 数字 / 布尔 / 下拉选择），必选缺失会在提交前拦下并提示；
  保留「高级：直接输入」入口（JSON 或每行 `key=value`）。新增纯 Dart 依赖 `yaml`。
- **R7 页面切换动画**：底部 / 侧边导航切换时加入**左右滑动**入场过渡
  （保留 `IndexedStack` 的状态与懒挂载）；关闭动画时瞬时切换。

> 待办：**R6 多语言**（其余页面仍有硬编码中文）体量较大，需要单独排期
> 逐页抽取文案 + 补齐各语言分片，本次未纳入，以免产出半成品的一致性问题。

## v4.5.0（2026-10-03）

第二阶段（体验）修复：

- **R1 通知中心**：条目可点击展开**完整详情**（时间 / 区域 / 正文，可选中复制）；
  新增「已读 / 未读」状态与「标记已读 / 全部已读」；保留「重置通知中心」
  （只清内存条目，磁盘日志不动）。
- **R4 只读缓存**：新增中枢级只读端点缓存（`GhReadCache`），为 Releases /
  分支 / 提交 / Issues / PR / Actions / 仓库详情等只读端点设定缓存时长
  （30–60 秒），账号维度隔离；**下拉刷新 / 写后重读会让缓存失效**并回源；
  切换账号时清空。搜索、用户、限流端点不缓存（必须新鲜）。写操作令整体失效。
- **R5 Release 附件**：点击改为**查看文件详情**（大小 / 类型 / 下载次数 / 直链），
  下载与复制链接移到详情弹窗与**长按**菜单——不再点一下就下载。
- **R11 动画警告**：检测到系统关闭动画（开发者选项 / 无障碍）时，启动即通过
  通知中心给出**明确警告**（此前应用不给任何提示，属缺陷）。

## v4.4.0（2026-10-03）

修复（设备实测反馈）

- **下载：不再走明文加速通道**。该通道仅支持 HTTP（无 TLS），在 Android 9+ 会被
  系统直接拦截（`Cleartext HTTP traffic to ... not permitted`）。设置项已从界面
  移除；通道地址仍只存在于实现内部常量，不对外暴露。
- **下载完成显示真实大小**：库对小文件可能一次进度事件都不发，此前界面一直显示
  `0 B`；现于完成时以磁盘文件大小回填（读不到则按事件码 `OGL-DL-101` 上报）。
- **Actions 筛选失效**：成功 / 失败 / 进行中筛选此前只用于判断空态，列表仍渲染
  全量；现按筛选后的子集渲染。
- **搜索页切换标签不清空结果**：切「仓库 / 代码」时清空旧结果与输入框。
- **切换 / 移除账号时清空全部缓存**：仓库缓存 + DNS 缓存 + 页面分页快照
  （避免"用 B 账号看到 A 账号的私有数据"）。
- **通知中心打通**：内核诊断的 **warn 与 error** 现在都会进入通知中心
  （error → 严重级弹窗；warn → 横幅），且要求携带事件码——不允许静默降级。

## v4.3.0（2026-10-03）

下载

- Release 附件加速**改为设置项**（设置 → 网络 →「Release 附件加速通道」），
  默认**关闭** —— 加速通道属于第三方信任边界，需用户显式开启；关闭后附件直连。
  该开关只作用于 Release 附件，不影响仓库文件 / Gist 的下载。
- **通道地址不再出现在任何界面文案或设置项中**（收敛为实现内部常量）。

## v4.2.0（2026-10-03）

本版：网络传输弃用 dio、代码编辑与高亮换用成熟库、并批量修复设备日志排查出的
问题（P2–P7）。

代码查看与编辑（**换用成熟库**）

- 新增 `re_editor`（编辑器内核）+ `re_highlight`（语法高亮，highlight.js 的 Dart
  移植）；删除自研词法器与自绘渲染 `lib/surface/widgets/code_view.dart`。
- 编辑器不再使用"高亮图层 + 透明输入层"叠加：语法高亮、行号、查找替换、
  撤销重做、折叠、快捷键全部由库提供，光标 / 换行 / 滚动不再错位。
- 查看器（仓库文件、Gist）与编辑器共用同一套库渲染（`OgLCodeViewer` /
  `OgLCodeField`）；超大文本改由库的 `CodeHighlightThemeMode.maxSize` 兜底。
- 保留项目语义：语言识别（按扩展名 / 文件名）、设置里的高亮预设与自定义配色
  （翻译为 highlight.js 主题表）、草稿防抖落盘、加锁保存与冲突提示。

下载（`background_downloader`，本就是库实现）

- 移除旧自研分块下载器遗留的 `threadsActive` 字段（从未赋值）；
- 进度速率改为按库的进度事件**差分估算**（此前该字段恒为 0，界面上的速率是假的）。

网络（**弃用 dio**）

- 传输层由 `dio` 改为**直接使用 `dart:io HttpClient`**（新增 `lib/base/net/io_net_transport.dart`，
  删除 `dio_net_transport.dart`），`pubspec.yaml` 移除 `dio` 依赖；Actions 日志下载（`IxActionLogs`）
  同步改为 `HttpClient`。理由：Dio 把"连接策略"藏进适配器层，排查与修都无法直接动手。
- **禁用 keep-alive 连接复用**（每个请求 `request.persistentConnection = false`，
  即请求头带 `connection: close`）：
  设备日志实证 `Connection closed before full header was received` 反复出现，
  而同一时刻原生自检全绿——差别只在"是否复用连接"。禁用复用后每个请求走新连接，
  从根上消除该类故障。
- 连接类失败（`SocketException` / `HttpException`）统一归为**可重试**的连接错误，
  并在重试前**清空 DNS 缓存**（避免钉在坏 IP 上）。
- 新增 PoC / 回归测试 `test/base/net_transport_reconnect_test.dart`：
  对端"响应后即关闭连接"时，连续请求必须全部成功；并断言连接策略已禁用复用。

日志排查后续修复（P2–P7）

- **P2 未分类网络错误现在可重试**：`dart:io` 把"连接在接收中被关闭"等场景归入
  `unknown`，此前不可重试，大响应中途失败即终止；现纳入可重试类别
  （是否真正重试仍受"仅幂等方法"约束，`POST` 依旧不会自动重试）。
- **P3 仓库浏览不再绕过缓存**：目录列表与文件读取原先一律 `refresh: true`，
  使底座缓存永不命中、每次切目录/切标签都重新下载；现默认走缓存，
  仅下拉刷新 / 写操作后强制回源。
- **P4 切标签不再重复拉取**：分页数据源新增"同目标 6 秒内的成功快照"，
  标签页被 `TabBarView` 销毁重建时秒开、不再重复请求；
  用户下拉刷新与写后重载不受影响（始终回源）。
- **P5 正常缺省不再报错**：404（无 README / CNAME / Pages）降级为 WARN；
  `readme()` 改为直接请求 `/readme`，去掉"先探测 `README.md`"的额外一次 404。
- **P6 窗口日志节流**：幽灵键盘 inset 高频抖动不再逐条落盘（同形态最多 1 秒 1 条）。
- **P7 重负载端点分页调小**：发布 / Actions 每页 30 → 10，降低单次响应体积
  （此前单次可达数百 KB ~ 2 MB）与弱网中断概率。

## v4.1.0（2026-10-03）

本版聚焦「仓库浏览」的补齐与控件/布局的 Material 3 规范化。

仓库浏览

- 新增**分支切换**：AppBar 下方常驻分支栏（Material 底部弹层 + 搜索），
  切换后「代码 / 提交 / 发布 / Actions」同步；
- 新增**新建文件**：代码标签提供 `FloatingActionButton` 入口（路径 + 内容）；
- 新增**目录内筛选**：按名称过滤当前目录条目；
- 新增**图片预览**：png / jpg / jpeg / gif / webp / bmp / ico 在应用内预览（可缩放），
  不再显示为二进制乱码；
- 新增**分页「加载更多」**：首页仓库列表（我的 / 星标）与仓库页的
  发布 / 分支 / 提交 / Actions 统一分页；
- `GhApi.workflowRuns` 新增 `branch` / `page` 参数。

控件与布局（Material 3）

- 「新建」类主操作统一为 `FloatingActionButton.extended`
  （新建仓库 / 新建议题 / 新建发布 / 新建分支 / 新建文件）；
- 次要操作收进 `PopupMenuButton`：仓库（复刻 / 复制克隆地址 / 浏览器打开）、
  文件（复制路径 / 浏览器打开 / 删除）、分支（重命名 / 删除）；
- 空 / 错 / 载三态与「加载更多」底部按钮统一；列表项统一 `ListTile` + `OgLReveal`；
- 危险操作（删除文件 / 删除分支 / 删除仓库）统一二次确认。

已知限制（客观）

- 分支切换作用于上述标签；议题 / PR 列表仍为仓库级（相关接口不按分支过滤）；
- 代码标签的目录内容由 Contents API 一次性返回，「加载更多」在代码标签仅表现为一次拉取；
- 文件内查找、blame、图片以外的二进制预览仍未实现。

验证

- 由 CI 验证：质量门（`analyze --fatal-infos --fatal-warnings` + 全量测试）
  与全平台构建矩阵（Android ×5 / Windows ×2 / Linux ×2 / macOS ×2 / iOS ×2）。

## v4.0.0（2026-10-03）

可靠性重构版：自底向上逐层修复，并将多个自研模块替换为成熟库。

验证状态

- CI 质量门通过：`flutter analyze --fatal-infos --fatal-warnings` + 全量单元/渲染测试；
- 全平台构建矩阵通过：13 个目标全部成功（Android ×5：arm64-v8a / armeabi-v7a / x86_64 / universal APK / AAB；
  Windows ×2；Linux ×2；macOS ×2；iOS ×2）。

依赖变更

- 新增 `permission_handler ^13.0.2`（运行时权限）、`background_downloader ^9.6.3`（下载）、`archive ^3.6.1`（日志解压）；
- 新增 `dependency_overrides: connectivity_plus: 6.1.4`：`background_downloader` 依赖 `connectivity_plus '>=6.1.3 <8.0.0'`，
  其 7.x 的 macOS / iOS Swift 使用了构建环境 SDK 尚未提供的 `NWPath.isUltraConstrained`，导致 iOS / macOS 构建失败；
  固定到 6.1.4（仍满足上游约束）后恢复；
- 未引入 `highlight` / `flutter_highlight` / `flutter_code_editor`：其 SDK 约束为 Dart < 3，与当前 Dart 3.13 不兼容。

权限

- 权限申请由纯 Dart 网关改为 `permission_handler`：Android / iOS / macOS 会真正调起系统权限弹窗；
  此前实现只执行"写入探针 + 打开设置"，且使用 iOS 专用的 `app-settings:` URI（在 Android 上无效）；
- Android 11+ 的「所有文件访问」使用 `manageExternalStorage`；Android 13+ 运行时请求 `POST_NOTIFICATIONS`；
- 构建期新增 `tool/inject_android_gradle.py`：幂等提升宿主 `compileSdk`（平台目录由 CI 现场生成）；
- 构建期新增 `tool/inject_windows_cmake.py`：为 `permission_handler_windows` 注入 MSVC 兼容宏
  `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`。

通知

- 统一通知入口：`KernelDiagnostics` 的 error 与引导层信任告警经 sink 转发到 `OgLNoticeCenter`，
  各层（含无 `BuildContext` 的底座 / 中枢）的告警均可触达界面；
- 通知中心新增历史记录列表。

认证

- `GhAuthService` 改为 `ChangeNotifier` 并引入 `GhAuthState`（unknown / signedOut / signingIn / signedIn / expired / guest）；
- HTTP 401 作为唯一出口触发失效标记；外壳订阅认证状态，令牌失效后自动回到登录门；切号 / 登出会通知订阅方。

草稿

- `DraftStore` 改为 `ChangeNotifier`，并通过 `GhApi.draftsChanged` 暴露；
  草稿箱与「我的」页订阅后实时刷新（此前为一次性查询）。

编辑器

- 编辑区改为「高亮图层 + 透明输入层」叠加，编辑过程中可见语法高亮（复用项目既有词法器；未引入 `highlight` 系库的原因见上）；
- 撤销 / 重做改用 Flutter 内建 `UndoHistoryController`（替换自研防抖快照栈）。

下载

- 下载实现由自研分块下载器改为 `background_downloader`（断点续传 / 队列 / 暂停 / 继续 / 取消）；
- 保持 `IxDownloadManager` / `IxDownloadTask` / `IxDownloadCategory` / `IxDownloadStatus` 对外契约不变，相关页面未改动；
- 落盘位置随库能力调整为「应用文档目录 / ogl / download / <分类>」（该库仅支持其 `BaseDirectory` 枚举，不支持任意绝对路径）。

Actions

- 新增运行日志：带令牌下载日志 zip 并经 `archive` 解压，按 job 展示与搜索
  （`ix_action_logs.dart` + `action_log_page.dart`）；
- 新增产物（artifacts）列表与下载地址端点。

动效

- 列表入场动效统一走 `OgLReveal` 与动效档位；本次覆盖搜索等页面。

其他

- 关于页依赖许可清单补充 `permission_handler` / `background_downloader` / `archive`；
- Android 发布护栏新增 `POST_NOTIFICATIONS` 断言；
- Windows 上的构建期 Python 脚本改为 ASCII 输出，并设置 `PYTHONIOENCODING=utf-8`
  （此前在 Windows 默认码页下打印非 ASCII 会抛 `UnicodeEncodeError` 并使该构建目标失败）。

已知限制

- `background_downloader 9.6.3` 的 `flutter.plugin.platforms` 仅声明 android / ios；桌面端（Windows / Linux / macOS）
  不注册该插件，桌面端下载功能不可用；
- 编辑器高亮为图层叠加实现，长文件下的滚动同步与自动换行场景尚未逐一验证；
- 动效为逐页补齐，尚未覆盖全部页面。

## v3.2.0（2026-10-03）

动效（与设置里的「动效档位」联动）

- 新增档位作用域与动效工具箱：动画时长与叠加效果按档位 0–3 变化；
- 入场动画覆盖：首页仓库、下载管理、通知中心、草稿箱、仓库页（Issues / Pull Requests / Releases / 分支 / 提交 / Actions）；
- 加载 / 空 / 错误三态之间加入淡入淡出；
- 档位 0 完全关闭动画；档位 1 仅淡入、档位 2 淡入 + 位移、档位 3 再叠缩放（开销随档位增加）；
- 新增分档与回退测试（时长递增、降到 0 回退为零、按档位叠加效果）。

其他

- 规划文档：新增 `docs/ANIMATION_PLAN.md`（3.2 任务与性能对应）；
- 交互细项（分段选择位移、对话框曲线、共享元素等）移交 3.3。

## v3.1.0（2026-10-03）

下载

- 内建下载器：多线程（32 线程）分块下载，支持暂停 / 继续 / 取消 / 重试 / 移除；
- 小于 16 MB 的文件一次铺满并发；服务器不支持 Range 时自动退回单流；
- 下载管理页展示进度与速率；首页右上角加入口；
- Release 附件经内置代理加速，落盘到 `ogl/download/<分类>/`。

文件与日志

- 统一应用根目录 `ogl`：日志落到 `ogl/logging`，下载按分类存放；
- 平台路径适配：Android 优先外部可见目录，不可写时退到应用外部目录；桌面用文档目录。

草稿

- 编辑器自动保存草稿；再次进入同一文件自动恢复并提醒；提交成功后清除；
- 「我的」页新增草稿箱入口。

可靠性与权限

- 启动接入失败写入重放；
- CNAME 更新改为加锁写入；
- 权限网关：Android 存储用真实写入探针主动获取，失败弹窗并跳转系统设置；
- 引导改为分步（欢迎 / 权限 / 隐私 / 完成）。

其他

- 首页右上角新增通知中心（可按告警 / 错误筛选、单条复制）。

## v3.0.0（2026-10-03）

界面

- 设置页改为可折叠分组，默认收起，并补充更多设置项与子项。
- 新增动效档位设置：最小 / 当前 / 标准 / 增强。
- 「关于」整理为设置页内的独立页面，展示项目名称、主要开发者、版本、仓库地址、未来扩展与启动诊断。
- 首页移除无响应的刷新按钮，保留下拉刷新。

功能

- 新增「捐赠一颗心」：二次确认后，用当前登录账号为本仓库加星；已 star 时不会重复操作。
- 新增「开源许可」栏目：本项目许可与第三方依赖清单。
- 新增「日志」栏目：日志文件位置与复制入口。
- 新增 15 种界面语言，翻译按页面分片保存。

可靠性

- 写入与删除带基线校验；冲突时先提示，再决定是否覆盖。

其他

- 开源许可切换为 AGPL-3.0。
- 新增星标与提交历史图表（见仓库首页）。
- 清理部分过时文案。

## v2.2.0（2026-10-02）

- 合并原定 v2.1.0 的内容（v2.1.0 未发布）。
- 修复静态分析错误后重新构建，发布产物 19 个。

## v2.1.0（未发布）

- 内容并入 v2.2.0。

## v2.0.0（2026-10-02）

- 修复手动发布时安装包版本号回落为 0.1.0 的问题：发布参数改为必填，并在构建阶段校验产物版本号。
- 构建版本号注入覆盖各平台产物。

## v1.4（2026-10-02）

- 新增缓存读取加速：目录与文件在短时间内命中缓存，下拉刷新可取最新。
- 写入与删除带基线校验，冲突时给出提示。
- 新增独立代码编辑器：撤销 / 重做、查找 / 替换、换行与字号、未保存提醒。
- 新增发布详情：附件下载、编辑与删除。
- 新增 Actions 运行详情（作业与步骤）与重新运行 / 取消。
- 新增手动触发工作流。
- 新增 Gist 列表、详情、新建、编辑与删除。
- Issues 支持评论。
- 文件图标按类型配色；代码高亮提供多种预设。

## v1.1.0（2026-10-01）

- 展示层重写，统一为 Material 3 组件。

## v1.0.0（2026-10-01）

- 首个版本，提供 Android / Windows / Linux / macOS / iOS 构建。

## v0.2.0-beta（预发布）

**主题 · Theme** — 第二阶段（W0–W8）：界面与功能重写。
*Stage two (W0–W8): a rewrite of both the interface and the feature set.*

### 新增 · Added（界面 · Interface）
- 统一页面骨架（页头 + 小节 + 箱体行），**12 个页面全部重写**：设置 / 首页 / 搜索 / 我的 / 议题 / PR / 提交 / Gists / 登录向导 / 新建仓库·议题·发布 / 仓库页 / 关于页，全部对齐设计文档。
- 主壳导航（手机底栏 / 平板导航轨 / 窄窗抽屉 + 页头）**全部自绘**，图标为 **47 个手写矢量**（零外部资源、纯直线、24 网格）。
- 行控件统一为 `OgLActionRow`（含自绘开关），清掉所有 Material `ListTile` / `SwitchListTile` / `ChoiceChip`。

### 新增 · Added（功能 · Features）
- **README 渲染**：仓库页代码标签下显示，**离线安全**（徽章剔除 / 图片占位 / 超长截断告知）。
- **代码搜索直达文件**：命中文件直接打开并显示上下文。
- **议题 Markdown**：正文与评论按 Markdown 渲染。
- 提交详情**分色补丁**预览（+ 绿 / − 红），超长截断。
- Gists 整行可点用浏览器打开；登录向导四步进度（暂存 → 验证 → 转正 → 保险库回读）。

### 可靠性 · Reliability
- 空结果不再被当"加载中"（零议题 / 零发布显示空态而非转圈）。
- 404 / 409 / 422 一律当"没有"；不再猜默认分支。
- 危险操作全部二次确认；失败一定可见。
- 新增**页面纪律护栏测试**（12 页必须走统一骨架）。

### 已知限制 · Known limitations
- 预发布：UI 自绘体系，1.0.0 起改为 Material 3 直出。
- 产物 19 个（Android 5 + Windows 2 + Linux 2 + macOS 2 + iOS 2 + 其它）。

## v0.1.0（预发布）

**主题 · Theme** — 首个公开发布：Linux 内核式分层架构的 GitHub 第三方客户端（Flutter 全平台）。
*The first public release: a GitHub client with a Linux-kernel-style layered architecture, built with Flutter for every platform.*

### 新增 · Added（核心能力 · Core capabilities）
- **登录**：个人访问令牌向导 + 游客模式。
- **首页**：我的仓库 / 星标仓库 / 新建仓库。
- **搜索**：仓库与代码双通道。
- **仓库全功能**：文件浏览与编辑提交；议题（新建 / 评论 / 关闭）；PR（列表 / 文件）；发布（新建 / 删除）；分支（增 / 删 / 改）；提交历史与对比；仓库设置（Pages / CNAME / 危险区）。
- **附加**：Gist 列表、账户管理、网络与 DNS 设置、应用日志。

### 安装注意 · Installation note
> **签名**：自本版起使用**固定证书**；由旧随机证书构建的安装包请**先卸载再安装**。

### 产物 · Artifacts
- Android（arm64-v8a / armeabi-v7a / x86_64 / universal APK / AAB）、Windows、Linux、macOS、iOS —— 共 **18** 个文件。