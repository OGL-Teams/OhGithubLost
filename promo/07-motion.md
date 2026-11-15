# OGL 宣传片 · 动效规范（07-motion）· 3D One-Shot

> 用户强调"动画是重点 / 整体灵动"。本版不再用 GSAP 逐元素淡入上浮，而用**相机运动 + 空间近场函数 + 连续材质参数**制造灵动感。

## 1. 相机（贯穿 175.01s，无停顿）

```js
u = clamp(t / 175.01, 0, 1)
z = 34 - 206u
x = sin(0.055t)*1.15 + sin(0.013t)*0.55
y = 3.0 + sin(0.041t)*0.35
roll = sin(0.018t)*0.006
look = (sin(0.021t)*0.9, 0.4+sin(0.031t)*0.35, z-17)
```

三条不同频率的正弦（0.055 / 0.013 / 0.041）叠加，避免匀速直线带来的"电梯感"；look-ahead 始终指向前方 17 单位，让站点从远处缓缓放大。

## 2. 站点近场（代替入场/出场动画）

```js
near = exp(-((camera.z - station.z)/13)^2)
scale   = 0.90 + 0.10*near        // 经过时轻微放大
opacity = 0.72 + 0.28*near        // 远处半透，近处实
group.y = sin(0.5t + i*0.7)*0.12*(1-near)
group.rotation.y = sin(0.18t + i)*0.012
```

- 没有"入场完成就静止"的问题：每个站点在整个 175s 内都有低频漂浮。
- 近场函数连续可导，不会出现帧跳。

## 3. 光与空气（呼应 BGM 能量）

```js
bloom = smoothstep(90,120,t) * (1 - smoothstep(160,175,t))
exposure = 1.06 + 0.08*bloom
fog.near = 42 + 8*bloom
fog.far  = 170 + 18*bloom
```

亮色不靠闪光，而靠雾距与曝光；90–160s 的空间更通透，片尾收回。

## 4. M3 语汇在 3D 里的对应

| M3 token | 3D 实现 |
|---|---|
| shape 8 / 12 | 面板 8px 圆角烘焙、线框块 0–4px 硬边 |
| tonal elevation | 白色面板 + PCFSoft 接触阴影，不用黑色投影堆 |
| state layer | 站点 opacity 0.72→1.00，等价 8%→100% 层级 |
| emphasized decelerate | 相机低频正弦（连续，无 ease 分段） |
| 8dp 网格 | 面板 1024×640、站点 Z 间距 18–19、地面网格 64 段 |

## 5. 确定性契约

- 所有可见状态只依赖 `e.detail.time`；`poseAt(t)` 是纯函数。
- 无 `requestAnimationFrame` / `setAnimationLoop` / `Date.now` / `performance.now` / `Math.random` / CSS transition。
- 纹理与 shader 在 `window.__hf.buildReady.oneShot` 里加载并编译；首帧 `gl.readPixels` 强制 GPU 完成。
- 每个 `hf-seek` 用 `e.detail.waitUntil(queue)` 串行化，帧可乱序到达但结果一致。

## 6. 自检

- [x] 第 0 帧有亮色地面、网格、导轨、HUD、第一块面板
- [x] 无切镜、无 wipe、无全屏色块
- [x] 无 ≥1.5s 静止：相机与站点始终在低频运动
- [x] 面板 `rotation.y ≤ 0.045rad`，文字可读
