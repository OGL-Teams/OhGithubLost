/// L3 展示级 · 全局错误呈现层：**错误捕获 + 弹窗/横幅抛出**。
///
/// ## 它在兜什么
/// 商业级应用的基本底线：**任何错误都不允许无声消失**。
/// 本文件把三类错误统一收口到"用户可见"：
/// 1. Flutter 框架异常（构建/布局/绘制）→ `critical` 弹窗；
/// 2. 平台/异步未捕获异常 → `critical` 弹窗；
/// 3. 业务层主动上报的告警（网络降级、磁盘清理失败等）→ 横幅。
///
/// ## 为什么是"中心 + 宿主"两级
/// - [OgLNoticeCenter] 是**单例**：任何层（包括没有 `BuildContext` 的
///   底座/中枢代码）都能上报，不依赖 UI 树；
/// - [OgLNoticeHost] 挂在 `MaterialApp.builder` 里：只有它持有
///   `Navigator` / `ScaffoldMessenger`，负责把通知真正"抛"到屏幕上。
///
/// 弹窗用 `AlertDialog`（阻塞式、必须被阅读——适用于异常）；
/// 普通告警用 `SnackBar`（不打断操作）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../kernel/boot/trust_warnings.dart';
import '../../kernel/diagnostics.dart';
import '../../kernel/log/og_l_log_file.dart';
import '../i18n/og_l_i18n.dart';
import 'system_notifier.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'shell', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 通知严重级别。
enum OgLNoticeSeverity {
  /// 提示（横幅展示）。
  info,

  /// 告警（横幅展示）。
  warning,

  /// 严重（**弹窗**展示，必须被用户看到）。
  critical,
}

/// 通知的**投递方式**（用户要求：用参数决定走哪些通道）。
///
/// **接线状态**：`delivery` 参数目前**尚未接线** —— 所有调用点都使用默认值
/// [auto]，没有任何调用方传 [inAppOnly] / [allChannels]。枚举与参数保留，
/// 供将来对"后台系统通知"做显式控制时逐个改调用点；在接线之前，行为等同
/// [auto]（critical 后台投系统通知、其余按级别展示）。
///
/// - [auto]：按严重级别自动决定（critical → 弹窗；其余 → 横幅）；
/// - [inAppOnly]：**只在应用内**提示（前台横幅 / 弹窗），不尝试系统通知；
/// - [allChannels]：**三种方式全用** —— 前台弹窗/横幅 + 同时投系统通知，
///   保证用户切到后台也能看到（如"下载完成""长时间任务结束"）。
enum OgLNoticeDelivery {
  /// 按级别自动。
  auto,

  /// 仅应用内。
  inAppOnly,

  /// 全部通道（应用内 + 系统通知）。
  allChannels,
}

/// 一条用户可见的通知。
class OgLNotice {
  /// 创建通知。
  const OgLNotice({
    required this.title,
    this.detail,
    this.severity = OgLNoticeSeverity.warning,
    this.delivery = OgLNoticeDelivery.auto,
  });

  /// 标题（一行说清发生了什么）。
  final String title;

  /// 详情（可为空；弹窗里可选文本复制）。
  final String? detail;

  /// 严重级别。
  final OgLNoticeSeverity severity;

  /// 投递方式。
  final OgLNoticeDelivery delivery;
}

/// 全局通知中心（单例）。
///
/// 线程模型：全部在 UI 隔离区（Flutter 主 isolate）内使用；
/// 队列有上限，防止"异常风暴"把内存打满（保留最早与最新的可读性折中：
/// 超限时丢弃最旧的低级别通知）。
class OgLNoticeCenter extends ChangeNotifier {
  OgLNoticeCenter._();

  /// 单例。
  static final OgLNoticeCenter instance = OgLNoticeCenter._();

  /// 队列上限（超过时**优先**丢弃最旧的 info/warning；
  /// 极端情况（队列里全是 critical）下丢弃最旧的一条——保证内存有界）。
  static const int maxPending = 50;

  final List<OgLNotice> _pending = <OgLNotice>[];
  final List<OgLNotice> _history = <OgLNotice>[];

  /// 历史通知（最新在前，供通知中心页展示）。
  List<OgLNotice> get history => List<OgLNotice>.unmodifiable(_history);

  /// 待展示队列（只读视图）。
  List<OgLNotice> get pending => List<OgLNotice>.unmodifiable(_pending);

  /// 上报一条通知。
  ///
  /// 去重：相同的 `title + detail` 已在队列里时不再重复入队
  /// （避免同一个异常每帧上报刷屏），**也不重复落盘**。
  ///
  /// [delivery]：投递方式；**当前所有调用点都走默认的 [OgLNoticeDelivery.auto]**
  /// （参数尚未接线，见该枚举的说明）。
  void report({
    required String title,
    String? detail,
    OgLNoticeSeverity severity = OgLNoticeSeverity.warning,
    OgLNoticeDelivery delivery = OgLNoticeDelivery.auto,
  }) {
    // 去重在前：相同的 `title + detail` 已在待展示队列里时，**直接返回** ——
    // 既不再入队，也不重复落盘。否则同一个异常每帧上报会把磁盘日志刷爆，
    // 而队列里其实只有一条（旧实现先落盘再去重，重复条目照样写盘）。
    for (final existing in _pending) {
      if (existing.title == title && existing.detail == detail) {
        return;
      }
    }
    // 落盘在后：走到这里的都是**新的**通知；它可能因为"正在弹窗"而延后
    // 展示，但绝不允许丢失（磁盘留痕）。
    OgLLogFile.line(
      _t('notification'),
      detail == null || detail.isEmpty ? title : '$title：$detail',
      level: severity == OgLNoticeSeverity.critical
          ? 'ERR'
          : severity == OgLNoticeSeverity.warning
              ? 'WARN'
              : 'INFO',
    );
    if (_pending.length >= maxPending) {
      final dropIndex = _pending.indexWhere(
        (OgLNotice n) => n.severity != OgLNoticeSeverity.critical,
      );
      _pending.removeAt(dropIndex == -1 ? 0 : dropIndex);
    }
    final notice = OgLNotice(
      title: title,
      detail: detail,
      severity: severity,
      delivery: delivery,
    );
    _pending.add(notice);
    _history.insert(0, notice);
    while (_history.length > 200) {
      _history.removeLast();
    }
    notifyListeners();
  }

  /// 取走最早的一条（宿主消费用）。
  OgLNotice? take() {
    if (_pending.isEmpty) {
      return null;
    }
    return _pending.removeAt(0);
  }

  /// 放回**队首**（后台暂存，回到前台时按原顺序补发）。
  ///
  /// 有意**不**触发 `notifyListeners`：否则会在宿主的 drain 里形成回环。
  void requeueFront(OgLNotice notice) {
    _pending.insert(0, notice);
  }

  /// 仅测试用：清空待展示与历史（避免用例之间互相污染）。
  @visibleForTesting
  void debugClear() {
    _pending.clear();
    _history.clear();
  }
}

/// 应用级日志环（surface 层）：记录用户操作与**原始错误**，供「关于页」展示。
///
/// 与内核日志（`KernelReport.logTail`）互补：
/// 内核管"启动与治理"，这里管"用户行为与网络/认证失败"。
class OgLAppLog extends ChangeNotifier {
  OgLAppLog._();

  /// 单例。
  static final OgLAppLog instance = OgLAppLog._();

  /// 条目上限（环形丢弃最旧）。
  static const int maxEntries = 2000;

  final List<OgLAppLogEntry> _entries = <OgLAppLogEntry>[];

  /// 通知合并（**微任务**，不引入计时器）。
  ///
  /// 批量写日志时不要逐条 notify —— 那会让通知中心整表重建；
  /// 用微任务把"同一事件循环内的连续写入"合并为一次通知：
  /// - **不延迟**：微任务在当前事件循环结束前执行，该看到的仍然看到；
  /// - **不留计时器**：遗留计时器在测试环境会被判为失败，也让退出更干净。
  ///
  /// 只合并"通知"，**数据仍然逐条立即入表**，不改变任何可见内容。
  bool _notifyScheduled = false;

  /// 全部条目（**最新在前**，方便直接看）。
  List<OgLAppLogEntry> get entries =>
      List<OgLAppLogEntry>.unmodifiable(_entries.reversed.toList());

  /// 追加一条。
  ///
  /// **同时写入磁盘**（`OgLLogFile`）：内存只负责"关于页里能翻"，
  /// 磁盘负责"进程死了也还在"。
  void add(
    String area,
    String message, {
    OgLNoticeSeverity severity = OgLNoticeSeverity.info,
    String? logLevel,
  }) {
    _entries.add(OgLAppLogEntry(
      at: DateTime.now(),
      area: area,
      message: message,
      severity: severity,
    ));
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    _notifyCoalesced();
    OgLLogFile.line(
      area,
      message,
      level: logLevel ??
          (severity == OgLNoticeSeverity.critical
              ? 'ERR'
              : severity == OgLNoticeSeverity.warning
                  ? 'WARN'
                  : 'INFO'),
    );
  }

  /// 合并后的通知（同一事件循环内只通知一次）。
  void _notifyCoalesced() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// 立即通知（已读状态等"用户刚点过"的操作，不该延迟）。
  void notifyNow() => notifyListeners();

  /// 记录**成功的结果**（用户明确要求：不要只记错误）。
  ///
  /// 5.0：**不再往文案里塞 `✔` / `▶` 这类符号字形**——它们在 Android 上会被
  /// 当成 emoji 呈现（不同字体大小不一致 → 用户说的“emoji 撕裂”）。
  /// 现在的约定：**结构化信息靠 `level`，可见性靠图标**，正文保持纯文本。
  /// 例：`result('仓库', '拉取议题', '30 条')` → 落盘 `[INFO] [仓库] 拉取议题：30 条`。
  void result(String area, String what, [String? detail]) {
    final String suffix = (detail == null || detail.isEmpty) ? '' : '：$detail';
    add(area, '$what$suffix');
  }

  /// 记录**一个步骤的开始**（与 [result] 配对，形成"开始→结果"两行）。
  ///
  /// 用独立的 `STEP` 级别区分"开始"与"结果"，而不是在正文里加 `▶`。
  void step(String area, String what) {
    add(area, what, logLevel: 'STEP');
  }

  // ───────────────────────── 已读状态（通知中心）─────────────────────────

  /// 已读条目的稳定标识集合。
  final Set<String> _readIds = <String>{};

  /// 条目稳定标识（时间戳 + 区域 + 正文）。
  static String _idOf(OgLAppLogEntry entry) =>
      '${entry.at.microsecondsSinceEpoch}|${entry.area}|${entry.message}';

  /// 是否已读。
  bool isRead(OgLAppLogEntry entry) => _readIds.contains(_idOf(entry));

  /// 未读条数（通知中心角标 / 标题用）。
  int get unreadCount =>
      _entries.where((OgLAppLogEntry e) => !_readIds.contains(_idOf(e))).length;

  /// 标记单条已读。
  void markRead(OgLAppLogEntry entry) {
    if (_readIds.add(_idOf(entry))) {
      notifyListeners();
    }
  }

  /// 全部标记已读。
  void markAllRead() {
    var changed = false;
    for (final OgLAppLogEntry entry in _entries) {
      changed = _readIds.add(_idOf(entry)) || changed;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// 清空全部条目与已读状态（"重置通知中心"；磁盘日志不受影响）。
  void clear() {
    if (_entries.isEmpty && _readIds.isEmpty) {
      return;
    }
    _entries.clear();
    _readIds.clear();
    notifyListeners();
  }
}

/// 一条应用日志。
class OgLAppLogEntry {
  /// 创建条目。
  const OgLAppLogEntry({
    required this.at,
    required this.area,
    required this.message,
    required this.severity,
  });

  /// 时间。
  final DateTime at;

  /// 区域（认证 / 仓库 / …）。
  final String area;

  /// 正文（含原始异常与堆栈）。
  final String message;

  /// 级别。
  final OgLNoticeSeverity severity;

  /// 展示格式：`[HH:mm:ss][区域] 正文`。
  String toDisplay() {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    final s = at.second.toString().padLeft(2, '0');
    return '[$h:$m:$s][$area] $message';
  }
}

/// 宿主：把通知中心里的条目渲染成弹窗 / 横幅。
///
/// 挂在 `MaterialApp.builder` —— 这样**整棵应用树**里的错误都能抛到这里。
///
/// **为什么需要 [navigatorKey]**：`builder` 层的 context 位于 Navigator
/// **之上**（Navigator 是 builder 的 child），`showDialog` 从该 context
/// 向上查找 Navigator 会直接报错。因此 critical 弹窗必须借应用根
/// Navigator 的 context 来完成；未提供（或尚未就绪）时降级为横幅，绝不静默。
class OgLNoticeHost extends StatefulWidget {
  /// 创建宿主。
  const OgLNoticeHost({
    required this.child,
    this.navigatorKey,
    super.key,
  });

  /// 被包裹的应用内容。
  final Widget child;

  /// 应用根 Navigator 的 key（可为 `null`：此时 critical 降级为横幅）。
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<OgLNoticeHost> createState() => _OgLNoticeHostState();
}

class _OgLNoticeHostState extends State<OgLNoticeHost>
    with WidgetsBindingObserver {
  bool _showing = false;

  /// 应用是否在前台（后台时**不弹应用内提示**——它们会丢失或异常）。
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    OgLNoticeCenter.instance.addListener(_drain);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OgLNoticeCenter.instance.removeListener(_drain);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool nowForeground = state == AppLifecycleState.resumed;
    if (nowForeground == _foreground) {
      return;
    }
    _foreground = nowForeground;
    // 回到前台：把后台期间积压的通知补发出来（绝不静默丢弃）。
    if (nowForeground) {
      _drain();
    }
  }

  void _drain() {
    if (!mounted || _showing) {
      return;
    }
    final notice = OgLNoticeCenter.instance.take();
    if (notice == null) {
      return;
    }
    if (!_foreground) {
      // 后台：应用内弹窗/横幅无法呈现。走**系统通道**（`allChannels` 必须；
      // `auto` 的 critical 也不能丢，因此同样投系统通知），其余保持排队，
      // 等回前台补发。
      if (notice.delivery == OgLNoticeDelivery.allChannels ||
          notice.severity == OgLNoticeSeverity.critical) {
        _emitSystemNotice(notice);
      } else {
        // 放回队首，回前台再展示（保持顺序）。
        OgLNoticeCenter.instance.requeueFront(notice);
      }
      return;
    }
    if (notice.delivery == OgLNoticeDelivery.allChannels) {
      // 前台也要求"三通道全用"：应用内提示的同时补一条系统通知。
      _emitSystemNotice(notice);
    }
    _showing = true;
    if (notice.severity == OgLNoticeSeverity.critical) {
      _presentCritical(notice);
    } else {
      _presentAmbient(notice);
    }
  }

  /// 系统通知通道（后台 / `allChannels` 时使用）。
  ///
  /// - 真正投递：`OgLSystemNotifier`（Android / Windows / Linux / macOS / iOS）；
  /// - 同时**落盘 + 记入应用日志**，即便系统通道不可用也不会丢消息；
  /// - 回到前台后，[_drain] 仍会把排队中的应用内提示补发出来。
  void _emitSystemNotice(OgLNotice notice) {
    final String text = notice.detail == null || notice.detail!.isEmpty
        ? notice.title
        : '${notice.title}：${notice.detail}';
    OgLLogFile.line(
      _t('notification'),
      _t('systemChannel', {'text': text}),
      level: notice.severity == OgLNoticeSeverity.critical ? 'ERR' : 'WARN',
    );
    OgLAppLog.instance.add(
      _t('notification'),
      _t('systemChannel', {'text': text}),
      severity: notice.severity,
    );
    unawaited(OgLSystemNotifier.instance.show(
      title: notice.title,
      body: notice.detail,
    ));
  }

  /// 严重：弹窗（必须被阅读）。
  ///
  /// 弹窗必须借**应用根 Navigator** 的 context——宿主自身所在的 `builder`
  /// 层在 Navigator 之上，直接就地 `showDialog` 会抛
  /// "does not include a Navigator"。根 Navigator 尚未就绪时
  /// 降级为横幅（仍然可见）并留盘，绝不静默。
  void _presentCritical(OgLNotice notice) {
    final BuildContext? navContext = widget.navigatorKey?.currentContext;
    if (navContext == null) {
      OgLLogFile.line(
        _t('notification'),
        '根 Navigator 未就绪，critical 降级为横幅：${notice.title}',
        level: 'WARN',
      );
      _presentAmbient(notice);
      return;
    }
    showDialog<void>(
      context: navContext,
      // 严重告警**必须被阅读**：遮罩点击与系统返回键都不允许关掉，
      // 只留「知道了」这一个出口（避免误触把关键告警一扫而过）。
      barrierDismissible: false,
      builder: (BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(notice.title),
          content: notice.detail == null || notice.detail!.isEmpty
              ? null
              : SelectableText(notice.detail!),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('gotIt')),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (!mounted) {
        return;
      }
      _showing = false;
      // 继续消费队列（可能还有更多）。
      WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    });
  }

  /// 一般：横幅（不打断操作）。
  void _presentAmbient(OgLNotice notice) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = notice.detail == null || notice.detail!.isEmpty
        ? notice.title
        : '${notice.title}：${notice.detail}';
    messenger?.showSnackBar(SnackBar(content: Text(text)));
    _showing = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 把内核诊断的 **warn / error** 转发到通知中心。
///
/// 用户要求：**不允许静默降级** —— 任何降级 / 异常都必须以"带事件码"的通知
/// 形式可见（error → 严重级，走弹窗；warn → 告警级，走横幅）。
class OgLDiagnosticsNoticeSink implements KernelLogSink {
  /// 创建接收方。
  const OgLDiagnosticsNoticeSink();

  @override
  void onLog(KernelLogEntry entry) {
    final bool isError = entry.level == KernelLogLevel.error;
    final bool isWarn = entry.level == KernelLogLevel.warn;
    if (!isError && !isWarn) {
      return;
    }
    OgLNoticeCenter.instance.report(
      title: entry.message,
      detail: entry.code == null ? entry.tag : '${entry.tag} · ${entry.code}',
      severity:
          isError ? OgLNoticeSeverity.critical : OgLNoticeSeverity.warning,
    );
  }
}

/// 把引导层信任告警转发到通知中心（`docs/BOOT.md（该文件未落地，以源码为准）` 要求"必须 UI 触达"）。
class OgLTrustNoticeSink implements TrustWarningSink {
  /// 创建接收方。
  const OgLTrustNoticeSink();

  @override
  void onWarning(BootTrustWarning warning) {
    OgLNoticeCenter.instance.report(
      title: warning.message,
      detail: warning.subject,
      severity: warning.severity == TrustSeverity.danger
          ? OgLNoticeSeverity.critical
          : OgLNoticeSeverity.warning,
    );
  }
}
