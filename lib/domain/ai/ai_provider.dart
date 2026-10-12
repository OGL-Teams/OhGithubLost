/// L2 · provider 协议适配（纯函数，无 I/O、无状态）。
///
/// 把统一的内部表示（[AiMessage] + [AiToolSpec]）翻译成 OpenAI 兼容 /
/// Claude Messages / Gemini GenerateContent 三种协议，并把三家的响应统一
/// 折回 [AiReply] / [AiStreamDelta]。
///
/// 密钥**不在**这里：请求头由传输层（`base`）按 provider 类型加。
library;

import 'dart:convert';

import 'ai_models.dart';

/// 一个工具声明（给模型看的函数 schema）。
class AiToolSpec {
  const AiToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

/// 一次聊天补全的中间请求（已脱敏，不含密钥）。
class AiChatRequest {
  const AiChatRequest({
    required this.model,
    required this.messages,
    this.tools = const <AiToolSpec>[],
    this.maxTokens = 4096,
    this.stream = false,
  });

  final String model;
  final List<AiMessage> messages;
  final List<AiToolSpec> tools;
  final int maxTokens;

  /// 是否流式（SSE）。
  final bool stream;
}

/// 一次补全的统一回复。
class AiReply {
  const AiReply({
    this.content = '',
    this.toolCalls = const <AiToolCall>[],
    this.finished = false,
  });

  final String content;
  final List<AiToolCall> toolCalls;

  /// `finish_reason` 命中 stop / end_turn 等「正常结束」。
  final bool finished;
}

/// 一个流式增量（已从 provider 的 delta 折成统一形态）。
class AiStreamDelta {
  const AiStreamDelta({this.content = '', this.finished = false});

  /// 本帧新增的文本（可为空：只携带结束标记或工具调用）。
  final String content;
  final bool finished;
}

/// provider 协议适配器。
class AiProvider {
  const AiProvider(this.kind);

  final AiProviderKind kind;

  // ── 请求构建 ──────────────────────────────────────────────────────────

  /// 聊天请求的相对路径 + 请求体（不含密钥头）。
  (String, Map<String, Object?>) buildChat(AiChatRequest req) {
    switch (kind) {
      case AiProviderKind.openai:
        return ('/chat/completions', _openaiBody(req));
      case AiProviderKind.anthropic:
        return ('/messages', _anthropicBody(req));
      case AiProviderKind.gemini:
        final String suffix =
            req.stream ? ':streamGenerateContent?alt=sse' : ':generateContent';
        return (
          '/models/${Uri.encodeComponent(req.model)}$suffix',
          _geminiBody(req),
        );
    }
  }

  Map<String, Object?> _openaiBody(AiChatRequest req) {
    return <String, Object?>{
      'model': req.model,
      'max_tokens': req.maxTokens,
      if (req.stream) 'stream': true,
      'messages': req.messages
          .map((AiMessage m) => m.toJson())
          .toList(),
      if (req.tools.isNotEmpty)
        'tools': req.tools
            .map((AiToolSpec t) => <String, Object?>{
                  'type': 'function',
                  'function': <String, Object?>{
                    'name': t.name,
                    'description': t.description,
                    'parameters': t.parameters,
                  },
                })
            .toList(),
    };
  }

  Map<String, Object?> _anthropicBody(AiChatRequest req) {
    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    String system = '';
    for (final AiMessage m in req.messages) {
      if (m.role == AiRole.system) {
        system = m.content;
        continue;
      }
      final String role = m.role == AiRole.assistant ? 'assistant' : 'user';
      final List<Object?> parts = <Object?>[];
      if (m.role == AiRole.tool) {
        parts.add(<String, Object?>{
          'type': 'tool_result',
          'tool_use_id': m.toolCallId,
          'content': m.content,
        });
      } else {
        if (m.content.isNotEmpty) {
          parts.add(<String, Object?>{'type': 'text', 'text': m.content});
        }
        for (final AiToolCall c in m.toolCalls) {
          parts.add(<String, Object?>{
            'type': 'tool_use',
            'id': c.id,
            'name': c.name,
            'input': c.arguments,
          });
        }
      }
      if (parts.isEmpty) {
        continue;
      }
      if (messages.isNotEmpty && messages.last['role'] == role) {
        (messages.last['content'] as List<Object?>).addAll(parts);
      } else {
        messages.add(<String, Object?>{'role': role, 'content': parts});
      }
    }
    return <String, Object?>{
      'model': req.model,
      'max_tokens': req.maxTokens,
      if (req.stream) 'stream': true,
      'system': system,
      'messages': messages,
      if (req.tools.isNotEmpty)
        'tools': req.tools
            .map((AiToolSpec t) => <String, Object?>{
                  'name': t.name,
                  'description': t.description,
                  'input_schema': t.parameters,
                })
            .toList(),
    };
  }

  Map<String, Object?> _geminiBody(AiChatRequest req) {
    final List<Map<String, Object?>> contents = <Map<String, Object?>>[];
    String system = '';
    final Map<String, String> callNames = <String, String>{};
    for (final AiMessage m in req.messages) {
      if (m.role == AiRole.system) {
        system = m.content;
        continue;
      }
      final String role = m.role == AiRole.assistant ? 'model' : 'user';
      final List<Object?> parts = <Object?>[];
      if (m.role == AiRole.tool) {
        Object? decoded = m.content;
        try {
          decoded = jsonDecode(m.content);
        } on FormatException {
          decoded = m.content;
        }
        parts.add(<String, Object?>{
          'functionResponse': <String, Object?>{
            'name': callNames[m.toolCallId] ?? '',
            'response': decoded is Map ? decoded : <String, Object?>{'result': decoded},
          },
        });
      } else {
        for (final AiToolCall c in m.toolCalls) {
          callNames[c.id] = c.name;
          parts.add(<String, Object?>{
            'functionCall': <String, Object?>{
              'name': c.name,
              'args': c.arguments,
            },
          });
        }
        if (m.content.isNotEmpty) {
          parts.add(<String, Object?>{'text': m.content});
        }
      }
      if (parts.isEmpty) {
        continue;
      }
      if (contents.isNotEmpty && contents.last['role'] == role) {
        (contents.last['parts'] as List<Object?>).addAll(parts);
      } else {
        contents.add(<String, Object?>{'role': role, 'parts': parts});
      }
    }
    return <String, Object?>{
      'systemInstruction': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{'text': system},
        ],
      },
      'contents': contents,
      'generationConfig': <String, Object?>{'maxOutputTokens': req.maxTokens},
      if (req.tools.isNotEmpty)
        'tools': <Object?>[
          <String, Object?>{
            'functionDeclarations': req.tools
                .map((AiToolSpec t) => <String, Object?>{
                      'name': t.name,
                      'description': t.description,
                      'parametersJsonSchema': t.parameters,
                    })
                .toList(),
          },
        ],
    };
  }

  // ── 响应解析 ──────────────────────────────────────────────────────────

  /// 把 provider 的完整响应体折成 [AiReply]。
  AiReply parseReply(Object? raw) {
    if (raw is! Map) {
      return const AiReply();
    }
    switch (kind) {
      case AiProviderKind.openai:
        return _parseOpenAi(raw);
      case AiProviderKind.anthropic:
        return _parseAnthropic(raw);
      case AiProviderKind.gemini:
        return _parseGemini(raw);
    }
  }

  AiReply _parseOpenAi(Map<Object?, Object?> raw) {
    final List<Object?> choices = (raw['choices'] as List?) ?? const <Object?>[];
    if (choices.isEmpty) {
      return const AiReply();
    }
    final Map<Object?, Object?> choice = choices.first as Map;
    final Map<Object?, Object?> message =
        (choice['message'] as Map?) ?? const <Object?, Object?>{};
    final List<Object?> calls = (message['tool_calls'] as List?) ?? const <Object?>[];
    return AiReply(
      content: '${message['content'] ?? ''}',
      toolCalls: calls.whereType<Map>().map(AiToolCall.fromRaw).toList(),
      finished: choice['finish_reason'] == 'stop',
    );
  }

  AiReply _parseAnthropic(Map<Object?, Object?> raw) {
    final List<Object?> parts = (raw['content'] as List?) ?? const <Object?>[];
    final List<AiToolCall> calls = <AiToolCall>[];
    final List<String> texts = <String>[];
    for (final Object? p in parts) {
      if (p is! Map) {
        continue;
      }
      if (p['type'] == 'text') {
        texts.add('${p['text'] ?? ''}');
      } else if (p['type'] == 'tool_use') {
        calls.add(AiToolCall(
          id: '${p['id'] ?? ''}',
          name: '${p['name'] ?? ''}',
          arguments: (p['input'] is Map)
              ? Map<String, Object?>.from(p['input'] as Map)
              : const <String, Object?>{},
        ));
      }
    }
    return AiReply(
      content: texts.join('\n'),
      toolCalls: calls,
      finished: raw['stop_reason'] != 'max_tokens',
    );
  }

  AiReply _parseGemini(Map<Object?, Object?> raw) {
    final List<Object?> candidates =
        (raw['candidates'] as List?) ?? const <Object?>[];
    if (candidates.isEmpty) {
      return const AiReply();
    }
    final Map<Object?, Object?> candidate = candidates.first as Map;
    final Map<Object?, Object?> content =
        (candidate['content'] as Map?) ?? const <Object?, Object?>{};
    final List<Object?> parts = (content['parts'] as List?) ?? const <Object?>[];
    final List<AiToolCall> calls = <AiToolCall>[];
    final List<String> texts = <String>[];
    int seq = 0;
    for (final Object? p in parts) {
      if (p is! Map) {
        continue;
      }
      if (p['text'] is String && p['thought'] != true) {
        texts.add(p['text'] as String);
      }
      final Map<Object?, Object?> fn = (p['functionCall'] as Map?) ?? const {};
      if (fn.isNotEmpty) {
        calls.add(AiToolCall(
          id: 'gemini_${seq++}',
          name: '${fn['name'] ?? ''}',
          arguments: (fn['args'] is Map)
              ? Map<String, Object?>.from(fn['args'] as Map)
              : const <String, Object?>{},
        ));
      }
    }
    return AiReply(
      content: texts.join('\n'),
      toolCalls: calls,
      finished: candidate['finishReason'] != 'MAX_TOKENS',
    );
  }

  /// 解析一个流式 SSE 帧（`data:` 里的 JSON）为 [AiStreamDelta]。
  ///
  /// 仅处理「文本增量 + 结束」；工具调用的流式增量由服务层按 `delta.tool_calls`
  /// 自行累积（各 provider 形态差异大，这里不硬塞进文本流）。
  AiStreamDelta parseStreamChunk(String data) {
    if (data == '[DONE]') {
      return const AiStreamDelta(finished: true);
    }
    final Object? raw;
    try {
      raw = jsonDecode(data);
    } on FormatException {
      return const AiStreamDelta();
    }
    if (raw is! Map) {
      return const AiStreamDelta();
    }
    switch (kind) {
      case AiProviderKind.openai:
        final List<Object?> choices =
            (raw['choices'] as List?) ?? const <Object?>[];
        if (choices.isEmpty) {
          return const AiStreamDelta();
        }
        final Map<Object?, Object?> choice = choices.first as Map;
        final Map<Object?, Object?> delta =
            (choice['delta'] as Map?) ?? const <Object?, Object?>{};
        return AiStreamDelta(
          content: '${delta['content'] ?? ''}',
          finished: choice['finish_reason'] != null,
        );
      case AiProviderKind.anthropic:
        // 流式事件形态：`content_block_delta` 携带 `delta.text`；
        // 结束哨兵是 `message_stop`（或 `message_delta` 的 stop_reason）。
        if (raw['type'] == 'message_stop') {
          return const AiStreamDelta(finished: true);
        }
        if (raw['type'] == 'content_block_delta') {
          final Map<Object?, Object?> delta =
              (raw['delta'] as Map?) ?? const <Object?, Object?>{};
          if (delta['type'] == 'text_delta') {
            return AiStreamDelta(content: '${delta['text'] ?? ''}');
          }
        }
        return const AiStreamDelta();
      case AiProviderKind.gemini:
        final List<Object?> candidates =
            (raw['candidates'] as List?) ?? const <Object?>[];
        if (candidates.isEmpty) {
          return const AiStreamDelta();
        }
        final Map<Object?, Object?> candidate = candidates.first as Map;
        final Map<Object?, Object?> content =
            (candidate['content'] as Map?) ?? const <Object?, Object?>{};
        final List<Object?> parts = (content['parts'] as List?) ?? const <Object?>[];
        final List<String> texts = <String>[];
        for (final Object? p in parts) {
          if (p is Map && p['text'] is String && p['thought'] != true) {
            texts.add(p['text'] as String);
          }
        }
        return AiStreamDelta(
          content: texts.join(),
          finished: candidate['finishReason'] != null,
        );
    }
  }

  /// 拉模型列表的相对路径（返回 `(path, 是否需分页)` —— 分页解析交给服务层）。
  String modelListPath() {
    switch (kind) {
      case AiProviderKind.openai:
      case AiProviderKind.anthropic:
        return '/models';
      case AiProviderKind.gemini:
        return '/models';
    }
  }

  /// 从「拉模型列表」的响应里抽模型 id 列表。
  List<String> parseModelList(Object? raw) {
    if (raw is! Map) {
      return const <String>[];
    }
    switch (kind) {
      case AiProviderKind.openai:
      case AiProviderKind.anthropic:
        return (raw['data'] as List? ?? const <Object?>[])
            .whereType<Map>()
            .map((Object? e) => '${(e as Map)['id'] ?? ''}')
            .where((String s) => s.isNotEmpty)
            .toList();
      case AiProviderKind.gemini:
        return (raw['models'] as List? ?? const <Object?>[])
            .whereType<Map>()
            .where((Object? e) =>
                ((e as Map)['supportedGenerationMethods'] as List? ?? const [])
                    .contains('generateContent'))
            .map((Object? e) => '${(e as Map)['name'] ?? ''}'.replaceFirst('models/', ''))
            .where((String s) => s.isNotEmpty)
            .toList();
    }
  }
}
