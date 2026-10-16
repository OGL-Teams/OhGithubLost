/// L3 展示级 · 法律文本（**多语言对照查看**）。
///
/// ## 为什么单独开一页
/// 引导页那份是「重点 + 折叠全文」，面向**首次阅读**；这一页面向**查阅**：
/// 可以把全部可用语言的法律文本逐个调出来对照。
///
/// ## 为什么不切界面语言
/// `OgLI18n.load()` 会**替换当前语言**（影响整个界面）。这里要的是"只看某个
/// 语言的正文、界面语言不动"，所以直接读 `assets/i18n/<code>/…` 资源，
/// 不去碰 i18n 的全局状态。
///
/// ## 效力声明
/// 以中文文本为准；其他语言的译本仅供解释。这一条在页面顶部常驻显示。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/og_l_space.dart';

/// 取 `settings` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'settings', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 法律文本查看页（可切换全部可用语言）。
class LegalTextPage extends StatefulWidget {
  /// 创建页面。
  const LegalTextPage({required this.surface, super.key});

  /// 表面桥（保留，便于后续按订阅状态决定是否高亮某段）。
  final SurfaceBridge surface;

  @override
  State<LegalTextPage> createState() => _LegalTextPageState();
}

class _LegalTextPageState extends State<LegalTextPage> {
  /// 当前查看的语言（默认 `zh` —— 效力以它为准）。
  String _locale = 'zh';
  String? _body;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load(_locale));
  }

  /// 直接读资源里的正文，**不改动界面语言**。
  Future<void> _load(String code) async {
    setState(() {
      _loading = true;
      _locale = code;
    });
    String body = '';
    try {
      final String raw =
          await rootBundle.loadString('assets/i18n/$code/onboarding.json');
      final Object? json = jsonDecode(raw);
      if (json is Map) {
        body = '${json['onboardingLicenseBody'] ?? ''}';
      }
    } catch (error) {
      body = '';
      OgLAppLog.instance.add(
        '法律文本',
        '读取 $code 失败：$error',
        severity: OgLNoticeSeverity.warning,
      );
    }
    if (!mounted || code != _locale) {
      // 过期响应：期间用户已切到别的语言，写回会让正文与所选语言不符。
      return;
    }
    setState(() {
      _body = body;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('legalText'))),
      body: Column(
        children: <Widget>[
          // ── 定性说明：**唯一具有法律效力的是 Apache-2.0**，本文只是说明 ──
          //    放在最顶：读者应当先知道本文不产生法律效力，再读内容。
          Container(
            width: double.infinity,
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline,
                    size: 18, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: OgLSpace.sm),
                Expanded(
                  child: Text(
                    OgLI18n.instance.t('onboarding', 'legalStatementOnly'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── 效力声明（语言与官方副本）──
          Container(
            width: double.infinity,
            color: theme.colorScheme.secondaryContainer,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.translate,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: OgLSpace.sm),
                    Expanded(
                      child: Text(
                        OgLI18n.instance
                            .t('onboarding', 'licenseAuthoritative'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.verified_outlined,
                        size: 18,
                        color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: OgLSpace.sm),
                    Expanded(
                      child: Text(
                        OgLI18n.instance.t('onboarding', 'licenseOfficialCopy'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── 语言选择：列出**全部可用语言** ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: <Widget>[
                Text(_t('legalLanguages'), style: theme.textTheme.labelLarge),
                const SizedBox(width: OgLSpace.md),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _locale,
                    onChanged: (String? value) {
                      if (value != null && value != _locale) {
                        unawaited(_load(value));
                      }
                    },
                    items: <DropdownMenuItem<String>>[
                      for (final OgLLocale item in OgLI18n.locales)
                        DropdownMenuItem<String>(
                          value: item.code,
                          child: Text('${item.label}（${item.code}）'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_body == null || _body!.isEmpty)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_t('legalTextEmpty'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _body!,
                          style:
                              theme.textTheme.bodySmall?.copyWith(height: 1.6),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
