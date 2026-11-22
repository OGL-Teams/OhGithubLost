# 功能审计 3-C · 文件操作与平台通道

> 文档戳：更新时间 2026-11-23T10:42:00+08:00 · v15.0.0
> 范围：`lib/domain/domain_bridge.dart`（文件相关部分）/ `lib/domain/gh/repo_file_service.dart` / `lib/base/disk/`（app_dirs.dart、app_dirs_fs_io.dart、og_l_storage.dart、og_l_storage_saf_io.dart、platform_io_impl.dart）/ `lib/domain/sys/sys_platform_io.dart` / `lib/surface/util/path_rules.dart`（旁证：file_preview.dart、permissions.dart、surface_bridge.dart、repo_page.dart、ix_download.dart、gh_models.dart、disk_store.dart、boot_fs.dart）。
> 纪律遵守：未读 Flutter SDK / pub 缓存；只读审计，未改任何代码。

---

## P0（数据丢失 / 崩溃 / 安全）

### P0-1 批量操作「基线必带」承诺未实现：未传 expectedHeadSha 时无任何并发保护，可静默覆盖 / 删除并发修改
- **复现**：`rg -n "chainSha = expectedHeadSha" lib/domain/gh/repo_file_service.dart`（_executeOps 内，≈L1010 附近）；`rg -n "expectedHeadSha != null && expectedHeadSha != headSha" lib/domain/gh/repo_file_service.dart`（_commitRaw 内）；`rg -n "凡是.*分支状态.*写入都带基线" lib/domain/gh/repo_file_service.dart`（文件头 ≈L40）。
- **症状**：文件头承诺「批量提交一律传 expectedHeadSha（调用方给了就用，**没给就从分支 ref 解析**）」。实现里 `chainSha = expectedHeadSha` 可为 `null`；`_commitRaw` 只有在 `expectedHeadSha != null` 时才做顶端校验，`api.commitFiles`（needsRaw=false 快路径）同样只在传入时校验。调用方不传时：rename/copy 的 tree upsert（`sha: blobSha` 无条件覆盖同路径）、deletion（`sha: null` 无条件删除同路径）在 expand→commit 的窗口内**静默顶掉**他人的并发提交——目标占用检查（`_ensureTargetFree`）只在展开阶段做，防不住提交期竞态。
- **根因**：文档承诺的「没给就从分支 ref 解析基线」没有落地为代码；tree API 的 upsert/delete 本身是无版本覆盖语义。
- **修复指令**：在 `repo_file_service.dart` `_executeOps` 中，`chainSha` 初始化处改为：`expectedHeadSha ?? await _headShaOf(fullName, ref)`（为空串时抛 `_RepoFileFailure('conflict', '无法解析分支基线，拒绝批量写入')`），保证每批 `_commitRaw` / `commitFiles` 都带非空基线；或最低限度在 `_commitRaw` 中当 `expectedHeadSha == null` 时主动取 headSha 并在提交前二次比对。注意 create() 单文件快路径已由 Contents API「无 sha 即 422」服务端兜底，不受此条影响。

---

## P1（功能失效 / 不一致）

### P1-1 批量提交整批载荷全量驻留内存：大目录操作内存峰值失控
- **复现**：`rg -n "读本块（rename / copy 在此读取旧内容" lib/domain/gh/repo_file_service.dart`；阶段②对 `cursor..end`（最多 `batchSize=200` 条）逐条 `await _readPayload(...)` 后才提交；`rg -n "base64.decode|base64Encode" lib/domain/gh/repo_file_service.dart`。
- **症状**：_readPayload 把整个文件读成 base64 字符串（≈1.33× 原始大小）再 decode 出 bytes（双份峰值 ≈2.4×），且整批 transfers 在提交完成前全部持有。200 个 × 各 50 MB 的目录 copy → 峰值可达数十 GB；移动端直接 OOM/被杀，且被杀时批次无提交（比 P0-1 好，但功能失效）。
- **根因**：「内存占用以 batchSize 为界」的口径按**条数**而非**字节**。
- **修复指令**：在 `RepoFileService` 增加 `maxBatchBytes`（如 64 MB）；阶段②累计读入字节超限即提前截断本批（`end = i`）；或对 >8 MB 的条目强制走「先传 blob、批内只留 sha 引用」的流式路径（_commitRaw 已支持 refSha 条目，改造面小）。

### P1-2 SAF 导出 `pasteLocalFile(overwrite: true)` 恒覆盖，违背全局「拒绝静默覆盖」原则
- **复现**：`rg -n "overwrite: true" lib/base/disk/og_l_storage_saf_io.dart`（L60 附近）；对照 `rg -n "拒绝静默覆盖" lib/domain/gh/repo_file_service.dart`。
- **症状**：存储②档每次下载完成都把成品按原名覆盖粘贴进用户授权的 SAF 文件夹。用户若在同一文件夹手工编辑/另存过同名文件（如 `report.pdf`），再次下载同名附件即被静默顶掉，无任何提示——与仓库操作侧「误覆盖是致命错误类别」的自我要求直接矛盾。
- **根因**：导出通道独立实现，未复用覆盖策略。
- **修复指令**：`og_l_storage_saf_io.dart` `pasteLocalFile` 增加 `overwrite` 参数（默认 false），用 `SafUtil().exists()`（或插件等价 API）先探存在性；存在时返回约定值让 `ix_download.dart _maybeExportToSaf` 改名（`name (1).ext`）或上报待用户决定。

### P1-3 目录 rename/copy 的取消 / 失败中间态：半搬移仓库状态
- **复现**：`rg -n "批次之间\*\*不具备原子性\*\*" lib/domain/gh/repo_file_service.dart`（batch() 文档）；分批循环 `while (cursor < total)` 中 `stopped = true` 的两条路径（读取失败 / 提交失败 / token.isCancelled）。
- **症状**：目录移动分多批提交时，第 1 批成功、第 2 批失败或取消 → 仓库处于「一半在新路径、一半在旧路径」的分裂状态，文件树视图与用户预期不一致；结果明细虽如实标注 `aborted`，但**没有任何恢复/回滚指引**，用户需手工比对补搬。
- **根因**：分批串行是配额保护的有意设计，但缺少「中断后续跑」的编排。
- **修复指令**：把每批的计划条目与已完成的 `chainSha` 持久化进 `WriteJournal`（base/disk/journal.dart 已有失败写入重放骨架），在 `DomainBridge` 启动重放处对未完成批次以同一 message 续提；至少在 `RepoFileResult` 增加 `resumable: true` + 断点信息字段供 UI 提供「继续」按钮。

---

## P2（打磨）

### P2-1 Windows 长路径清扫 / 收纳删除未走 winLong
- **复现**：`rg -n "await entity.delete" lib/base/disk/platform_io_impl.dart`（sweepTemp ≈L343-360，`entity.path` 未包 `winLong`）；`_packTooLong` 内 `await target.writeAsBytes` 已包 winLong，但 sweepTemp 不包。
- **症状**：Windows 上根目录深层残留的 `*.tmp`（路径 >240 字符）每次启动清扫都失败，进 `failed` 列表反复上报却永远删不掉。
- **修复指令**：sweepTemp 删除处改为 `File(winLong(entity.path)).delete()`。

### P2-2 目录探测把 404/409/422 一律当「不存在」
- **复现**：`rg -n "statusCode == 404" lib/domain/gh/repo_file_service.dart`（_probePath）。
- **症状**：422 也可能是 ref 非法等参数错误；误判 `_Probe.missing()` 后 create 会继续走 putContent 报一个更间接的错。不影响正确性（服务端兜底），但错误归因误导。
- **修复指令**：_probePath 只把 404/409 当 missing；422 原样 rethrow 由 _describe 归为 `failed`。

### P2-3 分支 ref 未做 URL 编码
- **复现**：`rg -n "git/refs/heads/\\\$ref|ref/heads/\\\$ref" lib/domain/gh/repo_file_service.dart`。
- **症状**：分支名含 `#`（git 合法字符）时 URL 被 `#` 截断，_headShaOf 返回空 →「无法确定分支顶端提交」。
- **修复指令**：ref 插值处统一 `Uri.encodeComponent(ref)`（与 encodeForUrl 同款逐段策略）。

### P2-4 path_rules 与 RepoFilePaths 双份实现已漂移出语义差
- **复现**：`rg -n "pathDirNeedSlash" lib/surface/util/path_rules.dart` vs `rg -n "validateDirectoryPath" lib/domain/gh/repo_file_service.dart`。
- **症状**：UI 侧目录**必须**尾随 `/`，域层 validateDirectoryPath 不要求；两份保留名/长度规则虽同源但靠注释约定同步，新增规则漏改一侧无测试拦截（app_dirs_category_test 只锁分类映射）。
- **修复指令**：以 `RepoFilePaths` 为唯一实现，`path_rules.dart` 改为薄转发（surface→domain 方向合法）；或加一个双实现逐用例比对测试。

### P2-5 `OgLStorage.plan()` 每次 `publicWritable()` 真实写探针
- **复现**：`rg -n "publicWritable" lib/base/disk/og_l_storage.dart lib/base/disk/app_dirs.dart`。
- **症状**：每次下载目录裁决都对 `/storage/emulated/0/ogl` 建目录+写删探针文件；无权限机型上每次都抛异常再吞掉，浪费 IO 且日志噪音。
- **修复指令**：`AppDirsFs.writable` 结果按「本次会话 + 权限版本号」缓存（`OgLAppDirs.invalidate` 已有失效钩子，复用它）。

### P2-6 单文件 rename 不保留可执行位（已知限制，未拦截提示）
- **复现**：`rg -n "单文件重命名不保留可执行位" lib/domain/gh/repo_file_service.dart`（_sourceOfContent 注释）。
- **症状**：`100755` 脚本经单文件 rename 后变 `100644`，CI 侧「permission denied」。代码已自知但用户无感知。
- **修复指令**：_expandMove 单文件分支探测 `content.raw['mode']`（Contents API 部分场景不返回则退而用 tree 条目），为 `100755` 时强制走 `_scanDirectory`+`_commitRaw` 路径以保模式。

---

## 已检查清单（全部逐行读过，无问题的也列出）

| 文件 | 检查点 | 结论 |
|---|---|---|
| lib/surface/util/path_rules.dart | 全部校验分支、保留名 stem 逻辑、CJK/控制字符正则、gitkeep 占位 | 逻辑自洽；漂移见 P2-4 |
| lib/domain/gh/repo_file_service.dart（2042 行全文） | create/delete/rename/copy/batch、_executeOps 分批、_expandOp、_probePath、_scanDirectory（truncated 拒执行、maxFilesPerOp）、_readPayload（UTF-8 严格复核/base64 兜底）、_commitBatch/_commitRaw、_run 写后失效缓存、取消检查点、错误码表 | P0-1 / P1-1 / P1-3 / P2-2 / P2-3 / P2-6 |
| lib/base/disk/app_dirs.dart | resolveRoot 唯一入口、缓存、tierOf、categoryFolder 映射 | 无新问题 |
| lib/base/disk/app_dirs_fs_io.dart | 候选链、真实写探针、路径分隔符归一 | 无新问题（探针见 P2-5） |
| lib/base/disk/og_l_storage.dart | 三档裁决、userVisible 统一走 isUserVisible、exportToSaf | 无新问题 |
| lib/base/disk/og_l_storage_saf_io.dart | pickDirectory 持久化授权、pasteLocalFile、loadConfig/saveConfig | P1-2 |
| lib/base/disk/platform_io_impl.dart（571 行全文） | abs() 防穿越（`..` 显式拒绝，测试锁定）、原子写唯一 tmp 名、winLong/UNC（`\\?\UNC` 前缀正确）、TooLongRoad 收纳与还原（损坏时抛而非当 null，B2-A-10 修复在位）、sweepTemp、IoDiskKv sha256 文件名+原键反查 | P2-1 |
| lib/kernel/contract/disk_store.dart | InMemoryFileStore.normalize（abs() 的依赖） | 无问题 |
| lib/kernel/boot/boot_fs.dart | normalizePath（仅剥 `./`，不剥 `/`）——boot 场景无用户输入路径，不构成穿越面 | 无问题 |
| lib/domain/sys/sys_platform_io.dart | Platform 原语收敛、readMemInfoText 平台守卫 | 无问题 |
| lib/domain/domain_bridge.dart | RepoFileService 装配与 DI 注册、downloadDirProvider 三档裁决接线、_OgLStorageExporter 不抛承诺、重放定时器防重入 | 无新问题 |
| 旁证：lib/surface/app/permissions.dart | Android 存储授权回退链（manageExternalStorage→storage→写探针）、拒绝后 needsUserAction 如实报告 | 无新问题 |
| 旁证：lib/surface/surface_bridge.dart | _probeStorage 先 invalidate 再裁决；SAF 档可见性特判 | 无新问题 |
| 旁证：lib/surface/util/file_preview.dart | image/audio 拦编辑入口（乱码覆盖防护）；unknown 类二进制由 gh_models decodeContent 严格 UTF-8（非 UTF-8→text=null）兜底，编辑器入口实际拦得住 | 无新问题 |
| 旁证：lib/surface/pages/repo_page.dart | _openEntryDefault/_showOpenWith/_openEditor 的 isTooLarge/text==null 守卫、README 图片 base64 解码 | 无新问题 |
| 旁证：lib/domain/ix/ix_download.dart | _maybeExportToSaf 去重表成功路径也移除（历史 bug 已修） | 无新问题 |
| 旁证：lib/domain/gh/gh_models.dart | 空文件 vs isTooLarge 区分、decodeContent utf8.decode | 无新问题 |

## 本席结论

文件操作域整体设计密度高、历史修复留痕充分（防穿越、原子写、收纳还原、SAF 三档、取消语义均有测试或注释锁定）。但 **P0-1 是文档承诺与实现的真实裂缝**：批量写入在不传基线时对并发修改完全不设防，且 tree upsert/delete 是无版本覆盖语义——这是本域唯一可能造成远端数据丢失的路径，建议最优先修（改动集中在 `_executeOps` 的 chainSha 初始化，约 5 行）。P1 三条（批量内存峰值、SAF 覆盖、半搬移中间态）为体验/资源风险，修复面中等。未发现路径穿越、非法文件名、UNC/分隔符、权限误判类的回归复发。
