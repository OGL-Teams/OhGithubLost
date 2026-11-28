# 修复任务书 · 第三轮（用户点名 4 个问题）

> 用户原话（2026-11-28）：①「顶端的分支选择条，这就是我之前跟你说的间距超出的问题，你仍然没有修好」；②「启动速度简直是一坨屎，我怀疑你是反复边界着色器，没有优化缓存」；③「在主分支或其他分支进入子目录之后再切换分支，如果对应分支没有相应的子目录就会 404」；④「代码预览和代码编辑器会重复请求那个代码文件，而不是直接读本地缓存。正确的网络缓存实现方式应该在我们的层级布置中的网络层实现对于相似而且没有时效性要求的请求，直接从缓存中读取并返回，而不是在逻辑层完成」。
> **「很多地方都值得优化，但是优先保证层级原则和代码干净度。我对代码有洁癖。」**

## 铁律（所有子代理必须原样带上）
1. **禁读 Flutter SDK**：禁止读取/下载/复制 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码；只用项目自身 lib/ 已验证代码；需要框架 API 事实就跳过并标「待核实」；本地 dart 仅用 `/opt/dart/bin/dart format`。
2. **层级原则（最高优先）**：L0 kernel → L1 base → L2 domain → L3 surface 单向依赖；**禁止越级 import**（`tool/layer_audit.py --fatal` 必须 0 违规）。
3. **代码干净度**：不留死代码、不留空回调、不留"以后再说"的 TODO 分支；每个改动都要有注释说明**为什么**这么做；命名与既有风格一致。
4. 只读审计不改代码的席产出报告；实施席改代码 + 自检，不 commit / push（主会话提交）。

## 四个修复项（分 3 席并行，范围互斥）

### 席 A · 分支条间距 + 切分支 404（lib/surface/pages/repo_page.dart）
- **A1 分支条高度**：`_branchBar` 的 ListTile `contentPadding` 带 `vertical: OgLSpace.md`（12），叠加 ListTile 自带垂直内边距 → 整条 80dp（截图实测）。改为**只保留水平 padding**（`horizontal: OgLSpace.lg`），高度回到 M3 标准 56dp。同时校正 leading 图标与标题间距、trailing「默认」标签与箭头的间距（标签与箭头之间至少 OgLSpace.sm，不要贴死）。验收：分支条总高 ≈56dp。
- **A2 切分支 404**：进入子目录后切分支，若新分支无该目录，`listDirectory` 抛 404（gh_api.dart:766 之后 rethrow）→ 页面显示错误。正确行为：**回退到该分支的根目录**并给一次轻提示（复用已有 i18n 键，不新增）。实现位置在 surface 层（`_CodeTab`/`_pickBranch` 侧），domain 层的 404 语义保持不变（不吞、不折叠）。
- 验收：rg 确认 `contentPadding` 无 vertical；切分支后路径不存在时不再出现错误面板。

### 席 B · 启动性能（lib/main.dart + lib/kernel/boot/ + lib/base/disk/）
- **B1 定位真实耗时**：启动串行 await 链是 `OgLLogFile.init`（多候选目录探测）→ `baseLayerModulesOnPlatform`（平台存储/密钥库解析）→ `kernel.boot`（**逐文件 sha256 + Ed25519 验签**，171 个 dart 文件）→ 权限自检。逐项给出耗时假设与修法。
- **B2 修**：把**不阻塞首帧**的工作移出启动关键路径（首帧前只做必要的；完整性校验、权限自检改为 runApp 之后并行做，且结果通过既有通知/诊断链触达——不静默）。目标：首帧不再等待完整性校验。
- **B3 缓存**：日志目录探测结果做**进程内记忆**（同一进程不要反复探测多个候选目录）；平台存储解析结果复用。
- 验收：启动日志里各阶段耗时可读；首帧前的 await 数量明显减少。

### 席 C · 缓存下沉到网络层（架构级，lib/base/net/ + lib/domain/gh/）
- **C1 现状**：读缓存逻辑在 L2 逻辑层（`lib/domain/gh/gh_read_cache.dart` + `gh_api.dart` 里每个方法各自 `_cacheKeyFor` + `_cache.read` + sha 前缀判断）——逻辑层在管缓存策略，重复且易漏。
- **C2 目标**：把「相似且无时效性要求的请求直接命中缓存返回」下沉到 **L1 网络层**：在 `lib/base/net/` 增加 HTTP 读缓存（装饰器/传输层实现皆可，但必须在 net 层），按请求特征判定可缓存性（GET、只读资源），命中直接返回；domain 层只表达"这次要强一致/要回源"的意图。
- **C3 边界**：不得让 base/net 依赖 domain（禁止 import domain/gh）；domain 现有的 `RepositoryCache`（D1–D9 一致性契约，见 docs/CONSISTENCY.md）**语义不变**，只是把"读路径的缓存命中"这条职责收到网络层——若发现两者职责重叠，先在报告里给出边界方案再改，**不要贸然删除 ConsistencyCache 契约**。
- **C4 重复请求**：代码预览（file_preview_page）与代码编辑器（code_editor_page）打开同一文件时重复请求 —— 改为第二次读已缓存内容（缓存键必须含 fullName + branch + path + 变体(JSON vs raw)，避免跨端点污染）。
- 验收：同一文件连续打开两次，第二次无网络请求；layer_audit 0 违规；`tool/contrast_audit.py` 等门禁不受影响。

## 交付纪律
- 每席完成即自检：`/opt/dart/bin/dart format --language-version=3.6 --set-exit-if-changed --output=none lib test`（0 changed）+ `python3 tool/layer_audit.py --fatal`（0 违规）+ `python3 tool/gate_of_gates.py --fatal` + `python3 tool/i18n_scan.py --check`
- 有行为改动时同步更新受影响的测试断言（v15 经验：断言与新行为不符会让 CI 红）
- 报告写入 `docs/FIX_ROUND_3_REPORT.md` 的对应小节（**先读全文再 append，禁止 file_write 覆盖**）
