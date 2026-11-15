# 03 · Asset Plan

只有五类输入：

| 资产 | 路径 | 用途 |
|---|---|---|
| 音轨 | `assets/audio/yancigui-25.m4a` | 已固化 25% 音量，175.082s，决定片长 |
| 字体子集 | `assets/fonts/heiti-subset.woff2` | 族名 OGLHeiti，仅含片中实际用到的字形 |
| GSAP | `assets/vendor/gsap.min.js` | 本地依赖，驱动唯一的位移时间轴 |
| 编年数据 | `data/milestones.json` | 16 条 version / headline |
| HTML | `index.html`、`compositions/credits.html` | 单根合成，全部画面 |

**没有图片。** 无边框、无装饰线、无图标、无渐变、无截图、无贴图。CI 在渲染前断言 promo/ 下不存在 png/jpg/jpeg/svg/webp/gif。
