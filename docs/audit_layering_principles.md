# 专项审计：层级桥接与模块独立原则（只读静态核验）

- 仓库：`/root/OhGithubLost`，HEAD `64cf405`
- 审计日期：2026-11-13
- 性质：**只读静态检查**。本次未修改任何源文件、未执行任何 git 写操作；本文件是唯一新增产物（报告本身）。
- 判定口径：AGENTS.md §1「四层 L0 kernel → L1 base → L2 domain → L3 surface 单向依赖；每层一座层桥（`*bridge.dart` 注册进 `KernelBridgeRegistry`）；上层只许 `XxxBridge.of(bridges)` resolve；禁止直接 import 下层内部文件」，合法例外 3 文件，KNOWN 白名单 2 项。

---

## 0. 先修正任务前提中的一处事实偏差（重要）

任务描述说「kernel/base/domain/surface 的四座层桥」。**实际上只有三座层桥**，L0 kernel 自身没有桥：

- `lib/main.dart:216-225`
```dart
    //   漏注册在启动期就抛 KernelBridgeError，不再拖到运行期 resolve。
    final report = await kernel.boot(
      modules,
      expectedBridges: <String>{
        ModuleLayer.base.key,
        ModuleLayer.domain.key,
        ModuleLayer.surface.key,
      },
    );
```
- `lib/main.dart:220` 注释明写：「★ 批 9 交叉 X-04：真实装配必须到齐 L1/L2/L3 三座层桥。**L0 内核自身没有桥（它是被依赖方）**。」

因此本报告按「**三座层桥 + 内核桥注册表**」核验；`KernelBridgeRegistry`（`lib/kernel/bridge_registry.dart`）是内核提供的基础设施，不是第四座桥。

---

## 1. 四座（实为三座）层桥的完整性

### 1.1 桥的实现与注册 — **成立**

| 层 | 桥文件 | 注册点 | 注册的层级键 |
|---|---|---|---|
| L1 base | `lib/base/base_bridge.dart:15` `class BaseBridge` | `lib/base/base_bridge.dart:54` `context.bridges.register(ModuleLayer.base.key, bridge);` | `base` |
| L2 domain | `lib/domain/domain_bridge.dart:40` `class DomainBridge` | `lib/domain/domain_bridge.dart:502` `context.bridges.register(ModuleLayer.domain.key, bridge);` | `domain` |
| L3 surface | `lib/surface/surface_bridge.dart:40` `class SurfaceBridge` | `lib/surface/surface_bridge.dart:661` `context.bridges.register(ModuleLayer.surface.key, bridge);` | `surface` |

内核侧封存时强校验层桥到齐：
- `lib/kernel/bridge_registry.dart:70-78`
```dart
  void seal({Set<String> expected = const <String>{}}) {
    if (expected.isNotEmpty) {
      final Set<String> missing = expected.difference(_bridges.keys.toSet());
      if (missing.isNotEmpty) {
        throw KernelBridgeError('层级桥未注册齐全，封存被拒绝：缺 ${missing.join('、')}');
      }
    }
```
- 每层键只允许注册一次：`lib/kernel/bridge_registry.dart:36-39`（重复注册抛 `KernelBridgeError`）。

**结论：成立**（三座桥全部实现、全部注册、键唯一、启动期强制到齐）。

### 1.2 文件头层级前缀 — **成立**

`tool/contract_audit.py` 强制四层文件头前缀（`check_headers`，第 96-113 行），实测当前基线 0 违规：

```
export/import 结构与指向：0 处
文件头层级前缀：0 处
平台门面：0 处
文档契约引用：0 处
装配顺序（L0→L3）：0 处
合计：0 处
```
抽查：`lib/base/base_bridge.dart:1` `/// L1 底座级 · 层桥：…`、`lib/domain/domain_bridge.dart:1` `/// L2 中枢级 · 层桥与模块装配。`、`lib/surface/surface_bridge.dart:1` `/// L3 展示级 · 表面桥（Surface Bridge）与装配根。`

### 1.3 surface 桥是否经 `KernelBridgeRegistry.of(bridges)` 取得 — **部分成立（有缺口）**

- 三个 `of()` 工厂齐全：`lib/base/base_bridge.dart:26`、`lib/domain/domain_bridge.dart:101`、`lib/surface/surface_bridge.dart:53`。
- 但 **`SurfaceBridge.of(bridges)` 是死代码**：全仓 `lib/` + `test/` 检索 `SurfaceBridge.of` 只命中定义处 `lib/surface/surface_bridge.dart:53`，无任何调用点。surface 桥的实际取用路径是「组合根拿模块字段」：
  - `lib/main.dart:299` `runApp(OgLApp(surface: surfaceModule.bridge, report: report));`
  - `lib/main.dart:285` `final IxNotificationCenter notifications = surfaceModule.bridge.domain.notifications;`
- 上层取用面：`lib/surface/app/og_l_app.dart:40-43`（`final SurfaceBridge surface;`）→ `lib/surface/app/client_shell.dart:63` → 逐层传给页面（`client_shell.dart:230-275`）。

**结论：有缺口（轻微）**。「只许 `XxxBridge.of(bridges)` resolve」在 L3 事实上没有落地：`of()` 未被使用，桥经 widget 构造函数层层下传。`KernelBridgeRegistry` 对 surface 而言只承担「注册 + 封存校验」两个职责。

### 1.4 有没有绕过桥直接 new 下层实现 — **成立（0 例）**

全仓检索下层实现类的构造点，排除 `lib/base/` 自身后**无任何命中**：

```
$ rg -n "RepositoryCache\(|NetBridge\(|InMemoryKv\(|InMemoryVault\(|InMemoryFileStore\(|WriteJournal\(|DraftStore\(" lib | grep -v '^lib/base/'
（仅 lib/surface/surface_bridge.dart:179/206 的 `clearRepositoryCache()` 方法名，非构造）
```

跨层 import 全量枚举（唯一合法例外之外只有 KNOWN 2 项）：

```
$ rg -n "import '\.\./\.\./base" lib/domain
lib/domain/gh/gh_client.dart:17:import '../../base/net/net_bridge.dart';
lib/domain/gh/gh_api.dart:17:import '../../base/disk/disk_cache.dart';

$ rg -n "import '\.\./(base|domain)" lib/surface
lib/surface/surface_bridge.dart:18..25   ← 合法例外（装配根）
```

底层能力一律经 `BaseBridge.of(context.bridges)` 取得：
- `lib/domain/domain_bridge.dart:144`（GhModule）、`:326`（SysModule）、`:386`（IxModule）、`lib/surface/surface_bridge.dart:630`（SurfaceLayerModule）。

**结论：成立。**

---

## 2. KNOWN 2 项的收敛方案

### 2.1 现状（精确调用点）

**KNOWN #1 — `lib/domain/gh/gh_api.dart` → `base/disk/disk_cache.dart`**

| 位置 | 代码 | 用途 |
|---|---|---|
| `gh_api.dart:17` | `import '../../base/disk/disk_cache.dart';` | 依赖 `RepositoryCache` + `CacheRemote` 两个类型 |
| `gh_api.dart:30` | `class GhApi implements CacheRemote {` | **实现底座定义的接口**（`CacheRemote` 定义在 `lib/base/disk/disk_cache.dart:40`） |
| `gh_api.dart:54` | `RepositoryCache? _cache;` | 字段 |
| `gh_api.dart:73` | `void attachReadCache(RepositoryCache cache, {required Future<String> Function() accountId,})` | 装配期绑定 |
| `gh_api.dart:63` | `Listenable get draftsChanged => _cache?.drafts ?? _neverNotifier;` | 取底座 `DraftStore`（`ChangeNotifier`）当通知源 |
| `gh_api.dart:383` | `final DraftSnapshot? snapshot = await cache.loadDraftSnapshot(key);` | 读草稿快照 |
| `gh_api.dart:931` | `final WriteOutcome outcome = await cache.write(...)` | D1–D7 写 |
| `gh_api.dart:1025` | `final WriteOutcome outcome = await cache.delete(...)` | D1/D2/D7 删 |
| `gh_api.dart:2190+` | `CacheRemote` 实现段（`read`/`write`/`delete`） | 底座反过来调 domain |

**KNOWN #2 — `lib/domain/gh/gh_client.dart` → `base/net/net_bridge.dart`**

| 位置 | 代码 | 用途 |
|---|---|---|
| `gh_client.dart:17` | `import '../../base/net/net_bridge.dart';` | 依赖 `NetBridge` 类型 |
| `gh_client.dart:433` | `required NetBridge net,` | 构造参数 |
| `gh_client.dart:446` | `final NetBridge _net;` | 字段 |
| `gh_client.dart:619` | `final netResponse = await _net.send(NetRequest(...));` | **全文件仅此一处**调用 |

关键事实：`NetRequest` / `NetResponse` **本来就在 L0**（`lib/kernel/contract/net_types.dart:116` `class NetRequest`、`:166` `class NetResponse`），`lib/base/net/net_types.dart:7` 只是转发导出（`export '../../kernel/contract/net_types.dart';`）。也就是说 **KNOWN #2 只差一个接口声明**。

### 2.2 仓库里已有的正确范式（应当照抄）

本仓已经用「L0 契约 + L1 实现 + 装配根注入」解决过同类问题两次，方案完全可复用：

- `lib/kernel/contract/download_engine.dart:92` `abstract class DownloadEngine` → `lib/domain/ix/ix_download.dart:529` `final DownloadEngine? _engine;`（domain 只认契约，实现在 base 注入于 `lib/domain/domain_bridge.dart:406`）。
- `lib/kernel/contract/storage_export.dart:16` `abstract class StorageExporter` → `lib/domain/ix/ix_download.dart:526` `final StorageExporter? _exporter;`（注入于 `lib/domain/domain_bridge.dart:408`）。

### 2.3 具体方案

#### 方案 A（推荐）：`NetClient` —— 一步到位，风险最低

**第 1 步 · 新增 L0 契约**
新增 `lib/kernel/contract/net_client.dart`：
```dart
/// L0 内核级 · 网络客户端契约（跨层只认这个接口）。
library;
import 'net_types.dart';

/// 跨层网络访问契约：上层只依赖它，不认识重试 / 镜像 / DNS 实现。
abstract class NetClient {
  /// 发送一次请求。
  Future<NetResponse> send(NetRequest request);
}
```

**第 2 步 · base 侧实现**
`lib/base/net/net_bridge.dart:18` 改为
```dart
class NetBridge implements NetClient {
```
`NetBridge.send`（`net_bridge.dart:98`）签名 `Future<NetResponse> send(NetRequest request) => transport.send(request);` 与契约**逐字匹配**，无需新增方法。
（可选更保守：`class _BridgeNetClient implements NetClient` 适配器，由 `BaseBridge` 暴露 `NetClient get client`；但 `implements` 更省代码且不破坏任何调用点。）

**第 3 步 · domain 侧改为依赖抽象**
- `lib/domain/gh/gh_client.dart:433` → `required NetClient net,`
- `lib/domain/gh/gh_client.dart:446` → `final NetClient _net;`
- 删除 `lib/domain/gh/gh_client.dart:17` 的 base import。

**第 4 步 · 装配根注入**
`lib/domain/domain_bridge.dart:151-157` 的 `GhClient(net: base.net, …)` **不用改**（`NetBridge` 是 `NetClient` 的子类型，赋值兼容）——**API 不破坏**。

**第 5 步 · 撤白名单**
`tool/layer_audit.py:71-74` 的 `KNOWN` 字典删除 `'domain/gh/gh_client.dart': {'base/net/net_bridge.dart'}` 一项。

- 风险：**极低**。仅 1 个调用点（`:619`）、1 个构造点（`domain_bridge.dart:151`）。
- 需改文件清单：`lib/kernel/contract/net_client.dart`（新增）、`lib/base/net/net_bridge.dart`（1 行）、`lib/domain/gh/gh_client.dart`（3 行）、`tool/layer_audit.py`（2 行）。
- 验证：`python3 tool/layer_audit.py --fatal`（KNOWN 计数应从 2 降到 1，违规仍 0）；`dart analyze lib/kernel lib/base lib/domain`；`test/domain/` 全量（`gh_submit_e2e_test.dart` 必跑）。

#### 方案 B：`ConsistencyCache` —— 需拆成 3 小步

KNOWN #1 比 #2 复杂，因为 `gh_api.dart` 同时**依赖底座定义的接口 `CacheRemote`**（`lib/base/disk/disk_cache.dart:40`）和**底座实现 `RepositoryCache`**。两者必须分别处理。

**第 1 步（必做，解耦接口）· 把 `CacheRemote` 上提到 L0**
- 在 `lib/kernel/contract/disk_types.dart` 新增 `CacheRemote`（照搬 `disk_cache.dart:40-64` 的三个方法签名，类型 `RemoteDocument` / `CacheKey` / `RemoteConflictException` **本来就都在这个文件里**：`disk_types.dart:162` `RemoteDocument`、`:82` `CacheKey`、`:177` `RemoteConflictException`）。
- `lib/base/disk/disk_cache.dart` 改为 `export '../../kernel/contract/disk_types.dart' show CacheRemote;` + `import`（或保留类定义但改为转发导出），`UnavailableCacheRemote`（`:67`）可留在 base。
- `lib/domain/gh/gh_api.dart:30` 的 `implements CacheRemote` 改为引用 L0 版本；**`gh_api.dart:17` 的 import 改成 `import '../../kernel/contract/disk_types.dart';`**（kernel 契约，合法）。
- 装配根 `lib/domain/domain_bridge.dart:162` `base.disk.cache.bindRemote(api);` **不用改**（`bindRemote` 形参类型改为 L0 的 `CacheRemote`，`GhApi` 满足）。
- 风险：**低**。唯一行为变化是「接口类型的归属层」，无运行时语义变化。注意 `disk_cache.dart` 里 `bindRemote(CacheRemote remote)`（`:223`）与 `remote` getter（`:228`）签名需同步改类型名（同一文件内 `export` 的名字可直接用）。
- 验证：`dart analyze lib/kernel lib/base lib/domain`；`test/base/cache_consistency_test.dart`、`test/domain/gh_submit_e2e_test.dart`。

**第 2 步（新增抽象）· 定义 `ConsistencyCache` 契约**
新增 `lib/kernel/contract/consistency_cache.dart`：
```dart
/// L0 内核级 · 一致性缓存契约（D1–D9 引擎的对外形态）。
library;
import 'package:flutter/foundation.dart' show Listenable;   // 已有先例：kernel/contract/download_engine.dart:16
import 'disk_types.dart';

abstract class ConsistencyCache {
  Future<CacheEntry?> read(CacheKey key, {bool refresh = false, Duration? maxAge});
  Future<WriteOutcome> write(WriteIntent intent, {bool confirmed = false});
  Future<void> invalidate(CacheKey key);
  Future<WriteOutcome> delete(CacheKey key, {required String message, required String baseSha, bool confirmed = false});
  Future<DraftSnapshot?> loadDraftSnapshot(CacheKey key);
  Future<int> purge();
  Listenable get draftsChanged;   // 草稿变更通知源（替代 base 的 DraftStore 类型）
}
```
- 签名**逐字取自** `lib/base/disk/disk_cache.dart`：`:237 read`、`:257 write`、`:290 invalidate`、`:300 delete`、`:204 loadDraftSnapshot`、`:487 purge`；`draftsChanged` 对应 `:213 DraftStore? get drafts`（`DraftStore extends ChangeNotifier`，`lib/base/disk/disk_draft.dart:100`）。
- `kernel/contract/` 已允许依赖 `package:flutter/foundation.dart`（`download_engine.dart:16`），故 `Listenable` 不破坏「kernel 不依赖 Flutter SDK」的门禁事实（`dart analyze lib/kernel` 不需要 Flutter SDK 的是**无 Flutter import** 的部分；此处已有先例，风险需实测——若 `dart analyze lib/kernel` 在无 Flutter 环境失败，则改用 `void Function(void) addDraftsListener(...)` 回调式契约，见 §8 风险项）。
- `lib/base/disk/disk_cache.dart:140` `class RepositoryCache implements ConsistencyCache`（方法已齐全，仅 `draftsChanged` 需加一个 getter 转发 `_drafts`）。
- `lib/base/disk/disk_bridge.dart:40` `final RepositoryCache cache;` → 建议**同时**保留类型化 getter 并新增 `final ConsistencyCache cacheContract;`，或直接把 `cache` 类型改为 `ConsistencyCache`（后者会让 `surface_bridge.dart:179` 的 `cache?.purge()` 需要契约里有 `purge()`——已含）。

**第 3 步（domain 改依赖抽象）**
- `lib/domain/gh/gh_api.dart:54` → `ConsistencyCache? _cache;`
- `lib/domain/gh/gh_api.dart:73` → `void attachReadCache(ConsistencyCache cache, {required Future<String> Function() accountId})`
- `lib/domain/gh/gh_api.dart:63` → `Listenable get draftsChanged => _cache?.draftsChanged ?? _neverNotifier;`
- 删除 `lib/domain/gh/gh_api.dart:17` 的 base import。
- **装配根不用改**：`lib/domain/domain_bridge.dart:168-171` `api.attachReadCache(base.disk.cache, accountId: …)`（`RepositoryCache` 是 `ConsistencyCache` 子类型，兼容）；`:162` `base.disk.cache.bindRemote(api)` 兼容。
- **API 不破坏**：唯一「破坏性」点是 `GhApi.attachReadCache` 的形参类型变宽（基类 → 接口），对现有调用点（仅 `domain_bridge.dart:168`）与测试（若测试用 `RepositoryCache` 传入，依然满足接口）均兼容。

**第 4 步 · 撤白名单**
`tool/layer_audit.py:72` 删除 `'domain/gh/gh_api.dart': {'base/disk/disk_cache.dart'}`。

- 风险：**中**（比 #2 高，因为牵涉 D1–D9 语义链与 `draftsChanged` 通知源）。必须逐小步落地、每步独立跑测试。
- 需改文件清单：`lib/kernel/contract/disk_types.dart`、`lib/kernel/contract/consistency_cache.dart`（新增）、`lib/base/disk/disk_cache.dart`、`lib/base/disk/disk_bridge.dart`、`lib/domain/gh/gh_api.dart`、`lib/domain/domain_bridge.dart`（仅类型名）、`tool/layer_audit.py`。
- 验证：`test/base/cache_consistency_test.dart`、`test/base/durability_test.dart`、`test/domain/gh_submit_e2e_test.dart`、`test/kernel/chaos_test.dart`、`dart analyze lib/kernel lib/base lib/domain`。
- **强烈建议**：方案 A 与方案 B 分两个独立 PR/批次，先 A 后 B（AGENTS 明确「属独立批次，避免与结构改动混在一起」）。

---

## 3. 模块独立性

### 3.1 模块是否只暴露 descriptor + 生命周期钩子 — **有缺口（轻微）**

`lib/kernel/contract/module.dart:151-168` 契约本身只有 `descriptor` + `onRegister`/`onStart`/`onStop`。但实现类普遍把服务实例暴露为公开字段：

- `lib/base/net/net_bridge.dart:115` `late final NetBridge bridge;`
- `lib/base/disk/disk_bridge.dart:100` `late final DiskBridge bridge;`
- `lib/domain/domain_bridge.dart:128-130` `late final GhAuthService auth; late final GhClient client; late final GhApi api;`
- `lib/domain/domain_bridge.dart:377-382` `late final IxSession session; late final IxTaskRunner tasks; late final IxNotificationCenter notifications; late final IxDownloadManager downloads; late final IxActionLogs actionLogs; late final IxPresign presign;`
- `lib/surface/surface_bridge.dart:613-616` `late final SurfaceBridge bridge; late final OgLSettingsController settings;`

现状用法上，跨模块取用走的是 DI（`lib/domain/domain_bridge.dart:387` `context.di.resolve<GhAuthService>()`），字段主要给组合根用（`lib/main.dart:285` `surfaceModule.bridge.domain.notifications`）。**判定：形式上偏离契约，实质风险低**，但「模块只暴露 descriptor + 钩子」这条并未被强制。

### 3.2 是否通过能力（provides/requires）而非具体类型耦合 — **不成立（有能力声明，无能力消费）**

- `requires` 声明的是**模块 ID**而非能力：`lib/domain/domain_bridge.dart:371` `requires: <String>['domain.gh', 'domain.sys']`、`lib/base/base_bridge.dart:43` `requires: <String>['base.net', 'base.disk']`。
- `provides` 声明能力串（`'gh.auth'`、`'gh.client'`、`'gh.api'`…，`lib/domain/domain_bridge.dart:138`），但**没有任何代码按能力串解析服务**：DI 按 `Type` 解析（`lib/kernel/di.dart:78` `T resolve<T extends Object>({String? tag})`），能力串只被 `ModuleBus` 用于「唯一性校验」（`lib/kernel/module_bus.dart:86,95`）。
- 实际耦合：`lib/domain/domain_bridge.dart:387` `final auth = context.di.resolve<GhAuthService>();` —— IxModule 依赖的是 **`GhAuthService` 具体类型**，而不是它自己声明依赖的 `'gh.auth'` 能力。若 GhModule 换掉认证实现，IxModule 立刻编译失败。
- `lib/kernel/module_bus.dart:118,151` 只按 `requires` 的模块 ID 做拓扑排序，不校验「被依赖模块是否真的提供了所需能力」。

**结论：不成立。** 能力体系目前是**装饰性的**：声明了 `provides`，消费侧（DI）完全按类型走。

### 3.3 模块是否私自持有别层的对象 — **部分成立（1 处值得记）**

- 域内跨模块持有：GhModule 把 `GhAuthService` 注册进 DI（`:270`），IxModule 再取用（`:387`）——同层，可接受（但见 3.2）。
- **跨层持有实例**：IxModule 构造的下载管理器持有 base 的实现实例：
  - `lib/domain/domain_bridge.dart:406` `engine: OgLRangeDownloader()`（base 实现，契约 `DownloadEngine` 在 L0）
  - `lib/domain/domain_bridge.dart:408` `storageExporter: const _OgLStorageExporter()`（base 实现，契约 `StorageExporter` 在 L0）
  这两处是**装配根**（合法例外文件）做的注入，domain 侧字段类型是 L0 契约（`lib/domain/ix/ix_download.dart:526,529`），因此 **方向正确、纪律成立**——这是本仓的正确范式。
- **一例需要留意**：`lib/domain/domain_bridge.dart:212-248` 的 `Timer.periodic` 闭包长期持有 `base.disk.cache`（L1 实现实例），跨越模块生命周期，且是 domain 层模块内**自己创建的定时器**持有 L1 实体。若要严格「模块不得持有别层对象」，这里应改为经契约 + 由 base 提供调度；风险低但值得在收敛方案里记一笔。

### 3.4 模块跨层直接引用别的模块的实现类 — **成立（0 例）**

无任何模块引用其他模块的实现类；`lib/domain/domain_bridge.dart:387` 是唯一跨模块取用，且经 DI。

---

## 4. DI 容器的边界

### 4.1 注册是否按层隔离 — **不成立（全局单容器，无层命名空间）**

- 容器是全局单例 `KernelDi`（`lib/kernel/di.dart:41`），键为 `(Type, tag)`（`:22-38`），**没有层级命名空间**。
- base 直接把 L1 实现注册进全局 DI：
  - `lib/base/disk/disk_bridge.dart:143-146` `context.di.register<DiskBridge>(bridge); context.di.register<RepositoryCache>(repositoryCache); context.di.register<WriteJournal>(writeJournal); context.di.register<DraftStore>(draftStore);`
  - `lib/base/net/net_bridge.dart:190-191` `context.di.register<NetBridge>(bridge); context.di.register<DnsService>(_dns);`
- domain 注册 L2 实现：`lib/domain/domain_bridge.dart:270-272`、`:343-344`、`:428-433`。
- 后果：任何层只要拿到 `Type`，就能从全局 DI 解析**任意层**的实现，绕过「只许经层桥」。目前之所以没出事，**完全依赖 `layer_audit.py` 挡住 import**（要解析 `RepositoryCache` 就得 import `base/disk/disk_cache.dart` → 被判违规）。**门禁与纪律是「一体两面」的耦合**：门禁一旦放宽，纪律立刻失守。

### 4.2 L3 拿 L2 服务是否只能经 DomainBridge — **形式成立，实质有缺口**

- 形式：`SurfaceBridge.domain` 的类型就是 `DomainBridge`（`lib/surface/surface_bridge.dart:60` `final DomainBridge domain;`），页面取用一律 `widget.surface.domain.api` / `.auth`（如 `lib/surface/pages/issue_page.dart:110`、`lib/surface/pages/search_page.dart:404`）。
- **缺口 1（类型粒度）**：经 DomainBridge 拿到的是 **domain 的实现类**（`GhApi` / `GhAuthService` / `IxDownloadManager` / `IxSession` / `IxActionLogs`），而不是「DTO + 能力接口」。`lib/domain/domain_bridge.dart:65-95` 把这些实现类作为公开字段暴露。
- **缺口 2（更严重）**：surface 装配根把 **L1 实现类**也暴露给了 L3：
  - `lib/surface/surface_bridge.dart:63` `final NetBridge? net;` ← base 实现
  - `lib/surface/surface_bridge.dart:66` `final RepositoryCache? cache;` ← base 实现
  - `lib/surface/surface_bridge.dart:84` `final DiskKv? uiPrefs;` ← base 契约实现
  - `lib/surface/surface_bridge.dart:467` `RepoFileService get repoFiles => domain.repoFiles;` ← **domain 实现类**（而 `lib/surface/types.dart:34` 恰恰 `hide RepoFileService`！门面藏的东西，桥又公开了，自相矛盾）
  - `lib/surface/surface_bridge.dart:64-66` 的注释自陈「仅供设置页应用 DNS 用」「仅供账号切换时清空」——**说明作者自己认为这是越界的临时通道**。
  - 现状**未被页面使用**（`rg "\.net\b|\.cache\b" lib/surface --glob '!surface_bridge.dart'` 无命中），属于**休眠的越界面**。
- **缺口 3**：`lib/surface/surface_bridge.dart:22` `import '../domain/gh/repo_file_service.dart';` 直接 import domain 内部文件（非 `domain_bridge.dart`），依赖合法但**进一步说明 L3 的可见面没有收口**。

**结论：L3 → L2 的路径形式上「只经 DomainBridge」成立；但 SurfaceBridge 同时把 L1 实现与 L1/Domain 实现类直接暴露给 L3，属实质缺口。**

---

## 5. 门面纪律

### 5.1 `surface/types.dart` 是否只导出 DTO/枚举/异常 — **有缺口（1 处导出服务类）**

逐条核对 `lib/surface/types.dart`：

| 行 | 导出 | 判定 |
|---|---|---|
| 18 | `export '../domain/gh/gh_auth.dart' hide GhAuthService;` | ✅ DTO/枚举（`GhAccount` 等） |
| 21 | `export '../domain/gh/gh_client.dart' hide GhClient;` | ✅ 异常/响应 |
| 22 | `export '../domain/gh/gh_draft.dart' show GhDraft, GhDraftRecord;` | ✅ DTO |
| 23 | `export '../domain/gh/gh_models.dart';` | ✅ DTO（`GhRepo`/`GhContent`…） |
| 24-31 | `export '../domain/gh/gh_oauth.dart' show GhOAuthDeviceFlow, GhOAuthCode, GhOAuthStatus, kOgLGitHubClientId;` | ✅ DTO + 常量（`kOgLGitHubClientId` 是编译期常量，有注释说明理由） |
| 34 | `export '../domain/gh/repo_file_service.dart' hide RepoFileService;` | ✅ 结果 DTO（但见 5.2：桥又把 `RepoFileService` 公开了） |
| 37 | `export '../domain/ix/ix_download.dart' hide IxDownloadManager;` | ✅ 任务 DTO |
| 40 | `export '../domain/ix/ix_notify.dart' hide IxNotificationCenter;` | ✅ |
| **43** | **`export '../domain/ix/ix_presign.dart' show IxPresign;`** | ❌ **导出的是服务类** |
| 46 | `export '../domain/ix/ix_session.dart' hide IxSession;` | ✅ |
| 47 | `export '../domain/ix/ix_task.dart' hide IxTaskRunner;` | ✅ |
| 51 | `export '../kernel/contract/disk_types.dart' show RemoteConflictException;` | ✅ 异常 |

第 43 行的具体问题：`IxPresign` 是**服务类**，有公开构造器与实例方法：
- `lib/domain/ix/ix_presign.dart:72` `IxPresign({required this.tokenProvider});`
- `lib/domain/ix/ix_presign.dart:77` `/// 把 [url] 解析成可直接下载的地址。`（`resolve`）

即：L3 拿到 `types.dart` 后**可以自己 `IxPresign(tokenProvider: …)` 造一个服务**，绕过 `SurfaceBridge.resolveDownloadUrl`（`lib/surface/surface_bridge.dart:315`）。页面当前只用到它的静态工具方法 `IxPresign.normalizeDigest`（`lib/surface/pages/release_detail_page.dart:292`），说明**真正需要的只是那个纯函数**，而非服务类。

**修法（零风险）**：把 `normalizeDigest` 抽成 `lib/domain/ix/ix_presign.dart` 顶层的顶层函数或独立 DTO 工具（如 `ix_presign_tools.dart` 的 `normalizeIxDigest`），`types.dart` 改为 `show IxPresignResult, normalizeIxDigest`，彻底不再导出 `IxPresign`。
（与本文件头 `lib/surface/types.dart:11-12` 自陈的「**隐藏**：一切服务与实现（`GhClient` / `GhAuthService` / `IxDownloadManager` …）」直接矛盾。）

### 5.2 `domain_bridge.dart` / `surface_bridge.dart` 作为装配根是否泄露了不该暴露的类型 — **有缺口**

- `lib/domain/domain_bridge.dart`：暴露的是 domain 自有实现（`GhApi`/`GhAuthService`/`IxSession`/…）+ `DomainBridge` 本身。**未暴露任何 base 实现类型**（`NetBridge`/`RepositoryCache` 只在方法体内局部使用，如 `:329` `_BridgeNetworkSource(base.net)`、`:398` `buildChannelApplier(base.net)`）。→ **domain 桥：成立**。
  - 一处次要泄露：`lib/domain/domain_bridge.dart:533` `IxChannelApplier buildChannelApplier(NetBridge net)` —— 这是**公开顶层函数**，签名里带 base 实现类型 `NetBridge`。虽在合法例外文件内，但它是可以被外部 import 调用的公开 API。建议改签名吃 L0 契约（`NetClient`/新增 `MirrorController` 契约），或降为私有 `_buildChannelApplier`。
- `lib/surface/surface_bridge.dart`：如 §4.2，暴露了 `NetBridge`（:63）、`RepositoryCache`（:66）、`DiskKv`（:84）、`RepoFileService`（:467）——**均为下层实现/实现类**。→ **surface 桥：不成立**。
  - `RepoFileService` 尤其刺眼：`lib/surface/types.dart:34` 明确 `hide RepoFileService`，而 `lib/surface/surface_bridge.dart:25,467` 又把它整类公开。页面（`lib/surface/pages/repo_page.dart:1547,1625,1726,1827`）确实在用 `widget.surface.repoFiles.create/delete/rename` → **门面纪律被桥从后门破掉**。
  - 建议：`SurfaceBridge` 改为暴露**能力方法**（`createRepoFile/deleteRepoFile/renameRepoFile`）或仅暴露 DTO 级 facade；`net`/`cache`/`uiPrefs` 三个字段改为**能力注入的函数**（`storageProbe`/`storageRoot` 已经是这种正确手法，见 `lib/surface/surface_bridge.dart:71,77`）。

### 5.3 页面是否绕过桥直接 import domain/base 内部文件 — **成立（独立复核后仍为 0）**

独立复核（不依赖 layer_audit 报告，直接全量检索 `lib/surface/**` 的 import）：
```
$ rg -n "^import '.*(domain|base|kernel|platform)/" lib/surface
lib/surface/app/client_shell.dart:19:  ../../kernel/kernel.dart
lib/surface/app/desktop_window.dart:24-25: ../../platform/platform.dart, ../../platform/window_capability.dart
lib/surface/app/error_surface.dart:24-26: kernel/boot/trust_warnings.dart, kernel/diagnostics.dart, kernel/log/og_l_log_file.dart
lib/surface/app/font_loader.dart:19:   kernel/log/og_l_log_file.dart
lib/surface/app/keyboard_guard.dart:18: kernel/log/og_l_log_file.dart
lib/surface/app/og_l_app.dart:18:      kernel/kernel.dart
lib/surface/app/permission_selftest.dart:21: kernel/diagnostics.dart
lib/surface/pages/about_page.dart:15: kernel/kernel.dart
lib/surface/pages/search_page.dart:17: kernel/log/og_l_log_file.dart
lib/surface/pages/settings_page.dart:31-32: kernel/kernel.dart, kernel/log/og_l_log_file.dart
lib/surface/surface_bridge.dart:18-28:（合法例外：base/domain 装配根）
```
- **没有任何页面 import `domain/` 或 `base/` 内部文件**（含 `lib/domain/ix/`、`lib/domain/gh/` 之外的边角：`lib/surface/util/`、`lib/surface/widgets/`、`lib/surface/i18n/`、`lib/surface/app/` 均已覆盖在上面的检索范围内）。
- kernel（契约层）与 platform 是合法的向下依赖。
- 唯一「非 import 路径」的绕过是**类型泄漏**（§4.2/§5.2）：页面经 `widget.surface.domain.api` 触达 domain 实现类 —— 这不是 import 违规，但同样是「页面直接消费下层服务」。

---

## 6. 跨层数据形状

### 6.1 L3 渲染模型是否都经 types.dart — **基本成立（13 个页面不 import types，但只是用类型推断）**

- 29 个页面中 16 个 `import '../types.dart'`；未 import 的 13 个（`about_page`、`action_log_page`、`gists_page`、`issue_page`、`legal_text_page`、`network_page`、`new_gist_page`、`new_issue_page`、`notifications_page`、`onboarding_page`、`pull_page`、`settings_section_page`、`workflow_dispatch_page`）经复核**只使用 `var`/`final` 推断出来的 domain 类型**，未写出任何 `Gh*`/`Ix*`/`Repo*` 类型名（`rg -o "\bGh[A-Z]\w*|\bIx[A-Z]\w*|\bRepo[A-Z]\w*" lib/surface` 统计：这 13 个文件均未出现在命中列表里）。
- `lib/surface/util/gh_format.dart:9` `import '../types.dart';` ✅（格式化工具也走门面）。

**结论：成立**（类型来源唯一）。

### 6.2 有没有把 domain 的可变状态对象直接给页面 — **不成立（存在直接传递）**

页面拿到的 domain 侧对象中，**至少 4 个是 `ChangeNotifier` 可变状态对象**，且是**实现类**而非 DTO：

| 对象 | 定义 | 页面取用点 |
|---|---|---|
| `GhAuthService`（登录态） | `lib/domain/gh/gh_auth.dart:159` `class GhAuthService extends ChangeNotifier` | `lib/surface/app/client_shell.dart:89,116-117`；`lib/surface/pages/login_page.dart:153`；`lib/surface/pages/settings_page.dart:92,102,132,134` |
| `IxDownloadManager`（下载管理器） | `lib/domain/ix/ix_download.dart:501` `class IxDownloadManager extends ChangeNotifier` | `lib/surface/pages/repo_page.dart:308,1894`；`lib/surface/pages/dashboard_page.dart:385,387`；`lib/surface/pages/download_manager_page.dart:401` 等 8 处 |
| `IxSession`（会话/偏好） | `lib/domain/ix/ix_session.dart:94` `class IxSession extends ChangeNotifier` | `lib/surface/pages/profile_page.dart:98` |
| `IxActionLogs`（服务，非状态但为实现类） | `lib/domain/ix/ix_action_logs.dart:49` | `lib/surface/pages/action_log_page.dart:154,189,192,281`；`lib/surface/pages/action_run_page.dart:250,290,315,318` |

- 讽刺的是，**SurfaceBridge 已经备好了正确的 DTO 出口**，页面却绕开它直接摸实现类：
  - `lib/surface/surface_bridge.dart:425` `Listenable get downloadsListenable => domain.downloads;`
  - `lib/surface/surface_bridge.dart:428` `List<IxDownloadTask> get downloadTasks => domain.downloads.tasks;`
  - `lib/surface/surface_bridge.dart:431-455` 已封装 `supportsPauseResume` / `isRanged` / `connectionsOf` / `clearFinishedDownloads` / `pause` / `resume` / `retry` / `cancel` / `remove`。
  - 但 `lib/surface/pages/download_manager_page.dart:401` 用的是 `widget.surface.domain.downloads.isRanged(task.id)`，**不是** `widget.surface.isRangedDownload(id)`；`repo_page.dart:308` 用 `widget.surface.domain.downloads.enqueue(...)`——**`enqueue` 在桥上根本没有对应出口**（桥只转发控制类操作，漏了入队）。
- 结论：**应转为不可变 DTO 的对象没有转**；桥已建的 DTO 出口被页面集体忽略。

**建议（不涉及本次改码）**：为 `enqueue` 等入队能力补桥出口；把 `downloadsListenable`/`downloadTasks` 作为页面**唯一**入口；对 `GhAuthService`/`IxSession` 的可变态（登录态、会话偏好）改为「桥上暴露不可变快照 + 桥自己订阅通知」，页面不再持有 domain 的 `ChangeNotifier`。

---

## 7. platform 层的地位

### 7.1 platform 是否只依赖 kernel — **成立（但门禁是死代码，见 §8）**

`lib/platform/**` 的全部 import（无 base / 无 domain）：
```
lib/platform/platform.dart:17,19-23   package:flutter/foundation.dart + 同层 window_*.dart
lib/platform/window_linux.dart:11-14   package:flutter/foundation.dart, package:window_manager/window_manager.dart, 同层
lib/platform/window_macos.dart:7-10    同上
lib/platform/window_mobile.dart:8-10   同上
lib/platform/window_windows.dart:10-13 同上
```
→ **platform 只依赖 flutter 包与自身，不依赖 kernel/base/domain**。事实层面成立。

### 7.2 跨平台条件 import 是否都经 lib/platform — **不成立**

- 条件 import 只有 2 处，且**都不在 platform**：
  - `lib/domain/gh/gh_oauth.dart:22` `import 'gh_oauth_stub.dart' if (dart.library.io) 'gh_oauth_io.dart' as impl;`
  - `lib/domain/ix/ix_action_logs.dart:25` `if (dart.library.js_interop) 'ix_action_logs_save_stub.dart' as io_impl;`
- `dart:io` **不收敛在 platform**，共 36 个文件命中，散布四层：
  - L2 domain：`lib/domain/sys/sys_platform_io.dart:7`、`lib/domain/ix/ix_action_logs_save_io.dart:7`、`lib/domain/ix/ix_presign_io.dart:8`、`lib/domain/ix/ix_download_backend_io.dart:9`、`lib/domain/ix/ix_action_logs_http_io.dart:7`、`lib/domain/gh/gh_oauth_io.dart`
  - L0 kernel：`lib/kernel/log/og_l_log_file_io.dart:7`
  - L1 base：`lib/base/net/io_net_transport.dart` 等
  - **L3 surface 也有**：`lib/surface/pages/settings_page.dart:24` `import 'dart:io';`、`lib/surface/app/font_pick.dart:10` `import 'dart:io';`
- AGENTS.md §1 已自陈这一现状：「平台实现 `*_io.dart` / `*_web.dart`（条件 import，编译期解析 —— **现状：`lib/platform/` 下无条件 import**）」——即规范承认未落地。

**结论：platform 的「只依赖 kernel」成立；「跨平台条件 import 都经 lib/platform」不成立**（条件 import 集中在 domain 层，`dart:io` 分散 36 文件，且 surface 页面直接 import `dart:io`）。

---

## 8. 门禁能否守住这些原则（覆盖矩阵 + 反例）

### 8.1 覆盖矩阵

| 原则 | 现有门禁 | 覆盖情况 |
|---|---|---|
| 单向依赖（import 边） | `tool/layer_audit.py:105-125`（import **与** export 都算） | ✅ 覆盖（含 export，`layer_audit.py:61`） |
| 合法例外 3 文件 | `layer_audit.py:53-57` `ALLOW` | ✅ 覆盖 |
| KNOWN 2 项 | `layer_audit.py:71-74` | ✅ 覆盖（且按解析后规范化路径匹配，绕过不易） |
| 文件头层级前缀 | `tool/contract_audit.py:96-113` | ✅ 覆盖（仅看文件前 400 字符） |
| export 指向真实文件 / 不向上 | `contract_audit.py:76-93` | ✅ 覆盖（但 `if (' in imp` 永假 → 见 8.2） |
| 平台判定走门面 | `contract_audit.py:116-123`（`defaultTargetPlatform` 白名单） | ⚠️ 只查 `defaultTargetPlatform`，不查 `dart:io` |
| 装配顺序 L0→L3 | `contract_audit.py:145-204` | ⚠️ 只认 `main.dart` 里 `<OgLModule>[` 列表，改写法即失效（`:159` 直接 return） |
| 桥齐全 / 唯一 | 运行时 `bridge_registry.dart:70-78` + `main.dart:221-225` | ✅ 启动期强制 |
| platform 只依赖 kernel | `layer_audit.py:50,111-115` | ❌ **规则是死代码**（见 8.2-①） |
| 模块能力耦合 | 无 | ❌ 无门禁 |
| DI 层隔离 | 无 | ❌ 无门禁 |
| 门面纪律（types.dart 不导服务） | 无 | ❌ 无门禁 |
| 桥不暴露下层实现类 | 无 | ❌ 无门禁 |
| 条件 import 的平台分支 | 无（正则只捕获第一个引号路径） | ❌ 无门禁 |
| 门禁自身有效（CWD/反向注入） | `tool/gate_of_gates.py` | ⚠️ 只做 2 条反向注入（layer 空扫、i18n dict），**无一条针对分层规则** |

### 8.2 反例（"若把 X 改成 Y，现有门禁会不会拦"）

① **platform 违规不会被拦（严重）**。`layer_audit.py:43-44` 的 `LAYERS = ['kernel','base','domain','surface']` 不含 `'platform'`；`layer_of()`（`:77-79`）对 `platform/...` 返回 `None`；主循环 `:98-99` `if lay is None: continue` → **platform 目录的文件根本不会被扫描**。`PLATFORM_ONLY_KERNEL`（`:50`）与 `:111-115` 的判断因此**永远不执行**（`lay` 不可能是 `'platform'`）。
反例：在 `lib/platform/platform.dart` 加 `import '../base/disk/disk_cache.dart';` → `layer_audit` 与 `contract_audit` **双双报绿**。（本报告 §7.1 的结论是靠人工检索得到的，不是靠门禁。）

② **条件 import 的平台分支不会被拦**。`layer_audit.py:61` `IMPORT_RE = re.compile(r"^\s*(?:import|export)\s+'([^']+)'", re.M)` 只捕获**第一个**引号路径：
`import 'x_stub.dart' if (dart.library.io) 'x_io.dart' as impl;` → 只检查 `x_stub.dart`，`x_io.dart` 完全不可见。
反例：把 `lib/domain/gh/gh_oauth_io.dart` 的内容改成 import `../../base/disk/disk_cache.dart` → 门禁不报。（`contract_audit.py:83` 的 `if ' (' in imp: continue` 同样无效——`imp` 只含第一个路径，永不含 `if (`。）

③ **types.dart 导出服务类不会被拦**。`lib/surface/types.dart` 在 `ALLOW` 内（`layer_audit.py:56`），其 export 边被完全豁免；`contract_audit` 只查「指向是否存在」「是否向上」，不查「是不是服务/实现类」。
反例：把 `types.dart:43` 改成 `export '../domain/ix/ix_presign.dart';`（连带导出服务类与 `IxPresign` 构造器）→ 两道门禁均报绿。

④ **桥把下层实现类暴露给 L3 不会被拦**。`lib/surface/surface_bridge.dart` 在 `ALLOW` 内；把 `lib/surface/surface_bridge.dart:63` 的 `final NetBridge? net;` 改成 `final RepositoryCache cache;`（或新增 `final NetBridge net;`）→ 门禁全绿，而 L3 已能持有 L1 一致性引擎实体。

⑤ **模块改用具体类型耦合不会被拦**。把 `lib/domain/domain_bridge.dart:387` 的 `context.di.resolve<GhAuthService>()` 改成 resolve 任意新类型、descriptor 的 `provides` 改成空数组 → `ModuleBus` 只校验 `provides` **唯一性**（`module_bus.dart:86,95`）与 `requires` 的模块 ID 存在性，**不校验「要求的能力是否被提供/被消费」** → 门禁全绿。

⑥ **页面绕过桥直接拿实现类不会被拦**。把 `lib/surface/pages/download_manager_page.dart:401` 的 `widget.surface.domain.downloads.isRanged(task.id)` 改成任何 `widget.surface.domain.<任意实现类>.xxx` → 无静态门禁（layer_audit 只看 import）。

⑦ **KNOWN 白名单是「路径级」而非「符号级」**：一旦 `gh_api.dart` 需要 base 的**另一个**符号（如 `disk_cache.dart` 里的 `CacheRemote` 已被 `gh_api.dart:30` 使用，但该 import 恰好在白名单内），白名单**不会**因为「符号变多」而报警；只有**换文件**才报违规。→ 「KNOWN 恰好 2 项」在符号粒度上并不被守。

### 8.3 缺口小结

现有门禁能守住「**import 边**」，守不住「**类型面 / 能力面 / 行为面**」。本报告 §4.2、§5.1、§5.2、§6.2 发现的四个缺口**全部在门禁盲区**内；§7.1 的 platform 结论甚至**不在任何门禁的有效扫描范围内**（死代码规则）。

---

## 9. 总体结论

### 9.1 逐条判定

| # | 检查项 | 判定 |
|---|---|---|
| 1 | 层桥完整性（实现/注册/文件头/不绕过桥 new） | **成立**（前提修正：只有三座桥，kernel 无桥；唯一小缺口是 `SurfaceBridge.of()` 死代码） |
| 2 | KNOWN 2 项 | **有缺口**（已知白名单 2 项成立；本报告给出 A/B 两套可分步方案） |
| 3 | 模块独立性 | **有缺口**（`provides/requires` 能力体系无消费侧，耦合实为具体类型；模块还额外暴露服务字段） |
| 4 | DI 容器边界 | **有缺口**（全局单容器无层命名空间；`SurfaceBridge` 把 L1 实现 `NetBridge`/`RepositoryCache`/`DiskKv` 与 L2 实现 `RepoFileService` 暴露给 L3） |
| 5 | 门面纪律 | **有缺口**（`types.dart:43` 导出服务类 `IxPresign`；`surface_bridge.dart` 与 `types.dart` 的 `hide RepoFileService` 自相矛盾；页面绕过桥 import domain/base 复核后确为 0） |
| 6 | 跨层数据形状 | **有缺口**（类型来源唯一 ✅；但 4 个 domain 可变状态对象直接给页面 ❌，桥上已备好的 DTO 出口被忽略） |
| 7 | platform 地位 | **有缺口**（platform 只依赖 kernel 事实成立；但条件 import 未经 platform，`dart:io` 分散 36 文件且 surface 页面直接 import） |
| 8 | 门禁覆盖 | **有缺口**（import 边守得住；类型面/能力面/数据形状面全部失守；platform 规则是死代码） |

### 9.2 最重要 3 条

1. **`lib/surface/surface_bridge.dart` 是当前最大的架构漏口**（`:63` `NetBridge`、`:66` `RepositoryCache`、`:84` `DiskKv`、`:467` `RepoFileService`）。它把 L1 的**一致性引擎实体**和 L2 的**服务实现**直接递到 L3 手里，且与 `lib/surface/types.dart:34` 的 `hide RepoFileService` 直接矛盾。**门禁管不到它**（ALLOW 文件），所以它一旦扩大不会被发现。
2. **能力体系（provides/requires）是装饰性的**：声明了 `'gh.auth'` 之类的能力串，实际消费全走 `KernelDi.resolve<T>()` 的**具体类型**（`lib/domain/domain_bridge.dart:387`）。「模块独立」这条原则在代码里**没有真正落地**，只是有了一份看起来像的声明。
3. **门禁存在一条死规则 + 两个盲区**：`layer_audit.py` 的 platform 单边规则因 `LAYERS` 不含 `'platform'` 而**永不执行**（`layer_audit.py:43,77-79,98-99,111-115`）；条件 import 的第二个分支不被解析（`:61`）；`types.dart`/`surface_bridge.dart` 里的**类型面**完全不受检。→ 「原则成立与否」目前**靠人盯，不靠门禁守**。

### 9.3 最该先收敛的一条

**先收敛 `lib/surface/surface_bridge.dart` 的类型面（第 4/5 条），而不是先动 KNOWN 2 项。**

理由：
- KNOWN 2 项是**已登记、已被门禁记账**的债，漏不掉、跑不掉；而 surface 桥的类型泄漏**没有任何门禁在看**，风险在持续累积（任何人加一个 `final X x;` 都不会被报）。
- 收敛成本低、纯机械、无运行时语义变化：
  1. `net` / `cache` / `uiPrefs` 三个字段 → 改为**能力函数注入**（与 `storageProbe`/`storageRoot` 同一手法，`lib/surface/surface_bridge.dart:71,77`）；
  2. `repoFiles` → 只暴露**动作方法**（`createRepoFile/deleteRepoFile/renameRepoFile`），不暴露 `RepoFileService` 类型；页面改调 `lib/surface/pages/repo_page.dart:1547,1625,1726,1827` 四处；
  3. `types.dart:43` 撤掉 `IxPresign`，只留 `IxPresignResult` + 抽出的 `normalizeDigest` 纯函数（`lib/surface/pages/release_detail_page.dart:292` 一处调用）。
- 完成后「L3 可见类型面」= DTO/枚举/异常 + 桥自身能力方法，才是真正的门面纪律；**且这条收敛不被任何门禁覆盖，所以只能靠评审**——建议同时补一条门禁（见 §9.4 第 1 步）。

### 9.4 建议路线图（5 步，每步含风险与验证方式）

> 与 §2 的 KNOWN 收敛方案**并行编排**：本路线图按「先堵漏口、再解债、最后补门禁」排序，KNOWN 收敛（A/B 方案）作为第 3/4 步穿插。

**第 1 步 · 堵住 surface 桥的类型漏口（不改行为）**
- 范围：`lib/surface/surface_bridge.dart`（`net`/`cache`/`uiPrefs` 改函数注入）、`lib/surface/types.dart`（撤 `IxPresign`）、`lib/domain/ix/ix_presign.dart`（抽出 `normalizeDigest` 纯函数）、`lib/surface/pages/repo_page.dart`（4 处改调桥方法）、`lib/surface/pages/release_detail_page.dart:292`。
- 风险：**低**（纯结构调整；`clearRepositoryCache`/`dnsServerChoices`/`dnsSummary`/`applyDns` 等已有 API 保持不变）。
- 验证：`dart analyze lib/surface`；`dart format --output=none lib`；截图/手动回归设置页 DNS、账号切换清缓存、仓库文件增删改四个路径；`layer_audit/contract_audit` 仍 0 违规。

**第 2 步 · 补门禁盲区（工具侧，不改业务代码）**
- 范围：`tool/layer_audit.py`（① 把 `platform` 纳入 `LAYERS` 或单列 `SCAN_DIRS` 让 `PLATFORM_ONLY_KERNEL` 真正生效；② `IMPORT_RE` 改为捕获**全部**引号路径，使条件 import 的第二个分支也参与判定）；`tool/contract_audit.py`（③ 新增「门面类型面」检查：`types.dart` 的 export 命中集不得包含服务/实现类，且 `surface_bridge.dart` 不得出现 base/domain 实现类型作为公开字段类型）；`tool/gate_of_gates.py`（④ 增加两条针对分层规则的反向注入：在临时副本里给 platform 加 base import → 必须报错；给条件 import 加越界分支 → 必须报错）。
- 风险：**低**（只改工具；须先跑一遍确认新规则在当前代码上 **0 违规**，否则第 1 步成果会被新门禁打回）。
- 验证：`python3 tool/layer_audit.py --fatal`、`python3 tool/contract_audit.py --fatal`、`python3 tool/gate_of_gates.py --fatal` 三者全绿；且**故意注入 4 个反例（§8.2 ①②③④）必须全部被抓**。

**第 3 步 · KNOWN #2 收敛（`NetClient`）**
- 范围：`lib/kernel/contract/net_client.dart`（新增）、`lib/base/net/net_bridge.dart`（`implements NetClient`）、`lib/domain/gh/gh_client.dart`（参数/字段改 `NetClient`、删 base import）、`tool/layer_audit.py`（撤一条 KNOWN）。
- 风险：**极低**（1 个调用点、1 个构造点；`GhClient(net: base.net, …)` 不变，**不破坏现有 API**）。
- 验证：`layer_audit` 的「已知待收敛」计数 2 → 1 且违规仍 0；`dart analyze lib/kernel lib/base lib/domain` 0 问题；`test/domain/gh_submit_e2e_test.dart` + `test/domain/` 全量；`test/kernel/chaos_test.dart`。

**第 4 步 · KNOWN #1 收敛（`CacheRemote` 上提 → `ConsistencyCache` 契约）**
- 顺序严格分三小步（各自独立提交）：
  - 4a：`CacheRemote` 从 `lib/base/disk/disk_cache.dart:40` 上提到 `lib/kernel/contract/disk_types.dart`，base 转发导出，`gh_api.dart:30` 改 implements，**`gh_api.dart:17` 的 import 改为 kernel 契约** → KNOWN #1 命中数可能不变（因为仍 import `RepositoryCache`），但**接口归属已正**。
  - 4b：新增 `lib/kernel/contract/consistency_cache.dart`（`read/write/invalidate/delete/loadDraftSnapshot/purge/draftsChanged`），`RepositoryCache implements ConsistencyCache`，`DiskBridge.cache` 类型收窄为契约。
  - 4c：`gh_api.dart:54,63,73` 改依赖 `ConsistencyCache`，删 base import；`domain_bridge.dart:162,168` 调用点保持兼容；撤 `tool/layer_audit.py` 最后一条 KNOWN。
- 风险：**中**（牵涉 D1–D9 语义链与草稿通知源；`kernel/contract` 引入 `package:flutter/foundation.dart` 的 `Listenable` 需确认「kernel 无 Flutter SDK 可 analyze」这条 CI 事实不被破坏——若被破坏，退化为回调式契约 `addDraftsListener(void Function())`）。
- 验证：`test/base/cache_consistency_test.dart`、`test/base/durability_test.dart`、`test/domain/gh_submit_e2e_test.dart`、`test/kernel/chaos_test.dart`、`test/base/` 全量；`layer_audit` 已知待收敛计数 → **0**；`boot_manifest.py` 需重跑签名（改了四层文件）。

**第 5 步 · 能力体系与数据形状收口（结构性，最后做）**
- 5a：`KernelDi` 增加「按能力串 resolve」的用法（`resolveByCapability('gh.auth')`）或让模块的 `provides` 真正被消费，`IxModule` 不再 resolve `GhAuthService` 具体类型。
- 5b：把 `GhAuthService`/`IxSession`/`IxDownloadManager` 的**可变态**改为「桥上不可变快照 + 桥内部订阅」，页面不再持有 domain 的 `ChangeNotifier`；补 `enqueue` 等缺失的桥出口，让 `lib/surface/pages/download_manager_page.dart:401` 等处改走 `SurfaceBridge` 已有的 DTO 出口（`lib/surface/surface_bridge.dart:425-455`）。
- 5c：DI 按层隔离（引入层级命名空间或分层容器），杜绝「拿到 Type 就能跨层解析」。
- 风险：**高**（触及全部页面与鉴权/下载/会话状态流；建议每小步独立 PR + 截图回归）。
- 验证：`test/` 全量；`dart analyze lib/kernel lib/base lib/domain` 0 问题；`dart format --output=none lib`；登录→下载→切号→清缓存→登出 全链路回归；截图对比（`test/screenshots/`）；`boot_manifest.py` 重跑。

---

## 10. 审计边界与诚实声明

- 本次为**只读静态审计**：未运行 `flutter`（设备环境无 Flutter SDK），未执行任何写操作或 git 操作；`dart analyze` 结论**引用自 AGENTS.md 与门禁脚本的既有事实**，未在本次会话中实测（`dart` 命令在沙箱内不存在）。
- 所有「文件:行号 + 代码片段」均为本次实测抓取（`rg` / `sed` / `cat -n`），未复制既有审计文档的结论；`layer_audit.py` 与 `contract_audit.py` 均已实跑，输出为「违规 0 处 / 已知待收敛 2 处」。
- 动态行为（运行时 DI 解析、模块拓扑、缓存 D1–D9 实际语义）**未做运行时验证**，相关判断基于代码路径静态推导。
- 其他代理正在修改 `lib/base/net/net_dns.dart`、`net_transport.dart`、`lib/domain/ix/ix_download.dart`、`lib/surface/pages/download_manager_page.dart` 等文件；本报告的行号基于 **HEAD `64cf405`**，若这些文件在落地前变更，涉及 `download_manager_page.dart` / `ix_download.dart` 的行号需重新核对（结论方向不受影响）。
