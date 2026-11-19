/// L2 · GitHub OAuth App **Web Flow**（Authorization Code + 本地回环回调）。
///
/// ## 为什么补这条通道
/// Device Flow 需要用户手动抄码、且轮询链路在部分网络下不稳（实测登录态
/// 隔日 401 掉线的反馈）。OAuth App 的 **标准 Web Flow** 只需在浏览器里点
/// 一次「Continue/Authorize」：应用在本机 `127.0.0.1` 随机端口起监听，
/// 打开系统浏览器到授权页，GitHub 把 `?code=` 回跳到本地端口，应用直接
/// 换 token——一次跳转完成，无抄码、无轮询。
///
/// ## 为什么可行（无 secret 约束）
/// GitHub 对 OAuth App 允许 `http://127.0.0.1:<任意端口>` 回调（RFC 8252
/// loopback 约定），**无需在 App 设置里固定端口**；整个流程只用 Client ID
/// （可随包分发），client secret 对 Native/loopback 流程不参与校验。
///
/// ## 平台适用
/// 桌面（Windows/macOS/Linux）系统浏览器直接可用；Android 走系统浏览器
/// （Custom Tab）同样能回跳 `127.0.0.1`（Chrome 会代理到应用本机回环）。
/// Web（dart:html）目标不支持本实现（无本地监听能力），回落 Device Flow。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../kernel/log/og_l_log_file.dart';
import 'gh_client.dart';

const String _authorizeUrl = 'https://github.com/login/oauth/authorize';
const String _tokenUrl = 'https://github.com/login/oauth/access_token';

/// 申请一次性授权（打开浏览器等待用户点 Continue）。
///
/// [openUrl] 由展示层注入（系统浏览器 / Custom Tab 打开能力），Domain 层
/// 不直接依赖 url_launcher。返回 `[token, state]`：token 为 `gho_…` 原始令牌。
Future<String> startWebFlow({
  required String clientId,
  required Future<void> Function(String url) openUrl,
  String scope = 'repo read:user',
  Duration timeout = const Duration(minutes: 10),
}) async {
  // 随机回环端口 + state（CSRF 防护：回调必须携带同一 state）。
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = server.port;
  final String state =
      'ogl-${DateTime.now().millisecondsSinceEpoch}-${port.toString()}';
  final Uri authorize =
      Uri.parse(_authorizeUrl).replace(queryParameters: <String, String>{
    'client_id': clientId,
    'redirect_uri': 'http://127.0.0.1:$port/callback',
    'scope': scope,
    'state': state,
  });
  OgLLogFile.line('登录', 'OAuth Web Flow：监听 http://127.0.0.1:$port/callback');

  final Completer<String> codeCompleter = Completer<String>();
  StreamSubscription<HttpRequest>? sub;
  try {
    sub = server.listen((HttpRequest request) async {
      final Uri uri = request.uri;
      // 回调页给浏览器一个友好结果（无论成败都关监听）。
      final HttpResponse response = request.response;
      response.headers.contentType = ContentType.html;
      if (uri.path == '/callback') {
        final String? err = uri.queryParameters['error'];
        final String? code = uri.queryParameters['code'];
        final String? gotState = uri.queryParameters['state'];
        if (err != null) {
          response.statusCode = 200;
          response.write(_page('授权已取消', 'err'));
          await response.close();
          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(
              GhAuthException('用户取消了授权（$err）', statusCode: 401),
            );
          }
          return;
        }
        if (gotState != state) {
          response.statusCode = 400;
          response.write(_page('state 校验失败，请重试', 'err'));
          await response.close();
          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(
              const GhAuthException('回调 state 不匹配（可能的 CSRF）', statusCode: 400),
            );
          }
          return;
        }
        if (code == null || code.isEmpty) {
          response.statusCode = 400;
          response.write(_page('回调缺少 code 参数', 'err'));
          await response.close();
          return;
        }
        response.statusCode = 200;
        response.write(_page('授权成功，请回到应用', 'ok'));
        await response.close();
        if (!codeCompleter.isCompleted) {
          codeCompleter.complete(code);
        }
        return;
      }
      // 非 /callback 路径（浏览器 favicon 请求等）：静默 404。
      response.statusCode = 404;
      await response.close();
    });

    await openUrl(authorize.toString());

    final String code = await codeCompleter.future.timeout(timeout);
    return await _exchangeToken(clientId, code);
  } finally {
    await sub?.cancel();
    await server.close(force: true);
  }
}

/// 用 code 换 access token（loopback native flow 不带 client_secret）。
Future<String> _exchangeToken(String clientId, String code) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.postUrl(Uri.parse(_tokenUrl)).timeout(
              const Duration(seconds: 15),
            );
    request.headers.set('Accept', 'application/json');
    request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    request.headers.set('User-Agent', 'OhGithubLost');
    request.write(
      'client_id=${Uri.encodeComponent(clientId)}'
      '&code=${Uri.encodeComponent(code)}'
      '&grant_type=authorization_code',
    );
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 15));
    final String body = await response.transform(utf8.decoder).join();
    final Map<String, dynamic> decoded =
        jsonDecode(body) as Map<String, dynamic>;
    final String? token = decoded['access_token'] as String?;
    if (token == null || token.isEmpty) {
      final String error = decoded['error'] as String? ?? body;
      throw GhAuthException(
        '换取令牌失败：$error',
        statusCode: response.statusCode,
      );
    }
    OgLLogFile.line('登录', 'OAuth Web Flow：令牌获取成功（${token.substring(0, 4)}…）');
    return token;
  } finally {
    client.close(force: true);
  }
}

/// 回调页 HTML（用户在浏览器里看到的临时页）。
String _page(String message, String kind) =>
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '<title>OhGithubLost</title><style>'
    'body{font-family:system-ui,sans-serif;display:flex;align-items:center;'
    'justify-content:center;height:100vh;margin:0;background:#0d1117;color:#e6edf3}'
    'div{text-align:center}h1{font-size:20px;font-weight:600}'
    'p{color:#8b949e}</style></head><body><div>'
    '<h1>${kind == 'ok' ? '✓' : '✕'} $message</h1>'
    '<p>OhGithubLost · OAuth</p></div></body></html>';
