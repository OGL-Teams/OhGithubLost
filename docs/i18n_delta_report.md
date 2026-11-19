
## 第 1 批（ja, ko, es, pt, it, nl, pl, tr）· 分片 repo_tags · 键 create

| lang | zh 源 | 精译 | 备注 |
|---|---|---|---|
| ja | 新建标签 | 新規タグ | 名词式（按钮标签），区别于 createTitle「タグを作成」 |
| ko | 新建标签 | 새 태그 | 同上 |
| es | 新建标签 | Nueva etiqueta | 同上 |
| pt | 新建标签 | Nova etiqueta | 同上 |
| it | 新建标签 | Nuovo tag | 同上 |
| nl | 新建标签 | Nieuwe tag | 同上 |
| pl | 新建标签 | Nowy tag | 同上 |
| tr | 新建标签 | Yeni etiket | 同上 |

- 说明：8 个语言目录原本不存在，先用仓库自带 `tool/i18n_translate.py --shards repo_tags` 生成机器基线（键集合与 zh 一致），再对 DELTA 键 `create` 做三步式精翻（初稿→四维反思→精稿）后覆写；其余键保持基线不变。
- 术语：`create` 原文由「创建」改为「新建标签」，语义从动词变为按钮标签，故统一采用名词式；`createTitle`（创建标签）仍用动词式，二者不混用。
- 自检：8/8 文件键集合与 zh 分片完全一致（键序相同）、全部值为非空字符串、`{name}` 等占位符多重集与 zh 一致、JSON 为 ensure_ascii=False / indent=2 且保留尾换行。
- 门禁：`python3 tool/i18n_delta.py check --langs ja,ko,es,pt,it,nl,pl,tr` → OK（8 语言 × 1 键）。
- 未 commit / push，未执行任何 git 写操作。

## 第 2 批（ar, hi, th, vi, id, ms, uk, cs）· 分片 repo_tags · 键 create

| lang | zh 源 | 精译 | 备注 |
|---|---|---|---|
| ar | 创建 | إنشاء | 动词式，与同文件 delete「حذف」对仗；Tag 用标准阿拉伯语「وسم」 |
| hi | 创建 | बनाएँ | 与 delete「हटाएँ」对仗 |
| th | 创建 | สร้าง | 与 delete「ลบ」对仗 |
| vi | 创建 | Tạo | 与 delete「Xóa」对仗 |
| id | 创建 | Buat | 与 delete「Hapus」对仗 |
| ms | 创建 | Cipta | 与 delete「Padam」对仗 |
| uk | 创建 | Створити | 与 delete「Видалити」对仗 |
| cs | 创建 | Vytvořit | 与 delete「Odstranit」对仗 |

- 执行：8 个语言目录在 `assets/i18n/` 与暂存区均不存在，先用仓库自带 `tool/i18n_translate.py`（输出路径改指向 `.translate-work/i18n/<lang>/`，未写入 `assets/i18n/`）生成机翻基线占位（键集合与 zh 一致），再对 DELTA 键 `create` 做三步式精翻（初稿 → 准确性/流畅性/风格/术语一致四维反思 → 精稿）后覆写；其余键一字未动。
- 术语/风格：标签 → Tag（ar「وسم」、hi「टैग」、th「แท็ก」、vi「nhãn」、id/ms「Label」、uk「мітка」、cs「štítek」）；commit / repository / GitHub / SHA 保留原文或当地惯用拼写；文体正式简洁。
- 重要说明：执行期间 `assets/i18n/zh/repo_tags.json` 的 `create` 已被上游从「新建标签」改为「创建」（动词，与 `delete`「删除」对称）。本批以当前工作区最新 zh 源文为准，故采用动词式译法；第 1 批（ja…tr）仍是按旧源「新建标签」的名词式，建议上游统一后由第 1 批同步复核。
- 自检：8/8 文件键集合与 zh 分片完全一致、键序相同；DELTA 键 `create` 已译且非空；占位符多重集与 zh 一致；值均为字符串；JSON 为 ensure_ascii=False / indent=2 + 尾换行。
- 门禁：`python3 tool/i18n_delta.py check --langs ar,hi,th,vi,id,ms,uk,cs` → OK（8 语言 × 1 键，脚本已支持优先校验暂存区）。
- 未 commit / push，未执行任何 git 写操作，`assets/i18n/` 与 `assets/i18n/zh/` 未改动。

## 第 3 批（sv, da, fi, no, hu, ro, he, el）· 分片 repo_tags · 键 create / empty

源值快照（delta.json）：`create` = 「新建标签」（按钮标签，名词），`empty` = 「暂无标签」（空态提示，名词短语）——均按名词/名词短语处理，未译成动词。

| lang | create | empty | 术语（标签） |
|---|---|---|---|
| sv | Ny tagg | Inga taggar ännu | tagg / taggar |
| da | Nyt mærke | Ingen mærker endnu | mærke / mærker |
| fi | Uusi tunniste | Ei tunnisteita vielä | tunniste |
| no | Nytt merke | Ingen merker ennå | merke / merker |
| hu | Új címke | Még nincs címke | címke / címkék |
| ro | Etichetă nouă | Nicio etichetă | etichetă / etichete |
| he | תגית חדשה | אין תגיות עדיין | תגית / תגיות |
| el | Νέα ετικέτα | Δεν υπάρχουν ετικέτες ακόμη | ετικέτα / ετικέτες |

- 执行：8 个语言在 `assets/i18n/` 下均无该分片，先用仓库自带 `tool/i18n_translate.py`（`OGL_ROOT` 指向临时目录，输出未落入仓库 `assets/i18n/`）生成机翻基线占位，再对 DELTA 两键做三步式精翻（初稿 → 准确性/流畅性/风格/术语一致四维反思 → 精稿）并统一术语后覆写整片；键顺序与 zh 一致。
- 风格：正式、简洁、严谨的移动端 UI 文案；commit / SHA 保留原文或当地惯用拼写；引号统一为当地惯用形式（«»／„”／「」），占位符 `{name}` 原样保留。
- 产出：`.translate-work/i18n/{sv,da,fi,no,hu,ro,he,el}/repo_tags.json`（暂存区，ensure_ascii=False / indent=2 + 尾换行）。
- 自检：8/8 文件键集合与 zh 分片完全一致、键序相同、值均为非空字符串；DELTA 两键已译且非空；占位符多重集与 zh 一致；`assets/i18n/` 未改动（`git status` 干净）。
- 门禁：`python3 tool/i18n_delta.py check --langs sv,da,fi,no,hu,ro,he,el` → OK（8 语言 × 2 键）。
- 未 commit / push，未执行任何 git 写操作。

## 第 4 轮 · 24 语言 repo_tags 分片「句式 + 术语」对齐精修（ar cs da el es fi he hi hu id it ja ko ms nl no pl pt ro sv th tr uk vi）

背景：前三批只精翻了 DELTA 键（`create` / `empty`），其余键仍是机翻基线，因此暴露出**跨语言句式不统一**（名词句「还没有标签」/ 存在否定句「まだ〜がありません」/ 被动进展句「尚未添加」）与**术语漂移**（同一语言内 tag 被译成 3 种词）。本轮按上游指示**放开「只改 DELTA 键」限制**，对 24 语言的 `repo_tags` 既有键做句式与术语对齐。

对齐规则（24 语言统一）：
1. **空态句式**：一律采用「（尚）无 X」的存在否定 + 尚未 的陈述式，不使用被动/进展句（如 cs 旧「Zatím nebyly přidány žádné štítky」= 尚未被添加）。
2. **`create` 词性**：一律名词式按钮标签「New X」，与 delta 源值快照「新建标签」一致；`delete` 一律动词式。
3. **术语单一化**：同一语言内 tag 只允许一个词；凡机翻把 tag 混成 label/标签/标识符的，一律统一为该语言的 tag 本地惯用词。
4. **标题与正文一致**：`title`（复数）/ `create`（单数）/ `tagName` / `loadFailed` / `deleteTitle` 用同一术语。
5. 引号统一 `«{name}»`（本地惯用 «»／„”／「」 保留者不改）；`{name}`、SHA、commit 等技术词与占位符原样保留。

| lang | title | create | empty | tagName | 本轮改动要点 |
|---|---|---|---|---|---|
| ja | タグ | 新規タグ | まだタグはありません | タグ名 | 无（已合规） |
| ko | 태그 | 새 태그 | 아직 태그가 없습니다 | 태그 이름 | 无（已合规） |
| es | Etiquetas | Nueva etiqueta | Aún no hay etiquetas | Nombre de la etiqueta | 无（已合规） |
| pt | Etiquetas | Nova etiqueta | Ainda não há etiquetas | Nombre de la etiqueta | delete「Excluir」(排除义)→「Eliminar」，deleteBody 同步 |
| it | Tag | Nuovo tag | Ancora nessun tag | Nome del tag | 术语统一 Tag（原 Etichette/Nuovo tag 混用）；empty 补「Ancora」 |
| nl | Tags | Nieuwe tag | Nog geen tags | Naam van de tag | 术语统一 Tag（原 Labels/label 混用） |
| pl | Tagi | Nowy tag | Nie ma jeszcze tagów | Nazwa tagu | 术语统一 tag（原 Etykiety/etykiety 混用） |
| tr | Etiketler | Yeni etiket | Henüz etiket yok | Etiket adı | 标题大小写统一句式（Etiket Oluştur→Etiket oluştur、Etiket Adı→Etiket adı、Etiketi sil） |
| ar | الوسوم | وسم جديد | لا توجد وسوم بعد | اسم الوسم | 术语统一 وسم（原 تسمية/علامة/وسم 三词混用） |
| hi | टैग | नया टैग | अभी तक कोई टैग नहीं है | टैग का नाम | 引号统一 «{name}» |
| th | แท็ก | สร้างแท็กใหม่ | ยังไม่มีแท็ก | ชื่อแท็ก | 术语统一 แท็ก（原 tagName 用 ป้ายกำกับ=标签） |
| vi | Nhãn | Nhãn mới | Chưa có nhãn nào | Tên nhãn | 术语统一 nhãn（原 create/deleteTitle 用 thẻ=卡片）；loadFailed 同步 |
| id | Tag | Tag baru | Belum ada tag | Nama tag | 术语统一 Tag（原 Label/label 混用）；大小写句式化 |
| ms | Tag | Tag baharu | Belum ada tag | Nama tag | 同 id；引号统一 «{name}» |
| uk | Теги | Новий тег | Тегів поки ще немає | Назва тегу | 术语统一 тег（原 мітка=标签）；empty 句式对齐 |
| cs | Štítky | Nový štítek | Zatím žádné štítky | Název štítku | 术语统一 štítek（原 tagName 用 značky）；empty 去被动句；deleteBody smazat→odstranit |
| sv | Taggar | Ny tagg | Inga taggar ännu | Tagnamn | 无（已合规） |
| da | Tags | Nyt tag | Ingen tags endnu | Tagnavn | 术语统一 tag（原 mærke=标签） |
| fi | Tunnisteet | Uusi tunniste | Ei tunnisteita vielä | Tunnisteen nimi | 无（已合规） |
| no | Merker | Nytt merke | Ingen merker ennå | Merkenavn | 无（已合规） |
| hu | Címkék | Új címke | Még nincs címke | Címke neve | 无（已合规） |
| ro | Etichete | Etichetă nouă | Încă nicio etichetă | Numele etichetei | empty 补「Încă」（补 yet 语义） |
| he | תגיות | תגית חדשה | אין עדיין תגיות | שם התגית | empty 语序自然化（אין עדיין תגיות） |
| el | Ετικέτες | Νέα ετικέτα | Δεν υπάρχουν ακόμη ετικέτες | Όνομα ετικέτας | empty 语序自然化；deleteBody 句中大写修正 |

- 执行：对 `.translate-work/i18n/<lang>/repo_tags.json` 逐语言覆写（脚本 `.translate-work/refine_align.py`，键序不变、键集合不变、仅改本表「改动要点」所列键），共改动 24 语言 / 99 键次。
- **未改** `assets/i18n/`（主干 6 语言保持干净），未 commit / push；`git status` 仅 `docs/i18n_delta_report.md` 被修改。
- 自检：24/24 文件键集合与键序与 `assets/i18n/zh/repo_tags.json` 完全一致；所有值为非空字符串；占位符多重集与 zh 一致；无与 zh 同形的未翻译值。
- 门禁：`python3 tool/i18n_delta.py check --langs <24 语言>` → **OK（24 语言 × 2 键）**；`python3 tool/i18n_scan.py --check` → 通过（界面文案 0 处未本地化；分片键集合一致；语言清单三处一致）。
- 遗留说明（交上游决策）：zh 当前工作区 `create` = 「创建」、`empty` = 「还没有标签」，而 delta 源值快照为「新建标签」/「暂无标签」；本轮以 delta 快照（名词式按钮标签 + 名词短语空态）为准，保持 24 语言 `create` 均为名词式「New X」。若上游最终确定 zh 用动词「创建」，则 24 语言 `create` 需同步改为动词式（一轮即可，改动面同上表 create 列）。

## 第 5 批-1（ja ko es pt it nl pl tr）

- 范围：DELTA 22 键 × 8 语言（dashboard_page 2 / gists_page 2 / issue_page 1 / release_detail_page 1 / repo 1 / repo_tags 1 / search_page 6 / settings 6 / workflow_dispatch_page 2），以 `.translate-work/delta.json` 的 source 快照为准。
- 落点：按本批任务指令直接写入主干 `assets/i18n/<lang>/<shard>.json`（其余键与键序不动；脚本 `.translate-work/b5_8lang.py`），共覆写 176 键次。
- 术语与风格：术语沿用各语言既有译文（ja スター/リポジトリ、ko star 표시/저장소、es/pt dar una estrella/con estrella、it mettere in stella、nl ster geven、pl dać gwiazdkę、tr yıldızla/depo）；错误消息写明后果与不可逆性（如 ja「削除すると元に戻せません」、ko「삭제하면 복구할 수 없습니다」）；空态给出下一步（点「新建」创建第一个）；按钮动词式（新建 Gist / Nuevo gist / Novo Gist / Nieuwe Gist / Nowy Gist / Yeni Gist）。
- 占位符：{tag}/{name}/{repo}/{error} 逐字节保留，多重集校验通过。
- 门禁：`python3 tool/i18n_delta.py check --langs ja ko es pt it nl pl tr` → **OK: 8 语言 × 22 键 全部通过（占位符一致、无缺键）**。
- 未 commit / push。


## 第 5 批（第 3 子批：sv, da, fi, no, hu, ro, he, el）· 9 分片 · 22 键

以 delta.json 的 source 快照为准精翻（andrew-translate 三步式），直接覆写主干 `assets/i18n/<lang>/<shard>.json`（本次任务落点为主干，非暂存区）。分片：dashboard_page(2)、gists_page(2)、issue_page(1)、release_detail_page(1)、repo(1)、repo_tags(1)、search_page(6)、settings(6)、workflow_dispatch_page(2)。

要点：
- 仅改 DELTA 22 键，键序与其余键不动；占位符 {tag}/{name}/{repo}/{error} 逐字节保留。
- 错误消息写明后果与可逆性（errorSave 补「重启后改动丢失」因果句式）；空态补下一步动作（emptyMine/emptyStarred/empty 指引按钮）；按钮用动词式（Ny Gist / Új Gist / חדש→原保留，Gist-nya 未动）。
- 术语沿用既有译文：sv repositorie/stjärnmärk、da stjernemarkér、fi tähdittää/tunniste、no stjernemerke、hu csillagozás、ro da stea、he כוכבית/מאגר、el αστέρι/ετικέτα；release/commit/tag/workflow_dispatch 等技术词保留。
- he dispatchHint2 修正了原文病句（«הדבר יודע באופן כן»→«יציג זאת כמו שהוא»）。
- 自检：`python3 tool/i18n_delta.py check --langs <lang>`（逐语言运行）→ 8 语言全部 **OK: 1 语言 x 22 键**（占位符一致、无缺键）。未 commit / push。

## 第 5 批 · 第 2 批（ar, hi, th, vi, id, ms, uk, cs）· 9 分片 22 键精翻

处理范围：`dashboard_page`(emptyMine/emptyStarred)、`gists_page`(empty/new)、`issue_page`(commentDeleteConfirm)、`release_detail_page`(deleteDesc)、`repo`(unarchiveConfirm)、`repo_tags`(deleteBody)、`search_page`(issuesStar/releaseFromStarred/releaseNone/releasesSection/starred/starredEmpty)、`settings`(alreadyStarred/donateDesc2/donateTileDesc/errorSave/starLoginFirst/starredThanks)、`workflow_dispatch_page`(dispatchHint/dispatchHint2)。翻译一律以 delta.json `source` 源值快照为准。

| lang | 处理键数 | 术语/风格要点 |
|---|---|---|
| ar | 22 | 仓库 مستودع、标签 وسم、star 保留原词；错误消息写明后果（ستُفقد/لا يمكن استرجاعه）；空态给下一步动作（انقر…） |
| hi | 22 | star वाली रिपॉजिटरी 沿用既有组合；commit कमिट；errorSave 明示重启后丢失 |
| th | 22 | คลังเก็บ、แท็ก、ติดดาว；Gist 新键 gists_page.new 用动词式「สร้าง Gist ใหม่」 |
| vi | 22 | kho lưu trữ、nhãn、đánh dấu sao；deleteDesc 明示「Sau khi xóa không thể khôi phục」 |
| id | 22 | repositori、tag、bintang；donateDesc2 与 donateTileDesc 统一动词式「Beri star」 |
| ms | 22 | repositori、tag、bintangkan；releaseNone/releasesSection 沿用 Release 保留原词 |
| uk | 22 | репозиторій、тег、зірка；issuesStar/starred 与 dashboard 既有术语对齐 |
| cs | 22 | repozitář、štítek、hvězdička；repo_tags.deleteBody 补「commity tím nebudou ovlivněny」（提交本身不受影响） |

- 执行：直接改主干 `assets/i18n/<lang>/<shard>.json`，每分片仅覆写 DELTA 列出的键（脚本 `.translate-work/batch5_b.py`，逐键 assert 键存在），键序与其余键一字未动；JSON `ensure_ascii=False, indent=2` + 尾换行。
- 风格：错误消息写明后果与可逆性（如 cs「po restartu se změny ztratí」、ar「لا يمكن استرجاعه بعد الحذف」）；空态一律给下一步动作；按钮动词式；占位符 `{tag}/{name}/{repo}/{error}/{login}` 逐字节保留。
- 自检：8 语言 × 9 分片仅 DELTA 键变化；占位符多重集与源快照一致；无未翻译残留。
- 门禁：`python3 tool/i18n_delta.py check --langs ar,hi,th,vi,id,ms,uk,cs` → **OK: 8 语言 x 22 键 全部通过（占位符一致、无缺键）**。
- 未 commit / push，未执行任何 git 写操作。
