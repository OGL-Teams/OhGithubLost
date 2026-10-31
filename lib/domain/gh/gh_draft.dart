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

/// 一条草稿的**编辑态**记录：正文 + 起草时的远端版本基线。
///
/// 为什么不直接返回底座的 `DraftRecord`：那是硬件层的存储模型，
/// 带缓存键等内部字段；交互层只需要"内容 + 基线"这一对可展示信息。
class GhDraftRecord {
  /// 创建记录。
  const GhDraftRecord({required this.content, this.baseSha});

  /// 草稿正文。
  final String content;

  /// 起草时基于的远端版本（乐观锁基线）；缺失表示没有可用基线。
  final String? baseSha;
}
