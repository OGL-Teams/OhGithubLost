/// 生命周期编排：注册、启动、停止与失败回滚。
///
/// 约定：
/// - 注册（[KernelLifecycle.registerAll]）按拓扑顺序执行，仅做接线；
/// - 启动（[KernelLifecycle.startAll]）按拓扑顺序执行，任何失败都会
///   **逆序回滚**已启动的模块并把错误上抛（见 STANDARDS S2：禁止吞异常）；
/// - 停止（[KernelLifecycle.stopAll]）逆序、幂等。
library;

import 'contract/module.dart';
import 'diagnostics.dart';

/// 启动失败异常（携带模块 ID、原因与回滚结果）。
class KernelStartupError extends Error {
  /// 创建异常。
  KernelStartupError({
    required this.moduleId,
    required this.message,
    required this.cause,
    this.rollbackErrors = const <String>[],
  });

  /// 失败模块 ID。
  final String moduleId;

  /// 失败说明。
  final String message;

  /// 原始异常。
  final Object cause;

  /// 回滚过程中收集到的错误（应为空数组）。
  final List<String> rollbackErrors;

  @override
  String toString() => 'KernelStartupError($moduleId): $message（cause=$cause, '
      'rollbackErrors=$rollbackErrors）';
}

/// 生命周期编排器。
class KernelLifecycle {
  /// 创建编排器。
  KernelLifecycle({required this.diagnostics});

  /// 诊断中枢。
  final KernelDiagnostics diagnostics;

  final Map<String, ModuleState> _states = <String, ModuleState>{};
  final List<OgLModule> _started = <OgLModule>[];

  /// 全部模块状态快照（`模块 ID → 状态名`）。
  Map<String, String> get states => <String, String>{
        for (final entry in _states.entries) entry.key: entry.value.name,
      };

  /// 已成功启动且尚未停止的模块（只读）。
  List<OgLModule> get started => List<OgLModule>.unmodifiable(_started);

  /// 查询模块状态（未登记视为 [ModuleState.registered]）。
  ModuleState stateOf(String moduleId) =>
      _states[moduleId] ?? ModuleState.registered;

  /// 按拓扑顺序执行注册回调；失败即抛出 [KernelStartupError]。
  Future<void> registerAll(
    List<OgLModule> ordered,
    KernelContext context,
  ) async {
    for (final module in ordered) {
      final id = module.descriptor.id;
      _states[id] = ModuleState.registering;
      final stopwatch = Stopwatch()..start();
      try {
        await module.onRegister(context);
        stopwatch.stop();
        _states[id] = ModuleState.registered;
        diagnostics.recordStage('register:$id', stopwatch.elapsed);
        diagnostics.recordModuleState(id, ModuleState.registered.name);
      } catch (error, stackTrace) {
        stopwatch.stop();
        _states[id] = ModuleState.failed;
        diagnostics.recordStage(
          'register:$id',
          stopwatch.elapsed,
          ok: false,
          detail: '$error',
        );
        diagnostics.recordModuleState(id, ModuleState.failed.name);
        diagnostics.error(
          'KERNEL',
          '模块注册失败: $id',
          code: 'OGL-KERNEL-201',
          data: <String, Object?>{'error': '$error', 'stack': '$stackTrace'},
        );
        throw KernelStartupError(
          moduleId: id,
          message: '模块注册失败',
          cause: error,
        );
      }
    }
  }

  /// 按拓扑顺序执行启动回调；失败时逆序回滚并抛出 [KernelStartupError]。
  Future<void> startAll(List<OgLModule> ordered) async {
    for (final module in ordered) {
      final id = module.descriptor.id;
      if (_states[id] == ModuleState.failed) {
        continue;
      }
      _states[id] = ModuleState.starting;
      final stopwatch = Stopwatch()..start();
      try {
        await module.onStart();
        stopwatch.stop();
        _states[id] = ModuleState.ready;
        _started.add(module);
        diagnostics.recordStage('start:$id', stopwatch.elapsed);
        diagnostics.recordModuleState(id, ModuleState.ready.name);
      } catch (error, stackTrace) {
        stopwatch.stop();
        _states[id] = ModuleState.failed;
        diagnostics.recordStage(
          'start:$id',
          stopwatch.elapsed,
          ok: false,
          detail: '$error',
        );
        diagnostics.recordModuleState(id, ModuleState.failed.name);
        final rollbackErrors = await _stopReverse();
        diagnostics.error(
          'KERNEL',
          '模块启动失败: $id',
          code: 'OGL-KERNEL-202',
          data: <String, Object?>{'error': '$error', 'stack': '$stackTrace'},
        );
        throw KernelStartupError(
          moduleId: id,
          message: '模块启动失败',
          cause: error,
          rollbackErrors: rollbackErrors,
        );
      }
    }
  }

  /// 逆序停止全部已启动模块（幂等）。
  Future<void> stopAll() async {
    final errors = await _stopReverse();
    if (errors.isNotEmpty) {
      diagnostics.warn(
        'KERNEL',
        '停止阶段出现异常',
        code: 'OGL-KERNEL-203',
        data: <String, Object?>{'errors': errors},
      );
    }
  }

  Future<List<String>> _stopReverse() async {
    final errors = <String>[];
    while (_started.isNotEmpty) {
      final module = _started.removeLast();
      final id = module.descriptor.id;
      _states[id] = ModuleState.stopping;
      final stopwatch = Stopwatch()..start();
      try {
        await module.onStop();
        stopwatch.stop();
        _states[id] = ModuleState.stopped;
        diagnostics.recordStage('stop:$id', stopwatch.elapsed);
        diagnostics.recordModuleState(id, ModuleState.stopped.name);
      } catch (error) {
        stopwatch.stop();
        errors.add('$id: $error');
        _states[id] = ModuleState.failed;
        diagnostics.recordStage(
          'stop:$id',
          stopwatch.elapsed,
          ok: false,
          detail: '$error',
        );
        diagnostics.recordModuleState(id, ModuleState.failed.name);
      }
    }
    return errors;
  }
}
