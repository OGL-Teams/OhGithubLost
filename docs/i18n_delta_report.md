
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
