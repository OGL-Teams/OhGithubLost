/// L3 展示级 · 下载管理（列表 + 进度 + 控制）。
///
/// - 逐条展示：文件名、分类、状态、大小 / 进度、速率；
/// - 控制：暂停 / 继续 / 取消 / 重试 / 移除 / 打开 / 复制路径；
/// - 数据来自中枢层的 [IxDownloadManager]（进度节流广播）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/animations.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/clipboard_x.dart';
import '../util/gh_format.dart';

/// 取 `download_manager_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'download_manager_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 下载已入队：弹 SnackBar，带「查看下载」动作跳转到下载中心。
///
/// 修「开始下载但看不到下载中心」：入队成功后不再只给一句提示，
/// 而是给出可直接跳转的入口。
void ogLShowDownloadQueued(
  BuildContext context,
  SurfaceBridge surface,
  String message,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      // 带「查看下载」动作的横幅应**长一点**：M3 默认 4s 容易
      // 在用户读完文件名之前就收回（特别是点了 "viewDownloads" 但
      // 不去点跳转的情况——横幅消失后就没入口了）。给 8s 留出决定时间。
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: OgLI18n.instance.t('common', 'viewDownloads'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => DownloadManagerPage(surface: surface),
          ),
        ),
      ),
    ),
  );
}

/// 下载管理页。
class DownloadManagerPage extends StatefulWidget {
  /// 创建页面。
  const DownloadManagerPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<DownloadManagerPage> createState() => _DownloadManagerPageState();
}

class _DownloadManagerPageState extends State<DownloadManagerPage> {
  /// 上次被移除的任务（供「撤销移除」恢复列表位置）。
  ///
  /// 只保留一条：移除是高频误触操作，但撤销多步会变成"历史管理"，
  /// 超出本页职责。移除后立即出现撤销入口，下一次移除覆盖它。
  IxDownloadTask? _lastRemoved;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SurfaceBridge surface = widget.surface;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: <Widget>[
          // 失败/取消的任务逐个点「重试」太累：一键重来全部失败项。
          IconButton(
            tooltip: _t('retryAllFailed'),
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _retryAllFailed(surface),
          ),
          IconButton(
            tooltip: _t('clearFinished'),
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: surface.clearFinishedDownloads,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 撤销条：移除后立刻出现，点一下把任务放回列表。
          if (_lastRemoved != null)
            Material(
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.undo,
                    size: 18, color: theme.colorScheme.onSecondaryContainer),
                title: Text(
                  _t('removedItem', {'name': _lastRemoved!.fileName}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                trailing: TextButton(
                  onPressed: _undoRemove,
                  child: Text(_t('undoRemove')),
                ),
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: surface.downloadsListenable,
              builder: (BuildContext context, Widget? _) {
                final List<IxDownloadTask> tasks = surface.downloadTasks;
                if (tasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.download_outlined,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(_t('empty')),
                        const SizedBox(height: 4),
                        Text(
                          _t('emptyHint'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) => OgLReveal(
                    delay: OgLAnim.staggerOf(context, index),
                    child: _taskCard(context, theme, tasks[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 一键重试**全部**失败 / 已取消的任务（逐个点太累）。
  Future<void> _retryAllFailed(SurfaceBridge surface) async {
    final List<IxDownloadTask> failed = surface.downloadTasks
        .where((IxDownloadTask t) =>
            t.status == IxDownloadStatus.failed ||
            t.status == IxDownloadStatus.canceled)
        .toList();
    if (failed.isEmpty) {
      OgLNotifier.of(context).info(_t('noFailedToRetry'));
      return;
    }
    for (final IxDownloadTask task in failed) {
      await surface.retryDownload(task.id);
    }
    if (mounted) {
      OgLNotifier.of(context).success(_t('retriedCount', {'n': failed.length}));
    }
  }

  /// 记录被移除的任务（供撤销条显示）。
  void _noteRemoved(IxDownloadTask task) {
    setState(() => _lastRemoved = task);
  }

  /// 撤销上次移除：把任务重新入列（重新走一遍下载）。
  ///
  /// 说明：本页只保存**元数据**（id / 文件名 / 地址），真正重新下载由
  /// 中枢层 `retry` 完成——所以撤销 = 重新入队，不是"恢复已完成的文件"。
  Future<void> _undoRemove() async {
    final IxDownloadTask? task = _lastRemoved;
    if (task == null) {
      return;
    }
    setState(() => _lastRemoved = null);
    await widget.surface.retryDownload(task.id);
  }

  Widget _taskCard(BuildContext context, ThemeData theme, IxDownloadTask task) {
    final bool active = task.status == IxDownloadStatus.running;
    final bool paused = task.status == IxDownloadStatus.paused;
    final bool done = task.status == IxDownloadStatus.completed;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_iconFor(task.category), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  _statusLabel(task.status),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // `total > 0` 才画进度条：Web 上总大小恒为 `0`（浏览器下载不向
            // 页面回报大小），无值进度条只会一直空转；此时照实写明
            // 「已交给浏览器下载」，不假装量得出进度。
            if (task.total > 0)
              // 5.0：进度条**平滑插值**（库的进度事件 200ms 一跳，
              // 直接绑值会出现"跳格子"；这里补间 220ms，观感连续）。
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: task.progress),
                duration: OgLAnim.fast(context),
                curve: OgLAnim.curve(context),
                builder: (
                  BuildContext context,
                  double value,
                  Widget? child,
                ) =>
                    LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: 4,
                ),
              )
            else
              Text(
                _t('handedToBrowser'),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                if (surface.domain.downloads.isRanged(task.id))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: _t('multiConnection'),
                      child: Icon(
                        Icons.multiple_stop,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: OgLAnim.enabled(context)
                        ? OgLAnim.fast(context)
                        : Duration.zero,
                    // 速率量化到 0.1 MB/s：小数位抖动不再触发重建。
                    child: Text(
                      _subtitleOf(task),
                      key: ValueKey<String>(
                        _quantizeSpeed(task.bytesPerSecond),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
            if (task.errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.errorText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (surface.supportsPauseResume &&
                    (active || task.status == IxDownloadStatus.queued))
                  IconButton(
                    tooltip: _t('pause'),
                    icon: const Icon(Icons.pause),
                    onPressed: () => unawaited(surface.pauseDownload(task.id)),
                  ),
                if (surface.supportsPauseResume && paused)
                  IconButton(
                    tooltip: _t('resume'),
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => unawaited(surface.resumeDownload(task.id)),
                  ),
                if (task.status == IxDownloadStatus.failed ||
                    task.status == IxDownloadStatus.canceled)
                  IconButton(
                    tooltip: _t('retry'),
                    icon: const Icon(Icons.refresh),
                    onPressed: () => unawaited(surface.retryDownload(task.id)),
                  ),
                if (active || task.status == IxDownloadStatus.queued || paused)
                  IconButton(
                    tooltip: _t('cancel'),
                    icon: const Icon(Icons.close),
                    onPressed: () => unawaited(surface.cancelDownload(task.id)),
                  ),
                if (done) ...<Widget>[
                  IconButton(
                    tooltip: _t('open'),
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => unawaited(_openLocal(context, task)),
                  ),
                  IconButton(
                    tooltip: _t('copyPath'),
                    icon: const Icon(Icons.content_copy),
                    onPressed: () => unawaited(_copyPath(context, task)),
                  ),
                ],
                IconButton(
                  tooltip: _t('remove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    _noteRemoved(task);
                    await surface.removeDownload(task.id);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(IxDownloadCategory category) => switch (category) {
        IxDownloadCategory.release => Icons.new_releases_outlined,
        IxDownloadCategory.repo => Icons.folder_zip_outlined,
        IxDownloadCategory.gist => Icons.article_outlined,
        IxDownloadCategory.artifact => Icons.inventory_2_outlined,
        IxDownloadCategory.other => Icons.download_outlined,
      };

  /// 分类展示名（**走 i18n**）。
  ///
  /// 注意：`IxDownloadCategory.label` 是域层的开发者可读串（中文），**不能直接
  /// 显示在界面上** —— 那会让非中文用户在下载管理页看到中文。域层不参与 i18n
  /// 扫描（`i18n_scan` 只看 `lib/surface/`），所以这类问题门禁抓不到，只能靠
  /// 「界面文案一律经 `_t`」这条纪律守住。
  static String _categoryLabel(IxDownloadCategory category) =>
      switch (category) {
        IxDownloadCategory.release => _t('categoryRelease'),
        IxDownloadCategory.repo => _t('categoryRepo'),
        IxDownloadCategory.gist => _t('categoryGist'),
        IxDownloadCategory.artifact => _t('categoryArtifact'),
        IxDownloadCategory.other => _t('categoryOther'),
      };

  /// 状态展示名（**走 i18n**，理由同上）。
  static String _statusLabel(IxDownloadStatus status) => switch (status) {
        IxDownloadStatus.queued => _t('statusQueued'),
        IxDownloadStatus.running => _t('statusRunning'),
        IxDownloadStatus.paused => _t('statusPaused'),
        IxDownloadStatus.completed => _t('statusCompleted'),
        IxDownloadStatus.failed => _t('statusFailed'),
        IxDownloadStatus.canceled => _t('statusCanceled'),
      };

  /// 副标题（分类 · 大小 · 速率）。
  ///
  /// 速率按 **0.1 MB/s 粒度**取整后再进 [AnimatedSwitcher]，避免每帧
  /// 因为小数位抖动而反复重建文本。
  /// 速率量化（0.1 MB/s 一档）：让 AnimatedSwitcher 只在「肉眼可见的变化」时换文本。
  static String _quantizeSpeed(double bytesPerSecond) =>
      (bytesPerSecond / 102400).round().toString();

  static String _subtitleOf(IxDownloadTask task) {
    final String size = task.total > 0
        ? '${ghSizeText(task.received)} / ${ghSizeText(task.total)}'
        : ghSizeText(task.received);
    final String speed = task.status == IxDownloadStatus.running
        ? ' · ${ghSizeText(task.bytesPerSecond.round())}/s'
        : '';
    return '${_categoryLabel(task.category)} · $size$speed';
  }

  Future<void> _openLocal(BuildContext context, IxDownloadTask task) async {
    try {
      // Web 上 `savePath` 是**下载地址**（http/https URL），不是文件路径：
      // 此前一律 `Uri.file()` 会拼出一个打不开的伪路径。
      // 原生上 `savePath` 是真实文件路径（可能无 scheme / 带 Windows 盘符），
      // 仍走 `Uri.file()` 规范化；已是 `file://` 形式的则原样使用。
      final Uri? parsed = Uri.tryParse(task.savePath);
      final Uri uri;
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        uri = parsed;
      } else if (parsed != null && parsed.scheme == 'file') {
        uri = parsed;
      } else {
        uri = Uri.file(task.savePath);
      }
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw StateError(_t('noAppForFile'));
      }
    } catch (_) {
      await ogLCopyText(task.savePath, tag: '下载路径');
      if (context.mounted) {
        OgLNotifier.of(context).info(_t('cannotOpenCopied'));
      }
    }
  }

  Future<void> _copyPath(BuildContext context, IxDownloadTask task) async {
    await ogLCopyText(task.savePath, tag: '下载路径');
    if (context.mounted) {
      OgLNotifier.of(context).success(_t('pathCopied'));
    }
  }
}
