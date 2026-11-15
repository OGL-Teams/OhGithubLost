# OGL 宣传片 · EDL（04-edl）· 3D One-Shot

主编辑文件：`promo/index.html`（单个 canvas composition）
渲染：1920×1080 / 30fps / **175.01s** / H.264 + AAC
片长锁：`assets/audio/bgm-lunar.mp3`（175.046531s，源曲 175.007979s，不裁切）

## 轨道

| 轨道 | 内容 |
|---|---|
| 1 | `#gl` — Three.js WebGL canvas，全片唯一画面层 |
| 2 | `#hud` / `#chapter` / `#progress` — 常驻轻量 HUD |
| 9 | `#bgm` ← `assets/audio/bgm-lunar.mp3`，volume 1 |

## 时间线（不是切镜表，是相机路径采样）

| 全局时间 | 相机 z（约） | 经过站点 | HUD 章节 |
|---|---|---|---|
| 0s | +34 | 00 开场进入视野 | 00 · 开场 |
| 14s | +17 | 01 仓库 | 01 · 仓库 |
| 30s | -1 | 02 代码 | 02 · 代码 |
| 46s | -20 | 03 编辑 | 03 · 编辑 |
| 62s | -39 | 04 Issue | 04 · Issue |
| 80s | -60 | 05 日志 | 05 · 日志 |
| 96s | -79 | 06 网络 | 06 · 网络 |
| 116s | -103 | 07 法律 | 07 · 法律 |
| 134s | -126 | 08 账号 | 08 · 账号 |
| 150s | -143 | 09 产物 | 09 · 产物 |
| 168s | -163 | 10 片尾 | 10 · 片尾 |
| 175.01s | -172 | 停在片尾后方 | 10 · 片尾 |

相机公式（纯时间函数）：

```js
u = t / 175.01
camera.z = 34 - u * 206
camera.x = sin(t*0.055)*1.15 + sin(t*0.013)*0.55
camera.y = 3.0 + sin(t*0.041)*0.35
lookAt( sin(t*0.021)*0.9, 0.4 + sin(t*0.031)*0.35, camera.z - 17 )
```

站点近场函数：

```js
near = exp(-((camera.z - station.z)/13)^2)
station.scale = 0.90 + 0.10 * near
panel.opacity = 0.72 + 0.28 * near
```

## 配乐

完整《月宫试云衣》，无裁切、无淡入淡出、无额外混音。画面唯一"对齐"是 90–160s 的曝光/雾距抬升，对应曲子的能量段；不做帧级卡点，因为一镜到底不该被鼓点切碎。详见 `06-music-plan.md`。

## 渲染

```bash
npm --prefix promo run lint    # 静态硬门禁
npm --prefix promo run render  # 官方 Chrome 环境
```

CI：`.github/workflows/promo-render.yml` → lint → render → 720p → 7z -mx=9 → tag `promo-<sha7>` → Release。

## 自检

- [x] 根 `data-duration="175.01"` 与音轨时长一致
- [x] 单个 composition、单个 canvas、无 `data-composition-src`
- [x] `hf-seek` 纯函数；无 rAF / Date.now / Math.random / timer
- [x] `window.__hf.buildReady.oneShot` 等纹理加载与 shader 编译
- [x] 第 0 帧亮色，有 HUD、导轨、地面、第一块面板
