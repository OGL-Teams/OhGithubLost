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
/// - 浏览器**提供** `Notification` → 直接用它发（见 `browser_notify.dart`）；
/// - 浏览器**不提供**（例如 iOS Safari 16.4 之前）→ **如实降级为"不通知"**，
///   把原因写进日志与通知中心，**绝不假装已发送**。
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

  /// 是否可用（初始化成功且平台支持）。
  bool get available => _initialized && !_unavailable;

  /// 不可用原因（可用时为 `null`）。
  String? get unavailableReason => _unavailableReason;

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
  Future<bool> _ensureInit() async {
    if (_initialized) {
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
      if (permission != 'unsupported' && permission != 'denied') {
        return true;
      }
      if (permission == 'denied') {
        _unavailable = true;
        _unavailableReason = '浏览器通知已被用户拒绝';
      } else {
        _unavailable = true;
        _unavailableReason = '浏览器不提供 Notification API';
      }
      OgLAppLog.instance.add(
        _t('notification'),
        '系统通知不可用：$permission（本次会话不发送系统通知）',
        severity: OgLNoticeSeverity.warning,
      );
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
