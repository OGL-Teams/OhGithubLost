/// L1 底座级 · 硬盘逻辑：提交日志（Write Journal，防线 D8）。
///
/// ## 它解决什么问题
/// 没有日志时，"提交"是**一次易失的网络调用**：
/// 用户点了提交 → 网络断 / App 被杀 → 这次提交**彻底消失，无人知道**。
///
/// 有了日志，"提交"升级为**可恢复的事务**：
/// ```
/// 写前：落盘一条 pending 记录（含内容与基线）
/// 写入：成功 → 移除记录；可重试失败 → 保留 pending；语义冲突 → 标记 abandoned
/// 重启：pending 列表仍在 → 提示用户「有 N 项未完成，是否重试」
/// ```
///
/// ## 为什么重放是安全的
/// 重放**不是**把旧内容硬灌回去，而是把记录还原成 [WriteIntent]
/// 再走一次完整的 `RepositoryCache.write()`——D1/D2/D7 一条不少。
/// 所以「上次提交因为基线过期而失败」的记录，重放时仍会被拦下并再次询问用户。
library;

import 'dart:convert';

import '../../kernel/diagnostics.dart';
import 'disk_store.dart';
import 'disk_types.dart';

/// 提交日志条目状态。
enum JournalStatus {
  /// 待完成（会出现在"待同步"列表里）。
  pending,

  /// 已放弃（语义性冲突，需用户重新决策，**不自动重放**）。
  abandoned,
}

/// 提交日志条目。
class JournalRecord {
  /// 创建条目。
  const JournalRecord({
    required this.id,
    required this.key,
    required this.content,
    required this.message,
    required this.createdAt,
    this.baseSha,
    this.dangerous = false,
    this.attempts = 0,
    this.status = JournalStatus.pending,
    this.lastError,
  });

  /// 条目 ID。
  final String id;

  /// 目标键。
  final CacheKey key;

  /// 待写入内容。
  final String content;

  /// 提交信息。
  final String message;

  /// 起草时所基于的远端版本。
  final String? baseSha;

  /// 是否危险操作。
  final bool dangerous;

  /// 已尝试次数。
  final int attempts;

  /// 状态。
  final JournalStatus status;

  /// 最近一次失败原因。
  final String? lastError;

  /// 创建时间。
  final DateTime createdAt;

  /// 还原为写意图（重放时**重新走 D1–D7**，绝不跳过任何防线）。
  WriteIntent toIntent() => WriteIntent(
        key: key,
        content: content,
        message: message,
        baseSha: baseSha,
        dangerous: dangerous,
      );

  /// 复制并覆盖部分字段。
  JournalRecord copyWith({
    int? attempts,
    JournalStatus? status,
    String? lastError,
  }) =>
      JournalRecord(
        id: id,
        key: key,
        content: content,
        message: message,
        createdAt: createdAt,
        baseSha: baseSha,
        dangerous: dangerous,
        attempts: attempts ?? this.attempts,
        status: status ?? this.status,
        lastError: lastError ?? this.lastError,
      );

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'key': key.encode(),
        'content': content,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        if (baseSha != null) 'baseSha': baseSha,
        'dangerous': dangerous,
        'attempts': attempts,
        'status': status.name,
        if (lastError != null) 'lastError': lastError,
      };

  /// 反序列化；结构不合法时返回 `null`（宁可丢弃，也不猜）。
  static JournalRecord? fromJson(Map<String, dynamic> json) {
    try {
      final key = CacheKey.decode(json['key'] as String);
      if (key == null) {
        return null;
      }
      return JournalRecord(
        id: json['id'] as String,
        key: key,
        content: json['content'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        baseSha: json['baseSha'] as String?,
        dangerous: json['dangerous'] as bool? ?? false,
        attempts: json['attempts'] as int? ?? 0,
        status: JournalStatus.values.firstWhere(
          (JournalStatus value) => value.name == json['status'],
          orElse: () => JournalStatus.pending,
        ),
        lastError: json['lastError'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'JournalRecord($id, ${key.encode()}, ${status.name}, attempts=$attempts)';
}

/// 提交日志（持久化）。
class WriteJournal {
  /// 创建日志。
  WriteJournal({
    DiskKv? store,
    KernelDiagnostics? diagnostics,
    this.namespace = 'ogl.journal.',
  })  : _store = store ?? InMemoryKv(),
        _diagnostics = diagnostics ?? KernelDiagnostics();

  /// 键前缀（多环境隔离用）。
  final String namespace;

  final DiskKv _store;
  KernelDiagnostics _diagnostics;
  int _sequence = 0;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 入队一条提交（**必须在发出写请求之前调用**，否则崩溃窗口无法覆盖）。
  Future<JournalRecord> enqueue(WriteIntent intent) async {
    final record = JournalRecord(
      id: _nextId(),
      key: intent.key,
      content: intent.content,
      message: intent.message,
      createdAt: DateTime.now(),
      baseSha: intent.baseSha,
      dangerous: intent.dangerous,
    );
    await _write(record);
    _diagnostics.warn(
      'JOURNAL',
      '提交已入队',
      code: 'OGL-JOURNAL-001',
      data: <String, Object?>{
        'id': record.id,
        'key': intent.key.encode(),
        'pending': await pendingCount(),
      },
    );
    return record;
  }

  /// 标记完成（移除记录）。
  Future<void> complete(String id) async {
    await _store.remove(_keyOf(id));
    _diagnostics.info(
      'JOURNAL',
      '提交已完成',
      code: 'OGL-JOURNAL-002',
      data: <String, Object?>{'id': id, 'pending': await pendingCount()},
    );
  }

  /// 标记可重试失败（保留 pending，供后续重放）。
  /// 重试上限：超过后转 abandoned——
  /// 无上限的 pending 会让"待同步"永远挂着（用户看到的就是"迟迟不成功"）。
  /// 上限内保持 pending（启动 / 网络恢复时自动重放）。
  static const int maxAttempts = 5;

  Future<void> fail(String id, String error) async {
    final record = await _read(id);
    if (record == null) {
      return;
    }
    final int attempts = record.attempts + 1;
    if (attempts >= maxAttempts) {
      await abandon(id, '重试 $attempts 次仍未成功：$error');
      return;
    }
    await _write(record.copyWith(
      attempts: attempts,
      lastError: error,
    ));
  }

  /// 按目标键标记"可重试失败"。
  ///
  /// 用于**异常路径**：写请求抛出网络异常时，调用栈里已经拿不到记录 ID，
  /// 但队列里那条 pending 必须被标注（否则 UI 上"已尝试次数"永远是 0）。
  ///
  /// **只标注最近的那一条**：同一个键可能因为多次崩溃留下多条 pending
  /// （A 崩了、B 又崩了），而这次异常只属于"刚刚发出的那一发"。
  /// 若把它们全部加一遍，历史记录的尝试次数会虚增，UI 会撒谎。
  Future<void> failByKey(CacheKey key, String error) async {
    final encoded = key.encode();
    JournalRecord? newest;
    for (final record in await records(status: JournalStatus.pending)) {
      if (record.key.encode() != encoded) {
        continue;
      }
      if (newest == null || record.createdAt.isAfter(newest.createdAt)) {
        newest = record;
      }
    }
    if (newest != null) {
      await fail(newest.id, error);
    }
  }

  /// 放弃（语义性冲突，需用户重新决策，**不自动重放**）。
  Future<void> abandon(String id, String reason) async {
    final record = await _read(id);
    if (record == null) {
      return;
    }
    await _write(record.copyWith(
      status: JournalStatus.abandoned,
      lastError: reason,
    ));
    _diagnostics.warn(
      'JOURNAL',
      '提交已放弃（需用户重新决策）',
      code: 'OGL-JOURNAL-003',
      data: <String, Object?>{'id': id, 'reason': reason},
    );
  }

  /// 查询记录（按创建时间升序）。
  Future<List<JournalRecord>> records({JournalStatus? status}) async {
    final result = <JournalRecord>[];
    for (final key in await _store.keys()) {
      if (!key.startsWith(namespace)) {
        continue;
      }
      final raw = await _store.read(key);
      if (raw == null) {
        continue;
      }
      final record = _decode(raw);
      if (record == null) {
        // 结构损坏：清掉，避免每次启动都报错。
        await _store.remove(key);
        continue;
      }
      if (status == null || record.status == status) {
        result.add(record);
      }
    }
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  /// 待完成条目数（UI 角标数据源）。
  Future<int> pendingCount() async =>
      (await records(status: JournalStatus.pending)).length;

  /// 清空全部记录（用户手动清理 / 重置账号）。
  Future<int> clear() async {
    var removed = 0;
    for (final record in await records()) {
      await _store.remove(_keyOf(record.id));
      removed++;
    }
    return removed;
  }

  String _keyOf(String id) => '$namespace$id';

  String _nextId() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  Future<void> _write(JournalRecord record) =>
      _store.write(_keyOf(record.id), jsonEncode(record.toJson()));

  Future<JournalRecord?> _read(String id) async {
    final raw = await _store.read(_keyOf(id));
    return raw == null ? null : _decode(raw);
  }

  JournalRecord? _decode(String raw) {
    try {
      return JournalRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
