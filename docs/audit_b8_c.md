# 第 8 批 · 视角 C：契约与规范审计（i18n 与门禁体系，v12.0.0 LTS）

> 只审不改：未改动 `lib/`，未写任何 `tool/` 文件，本报告为唯一产出。范围文件全部 `file_read` 完整读（清单见文末），不以 rg 代替阅读；行号以当前工作区为准。裁决依据：`docs/QUALITY_STANDARD.md`（59 条）。每条标注是否确证；风格偏好不计入缺陷。
> 优先级分布：P0×1 / P1×5 / P2×8 = 14 条。

---

### B8-C-01 [P0] contract_audit.py docstring 第 5 项「204/206 回归测试弱提示」仍未实现，且批 4 加的 `audit_` 排除使该死描述更难被发现（B3-C-12 未修复）
- **文件:行号**：`tool/contract_audit.py:13`（docstring 第 5 项）；对照 `:142-146`（`sections` 恰 4 键）、`:55-58`（`audit_` 排除）。
- **问题**：docstring 宣称做第 5 项检查「204/206 等状态码在写回执路径是否有对应的回归测试（弱提示）」，但 `main()` 只装配 4 个 section，全文无任何 `check_` 函数触及状态码或 test/ 目录。批 4 在 `check_doc_refs` 里加了 `if name.startswith('audit_'): continue`（合理，审计快照不是活契约），但 docstring 未同步说明该排除，且第 5 项死描述依旧。
- **后果**：`--fatal` 门禁被 AGENTS.md:29/66 当作「结构契约检查」引用，CI 全绿掩盖 docstring 与实现的 5/4 偏差；读者会误以为 206 回执已有门禁守卫（实际 test/domain 对 206 的覆盖由人肉补，无脚本裁决）。
- **违反原则**：53、55、57。
- **证据（确证·静态 + 实跑）**：docstring :13 原文；`sections` 4 键；实跑 `python3 tool/contract_audit.py` → 4 节各 0、exit=0；`grep check_` 仅 4 个函数。排除 `audit_` 的注释本身成立，不计缺陷；计的是第 5 项死描述。

### B8-C-02 [P1] layer_audit.py / i18n_scan.py 依赖 CWD，离开仓库根实跑静默通过——门禁能力与 AGENTS 宣称不符
- **文件:行号**：`tool/layer_audit.py:72`（`--lib default='lib'` 相对路径）与 `:105`；`tool/i18n_scan.py:244-246`（`--lib/--i18n` 相对默认）。
- **问题**：AGENTS.md §1/§2 宣称两脚本为 CI 门禁「违规退出 1」。但默认参数是相对路径：在仓库根之外执行 `python3 /path/tool/layer_audit.py --fatal` 实测「文件总数：0 / 违规：0 / exit=0」，i18n_scan 同样全绿（zh 目录都不存在也不报错，`os.path.isdir` 直接跳过检查）。
- **后果**：任何在错误 CWD（或 CI 工作目录配置漂移）下触发的调用会得到一份「零违规」的假绿报告；门禁的失败语义在 path 缺失时静默退化为 no-op。
- **违反原则**：53、45（由脚本强制而非靠自觉）。
- **证据（确证·实跑）**：`cd /tmp && python3 …/layer_audit.py --fatal` → 文件总数 0、exit=0；同法 i18n_scan --check → 「通过」exit=0。contract_audit.py 因用 `os.path.abspath(__file__)` 定根不受影响（对照正面）。

### B8-C-03 [P1] README.md 版本头停在 v9.0.0，落后当前 v12.0.0 三个大版本
- **文件:行号**：`README.md:5`；对照 `pubspec.yaml:21`（12.0.0+120000）、`lib/main.dart:46`（kOgLAppVersion='12.0.0'）、`AGENTS.md:3`（v12.0.0 LTS）。
- **问题**：README 副标题写「**GitHub 仓库管理客户端 · v9.0.0**」，徽章与平台表未更新出问题，但版本自述与真相差 3 个大版本；安装节示例仍写「`<version>` 形如 `v8.0.0`」。
- **后果**：项目第一入口谎报版本，违反原则 45「版本号只有一个真相，任何两处不一致都是谎报」；version_sync.py 只管 main.dart × pubspec，README 属该门禁盲区（与 B3-C-14/B5-C-01 同族，AGENTS 侧已修、README 侧遗漏）。
- **违反原则**：45、47、57。
- **证据（确证·静态）**：README.md:5、:79 原文；pubspec.yaml:21；main.dart:46。

### B8-C-04 [P1] AGENTS.md 宣称「处理 lib/ 与 test/」与「白名单 7+7 文件」等量化口径未随实际门禁复核，且 layer_audit KNOWN 注释「下一批」已挂空三个版本
- **文件:行号**：`AGENTS.md:14-15`（KNOWN 恰 2 项描述与实现一致）；对照 `tool/layer_audit.py:40,46-50,96`（注释「下一批：…」「已知待收敛（5.0 清单）」）。
- **问题**：layer_audit 的 KNOWN 白名单自 5.0 起注释为「下一批：引入启动层契约接口」，至 v12 三个版本未收敛、注释文本原样；AGENTS.md §1 把它如实转述为「恰 2 项待收敛」，但 ARCHITECTURE.md §4.3/§7 也标「后续工作」——三份文档都把同一待办挂在不同时间尺度上，无任何一处给出批次编号或截止。
- **后果**：待办无归属（原则 59 三问无答），后续审计无法判断是「计划中」还是「被遗忘」；白名单每多活一个版本，B3-C-13 的「错误进度感」就加深一层。
- **违反原则**：55、59、56。
- **证据（确证·静态）**：layer_audit.py:40/46/96 原文；KNOWN 2 项与 gh_api.dart:17、gh_client.dart:17 两个 import 对上；AGENTS.md:14、ARCHITECTURE.md §4.3/§7 原文。

### B8-C-05 [P2] QUALITY_STANDARD.md 原则 39 措辞精度：脱敏形态豁免仍未补充（B5-C-13 未采纳）
- **文件:行号**：`docs/QUALITY_STANDARD.md:39`；对照 `lib/domain/gh/gh_auth.dart:246-253`（OGL-AUTH-001 记 `token.masked`）。
- **问题**：原则 39 写「凭证…永不进日志」，实现按合理解释只记脱敏形态；B5-C-13 建议补「脱敏形态除外」一句，原则文本至今未改。原则自称「可裁决的依据」，但按字面裁决会把现存合规日志判为违规——裁决依据自身不可裁决。
- **后果**：后续审计者（或自动化规则）据字面误判 OGL-AUTH-001；或反向促使实现者删掉脱敏诊断，损失可观测性。
- **违反原则**：54（注释/规范应可裁决）、53。
- **证据（确证·静态）**：原则 39 原文 vs gh_auth.dart:250 日志字段；不判实现为缺陷，只判规范精度。

### B8-C-06 [P2] docs/README.md 把 QUALITY_STANDARD.md 描述为「十条原则性条款」，实际 59 条
- **文件:行号**：`docs/README.md:9`。
- **问题**：文档目录写「质量标准：十条原则性条款」；QUALITY_STANDARD.md 实有 59 条、分十章。该描述可能是早期 10 条版本残留，原则条数早已扩容。
- **后果**：文档索引撒谎（原则 57：文档引用的符号/事实必须真实存在）；新读者按「十条」预期读到一个 59 条文件。
- **违反原则**：57、56。
- **证据（确证·静态）**：docs/README.md:9 原文；QUALITY_STANDARD.md 末条编号 59。

### B8-C-07 [P2] AGENTS.md 声明的六语言清单（§6「Web 分支为 zh_TW」）与门禁实测的 6 目录清单口径不一致，zh_TW 无任何落点
- **文件:行号**：`AGENTS.md:66`（§6 新增页面：「建六语言分片（zh / zh_Hant / en / de / fr / ru；Web 分支为 zh_TW）」）；对照 `assets/i18n/`（6 目录，无 zh_TW）、`pubspec.yaml:144-149`、`lib/surface/i18n/og_l_i18n.dart:74-79`（均无 zh_TW）。
- **问题**：全库 `rg zh_TW` 仅命中一处注释（og_l_app.dart:191 的 Locale 映射说明）；「Web 分支为 zh_TW」所指的分支产物在当前工作区不存在，三处清单（locales/目录/pubspec）一致且都不含 zh_TW。
- **后果**：按 AGENTS 指引新增页面的贡献者会去找不存在的 zh_TW 分支分片；或误以为需自行建 zh_TW 目录——一旦建了，i18n_scan 三处清单检查反而报「目录有但 locales 未声明」。
- **违反原则**：57、53。
- **证据（确证·静态 + 实跑）**：`ls assets/i18n` 6 目录；pubspec :144-149；og_l_i18n.dart:74-79；rg zh_TW 仅 1 处注释；实跑 `i18n_scan.py --check` 通过（三处均为 6 种）。

### B8-C-08 [P2] i18n_scan.py docstring 的 `--allowlist` 参数不存在
- **文件:行号**：`tool/i18n_scan.py:21`（用法示例 `--allowlist tool/i18n_allow.txt`）；对照 `:241-246`（argparse 无该参数）。
- **问题**：docstring 用法一节列了 `--allowlist`，argparse 实际只有 `--lib/--i18n/--json/--check`；实跑报 `unrecognized arguments`。豁免实际由 `ALLOW_FILES`/`ALLOW_ITEMS`/`i18n-allow` 注释三套机制承担，与 docstring 描述的不是同一接口。
- **后果**：按文档调用直接报错；`tool/i18n_allow.txt` 文件也不存在，属 docstring 写了没实现的死接口（与 B8-C-01 同族：脚本自述 vs 实现）。
- **违反原则**：55、57、53。
- **证据（确证·静态 + 实跑）**：docstring :21 原文；argparse 参数表；`python3 tool/i18n_scan.py --allowlist foo.txt` → argparse error；`ls tool/i18n_allow.txt` → No such file。

### B8-C-09 [P2] contract_audit 文档契约引用检查正则 blind spot：`docs2/x.md`、`DOCS/y.md` 等形式不匹配，且引用存在性与「契约有效性」混为一谈
- **文件:行号**：`tool/contract_audit.py:36`（`DOC_REF_RE = r'docs/[A-Z0-9_.-]+\.md'`，`re.I`）。
- **问题**：实测 `docs2/x.md`、`DOCS/y.md` 均不命中（`docs2/` 前缀截断匹配、大写 DOCS 因 `\b` 无保障可命中但语义混淆）；同时该检查只验证文件存在，不验证被引文档是否与代码同步——B3-C-01/B5-C-02 那类「文档存在但描述过期」全部漏过。
- **后果**：门禁输出「文档契约引用：0 处」给出演示性安全感；「契约出处存在」被等价于「契约有效」，与原则 57 的实际要求（引用内容真实）有落差。
- **违反原则**：53、57。
- **证据（确证·静态 + 正则实测）**：:36 原文；Python 实测两例均空匹配；CONSISTENCY.md:46-48 已修（见 B8-C-13 正面确认）说明「过期文档」是现实发生过的问题类别。

### B8-C-10 [P2] contract_audit 文件头检查窗口 400 字符且只比对 L 代号，B3-C-06/B5-C-12 点名后无修复
- **文件:行号**：`tool/contract_audit.py:96`（`head = text[:400]`）、`:97-107`（只比 `m.group(1)`）。
- **问题**：两批前已确证的盲区原样：① 头注释若被推到 400 字符之后则漏检（实测第 381 字符处的 `/// L2` 仍可命中，窗口精确边界脆弱）；② `/// L2 ·` 与硬惯例 `/// L2 中枢级 ·` 无区分，`HEADER_RE` 只取两字符。
- **后果**：文件头硬惯例在门禁上仍是「写了但不查」，AGENTS.md §3「文件头注释是硬惯例」无脚本兜底。
- **违反原则**：53、6（命名/标记须可被脚本识别）。
- **证据（确证·静态 + 正则实测）**：:96 原文；`re.search` 实验确认窗口行为；同 B3-C-06 证据链。

### B8-C-11 [P2] ARCHITECTURE.md §4.3 仍宣称「项目仍有若干处按平台分流…待办收敛」，与 contract_audit 的 PLATFORM_ALLOW 白名单机制描述不一致——两份文档对同一现状给出两套叙事
- **文件:行号**：`docs/ARCHITECTURE.md:79-81`（§4.3 平台判定现状）；对照 `tool/contract_audit.py:33-45`（PLATFORM_ALLOW 5 文件登记制）、`AGENTS.md:29`（「平台判定必须经 lib/platform 门面…白名单」）。
- **问题**：ARCHITECTURE.md 写「统一收敛到 platform 层属待办事项」，未提及 contract_audit 已把 5 个文件（含 main.dart、permissions.dart、system_notifier.dart）登记为白名单例外；原则 3 要求例外「显式登记、可枚举」——登记存在，但架构文档的叙事停在「待办」而没承认例外清单。
- **后果**：读者按 ARCHITECTURE.md 会以为收敛尚未开始、无门禁；实际例外已登记。两文档冲突使「例外是否合法」需人工对源码裁决。
- **违反原则**：3、57、56。
- **证据（确证·静态）**：ARCHITECTURE.md §4.3 原文；contract_audit.py:33-45 白名单 5 项；实跑平台门禁 0 处。

### B8-C-12 [P2] 审计报告编号连续性：b7 缺 `_b`、b8 仅 `_b`、b1-b8 无 `_a/_b` 之外的缺口说明，docs/README.md 审计索引停在第 1/2 批
- **文件:行号**：`docs/` 目录清单（audit_b7_a/b7_c/b7_cross 存在、audit_b7_b 缺；audit_b8_b 存在、audit_b8_a/b8_c/b8_cross 未产出）；对照 `docs/README.md`（审计记录表只列 b1/b2 与 5 份专项，未提 b3–b8）、`docs/AUDIT_PLAN.md:35`（「每批：a/b/c/cross」）。
- **问题**：AUDIT_PLAN 承诺的批产物结构与实际不符：b7_b、b8_a 等文件缺失且无任何文档说明缺失原因（是未跑、还是在途、还是被否）；docs/README.md 的审计索引只写到第 2 批，b3–b7 共 16 份报告在索引中不可发现。
- **后果**：原则 56 要求「一次性规划落地后移除」、原则 47 要求记录与事实一致——计划文档描述的产物集与仓库状态脱节；交叉引用审计结论时无法确认某视角是否真的审过。
- **违反原则**：47、56、57。
- **证据（确证·静态）**：`ls docs | grep b[78]_` 结果；docs/README.md 审计表原文；AUDIT_PLAN.md:35 原文。缺文件本身可能是在途工作，故记文档失真而非流程违规。

### B8-C-13 [正面确认] 批 5 遗留三项文档契约已在当前工作区修复，交叉引用编号稳定
- **范围**：`docs/CONSISTENCY.md:46-48`（206 回执已改为「状态码为 206 或 written.sha 为空时一律回读」——B5-C-02/B3-C-01 关闭）；`AGENTS.md:3`（v12.0.0 LTS + 159 文件/49 测试与实测一致——B5-C-01 关闭）；`lib/surface/app/client_shell.dart:113-116`（refreshState 已接线并加同值短路防自激，注释挂 B7-A-01/B5-A-02/C-14 编号，与 gh_auth.dart:200-202 勘误注释互相可追溯）。
- **证据（确证·静态 + 实跑）**：三处原文；`rg refreshState` 现有 shell 接线 + 测试 `test/domain/gh_auth_service_test.dart:51-53`；layer_audit 实跑违规 0；audit_bN_cross 对 B3-C-09/B4-C-08/B5-C-11 等编号引用一致（rg 抽验 30+ 处无错位）。
- **不计缺陷**；记录为验证结论。

### B8-C-14 [P2] docs/README.md 未收录 OAUTH_ORG_SETUP.md 之外的 b3–b8 批次产物，且 AUDIT_PLAN.md 自称「八批」计划但无任何「计划完成度」记录
- **文件:行号**：`docs/AUDIT_PLAN.md:14-35`；对照实际 `docs/audit_b*.md` 28 份。
- **问题**：计划写「每批 a/b/c/cross + 交叉规则」，至今 8 批中只有 b1/b2/b3/b4/b6 集齐三视角，b5 缺 `_a`、b7 缺 `_b`、b8 只有 `_b`，且全库无一处说明总进度（哪批完结、哪些视角未跑）。一次性计划按原则 56 应在落地后移除或改写为事实记录，现为「永久考古层 + 失真」双重状态。
- **后果**：v12 LTS 的发布审计完整性不可自证——「审计过了吗？」这一问题在仓库内没有可追溯的答案表。
- **违反原则**：47、56。
- **证据（确证·静态）**：AUDIT_PLAN.md 原文 vs ls 清单；无任何进度总结文件（rg '八批|收口' docs 仅命中计划本身与 b7_cross 一处）。

---

## 覆盖文件清单（全部完整读）

| 文件 | 状态 |
|---|---|
| tool/contract_audit.py（165 行） | 完整读 + 实跑 |
| tool/layer_audit.py（106 行） | 完整读 + 实跑（含 /tmp CWD 实验） |
| tool/i18n_scan.py（328 行） | 完整读 + 实跑 --check 与非法参数实验 |
| tool/sort_imports.py（100 行） | 完整读 |
| docs/QUALITY_STANDARD.md（93 行） | 完整读 |
| docs/CONSISTENCY.md（61 行） | 完整读 |
| docs/ARCHITECTURE.md（149 行） | 完整读 |
| docs/README.md / docs/AUDIT_PLAN.md | 完整读 |
| AGENTS.md（95 行） | 完整读 |
| README.md（120 行） | 完整读 |
| docs/audit_b3_c.md（168 行）、audit_b5_c.md（135 行） | 完整读 |
| docs/audit_b7_cross.md / b6_cross / b4_cross / b8_b | rg 定向核对编号引用 |
| assets/i18n/ 目录、pubspec.yaml assets 段、og_l_i18n.dart locales 段 | 定向核对（三处清单一致性） |

## 整体规范符合度评价

**门禁体系骨架扎实，但「脚本自述 vs 实现」与「文档宣称 vs 覆盖」两层落差在 v12 仍未清零。**

- **做得好**：contract_audit 的 `audit_` 排除（批 4）注释理由充分、不是漏洞；i18n 三处清单一致性检查（locales × 目录 × pubspec）实测通过且设计有明确失效模式说明；refreshState 接线（批 5 修）带防自激短路并挂批号勘误注释，是「自我勘误留注释」（原则 58）的正面样本；跨批编号引用（B3-C-XX 被 B4/B5/B6/B7 引用）抽验 30+ 处无错位、可追溯。
- **结构性弱点**：① 门禁脚本 docstring 死接口两处（contract 第 5 项、i18n --allowlist），且 layer_audit/i18n_scan 的 CWD 敏感性让「CI 强制」承诺存在假绿通道（B8-C-01/02/08）；② 版本真相三处失真里 AGENTS 修了、README 没修（B8-C-03），版本纪律仍是「文档盲区靠人肉」；③ QUALITY_STANDARD 原则 39 精度、docs/README「十条」描述、ARCHITECTURE §4.3 白名单叙事三处规范层文档落后（B8-C-05/06/11）；④ 审计产物集与计划失真且无进度自证（B8-C-12/14）。
- **统计**：14 条（P0×1、P1×5、P2×8），全部确证·静态/实跑；B8-C-13 为正面确认，不计入缺陷数。

*未改动任何 lib/、tool/ 与被审文件；本报告为唯一产出。*
