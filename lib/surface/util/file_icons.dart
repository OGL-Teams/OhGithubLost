/// L3 展示级 · 文件类型视觉（图标 + 颜色，**唯一实现处**）。
///
/// 为什么单独成文件：
/// - 仓库浏览器 / 详情弹窗 / 搜索结果都要"按语言区分图标"，
///   若各页各写一份 switch，很快就会出现"同一个 `.py` 在两处图标不一样"；
/// - 这里只保留一组**纯函数**（无网络、无状态），便于单测。
///
/// 颜色采用固定调色板而非主题色：类型色是"语义色"，
/// 不应随明暗主题漂移，否则深色下某些色会糊成一团。
library;

import 'package:flutter/material.dart';

/// 一个文件（或目录）在列表里的视觉表示。
@immutable
class OgLFileVisual {
  /// 创建视觉。
  const OgLFileVisual(this.icon, this.color);

  /// 图标字形。
  final IconData icon;

  /// 类型色（`null` 表示跟随主题前景色）。
  final Color? color;
}

/// 目录统一视觉（文件夹优先展示时也靠它一眼区分）。
const OgLFileVisual kOgLDirectoryVisual =
    OgLFileVisual(Icons.folder, Color(0xFFE8B04B));

/// 未知类型文件。
const OgLFileVisual kOgLGenericFileVisual =
    OgLFileVisual(Icons.description_outlined, null);

/// 取路径的 basename（`lib/main.dart` → `main.dart`）。
String ogLBaseName(String path) {
  final int slash = path.lastIndexOf('/');
  return slash >= 0 ? path.substring(slash + 1) : path;
}

/// 取小写扩展名（无扩展名返回空串；`.gitignore` 这类点开头的不算扩展名）。
String ogLExtension(String path) {
  final String base = ogLBaseName(path).toLowerCase();
  final int dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) {
    return '';
  }
  return base.substring(dot + 1);
}

/// 根据路径给出图标与颜色（纯函数，可单测）。
OgLFileVisual ogLFileVisualFor(String path, {bool isDirectory = false}) {
  if (isDirectory) {
    return kOgLDirectoryVisual;
  }
  final String base = ogLBaseName(path).toLowerCase();
  final String ext = ogLExtension(path);

  switch (ext) {
    // ── 代码 ──
    case 'dart':
      return const OgLFileVisual(Icons.code, Color(0xFF2BB3A3));
    case 'js':
    case 'mjs':
    case 'cjs':
      return const OgLFileVisual(Icons.javascript, Color(0xFFE8C33A));
    case 'ts':
      return const OgLFileVisual(Icons.code, Color(0xFF3178C6));
    case 'jsx':
    case 'tsx':
      return const OgLFileVisual(Icons.code, Color(0xFF61DAFB));
    case 'py':
      return const OgLFileVisual(Icons.functions, Color(0xFF3B78A8));
    case 'java':
    case 'scala':
    case 'groovy':
      return const OgLFileVisual(Icons.code, Color(0xFFB07219));
    case 'kt':
    case 'kts':
      return const OgLFileVisual(Icons.code, Color(0xFFA97BFF));
    case 'go':
      return const OgLFileVisual(Icons.code, Color(0xFF00ADD8));
    case 'rs':
      return const OgLFileVisual(Icons.code, Color(0xFFDEA584));
    case 'c':
    case 'h':
      return const OgLFileVisual(Icons.code, Color(0xFF555555));
    case 'cpp':
    case 'cc':
    case 'cxx':
    case 'hpp':
    case 'hh':
      return const OgLFileVisual(Icons.code, Color(0xFFF34B7D));
    case 'cs':
      return const OgLFileVisual(Icons.code, Color(0xFF178600));
    case 'rb':
      return const OgLFileVisual(Icons.diamond, Color(0xFF701516));
    case 'php':
      return const OgLFileVisual(Icons.code, Color(0xFF787CB5));
    case 'swift':
      return const OgLFileVisual(Icons.code, Color(0xFFF05138));
    case 'sh':
    case 'bash':
    case 'zsh':
    case 'fish':
      return const OgLFileVisual(Icons.terminal, Color(0xFF4EAA25));
    case 'ps1':
      return const OgLFileVisual(Icons.terminal, Color(0xFF012456));
    case 'lua':
      return const OgLFileVisual(Icons.code, Color(0xFF000080));
    case 'r':
      return const OgLFileVisual(Icons.analytics_outlined, Color(0xFF276DC3));

    // ── Web / 标记 ──
    case 'html':
    case 'htm':
      return const OgLFileVisual(Icons.html, Color(0xFFE34C26));
    case 'css':
    case 'scss':
    case 'sass':
    case 'less':
      return const OgLFileVisual(Icons.css, Color(0xFF563D7C));
    case 'vue':
    case 'svelte':
      return const OgLFileVisual(Icons.web, Color(0xFF41B883));
    case 'xml':
      return const OgLFileVisual(Icons.code, Color(0xFFE37933));
    case 'svg':
      return const OgLFileVisual(Icons.image_outlined, Color(0xFFFF9900));

    // ── 数据 / 配置 ──
    case 'json':
      return const OgLFileVisual(Icons.data_object, Color(0xFFCBA135));
    case 'yaml':
    case 'yml':
      return const OgLFileVisual(Icons.tune, Color(0xFFCB171E));
    case 'toml':
    case 'ini':
    case 'cfg':
    case 'conf':
    case 'properties':
      return const OgLFileVisual(Icons.settings_suggest, Color(0xFF9AA0A6));
    case 'csv':
    case 'tsv':
      return const OgLFileVisual(Icons.table_chart_outlined, Color(0xFF3E8E41));
    case 'sql':
      return const OgLFileVisual(Icons.storage, Color(0xFF00758F));
    case 'graphql':
    case 'gql':
      return const OgLFileVisual(Icons.hub_outlined, Color(0xFFE10098));
    case 'proto':
      return const OgLFileVisual(Icons.hub_outlined, Color(0xFF5A5FD0));
    case 'gradle':
      return const OgLFileVisual(Icons.build_outlined, Color(0xFF02303A));
    case 'ipynb':
      return const OgLFileVisual(Icons.science_outlined, Color(0xFFDA5B0B));
    case 'lock':
      return const OgLFileVisual(Icons.lock_outline, Color(0xFF9AA0A6));
    case 'wasm':
      return const OgLFileVisual(Icons.memory, Color(0xFF654FF0));
    case 'vtt':
    case 'srt':
      return const OgLFileVisual(Icons.subtitles_outlined, Color(0xFF9AA0A6));
    case 'geojson':
      return const OgLFileVisual(Icons.public, Color(0xFF3E8E41));

    // ── 文档 ──
    case 'md':
    case 'markdown':
      return const OgLFileVisual(Icons.article_outlined, Color(0xFF083FA1));
    case 'txt':
    case 'log':
      return const OgLFileVisual(Icons.notes, Color(0xFF9AA0A6));
    case 'rst':
      return const OgLFileVisual(Icons.article_outlined, Color(0xFF9AA0A6));
    case 'pdf':
      return const OgLFileVisual(Icons.picture_as_pdf, Color(0xFFD93831));
    case 'doc':
    case 'docx':
      return const OgLFileVisual(Icons.description, Color(0xFF2B579A));
    case 'xls':
    case 'xlsx':
      return const OgLFileVisual(Icons.table_chart, Color(0xFF217346));
    case 'ppt':
    case 'pptx':
      return const OgLFileVisual(Icons.slideshow, Color(0xFFD24726));

    // ── 媒体 ──
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'ico':
    case 'tif':
    case 'tiff':
      return const OgLFileVisual(Icons.image_outlined, Color(0xFFB07219));
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'ogg':
    case 'm4a':
      return const OgLFileVisual(Icons.audiotrack, Color(0xFF1DB954));
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'avi':
    case 'webm':
      return const OgLFileVisual(Icons.movie_outlined, Color(0xFFE04E39));

    // ── 压缩 / 二进制 ──
    case 'zip':
    case 'tar':
    case 'gz':
    case 'tgz':
    case 'bz2':
    case 'xz':
    case '7z':
    case 'rar':
      return const OgLFileVisual(Icons.folder_zip_outlined, Color(0xFF9A7B4F));
    case 'exe':
    case 'dll':
    case 'so':
    case 'dylib':
    case 'bin':
    case 'apk':
    case 'aab':
    case 'ipa':
      return const OgLFileVisual(Icons.memory, Color(0xFF6E7B8B));

    // ── 字体 / 证书 ──
    case 'ttf':
    case 'otf':
    case 'woff':
    case 'woff2':
      return const OgLFileVisual(
          Icons.font_download_outlined, Color(0xFF8A6FD1));
    case 'pem':
    case 'crt':
    case 'cer':
    case 'key':
    case 'p12':
      return const OgLFileVisual(Icons.lock_outline, Color(0xFFC0392B));
    default:
      break;
  }

  // ── 无扩展名 / 特殊文件名 ──
  switch (base) {
    case 'dockerfile':
    case 'containerfile':
      return const OgLFileVisual(Icons.terminal, Color(0xFF0DB7ED));
    case 'makefile':
    case 'gnumakefile':
      return const OgLFileVisual(Icons.build_outlined, Color(0xFF6E7B8B));
    case '.gitignore':
    case '.gitattributes':
    case '.gitmodules':
    case '.dockerignore':
      return const OgLFileVisual(
          Icons.account_tree_outlined, Color(0xFFF14E32));
    case 'license':
    case 'licence':
    case 'copying':
    case 'notice':
      return const OgLFileVisual(Icons.gavel, Color(0xFF9AA0A6));
    case '.env':
    case '.env.local':
      return const OgLFileVisual(Icons.key_outlined, Color(0xFFE8B04B));
    case 'readme':
    case 'readme.md':
    case 'changelog':
    case 'changelog.md':
      return const OgLFileVisual(Icons.menu_book_outlined, Color(0xFF519ABA));
    default:
      return kOgLGenericFileVisual;
  }
}
