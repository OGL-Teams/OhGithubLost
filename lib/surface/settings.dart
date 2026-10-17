/// L3 展示级 · 设置（外观 / 代码与文件 / 网络 → 真实行为）。
///
/// ## 只留"真选项"
/// 每个字段都必须接到真实行为上，否则就是"假选项"（比没有选项更糟）：
/// - 外观：`mode` / `seedColorId` / `fontScale` / `density` / `reduceMotion`
///   / `motionLevel` → 直接决定 `ThemeData`、文字缩放与动效；
/// - 代码与文件：`codeHighlight` / `codeFontSize` / `codeWrap` / `foldersFirst`
///   → 直接作用于仓库代码查看器与目录排序；
/// - 网络：`dnsMode` / `dnsServerId` / `dnsPreferDoh` → 即时作用到底座网络；
/// - 引导：`onboardingDone` → 是否展示首次权限引导。
///
/// ## 两条纪律
/// - 反序列化**永不抛异常**：坏字段回落默认值，数值越界一律夹紧
///   （用户手改配置文件不会炸应用）；
/// - 存储键沿用 `ogl.settings`：老配置文件可平滑读取（多余字段被忽略，
///   缺失的新字段回落**等于旧行为**的保守默认值）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'i18n/og_l_i18n.dart';
import 'util/accel.dart';

/// 解析历史 / 手改配置里的下载并发（非法值 → 默认）。
int _asDownloadConnections(Object? raw) {
  final int? value = raw is int ? raw : int.tryParse('${raw ?? ''}');
  if (value == null) {
    return OgLSettings.kOgLDefaultDownloadConnections;
  }
  return OgLSettings.downloadConnectionChoices.contains(value)
      ? value
      : OgLSettings.kOgLDefaultDownloadConnections;
}

/// 明暗模式偏好。
enum OgLThemeMode {
  /// 跟随系统。
  system,

  /// 强制亮色。
  light,

  /// 强制暗色。
  dark;

  /// 解析（坏值回落 [OgLThemeMode.system]）。
  static OgLThemeMode parse(Object? raw) {
    if (raw is String) {
      for (final OgLThemeMode value in values) {
        if (value.name == raw) {
          return value;
        }
      }
    }
    return system;
  }
}

/// 用户设置（不可变；容错反序列化）。
///
/// 新增字段一律给**保守默认值**（等于旧行为），保证老配置文件升级后
/// 不会因为"新字段缺失"而改变用户已有的体验。
@immutable
class OgLSettings {
  /// 创建设置。
  const OgLSettings({
    this.mode = OgLThemeMode.system,
    this.seedColorId = 'github',
    this.fontScale = 1.0,
    this.density = 'comfortable',
    this.reduceMotion = false,
    this.dnsMode = 'system',
    this.dnsServerId = 'alidns',
    this.dnsPreferDoh = true,
    this.dnsCustomIp = '',
    this.dnsCustomDohUrl = '',
    this.downloadConnections = OgLSettings.kOgLDefaultDownloadConnections,
    this.releaseProxyEnabled = false,
    this.accelPrivateRepoAccepted = false,
    this.accelScopes = kOgLAccelAllScopeIds,
    this.releaseProxyChannels = const <OgLAccelChannel>[],
    this.releaseProxySelectedId = '',
    this.releaseProxyConsentVersion = 0,
    this.releaseProxyConsentAt,
    this.foldersFirst = true,
    this.codeHighlight = true,
    this.codeFontSize = 13,
    this.codeWrap = false,
    this.codeThemePreset = 'theme',
    this.codeColorBackground = 0xFF1E1E1E,
    this.codeColorForeground = 0xFFE6EDF3,
    this.codeColorKeyword = 0xFF569CD6,
    this.codeColorTypeName = 0xFF4EC9B0,
    this.codeColorString = 0xFFCE9178,
    this.codeColorComment = 0xFF6A9955,
    this.codeColorNumber = 0xFFB5CEA8,
    this.onboardingDone = false,
    this.motionLevel = 1,
    this.languageCode = 'zh',
  });

  /// 默认值。
  static const OgLSettings defaults = OgLSettings();

  /// 默认并发连接数（4：三条以上并行足够吃满家用宽带，又不至于把
  /// 小水管拖成"每片都在排队"）。
  static const int kOgLDefaultDownloadConnections = 4;

  /// 字号缩放上下限（与 `og_l_app` 的文字缩放夹紧一致）。
  static const double minFontScale = 0.8;
  static const double maxFontScale = 1.6;

  /// 代码字号上下限。
  static const double minCodeFontSize = 10;
  static const double maxCodeFontSize = 22;

  /// 允许的下载并发档位（设置页只给这几档，避免「随便填个大数」）。
  static const List<int> downloadConnectionChoices = <int>[1, 2, 4, 8, 16, 32];

  /// 由 JSON 构造（**永不抛**：坏数据回落默认）。
  factory OgLSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return defaults;
    }
    final Object? serverId = raw['dnsServerId'];
    final Object? seed = raw['seedColorId'];
    return OgLSettings(
      mode: OgLThemeMode.parse(raw['mode']),
      seedColorId: seed is String && seed.isNotEmpty ? seed : 'github',
      fontScale: _clampDouble(
        raw['fontScale'],
        fallback: 1.0,
        min: minFontScale,
        max: maxFontScale,
      ),
      density: raw['density'] == 'compact' ? 'compact' : 'comfortable',
      reduceMotion: _asBool(raw['reduceMotion'], fallback: false),
      dnsMode: raw['dnsMode'] == 'custom' ? 'custom' : 'system',
      dnsServerId:
          serverId is String && serverId.isNotEmpty ? serverId : 'alidns',
      dnsPreferDoh: _asBool(raw['dnsPreferDoh'], fallback: true),
      dnsCustomIp:
          raw['dnsCustomIp'] is String ? raw['dnsCustomIp'] as String : '',
      dnsCustomDohUrl: raw['dnsCustomDohUrl'] is String
          ? raw['dnsCustomDohUrl'] as String
          : '',
      downloadConnections: _asDownloadConnections(raw['downloadConnections']),
      releaseProxyEnabled: _asBool(raw['releaseProxyEnabled'], fallback: false),
      accelPrivateRepoAccepted:
          _asBool(raw['accelPrivateRepoAccepted'], fallback: false),
      accelScopes: _asAccelScopes(raw['accelScopes']),
      releaseProxyChannels: _asAccelChannels(raw['releaseProxyChannels']),
      releaseProxySelectedId: _asAccelSelectedId(raw['releaseProxySelectedId']),
      releaseProxyConsentVersion:
          _asInt(raw['releaseProxyConsentVersion'], fallback: 0),
      releaseProxyConsentAt: raw['releaseProxyConsentAt'] is String &&
              (raw['releaseProxyConsentAt'] as String).isNotEmpty
          ? raw['releaseProxyConsentAt'] as String
          : null,
      foldersFirst: _asBool(raw['foldersFirst'], fallback: true),
      codeHighlight: _asBool(raw['codeHighlight'], fallback: true),
      codeFontSize: _clampDouble(
        raw['codeFontSize'],
        fallback: 13,
        min: minCodeFontSize,
        max: maxCodeFontSize,
      ),
      codeWrap: _asBool(raw['codeWrap'], fallback: false),
      codeThemePreset: _asPreset(raw['codeThemePreset']),
      codeColorBackground:
          _asColorInt(raw['codeColorBackground'], fallback: 0xFF1E1E1E),
      codeColorForeground:
          _asColorInt(raw['codeColorForeground'], fallback: 0xFFE6EDF3),
      codeColorKeyword:
          _asColorInt(raw['codeColorKeyword'], fallback: 0xFF569CD6),
      codeColorTypeName:
          _asColorInt(raw['codeColorTypeName'], fallback: 0xFF4EC9B0),
      codeColorString:
          _asColorInt(raw['codeColorString'], fallback: 0xFFCE9178),
      codeColorComment:
          _asColorInt(raw['codeColorComment'], fallback: 0xFF6A9955),
      codeColorNumber:
          _asColorInt(raw['codeColorNumber'], fallback: 0xFFB5CEA8),
      onboardingDone: _asBool(raw['onboardingDone'], fallback: false),
      motionLevel: _motionLevelOf(raw),
      languageCode: _asLocale(raw['languageCode']),
    );
  }

  /// 动效档位解析（0–3；旧键 `reduceMotion` 为真时视为最小动效）。
  static int _motionLevelOf(Map<dynamic, dynamic> raw) {
    final Object? level = raw['motionLevel'];
    if (level is num) {
      // Infinity/NaN 的 toInt() 会抛 UnsupportedError——那会击穿
      // 「fromJson 永不抛」纪律（一处坏值 = 全部设置丢失）。非有限值回落。
      if (!level.isFinite) {
        return 1;
      }
      final int v = level.toInt();
      return v < 0 ? 0 : (v > 3 ? 3 : v);
    }
    if (_asBool(raw['reduceMotion'], fallback: false)) {
      return 0;
    }
    return 1;
  }

  static bool _asBool(Object? value, {required bool fallback}) =>
      value is bool ? value : fallback;

  static int _asInt(Object? value, {required int fallback}) => value is int
      ? value
      : (value is num && value.isFinite ? value.toInt() : fallback);

  /// 解析自定义通道列表（坏条目直接丢弃，绝不抛异常）。
  static List<OgLAccelChannel> _asAccelChannels(Object? value) {
    if (value is! List) {
      return const <OgLAccelChannel>[];
    }
    final List<OgLAccelChannel> result = <OgLAccelChannel>[];
    final Set<String> seen = <String>{};
    for (final Object? item in value) {
      final OgLAccelChannel? channel = OgLAccelChannel.fromJson(item);
      if (channel == null) {
        continue;
      }
      if (seen.add(channel.id)) {
        result.add(channel);
      }
    }
    return result;
  }

  /// 解析加速适用范围：只保留认识的 id；字段缺失 → 全开（= 历史行为）。
  static List<String> _asAccelScopes(Object? value) {
    if (value is! List) {
      return kOgLAccelAllScopeIds;
    }
    final List<String> out = <String>[];
    for (final Object? item in value) {
      final OgLAccelScope? scope = OgLAccelScope.fromId('$item');
      if (scope != null && !out.contains(scope.id)) {
        out.add(scope.id);
      }
    }
    // 显式写成空列表 = 用户把每一项都关了，那是合法状态，不回落成全开。
    return out;
  }

  /// 选中的通道 id。v6.4.3 起**没有内置通道**，因此默认是空串
  /// （= 没有选中任何通道 = 不加速），而不是回落到某个"产品默认通道"。
  static String _asAccelSelectedId(Object? value) =>
      value is String ? value : '';

  /// 代码主题预设白名单（与展示层 `code_editor_field.dart` 保持一致）。
  static const List<String> codeThemePresetIds = <String>[
    'theme',
    'high_contrast',
    'soft',
    'custom',
  ];

  /// 动效档位可选值（0 最小、1 当前、2 标准、3 增强）。
  static const List<int> motionLevelIds = <int>[0, 1, 2, 3];

  static String _asPreset(Object? value) =>
      value is String && codeThemePresetIds.contains(value) ? value : 'theme';

  /// 支持的语言代码白名单（与展示层 `og_l_i18n.dart` 保持一致）。
  ///
  /// v6.4.0 起收敛为 **6 种**（简中 / 繁中 / 英 / 德 / 法 / 俄）——
  /// 与 [OgLI18n.locales]、`assets/i18n/` 目录、pubspec 资源声明三处对齐。
  /// 保持"数据层不认识 UI 资源"的前提下，这里只存**代码**；
  /// 具体加载由展示层完成，非法代码一律回落 `zh`。
  static const List<String> languageCodes = <String>[
    'zh',
    'zh_TW',
    'en',
    'de',
    'fr',
    'ru',
  ];

  static String _asLocale(Object? value) =>
      value is String && languageCodes.contains(value) ? value : 'zh';

  static int _asColorInt(Object? value, {required int fallback}) {
    if (value is int && value >= 0 && value <= 0xFFFFFFFF) {
      return value;
    }
    if (value is num && value.isFinite) {
      // Infinity/NaN 的 toInt() 会抛（见 _motionLevelOf 处注）——先挡掉。
      final int v = value.toInt();
      if (v >= 0 && v <= 0xFFFFFFFF) {
        return v;
      }
    }
    return fallback;
  }

  static double _clampDouble(
    Object? value, {
    required double fallback,
    required double min,
    required double max,
  }) {
    if (value is! num) {
      return fallback;
    }
    final double v = value.toDouble();
    if (v.isNaN) {
      return fallback;
    }
    return v.clamp(min, max).toDouble();
  }

  /// 明暗模式。
  final OgLThemeMode mode;

  /// 主题种子色 id（映射见展示层 `theme.dart`）。
  final String seedColorId;

  /// 全局文字缩放（相对系统字号的额外倍数）。
  final double fontScale;

  /// 界面密度（`comfortable` / `compact`）。
  final String density;

  /// 是否减少动效（无障碍）。
  final bool reduceMotion;

  /// DNS 解析模式（`system` / `custom`）。
  final String dnsMode;

  /// 自定义模式下的内置 DNS 服务器 id。
  final String dnsServerId;

  /// 是否优先 DoH（加密解析）。
  final bool dnsPreferDoh;

  /// 自定义 DNS 服务器 IP（空串 = 未自定义）。
  ///
  /// 与 [dnsServerId] 的关系：`dnsServerId == 'custom'` 时用本字段；
  /// 内置五家（ali/dnspod/114/cloudflare/google）用不到它。
  final String dnsCustomIp;

  /// 自定义 DoH 端点（可选；必须 `https://`，空串 = 用明文 UDP）。
  final String dnsCustomDohUrl;

  /// 下载并发连接数（1 = 单连接走库；>1 = 多连接分片）。
  ///
  /// 由设置页给出，跟随 `enqueue` 传入中枢层；服务端不支持 Range 时
  /// 中枢层会**自动回退**到单连接，不会因为并发调高而下载失败。
  final int downloadConnections;

  /// Release 附件是否走加速通道。
  ///
  /// 默认**关闭**：加速通道属于第三方信任边界，需用户显式开启；
  /// 通道地址属实现细节，**不出现在界面文案中**。
  final bool releaseProxyEnabled;

  /// 用户是否已知情并接受「私有仓库走加速 = 令牌交给第三方代理」。
  ///
  /// ## 语义很关键：true 表示**接受风险**，false 表示**不加速**
  /// 本项目不留「别再问我、但照旧送令牌」这种选项 —— 那等于把一次性的
  /// 知情同意悄悄变成永久授权。用户在弹窗里关掉问询，得到的就是退回
  /// 不加速的默认行为。
  ///
  /// 默认 `false`：私有仓库的 raw 一律不加速（令牌不出设备）。
  final bool accelPrivateRepoAccepted;

  /// **加速适用范围**：哪些资源允许走通道（见 [OgLAccelScope]）。
  ///
  /// 前缀式代理开放的端点有限，"哪些资源加速"写死必然有人用不了；
  /// 所以逐项可关。默认全开 = 与历史行为一致；全关也合法（= 不加速）。
  final List<String> accelScopes;

  /// 用户自定义的加速通道（**不含**内置通道；内置通道是常量）。
  final List<OgLAccelChannel> releaseProxyChannels;

  /// 当前选中的通道 id；空串 = 没有选中（也就没有加速）。
  final String releaseProxySelectedId;

  /// 已同意的协议版本（0 = 从未同意；与 [kOgLAccelConsentVersion] 不一致需重新同意）。
  final int releaseProxyConsentVersion;

  /// 同意时间（ISO8601，作为"已同意"的凭据留痕）。
  final String? releaseProxyConsentAt;

  /// 全部可选通道（**只有用户自建的**；本应用不预置任何通道）。
  List<OgLAccelChannel> get allAccelChannels =>
      List<OgLAccelChannel>.unmodifiable(releaseProxyChannels);

  /// 当前选中的通道；**没有则为 `null`**（没建通道 = 没得选 = 不加速）。
  ///
  /// 此前这里会"回落内置通道"——那是一种隐式选择：用户没选，程序替他选了一个
  /// 开发者自建的代理。现在没有可回落的东西，没有就是没有。
  OgLAccelChannel? get activeAccelChannel {
    for (final OgLAccelChannel channel in allAccelChannels) {
      if (channel.id == releaseProxySelectedId) {
        return channel;
      }
    }
    return null;
  }

  /// 是否已完成当前版本的协议同意。
  bool get accelConsentCurrent =>
      releaseProxyConsentVersion >= kOgLAccelConsentVersion;

  /// 某个适用范围是否开启。
  bool accelScopeEnabled(OgLAccelScope scope) => accelScopes.contains(scope.id);

  /// **按范围**取生效前缀：范围关掉、或总开关/协议/通道任一不满足 → 空列表。
  ///
  /// 这是各调用点唯一的判断入口：调用方只说"我是哪一类资源"，是否加速由这里
  /// 决定（也就只有一处规则，不会两处结论不同）。
  List<String> accelPrefixesFor(OgLAccelScope scope) =>
      accelScopeEnabled(scope) ? activeAccelPrefixes : const <String>[];

  /// 当前生效的加速前缀列表（**至多一项**）；不可用时为空列表。
  ///
  /// 曾经这里返回"按优先级排列的链"并静默降级；现在一个通道就是一个前缀，
  /// 见 `util/download_proxy.dart` 的说明。
  List<String> get activeAccelPrefixes {
    final OgLAccelChannel? channel = activeAccelChannel;
    if (!releaseProxyEnabled || !accelConsentCurrent || channel == null) {
      return const <String>[];
    }
    return ogLAccelPrefixesFor(channel);
  }

  /// 仓库浏览器是否**目录优先**。
  final bool foldersFirst;

  /// 代码查看是否启用语法高亮。
  final bool codeHighlight;

  /// 代码字号。
  final double codeFontSize;

  /// 代码是否自动换行。
  final bool codeWrap;

  /// 代码高亮主题预设（见 [codeThemePresetIds]）。
  final String codeThemePreset;

  /// 自定义预设：背景色（ARGB）。
  final int codeColorBackground;

  /// 自定义预设：普通文本色。
  final int codeColorForeground;

  /// 自定义预设：关键词色。
  final int codeColorKeyword;

  /// 自定义预设：类型名色。
  final int codeColorTypeName;

  /// 自定义预设：字符串色。
  final int codeColorString;

  /// 自定义预设：注释色。
  final int codeColorComment;

  /// 自定义预设：数字色。
  final int codeColorNumber;

  /// 是否已完成首次引导（含权限说明）。
  final bool onboardingDone;

  /// 界面语言代码（见 [languageCodes]）。
  final String languageCode;

  /// 动效档位：0 最小、1 当前、2 标准、3 增强（详见 `app/motion.dart`）。
  final int motionLevel;

  /// 复制并覆盖部分字段。
  OgLSettings copyWith({
    OgLThemeMode? mode,
    String? seedColorId,
    double? fontScale,
    String? density,
    bool? reduceMotion,
    String? dnsMode,
    String? dnsServerId,
    String? dnsCustomIp,
    String? dnsCustomDohUrl,
    bool? dnsPreferDoh,
    int? downloadConnections,
    bool? releaseProxyEnabled,
    bool? accelPrivateRepoAccepted,
    List<String>? accelScopes,
    List<OgLAccelChannel>? releaseProxyChannels,
    String? releaseProxySelectedId,
    int? releaseProxyConsentVersion,
    String? releaseProxyConsentAt,
    bool? foldersFirst,
    bool? codeHighlight,
    double? codeFontSize,
    bool? codeWrap,
    String? codeThemePreset,
    int? codeColorBackground,
    int? codeColorForeground,
    int? codeColorKeyword,
    int? codeColorTypeName,
    int? codeColorString,
    int? codeColorComment,
    int? codeColorNumber,
    bool? onboardingDone,
    String? languageCode,
    int? motionLevel,
  }) =>
      OgLSettings(
        mode: mode ?? this.mode,
        seedColorId: seedColorId ?? this.seedColorId,
        fontScale: fontScale ?? this.fontScale,
        density: density ?? this.density,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        dnsMode: dnsMode ?? this.dnsMode,
        dnsServerId: dnsServerId ?? this.dnsServerId,
        dnsCustomIp: dnsCustomIp ?? this.dnsCustomIp,
        dnsCustomDohUrl: dnsCustomDohUrl ?? this.dnsCustomDohUrl,
        dnsPreferDoh: dnsPreferDoh ?? this.dnsPreferDoh,
        downloadConnections: downloadConnections ?? this.downloadConnections,
        releaseProxyEnabled: releaseProxyEnabled ?? this.releaseProxyEnabled,
        accelPrivateRepoAccepted:
            accelPrivateRepoAccepted ?? this.accelPrivateRepoAccepted,
        accelScopes: accelScopes ?? this.accelScopes,
        releaseProxyChannels: releaseProxyChannels ?? this.releaseProxyChannels,
        releaseProxySelectedId:
            releaseProxySelectedId ?? this.releaseProxySelectedId,
        releaseProxyConsentVersion:
            releaseProxyConsentVersion ?? this.releaseProxyConsentVersion,
        releaseProxyConsentAt:
            releaseProxyConsentAt ?? this.releaseProxyConsentAt,
        foldersFirst: foldersFirst ?? this.foldersFirst,
        codeHighlight: codeHighlight ?? this.codeHighlight,
        codeFontSize: codeFontSize ?? this.codeFontSize,
        codeWrap: codeWrap ?? this.codeWrap,
        codeThemePreset: codeThemePreset ?? this.codeThemePreset,
        codeColorBackground: codeColorBackground ?? this.codeColorBackground,
        codeColorForeground: codeColorForeground ?? this.codeColorForeground,
        codeColorKeyword: codeColorKeyword ?? this.codeColorKeyword,
        codeColorTypeName: codeColorTypeName ?? this.codeColorTypeName,
        codeColorString: codeColorString ?? this.codeColorString,
        codeColorComment: codeColorComment ?? this.codeColorComment,
        codeColorNumber: codeColorNumber ?? this.codeColorNumber,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        languageCode: languageCode ?? this.languageCode,
        motionLevel: motionLevel ?? this.motionLevel,
      );

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        'seedColorId': seedColorId,
        'fontScale': fontScale,
        'density': density,
        'reduceMotion': reduceMotion,
        'dnsMode': dnsMode,
        'dnsServerId': dnsServerId,
        'dnsPreferDoh': dnsPreferDoh,
        'dnsCustomIp': dnsCustomIp,
        'dnsCustomDohUrl': dnsCustomDohUrl,
        'downloadConnections': downloadConnections,
        'releaseProxyEnabled': releaseProxyEnabled,
        'accelPrivateRepoAccepted': accelPrivateRepoAccepted,
        'accelScopes': accelScopes,
        'releaseProxyChannels': <Object?>[
          for (final OgLAccelChannel channel in releaseProxyChannels)
            channel.toJson(),
        ],
        'releaseProxySelectedId': releaseProxySelectedId,
        'releaseProxyConsentVersion': releaseProxyConsentVersion,
        if (releaseProxyConsentAt != null)
          'releaseProxyConsentAt': releaseProxyConsentAt,
        'foldersFirst': foldersFirst,
        'codeHighlight': codeHighlight,
        'codeFontSize': codeFontSize,
        'codeWrap': codeWrap,
        'codeThemePreset': codeThemePreset,
        'codeColorBackground': codeColorBackground,
        'codeColorForeground': codeColorForeground,
        'codeColorKeyword': codeColorKeyword,
        'codeColorTypeName': codeColorTypeName,
        'codeColorString': codeColorString,
        'codeColorComment': codeColorComment,
        'codeColorNumber': codeColorNumber,
        'onboardingDone': onboardingDone,
        'motionLevel': motionLevel,
        'languageCode': languageCode,
      };

  /// 编码为 JSON 文本。
  String encode() => jsonEncode(toJson());
}

/// 设置持久化接口（由表面桥用底座 KV 实现；展示层不直接依赖底座）。
abstract class OgLSettingsPersistence {
  /// 读取原始 JSON（无记录返回 `null`）。
  Future<String?> read();

  /// 写入原始 JSON。
  Future<void> write(String raw);

  /// 清空。
  Future<void> clear();
}

/// 内存实现（测试 / 纯内存模式）。
class OgLInMemorySettingsPersistence implements OgLSettingsPersistence {
  /// 创建。
  OgLInMemorySettingsPersistence([this._raw]);

  String? _raw;

  @override
  Future<String?> read() async => _raw;

  @override
  Future<void> write(String raw) async {
    _raw = raw;
  }

  @override
  Future<void> clear() async {
    _raw = null;
  }
}

/// 设置控制器（UI 唯一读取设置的入口）。
class OgLSettingsController extends ChangeNotifier {
  /// 创建控制器。
  OgLSettingsController({OgLSettingsPersistence? persistence})
      : _persistence = persistence ?? OgLInMemorySettingsPersistence();

  /// 存储键（由表面桥绑定到底座 KV）。
  static const String storageKey = 'ogl.settings';

  final OgLSettingsPersistence _persistence;

  OgLSettings _settings = OgLSettings.defaults;
  String? _lastError;
  bool _loaded = false;

  /// load 世代号：每次 load 自增；迟到的 load 若发现自己不是最新一代，
  /// 不得覆盖内存（防 apply 先落、load 后到把新值冲回旧值）。
  int _loadGen = 0;

  /// 当前设置。
  OgLSettings get settings => _settings;

  /// 最近一次加载 / 保存错误（**不吞**，UI 可提示）。
  String? get lastError => _lastError;

  /// 是否已完成一次加载。
  bool get isLoaded => _loaded;

  /// UI 已消费一次错误后清零（弹过一次 SnackBar 后调用，避免反复弹同一条）。
  ///
  /// **不是**「下一次错误前不要再弹」——而是「这次已经告诉过用户了」。
  void clearLastError() {
    if (_lastError == null) {
      return;
    }
    _lastError = null;
    notifyListeners();
  }

  /// 加载（**永不抛**：坏数据回落默认并记录原因）。
  ///
  /// **首次启动**（尚无持久化数据）跟随系统语言：系统语言受支持就用它，
  /// 否则回落 `zh`。已有配置则一律尊重用户选择，不再被系统语言改写。
  Future<void> load() async {
    // 世代号：load 期间用户可能已经 apply（启动初期最快的操作路径）。
    // 迟到的 load 不得用旧快照覆盖内存里更新的值，否则改动被静默回退、
    // 且下一次 apply 会把旧值重新写盘（永久丢失）。
    final int gen = ++_loadGen;
    try {
      final String? raw = await _persistence.read();
      if (gen != _loadGen) {
        return; // 期间又来了一次 load/apply，本次结果作废。
      }
      if (raw == null) {
        _settings = OgLSettings.defaults
            .copyWith(languageCode: ogLDetectDeviceLocale());
      } else {
        _settings = OgLSettings.fromJson(jsonDecode(raw));
      }
      _lastError = null;
    } catch (error) {
      if (gen != _loadGen) {
        return;
      }
      _settings = OgLSettings.defaults;
      _lastError = OgLI18n.instance.t('settings', 'errorLoad',
          args: <String, String>{'error': '$error'});
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// 应用一份新设置（**先落盘**；失败保留内存新值并记录，绝不静默）。
  Future<void> apply(OgLSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      await _persistence.write(next.encode());
      // 保存结果改变 UI 可见状态（错误横幅），必须通知——否则横幅双向
      // 滞留：失败时横幅不出现，恢复成功后旧横幅不消失。
      if (_lastError != null) {
        _lastError = null;
        notifyListeners();
      }
    } catch (error) {
      _lastError = OgLI18n.instance.t('settings', 'errorSave',
          args: <String, String>{'error': '$error'});
      notifyListeners();
    }
  }

  /// 便捷：切换明暗。
  Future<void> setMode(OgLThemeMode mode) =>
      apply(_settings.copyWith(mode: mode));

  /// 便捷：设置 DNS 解析模式（`system` / `custom`）。
  Future<void> setDnsMode(String mode) => apply(
      _settings.copyWith(dnsMode: mode == 'custom' ? 'custom' : 'system'));

  /// 便捷：设置自定义模式下的内置 DNS。
  Future<void> setDnsServer(String serverId) =>
      apply(_settings.copyWith(dnsServerId: serverId));

  /// 便捷：设置 DoH 优先。
  Future<void> setDnsPreferDoh(bool enabled) =>
      apply(_settings.copyWith(dnsPreferDoh: enabled));

  /// 便捷：设置自定义 DNS 服务器 IP（空串 = 取消自定义）。
  ///
  /// 切换 id 到 `custom`：设置了 IP 即视为用户想用自定义解析器。
  Future<void> setDnsCustomIp(String ip) => apply(
        _settings.copyWith(
          dnsCustomIp: ip.trim(),
          dnsServerId: ip.trim().isEmpty ? _settings.dnsServerId : 'custom',
        ),
      );

  /// 便捷：设置自定义 DoH 端点（空串 = 只用明文 UDP）。
  Future<void> setDnsCustomDohUrl(String url) =>
      apply(_settings.copyWith(dnsCustomDohUrl: url.trim()));

  /// 便捷：Release 附件是否走加速通道（总开关）。
  Future<void> setReleaseProxyEnabled(bool enabled) =>
      apply(_settings.copyWith(releaseProxyEnabled: enabled));

  /// 便捷：选择生效的加速通道。
  Future<void> setReleaseProxySelected(String channelId) =>
      apply(_settings.copyWith(releaseProxySelectedId: channelId));

  /// 便捷：开关某个加速适用范围。
  Future<void> setAccelScope(OgLAccelScope scope, bool enabled) {
    final List<String> next = <String>[
      for (final String id in _settings.accelScopes)
        if (id != scope.id) id,
    ];
    if (enabled && !next.contains(scope.id)) {
      next.add(scope.id);
    }
    // 保持枚举顺序，落盘可读、diff 稳定。
    next.sort((String a, String b) => OgLAccelScope.values
        .indexWhere((OgLAccelScope s) => s.id == a)
        .compareTo(
            OgLAccelScope.values.indexWhere((OgLAccelScope s) => s.id == b)));
    return apply(_settings.copyWith(accelScopes: next));
  }

  /// 便捷：私有仓库是否允许走加速（**知情接受**才置 true）。
  Future<void> setAccelPrivateRepoAccepted(bool on) =>
      apply(_settings.copyWith(accelPrivateRepoAccepted: on));

  /// 便捷：新增/更新一个自定义加速通道。
  Future<void> upsertAccelChannel(OgLAccelChannel channel) {
    final List<OgLAccelChannel> next = <OgLAccelChannel>[
      for (final OgLAccelChannel item in _settings.releaseProxyChannels)
        if (item.id != channel.id) item,
      channel,
    ];
    return apply(_settings.copyWith(releaseProxyChannels: next));
  }

  /// 便捷：删除一个自定义加速通道（内置通道不可删）。
  Future<void> removeAccelChannel(String channelId) {
    final List<OgLAccelChannel> next = <OgLAccelChannel>[
      for (final OgLAccelChannel item in _settings.releaseProxyChannels)
        if (item.id != channelId) item,
    ];
    // 删掉的正是当前选中项 → 选中清空（**不回落到别的通道**：那等于替用户
    // 换了个代理，而用户可能并不接受那一个）。
    final bool needClear = _settings.releaseProxySelectedId == channelId;
    return apply(_settings.copyWith(
      releaseProxyChannels: next,
      releaseProxySelectedId: needClear ? '' : _settings.releaseProxySelectedId,
    ));
  }

  /// 便捷：记录"已同意当前版本协议"（写入时间作为凭据）。
  Future<void> acceptAccelConsent() => apply(_settings.copyWith(
        releaseProxyConsentVersion: kOgLAccelConsentVersion,
        releaseProxyConsentAt: DateTime.now().toIso8601String(),
      ));

  /// 便捷：设置主题色。
  Future<void> setSeedColor(String id) =>
      apply(_settings.copyWith(seedColorId: id));

  /// 便捷：设置全局文字缩放。
  Future<void> setFontScale(double scale) => apply(_settings.copyWith(
        fontScale: scale
            .clamp(
              OgLSettings.minFontScale,
              OgLSettings.maxFontScale,
            )
            .toDouble(),
      ));

  /// 便捷：设置界面密度（`comfortable` / `compact`）。
  Future<void> setDensity(String density) => apply(
        _settings.copyWith(
          density: density == 'compact' ? 'compact' : 'comfortable',
        ),
      );

  /// 便捷：设置减少动效。
  Future<void> setReduceMotion(bool enabled) =>
      apply(_settings.copyWith(reduceMotion: enabled));

  /// 便捷：设置全局动效档位（越界夹紧到 0–3）。
  Future<void> setMotionLevel(int level) => apply(
        _settings.copyWith(
          motionLevel: level < 0 ? 0 : (level > 3 ? 3 : level),
        ),
      );

  /// 便捷：设置目录优先。
  Future<void> setFoldersFirst(bool enabled) =>
      apply(_settings.copyWith(foldersFirst: enabled));

  /// 便捷：设置代码高亮。
  Future<void> setCodeHighlight(bool enabled) =>
      apply(_settings.copyWith(codeHighlight: enabled));

  /// 便捷：设置代码字号。
  Future<void> setCodeFontSize(double size) => apply(_settings.copyWith(
        codeFontSize: size
            .clamp(
              OgLSettings.minCodeFontSize,
              OgLSettings.maxCodeFontSize,
            )
            .toDouble(),
      ));

  /// 便捷：设置代码自动换行。
  Future<void> setCodeWrap(bool enabled) =>
      apply(_settings.copyWith(codeWrap: enabled));

  /// 便捷：设置代码高亮预设。
  Future<void> setCodeThemePreset(String preset) => apply(
        _settings.copyWith(
          codeThemePreset: OgLSettings.codeThemePresetIds.contains(preset)
              ? preset
              : 'theme',
        ),
      );

  /// 便捷：设置自定义预设的某一颜色。
  ///
  /// [field] 取 `background` / `foreground` / `keyword` / `typeName` /
  /// `string` / `comment` / `number`；未知字段忽略（不抛）。
  Future<void> setCodeColor(String field, int argb) async {
    switch (field) {
      case 'background':
        await apply(_settings.copyWith(codeColorBackground: argb));
        break;
      case 'foreground':
        await apply(_settings.copyWith(codeColorForeground: argb));
        break;
      case 'keyword':
        await apply(_settings.copyWith(codeColorKeyword: argb));
        break;
      case 'typeName':
        await apply(_settings.copyWith(codeColorTypeName: argb));
        break;
      case 'string':
        await apply(_settings.copyWith(codeColorString: argb));
        break;
      case 'comment':
        await apply(_settings.copyWith(codeColorComment: argb));
        break;
      case 'number':
        await apply(_settings.copyWith(codeColorNumber: argb));
        break;
      default:
        break;
    }
  }

  /// 便捷：标记首次引导已完成。
  Future<void> setOnboardingDone(bool done) =>
      apply(_settings.copyWith(onboardingDone: done));

  /// 便捷：设置下载并发连接数（非法档位回落默认）。
  Future<void> setDownloadConnections(int value) => apply(
        _settings.copyWith(
          downloadConnections:
              OgLSettings.downloadConnectionChoices.contains(value)
                  ? value
                  : OgLSettings.kOgLDefaultDownloadConnections,
        ),
      );

  /// 便捷：设置界面语言（非法代码回落 `zh`）。
  Future<void> setLanguage(String code) => apply(
        _settings.copyWith(
          languageCode: OgLSettings.languageCodes.contains(code) ? code : 'zh',
        ),
      );

  /// 重置为默认（并清空持久化）。
  Future<void> reset() async {
    await apply(OgLSettings.defaults);
    try {
      await _persistence.clear();
    } catch (error) {
      _lastError = OgLI18n.instance.t('settings', 'errorReset',
          args: <String, String>{'error': '$error'});
    }
  }
}
