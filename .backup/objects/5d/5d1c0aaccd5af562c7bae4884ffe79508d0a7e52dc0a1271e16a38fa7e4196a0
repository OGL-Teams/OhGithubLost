# OGL · Web（wasm · 实验性）

> **定位**：Web 只是五平台之外的**实验性**补充产物。
> **编译失败不影响发布** —— `web` 是独立工作流，既不被 `build.yml` 的
> `release` 任务依赖，自身也带 `continue-on-error`（CI 实证：web 腿失败时，
> CI 与 build 两条腿仍是 success）。

## 一、构成

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/web.yml` | 独立工作流：脚手架 → 守卫注入 → 编译 → 校验 → 发布 `app/` |
| `tool/web_build.py` | `--preflight` / `--prepare` / `--verify` / `--publish` 四步门禁 |
| `app/` | **构建产物目录**（每次先清空后重建，只保留最新一套） |

## 二、流水线

1. `flutter create --platforms=web … .` —— 平台目录**构建时生成**，不入库。
2. `python3 tool/web_build.py --preflight --prepare`
   - `--preflight`：预检 `pubspec.lock`，点名会阻塞 wasm 的 `dart:ffi` 依赖；
   - `--prepare`：体检 `web/index.html`（`flutter_bootstrap.js` 必须在），
     写出 `web/web_api_guard.js`，把 `<script>` **动态注入** `</head>` 之前（幂等），
     并写入 COOP/COEP `<meta>` 兜底。
3. `flutter build web --release --wasm --base-href /app/`
4. `python3 tool/web_build.py --verify` —— 核对 `index.html` / `flutter_bootstrap.js` /
   `main.dart.js` / `.wasm` / 渲染引擎 / 守卫已注入，缺一即**抛错**。
5. `python3 tool/web_build.py --publish` —— **先 `rmtree` 再重建** `app/`。
6. 用 GitHub REST（Git Data API）把 `app/` 提交回 `main`（本机 git 不可用）。

## 三、浏览器 API 守卫

守卫在 Flutter 引擎加载**之前**运行，缺任何一项即**抛错**（`OgLWebApiUnsupported`），
把原因挂到 `window.__oglWebApiFailures`，绝不静默白屏。

| 能力 | 为什么必需 |
| --- | --- |
| `WebAssembly` + `instantiateStreaming` | wasm 目标本身 |
| `fetch` / `ReadableStream` | 网络层与流式下载 |
| `TextDecoder` | 文本 / JSON 解码 |
| `crypto.getRandomValues` | 随机数 |
| `indexedDB` | 本地缓存 |
| `atob` / `btoa` | Base64 |
| `URL` | 地址拼接 |
| `Worker` | 后台任务 |
| `performance.now` | 动画计时 |
| `SharedArrayBuffer` + `crossOriginIsolated` | 有 SAB 却未隔离即报错（需 COOP/COEP） |

> 权威的跨源隔离方式是 **HTTP 响应头** COOP/COEP；`index.html` 里的
> `<meta>` 只是静态托管场景的兜底。

## 四、已知阻塞（当前编译不通过的原因）

`saf_util` / `saf_stream` → `jni` → `ffi` → **`dart:ffi`**，而 wasm 不支持
`dart:ffi`。dart2wasm 因此报：

```
Error: Dart library 'dart:ffi' is not available on this platform.
```

这属于**已知且被容忍**的状态：`--preflight` 会在编译前点名这些依赖，
web 腿失败也不影响正式平台构建与发布。要真正产出 wasm，需为
SAF / 文件系统能力补 web 实现。