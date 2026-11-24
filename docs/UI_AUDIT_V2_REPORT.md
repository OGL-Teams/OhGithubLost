# UI 深度复审 V2 · 交叉汇总报告（15 席 → 打磨计划）

> **文档戳 / Doc Stamp**
> - 更新时间：**2026-11-24 23:15:42 (Asia/Shanghai)**
> - 版本：**v15.0.0**（HEAD `46981c0`，`pubspec.yaml` version 15.0.0+150000）
> - 仓库：`/root/OhGithubLost`；**只读汇总**：未改代码、未 commit/push
> - 输入：`docs/UI_AUDIT_V2/` 下 15 份席位报告（1-A/1-B/1-C、2-A/2-B/2-C、3-A/3-B/3-C、4-A/4-B/4-C、5-A/5-B/5-C），全部逐份完整读取，未抽样
> - 口径：闭环判定取多席交叉后的**合并判定**（多席同判从众，分歧从严）；新发现/回归同根因合并并标注来源席

---

## 0. 结论速览

| 维度 | 结果 |
|---|---|
| 旧 61 条确证闭环 | **已修 18 / 修法有问题 21 / 未修 19 / 本轮未覆盖 3**；闭环率 **29.5%**（严格口径）；含部分闭环 **64%** |
| v15 回归（去重后） | **17 组**：P0 × 1、P1 × 13、P2 × 3 |
| 新发现（去重后） | **P0 × 2、P1 × 28、P2 × 25** |
| 打磨批次建议 | **7 批**；最小可行方案 = 前 3 批 |
| 一句话判词 | v15 把「空、漂浮」修成了「看得见、点得到但走不完」——**基础设施建好了（令牌/骨架件/图标层/notifier/档位表），但存量调用点大面积没收编**，这是所有残留问题的共同根因 |

---

## 1. 闭环总表（旧 61 条确证逐条合并判定）

判定来源：各席「闭环核对」表交叉合并；同一编号多席判定时取多数/从严。M-/C-/L-/A- 开头的旧账延伸项（v14 审计中的中低级条目）附在表尾一并给状态。

| 编号 | 问题 | 合并判定 | 依据（席） |
|---|---|---|---|
| B-01 | 全局描边失效 | **已修** | 1-A（strong 明暗五级 ≥3:1） |
| B-02 | 输入框空闲态无边界 | **修法有问题** | 1-A（主题默认值已设，但 40 处裸 `OutlineInputBorder()` 未删） |
| B-04 | dirty 返回丢数据 | **已修** | 3-A（8 页 PopScope 齐备） |
| B-05 | 命中区过小 | **已修** | 3-A、5-C（minTouch 48×48 主题层生效） |
| B-08 | 选中态不可见 | **已修** | 1-A（listTile/navBar/navRail 同 token） |
| B-1 | 启动占位屏配色脱节 | **修法有问题** | 2-A、5-A（消了硬编码黑白，但只跟平台亮度，不跟用户 mode/Material You） |
| B-2 | `_checked` 裸转圈中间态 | **未修** | 2-A、5-A（`client_shell.dart:278-280` 逐字保留） |
| B-3 | 失败页堆栈溢出 | **修法有问题** | 2-A（溢出已修；无复制/重试动作、裸键名、强制深色仍在） |
| G-01 | 卡片无接地 | **已修** | 1-A |
| G-02 | AppBar 无边界 | **已修** | 2-C（scrolledUnder=2 + 插值） |
| G-03 | 弹层层级跳变 | **已修** | 1-A（card<sheet<dialog 恢复） |
| G-04 | 输入框底色过深 | **已修** | 1-A |
| G-05 | 宽屏 720 裁切 | **修法有问题** | 2-C、2-B、5-B（AppBar full-bleed 达成；720 限宽下沉未做，`contentMax` 死常量） |
| G-06 | 启动链路锚定总项 | **修法有问题** | 2-A（B-2 未修、15s 超时未做、三态 AnimatedSwitcher 未落地） |
| G-07 | 禁用色过淡 | **修法有问题** | 1-A（暗色过；浅色 60% 仅 4.12–4.44:1 未达 4.5） |
| G-08 | 侧栏无接地 | **修法有问题** | 2-C（轨面已修；VerticalDivider 未删、无 SafeArea、无 groupAlignment） |
| G-09 | 切页透明鬼影/横移 | **修法有问题** | 2-C、2-B、4-C（鬼影+过冲已消；「顶栏静止」未实现，AppBar 仍在位移子树） |
| G-10 | 分页截断 | **已修** | 5-B（pageSize 与 per_page 对齐） |
| G-11 | 语义图标层 | **修法有问题** | 3-A、2-C、5-B、5-C（层已建，收编仅 22%，29 处裸 Icons.*；「发现」无 selectedIcon） |
| G-12 | 分页模式三分 | **修法有问题** | 2-C、5-B（数据层控制器统一；交互仍「自动滚动 vs 手动按钮」三分） |
| D-01 | 页面 gutter 五档并存 | **修法有问题** | 2-B（五档→两档，搜索/通知页残留） |
| D-02 | 卡片套卡片 | **已修** | 2-B |
| D-03 | 列表行死区/一屏 11 条 | **未修** | 2-B、5-B（行模板、density 全未动，一屏仍 8–9 条） |
| D-04 | issue 详情首屏 0 评论 | **未修** | 2-B、5-B |
| D-05 | 空态半屏占位/无 CTA | **修法有问题** | 2-A、2-B、3-B（半屏已删、13 处 CTA，但 4 处假按钮 + 11 处仍无 CTA） |
| D-06 | 裸转圈/骨架统一 | **未修** | 3-B（骨架仅 1 处调用，16 处裸转圈仍在） |
| D-07 | issue/PR meta 缺状态与规模 | **未修** | 2-B、5-B |
| D-08 | 8dp 逃逸/字面量间距 | **未修** | 2-B |
| D-09 | 搜索两套 gutter/通知不对称 | **未修** | 2-B |
| D-10 | 评论整块 Card/行距不一 | **未修** | 2-B |
| D-11 | README 行高/标题层级 | **未修** | 2-B、1-B（三项计划值均未落地） |
| D-12 | 设置过疏/尾部死区 | **未修** | 2-B |
| D-13 | 菜单行高/网格阶梯/评论输入沉底 | **未修** | 2-B、5-B |
| D-14 | 空态文案/游客态/Semantics | **修法有问题** | 5-A（首用文案好；游客态无差异化、CTA 误导） |
| F-01 | 写操作零进度 | **已修** | 4-B（issue `_dialogBusy` 是全库范本） |
| F-02 | 关议题无 busy/确认 | **已修** | 4-B |
| F-03 | SnackBar 无统一三语气 | **已修** | 4-B（三重区分；但主题 shape/elevation 零消费，1-A T-07） |
| F-04 | 登录 phase 灰小字无进度 | **未修** | 5-A（词条已写好未接线） |
| F-05 | 无防重入 | **已修** | 4-B |
| F-08 | 错误不在字段旁 | **修法有问题** | 3-C（改了 SnackBar 视觉，没改错误位置；errorText 仍仅 1/47） |
| F-09 | 必填零标记 | **未修** | 3-C（仍仅 2 页） |
| F-10 | AppBar 连按重复提交 | **未修** | 3-C（busy 闸后置于校验之后） |
| F-11 | 失败伪装成空 | **修法有问题** | 3-B（2 处已修；file_preview 空文件仍说「文件过大」） |
| F-12 | 转场不消费 secondaryAnimation | **已修** | 4-A（shared-axis X + 对向退场） |
| F-13 | 返回链吞手势 | **修法有问题** | 4-A（maybePop 接力已落地；`_backHandling` 静默吞第二次返回） |
| F-14 | 档位接线失效 | **未修** | 4-A、4-C（路由 300ms/主题 160ms/对话框 150ms/系统返回四处全未接） |
| F-15 | 时长/位移失配 | **修法有问题** | 4-A、4-C（6 项仅「淡入同窗」修好，错峰 806ms/fast 170ms/easeOutBack 10% 过冲仍在） |
| F-16 | 切 tab 无接力/连点被吞 | **未修** | 4-C（且连点时新页朝错方向滑入） |
| F-18 | 成功无确认 | **修法有问题** | 4-B（_close/_downloadLogs ✅；_cancel/_remove/分支增删改/删发布 ❌） |
| F-20 | 乐观更新无回滚说明 | **修法有问题** | 4-B（入队提示有；持久条目/角标未做） |
| F-21 | 深链与滚动恢复 | **未修** | 5-A、5-B（全库 0 深链；切号滚动归零） |
| S-01 | 唯一加载态是空白+转圈 | **未修** | 3-B |
| S-02 | 目录行只有标题（36% 填充） | **未修** | 2-B、5-B（`repo_page.dart:2599` 逐字 null） |
| S-03 | 空态半屏占位 | **已修** | 2-B、5-A（dashboard 已换 EmptyPane+CTA） |
| S-04 | Sliver 缺 emptyAction | **修法有问题** | 3-B（架构打通，但 issue 的 CTA 是禁用的） |
| C-01 | 整页转场缩放 | **已修** | 4-A（三档 scale 全 1 + 门禁） |
| C-05 | 切 tab 透明 0.70 鬼影 | **已修** | 4-A（0.94） |
| S1 | 危险确认框两套写法 | **修法有问题** | 3-A（helper 收编 7 处；repo_page 5 处等仍手写） |
| **未覆盖 3 条** | 旧账中 3 条无席认领 | **本轮未覆盖** | 均为 v14 中 L 级低危条目（深链相关 1 条归入 F-21 记账、其余 2 条无用户可感知面） |

**统计：已修 18 / 修法有问题 21 / 未修 19 / 本轮未覆盖 3（合计 61）**
- 严格闭环率 = 18/61 ≈ **29.5%**；含「修法有问题」的部分闭环 = 39/61 ≈ **64%**。
- 旧账延伸项（非 61 主表）：M5/M7/M8/M9/M10/M11/M12/L19（3-A，**8 条全部未修**）、M-07/M-08/M-09（1-C，**未修**）、M-06（1-C，已修）、A-M6/A-L2/A-L3（1-B，**未修**）、A-M7（1-B，修法有问题/风险缓解）、C-S1（两套 AppBar，未修）、C-S2（已修）、C-S6（分页，未修）、A-M1/A-M2（已修）、A-M3（修法有问题）、C3-C-01/C3-C-10（3-C，未修，与 F-08/F-10 部分重叠）。→ **延伸项 25 条：已修 6 / 修法有问题 3 / 未修 16**。

**闭环总判**：v15 四批（主题层/骨架状态/外壳转场/反馈闭环）在「定义层」完成度高（令牌、helper、骨架件、notifier、档位表全部真实落地），但**「消费层」没有跟上**——40 处裸输入框、16 处裸转圈、4 处假 CTA、29 处裸图标、7 处手写危险框、39 处未接档位的路由、0 处 retry/undo 接线。主题席 1-A 的判词可作全轮总结：「一次修主题应该全站生效的承诺没有兑现」。

---

## 2. 回归清单（v15 引入/暴露的问题，去重后按 P0/P1/P2）

> 同根因多席报 = 确证（括注席位数）。

### P0

- **R1 · 4 处空态 CTA 是假按钮（`onPressed: null` 直接发版）**【2-B/3-B/5-A/5-B 四席确证】
  `issue_page.dart:852`、`commit_page.dart:164`、`search_page.dart:1397`、`drafts_page.dart:205`。代码注释自认「待主会话/CI 裁决」就发布了。FilledButton.tonal 高辨识外形 + 点不动 = 比 v14 的「空」更糟。3-B 席列为 P0（发布纪律事故 + 主动误导）。

### P1

- **R2 · 300ms 防抖加在请求上而不是指示器上**【3-B/2-B/5-B】`async.dart:56/61/157-181`：先空等 300ms 再发请求；`minLoadingDuration` 因起算点含防抖而永不触发；`PagedController`/`dashboard._RepoPaged` 又没有这套逻辑——有防抖的页面凭空慢 0.3s，没防抖的照样闪。
- **R3 · 骨架屏非列表形且只覆盖 1/13**【3-B/2-B/5-B】`OgLAsyncSkeleton` 仅 2 块 68dp、垂直居中、92% 留白、与最终布局零重合（CLS 未解决）；`OgLAsyncSliver` loading（`async.dart:644`）仍裸转圈；search_page 还保留私有 `_SkeletonList` 双套并存。
- **R4 · 16 处裸转圈加载分支未换骨架**【3-B/2-A】13 处占满内容区（dashboard 首屏 `dashboard_page.dart:436`、repo 五处、file_preview、legal、repo_tags、onboarding、search 首搜、client_shell `_checked`）。
- **R5 · 40 处裸 `OutlineInputBorder()` 吃掉 v15 头号卖点**【1-A】新输入框描边在最常用表单（新建仓库/issue/设置/搜索）上缺席；`code_editor_field.dart:791/849` 另用 `InputBorder.none`。
- **R6 · 语义色明暗不同步**【1-A】success 暗色 diff 正文 2.39:1 近乎不可读；warning 浅色 4.03–4.24:1；`tool/contrast_audit.py` 因配对方式漏检（实跑报 0）。
- **R7 · SnackBar 主题零消费**【1-A】v15 的「暗色 actionTextColor 修复」在真实提示上没发生；`notifier.dart`/`error_surface.dart` 裸构造绕开 snackBarTheme。
- **R8 · 顶栏两套色阶 + 两套 AppBar**【1-A/5-C/2-B】OgLAppBar 插值起点 `surface` vs 主题 `surfaceContainerLow`；15 页 OgLAppBar vs 15 页裸 AppBar；`surfaceTintColor: transparent` 使 scrolledUnder 只剩阴影。
- **R9 · 启动链路回归**【2-A/5-A】首页首帧裸转圈（骨架没接上）；boot_splash 只跟平台亮度（用户强制主题/Material You 下闪变，叠加 `themeAnimationDuration: slow` 更惹眼）；三态切换无过渡、品牌锚点被硬切抹掉；Material You 晚到二次变色。
- **R10 · navRail 被 call site 覆盖**【1-A/2-C】`labelType` 覆盖主题、`VerticalDivider(width:1)` 未删、无 SafeArea/groupAlignment（下方 70% 空柱）；600–1200 档 rail/底栏密度感受不同。
- **R11 · 切 tab 连点朝错方向滑入**【4-C】`client_shell.dart:468-470` `isAnimating` 早退与已切换的 index 竞态；快速连点第 2 次切换被静默吞或方向错乱。
- **R12 · reduce-motion/系统关动画对页级转场、主题、对话框、Hero 完全无效**【4-A/4-C】且 `main.dart:152-166` 横幅宣称「动画将不可见」与实际相反（误导性文案）。
- **R13 · 路由时间线恒 300ms + 档位 3 错峰 806ms**【4-A/4-C】39 处 MaterialPageRoute 无 transitionDuration；运动只占前 42–70%，每级留 90–174ms 死等；stagger 36ms×16 = 末项 ≈806ms 可见。
- **R14 · 注释与实现漂移**【2-B/4-C/5-B】「顶栏由外层持有保持静止」未实现；「统一加载更多」repo_page 仍手动按钮；档位表 `shellOffset 0.05` 被 clamp 到 0.02（档位表说谎）；`contentMax` 死常量；onboarding 注释宣称语言/外观第一步但实现没有。

### P2

- **R15 · 强描边层级压平 + 接地靠线不靠阶**【1-A】明色描边 4–5:1 与 `outline` 同强，74 条分隔线同等强调；surface→container 仅 1.11:1。
- **R16 · 转场灰帧/过冲/弹簧被吃**【4-A/4-C】新旧页半透明叠加灰帧；easeOutBack 10% 过冲用于每个控件；切 tab 弹簧回弹被 `clamp(0,1)` 抹平（档位 3 = 档位 2）。
- **R17 · 启动屏字号/转圈规格跳变**【1-B/2-A】boot_splash 钉死 18px；转圈四套规格并存（22/24/默认/OgLIconSize）。

---

## 3. 新发现汇总（旧审计未抓到，去重合并，标注来源席）

### P0（2）

- **N-P0-1 · settings 加速通道弹窗吞输入**【3-C】`settings_page.dart:1907-1947`：先 `pop(true)` 后校验 URL，失败仅 SnackBar 并 dispose controller——用户填好的通道名/URL 全丢，必须重填。修法：仿 `repo_page.dart:1448-1523` StatefulBuilder 实时校验范式。
- **N-P0-2 · 4 处假 CTA 发版**（= 回归 R1，兼记新发现账）【2-B/3-B/5-A/5-B】。

### P1（28，同根因已合并）

| # | 问题 | 来源席 | 关键证据 |
|---|---|---|---|
| 1 | 提交闸后置（3 处可重复提交：CI 重跑/重复 Gist/重复评论） | 3-C | `workflow_dispatch:319-340`、`new_gist:86-96`、`issue:589-611` |
| 2 | 字段级错误仅 1/47；18/47 无可见 label（17 hint-only + 1 全裸） | 3-C | `rg errorText` 仅 `repo_page:1472`；`gist_detail:187` 全裸 |
| 3 | 失败提示全库零「重试」出口；Undo 0 处 | 4-B | `actionLabel/onAction` 基建在但业务接线 0% |
| 4 | 评论输入沉底 + issue 首屏 0 评论（看讨论 2–5 屏，够到输入框 2.5–3 屏） | 2-B/5-B | `issue_page:791-838/925-958` |
| 5 | 游客态 CTA 误导（「新建仓库」必 401）、无「去登录」路径 | 5-A/2-B | `dashboard_page:453-461` 无 guest 分支 |
| 6 | 登录页 PAT「怎么拿令牌」词条已写好整块未上屏 | 5-A | zh/login.json:4-13 零引用 |
| 7 | Device Flow 无过期倒计时、expired/denied 未接 UI | 5-A | `gh_oauth_types:9-24`、`login:503-507` |
| 8 | sliver 形态无软错误通道——下拉刷新失败静默吞 | 3-B | `async.dart:611-620` 不读 softError |
| 9 | 空文件被告知「文件过大」（原因错配） | 3-B | `file_preview:236-239` |
| 10 | repo_tags_page 整页仍是「另一套 UI 语言」 | 3-B | `:188-224` 裸 Text/转圈/一行字 |
| 11 | new_gist 校验/提交失败仍一次性 Toast | 3-B | `new_gist:88-125` |
| 12 | 危险确认 helper 半收编（7 处手写残留） | 3-A | repo_page×5、release_detail:201、settings:270 |
| 13 | 泛化按钮文案 3 处（OK/confirm×2） | 3-A | settings:850、repo_page:3884/3966 |
| 14 | 新建主操作三级分裂（AppBar TextButton vs 表单底 FilledButton） | 3-A | new_gist:147、workflow:416 等 |
| 15 | FAB 让路只覆盖 1/6；圆形 FAB 实际只收 57%；展开 easeOutBack 过冲 ≈4dp | 4-C | `scroll_aware_action:230-247/180` |
| 16 | 启动内核 boot 无超时（无限裸转圈无出口） | 2-A | `main.dart:222` |
| 17 | 启动失败页是死胡同（无复制日志/重试） | 2-A | `og_l_app:188-209` |
| 18 | 宽屏 gist 文件固定 0.5 屏高（1.2 文件/屏，全库最差密度） | 2-B | `gist_detail:484-488` |
| 19 | 通知行 3 行技术噪声 + 16/8 不对称（一屏仅 6 条） | 2-B | `notifications:312/327` |
| 20 | 等宽字号三套体系割裂（monoSm12/monoMd13/codeFontSize/平台默认14） | 1-B | `og_l_font:9-14`、6 处无 fontSize 的 mono |
| 21 | 2.0x 缩放四处固定尺寸破版（release 键列 72dp、查找面板 40dp 行高、两处 maxHeight） | 1-B | `release_detail:429`、`code_editor_field:733` 等 |
| 22 | 宽屏两栏结构性留白：rail 顶对齐无底座、桌面无主操作入口 | 2-C | `client_shell:373-403` |
| 23 | 高频页批量操作（多选/全选）全缺；设置无搜索 | 5-B | 六页 rg 0 命中 selection |
| 24 | 下载 release 产物 5–7 次点击（R5 先详情后下载反转） | 5-B | `release_detail:557/340-347` |
| 25 | Chip 命中区约 34–38dp <48 | 5-C | `theme.dart:432-434` |
| 26 | scroll_aware 收边元素不可键盘/读屏激活；未读状态语义丢失 | 5-C | `scroll_aware_action:368`、`discover_rows:69-73` |
| 27 | 搜索结果无筛选/排序/历史；代码命中不定位行 | 5-B | `search_page:1355-1426` |
| 28 | 无键盘快路径（`/`、Cmd+K）；深链缺失（外部链接永远落首页） | 5-B/5-A | rg shortcuts 0 |

### P2（25，归并为 9 组）

1. **页面裸弱线/令牌未消费**：ColorPicker `outlineVariant` 1px×4 处、`surfaceContainerLowest` 0 使用、Divider 高度裸值 8 处、SnackBar/弹层边框遮罩缺失【1-A/1-C】。
2. **动效打磨**：返回闸静默吞第二次、sheet 出场等长、1 处 sheet 旁路、Hero 无终点（半截 Hero）、首启三段硬切、repo TabBarView 未档位化、桌面宽窗整页横滑、引导页前后同长、`transitionOffset` 注释语义错、AppBar 滚动渐变整栏重建、fast 170ms、档位 0 非全静默、零触感反馈、收边点击无按压反馈、搜索 300ms 防抖体感滞后【4-A/4-C】。
3. **排版打磨**：boot_splash 裸 18、NavRail/Segmented 未派生 textTheme、hint 与输入值不同档、README 行高 1.5、Dialog 标题 22 应 24（归回归 R 组联动的 P2 部分）【1-B】。
4. **形状间距**：取色器 48dp 色块过度圆化、`contentMax` 语义混装、圆角工厂表达不一、列表行 12 vs 16 分叉（discover_rows/repo 筛选框）【1-C】。
5. **状态打磨**：空态 subtitle 全库未用、11 处空态无 CTA、6 处禁用无原因、成功语气误用 info/warning 共 10 处、error_surface 横幅「第四种语气」、busy 对话框可被 barrier 关、new_* 四页无按钮内转圈、按钮宽度跳变、Switch 说谎（提交型表单）、minLines 缺失、行号 clamp 无提示、查找条无边框、表单宽屏无语义宽度、字段无分组节奏【3-B/4-B/3-C】。
6. **控件**：delete_sweep 孤例、2 处无名 IconButton、桌面标题栏 46×38 命中区、无最小窗宽、warning 浅色 4.03:1、contrast_audit 工具 dark-only 缺口、code_editor_toolbar 窄窗溢出风险、chip 行键盘横滚【3-A/5-C】。
7. **效率**：repo_page 手动分页按钮、切号 ValueKey 重建丢滚动、perPage 三种、发布/PR/commits/runs 空态无出口、登录 phase 灰小字、权限告警仅通知中心弱可见【5-B/5-A/3-B】。
8. **启动**：失败页 i18n 裸键名/强制深色、转圈规格四套、占位屏字号不跟缩放、空态「去搜索」落点不符【2-A】。
9. **主题**：动态配色下强描边/选中态无运行期门禁、输入框 hint 动态色贴线【1-A】。

---

## 4. 分批打磨计划（核心交付）

排批原则：**先修「用户一打开就撞见」的，再修「天天用都硌手」的，最后收一致性**。每批 ≤15 文件、单一主题、可独立验证。工作量：S ≤半天 / M 1–2 天 / L ≥3 天。

### 批次 1 · 最刺眼的：假门、死等与裸转圈（预估 M，约 2 天）

| 编号 | 问题 | 文件（file:line） | 动作 |
|---|---|---|---|
| R1/N-P0-2 | 4 处假 CTA | `issue_page.dart:852`（+评论 FocusNode）、`commit_page.dart:164`（无 html_url 则删）、`search_page.dart:1397`（接 `_switchMode(0)`）、`drafts_page.dart:205`（删或改刷新） | 接真或删，不许留 null |
| R2 | 300ms 防抖加错位置 | `async.dart:56/61/157-181` | 请求立刻发；指示器 300ms 后才显示；min 从数据到达起算；120ms grace + 150ms min（5-B 建议） |
| R3 | 骨架非列表形 | `async.dart:371-410`（加 itemCount/itemBuilder，72dp 行 + 顶部对齐）、删 `search_page.dart:71-148` 私有骨架 | 统一为一个列表骨架件 |
| R4 | 裸转圈→骨架 | `async.dart:644`、`dashboard_page.dart:436/484`、`repo_page.dart:790/819/2453/2528`、`file_preview_page.dart:222/496`、`repo_tags_page.dart:199`、`search_page.dart:1389`、`client_shell.dart:278-280`、`legal_text_page.dart:176`、`onboarding_page.dart:364` | `client_shell` 换「正在恢复会话…」品牌恢复屏 |
| R9 部分 | 首页首帧 | `dashboard_page.dart:435-436` | 接骨架 |

- **验收**：`rg -n "onPressed: null" lib/surface/pages` 在四个空态点为 0；全库 `CircularProgressIndicator` 加载分支 ≤1（仅 boot_splash）；任何页面首帧有 ≥6 行同形骨架；连切 tab 5 次无 300ms 空等。
- **风险**：骨架行高与真实行高不一致会残留 CLS——骨架行高必须从列表行模板取同一常量；`client_shell` 恢复屏需新增 i18n key（30 语言分片）。

### 批次 2 · 边界与接地：40 处裸边框、两套 AppBar、侧栏接地（预估 M–L，2–3 天）

| 编号 | 问题 | 文件 | 动作 |
|---|---|---|---|
| R5/B-02 | 40 处裸 `OutlineInputBorder()` | `new_repo_page:152/161`、`new_issue_page:147/156`、`repo_page×9`、`settings_page×4`、`issue_page×5`、`search_page:1378` 等 | 批量删除 `border:` 覆写；确需无框的显式 `InputBorder.none` + filled |
| R8 | 顶栏两套色阶 | `og_l_app_bar.dart:139`（起点改读 `theme.appBarTheme.backgroundColor`） | 统一起点色 |
| R8/5-C | 15 页裸 AppBar | `issue_page:763`、`notifications:159`、`commit:93`、`gist_detail:340`、`release_detail:458`、`file_preview:206`、`code_editor:579`、`action_run:526`、`action_log:290`、`pull_page:109`、`download_manager:191`、`workflow_dispatch:413`、`new_gist:144`、`legal_text:100`、`login_page:326` | 全部迁 `OgLAppBar`（已支持 actions/bottom，迁移无阻塞） |
| R10/G-08 | rail 接地 | `client_shell.dart:376-402`（删 VerticalDivider、+SafeArea、+groupAlignment、labelType 交还主题） | 宽屏侧栏单一边界 |
| R6 部分 | SnackBar 主题消费 | `notifier.dart:129-146`、`error_surface.dart:572-578` | 补 shape/elevation/actionTextColor 或统一 `OgLSnackBar` |

- **验收**：`rg -n 'border: (const )?OutlineInputBorder\(\)' lib` = 0；`rg -n 'appBar: AppBar\(' lib/surface/pages` = 0；设置页任一输入框空闲态有可见 1px 描边；宽屏侧栏无双线、图标居中。
- **风险**：15 页 AppBar 迁移是行为面最广的一刀——OgLAppBar 的滚动插值需每页有 scrollController 或回落 scrolledUnderElevation；搜索框/编辑器查找条的无框样式需逐个确认不是「删了更有框」。

### 批次 3 · 状态与反馈：错误可恢复、危险收编、语气统一（预估 M，2 天）

| 编号 | 问题 | 文件 | 动作 |
|---|---|---|---|
| N-P0-1 | 弹窗吞输入 | `settings_page.dart:1907-1947` | StatefulBuilder 实时校验（范式 `repo_page:1448-1523`） |
| 新 P1-1 | 提交闸后置 3 处 | `workflow_dispatch:319`、`new_gist:86`、`issue:589` | handler 首行 `if (_busy) return`（约 6 行） |
| 新 P1-3 | 失败零重试 | `issue_page._runWrite`、`repo_page._close` 等 catch 处 | 传 `actionLabel: retry`（基建 `notifier.dart:89-95` 已在） |
| 新 P1-9 | 空文件说成过大 | `file_preview:236-239` | 新增 `previewEmpty` 键 + 重试按钮 |
| 新 P1-8 | sliver 吞刷新错误 | `async.dart:611-620` | 插入 `OgLAsyncSoftErrorBar` |
| S1/新 P1-12 | 危险确认收编 7 处 | repo_page×5、`release_detail:201`、`settings:270`、`token_exit_warning:156` | 改 `ogLDangerConfirm` |
| 4-B 语气 | 成功误用 warning/拦截误用 info | `repo_page:3046`（→success）、`issue_page:238/471/593`（→warning） | 逐点改 tone |
| 新 P1-11 | new_gist 一次性 Toast | `new_gist_page:88-125` | 改内联 errorContainer + errorText |

- **验收**：加速通道弹窗校验失败时输入保留且字段旁有红字；全库写操作失败 SnackBar 100% 带「重试」；`rg 'AlertDialog' repo_page` 危险路径 0 处手写 error 底；三语气调用点语义抽查 0 错配。
- **风险**：retry 回调需闭包捕获原请求参数（防重放脏数据）；danger 收编要逐处核对确认文案动词化（transfer 等不能只写 confirm）。

### 批次 4 · 密度与效率：行模板降高、目录 meta、评论固定栏（预估 L，3–4 天）

| 编号 | 问题 | 文件 | 动作 |
|---|---|---|---|
| D-03/S-02 | 目录行 null subtitle / 行高 | `repo_page.dart:2599`（目录补 `N 项 · 时间`）、`theme.dart:370-377`（minVerticalPadding sm→xxs）+ 各列表 `dense:true` | 一屏 11→13+ |
| D-07 | issue/PR meta | `repo_page.dart:2813-2818/2941-2944` | issue 行加 labels chip + 相对时间；PR 加 +−行数 |
| D-04/13 | 评论体验 | `issue_page.dart:925-958`（输入提为 `Scaffold.bottomNavigationBar` 固定栏）、`:77` 加 FocusNode、`:852` 接活、`:864-919` 评论卡改平铺行 | 回评论 0 滚动 |
| N-04/19 | gist 半屏/通知噪声 | `gist_detail:484-488`（minHeight 80/maxHeight 320）、`notifications:312/327`（maxLines 2、对称 padding） | 密度最差两页回正 |
| N-05 | 空态 CTA 真实化（剩余 11 处无 CTA） | `repo_page:2950/3462/3677/3626`、`action_log:364`、`search:791/1042/1050`、`release_detail:526`、`download_manager:250` | 传 subtitle + 真实 action |
| G-12 | repo_page 手动分页 | `repo_page.dart:771-832` | 距底 300px 自动 loadMore + 按钮兜底；同步改 `:8` 注释 |

- **验收**：目录行有 meta；issue 详情首屏（664dp）可见 ≥1 条评论；输入框固定可见；一屏列表 ≥12 行；gist 详情 ≥2 文件/屏；通知一屏 ≥9 条。
- **风险**：评论固定栏改 Scaffold 结构需回归键盘 inset/PopScope 交互；dense 行降高后触摸行高仍须 ≥48dp；`minVerticalPadding` 改主题会影响全部列表，需逐页截图对比。

### 批次 5 · 表单与输入：label、字段级错误、提交闸、键盘栈（预估 L，3 天）

| 编号 | 问题 | 文件 | 动作 |
|---|---|---|---|
| 新 P1-2 | 18 处无 label / 46 处错误离场 | 17 处 hint-only（`font_pick:32`、`issue:936/1141/1175`、`repo_page:708/2502/3867`、`search:1373`、`workflow:474/505`、`code_editor_field:781/839`、`log_search:59`、`settings:838`、`action_log:329`、`code_editor:434`、`new_gist:177`）+ 全裸 `gist_detail:187` | 全部补 `labelText`；五个主表单按 `repo_page:1464-1473` 范式加 errorText |
| F-09/新 | 必填标记 2→全 | new_issue/new_repo/new_release/repo_tags/release_detail/issue | label 后缀「（必填）/（可选）」+ onChanged 即时清错 |
| 新 | 键盘/autofill 栈 | `settings:1181`（IP number）、`login:375`（AutofillGroup+password）、`repo_tags:288`（SHA autocorrect:false）、单行补 textInputAction | |
| 新 P1-14 | 新建主操作统一 | new_gist:147、workflow:416 | AppBar TextButton → 表单底 FilledButton（或反之，取一种） |
| 3-C N-08/09/11 | busy 宽度跳变、Switch 说谎、minLines | login:407、new_*×4、`new_release:214/221`、`new_issue:151`、`new_release:187` | 固定宽 spinner、Switch→Checkbox（提交型）、补 minLines |
| 3-C N-15 | 表单分组 | new_release:171-227、workflow:579-585 | 组内 12/组间 24 + section 标题 |

- **验收**：`rg -n 'errorText:' lib` ≥ 12；无 label 输入框 = 0；`gist_detail:187` 有 label；新建四页连点提交只产生一次请求；标签输入后错误即时消失。
- **风险**：`Form/TextFormField` 改造波及脏检查（PopScope `_dirty` 逻辑需同步）；autofill 需真机验证密码管理器识别。

### 批次 6 · 动效与一致性：档位接线、reduce-motion 全局、图标收编（预估 M，2 天）

| 编号 | 问题 | 文件 | 动作 |
|---|---|---|---|
| R13/F-14 | 路由时长接档位 | 新增 `OgLPageRoute`（medium/fast），替换 39 处 MaterialPageRoute | 消灭 90–174ms 死等 |
| R12 | reduce-motion 全局 | `motion.dart:332`（+systemReduce）、`surface_bridge.dart:525/578`、`og_l_app.dart:96-104`（主题动画直读档位）、`overlays.dart:80-83` | 档位 0 全静默；`main.dart:155` 横幅文案先改真实 |
| F-15/4-C | 错峰/过冲数值 | `motion.dart:241/244-245/253-254`（fast 150、stagger 24×6、settle 过冲 ≤3%） | |
| R11/F-16 | 切 tab 可中断接力 | `client_shell.dart:455-478` | 用当前 value/velocity 重定向；或 AnimatedSwitcher 成对接力 |
| G-11 | 图标收编 29 处 | `og_l_icons.dart` 增 cancel/edit/deleteAll；机械替换 29 处裸 Icons.* | 收编率 22%→100% |
| C-S6 | 分页统一 | `search_page:483/589/1258`、`notifications:434`、`repo_page:771` | perPage=30 常量 + 统一 load-more |
| 4-A P2 旁路 | 4 处 showDialog + 1 处 sheet | `settings:763/834`、`code_editor:427`、`font_pick:28`、`search:951` | 走 ogLShowDialog/ogLShowSheet |

- **验收**：`rg transitionDuration` ≥ 39；系统「移除动画」开启后页面/主题/对话框零动画；`rg -n 'Icons\.(content_copy|open_in_new|delete_outline|refresh)' lib/surface/pages` = 0；档位 1/2/3 切 tab 手感可区分。
- **风险**：39 处路由替换是机械但面广——需保证 `settings` 参数透传不变；档位表数值改动后跑 `tool/motion_audit.py` + `motion_coverage_audit.py` 双门禁。

### 批次 7 · 无障碍与收尾：48dp、焦点、读屏语义、对比度全量（预估 M，2 天）

| 编号 | 问题 | 文件 | 动作 |
|---|---|---|---|
| 5-C P1-1 | Chip <48dp | `theme.dart:432-434` chipTheme padding | 总高 ≥48 |
| 5-C P1-2/3 | 键盘/读屏 | `scroll_aware_action:368`（Focus+Shortcuts+button role）、`discover_rows:69-73`（未读语义前缀） | |
| R6 | 语义色明暗 | `theme.dart:223-226`（success/warning 分明暗）、`tool/contrast_audit.py` 扩浅色+「色本身 vs 四档容器」 | 暗 diff ≥4.5 |
| 5-C P2 | 2 处无名 IconButton、桌面标题栏语义、warning 浅色调深、toolbar 溢出、chip 键盘横滚 | `settings:1613`、`gists:180`、`desktop_window`、`code_editor_toolbar:117` | |
| 2-A P1-05/06 | 启动超时 + 失败页出口 | `main.dart:222`（.timeout 15s）、`og_l_app:188-209`（复制日志/重启） | |
| 5-A | PAT 指引接线、游客空态、Device Flow 过期 UI | `login_page`（howTo Card）、`dashboard_page:453-461`（guest 分支）、`login:503-507` | |
| 1-B | 2.0x 破版三处 + 等宽档位对照 | `release_detail:429`、`code_editor_field:733`、`readme_view:579`、`action_log:540`、`og_l_font` | 200% 无 overflow |
| 宽屏 | 720 限宽下沉 | `client_shell.dart:317-328` TODO → 各页 `Center(ConstrainedBox(maxWidth: 1040))` | 正文 ≤80 字符/行 |

- **验收**：`contrast_audit.py` 明暗两套 0 问题；TalkBack 可听出未读/选中/加载中；`/` 聚焦搜索（若做）；宽屏 1200dp 正文行 ≤80 字符。
- **风险**：限宽下沉动 10+ 页布局，需逐页验收宽/窄两态；`OgLFeedRow` 语义改动可能影响既有 smoke test。

### 「若只做三批」最小可行方案

1. **批次 1（假门与裸转圈）**——直接回答用户判词里的「空」：4 处假 CTA、300ms 空等、列表骨架、恢复屏。改动集中在 `async.dart` + 6 个页面，一天半可见全局观感变化。
2. **批次 2（裸边框 + AppBar 统一）**——直接回答「不像同一产品」：40 处输入框描边让 v15 头号卖点真正上线，15 页 AppBar 统一让滚动行为一致。机械替换为主，风险低收益大。
3. **批次 3（错误可恢复 + 危险收编 + 提交闸）**——直接回答「作为工具的稳定感」：失败能重试、危险框一个口音、连点不会重复提交 CI。改动小（大部分 ≤10 行/处），闭环感最强。

三批合计约 5–7 天，覆盖本轮全部 P0 + 约 60% 的 P1；剩余批次（密度/表单/动效/无障碍）可在三批验收后按序推进。

---

## 5. 诚实结论：v15 之后离用户满意还有多远

v15 把用户 v14 判词里的「空」和「漂浮」修掉了大半——主题令牌、转场方向、外壳锚定、反馈三语气这些**制度层**都是真实且高质量的落地，方向没有问题；但离「满意」还差最后一公里，而且这一公里很具体：**v15 建好的每一件基础设施都存在大面积未收编的存量调用点**（40 处裸输入框吃掉新描边、16 处裸转圈绕开骨架、4 处假 CTA 直接发版、29 处裸图标绕开图标层、39 处路由绕开档位表、全库 0 处 retry/undo 接线），同时**v15 自己还引入了两个新的体感债务**（300ms 防抖加错了位置让每次切页强制空等、骨架只有 68dp 反而更显空）。最大的缺口按用户可感知度排序是：①等待仍是「空等」（骨架不接首屏/sliver/防抖错位）——批次 1；②同类页面不像同一产品（两套 AppBar、两套顶栏色阶、有边框和无边框的输入框混排）——批次 2；③出错后没有出路（失败无重试、弹窗吞输入、假按钮点不动）——批次 3。做完前 3 批（约一周），应用能从「看得见、点得到但走不完」进入「稳定可信」；做完 7 批，密度、效率、无障碍的旧账（一屏 8 条、找 issue 3–4 屏、批量操作缺失、Chip 34dp）才能清完——那之后才谈得上用户说的「满意」。

---

## 附：本报告的证据边界

- 汇总基于 15 席报告的 file:line 证据（各席均声明 `rg` 可复现、只读、未读 Flutter SDK）；本席未重新扫描代码（信息以席位报告为准），仅做交叉合并与去重。
- 各席均附「已检查清单/未覆盖声明」；已知盲区：真机渲染帧率、TalkBack 实测、200% 缩放实机、原生启动图（仓库无 android/ 目录）——相关条目已标注「静态推断」。
