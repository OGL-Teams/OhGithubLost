# 待收敛条 · 现状总表（2026-11-13 实测）

> 本表是**权威现状**：历史审计报告（`audit_b*_*.md`、`postrelease_*.md`）
> 都是「当时快照」，其结论已被后续批次部分修复或校准。一切以本表
> 的实测结果为准；新增待收敛项须同步登记到这里。
> 实测方法：源码标记核对 + 十一道门禁 + CI（`flutter analyze`/`test`）。

## 一、分层 / 桥接制度

| 条 | 现状 | 说明 |
|---|---|---|
| `layer_audit.KNOWN` 2 项 | ⚠️ **仍未收敛** | `gh_api.dart → base/disk/disk_cache.dart`、`gh_client.dart → base/net/net_bridge.dart` 实测仍在。正解：在 `kernel/contract/` 定义 `ConsistencyCache`/`NetClient` 抽象，实现类下移。属独立批次，AGENTS.md 已如实登记 |
| `layer_audit.ALLOW` 3 项 | ✅ 合法例外 | 两个装配根 + `surface/types.dart` 类型门面，制度要求 |
| `contract_audit.HEADER_EXEMPT` 4 项 | ✅ 合法例外 | 转发导出/契约文件，已有说明 |
| A-06 platform 文件头 | ⚠️ 规范决策未定 | `platform/` 6 文件用「平台实现层」中文前缀（无 L 编号）；`layer_of` 返回 None 不检查。要不要定 P 前缀属规范决策 |
| A-11 platform 统计口径 | ✅ 已如实说明 | 154 = 四层文件数，161 = 全 lib；`docs/5layer-audit-todo.md` 已写明两者都对 |

## 二、门禁自身（批 8 / 批 9 遗留）

| 条 | 现状 | 说明 |
|---|---|---|
| B8-C-01 contract_audit 死描述 | ✅ 已修 | docstring 第 5 项改为「全部四层文件头」，与实现一致 |
| B8-C-02 CWD 假绿 | ✅ 已修 | `layer_audit`/`i18n_scan` 用 `__file__` 定根 + 空扫即失败；`gate_of_gates` 临时 CWD + 反向注入 |
| B8-A-01 i18n 32 个 dict 值 | ✅ 已修 | 按语言取回字符串 + 值类型校验 |
| B8-A-02 只比 key 不比值 | ✅ 已修 | 同上 |
| B8-A-03 i18n 运行时接线 | ✅ 已评估可用 | 未改，现有实现可用 |
| B8-A-04 `t()` 插值控制字符 | ✅ 已修 | `og_l_i18n.dart` 过滤控制字符 |
| C-04 / C-17 / C-18 文档快照 | ✅ 已修 | 5layer-todo 现行快照、check_content 平台名白名单、test/README 覆盖表 |
| C-12 sort_imports `--fatal` | ✅ 已补 | 退出码语义 + export 独立段 + 注释跟随（曾两次被 `git add -A` 覆盖丢失，现由 CI 守卫） |
| C-13 终审计数 bash | ✅ 已修 | `grep -c` 失败不产生 `"0 0"` |
| 门禁白名单宽度 | ⚠️ 持续抽查 | layer ALLOW 3 / header 4 / platform 5 / motion 2 / perf 6；均有注释理由，未见放宽 |

## 三、UI 动效与细节（批 9 B 系列）

| 条 | 现状 | 说明 |
|---|---|---|
| B1 AsyncSliver 四态过渡 | ✅ 已修 | 三态走 `OgLSurfaceSwitch + ValueKey(state)`，data 保持 `SliverList.builder` 懒加载 |
| B2 TabBarView 降档 | ✅ 已修（折中） | 框架自带滑动动画无公开 duration；改为档位 0 禁拖拽但仍可点 tab，不砍功能 |
| B5 RefreshIndicator 统一 | ✅ 已修 | `OgLRefreshIndicator` 单一入口替换 10 处 |
| B10/B11/B12 门禁规则 | ✅ 已修 | 逐类别豁免、`seconds:` 纳入、AnimatedXxx 拦截、CURVES_ALLOWED 收敛 |
| B14 回归锁接线 | ✅ 已修 | 页面接线 + 源码断言（含重名/跳转/打磨契约） |
| B15/16/18/19/21/22 | ✅ 已修 | 驻留时长显式登记、41 处图标令牌、InkWell 圆角、6 处裸 AppBar、大字体两行、Semantics |
| **B3/B4/B7/B8/B13/B20/B23** | ⚠️ **仍未收敛** | SnackBar/Dialog/错误面板/下载速率的逐帧节奏、`Opacity(0.7+0.3t)`、mono 字号裸值、`AnimatedSize` 冗余三元。需真机采集后定档，不宜凭静态审查硬塞数值 |
| **B6** | ⚠️ **仍未收敛** | 设置分区/legal/onboarding/file_preview 四页入场动画；上次 UI 代理正是在这几页改坏，列为专项 |
| **B9** | ⚠️ 需真机 | 「档位 0 所有交互逐项核对」静态不可确证 |
| **B17** | ✅ 已修（12.6.3） | 推荐分类 `SegmentedButton` → 与 Issues 统一的 `OgLIssuesFilterChips` 横滑行；语言档硬编码英文 → 六语言 i18n |
| B19 余 15 处裸 AppBar | ✅ 有意保留 | 带 actions/bottom/自定义 leading；`OgLAppBar.title` 是 String，强替丢结构 |

## 四、发布后复查：下载（C/S 系列）

> 报告按 `b2ff56f`（12.6.1 时期）复核；12.6.2 又修了 C-02/C-06。

| 条 | 现状 | 说明 |
|---|---|---|
| C-01 重名落盘不一致 P0 | ✅ 已修（12.6.1） | `finalPath/finalSpec`，快照/单连接/分片三处一致 |
| C-02 重试退回原名覆盖 P0 | ✅ 已修（12.6.2） | `_retrySavePaths` 由 Set 改 Map，记住上一轮裁决路径 |
| C-06 resume 抢跑分片 P1 | ✅ 已修（12.6.2） | `wasRanged` 守卫 |
| **C-03 探测异常 fail-open** | ⚠️ **仍存在** | `resolveUniqueSavePath` 的 `catch` 与 999 个占用时 `return base` = 返回已存在路径。应失败闭合或 `writeExclusive` 占位 |
| **C-04 TOCTOU 无原子占位** | ⚠️ **仍存在** | 并发两任务可拿到同一个 `a (1).zip` |
| **C-05 撤销移除遗留豁免** | ⚠️ **仍存在** | `_lastRemoved` 恢复路径不消费 `_retrySavePaths` |
| **C-07 await 窗口 remove** | ⚠️ **仍存在** | 第二个 await 后 `_specs[id]!` 可能空指针 / 已删任务复活 |
| **C-08 fallback 异步重入** | ⚠️ **仍存在** | `_fallbackToSingle` 旧回合可覆盖新回合 savePath |
| **C-09 暂停速率负/进度回跳** | ⚠️ **仍存在** | 采样窗口未重置 |
| **C-10 total=0 谎称浏览器** | ⚠️ **仍存在** | 原生端也会显示该文案 |
| **C-11 Tween begin:0 重跑** | ⚠️ **仍存在** | 每次 build 从 0 重新插值，进度不连续 |
| C-12 超量字节裁剪 100% | ⚠️ 仍存在 | 掩盖数据错误 |
| C-13 单连接失败离页不可见 | ⚠️ 仍存在 | 不投递通知中心 |
| C-14 完整性失败文案误导 | ⚠️ 仍存在 | 无条件宣称「坏文件已删除」 |
| **C-15 retry 入队无兜底** | ⚠️ **仍存在** | `await _backend.enqueue(spec)` 异常会永久挂 queued |
| C-16 clearFinished 不清辅助表 | ⚠️ 仍存在 | `_roundOf` / `_retrySavePaths` 跨任务误消费 |
| C-17 Gist 无统一通知 | ⚠️ 仍存在 | 「查看下载」动作缺席 |
| C-18 降级依赖旧页 context | ⚠️ 仍存在 | 第三级降级仍用发起页 context |
| S-01 Web 分支契约漂移 | ⚠️ 推测 | 需 Web 分支实编验证 |
| S-02 库同名覆盖行为未知 | ⚠️ 推测 | 需真机放同名文件实测 |
| S-03 取消后 .partN 撞车 | ⚠️ 推测 | 回合间文件名冲突 |
| S-04 expectedSha256 只 Release | ⚠️ 仍存在 | 其它下载类型无校验 |

## 五、发布后复查：DNS / 网络（F 系列）

| 条 | 现状 | 说明 |
|---|---|---|
| F-01 结果 IP 无白名单 P0→P1 | ✅ 已修（12.6.1） | `ogLIsBlockedLiteralIp` 与重定向守卫共用；全被拦抛 `SocketException`。代理「完全不设防」属夸大：源 IP+事务 ID+rcode 早有校验 |
| F-08 presign 失败 PAT 外泄 | ✅ 校准为夸大 | `prefixes=[]` 时只剩直连 + TOKEN-EXIT-01 警告；库内部 302 仍是已知暴露面 |
| **F-02 DoH 仅 A 记录** | ⚠️ **仍存在** | 无 AAAA/CNAME/DNS64/TTL |
| **F-03 owner 校验可绕过** | ⚠️ **仍存在** | 「省略 name」可绕过 |
| **F-04 两级回退不可见** | ⚠️ **仍存在** | `lastResolvedVia` 无生产 UI 消费点，违反「绝不静默降级」 |
| **F-05 自检未覆盖三路** | ⚠️ **仍存在** | DNS/直连/镜像 + 结果未接页面 |
| **F-06 DoH 端点校验/跨主机重定向** | ⚠️ **仍存在** | 自定义端点校验不完整 |
| F-07 清空 DNS IP 旧解析器生效 | ⚠️ 仍存在 | 配置变更窗口 |
| F-09 加速候选绕过 URL 校验 | ⚠️ 仍存在 | 字符串前缀白名单 |
| F-10 Retry-After 无 jitter/asctime | ⚠️ 仍存在 | P2 |
| F-11 DNS 缓存不按 TTL/无 in-flight | ⚠️ 仍存在 | P2 |
| F-12 私有仓库图片必然 404 | ⚠️ 仍存在 | P2 |
| F-13 自定义 DNS IP 未校验 | ⚠️ 仍存在 | P2 |
| 批 1 的 8 组 P0/P1 | ✅ 全部仍成立 | 逐条代码核对无回归 |

## 六、供应链 / 发布纪律

| 条 | 现状 | 说明 |
|---|---|---|
| B8-B-01 签名覆盖不全 | ⚠️ **仍未收敛** | `coreDigest` 未覆盖 platform/main.dart，需发布信任链专项 |
| B8-B-06 Action 未钉 SHA | ⚠️ **仍未收敛** | 涉及全部 workflow 版本升级 + CI 实跑 |
| B8-B-07 Android 签名密码 | ⚠️ **仍未收敛** | 涉及 android/ 构建配置与 Secrets |
| DBG-04 presign 回退经库泄 PAT | ⚠️ 已知限制 | 已在 release_notes 登记 |
| docs/ 历史报告 17 处死链 | ✅ 有意保留 | 原始记录不追溯改写，由 `AUDIT_INDEX.md` 索引 |
| 推代理 402 / 直连超时 | ✅ 有备用通道 | 发布流程已多次实测自动/手动切换 |

## 七、收敛优先级建议（若继续推进）

1. **数据无价类**：C-03（fail-open）、C-04（原子占位）、C-07/C-08（异步重入）——仍是覆盖用户文件的真实窗口
2. **功能可用性**：C-15（retry 挂 queued）、C-05（撤销移除死路）、C-09（进度回跳）
3. **安全可见性**：F-04（回退不可见）、F-02/F-03（DoH 协议）、F-06（端点校验）
4. **供应链**：B8-B-01/06/07 需独立发布专项
5. **真机节奏**：B3/B6/B9 系列需采集后定档，不宜静态硬塞

> 纪律：本表只登记**实测**结论。任何"修完某条"须同时给出修复提交 +
> 回归锁 + CI 裁决结果；代理报告里的 P0 一律经主会话亲自复读后才计入。
