/// L3 展示级 · 新建发布（表单）。
///
/// - 标签必填（如 `v1.0.0`）；名称 / 说明可选；可勾选"预发布"；
/// - 目标提交点使用仓库默认分支；
/// - 成功后把新发布对象带回上一页（pop 值）。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/og_l_space.dart';
import '../widgets/scroll_aware_action.dart';

/// 取 `new_release_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'new_release_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 新建发布页。
class NewReleasePage extends StatefulWidget {
  /// 创建页面。
  const NewReleasePage({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// 仓库默认分支（作为目标提交点）。
  final String defaultBranch;

  @override
  State<NewReleasePage> createState() => _NewReleasePageState();
}

class _NewReleasePageState extends State<NewReleasePage> {
  final TextEditingController _tag = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _body = TextEditingController();

  /// 表单滚动位置：发布按钮（页面主操作）靠它做"下滑收边 / 上滑弹回"。
  final ScrollController _scroll = ScrollController();
  bool _prerelease = false;
  bool _draft = false;
  bool _busy = false;
  String? _error;

  /// 初始值（用于「返回时是否确认」的脏检查）。
  late final String _initialTag = _tag.text;
  late final String _initialName = _name.text;
  late final String _initialBody = _body.text;

  /// 表单是否已输入内容。
  bool get _dirty =>
      _tag.text != _initialTag ||
      _name.text != _initialName ||
      _body.text != _initialBody;

  /// 返回前的「放弃确认」（复用 `code_editor_page` 分片的既有文案，语义一致）。
  Future<bool?> _confirmDiscard() => ogLConfirmDiscardChanges(context);

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
    _tag.addListener(_onFieldChanged);
    _name.addListener(_onFieldChanged);
    _body.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _tag.removeListener(_onFieldChanged);
    _name.removeListener(_onFieldChanged);
    _body.removeListener(_onFieldChanged);
    _tag.dispose();
    _name.dispose();
    _body.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String tag = _tag.text.trim();
    if (tag.isEmpty) {
      setState(() => _error = _t('tagRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GhRelease release = await widget.surface.domain.api.createRelease(
        widget.fullName,
        tagName: tag,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        prerelease: _prerelease,
        draft: _draft,
        targetCommitish:
            widget.defaultBranch.isEmpty ? null : widget.defaultBranch,
      );
      OgLAppLog.instance.result('发布', _t('created'), release.tagName);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(release);
    } catch (error) {
      OgLAppLog.instance.add(
        '发布',
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
              padding: const EdgeInsets.all(OgLSpace.lg),
              children: <Widget>[
                TextField(
                  controller: _tag,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _t('tagLabel'),
                    hintText: 'v1.0.0',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: _t('titleLabel'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _body,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: _t('bodyLabel'),
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                SwitchListTile(
                  title: Text(_t('draft')),
                  subtitle: Text(_t('draftDesc')),
                  value: _draft,
                  onChanged: _busy
                      ? null
                      : (bool value) => setState(() => _draft = value),
                ),
                SwitchListTile(
                  title: Text(_t('prerelease')),
                  subtitle: Text(_t('prereleaseDesc')),
                  value: _prerelease,
                  onChanged: _busy
                      ? null
                      : (bool value) => setState(() => _prerelease = value),
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
                // 「发布」按钮跟着滚动"让路"：下滑时向屏外收起（只露约 1/4，点击即弹回），
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
                    child: Text(_busy ? _t('publishing') : _t('publish')),
                  ),
                ),
              ],
            )),
      ),
    );
  }
}
