
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
