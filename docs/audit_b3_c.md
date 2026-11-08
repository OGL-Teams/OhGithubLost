# 第 3 批 · 视角 C（契约与规范一致性）· GitHub API 层审计

- 目标：`/root/OhGithubLost`，main 分支（已核实 `git branch --show-current` = `main`）
- 范围：`lib/domain/gh/` 全部 10 文件 + `test/domain/` 全部 gh 相关测试（含 `sys_test.dart`）
  + `docs/NETWORK.md` / `docs/ARCHITECTURE.md` / `docs/CONSISTENCY.md`
  + `tool/{layer,motion,perf,ui,i18n}_audit*.py` 门禁脚本 + `docs/QUALITY_STANDARD.md` / `AGENTS.md`
- 裁决依据：`docs/QUALITY_STANDARD.md` 59 条原则（下称「原则 N」）· `AGENTS.md` · 三份文档原话
- 纪律：只审不改；**未修改任何 `lib/`、`test/`、`docs/NETWORK.md`、`docs/ARCHITECTURE.md`**；
  范围文件全部 `file_read` 完整读取；`grep`/`nl` 仅用于核实行号与符号存在性，不代替阅读
- 记录方式：发现一条即刻追加，不攒批；不确定的标「待议」

---

## B3-C-01 · 批1 C 点名的 4 处 `docs/NETWORK.md` 滞后**一处都未同步**

- **文件:行号 / 文档章节**：`docs/NETWORK.md:24`（「重试 / **主机冷却** / DoH 回落」）、
  `:38-46`（§二表格 4 行 + 「枚举定义…（**只有这 4 类**）」+「默认**全开**」）、
  `:14-21`（§一出口清单 6 行，无 `notifications` / Gist / 归档 / 图床）、
  `:97-113`（§五「web（浏览器）端的限制 —— **均经实测**」+ `:115-135` §六复现命令）；
  对照 `docs/audit_b1_c.md` 的 `B1-C-01` / `02` / `03` / `13`
- **问题描述**：批1 C（视角 C，同一视角）已逐条确证并点名 4 处文档滞后，本批复核
  `NETWORK.md` 全文 144 行，4 处**字句未动**：
  ① `:24` 仍把「主机冷却」挂在 `ResilientTransport` 名下（批1 已证全库无冷却实现）；
  ② `:45` 仍加粗断言「**只有这 4 类**」、`:46` 仍称「默认**全开**」（批1 已证
  `OgLAccelScope` 为 9 类、默认仅 4 类开）；
  ③ §一表格仍 6 行，全文无 `notifications` / `Gist` / `归档` / `图床` 字样；
  ④ §五标题仍写「均经实测」，但 §六 4 条 `curl` 复现命令只覆盖 raw/签名/CORS 中
  `api.github.com/rate_limit` 一项，表格里 8 行结论（预检 204/403、通道 308、
  签名地址无 ACAO、通道+Release 直链 `ACAO=*`）**没有任何一条给出对应复现命令**，
  `test/` 中也无 CORS 断言（批1 `B1-C-13` 已证 0 条）。
- **违反的原则编号/文档原话**：原则 **57**「文档引用的符号必须真实存在；改名时文档一并改，
  否则文档在撒谎」、原则 **52**「**端点语义必须实测**：空、无、未启用是三种不同的『没有』，
  混为一谈必出错」、原则 **45**「版本号只有一个真相；任何两处不一致都是谎报」(数字/数量同口径)、
  原则 **56**「文档只收持续有效的手册」。`NETWORK.md:9-10` 自述：
  「维护要求：本文所引用的每个符号必须与代码一致且**真实存在**；符号改名或行为变更时
  须一并更新，否则文档将失去准确性」；`NETWORK.md:3-4` 自述「本文回答三个问题：**应用向哪些
  主机发起请求**…**浏览器（web）端哪些途径可用**」。`AGENTS.md §8` 原话「文档引用的符号必须真实存在」。
- **P1** · **确证**（附证据）：本批 `file_read` 读 `docs/NETWORK.md` 全 144 行，逐行核对上述
  4 处原话；`grep -n "notifications\|Gist\|归档\|CORS\|主机冷却\|4 类" docs/NETWORK.md`
  仅命中 `:24`（主机冷却）与 `:45`（只有这 4 类），其余为 0；
  `docs/audit_b1_c.md:656-660` 自列确证清单包含 B1-C-01/02/03/13；
  `git log -1 --format=%h -- docs/NETWORK.md` 与批1 报告指向的旧版本一致。
- **备注**：本视角无 `docs/NETWORK.md` 写权限（纪律允许范围），只登记不修。

---

## B3-C-02 · 批1/批2 两轮点名的 CI 门禁盲区**全部未修**，且两个应建的契约门禁脚本不存在

- **文件:行号**：`tool/layer_audit.py:38`（`IMPORT_RE = re.compile(r"^\s*import\s+'([^']+)'", re.M)`，
  只匹配 `import`）、`:32-36`（`ALLOW` 整文件跳过，`:76-77` `if rel in ALLOW: continue`）、
  `:46-49`（`KNOWN` 白名单无归零检查）；`tool/motion_audit.py:36`
  （`SURFACE = os.path.join(ROOT, 'lib', 'surface')`）、`tool/perf_audit.py:28`（同）；
  `docs/CONSISTENCY.md:54-55` 自述「门禁盲区（待补）」；
  `tool/` 目录清单中**不存在** `net_contract_audit.py` / `disk_contract_audit.py`
- **问题描述**：三处「两轮都点名」的问题在本批复核依旧：
  ① `motion_audit.py` / `perf_audit.py` 的 `SURFACE` 常量硬编码 `lib/surface`，
  `os.walk(SURFACE)` 使 `--fatal` 全绿对 `lib/domain/gh/`、`lib/base/` 零覆盖；
  ② `layer_audit.py` 的正则**不解析 `export`**，跨层 `export`/转发门面的分层方向
  完全不受检（全库 19 处 `export`，见 `docs/audit_b2_c.md` 证据）；
  ③ `docs/CONSISTENCY.md:54` 仍把这两条写作「待补」而非「已修」，并称
  「本层语义目前无 CI 可裁决脚本」——即 `net_contract_audit.py` /
  `disk_contract_audit.py` 至今**没有创建**。`ui_audit.py:37`（`LIB = ROOT / 'lib'`）
  与 `i18n_scan.py` 的 `collect(args.lib)` 倒是全库扫描，反衬 motion/perf 的局限是
  实现选择而非技术限制。
- **违反的原则编号/文档原话**：原则 **53**「审计脚本只守语法与结构；语义严密性靠人读，
  读的时候禁止只看 diff」（本条指出现有脚本连结构都没守全）、原则 **3**「例外必须显式登记、
  可枚举、**可归零**；没有清单的例外就是漏洞」、原则 **6**「命名即结构：文件名必须能让
  审计脚本识别其层级角色」、原则 **55**「死代码零容忍；…过时的白名单…都是给后人的假情报」。
  `AGENTS.md §2` 原话：「**layer_audit.py --fatal**：分层 import 检查…（**扫描 lib/ 全部
  相对 import**，违规退出 1，当前基线违规 0）」；`docs/ARCHITECTURE.md §8.2` 把
  `motion/perf_audit --fatal` 列进「提交前自检」并宣称「违规 0」，易被误读为全库检查。
- **P1** · **确证**（附证据）：本批 `file_read` 读 5 个门禁脚本全文（layer 106 行 /
  motion 109 / perf 195 / ui 193 / i18n_scan 328），行号如上；
  `ls -la tool/` 输出 21 个文件，无 `net_contract_audit.py` / `disk_contract_audit.py`，
  且 5 个审计脚本 mtime 均为 `Nov 7 00:54`（未随批2/批3 改动）；
  `docs/audit_b2_c.md:91-97`（B2-C-09）与 `docs/audit_b1_c.md` B1-C-12 同结论；
  `docs/CONSISTENCY.md:54` 逐字仍为「门禁盲区（待补）：`layer_audit.py` 不解析 `export`，
  `motion/perf_audit.py` 只扫 `lib/surface/`」。
- **备注**：`docs/CONSISTENCY.md` 至少**如实自认**盲区，这一点符合原则 58，不算二次违规；
  违规在于「两轮点名 + 文档自认待补」后仍未落地任何新门禁。

---
