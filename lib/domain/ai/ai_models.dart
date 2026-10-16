/// L2 · AI 领域模型（纯数据，无 I/O、无 Flutter 依赖）。
///
/// 这些 DTO 由 `surface/types.dart` 门面按需 re-export 给页面；
/// 页面不得直接 import 本文件（分层纪律）。
library;

import 'dart:convert';

/// 支持的 provider 协议族。
enum AiProviderKind {
  openai,
  anthropic,
  gemini;

  static AiProviderKind? fromName(String? name) {
    for (final AiProviderKind k in AiProviderKind.values) {
      if (k.name == name) {
        return k;
      }
    }
    return null;
  }
}

/// 一条消息的角色。
enum AiRole {
  system,
  user,
  assistant,
  tool;

  static AiRole fromName(String? name) {
    for (final AiRole r in AiRole.values) {
      if (r.name == name) {
        return r;
      }
    }
    return AiRole.user;
  }
}

/// AI 的持久化设置（不含密钥，密钥单独走 `DiskVault`）。
class AiSettings {
  const AiSettings({
    required this.enabled,
    required this.kind,
    required this.model,
    required this.baseUrl,
  });

  final bool enabled;
  final AiProviderKind kind;
  final String model;

  /// 去尾斜杠后的纯 HTTPS 端点。
  final String baseUrl;

  static const AiSettings empty = AiSettings(
      enabled: false, kind: AiProviderKind.openai, model: '', baseUrl: '');

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'kind': kind.name,
        'model': model,
        'baseUrl': baseUrl,
      };

  static AiSettings fromJson(Object? raw) {
    if (raw is! Map) {
      return AiSettings.empty;
    }
    final String base =
        '${raw['baseUrl'] ?? ''}'.replaceAll(RegExp(r'/+$'), '');
    return AiSettings(
      enabled: raw['enabled'] == true,
      kind: AiProviderKind.fromName('${raw['kind']}') ?? AiProviderKind.openai,
      model: '${raw['model'] ?? ''}',
      baseUrl: base,
    );
  }
}

/// 一次工具调用（模型请求执行某个函数）。
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;

  /// 已解析成对象的参数（解析失败时为空 Map，绝不因坏参数崩掉整条链路）。
  final Map<String, Object?> arguments;

  static AiToolCall fromRaw(Map<Object?, Object?> raw) {
    final Map<Object?, Object?> fn =
        (raw['function'] as Map?) ?? const <Object?, Object?>{};
    final Object? argsRaw = fn['arguments'];
    Map<String, Object?> args = const <String, Object?>{};
    if (argsRaw is String && argsRaw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(argsRaw);
        if (decoded is Map) {
          args = Map<String, Object?>.from(decoded);
        }
      } on FormatException {
        args = const <String, Object?>{};
      }
    }
    return AiToolCall(
      id: '${raw['id'] ?? ''}',
      name: '${fn['name'] ?? ''}',
      arguments: args,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': 'function',
        'function': <String, Object?>{
          'name': name,
          'arguments': jsonEncode(arguments)
        },
      };
}

/// 一条消息（内部统一表示，不随 provider 变化）。
class AiMessage {
  const AiMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const <AiToolCall>[],
    this.toolCallId,
    this.name,
  });

  final AiRole role;
  final String content;
  final List<AiToolCall> toolCalls;

  /// 当 [role] 为 [AiRole.tool] 时，回填给哪个 tool_call 的 id。
  final String? toolCallId;
  final String? name;

  bool get isEmpty =>
      content.isEmpty && toolCalls.isEmpty && !(role == AiRole.tool);

  Map<String, Object?> toJson() => <String, Object?>{
        'role': role.name,
        'content': content,
        if (toolCalls.isNotEmpty)
          'tool_calls': toolCalls.map((AiToolCall t) => t.toJson()).toList(),
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null) 'name': name,
      };

  static AiMessage fromJson(Map<String, Object?> raw) {
    final List<Object?> calls =
        (raw['tool_calls'] as List?) ?? const <Object?>[];
    return AiMessage(
      role: AiRole.fromName('${raw['role']}'),
      content: '${raw['content'] ?? ''}',
      toolCalls: calls
          .whereType<Map<Object?, Object?>>()
          .map(AiToolCall.fromRaw)
          .toList(),
      toolCallId: raw['tool_call_id'] as String?,
      name: raw['name'] as String?,
    );
  }
}

/// 一段会话。
class AiConversation {
  AiConversation({
    required this.id,
    required this.accountId,
    this.repo,
    this.title,
    List<AiMessage> messages = const <AiMessage>[],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : messages = List<AiMessage>.of(messages),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String accountId;

  /// 会话绑定的仓库（`owner/name`；可空 = 未绑定）。
  final String? repo;
  final String? title;
  final List<AiMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'accountId': accountId,
        if (repo != null) 'repo': repo,
        if (title != null) 'title': title,
        'messages': messages.map((AiMessage m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static AiConversation fromJson(Map<String, Object?> raw) {
    final List<Object?> msgs = (raw['messages'] as List?) ?? const <Object?>[];
    return AiConversation(
      id: '${raw['id'] ?? ''}',
      accountId: '${raw['accountId'] ?? ''}',
      repo: raw['repo'] as String?,
      title: raw['title'] as String?,
      messages: msgs
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) =>
              AiMessage.fromJson(Map<String, Object?>.from(m)))
          .toList(),
      createdAt: DateTime.tryParse('${raw['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${raw['updatedAt'] ?? ''}'),
    );
  }
}

/// 一个文件级变更提案（AI 编辑仓库时给用户审阅用）。
class AiFileChange {
  const AiFileChange({
    required this.path,
    this.before,
    this.after,
    required this.mode,
  });

  final String path;
  final String? before;
  final String? after;

  /// `create` / `update` / `delete`。
  final String mode;
}
