/// L3 展示级 · 项目元数据（名称 / 主要开发者 / 仓库坐标 / 许可）。
///
/// ## 为什么单独成文件
/// 关于页、捐赠 star、开源许可三处都要用到同一组事实（项目名、仓库坐标、许可）。
/// 把事实收敛到一处，避免三份副本各自漂移。
///
/// ## 分层
/// 本文件属 `surface`（L3）的**纯常量**：不依赖任何运行时对象，
/// 也不引用 `base` / `domain`，可被页面与装配层安全共享。
library;

import '../i18n/og_l_i18n.dart';

/// 取 `shell` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'shell', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 项目元数据。
abstract final class OgLProjectInfo {
  /// 项目名称。
  static const String name = 'OhGithubLost';

  /// 简称。
  static const String abbreviation = 'OGL';

  /// 主要开发者。
  static const String mainDeveloper = 'OGL-Teams';

  /// 仓库所属账号。
  static const String repoOwner = 'OGL-Teams';

  /// 仓库名称。
  static const String repoName = 'OhGithubLost';

  /// 仓库全名（`owner/name`）。
  static const String repoFullName = '$repoOwner/$repoName';

  /// 仓库地址。
  static const String repositoryUrl = 'https://github.com/$repoFullName';

  /// 议题地址。
  static const String issuesUrl = '$repositoryUrl/issues';

  /// 本项目许可标识。
  static const String licenseId = 'Apache-2.0';

  /// 本项目许可名称。
  static const String licenseName = 'Apache License 2.0';

  /// 本项目许可地址。
  ///
  /// v6.4.0 前这里仍指向 `gnu.org/licenses/agpl-3.0.html` —— 常量名与
  /// `licenseId` 一起换了、值却漏改。任何一处将来用它生成「查看许可」链接，
  /// 都会把用户送到一份**与实际许可无关**的全文。许可标识、名称、地址三者
  /// 必须同时改，由新增测试锁死（见 `test/surface/license_meta_test.dart`）。
  static const String licenseUrl =
      'https://www.apache.org/licenses/LICENSE-2.0';
}

/// 第三方依赖与其许可（开源许可栏目展示用）。
///
/// 只列**运行期真正被 import 的包**（见 `pubspec.yaml` 的依赖说明）；
/// 开发期依赖（`flutter_lints` 等）不进入发布产物，因此不在此列。
class OgLDependencyLicense {
  /// 创建条目。
  const OgLDependencyLicense(this.name, this.license, this.purpose);

  /// 包名。
  final String name;

  /// 许可标识。
  final String license;

  /// 在本项目里的用途。
  final String purpose;
}

/// 第三方依赖清单：**顺序与 `pubspec.yaml` 的 `dependencies` 逐项一致**。
///
/// `flutter_localizations` 虽是 SDK 自带、不带外部版本号，但在 pubspec 中
/// 紧跟 `flutter` 排在所有外部包之前，这里同样列在首位（BSD-3-Clause，
/// 随产物分发）。
final List<OgLDependencyLicense> kOgLDependencyLicenses =
    <OgLDependencyLicense>[
  OgLDependencyLicense(
      'flutter_localizations', 'BSD-3-Clause', _t('featureLocalization')),
  OgLDependencyLicense(
      'path_provider', 'BSD-3-Clause', _t('featureCrossPlatformDirs')),
  OgLDependencyLicense(
      'flutter_secure_storage', 'MIT', _t('featureTokenVault')),
  OgLDependencyLicense('crypto', 'BSD-3-Clause', _t('featureDigest')),
  OgLDependencyLicense(
      'cryptography', 'Apache-2.0', _t('featureManifestSignature')),
  OgLDependencyLicense(
      'flutter_markdown', 'BSD-3-Clause', _t('featureMarkdown')),
  OgLDependencyLicense(
      'url_launcher', 'BSD-3-Clause', _t('featureExternalLink')),
  OgLDependencyLicense('flutter_svg', 'MIT', _t('featureSvg')),
  OgLDependencyLicense('re_editor', 'MIT', _t('featureCodeEditor')),
  OgLDependencyLicense('re_highlight', 'MIT', _t('featureHighlight')),
  OgLDependencyLicense('permission_handler', 'MIT', _t('featurePermissions')),
  OgLDependencyLicense('window_manager', 'MIT', _t('featureDesktopWindow')),
  OgLDependencyLicense('saf_util', 'BSD-3-Clause', _t('featureSafFolders')),
  OgLDependencyLicense('saf_stream', 'BSD-3-Clause', _t('featureSafCopy')),
  OgLDependencyLicense('background_downloader', 'MIT', _t('featureDownloads')),
  OgLDependencyLicense('archive', 'MIT', _t('featureActionsZip')),
  OgLDependencyLicense(
      'flutter_local_notifications', 'BSD-3-Clause', _t('featureSystemNotice')),
  OgLDependencyLicense('yaml', 'MIT', _t('featureWorkflowInputs')),
];
