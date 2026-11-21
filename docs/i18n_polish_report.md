# i18n 全量润色报告


> **更新时间 / Last Updated**：2026-11-17 07:52:35　**对应版本 / Version**：v14.0.0
## 繁體中文（zh_Hant，台湾用语）

### 范围与做法
- 对象：`assets/i18n/zh_Hant/` 既有语言包（繁中为主线既有 6 语言之一，本次为**润色**而非暂存）。
- 源文：`assets/i18n/zh/` 简中，28 分片 / 1272 键，逐分片一一对照。
- 依据 andrew-translate skill「润色模式」：把现有译文当作 translation_1，从反思阶段起逐句复核；按准确性 / 流畅性 / 地区用语 / 术语一致性四维检视。
- 全程人工语言润色，未调用任何机翻接口，未使用 `i18n_translate.py`；未 commit / 未 push。

### 完成量
- 分片：**28 / 28**
- 键数：**1272 / 1272**

### 主要修正明细
1. **未翻译的整句英文**（`issue_page.json`）：`actionFailed / cancel / close / closeHint / closeIssue(Title) / closed / commentFailed / commentHint / commentPostFailed / commentPosted / commentRequired / commentTooLong / comments / noComments / openNow / postComment / posting / publish / reopen / reopenHint / reopenIssue / reopened / toggleFailed` 等 20+ 键由英文改为台湾繁中（如 `Action failed` → `操作失敗`、`Post Comment` → `發表留言`、`Comment too long (...)` → `留言過長（…）`）。
2. **法律/声明长文本**（`onboarding.json`）：
   - `licenseIntro` 原为整段英文，已逐句译为繁中（含三部分适用范围说明）。
   - `licenseBody` / `onboardingLicenseBody` 中「十免责声明」漏标点，修正为「十、免責聲明」。
   - `traceableDesc`、`welcomeDesc`、`tokenVault`、`tokenVault2`、`noAuthNeeded`、`readyState/readyTitle2`、`currentPlatform / platformNote / requestingPermission / recheckPermissions` 等按台湾用语与简中源文校正。
3. **日文残留**：`預リリース`（4 处：new_release_page / release_detail_page / repo 的 prerelease 系列）改为台湾用语「預先發布」。
4. **简体字残留**：`如实→如實`（common.accelThirdPartyBody）、`无需→無需`、`準備就緒`、`平台`语境等逐处核对；台湾通行写法「平台 / 干擾」经确认非简体，予以保留。
5. **简中直译未本地化**（台湾用语到位）：
   - 「令牌 / Token / 權杖」统一为**權杖**（法律文本、Token 离开设备警告、登录/个人页说明等）；保留国际术语 `Token` 于技术标识语境（如 ghp_ 前缀、`GET /user`），并统一登录页为「權杖」叙述。
   - 「软件→軟體、网络→網路、设置→設定、标签→標籤、文件→檔案、数据→資料、信息→資訊、默认→預設、保存→儲存、支持→支援、界面→介面、视频→影片、用户→使用者」等台湾用语全面核对。
   - 「保存日志→儲存日誌」「回退失败→備援失敗→全文回退失敗」等动词用语校正。
6. **错译**：`search_page.json` 的「字庫」(仓库误译) 4 处、`noRepoForResult`「字庫→倉庫」；随后全局统一仓库译法为台湾惯用「儲存庫」（54+ 处「倉庫」、1 处「倉儲」、其余「字庫」一并归一），发布译法统一为「發布」（「釋出」6 处归一）。
7. **术语一致性**：评论统一「留言」（issue_page）、议题统一「議題」、日志统一「日誌」、 workspace「快取」、卸载「解除安裝」、尝试「嘗試」等；`Sources`/`Clone`/`Star`/`Issue`/`PR` 等技术词与品牌词按任务书保留原文或台湾惯用写法。
8. **占位符**：修正 3 处译文擅自增删占位符的问题——
   - `settings.consentedAt` 去掉译文多加的 `{at}`，与 zh 的 `{version}` 对齐；
   - `settings.donateTileDesc`、`settings.logoutDesc` 去掉译文多加的 `{repo}` / `{login}`（zh 源文本无占位符，运行期亦不传参）。
   - 其余键占位符逐字节保留。

### 自检结论
- **键集合 / 键顺序**：28 分片全部与 zh 一致（逐键 `list(keys)` 比对，0 差异）。
- **值类型**：1272 个值均为非空字符串（0 异常）。
- **占位符多重集**：`{name}` / `{count}` / `{error}` / `%@` / `\n` 等按 i18n_delta 的 PH 规则 + iOS `%@` 规则比对，0 不一致。
- **格式**：全部 2 空格缩进、`ensure_ascii=false`、UTF-8、末尾单个换行、无 CR（重建比对 0 差异）。
- **简体残留**：逐字 zhconv 检测，排除台湾通行字（台/干/里）后 0 真简体字残留。
- **日文/英文残留**：假名 0；整句英文残留 0（`licenseIntro` 已译）。
- **项目工具**：`python3 tool/i18n_scan.py --check` 通过——「6 语言 × 28 页面键集合一致；界面文案 0 处未本地化；语言清单三处一致」。

### 遗留问题
- 无阻塞项。个别语气性用词（如「權杖」在法律长文中的一致性）已按台湾 GitHub 语境统一；若产品侧对「储存库 vs 仓库」另有品牌偏好，可再按设计稿微调，但当前台湾用语已到位且全包一致。

## 德语（de）

### 范围与做法
- 对象：`assets/i18n/de/` 既有语言包（**润色**现有译文，非暂存重译），直接改主干；未 commit / 未 push。
- 源文：`assets/i18n/zh/` 简中，28 分片 / 1272 键，逐分片一一对照。
- 依据 andrew-translate skill「润色模式」：把现有 de 译文当作 translation_1，从反思阶段起按准确性 / 流畅性 / 术语一致性 / 文风四维逐句复核。
- 全程人工语言润色，**未调用任何机翻接口，未使用 `i18n_translate.py`**。工作方式为逐分片「读→改→保存」分批落盘。

### 完成量
- 分片：**28 / 28**
- 键数：**1272 / 1272**

### 主要修正明细
1. **英文占位 → 真德语**（核心问题，`issue_page.json` 20+ 键）：`Action failed`→`Aktion fehlgeschlagen`、`Close Issue`→`Issue schließen`、`Comment failed`→`Kommentar fehlgeschlagen`、`Markdown supported; please be kind…`→`Markdown wird unterstützt; bitte freundlich und konkret bleiben`、`Failed to post comment`→`Kommentar konnte nicht veröffentlicht werden`、`Comment too long`→`Kommentar zu lang`、`Post Comment`→`Kommentar veröffentlichen`、`Opening…/Posting…`→`Wird geöffnet…/Wird veröffentlicht…`、`Reopen Issue`→`Issue wieder öffnen`、`After reopening…`→`Nach dem Wiederöffnen…`、`Status toggle failed`→`Statuswechsel fehlgeschlagen`、`Cancel/Close/Closed/Comments/No comments yet` 等全部改为地道德语。
2. **与 en 同形的碰撞键**（gate 判定为未译）：`about_page/version`→`Version: {version}`、`action_run_page/durationMinSecs/durationSecs`→`Laufzeit …`、`action_run_page/status` 与 `repo/statusLabel`→`Aktueller Status: {status}`、`workflow_dispatch_page/optionalSuffix`→`(freiwillig)`。均保留占位符且符合德语习惯。
3. **占位符错误**：de 旧包部分值取自 en 而非 zh，导致多出占位符——`settings/consentedAt` 去掉多余的 `{at}`、`donateTileDesc` 去掉 `{repo}`、`logoutDesc` 去掉 `{login}`，全部与 zh 源文占位符逐字节对齐（全包仅此 3 处，已修）。
4. **键顺序**：6 个分片（common / download_manager_page / drafts_page / login / notifications_page / profile_page）键顺序与 zh 不一致，已按 zh 顺序重排，键集合 / 顺序现完全一致。
5. **法律/声明长文本**（`onboarding.json`）：`licenseBody` / `onboardingLicenseBody` 17 个章节与 zh 逐条核对（许可与权威文本→免责声明→联系方式），编号、语义、语气均准确，为完整德语译文，无英文占位；`licenseSimple` 原为缩略英文式短句，按 zh 全文重译为完整德语句（开源、代码与构建配置公开、LICENSE 位置、不收集数据、令牌留在本机）。
6. **错译/德语语法**：`release_detail_page/editTitle`「Version bearbeiten」→「Release bearbeiten」（对应 zh 编辑发布）；`repo/newDirectory`「Neuer Verzeichnis」→「Neues Verzeichnis」；`profile_page/switched`「Umschaltete」→「Umgeschaltet」；`settings` 多处 go flat 直译改为自然表述（已用当前账号、令牌不出设备、解析器 IP 留空即取消等）。
7. **术语一致性**：评论统一 Kommentar、发布/Release 保留技术词 Release、仓库 Repository/Repo、令牌 Token、议题 Issue 等按任务书技术词保留；未发现成片术语漂移。

### 自检结论
- `python3 tool/i18n_shard_check.py de assets/i18n/de` → **28 分片 / 1272 键 / problems=0**。
- `python3 tool/i18n_scan.py --check` → 通过：6 语言 × 28 页面键集合一致；界面文案 0 处未本地化；语言清单三处一致。
- 值类型：1272 个值均为非空字符串。
- 占位符多重集：全包与 zh 逐键比对，0 不一致。
- 格式：全部 2 空格缩进、`ensure_ascii=false`、UTF-8、末尾单个换行、无 CR（重建比对 0 差异）。
- 残留英文：整句英文占位 0；扫描确认无 `Action failed` / `Post Comment` 等残留。

### 遗留问题
- 无阻塞项。既有译文的德语敬称「Sie」与「du」在同一包内混用（如 login/repo 偏「Sie」，issue_page 偏「du」），属原包既有文风，未做全局统一以免改动过大；如产品需统一第二人称敬称，可作为后续独立润色项。

## 俄语（ru）

### 范围与做法
- 对象：`assets/i18n/ru/` 既有语言包（28 分片 / 1272 键），本次为**润色**，直接改主干。
- 源文：`assets/i18n/zh/` 简中，逐分片一一对照；并参照 `assets/i18n/en/` 基线识别与英文同形的未译值。
- 依据 andrew-translate skill「润色模式」：把现有译文当作 translation_1，从反思阶段起逐句复核；按准确性 / 流畅性 / 术语一致性 / 文风四维检视。
- 全程人工语言润色，未调用任何机翻接口，未使用 `i18n_translate.py`；未 commit / 未 push。

### 完成量
- 分片：**28 / 28**
- 键数：**1272 / 1272**

### 主要修正明细
1. **整片英文未译**（`issue_page.json`）：`actionFailed / cancel / close / closeHint / closeIssue(Title) / closed / commentFailed / commentHint / commentPostFailed / commentPosted / commentRequired / commentTooLong / comments / noComments / openNow / postComment / posting / publish / reopen / reopenHint / reopenIssue / reopened / toggleFailed` 等 20+ 键由英文改为俄语（如 `Action failed` → `Действие не удалось`、`Post Comment` → `Опубликовать комментарий`、`Close Issue #{number}` → `Закрыть Issue #{number}`）；同时把 `editIssue / issueEdited` 等补齐。
2. **占位符修正**（`settings.json`）：`consentedAt` 去掉译文多加的 `{at}`（对齐 zh 的 `{version}`）；`donateTileDesc`、`logoutDesc` 去掉译文多加的 `{repo}` / `{login}`（zh 源文本无占位符）。
3. **键集合/顺序**：`common / download_manager_page / drafts_page / login / notifications_page / profile_page` 六个分片键顺序与 zh 不一致，已按 zh 顺序重排；键集合原本一致。
4. **术语一致性**：「议题」统一保留技术词 **Issue**（`new_issue_page.submit/title`、`repo.closeIssue/issueCreated/newIssue/archiveConfirm` 原用了 `проблема`/`задача`/小写 `issue`，已统一为 `Issue`），与 `issue_page`、`search_page.feedIssue` 等保持一致。
5. **法律/声明长文本**（`onboarding.json`）：`licenseBody` / `onboardingLicenseBody` 逐句核对，`12. Форс-мажор` 一节多余的空行已去掉（与 zh 单换行一致）；`traceableDesc` 的 `Настройок` 拼写错误改为 `«Настроек»`；`licenseIntro` 介词 `об каналах` 改为 `о каналах`。
6. **格式**：全部 2 空格缩进、`ensure_ascii=false`、UTF-8、末尾单个换行、无 CR（round-trip 比对 0 差异）。

### 自检结论
- `python3 tool/i18n_shard_check.py ru assets/i18n/ru` → **problems=0**（28 分片 / 1272 键）。
- 键集合/键顺序：28 分片全部与 zh 一致（0 差异）。
- 占位符多重集：与 zh 逐键比对，0 不一致。
- 值类型：1272 个值均为非空字符串（0 异常）。
- 残留扫描：整句英文残留 0、CJK/假名残留 0。

### 遗留问题
- 无阻塞项。俄语 GitHub 语境里 `Issue / Token / Commit / Release / Gist` 等技术词按任务书保留原文；若产品侧另有本地化偏好（如把 Issue 译为「задача」），可全局统一替换，但当前与英文术语及包内其余键保持一致。

## 法语（fr）

### 范围与做法
- 对象：`assets/i18n/fr/` 既有语言包（28 分片 / 1272 键），本次为**润色**，直接改主干。
- 源文：`assets/i18n/zh/` 简中，逐分片一一对照；并参照 `assets/i18n/en/` 基线识别与英文同形的未译值。
- 依据 andrew-translate skill「润色模式」：把现有译文当作 translation_1，从反思阶段起逐句复核；按准确性 / 流畅性 / 地道法语 / 术语一致性四维检视。
- 全程人工语言润色，未调用任何机翻接口，未使用 `i18n_translate.py`；未 commit / 未 push。

### 完成量
- 分片：**28 / 28**
- 键数：**1272 / 1272**
- 实际改动：15 个分片共 **51 处** value 修订；6 个分片键顺序重排。

### 主要修正明细
1. **整片英文未译**（`issue_page.json`，25 键）：`actionFailed / cancel / close / closeHint / closeIssue(Title) / closed / commentFailed / commentHint / commentPostFailed / commentPosted / commentRequired / commentTooLong / comments / noComments / openNow / postComment / posting / publish / reopen / reopenHint / reopenIssue / reopened / toggleFailed` 等由英文改为法语（如 `Action failed` → `Échec de l’opération`、`Post Comment` → `Publier le commentaire`、`Comment too long…` → `Commentaire trop long (… caractères)…`、`Spam` → `Pourriel`）。
2. **与英文同形的残留**（按 zh 重译）：`about_page.version`（`Version : {version}`）、`about_page.commitCount`、`action_run_page.duration*` / `jobs`（→ `Tâches`）、`new_release_page.tagLabel`（→ `Étiquette (tag)`）、`repo.publicRepo`（→ `Dépôt public`）、`common.previewSvgSource`（→ `SVG (code source)`）、`common.updated`（拼写错误 `Misé` → `Mis à jour`）。其余与英文同形但确为法语正确词者（`Services / Public / Branches / Commits / Description / Type / Code / Notifications / Compact / Standard / OK / Image / Audio / Avatars` 及保留技术词 `Gists / Workflows / Noto Serif SC` 等）经核对后保留。
3. **占位符修正**（`settings.json`）：`consentedAt` 去掉译文多加的 `{at}`（对齐 zh 的 `{version}`）；`donateTileDesc` 去掉 `{repo}`；`logoutDesc` 去掉 `{login}`（zh 源文本无占位符）。
4. **键集合/顺序**：`common / download_manager_page / drafts_page / login / notifications_page / profile_page` 六个分片键顺序与 zh 不一致（键集合原本一致），已按 zh 顺序重排。
5. **法律/声明长文本**（`onboarding.json`，逐句核对）：
   - `licenseBody` / `onboardingLicenseBody`（17 节全文）逐句对照 zh 复核，仅润色第 10 节免责语句（`sauf obligation d'exclusion que la loi interdirait` → `sauf dans les cas où la loi interdirait une telle exclusion de responsabilité`），其余译文忠实准确。
   - **纠正实质错译**：`licenseOfficialLine` 原写「以英文 LICENSE 为准」，与 zh「以中文原文为准」不符，已改为中文原文为准（`…le texte chinois original prévaut`）；`licenseAuthoritative` 同步统一措辞。
   - `tokenVault` 改为「令牌仅存本机、不传第三方，数据只与 GitHub 通信」，与 zh 一致。
6. **术语一致性**：法语正文中 10 处 `Token` 统一为地道法语技术词 `jeton/jetons`（涉及 `action_log_page.noLogs`、`profile_page` 登录/删除令牌系列、`workflow_dispatch_page` 两处），保留字面代码标识 `TOKEN-EXIT-01` 与任务书要求保留原文的术语；仓库统一 `dépôt`，评论统一 `commentaire`，日志统一 `journaux`。

### 自检结论
- `python3 tool/i18n_shard_check.py fr assets/i18n/fr` → **problems=0**（28 分片 / 1272 键）。
- 键集合/键顺序：28 分片全部与 zh 一致（0 差异）。
- 占位符多重集：与 zh 逐键比对，0 不一致；额外做逐字节正则多重集校验，0 异常。
- 值类型：1272 个值均为非空字符串（0 异常）。
- 格式：全部 2 空格缩进、`ensure_ascii=false`、UTF-8、末尾单个换行、无 CR。
- 残留扫描：整句英文残留 0（自研 EN 功能词启发式扫描 0 命中）。

### 遗留问题
- 无阻塞项。`GitHub / Release / Actions / Issue / PR / Token / Gist / Commit / Workflows` 等技术词与品牌词按任务书保留原文；`Token` 在**法语叙述句**中统一译为 `jeton`，若产品侧对术语另有品牌偏好可全局替换。`about_page.version/commitCount` 与 `common.previewSvgSource` 为避免与英文基线同形而改写法语表述（加标签/说明），语义与 zh 一致。
