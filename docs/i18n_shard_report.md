

## 日语 ja

- **任务**：简中 `assets/i18n/zh/` → 日语（日本地区用语，ja），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/ja/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，已校对术语一致并沿用）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Issues、Pull requests、Code、`workflow_dispatch` 等。
- 沿用既有 `repo_tags.json` 术语：标签/tag → **タグ**；全语言包统一（新建发布 `tagLabel`、repo.tags、settings 标签排序/每页标签数等均用「タグ」）。
- 关键统一用词：仓库→リポジトリ，提交→コミット，分支→ブランチ，议题→Issue，发布（Release）→リリース，附件→添付ファイル，构建产物→ビルド成果物，作业/工作→ジョブ，标签(issue)→ラベル，草稿→下書き，令牌→トークン，星标→スター，预发布→プレリリース（pre-release 保留原词），线程→スレッド，分支/tag 语境「ref」保留原词。
- Actions 语境 `job` 按日本开发者习惯译为「ジョブ」；`SHA-256`、`GET /user`、`repo:`、`language:`、`key=value`、`https://` 等技术字面量原样保留。
- 移动端 UI 文风：正式、克制、地道敬体（~します / ~してください），无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody`、`onboardingLicenseBody`（十七节全文，各约 2800 字）、`licenseHighlights`、`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseAuthoritative*` 等逐句译成自然日语法律说明文；保留 `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 等原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`tokenExitBody`、`fileTooLargeBodyPrivate` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表原样保留。

### 自检结论（逐分片 Python 校验，全部通过）
- 分片数：**28/28**；键数：**1272**。
- 键集合与键顺序：与 zh **完全一致**（逐分片按键序列比对）。
- 值类型：全部为**非空字符串**。
- 占位符多重集：`{name}`、`{count}`、`%@`、`%1$@`、`$1`、`\n`、`\t` 等占位符与 zh **逐字节一致**（正则多重集计数比对，0 处不符）；两轮独立校验（build_ja.py + verify_ja.py）均通过。
- 未译值：无与 zh 同形且含汉字的未翻译值；日中同形同义的正当日语词（保存/内容/通知/最大化 等）经白名单精确豁免，非未翻译。
- 结果：**problems = 0**，自检全部通过。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。少量术语取舍：中文「标签」在 Git tag / Gist / Release 场景为「タグ」，在 issue 筛选场景为「ラベル」；中文「发布」在 Release 场景为「リリース/公開」，在「发布评论」等动作场景为「投稿」，均按语境区分。字体名「思源宋体」采用其在日本通行的名称「Noto Serif CJK」。若产品侧另有术语表，可据此再对齐。
