/// L1 底座级 · DNS 策略的**平台原语**（Web 侧实现）。
///
/// ## 为什么 Web 上不能"接管解析"
/// 浏览器**不向页面暴露裸 socket**（`fetch` / XHR 之外没有 UDP、没有 TCP），
/// 因此：
/// - **明文 DNS（UDP 53）做不了**：`dart:io` 的 `RawDatagramSocket` 在 Web 上
///   根本不存在，浏览器也没有替代 API；
/// - **DoH 可以查询，但不能"接管连接"**：页面能发 HTTPS 请求（CORS 允许时）
///   并从 JSON 里读到真实 IP，可能拿到的 IP **无法回灌给浏览器**——
///   真正建立连接时浏览器仍用它自己的解析器（页面既不能指定目标 IP，
///   也不能伪造 SNI / Host）。于是：
///   - `supportsDohQuery = true`：**能解析**（诊断 / 自检 / 展示用，真实 IP）；
///   - `supportsConnectionTakeover = false`：**不能接管**（连接仍由浏览器解析）。
///
/// 这不是"降级实现"，而是能力事实。三个标志分别由 [DnsService] 使用：
/// 明文 UDP 不可用就**不去尝试**（尝试只会得到 `UnsupportedError`，
/// 把"能力不存在"伪装成"解析失败"），DoH 可用就**真的去用**（见
/// `web_net_transport.dart` 的 `WebDohHttpClient`），接管不了就**如实说明**。
///
/// ★ 安全红线：**绝不**为了"看起来能用"而在 Web 上改写请求去跟随重定向或
///   直接把解析结果编造出来——那会让上层以为自定义 DNS 接管了连接。
library;

/// 平台 DNS 原语（Web）。
class DnsPlatform {
  const DnsPlatform._();

  /// 明文 UDP DNS（`server.ip:53`）在本平台是否可用：**不可用**。
  ///
  /// 浏览器没有裸 socket，`udpExchange` 直接抛 `UnsupportedError`；
  /// 调用方据此**不要**把"本平台没有这条通道"当成"这家 DNS 解析失败"。
  static const bool supportsUdpDns = false;

  /// DoH（DNS over HTTPS）**查询**在本平台是否可用：**可用**。
  ///
  /// `package:http` 的 `BrowserClient` 走浏览器的 `fetch`，能读到 DoH 的
  /// JSON 响应（前提是端点回 `Access-Control-Allow-Origin`）。
  /// 注意它只解决"拿得到真实 IP"，**不**等于"连接会用这个 IP"。
  static const bool supportsDohQuery = true;

  /// 自定义解析结果能否**用于真实连接**（接管解析）：**不能**。
  ///
  /// 浏览器在建立连接时自己解析域名，页面拿到的 IP 无法回灌；
  /// 详见文件头与 `docs/NETWORK.md`。`DnsService.supportsCustomDns`
  /// 即此语义——设置页据此如实说明"自定义 DNS 在 Web 上不接管连接"。
  static const bool supportsConnectionTakeover = false;

  /// 自定义 DNS 是否**可用于真实连接**（对外契约名，供 `DnsService` 读取）。
  ///
  /// 等价于 [supportsConnectionTakeover]：自定义解析器只有在能接管真实连接时
  /// 才有意义 —— Web 上不能，故为 `false`。设置页据此如实说明。
  static const bool supportsCustomDns = supportsConnectionTakeover;

  /// 系统解析：浏览器内部完成，页面拿不到 IP 列表。
  ///
  /// 返回 `[host]` 原样（而不是空列表）——语义是"解析结果是域名本身，
  /// 实际连接由浏览器的网络栈完成"。返回空会被上层判为解析失败。
  static Future<List<String>> lookup(String host) async => <String>[host];

  /// 是否为 IP 字面量（IPv4 / IPv6，含压缩写法）。
  ///
  /// ## 为什么必须严格
  /// 这里的结果会被 [DnsService] 当作"已经解析好的地址"直接放行，因此
  /// **越界的 IPv4（`999.1.1.1`）与 `host:port`（`1.2.3.4:53`）都必须判否**：
  /// 前者连不上，后者根本不是地址——放行等于"解析成功"了一个坏目标
  /// （原生侧由 `InternetAddress.tryParse` 天然拦住，Web 侧没有它，
  /// 只能自己把规则写对）。
  static bool isIpLiteral(String host) {
    if (host.isEmpty) {
      return false;
    }
    if (host.contains(':')) {
      return _isIpv6Literal(host);
    }
    return _isIpv4Literal(host);
  }

  /// 明文 UDP 交换：Web 上**不可用**（浏览器没有裸 socket）。
  ///
  /// 抛 [UnsupportedError] 而非静默返回 `null`：调用方若真走到这里，
  /// 应当看到"能力不存在"，而不是"超时"这种误导性的诊断。
  static Future<List<int>?> udpExchange(
    String serverIp,
    List<int> query, {
    required Duration timeout,
  }) async {
    throw UnsupportedError(
      'Web 平台不支持明文 UDP DNS（浏览器不提供裸 socket）',
    );
  }

  /// IPv4：恰好 4 段十进制、每段 0–255（**不接受** `999.1.1.1` 这类越界写法）。
  static bool _isIpv4Literal(String host) {
    final List<String> parts = host.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final String part in parts) {
      if (part.isEmpty || part.length > 3) {
        return false;
      }
      for (final int code in part.codeUnits) {
        if (code < 0x30 || code > 0x39) {
          return false;
        }
      }
      if (int.parse(part) > 255) {
        return false;
      }
    }
    return true;
  }

  /// IPv6：至多一个 `::`、每组 1–4 位十六进制、总组数 ≤ 8；
  /// 允许尾部的 IPv4 写法（`::ffff:1.2.3.4`，占两组）。
  static bool _isIpv6Literal(String host) {
    String value = host;
    // ① IPv4 尾巴：换成两个占位组后再按十六进制规则统一校验。
    if (value.contains('.')) {
      final int cut = value.lastIndexOf(':');
      if (cut < 0 || !_isIpv4Literal(value.substring(cut + 1))) {
        return false;
      }
      value = '${value.substring(0, cut)}:0:0';
    }
    // ② 拆出 `::` 压缩点两侧；两段各自不允许出现空组。
    final int compress = value.indexOf('::');
    final bool compressed = compress >= 0;
    if (compressed && value.indexOf('::', compress + 1) >= 0) {
      return false; // 第二个 `::`：非法
    }
    final String head = compressed ? value.substring(0, compress) : value;
    final String tail = compressed ? value.substring(compress + 2) : '';
    final List<String> groups = <String>[
      ...head.isEmpty ? const <String>[] : head.split(':'),
      ...tail.isEmpty ? const <String>[] : tail.split(':'),
    ];
    for (final String group in groups) {
      if (group.isEmpty || group.length > 4 || !_isHex(group)) {
        return false;
      }
    }
    // ③ 无压缩：必须正好 8 组；有压缩：**必须真的省下**至少一组。
    return compressed ? groups.length < 8 : groups.length == 8;
  }

  static bool _isHex(String value) {
    for (final int code in value.codeUnits) {
      final bool digit = code >= 0x30 && code <= 0x39;
      final bool lower = code >= 0x61 && code <= 0x66;
      final bool upper = code >= 0x41 && code <= 0x46;
      if (!digit && !lower && !upper) {
        return false;
      }
    }
    return true;
  }
}
