/// L2 · AI provider 协议适配纯函数测试（无 I/O、无网络、无状态）。
///
/// 覆盖 [AiProvider] 的三个纯函数：
/// - [AiProvider.parseStreamChunk]：SSE 帧（`data:` 剥掉后的 JSON / `[DONE]`）→ [AiStreamDelta]
/// - [AiProvider.parseReply]：三家完整响应体 → 统一 [AiReply]
/// - [AiProvider.buildChat]：三家协议（openai / claude / gemini）的路径与 body 形状
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ai/ai_models.dart';
import 'package:ohgithublost/domain/ai/ai_provider.dart';

void main() {
  group('parseStreamChunk', () {
    test('[DONE] 帧 → 结束标记', () {
      final AiStreamDelta d =
          const AiProvider(AiProviderKind.openai).parseStreamChunk('[DONE]');
      expect(d.finished, isTrue);
      expect(d.content, isEmpty);
    });

    test('空 data → 空增量', () {
      final AiStreamDelta d =
          const AiProvider(AiProviderKind.openai).parseStreamChunk('');
      expect(d.content, isEmpty);
      expect(d.finished, isFalse);
    });

    test('非法 JSON → 空增量（不抛）', () {
      final AiStreamDelta d =
          const AiProvider(AiProviderKind.openai).parseStreamChunk('not json');
      expect(d.content, isEmpty);
      expect(d.finished, isFalse);
    });

    test('JSON 不是对象（数字 / 数组）→ 空增量', () {
      const AiProvider p = AiProvider(AiProviderKind.openai);
      expect(p.parseStreamChunk('42').content, isEmpty);
      expect(p.parseStreamChunk('[1,2]').content, isEmpty);
    });

    test('openai：content 提取 + 无 finish_reason 未结束', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.openai)
          .parseStreamChunk(
              '{"choices":[{"delta":{"content":"你"},"finish_reason":null}]}');
      expect(d.content, '你');
      expect(d.finished, isFalse);
    });

    test('openai：finish_reason 命中 → 结束', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.openai)
          .parseStreamChunk(
              '{"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}');
      expect(d.finished, isTrue);
    });

    test('openai：choices 为空 → 空增量', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.openai)
          .parseStreamChunk('{"choices":[]}');
      expect(d.content, isEmpty);
      expect(d.finished, isFalse);
    });

    test('anthropic：content_block_delta/text_delta 提取文本', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.anthropic)
          .parseStreamChunk(
              '{"type":"content_block_delta","delta":{"type":"text_delta","text":"好"}}');
      expect(d.content, '好');
      expect(d.finished, isFalse);
    });

    test('anthropic：message_stop → 结束', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.anthropic)
          .parseStreamChunk('{"type":"message_stop"}');
      expect(d.finished, isTrue);
    });

    test('anthropic：非增量类型 → 空增量', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.anthropic)
          .parseStreamChunk('{"type":"message_start"}');
      expect(d.content, isEmpty);
      expect(d.finished, isFalse);
    });

    test('gemini：文本 + finishReason → 内容与结束', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.gemini)
          .parseStreamChunk(
              '{"candidates":[{"content":{"parts":[{"text":"hi"}]},"finishReason":"STOP"}]}');
      expect(d.content, 'hi');
      expect(d.finished, isTrue);
    });

    test('gemini：candidates 为空 → 空增量', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.gemini)
          .parseStreamChunk('{"candidates":[]}');
      expect(d.content, isEmpty);
      expect(d.finished, isFalse);
    });

    test('合约：输入应为剥掉 data: 前缀后的 JSON（带前缀整体判空）', () {
      final AiStreamDelta d = const AiProvider(AiProviderKind.openai)
          .parseStreamChunk('data: {"choices":[{"delta":{"content":"hi"}}]}');
      expect(d.content, isEmpty);
    });
  });

  group('parseReply', () {
    test('openai：普通文本回复', () {
      final AiReply reply = const AiProvider(AiProviderKind.openai).parseReply({
        'choices': [
          {
            'message': {'content': '你好'},
            'finish_reason': 'stop'
          }
        ]
      });
      expect(reply.content, '你好');
      expect(reply.finished, isTrue);
      expect(reply.toolCalls, isEmpty);
    });

    test('openai：带 tool_calls 的回复', () {
      final AiReply reply = const AiProvider(AiProviderKind.openai).parseReply({
        'choices': [
          {
            'message': {
              'content': '',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city":"北京"}'
                  }
                }
              ]
            },
            'finish_reason': 'tool_calls'
          }
        ]
      });
      expect(reply.content, isEmpty);
      expect(reply.finished, isFalse);
      expect(reply.toolCalls.single.name, 'get_weather');
      expect(reply.toolCalls.single.arguments, {'city': '北京'});
    });

    test('openai：空 choices → 空回复', () {
      final AiReply reply = const AiProvider(AiProviderKind.openai)
          .parseReply({'choices': <Object?>[]});
      expect(reply.content, isEmpty);
      expect(reply.finished, isFalse);
    });

    test('openai：非 Map 输入 → 空回复', () {
      final AiReply reply =
          const AiProvider(AiProviderKind.openai).parseReply('不是对象');
      expect(reply.content, isEmpty);
    });

    test('anthropic：文本 + tool_use', () {
      final AiReply reply =
          const AiProvider(AiProviderKind.anthropic).parseReply({
        'content': [
          {'type': 'text', 'text': 'hi'},
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'f',
            'input': {'a': 1}
          }
        ],
        'stop_reason': 'end_turn'
      });
      expect(reply.content, 'hi');
      expect(reply.toolCalls.single.name, 'f');
      expect(reply.toolCalls.single.arguments, {'a': 1});
      expect(reply.finished, isTrue);
    });

    test('anthropic：max_tokens 视为未正常结束', () {
      final AiReply reply = const AiProvider(AiProviderKind.anthropic)
          .parseReply({'content': <Object?>[], 'stop_reason': 'max_tokens'});
      expect(reply.finished, isFalse);
    });

    test('anthropic：多段文本用换行拼接', () {
      final AiReply reply =
          const AiProvider(AiProviderKind.anthropic).parseReply({
        'content': [
          {'type': 'text', 'text': 'a'},
          {'type': 'text', 'text': 'b'}
        ],
        'stop_reason': 'end_turn'
      });
      expect(reply.content, 'a\nb');
    });

    test('gemini：文本 + functionCall + STOP', () {
      final AiReply reply = const AiProvider(AiProviderKind.gemini).parseReply({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'hi'},
                {
                  'functionCall': {
                    'name': 'f',
                    'args': {'a': 1}
                  }
                }
              ],
              'role': 'model'
            },
            'finishReason': 'STOP'
          }
        ]
      });
      expect(reply.content, 'hi');
      expect(reply.toolCalls.single.name, 'f');
      expect(reply.toolCalls.single.arguments, {'a': 1});
      expect(reply.finished, isTrue);
    });

    test('gemini：MAX_TOKENS 视为未正常结束', () {
      final AiReply reply = const AiProvider(AiProviderKind.gemini).parseReply({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'x'}
              ]
            },
            'finishReason': 'MAX_TOKENS'
          }
        ]
      });
      expect(reply.finished, isFalse);
    });

    test('gemini：空 candidates → 空回复', () {
      final AiReply reply = const AiProvider(AiProviderKind.gemini)
          .parseReply({'candidates': <Object?>[]});
      expect(reply.content, isEmpty);
      expect(reply.finished, isFalse);
    });

    test('gemini：thought 段不计入正文', () {
      final AiReply reply = const AiProvider(AiProviderKind.gemini).parseReply({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '思考中', 'thought': true},
                {'text': '正文'}
              ]
            },
            'finishReason': 'STOP'
          }
        ]
      });
      expect(reply.content, '正文');
    });
  });

  group('buildChat', () {
    const AiToolSpec tool = AiToolSpec(
      name: 'get_weather',
      description: '查询天气',
      parameters: {'type': 'object'},
    );

    test('openai：路径 /chat/completions 与 body 形状', () {
      const AiProvider p = AiProvider(AiProviderKind.openai);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'gpt-4o',
          messages: [AiMessage(role: AiRole.user, content: 'hi')],
          tools: [tool],
          maxTokens: 2048,
        ),
      );
      expect(path, '/chat/completions');
      expect(body['model'], 'gpt-4o');
      expect(body['max_tokens'], 2048);
      expect(body.containsKey('stream'), isFalse);
      expect(
        (body['messages'] as List).single,
        {'role': 'user', 'content': 'hi'},
      );
      expect((body['tools'] as List).single, {
        'type': 'function',
        'function': {
          'name': 'get_weather',
          'description': '查询天气',
          'parameters': {'type': 'object'},
        },
      });
    });

    test('openai：stream 时带 stream: true，无 tools 时不带 tools 键', () {
      const AiProvider p = AiProvider(AiProviderKind.openai);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'gpt-4o',
          messages: [AiMessage(role: AiRole.user, content: 'hi')],
          stream: true,
        ),
      );
      expect(body['stream'], isTrue);
      expect(body.containsKey('tools'), isFalse);
      expect(path, '/chat/completions');
    });

    test('anthropic：路径 /messages，system 抽到顶层、工具用 input_schema', () {
      const AiProvider p = AiProvider(AiProviderKind.anthropic);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'claude-3',
          messages: [
            AiMessage(role: AiRole.system, content: '你是助手'),
            AiMessage(role: AiRole.user, content: 'hi'),
            AiMessage(
              role: AiRole.assistant,
              toolCalls: [
                AiToolCall(id: 'c1', name: 'f', arguments: {'a': 1})
              ],
            ),
          ],
          tools: [tool],
        ),
      );
      expect(path, '/messages');
      expect(body['system'], '你是助手');
      expect(body['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hi'}
          ]
        },
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'c1',
              'name': 'f',
              'input': {'a': 1}
            }
          ]
        },
      ]);
      expect((body['tools'] as List).single, {
        'name': 'get_weather',
        'description': '查询天气',
        'input_schema': {'type': 'object'},
      });
    });

    test('anthropic：tool 角色消息 → tool_result 块', () {
      const AiProvider p = AiProvider(AiProviderKind.anthropic);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'claude-3',
          messages: [
            AiMessage(role: AiRole.tool, content: 'ok', toolCallId: 'c1'),
          ],
        ),
      );
      expect(body['messages'], [
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'c1',
              'content': 'ok',
            }
          ]
        }
      ]);
    });

    test('gemini：路径带 :generateContent，body 用 contents/functionDeclarations',
        () {
      const AiProvider p = AiProvider(AiProviderKind.gemini);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'gemini-2.0-flash',
          messages: [AiMessage(role: AiRole.user, content: 'hi')],
          tools: [tool],
          maxTokens: 1024,
        ),
      );
      expect(path, '/models/gemini-2.0-flash:generateContent');
      expect(body['generationConfig'], {'maxOutputTokens': 1024});
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'hi'}
          ]
        }
      ]);
      expect((body['tools'] as List).single, {
        'functionDeclarations': [
          {
            'name': 'get_weather',
            'description': '查询天气',
            'parametersJsonSchema': {'type': 'object'},
          }
        ]
      });
    });

    test('gemini：stream 时路径切到 :streamGenerateContent?alt=sse', () {
      const AiProvider p = AiProvider(AiProviderKind.gemini);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'gemini-2.0-flash',
          messages: [AiMessage(role: AiRole.user, content: 'hi')],
          stream: true,
        ),
      );
      expect(path, '/models/gemini-2.0-flash:streamGenerateContent?alt=sse');
      expect(body['generationConfig'], {'maxOutputTokens': 4096});
    });

    test('gemini：system 消息抽到 systemInstruction', () {
      const AiProvider p = AiProvider(AiProviderKind.gemini);
      final (String path, Map<String, Object?> body) = p.buildChat(
        const AiChatRequest(
          model: 'gemini-2.0-flash',
          messages: [
            AiMessage(role: AiRole.system, content: '你是助手'),
            AiMessage(role: AiRole.user, content: 'hi'),
          ],
        ),
      );
      expect(body['systemInstruction'], {
        'parts': [
          {'text': '你是助手'}
        ]
      });
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'hi'}
          ]
        }
      ]);
    });
  });

  group('流式累积契约（多帧 → 完整回复）', () {
    AiStreamDelta acc(AiProviderKind kind, List<String> frames) {
      final AiProvider p = AiProvider(kind);
      final StringBuffer buf = StringBuffer();
      bool done = false;
      for (final String f in frames) {
        final AiStreamDelta d = p.parseStreamChunk(f);
        buf.write(d.content);
        done = done || d.finished;
      }
      return AiStreamDelta(content: buf.toString(), finished: done);
    }

    test('openai：10 帧累积 = 完整文本，末帧带 finish_reason 才算结束', () {
      final List<String> frames = <String>[
        for (int i = 0; i < 9; i++) '{"choices":[{"delta":{"content":"字$i"}}]}',
        '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
      ];
      final AiStreamDelta r = acc(AiProviderKind.openai, frames);
      expect(r.content, '字0字1字2字3字4字5字6字7字8');
      expect(r.finished, isTrue);
    });

    test('anthropic：流没给 message_stop 时不得谎报结束', () {
      final AiStreamDelta r = acc(AiProviderKind.anthropic, <String>[
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}',
        '{"type":"ping"}',
      ]);
      expect(r.content, '你好');
      expect(r.finished, isFalse);
    });

    test('gemini：多帧文本累积 + 末帧 STOP', () {
      final AiStreamDelta r = acc(AiProviderKind.gemini, <String>[
        '{"candidates":[{"content":{"parts":[{"text":"A"}]}}]}',
        '{"candidates":[{"content":{"parts":[{"text":"B"}]},"finishReason":"STOP"}]}',
      ]);
      expect(r.content, 'AB');
      expect(r.finished, isTrue);
    });

    test('中断流（无结束帧）：三家都不得判 finished —— 防截断回复被当完整', () {
      final Map<AiProviderKind, String> partial = <AiProviderKind, String>{
        AiProviderKind.openai: '{"choices":[{"delta":{"content":"半"}}]}',
        AiProviderKind.anthropic:
            '{"type":"content_block_delta","delta":{"type":"text_delta","text":"半"}}',
        AiProviderKind.gemini:
            '{"candidates":[{"content":{"parts":[{"text":"半"}]}}]}',
      };
      for (final MapEntry<AiProviderKind, String> e in partial.entries) {
        final AiStreamDelta r = acc(e.key, <String>[e.value]);
        expect(r.finished, isFalse, reason: '${e.key} 流中断不应判完成');
        expect(r.content, '半');
      }
    });
  });
}
