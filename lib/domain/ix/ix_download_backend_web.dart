/// L2 中枢级 · 下载后端的 **Web 实现**（把下载交给浏览器）。
///
/// ## 为什么是"交给浏览器"而不是"自己下载"
/// 浏览器**不给页面**：后台任务与队列（页面关掉就没了）、文件系统落盘
/// （页面不能把响应体写进用户的下载目录）、对下载过程的控制（暂停 / 继续 /
/// 取消）。页面能做的只有一件事：**把最终地址交给浏览器的下载器**
/// （`window.open` 一类导航），剩下的由浏览器负责。
///
/// ## 由此产生的能力限制（如实标注，不假装支持）
/// | 能力 | Web 上 |
/// |------|--------|
/// | 保存路径 | **没有本地路径**：`savePath` 放下载地址本身 |
/// | 进度 / 速度 | **拿不到**（字节不经过页面）→ `total` 保持 0 |
/// | 暂停 / 继续 | **不可用**（浏览器下载不受页面控制） |
/// | 多连接分片 | **不可用**（见 `range_download_web.dart`） |
/// | 读回成品做 sha256 校验 / 导出到 SAF | **不可用**（成品在浏览器下载目录） |
/// | 带 `Authorization` 头的下载 | **不可行**：浏览器会剥离/不允许页面设置
///   跨域鉴权头 → 如实报失败（不用"看似成功"糊过去） |
///
/// ## 状态语义
/// 触发成功即置 `completed`；触发失败（含"需要鉴权头"与"被弹窗拦截"）
/// 置 `failed` 并给出**可读的原因**——永远不置"下载中"，
/// 因为没有页面可观测的下载过程。
///
/// ## 错误文案的 i18n 约定
/// 本层不直接产用户可见文案（domain 层无 i18n 依赖）：失败原因以
/// **i18n 键名**（如 `downloadFailed.popupBlocked`）作为 `message` 上报，
/// 由展示层（`download_manager_page`）识别 `downloadFailed.` 前缀后翻译；
/// 识别不了的原样展示。
library;

import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'ix_download.dart';
import 'ix_download_error.dart';

/// 按平台创建下载后端（Web）。
IxDownloadBackend createDownloadBackend() => WebDownloadBackend();

/// Web 下载后端：交给浏览器下载。
class WebDownloadBackend implements IxDownloadBackend {
  final StreamController<IxDownloadEvent> _events =
      StreamController<IxDownloadEvent>.broadcast();

  @override
  Stream<IxDownloadEvent> get events => _events.stream;

  @override
  bool get canReadLocalFile => false;

  @override
  bool get supportsRanged => false;

  @override
  bool get supportsPauseResume => false;

  /// Web 上无落盘目录可裁决（下载不经页面）：**空操作**。
  ///
  /// 契约要求该 setter 存在（原生端由装配根注入 `OgLStorage.plan()` 的
  /// 结果）；Web 上没有任何"写到哪里"的分叉，实现为无害的空设置。
  @override
  set downloadDirProvider(Future<String?> Function()? provider) {}

  /// Web 上没有本地落盘路径：把**下载地址本身**作为 `savePath`（如实呈现，
  /// 不编造本地文件名）。展示层据此把"打开"按钮导向浏览器下载地址。
  @override
  Future<String> pathFor(IxDownloadSpec spec) async => spec.url;

  @override
  Future<void> enqueue(IxDownloadSpec spec) async {
    final String reasonKey = await _handOffToBrowser(spec);
    // 用微任务派发终态：`enqueue` 返回之前，调用方（管理器）还没把快照登记好，
    // 同步发事件会因查不到 id 而被丢弃。
    scheduleMicrotask(() {
      if (_events.isClosed) {
        return;
      }
      if (reasonKey.isEmpty) {
        _events.add(IxDownloadEvent.state(spec.id, IxDownloadStatus.completed));
      } else {
        _events.add(
          IxDownloadEvent.state(
            spec.id,
            IxDownloadStatus.failed,
            error: reasonKey,
          ),
        );
      }
    });
  }

  // ── 浏览器下载不可由页面控制：以下操作一律为空操作。
  //    管理器会先查 `supportsPauseResume`，用户看到的提示是"本平台不支持"，
  //    而不是一个按下去毫无反应、却显示"已暂停"的假按钮。

  @override
  Future<void> pause(String id) async {}

  @override
  Future<void> resume(String id) async {}

  @override
  Future<void> cancel(String id) async {}

  /// 已完成文件的大小 / 摘要 / 删除：
  ///
  /// Web 上**拿不到成品字节**（浏览器写进它自己的下载目录，页面不参与），
  /// 因此一律返回 `null` / 空操作——**不编造**。契约里的 `path` 参数在 Web 上
  /// 无意义（`savePath` 是下载地址），保留它是为了让两个平台的契约完全一致。
  @override
  Future<int?> completedSize(String id, {String? path}) async => null;

  @override
  Future<String?> fileSha256(String id, {String? path}) async => null;

  @override
  Future<void> deleteFile(String id, {String? path}) async {}

  @override
  void dispose() {
    _events.close();
  }

  /// 把下载地址交给浏览器；返回**失败原因键**（空串 = 已触发成功）。
  ///
  /// 返回的是 i18n 键（见文件头"错误文案的 i18n 约定"）：
  /// - `downloadFailed.authHeaderNotAllowed`：浏览器不允许页面设置跨域鉴权头；
  /// - `downloadFailed.popupBlocked`：触发了浏览器弹窗拦截；
  /// - `downloadFailed.browserLaunchFailed`：`launchUrl` 抛 / 返 false。
  Future<String> _handOffToBrowser(IxDownloadSpec spec) async {
    final Uri? uri = Uri.tryParse(spec.url);
    if (uri == null) {
      return 'downloadFailed.browserLaunchFailed';
    }
    final bool needsAuth = spec.headers.keys
        .any((String key) => key.toLowerCase() == 'authorization');
    if (needsAuth) {
      return 'downloadFailed.authHeaderNotAllowed';
    }
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return 'downloadFailed.popupBlocked';
      }
      return '';
    } catch (_) {
      return 'downloadFailed.browserLaunchFailed';
    }
  }
}

/// 供诊断使用：把错误键映射为结构化错误的工具（保留语义分类）。
///
/// 展示层不直接用；管理器收到 `error:` 字符串后会经
/// `_errorOfDescription` 归类（含 `downloadFailed.authHeaderNotAllowed`
/// → [IxDownloadErrorKind.needsAuth]）。
IxDownloadError webDownloadErrorOf(String key) {
  final IxDownloadErrorKind kind = key == 'downloadFailed.authHeaderNotAllowed'
      ? IxDownloadErrorKind.needsAuth
      : IxDownloadErrorKind.network;
  return IxDownloadError(kind, key, code: 'OGL-DL-501');
}
