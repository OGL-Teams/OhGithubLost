/// L3 展示级 · 外链打开（唯一入口）。
///
/// 详情页（README、议题、评论、PR、Gists…）都会遇到外链。
/// 若每页各写一遍，就会出现"有的页能开、有的页点了没反应"——
/// 而"点了没反应"正是最容易被当成"功能失效"的问题。
///
/// 这里只做一件事：**尽力打开，并如实返回结果**；
/// 失败时调用方把 URL 复制给用户（不是干瞪眼）。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import 'clipboard_x.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'common', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 用系统浏览器打开外链。
///
/// 返回 `true` = 已交给系统；`false` = 没打开（调用方必须**可见地**告诉用户）。
Future<bool> openExternalLink(Uri url, {String tag = '链接'}) async {
  OgLAppLog.instance.add(tag, '打开外部链接：$url');
  try {
    if (url.scheme.isEmpty) {
      OgLAppLog.instance.add(
        tag,
        '链接缺少协议，拒绝打开：$url',
        severity: OgLNoticeSeverity.warning,
      );
      return false;
    }
    final bool ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      OgLAppLog.instance.add(
        tag,
        '系统没有可用的浏览器：$url',
        severity: OgLNoticeSeverity.warning,
      );
    }
    return ok;
  } catch (error) {
    OgLAppLog.instance.add(
      tag,
      '打开链接失败：$error',
      severity: OgLNoticeSeverity.warning,
    );
    return false;
  }
}

/// 打开外链；失败时把 URL 复制到剪贴板并横幅提示。
Future<void> openLinkOrCopy(BuildContext context, String href,
    {String tag = '链接'}) async {
  final Uri? uri = Uri.tryParse(href);
  if (uri == null || uri.scheme.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('linkInvalid'))),
      );
    }
    return;
  }
  final bool ok = await openExternalLink(uri, tag: tag);
  if (ok) {
    return;
  }
  await ogLCopyText(href, tag: tag);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('linkOpenFailedCopy', {'url': href}))),
    );
  }
}
