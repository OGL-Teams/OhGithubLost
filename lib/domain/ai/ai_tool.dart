/// L2 · AI 可调用工具（函数调用）的注册项。
///
/// [AiService] 持有一个工具注册表；具体的 GitHub 操作（建 Issue / 读文件 /
/// 建 PR …）作为 [AiTool.run] 的实现由 `domain/gh` 提供、经 `domain_bridge`
/// 装配进注册表 —— AI 服务本身**不**直接 import 任何 gh 服务，保持可测试、
/// 可替换。
library;

/// 一个可被模型调用的工具。
class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.run,
  });

  final String name;
  final String description;

  /// JSON Schema（不含 `$schema`）——喂给模型的参数契约。
  final Map<String, Object?> parameters;

  /// 执行工具；返回可序列化的结果（Map / List / 标量）。
  ///
  /// 抛出的异常会被 [AiService] 捕获并作为 `tool_result` 回给模型，
  /// **不会**让整条会话崩溃。
  final Future<Object?> Function(Map<String, Object?> args) run;
}
