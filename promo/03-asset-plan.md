# OGL 宣传片 · 素材清单（03-asset-plan）· 3D One-Shot

## Pack B · 可验证素材（全部入库）

| 文件 | 来源 | 3D 用途 |
|---|---|---|
| `assets/screens/01-home.png` … `12-legal.png` | 用户提供 Android 实机截图 | 9 个站点的右侧 3D 平面贴图 |
| `assets/audio/bgm-lunar.mp3` | 挂载目录《月宫试云衣》，完整转码 | 主音轨；片长 175.01s 由它决定 |
| `assets/three/three.module.min.js` | HyperFrames registry `cuboid-carousel` 内置 Three.js | WebGL 运行时 |
| `assets/three/three.core.min.js` | 同上 | Three.js core 依赖 |
| `assets/three/Three-LICENSE.txt` | 同上 | MIT 许可 |
| `assets/vendor/gsap.min.js` | HyperFrames registry 内置 GSAP 3.14.2 | 空根 timeline 注册（runtime 契约） |
| `assets/fonts/UbuntuMono-{Regular,Bold}.ttf` | 仓库原字体 | 面板 mono 证据行烘焙 |
| `assets/ogl_icon.svg` | 仓库原图标 | 本版未上片，保留作品牌资产 |
| `assets/panels/panel-00.png … panel-10.png` | `scripts/bake_panels.py` 本地烘焙 | 11 块 3D 信息面板贴图 |

## Pack A · 代码生成视觉

- 亮色地面 / 网格 / 品牌蓝导轨 / 站点线框 / 小圆点 / 连接线：全部由 `assets/one-shot.js` 在 setup 里生成。
- 没有生成式图片，没有装饰性 AI 图；所有可读内容都来自真实截图或仓库数据。

## 面板烘焙

`python3 promo/scripts/bake_panels.py`

- 尺寸 1024×640，M3 亮色卡：8px 圆角、1px `#C7D0DC` 描边、左侧 4px `#0B57D0` 主色条。
- 字体：本机 Noto Sans CJK（标题 62 / 正文 30）+ Ubuntu Mono（kicker 28 / 证据行 26）。
- 中文 PNG 已提交进仓库，CI 不需要系统中文字体即可正确显示 3D 文字。

## 版权与来源

- 实机截图来自用户设备，含 `@yingo-server` 账号名，公开前建议确认。
- 《月宫试云衣》版权归 HOYO-MiX 及权利人，仅内部样片。
- Three.js MIT；GSAP 标准许可；Ubuntu Mono 与 OGL 图标为仓库自有资产。

## 缺口

- 没有 PR 差异、Actions 运行日志、下载管理页的实机截图（本版用日志页/网络页/关于页替代，不伪造）。
- 无配音，无字幕轨。
- 本地 ARM64 无法稳定启动 WebGL Chrome；正式出片只认 CI。
