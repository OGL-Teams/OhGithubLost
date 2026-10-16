/// L1 硬件层 · 多连接分片下载的**原生实现**（非 Web）。
///
/// 本文件是 `OgLRangeDownloader` 的真实实现：`dart:io HttpClient` 发 Range 请求，
/// 每片写独立的 `<目标>.partN`，成功后顺序合并。
///
/// 只在非 Web 构建里参与编译（由 `range_download.dart` 的条件导出选定）；
/// Web 对应文件是 `range_download_web.dart`。
///
/// 允许 `import 'dart:io'`：这正是"非 Web 侧实现文件"。
library;

import 'dart:io';

import '../../kernel/contract/download_engine.dart';
import 'range_download.dart';

/// 多连接分片下载器。
class OgLRangeDownloader implements DownloadEngine {
  /// 创建。
  ///
  /// [client] 可注入（复用既有连接池）；不传则自建并在 [close] 时关闭。
  OgLRangeDownloader({HttpClient? client, this.userAgent = 'OhGithubLost'})
      : _owned = client == null,
        _client = client ?? HttpClient() {
    _client.userAgent = userAgent;
  }

  final HttpClient _client;
  final bool _owned;

  /// User-Agent。
  final String userAgent;

  /// 每片最小字节（比它小的文件不值得分片）。
  static const int minChunkBytes = 1 << 20;

  @override
  Future<DownloadProbe> probe(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    const Duration timeout = Duration(seconds: 15);
    try {
      final HttpClientRequest head = await _client.headUrl(url);
      _applyHeaders(head, headers);
      head.persistentConnection = false;
      final HttpClientResponse response = await head.close().timeout(timeout);
      final int? length =
          response.contentLength >= 0 ? response.contentLength : null;
      final String acceptRanges =
          response.headers.value(HttpHeaders.acceptRangesHeader) ?? '';
      final String? fileName = _fileNameOf(response);
      final int status = response.statusCode;
      await response.drain<void>();
      if (status == 200 && acceptRanges.contains('bytes')) {
        return DownloadProbe(
          supportsRange: true,
          total: length,
          fileName: fileName,
          statusCode: status,
        );
      }
      // 有些服务端只在带 Range 的 GET 上才表态，复核一次。
      return await _probeByRange(url, headers: headers, timeout: timeout);
    } catch (error) {
      // HEAD 被禁（405 等）时同样用 Range 复核；仍失败则视为不支持。
      try {
        return await _probeByRange(url, headers: headers, timeout: timeout);
      } catch (inner) {
        return const DownloadProbe(supportsRange: false);
      }
    }
  }

  Future<DownloadProbe> _probeByRange(
    Uri url, {
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final HttpClientRequest request = await _client.getUrl(url);
    _applyHeaders(request, headers);
    request.persistentConnection = false;
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final HttpClientResponse response = await request.close().timeout(timeout);
    final int status = response.statusCode;
    final String? contentRange =
        response.headers.value(HttpHeaders.contentRangeHeader);
    final String? fileName = _fileNameOf(response);
    await response.drain<void>();
    if (status != HttpStatus.partialContent) {
      return DownloadProbe(supportsRange: false, statusCode: status);
    }
    return DownloadProbe(
      supportsRange: true,
      total: _totalFromContentRange(contentRange),
      fileName: fileName,
      statusCode: status,
    );
  }

  @override
  Future<int> fetch(
    DownloadRequest request, {
    void Function(int received, int total)? onProgress,
    DownloadCancelToken? cancel,
  }) async {
    if (request.total <= 0) {
      throw const DownloadUnsupported('总长度未知，无法分片');
    }
    final List<OgLByteRange> plan = OgLChunkPlan.of(
      total: request.total,
      connections: request.connections,
      minChunkBytes: minChunkBytes,
    );
    if (plan.length < 2) {
      throw const DownloadUnsupported('分片数不足（文件太小或并发不足）');
    }
    final File target = File(request.targetPath);
    final List<File> parts = <File>[
      for (int i = 0; i < plan.length; i++)
        File('${request.targetPath}.part$i'),
    ];
    int received = 0;

    bool merged = false;
    try {
      await Future.wait<void>(<Future<void>>[
        for (int i = 0; i < plan.length; i++)
          _fetchPart(
            url: request.url,
            part: parts[i],
            range: plan[i],
            headers: request.headers,
            cancel: cancel,
            onBytes: (int delta) {
              received += delta;
              onProgress?.call(received, request.total);
            },
          ),
      ]);
      // 合并：顺序拼接，写盘一次成型。
      //
      // ★ 合并阶段失败必须把半成品删掉：契约要求「失败不留半成品」（见
      //   kernel/contract/download_engine.dart），而此前 finally 只删分片，
      //   长度不符或 addStream 抛错时会把一个残缺的 target 留在磁盘上 ——
      //   中控回退到库任务时用的还是同一个路径。
      final IOSink sink = target.openWrite();
      try {
        for (final File part in parts) {
          await sink.addStream(part.openRead());
        }
      } finally {
        await sink.close();
      }
      final int written = await target.length();
      if (written != request.total) {
        throw DownloadHttpException('合并后长度不符：$written != ${request.total}');
      }
      merged = true;
      return written;
    } finally {
      if (!merged) {
        // 合并没成功：target 是半成品，一并清掉（失败不留半成品）。
        try {
          if (await target.exists()) {
            await target.delete();
          }
        } catch (_) {
          // 清理失败不改变结论：本次下载已经失败，上层会如实报错。
        }
      }
      for (final File part in parts) {
        if (await part.exists()) {
          try {
            await part.delete();
          } catch (_) {
            // 清理失败不影响主流程（下次同名任务会重建）。
          }
        }
      }
    }
  }

  Future<void> _fetchPart({
    required Uri url,
    required File part,
    required OgLByteRange range,
    required Map<String, String> headers,
    DownloadCancelToken? cancel,
    required void Function(int delta) onBytes,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const DownloadCanceled();
    }
    final HttpClientRequest request = await _client.getUrl(url);
    _applyHeaders(request, headers);
    request.persistentConnection = false;
    request.headers
        .set(HttpHeaders.rangeHeader, 'bytes=${range.start}-${range.end}');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.partialContent) {
      throw DownloadHttpException(
        '分片 $range 返回 ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final IOSink sink = part.openWrite();
    int got = 0;
    try {
      await for (final List<int> chunk in response) {
        if (cancel?.isCancelled ?? false) {
          throw const DownloadCanceled();
        }
        sink.add(chunk);
        got += chunk.length;
        onBytes(chunk.length);
      }
    } finally {
      await sink.close();
    }
    if (got != range.length) {
      // 长度不符：这一片不可信（由调用方删除全部分片）。
      throw DownloadHttpException('分片 $range 长度不符：$got != ${range.length}');
    }
  }

  void _applyHeaders(HttpClientRequest request, Map<String, String>? headers) {
    if (headers == null) {
      return;
    }
    for (final MapEntry<String, String> entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  @override
  void close() {
    if (_owned) {
      _client.close(force: true);
    }
  }

  @override
  DownloadCancelToken newCancelToken() => OgLRangeCancelToken();

  static int? _totalFromContentRange(String? value) {
    if (value == null) {
      return null;
    }
    final int slash = value.lastIndexOf('/');
    if (slash < 0) {
      return null;
    }
    return int.tryParse(value.substring(slash + 1).trim());
  }

  static String? _fileNameOf(HttpClientResponse response) {
    final String? disposition =
        response.headers.value('content-disposition');
    if (disposition == null) {
      return null;
    }
    final RegExpMatch? match =
        RegExp('filename="?([^";]+)"?').firstMatch(disposition);
    return match?.group(1);
  }
}
