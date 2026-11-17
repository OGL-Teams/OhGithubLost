# i18n 全语言接入 · 自主迭代状态（主会话维护）

> 用户指令（2026-11-17）：自行迭代，完成全部接入，分批进行，分多批，完成前不要通知，完成后发布版本。

## 目标
- 新语言：24 种暂存语言全量 28 分片精译并接入。
- 旧语言：现有 6 语言（zh/zh_Hant/en/de/fr/ru）全量润色。
- 全部完成后接线 → 门禁 → 发版 → 归档 → 一次性汇报。

## 语言清单
- 新接 24：ja ko es pt it nl pl tr ar hi th vi id ms uk cs sv da fi no hu ro he el
- 旧润色 6：zh（原文基准，不润色）/ zh_Hant / en / de / fr / ru
- 暂存目录：`.translate-work/i18n/<lang>/`，产出不得写 `assets/i18n/`（旧语言润色除外）。

## 纪律
- 子代理先读 `/var/minis/skills/andrew-translate/SKILL.md`，按分片级三步式（初稿→反思→精稿）。
- 禁机翻接口与 `tool/i18n_translate.py`。
- 占位符逐字节保留、术语保留原文、键集合/顺序与 zh 一致、2 空格缩进、ensure_ascii=false、末尾换行。
- 每子代理负责 1 语言 28 分片，最多 3 并发。
- 每轮只用 `subagent_task action=status` 查，不轮询；等待用 `minis-scheduled` 定时器（10 分钟）。

## 自检（每语言完成后）
逐分片：键集合/顺序 == zh；值非空字符串；占位符多重集 == zh；无与 zh 同形未译值（技术词除外）。
命令参考：`tool/i18n_scan.py --check`（接线后）、Python 逐分片脚本（接线前）。

## 进度
- [done] ja、ko、es、pt、it、nl、pl、tr、ar、th、hi、vi、id、ms、cs、uk、sv、da、fi、no、hu、he、ro 精译，zh_Hant 润色（全部自检 problems=0；zh_Hant 已在主干，i18n_scan 通过）
- [done] 24 语言全部精译完成并总闸验证 problems=0；zh_Hant 润色完成
- [进行中·3并发] de 润色（928d9c18）、fr 润色（6350169c）、ru 润色（d01bb4f5）
- [done] 接线 4 处完成，30 语言三处清单一致，十一门禁通过；提交 7c832df
- [done] 发版准备 commit 3251f77 已推，dispatch stable 13.0.2 已触发（HTTP 204）
- [进行中] 发布构建 + 归档（定时器 c790d791）
- en 为基线不润色

## 教训
- 子代理长任务易撞 provider 限流（503 / 6004 频率限制）：派发时明确「逐分片落盘」而非一次性读完再写。
- 失败 job 需重派，重派时收紧任务描述 + 指向自检工具。
- [待做] 接线 4 处：og_l_i18n.dart(locales+设备检测) / settings.dart(languageCodes) / pubspec.yaml(资源声明)；og_l_app.dart 自动从 locales 生成。
- [待做] 门禁：i18n_scan + 十一门禁 + gate_of_gates。
- [待做] 发布：dispatch build.yml stable；跟踪构建；确认 Release；归档 releases.json + generate_posts.py。

## 汇报纪律
全部归档完成前，不向用户发任何进度消息。完成后一次性汇报版本/语言/产物/归档统计。
