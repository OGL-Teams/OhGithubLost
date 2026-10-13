/// L1 底座级 · 硬盘逻辑：门面与模块装配。
///
/// 硬盘逻辑对外只暴露一个门面 [DiskBridge]：
/// KV、保险库、文件、路径规划、**一致性缓存**都在它后面。
/// 上层拿不到 `HttpClient`，也拿不到任何平台通道——这是"底座可替换"的前提。
library;

import '../../kernel/contract/module.dart';
import 'disk_cache.dart';
import 'disk_draft.dart';
import 'disk_journal.dart';
import 'disk_store.dart';

/// 硬盘逻辑门面。
class DiskBridge {
  /// 创建门面。
  const DiskBridge({
    required this.kv,
    required this.vault,
    required this.files,
    required this.paths,
    required this.cache,
    required this.journal,
    required this.drafts,
  });

  /// 键值存储。
  final DiskKv kv;

  /// 安全保险库。
  final DiskVault vault;

  /// 文件存储。
  final DiskFileStore files;

  /// 路径规划。
  final DiskPaths paths;

  /// 一致性缓存（**致命区**，见 `docs/CONSISTENCY.md（该文件未落地，以源码为准）`）。
  final RepositoryCache cache;

  /// 提交日志（D8：写前落盘，崩溃可恢复）。
  final WriteJournal journal;

  /// 草稿仓库（D9：编辑不丢）。
  final DraftStore drafts;

  @override
  String toString() => 'DiskBridge(kv=${kv.runtimeType}, '
      'files=${files.runtimeType}, vault=${vault.runtimeType})';
}

/// 硬盘逻辑模块（`base.disk`）。
///
/// 依赖：无。
/// 提供：`disk.kv` / `disk.vault` / `disk.files` / `disk.cache`。
class DiskModule extends OgLModule {
  /// 创建模块。
  ///
  /// 所有依赖都可注入，缺省走内存实现：这样**同一份代码**
  /// 既能跑在 CI 的内存环境，也能在真机上换成平台实现。
  DiskModule({
    DiskKv? kv,
    DiskVault? vault,
    DiskFileStore? files,
    DiskPaths? paths,
    RepositoryCache? cache,
    WriteJournal? journal,
    DraftStore? drafts,
  })  : kv = kv ?? InMemoryKv(),
        vault = vault ?? InMemoryVault(),
        files = files ?? InMemoryFileStore(),
        paths = paths ?? const InMemoryPaths(),
        cache = cache ?? RepositoryCache(),
        journal = journal ?? WriteJournal(),
        drafts = drafts ?? DraftStore();

  /// 键值存储。
  final DiskKv kv;

  /// 安全保险库。
  final DiskVault vault;

  /// 文件存储。
  final DiskFileStore files;

  /// 路径规划。
  final DiskPaths paths;

  /// 一致性缓存。
  final RepositoryCache cache;

  /// 提交日志。
  final WriteJournal journal;

  /// 草稿仓库。
  final DraftStore drafts;

  /// 门面实例（[onRegister] 后可用）。
  late final DiskBridge bridge;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'base.disk',
        layer: ModuleLayer.base,
        version: '0.1.0',
        provides: <String>[
          'disk.kv',
          'disk.vault',
          'disk.files',
          'disk.cache',
          'disk.journal',
          'disk.draft',
        ],
        description: '底座·硬盘逻辑（KV / 保险库 / 文件 / 缓存一致性 D1–D7 / 提交日志 D8 / 草稿 D9）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    // 三处接线一个都不能省：
    // ① 诊断中枢 → 让 D1–D10 的每次判定都进审计日志；
    // ② 提交日志 → 让"提交"成为可恢复事务（D8）；
    // ③ 草稿仓库 → 提交成功即清草稿（D9）。
    final repositoryCache = cache;
    final writeJournal = journal;
    final draftStore = drafts;

    repositoryCache.attachDiagnostics(context.diagnostics);
    repositoryCache.attachJournal(writeJournal);
    repositoryCache.attachDrafts(draftStore);
    writeJournal.attachDiagnostics(context.diagnostics);
    draftStore.attachDiagnostics(context.diagnostics);

    bridge = DiskBridge(
      kv: kv,
      vault: vault,
      files: files,
      paths: paths,
      cache: repositoryCache,
      journal: writeJournal,
      drafts: draftStore,
    );
    context.di.register<DiskBridge>(bridge);
    context.di.register<RepositoryCache>(repositoryCache);
    context.di.register<WriteJournal>(writeJournal);
    context.di.register<DraftStore>(draftStore);
    context.diagnostics.info(
      'DISK',
      '硬盘逻辑就绪',
      code: 'OGL-DISK-001',
      data: <String, Object?>{
        'kv': kv.runtimeType.toString(),
        'files': files.runtimeType.toString(),
        'vault': vault.runtimeType.toString(),
        'pendingWrites': await writeJournal.pendingCount(),
        'draftCount': await draftStore.count(),
      },
    );
  }
}
