/// L3 展示级 · 发布详情（说明 / 资产下载 / 编辑 / 删除）。
///
/// 补齐原"发布页只能看说明 + 删除"的缺口：
/// - **资产**：逐个列出（文件名 / 大小 / 下载次数），可**下载**
///   （交给内建下载器；Release 附件走内置代理加速，落盘到 `<ogl>/download/release/`）；
/// - **编辑**：标签 / 标题 / 说明 / 草稿 / 预发布，`PATCH` 后即时刷新；
/// - **删除**：二次确认；
/// - 返回时把"是否发生变更"带回列表页，列表据此刷新。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import 'download_manager_page.dart';
import '../types.dart';
import '../util/accel.dart';
import '../util/download_proxy.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/readme_view.dart';

/// 取 `release_detail_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('release_detail_page', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 发布详情页。
class ReleaseDetailPage extends StatefulWidget {
  /// 创建页面。
  const ReleaseDetailPage({
    required this.surface,
    required this.fullName,
    required this.release,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 发布对象。
  final GhRelease release;

  @override
  State<ReleaseDetailPage> createState() => _ReleaseDetailPageState();
}

class _ReleaseDetailPageState extends State<ReleaseDetailPage> {
  late GhRelease _release = widget.release;
  bool _busy = false;

  Future<void> _edit() async {
    final TextEditingController tag =
        TextEditingController(text: _release.tagName);
    final TextEditingController name =
        TextEditingController(text: _release.name ?? '');
    final TextEditingController body =
        TextEditingController(text: _release.body ?? '');
    bool draft = _release.isDraft;
    bool prerelease = _release.isPrerelease;

    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setLocal) => AlertDialog(
          title:  Text(_t('editTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: tag,
                  decoration:  InputDecoration(
                    labelText: _t('tagLabel'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration:  InputDecoration(
                    labelText: _t('titleLabel'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: body,
                  minLines: 5,
                  maxLines: 12,
                  decoration:  InputDecoration(
                    labelText: _t('bodyLabel'),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:  Text(_t('draft')),
                  value: draft,
                  onChanged: (bool v) => setLocal(() => draft = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:  Text(_t('prerelease')),
                  value: prerelease,
                  onChanged: (bool v) => setLocal(() => prerelease = v),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child:  Text(_t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child:  Text(_t('save')),
            ),
          ],
        ),
      ),
    );
    final String tagText = tag.text.trim();
    final String nameText = name.text.trim();
    final String bodyText = body.text;
    tag.dispose();
    name.dispose();
    body.dispose();
    if (submit != true || !mounted) {
      return;
    }
    if (tagText.isEmpty) {
      _notifier.warning(_t('tagRequired'));
      return;
    }
    setState(() => _busy = true);
    try {
      final GhRelease updated = await widget.surface.domain.api.updateRelease(
        widget.fullName,
        _release.id,
        tagName: tagText,
        name: nameText,
        body: bodyText,
        draft: draft,
        prerelease: prerelease,
      );
      OgLAppLog.instance.result(_t('publish'), _t('updated'), updated.tagName);
      if (!mounted) {
        return;
      }
      setState(() {
        _release = updated;
      });
      _notifier.success(_t('saved'));
    } catch (error) {
      OgLAppLog.instance.add(
        _t('publish'),
        _t('updateFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _notifier.warning(_t('saveFailed', {'error': error}));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('deleteTitle')),
        content: Text(_t('deleteDesc', {'tag': _release.tagName})),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.deleteRelease(widget.fullName, _release.id);
      OgLAppLog.instance.result(_t('publish'), _t('deleted'), _release.tagName);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        _t('publish'),
        _t('deleteFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _notifier.warning(_t('deleteFailed', {'error': error}));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _download(GhAsset asset) async {
    final String? url = asset.downloadUrl;
    if (url == null || url.isEmpty) {
      _notifier.warning(_t('assetNoUrl'));
      return;
    }
    try {
      // ① 本地解 302：把需认证的第一跳换成**短期签名地址**（令牌不出设备）。
      //    之后即便把地址交给加速通道，也不需要携带任何令牌。
      final String direct = await widget.surface.resolveDownloadUrl(url);
      final bool presigned = direct != url;
      // ② 路由判定：签名族 + 超过阈值才加速；候选地址末尾永远带直连兜底。
      //
      //    ⚠️ **预解析失败时必须放弃加速**：此时手上仍是「需要 Authorization 的
      //    第一跳」，把它交给代理等于把令牌送给第三方。此时改为直连 + 认证头。
      // 适用范围：Release 附件。用户可单独关掉这一类。
      final List<String> prefixes = presigned
          ? widget.surface.settings.settings
              .accelPrefixesFor(OgLAccelScope.releaseAsset)
          : const <String>[];
      final List<String> urls = ogLAccelCandidates(
        url: direct,
        prefixes: prefixes,
        family: OgLAccelFamily.signed,
        bytes: asset.size,
      );
      // ③ 认证头只在「没拿到签名地址」时用，且此时**必定是直连**。
      final Map<String, String> headers = presigned
          ? const <String, String>{}
          : await widget.surface.downloadAuthHeaders();
      await widget.surface.domain.downloads.enqueue(
        url: urls.first,
        fallbackUrls: urls.skip(1).toList(),
        headers: headers,
        fileName: asset.name,
        category: IxDownloadCategory.release,
        // 大附件优先多连接：服务端不支持 Range 时中枢层自动回退。
        connections: widget.surface.settings.settings.downloadConnections,
        // GitHub 提供的 sha256；有则下载后校验，没有则如实标记「未校验」。
        expectedSha256: IxPresign.normalizeDigest(asset.raw['digest']),
      );
      if (mounted) {
        ogLShowDownloadQueued(context, widget.surface,
            _t('addedToDownload', {'name': asset.name}));
      }
    } catch (error) {
      if (mounted) {
        _notifier.warning(_t('addDownloadFailed', {'error': error}));
      }
    }
  }

  /// R5：附件详情（点击触发）。展示文件名 / 大小 / 类型 / 下载次数 / 直链，
  /// 并提供「下载」「复制链接」两个动作——**不再点一下就下载**。
  Future<void> _showAssetDetail(GhAsset asset) async {
    if (!mounted) {
      return;
    }
    await ogLShowSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                asset.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _assetKeyRow(_t('size'), ghSizeText(asset.size)),
              _assetKeyRow(_t('downloadCount'), '${asset.downloadCount}'),
              if (asset.contentType != null && asset.contentType!.isNotEmpty)
                _assetKeyRow(_t('type'), asset.contentType!),
              if (asset.downloadUrl != null && asset.downloadUrl!.isNotEmpty)
                _assetKeyRow(_t('directLink'), asset.downloadUrl!),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_download(asset));
                      },
                      icon: const Icon(Icons.download_outlined),
                      label:  Text(_t('download')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_copyAssetLink(asset));
                      },
                      icon: const Icon(Icons.link),
                      label:  Text(_t('copyLink')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// R5：长按附件的快捷操作（下载 / 复制链接 / 查看详情）。
  Future<void> _showAssetActions(GhAsset asset) async {
    if (!mounted) {
      return;
    }
    await ogLShowSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title:  Text(_t('download')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_download(asset));
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title:  Text(_t('copyDownloadLink')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_copyAssetLink(asset));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title:  Text(_t('viewFileDetail')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_showAssetDetail(asset));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 复制附件的下载直链（**不**经加速通道，避免把通道地址暴露给用户）。
  Future<void> _copyAssetLink(GhAsset asset) async {
    final String? url = asset.downloadUrl;
    if (url == null || url.isEmpty) {
      _notifier.warning(_t('assetNoUrl'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _notifier.success(_t('copiedDownloadLink'));
  }

  Widget _assetKeyRow(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 72, child: Text(key)),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  Future<void> _copyNotes() async {
    final String text = _release.body ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _notifier.success(_t('copiedNotes'));
    }
  }

  /// 统一提示入口（Phase 5 后半收敛）：**提示长什么样、什么语气只有一处定义**
  /// （见 [OgLNotifier]，即 `surface/app/notifier.dart`）—— 本页不再自造 SnackBar。
  ///
  /// 语气分工：[OgLNotifier.success] 操作已生效 / [OgLNotifier.info] 普通说明 /
  /// [OgLNotifier.warning] 失败与"被拦下"（权限不足、目标不存在、写回失败…）。
  OgLNotifier get _notifier => OgLNotifier(ScaffoldMessenger.of(context));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> marks = <String>[
      if (_release.isDraft) _t('draft'),
      if (_release.isPrerelease) _t('prerelease'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _release.tagName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: _t('edit'),
            onPressed: _busy ? null : _edit,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _t('copyNotes'),
            onPressed: _copyNotes,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: _t('delete'),
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
      body: OgLReveal(delay: Duration.zero, child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            _release.name == null || _release.name!.isEmpty
                ? _release.tagName
                : _release.name!,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            <String>[
              if (_release.publishedAt != null)
                _t('publishedAt', {
                  'date': _release.publishedAt!
                      .toIso8601String()
                      .split('T')
                      .first,
                }),
              if (marks.isNotEmpty) marks.join(' / '),
              _t('assetsCount', {'count': _release.assets.length}),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (_release.body != null && _release.body!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ReadmeView(
                  markdown: _release.body!,
                  onOpenLink: (Uri uri) {
                    unawaited(openExternalLink(uri, tag: _t('publish')));
                  },
                ),
              ),
            ),
          ],
          const Divider(height: 32),
          Text(_t('assets'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_release.assets.isEmpty)
             Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(_t('noAssets')),
            )
          else
            for (final GhAsset asset in _release.assets)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(
                    asset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _t('assetMeta', {'size': ghSizeText(asset.size), 'count': asset.downloadCount}),
                  ),
                  trailing: const Icon(Icons.info_outline),
                  // R5：点击**先看详情**（不再直接触发下载）；长按弹出快捷操作。
                  onTap: () => unawaited(_showAssetDetail(asset)),
                  onLongPress: () => unawaited(_showAssetActions(asset)),
                ),
              ),
          const SizedBox(height: 24),
        ],
      )),
    );
  }
}