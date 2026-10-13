/// L0 启动层契约 · **成品导出**（把下载成品送到"用户看得见"的位置）。
///
/// ## 为什么放契约层
/// "导出到用户选的文件夹"要用 Android SAF（硬件层实现），而触发点是**逻辑层**的
/// 下载管理器；若逻辑层直接 import 硬件层，就破坏了
/// `surface → domain → base → kernel` 的依赖方向。
/// 于是把"能力"写在契约里（谁都可以引用），"实现"留在硬件层，由**装配根**
/// （`domain_bridge`）注入——与 `download_engine` / `disk_store` 同一套做法。
///
/// ## 语义
/// - 是否真的需要导出（存储②档）由**实现方**判断；
/// - **失败不许抛**：导出失败不影响"下载已完成"这个事实，返回 `false` 即可。
library;

/// 成品导出能力。
abstract class StorageExporter {
  /// 把刚落盘的 [localPath] 导出为 [fileName]（用户可见位置）。
  ///
  /// 返回 `true` 表示"确实导出成功"；`false` 表示"不需要导出 / 未授权 / 失败"。
  Future<bool> export({required String localPath, required String fileName});
}
