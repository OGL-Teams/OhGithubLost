/// 发布信任根（Release Trust Root）：内嵌 Ed25519 公钥。
///
/// 信任模型：
/// - CI 构建时用对应**私钥**给引导清单（Boot Manifest）签名；
/// - 应用启动时用这里的**公钥**校验签名；签名不符 → 拒绝启动；
/// - 私钥**不再随仓库保管**：存放于 GitHub Actions Secret（`OGL_BOOT_KEY`），
///   由构建流程在 CI 内临时还原使用（轮换记录见 `.github/signing/README.md`）；
/// - **密钥版本：v2（2026-10-02 全量轮换）**。历史版本各自内嵌各自的清单与公钥，
///   不受影响；外部签名物（如 Mod 清单）需用 v2 重签后才能在 1.1+ 上通过校验。
///
/// 防脱节：`test/kernel/boot_release_chain_test.dart` 用**固定签名样本**
/// （`test/kernel/fixtures/release_key_signed_manifest.json`，由发布私钥签出）
/// 验证「内嵌公钥可验发布签名」，任何一边被改动都会红。
library;

/// 32 字节 Ed25519 公钥原始字节（v2）。
///
/// base64：`Qaojo9YuV4nQoNbyfDiwoYofhUg/sPrKhOkDyW5DQ8s=`
const List<int> kOgLReleasePublicKey = <int>[
  65,
  170,
  35,
  163,
  214,
  46,
  87,
  137,
  208,
  160,
  214,
  242,
  124,
  56,
  176,
  161,
  138,
  31,
  133,
  72,
  63,
  176,
  250,
  202,
  132,
  233,
  3,
  201,
  110,
  67,
  67,
  203,
];

/// 公钥的 base64 形式（日志与文档展示用）。
const String kOgLReleasePublicKeyBase64 =
    'Qaojo9YuV4nQoNbyfDiwoYofhUg/sPrKhOkDyW5DQ8s=';
