/// 写操作预览：展示目标、完整前后内容和参数，不在确认前调用写接口。
library;

import 'package:flutter/material.dart';

import '../types.dart';
import 'ai_settings_page.dart';

Future<bool> confirmAiProposal(
  BuildContext context,
  AiProposal proposal,
) async {
  if (!context.mounted) {
    return false;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(aiText('confirmTitle')),
          content: SizedBox(
            width: 800,
            height: MediaQuery.sizeOf(context).height * .60,
            child: ListView(
              children: [
                Text('${proposal.repo} · ${proposal.branch}'),
                const SizedBox(height: 8),
                Text(aiText(proposal.operation)),
                const SizedBox(height: 8),
                SelectableText(proposal.payloadJson),
                if (proposal.baseSha.isNotEmpty)
                  SelectableText('HEAD ${proposal.baseSha}'),
                for (final file in proposal.files) ...[
                  const Divider(height: 24),
                  Text(
                    file.path,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(aiText('before')),
                  SelectableText(
                    file.before ?? aiText('absent'),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 12),
                  Text(aiText('after')),
                  SelectableText(
                    file.after ?? aiText('deleted'),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(aiText('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(aiText('confirm')),
            ),
          ],
        ),
      ) ??
      false;
}
