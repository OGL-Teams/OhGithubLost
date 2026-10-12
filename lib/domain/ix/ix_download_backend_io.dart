/// L2 中枢级 · 下载后端的 **原生实现** 占位（native / desktop / Android / iOS）。
///
/// 本分支（纯 Web）**不会**编译它——`pubspec.yaml` 里 `flutter:` 段把
/// `lib/domain/ix/` 整体作为"两平台共用契约 + Web 实现"装载，`io` 实现
/// 仅供其他分支/未来 Android 集成时 `import 'package:ogl/domain/ix/
/// ix_download_backend_io.dart'` 引用。
///
/// ## 为什么 Web 分支需要它存在
/// 上一里程碑的契约 `Future<Uri?> pathFor(IxDownloadSpec spec)`：
/// - Web 端 `ix_download_backend_web.dart` → 返回 `null`；
/// - 原生端（io）→ 返回 `Uri.file(spec.savePath)`。
///
/// 有了这个占位文件，**契约层与"原生路径形态"在仓库中**对得齐——审计脚本、
/// 编译器与 IDE 跳转都不会再把 `pathFor` 当成"只存在于 Web 的孤儿方法"，
/// 集成分支开起来时只要 `import 'ix_download_backend_io.dart'` 就能直接
/// 用，`Uri.file(spec.savePath)` 的实现也不必在每个集成分支里复制一遍。
///
/// ## 完整性
/// 原生端要兑现全部契约（`events` / `pause` / `resume` / ...），本文件**不**
/// 假装实现——它只覆盖 `pathFor`，其余方法抛 [UnimplementedError]，让集成方
/// 看到红灯补齐（避免"看似能编却运行时炸"）。
library;

import 'ix_download.dart';

/// 原生端的"路径解析"规则：把**本地绝对路径**包成 `Uri.file`。
///
/// `Uri.file` 与 `Uri.parse` 的关键差异：
/// - `Uri.file('/Users/foo/My File.md')` → `pathSegments = ['Users', 'foo', 'My%20File.md']`
///   保留**真实路径编码**（空格 → `%20`），`launchUrl` 才能正确传给系统；
/// - `Uri.parse(spec.savePath)` 在 Windows 路径或含空格的路径上会**丢掉编码**，
///   这是 `download_manager_page._openLocal` 上 `Uri.file` 被误换成 `Uri.parse`
///   后报"无应用打开"的根因。
///
/// ★ 路径**由调用方给出**（原生后端的 `background_downloader` 用
///   `task.filePath()` 算，应用文档目录由该库的 `BaseDirectory` 决定）。
///   本文件是纯 Web 构建里的**占位**，不 import `dart:io` / `path_provider`，
///   因此**不臆造**目录规则：只负责"本地路径 → Uri"这一步。
Uri pathForSpec(String localPath) => Uri.file(localPath);

/// 原生端 `pathFor` 的 [IxDownloadBackend] 适配入口（工厂）。
///
/// **仅供集成分支使用**——它把 `pathForSpec` 收进 backend 的协议方法里，
/// 其它方法在本文件**留白**（抛 `UnimplementedError`）以强制补齐。
class IoDownloadBackend implements IxDownloadBackend {
  /// 创建。集成分支应传入"由库算出的本地路径"查询函数
  /// （`DownloadTask.filePath()`），不要自己拼目录。
  IoDownloadBackend({String Function(IxDownloadSpec spec)? localPathOf})
      : _localPathOf = localPathOf;

  final String Function(IxDownloadSpec spec)? _localPathOf;

  @override
  Stream<IxDownloadEvent> get events =>
      throw UnimplementedError('IoDownloadBackend.events');

  @override
  bool get canReadLocalFile =>
      throw UnimplementedError('IoDownloadBackend.canReadLocalFile');

  @override
  bool get supportsRanged =>
      throw UnimplementedError('IoDownloadBackend.supportsRanged');

  @override
  bool get supportsPauseResume =>
      throw UnimplementedError('IoDownloadBackend.supportsPauseResume');

  @override
  Future<Uri?> pathFor(IxDownloadSpec spec) async {
    final String Function(IxDownloadSpec spec)? resolve = _localPathOf;
    if (resolve == null) {
      throw UnimplementedError(
        'IoDownloadBackend.pathFor：集成分支必须注入 localPathOf'
        '（由 background_downloader 的 task.filePath() 给出真实落盘路径）',
      );
    }
    return pathForSpec(resolve(spec));
  }

  @override
  Future<void> enqueue(IxDownloadSpec spec) =>
      throw UnimplementedError('IoDownloadBackend.enqueue');

  @override
  Future<void> pause(String id) =>
      throw UnimplementedError('IoDownloadBackend.pause');

  @override
  Future<void> resume(String id) =>
      throw UnimplementedError('IoDownloadBackend.resume');

  @override
  Future<void> cancel(String id) =>
      throw UnimplementedError('IoDownloadBackend.cancel');

  @override
  Future<int?> completedSize(String id, {String? path}) =>
      throw UnimplementedError('IoDownloadBackend.completedSize');

  @override
  Future<String?> fileSha256(String id, {String? path}) =>
      throw UnimplementedError('IoDownloadBackend.fileSha256');

  @override
  Future<void> deleteFile(String id, {String? path}) =>
      throw UnimplementedError('IoDownloadBackend.deleteFile');

  @override
  void dispose() => throw UnimplementedError('IoDownloadBackend.dispose');
}
