# v12.6.0 LTS 下载链路发布后专项复核（只读审查）

- 审查对象：发布提交 `5c84d6f`（v12.6.0 LTS）中的下载链路；同时复核审查期间工作树已前进到的 `70dda36` / `b2ff56f`（12.6.1 补丁与发版提交）。
- 只读约束：未修改源码 / 文档，未执行 `git commit` / `git push`；唯一写入为本报告。`git status --porcelain` 在复核时为干净工作树。
- 环境限制：本地无 Flutter SDK，未做 `flutter test` / `flutter build web`；类型与编译结论交 CI。以下「确证」均来自源码的静态可达路径，「推测」明确标注为需真机 / SDK 复现。
- 重要时序说明：审查期间另一代理把 HEAD 从 `5c84d6f` 推进到 `70dda36`（重名落盘 P0 补丁）再到 `b2ff56f`（v12.6.1 发版）。因此 C-01 是 **v12.6.0 已发布产物中的确证 P0，当前 HEAD 已部分修复**；其余 C-02 起均按当前 `b2ff56f` 源码复核，**仍存在**。

## 结论速览

- 用户四反馈中，「通知点查看返回 null」的主路径基本修好；「重名文件处理」只是修了一半；「进度模糊」在暂停 / 恢复、总长未知、速率估算上仍有真实缺陷；「成熟库 + 多线程」引入了 `resume` 抢跑、回退重入等回归。
- 最大剩余风险不是崩溃，而是**数据无价类覆盖**：`_retrySavePaths` 只记 id 不记上一轮裁决后的路径，导致「原名已存在 → 自动改名 `a (1).zip` → 从列表移除 → 再下载同一附件」会写回 `a.zip`，覆盖用户原有文件。
- 建议：即使已发 12.6.1，也不应宣布下载链路 LTS 稳定；应立刻补发 12.6.1.1 / 12.6.2，至少先修 C-02 ~ C-09。
- 计数：**确证 18 条（P0 2 / P1 7 / P2 9）**；**推测 4 条（P1 1 / P2 3）**。

## 结构完整性（通过）

对当前 `lib/domain/ix/ix_download.dart` 做字节级与结构级复核：

- `62464 bytes / 1641 lines`，`U+FFFD` 替换符 **0** 个；`dart format` 风格连续。
- 去注释后大括号 `212 / 212`、圆括号 `419 / 419` 配对，无截断。
- 类成员无重复声明：正则抽出的 `enqueue` / `pause` / `resume` / `cancel` / `dispose` 各出现两次，分别属于 `IxDownloadBackend` 抽象契约与 `IxDownloadManager` 实现，属预期；`_subscription` 的两次出现是构造器赋值（518）与字段声明（571），不是重复字段。
- `_backend` / `_diagnostics` / `_exporter` / `_engine` / `notifications` / `preferredConnections` / `_roundOf` / `_rangeConnections` / `_urlCandidates` / `_specs` / `_retrySavePaths` / `_pausedIds` / `_snapshots` / `_lastSample` / `_lastNotify` / `_disposed` / `_tasksCache*` / `_exportedToSaf` / `_expectedSha256` 均有读点；无 `TODO` / `FIXME` / 「半成品」残留。
- 但「结构完整」不等于「逻辑自洽」：下面 C-02 ~ C-10 都是这份完整文件里的状态机漏洞。
- CI 全绿也不能替代行为测试：`test/surface/download_notice_jump_test.dart:25-40`、`test/surface/download_notice_jump_test.dart:46-64` 主要是 `expect(source, contains(...))` 的源码字符串断言，不执行真实 Navigator push / 文件系统裁决。

---

# 一、确证缺陷

## C-01 · P0 · v12.6.0 重名裁决只改名，不改正落盘路径（当前 HEAD 已部分修复）

**范围**：`5c84d6f` 发布版本确证；`70dda36` 修复了单连接与快照路径，但见 C-02/C-08 仍有窗口。

**证据**（v12.6.0 `lib/domain/ix/ix_download.dart:754-760, 778, 904`）：

```dart
if (uniqueName.isNotEmpty && uniqueName != safeName) {
  finalName = uniqueName;
  _specs[id] = _specs[id]!.copyWith(fileName: finalName);
}
_snapshots[id] = queued.copyWith(savePath: savePath, fileName: finalName);
...
await _backend.enqueue(spec);   // 旧 spec = a.zip
...
targetPath: snap.savePath,      // 旧 savePath = a.zip
```

`resolveUniqueSavePath` 返回的是 `.../a (1).zip`，但 `savePath`、单连接入队 spec、分片 `targetPath` 仍用 `a.zip`：页面显示 `a (1).zip`，库 / 分片引擎实际写 `a.zip`，直接覆盖既有文件。

**当前修复**（`b2ff56f` `lib/domain/ix/ix_download.dart:750-785`）：新增 `finalPath = unique`、`finalSpec = _specs[id] ?? spec`，快照与单连接入队改用裁决后的值；`_runRanged` 第 809 行重新取 `_snapshots[id]`，故 `targetPath: snap.savePath` 在首次入队时通常已是 `finalPath`。

**落地修法**：保留该修复并补行为测试：真实文件系统先放 `a.zip`，分别以 `connections=1` 与 `connections=4` 入队，断言 `a.zip` 字节未变且新文件为 `a (1).zip`；禁止只用源码字符串断言。

---

## C-02 · P0 · 同 id 重试豁免丢失「上一轮裁决后的路径」，再下载覆盖原文件

**范围**：当前 `b2ff56f` 仍存在。

**证据**：

- `lib/domain/ix/ix_download.dart:1232-1237`：`remove` 只登记 id，丢弃 `knownPath` 的末段与路径：

```dart
final String? knownPath = _snapshots[id]?.savePath;
if (knownPath != null && knownPath.isNotEmpty) {
  _retrySavePaths.add(id);       // 只存 id，没存 a (1).zip
}
```

- `lib/domain/ix/ix_download.dart:736, 751, 765`：`enqueue` 重新从原 `safeName` 计算 `savePath`，豁免命中后既不读旧路径也不重新裁决：

```dart
final String savePath = await _backend.pathFor(spec); // spec.fileName 仍是 a.zip
final bool keepName = _retrySavePaths.remove(id);
if (!keepName) { /* resolveUniqueSavePath */ }
_snapshots[id] = queued.copyWith(savePath: finalPath, fileName: finalName);
```

- `lib/domain/ix/ix_download_backend_io.dart:145-150`：`pathFor` 由 `spec.fileName` 构造路径。

**复现**：目录已有用户文件 `a.zip` → 下载同名附件 → 裁决为 `a (1).zip` 并成功 → 点「移除」（不动磁盘）→ 再点同一附件下载 → `_retrySavePaths` 命中，`finalPath = .../a.zip`，`finalSpec.fileName = a.zip` → 库 / 分片写回 `a.zip`，**用户原有文件被覆盖**。注释所称「覆盖自己上一轮的成品」实际覆盖的是别人的 `a.zip`。

**落地修法**：把 `_retrySavePaths` 从 `Set<String>` 改成 `Map<String, ({String fileName, String savePath, DateTime at})>`；`remove` 存 `knownPath` 与 `_snapshots[id].fileName`，`enqueue` 命中时直接把 `spec` 与快照恢复成上一轮的 `finalName/finalPath`，并只在本任务确实拥有该路径时允许覆盖；超时 / `clearFinished` / 不同 URL 时清除。再下载同一附件但不再是「撤销移除」语义时，重新走 `resolveUniqueSavePath`。

---

## C-03 · P1 · 探测异常或 999 个候选都占用时「原样返回」= fail-open 覆盖

**证据**（`lib/domain/ix/ix_download_backend_io.dart:116-140`）：

```dart
if (!await candidate.exists()) { return base; }
...
for (int i = 1; i < 1000; i++) {
  final String next = '$dir/$stem ($i)$ext';
  if (!await File(next).exists()) { return next; }
}
// 999 个都已占用（理论极端）：宁可放弃改名也不静默覆盖。
return base;          // ← 已知 base 存在
} catch (_) {
// 探测失败（无文件系统能力等）：维持原路径。
return base;          // ← 可能已被占用
}
```

`enqueue` 没有对「返回路径是否仍被占用」做二次确认，随后 `spec.fileName = a.zip` 入队，库 / `openWrite()` 会覆盖。注释「宁可放弃改名也不静默覆盖」与代码行为相反。

**落地修法**：失败闭合 —— 抛 `FileSystemException` / `IxDownloadError(disk, ...)`，由 C-15 的入队异常路径置 `failed`，或改用 UUID / 时间戳后缀（`a.<uuid>.zip`）并 `File.open(mode: FileMode.writeExclusive)` 占位；任何情况下不得返回已存在的路径。补单测 Mock 文件系统让 `exists()` 抛异常，断言不返回 base。

---

## C-04 · P1 · 重名裁决是 TOCTOU：两个不同 id 可同时拿到同一个 `a (1).zip`

**证据**：

- `lib/domain/ix/ix_download_backend_io.dart:130-133`：只 `exists()` 检查，不占位：

```dart
final String next = '$dir/$stem ($i)$ext';
if (!await File(next).exists()) { return next; }
```

- `lib/base/net/range_download_io.dart:127-131, 172`：分片引擎直接以目标路径 `.partN` 写，合并时 `target.openWrite()` 截断：

```dart
final File target = File(request.targetPath);
final List<File> parts = <File>[... File('${request.targetPath}.part$i')];
...
final IOSink sink = target.openWrite();
```

- `lib/domain/ix/ix_download_backend_io.dart:155-168`：库任务也只带 `filename`，没有独占占位。

两个并发 `enqueue`（不同 URL / 不同 `safeName`，但都裁决到 `a (1).zip`）在「检查 → 写」之间互不排斥；后写者覆盖先写者，且 `.partN` 可能交叉删除。

**确证范围**：源码确实没有原子占位 / 锁；「库最终是否覆盖」属实现细节，见 S-02。

**落地修法**：裁决阶段用 `File.open(mode: FileMode.writeExclusive)` 创建 0 字节占位文件并把该路径作为唯一票据传给后端；后端改用「按路径写」而非只按 `filename` 推导，或引入进程内 `Map<path,id>` + `Lock` 串行化裁决到入队；分片 `.partN` 也要以占位票据派生，避免同名互删。

---

## C-05 · P1 · 「撤销移除」是死路，且会遗留永不消费的重名豁免

**证据**：

- `lib/surface/pages/download_manager_page.dart:336-342`：撤销调用 `retryDownload`：

```dart
setState(() => _lastRemoved = null);
await widget.surface.retryDownload(task.id);
```

- `lib/domain/ix/ix_download.dart:1226-1241`：`remove` 已删 `_specs` / `_snapshots`：

```dart
_specs.remove(id);
_snapshots.remove(id);
```

- `lib/domain/ix/ix_download.dart:1192-1200`：`retry` 无 spec 只写诊断后 return：

```dart
final IxDownloadSpec? spec = _specs[id];
if (spec == null) {
  _diagnostics?.warn('DL', '重试请求落在已不存在的任务上（spec 已清）：$id',
      code: 'OGL-DL-409');
  return;
}
```

页面没有任何用户可见反馈，任务也不会重新下载；`remove` 第 1237 行塞入的 `_retrySavePaths[id]` 一直留着，直到未来某次同 id `enqueue` 被误消费（与 C-02 叠加更危险）。

**落地修法**：`remove` 保留一份 tombstone（完整 url / headers / fileName / category / connections / fallbackUrls / expectedSha256 / 裁决后路径）供 `_undoRemove` 调 `enqueue` 重建，或在 `retry` 发现 spec 缺失时用 tombstone 恢复；超过 1 个撤销周期或 `clearFinished` 后清理 tombstone 与 `_retrySavePaths`；撤销入口加可见失败提示。

---

## C-06 · P1 · `resume` 把普通库任务抢跑成分片任务，断点续传变「重新下载」

**证据**（`lib/domain/ix/ix_download.dart:1143-1155`）：

```dart
final int connections = preferredConnections ?? _rangeConnections[id] ?? 1;
if (_specs.containsKey(id) && _engine != null) {
  _rangeConnections[id] = connections;
  _pausedIds.remove(id);
  _applyStatus(id, IxDownloadStatus.running);
  await _runRanged(id: id, connections: connections);
  return;
}
...
await _backend.resume(id);
```

条件只要求「有 spec + 有 engine」，**不判断任务当前是否分片、不判断 `supportsRanged`、不判断 `connections > 1`**。装配根 `lib/domain/domain_bridge.dart:401` 总是注入 `OgLRangeDownloader()`，所以任何原生库任务的 `_specs.containsKey(id)` 都为真。

后果链：`resume` → `_runRanged(connections: 1)` → `lib/base/net/range_download_io.dart:124-125` 因 `plan.length < 2` 抛 `DownloadUnsupported` → `_fallbackToSingle` 重新 `pathFor` + `_backend.enqueue(fallback)`；`lib/domain/ix/ix_download_backend_io.dart:161-168` 的 `enqueue` 先 `cancelTaskWithId` 再入队，暂停中的库任务被取消并从 0 重下。Web 分支同样会因 `engine != null` 进入 `_runRanged`，探测抛 `DownloadUnsupported` 后回退再次打开浏览器下载。

**落地修法**：只有 `_rangeConnections[id] != null && connections > 1 && _backend.supportsRanged` 才进 `_runRanged`；其余一律 `if (!_backend.supportsPauseResume) _rejectUnsupported(...) else await _backend.resume(id)`。把「设置里新并发数」只应用于失败重试 / 明确的多线程任务，不要改变库任务的恢复语义。

---

## C-07 · P1 · `resolveUniqueSavePath` 的 await 窗口里 `remove` 会让已删任务复活或空指针崩溃

**证据**（`lib/domain/ix/ix_download.dart:736-765`）：

```dart
final String savePath = await _backend.pathFor(spec);
if (_disposed || !identical(_snapshots[id], queued)) { return ...; }   // 第一次检查
...
final String unique = await _backend.resolveUniqueSavePath(spec, ...);   // 第二次 await
final String uniqueName = _lastSegmentOf(unique);
if (uniqueName.isNotEmpty && uniqueName != safeName) {
  finalName = uniqueName;
  _specs[id] = _specs[id]!.copyWith(fileName: finalName);               // remove 后为 null
}
final IxDownloadSpec finalSpec = _specs[id] ?? spec;
_snapshots[id] = queued.copyWith(savePath: finalPath, fileName: finalName); // 复活
```

`remove`（1226-1241）在第二个 await 期间清 `_specs` / `_snapshots`。若发生改名，`_specs[id]!` 直接 `Null check operator used on a null value`；若未改名，`_snapshots[id] = ...` 把已移除任务写回。注意此时快照的 `savePath` 仍是 `''`（725 行），因此 `remove` 不会登记豁免，反而使 C-02 的路径恢复更无从谈起。

**落地修法**：每个 await 后都重新检查 `_disposed || !identical(_snapshots[id], queued)`，并把裁决结果保存在局部变量，禁止在 await 后再次 `_specs[id]!`；`_specs` 的写入用 `finalSpec` 局部副本 + `putIfAbsent` 式条件写。补并发测试：`pathFor`/`resolveUniqueSavePath` 用 Completer 挂住，期间 `remove`，断言既不复活也不抛异常。

---

## C-08 · P1 · `_fallbackToSingle` 是异步重入点，旧回合可覆盖新回合并重复入队

**证据**：

- `lib/domain/ix/ix_download.dart:935-944`：只在进入 fallback **之前**校验回合：

```dart
if (_roundOf[id] != myRound) { return; }
await _fallbackToSingle(id, spec, url: uri.toString(), ...);
```

- `lib/domain/ix/ix_download.dart:1023-1050`：fallback 内部又有 `await _backend.pathFor(fallback)`，之后无回合校验，无条件改快照并入队：

```dart
_rangeTokens.remove(id);                 // 可能删掉新回合的 token
_rangeConnections.remove(id);
final String path = await _backend.pathFor(fallback);   // await 窗口
...
_snapshots[id] = current.copyWith(savePath: path, status: queued, ...);
await _backend.enqueue(fallback);         // 与新分片任务并发写同一 id
```

若用户在 `pathFor` 挂起期间点「继续 / 重试」，新 `_runRanged` 把 `_roundOf[id] + 1` 并写入 `running`；旧 fallback 回来后把状态打回 `queued`、覆盖 `savePath`，还向库再入队一个同 id 任务。两个下载源同时推进同一条记录，完成 / 失败事件交错。

**落地修法**：给 `_fallbackToSingle` 传 `round`，每次 await 后校验 `_roundOf[id] == round`，不一致立即退出；`_rangeTokens.remove(id)` 改成 `if (identical(_rangeTokens[id], token)) remove`；`_backend.enqueue` 前再次确认快照仍是 queued 且 spec 未变。最好把回退做成「先写一条 `fallbackPending` 意图，再由单飞调度器执行」。

---

## C-09 · P1 · 暂停 / 恢复后分片速率可为负，进度从旧采样值回跳

**证据**：

- `lib/domain/ix/ix_download.dart:893-903`：`_runRanged` 归零 `received`，但**不清 `_lastSample`，不清 `bytesPerSecond`**：

```dart
received: 0,
total: probe.total!,
error: null,
```

- `lib/domain/ix/ix_download.dart:1086-1100`：分片速率差分没有 `delta >= 0` 守卫（库路径 1547 行有）：

```dart
if (last != null) {
  final int ms = now.difference(last.at).inMilliseconds;
  if (ms >= 400) {
    speed = (received - last.received) * 1000 / ms;   // 新轮 0 - 旧轮大数 < 0
    _lastSample[id] = (at: now, received: received);
  }
}
...
status: IxDownloadStatus.running, received: received, bytesPerSecond: speed,
```

- `lib/surface/pages/download_manager_page.dart:558-560` + `lib/surface/util/gh_format.dart:99-103`：负数直接显示成 `-X B/s` / `-X.0 MB/s`。

暂停数秒后恢复，旧样本仍在，`ms >= 400` 必然命中，首几个分片回调给出明显负速率；`TweenAnimationBuilder` 的 `end` 从旧进度掉回 0，进度条回退。库路径虽有不改负速度的守卫，但 `speed` 保留旧值，恢复后仍显示暂停前的速度。

**落地修法**：`pause` / `cancel` / `resume` / `retry` / `_runRanged` 起始处统一 `_lastSample.remove(id)` 并 `bytesPerSecond: 0`；速率计算统一加 `speed = max(0, delta * 1000 / ms)`，负 delta 时把样本重置而非沿用；进度条动画用 `Tween(begin: previousProgress, end: currentProgress)` 或 `AnimatedBuilder` 保留上一帧值。

---

## C-10 · P2 · `total == 0` 在原生端也谎称「已交给浏览器下载」

**证据**（`lib/surface/pages/download_manager_page.dart:380-397`）：

```dart
// `total > 0` 才画进度条：Web 上总大小恒为 `0`...
if (task.total > 0) ...
else Text(_t('handedToBrowser'), ...);
```

`IxDownloadTask.total == 0` 既表示 Web 的「不可知」，也表示原生库尚未拿到 `Content-Length`、分片回退单连接后的 `total: 0`（`ix_download.dart:1038`）、入队后还没有进度事件。`lib/domain/ix/ix_download_backend_io.dart:262-269` 在 `expectedFileSize <= 0` 时把 `received` 也置 0，`_subtitleOf` 只显示 `0 B`。用户看到的是与当前平台不符的浏览器文案。

**落地修法**：区分「未知大小」与「已交浏览器」两种状态：`supportsPauseResume == false` / 后端能力位才显示浏览器文案；原生未知大小显示「大小未知 · 已下载 N B」（或 indeterminate 进度条），不要用浏览器兜底文案。

---

## C-11 · P2 · `TweenAnimationBuilder(begin: 0)` 让每次 build 都从 0 重新插值，进度不连续

**证据**（`lib/surface/pages/download_manager_page.dart:383-395`）：

```dart
TweenAnimationBuilder<double>(
  tween: Tween<double>(begin: 0, end: task.progress),
  duration: OgLAnim.fast(context),
  ...
  builder: ... LinearProgressIndicator(value: value.clamp(0.0, 1.0)),
)
```

列表随 200ms 节流通知重建；`begin` 固定 0 会让动画从 0 补到当前进度，尤其大文件 50% 以上时每 200ms 都看到进度条从空跑到一半。库的进度本身来自 `expectedFileSize * clamped`，不是分片 `onBytes` 的连续聚合。

**落地修法**：用 `Tween(begin: previous, end: current)` 保存上一帧，或改 `AnimatedSize`/自定义 `SingleTickerProviderStateMixin` 持有 `AnimationController`；也可直接用 `LinearProgressIndicator(value:)` 由节流事件驱动，不额外做「从 0 起」的补间。

---

## C-12 · P2 · `progress` 与 `percent` 会把超量字节静默裁剪成 100%，掩盖数据错误

**证据**（`lib/domain/ix/ix_download.dart:459-463`）：

```dart
double get progress =>
    total <= 0 ? 0 : (received / total).clamp(0, 1).toDouble();
int get percent => (progress * 100).round();
```

分片引擎 `lib/base/net/range_download_io.dart:138-146` 直接把各片 `onBytes` 累加；若 CDN / 代理返回超长 chunk 但最后一片长度校验被绕过，或库补发 `progress > 1.0`，UI 永远显示 100%，用户无法察觉异常；若事件顺序使 `received > total`，完成前也显示 100%。

**落地修法**：对 `received > total` 记诊断码并把状态标为「长度异常 / 待校验」，不要只用 `clamp`；后端 `TaskProgressUpdate` 的 `clamped` 也应同时 `min(1.0, ...)`；完整性校验失败时状态与文案要区分「长度不符」与「sha256 不符」。

---

## C-13 · P2 · 库单连接下载失败只写状态，不向通知中心投递；离开下载页不可见

**证据**：

- `lib/domain/ix/ix_download.dart:1519-1534`：failed 事件只改快照：

```dart
_snapshots[id] = snap.copyWith(
  status: status,
  error: _errorOfDescription(event.error),
);
...
return;
```

- `notifications?.push` 只在三处：分片失败 988、完整性失败 1429、完成 1444。
- `lib/domain/ix/ix_download.dart:779-792` 入队异常也只置 `failed` + `rethrow`，不 `push`。

用户四反馈里的「下载不充分 / 不健全」包含「失败要看得见」；当前只有分片路径兑现了 F-1，默认 `background_downloader` 单连接失败、入队失败、磁盘满 / 权限失败在页面外完全无声。

**落地修法**：抽出 `_markFailed(id, kind, message, code)`，统一写快照 + `notifications.push(level: danger/warning)` + 诊断；在 `_onEvent` 的 failed 分支、入队 catch、`_fallbackToSingle` catch、`_finishTask` catch 里调用。

---

## C-14 · P2 · 完整性校验失败文案无条件宣称「坏文件已删除」，与读不到文件 / 删除失败混淆

**证据**：

- `lib/domain/ix/ix_download.dart:1333-1342`：`fileSha256` 返回 null 时 `return false`，注释明确「读不到成品 ≠ 校验不匹配」；
- `lib/domain/ix/ix_download.dart:1414-1432`：所有 `!ok` 都走同一分支：

```dart
await _backend.deleteFile(id, path: snap.savePath);
...
message: '${_fileNameOf(snap)}：完整性校验未通过，坏文件已删除，可重试',
```

- `lib/domain/ix/ix_download_backend_io.dart:230-237`：`deleteFile` 吞掉删除异常，`File` 可能仍在。

用户被明确告知「坏文件已删除」，实际可能根本没读到文件（只想重试）或删除失败（坏文件仍在，下一次重试会复用它）。`verified` 三态也在「读不到」与「不匹配」之间没有状态区分。

**落地修法**：把 `_verifyIntegrity` 返回值改成枚举 `verified / mismatch / unreadable / unavailable`；`_finishTaskInner` 分别给文案与诊断码；`deleteFile` 返回 `bool`，失败时保留 `verified: false` 并禁止 SAF 导出 / 禁止把状态写成「可安全重试」。

---

## C-15 · P2 · `retry` 单连接路径没有入队异常兜底，会永久挂 queued

**证据**（`lib/domain/ix/ix_download.dart:1192-1222`）：

```dart
_snapshots[id] = snap.copyWith(status: queued, received: 0, ...);
...
await _backend.enqueue(spec);   // 无 try/catch
```

对比 `enqueue` 第 779-792 行已有「入队失败 → failed + 可见错误」的 P0 修复；`retry` 是另一条入队口，库未初始化 / 存储权限 / 磁盘满时直接抛异常给 `SurfaceBridge.retryDownload`，页面只把它当「单条重试失败继续」（`download_manager_page.dart:310-318` 的 `_retryAllFailed`），快照停留在 `queued`。

**落地修法**：把 `enqueue` catch 里的 `_markFailed` 抽成共用方法，`retry`、`_fallbackToSingle`、`resume` 的后端调用全部包住；失败时 `rethrow` 可选，但必须先落 `failed` 状态与通知。

---

## C-16 · P2 · `clearFinished` 不清 `_roundOf` / `_retrySavePaths`，辅助表仍会跨任务误消费

**证据**（`lib/domain/ix/ix_download.dart:1251-1275`）：

```dart
for (final String id in gone) {
  _rangeTokens[id]?.cancel();
  _rangeTokens.remove(id);
  _rangeConnections.remove(id);
  _pausedIds.remove(id);
  _specs.remove(id);
  _lastSample.remove(id);
  _expectedSha256.remove(id);
  _urlCandidates.remove(id);
  _exportedToSaf.remove(id);
}
```

`remove`（1229）会 `_roundOf.remove(id)`，`clearFinished` 不会；`_retrySavePaths` 两者都不清。下一次同 id 入队时 `_roundOf` 从旧值继续递增（不影响正确性但违背「逐表对齐」注释），更严重的是此前 `remove` 遗留的豁免会在 `clearFinished` 之后被任意同 id 入队误消费，与 C-02 叠加。

**落地修法**：把「清一个 id 的所有辅助表」抽成 `_forget(id, {required bool keepRetryPath})`，`remove` / `clearFinished` / `dispose` 共用；`clearFinished` 明确 `_roundOf.remove(id)` 与 `_retrySavePaths.remove(id)`；给豁免加 TTL / 来源路径校验。

---

## C-17 · P2 · Gist 下载不用 `OgLDownloadNotice`，「查看下载」动作缺席

**证据**（`lib/surface/pages/gist_detail_page.dart:309-326`）：

```dart
await widget.surface.domain.downloads.enqueue(...);
if (!context.mounted) { return; }
OgLNotifier.of(context).info(_t('downloadQueued', {'name': file.name}));
```

另外四个调用方（`repo_page.dart:319,1905`、`release_detail_page.dart:295`、`file_preview_page.dart:625`、`action_run_page.dart:435`）都走 `OgLDownloadNotice.instance.show(context, ...)`，默认带「查看下载」动作。Gist 页只用普通 info SnackBar，用户无法从通知直达下载管理页；用户反馈「通知点查看返回 null」虽然主路径修好，但 Gist 是漏网入口。

**落地修法**：Gist 成功后改调 `OgLDownloadNotice.instance.show(context, widget.surface, message: ...)`；失败也用 `DownloadNoticeKind.warning` 统一；`context.mounted` 守卫保留。

---

## C-18 · P2 · `OgLDownloadNotice` 降级路径仍依赖已 dispose 的发起页 context

**证据**：

- `lib/surface/pages/download_manager_page.dart:142-158`：rootContext 与 `OgLApp.navigatorKey.currentContext` 都为空才降级；
- `lib/surface/pages/download_manager_page.dart:159-169`：降级仍用旧 `context`：

```dart
unawaited(ogLCopyText('/download', tag: '下载管理页'));
OgLDownloadNotice.instance.show(context, surface, message: _t('viewDownloadsFallback'), ...);
```

- `show` 第一行（`lib/surface/pages/download_manager_page.dart:76-79`）就 `ScaffoldMessenger.of(context)` / `Theme.of(context)`。

8 秒 SnackBar 期间发起页被 pop 后，若根 Navigator 同时未就绪（启动早期 / 热重启 / 测试中），`ScaffoldMessenger.of(context)` 会对已失效 `Element` 抛异常，降级提示反而打不出来。主路径「rootContext → navigatorKey」是对的；这是第三级降级的残留。

**落地修法**：降级只 `ogLCopyText('/download')` + 写诊断码，或把提示投递到 `OgLNoticeHost` / 通知中心这类不依赖页面 context 的总线；若一定要 SnackBar，先判 `context.mounted`，并把根 context 从 `MaterialApp.builder` 缓存为静态可用引用。

---

# 二、推测 / 需 SDK 或真机复现

## S-01 · P1 · Web 分支契约漂移：与 main 的 `IxDownloadBackend` 已不同步

**推测依据**：main `lib/domain/ix/ix_download.dart:196` 新增抽象方法 `Future<String> resolveUniqueSavePath(...)`，但工作树 `weblite` 分支的 `lib/domain/ix/ix_download_backend_web.dart`（`git show weblite:...:43-120`）没有该方法，也没有 `supportsRanged` 之外的契约新增；`git diff --stat main..weblite -- lib/domain/ix/ix_download.dart` 显示 165 行差异。远程 `origin/webchk` / `origin/webcmp` 的 Web 后端同样只有 `supportsRanged`。

```dart
// main 契约
Future<String> resolveUniqueSavePath(IxDownloadSpec spec, {String? intendedPath});
// weblite WebDownloadBackend：没有 override
```

若 Web 分支同步 main 的 `ix_download.dart` 而不补齐实现，`WebDownloadBackend implements IxDownloadBackend` 会因缺少成员编译失败。当前没有 Flutter SDK / Web CI 运行记录，不能确证构建失败。

**落地修法**：在 Web 后端补 `resolveUniqueSavePath(spec, {intendedPath}) async => spec.url` 与 `supportsRanged`；把 `IxDownloadBackend` 契约与两个实现纳入同一份 `analyze` CI；为 Web 分支跑一次 `flutter build web --wasm`。

---

## S-02 · P2 · `background_downloader` 对同名文件的覆盖 / 冲突行为未知

**推测依据**：`lib/domain/ix/ix_download_backend_io.dart:155-168` 把 `spec.fileName` 直接交给 `DownloadTask.filename`，再 `cancelTaskWithId` + `enqueue`；本地未安装该包源码（pubspec 为 `^9.6.3`）。若库内部对已存在文件使用 `FileMode.write` 而非独占写，C-03 / C-04 / C-02 的覆盖会真实发生；若库自动顺延，页面显示的 `savePath` 又与实际落盘不一致。

**落地修法**：查阅 / 锁定 9.6.3 源码或写集成测试在真机放同名文件后 `enqueue`，断言旧文件不变；不依赖库内部行为，按 C-04 用占位的绝对路径写。

---

## S-03 · P2 · Range 引擎取消后 `.partN` 清理可能与新回合撞车

**推测依据**：`lib/base/net/range_download_io.dart:186-205` 的 `finally` 无条件遍历 `parts` 删除：

```dart
} finally {
  if (!merged) { ... target.delete(); }
  for (final File part in parts) {
    if (await part.exists()) { await part.delete(); }
  }
}
```

`_runRanged` 第 819-828 行取消旧 token 后立即把新 token 放进 `_rangeTokens[id]`，两个回合用同一个 `targetPath` 与同一组 `.partN`；旧轮 `Future.wait` 全部结束前，新轮已可能开始写同名 part。源码没有「按回合隔离的临时目录」，确有竞态窗口，但具体是否触发依赖网络回调时序。

**落地修法**：每回合用 `targetPath.<round>.partN` 或独立临时目录；`finally` 只删本回合的 parts；合并前再次检查 `cancel.isCancelled` 和 `_roundOf[id] == round`。

---

## S-04 · P2 · `expectedSha256` 只在 Release 详情页传入，其它下载类型无法校验

**推测依据**：`lib/surface/pages/release_detail_page.dart:293-294` 传 `expectedSha256: IxPresign.normalizeDigest(asset.raw['digest'])`；`repo_page.dart:309-315,1894-1900`、`file_preview_page.dart:615-625`、`action_run_page.dart:425-435`、`gist_detail_page.dart:309-315` 的 `enqueue` 都没有该参数。`lib/domain/ix/ix_download.dart:1309-1318` 无摘要时直接 `return true` 并标记未校验。这是「如实未校验」而非崩溃，但用户四反馈「下载不健全」里对加速代理替换文件的防护只覆盖 Release；其它资源经第三方通道时同样可被替换。

**落地修法**：若 API 返回 `sha256` / `digest` / `ETag` 可用，统一透传；没有摘要时在 UI 明确显示「未校验」（当前 `verified` 三态已有，但页面未在 `_subtitleOf` 呈现）；对加速通道可默认要求摘要或让用户知情接受。

---

# 三、逐项核对结论

## 1. 重名裁决

- **三者 fileName 是否一致**：v12.6.0 **否**（C-01）；当前 HEAD 首次入队**大致一致**：`_specs` 第 761 行、快照第 765 行、`finalSpec` 第 785 行、分片 `snap.savePath` 第 911 行都来自裁决后的值。
- **页面显示 `a (1).zip` 但库写 `a.zip` 的窗口**：v12.6.0 必现；当前 HEAD 仍在「remove → 再 enqueue（C-02）」「第二个 await 后被 remove（C-07）」「fallback 异步重入覆盖 savePath（C-08）」三处存在。
- **分片路径**：当前首次入队用 `_snapshots[id].savePath`，即 `finalPath`；但 `_fallbackToSingle` 第 1027 行重新 `pathFor(fallback)`，用的是 fallback spec 的原名，`savePath` 会被改回 `a.zip` 并入队（C-08），仍是覆盖窗口。
- **`_taskId` 改名后 id 不变**：第 634-639 行 id = `category.folder:safeName#url`，与 `finalName` 无关。两个不同任务撞名时 id 仍含各自 url / safeName，不会因改名撞 id；真正的问题是同 id 重试复用旧路径（C-02），以及 id 复用导致豁免集合被误消费（C-16）。
- **同 id 重试豁免消费一次**：`remove` 第 1237 行 `add`，`enqueue` 第 751 行 `remove`，单次路径上只消费一次；但 `clearFinished` / `retry` / `resume` 都不清它，`undoRemove` 也进不到 `enqueue`（C-05），所以会出现「永不消费」与「隔代误消费」。
- **探测异常不阻塞**：后端第 119/124/137/140 行返回已存在或无目录的 base，不是「不写」，而是继续写并覆盖（C-03）。

## 2. 通知跳转

- 优先级正确：`rootContext`（`download_manager_page.dart:142`）→ `OgLApp.navigatorKey.currentContext`（150）→ 复制 `/download` + 提示（159-169）；`OgLApp` 第 53/67 行确实把 key 挂到 `MaterialApp.navigatorKey`。
- 调用方 context：repo / release / file_preview / action_run 四个入口都在 `await enqueue` 后判 `mounted` 再 `show`；gist 用普通 `OgLNotifier`，没有「查看下载」动作（C-17）。`repo_page.dart:1907-1909` 的 catch 分支未判 `mounted`，但属失败提示而非通知跳转。
- dispose 后调用：主路径没有发现「未判 mounted 就 show」；第三级降级在极端时序仍用旧 context（C-18）。

## 3. 进度

- `IxDownloadEvent.progress` 只有 `received/total`、没有 `bytesPerSecond`（`ix_download.dart:140-158`）；单连接 total 来自库 `expectedFileSize`，received 由 `progress * total` 反算（`backend_io.dart:262-269`）；分片 total = `probe.total`，received = 各片 `onBytes` 累加（`range_download_io.dart:138-146`）；速度一律由 `_lastSample` 差分估算（1090-1100 / 1545-1551）。
- `_subtitleOf`（`download_manager_page.dart:553-563`）：`ghSizeText(received)/ghSizeText(total)` + `percent` + running 时 `ghSizeText(bytesPerSecond.round())/s` + `connections>1` 时 `N 线程`；`total=0` 只显示 `ghSizeText(received)`，并配「已交给浏览器」（C-10）。
- `connections>1` 时数字连续但动画不连续（C-11），暂停 / 恢复会回退并出现负速率（C-09）；`clamp` 掩盖超量（C-12）。

## 4. 多线程

- 传递链：设置档位 `settings.dart:156` 默认 4 → 各页面 `settings.settings.downloadConnections` → `enqueue(connections:)` → `ix_download.dart:772-777` → `_runRanged(connections:)` → `DownloadRequest.connections` → `OgLChunkPlan.of`（`range_download.dart:62-83`）。`setDownloadConnections` 同步 `preferredConnections`（`surface_bridge.dart:461-463`），但启动时不回填，故用户改设置前 `preferredConnections == null`，`resume` 会用 1（C-06）。
- 分片规划 / `.partN` / 合并 / `Content-Range` 校验 / 失败清理：`range_download_io.dart:119-205, 224-280`，闭区间、严格校验 206 + 区间 + 总量 + 长度，失败删 target 与所有 part，基本健全；但取消回合间 part 名冲突见 S-03。
- 不支持 Range 回退：`_runRanged` 的 `uri == null` / `DownloadUnsupported` / HTTP 200 三条都调 `_fallbackToSingle`，后者 `pathFor` + `enqueue(fallback)`；路径与回合竞态见 C-08，且 fallback 不重新做重名裁决（用原名）。
- 取消：`pause/cancel` 取消 token 并置状态；引擎 `finally` 清 target 与 parts；`_rangeTokens`/`_pausedIds` 在第 999-1000 行 finally 清除。但「旧 finally 删新 token、删新 part」的时序见 S-03 / C-08。

## 5. 健全性

- 入队异常：首次 `enqueue` 有 failed + `rethrow`（779-792），`retry` / `resume` / `fallback` 不完整（C-15 / C-13）。
- `expectedSha256`：`normalizeDigest` 只收 sha256 且 64 位 hex（`ix_presign.dart:225-239`）；`_verifyIntegrity` 三态 + 删除坏文件 + 跳过 SAF 导出，方向正确；失败文案与读不到文件混淆（C-14），覆盖率不足（S-04）。
- SAF：`_maybeExportToSaf` 判 disposed / exporter / canReadLocalFile / 去重，成功后移除 id，避免第二次永不导出；失败只留诊断，符合「不阻塞完成」。
- Web 后端不存在时的分支：main 用 `IxDownloadManager(backend: createDownloadBackend())`（`ix_download.dart:517`）+ `backend_io.dart:17` 无条件返回 `IoDownloadBackend()`，`import 'dart:io'` 直接编译进 main；Web 由独立 `web` 分支 / 本地 `weblite` 分支提供 `backend_web.dart`。这是发布流程分支而非运行时条件导入，易漂移（S-01）。main 的 `domain_bridge.dart:19,401` 还无条件 `OgLRangeDownloader()`，其 `range_download.dart:28` 无条件 `export range_download_io.dart`，Web 分支需整体替换。
- dispose 后事件回写：`_disposed` 在 `dispose()` 第 1627 行最先置位，`_safeNotify` / `_notifyThrottled` 拦截；但 `_onEvent` / `_applyRangeProgress` / `_applyStatus` / `_finishTask` 等写 `_snapshots` 前**不检查 `_disposed`**，会继续改已回收对象的内部 Map。不会因 `notifyListeners` 断言，但属于「dispose 后回写」（见下 C-19 风险说明中已并入 C-07/C-16 的守卫建议；此处不单独计数）。

## 6. 结构完整性

见开头「结构完整性（通过）」：无 UTF-8 替换符、无截断、括号配对、无重复成员 / 半成品残留、字段均有使用。逻辑自洽问题按 C-02 ~ C-09 处理。

---

# 四、修法优先级与建议

1. **立即（数据无价）**：C-02、C-03、C-04、C-08；把「裁决 → 占位 → 写盘 → 校验」做成一条原子链，所有 await 后带回合校验。
2. **立即（功能可用性）**：C-05、C-06、C-07、C-15；给 `retry/remove/clearFinished` 抽统一状态机与 `_markFailed`。
3. **本补丁内**：C-09、C-10、C-11、C-12、C-13、C-14、C-16、C-17、C-18；补真机 / widget 行为测试，不再用 `contains('finalPath')` 这类源码断言代替。
4. **验证**：S-01 ~ S-04 需 Flutter SDK + Web CI + 真机文件系统；特别跑 `flutter build web --wasm` 与「同名文件 + 重试 + 暂停恢复」矩阵。

---

# 五、证据校订（行号基准与补充片段）

- 行号以审查结束时工作树 HEAD `b2ff56f` 为准；C-01 明确引用的是发布提交 `5c84d6f` 的旧行号。`70dda36` 在 `enqueue` 附近新增 7 行，故 12.6.0 与 12.6.1 的 `ix_download.dart` 行号存在 ≤7 行偏移；每条发现的代码片段本身为定位依据。
- 上节「见下 C-19」为笔误：应为「见 C-07 的 await 后守卫建议与 C-16 的统一 `_forget(id)` 建议」。dispose 后事件回写不单独计数。
- S-02 补充证据片段（`lib/domain/ix/ix_download_backend_io.dart:155-168`）：

```dart
Future<void> enqueue(IxDownloadSpec spec) async {
  final DownloadTask task = await _build(spec);
  try { await _downloader.cancelTaskWithId(task.taskId); } catch (_) {}
  _tasks[spec.id] = task;
  _idsByLibraryId[task.taskId] = spec.id;
  await _downloader.enqueue(task);
}
```

- S-04 补充证据片段（`lib/surface/pages/release_detail_page.dart:293-294` 与 `lib/surface/pages/repo_page.dart:1894-1900` 对比）：

```dart
// Release：唯一传摘要的调用点
expectedSha256: IxPresign.normalizeDigest(asset.raw['digest']),
...
// 仓库文件：enqueue 无 expectedSha256 参数
await widget.surface.domain.downloads.enqueue(
  url: plan.urls.first,
  fallbackUrls: plan.urls.skip(1).toList(),
  headers: plan.headers,
  fileName: ghPathName(entry.path),
  category: IxDownloadCategory.repo,
  connections: widget.surface.settings.settings.downloadConnections,
);
```

---

# 六、总体结论

## 用户四反馈是否真修好

**没有真修好。**

1. **下载不充分 / 不健全**：部分修好（入队异常兜底、sha256、SAF、失败通知分片路径），但 `retry` 入队异常会挂 queued（C-15）、库失败离页不可见（C-13）、完整性失败文案误导（C-14）、Web 分支契约漂移（S-01）。
2. **进度模糊**：未修好。`total=0` 在原生端谎称「交给浏览器」（C-10），动画每 200ms 从 0 重跑（C-11），暂停 / 恢复出现负速率与进度回退（C-09），超量字节被裁剪成 100%（C-12）。
3. **成熟库 + 多线程**：方向正确（库单连接 + 自研 Range 分片、严格 `Content-Range`、失败全清），但引入回归：`resume` 抢跑分片 / 重新入队（C-06）、`_fallbackToSingle` 异步重入（C-08）、取消回合间 part 名冲突（S-03）。
4. **重名文件处理**：只修了一半。v12.6.0 是确证 P0 覆盖（C-01）；12.6.1 补了首次入队的 `finalPath/finalSpec`，但「移除 → 再下载」仍会写回原路径（C-02），探测异常仍 fail-open（C-03），并发裁决仍 TOCTOU（C-04）。
5. **通知点查看返回 null**：主路径基本修好（rootContext → `OgLApp.navigatorKey` → 复制 `/download` 降级），四个调用方都判 `mounted`；但 Gist 漏用统一通知（C-17），第三级降级仍依赖已 dispose 的页 context（C-18）。

## 最大剩余风险是什么

**数据无价类覆盖：`_retrySavePaths` 只记 id、不记上一轮裁决后的 `a (1).zip` 路径（C-02）。** 用户已有 `a.zip` → 新下载被改名 → 移除列表 → 再下载同一附件，会绕过裁决写回 `a.zip`，覆盖用户原有文件；C-03 的探测异常 fail-open、C-04 的并发 TOCTOU、C-08 的 fallback 重入会把同一风险放大。其次是 C-06 让「暂停 / 继续」变成取消并从 0 重下，属于用户可感知的功能回归。

## 是否建议立即出 12.6.1

**是，从 v12.6.0 的角度应立即出补丁；但审查期间工作树已经推进到 `b2ff56f release: v12.6.1 LTS 补丁`，这个 12.6.1 只修了 C-01，不足以宣布 LTS 下载链路稳定。** 建议立即再发 12.6.1.1 / 12.6.2（至少包含 C-02 ~ C-09），并在发版前补齐真机行为测试与 Web 分支编译；在修复上线前，建议对下载功能加临时保护：默认把 `downloadConnections` 降到 1，并在发现目标文件已存在时直接置 `failed` 而不是继续写。

---

## 发现计数汇总

| 类别 | P0 | P1 | P2 | 合计 |
|---|---:|---:|---:|---:|
| 确证 | 2（C-01、C-02） | 7（C-03~C-09） | 9（C-10~C-18） | **18** |
| 推测 | 0 | 1（S-01） | 3（S-02~S-04） | **4** |
| 合计 | **2** | **8** | **12** | **22** |

报告结束。审查过程未修改任何源码 / 文档，未执行 git 写操作；唯一写入为 `/root/OhGithubLost/docs/postrelease_download_audit.md`。
