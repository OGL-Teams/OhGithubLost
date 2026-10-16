/// L1 底座级 · 网络连接：DNS 策略（系统解析 / 自定义 DNS）。
///
/// ## 为什么需要它
/// 在部分网络环境下，`api.github.com`、`raw.githubusercontent.com` 会被
/// **DNS 污染**（返回错误 IP，TCP 直接连不上），而 HTTPS 本身毫无问题。
/// 换一个可信解析器就能绕开——这就是本文件的全部意义。
///
/// ## 设计原则（能力冲突 → 交由用户选择）
/// - **两条路都要有**：`system`（交给操作系统，最省事）与
///   `custom`（自定义解析器，绕开污染）；
/// - **默认内置五家**：阿里 / 腾讯 / 114 / Cloudflare / Google；
/// - **绝不静默降级**：自定义解析失败会**回退系统解析**，但必须记日志，
///   并且自检项会把这个事实报出来；
/// - **不引入新依赖**：DoH 走底座自己的 HTTP 能力，明文 DNS 用
///   `RawDatagramSocket` 自己编码报文（RFC 1035，仅 A/AAAA）。
///
/// ## 测试友好
/// UDP 通道（[DnsUdpChannel]）与 DoH 的 HTTP 能力（[DnsHttpClient]）
/// 都是抽象接口——因此**整套策略逻辑可以在 CI 上完全离线断言**，
/// 包括报文编解码、缓存、回退与并发竞速。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../kernel/diagnostics.dart';
import '../../kernel/environment.dart';
import 'net_dns_platform_io.dart';

/// DNS 解析模式。
enum NetDnsMode {
  /// 交给操作系统（默认；不改动任何行为）。
  system,

  /// 使用自定义 DNS 服务器列表。
  custom,
}

/// DoH 端点是否**真的可用**：必须是 `https://` 且带主机名。
///
/// ## 为什么在底座层收口
/// 明文 HTTP 的 DoH 等于不设防——中间人既能改答、也能看到全部查询，
/// 用户以为换上了可信解析器，实际是被更彻底地劫持。所以这里只认 `https`：
/// `http://…`、空串、相对地址、没有协议的裸地址（`1.1.1.1`）一律判为**不可用**，
/// 由调用方回退到明文 UDP 或系统解析（**不谎称已启用 DoH**）。
bool ogLIsUsableDohEndpoint(String? url) {
  if (url == null) {
    return false;
  }
  final String trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.isAbsolute) {
    return false;
  }
  if (parsed.scheme.toLowerCase() != 'https') {
    return false;
  }
  return parsed.host.isNotEmpty;
}

/// 把"用户填写的 DNS 地址"规格化成**明文 UDP 用的裸 IP 字面量**。
///
/// ## 为什么需要它
/// [DnsServer.ip] 最终会被交给平台的 socket 层（`InternetAddress(...)`）。
/// 而它的来源不可信（粘贴、手误、从网页抄来的 `https://1.1.1.1/dns-query`），
/// 若不规格化，`https://…`、`1.1.1.1:53`、`[2606:4700::1111]` 这类字符串会在
/// socket 层抛出 `ArgumentError`，被上一层归类成"网络失败"——
/// 用户永远看不出是自己填错了地址。
///
/// 处理：剥协议前缀 → 去路径 / 查询 → 去 IPv6 方括号 → 去 IPv4 的 `:port`。
/// 返回 `null` = 不是合法 IP 字面量（空串也返回 `null`），调用方据此报
/// "地址不合法"并跳过该家（继续下一家 / 回退系统解析）。
String? ogLNormalizeDnsAddress(String raw) {
  String value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  // ① 协议前缀：`https://` / `udp://` / `dns://` …（任何 `xxx://` 都剥掉）。
  final int scheme = value.indexOf('://');
  if (scheme >= 0) {
    value = value.substring(scheme + 3);
  }
  // ② 路径 / 查询 / 片段：`1.1.1.1/dns-query?x=1` → `1.1.1.1`。
  for (final String cut in const <String>['/', '?', '#']) {
    final int at = value.indexOf(cut);
    if (at >= 0) {
      value = value.substring(0, at);
    }
  }
  value = value.trim();
  if (value.isEmpty) {
    return null;
  }
  // ③ IPv6 方括号（`[::1]`）与 `[::1]:53`。
  if (value.startsWith('[')) {
    final int close = value.indexOf(']');
    if (close <= 1) {
      return null;
    }
    value = value.substring(1, close);
    return DnsPlatform.isIpLiteral(value) ? value : null;
  }
  // ④ 裸字面量（IPv4 / IPv6）直接通过。
  if (DnsPlatform.isIpLiteral(value)) {
    return value;
  }
  // ⑤ IPv4 带端口（`1.1.1.1:53`）：端口由实现固定为 53，这里只取地址部分。
  //    **不能**对含冒号的字符串泛化切分——IPv6 本身就含冒号。
  final RegExpMatch? withPort =
      RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$').firstMatch(value);
  if (withPort != null) {
    final String host = withPort.group(1)!;
    return DnsPlatform.isIpLiteral(host) ? host : null;
  }
  return null;
}

/// 一家 DNS 服务商。
class DnsServer {
  /// 创建服务商。
  const DnsServer({
    required this.id,
    required this.label,
    required this.ip,
    this.dohUrl,
    this.region = 'global',
  });

  /// 稳定 ID（用于设置持久化与日志）。
  final String id;

  /// 展示名。
  final String label;

  /// 明文 DNS 地址（UDP 53）。
  final String ip;

  /// DoH 端点（`null` 表示只支持明文）。
  final String? dohUrl;

  /// 归属地分组（`cn` / `global`），用于界面分组与默认排序。
  final String region;

  /// 是否支持 DoH（**必须是合法的 `https://` 端点**，明文 HTTP 不算）。
  ///
  /// ★ 曾经是 `dohUrl != null`：`http://…` 这种"明文的 DoH 端点"也会被
  ///   当作支持——用起来等于把全部查询明文交给中间人。
  bool get supportsDoh => ogLIsUsableDohEndpoint(dohUrl);

  @override
  String toString() => 'DnsServer($id, $ip${dohUrl == null ? '' : ', doh'})';
}

/// 内置 DNS 服务商（默认全部可用，顺序即默认优先级：国内优先）。
///
/// 之所以国内放前面：在受污染网络里，国内解析器的可达性最高，
/// 而它们对 GitHub 域名的解析同样有效。
const List<DnsServer> builtinDnsServers = <DnsServer>[
  DnsServer(
    id: 'alidns',
    label: '阿里 AliDNS',
    ip: '223.5.5.5',
    dohUrl: 'https://dns.alidns.com/resolve',
    region: 'cn',
  ),
  DnsServer(
    id: 'dnspod',
    label: '腾讯 DNSPod',
    ip: '119.29.29.29',
    dohUrl: 'https://doh.pub/dns-query',
    region: 'cn',
  ),
  DnsServer(
    id: 'dns114',
    label: '114 DNS',
    ip: '114.114.114.114',
    region: 'cn',
  ),
  DnsServer(
    id: 'cloudflare',
    label: 'Cloudflare',
    ip: '1.1.1.1',
    dohUrl: 'https://cloudflare-dns.com/dns-query',
  ),
  DnsServer(
    id: 'google',
    label: 'Google',
    ip: '8.8.8.8',
    dohUrl: 'https://dns.google/resolve',
  ),
];

/// DNS 解析异常。
class DnsException implements Exception {
  /// 创建异常。
  const DnsException(this.message);

  /// 说明。
  final String message;

  @override
  String toString() => 'DnsException: $message';
}

/// DNS 报文编解码（RFC 1035，仅 A / AAAA）。
///
/// 刻意保持**纯函数**：不碰 socket、不碰时间，因此可以用固定字节序列断言。
class DnsWireCodec {
  const DnsWireCodec._();

  /// A 记录。
  static const int typeA = 1;

  /// AAAA 记录。
  static const int typeAaaa = 28;

  /// 构造查询报文。
  static List<int> buildQuery(
    String host, {
    int id = 0,
    int type = typeA,
  }) {
    final out = <int>[];
    _writeU16(out, id);
    _writeU16(out, 0x0100); // QR=0, Opcode=0, RD=1
    _writeU16(out, 1); // QDCOUNT
    _writeU16(out, 0); // ANCOUNT
    _writeU16(out, 0); // NSCOUNT
    _writeU16(out, 0); // ARCOUNT

    for (final label in host.split('.')) {
      if (label.isEmpty) {
        continue;
      }
      final bytes = utf8.encode(label);
      if (bytes.length > 63) {
        throw DnsException('域名标签过长（>63 字节）：$label');
      }
      out.add(bytes.length);
      out.addAll(bytes);
    }
    out.add(0); // 结束标签
    _writeU16(out, type);
    _writeU16(out, 1); // CLASS IN
    return out;
  }

  /// 解析响应报文中的 A / AAAA 地址。
  ///
  /// 会校验事务 ID：**不匹配一律拒绝**（防伪造响应/串包）。
  static List<String> parseAnswers(List<int> packet, {int? expectId}) {
    if (packet.length < 12) {
      throw const DnsException('DNS 响应过短');
    }
    final id = _readU16(packet, 0);
    if (expectId != null && id != expectId) {
      throw DnsException('DNS 事务 ID 不匹配（收到 $id，期望 $expectId）');
    }
    final flags = _readU16(packet, 2);
    if ((flags & 0x8000) == 0) {
      throw const DnsException('收到的不是响应报文');
    }
    final rcode = flags & 0x000F;
    if (rcode != 0) {
      throw DnsException('DNS 返回错误码 $rcode');
    }

    final questionCount = _readU16(packet, 4);
    final answerCount = _readU16(packet, 6);

    var offset = 12;
    for (var index = 0; index < questionCount; index++) {
      offset = _skipName(packet, offset) + 4;
    }

    final addresses = <String>[];
    for (var index = 0; index < answerCount; index++) {
      offset = _skipName(packet, offset);
      if (offset + 10 > packet.length) {
        break;
      }
      final type = _readU16(packet, offset);
      final dataLength = _readU16(packet, offset + 8);
      final dataStart = offset + 10;
      if (dataStart + dataLength > packet.length) {
        break;
      }
      if (type == typeA && dataLength == 4) {
        addresses.add(
          '${packet[dataStart]}.${packet[dataStart + 1]}.'
          '${packet[dataStart + 2]}.${packet[dataStart + 3]}',
        );
      } else if (type == typeAaaa && dataLength == 16) {
        final parts = <String>[];
        for (var group = 0; group < 8; group++) {
          // ★ 每组补足 4 位十六进制：不补的话 `0abc` 会变成 `abc`，
          //   拼出来的字符串**不是**那个地址（`2001:abc::` ≠ `2001:0abc::`）。
          parts.add(
            ((packet[dataStart + group * 2] << 8) |
                    packet[dataStart + group * 2 + 1])
                .toRadixString(16)
                .padLeft(4, '0'),
          );
        }
        addresses.add(parts.join(':'));
      }
      offset = dataStart + dataLength;
    }
    return addresses;
  }

  static int _skipName(List<int> packet, int offset) {
    var cursor = offset;
    while (true) {
      if (cursor >= packet.length) {
        throw const DnsException('DNS 响应截断（域名未结束）');
      }
      final length = packet[cursor];
      if ((length & 0xC0) == 0xC0) {
        return cursor + 2; // 压缩指针
      }
      if (length == 0) {
        return cursor + 1;
      }
      cursor += 1 + length;
    }
  }

  static void _writeU16(List<int> out, int value) {
    out.add((value >> 8) & 0xFF);
    out.add(value & 0xFF);
  }

  static int _readU16(List<int> data, int offset) =>
      ((data[offset] & 0xFF) << 8) | (data[offset + 1] & 0xFF);
}

/// UDP 交换通道（抽象以便离线测试）。
abstract class DnsUdpChannel {
  /// 向 [serverIp]:53 发送 [query]，返回响应字节；超时返回 `null`。
  Future<List<int>?> exchange(
    String serverIp,
    List<int> query, {
    Duration timeout = const Duration(seconds: 5),
  });
}

/// 真实 UDP 通道。
///
/// 平台原语委托给 [DnsPlatform]（`net_dns_platform_io.dart`：`RawDatagramSocket`）。
class RawDnsUdpChannel implements DnsUdpChannel {
  @override
  Future<List<int>?> exchange(
    String serverIp,
    List<int> query, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      DnsPlatform.udpExchange(serverIp, query, timeout: timeout);
}

/// 解析器抽象。
abstract class DnsResolver {
  /// 稳定 ID。
  String get id;

  /// 解析主机名，返回 IP 列表。
  Future<List<String>> resolve(String host);
}

/// 系统解析（交给平台）。
///
/// 走 `InternetAddress.lookup`（真拿 IP）。
class SystemDnsResolver implements DnsResolver {
  @override
  String get id => 'system';

  @override
  Future<List<String>> resolve(String host) => DnsPlatform.lookup(host);
}

/// 明文 UDP DNS 解析器。
class UdpDnsResolver implements DnsResolver {
  /// 创建解析器。
  UdpDnsResolver({
    required this.server,
    required this.channel,
    this.timeout = const Duration(seconds: 5),
  });

  /// 目标服务商。
  final DnsServer server;

  /// 交换通道。
  final DnsUdpChannel channel;

  /// 超时。
  final Duration timeout;

  /// 事务 ID 随机源（随机起点 + 逐查询递增：既避免与陈旧响应串包，
  /// 也避免"从 1 开始"这种可被离线猜测的序列）。
  static final Random _idRandom = Random();

  int _queryId = _idRandom.nextInt(0x10000);

  @override
  String get id => server.id;

  /// 下一个事务 ID（从随机起点单调递增，回绕到 16 位）。
  int nextQueryId() => (++_queryId) & 0xFFFF;

  @override
  Future<List<String>> resolve(String host) async {
    // 地址合法性在**发查询之前**收口：非法地址（空串 / 带协议 / 带端口 /
    // 非 IP 文本）在这里报"地址不合法"，而不是让 socket 层抛
    // ArgumentError 被归类成"网络失败"。
    final String? serverIp = ogLNormalizeDnsAddress(server.ip);
    if (serverIp == null) {
      throw DnsException(
        '${server.label} 的 DNS 地址不合法（应为 IPv4 / IPv6 字面量）：'
        '"${server.ip}"',
      );
    }
    final queryId = nextQueryId();
    final query = DnsWireCodec.buildQuery(host, id: queryId);
    final response = await channel.exchange(serverIp, query, timeout: timeout);
    if (response == null) {
      throw DnsException('${server.label} 无响应（超时）');
    }
    return DnsWireCodec.parseAnswers(response, expectId: queryId);
  }
}

/// DoH 所需的**最小** HTTP 能力（由底座传输实现注入，不引入新依赖）。
abstract class DnsHttpClient {
  /// 发起 GET，返回响应体。
  Future<String> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
  });
}

/// DoH（DNS over HTTPS，JSON 格式）解析器。
///
/// 之所以重要：明文 53 端口在受限网络里常被劫持或阻断，
/// HTTPS 通常仍可用——DoH 是绕开 DNS 污染最稳的一条路。
class DohDnsResolver implements DnsResolver {
  /// 创建解析器。
  DohDnsResolver({
    required this.server,
    required this.client,
    this.timeout = const Duration(seconds: 8),
  }) : assert(server.dohUrl != null, 'DoH 解析器需要 server.dohUrl');

  /// 目标服务商。
  final DnsServer server;

  /// HTTP 能力。
  final DnsHttpClient client;

  /// 超时。
  final Duration timeout;

  @override
  String get id => server.id;

  @override
  Future<List<String>> resolve(String host) async {
    final endpoint = server.dohUrl!;
    final separator = endpoint.contains('?') ? '&' : '?';
    final body = await client.get(
      '$endpoint${separator}name=$host&type=A',
      headers: const <String, String>{'accept': 'application/dns-json'},
    ).timeout(timeout);
    return parseDohJson(body);
  }

  /// 解析 DoH 的 JSON 响应（抽出 A 记录）。
  ///
  /// 刻意做成静态纯函数：便于离线断言，也便于复用到 DoT/TLS 场景。
  static List<String> parseDohJson(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (error) {
      throw DnsException('DoH 响应不是合法 JSON：$error');
    }
    if (decoded is! Map) {
      throw const DnsException('DoH 响应结构异常');
    }
    final status = decoded['Status'];
    if (status is int && status != 0) {
      throw DnsException('DoH 返回错误状态 $status');
    }
    final answers = decoded['Answer'];
    if (answers is! List) {
      return const <String>[];
    }
    final result = <String>[];
    for (final answer in answers) {
      if (answer is! Map) {
        continue;
      }
      if (answer['type'] != DnsWireCodec.typeA) {
        continue;
      }
      final data = answer['data'];
      if (data is String && _ipv4.hasMatch(data)) {
        result.add(data);
      }
    }
    return result;
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
}

/// 解析结果（含缓存标记）。
class DnsAnswer {
  /// 创建结果。
  const DnsAnswer({
    required this.addresses,
    required this.serverId,
    required this.expiresAt,
  });

  /// 地址列表。
  final List<String> addresses;

  /// 由哪家解析器给出。
  final String serverId;

  /// 过期时间。
  final DateTime expiresAt;

  /// 是否已过期。
  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  @override
  String toString() => 'DnsAnswer(${addresses.join(',')} via $serverId)';
}

/// DNS 结果缓存（带 TTL 与条目上限）。
class DnsCache {
  /// 创建缓存。
  DnsCache({this.maxEntries = 512});

  /// 条目上限（超过时优先淘汰最接近过期者）。
  final int maxEntries;

  final Map<String, DnsAnswer> _entries = <String, DnsAnswer>{};

  /// 当前条目数。
  int get size => _entries.length;

  /// 读取（自动剔除过期项）。
  DnsAnswer? get(String host) {
    final answer = _entries[host];
    if (answer == null) {
      return null;
    }
    if (answer.isExpiredAt(DateTime.now())) {
      _entries.remove(host);
      return null;
    }
    return answer;
  }

  /// 写入。
  void put(String host, DnsAnswer answer) {
    _entries[host] = answer;
    if (_entries.length <= maxEntries) {
      return;
    }
    // 先清过期项，再按**最接近过期**的顺序淘汰（与注释里的承诺一致：
    // 腾位置时先丢"马上就要过期"的，最耐用的那些留下）。
    final now = DateTime.now();
    final expired = _entries.entries
        .where(
            (MapEntry<String, DnsAnswer> entry) => entry.value.isExpiredAt(now))
        .map((MapEntry<String, DnsAnswer> entry) => entry.key)
        .toList();
    for (final key in expired) {
      _entries.remove(key);
    }
    while (_entries.length > maxEntries) {
      String? soonest;
      DateTime? soonestAt;
      for (final MapEntry<String, DnsAnswer> entry in _entries.entries) {
        final DateTime at = entry.value.expiresAt;
        if (soonestAt == null || at.isBefore(soonestAt)) {
          soonest = entry.key;
          soonestAt = at;
        }
      }
      if (soonest == null) {
        return;
      }
      _entries.remove(soonest);
    }
  }

  /// 清空。
  void clear() => _entries.clear();
}

/// DNS 策略（**能力冲突 → 交由用户选择**的落点）。
class DnsPolicy {
  /// 创建策略。
  DnsPolicy({
    this.mode = NetDnsMode.system,
    List<DnsServer>? servers,
    this.preferDoh = true,
    this.raceServers = true,
    this.cacheTtl = const Duration(minutes: 5),
    this.timeout = const Duration(seconds: 5),
    this.fallbackToSystem = true,
  }) : servers = List<DnsServer>.of(servers ?? builtinDnsServers);

  /// 当前模式。
  ///
  /// 可变是有意的：用户在设置里切换后**立即生效**，不需要重建传输层。
  NetDnsMode mode;

  /// 服务器列表（顺序即优先级；可增删排序）。
  final List<DnsServer> servers;

  /// 是否优先 DoH（禁用后只用明文 UDP）。
  bool preferDoh;

  /// 多服务器时是否并发竞速（取最先成功者）。
  bool raceServers;

  /// 结果缓存时长。
  Duration cacheTtl;

  /// 单次解析超时。
  Duration timeout;

  /// 自定义解析全部失败时，是否回退系统解析。
  ///
  /// 建议保持 `true`：回退**不会**让污染变得更糟，却能让用户不至于完全断网。
  /// 但每次回退都会记 warn 日志，并在自检报告里体现。
  bool fallbackToSystem;

  /// 当前启用的服务器（按列表顺序）。
  List<DnsServer> get enabledServers => List<DnsServer>.unmodifiable(servers);

  @override
  String toString() =>
      'DnsPolicy(mode=${mode.name}, servers=${servers.length}, '
      'doh=$preferDoh, race=$raceServers)';
}

/// DNS 服务：按策略解析，带缓存、并发竞速与系统回退。
class DnsService {
  /// 创建服务。
  DnsService({
    DnsPolicy? policy,
    DnsResolver? systemResolver,
    DnsResolver Function(DnsServer server)? resolverFactory,
    DnsHttpClient? dohClient,
    DnsCache? cache,
    KernelDiagnostics? diagnostics,
  })  : policy = policy ?? DnsPolicy(),
        systemResolver = systemResolver ?? SystemDnsResolver(),
        cache = cache ?? DnsCache(),
        _diagnostics = diagnostics,
        _dohClient = dohClient,
        _resolverFactory = resolverFactory;

  /// 策略。
  final DnsPolicy policy;

  /// 系统解析器。
  final DnsResolver systemResolver;

  /// 结果缓存。
  final DnsCache cache;

  /// 注入的解析器工厂（`null` = 用本文件的默认工厂 `_defaultResolver`）。
  ///
  /// 默认工厂**会长出 DoH**（见 `_defaultResolver`）：这正是 `preferDoh`
  /// 设置的落点。此前的"默认工厂"写死为明文 UDP，于是设置里的
  /// 「DoH 优先」只是一个被存下来、又被策略摘要打印出来的字段，
  /// 对真实解析**毫无影响**（`IoDnsHttpClient` 因而也从未被使用过）。
  final DnsResolver Function(DnsServer server)? _resolverFactory;

  /// DoH 所需的 HTTP 能力（装配根注入 `IoDnsHttpClient`）。
  ///
  /// 为 `null` 时 DoH **无法进行**——底座本体不 import `dart:io`，
  /// 此时按明文 UDP 走，且**不谎称"已启用 DoH"**。
  final DnsHttpClient? _dohClient;

  KernelDiagnostics? _diagnostics;
  bool _warnedCustomUnsupported = false;

  /// 最近一次解析**实际由谁完成**（服务商 id，或 `system` /
  /// `system(fallback)`）。
  ///
  /// 自检报告据此如实呈现"到底是自定义解析成功的，还是已经悄悄回退到
  /// 系统解析了"——摘要里只说"解析成功"会把回退这件事藏起来。
  String? get lastResolvedVia => _lastVia;
  String? _lastVia;

  /// 本平台是否支持自定义 DNS（明文 UDP / DoH）。
  ///
  /// 原生平台恒为 `true`；**Web 恒为 `false`**——浏览器不提供裸 socket，
  /// 明文 DNS 与"用 DoH 结果去直连"都做不到，Web 上只有系统解析一条路。
  /// 设置页据此把"自定义 DNS"入口说明为"Web 端不生效"，
  /// 而不是留一个切过去却毫无作用的开关。
  bool get supportsCustomDns => DnsPlatform.supportsCustomDns;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 应用一次设置变更（模式 / 服务商 / 是否优先 DoH）。
  ///
  /// 与"直接改 [DnsPolicy] 的字段"的区别只有一个，但很关键：**旧缓存会被作废**。
  ///
  /// ## 为什么必须作废
  /// 缓存里的每一条答案都记着"是哪家给的"（[DnsAnswer.serverId]）。
  /// 用户把 DNS 从阿里换到 Cloudflare，若还继续返回阿里的答案，
  /// 表现在界面上就是**"设置改了却毫无变化"**——偏偏换 DNS 的动机
  /// 常常是"当前解析被污染"，于是用户会以为"这功能是假的"。
  /// 缓存默认 TTL 5 分钟，用户等不起这 5 分钟。
  ///
  /// 返回**是否真的发生了变化**（没变就不清缓存，避免无谓抖动 / 无谓日志）。
  bool applySelection({
    required bool custom,
    required String serverId,
    required bool preferDoh,
    DnsServer? customServer,
  }) {
    final NetDnsMode mode = custom ? NetDnsMode.custom : NetDnsMode.system;
    // ★ 自定义服务器优先：用户在设置里填了 IP → 用它（`serverId == 'custom'`
    //   或 `customServer != null` 均走这条）。内置五家仍可按 id 选中。
    final List<DnsServer> picked = customServer != null
        ? <DnsServer>[customServer]
        : builtinDnsServers
            .where((DnsServer server) => server.id == serverId)
            .toList();
    // 没选到内置服务商（id 拼错 / 已下线）→ 保留原列表，**不静默清空**：
    // 清空会让"自定义 DNS"变成一句空话（`_resolveCustom` 直接抛"未配置"）。
    final bool changed = policy.mode != mode ||
        policy.preferDoh != preferDoh ||
        (picked.isNotEmpty && !_sameServers(policy.servers, picked));
    policy.mode = mode;
    policy.preferDoh = preferDoh;
    if (picked.isNotEmpty) {
      policy.servers
        ..clear()
        ..addAll(picked);
    }
    if (changed) {
      cache.clear();
      _lastVia = null;
      _diagnostics?.info(
        'DNS',
        'DNS 策略已更新，旧的解析缓存已作废：'
            '${mode.name}${picked.isEmpty ? '' : ' · ${picked.first.id}'}'
            '${preferDoh ? ' · DoH 优先' : ' · 明文'}',
        code: 'OGL-DNS-104',
        data: <String, Object?>{'servers': policy.servers.length},
      );
    }
    return changed;
  }

  static bool _sameServers(List<DnsServer> a, List<DnsServer> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
  }

  /// 默认解析器：**DoH 优先**，否则明文 UDP。
  ///
  /// 判定顺序（少一条都会让设置的开关"看起来生效、实际不动"）：
  /// 1. `policy.preferDoh`（用户在设置里的"DoH 优先"）；
  /// 2. 该家有**合法**的 `https://` 端点（明文 HTTP 的端点不算，见
  ///    [ogLIsUsableDohEndpoint]）；
  /// 3. 装配根注入了 HTTP 能力（[DnsHttpClient]；底座本体不 import `dart:io`）。
  ///
  /// 三条都满足才用 [DohDnsResolver]，否则明文 UDP —— 而明文通道的失败
  /// 由 [_attemptServer] 按"同一家先 DoH 后明文"的顺序接住。
  DnsResolver _defaultResolver(DnsServer server) {
    final DnsHttpClient? client = _dohClient;
    if (policy.preferDoh &&
        client != null &&
        ogLIsUsableDohEndpoint(server.dohUrl)) {
      return DohDnsResolver(
        server: server,
        client: client,
        timeout: policy.timeout,
      );
    }
    return UdpDnsResolver(
      server: server,
      channel: RawDnsUdpChannel(),
      timeout: policy.timeout,
    );
  }

  /// 解析主机名。
  ///
  /// - IP 字面量直接返回（不做无谓查询）；
  /// - 命中缓存直接返回；
  /// - `system` 模式交给系统；`custom` 模式按策略尝试，失败可回退系统。
  Future<List<String>> resolve(String host) async {
    if (host.isEmpty) {
      throw const DnsException('主机名为空');
    }
    if (_ipv4.hasMatch(host)) {
      return <String>[host];
    }
    // IPv6 字面量（含压缩写法）直接返回，不做无谓查询。
    // 注意：**不能用 `contains(':')` 判断**——那会把 `host:port` 这类输入
    // 误当成 IP 直接返回，于是"解析成功"了一个根本连不上的地址。
    if (DnsPlatform.isIpLiteral(host)) {
      return <String>[host];
    }

    final cached = cache.get(host);
    if (cached != null) {
      _lastVia = cached.serverId;
      _diagnostics?.debug(
        'DNS',
        '缓存命中 $host',
        data: <String, Object?>{'via': cached.serverId},
      );
      return cached.addresses;
    }

    if (policy.mode == NetDnsMode.system || !supportsCustomDns) {
      // Web：自定义 DNS 入口不在本平台生效（浏览器不给裸 socket）。
      // 若用户确实选了自定义，这里**一次性留痕**并如实走系统解析——
      // 绝不静默吞掉这个选择（否则用户会以为切换成功了）。
      if (policy.mode == NetDnsMode.custom &&
          !supportsCustomDns &&
          !_warnedCustomUnsupported) {
        _warnedCustomUnsupported = true;
        _diagnostics?.warn(
          'DNS',
          '本平台不支持自定义 DNS，已按系统解析处理：$host',
          code: 'OGL-DNS-102',
          data: <String, Object?>{'platform': 'web'},
        );
      }
      final addresses = await _attempt(systemResolver, host);
      _remember(host, addresses, systemResolver.id);
      return addresses;
    }

    try {
      final resolution = await _resolveCustom(host);
      _remember(host, resolution.addresses, resolution.serverId);
      return resolution.addresses;
    } catch (error) {
      if (!policy.fallbackToSystem) {
        rethrow;
      }
      // 回退是安全网，但必须在日志里留下痕迹——绝不静默。
      _diagnostics?.warn(
        'DNS',
        '自定义 DNS 全部失败，已回退系统解析：$host',
        code: 'OGL-DNS-101',
        data: <String, Object?>{'error': '$error'},
      );
      final addresses = await _attempt(systemResolver, host);
      _remember(host, addresses, 'system(fallback)');
      return addresses;
    }
  }

  /// 生成环境自检项（注册到 `kernel.probes`）。
  KernelEnvironmentProbe probe({String sampleHost = 'api.github.com'}) =>
      DnsProbe(service: this, sampleHost: sampleHost);

  void _remember(String host, List<String> addresses, String serverId) {
    _lastVia = serverId;
    cache.put(
      host,
      DnsAnswer(
        addresses: addresses,
        serverId: serverId,
        expiresAt: DateTime.now().add(policy.cacheTtl),
      ),
    );
    _diagnostics?.debug(
      'DNS',
      '解析成功 $host',
      data: <String, Object?>{
        'via': serverId,
        'addresses': addresses.take(3).toList(),
      },
    );
  }

  Future<({List<String> addresses, String serverId})> _resolveCustom(
    String host,
  ) async {
    final servers = policy.servers;
    if (servers.isEmpty) {
      throw const DnsException('未配置任何 DNS 服务器');
    }

    if (policy.raceServers && servers.length > 1) {
      return _race(<Future<({List<String> addresses, String serverId})>>[
        for (final server in servers) _attemptServer(server, host),
      ]);
    }

    final failures = <String>[];
    for (final server in servers) {
      try {
        return await _attemptServer(server, host);
      } catch (error) {
        failures.add('$error');
      }
    }
    throw DnsException('全部 DNS 解析失败：${failures.join('；')}');
  }

  Future<({List<String> addresses, String serverId})> _attemptServer(
    DnsServer server,
    String host,
  ) async {
    final DnsResolver Function(DnsServer server)? factory = _resolverFactory;
    if (factory != null) {
      // 注入的工厂（测试 / 定制）：语义完全由调用方决定，本层不再插手。
      final addresses = await _attempt(factory(server), host);
      return (addresses: addresses, serverId: server.id);
    }
    final DnsResolver resolver = _defaultResolver(server);
    try {
      final addresses = await _attempt(resolver, host);
      return (addresses: addresses, serverId: server.id);
    } catch (error) {
      // DoH 不通（443 被阻断、端点 502…）→ **同一家的明文通道**再试一次。
      // 只对 DoH 解析器做这件事：明文 UDP 刚失败过，再试一遍毫无意义。
      // 跨家优先级不受影响（顺序仍由 [DnsPolicy.servers] 决定）。
      if (resolver is! DohDnsResolver) {
        rethrow;
      }
      _diagnostics?.info(
        'DNS',
        'DoH 失败，改用同一家的明文 DNS：${server.label}（$error）',
        code: 'OGL-DNS-103',
        data: <String, Object?>{'server': server.id, 'error': '$error'},
      );
      final addresses = await _attempt(
        UdpDnsResolver(
          server: server,
          channel: RawDnsUdpChannel(),
          timeout: policy.timeout,
        ),
        host,
      );
      return (addresses: addresses, serverId: server.id);
    }
  }

  Future<List<String>> _attempt(DnsResolver resolver, String host) async {
    final addresses = await resolver.resolve(host).timeout(policy.timeout);
    if (addresses.isEmpty) {
      throw DnsException('${resolver.id} 返回空结果');
    }
    return addresses;
  }

  /// 并发竞速：取最先成功者；全部失败才抛错。
  Future<({List<String> addresses, String serverId})> _race(
    List<Future<({List<String> addresses, String serverId})>> attempts,
  ) {
    final completer = Completer<({List<String> addresses, String serverId})>();
    var remaining = attempts.length;
    Object? lastError;
    for (final attempt in attempts) {
      attempt.then(
        (({List<String> addresses, String serverId}) value) {
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        },
        onError: (Object error) {
          lastError = error;
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.completeError(
              DnsException('并发解析全部失败：$lastError'),
            );
          }
        },
      );
    }
    return completer.future;
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
}

/// DNS 环境自检项（注册到内核的 [KernelProbeRegistry]）。
class DnsProbe implements KernelEnvironmentProbe {
  /// 创建自检项。
  DnsProbe({required this.service, this.sampleHost = 'api.github.com'});

  /// 被测服务。
  final DnsService service;

  /// 采样主机名。
  final String sampleHost;

  @override
  String get id => 'base.net.dns';

  @override
  String get title => 'DNS 解析';

  @override
  Future<KernelProbeResult> run() async {
    final stopwatch = Stopwatch()..start();
    final detail = <String, Object?>{
      'mode': service.policy.mode.name,
      'servers': service.policy.servers
          .map((DnsServer server) => '${server.id}(${server.ip})')
          .toList(),
      'preferDoh': service.policy.preferDoh,
    };
    try {
      final addresses = await service.resolve(sampleHost);
      stopwatch.stop();
      detail['addresses'] = addresses.take(3).toList();
      // 如实呈现"这一份结果是谁给的"：自定义解析成功、缓存命中、
      // 还是**已悄悄回退到系统解析**——摘要只说"解析成功"会把回退藏起来。
      final String? via = service.lastResolvedVia;
      final bool fellBack = via?.contains('fallback') ?? false;
      detail['via'] = via;
      detail['fallback'] = fellBack;
      detail['ms'] = stopwatch.elapsedMilliseconds;
      return KernelProbeResult(
        ok: addresses.isNotEmpty,
        summary: addresses.isEmpty
            ? '解析 $sampleHost 无结果'
            : '解析 $sampleHost → ${addresses.take(3).join(', ')}'
                '${fellBack ? '（自定义 DNS 全部失败，已回退系统解析）' : ''}',
        detail: detail,
      );
    } catch (error) {
      stopwatch.stop();
      detail['ms'] = stopwatch.elapsedMilliseconds;
      return KernelProbeResult(
        ok: false,
        summary: '解析 $sampleHost 失败：$error',
        detail: detail,
      );
    }
  }
}
