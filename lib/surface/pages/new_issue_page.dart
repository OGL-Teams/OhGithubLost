/// L3 展示级 · 新建议题（表单）。
///
/// - 标题必填；正文可选（Markdown）；
/// - 成功后 `pop(true)`，由上一页决定如何刷新。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/og_l_space.dart';

/// 取 `new_issue_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'new_issue_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 新建议题页。
class NewIssuePage extends StatefulWidget {
  /// 创建页面。
  const NewIssuePage({
    required this.surface,
    required this.fullName,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  @override
  State<NewIssuePage> createState() => _NewIssuePageState();
}

class _NewIssuePageState extends State<NewIssuePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _busy = false;
  String? _error;

  /// 初始值（用于「返回时是否确认」的脏检查）。
  late final String _initialTitle = _title.text;
  late final String _initialBody = _body.text;

  /// 表单是否已输入内容。
  bool get _dirty => _title.text != _initialTitle || _body.text != _initialBody;

  /// 返回前的「放弃确认」（复用 `code_editor_page` 分片的既有文案，语义一致）。
  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          final OgLI18n i18n = OgLI18n.instance;
          return AlertDialog(
            title: Text(i18n.t('code_editor_page', 'discardTitle')),
            content: Text(i18n.t('code_editor_page', 'discardDesc')),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(i18n.t('code_editor_page', 'continueEditing')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(i18n.t('code_editor_page', 'discardChanges')),
              ),
            ],
          );
        },
      );

  /// 任一字段变化 → 重建：`PopScope` 的 `canPop` 依赖文本内容，
  /// 否则输入后返回键仍按「未修改」直接放行（静默丢失输入）。
  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(_onFieldChanged);
    _body.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _title.removeListener(_onFieldChanged);
    _body.removeListener(_onFieldChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = _t('titleRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.surface.domain.api.createIssue(
        widget.fullName,
        title: title,
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
      );
      OgLAppLog.instance.result('议题', _t('created'), title);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      OgLAppLog.instance.add(
        '议题',
        _t('createFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _t('createFailed', {'error': error});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 返回时若表单已输入内容，先确认再离开 —— 不允许静默丢弃。
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final bool? leave = await _confirmDiscard();
        if (leave == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_t('title'))),
        body: OgLReveal(
            delay: Duration.zero,
            child: ListView(
              padding: const EdgeInsets.all(OgLSpace.lg),
              children: <Widget>[
                TextField(
                  controller: _title,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _t('titleLabel'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _body,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: _t('bodyLabel'),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: OgLSpace.md),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(OgLSpace.md),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: OgLSpace.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? _t('submitting') : _t('submit')),
                ),
              ],
            )),
      ),
    );
  }
}
