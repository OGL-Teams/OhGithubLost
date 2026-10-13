/// L1 底座级 · DNS 策略测试（报文编解码 / DoH / 缓存 / 竞速 / 回退）。
///
/// **全部离线**：UDP 通道与 DoH 的 HTTP 能力都是注入的抽象，
/// 因此这里连一个字节都不会真正发到网络上。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/net_dns.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

/// 一份手工构造的合法响应：`a.com → 1.2.3.4`（含压缩指针）。
const List<int> _cannedResponse = <int>[
  0x12,
  0x34,
  0x81,
  0x80,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x61,
  0x03,
  0x63,
  0x6F,
  0x6D,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0xC0,
  0x0C,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x3C,
  0x00,
  0x04,
  0x01,
  0x02,
  0x03,
  0x04,
];

/// 固定应答的 UDP 通道。
class _FakeUdpChannel implements DnsUdpChannel {
  _FakeUdpChannel({this.response, this.silent = false});

  final List<int>? response;
  final bool silent;
  int calls = 0;
  String? lastServerIp;
  List<int>? lastQuery;

  @override
  Future<List<int>?> exchange(
    String serverIp,
    List<int> query, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    calls++;
    lastServerIp = serverIp;
    lastQuery = query;
    if (silent || response == null) {
      return null;
    }
    // 真实服务器会把请求的事务 ID 原样回填到响应头部——
    // 假通道必须模仿这一点，否则测的是"假实现"而不是"真逻辑"。
    final patched = List<int>.of(response!);
    if (query.length >= 2) {
      patched[0] = query[0];
      patched[1] = query[1];
    }
    return patched;
  }
}

/// 可控解析器。
class _FakeResolver implements DnsResolver {
  _FakeResolver({
    required this.id,
    this.addresses = const <String>['9.9.9.9'],
    this.error,
    this.delay = Duration.zero,
  });

  @override
  final String id;
  final List<String> addresses;
  final Object? error;
  final Duration delay;
  int calls = 0;

  @override
  Future<List<String>> resolve(String host) async {
    calls++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return addresses;
  }
}

void main() {
  group('内置 DNS 服务商', () {
    test('五家齐全且地址正确', () {
      expect(builtinDnsServers.length, 5);
      final byId = <String, DnsServer>{
        for (final server in builtinDnsServers) server.id: server,
      };
      expect(
          byId.keys,
          containsAll(<String>[
            'alidns',
            'dnspod',
            'dns114',
            'cloudflare',
            'google',
          ]));
      expect(byId['alidns']!.ip, '223.5.5.5');
      expect(byId['dnspod']!.ip, '119.29.29.29');
      expect(byId['dns114']!.ip, '114.114.114.114');
      expect(byId['cloudflare']!.ip, '1.1.1.1');
      expect(byId['google']!.ip, '8.8.8.8');

      // 国内三家排在最前，符合"受污染网络下优先可达"的默认排序。
      expect(
        builtinDnsServers.take(3).map((DnsServer s) => s.region),
        everyElement('cn'),
      );
    });

    test('114 只支持明文（不虚构 DoH 端点）', () {
      final dns114 = builtinDnsServers
          .firstWhere((DnsServer server) => server.id == 'dns114');
      expect(dns114.supportsDoh, isFalse);
      expect(
        builtinDnsServers
            .where((DnsServer server) => server.supportsDoh)
            .length,
        4,
      );
    });
  });

  group('DNS 报文编解码（RFC 1035）', () {
    test('构造查询报文（字节级断言）', () {
      final query = DnsWireCodec.buildQuery('a.com', id: 0x1234);
      expect(query, <int>[
        0x12, 0x34, // 事务 ID
        0x01, 0x00, // RD=1
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x61, 0x03, 0x63, 0x6F, 0x6D, 0x00, // a.com
        0x00, 0x01, 0x00, 0x01, // A / IN
      ]);
    });

    test('解析响应（含压缩指针）', () {
      expect(
        DnsWireCodec.parseAnswers(_cannedResponse, expectId: 0x1234),
        <String>['1.2.3.4'],
      );
    });

    test('事务 ID 不匹配一律拒绝（防伪造响应）', () {
      expect(
        () => DnsWireCodec.parseAnswers(_cannedResponse, expectId: 0xFFFF),
        throwsA(isA<DnsException>()),
      );
    });

    test('拒绝非响应报文与过短报文', () {
      final notResponse = List<int>.of(_cannedResponse);
      notResponse[2] = 0x01; // 清掉 QR 位
      expect(
        () => DnsWireCodec.parseAnswers(notResponse),
        throwsA(isA<DnsException>()),
      );
      expect(
        () => DnsWireCodec.parseAnswers(<int>[0, 1, 2]),
        throwsA(isA<DnsException>()),
      );
    });

    test('错误码会抛出（NXDOMAIN=3）', () {
      final broken = List<int>.of(_cannedResponse);
      broken[3] = 0x83; // rcode=3
      expect(
        () => DnsWireCodec.parseAnswers(broken),
        throwsA(isA<DnsException>()),
      );
    });
  });

  group('明文 UDP 解析器', () {
    test('成功解析并带上事务 ID', () async {
      final channel = _FakeUdpChannel(response: _cannedResponse);
      final resolver = UdpDnsResolver(
        server: builtinDnsServers.first,
        channel: channel,
      );
      expect(await resolver.resolve('a.com'), <String>['1.2.3.4']);
      expect(channel.calls, 1);
      expect(channel.lastServerIp, '223.5.5.5');
    });

    test('通道超时（返回 null）→ 抛异常而不是返回空', () async {
      final resolver = UdpDnsResolver(
        server: builtinDnsServers.first,
        channel: _FakeUdpChannel(silent: true),
      );
      await expectLater(
        resolver.resolve('a.com'),
        throwsA(isA<DnsException>()),
      );
    });
  });

  group('DoH 解析器', () {
    test('解析合法 JSON 响应（只取 A 记录）', () {
      const body = '{"Status":0,"Answer":['
          '{"name":"a.com","type":5,"data":"alias.com"},'
          '{"name":"a.com","type":1,"data":"5.6.7.8"},'
          '{"name":"a.com","type":1,"data":"not-an-ip"}]}';
      expect(DohDnsResolver.parseDohJson(body), <String>['5.6.7.8']);
    });

    test('Status 非 0 → 抛异常', () {
      expect(
        () => DohDnsResolver.parseDohJson('{"Status":3}'),
        throwsA(isA<DnsException>()),
      );
    });

    test('非法 JSON → 抛异常', () {
      expect(
        () => DohDnsResolver.parseDohJson('<html>502</html>'),
        throwsA(isA<DnsException>()),
      );
    });

    test('无 Answer 字段 → 返回空列表（不抛）', () {
      expect(DohDnsResolver.parseDohJson('{"Status":0}'), isEmpty);
    });
  });

  group('DNS 结果缓存', () {
    test('未过期命中，过期即失效', () {
      final cache = DnsCache();
      cache.put(
        'a.com',
        DnsAnswer(
          addresses: const <String>['1.1.1.1'],
          serverId: 'alidns',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );
      expect(cache.get('a.com')?.serverId, 'alidns');

      cache.put(
        'b.com',
        DnsAnswer(
          addresses: const <String>['2.2.2.2'],
          serverId: 'dnspod',
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      expect(cache.get('b.com'), isNull);
      expect(cache.size, 1, reason: '过期项应被顺手剔除');
    });

    test('超过上限时淘汰', () {
      final cache = DnsCache(maxEntries: 2);
      for (var index = 0; index < 5; index++) {
        cache.put(
          'h$index',
          DnsAnswer(
            addresses: <String>['1.1.1.$index'],
            serverId: 'x',
            expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          ),
        );
      }
      expect(cache.size, lessThanOrEqualTo(2));
    });
  });

  group('DNS 服务（策略）', () {
    test('system 模式：只走系统解析器', () async {
      final system = _FakeResolver(id: 'system');
      final service = DnsService(
        policy: DnsPolicy(),
        systemResolver: system,
        resolverFactory: (DnsServer server) =>
            _FakeResolver(id: server.id, addresses: const <String>['0.0.0.0']),
      );
      expect(await service.resolve('a.com'), <String>['9.9.9.9']);
      expect(system.calls, 1);
    });

    test('IP 字面量直接返回，不做查询', () async {
      final system = _FakeResolver(id: 'system');
      final service = DnsService(systemResolver: system);
      expect(await service.resolve('1.2.3.4'), <String>['1.2.3.4']);
      expect(system.calls, 0);
    });

    test('IPv6 字面量直返；`host:port` 不得被误判为 IP', () async {
      final system = _FakeResolver(id: 'system');
      final service = DnsService(systemResolver: system);

      expect(await service.resolve('::1'), <String>['::1']);
      expect(system.calls, 0, reason: 'IPv6 字面量无需解析');

      // 关键回归：'example.com:8080' 含冒号但**不是** IP，
      // 早期用 `contains(':')` 判断会把它当 IP 直接返回，
      // 于是"解析成功"了一个根本连不上的地址。
      expect(await service.resolve('example.com:8080'), <String>['9.9.9.9']);
      expect(system.calls, 1, reason: '带端口的主机名必须真正走解析');
    });

    test('custom 模式：命中缓存不重复解析', () async {
      final resolver = _FakeResolver(id: 'alidns');
      final service = DnsService(
        policy: DnsPolicy(mode: NetDnsMode.custom, raceServers: false),
        resolverFactory: (DnsServer server) => resolver,
      );
      await service.resolve('a.com');
      await service.resolve('a.com');
      expect(resolver.calls, 1, reason: '第二次应命中缓存');
    });

    test('custom 模式：顺序尝试，前一失败后一接手', () async {
      final service = DnsService(
        policy: DnsPolicy(
          mode: NetDnsMode.custom,
          raceServers: false,
          servers: builtinDnsServers.take(2).toList(),
        ),
        resolverFactory: (DnsServer server) => server.id == 'alidns'
            ? _FakeResolver(id: server.id, error: const DnsException('超时'))
            : _FakeResolver(
                id: server.id, addresses: const <String>['7.7.7.7']),
      );
      expect(await service.resolve('a.com'), <String>['7.7.7.7']);
    });

    test('custom 模式：并发竞速取最先成功者', () async {
      final service = DnsService(
        policy: DnsPolicy(
          mode: NetDnsMode.custom,
          raceServers: true,
          servers: builtinDnsServers.take(2).toList(),
        ),
        resolverFactory: (DnsServer server) => server.id == 'alidns'
            ? _FakeResolver(
                id: server.id,
                delay: const Duration(milliseconds: 50),
                addresses: const <String>['1.1.1.1'],
              )
            : _FakeResolver(
                id: server.id, addresses: const <String>['2.2.2.2']),
      );
      expect(await service.resolve('a.com'), <String>['2.2.2.2']);
    });

    test('custom 全部失败 → 回退系统解析，并记 warn（绝不静默）', () async {
      final diagnostics = KernelDiagnostics();
      final system =
          _FakeResolver(id: 'system', addresses: const <String>['3.3.3.3']);
      final service = DnsService(
        policy: DnsPolicy(mode: NetDnsMode.custom, raceServers: false),
        systemResolver: system,
        diagnostics: diagnostics,
        resolverFactory: (DnsServer server) =>
            _FakeResolver(id: server.id, error: const DnsException('全挂')),
      );

      expect(await service.resolve('a.com'), <String>['3.3.3.3']);
      expect(system.calls, 1);
      expect(
        diagnostics.logTail.any((entry) => entry.code == 'OGL-DNS-101'),
        isTrue,
        reason: '回退必须留痕',
      );
    });

    test('关闭回退后，失败直接抛出', () async {
      final service = DnsService(
        policy: DnsPolicy(
          mode: NetDnsMode.custom,
          raceServers: false,
          fallbackToSystem: false,
        ),
        resolverFactory: (DnsServer server) =>
            _FakeResolver(id: server.id, error: const DnsException('全挂')),
      );
      await expectLater(
        service.resolve('a.com'),
        throwsA(isA<DnsException>()),
      );
    });

    test('未配置任何服务器 → 抛异常（且不静默回落真实网络）', () async {
      final service = DnsService(
        policy: DnsPolicy(
          mode: NetDnsMode.custom,
          servers: <DnsServer>[],
          fallbackToSystem: false,
        ),
      );
      await expectLater(
        service.resolve('a.com'),
        throwsA(isA<DnsException>()),
      );
    });
  });

  group('DNS 自检项', () {
    test('成功时给出解析结果与当前策略', () async {
      final service = DnsService(
        policy: DnsPolicy(mode: NetDnsMode.custom, raceServers: false),
        systemResolver: _FakeResolver(id: 'system'),
        resolverFactory: (DnsServer server) =>
            _FakeResolver(id: server.id, addresses: const <String>['8.8.4.4']),
      );
      final result =
          await DnsProbe(service: service, sampleHost: 'a.com').run();
      expect(result.ok, isTrue);
      expect(result.summary, contains('8.8.4.4'));
      expect(result.detail?['mode'], 'custom');
      expect((result.detail?['servers'] as List<Object?>).length, 5);
    });

    test('失败时 ok=false 而不是抛异常（自检不得拖垮启动）', () async {
      final service = DnsService(
        policy: DnsPolicy(
          mode: NetDnsMode.custom,
          raceServers: false,
          fallbackToSystem: false,
        ),
        resolverFactory: (DnsServer server) =>
            _FakeResolver(id: server.id, error: const DnsException('全挂')),
      );
      final result =
          await DnsProbe(service: service, sampleHost: 'a.com').run();
      expect(result.ok, isFalse);
      expect(result.summary, contains('失败'));
    });

    test('id 与 title 稳定', () {
      final probe = DnsProbe(service: DnsService());
      expect(probe.id, 'base.net.dns');
      expect(probe.title, 'DNS 解析');
    });
  });

  group('策略摘要（必须让用户看得见）', () {
    test('system 模式摘要', () {
      final service = DnsService(policy: DnsPolicy());
      expect(service.policy.mode, NetDnsMode.system);
      expect(service.policy.servers.length, 5);
    });

    test('custom 模式摘要包含家数与特性', () {
      final service = DnsService(
        policy: DnsPolicy(mode: NetDnsMode.custom, preferDoh: true),
      );
      expect(service.policy.toString(), contains('custom'));
      expect(service.policy.servers.length, 5);
    });
  });
}
