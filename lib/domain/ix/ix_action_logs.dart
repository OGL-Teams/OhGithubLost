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
import 'ix_action_logs_save_io.dart'
    if (dart.library.js_interop) 'ix_action_logs_save_stub.dart' as io_impl;

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

/// GitHub API 根（默认官方）。
const String kOgLApiBase = 'https://api.github.com';

/// Actions 日志服务。
class IxActionLogs {
  /// 创建服务。
  ///
  /// [tokenProvider] 返回当前令牌明文（未登录返回 `null`）。
  IxActionLogs({required this.tokenProvider, this.apiBase = kOgLApiBase});

  /// 令牌提供者。
  final Future<String?> Function() tokenProvider;

  /// GitHub API 根（默认官方；装配层可覆盖以支持企业实例）。
  final String apiBase;

  /// 带令牌发一个 **POST 写操作**（rerun / cancel），非 2xx 抛
  /// [IxActionLogsException]。
  ///
  /// 与 [fetch] 共用同一套传输（手动重定向、不复用连接）——写操作
  /// **不经过加速通道、不带查询参数**，响应体（通常为空）被丢弃。
  Future<void> _post(String path) async {
    final String? token = await tokenProvider();
    final Uri uri = Uri.parse('$apiBase$path');
    final Map<String, String> headers = <String, String>{
      'accept': 'application/vnd.github+json',
      'content-length': '0',
      if (token != null) 'authorization': 'Bearer $token',
    };
    try {
      await IxActionLogsHttp.postEmpty(uri, headers);
    } on IxActionLogsException {
      rethrow;
    }
  }

  /// 把一份日志文本保存到本地可见目录（`<publicOrAppRoot>/actions/<name>`）。
  ///
  /// - [root]：落盘根（页面从装配层取 `OgLStorage.plan().root`，本层不做裁决）；
  /// - [fileName]：形如 `owner-repo-run123456.log`（调用方负责净化）；
  /// - 返回完整路径（提示用户"存到了哪"）；
  /// - Web 无文件系统 → 抛 [IxActionLogsException]（如实报错，不假装成功）。
  ///
  /// 为什么不进 [IxDownloadManager]：下载器是"从 URL 拉字节"，日志文本
  /// 已在内存里，再绕一圈 URL 等于编造来源；直接落盘才是如实的路径。
  Future<String> saveToDisk({
    required String root,
    required String fileName,
    required String text,
  }) =>
      io_impl.ogLActionLogSaveToDisk(
        root: root,
        fileName: fileName,
        text: text,
      );

  /// 重新运行一次运行中 **失败的 job**（写操作）。
  ///
  /// 端点：`POST /repos/{o}/{r}/actions/runs/{id}/rerun-failed-jobs`。
  /// 403 = 无 `actions: write` 权限，调用方如实提示，不降级猜测。
  Future<void> rerunFailedJobs(String fullName, int runId) =>
      _post('/repos/$fullName/actions/runs/$runId/rerun-failed-jobs');

  /// 取消一次运行（写操作）。
  ///
  /// 端点：`POST /repos/{o}/{r}/actions/runs/{id}/cancel`。
  Future<void> cancel(String fullName, int runId) =>
      _post('/repos/$fullName/actions/runs/$runId/cancel');

  /// 把一次运行的日志拼成单份文本（`=== job ===` 分段），供下载 / 复制。
  static String joinLogs(Map<String, String> logs) => logs.entries
      .map((MapEntry<String, String> e) => '=== ${e.key} ===\n${e.value}')
      .join('\n\n');

  /// 拉取一次运行的日志；失败抛出 [IxActionLogsException]（调用方如实提示）。
  Future<Map<String, String>> fetch(String fullName, int runId) async {
    final String? token = await tokenProvider();
    final Uri uri = Uri.parse(
      '$apiBase/repos/$fullName/actions/runs/$runId/logs',
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
        file.content as List<int>,
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
