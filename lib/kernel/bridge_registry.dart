/// L0 内核级 · 桥注册与发现（每层一座桥）。
///
/// 内核**不认识**任何具体桥类型——它只维护"层级键 → 桥实例"的映射，
/// 由调用方在 `resolve` 时声明期望类型。这样内核永远不依赖上层实现。
library;

/// 桥注册错误。
class KernelBridgeError extends Error {
  /// 创建错误。
  KernelBridgeError(this.message);

  /// 错误说明。
  final String message;

  @override
  String toString() => 'KernelBridgeError: $message';
}

/// 桥注册表。
class KernelBridgeRegistry {
  final Map<String, Object> _bridges = <String, Object>{};

  bool _sealed = false;

  /// 是否已封存（封存后禁止再注册桥）。
  bool get isSealed => _sealed;

  /// 注册某层的桥；同一层级键只允许注册一次。
  void register<T extends Object>(String layerKey, T bridge) {
    if (_sealed) {
      throw KernelBridgeError('桥注册表已封存，禁止再注册: $layerKey');
    }
    if (layerKey.isEmpty) {
      throw KernelBridgeError('层级键不能为空');
    }
    if (_bridges.containsKey(layerKey)) {
      throw KernelBridgeError('层级桥已注册（每层仅允许一座桥）: $layerKey');
    }
    _bridges[layerKey] = bridge;
  }

  /// 解析某层的桥，并断言其类型。
  T resolve<T extends Object>(String layerKey) {
    final bridge = _bridges[layerKey];
    if (bridge is T) {
      return bridge;
    }
    if (bridge == null) {
      throw KernelBridgeError('层级桥未注册: $layerKey');
    }
    throw KernelBridgeError(
      '层级桥类型不匹配: $layerKey（期望 $T，实际 ${bridge.runtimeType}）',
    );
  }

  /// 某层是否已注册桥。
  bool isRegistered(String layerKey) => _bridges.containsKey(layerKey);

  /// 已注册桥的快照（只读，用于诊断与测试）。
  Map<String, Object> get snapshot =>
      Map<String, Object>.unmodifiable(_bridges);

  /// 封存注册表：装配阶段结束后调用。
  ///
  /// ★ 批 9 交叉 X-04：此前只置 `_sealed = true`，
  ///   **某层漏注册桥不报错**，要到运行期 `resolve()` 才炸（往往在用户
  ///   点开某个页面时）。现在由装配根显式声明必须到齐的层级键，
  ///   封存即校验，把「漏注册」提前到启动期、变成一次明确的失败。
  ///   `expected` 为空表示只封存不校验（供单测构造最小注册表用）。
  void seal({Set<String> expected = const <String>{}}) {
    if (expected.isNotEmpty) {
      final Set<String> missing = expected.difference(_bridges.keys.toSet());
      if (missing.isNotEmpty) {
        throw KernelBridgeError('层级桥未注册齐全，封存被拒绝：缺 ${missing.join('、')}');
      }
    }
    _sealed = true;
  }
}
