/// L2 中枢级 · 草稿视图（供草稿箱与编辑器使用）。
///
/// 只暴露可展示的字段；底层的缓存键编码不外泄。
library;

import 'package:flutter/foundation.dart';

/// 一条草稿的可读信息。
@immutable
class GhDraft {
  /// 创建草稿信息。
  const GhDraft({
    required this.repo,
    required this.branch,
    required this.path,
    required this.content,
    required this.revision,
    required this.updatedAt,
  });

  /// 仓库全名（`owner/name`）。
  final String repo;

  /// 分支（可能为空表示默认分支）。
  final String branch;

  /// 文件路径。
  final String path;

  /// 草稿内容。
  final String content;

  /// 修订号。
  final int revision;

  /// 最后更新时间。
  final DateTime updatedAt;

  /// 展示用文件名。
  String get fileName => path.split('/').last;
}
