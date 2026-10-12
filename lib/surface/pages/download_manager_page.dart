/// L3 展示级 · 下载管理（列表 + 进度 + 控制）。
///
/// - 逐条展示：文件名、分类、状态、大小 / 进度、速率；
/// - 控制：暂停 / 继续 / 取消 / 重试 / 移除 / 打开 / 复制路径；
/// - 数据来自中枢层的 [IxDownloadManager]（进度节流广播）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/animations.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/clipboard_x.dart';
import '../util/gh_format.dart';

/// 取 `download_manager_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('download_manager_page', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 下载已入队：弹 SnackBar，带「查看下载」动作跳转到下载中心。
void ogLShowDownloadQueued(
  BuildContext context,
  SurfaceBridge surface,
  String message,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
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
class DownloadManagerPage extends StatelessWidget {
  /// 创建页面。
  const DownloadManagerPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;


  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title:  Text(_t('title')),
        actions: <Widget>[
          IconButton(
            tooltip: _t('clearFinished'),
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: surface.clearFinishedDownloads,
          ),
        ],
      ),
      body: ListenableBuilder(
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
    );
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
            // 5.0：进度条**平滑插值**（库的进度事件 200ms 一跳，
            // 直接绑值会出现"跳格子"；这里补间 220ms，观感连续）。
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: task.total > 0 ? task.progress : 0,
              ),
              duration: OgLAnim.fast(context),
              curve: Curves.easeOut,
              builder: (
                BuildContext context,
                double value,
                Widget? child,
              ) =>
                  LinearProgressIndicator(
                value: task.total > 0 ? value.clamp(0.0, 1.0) : null,
                minHeight: 4,
              ),
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
            // 显示下载失败原因：
            // 1) 强类型（Web 后端）走 `_t('downloadFailed.${reason.name}')`；
            // 2) 兜底走 `task.error`（自由文本，如 `'integrityMismatch'`）
            //    —— 但不再"直接打印 String"，而是查 `failure.<key>`，缺则回退。
            if (task.failureReason != null || task.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _failureText(task),
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
                if (active || task.status == IxDownloadStatus.queued)
                  IconButton(
                    tooltip: _t('pause'),
                    icon: const Icon(Icons.pause),
                    onPressed: () => unawaited(surface.pauseDownload(task.id)),
                  ),
                if (paused)
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
                  if (!kIsWeb)
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
                  onPressed: () => unawaited(surface.removeDownload(task.id)),
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
  static String _categoryLabel(IxDownloadCategory category) => switch (category) {
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

  /// 失败原因 → 本地化文案。
  ///
  /// 优先枚举（Web 后端），缺键时回退到 `task.error` 的 i18n 映射，
  /// 再缺就回退到键名（**绝不返回空串**）。
  static String _failureText(IxDownloadTask task) {
    final IxDownloadFailureReason? reason = task.failureReason;
    if (reason != null && reason != IxDownloadFailureReason.ok) {
      // `_t` 的兜底链：当前语言 → en → 键名；键名不会空。
      final String localized = _t('downloadFailed.${reason.name}');
      // 兜底：如果键尚未翻译，至少把"开发期英文"也算上。
      if (localized != 'downloadFailed.${reason.name}') {
        return localized;
      }
      return IX_DOWNLOAD_FAILURE_FALLBACK;
    }
    final String? raw = task.error;
    if (raw == null || raw.isEmpty) {
      return _t('statusFailed');
    }
    // `task.error` 不是域枚举而是自由文本：用 `failure.<error>` 查 i18n，
    // 没有就回退到自由文本（仍是有用信息，而不是把英文键名丢给用户）。
    final String localized = _t('failure.$raw');
    if (localized != 'failure.$raw') {
      return localized;
    }
    return raw;
  }

  Future<void> _openLocal(BuildContext context, IxDownloadTask task) async {
    // Web 上的「打开」只是导航到下载 URL（成品由浏览器接管）；
    // 非 Web 上传的是真实本地路径，必须走 `Uri.file`，否则 `launchUrl` 解析
    // 不了 `C:\…` / 空格，转头向用户报"无应用打开"——实际上路径根本没读对。
    final Uri target = kIsWeb
        ? (Uri.tryParse(task.savePath) ?? Uri.parse(task.url))
        : Uri.file(task.savePath);
    try {
      final bool ok = await launchUrl(
        target,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        throw StateError(_t('noAppForFile'));
      }
    } catch (error) {
      // 失败兜底：复制路径给用户，并显示带 i18n 键的失败原因（不再吞）。
      if (!await ogLCopyText(task.savePath, tag: 'Download')) {
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('downloadOpenFailed', <String, Object?>{
            'reason': error.toString(),
          }))),
        );
      }
    }
  }

  Future<void> _copyPath(BuildContext context, IxDownloadTask task) async {
    if (!await ogLCopyText(task.savePath, tag: 'Download')) {
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('pathCopied'))),
      );
    }
  }
}