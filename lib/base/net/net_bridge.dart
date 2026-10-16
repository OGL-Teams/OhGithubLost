/// L1 底座级 · 网络连接：门面与模块装配。
///
/// [NetBridge] 是**本层对外唯一出口**：上层只认识它，不认识 HttpClient、
/// 不认识重试策略、更不认识镜像通道实现。
library;

import '../../kernel/contract/module.dart';
import 'io_net_transport.dart';
import 'net_dns.dart';
import 'net_mirror.dart';
import 'net_retry.dart';
import 'net_transport.dart';
import 'net_types.dart';

/// 网络连接门面。
class NetBridge {
  /// 创建门面。
  NetBridge({required this.transport, required this.observer, this.dns});

  /// 韧性传输（重试 + 镜像 + 观测）。
  final NetTransport transport;

  /// 观测器。
  final NetObserver observer;

  /// DNS 策略服务（`null` 表示只用系统解析）。
  final DnsService? dns;

  /// 当前 DNS 策略摘要（UI 必须向用户展示，不得让用户猜）。
  String get dnsSummary {
    final service = dns;
    if (service == null) {
      return '系统解析';
    }
    final policy = service.policy;
    // Web：浏览器不给裸 socket，自定义 DNS / DoH **不可能生效**。
    // 这里如实告诉用户，而不是展示一个切过去也毫无作用的开关。
    if (!service.supportsCustomDns) {
      return '系统解析（Web 浏览器不允许自定义 DNS）';
    }
    if (policy.mode == NetDnsMode.system) {
      return '系统解析';
    }
    return '${policy.servers.length} 家 DNS · '
        '${policy.preferDoh ? 'DoH 优先' : '明文'} · '
        '${policy.raceServers ? '并发竞速' : '顺序尝试'}';
  }

  /// 设置页：内置 DNS 服务器（id → 展示名）。
  Map<String, String> get dnsServerChoices => <String, String>{
        for (final server in builtinDnsServers)
          server.id: '${server.label} · ${server.ip}',
      };

  /// 设置页：应用 DNS 选择（策略对象为可变设计——即时生效）。
  ///
  /// ★ 真正的写入点是 [DnsService.applySelection]（它会**作废旧解析缓存**）。
  ///   早先这里直接改字段，缓存里的旧答案会照旧返回最多 TTL（5 分钟）——
  ///   用户看到的就是"设置改了却没生效"。
  void applyDnsSelection({
    required bool custom,
    required String serverId,
    required bool preferDoh,
    String customIp = '',
    String customDohUrl = '',
  }) {
    final service = dns;
    if (service == null) {
      return;
    }
    // ★ 自定义 DNS：用户在设置里填了 IP 就构造一个临时 DnsServer 传下去。
    //   DoH 端点必须是 `https://`（明文 HTTP 的 DoH 等于不设防），
    //   不合法就只走明文 UDP（`ogLIsUsableDohEndpoint` 做同一套判定）。
    final String ip = customIp.trim();
    final DnsServer? customServer = ip.isEmpty
        ? null
        : DnsServer(
            id: 'custom',
            label: '自定义',
            ip: ip,
            dohUrl: ogLIsUsableDohEndpoint(customDohUrl)
                ? customDohUrl.trim()
                : null,
          );
    service.applySelection(
      custom: custom,
      serverId: serverId,
      preferDoh: preferDoh,
      customServer: customServer,
    );
  }

  /// 发送请求。
  Future<NetResponse> send(NetRequest request) => transport.send(request);

  /// 便捷 GET（返回响应体文本；非 2xx 由调用方自行处理）。
  Future<NetResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? label,
  }) =>
      send(NetRequest(
        method: NetMethod.get,
        url: url,
        headers: headers,
        label: label,
      ));

  /// 当前网络统计。
  NetStats get stats => observer.snapshot();

  @override
  String toString() => 'NetBridge(${observer.snapshot()})';
}

/// 网络连接模块（`base.net`）。
///
/// 依赖：无（底座最底层）。
/// 提供：`net.transport`。
class NetModule extends OgLModule {
  /// 创建模块。
  ///
  /// [dns] 为 `null` 时会自动建一个**默认策略**的 [DnsService]
  /// （模式 = `system`，内置五家 DNS 已就绪，等用户在设置里选择）。
  /// 这样"内置 DNS"始终可用，而**默认行为与不加 DNS 完全一致**。
  ///
  /// ## 为什么默认就把 DoH 的 HTTP 能力装上
  /// 底座本体不 `import 'dart:io'`（它要能在任何平台编译），DoH 所需的
  /// HTTP 能力必须由装配层注入。此前没人注入 —— 于是设置里的
  /// 「DoH 优先」开着也**永远不会真的走 DoH**（默认工厂写死明文 UDP，
  /// `IoDnsHttpClient` 全项目没有任何使用点）。这里把它接上：
  /// 用户选的自定义 DNS + DoH 优先，才是它字面上的意思。
  NetModule({
    NetTransport? transport,
    NetObserver? observer,
    RetryPolicy policy = const RetryPolicy(),
    MirrorSelector? mirrors,
    NetTransport Function()? transportFactory,
    DnsService? dns,
  })  : _observer = observer ?? NetObserver(),
        _dns = dns ?? DnsService(dohClient: IoDnsHttpClient()),
        _explicit = transport {
    _policy = policy;
    _mirrors = mirrors ?? MirrorSelector();
    _factory = transportFactory;
  }

  final NetObserver _observer;
  final DnsService _dns;
  final NetTransport? _explicit;
  late final RetryPolicy _policy;
  late final MirrorSelector _mirrors;
  late final NetTransport Function()? _factory;

  /// 门面实例（[onRegister] 后可用）。
  late final NetBridge bridge;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'base.net',
        layer: ModuleLayer.base,
        version: '0.1.0',
        provides: <String>['net.transport', 'net.dns'],
        description: '底座·网络连接（传输 / 重试 / 观测 / DNS 策略）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    _dns.attachDiagnostics(context.diagnostics);

    final inner = _explicit ??
        _factory?.call() ??
        // 传输实现：dart:io 的 HttpClient（`io_net_transport.dart`）。
        createPlatformNetTransport(
          _dns,
          connectTimeout: const Duration(seconds: 15),
        );
    final transport = inner is ResilientTransport
        ? inner
        : ResilientTransport(
            inner: inner,
            policy: _policy,
            mirrors: _mirrors,
            observer: _observer,
          );

    bridge = NetBridge(transport: transport, observer: _observer, dns: _dns);

    context.di.register<NetBridge>(bridge);
    context.di.register<DnsService>(_dns);
    // 把 DNS 自检挂到内核自检表：启动报告里就能看到"当前用的是哪家 DNS"。
    context.probes?.register(_dns.probe());
    context.diagnostics.info(
      'NET',
      '网络连接就绪',
      code: 'OGL-NET-001',
      data: <String, Object?>{
        'policy': _policy.toString(),
        'mirrors': _mirrors.channels.length,
        'dns': bridge.dnsSummary,
        'syslog': 'DNS 策略可随时切换，不重建传输层',
      },
    );
  }
}
