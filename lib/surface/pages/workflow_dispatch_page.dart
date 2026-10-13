/// L3 展示级 · 手动触发工作流（`workflow_dispatch`）。
///
/// R10：选中工作流后，**读取它的 YAML 声明**（`on.workflow_dispatch.inputs`），
/// 把必选参数 / 默认值 / 可选项**渲染成表单**，而不是让用户手写 `key=value`。
/// 仍保留“高级：直接输入”的入口，兼容无法解析（或私有语法）的情况。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';

/// 取 `workflow_dispatch_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'workflow_dispatch_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 一个 `workflow_dispatch` 参数声明。
class _WfInput {
  _WfInput({
    required this.name,
    this.description,
    this.required = false,
    this.defaultValue,
    this.type = 'string',
    this.options = const <String>[],
  });

  final String name;
  final String? description;
  final bool required;
  final String? defaultValue;
  final String type;
  final List<String> options;
}

/// 手动触发页。
class WorkflowDispatchPage extends StatefulWidget {
  /// 创建页面。
  const WorkflowDispatchPage({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 默认分支（作为默认 ref）。
  final String defaultBranch;

  @override
  State<WorkflowDispatchPage> createState() => _WorkflowDispatchPageState();
}

class _WorkflowDispatchPageState extends State<WorkflowDispatchPage> {
  AsyncController<List<Map<String, dynamic>>>? _workflows;
  final TextEditingController _ref = TextEditingController();
  final TextEditingController _inputs = TextEditingController();
  String? _selected;
  String? _selectedPath;
  bool _busy = false;

  /// 解析出的参数表单状态。
  List<_WfInput> _form = const <_WfInput>[];
  final Map<String, TextEditingController> _formText =
      <String, TextEditingController>{};
  final Map<String, String> _formChoice = <String, String>{};
  final Map<String, bool> _formBool = <String, bool>{};
  bool _loadingForm = false;
  String? _formError;

  /// 表单请求代次：快速切换工作流时，**过期响应一律丢弃**，
  /// 避免"表单参数与所选工作流不符"。
  int _formRequestId = 0;

  @override
  void initState() {
    super.initState();
    _ref.text = widget.defaultBranch;
    _workflowsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _workflows?.dispose();
    _ref.dispose();
    _inputs.dispose();
    for (final TextEditingController c in _formText.values) {
      c.dispose();
    }
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _workflowsC() {
    final existing = _workflows;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: _t('title'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.workflows(widget.fullName),
    );
    _workflows = controller;
    return controller;
  }

  /// 解析 `on.workflow_dispatch.inputs`（YAML 1.2：`on` 作为普通键）。
  ///
  /// 兼容 `on:` 被解析成布尔键 `true` 的情况（部分 YAML 实现）。
  static List<_WfInput> _parseWorkflowInputs(String text) {
    final Object? doc = loadYaml(text);
    if (doc is! Map) {
      return const <_WfInput>[];
    }
    Object? on = doc['on'];
    on ??= doc[true];
    if (on is! Map) {
      // `on: workflow_dispatch`（无参数）或无法识别。
      return const <_WfInput>[];
    }
    Object? wd = on['workflow_dispatch'];
    wd ??= on[true];
    if (wd is! Map) {
      return const <_WfInput>[];
    }
    final Object? inputs = wd['inputs'];
    if (inputs is! Map) {
      return const <_WfInput>[];
    }
    final List<_WfInput> result = <_WfInput>[];
    for (final MapEntry<Object?, Object?> entry in inputs.entries) {
      final String name = '${entry.key}';
      final Object? cfg = entry.value;
      if (cfg is Map) {
        final Object? options = cfg['options'];
        result.add(_WfInput(
          name: name,
          description: cfg['description']?.toString(),
          required: cfg['required'] == true,
          defaultValue: cfg['default']?.toString(),
          type: cfg['type']?.toString() ?? 'string',
          options: options is List
              ? options.map((Object? o) => '$o').toList()
              : const <String>[],
        ));
      } else {
        result.add(_WfInput(name: name));
      }
    }
    return result;
  }

  Future<void> _loadForm(String path) async {
    final int requestId = ++_formRequestId;
    setState(() {
      _loadingForm = true;
      _formError = null;
      _form = const <_WfInput>[];
      for (final TextEditingController c in _formText.values) {
        c.dispose();
      }
      _formText.clear();
      _formChoice.clear();
      _formBool.clear();
    });
    try {
      final String? text = await widget.surface.domain.api.rawFileText(
        widget.fullName,
        path,
        branch: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      );
      if (!mounted || requestId != _formRequestId) {
        // 过期响应：期间用户已切换目标，这份表单不再对应当前所选工作流。
        return;
      }
      if (text == null) {
        setState(() {
          _loadingForm = false;
          _formError = _t('readFileFailed', {'path': path});
        });
        return;
      }
      final List<_WfInput> parsed = _parseWorkflowInputs(text);
      setState(() {
        _loadingForm = false;
        _form = parsed;
        for (final _WfInput input in parsed) {
          if (input.type == 'choice') {
            _formChoice[input.name] = input.defaultValue ??
                (input.options.isEmpty ? '' : input.options.first);
          } else if (input.type == 'boolean') {
            _formBool[input.name] = input.defaultValue == 'true';
          } else {
            _formText[input.name] =
                TextEditingController(text: input.defaultValue ?? '');
          }
        }
      });
    } catch (error) {
      if (!mounted || requestId != _formRequestId) {
        return;
      }
      setState(() {
        _loadingForm = false;
        _formError = _t('parseFailed', {'error': error});
      });
    }
  }

  /// 从下拉变更工作流时调用。
  void _selectWorkflow(Map<String, dynamic> wf) {
    setState(() {
      _selected = ghInt(wf, 'id').toString();
      _selectedPath = ghStr(wf, 'path');
    });
    final String? path = _selectedPath;
    if (path != null && path.isNotEmpty) {
      _loadForm(path);
    }
  }

  /// 表单 → inputs；缺必选即报错。
  Map<String, String> _collectFormInputs() {
    final Map<String, String> result = <String, String>{};
    final List<String> missing = <String>[];
    for (final _WfInput input in _form) {
      String value;
      if (input.type == 'choice') {
        value = _formChoice[input.name] ?? '';
      } else if (input.type == 'boolean') {
        value = (_formBool[input.name] ?? false) ? 'true' : 'false';
      } else {
        value = _formText[input.name]?.text.trim() ?? '';
      }
      if (value.isEmpty && input.required) {
        missing.add(input.name);
        continue;
      }
      if (value.isNotEmpty) {
        result[input.name] = value;
      }
    }
    if (missing.isNotEmpty) {
      throw FormatException(
          _t('missingRequired', {'names': missing.join('、')}));
    }
    return result;
  }

  /// 解析“高级：直接输入”文本框（JSON 或每行 key=value）。
  Map<String, String> _parseManualInputs() {
    final String raw = _inputs.text.trim();
    if (raw.isEmpty) {
      return const <String, String>{};
    }
    if (raw.startsWith('{')) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw FormatException(_t('inputsNotObject'));
      }
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          '${e.key}': '${e.value}',
      };
    }
    final Map<String, String> result = <String, String>{};
    for (final String line in raw.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final int eq = trimmed.indexOf('=');
      if (eq <= 0) {
        throw FormatException(_t('eachLineKeyValue'));
      }
      result[trimmed.substring(0, eq).trim()] =
          trimmed.substring(eq + 1).trim();
    }
    return result;
  }

  Future<void> _submit() async {
    final String workflowIdOrFile = _selected ?? '';
    if (workflowIdOrFile.isEmpty) {
      _toast(_t('selectWorkflow'));
      return;
    }
    final String ref = _ref.text.trim();
    if (ref.isEmpty) {
      _toast(_t('refRequired'));
      return;
    }
    Map<String, String> inputs;
    try {
      inputs = <String, String>{
        ..._collectFormInputs(),
        ..._parseManualInputs(),
      };
    } on FormatException catch (error) {
      _toast(error.message);
      return;
    }
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.dispatchWorkflow(
        widget.fullName,
        workflowIdOrFile: workflowIdOrFile,
        ref: ref,
        inputs: inputs,
      );
      OgLAppLog.instance.result('Actions', _t('triggered'), workflowIdOrFile);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        _t('triggerFailed', {'error': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _toast(_t('triggerFailedNoDispatch', {'error': error}));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 表单是否已输入内容（任一输入与初始值不同）。
  bool get _dirty {
    if (_ref.text != widget.defaultBranch || _inputs.text.trim().isNotEmpty) {
      return true;
    }
    for (final _WfInput input in _form) {
      final TextEditingController? controller = _formText[input.name];
      if (controller == null) {
        continue;
      }
      if (controller.text != (input.defaultValue ?? '')) {
        return true;
      }
    }
    return false;
  }

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
          title: Text(_t('manualTrigger')),
          actions: <Widget>[
            TextButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? _t('triggering') : _t('trigger')),
            ),
          ],
        ),
        body: AsyncView<List<Map<String, dynamic>>>(
          controller: _workflowsC(),
          emptyIcon: Icons.play_circle_outline,
          emptyText: _t('noWorkflows'),
          builder:
              (BuildContext context, List<Map<String, dynamic>> workflows) {
            if (_selected == null && workflows.isNotEmpty) {
              // 默认选中第一个工作流——不能在 build 中直接 setState，
              // 放到下一帧执行。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selected == null) {
                  _selectWorkflow(workflows.first);
                }
              });
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(_t('title'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: <Widget>[
                      for (final Map<String, dynamic> wf in workflows)
                        ListTile(
                          leading: Icon(
                            _selected == ghInt(wf, 'id').toString()
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(
                            ghStr(wf, 'name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${ghStr(wf, 'path')} · ${ghStr(wf, 'state')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: _busy ? null : () => _selectWorkflow(wf),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(_t('refLabel'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _ref,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'main',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child:
                          Text(_t('inputs'), style: theme.textTheme.titleSmall),
                    ),
                    if (_loadingForm)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._formSection(theme),
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title:
                      Text(_t('advanced'), style: theme.textTheme.titleSmall),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: <Widget>[
                    TextField(
                      controller: _inputs,
                      minLines: 3,
                      maxLines: 8,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: _t('jsonHint'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _t('dispatchHint') + _t('dispatchHint2'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 参数表单区：按类型渲染控件；无参数则给出说明。
  List<Widget> _formSection(ThemeData theme) {
    if (_formError != null) {
      return <Widget>[
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_formError!, style: theme.textTheme.bodySmall),
          ),
        ),
      ];
    }
    if (_form.isEmpty) {
      return <Widget>[
        Text(
          _t('noInputs'),
          style: theme.textTheme.bodySmall,
        ),
      ];
    }
    return <Widget>[
      for (final _WfInput input in _form)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _fieldFor(theme, input),
        ),
    ];
  }

  Widget _fieldFor(ThemeData theme, _WfInput input) {
    final String label = input.name +
        (input.required ? _t('requiredSuffix') : _t('optionalSuffix'));
    final String? helper = input.description;
    if (input.type == 'choice') {
      final String value = _formChoice[input.name] ?? '';
      return DropdownButtonFormField<String>(
        initialValue: input.options.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<String>>[
          for (final String option in input.options)
            DropdownMenuItem<String>(value: option, child: Text(option)),
        ],
        onChanged: (String? v) =>
            setState(() => _formChoice[input.name] = v ?? ''),
      );
    }
    if (input.type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: helper == null ? null : Text(helper),
        value: _formBool[input.name] ?? false,
        onChanged: (bool v) => setState(() => _formBool[input.name] = v),
      );
    }
    return TextField(
      controller: _formText[input.name],
      keyboardType: input.type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: input.type == 'number'
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
