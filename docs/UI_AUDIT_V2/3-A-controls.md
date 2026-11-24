# 批 3-A · 控件变体与图标语义复审（v15 之后）

> 文档戳：2026-11-24 22:46:28 · v15.0.0+150000
> 依据：material-3 SKILL.md Components 节、sota-frontend-design rules/03-design-systems-components.md（token 三层/语义词汇表/9 态契约）、lib/surface/util/og_l_icons.dart、lib/surface/theme.dart、docs/UX_CROSS_AUDIT/3-A-controls.md（旧 19 条）
> 方法：rg 全量统计 lib/surface/pages/ 按钮变体（FilledButton 94 / TextButton 57 / OutlinedButton 13 处）、图标语义（OgLIcons. 8 处 vs 裸 Icons.* 29 处）、禁用态 35 处。只读未改代码。

## 一、闭环核对（旧确证逐条判定）

| 旧条目 | 判定 | 证据 |
|---|---|---|
| S1 危险确认框两种写法并存 | **修法有问题（部分修）** | 已建统一入口 `ogLConfirm(danger:)` / `ogLDangerConfirm`（lib/surface/app/overlays.dart:85-144），收编 7 处（issue/repo_tags/profile/notifications/drafts/gist_detail/放弃修改）✅；但 **repo_page 仍 5 处手写 error 底 AlertDialog**（1613/1712/3291/3963/4025/4257 附近：删文件/删目录/删分支/Transfer/删仓库），release_detail_page:195-206、settings_page:268-272、token_exit_warning:156 亦手写——同一危险语义两条实现并存，helper 的 error/onError 前景 vs 手写版默认前景也不一致 |
| S2 新建主操作三级分裂 | **未修** | new_gist_page.dart:147、workflow_dispatch_page.dart:416 仍是 AppBar TextButton；new_issue:176 / new_repo:199 / new_release:239 是表单底 FilledButton——三种权重并存原样 |
| S3 重试按钮三种变体 | **未修（余一处）** | OgLAsyncErrorPane 统一 FilledButton.tonal（async.dart:437）✅，search_page 已走 errorPane ✅；但 repo_tags_page.dart:189 失败重试仍是**实心 FilledButton**，与全库 tonal 惯例分裂 |
| M5 drafts 查看弹窗权重错排 | **未修** | drafts_page.dart:182 删除草稿仍是最高权重 FilledButton（无 error 色），「去编辑器」tonal 屈居其后 |
| M7 repo_tags 缺 FAB | **未修** | rg FloatingActionButton：gists/dashboard/repo_page×4，repo_tags 无 |
| M8 search 分类档位两型 | **未修** | search_page.dart:1355 SegmentedButton 仍在；834/1025 已统一 FilterChip（两处已收敛、tab 分类残留） |
| M9 Pages 启用/禁用并排 | **未修** | repo_page.dart:4513-4521 仍 FilledButton.tonal(启用)+OutlinedButton(禁用) 并排 |
| M10 repo_page 下拉无 label | **未修** | repo_page.dart:4438-4441 decoration 仅 border，无 labelText |
| M11 legal 裸 DropdownButton | **未修** | legal_text_page.dart:148 仍裸 DropdownButton |
| M12 取消运行权重 | **未修** | action_run_page.dart:638 取消仍 OutlinedButton.icon（重跑 tonalIcon 626） |
| L19 外链出口两型 | **未修（轻微）** | gist_detail:385 TextButton.icon / 其它 IconButton 并存 |
| B-04（4-B 席）dirty 返回丢数据 | **已修（核对通过）** | 8 页带 dirty PopScope：new_gist/new_issue/new_release/new_repo/workflow_dispatch（各 2 处）/code_editor/settings/repo_page:4570 |
| B-05（1-B 席）命中区 | **已修** | theme.dart:184/411 minTouch 48×48、minButton 64×48 落到 text/outlined/iconButton 四类主题；rg 页面无小尺寸 IconButton/iconSize 裸值 |
| B-08（1-A 席）禁用色 | **已修** | theme.dart 为 Filled/Text/Outlined/Icon 四类按钮统一 `disabledForegroundColor: onSurface 0.60`（410/421/431/442）；页面无手写降透明禁用（rg withValues(alpha:0.3) 0 命中） |
| G-11 图标语义 | **修法有问题（层建了、没收编）** | 见 §二 |

## 二、回归：v15 语义图标层覆盖度（rg 全量）

`og_l_icons.dart` 定义 7 常量（copy/copyAll/refresh/retryAll/openExternal/delete/share），全库**引用仅 8 处**（search/repo/release_detail/file_preview/download/about）；裸 `Icons.*` 语义动作图标仍有 **29 处**：

- `Icons.content_copy` 4 处：settings_page:2311、download_manager:494、about:146、notifications:389
- `Icons.open_in_new` 11 处：search:958、repo_page:602/1288/1999、action_run:656、gists:181、download:489、file_preview:214、about:168/184/343、login:470
- `Icons.delete_outline` 10 处：repo_tags:238、settings:787/1615、issue:441、drafts:235、repo:2035/4577、profile:266、gist_detail:344、release_detail:476
- `Icons.refresh/restart_alt` 4 处：action_run:626/635、action_log:318、download:475

**典型冲突实例**：search_page.dart 同一弹层 958 行 `Icons.open_in_new`（打开仓库）与 973 行 `OgLIcons.openExternal` 并用——同一动作两种来源，违背 og_l_icons.dart:9「页面动作图标一律引用本层」的自述约定。语义本身目前无错配（未再发现 link 顶替复制），但**覆盖度 8/37≈22%**，单一事实来源名存实亡。`Icons.link`（settings:778「添加 URL」选项）属静态链接语义，可接受。
disabledForegroundColor 回归：新值 0.60 对 onSurface 对比充足，未引入可读性问题；IconButton 主题 iconSize 走 OgLIconSize.xl(24)，与页面 OgLIconSize 分档一致。

## 三、新发现

**P1-1 · helper 半收编造成两种危险确认实现**（即 S1 遗留，升级表述）：手写版 7 处（repo_page×5、release_detail:201、settings:270）未走 `ogLConfirm(danger:true)`，且 repo_page:3963 Transfer 确认钮文案用泛化 `confirm` 而非动词宾语。修复指令：release_detail/settings/token_exit_warning 全部改调 ogLDangerConfirm；repo_page 5 处 AlertDialog 改 `ogLConfirm(danger: true, confirmText: _t('deleteFileAction') …)`，删掉手写 error styleFrom。
**P1-2 · 泛化文案残留**：settings_page.dart:850「OK」（添加字体 URL 确认，应改「添加」）、repo_page.dart:3884/3966「confirm」（保存分支设置/Transfer，应改「保存更改」「转移仓库」）。其余全库按钮均为动词宾语（创建/发布/提交/删除 X），质量良好。
**P1-3 · 图标层收编**（§二 29 处）：指令——逐文件把上述裸 Icons.* 换成 OgLIcons.* 常量（机械替换，8 处已换的文件可作样板）；并在 og_l_icons.dart 增补 `cancel`（Icons.cancel_outlined，action_run:639）与 `edit`（edit_outlined，issue:436）避免二次漂移。
**P2-1 · 禁用态缺原因说明**：全库 35 处 onPressed:null 禁用中，仅 new_repo/new_gist 等以 busy 文案（「创建中…」）间接说明；4 处空态 CTA（drafts:205、commit:164、search:1397、issue:852）禁用且**无任何视觉/文案原因**（代码注释自述「待核实」）——用户看到灰色「去创建」按钮不知道为什么点不动。建议：待核实路由未决前先移除该 CTA，或补 helperText。
**P2-2 · delete_sweep 孤例**：notifications_page.dart:175 清空通知仍用 `Icons.delete_sweep_outlined`（全库唯一），与 OgLIcons.delete（delete_outline）分叉；属批量语义可保留，但应入图标层成为 `deleteAll` 常量并让确认文案带「全部」（resetTitle 已满足）。

## 四、用户满意度（三问之外）

- 「看到就知道会发生什么」：图标→动作映射目前**正确率高但来源混乱**（22% 收编），复制/删除/外链语义无错配 ✅；危险确认钮颜色差异能传达后果，但只对走 helper 的 7 处成立 ⚠️。
- 主操作权重：填表类页面底部 FilledButton 一致 ✅，AppBar 文字链提交（new_gist/workflow_dispatch）让用户低估「发布」的分量 ✗。
- 禁用按钮：busy 态有文案反馈 ✅；4 处无路由 CTA 是「点了没反应」的潜在来源 ✗。

## 五、P0/P1/P2 汇总

- **P0**：无（无数据丢失/不可用级问题；S1 遗留最接近但因二次确认仍在，降 P1）。
- **P1**：①危险确认 helper 半收编（7 处手写残留）②新建主操作三级分裂（S2）③图标层覆盖 22%（29 处裸 Icons）④repo_tags 重试实心 FilledButton⑤drafts 删除钮权重+无 error 色⑥泛化文案 OK/confirm 3 处。
- **P2**：①禁用无原因 4 处 ②delete_sweep 孤例 ③M7/M8/M9/M10/M11/M12/L19 共 7 条旧中等项未修（详见 §一表）。

## 六、本席对三问的回答

1. **闭环**：15 条旧确证中已修 3（B-04/B-05/B-08），修法有问题 2（S1 helper 只收编一半、G-11 图标层只覆盖 22%），未修 10（S2/S3/M5/M7/M8/M9/M10/M11/M12/L19）。核心结论：**v15 建好了「基础设施」（helper、图标层、disabled 令牌），但存量调用点没收编**。
2. **回归**：v15 引入的 disabledForegroundColor / OgLIconSize / ogLConfirm / ogLDangerConfirm 本身实现正确、无新缺陷；唯一回归风险是图标层约定与实际用法脱节（8/37），约定每多存在一天漂移越多。
3. **新发现**：P1-2 泛化文案 3 处、P2-1 无原因禁用 CTA 4 处、P2-2 delete_sweep 孤例；其余复检未发现旧审计外的新变体问题。

## 七、已检查清单

- [x] og_l_icons.dart 全文（7 常量与约定）
- [x] theme.dart 全文 505 行（四类按钮主题/minimumSize/disabled*）
- [x] rg：FilledButton(94)/TextButton(57)/OutlinedButton(13)/FAB(6)/PopScope(8 页)/showModalBottomSheet(3)/AlertDialog 手写(repo_page 15)
- [x] 裸 Icons.{content_copy,open_in_new,delete_outline,refresh,restart_alt,link,language,delete_sweep} 全命中点 29+2 处逐一过语境
- [x] ogLConfirm/ogLDangerConfirm 实现+7 调用点；repo_page/release_detail/settings/token_exit_warning 手写危险框逐处读上下文
- [x] 新建类 5 页（new_issue/new_gist/new_repo/new_release/workflow_dispatch）主操作变体
- [x] 重试点 5 处（async.dart errorPane/repo_tags/search/repo_page 加载更多/download）
- [x] 禁用态 35 处 onPressed:null 分类（busy 防重入 vs 无路由 CTA）
- [x] 泛化文案 rg（确定/OK/是/提交/confirm）全库
- [x] 30 页矩阵复检旧 3-A 全部 19 条的现存证据行号
- [x] 未覆盖移交：TextField label/键盘（→3-C）、三态骨架（→3-B）、SnackBar 语气（→4-B）
