# 审计报告 · 第4批 视角B：安全与数据（下载管理链路）

> 对象：OhGithubLost v12.0.0 LTS，下载管理链路（presign → 加速路由 → 入队 → 后端/分片 → 校验落盘）。
> 方式：只审不改、不写 lib/。全部目标文件已用 file_read 完整读；裁决依据 docs/QUALITY_STANDARD.md 与 AGENTS.md 全文。
> 结论状态标记：〔确证〕= 有代码证据；〔待议〕= 需运行时实测才能定谳。
> 追加顺序即编号顺序。

---

## B4-B-01 background_downloader 单连接库路径无重定向守卫，令牌是否随 302 外泄未经验证 〔待议〕

- 位置：lib/domain/ix/ix_download_backend_io.dart:99–121（`_build` → `DownloadTask(url, headers: spec.headers, retries: 2)` → `_downloader.enqueue(task)`）
- 问题一句话：手动重定向守卫（io_net_transport.dart 的 `_sendWithGuardedRedirect`）只覆盖 `IoNetTransport`；走 `background_downloader` 的单连接下载（含私有仓库归档 zip、私有 raw 直连、未预签名 Release/产物）把带 `Authorization` 的头直接交给第三方库，第一跳 302 后库是否跨主机剥离凭证完全取决于库的内部实现，本仓库无任何代码强制。
- 用户可见后果：若库在跨主机 302 时重发 Authorization（background_downloader 在 Android 用系统网络栈、桌面用自有实现，行为不一），令牌被送到 Location 指向的任意主机 —— 凭证外泄，违反 QUALITY_STANDARD 第 40 条。
- 级别：P0（若实测库不剥离）/ P1（若库确实剥离，则降级为"安全依赖未文档化的第三方行为"）
- 原则：40（令牌只在必要的跳使用一次）
- 证据：ix_download_backend_io.dart:99–106 `DownloadTask(url: spec.url, headers: spec.headers, retries: 2)`；repo_page.dart:283–288 私有仓库 `_downloadZip` 把 `downloadAuthHeaders()` 直接传给该路径，第一跳 `github.com/...zip` 必然 302 → `codeload.github.com`（跨主机）。
- 处置建议：需在真机/桌面抓包实测库的重定向行为；无论结果如何，私有仓库归档下载应先在本地走一次 presign 式手动第一跳（codeload 地址可本地解出）再入队。

## B4-B-02 `_downloadZip`（仓库归档）绕过 TOKEN-EXIT-01 门禁 〔确证〕

- 位置：lib/surface/pages/repo_page.dart:264–300（`_downloadZip`），对照 token_exit_warning.dart:58–120 与其余四个调用点（release_detail_page.dart:269、action_run_page.dart:408、file_preview_page.dart:590、repo_page.dart:1858）
- 问题一句话：token_exit_warning.dart 自述"门禁函数，四个下载调用点共用"，但仓库归档这一带令牌下载入口（私有仓库加速时令牌发往用户自建代理主机）从未调用 `ogLGuardTokenExitDownload`，只依赖设置页的一次性 `accelPrivateRepoAccepted` 知情开关。
- 用户可见后果：用户开启"私有仓库加速"总开关后，每一次私有归档下载把 Bearer 令牌交给第三方代理主机，均无逐次不可关闭警告、无 TOKEN-EXIT-01 决策留痕 —— 与其它四个入口的安全体验不一致，违反第 12 条（危险操作必须显式确认，且确认在调用点上类型化表达）。
- 级别：P1
- 原则：12、40
- 证据：repo_page.dart:286 `enqueue(url: candidates.first, headers: headers, ...)` 前无 `ogLGuardTokenExitDownload` 调用（rg 全库仅 4 处调用）。

## B4-B-03 除 Release 附件外，所有加速通道下载均无完整性校验，通道可替换内容 〔确证〕

- 位置：lib/domain/ix/ix_download.dart:638–652（`enqueue` 的 `expectedSha256` 参数）及各调用点；对照 release_detail_page.dart:292（唯一传 digest 的入口）
- 问题一句话：加速通道把全部响应字节交给用户自建的第三方服务器，只有 Release 附件用 GitHub 自带 `digest` 做 sha256 校验；仓库文件（file_preview_page.dart:606）、归档 zip（repo_page.dart:286）、Gist（gist_detail_page.dart:308）、Action 构建产物（action_run_page.dart:424）全部不传 `expectedSha256`，`_verifyIntegrity` 对这些任务只能如实标「未校验」（ix_download.dart:829–846，事件码 OGL-DL-401）。
- 用户可见后果：被篡改/污染的可执行文件、归档、产物会以"下载完成（未校验）"状态进入用户可见目录并导出 SAF；对产物/归档这类本可由 GitHub API 提供摘要的资源，属于防御缺位（数据风险，非凭证风险）。
- 级别：P1
- 原则：44（对外部目标保持怀疑）、8
- 证据：上述四个 enqueue 调用均无 `expectedSha256:` 实参（rg 验证仅 release_detail_page.dart:292 一处）。
- 备注：界面如实呈现「未校验」（不谎称验过），故不是"伪造成功"，但风险敞口真实存在；Action 产物可先 `GET /artifacts/{id}` 取 `archive_download_url` 的 Content-Length/ETag 做弱校验，或至少对签名族一律要求摘要。

## B4-B-04 `IxPresign.isForbiddenHost` 未拦截 NAT64（64:ff9b::/96）编码的 IPv4，SSRF 校验可被绕过 〔确证〕

- 位置：lib/domain/ix/ix_presign.dart:130–196（`isForbiddenHost`）
- 问题一句话：函数处理 IPv6 时只取 `split(':').first` 判 hextet、取 `split(':').last` 提 IPv4 映射段，`64:ff9b::a9fe:efee`（NAT64 well-known 前缀编码的 169.254.239.238）首段 hextet=0x64 不落在任何拒绝区间、末段无点，直接放行；`0177.0.0.1`（八进制 IPv4，`int.tryParse` 按 177 处理）同样放行。
- 用户可见后果：302 Location 若指向 NAT64 编码的回环/链路本地/云元数据地址，presign 会把它当作合法签名地址返回，后续分片/下载请求打向内网或 169.254.169.254（元数据 SSRF）；本应用不带凭证的后续跳不泄令牌，但可被用作内网探测（第 44 条下限被击穿）。io_net_transport.dart:64–110 的 `_ogLIsSafeRedirectTarget` 有同样的 IPv6 字面量白名单式漏洞（仅 startswith fe80/fc/fd）。
- 级别：P2（利用前提是攻击者能控制 302 Location —— 对 GitHub 官方域名难，对企业实例/被污染 DoH 场景可行）
- 原则：44
- 证据：ix_presign.dart:156–176（IPv6 分支）；对照 io_net_transport.dart:100–109。建议改用 `InternetAddress.tryParse` + 地址类别判定，或在首段命中 `64:ff9b` 时按 IPv4 规则复核末 32 位。
- 附注：域名形式目标不做 DNS 解析属文档明示的取舍（字面量判定 + TLS 兜底），DNS rebinding 残余风险标〔待议〕，不计缺陷。

## B4-B-05 带令牌的 `DownloadTask` 会被 background_downloader 持久化，令牌落库为明文序列化数据 〔确证〕（行为细节〔待议〕）

- 位置：lib/domain/ix/ix_download_backend_io.dart:99–106（`headers: spec.headers, retries: 2`）
- 问题一句话：`retries: 2` + 后台续传意味着任务（含 Authorization 头）必须跨进程存活 —— background_downloader 会把任务序列化进其 SQLite/SharedPreferences 持久层，令牌以明文进入非密钥库的存储，违反第 39 条"凭证只进系统密钥库，永不进序列化数据"；AGENTS.md 只声明"令牌只进系统密钥库"。
- 用户可见后果：root/备份/adb backup 场景下攻击者可从应用数据目录直接读出 GitHub PAT；无用户可见异常，纯静默数据风险。
- 级别：P1
- 原则：39
- 证据：`DownloadTask(headers: spec.headers)` 是库的持久化构造入口；带令牌的入队路径：repo_page.dart:283（私有归档）、file_preview_page.dart:606（私有仓库 API 直取）、release_detail_page.dart:264–283（未预签名回退）、action_run_page.dart:403–424。
- 〔待议〕部分：库的具体持久化格式/位置需实测确认；若确认持久化，建议对带令牌任务禁用 retries 或入队后即时改写库记录。

## B4-B-06 取消/失败/进程死亡会残留敏感内容的 `.partN` 临时分片 〔确证〕

- 位置：lib/base/net/range_download_io.dart:150–245（`fetch` 的 finally 清理仅在**进程存活**时执行）
- 问题一句话：分片临时文件写在最终下载目录（`<savePath>.partN`，与成品同目录），清理只靠本次 fetch 的 finally；进程被杀/设备断电后，私有仓库文件、私有归档的分片明文残留在公共下载目录（①档时是 `/storage/emulated/0/ogl/download/…`，任何有存储权限的应用可读），且没有任何启动期清扫逻辑（rg 全库无 `.part` 清扫）。
- 用户可见后果：用户感知不到；同设备其它应用可读到私有仓库内容的半截明文（数据风险）。
- 级别：P2
- 原则：13（半成品必须留有痕迹并能被重启发现 —— 现状是留了半成品、没有发现机制）
- 证据：range_download_io.dart:170–174 `File('${request.targetPath}.part$i')`；ix_download.dart 的 `remove`/`clearFinished` 均不触碰 `.partN`。
- 建议：启动/装配期对下载目录做一次 `*.part*` 清扫，或分片写私有缓存目录、合并后落最终目录。

## B4-B-07 单连接库路径的 206/截断响应是否污染成品不可证 〔待议〕

- 位置：lib/domain/ix/ix_download_backend_io.dart:99–121；对照 range_download_io.dart:206–245（分片路径已逐字节校验 Content-Range 对齐 + 总量 + 长度，B1-A-16 修复到位）
- 问题一句话：分片引擎对 206 错位区间、截断、CDN 换资源的防护是本仓库自己写的（`_rangeOf` + `expectedTotal` + `got != range.length` 三道），但单连接回退路径把这些全部交给 background_downloader —— 库是否校验 Content-Length 截断、是否对 206 响应（服务端错误地对无 Range 请求回 206）正确处理，本仓库无代码也无测试覆盖。
- 用户可见后果：若库不校验截断，用户拿到"完成"状态的半截文件，且除 Release（有 digest）外无校验兜底（B4-B-03），坏文件直接可用。
- 级别：P2
- 原则：44、42
- 证据：分片路径的防御代码与库路径之间无共享逻辑；`_finishTaskInner` 对无摘要任务不做任何字节级验证。
- 处置：真机用限速代理截断传输实测库行为；长期看单连接路径也应过自研引擎或在 `_verifyIntegrity` 对有 Content-Length 的资源做长度复核。

## B4-B-08 私有 raw 经加速通道时仅依赖"代理会转发 Authorization"的实测经验，Accept/头透传无任何运行时探测 〔待议〕

- 位置：lib/surface/surface_bridge.dart:382–391（加速分支只回 `downloadAuthHeaders()`，无 accept、无头透传探测）
- 问题一句话：注释与 NETWORK.md §3.2 声称"实测：代理会原样转发 Authorization 头"，但代码层面对用户自建通道不做任何能力探测（能否透传头、是否改写响应）；若通道剥离 Authorization，私有 raw 下载必然 404，界面按 `IxDownloadError`（network/unknown 类）如实报错 —— 不泄令牌（令牌根本没到 GitHub），但用户得到的是一条无诊断价值的失败。
- 用户可见后果：私有加速下载莫名失败；若通道**部分**透传（如剥 Accept 但留 Authorization），可能拿到错误格式的响应体被当成品落盘（与 B4-B-03 的无校验叠加）。
- 级别：P2（体验/数据完整性）；头透传失败不构成凭证风险
- 原则：52（端点语义必须实测）、21
- 证据：surface_bridge.dart:385–390；ix_download.dart:836–846（无摘要 → 未校验放行）。
- 〔待议〕：通道是否剥离头取决于用户配置的具体代理，无法静态判定；建议首次使用某通道时做一次 HEAD 探测并留痕。

## B4-B-09 Action 日志拉取的重定向循环不做 SSRF 主机校验、允许 https→http 降级 〔确证〕

- 位置：lib/domain/ix/ix_action_logs_http_io.dart:55–70（`fetchBytes` 的 while 重定向循环）
- 问题一句话：后续跳只校验 `scheme != 'http' && scheme != 'https'`，既允许 https→http 明文降级，也不调用 `IxPresign.isForbiddenHost`（同层现成函数），`apiBase` 被装配层覆盖（企业实例）或 DNS/DoH 被污染时，302 可把设备引向 `http://169.254.169.254/...` 或内网地址，响应字节被整体读入内存再尝试 unzip。
- 用户可见后果：无凭证外泄（后续跳已剥全部头，这段实现是全链路令牌纪律最好的部分），但存在内网探测与明文取内容被中间人篡改的可能；日志内容本身可能敏感（构建环境变量泄漏是 Actions 日志常见事故），被篡改的日志展示给用户即错误信息。
- 级别：P2
- 原则：44、40
- 证据：ix_action_logs_http_io.dart:60–64（仅 scheme 判断）；对照 io_net_transport.dart:71–109 与 ix_presign.dart:113–128 的完整校验 —— 三处重定向守卫三种强度，未收敛。
- 建议：抽出共享的 `safeRedirectTarget` 判定（kernel/contract 或 base），三处（io_net_transport / ix_presign / ix_action_logs_http）统一调用。

## B4-B-10 下载文件名净化到位，落盘路径穿越未发现可行路径 〔确证·无缺陷〕

- 位置：lib/domain/ix/ix_download.dart:244–312（`ogLSafeDownloadFileName`）、lib/domain/ix/ix_download_backend_io.dart:69–96（`_build` 的 directory 拼接）
- 结论：文件名侧 —— 末段截取、控制字符/分隔符剔除、`.`/`..` 拒绝、Windows 保留设备名（含 `nul.tar.gz` 首点判定）、限长保扩展名，覆盖完整；目录侧 —— `spec.folder` 只来自枚举 `IxDownloadCategory.folder`（固定五值），`downloadDirProvider` 返回值由装配层注入（OgLStorage.plan），无外部可控成分。Action 日志落盘（saveToDisk）的 fileName 由调用点用 `[^A-Za-z0-9._-]` 白名单净化（action_run_page.dart:315、action_log_page.dart:190），注入面为 `fullName`（来自 API 数据，含 `/` 已被替换）。未发现穿越路径。
- 级别：—（记录为已核验项）
- 原则：44、20

## B4-B-11 令牌纪律在 presign / 日志 / 传输三条链路上的正面结论 〔确证·正面〕

- 位置：lib/domain/ix/ix_presign_io.dart:20–70、lib/domain/ix/ix_action_logs_http_io.dart:34–58、lib/base/net/io_net_transport.dart:112–260
- 结论：① presign 第一跳 `followRedirects=false, maxRedirects=0`，Location 经 `safeRedirectTarget` 校验，第二跳不带头（令牌不出设备的核心机制成立）；② 日志拉取后续跳显式重建请求、只设 `accept: */*`，凭证头不随跳；③ IoNetTransport 对**所有**请求统一手动重定向，跨主机一律不跟随（含无凭证请求的 SSRF 防护），敏感头集合 6 种，302/303 降级 GET 时剔除 body 绑定头。三处实现相互印证，未发现令牌经 dart:io 自动跟随外泄的路径 —— 唯一敞口是 background_downloader 库路径（B4-B-01）。

## B4-B-12 `ogLGuardTokenExitDownload` 以大小写敏感的 `'authorization'` 键判令牌存在 〔确证〕

- 位置：lib/surface/app/token_exit_warning.dart:87–90（`headers['authorization']`）
- 问题一句话：HTTP 头名大小写不敏感，若任一调用点以 `'Authorization'` 传入（当前四个调用点均传小写，但该契约只靠约定维系），门禁会误判"不带令牌"直接放行。
- 用户可见后果：当前不可达（rg 确认所有调用点均小写）；属未来回归的埋雷。
- 级别：P2（防御性）
- 原则：53、18
- 证据：token_exit_warning.dart:88 `final String? auth = headers['authorization'];` 无 `toLowerCase` 归一。

## B4-B-13 分片探测 HEAD/Range 把带令牌的头发往加速通道候选地址，属知情豁免范围但无逐次留痕 〔确证·低〕

- 位置：lib/base/net/range_download_io.dart:52–120（`probe`/`_probeByRange` 应用 `spec.headers`）
- 问题一句话：私有 raw 加速场景下，探测请求（HEAD + Range GET）与正式下载同样把 Authorization 交给通道主机 —— 与下载本身同一信任决策（用户已知情接受），不构成额外外泄面，但 TOKEN-EXIT-01 留痕只发生在入队前，探测这一跳无独立记录。
- 用户可见后果：无额外风险；审计回溯时日志中的通道主机访问次数少于实际。
- 级别：P2（留痕完整性）
- 原则：12（弱相关）
- 备注：action_run_page.dart / repo_page.dart 的 README 图片预览路径（repo_page.dart:2124）同样带令牌走通道，语义与 download_proxy 文档一致。

---

## 覆盖文件清单

| 文件 | 完整读 | 结论要点 |
|---|---|---|
| lib/domain/ix/ix_download.dart（1533 行） | ✅ | B4-B-03/06/10；文件名净化是全链路最扎实的一段 |
| lib/domain/ix/ix_presign.dart（241 行） | ✅ | B4-B-04（NAT64/八进制绕过）；整体校验密度高 |
| lib/domain/ix/ix_presign_io.dart（98 行） | ✅ | B4-B-11；手动重定向正确 |
| lib/domain/ix/ix_download_backend_io.dart（279 行） | ✅ | B4-B-01/05/07/10 |
| lib/domain/ix/ix_action_logs.dart（162 行） | ✅ | 写操作不跟随重定向、不加查询参数，正确 |
| lib/domain/ix/ix_action_logs_http_io.dart（132 行） | ✅ | B4-B-09；凭证剥离正确但 SSRF/降级校验缺失 |
| lib/base/net/net_transport.dart（266 行） | ✅ | 重试纪律（幂等白名单）正确；换跳不重发凭证已修 |
| lib/base/net/io_net_transport.dart（552 行） | ✅ | B4-B-04/09；跨主机不跟随 + 敏感头 6 种，是链路最佳实现 |
| lib/base/net/range_download_io.dart（345 行） | ✅ | B4-B-06；206 三道校验到位 |
| lib/surface/app/token_exit_warning.dart（170 行） | ✅ | B4-B-12；弹窗不可关闭三重保证属实 |
| lib/surface/util/download_proxy.dart（118 行） | ✅ | 单候选无降级、私有豁免语义正确 |
| lib/surface/surface_bridge.dart（705 行，限 downloadAuthHeaders/planRepoFileDownload/resolveDownloadUrl 段精读） | ✅ | B4-B-02/08 |
| docs/NETWORK.md（154 行） | ✅ | 与代码一致性良好；§3.3"无降级"与 ogLAccelCandidates 实现吻合 |
| docs/QUALITY_STANDARD.md（93 行）/ AGENTS.md（95 行） | ✅ | 裁决依据 |
| 辅助核对（rg 抽查） | — | repo_page.dart / release_detail_page.dart / action_run_page.dart / file_preview_page.dart / gist_detail_page.dart / ix_action_logs_save_io.dart 的下载入口与净化调用点 |

## 整体评价

下载链路的**自研部分令牌纪律执行得相当好**：presign 手动第一跳、日志后续跳剥头、传输层全量手动重定向三处相互独立且方向一致，"令牌不出设备"在签名族上是成立的；文件名净化、206 防护、分片残留清理（进程内存活期内）都有实测痕迹支撑的防御代码，不是纸面工程。

真正的敞口集中在两处结构性问题：**一是安全边界外包** —— 单连接库路径（background_downloader）把重定向、截断、凭证剥离全部交给未审计的第三方库（B4-B-01/05/07），而带令牌的私有归档下载恰恰必须走这条路；**二是校验覆盖不均** —— 唯一有完整性校验的入口是 Release 附件，其余加速通道流量（可执行归档、产物）全部裸奔（B4-B-03），"如实标未校验"是诚实的，但不是防御。加上 `_downloadZip` 绕过 TOKEN-EXIT-01（B4-B-02）这一个明确的一致性缺口，本批共 1 项 P0 待议、3 项 P1、7 项 P2，无静默降级类新发现（该链条此前修复质量可见一斑）。
