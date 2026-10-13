/// L1 底座级 · 硬盘逻辑：大对象 blob 存储（与 [DiskKv] 形态一致，语义独立）。
///
/// ## 为什么单开一个抽象
/// `DiskKv` 落点由平台决定：
/// - 原生 → 私有目录里的 JSON / SQLite；
/// - Web → 默认走 `localStorage`（**5 MB 上限**）。
///
/// 草稿正文、提交日志条目、缓存内容字节都可能突破 5 MB；把它们强行塞
/// `localStorage` 会**静默丢草稿 / 静默丢待同步** —— 不可接受。
/// `DiskBlobStore` 单独声明，是为了让"普通 KV"（设置项、索引）与"大对象"
/// （草稿 / 日志 / 缓存内容）走两条路径，**不互相挤压**。
///
/// ## 与 [DiskKv] 的关系
/// 接口形态对齐，方便实现互通；语义上**不替代** `DiskKv`：
/// - 普通设置项继续走 `DiskKv`（localStorage 够用，且设置项通常极小）；
/// - 大对象改走 `DiskBlobStore`（Web = IndexedDB；原生 = 文件，未来实现）。
///
/// ## 平台实现
/// - Web：`lib/base/disk/blob_store_web.dart`（IndexedDB，`dart:js_interop`）；
/// - 原生：未来由 `lib/base/disk/blob_store_io.dart` 提供（**本分支暂不实现**）。
library;

/// 大对象 blob 存储（text 形态；上层自行决定序列化）。
///
/// 与 [DiskKv] 的接口**完全一致**，方便互转；二者**语义独立**，可以指向不同的
/// 物理后端（KV 走 localStorage，Blob 走 IndexedDB）。
abstract class DiskBlobStore {
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

/// 内存大对象 blob 存储（测试 / CI 离线 / 降级运行）。
///
/// ## 何时落回
/// - 单元测试：完全不依赖 IndexedDB / 文件系统，**离线可跑**；
/// - 生产环境的兜底：IndexedDB 初始化失败时（隐私模式 / 禁用存储），降级为
///   进程内存，**绝不抛**（与 [DiskKv] 在 localStorage 不可用时的兜底语义一致）。
class InMemoryBlobStore implements DiskBlobStore {
  /// 内存表。
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
