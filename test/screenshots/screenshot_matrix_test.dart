/// OGL · UI 截屏矩阵（供手动 CI 生成"全平台截屏"构建产物）。
///
/// ## 两种运行模式
/// - **默认（普通 `flutter test`）**：只跑一次"冒烟截屏"（不落盘）——
///   验证字体加载 / 假件 bridge / 捕获管线可用；
/// - **截屏模式（`OGL_SCREENSHOTS=1`）**：输出两份样本并落盘：
///   `build/ui_shots/portrait__home.png`（竖屏 390×844）与
///   `build/ui_shots/landscape__repo.png`（横屏 844×390）。
///   （历史上做过 5 平台 × 亮暗 × 形态的完整矩阵版，按需可再扩展。）
///
/// ## 离线假件
/// 用内存存储 + 脚本化传输组装**真实**的 DomainBridge/SurfaceBridge，
/// 不联网、不依赖真机；渲染的是与应用同一条 Flutter 渲染管线的真实页面。
///
/// ## 字体
/// 从 Flutter SDK 缓存（`$FLUTTER_ROOT/bin/cache/artifacts/material_fonts`）
/// 加载 Roboto / MaterialIcons 真字形；否则测试环境会用占位字形（方块）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/disk/disk_store.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';
import 'package:ohgithublost/domain/domain_bridge.dart';
import 'package:ohgithublost/domain/gh/gh_api.dart';
import 'package:ohgithublost/domain/gh/gh_auth.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';
import 'package:ohgithublost/domain/gh/gh_models.dart';
import 'package:ohgithublost/domain/ix/ix_notify.dart';
import 'package:ohgithublost/domain/ix/ix_session.dart';
import 'package:ohgithublost/domain/ix/ix_task.dart';
import 'package:ohgithublost/domain/sys/sys_access.dart';
import 'package:ohgithublost/domain/sys/sys_info.dart';
import 'package:ohgithublost/kernel/boot/boot_loader.dart';
import 'package:ohgithublost/kernel/boot/trust_warnings.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';
import 'package:ohgithublost/kernel/kernel.dart';
import 'package:ohgithublost/surface/pages/about_page.dart';
import 'package:ohgithublost/surface/pages/dashboard_page.dart';
import 'package:ohgithublost/surface/pages/login_page.dart';
import 'package:ohgithublost/surface/pages/repo_page.dart';
import 'package:ohgithublost/surface/pages/settings_page.dart';
import 'package:ohgithublost/surface/settings.dart';
import 'package:ohgithublost/surface/surface_bridge.dart';
import 'package:ohgithublost/surface/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 配置
// ─────────────────────────────────────────────────────────────────────────────

/// 是否落盘（手动 CI 设 `OGL_SCREENSHOTS=1`）。
final bool kWriteShots = Platform.environment['OGL_SCREENSHOTS'] == '1';

/// 输出根目录。
final String kOutRoot =
    Platform.environment['OGL_SCREENSHOT_DIR'] ?? 'build/ui_shots';

// ─────────────────────────────────────────────────────────────────────────────
// 字体加载
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _loadRealFonts() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    debugPrint('[截屏] 未发现 FLUTTER_ROOT，跳过真字体加载（字形可能为占位）');
    return;
  }
  final String fontDir = '$root/bin/cache/artifacts/material_fonts';
  if (!Directory(fontDir).existsSync()) {
    debugPrint('[截屏] 未发现字体缓存目录：$fontDir（字形可能为占位）');
    return;
  }
  await _loadFamily(
    'Roboto',
    <String>['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'],
    fontDir,
  );
  await _loadFamily(
    'MaterialIcons',
    <String>['MaterialIcons-Regular.otf'],
    fontDir,
  );
  debugPrint('[截屏] 真字体已加载：Roboto + MaterialIcons ($fontDir)');
}

Future<void> _loadFamily(
  String family,
  List<String> names,
  String dir,
) async {
  final FontLoader loader = FontLoader(family);
  bool any = false;
  for (final String name in names) {
    final File file = File('$dir/$name');
    if (!file.existsSync()) {
      continue;
    }
    final Uint8List bytes = file.readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    any = true;
  }
  if (any) {
    await loader.load();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 离线假件（脚本化传输 + 内存存储 → 真实桥）
// ─────────────────────────────────────────────────────────────────────────────

Map<String, Object?> _repoJson({
  required String fullName,
  required String description,
  required bool isPrivate,
  required int stars,
}) {
  final List<String> parts = fullName.split('/');
  return <String, Object?>{
    'id': fullName.hashCode.abs(),
    'name': parts.last,
    'full_name': fullName,
    'private': isPrivate,
    'owner': <String, Object?>{'login': parts.first, 'id': 1},
    'description': description,
    'default_branch': 'main',
    'stargazers_count': stars,
    'forks_count': 42,
    'watchers_count': stars,
    'open_issues_count': 7,
    'language': 'Dart',
    'size': 1024,
    'updated_at': '2026-10-02T00:00:00Z',
    'fork': false,
    'archived': false,
    'html_url': 'https://github.com/$fullName',
    'has_pages': true,
  };
}

/// 脚本化传输：只认少数路由，其余 404（页面不会去碰）。
class _ScriptedTransport implements NetTransport {
  @override
  Future<NetResponse> send(NetRequest request) async {
    final String path = Uri.parse(request.url).path;
    Object? body;
    if (path == '/user/repos') {
      body = <Map<String, Object?>>[
        _repoJson(
          fullName: 'octocat/Hello-World',
          description: '演示仓库 · 用于 UI 截屏',
          isPrivate: false,
          stars: 1234,
        ),
        _repoJson(
          fullName: 'octocat/ogl-private',
          description: '私有仓库示例',
          isPrivate: true,
          stars: 3,
        ),
        _repoJson(
          fullName: 'OGL-Teams/OhGithubLost',
          description: '全能 GitHub 仓库管理器（Flutter 全平台）',
          isPrivate: false,
          stars: 88,
        ),
      ];
    } else if (path == '/repos/octocat/Hello-World/contents/' ||
        path == '/repos/octocat/Hello-World/contents') {
      body = <Map<String, Object?>>[
        <String, Object?>{
          'name': 'lib',
          'path': 'lib',
          'type': 'dir',
          'sha': 'dir-sha-1',
          'size': 0,
        },
        <String, Object?>{
          'name': 'test',
          'path': 'test',
          'type': 'dir',
          'sha': 'dir-sha-2',
          'size': 0,
        },
        <String, Object?>{
          'name': 'README.md',
          'path': 'README.md',
          'type': 'file',
          'sha': 'file-sha-1',
          'size': 320,
        },
        <String, Object?>{
          'name': 'pubspec.yaml',
          'path': 'pubspec.yaml',
          'type': 'file',
          'sha': 'file-sha-2',
          'size': 240,
        },
      ];
    } else if (path == '/repos/octocat/Hello-World/contents/README.md') {
      const String markdown = '# OhGithubLost\n\n'
          '演示 README（截屏数据）。\n\n'
          '- 全平台构建\n'
          '- Material 3 界面\n\n'
          '```dart\nvoid main() => runApp(const OgLApp());\n```\n';
      body = <String, Object?>{
        'name': 'README.md',
        'path': 'README.md',
        'type': 'file',
        'sha': 'file-sha-1',
        'size': markdown.length,
        'content': base64Encode(utf8.encode(markdown)),
        'encoding': 'base64',
        'html_url':
            'https://github.com/octocat/Hello-World/blob/main/README.md',
      };
    } else {
      return const NetResponse(
        statusCode: 404,
        body: '{"message":"Not Found"}',
        duration: Duration(milliseconds: 1),
      );
    }
    return NetResponse(
      statusCode: 200,
      body: jsonEncode(body),
      duration: const Duration(milliseconds: 6),
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

/// 组装真实桥（内存存储 +脚本化网络；不依赖任何平台插件）。
Future<SurfaceBridge> _buildBridge() async {
  final InMemoryVault vault = InMemoryVault();
  final InMemoryKv kv = InMemoryKv();
  final GhAuthService auth = GhAuthService(vault: vault, store: kv);
  await auth.saveAccount(
    const GhAccount(id: 'user-1', login: 'octocat', name: 'Octo Cat'),
    const GhToken('ghp_demo_demo_demo_demo'),
  );
  await auth.switchTo('user-1');
  final GhClient client = GhClient(
    net: NetBridge(transport: _ScriptedTransport(), observer: NetObserver()),
    auth: auth,
  );
  final GhApi api = GhApi(client: client);
  final IxSession session = IxSession(auth: auth, store: kv);
  final IxTaskRunner tasks = IxTaskRunner();
  final IxNotificationCenter notifications = IxNotificationCenter();
  final SysInfoService sysInfo = SysInfoService();
  final SysAccessGuard sysAccess = SysAccessGuard(store: kv);
  final DomainBridge domain = DomainBridge(
    auth: auth,
    api: api,
    client: client,
    session: session,
    tasks: tasks,
    notifications: notifications,
    sysInfo: sysInfo,
    sysAccess: sysAccess,
  );
  final OgLSettingsController settings = OgLSettingsController(
    persistence: OgLInMemorySettingsPersistence(),
  );
  await settings.load();
  return SurfaceBridge(settings: settings, domain: domain, net: null);
}

/// 演示用启动报告（关于页需要）。
KernelReport _report() => KernelReport(
      generatedAt: DateTime(2026, 10, 2),
      appVersion: '1.1.0',
      safeMode: false,
      bootSummary: '内核引导完成（演示数据）',
      stages: const <BootStage>[],
      moduleStates: const <String, String>{
        'kernel': 'ok',
        'base': 'ok',
        'domain': 'ok',
        'surface': 'ok',
      },
      moduleGraph: 'kernel → base → domain → surface',
      bridges: const <String>['base', 'domain', 'surface'],
      services: const <String>['gh.auth', 'gh.client', 'gh.api', 'ix.session'],
      trustWarnings: const <BootTrustWarning>[],
      logTail: const <KernelLogEntry>[],
    );

// ─────────────────────────────────────────────────────────────────────────────
// 渲染与捕获
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _noop() async {}

Widget _pageOf(
  String screen,
  SurfaceBridge bridge,
  KernelReport report,
  GhRepo repo,
) {
  switch (screen) {
    case 'login':
      return LoginPage(surface: bridge, onLoggedIn: _noop);
    case 'home':
      return DashboardPage(surface: bridge);
    case 'repo':
      return RepoPage(surface: bridge, repo: repo);
    case 'settings':
      return SettingsPage(surface: bridge);
    case 'about':
      return AboutPage(report: report);
    default:
      throw StateError('未知页面: $screen');
  }
}

/// 渲染一屏并返回捕获锚点。
Future<GlobalKey> _pumpScreen(
  WidgetTester tester, {
  required String screen,
  required SurfaceBridge bridge,
  required KernelReport report,
  required GhRepo repo,
  required TargetPlatform platform,
  required Brightness brightness,
  required Size size,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  final GlobalKey key = GlobalKey();
  final ThemeData base = buildOgLTheme(brightness);
  final ThemeData theme = base.copyWith(
    platform: platform,
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: _pageOf(screen, bridge, report, repo),
      ),
    ),
  );
  // 让 initState 里的异步加载（假件网络/内存存储）完成。
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  return key;
}

double _pixelRatioFor(Size logical) => logical.width >= 1000 ? 1.0 : 2.0;

/// 捕获当前帧为 PNG 字节；给了 [writePath] 则落盘。返回字节数。
Future<int> _capture(
  WidgetTester tester,
  GlobalKey key, {
  required Size logical,
  String? writePath,
}) async {
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  int bytes = 0;
  await tester.runAsync(() async {
    final ui.Image image =
        await boundary.toImage(pixelRatio: _pixelRatioFor(logical));
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final Uint8List png = data!.buffer.asUint8List();
    bytes = png.length;
    if (writePath != null) {
      final File file = File(writePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png);
    }
  });
  return bytes;
}

// ─────────────────────────────────────────────────────────────────────────────
// 测试入口
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    await _loadRealFonts();
  });

  if (!kWriteShots) {
    // 默认模式：一次轻量冒烟（不落盘）——保证普通 CI 也验证管线可用。
    testWidgets('截屏冒烟（默认模式不落盘）', (WidgetTester tester) async {
      // 截屏希望保留阴影；测试框架默认关闭它，因此这里临时打开并**必须还原**
      // （否则触发 "painting debug variable was changed by the test" 断言）。
      debugDisableShadows = false;
      try {
        final SurfaceBridge bridge = await _buildBridge();
        final GlobalKey key = await _pumpScreen(
          tester,
          screen: 'login',
          bridge: bridge,
          report: _report(),
          repo: GhRepo.fromJson(<String, dynamic>{}),
          platform: TargetPlatform.android,
          brightness: Brightness.light,
          size: const Size(390, 844),
        );
        final int bytes = await _capture(
          tester,
          key,
          logical: const Size(390, 844),
        );
        expect(bytes, greaterThan(1000), reason: '捕获的 PNG 字节数异常');
      } finally {
        debugDisableShadows = true;
      }
    });
    return;
  }

  // 截屏模式：只出两份样本（竖屏 + 横屏）。
  testWidgets('截屏样本（竖屏 + 横屏）', (WidgetTester tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDisableShadows = false;
    try {
      final SurfaceBridge bridge = await _buildBridge();
      final KernelReport report = _report();
      final GhRepo repo = GhRepo.fromJson(_repoJson(
        fullName: 'octocat/Hello-World',
        description: '演示仓库 · 用于 UI 截屏',
        isPrivate: false,
        stars: 1234,
      ));
      // ★ 恢复完整矩阵（此前退化成 2 张样本，UI 改动无法自动发现视觉回归）。
      //   三个维度：页面 × 亮/暗 × 横/竖；另加「平台 × 亮/暗」的首页，
      //   因为 Material 的 `platform` 会改变按钮/输入框等控件的外观。
      // ★ 不能加 const：collection-for 与 `brightness.name` 都不是常量表达式。
      final List<(String, String, Size)> matrix = <(String, String, Size)>[
        for (final String screen in <String>[
          'login',
          'home',
          'repo',
          'settings',
          'about',
        ])
          for (final Brightness brightness in Brightness.values)
            for (final (String, Size) shape in <(String, Size)>[
              ('portrait', Size(390, 844)),
              ('landscape', Size(844, 390)),
            ])
              (screen, brightness.name, shape.$2),
        // 平台差异只在首页上铺开（其余页面与平台无关，避免用例数爆炸）。
        for (final TargetPlatform platform in <TargetPlatform>[
          TargetPlatform.android,
          TargetPlatform.windows,
          TargetPlatform.linux,
        ])
          for (final Brightness brightness in Brightness.values)
            ('home@${platform.name}', brightness.name, const Size(390, 844)),
      ];

      for (final (String name, String brightnessName, Size size) in matrix) {
        final Brightness brightness =
            brightnessName == 'dark' ? Brightness.dark : Brightness.light;
        final String platformTag = name.contains('@')
            ? name.substring(name.indexOf('@') + 1)
            : 'android';
        final TargetPlatform platform = switch (platformTag) {
          'windows' => TargetPlatform.windows,
          'linux' => TargetPlatform.linux,
          _ => TargetPlatform.android,
        };
        final String label = name.replaceAll('@', '__');
        final GlobalKey key = await _pumpScreen(
          tester,
          screen: name.split('@').first,
          bridge: bridge,
          report: report,
          repo: repo,
          platform: platform,
          brightness: brightness,
          size: size,
        );
        final int bytes = await _capture(
          tester,
          key,
          logical: size,
          writePath: '$kOutRoot/$label.png',
        );
        expect(bytes, greaterThan(1000), reason: '截屏捕获异常: $label');
        debugPrint('[截屏] $label ${size.width.toInt()}x${size.height.toInt()} '
            '→ ${(bytes / 1024).toStringAsFixed(1)} KB');
        debugDisableShadows = true;
      }
    } finally {
      debugDisableShadows = true;
    }
  });
}
