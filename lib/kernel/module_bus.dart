/// 模块总线：注册、依赖图校验与拓扑排序。
///
/// 它回答三个问题：
/// 1. 有哪些模块？（注册与去重）
/// 2. 谁先启动？（拓扑排序，依赖缺失/循环一律拒绝）
/// 3. 能力由谁提供？（provides 唯一性校验）
library;

import 'bridge_registry.dart';
import 'contract/module.dart';
import 'di.dart';
import 'diagnostics.dart';

/// 模块总线错误。
class KernelModuleBusError extends Error {
  /// 创建错误。
  KernelModuleBusError(this.message);

  /// 错误说明。
  final String message;

  @override
  String toString() => 'KernelModuleBusError: $message';
}

/// 模块总线。
class KernelModuleBus {
  /// 创建总线。
  KernelModuleBus({
    required this.di,
    required this.diagnostics,
    required this.bridges,
  });

  /// 依赖容器（转交给模块上下文）。
  final KernelDi di;

  /// 诊断中枢。
  final KernelDiagnostics diagnostics;

  /// 桥注册表（转交给模块上下文）。
  final KernelBridgeRegistry bridges;

  final Map<String, OgLModule> _modules = <String, OgLModule>{};
  final Map<String, String> _capabilities = <String, String>{};

  bool _sealed = false;

  /// 是否已封存（封存后禁止再注册）。
  bool get isSealed => _sealed;

  /// 已注册模块数量。
  int get length => _modules.length;

  /// 已注册模块（注册顺序）。
  List<OgLModule> get modules => List<OgLModule>.unmodifiable(_modules.values);

  /// 能力索引快照（`能力标识 → 模块 ID`）。
  Map<String, String> get capabilityIndex =>
      Map<String, String>.unmodifiable(_capabilities);

  /// 按 ID 取模块（不存在返回 `null`）。
  OgLModule? byId(String moduleId) => _modules[moduleId];

  /// 模块描述符清单（按 ID 排序，供启动报告使用）。
  List<ModuleDescriptor> descriptors() {
    final list = _modules.values.map((module) => module.descriptor).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  /// 注册模块（装配阶段调用）。
  void register(OgLModule module) {
    if (_sealed) {
      throw KernelModuleBusError('模块总线已封存，禁止再注册模块');
    }
    final descriptor = module.descriptor;
    if (!descriptor.isWellFormed) {
      throw KernelModuleBusError('模块描述符不符合规范: ${descriptor.id}');
    }
    if (_modules.containsKey(descriptor.id)) {
      throw KernelModuleBusError('模块 ID 重复: ${descriptor.id}');
    }
    // 先**整体校验**能力唯一性，再做任何写入——
    // 避免"部分提供后抛异常"留下一半注册的脏状态。
    for (final capability in descriptor.provides) {
      final owner = _capabilities[capability];
      if (owner != null) {
        throw KernelModuleBusError(
          '能力重复提供: $capability（$owner 与 ${descriptor.id}）',
        );
      }
    }
    _modules[descriptor.id] = module;
    for (final capability in descriptor.provides) {
      _capabilities[capability] = descriptor.id;
    }
    diagnostics.info(
      'KERNEL',
      '模块注册: ${descriptor.id}',
      code: 'OGL-KERNEL-101',
      data: <String, Object?>{
        'version': descriptor.version,
        'layer': descriptor.layer.key,
      },
    );
  }

  /// 封存总线（装配结束后调用）。
  void seal() {
    _sealed = true;
  }

  /// 校验依赖图（缺失依赖与循环依赖都会抛出异常）。
  void verify() {
    final missing = <String>[];
    for (final module in _modules.values) {
      for (final dependency in module.descriptor.requires) {
        if (!_modules.containsKey(dependency)) {
          missing.add('${module.descriptor.id} -> $dependency');
        }
      }
    }
    if (missing.isNotEmpty) {
      throw KernelModuleBusError('依赖缺失: ${missing.join(', ')}');
    }
    resolveOrder();
  }

  /// 解析启动顺序（稳定的深度优先拓扑排序）。
  List<OgLModule> resolveOrder() {
    final ordered = <OgLModule>[];
    final visiting = <String>{};
    final visited = <String>{};

    void visit(String id, List<String> path) {
      if (visited.contains(id)) {
        return;
      }
      if (visiting.contains(id)) {
        throw KernelModuleBusError(
          '检测到循环依赖: ${<String>[...path, id].join(' -> ')}',
        );
      }
      final module = _modules[id];
      if (module == null) {
        final from = path.isEmpty ? '<root>' : path.last;
        throw KernelModuleBusError('依赖缺失: $from -> $id');
      }
      visiting.add(id);
      for (final dependency in module.descriptor.requires) {
        visit(dependency, <String>[...path, id]);
      }
      visiting.remove(id);
      visited.add(id);
      ordered.add(module);
    }

    for (final id in _modules.keys.toList()) {
      visit(id, const <String>[]);
    }
    return List<OgLModule>.unmodifiable(ordered);
  }

  /// 导出依赖图（文本形式，供诊断报告展示）。
  String toDependencyGraph() {
    final buffer = StringBuffer();
    for (final descriptor in descriptors()) {
      final deps =
          descriptor.requires.isEmpty ? '-' : descriptor.requires.join(', ');
      buffer.writeln('${descriptor.id} [${descriptor.layer.key}] -> $deps');
    }
    return buffer.toString();
  }
}
