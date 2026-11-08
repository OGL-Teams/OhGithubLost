/// L3 展示级 · 字体文件来源辅助（设置页「私有字体」的取件入口）。
///
/// ## 为什么不引 file_picker
/// 依赖裁剪纪律：`file_picker` 曾被移除（见 pubspec 注释）。这里的取件
/// 以**手输路径**（桌面端直接可用）为主，Android 用户可经由系统文件
/// 管理器把字体放进「所有文件访问」可见的 ogl 目录后填路径。
/// 链接来源走 [OgLFontLoader.bytesOf] 的下载通道，不在此处。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../i18n/og_l_i18n.dart';

/// 字体文件取件辅助（设置页私有字体）。
abstract final class OgLFontPickers {
  /// 让用户输入本机字体文件路径（.ttf / .otf），读出字节。
  ///
  /// 返回 `null` = 用户取消；文件不存在或非字体扩展名抛异常（调用方提示）。
  static Future<Uint8List?> pickFontBytes(State state) async {
    final BuildContext context = state.context;
    if (!context.mounted) {
      return null;
    }
    final TextEditingController controller = TextEditingController();
    final String? ok = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(OgLI18n.instance.t('settings', 'uiFontPickTitle')),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/storage/emulated/0/ogl/fonts/MyFont.ttf',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(OgLI18n.instance.t('common', 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('ok'),
            child: Text(OgLI18n.instance.t('common', 'ok')),
          ),
        ],
      ),
    );
    if (ok != 'ok') {
      return null;
    }
    final String path = controller.text.trim();
    if (path.isEmpty) {
      return null;
    }
    final String lower = path.toLowerCase();
    if (!lower.endsWith('.ttf') && !lower.endsWith('.otf')) {
      throw StateError('仅支持 .ttf / .otf 字体文件');
    }
    final File file = File(path);
    if (!file.existsSync()) {
      throw StateError('文件不存在：$path');
    }
    return file.readAsBytes();
  }
}
