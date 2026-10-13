/// 引导完整性校验器：**Ed25519 清单签名** + **模块目录指纹**。
///
/// 威胁模型（见 `docs/BOOT.md（该文件未落地，以源码为准）` §6）：防御"打包后被注入/替换模块文件"、
/// "伪造扩展冒充官方模块"；不防御持有调试能力者的重打包。
///
/// 指纹算法（确定性，必须与构建脚本一致）：
/// 1. 递归列出模块目录内全部文件，按相对路径排序；
/// 2. 逐文件计算 `sha256(文件内容)`；
/// 3. 拼接每一行 `相对路径 + '\u0000' + 文件哈希 + '\n'`；
/// 4. 对拼接结果取 `sha256` 作为目录指纹。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../contract/module.dart';
import 'boot_fs.dart';
import 'boot_manifest.dart';

/// 单个模块的完整性结果。
class ModuleIntegrityResult {
  /// 创建结果。
  const ModuleIntegrityResult({
    required this.entry,
    required this.ok,
    this.actualSha256,
    this.reason,
  });

  /// 对应的清单条目。
  final BootModuleEntry entry;

  /// 是否通过校验。
  final bool ok;

  /// 实际计算的目录指纹（目录不存在时为 `null`）。
  final String? actualSha256;

  /// 失败原因（通过时为 `null`）。
  final String? reason;

  @override
  String toString() =>
      '${entry.id}: ${ok ? 'OK' : 'FAILED${reason == null ? '' : ' ($reason)'}'}';
}

/// 完整性报告。
class IntegrityReport {
  /// 创建报告。
  const IntegrityReport({required this.results, required this.signatureValid});

  /// 全部模块结果。
  final List<ModuleIntegrityResult> results;

  /// 清单签名是否有效。
  final bool signatureValid;

  /// 失败条目。
  List<ModuleIntegrityResult> get failures =>
      results.where((result) => !result.ok).toList();

  /// 是否全部通过。
  bool get allPassed => failures.isEmpty;

  /// 通过数量。
  int get verifiedCount => results.where((result) => result.ok).length;

  /// 失败模块 ID 列表。
  List<String> get failedModuleIds =>
      failures.map((result) => result.entry.id).toList();

  @override
  String toString() =>
      'IntegrityReport(verified=$verifiedCount/${results.length}, '
      'failures=$failedModuleIds, signatureValid=$signatureValid)';
}

/// 引导完整性校验器。
class BootIntegrityVerifier {
  /// 创建校验器。
  ///
  /// [releasePublicKey] 为 32 字节 Ed25519 公钥（由发布流程持有私钥签名）。
  BootIntegrityVerifier({
    required this.fileSystem,
    required List<int> releasePublicKey,
  }) : releasePublicKey = List<int>.unmodifiable(releasePublicKey);

  /// Ed25519 公钥长度（字节）。
  static const int ed25519PublicKeyLength = 32;

  /// 文件系统。
  final BootFileSystem fileSystem;

  /// 发布公钥。
  final List<int> releasePublicKey;

  final Ed25519 _ed25519 = Ed25519();

  /// 校验清单签名（覆盖 `canonicalPayloadBytes()`）。
  Future<bool> verifySignature(BootManifest manifest) async {
    final signatureBase64 = manifest.signature;
    if (signatureBase64 == null || signatureBase64.isEmpty) {
      return false;
    }
    if (releasePublicKey.length != ed25519PublicKeyLength) {
      return false;
    }
    List<int> signatureBytes;
    try {
      signatureBytes = base64.decode(signatureBase64);
    } on FormatException {
      return false;
    }
    try {
      final publicKey = SimplePublicKey(
        releasePublicKey,
        type: KeyPairType.ed25519,
      );
      final signature = Signature(signatureBytes, publicKey: publicKey);
      return await _ed25519.verify(
        manifest.canonicalPayloadBytes(),
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  /// 校验全部（或指定层级的）模块条目。
  Future<IntegrityReport> verifyModules(
    BootManifest manifest, {
    Set<ModuleLayer>? layers,
    bool signatureValid = false,
  }) async {
    final results = <ModuleIntegrityResult>[];
    for (final entry in manifest.modules) {
      if (layers != null &&
          (entry.layer == null || !layers.contains(entry.layer))) {
        continue;
      }
      results.add(await verifyModule(entry));
    }
    return IntegrityReport(results: results, signatureValid: signatureValid);
  }

  /// 校验单个模块条目。
  Future<ModuleIntegrityResult> verifyModule(BootModuleEntry entry) async {
    if (!entry.isWellFormed) {
      return ModuleIntegrityResult(
        entry: entry,
        ok: false,
        reason: '清单条目不完整（缺少 id/layer/path/sha256/version）',
      );
    }
    final actual = await directoryFingerprint(fileSystem, entry.path);
    if (actual == null) {
      return ModuleIntegrityResult(
        entry: entry,
        ok: false,
        reason: '模块目录不存在或为空: ${entry.path}',
      );
    }
    final ok = actual == entry.sha256;
    return ModuleIntegrityResult(
      entry: entry,
      ok: ok,
      actualSha256: actual,
      reason: ok ? null : '指纹不匹配（期望 ${entry.sha256}，实际 $actual）',
    );
  }

  /// 计算目录指纹；目录不存在或为空返回 `null`。
  static Future<String?> directoryFingerprint(
    BootFileSystem fileSystem,
    String directory,
  ) async {
    final base = directory.endsWith('/')
        ? directory.substring(0, directory.length - 1)
        : directory;
    final files = await fileSystem.listFilesRecursive(base);
    if (files.isEmpty) {
      return null;
    }
    final buffer = StringBuffer();
    for (final relativePath in files) {
      final bytes = await fileSystem.readBytes('$base/$relativePath');
      if (bytes == null) {
        // 列出后消失（并发删除/篡改）：一律视为校验失败。
        return null;
      }
      buffer.write(relativePath);
      buffer.write('\u0000');
      buffer.write(hashBytes(bytes));
      buffer.write('\n');
    }
    return hashBytes(utf8.encode(buffer.toString()));
  }

  /// 计算字节的 SHA-256（小写十六进制）。
  static String hashBytes(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}
