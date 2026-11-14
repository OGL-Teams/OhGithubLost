# OGL 宣传片 · 分镜（02-storyboard）

片长 56s · 1920×1080 · 30fps · 无配音 · BGM 96 BPM（ beats 网格见 `assets/audio/bgm-beats.json`）

| # | 时间 | 画面 | 文案 | 动效 / 转场 | 真实信号 |
|---|---|---|---|---|---|
| 1 | 0.0–6.0 | 深蓝网格地面，逐行"流式"写出仓库文件树，光标闪烁于 `lib/main.dart` | `GitHub 的日常` / `不必打开浏览器` | 网格线由中心扩散；标题 blur→clear + y 上浮 0.5s；文字逐字显现；6s impact 切 | `lib/` 真实五层目录名 |
| 2 | 6.0–14.0 | 镜头推入窗口骨架：左侧导航、中间文件树、右侧代码区，光标点击 `repo_page.dart`，右侧面板平滑展开 | `仓库 · 目录 · 提交` | camera push 0.55s + 面板 morph（宽度/圆角过渡而非硬切）；代码行错峰上浮 | `repo_page.dart`、`code_editor_page.dart`、提交与冲突处理 |
| 3 | 14.0–23.0 | 五个协作标签依次点亮，每个标签带一条真实状态条（Issue #、PR diff、Release tag、Action run、Gist） | `Issues / PR / Releases / Actions / Gist` | 标签 stagger 0.1s；状态条从 0 宽度扫出；23s impact | README 协作面板段落 |
| 4 | 23.0–32.0 | 四层架构块从下往上叠放，箭头只允许向下，越界箭头被红色拦下并淡出 | `kernel → base → domain → surface` / `依赖方向，CI 强制` | 层块 spring-free 上浮；`layer_audit.py --fatal` 以终端字符打出；箭头 tracing | 真实架构与门禁脚本名 |
| 5 | 32.0–40.0 | 网络韧性：三个请求节点 → 第一次失败如实红标 → 自动重试成功 → 令牌进保险箱图标 | `失败如实可见` / `令牌只在本机` | 节点连线绘制；失败标记不静默消失；保险箱关闭 0.4s | README 网络韧性 / 令牌安全 |
| 6 | 40.0–46.0 | 六面语言旗 + 四档动效滑块，滑块从左到右拖动时背景粒子密度变化 | `6 语言 · 4 档动效` | 旗子错峰翻转；滑块 transform 位移；密度渐变（确定性） | `assets/i18n/` 六目录 / 动效四档 |
| 7 | 46.0–52.0 | 四平台图标从中心向外就位，Web 窗口以 wasm 徽标收束 | `Android · Windows · Linux · Web` | 图标弧线入场；镜头轻微 pull back；52s 切 | README 平台支持表 |
| 8 | 52.0–56.0 | End card：OGL SVG 图标填充升起 + 字标 wipe in，底部命令 `flutter pub get && flutter run` | `OhGithubLost` / `开源 · Apache-2.0` | 图标 fill-rise 0.7s，字标 wipe 0.5s，CTA 保持 2.5s | 仓库真实图标 SVG 与许可证 |

## HyperFrames 实现提示

- 根 `index.html` 只放 8 个 scene host + 一个 `<audio>`；每个场景一个 `compositions/sN-*.html`。
- 所有 `.clip` 带 `data-start` / `data-duration` / `data-track-index`；`data-track-kind="graphics"` 在 scene host 上。
- 每个子 composition 末尾 `window.__timelines["<id>"] = tl;` 且 `tl.paused()`。
- 只 tween transform / opacity / SVG stroke-dashoffset / clip-path，不 tween left/top/width/height/display。
- 字体：`@font-face` 指向 `assets/fonts/UbuntuMono-Regular.ttf`（已随仓库复制）。
- BGM 通过根 `<audio id="bgm" src="assets/audio/bgm.wav">` 混入；无声画面无需 `data-has-audio`。
