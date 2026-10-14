/// L3 展示级 · Release 下载加速通道（模型 / 内置通道 / 法律声明）。
///
/// ## 能力
/// - **一个总开关**：`releaseProxyEnabled`——关掉即全部走直连；
/// - **多个通道**：内置通道（开发者自建，唯一）+ 任意多个用户自定义通道；
/// - **选择一个**：`releaseProxySelectedId` 指定当前生效通道。
///
/// ## 法律声明（必须显式同意后才可启用）
/// 通道会把"下载请求"导向应用之外的服务器，涉及第三方信任边界，因此：
/// - 自定义（第三方）通道 → **外来服务自负责任协议**；
/// - 内置通道 → **内置通道安全声明**。
/// 协议**正文**收敛在 i18n 分片（`common` 页 `accelThirdPartyBody` /
/// `accelBuiltinBody`，15 语言），标题与版本号见本文件与 `kOgLAccelConsentVersion`；
/// 用户同意后会记录版本号与时间，文本升版必须重新同意。
library;

import '../i18n/og_l_i18n.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('common', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 同意协议的版本号：**文本任何实质修改都必须 +1**，以便重新征求同意。
const int kOgLAccelConsentVersion = 1;

/// 一个下载加速通道。
class OgLAccelChannel {
  /// 创建通道。
  const OgLAccelChannel({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.builtin = false,
  });

  /// 唯一标识（自定义通道由用户创建，内置固定为 [kOgLAccelBuiltinId]）。
  final String id;

  /// 展示名。
  final String name;

  /// 前缀地址（形如 `https://host:port/`，以 `/` 结尾）。
  final String baseUrl;

  /// 是否内置（内置不可删除）。
  final bool builtin;

  /// 由 JSON 构造（容错）。
  static OgLAccelChannel? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw['id'];
    final Object? name = raw['name'];
    final Object? base = raw['baseUrl'];
    if (id is! String || id.isEmpty || base is! String || base.isEmpty) {
      return null;
    }
    return OgLAccelChannel(
      id: id,
      name: name is String && name.isNotEmpty ? name : id,
      baseUrl: base,
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
      };

  @override
  bool operator ==(Object other) =>
      other is OgLAccelChannel && other.id == id && other.baseUrl == baseUrl;

  @override
  int get hashCode => Object.hash(id, baseUrl);
}

/// 内置通道 id。
const String kOgLAccelBuiltinId = 'builtin';

/// **内置通道的加速链（按优先级，不可由用户调整）**。
///
/// 1. `https://gh.felicity.ac.cn/https://github.com/` —— **优先**；
/// 2. `https://gh.felicity.ac.cn/` —— **降级备选**（旧式镜像前缀）。
///
/// 该代理是「URL 转发」形式：把**完整的 GitHub 链接**拼在前缀之后，
/// 即 `前缀 + 原始 URL`，例如
/// `https://gh.felicity.ac.cn/https://github.com/…`。
/// 下载时按序探测，**静默降级**：前一个不可用就直接用下一个，不打扰用户。
const List<String> kOgLAccelBuiltinBaseUrls = <String>[
  'https://gh.felicity.ac.cn/https://github.com/',
  'https://gh.felicity.ac.cn/',
];

/// 内置通道主前缀（= 链首，供只认单个前缀的旧路径使用）。
const String kOgLAccelBuiltinBaseUrl =
    'https://gh.felicity.ac.cn/https://github.com/';

/// 内置通道。
///
/// 对用户是**一个**通道（界面上不出地址、不可删改）；内部按
/// [kOgLAccelBuiltinBaseUrls] 的顺序静默降级。
const OgLAccelChannel kOgLAccelBuiltinChannel = OgLAccelChannel(
  id: kOgLAccelBuiltinId,
  name: '内置通道',
  baseUrl: kOgLAccelBuiltinBaseUrl,
  builtin: true,
);

/// 某个通道对应的**加速前缀链**（内置 = 固定链；自定义 = 单个）。
List<String> ogLAccelPrefixChain(OgLAccelChannel channel) => channel.builtin
    ? <String>[
        for (final String base in kOgLAccelBuiltinBaseUrls)
          ogLNormalizeAccelBase(base),
      ]
    : <String>[ogLNormalizeAccelBase(channel.baseUrl)];

/// 校验自定义通道地址（返回 `null` = 通过）。
String? ogLValidateAccelBaseUrl(String raw) {
  final String input = raw.trim();
  if (input.isEmpty) {
    return _t('accelUrlRequired');
  }
  if (RegExp(r'[\u2E80-\u9FFF\uFF00-\uFFEF]').hasMatch(input)) {
    return _t('accelUrlCjk');
  }
  if (!input.startsWith('https://') && !input.startsWith('http://')) {
    return _t('accelUrlScheme');
  }
  if (input.contains(' ')) {
    return _t('accelUrlSpace');
  }
  if (input.startsWith('http://')) {
    // 明文会被 Android 9+ 直接拦截（此前 4.4.0 的故障根因），提前告知。
    return _t('accelUrlPlaintext');
  }
  if (!input.endsWith('/')) {
    return _t('accelUrlTrailingSlash');
  }
  return null;
}

/// 归一化：确保以 `/` 结尾（便于拼接原始 URL）。
String ogLNormalizeAccelBase(String raw) {
  final String trimmed = raw.trim();
  return trimmed.endsWith('/') ? trimmed : '$trimmed/';
}

/// 按通道类型返回对应协议文本。
String ogLAccelAgreementFor(OgLAccelChannel channel) => channel.builtin
    ? _t('accelBuiltinBody')
    : _t('accelThirdPartyBody');
