/// L2 中枢级 · 内建下载器（**按平台选下载后端**）。
///
/// ## 公开契约保持不变
/// [IxDownloadManager] / [IxDownloadTask] / [IxDownloadCategory] /
/// [IxDownloadStatus] 的名字与语义不变，页面（下载管理、Release、仓库文件）
/// 不碰实现、只读快照。唯一例外：`IxDownloadTask.error` 由裸 `String` 升级为
/// 结构化 [IxDownloadError]，只看字符串的调用点改读 `errorText` 即可。
///
/// ## 为什么要有"后端"
/// 把"怎么下载"抽成 [IxDownloadBackend]（本文件声明接口），实现收敛在
/// `ix_download_backend_io.dart`：`background_downloader` 提供后台下载、
/// 断点续传、队列与通知，成品落到应用文档目录。
/// `File` / `Directory` 的使用**全部**隔离在该实现里。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../kernel/contract/download_engine.dart';
import '../../kernel/contract/storage_export.dart';
import '../../kernel/diagnostics.dart';
import 'ix_download_backend_io.dart';
import 'ix_download_error.dart';

/// 下载分类（决定落到哪个子目录）。
enum IxDownloadCategory {
  /// Release 附件。
  release,

  /// 仓库文件。
  repo,

  /// Gist 文件。
  gist,

  /// Actions 构建产物。
  artifact,

  /// 其它。
  other;

  /// 子目录名。
  String get folder => switch (this) {
        IxDownloadCategory.release => 'release',
        IxDownloadCategory.repo => 'repo',
        IxDownloadCategory.gist => 'gist',
        IxDownloadCategory.artifact => 'artifact',
        IxDownloadCategory.other => 'other',
      };

  /// 展示名。
  String get label => switch (this) {
        IxDownloadCategory.release => 'Release',
        IxDownloadCategory.repo => '仓库文件',
        IxDownloadCategory.gist => 'Gist',
        IxDownloadCategory.artifact => '构建产物',
        IxDownloadCategory.other => '其它',
      };
}

/// 下载状态。
enum IxDownloadStatus {
  /// 排队中。
  queued,

  /// 下载中。
  running,

  /// 已暂停。
  paused,

  /// 已完成。
  completed,

  /// 失败。
  failed,

  /// 已取消。
  canceled;

  /// 展示名。
  String get label => switch (this) {
        IxDownloadStatus.queued => '排队中',
        IxDownloadStatus.running => '下载中',
        IxDownloadStatus.paused => '已暂停',
        IxDownloadStatus.completed => '已完成',
        IxDownloadStatus.failed => '失败',
        IxDownloadStatus.canceled => '已取消',
      };
}

/// 平台下载后端要执行的**一次任务描述**（不含平台类型，便于 Web/原生共用）。
@immutable
class IxDownloadSpec {
  /// 创建。
  const IxDownloadSpec({
    required this.id,
    required this.url,
    required this.fileName,
    required this.folder,
    this.headers = const <String, String>{},
  });

  /// 任务 id（由 [IxDownloadManager] 派生；后端必须原样沿用，
  /// 因为页面用它做暂停 / 取消 / 移除）。
  final String id;

  /// 源地址。
  final String url;

  /// 已净化的文件名。
  final String fileName;

  /// 分类子目录名。
  final String folder;

  /// 附带请求头（鉴权 / accept）。
  final Map<String, String> headers;

  /// 复制并覆盖源地址（分片探测失败后**静默降级**到其它候选地址时使用）。
  IxDownloadSpec copyWith({String? url}) => IxDownloadSpec(
        id: id,
        url: url ?? this.url,
        fileName: fileName,
        folder: folder,
        headers: headers,
      );
}

/// 后端事件：状态变化或进度。
///
/// 用"事件"而不是直接暴露库的 `TaskUpdate`，是为了让管理器与
/// `background_downloader` 的类型解耦——Web 侧不 import 那个库。
@immutable
class IxDownloadEvent {
  /// 状态事件。
  const IxDownloadEvent.state(this.id, this.status, {this.error})
      : received = 0,
        total = 0;

  /// 进度事件。
  const IxDownloadEvent.progress(
    this.id, {
    required this.received,
    required this.total,
  })  : status = null,
        error = null;

  /// 任务 id。
  final String id;

  /// 状态（进度事件为 `null`）。
  final IxDownloadStatus? status;

  /// 已收字节（进度事件）。
  final int received;

  /// 总字节（进度事件；0 = 未知）。
  final int total;

  /// 失败原因（状态事件）。
  final String? error;
}

/// 平台下载后端（原生 = `background_downloader`；Web = 浏览器下载）。
abstract class IxDownloadBackend {
  /// 后端事件流（状态 + 进度）。
  Stream<IxDownloadEvent> get events;

  /// 本平台能否**读回成品字节**（决定完整性校验与 SAF 导出是否可行）。
  ///
  /// Web = `false`：成品由浏览器写进它自己的下载目录，页面拿不到。
  bool get canReadLocalFile;

  /// 本平台是否支持**多连接分片**（Web = `false`）。
  bool get supportsRanged;

  /// 本平台是否支持**暂停 / 继续**（Web = `false`：浏览器下载不可被页面控制）。
  bool get supportsPauseResume;

  /// 计算落盘路径，**不入队**（分片路径需要先知道目标文件位置）。
  ///
  /// Web 上返回下载地址本身（页面没有本地路径可用）。
  Future<String> pathFor(IxDownloadSpec spec);

  /// 真正开始下载。
  Future<void> enqueue(IxDownloadSpec spec);

  /// 暂停（不支持时应为空操作，由管理器先行判能力）。
  Future<void> pause(String id);

  /// 继续。
  Future<void> resume(String id);

  /// 取消（Web 上无法真正中止浏览器下载，为空操作）。
  Future<void> cancel(String id);

  /// 已完成文件的大小（字节）；拿不到返回 `null`（**不编造**）。
  ///
  /// [path] 为**调用方已知的落盘路径**（`savePath`），必须传：
  /// 分片引擎自己写盘的任务**不在库的任务表里**（它从未 `enqueue`），
  /// 只按 id 查库表会一律返回 `null` —— 于是好好的文件被当成"读不到"。
  Future<int?> completedSize(String id, {String? path});

  /// 文件的 sha256（小写十六进制）；不可读返回 `null`。
  ///
  /// [path] 同 [completedSize]：**必须**把落盘路径传进来，否则分片下载
  /// （不经过库队列）的成品读不到 → 校验必然判"不匹配" → 好文件被误杀。
  Future<String?> fileSha256(String id, {String? path});

  /// 删除本地文件（完整性校验不通过时清理）。
  ///
  /// [path] 同 [completedSize]：不传就会删不掉该删的坏文件。
  Future<void> deleteFile(String id, {String? path});

  /// 释放资源。
  void dispose();

  /// 落盘目录裁决器（由装配根注入；`null` = 维持应用私有目录）。
  ///
  /// 后端在构造库任务时调用：返回值决定下载**直接写到哪里**。
  /// ① 公共目录档（用户拿到了 ogl 权限）→ 写 `/storage/emulated/0/ogl/download/…`，
  ///   文件立刻对用户可见；② SAF 档 → 照旧私有 + 完成后导出；③ 内部 → 私有。
  /// 必须容错：裁决抛异常时按未提供处理（私有目录），**绝不阻塞下载**。
  set downloadDirProvider(Future<String?> Function()? provider);
}

/// Windows 保留设备名（大小写不敏感，带任意扩展名都危险）。
const Set<String> _kReservedDeviceNames = <String>{
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// 落盘文件名的**安全净化**（下载器必须自己守住的边界）。
///
/// ## 为什么不能交给库
/// `fileName` 的来源之一是 Release 附件名（**仓库所有者完全可控**），另一来源
/// 是仓库路径末段。若直接交给 `DownloadTask.filename`，等于把路径构造的责任
/// 外包给 `background_downloader` 的内部实现 —— 而那不在本仓库内、无法审计。
/// 所以在这里收口：只取末段、剔除控制字符与路径分隔符、拒掉 `.`/`..`、
/// 绕开 Windows 保留设备名、限长并**保住扩展名**（用户靠它判断文件类型）。
///
/// 注：Web 上文件名只用于界面展示（真正落盘由浏览器决定），但净化逻辑
/// 仍然照跑——保持两个平台的展示一致，并避免把带路径分隔符的名字带进 URL。
String ogLSafeDownloadFileName(String raw, {String fallback = 'download'}) {
  // ① 只取末段：任何路径分隔符都在此切断（`\` 在 Windows 上同样是分隔符）。
  String name = raw.trim();
  final int cut = name.lastIndexOf(RegExp(r'[/\\]'));
  if (cut >= 0) {
    name = name.substring(cut + 1);
  }
  // ② 剔除控制字符、Shell/Windows 非法字符，并把连续空白收敛成一个空格。
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), '');
  name = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  // ③ 去掉前导点（隐藏文件）与尾部的点/空格（Windows 不允许尾随点与空格）。
  name =
      name.replaceAll(RegExp(r'^[.]+'), '').replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) {
    return fallback;
  }
  // ④ 拆扩展名；限长时优先保住扩展名。
  final int dot = name.lastIndexOf('.');
  final String stem = dot > 0 ? name.substring(0, dot) : name;
  final String ext = dot > 0 ? name.substring(dot) : '';
  const int limit = 120;
  String safeStem = stem.length > limit ? stem.substring(0, limit) : stem;
  if (safeStem.isEmpty) {
    safeStem = fallback;
  }
  // ⑤ Windows 保留设备名：改名，而不是放任它在 Windows 上失败。
  //
  //  ★ 判定取**第一个点之前**的部分：Windows 的设备名识别不是"最后一段
  //    扩展名之前"——`nul.tar.gz` 同样等价于 `NUL`（Microsoft 文档原话：
  //    "NUL.tar.gz is equivalent to NUL"）。旧实现只看最后一个点前的
  //    `safeStem`（如 `aux.tar`），`aux.tar.gz` 这类多扩展名因此绕过判定。
  final int firstDot = name.indexOf('.');
  final String deviceCandidate =
      (firstDot > 0 ? name.substring(0, firstDot) : name).toLowerCase();
  if (_kReservedDeviceNames.contains(deviceCandidate)) {
    safeStem = '_$safeStem';
  }
  // 扩展名本身也可能是攻击面（超长后缀会撑爆路径），过长就整个丢掉。
  return '$safeStem${ext.length > 16 ? '' : ext}';
}

/// 只允许 `http` / `https`，其余一律拒绝。
///
/// ## 为什么
/// 加速通道的地址由**用户填写**：一旦允许 `file://`，等于让远端内容指定去读
/// 本机任意文件；非 http 协议在浏览器端也无法走 CORS（与「web 分支强制开启」
/// 的前提冲突）。
String ogLAssertDownloadUrl(String url) {
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    throw ArgumentError.value(url, 'url', '只允许 http/https 地址');
  }
  return url;
}

/// 把**分片引擎**抛出的错误归入分类。
///
/// 引擎只暴露契约层异常类型 —— 本层**不 import `dart:io`**（Web 才可编译），
/// 因此 `SocketException` / `FileSystemException` 之类只能按文本特征粗判。
IxDownloadErrorKind _kindOfFailure(Object error) {
  if (error is DownloadUnsupported) {
    return IxDownloadErrorKind.unsupported;
  }
  if (error is DownloadHttpException) {
    return IxDownloadErrorKind.network;
  }
  return _kindOfText('$error');
}

/// 按描述文本粗判分类（判不出 → [IxDownloadErrorKind.unknown]，**不编造**）。
IxDownloadErrorKind _kindOfText(String text) {
  final String lower = text.toLowerCase();
  const List<String> diskHints = <String>[
    'filesystem',
    'file system',
    'no space',
    'enospc',
    'read-only',
    'permission denied',
    'write failed',
    'write error',
    'disk',
  ];
  const List<String> networkHints = <String>[
    'socket', 'connect', 'timeout', 'timed out', 'host', 'dns', //
    'network', 'unreachable', 'handshake', 'http', 'tls',
  ];
  for (final String hint in diskHints) {
    if (lower.contains(hint)) {
      return IxDownloadErrorKind.disk;
    }
  }
  for (final String hint in networkHints) {
    if (lower.contains(hint)) {
      return IxDownloadErrorKind.network;
    }
  }
  return IxDownloadErrorKind.unknown;
}

/// 由后端给的**描述文本**构造结构化错误；没有描述 = 没有错误（`null`）。
///
/// 库只给一句话、不给诊断码，所以这里不带 `code`（不编造码位）。
IxDownloadError? _errorOfDescription(String? description) {
  if (description == null || description.isEmpty) {
    return null;
  }
  return IxDownloadError(_kindOfText(description), description);
}

/// [IxDownloadTask.copyWith] 里「**未传** `error`」的哨兵。
///
/// Dart 的可选参数分不清"没传"与"传了 `null`"，而这两件事对 `error` 语义相反
/// （保留旧错误 / 清空），因此用私有实例做哨兵（`identical` 比较）。
const Object _kUnset = _UnsetSentinel();

/// 哨兵的私有类型（避免与外部任何 `const Object()` 撞车）。
class _UnsetSentinel {
  const _UnsetSentinel();
}

/// 一个下载任务的可读快照（不可变）。
@immutable
class IxDownloadTask {
  /// 创建快照。
  const IxDownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.category,
    required this.savePath,
    required this.status,
    required this.received,
    required this.total,
    required this.bytesPerSecond,
    required this.createdAt,
    this.error,
    this.verified,
  });

  /// 任务 id。
  final String id;

  /// 源地址。
  final String url;

  /// 文件名。
  final String fileName;

  /// 分类。
  final IxDownloadCategory category;

  /// 保存路径（绝对路径）。
  ///
  /// **Web**：浏览器不给页面文件路径，这里放**下载地址**（成品由浏览器的
  /// 下载器落盘，位置由浏览器决定）——界面据此展示，而不是假装有一个本地路径。
  final String savePath;

  /// 状态。
  final IxDownloadStatus status;

  /// 已收字节。
  final int received;

  /// 总字节（0 表示未知）。
  final int total;

  /// 即时速率（字节 / 秒）。
  final double bytesPerSecond;

  /// 创建时间。
  final DateTime createdAt;

  /// 失败原因（结构化：分类 + 说明 + 诊断码；`null` = 没有失败）。
  ///
  /// ★ 曾经是裸 `String`：没有分类、没有诊断码，页面只能整段回显。
  ///   只看字符串的既有调用点改读 [errorText]（字段换成对象后
  ///   `Text(task.error!)` 不再能编译）。
  final IxDownloadError? error;

  /// 完整性校验结果（三态，**不谎称验过**）：
  /// - `true`：已按期望摘要校验**通过**；
  /// - `false`：校验过但**不匹配** —— 任务会被置为失败；
  /// - `null`：**没有摘要可比对**，或**本平台拿不到成品字节**（Web）——
  ///   界面须如实呈现为「未校验」。
  final bool? verified;

  /// 面向用户的错误文本（没有错误时为空串）。
  ///
  /// ★ 给"只认字符串"的既有调用点留的兼容出口：字段从 `String?` 换成
  ///   [IxDownloadError] 之后，`Text(task.error!)` 不再能编译，改读本 getter
  ///   即可（内容与原先的展示文本一致）。
  String get errorText => error?.message ?? '';

  /// 进度（0–1；总长未知时为 0）。
  double get progress =>
      total <= 0 ? 0 : (received / total).clamp(0, 1).toDouble();

  /// 百分比（0–100）。
  int get percent => (progress * 100).round();

  /// 是否仍在进行。
  bool get busy =>
      status == IxDownloadStatus.running || status == IxDownloadStatus.queued;

  /// 是否已完成。
  bool get done => status == IxDownloadStatus.completed;

  /// 复制并覆盖部分字段。
  ///
  /// ★ [error] 用**哨兵**区分「未传参」与「显式传 `null`」：
  ///   - 不传 → 保留原值（进度事件不会顺手擦掉失败原因）；
  ///   - 显式 `error: null` → **清空**（重试时必须能清掉上一次的失败原因，
  ///     否则界面上会挂着一条早已过期的错误）。
  IxDownloadTask copyWith({
    IxDownloadStatus? status,
    int? received,
    int? total,
    double? bytesPerSecond,
    Object? error = _kUnset,
    String? savePath,
    bool? verified,
  }) =>
      IxDownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        category: category,
        savePath: savePath ?? this.savePath,
        status: status ?? this.status,
        received: received ?? this.received,
        total: total ?? this.total,
        bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
        createdAt: createdAt,
        error:
            identical(error, _kUnset) ? this.error : error as IxDownloadError?,
        verified: verified ?? this.verified,
      );
}

/// 下载管理器（展示层唯一入口；内部委托平台后端）。
class IxDownloadManager extends ChangeNotifier {
  /// 创建管理器。
  ///
  /// [diagnostics] 用于把"取不到文件大小"等**降级**情况按事件码上报
  /// （不允许静默）。
  /// [backend] 仅供测试注入；不传则按平台条件导入选定实现。
  IxDownloadManager({
    KernelDiagnostics? diagnostics,
    DownloadEngine? engine,
    StorageExporter? storageExporter,
    Future<String?> Function()? downloadDirProvider,
    IxDownloadBackend? backend,
  })  : _diagnostics = diagnostics,
        _engine = engine,
        _exporter = storageExporter,
        _backend = backend ?? createDownloadBackend() {
    _subscription = _backend.events.listen(_onEvent);
    _backend.downloadDirProvider = downloadDirProvider;
  }

  final IxDownloadBackend _backend;
  final KernelDiagnostics? _diagnostics;

  /// 成品导出能力（**契约层类型**，由装配根注入；为 `null` 时不导出）。
  final StorageExporter? _exporter;

  /// 多连接分片引擎（**契约层类型**，由装配根注入；为 `null` 时只用库）。
  final DownloadEngine? _engine;

  /// 走分片引擎的任务 → 取消令牌（暂停 / 取消 / 重试都靠它）。
  final Map<String, DownloadCancelToken> _rangeTokens =
      <String, DownloadCancelToken>{};

  /// 走分片引擎的任务 → 并发数（重试用同一份参数）。
  final Map<String, int> _rangeConnections = <String, int>{};

  /// 每个任务的**候选地址（按优先级）**：首个是首选，其余用于**静默降级**。
  final Map<String, List<String>> _urlCandidates = <String, List<String>>{};

  /// 每个任务的执行描述（重试 / 分片降级时复用）。
  final Map<String, IxDownloadSpec> _specs = <String, IxDownloadSpec>{};

  /// 已请求「暂停」的分片任务（取消令牌后据此标记 paused 而非 canceled）。
  final Set<String> _pausedIds = <String>{};

  /// 是否由分片引擎接管（页面据此显示"多线程"标记；Web 上恒为 `false`）。
  bool isRanged(String id) => _rangeTokens.containsKey(id);

  StreamSubscription<IxDownloadEvent>? _subscription;

  final Map<String, IxDownloadTask> _snapshots = <String, IxDownloadTask>{};

  /// 上次进度采样（用于估算速率；库本身只给进度、不给速度）。
  final Map<String, ({DateTime at, int received})> _lastSample =
      <String, ({DateTime at, int received})>{};

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 是否已 dispose（分片任务是 fire-and-forget，回收后可能仍有回调进来）。
  bool _disposed = false;

  /// 任务列表（新的在前）。
  List<IxDownloadTask> get tasks {
    final List<IxDownloadTask> list = _snapshots.values.toList();
    list.sort((IxDownloadTask a, IxDownloadTask b) =>
        b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 是否有任务。
  bool get isEmpty => _snapshots.isEmpty;

  /// 本平台后端是否支持**暂停 / 继续**（Web = `false`）。
  ///
  /// 页面据此隐藏暂停 / 继续按钮，而不是让用户点了之后收到"不支持"：
  /// 能力判定属于后端事实，UI 只做呈现（见 `SurfaceBridge.supportsPauseResume`）。
  bool get supportsPauseResume => _backend.supportsPauseResume;

  /// 进行中的任务数。
  int get runningCount => _snapshots.values
      .where((IxDownloadTask t) =>
          t.status == IxDownloadStatus.running ||
          t.status == IxDownloadStatus.queued)
      .length;

  /// 任务 id：由「分类 + 文件名 + 源地址」派生。
  ///
  /// 旧实现直接用 `background_downloader` 的 `taskId`；现在由本层派生，
  /// 因为 **Web 上没有那个库**。语义保持一致：同一条附件重复下载命中同一个
  /// id，页面据此复用同一条记录。
  static String _taskId(
    String url,
    String fileName,
    IxDownloadCategory category,
  ) =>
      '${category.folder}:$fileName#$url';

  /// 加入一个下载任务。
  Future<IxDownloadTask> enqueue({
    required String url,
    required String fileName,
    IxDownloadCategory category = IxDownloadCategory.other,
    Map<String, String> headers = const <String, String>{},
    int connections = 1,
    List<String> fallbackUrls = const <String>[],
    String? expectedSha256,
  }) async {
    // 安全边界收口（详见两个函数的文档）：
    // · 协议白名单 —— 加速通道地址由用户填写，非 http(s) 一律拒绝；
    // · 文件名净化 —— Release 附件名由仓库所有者完全可控，不能直接落盘。
    ogLAssertDownloadUrl(url);
    for (final String alt in fallbackUrls) {
      if (alt.isNotEmpty && alt != url) {
        ogLAssertDownloadUrl(alt);
      }
    }
    final String safeName = ogLSafeDownloadFileName(fileName);
    final String id = _taskId(url, safeName, category);

    // ★ 幂等入队：id 由「分类 + 文件名 + 源地址」派生，同一条附件重复点「下载」
    //   必须命中**同一条记录**（页面据此复用进度 / 暂停 / 移除）。
    //   · 已存在且**未终结**（queued / running / paused）→ 原样返回，不再入队，
    //     否则后端会为同一个 id 建两次任务；
    //   · 已终结（completed / failed / canceled）→ 先按 remove() 的清理口径
    //     清干净，再走全新入队。
    final IxDownloadTask? previous = _snapshots[id];
    if (previous != null) {
      final IxDownloadStatus previousStatus = previous.status;
      final bool terminal = previousStatus == IxDownloadStatus.completed ||
          previousStatus == IxDownloadStatus.failed ||
          previousStatus == IxDownloadStatus.canceled;
      if (!terminal) {
        return previous;
      }
      await remove(id);
    }

    final IxDownloadSpec spec = IxDownloadSpec(
      id: id,
      url: url,
      fileName: safeName,
      folder: category.folder,
      headers: headers,
    );
    _specs[id] = spec;
    // 候选地址（按优先级去重）：分片路径会逐个探测，**静默降级**到可用者。
    _urlCandidates[id] = <String>[
      url,
      for (final String alt in fallbackUrls)
        if (alt.isNotEmpty && alt != url) alt,
    ];
    // ★ 先登记快照，再去做 async 的 `pathFor`。
    //   顺序很关键：`pathFor` 是 async 的，等它回来的这段时间里页面就该看到
    //   这条任务 —— 否则 await 窗口内到达的后端事件会被当成"未知 id"丢掉，
    //   `tasks` / `runningCount` 也是空的。
    //   （此前把 `!containsKey(id)` 当守卫放在登记**之前**：全新任务的 id
    //     本来就不在表里，于是必然提前 return —— 既不登记也不入队，
    //     下载完全不可用。已修正。）
    final IxDownloadTask queued = IxDownloadTask(
      id: id,
      url: url,
      fileName: safeName,
      category: category,
      savePath: '',
      status: IxDownloadStatus.queued,
      received: 0,
      total: 0,
      bytesPerSecond: 0,
      createdAt: DateTime.now(),
    );
    _snapshots[id] = queued;
    // 期望摘要（sha256）；为空表示该资源没有可比对的摘要（如实标记未校验）。
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      _expectedSha256[id] = expectedSha256;
    }
    _safeNotify();

    final String savePath = await _backend.pathFor(spec);
    // ★ `pathFor` 是 async 的：这期间用户可能已把任务移除（`remove`）、
    //   或管理器已回收。此时**既不写回、也不入队** —— 写回会让被移除的任务
    //   "复活"。判据是"登记的那份快照还在原处"（同一个实例）：id 复用
    //   （同一条附件重复点下载）时实例会被换掉，那条旧 enqueue 同样应作废。
    if (_disposed || !identical(_snapshots[id], queued)) {
      return _snapshots[id] ?? queued;
    }
    _snapshots[id] = queued.copyWith(savePath: savePath);
    _safeNotify();

    // 并发 > 1 且装配层给了分片引擎、且后端支持分片 → 走**多连接分片**；
    // 不支持 Range 时自动回退到单连接（同一 taskId，页面无感）。
    // Web 后端 `supportsRanged = false`，因此这里直接走浏览器下载。
    if (connections > 1 &&
        _engine != null &&
        _backend.supportsRanged &&
        savePath.isNotEmpty) {
      _rangeConnections[id] = connections;
      unawaited(_runRanged(id: id, connections: connections));
      return _snapshots[id] ?? queued;
    }
    await _backend.enqueue(spec);
    return _snapshots[id] ?? queued;
  }

  /// 用分片引擎跑一个任务；不支持 / 失败则回退单连接。
  Future<void> _runRanged({
    required String id,
    required int connections,
  }) async {
    final IxDownloadTask? snap = _snapshots[id];
    final IxDownloadSpec? spec = _specs[id];
    if (snap == null || spec == null) {
      return;
    }
    final DownloadEngine engine = _engine!;
    final List<String> candidates = _urlCandidates[id] ?? <String>[spec.url];
    final DownloadCancelToken token = engine.newCancelToken();
    _rangeTokens[id] = token;

    // 按优先级逐个探测：命中第一个"可并发分片"的地址就停（**静默降级**）。
    Uri? uri;
    DownloadProbe probe = const DownloadProbe(supportsRange: false);
    String? reachable;
    for (final String candidate in candidates) {
      final Uri parsed = Uri.parse(candidate);
      DownloadProbe current;
      try {
        current = await engine.probe(
          parsed,
          headers: spec.headers.isEmpty ? null : spec.headers,
        );
      } catch (error) {
        // 该通道不可用 → 静默试下一个（不打扰用户）。
        continue;
      }
      reachable ??= candidate;
      if (current.supportsRange &&
          current.total != null &&
          current.total! > 0) {
        uri = parsed;
        probe = current;
        break;
      }
    }

    // ★ 探测是 async 的：这期间用户可能已把任务移除/取消。此时必须直接退出，
    //   否则下面的 `_snapshots[id] = ...` 会把条目**写回**（任务"复活"）。
    if (!_snapshots.containsKey(id)) {
      _rangeTokens.remove(id);
      return;
    }

    if (uri == null) {
      // 没有一个地址可并发分片：回退单连接（优先用最后一个可达地址）。
      await _fallbackToSingle(
        id,
        spec,
        url: reachable ?? candidates.first,
        reason: '无可分片通道（探测结果 $probe）',
        code: 'OGL-DL-201',
      );
      return;
    }

    _snapshots[id] = snap.copyWith(
      status: IxDownloadStatus.running,
      // ★ 分片引擎**每次都是从 0 重新拉**（暂停 / 失败后临时分片已被清掉），
      //   所以这里必须把已收字节一起归零：留着上一轮的数字，界面会在
      //   "重新下载"的头几秒里显示一个根本不属于本次下载的假进度。
      received: 0,
      total: probe.total!,
    );
    _safeNotify();

    try {
      await engine.fetch(
        DownloadRequest(
          url: uri,
          targetPath: snap.savePath,
          total: probe.total!,
          headers: spec.headers,
          connections: connections,
        ),
        cancel: token,
        onProgress: (int received, int total) =>
            _applyRangeProgress(id, received, total),
      );
      _applyRangeProgress(id, probe.total!, probe.total!);
      // 先校验完整性再宣告完成（校验不过则判失败，且不导出到 SAF）。
      await _finishTask(id);
    } on DownloadCanceled {
      _applyStatus(
        id,
        _pausedIds.contains(id)
            ? IxDownloadStatus.paused
            : IxDownloadStatus.canceled,
      );
    } on DownloadUnsupported catch (error) {
      // ★ 引擎说"我不行"（**文件太小**开不出第二片 / 服务端不支持 Range）
      //   —— 这**不是下载失败**。契约（`download_engine.dart`）写得很清楚：
      //   「目标不支持（或暂时无法）分片下载：调用方应回退到普通单连接下载」。
      //   旧实现把它当失败上报：于是「多线程下载」一开，**所有小于 1 MB 的
      //   文件必然"下载失败"**（文件与网络其实都没问题）。
      await _fallbackToSingle(
        id,
        spec,
        url: uri.toString(),
        reason: '分片不可用（${error.reason}）',
        code: 'OGL-DL-203',
      );
    } catch (error) {
      // 服务端**忽略 Range**（回 200 而不是 206）：同属"不支持分片"，
      // 一样回退单连接，而不是把用户这次下载判死。
      if (error is DownloadHttpException && error.statusCode == 200) {
        await _fallbackToSingle(
          id,
          spec,
          url: uri.toString(),
          reason: '服务端忽略 Range（HTTP 200 而非 206）',
          code: 'OGL-DL-204',
        );
      } else {
        // 分片失败**不静默**：记事件码并置失败（可重试）。
        _diagnostics?.error(
          'DL',
          '多连接下载失败：$uri（$error）',
          code: 'OGL-DL-202',
          data: <String, Object?>{'connections': connections},
        );
        final IxDownloadTask? current = _snapshots[id];
        if (current != null) {
          _snapshots[id] = current.copyWith(
            status: IxDownloadStatus.failed,
            error: IxDownloadError(
              _kindOfFailure(error),
              '$error',
              code: 'OGL-DL-202',
            ),
          );
          _safeNotify();
        }
      }
    } finally {
      _rangeTokens.remove(id);
      _pausedIds.remove(id);
    }
  }

  /// 回退到**库的单连接任务**（同一 taskId，页面无感：状态回到"排队中"，
  /// 随后由库的更新事件继续推进）。
  ///
  /// ## 为什么必须回退，而不是判失败
  /// 见 [DownloadUnsupported] 的契约语义：分片引擎在"文件太小 / 服务端不支持
  /// Range"时会明确说"我不行"，这**不是**下载失败。回退用的是同一条
  /// taskId，因此进度、暂停、重试、完整性校验都照旧。
  ///
  /// ## 自己的失败也要兜住
  /// 本方法是 `_runRanged` 的收尾，而 `_runRanged` 是 fire-and-forget
  /// （`unawaited(_runRanged(...))`）——这里若抛出，会变成无人处理的异步错误。
  Future<void> _fallbackToSingle(
    String id,
    IxDownloadSpec spec, {
    required String url,
    required String reason,
    required String code,
  }) async {
    // 从分片路径上摘下来：此后 pause / resume / retry 都走库的那条路。
    _rangeTokens.remove(id);
    _rangeConnections.remove(id);
    try {
      final IxDownloadSpec fallback = spec.copyWith(url: url);
      final String path = await _backend.pathFor(fallback);
      final IxDownloadTask? current = _snapshots[id];
      if (current == null) {
        // 任务已被移除：绝不写回（否则会把移除过的任务"复活"）。
        return;
      }
      _diagnostics?.info(
        'DL',
        '${spec.fileName}：$reason，已回退单连接下载',
        code: code,
        data: <String, Object?>{'taskId': id, 'url': url},
      );
      _snapshots[id] = current.copyWith(
        savePath: path,
        status: IxDownloadStatus.queued,
        // 单连接重来时进度从 0 起算：留着上一次分片的数字会显示成
        // "已经下了一半"的假进度（实际库那边才刚开始）。
        received: 0,
        total: 0,
        bytesPerSecond: 0,
      );
      _safeNotify();
      await _backend.enqueue(fallback);
    } catch (error) {
      _diagnostics?.error(
        'DL',
        '回退单连接失败：${spec.fileName}（$error）',
        code: 'OGL-DL-205',
        data: <String, Object?>{'taskId': id, 'url': url},
      );
      final IxDownloadTask? current = _snapshots[id];
      if (current != null) {
        _snapshots[id] = current.copyWith(
          status: IxDownloadStatus.failed,
          error: IxDownloadError(
            _kindOfFailure(error),
            '$error',
            code: 'OGL-DL-205',
          ),
        );
        _safeNotify();
      }
    }
  }

  /// 分片进度 → 快照（含速率估算；节流通知与库路径一致）。
  void _applyRangeProgress(String id, int received, int total) {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return;
    }
    final DateTime now = DateTime.now();
    final ({DateTime at, int received})? last = _lastSample[id];
    double speed = snap.bytesPerSecond;
    if (last != null) {
      final int ms = now.difference(last.at).inMilliseconds;
      if (ms >= 400) {
        speed = (received - last.received) * 1000 / ms;
        _lastSample[id] = (at: now, received: received);
      }
    } else {
      _lastSample[id] = (at: now, received: received);
    }
    _snapshots[id] = snap.copyWith(
      status: IxDownloadStatus.running,
      received: received,
      total: total,
      bytesPerSecond: speed,
    );
    _notifyThrottled();
  }

  /// 平台不支持的操作用户点了怎么办：**如实留痕，不改状态**。
  ///
  /// 典型场景：Web 上点了"暂停"——浏览器正在下载的字节不受页面控制。
  /// 这里绝不做"看起来暂停了"的假动作（那才是真正的欺骗）。
  void _rejectUnsupported(String id, String operation) {
    _diagnostics?.warn(
      'DL',
      '${_snapshots[id]?.fileName ?? id}：Web 平台不支持$operation',
      code: 'OGL-DL-501',
      data: <String, Object?>{'taskId': id},
    );
  }

  /// 暂停。
  Future<void> pause(String id) async {
    final DownloadCancelToken? token = _rangeTokens[id];
    if (token != null) {
      // 分片任务：取消当前分片连接即"暂停"（重试会重新分片拉取）。
      _pausedIds.add(id);
      token.cancel();
      _applyStatus(id, IxDownloadStatus.paused);
      return;
    }
    if (!_backend.supportsPauseResume) {
      _rejectUnsupported(id, '暂停');
      return;
    }
    await _backend.pause(id);
    _applyStatus(id, IxDownloadStatus.paused);
  }

  /// 继续。
  ///
  /// 分片任务没有"库队列"可恢复：重新起一次分片拉取（分片临时文件已在失败时清理，
  /// 因此是**从头发起**；换来的是不出现"假装在续传"的错位文件）。
  Future<void> resume(String id) async {
    final int? connections = _rangeConnections[id];
    if (connections != null && _specs.containsKey(id) && _engine != null) {
      _pausedIds.remove(id);
      _applyStatus(id, IxDownloadStatus.running);
      await _runRanged(id: id, connections: connections);
      return;
    }
    if (!_backend.supportsPauseResume) {
      _rejectUnsupported(id, '继续');
      return;
    }
    await _backend.resume(id);
    _applyStatus(id, IxDownloadStatus.running);
  }

  /// 取消（不会保留未完成文件）。
  ///
  /// 分片任务：取消令牌 → 各分片退出 → 引擎负责删掉全部临时分片。
  /// Web：浏览器已经开始的那次下载**无法被页面中止**（如实告知），
  /// 这里只把任务标记为已取消，不再让它出现在"进行中"。
  Future<void> cancel(String id) async {
    final DownloadCancelToken? token = _rangeTokens[id];
    if (token != null) {
      _pausedIds.remove(id);
      token.cancel();
      _applyStatus(id, IxDownloadStatus.canceled);
      return;
    }
    if (!_backend.supportsPauseResume) {
      _rejectUnsupported(id, '中止浏览器下载（仅标记为已取消）');
    }
    await _backend.cancel(id);
    _applyStatus(id, IxDownloadStatus.canceled);
  }

  /// 重试（重新入队）。
  Future<void> retry(String id) async {
    final IxDownloadSpec? spec = _specs[id];
    if (spec == null) {
      return;
    }
    final IxDownloadTask? snap = _snapshots[id];
    if (snap != null) {
      _snapshots[id] = snap.copyWith(
        status: IxDownloadStatus.queued,
        received: 0,
        total: 0,
        bytesPerSecond: 0,
        // ★ 显式清空上一次的失败原因（哨兵语义：只有显式 null 才清）。
        error: null,
      );
      _safeNotify();
    }
    final int? connections = _rangeConnections[id];
    if (connections != null && _engine != null && _backend.supportsRanged) {
      _pausedIds.remove(id);
      await _runRanged(id: id, connections: connections);
      return;
    }
    await _backend.enqueue(spec);
  }

  /// 从列表移除（进行中的先取消）。
  Future<void> remove(String id) async {
    _rangeTokens[id]?.cancel();
    _rangeTokens.remove(id);
    _rangeConnections.remove(id);
    _pausedIds.remove(id);
    await _backend.cancel(id);
    _specs.remove(id);
    _snapshots.remove(id);
    _lastSample.remove(id);
    _expectedSha256.remove(id);
    _urlCandidates.remove(id);
    _exportedToSaf.remove(id);
    _safeNotify();
  }

  /// 清空已完成 / 已取消 / 失败的条目（不动磁盘文件）。
  void clearFinished() {
    final Set<String> gone = <String>{};
    _snapshots.removeWhere((String id, IxDownloadTask t) {
      final bool finished = t.status == IxDownloadStatus.completed ||
          t.status == IxDownloadStatus.canceled ||
          t.status == IxDownloadStatus.failed;
      if (finished) {
        gone.add(id);
      }
      return finished;
    });
    // ★ 与 remove() **逐表对齐**：per-id 的辅助表一个都不能漏，否则随会话累积
    //   （旧实现只对"非 completed"清 `_specs`，已完成的条目会永久滞留）。
    for (final String id in gone) {
      _rangeTokens[id]?.cancel();
      _rangeTokens.remove(id);
      _rangeConnections.remove(id);
      _pausedIds.remove(id);
      _specs.remove(id);
      _lastSample.remove(id);
      _expectedSha256.remove(id);
      _urlCandidates.remove(id);
      _exportedToSaf.remove(id);
    }
    _safeNotify();
  }

  void _applyStatus(String id, IxDownloadStatus status) {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap != null) {
      _snapshots[id] = snap.copyWith(status: status);
      _safeNotify();
      if (status == IxDownloadStatus.completed) {
        unawaited(_maybeExportToSaf(id));
      }
    }
  }

  /// 已导出到 SAF 的任务（去重：进度/状态事件会反复到达）。
  final Set<String> _exportedToSaf = <String>{};

  /// 期望摘要（sha256 小写十六进制）→ 任务 id。
  final Map<String, String> _expectedSha256 = <String, String>{};

  /// 完成后**校验完整性**，返回是否可信。
  ///
  /// ## 为什么必须有这一步
  /// 加速通道把流量交给第三方服务器后，**代理有能力返回被替换的文件**。
  /// GitHub Release 资产自带 `digest`（`sha256:…`），不比对等于开了一个
  /// 无验证的内容入口 —— 加速省下的时间不值得换一个来路不明的包。
  ///
  /// 没有摘要时（私有仓库与旧资产常见）**如实标记为「未校验」**，绝不谎称验过。
  /// **Web 上拿不到成品字节**（浏览器写在自己目录里），同样如实标记未校验。
  Future<bool> _verifyIntegrity(String id) async {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return false;
    }
    final String? expected = _expectedSha256[id];
    if (expected == null || expected.isEmpty) {
      _diagnostics?.info(
        'DL',
        '该资源没有可校验的摘要，已如实标记为未校验：${snap.fileName}',
        code: 'OGL-DL-401',
      );
      return true;
    }
    if (!_backend.canReadLocalFile) {
      _diagnostics?.warn(
        'DL',
        '本平台无法读回下载成品，完整性未能校验（如实标记为未校验）：'
            '${snap.fileName}',
        code: 'OGL-DL-406',
        data: <String, Object?>{'expected': expected},
      );
      return true;
    }
    try {
      // ★ 必须把**落盘路径**一并传下去：分片下载的成品不经过库队列，
      //   只按 id 查库表会读到 `null` → 好好的文件被判"校验不匹配"。
      final String? actual = await _backend.fileSha256(id, path: snap.savePath);
      if (actual == null) {
        return false;
      }
      final bool ok = actual == expected;
      // ★ fileSha256 是 async 的：等待期间任务可能已被 remove()，也可能刚被
      //   进度事件改写过。必须**重新取**快照再写回，否则旧快照（旧状态 /
      //   旧进度）会覆盖回去，甚至把已移除的任务"复活"。
      final IxDownloadTask? fresh = _snapshots[id];
      if (fresh == null || _disposed) {
        return ok;
      }
      _snapshots[id] = fresh.copyWith(verified: ok);
      if (ok) {
        _diagnostics?.info(
          'DL',
          '完整性校验通过：${fresh.fileName}',
          code: 'OGL-DL-402',
        );
      } else {
        _diagnostics?.error(
          'DL',
          '完整性校验不匹配，判定为失败：${fresh.fileName}',
          code: 'OGL-DL-403',
          data: <String, Object?>{'expected': expected, 'actual': actual},
        );
      }
      _safeNotify();
      return ok;
    } catch (error) {
      _diagnostics?.warn(
        'DL',
        '完整性校验无法完成：$error',
        code: 'OGL-DL-404',
      );
      return false;
    }
  }

  /// 下载真正结束的收尾：**先校验，再宣告完成**。
  ///
  /// 顺序很重要：校验不通过时必须**跳过 SAF 导出**，否则被替换的文件会落到
  /// 用户可见的目录里。
  Future<void> _finishTask(String id) async {
    // ★ 幂等守卫：库事件（`_onEvent`）与分片路径（`_runRanged`）**两个入口**
    //   都会走到这里；已判定完成的任务不再重复收尾（否则同一份成品会被重复
    //   校验、重复触发导出）。
    if (_snapshots[id]?.status == IxDownloadStatus.completed) {
      return;
    }
    final bool ok = await _verifyIntegrity(id);
    if (!ok) {
      final IxDownloadTask? snap = _snapshots[id];
      if (snap != null) {
        // ★ 校验不匹配的成品必须**删掉**：留着它，用户点「重试」只会把同一份
        //   坏字节再校验一遍，永远失败。删掉后重试才会真正重新下载。
        await _backend.deleteFile(id, path: snap.savePath);
        _snapshots[id] = snap.copyWith(
          status: IxDownloadStatus.failed,
          error: const IxDownloadError(
            IxDownloadErrorKind.integrity,
            'integrityMismatch',
            code: 'OGL-DL-403',
          ),
        );
        _safeNotify();
      }
      return;
    }
    _applyStatus(id, IxDownloadStatus.completed); // 内部会触发 SAF 导出。
    unawaited(_fillCompletedSize(id));
  }

  /// 下载完成后，把成品**导出**到用户授权的 SAF 文件夹（存储②档）。
  ///
  /// - 只在 ② 档（`safDir`）生效；① 档直接写公共目录、③ 档无处可导；
  /// - **绝不抛出**：导出失败不影响"下载已完成"这个事实，只在日志留痕；
  /// - Web：`_exporter` 的实现（SAF）在该平台不适用，导出自然返回 `false`，
  ///   这里不做额外判断（能力判定属于导出实现自己的职责）。
  Future<void> _maybeExportToSaf(String id) async {
    if (_disposed) {
      // 管理器已回收：不再触碰导出实现（它是装配根注入的对象，
      // 此刻可能正在被释放）。成品已在磁盘上，晚一步导出没有意义。
      return;
    }
    final StorageExporter? exporter = _exporter;
    if (exporter == null) {
      return;
    }
    if (!_backend.canReadLocalFile) {
      // Web：没有本地成品可导出（成品在浏览器下载目录）。
      return;
    }
    if (!_exportedToSaf.add(id)) {
      return;
    }
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return;
    }
    try {
      final bool ok = await exporter.export(
        localPath: snap.savePath,
        fileName: snap.fileName,
      );
      if (!ok) {
        _exportedToSaf.remove(id);
        return;
      }
      _diagnostics?.info(
        'DL',
        '已导出到所选文件夹：${snap.fileName}',
        code: 'OGL-DL-301',
      );
      // ★ 导出成功后必须把 id 移出去重表：taskId 由 url+文件名派生，同一附件
      //   「下载 → 导出 → 从列表移除 → 再下载」会复用同一个 id；旧实现只在
      //   失败路径移除，于是第二次 `add(id)` 返回 false，成品**永不导出**。
      _exportedToSaf.remove(id);
    } catch (_) {
      _exportedToSaf.remove(id);
    }
  }

  /// 把后端事件映射成对外快照（进度节流）。
  void _onEvent(IxDownloadEvent event) {
    final String id = event.id;
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return;
    }
    final IxDownloadStatus? status = event.status;
    if (status != null) {
      if (status == IxDownloadStatus.completed) {
        // ★ 双入口去重：完成**不在这里直接改状态**，而是统一收口到
        //   `_finishTask`（先校验完整性，再宣告完成、导出 SAF）；
        //   它内部的幂等守卫保证只走一次。
        unawaited(_finishTask(id));
        return;
      }
      _snapshots[id] = snap.copyWith(
        status: status,
        // 失败事件带描述（结构化）；其余状态没有错误 → 显式清空，
        // 免得旧错误挂在新状态上（进度事件不走这里，不会误清）。
        error: _errorOfDescription(event.error),
      );
      _safeNotify();
      return;
    }
    // 进度事件。
    final int total = event.total > 0 ? event.total : snap.total;
    final int received = event.received;
    // 库只给进度，不给速度：用两次采样的差分估算。
    final DateTime now = DateTime.now();
    final ({DateTime at, int received})? last = _lastSample[id];
    double speed = snap.bytesPerSecond;
    if (last != null) {
      final int ms = now.difference(last.at).inMilliseconds;
      final int delta = received - last.received;
      if (ms > 0 && delta >= 0) {
        speed = delta * 1000 / ms;
      }
    }
    _lastSample[id] = (at: now, received: received);
    _snapshots[id] = snap.copyWith(
      received: received,
      total: total,
      bytesPerSecond: speed,
      status: IxDownloadStatus.running,
    );
    _notifyThrottled();
  }

  /// 安全通知：`dispose()` 之后到达的回调（分片任务是 fire-and-forget、
  /// 后端的流事件也可能已在途）一律**静默丢弃** —— 绝不触碰已回收的
  /// `ChangeNotifier`（debug 下会直接断言失败）。
  void _safeNotify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _notifyThrottled() {
    if (_disposed) {
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 200) {
      return;
    }
    _lastNotify = now;
    _safeNotify();
  }

  /// 完成后回填真实文件大小。
  ///
  /// 库对小文件可能一次进度事件都不发 → 界面会一直显示 "0 B"（截图实证）。
  /// Web：后端返回 `null`（拿不到），保持未知——**不编造**。
  Future<void> _fillCompletedSize(String id) async {
    try {
      final IxDownloadTask? snap = _snapshots[id];
      if (snap == null) {
        return;
      }
      final int? size = await _backend.completedSize(id, path: snap.savePath);
      final IxDownloadTask? fresh = _snapshots[id];
      if (size == null || fresh == null) {
        return;
      }
      _snapshots[id] = fresh.copyWith(received: size, total: size);
      _safeNotify();
    } catch (error) {
      // 不允许静默：按事件码上报到通知中心。
      _diagnostics?.warn(
        'DOWNLOAD',
        '下载完成后无法读取文件大小',
        code: 'OGL-DL-101',
        data: <String, Object?>{'taskId': id, 'error': '$error'},
      );
    }
  }

  @override
  void dispose() {
    // ★ 先把 `_disposed` 立起来（**最开头**）：从这一刻起所有通知都走
    //   `_safeNotify` 被拦下。分片任务是 fire-and-forget
    //   （`unawaited(_runRanged(...))`），管理器回收与它们的回调是赛跑关系；
    //   不先立旗，回调就可能触碰已回收的 `ChangeNotifier`（debug 直接断言失败）。
    _disposed = true;
    for (final DownloadCancelToken token in _rangeTokens.values) {
      token.cancel();
    }
    _rangeTokens.clear();
    _subscription?.cancel();
    _backend.dispose();
    super.dispose();
  }
}
