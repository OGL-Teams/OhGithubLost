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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'surface/app/web_install.dart';
import 'surface/app/web_pointer.dart';
import 'surface/i18n/og_l_i18n.dart';
import 'surface/surface_bridge.dart';

/// 应用版本（零外部资源：不读 pubspec，直接内联常量）。
///
/// 与 `pubspec.yaml` 的 `version:` 保持一致，发布流程会做一致性校验。
const String kOgLAppVersion = '6.5.0';

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
  // 把 localStorage 失败注入到 OgLAppLog：保持 base → surface 反转，
  //   不破坏分层。
  final bootstrap = await baseLayerModulesOnPlatform(
    onStorageFailure: (String message) {
      OgLAppLog.instance.add('存储', message, severity: OgLNoticeSeverity.warning);
    },
  );

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
    // ★ Web 专属接线（安装到桌面 / 加速服务首启说明）。非 Web 构建里
    //   `_ogLScheduleWebSurface` 立即返回，不会产生任何副作用。
    _ogLScheduleWebSurface(surfaceModule.bridge);
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

/// 当前平台名（诊断日志用；**规范化**为小写标识，如 `web` / `ios` / `macos`）。
///
/// 这里刻意**不使用 `dart:io` 的 `Platform`**：Web 上它不存在（编译不过），
/// 而 Flutter 的 `kIsWeb` + `defaultTargetPlatform` 在两端都可靠。
/// 浏览器里 `defaultTargetPlatform` 反映的是**宿主系统**，因此先判 `kIsWeb`。
String _ogLPlatformName() {
  if (kIsWeb) {
    return 'web';
  }
  return defaultTargetPlatform.name.toLowerCase();
}

/// `common` 分片文案（启动期对话框用；此时展示层已把 i18n 载入完成）。
String _ogLCommon(String key) => OgLI18n.instance.t('common', key);

/// `shell` 分片文案（Web 鼠标交互说明用）。
String _ogLShell(String key) => OgLI18n.instance.t('shell', key);

/// Web 专属接线：安装提示监听 + 启动后的一次性提示。
///
/// **非 Web 构建里本函数立即返回**，不注册监听、不弹窗（`kIsWeb` 在原生构建
/// 里是编译期常量 `false`，整段会被摇掉）。两个浏览器动作的实现见
/// `surface/app/web_install.dart` / `web_install_web.dart`（Web 用 `dart:js_interop`）。
void _ogLScheduleWebSurface(SurfaceBridge bridge) {
  if (!kIsWeb) {
    return;
  }
  // ① 尽早挂 `beforeinstallprompt` 监听：Chromium 至多派发一次，错过就没有了。
  //    这里只负责"抓住事件"，何时询问用户由下面的启动流程决定。
  ogLWebInstallWatch(() {});
  // ② 右键菜单：Web 版把「右键」接管为返回，浏览器自带的右键菜单必须先关掉
  //    （本 SDK 默认是开的：`BrowserContextMenu.enabled` 默认 true）。
  unawaited(BrowserContextMenu.disableContextMenu());
  // ③ 首帧之后再谈界面：此时根 Navigator 与 i18n 都已就绪。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_ogLShowWebStartupDialogs(bridge));
  });
}

/// 取根 Navigator 的 context（应用刚起来时可能还差一两帧，故做有限重试）。
Future<BuildContext?> _ogLRootContext() async {
  for (int attempt = 0; attempt < 10; attempt++) {
    final BuildContext? context = OgLApp.navigatorKey.currentContext;
    if (context != null) {
      return context;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return OgLApp.navigatorKey.currentContext;
}

/// Web 启动后的两个一次性/每次提示（顺序：先说明加速，再问安装）。
Future<void> _ogLShowWebStartupDialogs(SurfaceBridge bridge) async {
  final BuildContext? context = await _ogLRootContext();
  if (context == null) {
    // 拿不到 context 就如实留痕（不静默）；下次打开再试。
    OgLAppLog.instance.add(
      'Web',
      '启动提示未能展示：根 Navigator 尚未就绪',
      severity: OgLNoticeSeverity.warning,
    );
    return;
  }
  final OgLWebStartup startup = bridge.webStartup;
  // ① **首次打开**：说明"需要配置加速服务"（只弹一次；不配置也能用）。
  if (!startup.accelNoticeShown) {
    await startup.markAccelNoticeShown();
    if (!context.mounted) {
      return;
    }
    await _ogLShowAccelNotice(context);
  }
  // ② **首次检测到鼠标**：说明 Web 版的鼠标交互（只弹一次）。
  if (ogLWebFinePointer() && !startup.mouseNoticeShown) {
    await startup.markMouseNoticeShown();
    if (!context.mounted) {
      return;
    }
    await _ogLShowMouseNotice(context);
  }
  // ③ **每次打开**：按设置询问是否添加到桌面（默认开）。
  if (!startup.installPromptEnabled) {
    return;
  }
  // 已安装（standalone）→ 任何路径都不再提示。
  if (ogLWebInstallStandalone()) {
    return;
  }
  final OgLWebInstallPlatform platform = ogLWebInstallPlatform();
  if (platform == OgLWebInstallPlatform.unsupported) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  await _ogLShowInstallPrompt(context, platform);
}

/// 「需要配置加速服务」说明（Web 首次打开弹一次）。
///
/// 文案必须说清三件事：**不配置也能用**、**只是下载走直连**、
/// **入口在 设置 → 网络 → 加速**。
Future<void> _ogLShowAccelNotice(BuildContext context) => showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        // 正文较长：窄屏上允许滚动，避免溢出。
        scrollable: true,
        title: Text(_ogLCommon('webAccelNoticeTitle')),
        content: Text(_ogLCommon('webAccelNoticeBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_ogLCommon('confirm')),
          ),
        ],
      ),
    );

/// 「检测到鼠标」说明（Web 版只弹一次）。
///
/// 说清三件事：**右键 = 返回**、长按左键 = 长按菜单、单击 = 点按；
/// 触摸手势已禁用。弹窗本身**不接受返回**（`PopScope(canPop: false)`）：
/// 右键返回不该把说明自己关掉 —— 那会变成"刚弹出就消失"。
Future<void> _ogLShowMouseNotice(BuildContext context) => showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true,
          title: Text(_ogLShell('webMouseNoticeTitle')),
          content: Text(_ogLShell('webMouseNoticeBody')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_ogLCommon('confirm')),
            ),
          ],
        ),
      ),
    );

/// 「添加到桌面」提示。两条路径的差异见函数体。
Future<void> _ogLShowInstallPrompt(
  BuildContext context,
  OgLWebInstallPlatform platform,
) async {
  if (platform == OgLWebInstallPlatform.ios) {
    // iOS Safari **没有** `beforeinstallprompt`（平台限制，不是实现取舍）：
    // 只能显示"共享 → 添加到主屏幕"的手动引导，绝不做成一键安装的样子。
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(_ogLCommon('webInstallDialogTitle')),
        content: Text(_ogLCommon('webInstallIosBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_ogLCommon('close')),
          ),
        ],
      ),
    );
    return;
  }
  // Chromium：等 `beforeinstallprompt` 到来（通常首帧后几百毫秒内）。
  final bool canPrompt = await _ogLWaitInstallEvent();
  if (!context.mounted) {
    return;
  }
  // 有事件 → 可"一键安装"；没有事件（本轮不满足可安装条件 / 事件已错过）
  // → **如实给手动引导**，而不是给一个点了没反应的按钮。
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(_ogLCommon('webInstallDialogTitle')),
      content: Text(
        canPrompt
            ? _ogLCommon('webInstallDialogBody')
            : _ogLCommon('webInstallChromiumBody'),
      ),
      actions: canPrompt
          ? <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_ogLCommon('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(_ogLCommon('confirm')),
              ),
            ]
          : <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_ogLCommon('close')),
              ),
            ],
    ),
  );
  if (!canPrompt || confirmed != true) {
    return;
  }
  // 用户点了"添加"才真正调起浏览器安装弹窗；结果如实记入日志。
  final String outcome = await ogLWebInstallPrompt();
  OgLAppLog.instance.add('Web', '添加到桌面：浏览器返回=$outcome');
}

/// 等 `beforeinstallprompt`（最多约 3 秒）。返回是否已拿到可用的安装事件。
Future<bool> _ogLWaitInstallEvent() async {
  for (int attempt = 0; attempt < 10; attempt++) {
    if (ogLWebInstallCanPrompt()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return ogLWebInstallCanPrompt();
}
