# 一致性契约（D1–D9）

> 本文是 `lib/base/disk/disk_cache.dart` 七道防线的**外部规范基线**。
> 源码内联表格、测试、`DiskBridge` 注释均引用本文。
> 纪律：改实现必须同步改本文；本文与源码冲突时，以**源码**为准并立即修正本文。
> 原则依据：`docs/QUALITY_STANDARD.md`（数据无价、防线没有开关、失败必留痕）。

## 防线总表（当前实现）

| 防线 | 语义 | 触发时行为 | 事件码 |
|---|---|---|---|
| **D1 写前必读** | 远端**已存在**且无基线 → 拒绝；远端**不存在**且无基线 → 合法新建 | `requiresRead` / 放行 | `OGL-CONS-201` |
| **D2 SHA 乐观锁** | 本地基线必须与远端一致 | `staleSha` + 三方差异 | `OGL-CONS-202` |
| **D2′ 远端消失** | 基线存在但远端已无该文件 → 拒绝（防"删除又重建"写歪） | `staleSha` | `OGL-CONS-209` |
| **D3 冲突重试** | 409/422 按 rebase 有界重试 | 超限返回冲突，不外抛 | `OGL-CONS-2xx` |
| **D4 逐键互斥** | 同一 key 的读写串行（写与读都进锁） | 排队执行 | — |
| **D5 写后失效 + 回读校验** | 写成功后失效本地条目并回读远端 | **回读不一致仍按"已提交待确认"收尾**（不误报失败、不重复提交） | — |
| **D6 失败可感知** | 任何非预期异常变成 `WriteOutcome` 失败结果 + 可读 reason + 诊断 | 永不外抛（除非法键编程错误） | `OGL-CONS-206` |
| **D7 二次确认** | `dangerous` 或 `force` 必须 `confirmed=true` | `needsConfirmation` | `OGL-CONS-207` |
| **D8 提交日志** | 真正要发出的写先落 pending；重放**完整重走 D1–D7** | 成功 complete / 语义冲突 abandon | — |
| **D9 草稿** | 先落盘再展示，带 baseSha 基线，提交成功即清 | 可观察（ChangeNotifier） | — |

> 编号说明：源码个别注释用「D10」指代三方差异展示，那是 D2 的子步骤，**不是独立防线**。

## 关键语义裁决（易误解处）

### 1. 空串基线 = 无基线（SD-01）
`putContentLocked` 的 `baseSha` 是 `required String`，"新建 / 草稿缺基线"只能用空串表达。
引擎内部归一化为 `null` 后贯通 D1/D2/D2′/force/`expectedSha`；**绝不发 `sha: ''` 给服务端**（GitHub 回 422）。

### 2. D1 的合法例外（不是"防线被打破"）
- **远端不存在 + 无基线 = 新建**：服务端以"无 sha 即拒绝覆盖"兜底并发创建；
  此处**没有**绕过乐观锁，只是把"不存在"作为合法前提。
- **`recordJournal: false`**：仅用于 `replayPending` 重放，避免队列重影；重放本身完整走 D1–D7，由原记录收尾。
- **`force` + `confirmed`**：D7 用户显式二次确认后的类型化选择（原则 12），不是隐式开关。
- **未绑定缓存的裸写旁路**：`putContentLocked` 在 `cache==null/key==null` 时退化为裸网络写，
  **仍带 baseSha**（服务端乐观锁兜底）并把 409/422 折成结构化 `staleSha`；
  它跳过本地 D1–D7 是装配期降级，不是运行时可切换的开关。

### 3. D5 的当前语义（与旧注释不同）
旧表格写「回读校验失败 → `verificationFailed`」；**当前实现**是：写已到达远端后，
回读不一致按"`已提交` + baseSha 待确认"收尾，避免把已生效的写误报为失败导致用户重复提交。
`WriteConflict.verificationFailed` 枚举目前无产出路径（保留给未来的严格模式）。

### 4. 206 / 截断写回执
中间代理对 PUT 回 `206 Partial Content` 时，响应体可能不完整。
`GhApi.putContent` 在**状态码为 206 或 `written.sha` 为空**时一律**回读远端确认**
（206 说明中间代理截断了回执，即便截断体恰好带 sha 也不采信；不重试免撞 422），
回读不到则抛带状态码的异常。详见 `docs/audit_206.md`。

## 与测试 / 门禁的对应

- `test/base/cache_consistency_test.dart`：D1（含新建语义）、D2、D6、D7、D8 的离线断言
- `test/base/durability_test.dart` / `chaos_test.dart`：原子写、失败注入
- 门禁盲区（待补）：`layer_audit.py` 不解析 `export`，`motion/perf_audit.py` 只扫 `lib/surface/`；
  本层语义目前无 CI 可裁决脚本——见 `docs/5layer-audit-todo.md`。

## 变更记录

- 2026-11-08：落地本文（此前 3 处引用指向不存在的文件）；同步 D1 新语义与 D5 现状；
  界定 D1 的四类合法例外，避免被误读为"防线有开关"。
