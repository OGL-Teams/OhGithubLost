# OGL 宣传片 · 分镜（02-storyboard）· v2 · Wordless 卡点版

片长 56s · 1920×1080 · 30fps · 无配音
音轨：HOYO-MiX《子不语 Wordless》28–84s 裁段
定位：**新手开发者 + 尝鲜极客**
切点来自 8kHz 频谱通量 onset 分析：`0 / 6.8 / 14.1 / 23.0 / 32.2 / 40.2 / 46.2 / 52.3 / 56`
根 composition 在每个切点有 0.07s 入 / 0.24s 出的品牌蓝 `#beat-flash`。

| # | 全局时间 | 局部时长 | 画面 | 文案 | 动效 / 卡点 | 真实证据 |
|---|---|---|---|---|---|---|
| 1 | 0.0–6.8 | 6.8 | 深蓝网格 + 真实文件树；右侧大标题 | 「第一次用 GitHub / 也能直接上手」「装上就登录 · 仓库、议题、更新都在一个 App 里」「不用配环境，不用开浏览器」「v12.6.9 · 18 道离线门禁全通过」 | 0.9s 标题 blur→clear 错峰；6.3s wipe 起，6.8s 切点闪 | `lib/` 五层目录、v12.6.9 日志 |
| 2 | 6.8–14.1 | 7.3 | **实机截图** 01-home + 02-discover 并排取景 | 「仓库一眼看全」「发现页：别人的项目、议题、CI 动态」「实机截图 · Android」 | 两图依次 scale 1→1.12→1 连续推入（0.55s power3.inOut），第二张晚 0.3s；6.8s 切点闪；6.8s wipe 收 | 用户提供的 Android 截图 |
| 3 | 14.1–23.0 | 8.9 | 五张协作卡 + 顶部更新日志证据条 | 「Issues · PR · Releases · Actions · Gist」「不用来回切网页，五个入口都在底部导航」「12.6.3 → 12.6.9 · 7 天连续打磨」「发现页分类筛选 · 设置页平铺 · 键盘快捷键 · 字体缓存校验 · 18 道离线门禁」 | 证据条 1.2s 淡入；卡片 stagger 0.1；状态条 scaleX 扫出；14.1s 切点闪 | `changed/_posts` v12.6.3/8/9 |
| 4 | 23.0–32.2 | 9.2 | 四层架构块 + 越界箭头被拦截 + 终端字符 | 「kernel → base → domain → surface」「依赖方向只能向下」「tool/layer_audit.py --fatal」 | 层块上浮 stagger 0.14；SVG 箭头 trace；23.0s 切点闪 | README 架构 + 门禁脚本名 |
| 5 | 32.2–40.2 | 8.0 | 左：429→retry→200 全过程；右：**实机截图** 03-profile | 「出错会告诉你」「令牌只留在本机」「不用猜哪里失败了，也不怕账号留在别人设备上」「退出登录会删除本机保存的令牌」「草稿箱 · 没有未提交的草稿」 | 失败标记停留 1.2s 后才转成功；截图 32.2s 后推入；切点闪 | 截图原文 + README 网络韧性 |
| 6 | 40.2–46.2 | 6.0 | 六语言胶囊 + 四档动效滑块 + **实机截图** 04-settings | 「6 语言 · 4 档动效」「看不懂英文？装完就是中文」「设置页 · 跟随系统 · GitHub 蓝 · 100% · 下载线程数 16」 | 胶囊 rotationY 翻转 stagger；滑块 1.4s 位移；粒子确定性密度上升；40.2s 切点闪 | 截图原文 + `assets/i18n/` |
| 7 | 46.2–52.3 | 6.1 | 四平台卡弧线散开 | 「装上就能用 · 4 个平台」「Android / Windows / Linux / Web，挑你手边那台」「每版同时提供 .zip 与 .7z · 解压即用」 | 四卡不同 x/y 弧线就位 0.9s；连接线 trace；镜头 pull back；46.2s 切点闪 | README 平台表 |
| 8 | 52.3–56.0 | 3.7 | End card：OGL 图标 fill-rise + 字标 wipe + **实机截图** 05-about 小样 | 「第一次用 GitHub，也能直接上手」「搜 OhGithubLost · 下载即用」「想折腾源码？仓库里有 flutter pub get && flutter run」「v12.6.9 · Apache-2.0 · 致谢 18」 | 图标 0.7s 填充升起；字标 0.5s wipe；截图 ≤2.2s 淡入；52.3s 切点闪；末 1.5s 静止 | 仓库图标 SVG + 关于页截图 |

## 素材分配（5 张截图全部上片）

| 文件 | 场景 | 用途 |
|---|---|---|
| `01-home.png` | s2 | 仓库列表 / 新手第一眼 |
| `02-discover.png` | s2 | 发现页 / 议题与 CI 动态 |
| `03-profile.png` | s5 | 令牌与草稿安全 |
| `04-settings.png` | s6 | 中文界面与设置真实值 |
| `05-about.png` | s8 | 版本号 / 许可证 / 致谢 |

## HyperFrames 实现契约

- 根 `index.html`：8 个 scene host（新 `data-start`/`data-duration`）+ `#beat-flash` + `#vignette` + `#grain` + 主音轨 `wordless-56s.mp3` + 备用轨 `bgm.wav`（volume 0）。
- 子 composition 内部时间从 0 起；host id == `data-composition-id` == `window.__timelines` key。
- 所有 `.clip` 带 `data-start` / `data-duration` / `data-track-index`；wipe 目标侧必须 `opacity: 1`。
- 只 tween transform / opacity / clipPath / stroke-dashoffset；只用 `fromTo`；无随机数与定时器。
- 图片路径 `assets/screens/...`，无前导 `/`。
