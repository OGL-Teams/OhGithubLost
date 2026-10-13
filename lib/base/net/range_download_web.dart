/// L1 硬件层 · 多连接分片下载的 **Web 桩实现**（一律"不支持"）。
///
/// ## 为什么 Web 上做不到多连接分片
/// 分片下载需要两样东西，浏览器**都没有**：
/// 1. **可控的并发连接** —— `fetch` 连接池由浏览器统一管理，页面既不能开
///    N 条到同一主机的连接，也拿不到"某一条连接"；`Range` 头虽然能设，
///    但浏览器不会因为设置了 Range 就给你并发通道；
/// 2. **把响应体写进文件系统** —— 页面无法"把几片字节合并成目标文件"，
///    唯一的下载语义是把 URL 交给浏览器的下载器（那是浏览器自己的事，
///    页面不参与）。
///
/// 因此这里**如实抛 [DownloadUnsupported]**（契约允许的失败形态），
/// 而不是给一个"看起来在分片、实际全串行"的假实现：
/// 调用方（`IxDownloadManager`）捕获后**回退到单连接 / 浏览器下载**，
/// 用户看到的是"普通下载"，而不是"多线程却一样慢"。
///
/// 注：`IxDownloadManager` 还会先看后端的 `supportsRanged` 标志，
/// 在 Web 上根本不会走到这里——本类存在的意义是让装配根
/// （`domain_bridge` 注入 `OgLRangeDownloader()`）在 Web 上依然可编译，
/// 且一旦被调用就给出明确、非静默的失败。
library;

import '../../kernel/contract/download_engine.dart';
import 'range_download.dart';

/// 多连接分片下载器（Web：不支持）。
class OgLRangeDownloader implements DownloadEngine {
  /// 创建（Web 上无状态；装配根以无参形式构造即可）。
  OgLRangeDownloader();

  static const String _reason = 'Web 平台不支持多连接分片下载（浏览器不提供可控并发连接，'
      '页面也无法把分片写入文件系统）';

  @override
  Future<DownloadProbe> probe(
    Uri url, {
    Map<String, String>? headers,
  }) async =>
      throw const DownloadUnsupported(_reason);

  @override
  Future<int> fetch(
    DownloadRequest request, {
    void Function(int received, int total)? onProgress,
    DownloadCancelToken? cancel,
  }) async =>
      throw const DownloadUnsupported(_reason);

  @override
  void close() {
    // 无资源可释放（Web 上没有自建连接池）。
  }

  @override
  DownloadCancelToken newCancelToken() => OgLRangeCancelToken();
}
