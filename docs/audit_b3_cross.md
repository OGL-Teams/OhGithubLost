# 第 3 批 · 三视角交叉报告（GitHub API 层，v12.0.0 LTS）

> 三份原始记录：`audit_b3_a.md`（15 条）/ `audit_b3_b.md`（13 条）/ `audit_b3_c.md`（20 条），合计 48 条。
> 规则：三方命中=确证优先修；两方=复核；单方=主会话亲自 `file_read` 复读坐实/否决。
> 所有修改只在工作区，经全套门禁验证后才提交。

## 一、三方/两方命中（确证，已修或已裁决）

| 组 | 三视角命中 | 裁决 | 状态 |
|---|---|---|---|
| G1 | A-06 / C-18 /（B-08 关联）`jsonAsList`/读路径静默吞非法响应 | 确证 P1 | ✅ 已修：`jsonList`/`jsonAsList` 严格解析（非数组/坏 JSON/混入非对象一律抛 `FormatException` 并留 ERR 日志），新增 `test/domain/gh_list_strict_test.dart` 5 条断言 |
| G2 | A-07 / C-18 /（B-03 关联）`readmeExcerpt`/`latestVersionOf` 用 `on Object` 吞一切 | 确证 P1 | ✅ 已修：三处 catch 改 `OgLLogFile.line(... level: 'ERR')` 留痕 |
| G3 | A-02 / C-18（缓存键维度） | 确证 P1 | ✅ 已修：`readmeExcerpt` 加 `cacheBypass: true`，raw 文本不再与 JSON README 共用缓存 |
| G4 | A-03 / C-10 / B-03 `_isAbsentStatus` 读路径把 409/422 折成「不存在」 | 确证 P1（与 B2-A-05 P0 裁决相反） | ✅ 已修：只认 404，409/422 一律 rethrow |
| G5 | A-01 / C-09（测试缺口）`lockIssue` 用 PATCH（官方 PUT） | 亲自复读坐实 **P0** | ✅ 已修：`NetMethod.put` + label，新增 `test/domain/gh_write_endpoints_test.dart` 锁死 method/path/body |
| G6 | A-05 / B-05 `transferRepo` 202 异步待接受被当完成 | 亲自复读：UI 文案「已发起」并不假称完成，但**注释断言 full_name 已变 + 立即 pop** 属伪造成功 | ✅ 已修：更正 API 注释、六语言文案明确「待对方接受，仍在当前账号名下」、去掉 `pop` |
| G7 | A-11 /（C-09 关联）D8 重放定时器 3 次空转永久自停 + 防重入复位在死路径 | 亲自复读坐实 **P1**（提交入队后永不补做） | ✅ 已修：定时器不自停、异常在同一个 catchError 复位、启动期重放不再误改共享标志 |
| G8 | A-04 /（B-02 关联）游客 401 触发全局令牌失效出口 | 确证 P1 | ✅ 已修：发现页未登录时直接返回空动态，不发注定 401 的 `/notifications` |
| G9 | B-01 /（A-15 关联）`updateIssueLabels`/`Assignees` 全量替换丢他人设置 | 复核为 **P1 待议**：需写前重读远端合并，改 UI 交互面较大 | ⏳ 记录未修（`audit_b3_cross.md` 待办） |
| G10 | B-02 /（C-08 关联）`rawText` 第一跳令牌无主机白名单 | 复核为 **P1 结构性缺口**，当前唯一调用点是 GitHub 返回的 raw_url（待议可达性） | ⏳ 记录未修 |
| G11 | C-12 / C-13 门禁脚本自述能力 > 实际能力 | 确证（P0/P1 指「CI 全绿但语义无守卫」） | ⏳ 记录：docstring 第 5 项未实现、layer_audit 不解析 export；后续独立补 |

## 二、单方命中（亲自复读裁决）

| 编号 | 结论 |
|---|---|
| A-08 `GhReadCache.clear()` 只增纪元不删旧 key | P2 确认（资源无界），记录未修 |
| A-09 分支/ref 裸插值 | P2，需端点实测，记录待议 |
| A-10 206 回读不比对本次写 sha | P2，明确肯定主修复更严（206 无条件回读），并发风险待议 |
| A-12 `__list` 死分支 | P2 确认，与 C-20 同条，记录 |
| A-14 `_defaultBranchMemo` 无失效 | P1 确认（换默认分支后进程内永久用旧 ref），记录待修 |
| B-06 `dispatchWorkflow` 无二次确认 | P2 确认，记录 |
| B-07 IPv6 长形式回环/死代码分支 | P2 确认，记录 |
| B-10 `token_exit_warning` 只认一个凭证头 | P2 确认，当前无暴露，记录 |
| C-01/02/14/15/16/17 文档滞后 | P1/P2 确认，纯文档，后续批次统一同步 |
| C-04/05 危险端点确认靠注释、void 方法未声明 204 语义 | P1/P2 确认，**不改公共接口**（LTS 纪律），记录 |
| C-07 `surface/types.dart` hide/show 名单不符 | P1 确认，与 G11 一起后续补门禁 |
| C-11 `putContentLocked` 头注释「永不抛」不成立 | P1 确认，注释改「裸写路径可能抛 GhAuthException」比改行为更安全，待办 |
| C-19 `CacheRemote.read` 无差别吞 404 | P1 确认，需区分 404 body（空仓库 vs 分支失效），与 G4 同族，待办 |

## 三、经证据否决/降级（不误修）

- **B-05「转移/删除确认缺失」**：亲自复读 UI 有输入+二次确认，守卫存在；仅文案/202 语义问题（已并入 G6）。
- **B-11/B-12/B-13**：OAuth 落库脱敏、路径编码截断防护、私有加速警告+批量 confirmed 类型强制——三处确证通过，不动。
- **C-06**：L2 文件头格式偏好，报的是「门禁未检查硬惯例」而非排版，并入 G11。

## 四、本批结论

GitHub API 层**核心写链路与历史 P0 修复扎实**；风险集中在「四线新增端点语义未经实测 + 契约/文档/测试未随 LTS 同步」。本轮已修 **8 组确证问题（含 1 个 P0）**，新增 2 份离线回归测试；其余 P1/P2 均有编号、理由与待办归属，不冒充确证、不在代理运行期提交半成品。

修复提交后自动启动**批 4（下载管理）**三视角审计。
