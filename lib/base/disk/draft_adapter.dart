/// L1 底座级 · [DraftRepository] 适配器。
///
/// 把 `DraftStore`（`ChangeNotifier` + `DraftRecord` 实现）适配为
/// L0 契约的只读视图，使 `RepositoryCache` 能声明
/// `implements ConsistencyCache`，而 L2 完全不认识底座类型。
library;

import 'package:flutter/foundation.dart';

import '../../kernel/contract/consistency_cache.dart';
import '../../kernel/contract/disk_types.dart';
import 'disk_draft.dart';

/// 草稿仓储适配器。
class DraftRepositoryAdapter implements DraftRepository {
  /// 创建。
  DraftRepositoryAdapter(this._store);

  final DraftStore _store;

  @override
  Listenable get changes => _store;

  @override
  Future<List<DraftRecordView>> all() async {
    final List<DraftRecord> records = await _store.all();
    return <DraftRecordView>[
      for (final DraftRecord r in records)
        DraftRecordView(
          key: r.key,
          content: r.content,
          baseSha: r.baseSha,
          revision: r.revision,
          updatedAt: r.updatedAt,
        ),
    ];
  }

  @override
  Future<DraftRecordView> save(
    CacheKey key,
    String content, {
    String? baseSha,
  }) async {
    final DraftRecord r = await _store.save(key, content, baseSha: baseSha);
    return DraftRecordView(
      key: r.key,
      content: r.content,
      baseSha: r.baseSha,
      revision: r.revision,
      updatedAt: r.updatedAt,
    );
  }

  @override
  Future<void> discard(CacheKey key) => _store.discard(key);

  @override
  Future<int> clear() => _store.clear();
}
