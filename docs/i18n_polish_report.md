# i18n 全量润色报告

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
