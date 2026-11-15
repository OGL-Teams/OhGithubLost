# 发布说明 / Release Notes

> 体例从属于 [`docs/DOCUMENT_STYLE.md`](../docs/DOCUMENT_STYLE.md)。
> Convention is subordinate to [`docs/DOCUMENT_STYLE.md`](../docs/DOCUMENT_STYLE.md).

每版本一个文件，**中英逐条对照**；固定小节见上位规范。
One file per release, **bilingual line by line**; fixed sections are defined in
the parent guide.

- 文件名 / File name: `v<版本>.md`（例如 / e.g. `v12.6.10.md`）
- 未发布或跳过的版本不建文件，在 `CHANGELOG.md` 标注。
  Unreleased or skipped versions have no file here; record them in `CHANGELOG.md`.
- 发布时以本目录文件写入 GitHub Release 正文。
  The published Release body is taken from the matching file in this directory.

## 自动化 / Automation

发布作业 `build.yml` 的 `release` job 按以下优先级取正文。
The `release` job in `build.yml` selects the body in this order:

| 顺序 / Order | 来源 / Source | 说明 / Note |
| --- | --- | --- |
| ① | workflow 输入 `release_notes` | 手工 dispatch 显式传入 / Explicit manual dispatch input |
| ② | `release_notes/v<版本>.md` | **正规来源 / Canonical** |
| ③ | `release_notes/v<版本>-<通道>.md` | 通道预发布 / Channel pre-release |
| ④ | 自动模板 / Auto template | 兜底并发警告 / Fallback, emits a warning |

若线上 Release 正文明显偏短，说明当时走了兜底模板；检查对应文件是否存在，
必要时 PATCH 补齐。历史版本清单由 `changed/releases.json` 与 `CHANGELOG.md`
维护，本文件不再保留静态版本表。
A conspicuously short published body indicates the fallback template was used;
verify the corresponding file and PATCH the Release if needed. Historical version
inventory is maintained in `changed/releases.json` and `CHANGELOG.md`; no static
version table is kept here.

## 历史分界 / Boundary

v12.6.10 之前的文件保留原始体例，不追溯改写。自 v12.6.10 起，
新增文件一律采用中英逐条对照的固定小节体例。
Files predating v12.6.10 retain their original style and are not rewritten.
From v12.6.10 onward, all new files use the bilingual fixed-section convention.
