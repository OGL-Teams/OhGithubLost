# 下载系统 LTS 前修复 · 三件套笔记

> 范围：重名处理 + 通知跳转 + 进度可见性。基准 HEAD `fbbd93a`
> （工作期间并行代理在 `105f7ed` 提交了发现页打磨与 sort_imports 修复，
> 本文档只记录下载域改动）。纪律：不改公开签名（只加可选参数 / 新方法）、
> 不改事件流既有字段（只加）、L1 不 import L2/L3、i18n 六语言对齐。

---

## 1. 重名文件处理（自动改名不覆盖）

**问题**：`ix_download_backend_io.dart` 对已存在目标直接建库任务合并覆盖；
分片引擎 `range_download_io.dart:190` 也对已存在 target 直接 openWrite 拼接。
用户已下载的 `a.zip` 会被**静默替换**——数据无价。

**改动文件**
- `lib/domain/ix/ix_download.dart`：
  - 契约 `IxDownloadBackend` 新增 `resolveUniqueSavePath(spec, {intendedPath})`
    ——**带默认实现**（`intendedPath ?? pathFor(spec)`，即不改名），
    既有自定义后端向后兼容；
  - `IxDownloadSpec.copyWith` 增加**可选** `fileName` 参数（原 `copyWith(url:)` 照用）；
  - `enqueue` 在 `pathFor` 之后、**入队之前**做重名裁决（路径此时已可知）；
  - 管理器新增 `_retrySavePaths`（per-id 豁免表）：`remove()` 时记住被移除
    任务的 `savePath`，同 id 再次入队 → 跳过改名（同源覆盖 = 正确语义）；
    `enqueue` 消费一次即删（`clearFinished` 同步清理，不跨会话累积）；
  - 新增文件级纯函数 `_lastSegmentOf`（从最终路径取末段文件名）。
- `lib/domain/ix/ix_download_backend_io.dart`：
  - 抽出 `_resolveDirectory`（`_build` 与 `resolveUniqueSavePath` 共用同一份
    落盘目录口径，保证「探测到的路径」=「库任务真正写的路径」）；
  - 覆写 `resolveUniqueSavePath`：目标存在 → `stem (i).ext`（i=1..999，
    探测到第一个不存在的序号）；探测抛错 → 原样返回，**不阻塞下载**。
- `lib/base/net/*` 与 `lib/kernel/contract/download_engine.dart`：**未改**。
  分片引擎写 `targetPath` 由中枢层传入 —— 中枢层传进来的已经是改好名的
  最终路径，引擎侧天然不覆盖；无需在 L1 重复探测。

**关键决策**
- 探测时机 = **入队时**（不是完成时）：完成时才发现同名等于把用户文件
  暴露在覆盖险境一整个下载周期。
- 同 id 重试的判定 = 中枢层显式豁免（`_retrySavePaths`），而不是"快照里
  有 savePath 就跳过"——后者会把"移除 A 后新任务 B 撞名"误判成重试。
- 引擎（L1）不做探测：职责收在中枢层一处，两条路径（分片 / 库任务）
  自动都覆盖。
- i18n：改名不需要打扰用户（文件管理页本来就显示最终文件名），
  未新增提示键；如需提示可用 `savePath` 展示，本轮不加。

**测试** `test/domain/ix_download_dedup_test.dart`
- `resolveUniqueSavePath`：目标不存在 → 原样；存在 → `a (1).zip`（原文件
  字节不动）；`a (1).zip` 也存在 → `a (2).zip`。
- `IxDownloadManager.enqueue`：目录已有 `a.zip` → `savePath` / `fileName`
  变为 `a (1).zip` 且原文件完好；移除后同 id 重新入队 → 仍 `a.zip`
  （同 id 重试保持原名；首轮撞名仍正确改名为 `a (1).zip`）。

---

## 2. 通知点「查看下载」返回 null

**问题**：`OgLDownloadNotice.show(context…)` 捕获**发起页** context，
SnackBar 常驻 8s，期间用户可能已离开该页 → `Navigator.of(context)` 用旧
context push 不可靠（Navigator 不在祖先链时抛错 / 静默无效）。

**改动文件** `lib/surface/pages/download_manager_page.dart`
- `show` 增加**可选** `rootContext` 参数（调用方可显式给根 context；
  不传 = 行为不变，向后兼容）；
- `_jumpToManager` 跳转优先级：
  1. `rootContext`（调用方显式给的根 context，测试可注入）；
  2. `OgLApp.navigatorKey.currentContext`（应用根 Navigator，
     与 `error_surface.dart` 的 `OgLNoticeHost` 同一机制）；
  3. 都不可用 → **降级不静默**：复制管理页路径（`ogLCopyText('/download')`）
     + 弹「未能打开下载管理页，路径已复制」提示（`force: true` 绕过去重）。

**关键决策**
- 复用 `OgLApp.navigatorKey`（`og_l_app.dart` 已有，main.dart 注入），
  不新建全局 key——一个应用一个根。
- 新增页面 import：`download_manager_page.dart → ../app/og_l_app.dart`
  （L3→L3，`og_l_app.dart` 不反向 import 任何 pages，无循环）。

**测试** `test/surface/download_notice_jump_test.dart`
- pump 带 `navigatorKey` 的 MaterialApp，触发 queued 通知 → 断言出现
  `SnackBarAction` → 点击 → `DownloadManagerPage` 被推入根 Navigator。

---

## 3. 进度可见性

**问题**：分片任务（connections>1）的字节进度已按事件聚合到快照
（`received` / `total` / `bytesPerSecond`），但页面副标题只显示
「分类 · 大小 · 速率」——总量、百分比、线程数都不可见。

**改动文件**
- `lib/domain/ix/ix_download.dart`：管理器新增 `connectionsOf(id)`
  （`_rangeConnections[id] ?? 1`，非分片任务 = 1）。
- `lib/surface/surface_bridge.dart`：新增
  `isRangedDownload(id)` / `downloadConnectionsOf(id)` 透传（新增方法，
  既有方法不动）。
- `lib/surface/pages/download_manager_page.dart`：
  - `_subtitleOf(task, {required connections})`：分类 · `已收 / 总量`
    （`ghSizeText`）· `N%`（total>0 时）· `速率/s`（running 时）·
    「{n} 线程」（connections>1 时）——全部走 i18n，无硬编码中文；
  - 既有 `multiConnection` 图标 / `_quantizeSpeed` 节流重建逻辑不动。

**i18n 新增键**（`assets/i18n/<6 locales>/download_manager_page.json`，
共 12 条 = 2 键 × 6 语言，zh 基准）：
- `threads`：`{n} 线程` / `{n} threads` / `{n} Verbindungen` /
  `{n} connexions` / `{n} соед.` / `{n} 線程`
- `viewDownloadsFallback`（修 2 的降级提示，六语言同步补）
- `tool/i18n_scan.py --check` = exit 0（键集合一致 + 值全字符串）。

**测试**：进度行展示由既有 `test/surface/` 快照类测试覆盖布局；
新增数值格式化不引入纯函数（直接复用 `ghSizeText` + `task.percent`）。

---

## 门禁（本地可跑的十一道）

| 门禁 | 结果 |
|---|---|
| layer_audit / contract_audit / ui_audit / motion_audit / perf_audit / ci_config_audit / gate_of_gates（--fatal） | 全 0 |
| i18n_scan --check | 0 |
| version_sync / sort_imports --dry-run --fatal / changed/check_content --check | 全 0 |
| dart format --language-version=3.6 --set-exit-if-changed --output=none lib test | 我改动的文件全部干净；`search_page.dart` / `discover_rows.dart` / `ui_regression_test.dart` 为 **HEAD 基线既有漂移**（另一代理并行改动，未触碰、不归属本任务） |

类型级验证受限于本地无 Flutter SDK（`dart pub get` 因 Flutter 依赖不可用），
编译正确性靠 CI `flutter analyze --fatal-infos`；所有改动均为加法
（新可选参数 / 新方法 / 新键），无既有签名或字段变更。

## 遗留 / 未决
- 「多线程不充分」（问题 ④）不在本任务范围：连接数上限、每分片独立
  限速等增强留待后续批次。
- 真机验收项（公共目录 / SAF 两档下的重名行为）见
  `docs/LTS_1260_CHECKLIST.md` 第一节。
