/// L3 展示级 · Actions 运行详情（作业 + 步骤 + 重跑 / 取消）。
///
/// 补齐"Actions 只列运行、点不动"的缺口：现在能看到每个 job 的每一步，
/// 并支持对已结束的运行**重新运行**、对进行中的运行**取消**。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/accel.dart';
import '../util/download_proxy.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import 'action_log_page.dart';
import 'download_manager_page.dart';

/// 取 `action_run_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'action_run_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 一次运行 + 它的作业列表。
class _RunDetail {
  const _RunDetail(this.run, this.jobs, this.artifacts);

  final Map<String, dynamic> run;
  final List<Map<String, dynamic>> jobs;

  /// 本次运行的构建产物（可能为空）。产物端点需认证，下载前先在本地换签名地址。
  final List<Map<String, dynamic>> artifacts;
}

/// 运行详情页。
class ActionRunPage extends StatefulWidget {
  /// 创建页面。
  const ActionRunPage({
    required this.surface,
    required this.fullName,
    required this.run,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 运行对象（列表接口返回）。
  final Map<String, dynamic> run;

  /// 运行 ID。
  int get runId => ghInt(run, 'id');

  @override
  State<ActionRunPage> createState() => _ActionRunPageState();
}

class _ActionRunPageState extends State<ActionRunPage> {
  AsyncController<_RunDetail>? _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _detailC().loadIfNeeded();
  }

  @override
  void dispose() {
    _detail?.dispose();
    super.dispose();
  }

  AsyncController<_RunDetail> _detailC() {
    final existing = _detail;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<_RunDetail>(
      label: _t('title'),
      isEmpty: (_RunDetail value) => false,
      loader: () async {
        final Map<String, dynamic>? run =
            await widget.surface.domain.api.workflowRun(
          widget.fullName,
          widget.runId,
        );
        final List<Map<String, dynamic>> jobs =
            await widget.surface.domain.api.workflowRunJobs(
          widget.fullName,
          widget.runId,
        );
        // 产物列表：**失败不阻断**（老运行的产物会被 GitHub 清理，接口可能 404）。
        List<Map<String, dynamic>> artifacts = const <Map<String, dynamic>>[];
        try {
          artifacts = await widget.surface.domain.api.workflowRunArtifacts(
            widget.fullName,
            widget.runId,
          );
        } catch (_) {
          artifacts = const <Map<String, dynamic>>[];
        }
        return _RunDetail(run ?? widget.run, jobs, artifacts);
      },
    );
    _detail = controller;
    return controller;
  }

  Future<void> _rerun() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .rerunWorkflowRun(widget.fullName, widget.runId);
      OgLAppLog.instance
          .result('Actions', _t('rerunTriggered'), '#${widget.runId}');
      if (mounted) {
        OgLNotifier.of(context).info(_t('rerunTriggered'));
      }
      await _detailC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        _t('rerunFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('rerunFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancel() async {
    if (_busy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_t('cancelRun')),
        content: Text(_t('cancelRunDesc')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_t('back')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_t('cancelRun')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .cancelWorkflowRun(widget.fullName, widget.runId);
      OgLAppLog.instance
          .result('Actions', _t('cancelRequested'), '#${widget.runId}');
      await _detailC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        _t('cancelFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('cancelFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 统一提示入口（Phase 5 后半收敛）：**提示长什么样、什么语气只有一处定义**
  /// （见 [OgLNotifier]，即 `surface/app/notifier.dart`）—— 本页不再自造 SnackBar。
  ///
  /// 语气分工：[OgLNotifier.success] 操作已生效 / [OgLNotifier.info] 普通说明 /
  /// [OgLNotifier.warning] 失败与"被拦下"（权限不足、目标不存在、写回失败…）。
  OgLNotifier get _notifier => OgLNotifier(ScaffoldMessenger.of(context));

  /// 单个构建产物条目：名称 / 大小 / 有效期 + 下载按钮。
  Widget _artifactTile(ThemeData theme, Map<String, dynamic> artifact) {
    final String name = ghStr(artifact, 'name');
    final int size = ghInt(artifact, 'size_in_bytes');
    final bool expired = artifact['expired'] == true;
    final String expires = ghDate(artifact, 'expires_at');
    final String sizeText = size > 0 ? ghSizeText(size) : '';
    final String meta = <String>[
      if (sizeText.isNotEmpty) sizeText,
      if (expired)
        _t('artifactExpired')
      else if (expires.isNotEmpty)
        _t('artifactExpiresAt', <String, Object?>{'at': expires}),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: meta.isEmpty ? null : Text(meta),
        trailing: IconButton(
          icon: const Icon(Icons.download_outlined),
          // 已过期的产物点了也只是失败，直接禁用比让它报错更诚实。
          tooltip: _t('downloadArtifact'),
          onPressed:
              expired ? null : () => unawaited(_downloadArtifact(artifact)),
        ),
      ),
    );
  }

  /// 下载一个构建产物。
  ///
  /// 产物端点在 `api.github.com` 上、**必须带令牌**，因此走与 Release 相同的
  /// 两步：① 本地解 302 换签名地址（令牌不出设备）；② 按加速策略决定是否交给
  /// 代理。产物大小拿不到（要先下才知道），按「值得加速」处理。
  Future<void> _downloadArtifact(Map<String, dynamic> artifact) async {
    final int id = ghInt(artifact, 'id');
    final String name = ghStr(artifact, 'name');
    if (id <= 0 || name.isEmpty) {
      _notifier.warning(_t('artifactNoUrl'));
      return;
    }
    try {
      final String first =
          widget.surface.domain.api.artifactDownloadUrl(widget.fullName, id);
      final String direct = await widget.surface.resolveDownloadUrl(first);
      final bool presigned = direct != first;
      final List<String> urls = ogLAccelCandidates(
        url: direct,
        // 预解析失败时**放弃加速**：否则等于把令牌送给代理。
        // 适用范围：Action 构建产物（运行日志不走加速，见 OgLAccelScope）。
        prefixes: presigned
            ? widget.surface.settings.settings
                .accelPrefixesFor(OgLAccelScope.actionArtifact)
            : const <String>[],
        family: OgLAccelFamily.signed,
      );
      final Map<String, String> headers = presigned
          ? const <String, String>{}
          : await widget.surface.downloadAuthHeaders();
      await widget.surface.domain.downloads.enqueue(
        url: urls.first,
        fallbackUrls: urls.skip(1).toList(),
        headers: headers,
        fileName: name,
        category: IxDownloadCategory.artifact,
        connections: widget.surface.settings.settings.downloadConnections,
      );
      if (mounted) {
        OgLDownloadNotice.instance.show(context, widget.surface,
            message: _t('artifactAdded', <String, Object?>{'name': name}));
      }
    } catch (error) {
      if (mounted) {
        _notifier.warning(
          _t('artifactAddFailed', <String, Object?>{'error': error}),
        );
      }
    }
  }

  IconData _statusIcon(String status, String conclusion) {
    if (status != 'completed') {
      return Icons.sync;
    }
    switch (conclusion) {
      case 'success':
        return Icons.check_circle;
      case 'failure':
      case 'timed_out':
        return Icons.error;
      case 'cancelled':
      case 'skipped':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  Color _statusColor(ThemeData theme, String status, String conclusion) {
    if (status != 'completed') {
      return theme.colorScheme.primary;
    }
    switch (conclusion) {
      case 'success':
        return const Color(0xFF1A7F37);
      case 'failure':
      case 'timed_out':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }

  /// 把步骤/作业的 `started_at` → `completed_at` 折成"耗时"（缺失返回空串）。
  static String _durationText(Map<String, dynamic> node) {
    final DateTime? start = DateTime.tryParse(ghStr(node, 'started_at'));
    final DateTime? end = DateTime.tryParse(ghStr(node, 'completed_at'));
    if (start == null || end == null) {
      return '';
    }
    final Duration d = end.difference(start);
    if (d.isNegative) {
      return '';
    }
    if (d.inSeconds < 60) {
      return _t('durationSecs', {'secs': d.inSeconds});
    }
    return _t(
        'durationMinSecs', {'mins': d.inMinutes, 'secs': d.inSeconds % 60});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('runNumber', {
            'number': '${ghInt(widget.run, 'run_number')}',
          }),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: _t('viewLogs'),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => ActionLogPage(
                    surface: widget.surface,
                    fullName: widget.fullName,
                    runId: widget.runId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AsyncView<_RunDetail>(
        controller: _detailC(),
        emptyText: _t('noRunDetail'),
        builder: (BuildContext context, _RunDetail detail) {
          final Map<String, dynamic> run = detail.run;
          final String status = ghStr(run, 'status');
          final String conclusion = ghStr(run, 'conclusion');
          final String htmlUrl = ghStr(run, 'html_url');
          final bool running = status != 'completed';
          return RefreshIndicator(
            onRefresh: () => _detailC().load(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                // 头部（常量级）：状态 / 操作按钮 /「作业」标题 /（空态提示）。
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              _statusIcon(status, conclusion),
                              color: _statusColor(theme, status, conclusion),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ghStr(run, 'display_title').isEmpty
                                    ? ghStr(run, 'name')
                                    : ghStr(run, 'display_title'),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${ghStr(run, 'name')} · ${ghStr(run, 'event')} · '
                          '${ghStr(run, 'head_branch')} · ${ghShortSha(ghStr(run, 'head_sha'))}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_t('status', {'status': status})}'
                          '${conclusion.isEmpty ? '' : ' / $conclusion'} · '
                          '${ghDate(run, 'created_at')}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            if (!running)
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : _rerun,
                                icon: const Icon(Icons.refresh),
                                label: Text(_t('rerun')),
                              ),
                            if (running)
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _cancel,
                                icon: const Icon(Icons.cancel_outlined),
                                label: Text(_t('cancelRun')),
                              ),
                            if (htmlUrl.isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  unawaited(openLinkOrCopy(context, htmlUrl,
                                      tag: 'Actions'));
                                },
                                icon: const Icon(Icons.open_in_new),
                                label: Text(_t('openInBrowser')),
                              ),
                          ],
                        ),
                        const Divider(height: 32),
                        // 构建产物：有才显示（老运行的产物已被 GitHub 清理时不留空位）。
                        if (detail.artifacts.isNotEmpty) ...<Widget>[
                          Text(_t('artifacts'),
                              style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          for (final Map<String, dynamic> artifact
                              in detail.artifacts)
                            _artifactTile(theme, artifact),
                          const Divider(height: 32),
                        ],
                        Text(_t('jobs'), style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (detail.jobs.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(_t('noJobs')),
                          )
                      ],
                    ),
                  ),
                ),
                // 作业：按需构建（作业/步骤可以很多）。
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: detail.jobs.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, dynamic> job = detail.jobs[index];
                      return Card(
                        child: ExpansionTile(
                          leading: Icon(
                            _statusIcon(
                              ghStr(job, 'status'),
                              ghStr(job, 'conclusion'),
                            ),
                            color: _statusColor(
                              theme,
                              ghStr(job, 'status'),
                              ghStr(job, 'conclusion'),
                            ),
                          ),
                          title: Text(
                            ghStr(job, 'name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${ghStr(job, 'status')} · '
                            '${ghStr(job, 'conclusion').isEmpty ? '—' : ghStr(job, 'conclusion')}',
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          children: <Widget>[
                            for (final Object? rawStep in (job['steps'] is List
                                ? job['steps'] as List<Object?>
                                : const <Object?>[]))
                              if (rawStep is Map<Object?, Object?>)
                                Builder(builder: (BuildContext context) {
                                  final Map<String, dynamic> step =
                                      Map<String, dynamic>.from(rawStep);
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      _statusIcon(
                                        ghStr(step, 'status'),
                                        ghStr(step, 'conclusion'),
                                      ),
                                      size: 18,
                                      color: _statusColor(
                                        theme,
                                        ghStr(step, 'status'),
                                        ghStr(step, 'conclusion'),
                                      ),
                                    ),
                                    title: Text(
                                      '${ghInt(step, 'number')}. ${ghStr(step, 'name')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      <String>[
                                        ghStr(step, 'status'),
                                        if (ghStr(step, 'conclusion')
                                            .isNotEmpty)
                                          ghStr(step, 'conclusion'),
                                        if (_durationText(step).isNotEmpty)
                                          _durationText(step),
                                      ].join(' · '),
                                    ),
                                  );
                                }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    );
  }
}
