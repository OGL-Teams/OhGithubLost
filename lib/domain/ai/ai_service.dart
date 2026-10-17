/// L2 · AI 服务：设置 / 会话 / 补全编排（工具循环 + 流式）。
///
/// 依赖全部经构造注入的**抽象**（`kernel/contract` 的 `DiskKv` / `DiskVault` /
/// `AiHttpClient`），不 import 任何 `base` / `surface` 实现 —— 分层干净、
/// 可单测（可注入 `InMemoryKv` / `InMemoryVault` / 假 `AiHttpClient`）。
///
/// ## 与 fork 的差别（质量点）
/// - 不再是一个 1000+ 行的 god class：文件提交 / 构建轮询 / 审计不在这里，
///   它们要么是独立的 `domain/gh` 服务，要么经 [AiTool] 注入；
/// - 密钥只进 `DiskVault`，日志零密钥、零响应体；
/// - 工具执行异常**不**打断会话，作为 `tool_result` 回给模型。
library;

import 'dart:convert';

import '../../kernel/contract/ai_client.dart';
import '../../kernel/contract/disk_store.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'ai_tool.dart';

/// AI 业务错误（区别于传输层的 [AiTransportException]）。
class AiException implements Exception {
  const AiException(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() => 'AiException($code)${detail.isEmpty ? '' : '：$detail'}';
}

/// AI 服务。
class AiService {
  AiService({
    required DiskKv store,
    required DiskVault vault,
    required AiHttpClient http,
    List<AiTool> tools = const <AiTool>[],
  })  : _store = store,
        _vault = vault,
        _http = http,
        _tools = <String, AiTool>{for (final AiTool t in tools) t.name: t};

  static const String _settingsKey = 'ai.settings';
  static const String _secretKey = 'ai.secret';
  static const String _convPrefix = 'ai.conv.';
  static const String _auditPrefix = 'ai.audit.';
  static const int _maxRounds = 6;

  /// 每个账号的审计条目上限（防止无界增长）。
  static const int _maxAudit = 200;

  final DiskKv _store;
  final DiskVault _vault;
  final AiHttpClient _http;
  final Map<String, AiTool> _tools;

  // ── 设置与密钥 ────────────────────────────────────────────────────────

  Future<AiSettings> settings() async {
    final String? raw = await _store.read(_settingsKey);
    if (raw == null) {
      return AiSettings.empty;
    }
    try {
      return AiSettings.fromJson(jsonDecode(raw));
    } on FormatException {
      return AiSettings.empty;
    }
  }

  Future<void> saveSettings(AiSettings s) =>
      _store.write(_settingsKey, jsonEncode(s.toJson()));

  Future<String?> readKey() => _vault.readSecret(_secretKey);

  Future<void> writeKey(String key) => _vault.writeSecret(_secretKey, key);

  Future<void> clearKey() => _vault.deleteSecret(_secretKey);

  Future<bool> hasKey() async {
    final String? k = await _vault.readSecret(_secretKey);
    return k != null && k.isNotEmpty;
  }

  // ── 会话 ──────────────────────────────────────────────────────────────

  Future<List<AiConversation>> conversations(String accountId) async {
    final List<AiConversation> out = <AiConversation>[];
    for (final String key in await _store.keys()) {
      if (!key.startsWith(_convPrefix)) {
        continue;
      }
      final String? raw = await _store.read(key);
      if (raw == null) {
        continue;
      }
      try {
        final AiConversation c = AiConversation.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        );
        if (c.accountId == accountId) {
          out.add(c);
        }
      } on Object {
        // 损坏的会话条目跳过，不拖垮整个列表。
      }
    }
    out.sort((AiConversation a, AiConversation b) =>
        b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> saveConversation(AiConversation c) =>
      _store.write('$_convPrefix${c.id}', jsonEncode(c.toJson()));

  Future<void> deleteConversation(String id) =>
      _store.remove('$_convPrefix$id');

  // ── 审计（AI 操作永久落盘）────────────────────────────────────────────

  /// 该账号的 AI 操作审计记录（按时间升序，最多 [_maxAudit] 条）。
  Future<List<Map<String, Object?>>> audit(String accountId) async {
    final String? raw = await _store.read('$_auditPrefix$accountId');
    if (raw == null) {
      return const <Map<String, Object?>>[];
    }
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> e) => Map<String, Object?>.from(e))
          .toList();
    } on Object {
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> _record(String accountId, Map<String, Object?> entry) async {
    final List<Map<String, Object?>> entries = await audit(accountId);
    entries.add(entry);
    if (entries.length > _maxAudit) {
      entries.removeRange(0, entries.length - _maxAudit);
    }
    await _store.write('$_auditPrefix$accountId', jsonEncode(entries));
  }

  static bool _isErrorResult(Object? result) =>
      result is Map && result.containsKey('error');

  // ── 补全 ──────────────────────────────────────────────────────────────

  /// 非流式补全（**带工具循环**）：模型要调工具就执行、回填结果，最多
  /// [_maxRounds] 轮。
  ///
  /// 返回**完整转录**（含工具轮次与终答），便于持久化整段会话；
  /// 终答即 `result.last`（`AiRole.assistant`）。
  Future<List<AiMessage>> complete(
    List<AiMessage> messages, {
    String accountId = '',
    int maxTokens = 4096,
  }) async {
    final AiSettings s = await settings();
    final String key = await _requireKey(s);
    final AiProvider provider = AiProvider(s.kind);
    final List<AiMessage> msgs = List<AiMessage>.of(messages);

    for (int round = 0; round < _maxRounds; round++) {
      final (String path, Map<String, Object?> body) = provider.buildChat(
        AiChatRequest(
          model: s.model,
          messages: msgs,
          tools: _toolSpecs(),
          maxTokens: maxTokens,
        ),
      );
      final AiHttpResponse res;
      try {
        res = await _http.send(
          s.baseUrl + path,
          headers: _authHeaders(s.kind, key),
          body: body,
        );
      } on AiTransportException catch (e) {
        // ★ 传输层错误在这里**转成业务错误**（`transport` 码）：UI 层只认
        //   `AiException` 一种类型，不用再 import kernel 的传输异常 ——
        //   此前 UI 只 catch `AiException`，传输层异常直接穿透成未捕获异常。
        throw AiException('transport', e.message);
      }
      if (!res.ok) {
        throw AiException('httpError', _errorDetail(res.statusCode, res.body));
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(res.body);
      } on FormatException catch (e) {
        // 200 + HTML 错误页（登录页 / CDN 拦截）等非 JSON 体：
        // 转成业务异常（UI 只认 AiException），不许裸逃逸。
        throw AiException(
          'badResponse',
          '响应不是合法 JSON（HTTP ${res.statusCode}）：${e.message}',
        );
      }

      final AiReply reply = provider.parseReply(decoded);
      if (reply.toolCalls.isEmpty) {
        msgs.add(AiMessage(
          role: AiRole.assistant,
          content: reply.content,
          toolCalls: reply.toolCalls,
        ));
        return msgs;
      }
      msgs.add(AiMessage(
        role: AiRole.assistant,
        content: reply.content,
        toolCalls: reply.toolCalls,
      ));
      for (final AiToolCall call in reply.toolCalls) {
        final Object? result = await _runTool(call);
        msgs.add(AiMessage(
          role: AiRole.tool,
          content: jsonEncode(result),
          toolCallId: call.id,
          name: call.name,
        ));
        // ★ AI 操作永久落盘（审计）：每执行一个工具就写一条，重启后仍在。
        if (accountId.isNotEmpty) {
          await _record(accountId, <String, Object?>{
            'at': DateTime.now().toIso8601String(),
            'tool': call.name,
            'args': call.arguments,
            'ok': !_isErrorResult(result),
            'result': result,
          });
        }
      }
    }
    throw const AiException('toolLoopLimit');
  }

  /// 流式补全（真实 SSE，**文本 only，不带工具**）。
  ///
  /// 逐段 `yield` 文本增量，供 UI 做打字机效果；不缓冲整段响应。
  Stream<String> completeStream(
    List<AiMessage> messages, {
    int maxTokens = 4096,
  }) async* {
    final AiSettings s = await settings();
    final String key = await _requireKey(s);
    final AiProvider provider = AiProvider(s.kind);
    final (String path, Map<String, Object?> body) = provider.buildChat(
      AiChatRequest(
        model: s.model,
        messages: messages,
        maxTokens: maxTokens,
        stream: true,
      ),
    );
    try {
      await for (final AiSseEvent evt in _http.stream(
        s.baseUrl + path,
        headers: _authHeaders(s.kind, key),
        body: body,
      )) {
        final String? data = evt.data;
        if (data == null || evt.isDone) {
          continue;
        }
        final AiStreamDelta d = provider.parseStreamChunk(data);
        // 结束帧也可能携带正文（Gemini 把最后一段文本与 finishReason 放
        // 同一帧）：必须先吐正文再 break，否则结尾被静默截断。
        if (d.content.isNotEmpty) {
          yield d.content;
        }
        if (d.finished) {
          break;
        }
      }
    } on AiTransportException catch (e) {
      // 同 `complete()`：传输错误统一转成 `AiException`（UI 只 catch 一种）。
      throw AiException('transport', e.message);
    }
  }

  /// 探测模型列表（供设置页下拉）。
  ///
  /// [config] 传入时用表单里的**当前值**（尚未保存）；否则读已持久化的设置。
  Future<List<String>> detectModels({String? key, AiSettings? config}) async {
    final AiSettings s = config ?? await settings();
    final String k = key ?? await _requireKey(s);
    final AiProvider provider = AiProvider(s.kind);
    final AiHttpResponse res;
    try {
      res = await _http.send(
        s.baseUrl + provider.modelListPath(),
        headers: _authHeaders(s.kind, k),
      );
    } on AiTransportException catch (e) {
      // 同 `complete()`：传输错误统一转成 `AiException`（UI 只 catch 一种）。
      throw AiException('transport', e.message);
    }
    if (!res.ok) {
      throw AiException('httpError', _errorDetail(res.statusCode, res.body));
    }
    final Object? rawList;
    try {
      rawList = jsonDecode(res.body);
    } on FormatException catch (e) {
      throw AiException(
        'badResponse',
        '模型列表响应不是合法 JSON（HTTP ${res.statusCode}）：${e.message}',
      );
    }

    return provider.parseModelList(rawList);
  }

  // ── 内部 ──────────────────────────────────────────────────────────────

  List<AiToolSpec> _toolSpecs() => _tools.values
      .map((AiTool t) => AiToolSpec(
            name: t.name,
            description: t.description,
            parameters: t.parameters,
          ))
      .toList();

  Future<Object?> _runTool(AiToolCall call) async {
    final AiTool? tool = _tools[call.name];
    if (tool == null) {
      return <String, Object?>{'error': '未知工具：${call.name}'};
    }
    try {
      return await tool.run(call.arguments);
    } on Object catch (e) {
      return <String, Object?>{'error': '$e'};
    }
  }

  Future<String> _requireKey(AiSettings s) async {
    if (!s.enabled) {
      throw const AiException('disabled');
    }
    final String? key = await _vault.readSecret(_secretKey);
    if (key == null || key.isEmpty) {
      throw const AiException('noKey');
    }
    return key;
  }

  Map<String, String> _authHeaders(AiProviderKind kind, String key) {
    switch (kind) {
      case AiProviderKind.openai:
        return <String, String>{'authorization': 'Bearer $key'};
      case AiProviderKind.anthropic:
        return <String, String>{
          'x-api-key': key,
          'anthropic-version': '2023-06-01',
        };
      case AiProviderKind.gemini:
        return <String, String>{'x-goog-api-key': key};
    }
  }

  /// 从错误响应体里抽人话摘要（各家形状不同），只留一行、截断防刷屏。
  ///
  /// 抽不到就用状态码兜底——但绝不把 body 原样塞给用户（可能很长/含内部信息）。
  static String _errorDetail(int statusCode, String body) {
    String? msg;
    final Object? raw;
    try {
      raw = jsonDecode(body);
    } on FormatException {
      raw = null;
    }
    if (raw is Map) {
      final Object? err = raw['error'];
      if (err is Map) {
        final Object? m = err['message'];
        if (m is String && m.isNotEmpty) {
          msg = m;
        }
      } else if (err is String && err.isNotEmpty) {
        msg = err;
      } else if (raw['message'] is String) {
        msg = raw['message'] as String;
      }
    }
    if (msg == null || msg.isEmpty) {
      return 'HTTP $statusCode';
    }
    msg = msg.replaceAll('\n', ' ');
    if (msg.length > 160) {
      msg = '${msg.substring(0, 160)}…';
    }
    return 'HTTP $statusCode：$msg';
  }
}
