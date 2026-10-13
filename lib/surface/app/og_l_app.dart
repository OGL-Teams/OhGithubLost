/// L3 展示级 · 应用外壳（App Shell）。
///
/// ## 它做四件事
/// 1. `MaterialApp` 组装（主题 / 标题 / 根 Navigator）；
/// 2. 全局错误呈现层 [OgLNoticeHost]（未捕获异常 → 弹窗；告警 → 横幅）；
/// 3. 文字缩放夹紧（0.85–2.0，防超大字号把布局挤碎）与键盘 inset 守卫；
/// 4. 把启动报告交给主壳（关于页展示"到底加载了什么"）。
///
/// ## 保守实现
/// - 主题：`surface.themeFor(系统亮度)`，唯一一次编译；
/// - 组件：全部 Material 3（不再有自绘 Kit / 自研滚动行为以外的定制）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../kernel/kernel.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import 'animations.dart';
import 'client_shell.dart';
import 'desktop_window.dart';
import 'error_surface.dart';
import 'keyboard_guard.dart';
import 'motion.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'shell', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 应用根。
class OgLApp extends StatelessWidget {
  /// 创建应用根。
  const OgLApp({required this.surface, required this.report, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告。
  final KernelReport report;

  /// 应用根 Navigator 的 key。
  ///
  /// 错误弹窗宿主（[OgLNoticeHost]）挂在 `MaterialApp.builder`，
  /// 该层 context 在 Navigator **之上**——`showDialog` 必须借这个 key 的
  /// context 才能工作（否则 critical 弹窗会抛 "does not include a Navigator"）。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          surface.settings,
          OgLI18n.instance,
        ]),
        builder: (BuildContext context, Widget? _) {
          final OgLSettings current = surface.settings.settings;
          return MaterialApp(
            title: 'OhGithubLost',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            // 界面语言：由 i18n 内核决定（JSON 分片）；系统组件文案交给 delegates。
            locale: ogLMaterialLocaleOf(OgLI18n.instance.locale),
            supportedLocales: ogLMaterialSupportedLocales(),
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // 桌面：鼠标 / 触控板可拖拽滚动（Flutter 默认只认触摸）。
            scrollBehavior: const OgLScrollBehavior(),
            // R7：主题切换也带动画（设置里换明暗/主题色时不再"硬切"）。
            // 档位质量表：主题切换影响面大 → 用「慢」档；低档位自动更短、0 档为 0。
            themeAnimationDuration: OgLAnim.slow(context),
            themeAnimationCurve: OgLAnim.curve(context),
            // 主题由桥缓存（含动效档位）；这里只读，不再每次 build 重新 copyWith。
            theme: surface.themeFor(
              MediaQuery.platformBrightnessOf(context),
              motionLevel: current.motionLevel,
            ),
            // ⚠️ 文字缩放必须在 `builder` 里覆盖：
            // 该层位于 `WidgetsApp` 自建的 MediaQuery **之内**，
            // 若在外层包 MediaQuery，会被 WidgetsApp 的 MediaQuery 覆盖掉。
            builder: (BuildContext context, Widget? child) {
              final MediaQueryData query = MediaQuery.of(context);
              // 系统字号 × 用户系数，再夹紧到 [0.85, 2.0]：
              // 既尊重系统无障碍设置，又允许用户再微调。
              final double systemScale = query.textScaler.scale(1.0);
              final double scale =
                  (systemScale * current.fontScale).clamp(0.85, 2.0).toDouble();
              return OgLMotionScope(
                level: current.motionLevel,
                child: MediaQuery(
                  data: query.copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations:
                        OgLMotion.disableAnimations(query, current),
                  ),
                  // 键盘 inset 守卫：无文本焦点时的"幽灵键盘"一律归零，
                  // 并把窗口指标写进日志（真机复现时"半屏从哪来"有第一手数据）。
                  child: OgLKeyboardGuard(
                    // 全局错误呈现层：未捕获异常 → 弹窗；一般告警 → 横幅。
                    child: OgLNoticeHost(
                      navigatorKey: navigatorKey,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
            // 桌面端：自绘标题栏（不用系统默认装饰）。
            // 非桌面平台 / 用户选择系统装饰时，本组件原样返回子组件。
            home: OgLWindowFrame(
              child: OgLClientShell(surface: surface, report: report),
            ),
          );
        },
      );
}

/// 启动被拒时的兜底界面。
///
/// **不静默降级**：引导清单签名失败 / 模块依赖不满足时，
/// 直接把原因摊开给用户，并说明"数据没有被改动"。
class OgLBootFailureApp extends StatelessWidget {
  /// 创建兜底界面。
  const OgLBootFailureApp({required this.message, super.key});

  /// 失败原因。
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        scrollBehavior: const OgLScrollBehavior(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // M5: 用 textTheme.titleLarge 替代硬编码 22/w6 —— 跟随系统
                    // fontScale 缩放（用户把字号拉到 130% 时这一行会一起变大，
                    // 旧实现钉死 22px 看起来不协调）。
                    Text(
                      _t('bootRejected'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(_t('dataUntouched')),
                    const SizedBox(height: 16),
                    SelectableText(
                      message,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// 把 i18n 语言代码映射为 Material `Locale`（`zh_TW` → `Locale('zh','TW')`）。
Locale ogLMaterialLocaleOf(String code) {
  final int sep = code.indexOf('_');
  if (sep > 0 && sep < code.length - 1) {
    return Locale(code.substring(0, sep), code.substring(sep + 1));
  }
  return Locale(code);
}

/// 应用支持的 locale 列表（与 `OgLI18n.locales` 严格一致）。
List<Locale> ogLMaterialSupportedLocales() => <Locale>[
      for (final OgLLocale item in OgLI18n.locales)
        ogLMaterialLocaleOf(item.code),
    ];

/// 滚动行为：桌面端允许"鼠标 / 触控板拖拽滚动"。
///
/// Flutter 默认只让**触摸**拖拽滚动，桌面用户拿鼠标拖列表是拖不动的——
/// 这是社区里最常见的"一眼看出是移动端套壳"的细节。
class OgLScrollBehavior extends MaterialScrollBehavior {
  /// 创建滚动行为。
  const OgLScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
