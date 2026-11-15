# OGL 宣传片 · 配乐（06-music-plan）· 3D One-Shot

## 采用曲目

| 项 | 值 |
|---|---|
| 曲目 | HOYO-MiX《月宫试云衣 The Lunar Palace Draped in Clouds》 |
| 来源 | `/var/minis/mounts/Tiernan_Music/HOYO-MiX - 月宫试云衣 The Lunar Palace Draped in Clouds.mp3.mp3` |
| 源时长 | 175.007979s |
| 工程文件 | `assets/audio/bgm-lunar.mp3`，44.1kHz 立体声 / 192 kbps / 175.046531s |
| 片长 | **175.01s，由 BGM 长度决定，不做裁切** |
| 混音 | 全曲贯穿，无淡入淡出，无节奏切点 |

## 为什么不做卡点

上一版的卡点闪层把画面切成 7 段，被否为"页面切换死板"。这一版是单相机连续飞行：鼓点不该把镜头切碎。音乐只承担两件事：

1. 提供 175s 的时间长度；
2. 提供一条自然的情绪曲线，画面用**连续参数**跟随。

## 画面与能量对齐（连续，不打点）

| BGM 区间 | 画面连续参数 |
|---|---|
| 0–90s | 雾 near 42 / far 170，曝光 1.06；亮色、平稳、可读 |
| 90–120s | `smoothstep(90,120,t)` 抬升；雾 near → 50、far → 188，曝光 → 1.14 |
| 120–160s | 保持略亮的空气感，站点密度不变 |
| 160–175s | `1 - smoothstep(160,175,t)` 回落；片尾回到干净白蓝 |

这是连续的 `toneMappingExposure` / `Fog.near` / `Fog.far` 变化，不是转场、不是闪层、不是切镜。

## 版权

曲目版权归 HOYO-MiX 及权利人。工程内 `bgm-lunar.mp3` 仅随 `video` 分支用于内部样片评估；正式投放前须确认授权或换曲。换曲时片长必须重算：`index.html` 的 `data-duration`、所有 clip 的 `data-duration`、audio 的 `data-duration`、`one-shot.js` 的 `DUR`、EDL 与 workflow 校验值要同步。

## 备选方向（未采用）

- **Clean UI Demo Groove**（`bgm.wav`，96 BPM 代码合成）：无版权风险，但只有 56s，不符合"片长取决于 BGM 长度"且不裁切的要求。
- 《子不语 Wordless》132.19s：更短，节奏更分明，但会让一镜到底显得赶。
