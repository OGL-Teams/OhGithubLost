# OGL 宣传片 · 创意简报（01-brief）· Three.js 一镜到底

> 按 `promo-creator-skills` 流程重做。用户最新要求：Three.js 3D 宣传片、一镜到底、时长由 BGM 决定、整体亮色且灵动。

## 1. 输入与决策

| 项 | 值 |
|---|---|
| 产品 | OhGithubLost（OGL）· GitHub 仓库管理客户端 |
| 受众 | 已会 GitHub 的开发者 / 尝鲜极客 |
| 技能包 | `/promo-creator-skills`：brief → storyboard → assets → EDL → music → delivery |
| 渲染引擎 | HyperFrames 0.9.46 + Three.js（本地 vendor，离线可渲染） |
| 视觉 | **亮色 M3**：`#F7F9FC` 底面、`#FFFFFF` 面板、`#0B57D0` 主色、`#B26A00` 琥珀证据色 |
| 结构 | **单个相机连续飞行**，无 scene host、无切镜、无 wipe、无黑场 |
| BGM | HOYO-MiX《月宫试云衣 The Lunar Palace Draped in Clouds》完整曲目 |
| 片长 | **175.01s**（源曲 175.007979s，不裁切；转码后 175.046531s） |
| 分辨率 | 1920×1080 / 30fps |

## 2. 一句话主张

**GitHub 工作流，在本地完成。** 镜头不给口号，而是带观众沿着一条 3D 长廊穿过 11 个功能站点；每个站点是一块可读面板 + 一张真实手机截图。

## 3. 为什么是 3D 一镜到底

上一版被否：页面切换死板、动画无力、片头黑屏。3D 单相机天然解决这三点：

- 无切换：相机 z 从 `+34` 连续飞到 `-158`，站点沿 Z 轴排布，靠"经过"而不是"切到"。
- 有物理感：低频正弦漂移、近站点 scale 0.94→1.00、雾距随乐段呼吸、曝光在 90–160s 微升。
- 第 0 帧不黑：亮色地面、网格、导轨、HUD、第一块面板已经在相机视野里。

## 4. 证据（全部真实）

- 12 张 Android 实机截图：仓库 / 代码 / 编辑器 / Issue / 日志 / DNS / 法律 / 首页 / 发现 / 我的 / 设置 / 关于。
- 数字均来自截图或仓库：`index.html 1.2 KB`、`README.md 22 B`、`55 行 · 1243 字符 · UTF-8`、`#42281 · 37 条评论`、`7946ms / 7556ms / 313ms`、`16 连接`、`23 个产物`、`致谢 18`。
- 3D 文字面板由 `scripts/bake_panels.py` 用本地 Noto Sans CJK 烘焙为 PNG 提交进仓库；CI 不依赖任何 CJK 字体渲染 3D 文字。

## 5. 风险与边界

- 《月宫试云衣》版权归原权利人，仅内部样片；正式投放须授权或换曲。
- Three.js WebGL 依赖官方 Chrome；本地 ARM64 Alpine Chromium 在 PRoot 下启动超时，因此以 CI 渲染为准。
- 3D 面板只做极轻微 `rotation.y`（≤0.045rad），保证文字可读，不把产品 UI 斜成装饰。
- 没有路径追踪：用 raster + 阴影 + 三盏灯，保证 175s / 5250 帧可在 CI 时间内完成。
