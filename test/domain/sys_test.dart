/// L2 中枢级 · 本地深层信息与 Mod 能力守门测试。
///
/// 两条主线：
/// 1. **拿不到就说拿不到**：任何采集项失败都不能编值、不能拖垮整体；
/// 2. **默认最小披露**：未授权的能力，字段**根本不出现**在 Mod 拿到的数据里。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/domain/sys/sys_access.dart';
import 'package:ohgithublost/domain/sys/sys_info.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

/// 固定返回的网络来源。
class _FakeNetworkSource implements SysNetworkSource {
  _FakeNetworkSource({this.error});

  final Object? error;

  @override
  Future<SysNetworkInfo> collect() async {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return const SysNetworkInfo(
      dnsMode: 'custom',
      dnsSummary: '5 家 DNS · DoH 优先',
      mirrorChannels: <String>['ghproxy'],
      requests: 10,
      failures: 1,
      retries: 2,
    );
  }
}

SysSnapshot _snapshot() => SysSnapshot(
      collectedAt: DateTime.parse('2026-10-01T00:00:00Z'),
      device: const SysDeviceInfo(
        platform: 'android',
        osVersion: 'Linux 6.1',
        localeName: 'zh_CN',
        cpuCores: 8,
        model: 'Xiaomi 14',
        manufacturer: 'Xiaomi',
        isPhysicalDevice: true,
      ),
      app: SysAppInfo(
        appName: 'OGL',
        packageName: 'com.ogl.app',
        version: '0.1.0',
        buildNumber: '1',
        installId: 'install-secret-abc',
      ),
      runtime: const SysRuntimeInfo(
        localeName: 'zh_CN',
        timeZoneName: 'CST',
        utcOffsetMinutes: 480,
        utcOffsetHoursText: '+08:00',
      ),
      memory: const SysMemoryInfo(totalKb: 8000, availableKb: 2000),
      network: const SysNetworkInfo(
        dnsMode: 'custom',
        dnsSummary: '5 家 DNS',
      ),
    );

void main() {
  group('内存解析（/proc/meminfo）', () {
    test('能取出 MemTotal 与 MemAvailable', () {
      const text = 'MemTotal:        8000000 kB\n'
          'MemFree:         1000000 kB\n'
          'MemAvailable:    2000000 kB\n';
      final parsed = SysInfoService.parseMemInfo(text);
      expect(parsed, isNotNull);
      expect(parsed!.totalKb, 8000000);
      expect(parsed.availableKb, 2000000);
    });

    test('缺 MemAvailable 时给 0 而不是崩', () {
      final parsed = SysInfoService.parseMemInfo('MemTotal: 100 kB\n');
      expect(parsed!.totalKb, 100);
      expect(parsed.availableKb, 0);
    });

    test('没有 MemTotal → 返回 null（不编值）', () {
      expect(SysInfoService.parseMemInfo('完全不是 meminfo'), isNull);
    });
  });

  group('信息采集的健壮性', () {
    test('单项失败不影响整体（网络来源抛异常）', () async {
      final diagnostics = KernelDiagnostics();
      final service = SysInfoService(
        networkSource: _FakeNetworkSource(error: const FormatException('坏了')),
        memoryProbe: () async => (totalKb: 100, availableKb: 50),
        diagnostics: diagnostics,
      );
      final snapshot = await service.collect();
      expect(snapshot.network.dnsMode, 'unknown');
      expect(snapshot.memory.totalKb, 100, reason: '其它项不受影响');
      expect(
        diagnostics.logTail.any((e) => e.code == 'OGL-SYS-102'),
        isTrue,
      );
    });

    test('应用信息采集失败 → 空信息 + 留痕，而不是崩', () async {
      final diagnostics = KernelDiagnostics();
      final service = SysInfoService(
        appProbe: () async => throw const FormatException('插件没起来'),
        diagnostics: diagnostics,
      );
      final snapshot = await service.collect();
      expect(snapshot.app.version, isNull);
      expect(snapshot.app.displayVersion, '未知');
      expect(
        diagnostics.logTail.any((e) => e.code == 'OGL-SYS-103'),
        isTrue,
      );
    });

    test('应用信息采集成功 → 走插件来源', () async {
      final service = SysInfoService(
        appProbe: () async => (
          appName: 'OGL',
          packageName: 'com.ogl.app',
          version: '1.2.3',
          buildNumber: '45',
        ),
      );
      final snapshot = await service.collect();
      expect(snapshot.app.displayVersion, '1.2.3+45');
      expect(snapshot.app.source, SysSource.plugin);
    });

    test('内存探测抛异常 → 明确不可用', () async {
      final service = SysInfoService(
        memoryProbe: () async => throw StateError('读不到'),
      );
      final snapshot = await service.collect();
      expect(snapshot.memory.isAvailable, isFalse);
      expect(snapshot.memory.source, SysSource.unavailable);
    });

    test('设备基础信息来自 dart:io（CI 上也能拿到）', () async {
      final service = SysInfoService(
        networkSource: _FakeNetworkSource(),
      );
      final snapshot = await service.collect();
      expect(snapshot.device.platform, isNotEmpty);
      expect(snapshot.device.cpuCores, greaterThan(0));
      expect(snapshot.device.localeName, isNotEmpty);
      // 非 Android 平台不调用插件，硬件标识保持空。
      expect(snapshot.device.source, SysSource.dart);
    });

    test('运行环境带 UTC 偏移文本', () {
      final runtime = SysInfoService().collectRuntime();
      expect(runtime.utcOffsetHoursText, matches(RegExp(r'^[+-]\d{2}:\d{2}$')));
      expect(runtime.timeZoneName, isNotEmpty);
    });

    test('快照整体序列化（不含敏感项）', () {
      final json = _snapshot().toJson();
      expect(json.containsKey('device'), isTrue);
      expect(json.toString().contains('install-secret-abc'), isFalse);
    });
  });

  group('能力清单', () {
    test('清单覆盖全部枚举值（漏登记会被发现）', () {
      for (final capability in SysCapability.values) {
        final info = sysCapabilityInfo(capability);
        expect(info.label, isNotEmpty, reason: '$capability 缺展示名');
        expect(info.description, isNotEmpty, reason: '$capability 缺说明');
      }
      expect(sysCapabilityCatalog.length, SysCapability.values.length);
    });

    test('公开能力与需授权能力划分正确', () {
      expect(SysAccessGuard.isPublic(SysCapability.deviceBasic), isTrue);
      expect(SysAccessGuard.isPublic(SysCapability.appBasic), isTrue);
      expect(SysAccessGuard.isPublic(SysCapability.runtime), isTrue);
      expect(SysAccessGuard.isPublic(SysCapability.appInstallId), isFalse);
      expect(SysAccessGuard.isPublic(SysCapability.memory), isFalse);
      expect(
        sysCapabilityInfo(SysCapability.appInstallId).sensitive,
        isTrue,
        reason: '安装标识必须标记为敏感',
      );
    });

    test('授权请求说明能列出条目并标出敏感项', () {
      final request = SysAccessGuard.describeRequest(
        '示例 Mod',
        <SysCapability>[SysCapability.memory, SysCapability.appInstallId],
      );
      expect(request['mod'], '示例 Mod');
      expect((request['items'] as List<Object?>).length, 2);
      expect(request['hasSensitive'], isTrue);
    });
  });

  group('能力守门', () {
    late SysAccessGuard guard;

    setUp(() {
      guard = SysAccessGuard(store: InMemoryKv());
    });

    test('公开能力自动可用，且不产生授权记录', () async {
      final grants = await guard.grantsFor('mod.a');
      expect(grants, contains(SysCapability.deviceBasic));
      expect(grants, contains(SysCapability.appBasic));
      expect(await guard.allGrants(), isEmpty, reason: '公开能力不留记录');

      await guard.grant('mod.a', SysCapability.deviceBasic);
      expect(await guard.allGrants(), isEmpty);
    });

    test('未授权访问被拒绝并留审计', () async {
      final diagnostics = KernelDiagnostics();
      final guarded = SysAccessGuard(
        store: InMemoryKv(),
        diagnostics: diagnostics,
      );
      await expectLater(
        guarded.require('mod.a', SysCapability.appInstallId),
        throwsA(isA<SysAccessDenied>()),
      );
      expect(
        diagnostics.logTail.any((e) => e.code == 'OGL-SYSACC-101'),
        isTrue,
      );
    });

    test('授权后可访问，撤销后再次被拒', () async {
      await guard.grant('mod.a', SysCapability.appInstallId);
      await guard.require('mod.a', SysCapability.appInstallId); // 不抛

      await guard.revoke('mod.a', SysCapability.appInstallId);
      await expectLater(
        guard.require('mod.a', SysCapability.appInstallId),
        throwsA(isA<SysAccessDenied>()),
      );
    });

    test('授权持久化：新实例仍能看到（模拟重启）', () async {
      final kv = InMemoryKv();
      final first = SysAccessGuard(store: kv);
      await first.grant('mod.a', SysCapability.network);

      final second = SysAccessGuard(store: kv);
      expect(
        await second.grantsFor('mod.a'),
        contains(SysCapability.network),
      );
    });

    test('重复授权不产生重复记录', () async {
      await guard.grant('mod.a', SysCapability.memory);
      await guard.grant('mod.a', SysCapability.memory);
      expect((await guard.allGrants()).length, 1);
    });

    test('revokeAll 清空某 Mod 的全部授权（卸载时必须调用）', () async {
      await guard.grant('mod.a', SysCapability.memory);
      await guard.grant('mod.a', SysCapability.network);
      await guard.grant('mod.b', SysCapability.memory);

      expect(await guard.revokeAll('mod.a'), 2);
      expect(await guard.grantsFor('mod.a'),
          isNot(contains(SysCapability.memory)));
      expect(await guard.grantsFor('mod.b'), contains(SysCapability.memory));
    });

    test('损坏的授权记录被清理，不拖垮读取', () async {
      final kv = InMemoryKv();
      await kv.write('ogl.sysgrant.broken', '{{{');
      final guarded = SysAccessGuard(store: kv);
      await guarded.grant('mod.a', SysCapability.memory);
      expect((await guarded.allGrants()).length, 1);
      expect(await kv.has('ogl.sysgrant.broken'), isFalse);
    });

    test('无持久化时退化为内存模式（测试 / 预览）', () async {
      final memoryGuard = SysAccessGuard();
      await memoryGuard.grant('mod.a', SysCapability.memory);
      expect(
        await memoryGuard.grantsFor('mod.a'),
        contains(SysCapability.memory),
      );
    });

    test('并发授权不丢更新（读-改-写必须串行）', () async {
      final kv = InMemoryKv();
      final guarded = SysAccessGuard(store: kv);

      // 四个授权同时发出：如果不串行，后写者会基于旧快照抹掉前者的结果。
      await Future.wait(<Future<void>>[
        guarded.grant('mod.a', SysCapability.memory),
        guarded.grant('mod.a', SysCapability.network),
        guarded.grant('mod.b', SysCapability.memory),
        guarded.grant('mod.a', SysCapability.fileSystem),
      ]);

      expect((await guarded.allGrants()).length, 4);
      expect(
        await guarded.grantsFor('mod.a'),
        containsAll(<SysCapability>[
          SysCapability.memory,
          SysCapability.network,
          SysCapability.fileSystem,
        ]),
      );
      expect(await guarded.grantsFor('mod.b'), contains(SysCapability.memory));
    });

    test('并发撤销与授权不互相覆盖', () async {
      final guarded = SysAccessGuard(store: InMemoryKv());
      await guarded.grant('mod.a', SysCapability.memory);
      await guarded.grant('mod.a', SysCapability.network);
      await guarded.grant('mod.b', SysCapability.memory);

      await Future.wait(<Future<void>>[
        guarded.revoke('mod.a', SysCapability.memory),
        guarded.grant('mod.c', SysCapability.network),
      ]);

      expect(await guarded.grantsFor('mod.a'),
          isNot(contains(SysCapability.memory)));
      expect(await guarded.grantsFor('mod.a'), contains(SysCapability.network));
      expect(await guarded.grantsFor('mod.b'), contains(SysCapability.memory));
      expect(await guarded.grantsFor('mod.c'), contains(SysCapability.network));
    });
  });

  group('按授权裁剪（默认最小披露）', () {
    late SysAccessGuard guard;

    setUp(() {
      guard = SysAccessGuard(store: InMemoryKv());
    });

    test('无额外授权时：只有公开切片，敏感字段彻底不出现', () async {
      final slice = await guard.sliceFor('mod.a', _snapshot());
      final text = slice.toString();

      expect(slice.containsKey('runtime'), isTrue, reason: 'runtime 是公开能力');
      expect(slice.containsKey('device'), isTrue, reason: '基础设备信息是公开的');
      expect(slice.containsKey('memory'), isFalse);
      expect(slice.containsKey('network'), isFalse);
      expect(text.contains('install-secret-abc'), isFalse);
      expect(text.contains('Xiaomi'), isFalse, reason: '硬件标识必须被剥离');

      final device = slice['device']! as Map<String, Object?>;
      expect(device.containsKey('platform'), isTrue);
      expect(device.containsKey('model'), isFalse);
      expect(device.containsKey('manufacturer'), isFalse);
    });

    test('单独授权硬件标识：设备切片变完整', () async {
      await guard.grant('mod.a', SysCapability.deviceHardware);
      final slice = await guard.sliceFor('mod.a', _snapshot());
      final device = slice['device']! as Map<String, Object?>;
      expect(device['model'], 'Xiaomi 14');
      expect(device['manufacturer'], 'Xiaomi');
    });

    test('单独授权安装标识：才出现 installId', () async {
      final before = await guard.sliceFor('mod.a', _snapshot());
      expect(before.toString().contains('install-secret-abc'), isFalse);

      await guard.grant('mod.a', SysCapability.appInstallId);
      final after = await guard.sliceFor('mod.a', _snapshot());
      expect(after.toString().contains('install-secret-abc'), isTrue);
    });

    test('授权内存与网络后对应切片出现', () async {
      await guard.grant('mod.a', SysCapability.memory);
      await guard.grant('mod.a', SysCapability.network);
      final slice = await guard.sliceFor('mod.a', _snapshot());
      expect(slice.containsKey('memory'), isTrue);
      expect(slice.containsKey('network'), isTrue);
      expect((slice['granted']! as List<Object?>).length, greaterThan(3));
    });

    test('切片列出已授予能力，便于 Mod 自我诊断', () async {
      final slice = await guard.sliceFor('mod.a', _snapshot());
      final granted = (slice['granted']! as List<Object?>).cast<String>();
      expect(granted, contains('deviceBasic'));
      expect(granted, isNot(contains('appInstallId')));
    });
  });
}
