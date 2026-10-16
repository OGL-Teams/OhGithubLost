/// L2 中枢级 · 层桥与模块装配。
///
/// ## 这一层最重要的三根线
/// 1. **`base.disk.cache ↔ GhApi`**：把底座的一致性引擎（D1–D10）接到真实
///    GitHub API 上。**没有这根线，D1–D7 就是空转**——它必须在这里、
///    且只在这里接。
/// 2. **`NetBridge ↔ IxTaskRunner`**：批量任务选了"直连/镜像/自动"，
///    必须在第一个请求之前落到镜像选择器上。
/// 3. **`kernel.probes`**：各层把自己的自检项挂上去，启动报告才看得见全貌。
library;

import 'dart:async';

import '../base/base_bridge.dart';
import '../base/disk/og_l_storage.dart';
import '../base/net/ai_http_client_web.dart';
import '../base/net/net_bridge.dart';
import '../base/net/net_transport.dart';
import '../base/net/range_download.dart';
import '../kernel/bridge_registry.dart';
import '../kernel/contract/module.dart';
import '../kernel/contract/storage_export.dart';
import '../kernel/environment.dart';
import 'ai/ai_service.dart';
import 'ai/ai_tools.dart';
import 'gh/gh_api.dart';
import 'gh/gh_auth.dart';
import 'gh/gh_client.dart';
import 'gh/gh_read_cache.dart';
import 'gh/repo_file_service.dart';
import 'ix/ix_action_logs.dart';
import 'ix/ix_download.dart';
import 'ix/ix_notify.dart';
import 'ix/ix_presign.dart';
import 'ix/ix_session.dart';
import 'ix/ix_task.dart';
import 'sys/sys_access.dart';
import 'sys/sys_info.dart';

/// 中枢层桥（L2 唯一出口）。
class DomainBridge {
  /// 创建桥。
  DomainBridge({
    required this.auth,
    required this.api,
    required this.client,
    required this.session,
    required this.tasks,
    required this.notifications,
    required this.sysInfo,
    required this.sysAccess,
    required this.ai,
    IxDownloadManager? downloads,
    IxActionLogs? actionLogs,
    IxPresign? presign,
    RepoFileService? repoFiles,
  })  : downloads = downloads ?? IxDownloadManager(),
        actionLogs =
            actionLogs ?? IxActionLogs(tokenProvider: () async => null),
        presign = presign ?? IxPresign(tokenProvider: () async => null),
        _repoFiles = repoFiles ?? RepoFileService(api: api);

  /// 认证（多账号 / 令牌）。
  final GhAuthService auth;

  /// GitHub 端点封装（同时是底座的 `CacheRemote`）。
  final GhApi api;

  /// 请求客户端（限流 / 并发 / 分页）。
  final GhClient client;

  /// 会话（上下文 + 偏好）。
  final IxSession session;

  /// 批量任务运行器（**强制先确认**）。
  final IxTaskRunner tasks;

  /// 通知中心。
  final IxNotificationCenter notifications;

  /// 本地深层信息。
  final SysInfoService sysInfo;

  /// Mod 能力守门。
  final SysAccessGuard sysAccess;

  /// AI 助手（会话 / 设置 / 补全编排；密钥走 vault）。
  final AiService ai;

  /// 内建下载管理器。
  final IxDownloadManager downloads;

  /// Actions 运行日志服务。
  final IxActionLogs actionLogs;

  /// 第一跳解析（把需认证的地址换成短期签名地址；**令牌不出设备**）。
  final IxPresign presign;

  /// 仓库文件操作服务（create / delete / rename / copy / batch）。
  final RepoFileService _repoFiles;

  /// 仓库文件操作服务（**统一文件操作入口**：移动 / 复制 / 批量，逐项明细 + 进度）。
  RepoFileService get repoFiles => _repoFiles;

  /// 从内核桥表解析中枢桥（展示层的标准取用方式）。
  static DomainBridge of(KernelBridgeRegistry bridges) =>
      bridges.resolve<DomainBridge>(ModuleLayer.domain.key);

  @override
  String toString() =>
      'DomainBridge(account=${session.account?.login ?? '未登录'}, '
      'repo=${session.context.repo ?? '-'})';
}

/// GitHub 中枢模块（`domain.gh`）。
///
/// 依赖：`base.layer`（拿底座桥）。
/// 提供：`gh.auth` / `gh.client` / `gh.api`。
class GhModule extends OgLModule {
  /// 创建模块。
  GhModule({
    this.maxConcurrent = 4,
    this.baseUrl = 'https://api.github.com',
  });

  /// 请求并发上限。
  final int maxConcurrent;

  /// API 根。
  final String baseUrl;

  /// 装配出的服务（[onRegister] 后可用）。
  late final GhAuthService auth;
  late final GhClient client;
  late final GhApi api;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'domain.gh',
        layer: ModuleLayer.domain,
        version: '0.1.0',
        requires: <String>['base.layer'],
        provides: <String>['gh.auth', 'gh.client', 'gh.api'],
        description: '中枢·API 逻辑（认证 / 请求 / 端点封装 / CacheRemote 适配）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final base = BaseBridge.of(context.bridges);

    auth = GhAuthService(
      vault: base.disk.vault,
      store: base.disk.kv,
      diagnostics: context.diagnostics,
    );
    client = GhClient(
      net: base.net,
      auth: auth,
      baseUrl: baseUrl,
      maxConcurrent: maxConcurrent,
      diagnostics: context.diagnostics,
    );
    api = GhApi(client: client);

    // ── 关键接线：一致性引擎 ← 真实 API ──
    // 绑定之后，D1–D10 的每一次读写都会落到 GitHub 上。
    base.disk.cache.bindRemote(api);

    // ★ 反向接线（此前缺失，导致 D1–D7 空转）：
    // 让 API 的**读取路径**走底座缓存（目录列表 / 文件内容），
    // 写入路径经 `putContentLocked` 走缓存的 D1–D7。
    // 账号维度用于多用户隔离（未登录用 `guest`）。
    api.attachReadCache(
      base.disk.cache,
      accountId: () async => (await auth.activeAccountId()) ?? 'guest',
    );

    // ★ R4：只读端点缓存（releases / branches / commits / issues / pulls /
    //   Actions / 仓库详情 …）。与底座一致性缓存互补：前者面向文件内容，
    //   这里面向"可容忍短暂陈旧的只读列表 / 详情"，账号维度隔离，切号即清。
    client.attachReadCache(GhReadCache(
      store: base.disk.kv,
      accountId: () async => (await auth.activeAccountId()) ?? 'guest',
      diagnostics: context.diagnostics,
    ));

    // ★ 失败写入重放（D8）：把上次中断的写入在启动后补做。
    // 只依赖磁盘上的提交日志，失败不阻断启动（记录后照常进入界面）。
    unawaited(
      base.disk.cache.replayPending().then((outcomes) {
        final int ok = outcomes.where((o) => o.ok).length;
        context.diagnostics.info(
          'CONS',
          '失败写入重放完成',
          code: 'OGL-CONS-REPLAY',
          data: <String, Object?>{
            'replayed': outcomes.length,
            'succeeded': ok,
          },
        );
      }).catchError((Object error) {
        context.diagnostics.warn(
          'CONS',
          '失败写入重放异常：$error',
          code: 'OGL-CONS-REPLAY-ERR',
        );
      }),
    );

    context.di.register<GhAuthService>(auth);
    context.di.register<GhClient>(client);
    context.di.register<GhApi>(api);
    context.diagnostics.info(
      'GH',
      'API 逻辑就绪',
      code: 'OGL-GH-001',
      data: <String, Object?>{
        'baseUrl': baseUrl,
        'maxConcurrent': maxConcurrent,
        'cacheBound': true,
      },
    );
  }
}

/// 本地信息模块（`domain.sys`）。
///
/// 依赖：`base.layer`。
/// 提供：`sys.info` / `sys.access`。
class SysModule extends OgLModule {
  /// 创建模块。
  SysModule({
    AndroidProbe? androidProbe,
    AppProbe? appProbe,
    MemoryProbe? memoryProbe,
    SysNetworkSource? networkSource,
    bool installDefaultAppProbe = true,
  })  : _androidProbe = androidProbe,
        _appProbe = appProbe,
        _memoryProbe = memoryProbe,
        _networkSource = networkSource,
        _installDefaultAppProbe = installDefaultAppProbe;

  final AndroidProbe? _androidProbe;
  final AppProbe? _appProbe;
  final MemoryProbe? _memoryProbe;
  final SysNetworkSource? _networkSource;
  final bool _installDefaultAppProbe;

  /// 装配出的服务。
  late final SysInfoService info;
  late final SysAccessGuard access;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'domain.sys',
        layer: ModuleLayer.domain,
        version: '0.1.0',
        requires: <String>['base.layer'],
        provides: <String>['sys.info', 'sys.access'],
        description: '中枢·本地深层信息（设备/应用/环境）与 Mod 能力守门',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final base = BaseBridge.of(context.bridges);

    // 网络状态由底座推导，不另开探测路径。
    final networkSource = _networkSource ?? _BridgeNetworkSource(base.net);

    info = SysInfoService(
      androidProbe: _androidProbe,
      appProbe: _appProbe,
      memoryProbe: _memoryProbe,
      networkSource: networkSource,
      diagnostics: context.diagnostics,
    );
    access = SysAccessGuard(
      store: base.disk.kv,
      diagnostics: context.diagnostics,
    );

    context.di.register<SysInfoService>(info);
    context.di.register<SysAccessGuard>(access);
    context.probes?.register(_SysEnvProbe(info));
    context.diagnostics.info(
      'SYS',
      '本地信息就绪',
      code: 'OGL-SYS-001',
      data: <String, Object?>{
        'dns': base.net.dnsSummary,
        'customMemoryProbe': _memoryProbe != null,
      },
    );
  }

  /// 是否装入了默认的应用信息探测（真机装配层用 package_info_plus）。
  bool get hasDefaultAppProbe => _installDefaultAppProbe;
}

/// 交互模块（`domain.ix`）。
///
/// 依赖：`domain.gh` / `domain.sys`。
/// 提供：`ix.session` / `ix.task` / `ix.notify`。
class IxModule extends OgLModule {
  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'domain.ix',
        layer: ModuleLayer.domain,
        version: '0.1.0',
        requires: <String>['domain.gh', 'domain.sys'],
        provides: <String>['ix.session', 'ix.task', 'ix.notify', 'ix.download'],
        description: '中枢·交互逻辑（会话 / 批量任务 / 冲突编排 / 通知 / 下载）',
      );

  /// 装配出的服务。
  late final IxSession session;
  late final IxTaskRunner tasks;
  late final IxNotificationCenter notifications;
  late final IxDownloadManager downloads;
  late final IxActionLogs actionLogs;
  late final IxPresign presign;

  @override
  Future<void> onRegister(KernelContext context) async {
    final base = BaseBridge.of(context.bridges);
    final auth = context.di.resolve<GhAuthService>();

    session = IxSession(
      auth: auth,
      store: base.disk.kv,
      diagnostics: context.diagnostics,
    );
    // ★ 通道落地：把「直连 / 自动 / 指定镜像」真正作用到网络底座的镜像选择器上。
    // 没有这一段，"批量必须让用户选通道"就只是 UI 上的一句空话。
    tasks = IxTaskRunner(
      diagnostics: context.diagnostics,
      channelApplier: buildChannelApplier(base.net),
    );
    notifications = IxNotificationCenter();
    downloads = IxDownloadManager(
      diagnostics: context.diagnostics,
      // 多连接分片引擎（硬件层实现，逻辑层只认契约）。
      engine: OgLRangeDownloader(),
      // 成品导出（存储②档：把成品粘贴到用户选的 SAF 文件夹）。
      storageExporter: const _OgLStorageExporter(),
      // ★ 落盘目录裁决器（装配根注入，逻辑层只认函数签名）：
      //   返回的目录 = 「存储方案实际写入位置」/download。
      //   ① 公共目录档时即 /storage/emulated/0/ogl/download——
      //   下载**直接写进用户可见的 ogl 目录**（旧实现写死应用私有目录，
      //   用户"拿到了 ogl 权限却永远看不到文件"，还要靠打开 file:// 失败
      //   才发现文件根本不在那）。② SAF 档照旧私有 + 完成后导出；
      //   ③ 内部档维持私有。后端拿不到裁决（null）时回退私有目录，绝不阻塞下载。
      downloadDirProvider: () async =>
          '${(await OgLStorage.plan()).root}/download',
    );
    actionLogs = IxActionLogs(
      tokenProvider: () async => (await auth.activeToken())?.value,
    );
    presign = IxPresign(
      tokenProvider: () async => (await auth.activeToken())?.value,
    );

    context.di.register<IxSession>(session);
    context.di.register<IxTaskRunner>(tasks);
    context.di.register<IxNotificationCenter>(notifications);
    context.di.register<IxDownloadManager>(downloads);
    context.di.register<IxActionLogs>(actionLogs);
    context.di.register<IxPresign>(presign);
    context.diagnostics.info(
      'IX',
      '交互逻辑就绪',
      code: 'OGL-IX-001',
      data: <String, Object?>{
        'channelOptions': IxChannel.values.length,
        'batchConfirmRequired': true,
        'channelWired': tasks.hasChannelApplier,
        'downloader': '多连接分块（并发数见设置）',
      },
    );
  }

  @override
  Future<void> onStart() async {
    // 恢复上次会话（上下文 + 偏好），失败不影响启动。
    await session.restore();
  }
}

/// 中枢层装配模块（`domain.layer`）。
///
/// 依赖：`domain.gh` / `domain.ix` / `domain.sys`。
/// 提供：`domain.bridge`。
class DomainLayerModule extends OgLModule {
  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'domain.layer',
        layer: ModuleLayer.domain,
        version: '0.1.0',
        requires: <String>['domain.gh', 'domain.ix', 'domain.sys'],
        provides: <String>['domain.bridge'],
        description: '中枢·层桥装配（API 逻辑 + 交互逻辑 → 单一出口）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    // 第一跳解析（presign）需要**当前账号的令牌**：从认证服务实时取；
    // 未登录时返回 `null`（公开资源照样能拿到签名地址，只是不带 Authorization）。
    final ghAuth = context.di.resolve<GhAuthService>();
    // ★ 仓库文件操作服务：create / delete / rename / copy / batch 的统一入口。
    //   注册进 DI（后续模块可直接解析），并挂到中枢桥（展示层经
    //   `surface_bridge` 的转发取用；转发由后续相位补上）。
    final RepoFileService repoFiles = RepoFileService(
      api: context.di.resolve<GhApi>(),
      diagnostics: context.diagnostics,
    );
    context.di.register<RepoFileService>(repoFiles);

    // ── AI 助手：依赖经抽象注入（DiskKv / DiskVault / AiHttpClient）。
    //    工具注册表暂时为空——GitHub 操作工具（建 Issue / 读文件 / 建 PR …）
    //    在后续相位由 `domain/gh` 的只读/受控工具逐项接入。
    final base = BaseBridge.of(context.bridges);
    final AiService ai = AiService(
      store: base.disk.kv,
      vault: base.disk.vault,
      // Web 的 AiHttpClientWeb 构造会创建 http.Client()，因此不能 const。
      http: AiHttpClientWeb(),
      tools: buildAiTools(context.di.resolve<GhApi>()),
    );
    context.di.register<AiService>(ai);

    final bridge = DomainBridge(
      auth: ghAuth,
      api: context.di.resolve<GhApi>(),
      client: context.di.resolve<GhClient>(),
      session: context.di.resolve<IxSession>(),
      tasks: context.di.resolve<IxTaskRunner>(),
      notifications: context.di.resolve<IxNotificationCenter>(),
      sysInfo: context.di.resolve<SysInfoService>(),
      sysAccess: context.di.resolve<SysAccessGuard>(),
      ai: ai,
      downloads: context.di.resolve<IxDownloadManager>(),
      actionLogs: context.di.resolve<IxActionLogs>(),
      repoFiles: repoFiles,
      // 第一跳解析：此前**漏传**，DomainBridge 只能退回 `tokenProvider` 恒为
      // `null` 的兜底实例 —— 私有仓库的 Release 附件 / Action 产物因此拿不到
      // 签名地址。令牌在本地取用，不落到别处。
      presign: IxPresign(
        tokenProvider: () async => (await ghAuth.activeToken())?.value,
      ),
    );
    context.bridges.register(ModuleLayer.domain.key, bridge);
    context.diagnostics.info(
      'DOMAIN',
      '中枢桥已注册',
      code: 'OGL-DOMAIN-001',
      data: <String, Object?>{'layer': ModuleLayer.domain.key},
    );
  }
}

/// 组装 L2 全部模块（供 `main` 一行接入）。
List<OgLModule> domainLayerModules({
  GhModule? gh,
  SysModule? sys,
  IxModule? ix,
}) =>
    <OgLModule>[
      sys ?? SysModule(),
      gh ?? GhModule(),
      ix ?? IxModule(),
      DomainLayerModule(),
    ];

/// 把批量任务的通道选择**真正落到网络底座**上（装配层使用）。
///
/// 三种选择对应三种真实动作：
/// - `direct` → 停用全部镜像通道（真·直连）
/// - `auto`   → 启用全部通道（交给选择器按顺序 / 竞速挑）
/// - `mirror` → 只保留指定通道
///
/// 非 IO / 无镜像能力时静默跳过是可接受的：那本来就等价于"直连"。
IxChannelApplier buildChannelApplier(NetBridge net) {
  return (IxBatchDecision decision) async {
    final transport = net.transport;
    if (transport is! ResilientTransport) {
      return;
    }
    final mirrors = transport.mirrors;
    switch (decision.channel) {
      case IxChannel.direct:
        mirrors.setAllEnabled(false);
      case IxChannel.auto:
        mirrors.setAllEnabled(true);
      case IxChannel.mirror:
        mirrors.restrictTo(decision.mirrorId);
    }
  };
}

/// 把 `NetBridge` 的网络状态包装成 [SysNetworkSource]。
class _BridgeNetworkSource implements SysNetworkSource {
  _BridgeNetworkSource(this._net);

  final NetBridge _net;

  @override
  Future<SysNetworkInfo> collect() async {
    final stats = _net.stats;
    final transport = _net.transport;
    final mirrors = transport is ResilientTransport
        ? transport.mirrors.enabledIds
        : const <String>[];
    return SysNetworkInfo(
      dnsMode: _net.dns?.policy.mode.name ?? 'system',
      dnsSummary: _net.dnsSummary,
      mirrorChannels: mirrors,
      requests: stats.requests,
      failures: stats.failures,
      retries: stats.retries,
    );
  }
}

/// 设备/环境自检项。
class _SysEnvProbe implements KernelEnvironmentProbe {
  _SysEnvProbe(this._info);

  final SysInfoService _info;

  @override
  String get id => 'domain.sys.env';

  @override
  String get title => '运行环境';

  @override
  Future<KernelProbeResult> run() async {
    final runtime = _info.collectRuntime();
    return KernelProbeResult(
      ok: true,
      summary: '${runtime.localeName} · UTC${runtime.utcOffsetHoursText}',
      detail: runtime.toJson(),
    );
  }
}

/// 装配根提供的**成品导出**实现（逻辑层只认契约，硬件层干活）。
///
/// 存储②档（用户授权了 SAF 文件夹）时，把下载成品**粘贴**进该文件夹；
/// 其余档位返回 `false`（不需要导出）。**绝不抛出**。
class _OgLStorageExporter implements StorageExporter {
  /// 创建。
  const _OgLStorageExporter();

  @override
  Future<bool> export({
    required String localPath,
    required String fileName,
  }) async {
    try {
      final OgLStoragePlan plan = await OgLStorage.plan();
      if (plan.mode != OgLStorageMode.safDir) {
        return false;
      }
      return await OgLStorage.exportToSaf(
        localPath: localPath,
        fileName: fileName,
      );
    } catch (_) {
      return false;
    }
  }
}
