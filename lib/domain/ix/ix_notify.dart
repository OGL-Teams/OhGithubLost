/// L2 中枢级 · 交互逻辑：通知与告警汇总。
///
/// 把三类东西收敛成一个用户能看懂的列表：
/// 1. **信任告警**（MOd/主题装载，见 `docs/BOOT.md（该文件未落地，以源码为准）`）——由装配层映射后投递；
/// 2. **审计告警**（内核诊断里的 warn/error，如 D6/D10 的拒绝）；
/// 3. **运行告警**（同步失败、额度耗尽、批量任务结果）。
///
/// 纪律：
/// - **同类告警去重**（同一个 code + 同一对象只保留最新一条并累加次数）；
/// - **不静默丢弃**：被抑制的条目数会累计在 [IxNotification.suppressedCount]；
/// - 告警等级只影响展示，**不影响"是否记录"**。
library;

import 'package:flutter/foundation.dart';

import '../../kernel/diagnostics.dart';

/// 告警等级。
enum IxNotificationLevel {
  /// 提示。
  info,

  /// 警告（需要用户知情）。
  warning,

  /// 危险（数据安全相关，必须醒目标出）。
  danger,
}

/// 一条通知。
class IxNotification {
  /// 创建通知。
  const IxNotification({
    required this.id,
    required this.level,
    required this.title,
    required this.message,
    required this.createdAt,
    this.code,
    this.source,
    this.dismissible = true,
    this.count = 1,
    this.suppressedCount = 0,
    this.actions = const <String>[],
  });

  /// 稳定 ID（去重键：`source|code|subject`）。
  final String id;

  /// 等级。
  final IxNotificationLevel level;

  /// 标题。
  final String title;

  /// 正文。
  final String message;

  /// 产生时间。
  final DateTime createdAt;

  /// 事件码（如 `OGL-CONS-202`）。
  final String? code;

  /// 来源（如 `CACHE` / `BOOT`）。
  final String? source;

  /// 是否可关闭（安全类告警可设为不可关）。
  final bool dismissible;

  /// 重复次数。
  final int count;

  /// 被抑制（合并）的条数。
  final int suppressedCount;

  /// 建议动作（展示用文案键）。
  final List<String> actions;

  /// 复制并累加一次重复。
  IxNotification bump() => IxNotification(
        id: id,
        level: level,
        title: title,
        message: message,
        createdAt: createdAt,
        code: code,
        source: source,
        dismissible: dismissible,
        count: count + 1,
        suppressedCount: suppressedCount + 1,
        actions: actions,
      );

  @override
  String toString() =>
      'IxNotification(${level.name}, $title${count > 1 ? ' ×$count' : ''})';
}

/// 通知中心。
class IxNotificationCenter extends ChangeNotifier {
  /// 创建通知中心。
  IxNotificationCenter({this.maxEntries = 200});

  /// 条目上限（超出时淘汰最旧的**可关闭**条目）。
  final int maxEntries;

  final List<IxNotification> _items = <IxNotification>[];
  final Set<String> _dismissed = <String>{};

  /// 全部通知（新→旧）。
  List<IxNotification> get items => List<IxNotification>.unmodifiable(_items);

  /// 未读数量（未关闭的数量）。
  int get unreadCount => _items.length;

  /// 是否存在危险级告警（UI 用来显示红点）。
  bool get hasDanger => _items
      .any((IxNotification item) => item.level == IxNotificationLevel.danger);

  /// 投递一条通知；同 ID 会合并计数而不是堆叠。
  void push({
    required IxNotificationLevel level,
    required String title,
    required String message,
    String? code,
    String? source,
    String? subject,
    bool dismissible = true,
    List<String> actions = const <String>[],
  }) {
    final id = <String?>[source, code, subject].whereType<String>().join('|');
    final key = id.isEmpty ? '$title|$message' : id;
    final index = _items.indexWhere((IxNotification item) => item.id == key);
    if (index >= 0) {
      _items[index] = _items[index].bump();
      // 重新触发一次，让 UI 把合并后的条目移到最前。
      final merged = _items.removeAt(index);
      _items.insert(0, merged);
      notifyListeners();
      return;
    }
    _items.insert(
      0,
      IxNotification(
        id: key,
        level: level,
        title: title,
        message: message,
        createdAt: DateTime.now(),
        code: code,
        source: source,
        dismissible: dismissible,
        actions: actions,
      ),
    );
    _trim();
    notifyListeners();
  }

  /// 从内核诊断记录导入（只导 warn / error，避免刷屏）。
  ///
  /// [since] 之后已导入过的条目会被跳过——由调用方传上次的水位。
  int ingestDiagnostics(
    List<KernelLogEntry> entries, {
    DateTime? since,
  }) {
    var imported = 0;
    for (final entry in entries) {
      if (entry.level != KernelLogLevel.warn &&
          entry.level != KernelLogLevel.error) {
        continue;
      }
      if (since != null && !entry.timestamp.isAfter(since)) {
        continue;
      }
      push(
        level: entry.level == KernelLogLevel.error
            ? IxNotificationLevel.danger
            : IxNotificationLevel.warning,
        title: entry.message,
        message: entry.tag,
        code: entry.code,
        source: entry.tag,
        subject: '${entry.data}',
        dismissible: entry.level != KernelLogLevel.error,
      );
      imported++;
    }
    return imported;
  }

  /// 关闭一条。
  void dismiss(String id) {
    final before = _items.length;
    _items.removeWhere(
        (IxNotification item) => item.id == id && item.dismissible);
    if (_items.length != before) {
      _dismissed.add(id);
      notifyListeners();
    }
  }

  /// 清空全部可关闭条目（不可关闭的安全告警会保留）。
  int clearDismissible() {
    final before = _items.length;
    _items.removeWhere((IxNotification item) => item.dismissible);
    final removed = before - _items.length;
    if (removed > 0) {
      notifyListeners();
    }
    return removed;
  }

  /// 是否曾被关闭过（用于"不再提示"）。
  bool wasDismissed(String id) => _dismissed.contains(id);

  void _trim() {
    while (_items.length > maxEntries) {
      final index = _items.lastIndexWhere(
        (IxNotification item) => item.dismissible,
      );
      if (index < 0) {
        return; // 全是不可关闭的：宁可超限，也不丢安全告警。
      }
      _items.removeAt(index);
    }
  }
}
