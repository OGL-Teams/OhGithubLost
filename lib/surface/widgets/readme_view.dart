/// L3 展示级 · README / Markdown 渲染（离线安全 + 排版直接取自主题）。
///
/// ## 为什么先做一次"净化"
/// 直接把 GitHub 的 Markdown 丢给渲染器在真机上会踩三个坑：
/// 1. 大量 HTML 包裹（`<div align="center">`、`<p>`…）在移动端没有意义；
/// 2. 巨型 README（几万字符）一次构建上万个 Widget，滚动直接掉帧；
/// 3. 图片既有相对路径（`docs/a.png`）也有第三方绝对地址。
///
/// [simplifyReadme] 是一次**纯函数净化**（可单测）：注释与标签剥掉、
/// 空行压缩、超长按行边界截断；图片默认**保留**（由调用方给出基址后真正加载）。
///
/// ## 链接与图片为什么必须给基址
/// README 里 `](LICENSE)`、`![](docs/a.png)` 这类写法是**相对**的。
/// 相对 URI 没有 scheme，系统浏览器打不开（表现为"点了没反应"），
/// `Image.network` 也无从下手。因此这里统一用 [ReadmeView.linkBase]
/// （GitHub `blob` 基址）与 [ReadmeView.imageBase]（`raw` 基址）解析成绝对地址。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'common', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 徽章行：`[![alt](图片)](链接)`（可重复；装饰用，整行删除）。
final RegExp _badgeRow = RegExp(r'^(\s*\[!\[[^\)]*\)\]\([^)]*\)\s*)+$');

/// 图片语法：`![alt](url "title")`。
final RegExp _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)');

/// HTML `<img src="…" alt="…">`。
final RegExp _htmlImage = RegExp(
  r'''<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>''',
  caseSensitive: false,
);

/// HTML 标签。
final RegExp _htmlTag = RegExp(r'</?[a-zA-Z][^>]*>');

/// HTML 注释。
final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// 看起来像裸域名（`www.x.com/a`、`x.io`）——补 `https://` 还能救。
final RegExp _bareHost = RegExp(r'^[\w-]+(\.[\w-]+)+([/?#].*)?$');

/// 可交给系统浏览器 / 图片加载的 scheme。
bool _isWebScheme(String scheme) =>
    scheme == 'http' || scheme == 'https' || scheme == 'mailto';

/// 把 Markdown 里的链接地址解析成**绝对** URI。
///
/// - 已带 http/https/mailto → 原样返回；
/// - `#标题` → 拼到基址上（GitHub 锚点可直接在浏览器打开）；
/// - 相对路径 → 用 [base] 解析（`base` 需以 `/` 结尾）；
/// - 无基址的裸域名 → 补 `https://`；
/// - 其余（`javascript:`、`data:`、纯文字）→ `null`（调用方提示用户）。
Uri? resolveReadmeUri(String href, {Uri? base}) {
  final String raw = href.trim();
  if (raw.isEmpty) {
    return null;
  }
  final Uri? direct = Uri.tryParse(raw);
  if (direct != null && direct.scheme.isNotEmpty) {
    return _isWebScheme(direct.scheme) ? direct : null;
  }
  if (base == null) {
    return _bareHost.hasMatch(raw) ? Uri.tryParse('https://$raw') : null;
  }
  if (raw.startsWith('#')) {
    return base.replace(fragment: raw.substring(1));
  }
  final Uri resolved = base.resolve(raw);
  return _isWebScheme(resolved.scheme) ? resolved : null;
}

/// 把图片地址解析成**绝对** URI（只接受 http/https）。
Uri? resolveReadmeImageUri(String src, {Uri? base}) {
  final String raw = src.trim();
  if (raw.isEmpty) {
    return null;
  }
  final Uri? direct = Uri.tryParse(raw);
  if (direct != null && direct.scheme.isNotEmpty) {
    final String s = direct.scheme.toLowerCase();
    return (s == 'http' || s == 'https') ? direct : null;
  }
  if (base == null) {
    return null;
  }
  final Uri resolved = base.resolve(raw);
  final String s = resolved.scheme.toLowerCase();
  return (s == 'http' || s == 'https') ? resolved : null;
}

/// 取仓库内**相对路径**（去掉 `./`、前导 `/`、查询串与锚点）。
String repoRelativePathOf(Uri uri) {
  String p = uri.path;
  if (p.isEmpty) {
    return '';
  }
  while (p.startsWith('./')) {
    p = p.substring(2);
  }
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  return Uri.decodeComponent(p);
}

/// 把原文净化成"手机友好"的 Markdown。
///
/// 规则（顺序很重要）：
/// 1. 去掉 HTML 注释；
/// 2. `<img src=x>` → `![x](x)`（否则图片永远加载不出来）；
/// 3. 徽章行整行删除（**仅** [keepBadges] 为 false 时）；
/// 4. 图片：`keepImages` 为 true 时保留语法（由渲染层真正取图），
///    超过 [maxImages] 张后的多余图片退化为 `（图：alt）`；
/// 5. 去掉其余 HTML 标签，只留文本；
/// 6. 连续空行压成一行；
/// 7. 超长按**行边界**截断，并补一行说明（不做静默丢内容）。
String simplifyReadme(
  String source, {
  int maxChars = 24000,
  bool keepImages = true,
  bool keepBadges = false,
  int maxImages = 40,
}) {
  final List<String> kept = <String>[];
  bool inFence = false;
  int images = 0;

  for (final String rawLine in source.split('\n')) {
    final String line = rawLine.trimRight();
    final String probe = line.trim();

    // 代码块内部原样保留（代码里的 `<div>`、`![]`、注释都不该被改）。
    if (probe.startsWith('```') || probe.startsWith('~~~')) {
      inFence = !inFence;
      kept.add(line);
      continue;
    }
    if (inFence) {
      kept.add(line);
      continue;
    }

    String noComment = line.replaceAll(_htmlComment, '');
    // HTML 内嵌图 → Markdown 图（alt 从 src 的文件名兜底）。
    noComment = noComment.replaceAllMapped(_htmlImage, (Match m) {
      final String src = m.group(1)?.trim() ?? '';
      if (src.isEmpty) {
        return '';
      }
      final String name = src.split('/').last;
      return '![$name]($src)';
    });

    final String bare = noComment.trim();
    if (bare.isEmpty) {
      kept.add('');
      continue;
    }
    if (!keepBadges && _badgeRow.hasMatch(bare)) {
      continue;
    }

    final String swapped = noComment.replaceAllMapped(_image, (Match m) {
      final String alt = m.group(1)?.trim() ?? '';
      final String url = m.group(2)?.trim() ?? '';
      if (keepImages && url.isNotEmpty && images < maxImages) {
        images++;
        return m.group(0) ?? '';
      }
      return alt.isEmpty
          ? _t('readmeImageOmitted')
          : _t('readmeImageAlt', {'alt': alt});
    });
    kept.add(swapped.replaceAll(_htmlTag, '').trimRight());
  }

  // 压缩连续空行。
  final List<String> out = <String>[];
  int blanks = 0;
  for (final String line in kept) {
    if (line.trim().isEmpty) {
      blanks++;
      if (blanks > 1) {
        continue;
      }
    } else {
      blanks = 0;
    }
    out.add(line);
  }
  String md = out.join('\n').trim();

  if (md.length <= maxChars) {
    return md;
  }
  int cut = md.lastIndexOf('\n', maxChars);
  if (cut <= 0) {
    cut = maxChars;
  }
  md = md.substring(0, cut).trimRight();
  return '$md\n\n---\n\n${_t('readmeTruncated')}';
}

/// Markdown 视图：净化 + 主题排版 + 链接/图片回调。
class ReadmeView extends StatelessWidget {
  /// 创建视图。
  const ReadmeView({
    required this.markdown,
    this.onOpenLink,
    this.linkBase,
    this.imageBase,
    this.maxChars = 24000,
    this.loadImages = true,
    this.maxImages = 40,
    this.imageLoader,
    this.imageProxyPrefix,
    this.imageHeaders,
    super.key,
  });

  /// 原文（Markdown）。
  final String markdown;

  /// 链接点击（收到已解析的绝对 URL）。
  final void Function(Uri url)? onOpenLink;

  /// 链接基址（例如 `https://github.com/o/r/blob/main/`，必须以 `/` 结尾）。
  final Uri? linkBase;

  /// 图片基址（例如 `https://raw.githubusercontent.com/o/r/main/`）。
  final Uri? imageBase;

  /// 图片**加速前缀**（非空 = 仓库内图片走 `前缀 + raw 地址`）。
  ///
  /// 为什么不直接用 Contents API：`.imageLoader` 那条路会消耗 API 配额
  /// （认证后 5000 次/小时），而一次 README 就可能要几十张图；`raw` 端点
  /// 则不限流。因此**自定义通道 + 公开仓库**（或私有仓库且用户已知情接受）
  /// 时改走 raw + 代理。
  ///
  /// 私有仓库走这条路**必须带令牌**：`raw` 没有签名机制，匿名访问是 404；
  /// 通道会原样转发 `Authorization`，所以由调用方通过 [imageHeaders] 提供
  /// 认证头（`Image.network` 支持 headers）。拿不到令牌时调用方不该启用
  /// [imageProxyPrefix]，退回 `imageLoader`（API 取字节）。
  final String? imageProxyPrefix;

  /// 加速图片的**认证头**（`Future`：令牌要读一次安全保险库）。
  ///
  /// 仅"私有仓库 + 已启用加速"时非空 —— 那时 raw 必须带令牌，否则必然 404。
  /// 为 `null` 或解析成空 map 时不带任何头（公开仓库的常态）。
  final Future<Map<String, String>>? imageHeaders;

  /// 截断阈值（字符数）。
  final int maxChars;

  /// 是否真正加载图片（关闭则退化为 `（图：alt）` 文本）。
  final bool loadImages;

  /// 单次最多加载的图片数（防巨型 README 拖垮滚动）。
  final int maxImages;

  /// 图片字节加载器（**走 API**）。
  ///
  /// 参数是**仓库内相对路径**，返回字节后交给 `Image.memory`。
  /// 这样图片不经过 `raw.githubusercontent.com`，避开 DNS 污染；
  /// 为 `null` 时只认绝对地址（http/https）。
  final Future<Uint8List?> Function(String path)? imageLoader;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Uri? imgBase = loadImages ? imageBase : null;
    final Future<Uint8List?> Function(String path)? loader =
        loadImages ? imageLoader : null;
    final String md = simplifyReadme(
      markdown,
      maxChars: maxChars,
      keepImages: loadImages,
      maxImages: maxImages,
    );
    final TextStyle body = theme.textTheme.bodyMedium ?? const TextStyle();
    final TextStyle mono = const TextStyle(fontFamily: 'monospace');

    return MarkdownBody(
      data: md,
      selectable: true,
      shrinkWrap: true,
      onTapLink: (String text, String? href, String title) {
        final void Function(Uri url)? open = onOpenLink;
        if (href == null || open == null) {
          return;
        }
        final Uri? uri = resolveReadmeUri(href, base: linkBase);
        if (uri == null) {
          // 打不开时**可见地**告诉用户，而不是点了没反应。
          // 走统一提示通道（样式 / 时长 / 语气全局一致）。
          OgLNotifier.of(context).warning(_t('linkInvalid'));
          return;
        }
        open(uri);
      },
      // 说明：`imageBuilder` 在当前 flutter_markdown 版本已标记 deprecated，
      // 但本项目**尚未迁移**到替代方案（`builders` + 自定义
      // MarkdownElementBuilder），而这里需要的是"按 URI 决定取字节还是直连"
      // 这一层钩子 —— 迁移需单独批次评估，故暂留并显式说明理由，
      // 而不是让一个无注释的 ignore 留在代码里。
      // ignore: deprecated_member_use
      imageBuilder: (Uri uri, String? title, String? alt) {
        final String label =
            (alt == null || alt.trim().isEmpty) ? uri.path : alt.trim();
        final TextStyle fallback =
            body.copyWith(color: scheme.onSurfaceVariant);
        // ① 加速路径：**自定义通道 + 公开仓库**（或私有仓库且用户已知情接受）
        //    时，仓库内图片走 **raw + 代理**。
        //    私有仓库的 raw 必须带令牌（匿名是 404）：令牌由 [imageHeaders]
        //    以 `Authorization` 头给出（`Image.network` 支持 headers，通道会
        //    原样转发）；没有它就是取不到内容，调用方应保持 proxy 为空。
        //    比 API 取字节更好：raw 不限流（API 认证后也只有 5000 次/小时）。
        final String proxy = imageProxyPrefix ?? '';
        if (proxy.isNotEmpty && !uri.hasScheme) {
          final Uri? raw = resolveReadmeImageUri(uri.toString(), base: imgBase);
          if (raw != null) {
            return _ReadmeImage.net(
              url: Uri.parse('$proxy$raw'),
              alt: label,
              fallbackStyle: fallback,
              headers: imageHeaders,
            );
          }
        }
        // ② 仓库内相对路径 → 走 API 取字节（私有仓库唯一可行；也不碰 raw 域名）。
        if (!uri.hasScheme && loader != null) {
          final String path = repoRelativePathOf(uri);
          if (path.isNotEmpty) {
            return _ReadmeImage.api(
              path: path,
              // 缓存作用域 = 该仓库+分支的基址，防止跨仓库串图。
              scope: imgBase?.toString() ?? '',
              alt: label,
              fallbackStyle: fallback,
              loader: loader,
            );
          }
        }
        // ② 绝对 http/https（第三方图床）→ 只能直连。
        final Uri? target = uri.hasScheme
            ? resolveReadmeImageUri(uri.toString())
            : resolveReadmeImageUri(uri.toString(), base: imgBase);
        if (target == null) {
          return Text(_t('readmeImageAlt', {'alt': label}), style: fallback);
        }
        return _ReadmeImage.net(
            url: target, alt: label, fallbackStyle: fallback);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body.copyWith(height: 1.5),
        h1: theme.textTheme.headlineSmall,
        h2: theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        code: mono.copyWith(
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(OgLRadius.sm),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 3),
          ),
        ),
        a: TextStyle(color: scheme.primary),
        img: body,
        listBullet: body,
        blockSpacing: 12,
      ),
    );
  }
}

/// README 内嵌图片：优先走 **API 字节**，第三方绝对地址才直连。
class _ReadmeImage extends StatelessWidget {
  /// 走 API：参数是仓库内相对路径。
  const _ReadmeImage.api({
    required String path,

    /// 缓存作用域（仓库 + 分支的基址）。字节缓存必须区分仓库：
    /// 只以仓库内相对路径为键时，`assets/logo.png` 这类同名文件会在
    /// 两个仓库之间命中同一份缓存，显示成另一个仓库的图且无任何提示。
    String scope = '',
    required this.alt,
    required this.fallbackStyle,
    required Future<Uint8List?> Function(String path) loader,
  })  : _path = path,
        _scope = scope,
        _url = null,
        _loader = loader,
        _headers = null;

  /// 直连：绝对 http/https 地址。
  const _ReadmeImage.net({
    required Uri url,
    required this.alt,
    required this.fallbackStyle,
    Future<Map<String, String>>? headers,
  })  : _url = url,
        _headers = headers,
        _scope = '',
        _path = null,
        _loader = null;

  final String? _path;

  /// 请求头（仅"私有仓库 + 加速"时非空：raw 必须带令牌，否则必然 404）。
  final Future<Map<String, String>>? _headers;

  /// 字节缓存的命名空间（仓库 + 分支）；直连图片为空串。
  final String _scope;

  final Uri? _url;
  final Future<Uint8List?> Function(String path)? _loader;

  /// 无障碍文本 / 失败时的替代文案。
  final String alt;

  /// 失败文案样式。
  final TextStyle fallbackStyle;

  /// 字节缓存：同一张图重复出现或重建时不再请求。
  ///
  /// 键包含 [_scope]（仓库 + 分支），否则不同仓库的同名图片会互相串用。
  /// 上限按**总字节数**（32MB）LRU 淘汰——此前只限张数（32 张），连翻
  /// 大图会把原始字节攒到上百 MB，进程级存活导致内存单调增长。
  static const int _cacheMaxBytes = 32 << 20;
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static final Map<String, int> _cacheOrder = <String, int>{};
  static int _cacheClock = 0;
  static int _cacheBytes = 0;

  static void _cachePut(String key, Uint8List bytes) {
    final int existing = _cacheOrder[key] ?? 0;
    if (existing != 0) {
      _cacheBytes -= _cache[key]?.length ?? 0;
    }
    while (
        _cacheBytes + bytes.length > _cacheMaxBytes && _cacheOrder.isNotEmpty) {
      final String oldest = _cacheOrder.keys
          .reduce((a, b) => _cacheOrder[a]! < _cacheOrder[b]! ? a : b);
      _cacheBytes -= _cache[oldest]?.length ?? 0;
      _cache.remove(oldest);
      _cacheOrder.remove(oldest);
    }
    _cacheClock++;
    _cacheOrder[key] = _cacheClock;
    _cache[key] = bytes;
    _cacheBytes += bytes.length;
  }

  static int _targetWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round();

  @override
  Widget build(BuildContext context) {
    final String? path = _path;
    if (path == null) {
      return _frame(_network());
    }
    final String cacheKey = '$_scope|$path';
    final Uint8List? cached = _cache[cacheKey];
    if (cached != null) {
      return _frame(Image.memory(cached,
          cacheWidth: _targetWidth(context),
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft));
    }
    return _frame(
      FutureBuilder<Uint8List?>(
        future: _load(path),
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _ReadmeImageSpinner();
          }
          final Uint8List? bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return Text(_t('readmeImageAlt', {'alt': alt}),
                style: fallbackStyle);
          }
          return Image.memory(bytes,
              cacheWidth: _targetWidth(context),
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft);
        },
      ),
    );
  }

  Future<Uint8List?> _load(String path) async {
    final Future<Uint8List?> Function(String path)? loader = _loader;
    if (loader == null) {
      return null;
    }
    try {
      final Uint8List? bytes = await loader(path);
      if (bytes != null && bytes.isNotEmpty) {
        // 与 build() 用同一套键：作用域 + 仓库内路径。
        _cachePut('$_scope|$path', bytes);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _network() {
    final Future<Map<String, String>>? headers = _headers;
    if (headers == null) {
      return _image(const <String, String>{});
    }
    // 私有仓库 + 加速：令牌要读一次安全保险库，先等它到位再发起图片请求
    //（否则 raw 匿名必然 404，用户看到的是莫名其妙的替代文本）。
    return FutureBuilder<Map<String, String>>(
      future: headers,
      builder: (BuildContext context, AsyncSnapshot<Map<String, String>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _ReadmeImageSpinner();
        }
        return _image(snap.data ?? const <String, String>{});
      },
    );
  }

  Widget _image(Map<String, String> headers) => Image.network(
        _url.toString(),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        // 空 map = 一个头都不带（公开仓库的常态；取不到令牌时如实退化为匿名）。
        headers: headers.isEmpty ? null : headers,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            Text(_t('readmeImageAlt', {'alt': alt}), style: fallbackStyle),
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? progress) =>
                progress == null ? child : const _ReadmeImageSpinner(),
      );

  Widget _frame(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OgLSpace.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: child,
        ),
      );
}

/// 图片加载中的小指示。
class _ReadmeImageSpinner extends StatelessWidget {
  const _ReadmeImageSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: OgLSpace.sm),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
