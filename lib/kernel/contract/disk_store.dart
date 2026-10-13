/// L1 底座级 · 硬盘逻辑：存储原语（KV / 保险库 / 文件）。
///
/// 每个原语都是**接口 + 内存实现**两步走：
/// - 接口：定义"硬盘逻辑层承诺的能力"；
/// - 内存实现：让上层的缓存一致性引擎可以在 CI 上**完全离线**地被断言。
///
/// 真实平台实现（Android 私有目录 / Windows AppData / Linux XDG）
/// 在 `platform_io.dart` 中通过同一接口接入，不改动上层一行代码。
library;

/// 键值存储。
abstract class DiskKv {
  /// 读取；不存在返回 `null`。
  Future<String?> read(String key);

  /// 写入（覆盖）。
  Future<void> write(String key, String value);

  /// 删除（不存在时静默）。
  Future<void> remove(String key);

  /// 是否存在。
  Future<bool> has(String key);

  /// 全部键。
  Future<List<String>> keys();
}

/// 安全保险库（令牌等敏感数据；真实实现走 Keystore / DPAPI / libsecret）。
abstract class DiskVault {
  /// 读取密文（明文返回给调用方；仅限内存持有）。
  Future<String?> readSecret(String key);

  /// 写入密文。
  Future<void> writeSecret(String key, String value);

  /// 删除密文。
  Future<void> deleteSecret(String key);
}

/// 文件存储（以 UTF-8 文本为最小单位；二进制由上层以 base64 承载）。
abstract class DiskFileStore {
  /// 读取文本；不存在返回 `null`。
  Future<String?> readText(String path);

  /// 写入文本。
  Future<void> writeText(String path, String content);

  /// 删除文件（不存在时静默）。
  Future<void> delete(String path);

  /// 是否存在。
  Future<bool> exists(String path);

  /// 列出目录下的一级条目名（已排序）。
  Future<List<String>> list(String directory);
}

/// 内存 KV（测试 / 降级运行）。
class InMemoryKv implements DiskKv {
  final Map<String, String> _data = <String, String>{};

  /// 内容快照（测试断言用）。
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<bool> has(String key) async => _data.containsKey(key);

  @override
  Future<List<String>> keys() async => _data.keys.toList()..sort();
}

/// 内存保险库。
class InMemoryVault implements DiskVault {
  final Map<String, String> _secrets = <String, String>{};

  /// 密文快照。
  Map<String, String> get snapshot =>
      Map<String, String>.unmodifiable(_secrets);

  @override
  Future<String?> readSecret(String key) async => _secrets[key];

  @override
  Future<void> writeSecret(String key, String value) async {
    _secrets[key] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    _secrets.remove(key);
  }
}

/// 内存文件存储。
class InMemoryFileStore implements DiskFileStore {
  final Map<String, String> _files = <String, String>{};

  /// 文件快照。
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_files);

  /// 归一化路径（统一分隔符、去掉前导 `./` 与 `/`）。
  static String normalize(String path) {
    var value = path.replaceAll(r'\', '/');
    while (value.startsWith('./')) {
      value = value.substring(2);
    }
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    return value;
  }

  @override
  Future<String?> readText(String path) async => _files[normalize(path)];

  @override
  Future<void> writeText(String path, String content) async {
    _files[normalize(path)] = content;
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(normalize(path));
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(normalize(path));

  @override
  Future<List<String>> list(String directory) async {
    final prefix = normalize(directory);
    final scope = prefix.isEmpty ? '' : '$prefix/';
    final names = <String>{};
    for (final key in _files.keys) {
      if (!key.startsWith(scope)) {
        continue;
      }
      final rest = key.substring(scope.length);
      if (rest.isEmpty) {
        continue;
      }
      names.add(
          rest.contains('/') ? rest.substring(0, rest.indexOf('/')) : rest);
    }
    return names.toList()..sort();
  }
}

/// 路径规划抽象（各平台私有目录由平台实现决定）。
abstract class DiskPaths {
  /// 缓存根目录。
  Future<String> cacheRoot();

  /// 配置根目录。
  Future<String> configRoot();

  /// 日志根目录。
  Future<String> logRoot();
}

/// 内存路径规划（测试 / 预览）。
class InMemoryPaths implements DiskPaths {
  /// 创建路径规划。
  const InMemoryPaths({this.root = '/ogl'});

  /// 根路径。
  final String root;

  @override
  Future<String> cacheRoot() async => '$root/cache';

  @override
  Future<String> configRoot() async => '$root/config';

  @override
  Future<String> logRoot() async => '$root/logs';
}
