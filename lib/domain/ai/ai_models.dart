/// AI 的数据契约：只包含可序列化数据，不持有 GitHub 令牌。
library;

import 'dart:convert';

/// 两条网络通道都由装配根注入；业务层不依赖底座实现。
typedef AiGithubRequest = Future<Object?> Function(
  String method,
  String path,
  Map<String, Object?>? body,
  Map<String, String> query,
);
typedef AiProviderRequest = Future<Map<String, dynamic>> Function(
  AiSettings settings,
  String endpoint,
  String key,
  Map<String, Object?>? body,
);
typedef AiConfirmation = Future<bool> Function(AiProposal proposal);

/// 可读的业务错误键由展示层翻译。
class AiException implements Exception {
  const AiException(this.code, [this.detail = '']);
  final String code;
  final String detail;
  @override
  String toString() => '$code${detail.isEmpty ? '' : ': $detail'}';
}

/// 仅保存非敏感配置；密钥单独写入系统保险库。
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.model = '',
    this.kind = 'openai',
    this.baseUrl = 'https://api.deepseek.com',
  });
  final bool enabled;
  final String model;
  final String kind;
  final String baseUrl;
  String get keyId => 'ai.key.$kind.${Uri.encodeComponent(baseUrl)}';
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'model': model,
    'kind': kind,
    'baseUrl': baseUrl,
  };
  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
    enabled: json['enabled'] == true,
    model: json['model'] as String? ?? '',
    kind: json['kind'] as String? ?? 'openai',
    baseUrl: json['baseUrl'] as String? ?? 'https://api.deepseek.com',
  );
}

/// 一条聊天消息；附件只保存 GitHub 产物 ID，不保存短期签名地址。
class AiMessage {
  AiMessage(
    this.role,
    this.content, {
    DateTime? at,
    this.artifacts = const [],
    this.notice = false,
  }) : at = at ?? DateTime.now();
  final bool notice;
  final String role;
  final String content;
  final DateTime at;
  final List<Map<String, dynamic>> artifacts;
  Map<String, Object?> toJson() => {
    'role': role,
    'content': content,
    'at': at.toIso8601String(),
    'artifacts': artifacts,
    'notice': notice,
  };
  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    json['role'] as String,
    json['content'] as String,
    at: DateTime.parse(json['at'] as String),
    notice: json['notice'] == true,
    artifacts: (json['artifacts'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

/// 会话按 GitHub 账号隔离，每个会话持有独立仓库上下文。
class AiConversation {
  AiConversation({
    required this.id,
    required this.accountId,
    this.repo = '',
    this.branch = '',
    List<AiMessage>? messages,
  }) : messages = messages ?? [];
  final String id;
  final String accountId;
  String repo;
  String branch;
  final List<AiMessage> messages;
  Map<String, Object?> toJson() => {
    'id': id,
    'accountId': accountId,
    'repo': repo,
    'branch': branch,
    'messages': messages.map((e) => e.toJson()).toList(),
  };
  factory AiConversation.fromJson(Map<String, dynamic> json) => AiConversation(
    id: json['id'] as String,
    accountId: json['accountId'] as String,
    repo: json['repo'] as String? ?? '',
    branch: json['branch'] as String? ?? '',
    messages: (json['messages'] as List)
        .map((e) => AiMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// 文件差异是不可变快照，确认之后不会再次读取模型生成的内容。
class AiFileChange {
  const AiFileChange({
    required this.path,
    required this.before,
    required this.after,
    this.mode = '100644',
  });
  final String path;
  final String? before;
  final String? after;
  final String mode;
  Map<String, Object?> toJson() => {
    'path': path,
    'before': before,
    'after': after,
    'mode': mode,
  };
}

/// 所有写操作共用确认对象，固定账号、仓库、分支和远端基线。
class AiProposal {
  AiProposal({
    required this.operation,
    required this.accountId,
    required this.repo,
    required this.branch,
    required this.payload,
    this.conversationId = '',
    this.baseSha = '',
    this.baseTree = '',
    List<AiFileChange> files = const [],
  }) : files = List.unmodifiable(files),
       payloadJson = jsonEncode(payload);
  final String conversationId;
  final String operation;
  final String accountId;
  final String repo;
  final String branch;
  final String baseSha;
  final String baseTree;
  final Map<String, Object?> payload;
  final String payloadJson;
  final List<AiFileChange> files;
}
