# 审计报告 · 第6批 视角B：UI 安全与数据（B6-B）

> 审计对象：/root/OhGithubLost v12.0.0 LTS —— UI 层与状态管理。
> 范围：lib/surface/app/（async / paged_controller / notifier / overlays / client_shell / permissions / token_exit_warning）、lib/surface/pages/（issue / pull / release_detail / repo_page 的写操作入口）、lib/surface/widgets/log_body.dart、lib/surface/types.dart。
> 依据：docs/QUALITY_STANDARD.md、AGENTS.md（均已完整读）。只审不改、未写 lib/。
> 所有条目均为静态代码确证（含代码证据）；需运行时复现的标「待议」。

---

## P0

（无。本批范围内未发现可直接造成数据静默丢失或权限误放行的 P0。）

## P1

### B6-B-01 切号后，Navigator 压栈页面与未重建 tab 的旧账号数据存在可见窗口
- 文件:行：lib/surface/app/client_shell.dart:245-263（`_pageFor` + IndexedStack）；lib/surface/pages/profile_page.dart:101-130（`_switchTo`）
- 问题：切号清缓存（`clearAllCaches` + `clearOgLRepoPageCaches`）只覆盖"可重建"的缓存层；壳内已挂载的 tab 页只有 Dashboard/Discover 用 `ValueKey('dash-<accountId>')` 重建，而 `_visited` 里已挂载且未被重新 key 的页面（以及任何被 `Navigator.push` 压在壳上、尚未 pop 的页面）里的 `AsyncController`/`PagedController` **实例数据仍在内存并继续展示**。
- 用户可见后果：A 账号打开过的列表（如私有仓库分支/议题列表）在切到 B 账号后，若该页仍在挂载且没有随 accountId 换 key，会先显示 A 的数据直到下一次手动刷新——即"用 B 账号看到 A 的私有数据"的串台窗口（与 profile_page.dart:116 注释宣称的"切换后必须清空所有缓存"不完全等价）。
- 级别：P1；原则 8/28；确证：代码证据 —— client_shell.dart 仅对 home/discover 传 `key: ValueKey('...-${_accountId ?? 'guest'}')`，profile/settings 与压栈页面无 key；profile_page.dart:118-119 只清桥层缓存与分页快照，不通知存活页面重建。
- 备注：待议——需运行时验证压栈页面在切号路径上是否总是先被 pop（Tab 内切号时无法回到压栈页，但 `_onAuthChanged → _check` 触发的 setState 会保活 IndexedStack 内的旧 State）。

### B6-B-02 PagedController 进程级快照缓存无上限、无 TTL 逐出，长期驻留旧账号可见数据
- 文件:行：lib/surface/app/paged_controller.dart:68-76、220-229
- 问题：`_recentPage` 是文件级（进程内共享）Map，只在 `clearCaches()`（切号/移除账号）时整体清空；TTL 6 秒只决定"是否回源"，**过期条目不会被删除**；条目数无上限（原则 29）。缓存键（如 `branches:$name`）不含账号维度，正确性完全依赖调用方记得调 `clearCaches`。
- 用户可见后果：a) 内存随浏览过的仓库/标签数无界增长；b) 任何一条"切号但未清缓存"的旁路（如 B6-B-01 的窗口、或 `_switchTo` 中 `switchTo` 成功但 `clearAllCaches` 抛异常时，profile_page.dart:108-122 的 catch 直接跳过清缓存）都会把上一账号的快照留给下一账号。
- 级别：P1；原则 28/29；确证：代码证据 —— `_recentPage[key] = _CachedPage(...)` 只写不清，`clearCaches` 仅两处调用（profile_page 切号/移除 + repo_page.dart:760 门面）。

## P2

### B6-B-03 AsyncController/PagedController 用"兜底 catch"把编程错误降级成『未知错误』
- 文件:行：lib/surface/app/async.dart:174-185（`catch (error)`）、lib/surface/app/paged_controller.dart:216-221（`catch (e)`）
- 问题：两处均为无类型限定的 catch，把 `TypeError`、`StateError` 等编程错误与网络异常同等处理：async.dart 归类为 `errorUnknown`（"未知原因"），paged_controller 直接 `error = '$e'`。原则 18/19 禁止兜底 catch、编程错误不降级。
- 用户可见后果：页面渲染缺陷/契约破坏被伪装成"加载失败，可重试"，开发期不炸、用户重试永远失败，排障只能翻日志。
- 级别：P2；原则 15/18/19；确证：代码证据。

### B6-B-04 AsyncController 错误归类把 403 限流误报为"权限不足"，原始错误信息不上屏
- 文件:行：lib/surface/app/async.dart:200-232（`_describe`）
- 问题：分类关键词把 `403` 一律归入 auth → "权限不足"；GitHub 限流（403 + rate limit）与真正无权限混为一谈。且 UI 只显示 `_t('failedWith')` 的模板句，原始异常文本只进日志（原则 38 要求错误信息说清"发生了什么、能做什么"）。
- 用户可见后果：限流时用户被引导去怀疑账号权限，重试无效；"能做什么"（等限流窗口）没有传达。
- 级别：P2；原则 38；确证：代码证据。

### B6-B-05 危险操作确认对话框 barrierDismissible=true，与令牌出设备警告的三重防关闭语义不一致
- 文件:行：lib/surface/app/overlays.dart:77-84（`ogLShowDialog` 默认 `barrierDismissible: true`）；lib/surface/app/token_exit_warning.dart:105-108（`false` + `PopScope(canPop:false)`）；lib/surface/pages/issue_page.dart:340、467、507；repo_page.dart:350、3844（可见性）、3893 区段（转移）、4164（删库）、3213（删分支）
- 问题：转移仓库/切换可见性/删除仓库/删除分支/锁定议题等不可逆操作的确认框全部可被"点遮罩 / 返回手势"一键取消。取消本身安全（不会误执行），真正的语义问题是**确认动作没有防连点**：`FilledButton` 的 `onPressed` pop(true) 后，`_runWrite`/`setState(_busy)` 才生效，确认按钮在弹窗存续期间可多次点按（多次 pop(true) 无害，故降为 P2）；且全仓库没有统一的"危险确认"类型（原则 12 要求确认在类型上表达，目前是各页手写 AlertDialog）。
- 用户可见后果：一致性缺口——同样是"危险"，令牌警告三重防关闭，删库确认一碰遮罩就没；用户无法形成稳定预期。
- 级别：P2；原则 12；确证：代码证据（token_exit_warning 为正面样板）。

### B6-B-06 issue_page 写权限入口判据与评论菜单判据混用，登录名读取失败按游客收敛后仍可由 canWrite 打开他人评论菜单
- 文件:行：lib/surface/pages/issue_page.dart:853-859（`if (canWrite || ghLogin(comment) == _viewerLogin)`）、117-131（`_resolveViewerLogin`）
- 问题：评论"编辑/删除"入口对 `canWrite == true` 的用户在**任何**评论上都出现，客户端不区分"自己的评论"与"他人评论"；`_viewerLogin` 读取失败按空串收敛（游客），但 canWrite 为 true 时菜单照开。依赖服务端 403 兜底（文件头注释自认"客户端不猜权限"）。
- 用户可见后果：push-only 协作者对自己无权改删的评论（如他人评论在锁定议题下的边界情况）点开后得到 403 报错横幅——失败如实可见，不算数据风险，但是可预知的必然失败路径（浪费一次往返 + 一次惊吓）。
- 级别：P2；原则 9/38；确证：代码证据。

### B6-B-07 issue 正文编辑无长度护栏，评论有 6 万字符护栏——同一页面双标
- 文件:行：lib/surface/pages/issue_page.dart:50-52（`_kMaxCommentChars`）、196-204（`_editIssue` 仅校验标题非空）、505-521（`_postComment` 有护栏）；lib/surface/pages/release_detail_page.dart:83-190（`_edit` 的 body TextField 无任何长度/内容护栏）
- 问题：发评论/改评论本地先拦超长正文；但**编辑议题正文**与**编辑 Release 说明**都没有本地长度护栏，超限请求直接打到服务端。
- 用户可见后果：用户在本地编辑器里写了几万字正文，保存后才收到服务端拒绝，且（release 路径）错误原文直接拼进 SnackBar；长输入没有草稿护栏（原则 8：用户写的内容不能丢——对话框关闭即丢，无草稿落盘）。
- 级别：P2；原则 8/38；确证：代码证据。

### B6-B-08 指派人与转移目标登录名零格式校验，topics 有归一化——四线表单校验强度不一
- 文件:行：lib/surface/pages/issue_page.dart:303-333（`_manageAssignees`：split(', ')+trim 后直接 PUT）；lib/surface/pages/repo_page.dart:3893-3940 区段（`_transferRepo`：`_promptText` 取任意字符串 trim 后作为 newOwner）；对照 repo_page.dart:3704-3720（`_normalizeTopics` 有 `^[a-z0-9][a-z0-9-]*$` 白名单，做得对）
- 问题：assignees 与 transfer 的目标是 GitHub login/owner 名，未做 login 字符集/长度校验（含大小写、URL、空格残留、全角字符）；注入面实际由服务端兜住（GitHub 校验 422/404），但错误会原样回显给用户，且转移确认框按钮文案 `transferTo` 直接内插未校验字符串（展示层注入面：长字符串/控制字符可撑破对话框排版）。
- 用户可见后果：粘贴错内容（如整条仓库 URL）后得到含原文的 404 报错；恶意 issue 里的超长 login 显示溢出。无数据损坏路径。
- 级别：P2；原则 20/38；确证：代码证据。

### B6-B-09 仓库删除操作不在 `_busy` 闸门内，删除在途可再次触发
- 文件:行：lib/surface/pages/repo_page.dart:4163-4199（`_deleteRepo`：确认后直接 `api.deleteRepo`，无 `setState(_busy)`，入口按钮 4475 也不受 `_busy` 禁用）
- 问题：同页其它写操作（可见性/转移/归档）都有 `_busy` 防重入，唯独删库没有；DELETE 在途时用户可再点"删除仓库"重复发起（DELETE 幂等，第二次 404 会走 `branchDeleteFailed` 错误分支，谎报"删除失败"）。
- 用户可见后果：第二次点击收到"删除失败"横幅，但仓库实际已删——伪造的失败比失败更难排查（原则 42）。
- 级别：P2；原则 26/42；确证：代码证据（对照 3724/3814/3950 等处的 `_busy` 模式）。

### B6-B-10 issue_page `_toggleLock` 先读后写缺失：锁定状态取自列表对象的本地镜像
- 文件:行：lib/surface/pages/issue_page.dart:87（`_locked = widget.issue['locked'] == true`）、338-372（`locking = !_locked` 直接翻转本地值）
- 问题：议题可能早在列表页打开后就被他人锁定/解锁；进入详情页不重新读 `locked` 字段，确认框文案与随后 PATCH 的动作都基于可能过期的本地镜像。服务端幂等兜底，无数据损坏。
- 用户可见后果：确认框写"锁定"实际发出的是对已锁定议题的重复锁定（或反之），成功提示与远端状态可能短暂不符。
- 级别：P2；原则 9；确证：代码证据。

### B6-B-11 PagedController 排队重放与 finally 通知的次序造成一帧"清空后重放"
- 文件:行：lib/surface/app/paged_controller.dart:225-233（finally 中先 `_notify()` 再 `unawaited(refresh())`）
- 问题：在途请求结束时先 `_notify`（此刻 items 已是旧代次数据或已 clear），随后重放的 `refresh()` 里 `_generation++` 并再次 `_load(reset:true)` 清空 items——两次连续 notify 之间用户会看到一次列表闪空（快速切换筛选时可感知）。
- 用户可见后果：纯视觉抖动，不丢数据、不串数据。
- 级别：P2；原则 33（体验刻度）；确证：代码证据；待议——需真机确认是否可感知。

### B6-B-12 OgLNotifier 在 messenger 未挂载时静默丢弃提示（无日志旁路）
- 文件:行：lib/surface/app/notifier.dart:64-69（`if (!_messenger.mounted) return;`）
- 问题：调用方纪律是"先记日志再提示"（issue_page 等已遵守），但本类作为"统一入口"本身丢弃时不留任何痕；若未来某个调用点先提示后记日志（或只提示），失败即静默消失。SnackBar 队列本身无上限（连续失败可无限排队），原则 29 的"所有资源有上限"未覆盖。
- 用户可见后果：当前调用面无实际丢失；风险是结构性的（回退通道依赖调用方自觉）。
- 级别：P2；原则 15/29；确证：代码证据。

### B6-B-13 log_body 查找命中列表无上限；激活查询后每块重算前缀和，大日志 O(n²)
- 文件:行：lib/surface/widgets/log_body.dart:118-140（`_rebuild` 的 while 扫描：单字符 query 对 10MB 日志产生数百万个 `_hits` 偏移）、172-193（`_chunkText`：每块都要累加前面所有块长度求 `blockStart`，滚动时 O(块数×块长)）
- 问题：`_hits` 无条目上限（原则 29）；`blockStart` 逐块前缀和未预计算（原则 31：热路径不分配/重复计算）。查找扫描虽有页面防抖，但命中列表与富文本切片都在主 isolate。
- 用户可见后果：对超大日志输入短查询时明显卡顿甚至内存尖峰（jank 而非崩溃）。
- 级别：P2；原则 29/31；确证：代码证据；待议——需实测卡顿阈值。

### B6-B-14 permissions 网关把一切异常吞成 needsUserAction，无日志
- 文件:行：lib/surface/app/permissions.dart:128-140（`_statusOf`/`_requestOf` 的 `catch (_) return needsUserAction`）
- 问题：权限查询/请求的任何异常（插件缺失、平台通道错误）都被无声折叠为"需用户手动开启"，与同文件 `_openAppSettings` 记日志的做法不一致；`describe()` 里存储探针失败同样吞掉。原则 16：捕获后必须转化为明确结果**或告警**。
- 用户可见后果：用户被反复引导去系统设置开一个实际上已经打开（或不可能打开）的权限，无法解释。
- 级别：P2；原则 15/16/18；确证：代码证据。

### B6-B-15 client_shell `_check` 失败路径把"读取异常"当"未登录"，登录态可能被瞬时错误顶掉
- 文件:行：lib/surface/app/client_shell.dart:106-143
- 问题：`refreshState()/activeAccount()` 任一抛异常即按未登录处理并进登录门（注释自辩"有恢复路径"）； transient IO 错误会让已登录用户突然看到登录页（状态未丢，重试可回，但用户以为被登出）。与 platform 存储失败"退回内存但大声上报"的纪律相比，此处只有日志无 UI 告知。
- 用户可见后果：偶发"闪回登录页"；在登录页选择游客模式后 `_guest=true`，即使用户实际有有效令牌，此后仍以游客身份浏览（私有仓库不可见），需手动再登录——一个真实的降级粘滞路径。
- 级别：P2；原则 21/38；确证：代码证据；待议——粘滞窗口需运行时确认。

### B6-B-16 `_saveBasic` 提交 topics 无条数/单项长度上限
- 文件:行：lib/surface/pages/repo_page.dart:3722-3753（`_saveBasic` 直接把 `_topicsValue` 全量 PATCH）；归一化在 3704-3720（只过滤非法字符与重复）
- 问题：GitHub 限制单仓库 ≤20 个 topics、单项长度有限；本地归一化不设数量上限，超限 PATCH 被服务端 422 拒绝后，`_topicsValue` 仍是本地态，与远端不一致直到下次 `onRepoChanged`。
- 用户可见后果：保存报错后 chips 显示的内容与远端不符（本地显示 25 个，远端还是旧的）。
- 级别：P2；原则 9/38；确证：代码证据。

### B6-B-17 ZIP 下载入口的候选地址构造正确，但 `Uri.encodeComponent(_branch)` 对含 `/` 的分支名（如 `feature/x`）会编码成 `feature%2Fx`，GitHub 归档端点不接受
- 文件:行：lib/surface/pages/repo_page.dart:261-317（`_downloadZip`）
- 问题：`refs/heads/{branch}.zip` 处分支名整体 `encodeComponent`；GitHub 对斜杠分支的归档路径要求保留斜杠（`refs/heads/feature/x.zip`）。含斜杠分支点"下载 ZIP"会 404（下载任务入队后失败，错误在下载中心可见）。
- 用户可见后果：非默认分支（常见命名 feature/x）的 ZIP 下载必然失败；失败有留痕（下载管理器），但每次都可预知。
- 级别：P2；原则 38；确证：代码证据（待议——端点行为需运行时实测）。

### B6-B-18 types.dart 对 gh_models.dart 全量导出（无 hide/show 收口）
- 文件:行：lib/surface/types.dart:19（`export '../domain/gh/gh_models.dart';`）
- 问题：其它 domain 文件都逐一 `hide` 实现类，唯独 gh_models 全量透出；一旦未来有人把服务类/客户端引用放进 gh_models（或它 re-export 别的文件），UI 就静默获得越层访问，contract_audit 未必拦得住（export 指向合法）。
- 用户可见后果：无直接用户后果；是分层纪律的结构性开口（原则 1/5）。
- 级别：P2；原则 1/5/55；确证：代码证据。

### B6-B-19 正面确认（不计缺陷）
- token_exit_warning.dart：`barrierDismissible:false` + `PopScope(canPop:false)` + 无计时器 + 决策落日志（TOKEN-EXIT-01），白名单主机精确到子域，与 QUALITY_STANDARD 第 12/40 条完全对齐；repo_page `_downloadZip`、release_detail `_download` 均在入队前同步点调用门禁，B4 遗漏已修复。
- issue_page 写操作统一经 `_runWrite`（`_busy` 防连点 + 失败横幅 + critical 日志 + mounted 收口），评论 6 万字符本地护栏、编辑对话框实时校验（repo_page `_createFile` 在对话框内即时校验避免 dispose 丢输入）均为同类实现中的正面样板。
- overlays.dart 的 `sheetAnimationStyle` 方案避免了自建控制器 pop 同帧 dispose 的闭场动画截断，注释与实现一致。

---

## 覆盖文件清单

| 文件 | 行数 | 覆盖方式 |
|---|---|---|
| lib/surface/app/async.dart | 553 | 完整读 |
| lib/surface/app/paged_controller.dart | 233 | 完整读 |
| lib/surface/app/notifier.dart | 75 | 完整读 |
| lib/surface/app/overlays.dart | 108 | 完整读 |
| lib/surface/app/client_shell.dart | 491 | 完整读 |
| lib/surface/app/permissions.dart | 461 | 完整读 |
| lib/surface/app/token_exit_warning.dart | 170 | 完整读 |
| lib/surface/pages/issue_page.dart | 1087 | 完整读（写操作入口逐条核） |
| lib/surface/pages/pull_page.dart | 213 | 完整读（只读页，无写入口） |
| lib/surface/pages/release_detail_page.dart | 557 | 完整读 |
| lib/surface/pages/repo_page.dart | 4509 | 完整读（四线写入口：编辑/标签/指派/锁定在 issue_page；转移/可见性/删库/归档/topics/CNAME/Pages/删分支/ZIP 在 repo_page，逐条定位核对） |
| lib/surface/widgets/log_body.dart | 217 | 完整读 |
| lib/surface/types.dart | 44 | 完整读 |
| 佐证：pages/profile_page.dart（切号清缓存链路） | 371 | 关键段读 |
| 依据：docs/QUALITY_STANDARD.md、AGENTS.md | — | 完整读 |

## 整体评价

UI 层的写操作纪律整体高于同类项目：危险操作普遍有二次确认、`_busy` 防连点闸门、失败横幅 + critical 日志双留痕，令牌出设备门禁（TOKEN-EXIT-01）是不可关闭确认的类型化样板，topics 归一化与文件路径实时校验也到位。主要短板集中在三处：① **切号后的缓存/存活页面失效链路不完备**（B6-B-01/02）——清缓存依赖调用方记得调，且不覆盖已挂载页面持有的实例数据，这是本批唯一够得上 P1 的数据可见性风险；② **兜底 catch 与错误归一化**（B6-B-03/04/14）把编程错误和限流降级成含糊的"未知/权限"文案，违背项目自己的"失败如实可见"底线；③ **校验强度不均**（B6-B-07/08/16/17）——同一批四线新增表单里 topics 做对了、assignees/transfer/正文长度没做。建议优先收敛切号失效路径（把 accountId 纳入快照键或统一注销存活控制器），其余为打磨级修复。
