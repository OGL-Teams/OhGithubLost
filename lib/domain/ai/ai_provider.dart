/// 统一 OpenAI 兼容、Claude Messages 和 Gemini GenerateContent 的工具调用。
library;

import 'dart:convert';

import 'ai_models.dart';

typedef AiHttpSend = Future<Map<String, dynamic>> Function(
  String url,
  Map<String, String> headers,
  Map<String, Object?>? body,
);

class AiProvider {
  AiProvider(this.http);
  final AiHttpSend http;

  /// 服务地址必须由用户在设置里明确选择；禁止把凭据嵌入 URL。
  static void validate(AiSettings config) {
    final uri = Uri.tryParse(config.baseUrl);
    if (!['openai', 'anthropic', 'gemini'].contains(config.kind) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AiException('invalidEndpoint');
    }
  }

  Future<Map<String, dynamic>> request(
    AiSettings config,
    String endpoint,
    String key,
    Map<String, Object?>? body,
  ) async {
    validate(config);
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      if (config.kind == 'openai') 'authorization': 'Bearer $key',
      if (config.kind == 'anthropic') ...{
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      if (config.kind == 'gemini') 'x-goog-api-key': key,
    };
    if (endpoint == 'models') {
      final all = <Map<String, dynamic>>[];
      String suffix = '/models';
      for (var page = 0; page < 20; page++) {
        final result = await http('$base$suffix', headers, null);
        if (config.kind == 'gemini') {
          all.addAll(
            (result['models'] as List? ?? [])
                .whereType<Map>()
                .where(
                  (e) => (e['supportedGenerationMethods'] as List? ?? [])
                      .contains('generateContent'),
                )
                .map(
                  (e) => <String, dynamic>{
                    'id': '${e['name']}'.replaceFirst('models/', ''),
                  },
                ),
          );
          final next = result['nextPageToken'] as String?;
          if (next == null || next.isEmpty) {
            return {'data': all};
          }
          suffix = '/models?pageToken=${Uri.encodeQueryComponent(next)}';
        } else {
          all.addAll(
            (result['data'] as List? ?? []).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e),
            ),
          );
          if (config.kind != 'anthropic' || result['has_more'] != true) {
            return {'data': all};
          }
          final last = result['last_id'] as String?;
          if (last == null) {
            throw const AiException('invalidResponse');
          }
          suffix = '/models?after_id=${Uri.encodeQueryComponent(last)}';
        }
      }
      throw const AiException('modelLimit');
    }
    if (endpoint != 'chat/completions' || body == null) {
      throw const AiException('invalidResponse');
    }
    if (config.kind == 'openai') {
      // 部分推理模型不接受 max_tokens；统一使用较新的输出预算参数。
      final payload = {...body};
      if (Uri.parse(base).host == 'api.openai.com') {
        payload['max_completion_tokens'] = payload.remove('max_tokens');
      }
      return http(
        '$base/chat/completions',
        headers,
        Map<String, Object?>.from(payload)..remove('_provider_parts'),
      );
    }
    if (config.kind == 'anthropic') {
      final messages = <Map<String, Object?>>[];
      String system = '';
      for (final value in body['messages'] as List) {
        final message = value as Map;
        if (message['role'] == 'system') {
          system = message['content'] as String;
          continue;
        }
        final role = message['role'] == 'assistant' ? 'assistant' : 'user';
        final parts = <Object?>[];
        if (message['role'] == 'tool') {
          parts.add({
            'type': 'tool_result',
            'tool_use_id': message['tool_call_id'],
            'content': message['content'],
          });
        } else if (message['_provider_parts'] is List) {
          parts.addAll(message['_provider_parts'] as List);
        } else {
          if (message['content'] is String &&
              (message['content'] as String).isNotEmpty) {
            parts.add({'type': 'text', 'text': message['content']});
          }
          for (final call in message['tool_calls'] as List? ?? []) {
            final fn = (call as Map)['function'] as Map;
            parts.add({
              'type': 'tool_use',
              'id': call['id'],
              'name': fn['name'],
              'input': jsonDecode(fn['arguments'] as String),
            });
          }
        }
        if (parts.isEmpty) {
          continue;
        }
        if (messages.isNotEmpty && messages.last['role'] == role) {
          (messages.last['content'] as List).addAll(parts);
        } else {
          messages.add({'role': role, 'content': parts});
        }
      }
      final result = await http('$base/messages', headers, {
        'model': body['model'],
        'max_tokens': body['max_tokens'],
        'system': system,
        'messages': messages,
        'tools': (body['tools'] as List).map((e) {
          final fn = (e as Map)['function'] as Map;
          return {
            'name': fn['name'],
            'description': fn['description'],
            'input_schema': fn['parameters'],
          };
        }).toList(),
      });
      final parts = result['content'] as List? ?? [];
      return {
        'choices': [
          {
            'finish_reason': result['stop_reason'] == 'max_tokens'
                ? 'length'
                : 'stop',
            'message': {
              'role': 'assistant',
              '_provider_parts': parts,
              'content': parts
                  .whereType<Map>()
                  .where((e) => e['type'] == 'text')
                  .map((e) => e['text'])
                  .join('\n'),
              'tool_calls': parts
                  .whereType<Map>()
                  .where((e) => e['type'] == 'tool_use')
                  .map(
                    (e) => {
                      'id': e['id'],
                      'type': 'function',
                      'function': {
                        'name': e['name'],
                        'arguments': jsonEncode(e['input']),
                      },
                    },
                  )
                  .toList(),
            },
          },
        ],
      };
    }
    final contents = <Map<String, Object?>>[];
    final callNames = <String, String>{};
    String system = '';
    for (final raw in body['messages'] as List) {
      final message = raw as Map;
      if (message['role'] == 'system') {
        system = message['content'] as String;
        continue;
      }
      final role = message['role'] == 'assistant' ? 'model' : 'user';
      final parts = <Object?>[];
      if (message['role'] == 'tool') {
        final decoded = jsonDecode(message['content'] as String);
        parts.add({
          'functionResponse': {
            'name': callNames[message['tool_call_id']],
            'response': decoded is Map ? decoded : {'result': decoded},
          },
        });
      } else {
        for (final call in message['tool_calls'] as List? ?? []) {
          callNames[(call as Map)['id'] as String] =
              (call['function'] as Map)['name'] as String;
        }
        if (message['_provider_parts'] is List) {
          // Gemini 的 thoughtSignature 必须原样回传，不能丢弃。
          parts.addAll(message['_provider_parts'] as List);
        } else if (message['content'] is String &&
            (message['content'] as String).isNotEmpty) {
          parts.add({'text': message['content']});
        }
      }
      if (parts.isEmpty) {
        continue;
      }
      if (contents.isNotEmpty && contents.last['role'] == role) {
        (contents.last['parts'] as List).addAll(parts);
      } else {
        contents.add({'role': role, 'parts': parts});
      }
    }
    final model = Uri.encodeComponent(body['model'] as String);
    final result = await http('$base/models/$model:generateContent', headers, {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': contents,
      'generationConfig': {'maxOutputTokens': body['max_tokens']},
      'tools': [
        {
          'functionDeclarations': (body['tools'] as List).map((e) {
            final fn = (e as Map)['function'] as Map;
            return {
              'name': fn['name'],
              'description': fn['description'],
              'parametersJsonSchema': fn['parameters'],
            };
          }).toList(),
        },
      ],
    });
    final candidates = result['candidates'] as List? ?? [];
    if (candidates.isEmpty) {
      throw const AiException('invalidResponse');
    }
    final candidate = candidates.first as Map;
    final parts = (candidate['content'] as Map?)?['parts'] as List? ?? [];
    var sequence = 0;
    return {
      'choices': [
        {
          'finish_reason': candidate['finishReason'] == 'MAX_TOKENS'
              ? 'length'
              : 'stop',
          'message': {
            'role': 'assistant',
            '_provider_parts': parts,
            'content': parts
                .whereType<Map>()
                .where((e) => e['text'] is String && e['thought'] != true)
                .map((e) => e['text'])
                .join('\n'),
            'tool_calls': parts
                .whereType<Map>()
                .where((e) => e['functionCall'] is Map)
                .map((e) {
                  final fn = e['functionCall'] as Map;
                  return {
                    'id': 'gemini_${sequence++}',
                    'type': 'function',
                    'function': {
                      'name': fn['name'],
                      'arguments': jsonEncode(fn['args'] ?? {}),
                    },
                  };
                })
                .toList(),
          },
        },
      ],
    };
  }
}
