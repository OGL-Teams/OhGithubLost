/// L0 启动层契约 · **下载引擎**（多连接分片能力的接口）。
///
/// ## 为什么放契约层
/// 分片下载要动 `dart:io HttpClient`（硬件层实现），但使用方是**逻辑层**的
/// 下载管理器；若逻辑层直接 import 硬件层实现，就破坏了
/// `surface → domain → base → kernel` 的依赖方向。
/// 于是把"能力"写在契约里（谁都可以引用），"实现"留在硬件层，
/// 由**装配根**（`domain_bridge`）注入——与 `disk_store` / `net_types` 同一套做法。
///
/// ## 语义
/// - [probe]：探测目标是否支持 `Range`（决定能否并发分片）；
/// - [fetch]：按分片并发拉取并落盘到 [DownloadRequest.targetPath]，返回写入字节数；
/// - **失败必须清理**：不允许把"半成品"当成成功（实现方负责删掉临时分片）。
library;

import 'package:flutter/foundation.dart';

/// 探测结果。
@immutable
class DownloadProbe {
  /// 创建。
  const DownloadProbe({
    required this.supportsRange,
    this.total,
    this.fileName,
    this.statusCode,
  });

  /// 服务端是否支持 Range（能否并发分片）。
  final bool supportsRange;

  /// 总字节数（未知 = null）。
  final int? total;

  /// 服务端给出的文件名（若有）。
  final String? fileName;

  /// 探测时的状态码（诊断用）。
  final int? statusCode;

  /// 序列化（进日志 / 诊断）。
  Map<String, Object?> toJson() => <String, Object?>{
        'supportsRange': supportsRange,
        if (total != null) 'total': total,
        if (fileName != null) 'fileName': fileName,
        if (statusCode != null) 'statusCode': statusCode,
      };

  @override
  String toString() =>
      'DownloadProbe(range=$supportsRange total=$total status=$statusCode)';
}

/// 取消令牌（跨分片共享；暂停 / 取消都走它）。
abstract class DownloadCancelToken {
  /// 是否已取消。
  bool get isCancelled;

  /// 请求取消（实现方在下一次读到时退出）。
  void cancel();
}

/// 分片拉取请求。
@immutable
class DownloadRequest {
  /// 创建。
  const DownloadRequest({
    required this.url,
    required this.targetPath,
    required this.total,
    this.headers = const <String, String>{},
    this.connections = 4,
  });

  /// 源地址。
  final Uri url;

  /// 落盘路径（分片临时文件由实现方自行命名与清理）。
  final String targetPath;

  /// 总字节数（来自 [DownloadProbe.total]）。
  final int total;

  /// 附带请求头（鉴权 / UA）。
  final Map<String, String> headers;

  /// 并发连接数。
  final int connections;
}

/// 下载引擎（硬件层实现，逻辑层只认这个接口）。
abstract class DownloadEngine {
  /// 探测是否支持 Range。
  Future<DownloadProbe> probe(
    Uri url, {
    Map<String, String>? headers,
  });

  /// 分片并发拉取并落盘；返回写入的字节数。
  ///
  /// [onProgress] 汇报**累计**已收字节与总量（用于进度条与速度）。
  Future<int> fetch(
    DownloadRequest request, {
    void Function(int received, int total)? onProgress,
    DownloadCancelToken? cancel,
  });

  /// 释放资源（注入的连接池由调用方负责）。
  void close();

  /// 新建一个取消令牌（调用方不关心实现，便于测试注入假引擎）。
  DownloadCancelToken newCancelToken();
}

/// 目标不支持（或暂时无法）分片下载：调用方应回退到普通单连接下载。
class DownloadUnsupported implements Exception {
  /// 创建。
  const DownloadUnsupported(this.reason);

  /// 原因（进日志）。
  final String reason;

  @override
  String toString() => 'DownloadUnsupported: $reason';
}

/// 分片请求失败（HTTP 状态 / 长度不符等）。
class DownloadHttpException implements Exception {
  /// 创建。
  const DownloadHttpException(this.detail, {this.statusCode});

  /// 说明。
  final String detail;

  /// 状态码（若有）。
  final int? statusCode;

  @override
  String toString() => 'DownloadHttpException($statusCode)：$detail';
}

/// 已被取消（调用方据此把任务标记为"已取消"，而不是"失败"）。
class DownloadCanceled implements Exception {
  /// 创建。
  const DownloadCanceled();

  @override
  String toString() => 'DownloadCanceled';
}
