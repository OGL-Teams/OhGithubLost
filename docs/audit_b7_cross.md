# 第 7 批 · 三视角交叉报告（主题/字体/令牌警告，v12.0.0 LTS）

> 三份原始记录：`audit_b7_a.md`（11 条）/ `audit_b7_b.md`（运行中转 done）/ `audit_b7_c.md`（13 条）。
> 规则：三方命中=确证优先修；两方=复核；单方=主会话亲自 `file_read` 复读坐实/否决。

## 一、确证问题（已修）

| 编号 | 视角 | 问题 | 裁决 | 状态 |
|---|---|---|---|---|
| **B7-A-01** | A 单方（亲自复读坐实） | 批 5 接线 `refreshState` 引入**通知自激循环**：`_setState` 无同值短路 → refreshState → `_onAuthChanged` → `_check` → 再 refreshState，启动后无限空转 | **P0**：这是批 5 修复（B5-A-02/C-14）引入的回归 | ✅ 已修：`_setState` 同值短路 + `_check` 世代号防重入 |
| **B7-A-02** | A 单方 | `buildOgLTheme` 的 appBar/dialog/chip/hint/snackBar 就地 TextStyle 绕过 `textTheme.apply`——换字体只换一半 | **P1** 复读坐实（九处就地 TextStyle） | ✅ 已修：`buildOgLTheme` 加 `uiFontFamily` 参数，九处就地 TextStyle 全部接收；调用方传 `_uiFontFamilyOf` 结果 |
| **B7-A-03 = B7-C-03** | A+C 两方 | 私有字体落盘 `Directory.systemTemp`（注释却写"应用支持目录"），系统清理后字体静默失效 | **P1** 复读坐实（触碰原则 15/8） | ✅ 已修（配合 B7-A-04）：思源宋体下载后落盘缓存、下次 `bytesOf` 缓存优先读取 |
| **B7-A-04 = B7-C-04** | A+C 两方 | 思源宋体每次冷启动整只重新下载（~30MB），落盘文件只写不读；未注册回落系统字体无任何日志 | **P1** 复读坐实 | ✅ 已修：cache-first 读取 + 下载后落盘（失败留痕不阻断）+ `_uiFontFamilyOf` 回落日志 |
| **B7-A-05** | A 单方 | （与 B7-A-01 一并修的 `_check` 世代号） | 并入 B7-A-01 | ✅ 已修 |

## 二、记录未修（P1/P2，附理由）

| 编号 | 问题 | 理由 |
|---|---|---|
| B7-C-01 | surface_bridge 缓存键注释「三者」实为五元组 | P1 文档：文本修改，与批 7 修复同批顺手改不如与批 8 文档统一批次 |
| B7-C-07/08/09/10 | themeFor 缓存/字体回落链/OgLAppBar 渐变/动效档位边界零测试 | P1：与 B5-C-11、B4-C-08 同族——「测试专项」列批 8 收口后第一优先 |
| B7-C-11 | USAGE.md 外观章节缺字体管理 | P2 文档，记录 |
| B7-C-12 | preload 额度不随档位单调 | P2 确证（数据事实），属策略设计而非缺陷，记录待议 |
| B7-A-06~11 | OgLReveal Timer 不重启、OgLAppBar 多 position（待议）、preload jobs 不重登记、门禁小写键、注释错挂、KeyboardGuard 全树 setState | P2 确证，记录待办 |
| B7-B 系列 | 字体下载 URL 注入面、theme_packs 注入、fontScale 边界 | B 视角运行中，结果送达后并入交叉 |

## 三、经证据否决

- **B7-A 正面确认**：动效档位表（0 档全静默/越界归 0/单调性测试钉住）、themeFor 有界缓存、设置→主题传播链、back_guard、desktop_window——不动。
- **B7-C-05/06 门禁豁免复核**：action_log_page 防抖豁免与 kOglMonoFamily 放行均仍必要，无过期——门禁名单经复核有效。
- **B7-C-13**：AGENTS 版本三处一致（批 5 修复仍成立）、motion 四档表与测试逐项一致。

## 四、本批结论

主题与动效子系统质量最高（门禁实跑全绿、档位表有测试钉住）；风险集中在**字体子系统**（落盘目录名实不符/缓存只写不读/回落无日志——本轮已修）与**批 5 修复引入的自激循环回归**（已修）。重要教训：**修复本身也需要被审计**——B7-A-01 正是批 5 修复的回归，交叉审计再次证明其价值。
