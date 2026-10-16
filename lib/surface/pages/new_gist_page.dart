/// L3 展示级 · 新建 Gist（单文件）。
///
/// 说明：GitHub 支持多文件 Gist，但移动端输入体验有限；
/// 这里先做**单文件**新建，详情页可继续追加/编辑。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/og_l_space.dart';

/// 取 `new_gist_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'new_gist_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 新建 Gist 页。
class NewGistPage extends StatefulWidget {
  /// 创建页面。
  const NewGistPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<NewGistPage> createState() => _NewGistPageState();
}

class _NewGistPageState extends State<NewGistPage> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _filename =
      TextEditingController(text: 'snippet.txt');
  final TextEditingController _content = TextEditingController();
  bool _public = false;
  bool _busy = false;

  /// 初始值（用于「返回时是否确认」的脏检查）。
  late final String _initialDescription = _description.text;
  late final String _initialFilename = _filename.text;
  late final String _initialContent = _content.text;

  /// 表单是否已输入内容。
  bool get _dirty =>
      _description.text != _initialDescription ||
      _filename.text != _initialFilename ||
      _content.text != _initialContent;

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
    _description.addListener(_onFieldChanged);
    _filename.addListener(_onFieldChanged);
    _content.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _description.removeListener(_onFieldChanged);
    _filename.removeListener(_onFieldChanged);
    _content.removeListener(_onFieldChanged);
    _description.dispose();
    _filename.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String filename = _filename.text.trim();
    if (filename.isEmpty) {
      OgLNotifier.of(context).info(_t('fileNameRequired'));
      return;
    }
    if (_content.text.isEmpty) {
      OgLNotifier.of(context).info(_t('contentRequired'));
      return;
    }
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.createGist(
        files: <String, String>{filename: _content.text},
        description: _description.text,
        public: _public,
      );
      OgLAppLog.instance.result('Gist', _t('created'), filename);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Gist',
        _t('createFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        OgLNotifier.of(context).warning(
          _t('createFailed', {'error': error}),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
        appBar: AppBar(
          title: Text(_t('title')),
          actions: <Widget>[
            TextButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? _t('creating') : _t('create')),
            ),
          ],
        ),
        body: OgLReveal(
            delay: Duration.zero,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _description,
                  decoration: InputDecoration(
                    labelText: _t('description'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _filename,
                  decoration: InputDecoration(
                    labelText: _t('fileName'),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.insert_drive_file_outlined),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                Text(_t('content'), style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                TextField(
                  controller: _content,
                  minLines: 8,
                  maxLines: 20,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: _t('contentHint'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('isPublic')),
                  subtitle: Text(_t('isPublicDesc')),
                  value: _public,
                  onChanged: (bool on) => setState(() => _public = on),
                ),
                const SizedBox(height: OgLSpace.sm),
                Text(
                  _t('fileNameHint'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            )),
      ),
    );
  }
}
