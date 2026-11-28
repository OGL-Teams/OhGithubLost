/// L0 内核级 · 启动层（BootLoader）：五阶段引导序列。
///
/// ```
/// Stage 0 清单自检  ▸ schema 版本与条目合法性
/// Stage 1 签名校验  ▸ Ed25519（公钥内嵌）
/// Stage 2 模块校验  ▸ base/domain/surface 官方模块目录指纹（BL 锁）
/// Stage 3 扩展策略  ▸ 主题不设限 / Mod 放行 +总线告警
/// Stage 4 就绪上报  ▸ 阶段耗时、告警清单、安全模式标记
/// ```
///
/// 语义约定：
/// - **拒绝启动**（签名无效 / 清单损坏 / schema 不支持）返回 `succeeded == false`，
///   由内核抛出 `KernelBootException`；
/// - **安全模式**（部分官方模块被排除）返回 `succeeded == true && safeMode == true`，
///   被排除模块的 ID 由 `excludedModules` 给出，内核据此过滤模块清单。
library;

import 'dart:convert';

import '../diagnostics.dart';
import 'boot_fs.dart';
import 'boot_manifest.dart';
import 'integrity_verifier.dart';
import 'trust_policy.dart';
import 'trust_warnings.dart';

/// 一个引导阶段的执行结果。
class BootStage {
  /// 创建阶段结果。
  const BootStage({
    required this.name,
    required this.ok,
    required this.duration,
    this.detail,
  });

  /// 阶段名（`boot.self_check` / `boot.signature` / …）。
  final String name;

  /// 是否通过。
  final bool ok;

  /// 耗时。
  final Duration duration;

  /// 补充说明（失败原因等）。
  final String? detail;

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'ok': ok,
        'ms': duration.inMicroseconds / 1000,
        if (detail != null) 'detail': detail,
      };

  @override
  String toString() =>
      '$name ${duration.inMilliseconds}ms${ok ? '' : ' FAILED${detail == null ? '' : ' ($detail)'}'}';
}

/// 引导结果。
class BootResult {
  /// 创建结果。
  const BootResult({
    required this.succeeded,
    required this.safeMode,
    required this.stages,
    required this.trustWarnings,
    this.manifest,
    this.integrity,
    this.failureReason,
    this.excludedModules = const <String>[],
  });

  /// 是否允许继续启动。
  final bool succeeded;

  /// 是否进入安全模式（存在被排除的官方模块）。
  final bool safeMode;

  /// 阶段结果（按执行顺序）。
  final List<BootStage> stages;

  /// 本次引导产生的信任告警（**必须**被 UI 触达，见 docs/COLD_START.md）。
  final List<BootTrustWarning> trustWarnings;

  /// 引导清单（拒绝启动时为 `null`）。
  final BootManifest? manifest;

  /// 完整性报告（拒绝启动时为 `null`）。
  final IntegrityReport? integrity;

  /// 拒绝启动的原因。
  final String? failureReason;

  /// 被拒绝装载的模块 ID。
  final List<String> excludedModules;

  /// 是否被拒绝启动。
  bool get isRefused => !succeeded;

  /// 各阶段耗时合计。
  Duration get totalDuration =>
      stages.fold(Duration.zero, (total, stage) => total + stage.duration);

  /// 单行摘要（日志与测试断言用）。
  String toSummary() {
    final buffer = StringBuffer()
      ..write('BootResult(succeeded=$succeeded, safeMode=$safeMode, ')
      ..write('stages=${stages.length}, ')
      ..write('warnings=${trustWarnings.length}, ')
      ..write('total=${totalDuration.inMilliseconds}ms');
    if (failureReason != null) {
      buffer.write(', reason=$failureReason');
    }
    if (excludedModules.isNotEmpty) {
      buffer.write(', excluded=$excludedModules');
    }
    buffer.write(')');
    return buffer.toString();
  }

  @override
  String toString() => toSummary();
}

/// 启动层。
class BootLoader {
  /// 创建启动层。
  ///
  /// [developmentBypass] 仅用于调试构建：允许清单缺失 / 未签名清单继续启动，
  /// 但**必然**产生一条 `OGL-BOOT-107` 告警，且在发布构建中必须为 `false`。
  BootLoader({
    required this.fileSystem,
    required this.verifier,
    required this.diagnostics,
    required this.warnings,
    this.policy = const BootTrustPolicy(),
    this.manifestPath = 'assets/boot/manifest.json',
    this.developmentBypass = false,
    this.deferModuleIntegrity = false,
  });

  /// 文件系统（校验模块指纹用）。
  final BootFileSystem fileSystem;

  /// 完整性校验器。
  final BootIntegrityVerifier verifier;

  /// 诊断中枢。
  final KernelDiagnostics diagnostics;

  /// 信任告警收集器。
  final TrustWarningCollector warnings;

  /// 信任策略。
  final BootTrustPolicy policy;

  /// 引导清单路径（相对应用根）。
  final String manifestPath;

  /// 是否启用开发旁路（调试构建专用）。
  final bool developmentBypass;

  /// 是否**延后** Stage 2（官方模块完整性校验）到首帧之后。
  ///
  /// 为什么：Stage 2 要逐文件算 sha256（清单声明模块条目时是真实磁盘 I/O），
  /// 放在首帧前会拖慢冷启动。延后的信任语义（见 [verifyDeferredModules]）：
  /// **延后 ≠ 跳过**——校验失败时组合根必须用失败界面替换正常功能，
  /// 比"安全模式"更严格（模块已装配、无法事后排除，因此直接拒绝）。
  final bool deferModuleIntegrity;

  /// 最近一次 [run] 的清单签名结论（`verifyDeferredModules` 复用；内部状态）。
  bool _signatureValid = false;

  /// 对扩展种类作出信任裁决（消费层装载 Mod / 主题时调用）。
  TrustDecision evaluateExtension(ExtensionKind kind) => policy.evaluate(kind);

  /// 执行五阶段引导序列。
  Future<BootResult> run() async {
    final stages = <BootStage>[];

    // ── Stage 0（读取）:引导清单 ────────────────────────────────────────
    final readWatch = Stopwatch()..start();
    final bytes = await fileSystem.readBytes(manifestPath);
    readWatch.stop();

    BootManifest manifest;
    if (bytes == null) {
      if (!developmentBypass) {
        stages.add(BootStage(
          name: 'boot.manifest',
          ok: false,
          duration: readWatch.elapsed,
          detail: '清单缺失: $manifestPath',
        ));
        return _refuse(
          stages,
          reason: '引导清单缺失: $manifestPath',
          code: BootWarningCodes.manifestMissing,
          severity: TrustSeverity.danger,
          subject: 'manifest',
        );
      }
      diagnostics.warn(
        'BOOT',
        '开发旁路：引导清单缺失，跳过完整性校验',
        code: BootWarningCodes.developmentBypass,
      );
      warnings.report(
        code: BootWarningCodes.developmentBypass,
        subject: 'manifest',
        severity: TrustSeverity.info,
        message: '开发旁路已启用：跳过引导清单签名与模块指纹校验（仅调试构建可用）',
      );
      stages.add(BootStage(
        name: 'boot.manifest',
        ok: true,
        duration: readWatch.elapsed,
        detail: '开发旁路（清单缺失）',
      ));
      manifest = BootManifest.empty();
      _deferredManifest = manifest;
    } else {
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) {
          throw const FormatException('清单根节点必须是对象');
        }
        final json = <String, Object?>{};
        for (final entry in decoded.entries) {
          json[entry.key.toString()] = entry.value;
        }
        manifest = BootManifest.fromJson(json);
        _deferredManifest = manifest;
        stages.add(BootStage(
          name: 'boot.manifest',
          ok: true,
          duration: readWatch.elapsed,
        ));
      } catch (error) {
        stages.add(BootStage(
          name: 'boot.manifest',
          ok: false,
          duration: readWatch.elapsed,
          detail: '解析失败: $error',
        ));
        return _refuse(
          stages,
          reason: '引导清单解析失败: $error',
          code: BootWarningCodes.manifestMissing,
          severity: TrustSeverity.danger,
          subject: 'manifest',
        );
      }
    }

    // ── Stage 0（自检）:schema 与条目合法性 ─────────────────────────────
    final selfCheckWatch = Stopwatch()..start();
    final selfCheckOk =
        manifest.isSchemaSupported && manifest.malformedModuleCount == 0;
    selfCheckWatch.stop();
    stages.add(BootStage(
      name: 'boot.self_check',
      ok: selfCheckOk,
      duration: selfCheckWatch.elapsed,
      detail: selfCheckOk
          ? 'schema=${manifest.schema}, modules=${manifest.modules.length}'
          : 'schema=${manifest.schema}（支持 ≤$kSupportedManifestSchema）, '
              '非法条目=${manifest.malformedModuleCount}',
    ));
    if (!selfCheckOk) {
      return _refuse(
        stages,
        reason: '引导清单自检失败（schema 不受支持或条目损坏）',
        code: BootWarningCodes.manifestMissing,
        severity: TrustSeverity.danger,
        subject: 'manifest',
      );
    }

    // ── Stage 1:清单签名 ───────────────────────────────────────────────
    final signatureWatch = Stopwatch()..start();
    final signatureValid = await verifier.verifySignature(manifest);
    signatureWatch.stop();
    stages.add(BootStage(
      name: 'boot.signature',
      ok: signatureValid,
      duration: signatureWatch.elapsed,
      detail: signatureValid ? null : '签名无效或缺失',
    ));
    if (!signatureValid) {
      if (!developmentBypass) {
        return _refuse(
          stages,
          reason: '引导清单签名校验失败（应用可能被篡改）',
          code: BootWarningCodes.manifestSignatureInvalid,
          severity: TrustSeverity.danger,
          subject: 'manifest',
        );
      }
      diagnostics.warn(
        'BOOT',
        '开发旁路：清单未签名或签名无效，继续启动',
        code: BootWarningCodes.developmentBypass,
      );
      warnings.report(
        code: BootWarningCodes.developmentBypass,
        subject: 'manifest',
        severity: TrustSeverity.info,
        message: '开发旁路已启用：跳过清单签名校验（仅调试构建可用）',
      );
    }

    // ── Stage 2:官方模块完整性（BL 锁） ────────────────────────────────
    // 延后模式（deferModuleIntegrity）：本阶段**只登记耗时为 0 的占位结论**，
    // 逐文件 sha256 的真实校验移到首帧后的 [verifyDeferredModules]。
    // 这是性能取舍，不是信任降级——组合根必须消费 [verifyDeferredModules]
    // 的结果并用失败界面阻断正常功能（详见该方法注释）。
    // 三个结论变量对两条路径（即时 / 延后）统一收口，Stage 4 只看这里。
    IntegrityReport? integrity;
    final excluded = <String>[];
    bool safeMode = false;
    if (deferModuleIntegrity) {
      _signatureValid = signatureValid;
      stages.add(BootStage(
        name: 'boot.modules',
        ok: true,
        duration: Duration.zero,
        detail: '延后校验：清单 ${manifest.modules.length} 个模块条目'
            '（首帧后逐文件指纹比对，失败将阻断进入正常功能）',
      ));
    } else {
      final integrityWatch = Stopwatch()..start();
      integrity = await verifier.verifyModules(
        manifest,
        signatureValid: signatureValid,
      );
      integrityWatch.stop();
      stages.add(BootStage(
        name: 'boot.modules',
        ok: integrity.allPassed,
        duration: integrityWatch.elapsed,
        detail: integrity.allPassed
            // ★ 清单没有模块条目时，本阶段是**没有校验对象**，不是「都验过了」。
            //   核心模块是 AOT 编译产物，运行时没有目录文件可指纹比对
            //   （见 tool/boot_manifest.py 的说明）。这里如实写出来，
            //   避免日志被读成「模块完整性已校验」。
            ? (manifest.modules.isEmpty
                ? '清单未声明模块条目：本阶段无校验对象（见 tool/boot_manifest.py）'
                : '${integrity.verifiedCount} 个模块通过')
            : '失败: ${integrity.failedModuleIds.join(', ')}',
      ));

      for (final failure in integrity.failures) {
        excluded.add(failure.entry.id);
        diagnostics.error(
          'BOOT',
          '官方模块完整性校验失败，拒绝装载: ${failure.entry.id}',
          code: BootWarningCodes.moduleIntegrityFailed,
          data: <String, Object?>{
            'path': failure.entry.path,
            'expected': failure.entry.sha256,
            'actual': failure.actualSha256,
            'reason': failure.reason,
          },
        );
        warnings.report(
          code: BootWarningCodes.moduleIntegrityFailed,
          subject: 'module:${failure.entry.id}',
          severity: TrustSeverity.danger,
          message: '官方模块完整性校验失败，已拒绝装载并进入安全模式'
              '（${failure.reason ?? '未知原因'}）',
          data: <String, Object?>{
            'path': failure.entry.path,
            'expected': failure.entry.sha256,
            'actual': failure.actualSha256,
          },
        );
      }
      safeMode = excluded.isNotEmpty;
    } // ── Stage 3:扩展策略登记 ───────────────────────────────────────────
    final policyWatch = Stopwatch()..start();
    final themeDecision = policy.evaluate(ExtensionKind.thirdPartyTheme);
    final modDecision = policy.evaluate(ExtensionKind.thirdPartyMod);
    policyWatch.stop();
    stages.add(BootStage(
      name: 'boot.extensions',
      ok: true,
      duration: policyWatch.elapsed,
      detail: '主题=${themeDecision.tier.name}（告警=${themeDecision.mustWarnBus}）, '
          'Mod=${modDecision.tier.name}（告警=${modDecision.mustWarnBus}）',
    ));

    // ── Stage 4:就绪上报 ───────────────────────────────────────────────
    final readyWatch = Stopwatch()..start();
    readyWatch.stop();
    stages.add(BootStage(
      name: 'boot.ready',
      ok: true,
      duration: readyWatch.elapsed,
      detail: safeMode ? '安全模式（排除 ${excluded.length} 个模块）' : null,
    ));

    diagnostics.info(
      'BOOT',
      '引导完成',
      code: 'OGL-BOOT-001',
      data: <String, Object?>{
        'safeMode': safeMode,
        'excluded': excluded,
        'warnings': warnings.count,
        'signatureValid': signatureValid,
      },
    );

    return BootResult(
      succeeded: true,
      safeMode: safeMode,
      manifest: manifest,
      // 延后模式下首帧前的结论是"尚未校验"（null）——组合根必须随后调用
      // [verifyDeferredModules] 补上，绝不允许把 null 当"通过"展示。
      integrity: deferredIntegrity,
      stages: List<BootStage>.unmodifiable(stages),
      trustWarnings: warnings.warnings,
      excludedModules: List<String>.unmodifiable(excluded),
    );
  }

  /// 延后模式下首帧前的完整性结论（恒 `null`；非延后模式无意义）。
  ///
  /// 组合根用它区分"还没校验"与"校验通过"：`BootResult.integrity == null`
  /// 且 [deferModuleIntegrity] 为真时，**必须**在展示正常功能前完成
  /// [verifyDeferredModules]。
  static IntegrityReport? get deferredIntegrity => null;

  /// 最近一次 [run] 的引导清单（延后校验用）。
  BootManifest? _deferredManifest;

  /// 首帧后补做官方模块完整性校验（[deferModuleIntegrity] 的下半场）。
  ///
  /// **信任语义（延后 ≠ 跳过，fail-closed）**：
  /// - 校验**通过** → 组合根放行正常功能；
  /// - 校验**失败** → 与首帧前失败不同：模块此刻**已经装配进总线**，无法事后
  ///   "排除重装"，因此组合根必须用 `OgLBootFailureApp` **替换**正常界面
  ///   （比安全模式更严格的 fail-closed）；
  /// - 校验**异常**（IO/解码崩溃）→ 等同失败：指纹算不出来 = 无法证明完整，
  ///   宁可误拒也不能放过篡改。
  ///
  /// 结果经 `diagnostics.error` + `warnings.report`（OGL-BOOT-102）触达
  /// 既有通知链，并回传 `IntegrityReport?`（null = 该次引导不是延后模式，
  /// 调用方没有职责）供组合根裁决。
  Future<IntegrityReport?> verifyDeferredModules() async {
    if (!deferModuleIntegrity) {
      return null;
    }
    // 清单与签名结论来自最近一次 run()；_signatureValid 为 false 时
    // verifyModules 的逐条结论不变，但"指纹通过 + 签名无效"这种组合
    // 在 run() 里本就拒绝启动（非旁路），到不了这里。
    final manifest = _deferredManifest;
    if (manifest == null) {
      return null;
    }
    final IntegrityReport integrity;
    try {
      integrity = await verifier.verifyModules(
        manifest,
        signatureValid: _signatureValid,
      );
    } catch (error) {
      // 异常 = 校验没有完成 = 不能证明完整：fail-closed。
      diagnostics.error(
        'BOOT',
        '延后完整性校验未完成（视为失败，fail-closed）：$error',
        code: BootWarningCodes.moduleIntegrityFailed,
      );
      warnings.report(
        code: BootWarningCodes.moduleIntegrityFailed,
        subject: 'module:*',
        severity: TrustSeverity.danger,
        message: '延后完整性校验未完成（$error）；按失败处理，功能已被阻断',
      );
      return null;
    }
    // 正常路径：逐条上报（与首帧前路径同一事件码 / 通知链），再回传统计。
    for (final failure in integrity.failures) {
      diagnostics.error(
        'BOOT',
        '官方模块完整性校验失败（延后，已阻断进入正常功能）: ${failure.entry.id}',
        code: BootWarningCodes.moduleIntegrityFailed,
        data: <String, Object?>{
          'path': failure.entry.path,
          'expected': failure.entry.sha256,
          'actual': failure.actualSha256,
          'reason': failure.reason,
        },
      );
      warnings.report(
        code: BootWarningCodes.moduleIntegrityFailed,
        subject: 'module:${failure.entry.id}',
        severity: TrustSeverity.danger,
        message: '官方模块完整性校验失败（延后校验）：应用已阻断进入正常功能'
            '（${failure.reason ?? '未知原因'}）',
        data: <String, Object?>{
          'path': failure.entry.path,
          'expected': failure.entry.sha256,
          'actual': failure.actualSha256,
        },
      );
    }
    diagnostics.info(
      'BOOT',
      '延后完整性校验完成',
      code: 'OGL-BOOT-001',
      data: <String, Object?>{
        'verified': integrity.verifiedCount,
        'total': integrity.results.length,
        'allPassed': integrity.allPassed,
      },
    );
    return integrity;
  }

  BootResult _refuse(
    List<BootStage> stages, {
    required String reason,
    required String code,
    required TrustSeverity severity,
    required String subject,
  }) {
    diagnostics.error(
      'BOOT',
      '引导拒绝启动: $reason',
      code: code,
      data: <String, Object?>{'manifestPath': manifestPath},
    );
    warnings.report(
      code: code,
      subject: subject,
      severity: severity,
      message: reason,
    );
    return BootResult(
      succeeded: false,
      safeMode: false,
      stages: List<BootStage>.unmodifiable(stages),
      trustWarnings: warnings.warnings,
      failureReason: reason,
    );
  }
}
