# 仓库 Tags 功能 / Repository Tags Feature

> 目标层级与分阶段计划 / Target layers and staged plan.
> 体例从属于 / Convention: [`DOCUMENT_STYLE.md`](DOCUMENT_STYLE.md).

> **更新时间 / Last Updated**：2026-11-15 19:29:40　**对应版本 / Version**：v14.0.0

## 一、目标 / Goal

补齐仓库 Git tags 的读取与管理，并据此扩展设置页的可配置内容，作为下一个
大版本（v13.0.0）的主功能。
Add repository Git tag management and extend Settings with related options as
the main feature of the next major release (v13.0.0).

现状 / Current state: `GhApi` 已有 `releases` / `branches` 全链；tags 仅在
「最新版本号」里以回退方式读取，没有列表、创建、删除能力。
`GhApi` already has full release and branch chains; tags are only read as a
fallback in "latest version", with no list / create / delete capability.

## 二、层级划分 / Layer Assignment

| 层 / Layer | 文件 / File | 职责 / Responsibility |
| --- | --- | --- |
| L0 | `lib/kernel/contract/net_types.dart` | 已提供 `NetMethod`/`GhRequest` 语义；不新增 / No change |
| L1 | — | 网络与缓存能力已足够 / Existing transport and cache suffice |
| L2 | `lib/domain/gh/gh_models.dart` | 新增 `GhTag` 数据类 / New `GhTag` record |
| L2 | `lib/domain/gh/gh_api.dart` | `listTags` / `createTag` / `deleteTag` / `getTag` |
| L2 | `lib/domain/gh/gh_client.dart` | 复用 `getList` / `getObject` / `send` / No change |
| L3 桥 / Bridge | `lib/domain/domain_bridge.dart` | 暴露 `tags` 只读出口 / Expose a read-only tags facade |
| L3 | `lib/surface/pages/repo_page.dart` | Tags 子页入口与列表 / Tags subpage entry and list |
| L3 | `lib/surface/pages/repo_tags_page.dart` | 新建：列表 / 创建 / 删除 / New page |
| L3 | `lib/surface/pages/settings_page.dart` | 新增设置项 / New settings entries |

**依赖方向 / Dependency direction**: L3 → L2 → L0；不新增反向依赖。
L3 → L2 → L0 only; no new upward dependencies.

## 三、分阶段 / Stages

| 阶段 / Stage | 内容 / Content | 验收 / Acceptance |
| --- | --- | --- |
| S1 | `GhTag` + `listTags`（分页）/ `getTag` | 离线单测：字段解析、分页参数 |
| S2 | `createTag` / `deleteTag`（写一致性 D1–D9 由既有链路保障） | 单测：请求路径、方法、body、错误映射 |
| S3 | `DomainBridge.tags` 只读出口 + `SurfaceBridge` 透传 | `contract_audit` / `facade_audit` 全绿 |
| S4 | `RepoPage` 入口 + `RepoTagsPage`（平铺、零气泡） | widget 测试：列表/空态/错误三态 |
| S5 | 设置页新增：tags 排序、默认每页数量、删除二次确认 | 持久化往返测试 |
| S6 | 六语言文案 + 回归锁 + 全门禁 + CI | `i18n_scan` / `flutter test` 全绿 |
| S7 | 版本号 13.0.0、发布说明、tag、23 产物、归档 | 完整发布流程 |

每阶段独立提交，CI 绿后再进入下一阶段；不并行写同一文件。
Each stage is committed independently; the next starts only after CI is green.
No two stages write the same file concurrently.

## 四、设置页新增项 / New Settings

| 键 / Key | 类型 / Type | 默认 / Default | 说明 / Meaning |
| --- | --- | --- | --- |
| `tagSort` | enum: `name` / `updated` | `name` | 标签列表排序 / Tag list order |
| `tagsPerPage` | int: 20/30/50/100 | 30 | 每页数量 / Page size |
| `tagDeleteConfirm` | bool | true | 删除前二次确认 / Confirm before deletion |

以上均为**客户端偏好**，不改变 GitHub 服务端数据；写入 `OgLSettings`
并由既有 KeyValue 持久化。
These are client-side preferences; they do not alter GitHub server data and
reuse the existing `OgLSettings` persistence.

## 五、API 契约 / API Contract

`GET /repos/{owner}/{repo}/tags?per_page=&page=` → `List<GhTag>`
`GET /repos/{owner}/{repo}/git/ref/tags/{tag}` → `GhTag`
`POST /repos/{owner}/{repo}/git/refs`（`ref: refs/tags/<name>`, `sha`）→ `GhTag`
`DELETE /repos/{owner}/{repo}/git/refs/tags/{tag}` → `void`

创建走 Git refs 而非 Releases API；轻量标签不生成 Release。
Creation uses Git refs rather than the Releases API; lightweight tags do not
create a Release. Deletion is a destructive operation and always requires
explicit confirmation in the UI.

## 六、历史分界 / Boundary

v12.6.10 之前的文档体例不追溯改写；本文件自 v13.0.0 计划起采用
中英双语正式体例。
Documents predating v12.6.10 are not rewritten. This plan adopts the formal
bilingual convention from the v13.0.0 cycle onward.

