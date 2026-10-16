/// L2 中枢级 · Actions 运行日志（**带令牌下载 zip + 解压**）。
///
/// GitHub 的日志接口 `GET /repos/{o}/{r}/actions/runs/{id}/logs`
/// 返回 **302 → zip**（逐个 job 一个 `.txt`），必须带令牌请求。
/// 本服务负责：带令牌拉取二进制 → 用 `archive` 解压 → 返回
/// `job 名 → 文本` 映射，供运行详情页展示与检索。
///
/// ## 平台分层
/// "取一段字节"这一步要 HTTP 客户端（`dart:io HttpClient`），实现收敛在
/// `ix_action_logs_http_io.dart`。**解压**部分（`archive`）是纯 Dart，
/// 与传输共用同一份代码，不必拆。
///
/// ## 传输策略（2026-10-03）
/// 由 Dio 改为原生 `HttpClient`：这里只需要"取一段字节"，没必要为它引入一个
/// HTTP 框架；同时**禁用连接复用**，与底座传输保持同一策略，避开
/// `Connection closed before full header` 一类故障。
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'ix_action_logs_http_io.dart';

/// 日志拉取失败（HTTP 状态或网络错误）。
///
/// 单独定类型（而不是漏一个 `HttpException` 出去）的原因：上层不该被迫
/// 认识平台类型。交互层只做"如实提示"。
class IxActionLogsException implements Exception {
  /// 创建异常。
  const IxActionLogsException(this.message, {this.statusCode});

  /// 说明。
  final String message;

  /// HTTP 状态码（若已拿到响应）。
  final int? statusCode;

  @override
  String toString() => 'IxActionLogsException(${statusCode ?? '-'})：$message';
}

/// Actions 日志服务。
class IxActionLogs {
  /// 创建服务。
  ///
  /// [tokenProvider] 返回当前令牌明文（未登录返回 `null`）。
  IxActionLogs({required this.tokenProvider});

  /// 令牌提供者。
  final Future<String?> Function() tokenProvider;

  /// 拉取一次运行的日志；失败抛出 [IxActionLogsException]（调用方如实提示）。
  Future<Map<String, String>> fetch(String fullName, int runId) async {
    final String? token = await tokenProvider();
    final Uri uri = Uri.parse(
      'https://api.github.com/repos/$fullName/actions/runs/$runId/logs',
    );
    final Map<String, String> headers = <String, String>{
      'accept': 'application/vnd.github+json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    final List<int> data = await IxActionLogsHttp.fetchBytes(uri, headers);
    if (data.isEmpty) {
      return const <String, String>{};
    }
    return _decodeZip(data);
  }

  /// 解压日志 zip → `job 名 → 文本`。
  ///
  /// 纯 Dart（`archive`），Web 上同样可用——没有理由为此写两遍。
  static Map<String, String> _decodeZip(List<int> bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Map<String, String> out = <String, String>{};
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.txt')) {
        continue;
      }
      out[_labelOf(file.name)] = utf8.decode(
        file.content,
        allowMalformed: true,
      );
    }
    return out;
  }

  /// zip 内条目形如 `job 名/1_步骤.txt` → 取 `job 名` 作为分组标题。
  static String _labelOf(String path) {
    final int slash = path.indexOf('/');
    if (slash <= 0) {
      return path.replaceAll('.txt', '');
    }
    return path.substring(0, slash);
  }
}
