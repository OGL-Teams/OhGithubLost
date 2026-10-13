/// L2 中枢级 · 下载失败的**结构化**描述（分类 + 说明 + 诊断码）。
///
/// ## 为什么不再是裸 `String`
/// `IxDownloadTask.error` 曾经只放一个字符串：页面只能整段回显，既看不出
/// 「是网络断了、磁盘满了，还是校验没过」，也没法按分类给出**不同的下一步**
/// （重试 / 换通道 / 重新下载 / 去登录）。分类与诊断码在这里收口，
/// [IxDownloadError.message] 仍是**面向用户的那一句话**。
///
/// ## 边界
/// 本文件是纯数据描述（不含任何下载实现）：Web 与原生共用同一套分类。
/// 判不出分类时用 [IxDownloadErrorKind.unknown]——**不编造**。
library;

import 'package:flutter/foundation.dart';

/// 下载错误分类（结构化，取代裸 String）。
enum IxDownloadErrorKind {
  /// 网络失败（连接 / 超时 / DNS）。
  network,

  /// 磁盘写入失败。
  disk,

  /// 校验不匹配。
  integrity,

  /// 用户取消。
  canceled,

  /// 平台不支持该操作。
  unsupported,

  /// 需要认证（Web 上无法带 Authorization）。
  needsAuth,

  /// 其它：描述文本里**判不出**分类时的如实归类。
  unknown,
}

/// 一次下载失败的结构化描述（不可变）。
@immutable
class IxDownloadError {
  /// 创建。
  ///
  /// [kind] 分类；[message] 面向用户的说明；[code] 诊断码（无对应事件码时留空）。
  const IxDownloadError(this.kind, this.message, {this.code});

  /// 分类（决定界面给的下一步动作）。
  final IxDownloadErrorKind kind;

  /// 面向用户的说明文本（界面显示的就是这一句）。
  final String message;

  /// 诊断码，如 `OGL-DL-202`；没有对应事件码时为 `null`。
  final String? code;

  @override
  String toString() => code == null ? message : '$message (code: $code)';
}
