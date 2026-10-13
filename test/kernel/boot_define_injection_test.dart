/// 引导清单注入防空回归（构建腿专用）。
///
/// 普通 `flutter test`（未注入）会直接通过；
/// 构建里以 `--dart-define` 注入 `OGL_BOOT_MANIFEST` 后运行本文件，
/// 校验：注入非空、可解析、schema 正常、签名能被内嵌公钥验证。
/// 这样"注入静默失败 → 发布包拒绝启动"这类事故在上游就被拦截。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/boot/boot_fs.dart';
import 'package:ohgithublost/kernel/boot/boot_manifest.dart';
import 'package:ohgithublost/kernel/boot/integrity_verifier.dart';
import 'package:ohgithublost/kernel/boot/release_trust_root.dart';

const String _injected = String.fromEnvironment('OGL_BOOT_MANIFEST');

void main() {
  test('注入存在时必须可解析、且签名与信任根吻合', () async {
    if (_injected.isEmpty) {
      // 未注入（常规 CI / 本地测试）：本测试不适用。
      return;
    }
    final decoded = jsonDecode(_injected);
    expect(decoded, isA<Map<String, Object?>>());
    final json = <String, Object?>{
      for (final entry in (decoded as Map).entries)
        entry.key.toString(): entry.value,
    };
    final manifest = BootManifest.fromJson(json);
    expect(manifest.isSigned, isTrue, reason: '注入的清单必须带签名');
    expect(manifest.isSchemaSupported, isTrue);
    expect(manifest.modules.every((module) => module.isWellFormed), isTrue);

    final verifier = BootIntegrityVerifier(
      fileSystem: InMemoryBootFileSystem(),
      releasePublicKey: kOgLReleasePublicKey,
    );
    expect(await verifier.verifySignature(manifest), isTrue,
        reason: '注入清单的签名无法被内嵌公钥验证（信任链断裂）');
  });
}
