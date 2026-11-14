# OGL 宣传片 · 分镜（02-storyboard）· v3

片长 56s · 1920×1080 · 30fps · 无配音
音轨：HOYO-MiX《子不语 Wordless》28–84s 裁段
定位：**新手开发者 + 尝鲜极客**（新手句做主标，极客证据只做角落 mono 小字）

切点来自 8kHz 频谱通量 onset 分析：`0 / 6.8 / 14.1 / 23.0 / 32.2 / 40.2 / 46.2 / 52.3 / 56`
根 composition 在每个切点有品牌蓝 `#beat-flash`：弱段（6.8/14.1/23.0/32.2）peak 0.38、衰减 0.30s；强段（40.2/46.2/52.3）peak 0.62、衰减 0.16s + `scale 0.985→1`。

| # | 全局时间 | 局部时长 | 画面 | 主标题 / 副标题 / 极客小字 | 动效与卡点 |
|---|---|---|---|---|---|
| 1 | 0.0–6.8 | 6.8 | 网格 + 精简文件树（pages/net/disk/i18n/assets）+ 大标题 | 「第一次用 GitHub / 也能直接上手」「仓库、议题、更新，都在一个 App 里 / 不用配环境，也不用开浏览器」「v12.6.9 · 装上就登录」 | 标题 blur→clear 错峰；cursor 1.5s 进入、扫描线 2.6s；4.4s 起网格反向微移填静止段；6.3s wipe |
| 2 | 6.8–14.1 | 7.3 | **实机截图** 01-home 440×782 + 02-discover 440×782（间距 120）+ 下方 punch-in 裁切条 | 「仓库一眼看全」「发现页：热门项目、议题、构建动态 / 顺手就能点开」「真机截图 · OGL-Teams/OhGithubLost」 | 两图 2.2/2.5s 推入 1→1.12 再回落；punch-in 3.0s 推入、5.6s 淡出；4.0s 起两图错峰呼吸；6.8s wipe |
| 3 | 14.1–23.0 | 8.9 | 五张协作卡 + 证据条 | 「议题 · 评审 · 发布 · 构建 · 片段」「不用来回切网页 / 五个入口都在底部导航」「Issues · Pull requests · Releases · Actions · Gist」 | 卡 0.14 / 状态条 0.08 / 圆点 0.06 错峰；6.0s 状态条二次扫动、6.6s 小数字上浮；8.4s wipe |
| 4 | 23.0–32.2 | 9.2 | 四层架构块 + 越界箭头 + 终端 | 「kernel → base → domain → surface」「依赖方向只能向下」「tool/layer_audit.py --fatal」 | 层块自下而上 stagger 0.14；箭头 dashoffset trace；越界红叉拦截；8.7s wipe |
| 5 | 32.2–40.2 | 8.0 | 左：429→retry→200；右：**实机截图** 03-profile 400×711 + 两条标注卡 | 「出错会告诉你 / 令牌只留在本机」「不用猜哪里失败了，也不怕账号留在别人设备上」「退出登录会删除本机保存的令牌 / 没有未提交的草稿」「429 · rate limited → retry 2/3 → 200 OK」 | 失败标记停留 1.2s 才转成功；截图 1.0s 先入场；6.07s（38.27 全局 onset）给 200 OK 脉冲；6.45s 截图微推；7.5s wipe |
| 6 | 40.2–46.2 | 6.0 | 六语言胶囊 + 四档滑块 + **实机截图** 04-settings 380×676 | 「6 语言 · 4 档动效」「看不懂英文？装完就是中文」「assets/i18n/ ×6」「动效可调 · 低配机也顺滑」 | 胶囊 rotationY 翻转 stagger 0.08；滑块 3.2s 位移 1.4s，轨道右端 1450；18 颗粒子确定性变亮（上限 0.6）；5.5s wipe |
| 7 | 46.2–52.3 | 6.1 | 四平台卡弧线就位 | 「装上就能用 · 4 个平台」「Android / Windows / Linux / Web，挑你手边那台」「APK + AAB / x64·arm64 / deb·rpm·AppImage / 浏览器直接打开」「zip + 7z 双格式 · 同版同步发布」 | 四卡不同 x/y 弧线 0.9s；连接线 stroke 0.35；镜头 pull back（immediateRender:false）；5.6s wipe |
| 8 | 52.3–56.0 | 3.7 | End card：图标圆角容器 + 字标 | 「OhGithubLost」「第一次用 GitHub，也能直接上手」「搜 OhGithubLost · 下载即用」「v12.6.9 · Apache-2.0」「想折腾源码？仓库里有 flutter pub get && flutter run」 | 图标 fill-rise 0.7s、字标 wipe 0.5s、CTA 1.3s；全部 ≤2.15s 结束，后 1.5s 静止，无 fade out |

## 素材分配（4 张截图上片，05-about 按审稿意见撤出 end card）

| 文件 | 场景 | 用途 |
|---|---|---|
| `01-home.png` | s2 | 仓库列表 + punch-in 裁「OGL-Teams/OhGithubLost · Dart · 4 星标」行 |
| `02-discover.png` | s2 | 发现页 / 议题与构建动态 |
| `03-profile.png` | s5 | 令牌与草稿安全 |
| `04-settings.png` | s6 | 中文界面与真实配置值 |
| `05-about.png` | — | 备选素材，当前不上片（end card 不放缩略图） |

## 审稿吸收记录（v2 → v3）

- 文案去黑话：s1 移走「18 道门禁」与层名；s2「CI 动态」→「构建动态」；s3 英文术语降为小字并加中文主标；s5 删 `DoH · retry · backoff`；s6 删无锚点宣称与 i18n 路径串；s7 删「macOS/iOS 弃用」上屏、去掉 glibc/ABI 细节；s8 删重复许可证行与 180px 缩略图。
- 动效补死段：s1 4.4–6.2 网格微移；s2 punch-in + 双图呼吸填 3.0–6.8；s3 状态条二次扫动 + 数字上浮填 6.0–8.4；s5 加 6.07s onset 脉冲与截图微推。
- 卡点分档：弱段/强段不同的峰值与衰减，强段带 punch scale。
- 视觉统一：`.shot` 2px #30363d 描边 + 1px 高光；四场景标题统一 72px；s8 图标加 #161b22 圆角容器；中文不再用 Ubuntu Mono。
