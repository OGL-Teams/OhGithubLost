/// 启动层文件系统抽象。
///
/// 目的有二：
/// 1. **可测试**：启动校验逻辑可以完全跑在内存文件系统上（CI 无需真实安装目录）；
/// 2. **可移植**：Android / Windows / Linux 共用同一套校验逻辑。
library;

import 'dart:convert';

/// 启动层文件系统接口。
abstract class BootFileSystem {
  /// 创建文件系统实现（提供 const 构造，便于子类保持 const 构造能力）。
  const BootFileSystem();

  /// 路径（文件或目录）是否存在。
  Future<bool> exists(String path);

  /// 读取文件字节；不存在时返回 `null`。
  Future<List<int>?> readBytes(String path);

  /// 递归列出目录内文件，返回**相对该目录**的 POSIX 路径（已排序，仅文件）。
  ///
  /// 目录不存在时返回空列表（由调用方判定为校验失败）。
  Future<List<String>> listFilesRecursive(String directory);

  /// 读取 UTF-8 文本；不存在时返回 `null`。
  Future<String?> readText(String path) async {
    final bytes = await readBytes(path);
    if (bytes == null) {
      return null;
    }
    return utf8.decode(bytes);
  }
}

/// 真实 IO 实现（Android / Windows / Linux）。
// 这里曾有一个 `IoBootFileSystem`（真文件系统实现）。它只被定义、从未被
// 使用：启动装配（`main.dart`）用 `InMemoryBootFileSystem` + 内嵌清单。
// 保留一个没人用的实现会让人误以为启动路径会读磁盘，已删除。

/// 内存文件系统（测试 / 诊断用）。
class InMemoryBootFileSystem extends BootFileSystem {
  /// 创建实例；`files` 的键为 POSIX 路径，值为文件字节。
  InMemoryBootFileSystem([Map<String, List<int>>? files])
      : _files = <String, List<int>>{
          for (final entry in (files ?? const <String, List<int>>{}).entries)
            normalizePath(entry.key): entry.value,
        };

  final Map<String, List<int>> _files;

  /// 全部文件（只读快照）。
  Map<String, List<int>> get files =>
      Map<String, List<int>>.unmodifiable(_files);

  /// 以 UTF-8 文本写入一个文件（测试便利方法）。
  void writeText(String path, String content) {
    _files[normalizePath(path)] = utf8.encode(content);
  }

  /// 以字节写入一个文件。
  void writeBytes(String path, List<int> bytes) {
    _files[normalizePath(path)] = bytes;
  }

  /// 归一化路径：统一分隔符、去掉开头的 `./`。
  static String normalizePath(String path) {
    var normalized = path.replaceAll(r'\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }

  @override
  Future<bool> exists(String path) async {
    final normalized = normalizePath(path);
    if (_files.containsKey(normalized)) {
      return true;
    }
    return _files.keys.any((key) => key.startsWith('$normalized/'));
  }

  @override
  Future<List<int>?> readBytes(String path) async =>
      _files[normalizePath(path)];

  @override
  Future<List<String>> listFilesRecursive(String directory) async {
    final normalized = normalizePath(directory);
    final prefix = normalized.isEmpty ? '' : '$normalized/';
    final result = _files.keys
        .where((key) => prefix.isEmpty || key.startsWith(prefix))
        .map((key) => prefix.isEmpty ? key : key.substring(prefix.length))
        .toList()
      ..sort();
    return result;
  }
}
