/// L3 展示级 · 剪贴板操作统一封装（**Web 上失败必须可见**）。
///
/// ## 为什么单独一个文件
/// 项目里有十多处 `Clipboard.setData(...)` 散落在页面里 —— 复制仓库链接、
/// 复制日志、复制附件 URL、复制路径…… Web 上每次调用都可能失败：
/// - 文档**未获焦**时，浏览器拒绝写入（焦点不在本页面）；
/// - 用户**未授权**（部分浏览器会弹条授权）；
/// - 浏览器策略（如 Safari 桌面）下只能由用户手势触发。
///
/// 旧代码全部是裸 `await Clipboard.setData(...)` + 立刻弹 "已复制"
/// 的 SnackBar —— 失败时 UI 上完全看不出，用户只能怀疑"是不是没复制成功"。
///
/// 本文件把失败**如实收口**：记日志 + 上报通知中心 + 让调用方感知
/// （`Future<bool>` 返回值），UI 层可以选择"复制失败，请手动复制"提示。
///
/// ## 用法
/// ```dart
/// final bool ok = await ogLCopyText(url, tag: '仓库');
/// if (!ok && context.mounted) {
///   ScaffoldMessenger.of(context).showSnackBar(
///     SnackBar(content: Text(_t('copyFailed'))),
///   );
/// }
/// ```
///
/// ## 为什么还包一层 `tag`
/// 上报日志时，原始异常不含"是谁调的"信息；这里把业务标签一并带上，
/// 通知中心的历史与磁盘日志都能直接定位到页面。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/error_surface.dart';

/// 复制文本到剪贴板（**Web 友好**：失败如实上报）。
///
/// 失败时不抛：返回 `false` + 写应用日志 + 上报通知中心（warning 级）。
/// 调用方拿到 `false` 应给出可读的失败提示，而不是继续弹"已复制"。
///
/// [tag] 用于日志与通知中心定位调用方（默认 `'OGL'`）。
Future<bool> ogLCopyText(String text, {String tag = 'OGL'}) async {
  try {
    if (kIsWeb && text.isEmpty) {
      // 空串在 Web 上仍能写入，但调用方多半是误用 —— 提前一拍。
      OgLAppLog.instance.add(
        tag,
        '复制到剪贴板：内容为空，已跳过',
        severity: OgLNoticeSeverity.warning,
      );
      return false;
    }
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (error, stack) {
    // ★ Web 上"未获焦"是**最常见**的失败原因 —— 不是真错，是浏览器策略。
    //   但仍然要可见（用户已经点了复制按钮，结果啥也没拿到）。
    OgLAppLog.instance.add(
      tag,
      '复制到剪贴板失败：$error',
      severity: OgLNoticeSeverity.warning,
    );
    OgLNoticeCenter.instance.report(
      title: '复制失败',
      detail: '$error\n$stack',
      severity: OgLNoticeSeverity.warning,
    );
    debugPrint('OGL 剪贴板：复制失败（$tag） $error');
    return false;
  }
}

/// 从剪贴板读取文本。
///
/// 与 [ogLCopyText] 对称 —— 同样的"失败可见"原则：
/// Web 上常因**未获焦**或**未授权**而读不到，返回 `null` 而不是抛异常。
///
/// [tag] 用于日志定位调用方。
Future<String?> ogLPasteText({String tag = 'OGL'}) async {
  try {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  } catch (error, stack) {
    OgLAppLog.instance.add(
      tag,
      '读取剪贴板失败：$error',
      severity: OgLNoticeSeverity.warning,
    );
    OgLNoticeCenter.instance.report(
      title: '读取剪贴板失败',
      detail: '$error\n$stack',
      severity: OgLNoticeSeverity.warning,
    );
    debugPrint('OGL 剪贴板：读取失败（$tag） $error');
    return null;
  }
}

/// 复制文本到剪贴板的"安全别名"（语义与 [ogLCopyText] 一致）。
///
/// 名字与项目早期约定一致（`safeClipboardSet`），新页面建议直接用
/// [ogLCopyText] —— `ogLCopyText` 命名更短，意图更清晰。本别名保留是为
/// 不强制改历史命名，且让旧调用点（`release_detail_page` / `gist_detail_page` /
/// `about_page`）的迁移是"重命名 import 即可"，不动调用方代码。
@Deprecated('Prefer ogLCopyText; this alias will be removed in the next cleanup pass.')
Future<bool> safeClipboardSet(String text, {String tag = 'OGL'}) =>
    ogLCopyText(text, tag: tag);