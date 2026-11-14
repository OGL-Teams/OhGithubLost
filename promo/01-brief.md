# OGL 宣传片 · 创意简报（01-brief）· v3 · M3 / 极客向

> 2026-11-15 更新。受众与设计方向均已按反馈修正。

## 1. 受众（修正）

**已经会用 GitHub 的开发者与尝鲜极客**。判断依据：需要找 GitHub 客户端的人，先得知道仓库、Issue、PR、Release、Actions 是什么。因此：

- 不做「小白教学」（「装上就登录」「不用配环境」这类话已全部删除）；
- 直接说清能力边界、约束与代价，用可核对的数据而不是形容词；
- 允许出现 `layer_audit.py --fatal`、`dart2wasm`、`glibc ≥ 2.35` 这类术语——这是目标读者的日常语言。

语气：**正式、克制、可核验**。不喊口号，不用「重新定义」「丝滑」之类营销词。

## 2. 设计系统（Material Design 3，强制）

用户明确指出「圆角过多、完全没有遵循 Material Design」。本轮以 M3 规范重建，令牌集中在 `promo/index.html`：

| 维度 | 落地 |
|---|---|
| 色彩 | M3 角色：`surface` / `surface-container-low…highest` / `on-surface` / `on-surface-variant` / `outline` / `outline-variant` / `primary` / `primary-container` / `tertiary` / `error`；主色浅蓝 `#A9C7FF`（seed `#0969DA`），强调琥珀 `#E3B341` |
| 字型 | M3 type scale 取 8 档：display 96 / headline 56 / title 32 / title-m 26·500 / body 24 / body-m 22 / label 22·500 / label-m 20·500；Roboto 为界面字，数据用仓库自带 Ubuntu Mono |
| 形状 | corner scale：none 0 / xs 4 / sm 8 / md 12 / lg 16 / xl 28；**卡片 12、Chip 8、截图框 8、分隔 0**；不使用 20/22/24 与无差别 999 胶囊 |
| 高度 | 用 surface-container 分级表达层级，1px `outline-variant` 描边；删除 `0 24px 70px` 类重投影 |
| 间距 | 8dp 网格（8/16/24/32/48/64/96），页面边距 96 |
| 动效 | 只 tween transform / opacity / clipPath；缓动 `power2/3/4.out`；卡点为 8% / 16% primary 状态层叠加，不做缩放抖动 |

## 3. 内容结构（每屏一个论点 + 硬数据）

| 场景 | 论点 | 数据锚点 |
|---|---|---|
| s1 | GitHub 工作流在本地完成 | 4 平台 / 6 语言 / 跨层越级 0 |
| s2 | 仓库与代码的完整编辑链路 | 29 个页面模块 / 4 层依赖 / 0 越级 / 草稿自动持久化 |
| s3 | 五条工作流共用状态模型 | #1284 bug open / diff +342 −87 / v12.6.9 23 产物 / run #892 1m42s / 6 片段；`12.6.3 → 12.6.9 · 7 天 7 版 · 18 道门禁` |
| s4 | 四层单向依赖 | `surface → domain → base → kernel`，`0 violations` |
| s5 | 失败分类可见、凭据本地 | 429 → retry 2/3 · backoff 800ms → 200 OK 241ms；DoH · 指数退避 · 限流避让 |
| s6 | 6 语言与 4 档动效是可验证契约 | i18n 六目录；动效 静默/保守/标准/拉满 |
| s7 | 4 平台 23 个产物 | 4 ABI + AAB / x64·arm64 / deb·rpm·AppImage / dart2wasm |
| s8 | 交付入口 | `github.com/OGL-Teams/OhGithubLost`、v12.6.9、Apache-2.0 |

以上数据全部来自仓库 README、`docs/ARCHITECTURE.md`、`changed/_posts` 与实机截图，无编造。

## 4. 素材

- 实机截图：`01-home` / `02-discover` / `03-profile` / `04-settings`（`05-about` 暂不上片，端卡不放缩略图）。
- 仓库资产：Ubuntu Mono 字体、`ogl_icon.svg`。
- 音轨：HOYO-MiX《子不语 Wordless》28–84s 裁段，卡点见 `06-music-plan.md`。

## 5. 风险

- 歌曲版权未确认，正式对外投放前必须授权或切回 `bgm.wav`。
- 截图含 `@yingo-server` 账号名与通知条目，公开前建议处理。
- 竖屏截图在横屏舞台上只作局部证据，不伪装成桌面 UI。
