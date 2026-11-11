# 仓库整理报告（docs 文档域）· 2026-11

> 本次只审不改源码，仅创建/编辑文档；未移动、未删除任何文件（历史审计链接众多，移动会制造死链）。
> 基线：HEAD `5acb015`，版本 v12.5.2。

## 一、docs/ 文件总数与分类统计

共 **56** 个 `.md` 文件：

| 分类 | 数量 | 文件 |
|---|---|---|
| 长期规范 | 4 | QUALITY_STANDARD、CONSISTENCY、ARCHITECTURE、I18N |
| 设计与方案 | 5 | NETWORK、WEB_LITE_PLAN、USAGE、COLD_START、OAUTH_ORG_SETUP |
| 审计计划与索引 | 2 | AUDIT_PLAN、AUDIT_INDEX（本次新建） |
| 批审计（1–8 + 批 9） | 37 | audit_b1~b8 各 a/b/c（24）+ 各 cross（8）+ audit_spec_a/b/c + audit_spec_cross（4） |
| 批外专项 | 6 | audit_206、audit_submit_download、audit_ui、audit_net_data、audit_debug_empty_fail、5layer-audit-todo |
| 运维与杂项 | 3 | CI_BUILD_BASELINE、REPO_HYGIENE（本次新建）、fonts.md（字体 CDN 决策记录） |
| 目录索引 | 1 | README.md（本次重写为四类索引） |

**一次性审计报告（应归档保留，本次不移）**：上表「批审计」37 篇 + 「批外专项」6 篇 + fonts.md，共 44 篇，全部登记于 [`AUDIT_INDEX.md`](AUDIT_INDEX.md)（fonts.md 为决策记录，在 docs/README.md 归入审计/杂项）。
**长期规范（应显眼）**：QUALITY_STANDARD、CONSISTENCY、ARCHITECTURE、I18N、AGENTS.md（根目录）——已在 docs/README.md 与根 README「文档地图」置顶链接。

## 二、死链清单（实测）

实测命令（可复跑）：

```
python3 - <<'EOF'
import re, os, glob
pats = re.compile(r'(docs/[\w\-./]+\.md|lib/[\w\-./]+\.dart|tool/[\w\-./]+\.py)')
for f in sorted(glob.glob('docs/*.md')):
    for i, line in enumerate(open(f, encoding='utf-8'), 1):
        for m in pats.findall(line):
            if not os.path.exists(m):
                print(f, i, m)
EOF
```

**docs/ 内共 17 处死链**，全部为历史审计报告中对当时计划路径/文件名的引用（审计报告只审不改，不追溯修改）：

| 出处 | 死链 | 性质 |
|---|---|---|
| `5layer-audit-todo.md:45` | 日期占位符文档名（5layer-audit- 前缀） | 模板占位符，非真实引用 |
| `AUDIT_PLAN.md:16,35` | `audit_bN_…`（a 与 cross） | N 为变量写法 |
| `audit_b1_cross.md:81` | net 契约审计脚本（tool 下） | 建议中的脚本，未创建 |
| `audit_b2_b.md:519` | `gh_auth_service.dart`（gh 目录下） | 猜测文件名（实为 `gh_auth.dart`） |
| `audit_b2_cross.md:32` | disk 契约审计脚本（tool 下） | 建议中的脚本，未创建 |
| `audit_b4_c.md:180-181` | `DURABILITY.md`、`BOOT.md` | 引用当时计划文档，未创建 |
| `audit_b6_a.md:126` | `client_shell.dart`（猜测的 pages 路径） | 猜测路径（壳在 `lib/surface/app/`） |
| `audit_spec_a.md:15,41,70` | `any_page.dart`、`_re.dart`、`NAMING.md` | 示例路径 / 猜测文件名 / 未创建文档 |
| `audit_spec_c.md:100` | v12.5.x 占位版本文件（release_notes 与 changed/_content） | x 为版本占位符 |

另有 CHANGELOG.md 历史版本条目中的 13 处（旧版 web 构建脚本、WEB 手册、旧版 AI 审计脚本、桌面 shell 注入脚本、Android Gradle 注入脚本、旧代码查看组件、动效计划文档等）——均为已删除的旧版文件/工具的历史记录，**属正常历史，不改**（改写历史条目反而违背「记录当时事实」原则）。

**门禁联动注意**：`tool/contract_audit.py` 会扫描非 `audit_` 前缀的 docs 文件中对「`docs/` + 大写样式文件名」的引用并要求真实存在（见其 `check_doc_refs`）。因此**活文档**（README、索引、整理报告等）不得写出任何不存在的 docs 路径，即使只是举例或引用死链清单；本报告因此一律不带 `docs/` 前缀地转述上述死链。

## 三、发现的问题（本次审计结论）

- **重复/散落**：审计批次清单此前同时出现在 AUDIT_PLAN.md 与 docs/README.md，且 docs/README.md 只列到批 1/2——本次以 AUDIT_INDEX.md 为唯一总账，docs/README.md 只留入口。
- **命名**：`audit_spec_*.md`（批 9）与 `audit_b*_*.md`（批 1–8）前缀不一致，系历史事实，本次不改名（避免死链），在索引中注明对应关系。
- **编号断档**：无。批 1–8 齐全，批 9 以 `audit_spec_*` 命名；`audit_b8_cross.md` 曾缺失，已由主会话补写。
- **过期**：docs/README.md 原有「本目录仅收录持续有效的手册类文档，一次性规划落地后即移除」的约定与现状矛盾（44 篇一次性报告仍在），本次已修正该约定为「保留并索引」。
- **引用不存在的类名/事件码**：未发现（死链均为路径级，且多为审计猜测性引用，已在表中标明性质）。

## 四、建议归档但本次不移动的文件

为避免破坏历史互链，以下文件建议未来引入 `docs/archive/` 时一并做重定向页，本次**不移动**：

- `fonts.md`（v8.2.0 时代的字体决策，长期未更新）
- `audit_206.md`、`audit_debug_empty_fail.md`（对应问题已收口）
- `5layer-audit-todo.md`（五层审计遗留待办，若已全部消化可归档）

## 五、本次已整理

| 项 | 动作 |
|---|---|
| 新建 `docs/AUDIT_INDEX.md` | 九批 + 批外专项总索引，含汇总表、报告路径、状态、P0/P1 口径 |
| 重写 `docs/README.md` | 规范/设计/审计/运维四类索引；「59 条」口径保留并加粗；补 AUDIT_INDEX、CI_BUILD_BASELINE、AGENTS.md、REPO_HYGIENE 链接；修正与现状矛盾的「落地即移除」约定 |
| 补根 `README.md`「文档地图」 | 指向 docs/README、AGENTS、QUALITY_STANDARD、AUDIT_INDEX、CI_BUILD_BASELINE、release_notes/ |
| 补 `CHANGELOG.md` 12.5.3（未发布）条目 | 顶部新增，不动既有 12.5.x 条目 |
| 新建本报告 `docs/REPO_HYGIENE.md` | 死链实测、分类统计、归档建议 |

## 六、未整理及原因

| 项 | 原因 |
|---|---|
| `audit_spec_*` 未改名对齐 `audit_b9_*` | 改名会制造死链（audit_spec_cross.md 等多处互链）；由索引注明对应关系即可 |
| 17 处 docs/ 死链未修 | 全部位于历史审计报告内部（只审不改的原始记录），追溯改写违背「报告记录当时事实」原则 |
| CHANGELOG 历史条目 13 处死链 | 历史版本记录，改写即失真 |
| 无 `NAMING.md`、`DURABILITY.md`、`BOOT.md` 三份计划文档 | 为各报告引用时计划创建的文档，是否补写属内容决策，超出文档整理范围 |
| 44 篇一次性报告未移入 archive/ | 移动破坏历史链接；已全部纳入 AUDIT_INDEX 索引，达成「可检索」目标 |

## 七、面向未来的纪律

**新增任何审计报告（批审计或专项）落盘当天，必须同时在 `docs/AUDIT_INDEX.md` 登记**：范围、三份视角报告 + 交叉报告路径、状态。未登记的报告视为未完成交付。
