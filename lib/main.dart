/// OGL 应用入口。
///
/// ## 这个文件做三件事
/// 1. **组装四层**：`baseLayerModules()` + `domainLayerModules()` + `SurfaceLayerModule`
///    （顺序即拓扑：L1 → L2 → L3，内核会自己校验依赖）；
/// 2. **零外部资源启动**：引导清单**不读文件、不落盘**——
///    仓库里没有任何 `assets/`，所以清单只能是"缺失"或"由发布流程注入"。
///    调试构建允许缺失（`developmentBypass`，必然产生 `OGL-BOOT-107` 告警）；
///    发布构建要求清单已签名，否则**拒绝启动**（这是信任链条的第一环）。
/// 3. **把启动结果交给 UI**：[OgLApp] 会展示启动报告与信任告警，
///    用户第一次打开就能看见"到底加载了什么"。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'base/base_bootstrap.dart';
import 'base/log/log_dirs.dart';
import 'domain/domain_bridge.dart';
import 'kernel/boot/boot_fs.dart';
import 'kernel/boot/boot_loader.dart';
import 'kernel/boot/integrity_verifier.dart';
import 'kernel/boot/release_trust_root.dart';
import 'kernel/boot/trust_policy.dart';
import 'kernel/boot/trust_warnings.dart';
import 'kernel/contract/module.dart';
import 'kernel/diagnostics.dart';
import 'kernel/kernel.dart';
import 'kernel/log/og_l_log_file.dart';
import 'surface/app/error_surface.dart';
import 'surface/app/og_l_app.dart';
import 'surface/app/permission_selftest.dart';
import 'surface/surface_bridge.dart';

/// 应用版本（零外部资源：不读 pubspec，直接内联常量）。
///
/// 与 `pubspec.yaml` 的 `version:` 保持一致，发布流程会做一致性校验。
const String kOgLAppVersion = '7.4.0';

/// 发布构建注入的引导清单 JSON（由 `--dart-define-from-file` 提供；调试构建为空）。
///
/// 零外部资源：清单不落盘、不进 assets，直接编译进二进制；
/// 由 CI（`tool/boot_manifest.py`）生成并 Ed25519 签名，见 `.github/signing/`。
const String kOgLBootManifestJson = String.fromEnvironment('OGL_BOOT_MANIFEST');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ── 日志落盘：**任何后续日志都必须先能写盘** ──────────────────────────
  // 候选顺序：sdcard/logging → 应用外部目录 → 文档目录 → 支持目录；
  // 全失败也不静默——把原因写进内存日志（关于页可见）。
  await OgLLogFile.init(
    candidates: await ogLLogDirectoryCandidates(),
    appVersion: kOgLAppVersion,
    buildMode: kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug'),
    platform: _ogLPlatformName(),
  );
  // 平台与版本：`dart:io` 的 `Platform.operatingSystemVersion` 在 Web 上不存在，
  // 而诊断日志真正需要的是"哪个平台"这一项，因此这里只写规范化后的平台名
  // （web / android / ios / linux / macos / windows），**不编造**系统版本号。
  OgLAppLog.instance.add(
    '启动',
    '进程启动：版本=$kOgLAppVersion 平台=${_ogLPlatformName()}',
  );
  if (!OgLLogFile.isEnabled) {
    OgLAppLog.instance.add(
      '日志',
      '日志落盘不可用（尝试过：${OgLLogFile.triedDirectories.join(' | ')}；'
          '最后错误：${OgLLogFile.lastError}）',
      severity: OgLNoticeSeverity.critical,
    );
  }

  // ── 全局错误捕获：任何未捕获异常都必须"被看见"，不许无声消失 ──────────
  // 1) Flutter 框架异常（构建/布局/绘制）：先走默认呈现（控制台），
  //    再上报全局通知中心 → 由 OgLNoticeHost 弹窗给用户。
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    // 框架异常连**堆栈与上下文**一起落盘：这是排查"界面全空"唯一的线索。
    OgLLogFile.line('崩溃', details.toString(), level: 'ERR');
    OgLNoticeCenter.instance.report(
      title: '界面异常',
      detail: details.exceptionAsString(),
      severity: OgLNoticeSeverity.critical,
      delivery: OgLNoticeDelivery.inAppOnly,
    );
  };
  // 2) 平台/异步未捕获异常：返回 true 表示"已处理"（已呈现给用户），
  //    避免被框架静默吞掉。
  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stack) {
    OgLLogFile.line('崩溃', '未捕获异常：$error\n$stack', level: 'ERR');
    OgLNoticeCenter.instance.report(
      title: '未捕获异常',
      detail: error.toString(),
      severity: OgLNoticeSeverity.critical,
      delivery: OgLNoticeDelivery.inAppOnly,
    );
    return true;
  };

  final diagnostics = KernelDiagnostics(appVersion: kOgLAppVersion);
  final warnings = TrustWarningCollector();

  // ★ 通知系统贯穿全局：把内核诊断的 error 与引导层信任告警转发到通知中心，
  //   这样"任何一层"的告警都能触达用户，而不是只躺在日志里。
  diagnostics.addSink(const OgLDiagnosticsNoticeSink());
  warnings.addSink(const OgLTrustNoticeSink());

  // ★ R11：系统「减少动效 / 开发者选项 → 动画缩放」被关闭时，应用内的过渡与
  //   反馈动画会**静默消失**（此前应用不给任何提示，用户会以为"应用没做好"）。
  //   这里在启动时检测一次并提交通知中心（告警级 → 横幅），绝不静默。
  try {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    if (features.disableAnimations) {
      OgLNoticeCenter.instance.report(
        title: '系统已关闭动画',
        detail: '检测到系统已关闭动画（常见于「开发者选项 → 动画程序时长缩放」'
            '或「无障碍 → 移除动画」）。应用内的页面切换与控件反馈动画将不可见，'
            '但功能不受影响。如需动画，请在系统设置中重新开启。',
        severity: OgLNoticeSeverity.warning,
      );
    }
  } catch (error) {
    // 读取无障碍设置失败也要留痕（不允许静默降级）。
    OgLAppLog.instance.add(
      '启动',
      '读取系统无障碍设置失败（无法判断动画是否被关闭）：$error',
      severity: OgLNoticeSeverity.warning,
    );
  }

  // ★ 零外部资源的关键一步：
  // 引导文件系统完全在内存里，仓库不含任何 assets 文件。
  // 发布构建时把 CI 签名好的清单（经 `--dart-define-from-file` 注入）
  // 写入内存文件系统；调试构建允许缺失（开发旁路 + OGL-BOOT-107 告警）。
  final bootFileSystem = InMemoryBootFileSystem();
  // 发布构建必须携带已签名清单（CI 注入）；缺失 = 拒绝启动，不静默降级。
  final hasSignedManifest = kOgLBootManifestJson.isNotEmpty;
  if (hasSignedManifest) {
    bootFileSystem.writeText('boot/manifest.json', kOgLBootManifestJson);
  }

  final kernel = OgLKernel(
    diagnostics: diagnostics,
    appVersion: kOgLAppVersion,
    bootLoader: BootLoader(
      fileSystem: bootFileSystem,
      verifier: BootIntegrityVerifier(
        fileSystem: bootFileSystem,
        // 发布信任根：内嵌 Ed25519 公钥（私钥仅 CI 持有，见 `.github/signing/`）。
        releasePublicKey: kOgLReleasePublicKey,
      ),
      diagnostics: diagnostics,
      warnings: warnings,
      policy: const BootTrustPolicy(),
      manifestPath: 'boot/manifest.json',
      // 开发旁路**仅对调试构建开放**：发布构建缺清单 / 签名无效 = 拒绝启动。
      developmentBypass: !hasSignedManifest && !kReleaseMode,
    ),
  );

  // 展示层模块单独持有，方便拿到装配好的桥（避免依赖内核内部结构）。
  final surfaceModule = SurfaceLayerModule();

  // ★ 组合根：装配 L1 —— 解析平台存储（登录 / 设置 / 缓存真正落盘）；
  // 失败退回内存并把错误原样带上来（下面大声上报，绝不静默）。
  final bootstrap = await baseLayerModulesOnPlatform();

  final List<OgLModule> modules = <OgLModule>[
    ...bootstrap.modules,
    ...domainLayerModules(),
    surfaceModule,
  ];

  try {
    OgLAppLog.instance.step('启动', '内核引导（${modules.length} 个模块）…');
    final report = await kernel.boot(modules);
    OgLAppLog.instance.result(
      '启动',
      '内核引导完成',
      '模块 ${report.moduleStates.length} 项 / 告警 ${report.trustWarnings.length} 条 / '
          '阶段 ${report.stages.length} 个 / 安全模式=${report.safeMode}',
    );
    for (final Object warning in report.trustWarnings) {
      OgLAppLog.instance.add(
        '启动',
        '信任告警：$warning',
        severity: OgLNoticeSeverity.warning,
      );
    }
    final storageError = bootstrap.storageError;
    if (storageError != null) {
      // 不静默：进应用级日志（关于页可见），并弹窗提醒。
      OgLAppLog.instance.add(
        '存储',
        '平台存储不可用，本次会话不保存任何数据：$storageError',
        severity: OgLNoticeSeverity.critical,
      );
      OgLNoticeCenter.instance.report(
        title: '存储不可用',
        detail: '平台存储初始化失败，登录与设置将无法保存到本机。\n$storageError',
        severity: OgLNoticeSeverity.critical,
      );
    }
    // ★ 5.0：权限网关**每次启动**都实测一遍（不只是首次引导那一次）。
    //   只复核、不弹窗（重新请求交给引导页 / 设置页）；缺什么、影响什么、
    //   怎么修 → 诊断日志 + 通知中心（**带事件码** OGL-PERM-00x）。
    //   加超时兜底：权限查询走平台通道，绝不允许它拖住启动。
    OgLAppLog.instance.step('启动', '权限自检（每次启动）…');
    try {
      await ogLRunPermissionSelfTest(
        diagnostics: diagnostics,
        storageProbe: surfaceModule.bridge.ensureStorage,
        storageLocation: surfaceModule.bridge.appStoragePath,
      ).timeout(const Duration(seconds: 5));
    } catch (error) {
      // 自检超时 / 异常也要留痕，且不阻断启动（宁可漏报，不可不放行）。
      OgLLogFile.line('权限', '权限自检未完成（超时或异常）：$error', level: 'WARN');
      OgLAppLog.instance.add(
        '权限',
        '权限自检未完成：$error',
        severity: OgLNoticeSeverity.warning,
      );
    }
    OgLAppLog.instance.result('启动', '进入界面（runApp）', '启动报告已就绪');
    runApp(OgLApp(surface: surfaceModule.bridge, report: report));
  } on KernelBootException catch (error) {
    // 启动被拒（清单签名失败 / 模块依赖不满足）：**不静默降级**，
    // 直接把原因摊给用户看——这是数据安全产品该有的态度。
    OgLAppLog.instance.add(
      '启动',
      '内核拒绝启动：$error',
      severity: OgLNoticeSeverity.critical,
    );
    runApp(OgLBootFailureApp(message: error.toString()));
  } catch (error, stackTrace) {
    // 兜底：任何**未预期**的装配 / 启动异常也必须可见——绝不允许白屏。
    OgLLogFile.line(
      '崩溃',
      '启动流程未捕获异常：$error\n$stackTrace',
      level: 'ERR',
    );
    OgLAppLog.instance.add(
      '启动',
      '启动流程异常：$error',
      severity: OgLNoticeSeverity.critical,
    );
    runApp(OgLBootFailureApp(
      message: '启动流程出现未预期异常：$error\n\n$stackTrace',
    ));
  }
}

/// 当前平台名（诊断日志用；**规范化**为小写标识，如 `android` / `linux` / `windows`）。
///
/// 这里刻意**不使用 `dart:io` 的 `Platform`**，只用 Flutter 的
/// `defaultTargetPlatform`（Web 检查已随 Web 支持一并移除）。
String _ogLPlatformName() {
  return defaultTargetPlatform.name.toLowerCase();
}

