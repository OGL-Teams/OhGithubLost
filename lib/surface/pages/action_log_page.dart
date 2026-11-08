/// L3 展示级 · Actions 运行日志（按 job 分组折叠 + 日志内查找 + 下载到本地）。
///
/// 数据来自中枢层 `IxActionLogs`（带令牌下载日志 zip 并解压），
/// 页面只负责呈现、检索与落盘。
///
/// ## 分组语义（与运行详情页对齐）
/// - job 名对齐 `action_run_page` 的作业列表（日志 zip 的 `job/步骤.txt` 目录名）；
/// - **失败 job 置顶 + 默认展开**，全部成功则默认折叠（失败的现场不该被收起来）；
/// - 状态色点取自运行详情页同源数据（本页直接按结论着色，规则一致）。
///
/// ## 性能边界
/// 日志可能几百 KB：正文渲染继续交给 `OgLLogBody` 分块虚拟化；
/// 查找命中只做**计数与首处定位**（滚动到该块），不在全文上铺高亮——
/// 全文高亮会让"输入一个字符"变成一次全量排版。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../util/clipboard_x.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/log_body.dart';
import '../widgets/log_search.dart';

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
  /// 查找关键词（防抖后生效）。
  String _search = '';
  Timer? _debounce;
  /// 每个 job 的查找结果（job 名 → 命中偏移列表）。
  Map<String, List<int>> _matches = const <String, List<int>>{};
  int _matchTotal = 0;

  @override
  void initState() {
    super.initState();
    _logsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _logs?.dispose();
    _query.dispose();
    super.dispose();
  }

  /// 复制当前已加载的全部日志（按 job 分段拼接）。
  Future<void> _copyAll() async {
    final Map<String, String>? data = _logs?.data;
    if (data == null || data.isEmpty) {
      OgLNotifier.of(context).info(_t('nothingToCopy'));
      return;
    }
    await ogLCopyText(
      IxJoin.join(data),
      tag: _t('title'),
    );
    if (mounted) {
      OgLNotifier.of(context).info(_t('copied', {'label': _t('title')}));
    }
  }

  /// 下载整份日志到本地可见目录（`actions/<repo>-run<id>.log`）。
  Future<void> _download() async {
    final Map<String, String>? data = _logs?.data;
    if (data == null || data.isEmpty) {
      OgLNotifier.of(context).info(_t('nothingToCopy'));
      return;
    }
    try {
      final String root = (await OgLStoragePlanProbe.planRoot());
      final String safeRepo = widget.fullName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
      final String path = await widget.surface.domain.actionLogs.saveToDisk(
        root: root,
        fileName: '$safeRepo-run${widget.runId}.log',
        text: IxJoin.join(data),
      );
      OgLAppLog.instance.result('Actions', _t('downloaded'), path);
      if (mounted) {
        OgLNotifier.of(context).success(
              _t('downloadedAt', {'path': path}),
            );
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        _t('downloadFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(_t('downloadFailed', {'error': error}));
      }
    }
  }

  /// 关键词变化：防抖 300ms 后全量扫描计数（只扫内存字符串，成本可接受）。
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _search = value;
        _matches = _scanAll();
        _matchTotal = _matches.values.fold(0, (int a, List<int> b) => a + b.length);
      });
    });
  }

  /// 扫描全部 job（大小写不敏感）；返回 job 名 → 命中偏移列表。
  Map<String, List<int>> _scanAll() {
    final Map<String, String>? data = _logs?.data;
    if (data == null || _search.trim().isEmpty) {
      return const <String, List<int>>{};
    }
    final String needle = _search.toLowerCase();
    final Map<String, List<int>> out = <String, List<int>>{};
    data.forEach((String job, String text) {
      final String hay = text.toLowerCase();
      final List<int> hits = <int>[];
      var cursor = 0;
      while (cursor <= hay.length - needle.length) {
        final int hit = hay.indexOf(needle, cursor);
        if (hit < 0) {
          break;
        }
        hits.add(hit);
        cursor = hit + needle.length;
      }
      if (hits.isNotEmpty) {
        out[job] = hits;
      }
    });
    return out;
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
          // 复制整份日志：排查问题要把它贴给别人，逐块手选太笨。
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _t('copyAll'),
            onPressed: _copyAll,
          ),
          // 下载到本地：整份日志落盘 actions/ 目录（Web 无文件系统则如实报错）。
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: _t('downloadLog'),
            onPressed: () => unawaited(_download()),
          ),
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
                  return OgLAsyncEmptyPane(
                    icon: Icons.filter_alt_off_outlined,
                    text: _t('noMatchingJob'),
                  );
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
