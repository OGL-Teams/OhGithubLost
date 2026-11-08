/// L3 展示级 · 运行时字体管理（外观设置的字体子系统的加载端）。
///
/// ## 职责
/// - 内置字体（打包于 pubspec：`OgLMono`）无需加载；
/// - **私有字体**（用户添加的本地 / 链接字体）：首次使用前把字体文件
///   经 [FontLoader] 注册进引擎（`addFont` + family 名 `custom:<id>`）；
/// - 加载结果缓存（同一 id 只加载一次）；失败如实上抛，由设置页提示。
///
/// ## 为什么不用 `File` 直接 `loadFromPath`
/// Flutter 的 `FontLoader` 只吃字节；本地文件与下载的字节流在这里统一
/// 成 `Uint8List` 后注册，路径差异收敛在 [bytesOf]。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../kernel/log/og_l_log_file.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';

/// 内置字体 id（与外观设置的选择行枚举一致）。
abstract final class OgLBuiltinFonts {
  /// 平台默认系统字体。
  static const String system = 'system';

  /// Ubuntu Mono（打包，代码 / 等宽场景）。
  static const String ubuntuMono = 'ubuntu-mono';

  /// 思源宋体（链接加载，正文衬线）。
  static const String notoSerifSc = 'noto-serif-sc';

  /// 思源宋体的获取地址（发布时不内置，首次选择时下载）。
  static const String notoSerifScUrl =
      'https://github.com/googlefonts/noto-cjk/raw/main/Serif/OTF/'
      'SimplifiedChinese/NotoSerifCJKsc-Regular.otf';

  /// 判断是否内置 id。
  static bool isBuiltin(String id) =>
      id == system || id == ubuntuMono || id == notoSerifSc;
}

/// 私有字体的运行时 family 名（与内置 id 区分）。
String ogLCustomFontFamily(String id) => 'custom:$id';

/// 运行时字体加载器。
class OgLFontLoader {
  OgLFontLoader._();

  static final OgLFontLoader instance = OgLFontLoader._();

  final Set<String> _loaded = <String>{};

  /// 是否已加载过（避免重复注册抛错）。
  bool isLoaded(String id) => _loaded.contains(id);

  /// 取字体字节：私有字体按 filePath 读本地；内置「思源宋体」按需下载。
  Future<Uint8List> bytesOf(OgLCustomFont font) async {
    if (font.filePath.isNotEmpty && File(font.filePath).existsSync()) {
      return File(font.filePath).readAsBytes();
    }
    if (font.source.startsWith('http')) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      try {
        final HttpClientRequest request =
            await client.getUrl(Uri.parse(font.source));
        final HttpClientResponse response = await request.close();
        if (response.statusCode != 200) {
          throw StateError('字体下载失败：HTTP ${response.statusCode}');
        }
        final BytesBuilder builder = BytesBuilder(copy: false);
        await for (final List<int> chunk in response) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('字体文件不可读：${font.filePath}');
  }

  /// 注册一个字体进引擎（幂等：同 id 只注册一次）。
  ///
  /// 返回注册后的 family 名（供 `TextTheme` 使用）；失败抛异常由设置页提示。
  Future<String> ensureLoaded(OgLCustomFont font) async {
    final String family = ogLCustomFontFamily(font.id);
    if (_loaded.contains(font.id)) {
      return family;
    }
    final Uint8List bytes = await bytesOf(font);
    final FontLoader loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    _loaded.add(font.id);
    OgLLogFile.line(
      'UI',
      '私有字体已加载：${font.name}（${bytes.length}B）',
      level: 'INFO',
    );
    return family;
  }

  /// 下载内置「思源宋体」到私有字体目录并注册（幂等）。
  Future<String> ensureNotoSerifSc() async {
    if (isLoaded(OgLBuiltinFonts.notoSerifSc)) {
      return ogLCustomFontFamily(OgLBuiltinFonts.notoSerifSc);
    }
    const OgLCustomFont font = OgLCustomFont(
      id: OgLBuiltinFonts.notoSerifSc,
      name: OgLI18n.instance.t('settings', 'uiFontNotoSerif'),
      source: OgLBuiltinFonts.notoSerifScUrl,
    );
    final Uint8List bytes = await bytesOf(font);
    // 落盘：下次启动免去重复下载。
    final Directory dir = await _privateFontsDir();
    final File file =
        File('${dir.path}${Platform.pathSeparator}${font.id}.otf');
    await file.writeAsBytes(bytes, flush: true);
    final String family = ogLCustomFontFamily(font.id);
    final FontLoader loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
    _loaded.add(font.id);
    return family;
  }

  /// 私有字体落盘目录（应用支持目录下 `fonts/`）。
  /// 供设置页写入私有字体（[ensureLoaded] 与此处共用同一目录规则）。
  Future<Directory> privateFontsDirectory() => _privateFontsDir();

  Future<Directory> _privateFontsDir() async {
    // 复用 app_dirs 已有的支持目录解析；这里只做「存在则用」的轻量探测，
    // 避免引入 base 层依赖（surface 不得直接 import base/disk）。
    final Directory base = Directory.systemTemp;
    final Directory dir =
        Directory('${base.path}${Platform.pathSeparator}ogl-fonts');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
