/// GitHub 通知、星标组织、关注检查与贡献统计：按账号持久化。
library;

import 'dart:convert';

import '../../kernel/contract/disk_store.dart';
import '../ai/ai_models.dart';

class ProductivityService {
  ProductivityService({
    required this.github,
    required this.account,
    required DiskKv store,
    this.notificationGithub,
  }) : _store = store;
  final AiGithubRequest github;

  /// 可选账号绑定通道；生产通知操作全部使用此通道。
  final Future<Object?> Function(
    String,
    String,
    String,
    Map<String, Object?>?,
    Map<String, String>,
  )?
  notificationGithub;

  Future<Object?> _notificationRequest(
    String method,
    String path,
    Map<String, Object?>? body,
    Map<String, String> query,
  ) async {
    final id = await _id();
    final bound = notificationGithub;
    final result = bound == null
        ? await github(method, path, body, query)
        : await bound(id, method, path, body, query);
    if (await _id() != id) throw const AiException('accountChanged');
    return result;
  }

  final Future<String?> Function() account;
  final DiskKv _store;

  Future<String> _id() async {
    final id = await account();
    if (id == null) {
      throw const AiException('loginRequired');
    }
    return id;
  }

  Future<List<Map<String, dynamic>>> notifications({
    int page = 1,
    bool all = false,
  }) async => (await _notificationRequest('GET', '/notifications', null, {
    'all': '$all',
    'per_page': '50',
    'page': '$page',
  }) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> markRead(String threadId) async {
    if (!RegExp(r'^\d+$').hasMatch(threadId)) {
      throw const AiException('invalidResponse');
    }
    await _notificationRequest(
      'PATCH',
      '/notifications/threads/$threadId',
      {},
      {},
    );
  }

  /// 通过 GitHub 批量接口处理所有页；以点击时刻为截止，保留之后的新消息。
  Future<void> markAllNotificationsRead() async {
    final cutoff =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    await _notificationRequest('PUT', '/notifications', <String, Object?>{
      'last_read_at': cutoff,
      'read': true,
    }, <String, String>{});
  }

  /// 通知只允许读取其仓库内的 Issue/PR，不能跟随任意外部 subject URL。
  Future<Map<String, dynamic>> notificationSubject(
    String repo,
    String url,
  ) async {
    AiServiceValidation.repo(repo);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'api.github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp('^/repos/${RegExp.escape(repo)}/(issues|pulls)/[1-9][0-9]*\$')
            .hasMatch(uri.path)) {
      throw const AiException('invalidResponse');
    }
    final user = await _id();
    final item = Map<String, dynamic>.from(
      await github('GET', uri.path, null, {}) as Map,
    );
    if (await _id() != user) {
      throw const AiException('accountChanged');
    }
    return item;
  }

  Future<Map<String, dynamic>> starMetadata() async {
    final raw = await _store.read('productivity.stars.${await _id()}');
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> organizeStar(
    String repo,
    String category,
    List<String> tags,
  ) async {
    AiServiceValidation.repo(repo);
    final id = await _id();
    final meta = await starMetadata();
    meta[repo] = {
      'category': category.trim(),
      'tags': tags
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),
    };
    if (await _id() != id) {
      throw const AiException('accountChanged');
    }
    await _store.write('productivity.stars.$id', jsonEncode(meta));
  }

  Future<Map<String, dynamic>> watches() async {
    final raw = await _store.read('productivity.watches.${await _id()}');
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<Map<String, Object?>> _snapshot(String repo) async {
    final detail = await github('GET', '/repos/$repo', null, {}) as Map;
    final commits = await github('GET', '/repos/$repo/commits', null, {
      'sha': '${detail['default_branch']}',
      'per_page': '1',
    }) as List;
    final releases = await github('GET', '/repos/$repo/releases', null, {
      'per_page': '1',
    }) as List;
    return {
      'commit': commits.isEmpty ? '' : (commits.first as Map)['sha'],
      'release': releases.isEmpty ? '' : '${(releases.first as Map)['id']}',
    };
  }

  Future<void> setWatch(String repo, bool enabled) async {
    AiServiceValidation.repo(repo);
    final user = await _id();
    final list = await watches();
    if (enabled) {
      list[repo] = await _snapshot(repo);
    } else {
      list.remove(repo);
    }
    if (await _id() != user) {
      throw const AiException('accountChanged');
    }
    await _store.write('productivity.watches.$user', jsonEncode(list));
  }

  /// 限制每轮监控仓库数，逐仓库失败保留原基线，下一轮可继续恢复。
  Future<List<Map<String, dynamic>>> pollUpdates() async {
    final user = await _id();
    final list = await watches();
    final updates = <Map<String, dynamic>>[];
    final errors = <String>[];
    for (final repo in list.keys.take(50).toList()) {
      try {
        final before = list[repo] as Map;
        final current = await _snapshot(repo);
        final commitChanged = before['commit'] != current['commit'];
        final releaseChanged =
            before['release'] != current['release'] && current['release'] != '';
        if (commitChanged || releaseChanged) {
          updates.add({
            'repo': repo,
            'commit': commitChanged,
            'release': releaseChanged,
          });
        }
        list[repo] = current;
      } catch (_) {
        errors.add(repo);
      }
    }
    if (await _id() != user) {
      throw const AiException('accountChanged');
    }
    await _store.write('productivity.watches.$user', jsonEncode(list));
    if (errors.isNotEmpty && updates.isEmpty) {
      throw AiException('watchFailed', errors.join(', '));
    }
    return updates;
  }

  /// 统计明确标注范围：GitHub 搜索可见提交，逐提交累计增删行，不伪造全量行数。
  Future<Map<String, dynamic>> contributions(
    String login,
    DateTime month,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(login)) {
      throw const AiException('invalidResponse');
    }
    final start = DateTime.utc(month.year, month.month, 1);
    final end = DateTime.utc(
      month.year,
      month.month + 1,
      1,
    ).subtract(const Duration(days: 1));
    String date(DateTime d) => d.toIso8601String().substring(0, 10);
    final result = await github('GET', '/search/commits', null, {
      'q': 'author:$login committer-date:${date(start)}..${date(end)}',
      'per_page': '100',
    }) as Map;
    final items = result['items'] as List? ?? [];
    var added = 0, deleted = 0, measured = 0, failed = 0;
    for (final item in items.whereType<Map>()) {
      try {
        final repo = (item['repository'] as Map)['full_name'] as String;
        final detail = await github(
          'GET',
          '/repos/$repo/commits/${item['sha']}',
          null,
          {},
        ) as Map;
        final stats = detail['stats'] as Map;
        added += (stats['additions'] as num).toInt();
        deleted += (stats['deletions'] as num).toInt();
        measured++;
      } catch (_) {
        failed++;
      }
    }
    return {
      'commits': result['total_count'] ?? 0,
      'added': added,
      'deleted': deleted,
      'measured': measured,
      'failed': failed,
      'incomplete': result['incomplete_results'] == true,
      'sampled': measured < (result['total_count'] as num? ?? 0),
    };
  }
}

/// 独立的低成本校验，不让展示层获得任意 GitHub API 路径。
class AiServiceValidation {
  static void repo(String repo) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+$')
        .hasMatch(repo)) {
      throw const AiException('invalidRepo');
    }
  }
}
