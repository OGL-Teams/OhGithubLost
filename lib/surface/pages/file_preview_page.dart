/// L3 展示级 · 文件预览页（图片 / SVG / XML / 音频 / 文本）。
///
/// ## 为什么单独开一页，而不是塞进仓库页
/// 仓库页的「点文件 → 内联看文本」对**位图与音频毫无意义**（二进制当文本看是
/// 乱码），而 SVG 与 XML 既可能想看源码、也可能想看渲染结果。把这些差异收进
/// 一个独立页面，「打开方式」的选择就有了明确落点，也不必改动仓库页既有流程。
///
/// ## 一条如实告知的硬约束
/// 文件内容走 GitHub Contents API，而该接口对**超过 1 MB 的文件不返回内容**。
/// 音频几乎必然超限，所以**不做内置播放**是接口决定的，不是偷懒 —— 页面会
/// 明说原因，并指引到「下载后用系统播放器」。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/async.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/accel.dart';
import '../util/download_proxy.dart';
import '../util/file_preview.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../util/og_l_space.dart';
import '../widgets/code_editor_field.dart';
import 'download_manager_page.dart';
import 'settings_page.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'common', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 文件预览页。
class FilePreviewPage extends StatefulWidget {
  /// 创建页面。
  const FilePreviewPage({
    required this.surface,
    required this.fullName,
    required this.path,
    this.branch = 'main',
    this.kind = OgLPreviewKind.image,
    this.repoPrivate = false,
    this.size = 0,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 文件路径。
  final String path;

  /// 分支。
  final String branch;

  /// 预览方式（由调用方用 `ogLPreviewKindOf` 判定后传入）。
  final OgLPreviewKind kind;

  /// 仓库是否私有（决定仓库文件的取法：私有只能走 API 带认证）。
  final bool repoPrivate;

  /// 文件大小（0 = 未知；决定是否值得走加速）。
  final int size;

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  bool _loading = true;
  String? _error;
  Uint8List? _bytes;

  /// 已加入下载（按钮改文案，避免重复点）。
  bool _queued = false;
  bool _busy = false;

  /// 内容超过 Contents API 的单文件上限（1 MB）时为 true。
  bool _tooLarge = false;

  /// 用户已确认「改用 raw 链接」。
  bool _useRaw = false;

  /// raw 直链（`raw.githubusercontent.com`）。
  String get _rawUrl => 'https://raw.githubusercontent.com/${widget.fullName}/'
      '${Uri.encodeComponent(widget.branch)}/'
      '${widget.path.split('/').map(Uri.encodeComponent).join('/')}';

  /// 加速是否已开启（内置或自定义任一）。
  ///
  /// 判定只看**是否启用**，不看选的是哪个通道 —— 按产品要求：
  /// 开启加速（无论内置还是自定义）后**不再弹窗**；只有**加速关闭**时才问。
  bool get _accelOn => widget.surface.settings.settings
      .accelPrefixesFor(OgLAccelScope.repoFile)
      .isNotEmpty;

  /// 加速已开启时的 raw 地址候选（含直连兜底）；未开启时只给直连。
  List<String> get _rawCandidates {
    // 预览页取的是「仓库文件」这一类；范围没开就等于没加速。
    final List<String> prefixes = widget.surface.settings.settings
        .accelPrefixesFor(OgLAccelScope.repoFile);
    return ogLAccelCandidates(
      url: _rawUrl,
      prefixes: prefixes,
      family: OgLAccelFamily.raw,
      repoPrivate: widget.repoPrivate,
      // 私有 + 加速：需用户已在设置页知情接受（否则令牌绝不出设备）。
      privateAccelAccepted:
          widget.surface.settings.settings.accelPrivateRepoAccepted,
      // 大小未知：raw 族的加速判定已有「内置通道」的门槛。
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // 重试前**复位错误态**：否则重试成功后仍会卡在错误页
    //（`_buildBody` 先看 `_error`，旧错误没清就永远看不到内容）。
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _tooLarge = false;
      });
    }
    try {
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        widget.path,
        branch: widget.branch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        setState(() {
          _loading = false;
          _error = _t('previewTooLarge');
        });
        return;
      }
      final String encoding = '${content.raw['encoding'] ?? ''}';
      final String encoded = '${content.raw['content'] ?? ''}';
      if (encoded.isEmpty) {
        // Contents API 对 >1 MB 的文件不回内容 —— 如实说明，不假装加载失败。
        setState(() {
          _loading = false;
          _tooLarge = true;
        });
        return;
      }
      final Uint8List bytes = encoding == 'base64'
          ? base64Decode(encoded.replaceAll('\n', ''))
          : Uint8List.fromList(utf8.encode(encoded));
      setState(() {
        _loading = false;
        _bytes = bytes;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  /// 浏览器里的文件页地址（私有仓库需要登录，故只作兜底）。
  String get _htmlUrl =>
      'https://github.com/${widget.fullName}/blob/${widget.branch}/${widget.path}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ghPathName(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: _t('openInBrowser'),
            onPressed: () =>
                unawaited(openLinkOrCopy(context, _htmlUrl, tag: 'Preview')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final String? error = _error;
    if (error != null) {
      return OgLAsyncErrorPane(message: error, onRetry: _load);
    }
    if (_tooLarge) {
      // 大文件（Contents API 对 > 1 MB 不回内容）：按类型给出**可用的动作**，
      // 而不是丢一句「太大」就完了。取法见 [_tooLargePane]。
      return _tooLargePane(theme);
    }
    final Uint8List? bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      return _notice(theme, Icons.info_outline, _t('previewTooLarge'));
    }
    switch (widget.kind) {
      case OgLPreviewKind.image:
        return _image(bytes);
      case OgLPreviewKind.audio:
        return _audioCard(theme);
      case OgLPreviewKind.svg:
        // SVG 优先按矢量渲染；渲染失败时**如实退化为源码**（见 [_svg]）。
        return _svg(bytes);
      case OgLPreviewKind.xml:
      case OgLPreviewKind.unknown:
        return _text(bytes);
    }
  }

  /// 图片：可缩放查看（Material 自带 `InteractiveViewer`，不引额外依赖）。
  ///
  /// 解码按**屏幕尺寸**降采样（`cacheWidth`）：手机原图常是 12MP，全分辨率
  /// 解码一次占 48MB 位图内存、主线程卡数百毫秒；显示区只有一屏，缩放由
  /// `InteractiveViewer` 对已降采样位图做 GPU 变换，清晰度足够。
  Widget _image(Uint8List bytes) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final Size screen = MediaQuery.sizeOf(context);
    final int targetWidth = (screen.width * dpr).round();
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 6,
      child: Center(
        child: Image.memory(
          bytes,
          cacheWidth: targetWidth,
          fit: BoxFit.contain,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) =>
                  _notice(Theme.of(context), Icons.broken_image_outlined,
                      _t('previewTooLarge')),
        ),
      ),
    );
  }

  /// SVG：矢量渲染（可缩放），失败或超限时退化为源码。
  ///
  /// 为什么给退化路径：SVG 也可能是超大文件或被 Contents API 截断的内容，
  /// 渲染不出来时**让用户看到源码**比显示一句「加载失败」有用得多。
  Widget _svg(Uint8List bytes) {
    final String source = _textOf(bytes);
    return Column(
      children: <Widget>[
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 8,
            child: Center(
              child: SvgPicture.string(
                source,
                fit: BoxFit.contain,
                placeholderBuilder: (BuildContext context) => _text(bytes),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 文本族（XML / 其它）：复用既有代码查看器（自带语法高亮与查找）。
  /// 源码文本缓存（按字节身份）：重试 / 切换显示模式时不再重复 decode
  /// 最多 1MB 的内容（SVG 失败退化路径此前还会 decode 两遍）。
  Uint8List? _textSource;
  String? _textCache;

  String _textOf(Uint8List bytes) {
    if (identical(_textSource, bytes) && _textCache != null) {
      return _textCache!;
    }
    final String source = utf8.decode(bytes, allowMalformed: true);
    _textSource = bytes;
    _textCache = source;
    return source;
  }

  Widget _text(Uint8List bytes) {
    final String source = _textOf(bytes);
    return Column(
      children: <Widget>[
        if (widget.kind == OgLPreviewKind.svg)
          _banner(Theme.of(context), Icons.info_outline, _t('previewSvgHint')),
        Expanded(
          child: OgLCodeViewer(
            code: source,
            path: widget.path,
            fontSize: widget.surface.settings.settings.codeFontSize,
            wrap: widget.surface.settings.settings.codeWrap,
            highlight: widget.surface.settings.settings.codeHighlight,
            codeTheme: ogLCodeThemeFor(
              preset: widget.surface.settings.settings.codeThemePreset,
              scheme: Theme.of(context).colorScheme,
              customBackground:
                  widget.surface.settings.settings.codeColorBackground,
              customForeground:
                  widget.surface.settings.settings.codeColorForeground,
              customKeyword: widget.surface.settings.settings.codeColorKeyword,
              customTypeName:
                  widget.surface.settings.settings.codeColorTypeName,
              customString: widget.surface.settings.settings.codeColorString,
              customComment: widget.surface.settings.settings.codeColorComment,
              customNumber: widget.surface.settings.settings.codeColorNumber,
            ),
          ),
        ),
      ],
    );
  }

  /// > 1 MB 时的取法面板。
  ///
  /// ## 产品规则（用户明确要求）
  /// - **加速已开启**（内置或自定义任一）→ **不弹窗**，直接用 raw 链接；
  /// - **加速关闭** → 弹窗让用户选：改用 raw 链接 / 前往设置调整加速方式。
  ///
  /// 之所以要问：raw 直链走的是与 Contents API 不同的链路；用户有权知道
  /// 自己换了取法。
  ///
  /// ## 私有仓库（v6.4.0 修正，v6.4.1 放宽）
  /// 「加速已开启 → 不弹窗」原先只对公开仓库成立：私有仓库的 raw 默认不加速，
  /// 照搬「不弹窗直接走 raw」会让用户掉进一个必然失败的分支。
  /// v6.4.1 起，私有仓库若用户已在设置页**知情接受**「令牌交给第三方代理」，
  /// 则与公开仓库一样静默走 raw + 加速；未接受则照常弹窗如实说明。
  Widget _tooLargePane(ThemeData theme) {
    final bool privateOk = !widget.repoPrivate ||
        widget.surface.settings.settings.accelPrivateRepoAccepted;
    if (_useRaw || (_accelOn && privateOk)) {
      return _rawView(theme);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OgLSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.data_usage, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: OgLSpace.md),
            Text(
              _t('fileTooLargeTitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: OgLSpace.sm),
            Text(
              // 私有仓库 + 未接受加速：多给一句实话，别让人白去设置里找开关。
              // 已接受的私有仓库与公开仓库同等待遇，不需要这句解释。
              (widget.repoPrivate &&
                      !widget
                          .surface.settings.settings.accelPrivateRepoAccepted)
                  ? _t('fileTooLargeBodyPrivate')
                  : _t('fileTooLargeBody'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: OgLSpace.xl),
            FilledButton.icon(
              onPressed: () => setState(() => _useRaw = true),
              icon: const Icon(Icons.link),
              label: Text(_t('useRawLink')),
            ),
            const SizedBox(height: OgLSpace.sm),
            OutlinedButton.icon(
              onPressed: () => unawaited(_openSettings()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(_t('goToSettings')),
            ),
          ],
        ),
      ),
    );
  }

  /// 跳转设置页（用户去调整加速方式）。
  Future<void> _openSettings() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext context) => SettingsPage(surface: widget.surface),
    ));
    // 回来时按新的加速设置重判一次取法。
    if (mounted) {
      setState(() {});
    }
  }

  /// 用 raw 链接渲染（图片直接显示；音频交系统播放器）。
  ///
  /// ## 认证头：这里曾有一个必然失败的分支
  /// 私有仓库的 raw 直链**必须带 `Authorization`**（raw 没有签名机制）。
  /// 原实现写成：
  /// ```dart
  /// headers: proxied || !widget.repoPrivate ? null : const <String, String>{},
  /// ```
  /// 注释说「未走代理且是私有仓库才带」，但那个分支给的是**空 map** ——
  /// 一个头都没带。于是私有仓库的大图预览 100% 404，而界面把它显示成
  /// 「文件过大，无法在内置预览中加载」，把**认证失败**误报成**文件过大**。
  ///
  /// 现在改为：**私有仓库一律取一次令牌**（`downloadAuthHeaders`，取不到就
  /// 退化成空 map，那才是「匿名访问」的诚实表达）；公开仓库一个头都不带。
  /// 判据是「仓库是否私有」，不是「是否走了代理」—— 通道会原样转发
  /// Authorization 头，私有仓库即便走通道也必须带上令牌才能取到内容。
  Widget _rawView(ThemeData theme) {
    final List<String> urls = _rawCandidates;
    if (urls.isEmpty) {
      return _notice(theme, Icons.link_off, _t('fileTooLargeTitle'));
    }
    final String url = urls.first;

    switch (widget.kind) {
      case OgLPreviewKind.image:
        return FutureBuilder<Map<String, String>>(
          // ★ 判据是「私有仓库」，不是「是否走代理」。
          //   私有仓库的 raw 一律需要令牌 —— 即便走了代理也一样
          //   （实测：代理会原样转发 Authorization 头，没有它代理自己也取不到）。
          //   公开仓库则相反：一个头都不该带。
          //   旧写法 `proxied || !repoPrivate` 会在「私有 + 已接受加速」时
          //   给出空头，于是代理拿到一个取不到内容的地址 —— 必然 404。
          future: widget.repoPrivate
              ? widget.surface.downloadAuthHeaders()
              : Future<Map<String, String>>.value(const <String, String>{}),
          builder:
              (BuildContext context, AsyncSnapshot<Map<String, String>> snap) {
            final Map<String, String> headers =
                snap.data ?? const <String, String>{};
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 6,
              child: Center(
                child: Image.network(
                  url,
                  // 空 map 等同不带头；这里只在私有仓库且未走代理时才有内容。
                  headers: headers.isEmpty ? null : headers,
                  fit: BoxFit.contain,
                  loadingBuilder: (BuildContext context, Widget child,
                          ImageChunkEvent? progress) =>
                      progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                  errorBuilder:
                      (BuildContext context, Object error, StackTrace? stack) =>
                          // ★ 这里**不能**说「文件过大」：>1 MB 已经由
                          //   `_tooLargePane` 处理过了，走到这里说明是加载失败
                          //   （认证、限流、网络），说成文件过大会让人白折腾。
                          _notice(theme, Icons.broken_image_outlined,
                              _t('previewLoadFailed')),
                ),
              ),
            );
          },
        );
      case OgLPreviewKind.audio:
        // 音频必然超限：默认就给出「用系统播放器打开」这条唯一可行的路。
        return _audioCard(theme, rawUrl: url);
      case OgLPreviewKind.svg:
      case OgLPreviewKind.xml:
      case OgLPreviewKind.unknown:
        // 文本类 > 1 MB 不在预览页展开（编辑器才是它的去处）。
        return _notice(
            theme, Icons.description_outlined, _t('fileTooLargeTitle'));
    }
  }

  /// 音频：**给动作，不给空话**。
  ///
  /// 内置播放做不到（Contents API 对 >1 MB 不回内容，音频必然超限），所以这里
  /// 直接把出路摆出来。取法与仓库页完全一致
  /// （`SurfaceBridge.planRepoFileDownload`）：不加速走 API 带认证，加速走代理 + raw。
  ///
  /// ## 私有仓库不给「播放」（v6.4.0 修正）
  /// 「播放」是把 raw 地址交给**系统播放器**——进程之外的程序，它没有本应用的
  /// 令牌，私有仓库的 raw 一律 404。此前私有仓库也会显示这个按钮，等于给一个
  /// 点了必然失败的动作。私有仓库只给「下载」（下载走本应用的传输层，带认证）。
  Widget _audioCard(ThemeData theme, {String? rawUrl}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.music_note_outlined,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: OgLSpace.md),
              Text(
                _t('previewAudioHint'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: OgLSpace.xl),
              // 有 raw 地址时优先给「播放」：这是**真的能听到声音**的那条路
              // （走系统播放器；应用内播放需要额外音频依赖且音频必然超过
              //  Contents API 的 1 MB 上限，内置播放本就不成立）。
              // ★ 私有仓库不给：系统播放器没有本应用的令牌，点了必然 404。
              if (rawUrl != null && rawUrl.isNotEmpty && !widget.repoPrivate)
                FilledButton.icon(
                  onPressed: () =>
                      unawaited(openLinkOrCopy(context, rawUrl, tag: 'Audio')),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_t('previewAudioPlay')),
                ),
              if (rawUrl != null && rawUrl.isNotEmpty && !widget.repoPrivate)
                const SizedBox(height: OgLSpace.sm),
              OutlinedButton.icon(
                onPressed:
                    (_busy || _queued) ? null : () => unawaited(_enqueueFile()),
                icon: const Icon(Icons.download_outlined),
                label: Text(_t('download')),
              ),
            ],
          ),
        ),
      );

  /// 把当前文件加入下载（音频预览的出路）。
  Future<void> _enqueueFile() async {
    setState(() => _busy = true);
    try {
      final ({List<String> urls, Map<String, String> headers}) plan =
          await widget.surface.planRepoFileDownload(
        fullName: widget.fullName,
        path: widget.path,
        branch: widget.branch,
        repoPrivate: widget.repoPrivate,
        size: widget.size > 0 ? widget.size : null,
      );
      await widget.surface.domain.downloads.enqueue(
        url: plan.urls.first,
        fallbackUrls: plan.urls.skip(1).toList(),
        headers: plan.headers,
        fileName: ghPathName(widget.path),
        category: IxDownloadCategory.repo,
        connections: widget.surface.settings.settings.downloadConnections,
      );
      if (mounted) {
        setState(() => _queued = true);
        OgLDownloadNotice.instance.show(context, widget.surface,
            message: _t('addedToDownload', <String, Object?>{
              'name': ghPathName(widget.path),
            }));
      }
    } catch (error) {
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('addDownloadFailed', <String, Object?>{'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _notice(ThemeData theme, IconData icon, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(OgLSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: OgLSpace.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  Widget _banner(ThemeData theme, IconData icon, String message) => Container(
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(
            horizontal: OgLSpace.md, vertical: OgLSpace.sm),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: OgLSpace.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
}
