/// L3 展示级 · Actions 运行日志（按 job 展示，可搜索）。
///
/// 数据来自中枢层 `IxActionLogs`（带令牌下载日志 zip 并解压），
/// 页面只负责呈现与检索。
library;

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/log_body.dart';

/// 取 `action_log_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'action_log_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// Actions 日志页。
class ActionLogPage extends StatefulWidget {
  /// 创建页面。
  const ActionLogPage({
    required this.surface,
    required this.fullName,
    required this.runId,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 运行 ID。
  final int runId;

  @override
  State<ActionLogPage> createState() => _ActionLogPageState();
}

class _ActionLogPageState extends State<ActionLogPage> {
  AsyncController<Map<String, String>>? _logs;
  final TextEditingController _query = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _logsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _logs?.dispose();
    _query.dispose();
    super.dispose();
  }

  AsyncController<Map<String, String>> _logsC() {
    final existing = _logs;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<Map<String, String>>(
      label: _t('title'),
      isEmpty: (Map<String, String> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.actionLogs.fetch(widget.fullName, widget.runId),
    );
    _logs = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: _t('reload'),
            onPressed: () => _logsC().load(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                OgLSpace.md, OgLSpace.md, OgLSpace.md, OgLSpace.sm),
            child: TextField(
              controller: _query,
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                hintText: _t('searchJobHint'),
              ),
              onChanged: (String value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: AsyncView<Map<String, String>>(
              controller: _logsC(),
              emptyIcon: Icons.receipt_long,
              emptyText: _t('noLogs'),
              builder: (BuildContext context, Map<String, String> logs) {
                final List<String> keys = logs.keys
                    .where((String k) =>
                        _filter.isEmpty ||
                        k.toLowerCase().contains(_filter.toLowerCase()))
                    .toList()
                  ..sort();
                if (keys.isEmpty) {
                  return Center(child: Text(_t('noMatchingJob')));
                }
                return ListView(
                  padding: const EdgeInsets.all(OgLSpace.md),
                  children: <Widget>[
                    for (final String key in keys)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          leading: const Icon(Icons.terminal),
                          title: Text(
                            key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                              OgLSpace.md, 0, OgLSpace.md, OgLSpace.md),
                          children: <Widget>[
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 420),
                              padding: const EdgeInsets.all(OgLSpace.md),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius:
                                    BorderRadius.circular(OgLRadius.sm),
                              ),
                              // 5.0：长日志**分块虚拟化**渲染。
                              // 之前把整份日志塞进一个 `SelectableText`，
                              // 上万行的 Actions 日志会一次性排版全部行 → 展开就是几秒卡顿。
                              // 现在按行切块、交给 `ListView.builder` 按需渲染。
                              child: OgLLogBody(text: logs[key] ?? ''),
                            ),
                            const SizedBox(height: OgLSpace.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _t('linesCount', <String, Object?>{
                                  'count': (logs[key] ?? '').split('\n').length,
                                }),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
