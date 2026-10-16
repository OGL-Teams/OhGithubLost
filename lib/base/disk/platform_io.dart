/// L1 底座级 · 硬盘逻辑：**平台实现的入口**（唯一需要分平台的接缝）。
///
/// ## 这一层是什么
/// 真实的文件系统操作（File / Directory / IOSink）全部收敛在
/// [platform_io_impl.dart]；本文件只做一步**直接导出**——调用方
/// （`base_bootstrap.dart`、单测等）只需 `import 'platform_io.dart';`。
///
/// 注：本分支为**纯原生构建**，原先对 Web（浏览器）的条件导出已移除；
/// 实现文件后缀 `_impl` 仅表示「实现」。
library;

export 'platform_io_impl.dart';
