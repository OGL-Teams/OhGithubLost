/// L2 中枢级 · 第一跳解析的**原生实现**（非 Web）。
///
/// 用 `dart:io HttpClient` 手工走第一跳：**显式不跟随重定向**，
/// 自己读取并校验 `Location`（跳转目标由本仓库校验，不依赖 SDK 的隐式行为）。
///
/// 只在非 Web 构建里参与编译（由 `ix_presign.dart` 的条件导入选定）；
/// Web 对应文件是 `ix_presign_web.dart`（无法预签名，如实返回原地址）。
library;

import 'dart:io';

import 'ix_presign.dart';

/// 第一跳探测（非 Web）。
abstract final class IxPresignProbe {
  /// 走完第一跳，返回可直接下载的地址（失败时 `url` 为 `null`）。
  static Future<IxPresignResult> resolve(
    String url,
    Future<String?> Function() tokenProvider,
  ) async {
    final Uri source = Uri.parse(url);
    final HttpClient client = _defaultClient();
    try {
      final HttpClientRequest request =
          await client.getUrl(source).timeout(_connectTimeout);
      // ★ 显式不跟随：跳转目标由 [IxPresign.safeRedirectTarget] 校验，
      //   不依赖 SDK 的隐式剥离行为。
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.persistentConnection = false;
      request.headers.set('accept', '*/*');
      final String? token = await tokenProvider();
      if (token != null && token.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $token');
      }
      final HttpClientResponse response =
          await request.close().timeout(_receiveTimeout);
      final int status = response.statusCode;
      if (status >= 300 && status < 400) {
        final String? location =
            response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          return IxPresignResult(
            url: null,
            redirected: true,
            statusCode: status,
            error: '3xx 但没有 Location',
          );
        }
        final String? target = IxPresign.safeRedirectTarget(location, source);
        if (target == null) {
          return IxPresignResult(
            url: null,
            redirected: true,
            statusCode: status,
            error: '跳转目标被拒绝（协议或主机不安全）',
          );
        }
        return IxPresignResult(
          url: target,
          redirected: true,
          statusCode: status,
        );
      }
      // 200：第一跳本身就是直链，原样返回。
      // ★ 这里**不能** drain —— 200 意味着后面是真实的文件字节，把它们读掉再
      //   丢弃等于白跑一遍全量流量（调用方随后还会完整下载一次）。
      //   连接由 finally 里的 force close 收尾，不需要靠 drain 回收。
      if (status >= 200 && status < 300) {
        return IxPresignResult(
          url: url,
          redirected: false,
          statusCode: status,
        );
      }
      return IxPresignResult(
        url: null,
        redirected: false,
        statusCode: status,
        error: 'HTTP $status',
      );
    } on Object catch (error) {
      return IxPresignResult(url: null, redirected: false, error: '$error');
    } finally {
      client.close(force: true);
    }
  }

  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _receiveTimeout = Duration(seconds: 30);

  static HttpClient _defaultClient() {
    final HttpClient client = HttpClient();
    client.idleTimeout = const Duration(seconds: 3);
    client.connectionTimeout = _connectTimeout;
    client.userAgent = 'OhGithubLost';
    return client;
  }
}
