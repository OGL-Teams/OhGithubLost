/// 启动层信任策略：谁必须过校验，谁放开，谁告警。
///
/// 产品默认策略（与 `docs/BOOT.md（该文件未落地，以源码为准）` 保持一致，调整必须走 ADR）：
///
/// | 扩展种类 | 级别 | 签名要求 | 放行 | 总线告警 | 用户确认 |
/// |---|---|---|---|---|---|
/// | 官方核心模块 | locked | 是 | 是 | 否 | 否 |
/// | 官方扩展 | verified | 是 | 是 | 否 | 否 |
/// | 第三方主题 | open | 否 | 是 | 否 | 否 |
/// | 第三方 Mod | warn | 否 | 是 | **是** | 否（danger 级告警时由调用方升级为确认） |
library;

/// 扩展种类。
enum ExtensionKind {
  /// 官方核心模块（kernel/base/domain/surface 内置，受 BL 锁保护）。
  officialCore,

  /// 官方扩展（官方发布的 Mod / 主题包）。
  officialExtension,

  /// 第三方主题包（**信任不设限**：仅做 schema 白名单解析校验）。
  thirdPartyTheme,

  /// 第三方 Mod 包（**放行 + 总线告警**）。
  thirdPartyMod,
}

/// 信任级别。
enum TrustTier {
  /// 锁定：必须通过签名与指纹校验，否则拒绝装载。
  locked,

  /// 已验证：必须与清单指纹一致。
  verified,

  /// 告警：允许装载，但必须产生信任告警。
  warn,

  /// 开放：不设信任限制（仍受 schema 白名单约束）。
  open,
}

/// 策略裁决结果。
class TrustDecision {
  /// 创建裁决。
  const TrustDecision({
    required this.kind,
    required this.tier,
    required this.requireSignature,
    required this.allowLoad,
    required this.mustWarnBus,
    required this.requiresUserConsent,
    required this.rationale,
  });

  /// 被裁决的扩展种类。
  final ExtensionKind kind;

  /// 信任级别。
  final TrustTier tier;

  /// 是否要求签名 / 指纹校验。
  final bool requireSignature;

  /// 是否允许装载。
  final bool allowLoad;

  /// 是否必须产生总线告警。
  final bool mustWarnBus;

  /// 是否必须获得用户显式确认后才可继续。
  final bool requiresUserConsent;

  /// 裁决依据（进入日志与 UI 说明）。
  final String rationale;

  @override
  String toString() =>
      'TrustDecision(${kind.name}: tier=${tier.name}, load=$allowLoad, '
      'signature=$requireSignature, warn=$mustWarnBus, consent=$requiresUserConsent)';
}

/// 启动层信任策略。
class BootTrustPolicy {
  /// 创建策略（默认值即产品策略）。
  const BootTrustPolicy();

  /// 对指定扩展种类作出裁决。
  TrustDecision evaluate(ExtensionKind kind) {
    switch (kind) {
      case ExtensionKind.officialCore:
        return TrustDecision(
          kind: kind,
          tier: TrustTier.locked,
          requireSignature: true,
          allowLoad: true,
          mustWarnBus: false,
          requiresUserConsent: false,
          rationale: '官方核心模块：必须通过引导清单签名与目录指纹校验（BL 锁）',
        );
      case ExtensionKind.officialExtension:
        return TrustDecision(
          kind: kind,
          tier: TrustTier.verified,
          requireSignature: true,
          allowLoad: true,
          mustWarnBus: false,
          requiresUserConsent: false,
          rationale: '官方扩展：必须与引导清单指纹一致',
        );
      case ExtensionKind.thirdPartyTheme:
        return TrustDecision(
          kind: kind,
          tier: TrustTier.open,
          requireSignature: false,
          allowLoad: true,
          mustWarnBus: false,
          requiresUserConsent: false,
          rationale: '第三方主题：信任不设限（声明式数据 + schema 白名单解析）',
        );
      case ExtensionKind.thirdPartyMod:
        return TrustDecision(
          kind: kind,
          tier: TrustTier.warn,
          requireSignature: false,
          allowLoad: true,
          mustWarnBus: true,
          requiresUserConsent: false,
          rationale: '第三方 Mod：允许装载，但必须向总线发出告警并通知用户',
        );
    }
  }

  /// 是否需要为指定种类产生总线告警。
  bool shouldWarn(ExtensionKind kind) => evaluate(kind).mustWarnBus;
}
