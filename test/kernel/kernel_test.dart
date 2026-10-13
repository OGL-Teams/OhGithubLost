/// 内核级测试套件。
///
/// 覆盖（对照 `docs/BOOT.md` §7 与 `docs/CONSISTENCY.md` 的测试要求）：
/// 1. 规范化 JSON 的确定性；
/// 2. Ed25519 清单签名：有效 / 篡改 / 伪造；
/// 3. 模块目录指纹：一致 / 内容被替换 / 目录缺失；
/// 4. 引导五阶段：正常 / 安全模式 / 拒绝启动 / 开发旁路 / schema 不受支持；
/// 5. 依赖容器、桥注册表、模块总线、生命周期（含失败回滚）；
/// 6. 内核端到端：装配、封存、就绪报告、停机。
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/boot/boot_fs.dart';
import 'package:ohgithublost/kernel/boot/boot_loader.dart';
import 'package:ohgithublost/kernel/boot/boot_manifest.dart';
import 'package:ohgithublost/kernel/boot/integrity_verifier.dart';
import 'package:ohgithublost/kernel/boot/trust_policy.dart';
import 'package:ohgithublost/kernel/boot/trust_warnings.dart';
import 'package:ohgithublost/kernel/bridge_registry.dart';
import 'package:ohgithublost/kernel/contract/module.dart';
import 'package:ohgithublost/kernel/di.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';
import 'package:ohgithublost/kernel/kernel.dart';
import 'package:ohgithublost/kernel/lifecycle.dart';
import 'package:ohgithublost/kernel/module_bus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 测试夹具
// ─────────────────────────────────────────────────────────────────────────────

/// 一个"模块"在磁盘上的形态（用于引导校验）。
class _ModuleSpec {
  const _ModuleSpec({
    required this.id,
    required this.layer,
    required this.path,
    required this.files,
  });

  final String id;
  final ModuleLayer layer;
  final String path;
  final Map<String, String> files;
}

/// 已签名的引导环境。
class _Fixture {
  _Fixture({
    required this.fs,
    required this.publicKey,
    required this.manifestPath,
  });

  final InMemoryBootFileSystem fs;
  final List<int> publicKey;
  final String manifestPath;
}

/// 引导测试台（启动层 + 告警收集器 + 诊断）。
class _Harness {
  _Harness({
    required this.loader,
    required this.warnings,
    required this.diagnostics,
  });

  final BootLoader loader;
  final TrustWarningCollector warnings;
  final KernelDiagnostics diagnostics;
}

Future<_Fixture> _buildFixture({
  required List<_ModuleSpec> specs,
  int schema = 1,
  bool corruptSignature = false,
}) async {
  final fs = InMemoryBootFileSystem();
  for (final spec in specs) {
    for (final file in spec.files.entries) {
      fs.writeText('${spec.path}/${file.key}', file.value);
    }
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();

  final entries = <Map<String, Object?>>[];
  for (final spec in specs) {
    final fingerprint =
        await BootIntegrityVerifier.directoryFingerprint(fs, spec.path);
    entries.add(<String, Object?>{
      'id': spec.id,
      'layer': spec.layer.key,
      'path': spec.path,
      'sha256': fingerprint,
      'version': '0.1.0',
    });
  }

  final payload = <String, Object?>{
    'schema': schema,
    'appVersion': '0.1.0',
    'buildId': 'test-build',
    'generatedAt': '2026-01-01T00:00:00Z',
    'modules': entries,
  };
  final signature = await algorithm.sign(
    utf8.encode(canonicalJsonEncode(payload)),
    keyPair: keyPair,
  );
  final signatureBase64 = corruptSignature
      ? base64.encode(List<int>.filled(signature.bytes.length, 0))
      : base64.encode(signature.bytes);

  const manifestPath = 'assets/boot/manifest.json';
  fs.writeText(
    manifestPath,
    jsonEncode(<String, Object?>{...payload, 'signature': signatureBase64}),
  );

  return _Fixture(
    fs: fs,
    publicKey: publicKey.bytes,
    manifestPath: manifestPath,
  );
}

_Harness _buildHarness(_Fixture fixture, {bool developmentBypass = false}) {
  final diagnostics = KernelDiagnostics(appVersion: '0.1.0');
  final warnings = TrustWarningCollector();
  return _Harness(
    loader: BootLoader(
      fileSystem: fixture.fs,
      verifier: BootIntegrityVerifier(
        fileSystem: fixture.fs,
        releasePublicKey: fixture.publicKey,
      ),
      diagnostics: diagnostics,
      warnings: warnings,
      manifestPath: fixture.manifestPath,
      developmentBypass: developmentBypass,
    ),
    warnings: warnings,
    diagnostics: diagnostics,
  );
}

List<_ModuleSpec> _defaultSpecs() => <_ModuleSpec>[
      _ModuleSpec(
        id: 'base.net',
        layer: ModuleLayer.base,
        path: 'lib/base/net',
        files: <String, String>{'net_engine.dart': 'class NetEngine {}'},
      ),
      _ModuleSpec(
        id: 'domain.api',
        layer: ModuleLayer.domain,
        path: 'lib/domain/api',
        files: <String, String>{'gh_api.dart': 'class GhApi {}'},
      ),
    ];

// ─────────────────────────────────────────────────────────────────────────────
// 测试替身模块
// ─────────────────────────────────────────────────────────────────────────────

class _FakeBridge {}

class _FakeModule extends OgLModule {
  _FakeModule({
    required this.id,
    required this.layer,
    this.requires = const <String>[],
    this.provides = const <String>[],
    this.failOnStart = false,
  });

  final String id;
  final ModuleLayer layer;
  final List<String> requires;
  final List<String> provides;
  final bool failOnStart;

  /// 生命周期调用轨迹（`register` / `start` / `stop`）。
  final List<String> trace = <String>[];

  @override
  ModuleDescriptor get descriptor => ModuleDescriptor(
        id: id,
        layer: layer,
        version: '1.0.0',
        requires: requires,
        provides: provides,
        description: '测试模块 $id',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    trace.add('register');
    if (id == 'base.net') {
      context.di.register<String>('net-engine');
      context.bridges.register('base', _FakeBridge());
    }
  }

  @override
  Future<void> onStart() async {
    trace.add('start');
    if (failOnStart) {
      throw StateError('$id 启动失败（测试注入）');
    }
  }

  @override
  Future<void> onStop() async {
    trace.add('stop');
  }
}

void main() {
  group('规范化 JSON', () {
    test('键按字典序、无空白、可重复', () {
      final value = <String, Object?>{
        'b': 1,
        'a': <Object?>[
          2,
          <String, Object?>{'d': true, 'c': 'x'},
        ],
      };
      const expected = '{"a":[2,{"c":"x","d":true}],"b":1}';
      expect(canonicalJsonEncode(value), expected);
      expect(canonicalJsonEncode(value), canonicalJsonEncode(value));
    });

    test('拒绝 NaN 与不支持的类型', () {
      expect(() => canonicalJsonEncode(double.nan), throwsFormatException);
      expect(
        () => canonicalJsonEncode(<Object?>[Object()]),
        throwsFormatException,
      );
    });
  });

  group('引导完整性（签名 + 指纹）', () {
    test('合法签名通过校验', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final manifest = BootManifest.fromJson(
        jsonDecode(fixture.fs.files[fixture.manifestPath] != null
            ? utf8.decode(fixture.fs.files[fixture.manifestPath]!)
            : '{}') as Map<String, Object?>,
      );
      final verifier = BootIntegrityVerifier(
        fileSystem: fixture.fs,
        releasePublicKey: fixture.publicKey,
      );
      expect(await verifier.verifySignature(manifest), isTrue);
    });

    test('负载被篡改后签名不再有效（防伪）', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final raw =
          utf8.decode(fixture.fs.files[fixture.manifestPath]!) as dynamic;
      final json = jsonDecode(raw) as Map<String, Object?>;
      // 篡改模块指纹，但保留原签名。
      final modules =
          (json['modules']! as List<Object?>).cast<Map<String, Object?>>();
      modules.first['sha256'] = 'deadbeef';
      final manifest = BootManifest.fromJson(json);
      final verifier = BootIntegrityVerifier(
        fileSystem: fixture.fs,
        releasePublicKey: fixture.publicKey,
      );
      expect(await verifier.verifySignature(manifest), isFalse);
    });

    test('目录指纹：一致 / 内容替换 / 目录缺失', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final manifest = BootManifest.fromJson(
        jsonDecode(utf8.decode(fixture.fs.files[fixture.manifestPath]!))
            as Map<String, Object?>,
      );
      final verifier = BootIntegrityVerifier(
        fileSystem: fixture.fs,
        releasePublicKey: fixture.publicKey,
      );

      final report = await verifier.verifyModules(manifest);
      expect(report.allPassed, isTrue);
      expect(report.verifiedCount, 2);

      // 替换文件内容 → 指纹失配
      fixture.fs.writeText('lib/base/net/net_engine.dart', 'class Tampered {}');
      final tampered = await verifier.verifyModules(manifest);
      expect(tampered.allPassed, isFalse);
      expect(tampered.failedModuleIds, contains('base.net'));

      // 目录整体缺失 → 视为失败
      final emptyFs = InMemoryBootFileSystem();
      final missingVerifier = BootIntegrityVerifier(
        fileSystem: emptyFs,
        releasePublicKey: fixture.publicKey,
      );
      final missing = await missingVerifier.verifyModules(manifest);
      expect(missing.failedModuleIds.length, 2);
    });
  });

  group('启动层五阶段', () {
    test('正常引导：通过、非安全模式、阶段完整', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final harness = _buildHarness(fixture);
      final result = await harness.loader.run();

      expect(result.succeeded, isTrue);
      expect(result.safeMode, isFalse);
      expect(result.excludedModules, isEmpty);
      expect(
        result.stages.map((stage) => stage.name).toList(),
        <String>[
          'boot.manifest',
          'boot.self_check',
          'boot.signature',
          'boot.modules',
          'boot.extensions',
          'boot.ready',
        ],
      );
      expect(harness.warnings.count, 0);
    });

    test('模块被篡改：安全模式 + 危险级告警', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      fixture.fs.writeText('lib/domain/api/gh_api.dart', 'class Evil {}');
      final harness = _buildHarness(fixture);
      final result = await harness.loader.run();

      expect(result.succeeded, isTrue);
      expect(result.safeMode, isTrue);
      expect(result.excludedModules, <String>['domain.api']);
      expect(harness.warnings.count, 1);
      expect(harness.warnings.mostSevere?.code,
          BootWarningCodes.moduleIntegrityFailed);
      expect(harness.warnings.hasDanger, isTrue);
    });

    test('签名无效：拒绝启动', () async {
      final fixture =
          await _buildFixture(specs: _defaultSpecs(), corruptSignature: true);
      final harness = _buildHarness(fixture);
      final result = await harness.loader.run();

      expect(result.succeeded, isFalse);
      expect(result.failureReason, contains('签名'));
      expect(harness.warnings.hasDanger, isTrue);
      expect(harness.diagnostics.errorCount, greaterThan(0));
    });

    test('schema 不受支持：拒绝启动', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs(), schema: 99);
      final harness = _buildHarness(fixture);
      final result = await harness.loader.run();

      expect(result.succeeded, isFalse);
      expect(result.failureReason, contains('自检'));
    });

    test('清单缺失：默认拒绝；开发旁路放行并告警', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final manifestPath = fixture.manifestPath;
      final fsWithoutManifest = InMemoryBootFileSystem();
      final strict = BootLoader(
        fileSystem: fsWithoutManifest,
        verifier: BootIntegrityVerifier(
          fileSystem: fsWithoutManifest,
          releasePublicKey: fixture.publicKey,
        ),
        diagnostics: KernelDiagnostics(),
        warnings: TrustWarningCollector(),
        manifestPath: manifestPath,
      );
      final strictResult = await strict.run();
      expect(strictResult.succeeded, isFalse);
      expect(strictResult.failureReason, contains('缺失'));

      final warnings = TrustWarningCollector();
      final devFs = InMemoryBootFileSystem();
      final dev = BootLoader(
        fileSystem: devFs,
        verifier: BootIntegrityVerifier(
          fileSystem: devFs,
          releasePublicKey: fixture.publicKey,
        ),
        diagnostics: KernelDiagnostics(),
        warnings: warnings,
        manifestPath: manifestPath,
        developmentBypass: true,
      );
      final devResult = await dev.run();
      expect(devResult.succeeded, isTrue);
      expect(warnings.count, greaterThan(0));
      for (final warning in warnings.warnings) {
        expect(warning.code, BootWarningCodes.developmentBypass);
      }
    });
  });

  group('信任策略', () {
    const policy = BootTrustPolicy();

    test('官方核心：locked + 强制签名', () {
      final decision = policy.evaluate(ExtensionKind.officialCore);
      expect(decision.tier, TrustTier.locked);
      expect(decision.requireSignature, isTrue);
      expect(decision.allowLoad, isTrue);
      expect(decision.mustWarnBus, isFalse);
    });

    test('第三方主题：不设限制且不告警', () {
      final decision = policy.evaluate(ExtensionKind.thirdPartyTheme);
      expect(decision.tier, TrustTier.open);
      expect(decision.allowLoad, isTrue);
      expect(decision.requireSignature, isFalse);
      expect(decision.mustWarnBus, isFalse);
    });

    test('第三方 Mod：放行但必须总线告警', () {
      final decision = policy.evaluate(ExtensionKind.thirdPartyMod);
      expect(decision.tier, TrustTier.warn);
      expect(decision.allowLoad, isTrue);
      expect(decision.mustWarnBus, isTrue);
      expect(policy.shouldWarn(ExtensionKind.thirdPartyMod), isTrue);
    });
  });

  group('依赖容器', () {
    test('注册 / 解析 / 标签 / 重复 / 未注册', () {
      final di = KernelDi();
      di.register<String>('a');
      di.register<String>('b', tag: 'second');
      expect(di.resolve<String>(), 'a');
      expect(di.resolve<String>(tag: 'second'), 'b');
      expect(di.tryResolve<int>(), isNull);
      expect(() => di.register<String>('dup'), throwsA(isA<KernelDiError>()));
      expect(() => di.resolve<int>(), throwsA(isA<KernelDiError>()));
      expect(di.contains<String>(), isTrue);
    });

    test('工厂惰性解析且只创建一次', () {
      final di = KernelDi();
      var created = 0;
      di.registerFactory<List<int>>((di) {
        created++;
        return <int>[1, 2, 3];
      });
      expect(di.resolve<List<int>>(), <int>[1, 2, 3]);
      expect(di.resolve<List<int>>(), <int>[1, 2, 3]);
      expect(created, 1);
    });

    test('封存后禁止注册', () {
      final di = KernelDi()..seal();
      expect(di.isSealed, isTrue);
      expect(() => di.register<String>('x'), throwsA(isA<KernelDiError>()));
    });
  });

  group('桥注册表', () {
    test('注册 / 解析 / 重复 / 类型不符 / 封存', () {
      final registry = KernelBridgeRegistry();
      registry.register<_FakeBridge>('base', _FakeBridge());
      expect(registry.resolve<_FakeBridge>('base'), isA<_FakeBridge>());
      expect(registry.isRegistered('base'), isTrue);
      expect(
        () => registry.register<_FakeBridge>('base', _FakeBridge()),
        throwsA(isA<KernelBridgeError>()),
      );
      expect(
        () => registry.resolve<String>('base'),
        throwsA(isA<KernelBridgeError>()),
      );
      expect(
        () => registry.resolve<_FakeBridge>('domain'),
        throwsA(isA<KernelBridgeError>()),
      );
      registry.seal();
      expect(
        () => registry.register<_FakeBridge>('surface', _FakeBridge()),
        throwsA(isA<KernelBridgeError>()),
      );
    });
  });

  group('模块总线', () {
    KernelModuleBus buildBus() => KernelModuleBus(
          di: KernelDi(),
          diagnostics: KernelDiagnostics(),
          bridges: KernelBridgeRegistry(),
        );

    test('拓扑排序：依赖先启动', () {
      final bus = buildBus();
      final api = _FakeModule(
        id: 'domain.api',
        layer: ModuleLayer.domain,
        requires: const <String>['base.net'],
      );
      final net = _FakeModule(id: 'base.net', layer: ModuleLayer.base);
      bus.register(api);
      bus.register(net);

      final order = bus.resolveOrder().map((m) => m.descriptor.id).toList();
      expect(order, <String>['base.net', 'domain.api']);
      expect(
          bus.toDependencyGraph(), contains('domain.api [domain] -> base.net'));
    });

    test('依赖缺失 / 循环依赖 / ID 重复 / 能力重复 / 描述符非法', () {
      final bus = buildBus();
      bus.register(_FakeModule(
        id: 'domain.api',
        layer: ModuleLayer.domain,
        requires: const <String>['base.net'],
      ));
      expect(() => bus.verify(), throwsA(isA<KernelModuleBusError>()));

      final cycleBus = buildBus();
      cycleBus.register(_FakeModule(
        id: 'base.net',
        layer: ModuleLayer.base,
        requires: const <String>['base.disk'],
      ));
      cycleBus.register(_FakeModule(
        id: 'base.disk',
        layer: ModuleLayer.base,
        requires: const <String>['base.net'],
      ));
      expect(() => cycleBus.verify(), throwsA(isA<KernelModuleBusError>()));

      final dupBus = buildBus();
      dupBus.register(_FakeModule(id: 'base.net', layer: ModuleLayer.base));
      expect(
        () => dupBus
            .register(_FakeModule(id: 'base.net', layer: ModuleLayer.base)),
        throwsA(isA<KernelModuleBusError>()),
      );

      final capBus = buildBus();
      capBus.register(_FakeModule(
        id: 'base.net',
        layer: ModuleLayer.base,
        provides: const <String>['net'],
      ));
      expect(
        () => capBus.register(_FakeModule(
          id: 'base.disk',
          layer: ModuleLayer.base,
          provides: const <String>['net'],
        )),
        throwsA(isA<KernelModuleBusError>()),
      );

      final badBus = buildBus();
      expect(
        () => badBus.register(_FakeModule(id: 'net', layer: ModuleLayer.base)),
        throwsA(isA<KernelModuleBusError>()),
      );
    });
  });

  group('生命周期', () {
    test('启动顺序 + 逆序停止', () async {
      final diagnostics = KernelDiagnostics();
      final lifecycle = KernelLifecycle(diagnostics: diagnostics);
      final net = _FakeModule(id: 'base.net', layer: ModuleLayer.base);
      final api = _FakeModule(
        id: 'domain.api',
        layer: ModuleLayer.domain,
        requires: const <String>['base.net'],
      );
      final bus = KernelModuleBus(
        di: KernelDi(),
        diagnostics: diagnostics,
        bridges: KernelBridgeRegistry(),
      )
        ..register(api)
        ..register(net);
      final ordered = bus.resolveOrder();
      final context = KernelContext(
        di: KernelDi(),
        diagnostics: diagnostics,
        bridges: KernelBridgeRegistry(),
        warnings: TrustWarningCollector(),
      );

      await lifecycle.registerAll(ordered, context);
      await lifecycle.startAll(ordered);
      expect(lifecycle.stateOf('base.net'), ModuleState.ready);
      expect(lifecycle.stateOf('domain.api'), ModuleState.ready);

      await lifecycle.stopAll();
      expect(net.trace, <String>['register', 'start', 'stop']);
      expect(api.trace, <String>['register', 'start', 'stop']);
      expect(lifecycle.stateOf('domain.api'), ModuleState.stopped);
    });

    test('启动失败：已启动模块逆序回滚', () async {
      final diagnostics = KernelDiagnostics();
      final lifecycle = KernelLifecycle(diagnostics: diagnostics);
      final net = _FakeModule(id: 'base.net', layer: ModuleLayer.base);
      final api = _FakeModule(
        id: 'domain.api',
        layer: ModuleLayer.domain,
        requires: const <String>['base.net'],
        failOnStart: true,
      );
      final bus = KernelModuleBus(
        di: KernelDi(),
        diagnostics: diagnostics,
        bridges: KernelBridgeRegistry(),
      )
        ..register(api)
        ..register(net);
      final ordered = bus.resolveOrder();
      final context = KernelContext(
        di: KernelDi(),
        diagnostics: diagnostics,
        bridges: KernelBridgeRegistry(),
        warnings: TrustWarningCollector(),
      );

      await lifecycle.registerAll(ordered, context);
      await expectLater(
        lifecycle.startAll(ordered),
        throwsA(isA<KernelStartupError>()),
      );
      expect(net.trace.contains('stop'), isTrue);
      expect(lifecycle.stateOf('domain.api'), ModuleState.failed);
    });
  });

  group('内核端到端', () {
    test('装配 / 封存 / 报告 / 停机', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final harness = _buildHarness(fixture);
      final kernel = OgLKernel(
        diagnostics: harness.diagnostics,
        bootLoader: harness.loader,
        appVersion: '0.1.0',
      );

      final net = _FakeModule(id: 'base.net', layer: ModuleLayer.base);
      final api = _FakeModule(
        id: 'domain.api',
        layer: ModuleLayer.domain,
        requires: const <String>['base.net'],
      );

      final report = await kernel.boot(<OgLModule>[api, net]);

      expect(kernel.isRunning, isTrue);
      expect(report.safeMode, isFalse);
      expect(report.moduleStates['base.net'], ModuleState.ready.name);
      expect(report.moduleStates['domain.api'], ModuleState.ready.name);
      expect(report.bridges, <String>['base']);
      expect(report.services, contains('String'));
      expect(report.moduleGraph, contains('domain.api'));
      expect(kernel.di.resolve<String>(), 'net-engine');

      // 装配完成后容器封存：禁止再注册。
      expect(kernel.di.isSealed, isTrue);
      expect(kernel.bridges.isSealed, isTrue);
      expect(kernel.bus.isSealed, isTrue);

      // 重复 boot 必须拒绝。
      await expectLater(
        kernel.boot(<OgLModule>[net]),
        throwsA(isA<KernelBootException>()),
      );

      await kernel.shutdown();
      expect(kernel.isRunning, isFalse);
      expect(net.trace, contains('stop'));
    });

    test('清单声明的模块未被提供 → 留痕 OGL-BOOT-108（不静默通过）', () async {
      // 5.0 由一次性一致性探针发现的缺口：清单里有、运行期没给 → 以前静默通过。
      final fixture = await _buildFixture(specs: _defaultSpecs());
      final harness = _buildHarness(fixture);
      final kernel = OgLKernel(
        diagnostics: harness.diagnostics,
        bootLoader: harness.loader,
      );

      // 只提供 base.net：清单声明的 domain.api 故意不给。
      final report = await kernel.boot(<OgLModule>[
        _FakeModule(id: 'base.net', layer: ModuleLayer.base),
      ]);

      expect(report.safeMode, isFalse, reason: '这是装配缺失，不是完整性失败');
      expect(
        harness.diagnostics.logTail.any(
          (KernelLogEntry entry) => entry.code == 'OGL-BOOT-108',
        ),
        isTrue,
        reason: '必须留下「清单声明但装配缺失」的事件码',
      );
    });

    test('安全模式下被排除模块不参与装配', () async {
      final fixture = await _buildFixture(specs: _defaultSpecs());
      fixture.fs.writeText('lib/domain/api/gh_api.dart', 'class Evil {}');
      final harness = _buildHarness(fixture);
      final kernel = OgLKernel(
        diagnostics: harness.diagnostics,
        bootLoader: harness.loader,
      );

      final net = _FakeModule(id: 'base.net', layer: ModuleLayer.base);
      final api = _FakeModule(id: 'domain.api', layer: ModuleLayer.domain);

      final report = await kernel.boot(<OgLModule>[net, api]);

      expect(kernel.safeMode, isTrue);
      expect(report.safeMode, isTrue);
      expect(report.moduleStates.containsKey('domain.api'), isFalse);
      expect(report.moduleStates['base.net'], ModuleState.ready.name);
      expect(report.trustWarnings, isNotEmpty);
    });
  });
}
