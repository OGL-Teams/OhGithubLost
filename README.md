<div align="center">

# OhGithubLost

**GitHub 仓库管理客户端 · v9.0.0**

Android · Windows · Linux · Web

浏览与编辑仓库、处理 Issues / Pull Requests / Releases / Actions、管理 Gist —— 不必打开浏览器。

[![Release](https://img.shields.io/github/v/release/OGL-Teams/OhGithubLost?label=release&color=blue)](https://github.com/OGL-Teams/OhGithubLost/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-informational)](#平台支持)
[![i18n](https://img.shields.io/badge/i18n-6%20languages-informational)](docs/I18N.md)

<br>

<img width="49%" alt="Star history" src="https://fastly.jsdelivr.net/gh/OGL-Teams/OhGithubLost@stats/stats/star-history.png">
<img width="49%" alt="Commit history" src="https://fastly.jsdelivr.net/gh/OGL-Teams/OhGithubLost@stats/stats/commit-history.png">

<sub>5K 极客风图表 · `stats` 分支每 10 分钟自动更新 · 更新后自动清 jsDelivr 缓存</sub>

</div>

<br>

> **插入截图**：主界面（首页 / 仓库页 / 代码编辑器 三联图最佳），置于 README 居中位置。

---

## 关于本项目

OhGithubLost（以下简称 OGL）是一款基于 Flutter 构建的 GitHub 客户端，旨在将 GitHub 的日常协作能力——仓库浏览与提交、Issue 与 PR 处理、Release 与 Action 监控、Gist 管理——搬到本地应用窗口之内，使用者不必再为这些操作打开浏览器。项目以「数据可靠性」与「失败如实可见」为工程底线：不静默降级、不预置加速通道、不掩盖版本冲突。

OGL 同时面向使用者与开发者：使用者经由发行产物安装；开发者经由 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 了解五层结构与依赖门禁。

## 核心特性

- **仓库全功能**：目录树浏览、文件预览与 README 渲染；新建、编辑、删除、重命名（含目录）；提交与冲突处理。
- **协作面板**：Issues / Pull Requests / Releases / Actions / Gist 一并支持，含 PR 差异、Action 日志与工作流手动触发。
- **多账号与令牌安全**：自由切换账号；令牌仅存本机系统密钥库，界面与日志中脱敏，退出登录即删除。
- **下载与草稿**：内置多连接分片下载，支持断点续传；编辑器自动持久化未提交草稿，再次进入同文件自动恢复。
- **网络韧性**：内置 DoH、自动重试与限流避让；失败如实报错，不静默降级。Release 附件下载可经**用户自备的加速通道**（默认关闭，应用不预置任何代理）。
- **国际化与动效**：6 种界面语言（简体中文 / 繁體中文 / English / Deutsch / Français / Русский），文案零硬编码由 CI 强制校验；动效分四档（静默 / 保守 / 标准 / 拉满），降档降开销、不删效果。

## 平台支持

| 平台  | 状态 | 产物 |
| ---   | --- | --- |
| Android | 支持 | 4 架构 APK（arm64-v8a / armeabi-v7a / x86_64 / universal）+ AAB |
| Windows | 支持 | x64 / arm64 |
| Linux | 支持 | x64 / arm64；deb / rpm / AppImage；**glibc ≥ 2.35** |
| Web | 支持 | <https://oghapp.344977.xyz/>（dart2wasm 主载，dart2js 兜底） |
| macOS / iOS | 弃用 | 最后支持版本 v5.3.0 |

不支持：桌面 32 位、musl-libc、Windows 7 / 8.1。

## 安装

从 [**Releases**](https://github.com/OGL-Teams/OhGithubLost/releases) 下载。每个产物同时提供 `.zip` 与 `.7z`（极限压缩），任选其一。

| 平台 | 文件 | 安装 |
| --- | --- | --- |
| Android | `OGL-<version>-Android.<abi>.zip` / `.AAB.zip` | 解压后安装 APK |
| Windows | `OGL-<version>-Windows.<arch>.zip` | 运行解压目录下的 `oghl.exe` |
| Linux | `OGL-<version>-Linux.<arch>.deb` / `.rpm` / `.AppImage` | `sudo dpkg -i *.deb` 或 `sudo rpm -i *.rpm`；AppImage 直接运行（无需 FUSE） |
| Web | 在线访问 | <https://oghapp.344977.xyz/> |

`<version>` 形如 `v8.0.0`，`<arch>` 形如 `x64` / `arm64`。

## 从源码构建

需要 Flutter **3.47.5**（Dart 3.13）及目标平台工具链。

```bash
flutter pub get
flutter run                    # 开发调试
flutter build apk              # Android
flutter build windows          # Windows
flutter build linux            # Linux（宿主直编，glibc 下限见 CI）
flutter build web --release --wasm --no-web-resources-cdn   # Web
```

## 架构概览

代码分为五层，依赖方向**只能向下**（`surface → domain → base → kernel`，`platform` 仅依赖 `kernel`）。CI 由 `tool/layer_audit.py --fatal` 强制；另有 i18n、动效分级、性能反模式三道门禁。完整说明见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

```
lib/
  kernel/    启动层  引导清单、Ed25519 签名、信任根
  base/      硬件层  网络（DoH / 重试 / 限流）、磁盘（原子写 / 缓存）
  domain/    逻辑层  GitHub API、本地深层信息
  surface/   交互层  UI、设置、i18n
```

## 用法

初次使用者请阅读 [`docs/USAGE.md`](docs/USAGE.md)：登录流程、首次权限引导、首页 / 搜索 / 仓库页操作、代码编辑器（含冲突处理）、下载管理、通知中心、设置项与故障排除均在其中。

## 文档索引

- [`docs/USAGE.md`](docs/USAGE.md) —— 使用说明（任务驱动，含故障排除）
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) —— 五层架构与依赖门禁
- [`docs/NETWORK.md`](docs/NETWORK.md) —— 网络连接总览（出口主机 / 资源取法 / Web 端限制）
- [`docs/I18N.md`](docs/I18N.md) —— 多语言维护手册
- [`CHANGELOG.md`](CHANGELOG.md) —— 完整版本历史
- [`release_notes/`](release_notes/) —— 逐版本发布说明（中英对照）
- <https://oglb.344977.xyz/> —— 更新日志站点（逐版本中英对照）

## 贡献

OGL 不接受随意合入：分层违规、未本地化中文、动效绕档、质量反模式均由 CI 拦截。请先阅读 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) 的「依赖方向的保障机制」与 [`docs/I18N.md`](docs/I18N.md) 的流程，再提交变更。

## 许可证

本项目使用 [Apache License 2.0](LICENSE)。第三方依赖声明见 [`NOTICE`](NOTICE) 与应用内「许可」页面。

<br>

<sub>星标与提交历史见页首图表，数据源为 `stats` 分支的 `history.json`。</sub>