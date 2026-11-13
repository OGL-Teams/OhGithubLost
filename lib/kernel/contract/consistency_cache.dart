/// L0 内核级 · 一致性缓存契约（D1–D9 的**抽象边界**）。
///
/// ## 为什么要有这一层
/// `RepositoryCache`（L1 底座层）是 D1–D9 一致性引擎的实现，
/// 此前 `GhApi`（L2）直接 import 它，被 `layer_audit.KNOWN`
/// 白名单长期豁免。本契约把 L2 需要的**能力**抽成抽象：
/// L2 只认识 `ConsistencyCache`，装配根注入 L1 实现，
/// 依赖方向回到「上层依赖下层契约」，白名单随之摘除。
///
/// ## 边界
/// - 所有输入/输出类型都来自 `kernel/contract/disk_types.dart`；
/// - 本文件不含任何磁盘实现、不依赖 Flutter 之外的包；
/// - `Listenable` 来自 `package:flutter/foundation.dart`（内核已有该依赖）。
library;

import 'package:flutter/foundation.dart';

import 'disk_types.dart';

/// 草稿仓储（D9）：按 [CacheKey] 存取，变更可监听。
///
/// [all] 返回**只读视图**，调用方不得据其修改内部状态。
abstract class DraftRepository {
  /// 草稿变更通知。
  Listenable get changes;

  /// 列出全部草稿记录（按时间倒序，由实现决定）。
  Future<List<DraftRecordView>> all();

  /// 保存草稿；返回保存后的记录。
  Future<DraftRecordView> save(
    CacheKey key,
    String content, {
    String? baseSha,
  });

  /// 丢弃某键的草稿。
  Future<void> discard(CacheKey key);

  /// 清空全部草稿，返回删除条数。
  Future<int> clear();
}

/// 草稿记录的**只读视图**（L0 数据形状，不暴露底座实现类型）。
class DraftRecordView {
  /// 创建。
  const DraftRecordView({
    required this.key,
    required this.content,
    required this.updatedAt,
    this.baseSha,
    this.revision = 0,
  });

  /// 目标键。
  final CacheKey key;

  /// 草稿正文。
  final String content;

  /// 基线（起草时远端版本）。
  final String? baseSha;

  /// 修订号。
  final int revision;

  /// 最后更新时间。
  final DateTime updatedAt;
}

/// 一致性缓存：读穿透 + D1–D9 写一致性 + 草稿仓储。
///
/// 逻辑层（domain）只依赖本抽象；底座层实现并在装配期注入。
abstract class ConsistencyCache {
  /// 读穿透缓存（TTL + 完整性校验 + 有界淘汰）。
  Future<CacheEntry?> read(
    CacheKey key, {
    bool refresh = false,
    Duration? maxAge,
  });

  /// 完整走 D1–D7 的写入；永不外抛（除非法键），失败体现在 [WriteOutcome]。
  ///
  /// [recordJournal] 为 `false` 时不写提交日志（仅供重放使用）。
  Future<WriteOutcome> write(
    WriteIntent intent, {
    bool confirmed = false,
    bool recordJournal = true,
  });

  /// 仅失效本地缓存（D5 写后失效）。
  Future<void> invalidate(CacheKey key);

  /// 删除（D1 / D2 / D7），失败如实返回、由用户重试。
  Future<WriteOutcome> delete(
    CacheKey key, {
    required String message,
    required String baseSha,
    bool confirmed = false,
  });

  /// 草稿快照（D9）；无草稿返回 `null`。
  Future<DraftSnapshot?> loadDraftSnapshot(CacheKey key);

  /// 草稿仓储；未接线返回 `null`（调用方必须落回空态）。
  DraftRepository? get drafts;

  /// 草稿变更通知（未接线时返回永不通知的占位，由实现保证）。
  Listenable get draftsChanged;
}
