# 排查报告：仓库列表为空 & 下载经常失败（2026-11-07）

## DBG-01 · P0（已修复）· 编译错误：`_kUnset` 未定义 → 带 Authorization 的所有 API 请求全灭

- 文件：`lib/base/net/io_net_transport.dart`（重定向守卫新代码）
- 现象：新守卫代码引入了哨兵**类型** `_UnsetMarker`，但 `_writeBody` 与
  `_sendWithGuardedRedirect` 里引用的是哨兵**实例** `_kUnset` —— 该常量从未声明：
  - L276：`identical(bodyOverride, _kUnset)`
  - L297：`Object? bodyOverride = _kUnset,`
  - L303：`if (!identical(bodyOverride, _kUnset))`
  而文件里只有 L32 的 `class _UnsetMarker { const _UnsetMarker(); }`。
- 根因分析：这是**编译期错误**，不是运行时行为差异。 Dart SDK 3.13.7 实测：
  `dart tool/debug_probe/probe.dart`（构造 `IoNetTransport` + `ResilientTransport`
  发真实请求）编译直接失败：
  ```
  lib/base/net/io_net_transport.dart:297:28: Error: Undefined name '_kUnset'.
  lib/base/net/io_net_transport.dart:276:55: Error: The getter '_kUnset' isn't
  defined for the type 'IoNetTransport'.
  ```
  因此**只要这段新代码被编译进包**（任何 `dart/flutter build`），整个应用
  根本构建不出来；若用户装的是旧包，则新守卫从未生效。两种情况下
  「仓库列表空 / 下载失败」都不是这段代码**运行时**造成的 —— 但它让本轮
  排查无法用最新代码验证，也必然阻塞下次发版，属 P0。
- 修复（file_edit）：在 `_UnsetMarker` 类后补上哨兵实例声明：
  ```dart
  const Object _kUnset = _UnsetMarker();
  ```
- 修复后验证：同一探针（本地 mock 服务器：第一跳 `/user/repos` 302 跨主机 →
  第二跳回 JSON 列表）编译通过并运行，结果：
  ```
  STATUS=200
  BODY=[{"id":1,...,"full_name":"me/demo",...},{"firstHopAuth":true,"secondHopAuth":true}]
  ```
  证明修复后守卫的语义正确：
  1. 带凭证请求遇到**同主机**（含端口）302 → 手动跟随且凭证保留（`firstHopAuth=true`
     表示第一跳带了 Authorization；`secondHopAuth=true` 表示同源跟随重发了凭证）；
  2. 302 被正确跟随，`ResilientTransport` 拿到 200，**不会把 3xx 当失败抛错**；
  3. 响应 JSON 正常传回上层（`GhResponse.jsonList` 可解析，见下）。

## DBG-02 · 结论（无需修复）· 守卫不会把 302 当失败抛错，但**跨主机** 302 现在会如实失败

- 文件：`lib/base/net/io_net_transport.dart` L150–330、
  `lib/base/net/net_transport.dart` L123–145（ResilientTransport）、
  `lib/domain/gh/gh_client.dart` L656–700（`_throwIfFailed`）。
- 根因分析（审查链路 `dashboard → gh_api.myRepos → gh_client.send → net → io_net_transport`）：
  1. **api.github.com 的常规 API（`/user/repos`、`/user/starred`）从不 302**：
     GitHub 对这些端点直接回 200/304/4xx。守卫只对**带 Authorization 的请求**启用
     手动跟随；同源 302/303 会正确降级 GET 并跟随（探针已实证）。所以正常
     仓库列表调用不会因守卫失败。
  2. 但**跨主机 302**（典型：`GET .../runs/{id}/logs` →
     `results-receiver.actions.githubusercontent.com`）现在会停止跟随，把 3xx
     响应原样交给上层。上层 `ResilientTransport` 只重试 `{408,429,5xx}`
     （`net_retry.dart` L14），3xx 属"语义性响应"直接返回；`GhClient._throwIfFailed`
     落到 `default:` 分支抛
     `GhAuthException('请求失败（HTTP 3xx）…')`。**这是设计意图**
     （原则 40：凭证不出设备），不算 bug；但意味着任何"依赖 API 302 拿真内容"
     的路径必须先走 presign（见 DBG-04）。
  3. `ix_action_logs_http_io.dart` 已自行手动跟随并**剥离后续跳凭证**（L27–83），
     与守卫语义一致，不受影响。

## DBG-03 · P2（未修，证据充分）· 首页刷新**不绕缓存**：30 秒 TTL 内下拉刷新永远拿到同一份（可能为空的）结果

- 文件：`lib/domain/gh/gh_client.dart` L434–447（`ttlForPath` 给 `/user/repos`、
  `/user/starred` 30s TTL）+ L528–556（命中即返回，不看是否"刷新"）；
  `lib/surface/pages/dashboard_page.dart` L574–586（`refresh()`）。
- 根因分析：`GhRequest.cacheBypass` 参数存在，但 `_RepoPaged.refresh()` 调
  `surface.domain.api.myRepos(...)` → `client.getList(...)`，**没有任何调用点传
  `cacheBypass: true`**（全仓 `rg cacheBypass` 只命中 gh_client.dart 自己）。
  后果：若第一页请求曾失败并（在旧版本/异常路径下）写入过空体，或首次返回
  空列表（例如刚登录 token 权限短暂受限），**30 秒内所有刷新都命中缓存**，
  用户看到的一直是空列表，下拉刷新"没反应"。`GhReadCache.put` 只在
  `response.isSuccess` 时写（gh_client.dart L641–648），所以"失败结果被缓存住"
  这条路是堵住的；真正的问题是**空成功结果 + TTL 内无法穿透**。
- 缓解因素：`jsonList` 解析已是同步且正确（gh_client.dart L479–516 的历史
  bug 注释可证已修）；`AsyncController`/`_RepoPaged` 的错误均会写入
  `error` 并渲染错误面板（async.dart L115–150、dashboard_page.dart L398–401），
  **异常不会被吞成空** —— 空态只在 `loader()` 成功返回空列表时出现。
- 修复建议（最小侵入）：给 `GhApi.myRepos/starredRepos` 增加 `bypassCache`
  参数并透传到 `GhRequest.cacheBypass`；`_RepoPaged.refresh()` 置真、
  `loadMore()` 保持 false。或更简单：下拉刷新时直接 `cacheBypass: true`
  （gh_api 里 `myRepos` 增加可选参数即可）。

## DBG-04 · P1（已修一半 / 剩余部分无需改码）· 下载链路审查：presign 已先解 302，enqueue 头不该带 Authorization —— 逐条核对结论

- 链路：`release_detail_page._download` / `action_run_page._downloadArtifact`
  先 `surface.resolveDownloadUrl(url)`（本地 presign，令牌不出设备，302 在本地
  解掉），成功后才入队且 `headers = {}`（release_detail_page.dart L240–272、
  action_run_page.dart L239–281）。**签名地址不带凭证**，background_downloader
  的 302（如有）也不涉及凭证泄露。
- 失败路径 A（**主要嫌疑**）：`resolveDownloadUrl` 失败/超时 → 回退原始
  「需认证的第一跳」+ `downloadAuthHeaders()`。这条**正是现在会被新守卫拦截的
  路径**：入队给 background_downloader 的 headers 含 `authorization`，库内部
  用自己的 HttpClient（不走 IoNetTransport，守卫管不到它——守卫只守
  `net.transport` 这条 API 通道），但第一跳 302 → 签名主机时，库默认
  `followRedirects` 行为会**原样转发 Authorization 到第三方主机**。
  这是一个**真实的凭证外泄风险**（P1 安全），不是"下载失败"：
  下载大概率能成功（302 会跟），但令牌被送出。建议给入队的
  background_downloader 任务**禁止自动跟随**或强制先 presign（presign
  失败就放弃下载，不要带凭证直连）。
- 失败路径 B（分片）：`planRepoFileDownload` 不加速时给
  `api.github.com/repos/.../contents/...?ref=...` + `Accept: raw` +
  Authorization。`OgLRangeDownloader.probe` 对它发 HEAD；该端点实测支持
  Range，`probe` 命中 200+`Accept-Ranges: bytes` 或降级 `_probeByRange`
  拿 206 → 正常分片。**但 probe 用的是裸 HttpClient，302（api.github.com 的
  contents 端点不 302，raw 端点才 302）风险低**；若服务端回 3xx，
  `probe` 得到 `supportsRange=false` → 回退 `_fallbackToSingle`，交给
  background_downloader（默认跟随重定向）→ 下载能完成（令牌外泄同路径 A）。
- 失败路径 C（已确认非 bug）：小于 1 MB 文件走分片 →
  `DownloadUnsupported('分片数不足')` → `_fallbackToSingle` 回退单连接
  （ix_download.dart L844–862），不是失败。
- 结论：**"下载经常失败"最可能不是本仓库代码的 bug，而是**
  ① 用户开了"多线程下载"但加速通道不可用/未配置 → 全部走直连
  `api.github.com/contents`（私有仓库 + 大文件在弱网下慢/超时）；
  ② 或 presign 第一跳超时（20s，`ix_presign_io.dart` L96）在弱网下频繁发生 →
  每次都退回「带凭证直连第一跳」路径，background_downloader 跨主机跟随 302
  虽能下但暴露令牌（安全，见上）。仓库代码层面没有把成功判失败的逻辑；
  探测/回退/回合守卫/A-2 代次守卫逻辑自洽。

## DBG-05 · 证据与验证方法

- 验证脚本：`tool/debug_probe/probe.dart`（已跑完删除）：本地 `HttpServer`
  模拟「302 跨主机 → JSON 列表」，对 `IoNetTransport+ResilientTransport`
  发带 `Authorization` 的 GET；修复 `_kUnset` 前编译失败、修复后 200 + 凭证
  只在同源跟随中重发。
- `dart analyze lib/base/net lib/domain/gh lib/domain/ix`：除"缺 Flutter SDK /
  pub 包"的环境性报错外，唯一真实代码错误即 DBG-01，已消除。
- 沙箱无 Flutter SDK，无法 `flutter pub get` / 跑 `test/`，运行时验证用
  纯 Dart 探针替代（见上）。

## 汇总

| 编号 | 级别 | 状态 | 一句话 |
|------|------|------|--------|
| DBG-01 | P0 | ✅已修复 | `_kUnset` 未定义导致守卫代码编译失败；补哨兵实例后探针验证 302 同源跟随 + 200 正常 |
| DBG-02 | — | 结论 | 守卫不会把 302 当失败；跨主机 3xx 如实上抛是设计意图（凭证不出设备） |
| DBG-03 | P2 | ❌未修 | 首页刷新不 bypass 30s 只读缓存，TTL 内空结果无法穿透 |
| DBG-04 | P1(安全) | ❌未修 | presign 失败回退时把 Authorization 交给 background_downloader，跨主机 302 会外泄令牌；建议 presign 失败即中止下载而非带凭证直连 |
