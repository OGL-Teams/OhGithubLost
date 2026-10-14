/// L3 展示级 · 表面桥（Surface Bridge）与装配根。
///
/// ## 分层纪律
/// 本文件是**展示层的装配根**，和 `DomainLayerModule` 同级，因此它可以跨层
/// import 底座桥（就像中枢层那样）。除此之外，
/// **所有页面与控件一律只通过 [SurfaceBridge] 取用**，不得直接 import base/domain。
///
/// ## 它把两件事接到一起
/// 1. **设置落盘**：`OgLSettingsController` ↔ L1 的 KV（`base.disk.kv`）；
/// 2. **DNS 即时生效**：设置里的 DNS 选择 → `base.net.applyDnsSelection`。
///
/// 主题编译（`themeFor`）也在这里收口：
/// 设置里的明暗偏好 + 系统亮度 → 唯一一次 `ThemeData` 编译。
library;

import 'package:flutter/material.dart';

import '../base/base_bridge.dart';
import '../base/disk/app_dirs.dart';
import '../base/disk/disk_cache.dart';
import '../base/disk/disk_store.dart';
import '../base/disk/og_l_storage.dart';
import '../base/net/net_bridge.dart';
import '../domain/domain_bridge.dart';
import '../domain/gh/repo_file_service.dart';
import '../kernel/bridge_registry.dart';
import '../kernel/contract/module.dart';
import 'app/error_surface.dart';
import 'app/motion.dart';
import 'i18n/og_l_i18n.dart';
import 'settings.dart';
import 'theme.dart';
import 'types.dart';
import 'util/accel.dart';
import 'util/download_proxy.dart';

/// 表面桥：展示层对外的唯一入口。
class SurfaceBridge {
  /// 创建桥。
  SurfaceBridge({
    required this.settings,
    required this.domain,
    this.net,
    this.cache,
    this.storageProbe,
    this.uiPrefs,
  });

  /// 从内核桥表解析（展示层的标准取用方式）。
  static SurfaceBridge of(KernelBridgeRegistry bridges) =>
      bridges.resolve<SurfaceBridge>(ModuleLayer.surface.key);

  /// 设置控制器。
  final OgLSettingsController settings;

  /// 中枢桥（页面需要业务数据时通过它取）。
  final DomainBridge domain;

  /// 网络门面（**仅供设置页应用 DNS 用**；页面不得直接使用）。
  final NetBridge? net;

  /// 一致性缓存（**仅供账号切换时清空**，页面不得直接读写）。
  final RepositoryCache? cache;

  /// 存储可用性探针（由装配层注入；返回是否可写）。
  ///
  /// 展示层不直接依赖底座，因此以函数形式注入。
  final Future<bool> Function()? storageProbe;

  /// 界面偏好 KV（**纯展示层状态**：分组展开状态等）。
  ///
  /// 为什么不塞进 [settings]：`OgLSettings` 是"用户设置"，
  /// 「哪个分组是展开的」不是设置、也不该被"重置设置"清掉
  /// （重置后分组开合保持原样，用户不会突然找不到刚才那一组）。
  final DiskKv? uiPrefs;

  /// 读一条界面偏好（无记录 / 未接线 / 读失败一律 `null`）。
  Future<String?> readUiPref(String key) async {
    try {
      return await uiPrefs?.read(key);
    } catch (_) {
      // 读不到就用默认值：界面偏好缺失不影响任何功能。
      return null;
    }
  }

  /// 写一条界面偏好（写失败只留诊断日志，不打扰用户）。
  Future<void> writeUiPref(String key, String value) async {
    try {
      await uiPrefs?.write(key, value);
    } catch (error) {
      OgLAppLog.instance.add(
        '界面偏好',
        '写入失败：$key -> $error',
        severity: OgLNoticeSeverity.warning,
      );
    }
  }

  /// 探测存储是否可用（无探针时按可用处理）。
  Future<bool> ensureStorage() async {
    final probe = storageProbe;
    if (probe == null) {
      return true;
    }
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  /// 应用根目录展示串（供"关于"等处展示实际落盘位置）。
  Future<String> appRootPath() async {
    try {
      return await OgLAppDirs.root();
    } catch (_) {
      return OgLI18n.instance.t('common', 'unknown');
    }
  }

  /// 当前落盘位置（路径串；供权限说明里如实展示）。
  Future<String> appStoragePath() async => (await appStorageInfo()).path;

  /// 当前落盘位置摘要：路径 + **是否用户可见**（文件管理器 / 电脑能找到）。
  ///
  /// 可见性由**三档方案**裁决：公共目录 ✅ / SAF 文件夹 ✅ / 应用内部 ⚠️。
  Future<({String path, bool visible})> appStorageInfo() async {
    try {
      final OgLStoragePlan plan = await OgLStorage.plan();
      return (path: plan.root, visible: plan.userVisible);
    } catch (_) {
      return (path: OgLI18n.instance.t('common', 'unknown'), visible: false);
    }
  }

  /// 当前落盘档位（`public` / `saf` / `internal`；供 UI 如实展示）。
  Future<String> appStorageMode() async {
    try {
      return (await OgLStorage.plan()).label;
    } catch (_) {
      return 'internal';
    }
  }

  /// 已授权的 SAF 文件夹 URI（未授权 = `null`）。
  Future<String?> safTreeUri() async {
    await OgLStorage.ensureLoaded();
    return OgLStorage.safTreeUri;
  }

  /// 让用户**选一个文件夹**（SAF）并持久化授权；返回是否成功。
  Future<bool> pickSafDirectory() async {
    final String? uri = await OgLSaf.pickDirectory();
    if (uri == null) {
      return false;
    }
    await OgLStorage.setSafTreeUri(uri);
    return true;
  }

  /// 取消 SAF 授权（回到"内部存储"档）。
  Future<void> clearSafDirectory() => OgLStorage.setSafTreeUri(null);

  /// 清空本机仓库缓存。
  ///
  /// **多用户安全**：缓存按仓库维度存放，不含账号信息。若切换账号后不清理，
  /// 就可能出现"用 B 账号看到 A 账号私有仓库缓存"的串台。因此切换账号时
  /// 由设置/账户页显式调用本方法。
  Future<int> clearRepositoryCache() async => await cache?.purge() ?? 0;

  /// **注销一个账号**（迁移 / 移除 本机凭据），并清空全部本机缓存。
  ///
  /// ## 为什么收口在这里
  /// 这是**同一个操作**，此前却有两份实现在并行：
  /// · 「我的」页 `_remove`：`removeAccount` + 只清**仓库缓存**
  /// · 设置页 `_logout`（已被取代、未接线）：`removeAccount` + 清**全部缓存**
  ///
  /// 两者清理范围不同 —— 前者会留下 DNS 缓存与页面分页快照。多账号场景下
  /// 这正是「用 B 账号看到 A 账号内容」的串台来源。而本类的 `clearAllCaches`
  /// 注释里早就写着「**用户要求：切换 / 移除账号时必须清除所有缓存**」。
  ///
  /// 现在统一走这里：注销 + 清全部缓存。调用方只需额外调一次
  /// `clearOgLRepoPageCaches()`（页面级快照在页面层，桥不反向依赖页面）。
  ///
  /// 返回是否成功；失败时**如实抛出**，由调用方呈现。
  Future<void> forgetAccount(String accountId) async {
    await domain.auth.removeAccount(accountId);
    await clearAllCaches();
  }

  /// 清空**全部**本机缓存（仓库缓存 + DNS 缓存 + 页面分页快照）。
  ///
  /// 用户要求：**切换 / 移除账号时必须清除所有缓存**。
  /// 页面级快照由调用方额外调用 `clearOgLRepoPageCaches()`（避免桥依赖页面）。
  Future<int> clearAllCaches() async {
    final int removed = await clearRepositoryCache();
    try {
      // 只读端点缓存（releases / branches / issues …）同样按账号隔离，
      // 切号必须一并清空，否则会出现"用 B 账号看到 A 账号缓存"的串台。
      await domain.api.invalidateReadCache();
      net?.dns?.cache.clear();
    } catch (error) {
      // 不允许静默：清不掉也要留痕（通知中心可见）。
      OgLAppLog.instance.add(
        '缓存',
        '清空 DNS 缓存失败：$error',
        severity: OgLNoticeSeverity.warning,
      );
    }
    return removed;
  }

  /// DNS 可选服务器（id → 展示名）。
  Map<String, String> get dnsServerChoices =>
      net?.dnsServerChoices ?? const <String, String>{};

  /// 当前 DNS 策略摘要（UI 必须向用户展示，不得让用户猜）。
  String get dnsSummary =>
      net?.dnsSummary ?? OgLI18n.instance.t('common', 'systemResolve');

  /// 把当前设置里的 DNS 选择应用到网络底座（策略对象可变 → 即时生效）。
  void applyDns() {
    final OgLSettings current = settings.settings;
    net?.applyDnsSelection(
      custom: current.dnsMode == 'custom',
      serverId: current.dnsServerId,
      preferDoh: current.dnsPreferDoh,
    );
  }

  /// 便捷：改 DNS 模式并即刻应用。
  Future<void> setDnsMode(String mode) async {
    await settings.setDnsMode(mode);
    applyDns();
  }

  /// 便捷：换 DNS 服务器并即刻应用。
  Future<void> setDnsServer(String serverId) async {
    await settings.setDnsServer(serverId);
    applyDns();
  }

  /// 便捷：切换 DoH 优先并即刻应用。
  Future<void> setDnsPreferDoh(bool enabled) async {
    await settings.setDnsPreferDoh(enabled);
    applyDns();
  }

  // ── Release 下载加速通道（总开关 / 通道增删选 / 协议同意）───────────────

  /// 便捷：Release 附件是否走加速通道（总开关）。
  Future<void> setReleaseProxyEnabled(bool enabled) =>
      settings.setReleaseProxyEnabled(enabled);

  /// 便捷：选择生效的加速通道。
  Future<void> setReleaseProxySelected(String channelId) =>
      settings.setReleaseProxySelected(channelId);

  /// 便捷：开关某个加速适用范围。
  Future<void> setAccelScope(OgLAccelScope scope, bool enabled) =>
      settings.setAccelScope(scope, enabled);

  /// 便捷：设置「私有仓库是否允许走加速」。
  ///
  /// 语义见 `OgLSettings.accelPrivateRepoAccepted`：
  /// `true` = 用户知情接受（令牌会交给第三方代理）；`false` = 不加速。
  Future<void> setAccelPrivateRepoAccepted(bool on) =>
      settings.setAccelPrivateRepoAccepted(on);

  /// 便捷：新增 / 更新一个自定义加速通道。
  Future<void> upsertAccelChannel(OgLAccelChannel channel) =>
      settings.upsertAccelChannel(channel);

  /// 便捷：删除一个自定义加速通道（内置通道不可删）。
  Future<void> removeAccelChannel(String channelId) =>
      settings.removeAccelChannel(channelId);

  /// 便捷：记录"已同意当前版本协议"（含时间凭据）。
  Future<void> acceptAccelConsent() => settings.acceptAccelConsent();

  // ── 下载地址解析（加速的前置步骤）────────────────────────────────────

  /// 把「需要认证的第一跳地址」解析为**可直接下载**的地址。
  ///
  /// Release 附件 / Action 日志 / Action 产物都是「302 → 短期签名 URL」结构，
  /// 由域层 `IxPresign` 在**本地**走完第一跳（令牌不出设备），拿到绑定单对象
  /// 且约 30 分钟有效的签名地址；页面随后才决定是否把它交给加速通道。
  ///
  /// 解析失败时**如实回退**到原始地址（宁可慢，也不静默失败）。
  Future<String> resolveDownloadUrl(String url) async {
    try {
      final result = await domain.presign.resolve(url);
      return result.url ?? url;
    } catch (_) {
      return url;
    }
  }

  /// 下载用的认证头（**仅在无法预解析时**才需要，例如直连私有仓库的 raw 地址）。
  ///
  /// 返回空表表示未登录。令牌不会离开设备，但调用方**不得**把这些头交给
  /// 加速通道 —— 那等于把令牌送给第三方。
  Future<Map<String, String>> downloadAuthHeaders() async {
    try {
      final token = await domain.auth.activeToken();
      final String? value = token?.value;
      if (value == null || value.isEmpty) {
        return const <String, String>{};
      }
      return <String, String>{'authorization': 'Bearer $value'};
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// 仓库文件的**下载方案**：地址候选 + 请求头（两条路，收口在这里）。
  ///
  /// - **不加速** → `/repos/…/contents/…` 加 `Accept: application/vnd.github.raw`
  ///   并带 Bearer。该端点实测支持 Range，所以多连接分片下载照常可用。
  /// - **加速**（**自定义通道** + 公开仓库，或私有仓库且用户已知情接受）→
  ///   把 **raw 链接**交给代理。公开仓库不需要令牌、不限流；私有仓库的 raw
  ///   必须带令牌（代理会原样转发 `Authorization`），因此只有用户
  ///   知情接受"令牌会交给第三方通道"之后才允许 —— 见
  ///   `ogLAccelCandidates` 的 `privateAccelAccepted`。
  /// 判定规则见 `util/download_proxy.dart`。
  Future<({List<String> urls, Map<String, String> headers})>
      planRepoFileDownload({
    required String fullName,
    required String path,
    required String branch,
    required bool repoPrivate,
    int? size,
  }) async {
    final OgLSettings current = settings.settings;
    final String encodedPath =
        path.split('/').map(Uri.encodeComponent).join('/');
    final String rawUrl = 'https://raw.githubusercontent.com/$fullName/'
        '${Uri.encodeComponent(branch)}/$encodedPath';
    final List<String> candidates = ogLAccelCandidates(
      url: rawUrl,
      // 本处是「仓库文件」这一类的唯一入口（仓库页下载 / 预览页加入下载共用）。
      prefixes: current.accelPrefixesFor(OgLAccelScope.repoFile),
      family: OgLAccelFamily.raw,
      bytes: size,
      repoPrivate: repoPrivate,
      // 私有 + 加速：只有在用户已知情接受时才允许（令牌会交给代理）。
      privateAccelAccepted: current.accelPrivateRepoAccepted,
    );
    if (candidates.first != rawUrl) {
      // 走加速。
      //
      // ★ 私有仓库加速时**必须带令牌**：raw 匿名 404，代理没有令牌同样取不到
      //   （实测：代理会原样转发 Authorization 头）。这正是用户在那道 3 秒
      //   警告里被告知、并显式接受的那件事。
      //   公开仓库则相反 —— 一个头都不带，代理没必要也不需要令牌。
      return (
        urls: candidates,
        headers: repoPrivate
            ? await downloadAuthHeaders()
            : const <String, String>{},
      );
    }
    final String apiUrl = 'https://api.github.com/repos/$fullName/contents/'
        '$encodedPath?ref=${Uri.encodeComponent(branch)}';
    return (
      urls: <String>[apiUrl],
      headers: <String, String>{
        ...await downloadAuthHeaders(),
        'accept': 'application/vnd.github.raw',
      },
    );
  }

  /// 仓库文件是否会走加速（供界面如实说明当前取法）。
  ///
  /// 与 [ogLAccelCandidates] 的 raw 族规则保持一致：有**自定义通道**，且
  /// （公开仓库）或（私有仓库且用户已知情接受），大小未知或超过阈值。
  bool repoFileAccelerated({
    required bool repoPrivate,
    int? size,
    OgLAccelScope scope = OgLAccelScope.repoFile,
  }) {
    final OgLSettings current = settings.settings;
    final bool privateOk = !repoPrivate || current.accelPrivateRepoAccepted;
    // v6.4.3：不再有"内置通道"这一概念；有自建通道、协议在有效期、且**该类资源
    // 的适用范围开着**才加速。私有仓库还需用户知情接受。
    return current.accelPrefixesFor(scope).isNotEmpty &&
        privateOk &&
        (size == null || size > kOgLAccelMinBytes);
  }

  // ── 下载能力（交互层**通过桥取用**，不接触逻辑层的管理器实现）──────────

  /// 下载状态监听（任务增删 / 进度变化）。
  Listenable get downloadsListenable => domain.downloads;

  /// 全部下载任务快照。
  List<IxDownloadTask> get downloadTasks => domain.downloads.tasks;

  /// 下载后端是否支持**暂停 / 继续**（Web = `false`，页面据此隐藏这两个按钮）。
  bool get supportsPauseResume => domain.downloads.supportsPauseResume;

  /// 清除已完成任务。
  void clearFinishedDownloads() => domain.downloads.clearFinished();

  /// 暂停某个下载。
  Future<void> pauseDownload(String id) => domain.downloads.pause(id);

  /// 继续某个下载。
  Future<void> resumeDownload(String id) => domain.downloads.resume(id);

  /// 重试某个失败下载。
  Future<void> retryDownload(String id) => domain.downloads.retry(id);

  /// 取消某个下载。
  Future<void> cancelDownload(String id) => domain.downloads.cancel(id);

  /// 从列表移除某个下载记录。
  Future<void> removeDownload(String id) => domain.downloads.remove(id);

  /// 设置下载并发连接数（非法档位由 `settings` 回落默认）。
  Future<void> setDownloadConnections(int value) =>
      settings.setDownloadConnections(value);

  /// AI 助手是否启用（设置页 / 客户端 tab 入口 / AI 子页都按它判可见性）。
  ///
  /// 数据源是 AI 设置（`AiSettings.enabled` + provider + 模型），不现造：
  /// `domain.ai.settings()` 已存在；新增的 `hasAi` 只是把"读一次"封装成
  /// 一个**同步可见**的派生属性 —— 之前各页面都是各读各的 Future，UI
  /// 重建节奏也各走各的。
  ///
  /// 缓存策略：构造时读一次，结果写进 [_cachedHasAi]。后续页面要"立刻
  /// 跟上"AI 开关的变更，就调一次 [refreshAi];失败时保留旧值（不是 false）。
  bool _cachedHasAi = false;

  /// 读 AI 当前是否启用（页面进入时一次性调用即可）。
  Future<bool> hasAi() async {
    try {
      // 类型化读取（`AiSettings` 经 `types.dart` 导出）：不要用 dynamic +
      // `is Object` 的写法 —— 后者会把 `enabled` 的静态解析打断，编译期直接报
      // "The getter 'enabled' isn't defined for the type 'Object'"。
      final AiSettings s = await domain.ai.settings();
      _cachedHasAi = s.enabled;
    } catch (_) {
      // 读不到就保留旧值：hasAi 是"该不该让用户看到 AI 入口"的开关，
      // 读失败不该让入口从屏幕上消失。
    }
    return _cachedHasAi;
  }

  /// 当前缓存值（同步版本；用于 build 里就近决定要不要渲染 AI 入口）。
  bool get hasAiCached => _cachedHasAi;

  /// 刷新缓存（在 AI 设置保存后调用，例如设置页 / AI 子页写完时）。
  Future<void> refreshAi() => hasAi();

  /// 仓库文件操作服务（统一文件操作入口）。
  RepoFileService get repoFiles => domain.repoFiles;

  /// 切换界面语言：先落盘设置，再加载对应语言分片。
  ///
  /// 非法代码由 `settings.setLanguage` 回落 `zh`；加载失败由 i18n 内部兜底英文。
  Future<void> setLanguage(String code) async {
    await settings.setLanguage(code);
    await OgLI18n.instance.load(settings.settings.languageCode);
  }

  /// 解析明暗：用户偏好优先，`system` 时跟随系统。
  Brightness brightnessFor(Brightness systemBrightness) =>
      switch (settings.settings.mode) {
        OgLThemeMode.light => Brightness.light,
        OgLThemeMode.dark => Brightness.dark,
        OgLThemeMode.system => systemBrightness,
      };

  /// 按当前设置编译主题（全应用唯一的一次编译）。
  /// 主题缓存键（三者任一变化才重算）。
  Brightness? _themeCacheBrightness;
  String? _themeCacheSeed;
  String? _themeCacheDensity;
  int? _themeCacheMotion;
  ThemeData? _themeCache;

  /// 当前主题（**带缓存**）。
  ///
  /// `ThemeData` 构造不便宜，而每次设置 / 语言 / 通知变化都会走到这里；
  /// 键不变就复用同一实例——顺带让 `AnimatedTheme` 不再把"等价主题"当成变化。
  /// [motionLevel] 参与缓存键，因为过渡主题随档位变化。
  ThemeData themeFor(Brightness systemBrightness, {int motionLevel = 1}) {
    final OgLSettings current = settings.settings;
    final Brightness brightness = brightnessFor(systemBrightness);
    final String seed = current.seedColorId;
    final String density = current.density;
    final ThemeData? cached = _themeCache;
    if (cached != null &&
        _themeCacheBrightness == brightness &&
        _themeCacheSeed == seed &&
        _themeCacheDensity == density &&
        _themeCacheMotion == motionLevel) {
      return cached;
    }
    final ThemeData built = buildOgLTheme(
      brightness,
      seedColor: ogLSeedColorOf(seed),
      density: ogLDensityOf(density),
    ).copyWith(
      pageTransitionsTheme: OgLMotion.pageTransitions(motionLevel),
      // ExpansionTile（关于页的诊断折叠组等）也接**动效档位**：
      // 时长 / 曲线与整页动效同源（档位 0 → 零时长，即"立即展开"）。
      expansionTileTheme: ExpansionTileThemeData(
        expansionAnimationStyle: AnimationStyle(
          duration: OgLOAnimQuality.of(motionLevel).medium,
          curve: OgLOAnimQuality.of(motionLevel).curve,
        ),
      ),
    );
    _themeCache = built;
    _themeCacheBrightness = brightness;
    _themeCacheSeed = seed;
    _themeCacheDensity = density;
    _themeCacheMotion = motionLevel;
    return built;
  }

  @override
  String toString() => 'SurfaceBridge(mode=${settings.settings.mode.name}, '
      'dns=${settings.settings.dnsMode})';
}

/// 用 L1 的 KV 实现设置持久化（**唯一**允许把 L3 的存储需求接到 L1 的地方）。
class KvSettingsPersistence implements OgLSettingsPersistence {
  /// 创建。
  const KvSettingsPersistence(this._kv,
      {this.key = OgLSettingsController.storageKey});

  final DiskKv _kv;

  /// 存储键。
  final String key;

  @override
  Future<String?> read() => _kv.read(key);

  @override
  Future<void> write(String raw) => _kv.write(key, raw);

  @override
  Future<void> clear() => _kv.remove(key);
}

/// 展示层模块（`surface.layer`）。
///
/// 依赖 `domain.layer`：展示层**永远**通过中枢层拿业务数据，
/// 不允许自己去碰 API。
class SurfaceLayerModule extends OgLModule {
  /// 装配出的桥（[onRegister] 后可用）。
  late final SurfaceBridge bridge;

  /// 设置控制器（UI 根节点监听它来重建主题）。
  late final OgLSettingsController settings;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'surface.layer',
        layer: ModuleLayer.surface,
        version: '0.2.0',
        requires: <String>['domain.layer'],
        provides: <String>['surface.bridge'],
        description: '展示·Material3 页面/主题/设置 的装配入口',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final BaseBridge base = BaseBridge.of(context.bridges);

    settings = OgLSettingsController(
      persistence: KvSettingsPersistence(base.disk.kv),
    );
    // 设置读取失败也必须让应用起来（load 内部已兜底，这里再包一层是双保险）。
    await settings.load();
    // 把持久化的 DNS 选择应用到网络底座（策略为可变设计，即刻生效）。
    final OgLSettings persisted = settings.settings;
    base.net.applyDnsSelection(
      custom: persisted.dnsMode == 'custom',
      serverId: persisted.dnsServerId,
      preferDoh: persisted.dnsPreferDoh,
    );
    // i18n：按持久化语言加载 JSON 分片（英文基线 + 当前语言）。
    // **失败不阻断启动**：i18n 内部兜底英文/键名。
    await OgLI18n.instance.load(persisted.languageCode);

    bridge = SurfaceBridge(
      settings: settings,
      domain: DomainBridge.of(context.bridges),
      net: base.net,
      cache: base.disk.cache,
      storageProbe: _probeStorage,
      // 界面偏好（分组展开状态）走同一套 KV：与设置数据分开存，
      // 但共用"底座可替换"的唯一入口。
      uiPrefs: base.disk.kv,
    );
    context.bridges.register(ModuleLayer.surface.key, bridge);

    context.diagnostics.info(
      'SURFACE',
      '展示层地基就绪',
      code: 'OGL-SURFACE-001',
      data: <String, Object?>{
        'framework': 'material3',
        'settingsLoaded': settings.isLoaded,
        'settingsError': settings.lastError != null,
      },
    );
  }

  @override
  Future<void> onStart() async {
    // 展示层没有后台任务：它的"启动"就是设置加载完成（上一步已完成）。
  }
}

/// 组装 L3 全部模块（供 `main` 一行接入，与 L1/L2 的装配入口保持同构）。
///
/// **只暴露一个模块**：展示层的所有能力都从 [SurfaceBridge] 出去，
/// 不像 L1/L2 那样需要按子系统拆分——因为 UI 本来就是"一张皮"。
List<OgLModule> surfaceLayerModules() => <OgLModule>[
      SurfaceLayerModule(),
    ];

/// 存储探针：**按三档方案裁决**「用户拿不拿得到文件」。
///
/// 三个关键点（此前踩过的坑）：
/// 1. **先让根目录缓存失效**：权限可能在本次会话里刚变（用户去系统设置授权后
///    返回），缓存不清就会一直卡在旧位置——"就算给了所有文件权限，也还是
///    优先用内部存储"。
/// 2. **判的是"用户可见"，不是"能不能写"**：应用私有目录（内部存储 /
///    `Android/data`）一定写得动，但它们**用户看不到**。
/// 3. **①②算过、③不过**：公共目录 ✅ / SAF 文件夹 ✅ / 应用内部 ⚠️
///    （如实报告"不过"，但**不阻断**——功能照常）。
///
/// ## 平台差异在哪
/// 实现细节按平台收敛在底座（`base/disk/app_dirs_fs_io.dart`），
/// 展示层里**一个 `dart:io` 都不需要**。
Future<bool> _probeStorage() async {
  OgLAppDirs.invalidate();
  try {
    final OgLStoragePlan plan = await OgLStorage.plan();
    if (!plan.userVisible) {
      return false;
    }
    // SAF 档：真正可见的是用户**自己授权**的那个文件夹（`plan.root` 只是
    // 应用内的回退路径），其可写性由系统授权保证 → 用该档位本身作答。
    if (plan.mode == OgLStorageMode.safDir) {
      return true;
    }
    // 其余档位：对**用户可见的公共目录**做一次真实写入探针
    // （底座实现：建目录 → 写入 → 删除）。
    return await OgLAppDirs.publicWritable();
  } catch (_) {
    return false;
  }
}
