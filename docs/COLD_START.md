# 冷启动优化

本文说明 OgL 的启动路径、已实施的优化，以及各项优化的依据与边界。

## 一、启动路径

```
进程启动
  └─ WidgetsFlutterBinding.ensureInitialized()
  └─ runApp(OgLBootSplash)          ← 首帧（零依赖占位屏）
  └─ OgLLogFile.init()              ← 日志落盘（后续日志的前提）
  └─ baseLayerModulesOnPlatform()   ← 平台存储解析
  └─ kernel.boot(modules)           ← 信任链校验 + 模块装配
  └─ runApp(OgLApp)                 ← 真实界面（顶替占位屏）
  └─ 权限自检（fire-and-forget）     ← 不阻塞首屏
```

## 二、已实施的优化

### 1. 首帧先上占位屏（消除启动白屏）
`runApp` 之前有四段 `await`（日志落盘 / 平台存储 / 内核引导 / 权限自检），
合计可达数百毫秒至数秒。此前期间不渲染任何内容，用户看到系统 splash 之后
的空白，观感等同于应用无响应。

现改为**第二次 `runApp`** 模式：先渲染零依赖的 `OgLBootSplash`（不读磁盘、
不碰内核、不显示任何用户数据），初始化完成后再 `runApp(OgLApp)` 顶替。
这是 Flutter 官方推荐的启动模式；占位屏不削弱引导清单的信任链语义
（校验仍在显示真实界面之前完成）。

### 2. 权限自检移出关键路径
权限自检（`ogLRunPermissionSelfTest`）是**诊断性**复核，没有"必须做完才能
显示界面"的理由，且走平台通道、最坏情况耗时 5 秒（超时上限）。现移至
`runApp` 之后的 fire-and-forget，结果以日志与通知中心呈现。

### 3. 分割 APK（`--split-per-abi`）
Android 按 ABI 拆分产物：单架构 APK 体积显著小于 universal 包，解析与
首次加载更快。通用包仍单独产出，供不确定机型的用户使用。

### 4. Web 端 `--wasm` + `--no-web-resources-cdn`
- `--wasm`（dart2wasm）比 dart2js 有更好的运行时性能；
- `--no-web-resources-cdn` 把 CanvasKit 等资源改为**同源加载**，消除冷启动
  对第三方 CDN 的首次往返（此前实测 jsDelivr 冷启动 6~19 秒）。

## 三、着色器编译

| 平台 | 渲染后端 | 着色器策略 |
| --- | --- | --- |
| Android | Impeller（Flutter 3.16+ 默认） | Impeller 自带预编译着色器，**不存在 SkSL 首次编译抖动** |
| iOS / macOS | Impeller | 同上 |
| Windows / Linux | Skia | 使用 `--release` 的默认行为；如需进一步优化可在真实设备上采集 SkSL 后经 `--bundle-sksl-path` 打包 |
| Web | CanvasKit（wasm）/ html | CanvasKit 自带预编译着色器 |

**桌面端 SkSL 的现状**：`--bundle-sksl-path` 需要一个**在真实设备上运行并
采集**的 SkSL 包，CI 无法凭空生成（生成物与驱动的着色器变体强相关）。因此
本仓库**不打包** SkSL，桌面端沿用 Skia 默认策略。

## 四、构建参数

`--tree-shake-icons` 在 `flutter build --release` 下**默认启用**（未显式传入
不代表未生效）；构建脚本未传 `--no-tree-shake-icons`，图标字体已被裁剪。

## 五、尚未实施（记录在案）

- **延迟加载重页面**（`deferred as`）：`repo_page.dart` 等页面体量较大，
  理论可用 deferred import 减少首帧前的解析量。当前未实施——主流平台
  （AOT / wasm）的收益需要实测数据支撑，且会改变构建结构。
- **启动耗时埋点**：`OgLAppLog.instance.step/result` 已记录各阶段，但尚未
  汇总成"启动总耗时"指标；后续可加一条 `启动耗时=Nms` 的结构化日志。
