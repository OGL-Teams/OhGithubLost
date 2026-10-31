/// L2 中枢级 · 仓库文件操作服务。
///
/// 统一 create / delete / rename(=move) / copy / batchDelete / batchMove / batchCopy。
///
/// ## 这一层解决的问题
/// 既有能力分散在三处，各自只覆盖一半场景：
/// 1. `GhApi.putContent` / `deleteContent`（Contents API）：单文件可用，但
///    路径**裸插值**进 URL（含 `#` / `?` / 空格时会静默截断），且受 1 MB 红线限制；
/// 2. `GhApi.commitFiles`（Git Data API）：多文件**原子**提交，但只接受 UTF-8 文本，
///    二进制经 `utf8.encode` 会被破坏（非法字节 → U+FFFD，回写即数据事故）；
/// 3. 展示层路径规则（`surface/util/path_rules.dart`）只服务"新建条目"，
///    且 domain 不能 import surface（依赖方向 surface → domain → base → kernel）。
///
/// 本服务把三者收口成一个入口：
/// - **路径**：所有进入 URL 的路径逐段 `Uri.encodeComponent`
///   （提交 JSON 里仍是**原始路径** —— 树条目必须是仓库里的真实名字）；
/// - **文本 / 二进制**：扩展名判定 + 严格 UTF-8 复核。文本走既有
///   `commitFiles` 管线；二进制 / 超限 / 符号链接 / 子模块走 **Blobs API 或
///   sha 引用**，字节精确（见 [_readPayload] 与 [_commitRaw] 的说明）；
/// - **目录**：递归树前缀展开；服务端返回截断（`tree.truncated`）时**拒绝执行**，
///   绝不"部分搬运"；
/// - **批量**：> [RepoFileService.batchSize]（默认 200）自动分批串行提交，
///   基线**逐批链式推进**（上一批的 commit SHA 即下一批的 `expectedHeadSha`）；
/// - **结果**：逐项明细（成功 / 失败 / 已取消 / 未执行），绝不谎报整体状态。
///
/// ## 一致性策略（一句话）
/// **凡是"分支状态"的写入都带基线**：批量提交一律传 `expectedHeadSha`（调用方
/// 给了就用，没给就从分支 ref 解析；多批时链式推进）；Contents API 的单文件
/// 写入用**文件级 baseSha**（服务端乐观锁：create 不覆盖、delete 不删错版本）；
/// 所有内容读取都发生在第一批提交之前（`commitFiles` 同款"先读后写"原则）。
///
/// ## 取消
/// [RepoFileService.cancel]（或调用方自备的 [RepoFileCancelToken]）在
/// **检查点**生效：逐文件读取之间、每批提交之前、每个 blob 上传之前。
/// 已发出的 HTTP 请求**不打断**（批次内一旦开始创建对象就把它做完，避免留下
/// 半可见状态）；被取消的条目在结果中如实标记 `cancelled`。
///
/// ## 错误码格式
/// 逐项结果的 [RepoFileItemResult.error] 形如 `code: message`（code 稳定可供
/// 程序判断，message 为中文可读描述）。码表：
/// `invalidRepo` / `invalidPath` / `emptyContent` / `exists` / `notFound` /
/// `notDirectory` / `isDirectory` / `conflict` / `rateLimit` / `auth` /
/// `treeTruncated` / `tooManyFiles` / `unsupported` / `cancelled` /
/// `aborted` / `failed`。
library;

import 'dart:convert';

import '../../kernel/contract/disk_types.dart';
import '../../kernel/contract/net_types.dart';
import '../../kernel/diagnostics.dart';
import 'gh_api.dart';
import 'gh_client.dart';
import 'gh_models.dart';

/// 操作类型。
enum RepoFileOp {
  /// 新建单文件。
  create,

  /// 删除（文件或目录递归）。
  delete,

  /// 重命名 / 移动（文件或目录）。
  rename,

  /// 复制（文件或目录）。
  copy,

  /// 批量删除（目录递归 / 多条目）。
  batchDelete,

  /// 批量移动。
  batchMove,

  /// 批量复制。
  batchCopy;

  /// 是否为批量类别。
  ///
  /// [RepoFileService.batch] 的组合操作**只接受**非批量类别
  /// （批量类别用于描述"目录递归 / 多条目"这类由服务内部展开的动作）。
  bool get isBatchKind =>
      this == batchDelete || this == batchMove || this == batchCopy;
}

/// 进度阶段。
enum RepoFilePhase {
  /// 扫描 / 校验 / 基线解析中。
  preparing,

  /// 逐文件读取内容（rename / copy / batch 需要读旧内容）。
  reading,

  /// 正在把一批变更写入远端（blob / 内容上传开始）。
  uploading,

  /// 一批变更的提交已落定（commit + 引用更新完成）。
  committing,

  /// 全部完成。
  done,
}

/// 进度回调载荷。
///
/// `current` 的含义随阶段变化（都表示"已完成条目数"的口径）：
/// - `preparing`：已扫描条目数（通常 0）；
/// - `reading`：已读取文件数；
/// - `uploading`：本批开始时**已提交完成**的条目数；
/// - `committing`：该批提交后已完成的条目数；
/// - `done`：`total`。
class RepoFileProgress {
  /// 创建进度。
  const RepoFileProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.currentPath,
  });

  /// 阶段。
  final RepoFilePhase phase;

  /// 已完成条目数。
  final int current;

  /// 总条目数（未知时为 0）。
  final int total;

  /// 当前正在处理的路径（批次级事件为批次代表路径，可能为空串）。
  final String currentPath;

  /// 完成比例（0–1；总数未知时为 0）。
  double get ratio => total <= 0 ? 0 : (current / total).clamp(0, 1).toDouble();

  @override
  String toString() =>
      'RepoFileProgress(${phase.name}, $current/$total, $currentPath)';
}

/// 单条结果。
class RepoFileItemResult {
  /// 创建结果。
  const RepoFileItemResult({required this.path, required this.ok, this.error});

  /// 成功项。
  ///
  /// rename / copy 的 [path] 是**新路径**（结果视角：文件现在在哪）；
  /// delete 是**被删除的路径**；create 是**创建的路径**。
  factory RepoFileItemResult.success(String path) =>
      RepoFileItemResult(path: path, ok: true);

  /// 失败项（[error] 形如 `code: message`）。
  factory RepoFileItemResult.failure(String path, String error) =>
      RepoFileItemResult(path: path, ok: false, error: error);

  /// 相关路径（见 [RepoFileItemResult.success] 的说明）。
  final String path;

  /// 是否成功。
  final bool ok;

  /// 结构化错误码或描述（`code: message`），成功时为 `null`。
  final String? error;

  @override
  String toString() =>
      'RepoFileItemResult($path ${ok ? 'OK' : 'FAIL: $error'})';
}

/// 操作结果（含逐项明细）。
class RepoFileResult {
  /// 创建结果。
  const RepoFileResult({required this.ok, required this.items, this.commitSha});

  /// 是否全部成功。
  final bool ok;

  /// 逐项明细。
  final List<RepoFileItemResult> items;

  /// 最后一次提交的 SHA（如有）。
  ///
  /// 说明：Git Data API 的提交（rename / copy / delete 目录 / batch）必然可得；
  /// Contents API 的单文件写入（create / 单文件 delete）拿不到 commit SHA
  /// （`GhApi.putContent` 只解析内容体，不解析响应里的 commit 字段），
  /// 此时为 `null`，**不拿 blob sha 冒充**。
  final String? commitSha;

  /// 条目总数。
  int get total => items.length;

  /// 成功数。
  int get succeeded => items.where((RepoFileItemResult item) => item.ok).length;

  /// 失败数。
  int get failed => items.where((RepoFileItemResult item) => !item.ok).length;

  /// 一行摘要（通知 / 角标用）。
  String get summary => '成功 $succeeded / 失败 $failed';

  @override
  String toString() => 'RepoFileResult(ok=$ok, $summary, '
      'commit=${commitSha == null ? '-' : shortSha(commitSha)})';
}

/// 批量组合操作的单条描述。
///
/// [RepoFileService.batch] 需要操作携带**路径与内容**，而 [RepoFileOp] 只是
/// 类别枚举，因此用本类承载一条具体操作。
class RepoFileBatchOp {
  /// 新建一个文件（[content] 不能为空；`.gitkeep` 例外——它就是空占位）。
  RepoFileBatchOp.create({required this.path, required this.content})
      : op = RepoFileOp.create,
        newPath = null,
        isDirectory = false;

  /// 删除（[isDirectory] 为真时递归删除目录下全部文件）。
  RepoFileBatchOp.delete({required this.path, this.isDirectory = false})
      : op = RepoFileOp.delete,
        content = null,
        newPath = null;

  /// 重命名 / 移动（文件或目录，自动探测）。
  RepoFileBatchOp.rename({required this.path, required this.newPath})
      : op = RepoFileOp.rename,
        content = null,
        isDirectory = false;

  /// 复制（文件或目录，自动探测；不删源）。
  RepoFileBatchOp.copy({required this.path, required this.newPath})
      : op = RepoFileOp.copy,
        content = null,
        isDirectory = false;

  /// 操作类别（**只允许** create / delete / rename / copy）。
  final RepoFileOp op;

  /// 源路径（create 为新建路径）。
  final String path;

  /// 目标路径（仅 rename / copy）。
  final String? newPath;

  /// 文件内容（仅 create）。
  final String? content;

  /// 是否目录（仅 delete 使用）。
  final bool isDirectory;

  /// 可读摘要（日志 / 诊断用）。
  Map<String, Object?> describe() => <String, Object?>{
        'op': op.name,
        'path': path,
        if (newPath != null) 'newPath': newPath,
        if (isDirectory) 'isDirectory': true,
      };

  @override
  String toString() =>
      'RepoFileBatchOp(${op.name} $path${newPath == null ? '' : ' → $newPath'})';
}

/// 取消令牌（照 `DownloadCancelToken` 的语义：跨阶段共享、只置位不阻塞）。
///
/// 传入公开方法即启用；不传时服务内部自建一枚，供 [RepoFileService.cancel]
/// 取消"最近开始的操作"。取消语义见文件头。
class RepoFileCancelToken {
  /// 创建令牌。
  RepoFileCancelToken();

  bool _cancelled = false;

  /// 是否已取消。
  bool get isCancelled => _cancelled;

  /// 请求取消（下一次检查点生效）。
  void cancel() {
    _cancelled = true;
  }

  /// 检查点：已取消则抛出内部异常，由服务统一转成 `cancelled` 逐项结果。
  void _check() {
    if (_cancelled) {
      throw const _RepoFileCancelled();
    }
  }
}

/// 服务已取消（内部流转；永远被服务捕获，不逃逸到调用方）。
class _RepoFileCancelled implements Exception {
  /// 创建。
  const _RepoFileCancelled();

  @override
  String toString() => '已取消';
}

/// 结构化失败（内部流转）。
class _RepoFileFailure implements Exception {
  /// 创建。
  const _RepoFileFailure(this.code, this.message);

  /// 稳定错误码。
  final String code;

  /// 可读描述。
  final String message;

  @override
  String toString() => '$code: $message';
}

/// 仓库条目路径规则（域层唯一判定入口）。
///
/// ## 为什么在这里自带一份规则
/// 依赖方向是 `surface → domain → base → kernel`：domain 不能 import surface，
/// 因此 `surface/util/path_rules.dart`（新建 / 重命名共用的用户规则）与
/// `domain/ix/ix_download.dart` 的保留设备名清单、`surface/util/file_preview.dart`
/// 的图片 / 音频扩展名表，在这里**集中声明一次**，供本服务与后续展示层引用，
/// 避免"两份实现各自漂移"。规则本身与 path_rules 保持一致：
/// - **禁止中文与全角字符**（后续落盘 / 转译极易出错，入口直接拒绝）；
/// - **禁止空格与 `<>:"|?*#%\` 等特殊字符**（只允许 `A-Z a-z 0-9 . _ -` 与 `/`）；
/// - **禁止 Windows 保留名**（con / prn / aux / nul / com1-9 / lpt1-9）；
/// - **禁止空文件内容**（`.gitkeep` 目录占位例外）。
///
/// 说明：严格的字符集规则只作用于**用户新输入的目标路径**；仓库里既有的
/// 旧路径（可能含中文等历史名称）不因此被拒绝——移动它们时只做协议/安全
/// 层面的校验（见 [validateDerivedPath]）。
class RepoFilePaths {
  const RepoFilePaths._();

  /// `.gitkeep` 文件名（目录占位）。
  static const String gitKeepName = '.gitkeep';

  /// Windows 保留名（大小写不敏感；这些名字在 Windows 上无法落盘）。
  ///
  /// 与 `surface/util/path_rules.dart` 及 `domain/ix/ix_download.dart`
  /// 的保留名清单同源。
  static const Set<String> reservedNames = <String>{
    'con', 'prn', 'aux', 'nul', //
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// 二进制扩展名表（域层唯一判定入口）。
  ///
  /// 与 `surface/util/file_preview.dart` 的图片 / 音频族同源、并补齐视频 /
  /// 压缩包 / 可执行文件 / 字体等常见二进制族。
  ///
  /// **判定错了也不会损坏数据**：读取侧对"文本类"还要做**严格 UTF-8 复核**，
  /// 复核不过自动改走字节搬运（base64 原样透传），写入侧两条路径都以字节
  /// 精确为底线（见 [_readPayload]）。因此本表只影响"用哪条管线"，
  /// 不决定"对不对"。
  static const Set<String> binaryExtensions = <String>{
    // 位图（与 file_preview.dart 图片族一致；SVG 是文本，不在此列）
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'avif', 'tif', 'tiff',
    // 音频（与 file_preview.dart 音频族一致）
    'mp3', 'm4a', 'wav', 'ogg', 'oga', 'flac', 'aac', 'opus', 'wma', 'mid',
    // 视频
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', 'wmv', 'flv', 'mpg', 'mpeg',
    '3gp',
    // 压缩 / 打包
    'zip', 'gz', 'tgz', 'bz2', 'xz', 'zst', '7z', 'rar', 'jar', 'war', 'apk',
    'ipa', 'aab', 'deb', 'rpm', 'dmg', 'iso', 'img',
    // 文档
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
    'epub',
    // 可执行 / 目标文件
    'exe', 'dll', 'so', 'dylib', 'bin', 'o', 'obj', 'a', 'lib', 'pdb',
    'class', 'pyc', 'pyo', 'wasm', 'dex', 'elf', 'msi',
    // 字体
    'ttf', 'otf', 'woff', 'woff2', 'eot',
    // 数据库 / 归档数据
    'db', 'sqlite', 'sqlite3', 'mdb', 'dat', 'pak', 'mo',
    // 设计 / 工程文件
    'psd', 'ai', 'sketch', 'fig', 'xcf',
    // 密钥库
    'keystore', 'jks', 'p12', 'pfx',
  };

  /// 中文 / 全角 / 其他东亚标点（含 CJK、全角标点）。与 path_rules 一致。
  static final RegExp _kCjk =
      RegExp(r'[\u2E80-\u9FFF\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFFEF]');

  /// 单个路径段允许的字符（不含 `/`）。
  static final RegExp _kAllowedSegment = RegExp(r'^[A-Za-z0-9._-]+$');

  /// 控制字符。
  static final RegExp _kControl = RegExp(r'[\x00-\x1F\x7F]');

  /// 是否为目录占位文件。
  static bool isGitKeep(String path) {
    final List<String> parts = path.split('/');
    return parts.isNotEmpty && parts.last == gitKeepName;
  }

  /// 取小写扩展名（无扩展名返回空串）。
  static String extensionOf(String path) {
    final String name = path.split('/').last;
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  /// 是否按二进制处理（扩展名判定；见 [binaryExtensions] 的说明）。
  static bool isBinaryPath(String path) =>
      binaryExtensions.contains(extensionOf(path));

  /// 规范化：去除首尾空白与首尾 `/`（仓库内路径是相对路径）。
  static String clean(String path) {
    String result = path.trim();
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// 把仓库内路径**逐段**百分号编码（仅供 URL 插值）。
  ///
  /// 树 / 提交的 JSON 体里必须用 [clean] 后的**原始路径**——那是仓库里的
  /// 真实文件名，编码过的路径会被原样写进仓库（数据事故）。
  static String encodeForUrl(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  /// 校验"新建 / 重命名目标"的**文件**路径。返回 `null` 表示通过。
  static String? validateFilePath(String raw) =>
      _validate(raw, directory: false);

  /// 校验"新建 / 重命名目标"的**目录**路径（尾随 `/` 可选）。返回 `null` 表示通过。
  static String? validateDirectoryPath(String raw) =>
      _validate(raw, directory: true);

  /// 文件内容校验（用户规则：**不允许空文件**；`.gitkeep` 例外）。
  static String? validateContent(String path, String content) {
    if (isGitKeep(path)) {
      return null;
    }
    if (content.trim().isEmpty) {
      return '文件内容不能为空（空文件没有意义；目录占位请用 .gitkeep）';
    }
    return null;
  }

  /// 校验**目录展开派生**出的目标路径（比用户输入宽松）。
  ///
  /// 只拒绝会破坏协议 / 安全形态的东西（空段、`.` / `..`、反斜杠、控制字符、
  /// 首尾 `/`）；不执行字符集 / 中文 / 长度限制——旧仓库里的历史文件名
  /// （可能含中文）应当能被搬运。返回 `null` 表示通过。
  static String? validateDerivedPath(String path) {
    final String input = path.trim();
    if (input.isEmpty) {
      return '路径为空';
    }
    if (_kControl.hasMatch(input)) {
      return '路径包含控制字符';
    }
    if (input.contains(r'\')) {
      return r'路径包含反斜杠（\）';
    }
    if (input.startsWith('/') || input.endsWith('/')) {
      return '路径首尾不能有 /';
    }
    if (input.contains('//')) {
      return '路径包含连续的 /';
    }
    for (final String segment in input.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        return '路径包含非法段：$segment';
      }
    }
    return null;
  }

  static String? _validate(String raw, {required bool directory}) {
    final String input = raw.trim();
    if (input.isEmpty) {
      return directory ? '目录路径不能为空' : '文件路径不能为空';
    }
    if (_kControl.hasMatch(input)) {
      return '路径不能包含控制字符';
    }
    if (_kCjk.hasMatch(input)) {
      return '路径不能包含中文或全角字符';
    }
    if (input.contains(r'\')) {
      return r'路径不能包含反斜杠（\）';
    }
    if (input.startsWith('/')) {
      return '路径不能以 / 开头（仓库内路径是相对路径）';
    }
    if (input.contains('//')) {
      return '路径不能包含连续的 /';
    }
    final bool trailingSlash = input.endsWith('/');
    if (!directory && trailingSlash) {
      return '文件路径不能以 / 结尾';
    }
    final List<String> segments =
        input.split('/').where((String s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return '路径无效';
    }
    for (final String segment in segments) {
      final String? problem = _segmentProblem(segment);
      if (problem != null) {
        return problem;
      }
    }
    return null;
  }

  static String? _segmentProblem(String segment) {
    if (segment == '.' || segment == '..') {
      return '路径不能包含 . 或 .. 段';
    }
    if (segment.length > 100) {
      return '路径段过长（超过 100 字符）：$segment';
    }
    if (segment.endsWith('.') || segment.endsWith(' ')) {
      return '路径段不能以点或空格结尾：$segment';
    }
    if (segment.contains(' ')) {
      return '路径不能包含空格：$segment';
    }
    if (!_kAllowedSegment.hasMatch(segment)) {
      return '路径只能包含 A-Z a-z 0-9 . _ - 与 /：$segment';
    }
    final String stem = segment.contains('.')
        ? segment.substring(0, segment.indexOf('.'))
        : segment;
    if (reservedNames.contains(stem.toLowerCase())) {
      return '「$segment」是系统保留名（Windows 无法落盘）';
    }
    return null;
  }
}

/// 仓库文件操作服务（L2 中枢级）。
///
/// 用法：
/// ```dart
/// final RepoFileResult result = await service.rename(
///   'owner/repo', 'main', 'docs/a.md', 'manual/a.md',
///   expectedHeadSha: headSha,
///   onProgress: (RepoFileProgress p) => setState(() => progress = p),
/// );
/// ```
/// 所有公开方法**永不抛**：网络 / 冲突 / 校验失败都折叠进 [RepoFileResult]
/// 的逐项明细（调用方看 `ok` 与 `items` 即可）。
class RepoFileService {
  /// 创建服务。
  ///
  /// [batchSize]：单次提交包含的最大条目数（默认 200，保守值）；超出自动分批。
  /// [maxFilesPerOp]：单次目录操作允许的最大文件数（默认 2000，**额度保护**：
  /// 每个文件至少一次读取、每批一次四连提交，无上限会烧光小时配额）。
  RepoFileService({
    required this.api,
    GhClient? client,
    KernelDiagnostics? diagnostics,
    this.batchSize = 200,
    this.maxFilesPerOp = 2000,
  })  : client = client ?? api.client,
        _diagnostics = diagnostics;

  /// GitHub 端点封装（Contents / Trees / Blobs / 批量提交）。
  final GhApi api;

  /// 请求客户端（ref / commit 元数据与原始 blob 读取）。
  final GhClient client;

  /// 单次提交的最大条目数（>1 时自动分批串行提交）。
  final int batchSize;

  /// 单次目录操作的最大文件数（超过直接拒绝，防烧光额度）。
  final int maxFilesPerOp;

  final KernelDiagnostics? _diagnostics;
  RepoFileCancelToken? _active;

  /// Blobs API 单对象上限（100 MB）：超过则改用 sha 引用搬运（同仓库内零成本）。
  static const int _contentTransferLimit = 100 * 1024 * 1024;

  /// 常规文件模式。
  static const String _defaultMode = '100644';

  /// 符号链接模式。
  static const String _symlinkMode = '120000';

  /// 子模块（gitlink）模式。
  static const String _submoduleMode = '160000';

  /// 是否已有操作在进行中（[cancel] 只作用于**最近开始**的一次）。
  bool get isBusy => _active != null;

  /// 取消当前进行中的操作（检查点生效，见文件头说明）。
  void cancel() {
    final RepoFileCancelToken? active = _active;
    if (active == null) {
      return;
    }
    _diagnostics?.warn('RF', '用户请求取消文件操作', code: 'OGL-RF-101');
    active.cancel();
  }

  // ───────────────────────── 公开操作 ─────────────────────────

  /// 新建单个文件（Contents API 快路径）。
  ///
  /// - 路径与内容先过 [RepoFilePaths] 规则（禁中文 / 保留名 / 空内容，`.gitkeep` 例外）；
  /// - 目标已存在 → `exists`（**不覆盖**：create 只负责"创建"）；
  /// - [expectedHeadSha] 给了就先校验分支顶端；服务端另有"无 sha 即拒绝覆盖"
  ///   的乐观锁兜底（并发创建第二个写入者会得到 `conflict`）。
  Future<RepoFileResult> create(
    String fullName,
    String branch,
    String path,
    String content, {
    String? message,
    String? expectedHeadSha,
    String? expectedFileSha,
    void Function(RepoFileProgress)? onProgress,
    RepoFileCancelToken? cancelToken,
  }) =>
      _run('create', path, cancelToken, (RepoFileCancelToken token) async {
        _emit(onProgress, RepoFilePhase.preparing, 0, 1, path);
        final String? repoProblem = _checkRepo(fullName);
        if (repoProblem != null) {
          return _singleFailure(
            path,
            _RepoFileFailure('invalidRepo', repoProblem),
          );
        }
        final String? invalid = RepoFilePaths.validateFilePath(path);
        if (invalid != null) {
          return _singleFailure(path, _RepoFileFailure('invalidPath', invalid));
        }
        final String target = RepoFilePaths.clean(path);
        final String? emptyContent =
            RepoFilePaths.validateContent(target, content);
        if (emptyContent != null) {
          return _singleFailure(
            target,
            _RepoFileFailure('emptyContent', emptyContent),
          );
        }
        final String ref = await _resolveRef(fullName, branch);
        if (expectedHeadSha != null) {
          await _assertHead(fullName, ref, expectedHeadSha);
        }
        token._check();
        final _Probe probe = await _probePath(fullName, ref, target);
        if (probe.found) {
          return _singleFailure(
            target,
            _RepoFileFailure(
              probe.isDirectory ? 'isDirectory' : 'exists',
              probe.isDirectory
                  ? '目标已是目录：$target'
                  : '目标已存在：$target（create 不覆盖既有文件）',
            ),
          );
        }
        token._check();
        _emit(onProgress, RepoFilePhase.uploading, 0, 1, target);
        await api.putContent(
          fullName,
          RepoFilePaths.encodeForUrl(target),
          content: content,
          message: message ?? 'create: $target',
          branch: ref,
        );
        _emit(onProgress, RepoFilePhase.committing, 1, 1, target);
        _emit(onProgress, RepoFilePhase.done, 1, 1, '');
        return RepoFileResult(
          ok: true,
          items: <RepoFileItemResult>[RepoFileItemResult.success(target)],
        );
      });

  /// 删除（单文件走 Contents API 快路径；目录递归走 Git Data API）。
  ///
  /// - `isDirectory: false`：单文件删除，用探测到的文件 sha 作**文件级基线**
  ///   （乐观锁：不会删错版本）；
  /// - `isDirectory: true`：`tree(recursive: 1)` 前缀过滤拿全部文件 →
  ///   每 ≤ [batchSize] 个 deletion 一批、**串行提交**（每批一次进度回调）；
  /// - [expectedHeadSha]：给了就逐批校验；多批时服务自动用上一批的 commit
  ///   SHA 作为下一批基线（链式推进）。
  Future<RepoFileResult> delete(
    String fullName,
    String branch,
    String path, {
    bool isDirectory = false,
    String? message,
    String? expectedHeadSha,
    void Function(RepoFileProgress)? onProgress,
    RepoFileCancelToken? cancelToken,
  }) {
    if (isDirectory) {
      return _executeOps(
        'delete',
        fullName,
        branch,
        <RepoFileBatchOp>[
          RepoFileBatchOp.delete(path: path, isDirectory: true),
        ],
        message: message,
        expectedHeadSha: expectedHeadSha,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    return _run('delete', path, cancelToken, (RepoFileCancelToken token) async {
      _emit(onProgress, RepoFilePhase.preparing, 0, 1, path);
      final String? repoProblem = _checkRepo(fullName);
      if (repoProblem != null) {
        return _singleFailure(
          path,
          _RepoFileFailure('invalidRepo', repoProblem),
        );
      }
      final String source = RepoFilePaths.clean(path);
      if (source.isEmpty) {
        return _singleFailure(
          path,
          const _RepoFileFailure('invalidPath', '路径不能为空'),
        );
      }
      final String ref = await _resolveRef(fullName, branch);
      token._check();
      final _Probe probe = await _probePath(fullName, ref, source);
      if (probe.isEmpty) {
        return _singleFailure(
          source,
          _RepoFileFailure('notFound', '目标不存在：$source'),
        );
      }
      if (probe.isDirectory) {
        return _singleFailure(
          source,
          const _RepoFileFailure(
              'isDirectory', '目标为目录：请以 isDirectory: true 递归删除'),
        );
      }
      if (expectedHeadSha != null) {
        await _assertHead(fullName, ref, expectedHeadSha);
      }
      token._check();
      _emit(onProgress, RepoFilePhase.uploading, 0, 1, source);
      await api.deleteContent(
        fullName,
        RepoFilePaths.encodeForUrl(source),
        message: message ?? 'delete: $source',
        baseSha: expectedFileSha ?? probe.content!.sha,
        branch: ref,
      );
      _emit(onProgress, RepoFilePhase.committing, 1, 1, source);
      _emit(onProgress, RepoFilePhase.done, 1, 1, '');
      return RepoFileResult(
        ok: true,
        items: <RepoFileItemResult>[RepoFileItemResult.success(source)],
      );
    });
  }

  /// 重命名 / 移动（文件或目录，自动探测；目标已存在则**拒绝**）。
  ///
  /// - 单文件：读旧内容（Contents 内联 base64 或 Blobs API，**不限 1 MB**）→
  ///   `commitFiles(upserts: {newPath: content}, deletions: [oldPath])`——一次提交、原子；
  /// - 目录：`tree` 前缀过滤 → 逐文件读取 → 每 ≤ [batchSize] 个"移动对"
  ///   一批串行提交（upsert 新路径 + delete 旧路径）；
  /// - 二进制 / 符号链接 / 子模块 / >100 MB：走 Blobs 或 sha 引用，**字节精确**。
  Future<RepoFileResult> rename(
    String fullName,
    String branch,
    String oldPath,
    String newPath, {
    String? message,
    String? expectedHeadSha,
    void Function(RepoFileProgress)? onProgress,
    RepoFileCancelToken? cancelToken,
  }) =>
      _executeOps(
        'rename',
        fullName,
        branch,
        <RepoFileBatchOp>[
          RepoFileBatchOp.rename(path: oldPath, newPath: newPath),
        ],
        message: message,
        expectedHeadSha: expectedHeadSha,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  /// 复制（文件或目录，自动探测；**不删源**；目标已存在则拒绝）。
  ///
  /// 与 [rename] 同款管线，只是不携带 deletions；目录复制同样支持
  /// 二进制 / 大文件（Blobs / sha 引用）。
  Future<RepoFileResult> copy(
    String fullName,
    String branch,
    String fromPath,
    String toPath, {
    String? message,
    String? expectedHeadSha,
    void Function(RepoFileProgress)? onProgress,
    RepoFileCancelToken? cancelToken,
  }) =>
      _executeOps(
        'copy',
        fullName,
        branch,
        <RepoFileBatchOp>[
          RepoFileBatchOp.copy(path: fromPath, newPath: toPath),
        ],
        message: message,
        expectedHeadSha: expectedHeadSha,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  /// 组合操作（**一次 commit**：条目数 ≤ [batchSize] 时只有一个提交）。
  ///
  /// - `ops` 只允许 create / delete / rename / copy（批量类别拒绝）；
  /// - **全有或全无的校验语义**：任一操作在展开阶段失败 → 整个批次不写入
  ///   任何内容（失败方拿到具体错误，其余标记 `aborted`）；
  /// - 条目数 > [batchSize] 时按批串行提交（批次之间**不具备原子性**，
  ///   逐项明细如实汇报哪些完成、哪些未执行）。
  Future<RepoFileResult> batch(
    String fullName,
    String branch,
    List<RepoFileBatchOp> ops, {
    String? message,
    String? expectedHeadSha,
    void Function(RepoFileProgress)? onProgress,
    RepoFileCancelToken? cancelToken,
  }) =>
      _executeOps(
        'batch',
        fullName,
        branch,
        ops,
        message: message,
        expectedHeadSha: expectedHeadSha,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  // ───────────────────────── 执行引擎 ─────────────────────────

  /// 统一执行引擎：**先展开（全只读）、再分块（读 + 提交）**。
  ///
  /// - 展开阶段完成全部探测 / 扫描 / 校验（任一失败 → 一条都不写）；
  /// - 提交阶段逐块读取载荷并提交，"读在前、写在后"（块内成立），
  ///   内存占用以 [batchSize] 为界；
  /// - 多块时用上一块提交的 SHA 作为下一块基线（链式 `expectedHeadSha`）。
  Future<RepoFileResult> _executeOps(
    String label,
    String fullName,
    String branch,
    List<RepoFileBatchOp> ops, {
    String? message,
    String? expectedHeadSha,
    void Function(RepoFileProgress)? onProgress,
    RepoFileCancelToken? cancelToken,
  }) =>
      _run(label, ops.isEmpty ? '' : ops.first.path, cancelToken,
          (RepoFileCancelToken token) async {
        _emit(onProgress, RepoFilePhase.preparing, 0, 0,
            ops.isEmpty ? '' : ops.first.path);
        final String? repoProblem = _checkRepo(fullName);
        if (repoProblem != null) {
          return _singleFailure(
            '',
            _RepoFileFailure('invalidRepo', repoProblem),
          );
        }
        if (ops.isEmpty) {
          return _singleFailure(
            '',
            const _RepoFileFailure('invalidOp', '操作列表为空'),
          );
        }
        for (final RepoFileBatchOp op in ops) {
          if (op.op.isBatchKind) {
            return _singleFailure(
              op.path,
              _RepoFileFailure(
                'invalidOp',
                'batch() 内不允许嵌套批量操作（${op.op.name}）',
              ),
            );
          }
        }
        final String ref = await _resolveRef(fullName, branch);

        // ── 阶段 A：展开（全部只读；任一失败 → 不写任何内容） ──
        final List<_PlannedEntry> entries = <_PlannedEntry>[];
        for (int i = 0; i < ops.length; i++) {
          try {
            token._check();
            await _expandOp(fullName, ref, i, ops[i], entries);
          } catch (error) {
            return _expansionFailure(ops, i, entries, error);
          }
        }
        final int total = entries.length;
        if (total == 0) {
          return _singleFailure(
            ops.first.path,
            const _RepoFileFailure('notFound', '没有可执行的文件'),
          );
        }
        final String commitMessage =
            message ?? _defaultBatchMessage(ops, total);
        _emit(onProgress, RepoFilePhase.preparing, 0, total, '');

        // ── 阶段 B：分块（读 + 提交） ──
        final List<String?> failures = List<String?>.filled(total, null);
        String? chainSha = expectedHeadSha;
        String? commitSha;
        bool stopped = false;
        bool cancelledStop = false;
        int cursor = 0;
        while (cursor < total) {
          int end = cursor + batchSize;
          if (end > total) {
            end = total;
          }
          if (stopped) {
            for (int i = cursor; i < end; i++) {
              failures[i] = cancelledStop
                  ? 'aborted: 操作已取消，本项未执行'
                  : 'aborted: 前序批次失败，本项未执行';
            }
            cursor = end;
            continue;
          }
          if (token.isCancelled) {
            cancelledStop = true;
            stopped = true;
            continue;
          }
          // ① 读本块（rename / copy 在此读取旧内容；create 的载荷已就位）。
          final List<_Transfer> transfers = <_Transfer>[];
          final List<_Deletion> deletions = <_Deletion>[];
          String? readFailure;
          int failedAt = -1;
          bool readCancelled = false;
          for (int i = cursor; i < end; i++) {
            final _PlannedEntry entry = entries[i];
            final _Deletion? deletion = entry.deletion;
            if (deletion != null) {
              deletions.add(deletion);
            }
            final _UpsertSetup? setup = entry.setup;
            if (setup == null) {
              continue;
            }
            try {
              token._check();
              final _Payload payload;
              if (setup.inlineText != null) {
                payload = _Payload.text(setup.inlineText!);
              } else {
                payload = await _readPayload(fullName, setup.source!, token);
              }
              transfers.add(_Transfer(
                from: setup.source?.path ?? entry.resultPath,
                to: entry.resultPath,
                payload: payload,
                mode: setup.source?.mode ?? _defaultMode,
                type: setup.source?.type ?? GhTreeEntryType.blob,
              ));
              _emit(onProgress, RepoFilePhase.reading, i + 1, total,
                  entry.resultPath);
            } catch (error) {
              readFailure = _describe(error);
              failedAt = i;
              readCancelled = error is _RepoFileCancelled;
              break;
            }
          }
          if (readFailure != null) {
            for (int i = cursor; i < end; i++) {
              failures[i] =
                  i == failedAt ? readFailure : 'aborted: 本批未提交（前序读取失败）';
            }
            stopped = true;
            cancelledStop = readCancelled;
            cursor = end;
            continue;
          }
          if (token.isCancelled) {
            cancelledStop = true;
            stopped = true;
            continue;
          }
          // ② 提交本块。
          _emit(
            onProgress,
            RepoFilePhase.uploading,
            cursor,
            total,
            transfers.isNotEmpty ? transfers.first.to : deletions.first.path,
          );
          try {
            final String sha = await _commitBatch(
              fullName,
              ref: ref,
              upserts: transfers,
              deletions: deletions,
              message: commitMessage,
              expectedHeadSha: chainSha,
              token: token,
            );
            chainSha = sha;
            commitSha = sha;
            _emit(
              onProgress,
              RepoFilePhase.committing,
              end,
              total,
              transfers.isNotEmpty ? transfers.last.to : deletions.last.path,
            );
          } catch (error) {
            cancelledStop = error is _RepoFileCancelled;
            final String described = _describe(error);
            for (int i = cursor; i < end; i++) {
              failures[i] = described;
            }
            stopped = true;
          }
          cursor = end;
        }
        _emit(onProgress, RepoFilePhase.done, total, total, '');
        final List<RepoFileItemResult> items = <RepoFileItemResult>[];
        for (int i = 0; i < total; i++) {
          final String? failure = failures[i];
          items.add(failure == null
              ? RepoFileItemResult.success(entries[i].resultPath)
              : RepoFileItemResult.failure(entries[i].resultPath, failure));
        }
        return RepoFileResult(
          ok: items.every((RepoFileItemResult item) => item.ok),
          items: items,
          commitSha: commitSha,
        );
      });

  /// 展开阶段的失败：失败操作给具体错误，其余操作如实标记未执行。
  RepoFileResult _expansionFailure(
    List<RepoFileBatchOp> ops,
    int failedIndex,
    List<_PlannedEntry> expanded,
    Object error,
  ) {
    final bool cancelled = error is _RepoFileCancelled;
    final List<RepoFileItemResult> items = <RepoFileItemResult>[];
    for (final _PlannedEntry entry in expanded) {
      items.add(RepoFileItemResult.failure(
        entry.resultPath,
        cancelled ? 'aborted: 操作已取消，本项未执行' : 'aborted: 批次校验未通过，本项未执行',
      ));
    }
    items.add(
      RepoFileItemResult.failure(ops[failedIndex].path, _describe(error)),
    );
    for (int k = failedIndex + 1; k < ops.length; k++) {
      items.add(RepoFileItemResult.failure(
        ops[k].path,
        cancelled ? 'aborted: 操作已取消，本项未执行' : 'aborted: 前序操作校验失败，本项未执行',
      ));
    }
    return RepoFileResult(ok: false, items: items);
  }

  /// 展开一条操作（全部只读：校验 / 探测 / 扫描；内容读取在提交阶段做）。
  Future<void> _expandOp(
    String fullName,
    String ref,
    int opIndex,
    RepoFileBatchOp op,
    List<_PlannedEntry> entries,
  ) async {
    switch (op.op) {
      case RepoFileOp.create:
        entries.add(await _expandCreate(fullName, ref, opIndex, op));
        return;
      case RepoFileOp.delete:
        entries.addAll(await _expandDelete(fullName, ref, opIndex, op));
        return;
      case RepoFileOp.rename:
      case RepoFileOp.copy:
        entries.addAll(await _expandMove(
          fullName,
          ref,
          opIndex,
          op,
          copy: op.op == RepoFileOp.copy,
        ));
        return;
      case RepoFileOp.batchDelete:
      case RepoFileOp.batchMove:
      case RepoFileOp.batchCopy:
        throw const _RepoFileFailure(
          'invalidOp',
          '批量类别不能作为组合操作的单条指令',
        );
    }
  }

  Future<_PlannedEntry> _expandCreate(
    String fullName,
    String ref,
    int opIndex,
    RepoFileBatchOp op,
  ) async {
    final String? content = op.content;
    if (content == null) {
      throw const _RepoFileFailure('invalidOp', 'create 操作缺少 content');
    }
    final String? invalid = RepoFilePaths.validateFilePath(op.path);
    if (invalid != null) {
      throw _RepoFileFailure('invalidPath', invalid);
    }
    final String target = RepoFilePaths.clean(op.path);
    final String? empty = RepoFilePaths.validateContent(target, content);
    if (empty != null) {
      throw _RepoFileFailure('emptyContent', empty);
    }
    final _Probe probe = await _probePath(fullName, ref, target);
    if (probe.found) {
      throw _RepoFileFailure(
        probe.isDirectory ? 'isDirectory' : 'exists',
        '目标已存在：$target（create 不覆盖既有文件）',
      );
    }
    return _PlannedEntry(
      opIndex: opIndex,
      resultPath: target,
      setup: _UpsertSetup.content(content),
    );
  }

  Future<List<_PlannedEntry>> _expandDelete(
    String fullName,
    String ref,
    int opIndex,
    RepoFileBatchOp op,
  ) async {
    final String source = RepoFilePaths.clean(op.path);
    if (source.isEmpty) {
      throw const _RepoFileFailure('invalidPath', '删除路径不能为空');
    }
    if (op.isDirectory) {
      final List<_Source> sources = await _scanDirectory(fullName, ref, source);
      if (sources.isEmpty) {
        final _Probe probe = await _probePath(fullName, ref, source);
        throw _RepoFileFailure(
          probe.isFile ? 'notDirectory' : 'notFound',
          probe.isFile ? '目标不是目录：$source' : '目录不存在或没有任何文件：$source',
        );
      }
      return <_PlannedEntry>[
        for (final _Source item in sources)
          _PlannedEntry(
            opIndex: opIndex,
            resultPath: item.path,
            deletion: _deletionFor(item.path, item.mode, item.type),
          ),
      ];
    }
    final _Probe probe = await _probePath(fullName, ref, source);
    if (probe.isEmpty) {
      throw _RepoFileFailure('notFound', '目标不存在：$source');
    }
    if (probe.isDirectory) {
      throw _RepoFileFailure(
        'isDirectory',
        '目标为目录：请以 isDirectory: true 递归删除',
      );
    }
    final _Source item = _sourceOfContent(source, probe.content!);
    return <_PlannedEntry>[
      _PlannedEntry(
        opIndex: opIndex,
        resultPath: source,
        deletion: _deletionFor(item.path, item.mode, item.type),
      ),
    ];
  }

  Future<List<_PlannedEntry>> _expandMove(
    String fullName,
    String ref,
    int opIndex,
    RepoFileBatchOp op, {
    required bool copy,
  }) async {
    final String? rawTarget = op.newPath;
    if (rawTarget == null) {
      throw const _RepoFileFailure('invalidOp', 'rename/copy 操作缺少 newPath');
    }
    final String source = RepoFilePaths.clean(op.path);
    final String target = RepoFilePaths.clean(rawTarget);
    if (source.isEmpty) {
      throw const _RepoFileFailure('invalidPath', '源路径不能为空');
    }
    if (target.isEmpty) {
      throw const _RepoFileFailure('invalidPath', '目标路径不能为空');
    }
    if (source == target) {
      throw const _RepoFileFailure('invalidPath', '目标路径与源路径相同');
    }
    if (!copy && target.startsWith('$source/')) {
      throw _RepoFileFailure('invalidPath', '不能把目录移动到自身内部（$target）');
    }
    final _Probe probe = await _probePath(fullName, ref, source);
    if (probe.isEmpty) {
      throw _RepoFileFailure('notFound', '源路径不存在：$source');
    }

    // 单文件。
    if (probe.isFile) {
      final String? invalid = RepoFilePaths.validateFilePath(target);
      if (invalid != null) {
        throw _RepoFileFailure('invalidPath', invalid);
      }
      await _ensureTargetFree(fullName, ref, target);
      final _Source item = _sourceOfContent(source, probe.content!);
      return <_PlannedEntry>[
        _PlannedEntry(
          opIndex: opIndex,
          resultPath: target,
          setup: _UpsertSetup.source(item),
          deletion: copy ? null : _deletionFor(item.path, item.mode, item.type),
        ),
      ];
    }

    // 目录：tree 前缀过滤 → 派生目标路径并逐一校验。
    final String? invalidDir = RepoFilePaths.validateDirectoryPath(target);
    if (invalidDir != null) {
      throw _RepoFileFailure('invalidPath', invalidDir);
    }
    await _ensureTargetFree(fullName, ref, target);
    final List<_Source> sources = await _scanDirectory(fullName, ref, source);
    if (sources.isEmpty) {
      throw _RepoFileFailure('notFound', '目录不存在或没有任何文件：$source');
    }
    final String prefix = '$source/';
    final List<_PlannedEntry> entries = <_PlannedEntry>[];
    for (final _Source item in sources) {
      final String derived = '$target/${item.path.substring(prefix.length)}';
      final String? problem = RepoFilePaths.validateDerivedPath(derived);
      if (problem != null) {
        throw _RepoFileFailure(
          'invalidPath',
          '派生目标路径不合法（$derived：$problem）',
        );
      }
      entries.add(_PlannedEntry(
        opIndex: opIndex,
        resultPath: derived,
        setup: _UpsertSetup.source(item),
        deletion: copy ? null : _deletionFor(item.path, item.mode, item.type),
      ));
    }
    return entries;
  }

  /// 目标路径必须不存在（**拒绝静默覆盖**：误覆盖是本应用的致命错误类别）。
  Future<void> _ensureTargetFree(
    String fullName,
    String ref,
    String target,
  ) async {
    final _Probe probe = await _probePath(fullName, ref, target);
    if (probe.found) {
      throw _RepoFileFailure(
        'exists',
        '目标已存在：$target（为避免误覆盖，请先删除目标）',
      );
    }
  }

  // ───────────────────────── 基础设施 ─────────────────────────

  /// 统一收口：令牌绑定 + 结果日志 + **写后失效读缓存** + 永不抛。
  ///
  /// 缓存失效收在这里而不是分散到各写方法：`body` 返回时，任何一次提交
  /// （Contents 单文件写入或 Git Data 批量提交）都已落定——只要有条目
  /// 真的写成功，本地只读缓存就已过期，读路径随后必须回源。
  Future<RepoFileResult> _run(
    String label,
    String fallbackPath,
    RepoFileCancelToken? external,
    Future<RepoFileResult> Function(RepoFileCancelToken token) body,
  ) async {
    final RepoFileCancelToken token = _begin(external);
    try {
      final RepoFileResult result = await body(token);
      if (result.succeeded > 0) {
        try {
          await api.invalidateReadCache();
        } catch (error) {
          // 缓存失效失败不改变"写入已成功"的事实，也不静默：记诊断。
          _diagnostics?.warn('RF', '写后失效读缓存失败：$error', code: 'OGL-RF-106');
        }
      }
      _logResult(label, result);
      return result;
    } catch (error) {
      _diagnostics?.warn('RF', '$label 异常：$error', code: 'OGL-RF-103');
      return _singleFailure(fallbackPath, error);
    } finally {
      _end(token);
    }
  }

  RepoFileCancelToken _begin(RepoFileCancelToken? external) {
    final RepoFileCancelToken token = external ?? RepoFileCancelToken();
    _active = token;
    return token;
  }

  void _end(RepoFileCancelToken token) {
    if (identical(_active, token)) {
      _active = null;
    }
  }

  void _logResult(String label, RepoFileResult result) {
    final KernelDiagnostics? diagnostics = _diagnostics;
    if (diagnostics == null) {
      return;
    }
    final Map<String, Object?> data = <String, Object?>{
      'total': result.total,
      'failed': result.failed,
      if (result.commitSha != null) 'commit': shortSha(result.commitSha),
    };
    if (result.ok) {
      diagnostics.info('RF', '$label 完成：${result.summary}',
          code: 'OGL-RF-001', data: data);
    } else {
      diagnostics.warn('RF', '$label 结束：${result.summary}',
          code: 'OGL-RF-002', data: data);
    }
  }

  void _emit(
    void Function(RepoFileProgress)? sink,
    RepoFilePhase phase,
    int current,
    int total,
    String currentPath,
  ) {
    if (sink == null) {
      return;
    }
    try {
      sink(RepoFileProgress(
        phase: phase,
        current: current,
        total: total,
        currentPath: currentPath,
      ));
    } catch (error) {
      // 进度回调是消费方代码：抛异常不能中断操作，但**不允许静默**。
      _diagnostics?.warn('RF', '进度回调异常（已忽略并继续）：$error', code: 'OGL-RF-105');
    }
  }

  String? _checkRepo(String fullName) {
    final String name = fullName.trim();
    if (name.isEmpty) {
      return '仓库全名不能为空';
    }
    if (!name.contains('/')) {
      return '仓库全名应形如 owner/name：$name';
    }
    if (RegExp(r'\s').hasMatch(name)) {
      return '仓库全名不能包含空白字符：$name';
    }
    return null;
  }

  /// 解析分支：显式给了就用；为空则取仓库**实际**默认分支（**绝不猜** `main`）。
  Future<String> _resolveRef(String fullName, String branch) async {
    final String given = branch.trim();
    if (given.isNotEmpty) {
      return given;
    }
    final Map<String, dynamic>? object =
        await client.getObject('/repos/$fullName');
    final String fallback =
        GhJson.str(object ?? const <String, dynamic>{}, 'default_branch');
    if (fallback.isEmpty) {
      throw GhAuthException(
        '无法确定 $fullName 的默认分支（仓库详情未返回 default_branch），请显式指定分支',
      );
    }
    return fallback;
  }

  /// 校验分支顶端等于期望基线（不等 → [RemoteConflictException]）。
  Future<void> _assertHead(
    String fullName,
    String ref,
    String expectedHeadSha,
  ) async {
    final String head = await _headShaOf(fullName, ref);
    if (head.isEmpty) {
      throw GhAuthException('无法确定分支 $ref 的顶端提交');
    }
    if (head != expectedHeadSha) {
      throw RemoteConflictException(
        statusCode: 409,
        currentSha: head,
        message: '分支已前进（期望 ${shortSha(expectedHeadSha)}，远端 ${shortSha(head)}）',
      );
    }
  }

  /// 路径探测：一次请求区分**文件 / 目录 / 不存在**。
  ///
  /// Contents API 对文件返回对象、对目录返回数组——据此区分，天然无歧义
  /// （`GhApi.content` 在未命中缓存时对目录返回 `null`，不能用于类型判定）。
  Future<_Probe> _probePath(String fullName, String ref, String path) async {
    try {
      final GhResponse response = await client.send(GhRequest(
        path: '/repos/$fullName/contents/${RepoFilePaths.encodeForUrl(path)}',
        query: <String, String>{'ref': ref},
        label: 'GET contents/$path',
      ));
      final Map<String, dynamic>? object = response.jsonObject;
      if (object != null) {
        return _Probe.file(GhContent.fromJson(object));
      }
      return _Probe.directory();
    } on GhNotFoundException {
      return _Probe.missing();
    } on GhAuthException catch (error) {
      // 空仓库（409）等情形如实当作"没有"（与 GhApi._isAbsentStatus 同款）。
      if (error.statusCode == 404 ||
          error.statusCode == 409 ||
          error.statusCode == 422) {
        return _Probe.missing();
      }
      rethrow;
    }
  }

  /// 目录树前缀展开：拿全部文件（blob + 子模块 gitlink），排序、限流、防截断。
  Future<List<_Source>> _scanDirectory(
    String fullName,
    String ref,
    String directory,
  ) async {
    final GhTree tree = await api.tree(fullName, branch: ref, recursive: true);
    if (tree.truncated) {
      throw const _RepoFileFailure(
        'treeTruncated',
        '目录树被服务端截断（仓库过大），拒绝执行不完整的批量操作——请缩小操作范围',
      );
    }
    final String prefix = '$directory/';
    final List<_Source> sources = <_Source>[];
    for (final GhTreeEntry entry in tree.entries) {
      if (!entry.path.startsWith(prefix)) {
        continue;
      }
      if (entry.type == GhTreeEntryType.tree) {
        continue; // 目录条目本身由文件路径隐式表达，无需搬运。
      }
      if (entry.type == GhTreeEntryType.unknown) {
        throw _RepoFileFailure(
          'unsupported',
          '目录中存在未知类型条目（${entry.path}），拒绝执行以免搬运不完整',
        );
      }
      sources.add(_sourceOfEntry(entry));
    }
    sources.sort((_Source a, _Source b) => a.path.compareTo(b.path));
    if (sources.length > maxFilesPerOp) {
      throw _RepoFileFailure(
        'tooManyFiles',
        '目录下共 ${sources.length} 个文件，超过单次操作上限（$maxFilesPerOp）——请分批执行',
      );
    }
    return sources;
  }

  /// 读取文件载荷（文本 / 字节 / 引用）。
  ///
  /// 决策顺序（**字节精确是底线**）：
  /// 1. 符号链接 / 子模块 → 按 sha 引用搬运（内容重传会改变语义）；
  /// 2. > 100 MB（Blobs 单对象上限）→ 按 sha 引用搬运（同仓库零成本）；
  /// 3. 其余读 base64（Contents 内联或 Blobs API，**不限 1 MB**）；
  /// 4. 文本类做**严格 UTF-8 复核**：通过才走文本管线（可复用 `commitFiles`），
  ///    失败自动改走字节搬运（base64 原样透传）。
  Future<_Payload> _readPayload(
    String fullName,
    _Source source,
    RepoFileCancelToken token,
  ) async {
    token._check();
    if (source.type == GhTreeEntryType.commit || source.mode == _symlinkMode) {
      if (source.sha.isEmpty) {
        throw _RepoFileFailure('failed', '条目缺少 sha，无法按引用搬运：${source.path}');
      }
      return _Payload.reference(source.sha);
    }
    if (source.size > _contentTransferLimit && source.sha.isNotEmpty) {
      return _Payload.reference(source.sha);
    }
    String? base64Text = source.inlineBase64;
    if (base64Text == null || base64Text.isEmpty) {
      if (source.sha.isEmpty) {
        throw _RepoFileFailure('failed', '文件缺少指纹（sha），无法读取内容：${source.path}');
      }
      base64Text = await _blobBase64(fullName, source.sha);
    }
    if (base64Text.isEmpty) {
      if (source.size == 0) {
        return const _Payload.text('');
      }
      throw _RepoFileFailure(
        'failed',
        '读取到空内容（sha=${shortSha(source.sha)}）：${source.path}',
      );
    }
    final List<int>? bytes = _tryDecodeBase64(base64Text);
    if (bytes == null) {
      throw _RepoFileFailure('failed', '内容 base64 无法解码：${source.path}');
    }
    if (!RepoFilePaths.isBinaryPath(source.path)) {
      try {
        return _Payload.text(utf8.decode(bytes));
      } on FormatException {
        // 非合法 UTF-8：落回字节搬运，绝不有损转码。
      }
    }
    return _Payload.bytes(base64Text);
  }

  /// 读取一个 blob 的 base64 内容（按 sha，**无 1 MB 红线**、无路径编码问题）。
  Future<String> _blobBase64(String fullName, String sha) async {
    final GhResponse response = await client.send(GhRequest(
      path: '/repos/$fullName/git/blobs/$sha',
      label: 'GET blobs/$sha',
    ));
    final Map<String, dynamic> object =
        response.jsonObject ?? const <String, dynamic>{};
    return _normalizeBase64(GhJson.str(object, 'content'));
  }

  static List<int>? _tryDecodeBase64(String text) {
    try {
      return base64.decode(text);
    } on FormatException {
      return null;
    }
  }

  /// 去除 base64 里的空白（GitHub 会按 60 字符换行）。
  static String _normalizeBase64(String raw) =>
      raw.replaceAll(RegExp(r'\s'), '');

  // ───────────────────────── 提交管线 ─────────────────────────

  /// 一批提交：纯文本且全为常规模式 → 复用 `GhApi.commitFiles`；
  /// 否则走 [_commitRaw]（base64 原样创建 blob / sha 引用，字节精确）。
  Future<String> _commitBatch(
    String fullName, {
    required String ref,
    required List<_Transfer> upserts,
    required List<_Deletion> deletions,
    required String message,
    String? expectedHeadSha,
    required RepoFileCancelToken token,
  }) async {
    final bool needsRaw = upserts.any(
            (_Transfer t) => t.payload.needsRaw || t.mode != _defaultMode) ||
        deletions.any((_Deletion d) => !d.isPlain);
    if (!needsRaw) {
      return api.commitFiles(
        fullName,
        branch: ref,
        upserts: <String, String>{
          for (final _Transfer t in upserts) t.to: t.payload.text!,
        },
        deletions: <String>[for (final _Deletion d in deletions) d.path],
        message: message,
        expectedHeadSha: expectedHeadSha,
      );
    }
    return _commitRaw(
      fullName,
      ref: ref,
      upserts: upserts,
      deletions: deletions,
      message: message,
      expectedHeadSha: expectedHeadSha,
      token: token,
    );
  }

  /// 原始提交管线（**镜像 `GhApi.commitFiles` 的 blob → tree → commit → ref**）。
  ///
  /// 与 `commitFiles` 的差异（也是存在的理由）：
  /// - blob 以 **base64 原样**创建（`encoding: base64`）——字节精确、无 1 MB 限制；
  /// - 支持 **sha 引用条目**（符号链接 / 子模块 / >100 MB 文件零拷贝搬运）；
  /// - 逐条目保留 mode（可执行位 100755 不丢）。
  ///
  /// 一旦 `GhApi.commitFiles` 支持 base64 载荷与引用条目，本方法应删除并改调它。
  Future<String> _commitRaw(
    String fullName, {
    required String ref,
    required List<_Transfer> upserts,
    required List<_Deletion> deletions,
    required String message,
    String? expectedHeadSha,
    required RepoFileCancelToken token,
  }) async {
    // ① 先校验基线、先读基线树，**再**创建任何对象（与 commitFiles 同款顺序：
    //    中途失败时远端最多留下会被 GC 的孤儿 blob，而不是半截提交）。
    final String headSha = await _headShaOf(fullName, ref);
    if (headSha.isEmpty) {
      throw GhAuthException('无法确定分支 $ref 的顶端提交');
    }
    if (expectedHeadSha != null && expectedHeadSha != headSha) {
      throw RemoteConflictException(
        statusCode: 409,
        currentSha: headSha,
        message: '分支已前进，拒绝批量提交',
      );
    }
    final String baseTree = await _treeShaOfCommit(fullName, headSha);

    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
    for (final _Transfer t in upserts) {
      // ★ 每个 blob 上传前一个取消检查点（已发出的请求不打断）。
      token._check();
      final String? refSha = t.payload.refSha;
      if (refSha != null) {
        entries.add(<String, Object?>{
          'path': t.to,
          'mode': t.mode,
          'type': t.type == GhTreeEntryType.commit ? 'commit' : 'blob',
          'sha': refSha,
        });
        continue;
      }
      final String base64Content =
          t.payload.base64 ?? base64Encode(utf8.encode(t.payload.text!));
      final GhResponse blob = await client.send(GhRequest(
        path: '/repos/$fullName/git/blobs',
        method: NetMethod.post,
        body: <String, Object?>{
          'content': base64Content,
          'encoding': 'base64',
        },
        label: 'POST blobs(${t.to})',
      ));
      final String blobSha = GhJson.str(
        blob.jsonObject ?? const <String, dynamic>{},
        'sha',
      );
      entries.add(<String, Object?>{
        'path': t.to,
        'mode': t.mode,
        'type': 'blob',
        'sha': blobSha,
      });
    }
    for (final _Deletion d in deletions) {
      entries.add(<String, Object?>{
        'path': d.path,
        'mode': d.mode,
        'type': d.type,
        'sha': null,
      });
    }
    if (entries.isEmpty) {
      throw ArgumentError('批量提交内容为空（upserts 与 deletions 至少需要一个）');
    }

    final GhResponse tree = await client.send(GhRequest(
      path: '/repos/$fullName/git/trees',
      method: NetMethod.post,
      body: <String, Object?>{'base_tree': baseTree, 'tree': entries},
      label: 'POST trees',
    ));
    final String treeSha =
        GhJson.str(tree.jsonObject ?? const <String, dynamic>{}, 'sha');

    final GhResponse commit = await client.send(GhRequest(
      path: '/repos/$fullName/git/commits',
      method: NetMethod.post,
      body: <String, Object?>{
        'message': message,
        'tree': treeSha,
        'parents': <String>[headSha],
      },
      label: 'POST commits',
    ));
    final String commitSha =
        GhJson.str(commit.jsonObject ?? const <String, dynamic>{}, 'sha');

    await client.send(GhRequest(
      path: '/repos/$fullName/git/refs/heads/$ref',
      method: NetMethod.patch,
      body: <String, Object?>{'sha': commitSha, 'force': false},
      label: 'PATCH refs/heads/$ref',
      conflictsAsRemoteConflict: true,
    ));
    return commitSha;
  }

  Future<String> _headShaOf(String fullName, String ref) async {
    try {
      final Map<String, dynamic>? object =
          await client.getObject('/repos/$fullName/git/ref/heads/$ref');
      final Object? target = object?['object'];
      if (target is Map) {
        return GhJson.str(Map<String, dynamic>.from(target), 'sha');
      }
    } on GhNotFoundException {
      return '';
    }
    return '';
  }

  Future<String> _treeShaOfCommit(String fullName, String commitSha) async {
    final Map<String, dynamic>? object =
        await client.getObject('/repos/$fullName/git/commits/$commitSha');
    final Object? tree = object?['tree'];
    if (tree is Map) {
      return GhJson.str(Map<String, dynamic>.from(tree), 'sha');
    }
    return '';
  }

  // ───────────────────────── 小型辅助 ─────────────────────────

  /// 生成删除条目：常规文件沿用 `100644`（与 `commitFiles` 的 deletion
  /// 表示保持一致）；符号链接 / 子模块保留真实模式与类型（否则 gitlink 删不掉）。
  _Deletion _deletionFor(String path, String mode, GhTreeEntryType type) {
    if (type == GhTreeEntryType.commit) {
      return _Deletion(path: path, mode: _submoduleMode, type: 'commit');
    }
    if (mode == _symlinkMode) {
      return _Deletion(path: path, mode: _symlinkMode, type: 'blob');
    }
    return _Deletion(path: path, mode: _defaultMode, type: 'blob');
  }

  /// 默认提交信息（单操作带具体路径；组合操作用条数摘要）。
  String _defaultBatchMessage(List<RepoFileBatchOp> ops, int fileCount) {
    if (ops.length == 1) {
      final RepoFileBatchOp op = ops.first;
      final String from = RepoFilePaths.clean(op.path);
      final String to = RepoFilePaths.clean(op.newPath ?? '');
      switch (op.op) {
        case RepoFileOp.create:
          return 'create: $from';
        case RepoFileOp.delete:
          return fileCount > 1
              ? 'delete: $from/（$fileCount 个文件）'
              : 'delete: $from';
        case RepoFileOp.rename:
          return fileCount > 1
              ? 'rename: $from/ → $to/（$fileCount 个文件）'
              : 'rename: $from → $to';
        case RepoFileOp.copy:
          return fileCount > 1
              ? 'copy: $from/ → $to/（$fileCount 个文件）'
              : 'copy: $from → $to';
        case RepoFileOp.batchDelete:
        case RepoFileOp.batchMove:
        case RepoFileOp.batchCopy:
          break;
      }
    }
    return 'batch: ${ops.length} 项操作（$fileCount 个文件）';
  }

  RepoFileResult _singleFailure(String path, Object error) => RepoFileResult(
        ok: false,
        items: <RepoFileItemResult>[
          RepoFileItemResult.failure(path, _describe(error)),
        ],
      );

  /// 异常 → `code: message`（供逐项结果展示；**不吞类型信息**）。
  String _describe(Object error) {
    if (error is _RepoFileCancelled) {
      return 'cancelled: 操作已取消';
    }
    if (error is _RepoFileFailure) {
      return '${error.code}: ${error.message}';
    }
    if (error is RemoteConflictException) {
      final String detail = error.message ?? '远端已变化';
      return error.currentSha == null
          ? 'conflict: $detail'
          : 'conflict: $detail（远端版本 ${shortSha(error.currentSha)}）';
    }
    if (error is GhRateLimitException) {
      final DateTime? resetAt = error.resetAt;
      final String when =
          resetAt == null ? '' : '（约 ${_minutesUntil(resetAt)} 分钟后恢复）';
      return 'rateLimit: ${error.message}$when';
    }
    if (error is GhAuthException) {
      return 'auth: ${error.message}';
    }
    if (error is GhNotFoundException) {
      return 'notFound: ${error.path} 不存在或无权访问';
    }
    return 'failed: $error';
  }

  static int _minutesUntil(DateTime time) {
    final int minutes = time.difference(DateTime.now()).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// 树条目 → 源信息（mode 从 raw 里取，含符号链接 / 子模块的真实模式）。
  _Source _sourceOfEntry(GhTreeEntry entry) => _Source(
        path: entry.path,
        sha: entry.sha,
        size: entry.size,
        mode: GhJson.str(entry.raw, 'mode', fallback: _defaultMode),
        type: entry.type,
        inlineBase64: null,
      );

  /// Contents API 条目 → 源信息（顺带拿到 ≤1 MB 的内联 base64）。
  ///
  /// Contents API 不返回文件模式：普通文件按 `100644` 处理（**已知限制**：
  /// 单文件重命名不保留可执行位，Contents API 不暴露它）；`type` 为
  /// `symlink` / `submodule` 时按模式推断并走 sha 引用搬运（见 [_readPayload]）。
  _Source _sourceOfContent(String requestedPath, GhContent content) {
    final String type = GhJson.str(content.raw, 'type', fallback: 'file');
    String mode = _defaultMode;
    GhTreeEntryType entryType = GhTreeEntryType.blob;
    if (type == 'symlink') {
      mode = _symlinkMode;
    } else if (type == 'submodule') {
      mode = _submoduleMode;
      entryType = GhTreeEntryType.commit;
    }
    return _Source(
      path: content.path.isNotEmpty ? content.path : requestedPath,
      sha: content.sha,
      size: content.size,
      mode: mode,
      type: entryType,
      inlineBase64: _normalizeBase64(GhJson.str(content.raw, 'content')),
    );
  }
}

// ───────────────────────── 内部数据类 ─────────────────────────

/// 待搬运文件的元信息（源视角）。
class _Source {
  const _Source({
    required this.path,
    required this.sha,
    required this.size,
    required this.mode,
    required this.type,
    this.inlineBase64,
  });

  /// 仓库内路径。
  final String path;

  /// blob 指纹（引用搬运 / Blobs API 读取用）。
  final String sha;

  /// 字节数（0 = 空文件或未知）。
  final int size;

  /// git 模式（`100644` / `100755` / `120000` / `160000`）。
  final String mode;

  /// 树条目类型（blob / commit）。
  final GhTreeEntryType type;

  /// Contents API 顺带返回的内联 base64（≤1 MB 才有；否则为 `null`）。
  final String? inlineBase64;
}

/// 待写入的载荷（三选一：文本 / 字节 / sha 引用）。
class _Payload {
  const _Payload.text(this.text)
      : base64 = null,
        refSha = null;

  const _Payload.bytes(this.base64)
      : text = null,
        refSha = null;

  const _Payload.reference(this.refSha)
      : text = null,
        base64 = null;

  /// 文本内容（合法 UTF-8 才有）。
  final String? text;

  /// 原始字节的 base64（原样透传，字节精确）。
  final String? base64;

  /// 已有 blob 的 sha（零拷贝引用）。
  final String? refSha;

  /// 是否需要原始提交管线（`commitFiles` 只接受文本）。
  bool get needsRaw => base64 != null || refSha != null;
}

/// 一个 upsert（源 → 目标 + 载荷 + 模式 / 类型）。
class _Transfer {
  const _Transfer({
    required this.from,
    required this.to,
    required this.payload,
    required this.mode,
    required this.type,
  });

  /// 源路径（删除旧路径时用；create 等于目标路径）。
  final String from;

  /// 目标路径（树条目里的 path，**原始未编码**）。
  final String to;

  /// 载荷。
  final _Payload payload;

  /// git 模式（目标条目沿用源模式，可执行位不丢）。
  final String mode;

  /// 树条目类型（blob / commit）。
  final GhTreeEntryType type;
}

/// 一个 deletion（保留模式 / 类型以支持符号链接与子模块）。
class _Deletion {
  const _Deletion({required this.path, required this.mode, required this.type});

  /// 待删除路径。
  final String path;

  /// git 模式。
  final String mode;

  /// 树条目类型。
  final String type;

  /// 是否"常规文件删除"（可走 `commitFiles` 的 deletion 表示）。
  bool get isPlain => mode == RepoFileService._defaultMode && type == 'blob';
}

/// 路径探测结果（文件 / 目录 / 不存在）。
class _Probe {
  _Probe.file(this.content)
      : isDirectory = false,
        found = true;

  _Probe.directory()
      : content = null,
        isDirectory = true,
        found = true;

  _Probe.missing()
      : content = null,
        isDirectory = false,
        found = false;

  /// 命中文件时的内容条目（目录 / 不存在为 `null`）。
  final GhContent? content;

  /// 是否目录。
  final bool isDirectory;

  /// 是否存在。
  final bool found;

  /// 是否文件。
  bool get isFile => found && !isDirectory;

  /// 是否不存在。
  bool get isEmpty => !found;
}

/// 计划条目：一条待提交的 upsert / deletion（"移动对"两者皆有）。
class _PlannedEntry {
  const _PlannedEntry({
    required this.opIndex,
    required this.resultPath,
    this.setup,
    this.deletion,
  });

  /// 所属组合操作的序号（诊断 / 归因用）。
  final int opIndex;

  /// 逐项结果里展示的路径（rename / copy 为新路径，其余为操作路径）。
  final String resultPath;

  /// upsert 取数方式（无 upsert 时为 `null`，如纯删除）。
  final _UpsertSetup? setup;

  /// deletion（无删除时为 `null`，如 create / copy）。
  final _Deletion? deletion;
}

/// upsert 的取数方式：直接内容（create）或从源读取（rename / copy）。
class _UpsertSetup {
  const _UpsertSetup.source(this.source) : inlineText = null;

  const _UpsertSetup.content(this.inlineText) : source = null;

  /// 源信息（提交阶段按它读取载荷）。
  final _Source? source;

  /// 直接内容（create；字符串本身，不会在读取阶段被变更）。
  final String? inlineText;
}
