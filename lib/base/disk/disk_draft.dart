/// L1 底座级 · 硬盘逻辑：草稿持久化（Draft Store，防线 D9）。
///
/// ## 它解决什么问题
/// 用户改了文件、还没点提交，此时崩溃 / 被系统杀 / 切走再也没回来——
/// **用户敲的字就没了**。这对"数据无价"而言不可接受。
///
/// ## 规则
/// 1. **先落盘，再展示**：编辑器每次变更都要 `save()`（调用方做防抖）；
/// 2. **提交成功即清草稿**：由 `RepositoryCache` 在写成功后调用 [discard]，
///    保证"草稿"不会在提交成功后阴魂不散地盖住新内容；
/// 3. **草稿带基线**：记录起草时基于哪个远端版本，冲突判定才有依据；
/// 4. **变更可观察**：本类是可监听的（[ChangeNotifier]），草稿箱与角标
///    据此实时刷新，不再靠"一次性 FutureBuilder"造成状态滞后。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../kernel/diagnostics.dart';
import 'disk_store.dart';
import 'disk_types.dart';

/// 草稿记录。
class DraftRecord {
  /// 创建草稿。
  const DraftRecord({
    required this.key,
    required this.content,
    required this.updatedAt,
    this.baseSha,
    this.revision = 0,
  });

  /// 目标键。
  final CacheKey key;

  /// 草稿内容（用户当前看到的、尚未提交的文本）。
  final String content;

  /// 起草时基于的远端版本。
  final String? baseSha;

  /// 草稿修订号（每次保存递增）。
  final int revision;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 复制并覆盖部分字段。
  DraftRecord copyWith({
    String? content,
    String? baseSha,
    DateTime? updatedAt,
    int? revision,
  }) =>
      DraftRecord(
        key: key,
        content: content ?? this.content,
        baseSha: baseSha ?? this.baseSha,
        revision: revision ?? this.revision,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'key': key.encode(),
        'content': content,
        if (baseSha != null) 'baseSha': baseSha,
        'revision': revision,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// 反序列化；结构不合法返回 `null`。
  static DraftRecord? fromJson(Map<String, dynamic> json) {
    try {
      final key = CacheKey.decode(json['key'] as String);
      if (key == null) {
        return null;
      }
      return DraftRecord(
        key: key,
        content: json['content'] as String,
        baseSha: json['baseSha'] as String?,
        revision: json['revision'] as int? ?? 0,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'DraftRecord(${key.encode()}, rv=$revision, ${content.length}B)';
}

/// 草稿仓库（持久化，**可观察**）。
class DraftStore extends ChangeNotifier {
  /// 创建草稿仓库。
  DraftStore({
    DiskKv? store,
    KernelDiagnostics? diagnostics,
    this.namespace = 'ogl.draft.',
  })  : _store = store ?? InMemoryKv(),
        _diagnostics = diagnostics ?? KernelDiagnostics();

  /// 键前缀。
  final String namespace;

  final DiskKv _store;
  KernelDiagnostics _diagnostics;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 保存草稿（不存在则新建；[baseSha] 缺省沿用已有值）。
  Future<DraftRecord> save(
    CacheKey key,
    String content, {
    String? baseSha,
  }) async {
    final existing = await load(key);
    final record = DraftRecord(
      key: key,
      content: content,
      baseSha: baseSha ?? existing?.baseSha,
      revision: (existing?.revision ?? 0) + 1,
      updatedAt: DateTime.now(),
    );
    await _store.write(_keyOf(key), jsonEncode(record.toJson()));
    notifyListeners();
    return record;
  }

  /// 读取草稿；不存在返回 `null`。
  Future<DraftRecord?> load(CacheKey key) async {
    final raw = await _store.read(_keyOf(key));
    if (raw == null) {
      return null;
    }
    try {
      return DraftRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await discard(key);
      return null;
    }
  }

  /// 是否存在草稿。
  Future<bool> has(CacheKey key) async => await load(key) != null;

  /// 丢弃草稿（提交成功后由缓存引擎调用）。
  Future<void> discard(CacheKey key) async {
    await _store.remove(_keyOf(key));
    notifyListeners();
  }

  /// 列出全部草稿（按更新时间升序，便于"恢复上次编辑"列表）。
  Future<List<DraftRecord>> all() async {
    final result = <DraftRecord>[];
    for (final key in await _store.keys()) {
      if (!key.startsWith(namespace)) {
        continue;
      }
      final raw = await _store.read(key);
      if (raw == null) {
        continue;
      }
      try {
        final record =
            DraftRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (record == null) {
          await _store.remove(key);
          continue;
        }
        result.add(record);
      } catch (_) {
        await _store.remove(key);
      }
    }
    result.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return result;
  }

  /// 草稿数量（UI 角标数据源）。
  Future<int> count() async => (await all()).length;

  /// 清空全部草稿。
  Future<int> clear() async {
    final removed = await all();
    for (final record in removed) {
      await discard(record.key);
    }
    _diagnostics.info(
      'DRAFT',
      '草稿已清空',
      code: 'OGL-DRAFT-002',
      data: <String, Object?>{'removed': removed.length},
    );
    notifyListeners();
    return removed.length;
  }

  String _keyOf(CacheKey key) => '$namespace${key.encode()}';
}
