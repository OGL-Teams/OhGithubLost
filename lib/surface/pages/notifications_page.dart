/// L3 展示级 · 通知中心（运行事件与错误）。
///
/// 汇总应用运行期的事件：成功结果、告警与错误。
/// 数据来自 [OgLAppLog]（同时落盘），可展开看**完整详情**、标记已读、复制单条。
///
/// R1 修复：此前条目只能看到一行被截断的摘要，也没有"已读"概念。
/// 现在：
/// - 点击条目 → 展开完整详情（时间 / 区域 / 正文）；
/// - 未读条目标题加粗，行尾提供"标记已读"；
/// - 顶栏提供"全部已读"与"重置通知中心"（清空内存条目，不动磁盘日志）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../util/clipboard_x.dart';

/// 取 `notifications_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('notifications_page', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 通知中心页。
class NotificationsPage extends StatefulWidget {
  /// 创建页面。
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  /// 过滤：0 全部 / 1 告警 / 2 错误。
  int _filter = 0;

  /// 已展开详情的条目（按标识去重）。
  final Set<String> _expanded = <String>{};

  static String _idOf(OgLAppLogEntry entry) =>
      '${entry.at.microsecondsSinceEpoch}|${entry.area}|${entry.message}';

  static String _fmt(DateTime time) {
    final DateTime t = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  bool _match(OgLAppLogEntry entry) {
    switch (_filter) {
      case 1:
        return entry.severity == OgLNoticeSeverity.warning ||
            entry.severity == OgLNoticeSeverity.critical;
      case 2:
        return entry.severity == OgLNoticeSeverity.critical;
      default:
        return true;
    }
  }

  Future<void> _confirmReset() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('resetTitle')),
        content:  Text(_t('resetDesc')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('reset')),
          ),
        ],
      ),
    );
    if (ok == true) {
      OgLAppLog.instance.clear();
      if (mounted) {
        setState(_expanded.clear);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title:  Text(_t('title')),
        actions: <Widget>[
          IconButton(
            tooltip: _t('markAllRead'),
            icon: const Icon(Icons.done_all),
            onPressed: OgLAppLog.instance.markAllRead,
          ),
          IconButton(
            tooltip: _t('resetTitle'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => unawaited(_confirmReset()),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SegmentedButton<int>(
              segments:  <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text(_t('filterAll'))),
                ButtonSegment<int>(value: 1, label: Text(_t('filterWarning'))),
                ButtonSegment<int>(value: 2, label: Text(_t('filterError'))),
              ],
              selected: <int>{_filter},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> selection) {
                if (selection.isNotEmpty) {
                  setState(() => _filter = selection.first);
                }
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: OgLAppLog.instance,
              builder: (BuildContext context, Widget? _) {
                final List<OgLAppLogEntry> entries =
                    OgLAppLog.instance.entries.where(_match).toList();
                if (entries.isEmpty) {
                  return Center(
                    child: Text(_t('empty'), style: theme.textTheme.bodySmall),
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final OgLAppLogEntry entry = entries[index];
                    final String id = _idOf(entry);
                    final bool read = OgLAppLog.instance.isRead(entry);
                    final bool expanded = _expanded.contains(id);
                    return OgLReveal(
                      delay: OgLAnim.staggerOf(context, index),
                      child: _NotificationTile(
                        entry: entry,
                        read: read,
                        expanded: expanded,
                        timeText: _fmt(entry.at),
                        icon: _iconOf(entry.severity),
                        color: _colorOf(theme, entry.severity),
                        onToggle: () => setState(() {
                          if (expanded) {
                            _expanded.remove(id);
                          } else {
                            _expanded.add(id);
                            OgLAppLog.instance.markRead(entry);
                          }
                        }),
                        onMarkRead: () => OgLAppLog.instance.markRead(entry),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconOf(OgLNoticeSeverity severity) => switch (severity) {
        OgLNoticeSeverity.critical => Icons.error_outline,
        OgLNoticeSeverity.warning => Icons.warning_amber_rounded,
        OgLNoticeSeverity.info => Icons.check_circle_outline,
      };

  static Color _colorOf(ThemeData theme, OgLNoticeSeverity severity) =>
      switch (severity) {
        OgLNoticeSeverity.critical => theme.colorScheme.error,
        OgLNoticeSeverity.warning => theme.colorScheme.tertiary,
        OgLNoticeSeverity.info => theme.colorScheme.primary,
      };
}

/// 单条通知（可展开详情）。
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.entry,
    required this.read,
    required this.expanded,
    required this.timeText,
    required this.icon,
    required this.color,
    required this.onToggle,
    required this.onMarkRead,
  });

  final OgLAppLogEntry entry;
  final bool read;
  final bool expanded;
  final String timeText;
  final IconData icon;
  final Color color;
  final VoidCallback onToggle;
  final VoidCallback onMarkRead;

  Future<void> _copyEntryText(
    BuildContext context,
    OgLAppLogEntry entry,
  ) async {
    if (!await ogLCopyText(entry.toDisplay(), tag: 'Notifications')) {
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('copiedEvent'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      // 通知开关是「可切换项」：屏幕阅读器要能念出标题与开关状态，
      // 否则用户只能看到一行文字，不知道点了会发生什么。
      toggled: OgLAppLog.instance.isRead(entry),
      button: true,
      label: entry.message,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.message,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: read ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.area} · $timeText'
                    '${read ? '' : ' · ${_t('unread')}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: read
                          ? theme.colorScheme.outline
                          : theme.colorScheme.primary,
                    ),
                  ),
                  // 5.0：详情展开带动画（此前是「啪」地出现）。
                  // 用 AnimatedSize 让高度平滑变化；关闭动画时直接跳变。
                  AnimatedSize(
                    duration: OgLAnim.enabled(context)
                        ? OgLAnim.fast(context)
                        : Duration.zero,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const SizedBox(height: 8),
                              // 完整详情：不截断，可选中复制。
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  entry.toDisplay(),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: <Widget>[
                                  TextButton.icon(
                                    onPressed: () {
                                      unawaited(_copyEntryText(context, entry));
                                    },
                                    icon: const Icon(Icons.content_copy,
                                        size: 16),
                                    label:  Text(_t('copy')),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
            if (!read)
              IconButton(
                tooltip: _t('markRead'),
                icon: const Icon(Icons.done, size: 18),
                onPressed: onMarkRead,
              ),
            // 展开指示：图标旋转（不用任何 emoji / 符号字形）。
            IgnorePointer(
              child: AnimatedRotation(
                duration: OgLAnim.enabled(context)
                    ? OgLAnim.fast(context)
                    : Duration.zero,
                turns: expanded ? 0.5 : 0,
                child: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
