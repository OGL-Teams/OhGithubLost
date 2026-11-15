# B站 Index-Translate 翻译 API · Agent 集成文档 / Bilibili Index-Translate API · Agent Integration

版本 / Version：基于 2026-11 公开接口现状 / Based on the public API as of 2026-11
定位 / Scope：面向 Agent 调用方的技术契约与质量调优指南 / Technical contract and quality guide for Agent callers
适用模型 / Models：Index-Translate-35B-A3B / 9B / 2B，音节控制专项 / syllable-controlled Index-Homura-9B / 2B

## 1. 接口契约 / API Contract

| 项 / Item | 值 / Value |
| --- | --- |
| Base URL | `https://index-translate.bilibili.com/v1` |
| Chat Completions | `POST /v1/chat/completions` |
| Responses API（OpenAI 兼容 / OpenAI-compatible） | `POST /v1/responses` |
| 鉴权 / Auth | 无需真实 Key；`api_key` 任意字符串 / No real key; any string for `api_key` |

OpenAI SDK 可直接接入：`base_url` 指向上述地址，`api_key` 填 `index`。

### 1.2 模型清单 / Model Catalogue

| 模型 ID / Model | 定位 / Role | 适用场景 / Use case |
| --- | --- | --- |
| Index-Translate-35B-A3B | 能力最强（MoE，激活约 3B / strongest, MoE ~3B active） | 质量优先、复杂约束、意译调优 / quality, hard constraints, idiomatic tuning |
| Index-Translate-9B | 均衡 / balanced | 常规翻译、字幕、结构化内容 / general, subtitles, structured text |
| Index-Translate-2B | 轻量 / lightweight | 低延迟、大批量 / low latency, bulk |
| Index-Homura-9B / 2B | 音节受控专项 / syllable-controlled | 配音、字幕时长对齐 / dubbing, subtitle timing |

文本模型覆盖约 150 种语言 / ~150 text languages；图像翻译内置视觉编码器 / image translation has a built-in visual encoder.

### 1.3 两个强制参数 / Two Mandatory Parameters

1. `chat_template_kwargs: {"enable_thinking": false}` — 不传则输出思维链而非译文，是最隐蔽的故障点 / Without it the model emits CoT instead of the translation.
2. `temperature: 0` — 官方贪心解码对齐值，稳定且贴近直译 / Greedy decoding, stable and literal.

OpenAI SDK 用 `extra_body={"chat_template_kwargs": {"enable_thinking": False}}` 注入 / Inject via `extra_body`.

## 2. 质量层 / Quality Layer

「意译」不能靠一句「请意译」碰运气 / Do not rely on a vague "translate idiomatically". 训练采用 Rubric-as-Reward + GRPO，原生支持硬/软约束 / Rubric-as-Reward + GRPO yields native hard/soft constraint following.

| 类型 / Type | 判定 / Verdict | 用途 / Use |
| --- | --- | --- |
| 硬约束 / Hard | 一票否决 / veto | 术语、JSON/CSV 格式、占位符、社交元素（@、#、表情）/ terminology, format, placeholders, social tokens |
| 软约束 / Soft | 0 / 0.5 / 1 连续评分 / graded | 文风、领域消歧、跨句一致、指代 / style, domain, coherence, coreference |

核心杠杆在软约束：指定「什么样的意译是好的」/ Use soft constraints to define *what good means*.

### 2.2 instTrans 结构化格式 / instTrans Prompt Format

```
请将以下{源语言}{文体}翻译成{目标语言}，并且严格遵循所有约束要求。
〖源文〗
{源文本}
〖约束要求〗
1. 〖硬性要求〗{术语对照 / 格式保护项}
2. 〖注意〗{文风、领域、语气等软约束}
只输出译文，不要有任何额外说明。
```

结尾「只输出译文」是输出不变量 / "Output only the translation" is the output invariant.

### 2.3 软约束示例 / Soft Constraint Examples

- 口语 / 社媒：「采用社交媒体的轻松、网感风格，保留夸张语气和情绪强度；可适度玩梗，但不得改变核心语义。」
- 字幕 / 配音：「译文须在指定音节预算内完成意译，优先保证口语自然度和情绪还原，允许句式重组。」预算由 Index-Homura `--syllables` 控制（官方 81.92% 落在目标 ±10%）。
- 文学 / 典雅：「使用典雅、富有文学性的语言进行意译，优先保留修辞节奏和意象，允许为达意而调整句法。」

### 2.4 领域消歧 / Domain Disambiguation

显式声明 genre / State the domain explicitly：`The plant is operating at full capacity.` +「语境为工业制造领域，plant 应译为『工厂』而非『植物』」。

## 3. Agent 调用范式 / Calling Patterns

最小请求 / Minimal request（`POST /v1/chat/completions`）：`model=Index-Translate-35B-A3B`、`temperature=0`、`chat_template_kwargs.enable_thinking=false`、单条 user message 要求「直接输出译文，不要解释」。

结构化构造 / Structured builder：把 `genre / soft_notes / hard_terms` 注入 instTrans 模板；`hard_terms` 生成「专名/术语对照」，软约束描述文风与领域，结尾恒为「只输出译文」。

输出清洗 / Output hygiene：即便注入了 `enable_thinking=false`，仍剥离 `</think>` 残留并 `.strip()` / Strip residual `</think>` even with thinking disabled.

## 4. 错误码与降级 / Errors and Fallback

| 现象 / Symptom | 原因 / Cause | 处理 / Action |
| --- | --- | --- |
| 412 | WAF / CORS 预检 / WAF preflight | 不从浏览器直连；由服务端或本地代理发起 / server-side or local proxy |
| 429 / 5xx | 限速或过载 / rate limit or overload | 仅对 429/500/502/503/504 指数退避 / exponential backoff only for these |
| 401 / 403 | 端点拒绝（非 Key 问题）/ endpoint refusal, not auth | 视为不可用并降级 / treat as unavailable |
| 返回 CoT / CoT text | 漏传 `enable_thinking=false` | 检查参数注入链路 / check injection chain |

降级链 / Fallback chain：35B 免费公网 → 本地代理（自动注入两个强制参数）→ 自部署 9B/2B（vLLM / SGLang，Apache-2.0 权重）→ 备用翻译后端。高并发生产场景应自部署 / Self-host for production or high concurrency.

## 5. 检查清单 / Checklist

- ☐ 每个请求注入 `enable_thinking:false` / injected on every request
- ☐ 显式 `temperature:0` / explicitly set
- ☐ 服务端发起，不经浏览器 / server-side, no browser direct
- ☐ instTrans 承载硬/软约束 / instTrans carries constraints
- ☐ 意译通过软约束具体描述文风/领域/语气 / soft constraints specify style, domain, tone
- ☐ 配置 429/412/超时退避与降级 / backoff and fallback configured
- ☐ 输出清洗 `</think>` 残留 / strip residual `</think>`
- ☐ 高并发已评估自部署 / self-hosting evaluated

## 6. 本项目落地约束 / Project-Specific Constraints

`assets/i18n/*` 为 JSON 分片，含 `%@`、`$1`、`{name}`、`\n` 等占位符 / JSON shards contain placeholders. 这些是**硬约束**：译文必须逐字保留占位符与 JSON 转义，不得增删键 / Placeholders and JSON escapes are hard constraints; keys must not change. 软约束统一为「移动端软件界面文案，正式、简洁、克制；按目标语言习惯表达，不逐字硬译」/ Soft constraint: mobile-app UI copy, formal, concise, idiomatic rather than word-for-word. 长文本（法律声明）用 9B 分片，短界面文案用 35B 保证占位符稳定 / 9B for long legal text in chunks, 35B for short UI strings to protect placeholders. 每个分片译后校验键集合、值类型与占位符多重集 / Validate key set, value types and placeholder multiset after every shard.
