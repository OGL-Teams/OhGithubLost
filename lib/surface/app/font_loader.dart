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
      'https://raw.githubusercontent.com/googlefonts/noto-cjk/main/Serif/OTF/'
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
  final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  /// 是否已加载过（避免重复注册抛错）。
  bool isLoaded(String id) => _loaded.contains(id);

  /// 取字体字节：私有字体按 filePath 读本地；内置「思源宋体」按需下载。
  Future<Uint8List> bytesOf(OgLCustomFont font) async {
    if (font.filePath.isNotEmpty && File(font.filePath).existsSync()) {
      return File(font.filePath).readAsBytes();
    }
    if (font.source.startsWith('http')) {
      // ★ B7-A-03/04：下载前先查私有字体目录的落盘缓存——思源宋体 ~30MB，
      //   此前每次冷启动都整只重新下载，落盘文件只写不读。
      final File cached = File(
        '${(await privateFontsDirectory()).path}'
        '${Platform.pathSeparator}'
        '${font.id}${_extOf(font.source)}',
      );
      if (cached.existsSync()) {
        final Uint8List bytes = await cached.readAsBytes();
        if (_looksLikeFont(bytes)) {
          return bytes;
        }
        OgLLogFile.line('UI', '字体缓存损坏，已丢弃：${cached.path}', level: 'ERR');
        await cached.delete();
      }
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      try {
        final HttpClientRequest request =
            await client.getUrl(Uri.parse(font.source));
        final HttpClientResponse response = await request.close();
        if (response.statusCode != 200) {
          throw StateError('字体下载失败：HTTP ${response.statusCode}');
        }
        const int maxBytes = 64 * 1024 * 1024; // 思源宋体 ~24MB
        final BytesBuilder builder = BytesBuilder(copy: false);
        int total = 0;
        await for (final List<int> chunk in response) {
          total += chunk.length;
          if (total > maxBytes) {
            throw StateError('字体下载超出大小上限');
          }
          builder.add(chunk);
        }
        final Uint8List bytes = builder.takeBytes();
        if (!_looksLikeFont(bytes)) {
          throw StateError('下载内容不是有效字体文件（HTML / 截断？）');
        }
        // ★ 原子落盘：先 .part 再 rename，中断不留半截缓存。
        try {
          final File part = File('${cached.path}.part');
          await part.writeAsBytes(bytes, flush: true);
          await part.rename(cached.path);
        } on Object catch (error) {
          OgLLogFile.line('UI', '字体缓存落盘失败：$error', level: 'ERR');
        }
        return bytes;
      } on Object catch (error) {
        // ★ 失败如实留痕（此前静默抛给上层）。
        OgLLogFile.line('UI', '字体下载失败：${font.source} · $error', level: 'ERR');
        rethrow;
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('字体文件不可读：${font.filePath}');
  }

  /// 注册一个字体进引擎（幂等：同 id 只注册一次）。
  ///
  /// 返回注册后的 family 名（供 `TextTheme` 使用）；失败抛异常由设置页提示。
  Future<String> ensureLoaded(OgLCustomFont font) {
    final String family = ogLCustomFontFamily(font.id);
    if (_loaded.contains(font.id)) {
      return Future<String>.value(family);
    }
    final Future<String>? running = _inFlight[font.id];
    if (running != null) {
      return running;
    }
    final Future<String> task = _load(font, family);
    _inFlight[font.id] = task;
    return task.whenComplete(() => _inFlight.remove(font.id));
  }

  Future<String> _load(OgLCustomFont font, String family) async {
    final Uint8List bytes = await bytesOf(font);
    // sublistView 尊重 offsetInBytes（ByteData.view(bytes.buffer) 不尊重）。
    final FontLoader loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
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
  Future<String> ensureNotoSerifSc() => ensureLoaded(OgLCustomFont(
        id: OgLBuiltinFonts.notoSerifSc,
        name: OgLI18n.instance.t('settings', 'uiFontNotoSerif'),
        source: OgLBuiltinFonts.notoSerifScUrl,
      ));

  /// OTF/TTF 魔数粗校验：拦下 HTML 错误页 / 空文件 / 截断文件。
  static bool _looksLikeFont(Uint8List bytes) {
    if (bytes.length < 4) {
      return false;
    }
    final int tag =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return tag == 0x00010000 || // TTF
        tag == 0x4F54544F || // OTTO
        tag == 0x74727565 || // true
        tag == 0x74746366 || // ttcf
        tag == 0x774F4646 || // wOFF
        tag == 0x774F4632; // wOF2
  }

  /// 从 URL 推断字体扩展名（缺省 .ttf；.otf/.ttf 之外如实取尾段）。
  static String _extOf(String source) {
    final String path = source.split('?').first;
    if (path.toLowerCase().endsWith('.otf')) {
      return '.otf';
    }
    return '.ttf';
  }

  /// 私有字体落盘目录（应用支持目录下 `fonts/`）。
  /// 供设置页写入私有字体（[ensureLoaded] 与此处共用同一目录规则）。
  Future<Directory> privateFontsDirectory() => _privateFontsDir();

  Future<Directory> _privateFontsDir() async {
    // 复用 app_dirs 已有的支持目录解析；这里只做「存在则用」的轻量探测，
    // 避免引入 base 层依赖（surface 不得直接 import base/disk）。
    final String home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final Directory dir =
        Directory('$home${Platform.pathSeparator}.ohgithublost'
            '${Platform.pathSeparator}fonts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
