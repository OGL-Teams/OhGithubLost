# Web 版最小化重构清单（v13-web-lite 草案）

> 目标：**基础运行框架 + 全部仓库代码功能完整保留**；只砍浏览器物理上不成立或用户明确不需要的外围（搜索、下载管理、Actions、AI、Gist、Release 详情/新建、通知/网络/设置分段页、权限与窗口能力）；**性能优化为第一优先**（首屏体积、冷启动、长列表、网络往返）。
> 现状：`web` 分支 191 个 lib 文件、19 个运行时依赖、落后 main 64 个 lib 提交；含整套 AI 功能线（1351 行）与大量原生插件，是 Web 包体与启动开销的主要来源。
> 纪律：清单只列「保留 / 砍除 / 性能」三类可裁决项；不写实现细节，实施时另出方案。

## 〇、边界修正（2026-11-09，第二次修正：网络与缓存全保留）

用户明确要求：**基础运行框架与全部仓库代码功能完整保留；网络相关功能（含网络加速处理）与缓存相关功能同样完整保留并做好优化**。据此修正：
- 保留 repo_page 完整四 tab（目录 / 提交 / Issue·PR / 仓库设置）、repo_file_service 全套批量能力、commit_page、new_repo_page、drafts_page、issue_page / pull_page（含评论/标签/指派/锁定）、profile 多账号；
- 「搜索仓库」按用户要求砍除，但**不连带删除**任何仓库浏览或提交代码；
- **网络相关全保留**：NetBridge / ResilientTransport / WebNetTransport / DNS 策略（含 DoH 的 Web 能力边界如实标注）/ 重试与镜像 / 网络自检 / 加速九类范围 / `download_proxy` / TOKEN-EXIT-01 警告 / `network_page`（网络设置页**保留**）；
- **缓存体系全保留**：RepositoryCache（D1–D9）、DiskKv（localStorage 实现）、GhReadCache、DraftStore、持久化 localStorage KV、只读缓存 TTL 与失效；Web 端缓存做好：TTL 分层、写入原子性、索引完整性校验、配额超限降级留痕；
- 设置页只化简文案与层级，不删功能；
- 砍除面收窄为「浏览器物理不成立 + 点名不要」两类（见第二节修正）。

## 一、保留（最小可用集）

| 板块 | 保留内容 | 理由 |
|---|---|---|
| 仓库 | **全部保留**：列表、详情四 tab、目录、文件预览、README、提交历史、新仓库向导、star | 用户明确要求 |
| 提交相关 | **全部保留**：单文件编辑/保存、新建/删除/重命名/复制/批量、expectedHeadSha 链式推进、tree truncated 拒绝、草稿箱、冲突可见 | 用户明确要求 |
| 发现页 | 关注仓库动态、推荐仓库、问题汇总（三标签） | 用户明确要求保留；但见「三、性能」的懒加载约束 |
| 账户 | PAT 登录、退出、多账号切换、令牌内存态 + localStorage KV、登录门 | Web 无 OAuth Device Flow（stub 明确不支持） |
| 设置 | **功能全保留**，仅化简文案与层级、统一项间距 | 不删功能 |
| 网络（第二次修正新增） | **全部保留**：Web 传输、DNS/DoH 能力边界、重试、镜像、网络自检、**九类加速范围与私有仓库知情警告**、网络设置页 | 用户明确要求；浏览器 CORS 限制如实说明，不做静默降级 |
| 缓存（第二次修正新增） | **全部保留**：RepositoryCache D1–D9、localStorage DiskKv、GhReadCache、DraftStore、TTL/失效/完整性；另做 Web 专项优化（见第三节） |
| 底座 | Ed25519 引导清单验签、统一网络栈、日志（内存级，不落盘） | 信任链与失败可见性不能砍 |

## 二、砍除（页面 / 模块 / 依赖）

### 2.1 整块功能
- **搜索**（含仓库搜索/代码搜索、SearchResultsPage、代码编辑器内全局搜索入口）
- **下载管理**（IxDownloadManager、分片引擎、预签名、后台下载、下载页、后台通知）
- **Actions**（运行列表、日志查看/查找/下载、重跑失败作业、取消运行）
- **Gist**、**通知中心**、**工作流派发**（草稿箱页面**修正为保留**，属提交相关）
- **Release 详情/新建**（与仓库代码功能无关的外围）
- ~~Issue/PR 详情~~（**修正：保留**）、~~提交图 / 新仓库向导 / 仓库设置~~（**修正：全部保留**）
- **AI 全套**（`lib/domain/ai/*` 5 文件、`ai_http_client_*`、AI 设置/聊天页、AI 审计工具）
- **权限网关**（Web 无原生权限：存储/通知/窗口能力全砍，相关文案删除）
- ~~多账号切换~~（**修正：保留**）、**加速通道**（浏览器 CORS 下本就不可用）、**自定义 DNS/DoH**（Web 无裸 socket）
- **窗口/桌面能力**（window_manager、托盘、自绘标题栏、桌面图标）

### 2.2 依赖裁减（19 → 目标 8）
| 保留（12） | 砍除（11） |
|---|---|
| flutter / flutter_localizations / flutter_markdown / url_launcher / crypto / cryptography / re_editor / re_highlight / **path_provider**（app_dirs Web 实现仍引用）/ **flutter_secure_storage**（Web 实现为内存态令牌，无明文落盘）/ **yaml** / **connectivity_plus** | flutter_svg、permission_handler、window_manager、saf_util、saf_stream、background_downloader、archive、flutter_local_notifications、isolate_manager（视 `dart2wasm` 实测结果决定，若仍需要则保留） |

### 2.3 平台胶水
- 保留并精简 `web_net_transport.dart`（浏览器 HTTP）、`platform_web_impl.dart`（内存 KV）、日志 stub、窗口占位、条件导入配对
- 删除所有 `*_io.dart` 在 Web 未被引用的实体（保留编译可达性所需的最小桩）

## 三、性能优化（第一优先）

| 项 | 做法 | 量化目标 |
|---|---|---|
| **首屏体积** | 砍除依赖后 wasm 主包自测；大模块用 `deferred as` 延迟加载（发现页、编辑器、设置各成一个 deferred 库） | 主包 ≤ 现有 60% |
| **冷启动** | 启动路径只做：零依赖占位屏 → 日志/信任链 → 装配 → 首帧；发现页/推荐/通知**一律进 tab 后懒加载**（`_visited` 已具备机制），不在启动时拉任何列表 | 首帧前 0 次业务 API 请求 |
| **字体** | 默认**系统字体栈**（零字体下载）；内置 Ubuntu Mono 按需、思源宋体从 Web 设置中移除（30MB 下载对浏览器不可接受） | 首帧 0 字体请求 |
| **CanvasKit/wasm** | 保持 `--no-web-resources-cdn` 同源加载；字体清单与 CanvasKit 由外层加载器并发预取（已有实现）并加真实进度条 | 进度可见 |
| **长列表** | 仓库目录/发现页/问题汇总一律 `ListView.builder` + `RepaintBoundary`；禁止 `shrinkWrap` 与一次性 `Column(children:[...])` | 1000 项滚动不掉帧 |
| **README/Markdown** | 超长文档分块渲染（复用 `log_body.dart` 的虚拟化思路），代码块高亮延后到可视区；图片 `loadingBuilder` + 错误兜底 | 大 README 首屏 ≤ 200ms 主线程 |
| **网络** | 只读缓存 TTL 分层（列表短、详情长）；并发上限按浏览器 6 连接收紧；取消在途请求；加速通道能力探测（剥头/改写如实留痕，不静默降级） | 切 tab 不堆积请求 |
| **缓存（Web 专项）** | localStorage 写入配额超限→隔离+告警（不静默丢）；索引带长度+摘要校验；草稿先落盘再展示；GhReadCache 键含 Accept 维度（防 raw/JSON 串）；TTL 过期条目启动清扫 | 刷新后缓存仍可用且不脏 |
| **令牌** | 内存态 + `flutter_secure_storage` 砍除后，刷新即需重登作为**明确取舍**写入登录页文案（不静默降级） | 无隐式行为 |
| **构建** | wasm 为主产物、js 仅兜底；`--tree-shake-icons` 全量开启；`web/` 静态资源按版本桶长期缓存 | 二次访问命中缓存 |

## 四、实施顺序（建议）

1. **裁依赖 + 删页面**（一次性拿到体积收益，先跑 `flutter build web --wasm` 验证可编译）
2. **补 Web 桩**：`ix_download_backend_web`（如实抛不支持/或整链删除）、令牌内存态实现、日志 stub
3. **三 tab 懒加载 + deferred 拆分**（性能主收益）
4. **化简设置页**（单页、六语言文案同步、气泡宽度沿用 main 的统一规格）
5. **性能基线对比**：首屏字节数 / 首帧时间 / 长列表滚动 / 二次访问缓存命中，四项出实测数据
6. **发布**：`web` 分支独立版本号（建议 `v13.0.0-web-lite`），`web.yml` 构建、`changed/` 站点登记

## 五、明确取舍（需在 UI 如实说明）

- 刷新页面需重新输入访问令牌（无持久化保险库）
- 无下载、无 Actions、无 Gist、无搜索；Issue/PR 详情保留；网络加速与缓存能力全部保留（浏览器限制项如实说明）
- 私有仓库的 raw 图片受 CORS 限制，改走 API 取字节（已有实现）；加速通道在浏览器下哪些类别可用、哪些受 CORS 限制，设置页如实列出
- 以上全部**不静默降级**：入口不显示或按钮明确标注，绝不显示后无声失败
