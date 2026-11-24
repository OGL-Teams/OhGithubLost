/// OGL · UI 截屏矩阵（供手动 CI 生成"全平台截屏"构建产物）。
///
/// ## 两种运行模式
/// - **默认（普通 `flutter test`）**：只跑一次"冒烟截屏"（不落盘）——
///   验证字体加载 / 假件 bridge / 捕获管线可用；
/// - **截屏模式（`OGL_SCREENSHOTS=1`）**：把完整页面矩阵真实渲染并落盘到
///   `build/ui_shots/<页面名>.png`（每页竖屏 390×844 + 横屏 844×390，
///   首页另按平台 × 亮暗铺开）。文件名带页面名，CI 上传为 `ui-shots` artifact。
///
/// ## 数据来源：真实令牌优先，缺失回落假件
/// - 进程环境 `OGL_SCREENSHOT_TOKEN` 非空且形态合法（经 [GhToken.looksValid]
///   校验）→ 用真实 [IoNetTransport] + `Bearer <token>` 构造 [GhClient]，
///   真实 GET api.github.com，按页面需要抓取 issue / PR / release / Actions 等
///   数据；拼写不对的令牌或 API 失败不打印令牌、不中断整批，相关页标 skip 并
///   留 TODO；
/// - 令牌缺失 / 解析失败 / 真实取数失败 → 回落脚本化假件（[ScreenshotData] 里
///   的离线样例），保证 matrix 每个页面仍有一张可比的截图。
///   令牌只写进内存保险库，测试结束即擦除，不落盘、不进日志/报告/产物。
///
/// ## 离线假件（fallback）
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
import 'package:ohgithublost/base/net/io_net_transport.dart';
import 'package:ohgithublost/base/net/net_bridge.dart';
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
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';
import 'package:ohgithublost/surface/pages/about_page.dart';
import 'package:ohgithublost/surface/pages/action_log_page.dart';
import 'package:ohgithublost/surface/pages/action_run_page.dart';
import 'package:ohgithublost/surface/pages/code_editor_page.dart';
import 'package:ohgithublost/surface/pages/commit_page.dart';
import 'package:ohgithublost/surface/pages/dashboard_page.dart';
import 'package:ohgithublost/surface/pages/search_page.dart';
import 'package:ohgithublost/surface/pages/download_manager_page.dart';
import 'package:ohgithublost/surface/pages/drafts_page.dart';
import 'package:ohgithublost/surface/pages/file_preview_page.dart';
import 'package:ohgithublost/surface/pages/gist_detail_page.dart';
import 'package:ohgithublost/surface/pages/gists_page.dart';
import 'package:ohgithublost/surface/pages/issue_page.dart';
import 'package:ohgithublost/surface/pages/legal_text_page.dart';
import 'package:ohgithublost/surface/pages/login_page.dart';
import 'package:ohgithublost/surface/pages/network_page.dart';
import 'package:ohgithublost/surface/pages/new_gist_page.dart';
import 'package:ohgithublost/surface/pages/new_issue_page.dart';
import 'package:ohgithublost/surface/pages/new_release_page.dart';
import 'package:ohgithublost/surface/pages/new_repo_page.dart';
import 'package:ohgithublost/surface/pages/notifications_page.dart';
import 'package:ohgithublost/surface/pages/onboarding_page.dart';
import 'package:ohgithublost/surface/pages/profile_page.dart';
import 'package:ohgithublost/surface/pages/pull_page.dart';
import 'package:ohgithublost/surface/pages/release_detail_page.dart';
import 'package:ohgithublost/surface/pages/repo_page.dart';
import 'package:ohgithublost/surface/pages/repo_tags_page.dart';
import 'package:ohgithublost/surface/pages/search_page.dart';
import 'package:ohgithublost/surface/pages/settings_page.dart';
import 'package:ohgithublost/surface/pages/settings_section_page.dart';
import 'package:ohgithublost/surface/pages/workflow_dispatch_page.dart';
import 'package:ohgithublost/surface/settings.dart';
import 'package:ohgithublost/surface/surface_bridge.dart';
import 'package:ohgithublost/surface/theme.dart';
import 'package:ohgithublost/surface/util/file_preview.dart';
import 'package:ohgithublost/surface/widgets/settings/settings_group.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 配置
// ─────────────────────────────────────────────────────────────────────────────

/// 是否落盘（手动 CI 设 `OGL_SCREENSHOTS=1`）。
final bool kWriteShots = Platform.environment['OGL_SCREENSHOTS'] == '1';

/// 令牌只经环境变量注入测试进程；不写 dart-define、不打印、不落产物。
final String? kScreenshotToken = Platform.environment['OGL_SCREENSHOT_TOKEN'];

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

/// 组装真实桥（脚本化网络；不依赖任何平台插件）。
///
/// [token] 非空时改用真实 [IoNetTransport]（Bearer 由 GhClient 从保险库注入
/// authorization 头），走真实 GitHub API；为空时回落脚本化假件。
/// 返回：[bridge] 与本次使用的存储（供调用方在结束时擦除令牌）。
Future<({SurfaceBridge bridge, InMemoryVault vault, InMemoryKv kv})>
    _buildBridge([
  String? token,
]) async {
  final InMemoryVault vault = InMemoryVault();
  final InMemoryKv kv = InMemoryKv();
  final GhAuthService auth = GhAuthService(vault: vault, store: kv);
  await auth.saveAccount(
    const GhAccount(id: 'user-1', login: 'octocat', name: 'Octo Cat'),
    GhToken(token ?? 'ghp_demo_demo_demo_demo'),
  );
  await auth.switchTo('user-1');
  final NetTransport transport =
      token == null ? _ScriptedTransport() : IoNetTransport();
  final GhClient client = GhClient(
    net: NetBridge(transport: transport, observer: NetObserver()),
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
  return (
    bridge: SurfaceBridge(settings: settings, domain: domain, net: null),
    vault: vault,
    kv: kv,
  );
}

/// 每页所需的最小真实数据；空列表字段表示取数失败 → 该页标 skip。
class ScreenshotData {
  const ScreenshotData({
    required this.repo,
    required this.commits,
    required this.releases,
    required this.issues,
    required this.pulls,
    required this.gists,
    required this.workflowRuns,
    required this.runId,
  });

  final GhRepo repo;
  final List<GhCommit> commits;
  final List<GhRelease> releases;
  final List<Map<String, dynamic>> issues;
  final List<Map<String, dynamic>> pulls;
  final List<Map<String, dynamic>> gists;
  final List<Map<String, dynamic>> workflowRuns;
  final int runId;

  /// 页面 → 是否缺它专属的数据（缺则该页跳过并留 TODO）。
  bool missingFor(String screen) => switch (screen) {
        'commit' => commits.isEmpty,
        'release_detail' => releases.isEmpty,
        'issue' => issues.isEmpty,
        'pull' => pulls.isEmpty,
        'gist_detail' => gists.isEmpty,
        'action_run' || 'action_log' => workflowRuns.isEmpty || runId <= 0,
        _ => false,
      };
}

/// 离线样例数据（fallback）：每个依赖参数的页面都有可渲染对象。
ScreenshotData _demoData() {
  final GhRepo repo = GhRepo.fromJson(_repoJson(
    fullName: 'octocat/Hello-World',
    description: '演示仓库 · 用于 UI 截屏',
    isPrivate: false,
    stars: 1234,
  ));
  final GhCommit commit = GhCommit.fromJson(<String, dynamic>{
    'sha': 'demo-sha-0001',
    'commit': <String, dynamic>{
      'message': 'chore: 截屏演示提交',
      'author': <String, dynamic>{
        'name': 'Octo Cat',
        'date': '2026-10-01T00:00:00Z',
      },
    },
    'parents': <dynamic>[],
  });
  final GhRelease release = GhRelease.fromJson(<String, dynamic>{
    'id': 1,
    'tag_name': 'v1.0.0',
    'name': '演示发布',
    'body': '截屏演示发布正文',
    'draft': false,
    'prerelease': false,
    'created_at': '2026-10-01T00:00:00Z',
    'published_at': '2026-10-02T00:00:00Z',
  });
  return ScreenshotData(
    repo: repo,
    commits: <GhCommit>[commit],
    releases: <GhRelease>[release],
    issues: <Map<String, dynamic>>[
      <String, dynamic>{
        'number': 1,
        'title': '演示 Issue',
        'state': 'open',
        'user': <String, dynamic>{'login': 'octocat'},
        'created_at': '2026-10-01T00:00:00Z',
        'body': '截屏演示 Issue 正文',
        'comments': 0,
      },
    ],
    pulls: <Map<String, dynamic>>[
      <String, dynamic>{
        'number': 2,
        'title': '演示 PR',
        'state': 'open',
        'user': <String, dynamic>{'login': 'octocat'},
        'created_at': '2026-10-01T00:00:00Z',
        'body': '截屏演示 PR 正文',
        'head': <String, dynamic>{'ref': 'feature'},
        'base': <String, dynamic>{'ref': 'main'},
      },
    ],
    gists: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'demo-gist-0001',
        'description': '演示 Gist',
        'public': true,
        'updated_at': '2026-10-01T00:00:00Z',
        'files': <String, dynamic>{
          'main.dart': <String, dynamic>{
            'filename': 'main.dart',
            'language': 'Dart',
            'content': 'void main() => print("demo");',
          },
        },
      },
    ],
    workflowRuns: <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 123456,
        'name': 'CI',
        'status': 'completed',
        'conclusion': 'success',
        'created_at': '2026-10-01T00:00:00Z',
        'html_url':
            'https://github.com/octocat/Hello-World/actions/runs/123456',
      },
    ],
    runId: 123456,
  );
}

/// 真实取数：所有网络异常都吞掉并记成「未取到」，绝不打印异常文本
/// （响应体可能回显令牌片段）；缺的数据由调用方标 skip + fallback。
Future<ScreenshotData> _realData(GhApi api, String repoFullName) async {
  Future<T?> safe<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (_) {
      return null;
    }
  }

  final GhRepo? repo = await safe(() => api.repo(repoFullName));
  final List<GhCommit> commits = await safe(
        () => api.commits(repoFullName, perPage: 5),
      ) ??
      const <GhCommit>[];
  final List<GhRelease> releases = await safe(
        () => api.releases(repoFullName, perPage: 5),
      ) ??
      const <GhRelease>[];
  final List<Map<String, dynamic>> issues = await safe(
        () => api.issues(repoFullName, perPage: 5),
      ) ??
      const <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> pulls = await safe(
        () => api.pulls(repoFullName, perPage: 5),
      ) ??
      const <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> gists =
      await safe(() => api.gists()) ?? const <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> runs = await safe(
        () => api.workflowRuns(repoFullName, perPage: 5),
      ) ??
      const <Map<String, dynamic>>[];
  final int runId =
      runs.isEmpty ? 0 : int.tryParse('${runs.first['id'] ?? ''}') ?? 0;
  return ScreenshotData(
    repo: repo ?? _demoData().repo,
    commits: commits,
    releases: releases,
    issues: issues,
    pulls: pulls,
    gists: gists,
    workflowRuns: runs,
    runId: runId,
  );
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

/// 全部 30 页（对照 lib/surface/pages/*.dart）→ 构造各自页面所需参数。
/// 需要参数的页在 [data] 缺数据时返回 null，调用方标 skip + TODO。
Widget? _pageOf(
  String screen,
  SurfaceBridge bridge,
  KernelReport report,
  ScreenshotData data,
) {
  final GhRepo repo = data.repo;
  final String fullName =
      repo.fullName.isEmpty ? 'octocat/Hello-World' : repo.fullName;
  final String branch =
      repo.defaultBranch.isEmpty ? 'main' : repo.defaultBranch;
  final Map<String, dynamic> firstIssue =
      data.issues.isEmpty ? <String, dynamic>{} : data.issues.first;
  final Map<String, dynamic> firstPull =
      data.pulls.isEmpty ? <String, dynamic>{} : data.pulls.first;
  final Map<String, dynamic> firstRun =
      data.workflowRuns.isEmpty ? <String, dynamic>{} : data.workflowRuns.first;
  final String gistId =
      data.gists.isEmpty ? '' : '${data.gists.first['id'] ?? ''}';
  switch (screen) {
    case 'login':
      return LoginPage(surface: bridge, onLoggedIn: _noop);
    case 'home':
      return DashboardPage(surface: bridge);
    case 'repo':
      return RepoPage(surface: bridge, repo: repo);
    case 'settings':
      return SettingsPage(surface: bridge, report: report);
    case 'about':
      return AboutPage(report: report);
    // 30 页矩阵余下 25 页（含 search_page 的两页 / network_page）。
    case 'search':
      return DiscoverPage(surface: bridge);
    case 'search_results':
      return SearchResultsPage(surface: bridge, query: 'github', mode: 0);
    case 'notifications':
      return const NotificationsPage();
    case 'profile':
      return ProfilePage(surface: bridge, onAccountsChanged: _noop);
    case 'onboarding':
      return OnboardingPage(surface: bridge, onFinished: () {});
    case 'gists':
      return GistsPage(surface: bridge);
    case 'new_gist':
      return NewGistPage(surface: bridge);
    case 'drafts':
      return DraftsPage(surface: bridge);
    case 'download_manager':
      return DownloadManagerPage(surface: bridge);
    case 'legal_text':
      return LegalTextPage(surface: bridge);
    case 'new_repo':
      return NewRepoPage(surface: bridge);
    case 'network':
      return NetworkSettingsPage(
        surface: bridge,
        builder: (BuildContext context, OgLSettings value) => OgLSettingsGroup(
          children: <Widget>[
            Text(
                'DNS: ${value.dnsServerId} / 并发: ${value.downloadConnections}'),
          ],
        ),
      );
    case 'settings_section':
      return const SettingsSectionPage(
        title: 'Settings Section',
        sections: <Widget>[Text('Section placeholder')],
      );
    case 'repo_tags':
      return RepoTagsPage(surface: bridge, fullName: fullName);
    case 'new_release':
      return NewReleasePage(
        surface: bridge,
        fullName: fullName,
        defaultBranch: branch,
      );
    case 'workflow_dispatch':
      return WorkflowDispatchPage(
        surface: bridge,
        fullName: fullName,
        defaultBranch: branch,
      );
    case 'new_issue':
      return NewIssuePage(surface: bridge, fullName: fullName);
    case 'gist_detail':
      if (data.missingFor(screen)) return null;
      return GistDetailPage(surface: bridge, gistId: gistId);
    case 'issue':
      if (data.missingFor(screen)) return null;
      return IssuePage(
        surface: bridge,
        fullName: fullName,
        issue: firstIssue,
      );
    case 'pull':
      if (data.missingFor(screen)) return null;
      return PullPage(
        surface: bridge,
        fullName: fullName,
        pull: firstPull,
        number: int.tryParse('${firstPull['number'] ?? 0}') ?? 1,
      );
    case 'commit':
      if (data.missingFor(screen)) return null;
      return CommitPage(
        surface: bridge,
        fullName: fullName,
        commit: data.commits.first,
      );
    case 'release_detail':
      if (data.missingFor(screen)) return null;
      return ReleaseDetailPage(
        surface: bridge,
        fullName: fullName,
        release: data.releases.first,
      );
    case 'action_run':
      if (data.missingFor(screen)) return null;
      return ActionRunPage(
        surface: bridge,
        fullName: fullName,
        run: firstRun,
      );
    case 'action_log':
      if (data.missingFor(screen)) return null;
      return ActionLogPage(
        surface: bridge,
        fullName: fullName,
        runId: data.runId,
      );
    case 'file_preview':
      return FilePreviewPage(
        surface: bridge,
        fullName: fullName,
        path: 'README.md',
        branch: branch,
        kind: OgLPreviewKind.unknown,
      );
    case 'code_editor':
      return CodeEditorPage(
        surface: bridge,
        fullName: fullName,
        path: 'README.md',
        initialText: '# OhGithubLost',
        baseSha: 'demo-base-sha',
        branch: branch,
      );
    default:
      return null;
  }
}

/// 渲染一屏并返回捕获锚点。
Future<GlobalKey> _pumpScreen(
  WidgetTester tester, {
  required String screen,
  required SurfaceBridge bridge,
  required KernelReport report,
  required ScreenshotData data,
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
        home: _pageOf(screen, bridge, report, data)!,
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

/// 全部 30 页页面清单（lib/surface/pages/*.dart，含 search_page 的 2 页）。
/// 截图文件名直接取这里的页面名（保证与源码一一对应）。
const List<String> kAllScreens = <String>[
  'about',
  'action_log',
  'action_run',
  'code_editor',
  'commit',
  'dashboard',
  'download_manager',
  'drafts',
  'file_preview',
  'gist_detail',
  'gists',
  'issue',
  'legal_text',
  'login',
  'network',
  'new_gist',
  'new_issue',
  'new_release',
  'new_repo',
  'notifications',
  'onboarding',
  'profile',
  'pull',
  'release_detail',
  'repo',
  'repo_tags',
  'search',
  'search_results',
  'settings',
  'workflow_dispatch',
];

/// 令牌经环境注入；**格式不对即回落假件**（且不打印令牌形态）。
/// 不设 dart-define：Flutter `flutter test --dart-define-from-env` 不可用，
/// 故直接在测试进程读 Platform.environment（CI 只在 flutter test 步设该 env）。
bool get _hasRealToken {
  final String? token = kScreenshotToken;
  if (token == null || token.trim().isEmpty) return false;
  return GhToken(token.trim()).looksValid;
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    // 英文环境：i18n 默认按设备 locale（CI 为 zh），截图固定 en 保证可比。
    await OgLI18n.instance.load('en');
  });

  if (!kWriteShots) {
    // 默认模式：一次轻量冒烟（不落盘）——保证普通 CI 也验证管线可用。
    testWidgets('截屏冒烟（默认模式不落盘）', (WidgetTester tester) async {
      // `_pumpScreen` 会改 `tester.view.physicalSize / devicePixelRatio`，
      // 冒烟分支此前未还原，泄漏到其它用例会 flaky —— 这里补上还原（R7）。
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      // 截屏希望保留阴影；测试框架默认关闭它，因此这里临时打开并**必须还原**
      // （否则触发 "painting debug variable was changed by the test" 断言）。
      debugDisableShadows = false;
      final ({SurfaceBridge bridge, InMemoryVault vault, InMemoryKv kv}) built =
          await _buildBridge();
      addTearDown(() async {
        await built.vault.deleteSecret('gh.token.user-1');
        await built.kv.remove('ogl.gh.account.user-1');
      });
      try {
        final GlobalKey key = await _pumpScreen(
          tester,
          screen: 'login',
          bridge: built.bridge,
          report: _report(),
          data: _demoData(),
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

  // 截屏模式：全部 30 页 × 亮暗 × 横竖 + 首页平台维度，真实令牌优先。
  testWidgets('截屏矩阵（30 页 · 英文 · 真实数据/假件回落）', (WidgetTester tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDisableShadows = false;
    final ({SurfaceBridge bridge, InMemoryVault vault, InMemoryKv kv}) built =
        await _buildBridge(_hasRealToken ? kScreenshotToken!.trim() : null);
    // 令牌只在内存保险库活到测试结束；这里擦除，绝不落盘或进产物。
    addTearDown(() async {
      await built.vault.deleteSecret('gh.token.user-1');
      await built.kv.remove('ogl.gh.account.user-1');
    });
    try {
      final KernelReport report = _report();
      // 真实取数：失败页面标 skip + TODO，其余用假件数据保证有截图可比。
      ScreenshotData data = _demoData();
      if (_hasRealToken) {
        try {
          data = await _realData(
            built.bridge.domain.api,
            'OGL-Teams/OhGithubLost',
          );
        } catch (_) {
          data = _demoData();
        }
      }
      final ScreenshotData demo = _demoData();
      final Set<String> realMissing = <String>{};

      // 三个维度：页面 × 亮/暗 × 横/竖；首页另铺平台（Material 控件外观不同）。
      final List<(String, String, Size)> matrix = <(String, String, Size)>[
        for (final String screen in kAllScreens)
          for (final Brightness brightness in Brightness.values)
            for (final (String, Size) shape in <(String, Size)>[
              ('portrait', Size(390, 844)),
              ('landscape', Size(844, 390)),
            ])
              (screen, brightness.name, shape.$2),
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
        final String screen = name.split('@').first;
        ScreenshotData use = data;
        if (data.missingFor(screen)) {
          // TODO: 真实 API 取不到该页专属参数（权限/网络/空仓库）——暂用假件
          // 数据出图并在日志标 skip，待 CI 令牌权限或样例仓库补齐后转真。
          realMissing.add(screen);
          use = demo;
        }
        final Widget? page = _pageOf(screen, built.bridge, report, use);
        if (page == null) {
          // 不应发生：kAllScreens 与 _pageOf 的 case 表一一对应。
          throw StateError('页面矩阵缺构造分支: $screen');
        }
        final String label =
            '$screen@${brightnessName}_${size.width.toInt()}x${size.height.toInt()}'
                .replaceAll('@', '__');
        final GlobalKey key = await _pumpScreen(
          tester,
          screen: screen,
          bridge: built.bridge,
          report: report,
          data: use,
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
      if (realMissing.isNotEmpty) {
        // 只列页面名；不含令牌、响应体或任何网络错误文本。
        debugPrint('[截屏] 以下页面真实数据不足，已用假件出图（待补）：'
            '${realMissing.join(', ')}');
      }
      debugPrint('[截屏] 模式=${_hasRealToken ? 'real' : 'fixture'} '
          '页面=${kAllScreens.length} 图片=${matrix.length}');
    } finally {
      debugDisableShadows = true;
    }
  });
}
