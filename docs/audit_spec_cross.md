# 规范专项审查 · 三视角交叉报告（第 9 批）

> 时间：2026-11-11 · 基线 `33eb271`（v12.5.2）
> 方法：沿用 `docs/AUDIT_PLAN.md` 八批三视角交叉法——
> A 实现正确性 / B UI 动画与细节 / C 规范契约与门禁，**只审不改**，
> 主会话交叉：两方以上命中 = 确证优先；单方 = 亲自复读；
> 静态结论必须经 CI 测试裁决。

## 一、三份报告

| 视角 | 报告 | 发现 | 分布 |
|---|---|---|---|
| A 分层与桥接制度 | `docs/audit_spec_a.md` | 13 | P1×4、P2×8、推测×1 |
| B UI 动画补全 + 细节打磨 | `docs/audit_spec_b.md` | 23 | P1×5、P2×18 |
| C 规范契约与门禁体系 | `docs/audit_spec_c.md` | 17 | **P0×1**、P1×7、P2×9 |

合计 53 条。当前八道门禁全部通过（0 违规）——**这恰恰是问题**：
报告指出的是门禁「覆盖面」而非「已拦下项」。

## 二、交叉确证（两方以上命中 + 主会话亲自复现）

### X-01 [P0·确证] 门禁在错误 CWD 下静默全绿
- 命中：A-02（`--lib lib/surface` → 文件总数 0 / exit 0）、
  C 的 P0（批 8 `B8-C-02` 原样未修）、批 8 C 视角旧报告。
- 主会话复现（`cd /tmp` 后跑）：
  ```
  python3 /root/OhGithubLost/tool/layer_audit.py --fatal
    → 文件总数：0 / 违规：0 处 / exit=0
  python3 /root/OhGithubLost/tool/i18n_scan.py --check
    → 中文字面量 0 处 / [check] 通过 / exit=0
  ```
- 根因：两脚本用相对 `Path('lib')` / `Path('assets/i18n')` 解析，
  而 contract/perf/motion/ui 四支已用 `__file__` 定根不受影响。
- **性质**：违反「失败必须如实可见」——门禁失去能力时不是报错而是报绿。
  这是本次最该先修的一条，且修复成本极低（定根 + `total==0` 即失败）。

### X-02 [P0·确证] i18n 分片里 32 个值是 dict 而非字符串
- 命中：C 的 P0（批 8 `B8-A-01` 未修）、批 8 A 视角旧报告；
  两视角 + 主会话三方确证。
- 主会话复现：`assets/i18n/{zh_Hant,de,fr,ru}/common.json` 的
  `tokenExit*` 8 键 × 4 语言 = **32 个 dict 值**；`zh` 同键全是 `str`。
- 运行时实害：`_loadPage` 用 `'${e.value}'` 把 dict **字符串化**，
  `token_exit_warning.dart:131/136/142/154/162` 的 `i18n.t()` 于是把
  整张 `{de:…, fr:…, ru:…, zh_Hant:…}` 当正文显示——
  **令牌出本机确认对话框（安全文案）在四种语言下全是乱码**。
- `i18n_scan --check` 只比 key 集合，不校验值类型（B8-A-02 亦未修），故 CI 全绿。

### X-03 [P1·确证] export 可绕过分层门禁
- 命中：A-01 + C 的「门禁骨架」条目。主会话复读确证：
  `layer_audit.py:41` 的 `IMPORT_RE` 只匹配 `^\s*import`；
  `contract_audit.py:90` 虽解析 export，但只拦「向上导出」。
- 反例（未改文件）：任意页面写
  `export '../../domain/gh/gh_models.dart' show GhRepo;`
  两支门禁都会放行 → `surface/types.dart`「唯一门面」纪律被击穿。

### X-04 [P1·确证] 层桥注册完整性无守卫
- 命中：A-03 + C 的制度化建议。主会话复读确证：
  `KernelBridgeRegistry` 是 `Map<String,Object>` 裸键，注册点恰 3 处
  （`base_bridge.dart:54` / `domain_bridge.dart:501` / `surface_bridge.dart:650`，
  L0 无桥），`seal()` 不校验键集合；漏注册要到运行期 `resolve` 才炸。

### X-05 [P1·确证] 文件头层级前缀错误 + 门禁盲区
- 命中：A-04 + C 的文档契约条目。主会话复读：
  `kernel/contract/` 下 `disk_store.dart`、`disk_types.dart`、`net_types.dart`
  三个文件头自称 **L1 底座级**（应为 L0）；
  `contract_audit.py` 只查 `lib/base` / `lib/domain`，**跳过 kernel**，
  永远不会发现。

### X-06 [P1·确证] 动效覆盖缺口是「覆盖面」问题
- 命中：B1（OgLAsyncSliver 四态硬切）、B2（TabBarView 硬切）。
- 主会话复读 `async.dart:513-548`：`OgLAsyncSliver` 的 data / empty /
  error / loading **四个分支全是裸 return**，而 `AsyncView` 的三态走
  `OgLSurfaceSwitch`、data 走 `OgLReveal`。同一个 `AsyncController`
  在不同页面表现不一致，与「降档 = 降质量、不砍功能」相悖。
- motion/ui/perf 三门禁均 0 违规——**不是硬编码问题，是没接现成组件**。

### X-07 [P1·确证] v12.5.2 回归锁只测组件、不测接线
- 命中：B14 + C 的正面确认（组件都有行为断言，但接线确属盲区）。
- 主会话复读：`test/surface/ui_regression_test.dart` 三个测试全部
  `new OgLFeedRow / OgLIssuesFilterChips / OgLCodeEditorToolbar`，
  页面若弃用这些组件测试照样绿。另全仓有 18 处与历史病灶同构的
  `crossAxisAlignment: stretch` 无锁保护。

### X-08 [P1·确证] 文档数字静默腐烂
- 命中：A-10（161 vs 159）、C 的 P1、批 8 `B8-C-03`。
- 主会话复现：`README.md` 版本头仍是 **v9.0.0**（当前 12.5.2）；
  实测 161 个 Dart 文件 / 51 个测试，AGENTS.md 写 159/49；
  `docs/README.md` 称「十条原则」而 `QUALITY_STANDARD.md` 实为 59 条。
- `version_sync.py` 只看 `main.dart × pubspec.yaml`，这些入口全在盲区。

## 三、单方命中·亲自复读结论

| 条目 | 复读结论 |
|---|---|
| C：`contract_audit.py` docstring 第 5 项「204/206 回归测试弱提示」 | **确证未实现**（脚本只有 4 项检查），批 8 `B8-C-01` 原样存在。属文档自述 ≠ 实现。 |
| C：批 8 遗留 15 项「未修 12 / 部分修 3 / 已修 0」、`audit_b8_cross.md` 未生成 | 抽查 3 项全部吻合；接受其结论，不逐条复跑。 |
| B3：SnackBar 三处规格分叉 | 主会话见 `showSnackBar` 6 处（`error_surface.dart:572`、`notifier.dart:65`、`download_manager_page.dart:96`）确实分叉，但 `notifier.dart` 是唯一规范入口、另两处是错误/下载专用横幅，**降级 P2**（不是无意义的重复，需评估后再统一）。 |
| B16：41 处裸图标尺寸 | 确证存在，但 `ui_audit.py` 只查间距/圆角令牌、不查图标尺寸；**属令牌体系缺口，P2**，非 UI 事故。 |
| B：motion_audit 白名单漏洞（整行豁免、`seconds: 8` 漏网、`CURVES_ALLOWED` 放行档位表外曲线、AnimatedXxx 不拦） | 静态证据成立，但与 X-01 同类（门禁自身可信度），合并处理。 |
| A-13（推测） | 证据不足，不进入修复队列。 |

## 四、正面确认（制度成立的部分）

- 四层单向依赖在 161 个文件的 import 边里**没有绕层桥的确证违规**；
  3 个合法例外与 2 个 KNOWN 白名单与 AGENTS.md 一致。
- 三座层桥（L1/L2/L3）均 `*bridge.dart` 命名、按 L0→L3 顺序注册。
- v12.5.0/12.5.1/12.5.2 发布四件套（`release_notes/`、
  `changed/_content/`、`releases.json`、`_posts`、线上正文）**已对齐**；
  补正文时主会话已 PATCH 两版线上 Release。
- i18n 三处语言清单一致（6 种）；23 件产物、tag、版本号均正确。
- 八道门禁在**正确 CWD** 下全部通过；CI 严格模式（每步收集、终审统一 fail）有效。

## 五、修复队列（按收益 × 风险排序）

> 纪律：先修「门禁自身可信度」，再修数据缺陷，最后做 UI 补全；
> 每一条都配回归测试，静态结论必须经 CI 裁决。

1. **P0 · gate-of-gates**：`layer_audit.py` / `i18n_scan.py` 用 `__file__` 定根；
   扫描对象数为 0 直接失败；CI 加一步「在临时 CWD 跑所有门禁必须失败」，
   把「门禁有能力」本身钉成可验证契约。
2. **P0 · i18n 值类型**：修 32 个 dict 值（按各语言取回正确译文）；
   `i18n_scan.py --check` 增加「值必须是字符串」，测试同步。
3. **P1 · export 旁路**：`IMPORT_RE` 改 `(?:import|export)`；
   `contract_audit.py` 的向下导出也纳入层级判定。
4. **P1 · 契约自述对齐**：删掉 `contract_audit.py` docstring 第 5 项死描述
   （或真正实现）；补 `kernel/` 文件头层级检查，修 3 个 L1→L0 前缀。
5. **P1 · 桥注册断言**：`seal()` 校验键集合恰为 `{base,domain,surface}` 并加测试。
6. **P1 · 文档数字**：README 版本头、AGENTS.md 161/51、docs/README 59 条、
   CHANGELOG 补 12.5.0–12.5.2；新建 `docs/audit_b8_cross.md` 收口批 8。
7. **P1 · 动效补全**：`OgLAsyncSliver` 三态接 `OgLSurfaceSwitch + ValueKey(state)`；
   TabBarView 切换走 `OgLAnim.shellDuration/shellOffset`；评估 11 处
   RefreshIndicator 的档位一致性。
8. **P1 · 回归锁接线**：给 `search_page.dart` / `code_editor_page.dart`
   加页面级渲染测试，确保组件真的被接入。
9. **P2 · 门禁覆盖面**：motion/ui 白名单收紧（`seconds:`、`CURVES_ALLOWED`、
   AnimatedXxx）、图标尺寸令牌、SnackBar 规格收敛、裸数字清理。

## 六、总体结论

**分层加桥接制度本身成立**（161 文件无确证绕层违规、三桥按序注册），
但**保证这套制度的门禁不可信**：离开仓库根目录会静默报绿、export 可绕过、
kernel 文件头无人检查、桥漏注册无断言、i18n 安全文案里有 32 个 dict 值
而 CI 全绿。批 8 指出的 15 项遗留 **12 项未修、3 项部分修、0 项已修**——
「门禁自身可信度」自批 8 以来零推进。

**UI 侧同理**：硬编码动效为 0（motion_audit 有效），但 `AsyncSliver` 四态、
TabBarView、11 处 RefreshIndicator 仍是硬切；v12.5.2 的回归锁只锁组件、不锁接线。
制度已写好，缺的是「把制度接到每个入口」与「让门禁自己被门禁检查」。

最该补的一条规范：**门禁失效必须报错，不得静默通过**。
最该补的一道门禁：**gate-of-gates**（临时 CWD + 扫描数 > 0 + 自述=实现 + 文档数字）。
