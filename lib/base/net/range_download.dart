/// L1 硬件层 · **多连接分片（HTTP Range）下载**（实现启动层契约 [DownloadEngine]）。
///
/// ## 为什么需要它
/// `background_downloader` 是单连接下载：大文件（Release 附件动辄几十 MB）只能
/// 吃一条 TCP 的带宽，用户实测"再快的网也跑不满"。本文件用 `Range` 请求把文件
/// 切成若干片、**并发拉取**，最后顺序合并成目标文件。
///
/// ## 为什么每片写独立临时文件（而不是共用一个 `RandomAccessFile`）
/// 项目早期正是"多 worker 共用一个文件句柄并发定位写入"，导致偶发**错位写坏**。
/// 这里改为每片各写 `<目标>.partN`，全部成功后再顺序合并：
/// - 没有共享可写状态 → 不存在错位竞争；
/// - 任一分片失败/取消 → 删掉所有分片，**不留半成品**（不会把坏文件当成功）。
///
/// ## 与库的分工
/// 本文件是**增补引擎**：不支持 Range（或探测失败）时抛 [DownloadUnsupported]，
/// 由中枢层回退到库任务，绝不硬撑。
///
/// ## 平台分层
/// 本文件只保留**跨平台**的纯逻辑（区间 / 分片规划 / 取消令牌），
/// [OgLRangeDownloader] 由实现文件 `range_download_io.dart` 导出
/// （`dart:io` 的 `HttpClient` + 文件分片落盘：真实并发分片实现）。
library;

import 'package:flutter/foundation.dart';

import '../../kernel/contract/download_engine.dart';

export 'range_download_io.dart' show OgLRangeDownloader;

/// 一个字节区间（**闭区间**：`start..end` 含两端）。
@immutable
class OgLByteRange {
  /// 创建区间。
  const OgLByteRange(this.start, this.end);

  /// 起始偏移（含）。
  final int start;

  /// 结束偏移（含）。
  final int end;

  /// 区间长度。
  int get length => end - start + 1;

  @override
  String toString() => '$start-$end';
}

/// 分片规划（**纯函数**，可单测）。
abstract final class OgLChunkPlan {
  /// 把 [total] 字节切成至多 [connections] 片。
  ///
  /// 规则：
  /// - 每片不小于 [minChunkBytes]（小文件不为它开一堆连接）；
  /// - 分片数 = `min(connections, ceil(total / minChunkBytes))`；
  /// - 余数补给**最后一片**，保证并集正好覆盖 `0..total-1`（不重不漏）。
  static List<OgLByteRange> of({
    required int total,
    required int connections,
    int minChunkBytes = 1 << 20,
  }) {
    if (total <= 0) {
      return const <OgLByteRange>[];
    }
    final int maxConnections = connections < 1 ? 1 : connections;
    final int minChunk = minChunkBytes < 1 ? 1 : minChunkBytes;
    final int byMin = (total + minChunk - 1) ~/ minChunk;
    final int count =
        maxConnections < byMin ? maxConnections : (byMin < 1 ? 1 : byMin);
    final int base = total ~/ count;
    final List<OgLByteRange> out = <OgLByteRange>[];
    int start = 0;
    for (int i = 0; i < count; i++) {
      final int end = i == count - 1 ? total - 1 : start + base - 1;
      out.add(OgLByteRange(start, end));
      start = end + 1;
    }
    return out;
  }
}

/// 取消令牌（实现契约；暂停 / 取消都走它）。
///
/// 纯内存标志位，**不含平台代码**，因此两个平台的实现都可以直接复用。
class OgLRangeCancelToken implements DownloadCancelToken {
  bool _canceled = false;

  @override
  bool get isCancelled => _canceled;

  @override
  void cancel() => _canceled = true;
}
