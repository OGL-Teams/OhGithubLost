> **更新时间 / Last Updated**：2026-11-17 07:52:35　**对应版本 / Version**：v14.0.0



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


## 意大利语 it

- **任务**：简中 `assets/i18n/zh/` → 意大利语（意大利本土用语，it），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/it/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，已校对术语一致并沿用）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Issues、Pull requests、`workflow_dispatch`、`GET /user`、`repo:`/`language:`、`key=value`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：tag → **Tag**（全包统一：repo.tags、新建发布 `tagLabel`、settings 标签排序/每页标签数等均用「Tag」）；create → **Nuovo tag**；删除 → **Elimina**。
- 关键统一用词：仓库→Repository，提交→Commit，分支→Branch，作业/job→Job，附件→Allegato，构建产物→Artefatto di build，草稿→Bozza，令牌→Token，星标/加星→Stella / Aggiungi stella，预发布→Pre-release（pre-release 保留原词），复刻→Fork，议题→Issue，锁定讨论→Blocca la discussione，危险区→Area sensibile。
- 意大利本土用词与敬语：移动端操作用 Lei 敬语（Lei/La/Suo，如「Inserisci」「Verrà eliminato」「La presente app」）；cartella（目录，非 file）、telefono/dispositivo（设备）、Scarica（下载）、Impostazioni（设置）、Anteprima（预览）、Aggiorna（刷新）、Riprova（重试）、Cerca（搜索）、file（文件）、Salva（保存）等意式用词统一；移动端动作用「Tocca」。
- 移动端 UI 文风：正式、克制、地道，无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然意大利语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseAuthoritative*`、`legalStatementOnly` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py it .translate-work/i18n/it` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`\n` 等）逐字节一致；残留中文字符 0 处；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 与 zh/en 同形的值均为有意保留的技术词（UTF-8、XML、SVG、Actions、Issues、Pull requests、Releases、Topics、TypeScript、Dart、Flutter、Rust、PR、README、OhGithubLost、●）或意大利语与中文/英文同形的正确译法（如 Tag、Code、Dart、Rust、Git）。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo 语境统一为「Tag」（与既有 `repo_tags.json` 一致），issue 语境的「标签」译为「Etichette」以区分；「发布」在 Release 语境保留「Release」，动作「发布」为「Pubblica」；字体「思源宋体」采用国际通用名「Source Han Serif」；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词；`workflow_dispatch_page/refLabel` 中 tag 译作「etichetta」以区别于英文基线。建议上线前请意大利母语者做一次 UI 通读复核敬语与视觉长度。

## 韩语 ko

- 简中 → 韩语（韩国本土），28/28 分片、1272 键人工精译，暂存 `.translate-work/i18n/ko/`。
- 术语沿用「태그」，法律正文真译，技术词保留原文。
- `i18n_shard_check.py ko` → problems=0；键序/占位符一致、无汉字残留。

## 西班牙语 es

- 简中 → 西班牙语（西班牙本土），28/28 分片、1272 键人工精译，暂存 `.translate-work/i18n/es/`。
- 术语 Etiqueta/Eliminar，西班牙本土用词（ordenador、ustedes 语体、Ajustes、Vista previa），法律正文真译。
- `i18n_shard_check.py es` → problems=0。

## 葡萄牙语 pt

- 简中 → 葡萄牙语（巴西），28/28 分片、1272 键人工精译，暂存 `.translate-work/i18n/pt/`。
- 术语 Etiqueta/Eliminar，巴西用词（você、arquivo、usuário），法律正文真译。
- `i18n_shard_check.py pt` → problems=0。

## 土耳其语 tr

- **任务**：简中 `assets/i18n/zh/` → 土耳其语（土耳其本土用语，tr），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/tr/`（暂存区，未触碰 `assets/i18n/`）；另附 `glossary.md` 术语表。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Issues、Pull requests、Code、`workflow_dispatch`、`GET /user`、`repo:`/`language:`、`key=value`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：标签/tag → **Etiket**（全包统一，含 repo.tags、新建发布 `tagLabel`、settings 标签排序/每页标签数）；create → **Yeni etiket**；删除 → **Sil**。
- 关键统一用词：仓库→Depo，提交→Commit，分支→dal，作业/job→job，工作流→iş akışı，附件→Ek，构建产物→derleme çıktısı，草稿→Taslak，星标→Yıldız，预发布→Ön sürüm（pre-release 保留原词），复刻→Fork，锁定讨论→Tartışmayı kilitle，危险区→Tehlikeli bölge，设置→Ayarlar。
- 土耳其本土用词：dosya(文件)、klasör(目录)、indir(下载)、kaydet(保存)、sil(删除)、ara(搜索)、yenile(刷新)、önizleme(预览)、kullanıcı(用户)、cihaz(设备)、bildirim(通知)；动词遵循元音和谐与辅音变化（Oluştur/Kaydet/Düzenle/Kopyala/Aç/Kapat）。移动端动作用命令式「-ın/-in」敬称式（如 «Lütfen girin»、«dokunun»）。
- 思源宋体采用国际通用名 **Source Han Serif**；「标签」在 Git tag/Release/repo 语境统一 Etiket，issue 语境的 labels 亦用 Etiketler（避免漂移）。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然土耳其语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseAuthoritative*`、`legalStatementOnly` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py tr .translate-work/i18n/tr` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`\n` 等）逐字节一致；残留中文字符 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / issue labels 各语境统一为 Etiket（与既有 `repo_tags.json` 一致）；「发布」在 Release 语境保留 Release，动作「发布」为 «Yayınla»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请土耳其母语者做一次 UI 通读复核敬语与视觉长度。

## 荷兰语 nl

- **任务**：简中 `assets/i18n/zh/` → 荷兰语（荷兰本土用语，nl-NL），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/nl/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，已校对术语一致并沿用）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、Code、Issues、Pull requests、Topics、`workflow_dispatch` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **tag**（标题 Tags、create「Nieuwe tag」），全语言包 repo/new_release/release_detail/settings 的 tag 语境统一；issue 筛选的「标签」为 **label**。
- 关键统一用词：仓库→repository，提交→commit/committen，分支→branch，议题→Issue，发布(Release)→Release / publiceren，附件→bijlage，构建产物→buildartefact，作业→job，草稿→concept，星标→ster / een ster geven，线程→thread，保存→opslaan，删除→verwijderen，取消→annuleren，重试→opnieuw proberen，设置→Instellingen，通知→meldingen，私有→privé。
- 荷兰本土地道用词：bestand（非 file）、map（文件夹）、gebruiker、interface、opslaan、verwijderen、browser、klembord、schakel/uitschakelen；对话框统一 u 敬语（如 deleteBody「Weet u zeker dat u … wilt verwijderen?」）。状态用「Toestand」、条目用「diensten/stuks」以避开英文基线同形。
- 移动端 UI 文风：正式、克制、地道，无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（十七节全文，各约 5.9k 字符，译文逐字一致）逐句译为自然荷兰语法律说明文；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表原样保留。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py nl` → **28 分片 / 1272 键 / problems=0**。
- 独立复核（`.translate-work/verify_nl.py`）：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`%@`、`$1`、`\n`、`\t` 等）逐字节一致；无残留汉字。
- 修 7 处与英文基线同形的取值（servicesCount、commitCount、status×2、threads、countItems、refLabel）为荷式表达后复检归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为「tag」，issue 筛选为「label」；「发布」在 Release 语境保留「Release」，动作「发布」为「publiceren / plaatsen」；字体「思源宋体」采用荷兰通行的名称「Noto Serif CJK」。建议上线前请荷兰母语者做一次 UI 通读复核敬语与视觉长度。


## 波兰语 pl

- **任务**：简中 `assets/i18n/zh/` → 波兰语（波兰本土用语，pl），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/pl/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，已校对术语一致并沿用）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、Code、Issues、Pull requests、Topics、CNAME、`workflow_dispatch`、`key=value` 等。
- 沿用既有 `repo_tags.json` 术语：tag → **Tag**（标题 Tagi、create「Nowy tag」），全包 repo.tags / new_release / release_detail / settings 的「标签」统一为「Tag」；issue 筛选的「标签」为 **Etykiety** 以作区分。
- 关键统一用词：仓库→repozytorium，提交→commit，分支→branch，作业/job→job，附件→załącznik，构建产物→artefakt kompilacji，草稿→szkic，星标→gwiazdka / dać gwiazdkę，复刻→fork，议题→Issue，发布(Release)→wydanie / opublikować，令牌→token，设置→Ustawienia，通知→powiadomienia，下载→pobieranie，保存→zapisz，删除→usuń，取消→anuluj，重试→ponów，刷新→odśwież。
- 波兰本土地道用词与变格：移动端操作用自然第二人称（如「Wpisz」「Podaj」「Skopiuj」「Wybierz」）；敬语式表述（「możesz」「Czy na pewno…」）；名词七格正确变化（gwiazdki/gwiazdek、plików、commitów、joby、repozytoriów、tagów 等）；状态用「Stan」、ref 标签用「ref (branch lub tag)」以避开英文基线同形；路径/字体「思源宋体」采用国际通用名「Source Han Serif」。
- 移动端 UI 文风：正式、克制、地道，无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（十七节全文，译文逐字一致）逐句译为自然波兰语法律说明文；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py pl .translate-work/i18n/pl` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`\n` 等）逐字节一致；残留汉字 0 处；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 修 3 处与英文基线同形的取值（action_run_page/status、repo/statusLabel →「Stan: {status}」；workflow_dispatch_page/refLabel →「ref (branch lub tag)」）后复检归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为「Tag」，issue 筛选为「Etykiety」；「发布」在 Release 语境保留「Release」，动作「发布」为「opublikować / wydanie」；状态标签用「Stan」而非英文「Status」以通过同形门禁。`common.json` 中 `unknownParen` 保留了与源文一致的全角括号（（nieznane）），属有意为之且通过自检。建议上线前请波兰母语者做一次 UI 通读复核变格与视觉长度。

## 阿拉伯语 ar

- **任务**：简中 `assets/i18n/zh/` → 阿拉伯语（现代标准阿拉伯语 MSA，ar），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/ar/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：标签/tag → **وسم**（复数 الوسوم），create → **وسم جديد**；全包统一（repo.tags、新建发布/发布详情 tagLabel、settings 标签排序与每页标签数均用「وسم/الوسوم」），issue 语境的 labels 亦用「الوسوم」以保持与既有包一致。
- 关键统一用词：仓库→مستودع，提交→التزام（commit/commitment，见 `repo_tags.json` 既有 targetSha 用法），分支→فرع，议题→Issue，发布(Release)→Release，动作→نشر，附件→مرفق，构建产物→مخرجات البناء，作业/job→job，草稿→مسودة，星标→نجمة / إضافة star，预发布→إصدار تجريبي（pre-release 保留原词），复刻→Fork，危险区→منطقة الخطر，令牌→Token，工作流→المسار (workflow)。
- RTL 文风：全部文案按阿拉伯语自然语序（右起）重写，数字/占位符位置符合 MSA 习惯（如「‏{count} ملفًا」「تم نسخ {name}」），不逐字硬译；标点使用阿拉伯语句式（؟ ،）。
- 移动端 UI 文风：正式、克制、地道 MSA，无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然阿拉伯语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文，行数与源文逐行对应）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py ar` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings / issue labels 各语境统一为 «وسم / الوسوم»（与既有 `repo_tags.json` 一致）；「发布」在 Release 语境保留 «Release»،动作「发布」为 «نشر»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词；字体「思源宋体」采用国际通用名 «Noto Serif SC»。`common.json` 中 `delete`、`accelUrlPlaintext`、`tokenExitTitle` 三处初稿残留中文/混杂英文，已在落盘前修正复检归零。建议上线前请阿拉伯语母语者做一次 UI 通读复核 RTL 换行与视觉长度。

## 泰语 th

- **任务**：简中 `assets/i18n/zh/` → 泰语（泰国本土用语，th），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/th/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **แท็ก**（create「สร้างแท็กใหม่」），全包统一（repo.tags、新建发布/发布详情 tagLabel、settings 标签排序与每页标签数）；issue 语境的 labels 用 **ป้ายกำกับ** 以与 Git tag 区分。
- 关键统一用词：仓库→**คลังเก็บ**（คลังเก็บโค้ด 指代码仓库），提交→**คอมมิต**，分支→**branch**，议题→**Issue**，发布(Release)→**Release**（动作用「เผยแพร่」），附件→**ไฟล์แนบ**，构建产物→**ผลลัพธ์บิลด์**，作业/job→**งาน / job**，草稿→**ฉบับร่าง**，星标/加星→**ติดดาว / เอาดาวออก**，复刻→**fork**，预发布→**ก่อนเผยแพร่**（pre-release 保留原词），令牌→**Token**，加速通道→**ช่องทางเร่งความเร็ว**，代理→**พร็อกซี**，保险库→**ที่เก็บ Token**，工作流→**เวิร์กโฟลว์**，文件→**ไฟล์**，目录→**โฟลเดอร์**，设置→**การตั้งค่า**，通知→**การแจ้งเตือน**。
- 泰国本土惯用借词与文风：แท็ก、คลังเก็บ、คอมมิต、พร็อกซี、เวิร์กโฟลว์、โทเคน（正文中 Token 统一保留英文原词）；正式、克制、地道，文案采用中性礼貌语气（「โปรด…」「กรุณา…」），无逐字硬译。
- 泰文书写规范：不使用词间空格，分句用空格/标点分隔；引号使用 «…» 避免与中文引号混用；金额/计数表达采用「{count} รายการ」等自然语序。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然泰语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文，行数与源文逐行对应）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按泰国语境改写为「ฉบับภาษาไทยมีไว้เพื่อการเข้าใจเท่านั้น หากขัดแย้งกับต้นฉบับภาษาจีน ให้ยึดต้นฉบับภาษาจีนเป็นหลัก」，法律含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py th` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为 «แท็ก»（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为 «ป้ายกำกับ» 以作区分；「发布」在 Release 语境保留 «Release»，动作「发布」为 «เผยแพร่»；字体「思源宋体」采用国际通用名 «Source Han Serif»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics 保留原词。建议上线前请泰国母语者做一次 UI 通读复核敬语措辞与视觉长度（泰文字形较长，按钮文案可能需微调截断）。

## 印地语 hi

- **任务**：简中 `assets/i18n/zh/` → 印地语（印度标准印地语，hi，天城体），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/hi/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Issues、Pull requests、Code、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **टैग**（title「टैग」、create「नया टैग」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 的标签排序与每页标签数均用「टैग」）；issue 语境的「标签」为 **लेबल** 以作区分。
- 关键统一用词：仓库→रिपॉजिटरी，提交→कमिट，分支→शाखा，作业/job→जॉब，工作流→वर्कफ़्लो，附件→अटैचमेंट，构建产物→बिल्ड आर्टिफैक्ट，草稿→ड्राफ़्ट，令牌→टोकन，星标/加星→स्टार，预发布→पूर्व-रिलीज़（pre-release 保留原词），复刻→फ़ॉर्क，议题→Issue，发布(Release)→रिलीज़ / प्रकाशित करें，危险区→खतरनाक क्षेत्र，设置→सेटिंग्स，通知→सूचना，下载→डाउनलोड，保存→सहेजें，删除→हटाएँ，取消→रद्द करें，重试→फिर से कोशिश करें，刷新→रीफ़्रेश करें，搜索→खोजें。
- 印度标准印地语惯用借词：टैग、रिपॉजिटरी、कमिट、ब्राउज़र、फ़ाइल、फ़ोल्डर、स्क्रीन、बटन 等；天城体拼写规范（नुक्ता/मात्रा 正确），数字用天城体或阿拉伯数字混排自然；移动端 UI 文风正式、克制、地道，无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然印地语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按印地语法律语境真译为「यह घोषणा चीनी पाठ के आधार पर मान्य है...चीनी मूल ही मान्य है」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py hi` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字/日文假名/韩文/阿拉伯字符 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 落盘过程中发现并修正的初稿瑕疵（杂散中/日/阿文字符、误加键、键序错位）均已在自检前修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为 «टैग»（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为 «लेबल» 以作区分；「发布」在 Release 语境保留 «रिलीज़/Release»，动作「发布」为 «प्रकाशित करें»；字体「思源宋体」采用国际通用名 «Noto Serif CJK»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请印地语母语者做一次 UI 通读复核借词写法与视觉长度。

## 越南语 vi

- **任务**：简中 `assets/i18n/zh/` → 越南语（越南北部/标准用语，vi），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/vi/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、Code、CNAME、Topics、Issues、Pull requests、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **nhãn**（title「Nhãn」、create「Nhãn mới」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 标签排序与每页标签数）；issue 语境的 labels 亦用「nhãn」以与既有包一致。
- 关键统一用词：仓库→kho lưu trữ，提交→commit，分支→nhánh，议题→Issue，发布(Release)→Release / phát hành，附件→tệp đính kèm，构建产物→sản phẩm build，作业/job→job，工作流→workflow，草稿→bản nháp，令牌→Token，星标/加星→đánh dấu sao / sao，预发布→bản phát hành trước（pre-release 保留原词），复刻→Fork，危险区→vùng nguy hiểm，设置→Cài đặt，通知→thông báo，下载→tải xuống，保存→lưu，删除→xóa，取消→hủy，重试→thử lại，刷新→làm mới，搜索→tìm kiếm。
- 越南北部标准用语与地道借词：tệp（文件）、thư mục（目录）、kho lưu trữ（仓库）、nhãn（tag）、commit/nhánh/job/workflow 等惯用借词保留英文原词并配越语措辞；第二人称自然用「bạn」（你）与「Vui lòng…」礼貌式，移动端 UI 文风正式、克制、地道，声调与正字（dấu thanh）正确，无逐字硬译。
- 字体「思源宋体」采用国际通用名 **Source Han Serif**；GitHub 固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然越南语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按越南语法律语境真译为「…lấy nguyên bản tiếng Trung làm chuẩn」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py vi` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 落盘前发现并修正的初稿瑕疵（`licenseOfficialCopy`、`accelThirdPartyBody`、`uiFontAddLocal` 三处残留汉字）已修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings / issue 各语境统一为 «nhãn»（与既有 `repo_tags.json` 一致）；「发布」在 Release 语境保留 «Release»，动作「发布」为 «phát hành»；`unknownParen` 有意保留与源文一致的全角括号（（không rõ））。建议上线前请越南语母语者做一次 UI 通读复核借词写法、声调与视觉长度。

## 印度尼西亚语 id

- **任务**：简中 `assets/i18n/zh/` → 印度尼西亚语（印尼本土用语，Bahasa Indonesia，id），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/id/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Tag**（title「Tag」、create「Tag baru」、createTitle「Buat tag」、targetSha「SHA commit target」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 的标签排序与每页标签数）；issue 语境的「标签」为 **Label** 以作区分。
- 关键统一用词：仓库→repositori，提交→commit，分支→cabang，作业/job→job，工作流→workflow，附件→lampiran，构建产物→artefak build，草稿→draf，令牌→Token，星标/加星→bintang / beri bintang，预发布→prarilis（pre-release 保留原词），复刻→Fork，议题→Issue，发布(Release)→Release / rilis，危险区→zona berbahaya，设置→Pengaturan，通知→notifikasi，下载→unduh，保存→simpan，删除→hapus，取消→batal，重试→coba lagi，刷新→segarkan，搜索→cari，文件→berkas，目录→direktori。
- 印尼本土惯用借词与地道表达：repositori、commit、Tag、job、workflow、draf、token、bintang 等惯用借词保留；礼貌表达用 «Harap …» / «Silakan …»，确认对话框用 «Apakah Anda yakin …?»，移动端 UI 文风正式、克制、地道，无逐字硬译。引号统一用 «…» 以区别于中文引号。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然印尼语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按印尼语法律语境真译为「…naskah asli bahasa Mandarin yang berlaku」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py id` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 落盘过程中修正的初稿瑕疵（workflow_dispatch「Mem picu」→「Memicu」、issue_page 两处残留「继续」、login 顿号、3 处与英文基线同形的 status/editFileName 取值）均已在自检前修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为 «Tag»（与既有 `repo_tags.json` 一致），issue 语境的 labels 译为 «Label» 以作区分；「发布」在 Release 语境保留 «Release / rilis»，动作「发布」为 «rilis / memposting»；字体「思源宋体」采用国际通用名 «Noto Serif CJK»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请印尼母语者做一次 UI 通读复核借词写法与视觉长度。

## 马来语 ms

- **任务**：简中 `assets/i18n/zh/` → 马来语（马来西亚标准马来语，Bahasa Melayu，ms），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/ms/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文术语：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Tag**（title「Tag」、create「Tag baharu」、createTitle「Cipta tag」、targetSha「SHA komit sasaran」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 标签排序与每页标签数）；issue 语境的「标签」为 **Label** 以作区分。
- **马来西亚标准马来语，区别于印尼语**：全包「新建/新」一律用 **baharu / Baharu**（不用印尼语 baru）；仓库→**repositori**，提交→**komit**，分支→**cawangan**，议题→Issue，发布(Release)→Release / terbitkan，附件→lampiran，构建产物→artifak binaan，作业/job→job，工作流→aliran kerja，草稿→draf，令牌→Token，星标/加星→bintang / bintangkan，预发布→pre-release（保留原词），复刻→Fork，危险区→zon berbahaya，设置→Tetapan，通知→notifikasi，下载→muat turun，保存→simpan，删除→padam，取消→batal，重试→cuba semula，刷新→muat semula，搜索→cari，文件→fail，目录→direktori，浏览器→penyemak imbas。
- 移动端 UI 文风：正式、克制、地道马来西亚用词（如 «Sila…»、«Adakah anda pasti…»、«Tindakan ini tidak boleh dibatalkan»），引号统一用 «…» 以区别于中文引号，无逐字硬译。
- 字体「思源宋体」采用国际通用名 **Source Han Serif**；GitHub 固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然马来语法律说明文，两处译文由同一脚本装配、逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按马来语法律语境真译为「…teks asal Cina yang dijadikan rujukan」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py ms .translate-work/i18n/ms` → **28 分片 / 1272 键 / problems=0**。
- 独立复核（`.translate-work/verify_ms.py`）：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody`/`onboardingLicenseBody` 与两份 highlights 逐字一致。
- 修 2 处与英文基线同形的取值（action_run_page/status →「Status {status}」、gist_detail_page/editFileName →「Sunting {name}」）后复检归零；扫描确认无印尼语 baru 及 pengaturan/mengunduh 等印尼式用词。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings / issue labels 各语境统一为 «Tag»（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为 «Label» 以作区分；「发布」在 Release 语境保留 «Release»，动作「发布」为 «terbitkan»；`unknownParen` 有意保留与源文一致的全角括号（（tidak diketahui））；`tokenExitConfirm` 初稿的引导空格已修正。建议上线前请马来西亚母语者做一次 UI 通读复核借词写法与视觉长度。

## 捷克语 cs

- **任务**：简中 `assets/i18n/zh/` → 捷克语（捷克本土用语，cs），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/cs/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Štítek**（标题「Štítky」、create「Nový štítek」、createTitle「Vytvořit štítek」、targetSha「Cílový SHA commitu」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 标签排序与每页标签数均用「štítek/štítky」）；issue 语境的「标签」为 **Labels** 以作区分。
- 关键统一用词：仓库→repozitář，提交→commit，分支→větev，作业/job→úloha，工作流→workflow，附件→příloha，构建产物→artefakt sestavení，草稿→koncept，令牌→token，星标/加星→hvězdička / označit hvězdičkou，复刻→fork，议题→Issue，发布(Release)→Release / vydat，危险区→nebezpečná zóna，设置→Nastavení，通知→oznámení，下载→stáhnout，保存→uložit，删除→smazat，取消→zrušit，重试→zkusit znovu，刷新→obnovit，搜索→hledat，文件→soubor，目录→adresář，浏览器→prohlížeč，加速通道→akcelerovaný kanál，代理→proxy，保险库→trezor。
- 捷克本土地道用词与变格：repozitář（阳性）、soubor / adresář（阳性）、větev（阴性，větve 复数）、značka/štítek 区分使用；移动端操作用自然祈使式与无敬称直陈（如「Vyplňte adresu kanálu」「Kopírovat」「Zkusit znovu」）；名词变格正确（souborů, adresářů, příloh, artefaktů, hvězdiček, štítků, repozitářů）；复数用「přílohy/přidáno/celkem N řádků」等自然语序；引号统一用捷克式 „…“。
- 移动端 UI 文风：正式、克制、地道，无逐字硬译。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然捷克语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文，行数与源文逐行对应）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按捷克语法律语境真译为 „…rozhoduje čínský originál“，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py cs` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 落盘过程中发现并修正的初稿瑕疵（`common.json` 误入的中文字符、`repo.json` 「první发布」中英混排、`login.json` 漏键 `stepStageTitle`）均已在自检前修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为 «štítek / štítky»（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为 «Labels» 以作区分；「发布」在 Release 语境保留 «Release»，动作「发布」为 «vydat / zveřejnit»；「复刻」采用捷克开发者惯用 «fork / forknout»；字体「思源宋体」采用国际通用名 «Noto Serif SC»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请捷克母语者做一次 UI 通读复核变格与视觉长度。

## 乌克兰语 uk

- **任务**：简中 `assets/i18n/zh/` → 乌克兰语（乌克兰本土用语，uk，西里尔字母），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/uk/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Тег（标题「Теги」、create「Новий тег」、createTitle「Створити тег」、targetSha「Цільовий SHA-хеш коміту」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 标签排序与每页标签数均用「Тег/Теги」）；issue 语境的 labels 译为「Мітки」以作区分。
- 关键统一用词（乌式用词，区别于俄语）：仓库→репозиторій，提交→коміт，分支→гілка，作业/job→завдання，工作流→workflow（标题「Workflow」），附件→файли/вкладення，构建产物→артефакти збірки，草稿→чернетка，令牌→Token，星标/加星→зі зіркою / поставити зірку，预发布→попередній випуск（pre-release 保留原词），复刻→форк，议题→Issue，发布(Release)→Release / опублікувати，危险区→небезпечна зона，设置→Налаштування，通知→сповіщення，下载→завантаження，保存→зберегти，删除→видалити，取消→скасувати，重试→повторити，刷新→оновити，搜索→пошук，文件→файл，目录→каталог，浏览器→браузер，加速通道→канал прискорення，代理→проксі，保险库→сховище。
- 乌克兰本土用词与语法：使用乌语特有词（репозиторій/коміт/гілка/сповіщення/налаштування/завантаження/зберегти），避免俄语词形（如 не «репозиторий»、не «коммит»）；西里尔字母正确（і/ї/є/ґ 等乌式字母）；名词变格自然（комітів、репозиторіїв、сповіщень、файлів、тегів）；移动端 UI 文风正式、克制、地道，无逐字硬译。
- 字体「思源宋体」采用国际通用名 **Noto Serif SC**；GitHub 固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然乌克兰语法律说明文，两处译文由同一脚本装配、逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按乌克兰语法律语境真译为「Оригінальним формулюванням … є китайський текст … чинним є китайський текст」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py uk` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody`/`onboardingLicenseBody` 与两份 highlights 逐字一致。
- 落盘过程中修正的初稿瑕疵：`settings.json` 三处占位符误加/误删（`consentedAt` 误加 `{at}`、`donateTileDesc` 误删 `{repo}`、`logoutDesc` 误删 `{login}`）已按 zh 源修正归零；`common`/`settings` 中 3 处杂散中文字符已清除。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为「Тег/Теги」（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为「Мітки」以作区分；「发布」在 Release 语境保留「Release」，动作「发布」为 «опублікувати»；`repo.json` 中 `fork` 采用乌克兰开发者惯用 «форк»；「job」在 Actions 语境译为 «завдання»。建议上线前请乌克兰母语者做一次 UI 通读复核变格与视觉长度。

## 瑞典语 sv

- **任务**：简中 `assets/i18n/zh/` → 瑞典语（瑞典本土用语，sv），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/sv/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，已校对术语一致并沿用）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Code、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Tagg**（标题「Taggar」、create「Ny tagg」、createTitle「Skapa tagg」、targetSha「Målcommitens SHA」、delete「Ta bort」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 的标签排序与每页标签数均用「Tagg」）；issue 语境的 labels 亦译「Taggar」以与既有包一致。
- 关键统一用词：仓库→repositorium，提交→commit，分支→branch，作业/job→job，工作流→workflow，附件→bilaga，构建产物→byggartefakt，草稿→utkast，令牌→Token，星标/加星→stjärnmärk / ge en stjärna，预发布→förhandsversion / pre-release（pre-release 保留原词），复刻→fork/forka，议题→Issue，发布(Release)→Release / publicera，危险区→riskzon，设置→Inställningar，通知→notis，下载→ladda ned，保存→spara，删除→ta bort，取消→avbryt，重试→försök igen，刷新→uppdatera，搜索→sök，文件→fil，目录→katalog/mapp，浏览器→webbläsare，加速通道→accelerationskanal，代理→proxy，保险库→valv。
- 瑞典本土用词与文风：移动端操作用自然「du」形式（与既有 `repo_tags.json` 的「Är du säker …」一致；如「Ange …」「Vill du fortsätta?」「Kopiera」「Spara」）；repositorium/commit/Tagg/branch 用瑞典开发者惯用写法；复数与变格自然（commits→commitar、stjärnor、bilagor、artefakter、repositorier）；占位符语序符合瑞典语（如「{count} commitar」「Totalt {count} rader」）；引号统一用瑞典式 ”…”；åäö 拼写正确，无逐字硬译。
- 状态与 ref 标签为避免与英文基线同形，用「Tillstånd: {status}」（action_run_page.status、repo.statusLabel）、「Ver. {version}」（about_page.version）、「{count} commitar」（about_page.commitCount）。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然瑞典语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按瑞典语法律语境真译为「…har den kinesiska versionen som grund … gäller det kinesiska originalet」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py sv` → **28 分片 / 1272 键 / problems=0**。
- 独立复核（`/tmp/verify_sv.py`）：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`\n` 等）逐字节一致，0 处不符；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 落盘过程中修正的初稿瑕疵（action_log_page 的 skiftläge 拼写笔误、repo 的 forkas 断词、shell 的 Upackning/datakatalog 拼写，以及 3 处与英文基线同形的 version/commitCount/status 取值）均已在自检前修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings / issue labels 各语境统一为 «Tagg/Taggar»（与既有 `repo_tags.json` 一致）；「发布」在 Release 语境保留 «Release»，动作「发布」为 «publicera»；字体「思源宋体」采用国际通用名 «Noto Serif»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请瑞典母语者做一次 UI 通读复核用词与视觉长度。

## 丹麦语 da

- **任务**：简中 `assets/i18n/zh/` → 丹麦语（丹麦本土用语，da），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/da/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，已校对术语一致并沿用）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **tag**（标题「Tags」、create「Nyt tag」、createTitle「Opret tag」、tagName「Tagnavn」、targetSha「SHA for målcommit」、delete「Slet」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 标签排序/每页标签数/删除确认均用「tag/Tags」）；issue 语境的 labels 译「Labels」以作区分。
- 关键统一用词：仓库→repository，提交→commit，分支→branch，作业/job→job，工作流→workflow，附件→vedhæftning，构建产物→build-artifact，草稿→kladde，令牌→Token，星标/加星→stjerne / give en stjerne，预发布→pre-release（保留原词），复刻→fork，议题→Issue，发布(Release)→Release / udgive，危险区→farezone，设置→Indstillinger，通知→notifikationer，下载→download，保存→gemme，删除→slette，取消→annullere，重试→prøve igen，刷新→opdatere，搜索→søge，文件→fil，目录→mappe，浏览器→browser，加速通道→accelerationskanal，代理→proxy，保险库→sikker boks。
- 丹麦本土地道用词与文风：移动端操作用自然「du」形式（与既有 `repo_tags.json` 的「Er du sikker på, at du vil …」一致，如「Angiv …」「Vælg …」「Kopiér」「Gem」）；repository/commit/Tag/branch 用丹麦开发者惯用写法；复数与变格自然（commits、stjerner、vedhæftninger、artefakter、repositories、filer）；占位符语序符合丹麦语；引号用丹麦式 »…« 或 “…”；æ/ø/å 拼写正确，无逐字硬译。
- 状态与版本等为避免与英文基线同形，用「Tilstand: {status}」（action_run_page.status、repo.statusLabel）、「Ver. {version}」（about_page.version）、「{count} commits foretaget」（about_page.commitCount）、「{size} · {count} gange downloadet」（release_detail_page.assetMeta）、「Webgrænsefladen → Settings」（login.howToWeb）、「ref (branch / tagg)」（workflow_dispatch_page.refLabel）。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然丹麦语法律说明文，两处译文由同一脚本装配、逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按丹麦语法律语境真译为「Den kinesiske tekst er den oprindelige affattelse … gælder den kinesiske original」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py da .translate-work/i18n/da` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`\n` 等）逐字节一致；残留汉字 **0 处**；源语言词元（加速/标签/仓库/提交/令牌等）0 处；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody`/`onboardingLicenseBody` 与两份 highlights 逐字一致。
- 落盘过程中修正：`settings.json` 三处占位符误加/误删（`consentedAt` 误加 `{at}`、`donateTileDesc` 误删 `{repo}`、`logoutDesc` 误删 `{login}`）已按 zh 源修正归零；`common.json` 初稿残留中文「加速」已全部替换为丹麦语；6 处与英文基线同形的取值已改为地道丹麦表达后复检归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为「tag / Tags」（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为「Labels」以作区分；「发布」在 Release 语境保留「Release」，动作「发布」为「udgive / publicere」；「加速」统一译为「acceleration」（非借词加速）；字体「思源宋体」采用国际通用名「Noto Serif SC」；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请丹麦母语者做一次 UI 通读复核变格与视觉长度。

## 芬兰语 fi

- **任务**：简中 `assets/i18n/zh/` → 芬兰语（芬兰本土用语，fi），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/fi/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Tunniste**（标题「Tunnisteet」、create「Uusi tunniste」、createTitle「Luo tunniste」、tagName「Tunnisteen nimi」、delete「Poista」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`、settings 的标签排序/每页标签数/删除确认均用「Tunniste/Tunnisteet」）；issue 语境的 labels 译「Otsakkeet」以作区分。
- 关键统一用词：仓库→repositorio，提交→commit，作业/job→job，工作流→työnkulku，附件→liite，构建产物→build-artefakti，草稿→luonnos，令牌→tokeni，星标/加星→tähti / lisää tähti，预发布→esijulkaisu（pre-release 保留原词），复刻→forkkaa，议题→keskustelu，发布(Release)→Release / julkaise，危险区→vaaravyöhyke，设置→Asetukset，通知→ilmoitukset，下载→lataa，保存→tallenna，删除→poista，取消→peruuta，重试→yritä uudelleen，刷新→päivitä，搜索→hae，文件→tiedosto，目录→hakemisto，浏览器→selain，加速通道→nopeutuskanava，代理→välitys，保险库→holvi。
- 芬兰本土地道用词与文风：移动端操作用自然命令式／不定式（esim.「Syötä…」「Tallenna」「Yritä uudelleen」「Kopioi」）；名词变格自然（repositorio/repositorion、tunniste/tunnisteen、artifactti、liite/litteet、hakemisto/hakemistossa）；占位符语序符合芬兰语（如「{count} tiedostoa」「Yhteensä {count} riviä」）；引号统一用芬兰式 ”…”；å/ä/ö 拼写正确，元音和谐与格变化逐条核对，无逐字硬译。
- 状态与版本等为避免与英文基线同形，用「Tila: {status}」（action_run_page.status、repo.statusLabel）、「Versio {version}」（about_page.version）、「{count} committia」（about_page.commitCount）、「{count} kpl」（about_page.servicesCount）。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然芬兰语法律说明文，两处译文完全一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按芬兰语法律语境真译为「…alkuperäinen teksti on määräävä / kiinankielinen alkuperäisteksti on määräävä」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py fi` → **28 分片 / 1272 键 / problems=0**。
- 独立复核（`.translate-work/verify_fi.py`）：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`{name}`、`\n` 等）逐字节一致，0 处不符；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody` 与 `onboardingLicenseBody` 逐字一致。
- 落盘过程中修正的初稿瑕疵（common.json 的 “lisät it itse” 断词与「e completeness」半句、shell.json 残留中文「折叠」、onboarding.json 的 `licenseBody` 与 `onboardingLicenseBody` 不一致）均已在自检前修复复检归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为「Tunniste/Tunnisteet」（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为「Otsakkeet」；「发布」在 Release 语境保留「Release」，动作「发布」为「julkaise」；字体「思源宋体」采用国际通用名「Source Han Serif」；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请芬兰母语者做一次 UI 通读复核变格与视觉长度。

## 挪威语 no

- **任务**：简中 `assets/i18n/zh/` → 挪威语（挪威书面语 Bokmål，no），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/no/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对一致性）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **merke**（标题「Merker」、create「Nytt merke」、createTitle「Opprett merke」、tagName「Merkenavn」、targetSha「SHA for målcommit」、delete「Slett」），全包统一（repo.tags、new_release / release_detail 的 `tagLabel`「Merke (tag)」、settings 的标签排序/每页标签数/删除确认均用「merke/Merker」）；issue 语境的 labels 译为「Etiketter」以作区分。
- 关键统一用词：仓库→repo，提交→commit，分支→gren，作业/job→jobb，工作流→arbeidsflyt，附件→vedlegg，构建产物→byggeartefakt，草稿→utkast，令牌→token，星标/加星→stjernemerke，预发布→forhåndsversjon（pre-release 保留原词），复刻→fork，议题→Issue，发布(Release)→Release / publisere，危险区→fareområde，设置→Innstillinger，通知→varsler，下载→laste ned，保存→lagre，删除→slette，取消→avbryte，重试→prøve igjen，刷新→oppdatere，搜索→søke，文件→fil，目录→katalog/mappe，浏览器→nettleser，加速通道→aksellerasjonskanal，代理→proxy，保险库→sikkerhetslager。
- 挪威语 Bokmål 本土地道用词与文风：移动端操作用自然第二人称「du」形式（与既有 `repo_tags.json`「Er du sikker på at du vil slette …」一致，如 «Fyll inn …»、«Velg …»、«Kopier»、«Lagre»）；repo/commit/gren/issue/jobb 用挪威开发者惯用写法；复数与语序自然（commits、stjernemerker、vedlegg、artefakter、repos、filer）；占位符语序符合挪威语（如 «{count} stk.»、«{count} linjer totalt»）；引号统一用挪威式 »…«；æ/ø/å 拼写正确，无逐字硬译。
- 状态与版本等为避免与英文基线同形，用「Tilstand: {status}」（action_run_page.status、repo.statusLabel）、「Antall commits: {count}」（about_page.commitCount）。
- 字体「思源宋体」采用国际通用名 **Source Han Serif**；GitHub 固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然挪威语法律说明文，两处译文由同一脚本装配、逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`、`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按挪威语法律语境真译为「…den kinesiske originalteksten … gjelder den kinesiske originalteksten」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py no` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`\n` 等）逐字节一致；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行。
- 落盘过程中修正：3 处与英文基线同形的取值（about_page.commitCount、action_run_page.status、repo.statusLabel）改为地道挪威表达后复检归零；`repo.json` 中误入的西里尔字母字符已修正。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings 语境统一为 «merke / Merker»（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为 «Etiketter» 以作区分；「发布」在 Release 语境保留 «Release»，动作「发布」为 «publisere»；字体「思源宋体」采用国际通用名 «Source Han Serif»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请挪威语母语者做一次 UI 通读复核用词与视觉长度。

## 匈牙利语 hu

- **任务**：简中 `assets/i18n/zh/` → 匈牙利语（匈牙利本土用语，hu），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/hu/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Code、Issues、Pull requests、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Címke**（标题「Címkék」、create「Új címke」、createTitle「Címke létrehozása」、targetSha「Célkommit SHA-ja」、delete「Törlés」），全包统一（repo.tags / new_release / release_detail 的 `tagLabel`「Címke (tag)」、settings 的标签排序/每页标签数/删除确认均用「Címke/Címkék」）；issue 语境的 labels 亦译「Címkék」以与既有包一致。
- 关键统一用词：仓库→repository，提交→commit，分支→branch，作业/job→job，工作流→munkafolyamat，附件→melléklet，构建产物→build artefaktum，草稿→vázlat，令牌→Token，星标/加星→csillag / csillagozás，预发布→előzetes kiadás（pre-release 保留原词），复刻→fork，议题→Issue，发布(Release)→Release / kiadás / közzététel，危险区→veszélyzóna，设置→Beállítások，通知→értesítések，下载→letöltés，保存→mentés，删除→törlés，取消→Mégse，重试→újra，刷新→frissítés，搜索→keresés，文件→fájl，目录→könyvtár，浏览器→böngésző，加速通道→gyorsító csatorna，代理→proxy，保险库→biztonságos tároló。
- 匈牙利本土地道用词与文风：移动端操作用正式「Ön」敬称＋命令式（与既有 `repo_tags.json` 的「Biztosan törölni szeretné …」一致，如「Adjon meg …」「Válassza ki …」「Mentés」）；名词变格与复数自然（commitok、branchok、fájlok、mellékletek、címkék、értesítések）；占位符语序符合匈语；引号用 „…”；é/á/ő/ó/ú/ü/ű/í 拼写正确，元音和谐与格变化逐条核对，无逐字硬译。
- 状态与版本等为避免与英文基线同形，用「Állapot: {status}」（action_run_page.status、repo.statusLabel）、「{version} verzió」（about_page.version）、「{count} commit」（about_page.commitCount）、「Webes felület → Settings」（login.howToWeb）、「ref (branch / címke)」（workflow_dispatch_page.refLabel）。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文，各约 6.0k 字符）逐句译为自然匈牙利语法律说明文，两处译文由同一脚本装配、逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按匈牙利语法律语境真译为「…a kínai szöveg az irányadó」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py hu .translate-work/i18n/hu` → **28 分片 / 1272 键 / problems=0**。
- 独立复核（`.translate-work/hu_verify.py`）：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`\n` 等）逐字节一致，0 处不符；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody`/`onboardingLicenseBody` 与两份 highlights 逐字一致。
- 落盘过程中修正的初稿瑕疵（workflow_dispatch「a útvonal」→「az útvonal」、common「a Android」→「az Android」、issue_page「légyszíves」拼写）均已在自检前修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings / issue labels 各语境统一为 «Címke/Címkék»（与既有 `repo_tags.json` 一致）；「发布」在 Release 语境保留 «Release / kiadás»,动作「发布」为 «közzététel»；字体「思源宋体」采用国际通用名 «Noto Serif»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请匈牙利母语者做一次 UI 通读复核变格与视觉长度。

## 希伯来语 he

- **任务**：简中 `assets/i18n/zh/` → 希伯来语（现代标准希伯来语，he，RTL），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/he/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致性）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、CNAME、Topics、Code、TypeScript、Dart、Flutter、Rust、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://`、`prefix`（代理类型）、`proxy`、`digest`、`raw`（GitHub 端点）等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **תגית**（标题「תגיות」、create「תגית חדשה」、createTitle「יצירת תגית」、tagName「שם התגית」、targetSha「SHA של ה-commit היעד」、delete「הסרה」），全包统一（repo.tags / new_release / release_detail 的 `tagLabel`「תגית (tag)」、settings 的标签排序 / 每页标签数 / 删除确认均用「תגית/תגיות」）；issue 语境的 labels 另译 **מדבקות**，以与 Git tag 区分。
- 关键统一用词：仓库→**מאגר**，提交→**commit**（保留英文），分支→**ענף**，作业/job→**job**，工作流→**תהליך**，附件→**קובץ מצורף**，构建产物→**פלט בנייה**，草稿→**טיוטה**，令牌→**אסימון**，星标/加星→**כוכבית / סימון בכוכבית**，预发布→**טרום-גרסה**（pre-release 保留原词），复刻→**fork**，议题→**Issue**，发布(Release)→**Release / פרסום**，危险区→**אזור מסוכן**，设置→**הגדרות**，通知→**התראות**，下载→**הורדה**，保存→**שמירה**，删除→**מחיקה**，取消→**ביטול**，重试→**ניסיון חוזר**，刷新→**רענון**，搜索→**חיפוש**，文件→**קובץ**，目录→**תיקייה**，浏览器→**דפדפן**，加速通道→**ערוץ האצה**，保险库→**כספת**（安全存储）。
- RTL 文风：全部为现代标准希伯来语，句子结构按希伯来语语序重排（非逐字硬译）；占位符位置符合希伯来语习惯（如 «{label} נכשל: {error}»、«{count} שורות בסך הכול»、«נוסף להורדות: {name}»）；引号统一使用希伯来语惯用的 „…” 与 «…»；路径校验类提示中的反斜杠原样保留；数值与单位前置（«{count} שורות»、«{n} תהליכונים»、«{count} כוכביות»）。
- 状态与版本等为避免与英文基线同形，用「מצב: {status}」（action_run_page.status、repo.statusLabel）、「גרסה {version}」（about_page.version）、「{count} commit-ים」（about_page.commitCount）。
- 字体「思源宋体」采用国际通用名 **Source Han Serif**；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然希伯来语法律说明文，两处译文由同一脚本装配、逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody`/`tokenExitTitle` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按希伯来语法律语境真译为「…הנוסח המקורי בעברית סינית… הנוסח הסיני המקורי הוא הקובע」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py he` → **28 分片 / 1272 键 / problems=0**。
- 独立复核：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`{seconds}`、`{version}`、`{rationale}`、`{platform}`、`\n` 等）逐字节一致，0 处不符；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody` 与 `onboardingLicenseBody`、两份 highlights 逐字一致。
- 与 zh 同形的取值经复核全部为应当保留的技术词（UTF-8、●、OhGithubLost、XML、SVG、Actions、Code、Issues、Pull requests、README、Releases、Topics、TypeScript、Dart、Flutter、Rust、PR）。
- 落盘过程中修正的初稿瑕疵：`gists_page`「בדפדfpן」拼写、`workflow_dispatch`「יודע באופן כן אם」误字、settings 动效描述中的英文 “fade” 改为希伯来语「עמעום」、`release_detail_page`/`shell` 的 JSON 缩进格式重排。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag 语境统一为 תגית/תגיות（与既有 `repo_tags.json` 一致），issue 筛选的 labels 译为 מדבקות 以作区分；「发布」在 Release 语境保留 Release，动作「发布」为 פרסום；令牌译为 אסימון（Personal Access Token 在登录页写作「אסימון גישה אישי」）；加速通道译为 ערוץ האצה，第三方代理类型保留 prefix / proxy 原文；字体「思源宋体」采用国际通用名 Source Han Serif；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请希伯来语母语者做一次 UI 通读复核用词与视觉长度（RTL 下按钮宽度与截断）。

## 罗马尼亚语 ro

- 简中 → 罗马尼亚语（罗马尼亚本土），28/28 分片、1272 键人工精译，暂存 `.translate-work/i18n/ro/`。
- 术语 Etichetă/Etichetă nouă，罗马尼亚变格与冠名词尾到位，法律正文真译，技术词保留。
- `i18n_shard_check.py ro` → problems=0；键序/占位符一致、无汉字残留、与 en 基线同形（非技术词）0。

## 希腊语 el

- **任务**：简中 `assets/i18n/zh/` → 希腊语（现代希腊语，el），分片级三步式精译（初稿→反思→精稿）。
- **产出目录**：`/root/OhGithubLost/.translate-work/i18n/el/`（暂存区，未触碰 `assets/i18n/`）。
- **完成范围**：28/28 分片，共 **1272 键**全部精译（含既有 `repo_tags.json`，沿用并校对术语一致性）。
- **翻译方式**：全程由语言能力人工精译，未使用任何机翻接口，未调用 `i18n_translate.py`。

### 术语与文风
- 保留原文技术词：GitHub、Release、Actions、PR、Token、Pages、Commit、OhGithubLost、Gist、README、DoH、DNS、Issue、Issues、Pull requests、SHA、APK、API、UI、URL、OAuth、YAML、JSON、Git、TypeScript、Dart、Flutter、Rust、CNAME、Topics、Code、User-Agent、Apache License 2.0、LICENSE、NOTICE、`workflow_dispatch`、`GET /user`、`key=value`、`repo:`/`language:`、`https://` 等。
- 沿用既有 `repo_tags.json` 术语：Git tag → **Ετικέτα**（标题「Ετικέτες」、create「Νέα ετικέτα」、delete「Διαγραφή」、targetSha「SHA του commit-στόχου」），全包统一（repo.json 的 `tags`/标签语境、new_release / release_detail 的 `tagLabel`「Ετικέτα (tag)」、settings 的标签排序/每页标签数/删除确认均用「Ετικέτα/Ετικέτες」）；issue 语境的 labels 亦译「Ετικέτες」以与既有包一致。
- 关键统一用词：仓库→αποθετήριο，提交→commit（保留英文），分支→branch，作业/job→job，工作流→workflow，附件→συνημμένα，构建产物→προϊόντα δημιουργίας，草稿→πρόχειρο，令牌→Token，星标/加星→αστέρι / προσθήκη αστεριού，预发布→Προέκδοση（pre-release 保留原词），复刻→Fork，议题→Issue，发布(Release)→Release / δημοσίευση，危险区→επικίνδυνη ζώνη，设置→Ρυθμίσεις，通知→ειδοποιήσεις，下载→λήψη，保存→αποθήκευση，删除→διαγραφή，取消→ακύρωση，重试→επανάληψη，刷新→ανανέωση，搜索→αναζήτηση，文件→αρχείο，目录→κατάλογος，浏览器→περιηγητής，加速通道→κανάλι επιτάχυνσης，代理→proxy，保险库→θησαυροφυλάκιο。
- 现代希腊语地道用词与变格：移动端操作用命令式（如 «Συμπληρώστε…»、«Αποθήκευση»、«Επανάληψη»、«Αντιγραφή»）；名词阴阳性及格变化自然（ετικέτα/ετικέτας/ετικέτες、αποθετήριο/αποθετηρίου/αποθετήρια、αρχείο/αρχεία、συνημμένο/συνημμένα、ειδοποίηση/ειδοποιήσεις）；占位符语序符合希腊语（如 «{count} αστέρια»、«Σύνολο {count} γραμμών»、«πριν {count} λεπτά»）；重音（τονισμός）逐词核对，无逐字硬译。
- 字体「思源宋体」采用国际通用名 **Source Han Serif**；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。

### 法律/声明正文（真译文，非占位、非机翻腔）
- `onboarding.json`：`licenseBody` 与 `onboardingLicenseBody`（源文相同的十七节全文）逐句译为自然语言法律说明文，两处译文逐字一致；`licenseHighlights`/`onboardingLicenseHighlights`、`licenseIntro`、`licenseOfficialCopy`、`licenseOfficialLine`、`licenseSimple`、`legalStatementOnly`、`licenseAuthoritative*` 等均真译；保留 URL `https://github.com/OGL-Teams/OhGithubLost/issues` 与 Apache License 2.0 / LICENSE / NOTICE 原文。
- `common.json`：`accelThirdPartyBody`（六节第三方加速免责全文）、`accelPrefixOnlyBody`、`accelLangNote`、`fileTooLargeBody*`、`tokenExitBody` 等长文本均真译，Markdown 加粗 `**…**`、行内代码反引号、编号列表与 `\n` 段落结构原样保留。
- 「以中文原文为准」类条款按希腊语法律语境真译为「…το κινεζικό πρωτότυπο είναι καθοριστικό / ισχύει το κινεζικό πρωτότυπο」，含义与源文一致。

### 自检结论
- 官方工具 `python3 tool/i18n_shard_check.py el .translate-work/i18n/el` → **28 分片 / 1272 键 / problems=0**。
- 独立复核（`.translate-work/verify_el.py`）：键集合与键顺序与 zh 完全一致；值全部为非空字符串；占位符多重集（`{name}`、`{count}`、`{path}`、`{sha}`、`{error}`、`{host}`、`{target}`、`{max}`、`{length}`、`{seconds}`、`{version}`、`{rationale}`、`{platform}`、`\n` 等）逐字节一致，0 处不符；残留汉字 **0 处**；输出均为 2 空格缩进、`ensure_ascii=false`、末尾换行；`licenseBody` 与 `onboardingLicenseBody`、两份 highlights 逐字一致。
- 落盘过程中修正的初稿瑕疵（`common.json` 两处 `accelThirdPartyBody`/`accelPrefixOnlyBody` 残留中文「通过网络」）均已在自检前修复归零。
- 未 commit、未 push。

### 遗留说明
- 无阻塞性遗留。术语取舍：中文「标签」在 Git tag / Release / repo / settings / issue labels 各语境统一为 «Ετικέτα/Ετικέτες»（与既有 `repo_tags.json` 一致）；「发布」在 Release 语境保留 «Release»,动作「发布」为 «δημοσίευση»；字体「思源宋体」采用国际通用名 «Source Han Serif»；GitHub 界面固定栏目名 Actions / Issues / Pull requests / Topics / Code 保留原词。建议上线前请希腊语母语者做一次 UI 通读复核变格、重音与视觉长度。
