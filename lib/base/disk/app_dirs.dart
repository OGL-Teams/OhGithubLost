/// L1 底座级 · 应用目录规划（**唯一**知道"ogl 放哪"的地方）。
///
/// ## 约定的目录结构
/// ```text
/// <root>/                     应用根（默认 ogl）
///   logging/                  日志落盘
///   download/                 下载根
///     release/                Release 附件
///     repo/                   仓库文件
///     gist/                   Gist 文件
///     other/                  其它
/// ```
///
/// ## 平台适配
/// - Android：优先外部可见目录 `/storage/emulated/0/ogl`（需可写）；
///   不可写时退到应用外部目录 `/storage/emulated/0/Android/data/<pkg>/files/ogl`
///   （无需权限、文件管理器可见）；再退到应用文档目录。
/// - 桌面（Windows / Linux / macOS）：文档目录下的 `ogl`。
/// - 探测方式为**真实写入探针**：能建目录并写删探针文件才算可用，不靠猜。
///
/// ## Web 适配
/// 浏览器里**没有文件系统**，也**不能调用 path_provider**：
/// - 只有**一档**：`internal` 语义，根用虚拟前缀 `web`；
/// - [OgLAppDirs.isUserVisible] 在 web 上**恒 `false`**（用户看不到应用存储）。
///
/// 真正的平台差异（文件系统探测）全部收敛到 Web 实现 `app_dirs_fs_web.dart`
/// （本分支只构建浏览器产物），本文件本身不依赖 `dart:io`。
library;

import 'package:flutter/foundation.dart';

import 'app_dirs_fs_web.dart';

/// 落盘位置分级（决定"用户能不能在文件管理器里看到"）。
enum OgLStorageTier {
  /// 系统可见的公共目录（如 `/storage/emulated/0/ogl`）——**用户看得到**。
  public,

  /// 应用外部目录（`/storage/emulated/0/Android/data/<pkg>/files/...`）：
  /// 无需权限即可写，但 Android 11+ 起多数文件管理器**看不到**。
  appExternal,

  /// 应用内部目录（`/data/user/0/<pkg>/...`）——**用户完全看不到**。
  internal,

  /// 桌面平台（文档目录，用户可见）。
  desktop,

  /// 无法判定。
  unknown,
}

/// 应用目录规划。
abstract final class OgLAppDirs {
  /// 根目录名。
  static const String folderName = 'ogl';

  /// **期望的公共根目录**（用户可见的那个）；无法确定时返回 `null`。
  ///
  /// - Android：`/storage/emulated/0/ogl`（写它需要"所有文件访问"或旧版存储权限）；
  /// - 桌面：文档目录下的 `ogl`。
  static Future<String?> publicRoot() async {
    if (kIsWeb) {
      // 浏览器没有「用户可见的公共目录」。
      return null;
    }
    return AppDirsFs.publicRoot(folderName);
  }

  /// 公共根目录当前是否**真的可写**（真实写入探针）。
  static Future<bool> publicWritable() async {
    final String? target = await publicRoot();
    if (target == null) {
      return false;
    }
    return _writable(target);
  }

  /// 落盘位置分级。
  static OgLStorageTier tierOf(String path) {
    if (kIsWeb) {
      // 浏览器只有一档：应用内部（虚拟根 `web`），且用户看不到。
      return OgLStorageTier.internal;
    }
    final String p = path.replaceAll(r'\', '/');
    if (p.contains('/Android/data/') || p.contains('/Android/obb/')) {
      return OgLStorageTier.appExternal;
    }
    if (p.startsWith('/data/') || p.contains('/data/user/')) {
      return OgLStorageTier.internal;
    }
    if (p.startsWith('/storage/emulated/')) {
      return OgLStorageTier.public;
    }
    if (p.startsWith('/storage/')) {
      // 其它挂载点（可移动存储等）：不经应用私有目录，视为可见。
      return OgLStorageTier.public;
    }
    // 桌面平台用 `defaultTargetPlatform` 判定（不引入 dart:io 的 Platform）。
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return OgLStorageTier.desktop;
    }
    return OgLStorageTier.unknown;
  }

  /// 该路径是否**用户可见**（能靠文件管理器 / 电脑找到）。
  ///
  /// 注意：应用外部目录（`Android/data/...`）**不算可见**——Android 11+
  /// 起系统会隐藏它，用户实际上找不到。
  static bool isUserVisible(String path) {
    final OgLStorageTier tier = tierOf(path);
    return tier == OgLStorageTier.public || tier == OgLStorageTier.desktop;
  }

  /// 当前落盘位置摘要（路径 + 分级 + 是否可见）。
  static Future<({String path, OgLStorageTier tier, bool visible})>
      location() async {
    final String path = await root();
    final OgLStorageTier tier = tierOf(path);
    return (
      path: path,
      tier: tier,
      visible: tier == OgLStorageTier.public || tier == OgLStorageTier.desktop,
    );
  }

  /// **使根目录缓存失效**（权限变化后必须调用，否则会一直卡在旧位置）。
  static void invalidate() {
    _rootCache = null;
  }

  /// 解析应用根目录（结果按进程缓存：一次探测，后续复用）。
  static Future<String> root() async {
    final String? cached = _rootCache;
    if (cached != null) {
      return cached;
    }
    final String resolved = await _resolveRoot();
    _rootCache = resolved;
    return resolved;
  }

  static String? _rootCache;

  /// 日志目录。
  static Future<String> logging() async => '${await root()}/logging';

  /// 下载根目录。
  static Future<String> downloads() async => '${await root()}/download';

  /// 下载分类的子目录名（`<下载根>/<分类>/`）。
  ///
  /// ## 这是**分类 → 目录名**的唯一映射
  /// 下载器内部走的是 `IxDownloadCategory.folder`（中枢层），两者必须**逐项一致**。
  /// 因为底座不能反向依赖中枢（`layer_audit` 会拦），这里以字符串入参独立维护，
  /// 再由 `test/base/app_dirs_category_test.dart` 把两边**逐个枚举比对** ——
  /// 新增分类时漏改任一侧，测试立刻失败。
  ///
  /// ⚠️ 历史上这里漏过 `artifact`（Action 构建产物），会**静默落到 `other/`**。
  static String categoryFolder(String category) {
    switch (category) {
      case 'release':
        return 'release';
      case 'repo':
        return 'repo';
      case 'gist':
        return 'gist';
      case 'artifact':
        return 'artifact';
      default:
        return 'other';
    }
  }

  static Future<String> _resolveRoot() async {
    // Web：一档虚拟根 `web`（`app_dirs_fs_web.dart` 里解析，不碰 path_provider）。
    return AppDirsFs.resolveRoot(folderName);
  }

  /// 真实写入探针：能建目录、能写入并删除探针文件，才算可写。
  ///
  /// Web 端恒 `false`（浏览器沙箱里没有可写的"用户可见目录"）。
  static Future<bool> _writable(String dir) => AppDirsFs.writable(dir);
}
