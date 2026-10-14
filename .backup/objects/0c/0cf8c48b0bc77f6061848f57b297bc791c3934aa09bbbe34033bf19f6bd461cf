# OhGithubLost（OGL）

**一个 GitHub 仓库管理客户端** —— 手机 / 平板 / 桌面可用。
用它浏览与编辑仓库、处理 Issues 与 Pull Requests、查看 Releases 与 Actions、管理 Gist，不必打开浏览器。

> 名称由来：GitHub 官方没有适合移动端的仓库管理客户端，OGL 就是要"把丢失的 GitHub 找回来"。

## 功能特性 / Features

- **仓库浏览**：目录树、文件预览、README 渲染（图片经 Contents API 加载，避开 DNS 污染）
- **编辑**：在线编辑 / 新建 / 删除文件，提交与冲突处理（七道防线 D1–D7 + 持久化 D8–D10）
- **协作**：Issues / Pull Requests / Releases / Actions / Gist
- **多账号**：自由切换，Token 安全存储
- **下载**：多连接分片下载 + 断点续传 + 加速通道（默认关闭，可显式开启）
- **网络韧性**：内置 DoH、镜像降级、重试与限流避让；加速通道失败静默降级
- **动效分级**：静默 / 保守 / 标准 / 拉满四档，降档降开销、不删效果
- **15 种语言**：界面文案零硬编码，CI 强制校验
- **桌面自绘窗口**：自研标题栏（拖拽 / 双击最大化 / 最小化·最大化·关闭），可在设置菜单回退系统窗口管理器

## 平台支持 / Platform support

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Android | ✅ 支持 | 4 架构 APK + AAB；arm64-v8a / armeabi-v7a / x86_64 / universal |
| Windows | ✅ 支持 | x64 / arm64；建议开启长路径支持（非必须，超限有收纳回退） |
| Linux | ✅ 支持 | x64 / arm64；deb / rpm / AppImage；**glibc ≥ 2.35**（Ubuntu 22.04 一代及以上） |
| macOS / iOS | ❌ 弃用 | 最后支持版本 v5.3.0 |

**不要做无用尝试**：桌面 32 位、musl-libc、Windows 7 / 8.1 均不支持。

## 安装 / Install

每个版本在 **Releases** 发布，产物仅压缩包（zip + 7z 极限压缩），Linux 额外裸放 deb / rpm / AppImage。

| 平台 | 产物名（`<version>` 取版本号，如 `v6.0.0`） |
| --- | --- |
| Android | `OGL-<version>-Android.arm64-v8a.zip` / `.armeabi-v7a` / `.x86_64` / `.universal-APK` / `.AAB` |
| Windows | `OGL-<version>-Windows.x64.zip` / `.arm64.zip` |
| Linux | `OGL-<version>-Linux.x64.deb` / `.rpm` / `.AppImage`（`.arm64` 同理） |

每个压缩包都有 **zip 与 7z 两份**（极限压缩），按需选一种即可。

解压后：
- **Android**：直接安装 APK；
- **Windows**：运行解压目录下的 `oghl.exe`（`ohgithublost.exe`）；
- **Linux**：`sudo dpkg -i *.deb` 或 `sudo rpm -i *.rpm`，或直接运行 `.AppImage`（已内置 `--appimage-extract-and-run`，无需 FUSE）。

## 从源码构建 / Build from source

要求：Flutter **3.47.5**（Dart 3.13.4），Android / Windows / Linux 相应工具链。

```bash
flutter pub get
flutter run              # 开发
flutter build apk        # Android
flutter build windows    # Windows
flutter build linux      # Linux（宿主直编，glibc 下限见 CI）
```

## 目录结构 / Repository layout

```
.github/workflows/   CI：质量门（5 项审计 + analyze + test）、构建矩阵（9 条腿）、发布
assets/              资源：icon（唯一事实来源 SVG）/ i18n（15 语言）/ boot / mods / theme_packs
docs/                文档：使用说明 USAGE.md、多语言维护手册 I18N.md
lib/                 源码（四层架构）
  kernel/            启动层：引导清单 / 签名 / 信任根
  base/              硬件层：网络（DoH / 镜像 / 重试）+ 磁盘（原子写 / 长路径 / 缓存）
  domain/            逻辑层：GitHub API、本地深层信息
  surface/           交互层：UI、设置、i18n
changed/             更新日志站点（Jekyll 源，同时发布到 GitHub Pages 与 Netlify）
release_notes/       发布说明（每版本一个 .md，中英对照）
test/                测试（base / domain / kernel / surface / screenshots）
tool/                工具（图标光栅化 / 桌面壳注入 / Linux 打包 / 审计门禁）
```

## 架构纪律 / Architecture

依赖只能向下：`surface → domain → base → kernel`；装配根与类型门面为白名单例外。
CI 用 `tool/layer_audit.py --fatal` 强制。

## 文档索引 / Docs

| 文档 | 内容 |
| --- | --- |
| `docs/USAGE.md` | 使用说明（安装 / 登录 / 主要功能） |
| `docs/I18N.md` | 多语言维护手册（新增文案 / 翻译流程） |
| `release_notes/v6.0.0.md` | 本版本发布说明（中英对照） |
| `CHANGELOG.md` | 完整版本历史（含未发布 / 跳过版本的事实标注） |

**更新日志站点**：<https://yingo-server.github.io/OhGithubLost/>
逐版本的中英对照说明都在这里，比翻 Releases 列表更快；Netlify 镜像同源同内容。

## 发布节奏 / Release cadence

- 版本号语义：`vX.Y.Z`，跳过即标注（如 `v5.7.0（未发布 · 跳过）`）；
- 未单独发版的开发迭代会**并入下一个正式版**并标注来源版本号；
- 发布说明规范：**中英逐条对照**，含 新增 / 变更 / 修复 / 已知限制 / 产物，不写空话。

## 许可证 / License

**AGPL-3.0**（见 `LICENSE`）。第三方依赖许可见应用内「许可」页面。
