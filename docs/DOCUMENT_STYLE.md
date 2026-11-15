# 文档体系统一规范 / Documentation Style Guide

> **状态 / Status**：权威契约 / Normative contract  
> **生效 / Effective**：自 v12.6.10 起 / Since v12.6.10  
> **适用 / Scope**：本仓库全部 Markdown 文档 / All Markdown documents in this repository

本文件确立唯一的文档体例。各目录既有规范（如 `changed/_content/_STYLE.md`、
`release_notes/README.md`）不得与本文件冲突；冲突时以本文件为准。
This document establishes the single documentation convention. Directory-level
guides shall not conflict with it; where they do, this document prevails.

---

## 一、通用文风 / General Style

| 项 / Item | 规范 / Rule |
| --- | --- |
| 语体 / Register | 正式书面语；陈述事实，不作评价 / Formal written register; state facts, not opinions |
| 人称 / Person | 不使用「我们」「你」「大家」；使用被动或无人称 / No first- or second-person pronouns |
| 禁用 / Prohibited | 口语、营销语、感叹号、表情符号 / Colloquialisms, marketing tone, exclamation marks, emoji |
| 术语 / Terminology | 首次出现的中英并列；其后一致 / Introduce terms bilingually on first use, then keep consistent |
| 数字 / Figures | 不写死版本、文件数、测试数等量值；以工具实测为准 / No hard-coded versions or counts; derive from tooling |
| 引用 / References | 相对链接必须有效；禁止悬空路径 / Relative links must resolve; no dangling paths |

## 二、中英双语格式 / Bilingual Format

正式规范与发布说明采用**中英逐条对照**：中文在前，英文紧随，
以 ` / ` 分隔标题，段落之间不交替整篇译文。
Normative and release documents use **line-by-line bilingual presentation**:
Chinese first, English immediately after; section titles separated by ` / `.
Do not append a full translation as a separate block.

示例 / Example：

```
## 新增 / Added

- 新增离线缓存；网络中断时仍可查看最近内容。
  Added offline caching; recent content remains available when the network is unavailable.

## 修复 / Fixed

- 修复同名文件覆盖；下载时自动选择不冲突的文件名。
  Fixed same-name overwrite; downloads now select a non-conflicting file name.
```

## 三、目录职责 / Directory Responsibilities

## 三、目录职责 / Directory Responsibilities

**层级口径 / Layer terminology**：代码依赖门禁按四层 L0–L3
（kernel / base / domain / surface）计层，`lib/platform` 为独立平台门面层，
只依赖 kernel。`ARCHITECTURE.md` 的「五层」描述包含该门面层，两者并不矛盾；
引用时须写明所采口径，不得混用。
The dependency gate counts four layers L0–L3 (kernel / base / domain / surface);
`lib/platform` is a separate platform-facade layer depending only on kernel.
The "five layers" wording in `ARCHITECTURE.md` includes that facade. State which
convention is used; do not mix the two.

语言与格式按**读者**区分；同一目录内不得混用不同代际的体例。
Language and format follow the **audience**; a single directory shall not mix
conventions from different generations.

| 目录 / Directory | 读者 / Audience | 语言 / Language | 体例 / Format |
| --- | --- | --- | --- |
| `release_notes/v*.md` | 用户、Release 页 / Users, Release page | 中英逐条对照 / Bilingual | 固定小节 / Fixed sections |
| `CHANGELOG.md` | 贡献者 / Contributors | 中英对照要点 / Bilingual entries | 版本倒序 / Reverse-chronological |
| `changed/_content/v*.md` 与 `_posts/` | 网站读者 / Site readers | 中文书面语 / Formal Chinese | 面向使用者，见 `_STYLE.md` / User-facing, see `_STYLE.md` |
| `docs/*.md` | 贡献者、审阅者 / Contributors, reviewers | 中文为主；术语双语 / Chinese with bilingual terms | 分长期规范与一次性报告 / Normative vs. historical |
| `README.md` / `AGENTS.md` | 所有读者 / All readers | 中文为主；关键术语双语 / Chinese with bilingual key terms | 地图式，不写量值 / Index-style, no counts |

发布说明固定小节（无内容则整节删除）/ Fixed release-note sections
(omit an empty section entirely)：

`新增 / Added` → `改进 / Improved` → `修复 / Fixed` →
`变更 / Changed` → `已知限制 / Known limitations` → `产物 / Artifacts`。

## 四、历史分界 / Historical Boundary

v12.6.10 之前的文件保留原始体例，不追溯改写：一次性报告是当时的原始记录，
批量重写会失真并制造死链。撕裂指的是**同一目录内代际混用**，
由本文件划定分界后不再新增异体。
Files predating v12.6.10 retain their original style and shall not be rewritten
retrospectively: historical reports are contemporaneous records, and bulk
rewriting would distort them and break links. "Inconsistency" denotes
generation mixing **within one directory**; this document closes that boundary.

- `release_notes/README.md`：仅保留体例与自动化说明，删除过期的版本清单。
  Retain convention and automation notes only; remove the stale version table.
- `changed/_content/_STYLE.md`：与本文对齐，不另立冲突条款。
  Align with this document; introduce no conflicting rules.
- `docs/REPO_HYGIENE.md` 等历史整理报告：保留原表，以「现状勘误」标注当前口径。
  Historical hygiene reports keep their tables and mark current figures via an erratum.

## 五、维护纪律 / Maintenance Discipline

1. 新增文档先判定所属目录，再套用对应体例 / Classify the directory before writing.
2. 规范类文档的修改须中英双语、正式、成对 / Changes to normative documents shall be bilingual, formal, and paired.
3. 发布说明正文与线上 Release 正文必须一致 / Release-note files and published Release bodies must match.
4. 新增审计/审查报告须登记于 `docs/AUDIT_INDEX.md` / Register new reports in `docs/AUDIT_INDEX.md`.
5. 每次整理后实测死链与全量门禁 / Verify dead links and run all gates after each cleanup.
