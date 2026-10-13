/// L3 展示级 · 把 GitHub 的响应字段翻成人话（唯一实现处）。
///
/// 议题 / PR / 提交 / Gists / 搜索拿到的是原始 `Map`：
/// 页面各写一份解析就会出现"同一个字段各页显示不一"的历史问题。
/// 这里只保留一组**纯函数**（无 Flutter 依赖，容易单测）。
library;

import '../i18n/og_l_i18n.dart';
import '../types.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'common', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 取字符串字段（缺省 / 非字符串 → 空串）。
String ghStr(Map<String, dynamic> node, String key) {
  final Object? value = node[key];
  return value is String ? value : '';
}

/// 取可空字符串字段。
String? ghStrOrNull(Map<String, dynamic> node, String key) {
  final Object? value = node[key];
  return value is String ? value : null;
}

/// 取整数字段（字符串数字也可解析；缺省 → 0）。
int ghInt(Map<String, dynamic> node, String key) {
  final Object? value = node[key];
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// 取 `user.login`（`user` 不是对象时返回空串）。
String ghLogin(Map<String, dynamic> node) {
  final Object? user = node['user'];
  if (user is Map<Object?, Object?>) {
    return ghStr(Map<String, dynamic>.from(user), 'login');
  }
  return '';
}

/// ISO 8601 时间截到 `YYYY-MM-DD`（空 / 非法返回空串）。
String ghDate(Map<String, dynamic> node, String key) {
  final String raw = ghStr(node, key);
  if (raw.isEmpty) {
    return '';
  }
  return raw.split('T').first;
}

/// 文件变更状态 → 中文（未知状态原样返回，空则给"变更"）。
String ghFileStatusText(String status) {
  switch (status) {
    case 'added':
      return _t('changeAdded');
    case 'removed':
      return _t('changeRemoved');
    case 'modified':
      return _t('changeModified');
    case 'renamed':
      return _t('changeRenamed');
    case 'copied':
      return _t('changeCopied');
    case 'changed':
      return _t('changeChanged');
    default:
      return status.isEmpty ? _t('changeChanged') : status;
  }
}

/// 短 sha（GitHub 网页端也是 7 位）。
String ghShortSha(String sha) => sha.length >= 7 ? sha.substring(0, 7) : sha;

/// 提交作者显示名（优先 GitHub 登录名，退回本地提交名，再退回"未知"）。
String ghCommitAuthor(GhCommit commit) =>
    commit.authorLogin ?? commit.authorName ?? _t('unknown');

/// 内容条目显示名（取 path 最后一段）。
String ghPathName(String path) {
  if (path.isEmpty) {
    return path;
  }
  final List<String> parts = path.split('/');
  return parts.last;
}

/// 文件大小 → 人话（B / KB / MB）。
String ghSizeText(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final double kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
