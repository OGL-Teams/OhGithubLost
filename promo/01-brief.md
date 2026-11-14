# OGL 宣传片 · 创意简报（01-brief）

> 生成日期：2026-11-14 · 依据 OhGithubLost 仓库 40b7831 真实信息

## 1. 产品定位

OhGithubLost（OGL）是一款基于 Flutter 的 GitHub 仓库管理客户端，把仓库浏览与提交、Issues / PR / Releases / Actions / Gist 协作从浏览器搬进本地应用窗口。支持 Android · Windows · Linux · Web 四平台，macOS/iOS 已弃用。

**一句话**：GitHub 的日常，不必打开浏览器。

## 2. 目标观众

开源项目维护者、多仓库/多账号协作的开发者、需要离线草稿与可靠下载的工程团队。他们反感"看起来能用、失败时静默降级"的工具。

## 3. 核心卖点与证明点（全部来自 README/代码，不虚构）

| 卖点 | 可验证证明 |
|---|---|
| 全功能仓库操作 | 目录树 / 文件预览 / 新建编辑删除重命名 / 提交与冲突处理；`lib/surface/pages/` 下 29 个页面 |
| 协作面板 | Issues · PR 差异 · Releases 附件 · Actions 日志 · 工作流手动触发 · Gist |
| 令牌安全 | 仅存系统密钥库，界面日志脱敏，退出即删 |
| 网络韧性 | DoH / 自动重试 / 限流避让；失败如实报错，不静默降级；加速通道默认关闭且不预置 |
| 工程可信 | 五层架构 `kernel → base → domain → surface`，依赖方向由 `tool/layer_audit.py --fatal` 强制 |
| 国际化 | 6 种语言，文案零硬编码由 CI 强制校验；`assets/i18n/` 下 de/en/fr/ru/zh/zh_Hant |
| 动效分级 | 静默/保守/标准/拉满四档，降档降开销不删效果 |
| 多平台 | Android 4 ABI + AAB、Windows x64/arm64、Linux deb/rpm/AppImage、Web (dart2wasm) |

## 4. 视觉风格（用户指定：流畅动画风格）

- **基调**：GitHub 深蓝 (#0D1117) + 品牌蓝 (#0969DA，取自 `kOgLSeedColor`) + 冷白 (#E6EDF3)，琥珀色 (#E3B341) 作状态强调。
- **字体**：仓库自带 `UbuntuMono`（复制进 `assets/fonts/`），代码与数据用等宽；标题用系统 sans 作对比。
- **动效语言**：连续 camera push（0.4–0.6s）、元素 morph 而非硬切、GSAP `power3/power4.out` 缓动、所有位移只用 transform、元素错峰入场（stagger 0.06–0.12s）。禁止弹跳/回弹 overshoot，保持"顺滑"。
- **画面证据**：不虚构 UI 控件。用真实页面/文件名（`repo_page.dart` / `dashboard_page.dart`）、真实架构层次、真实 CI 门禁名、真实 i18n 目录绘制可核对的界面示意与代码流。

## 5. 叙事结构（56 秒 / 30fps / 1920×1080）

Hook → Tension → Reveal → Proof ×3 → Payoff → End card。段落切换对齐 BGM 的 96 BPM 网格与 6 个 impact 点（6/14/23/32/40/46s）。

## 6. 风险与缺口

- 仓库无应用截图、无 Logo 位图（仅 `assets/icon/ogl_icon.svg`），因此不采用"真实界面录屏"路线，改用**代码重绘的可核对界面骨架 + 真实文件名/标签**，并在交付说明中标注为示意重绘而非截图。
- 本地 ARM64 无 Chrome Headless Shell 官方构建 → 本地只做 lint/短帧冒烟，正式出片由 `.github/workflows/promo-render.yml` 在 ubuntu-latest 完成。
- 无配音（未要求）；BGM 为纯代码合成，无版权风险。
