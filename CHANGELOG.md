# 更新日志

## 10.0.0（2026-10-31）

### 移除

- 完整移除 AI 助手、设置、网络调用、审计任务与入口；升级时清理本机遗留的 AI 数据。
- 界面语言收敛为简体中文与 English。

### 修复

- 编辑器进入前重新读取完整文件，严格校验 UTF-8，恢复草稿时保留原始版本基线。
- 草稿保存与删除顺序执行；路径特殊字符、删除版本校验与冲突反馈得到修正。

### 改进

- 校正中英文案，统一错误提示、确认操作、对话框动效与界面间距。

## v9.5.0（2026-10-18 · 正式版）

> **主题**：正确性总攻——两轮全域缺陷检索 × 全量修复 × 契约测试固化。

### 修复 · Critical（数据丢失类）
- **空文件被判"远端不存在"** → 空串哨兵区分"空内容"与"无内容"，空文件可正常保存。
- **编辑器"已保存"闩锁** → 保存后的增量编辑不再静默丢失（退出拦截 + 草稿回写以已提交版本为基准）。

### 修复 · Fixed
- AI：结束帧正文截断（Gemini 尾字丢失）/ SSE 尾帧丢失 / 流式读超时挂死 / 非 JSON 体裸逃逸 / 错误只报状态码 → 五项全修。
- 设置：`Infinity`/`NaN` 一处坏值丢全部设置 → 有限性守卫；保存失败横幅双向滞留 → 状态变化必通知；启动初期设置被旧快照覆盖 → 世代号守卫。
- GitHub：改默认分支后全进程用旧值 / 裸写路径丢 force 语义 / 直接写后 30s 读旧值 / 批量提交可清空仓库（base_tree 空即中止）/ 星标状态说谎。
- 生命周期：登录收尾顺序颠倒破坏好会话 → 调序；僵尸账号+令牌残留 → 按 id 精确清理；AI 切号串会话 → 按账号 key 化；切号残留仓库上下文 → 即清。
- 编辑器：强制覆盖"确认 A 顶掉 B" → 覆盖前复核远端；提交成功误报失败 → 保存态先落定；放弃修改与草稿竞态；"远端已删除"误导预览。

### 界面 · UI
- 新建文件"先关框后校验"丢全部输入 → 对话框内实时校验 + 按钮禁用。
- AI 历史会话删除补二次确认（对齐全仓惯例，6 语言）。
- 发送失败回填输入框原文；星标/分支三处挂载防护。

### 质量 · Quality
- 契约回归测试 +4 组（Infinity 回落 / 世代交错 / Gemini 结束帧 / OpenAI 结束帧）。
- 五项静态门禁 0 违规（分层 / UI 令牌 / 性能 / i18n / 版本一致性）。

完整说明见 `release_notes/v9.5.0.md`。

## v9.1.0（2026-10-15 · 正式版）

> **主题**：9.0 后的用户体验/架构收口（间距 Token/通知总线/AI 流式/下载隔离/删死代码）。

### 修复 · Fixed
- 下载管理器单任务崩溃染红整页 → ErrorWidget.builder 隔离
- AI 聊天接上 SSE 真流式（打字机 + 停止按钮）
- 设置页未持久化时全展开（首次进入不再挨个点）
- 27 个 surface 文件裸 SizedBox(8/12/16/24) → OgLSpace token 统一
- AI 页面 9 处裸 EdgeInsets → token 统一
- 下载通知 5 文件 5 套实现 → 1 个 OgLDownloadNotice 统一

### 变更 · Changed
- 删死代码 `lib/domain/sys/`（sys_access + sys_info + sys_platform_io = 1080 行零调用）
- 补 i18n 漏键 `copyFailed`（6 语言）
- 自研网络层 2898 行**保持**（重试/超时/DNS/Mirror/Range 完整）——换 dio/http/chopper 破坏 web 隔离与契约

完整说明见 `release_notes/v9.1.0.md`。

## v9.0.0（2026-10-15 · 正式版）

> **主题**：十轮迭代打磨，达商业级成品。

### 新增 · Added
- 下载管理：重试全部失败 + 撤销移除。
- 统计图表：5K 极客风 + 性能 3.7× + 算法加固。
- 核心域测试约 1974 条断言。

### 修复 · Fixed
- AI 配置 HTTP 端点崩溃 → 即时校验 + 明文提示（**修复前**：直接崩）。
- AI 底层 TLS/密钥错误静默穿透 → 可见（**修复前**：毫无反应）。
- 下载完成卡「下载中」→ 兜底（**修复前**：状态永停）。
- **Web 版自 v7.x 起首次稳定构建**（http 依赖 / isolate_manager / window_manager 平台隔离）。
- 用户故障无日志 → 统一接入日志系统。
- 剪贴板 Web 端静默失效 → 统一封装。

完整说明见 `release_notes/v9.0.0.md`。

## v8.6.0（2026-10-15 · 正式版）

> **主题**：生产日志完整化 · 测试覆盖补齐 · Web 分支稳定。

### 新增 · Added
- 核心域测试 +55 条：AI 协议适配（parseStreamChunk/parseReply/buildChat）、
  下载幂等入队、认证状态机。总量约 1974 条断言。

### 修复 · Fixed
- 用户故障无日志可查（**修复前**：debugPrint 吞错 release 下剥离 → **修复后**：接入统一日志）。
- 3 个 flaky 测试（网络时序/跨午夜墙钟/视口不还原）→ 稳定。
- Web 构建反复失败（平台差异文件被 main 覆盖）→ 明确差异清单、稳定通过。

完整说明见 `release_notes/v8.6.0.md`。

## v8.5.0（2026-10-15 · 正式版）

> **主题**：AI 配置可用性 · 下载管理增强 · Web 分支编译修通 · 统计图表 5K 极客风。

### 新增 · Added

- **下载管理**：一键「重试全部失败」；移除后可「撤销移除」。
- **统计图表**：5K 分辨率极客风，横轴 10 / 纵轴 10 刻度，曲线单调三次平滑，
  渲染性能 3.7×。

### 修复 · Fixed

- AI 配置填 `http://` 端点不再崩溃，改为即时校验收据 + 明文知情提示（**修复前**：直接崩）。
- AI 底层 TLS 握手 / 密钥存储异常不再静默穿透（**修复前**：点了没反应）。
- 下载完成却卡在「下载中」（完整性校验抛错）已兜底（**修复前**：状态永停）。
- **Web 版首次构建成功**：补 `http` 依赖 + `isolate_manager` 覆盖 + `window_manager` 平台隔离
  （**修复前**：Web 分支自 v7.x 起持续失败）。
- 剪贴板残留的静默失效点统一封装（**修复前**：Web 端复制无声失败）。

完整说明见 `release_notes/v8.5.0.md`。

## v8.2.0（2026-10-13 · 正式版）

> **主题**：AI 助手接入 · 主页导航重构 · 设置页两级层级 · 下载中心直达与 32 线程。

### 新增 · Added

- **AI 助手**：多轮对话 + 三协议（OpenAI/Claude/Gemini）+ 工具调用；密钥走安全存储；
  AI 操作永久落盘（审计）；回复纯文本渲染（不用 markdown）。

- **主页导航重构**：底栏 / 导航轨改为「仓库 · 搜索 · AI · 个人 · 设置」五格；
  **设置从「个人」页底的二次点击提升为一级入口**（高频页少点一次）。

- **设置页两级层级**：第一层进入式分类 → 第二层折叠式分组。

- **下载中心直达**：下载入队后 SnackBar 带「查看下载」动作，可一键跳到下载中心。

- **AI 能力位**：新增 `surface.hasAi`，界面按「是否已启用 AI」决定入口是否出现，
  不再进页面才发现是空壳。

### 变更 · Changed

- **下载并发档位**：1 / 2 / 4 / 8 → 增加 **16 / 32**（分片数仍受文件大小约束，
  小文件自动回退单连接）。

- 通知中心标题显示**未读计数**（`通知 (N)`）。

- **协议 / 法律 / 隐私文本 UTF-8 字符化**：正文以 `§` 编号、`·` 引条目、`※` 起声明、
  `───` 作分隔呈现，**去除 markdown 观感**；六语言（zh / zh-TW / en / de / fr / ru）
  结构与编号一致；渲染统一走纯文本组件。

### 修复 · Fixed

#### AI 配置 HTTP 端点崩溃
- 修复前：在 AI 设置里填以 `http://` 开头的端点，应用弹未捕获异常并崩溃。
- 修复后：HTTP 与 HTTPS 端点都能填、能保存；协议差异只以提示告知，不再闪退。

#### 下载文件不进 ogl 目录
- 修复前：授权「使用 ogl 目录」之后，完成的下载仍然只在应用私有目录里，
  在 ogl 目录看不到任何文件，像"授权没生效"。
- 修复后：落盘位置跟随存储裁决——公共目录档**直接写进用户可见的 ogl 目录**，
  下完即可见；授权前的下载保持原位置不变。

#### 同一附件第二次下载失败
- 修复前：同一条附件「下载 → 移除 → 再下载」，第二次没有反应，也不进下载中心。
- 修复后：重新入队前先清理库内旧任务记录，第二次、第三次下载都能正常开始。

#### 悬浮按钮遮住列表内容
- 修复前：主页 / 仓库页的悬浮按钮压住列表最后一行，要手动多滚一下才看全。
- 修复后：下滑时按钮**自动收边**（只露约 1/4），轻点即弹回，上滑自动展开；
  距底部半屏内也会主动让位。

#### 剪贴板在部分场景静默失效
- 修复前：外链打开失败时的"复制链接"兜底、下载管理里的"复制路径"、关于页的
  "复制"等十余处各自直接调平台剪贴板；Web 端无用户手势时会静默失败且**不提示**。
- 修复后：全部走统一封装 `ogLCopyText`（Web 端走浏览器剪贴板 API 并降级提示），
  失败不再无声无息。

#### 提示条样式与语气不统一
- 修复前：各页面自己拼 SnackBar——定位（悬浮/贴底）、配色、成功与失败看起来一样。
- 修复后：全部收敛到 `OgLNotifier`（success / info / warning 三种语气），
  样式只有一处定义，失败用 error 配色。

#### 通知横幅停留过短 / 下载横幅不收回
- 修复前：下载入队横幅一闪而过，来不及点到「查看下载」。
- 修复后：带动作的横幅停留 **8 秒**，留出操作时间。

#### 保存失败提示被埋在页面中部
- 修复前：设置保存失败的红条出现在分组列表中段，滚动时容易错过。
- 修复后：红条**紧贴标题栏下方**（`AnimatedSize` 平滑展开），与内容视觉断开。

#### 设置页两级留白 / 行密度不一致
- 修复前：进入分区页后卡片比主页宽一圈；两层行的箭头大小与内边距都不同，
  像两个应用。
- 修复后：两层统一边距与行高，箭头尺寸一致；图标风格统一为 outlined。

#### 设置页折叠组进入即收起
- 修复前：进入分区页先看到一张收起的卡，还要再点一次才能见内容。
- 修复后：分区页**进入即展开**，直接看到全部条目。

#### 部分文字不随系统字号缩放
- 修复前：启动拒绝页标题等硬编码字号，用户把系统字号调大后纹丝不动。
- 修复后：改用主题文字样式（TextTheme），跟随系统缩放。

### 其它

- **CI 新增格式护栏**：`dart format --set-exit-if-changed lib test` 与静态分析同跑，
  防止大面积空白漂移混进评审。
- 新增 `test/surface/notifier_test.dart`、`test/surface/settings_collapse_test.dart`。
- `docs/fonts.md`：说明当前**无自定义字体、无需 CDN 加速**，并保留将来接入
  Noto Sans CJK / JetBrains Mono 的镜像方案。
- `docs/5layer-audit-todo.md`：五层架构 + 兼容性 + 错误捕获的审计待办清单。

完整说明见 `release_notes/v8.2.0.md`。

## v8.0.0（2026-10-12 · 正式版）

> **主题**：下载 / DNS 治本 · 设置页重做 · 悬浮元素让路 · 动画泄漏治理与分级预加载。

### 修复 · Fixed
- **下载**：分片不可用时回退单连接（此前小文件必然"下载失败"）；分片响应校验 `Content-Range`；
  分片成品按显式 `path` 读回；暂停 / 重试后进度与失败原因归零；dispose 后回调不再改状态。
- **DNS**：「DoH 优先」此前是死代码（从未接到解析链）——现真正生效；换服务商后缓存作废；
  非法地址入口规格化；AAAA 补零；缓存淘汰语义与注释对齐；自检可见"已回退系统解析"。
- **设置**：`kOgLSettingsRowPadding` 类型写成 `EdgeInsets` 却赋值 `EdgeInsetsDirectional`（9 条编译错误、整包构建失败）——已修正。
- **动画**：`OgLReveal` 整个类没有 `dispose()`（错峰闭包拖着已卸载 State）；
  每个路由每帧泄漏 2 个 `CurvedAnimation`（死监听者永不摘除）——均已修复，观感零变化。

### 新增 · Added
- **分级动画预加载**：按动效档位（0 不预加载 / 1 仅当前页 / 2 全屏为主且额度最大 /
  3 当前 + 下一子层级），有数量与内存上限、空闲调度、可取消。
- **悬浮元素滚动感知**（`ScrollAwareAction`）：下滑收边只露 1/4、点击弹出、上滑自动弹回、
  近底部半屏收起；覆盖首页 / 仓库页 4 个标签页 / 发布页共 7 处。

### 变更 · Changed
- **设置页重新设计**：5 个可折叠分组 + 5 种统一行型 + 收起时当前值摘要 + 危险区视觉隔离；
  色板与分段按钮收进选择弹窗。功能一项未少（逐键对照）。

完整说明见 `release_notes/v8.0.0.md`。

## v7.4.0（2026-10-11 · 正式版）

> **主题**：仓库文件操作接入文件操作服务 + 遗留缺陷修复批。

### 修复 · Fixed
- **仓库页文件操作接入 `RepoFileService`**：新建 / 删除 / 重命名与目录递归删除改调服务 —— 路径经服务规则校验、单文件写入带**文件级基线**（create 不覆盖、delete 不删错版本）；目录删除由服务自动分批（≤200/批、基线链式推进），页面级 200 文件硬上限移除；整体成败以 `result.ok` 判定，失败按 `result.items` 逐项提示（同一文案只报一次）。
- **目录删除 / 重命名增加进行中进度**：服务的 `onProgress` 回调更新代码标签顶部状态行（阶段 + 已处理 / 总数），进行中不再整页转圈、把内容藏起来。
- **写后失效只读缓存**：`RepoFileService` 每个写操作在条目真正落定后调用 `GhApi.invalidateReadCache()`，随后的读取回源（失效失败不改变「写入已成功」的事实，只记诊断）。
- 设置层语言白名单与展示层对齐：`languageCodes` 由 15 种收敛为 6 种（简中 / 繁中 / 英 / 德 / 法 / 俄），注释同步说明与 `OgLI18n.locales`、`assets/i18n/` 目录、pubspec 声明三处一致。
- 删除文件预览枚举中的死值 `OgLPreviewKind.text`：文本文件仍判定为 `unknown`（既有行为由测试锁定），`file_preview_page` 的对应分支一并删除。
- 删除文件图标里不可达的 `readme.md` / `changelog.md` 分支（`md` 扩展名在扩展名分支已先返回）。
- 加速地址校验补主机名检查：`https://`（无主机）不再放行 —— 它会把「加速已开」伪装成直连（新增键 `accelUrlHost`，6 语言）。
- 下载文件名净化：Windows 保留名改按**第一个点之前**的部分判定，`aux.tar.gz` 等多扩展名不再绕过（补测试用例）。
- 登录令牌格式提示补 `ghs_` / `ghr_` 前缀（6 语言）：提示与实际接受的 6 种前缀一致。
- Gist 详情：`raw` 回退拉全文失败时把「可能被截断」如实带进 `_GistFile.truncated`，卡片标注（新增键 `truncatedWarning`，6 语言），不再把残缺内容当完整展示。
- 通知中心：相同的 `title + detail` **先查去重再落盘**，重复条目不再写入磁盘日志。
- `OgLNoticeDelivery` 注明接线状态：当前调用点均走默认 `auto`，参数尚未接线（逻辑未变）。
- 关于页依赖许可清单补 `flutter_svg` / `window_manager` / `saf_util` / `saf_stream` / `flutter_local_notifications` / `yaml` 六项，顺序声明改为与 `pubspec.yaml` 的 `dependencies` 逐项一致。
- 登录页清理：删除数字进度的死注释、`finally` 中冗余的未挂载分支；`_openOnboarding` 改用已取得的 `navigator`。
- 动效注释与实现对齐：起始缩放「仅拉满档 < 1」改为「标准档起 < 1：0.99 → 0.975」。

### 变更 · Changed
- 版本号：`pubspec.yaml` 7.3.1+70310 → **7.4.0+70400**；`kOgLAppVersion` 同步升至 7.4.0。

## v7.3.1（2026-10-11 · 正式版）

> **主题**：界面细节修复批 —— 弹层闭场动效 / 表单返回保护 / 动效与无障碍覆盖 / 多语言文案。

### 修复 · Fixed
- 底部弹层（`ogLShowSheet`）的闭场动画不再被掐断：不再自建动画控制器（关闭同帧释放会取消出场动画），改用 `sheetAnimationStyle` 按档位给时长。
- 新建发布 / 仓库 / 议题 / Gist / 工作流参数与仓库设置六个表单：输入后返回键即时走「放弃确认」，不再把已输入的内容当作「未修改」直接放行。
- 代码编辑器恢复草稿不再覆盖用户已输入的内容（异步读取期间已开始编辑时丢弃旧草稿）。
- 关于页赞助入口打不开浏览器时：先复制仓库链接，再提示「已复制」（此前只提示、不复制）。
- 设置页 9 处 + 关于页 2 处散装 `showSnackBar` 收敛到 `OgLNotifier`；「取消文件夹授权」改告警语气、「下载并发数」改成功语气。

### 变更 · Changed
- 设置页日志区改为可折叠（`ExpansionTile`，默认收起）；账户行、日志空态 / 正文补 `AnimatedSize` 过渡，加速通道增删沿用外层 `AnimatedSize`。
- 无障碍：设置页分组标题补 `Semantics(header: true)`；滑块行加 `MergeSemantics`；色板与加速通道声明 `inMutuallyExclusiveGroup`。
- 动效档位注释与实现对齐（标准档含 0.99 轻微缩放）；「减少动效」说明更正为「手动强制 / 档位静默」。
- 多语言：冲突提示 8 键补 zh_TW / de / fr / ru；`onboardingLicenseHighlights` 补 de / fr / ru；6 语言清除指向已删内置通道的表述；德文（`Protokolldatei` / `Projektinformationen`）与俄文（登录 / 公开 / 文件访问）拼写修正。
- `kOgLAppVersion` 与 pubspec 同步升至 7.3.1。

## v7.3.0（2026-10-10 · 正式版）

> **主题**：新增文件操作服务（移动 / 复制 / 批量）+ 传输层健全 + 界面与交互修复。

### 新增 · Added
- **文件操作服务**（`RepoFileService`）：统一 create / delete / rename(=move) / copy / batchDelete / batchMove / batchCopy；支持文本与二进制（Blobs API / sha 引用，不限 1 MB）；目录操作递归展开；>200 文件自动分批 + 基线链式推进 + 进度回调 + 取消；目标已存在拒绝覆盖。
- **下载错误分类**（`IxDownloadError`）：网络 / 磁盘 / 校验 / 取消 / 不支持 / 需认证——取代裸字符串。
- 下载任务幂等入队；clearFinished 补清泄漏辅助表；completed 双入口去重。
- 文件写操作（删除/批量/重命名）增加进行中状态反馈。

### 变更 · Changed
- `net_transport.dart` 默认可重试方法移除 PUT / DELETE（非幂等操作）。
- `types.dart` 的 9 条 export 路径修正（此前解析到仓库外）。
- `IxPresign` 补传令牌（此前漏传导致签名族加速静默失效）。
- 法律文案清除指向已删内置通道的表述（6 语言）。
- `kOgLAppVersion` 对齐 pubspec 版本号。
- 冲突错误文案改为用户可读（不再显示枚举名）。
- 严重告警弹窗不可被误关。

### 修复 · Fixed
- 文件预览页重试成功后不再卡在错误页。
- 工作流表单快速切换不再错配参数。
- 下载管理页控制器释放后不再触发通知。
- 返回键快速连按不再穿透多层。
- `atHome` 判定收窄：引导/登录阶段不再触发「再按一次退出」。
- 重命名不再使用缓存旧内容覆盖新路径。
- 新建文件增加防重复写入保护。

## v7.2.2（2026-10-09 · 正式版）

> **主题**：修复一轮界面与交互审查发现的问题。

### 修复 · Fixed
- 打开含代码文件的 Gist 详情页会触发布局断言（编辑器组件在无界高度的列表里）；
  现为每个文件给定确定高度。
- 代码编辑器内打字时，键盘会遮住编辑区底部（自绘输入未纳入键盘避让判定）。
- 首页与仓库页的「下拉刷新 / 加载更多 / 切换筛选」存在竞态：快速操作会丢失第一页、
  重复条目或显示与筛选不符的数据。相关列表改为排队刷新或丢弃过期响应。
- 代码编辑器退出时无条件回写草稿：「保存成功」或「放弃修改」后草稿仍会残留，
  与操作语义相反。现在这两种情况不再回写，「放弃」会真正删除草稿。
- 文件预览页加载失败后，「重试」成功仍显示错误页（错误状态未复位）。
- 手动触发工作流时快速切换目标，表单参数可能与所选工作流不符（请求无序）。
- 搜索与仓库页在控制器释放后仍可能收到通知（debug 下触发断言）。
- 新建 Gist / 议题 / 仓库 / 发布 / 工作流参数 / 仓库设置等表单，
  返回时不再静默丢弃已输入内容（与代码编辑器一致的「放弃确认」）。
- 删除仓库后，首页与搜索结果不再保留已删除的仓库。
- 授予「所有文件访问」权限后，提示文案误显示为 DNS 相关（文案串用）。
- 二进制 / 图片文件可经「打开方式 → 编辑器」进入并保存乱码内容覆盖原文件；
  现按文件类型禁用该入口。
- 设置页账户行在页面重建时反复闪「读取中」（Future 在 build 中创建）。
- 法律文本页快速切换语言时，正文可能与所选语言不一致。
- 布局与动效：加速范围开关组与标题错位、条件内容无过渡、弹窗与折叠动画未接动效档位、
  协议弹窗勾选框位置、错误卡片边距、若干对齐与触控目标过小、
  两处缺失的无障碍语义、关于页硬编码颜色、字号滑块整页重建等。

## v7.2.1（2026-10-09 · 正式版）

> **主题**：调整平台架构兼容性。

### 变更 · Changed
- **Web 与原生拆分为两个独立系统**：本分支为原生版，只构建 Android / Windows / Linux；
  Web 在独立分支维护，产物发布到该分支的 `app/<版本数字>/`，不产生 GitHub Release。

本项目各版本的变更记录，新版本在前。

## v7.0.0（2026-10-08 · 正式版）

> **主题**：新增 **Web 版**（浏览器），并把它作为正式平台之一。
> 桌面与移动端的代码通过条件导入收敛平台差异，Web 侧另有一套实现。
> 同时新增「按版本发布到 `app/`」的部署结构。

### 新增 · Added
- **Web 版（PWA）**：可在浏览器中使用，并可「添加到桌面 / 主屏幕」作为独立窗口打开。
  - 入口：`app/index.html` 用 iframe 包裹**当前版本**，地址长期不变；
    各版本产物放在 `app/v<版本号去点>/`（如 `v700`），`app/versions.json` 为清单。
  - `web/index.html` 手写入口页，含 PWA 清单与 `apple-*` 标签。
  - 图标与三端同源：由 `assets/icon/ogl_icon.svg` 光栅化生成。
- **「添加到桌面」提示**：Chromium（含 macOS）走标准安装流程，每次打开提示一次；
  **iOS Safari 不支持 `beforeinstallprompt`**（平台限制），因此 iOS 上给出
  「共享 → 添加到主屏幕」的引导。已安装（standalone）时不再提示。
  可在 设置 → Web 版 关闭该提示。
- **Web 首次打开对话框**：提示可配置加速服务，并写明「不配置也能正常使用，
  只是下载走直连」，入口指向 设置 → 网络 → 加速。
- **`tool/web_publish.py`**：把构建产物按版本发布到 `app/`，并重写入口页与清单。

### 变更 · Changed
- **平台差异改用条件导入收敛**：此前 18 个文件直接 `import 'dart:io'`，
  浏览器里没有该库。现改为
  `import 'x_io.dart' if (dart.library.js_interop) 'x_web.dart';`，
  能用 `kIsWeb` + `defaultTargetPlatform` 解决的一律不再引入 `dart:io`。
- 新增依赖 `http: ^1.2.2`（自带浏览器实现，供 Web 传输层使用）。
- `web.yml` 在 `main` 与 `web` 两条分支上构建 Web；其成败**不阻塞**五平台发布。

### Web 侧的平台实现（与桌面行为不同的部分，均如实标注）
- **磁盘**：浏览器没有文件系统。键值存储走 `localStorage`，文件类存储为**会话内有效**
  的内存表；`SecureDiskVault`（令牌保险库）在 Web 上**仅内存持有**，刷新需重新登录 ——
  这是为了避免把长期令牌明文留在 `localStorage`。
- **网络**：传输层改用 `BrowserClient`。**自定义 DNS 与 DoH 在 Web 上不可用**
  （浏览器不提供裸 socket，也无法把解析结果回灌给连接），设置页会如实显示这一点。
- **网络自检**：Web 上为「有限自检」，只测 HTTP 可达性，不含 DNS / TCP / TLS 探测。
- **下载**：`background_downloader` 没有 Web 实现，因此 Web 上的下载**交给浏览器**。
  由此暂停、续传、多连接分片、进度、文件大小、保存路径、成品 sha256 校验均**不可用**，
  界面与日志如实标注，不做假动作（例如「暂停」不会被伪装成已暂停）。
- **带 `Authorization` 头的下载在 Web 上会明确失败**（浏览器不允许页面设置跨域鉴权头），
  原因是能否成功取决于目标站点是否允许跨域，这里不猜。
- **预签名（第一跳 302 解析）在 Web 上不可用**：`fetch` 读不到跨域重定向的 `Location`。
  实现如实返回「解不出签名」，**不会**改成跟随重定向（那会绕过「令牌只用于第一跳」的设计）。
- **日志不落盘**：Web 上 `OgLLogFile.isEnabled == false`，保留浏览器控制台输出。

### 修复 · Fixed（沿用 v6.5.0 的一轮审查结论）
- 见 v6.5.0 小节：分页缓存丢 `Link` 头、SAF 二次下载不导出、探测期任务复活、
  完整性校验失败不删坏文件、SSRF 归一化、19 处文案取错语言分片等。

### 已知限制 · Known limitations
- Web 上不提供：自定义 DNS / DoH、多连接分片、后台下载与续传、下载进度与校验、
  导出到 SAF、TLS / DNS 级网络自检。
- iOS 只能按引导手动「添加到主屏幕」（Safari 不提供安装接口）。
- **`docs/ARCHITECTURE.md` 等 5 份被注释引用的文档仍不存在**（已逐处标注「以源码为准」）。
- **Linux 裸放安装包 3 / 6**：rpm（arm64）缺平台定义；AppImage 的 `ARCH`
  环境变量未被接受。三种包在 zip / 7z 里都齐全。
- macOS / iOS 原生应用自 v5.6.0 起弃用（Web 版在 iOS 浏览器上可用，但不是原生应用）。

## v6.5.0（2026-10-08 · 正式版）

> **主题**：修复一轮全量代码审查发现的问题。
> 审查用 4 个子代理并行覆盖加速链路、平台与底座、展示层、领域层与工具，
> 结论逐条经人工复核（`docs/NETWORK.md` 与 `release_notes/` 的措辞同期校准）。

### 修复 · Fixed（用户可感知）

- **README 仓库内图片在私有仓库必然 404**：`Image.network` 没有 headers 参数，
  无法携带令牌，而私有 raw 匿名访问返回 404。此前「私有 + 已知情接受」会
  走到该分支；现在私有仓库一律回退到 API 取字节（那条带令牌）。
- **仓库内图片跨仓库/分支串图**：`ReadmeView` 的字节缓存只以仓库内相对路径为键，
  `assets/logo.png` 这类同名文件在两个仓库间会命中同一份缓存。键改为
  `仓库@分支:路径`。
- **分页列表在缓存窗口内只显示第一页**：缓存命中时只回填响应体、`headers` 为空，
  而翻页依赖 `Link` 头。现在缓存条目连同 `link` 一起存储并在命中时回填。
- **同一文件第二次下载不再导出到 SAF**：导出去重表只在失败路径移除 id，
  成功导出后 id 常驻；而 taskId 由 url + 文件名派生，重复下载会命中同一条目。
- **自定义 DNS / DoH 开关对真实请求不生效**：`connectionFactory` 只在传输层
  构造时安装一次，而 DNS 模式的写入发生在模块注册之后。现在每次发送前按当前
  策略校正（模式变化才重装；切回系统 DNS 时把 factory 摘掉）。
- **登录页切换账号不清缓存**：只清仓库缓存的路径会留下 DNS 缓存与页面分页快照，
  多账号下是「用 B 账号看到 A 账号内容」的来源。现与「我的」页一致，清全部缓存
  （含页面级快照）。
- **版本常量 `kOgLAppVersion` 停在 `6.0.0`**，与 `pubspec.yaml` 相差三个小版本。
  该常量会写入日志与内核报告。已对齐。

### 修复 · Fixed（下载器与网络）

- **分片任务在探测期间被移除后会「复活」**：`_runRanged` 在 `await probe` 之后
  无条件写回快照。现在探测返回后先确认任务仍在，否则直接退出（也不会再落盘）。
- **任务表清理不完整**：`remove()` 与 `clearFinished()` 漏清 `_urlCandidates`、
  `_rangeConnections`、`_lastSample`、`_expectedSha256`、`_exportedToSaf`，
  造成会话级累积。现统一收口。
- **`dispose()` 不取消进行中的分片下载**：分片任务是 fire-and-forget，管理器
  回收后引擎仍在下载并调用已释放的通知器。现取消全部令牌并加 `_disposed` 守卫。
- **`ix_presign` 在 200 直链分支先 `drain()` 再注释说明「不能 drain」**：
  每个直链下载都会多跑一遍全量流量。已移除该 `drain`。
- **`isForbiddenHost` 存在绕过形式**：只识别点分十进制与 `fe80:` 前缀。
  现在先做归一化（整数形式的 IPv4、IPv4-mapped IPv6、去掉方括号与尾点），
  IPv6 段判断改为按位（`fc00::/7`、`fe80::/10`），并支持 `127.1` 这类缩写。
- **分片合并失败会留下半成品文件**：`finally` 只删分片，不删 `target`。
  现按契约在未成功合并时删除目标文件。
- **`abs()` 未拒绝绝对路径与空串**（注释称会拒绝）：`/etc/passwd` 会被静默
  剥掉前导斜杠塞进根目录。现显式拒绝。

### 修复 · Fixed（界面文案）

- **19 个界面文案取自错误的语言分片，显示为裸键名**：
  设置页 13 处、仓库页 2 处、关于页 4 处。取法已改到键实际所在的分片。
- **`previewSvg` / `previewUnknown` 两个键在 6 种语言里都不存在**（「打开方式」
  弹窗的 SVG 与未知类型条目显示裸键）。已补齐。
- 三处**硬编码中文**改为 i18n：Gist 详情页的「公开 / N 个文件」、议题列表的
  「N 条评论」、评论作者缺失时的「未知用户」（后者复用已有的 `common.unknown`）。

### 变更 · Changed（门禁与文档）

- **`i18n_scan.py` 的分类规则收紧**：`LOG_CONTEXT` 原含 `log\w*(`，
  该模式会命中 `AlertDialog(`、`showDialog(`、`catalog(` 与 `login(`，
  使对话框附近的用户可见文案被计为开发者日志。现改为只列精确的日志入口。
- `docs/NETWORK.md` 更正与代码不符的表述（原写传输层有「主机冷却 / DoH 回落」，
  实际不存在），并补上「加速适用范围」与 web 端 CORS 实测表。
- `docs/README.md` 补入 `NETWORK.md` 索引；文中路径改为可点击链接。
- 多处注释更正为与实现一致：`platform.dart` 的平台分派范围、
  `download_proxy.dart` / `readme_view.dart` / `file_preview_page.dart` 的
  私有仓库口径、`net_bridge.dart` 的模块描述、`ix_task.dart` 的 `auto` 语义、
  日志文件名格式、诊断中的并发数文案。
- 删除无引用的 `IoBootFileSystem`；对仅测试使用的 `ScriptedTransport` 与
  无调用方的 `DiskPaths` 加注说明。

### 已知限制 · Known limitations

- `docs/ARCHITECTURE.md`、`BOOT.md`、`CONSISTENCY.md`、`DURABILITY.md`、
  `NAMING.md` 被代码注释引用，但仓库中并不存在；引用未清理。
- **Action 运行日志不走加速**（直接请求 `api.github.com`），加速适用范围没有它。
- **web 端**：私有仓库的 raw 与「私有 + 加速」均不可用（浏览器预检会拦截
  `Authorization`，而 Release 附件的签名地址不带 CORS 头）。
- **Linux 裸放安装包 3 / 6**：rpm（arm64）缺平台定义；AppImage 的 `ARCH`
  环境变量未被接受。三种包在 zip / 7z 里都齐全。
- macOS / iOS 自 v5.6.0 起弃用。

## v6.4.3（未单独发布 · 内容并入 v6.5.0 / never shipped separately）

> **主题**：**删掉内置代理，只留自定义通道**；同时去掉一切静默降级。
>
> 这个项目的定位是本地工具：不收集数据、令牌不出设备。而「内置加速通道」
> 是一台由项目维护的代理服务器 —— 无论协议怎么写，它都在信任链上：
> 它知道你请求了什么文件，也能在签名地址的有效期内自行取走文件。
> 这与上面的定位冲突，因此移除。

### 新增 · Added
- **加速适用范围可逐项开关**（设置 → 网络 → 加速）：前缀式代理开放的端点有限，
  有的能转发 Release 附件却转发不了仓库内图片，"哪些资源加速"写死必然有人用不了。
  现在由用户指定，**只有 4 类**（清单来自代码，不凭印象添端点）：

  | 适用范围 | 资源 | 代码位置 |
  | --- | --- | --- |
  | Release 附件 | `release_detail_page.dart` | 签名族 |
  | Action 构建产物 | `action_run_page.dart` | 签名族 |
  | 仓库文件（下载与预览） | `surface_bridge.planRepoFileDownload`、`file_preview_page.dart` | raw 族 |
  | README 仓库内图片 | `repo_page.dart` | raw 族 |

  默认全开（与历史行为一致），可逐项关闭；全关也合法（等于不加速）。
  **Action 运行日志不走加速**，因此没有对应开关。
  各调用点只声明"我是哪一类"，是否加速统一由 `OgLSettings.accelPrefixesFor` 判定，
  避免同一资源出现两处不同结论。

### 移除 · Removed
- **内置加速通道**（`proxy.344977.xyz`）：通道列表不再包含任何内置项，
  `kOgLAccelBuiltinChannel` / `kOgLAccelBuiltinId` / `kOgLAccelBuiltinBaseUrls`
  一并删除。**要加速需自行添加通道地址**；不添加就一直走直连。
- **内置网络镜像**（`defaultMirrorChannels` 里的 ghproxy.net 换主机规则）：
  它们是"我们替你选的第三方代理"，同样予以清空。镜像机制本身保留但**当前不生效**。
- **降级回退**：`ogLAccelCandidates` 现在**至多返回一项** —— 加速就是
  `前缀 + 原址`，不加速就是原址，**不再垫一个直连候选**。
  此后不会出现「界面显示在加速、实际走的直连」这种谁也说不清的状态；
  失败就如实报错。
- 多前缀「优先级链」（前一个失败换下一个）随之删除：一个通道就是一个前缀。

### 变更 · Changed
- **协议升版 v3 → v4（需重新同意）**：`accelThirdPartyBody` 重写 ——
  删去「本应用提供/维护通道」的表述，明确「本应用不预置任何通道，也不提供
  代理服务」，并把「失败不静默回落直连」写进正文。
  内置通道专属的协议文本（`accelBuiltinBody` 等）与相关界面文案一并删除。
- 设置页：无通道时显示明确空态（本应用不提供通道，要加速需自备），
  删掉通道不再"回落"到别的通道，而是清空选中（那等于替你换了个代理）。
- `README` / `docs/USAGE.md` / `docs/NETWORK.md` 同步订正；
  `NETWORK.md` 补入 **web 端 CORS 实测表**（哪些路在浏览器上走得通）。

### 修复 · Fixed
- 设置页「添加自定义通道」的副标题此前是**硬编码中文**，未走 i18n；
  6 语言补齐 `accelAddHint`。
- `i18n_scan.py` 的失效豁免（`accel.dart` 的内置通道展示名）已清除，
  并记录其 UI/日志分类跨度过宽的已知盲区。

## v6.4.2（2026-10-07 · 正式版）

> **主题**：图标改由 `assets/icon` 统一生成，并修复两个自 v5.6.0 起存在的缺陷。
>
> 起因是「更新图标为 assets/icon 的，全平台自动适配」。查管线时发现：
> 声明与实际不一致。一个是**从来没跟过源图**，一个是**整张图是空的**。

### 修复 · Fixed
- **Windows 的 ICO 与 Linux 的 PNG 自 v5.6.0 起一直是空白图标**：
  `desktop_icon.render_rgba` 解析出的图层里存的是 `url(#bodyGrad)` 这样的引用串，
  而渐变表的键是 `bodyGrad`，查表写成 `grads.get(layer["fill"].strip())` ——
  **永远查不到**，于是每个图层都被 `continue` 跳过，输出是一张**全透明**的图。
  症状不是报错，而是一个看不见的图标；构建全程"成功"。
  - 修法：新增 `_resolve_paint()` 正确解析 `url(#id)` 引用，并顺带支持
    `#RRGGBB` 纯色（用同色双停靠点表示），避免源 SVG 换写法又静默变空。
  - **加守卫**：渲染结果若全透明则**直接抛错**，不允许再交出空白图。
- **Android 图标从来没有跟过源图**：`inject_platform_spec.py` 里是一段
  **硬编码的矢量前景**（盾牌 + 蓝色三角），与 `assets/icon/ogl_icon.svg`
  （深色多边形 + 金色双眼）不一致 —— 此前所称的「唯一事实来源」与实际不符。
  注释还指向一个早已删除的脚本。
  - 修法：删掉硬编码常量，新增 `tool/svg_vector.py` 把源 SVG **转成
    VectorDrawable**，Android 改为真实转换。
- **自适应图标纵向偏移 3%**：矢量居中只按 X 算了横向平移，Y 直接套用了同一个
  值。源图重心是 (256, 272)，于是图形在安全区里整体下移约 3%。已改为 X/Y 分别计算。

### 变更 · Changed
- **图标全平台统一从同一份 SVG 派生**（`assets/icon/ogl_icon.svg` 是唯一来源）：
  - **Android**：矢量 `VectorDrawable`（自适应前景收在安全区内 + 传统图标矢量
    放 `mipmap-anydpi/`），不再有手写 XML；
  - **Windows**：256 ICO；**Linux**：2048 PNG 母版（两者共用同一套光栅器）。
- 传统启动图标放在 `mipmap-anydpi/`：`anydpi` 的优先级高于具体密度，因此会
  盖过 `flutter create` 生成的五套模板 PNG —— 无需删除那些文件，也不会在
  API < 26 的设备上残留 Flutter 默认图标。
- `desktop_icon._parse_svg` 更名公开为 `parse_svg`：Android 的矢量转换也用它，
  两个平台必须从同一份解析结果出发，否则"同一个图标"会各处一个样。

### 新增 · Added
- `tool/svg_vector.py`：SVG → Android VectorDrawable（`polygon` + `linearGradient`，
  纯标准库；渐变按 SVG 的 `objectBoundingBox` 语义换算成 Android 的绝对坐标）。
- 注入器自检新增第 ⑬ 节「图标管线」，13 项断言：桌面渲染非空白且占比合理、
  全透明必须报错、矢量含真实几何与渐变、安全区生效、五个 Android 图标文件
  均写出、前景确实是源图转换（而非旧硬编码盾牌）。

## v6.4.1（2026-10-07 · 正式版）

> **主题**：私有仓库也可以加速了 —— 但必须先过一道**知情警告**。
>
> 上一版把私有仓库的 raw 一律排除在加速之外，理由是「raw 没有签名机制，
> 交给代理等于送令牌」。这个理由成立，但用户可能愿意承担这个风险换速度。
> 所以改为**把选择权还给用户**，并且让这个选择真的被看见。

### 新增 · Added
- **私有仓库加速的知情开关**（`accelPrivateRepoAccepted`，默认 `false`）：
  - 位于**设置 → 网络 → 加速通道**，与总开关同页；
  - **开启方向**必须先过警告弹窗，弹窗**强制展示 3 秒**后才可操作，按钮上
    显示剩余秒数（防手滑连点 —— 这是「令牌离开设备」的唯一一道闸门，
    滑过去就等于没有）；
  - **关闭方向不弹窗**，且语义是「不再询问**且**不再加速」，退回 API 直取。
    不留「别再问我、但照旧送令牌」这种选项 —— 那等于把一次性知情同意
    悄悄变成永久授权。
  - 弹窗文案讲清三件实测事实：私有 raw 匿名 404、必须带令牌；
    内置通道会**原样转发** Authorization 头给 GitHub（带令牌 200 / 不带 404）；
    令牌进入第三方服务器后其留存与用途不在本项目控制范围内。
- **`docs/NETWORK.md`**：全仓库网络连接清单。出口主机 × 资源类型 × 取法 ×
  公私差异 × 复现命令。文档里点到的每个符号都已逐条核验存在。

### 变更 · Changed
- `ogLAccelCandidates` 新增 `privateAccelAccepted`：私有 + raw 族只在用户
  知情接受后才加速；公开仓库不受影响。
- 私有 + 加速时**必须带令牌**：raw 匿名 404，代理没有令牌同样取不到。
  旧判据 `proxied || !repoPrivate` 在「私有 + 已接受」时给出空头，必然 404。
- 同步三处仍按「私有永不加速」写的旧判定：`SurfaceBridge.repoFileAccelerated`、
  预览页大文件面板的弹窗条件与提示文案条件。

### 修复 · Fixed
- 补回 `ogLAccelCandidates` 在上一笔提交中被误删的 `repoPrivate` 参数
  （改签名时替换掉了，函数体却仍在引用它）—— 曾导致 9 条构建腿与质量门全红。

## v6.4.0（2026-10-07 · 正式版）

> **主题**：把界面语言从 15 种收到 6 种 —— 保留全部键均有实际译文的那 6 种。
>
> 这不是一次功能更新。上一版埋着的隐患是：15 种语言里有 12 种的法律类正文
> 实际是**英文占位**（键在、目录在、值与英文一模一样）。用户切到自己的语言，
> 看到的仍是看不懂的法律说明。

### 新增 · Added
- **语言清单三处一致性成为 CI 门禁**：`OgLI18n.locales`（Dart 运行时清单）、
  `assets/i18n/` 下的目录、`pubspec.yaml` 的 `assets` 声明，三者必须逐项一致。
  `tool/i18n_scan.py --check` 新增该项检查（实测：故意加一个不存在的语言目录
   → 退出码 1）。
  这是本版在根因层面的防护：两边不同步会分别造成两种**方向相反**的故障 ——
  pubspec 多声明 → 构建期资源缺失直接失败；pubspec 少声明 → 构建通过、
  运行时该语言全是裸键名。后者尤其难查。

### 变更 · Changed
- **界面语言由 15 种收敛为 6 种**：`zh`（源）/ `zh_TW` / `en` / `de` / `fr` / `ru`。
  移除 `ja` `ko` `es` `pt` `ar` `hi` `th` `vi` `id` 九个语言目录，并同步
  `OgLI18n.locales`、`pubspec.yaml`、`README.md`、`docs/USAGE.md`、`docs/I18N.md`。
  **加回某个语种的前提是全部键都是真译文**，而不是把英文复制一遍。
- **仓库页选项卡按语种分别处理**（此前各语言混杂、口径不一）：
  - `zh` / `zh_TW`：`Code` / `Issues` / `Pull requests` / `Actions` 保留英文，
    其余（分支 / 提交 / 设置）照常用中文。
  - `de` / `fr` / `ru`：全部译为各自语言的对应词（如 `ru` 的 Issues → `Задачи`、
    `Releases` → `Релизы`）。此前这些语言里混着英文残留 —— 例如 `fr` 的
    `pulls` 仍是 `Pull Requests`、`releases` 仍是 `Releases`。
  - 测试 `test/surface/i18n_test.dart` 相应更新：语种数 15 → 6，并保留
    「中文语境下 GitHub 术语必须保持英文」这条断言。
- **繁体中文修正少量沿用大陆用法的词**：`Gist 片段` → `Gist 程式碼片段`、
  `我的加速` → `我的加速節點`（用词差异，非字形转换）。

### 修复 · Fixed
- **`OgLProjectInfo.licenseUrl` 仍指向 AGPL-3.0**：v6.3.0 换了许可，标识
  （`licenseId`）与名称（`licenseName`）都改了，**地址漏改**，还指向
  `www.gnu.org/licenses/agpl-3.0.html`。该常量目前无引用（死常量），但一旦将来
  有人用它生成「查看许可」链接，就会把用户送到一份**与实际许可无关**的全文。
  已改为 `https://www.apache.org/licenses/LICENSE-2.0`。
- **私有仓库大文件预览「用了 raw 却不带令牌」**（必然失败且被误报）：
  预览超过 1 MB 的图片时若改用 raw 链接，代码里写成
  `headers: proxied || !repoPrivate ? null : const <String, String>{}` ——
  注释说「未走代理且私有仓库才带认证头」，实际给的是**空 map**，一个头都没带。
  私有仓库必然 404，而界面把结果显示成「文件过大，无法在内置预览中加载」，
  把**认证失败**误报成**文件过大**。现在真的去取一步令牌
  （`downloadAuthHeaders`）；走代理时依旧一律不带（把令牌交给代理等于送令牌）。
- **私有仓库被「加速已开启 → 不弹窗」规则误伤**：raw 族的加速门槛本就是
  「内置通道 + 公开仓库」，**私有仓库的 raw 永远不加速**。但旧代码只要检测到
  加速开关开着就不弹窗、直接走 raw，于是私有仓库用户什么都看不到就掉进上面
  那个必然失败的分支。现已显式排除私有仓库，让它照常弹窗。
- **私有仓库的音频「播放」按钮点了必然失败**：该按钮把 raw 地址交给**系统
  播放器**，而系统播放器没有本应用的令牌，私有仓库一律 404。私有仓库现在只给
  「下载」（走本应用传输层，带认证）。
- **法律全文弹窗写死 `height: 460`**：小屏、大字体或横屏下会超出 AlertDialog
  可用高度而溢出。改为按视口比例给上限（`MediaQuery.sizeOf(context).height * 0.6`）。
- 新增键 `common.previewLoadFailed`，用于把「加载失败」与「文件过大」区分开 ——
  超过 1 MB 已有专门的面板处理，走到 `errorBuilder` 说明是认证 / 限流 / 网络问题，
  说成「文件过大」会让人往错误方向排查。该键已补齐 6 语言。

### 已知限制 · Known limitations
- **音频不做内置播放**：Contents API 对超过 1 MB 的文件不返回内容，音频必然超限。
  预览页对公开仓库给「播放」（交系统播放器），私有仓库给「下载」。
- **Linux 裸放安装包仍缺失**：rpm（arm64）因 Ubuntu 的 rpm 缺少 aarch64 平台
  定义、无法在 x86_64 宿主上交叉构建；两个 AppImage 因 appimagetool 未接受到
  `ARCH` 环境变量而退出码 1。三种包在 zip / 7z 里都齐全，功能上不缺，
  只是未裸放直传。
- **私有仓库的 raw 内容无法走加速**（README 仓库内图片、仓库文件）：`raw` 端点
  没有签名机制，交给代理等于送令牌。这是硬约束，不是取舍。
- macOS / iOS 自 v5.6.0 起弃用。

## v6.3.0（2026-10-06 · 正式版）

### 变更 · Changed
- **许可证从 GNU AGPL-3.0 更换为 Apache License 2.0**：
  - 全文替换 `LICENSE`；新增 `NOTICE`（Apache-2.0 第 4(d) 条要求）。
  - 两者均已加入 `pubspec.yaml` 的 `resources`，**随构建产物分发**。
    此前 AGPL 全文只存在于源码仓库，构建产物中**没有**，严格说不满足
    「随分发提供许可副本」的要求 —— 本次一并修正。
  - 应用内「开源许可」条目可点开查看**许可全文**（可选中复制）。
  - 同步更新：`README` / `docs/USAGE.md` / `tool/linux_packages.py` 的包元数据 /
    `OgLProjectInfo` / 15 语言界面文案（`AGPL-3.0` → `Apache-2.0`，免责条款
    引用由第 15、16 条改为第 7、8 条）。
  - **尽调结论**：仓库仅一名贡献者（可单方更换许可）；18 个依赖全部为
    BSD-3 / MIT / Apache-2.0，**无 GPL/AGPL 等传染性许可**，更换后无冲突。
  - ⚠️ 影响：Apache-2.0 **不要求**衍生作品开源（AGPL 强著佐权、且网络使用
    即触发源码披露义务）。这是一次许可政策的**放宽**。
- **隐私与加速说明定性为「说明性声明」**：新增定性段落置于引导页法律页、
  设置页法律文本页、加速说明弹窗的**最前面** ——
  「本文是说明性声明，不是法律协议，不产生法律效力，开发者不因本文承担任何
  责任。本应用唯一具有法律效力的文件是随程序提供的 Apache License 2.0。」
  条款内容未动，仅调整字样（协议→说明、承诺→实际做法）。
- 同步修正三处**措辞硬冲突**：`licenseIntro` 原写「第二部分是**保证**」、
  `accelLangNote` 原写「仅中文译本**具有法律效力**」，均与「本文不产生法律
  效力」直接矛盾；现统一为「中文为**原始表述**，其他语言仅供理解参考」。

### 移除 · Removed
- 设置页 `_logout`：被「我的」页的账号移除功能取代的**重复实现**，
  删除后账号注销统一走 `SurfaceBridge.forgetAccount`。
  （该重复实现还掩盖了一次**功能退化**：v4.4.0 曾要求「切换/移除账号时清空
  全部缓存」，后来在「我的」页退化成了只清仓库缓存，会留下 DNS 缓存与
  页面分页快照，多账号下造成串台。已恢复。）

### 修复 · Fixed
- **「捐赠一颗心」功能从未接线**：实现完整、README 也一直承诺，但界面上没有
  入口，靠 `// ignore: unused_element` 压着 `analyze`。已在设置页补上入口，
  并移除 3 处 ignore 注释。

## v6.3.0（2026-10-06 · 正式版）

> **主题**：无障碍补全 + 恢复 UI 截屏矩阵 + 消除两套「可见性」定义。
> 本版**没有新增功能**，是把前两版欠的工程质量补齐 —— 尤其是两处
> 结论相反且未经验证一致的定义分叉。

### 新增 · Added
- **无障碍语义标注（4 处）**：此前全项目 `Semantics` 为 **0**。50 个图标按钮虽都有
  `tooltip`（Flutter 会自动取作语义标签），但**自定义可点击区域**没有任何语义标注，
  屏幕阅读器只能念出"按钮"，用户不知道点了会怎样。
  - 标题栏窗口控件（最小化 / 最大化 / 关闭）→ `Semantics(button: true, label: …)`
  - 代码配色色板 → `Semantics(button: true, selected: …, label: 颜色 #rrggbb)`
  - 通知开关行 → `Semantics(toggled: …, button: true, label: 消息内容)`
  - 仓库页分支选择条 → `Semantics(button: true, label: 选择分支)`
  - 文案 4 键 × 15 语言。
- **恢复 UI 截屏矩阵**：从 **2 张样本**扩回 **26 张**（5 页面 × 亮/暗 × 横/竖 = 20，
  再加 3 平台 × 亮/暗的首页 = 6）。此前退化成冒烟测试后，UI 改动**无法自动发现
  视觉回归**。

### 变更 · Changed
- **「落盘可见性」统一成一套判定**。此前有两处定义：
  - `OgLStoragePlan.userVisible`：`mode != internal`（按**档位**）
  - `OgLAppDirs.isUserVisible`：`tier ∈ {public, desktop}`（按**路径分级**）

  两者在「桌面文档目录不可写、最终落到应用支持目录」时给出**相反结论**。
  界面接的是前者、测试锁的是后者，**两者的一致性未被验证过**。
  现统一成路径分级（唯一来源），SAF 档作为例外单列（用户授权过就可见）。
  新增测试把「无论什么档位，可见性都等于按路径分级的结论」钉成回归。

- **`OgLAppDirs.categoryFolder` 补上 `artifact` 映射**。此前漏了 Action 构建产物，
  一旦被用到会**静默落到 `other/`** —— 用户看不到任何异常，只是分类目录不对。
  补上映射，并新增测试把底座与中枢两份映射**逐枚举比对**（新增分类漏改一侧立刻红灯）。
  死代码转为防漂移护栏。

### 修复 · Fixed
- **`window_windows.dart` 缩进损坏**：第 27/29/30 行等顶格，Linux 同位置正常。
  应是 v6.0.1 删除注入脚本那次重构的残留。
- **`app_dirs.dart` 注释与代码矛盾**：`_resolveRoot()` ② 档注释原说应用外部目录
  「文件管理器可见」，而 `isUserVisible()` 明确判为**不可见**（Android 11+ 隐藏
  `Android/data/`）。注释会误导后续维护，已改为准确描述并说明为何仍选它作退路。
- **`appTitle` 三份字面量重复**（windows / linux / macos）：值上收到
  `window_capability.dart` 的 `kOgLAppTitle`，各平台保留同名常量指向它
  （不删符号），消除标题悄悄分叉的可能。

### 已知限制 · Known limitations
- **音频不做内置播放**：Contents API 对超过 1 MB 的文件不返回内容，音频必然超限。
  预览页给出「下载」动作，之后可在下载管理页交给系统播放器。
- **Linux 裸放安装包仅 3 / 6**：deb（amd64 / arm64）与 rpm（x86_64）已产出；
  rpm（arm64）因 Ubuntu 的 rpm 缺少 aarch64 平台定义、无法在 x86_64 宿主上交叉构建；
  两个 AppImage 因 appimagetool 未接受到 `ARCH` 环境变量而退出码 1。
  三种包在 zip / 7z 里都齐全，功能不缺，只是未裸放直传。详见「产物」一节。
- **14 种语言的加速协议文本仍为旧版**（zh 已改，键集合未变故门禁通过）。
  法律 / 隐私文本在 15 种语言下不一致是合规风险，需按既定流程补齐。
- **私有仓库的 raw 内容无法走加速**（README 仓库内图片、仓库文件）：`raw` 端点
  没有签名机制，交给代理等于送令牌。这是硬约束。
- macOS / iOS 自 v5.6.0 起弃用。

## v6.2.0（2026-10-06 · 正式版）

> **主题**：下载链路重做（端点 / 路由 / 完整性）+ 文件预览 + 隐私承诺。
> 三个此前"看起来能用、实际私有仓库用不了"的缺陷一并修掉。

### 新增 · Added
- **文件预览**：图片（可缩放）、SVG（矢量渲染）、XML 与文本（语法高亮）。
  仓库页**长按文件 →「打开方式」**可选「内置预览 / 编辑器 / 浏览器」，
  默认项按类型给出（图片默认渲染、SVG 默认渲染、源码类默认进查看器）。
- **Action 构建产物下载控件**：运行详情页列出产物（名称 / 大小 / 有效期），
  已过期的条目直接禁用 —— 点了也只会失败。
- **编辑器长按菜单**：复制 / 剪切 / 粘贴 / 全选。核实 `re_editor` 的 `CodeEditor`
  **没有 `contextMenuBuilder`**，只接受 `SelectionToolbarController`（抽象类），
  不传就没有菜单 —— 这正是「长按没有复制菜单」的根因。已用官方 factory
  `MobileSelectionToolbarController` 接上；文案取自 `MaterialLocalizations`，
  15 种语言由 Flutter 官方提供，无需自建词条。
- **引导页最后一页《开源协议与隐私承诺》**（15 语言全文，1104 字符）：
  **保证不收集数据**（无遥测 / 分析 / 广告 / 追踪 SDK；令牌只在本机安全存储且
  日志脱敏；网络请求仅指向 GitHub 与用户自选的加速通道），并**明确排除**可选的
  Web（浏览器）版本 —— 它跑在浏览器、站点托管方与网络中间环节之上，本应用无法
  替它们承诺；该功能默认关闭，只有主动开启才受此例外约束。

### 变更 · Changed
- **内置加速通道改为 `https://proxy.344977.xyz/`**（单前缀，转发完整原始链接）。
  同意协议版本 1 → 2 —— 地址变更属实质修改，必须重新征求同意。
- **加速路由重写为纯函数**（`ogLAccelCandidates`）：
  - 签名族（Release 附件 / Action 日志 / 产物）：大小未知或超过 500KB 即加速；
  - **raw 族（仓库文件 / README 仓库内图片）：仅「内置通道 + 公开仓库」才加速**。
    私有仓库的 raw **永远不加速** —— raw 端点没有签名机制，交给代理等于送令牌。
- **仓库文件取法按是否加速分流**：不加速走 API
  （`/repos/{o}/{r}/contents/{path}` + `Accept: application/vnd.github.raw`），
  加速才把 raw 链接交给代理。端点经实测选定：raw 媒体类型是 **1MB–100MB 文件的
  唯一取法**（JSON 形式对 >1MB 返回空 `content`），且**支持 Range**
  （实测 `206` + `content-range`），多连接分片下载不退化。
- **README 仓库内图片**：内置 + 公开时改走 raw + 代理。理由不只是速度 ——
  raw 不限流，而 Contents API 认证后也只有 5000 次/小时，一次 README 几十张图
  很容易吃配额。
- **登录页极简化**：删掉「怎么拿令牌」整块引导、「向导进度」四步清单与重复的
  「粘贴令牌」标题（输入框已有 label）。保留安全说明、令牌输入、显示 / 隐藏、
  登录与游客入口，以及一行紧凑的当前阶段提示。文件缩小 27%。
- 下载管理页的状态与分类标签改为走 i18n —— 此前直接把域层**硬编码中文**的
  `label` getter 渲染到界面，非中文用户会看到「已完成」「仓库文件」。
  `i18n_scan` 只扫 `lib/surface/`，域层不参与，**这类问题门禁永远抓不到**，
  只能靠「界面文案一律经 `_t()`」这条纪律守住。

### 修复 · Fixed
- **私有仓库下载未带认证头**（Release 附件 / Action 产物 / 仓库文件三处）。
  提交前实际表现是：私有仓库点下载必然 401/404。
- **仓库文件的 raw 直链在私有仓库取不到内容** —— raw 无签名机制，必须走 API
  带令牌。这也是"不加速时也该走 API"的由来。
- **下载后不校验完整性**：这是引入第三方加速代理后**唯一能让代理静默替换下载
  内容**的缺口。现在比对 GitHub 提供的 SHA-256；不匹配判为失败且**跳过 SAF
  导出**（顺序：先校验再宣告完成）；没有摘要可比对时如实标注「未校验」。
- **文件名零净化**：`fileName` 的来源之一是 Release 附件名（仓库所有者可自行指定），
  直接交给第三方下载库等于把路径构造外包给无法审计的实现。新增净化：只取末段、
  剔控制字符、拒 `..`、绕开 Windows 保留设备名、限长 120 并保住扩展名。
- **非 http(s) 地址被放行**：新增协议白名单，入队与全部降级地址一律校验。
- **跨域重定向的令牌外泄风险**：此前依赖 Dart SDK 未文档化的「跨域自动剥离
  Authorization」行为，代码里既没显式关闭也没断言。现在显式**不跟随重定向**，
  并校验跳转目标（只允许 http/https，拒绝回环 / 私网 / 链路本地，含云元数据
  `169.254.169.254`）。
- **构建 · Windows 两条腿的 spec 从未被应用**：Windows runner 无 PyYAML，注入器
  走手写的零依赖兜底解析器，而它几乎解析不出内容（实测无 PyYAML 只解析出 1 条，
  装上 PyYAML 则 7 条全出），于是编译宏全部未注入。已重写为**缩进驱动的递归
  解析器**（词法阶段折叠 `>` / `|` 块），与 PyYAML 结果**逐字段一致**。
- **构建 · Android 五条腿未跟进 Kotlin DSL 迁移**：Flutter 3.47.5 的模板已生成
  `android/app/build.gradle.kts`，而 spec 仍指向 `build.gradle`，注入被静默跳过，
  导致 `compileSdk` 停在 36（插件要求 37）且 desugaring 未开。注入器现在**缺目标
  文件即报错退出**，失败点从编译期前移到注入期，日志直接指出缺哪个文件。
- **发布 · Linux 的 deb / rpm / AppImage 从未真正发布过**：发布作业**没有
  `actions/checkout`**，工作目录是空的，`tool/linux_packages.py` 不存在；
  而该步骤带 `|| true`，错误被吞掉。实测 v5.6.0 / v6.0.0 / v6.2.0 的 Release
  里裸放安装包数量**均为 0**，而 README 一直承诺提供它们。已补上签出步骤，并把
  「脚本不存在」改为**非零退出码失败**（单个格式打包失败仍只告警，不拖垮发布）。

### 移除 · Removed
- main 上的 Web 残留：`.github/workflows/web.yml`（挂在 `push:[main]`，每次推 main
  都白跑一遍，且带 `contents: write` 权限）、`tool/web_build.py`、`docs/WEB.md`。
  v6.0.1 的 changelog 声称已删除，但**从未真正推上去**。
- 5 个已被 `platform_spec.yaml` + 统一注入器取代的旧脚本。
- 2 个零引用僵尸文档（按 `docs/README.md` 自身"一次性规划落地后即移除"的约定）。

### 已知限制 · Known limitations
- **私有仓库的 raw 内容无法走加速**（README 仓库内图片、仓库文件）。这是硬约束，
  不是取舍：`raw` 端点没有签名机制。
- **音频不做内置播放**：Contents API 对超过 1 MB 的文件不返回内容，音频必然超限。
  预览页给出「下载」动作，之后可在下载管理页交给系统播放器。
- **Web 功能不在隐私承诺范围内**（见引导页最后一页）；默认关闭。
- macOS / iOS 自 v5.6.0 起弃用。
- **Linux 裸放安装包仅产出 3 / 6**：deb（amd64 / arm64）与 rpm（x86_64）已产出；
  rpm（arm64）因 Ubuntu 的 rpm 缺少 aarch64 平台定义、无法在 x86_64 宿主上交叉构建，
  两个 AppImage 因 appimagetool 未接受到 `ARCH` 环境变量而退出码 1。
  三种包在 zip / 7z 里都齐全，功能上不缺，只是未裸放直传。

## v6.0.1（2026-10-05 · 正式版）

> **主题**：内置加速通道换新代理 + **架构决策**：Web 端独立成支。
> 加速通道面向所有正式平台；Web 从此**不在 main 上**，走独立分支。

### 架构决策 · Architecture
- **Web 端独立**（独立分支 `web` + 独立 `lib/` + 独立 workflows）：
  - **不共用代码**：web 端不复用 main 的 `lib/`，另起一套原生实现；
  - **不共用 actions**：web 端不跑 `build.yml` / `ci.yml`，有自己的工作流；
  - **允许反复失败**：web 端编译失败**不影响** main 的五平台构建与发布。
  > Web lives on its own branch with its own `lib/` and its own workflows — no shared
  > code, no shared actions, and it may fail as often as it needs without ever
  > affecting the five-platform release.
- **平台能力下沉：能写 Dart 的写 Dart，写不了的写详细配置**（本次落地）：
  - **新增 `lib/platform/` 平台实现层** —— 每个平台一份**真实 Dart 实现**
    （`window_windows.dart` / `window_linux.dart` / `window_macos.dart` /
    `window_mobile.dart`），契约在 `window_capability.dart`，
    **选平台只发生在 `platform.dart` 一处**（全项目唯一的 `Platform.isXxx`）。
  - **`surface/app/desktop_window.dart` 退化为桥接**：函数名 / 枚举 / 常量
    原样转发，上层调用点**零改动**。
  - **原生窗口标题不再需要 C++ 注入**：`windowManager.setTitle()` 写的
    就是窗口管理器读的那个标题，`inject_desktop_shell.py` 是重复劳动，
    **已删除**。
  - **物理上写不了 Dart 的部分**（Android 安装期权限、compileSdk /
    desugaring、Windows 编译宏、ICO/PNG 图标、macOS entitlements）集中声明在
    **`tool/platform_spec.yaml`**，由 `tool/inject_platform_spec.py` 在构建期注入。
  - **注入不是逃生舱**：spec 每一条都必须写 `why`（为什么不能用 Dart），
    脚本强制校验，**缺 `why` 直接拒绝执行**；自检
    （`inject_platform_spec_selftest.py`，22 项，含幂等性与仓库不被污染）已挂 CI。
  - 删除 `inject_android_gradle.py` / `inject_android_manifest.py` /
    `inject_windows_cmake.py` / `inject_desktop_shell.py` / `inject_android_icon.py`
    五个脚本，由 spec 驱动的注入器统一接管。

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
- 更新日志站（`changed/`）**全部** Release 下载链接由旧式镜像前缀改为
  `https://gh.felicity.ac.cn/https://github.com/…` 形式；生成器
  `changed/generate_posts.py` 的 `ACCEL_HOST` 同步更新，保证后续重新生成一致。

### 移除 · Removed
- **实验性 Web（wasm）构建管线从 main 移除**（`.github/workflows/web.yml`、
  `tool/web_build.py`、`docs/WEB.md`）：该管线在 main 上是**死代码**（wasm 因
  `dart:ffi` 依赖必然失败），留着只会混淆职责。Web 改由独立分支承接。

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
- **Windows 本地缓存无法写入**：缓存 blob 文件名原样拼接 `scope|path`，
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
- 档位 0 关闭全部动画；档位 1 仅淡入、档位 2 淡入 + 位移、档位 3 再叠缩放（开销随档位增加）；
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