# OGL 宣传片 · 素材清单（03-asset-plan）

## pack-b：来自仓库的可验证素材

| 文件 | 来源 | 用途 |
|---|---|---|
| `assets/fonts/UbuntuMono-Regular.ttf` | 仓库 `assets/fonts/` | 所有代码 / 数据 / 标签的等宽字体 |
| `assets/fonts/UbuntuMono-Bold.ttf` | 仓库 `assets/fonts/` | 等宽强调字重 |
| `assets/ogl_icon.svg` | 仓库 `assets/icon/ogl_icon.svg` | End card 品牌图标（几何唯一事实来源） |
| `assets/audio/bgm.wav` | `scripts/make_bgm.py` 代码合成 | 96 BPM 全片配乐 |
| `assets/audio/bgm-beats.json` | 同上 | 节拍网格 / 转场点，供剪辑对齐 |
| `assets/vendor/gsap.min.js` | HyperFrames registry `code-slice-hero` 内置 GSAP 3.14.2（本地副本，离线可渲染） | 动画运行时 |

## pack-a：代码绘制的示意视觉

全部画面由 `compositions/s*.html` 的 HTML/CSS/SVG 绘制，没有生成式图片。

**重要声明**：`s2-repo` 中的窗口骨架是**依据真实页面文件名与 README 功能描述重绘的示意界面**，不是应用截图。仓库未提供任何应用截图；所有标签（Dashboard / Repositories / Issues / Pull requests / …）、文件名（`repo_page.dart`、`code_editor_page.dart`）、目录（`assets/i18n/`）与门禁脚本名（`tool/layer_audit.py --fatal`）均取自代码，未虚构控件功能。

## 版权与来源

- 字体：Ubuntu Mono，随仓库原样复制。
- 图标：仓库自有 SVG，Apache-2.0 项目资产。
- BGM：本项目脚本算法合成，无第三方音频。
- GSAP：标准版，随 HyperFrames registry 分发（Apache-2.0 生态内的 MIT/标准许可），仅本地离线引用。

## 缺口

- 无应用录屏 / 截图 → 采用可核对的示意重绘，交付文档须标注。
- 无配音（需求未要求）。
