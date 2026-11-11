# 批 9 第二轮 · 分层桥接 / 门禁体系 / 规范文本修复记录

> 基线 `5acb015`。A/C 组代理并行修复后超时，报告未落盘；主会话按它的
> 回传内容核对工作区、补齐 3 个待办，并登记未修项。

## 已修（代理完成 + 主会话复核）

| 条目 | 修法 |
|---|---|
| A-05 | `layer_audit.py` 的 KNOWN 改为**规范化目标路径后**比对，不再按 import 原文字面匹配（防路径改写套用白名单） |
| A-06 | kernel 23 个文件 L0 头已由批 9 第一轮补齐；`contract_audit.check_headers` 不再跳过 kernel，实跑 0 违规 |
| A-07 | `docs/ARCHITECTURE.md` §6.2 重写为现状如实记载（platform/ 条件 import 实际为零、无 `*_web.dart`），不凭空造实现 |
| A-08 | `AGENTS.md` 补组合根例外说明（main.dart 直用 `defaultTargetPlatform` 已登记 PLATFORM_ALLOW） |
| A-09 | `lib/surface/types.dart` 的 `export 'gh_oauth.dart'` 改为显式 `show` 白名单 3 符号，堵住「hide 黑名单」把实现透给页面 |
| A-10 | 文档漂移批量修正：BOOT→COLD_START、NAMING→ARCHITECTURE、DURABILITY→CONSISTENCY 引用；删「未落地」过期括注；domain 注释 D1–D10 → D1–D9；main.dart 的 assets 叙述改为如实表述 |
| A-11 | `layer_audit.py` 加「platform 只许依赖 kernel」单边规则；总文件数口径 154（四层）与 161（全 lib）在 `docs/5layer-audit-todo.md` 里如实说明，不再互相「修正」 |
| A-12 | 命名约定中「服务 *service/*manager/*api」属纸面规则，AGENTS.md 不再宣称脚本可识别 |
| A-13 | `contract_audit.py` 新增第 5 节「装配顺序 L0→L3」静态检查（FACTORY_LAYER 映射 + 单调性），注入反例实测可检出 |
| B10 | `motion_audit.py` 的 `ALLOW_LINE_HINTS` 改为**按规则类别 × 提示词逐项匹配**，取消整行子串豁免 |
| B11 | `Duration(seconds/minutes/hours/days:)` 纳入硬编码时长检查；`AnimatedXxx` 家族纳入（duration 走 OgLAnim / Duration.zero 即合规） |
| B12 | `ui_audit.py` 的 `CURVES_ALLOWED` 从 10 收敛到 6，与 `motion.dart` 档位表一致 |
| C-04 | `docs/5layer-audit-todo.md` 重写为「v8.2.0 历史占位 + 现行快照对照」 |
| C-05 | `AGENTS.md` perf 白名单口径按 `perf_audit.py` 实际（ALLOW 6 + REVIEWED_BOUNDED 7）更新 |
| C-06 | `CONSISTENCY.md` 的 D3 事件码占位符改为源码实际的 `OGL-CONS-203/204` |
| C-07 | `i18n_scan.py` 真正实现 `--allowlist`（此前 docstring 虚构接口） |
| C-08 | `layer_audit.py` 层名统一为 kernel/base/domain/surface + L0–L3 |
| C-09 | `CONSISTENCY.md`「layer_audit 不解析 export」过期表述更新 |
| C-11 | `contract_audit.py` docstring 重写，自述 5 节 = 实现 5 节（原第 5 项「204/206 弱提示」是死描述） |
| C-12 | `sort_imports.py` 补 `--fatal`；`check_content.py` 补 `--check/--fatal` 并接进 ci.yml 严格模式 |
| C-13 | ci.yml 终审计数 `N=$(grep -c ... || echo 0)` 的 bash 缺陷修复（无匹配时不再得到 `"0 0"`） |
| C-17 | `check_content.py` 加 `PROPER_NOUNS` 白名单（macOS/iOS/GitHub… 与文件名 `` `#` `` `` `?` ``），平台名误报归零 |
| C-18 | `test/README.md` 覆盖表按实测 52 文件 / 各目录数更新 |
| 批8 B8-A-03 | i18n 运行时状态/设置接线：**已评估**，现有实现可用，未改（见下） |
| 批8 B8-A-04 | `OgLI18n.t()` 插值先过滤控制字符，堵低危提示注入面 |

## 主会话补齐的 3 个待办

1. `tool/sort_imports.py --fatal`（代理只改了 ci.yml 引用，脚本恒返回 0 → 已补退出码）
2. ci.yml 的 PyYAML 解析 + 终审计数段 bash 实测通过
3. C-04 / C-17 / C-18 三条文档与白名单小修（见上表）

## 未修项及理由

| 条目 | 理由 |
|---|---|
| B8-B-01 签名覆盖不全 | 涉及 `coreDigest` 覆盖面与发布信任链，需专项设计 + 发版验证，非低成本 |
| B8-B-06 Action 钉 SHA | 涉及全部 workflow 版本升级与 CI 实跑；本轮 build.yml 明确禁改（发布流程刚收敛），留专项 |
| B8-B-07 Android 签名密码 | 涉及 android/ 构建配置与 Secrets，超出本轮文件域 |
| A-06 platform 文件头 | platform/ 6 文件用「平台实现层」中文前缀（无 L 编号），contract_audit 的 `layer_of` 对 platform 返回 None 不检查；要不要定 P 前缀属规范决策，未擅自加 |
| A-11 完整形态 | 未把 platform 纳入 154 统计，改为文档如实说明口径差异（154 四层 / 161 全 lib 都对） |
| B10/B12 余项 | `kOglNoticeDwell` 以 `motion-allow:` 显式登记（此前靠 `Cache` 子串整行豁免，现改为有理由的精确豁免），非放宽门禁 |

## 门禁

十道门禁 + `py_compile tool/*.py` + PyYAML 解析全绿；
`gate_of_gates.py --fatal` 在临时 CWD 验证 7 支门禁仍有能力，
且反向注入（空扫 / dict 值）必失败。
