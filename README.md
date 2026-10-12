<div align="center">

# OhGithubLost

**GitHub 仓库管理客户端** · Web 版

浏览与编辑仓库、处理 Issues / Pull Requests / Releases / Actions、管理 Gist —— 不必打开浏览器。

[![Release](https://img.shields.io/github/v/release/yingo-server/OhGithubLost?label=release&color=blue)](https://github.com/yingo-server/OhGithubLost/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Web-informational)](#平台支持)
[![i18n](https://img.shields.io/badge/i18n-6%20languages-informational)](docs/I18N.md)

**在线使用：<https://oghapp.344977.xyz/>**

<br>

<img width="49%" alt="Star history" src="https://fastly.jsdelivr.net/gh/yingo-server/OhGithubLost@stats/stats/star-history.png">
<img width="49%" alt="Commit history" src="https://fastly.jsdelivr.net/gh/yingo-server/OhGithubLost@stats/stats/commit-history.png">

<sub>图表由 `stats` 分支每小时自动更新</sub>

</div>

---

> **分支说明** —— 本仓库有两条独立维护的分支：
>
> | 分支 | 内容 |
> | --- | --- |
> | `main` | 原生版（Android / Windows / Linux），产物走 GitHub Releases |
> | `web`（当前） | 浏览器版，产物构建后提交到 `app/` 目录并部署到站点 |
>
> 两条分支共享同一套 `lib/` 四层架构与 i18n 资源，平台接缝各自实现。

## 功能

| | |
| --- | --- |
| **仓库** | 目录树、文件预览、README 渲染；新建 / 编辑 / 删除 / 重命名（含目录递归）；提交与冲突处理 |
| **协作** | Issues、Pull Requests、Releases、Actions、Gist |
| **账号** | 多账号自由切换；令牌存于浏览器本地存储 |
| **下载** | 交浏览器接管；多连接分片与断点续传仅在原生分支可用 |
| **网络** | DoH 查询（`navigator` 允许时）；**不做静默降级** —— 失败如实报错 |
| **动效** | 四档（静默 / 保守 / 标准 / 拉满）；按档位分级预加载 |
| **语言** | 6 种（简体中文 / 繁體中文 / English / Deutsch / Français / Русский）；文案零硬编码，CI 强制校验 |

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Web | 支持 | Chrome / Edge / Firefox 89+，Safari 16.4+（dart2wasm 主载，dart2js 兜底） |
| Android / Windows / Linux | 见 [`main` 分支](https://github.com/yingo-server/OhGithubLost/tree/main) | 本分支不构建原生产物 |
| macOS / iOS | 弃用 | 最后支持版本 v5.3.0（原生分支） |

浏览器基线取 **WebAssembly GC** 支持：更老的浏览器自动走 dart2js 兜底产物。

## 构建

需要 Flutter **3.47.5**（Dart 3.13）。

```bash
flutter pub get
flutter run --debug                                     # 开发调试
flutter build web --release --wasm --no-web-resources-cdn   # 正式（主载）
flutter build web --release --no-web-resources-cdn          # 正式（兜底）
```

- `--wasm` 产出 `main.dart.wasm`（体积更小、启动更快）；
- `--no-web-resources-cdn` 让 CanvasKit 打进产物、从**同源**加载
  （默认会去 `www.gstatic.com` 拉，部分网络不可达）；
- 产物按版本发布到 `app/wasm/<版本数字>/` 与 `app/js/<版本数字>/`，
  入口页 `app/index.html` 按 WebAssembly 能力嗅探分流。

发布由 `.github/workflows/web.yml` 完成：双构建 → 校验 → 双桶发布 → 预热 CDN → 提交 `app/`。

## 架构

```
lib/
  kernel/    启动层  引导清单、Ed25519 签名、信任根
  base/      硬件层  网络（DoH / 重试 / 限流）、磁盘（localStorage / IndexedDB）
  domain/    逻辑层  GitHub API、本地深层信息
  surface/   交互层  UI、设置、i18n
```

依赖只能向下：`surface → domain → base → kernel`（装配根与类型门面为白名单例外）。
CI 由 `tool/layer_audit.py --fatal` 强制；另有 i18n、动效分级、性能反模式三道门禁。

## 仓库结构

```
.github/workflows/   CI：质量门、Web 构建与发布、统计
app/                 已发布的 Web 产物（按版本目录并存，入口页自动分流）
assets/              icon、i18n（6 语言）、boot、theme_packs
docs/                USAGE.md、I18N.md
lib/                 源码（四层架构，见上）
changed/             更新日志站点源
release_notes/       逐版本发布说明
test/                测试
tool/                平台规格注入、审计门禁、Web 发布与统计图表
web/                 PWA 脚手架（入口模板、清单、图标）
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [`docs/USAGE.md`](docs/USAGE.md) | 使用说明 |
| [`docs/I18N.md`](docs/I18N.md) | 多语言维护手册 |
| [`CHANGELOG.md`](CHANGELOG.md) | 完整版本历史 |
| [`release_notes/`](release_notes/) | 逐版本发布说明 |
| <https://yingo-server.github.io/OhGithubLost/> | 更新日志站点（逐版本中英对照） |

## 版本与发布

- 语义化版本 `vX.Y.Z`；跳过的版本在 `CHANGELOG.md` 中标注；
- 发布说明**中英逐条对照**，包含 新增 / 变更 / 修复 / 已知限制 / 产物；
- 版本目录一经发布即 `immutable` 缓存，优化必须走新版本号。

## 许可

[Apache-2.0](LICENSE)。第三方依赖许可见应用内「许可」页面与 [`NOTICE`](NOTICE)。
