# OGL 宣传片 · 交付说明（05-delivery）· v2

## 分支与产物

| 项 | 值 |
|---|---|
| 专用分支 | `video` |
| CI 工作流 | `.github/workflows/promo-render.yml` |
| 触发 | push 到 video / main / promo\/**（限 `promo/**` 与 workflow 变更）、手动 dispatch |
| tag | `promo-<sha7>`，每次 video 分支渲染成功自动创建并推送 |
| Release | 同 tag，附带 4 个文件 |
| 成片 | `OGL-Promo.mp4`（56s / 1920×1080 / 30fps / H.264 CRF16 + Wordless 混音，约 11.9 MB） |
| 轻量版 | `OGL-Promo-720p.mp4`（1280×720 / CRF23 / preset slow / faststart，体积约为 1080p 的 30–40%，用于移动端与聊天分发） |
| 压缩包 | `OGL-Promo.7z` — **7-Zip `-mx=9 -m0=LZMA2 -md=64m -mmt=on` 极限压缩**，含两个成片、联系表、lint/check、EDL、交付文档 |
| 联系表 | `contact-sheet.jpg`（每 6 秒一帧，3×3） |
| 校验 | `SHA256SUMS.txt` |
| 诊断 | `lint.json`（硬门禁，0 error）、`check.json`（运行时/布局诊断） |

## 源文件

```
promo/
├── index.html                 # 根：8 场景 + 7 卡点闪层 + 主/备音轨 + 暗角
├── compositions/s1-hook.html … s8-end.html
├── assets/screens/01-home.png … 05-about.png   # 5 张 Android 实机截图
├── assets/fonts/              # UbuntuMono-Regular/Bold.ttf
├── assets/ogl_icon.svg        # 仓库原图标
├── assets/vendor/gsap.min.js  # GSAP 3.14.2 本地副本
├── assets/audio/wordless-56s.mp3  # HOYO-MiX《子不语 Wordless》28–84s 裁段
├── assets/audio/bgm.wav       # 96 BPM 合成备用轨
├── assets/audio/bgm-beats.json
├── scripts/make_bgm.py        # 确定性 BGM 生成器（seed 20261114）
├── package.json / meta.json
├── 01-brief.md · 02-storyboard.md · 03-asset-plan.md
├── 04-edl.md · 06-music-plan.md · 07-motion.md · 05-delivery.md
```

## 本地修改方式

```bash
python3 promo/scripts/make_bgm.py        # 改备用音乐后须同步提交 wav
npm --prefix promo run lint              # 静态门禁（不需浏览器）
npm --prefix promo run check             # 运行时/布局/对比度（需 Chromium）
npm --prefix promo run render            # 本地出片（ARM64 需 HYPERFRAMES_BROWSER_PATH）
```

改主音轨：替换 `assets/audio/wordless-56s.mp3` 并同步 `index.html` 的 `#bgm src`；若切回合成 BGM，把 `#bgm` 与 `#bgm-fallback` 的 `data-volume` 对调即可，画面无需改动。
改卡点：同时调整 root 的 `cuts` 数组、8 个 host 的 `data-start`/`data-duration`、各子场景的 wipe 绝对时间、`02-storyboard.md` 与 `04-edl.md`。

## 已知限制

1. **音乐授权**：《子不语 Wordless》版权归原权利人，仅用于本次样片评估。正式对外投放前必须确认授权，或切回 `bgm.wav`（已在工程内保留为零改动备用方案）。
2. **截图隐私**：5 张实机图含 `@yingo-server` 账号名与通知条目；对外发布前建议打码或确认可公开。
3. **示意重绘**：s3/s4/s5/s6/s7 的卡片、架构、节点、滑块、平台轮廓是代码绘制，用于表达关系，不冒充应用界面；s2/s5/s6/s8 已用真实截图作为主证据。
4. **桌面端无截图**：只有 Android 竖屏实机图，s7 平台卡仍是矢量示意。
5. **本地 ARM64 渲染环境**：HyperFrames 0.9.46 的 `browser ensure` 误判 linux-arm64 无 Chrome 构建（实际 Chrome for Testing Stable 157 已提供 `chrome-headless-shell-linux-arm64.zip`）；本地可装 Alpine `chromium` 并设 `HYPERFRAMES_BROWSER_PATH=/usr/bin/chromium`。正式出片统一在 CI 的 ubuntu-latest 完成，CI 显式安装 `ffmpeg`、`p7zip-full`、`fonts-noto-cjk`。
6. **中文字体**：CI 已装 Noto CJK；本地缺 CJK 字体会出现豆腐块。
7. **无配音**：全片只有音乐与画面，无旁白与字幕。
8. **`timeline_track_too_dense` 警告**：单文件同轨道元素较多的可维护性建议，不影响渲染。
9. **BGM 复现性**：CI 重算 `bgm.wav` 并与提交产物逐字节比对；升级 numpy / 改算法时须同时提交新 wav。
10. **设计系统**：全片按 Material 3 令牌实现（`index.html` 第 12–120 行为唯一来源）：形状仅 0/4/8/12、M3 type scale、surface-container 分级、零投影；动效规范见 `07-motion.md`。
11. **压缩边界**：1080p 源片已是 H.264 CRF16，7-Zip 对视频流几乎无收益（实测 11.86 MB → 11.76 MB）；要显著减体积请用 `OGL-Promo-720p.mp4`。
