# i18n 分片级精译任务书（子代理 + andrew-translate skill）

## 目标
按 andrew-translate skill 的核心纪律，把简体中文界面文案精译成目标语言，产出可直接接入应用的完整语言包。
禁止调用任何机翻接口（`i18n_translate.py`、B 站 Index-Translate 等一律不用），全部由你的语言能力精译。

## 第一步：读 skill（必做）
完整读取 `/var/minis/skills/andrew-translate/SKILL.md`，把其中以下纪律用于**分片级**翻译（不逐键跑完整三步式）：
- 术语一致性：同一术语全局统一，不逐句漂移
- 地区用语：按指定地区（见各任务）选词
- 三步式压缩：每个分片先在思考里形成初稿 → 反思（术语/占位符/语气）→ 写出精稿
- 文风：移动端 UI 文案，正式、克制、地道，不逐字硬译

## 源文与产出
- **源文**：`/root/OhGithubLost/assets/i18n/zh/<shard>.json`（简中，1272 键 / 28 分片）
- **产出**：`/root/OhGithubLost/.translate-work/i18n/<lang>/<shard>.json`
  - 必须写这个暂存目录，**绝对不要写 `assets/i18n/`**（那是主干，会破坏键集合门禁）
  - 每个分片的键集合、键顺序必须与 zh 完全一致；值为字符串
  - 2 空格缩进、`ensure_ascii=false`、末尾换行

## 硬约束（违反即返工）
1. **占位符逐字节保留**：`%@`、`%1$@`、`{name}`、`$1`、`\n`、`\t` 等，翻译后的值里必须与源文**完全一致**（多重集相同）。用 `tool/i18n_delta.py` 的 PH 规则自检。
2. **术语不译，保留原文**：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issue 号、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git。
3. **法律/声明正文必须真译文**：`onboarding.json` 里的 `onboardingLicenseBody`、`accelThirdPartyBody` 等长文本，逐句翻译，不得留英文占位，不得机翻腔。
4. **不得改动非 KEY 之外的结构**：只改 value，不动 key、不动顺序。
5. 不 commit、不 push。

## 质量自检（产出后必跑）
```
OGL_ROOT=/root/OhGithubLost/.translate-work/<lang>-root python3 tool/i18n_scan.py --check
```
若工具依赖目录结构，可改用逐分片 Python 自检：键集合/顺序与 zh 一致、值非空字符串、占位符多重集一致、无与 zh 同形的未翻译值（技术词保留项除外）。

## 地区用语
见各任务指定的地区（如 ja=日本、pt=巴西、es=西班牙本土）。同一语言内术语只用一种译法。

## 返回
报告：完成的分片数 / 总键数、自检结论、遗留问题（如某术语拿不准）。聊天回复 <200 字，明细写进指定的报告文件（如任务书所附）。
