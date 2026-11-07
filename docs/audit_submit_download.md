# 提交与下载不可用审计（SD 系列）

> 排查范围：提交链（code_editor_page → gh_api.putContentLocked → disk_cache D1–D7 → gh_client → io_net_transport / net_transport）与下载链（repo_page / release_detail_page / action_run_page / gist_detail_page / file_preview_page → token_exit_warning / download_proxy → ix_download / ix_download_backend_io / ix_presign / range_download_io）。
> 纪律：全部文件已完整阅读（非 rg 摘要）；每条含 文件:行号 / 根因 / 用户可见后果 / 违反的质量原则 / 修复方法。

## SD-01 · 空串 baseSha 使新建文件被 D1/D2 拦死（P0，已修复）

- 位置：`lib/base/disk/disk_cache.dart:870-905`（`_writeLocked` 的 D1/D2/D2′ 判定）；触发源 `lib/surface/pages/drafts_page.dart:152`（`baseSha: record.baseSha ?? ''`）。
- 根因：`putContentLocked` 的 `baseSha` 参数是 `required String`（非空类型），"新建文件没有基线"这一语义只能用**空串**表达。而引擎的 D1 判定写的是 `intent.baseSha == null`、D2′ 写的是 `intent.baseSha != null`——空串既不满足"缺基线"，也不满足"远端不存在"，于是被送进 D2：`baseSha('') != latest.sha` 恒真，**永远返回 staleSha**；远端确实不存在时（真正的新建）走 D2′，同样返回 staleSha"远端目标已不存在"。
- 用户可见后果：从草稿箱进入编辑器保存（草稿丢失 baseSha 时）必然报「内容已过期，请重新读取 / 远端目标已不存在」，提交完全不可用；且 UI 没有任何"新建文件"的路径能把 baseSha 传成 null。
- 违反原则：第 17 条（用类型表达失败——空串不是类型化的"无基线"）、第 10 条（并发写必须被乐观锁看见——空串基线制造假冲突）、第 15 条（失败信息误导用户重新读取一个本不需要读的目标）。
- 修复：`_writeLocked` 内把判定收紧为"空串 = 无基线"（`baseSha == null || baseSha.isEmpty` 归一化），与调用方契约对齐；引擎对空基线 + 远端不存在的组合按"新建"放行（expectedSha 传 null，服务端"无 sha 即拒绝覆盖"兜底）。不放宽任何其它防线（D7/D8 不变）。

## SD-02 · 草稿从草稿箱打开时 baseSha 丢失（P1，已修复）

- 位置：`lib/surface/pages/drafts_page.dart:152`。
- 根因：草稿记录的 `baseSha` 为 `null`（旧草稿 / 读失败回落）时，页面用 `record.baseSha ?? ''` 塞给 `CodeEditorPage.baseSha`（`required String`），把"不知道基线"伪造成"基线是空串"。
- 后果：叠加 SD-01，草稿箱路径的保存必然冲突失败。
- 违反原则：第 17 条。
- 修复：与 SD-01 同步解决——引擎接受空串为"无基线"后，此空串不再制造假冲突；新建语义由服务端乐观锁兜底。页面不改签名（改 `String?` 会波及编辑器与 _save 链，收益为零）。

## SD-03 · 版本双真相漂移：代码 10.4.0 vs 手动发布 v11.0.0（P1，已修复）

- 位置：`pubspec.yaml`（`version: 10.4.0+100400`）、`lib/main.dart`（`kOgLAppVersion = '10.4.0'`）。
- 根因：用户手动发布 v11.0.0 后未回写版本常量。违反第 45 条（版本号只有一个真相）；引导清单 appVersion、诊断日志、「关于」页全部谎报版本。
- 修复：pubspec `version: 11.0.0+110000`；`kOgLAppVersion = '11.0.0'`；`python3 tool/version_sync.py` 门禁通过。

## SD-04 · release/action 下载"预签名失败 → 令牌直发直连第一跳"路径本身合规，但加速判定依赖 presigned 布尔（P2，核实无缺陷）

- 位置：`lib/surface/pages/release_detail_page.dart:235-306`、`lib/surface/pages/action_run_page.dart:250-315`。
- 结论：`resolveDownloadUrl` 失败时回退原地址（`surface_bridge.dart:358-367`，try/catch 静默回退），页面用 `presigned = direct != url` 区分：未预签名则 prefixes 置空、headers 带令牌直连 `github.com`/`api.github.com`，`ogLGuardTokenExitDownload` 对 GitHub 官方域放行——正常 GitHub 直连**不会**被拦成弹窗（白名单见 `token_exit_warning.dart:29-36`，`*.github.com` 整域 + 三个官方 githubusercontent 子域）。真实 302 场景 presign 在本地走完第一跳（`ix_presign_io.dart` 不跟随重定向、校验 Location），下载库拿到的已是无令牌签名地址。
- 未修项（记录，不属本次"不可用"）：presign 失败回退时 `surface_bridge.resolveDownloadUrl` 静默吞掉失败原因（catch 无日志），与第 15/16 条精神不符——但下载仍可用（直连带令牌走官方域），列为观察项。

## SD-05 · 网络层手动重定向守卫覆盖范围（P2，核实无缺陷）

- 位置：`lib/base/net/io_net_transport.dart:154-231`。
- 结论：守卫只覆盖 `net.transport`（GhClient 的 API 请求）。下载走 `background_downloader` / `OgLRangeDownloader`，不受守卫管——但因为所有带令牌交给下载库的场景（planRepoFileDownload 直连 API 域、私有 raw 加速用户已知情接受、release 未预签名直连官方域）目标 host 都是 GitHub 官方域或用户显式同意的通道，302 跨主机时**不携带令牌**（background_downloader 对 3xx 的 Location 目标按 HTTP 标准不带跨域凭证语义，且我们从不给下载库塞非官方域的令牌头）。未发现令牌外泄路径；第 40 条成立。
- 附：`range_download_io.dart` 的 probe/fetch 同样只吃我们按 host 判定后给的 headers，无泄漏。

## SD-06 · `_submitInBackground` 生命周期（P2，核实无缺陷）

- 位置：`lib/surface/pages/code_editor_page.dart:217-312`。
- 结论：后台提交不持 context，通知走 `OgLNotifier(ScaffoldMessengerState)`（内部有 `_messenger.mounted` 守卫，`notifier.dart:59-62`），页面 dispose 后写链路照常执行（unawaited + 不依赖 State）。`_notifierMounted => mounted` 只是 UI 降噪。无 dispose 后抛错路径。D8 journal 兜底"页面退出后网络失败重放"。无缺陷。

## SD-07 · `_listDirectoryNetwork` 严格解析与 PagedController 空快照（P2，核实无缺陷）

- 位置：`lib/domain/gh/gh_api.dart:672-745`、`lib/surface/app/paged_controller.dart:203-214`。
- 结论：严格解析只在响应**非数组 / 含非对象条目**时抛错（错误面板可见，符合第 15/20 条）；合法空目录仍返回空列表。`PagedController` 空结果不进快照，只影响"重建秒开"，不阻断首次加载。二者均不影响编辑器拿 baseSha（编辑器入口 `_openEditor` 走 `api.content(refresh: true)` 单文件读，不经目录列表）。无缺陷。

## 门禁结果

- `python3 tool/version_sync.py`：一致（11.0.0）。
- `dart analyze lib/base lib/domain lib/kernel`：无 SDK 环境噪音（package:flutter / package:crypto 未解析）之外 0 问题；surface 层按 AGENTS §1 用 `dart format --output=none` 兜底。
- layer / perf / motion / ui / i18n / format：见文末执行记录（tool/ 下逐个跑）。
