/// L3 展示级 · Actions 运行日志（按 job 分组折叠 + 日志内查找 + 下载到本地）。
///
/// 数据来自中枢层 `IxActionLogs`（带令牌下载日志 zip 并解压），
/// 页面只负责呈现、检索与落盘。
///
/// ## 分组语义（与运行详情页对齐）
/// - job 名与 `action_run_page` 的作业列表同名（日志 zip 的 `job/步骤.txt` 目录名）；
/// - **失败 job 置顶 + 默认展开**，全部成功则默认折叠（失败的现场不该被收起来）；
/// - 组前的状态点按 job 名对齐运行详情页的 job 结论（本页自取 jobs 接口，
///   失败不阻断日志展示——结论缺失按"未知"灰点，不猜成功）。
///
/// ## 性能边界
/// 日志可能几百 KB：正文渲染继续交给 `OgLLogBody` 分块虚拟化；
/// 查找做**计数 + 命中行高亮**（命中行以高亮片段渲染），不在全文上铺
/// 装饰——全文高亮会把"输入一个字符"变成一次全量排版。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../util/clipboard_x.dart';
import '../util/gh_format.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/log_body.dart';
import '../widgets/log_search.dart';

/// 取 `action_log_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'action_log_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 一次查找的快照：关键词 + 命中（job 名 → 命中偏移列表）+ 命中总数。
class _SearchState {
  const _SearchState(this.query, this.matches, this.total);

  /// 关键词（小写；空 = 未查找）。
  final String query;

  /// job 名 → 命中偏移列表（按出现顺序）。
  final Map<String, List<int>> matches;

  /// 命中总数。
  final int total;

  /// 是否处于"已输入但零命中"（用于提示）。
  bool get noHit => query.isNotEmpty && total == 0;

  /// 无查找状态。
  static const _SearchState empty = _SearchState('', <String, List<int>>{}, 0);
}

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
  AsyncController<List<Map<String, dynamic>>>? _jobs;
  final TextEditingController _query = TextEditingController();
  String _filter = '';
  Timer? _debounce;

  /// 查找防抖窗口（打字节流，非动效时长；与 search_page 同豁免口径）。
  static const Duration _debounceWindow = Duration(milliseconds: 300);
  _SearchState _search = _SearchState.empty;

  /// 查找条展开状态（默认收起，不占纵向空间）。
  bool _searchOpen = false;

  /// 当前第几处命中（1 起；0 = 无）。
  int _searchIndex = 0;

  /// 跳转令牌（值变化触发 `OgLLogBody` 内滚动；每次跳转 +1 或 -1）。
  int _jumpToken = 0;

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

  /// job 结论表（job 名 → `success` / `failure` / …；取不到返回空表）。
  ///
  /// 为什么本页再拉一次 jobs：状态点是"运行详情页同源"的结论，而日志 zip
  /// 的文件名只有 job 名没有结论。jobs 接口轻量（每运行几十条），
  /// **失败不阻断日志展示**——结论缺失按未知灰点（这是降级，但要可见：
  /// 灰点本身就是"未知"的如实表达，不伪装成成功/失败）。
  AsyncController<List<Map<String, dynamic>>> _jobsC() {
    final existing = _jobs;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: _t('title'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () async {
        try {
          return await widget.surface.domain.api
              .workflowRunJobs(widget.fullName, widget.runId);
        } catch (_) {
          // 失败可见性：结论列整体按"未知"呈现（灰点），并在日志区照常展示。
          return const <Map<String, dynamic>>[];
        }
      },
    );
    _jobs = controller;
    return controller;
  }

  /// 复制当前已加载的全部日志（按 job 分段拼接）。
  Future<void> _copyAll() async {
    final Map<String, String>? data = _logs?.data;
    if (data == null || data.isEmpty) {
      OgLNotifier.of(context).info(_t('nothingToCopy'));
      return;
    }
    await ogLCopyText(
      widget.surface.domain.actionLogs.joinLogs(data),
      tag: _t('title'),
    );
    if (mounted) {
      OgLNotifier.of(context).info(_t('copied', {'label': _t('title')}));
    }
  }

  /// 下载整份日志到本地可见目录（`actions/<safe-repo>-run<id>.log`）。
  ///
  /// 为什么不走 `IxDownloadManager`：下载器是"从 URL 拉字节"，而日志文本
  /// 已在内存里——直接落盘才是如实的路径。Web 无文件系统 → 中枢层抛
  /// 类型化异常，这里如实提示（不静默降级）。
  Future<void> _download() async {
    final Map<String, String>? data = _logs?.data;
    if (data == null || data.isEmpty) {
      OgLNotifier.of(context).info(_t('nothingToCopy'));
      return;
    }
    final Future<String?> Function()? probe = widget.surface.storageRoot;
    if (probe == null) {
      OgLNotifier.of(context).warning(_t('downloadUnavailable'));
      return;
    }
    try {
      final String? root = await probe();
      if (root == null || root.isEmpty) {
        if (mounted) {
          OgLNotifier.of(context).warning(_t('downloadUnavailable'));
        }
        return;
      }
      // 文件名净化：repo 全名可能含 `/` 等路径字符。
      final String safeRepo =
          widget.fullName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
      final String path = await widget.surface.domain.actionLogs.saveToDisk(
        root: root,
        fileName: '$safeRepo-run${widget.runId}.log',
        text: widget.surface.domain.actionLogs.joinLogs(data),
      );
      OgLAppLog.instance.result('Actions', _t('downloaded'), path);
      if (mounted) {
        OgLNotifier.of(context)
            .success(_t('downloadedAt', <String, Object?>{'path': path}));
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        _t('downloadFailed', <String, Object?>{'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context)
            .warning(_t('downloadFailed', <String, Object?>{'error': error}));
      }
    }
  }

  /// 关键词变化：防抖后全量扫描计数（纯内存字符串扫描，成本可接受）。
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _search = _scan(value);
        _searchIndex = _search.total > 0 ? 1 : 0;
        _jumpToken++;
      });
    });
  }

  /// 上一处（-1）/ 下一处（+1）：在**命中总数**上循环。
  ///
  /// 命中分布在多个 job 时循环跨 job——正文都渲染着，跳到哪组都看得见。
  void _jumpTo(int delta) {
    if (_search.total <= 0) {
      return;
    }
    setState(() {
      _searchIndex =
          ((_searchIndex - 1 + delta) % _search.total + _search.total) %
                  _search.total +
              1;
      _jumpToken++;
    });
  }

  /// 扫描全部 job（大小写不敏感）：job 名 → 命中偏移列表。
  _SearchState _scan(String raw) {
    final Map<String, String>? data = _logs?.data;
    final String needle = raw.trim().toLowerCase();
    if (data == null || needle.isEmpty) {
      return _SearchState.empty;
    }
    final Map<String, List<int>> out = <String, List<int>>{};
    var total = 0;
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
        total += hits.length;
      }
    });
    return _SearchState(needle, out, total);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: <Widget>[
          // 日志内查找：开关查找条（计数与命中行高亮在组内生效）。
          IconButton(
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            tooltip: _t('toggleSearch'),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _debounce?.cancel();
                _search = _SearchState.empty;
              }
            }),
          ),
          // 复制整份日志：排查问题要把它贴给别人，逐块手选太笨。
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _t('copyAll'),
            onPressed: () => unawaited(_copyAll()),
          ),
          // 下载到本地：整份日志落盘 actions/ 目录（Web 无文件系统 → 如实报错）。
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
                prefixIcon: const Icon(Icons.search),
                hintText: _t('searchJobHint'),
              ),
              onChanged: (String value) => setState(() => _filter = value),
            ),
          ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OgLSpace.md),
              child: OgLLogSearchBar(
                hintText: _t('searchLogHint'),
                total: _search.total,
                current: _search.total > 0 ? _searchIndex + 1 : 0,
                onSubmit: _onSearchChanged,
                onJump: _jumpTo,
              ),
            ),
          if (_search.noHit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OgLSpace.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_t('noLogMatch'),
                    style: Theme.of(context).textTheme.bodySmall),
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
                    .toList();
                if (keys.isEmpty) {
                  return OgLAsyncEmptyPane(
                    icon: Icons.filter_alt_off_outlined,
                    text: _t('noMatchingJob'),
                  );
                }
                // 结论表：jobs 数据可用则对齐运行详情页；不可用则全按"未知"。
                final Map<String, String> conclusions = <String, String>{};
                final List<Map<String, dynamic>>? jobs = _jobsC().data;
                if (jobs != null) {
                  for (final Map<String, dynamic> job in jobs) {
                    conclusions[ghStr(job, 'name')] = ghStr(job, 'conclusion');
                  }
                }
                return _JobGroupList(
                  logs: logs,
                  keys: keys,
                  conclusions: conclusions,
                  search: _search,
                  searchIndex: _searchIndex,
                  jumpToken: _jumpToken,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 按 job 分组的折叠列表。
///
/// - **失败 job 置顶 + 默认展开**：失败的现场不该被收起来；
/// - 全部成功 → 默认全部折叠（展开一份几百 KB 的日志是有成本的动作）；
/// - 组前状态点：成功 / 失败 / 进行中 / 未知（与运行详情页同规则）。
class _JobGroupList extends StatelessWidget {
  const _JobGroupList({
    required this.logs,
    required this.keys,
    required this.conclusions,
    required this.search,
    required this.searchIndex,
    required this.jumpToken,
  });

  /// job 名 → 日志文本。
  final Map<String, String> logs;

  /// 过滤后的 job 名（顺序将被失败置顶重排）。
  final List<String> keys;

  /// job 名 → 结论（缺失 = 未知）。
  final Map<String, String> conclusions;

  /// 当前查找状态（空 = 无查找）。
  final _SearchState search;

  /// 当前第几处命中（1 起）。
  final int searchIndex;

  /// 跳转令牌（透传给正文触发滚动）。
  final int jumpToken;

  /// 是否失败结论。
  static bool _isFailed(String conclusion) =>
      conclusion == 'failure' || conclusion == 'timed_out';

  @override
  Widget build(BuildContext context) {
    bool failed(String name) => _isFailed(conclusions[name] ?? '');
    final List<String> bad = keys.where(failed).toList()..sort();
    final List<String> rest = keys.where((String k) => !failed(k)).toList()
      ..sort();
    final List<String> ordered = <String>[...bad, ...rest];
    // 初始展开集合：有失败 job → 只展开失败组；否则全折叠。
    final Set<String> open = <String>{...bad};
    return ListView(
      padding: const EdgeInsets.all(OgLSpace.md),
      children: <Widget>[
        for (final String key in ordered)
          _JobCard(
            name: key,
            text: logs[key] ?? '',
            conclusion: conclusions[key] ?? '',
            initiallyExpanded: open.contains(key),
            search: search,
            searchIndex: searchIndex,
            jumpToken: jumpToken,
          ),
      ],
    );
  }
}

/// 单个 job 的折叠卡（状态点 + 标题 + 命中计数 + 分块日志正文）。
class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.name,
    required this.text,
    required this.conclusion,
    required this.initiallyExpanded,
    required this.search,
    required this.searchIndex,
    required this.jumpToken,
  });

  final String name;
  final String text;
  final String conclusion;
  final bool initiallyExpanded;
  final _SearchState search;

  /// 当前第几处命中。
  final int searchIndex;

  /// 跳转令牌。
  final int jumpToken;

  /// 状态点颜色（与运行详情页 `_statusColor` 同规则；进行中看状态字段之外的
  /// 信号不可得，故非 completed 的结论一律未知灰——诚实优于猜测）。
  Color _dotColor(ThemeData theme) {
    switch (conclusion) {
      case 'success':
        return theme.extension<OgLSemanticColors>()?.success ??
            theme.colorScheme.primary;
      case 'failure':
      case 'timed_out':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<int>? hits =
        search.query.isEmpty ? null : (search.matches[name] ?? const <int>[]);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // key 含初始展开态：失败置顶重排后能以正确展开态重建。
        key: ValueKey<String>('log-job-$name-$initiallyExpanded'),
        initiallyExpanded: initiallyExpanded,
        leading: Icon(Icons.circle, size: 12, color: _dotColor(theme)),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: hits != null && hits.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(right: OgLSpace.sm),
                child: Text(
                  '${hits.length}',
                  style: theme.textTheme.bodySmall,
                ),
              )
            : null,
        childrenPadding:
            const EdgeInsets.fromLTRB(OgLSpace.md, 0, OgLSpace.md, OgLSpace.md),
        children: <Widget>[
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 420),
            padding: const EdgeInsets.all(OgLSpace.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(OgLRadius.sm),
            ),
            // 长日志分块虚拟化（几万行 Actions 日志按需排版，展开不卡顿）。
            // 查找激活：本组有命中才传关键词（高亮 + 跳转定位都在组内生效）。
            child: OgLLogBody(
              text: text,
              query: hits != null && hits.isNotEmpty ? search.query : '',
              jumpToken: hits != null && hits.isNotEmpty ? jumpToken : 0,
            ),
          ),
          const SizedBox(height: OgLSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _t('linesCount', <String, Object?>{
                'count': text.split('\n').length,
              }),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
