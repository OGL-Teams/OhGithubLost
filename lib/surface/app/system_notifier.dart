/// L3 展示级 · 系统级通知（Android / Windows / Linux / macOS / iOS）。
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
/// 平台识别全程只用 `defaultTargetPlatform`，**不 import `dart:io`**
/// （见 `lib/platform/platform.dart` 的说明）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../i18n/og_l_i18n.dart';
import 'error_surface.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'shell', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 系统通知发送器（单例）。
class OgLSystemNotifier {
  OgLSystemNotifier._();

  /// 单例。
  static final OgLSystemNotifier instance = OgLSystemNotifier._();

  /// 原生平台的插件（**懒创建**：第一次真的要发通知时才构造）。
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

  /// 系统通知初始化参数（按平台分派）。
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
  Future<void> show({required String title, String? body}) async {
    try {
      if (!await _ensureInit()) {
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
