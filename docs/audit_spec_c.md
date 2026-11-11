# 审计报告 · 视角 C：规范一致性、文档契约与门禁体系（v12.5.2，main）

> 只审不改。本报告为唯一产出，未改动任何源码/文档/CI 文件，未执行 git 写操作。
> 方法：AGENTS.md / QUALITY_STANDARD.md / CONSISTENCY.md / ARCHITECTURE.md / release_notes/README.md / changed/_content/_STYLE.md 全文读；全部门禁脚本实跑（仓库根 + /tmp 双 CWD）；release 四方（release_notes/ _content/ releases.json/ _posts/）脚本比对；test/ 全清单 + 抽读。
> 行号以当前工作区（v12.5.2）为准。区分【确证】（静态+实跑）与【推测】。

**统计：共 17 条 —— P0×1，P1×7，P2×9。**（另有 3 项正面确认，不计入缺陷。）

---

## 一、规范漂移（文档说的 X vs 实际 Y）

### C-01 [P1] AGENTS.md 版本头与量纲全面过期（确证）
- **文件:行号**：`AGENTS.md:3-4`
- **证据**：文档自述「v12.0.0 LTS…159 个 Dart 文件 ≈ 55,800 行，测试 49 文件 ≈ 10,700 行」；实测 `pubspec.yaml:21` = 12.5.2+125200、`lib/main.dart:46` = '12.5.2'，`find lib -name '*.dart' | wc -l` = **161**，`wc -l` 合计 **56,565 行**，`find test -name '*_test.dart' | wc -l` = **51**（≈10,967 行）。四项数字全部落后三个 patch 版本。AGENTS.md §7 重点测试清单也未含 v12.5.x 新增的 `ui_regression_test.dart`（51 文件 vs 自述 49）。
- **建议**：AGENTS.md 头部数字改为脚本可生成（如 version_sync.py 顺带校验 AGENTS 自述与实测一致），或改为不带具体数字的表述。版本纪律应覆盖所有「自称版本」的入口，不只是 main.dart × pubspec。

### C-02 [P1] README.md 版本头停在 v9.0.0，落后当前 v12.5.2（确证；B8-C-03 未修复，且又落后 3 个版本）
- **文件:行号**：`README.md:5`
- **证据**：「**GitHub 仓库管理客户端 · v9.0.0**」；对照 pubspec 12.5.2。自批 8 点名至今**原样未动**。
- **建议**：修 README，并把 README 版本自述纳入 version_sync.py 检查面（见 C-15 制度性建议）。

### C-03 [P2] docs/README.md 把 QUALITY_STANDARD.md 描述为「十条原则性条款」，实际 59 条（确证；B8-C-06 未修复）
- **文件:行号**：`docs/README.md:9`；QUALITY_STANDARD.md 末条编号 59、共十章。
- **建议**：改为「59 条原则 · 十章」或去掉数量。

### C-04 [P2] docs/5layer-audit-todo.md 的门禁输出快照与现状不符（确证）
- **文件:行号**：`docs/5layer-audit-todo.md:9-14`
- **证据**：写「main 144 文件 / web 151 文件」，实测 layer_audit 报 161 文件；「perf_audit 输出：0 违规」——当前 `perf_audit.py --fatal` 报告 **15 处**（均为已登记 ALLOW/REVIEWED_BOUNDED 的报告性条目，非违规，但快照数字失真）。
- **违反原则**：57、47。
- **建议**：该文件为快照性质，标注「数字为记录时点快照」或刷新。

### C-05 [P2] AGENTS.md §1 宣称 perf 白名单「ALLOW 7 文件 + REVIEWED_BOUNDED 7 文件」，与实现不符（确证）
- **文件:行号**：`AGENTS.md`（§2 第 2 条）；`tool/perf_audit.py:31-49`
- **证据**：实测 ALLOW 恰 **6** 项、REVIEWED_BOUNDED 恰 **7** 项（awk 计数）。文档多算 1。
- **违反原则**：45、57（量化口径不可凭记忆写）。
- **建议**：改为「ALLOW 6 + REVIEWED_BOUNDED 7」，或让脚本 `--selfcheck` 输出白名单计数供文档引用。

### C-06 [P2] CONSISTENCY.md 事件码「OGL-CONS-2xx」为占位符写法，源码实际是 203/204（确证）
- **文件:行号**：`docs/CONSISTENCY.md:15`（D3 行事件码列）
- **证据**：`disk_cache.dart` 实际出现 OGL-CONS-201/202/203/204/206/207/208/209；D3 冲突重试对应 **203/204**，而总表写「2xx」。本表自称「权威语义基线、源码引用本文」，占位符使「引用具体事件码」的契约无法核对。其余各行事件码（201/202/206/207/209）与源码一致。
- **建议**：D3 行改为 `OGL-CONS-203/204`。

### C-07 [P2] i18n_scan.py docstring 虚构 `--allowlist` 接口（确证；B8-C-08 未修复）
- **文件:行号**：`tool/i18n_scan.py:21`（用法示例）vs `:241-246`（argparse 仅 --lib/--i18n/--json/--check）
- **证据**：实跑 `--allowlist` 报 unrecognized arguments；`tool/i18n_allow.txt` 不存在。
- **建议**：删除 docstring 死接口或实现之。

### C-08 [P2] layer_audit.py 自述层名与 AGENTS.md 不一致：「硬件层/启动层」vs「kernel L0 内核层」（确证）
- **文件:行号**：`tool/layer_audit.py:6-9`（「L0 启动层 kernel / L1 硬件层 base / L2 逻辑层 / L3 交互层」）；AGENTS.md §1 用「kernel L0 / base L1 / domain L2 / surface L3」。ARCHITECTURE.md §5 例子还写「硬件层内还有 disk/disk_bridge.dart」。同一套层在三个文档三种叫法，读者对不上号。
- **违反原则**：57。
- **建议**：统一术语表（kernel/base/domain/surface + L0–L3），门禁 docstring 同步。

### C-09 [P2] CONSISTENCY.md「门禁盲区（待补）：layer_audit.py 不解析 export」已过期（确证·正面偏确认但记录失真）
- **文件:行号**：`docs/CONSISTENCY.md:46-48`
- **证据**：batch 1/2 后 contract_audit.py 已解析 export（`IMPORT_RE` 同时匹配 import|export，`tool/contract_audit.py:31,71-88`）并覆盖 base/domain 文件头与平台门面。该「待补」清单只保留「motion/perf 只扫 surface、本层语义无 CI 裁决」才成立。
- **建议**：更新该段，否则后人按它判断门禁覆盖面会低估现有能力。

---

## 二、门禁假绿 / 盲区

### C-10 [P0] layer_audit.py 与 i18n_scan.py 依赖 CWD，离开仓库根静默全绿（确证·实跑复现；B8-C-02 **未修复**）
- **文件:行号**：`tool/layer_audit.py:72`（`--lib default='lib'` 相对路径）；`tool/i18n_scan.py:244-246`（`--lib/--i18n` 同病）
- **证据（本次实跑）**：
  - `cd /tmp && python3 …/layer_audit.py --fatal` → 「文件总数：0 / 违规：0」**exit=0**；
  - `cd /tmp && python3 …/i18n_scan.py --check` → 「界面文案 0 处未本地化…[check] 通过」**exit=0**（zh 分片目录不存在也不报错，`load_shard` 返回 None 即跳过；语言清单检查同样全绿）；
  - 对照：contract_audit/ui_audit/perf_audit/motion_audit/ci_config_audit 均以 `__file__` 定根，/tmp 下仍真实扫描（perf 从 /tmp 实跑报 15 处，与根目录一致）。门禁体系内**两种定根方式并存**，说明修复成本极低（照抄 `ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))`），但两支最老的门禁一直没修。
- **后果**：CI 中若 working-directory 漂移，两支门禁零成本假绿；本地/定时任务在任意目录调用时输出「0 违规」的伪证。直接违反「失败必须如实可见」工程底线。
- **违反原则**：45、53、15。
- **建议**：① 两脚本默认路径改为基于 `__file__` 的绝对 ROOT；② 加最小健全性断言：扫描文件数为 0 或 zh 分片目录不存在时**显式报错退出非零**（fail loud，而不是 no-op）。③ 建议同查 version_sync.py、sort_imports.py 等其余脚本（本次未逐一 /tmp 实跑，标推测）。

### C-11 [P1] contract_audit.py docstring 第 5 项「204/206 回归测试弱提示」死描述仍未实现（确证；B8-C-01 **未修复**）
- **文件:行号**：`tool/contract_audit.py:13`（docstring 第 5 项）vs `:140-146`（`sections` 恰 4 键；全文无任何 check 函数触及状态码或 test/）
- **证据**：实跑 `--fatal` → 4 节各 0、exit=0；docstring 列 5 项。批 4 加的 `audit_` 排除（`:55-58`）注释成立，但 docstring 未同步。
- **违反原则**：53、55、57。
- **建议**：删掉第 5 项；docstring 同步说明 `audit_*.md` 排除规则。156 行脚本，5 分钟工作量，挂了三个版本。

### C-12 [P1] sort_imports.py / check_content.py 有工具无门禁：未接入 CI（确证）
- **文件:行号**：`.github/workflows/ci.yml`（全文 grep 无 sort_imports / check_content）；`tool/README.md:29` 宣称 sort_imports 为仓库工具；`changed/check_content.py` 自述「命中即打印，退出码非零」。
- **证据**：CI 十道门禁（AGENTS §2）不含这两支；check_content.py 实跑当前 `exit=1`（4 篇历史文章命中「macOS/iOS 被驼峰正则误伤」等），若接入需先修误报，但**规范要求的检查面（_STYLE.md 的内容边界/语气/结构/篇幅）完全靠人肉**。_STYLE.md 诸多要求（书面语、字数 350–700、节序、每节 3–8 条）check_content.py 一条都没覆盖——它只查技术词残留。
- **违反原则**：45（由脚本强制而非靠自觉）、53。
- **建议**：check_content 补规则（字数区间、节序、感叹号已在、人称已在）后接入 CI 严格模式（历史文章白名单豁免）；sort_imports 接 `--check` 模式或从 AGENTS 门禁清单中说明它是手动工具。

### C-13 [P1] ci.yml 严格模式终审的计数命令有一个潜伏缺陷（确证·bash 语义实测）
- **文件:行号**：`.github/workflows/ci.yml:161`（`N=$(grep -c 'FAIL:' /tmp/strict_failures.txt 2>/dev/null || echo 0)`）
- **证据**：`grep -c` 在文件不存在时输出 `0` 且退出码 2 —— `||` 触发后再 echo 一个 0，**无碍**；但若命令替换内 grep 因其它原因退出非零（如文件存在但为二进制/权限问题），`|| echo 0` 会**覆盖 grep 已经输出的真实计数**，得到 0 → 终审放行。本次在 Alpine 实测：文件存在时返回 1 正常；文件不存在返回 0 正常；缺陷仅在异常退出路径。低概率但终审是全门禁的唯一裁决点，属「静默降级」形状的代码。
- **建议**：改为 `N=$(grep -c 'FAIL:' /tmp/strict_failures.txt); N=${N:-0}` 或 `cat 文件 | grep -c` 前先 `[ -f ]`。
- （推测成分：CI runner 的 grep 行为与实测一致度高，但未在 GitHub runner 验证，标确证·静态+本地实测。）

### C-14 [P2] perf_audit 从 /tmp 运行时「15 处」报告与根目录一致，但计数口径说明缺失（确证·低危）
- **文件:行号**：`tool/perf_audit.py:27`（`__file__` 定根，无 CWD 假绿）
- **证据**：/tmp 实跑输出 15 处（同根目录），确认已修。此条为对照记录，计入 C-10 的正面证据链。

---

## 三、发布规范（v12.5.0 / 12.5.1 / 12.5.2 四方对齐）

### C-15 [正面确认] v12.5.0/12.5.1/12.5.2 四方对齐良好（确证·实跑）
- `release_notes/v12.5.x.md`（中英对照、含「产物」节）↔ `changed/_content/v12.5.x.md`（面向使用者、406/459/476 字，均在 350–700 区间）↔ `releases.json`（三版本均在，各 23 assets，**每个 asset 键集恰 {name, url, size}，0 缺 url**）↔ `_posts/2026-11-10-v12.5.{0,1,2}.md`（front-matter version 与正文一致，含下载表）。`generate_posts.py` 对三版本均正常生成（posts 已存在且与 _content 一致），无「缺说明跳过」迹象。version_sync exit=0。

### C-16 [P1] CHANGELOG.md 顶部停在 12.4.0，缺 12.5.0/12.5.1/12.5.2 条目（确证）
- **文件:行号**：`CHANGELOG.md:3`（`## 12.4.0（2026-11-10）`，grep "12.5" 无条目）
- **证据**：AGENTS.md §8「CHANGELOG.md 新版本在前」；三个已发布版本在 release_notes/_content/releases.json/_posts 四处齐备，唯独 CHANGELOG 缺失。版本真相链五处少一处。
- **违反原则**：45、47。
- **建议**：补 12.5.0–12.5.2 条目；version_sync.py 顺带校验「CHANGELOG 顶部版本 == pubspec version」。
- （关联确认：release_notes/README.md 的发布正文优先级表与 ci/build 流程自述一致，无漂移。）

### C-17 [P2] check_content.py 的驼峰正则把 macOS/iOS 误判为「可疑表述」，规则未区分平台名（确证·实跑）
- **文件:行号**：`changed/check_content.py:17`（`\b[a-z]+[A-Z][A-Za-z]*\b`）；实跑命中 v5.6.0/v7.x 的 macOS、iOS。
- **后果**：误报使脚本当前恒 exit=1，即使接入 CI 也无法作为可信信号（全部命中需人工裁决 → 狼来了效应）；同时它对 _STYLE.md 的字数/结构/语气要求覆盖率为 0（见 C-12）。
- **建议**：白名单 {macOS, iOS, GitHub, …} + 补字数/节序检查。

---

## 四、测试覆盖

### C-18 [P2]（合并计入 P2 计数）test/README.md 覆盖表与 test/ 实况偏差（确证）
- **文件:行号**：`test/README.md` 表格；实测 kernel 6 / base 12 / domain 14 / surface 19 + screenshots。
- **证据**：表格未列 `ui_regression_test.dart`（v12.5.2 发布说明宣称「三处布局契约已写入自动检查」，该测试存在且含真实 widget 断言——`expect(find.text('标题行'),…)`、`side.width > 0` 等行为断言，非空壳）；未列 `boot_define_injection_test.dart`、`gh_write_endpoints_test.dart` 等。README 覆盖表为早期版本残留。
- **说明**：三个新增可测组件（ui_regression 对应的布局契约、permission_selftest、format）**均有测试且为行为断言**，抽读未发现「只断言常量」的空壳测试；CI 配置自检（ci_config_audit）已接入 ci.yml。缺陷仅在 README 索引失真（原则 57）。

### 测试面小结（正面确认，不计缺陷）
1. 51 个 *_test.dart 覆盖四层 + screenshots，v12.5.x 新组件有回归测试且断言行为（非常量）。
2. `ci_config_audit.py --fatal` 已接入 ci.yml（第 4 步），含 PyYAML 兜底安装。
3. `stats_chart.py --selftest`、`inject_platform_spec_selftest.py` 均在 CI。i18n_scan `--check` 也已接入（i18n 门禁完整）。

---

## 五、文档契约引用

- **正向（contract_audit 检查面）**：实跑「文档契约引用：0 处」，`docs/` 非审计文件中引用的 docs/*.md 全部存在。确证。
- **反向（docs 引用不存在的源码符号/事件码）**：本次未发现悬空源码符号引用；事件码漂移见 C-06（占位符 2xx）；层名漂移见 C-08；数字漂移见 C-01/03/04/05。
- **audit_b8_cross.md 未生成**：`ls docs | grep b8` 仅 `_a/_b/_c`，`grep -rn b8_cross docs` 无命中 → **确证缺失**，详见遗留项核对表。

---

## 六、制度性缺口（最该补的一规范 + 一门禁）

### 最该补的一条规范
**「所有自称版本/计数的文档数字必须可由脚本再生成或由脚本校验」**（落点：AGENTS.md §8 增一条 + QUALITY_STANDARD 第 45 条扩围）。理由：本轮 P1 里 C-01/02/03/16 四条全是「文档数字静默腐烂」——版本号、文件数、测试数、白名单计数、CHANGELOG 顶部版本。现有 version_sync.py 只看 main.dart × pubspec 两个点，AGENTS/README/CHANGELOG/docs/README 全在其盲区；这些数字每年腐烂数次而无人发现，因为没有任何门禁负责。规范先行，门禁随后（见下）。

### 最该补的一道门禁
**门禁脚本自身的健全性自检（gate-of-gates）**：一个 20 行脚本（或并入 ci_config_audit），CI 中执行：
1. 对每支 `tool/*_audit*.py` 在**仓库根之外的临时 CWD** 跑一遍，断言其「扫描对象数 > 0」（直接击杀 C-10 类 CWD 假绿——layer_audit/i18n_scan 在 /tmp 下报 0 文件 0 违规 exit 0，是当前体系里最危险的假绿通道）；
2. 解析各脚本 docstring 宣称的检查项数 vs `sections`/argparse 实际装配数（击杀 C-11/C-07 类死描述——B8-C-01 挂三个版本无人发现，因为没有任何东西校验「脚本自述=实现」）。
3. 顺带校验 AGENTS.md 头部数字 / README 版本 / CHANGELOG 顶部版本与 pubspec 一致（击杀 C-01/02/16）。
为什么现有制度拦不住：CI 严格模式只验证「门禁说全绿」，从不验证「门禁有能力说真话」；QUALITY 第 53 条只约束审计脚本守语法结构，没有一条原则约束**门禁本身的可信度**。这是整个体系的元盲区。

---

## 批 8 遗留项现状核对表（对照 docs/audit_b8_a.md / b8_b.md / b8_c.md）

| 遗留项 | 级别 | 现状 | 证据 |
|---|---|---|---|
| B8-C-01 contract_audit docstring 第 5 项死描述 | P0 | **未修** | `contract_audit.py:13` 仍列 5 项，`:142-146` sections 恰 4 键；实跑 4 节。见本报告 C-11 |
| B8-C-02 layer_audit/i18n_scan 依赖 CWD | P1 | **未修** | /tmp 实跑两脚本均 exit=0 全绿（layer 报 0 文件）。见 C-10 |
| B8-C-03 README 版本头 v9.0.0 | P1 | **未修**（且已从落后 3 个大版本扩大到 3 个大版本+3 个 patch） | `README.md:5` 原文未动。见 C-02 |
| B8-C-04 layer_audit KNOWN「下一批」挂空 | P1 | **未修** | `layer_audit.py:40,46-50` 注释原文仍在；KNOWN 仍 2 项未收敛 |
| B8-C-05 QUALITY 原则 39 脱敏豁免措辞 | P2 | **未修** | `QUALITY_STANDARD.md` 原则 39 原文未加「脱敏形态除外」 |
| B8-C-06 docs/README「十条」描述 | P2 | **未修** | `docs/README.md:9` 原文。见 C-03 |
| B8-C-07 AGENTS「Web 分支为 zh_TW」无落点 | P2 | **部分修/未修** | `AGENTS.md` §6 仍写「Web 分支为 zh_TW」；assets/i18n 仍 6 目录无 zh_TW。未改文档也未除歧义 |
| B8-C-08 i18n_scan docstring `--allowlist` 死接口 | P2 | **未修** | `i18n_scan.py:21` 原文。见 C-07 |
| B8-C-09 contract_audit 文档引用正则盲区 | P2 | **未修** | `contract_audit.py:36` 正则原样 |
| B8-C-10 文件头检查 400 字符窗口/只比代号 | P2 | **未修** | `contract_audit.py:96` `text[:400]` 原样 |
| B8-C-11 ARCHITECTURE §4.3 与 PLATFORM_ALLOW 叙事不一致 | P2 | **部分修** | ARCHITECTURE.md §4.3 已补「平台判定现状…应经 platform 层门面」并承认若干分流文件存在，但未提及 contract_audit 已把 5 文件登记白名单，两文档仍未对齐 |
| B8-C-12 / B8-C-14 审计产物集与计划失真、docs/README 索引停在第 1/2 批 | P2 | **部分修** | b8_a/b8_c 已补齐（本轮可见），但 **audit_b8_cross.md 仍未生成**（ls 确证）；docs/README.md 审计索引仍只列 b1/b2 + 5 专项（`:18-19`），b3–b8 共 20+ 份报告不可发现；AUDIT_PLAN.md「每批 a/b/c/cross」承诺仍与实际缺口（b7_b 缺、b8_cross 缺）无说明 |
| B8-B-01 boot manifest 不覆盖 lib/platform 与 main.dart | P1 | **未修** | `tool/boot_manifest.py` layer_dirs 仍为四层（tool/README 与 b8_b 引用一致，未见到修复痕迹） |
| B8-B-06 CI Action 未钉 commit SHA | P1 | **未修** | ci.yml 仍 `actions/checkout@v4` 等 tag 引用 |
| B8-B-07 Android 签名密码硬编码 `android` | P1 | **未修**（本次未复核 build.yml，按 b8_b 记录与无变更迹象记未修；**推测**） | — |
| B8-A-01 六语言分片 32 个字典值 | P0 | **未修**（本轮脚本确证） | 实测 162 分片 json.load：zh_Hant/de/fr/ru common.json 的 tokenExit* 8 键 × 4 语言 = 32 个值仍为 dict，非字符串 |
| B8-A-02 i18n_scan 只比 key 不比值类型 | P1 | **未修** | `i18n_scan.py:226-242` 仍为 `set(keys)` 比对 |

**补充核对（B8-A-01 值类型）**：本轮已用脚本核完全部 162 分片：**32 个字典值原样存在**（zh_Hant/de/fr/ru × common.json 的 tokenExit* 8 键，`json.load` 实测 `bad: 32`），B8-A-01 的 P0 数据缺陷**未修**；且 i18n_scan `--check`（只比 key）与 i18n_test.dart（同法）均不校验值类型（B8-A-02 未修），CI 全绿放行。

### 总结论
批 8 遗留项 **14 项可核对项：未修 11、部分修 3、已修 0**。尤其批 8 视角 C 自己点名的两条 P0/P1 门禁假绿（C-01 docstring、C-02 CWD）在 v12.5.2 上原样存在，且 C-02 已在本轮 /tmp 实跑二次确证。交叉报告 audit_b8_cross.md 未生成，与 AUDIT_PLAN 承诺不符。门禁体系的「骨架」（严格模式收集-终审、contract_audit 补盲区、check_content 体系）自批 1/2 后明显改善，但「门禁自身可信度」这条线自批 8 以来零推进。
