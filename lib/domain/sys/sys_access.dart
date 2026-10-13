/// L2 中枢级 · Mod 能力守门（Capability Guard）。
///
/// ## 它解决什么问题
/// Mod 包是**第三方代码**。它想看设备信息、网络状态、安装 ID——
/// 这些一旦无门槛开放，就等于把用户指纹交给了每一个插件。
///
/// 所以：**能力必须显式声明、显式授权、可撤销、可审计**，并且
/// **默认最小披露**——没授权的能力，字段**根本不出现**在返回结果里
/// （而不是返回 `null` 让 Mod 猜）。
///
/// ## 与 BOOT 的关系
/// [BOOT.md](../docs/BOOT.md（该文件未落地，以源码为准）) 规定"装载 Mod 必须弹窗告警"；
/// 本文档对应的是"**运行期**越权访问"。两者一前一后，缺一不可。
library;

import 'dart:async';
import 'dart:convert';

import '../../kernel/contract/disk_store.dart';
import '../../kernel/diagnostics.dart';
import 'sys_info.dart';

/// Mod 可申请的能力。
enum SysCapability {
  /// 基础设备信息（平台 / 系统版本 / 核数）——**公开，无需授权**。
  deviceBasic,

  /// 设备硬件标识（机型 / 厂商 / 是否真机）。
  deviceHardware,

  /// 应用基础信息（版本 / 包名）。
  appBasic,

  /// 安装 ID（**敏感**：可用于跨会话追踪设备）。
  appInstallId,

  /// 运行环境（区域 / 时区）。
  runtime,

  /// 内存。
  memory,

  /// 网络策略状态（DNS / 镜像通道 / 统计）。
  network,

  /// 自定义数据目录读写（未来扩展）。
  fileSystem,
}

/// 能力元数据。
class SysCapabilityInfo {
  /// 创建元数据。
  const SysCapabilityInfo({
    required this.capability,
    required this.label,
    required this.description,
    this.sensitive = false,
    this.grantRequired = true,
  });

  /// 能力。
  final SysCapability capability;

  /// 展示名。
  final String label;

  /// 给用户看的说明（**必须说清拿去看什么**）。
  final String description;

  /// 是否敏感。
  final bool sensitive;

  /// 是否需要显式授权（`false` 表示公开能力）。
  final bool grantRequired;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'capability': capability.name,
        'label': label,
        'description': description,
        'sensitive': sensitive,
        'grantRequired': grantRequired,
      };
}

/// 能力清单（**唯一真源**：界面展示与守门判定都用它）。
const List<SysCapabilityInfo> sysCapabilityCatalog = <SysCapabilityInfo>[
  SysCapabilityInfo(
    capability: SysCapability.deviceBasic,
    label: '设备基础信息',
    description: '平台名称、系统版本、CPU 核数。用于适配界面与排查问题。',
    grantRequired: false,
  ),
  SysCapabilityInfo(
    capability: SysCapability.deviceHardware,
    label: '设备硬件标识',
    description: '机型与厂商（如 "Xiaomi 14"）。会被 Mod 用于判断设备能力。',
  ),
  SysCapabilityInfo(
    capability: SysCapability.appBasic,
    label: '应用基础信息',
    description: '本应用名称、包名与版本号。',
    grantRequired: false,
  ),
  SysCapabilityInfo(
    capability: SysCapability.appInstallId,
    label: '安装标识',
    description: '本机安装的唯一标识。**可用于跨会话追踪你的设备**，请谨慎授权。',
    sensitive: true,
  ),
  SysCapabilityInfo(
    capability: SysCapability.runtime,
    label: '运行环境',
    description: '系统区域与时区。用于正确显示时间与本地化。',
    grantRequired: false,
  ),
  SysCapabilityInfo(
    capability: SysCapability.memory,
    label: '内存信息',
    description: '总内存与可用内存。Mod 可用于按内存决定加载策略。',
  ),
  SysCapabilityInfo(
    capability: SysCapability.network,
    label: '网络策略状态',
    description: '当前 DNS 模式、加速通道与请求统计。',
  ),
  SysCapabilityInfo(
    capability: SysCapability.fileSystem,
    label: '数据目录读写',
    description: '允许 Mod 在本应用数据目录内读写自己的文件。',
  ),
];

/// 能力元数据查询。
SysCapabilityInfo sysCapabilityInfo(SysCapability capability) =>
    sysCapabilityCatalog.firstWhere(
      (SysCapabilityInfo info) => info.capability == capability,
      orElse: () => SysCapabilityInfo(
        capability: capability,
        label: capability.name,
        description: '未登记的能力（请补齐能力清单）',
      ),
    );

/// 一条授权记录。
class SysGrant {
  /// 创建授权。
  const SysGrant({
    required this.modId,
    required this.capability,
    required this.grantedAt,
    this.note,
  });

  /// Mod 标识。
  final String modId;

  /// 能力。
  final SysCapability capability;

  /// 授权时间。
  final DateTime grantedAt;

  /// 备注（用户授权时的上下文）。
  final String? note;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'modId': modId,
        'capability': capability.name,
        'grantedAt': grantedAt.toIso8601String(),
        if (note != null) 'note': note,
      };

  /// 反序列化。
  static SysGrant? fromJson(Map<String, dynamic> json) {
    final modId = json['modId'];
    final capabilityName = json['capability'];
    if (modId is! String || capabilityName is! String) {
      return null;
    }
    SysCapability? capability;
    for (final value in SysCapability.values) {
      if (value.name == capabilityName) {
        capability = value;
      }
    }
    if (capability == null) {
      return null;
    }
    return SysGrant(
      modId: modId,
      capability: capability,
      grantedAt: json['grantedAt'] is String
          ? DateTime.tryParse(json['grantedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      note: json['note'] is String ? json['note'] as String : null,
    );
  }
}

/// 访问被拒绝。
class SysAccessDenied implements Exception {
  /// 创建异常。
  const SysAccessDenied(this.modId, this.capability);

  /// Mod 标识。
  final String modId;

  /// 缺失的能力。
  final SysCapability capability;

  @override
  String toString() =>
      'SysAccessDenied: Mod "$modId" 未获授权 capability=${capability.name}'
      '（${sysCapabilityInfo(capability).description}）';
}

/// 能力守门。
class SysAccessGuard {
  /// 创建守门。
  SysAccessGuard({
    DiskKv? store,
    KernelDiagnostics? diagnostics,
  })  : _store = store,
        _diagnostics = diagnostics;

  /// 授权记录前缀。
  static const String grantPrefix = 'ogl.sysgrant.';

  final DiskKv? _store;
  KernelDiagnostics? _diagnostics;

  /// 无持久化时的内存兜底（测试 / 纯内存模式）。
  final List<SysGrant> _memory = <SysGrant>[];

  /// 写操作的串行化尾指针。
  ///
  /// `grant` / `revoke` 都是"读全部 → 改 → 写全部"，**必须串行**，
  /// 否则两个并发授权会各自基于旧快照写回，后写者把前者的授权抹掉
  /// （经典 read-modify-write 丢失更新）。
  Future<void> _serial = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _serial;
    final completer = Completer<void>();
    _serial = completer.future;
    try {
      await previous;
    } catch (_) {
      // 前序写操作失败不影响本次（各自独立判定）。
    }
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 该能力是否**无需授权**即可读。
  static bool isPublic(SysCapability capability) =>
      !sysCapabilityInfo(capability).grantRequired;

  /// 某 Mod 已获得的能力。
  Future<Set<SysCapability>> grantsFor(String modId) async {
    final result = <SysCapability>{};
    for (final capability in SysCapability.values) {
      if (isPublic(capability)) {
        result.add(capability);
      }
    }
    for (final grant in await _allGrants()) {
      if (grant.modId == modId) {
        result.add(grant.capability);
      }
    }
    return result;
  }

  /// 全部授权（审计 / 设置页展示）。
  Future<List<SysGrant>> allGrants() async => _allGrants();

  /// 授权。
  ///
  /// **串行执行**：读-改-写必须原子，否则并发授权会丢失更新。
  Future<void> grant(
    String modId,
    SysCapability capability, {
    String? note,
  }) {
    if (isPublic(capability)) {
      return Future<void>.value(); // 公开能力无需授权，也不留记录。
    }
    return _serialized(() async {
      final grants = await _allGrants();
      grants.removeWhere((SysGrant grant) =>
          grant.modId == modId && grant.capability == capability);
      final grant = SysGrant(
        modId: modId,
        capability: capability,
        grantedAt: DateTime.now(),
        note: note,
      );
      grants.add(grant);
      await _saveAll(grants);
      _diagnostics?.warn(
        'SYSACC',
        'Mod 获得能力授权',
        code: 'OGL-SYSACC-001',
        data: <String, Object?>{
          'modId': modId,
          'capability': capability.name,
          'sensitive': sysCapabilityInfo(capability).sensitive,
        },
      );
    });
  }

  /// 撤销。
  Future<void> revoke(String modId, SysCapability capability) =>
      _serialized(() async {
        final grants = await _allGrants();
        final before = grants.length;
        grants.removeWhere((SysGrant grant) =>
            grant.modId == modId && grant.capability == capability);
        if (grants.length != before) {
          await _saveAll(grants);
          _diagnostics?.info(
            'SYSACC',
            'Mod 能力已撤销',
            code: 'OGL-SYSACC-002',
            data: <String, Object?>{
              'modId': modId,
              'capability': capability.name,
            },
          );
        }
      });

  /// 撤销某 Mod 的全部能力（卸载 Mod 时必须调用）。
  Future<int> revokeAll(String modId) => _serialized(() async {
        final grants = await _allGrants();
        final before = grants.length;
        grants.removeWhere((SysGrant grant) => grant.modId == modId);
        await _saveAll(grants);
        final removed = before - grants.length;
        if (removed > 0) {
          _diagnostics?.warn(
            'SYSACC',
            'Mod 全部能力已撤销',
            code: 'OGL-SYSACC-003',
            data: <String, Object?>{'modId': modId, 'removed': removed},
          );
        }
        return removed;
      });

  /// 断言某 Mod 拥有某能力；缺失则抛 [SysAccessDenied]（并留审计）。
  Future<void> require(
    String modId,
    SysCapability capability,
  ) async {
    final owned = await grantsFor(modId);
    if (!owned.contains(capability)) {
      _diagnostics?.warn(
        'SYSACC',
        'Mod 越权访问被拒绝',
        code: 'OGL-SYSACC-101',
        data: <String, Object?>{
          'modId': modId,
          'capability': capability.name,
        },
      );
      throw SysAccessDenied(modId, capability);
    }
  }

  /// 按授权裁剪快照：**未授权的切片直接不出现**。
  ///
  /// 这一步是"默认最小披露"的落点——不是返回 null，而是不返回。
  Future<Map<String, Object?>> sliceFor(
    String modId,
    SysSnapshot snapshot,
  ) async {
    final owned = await grantsFor(modId);
    final result = <String, Object?>{
      'collectedAt': snapshot.collectedAt.toIso8601String(),
      'granted': (owned.toList()
            ..sort(
                (SysCapability a, SysCapability b) => a.name.compareTo(b.name)))
          .map((SysCapability capability) => capability.name)
          .toList(),
    };

    final device = snapshot.device.toJson();
    if (owned.contains(SysCapability.deviceHardware)) {
      result['device'] = device;
    } else {
      // 只给公开字段，硬件标识被**剥离**。
      result['device'] = <String, Object?>{
        'platform': snapshot.device.platform,
        'osVersion': snapshot.device.osVersion,
        'cpuCores': snapshot.device.cpuCores,
        'source': snapshot.device.source.name,
      };
    }

    result['app'] = owned.contains(SysCapability.appInstallId)
        ? snapshot.app.toJsonWithSecrets()
        : snapshot.app.toJson();

    if (owned.contains(SysCapability.runtime)) {
      result['runtime'] = snapshot.runtime.toJson();
    }
    if (owned.contains(SysCapability.memory)) {
      result['memory'] = snapshot.memory.toJson();
    }
    if (owned.contains(SysCapability.network)) {
      result['network'] = snapshot.network.toJson();
    }
    return result;
  }

  /// 生成给用户看的授权请求说明（**必须能读懂**）。
  static Map<String, Object?> describeRequest(
    String modName,
    List<SysCapability> requested,
  ) =>
      <String, Object?>{
        'mod': modName,
        'items': requested
            .map((SysCapability capability) =>
                sysCapabilityInfo(capability).toJson())
            .toList(),
        'hasSensitive': requested.any(
          (SysCapability capability) => sysCapabilityInfo(capability).sensitive,
        ),
      };

  Future<List<SysGrant>> _allGrants() async {
    final store = _store;
    if (store == null) {
      return List<SysGrant>.of(_memory);
    }
    final grants = <SysGrant>[];
    for (final key in await store.keys()) {
      if (!key.startsWith(grantPrefix)) {
        continue;
      }
      final raw = await store.read(key);
      if (raw == null) {
        continue;
      }
      try {
        final grant =
            SysGrant.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (grant == null) {
          await store.remove(key);
          continue;
        }
        grants.add(grant);
      } catch (_) {
        await store.remove(key);
      }
    }
    return grants;
  }

  Future<void> _saveAll(List<SysGrant> grants) async {
    final store = _store;
    if (store == null) {
      _memory
        ..clear()
        ..addAll(grants);
      return;
    }
    // 先清旧记录，再写新记录（避免已撤销的授权残留）。
    for (final key in await store.keys()) {
      if (key.startsWith(grantPrefix)) {
        await store.remove(key);
      }
    }
    for (final grant in grants) {
      await store.write(
        '$grantPrefix${grant.modId}.${grant.capability.name}',
        jsonEncode(grant.toJson()),
      );
    }
  }
}
