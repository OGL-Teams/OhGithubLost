/// L3 展示级 · 轻量国际化（i18n）。
///
/// ## 设计要点
/// 1. **JSON 分片、按页面组织**：`assets/i18n/<locale>/<page>.json`
///    （page = `common` / `shell` / `settings` / `repo` / `login`…）。
///    要改某个页面的文案，只动那一个文件即可，不用翻一个巨型翻译表。
/// 2. **英文基线 + 就近兜底**：缺失键依次回落「当前语言 → 英文 → 键名」，
///    绝不因为漏翻而显示空白。
/// 3. **中文语境保留英文术语**：`issue` / `release` / `action` / `pr` 等
///    在 `zh` 分片里**原样保留英文**（按产品要求）。
/// 4. 不引入 `intl`：本需求只需"查表替换"，无需复数/日期本地化
///    （日期由 GitHub 原样返回，系统组件文案由 `flutter_localizations` 负责）。
library;

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一个可选语言。
@immutable
class OgLLocale {
  /// 创建语言项。
  const OgLLocale(this.code, this.label);

  /// 语言代码（同时是目录名）。
  final String code;

  /// 原生展示名（下拉框里显示）。
  final String label;
}

/// 系统语言 → 受支持的界面语言代码（**首次启动**用；不认识就回落 `zh`）。
///
/// - `zh` 会按区域/字形细分：繁体（Hant / TW / HK / MO）→ `zh_TW`，其余 → `zh`；
/// - 其它语言只取主语言码（`en_US` → `en`），不在清单内一律回落 `zh`。
String ogLDetectDeviceLocale() {
  final Locale device = PlatformDispatcher.instance.locale;
  final String language = device.languageCode;
  if (language == 'zh') {
    final String script = device.scriptCode ?? '';
    final String region = device.countryCode ?? '';
    final bool traditional =
        script == 'Hant' || region == 'TW' || region == 'HK' || region == 'MO';
    return traditional ? 'zh_TW' : 'zh';
  }
  for (final OgLLocale item in OgLI18n.locales) {
    if (item.code == language) {
      return language;
    }
  }
  return 'zh';
}

/// i18n 内核（全局单例；仅展示层使用）。
class OgLI18n extends ChangeNotifier {
  OgLI18n._();

  /// 全局实例。
  static final OgLI18n instance = OgLI18n._();

  /// 基线语言（任何缺失键的最终兜底）。
  static const String baseLocale = 'en';

  /// 全部可选语言（v6.4.0 起收敛为 6 种；此前为 15 种）。
  ///
  /// ## 为什么砍掉 9 种
  /// 15 种里有 12 种的法律类正文（`onboardingLicenseBody`、`accelThirdPartyBody`
  /// 等）实际是**英文占位**：语言目录存在、键存在、值与英文相同。用户在自己的
  /// 语言里读到的是自己看不懂的法律说明，而这恰恰是本项目最不容含糊的部分。
  ///
  /// 一位负责任的维护者宁可少 9 种语言，也不肯让 9 种语言的人读到自己读不懂
  /// 的条款。剩下的 6 种——简中（原始表述）／繁中／英／德／法／俄——每一份都是
  /// 逐句写出来的，可以对读。
  ///
  /// 将来若要把某个语种加回来，前提是**它的全部键都是真译文**，而不是复制
  /// 英文。键集合由 `tool/i18n_scan.py --check` 强制与 `zh` 一致。
  static const List<OgLLocale> locales = <OgLLocale>[
    OgLLocale('zh', '简体中文'),
    OgLLocale('zh_TW', '繁體中文'),
    OgLLocale('en', 'English'),
    OgLLocale('de', 'Deutsch'),
    OgLLocale('fr', 'Français'),
    OgLLocale('ru', 'Русский'),
  ];

  /// 需要加载的页面分片（新增页面时在这里补一项即可）。
  static const List<String> pages = <String>[
    'about_page',
    'action_log_page',
    'action_run_page',
    'ai',
    'code_editor_page',
    'commit_page',
    'common',
    'dashboard_page',
    'download_manager_page',
    'drafts_page',
    'gist_detail_page',
    'gists_page',
    'issue_page',
    'login',
    'new_gist_page',
    'new_issue_page',
    'new_release_page',
    'new_repo_page',
    'notifications_page',
    'onboarding',
    'profile_page',
    'pull_page',
    'release_detail_page',
    'repo',
    'search_page',
    'settings',
    'shell',
    'workflow_dispatch_page',
  ];

  String _locale = 'zh';
  // locale → page → key → value
  final Map<String, Map<String, Map<String, String>>> _data =
      <String, Map<String, Map<String, String>>>{};

  /// 当前语言代码。
  String get locale => _locale;

  /// 当前语言的展示名。
  String get localeLabel {
    for (final OgLLocale item in locales) {
      if (item.code == _locale) {
        return item.label;
      }
    }
    return _locale;
  }

  /// 加载某语言的全部页面分片（同时确保英文基线已加载）。
  ///
  /// **永不抛**：单个分片读取失败只记录，不阻断应用（缺键会兜底到英文）。
  Future<void> load(String code) async {
    final String target = _isSupported(code) ? code : 'zh';
    // 基线与目标语言互不依赖，可同时读取；两者都到齐后兜底链才成立。
    await Future.wait(<Future<void>>[
      if (!_data.containsKey(baseLocale)) _loadLocale(baseLocale),
      if (!_data.containsKey(target)) _loadLocale(target),
    ]);
    if (_locale != target) {
      _locale = target;
      notifyListeners();
    }
  }

  bool _isSupported(String code) {
    for (final OgLLocale item in locales) {
      if (item.code == code) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadLocale(String code) async {
    // ★ 分片必须**并发**读取，不能顺序 await。
    //
    // 每个分片是一次独立的资源请求（Web 上就是一次 HTTP 取回）。20 余个分片
    // 顺序读取意味着 20 余次往返：桌面宽带下约 1~2 秒，移动网络下可达十几秒，
    // 期间界面停在启动画面。并发读取后总耗时接近单次往返。
    final List<Map<String, String>> results = await Future.wait(
      pages.map((String page) => _loadPage(code, page)),
    );
    final Map<String, Map<String, String>> pagesData =
        <String, Map<String, String>>{};
    for (int i = 0; i < pages.length; i++) {
      pagesData[pages[i]] = results[i];
    }
    _data[code] = pagesData;
  }

  Future<Map<String, String>> _loadPage(String code, String page) async {
    try {
      final String raw =
          await rootBundle.loadString('assets/i18n/$code/$page.json');
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String, String>{};
      }
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          '${e.key}': '${e.value}',
      };
    } catch (_) {
      // 分片缺失 / 解析失败：返回空表，交给兜底链（英文 → 键名）。
      return const <String, String>{};
    }
  }

  /// 取文案：`t('shell', 'home')`；需要插值用 `t('repo', 'deleted', args: {'path': p})`。
  ///
  /// 兜底顺序：当前语言 → 英文基线 → 键名（**绝不返回空串**）。
  ///
  /// 占位符：文案里写 `{path}`，调用时传 `args: {'path': ...}`；
  /// 缺参时**保留原样**（`{path}`）而不是抛异常——UI 不该因为缺一个参数就崩。
  String t(String page, String key, {Map<String, String>? args}) {
    final String raw = _raw(page, key);
    if (args == null || args.isEmpty) {
      return raw;
    }
    String out = raw;
    for (final MapEntry<String, String> entry in args.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    return out;
  }

  /// 原始文案（当前语言 → 英文基线 → 键名）。
  String _raw(String page, String key) {
    final String? current = _data[_locale]?[page]?[key];
    if (current != null && current.isNotEmpty) {
      return current;
    }
    final String? base = _data[baseLocale]?[page]?[key];
    if (base != null && base.isNotEmpty) {
      return base;
    }
    return key;
  }

  /// 仅测试用：注入内存数据（避免测试环境读不到 assets）。
  @visibleForTesting
  void debugInject(
    String code,
    Map<String, Map<String, String>> pagesData,
  ) {
    _data[code] = pagesData;
    _locale = code;
  }
}
