/// AI 设置：协议与服务地址独立配置，只显示密钥是否已保存。
library;

import 'package:flutter/material.dart';

import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';

String aiText(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('ai', key, args: args);

/// 公共错误入口只显示业务键或通用错误，不输出密钥/响应原文。
String aiError(Object error) =>
    aiText(error is AiException ? error.code : 'requestFailed');

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({required this.surface, super.key});
  final SurfaceBridge surface;
  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  String _kind = 'openai', _model = '', _preset = 'deepseek';
  bool _enabled = false, _busy = true, _savedKey = false;
  String? _error;
  List<String> _models = [];
  static const _presets = {
    'deepseek': ('openai', 'https://api.deepseek.com'),
    'openai': ('openai', 'https://api.openai.com/v1'),
    'anthropic': ('anthropic', 'https://api.anthropic.com/v1'),
    'gemini': ('gemini', 'https://generativelanguage.googleapis.com/v1beta'),
    'custom': ('openai', ''),
  };

  AiSettings get _config => AiSettings(
    enabled: _enabled,
    model: _model,
    kind: _kind,
    baseUrl: _url.text.trim().replaceAll(RegExp(r'/+$'), ''),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.surface.aiSettings();
      final hasKey = await widget.surface.aiHasKey(config: value);
      if (!mounted) {
        return;
      }
      setState(() {
        _enabled = value.enabled;
        _kind = value.kind;
        _model = value.model;
        _url.text = value.baseUrl;
        _savedKey = hasKey;
        _preset =
            _presets.entries
                .where((e) => e.value.$2 == value.baseUrl)
                .map((e) => e.key)
                .firstOrNull ??
            'custom';
        _busy = false;
      });
      if (hasKey) {
        await _detect();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = aiError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = _config;
      final models = await widget.surface.aiDetectModels(
        key: _key.text,
        config: config,
      );
      final saved = await widget.surface.aiHasKey(config: config);
      if (!mounted) {
        return;
      }
      setState(() {
        _models = models;
        _savedKey = saved;
        if (!_models.contains(_model)) {
          _model = _models.first;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = aiError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save({bool clear = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_enabled && !clear && _models.isEmpty) {
        throw const AiException('detectFirst');
      }
      await widget.surface.aiSaveSettings(
        _config,
        key: clear ? null : _key.text,
        clearKey: clear,
      );
      _key.clear();
      final saved = await widget.surface.aiHasKey(config: _config);
      if (mounted) {
        setState(() => _savedKey = saved);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(aiText('saved'))));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = aiError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(aiText('settings'))),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile(
              title: Text(aiText('enabled')),
              value: _enabled,
              onChanged: _busy ? null : (v) => setState(() => _enabled = v),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(aiText('privacy')),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _preset,
              decoration: InputDecoration(labelText: aiText('provider')),
              items: _presets.keys
                  .map(
                    (e) => DropdownMenuItem(value: e, child: Text(aiText(e))),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _preset = v!;
                      _kind = _presets[v]!.$1;
                      _url.text = _presets[v]!.$2;
                      _key.clear();
                      _models = [];
                      _model = '';
                      _savedKey = false;
                    }),
            ),
            const SizedBox(height: 16),
            if (_preset == 'custom') ...[
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: InputDecoration(labelText: aiText('protocol')),
                items: ['openai', 'anthropic', 'gemini']
                    .map(
                      (e) => DropdownMenuItem(value: e, child: Text(aiText(e))),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _kind = v!;
                        _models = [];
                        _model = '';
                        _savedKey = false;
                      }),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _url,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: aiText('baseUrl'),
                helperText: aiText('urlHint'),
              ),
              onChanged: (_) => setState(() {
                _models = [];
                _model = '';
                _savedKey = false;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: aiText('apiKey'),
                helperText: aiText(_savedKey ? 'keySaved' : 'keyHint'),
              ),
              onChanged: (_) => setState(() {
                _models = [];
                _model = '';
              }),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _detect,
              icon: const Icon(Icons.manage_search),
              label: Text(aiText('detectModels')),
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('$_kind:$_model'),
                initialValue: _model,
                isExpanded: true,
                decoration: InputDecoration(labelText: aiText('model')),
                items: _models
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _model = v!),
              ),
              const SizedBox(height: 8),
              Text(aiText('modelHint')),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : () => _save(),
              icon: const Icon(Icons.save_outlined),
              label: Text(aiText('save')),
            ),
            if (_savedKey)
              TextButton(
                onPressed: _busy ? null : () => _save(clear: true),
                child: Text(aiText('removeKey')),
              ),
          ],
        ),
      ),
    ),
  );
}
