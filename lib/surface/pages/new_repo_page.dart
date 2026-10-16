/// L3 展示级 · 新建仓库（表单）。
///
/// - 只保留必要字段：名称 / 描述 / 是否私有；
/// - 提交失败**保留输入**并给出可读错误（不是"点了没反应"）；
/// - 成功后把新仓库对象带回上一页（pop 值）。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/og_l_space.dart';
import '../widgets/scroll_aware_action.dart';

/// 取 `new_repo_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'new_repo_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 新建仓库页。
class NewRepoPage extends StatefulWidget {
  /// 创建页面。
  const NewRepoPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<NewRepoPage> createState() => _NewRepoPageState();
}

class _NewRepoPageState extends State<NewRepoPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// 表单一滚动位置：提交按钮（页面主操作）靠它做"下滑收边 / 上滑弹回"。
  final ScrollController _scroll = ScrollController();
  bool _private = false;
  bool _busy = false;
  String? _error;

  /// 初始值（用于「返回时是否确认」的脏检查）。
  late final String _initialName = _name.text;
  late final String _initialDescription = _description.text;

  /// 表单是否已输入内容。
  bool get _dirty =>
      _name.text != _initialName || _description.text != _initialDescription;

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
    _name.addListener(_onFieldChanged);
    _description.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onFieldChanged);
    _description.removeListener(_onFieldChanged);
    _name.dispose();
    _description.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = _t('nameRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GhRepo repo = await widget.surface.domain.api.createRepo(
        name: name,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        private: _private,
      );
      OgLAppLog.instance.result(_t('title'), _t('created'), repo.fullName);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(repo);
    } catch (error) {
      OgLAppLog.instance.add(
        _t('title'),
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
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _t('nameLabel'),
                    hintText: 'my-project',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _t('description'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                SwitchListTile(
                  title: Text(_t('private')),
                  subtitle: Text(_t('privateDesc')),
                  value: _private,
                  onChanged: _busy
                      ? null
                      : (bool value) => setState(() => _private = value),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: OgLSpace.md),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
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
                // 「创建」按钮跟着滚动"让路"：下滑时向屏外收起（只露约 1/4，点击即弹回），
                // 上滑自动完全弹回。
                //
                // 该按钮本身就在内容**末尾**（滚到底才出现），若再叠加"近底部半屏收起"，
                // 等于把页面主操作藏起来 —— 按用户「收起按照那个页面」的要求，
                // 本页关闭该规则（bottomReserve: 0），只保留方向规则。
                ScrollAwareAction(
                  controller: _scroll,
                  edge: AxisDirection.down,
                  bottomReserve: 0,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? _t('creating') : _t('create')),
                  ),
                ),
              ],
            )),
      ),
    );
  }
}
