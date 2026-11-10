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
