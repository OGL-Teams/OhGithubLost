# OGL 宣传片 · 交付说明（05-delivery）· 3D One-Shot

## 成片

| 项 | 值 |
|---|---|
| 分支 | `video` |
| 技术栈 | HyperFrames 0.9.46 + Three.js（本地 vendor）+ GSAP（空 timeline 注册） |
| 结构 | **单个 canvas / 单相机 / 一镜到底 / 零切镜 / 零黑场** |
| 时长 | **175.01s**，由 BGM《月宫试云衣》完整长度决定，不裁切 |
| 分辨率 | 1920×1080 / 30fps；另出 720p 轻量版 |
| 压缩包 | `OGL-Promo.7z`，7-Zip `-mx=9 -m0=LZMA2 -md=64m -mmt=on` |
| tag | `promo-<sha7>`，每次 video 分支渲染成功自动打 tag + Release |

## 关键源文件

```
promo/
├── index.html                    # 单个 WebGL canvas + HUD + BGM
├── assets/one-shot.js            # Three.js 场景、相机路径、hf-seek 纯函数
├── assets/three/                 # three.module.min.js / three.core.min.js / LICENSE
├── assets/vendor/gsap.min.js
├── assets/audio/bgm-lunar.mp3    # 175.01s 主音轨
├── assets/panels/panel-00..10.png# 烘焙中文面板（CJK 不依赖 CI 字体）
├── assets/screens/01..12.png     # 12 张 Android 实机截图
├── scripts/bake_panels.py        # 面板烘焙器（本地运行，PNG 入库）
├── 01-brief.md · 02-storyboard.md · 03-asset-plan.md
├── 04-edl.md · 06-music-plan.md · 07-motion.md
└── 08-architecture.md            # 2D 重构的历史记录，当前不参与渲染
```

`compositions-2d-archive/` 是上一版 180s 多场景 HTML，已归档，不参与 lint / render。

## 本地修改方式

```bash
python3 promo/scripts/bake_panels.py       # 改面板文案后重烘焙
npm --prefix promo run lint                # 静态门禁（不需 WebGL）
npm --prefix promo run render              # 官方 Chrome 环境
```

改相机节奏：只动 `assets/one-shot.js` 的 `poseAt(t)`。改站点：动 `STATIONS` 数组 + 对应面板贴图。改片长：必须同步 BGM、`index.html` 的 4 个 `data-duration`、audio duration、`one-shot.js` 的 `DUR`、EDL 与 workflow 校验。

## 已知限制

1. **音乐授权**：《月宫试云衣》版权归原权利人；仅内部样片，正式投放须授权或换曲。
2. **WebGL 环境**：本地 ARM64 Alpine Chromium 在 PRoot 下启动超时；正式出片只认 CI 的 ubuntu-latest Chrome + SwiftShader。
3. **截图隐私**：实机图含 `@yingo-server` 账号名与通知条目，公开前建议处理。
4. **3D 可读性**：面板只做 ≤0.045rad 的轻微倾斜；不把产品 UI 当装饰块旋转。
5. **无配音 / 无字幕**：全片靠 3D 面板与 HUD 承载文字。
6. **lint warning**：`nested_structure_needs_subcomposition` 1 条（HUD 进度条内嵌填充 div），仅为可维护性建议，不影响渲染。
