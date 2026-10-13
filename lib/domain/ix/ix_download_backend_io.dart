/// L2 中枢级 · 下载后端的**原生实现**（`background_downloader` + `dart:io`）。
///
/// 负责：后台下载入队、暂停 / 继续 / 取消、落盘路径、成品读回（大小 / sha256 /
/// 删除）。**所有 `File` / `Directory` 的使用都隔离在本文件里**，
/// `ix_download.dart` 本体不碰 `dart:io`。
library;

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';

import 'ix_download.dart';

/// 按平台创建下载后端。
IxDownloadBackend createDownloadBackend() => IoDownloadBackend();

/// 原生下载后端（`background_downloader`）。
class IoDownloadBackend implements IxDownloadBackend {
  /// 创建后端（含订阅库的更新流）。
  IoDownloadBackend({FileDownloader? downloader})
      : _downloader = downloader ?? FileDownloader() {
    _subscription = _downloader.updates.listen(_onUpdate);
  }

  final FileDownloader _downloader;
  final StreamController<IxDownloadEvent> _events =
      StreamController<IxDownloadEvent>.broadcast();

  /// 本层任务 id → 库任务（暂停 / 继续 / 取消要传库对象）。
  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};

  /// 库任务 id → 本层任务 id（库的更新事件只有它自己的 id）。
  final Map<String, String> _idsByLibraryId = <String, String>{};

  StreamSubscription<TaskUpdate>? _subscription;

  /// 落盘目录裁决器（装配根注入；`null` = 应用私有目录，见契约注释）。
  Future<String?> Function()? _downloadDirProvider;

  @override
  set downloadDirProvider(Future<String?> Function()? provider) {
    _downloadDirProvider = provider;
  }

  @override
  Stream<IxDownloadEvent> get events => _events.stream;

  @override
  bool get canReadLocalFile => true;

  @override
  bool get supportsRanged => true;

  @override
  bool get supportsPauseResume => true;

  /// 构造库任务（`pathFor` 与 `enqueue` 共用同一份参数，保证 taskId 一致）。
  ///
  /// ★ 落盘去处跟随存储裁决（[downloadDirProvider]）：
  ///   - 公共目录档（用户拿到 ogl 权限）→ `directory` 指向
  ///     `/storage/emulated/0/ogl/download/…`，**直接写用户可见目录**；
  ///   - SAF / 内部档 → 裁决器返回的是私有根，行为与旧版一致
  ///     （SAF 档完成后仍由导出器粘贴过去）；
  ///   - 裁决器不可用 / 抛异常 → 回退旧版私有目录，**绝不阻塞下载**。
  ///
  /// 注意：库的 `directory` 是**相对** baseDirectory 的路径；这里在桌面 /
  /// 公共目录场景传绝对路径，用 [BaseDirectory.root]（库对 root + 以 `/`
  /// 开头的 directory 会按绝对路径处理）。
  Future<DownloadTask> _build(IxDownloadSpec spec) async {
    String directory = 'ogl/download/${spec.folder}';
    BaseDirectory base = BaseDirectory.applicationDocuments;
    try {
      final String? resolved = await _downloadDirProvider?.call();
      if (resolved != null && resolved.isNotEmpty) {
        directory = '$resolved/${spec.folder}';
        base = BaseDirectory.root;
      }
    } catch (_) {
      // 裁决失败：维持私有目录（下载可用性优先）。
    }
    return DownloadTask(
      url: spec.url,
      filename: spec.fileName,
      directory: directory,
      baseDirectory: base,
      headers: spec.headers,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 2,
    );
  }

  @override
  Future<String> pathFor(IxDownloadSpec spec) async {
    try {
      return await (await _build(spec)).filePath();
    } catch (_) {
      // 拿不到真实路径时退回文件名（界面至少能显示一个可读的名字）。
      return spec.fileName;
    }
  }

  @override
  Future<void> enqueue(IxDownloadSpec spec) async {
    final DownloadTask task = await _build(spec);
    // ★ 同一 taskId 的旧终态记录必须先清：库对「已完成/已失败」的 taskId
    //   重新 enqueue 会拒绝或直接补一个旧状态事件——于是「下载 → 移除 →
    //   再下载同一条」第二次必然失败且无任何界面提示（横幅也不弹）。
    //   先 cancel 再 enqueue = 库内重置该 id 的状态机。
    try {
      await _downloader.cancelTaskWithId(task.taskId);
    } catch (_) {
      // 无旧任务时忽略。
    }
    _tasks[spec.id] = task;
    _idsByLibraryId[task.taskId] = spec.id;
    await _downloader.enqueue(task);
  }

  @override
  Future<void> pause(String id) async {
    final DownloadTask? task = _tasks[id];
    if (task != null) {
      await _downloader.pause(task);
    }
  }

  @override
  Future<void> resume(String id) async {
    final DownloadTask? task = _tasks[id];
    if (task != null) {
      await _downloader.resume(task);
    }
  }

  @override
  Future<void> cancel(String id) async {
    final DownloadTask? task = _tasks[id];
    if (task != null) {
      await _downloader.cancelTaskWithId(task.taskId);
    }
  }

  @override
  Future<int?> completedSize(String id, {String? path}) async {
    final File? file = await _fileOf(id, path);
    if (file == null) {
      return null;
    }
    try {
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> fileSha256(String id, {String? path}) async {
    final File? file = await _fileOf(id, path);
    if (file == null) {
      return null;
    }
    try {
      return (await sha256.bind(file.openRead()).first).toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteFile(String id, {String? path}) async {
    final File? file = await _fileOf(id, path);
    if (file == null) {
      return;
    }
    try {
      await file.delete();
    } catch (_) {
      // 清理失败不改变结论（下载已判定失败，上层会如实报错）。
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _events.close();
  }

  /// 把库的更新翻译成本层的状态 / 进度事件。
  void _onUpdate(TaskUpdate update) {
    if (update is TaskStatusUpdate) {
      final String? id = _idsByLibraryId[update.task.taskId];
      if (id == null) {
        return;
      }
      _events.add(IxDownloadEvent.state(
        id,
        _mapStatus(update.status),
        error: update.exception?.description,
      ));
      return;
    }
    if (update is TaskProgressUpdate) {
      final String? id = _idsByLibraryId[update.task.taskId];
      if (id == null) {
        return;
      }
      final int total =
          update.expectedFileSize > 0 ? update.expectedFileSize : 0;
      // ★ 库对终态补发的 progress 是负数（progressFailed=-1.0 等），
      //   不守卫会算出负的 received → 界面显示「-4.3 MB / 4.3 MB」。
      final double clamped = update.progress < 0 ? 0 : update.progress;
      final int received = total > 0 ? (clamped * total).round() : 0;
      _events
          .add(IxDownloadEvent.progress(id, received: received, total: total));
    }
  }

  /// 解析任务对应的本地文件（不存在返回 `null`，**不抛**）。
  ///
  /// [path] 为调用方给出的落盘路径（`savePath`）时**优先使用它**：
  /// 分片引擎自己写盘的任务从未进过库队列（`_tasks[id] == null`），
  /// 只按 id 查库表会一律返回 `null`，于是刚下好的成品被读成"不存在"。
  Future<File?> _fileOf(String id, String? path) async {
    final String? explicit = (path == null || path.isEmpty) ? null : path;
    try {
      if (explicit != null) {
        final File file = File(explicit);
        return await file.exists() ? file : null;
      }
      final DownloadTask? task = _tasks[id];
      if (task == null) {
        return null;
      }
      final File file = File(await task.filePath());
      if (!await file.exists()) {
        return null;
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 库状态 → 本应用状态。
  ///
  /// ★ 用 if 链而不是 switch：`TaskStatus` 是**第三方枚举**，
  ///   - 写成穷尽 switch + `default` 时，若该枚举的取值恰好被上面列全，
  ///     `default` 会被判为不可达（`--fatal-warnings` 直接红）；
  ///   - 去掉 `default` 又在枚举新增取值时变成「未穷尽」编译错误。
  ///   if 链对两种情况都成立，且语义就是「已知的逐个映射，其余归失败」。
  static IxDownloadStatus _mapStatus(TaskStatus status) {
    if (status == TaskStatus.enqueued) {
      return IxDownloadStatus.queued;
    }
    if (status == TaskStatus.running) {
      return IxDownloadStatus.running;
    }
    if (status == TaskStatus.complete) {
      return IxDownloadStatus.completed;
    }
    if (status == TaskStatus.paused) {
      return IxDownloadStatus.paused;
    }
    if (status == TaskStatus.canceled) {
      return IxDownloadStatus.canceled;
    }
    // ★ 库的指数退避重试窗口（非终态）：映射为排队，否则界面显示「失败」
    //   然后下一个 running 又把它改回来（闪烁）。
    if (status == TaskStatus.waitingToRetry) {
      return IxDownloadStatus.queued;
    }
    // failed / notFound / 该库将来新增的取值：一律按失败处理。
    return IxDownloadStatus.failed;
  }
}
