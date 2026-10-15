/// L3 · AI 设置页：服务商 / 协议 / 模型 / 端点 / 密钥。
///
/// 密钥只经 [AiService] 写入 `DiskVault`，本页不落任何日志；端点必须是
/// 纯 HTTPS（协议层与传输层都会再校验一道）。
library;

import 'package:flutter/material.dart';

import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';

/// 取 `ai` 分片文案。
String _t(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('ai', key, args: args);

/// 内置服务商预设（无密钥、无自定义端点时的快速选择）。
class _AiPreset {
  const _AiPreset(this.label, this.kind, this.baseUrl,
      {this.defaultModel = ''});

  final String label;
  final AiProviderKind kind;
  final String baseUrl;
  final String defaultModel;
}

const List<_AiPreset> _kPresets = <_AiPreset>[
  _AiPreset('DeepSeek', AiProviderKind.openai, 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat'),
  _AiPreset('OpenAI', AiProviderKind.openai, 'https://api.openai.com/v1'),
  _AiPreset('Anthropic', AiProviderKind.anthropic, 'https://api.anthropic.com'),
  _AiPreset('Gemini', AiProviderKind.gemini,
      'https://generativelanguage.googleapis.com/v1beta'),
];

/// AI 设置页。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({required this.surface, super.key});

  final SurfaceBridge surface;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _key = TextEditingController();

  bool _enabled = false;
  AiProviderKind _kind = AiProviderKind.openai;
  String _model = '';
  bool _busy = true;
  bool _saving = false;
  bool _hasKey = false;
  List<String> _models = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final AiService ai = widget.surface.domain.ai;
    final AiSettings s = await ai.settings();
    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = s.enabled;
      _kind = s.kind;
      _model = s.model;
      _url.text = s.baseUrl;
      _busy = false;
    });
    final bool hasKey = await ai.hasKey();
    if (mounted) {
      setState(() => _hasKey = hasKey);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  String get _baseUrl => _url.text.trim().replaceAll(RegExp(r'/+$'), '');

  void _applyPreset(_AiPreset p) {
    setState(() {
      _kind = p.kind;
      _url.text = p.baseUrl;
      if (p.defaultModel.isNotEmpty) {
        _model = p.defaultModel;
      }
      _models = <String>[];
    });
  }

  Future<void> _detectModels() async {
    setState(() => _saving = true);
    try {
      final List<String> models = await widget.surface.domain.ai.detectModels(
        key: _key.text.trim().isEmpty ? null : _key.text.trim(),
        config: AiSettings(
          enabled: true,
          kind: _kind,
          model: _model,
          baseUrl: _baseUrl,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _models = models;
        if (!models.contains(_model) && models.isNotEmpty) {
          _model = models.first;
        }
      });
    } on AiException catch (e) {
      if (mounted) {
        // 优先展示可读详情（如「端点必须是 HTTPS」）：code 只是类别。
        _toast('${_t('error')}：${e.detail.isEmpty ? e.code : e.detail}');
      }
    } on Object catch (e) {
      // 解析层（jsonDecode / parseModelList）遇 200+非 JSON 响应会抛
      // FormatException / TypeError —— 不属于 AiException，必须兜住，
      // 否则是「未捕获异步错误」（onPressed 未 await）。
      if (mounted) {
        _toast('${_t('error')}：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _save() async {
    // 保存前先本地校验：让用户看到**具体哪一项**不合法，而不是保存后
    // 才从传输层收到一句笼统的失败。
    final String? invalid = _endpointError(_url.text);
    if (invalid != null) {
      _toast('${_t('error')}：$invalid');
      return;
    }
    setState(() => _saving = true);
    final AiService ai = widget.surface.domain.ai;
    try {
      await ai.saveSettings(AiSettings(
        enabled: _enabled,
        kind: _kind,
        model: _model,
        baseUrl: _baseUrl,
      ));
      final String key = _key.text.trim();
      if (key.isNotEmpty) {
        await ai.writeKey(key);
        _key.clear();
        _hasKey = true;
      }
      if (mounted) {
        setState(() => _hasKey = true);
        _toast(_t('saved'));
      }
    } on AiException catch (e) {
      if (mounted) {
        _toast('${_t('error')}：${e.detail.isEmpty ? e.code : e.detail}');
      }
    } on Object catch (e) {
      // writeKey → SecureDiskVault → flutter_secure_storage 可能抛
      // PlatformException（Android Keystore 失败等）——不属于 AiException。
      if (mounted) {
        _toast('${_t('error')}：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _removeKey() async {
    try {
      await widget.surface.domain.ai.clearKey();
      if (mounted) {
        setState(() => _hasKey = false);
        _toast(_t('saved'));
      }
    } on Object catch (e) {
      // clearKey → vault 删除可能抛 PlatformException（旧实现无任何 catch，
      // 表现为「点了没反应」）。
      if (mounted) {
        _toast('${_t('error')}：$e');
      }
    }
  }

  /// 端点即时校验：**返回空串表示可用**，否则返回给用户的可读原因。
  ///
  /// 与传输层（`ai_http_client_io._validateEndpoint`）保持**同一套判据**，
  /// 但在 UI 层提前一步给出反馈——用户改一个字符就能看到问题，
  /// 而不是点保存才被抛一脸异常（旧实现的实际表现）。
  String? _endpointError(String raw) {
    final String url = raw.trim();
    if (url.isEmpty) {
      return _t('urlRequired');
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return _t('urlInvalid');
    }
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return _t('urlSchemeInvalid');
    }
    if (uri.userInfo.isNotEmpty) {
      return _t('urlNoUserInfo');
    }
    if (uri.hasQuery || uri.hasFragment) {
      return _t('urlNoQuery');
    }
    return null;
  }

  /// 是否明文端点（`http://` 且非本机）——用于给出**知情提示**（不阻止）。
  bool get _isPlaintext =>
      _endpointError(_url.text) == null &&
      _baseUrl.startsWith('http://') &&
      !_isLoopback(_baseUrl);

  /// 本机/回环地址：明文传输未出设备，无需告警。
  static bool _isLoopback(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String host = uri?.host.toLowerCase() ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
  }

  void _toast(String msg) {
    OgLNotifier.of(context).info(msg);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('settings'))),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(all),
              children: <Widget>[
                SwitchListTile(
                  title: Text(_t('enabled')),
                  value: _enabled,
                  onChanged: (bool v) => setState(() => _enabled = v),
                ),
                const Divider(),
                Text(_t('provider'), style: theme.textTheme.titleSmall),
                const SizedBox(height: OgLSpace.sm),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final _AiPreset p in _kPresets)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: _baseUrl == p.baseUrl,
                        onSelected: (bool _) => _applyPreset(p),
                      ),
                  ],
                ),
                const SizedBox(height: OgLSpace.lg),
                DropdownButtonFormField<AiProviderKind>(
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: _t('protocol')),
                  items: <DropdownMenuItem<AiProviderKind>>[
                    for (final AiProviderKind k in AiProviderKind.values)
                      DropdownMenuItem<AiProviderKind>(
                          value: k, child: Text(k.name)),
                  ],
                  onChanged: (AiProviderKind? v) {
                    if (v != null) {
                      setState(() => _kind = v);
                    }
                  },
                ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  // 输入时即时反馈：改一个字符就能看到问题，不用等保存。
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _t('baseUrl'),
                    hintText: _t('urlHint'),
                    errorText: _endpointError(_url.text),
                    errorMaxLines: 2,
                  ),
                ),
                // 明文端点：**知情提示**（不阻止使用，但说清风险）。
                if (_isPlaintext)
                  Padding(
                    padding: const EdgeInsets.only(only),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: OgLSpace.sm),
                        Expanded(
                          child: Text(
                            _t('plaintextHint'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: OgLSpace.md),
                TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _hasKey ? _t('keySaved') : _t('apiKey'),
                    hintText: _t('keyHint'),
                  ),
                ),
                const SizedBox(height: OgLSpace.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _model.isEmpty ? null : _model,
                        decoration: InputDecoration(labelText: _t('model')),
                        items: <DropdownMenuItem<String>>[
                          if (_model.isNotEmpty)
                            DropdownMenuItem<String>(
                                value: _model, child: Text(_model)),
                          for (final String m in _models)
                            DropdownMenuItem<String>(value: m, child: Text(m)),
                        ],
                        onChanged: (String? v) {
                          if (v != null) {
                            setState(() => _model = v);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: OgLSpace.sm),
                    TextButton.icon(
                      onPressed: _saving ? null : _detectModels,
                      icon: const Icon(Icons.refresh),
                      label: Text(_t('detectModels')),
                    ),
                  ],
                ),
                const SizedBox(height: OgLSpace.md),
                if (_hasKey)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _removeKey,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(_t('removeKey')),
                    ),
                  ),
                const SizedBox(height: OgLSpace.lg),
                Text(_t('privacy'), style: theme.textTheme.bodySmall),
                const SizedBox(height: OgLSpace.lg),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_t('save')),
                ),
              ],
            ),
    );
  }
}
