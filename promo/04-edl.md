# 04 · EDL

单根合成 `compositions/credits.html`，时间域 `[0, 175.082)`，30fps。

| 轨道 | 类型 | 内容 | 区间 |
|---|---|---|---|
| 1 | graphics credits | OGLHeiti 文字流，16 条，居中上滚 | 0 → 175.082s |
| 9 | audio | `yancigui-25.m4a`，原音量 25% 已固化 | 0 → 175.082s |

其余轨道为空。四幕仅作为数据分组，不映射为轨道、不上屏。

**滚动公式**：`y(t) = H/2 − v·t`，`v = D / T`，`T = 175.082s`，`D` 为从首行中心到末行完全离屏的位移。每步高 `2h`（`h` 为行高），故条间空一整行字高；第一行在 t=0 位于画面中心。`v` 恒定，无缓动。

**片长校验**：CI 对音轨与成片各做一次 ffprobe，`|duration − 175.082| ≤ 0.5s`；不满足即失败。

**CI 产物**：`OGL-Credits.mp4`（1080p）、`OGL-Credits-720p.mp4`（CRF23）、`contact-sheet.jpg`（fps=1/10 · tile 3x3）、`OGL-Credits.7z`（−mx=9）、`SHA256SUMS.txt`、`lint.json`、`check.json`。
