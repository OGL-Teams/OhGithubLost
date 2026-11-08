# 第 1 批 · 视角 A（实现正确性）· 网络传输层审计

- 目标：`/root/OhGithubLost`，main 分支 `dfd867f`，范围 `lib/base/net/*` + `lib/kernel/contract/net_types.dart`
- 裁决依据：`docs/QUALITY_STANDARD.md`（下称「原则 N」）、`AGENTS.md`
- 纪律：只审不改；`lib/` 未改动；范围文件全部用 file_read 完整读取
- 记录方式：发现一条即刻追加，不攒批

---

## B1-A-01

- **文件:行号**：`lib/base/net/io_net_transport.dart:168-173`（调用点）、`:232-245`（函数签名与写体）、`:285-298`（`_writeBody`）
- **问题描述**：`_sendWithGuardedRedirect` 的命名参数 `Object? bodyOverride` **没有默认值**，Dart 可空可选参数缺省即 `null`；而 `_writeBody` 用 `_kUnset` 哨兵区分「未指定」（沿用 `request.body`）与「显式 null」（明确无 body）。首次调用只传 `redirectsLeft: 5`，于是 `bodyOverride == null` 被当成「明确不要 body」，`identical(null, _kUnset)` 为 false，`_writeBody` 的 `body` 取 `null`，`if (body != null)` 整块被跳过 —— **所有带 `Authorization` 头的请求，第一跳都不发送请求体**。递归时的 `nextBody = identical(bodyOverride,_kUnset) ? request.body : bodyOverride` 也因首跳为 null 而把 null 传给 307/308 后续跳，body 一路丢失。非带凭证路径（`:183` 直接 `_writeBody(req, request)`）用默认 `_kUnset`，行为正常，形成「同一请求只因有无令牌而内容不同」的分支差异。
- **修复前 vs 修复后的行为差异**：修复前，带凭证的 `PUT /repos/.../contents`（`body` 为 JSON，含 content/message/sha）、带凭证的 POST/PATCH 发出的是空体请求；修复后（把 `bodyOverride` 默认设为 `_kUnset`，或首跳显式传 `_kUnset`，并让 `nextBody` 在哨兵分支取 `request.body`）第一跳按 `NetRequest.body` 写入完整字节，307/308 同源跳转继续携带原 body，只有 302/303 降级 GET 才丢弃 body。
- **用户可见后果**：所有经 `NetBridge` 发送、带令牌的写操作（新建/更新仓库文件、创建 Release、提交评论等）静默丢失内容；服务端收到空体后返回 4xx，或以空内容创建/覆盖资源（例如把用户写的空文件当成功），用户看到「保存失败/422」或「保存成功但内容是空的」，且没有任何日志指出 body 被丢弃。
- **严重度**：P0
- **违反原则编号**：8（数据无价：用户写的内容不能丢）、15（静默降级）、42（失败如实报错，勿伪造成功）
- **是否确证**：**确证**。代码证据：`:236-238` `Object? bodyOverride,` 无默认值；`:245` `_writeBody(req, request, bodyOverride: bodyOverride);`；`:288` `Object? bodyOverride = _kUnset`；`:293-298` `if (!identical(bodyOverride, _kUnset)) body = bodyOverride; ... if (body != null) { ... }`。首跳未传参 ⇒ `bodyOverride == null` ⇒ 与哨兵不同 ⇒ 不写体，无其它分支可补偿。调用链证据（确证真实可达）：`lib/domain/gh/gh_client.dart:582` 组装 `'authorization': 'Bearer ...'`，`:592-599` 构造 `NetRequest(method: request.method, body: request.body == null ? null : jsonEncode(request.body))` 并交给 `_net.send`；`NetModule.onRegister`（`net_bridge.dart:169-186`）把 `IoNetTransport` 包进 `ResilientTransport` 注入。因此一次带令牌的 `PUT /contents` 必然进入 `hasCredential == true` 的守卫路径，body 被静默丢弃。

## B1-A-02

- **文件:行号**：`lib/base/net/io_net_transport.dart:249-255`、`:265-277`
- **问题描述**：把**所有** 3xx 都视为可跟随的重定向（`status >= 300 && status < 400`），且没有校验 `Location` 解析结果的可发送性。304 Not Modified（条件 GET 的正常响应）、300 Multiple Choices、305/306 等只要带了 `Location` 就会被重新发一次请求；其中 304/300 走「保持原方法 + 保持原 body」分支（`:265-269`），于是带凭证的 `PUT`/`POST` 条件请求遇到带 `Location` 的 304 时，会把原 body **再发一遍**到 Location 指向的路径。另外 `uri.resolve(location)` 未做 try/catch，畸形 `Location`（非法百分号转义、控制字符）抛 `FormatException`，被 `send()` 的 `on Object catch`（`:222-225`）翻译成 `NetException(unknown, '未知网络错误…')`，真实的 3xx 语义与响应体全部丢失。
- **修复前 vs 修复后的行为差异**：修复前，只有 301/302/303/307/308 之外的一切 3xx 也可能触发额外请求，`Location` 无法解析时整个请求变成「未知网络错误」；修复后，仅在白名单状态码（且 `Location` 可解析、scheme 为 http/https）时跟随，其余 3xx 与畸形 Location 一律把原响应如实交还上层。
- **用户可见后果**：条件请求（ETag / If-None-Match）命中 304 时产生多余的一次请求，极端情况下重复提交写请求体；代理返回畸形 Location 时用户看到与事实无关的「未知网络错误」，无法判断是重定向问题还是网络断开。
- **严重度**：P1（重复发 body 分支）；P2（畸形 Location 分支）
- **违反原则编号**：26（写操作要么幂等，要么防重）、16/42（不吞异常、如实报错）、20（外部数据不可信）
- **是否确证**：**确证（状态码白名单缺失、resolve 无保护可由代码直接判定；304 携带 Location 是否出现取决于服务端/代理，故该场景的用户可见后果部分标「待议」）**。代码证据：`:250` `final bool isRedirect = status >= 300 && status < 400;`；`:255` `final Uri next = uri.resolve(location);`（无异常保护）；`:265-266` `switchToGet` 只判 302/303；`:267-269` 其余状态保留原 body。

## B1-A-03

- **文件:行号**：`lib/kernel/contract/net_types.dart:206-225`（`parseRetryAfterHeader`）、`lib/base/net/net_retry.dart:71-73`、`lib/base/net/net_transport.dart:160-168`
- **问题描述**：注释承诺解析「秒数或 HTTP 日期」，实现却用 `DateTime.parse(raw)`；`DateTime.parse` 只接受 ISO-8601（如 `2026-01-01T00:00:00Z`），而 RFC 7231 §7.1.3 规定的 HTTP-date（`Wed, 21 Oct 2015 07:28:00 GMT`）会抛 `FormatException`，被 `catch (_) { return null; }` 吞掉。于是服务端以 HTTP-date 给出 `Retry-After` 时，`delayFor` 收不到 `retryAfter`，改用本地指数退避（首次 300ms±25%）。另外即便收到合法的秒数形式，`delayFor` 走 `return retryAfter > maxDelay ? maxDelay : retryAfter;`（`:72`）**完全跳过 jitter**，「Retry-After 优先 + jitter」中的 jitter 只对指数路径生效。
- **修复前 vs 修复后的行为差异**：修复前 `Retry-After: Wed, 21 Oct 2015 07:28:00 GMT` → 退避 ~300ms；修复后（用 `HttpDate.parse`，或对秒数形式叠加 ±jitter 并只保证不早于服务端要求）→ 等待服务端指定的时刻/秒数（上限 `maxDelay`），且同一时刻被限流的多个客户端不会齐刷刷同时重试。
- **用户可见后果**：429/503 带 HTTP-date 形式的 Retry-After 时，客户端几乎立刻重试，可能连续撞限流甚至触发 GitHub 滥用检测（次级限流），用户看到「操作一直失败/稍后再试」，而服务端其实已明确告知等待时间。
- **严重度**：P1
- **违反原则编号**：42（失败如实报错 / 尊重服务端事实）、AGENTS.md §5「Retry-After 优先 + jitter」；29（无退避上限地频繁重试）
- **是否确证**：**确证**。代码证据：`:214` `int.tryParse(raw.trim())`；`:219` `final target = DateTime.parse(raw);`；`:220-224` 负差/解析失败一律 `null`；`net_retry.dart:71-73` `retryAfter != null` 分支直接返回、无 `jitter` 参与；全项目无 `HttpDate` 使用点（`grep -rn "HttpDate" lib/` 为 0）。

## B1-A-04

- **文件:行号**：`lib/base/net/io_net_transport.dart:265-277`（`switchToGet` / `nextBody`）
- **问题描述**：302 被**无差别**降级为 GET，且丢弃原 body。RFC 7231 §6.4.3 的 302 只对 POST 允许「MAY change to GET」，对 PUT/PATCH/DELETE（以及本来就没 body 的 GET）应保持原方法与原 body；303 才是「一律 GET 且无 body」。这里 `status == HttpStatus.movedTemporarily || status == HttpStatus.seeOther` 把二者合并，于是带凭证的 `PUT /repos/.../contents` 收到同源 302 后，第二跳变成 `GET <Location>` 且不带 body。注意 `:242-244` 仍把原 `Content-Type`/`Content-Length` 等请求头原样重设，GET 带着写请求的头，服务端更难判别。
- **修复前 vs 修复后的行为差异**：修复前 302 的 PUT/DELETE → GET 空体，若最终 URL 返回 200 就是一次**伪造的成功**（写根本没发生）；修复后 302 对 POST 降级 GET、对其它方法保留原方法与 body，仅 303 一律降级，且降级时剥离 `Content-*`/实体头。
- **用户可见后果**：文件编辑/删除等写操作遇到同源临时重定向（GitHub/反向代理常见）时，界面显示保存成功但远端内容没变（或显示无关的资源内容），用户数据看似写入实则丢失；排查时还因「成功状态」看不到错误日志。
- **严重度**：P0
- **违反原则编号**：8（用户写的内容不能丢）、42（失败如实报错；伪造成功更糟）、41（重试/重定向不得造成语义错位）
- **是否确证**：**确证（代码语义确证；302 是否由具体端点触发取决于服务端，属外部条件）**。代码证据：`:265-266` `final bool switchToGet = status == HttpStatus.movedTemporarily || status == HttpStatus.seeOther;`；`:267-269` `nextBody = switchToGet ? null : ...`；`:271-276` 递归时 verb 用 `switchToGet ? NetMethod.get.verb : verb`。302 常量值为 302，303 为 303；无任何 `verb == 'POST'` 条件。

## B1-A-05

- **文件:行号**：`lib/base/net/net_transport.dart:124-146`（异常分支）；`lib/kernel/contract/net_types.dart:67-72`
- **问题描述**：`advanceHop()` 在 `delayFor(kind: error.kind)` **之前**执行，即失败类别是否允许重试还没判定，就已经把请求重新发到下一个镜像。于是 `NetErrorKind.tls`（证书校验失败）、`cancelled`（用户取消）、`client`（4xx 类异常）这些 `isRetryable == false` 的失败，仍会被原样重发 1..N 次（N = 已配置镜像数）；所有镜像失败后才因 `delayFor(...) == null` 而 `rethrow` 最后一次错误。TLS 错误本应「编程/信任错误不降级不重试」，`cancelled` 本应立刻停止，却被加成多次网络请求；带 `Authorization` 的请求还会被送到用户配置的第三方镜像主机（令牌随每一跳重发）。
- **修复前 vs 修复后的行为差异**：修复前 `tls`/`cancelled` 异常 → 立刻换镜像重发 N 次（无退避、无凭证剥离），最后抛回；修复后先做 `error.kind.isRetryable` 及 `retryAfter`/预算判定，仅对瞬时类（`connection`/`timeout`/`server`/`rateLimited`/`unknown`）才允许换跳或退避，不可重试类别立即 `rethrow` 且零额外请求。
- **用户可见后果**：证书错误被误报成「连接被对端关闭」类的最后一次镜像错误，真正的 TLS 原因被掩盖；用户取消操作后仍有请求在后台跑；私有仓库令牌被发往未授信的镜像主机。
- **严重度**：P1（当前 `defaultMirrorChannels` 为空、装配层未注入通道，生产路径不可达；镜像机制可经 `MirrorSelector.add` 启用，故属传输状态机的确证缺陷）
- **违反原则编号**：40（令牌只在必要的跳使用一次）、19（编程/信任错误不降级不重试）、41（只重试幂等方法之外还要判断失败类别）、24（取消了要注销/停止）
- **是否确证**：**确证（状态机顺序由代码直接判定；令牌外发的实际发生以「配置了 >0 个可用镜像」为条件）**。代码证据：`:124` `on NetException catch (error)` → `:127` `if (!mayRetry) rethrow;` → `:130` `if (advanceHop()) { continue; }` → 直到 `:134-138` 才把 `kind: error.kind` 交给 `_policy.delayFor`；`net_retry.dart:62-65` 才检查 `kind.isRetryable`；`net_types.dart:67-72` 中 `tls`/`cancelled`/`client` 不在可重试集合。

## B1-A-06

- **文件:行号**：`lib/base/net/net_transport.dart:155-182`（响应路径）、`:130-143`（异常路径）
- **问题描述**：`5xx/429 先换跳再退避` 的实现是「换跳时直接 `continue`」，完全跳过 `_policy.delayFor(...)`，因此既**不等待 `Retry-After`**，也不做指数退避、不调用 `onRetry`、不递增 `attempt`。同样地异常路径在 `advanceHop()` 成功时连 `error.retryAfter` 都不读。也就是说只要配置了 ≥1 个可用镜像，服务端给出的 `Retry-After`（如 429 要求等 60s）会被无声忽略，客户端在几毫秒内把同一请求连续打到下一个镜像；换完所有镜像才进入退避。
- **修复前 vs 修复后的行为差异**：修复前 429 + `Retry-After: 60` + 2 个镜像 → 立即连发 3 个请求（原站→镜像1→镜像2），之后才可能退避；修复后换跳也要受 `Retry-After`/退避约束（或至少在换跳前取 `retryAfter` 并 `await _sleep(delay)`，镜像切换计次但仍尊重服务端），且每次换跳都留下重试观测。
- **用户可见后果**：触发 GitHub 次级限流后不但没按服务端要求等待，反而短时间放大请求量，可能升级为滥用拦截/临时封禁；用户看到「一直转圈后失败」，而诊断统计的 `retries` 仍为 0（看不到这些隐式重发）。
- **严重度**：P1（生产默认无镜像通道，故当前不可达；`MirrorSelector.add` 启用后必现）
- **违反原则编号**：AGENTS.md §5「Retry-After 优先 + jitter」、原则 29（重试次数/频率有上限）、原则 41（只重试幂等方法，且要尊重服务端）、原则 15（降级路径必须有观测）
- **是否确证**：**确证（状态机行为由代码直接判定；实际触发以「配置了可用镜像」为条件）**。代码证据：`:156-158` `if (mayRetry && advanceHop()) { continue; }`；`continue` 之前的唯一 `delayFor` 调用在 `:162-168`（带 `retryAfter`），被跳过；`:180-182` `onRetry`/`await _sleep(delay)`/`attempt++` 同样被跳过。异常路径 `:130-132` 的 `continue` 跳过 `:134-143`。

## B1-A-07

- **文件:行号**：`lib/base/net/net_transport.dart:162-179`、`lib/base/net/net_retry.dart:22`
- **问题描述**：「重试已耗尽」这条错误对**从未重试过**的请求也会出现：① 非幂等方法（`POST`/`PUT`/`PATCH`/`DELETE`）收到 `retryableStatuses` 中的 408/429/5xx 时，`mayRetry == false` ⇒ `delayFor` 直接为 `null` ⇒ 抛 `'HTTP 503：重试已耗尽'`；② `maxAttempts == 1` 时首跳失败同样如此。异常 `NetException` 的 `statusCode`/`body` 尚在，但消息与事实相反，且 `_observer.onFailure` 不计一次失败（统计与事实不符）。
- **修复前 vs 修复后的行为差异**：修复前用户/日志看到「重试已耗尽」，误以为已经重了很多次；修复后按情形分别报「方法不幂等，未重试：HTTP 503」/「首次请求即收到 HTTP 503」，并在最终失败处调用 `onFailure`。
- **用户可见后果**：错误提示误导排查方向（用户去查重试配置而不是服务端 503），诊断页失败计数偏低。
- **严重度**：P2
- **违反原则编号**：42（失败如实报错）、38（错误信息面向用户：说发生了什么）、16（不吞异常，要转成明确结果）
- **是否确证**：**确证**。代码证据：`:162` `final delay = mayRetry ? _policy.delayFor(...) : null;`；`:170-178` `if (delay == null) throw NetException(..., 'HTTP ...：重试已耗尽', ...)`；`net_retry.dart:44` `canRetry(attemptsDone) => attemptsDone < maxAttempts`，`maxAttempts=1` 时 `delayFor(1, ...) == null`。

## B1-A-08

- **文件:行号**：`lib/base/net/io_net_transport.dart:153-225`（整个 `send`，含 `:175-185`、`:239-247`）、`lib/kernel/contract/net_types.dart:123`（`NetRequest.timeout`）
- **问题描述**：`IoNetTransport` 暴露 `connectTimeout`/`receiveTimeout` 并作用到 `openUrl`/`close`，但 **`request.timeout`（契约里明确的「单次请求超时」，默认 30s、调用方可逐请求设置）从头到尾没有被读取**；`receiveTimeout` 又硬编码为 60s，且只对 `req.close()` 与 `utf8.decoder.join()` 生效，不会覆盖 socket 建立阶段。此外 `utf8.decoder` 遇到非法 UTF-8 字节会抛 `FormatException`，被 `on Object catch` 包成 `NetException(unknown, '未知网络错误…')`，而这个 `unknown` 是 `isRetryable == true`（`net_types.dart:67-72`），于是 GET/HEAD 会在换跳/退避后反复重下同一个损坏响应。
- **修复前 vs 修复后的行为差异**：修复前逐请求 `timeout` 设置被无视；字节流损坏被当成瞬时网络故障重试（最终报「未知网络错误」）；修复后 `request.timeout` 覆盖单次请求全链路（含 socket 与读），非法编码以 `allowMalformed` 或明确的 `NetException(client/server)` 处理且不触发幂等重试。
- **用户可见后果**：`GhClient` 在 `lib/domain/gh/gh_client.dart:597` 明确传入 `timeout: const Duration(seconds: 30)`，`IoNetTransport` 却仍可能挂 60s+15s；非 UTF-8 响应（压缩/二进制误当文本）导致重试放大与误导性错误提示。
- **严重度**：P1
- **违反原则编号**：原则 5（契约先于实现：契约字段须兑现）、原则 19（编程/数据格式错误不重试）、原则 42（如实报错）
- **是否确证**：**确证（字段未使用、异常分类错误由代码直接判定；具体某次响应是否含非法字节属外部条件）**。代码证据：全文件 `request.timeout` 零引用；`:184` `.timeout(receiveTimeout)`、`:187` `.timeout(receiveTimeout)`；`:222-225` `on Object catch` → `NetException(NetErrorKind.unknown, ...)`；`net_types.dart:67-72` 把 `unknown` 列入 `isRetryable`。

## B1-A-09

- **文件:行号**：`lib/kernel/contract/net_types.dart:194-195`、`:251-252`、`lib/base/net/io_net_transport.dart:186-193`、`:334-340`
- **问题描述**：三处信息损失：① `NetResponse.bodyLength => body.length` 是 **UTF-16 码元数**，`NetStats.bytesIn` 却标注「累计接收字节」并在 `toString` 打印 `${bytesIn}B`，中文/emoji 等响应会低报字节数；② `body` 被 `utf8.decoder` 强制解码为文本，**二进制响应（Release 附件、图片、zip）不可逆地损坏**，注释声称「二进制场景由上层再解码」但原始字节早已丢失；③ `_flattenHeaders` 把多值头 `values.join(', ')` 拍成单个字符串，若某个值自带逗号（`Link: <a>; rel="next", <b>; rel="last"`、`Set-Cookie`、`Retry-After` 的重复头）则无法还原边界，大小写虽然统一小写但值内信息混淆。响应也从不填 `fromMirrorId`，令 `gh_client.dart:625` 的「/ 镜像 xx」提示永远为空。
- **修复前 vs 修复后的行为差异**：修复前观测字节数按字符计、二进制内容乱码/抛错、多值头不可分辨、镜像来源不可观测；修复后 `NetResponse` 保留 `List<int> bodyBytes`（`bodyLength` 取字节数）、`headers` 用 `Map<String, List<String>>` 或至少保留原始多值、并在 `ResilientTransport` 返回时写入 `fromMirrorId`。
- **用户可见后果**：诊断页流量统计偏低；下载/预览二进制资源得到乱码或「未知网络错误」；`Link` 分页头的逗号被误解析导致翻页错乱；镜像通道是否生效完全看不见。
- **严重度**：P1
- **违反原则编号**：原则 42（失败如实报错）、原则 15/53（端点语义/信息必须如实可观测）、原则 20（外部数据不可信，反序列化不能损坏数据）
- **是否确证**：**确证**。代码证据：`:195` `int get bodyLength => body.length;`；`net_types.dart:251-252` `/// 累计接收字节（按字符计）`/`final int bytesIn`；`:295-297` `_bytesIn += response.bodyLength`；`io_net_transport.dart:186-187` `await response.transform(utf8.decoder).join()`；`:336-338` `result[name.toLowerCase()] = values.join(', ')`；`net_transport.dart:151-153` 直接 `return response;` 无 `copyWith`/`fromMirrorId` 赋值；全项目 `fromMirrorId: ` 无写入点。

## B1-A-10

- **文件:行号**：`lib/base/net/net_dns.dart:403-413`、`:427-433`、`:255-262`、`lib/base/net/net_dns_platform_io.dart:40-72`
- **问题描述**：UDP 解析器的注释声称「随机起点 + 逐查询递增：既避免与陈旧响应串包，也避免可被离线猜测的序列」，但 `_idRandom` 是 `static final`，`_queryId` 是**实例字段**，且每次解析都通过 `RawDnsUdpChannel()` **新建一个 `UdpDnsResolver`**（`:808-812`、`:963-968`）。于是每个实例都从同一个静态随机起点 `R` 出发，`nextQueryId()` 第一次必然返回 `R+1`（掩码 16 位）：所有查询的事务 ID 完全相同且可预测。加上 `udpExchange` 只校验来源 IP、不校验源端口，也不校验响应里的 Question 段是否与查询主机名一致，同一 `serverIp` 上任何先前超时/残留的响应（甚至同网段伪造包）都能通过 `expectId == R+1` 的校验，被当作本次查询的答案。`parseAnswers` 只比较 ID 与 QR/RCODE，不比对 QNAME/QTYPE/QCLASS。
- **修复前 vs 修复后的行为差异**：修复前 `resolve('api.github.com')` 与随后所有 `resolve('raw.githubusercontent.com')` 的 DNS 报文 ID 恒为 `(R+1)&0xFFFF`，旧响应/伪造包可被错配接受；修复后每个查询用独立随机数（或把计数器提升为静态并配合端口/Question 校验），ID 与 Question 双重校验，错包一律丢弃重等。
- **用户可见后果**：域名被解析成另一域名/陈旧 IP，表现为「偶发连不上、换 DNS 也没用」或把流量导向被污染的 IP，而错误提示只说「连接失败」，极难定位。
- **严重度**：P1
- **违反原则编号**：原则 44（对外部目标保持怀疑）、原则 20（外部数据不可信）、原则 22（每个异步结果都要校验它是否仍然有效）
- **是否确证**：**确证（ID 恒定/可预测与缺少 Question 校验由代码直接判定；真实网络是否出现伪造/残留包属外部条件，故后果标为该条件下的必现结果）**。代码证据：`:405` `static final Random _idRandom = Random();`；`:407` `int _queryId = _idRandom.nextInt(0x10000);`（实例字段）；`:413` `int nextQueryId() => (++_queryId) & 0xFFFF;`；`:808-812` 与 `:963-968` 每次 `new UdpDnsResolver(...)`；`:259-262` 只比对 ID；`net_dns_platform_io.dart:59-64` 只比对 `datagram.address.address`。

## B1-A-11

- **文件:行号**：`lib/base/net/net_dns.dart:222-249`（`buildQuery`）、`:255-313`（`parseAnswers`）
- **问题描述**：解码器与编码器不对等：① `buildQuery` 固定 `QDCOUNT=1`，但 `parseAnswers` 不把 `questionCount`/`answerCount` 与报文字节数一致性做校验（无 `QDCOUNT>=1`、无 `ANCOUNT` 越界检查），遇到 truncated/malformed 响应会用 `break` 静默返回**部分或空**地址列表；② RFC 1035 允许的**名称压缩指针**在 `_skipName`（`:316-330`）里只判断 `0xC0` 掩码并返回 `cursor+2`，对于指针落在报文尾部（`cursor+1 >= packet.length`）或指向越界位置并不校验，且**不解析指针目标**，因此若答案名称是指针而后续 RR 数据紧跟其后，解析仍能工作（因为返回 `cursor+2` 恰是 RR 头），但对「指针链/指针指向更早位置」的合法报文不做边界防护；③ 只解析 A/AAAA，且 `UdpDnsResolver` 只发 `type=A`（`:428` 未传 `type`），DoH 也只请求 `type=A`（`:477`），于是注释承诺的「仅 A/AAAA」中 **AAAA 路径在真实解析里从未被使用**：自定义 DNS 永远拿不到 IPv6 地址，`IoNetTransport._applyPolicy` 的 IPv6 优先/回退逻辑实际只有系统解析会返回 v6；④ AAAA 输出用 `parts.join(':')` 不做零压缩，`DnsPlatform.isIpLiteral` 能接受，但日志/诊断里全是零膨胀地址。
- **修复前 vs 修复后的行为差异**：修复前坏报文 → 空/部分地址（上层 `_attempt` 抛「返回空结果」或拿残缺列表直连），AAAA 永不可用；修复后对截断报文明确抛 `DnsException('响应截断')` 并回退系统解析、指针做边界检查、查询同时请求 A 与 AAAA。
- **用户可见后果**：在只有 IPv6 可达的网络里，自定义 DNS 模式解析失败并总是回退系统解析（用户以为「DoH 优先」生效实则没有）；偶发坏包导致连接失败且诊断信息不足。
- **严重度**：P2
- **违反原则编号**：原则 20（外部数据不可信，坏数据要夹紧并记录）、原则 15（静默降级）、原则 42（失败如实报错）
- **是否确证**：**确证（代码结构直接判定）；「AAAA 不被查询」与「坏报文返回空列表」为可静态复现的确定性事实**。代码证据：`:230` `_writeU16(out, 1) // QDCOUNT` 与 `:247` `_writeU16(out, type)`（默认 `typeA`）；`:428` `DnsWireCodec.buildQuery(host, id: queryId)`；`:477-479` `'$endpoint${separator}name=$host&type=A'`；`:283-285`/`:289-291` `if (...) break;`；`:323-325` 指针仅 `return cursor + 2`，无边界/目标校验；`:297-309` AAAA 解码分支存在但无调用路径。

## B1-A-12

- **文件:行号**：`lib/base/net/net_dns.dart:734-773`（`applySelection`）、`:775-785`（`_sameServers`）、`:890-899`（`_remember`）、`lib/base/net/io_net_transport.dart:144-151`（`_syncPolicy`）
- **问题描述**：缓存失效判定只看「模式、preferDoh、服务器 **id 列表**」，不看 `cacheTtl`/`raceServers`/`fallbackToSystem`，也不看**同一 id 下的服务器内容**。用户在设置页修改自定义 DNS 服务器的 IP（或 DoH 端点）时，`customServer.id` 恒为 `'custom'`（见 `net_bridge.dart:84-91`），`_sameServers` 只比 `a[i].id != b[i].id`，于是 `changed == false`，`cache.clear()` 不执行：最长 `cacheTtl`（默认 5 分钟）内继续把**旧 IP 解析出的地址**返回给连接工厂。更糟的是 `_syncPolicy` 只按 `dns.policy.mode` 判断要不要重装 `connectionFactory`（`:145-150`）：`connectionFactory` 闭包捕获的是同一个 `DnsService` 引用，服务器列表变化本身不需要重装闭包（此处**不重装是正确的**），但模式不变意味着没有任何时机清理旧缓存，连接工厂下一次解析仍会命中 5 分钟前按旧 IP 写入的答案。此外 `_ipv4` 字面量（`999.999.999.999`）在 `resolve` 里被正则直接放行（`:824-825`），绕过 `DnsPlatform.isIpLiteral` 校验，成为「解析成功」的非法地址。
- **修复前 vs 修复后的行为差异**：修复前改自定义服务器地址 → 立即生效的承诺落空，5 分钟内仍连旧 IP；修复后把 `ip`/`dohUrl`/`cacheTtl`/`raceServers`/`fallbackToSystem` 一并纳入 `changed`，并在策略对象任何可变字段变化时清缓存、重装连接工厂。
- **用户可见后果**：用户为绕开 DNS 污染切换到新的解析器，界面显示「设置已保存」却继续连被污染的 IP，反复失败；填错 IP 时得到「连接失败」而非「地址不合法」。
- **严重度**：P1
- **违反原则编号**：原则 28（缓存键必须覆盖产生差异的全部维度）、原则 15（静默降级/设置看似生效实则不动）、原则 20（外部输入校验）
- **是否确证**：**确证**。代码证据：`:743-747` `picked` 用 `id` 匹配；`:750-752` `changed` 三条件；`:775-785` `_sameServers` 只比 `id`；`net_bridge.dart:84-91` `DnsServer(id: 'custom', ip: ip, ...)`；`:897` `expiresAt: DateTime.now().add(policy.cacheTtl)`；`io_net_transport.dart:145-150` `if (mode == _appliedMode) return;`；`:824` `if (_ipv4.hasMatch(host)) return <String>[host];` 且 `:1010` 正则不校验每段 ≤255。

## B1-A-13

- **文件:行号**：`lib/base/net/net_dns.dart:471-479`、`:484-516`、`:47-63`（`ogLIsUsableDohEndpoint`）
- **问题描述**：DoH 请求把 `host` 直接拼进 URL：`'$endpoint${separator}name=$host&type=A'`，既不做 `Uri.encodeQueryComponent`，也不拒绝含 `&`/`#`/空格的恶意 host；虽然 `resolve()` 在 `:830` 用 `DnsPlatform.isIpLiteral` 排除了 `host:port`，但普通主机名解析时可被 `&type=AAAA`、`#` 之类参数注入影响查询类型/截断。`parseDohJson` 也只按 `type==1` 过滤，不校验 `Answer.name` 是否等于请求的 `host`（`parseDohJson` 是静态纯函数，压根没有 `host` 参数），因此缓存/竞速场景下拿到的答案可能属于另一个域名。另外 `ogLIsUsableDohEndpoint` 只查 `scheme == https` 与 `host.isEmpty`，对 `https://user:pass@evil.example/dns-query`（内嵌凭证）、`https://127.0.0.1/...`（回环）等一律放行，与原则 44「拒绝回环/私网/元数据地址」相冲突。
- **修复前 vs 修复后的行为差异**：修复前自定义 DoH 端点可带凭证/私网地址，查询名可篡改查询串，Answer 与请求主机名不做绑定；修复后 `Uri.https(...queryParameters: ...)` 编码、校验 `Answer.name`、并在端点与解析结果两侧都拒绝回环/私网/169.254.169.254。
- **用户可见后果**：恶意或误填的 DoH 端点导致 DNS 查询结果错位（连到错误 IP）、查询参数被覆盖；私有网络地址被当作「可信解析器」，形成 SSRF 面。
- **严重度**：P2（实际触发依赖用户填写了恶意/异常端点）
- **违反原则编号**：原则 44（对外部目标保持怀疑：拒绝回环、私网与元数据地址）、原则 20（外部数据不可信）、原则 28（缓存/结果键必须覆盖产生差异的全部维度）
- **是否确证**：**确证（编码缺失、未校验 Answer.name、端点校验缺失均由代码直接判定）**。代码证据：`:475` `'$endpoint${separator}name=$host&type=A'`；`:484` `static List<String> parseDohJson(String body)`（无 host 参数）；`:503-513` 仅按 `answer['type']` 与 `_ipv4` 过滤；`:59-62` 仅校验 `https` 与 `host.isNotEmpty`。

## B1-A-14

- **文件:行号**：`lib/base/net/range_download.dart:56-78`（`OgLChunkPlan.of`）、`:52-55`（注释承诺）、`lib/base/net/range_download_io.dart:31-32`、`:107-114`
- **问题描述**：分片数算法 `count = min(connections, ceil(total / minChunkBytes))`，随后 `base = total ~/ count` 均分。当 `total` 不是 `minChunkBytes` 的整数倍时，`ceil` 把片数向上取整，均分后的 `base` 会**小于 1MB**：例如 `total = 2MB+1`、`connections=8` → `byMin=3`、`count=3`、`base=699051`，前两片各 699051B（约 0.67MB），最后一片 699051B；`total = 3MB-1` → 3 片各 1048575B；`total = 5MB+123` → 6 片各 873833B。这直接违反文件头与 AGENTS.md §5 的「分片下载每片 ≥1MB / 每片不小于 minChunkBytes」不变式。测试 `test/base/range_download_test.dart:58-64` 只断言 `3MB` 整除场景的片数，未覆盖非整除时的最小片长。
- **修复前 vs 修复后的行为差异**：修复前 2MB+1 字节的文件被切成 3 片（每片 <1MB）；修复后 `count = max(1, min(connections, total ~/ minChunkBytes))`（向下取整）⇒ 2 片（1MB + 1MB+1），或把余数并入最后一片但保证前 N-1 片 ≥minChunk；所有片长恒 ≥1MB。
- **用户可见后果**：对 2–6MB 的 Release 附件/仓库文件额外开连接、并发收益为负（每片 TCP 握手/TLS 成本占比更高），大文件并发数也偏离用户设置；不变量被破坏后，未来若有人依赖「每片 ≥1MB」做断点/续传块大小判断会写入错位数据。
- **严重度**：P2
- **违反原则编号**：AGENTS.md §5「分片下载每片 ≥1MB」、原则 53（端点语义必须实测：边界值须覆盖）、原则 32（性能问题在架构层解决）
- **是否确证**：**确证（纯函数可用固定输入复现）**。代码证据：`:66` `final int byMin = (total + minChunk - 1) ~/ minChunk;`；`:67-68` `count = maxConnections < byMin ? maxConnections : ...`；`:69` `final int base = total ~/ count;`；`:72-73` 前 `count-1` 片长度恰为 `base`。独立计算复核：`total=2097153, connections=8, minChunk=1048576` → `count=3, base=699051, 最小片=699051 < 1048576`。

## B1-A-15

- **文件:行号**：`lib/base/net/range_download_io.dart:158-178`（`finally` 清理）、`:124-137`（`Future.wait`）、`:218-231`（`_fetchPart` 写盘）
- **问题描述**：清理逻辑把「已存在的 `.partN` 一律删除」，而 `fetch` 开始时既不检查、也不删除同名遗留分片，也**不加任何互斥/单飞**。`Future.wait` 的语义是「第一个错误立即完成，但其余分片 Future 仍在后台继续跑」；于是首个失败抛出进入 `finally` 时：① 其它分片可能还在写自己的 `.partN`，删除它们会与 `IOSink` 写入竞争（Linux 上删除后写句柄仍写，Windows 上删除失败被 `catch (_)` 吞掉）；② 删除成功后后台分片仍可能重建该文件，导致磁盘留下孤儿 `.partN`；③ 若中控在旧轮失败后立刻 resume（同 `targetPath`），新一轮 `fetch` 的 `.partN` 与旧轮残留的同名文件重叠，`part.openWrite()` 默认截断写但旧轮仍可能续写，合并出长度恰好正确、内容错乱的文件。文件头承诺「任一分片失败/取消 → 删掉所有分片，不留半成品」，实际只删一次、不与后台任务同步。
- **修复前 vs 修复后的行为差异**：修复前失败后立即清理，后台分片可能残留/复写；修复后 `Future.wait` 之后 `await` 所有分片 Future 收敛（或用 `Future.wait(..., eagerError: false)` + `await Future.wait(...).catchError`），再清理；并在 `fetch` 入口加任务级互斥 + 清理遗留 `.partN`。
- **用户可见后果**：失败/取消后磁盘残留临时分片，重试下载得到损坏文件（长度校验无法发现内容错位），且 `catch (_)` 静默吞掉清理失败，用户/日志都看不到。
- **严重度**：P1
- **违反原则编号**：原则 13（每次写入要么完整生效，要么可恢复；半成品必须能被重启发现）、原则 22（每个异步结果都要校验它是否仍然有效）、原则 23（互斥闸门成对）、原则 16（不吞异常）
- **是否确证**：**确证（Dart `Future.wait` 在首个错误时不等其它 Future，且 `finally` 无等待/互斥，代码直接判定；竞态窗口是否命中取决于时序）**。代码证据：`:124` `await Future.wait<void>(<Future<void>>[...])`；`:158-178` `finally` 中仅 `if (await part.exists()) { try { await part.delete(); } catch (_) {} }`；`:218-230` 每个分片持有独立 `IOSink` 且只在自己的 `finally` 里 `close()`；`ix_download.dart:740-754` 明确注释「resume/retry 双击会创建第二个引擎 fetch，两个 fetch 并发写同一 targetPath」，说明并发 `fetch` 是已知场景（但只在中控层做了状态回合保护，未覆盖引擎层文件竞争）。

## B1-A-16

- **文件:行号**：`lib/base/net/range_download_io.dart:197-203`（非 206 分支）、`:208-217`（Content-Range 不符分支）
- **问题描述**：两个错误分支在抛 `DownloadHttpException` 前**没有 `await response.drain<void>()`**，而 `_fetchPart` 也没有任何 `try/finally` 去 `response` 或取消 `HttpClientRequest`。`dart:io` 的 `HttpClientResponse` 若不 drain/close，底层连接会一直挂起（连接池资源不归还）；`ResilientTransport`/调用方的重试会让同一 `_client` 很快堆满 8 个 `maxConnectionsPerHost`（虽然本类未设置该值，但默认有上限）。`probe` 路径（`:86`）反而做了 drain，说明这是遗漏而非设计。另外 `_rangeOf` 的正则 `r'bytes\s+(\d+)\s*-\s*(\d+)'` 未锚定结尾、未校验 `/total` 与 `total` 一致：`Content-Range: bytes 0-99/*`、甚至 `bytes 0-99 garbage/999` 都会被当成合法区间并**跳过错位校验**；头部缺失（`:211` `actual != null` 才校验）也按注释「不猜」放行，导致 CDN 返回错位区间但省略/畸形 Content-Range 时，合并出一个长度正确、内容错乱的文件（`got` 等于片长，长度校验 `:232` 拦不住）。
- **修复前 vs 修复后的行为差异**：修复前失败分支泄漏连接，206 + 缺失/畸形 Content-Range 被当作「校验通过」；修复后所有分支 drain，206 必须有合法且与请求一致的 `Content-Range`（RFC 7233 要求），否则显式抛错并清理。
- **用户可见后果**：反复失败/重试后下载器逐渐卡死（后续请求排队等连接）；多连接下载完成后文件看似成功（长度对）但内容损坏（zip/安装包校验失败或解压报错）。
- **严重度**：P1
- **违反原则编号**：原则 24（资源的开启与关闭在生命周期上对称）、原则 20（外部数据不可信，坏头部不能夹紧成「通过」）、原则 42（失败如实报错；伪造成功）
- **是否确证**：**确证（代码直接判定；错位区间能否绕过校验还取决于服务端是否省略/畸形化 Content-Range）**。代码证据：`:198-203`、`:211-216` 直接 `throw` 无 `drain`；`:86` `await response.drain<void>();` 对照；`:276-279` 正则无 `^`/`$` 与 `/total` 校验；`:211` `if (actual != null && ...)`；`:232` 仅用 `got != range.length` 兜底。

## B1-A-17

- **文件:行号**：`lib/base/net/io_net_transport.dart:163-185`（`hasCredential` 判定与自动重定向分支）、`lib/base/net/range_download_io.dart:238-245`（`_applyHeaders`）
- **问题描述**：凭证守卫只认 `authorization` 一个头名：`request.headers.keys.any((key) => key.toLowerCase() == 'authorization')`。其它携带凭证的头（`cookie`、`x-api-key`、`proxy-authorization`、`x-auth-token`、GitHub 的 `token xxx` 若放在别处）都不触发手动跟随，直接走 `req.followRedirects = true; req.maxRedirects = 5`（`:178-179`），由 `dart:io` 自动跟随并把**全部请求头原样重发到任意主机**。这等于给跨主机 302 开放了凭证外发路径 —— 与文件头「原则 40：令牌只在必要的跳使用一次」的承诺相反。另外 `NetRequest.copyWith` 只覆盖 url/headers/label，镜像改 URL 时（`:100`）原样带上 `Authorization`，`ResilientTransport` 换跳也不剥离凭证。
- **修复前 vs 修复后的行为差异**：修复前带 `cookie`/`x-api-key` 的请求遇到跨主机 302 → 自动跟随且携带全部头；带 `Authorization` 的请求换镜像 → 令牌发到第三方镜像主机；修复后把守卫改为「存在任何敏感头（含大小写归一、cookie、proxy-authorization、x-*-token/key）」或干脆**所有请求一律走手动跟随**，并在换镜像/跨源时剥离凭证头。
- **用户可见后果**：会话 cookie / API key 泄露给重定向目标或用户配置的加速镜像；私有仓库令牌经第三方主机中转，违反「令牌不出设备」的产品定位。
- **严重度**：P0（原则 40 相关；实际触发需有非 `authorization` 形式的凭证或启用了镜像，故触发条件受限，但代码路径确证）
- **违反原则编号**：原则 40（令牌只在必要的跳使用一次；重定向之后仍携带凭证是事故）、原则 39（凭证只进系统密钥库，不进第三方）、原则 43（不预置代理）、AGENTS.md §5「令牌不出设备」
- **是否确证**：**确证（守卫条件与自动跟随分支由代码直接判定）**。代码证据：`:163-165` 仅判 `== 'authorization'`；`:175-184` `else` 分支 `req.followRedirects = true; req.maxRedirects = 5;` 且 `request.headers.forEach(... req.headers.set(key, value))`；`net_transport.dart:100` `current = original.copyWith(url: mirror.url);` 保留 `headers`；`net_types.dart:146-158` `copyWith` 无凭证剥离逻辑。反证对照：`ix_presign_io.dart:26-27` 与 `ix_action_logs_http_io.dart:30-31` 都显式 `followRedirects = false`，说明跨主机 302 在本应用是真实存在的主要链路。

## B1-A-18

- **文件:行号**：`lib/base/net/io_net_transport.dart:212-225`、`:128-132`（`connectionFactory` 抛 `NetException`）
- **问题描述**：`send()` 的 `on Object catch (error)`（`:222`）会把**已经翻译好的 `NetException` 再包一层**：自定义 DNS 模式下 `_applyPolicy` 的 `connectionFactory` 在 `:128-132` 抛 `NetException(connection, 'DNS 解析后无法连接 …')`，该异常在 `openUrl`/`close` 链路中冒泡回来，被 `:222` 捕获后变成 `NetException(unknown, '未知网络错误（NetException(connection…): …）', cause: 原异常)`。而 `unknown` 是 `isRetryable`（`net_types.dart:67-72`），于是明确的 DNS 连接失败被误归类为「未知」，错误信息丢失、重试策略按未知类走。`IoDnsHttpClient.get` 抛出的 `TimeoutException` 在 `DohDnsResolver.resolve` 里也没有先归一（`:474-477` 只有 `.timeout()`），最终由 `_attemptServer` 的 `catch` 转成 `DnsException` 字符串，语义同样被抹平。
- **修复前 vs 修复后的行为差异**：修复前用户看到「未知网络错误（NetException(connection…): DNS 解析后无法连接…）」；修复后在 `on Object catch` 前先 `on NetException catch (error) { rethrow; }`（或让 `cause` 保留原 kind/status），分类与文案保持 `connection`。
- **用户可见后果**：诊断日志里「连接失败」变成「未知网络错误」，`self-test` 附加的 errno 级信息被内层字符串掩盖；用户按错误提示排查方向错误。
- **严重度**：P1
- **违反原则编号**：原则 17（用类型表达失败）、原则 16（不吞异常）、原则 42（失败如实报错）、原则 19（分类错误会导致错误重试）
- **是否确证**：**确证（异常嵌套路径由代码直接判定；是否真的由 connectionFactory 冒泡到该 catch 取决于 dart:io 实现，但 `on Object catch` 无 NetException 前置分支是确定的）**。代码证据：`:195-225` 的 catch 链顺序为 `TimeoutException`/`HandshakeException`/`TlsException`/`SocketException`/`HttpException`/`Object`，**无 `on NetException`**；`:128-132` 在 `connectionFactory` 里 `throw NetException(...)`；`net_types.dart:67-72` `unknown.isRetryable == true`。

## B1-A-19

- **文件:行号**：`lib/base/net/io_net_transport.dart:101-132`（`connectionFactory` 循环）、`:14-19`（注释「全部失败回退系统解析」）
- **问题描述**：`Socket.startConnect(host, port)` 的类型是 `Future<ConnectionTask<Socket>>`，其 Future 在**连接尝试刚开始**时即完成（真正握手结果在 `ConnectionTask.socket` 里，由 `HttpClient` 后续 await）。代码却把 `await Socket.startConnect(...).timeout(connectTimeout)` 当成「连上了这个 IP」并在 try 中直接 `return`，于是 `for (final String address in addresses)` **第一轮就返回**，后续 IP 与「全部失败 → 系统解析再试」分支（`:120-127`）永远不可达；`catch (error)` 只能捕获「无法启动连接尝试」这类早期参数错误，捕获不到 ECONNREFUSED / 黑洞 IP。IPv4 优先退化为「只试第一个 IP」，且 `lastError` 永远为 null。
- **修复前 vs 修复后的行为差异**：修复前自定义 DNS 返回 `[坏IP, 好IP]` → 只把 `ConnectionTask<坏IP>` 交给 HttpClient，握手失败后整个请求失败；修复后 `final task = await Socket.startConnect(...); return await task.socket`（或改用 `Socket.connect(...)` 并逐个 `destroy()`），失败才继续下一个地址，全失败才回退系统解析。
- **用户可见后果**：DNS 污染/解析结果首地址不可达时，自定义 DNS 与 DoH 看似生效却连不上，多地址冗余、IPv6 备胎、系统解析兜底全部失效；错误文案里的「自定义 N 地址 + 系统解析均失败」也永远是谎话（实际只试了一个）。
- **严重度**：P1
- **违反原则编号**：原则 42（失败如实报错）、原则 15（降级路径必须有触发条件）、原则 21（降级路径有观测与退出条件）
- **是否确证**：**确证（基于 dart:io `Socket.startConnect` 的公开 API 契约：`Future<ConnectionTask<Socket>>` 表示「开始连接」而非「已连接」；本环境无 `dart` 可执行文件，未能运行实测，故注明这一点）**。代码证据：`:109-118` `for (...) { try { return await Socket.startConnect(address, port).timeout(connectTimeout); } catch (error) { lastError = error; } }`；`:119-127` 兜底分支位于循环之后；`:128-132` 文案断言「自定义 ${addresses.length} 地址 + 系统解析均失败」。

## B1-A-20

- **文件:行号**：`lib/base/net/net_retry.dart:71-73`、`lib/base/net/net_transport.dart:166-167`
- **问题描述**：`delayFor` 对服务端 `Retry-After` 的处理是 `return retryAfter > maxDelay ? maxDelay : retryAfter;`，`maxDelay` 默认 8s。GitHub 次级限流 / 503 的 `Retry-After` 常为 30–3600s，一律被压成 8s，客户端随后按 `while (attempt <= maxAttempts)`（默认 3）在 8s、8s 后重试两次，全程远早于服务端允许的时刻。这与注释「**尊重服务端**：Retry-After 优先于本地指数退避（限流场景必须听话）」以及 AGENTS.md §5「Retry-After 优先 + jitter」直接矛盾：本地上限把服务端指令覆盖掉了。
- **修复前 vs 修复后的行为差异**：修复前 `Retry-After: 60` → 实际等 8s；修复后服务端值在合理安全上限内原样生效（超出上限则**停止重试并显式失败**，而不是谎报等待），并把 jitter 用在指数路径上。
- **用户可见后果**：触发 GitHub 次级限流后持续过早重试，极易升级成滥用拦截/临时封禁；用户看到「操作一直失败、请稍后再试」，而服务端其实已给出明确等待时间。
- **严重度**：P1
- **违反原则编号**：原则 42（失败如实报错、尊重服务端事实）、原则 29（重试次数/频率有上限）、AGENTS.md §5「Retry-After 优先 + jitter」
- **是否确证**：**确证**。代码证据：`:71-73` `if (retryAfter != null && retryAfter > Duration.zero) { return retryAfter > maxDelay ? maxDelay : retryAfter; }`；`:20` `this.maxDelay = const Duration(seconds: 8)`；`net_transport.dart:167` 传入 `parseRetryAfterHeader(response.headers['retry-after'])`；`gh_client.dart:797-801` 的 `_retryAfterOf` 同样把 403/429 的秒数解析出来（但那是另一条错误路径，未经 `delayFor`）。

## B1-A-21

- **文件:行号**：`lib/base/net/net_mirror.dart:31-51`（`MirrorChannel.apply`）、`:21-24`（字段注释）
- **问题描述**：`apply` 用 `url.replaceFirstMapped(regex, ...)` 拼接 `replacement`，但 `replacement` 是**用户可填的字符串**，其中 `$0` 是 Dart `replaceFirstMapped` 的「整个匹配」占位符，代码只从 `groupCount` 到 1 循环替换 `$N`，**从不处理 `$0`**。于是 `replacement = 'https://p/$0'` 时得到的是「整段原 URL」而非任何捕获组，生成的 URL 与预期完全不同。其次，反向引用替换用的是 `output.replaceAll('\$$index', match.group(index) ?? '')` —— 它把捕获组内容当作**字面量**插回 `output`，但替换发生在回调返回值里，若捕获内容本身含 `$1`/`$10` 之类的美元序列，后续 `index` 递减循环会把它再替换一次（二次展开），产生 `https://p/a$2` 之类被截断的 URL。第三，`apply` 不校验改写结果是否仍是合法 http(s) URL（`RegExp` 本身也不缓存编译错误：非法 pattern 会在 `hasMatch` 时抛 `FormatException`，`MirrorSelector.mirrorFor` 没有 try/catch，整个 `send()` 崩溃而非跳过坏通道）。
- **修复前 vs 修复后的行为差异**：修复前含 `$0` 或捕获内容含 `$N` 的通道配置得到损坏 URL，非法正则让请求直接异常终止；修复后显式支持 `$0`（或拒绝 `$0` 并报配置错误）、用一次性模板解析避免二次展开、编译与结果都做校验并跳过坏通道（留痕）。
- **用户可见后果**：用户自填加速通道后请求打到错误/畸形地址，表现为「全部请求 404/连接失败」；填错正则导致 App 的网络请求整体抛异常而不是回退直连。
- **严重度**：P2
- **违反原则编号**：原则 20（外部数据不可信，配置要夹紧并记录）、原则 15（降级路径必须有触发条件/退出条件）、原则 53（端点语义必须实测）
- **是否确证**：**确证（Dart `replaceFirstMapped` 对 `$0`/`$N` 的语义与循环替换顺序由代码直接判定；本环境无 dart 可执行文件，未跑运行时复现）**。代码证据：`:38` `final regex = _compiled(pattern);`；`:39-41` `url.replaceFirstMapped(regex, (match) {...})`；`:43-47` `for (var index = match.groupCount; index >= 1; index--) output = output.replaceAll('\$$index', match.group(index) ?? '');`（循环不含 `0`，且为多次 `replaceAll`）；`:49` `return mirrored == url ? null : mirrored;` 无 URL 合法性校验。

## B1-A-22

- **文件:行号**：`lib/base/net/io_net_transport.dart:360-378`（`IoDnsHttpClient.get`）、`lib/base/net/net_dns.dart:47-63`（`ogLIsUsableDohEndpoint`）、`:450-479`（`DohDnsResolver`）、`:797-813`（`_defaultResolver`）
- **问题描述**：「DoH 只认 https」只在**入口 URL 字符串**上校验一次。`IoDnsHttpClient.get` 用 `_client.getUrl(uri)` 后**没有设置 `req.followRedirects = false`**（只设了 `persistentConnection = false`），而 `dart:io HttpClientRequest.followRedirects` 默认为 `true`、`maxRedirects` 默认 5：一个 `https://dns.example/dns-query` 端点返回 302 到 `http://attacker/dns-query` 时，DNS 查询会以明文自动重发，查询内容与应答完全暴露给中间人；`ogLIsUsableDohEndpoint` 的注释却明确写「明文 HTTP 的 DoH 等于不设防……一律判为不可用」。此外 `DohDnsResolver` 构造只 `assert(server.dohUrl != null)`（`:456`），**不校验 https**；`_defaultResolver` 是唯一调用 `ogLIsUsableDohEndpoint` 的地方，若 `DnsService` 通过 `resolverFactory` 注入或外部直接构造 `DnsPolicy(servers: ...)`，明文 `dohUrl` 会被直接当成 DoH 使用 —— 防线有旁路。
- **修复前 vs 修复后的行为差异**：修复前入口 https 但重定向到 http 仍被跟随，且注入路径可用明文 DoH；修复后 `IoDnsHttpClient` 显式 `followRedirects = false` 并对每一跳 Location 复核 scheme/host，`DohDnsResolver.resolve` 入口再次强制 `ogLIsUsableDohEndpoint(server.dohUrl)`。
- **用户可见后果**：用户以为「DoH 优先」已加密绕过 DNS 污染，实际查询被重定向到明文第三方，DNS 答案可被任意篡改（把 GitHub 域名指向恶意 IP），且日志/自检仍显示「DoH 优先」。
- **严重度**：P0（原则 40/44 类安全边界；触发需 DoH 端点被劫持或用户填了会跳转的端点，故条件受限）
- **违反原则编号**：原则 40/AGENTS.md §5「DoH 只认 https」、原则 11（防线没有开关，不允许旁路捷径）、原则 44（对外部目标保持怀疑）、原则 15（静默降级）
- **是否确证**：**确证（代码未关闭自动重定向、DohDnsResolver 无 scheme 校验由代码直接判定；dart:io 默认 `followRedirects=true` 为公开契约，本环境无 dart 可执行文件未跑运行时复现）**。代码证据：`:366` `final HttpClientRequest req = await _client.getUrl(uri).timeout(_timeout);`；`:367-370` 只设自定义头与 `req.persistentConnection = false`，无 `followRedirects`；`:374-377` 仅按最终 `response.statusCode` 判 2xx；`net_dns.dart:456` `: assert(server.dohUrl != null, ...)`；`:472-475` `final endpoint = server.dohUrl!;` 直接拼接；`:799-801` 唯一一处 `ogLIsUsableDohEndpoint(server.dohUrl)`。

## B1-A-23

- **文件:行号**：`lib/base/net/io_net_transport.dart:174-185`（无凭证路径）、`:255-262`（`sameOrigin` 判定）
- **问题描述**：`hasCredential == false` 的请求完全交给 `dart:io` 自动跟随（`followRedirects = true; maxRedirects = 5`），**没有任何目标校验**：`Location` 可以跨主机、把 https 降级为 http、指向 `127.0.0.1` / `169.254.169.254` / 私网段，dart:io 都会照发并读取响应体。带凭证路径的 `sameOrigin` 判定（`:256-258`）也只比较 `scheme/host/port`，不做回环/私网/元数据地址拒绝，且 `next.host == uri.host` 为大小写敏感的字符串比较（`API.GITHUB.COM` vs `api.github.com` 会被判为跨主机，保守但不一致）。这与 AGENTS.md §5「SSRF 防护（拒绝回环/私网/169.254.169.254）」及原则 44 直接冲突：项目其它位置（`IxPresign.safeRedirectTarget`）有专门校验，传输层这条主链路却没有。
- **修复前 vs 修复后的行为差异**：修复前 `https://api.github.com/...` 返回 `Location: http://169.254.169.254/latest/meta-data/` → 客户端自动跟随并读回元数据内容；修复后所有重定向（含带凭证路径）都经统一白名单：仅 http/https、拒绝回环/私网/链路本地/元数据地址、拒绝 https→http 降级，越界即返回 3xx 并留痕。
- **用户可见后果**：来自 API 响应 JSON 的 URL（avatar_url / download_url / html_url，属外部数据）若被篡改或服务端被劫持，App 会把请求打到内网/云元数据服务并把响应体交给上层解析；同时 https 降为 http 会明文传输请求内容。
- **严重度**：P1
- **违反原则编号**：原则 44（对外部目标保持怀疑：拒绝回环、私网与元数据地址是下限）、原则 20（外部数据不可信）、原则 11（防线没有开关）、AGENTS.md §5「SSRF 防护」
- **是否确证**：**确证（传输层确无目标校验由代码直接判定；是否出现恶意 Location 属外部条件）**。代码证据：`:163-165` 只按 `authorization` 分流；`:178-179` `req.followRedirects = true; req.maxRedirects = 5;`；`:255-258` `final Uri next = uri.resolve(location); final bool sameOrigin = next.scheme == uri.scheme && next.host == uri.host && next.port == uri.port;`；全文件无 `isLoopback` / `isPrivate` / `169.254` / `isLinkLocal` 判定。对照 `lib/domain/ix/ix_presign_io.dart:49-57` 明确调用 `IxPresign.safeRedirectTarget(location, source)` 做协议/主机校验。

## B1-A-24

- **文件:行号**：`lib/base/net/net_dns.dart:700-707`（`_lastVia`）、`:820-884`（`resolve`）、`:983-1007`（`_race`）、`lib/base/net/io_net_transport.dart:321-331`（`_selfTestReport`）
- **问题描述**：`DnsService.resolve` **没有单飞（single-flight）**：缓存 miss 后并发的多个请求会各自发起完整解析（每个都含多服务器竞速 + DoH + 明文 UDP），且共享单个可变字段 `_lastVia` / 单键缓存。`_selfTestReport` 在任意连接失败时 `cache.clear()`，于是并发的后续请求再次 miss、再次全量解析；`DnsProbe.run()`（`:1030-1040`）读 `service.lastResolvedVia` 判断「是否已回退系统解析」时，可能读到另一个并发请求刚写的值。同理 `_race` 里胜出者 `completer.complete(value)` 后，其余 Future 仍继续跑 `_attemptServer`（甚至发起 UDP 请求），它们的失败结果被丢弃但网络流量已经发生；`remaining` 只在 `onError` 分支递减，成功分支不减，导致「全部失败」判定在部分成功时不会误触发（无误），但也意味着无人等待/取消落败者。
- **修复前 vs 修复后的行为差异**：修复前 20 个并发请求同时打 DNS，缓存刚被清就重复解析，自检报告里的 `via`/`fallback` 可能属于另一请求；修复后按 host 合并 in-flight Future，落败竞速者被取消，并把 `lastResolvedVia` 作为解析结果的一部分返回而非全局可变状态。
- **用户可见后果**：网络抖动时 DNS 请求放大（每次失败清缓存 + 并发全量解析），恢复变慢；自检/诊断页显示「未回退」而实际已回退（或相反），误导排查方向。
- **严重度**：P2
- **违反原则编号**：原则 22（每个异步结果都要校验它是否仍然有效）、原则 27（并发假设写进注释）、原则 29（无界并发/重复请求）、原则 42（如实呈现「谁给的」）
- **是否确证**：**确证（无单飞、`_lastVia` 为全局单字段、落败竞速者不被取消均由代码直接判定；错配是否发生取决于时序）**。代码证据：`:834` `final cached = cache.get(host);` 之后无 in-flight map；`:865-882` 直接 `_resolveCustom` 并 `_remember`；`:891` `_lastVia = serverId;`；`:990-995` 成功分支只 `completer.complete(value)`，无取消其它 Future；`io_net_transport.dart:322` `_dns?.cache.clear();`。

## B1-A-25

- **文件:行号**：`lib/base/net/net_dns_platform_io.dart:40-72`（`udpExchange`）、`lib/base/net/net_dns.dart:98-110`（`ogLNormalizeDnsAddress` 允许 IPv6）、`:420-433`（`UdpDnsResolver`）
- **问题描述**：`ogLNormalizeDnsAddress` 明确接受 IPv6 字面量（`[::1]`、`2606:4700::1111`），但 `udpExchange` 用 `RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)` 创建**仅 IPv4** 的 socket，随后 `socket.send(query, InternetAddress(serverIp), 53)` 把 IPv6 目标交给它 —— IPv4 socket 无法向 IPv6 地址发包，结果必然抛错/失败，用户填 IPv6 DNS 服务器永远得到「无响应（超时）」并回退系统解析。其次 `if (datagram.address.address != serverIp)` 用**字符串精确比较**：IPv6 地址存在多种合法写法（`2606:4700::1111` vs `2606:4700:0:0:0:0:0:1111`），而 `InternetAddress.address` 返回规范化形式，`serverIp` 是用户原样输入，合法响应会被判为「来源不符」而丢弃，直到超时。
- **修复前 vs 修复后的行为差异**：修复前 IPv6 DNS 服务器不可用、部分合法 IPv6 响应被丢；修复后按目标地址族绑定 `anyIPv4`/`anyIPv6`，并用 `InternetAddress` 的数值比较（或 `==` 运算符）校验来源，同时校验源端口为 53。
- **用户可见后果**：用户按运营商/DoH 文档填入 IPv6 DNS 地址，设置显示已生效但实际一直走系统解析（DNS 污染未被绕开），错误文案只说「超时」，看不出是地址族不支持。
- **严重度**：P1
- **违反原则编号**：原则 15（静默降级/开关看似生效实则不动）、原则 42（失败如实报错）、原则 4（平台差异在唯一位置裁决）
- **是否确证**：**确证（IPv4-only socket 与 IPv6 目标的不兼容、字符串比较不做地址规范化由代码与 API 契约直接判定；本环境无 dart 可执行文件，未跑 socket 实测，故异常的具体类型未确证）**。代码证据：`:46` `await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)`；`:71` `socket.send(query, InternetAddress(serverIp), 53)`；`:59-63` `if (datagram.address.address != serverIp) return;`；`net_dns.dart:99-109` `[` 分支与 `DnsPlatform.isIpLiteral(value)` 分支均接受 IPv6。

## B1-A-26

- **文件:行号**：`lib/base/net/net_transport.dart:96-109`（`advanceHop`）、`:115-183`（重试循环）、`lib/base/net/net_mirror.dart:52-54`（`_regexCache`）、`:74-79`（`MirrorSelector`）
- **问题描述**：`advanceHop()` 的「回落直连」分支只看 `current.url != original.url`，而 `triedMirrors` 在换跳过程中会持续累积。若 `MirrorSelector` 允许**运行时增改通道**（`add` / `setAllEnabled` / `restrictTo` 都是公开可变方法），或两条通道的 `apply` 对同一 URL 生成**相同镜像 URL**（不同 id、相同结果），`mirrorFor(original.url, skip: triedMirrors)` 每次都可能返回一个「新 id」，`triedMirrors.add(mirror.id)` 后 `current.url != original.url` 又成立，`advanceHop()` 恒返回 `true` → `while (attempt <= _policy.maxAttempts)` 里的 `attempt` **永不递增**（`:156-158` / `:130-132` 直接 `continue`），形成**无预算、无退避的无限请求循环**。原则 29「所有资源有上限：重试次数」在换跳路径上没有任何硬性封顶；`MirrorSelector.add` 无去重/上限，`_regexCache` 是 `static final Map` 且 `putIfAbsent` 永不淘汰，恶意/频繁改 pattern 会让缓存无界增长。
- **修复前 vs 修复后的行为差异**：修复前配置 N 个同类镜像（或运行中新增通道）可能让请求无限打下去且 `observer.retries` 始终为 0；修复后把「总换跳次数」纳入预算（例如 `maxHops = mirrors.channels.length + 1`，或让换跳也递增 `attempt`），并对 `triedMirrors`/最终 URL 双重去重、给正则缓存设上限。
- **用户可见后果**：界面长期转圈、电量与流量被持续消耗、GitHub API 配额被烧光，且诊断页看不到重试计数；这是一条「配了加速反而更糟」的放大路径。
- **严重度**：P1（生产默认通道为空，故当前不可达；`MirrorSelector.add` 启用后可由配置触发）
- **违反原则编号**：原则 29（有上限：重试次数、并发数、缓存）、原则 21（降级路径必须有退出条件）、原则 15（降级路径必须有观测）
- **是否确证**：**确证（循环不变量由代码直接判定：`:130-132`/`:156-158` 的 `continue` 之前无 `attempt++`，`:97` 的 skip 集合只按 id 去重；`MirrorSelector.add` 为公开无上限写入点）**。代码证据：`:92` `final triedMirrors = <String>{};`；`:97-102` 每次 `mirrorFor(original.url, skip: triedMirrors)` 且 `triedMirrors.add(mirror.id)`；`:104-106` 回落直连只比较 URL；`:115` `while (attempt <= _policy.maxAttempts)`；`net_mirror.dart:86` `void add(MirrorChannel channel) => _channels.add(channel);`；`:52-54` `static final Map<String, RegExp> _regexCache ... putIfAbsent(...)` 无淘汰。

## B1-A-27

- **文件:行号**：`lib/base/net/net_dns.dart:546-604`（`DnsCache`）、`:637-641`（`cacheTtl` 可变字段）、`:734-773`（`applySelection`）、`:890-899`（`_remember`）
- **问题描述**：`DnsCache.put` 的 `maxEntries == 0` 边界：先 `_entries[host] = answer` 再清过期项，若新条目本身已过期且 `maxEntries == 0`，`while` 循环会把它删掉（尚属合理），但 `maxEntries < 0` 时 `while (_entries.length > maxEntries)` 会一直成立，`soonest == null` 才 `return` —— 实际会清空全部条目且不报错，属于配置错误被静默吞掉。更实质的是 `policy.cacheTtl` 是公开可变字段（`final DnsPolicy policy` 但字段本身非 final），运行时改 TTL **不会**清缓存：`applySelection` 的 `changed` 判定不含 `cacheTtl`（已在 B1-A-12 记录），`DnsCache.get` 只按写入时算好的 `expiresAt` 判断，于是把 TTL 从 5 分钟调到 10 秒后，已有条目仍按 5 分钟生效。DNS 应答自带的 TTL（`:286-287` 读到的 `ttl` 字段）也完全未被使用，一律用 `policy.cacheTtl`，无法尊重权威服务器缓存语义。
- **修复前 vs 修复后的行为差异**：修复前改 TTL 不即时生效、坏 IP 在旧 TTL 内被反复使用；修复后 `cacheTtl` 变更纳入失效判定（或写入时记录策略版本），并取 `min(authoritative TTL, policy.cacheTtl)`。
- **用户可见后果**：用户为排查 DNS 污染把 TTL 调短，界面显示已改却仍连旧 IP 数分钟；权威 DNS 刚把域名切到新 IP，客户端仍钉在旧地址。
- **严重度**：P2
- **违反原则编号**：原则 28（缓存键/失效条件必须覆盖产生差异的全部维度）、原则 15（静默失效）、原则 19（编程/配置错误不要被吞）
- **是否确证**：**确证**。代码证据：`:573-603` `put` 直接写入后只按 `maxEntries` 淘汰；`:637-638` `Duration cacheTtl;` 可变；`:750-752` `changed` 只比较 `mode`/`preferDoh`/`picked`；`:560-569` `get` 只看 `answer.isExpiredAt(DateTime.now())`；`:286-287` 解析 RR 时读 `type`/`dataLength`，从未读取 `offset+4..+7` 的 TTL 字段；`:897` `expiresAt: DateTime.now().add(policy.cacheTtl)`。

## B1-A-28

- **文件:行号**：`lib/base/net/io_net_transport.dart:77-79`（`autoUncompress = true`）、`:186-194`（构造 `NetResponse`）、`lib/kernel/contract/net_types.dart:194-203`（`bodyLength`/`toString`）
- **问题描述**：`_applyPolicy` 设 `client.autoUncompress = true`，dart:io 会自动去掉 `Content-Encoding: gzip` 并解压响应体，但 `_flattenHeaders`（`:334-340`）把原始头原样返回 —— 于是 `NetResponse.headers['content-encoding'] == 'gzip'`，而 `NetResponse.body` 已是解压后的文本，`headers['content-length']` 仍是压缩后的字节数。`bodyLength`（`body.length`）则是**解压后的 UTF-16 码元数**，与日志里 `${bodyLength} 字符`（`gh_client.dart:623`）和 `NetStats.bytesIn`（标注 B）三者互不一致。上层若按 `content-length` 做下载进度/断点判断，会拿压缩字节数当真实长度。
- **修复前 vs 修复后的行为差异**：修复前解压后的 body 配着 gzip 头与压缩长度；修复后在解压时移除/修正 `content-encoding`/`content-length`，并让 `bodyLength` 明确是字符数（或改为字节数并保留 `bytes`），使日志与统计口径一致。
- **用户可见后果**：诊断页流量统计与实际传输字节数偏差数倍；依赖 `content-length` 的进度条/「文件是否完整」判断出现假失败或假成功。
- **严重度**：P2
- **违反原则编号**：原则 42（失败如实报错 / 观测如实）、原则 53（端点语义必须实测）、原则 15（不静默改写语义）
- **是否确证**：**确证（autoUncompress 与原样扁平化头部由代码直接判定；是否有上层依赖 content-length 需逐文件确认，故后果部分标「若」）**。代码证据：`:78` `client.autoUncompress = true;`；`:186-193` `await response.transform(utf8.decoder).join()` 与 `headers: _flattenHeaders(response.headers)`；`:334-340` `headers.forEach(...)` 原样拷贝所有头；`net_types.dart:195` `int get bodyLength => body.length;`；`:200-203` `toString()` 输出 `${bodyLength}B`。

## B1-A-29

- **文件:行号**：`lib/base/net/net_self_test.dart:24-47`（`cachedOrRun`）、`lib/base/net/io_net_transport.dart:318-331`（`_selfTestReport`）
- **问题描述**：`cachedOrRun` 的缓存是 3 个全局静态字段，且「运行自检」期间**没有 in-flight 合并**：多个请求同时连接失败时会各自跑一遍完整自检（DNS A/AAAA + 逐地址 TCP + 裸 TLS + 两条 HttpClient 探针，见 `net_self_test_impl_io.dart:19-100`），并在结束后互相覆盖 `_cachedReport`/`_cachedHost`；更糟的是 `_selfTestReport` 每次都先 `_dns?.cache.clear()`（`:322`），故意清掉 DNS 缓存，于是重试链路里的每一次失败都重复全量自检（注释却说「重试链路只自测一次」）。自检实现里 `tls.write(...)` 后只 `await tls.first`，未 `await tls.drain()`/`flush()`；`resp`/`resp2` 也不 drain（`:76-95`），依赖 `hc.close(force: true)` 兜底，属于资源生命周期不对称。
- **修复前 vs 修复后的行为差异**：修复前 N 个并发失败 → N 次并发自检 + 缓存互相覆盖；修复后按 host 合并 in-flight 自检 Future、缓存写入与 `host` 绑定，连接释放显式 drain。
- **用户可见后果**：断网时错误提示里附带的「自检报告」可能属于另一台主机（误导排查），且大量额外 TCP/TLS 探测拖慢失败反馈、耗电耗流量。
- **严重度**：P2
- **违反原则编号**：原则 22（过期/错配的异步结果必须丢弃）、原则 24（资源开启关闭对称）、原则 29（并发/重试次数有上限）、原则 42（如实报错）
- **是否确证**：**确证（静态全局缓存与无单飞由代码直接判定；错配是否发生取决于并发时序）**。代码证据：`net_self_test.dart:24-26` 三个 `static` 字段；`:35-47` 命中判断后立即 `await run(...)` 再写回，无 in-flight map；`io_net_transport.dart:322` 每次 `_dns?.cache.clear();`；`net_self_test_impl_io.dart:57-60` `tls.write(...); final first = await tls.first...; await tls.close();`（无 drain/flush）；`:76-95` `resp`/`resp2` 未 drain。

## B1-A-30

- **文件:行号**：`lib/base/net/io_net_transport.dart:239-245`、`:265-277`、`:299-315`（`_writeBody`）
- **问题描述**：302/303 降级为 GET 时只把 `bodyOverride` 置为 `null`，但递归调用仍传**同一个 `NetRequest request`**，`:242-244` 又把原始请求头（含 `Content-Type`、`Content-Length`、`Content-Encoding`、`Transfer-Encoding`，以及 `If-Match`/`If-None-Match` 等写操作条件头）原样 `set` 到新的 GET 上。`_writeBody` 只在 `body != null` 时注入默认 `Content-Type`，不会**移除**这些实体头；若调用方显式传了 `content-length`，dart:io 会把「无 body 的 GET + 非零 Content-Length」发给服务端，服务端可能一直等 body 直至超时，或直接拒绝。注释承诺「302/303 把方法降级为 GET 且不带 body」，实际只丢了字节、没丢语义。
- **修复前 vs 修复后的行为差异**：修复前 POST/PUT 的 303 → `GET Location` 携带 `Content-Length: N`、`Content-Type: application/json`、`If-Match: <sha>`；修复后降级时重建请求头集合，剔除所有实体头与写条件头，只保留 `Accept`/`Authorization`（同源）等安全头。
- **用户可见后果**：带 `content-length` 的写请求遇到 303 后第二跳挂起/被 4xx 拒绝，最终表现为「保存失败/超时」；`If-Match` 被带到 GET 上可能导致 412，错误原因与真实操作完全脱节。
- **严重度**：P1
- **违反原则编号**：原则 42（失败如实报错）、原则 40（令牌/条件头只在必要的跳使用一次）、原则 5（契约语义须兑现）
- **是否确证**：**确证（头部重设与无剔除逻辑由代码直接判定；调用方是否传 `content-length` 属外部条件，但 `Content-Type` 在 `_writeBody` 首跳写 body 时会自动注入到 `req.headers`，注意该注入发生在 `HttpClientRequest` 上而非 `request.headers`，因此严格说被重设的是调用方显式传入的实体头）**。代码证据：`:242-244` `request.headers.forEach((key, value) { req.headers.set(key, value); });`；`:267-269` `nextBody = switchToGet ? null : ...`；`:271-276` 递归仍传 `request`（无 `copyWith(headers: ...)`）；`:299-309` 只在 `body != null` 时补 `Content-Type`，无任何 `remove` 调用；`net_types.dart:146-158` `copyWith` 虽支持 `headers` 覆盖但此处未使用。

## B1-A-31

- **文件:行号**：`lib/base/net/net_bridge.dart:171-187`（装配）、`lib/kernel/contract/net_types.dart:277-333`（`NetObserver`）
- **问题描述**：当 `NetModule` 通过 `_explicit` 或 `_factory` 注入的 `inner` **本身就是 `ResilientTransport`** 时（`net_bridge.dart:178-179`），装配层直接复用它而不再包装，但 `NetBridge` 的 `observer` 仍用模块自建的 `_observer`（`:140`、`:187`）。若注入的 `ResilientTransport` 自带另一个 `NetObserver`（构造函数 `:54` 允许注入），`NetBridge.stats` 读到的将是另一个对象，永远为 0。同时 `NetObserver` 全是裸 `int` 非原子累加且无锁（`:281-312`），`ResilientTransport` 可被多个 isolate/并发请求共享，`_requests++` 虽在单 isolate 事件循环内不会撕裂，但 `onFailure` 只在**异常**路径调用（`:125`），响应路径「重试耗尽显式失败」（`:173-178`）不调用 `onFailure`，最终失败不计入 `failures`。
- **修复前 vs 修复后的行为差异**：修复前注入式装配下统计页恒为 0；429/5xx 重试耗尽后 `requests=3, retries=2, failures=0`（用户以为没失败）；修复后 `NetBridge` 从 `transport.observer` 取值，并在所有显式失败分支调用 `onFailure`。
- **用户可见后果**：诊断页/自检报告显示「0 请求 0 失败」，与界面上的报错自相矛盾；运维据此判断网络层没问题，排查方向被带偏。
- **严重度**：P2
- **违反原则编号**：原则 42（失败如实可见）、原则 15（失败必留痕）、原则 17（用类型表达失败，不让调用方忽略）
- **是否确证**：**确证**。代码证据：`net_bridge.dart:178-185` `inner is ResilientTransport ? inner : ResilientTransport(... observer: _observer ...)`；`:187` `NetBridge(transport: transport, observer: _observer, ...)`；`:110` `NetStats get stats => observer.snapshot();`；`net_transport.dart:170-178` 抛 `NetException` 前无 `_observer.onFailure(...)`；`:124-125` 仅异常路径有 `onFailure`。

## B1-A-32

- **文件:行号**：`lib/base/net/net_self_test_impl_io.dart:82-90`（带凭据头 /user 探测）、`:65-78`（裸 TLS 探针）
- **问题描述**：连接类失败后自动运行的自检会向 `https://<host>/user` **主动发送一个假令牌** `Bearer selftest-fake`，并把响应状态码写进日志。GitHub 对无效令牌的 401 请求会记入滥用/认证失败统计；断网重试链路里每次失败都可能触发一遍完整自检（见 B1-A-29），等于在故障时额外制造带 `Authorization` 的无效请求。裸 TLS 探针则硬编码 `GET /zen`、`Host: $host`（`:65-69`），把任意 host（可能包括用户配置的第三方加速域名或内网地址）当作 GitHub API 探测，报告的 `HTTP/1.1 401 ...` 会被当成「原生栈 OK」写进异常消息。
- **修复前 vs 修复后的行为差异**：修复前自动自检产生无效认证请求并把它当作诊断依据；修复后凭据头探测改为可选/显式用户触发（或只用不触发认证的端点），裸 TLS 探针只验证握手连通性、不谎称 HTTP 层结果。
- **用户可见后果**：账号侧出现不明来源的认证失败记录；用户看到的「自检报告」里混有与真实请求无关的 401/404，误判「服务端正常、客户端坏了」。
- **严重度**：P2
- **违反原则编号**：原则 39（凭证不入日志/不伪造）、原则 42（失败如实报错）、原则 15（降级路径必须有触发条件与观测）
- **是否确证**：**确证（代码直接判定：无条件发假令牌、探针路径硬编码；GitHub 是否计入统计属外部行为，故该后果标「可能」）**。代码证据：`:83-86` `final req2 = await hc.getUrl(Uri.parse('https://$host/user'))...; req2.headers.set('authorization', 'Bearer selftest-fake');`；`:87-90` `lines.add('HTTP(带凭据头 /user): ${resp2.statusCode}');`；`:65-69` `tls.write('GET /zen HTTP/1.1\r\nHost: $host\r\n...')`。

## B1-A-33

- **文件:行号**：`lib/base/net/net_transport.dart:124-140`（异常路径 `retryAfter`）、`lib/base/net/io_net_transport.dart:195-225`（所有 `throw NetException`）、`lib/kernel/contract/net_types.dart:102-103`
- **问题描述**：`NetException.retryAfter` 在传输层**无任何写入点**。`IoNetTransport.send` 的全部异常分支（TimeoutException / HandshakeException / TlsException / SocketException / HttpException / Object）都只填 `kind/message/cause`，从不解析响应头的 `Retry-After`；而 `ResilientTransport` 只在异常路径读 `error.retryAfter`（`:137`），即这个字段永远为 `null`。换句话说「429/503 响应携带 Retry-After」只有在 `inner` **正常返回 NetResponse** 时才被尊重；一旦底层把 429 变成异常（`NetErrorKind.rateLimited`），或代理在握手阶段返回带 Retry-After 的错误，服务端指令就完全丢失，只按本地指数退避重试。
- **修复前 vs 修复后的行为差异**：修复前异常形式的限流 → `retryAfter == null` → 300ms/600ms 退避；修复后在 `IoNetTransport` 拿到响应头时解析并填入 `NetException.retryAfter`，异常路径与响应路径共用 `parseRetryAfterHeader`。
- **用户可见后果**：限流异常路径下过快重试，与 B1-A-03/B1-A-20 叠加放大，可能触发 GitHub 滥用拦截。
- **严重度**：P2
- **违反原则编号**：原则 42（如实传递服务端事实）、AGENTS.md §5「Retry-After 优先」、原则 17（用类型表达失败）
- **是否确证**：**确证**。代码证据：全项目 `retryAfter:` 命名参数写入点仅 `lib/domain/gh/gh_client.dart:754` 与 `NetException` 构造定义；`io_net_transport.dart:195-225` 六个 `throw NetException(...)` 均未传 `retryAfter`/`statusCode`；`net_transport.dart:134-138` 读 `error.retryAfter`；`net_retry.dart:71-73` 在 `retryAfter != null` 时才走服务端优先分支。

## B1-A-34

- **文件:行号**：`lib/base/net/net_dns.dart:17`（`import 'net_dns_platform_io.dart'`）、`:709-715`（`supportsCustomDns`）、`:845-859`（Web 分支）；`lib/base/net/net_dns_platform_io.dart:19-23`、`:13`；`lib/base/net/net_bridge.dart:9`（`import 'io_net_transport.dart'`）、`:174-177`；`lib/base/net/range_download.dart:20-21`（`export 'range_download_io.dart'`）
- **问题描述**：`net_dns.dart` 对平台原语是**无条件 import `net_dns_platform_io.dart`**（该文件 `import 'dart:io'`），`net_self_test.dart` / `range_download.dart` / `net_bridge.dart` 同样无条件 import/export `*_io.dart`。项目声明支持 Web（AGENTS.md 首页、docs/NETWORK.md §五），但没有任何 `if (dart.library.io)` 条件导入或 `*_web.dart` 实现。因此 Web 构建要么编译失败（`dart:io` 在 Web 不可用），要么 `DnsPlatform.supportsCustomDns` 恒为 `true` —— 与 `DnsService` 注释「Web 恒为 false」「设置页会把入口说明为 Web 端不生效」以及 `NetBridge.dnsSummary` 的 `!service.supportsCustomDns` 分支完全对不上：那段 Web 提示代码在真实 Web 构建里根本走不到。
- **修复前 vs 修复后的行为差异**：修复前 Web 无法编译这套网络栈（或得到恒 true 的能力标记，设置页谎称自定义 DNS 生效）；修复后按条件导入 `net_dns_platform_web.dart`（`supportsCustomDns = false`），并把 `IoNetTransport`/`OgLRangeDownloader` 的 Web 替身显式登记。
- **用户可见后果**：Web 版本发布失败，或 Web 用户看到「自定义 DNS / DoH 优先 / 分片下载」可用却毫无效果，违反「不留看起来能选、实际静默失效的开关」。
- **严重度**：P1
- **违反原则编号**：原则 4（平台差异在唯一的位置裁决）、原则 15（静默降级/开关假生效）、原则 3（例外必须显式登记）、原则 52（空、无、未启用是三种不同的「没有」）
- **是否确证**：**确证（无 Web 条件导入/实现文件由目录与 import 语句直接判定；本环境无 Flutter SDK，未实际执行 `flutter build web`，故「编译失败」的具体报错未实测，标确定事实为「没有 Web 实现且平台标记恒 true」）**。代码证据：`ls lib/base/net/` 仅有 `*_io.dart`，无 `*_web.dart`；`net_dns.dart:17` 无条件 import；`net_dns_platform_io.dart:23` `static const bool supportsCustomDns = true;`；`net_dns.dart:715` `=> DnsPlatform.supportsCustomDns;`；`net_bridge.dart:40-44` 的 `!service.supportsCustomDns` 分支。

## B1-A-35

- **文件:行号**：`lib/base/net/net_dns.dart:474-477`（`DohDnsResolver.resolve`）、`:974-975`（`_attempt`）、`:949-970`（DoH 失败回落明文）、`lib/base/net/io_net_transport.dart:356-377`（`IoDnsHttpClient._timeout`）
- **问题描述**：DoH 单次解析存在**三层叠加超时**：`IoDnsHttpClient` 内部对 `getUrl`/`close`/`transform.join` 各设 `_timeout = 8s`（最坏 24s），`DohDnsResolver.resolve` 再 `.timeout(timeout)`（构造时传 `policy.timeout`，默认 5s），`DnsService._attempt` 又 `.timeout(policy.timeout)`（默认 5s）。外层 5s 先到时，内层 HTTP 请求只是被放弃（`Future.timeout` 不取消底层请求），`HttpClient` 里的连接继续占用；`_attemptServer` 的 `catch` 随即对**同一家**发起明文 UDP 重试（`:962-969`），于是「DoH 优先」在慢网络里几乎总是退化为明文 DNS，而诊断里只打一行 `OGL-DNS-103` info（`:956-960`）。这与「DoH 是绕开污染最稳的一条路」「不静默降级」相冲突：超时配置本身让加密通道难以胜出。
- **修复前 vs 修复后的行为差异**：修复前 DoH 请求 5s 未回 → 外层抛 TimeoutException → 立刻改发明文 UDP；修复后统一一处超时（按 `policy.timeout` 分配给整个 DoH 请求，含取消底层 socket），并把「回退明文」作为用户可见的显式降级记录。
- **用户可见后果**：受限网络里用户以为开了 DoH，实际查询仍走可被劫持的明文 53 端口；每次解析额外留一个未取消的 HTTPS 连接，慢网络下连接数累积。
- **严重度**：P2
- **违反原则编号**：原则 15（静默降级）、原则 21（降级路径必须有触发条件、观测、退出条件）、原则 24（资源开启与关闭对称）、原则 29（超时/并发有上限）
- **是否确证**：**确证（三层 timeout 与 catch 后明文重试由代码直接判定；`Future.timeout` 不取消底层 Future 是 Dart 语言契约）**。代码证据：`:477` `.timeout(timeout)`；`:975` `.timeout(policy.timeout)`；`io_net_transport.dart:356` `static const Duration _timeout = Duration(seconds: 8);`；`:366/:371/:373` 三处 `.timeout(_timeout)`；`net_dns.dart:805` `timeout: policy.timeout`（默认 `:619` 5s）；`:949-970` `catch` 后 `UdpDnsResolver(... RawDnsUdpChannel())` 重试。

## B1-A-36

- **文件:行号**：`lib/base/net/range_download_io.dart:34-96`（`probe` / `_probeByRange`）、`lib/base/net/range_download.dart:84-92`（`OgLRangeCancelToken`）
- **问题描述**：`probe` 在 `HEAD` 返回 200 且 `accept-ranges: bytes` 时直接返回 `supportsRange: true, total: length`，但**没有校验 `length` 是否为 null**；`_probeByRange` 的 206 分支同样可能 `total: null`。中控 `ix_download.dart:776-782` 用 `current.total != null && > 0` 过滤，故不会直接崩，但会把「HEAD 说支持 Range 却没给长度」的地址判为不可用并**静默换下一个候选**（`ix_download.dart:760-773` 的 debug 日志只在抛异常时打）。更实质的是 `_fetchPart` 用 `request.close()` **没有 timeout**（`:197`，对比 `probe` 各处 `.timeout(timeout)`），且取消令牌只在拿到响应后的 `await for` 里检查（`:221-224`）：若某片卡在连接/等响应头阶段，用户取消后该分片永不退出，`Future.wait` 永不完成，清理 `finally`（`:158`）也永不执行 —— 取消失效、临时文件与目标文件都留在磁盘上。
- **修复前 vs 修复后的行为差异**：修复前取消时若有分片卡在 `request.close()`，整个 `fetch` 挂死；修复后给 `getUrl`/`close`/每个 chunk 加 `request.timeout`（或 `HttpClient.connectionTimeout`）与取消订阅，并把取消检查放到等待响应头之前与之后。
- **用户可见后果**：暂停/取消下载后界面一直停在「正在取消」，磁盘残留 `.partN`，重启同一任务时可能与旧分片交错写出损坏文件。
- **严重度**：P1
- **违反原则编号**：原则 22（过期/取消的异步结果必须丢弃）、原则 24（资源生命周期对称）、原则 13（不留半成品）、原则 29（所有等待有上限）
- **是否确证**：**确证**。代码证据：`:197` `final HttpClientResponse response = await request.close();`（无 `.timeout`）；`:189-191` 只在函数入口检查一次 `cancel`；`:221-224` 取消检查位于 `await for` 内（即响应头之后）；`range_download.dart:89-91` `cancel()` 只置 bool，不通知任何等待者；`fetch` 的 `:124` `await Future.wait(...)` 等待所有分片；`:158` `finally` 在 `Future.wait` 完成后才执行。

## B1-A-37

- **文件:行号**：`lib/base/net/net_dns.dart:272-313`（`parseAnswers`）、`:316-330`（`_skipName`）
- **问题描述**：`parseAnswers` 在读取 RR 头之前只检查 `offset + 10 > packet.length`（`:283`），却用 `_readU16(packet, offset)` / `_readU16(packet, offset+8)` 直接下标访问；`_skipName` 遇到压缩指针时 `return cursor + 2`（`:323-325`），**不检查 `cursor+1` 是否越界**，也不校验指针目标偏移（`(length & 0x3F)<<8 | nextByte`）是否指向报文内合法位置，更不检查 `0x40`/`0x80` 这类保留的 label 类型位会把它当成普通长度字节（可让 `cursor` 跳过最多 63 字节后越界）。若 `questionCount` 被伪造成很大值，`_skipName` 会抛 `DnsException('响应截断')`（尚可），但 `answerCount` 很大且 `_skipName` 返回 `packet.length-1` 时，`offset+10 > packet.length` 的 `break` 能挡住 RR 头读取；真正缺的是**指针目标合法性 / 事务 ID 之外的 QR、QDCOUNT/ANCOUNT 与报文长度一致性**校验，以及 AAAA 记录值需 16 字节、A 记录 4 字节之外的 RDATA 越界已由 `:289-291` 覆盖。综合看，坏报文主要被 `break` 静默转成「部分地址列表」，而不是明确报错（同 B1-A-11）。
- **修复前 vs 修复后的行为差异**：修复前畸形/截断报文 → 空或部分地址（上层 `_attempt` 报「返回空结果」或直连残缺 IP 列表）；修复后逐字段边界校验，任何截断/非法指针都明确抛 `DnsException` 并触发系统解析回退与日志留痕。
- **用户可见后果**：偶发 DNS 坏包时表现为「连接失败」或连到不完整 IP 列表，诊断里没有「报文损坏」线索。
- **严重度**：P2
- **违反原则编号**：原则 20（外部数据不可信，坏数据夹紧回默认并记录）、原则 42（失败如实报错）、原则 44
- **是否确证**：**确证（缺少指针边界/目标校验、静默 break 由代码直接判定；具体坏包形态属外部条件）**。代码证据：`:276-278` `offset = _skipName(packet, offset) + 4;` 无整体边界检查；`:323-325` `if ((length & 0xC0) == 0xC0) { return cursor + 2; }` 无 `cursor+1 < packet.length` 与目标偏移校验；`:283-285` / `:289-291` 用 `break` 静默结束循环；`:313` `return addresses;` 不区分「0 个答案」与「报文损坏」。

---

## 待议清单（不冒充确证）

1. **待议 D-01（与 B1-A-02 相关）**：304 Not Modified 携带 `Location` 是否会在真实 GitHub API / 代理链路中出现。代码层面 3xx 全量跟随是确证缺陷，但「重复发送写请求体」的用户可见后果取决于服务端行为，需抓包验证。
2. **待议 D-02（与 B1-A-04 相关）**：`PUT /contents` 等写操作是否被服务端以 302 同源重定向。RFC 语义与代码分支确证，触发需要具体端点实测（AGENTS.md 原则 49/53 要求离线契约测试，不应只靠现场）。
3. **待议 D-03（与 B1-A-19 相关）**：本环境无 `dart`/Flutter SDK，`Socket.startConnect` 返回 `ConnectionTask` 的行为依据 dart:io 公开 API 契约判定；建议在真实设备上以 `[坏IP, 好IP]` 自定义 DNS 结果复现「只试第一个地址」。
4. **待议 D-04（与 B1-A-21 相关）**：`replaceFirstMapped` 对 `$0` 与捕获内容二次展开的具体结果需 Dart 运行时复现；代码层面缺少处理是确证的。
5. **待议 D-05（与 B1-A-34 相关）**：未执行 `flutter build web`，Web 构建的具体编译错误未实测；无 Web 实现文件与 `supportsCustomDns` 恒 true 是确证的。
6. **待议 D-06（与 B1-A-17/B1-A-22 相关）**：非 `authorization` 形式凭证（`cookie`/`x-api-key`）以及 https→http 的 DoH 重定向是否出现在当前用户配置/服务端，属外部条件；代码防线缺失是确证的。
7. **待议 D-07（与 B1-A-11/B1-A-13 相关）**：自定义 DNS 不查 AAAA 是否会导致纯 IPv6 环境完全不可用，取决于系统解析回退（`fallbackToSystem = true`）的结果；「AAAA 查询路径无调用点」是确证的。
8. **待议 D-08（与 B1-A-32 相关）**：GitHub 是否把 `Bearer selftest-fake` 的 401 计入账号异常/滥用统计，属服务端策略，未实测。

---

## 覆盖文件清单（全部 file_read 完整读取）

| # | 文件 | 行数 | 结论 |
|---|---|---|---|
| 1 | `lib/base/net/io_net_transport.dart` | 386 | 已读；B1-A-01/02/04/08/09/17/18/19/22/23/28/30/33/35 |
| 2 | `lib/base/net/net_transport.dart` | 237 | 已读；B1-A-05/06/07/26/31/33 |
| 3 | `lib/base/net/net_dns.dart` | 1069 | 已读；B1-A-10/11/12/13/24/25/27/34/35/37 |
| 4 | `lib/base/net/net_retry.dart` | 93 | 已读；B1-A-03/20/33 |
| 5 | `lib/base/net/net_mirror.dart` | 165 | 已读；B1-A-21/26 |
| 6 | `lib/base/net/range_download.dart` | 92 | 已读；B1-A-14/34/36 |
| 7 | `lib/base/net/range_download_io.dart` | 300 | 已读；B1-A-14/15/16/17/36 |
| 8 | `lib/base/net/net_bridge.dart` | 205 | 已读；B1-A-12/31/34 |
| 9 | `lib/base/net/net_self_test.dart` | 60 | 已读；B1-A-29 |
| 10 | `lib/base/net/net_self_test_impl_io.dart` | 119 | 已读；B1-A-29/32 |
| 11 | `lib/base/net/net_types.dart` | 7 | 已读（仅 re-export） |
| 12 | `lib/base/net/net_dns_platform_io.dart` | 79 | 已读；B1-A-10/25/34 |
| 13 | `lib/kernel/contract/net_types.dart` | 334 | 已读；B1-A-03/08/09/17/28/31/33 |

裁决依据：`docs/QUALITY_STANDARD.md`（93 行）、`AGENTS.md`（91 行）均已完整读取。辅助只读核验（未纳入范围计分）：`docs/NETWORK.md`、`lib/domain/gh/gh_client.dart` 相关段、`lib/domain/ix/ix_download.dart` 相关段、`lib/domain/ix/ix_presign_io.dart`、`lib/surface/util/accel.dart`、`lib/kernel/contract/download_engine.dart`、`test/base/net_test.dart`、`test/base/net_dns_test.dart`、`test/base/range_download_test.dart`。

**纪律确认**：本视角全程只写 `docs/audit_b1_a.md`；`git diff --stat -- lib/` 为空，未修改任何 `lib/` 文件（`docs/audit_b1_b.md` / `audit_b1_c.md` 为并行视角产物，非本视角写入；`docs/AUDIT_PLAN.md` 为审计前已存在）。
