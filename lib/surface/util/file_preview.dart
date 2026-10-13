/// L3 展示级 · 文件预览的**类型判定**与可用方式（纯函数，便于单测）。
///
/// ## 为什么需要「多种打开方式」
/// 同一份文件在不同场景下要用不同方式看：图片当然要渲染出来，但**SVG 既可以
/// 当矢量图渲染、也可以当源码看**；XML 更像文本；音频只能交给系统播放器。
/// 因此这里只做判定，由界面列出「可行的方式」并标出默认项。
///
/// ## 一条硬约束（决定了音频不做内置播放）
/// 仓库文件走 GitHub Contents API，而该接口对**超过 1 MB 的文件不返回内容**
/// （`isTooLarge`）。音频文件几乎必然超过这个阈值，所以**内置播放本来就不可能
/// 实现**——正确做法是下载后用系统播放器打开。
library;

/// 预览方式。
enum OgLPreviewKind {
  /// 位图：内置渲染（默认方式）。
  image,

  /// 矢量图：可渲染（flutter_svg），也可看源码。
  svg,

  /// XML 家族：按文本 + 语法高亮看。
  xml,

  /// 音频：交系统播放器（Contents API 拿不到大文件字节，无法内置播放）。
  audio,

  /// 未知：不提供预览，只提供下载 / 浏览器打开。
  unknown,
}

const Set<String> _kImageExt = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'ico',
  'avif',
  'tif',
  'tiff',
};

const Set<String> _kAudioExt = <String>{
  'mp3',
  'm4a',
  'wav',
  'ogg',
  'oga',
  'flac',
  'aac',
  'opus',
  'wma',
  'mid',
};

const Set<String> _kXmlExt = <String>{
  'xml',
  'xsd',
  'xsl',
  'xslt',
  'plist',
  'csproj',
  'vcxproj',
  'props',
  'targets',
  'xaml',
  'rss',
  'atom',
  'pom',
  'gradle',
  'iml',
  'storyboard',
  'xib',
};

/// 取小写扩展名（无扩展名返回空串）。
String ogLExtensionOf(String path) {
  final String name = path.split('/').last;
  final int dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

/// 判定预览方式。
OgLPreviewKind ogLPreviewKindOf(String path) {
  final String ext = ogLExtensionOf(path);
  if (ext.isEmpty) {
    return OgLPreviewKind.unknown;
  }
  if (ext == 'svg') {
    return OgLPreviewKind.svg;
  }
  if (_kImageExt.contains(ext)) {
    return OgLPreviewKind.image;
  }
  if (_kAudioExt.contains(ext)) {
    return OgLPreviewKind.audio;
  }
  if (_kXmlExt.contains(ext)) {
    return OgLPreviewKind.xml;
  }
  return OgLPreviewKind.unknown;
}

/// 该类型是否**值得直接进预览**（否则应按老路子当文本看）。
///
/// 位图与音频：按文本看毫无意义，直接进预览。
/// SVG / XML：源码本身有意义，保持进查看器，由「打开方式」提供渲染选项。
bool ogLPreviewFirst(OgLPreviewKind kind) =>
    kind == OgLPreviewKind.image || kind == OgLPreviewKind.audio;

/// 判定能否**内置渲染**。
///
/// 位图与 SVG 都能渲染：位图用 Flutter 自带的 `Image`，SVG 由 `flutter_svg`
/// （纯 Dart，无原生依赖）。音频不能内置播放（见文件头的接口约束说明）。
bool ogLCanRenderInline(OgLPreviewKind kind) =>
    kind == OgLPreviewKind.image || kind == OgLPreviewKind.svg;

/// 判定能否进**文本编辑器**。
///
/// 位图 / 音频等二进制按文本解码（`allowMalformed`）会产出乱码，
/// 保存后即"用乱码覆盖原文件"—— 这是数据损坏路径，必须拦在入口。
/// SVG / XML / 文本类仍然可编辑（源码本身就是有意义的内容）。
bool ogLCanEditAsText(OgLPreviewKind kind) =>
    kind != OgLPreviewKind.image && kind != OgLPreviewKind.audio;

/// i18n 键（`common` 分片）→ 打开方式的展示名。
String ogLPreviewKindKey(OgLPreviewKind kind) => switch (kind) {
      OgLPreviewKind.image => 'previewImage',
      OgLPreviewKind.svg => 'previewSvg',
      OgLPreviewKind.xml => 'previewXml',
      OgLPreviewKind.audio => 'previewAudio',
      OgLPreviewKind.unknown => 'previewUnknown',
    };
