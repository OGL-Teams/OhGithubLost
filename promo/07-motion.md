# OGL 宣传片 · 动效规范（07-motion）

> 依据 Material Design 3 motion：easing tokens、duration tokens、transition patterns（shared axis / container transform / fade through）。
> 这条是用户明确指出的重点：动画不是"淡入上浮"模板，而是有方向的转场与层级。

## 1. Easing / Duration 映射

GSAP 没有 CustomEase 插件时的等价映射（只用内置 ease）：

| M3 token | 曲线含义 | GSAP 近似 | 用在哪 |
|---|---|---|---|
| emphasized decelerate | (0.05, 0, 0, 1) | `power4.out` | 场景/大块入场 |
| emphasized accelerate | (0.3, 0, 1, 1) | `power3.in` | 场景退场 |
| standard | (0.2, 0, 0, 1) | `power2.inOut` | 同层级位置变化 |
| standard decelerate | (0, 0, 0, 1) | `power2.out` | 小元素入场 |
| linear | — | `none` | 进度/滑块拖动 |

| M3 duration | 值 | 用途 |
|---|---|---|
| short2 | 100ms | 状态层、涟漪 |
| short4 | 200ms | 图标/小标签 |
| medium2 | 300ms | 列表项、Chip |
| medium4 | 400ms | 卡片、面板 |
| long2 | 500ms | 大型共享轴位移 |
| long4 | 600ms | 场景级 container transform |

**禁用**：`bounce` / `elastic` / `back`（M3 不用回弹），以及超 800ms 的单段入场。

## 2. 转场：删掉全屏黑场 wipe，改 shared axis X

当前 7 个切点都是「0.5s 全屏 ground 色覆盖」→ 每 7 秒一次黑场，7 次后非常公式化。改为两段式共享轴位移：

```js
// 出场（duration - 0.42s 起，0.26s）
tl.fromTo("#sN-stage", { x: 0, opacity: 1 },
  { x: -80, opacity: 0, duration: 0.26, ease: "power3.in", immediateRender: false }, D - 0.42);

// 入场（0 起，0.42s）—— 与出场方向一致，形成"世界向左推进"的连续感
tl.fromTo("#sN-stage", { x: 80, opacity: 0 },
  { x: 0, opacity: 1, duration: 0.42, ease: "power4.out" }, 0);
```

- 每个场景根下加一层 `#sN-stage`（position:absolute; inset:0），所有可见元素放进去；根 `#root` 不动。
- 只 tween `x` / `opacity`，可 seek、无随机。
- 切点仍有 `#beat-flash`（8% / 16% primary 状态层），但不遮画面。

## 3. 场景内部的 M3 动效语法

| 手法 | 实现 | 用在哪 |
|---|---|---|
| 列表项分批入场 | y 16→0 + opacity，stagger 0.04，`power2.out`，300ms | s3 五卡、s6 六语言、s7 四平台 |
| 容器变换（container transform） | scale 0.92→1 + opacity + 圆角不变，400ms `power4.out` | s2 截图从面板位置展开、s8 图标容器 |
| 共享轴 Z（深度） | scale 1.04→1 + opacity，500ms | s1 右侧产品面板、s5 截图 |
| 状态层（state layer） | 8% / 12% primary 覆盖层 opacity 0→1→0，100ms/200ms | s5 的 429→retry→200 状态切换、s3 卡状态条 |
| 数据逐行揭示 | clipPath inset(0 100% 0 0) → inset(0 0 0 0)，300ms，stagger 0.05 | s3/s5/s7 的 mono 数据行 |
| 计数/进度 | scaleX 0→1（transformOrigin left），`power2.inOut` | s3 状态条、s6 滑块、s4 箭头 |
| 强调脉冲 | scale 1→1.06→1，各 120ms | s5 的 200 OK 落在 38.27s 强 onset |

**禁止**：同一元素并行两条改同一属性的 tween；`display/visibility/autoAlpha`；布局属性；CSS transition。

## 4. 场景级节奏（与 Wordless 对齐）

| 场景 | 局部时长 | 内部节拍 |
|---|---|---|
| s1 | 6.8 | 0.1 kicker → 0.35 标题 → 0.8 定义 → 1.0/1.15/1.3 数据 → 4.6 呼吸 |
| s2 | 7.3 | 0.1 标题 → 0.5/0.7 截图 → 2.2/2.5 推入 → 4.2 数据行呼吸 |
| s3 | 8.9 | 0.2 标题 → 0.8 卡 stagger → 1.6 状态 → 2.4 说明行 → 5.9 呼吸 |
| s4 | 9.2 | 0.3 标题 → 0.8 层块自下而上 → 1.2 终端逐行 → 5.0 越界拦截 |
| s5 | 8.0 | 0.2 标题 → 0.8 节点 → 2.0/3.2/4.1 三态 → 6.2 微推 |
| s6 | 6.0 | 0.2 标题 → 0.7 语言行 → 3.2 滑块 1.4s → 5.9 收 |
| s7 | 6.1 | 0.2 标题 → 0.8 四块 → 1.6 底行 → 4.4 呼吸 |
| s8 | 3.7 | 0.1 图标 → 0.5 字标 → 0.9 说明 → 1.2 CTA → 1.5 命令 → 静止 1.7 |

## 5. 卡点层

- 弱拍（6.8 / 14.1 / 23.0 / 32.2）：primary 8%，80ms 入 / 300ms 出。
- 强拍（40.2 / 46.2 / 52.3）：primary 16%，60ms 入 / 220ms 出。
- 不用缩放抖动、不用白闪；状态层叠加是 M3 的语言。

## 6. 自检清单

- [ ] 每场景有 `#sN-stage`，入场/出场都是 x+opacity。
- [ ] 无 `wipe` 全屏覆盖层残留（除 s8 无转场）。
- [ ] 所有 ease ∈ {power2,power3,power4}.{out,in,inOut}, none。
- [ ] 单段入场 ≤ 600ms；stagger ≤ 0.06。
- [ ] 同元素多段 tween 带 `immediateRender:false`。
- [ ] 无 rAF / Date.now / Math.random / CSS transition。
