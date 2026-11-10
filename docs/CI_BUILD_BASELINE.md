# CI 构建时长基线（实测，2026-11-10）

> 数据来源：GitHub Actions API 的 `runs/{id}/jobs` 步骤级
> `started_at` / `completed_at`，不是估算。
> 改 CI 配置前先读这份基线，改完用 `/tmp/ci_benchmark.py` 复测，
> **不要凭感觉加缓存或拆 job**。

## 优化前的耗时结构

### CI（`ci.yml`，单 job，run 42834046450）

| 步骤 | 耗时 |
|---|---|
| 安装 Flutter（已有 flutter-action cache） | 15s |
| 图表自检 | 9s |
| 平台注入器自检 | 9s |
| 静态分析 `flutter analyze --fatal-infos` | 15s |
| 单元测试 `flutter test`（含渲染快照） | 40s |
| 其余 10 余项 Python 门禁 | 各 0~1s |
| **步骤合计** | **96s** |

结论：**CI 本来就快**，瓶颈不在质量门。任何"拆分 CI job""并行跑门禁"
的改动都是负收益（额外调度开销 > 门禁本身）。
`ui-shots` 产物被 `release-verify.yml` 消费，也不能把上传拆走。

### Build（`build.yml`，9 腿矩阵，run 42716766965 与 42834046744）

| 环节 | 耗时 | 说明 |
|---|---|---|
| Android 5 腿各 `flutter build apk/appbundle` | **350~379s / 腿** | 墙钟取决于最慢腿 |
| Windows · x64 装 Flutter | 124s | flutter-action 首次拉 SDK |
| Windows · arm64（git 方式装 Flutter） | 25s + 环境信息 54s | 首次自编译 flutter tool |
| Windows · arm64 构建 | 198s | |
| Linux · arm64 构建 | 58s | |
| **发布 job：产物压缩（zip -9 + 7z -mx=9）** | **85s** | 8 个目录**串行** |
| Linux 安装包（deb/rpm/AppImage） | 37s | |
| **整体墙钟** | **约 7 分钟** | 并行矩阵 + 发布 job |

## 已做的优化（commit f2321f0 起）

| 改动 | 针对的问题 | 预期 |
|---|---|---|
| `build.yml` 缓存 `~/.gradle/{caches,wrapper}` + `ANDROID_SDK_ROOT/{ndk,cmake}` | 每腿重下 Gradle 依赖与 **~2GB NDK**；本次还出现 `Error on ZipFile unknown archive` 损坏下载导致整腿作废 | 第二次起每腿省 2~4 分钟，且绕开重复下载 |
| `build.yml` 缓存 arm64 两腿的 Flutter SDK（路径用 `~`） | Windows 124s / Linux 27s 的 clone 与首次工具编译每次重来 | 命中后跳过 `git clone` |
| `build.yml` 产物压缩并行化 | 85s 串行 | ~15s |
| `build.yml` push 加 `paths-ignore` | 纯文档提交（v12.5.1 / v12.5.2 的 `changed/` 归档）也跑 9 腿矩阵 | 这类推送完全不触发 Build |
| `ci.yml` 缓存 `.dart_tool/package_config.json` | 依赖树重复解析 | 数秒 |
| `web.yml` 缓存 `~/.pub-cache` 与 `.dart_tool` | wasm/js 双构建各解析一遍依赖 | 数秒~数十秒 |
| `tool/ci_config_audit.py` 接进质量门 | 缓存键/路径/并行压缩写坏只有跑一次 7 分钟才发现 | 离线 0.1s 拦下 |

### 边界与纪律

- `paths-ignore` **只作用于 push**：PR 全量构建（合并门槛不可绕过），
  `workflow_dispatch` 不受 paths 过滤（正式发布照常全平台）。
- `.github/workflows/**`、`lib/`、`tool/`、`pubspec.yaml` 不在忽略列表：
  改到构建配置本身**必然**触发 Build 验证。
- 缓存键绑定 `FLUTTER_VERSION` + `hashFiles('pubspec.yaml')`，
  并带 `restore-keys` 前缀回退；依赖变更不会用到旧缓存。
- 缓存路径不许写死平台专属绝对路径（Windows arm64 的 HOME 与 Linux 不同），
  一律用 `~` 或 `env.*`——由 `ci_config_audit.py` 强制。
- 并行压缩的 `wait` **必须逐个取退出码**：`wait` 不带参数只返回最后一个
  后台任务的结果，压缩失败会被静默吞掉（少发一个包而发布照样成功）。
- 大体积缓存**不许让多条并行腿写同一个 key**（见下节实测教训）；
  由 `ci_config_audit.py` 强制 save 步骤必须带 `matrix.*` 独占条件。

### 第一次尝试的失败（**必须记住**）

最初用 `actions/cache@v4` 让 5 条 Android 腿都自动 post-save 同一个
~2GB 的 key。完整成功 run **42840707327** 的实测：

| 指标 | 结果 |
|---|---|
| run 墙钟 | **940s（15m40s）**，比优化前 ~7min **慢一倍多** |
| 5 条腿 `Post 缓存` 步骤 | 280 / 361 / 373 / 431 / **508s**（比构建步还慢） |
| 缓存日志 `Failed to save` | **8 次**：`reserve cache with key ... another job may be ...` |
| `Cache saved` | 6 次，**全是 `flutter-sdk-git-*`**；Android 大缓存一条都没存上 |

根因：v4 在**每个 job 的 post 步骤**都打包上传；GitHub 只允许一个 job
保留该 key，其余 4 份上传全是白烧，且缓存按 **2GB 分段**传输，
并发分段互相拖慢。子代理调研超时只带回这一条有效信息，但与实测吻合。

**修法（已落盘）**：
- 所有 Android 腿改 `actions/cache/restore@v4`（只读，**零 post 上传**）；
- 仅 `Android · AAB` 腿在上传产物后用 `actions/cache/save@v4` 显式保存一次，
  条件带 `success()`（构建失败时不把半拉好的 Gradle 状态写进缓存）
  与 `steps.android-cache.outputs.cache-hit != 'true'`（命中则不重复写）；
- `ci_config_audit.py` 新增检查：同时出现 restore/save 时，
  save 必须带 `matrix.*` 独占条件，防止复发。

### 第二次失败（缓存内容选错，**更要记住**）

修正并发写后 run **42843889680**：墙钟 **414s**（回到基线），
CI 绿、Build 绿。但日志显示**缓存完全没生效**：

```
Cache hit for: android-gradle-...        ← 先报命中
Cache Size: ~4078 MB (4.2 GB)
tar: ... Cannot utime: Operation not permitted   ← 数百条
tar: Exiting with failure status due to previous errors
##[warning]Failed to restore
Cache not found for input keys: ...
```

5 条腿全部如此：下载 4GB、解包失败、各白花 57~107s；AAB 腿的
独占 save 也 `Failed to save: Unable to reserve cache`。

根因：把 `${ANDROID_SDK_ROOT}/ndk` 与 `/cmake` **整目录**塞进缓存。
runner 预装 SDK 属 **root**，且含 3 个 NDK 版本（27/29/30）+ 2 个 cmake，
共 4GB；用户态 `tar` 无法恢复其 `utime/chmod`，必然失败。

**最终修法**：缓存路径收敛为**用户可写、各腿共享、体积小**的两项：
`~/.gradle/caches/modules-2`（Maven 制品）与 `~/.gradle/wrapper/dists`
（Gradle 发行版，已换官方 CDN）。NDK 交给 Flutter Gradle 插件按需下载，
靠「预装 CMake」与 CDN 降低失败率——hosted runner 每腿独立 VM，
root 所有的系统 SDK 无法可靠缓存，**接受这一成本**。

`ci_config_audit.py` 再加规则：缓存路径出现
`ANDROID_SDK_ROOT / ANDROID_HOME / android/sdk` 且带 `/ndk`、`/cmake`
段即报错（含变量引用形式），并做了反向注入验证。

### 额度清理

失败版产生 8 条缓存共 **8.30 GB**（逼近 10GB 上限）：
删掉 4.08GB 的 `android-gradle-*` 与 0 字节的 `pubspec-*`，
**8.30 GB → 4.32 GB**（释放 3.98 GB）。保留 6 条仍有效的
Flutter SDK / pub 缓存（实测 arm64 两腿命中）。
清理脚本：`/tmp/clean_ogl_caches.py`（按 key 前缀删除，保守只删失败项）。

### 最终验证（run **42846860782**，commit `082f794`，完整 success）

| 指标 | 优化前基线 | 并发写失败版 | 4GB 缓存失败版 | **最终版** |
|---|---|---|---|---|
| Build 墙钟 | ~420s | **940s** | 414s | **452s** |
| Android 构建步 | 350~379s | 257~402s | 168~231s | 299~379s |
| `Post 缓存` 步骤 | 无 | 280~508s × 5 | 无 | **无** |
| 缓存 restore | — | 全失败 | 下载 4GB 后 `Failed to restore` | **0~1s，无 `Cannot utime` / `Failed to restore`** |
| 独占 save | — | 8 次 `Failed to save` | `Failed to save` | **AAB 腿 14s 成功一次** |
| 缓存包 | — | ~2GB × 5 | **4078 MB** | **1124 MB**（只有 Gradle 依赖） |
| Actions 缓存总额 | — | — | 8.30 GB | **5.42 GB**（< 10GB 上限） |

**诚实结论**：最终墙钟 452s 与优化前 ~420s 基本持平（+32s，
这一轮是冷启动 + 独占 save 14s）。**Gradle 缓存并没有把构建压得更短**——
因为 NDK 下载无法可靠缓存（root 所有的 runner 系统 SDK），
它仍是 Android 腿的主要耗时。缓存的真实价值在于：
- 消除了两次失败版引入的额外开销（940s / 4GB 恢复）；
- Gradle Maven 制品与发行版不再每腿重下（下一轮起生效）；
- 避免 NDK/Gradle 下载损坏时整腿作废的概率（CDN + 预装 CMake）。

**真正稳定生效的压缩项**：
1. `paths-ignore`：纯文档提交不再跑 9 腿矩阵（省整轮 ~7min）；
2. 产物压缩并行化：发布 job **85s → ~15s**；
3. arm64 两腿 Flutter SDK 缓存：实测 `Cache hit`，省 clone 与首次工具编译
   （Windows 124s + 54s / Linux 27s）；
4. CI 门禁离线自检：配置写坏不再要跑一轮 7 分钟才发现。

**验证纪律**：`actions/cache` 在 job 的 post 步骤才写缓存，**run 被
`cancel-in-progress` 取消时不会保存**。验证缓存收益时不要连续 push，
必须让一整轮 Build 完整跑完；被取消的 run 里
构建步耗时是假的（如 `The operation was canceled` 会让 370s 的活显示成 110s）。

## 复测方法

```sh
python3 tool/ci_config_audit.py --fatal   # 离线：配置结构
GITHUB_TOKEN=<PAT> python3 tool/ci_benchmark.py   # 在线：步骤耗时与缓存命中
```

对比时**必须**取 `completed == success` 的完整 run；被取消的 run 里
构建步耗时是假的（如 `The operation was canceled` 会让 370s 的活显示成 110s）。
