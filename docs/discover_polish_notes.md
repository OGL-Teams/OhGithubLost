# 逐项记录：改动 → 理由 → 验证

> 范围：发现页 = `lib/surface/pages/search_page.dart` 的 DiscoverPage（动态 / 推荐 / Issues 三子标签）
> + `lib/surface/widgets/discover_rows.dart`。基准 HEAD `fbbd93a`（期间另一并行代理在 `105f7ed` 提交，
> 本文档记录的改动以两者叠加后的工作区为准）。纪律：不动页面结构，只做小步打磨，每步可编译。

## 一、已改项（3 项）

### 1. 骨架与数据态行节奏对齐（任务项 1）— ✅ 改
- **改动**：`_SkeletonList`（search_page.dart）由 `ListView.builder` 改为
  `ListView.separated` + `const Divider(height: 1)`，与动态 / Issues 数据态的
  `ListView.separated(separatorBuilder: Divider(height: 1))` 节奏完全一致。
- **理由**：动态 / Issues 两 tab 数据态每行之间有 1px `Divider`（6 行累计 5px），
  骨架态没有。加载完成瞬间整列内容上移数像素——这正是任务点名的「不对齐会闪跳」
  中可以零风险修掉的部分。骨架行内部结构（状态条占位 + 标题行 + 元信息行）
  与 `OgLFeedRow` / Issues 行的三段式高度已对齐，未动。
- **验证**：源码级可 diff 复核（`ListView.separated` + `Divider(height: 1)`）；
  回归锁 `test/surface/ui_regression_test.dart` 新增断言钉住该契约。

### 2. 推荐卡 README 切片可展开也可收起（任务项 4）— ✅ 改
- **改动**：`_RepoCardState.build` 中 README 切片的 `InkWell.onTap` 由
  「仅折叠态可点（展开后 onTap: null）」改为 `setState(() => _readmeExpanded = !_readmeExpanded)`。
- **理由**：原实现是「只进不退」的单向门：用户点开后想收回摘要，唯一的路径是
  离开页面回来。toggle 是同一交互元素的对称补全，无结构变化、无新依赖、无文案需求
  （展开/收起箭头图标 `expand_more`/`expand_less` 已有，随状态切换，语义完整）。
- **验证**：回归锁断言 `_readmeExpanded = !_readmeExpanded` 存在于 `_RepoCard`
  源码段内（防止退回单向门）。

### 3. 推荐 tab 错误重试文案键修复（任务项 6）— ✅ 改
- **改动**：`_buildRecommendedTab` 错误分支的重试按钮文案键由 `_t('retry')` 改为
  `_t('categoryRetry')`，并在六个语言分片
  （`assets/i18n/{zh,zh_Hant,en,de,fr,ru}/search_page.json`）新增 `categoryRetry` 键
  （重试 / 重試 / Retry / Erneut versuchen / Réessayer / Повторить）。
- **理由**：`search_page.json` 分片**没有** `retry` 键，`OgLI18n._raw` 的兜底链
  （当前语言 → 英文基线 → 键名）会一路落到键名，六语言用户全部看到字面量「retry」。
  修文案必须键六语言齐补（i18n_scan --check 强制键集合与 zh 一致），已同步补齐。
  重试逻辑本身（`_loadMoreRepos()`）不动；`_issues` / `_feed` 的错误已走
  `AsyncView` → `OgLAsyncErrorPane`（其内部重试按钮用的是 `common.json` 的
  `retry` 键，兜底正确），不需要改。
- **验证**：`python3 tool/i18n_scan.py --check` exit 0（键集合一致、值全字符串、
  0 处未本地化）；回归锁断言 `search_page.dart` 不再包含 `_t('retry')` 且包含
  `_t('categoryRetry')`。

## 二、评估过但不改的项（含理由）

### 1. 骨架行高与推荐卡高的深对齐 — 不改
- 推荐 tab 的真实行是**双列 `_RepoCard`**（标题 + 两行描述 + README 切片 + meta 行，
  卡片高度随内容浮动 100~200px+），骨架行是紧凑三段式（约 64px）。要「对齐」只能
  把骨架做成假卡片网格——但骨架态只在 `_repos.isEmpty && _repoLoading` 的**首屏**
  出现，且首帧到数据态是整列表替换（非逐行过渡），骨架高度不影响切换后的视觉连续性；
  做假卡骨架反而引入新的「骨架像什么」的维护负担。收益/风险比不足，LTS 前不动。
- 任务项 1 说「仅调整明显错位的」——行节奏（1px Divider）是明显错位，已修；
  行高形态差异不是「错位」，不改。

### 2. 下拉刷新结构核对（任务项 2）— 无需改
- 逐一核对：动态 tab `OgLRefreshIndicator` 包 `AsyncView`（列表可滚动 ✅）；
  Issues tab `Column(stretch) > [OgLIssuesFilterChips, Expanded(AsyncView…)]`——
  筛选行**不在**刷新作用域内，`AsyncView` 的列表在 `Expanded` 内独立可滚，
  无嵌套滚动问题；推荐 tab `OgLRefreshIndicator` 只包 `Expanded` 内的
  `LayoutBuilder > ListView`，分类筛选行在刷新器之外，结构正确。
  回归锁已有「不留裸 RefreshIndicator」的全页面扫描测试兜底。
- 结论：结构无恙，零改动。（任务自己预判的「RefreshIndicator 包整个 Column
  会有嵌套滚动问题」在当前代码里不成立——它只包 Expanded 内的列表。）

### 3. Issues 行信息密度（任务项 3）— 已达标，无需改
- 元信息行已显示 `仓库名 #编号 · 作者 · 相对时间`（`_repoFullOf` + `ghInt(item,'number')`
  + `ghLogin` + `_relativeTime`），仓库与编号（issue #N）都在。标题/图标/评论数/
  进入箭头齐备。补无可补。

### 4. 推荐卡宽屏间距令牌核对（任务项 4 余项）— 已达标，无需改
- 卡片间距走 `OgLSpace.xxs`（网格 Padding.all）、内边距 `OgLSpace.md`、
  meta 行 `OgLSpace.sm`/`xxs`，全部是令牌，无裸数字；双列阈值 `600` 是
  Material 常规窗口档位断言，`ui_audit` 未报。长按菜单（打开/克隆/浏览器）已有。
- README 摘要切片、版本号、star 数显示均已在（`_readmeOf`/`_versionOf`/
  `repo.stars`），本次只修了上面第 2 条的交互缺口。

### 5. 分类筛选行窄屏溢出（任务项 5）— 结构性风险，不改
- 五档 `SegmentedButton`（热门 / TypeScript / Dart / Flutter / Rust）在 360dp
  窄屏确实接近溢出临界。但改横滑（`SingleChildScrollView`）或 wrap 属于**组件
  类型更换**，会牵动 `_repoCategory` 选中语义、`Semantics(label: categoryFilter)`
  包裹层与 `_kCategoryQueries` 的五档耦合，且 Issues tab 已用 FilterChip 横滑行
  （`OgLIssuesFilterChips`），把推荐 tab 也换成同款等于把 B17「chip 三套写法」
  的统一工作提前到 LTS——该重构在 `audit_spec_b.md` B17 有明确的排期与双模
  设计，不宜在本轮塞进。真机若有溢出反馈，按 B17 方案统一处理。

### 6. 错误与重试（任务项 6 余项）— 已达标，无需改
- `_issues` / `_feed` 走 `AsyncView`，其错误态用 `OgLAsyncErrorPane`
  （message + 重试按钮 `controller.load`），自带重试。推荐 tab 重试见已改项 3。

### 7. 空态文案六语言齐全（任务项 7）— 已达标，验证通过
- `feedEmpty` / `issuesEmpty` / `recommendedEmpty` / `starredEmpty` 六语言分片
  均有（`starredEmpty` 当前无调用方——star 仓库的发布区块不在发现页三 tab 内，
  属于历史键，i18n_scan 不因未引用报错，保留）。
  `python3 tool/i18n_scan.py --check` exit 0 复核通过。

### 8. 回归锁（任务项 8）— 已补
- 见上文三条已改项各自的验证段：新增源码断言测试
  「发现页打磨契约（LTS 前打磨项）」，照既有 `_readSource` 静态断言风格，
  三条断言分别钉住骨架节奏契约、重试文案键契约、README toggle 契约。

## 三、过程备注（供下一任接手）

- 本轮确认：本地可用 `dart`（3.13.7，`/opt/d3137/dart-sdk/bin`）与 CI 版本一致；
  `--language-version=3.6` 下 3.13.7 的 dart_style 对**其余未触碰文件**零漂移，
  仅上述三个被并行代理提交的文件存在风格代际差异（其余文件 `dart format
  --language-version=3.6 --output=none lib test` 全部 CLEAN）。
- 工作区另有并行代理的下载系统改造在途（download 相关文件），与本任务无交集，
  未触碰。
