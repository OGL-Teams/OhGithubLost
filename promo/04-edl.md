# OGL 宣传片 · EDL（04-edl）· v2 · Wordless 卡点版

主编辑文件：`promo/index.html`
渲染目标：1920×1080 / 30 fps / 56.000 s / H.264 MP4 + AAC 音轨
定位：新手开发者 + 尝鲜极客

| 轨道 | 类型 | 内容 |
|---|---|---|
| 1 | graphics | 8 个 scene host，见下表 |
| 7 | graphics | `#beat-flash` — 7 个真实 onset 上的品牌蓝脉冲 |
| 8 | graphics | `#vignette` 暗角 + `#grain` 扫描线（全片静态） |
| — | 转场 | 每场景 `#sN-stage` 的 M3 shared axis X：入场 x:+80→0（0.42s power4.out），出场 x:0→-80（0.26s power3.in） |
| 9 | audio | `#bgm` ← `assets/audio/wordless-56s.mp3`，volume 0.92 |
| 10 | audio | `#bgm-fallback` ← `assets/audio/bgm.wav`，volume 0（备用，不参与混音） |

## 场景时间线（对齐 onset）

| In | Out | 场景 ID | 局部时长 | 文件 | 切点依据 |
|---|---|---|---|---|---|
| 00:00.000 | 00:06.800 | s1-hook | 6.8 | `compositions/s1-hook.html` | 6.79s 强拍 |
| 00:06.800 | 00:14.100 | s2-repo | 7.3 | `compositions/s2-repo.html` | 14.10s 强拍 |
| 00:14.100 | 00:23.000 | s3-collab | 8.9 | `compositions/s3-collab.html` | 23.03s 强拍 |
| 00:23.000 | 00:32.200 | s4-layers | 9.2 | `compositions/s4-layers.html` | 32.23s 强拍 |
| 00:32.200 | 00:40.200 | s5-trust | 8.0 | `compositions/s5-trust.html` | 40.25s 强拍 |
| 00:40.200 | 00:46.200 | s6-i18n | 6.0 | `compositions/s6-i18n.html` | 46.23s 强拍 |
| 00:46.200 | 00:52.300 | s7-platforms | 6.1 | `compositions/s7-platforms.html` | 52.33s 强拍 |
| 00:52.300 | 00:56.000 | s8-end | 3.7 | `compositions/s8-end.html` | 末帧静止 1.5s |

时长校验：6.8 + 7.3 + 8.9 + 9.2 + 8.0 + 6.0 + 6.1 + 3.7 = **56.0**。

## 卡点结构

每个切点 `t`：

1. `t - 0.42s`：上一场景 `#sN-stage` 向左退出（x 0→-80，opacity 1→0，0.26s power3.in）。
2. `t`：根 `#beat-flash` 按弱/强拍叠加 primary 8% / 16% 状态层；新场景 host 起。
3. `t + 0.1~0.9s`：新场景主体 stagger 入场。

根 timeline 只驱动 `#beat-flash`，从不 add 子场景 timeline；runtime 按 host 的 `data-start` 各自 seek。

## 渲染与交付

```bash
# 本地
python3 promo/scripts/make_bgm.py       # 复现备用音轨
npm --prefix promo run lint             # 静态硬门禁
npm --prefix promo run render           # 本地出片（ARM64 需 HYPERFRAMES_BROWSER_PATH）

# CI（video 分支自动）
# 1. ffmpeg / p7zip-full / fonts-noto-cjk
# 2. lint 0 error → render MP4 → contact sheet
# 3. 7z a -t7z -mx=9 -m0=LZMA2 -md=64m → OGL-Promo.7z
# 4. git tag promo-<sha7> + GitHub Release（含 7z、MP4、联系表、SHA256SUMS）
```

## 剪辑契约自检

- 根 `data-duration="56"` 等于 8 个 host 时长之和。
- 每个 `.clip` 有 `data-start` / `data-duration` / `data-track-index`；图片路径 `assets/screens/...`。
- 每个 scene 的 host id == `data-composition-id` == `window.__timelines` key。
- 每个子 composition 一条 `gsap.timeline({paused:true})`；wipe 目标侧显式 `opacity: 1`。
- 无 `Date.now()` / `Math.random()` / fetch / timer / `repeat:-1`；一律 `fromTo`。
