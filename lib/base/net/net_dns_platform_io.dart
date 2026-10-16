/// L1 底座级 · DNS 策略的**平台原语**（非 Web 侧实现）。
///
/// ## 为什么拆出这个文件
/// `net_dns.dart` 的**策略逻辑**（报文编解码 / 缓存 / 竞速 / 回退 / 自检）
/// 与平台无关，可以在 Web 上原样复用；真正碰平台网络的只有三件事：
/// 系统解析、IP 字面量判断、明文 UDP 交换。
///
/// 这三件事被收进本文件的 [DnsPlatform]；`net_dns.dart` 通过条件导入选用
/// 本文件（非 Web）或 `net_dns_platform_web.dart`（Web），从而本体不再
/// `import 'dart:io'` —— 浏览器里没有 `dart:io`，进来就是编译失败。
library;

import 'dart:async';
import 'dart:io';

/// 平台 DNS 原语（Android / Windows / Linux / macOS / iOS）。
class DnsPlatform {
  const DnsPlatform._();

  /// 本平台是否支持**自定义 DNS（明文 UDP / DoH）**。
  ///
  /// 原生平台为 `true`；Web 为 `false`（浏览器不给裸 socket）——
  /// `DnsService` 据此决定是否允许走自定义解析路径，避免留下一个
  /// "看起来能选、实际静默失效"的开关。
  static const bool supportsCustomDns = true;

  /// 系统解析：交给操作系统（`InternetAddress.lookup`）。
  static Future<List<String>> lookup(String host) async {
    final List<InternetAddress> list = await InternetAddress.lookup(host);
    return list.map((InternetAddress address) => address.address).toList();
  }

  /// 是否为 IP 字面量（IPv4 / IPv6，含压缩写法）。
  ///
  /// 必须能区分 `host:port` 这类输入（它不是 IP），否则会把一个连不上的
  /// "地址"当成解析成功的直连目标。
  static bool isIpLiteral(String host) => InternetAddress.tryParse(host) != null;

  /// 明文 UDP DNS 交换：向 `serverIp:53` 发送 [query]，返回响应字节；
  /// 超时返回 `null`（由上层翻译成 `DnsException`）。
  static Future<List<int>?> udpExchange(
    String serverIp,
    List<int> query, {
    required Duration timeout,
  }) async {
    final RawDatagramSocket socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final Completer<List<int>?> completer = Completer<List<int>?>();
    Timer? timer;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      subscription = socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read || completer.isCompleted) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        // **来源校验**：只接受目标服务器发来的响应，其它来源的数据包直接忽略
        // （配合事务 ID 校验，构成"来源 + 串包"双重防伪）。
        if (datagram.address.address != serverIp) {
          return;
        }
        completer.complete(datagram.data);
      });
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });
      socket.send(query, InternetAddress(serverIp), 53);
      return await completer.future;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket.close();
    }
  }
}
