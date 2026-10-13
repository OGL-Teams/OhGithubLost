/// 发布信任链测试：固定签名样本 ↔ 内嵌公钥 ↔ 启动校验，一条链端到端。
///
/// 私钥**不再随仓库保管**（移至 GitHub Actions Secret `OGL_BOOT_KEY`），
/// 因此这里用"固定签名样本"做足三项检查：
/// 1. **信任根锁定**：内嵌公钥必须能验证样本（样本由发布私钥签出）——
///    任何一边被改动（换密钥、改规范化）都会在这里变红；
/// 2. **签名机制**：另用临时密钥对走一遍 签→验 全链（不依赖仓库内私钥）；
/// 3. **启动链**：样本清单 + 旁路关闭 = 干净启动；篡改 = 拒绝启动。
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/boot/boot_fs.dart';
import 'package:ohgithublost/kernel/boot/boot_loader.dart';
import 'package:ohgithublost/kernel/boot/boot_manifest.dart';
import 'package:ohgithublost/kernel/boot/integrity_verifier.dart';
import 'package:ohgithublost/kernel/boot/release_trust_root.dart';
import 'package:ohgithublost/kernel/boot/trust_warnings.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

const String _fixturePath =
    'test/kernel/fixtures/release_key_signed_manifest.json';
const String _manifestPath = 'boot/manifest.json';

Map<String, Object?> _loadFixture() {
  final File file = File(_fixturePath);
  expect(file.existsSync(), isTrue, reason: '固定签名样本缺失: $_fixturePath');
  final Object? decoded = jsonDecode(file.readAsStringSync());
  expect(decoded, isA<Map<String, dynamic>>());
  return (decoded! as Map<String, dynamic>).cast<String, Object?>();
}

Map<String, Object?> _payload() => <String, Object?>{
      'schema': 1,
      'appVersion': '0.0.0-test',
      'buildId': 'chain-test',
      'generatedAt': '2026-01-01T00:00:00Z',
      'modules': <Object?>[],
      'coreDigest': 'test-digest',
    };

void main() {
  test('信任根锁定：固定签名样本必须能被内嵌公钥验证', () async {
    final Map<String, Object?> fixture = _loadFixture();
    final BootManifest manifest = BootManifest.fromJson(fixture);
    expect(manifest.isSigned, isTrue, reason: '样本必须带签名');

    final verifier = BootIntegrityVerifier(
      fileSystem: InMemoryBootFileSystem(),
      releasePublicKey: kOgLReleasePublicKey,
    );
    expect(
      await verifier.verifySignature(manifest),
      isTrue,
      reason: '样本与内嵌公钥不匹配（信任根脱节，或轮换后未同步样本）',
    );
  });

  test('签名机制：临时密钥对可完成 签→验 全链', () async {
    final SimpleKeyPair keyPair = await Ed25519().newKeyPair();
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();

    final Map<String, Object?> payload = _payload();
    final List<int> message = utf8.encode(canonicalJsonEncode(payload));
    final Signature signature = await Ed25519().sign(message, keyPair: keyPair);

    final BootManifest manifest = BootManifest.fromJson(<String, Object?>{
      ...payload,
      'signature': base64.encode(signature.bytes),
    });
    final verifier = BootIntegrityVerifier(
      fileSystem: InMemoryBootFileSystem(),
      releasePublicKey: publicKey.bytes,
    );
    expect(await verifier.verifySignature(manifest), isTrue);
  });

  test('启动链：样本清单 + 旁路关闭 = 干净启动（零告警）', () async {
    final Map<String, Object?> fixture = _loadFixture();

    final InMemoryBootFileSystem fs = InMemoryBootFileSystem();
    fs.writeText(_manifestPath, jsonEncode(fixture));

    final TrustWarningCollector warnings = TrustWarningCollector();
    final loader = BootLoader(
      fileSystem: fs,
      verifier: BootIntegrityVerifier(
        fileSystem: fs,
        releasePublicKey: kOgLReleasePublicKey,
      ),
      diagnostics: KernelDiagnostics(appVersion: 'test'),
      warnings: warnings,
      manifestPath: _manifestPath,
      developmentBypass: false,
    );

    final result = await loader.run();
    expect(result.succeeded, isTrue);
    expect(result.safeMode, isFalse);
    expect(warnings.count, 0, reason: '正式启动不允许产生任何信任告警');
  });

  test('启动链：清单被篡改 = 拒绝启动', () async {
    final Map<String, Object?> fixture = _loadFixture();

    // 篡改：换了 appVersion，签名保持原样 → 必须拒绝。
    final Map<String, Object?> tampered = <String, Object?>{
      ...fixture,
      'appVersion': '9.9.9-evil',
    };
    final InMemoryBootFileSystem fs = InMemoryBootFileSystem();
    fs.writeText(_manifestPath, jsonEncode(tampered));

    final loader = BootLoader(
      fileSystem: fs,
      verifier: BootIntegrityVerifier(
        fileSystem: fs,
        releasePublicKey: kOgLReleasePublicKey,
      ),
      diagnostics: KernelDiagnostics(appVersion: 'test'),
      warnings: TrustWarningCollector(),
      manifestPath: _manifestPath,
      developmentBypass: false,
    );

    final result = await loader.run();
    expect(result.succeeded, isFalse);
    expect(result.failureReason, contains('签名'));
  });
}
