/// L2 中枢级 · 内建下载器（**按平台选下载后端**）。
///
/// ## 公开契约保持不变
/// [IxDownloadManager] / [IxDownloadTask] / [IxDownloadCategory] /
/// [IxDownloadStatus] 的名字与语义不变，页面（下载管理、Release、仓库文件）
/// **零改动**。
///
/// ## 为什么要有"后端"
/// 下载这件事在两个平台上**根本不同**：
/// - 原生（Android / iOS / Windows / Linux / macOS）：`background_downloader`
///   提供后台下载、断点续传、队列与通知，成品落到应用文档目录；
/// - **Web**：`background_downloader` **没有 Web 实现**（其平台清单只有
///   android / ios 等原生平台）。浏览器里没有后台任务、没有文件系统落盘、
///   也不允许页面接管"下载中的字节"；页面唯一能做的是**把最终地址交给
///   浏览器自己的下载器**。
///
/// 因此把"怎么下载"抽成 [IxDownloadBackend]（本文件声明接口），
/// 本分支（纯 Web）取 `ix_download_backend_web.dart`（交给浏览器下载）。
/// `File` / `Directory` 的使用**全部**隔离在平台实现文件里。
///
/// ## 能力差异（Web 上不可用，如实标注，不假装支持）
/// | 能力 | 原生 | Web |
/// |------|------|-----|
/// | 后台下载 / 队列 / 重试 | 有（库提供） | 无（浏览器接管） |
/// | 暂停 / 继续 | 有 | **无**（浏览器下载不可被页面控制） |
/// | 多连接分片 | 有（Range） | **无**（见 `range_download_web.dart`） |
/// | 读回成品字节（校验 sha256 / 导出） | 有 | **无**（成品在浏览器下载目录） |
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../kernel/contract/download_engine.dart';
import '../../kernel/contract/storage_export.dart';
import '../../kernel/diagnostics.dart';
import 'ix_download_backend_web.dart';

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
  ///
  /// [errorReason] 仅在 [status] 为 [IxDownloadStatus.failed] 时非 null；
  /// 它是**强类型**失败原因（见 [IxDownloadFailureReason]），由 UI 层
  /// 通过 `_t('downloadFailed.${reason.name}')` 映射为本地化文案——
  /// 比传原始 String 更安全（不可注入、不可拼写错误、自动 lint）。
  const IxDownloadEvent.state(
    this.id,
    this.status, {
    this.errorReason,
  })  : received = 0,
        total = 0,
        error = null;

  /// 进度事件。
  const IxDownloadEvent.progress(
    this.id, {
    required this.received,
    required this.total,
  })  : status = null,
        error = null,
        errorReason = null;

  /// 任务 id。
  final String id;

  /// 状态（进度事件为 `null`）。
  final IxDownloadStatus? status;

  /// 已收字节（进度事件）。
  final int received;

  /// 总字节（进度事件；0 = 未知）。
  final int total;

  /// 失败原因（已弃用：见 [errorReason]）。保留字段仅为兼容旧实现，
  /// 新代码请走 [errorReason]（i18n 强类型）。
  @Deprecated('Use errorReason for new code; this is the untranslated string.')
  final String? error;

  /// 强类型失败原因（仅状态事件为 `failed` 时非 null）。
  ///
  /// UI 层：`_t('downloadFailed.${reason.name}')`；
  /// 缺该键时兜底走 [IX_DOWNLOAD_FAILURE_FALLBACK]。
  final IxDownloadFailureReason? errorReason;
}

/// 下载失败的强类型原因（用于事件 + UI 本地化）。
///
/// ## 为什么是枚举而不是 String
/// - UI 层要 `_t('downloadFailed.${reason.name}')` 拿本地化文案；
///   String 没有 `.name`，且允许任意拼写（typo）→ 不能 lint。
/// - 后端（`ix_download_backend_web.dart`）只暴露这几个有限原因；
///   加上 `ok` 是为了"成功也走枚举、不混用类型"。
/// - 增删原因必须改这个枚举 + 同步更新 i18n 键 + 跑 `i18n_scan --check`。
enum IxDownloadFailureReason {
  /// 占位：成功（事件不为失败时也会用到，便于 UI 无脑 switch）。
  ok,

  /// 浏览器不允许页面为跨域请求设置 Authorization 头。
  authHeaderNotAllowed,

  /// 触发了浏览器的弹窗拦截（`window.open` 被拦）。
  popupBlocked,

  /// 浏览器未给出可用的应用去"打开外部链接"（无浏览器 / launchUrl 抛）。
  browserLaunchFailed,

  /// 平台不支持该操作（暂停 / 继续 / 分片）。Web 后端 `_rejectUnsupported`
  /// 走诊断通道（`OGL-DL-501`），不返回失败原因——保留枚举以便未来需要时
  /// 接入 UI 而不破坏 `.name` 拼写。
  notSupported,
}

/// 当 `downloadFailed.<reason.name>` 缺失时的兜底文案（i18n 扫描兜底链之外的
/// 终端兜底：开发期忘了加键也能展示出"是哪个原因"）。
const String IX_DOWNLOAD_FAILURE_FALLBACK = 'Download failed';

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

  /// 计算落盘位置，**不入队**（分片路径需要先知道目标文件 URI）。
  ///
  /// 原生上返回 `Uri.file(spec.savePath)`（本地真实路径）；
  /// Web 上返回 `null` —— 浏览器写进它自己的下载目录，页面拿不到路径，
  /// 接口里**绝不**返回下载地址（与"`savePath` 等于本地路径"语义冲突）。
  Future<Uri?> pathFor(IxDownloadSpec spec);

  /// 真正开始下载。
  Future<void> enqueue(IxDownloadSpec spec);

  /// 暂停（不支持时应为空操作，由管理器先行判能力）。
  Future<void> pause(String id);

  /// 继续。
  Future<void> resume(String id);

  /// 取消（Web 上无法真正中止浏览器下载，为空操作）。
  Future<void> cancel(String id);

  /// 已完成文件的大小（字节）；拿不到返回 `null`（**不编造**）。
  Future<int?> completedSize(String id);

  /// 文件的 sha256（小写十六进制）；不可读返回 `null`。
  Future<String?> fileSha256(String id);

  /// 删除本地文件（完整性校验不通过时清理）。
  Future<void> deleteFile(String id);

  /// 释放资源。
  void dispose();
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
  name = name.replaceAll(RegExp(r'^[.]+'), '').replaceAll(RegExp(r'[. ]+$'), '');
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
  if (_kReservedDeviceNames.contains(safeStem.toLowerCase())) {
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
  if (parsed == null ||
      (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    throw ArgumentError.value(url, 'url', '只允许 http/https 地址');
  }
  return url;
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
    this.failureReason,
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

  /// 失败原因（**自由文本**，给"非 Web / 非固定原因"用，例如校验不匹配
  /// `'integrityMismatch'`、多连接下载异常 `$error`）。Web 后端的枚举化失败
  /// 用下方的 [failureReason] 字段；UI 层优先渲染 [failureReason]。
  final String? error;

  /// 强类型失败原因（Web 后端专用，UI 渲染本地化文案）。
  ///
  /// 与 [error] 同时只能有一个非 null：Web 走 [failureReason]；
  /// 原生（非枚举化原因）走 [error]。详情见 [IxDownloadEvent.errorReason]。
  final IxDownloadFailureReason? failureReason;

  /// 完整性校验结果（三态，**不谎称验过**）：
  /// - `true`：已按期望摘要校验**通过**；
  /// - `false`：校验过但**不匹配** —— 任务会被置为失败；
  /// - `null`：**没有摘要可比对**，或**本平台拿不到成品字节**（Web）——
  ///   界面须如实呈现为「未校验」。
  final bool? verified;

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
  IxDownloadTask copyWith({
    IxDownloadStatus? status,
    int? received,
    int? total,
    double? bytesPerSecond,
    String? error,
    IxDownloadFailureReason? failureReason,
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
        error: error ?? this.error,
        failureReason: failureReason ?? this.failureReason,
        verified: verified ?? this.verified,
      );
}

/// 下载管理器（展示层唯一入口；内部委托平台后端）。
class IxDownloadManager extends ChangeNotifier {
  /// 创建管理器。
  ///
  /// [diagnostics] 用于把"取不到文件大小"等**降级**情况按事件码上报
  /// （不允许静默）。
  /// [backend] 仅供测试注入；不传则取平台实现（`ix_download_backend_web.dart`）。
  IxDownloadManager({
    KernelDiagnostics? diagnostics,
    DownloadEngine? engine,
    StorageExporter? storageExporter,
    IxDownloadBackend? backend,
  })  : _diagnostics = diagnostics,
        _engine = engine,
        _exporter = storageExporter,
        _backend = backend ?? createDownloadBackend() {
    _subscription = _backend.events.listen(_onEvent);
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
    // 原生：`Uri.file(savePath).toFilePath()` 真正本地路径；
    // Web：返回 `null`，界面据此知道"成品在浏览器下载目录"，
    //   与之前把 URL 塞进 savePath（导致 `Uri.file(url)` 解析错）彻底切割。
    final Uri? localUri = await _backend.pathFor(spec);
    final String savePath = localUri?.toFilePath() ?? '';
    _snapshots[id] = IxDownloadTask(
      id: id,
      url: url,
      fileName: safeName,
      category: category,
      savePath: savePath,
      status: IxDownloadStatus.queued,
      received: 0,
      total: 0,
      bytesPerSecond: 0,
      createdAt: DateTime.now(),
    );
    // 期望摘要（sha256）；为空表示该资源没有可比对的摘要（如实标记未校验）。
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      _expectedSha256[id] = expectedSha256;
    }
    notifyListeners();

    // 并发 > 1 且装配层给了分片引擎、且后端支持分片 → 走**多连接分片**；
    // 不支持 Range 时自动回退到单连接（同一 taskId，页面无感）。
    // Web 后端 `supportsRanged = false`，因此这里直接走浏览器下载。
    if (connections > 1 &&
        _engine != null &&
        _backend.supportsRanged &&
        savePath.isNotEmpty) {
      _rangeConnections[id] = connections;
      unawaited(_runRanged(id: id, connections: connections));
      return _snapshots[id]!;
    }
    await _backend.enqueue(spec);
    return _snapshots[id]!;
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
      if (current.supportsRange && current.total != null && current.total! > 0) {
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
      _rangeTokens.remove(id);
      _diagnostics?.info(
        'DL',
        '无可分片通道，回退单连接下载：${candidates.first}',
        code: 'OGL-DL-201',
        data: probe.toJson(),
      );
      final String target = reachable ?? candidates.first;
      final IxDownloadSpec fallback = spec.copyWith(url: target);
      final String path =
          (await _backend.pathFor(fallback))?.toFilePath() ?? '';
      final IxDownloadTask? current = _snapshots[id];
      if (current != null) {
        _snapshots[id] = current.copyWith(savePath: path);
      }
      await _backend.enqueue(fallback);
      return;
    }

    _snapshots[id] = snap.copyWith(
      status: IxDownloadStatus.running,
      total: probe.total!,
    );
    notifyListeners();

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
    } catch (error) {
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
          error: '$error',
        );
        notifyListeners();
      }
    } finally {
      _rangeTokens.remove(id);
      _pausedIds.remove(id);
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
      );
      notifyListeners();
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
    notifyListeners();
  }

  /// 清空已完成 / 已取消 / 失败的条目（不动磁盘文件）。
  void clearFinished() {
    final Set<String> gone = <String>{};
    _snapshots.removeWhere((String id, IxDownloadTask t) {
      final bool finished = t.status == IxDownloadStatus.completed ||
          t.status == IxDownloadStatus.canceled ||
          t.status == IxDownloadStatus.failed;
      if (finished && t.status != IxDownloadStatus.completed) {
        _specs.remove(id);
      }
      if (finished) {
        gone.add(id);
      }
      return finished;
    });
    // 与 remove() 一样，把 per-id 的辅助表一并清掉（否则会随会话累积）。
    for (final String id in gone) {
      _rangeConnections.remove(id);
      _pausedIds.remove(id);
      _lastSample.remove(id);
      _expectedSha256.remove(id);
      _urlCandidates.remove(id);
      _exportedToSaf.remove(id);
    }
    notifyListeners();
  }

  void _applyStatus(String id, IxDownloadStatus status) {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap != null) {
      _snapshots[id] = snap.copyWith(status: status);
      notifyListeners();
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
      final String? actual = await _backend.fileSha256(id);
      if (actual == null) {
        return false;
      }
      final bool ok = actual == expected;
      _snapshots[id] = snap.copyWith(verified: ok);
      if (ok) {
        _diagnostics?.info(
          'DL',
          '完整性校验通过：${snap.fileName}',
          code: 'OGL-DL-402',
        );
      } else {
        _diagnostics?.error(
          'DL',
          '完整性校验不匹配，判定为失败：${snap.fileName}',
          code: 'OGL-DL-403',
          data: <String, Object?>{'expected': expected, 'actual': actual},
        );
      }
      notifyListeners();
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
    // ★ 与 `_runRanged` 同样的入口守卫：分片任务是 fire-and-forget，
    //   在它跑完之前用户可能已 dispose 管理器或移除任务；这时再动
    //   `_snapshots[id]` 会把条目复活（"任务走了又回来"）。
    if (_disposed || !_snapshots.containsKey(id)) {
      return;
    }
    final bool ok = await _verifyIntegrity(id);
    if (!ok) {
      final IxDownloadTask? snap = _snapshots[id];
      if (!_disposed && snap != null) {
        // ★ 校验不匹配的成品必须**删掉**：留着它，用户点「重试」只会把同一份
        //   坏字节再校验一遍，永远失败。删掉后重试才会真正重新下载。
        await _backend.deleteFile(id);
        _snapshots[id] = snap.copyWith(
          status: IxDownloadStatus.failed,
          error: 'integrityMismatch',
        );
        notifyListeners();
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
      // 失败事件：优先把强类型原因写到 `failureReason`，方便 UI 走 `_t`。
      // `event.error`（已弃用 String）保留兼容老路径（仅原生端可能给）。
      final String? legacy =
          // ignore: deprecated_member_use_from_same_package
          event.error;
      _snapshots[id] = snap.copyWith(
        status: status,
        error: legacy,
        failureReason: event.errorReason,
      );
      notifyListeners();
      if (status == IxDownloadStatus.completed) {
        // 先校验完整性，再回填大小与导出 SAF（校验不过则判失败、不导出）。
        unawaited(_finishTask(id));
      }
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

  void _notifyThrottled() {
    if (_disposed) {
      return;
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 200) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  /// 完成后回填真实文件大小。
  ///
  /// 库对小文件可能一次进度事件都不发 → 界面会一直显示 "0 B"（截图实证）。
  /// Web：后端返回 `null`（拿不到），保持未知——**不编造**。
  Future<void> _fillCompletedSize(String id) async {
    // ★ 入口守卫：与 _finishTask 同一来源——任务可能在后台完成回填到来时
    //   已被用户移除/管理器已 dispose，再写 _snapshots[id] 会把条目复活。
    if (_disposed || !_snapshots.containsKey(id)) {
      return;
    }
    try {
      final int? size = await _backend.completedSize(id);
      final IxDownloadTask? snap = _snapshots[id];
      if (_disposed || size == null || snap == null) {
        return;
      }
      _snapshots[id] = snap.copyWith(received: size, total: size);
      notifyListeners();
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
    // ★ 分片任务是 fire-and-forget（`unawaited(_runRanged(...))`）：不取消的话，
    //   管理器回收后引擎仍在下载，并会调用已 dispose 的 ChangeNotifier
    //   （debug 下直接断言失败）。这里逐个取消，并用 _disposed 拦住后续通知。
    for (final DownloadCancelToken token in _rangeTokens.values) {
      token.cancel();
    }
    _rangeTokens.clear();
    _disposed = true;
    _subscription?.cancel();
    _backend.dispose();
    super.dispose();
  }
}
