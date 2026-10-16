/// L1 底座级 · 网络自检（实现见 `NetSelfTest`）：
/// 把 errno 级真相写进日志与界面，不再让"连接失败"三个字背走全部信息。
///
/// ## 平台分层
/// 本文件只保留**与平台无关**的部分（缓存、"同一主机 30 秒内只测一次"），
/// 真正的探测交给实现文件 `net_self_test_impl_io.dart`：DNS 解析 +
/// 逐地址 TCP + 裸 TLS + `HttpClient` 四条探针（把故障压到具体一层）。
library;

import 'net_self_test_impl_io.dart';

/// 网络自检：解析 → 逐地址 TCP 连接，输出可读报告。
///
/// 用途：登录/列表出现「连接失败」（`NetException.kind == connection`）时，
/// 自动运行一次并把报告附进异常消息——把 errno 级真相写进日志与界面，
/// 不再让"连接失败"三个字背走全部信息。
///
/// 为什么需要它：设备网络可能对 `curl` 完全通畅，而 App 进程请求失败；
/// 自检在**同一进程、同一时刻**复现整条链路，结果可直接区分：
/// DNS 污染 / IPv6 黑洞 / 系统级应用联网拦截 / TLS 问题。
class NetSelfTest {
  const NetSelfTest._();

  static String? _cachedReport;
  static DateTime? _cachedAt;
  static String? _cachedHost;

  /// 带缓存的运行：`ttl` 内、**同一主机**重复调用直接返回上次报告
  /// （重试链路只自测一次，避免拖慢失败路径）。
  static Future<String> cachedOrRun(
    String host, {
    Duration ttl = const Duration(seconds: 30),
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final lastAt = _cachedAt;
    final last = _cachedReport;
    if (last != null &&
        lastAt != null &&
        _cachedHost == host &&
        DateTime.now().difference(lastAt) < ttl) {
      return last;
    }
    final report = await run(host, timeout: timeout);
    _cachedReport = report;
    _cachedAt = DateTime.now();
    _cachedHost = host;
    return report;
  }

  /// 运行自检（平台实现见文件头注释）。
  ///
  /// 返回单行报告，例如：
  /// `api.github.com:443 | DNS 2 个: 20.205.243.168(IPv4), 2606:... (IPv6) | TCP[20.205.243.168]: OK 350ms | TCP[2606:...]: 失败 12ms → SocketException: ...`
  static Future<String> run(
    String host, {
    int port = 443,
    Duration timeout = const Duration(seconds: 4),
  }) =>
      NetSelfTestImpl.run(host, port: port, timeout: timeout);
}
