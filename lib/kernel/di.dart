/// L0 内核级 · 内核级类型化依赖容器（DI）。
///
/// 设计目标：
/// - **显式**：一切跨模块实例都通过 `resolve` 获得，禁止跨层 `new`；
/// - **封闭**：启动完成后 `seal()` 封存，杜绝运行期偷偷注册；
/// - **可诊断**：支持导出已注册键清单，进入启动报告。
library;

/// 依赖容器错误。
class KernelDiError extends Error {
  /// 创建错误。
  KernelDiError(this.message);

  /// 错误说明。
  final String message;

  @override
  String toString() => 'KernelDiError: $message';
}

/// 服务键：`Type` + 可选标签（同类型多实例场景）。
class _ServiceKey {
  /// [scope] 为层命名空间（如 base / domain）；null = 全局键，
  /// 保持既有 register/resolve 调用面完全兼容。
  const _ServiceKey(this.type, this.tag, [this.scope]);

  final Type type;
  final String? tag;
  final String? scope;

  @override
  bool operator ==(Object other) {
    return other is _ServiceKey &&
        other.type == type &&
        other.tag == tag &&
        other.scope == scope;
  }

  @override
  int get hashCode => Object.hash(type, tag, scope);

  @override
  String toString() {
    final String base = tag == null ? '$type' : '$type#$tag';
    return scope == null ? base : '$scope:$base';
  }
}

/// 类型化依赖容器。
class KernelDi {
  final Map<_ServiceKey, Object> _instances = <_ServiceKey, Object>{};
  final Map<_ServiceKey, Object Function(KernelDi di)> _factories =
      <_ServiceKey, Object Function(KernelDi di)>{};

  bool _sealed = false;

  /// 容器是否已封存（封存后禁止任何注册行为）。
  bool get isSealed => _sealed;

  /// 注册一个现成实例。
  ///
  /// 默认拒绝覆盖已注册的服务；显式传 `replace: true` 才允许替换。
  void register<T extends Object>(
    T instance, {
    String? tag,
    bool replace = false,
  }) {
    _ensureMutable();
    final key = _ServiceKey(T, tag);
    _ensureAbsent(key, replace: replace);
    _instances[key] = instance;
  }

  /// 注册一个惰性工厂（首次 `resolve` 时创建并缓存）。
  void registerFactory<T extends Object>(
    T Function(KernelDi di) factory, {
    String? tag,
    bool replace = false,
  }) {
    _ensureMutable();
    final key = _ServiceKey(T, tag);
    _ensureAbsent(key, replace: replace);
    _factories[key] = factory;
  }

  /// 解析服务；未注册时抛出 [KernelDiError]。
  T resolve<T extends Object>({String? tag}) {
    final key = _ServiceKey(T, tag);
    final instance = _instances[key];
    if (instance is T) {
      return instance;
    }
    final factory = _factories[key];
    if (factory != null) {
      final created = factory(this);
      if (created is! T) {
        throw KernelDiError('工厂返回类型不匹配: $key');
      }
      _instances[key] = created;
      // 工厂使命完成：实例已缓存，移除惰性条目——
      // 否则 describe() 会把同一个键同时列为"实例"和"(factory)"（重复且误导）。
      _factories.remove(key);
      return created;
    }
    throw KernelDiError('未注册的服务: $key');
  }

  /// 解析服务；未注册时返回 `null`。
  T? tryResolve<T extends Object>({String? tag}) {
    final key = _ServiceKey(T, tag);
    if (_instances.containsKey(key) || _factories.containsKey(key)) {
      return resolve<T>(tag: tag);
    }
    return null;
  }

  /// 是否已注册（含惰性工厂）。
  bool contains<T extends Object>({String? tag}) {
    final key = _ServiceKey(T, tag);
    return _instances.containsKey(key) || _factories.containsKey(key);
  }

  /// ★ 层命名空间（批 12）：把服务注册到指定层的私有命名空间，
  ///   跨层不得用 `resolve<T>()` 意外取到——必须显式声明来源层。
  ///   给新代码一条正确的路，并由 describe() 如实列出作用域。
  void registerIn<T extends Object>(
    String scope,
    T instance, {
    String? tag,
    bool replace = false,
  }) {
    _ensureMutable();
    if (scope.isEmpty) {
      throw KernelDiError('层命名空间不能为空');
    }
    final _ServiceKey key = _ServiceKey(T, tag, scope);
    _ensureAbsent(key, replace: replace);
    _instances[key] = instance;
  }

  /// 从指定层命名空间解析；未注册时抛错（不回落到全局键）。
  T resolveFrom<T extends Object>(String scope, {String? tag}) {
    final _ServiceKey key = _ServiceKey(T, tag, scope);
    final Object? instance = _instances[key];
    if (instance is T) {
      return instance;
    }
    throw KernelDiError('层 $scope 未注册服务: $key');
  }

  /// 该层命名空间已注册的服务键清单（启动诊断用）。
  List<String> describeScope(String scope) => <String>[
        for (final _ServiceKey key in _instances.keys)
          if (key.scope == scope) key.toString(),
      ]..sort();

  /// 封存容器：启动完成后调用，此后任何注册都会抛出异常。
  void seal() {
    _sealed = true;
  }

  /// 导出已注册键清单（按名称排序），用于启动诊断。
  List<String> describe() {
    final keys = <String>{
      ..._instances.keys.map((key) => key.toString()),
      ..._factories.keys.map((key) => '${key.toString()} (factory)'),
    }.toList()
      ..sort();
    return keys;
  }

  void _ensureMutable() {
    if (_sealed) {
      throw KernelDiError('容器已封存，启动完成后禁止再注册服务');
    }
  }

  void _ensureAbsent(_ServiceKey key, {required bool replace}) {
    if (replace) {
      _instances.remove(key);
      _factories.remove(key);
      return;
    }
    if (_instances.containsKey(key) || _factories.containsKey(key)) {
      throw KernelDiError('服务已注册（如需覆盖请显式 replace: true）: $key');
    }
  }
}
