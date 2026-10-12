/// L3 展示级 · 系统级通知（Android / Windows / Linux / macOS / iOS / **Web**）。
///
/// ## 用途
/// 应用在**后台**时，应用内弹窗/横幅无法呈现，必须改成系统通知：
/// 下载完成、长时间任务结束、严重错误等。
///
/// ## 设计
/// - **懒初始化**：第一次真的要发通知时才初始化插件，不拖慢启动；
/// - **不静默**：任何平台异常都写进应用日志（关于页/通知中心可见）；
/// - **平台守卫**：不支持的平台直接跳过并留痕，绝不外抛。
///
/// ## Web（浏览器）
/// 浏览器里没有 `flutter_local_notifications` 那条路可走（页面一刷新、标签页
/// 一关闭，通知渠道就没了），因此：
/// - 浏览器**已授权** `Notification`（`granted`）→ 直接用它发（见
///   `browser_notify.dart`）；
/// - 浏览器**不提供** `Notification`（例如 iOS Safari 16.4 之前）→
///   **如实降级为"不通知"**，把原因写进日志与通知中心，**绝不假装已发送**；
/// - 浏览器**提供但尚未授权**（`default`）/ 读取或申请失败（`error`）→
///   同样如实报"不可用"并写明原因（可用时**不是**这个状态），
///   而且这类状态**会话内可恢复**：下次发送会重新实测，用户刚在站点设置或
///   设置页授权后立刻生效；
/// - **本模块从不申请权限**：`Notification.requestPermission()` 必须在用户
///   手势里调用（启动期自动申请会被浏览器静默拒绝），因此它也**不会**重复
///   弹授权条——申请只由引导页 / 设置页的按钮触发。
///
/// 平台识别全程只用 `kIsWeb` + `defaultTargetPlatform`，**不 import `dart:io`**
/// （Web 上它不存在，见 `lib/platform/platform.dart` 的说明）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../i18n/og_l_i18n.dart';
import 'browser_notify.dart';
import 'error_surface.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('shell', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 系统通知发送器（单例）。
class OgLSystemNotifier {
  OgLSystemNotifier._();

  /// 单例。
  static final OgLSystemNotifier instance = OgLSystemNotifier._();

  /// 原生平台的插件（**懒创建**：Web 上根本不会用到它，也就不构造它）。
  late final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _unavailable = false;
  String? _unavailableReason;
  int _nextId = 1;

  /// Web：最近一次实测到的浏览器通知授权状态
  /// （`granted` / `default` / `denied` / `unsupported` / `error`）。
  String? _webPermission;

  /// 是否可用（初始化成功且平台支持）。
  ///
  /// Web 上语义收窄为"**真的发得出去**"：只有授权为 `granted` 才算可用。
  /// 浏览器支持通知但还没授权（`default`）时如实报不可用 + 原因，
  /// 而不是"报可用、发送时才失败"。
  bool get available => _initialized && !_unavailable;

  /// 不可用原因（可用时为 `null`）。
  String? get unavailableReason => _unavailableReason;

  /// Web：上次判定的"不可用"是否属于**会话内可恢复**的状态。
  ///
  /// `default`（尚未授权）/ `error`（读取或申请失败）都会随用户在站点设置里
  /// 改授权、或在应用内点"申请"而变化 —— 一旦缓存到底，就会出现"明明刚授权
  /// 成功，应用还一直说不支持"。`denied` / `unsupported` 才一票否决。
  bool get _webRecoverable =>
      kIsWeb && (_webPermission == 'default' || _webPermission == 'error');

  /// Windows 用的是 AppUserModelID + GUID（固定值即可，需全局唯一）。
  static const String _kWindowsAppUserModelId = 'com.ohgithublost.ogl';
  static const String _kWindowsGuid = 'b6e7c1a2-3f45-4a9b-8c21-9d5e6f7a8b90';

  /// 原生平台的通知初始化参数（**Web 不会走到这里**）。
  InitializationSettings _initializationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        );
      case TargetPlatform.iOS:
        return const InitializationSettings(
          iOS: DarwinInitializationSettings(),
        );
      case TargetPlatform.macOS:
        return const InitializationSettings(
          macOS: DarwinInitializationSettings(),
        );
      case TargetPlatform.linux:
        return InitializationSettings(
          linux: LinuxInitializationSettings(defaultActionName: _t('open')),
        );
      case TargetPlatform.windows:
        return const InitializationSettings(
          windows: WindowsInitializationSettings(
            appName: 'OhGithubLost',
            appUserModelId: _kWindowsAppUserModelId,
            guid: _kWindowsGuid,
          ),
        );
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          '平台不支持系统通知：${defaultTargetPlatform.name}',
        );
    }
  }

  /// 初始化（幂等）。返回是否可用。
  ///
  /// Web：**只读取**授权状态，从不申请权限（申请必须在用户手势里，
  /// 启动期自动申请会被浏览器静默拒绝 —— 这正是"权限网关异常"的典型成因）。
  /// 因此重复初始化**不会**重复弹授权条。
  Future<bool> _ensureInit() async {
    // `denied` / `unsupported` 一票否决；`default` / `error` 可恢复，
    // 每次重新实测（用户可能刚授权）。
    if (_initialized && !_webRecoverable) {
      return !_unavailable;
    }
    _initialized = true;
    // ★ Web：浏览器通知没有"初始化"这一步，只判断浏览器给不给这个能力。
    //   不给就**如实降级为不通知**（而不是假装初始化成功）。
    //   优先走 `navigator.permissions.query`（Permissions API），失败时
    //   回退到 `Notification.permission`，两条路径结果对齐（见
    //   `browser_notify_web.dart` 的 `ogLBrowserNotifyPermissionAsync`）。
    if (kIsWeb) {
      final String permission = await ogLBrowserNotifyPermissionAsync();
      _webPermission = permission;
      if (permission == 'granted') {
        _unavailable = false;
        _unavailableReason = null;
        return true;
      }
      _unavailable = true;
      // 五种状态必须分开报：`default`（还没问过）与 `unsupported`（没这个 API）
      // 是**两件事**，`error`（读取/申请失败）又是第三件 —— 混报会让用户
      // 得到一个错误的结论（例如"换浏览器"）。文案走 i18n（`shell` 分片）。
      final String nextReason;
      if (permission == 'denied') {
        nextReason = _t('notifWebDenied');
      } else if (permission == 'default') {
        nextReason = _t('notifWebNotGranted');
      } else if (permission == 'unsupported') {
        nextReason = _t('notifWebUnsupported');
      } else {
        nextReason = _t('notifWebUnknown');
      }
      // 可恢复状态会被反复实测 —— 只在原因**变化**时记一条，避免刷屏。
      if (_unavailableReason != nextReason) {
        _unavailableReason = nextReason;
        OgLAppLog.instance.add(
          _t('notification'),
          '系统通知不可用：$nextReason（本次会话不发送系统通知）',
          severity: OgLNoticeSeverity.warning,
        );
      }
      return false;
    }
    try {
      final InitializationSettings settings = _initializationSettings();
      final bool? ok = await _plugin.initialize(settings: settings);
      if (ok == false) {
        _unavailable = true;
        _unavailableReason = '插件初始化返回 false';
        OgLAppLog.instance.add(
          _t('notification'),
          '系统通知初始化失败：插件返回 false',
          severity: OgLNoticeSeverity.warning,
        );
        return false;
      }
      return true;
    } catch (error) {
      _unavailable = true;
      _unavailableReason = '$error';
      OgLAppLog.instance.add(
        _t('notification'),
        _t('systemNotifUnavailable', {'error': error}),
        severity: OgLNoticeSeverity.warning,
      );
      return false;
    }
  }

  /// 发送一条系统通知。失败只留痕，不抛。
  ///
  /// Web：浏览器**支持** `Notification` 就直接发；**不支持**则本就
  /// `_ensureInit()` 失败、这里直接返回（降级为"不通知"）。
  /// 发送失败（未授权 / 被浏览器拒绝）**如实**记录为"未发出"。
  Future<void> show({required String title, String? body}) async {
    try {
      if (!await _ensureInit()) {
        return;
      }
      if (kIsWeb) {
        if (!ogLBrowserNotifyShow(title, body)) {
          OgLAppLog.instance.add(
            _t('notification'),
            '浏览器通知未发出（未授权或被浏览器拒绝）',
            severity: OgLNoticeSeverity.warning,
          );
        }
        return;
      }
      final NotificationDetails details = NotificationDetails(
        android: AndroidNotificationDetails(
          'ogl_events',
          _t('appNotifications'),
          channelDescription: _t('appNotifDesc'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (error) {
      OgLAppLog.instance.add(
        _t('notification'),
        '发送系统通知失败：$error',
        severity: OgLNoticeSeverity.warning,
      );
    }
  }
}
