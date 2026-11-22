# 全仓库功能审计交叉汇总总报告（15 席）

> 文档戳：更新时间 **2026-11-23 07:24:36 +0800（Asia/Shanghai）** · **v15.0.0**
> 仓库 `/root/OhGithubLost` · 汇总对象：`docs/FUNC_AUDIT/` 下 15 份功能审计报告 · **只读审计，本轮未修任何代码、未 commit/push**
> 统计口径：逐份完整读取 15 份报告（1-A…5-C，约 25 万字），从每份「问题清单」按编号逐条累加；显式标注「撤销 / 核实为正确」的条目不计入（1-A 的 P0-1、P1-8）。4-C 为同一席拆成 pages-1 / pages-2 两个文件，统计时合并计席但分别计问题。

---

## 0. 覆盖声明与一处缺口（务必先读）

| 项 | 事实 |
|---|---|
| 报告文件数 | **15 个**（`1-A,1-B,1-C,2-A,2-B,2-C,3-A,3-B,3-C,4-A,4-B,4-C-pages-1,4-C-pages-2,5-A,5-C`） |
| 实际覆盖席 | **14 席**（4-C 一席拆两文件） |
| **缺失席** | **5-B（34 个 tool/ 门禁脚本判据有效性）报告不存在**——目录中 4-C 被拆成两份、5-B 位置被空出；`git status` 显示 `docs/FUNC_AUDIT/` 为未跟踪目录，无历史提交可恢复；全仓 `rg` 无「功能审计 5-B」正文 |
| 5-B 线索处置 | 任务书给出的 5-B 三项 P0（`sort_imports` 恒绿 / `gate_of_gates` 空扫绿 / i18n 反向验证错）**无法从 5-B 报告核实**。本代理改以「读工具源码 + 跑门禁 + 读既有审计文档」交叉验证：`tool/sort_imports.py:104,120` 已有 `--fatal` 退出码；`tool/gate_of_gates.py:76-139` 已实现空扫检测 + 两条反向注入；`docs/CONVERGENCE_STATUS.md:28,34` 记载二者分别为「批 9 已修 / C-12 已补」。**结论：这三项属历史已修缺陷，按当前代码不构成现役 P0**；下文「门禁失明」系统级结论改由可核实的 5-A + 5-C + 1-C + 4-B 证据支撑。 |
| 当前门禁实跑 | `python3 tool/sort_imports.py --dry-run --fatal` → 0；`python3 tool/gate_of_gates.py --fatal` → **exit 1**，唯一原因是 `contract_audit` 的文档契约引用（即本报告生成后应消解的红） |

---

## 1. 15 席原始问题统计

### 1.1 逐席明细

| 席 | 域 | P0 | P1 | P2 | 合计 | 主要编号 |
|---|---|---:|---:|---:|---:|---|
| 1-A | 数据层·API | 3 | 8 | 8 | 19 | P0-2/3/4；P1-1…7/9（P0-1、P1-8 撤销） |
| 1-B | 数据层·缓存 | 1 | 6 | 4 | 11 | 1B-01…1B-11 |
| 1-C | 数据层·引导信任 | 1 | 6 | 3 | 10 | P0-1；P1-1…6；P2-1…3 |
| 2-A | 认证网络·登录 | 1 | 3 | 4 | 8 | P0-1；P1-1…3；P2-1…4 |
| 2-B | 认证网络·传输 | 0 | 3 | 9 | 12 | P1-1…3；P2-1…9 |
| 2-C | 认证网络·编排 | 2 | 7 | 5 | 14 | P0-1/2；P1-1…7；P2-1…5 |
| 3-A | 任务下载·下载 | 0 | 6 | 2 | 8 | 3-A-01…08 |
| 3-B | 任务下载·通知 | 0 | 3 | 5 | 8 | P1-1…3；P2-1…5 |
| 3-C | 任务下载·文件操作 | 1 | 3 | 6 | 10 | P0-1；P1-1…3；P2-1…6 |
| 4-A | 展示·外壳 | 2 | 6 | 6 | 14 | P0-1/2；P1-1…6；P2-1…6 |
| 4-B | 展示·设置 | 1 | 4 | 4 | 9 | 4B-01…4B-09 |
| 4-C-1 | 展示·页面前半 | 0 | 4 | 3 | 7 | P1-1…4；P2-1…3 |
| 4-C-2 | 展示·页面后半 | 0 | 4 | 12 | 16 | 问题 1…16 |
| 5-A | 工程·测试 | 2 | 5 | 4 | 11 | A-1…A-11 |
| 5-B | 工程·门禁判据 | — | — | — | **缺报告** | 见 §0 |
| 5-C | 工程·发布 | 2 | 4 | 6 | 12 | P0-1/2；P1-1…4；P2-1…6 |
| **合计** | **15 文件 / 14 席** | **16** | **72** | **81** | **169** | — |

### 1.2 汇总口径说明（报告内部存在计数漂移，已按清单订正）

- **1-A**：结论行写「P0×3/P1×6/P2×8（17）」，但 P1 小节实际列 P1-1…P1-7、P1-9 共 **8** 条（P1-6 标注「建议降 P2」仍留在 P1 节），故按清单计 8。
- **2-A**：结论写「共 7 条」，实际 P0-1 + P1×3 + P2×4 = **8** 条。
- **2-C**：结论写「P1×6」，实际列 P1-1…P1-7 共 **7** 条。
- **4-A**：结论写「共 12 条（2 P0 / 4 P1 / 6 P2）」，实际清单列 P0×2 + P1-1…6（6）+ P2-1…6（6）= **14** 条（结论称 P1-5/P2-6 为低危联动项，但未撤销编号）。
- **4-C-2**：无总览表，按编号 1…16 计（P1=4、P2=12）。
- 其余各席与自身总览/结论一致。**表中一律按「问题清单实际编号条目」计**，故总数 169 而非各结论行的简单相加。

分布：**P0 16（9.5%）· P1 72（42.6%）· P2 81（47.9%）**。P0 高度集中在「并发写覆盖 / 凭证外泄 / 账号串号 / 发布核验」四条主线。

---

## 2. 交叉确证（多席同报 → 合并为确证问题）

判定规则：≥2 个**不同席**独立报出同一根因（4-C 的两文件视为同一席）。共归并出 **12 个确证问题（C-01…C-12）**，覆盖原始 169 条中的 44 条。

### C-01 Web Flow state 可预测 / CSRF 会话固定 【安全 · 席位分歧升级为 P0】
- 1-A **P1-7**：`gh_oauth_webflow_io.dart:46-48`，state=`ogl-<ms>-<port>`，熵不足。
- 2-A **P0-1**：`gh_oauth_webflow_io.dart:29-31`，同根因，明确「攻击者 code 注入→受害者登录攻击者账号」。
- 合并裁定：两席同文件同表达式，确证；**取高严重级 P0**。修复：改 `Random.secure()` ≥128bit，去掉时间戳/端口。

### C-02 并发写覆盖 / TOCTOU 乐观锁基线不可靠 【根因族 · 4 席确证】
| 来源席 | 编号 | 症状 |
|---|---|---|
| 1-A | P0-2 | `RepoFileService.create` 探测后无 sha PUT，并发第二写者静默覆盖首写（`repo_file_service.dart:620-686`） |
| 1-B | P0-1（1B-01） | 冲突重试把「409 sha」与「另一次 read 的 content」拼成一次写入，合并基于 A 版却带 B 版 sha（`disk_cache.dart:769,783,784`） |
| 3-A | 3-A-01 / **3-A-02** | 分片按 `snap.savePath` 落盘与库任务双口径；`resolveUniqueSavePath` 的 `create(exclusive:true)` 后**立即 delete**，占位非锁（`backend_io.dart:126-127`） |
| 3-C | P0-1 | 批量写入不传 `expectedHeadSha` 时**完全无并发保护**，文件头「没给就从分支 ref 解析」的承诺未落地（`repo_file_service.dart:~1010`） |
- 合并裁定：四席同一根因族——**「校验/占位/提交非原子，乐观锁基线未绑定同一快照」**。修复：统一以同一次读的 `(sha,content)` 重定基；`create` 新建需显式 404 确认；批量 `chainSha = expectedHeadSha ?? await _headShaOf(...)`；下载占位保留至写入交接。
- 关联（非同一根因但同属写失效）：1-A P1-9、2-C P1-4（写后/写失败目录缓存不失效）、1-B P1-07（delete 后草稿未清）。

### C-03 令牌/凭证经非主通道外泄 【P0 · 3 席 + 零测试放大】
- 2-C **P0-1**：`gh_client.dart:615-620` 请求行含完整 query 落盘；`gh_api.dart:1938-1943` `rawText` 全开 URL 注入，带 `token` 的 URL 原文入日志。
- 2-B **P1-1**：`range_download_io.dart` 影子 HTTP 通道无 `followRedirects=false`，302 跨主机原样重发 `authorization` 头。
- 1-A **P0-4**：`gh_auth.dart:78-83` 短令牌（9–12 位）首尾各露 4 字符。
- 5-A **A-2（P0）**：上述外泄面与 SecureDiskVault 行为**零测试**（仅 1 行类型断言）。
- 合并裁定：确证；2-C+2-B 为真正同根（凭证绕过主传输守卫），1-A 为同类脱敏面，5-A 为验证缺口。修复：日志 query 键黑名单 + rawText host 白名单；Range 三处请求关重定向并剥离敏感头；`masked` 对 `length<=12` 全掩；补 vault/脱敏契约测试。

### C-04 跨账号数据串 / 账号切换非全局失效边界 【P0 · 4 席确证】
| 来源席 | 编号 | 症状 |
|---|---|---|
| 2-A | P1-2 | 登录中断残留 `pending-` 账号 + 临时令牌，重启后假登录（`login_page.dart:_finishLogin`） |
| 3-B | P1-2 | `ix_session.dart:79-80,288-305` context 单键不绑 accountId，跨账号恢复私有仓库名 |
| 4-A | **P0-1** | `client_shell.dart:282-291,232-237` 认证门切换不清 Navigator 栈，`_visited` 与页面 State 跨账号复用 |
| 4-C-2 | #8/#9 | `login_page.dart:264-283` 晚段失败留 `user-<id>` 半成品账号；页面关闭丢弃已取得 OAuth 令牌 |
- 合并裁定：确证（4 席）。根因：**账号身份变化未作为全局失效边界**。修复：账号切换统一 popUntil 首路由 + 清 `_visited`/页 key；context 序列化带 accountId 并 restore 校验；启动清孤儿 pending；回滚同时删 `user-<id>`。

### C-05 限流资源桶 / `lastRateLimit` 双口径误报 【2 席确证】
- 1-A **P0-3**（`gh_api.dart:75-82`）+ 1-A P1-3：解析失败回退 `lastRateLimit`，桶键混用响应头 resource 与路径推导 resource。
- 2-C **P1-2**（`gh_client.dart:541-544,633`）：`_lastRateLimit` 单槽展示 search 余量冒充 core。
- 合并裁定：确证（1-A + 2-C）。修复：回填用请求侧 `resourceOfPath`；展示改 `_rateLimits['core']`；解析失败返回 null 而非回退。

### C-06 `GhReadCache._key` 未覆盖全部分区维度 【P0/P1 · 2 席确证】
- 1-B **P1-04**：键不含 `baseUrl`，切企业版/代理后命中旧环境数据。
- 2-C **P0-2**：键不含 `Accept`，JSON/raw 双通道互相污染。
- 合并裁定：确证（1-B + 2-C）。修复：`_key` 注入 baseUrl 与 accept 维度；baseUrl 变更触发 `clear()`。

### C-07 写后 / 失败 / 删除的缓存失效不完整 【P1 · 3 席确证】
- 1-A **P1-9**：批量 Git Data 提交绕过 `dir:` 哨兵失效，60s 内显示旧目录名。
- 2-C **P1-4**：`gh_client.dart:664-669` 仅写成功才 clear，409/422 冲突窗口列表陈旧。
- 1-B **P1-07**：`delete` 成功未清草稿、失败未失效本地条目，旧内容可复活。
- 合并裁定：确证（3 席）。修复：失效条件放宽到「非 GET 且非 429/5xx」；暴露仓库级失效清 `dir:` 前缀；delete 成功/失败均 `_evictEncoded` 并 discard 草稿。

### C-08 引导注入校验只覆盖 1/9 构建腿（门禁覆盖失明）【P0 · 2 席确证】
- 1-C **P0-1**：`build.yml:608-613` 带 `if: matrix.label == 'Android · arm64-v8a'`，且信任根 fixture 用占位 `coreDigest="fixture-digest"`。
- 5-C **P2-4**：同文件同行号，明确标注「与 1-C 席同报，确证」。
- 合并裁定：确证（2 席）。修复：去掉腿限制，逐腿验签；fixture 用真构建参数重签。

### C-09 OAuth / 令牌 / 保险库零行为测试 【P0 · 系统级，2 席确证】
- 5-A **A-1/A-2（均 P0）**：Device Flow 轮询、state/CSRF、Web Flow、SecureDiskVault、401→markExpired 全链路零测试；`gh_oauth_flow_test.dart` 仅 3 例纸面契约。
- 2-A P0-1 / P1-2：正是这些零测试路径里的现役 P0/P1。
- 合并裁定：确证（5-A + 2-A）。**与「CI 全绿」一起构成系统级结论，见 §5。**

### C-10 分页不可靠 / 截断不可见 【P1 · 3 席确证】
- 1-A **P1-4**：`paginate` maxPages=10 上限仅记 diagnostics，流消费方看不到截断。
- 2-C **P1-5**：`paginate` 忽略 `response.page.next`，靠 page++ 近似，Link 回填成死代码。
- 4-C-2 **#4**：`gists_page` 只取第一页 30 条，无 LoadMore。
- 合并裁定：确证（3 席，表现层各异、根因同为「分页协议未端到端消费」）。

### C-11 SAF / 导出覆盖与验证缺口 【P1 · 3 席确证】
- 3-C **P1-2**：`og_l_storage_saf_io.dart` `pasteLocalFile(overwrite:true)` 恒覆盖用户手工编辑的同名文件。
- 1-B **P2-10**：`existsSync()` 在 async 路径吞异常致导出静默放弃。
- 5-A **A-6**：SAF 零测试。
- 合并裁定：确证（3 席）。修复：overwrite 默认 false + 改名/提示；异步 exists；补 SAF 假件契约测试。

### C-12 异步生命周期 / 取消不统一 【P1 · 3 席确证】
- 2-C **P1-6**：`GhRequest` 无 generation/cancelToken，commitFiles 四连请求离页后仍烧额度/半程提交。
- 3-A **3-A-03 / P2-7**：终态事件无回合守卫可复活已完成快照；`dispose` 后仍 await 触碰注入对象。
- 4-A **P1-6**：PopScope `canPop` 不订阅路由栈，预测性返回动画与结果撕裂。
- 合并裁定：确证（3 席）。修复：GhRequest 加 isCancelled + 各 await 后查；终态吸收态 + 统一回合制；RouteObserver 刷新 canPop。

### 其它仅单席报告、未达确证门槛的高价值项（保留在 P0 表）
1-C P1-2（Mod 告警从不接线）、4-A P0-2（后台 critical 通知被消费）、4-B 4B-01（设置全量丢失）、5-C P0-1/P0-2（发布核验/幂等）、2-B P1-2（Retry-After 截断烧额度）等。

---

## 3. 全部 P0 清单（16 条，按严重度排序）

> 排序依据：影响面 × 严重度 × 可逆性（不可恢复/系统级优先）。「来源席」列含交叉确证组号。

| # | 编号 | 一句话症状 | 根因文件:行 | 修复指令 | 来源席 |
|---:|---|---|---|---|---|
| 1 | **5-C P0-1** | Release Verify 与真实产物全面失配，四平台 job 100% 失败、核验长期空转 | `release-verify.yml:103,130,159,259,377-378` | 重写 pattern 为 `OGL-*.zip`；解压取内嵌 APK/AAB 验签；删 Apple/best-effort 分支；加产物总数总闸 | 5-C（单席） |
| 2 | **5-C P0-2** | 重复 dispatch 静默覆盖已发布 Release，历史记录不可信（不可逆） | `build.yml:744,802-811` | tag 创建前 `gh api .../git/ref/tags/<tag>` 硬守卫，存在即 exit 1（除显式 allow_overwrite）；`fail_on_unmatched_files:true` | 5-C（单席） |
| 3 | **1-A P0-2** | `create` 无 sha PUT + 探测写 TOCTOU，并发第二写者静默覆盖首写 | `repo_file_service.dart:620-686`；`gh_api.dart:872-885` | 探测 missing 后重读确认 404；`putContent` 增 `createNew:true` 显式语义；改 :616 注释 | C-02（1-A/1-B/3-A/3-C） |
| 4 | **1-B P0-1** | 冲突重试拿 A 版 sha 拼 B 版内容，乐观锁通过但覆盖他人修改/内容损坏 | `disk_cache.dart:769,783,784`；`disk_types.dart:195` | 只接受同一次 read 的 (sha,content)；`fresh==null` 时禁止重定基直接返回 staleSha；补两类回归测试 | C-02 |
| 5 | **3-C P0-1** | 批量写入不传 `expectedHeadSha` 时无并发保护，tree upsert/delete 静默顶掉并发提交 | `repo_file_service.dart:~1010`（`_executeOps`） | `chainSha = expectedHeadSha ?? await _headShaOf(...)`，空则抛 conflict 拒绝写入 | C-02 |
| 6 | **2-C P0-1** | 请求行完整 query 落盘 + `rawText` 全开 URL，令牌可原文写进 sdcard 日志 | `gh_client.dart:615-620`；`gh_api.dart:1938-1943` | 日志 query 键黑名单打码；`rawText` host 白名单（api.github.com/raw/gist）；均在 send/rawText 内实现 | C-03（2-C/2-B/1-A/5-A） |
| 7 | **2-A P0-1** | Web Flow state=时间戳+端口可预测，伪造回调注入攻击者 code → 会话固定/登录到攻击者账号 | `gh_oauth_webflow_io.dart:29-31`（亦 :46-48） | `Random.secure()` ≥128bit base64Url；不编入时间戳/端口 | C-01（1-A/2-A，**分歧升级**） |
| 8 | **1-C P0-1** | 信任根用占位 `coreDigest` 假锁定，1/9 腿验签，被污染清单仍可出包 | `build.yml:608-613`；`test/kernel/fixtures/release_key_signed_manifest.json`；`tool/boot_manifest.py:74-90` | 去腿限制逐腿验签；真参数重签 fixture；加「构建合约」测试比对 Python/Dart canonical 字节 | C-08（1-C/5-C） |
| 9 | **4-A P0-1** | 认证门切换不清导航栈/`_visited`，登出切号后旧账号页面 State 被新账号复用 | `client_shell.dart:282-291,232-237` | `_accountId` 变更时清 `_visited`+换页 key，入登录门前 `popUntil(isFirst)`；登录回调显式清 guest/栈 | C-04（2-A/3-B/4-A/4-C） |
| 10 | **4-B P0-1** | `tagsPerPage` 的 `contains(double)+as int` 抛异常，坏配置使**每次启动全量设置丢失** | `settings.dart:250-251` | 加 `_asChoiceInt` 统一 int/有限 num/越界；补 `fromJson({'tagsPerPage':30.0})` 不抛断言 | 4-B（单席，已本地 dart 复现） |
| 11 | **2-C P0-2** | 缓存键不含 `Accept`，JSON/raw 跨端点污染（潜在错编码 body） | `gh_client.dart:507`；`gh_read_cache.dart:63-69` | `_key` 加 accept 维度，或删 readme 的 60s TTL 白名单 | C-06（1-B/2-C） |
| 12 | **1-A P0-3** | `/rate_limit` 解析失败回退单槽 `lastRateLimit`，search 余量冒充 core，误判额度充足 | `gh_api.dart:75-82`；`gh_client.dart:628-631` | 无法解析 core 时返回 null/抛；暴露 `rateLimitOf('core')` | C-05（1-A/2-C） |
| 13 | **4-A P0-2** | 后台态 critical 通知被 `_drain` 直接消费，回前台后应用内弹窗永不出现 | `error_surface.dart:460-478,494-510` | 后台 critical 投系统通知后 `requeueFront(notice)` 而非消费；加 `presentedInApp` 标记 | 4-A（单席） |
| 14 | **1-A P0-4** | 短令牌（9–12 位）首尾各露 4 字符，脱敏面过大 | `gh_auth.dart:78-83` | `length<=12 ? '****' : 前4+****+后4`；`looksValid` 失败不阻断保存 | C-03 |
| 15 | **5-A A-1** | 认证失效端到端零测试：Device Flow/CSRF/vault/401→markExpired 全无行为断言 | `test/domain/gh_oauth_flow_test.dart:1-35` | 新增 `gh_oauth_e2e_test.dart` 脚本化假件驱动全轮询 + vault 回读 + 401 联动 | C-09（5-A/2-A） |
| 16 | **5-A A-2** | 令牌外泄/保险库行为零测试，外泄面无回归防线 | `test/base/base_bootstrap_test.dart:30`（唯一 isA 断言） | 补 vault 契约测试 + 日志/诊断 token mask 断言；chaos 纳入带 token 响应体 | C-03/C-09 |

**P0 归属**：数据层 5、认证网络 5、展示层 3、工程发布 3（5-A×2 + 5-C×2 中后两者归工程；上表已按席标注）。确证组涵盖 #3–#9、#11、#12、#14–#16。

---

## 4. 按域索引 + 热点文件回链

### 4.1 五域确证问题索引

| 域 | 确证问题编号（本域相关） | 域内主要单席 P0/P1 |
|---|---|---|
| **数据层**（1-A/1-B/1-C） | C-01, C-02, C-03, C-05, C-06, C-07, C-08 | 1-A P0-3/4；1-B 1B-01/02/05；1-C P0-1/P1-1（Mod 告警未接线） |
| **认证网络**（2-A/2-B/2-C） | C-01, C-03, C-04, C-05, C-06, C-07, C-09, C-12 | 2-B P1-2（Retry-After 截断）、P1-3（Range 无超时）；2-C P1-3（信号量泄漏）、P1-6（无取消） |
| **任务下载**（3-A/3-B/3-C） | C-02, C-04, C-11, C-12 | 3-A 3-A-04（resume 从头重下）、3-A-06（无 digest 跳过 size 校验）；3-B P1-1（不再提示失效） |
| **展示逻辑**（4-A/4-B/4-C） | C-04, C-09, C-10, C-11, C-12 | 4-A P0-2/P1-3（桌面关闭无拦截）；4-B 4B-01/02/05；4-C-1 P1-2（Issue 空白）、P1-4（标签刷新被吞）；4-C-2 #1/#2（jobs 未加载/查找跳错） |
| **工程发布**（5-A/5-B缺/5-C） | C-08, C-09, C-10, C-11 | 5-C P0-1/P0-2/P1-1（无产物硬校验）/P1-2（channel 不一致）/P1-3（Gradle 缓存饥饿）；5-A A-3（21 页零测试） |

### 4.2 热点文件回链（theme.dart 之外的跨席高频问题文件）

| 热点文件 | 回链问题（席:编号） | 涉及确证组 |
|---|---|---|
| `lib/domain/gh/gh_client.dart` | 1-A P1-3/4/P2-3；2-C **P0-1**/P0-2/P1-1…7 | C-03, C-05, C-06, C-07, C-12 |
| `lib/domain/gh/gh_api.dart` | 1-A **P0-3**/P1-1/2/5/9/P2-4/6/7；2-C P0-1/P1-6；4-C-2 #4（gists 分页） | C-03, C-05, C-10 |
| `lib/domain/gh/repo_file_service.dart` | 1-A **P0-2**/P1-9；3-C **P0-1**/P1-1/3/P2-2/3/6 | **C-02** |
| `lib/base/net/range_download_io.dart` | 2-B **P1-1**/P1-3；3-A-04/05（引擎侧） | C-03 |
| `lib/domain/ix/ix_download.dart` + `backend_io.dart` | 3-A-01…07；5-A A-5（resume 零测试） | C-02, C-12 |
| `lib/domain/gh/gh_oauth_webflow_io.dart` | 2-A **P0-1**；1-A P1-7 | **C-01** |
| `lib/domain/gh/gh_read_cache.dart` | 1-B P1-04/P2-06；2-C **P0-2** | **C-06** |
| `lib/base/disk/disk_cache.dart` | 1-B **1B-01**/02/03/07 | **C-02**, C-07 |
| `lib/surface/app/client_shell.dart` | 4-A **P0-1**/P1-2/5/6 | **C-04**, C-12 |
| `lib/surface/settings.dart` | 4-B **4B-01**/02/03/04/05/06/09；4-A P2-6（theme seed 不同源） | — |
| `lib/domain/ix/ix_session.dart` | 3-B P1-2 | **C-04** |
| `.github/workflows/build.yml` | 1-C **P0-1**/P1-1；5-C **P0-2**/P1-1/2/3/P2-4 | C-08 |
| `.github/workflows/release-verify.yml` | 5-C **P0-1** | — |
| `tool/gate_of_gates.py` / `sort_imports.py` | 5-B 缺报告；本代理实跑验证（§0）：CWD 空扫/反向注入已在位，`--fatal` 因 contract_audit 文档引用报 1（本报告消解） | C-08/C-09（系统级） |

> 说明：`lib/surface/theme.dart` 被 4-A P2-6、4-B P2-7/4B-03 引用（splash seed 不同源、seedColorId 白名单、i18n `_t('ok')` 取错分片），按任务要求不列入热点回链表但在域索引中已覆盖。

---

## 5. 系统级结论：CI 全绿 ≠ 质量达标

**必须单列**。证据链：

1. **5-A**：OAuth 全链路 + 令牌保险库零行为测试（A-1/A-2 为 P0），21/30 页面与整个外壳状态机零 widget 测试（A-3/A-4）；CI 虽无 `continue-on-error`/skip 掩盖，但**测不到的路径永远绿**。
2. **5-C**：`release-verify.yml` 与发布形态全面脱节、四平台 100% 失败却长期无人察觉（P0-1）——门禁自身失修而 CI 照常推进。
3. **1-C + 5-C**：引导注入校验只在 1/9 构建腿跑（C-08），其余 8 腿带污染清单仍出包。
4. **4-B**：`tagsPerPage: 30.0` 击穿「fromJson 永不抛」纪律，而该测试组存在却漏此输入（4B-01）；`i18n_scan.py --check` 全绿但 `_t('ok')` 缺键一路漏到运行时（4B-07）——**测试/门禁只校验了它知道的形状**。
5. **5-B 缺席**：34 个 tool/ 门禁脚本判据的本轮专项审计未产出（§0），意味着「门禁本身是否纸面白名单」这一层本轮无人背书。

**结论**：现存 CI 的绿色只能证明「已登记的断言通过」，不能证明功能正确。P0 表里 #1/#2/#7/#10/#15/#16 全部是在 CI 全绿背景下存活的缺陷。改进方向：把「零测试路径」本身作为门禁对象（覆盖率/关键路径清单），并把 release-verify、注入校验、文档契约引用纳入必红闸门。

---

## 6. 如果只修 5 件事（按影响面 × 严重度）

| 优先级 | 事项 | 覆盖的确证组 / P0 | 理由（影响面×严重度） |
|---:|---|---|---|
| **1** | **统一并发写入的乐观锁基线**：create 新建确认、冲突重定基同快照、批量必带 headSha、下载占位锁 | C-02（1-A P0-2 / 1-B P0-1 / 3-C P0-1 / 3-A-02/01） | 唯一会造成**远端数据静默丢失且不可逆**的根因族，4 席独立确证，改动集中在 3 处函数（`_executeOps` chainSha、`disk_cache` 重试分支、`create` 探测） |
| **2** | **收口凭证出口**：Web Flow state 随机化 + 日志 query 打码/rawText host 白名单 + Range 关重定向 + 令牌脱敏 | C-01 + C-03（2-A P0-1、2-C P0-1、1-A P0-4、2-B P1-1） | 安全面最高，3 席确证；全部为局部改动，修复后立即消除「登录到攻击者账号」与「令牌落盘/跨主机」两类严重后果 |
| **3** | **发布链可信化**：release-verify 按当前产物形态重写 + 产物数总闸 + dispatch tag 幂等守卫 + channel/prerelease 统一 | 5-C P0-1/P0-2/P1-1/P1-2 + C-08 | 不可逆（静默覆盖历史 Release）+ 长期空转核验；直接决定用户下载到的产物是否可信 |
| **4** | **把账号切换做成全局失效边界**：清 Navigator 栈与 `_visited`、context 绑 accountId、启动清 pending/半成品账号 | C-04（4-A P0-1、2-A P1-2、3-B P1-2、4-C-2 #8/#9） | 4 席确证的隐私/数据串问题，一次修复同时解决假登录、跨账号仓库名泄露、旧账号页面复用 |
| **5** | **配置与测试地基**：修 settings `tagsPerPage` 反序列化 + 写盘串行化/回滚，补 OAuth/vault 行为测试与门禁自体检 | 4-B 4B-01/05 + C-09（5-A A-1/A-2）+ §5 系统级 | 用户可感知面最大（每次启动全量设置丢失），且补测试是防止前四项回归的唯一手段；与生成总报告后 contract_audit 红灯消解同批完成 |

> 未进前五但需尽快跟进：1-C P1-2（Mod 强制告警从不接线，安全策略形同虚设）、2-B P1-2（Retry-After 截断烧限流额度）、4-A P1-3（桌面关闭无脏草稿/下载确认）、3-A-04/06（resume 从头重下、无 digest 时截断文件判完成）、4-C-1 P1-2（Issue 详情空白/状态误判）。

---

## 7. 收尾状态

- **本轮性质**：只读交叉审计。已逐份完整读取 15 份报告；未修改任何 `lib/`、`.github/`、`tool/` 代码；未 commit / 未 push。唯一新建产物为 `docs/FUNC_AUDIT_REPORT.md`（本文件）。
- **契约红灯处置**：`docs/FUNC_AUDIT_BRIEF.md` 引用本文件，生成前 `tool/contract_audit.py --fatal` 报「文档契约引用：1 处（契约文档不存在）」。本文件生成后立即复跑确认归零（见交付记录）。
- **待主会话/CI 裁决项**（各席均按纪律未越权）：1-A 的 REST 字段语义（watchers/filter/annotated tag/webflow 文件名编码）、3-A 的 `background_downloader` 内部并发上限与 Web 条件导入、4-C-1 的 `issue()` domain 端点是否存在、4-C-2 的 url_launcher 返回 false 语义、5-A 的 ci.yml 下 boot_define_injection 行为。
- **5-B 缺口**：建议主会话补派 5-B「tool/ 门禁判据有效性」专项审计（本代理已以源码实跑代替性地核实了三条线索，均已修复，但不能替代一席完整覆盖 34 个脚本的结论）。

**本总报告结论**：169 条原始问题（P0 16 / P1 72 / P2 81），归并出 12 个跨席确证问题；最高风险集中在「并发写覆盖 / 凭证外泄 / 账号串号 / 发布核验失修」四族，且全部能在 CI 全绿背景下存活。本轮只审计，修复未执行。
