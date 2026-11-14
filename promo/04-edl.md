# OGL 宣传片 · EDL（04-edl）

主编辑文件：`promo/index.html`（HyperFrames 根 composition）
渲染目标：1920×1080 / 30 fps / 56.000 s / H.264 MP4 + AAC 音轨

| 轨道 | 类型 | 内容 |
|---|---|---|
| 1 | graphics | 8 个 scene host，见下表 |
| 8 | graphics | `#vignette` 暗角 + `#grain` 扫描线（全片静态） |
| 9 | audio | `#bgm` ← `assets/audio/bgm.wav`，data-volume 0.85 |

## 场景时间线

| In | Out | 场景 ID | 文件 | 主转场 |
|---|---|---|---|---|
| 00:00.000 | 00:06.000 | s1-hook | `compositions/s1-hook.html` | clipPath wipe ↑ |
| 00:06.000 | 00:14.000 | s2-repo | `compositions/s2-repo.html` | camera push 0.55s + wipe ↑ |
| 00:14.000 | 00:23.000 | s3-collab | `compositions/s3-collab.html` | 卡片 stagger + wipe ↑ |
| 00:23.000 | 00:32.000 | s4-layers | `compositions/s4-layers.html` | 层块堆叠 + wipe ↑ |
| 00:32.000 | 00:40.000 | s5-trust | `compositions/s5-trust.html` | 连线 trace + wipe ↑ |
| 00:40.000 | 00:46.000 | s6-i18n | `compositions/s6-i18n.html` | 滑块 + wipe ↑ |
| 00:46.000 | 00:52.000 | s7-platforms | `compositions/s7-platforms.html` | 弧形散开 + wipe ↑ |
| 00:52.000 | 00:56.000 | s8-end | `compositions/s8-end.html` | 图标 fill-rise，末帧静止 1.5s |

## 音画对齐点（BGM impact）

`6 / 14 / 23 / 32 / 40 / 46 s` 为 impact 点，与场景切换一致；`4.6 / 12.6 / 21.6 / 30.6 / 38.6 / 44.6 s` 为 1.4s riser，位于每次切换前。

## 渲染命令

```bash
# 本地（ARM64 需 HYPERFRAMES_BROWSER_PATH 指向 Chromium / headless-shell）
python3 promo/scripts/make_bgm.py
npm --prefix promo run check
npm --prefix promo run render

# CI：.github/workflows/promo-render.yml 在 ubuntu-latest 自动完成
```

## 剪辑契约自检

- 根 `data-duration="56"` 与所有子场景时长之和一致（6+8+9+9+8+6+6+4 = 56）。
- 每个 `.clip` 有 `data-start` / `data-duration` / `data-track-index`。
- 每个 scene 的 host id == `data-composition-id` == `window.__timelines` 的 key。
- 每个子 composition 一条 `gsap.timeline({paused:true})`，未 add 到根 timeline。
- 无 `Date.now()` / `Math.random()` / fetch / timer / `repeat:-1`；不用 `from`（一律 `fromTo`，seek 安全）。
