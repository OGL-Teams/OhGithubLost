/// L3 展示级 · **令牌出设备前的不可关闭警告弹窗**（TOKEN-EXIT-01）。
///
/// ## 为什么需要它
/// 下载相关**不替用户决策**（QUALITY_STANDARD 第 12 / 40 条）：凡是"这次下载
/// 会把 GitHub 令牌（`authorization` 头）发给**非 GitHub 主机**"的场景，
/// 必须先经用户显式确认——确认在类型上表达（本 API 返回 `Future<bool>`），
/// 不靠调用方自觉。
///
/// ## 不可关闭的三重保证
/// | 关闭途径 | 处置 |
/// |---|---|
/// | 点遮罩关闭 | `barrierDismissible: false`（经 [ogLShowDialog] 传入） |
/// | 系统返回键 / 返回手势 | `PopScope(canPop: false)` 拦截 |
/// | 自动超时 / 静默放行 | 无计时器；只有两个按钮能结束弹窗 |
///
/// ## 视觉
/// 背景取 `colorScheme.errorContainer`（令牌外字面色禁令，见 ui_audit）；
/// 确认按钮用 `colorScheme.error` 底 + `onError` 前景，与"取消"形成
/// 明确的危险/安全对比。
///
/// ## 留痕
/// 弹窗结果（无论确认或取消）写入 `OgLAppLog`（surface 层诊断环，
/// 同步落盘）——**不静默**，事后可在「关于页」回溯这次令牌出设备决策。
///
/// ## 用法（门禁函数，四个下载调用点共用）
/// ```dart
/// final bool allowed = await ogLGuardTokenExitDownload(
///   context,
///   url: plan.urls.first,
///   headers: plan.headers,
///   targetSummary: fileName,
/// );
/// if (!allowed) { /* 如实提示已取消，不入队 */ return; }
/// await downloads.enqueue(...);
/// ```
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../util/og_l_space.dart';

/// 令牌允许直发的 GitHub 主机白名单（小写、不带端口）。
///
/// `*.github.com` 整域放行（含 api.github.com / gist.github.com 等）；
/// `githubusercontent.com` 只放行 GitHub 官方对象/原始内容三个子域——
/// 其它子域（含用户可控的泛解析）不在列，照走警告。
const List<String> kOgLTokenSafeHosts = <String>[
  'github.com',
  'raw.githubusercontent.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
];

/// 该主机是否属于 GitHub 官方下载域（令牌可直发，无需警告）。
bool ogLIsGitHubDownloadHost(String host) {
  final String h = host.toLowerCase();
  if (h.endsWith('.github.com') || h == 'github.com') {
    return true;
  }
  return kOgLTokenSafeHosts.contains(h);
}

/// 下载令牌出设备门禁：入队前最后一道闸。
///
/// - `headers` 不带 `authorization`（含空表 / 未登录）→ 直接放行；
/// - 最终 URL 的 host 属于 GitHub 官方域 → 放行（第 40 条：令牌只在
///   必要的跳步使用，发给 GitHub 自己不算"出设备"）;
/// - 其余情况（典型：用户自建加速通道）→ 弹**不可关闭**警告，
///   返回 `true` 仅当用户点了「仍要下载」。
///
/// **必须在能拿到 [BuildContext] 的最浅层调用**（enqueue 之前的同步点）；
/// 取消时不入队，由调用方在界面上如实提示"已取消"。
Future<bool> ogLGuardTokenExitDownload(
  BuildContext context, {
  required String url,
  required Map<String, String> headers,
  required String targetSummary,
}) async {
  final String? auth = headers['authorization'];
  final bool carriesToken = auth != null && auth.isNotEmpty;
  if (!carriesToken) {
    return true;
  }
  final Uri? uri = Uri.tryParse(url);
  final String host = (uri?.host ?? '').trim().toLowerCase();
  if (ogLIsGitHubDownloadHost(host)) {
    return true;
  }
  final bool proceed = await showOgLTokenExitWarning(
    context,
    host: host.isEmpty ? url : host,
    targetSummary: targetSummary,
  );
  // TOKEN-EXIT-01: 决策留痕（不静默）。OgLAppLog 是 surface 层诊断环，
  // 同步写磁盘日志，供「关于页」回溯。
  OgLAppLog.instance.add(
    '下载',
    OgLI18n.instance.t(
      'common',
      proceed ? 'tokenExitLogConfirmed' : 'tokenExitLogCancelled',
      args: <String, String>{'host': host.isEmpty ? url : host},
    ),
    severity: OgLNoticeSeverity.warning,
    logLevel: 'TOKEN-EXIT-01',
  );
  return proceed;
}

/// 弹出"令牌将离开设备"的**不可关闭**警告。返回 `true` = 用户确认继续下载。
Future<bool> showOgLTokenExitWarning(
  BuildContext context, {
  required String host,
  required String targetSummary,
}) async {
  final bool? proceed = await ogLShowDialog<bool>(
    context: context,
    // TOKEN-EXIT-01: 遮罩点击不关闭；返回键由下方 PopScope 拦截。
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      final OgLI18n i18n = OgLI18n.instance;
      final ThemeData theme = Theme.of(dialogContext);
      return PopScope<bool>(
        // TOKEN-EXIT-01: 系统返回键 / 返回手势同样不能绕过警告。
        canPop: false,
        child: AlertDialog(
          // 暗红警示底色：取主题语义令牌 errorContainer，不写字面色。
          backgroundColor: theme.colorScheme.errorContainer,
          title: Text(i18n.t('common', 'tokenExitTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(i18n.t('common', 'tokenExitBody')),
              const SizedBox(height: OgLSpace.md),
              // 目标主机加粗单列：让用户看清"到底是谁收到了令牌"。
              Text(
                i18n.t(
                  'common',
                  'tokenExitHost',
                  args: <String, String>{'host': host, 'target': targetSummary},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(i18n.t('common', 'tokenExitCancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(i18n.t('common', 'tokenExitConfirm')),
            ),
          ],
        ),
      );
    },
  );
  return proceed ?? false;
}
