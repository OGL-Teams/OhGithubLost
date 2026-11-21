# UX 文案审计报告（zh 源 + en 基线同步）


> **更新时间 / Last Updated**：2026-11-19 21:32:49　**对应版本 / Version**：v14.0.0
审计依据：sota-ux-writing skill（rules/01–04 全部 Audit checklist）。
范围：assets/i18n/zh 全部 28 分片（1272 键）；en 仅同步被改键。
约束遵守：未改键名/键集合/键顺序/占位符多重集；未动其余 28 语言；未 commit；未动 lib/。

## 改动清单（22 键）

| 分片 | 键 | 旧值（zh） | 新值（zh） | 理由 |
|---|---|---|---|---|
| search_page | issuesStar | 我星标的仓库 | 我星标的仓库→「我星标的仓库」统一 | 术语：全 UI 一律「星标」，删除英文 star 混用 |
| search_page | releaseFromStarred | 来自你 star 的仓库 | 来自你星标的仓库 | 同上，去英文混排 |
| search_page | releaseNone | star 的仓库还没有发布 | 你星标的仓库还没有发布 | 术语统一 + 主语明确 |
| search_page | releasesSection | star 仓库的发布 | 星标仓库的发布 | 术语统一 |
| search_page | starred | 我星标的 | 我星标的仓库 | 宾语完整，脱离上下文可读（Tab 文案也成立） |
| search_page | starredEmpty | 还没有 star 仓库 | 还没有星标仓库 | 术语统一 |
| settings | alreadyStarred | 该账号已 star，不重复操作 | 该账号已点过星，无需重复 | 术语统一；「不重复操作」生硬 |
| settings | starLoginFirst | 请先登录，再为项目点亮 star | 登录后才能为项目点星 | 去修饰（点亮）、前置重点、术语统一 |
| settings | starredThanks | 感谢支持，已为项目点亮 star | 感谢支持，已为项目点星 | 同上 |
| settings | donateDesc2 | 给 {repo} 点 star | 为 {repo} 点星 | 术语统一；占位符保留 |
| settings | donateTileDesc | 用当前账号点 star | 用当前账号为项目点星 | 动词+宾语完整 |
| settings | errorSave | 保存失败，重启后丢失：{error} | 设置保存失败：{error}，重启后会丢失本次改动 | 错误契约：先说什么坏了，后果紧跟；「重启后丢失」歧义（像建议重启） |
| dashboard_page | emptyMine | 还没有仓库 | 还没有仓库。点「新建仓库」创建第一个 | 空态三要素：现状 + 下一步（rules/02 §3） |
| dashboard_page | emptyStarred | 还没有星标仓库 | 还没有星标仓库。在仓库页点「加星」即可收藏 | 同上；且与 filtered-zero 区分（此处是首用空态） |
| gists_page | empty | 还没有 Gist 片段 | 还没有 Gist 片段。点「新建」创建第一个 | 空态给下一步 |
| gists_page | new | 新建 | 新建 Gist | 按钮 = 动词+宾语 |
| repo_tags | deleteBody | 确定删除「{name}」吗？此操作不可撤销。 | 将删除标签「{name}」，提交本身不受影响。此操作不可撤销。 | 确认弹窗写具体后果 + 可逆性边界（删 tag 不删提交）；去掉「确定…吗？」泛化标题式问句 |
| issue_page | commentDeleteConfirm | 确认删除这条评论？删除后不可恢复。 | 删除这条评论？删除后无法恢复。 | 「确认删除…？」动词冗余（按钮本身即确认）；微调措辞 |
| release_detail_page | deleteDesc | 将删除发布 {tag}。该操作不易撤销。 | 将删除发布 {tag}，删除后无法恢复。 | GitHub Release 删除实际不可恢复，「不易撤销」弱化风险、误导（High：数据损失描述失真） |
| repo | unarchiveConfirm | 取消归档后仓库恢复可写。确定？ | 取消归档？取消后仓库恢复可写。 | 标题先行点题，「确定？」孤悬生硬 |
| workflow_dispatch_page | dispatchHint | 提示：仅声明了 workflow_dispatch 的工作流可被触发； | 只有声明了 workflow_dispatch 的工作流才能手动触发； | 去「提示：」前缀；分号句改完整陈述 |
| workflow_dispatch_page | dispatchHint2 | 否则 GitHub 会返回 422（本页会如实提示）。 | 否则 GitHub 会返回 422，本页会如实提示。 | 与上句连成完整因果句，去括号插语 |

对应 en 键全部按对齐语义重写（en 为基线，如 `New Gist`、`Delete tag "{name}"? Commits are not affected. This cannot be undone.`、`Release {tag} will be deleted. This cannot be undone.` 等）。

## 记录不改（风格偏好 / 超出保守边界）

- 术语漂移残留：repo.json `fork` 译「复刻」（GitHub 官方中文惯用「复刻」，保留）；`加星/星标/点星` 三种动词并存（已统一名词「星标」，动词形态属风格层，建议后续统一为「点星/加星」其一，涉及 keys 过多，本次未动）。
- `deleteForever`（repo.json）与 `delete` 并存：语义上「永久删除」对应回收站类场景，此处仓库无回收站，建议后续核实调用点后合并。
- common.json `ok: 确定` / `confirm: 确认` 作为通用键存在；调用点多为非后果性弹窗，未盲改（改按钮需逐调用点核对上下文，属 lib/ 层工作）。
- `unassign: 移除`（issue_page）：语义为「移除指派人」，键名语义受限，保留。
- 大段法律/协议文本（onboarding licenseBody、common accelThirdPartyBody）：法律文本以精确为先，不作平语化改写（skill rules/01 §6 明示法律/同意文本豁免）。
- `fetchOrSettings: 获取 / 去设置`（onboarding）：斜杠双动作按钮，信息密度可接受，未改。

## 本地化安全检查（rules/04）

- 全部分片占位符均为命名参数 `{name}` 形式，无位置参数、无字符串拼接句。
- 拆句风险键：workflow_dispatch_page `dispatchHint`/`dispatchHint2` 为两句硬拆（译语无法调序）——已在报告中记录为结构性遗留（合并需改键集合，超出本次权限），本次仅改善句法完整性。同类：common `fileTooLargeBody`（含 \n 分段，可接受）；repo `deleteDirDesc`/`deleteDirDesc2`（两句拆分，en 同形 `Will delete {count} file(s) under {path},` — 记录遗留，未动）。
- 中文无复数陷阱；`{count}` 型键均以「{count} 个/条」形态出现，适合多数译语。

## lib/ 硬编码检查

i18n_scan 报告 711 处中文字面量，全部归类为「开发者日志·有意保留」（日志/诊断输出，非界面文案），无需外化。

## 遗留问题（后续管线跟进）

1. settings/consentedAt、settings/logoutDesc：en 占位符与 zh 不一致（既有问题，本次未触碰，属 en 数据 bug，需单独修）。
2. repo `deleteDirDesc`/`deleteDirDesc2` 拆句、workflow_dispatch dispatchHint 拆句：需改键集合才能根治。
3. 星标动词（加星/点星/点亮）未完全统一，涉及 ~10 键，建议一次 glossary 迁移。
4. `ok`/`confirm` 通用键在后果性弹窗处的调用点需逐一核对（涉及 lib/）。

## 自检结果

- `python3 tool/i18n_scan.py --check` ✅ 通过（键集合 30 语言×28 分片一致；界面文案 0 处未本地化）
- `python3 tool/i18n_shard_check.py en assets/i18n/en` ✅（仅报 2 处既有占位符问题，与本次改动无关）
- `python3 tool/gate_of_gates.py --fatal` ✅ 11 支门禁全过，反向验证通过
