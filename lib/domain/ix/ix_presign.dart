/// L2 中枢级 · 第一跳解析：把「需要认证的地址」换成一个**可直接下载的短期
/// 签名地址**。
///
/// ## 为什么需要它（实测结论，非推测）
/// GitHub 的三类二进制资源都是「**302 → 短期签名 URL**」的结构：
///
/// | 资源            | 第一跳                                | 302 目标                                |
/// |-----------------|---------------------------------------|-----------------------------------------|
/// | Release 附件    | `github.com/…/releases/download/…`   | `release-assets.githubusercontent.com`   |
/// | Action 运行日志 | `api.github.com/…/runs/{id}/logs`     | `results-receiver.actions.githubusercontent.com` |
/// | Action 构建产物 | `api.github.com/…/artifacts/{id}/zip` | `*.blob.core.windows.net`               |
///
/// **只有第一跳需要 `Authorization: Bearer`**；第二跳是绑定单对象、约 30 分钟
/// 有效的签名 URL，**不需要任何令牌**。所以只要在本地把第一跳走完、拿到
/// `Location`，后续（含交给第三方加速代理）都不必携带令牌 —— 令牌不出设备。
///
/// ## 顺带落地的安全约束
/// - **不跟随重定向**（`followRedirects = false`）：跳转目标由本方法显式校验，
///   而不是交给 SDK 的隐式行为。此前 `range_download.dart` 直接依赖
///   「Dart 跨域自动剥离 Authorization」这一未文档化行为来保证令牌不外泄。
/// - **跳转目标校验**：只允许 http/https，并拒绝回环 / 私网 / 链路本地地址
///   （含云元数据 `169.254.169.254`）。加速通道地址由用户填写，不校验就等于
///   允许设备被引导去探测内网。
library;

import 'ix_presign_web.dart';

/// 解析结果（失败时 [url] 为 `null`，调用方据此降级）。
class IxPresignResult {
  /// 创建结果。
  const IxPresignResult({
    required this.url,
    required this.redirected,
    this.statusCode,
    this.error,
  });

  /// 可直接请求的地址（`null` = 解析失败，调用方应回退到原始地址）。
  final String? url;

  /// 是否真的发生了跳转（`false` = 原始地址本身就是可下载的直链）。
  final bool redirected;

  /// 第一跳的 HTTP 状态码（便于诊断）。
  final int? statusCode;

  /// 失败原因（**如实携带，不静默**）。
  final String? error;

  /// 是否成功。
  bool get ok => url != null;

  @override
  String toString() => 'IxPresignResult(ok=$ok, redirected=$redirected, '
      'status=$statusCode, error=$error)';
}

/// 第一跳解析服务。
class IxPresign {
  /// 创建服务。
  ///
  /// [tokenProvider] 返回当前令牌明文（未登录返回 `null`；公开资源此时同样
  /// 能拿到签名地址，只是没有 Authorization 头）。
  ///
  /// ## Web 上的行为（如实说明，不假装）
  /// 浏览器把跨域 302 当作**不可读的网络细节**（`fetch` 里是
  /// `type === 'opaqueredirect'`，拿不到 `Location`），因此 Web 上**无法预签名**：
  /// [resolve] 直接返回 `IxPresignResult(url: 原地址, redirected: false)`，
  /// 由调用方按「无签名」处理。
  /// ★ 绝不会改成"跟随重定向去读内容"——那会绕过令牌保护把受保护资源取回，
  ///   是安全边界的破坏。真正的第一跳只在原生平台进行。
  IxPresign({required this.tokenProvider});

  /// 令牌提供者。
  final Future<String?> Function() tokenProvider;

  /// 把 [url] 解析成可直接下载的地址。
  ///
  /// 流程（原生平台）：请求第一跳（**不跟随重定向**）→ 若为 3xx 则取
  /// `Location` 并校验 → 返回该地址；若第一跳本身就是 200，则原样返回。
  /// Web 平台见构造函数的说明。
  Future<IxPresignResult> resolve(String url) async {
    final Uri? source = Uri.tryParse(url);
    if (source == null ||
        (source.scheme != 'http' && source.scheme != 'https')) {
      return IxPresignResult(
        url: null,
        redirected: false,
        error: '非 http/https 地址',
      );
    }
    return IxPresignProbe.resolve(url, tokenProvider);
  }

  /// 校验并解析跳转目标（相对地址按 [base] 补全）。
  static String? safeRedirectTarget(String location, Uri base) {
    final Uri? target = Uri.tryParse(location);
    if (target == null) {
      return null;
    }
    final Uri absolute = target.hasScheme ? target : base.resolveUri(target);
    if (absolute.scheme != 'http' && absolute.scheme != 'https') {
      return null;
    }
    if (isForbiddenHost(absolute.host)) {
      return null;
    }
    return absolute.toString();
  }

  /// 拒绝**回环 / 私网 / 链路本地 / 未指定 / 空**主机。
  ///
  /// 公开理由：加速通道地址由用户填写，而签名地址来自 302；不校验就等于给了
  /// 一条「让设备去请求任意内网地址」的路。云环境元数据服务
  /// （`169.254.169.254`）就在链路本地段里。
  static bool isForbiddenHost(String host) {
    String h = host.trim().toLowerCase();
    // 去掉 IPv6 字面量的方括号与 FQDN 的尾点。
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    if (h.isEmpty || h == 'localhost' || h.endsWith('.localhost')) {
      return true;
    }

    // ① 整数形式的 IPv4（`2130706433`、`0x7f000001`）→ 先化成点分。
    //    浏览器会照这两种写法访问 127.0.0.1，不归一化就等于留了后门。
    final String? dotted = _ipv4FromInteger(h);
    if (dotted != null) {
      h = dotted;
    }

    // ② IPv6 里的 IPv4 映射/兼容写法（`::ffff:127.0.0.1`）→ 取末段的 IPv4。
    if (h.contains(':')) {
      final String tail = h.split(':').last;
      if (tail.contains('.')) {
        h = tail;
      }
    }

    // ③ IPv6 段判断（按**位**，不再用前缀字符串比较）。
    if (h.contains(':')) {
      final String first = h.split(':').first;
      if (first.isEmpty) {
        return true; // `::1` / `::` 这类省略写法一律拒绝
      }
      final int? hextet = int.tryParse(first, radix: 16);
      if (hextet == null) {
        return false;
      }
      if (hextet == 0) {
        return true; // 未指定地址
      }
      if (hextet >= 0xfc00 && hextet <= 0xfdff) {
        return true; // fc00::/7 唯一本地
      }
      if (hextet >= 0xfe80 && hextet <= 0xfebf) {
        return true; // fe80::/10 链路本地
      }
      return false; // 其它公网 IPv6
    }

    // ④ 点分 IPv4（含 `127.1` 这类缩写：缺的段按 0 处理）。
    final List<String> parts = h.split('.');
    if (parts.length > 4) {
      return false;
    }
    final List<int> nums = <int>[];
    for (final String part in parts) {
      final int? v = int.tryParse(part);
      if (v == null || v < 0 || v > 255) {
        return false; // 不是 IP，也不像域名：交给上层按域名处理
      }
      nums.add(v);
    }
    if (nums.isEmpty) {
      return false;
    }
    final int a = nums[0];
    final int b = nums.length > 1 ? nums[1] : 0;
    if (a == 0 || a == 127) {
      return true; // 未指定 / 回环
    }
    if (a == 10) {
      return true; // 私网 10/8
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return true; // 私网 172.16/12
    }
    if (a == 192 && b == 168) {
      return true; // 私网 192.168/16
    }
    if (a == 169 && b == 254) {
      return true; // 链路本地，含云元数据
    }
    return false;
  }

  /// `2130706433` / `0x7f000001` 这类整数形式的 IPv4 → 点分字符串。
  ///
  /// 不是这两种形式时返回 `null`（保持原样）。
  static String? _ipv4FromInteger(String host) {
    BigInt? value;
    if (RegExp(r'^\d+$').hasMatch(host)) {
      value = BigInt.tryParse(host);
    } else if (RegExp(r'^0x[0-9a-f]+$').hasMatch(host)) {
      value = BigInt.tryParse(host.substring(2), radix: 16);
    }
    if (value == null ||
        value < BigInt.zero ||
        value > BigInt.from(0xFFFFFFFF)) {
      return null;
    }
    final int v = value.toInt();
    return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }

  /// 把 JSON 里的摘要字段规整成小写十六进制；不是 sha256 或缺失则返回 `null`。
  ///
  /// GitHub Release 资产的 `digest` 形如 `sha256:ab12…`；私有仓库与旧资产
  /// 可能为 `null` —— 那就**如实当作未提供**，绝不假装验过。
  static String? normalizeDigest(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    final String text = raw.trim().toLowerCase();
    final int colon = text.indexOf(':');
    final String algo = colon < 0 ? text : text.substring(0, colon);
    if (algo != 'sha256') {
      return null;
    }
    final String hex = colon < 0 ? '' : text.substring(colon + 1);
    if (hex.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
      return null;
    }
    return hex;
  }
}
