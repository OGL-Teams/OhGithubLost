/// L3 展示级 · 下载加速通道（模型 / 校验 / 法律声明）。
///
/// ## 能力（v6.4.3 起：**没有内置通道**）
/// - **一个总开关**：`releaseProxyEnabled`——关掉即全部走直连；
/// - **只有自定义通道**：用户自己填地址，填了才有加速，没填就没有；
/// - **选择一个**：`releaseProxySelectedId` 指定当前生效通道。
///
/// ## 为什么删掉内置通道（这是本次的实质变更）
/// 内置通道是**开发者自建的代理**：请求要经过一台由项目维护的服务器。
/// 无论协议怎么写得清楚，那台服务器都在信任链上 —— 它看到你请求了什么文件，
/// 也能在那张约 30 分钟的签名地址有效期内自行取走文件。
///
/// 这个项目的定位是"本地工具"：不收集数据、令牌不出设备。而"内置代理"天生
/// 与"不经过任何我方服务器"冲突。所以干脆不要它：
/// **想要加速，请自备通道** —— 那是你与第三方之间的事，不是本项目对你的
/// 暗中安排。
///
/// 连带删掉的还有**降级回退**：此前加速失败会静默改走直连（甚至多前缀逐个
/// 试）。静默降级会让人误以为加速在生效，也会让"到底走没走代理"变成一个
/// 没人说得清的问题。现在：**开着就走通道，失败就是失败**，如实报错。
///
/// ## 法律声明（必须显式同意后才可启用）
/// 通道会把"下载请求"导向**应用之外的服务器**（由用户自行指定），因此需要
/// 《外来服务自负责任协议》。协议**正文**收敛在 i18n 分片（`common` 页
/// `accelThirdPartyBody`），标题与版本号见本文件与 [kOgLAccelConsentVersion]；
/// 用户同意后记录版本号与时间，文本升版必须重新同意。
library;

import '../i18n/og_l_i18n.dart';

/// 取 `common` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'common', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 同意协议的版本号：**文本任何实质修改都必须 +1**，以便重新征求同意。
///
/// v2：内置通道换为 `proxy.344977.xyz`（地址变更属实质修改）。
/// v3：新增「加速通道属于本应用提供的网络服务」「仅支持前缀式代理」
///     「以中文文本为准」三段说明。
/// v4：**删除内置通道与降级回退**，只允许自定义通道；协议随之删去
///     「本应用提供/维护通道」的表述，并明确「失败不静默回落直连」。
///     这是使用者需要重新确认的实质变化。
const int kOgLAccelConsentVersion = 4;

/// **加速适用范围** —— 哪些资源允许走通道。
///
/// ## 为什么要有它
/// 前缀式代理（如 GHproxy 一类项目）**开放的端点有限**：它可能能转发 Release
/// 附件，却转发不了仓库文件；也可能反过来。写死"哪些资源加速"必然有一半人
/// 用不了。所以把选择权交给用户：**只在你确实需要的类别上开加速**。
///
/// ## 这份清单来自代码，不是文档
/// 全项目**只有 4 处**调用加速判定（`rg 'OgLAccelFamily\.' lib/`）：
/// - [releaseAsset]：`release_detail_page.dart` 的 Release 附件下载；
/// - [actionArtifact]：`action_run_page.dart` 的 Action 构建产物下载；
/// - [repoFile]：`surface_bridge.planRepoFileDownload`（仓库页下载 /
///   预览页「加入下载」）与 `file_preview_page.dart` 的内联 raw 取法；
/// - [readmeImage]：`repo_page.dart` 的 README 仓库内图片。
///
/// **Action 运行日志不走加速**（`ix_action_logs.dart` 直接请求
/// `api.github.com`），因此这里没有对应项 —— 不凭印象添端点。
enum OgLAccelScope {
  /// Release 附件。
  releaseAsset('releaseAsset'),

  /// Action 构建产物。
  actionArtifact('actionArtifact'),

  /// 仓库文件（下载与预览）。
  repoFile('repoFile'),

  /// README 仓库内图片。
  readmeImage('readmeImage');

  const OgLAccelScope(this.id);

  /// 稳定 id（落盘用；改名等于丢用户设置，务必保持小驼峰不变）。
  final String id;

  /// 由 id 解析；未知返回 `null`（容错，不抛）。
  static OgLAccelScope? fromId(String? id) {
    for (final OgLAccelScope scope in values) {
      if (scope.id == id) {
        return scope;
      }
    }
    return null;
  }

  /// 展示名（i18n 键在 `settings` 分片的 `accelScopeXxx`）。
  String get labelKey => 'accelScope${id[0].toUpperCase()}${id.substring(1)}';
}

/// 全部范围的 id（**默认值**：不改变既有行为，用户可逐项关掉）。
///
/// 刻意写成显式列表而不是从 `values` 派生：它是**落盘默认值**，必须稳定；
/// 新增范围时应显式加进来，并由测试保证与枚举不漂移
/// （见 `test/surface/path_rules_test.dart` 的「范围清单与枚举一致」）。
const List<String> kOgLAccelAllScopeIds = <String>[
  'releaseAsset',
  'actionArtifact',
  'repoFile',
  'readmeImage',
];

/// 一个下载加速通道（**全部由用户创建**）。
class OgLAccelChannel {
  /// 创建通道。
  const OgLAccelChannel({
    required this.id,
    required this.name,
    required this.baseUrl,
  });

  /// 唯一标识（创建时生成）。
  final String id;

  /// 展示名。
  final String name;

  /// 前缀地址（形如 `https://host:port/`，以 `/` 结尾）。
  final String baseUrl;

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

/// 某个通道对应的加速前缀（**单个**）。
///
/// 曾经这里返回的是"链"（内置多前缀按优先级逐个试）。链本身就是静默降级的
/// 一种：前一个失败就换下一个，用户无从知道走了哪条。现在一个通道就是一个
/// 前缀，没有第二个。
List<String> ogLAccelPrefixesFor(OgLAccelChannel channel) =>
    <String>[ogLNormalizeAccelBase(channel.baseUrl)];

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
  // ★ 形状必须真的是一个 URL，而不是"以 https:// 开头"就算数：
  //   旧实现只查前缀 + 结尾斜杠，`https://`（无主机）能原样通过 ——
  //   它会以空前缀参与拼接（`https://` + 原地址 = 原地址），把"加速已开"
  //   伪装成静默直连。这里用 Uri 解一次并强制要求非空 host。
  final Uri? parsed = Uri.tryParse(input);
  if (parsed == null || parsed.host.isEmpty) {
    return _t('accelUrlHost');
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

/// 加速协议正文（只有一种：外来服务自负责任）。
String ogLAccelAgreement() => _t('accelThirdPartyBody');
