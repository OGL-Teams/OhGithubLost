/// L2 中枢级 · API 逻辑：GitHub 领域模型。
///
/// ## 三条解析铁律（对应 STANDARDS 的"容错解析"）
/// 1. **缺字段给默认值**：服务端少给一个字段，不能让我们崩；
/// 2. **未知字段保留**：GitHub 随时加字段，我们把整个原始 JSON 留在
///    [GhRecord.raw] 里——将来要用直接取，不用改模型；
/// 3. **类型不对不硬转**：`"3"` 与 `3` 都接受，`null` 与缺失等价。
///
/// ## 为什么模型要带 `raw`
/// Mod 包 / 高级用户常常需要 GitHub 原始字段（我们没建模的那些）。
/// 保留 `raw` 等于**免迁移地支持未来字段**，代价只是一份 Map。
library;

import 'dart:convert';

/// 容错 JSON 读取。
class GhJson {
  const GhJson._();

  /// 读字符串。
  static String str(
    Map<String, dynamic> json,
    String key, {
    String fallback = '',
  }) {
    final value = json[key];
    return value is String ? value : fallback;
  }

  /// 读可空字符串（空串视为缺失）。
  static String? strOrNull(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// 读整数（`"3"` 与 `3` 都接受）。
  static int integer(
    Map<String, dynamic> json,
    String key, {
    int fallback = 0,
  }) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  /// 读布尔（`1` / `"true"` 都接受）。
  static bool boolean(
    Map<String, dynamic> json,
    String key, {
    bool fallback = false,
  }) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.toLowerCase() == 'true';
    }
    return fallback;
  }

  /// 读时间（ISO 8601；解析失败返回 `null`）。
  static DateTime? date(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  /// 读对象列表（自动跳过非对象元素）。
  static List<Map<String, dynamic>> objects(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// 读字符串列表。
  static List<String> strings(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList();
  }
}

/// 所有领域模型的公共契约。
abstract class GhRecord {
  /// 创建记录。
  ///
  /// 提供 `const` 构造，使各子类保持 `const` 构造能力
  /// （模型在测试与常量场景下会被大量以 `const` 使用）。
  const GhRecord();

  /// 原始 JSON（未知字段保留在此，供 Mod / 高级用户读取）。
  Map<String, dynamic> get raw;

  /// 序列化（不含 [raw]，避免持久化体积失控）。
  Map<String, Object?> toJson();

  /// 带 raw 的完整导出（调试 / Mod 用）。
  Map<String, Object?> toJsonWithRaw() => <String, Object?>{
        ...toJson(),
        'raw': raw,
      };
}

/// 用户 / 组织。
class GhUser extends GhRecord {
  /// 创建用户。
  const GhUser({
    required this.login,
    required this.id,
    this.name,
    this.avatarUrl,
    this.htmlUrl,
    this.type = 'User',
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhUser.fromJson(Map<String, dynamic> json) => GhUser(
        login: GhJson.str(json, 'login'),
        id: GhJson.integer(json, 'id'),
        name: GhJson.strOrNull(json, 'name'),
        avatarUrl: GhJson.strOrNull(json, 'avatar_url'),
        htmlUrl: GhJson.strOrNull(json, 'html_url'),
        type: GhJson.str(json, 'type', fallback: 'User'),
        raw: json,
      );

  /// 登录名。
  final String login;

  /// 数字 ID。
  final int id;

  /// 昵称。
  final String? name;

  /// 头像。
  final String? avatarUrl;

  /// 主页。
  final String? htmlUrl;

  /// 类型（`User` / `Organization` / `Bot`）。
  final String type;

  @override
  final Map<String, dynamic> raw;

  /// 是否组织。
  bool get isOrganization => type == 'Organization';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'login': login,
        'id': id,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (htmlUrl != null) 'htmlUrl': htmlUrl,
        'type': type,
      };

  @override
  String toString() => 'GhUser($login)';
}

/// 仓库。
class GhRepo extends GhRecord {
  /// 创建仓库。
  const GhRepo({
    required this.fullName,
    required this.owner,
    required this.name,
    this.isPrivate = false,
    this.description,
    this.defaultBranch = '',
    this.stars = 0,
    this.forks = 0,
    this.watchers = 0,
    this.openIssues = 0,
    this.language,
    this.sizeKb = 0,
    this.updatedAt,
    this.isFork = false,
    this.isArchived = false,
    this.htmlUrl,
    this.hasPages = false,
    this.canPush,
    this.canAdmin,
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhRepo.fromJson(Map<String, dynamic> json) {
    final ownerJson = json['owner'];
    final owner = ownerJson is Map<Object?, Object?>
        ? Map<String, dynamic>.from(ownerJson)
        : const <String, dynamic>{};
    // `permissions` 仅在"已认证 + 对该仓库有权限"时才由 GitHub 返回。
    // 缺失（游客 / 列表接口）⇒ 两个字段保持 null，调用方按**不可写**处理。
    final Object? permissionsJson = json['permissions'];
    final Map<String, dynamic> permissions =
        permissionsJson is Map<Object?, Object?>
            ? Map<String, dynamic>.from(permissionsJson)
            : const <String, dynamic>{};
    final bool? canPush =
        permissions.isEmpty ? null : GhJson.boolean(permissions, 'push');
    final bool? canAdmin =
        permissions.isEmpty ? null : GhJson.boolean(permissions, 'admin');
    return GhRepo(
      fullName: GhJson.str(json, 'full_name'),
      owner: GhUser.fromJson(owner),
      name: GhJson.str(json, 'name'),
      isPrivate: GhJson.boolean(json, 'private'),
      description: GhJson.strOrNull(json, 'description'),
      // 列表接口有时不返回 default_branch；**不猜**（猜错会让目录/提交标签 404），
      // 留空由调用方用 `GET /repos/{full}` 兜底。
      defaultBranch: GhJson.str(json, 'default_branch'),
      stars: GhJson.integer(json, 'stargazers_count'),
      forks: GhJson.integer(json, 'forks_count'),
      watchers: GhJson.integer(json, 'watchers_count'),
      openIssues: GhJson.integer(json, 'open_issues_count'),
      language: GhJson.strOrNull(json, 'language'),
      sizeKb: GhJson.integer(json, 'size'),
      updatedAt: GhJson.date(json, 'updated_at'),
      isFork: GhJson.boolean(json, 'fork'),
      isArchived: GhJson.boolean(json, 'archived'),
      htmlUrl: GhJson.strOrNull(json, 'html_url'),
      hasPages: GhJson.boolean(json, 'has_pages'),
      canPush: canPush,
      canAdmin: canAdmin,
      raw: json,
    );
  }

  /// `owner/name`。
  final String fullName;

  /// 拥有者。
  final GhUser owner;

  /// 仓库名。
  final String name;

  /// 是否私有。
  final bool isPrivate;

  /// 描述。
  final String? description;

  /// 默认分支。
  final String defaultBranch;

  /// 星标数。
  final int stars;

  /// 复刻数。
  final int forks;

  /// 关注数。
  final int watchers;

  /// 开放议题数。
  final int openIssues;

  /// 主语言。
  final String? language;

  /// 体积（KB）。
  final int sizeKb;

  /// 更新时间。
  final DateTime? updatedAt;

  /// 是否复刻。
  final bool isFork;

  /// 是否归档。
  final bool isArchived;

  /// 网页地址。
  final String? htmlUrl;

  /// 是否启用了 Pages。
  final bool hasPages;

  /// 当前登录用户对该仓库是否有 **push（写）** 权限。
  ///
  /// `null` = GitHub 未返回 `permissions`（游客 / 列表接口）⇒ 按不可写处理。
  final bool? canPush;

  /// 当前登录用户对该仓库是否有 **admin** 权限。
  final bool? canAdmin;

  /// 是否可写（[canPush] 为真的**唯一**判据；不做任何降级猜测）。
  bool get isWritable => canPush == true;

  @override
  final Map<String, dynamic> raw;

  /// `owner` 登录名。
  String get ownerLogin => owner.login;

  /// 能否发布为主站（必须是 `用户名.github.io`）。
  bool get canBeMainSite =>
      name.toLowerCase() == '${owner.login.toLowerCase()}.github.io';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'fullName': fullName,
        'owner': owner.toJson(),
        'name': name,
        'isPrivate': isPrivate,
        if (description != null) 'description': description,
        'defaultBranch': defaultBranch,
        'stars': stars,
        'forks': forks,
        'watchers': watchers,
        'openIssues': openIssues,
        if (language != null) 'language': language,
        'sizeKb': sizeKb,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        'isFork': isFork,
        'isArchived': isArchived,
        if (htmlUrl != null) 'htmlUrl': htmlUrl,
        'hasPages': hasPages,
        if (canPush != null) 'canPush': canPush,
        if (canAdmin != null) 'canAdmin': canAdmin,
      };

  @override
  String toString() =>
      'GhRepo($fullName, branch=$defaultBranch, private=$isPrivate)';
}

/// 分支。
class GhBranch extends GhRecord {
  /// 创建分支。
  const GhBranch({
    required this.name,
    required this.sha,
    this.isProtected = false,
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhBranch.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'];
    final commitJson = commit is Map<Object?, Object?>
        ? Map<String, dynamic>.from(commit)
        : const <String, dynamic>{};
    return GhBranch(
      name: GhJson.str(json, 'name'),
      sha: GhJson.str(commitJson, 'sha'),
      isProtected: GhJson.boolean(json, 'protected'),
      raw: json,
    );
  }

  /// 分支名。
  final String name;

  /// 顶端提交。
  final String sha;

  /// 是否受保护。
  final bool isProtected;

  @override
  final Map<String, dynamic> raw;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'sha': sha,
        'isProtected': isProtected,
      };

  @override
  String toString() =>
      'GhBranch($name@${sha.isEmpty ? '?' : sha.substring(0, 7)})';
}

/// 树节点类型。
enum GhTreeEntryType {
  /// 文件。
  blob,

  /// 目录。
  tree,

  /// 子模块。
  commit,

  /// 未知（服务端新增类型时保留原样，不崩）。
  unknown;

  /// 由字符串解析。
  static GhTreeEntryType parse(String raw) {
    for (final value in GhTreeEntryType.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return GhTreeEntryType.unknown;
  }
}

/// 目录树节点。
class GhTreeEntry extends GhRecord {
  /// 创建节点。
  const GhTreeEntry({
    required this.path,
    required this.type,
    required this.sha,
    this.size = 0,
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhTreeEntry.fromJson(Map<String, dynamic> json) => GhTreeEntry(
        path: GhJson.str(json, 'path'),
        type: GhTreeEntryType.parse(GhJson.str(json, 'type')),
        sha: GhJson.str(json, 'sha'),
        size: GhJson.integer(json, 'size'),
        raw: json,
      );

  /// 仓库内完整路径。
  final String path;

  /// 类型。
  final GhTreeEntryType type;

  /// 内容指纹。
  final String sha;

  /// 字节数（目录为 0）。
  final int size;

  @override
  final Map<String, dynamic> raw;

  /// 是否文件。
  bool get isFile => type == GhTreeEntryType.blob;

  /// 是否目录。
  bool get isDirectory => type == GhTreeEntryType.tree;

  /// 文件名（末段）。
  String get name {
    final index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }

  /// 父目录（根目录返回空串）。
  String get parentPath {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'type': type.name,
        'sha': sha,
        'size': size,
      };

  @override
  String toString() => 'GhTreeEntry(${type.name} $path)';
}

/// 目录树。
///
/// **[truncated] 是一等公民**：GitHub 对大仓库会在 7 MB / 10 万条处截断，
/// 且**不会报错**——不处理它就会静默少文件。上层必须据此决定
/// "改用逐层懒加载"或"提示用户范围过大"。
class GhTree extends GhRecord {
  /// 创建树。
  const GhTree({
    required this.sha,
    required this.entries,
    this.truncated = false,
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhTree.fromJson(Map<String, dynamic> json) => GhTree(
        sha: GhJson.str(json, 'sha'),
        truncated: GhJson.boolean(json, 'truncated'),
        entries:
            GhJson.objects(json, 'tree').map(GhTreeEntry.fromJson).toList(),
        raw: json,
      );

  /// 树指纹。
  final String sha;

  /// 节点列表。
  final List<GhTreeEntry> entries;

  /// **是否被服务端截断**（为真时 [entries] 不完整）。
  final bool truncated;

  @override
  final Map<String, dynamic> raw;

  /// 文件列表。
  List<GhTreeEntry> get files =>
      entries.where((GhTreeEntry entry) => entry.isFile).toList();

  /// 目录列表。
  List<GhTreeEntry> get directories =>
      entries.where((GhTreeEntry entry) => entry.isDirectory).toList();

  /// 某目录下的一级子项。
  List<GhTreeEntry> childrenOf(String directory) {
    final prefix = directory.isEmpty ? '' : '$directory/';
    return entries
        .where((GhTreeEntry entry) =>
            entry.path.startsWith(prefix) &&
            !entry.path.substring(prefix.length).contains('/'))
        .toList();
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'sha': sha,
        'truncated': truncated,
        'entries': entries.map((GhTreeEntry entry) => entry.toJson()).toList(),
      };

  @override
  String toString() =>
      'GhTree(${entries.length} entries${truncated ? ', TRUNCATED' : ''})';
}

/// 内容条目（Contents API 的返回，可能是文件或目录）。
class GhContent extends GhRecord {
  /// 创建内容。
  const GhContent({
    required this.path,
    required this.sha,
    this.size = 0,
    this.text,
    this.isDirectory = false,
    this.downloadUrl,
    this.htmlUrl,
    this.isTooLarge = false,
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  ///
  /// 注意：Contents API 对 **>1 MB 的文件**会返回 `content: ""` ——
  /// 这里把它识别为 [isTooLarge]，上层必须改走 Blobs API，
  /// 否则会"静默拿到空内容"。
  factory GhContent.fromJson(Map<String, dynamic> json) {
    final type = GhJson.str(json, 'type');
    final encoding = GhJson.str(json, 'encoding');
    final encoded = GhJson.str(json, 'content');
    final size = GhJson.integer(json, 'size');
    final isDirectory = type == 'dir';
    final hasBody = encoded.isNotEmpty;
    // ★ 空文件（content=="" 且 size==0）是**真实存在**的文件：内容是
    //   空串而不是"未知"。text 仍用 null 表示"没拿到"，但空文件要有
    //   sha 且 size==0 的事实留给 read() 区分——否则写链路把它当
    //   "远端不存在"，空文件的合法保存会走错分支（历史 P0）。
    return GhContent(
      path: GhJson.str(json, 'path'),
      sha: GhJson.str(json, 'sha'),
      size: size,
      text: hasBody
          ? GhContent.decodeContent(encoded, encoding)
          : (!isDirectory && size == 0 ? '' : null),
      isDirectory: isDirectory,
      downloadUrl: GhJson.strOrNull(json, 'download_url'),
      htmlUrl: GhJson.strOrNull(json, 'html_url'),
      // 非目录、体积不小、却没有内容 → 被 Contents API 省略，必须走 Blobs API。
      isTooLarge: !isDirectory && !hasBody && size > 0,
      raw: json,
    );
  }

  /// 仓库内路径。
  final String path;

  /// 内容指纹（写入时作为乐观锁的基线）。
  final String sha;

  /// 字节数。
  final int size;

  /// 文本内容（目录或过大时为 `null`）。
  final String? text;

  /// 是否目录。
  final bool isDirectory;

  /// 原始下载地址。
  final String? downloadUrl;

  /// 网页地址。
  final String? htmlUrl;

  /// **内容被服务端省略**（>1 MB），需要改走 Blobs API。
  final bool isTooLarge;

  @override
  final Map<String, dynamic> raw;

  /// 解码 base64 内容（容错：非法 base64 返回 `null` 而不是抛）。
  static String? decodeContent(String encoded, String encoding) {
    if (encoded.isEmpty) {
      return null;
    }
    if (encoding.isNotEmpty && encoding != 'base64') {
      return null;
    }
    final normalized = encoded.replaceAll('\n', '').replaceAll('\r', '');
    try {
      // ★ 必须是 UTF-8 解码：`String.fromCharCodes` 会把多字节字符拆成乱码，
      //   中文 / emoji 文件内容全毁——曾因此出现“解码错误”。
      return utf8.decode(base64Decode(normalized), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'sha': sha,
        'size': size,
        if (text != null) 'text': text,
        'isDirectory': isDirectory,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        'isTooLarge': isTooLarge,
      };

  @override
  String toString() => 'GhContent($path, ${isDirectory ? 'dir' : '${size}B'}'
      '${isTooLarge ? ', TOO LARGE' : ''})';
}

/// 发布版本。
class GhRelease extends GhRecord {
  /// 创建发布。
  const GhRelease({
    required this.id,
    required this.tagName,
    this.name,
    this.body,
    this.isDraft = false,
    this.isPrerelease = false,
    this.createdAt,
    this.publishedAt,
    this.assets = const <GhAsset>[],
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhRelease.fromJson(Map<String, dynamic> json) => GhRelease(
        id: GhJson.integer(json, 'id'),
        tagName: GhJson.str(json, 'tag_name'),
        name: GhJson.strOrNull(json, 'name'),
        body: GhJson.strOrNull(json, 'body'),
        isDraft: GhJson.boolean(json, 'draft'),
        isPrerelease: GhJson.boolean(json, 'prerelease'),
        createdAt: GhJson.date(json, 'created_at'),
        publishedAt: GhJson.date(json, 'published_at'),
        assets: GhJson.objects(json, 'assets').map(GhAsset.fromJson).toList(),
        raw: json,
      );

  /// ID。
  final int id;

  /// 标签名。
  final String tagName;

  /// 标题。
  final String? name;

  /// 说明正文。
  final String? body;

  /// 草稿。
  final bool isDraft;

  /// 预发布。
  final bool isPrerelease;

  /// 创建时间。
  final DateTime? createdAt;

  /// 发布时间。
  final DateTime? publishedAt;

  /// 附件。
  final List<GhAsset> assets;

  @override
  final Map<String, dynamic> raw;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'tagName': tagName,
        if (name != null) 'name': name,
        if (body != null) 'body': body,
        'isDraft': isDraft,
        'isPrerelease': isPrerelease,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        'assets': assets.map((GhAsset asset) => asset.toJson()).toList(),
      };

  @override
  String toString() =>
      'GhRelease($tagName${isPrerelease ? ', pre' : ''}, ${assets.length} assets)';
}

/// 发布附件。
class GhAsset extends GhRecord {
  /// 创建附件。
  const GhAsset({
    required this.id,
    required this.name,
    this.size = 0,
    this.contentType,
    this.downloadUrl,
    this.downloadCount = 0,
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhAsset.fromJson(Map<String, dynamic> json) => GhAsset(
        id: GhJson.integer(json, 'id'),
        name: GhJson.str(json, 'name'),
        size: GhJson.integer(json, 'size'),
        contentType: GhJson.strOrNull(json, 'content_type'),
        downloadUrl: GhJson.strOrNull(json, 'browser_download_url'),
        downloadCount: GhJson.integer(json, 'download_count'),
        raw: json,
      );

  /// ID。
  final int id;

  /// 文件名。
  final String name;

  /// 字节数。
  final int size;

  /// MIME。
  final String? contentType;

  /// 下载地址。
  final String? downloadUrl;

  /// 下载次数。
  final int downloadCount;

  @override
  final Map<String, dynamic> raw;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'size': size,
        if (contentType != null) 'contentType': contentType,
        if (downloadUrl != null) 'downloadUrl': downloadUrl,
        'downloadCount': downloadCount,
      };

  @override
  String toString() => 'GhAsset($name, ${size}B)';
}

/// 提交。
class GhCommit extends GhRecord {
  /// 创建提交。
  const GhCommit({
    required this.sha,
    this.message = '',
    this.authorName,
    this.authorLogin,
    this.date,
    this.parentShas = const <String>[],
    this.raw = const <String, dynamic>{},
  });

  /// 由 JSON 构造。
  factory GhCommit.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'];
    final commitJson = commit is Map<Object?, Object?>
        ? Map<String, dynamic>.from(commit)
        : const <String, dynamic>{};
    final author = commitJson['author'];
    final authorJson = author is Map<Object?, Object?>
        ? Map<String, dynamic>.from(author)
        : const <String, dynamic>{};
    final user = json['author'];
    final userJson = user is Map<Object?, Object?>
        ? Map<String, dynamic>.from(user)
        : const <String, dynamic>{};
    return GhCommit(
      sha: GhJson.str(json, 'sha'),
      message: GhJson.str(commitJson, 'message'),
      authorName: GhJson.strOrNull(authorJson, 'name'),
      authorLogin: GhJson.strOrNull(userJson, 'login'),
      date: GhJson.date(authorJson, 'date'),
      parentShas: GhJson.objects(json, 'parents')
          .map((Map<String, dynamic> parent) => GhJson.str(parent, 'sha'))
          .toList(),
      raw: json,
    );
  }

  /// 提交指纹。
  final String sha;

  /// 提交信息。
  final String message;

  /// 作者名。
  final String? authorName;

  /// 作者登录名。
  final String? authorLogin;

  /// 提交时间。
  final DateTime? date;

  /// 父提交。
  final List<String> parentShas;

  @override
  final Map<String, dynamic> raw;

  /// 首行信息。
  String get subject {
    final index = message.indexOf('\n');
    return index < 0 ? message : message.substring(0, index);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'sha': sha,
        'message': message,
        if (authorName != null) 'authorName': authorName,
        if (authorLogin != null) 'authorLogin': authorLogin,
        if (date != null) 'date': date!.toIso8601String(),
        'parentShas': parentShas,
      };

  @override
  String toString() =>
      'GhCommit(${sha.isEmpty ? '?' : sha.substring(0, 7)} $subject)';
}

/// 分页信息（从 `Link` 头解析）。
class GhPage {
  /// 创建分页。
  const GhPage({
    this.next,
    this.prev,
    this.last,
    this.first,
  });

  /// 下一页 URL。
  final String? next;

  /// 上一页 URL。
  final String? prev;

  /// 最后一页 URL。
  final String? last;

  /// 第一页 URL。
  final String? first;

  /// 是否有下一页。
  bool get hasNext => next != null;

  /// 从 `Link` 头解析。
  ///
  /// 形如：`<https://api.github.com/...&page=2>; rel="next", <...>; rel="last"`
  static GhPage parse(String? linkHeader) {
    if (linkHeader == null || linkHeader.isEmpty) {
      return const GhPage();
    }
    String? next;
    String? prev;
    String? last;
    String? first;
    for (final part in linkHeader.split(',')) {
      final segments = part.split(';');
      if (segments.length < 2) {
        continue;
      }
      final url = segments.first.trim();
      if (!url.startsWith('<') || !url.endsWith('>')) {
        continue;
      }
      final target = url.substring(1, url.length - 1);
      for (final segment in segments.skip(1)) {
        final trimmed = segment.trim();
        // 容忍 `rel="next"` 与 `rel = "next"` 两种写法（不同网关行为不一致）。
        final equals = trimmed.indexOf('=');
        if (equals <= 0) {
          continue;
        }
        if (trimmed.substring(0, equals).trim() != 'rel') {
          continue;
        }
        final rel = trimmed.substring(equals + 1).replaceAll('"', '').trim();
        // 刻意用 if/else 而非 switch：break 语义在 Dart 各版本间有过变化，
        // 这里不需要任何"贯穿"行为，写成条件链最不容易出错。
        if (rel == 'next') {
          next = target;
        } else if (rel == 'prev') {
          prev = target;
        } else if (rel == 'last') {
          last = target;
        } else if (rel == 'first') {
          first = target;
        }
      }
    }
    return GhPage(next: next, prev: prev, last: last, first: first);
  }

  /// 从 URL 提取页码（用于"当前第几页"）。
  static int? pageOf(String? url) {
    if (url == null) {
      return null;
    }
    final match = RegExp(r'[?&]page=(\d+)').firstMatch(url);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  @override
  String toString() =>
      'GhPage(next=${next == null ? '-' : 'yes'}, prev=${prev == null ? '-' : 'yes'})';
}
