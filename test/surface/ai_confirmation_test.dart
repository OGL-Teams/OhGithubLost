/// 确认弹窗必须展示目标和完整前后内容，取消不能被解释成批准。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';
import 'package:ohgithublost/surface/pages/ai_confirmation.dart';
import 'package:ohgithublost/surface/pages/ai_settings_page.dart';
import 'package:ohgithublost/surface/types.dart';

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('AI confirmation shows full changes and cancels ($language)', (
      tester,
    ) async {
      final raw = jsonDecode(
        File('assets/i18n/$language/ai.json').readAsStringSync(),
      ) as Map;
      OgLI18n.instance.debugInject(language, {
        'ai': {
          for (final entry in raw.entries) '${entry.key}': '${entry.value}',
        },
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  accepted = await confirmAiProposal(
                    context,
                    AiProposal(
                      operation: 'propose_files',
                      accountId: '1',
                      repo: 'owner/repo',
                      branch: 'main',
                      baseSha: 'baseline',
                      payload: {'message': 'Update'},
                      files: [
                        const AiFileChange(
                          path: 'lib/example.dart',
                          before: 'old content',
                          after: 'new content',
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('owner/repo · main'), findsOneWidget);
      expect(find.text('lib/example.dart'), findsOneWidget);
      expect(find.text('old content'), findsOneWidget);
      expect(find.text('new content'), findsOneWidget);
      expect(accepted, isNull);
      await tester.tap(find.text(aiText('cancel')));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
