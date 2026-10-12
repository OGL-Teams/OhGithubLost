<div align="center">

# OhGithubLost

**GitHub 仓库管理客户端**

Android · Windows · Linux · Web

浏览与编辑仓库、处理 Issues / Pull Requests / Releases / Actions、管理 Gist —— 不必打开浏览器。

[![Release](https://img.shields.io/github/v/release/OGL-Teams/OhGithubLost?label=release&color=blue)](https://github.com/OGL-Teams/OhGithubLost/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-informational)](#平台支持)
[![i18n](https://img.shields.io/badge/i18n-6%20languages-informational)](docs/I18N.md)

<br>

<img width="49%" alt="Star history" src="https://fastly.jsdelivr.net/gh/OGL-Teams/OhGithubLost@stats/stats/star-history.png">
<img width="49%" alt="Commit history" src="https://fastly.jsdelivr.net/gh/OGL-Teams/OhGithubLost@stats/stats/commit-history.png">

<sub>图表由 `stats` 分支每小时自动更新</sub>

</div>

---

## 功能

| | |
| --- | --- |
| **仓库** | 目录树、文件预览、README 渲染；新建 / 编辑 / 删除 / 重命名（含目录递归）；提交与冲突处理 |
| **协作** | Issues、Pull Requests、Releases、Actions、Gist |
| **账号** | 多账号自由切换；令牌本地安全存储 |
| **下载** | 多连接分片 + 断点续传；加速通道**自备**（默认关闭，应用不预置任何代理） |
| **网络** | 内置 DoH、重试与限流避让；**不做静默降级** —— 失败如实报错 |
| **动效** | 四档（静默 / 保守 / 标准 / 拉满），降档降开销、不删效果；按档位分级预加载 |
| **语言** | 6 种（简体中文 / 繁體中文 / English / Deutsch / Français / Русский）；文案零硬编码，CI 强制校验 |

## 平台支持

| 平台 | 状态 | 产物 |
| --- | --- | --- |
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

## 架构

```
lib/
  kernel/    启动层  引导清单、Ed25519 签名、信任根
  base/      硬件层  网络（DoH / 重试 / 限流）、磁盘（原子写 / 缓存）
  domain/    逻辑层  GitHub API、本地深层信息
  surface/   交互层  UI、设置、i18n
```

依赖只能向下：`surface → domain → base → kernel`（装配根与类型门面为白名单例外）。
CI 由 `tool/layer_audit.py --fatal` 强制；另有 i18n、动效分级、性能反模式三道门禁。

## 仓库结构

```
.github/workflows/   CI：质量门、构建矩阵、发布、统计
assets/              icon（SVG 为唯一事实来源 → 三端派生）、i18n、boot、mods、theme_packs
docs/                USAGE.md、I18N.md
lib/                 源码（四层架构，见上）
changed/             更新日志站点源（同时发布到 GitHub Pages 与 Netlify）
release_notes/       逐版本发布说明（中英对照）
test/                测试
tool/                图标派生、平台规格注入、打包、审计门禁、统计图表
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [`docs/USAGE.md`](docs/USAGE.md) | 使用说明 |
| [`docs/I18N.md`](docs/I18N.md) | 多语言维护手册 |
| [`CHANGELOG.md`](CHANGELOG.md) | 完整版本历史 |
| [`release_notes/`](release_notes/) | 逐版本发布说明 |
| <https://oglb.344977.xyz/> | 更新日志站点（逐版本中英对照） |

## 版本与发布

- 语义化版本 `vX.Y.Z`；跳过的版本在 `CHANGELOG.md` 中标注；
- 发布说明**中英逐条对照**，包含 新增 / 变更 / 修复 / 已知限制 / 产物；
- 星标与提交历史见页首图表，数据源为 `stats` 分支的 `history.json`。

## 许可

[Apache-2.0](LICENSE)。第三方依赖许可见应用内「许可」页面与 [`NOTICE`](NOTICE)。
