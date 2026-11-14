# OGL 宣传片 · 配乐方案（06-music-plan）· v2

## 采用：HOYO-MiX《子不语 Wordless》卡点混音

| 项 | 值 |
|---|---|
| 来源 | `/var/minis/mounts/Tiernan_Music/HOYO-MiX - 子不语 Wordless.mp3.mp3` |
| 源文件 | 132.19s，FLAC-in-MP3 容器，48kHz 双声道，~1.65 Mbps |
| 裁段 | 28.0–84.0s，共 56.0s |
| 工程文件 | `assets/audio/wordless-56s.mp3`（44.1kHz 立体声，192 kbps，1.3 MB） |
| 音量 | `data-volume="0.92"` |
| 用途 | 全片主音轨；原合成 BGM 降为备用轨（volume 0） |

### 为什么取 28–84s

8kHz 单声道频谱通量分析显示：0–2s 是弱引入（rms 0.048），14–22s 有明显能量台（0.22–0.23），38–52s 是主副歌峰（0.28–0.41）。裁段把「起 → 推进 → 爆发 → 收束」压进 56s，正好覆盖 Hook 到 End card，不需要人为做 drop。

### 卡点分析（确定性，可复算）

```
ffmpeg -i <wordless> -ac 1 -ar 8000 -f f32le cut8k.f32
# 80-sample hop / 1024 窗 → RMS 包络 → 一阶正差分 → 7 点平滑 → 局部峰值
# 阈值 = 80 分位，最小间隔 0.19s
```

得到 106 个强 onset；主间隔 0.34s（≈176 BPM 的八分律动感）。

**场景切点（全局秒）**：`0 / 6.8 / 14.1 / 23.0 / 32.2 / 40.2 / 46.2 / 52.3 / 56`
对应裁段内实测强拍：`6.79 / 14.10 / 23.03 / 32.23 / 40.25 / 46.23 / 52.33`。

根 composition 在 7 个切点执行：

```js
tl.fromTo("#beat-flash", { opacity: 0 },
  { opacity: 0.55, duration: 0.07, ease: "power2.out" }, t);
tl.to("#beat-flash", { opacity: 0, duration: 0.24, ease: "power2.in" }, t + 0.07);
```

闪层是品牌蓝径向光（z-index 89，在暗角之下），只做节奏提示，不遮挡文字。子场景的 wipe 也落在切点前 0.5s，形成「画面先收、鼓点落下、新场景展开」的三拍结构。

### 画面密度与能量对齐

| 段落 | 音乐 rms | 画面策略 |
|---|---|---|
| 0–14s | 0.05→0.20 | 稀疏：标题 + 两张实机图，留白多 |
| 14–32s | 0.21→0.23 | 中密度：五卡 + 四层架构，stagger 加密 |
| 32–40s | 0.12→0.14 | 收一拍：失败标记停留 1.2s，让「如实可见」被读到 |
| 40–52s | 0.33→0.35 | 高密度：滑块 + 四平台同时散开 |
| 52–56s | 0.23 | 静止 End card，音尾自然收束 |

## 备用方向：Clean UI Demo Groove（代码合成，保留）

`scripts/make_bgm.py` 仍会生成 96 BPM / Am–F–C–G / 56s 的 `bgm.wav`，CI 逐字节复现校验。若 Wordless 授权无法确认，把 `index.html` 里两个 `<audio>` 的 `data-volume` 对调即可切回，无需改任何画面。

## 版权

《子不语 Wordless》版权归 HOYO-MiX 及权利人所有。工程内 `wordless-56s.mp3` 仅随 `video` 分支用于本次内部样片评估；**正式对外发布前必须确认授权，或切回合成 BGM**。这条不是可选项。

## 第三方音乐 prompt（若日后换原创编曲）

**English prompt**: "Instrumental cinematic pop with Chinese orchestral color, 56 seconds, gentle intro, steady mid-section, largest chorus at 38–52s, strong percussive onsets at 6.8/14.1/23.0/32.2/40.2/46.2/52.3s, no vocals, no EDM drop, suitable for a beginner-friendly developer tool promo."
**Negative prompt**: "vocal chops, trap hats, big trailer brass, tempo changes, fade-out before end card".
