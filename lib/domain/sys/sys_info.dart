/// L2 中枢级 · 本地深层信息（供 Mod 包 / 诊断页 / 关于页消费）。
///
/// ## 为什么需要它
/// Mod 包要"贴进系统"：显示设备型号、内存、时区、当前网络策略……
/// 这些**不在 GitHub API 里**，只能从本地拿。老 App 完全没有这一层，
/// 所以它的插件只能改改颜色——这就是差距所在。
///
/// ## 三条纪律
/// 1. **采集器可注入**：`device_info_plus` / `package_info_plus` 在 CI 上跑不了，
///    所以每个采集器都是可替换函数——测试注入假实现，真机用插件；
/// 2. **拿不到就说拿不到**：任何一项信息都带来源标记，
///    采集失败返回 `null` 而不是编一个值出来；
/// 3. **默认最小披露**：敏感项（安装 ID）默认脱敏，
///    Mod 必须经 `SysAccessGuard` 申请才拿得到。
library;

import '../../kernel/diagnostics.dart';
import 'sys_platform_io.dart';

/// 信息采集来源。
enum SysSource {
  /// `dart:io` 直接可得（跨平台，最可靠）。
  dart,

  /// Flutter / 平台框架 API 可得（**不依赖 `dart:io`** 的采集路径）。
  web,

  /// 平台插件（device_info_plus / package_info_plus）。
  plugin,

  /// 由底座推导（如网络策略状态）。
  derived,

  /// 当前平台拿不到。
  unavailable,
}

/// 设备信息。
class SysDeviceInfo {
  /// 创建设备信息。
  const SysDeviceInfo({
    required this.platform,
    required this.osVersion,
    required this.localeName,
    required this.cpuCores,
    this.model,
    this.manufacturer,
    this.androidRelease,
    this.isPhysicalDevice,
    this.source = SysSource.dart,
  });

  /// 平台名（`android` / `windows` / `linux` / `ios` / `macos`）。
  final String platform;

  /// 系统版本串。
  final String osVersion;

  /// 区域设置。
  final String localeName;

  /// CPU 逻辑核数。
  ///
  /// **Web 上为 `null`**：浏览器不提供跨平台的核数 API，
  /// 如实标"未知"，而不是编一个数字。
  final int? cpuCores;

  /// 机型（需插件，桌面/CI 为 `null`）。
  final String? model;

  /// 厂商。
  final String? manufacturer;

  /// Android 版本号（如 `13`）。
  final String? androidRelease;

  /// 是否物理设备（模拟器为 `false`）。
  final bool? isPhysicalDevice;

  /// 来源。
  final SysSource source;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'platform': platform,
        'osVersion': osVersion,
        'localeName': localeName,
        if (cpuCores != null) 'cpuCores': cpuCores,
        if (model != null) 'model': model,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (androidRelease != null) 'androidRelease': androidRelease,
        if (isPhysicalDevice != null) 'isPhysicalDevice': isPhysicalDevice,
        'source': source.name,
      };

  @override
  String toString() =>
      'SysDeviceInfo($platform $osVersion, ${cpuCores ?? '?'}cores)';
}

/// 应用信息。
class SysAppInfo {
  /// 创建应用信息。
  const SysAppInfo({
    this.appName,
    this.packageName,
    this.version,
    this.buildNumber,
    this.installId,
    this.firstLaunchedAt,
    this.dataRoot,
    this.source = SysSource.plugin,
  });

  /// 应用名。
  final String? appName;

  /// 包名 / Bundle ID。
  final String? packageName;

  /// 版本号。
  final String? version;

  /// 构建号。
  final String? buildNumber;

  /// **安装 ID（敏感）**：用于区分"不同设备"，默认脱敏。
  final String? installId;

  /// 首次启动时间。
  final DateTime? firstLaunchedAt;

  /// 数据根目录。
  final String? dataRoot;

  /// 来源。
  final SysSource source;

  /// 展示用版本串。
  String get displayVersion {
    final v = version;
    if (v == null) {
      return '未知';
    }
    final b = buildNumber;
    return b == null || b.isEmpty ? v : '$v+$b';
  }

  /// 序列化。
  ///
  /// **默认不含 [installId]**——脱敏是默认行为，不是可选项。
  Map<String, Object?> toJson() => <String, Object?>{
        if (appName != null) 'appName': appName,
        if (packageName != null) 'packageName': packageName,
        if (version != null) 'version': version,
        if (buildNumber != null) 'buildNumber': buildNumber,
        if (firstLaunchedAt != null)
          'firstLaunchedAt': firstLaunchedAt!.toIso8601String(),
        if (dataRoot != null) 'dataRoot': dataRoot,
        'source': source.name,
      };

  /// 含敏感项的序列化（**仅授权给 Mod 时使用**）。
  Map<String, Object?> toJsonWithSecrets() => <String, Object?>{
        ...toJson(),
        if (installId != null) 'installId': installId,
      };

  @override
  String toString() => 'SysAppInfo($packageName $displayVersion)';
}

/// 运行环境信息。
class SysRuntimeInfo {
  /// 创建运行环境信息。
  const SysRuntimeInfo({
    required this.localeName,
    required this.timeZoneName,
    required this.utcOffsetMinutes,
    required this.utcOffsetHoursText,
  });

  /// 区域。
  final String localeName;

  /// 时区名。
  final String timeZoneName;

  /// UTC 偏移（分钟）。
  final int utcOffsetMinutes;

  /// 形如 `+08:00` 的文本。
  final String utcOffsetHoursText;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'localeName': localeName,
        'timeZoneName': timeZoneName,
        'utcOffsetMinutes': utcOffsetMinutes,
        'utcOffset': utcOffsetHoursText,
      };

  @override
  String toString() => 'SysRuntimeInfo($localeName, UTC$utcOffsetHoursText)';
}

/// 内存信息（best-effort：Linux / Android 读 `/proc/meminfo`）。
class SysMemoryInfo {
  /// 创建内存信息。
  const SysMemoryInfo({
    this.totalKb,
    this.availableKb,
    this.source = SysSource.unavailable,
  });

  /// 总内存（KB）。
  final int? totalKb;

  /// 可用内存（KB）。
  final int? availableKb;

  /// 来源。
  final SysSource source;

  /// 是否可用。
  bool get isAvailable => totalKb != null;

  /// 使用率（0–1，未知返回 `null`）。
  double? get usedRatio {
    final total = totalKb;
    final available = availableKb;
    if (total == null || available == null || total <= 0) {
      return null;
    }
    return (total - available) / total;
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        if (totalKb != null) 'totalKb': totalKb,
        if (availableKb != null) 'availableKb': availableKb,
        if (usedRatio != null)
          'usedRatio': double.parse(usedRatio!.toStringAsFixed(3)),
        'source': source.name,
      };

  @override
  String toString() =>
      'SysMemoryInfo(total=${totalKb}KB, available=${availableKb}KB)';
}

/// 网络策略状态（**由底座推导**，不是新开一路探测）。
class SysNetworkInfo {
  /// 创建网络信息。
  const SysNetworkInfo({
    required this.dnsMode,
    required this.dnsSummary,
    this.mirrorChannels = const <String>[],
    this.requests = 0,
    this.failures = 0,
    this.retries = 0,
  });

  /// DNS 模式（`system` / `custom`）。
  final String dnsMode;

  /// DNS 摘要（给用户看的）。
  final String dnsSummary;

  /// 已配置的镜像通道 ID。
  final List<String> mirrorChannels;

  /// 累计请求数。
  final int requests;

  /// 累计失败数。
  final int failures;

  /// 累计重试数。
  final int retries;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'dnsMode': dnsMode,
        'dnsSummary': dnsSummary,
        'mirrorChannels': mirrorChannels,
        'requests': requests,
        'failures': failures,
        'retries': retries,
      };

  @override
  String toString() =>
      'SysNetworkInfo(dns=$dnsMode, mirrors=${mirrorChannels.length})';
}

/// 一次完整采集。
class SysSnapshot {
  /// 创建快照。
  const SysSnapshot({
    required this.collectedAt,
    required this.device,
    required this.app,
    required this.runtime,
    required this.memory,
    required this.network,
  });

  /// 采集时间。
  final DateTime collectedAt;

  /// 设备。
  final SysDeviceInfo device;

  /// 应用。
  final SysAppInfo app;

  /// 运行环境。
  final SysRuntimeInfo runtime;

  /// 内存。
  final SysMemoryInfo memory;

  /// 网络。
  final SysNetworkInfo network;

  /// 序列化（**不含敏感项**）。
  Map<String, Object?> toJson() => <String, Object?>{
        'collectedAt': collectedAt.toIso8601String(),
        'device': device.toJson(),
        'app': app.toJson(),
        'runtime': runtime.toJson(),
        'memory': memory.toJson(),
        'network': network.toJson(),
      };

  @override
  String toString() =>
      'SysSnapshot(${device.platform}, ${app.displayVersion}, ${network.dnsMode})';
}

/// Android 专有信息探测（真机走 `device_info_plus`；测试注入假实现）。
typedef AndroidProbe = Future<
        ({
          String model,
          String manufacturer,
          String release,
          bool isPhysical,
        })?>
    Function();

/// 应用信息探测（真机走 `package_info_plus`）。
typedef AppProbe = Future<
        ({
          String appName,
          String packageName,
          String version,
          String buildNumber,
        })?>
    Function();

/// 内存探测（读 `/proc/meminfo`）。
typedef MemoryProbe = Future<({int totalKb, int availableKb})?> Function();

/// 网络状态来源（由装配层用 `NetBridge` 包装后注入，保持本层干净）。
abstract class SysNetworkSource {
  /// 采集一次。
  Future<SysNetworkInfo> collect();
}

/// 未接线时的占位（明确返回"未知"，而不是编一个值）。
class UnavailableNetworkSource implements SysNetworkSource {
  /// 创建占位。
  const UnavailableNetworkSource();

  @override
  Future<SysNetworkInfo> collect() async => const SysNetworkInfo(
        dnsMode: 'unknown',
        dnsSummary: '未接线',
      );
}

/// 本地深层信息服务。
class SysInfoService {
  /// 创建服务。
  SysInfoService({
    AndroidProbe? androidProbe,
    AppProbe? appProbe,
    MemoryProbe? memoryProbe,
    SysNetworkSource? networkSource,
    Future<String> Function(String path)? readFile,
    KernelDiagnostics? diagnostics,
  })  : _androidProbe = androidProbe,
        _appProbe = appProbe,
        _memoryProbe = memoryProbe ?? _defaultMemoryProbe,
        _networkSource = networkSource ?? const UnavailableNetworkSource(),
        _readFile = readFile ?? _defaultReadFile,
        _diagnostics = diagnostics;

  final AndroidProbe? _androidProbe;
  final AppProbe? _appProbe;
  final MemoryProbe _memoryProbe;
  final SysNetworkSource _networkSource;
  final Future<String> Function(String path) _readFile;
  KernelDiagnostics? _diagnostics;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 采集一次完整快照。
  ///
  /// **单项失败不影响整体**：某一项采集抛异常，只让该项留空，
  /// 绝不让整个"关于页"打不开。
  Future<SysSnapshot> collect() async {
    final device = await _collectDevice();
    final app = await _collectApp();
    final runtime = collectRuntime();
    final memory = await _collectMemory();
    SysNetworkInfo network;
    try {
      network = await _networkSource.collect();
    } catch (error) {
      _diagnostics?.warn(
        'SYS',
        '网络信息采集失败：$error',
        code: 'OGL-SYS-102',
      );
      network = const SysNetworkInfo(dnsMode: 'unknown', dnsSummary: '采集失败');
    }
    return SysSnapshot(
      collectedAt: DateTime.now(),
      device: device,
      app: app,
      runtime: runtime,
      memory: memory,
      network: network,
    );
  }

  /// 运行环境（`SysPlatform` 原语 + `DateTime`，无需插件）。
  ///
  /// 时区与偏移来自 `DateTime`，**两个平台都可用**（浏览器同样有本地时区）。
  SysRuntimeInfo collectRuntime() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return SysRuntimeInfo(
      localeName: SysPlatform.localeName,
      timeZoneName: now.timeZoneName,
      utcOffsetMinutes: offset.inMinutes,
      utcOffsetHoursText: '$sign$hours:$minutes',
    );
  }

  Future<SysDeviceInfo> _collectDevice() async {
    String? model;
    String? manufacturer;
    String? androidRelease;
    bool? isPhysical;
    var source = SysSource.dart;

    final probe = _androidProbe;
    // 设备插件是 Android 专有的：Web 上 `isAndroid` 恒为 false，不会进来。
    if (probe != null && SysPlatform.isAndroid) {
      try {
        final info = await probe();
        if (info != null) {
          model = info.model;
          manufacturer = info.manufacturer;
          androidRelease = info.release;
          isPhysical = info.isPhysical;
          source = SysSource.plugin;
        }
      } catch (error) {
        _diagnostics?.warn(
          'SYS',
          '设备插件信息采集失败，已降级为基础平台信息：$error',
          code: 'OGL-SYS-101',
        );
      }
    }

    return SysDeviceInfo(
      platform: SysPlatform.operatingSystem,
      osVersion: SysPlatform.operatingSystemVersion,
      localeName: SysPlatform.localeName,
      cpuCores: SysPlatform.numberOfProcessors,
      model: model,
      manufacturer: manufacturer,
      androidRelease: androidRelease,
      isPhysicalDevice: isPhysical,
      source: source,
    );
  }

  Future<SysAppInfo> _collectApp() async {
    final probe = _appProbe;
    if (probe == null) {
      return const SysAppInfo();
    }
    try {
      final info = await probe();
      if (info == null) {
        return const SysAppInfo();
      }
      return SysAppInfo(
        appName: info.appName,
        packageName: info.packageName,
        version: info.version,
        buildNumber: info.buildNumber,
        source: SysSource.plugin,
      );
    } catch (error) {
      _diagnostics?.warn(
        'SYS',
        '应用信息采集失败：$error',
        code: 'OGL-SYS-103',
      );
      return const SysAppInfo();
    }
  }

  Future<SysMemoryInfo> _collectMemory() async {
    try {
      final value = await _memoryProbe();
      if (value == null) {
        return const SysMemoryInfo();
      }
      return SysMemoryInfo(
        totalKb: value.totalKb,
        availableKb: value.availableKb,
        source: SysSource.dart,
      );
    } catch (_) {
      return const SysMemoryInfo();
    }
  }

  static Future<String> _defaultReadFile(String path) =>
      SysPlatform.readFile(path);

  /// 默认内存探测：读 `/proc/meminfo`（由 `SysPlatform` 完成平台判断）。
  ///
  /// Web：`readMemInfoText()` 返回 `null`（浏览器不暴露内存信息），
  /// 于是内存项如实标记为「不可用」，而不是编一个数字。
  static Future<({int totalKb, int availableKb})?> _defaultMemoryProbe() async {
    final String? text = await SysPlatform.readMemInfoText();
    if (text == null) {
      return null;
    }
    return parseMemInfo(text);
  }

  /// 解析 `/proc/meminfo`（纯函数，便于离线断言）。
  static ({int totalKb, int availableKb})? parseMemInfo(String text) {
    int? total;
    int? available;
    for (final line in text.split('\n')) {
      if (line.startsWith('MemTotal:')) {
        total = _firstInt(line);
      } else if (line.startsWith('MemAvailable:')) {
        available = _firstInt(line);
      }
      if (total != null && available != null) {
        break;
      }
    }
    if (total == null) {
      return null;
    }
    return (totalKb: total, availableKb: available ?? 0);
  }

  static int? _firstInt(String line) {
    final match = RegExp(r'(\d+)').firstMatch(line);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  /// 注入的文件读取器（诊断用）。
  Future<String> Function(String path) get fileReader => _readFile;
}
