# 性能

本文说明 OgL 的**冷启动**、**着色器（动画卡顿的主要来源）**与**渲染**三条线
各自的现状、已实施的优化，以及尚未实施的项。

## 一、冷启动

### 启动路径（首帧之后才算"用户已看到东西"）

```
进程启动
  └─ WidgetsFlutterBinding.ensureInitialized()
  └─ runApp(OgLBootSplash)        ← 首帧（零依赖占位屏，不读磁盘、不碰内核）
  └─ OgLLogFile.init()            ← 日志落盘（磁盘写入探针）
  └─ baseLayerModulesOnPlatform() ← 平台存储解析（目录探针）
  └─ kernel.boot()                ← 信任链校验（Ed25519 验签） + 模块装配 + i18n
  └─ runApp(OgLApp)               ← 真实界面（顶替占位屏）
  └─ 权限自检（fire-and-forget）   ← 不阻塞首屏
```

### 已实施

1. **首帧占位屏**：`runApp` 之前有四段 `await`（日志落盘 / 平台存储 / 内核
   引导 / 权限自检），期间若不渲染任何内容，用户面对的是系统 splash 之后的
   空白。现先渲染 `OgLBootSplash`，初始化完成后第二次 `runApp` 顶替
   （Flutter 官方推荐的启动模式）。占位屏不读磁盘、不显示用户数据，
   **不削弱**引导清单的信任链语义。
2. **权限自检移出关键路径**：它是诊断性复核，最坏耗时 5 秒（超时上限），
   没有"必须做完才能显示界面"的理由 → 移到 `runApp` 之后 fire-and-forget。
3. **目录探针有缓存**：`OgLAppDirs` 的根目录解析结果缓存（`_rootCache`），
   同一次会话不重复探测。

## 二、着色器（动画卡顿的主要成因）

### 各平台的实际机制

| 平台 | 渲染后端 | 着色器策略 |
| --- | --- | --- |
| Android | **Impeller**（Flutter 3.16+ 默认） | **构建期 AOT 编译**全部着色器，随产物打包 → **运行时不存在着色器编译抖动** |
| iOS / macOS | **Impeller** | 同上 |
| Windows / Linux | Skia | 运行时按需编译；可用 SkSL bundle 预编译（见下） |
| Web | CanvasKit | 预编译着色器内置于 CanvasKit 资源中 |

**结论**：移动端（主要目标平台）的"预编译着色器"由 Impeller 在**构建期**完成，
不需要也不适用 SkSL bundle。真正需要预编译的是**桌面端（Skia）**。

### 桌面端 SkSL 预编译（已就位，待采Bundle）

`build.yml` 已加钩子：构建 Windows / Linux 时，若仓库存在
`sksl/warmup.sksl.json`，自动追加 `--bundle-sksl-path`；不存在则留空跳过
（不影响构建）。

采集步骤（**必须在目标设备上做**，SkSL 与 GPU 驱动强相关）：

```bash
# 1) 在目标机器上以 profile 模式运行，动效缓存写入指定文件
flutter run --profile --cache-sksl --write-sksl-on-exit sksl/warmup.sksl.json
# 2) 在应用里把主要交互走一遍（列表滚动、页面切换、下拉刷新…）
# 3) 正常退出应用 → bundle 落盘
# 4) 把 sksl/warmup.sksl.json 提交进仓库 → CI 下次构建自动启用
```

本仓库**不预置** bundle：它依赖具体 GPU 驱动，凭 CI 无法生成（生成物与
驱动强相关，拿别人的 bundle 可能反而引入抖动）。

## 三、动画与渲染

### 已实施的抗卡顿设计

1. **档位质量表**（`surface/app/motion.dart`）：按设备能力分级（时长 / 位移 /
   错峰上限 / 是否缩放全部由档位决定）。低档位自动缩短甚至关闭动画。
2. **列表错峰有上限**：`OgLAnim.staggerOf(context, index)` 对超出档位上限的
   序号返回 `null`，`OgLReveal` 见到 `null` **直接渲染**（不进入动画）——
   长列表滚动时不会因为"每一行都入场动画"而发涩。
3. **逐项独立绘制边界**：`OgLReveal` 每项包 `RepaintBoundary`，动画期间不牵连
   整个列表重绘。
4. **零 saveLayer 型效果**：全项目**没有** `BackdropFilter` / `ImageFilter.blur` /
   `ColorFiltered` / `ShaderMask`（这些每帧都会触发离屏合成，是卡顿的典型成因）。
   该事实已**由门禁守住**（见下）。

### 门禁（`tool/perf_audit.py --fatal`，CI 强制）

- `shrinkWrap: true`（长列表禁用，会退化为一次性布局）
- `MediaQuery.of(context)`（宽依赖，应改用 `MediaQuery.sizeOf` 等窄依赖）
- `Opacity(`（非 `Animated`）——直接 `Opacity` 会触发 `saveLayer`
- **`BackdropFilter` / `ImageFilter.blur` / `ColorFiltered` / `ShaderMask`**（新增）
- 急加载长列表（`ListView(children: [...])` 内含 `for (`）

确有必要使用时，须在 `perf_audit.py` 白名单登记并写明理由（现有登记项即按此规则处理）。

## 四、尚未实施（记录在案）

- **延迟加载重页面**（`deferred as`）：`repo_page.dart` 体量较大，理论可用
  deferred import 降低首帧前的解析量。当前未实施——AOT / wasm 下的收益需
  实测支撑，且会改变构建结构。
- **启动耗时指标**：各阶段已用 `OgLAppLog.instance.step/result` 埋点，但尚未
  汇总成一条「启动总耗时=Nms」的结构化日志。
- **`itemExtent`**：列表项高度固定的场景（如下载管理）可设 `itemExtent`
  跳过逐项测量；当前列表项高度可变（进度条条件显示），未启用。
