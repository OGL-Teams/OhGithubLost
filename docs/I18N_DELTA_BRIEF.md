# i18n 增量翻译任务书（andrew-translate 子代理）


> **更新时间 / Last Updated**：2026-11-16 05:56:53　**对应版本 / Version**：v14.0.0
## 目标
对 `assets/i18n/zh/` 的 28 个分片，把**新增或改动的键**翻译到分派的语言集合。
默认双语（zh_Hant / en）只在重要版本扩展到 30 语言。

## 你会收到（任务书注入）
- `LANGS`：本次负责的语言代码列表（8 种/代理）- `DELTA`：一个 JSON 文件路径，结构 `{"delta": {"<shard>": ["key1",...]},
  "source": {"<shard>": {"key1": "<中文原文>"}}}`。
  **翻译必须以 `source` 里的源值快照为准**（不是翻译时刻工作区的中文值——
  源文若在途中被改，各批会对同一键给出不同译文）。
  `delta` 为空 → 直接结束。

## 产出落点（重要，勿写错）
- 目标目录：`.translate-work/i18n/<lang>/<shard>.json`（**暂存区**，已被 .gitignore 排除）。
- **不要写进 `assets/i18n/`**：主干只维护 zh / zh_Hant / en（默认双语）。多语言在
  「重要版本」才整体合入；缺分片的语言目录进主干会破坏 `tool/i18n_scan.py --check`
  的「键集合以 zh 全量为基准」校验。
- 若目标语言在 `assets/i18n/` 下没有该分片：用仓库自带 `tool/i18n_translate.py`
  生成机翻基线到暂存区（仅作占位），再对 DELTA 键做精翻覆写。

## 硬性输出契约
1. 只改 `assets/i18n/<lang>/<shard>.json` 的 **DELTA 列出的键**；其余键一字不动。
2. 占位符 `{name}`、`%s`、`{{var}}`、URL、Markdown 结构原样保留（可校验：占位符多重集必须与中文源一致）。
3. 值必须是字符串；JSON 用 `ensure_ascii=False, indent=2` + 尾换行写回。
4. 每个分片写完立即落盘（失败只影响该分片，可续跑）。

## 翻译风格（andrew-translate 三步式）
- 内部完成初稿 → 四维反思（准确性/流畅性/风格/术语一致）→ 精稿，**只交付精稿**。
- 文体：正式、简洁、严谨的移动端 UI 文案。不口语化、不玩梗、不解释性长句。
- **术语表（全语言统一）**：
  - 标签 → Tag（动词用「创建/删除」，语言内用当地惯用词）
  - 提交 → commit；仓库 → repository；工作流 → workflow
  - 本应用名 OhGithubLost 保留原文；GitHub / Gist / DoH / SHA / APK 等技术词保留原文
  - zh_Hant 用台湾用语：軟體/網路/設定/標籤；不用大陆词直转
- **格式保护**：三引号外的 JSON 键、`\n`、前后空格数量保持。

## 禁止
- 不得 commit / push（只改工作区文件）
- 不得改动 DELTA 之外的键
- 不得重排 JSON 键顺序（保持原文件键序，新增键追加尾部）
- 不得为了"完整"翻译未列入 DELTA 的键

## 验收自检（交付前逐条过）
- [ ] 本批 LANGS × DELTA 涉及分片的键全部处理
- [ ] 抽 3 分片 diff：只有 DELTA 键变化
- [ ] `python3 tool/i18n_scan.py --check` 通过（键集合一致、值类型字符串）
- [ ] 增量校验通过：`python3 tool/i18n_delta.py check`（缺键 / 占位符多重集 / 未翻译 三重校验）

## 返回格式
聊天回报 ≤ 200 字：处理的键数、失败分片（如有）、门禁结果。明细写
`docs/i18n_delta_report.md`（该文件若不存在则新建；只写你本批的语言）。
