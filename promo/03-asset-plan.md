# OGL 宣传片 · 素材清单（03-asset-plan）· v2

## pack-b：可验证素材

| 文件 | 来源 | 用途 |
|---|---|---|
| `assets/screens/01-home.png` | 用户提供 Android 实机截图 | s2 首页仓库列表 |
| `assets/screens/02-discover.png` | 同上 | s2 发现页 / 议题 / CI 动态 |
| `assets/screens/03-profile.png` | 同上 | s5 令牌与草稿安全 |
| `assets/screens/04-settings.png` | 同上 | s6 中文设置与真实配置值 |
| `assets/screens/05-about.png` | 同上 | s8 版本 / 许可 / 致谢 |
| `assets/fonts/UbuntuMono-{Regular,Bold}.ttf` | 仓库 `assets/fonts/` | 代码与数据字体 |
| `assets/ogl_icon.svg` | 仓库 `assets/icon/ogl_icon.svg` | End card 品牌图标 |
| `assets/audio/wordless-56s.mp3` | 挂载目录 Tiernan_Music，28–84s 裁段转码 | 主音轨，卡点基准 |
| `assets/audio/bgm.wav` | `scripts/make_bgm.py` 合成 | 备用轨（volume 0） |
| `assets/audio/bgm-beats.json` | 同上 | 原 96 BPM 网格，保留作对照 |
| `assets/vendor/gsap.min.js` | HyperFrames registry 自带 GSAP 3.14.2 | 离线动画运行时 |
| `changed/_posts/v12.6.{3,8,9}.md` | 仓库更新日志 | s1/s3/s8 的证据文案 |

**截图共同特征**：1080×1920 竖屏、白底、Material 3、中文界面、底部四标签（仓库 / 发现 / 个人 / 设置）、状态栏 10:17–10:18。作为「实机证据」使用，不裁切掉可见文字，不做 3D 倾斜。

## pack-a：代码绘制的示意视觉

`s3` 五功能卡、`s4` 四层架构与越界箭头、`s5` 请求节点、`s6` 语言胶囊与滑块、`s7` 平台轮廓与连接线、`s8` 图标填充——均为 HTML/CSS/SVG 绘制。

**变更**：v1 的 `s2` 假窗口骨架（虚构导航 + `repo_page.dart` 代码块）已**删除**，改为两张真实截图。其余场景的示意元素不冒充应用界面，只表达架构/状态/数据关系。

## 版权与来源

- 5 张截图：用户提供，来自其本人设备，含 `@yingo-server` 账号名与通知条目；对外发布前建议打码或确认可公开。
- 字体与图标：仓库自有，Apache-2.0 项目资产。
- `wordless-56s.mp3`：HOYO-MiX《子不语 Wordless》裁段，**版权归原权利人**，仅内部样片评估；正式投放需授权或切回 `bgm.wav`。
- `bgm.wav`：本项目脚本算法合成，无第三方音频。
- GSAP：随 HyperFrames registry 分发的本地副本。

## 缺口

- 无桌面端实机截图（只有 Android 竖屏），因此 s7 的平台卡仍是矢量示意，不假装成截图。
- 无配音（需求未要求）。
- 无应用录屏，卡点靠切点与闪层实现，不做「假操作」动画。
