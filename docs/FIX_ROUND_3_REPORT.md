# 修复报告 · 第三轮

> 各席完成后在此追加小节（禁止覆盖他人小节）。铁律与验收口径见 `docs/FIX_ROUND_3_BRIEF.md`。

## 席 A · 分支条间距 + 切分支 404（lib/surface/pages/repo_page.dart）

### A1 分支条高度（回 M3 标准 56dp）

- `_branchBar` 的 ListTile `contentPadding` 去掉 `vertical: OgLSpace.md`（与 ListTile 自带垂直内边距叠加 → 整条 ~80dp，用户截图实测）；改为只保留 `horizontal: OgLSpace.lg`。现在分支条高度回到 M3 原生 ListTile 的标准行高（dense=false 时 ≈56dp）。
- leading 图标与标题：交回 M3 ListTile 原生间距规约（无自定义撑开），`leading: Icon(Icons.account_tree_outlined, size: OgLIconSize.md)` 不变。
- trailing 的「默认」标签与 `Icons.expand_more` 之间已有 `Padding(right: OgLSpace.sm)`（8dp ≥ 规约的 OgLSpace.sm 下限），未贴死，本项保持。

### A2 切分支 404 → 回退根目录 + 轻提示

- **决策位置在 surface 层**（`RepoPageState._onBranchPicked`，由 `_pickBranch` 选中分支后调用）；domain 层 `listDirectory` 的 404 语义不动（不吞、不折叠，`gh_api.dart` 未改）。
- 流程：
  1. 选中新分支后**先复位**：`_branch = next`、`_codePath = ''`（根）、`_codeInitialPath = null`，并清掉 `_CodeTab` 的旧状态 —— key 从 `code-$branch` 改为 `code-$branch-$_codePath`，路径复位会让标签重建并加载新分支根目录（不会拿旧路径打 404）。
  2. 若用户原在子目录（`previousPath` 非空），用 domain 既有的 `GhApi.content(fullName, previousPath, branch: next)` 做**单路径探测**（`content` 的 404 语义是「返回 null 不抛」）：
     - 探测到目录 → `setState` 恢复 `_codePath`（浏览位置无损）；
     - 探测 404（null）→ **安静停在根目录**，只给一次 `OgLNotifier.info` 轻提示（info 语气，非错误面板，不打断）；
     - 探测抛错（网络/限流）→ 安静停在根目录，不提示（避免失败噪音）。
- **提示文案**：新增 1 个键 `repo.backToRootBecausePathMissing`（zh：`该分支下没有此路径，已回到根目录：{path}`），30 语言分片全部补齐并对齐（此前审计：不存在可复用的「切分支路径回退」语义键；`pathNotFound` 是错误语境，不合适）。
- `unawaited(_onBranchPicked(next))`：探测不阻塞分支切换的即时 UI 反馈。

### 自检（全部落盘后实跑）

- `/opt/dart/bin/dart format --language-version=3.6 --set-exit-if-changed --output=none lib test` → **0 changed**（exit 0）。
- `python3 tool/layer_audit.py --fatal` → **0 违规**。
- `python3 tool/gate_of_gates.py --fatal` → 唯一红项 `contract_audit`，原因是**报告文件（本文件）当时尚不存在**（`docs/FIX_ROUND_3_REPORT.md: 引用的契约文档不存在`）——本文件落盘后即消除，属预置依赖而非席 A 代码问题；其余 11 项门禁全绿。
- `python3 tool/i18n_scan.py --check` → 通过（键集合 30 语言一致，0 处未本地化中文）。
- `contract_audit.py` 复核：本文件创建后合计归 0。
- 验收 `rg`：`repo_page.dart` 的 `_branchBar` contentPadding 无 vertical；`backToRootBecausePathMissing` 在代码与全部分片各出现。

### 未 commit / 未 push（按交付纪律，主会话提交）。

### 待核实项

- ListTile 实际渲染高度（≈56dp）需真机/模拟器目检确认（沙箱无法跑 Flutter 渲染）。
- `_CodeTab` key 含 `_codePath` 后，目录间导航（`_goTo`）会销毁重建 code 标签的 State —— 已核对 `PagedController` 快照键（`cacheKey` 跟随路径）与 `_bootstrap` 的恢复分支，行为等价，但建议真机过一遍「进入子目录→切走标签→切回」路径无闪动。
