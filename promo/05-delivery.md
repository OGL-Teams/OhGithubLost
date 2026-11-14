# OGL 宣传片 · 交付说明（05-delivery）

## 分支与产物

| 项 | 值 |
|---|---|
| 专用分支 | `video` |
| CI 工作流 | `.github/workflows/promo-render.yml` |
| 触发 | push 到 video / main / promo\/**（限 `promo/**` 与 workflow 文件变更）、或手动 dispatch |
| 成片 | CI artifact `OGL-Promo.mp4`（56s / 1920×1080 / 30fps / H.264 + 代码合成 BGM） |
| 联系表 | CI artifact `contact-sheet.jpg`（每 6 秒一帧，3×3） |
| 诊断 | `lint.json`（硬门禁，0 error）、`check.json`（运行时/布局诊断） |

## 源文件

```
promo/
├── index.html                 # 根 composition：8 场景 + BGM + 暗角/扫描线
├── compositions/s1-hook.html  … s8-end.html
├── assets/fonts/              # UbuntuMono-Regular/Bold.ttf（仓库原样复制）
├── assets/ogl_icon.svg        # 仓库 assets/icon/ogl_icon.svg
├── assets/vendor/gsap.min.js  # GSAP 3.14.2 本地副本（离线可渲染）
├── assets/audio/bgm.wav       # 96 BPM 代码合成音轨
├── assets/audio/bgm-beats.json
├── scripts/make_bgm.py        # 确定性 BGM 生成器（seed 20261114）
├── package.json / meta.json
├── 01-brief.md · 02-storyboard.md · 03-asset-plan.md
├── 04-edl.md · 06-music-plan.md
└── 05-delivery.md（本文件）
```

## 本地修改方式

```bash
python3 promo/scripts/make_bgm.py        # 改音乐后重生成（须同步提交 wav）
npm --prefix promo run lint              # 静态门禁（不需浏览器）
npm --prefix promo run check             # 运行时/布局/对比度（需 Chromium）
npm --prefix promo run render            # 本地出片（ARM64 需 HYPERFRAMES_BROWSER_PATH）
```

改文案：`index.html` 的 `data-composition-variables` 与各 `compositions/*.html` 内的 `data-var-text` 绑定元素。
改节奏：同时调整 root 的 `data-duration`、各 host 的 `data-start`/`data-duration`、子场景 timeline 的绝对秒位置、`scripts/make_bgm.py` 的 `DUR` 与 impact 点。

## 已知限制

1. **示意重绘，非应用截图**：仓库无应用截图/录屏，`s2-repo` 的窗口骨架是依据真实页面文件名与 README 功能描述用 HTML 重绘的。所有标签、文件名、目录名、门禁脚本名均取自代码，未虚构控件功能；若日后补到真实截图，应替换该场景。
2. **本地 ARM64 渲染环境**：HyperFrames 0.9.46 的 `browser ensure` 误判 linux-arm64 无 Chrome 构建（实际 Chrome for Testing Stable 157 已提供 `chrome-headless-shell-linux-arm64.zip`）；本地可装 Alpine `chromium` 并设 `HYPERFRAMES_BROWSER_PATH=/usr/bin/chromium`。正式出片统一在 CI 的 ubuntu-latest 上完成，避免跨环境字体/编码差异。
3. **中文字体**：CI 已安装 `fonts-noto-cjk`；本地若缺 CJK 字体会出现豆腐块，需自行安装。
4. **无配音**：需求未要求，全片只有 BGM 与画面，无旁白与字幕。
5. **BGM 可复现性受 numpy 版本影响**：CI 会重算 wav 并与提交产物逐字节比对；升级 numpy / 改算法时须同时提交新 wav。
6. **`timeline_track_too_dense` 警告 4 条**（s5/s6/s7 单文件同轨道元素较多）：仅为可维护性建议，不影响渲染，未拆分以免引入额外的 composition 挂载复杂度。
