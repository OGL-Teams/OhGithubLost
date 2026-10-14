/// L3 展示级 · 权限网关（跨平台分派 + **真实系统请求**）。
///
/// ## 为什么是 `permission_handler`
/// 早期版本是纯 Dart 网关：Android 上只会"跑探针 + 打开设置"，
/// 从不调用运行时权限弹窗；打开设置用的还是 iOS 的 `app-settings:` URI，
/// 在 Android 上基本必然失败 —— 表现为"点了没反应 / 显示不支持"。
/// 现在改用成熟库 `permission_handler`：
/// - **真正调起系统权限弹窗**（Android 运行时权限 / iOS 通知授权）；
/// - `openAppSettings()` 使用各平台**正确**的设置页入口；
/// - Android 11+ 的"所有文件访问"走 `manageExternalStorage` 特殊页。
///
/// ## Android 的编译链注意事项
/// `permission_handler_android` 要求宿主 `compileSdk` 高于 Flutter 默认值。
/// 本项目平台目录由 CI 现场生成，故在构建期由
/// `tool/inject_platform_spec.py` 幂等注入 `compileSdk`（见 build.yml）。
///
/// ## 平台差异
/// | 平台            | 存储                 | 通知                 |
/// |-----------------|----------------------|----------------------|
/// | Android         | 运行时/特殊页请求    | 13+ 运行时请求        |
/// | iOS / macOS     | 沙箱内不需要         | 系统弹窗请求          |
/// | Windows / Linux | 不需要               | 不需要                |
/// | Web             | 不支持               | 不支持                |
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n/og_l_i18n.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('shell', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 权限种类（与业务相关的最小集合）。
enum OgLPermission {
  /// 存储 / 文件访问（影响日志落盘位置、下载文件可见性）。
  storage,

  /// 通知（影响限流提醒、下载完成等主动提示）。
  notifications,
}

/// 权限状态。
enum OgLPermissionStatus {
  /// 已具备（或系统已默认授予）。
  granted,

  /// 需要用户到系统设置手动开启。
  needsUserAction,

  /// 该平台不需要此类权限。
  notRequired,

  /// 该平台不支持此类权限。
  unsupported,
}

/// 单条权限的说明与状态。
@immutable
class OgLPermissionInfo {
  /// 创建条目。
  const OgLPermissionInfo({
    required this.permission,
    required this.title,
    required this.rationale,
    required this.status,
  });

  /// 权限种类。
  final OgLPermission permission;

  /// 标题。
  final String title;

  /// 为什么需要它。
  final String rationale;

  /// 当前状态。
  final OgLPermissionStatus status;

  /// 是否还需要用户处理。
  bool get actionable => status == OgLPermissionStatus.needsUserAction;

  /// 是否已就绪（无需再处理）。
  bool get ready =>
      status == OgLPermissionStatus.granted ||
      status == OgLPermissionStatus.notRequired;

  /// 复制并覆盖状态。
  OgLPermissionInfo withStatus(OgLPermissionStatus next) => OgLPermissionInfo(
        permission: permission,
        title: title,
        rationale: rationale,
        status: next,
      );
}

/// 权限网关接口（各平台实现）。
abstract class OgLPermissionGateway {
  /// 平台展示名（引导页会明显展示，用户要知道自己在为哪个平台授权）。
  String get platformLabel;

  /// 本平台托管的权限清单及其当前状态。
  Future<List<OgLPermissionInfo>> describe();

  /// 主动获取一次（**真正调起系统弹窗**）。返回获取后的状态。
  Future<OgLPermissionStatus> request(OgLPermission permission);

  /// 是否具备"跳到本应用系统设置页"的能力。
  bool get canOpenSettings;
}

/// 按运行平台创建网关（**唯一入口**）。
///
/// [storageProbe] 由装配层注入：返回"应用目录当前是否可写"。
/// 不传时按"可用"处理（例如桌面端）。
OgLPermissionGateway ogLPermissionGateway({
  Future<bool> Function()? storageProbe,
  Future<String> Function()? storageLocation,
}) {
  if (kIsWeb) {
    return const _WebPermissionGateway();
  }
  if (Platform.isAndroid) {
    return _AndroidPermissionGateway(
      storageProbe: storageProbe,
      storageLocation: storageLocation,
    );
  }
  if (Platform.isIOS) {
    return const _IosPermissionGateway();
  }
  if (Platform.isMacOS) {
    return const _MacPermissionGateway();
  }
  return const _DesktopPermissionGateway();
}

/// 尝试跳转到本应用的系统设置页（由 `permission_handler` 提供正确入口）。
Future<bool> _openAppSettings() async {
  try {
    return await openAppSettings();
  } catch (error) {
    // 该平台不支持时如实返回 false，由 UI 告知用户手动前往，绝不假装成功。
    debugPrint('OGL 权限网关：打开系统设置失败：$error');
    return false;
  }
}

/// `permission_handler` 状态 → 本项目状态。
OgLPermissionStatus _mapStatus(PermissionStatus status) {
  if (status.isGranted || status.isLimited || status.isProvisional) {
    return OgLPermissionStatus.granted;
  }
  if (status.isRestricted) {
    return OgLPermissionStatus.unsupported;
  }
  // denied（尚未请求）/ permanentlyDenied（已被拒绝）都交回用户处理。
  return OgLPermissionStatus.needsUserAction;
}

/// 安全读取系统权限状态（异常一律视为"需用户处理"，绝不外抛）。
Future<OgLPermissionStatus> _statusOf(Permission permission) async {
  try {
    return _mapStatus(await permission.status);
  } catch (_) {
    return OgLPermissionStatus.needsUserAction;
  }
}

/// 安全请求系统权限（异常一律视为"需用户处理"，绝不外抛）。
Future<OgLPermissionStatus> _requestOf(Permission permission) async {
  try {
    return _mapStatus(await permission.request());
  } catch (_) {
    return OgLPermissionStatus.needsUserAction;
  }
}

/// 基于 `permission_handler` 的通用网关（Android / iOS / macOS 共用）。
abstract class _HandlerGateway implements OgLPermissionGateway {
  /// 创建。
  const _HandlerGateway({
    Future<bool> Function()? storageProbe,
    Future<String> Function()? storageLocation,
  })  : _probeOverride = storageProbe,
        _locationProvider = storageLocation;

  final Future<bool> Function()? _probeOverride;
  final Future<String> Function()? _locationProvider;

  @override
  bool get canOpenSettings => true;

  /// 「存储」映射到的系统权限（按优先级；空 = 本平台不需要）。
  List<Permission> storagePermissions();

  /// 「通知」映射到的系统权限（`null` = 本平台不需要）。
  Permission? notificationPermission();

  /// 本地可写探针。
  ///
  /// **约定**：它必须返回"文件是否落在**用户可见**的位置"，而不是
  /// "随便找个能写的地方"——否则退回应用私有目录也会被判成"已授权"。
  Future<bool> Function()? get storageProbe => _probeOverride;

  /// 说明里的**平台差异提示**（默认无；例如 Android 按版本不同）。
  String storageRationaleExtra() => '';

  Future<bool> _storageOk() async {
    final probe = storageProbe;
    if (probe == null) {
      return true;
    }
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  /// 当前落盘位置（取不到就返回 `null`）。
  Future<String?> _locationText() async {
    final provider = _locationProvider;
    if (provider == null) {
      return null;
    }
    try {
      return await provider();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<OgLPermissionInfo>> describe() async {
    final List<Permission> storage = storagePermissions();
    final Permission? notify = notificationPermission();
    final bool sandbox = storage.isEmpty;
    final bool ok = sandbox ? true : await _storageOk();
    String rationale = sandbox
        ? _t('storageSandbox')
        : _t('storageGrantDesc1') + _t('storageGrantDesc2');
    if (!sandbox && !ok) {
      // 未就绪时**如实告诉用户两件事**：为什么（各版本差异）+ 现在落在哪。
      final String extra = storageRationaleExtra();
      if (extra.isNotEmpty) {
        rationale = '$rationale\n$extra';
      }
      final String? where = await _locationText();
      if (where != null && where.isNotEmpty) {
        rationale = '$rationale\n${_t('storageWhere')}：$where';
      }
    }
    return <OgLPermissionInfo>[
      OgLPermissionInfo(
        permission: OgLPermission.storage,
        title: _t('storageAccess'),
        rationale: rationale,
        status: sandbox
            ? OgLPermissionStatus.notRequired
            : (ok
                ? OgLPermissionStatus.granted
                : OgLPermissionStatus.needsUserAction),
      ),
      OgLPermissionInfo(
        permission: OgLPermission.notifications,
        title: _t('notification'),
        rationale: notify == null
            ? _t('notifNoAuth')
            : _t('notifDesc'),
        status: notify == null
            ? OgLPermissionStatus.notRequired
            : await _statusOf(notify),
      ),
    ];
  }

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async {
    switch (permission) {
      case OgLPermission.storage:
        final List<Permission> storage = storagePermissions();
        if (storage.isEmpty) {
          return OgLPermissionStatus.notRequired;
        }
        // ★ 真正调起系统弹窗：逐个请求，任一授予即视为已授权。
        for (final Permission item in storage) {
          final OgLPermissionStatus status = await _requestOf(item);
          if (status == OgLPermissionStatus.granted) {
            break;
          }
        }
        // 授权后仍以真实写入探针做二次确认（授权 ≠ 可写）。
        if (await _storageOk()) {
          return OgLPermissionStatus.granted;
        }
        await _openAppSettings();
        return OgLPermissionStatus.needsUserAction;
      case OgLPermission.notifications:
        final Permission? notify = notificationPermission();
        if (notify == null) {
          return OgLPermissionStatus.notRequired;
        }
        return _requestOf(notify);
    }
  }
}

/// Android：存储（运行时 / 所有文件访问）+ 通知（13+）。
class _AndroidPermissionGateway extends _HandlerGateway {
  /// 创建网关。
  const _AndroidPermissionGateway({
    super.storageProbe,
    super.storageLocation,
  });

  @override
  String get platformLabel => 'Android';

  /// 版本差异提示：Android 11+ 需要"所有文件访问"；部分 ROM 只允许逐个授权。
  @override
  String storageRationaleExtra() => _t('storageHintModern');

  @override
  List<Permission> storagePermissions() => const <Permission>[
        // Android 11+ 需要「所有文件访问」才能写 /sdcard 根目录；
        // 旧版本则用传统存储权限。两者都请求，命中即止。
        Permission.manageExternalStorage,
        Permission.storage,
      ];

  @override
  Permission? notificationPermission() => Permission.notification;
}

/// iOS：沙箱内存储无需权限；通知需系统弹窗。
class _IosPermissionGateway extends _HandlerGateway {
  /// 创建网关。
  const _IosPermissionGateway();

  @override
  String get platformLabel => 'iOS';

  @override
  List<Permission> storagePermissions() => const <Permission>[];

  @override
  Permission? notificationPermission() => Permission.notification;
}

/// macOS：沙箱内存储无需权限；通知需系统弹窗。
class _MacPermissionGateway extends _HandlerGateway {
  /// 创建网关。
  const _MacPermissionGateway();

  @override
  String get platformLabel => 'macOS';

  @override
  List<Permission> storagePermissions() => const <Permission>[];

  @override
  Permission? notificationPermission() => Permission.notification;
}

/// Windows / Linux：桌面平台，所需权限均不需要。
class _DesktopPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _DesktopPermissionGateway();

  @override
  String get platformLabel {
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    // 其它桌面/未知平台：用系统名兜底，避免谎报平台。
    return Platform.operatingSystem;
  }

  @override
  bool get canOpenSettings => false;

  @override
  Future<List<OgLPermissionInfo>> describe() async =>
       <OgLPermissionInfo>[
        OgLPermissionInfo(
          permission: OgLPermission.storage,
          title: _t('storageAccess'),
          rationale: _t('desktopStorageDesc'),
          status: OgLPermissionStatus.notRequired,
        ),
        OgLPermissionInfo(
          permission: OgLPermission.notifications,
          title: _t('notification'),
          rationale: _t('desktopNotifDesc'),
          status: OgLPermissionStatus.notRequired,
        ),
      ];

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async =>
      OgLPermissionStatus.notRequired;
}

/// Web：不支持系统权限。
class _WebPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _WebPermissionGateway();

  @override
  String get platformLabel => 'Web';

  @override
  bool get canOpenSettings => false;

  @override
  Future<List<OgLPermissionInfo>> describe() async =>
       <OgLPermissionInfo>[
        OgLPermissionInfo(
          permission: OgLPermission.storage,
          title: _t('storageAccess'),
          rationale: _t('webStorageDesc'),
          status: OgLPermissionStatus.unsupported,
        ),
        OgLPermissionInfo(
          permission: OgLPermission.notifications,
          title: _t('notification'),
          rationale: _t('webNotifDesc'),
          status: OgLPermissionStatus.unsupported,
        ),
      ];

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async =>
      OgLPermissionStatus.unsupported;
}