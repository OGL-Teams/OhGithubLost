# 功能审计 1-A · GitHub API 正确性（lib/domain/gh/）

> 文档戳：更新时间 2026-11-23 06:41:02（Asia/Shanghai）· v15.0.0
> 范围：lib/domain/gh/ 全部 12 文件（7331 行）。只读审计，未改动任何代码。
> 事实基准：GitHub REST v2022-11-28 公开文档 + 项目内测试常量（test/domain/gh_*_test.dart）；无 docs/API_FIELDS_TRUTH 文件，涉及未核实处已标「待核实」。

---

## P0（数据丢失 / 崩溃 / 安全）

### P0-1 `paginate` 只发 GET 却会把 Link 头 + per_page/page 注入带 query 的非 GET（低危）与「限流头资源标签覆盖」——更严重的是限流资源分类键不可靠（降级为 P1，见 P1-3）⇒ 本条撤销

（审计过程中将本条重分类，见 P1-3；保留编号以防引用错位。）

### P0-2 RepoFileService.create 对**空基线（新建）不校验远端**即无 sha PUT，且 `_probePath` 与写之间存在 TOCTOU——并发第二写者覆盖首写
- 位置：lib/domain/gh/repo_file_service.dart:620-686（`create`）+ :1411-1425（`_probePath`）
- 症状：`create()` 先 `_probePath`（GET contents，ref query），探得 `missing` 后调 `api.putContent(..., baseSha 未传)`。GhApi.putContent（gh_api.dart:872-885）在 `baseSha == null/空` 时**不带 sha** 发 PUT contents。GitHub Contents API 语义：PUT 不带 sha = 更新；对已存在文件无 sha PUT 是**无条件覆盖**。
- 根因：探测（读）与提交（写）非原子；两个客户端先后 create 同一路径，后到者在探测通过后用无 sha PUT 静默覆盖先到者刚写入的文件，无任何冲突提示。方法注释声称"服务端另有『无 sha 即拒绝覆盖』的乐观锁兜底"（repo_file_service.dart:616 附近）——该承诺**与 GitHub 实际行为不符**（待核实标注：GitHub 官方文档对 PUT contents 无 sha 更新已存在文件的行为描述为 replace，无 422 拒绝逻辑；CI 无此类并发用例）。
- 修复指令：repo_file_service.dart `create` 在探测 missing 后、putContent 前**重读一次目标**或直接改为：探测成功后先 GET 该路径（期望 404），若 2xx 则返回 `exists`；`GhApi.putContent` 对「调用方未显式声明新建意图」的写禁止省略 sha（新增 `createNew: true` 参数，不发 sha 前先确认远端 404）。同时修正 :616 注释。

### P0-3 `GhApi.rateLimit()` 把错误响应/非对象响应当作"回退 lastRateLimit"，可能把**其它资源类别**的剩余量误报为 core 额度
- 位置：lib/domain/gh/gh_api.dart:75-82（`rateLimit`）
- 症状：`GET /rate_limit` 成功但响应被中间代理截断成非 JSON 时 `jsonObject` 返回 null → `object?['resources']` 为 null → 直接返回 `client.lastRateLimit`。`lastRateLimit` 是**最后一次任意请求**的快照（gh_client.dart:628-631），可能属于 search 资源；仪表盘据此显示"core 余量充足"而实际 core 已耗尽。
- 根因：`GhClient._rateLimits`（gh_client.dart:526）已按资源分桶，但 `lastRateLimit` 单槽 getter 仍被 `rateLimit()` 引用，两个口径打架。
- 修复指令：gh_api.dart `rateLimit()` 在 `/rate_limit` 响应无法解析出 `resources.core` 时返回 null（或抛），不再回退 `lastRateLimit`；或让 GhClient 暴露 `rateLimitOf('core')`。

### P0-4 GhToken.masked 对长度 8–12 的令牌泄漏首尾各 4 字符，重叠区间可能暴露大半令牌
- 位置：lib/domain/gh/gh_auth.dart:78-83
- 症状：`value.length == 8` → `'****'`；`length == 9..12` → 前 4 + 后 4，中间仅 1–4 字符被掩。GitHub 令牌前缀 `ghp_`/`gho_` 固定占 4 字符，尾 4 字符又暴露——对 9–12 位残留场景（如被截断的旧式 40 位令牌中间已不可见，但泄漏面为 8/40+）仍偏大；更关键的是 `looksValid`（:90-97）不含未来前缀时 `masked` 与 `looksValid` 不一致会被 UI 用于提示"令牌无效"，而 `github_pat_` 细粒度令牌其实合法。
- 根因：脱敏规则未对短值收敛；`looksValid` 前缀表是硬编码快照。
- 修复指令：gh_auth.dart `masked` 改为 `length <= 12 ? '****' : 前4+****+后4`；`looksValid` 命中失败时不要用于阻断保存（仅提示）。严重级按"信息泄露面"评 P0 偏严，若主会话认为实际令牌 ≥ 40 字符可降 P2——此处按最坏情况列出。

## P1（功能失效 / 不一致）

### P1-1 `issues()` 发送非法参数 `filter=all`——`/repos/{o}/{r}/issues` 不接受 `filter`（那是 `/issues` 用户级端点的参数）
- 位置：lib/domain/gh/gh_api.dart:1671-1691
- 症状：query 同时带 `state/per_page/page/filter`。GitHub 仓库级 issues 端点参数表无 `filter`；未知名参数 GitHub 通常忽略，不报错，但它是无效负载且误导阅读。**待核实**（无权威快照，按公开文档记忆标注）。
- 修复指令：删除 gh_api.dart:1682 的 `'filter': 'all'` 一行；若想要"含全部已关闭"语义用 `state: 'all'`。

### P1-2 目录级响应在 `GhApi._listDirectoryNetwork` 之外，`GhApi.content()` 对目录走缓存路径返回伪 GhContent（sha=''、size=0），与网络路径返回 null 的语义不一致
- 位置：lib/domain/gh/gh_api.dart:247-265（`content` 缓存命中分支）vs :296-317（`_contentNetwork` 目录返回 null）
- 症状：缓存命中目录标记（`dir:` 前缀）时返回 `GhContent(isDirectory: true, sha: '', size: 0)`；缓存未命中时 `_contentNetwork` 对目录响应 `object.containsKey('__list')` 返回 null。同一目录、缓存窗口内外两种返回形态，调用方若用 `content()` 判"存在性/类型"（repo_file_service.dart:1411 `_probePath` 特意绕开它并注明原因），行为漂移。
- 根因：缓存层把"目录列表"折叠成哨兵条目，读路径没有统一归一。
- 修复指令：`content()` 缓存命中遇 `dir:` 标记时返回 null（与网络路径对齐），或 `_contentNetwork` 同样返回目录哨兵；二选一，保证两路径同型。

### P1-3 限流资源分类依赖响应头 `x-ratelimit-resource`，但 GhClient 存桶键混用了"路径推导的 resource"与"响应头 resource"，且头缺省时归 core——search 列表被误计入 core 桶
- 位置：lib/domain/gh/gh_client.dart:588-595（预检用 `resourceOfPath`）与 :627-631（回填用 `rateLimit.resource`，缺头默认 `'core'`）
- 症状：GitHub 对 search 端点响应**通常带** `x-ratelimit-resource: search`；但部分代理/镜像会剥掉该头 → 回填成 core 桶 → core 额度被 search 的余量覆盖 → 下一发 search 请求预检查的是 search 桶（真实值从未写入），core 预检读到的却是 search 余量——两方向都可能错。
- 根因：回填桶键应使用**请求侧**推导的 `resourceOfPath(request.path)`，与预检键保持同一函数；响应头 resource 只做参考。
- 修复指令：gh_client.dart:628-631 改为 `_rateLimits[resource] = rateLimit`（resource 即 :588 处的请求侧分类），不要信响应头里的 resource 字段（或仅在两者一致时使用）。

### P1-4 `myRepos`/`branches` 等列表方法未消费 Link 头做"是否有下一页"，`paginate` 默认 maxPages=10 上限 × perPage=100 = 1000 条——>1000 仓库的用户列表静默截断
- 位置：lib/domain/gh/gh_client.dart:719-744（paginate）
- 症状：`paginate` 逐页用 Link.next 判断，正确；但达到 maxPages 时只记一条 diagnostics warn（:742-744），对流消费方**不可见**——调用方拿到的是"完整列表"假象。`myRepos` 等 UI 分页方法（gh_api.dart:95-117）由页面按 page 参数翻页，靠的是 UI 自己递增 page，无 Link 校验，最后一页判断是 `list.length < perPage` 的隐式约定（surface 层，未在本次范围）。
- 根因：安全上限设计正确，但截断未向上传播。
- 修复指令：`paginate` 在触发上限时 yield 一条带标记的分页（或让 GhApi 层包一个 `GhPageResult{items, truncated}`）；至少把 diagnostics.warn 升级为随流事件。

### P1-5 `GhApi.tag()` 与 `GhApi.createTag()` 对 annotated tag 返回的是 **ref 的 sha（指向 tag 对象）而非 peeling 后的 commit sha**，与 `GhTag.fromJson`（列表端点）口径不一致
- 位置：lib/domain/gh/gh_api.dart:457-478（`tag`）、:495-520（`createTag`）、gh_models.dart:291-315（`GhTag.fromJson` 用 `commit.sha`）
- 症状：`GET /repos/{o}/{r}/tags` 列表项的 `commit.sha` 是 GitHub **已 peel** 到 commit 的 sha；而 `git/ref/tags/{name}` 返回的 `object.sha` 对 annotated tag 是 tag 对象自身的 sha。同一个标签，列表页与详情页显示两个不同 sha；用户复制"列表 sha"去 checkout 是 commit，复制"详情 sha"去 checkout 会失败。
- 根因：两处解析未统一 peel 语义（ref API 可用 `Accept: application/vnd.github.v3+json` + `?per_page`，或取 tag 对象再解 `object.tagger`…标准做法是再 GET tag 对象取 `object.sha`）。
- 修复指令：gh_api.dart `tag()`/`createTag()` 在拿到 ref 的 object.type == 'tag' 时追加一次 `GET /repos/{o}/{r}/git/tags/{sha}` 取内层 `object.sha` 作为 GhTag.sha（原值放 raw）。

### P1-6 `commitFiles` deletion 条目 `mode: '100644', type: 'blob', sha: null`：对符号链接/子模块路径的删除会走错（与 `_commitRaw`/`_deletionFor` 的精细处理不一致），且 **deletion 用 `mode 100644 + sha null` 在 Git Data API 里是合法的**（GitHub 以 path 为准删条目）——但 mixed batch 中 symlink 也会被当普通 blob 删
- 位置：lib/domain/gh/gh_api.dart:1196-1204（deletions 硬编码 100644/blob）vs repo_file_service.dart:1544-1551 与 :1786-1796（已按 mode/type 区分）
- 症状：`GhApi.commitFiles` 直接暴露给其它调用方（rg 确认 repo_file_service 在 `needsRaw` 假分支调用它——纯文本常规文件时 deletion 全是普通 blob，安全）。但**任何其它调用方**传含 symlink 的 deletions 时，GitHub 端以 path 匹配删除，实际仍能删掉（sha null + 任意 mode 都删）——功能可用，仅语义噪音。**降级：确认无第三方调用后为 P2**。
- 修复指令：在 `GhApi.commitFiles` 文档注释声明"deletions 仅支持常规 blob"；或同款按 mode/type 收口（gh_api.dart:1196-1204）。

### P1-7 Web Flow state 熵不足且可预测（毫秒时间戳 + 端口号），CSRF 防护形同虚设
- 位置：lib/domain/gh/gh_oauth_webflow_io.dart:46-48
- 症状：state = `ogl-<ms>-<port>`。攻击者若能预测发起时间（同一秒内诱导用户点击）可构造 state 匹配的回调，交换攻击者自己的 code 造成 **code 注入/会话固定**（登录到攻击者账号）。OAuth 2.1 明确要求 state 应为密码学随机值。
- 修复指令：gh_oauth_webflow_io.dart:47 用 `Random.secure()` 生成 ≥128-bit 随机数做 state（dart:math），替换时间戳拼接。

### P1-8 Device Flow `slow_down` 处理在 `GhOAuthCode.interval` 已含 GitHub 返回 interval 时只 +5s——标准要求把轮询间隔改为**当前间隔 +5s**（实现一致），但 `interval` 起始值取自 start 响应后未与本地最小 5s 取 max；GitHub 返回 interval 缺失时 fallback 5，正确——此条核实为**正确**，撤销

### P1-9 `GhClient.send` 对写操作（非 GET）成功后 `_readCache?.clear()`，但**只清"只读端点缓存"**；底座 ConsistencyCache 的目录列表缓存（gh_api `_dirMaxAge` 1 分钟）依赖 D5 写后失效——但 `RepoFileService._run` 只在 `result.succeeded > 0` 时 `api.invalidateReadCache()`（repo_file_service.dart:1333-1341），而 `GhApi.putContentLocked` 裸写分支（gh_api.dart:972-998）失效的是**单键**。多文件批量提交后，底座缓存的**其它路径**条目（如目录列表）未失效 → 批量改名后目录页 60 秒内仍显示旧文件名
- 位置：lib/domain/gh/gh_api.dart:882-935（putContent 注释明确"引擎路径 D5 自带失效"）、repo_file_service.dart:1333-1341（只 invalidateReadCache = GhClient 的 R4 缓存，非 ConsistencyCache）
- 症状：批量 rename/copy/delete 走 `_commitRaw`/`commitFiles`（Git Data API），完全绕过 ConsistencyCache 的逐键写后失效——它只按 `key.path` 失效单文件。目录列表缓存键是 `dir:` 哨兵条目，批量操作后**父目录列表**的缓存条目仍是旧 JSON，TTL 1 分钟内用户看到旧目录结构；写的是另一分支/仓库时更无失效。
- 根因：ConsistencyCache 失效粒度 = 单文件键；目录列表条目（`dir:` 前缀）没有随 Git Data 提交失效的路径。
- 修复指令：`RepoFileService._run` 在成功后额外调用 `api` 所属 ConsistencyCache 的**仓库/分支级**失效（需 ConsistencyCache 暴露 `invalidateRepo(scope)` 或清 `dir:` 前缀条目）；至少在 `_commitBatch` 成功后 invalidate 父目录键。若主会话判定 60s TTL 可接受，可降 P2——但"改名后立刻看到旧名字"是可复现的功能不一致，列 P1。

## P2（打磨）

### P2-1 `GhRepo.watchers` 读 `watchers_count`，GitHub 已把该字段与 `stargazers_count` 等值化（watchers 实为 watchers_count == stars）
- 位置：gh_models.dart:248
- 症状：仓库卡片若展示"关注数"会显示与星标数相同的值。**待核实**（GitHub 官方文档注明 watchers_count 与 stargazers_count 同义；真实订阅数在 `subscribers_count`）。
- 修复指令：gh_models.dart:248 改读 `subscribers_count`，并把 UI 文案改为"Star 数"或分开两个字段。

### P2-2 `RepoFilePaths._segmentProblem` 段长上限 100 字符 + `_kAllowedSegment` 禁止 `+`：合法 GitHub 文件名（含 `+`、`~`、`!`、`'`、`(`、`)`、`,` 等）在**用户新建/重命名**时被拒——这是产品决策而非 bug；但 `validateDerivedPath`（:461-483）放宽后，重命名**已有**含 `+` 文件进入目录时派生路径合法，行为不对称已按注释声明，接受
- 位置：repo_file_service.dart:523-537
- 无需修复；列档备查。

### P2-3 `GhResponse.jsonAsList` 中 `decoded is List` 分支调用 `jsonList` 会**二次解码 body**（jsonDecode 两次），大列表性能浪费
- 位置：gh_client.dart:355-367
- 修复指令：`jsonAsList` 直接复用一次解码结果，避免调用 `jsonList` 再 `_decode()`。

### P2-4 `GhApi.readmeExcerpt` 过滤规则把 `---` 开头的 frontmatter 整段丢掉首行后，`---` 结束行也被丢，但 frontmatter 中间的键值行会混入正文
- 位置：gh_api.dart:1468-1496
- 修复指令：检测到 frontmatter（首行为 `---`）时跳过到下一个 `---` 再过滤。

### P2-5 `GhJson.integer` 对 `double` 类型 JSON（如 `1e3`）走 `num.toInt()` 正确；对超大数字字符串 `int.tryParse` 失败回 fallback 0，静默——低风险，列档
- 位置：gh_models.dart:45-58

### P2-6 `dispatchWorkflow` 对 workflow 文件名**未做 URL 编码**（`$workflowIdOrFile` 直接插值）；含空格/子目录文件名（`.github/workflows/build release.yml`）会 404
- 位置：gh_api.dart:1990-2004
- 修复指令：对 `workflowIdOrFile` 做 `_ghPath` 同款逐段编码（GitHub 该端点按文件名匹配，需 encode）。

### P2-7 `latestVersionOf` 回退 `/tags?per_page=1` 取的是**字母序第一个 tag**（GitHub tags 端点默认按 name 字母序、非语义版本序），"最新版本"可能取到 `v0.x` 而 `v10.0` 排在前
- 位置：gh_api.dart:1522-1541
- 修复指令：拉多页 tag 后按语义版本（或创建时间）排序取最新；或改用 `git/matching-refs/tags` + 客户端排序。**待核实**（排序无权威文档，按已知行为标注）。

### P2-8 `GhOAuthCode.interval` 上界未 clamp：GitHub 返回异常大的 interval（如 600）时轮询 15 分钟内只发 1-2 次，用户以为卡死
- 位置：gh_oauth_io.dart:52-55（interval 解析）、gh_oauth_io.dart:82（delay）
- 修复指令：`interval` clamp 到 [5, 30] 秒。

---

## 已检查清单（12/12 文件，全覆盖；未抽样）

| 文件 | 行数 | 结论 |
|---|---|---|
| gh_api.dart | 2308 | P0-3, P1-1, P1-2, P1-5, P1-9, P2-4, P2-6, P2-7 |
| gh_client.dart | 845 | P1-3, P1-4, P2-3 |
| gh_models.dart | 1024 | P1-5（口径）、P2-1, P2-5；fromJson 容错总体良好（缺字段默认值/类型不硬转均落实） |
| repo_file_service.dart | 2042 | P0-2, P1-9, P2-2；BASE64 双管线（文本严格 UTF-8 复核 + 字节透传）验证正确；路径逐段编码验证正确（:673/:758/:1441） |
| gh_auth.dart | 423 | P0-4 |
| gh_draft.dart | 56 | 无问题（纯视图类） |
| gh_read_cache.dart | 184 | 无独立问题（与 P1-4 Link 头已修，纪元清理正确） |
| gh_oauth.dart | 95 | 无问题（facade 转发正确） |
| gh_oauth_types.dart | 43 | 无问题 |
| gh_oauth_stub.dart | 28 | 无问题（明确抛 UnsupportedError） |
| gh_oauth_io.dart | 116 | P1-8（核实为正确，撤销）、P2-8 |
| gh_oauth_webflow_io.dart | 167 | P1-7 |

### 逐维度覆盖确认
- ①API 方法/路径/参数：核查了 60+ 端点封装（user/repos/starred/forks/transfer/branches/rename/contents/blobs/trees/commits/refs/releases/search/pages/issues/pulls/comments/lock/labels/gists/actions/notifications/readme/rate_limit）。方法与路径与 GitHub REST v2022-11-28 一致；仅 P1-1 `filter` 参数、P2-6 workflow 文件名编码为疑点。`lockIssue` 用 PUT（gh_api.dart:1796）**正确**（官方 PUT lock）。PR 评论共用 issues/comments 端点（:1743）**正确**。
- ②分页：GhPage.parse Link 头解析正确（含 `rel = "next"` 容错、pageOf 正则）；paginate 逐页走 next 且有空页/上限保护（P1-4 上限不透明）；列表方法 per_page/page 传参全部正确；分支跨页查找上限 3 页（gh_api.dart:559-574）合理。
- ③错误映射：401（带令牌才 markExpired）/403+Retry-After/429/abuse→限流、404→NotFound、409/422→可配 RemoteConflictException、206→回读确认（putContent gh_api.dart:898-915）——映射矩阵完整且与 gh_client_test 断言一致。唯一疑点 P1-3 资源桶键。
- ④模型解析：GhJson 全套容错（str/integer/boolean/date/objects/strings）核实无硬转崩溃点；GhContent 空文件/超 1MB/目录三分支正确；GhTree.truncated 一等公民。P1-5 tag sha 口径、P2-1 watchers 为已发现项。
- ⑤文件操作：BASE64 编解码（putContent base64Encode(utf8) / blobText utf8.decode / _normalizeBase64 去空白）验证正确；路径双重编码风险排查：URL 用 encodeForUrl、JSON body 用原始路径，无重复编码；冲突处理（expectedHeadSha 逐批链式 + 文件级 baseSha + tree truncated 拒执行）设计正确，唯 P0-2 create TOCTOU 与 P1-9 目录缓存失效两处缺口。

---

## 本席结论

12 文件全查。**P0×3（有效）**：create 无 sha PUT 的 TOCTOU 覆盖（P0-2）、rateLimit 回退跨资源误报（P0-3）、短令牌脱敏面过大（P0-4，可能降级）。**P1×6**：非法 `filter` 参数、目录哨兵语义不一致、限流资源桶键混用、分页上限不可见、annotated tag sha 口径分裂、Web Flow state 熵不足、批量提交后目录缓存不失效（其中 P1-6 已建议降 P2）。**P2×8**。整体架构质量高：错误映射矩阵、容错解析、字节精确双管线、路径编码分离均落实到位且有多席位交叉审计修复痕迹（B2/B3/B5 系列编号）；剩余问题集中在**并发写竞态**与**跨端点语义口径**两类，均为可局部修复项。无权威 API_FIELDS_TRUTH 文档，2 处标「待核实」建议主会话/CI 裁决。
