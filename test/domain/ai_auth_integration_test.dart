/// 使用真实认证服务和 GitHub 客户端，验证 AI 不需要第二份 GitHub token。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/ai/ai_models.dart';
import 'package:ohgithublost/domain/ai/ai_service.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';
import 'package:ohgithublost/kernel/contract/disk_store.dart';

void main() {
  test(
    'AI reads use the currently signed-in GitHub token; AI keys stay separate',
    () async {
      final vault = InMemoryVault(), store = InMemoryKv();
      final auth = GhAuthService(vault: vault, store: store);
      await auth.saveAccount(
        const GhAccount(id: 'alice', login: 'alice'),
        const GhToken('ghp_alice_test'),
      );
      await auth.saveAccount(
        const GhAccount(id: 'bob', login: 'bob'),
        const GhToken('ghp_bob_test'),
      );
      final transport = ScriptedTransport(
        List.generate(
          2,
          (_) => NetResponse(
            statusCode: 200,
            body: jsonEncode({'name': 'repo'}),
            duration: const Duration(milliseconds: 1),
          ),
        ),
      );
      final client = GhClient(
        net: NetBridge(transport: transport, observer: NetObserver()),
        auth: auth,
      );
      Future<Object?> github(
        String method,
        String path,
        Map<String, Object?>? body,
        Map<String, String> query,
      ) async {
        final response = await client.send(
          GhRequest(
            path: path,
            method: NetMethod.values.firstWhere((e) => e.verb == method),
            body: body,
            query: query,
            cacheBypass: true,
          ),
        );
        return jsonDecode(response.body);
      }

      var turn = 0;
      final ai = AiService(
        store: store,
        vault: vault,
        github: github,
        account: auth.activeAccountId,
        provider: (config, endpoint, key, body) async {
          expect(key, 'AI_ONLY');
          expect(jsonEncode(body), isNot(contains('ghp_')));
          if (endpoint == 'models') {
            return {
              'data': [
                {'id': 'returned-model'},
              ],
            };
          }
          return {
            'choices': [
              {
                'message': ++turn % 2 == 1
                    ? {
                        'role': 'assistant',
                        'content': null,
                        'tool_calls': [
                          {
                            'id': 'read',
                            'type': 'function',
                            'function': {
                              'name': 'repository_info',
                              'arguments': '{}',
                            },
                          },
                        ],
                      }
                    : {'role': 'assistant', 'content': 'Read successfully'},
              },
            ],
          };
        },
      );
      await ai.saveSettings(const AiSettings(enabled: true), key: 'AI_ONLY');
      for (final id in ['alice', 'bob']) {
        await auth.switchTo(id);
        final chat = AiConversation(
          id: id,
          accountId: id,
          repo: 'owner/repo',
          branch: 'main',
        );
        await ai.send(chat, 'Read repository', (_) async => false);
        expect((await ai.conversations()).single.accountId, id);
      }
      expect(
        transport.received.map((e) => e.headers['authorization']).toList(),
        ['Bearer ghp_alice_test', 'Bearer ghp_bob_test'],
      );
      expect(
        transport.received.every(
          (e) => !jsonEncode(e.headers).contains('AI_ONLY'),
        ),
        isTrue,
      );
    },
  );
}
