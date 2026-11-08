# 第 3 批 · 视角 A（实现正确性）：GitHub API 层审计

> 基线：`/root/OhGithubLost` v12.0.0 LTS（`08e5814`）。只审不改，未改动任何 `lib/` 文件。
> 裁决依据：`docs/QUALITY_STANDARD.md`（59 条原则，全文读完）、`AGENTS.md`（95 行全文读完）、`docs/CONSISTENCY.md`（60 行全文读完）。
> 阅读纪律：`lib/domain/gh/` 全部 11 个 Dart 文件 + `lib/domain/domain_bridge.dart` gh 装配段均已用 `file_read` 完整读完（`gh_api.dart` 2222 行 / `repo_file_service.dart` 2042 行按 400 行分段读完），未用 `rg` 正则代替阅读；`rg` 仅用于定位调用方与行号复核。
> 端点语义核查：拉取 GitHub 官方 OpenAPI 描述 `descriptions/api.github.com/api.github.com.json`（14.2 MB）解析 `paths[].*.operationId` / 请求体 / 响应；对 `lock` 端点、`/readme` 的 `Accept`、`/releases/latest`、游客 `/notifications` 做匿名实测。实测受限处一律标「待议」，不冒充确证。
> 每条格式：编号 · 文件:行号 · 问题一句话 · 用户可见后果 · P0/P1/P2 · 违反原则编号 · 是否确证 + 代码证据。

---

## B3-A-01 · `lockIssue` 用了 PATCH，GitHub 官方端点是 PUT（P0，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:1699-1714`（`lockIssue`）。
- **问题一句话**：锁定 Issue 发的是 `NetMethod.patch`，而 GitHub REST `PUT /repos/{owner}/{repo}/issues/{issue_number}/lock`（operationId `issues/lock`）才是唯一合法方法；PATCH 在该路径上没有定义。
- **代码证据**：
  ```dart
  // gh_api.dart:1704-1708
  .send(GhRequest(
    path: '/repos/$fullName/issues/$number/lock',
    method: NetMethod.patch,                 // ← 应为 NetMethod.put
    body: <String, Object?>{
      if (lockReason != null && lockReason.isNotEmpty)
        'lock_reason': lockReason,
    },
    label: 'PATCH issues/$number/lock',
  ))
  ```
  官方 OpenAPI 实测解析：
  ```
  PATH /repos/{owner}/{repo}/issues/{issue_number}/lock
     PUT issues/lock    responses: ['204','403','410','404','422']
       body application/json required=False props=['lock_reason']
     DELETE issues/unlock responses: ['204','403','404']
  ```
  匿名实测（`octocat/Hello-World/issues/1/lock`，`-d '{}'`）：
  ```
  -X PATCH → 404 {"message":"Not Found", ...}
  -X PUT   → 401 {"message":"Requires authentication", ...}
  ```
  PATCH 落在 404「路由不存在」，PUT 才进入认证判定——方法错误确证，与权限无关。
- **用户可见后果**：`lib/surface/pages/issue_page.dart:366` 的「锁定」按钮经 `_runWrite`（`:173-202`）捕获 `GhNotFoundException`，必然显示「操作失败：… 不存在或无权访问」，同时 `OgLAppLog` 记 critical；Issue 永远锁不上。用户重试多少次都一样，且错误文案把方法错误误报成权限/资源问题（原则 42「失败如实报错」）。`unlockIssue`（`:1717`，DELETE）端点正确，于是「解锁」可用、「锁定」不可用，状态机单向断裂。
- **严重级别**：**P0**（四线新增功能完全不可用，且错误信息误导排查方向）。
- **违反原则**：**42**（失败如实报错 / 不伪造成功）、**52**（端点语义必须实测）、**18**（把「方法写错」兜底成 `GhAuthException`/404 的宽泛异常语义）、**17**（`Future<void>` 让调用方误以为无返回即成功）。
- **是否确证**：**确证**（官方 OpenAPI + 匿名 HTTP 实测 + 源码三证；不依赖认证态即可区分 PATCH 404 / PUT 401）。
- **幂等与失败分支**：`PUT .../lock` 官方响应 204，重复锁定已锁 Issue 返回 204（幂等），但当前实现根本到不了服务端；`lock_reason` 枚举虽由服务端校验（注释已说明 422），当前 422 会被 `_throwIfFailed` 折成 `GhAuthException` 而非结构化冲突，调用方只能看到「认证/请求失败」。修复为 `NetMethod.put` 后仍需注意：`lockReason` 为空时 body 为 `{}`（OpenAPI `required=False`，可接受）。

---

## B3-A-02 · `readmeExcerpt` 与 `readme` 共用同一缓存键，但一个要 raw 文本、一个要 JSON（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:1402-1432`（`readmeExcerpt`）、`:2029-2047`（`readme`）、`lib/domain/gh/gh_client.dart:445-496`（`ttlForPath`）、`:536-571`（缓存命中分支）、`lib/domain/gh/gh_read_cache.dart:64-73`（`_key`）。
- **问题一句话**：两个方法请求同一个 `path = '/repos/$fullName/readme'`，差别只在 `headers` 的 `accept`；而 `GhReadCache._key` 只由 `(account, path, canonicalQuery)` 组成，**不含请求头**，命中时 `GhClient.send` 直接返回缓存 body，头差异被完全忽略。
- **代码证据**：
  ```dart
  // gh_api.dart:1404-1408  readmeExcerpt：要纯文本
  final response = await client.send(GhRequest(
    path: '/repos/$fullName/readme',
    headers: const <String, String>{'accept': 'application/vnd.github.raw'},
    label: 'GET readme',
  ));
  final List<String> lines = response.body.split('\n') ...   // 直接当 Markdown 文本切片

  // gh_api.dart:2031-2034  readme：要 base64 JSON
  final object = await client.getObject('/repos/$fullName/readme', label: 'GET readme');
  final encoded = GhJson.str(object ?? ..., 'content');
  return GhContent.decodeContent(encoded, ...);
  ```
  ```dart
  // gh_client.dart:445-496：'/repos/x/readme' 命中 hasSegment('readme') → 60s
  if (hasSegment('releases') || ... || (hasSegment('readme')) || ...) {
    return const Duration(seconds: 60);
  }
  // gh_client.dart:541-556：命中即返回，**不区分 headers**
  final ({String, String})? cached = await _readCache?.get(request.path, request.query, cacheTtl);
  if (cached != null) {
    return GhResponse(statusCode: 200, body: cached.body, headers: ...);
  }
  ```
  ```dart
  // gh_read_cache.dart:64-73
  final String raw = '$account\n$path\n${_canonicalQuery(query)}';   // ← 没有 headers
  ```
  匿名实测 `Accept: application/vnd.github.raw` → `200` + `Content-Type: application/vnd.github.raw; charset=utf-8` + 纯文本 `Hello World!`；默认 `accept: application/vnd.github+json` → JSON 对象（含 `content`/`encoding`）。两种 body 形状完全不同，确证。
- **用户可见后果**：60 秒窗口内，先打开仓库页（`repo_page.dart:1050` 调 `readme()` 缓存 JSON），再进「发现」页推荐卡片（`search_page.dart:260` 调 `readmeExcerpt`），卡片会把 `{"name":"README.md","path":"README.md","sha":...,"content":"IyB..."}` 这一整串 JSON 当作 README 正文渲染成「切片」，出现 `{"name":"README.md","sha":"...` 之类的乱码小字；反向顺序则仓库页 README 因 `jsonObject == null` 而静默变空白/丢失（原则 20、28）。这是「缓存键没覆盖产生差异的全部维度」的典型。
- **严重级别**：**P1**（推荐卡片与仓库页 README 内容互相污染、时隐时现，用户会认为 README 坏了；不丢数据但展示错误）。
- **违反原则**：**28**（缓存键必须覆盖产生差异的全部维度）、**20**（外部数据不可信 / 坏数据夹紧回默认值并记录）、**15**（静默拿到错误形状）、**4**（同一抽象下平台/媒体类型差异未被裁决）。
- **是否确证**：**确证**（源码键构造 + TTL 白名单 + 命中分支 + 匿名 Accept 实测四证）。
- **补充**：`GhRequest.cacheBypass` 已存在但两个 readme 调用都没设置；`readmeExcerpt` 的 `on Object { return ''; }`（`:1430`）会把 JSON 被当文本解析出的奇怪字符串也吞成「成功但内容怪」，不留任何日志（原则 16/18）。

---

## B3-A-03 · `RepoFileService.create` / `delete` 把已编码路径再交给 `putContent` / `deleteContent`，造成二次百分号编码（P1，确证）

- **文件:行号**：`lib/domain/gh/repo_file_service.dart:671-677`、`:756-762`（调用侧预编码）、`:429-431`（`encodeForUrl`）、`lib/domain/gh/gh_api.dart:26-27`（`_ghPath`）、`:792`（`putContent`）、`:1051`（`deleteContent`）。
- **问题一句话**：服务层对目标路径调用 `RepoFilePaths.encodeForUrl` 后把编码结果当作「路径」传给 `GhApi.putContent/deleteContent`，而这两个方法内部又无条件调用 `_ghPath` → 对 `%` 再编码成 `%25`。
- **代码证据**：
  ```dart
  // repo_file_service.dart:671-674
  await api.putContent(
    fullName,
    RepoFilePaths.encodeForUrl(target),      // ← 已经逐段编码
    content: content, message: ..., branch: ref,
  );
  // repo_file_service.dart:756-759
  await api.deleteContent(
    fullName,
    RepoFilePaths.encodeForUrl(source),      // ← 同上
    ...
  );
  ```
  ```dart
  // gh_api.dart:26-27
  String _ghPath(String path) => path.split('/').map(Uri.encodeComponent).join('/');
  // gh_api.dart:792 / 1051
  path: '/repos/$fullName/contents/${_ghPath(path)}',
  ```
  `Uri.encodeComponent('%') == '%25'`，确证：`'a%2Fb'` 经第二次 `_ghPath` 变 `'a%252Fb'`。同文件 `_probePath`（`:1441`）自己拼 URL 并只用一次 `encodeForUrl`，**未**经过 `_ghPath`，因此「探测路径」与「写入路径」在同一操作里指向不同的资源。
- **用户可见后果**：目前用户新建路径被 `_segmentProblem` 限制为 `A-Za-z0-9._-`（`:520` 的 `_kAllowedSegment`），编码是恒等变换，暂不暴露；但 (a) `delete` 的 `source` 只过了 `clean`，**没有走字符白名单**，删除仓库里既有的含空格 / `#` / `?` / 中文的历史文件名时，探测命中真实文件、DELETE 却打到 `%25...` 这个不存在的路径 → 404「目标不存在或无权访问」，删除永久失败；(b) `create` 后续一旦放宽输入规则即直接写入错名文件。违反「路径逐段编码」这一确证点的**契约一致性**：同一层里出现「已编码」与「未编码」两种 `path` 语义却共用一个参数名。
- **严重级别**：**P1**（历史文件名删除功能不可用；且与「不会静默截断」的设计目标相悖）。
- **违反原则**：**9**（写前读与写落到不同远端路径，状态判断失效）、**10**（乐观锁锁的是探测到的文件，删的是另一个路径）、**28**（路径作为资源标识，编码维度不一致）、**57**（文件头注释「所有进入 URL 的路径逐段 `Uri.encodeComponent`」与实际双重编码不符）。
- **是否确证**：**确证**（两处调用 + 两处 `_ghPath` 字面代码；`Uri.encodeComponent` 语义）；实际 GitHub 对含 `%25` 路径返回 404 属标准行为，但本环境无写权限，端到端结果标**待议**（需带令牌实测）。
- **对比（正确对照）**：`GhApi.content` / `_contentNetwork` / `listDirectory` / `read` / `write` / `writeCname` / `repo_page.dart:4052` 都传**原始路径**并只经一次 `_ghPath`，路径编码在 `GhApi` 内部是自洽的；错的是 `RepoFileService` 这两处越俎代庖。

---

## B3-A-04 · `notifications` 匿名 401 触发全局 401 出口，游客模式被强制踢回登录门（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:1375-1396`（`notifications`）、`lib/domain/gh/gh_client.dart:729-740`（`_throwIfFailed` case 401）、`lib/surface/pages/search_page.dart:190-208`（发现页 feed loader）、`lib/surface/app/client_shell.dart:263-270`（登录门）。
- **问题一句话**：`notifications` 注释写「401（游客）由调用方如实展示为空/登录提示」，但 `GhClient._throwIfFailed` 对 401 无条件 `auth.markExpired(...)`，把「游客未登录」误判成「令牌失效」；发现页初始化即无条件 `unawaited(_feed!.load())`，游客一进应用就打 `/notifications`。
- **代码证据**：
  ```dart
  // gh_api.dart:1373-1374（注释与实现矛盾）
  /// 401（游客）由调用方如实展示为空/登录提示，不假装成功。
  ...
  // gh_client.dart:731-739
  case 401:
    _auth.markExpired('令牌无效或已过期，请重新授权');   // ← 不区分「无令牌」与「令牌失效」
    throw const GhAuthException('令牌无效或已过期，请重新授权', statusCode: 401);
  ```
  ```dart
  // gh_auth.dart:280-290  markExpired → _setState(GhAuthState.expired) → notifyListeners
  // client_shell.dart:263-270
  if ((_accountId == null || widget.surface.domain.auth.state == GhAuthState.expired) && !_guest) {
    return LoginPage(...);
  }
  ```
  匿名实测 `GET https://api.github.com/notifications` → `401 {"message":"Requires authentication"}`；`search_page.dart:197` 无论 `auth.isSignedIn` 与否都调用，确证。
- **用户可见后果**：用户点「跳过登录 / 游客浏览」后，外壳 `_guest=true` 本应放行，但 `_onAuthChanged` → `_check()` 会因 `_accountId == null` 与登录门判定再次生效（`client_shell.dart:263` 的 `_guest` 在 `_check()` 里被 `:127` 重置为 `false`），游客被反复弹回登录页；同时「令牌已失效」的诊断与提示是**假的**（根本没有令牌），误导用户去重新授权（原则 15/42）。这正是质量原则 52 说的「空、无、未启用是三种不同的『没有』」被混为一谈。
- **严重级别**：**P1**（游客模式不可用，且产生伪造的「令牌失效」告警）。
- **违反原则**：**52**（端点语义必须实测：游客 401 ≠ 令牌失效 401）、**42**（失败如实报错）、**15**（静默降级/误报）、**16**（不吞异常但也不该错误分类）。
- **是否确证**：**确证**（源码 401 分支 + `markExpired` + 外壳判定 + 匿名 401 实测 + feed 无条件加载）。`_check()` 中 `_guest` 被置 false 的完整条件链（`:105-130`）属装配/UI 范围，交叉验证标**待议**（本视角只读了调用点）。
- **分页 / 形状处理结论**：`notifications` 的 `jsonAsList` 用法对「数组 + 单对象错误体」做了 `items.length == 1 && containsKey('message')` 过滤（`:1393-1395`），形状处理正确；`page` / `perPage` 参数透传正确（OpenAPI `GET /notifications` 确有 `page`、`per_page`(max 50)、`all`、`participating`），但 `notifications()` **未使用 `client.paginate` 也不解析 `Link`**，且 `ttlForPath('/notifications')` 返回 `null`（不缓存），故 30 条之外的通知永远看不到、发现页也没有加载更多入口 —— **P2，确证**（`search_page.dart:197` 固定 `perPage: 30`，`_feed.load` 无分页）。此项并入本条记录，不另立编号。

---
## B3-A-05 · `transferRepo` 把异步待接受的 202 当成「转移已完成」上报成功（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:296-310`（`transferRepo`）、`lib/surface/pages/repo_page.dart:3946-3958`（调用方）。
- **问题一句话**：`POST /repos/{owner}/{repo}/transfer` 的 `202 Accepted` 对「个人仓库 → 另一个用户」只表示**转移请求已发出、等待新所有者接受**，仓库 `full_name` 此刻**并未改变**；方法返回 `Future<void>` 丢弃响应体，调用方立即弹「已转移」并退出详情页。
- **代码证据**：
  ```dart
  // gh_api.dart:296-310
  /// `POST /repos/{owner}/{repo}/transfer`，body `new_owner`；
  /// 成功返回 202，仓库 `full_name` 随之改变 —— 调用方应按"仓库已离开
  /// 当前地址"处理（刷新列表 / 退出详情页），不得继续用旧名读写。   ← 注释断言错误
  Future<void> transferRepo(String fullName, {required String newOwner}) =>
      client.send(GhRequest(
        path: '/repos/$fullName/transfer',
        method: NetMethod.post,
        body: <String, Object?>{'new_owner': newOwner},
        label: 'POST /repos/$fullName/transfer',
      )).then((_) {});                       // 202 的 body 被丢弃，无任何 pending 语义
  ```
  官方 OpenAPI（实测解析）：
  ```
  POST repos/transfer responses: ['202']
    requestBody required=True props=['new_owner','new_name','team_ids']
    description: "A transfer request will need to be accepted by the new owner when
      transferring a personal repository to another user. The response will contain
      the original `owner`, and the transfer will continue asynchronously."
    202 schema: $ref minimal-repository   ← 响应体里仍是**原 owner**
  ```
  ```dart
  // repo_page.dart:3946-3958
  await widget.surface.domain.api.transferRepo(_full, newOwner: target);
  OgLAppLog.instance.result('仓库', _t('transferred', {'owner': target}), _full);
  OgLNotifier.of(context).success(_t('transferred', {'owner': target}));   // 「已转移」
  Navigator.of(context).pop(true);                                        // 按已换址退出
  ```
- **用户可见后果**：用户输入目标账号、通过二次确认后，应用立刻显示「已转移至 X」并退出仓库页；实际上仓库仍在自己名下（需对方在 GitHub 上接受邀请），列表刷新后仓库原样出现。用户会以为操作已生效而不再跟进，甚至重复发起转移请求，或误以为数据丢了。错误方向与原则 42 相反 —— **伪造的成功**。响应体里保留的 `owner`（可用于判定 pending）被完全丢弃。
- **严重级别**：**P1**（危险操作的结果被误报，用户决策被误导；不涉及数据丢失故不列 P0）。
- **违反原则**：**42**（失败如实报错 / 不伪造成功）、**52**（端点语义必须实测：202 ≠ 完成）、**17**（`Future<void>` 无法表达 pending 状态，调用方无法区分「已完成」与「待接受」）、**12**（危险操作确认后应有明确的结果语义）。
- **是否确证**：**确证**（官方 OpenAPI `description` + 202 schema + 源码注释/调用方三证）。个人仓库→用户场景的 GitHub 站内确认流程需登录态观察，标**待议**；但「202 是异步、body 仍是原 owner」这一点由官方描述直接确证。
- **端点/请求体/失败分支其余结论**：`POST` + `new_owner` 必填 —— 与 OpenAPI 一致（**正确**）；`team_ids` / `new_name` 未暴露不影响正确性。失败分支：`_throwIfFailed` 把 403/404/422 折成 `GhAuthException`，`repo_page.dart:3960` 显示「转移失败」—— 可见，无静默（**正确**）。幂等：非幂等 POST，调用方 `_busy` 防连点（**正确**）。

---

## B3-A-06 · `getList` / `notifications` / `latestVersionOf` 依赖的 `jsonAsList` 把「非数组 / 解析失败」静默变成列表或空列表（P1，确证）

- **文件:行号**：`lib/domain/gh/gh_client.dart:326-360`（`jsonObject` / `jsonList` / `jsonAsList`）、`:679-685`（`getList`）、`lib/domain/gh/gh_api.dart:1392`（`notifications`）、`:1461`（`latestVersionOf` 的 `/tags`）、`:690-737`（`_listDirectoryNetwork` 的对照实现）。
- **问题一句话**：`gh_api.dart` 自己已在 `_listDirectoryNetwork` 里写明「`jsonAsList` 会把解析失败 / 非数组响应静默变成空列表——那正是『API 有结果却被非法抛弃』的入口」，但 `GhClient.getList` 及所有基于它的端点仍统一使用 `jsonAsList`：单个 JSON 对象会被包成 **1 条伪记录**，截断/非法 JSON 会变成 **空列表**，两者都不报错。
- **代码证据**：
  ```dart
  // gh_client.dart:336-360
  List<Map<String, dynamic>> get jsonList {
    try {
      final Object? decoded = _decode();
      if (decoded is! List) { return const <Map<String, dynamic>>[]; }   // 非数组 → 空
      return decoded.whereType<Map<Object?, Object?>>()...;
    } catch (_) { return const <Map<String, dynamic>>[]; }               // 解析失败 → 空，吞掉
  }
  List<Map<String, dynamic>> get jsonAsList {
    final asList = jsonList;
    if (asList.isNotEmpty) { return asList; }
    final asObject = jsonObject;
    return asObject == null
        ? const <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[asObject];                               // 对象 → 1 条伪记录
  }
  // gh_client.dart:679-685
  Future<List<Map<String, dynamic>>> getList(String path, ...) async {
    final response = await send(GhRequest(path: path, query: query, label: label));
    return response.jsonAsList;
  }
  ```
  对照（同一文件里已知的正确做法，`gh_api.dart:711-714`）：
  ```dart
  // ★ 严格解析：Contents API 的目录响应**必须是数组**。
  //   jsonAsList 会把解析失败 / 非数组响应静默变成空列表——那正是
  //   「API 有结果却被非法抛弃」的入口。这里自己解一次，形状不对就抛 ...
  ```
  `notifications`（`:1392-1395`）只挡了一种特例：`items.length == 1 && items.first.containsKey('message')`；其它单对象（如 `{"documentation_url": ...}`、代理改写体）仍被当通知。`latestVersionOf` 的 `/tags`（`:1461`）用 `jsonAsList`，单对象 `{...}` 会变成 `items.first` 且没有 `name` → 返回 `''`（调用方当「无版本」）。
- **用户可见后果**：`issues()` / `pulls()` / `branches()` / `labels()` / `releases()` / `starredRepos()` 等列表在网络被中间设备改写、返回 2xx 单对象错误体或截断 JSON 时，要么显示**一条标题为空的幽灵记录**，要么显示**「暂无数据」**且无任何错误面板；用户以为仓库真的没内容，重新下拉刷新也无济于事（错误被吞，不留日志）。这正是 `docs/audit_206.md` 记录的 206 截断类问题在**所有 GET 列表端点**上的残留面。
- **严重级别**：**P1**（失败不可见、错误数据被当正常数据；影响面覆盖整个列表读取）。
- **违反原则**：**15**（静默降级是最严重的缺陷）、**16**（吞异常后未转成明确结果或告警）、**20**（反序列化坏数据应夹紧回默认**并记录**）、**42**（伪造的成功/空结果）、**18**（`catch (_)` 兜底一切）。
- **是否确证**：**确证**（源码自认 + `getList` 全量使用 + 三个新增 API 的调用点）。「中间代理实际回单对象 2xx」属现场条件，标**待议**；但代码路径的形状处理缺陷无需现场即可确证。

---

## B3-A-07 · `readmeExcerpt` / `latestVersionOf` 用 `on Object` 兜底一切且不留痕，语义混淆「无」与「失败」（P2，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:1402-1432`（`readmeExcerpt` 的 `on Object { return ''; }`）、`:1437-1468`（`latestVersionOf` 的 `on Object { return null; }`）、`lib/domain/gh/gh_client.dart:729-786`（`_throwIfFailed` 的异常分类）。
- **问题一句话**：两个新增卡片 API 用 `on Object` 吞掉**全部**异常（401 令牌失效 / 403 权限 / 429 限流 / 超时 / FormatException / 编程错误），统一返回 `''` 或 `null`，既不区分「没有 README」「没有 Release」与「请求失败」，也不写一行日志。
- **代码证据**：
  ```dart
  // gh_api.dart:1428-1431
    } on Object {
      return '';                    // 401/403/429/超时/206 截断 → 全部是「没有 README」
    }
  // gh_api.dart:1446-1451
    } on GhNotFoundException {
      // 没有 Release：回退 tag。
    } on Object {
      return null;                  // 403 限流 → 直接 null，**连 /tags 回退都不走**
    }
  ```
  另有形状缺陷：`latestVersionOf` 的 `/releases/latest` 只对 `GhNotFoundException`(404) 回退 `/tags`；**403/429/5xx 直接 `return null`**，与注释「无 Release 回退 /tags」不一致。且官方 `GET /releases/latest` 明确排除 draft 与 prerelease（OpenAPI `repos/get-latest-release` responses 仅 `200`/`404`），因此「只有预发布的仓库」会 404 → 回退 `/tags` → 把一个**从未正式发布**的 tag 当成「最新版本号」显示。
- **用户可见后果**：限流触发时推荐卡片静默少一行小字，用户/日志都看不到原因；反过来，只有预发布版本的仓库被标上一个并不存在的「正式最新版本号」。排查时 `OgLLogFile` 里只有 `GhClient.send` 的一条 ERR（异常确实被记了），但领域层把分类信息全丢了 —— 「没有」与「失败」在 UI 上完全同形。
- **严重级别**：**P2**（不丢数据、不阻断主流程，但失败不可观测、版本号语义可能不实）。
- **违反原则**：**15**、**16**、**18**（兜底一切 catch）、**20**（应夹紧回默认**并记录**）、**52**（端点语义：404 有三种含义）、**42**。
- **是否确证**：**确证**（源码 `on Object` + OpenAPI `repos/get-latest-release` + 匿名实测 `octocat/Hello-World/releases/latest → 404 {"message":"Not Found"}`）。`/tags` 的 `per_page=1` 是否保证返回「最新版本」的 tag 取决于服务端排序，标**待议**。
- **补充（P2，确证）**：`readmeExcerpt` 的 `text.substring(0, cut > 0 ? cut : maxChars)` 以 UTF-16 code unit 计数并按 `' '` 找词边界；中文 README 常无空格 → `cut <= 0` → 在 `maxChars` 处硬切，可能把代理对（emoji）切成孤立代理，卡片出现替换字符；与 `gh_api.dart:586-589` 特意用 `utf8.encode(...).length` 保证字节数正确的做法不一致。

---

## B3-A-08 · `GhReadCache.clear()` 只递增纪元、从不删旧条目，每次写操作都留下一代孤儿（P2，确证）

- **文件:行号**：`lib/domain/gh/gh_read_cache.dart:171-183`（`clear`）、`:64-73`（`_key`）、`:128-153`（`put`）、`lib/domain/gh/gh_client.dart:642-646`（每次非 GET 成功都 `clear()`）。
- **问题一句话**：`clear()` 只把 `ogl.rc.epoch` 加 1 让旧条目「自然失联」，磁盘 KV 里的旧 key **永不删除**；而每次写请求成功都会触发一次 `clear()`，于是每次写都新增一整代再也不会被访问、也不会被回收的缓存条目。
- **代码证据**：
  ```dart
  // gh_read_cache.dart:171-183
  Future<void> clear() async {
    try {
      final int next = (await _epoch(refresh: true)) + 1;
      await store.write(_epochKey, '$next');       // ← 只有写入新纪元，无 keys()/remove()
      _epochMemo = next;
    } catch (...) {...}
  }
  // gh_read_cache.dart:68-72
  final int epoch = await _epoch();
  final String digest = sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  return '$_prefix.$epoch.$digest';                // ← 每次写后全部改到新命名空间
  ```
  ```dart
  // gh_client.dart:642-646
  if (request.method != NetMethod.get && response.isSuccess) {
    await _readCache?.clear();                      // 每个 PUT/PATCH/POST/DELETE 成功都调用
  }
  ```
  文件头注释亦自认：「换纪元清理：`clear()` 只递增纪元计数，旧条目自然失联（无需删除 API）」。`DiskKv.keys()` / `remove()` 在本层已有使用先例（`gh_auth.dart:220`、`:242`），并非无 API 可用。
- **用户可见后果**：长期使用（尤其批量文件操作，>200 文件分批 = 多次提交）后应用私有磁盘被只读缓存碎片持续占用，无上限、无淘汰、无诊断；磁盘写满时 `get`/`put` 的 `catch` 会把失败再降级成「缓存未命中」，用户只感到变慢而查不出原因。
- **严重级别**：**P2**（有界性问题，短期内用户无感）。
- **违反原则**：**29**（所有资源有上限：磁盘无界增长终将以崩溃收场）、**28**、**15**（失效失败静默降级）、**21**（降级路径没有退出条件）。
- **是否确证**：**确证**（`clear` / `_key` / `put` / `send` 四处源码；无删除调用）。

---

## B3-A-09 · 分支名 / 仓库名在所有非 contents 端点裸插值进 URL，未逐段编码（P2，部分待议）

- **文件:行号**：`lib/domain/gh/gh_api.dart:521`（`renameBranch`）、`:531`（`deleteBranch`）、`:1164`（`commitFiles` 的 `PATCH refs/heads/$branch`）、`:2200`（`_headShaOf` 的 `git/ref/heads/$branch`）、`lib/domain/gh/repo_file_service.dart:1721`、`:1733`；以及 `gh_api.dart` 全篇 `'/repos/$fullName/...'`（20+ 处）。
- **问题一句话**：唯一实现「路径逐段编码」的是 `_ghPath`（`:26-27`）与 `RepoFilePaths.encodeForUrl`，但**只覆盖 `contents` 端点**；分支名（`feature/x`、`fix#123`、`release%1`）与 `fullName` 在 `branches/.../rename`、`git/refs/heads/...`、`git/ref/heads/...`、`git/trees/$ref` 等处全部裸插值。
- **代码证据**：
  ```dart
  // gh_api.dart:531
  path: '/repos/$fullName/git/refs/heads/$name',
  // gh_api.dart:1164
  path: '/repos/$fullName/git/refs/heads/$branch',
  // gh_api.dart:2200
  final object = await client.getObject('/repos/$fullName/git/ref/heads/$branch');
  // gh_api.dart:26-27  ← 只被 contents 五个调用点使用
  String _ghPath(String path) => path.split('/').map(Uri.encodeComponent).join('/');
  ```
  `GhRequest.toUrl`（`gh_client.dart:273-285`）只对 `query` 做 `Uri.encodeComponent`，对 `path` 原样拼接；`#` 在 URL 中是片段分隔符、`?` 是查询分隔符、`%` 会被当转义前缀。Git ref 规则允许 `#` 与 `%`（只禁止空格、`?`、`*`、`[`、`\`、`~`、`:`、`^`、`..` 等），故 `fix#123` 是合法分支名。
- **用户可见后果**：对含 `#` / `%` 的分支执行「删除分支 / 批量提交 / 创建分支基线解析」时，请求落到被截断或错误转义的 ref 上 → 404 或操作了错的 ref；`commitFiles` 的 `expectedHeadSha` 基线解析（`:2200`）拿不到 head → 抛「无法确定分支顶端提交」，批量操作整体失败且提示与真实原因无关。
- **严重级别**：**P2**（合法但少见的分支名；`feature/foo` 这类斜杠分支 GitHub 官方端点本就接受，不受影响）。
- **违反原则**：**28**（标识维度未统一）、**42**（失败原因误导）、**9**（写前基线解析到错 ref）。
- **是否确证**：**确证**（源码中这些端点确实没有任何编码）。GitHub 对 `fix#123` 的具体响应因匿名实测触发 `403 API rate limit exceeded` 未能完成，端到端行为标**待议**（需带令牌实测）。

---

## B3-A-10 · 206 回读确认只验「远端有文件」，不验「是本次写入」；`_contentNetwork` 又吞掉 409/422（P2，确证 + 待议）

- **文件:行号**：`lib/domain/gh/gh_api.dart:811-829`（`putContent` 206 回读）、`:611-640`（`_contentNetwork`）、`:2175-2178`（`_isAbsentStatus`）、`lib/base/disk/disk_cache.dart:794-806`（`_verifyReadback`）。
- **问题一句话**：206/回执缺 sha 时的补救是「回读远端，只要 sha 非空就把 `written` 替换成远端内容」，**不比对回执里的 sha、也不比对内容**；且 `_contentNetwork` 把 409/422 一律吞成 `null`（`_isAbsentStatus`），于是「读失败」与「文件不存在」同形。
- **代码证据**：
  ```dart
  // gh_api.dart:816-829
  final bool receiptIncomplete = response.statusCode == 206;
  if (receiptIncomplete || written.sha.isEmpty) {
    final GhContent? confirmed = await _contentNetwork(fullName, path, branch: branch);
    if (confirmed != null && confirmed.sha.isNotEmpty) {
      written = confirmed;                 // ← 无条件采用**当前**远端 sha
    } else {
      throw GhAuthException('提交已发出但响应不完整（HTTP ${response.statusCode}）；'
          '无法确认远端状态，请稍后刷新查看', statusCode: response.statusCode);
    }
  }
  // gh_api.dart:632-640
  } on GhAuthException catch (error) {
    if (_isAbsentStatus(error.statusCode)) { return null; }   // 409/422 → 「读不到」
    rethrow;
  }
  // gh_api.dart:2175-2178
  static bool _isAbsentStatus(int? statusCode) =>
      statusCode == 404 || statusCode == 409 || statusCode == 422;
  ```
  `disk_cache.dart:799-801` 的 D5 `_verifyReadback(key, expectedSha)` 随后拿 `written.sha` 作期望值：若 206 与并发写叠加，回读到的是**别人**的 sha，`written.sha` 与远端一致 → 校验通过 → 引擎把远端内容入缓存并返回 `WriteOutcome.success`，用户这次写被静默判为成功。
- **用户可见后果**：普通 206 场景（本次确证点）已被正确修复 —— 「206 一律回读 + `sha.isEmpty` 也回读 + 回读不到抛带状态码异常」与 `docs/CONSISTENCY.md` §4 / `docs/audit_206.md` 完全一致，不重试 PUT、不伪造 sha，**判为正确**。残余风险只在「206 + 并发写」或「回读 409/422」出现：前者可能把别人的版本记成自己的成功；后者被折成「无法确认远端状态」，如实报错但把 422（可能是无效 ref）误描述为「响应不完整」。
- **严重级别**：**P2**（需要 206 与并发同时发生；诚实报错路径是安全的）。
- **违反原则**：**9**（写前/写后状态判定）、**10**（并发写必须被乐观锁看见）、**42**（可能伪造成功）、**52**（端点语义）。
- **是否确证**：**确证**（代码路径完整可读）。「206 + 并发写」的现场复现标**待议**（需带令牌与可控代理实测）。
- **优先肯定**：`putContent` 的 206 主修复比 `docs/audit_206.md` 描述的方案更严（对 206 无条件回读，即便截断体里恰好带 sha 也不采信），且**未在 `putContent` 内调用 `cache.invalidate`**（`:831-837` 明示防 `RepositoryCache._writeLocked` 自锁死锁），实现正确。

---
## B3-A-11 · 启动期 D8 重放定时器 3 次空转后永久自停，运行中入队的写再也不会被重放（P1，确证）

- **文件:行号**：`lib/domain/domain_bridge.dart:207-250`（`GhModule.onRegister` 的 `Timer.periodic` 重放）、`:253-270`（启动时那一次 `replayPending`）。
- **问题一句话**：`idleTicks >= 3` 后 `timer.cancel()` 是**不可恢复**的停止，而注释写「常驻定时器只在有待办时有意义」；应用启动后 90 秒（3 × 30s 空转）就永久取消，此后任何写入失败进入 D8 待同步队列都没有重放触发点（没有新写触发、没有队列监听、没有下次定时器）。
- **代码证据**：
  ```dart
  // domain_bridge.dart:210-221
  var idleTicks = 0;
  bool replayInFlight = false;
  Timer.periodic(const Duration(seconds: 30), (Timer timer) {
    if (idleTicks >= 3) {
      timer.cancel();                    // ← 永久停，无 restart / 无订阅入队事件
      return;
    }
    if (replayInFlight) { return; }
    replayInFlight = true;
    unawaited(base.disk.cache.replayPending().then((outcomes) {
      replayInFlight = false;
      if (outcomes.isEmpty) { idleTicks++; return; }   // 空转累加，无外部复位路径
      idleTicks = 0;
      ...
  ```
  注释自述目标（`:203-206`）：「运行中每 30s 再查一次队列：此前只在启动时重放，运行中失败的任务会一直挂在『待同步』里（用户看到的就是『提交入队后迟迟不成功』）」—— 自停后**恰恰回到这个 bug**。`rg` 全库无其它 `replayPending()` 调用点，无 `DiskJournal` 变更通知订阅。
- **用户可见后果**：用户开着应用超过 1.5 分钟后遇到断网/409 失败，写入进入「待同步」队列并如实显示，但直到**重启应用**前永远不会自动补做；用户看到「提交入队后迟迟不成功」，手动重试又可能造成重复提交（原则 26 防重依赖 D8 队列正确收尾）。这是本次确证点之外、装配段里最实的实现倒退。
- **严重级别**：**P1**（数据提交可靠性受损，用户需重启才恢复；不丢数据因为队列落盘，故不列 P0）。
- **违反原则**：**13**（半成品状态必须留有痕迹**并能被重启发现**；此处连运行中发现都做不到）、**21**（降级路径必须有退出条件 —— 有退出但没有**重新进入**条件）、**26**（写操作幂等/防重依赖可靠重放）、**15**（静默停摆）。
- **是否确证**：**确证**（`timer.cancel` 无恢复路径 + 全库无其它重放入口 + `replayPending` 的触发仅此两处）。
- **附带缺陷（P2，确证）**：同一 `.then(...).catchError(...).catchError(...)` 链里，第一个 `catchError` **没有**复位 `replayInFlight`，第二个 `catchError` 才复位；由于第一个 handler 本身不抛，第二个 `catchError` 挂在「已成功处理的 Future」上**不会执行** → 一次 `replayPending()` 抛异常后 `replayInFlight` 永远为 `true`，之后每个 30s tick 都在 `if (replayInFlight) return;` 处返回，`idleTicks` 也不再增长，定时器空转到进程结束。注释「B2-B-19：异常路径同样复位防重入标志」与实际生效路径相反。违反原则 **23**（互斥闸门成对且同所有者）、**15**。
  ```dart
  // domain_bridge.dart:241-252
  }).catchError((Object error) {          // ← 这个 handler 生效
    context.diagnostics.warn(...);        // ← 没有 replayInFlight = false
  }).catchError((Object error) {          // ← 前一步已正常返回，永不执行
    replayInFlight = false;               // ← 复位代码在死路径上
    ...
  }),
  ```
  另：启动期那次 `replayPending().then(...)` 里 `replayInFlight = false`（`:254`）与定时器**共享同一标志但不属于同一次重放**，会在定时器重放仍在途时把标志清零，可能放行第二个并发重放（原则 23）。

---

## B3-A-12 · `_contentNetwork` 里 `__list` 分支是永不触发的死代码；目录读取靠 `getObject` 返回 `null` 兜底（P2，确证）

- **文件:行号**：`lib/domain/gh/gh_api.dart:626-630`（`_contentNetwork`）、`lib/domain/gh/gh_client.dart:326-334`（`getObject` → `jsonObject`）。
- **问题一句话**：`_contentNetwork` 判断 `object.containsKey('__list')` 以识别「目录返回数组」，但 `GhResponse.jsonObject` 对数组响应只会返回 `null`，全库没有任何地方产生 `__list` 键。
- **代码证据**：
  ```dart
  // gh_api.dart:626-630
  if (object == null) { return null; }
  // 目录返回数组，这里只取条目信息。
  if (object.containsKey('__list')) { return null; }   // ← 死分支
  return GhContent.fromJson(object);
  // gh_client.dart:326-334
  Map<String, dynamic>? get jsonObject {
    try {
      final Object? decoded = _decode();
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;  // 数组 → null
    } catch (_) { return null; }
  }
  ```
  `rg -n '__list' lib test` 全库仅此 1 处命中，确证无生产者。
- **用户可见后果**：当前行为**恰好正确**（目录 → `getObject` 返回 `null` → `_contentNetwork` 返回 `null`），但注释与代码在向后来者撒谎：维护者若照「`__list` 标记」的假设去改 `GhClient.getObject`（例如把数组包成 `{'__list': ...}`），或反过来依赖 `object != null` 就意味着「是文件」，都会引入误判；而且 `getObject` 把「截断 JSON / 非法 JSON / 数组 / 空 body」**全部**折成同一个 `null`，`_contentNetwork` 无法区分「这是目录」与「响应被代理改写」，于是 `GhApi.content()` 对坏数据静默返回 `null`（上层显示「文件不存在」），与 `read()` 里明确抛 `GhAuthException('目录/内容响应解析失败')` 的严格策略不一致。
- **严重级别**：**P2**（当前无功能故障，属死代码 + 形状语义不一致）。
- **违反原则**：**55**（死代码零容忍 / 过时白名单是假情报）、**20**（坏数据夹紧回默认**并记录**）、**42**（伪造的「不存在」）、**16**。
- **是否确证**：**确证**（`rg` 全库唯一命中 + `jsonObject` 语义）。
- **对照（正确）**：`_listDirectoryNetwork`（`:690-737`）自己 `jsonDecode(response.body)` 并在 `decoded is! List` 时 `throw FormatException`，还校验非对象条目数并写 `OgLLogFile.line(..., level: 'ERR')` —— 404 严格数组解析与 `GhNotFoundException.body` 这一确证点**完全符合规范**：`gh_client.dart:779` 传 `_snippet(response.body)`，`gh_api.dart:693-707` 用 `error.body` 区分「仓库确实为空」与「分支失效/无权限」，其余 404 记 WARN 后 `rethrow`；`GhNotFoundException` 类（`:133-148`）保留 `path` + `body` 且 `toString` 带 body。**判为正确，无发现**。

---

## B3-A-13 · `read()` 的空文件识别依赖 `parsed.size == 0`，但 `GhContent.fromJson` 已把空文件 `text` 置为 `''`，缩进/注释与实现存在双重判定（P2，确证 / 低优先）

- **文件:行号**：`lib/domain/gh/gh_api.dart:2108-2125`（`read` 的 `text == null` 分支）、`lib/domain/gh/gh_models.dart:618-641`（`GhContent.fromJson`）。
- **问题一句话**：`read()` 在 `text == null` 时用 `size == 0 && sha.isNotEmpty` 把空文件补成 `''`，但 `GhContent.fromJson` 已经对「非目录 + size==0」返回 `text: ''`；真正会走到该补充分支的只有「目录」或「sha 为空但 size==0」等异常形状。
- **代码证据**：
  ```dart
  // gh_models.dart:635-637
  text: hasBody ? GhContent.decodeContent(encoded, encoding)
                : (!isDirectory && size == 0 ? '' : null),
  // gh_api.dart:2114-2123
  if (text == null) {
    if (!parsed.isDirectory && parsed.size == 0 && parsed.sha.isNotEmpty) {
      text = '';
    } else {
      throw const GhAuthException('远端文件存在但内容不可读…', statusCode: 200);
    }
  }
  ```
- **用户可见后果**：当前行为正确（空文件与「读不到」被区分，D1 不会误判为「远端不存在」）。风险在于：`decodeContent` 对非法 base64 返回 `null`（`gh_models.dart:660-668`），此时 `size > 0` → 抛「为防覆盖已阻止写入」，**如实报错且安全**；但错误信息把「base64 损坏」说成「Blobs 回退失败或响应被截断」，与 `_isTooLarge` 判断（`size > _contentSizeLimit`）混在一起，排查方向略有偏差。
- **严重级别**：**P2**（仅可维护性/诊断精度）。
- **违反原则**：**54**（注释解释为什么）、**42**（错误原因描述不精确）、**58**（自我勘误）。
- **是否确证**：**确证**（两处源码对照；`read()` 的 else 分支抛异常，无静默覆盖，安全）。

---

## B3-A-14 · `tree(truncated)` 在 `RepoFileService._scanDirectory` 拒绝执行，但 `GhApi.tree()` 本身与页面调用点的处理不一致（P1，确证 + 待议）

- **文件:行号**：`lib/domain/gh/repo_file_service.dart:1465-1480`（`_scanDirectory`）、`lib/domain/gh/gh_api.dart:542-565`（`tree`）、`:2184-2195`（`_defaultBranchOf` memo）、`lib/surface/pages/repo_page.dart:1644-1653`（`_deleteDirectory`）。
- **问题一句话**：`_scanDirectory` 正确地在 `tree.truncated` 时抛 `treeTruncated` 拒绝执行（**确证点通过**），但 `tree()` 把「默认分支」和「分支 ref」裸插值进 `/git/trees/$ref`，并且 `_defaultBranchMemo` 是**进程内永久记忆且无失效路径**，`updateRepo(defaultBranch:)` 只在参数非空时更新；外部在 GitHub 网页改了默认分支后，本进程内所有 `tree()` / 缓存键 / `createBranch` / `enablePages` 继续打旧 ref。
- **代码证据**：
  ```dart
  // repo_file_service.dart:1468-1476  ← 正确的拒绝执行
  final GhTree tree = await api.tree(fullName, branch: ref, recursive: true);
  if (tree.truncated) {
    throw const _RepoFileFailure('treeTruncated',
      '目录树被服务端截断（仓库过大），拒绝执行不完整的批量操作——请缩小操作范围');
  }
  // gh_api.dart:556-561
  final response = await client.send(GhRequest(
    path: '/repos/$fullName/git/trees/$ref',        // ← ref 裸插值（见 B3-A-09）
    query: recursive ? <String, String>{'recursive': '1'} : const {},
    label: 'GET tree($ref)',
  ));
  // gh_api.dart:2184-2195  memo 只读一次、无 invalidate
  final String? memo = _defaultBranchMemo[fullName];
  if (memo != null && memo.isNotEmpty) { return memo; }
  ```
  `rg -n '_defaultBranchMemo' gh_api.dart` 只命中 `:56`（声明）、`:270`（`updateRepo` 写入）、`:2184` / `:2192`（`_defaultBranchOf` 读/写），**没有任何 `remove` / `clear`**；`invalidateReadCache()`（`:125`）只清 `GhReadCache`，不动 `_defaultBranchMemo`；切号也不清。
- **用户可见后果**：用户在 GitHub 网页把默认分支从 `master` 改成 `main`（或反之），应用内不重启就是：目录树打旧 ref → 404/旧内容；`_cacheKeyFor` 用旧 ref 构造 `CacheScope.branch`，缓存键与真实分支错位；批量删除的 `_scanDirectory` 拿到旧树，可能按「空目录 / notFound」拒绝执行，或在旧分支上执行删除（危险）。切账号后 memo 仍按 `fullName` 复用，跨账号同名的私有/公开仓库也会串。
- **严重级别**：**P1**（可导致在错误分支上执行批量删除，且无自愈路径；需重启）。
- **违反原则**：**28**（缓存键必须覆盖产生差异的全部维度：账号、默认分支变更）、**9**（写前必读读到的是旧基线）、**20**（外部状态变化未夹紧）、**15**（静默落在旧分支，注释自己也写了「重启前都不会自愈」）。
- **是否确证**：**确证**（memo 无失效路径 + `tree` 裸插值 + `_scanDirectory` 用它做删除展开）。「批量删除打到旧分支」的端到端结果需带令牌实测，标**待议**；memo 不失效这一实现缺陷本身已确证。
- **`truncated` 结论**：`gh_models.dart:539-556` 把 `truncated` 设为一等字段并注释「不处理它就会静默少文件」，`GhTree.fromJson` 用 `GhJson.boolean` 容错读取；`repo_page.dart:1647-1650` 预扫描也检查 `truncated` 并提示 `dirTooLarge` → **两处调用点都拒绝执行，确证点通过，无发现**。

---

## B3-A-15 · 四线新增方法缺少任何离线测试；`GhClient.paginate` 全库无调用方（P2，确证）

- **文件:行号**：`test/domain/`（`gh_test.dart` / `gh_client_test.dart` / `gh_absent_test.dart` / `gh_models_decode_test.dart` / `gh_submit_e2e_test.dart` / `gh_auth_service_test.dart`）、`lib/domain/gh/gh_client.dart:688-727`（`paginate`）。
- **问题一句话**：8 个四线新增方法（`transferRepo` / `updateIssue` / `updateIssueLabels` / `updateIssueAssignees` / `lockIssue` / `unlockIssue` / `updateIssueComment` / `deleteIssueComment`）在 `test/` 中**零引用**；`notifications` / `readmeExcerpt` / `latestVersionOf` 亦零引用；`GhClient.paginate()`（含 `GhPage.parse` 的 `next` 判定和安全上限告警）全库 `rg '\.paginate\('` 零命中，是未被使用的死能力。
- **代码证据**：
  ```
  $ rg -n 'lockIssue|unlockIssue|updateIssueComment|deleteIssueComment|updateIssueLabels|updateIssueAssignees|transferRepo|notifications\(|readmeExcerpt|latestVersionOf|treeTruncated|expectedHeadSha' test
  test/domain/gh_client_test.dart:374:  expectedHeadSha: 'old',     ← 唯一命中，且是已有的 commitFiles 测试
  ```
  `test/domain/` 现有 6 个文件覆盖了 `putContentLocked` 提交链回归守卫、`GhContent` 解码、401/403/404 分类、模型容错，但四线新增端点一行测试都没有 —— 这正是 B3-A-01（PATCH vs PUT）能直接合入 v12.0.0 LTS 的原因。
- **用户可见后果**：端点方法/请求体/返回解析的回归没有门禁拦截；`paginate` 的分页逻辑（含 `Link` 解析、`maxPages` 上限、`OGL-GH-101` 告警）从未被真实执行，`notifications` 只能拿第一页（并入 B3-A-04 的 P2 项）。
- **严重级别**：**P2**（测试覆盖缺口，不是运行时故障）。
- **违反原则**：**49**（测试离线可跑）、**50**（用接口 + 内存实现测契约）、**51**（破坏性测试与正常路径同等重要）、**52**（端点语义必须实测）、**55**（死代码零容忍 —— `paginate` 未被使用）。
- **是否确证**：**确证**（`rg --files test` + `rg` 全库调用点扫描）。

---

## 四线新增方法逐项裁决表（重点确证点）

| 方法 | 端点语义 | 请求体 | 返回解析 | 幂等 / 失败分支 | 结论 |
|---|---|---|---|---|---|
| `transferRepo` (`:299`) | `POST .../transfer`，OpenAPI `repos/transfer` ✅ | `new_owner` 必填 ✅ | `Future<void>` 丢 202 body ❌ | 非幂等；403/404/422 → 可见失败 ✅；**202 误报完成** ❌ | **B3-A-05（P1）** |
| `updateIssue` (`:1627`) | `PATCH .../issues/{n}`，OpenAPI `issues/update` ✅ | `state`/`title`/`body` 均合法属性 ✅ | `jsonObject ?? {}`；空 body 变空 Map（调用方只用 `_runWrite` 的成功信号量，不读内容）✅ | PATCH 天然幂等；422 折 `GhAuthException` 可见 ✅ | 实现正确；**待议**：`state_reason` / `milestone` 未暴露不影响正确性 |
| `updateIssueLabels` (`:1727`) | `PATCH .../issues/{n}` + `labels`，OpenAPI 属性存在 ✅ | 全量替换语义，注释与 `issue_page.dart:288` 先算目标集合一致 ✅ | `Future<void>` 丢弃 200 body；调用方仅靠无异常判成功 ✅ | 幂等；422（不存在的 label）可见失败 ✅ | 实现正确 |
| `updateIssueAssignees` (`:1744`) | `PATCH .../issues/{n}` + `assignees` ✅ | 全量替换；空列表清空 ✅ | 同上 ✅ | 幂等；422（不可指派者）可见 ✅ | 实现正确 |
| `lockIssue` (`:1699`) | **PATCH，应为 PUT** ❌ | `lock_reason` 属性名正确 ✅ | `Future<void>`，204 无 body 正常 ✅ | 幂等（PUT 204）；但 404 被误报「不存在/无权」❌ | **B3-A-01（P0）** |
| `unlockIssue` (`:1717`) | `DELETE .../issues/{n}/lock`，OpenAPI `issues/unlock` ✅ | 无 body ✅ | `Future<void>`，204 ✅ | 幂等；403/404 可见 ✅ | 实现正确 |
| `updateIssueComment` (`:1675`) | `PATCH .../issues/comments/{id}`，OpenAPI `issues/update-comment` ✅ | `body` 必填 ✅ | `jsonObject ?? {}`；`issue_page.dart:455` 只在成功后 `_commentsC().load()`，不依赖返回值 ✅ | 幂等；422 可见 ✅ | 实现正确 |
| `deleteIssueComment` (`:1690`) | `DELETE .../issues/comments/{id}`，OpenAPI `issues/delete-comment` ✅ | 无 body ✅ | `Future<void>`，204 ✅；`issue_page.dart:491` 有二次确认 ✅ | 幂等；404（重复删）会报失败但无数据损害 ✅ | 实现正确 |

> 「待议」项说明：`updateIssue` 的 `state: 'closed'` 在 `repo_page.dart:2674` 与 `issue_page.dart:534` 的并发点击由页面 `_busy` 防护，跨页面并发是否仍有双 PATCH 未实测；`transferRepo` 个人仓库→用户需对方接受，站内流程需登录态观察。以上均不冒充确证。

---

## 其余重点确证点逐项结论

| 确证点 | 结论 | 证据 |
|---|---|---|
| **206 回读确认**（`putContent` 无 sha 时 `_contentNetwork` 回读） | **通过**（主路径正确，比 `audit_206.md` 方案更严） | `gh_api.dart:816-829`：206 无条件回读 + `sha.isEmpty` 也回读 + 回读不到抛带真实状态码异常；不重试 PUT、不伪造 sha、不在锁内失效缓存。残余并发风险见 **B3-A-10（P2）** |
| **404 严格数组解析 + `GhNotFoundException.body`** | **通过** | `gh_api.dart:711-737` 自行 `jsonDecode` 并校验 `List`/条目数、记 ERR；`:693-707` 用 `error.body` 区分空仓库与其它 404，非空格外记 WARN + `rethrow`；`gh_client.dart:137-148` / `:779` 保留 `path`+`body`。死分支见 **B3-A-12（P2）** |
| **`/notifications` 分页 / 形状** | **部分缺陷** | 形状过滤 `:1393-1395` 正确但只挡一种；`page/perPage` 透传正确但无 `Link`/分页入口 → **B3-A-04（P1 + P2）**；游客 401 误判 → 同条 |
| **`/readme` 新 API 形状** | **缺陷** | 与 `readme()` 缓存键冲突 → **B3-A-02（P1）**；`on Object` 吞异常 → **B3-A-07（P2）** |
| **`latestVersionOf` 形状** | **缺陷** | `jsonAsList` 单对象伪记录 → **B3-A-06**；403/429 不回退 `/tags`、draft/prerelease 被 tag 冒充 → **B3-A-07** |
| **`tree truncated` 拒绝执行** | **通过** | `repo_file_service.dart:1468-1476` 抛 `treeTruncated`；`repo_page.dart:1647-1650` 提示 `dirTooLarge`；`gh_models.dart:539-556` 一等字段。memo/ref 缺陷见 **B3-A-14** |
| **路径逐段编码** | **部分缺陷** | `contents` 端点 `_ghPath` 正确；`RepoFileService` 双重编码 → **B3-A-03**；分支/ref 裸插值 → **B3-A-09** |
| **批量 `expectedHeadSha` 链式推进** | **通过** | `repo_file_service.dart:920-1010`：`chainSha = expectedHeadSha`，每块 `_commitBatch(... expectedHeadSha: chainSha)` 成功后 `chainSha = sha`；`_commitBatch`（`:1600-1620`）与 `_commitRaw`（`:1640-1660`）都在建 blob 前校验 head 并比对基线；`gh_api.dart:commitFiles`（`:1075-1100`）同样先校验再建 blob，ref 更新带 `conflictsAsRemoteConflict: true`。失败批次 `stopped=true` 后逐项标 `aborted`，不谎报整体状态 ✅ |

---

## 覆盖文件清单（`file_read` 完整读完）

| 文件 | 行数 | 读取方式 |
|---|---:|---|
| `lib/domain/gh/gh_api.dart` | 2222 | 6 段（1-400 / 401-800 / 801-1200 / 1201-1600 / 1601-2000 / 2001-2222）|
| `lib/domain/gh/gh_client.dart` | 812 | 2 段（1-420 / 421-812）|
| `lib/domain/gh/repo_file_service.dart` | 2042 | 5 段（1-420 / 421-840 / 841-1260 / 1261-1680 / 1681-2042）|
| `lib/domain/gh/gh_models.dart` | 983 | 2 段（1-500 / 501-983）|
| `lib/domain/gh/gh_read_cache.dart` | 184 | 全文 |
| `lib/domain/gh/gh_auth.dart` | 406 | 全文 |
| `lib/domain/gh/gh_oauth.dart` | 58 | 全文 |
| `lib/domain/gh/gh_oauth_io.dart` | 113 | 全文 |
| `lib/domain/gh/gh_oauth_stub.dart` | 18 | 全文 |
| `lib/domain/gh/gh_oauth_types.dart` | 43 | 全文 |
| `lib/domain/gh/gh_draft.dart` | 56 | 全文 |
| `lib/domain/domain_bridge.dart`（gh 装配段）| 634 | 2 段全文（1-330 / 331-634），重点 `GhModule.onRegister` `:140-285`、`DomainLayerModule` `:480-510` |
| `docs/QUALITY_STANDARD.md` | 93 | 全文（裁决依据）|
| `AGENTS.md` | 95 | 全文（裁决依据）|
| `docs/CONSISTENCY.md` | 60 | 全文（裁决依据）|

辅助（非裁决依据，仅用于交叉验证）：`docs/AUDIT_PLAN.md`、`docs/audit_206.md` 全文；`lib/base/disk/disk_cache.dart` 的 D5 `_verifyReadback` 段；`lib/surface/pages/{search_page,issue_page,repo_page}.dart` 与 `lib/surface/app/client_shell.dart` 的调用点；官方 OpenAPI 描述文件（14.2 MB）；`test/domain/` 文件清单。

### 已核查但未列入发现（判定正确）

- `GhClient._Semaphore` 的「许可转交」语义（`gh_client.dart:371-410`）：`release` 时 `_used` 保持不变、等待者不再自增，确实防止了并发上限被击穿 ✅
- `ttlForPath` 按 path **段**匹配（`:472-487`），避免了 owner/repo 名含 `readme` 等关键字被误配 TTL ✅
- 只读缓存回填拒收 206（`:632`）、写操作成功后整体失效（`:642-646`）、命中时回填 `Link` 头（`gh_read_cache.dart:86-126`）✅
- `_throwIfFailed` 的 429 无限流头、403 滥用拦截、按资源类别限流避让（`:729-786`、`:512-530`）✅
- `GhContent.decodeContent` 用 `utf8.decode(base64Decode(...))` 且非法 base64 返回 `null` 不抛 ✅
- `RepoFileService` 的取消检查点、逐项 `aborted` 明细、`_run` 永不抛 + 写后失效 + 诊断码 ✅
- `gh_auth.dart` 令牌脱敏、`saveAccount` 先密文后元数据、`removeAccount` 先删令牌、`switchTo` 校验令牌 ✅
- `gh_oauth_io.dart` 的 `slow_down` 递增间隔、`expired_token` / `access_denied` 分类、15 分钟上限、`HttpClient.close(force: true)` 成对 ✅
- `gh_oauth_stub.dart` 明确抛 `UnsupportedError`，不静默降级 ✅

---

## 该层整体评价

**结论：v12.0.0 LTS 的 GitHub API 层「底座接线与写一致性」质量较高，「新增端点的语义实测」明显欠账。**

1. **强项（可信）**：`GhApi` 作为 `CacheRemote` 的适配是全层最扎实的部分 —— `read()` 明确区分「远端不存在」「空文件」「内容不可读/被截断」并拒绝放行无基线 PUT（`:2056-2127`），`putContent` 的 206 回读确认、`_listDirectoryNetwork` 的严格数组解析、`RepoFileService` 的 truncated 拒绝与 `expectedHeadSha` 链式推进、`GhClient` 的信号量/限流/认证出口，均体现「数据无价 + 失败如实可见」的底线，且与 `docs/CONSISTENCY.md` D1–D9 一致。历史 P0（假失败 206、D1 误判覆盖、缓存锁内自锁）确实已被修掉并有测试守卫。

2. **主要风险（P0/P1）**：四线新增的 8 个方法**没有一条离线测试**（B3-A-15），直接导致 `lockIssue` 的 PATCH/PUT 错误（B3-A-01，P0）合入 LTS；`transferRepo` 把异步 202 当作完成（B3-A-05，P1）；`/readme` 两个消费者共用不含请求头的缓存键（B3-A-02，P1）；`RepoFileService` 越层预编码造成二次编码（B3-A-03，P1）；`notifications` 的游客 401 触发全局令牌失效出口（B3-A-04，P1）；装配段 D8 重放定时器 3 次空转后永久自停 + 防重入标志复位在死路径上（B3-A-11，P1）；`_defaultBranchMemo` 无失效路径可让批量删除落在旧分支（B3-A-14，P1）。这些都不是风格问题，而是「端点语义 / 状态机 / 缓存维度 / 生命周期」的实现错误，且多数**用户可见且无法自愈**。

3. **系统性缺陷（跨条）**：
   - **形状处理两套标准**：`_listDirectoryNetwork` 自己解 JSON 并抛，其余所有 GET 列表仍走静默的 `jsonAsList`（B3-A-06）。
   - **`on Object` 兜底一切**：三个新 API 把 401/403/429/超时/坏 JSON 全折成 `''` / `null`，零日志（B3-A-07）。
   - **标识维度不统一**：路径在 `RepoFileService` 与 `GhApi` 之间「已编码/未编码」同参混用；分支/ref 全裸插值；`GhReadCache` 键不含请求头；`_defaultBranchMemo` 键不含账号与更新事件（B3-A-02/03/09/14）。
   - **资源上限**：`GhReadCache.clear()` 只增纪元不删旧 key，每次写都留一代孤儿（B3-A-08）。

4. **修复优先级建议**：B3-A-01 → B3-A-11 → B3-A-05 → B3-A-02/03/04/14 → B3-A-06 → B3-A-07/08/09/10/12/13/15。前两条分别对应「功能完全不可用」与「提交可靠性回退」，应优先。所有修复需补离线测试（接口 + 内存 `NetBridge` 假实现）锁死端点方法、请求体、202 pending 语义、缓存键维度与定时器恢复路径 —— 原则 49/50/51/52。

5. **纪律声明**：本审计只写 `docs/audit_b3_a.md`，未改动 `lib/` 任何文件；端点方法以 GitHub 官方 OpenAPI + 匿名 HTTP 实测为准，需登录态/可控代理才能复现的行为一律标「待议」，未冒充确证。

