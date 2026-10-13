/// L1 底座级 · 网络连接：镜像（加速）通道。
///
/// 原 App 依赖第三方加速域名访问 GitHub。这里把它抽象成**可插拔的通道列表**：
/// 通道按声明顺序尝试，全部不可用则回落直连（直连永远保留，是最后底线）。
library;

/// 镜像通道：把匹配的主机替换为加速主机。
class MirrorChannel {
  /// 创建通道。
  const MirrorChannel({
    required this.id,
    required this.pattern,
    required this.replacement,
    this.enabled = true,
  });

  /// 通道 ID（用于诊断与"本次已尝试"去重）。
  final String id;

  /// 匹配正则（作用于完整 URL）。
  final String pattern;

  /// 替换后的 URL 模板（支持 `$1` 等反向引用）。
  final String replacement;

  /// 是否启用（主题包 / 设置可关闭）。
  final bool enabled;

  /// 对 [url] 应用本通道；不匹配时返回 `null`。
  String? apply(String url) {
    if (!enabled) {
      return null;
    }
    final regex = _compiled(pattern);
    if (!regex.hasMatch(url)) {
      return null;
    }
    final mirrored = url.replaceFirstMapped(regex, (match) {
      var output = replacement;
      // **从大到小**替换：否则 `$1` 会先命中 `$10` 的前缀，
      // 把 `$10` 变成 `<g1>0`（经典反向引用陷阱）。
      for (var index = match.groupCount; index >= 1; index--) {
        output = output.replaceAll('\$$index', match.group(index) ?? '');
      }
      return output;
    });
    return mirrored == url ? null : mirrored;
  }

  /// 正则编译缓存：`apply` 在每次请求、每条通道上都会被调用，
  /// 每次重新 `RegExp(pattern)` 是纯浪费（通道数量有限，缓存安全）。
  static final Map<String, RegExp> _regexCache = <String, RegExp>{};

  static RegExp _compiled(String pattern) =>
      _regexCache.putIfAbsent(pattern, () => RegExp(pattern));

  /// 复制并覆盖启用状态（通道本身不可变，切换开关靠重建）。
  MirrorChannel copyWith({bool? enabled}) => MirrorChannel(
        id: id,
        pattern: pattern,
        replacement: replacement,
        enabled: enabled ?? this.enabled,
      );

  @override
  String toString() => 'MirrorChannel($id, enabled=$enabled)';
}

/// 镜像选择器：按声明顺序挑选下一个可用通道。
///
/// 刻意不做"测速择优"——那需要额外请求，且加速域名质量波动大；
/// 顺序 + 失败跳过（[skip]）在实践中更稳定，也更可预测。
class MirrorSelector {
  /// 创建选择器。
  MirrorSelector({List<MirrorChannel> channels = const <MirrorChannel>[]})
      : _channels = List<MirrorChannel>.of(channels);

  final List<MirrorChannel> _channels;

  /// 通道列表（只读）。
  List<MirrorChannel> get channels =>
      List<MirrorChannel>.unmodifiable(_channels);

  /// 是否配置了可用通道。
  bool get isEmpty => _channels.every((channel) => !channel.enabled);

  /// 追加通道（诊断页手动添加加速源）。
  void add(MirrorChannel channel) => _channels.add(channel);

  /// 批量启停全部通道（批量任务选择"直连"时全停、"自动"时全开）。
  void setAllEnabled(bool enabled) {
    final replaced = <MirrorChannel>[
      for (final MirrorChannel channel in _channels)
        channel.copyWith(enabled: enabled),
    ];
    _channels
      ..clear()
      ..addAll(replaced);
  }

  /// 只保留某个通道可用（其余停用）；[only] 为 `null` 表示全部停用。
  void restrictTo(String? only) {
    final replaced = <MirrorChannel>[
      for (final MirrorChannel channel in _channels)
        channel.copyWith(enabled: only != null && channel.id == only),
    ];
    _channels
      ..clear()
      ..addAll(replaced);
  }

  /// 当前启用的通道 ID。
  List<String> get enabledIds => <String>[
        for (final MirrorChannel channel in _channels)
          if (channel.enabled) channel.id,
      ];

  /// 挑选下一个可用通道；无可用通道时返回 `null`（回落直连）。
  ({String id, String url})? mirrorFor(
    String url, {
    Set<String> skip = const <String>{},
  }) {
    for (final channel in _channels) {
      if (skip.contains(channel.id)) {
        continue;
      }
      final mirrored = channel.apply(url);
      if (mirrored != null) {
        return (id: channel.id, url: mirrored);
      }
    }
    return null;
  }

  /// 命中该 URL 的通道（不论是否已尝试）。
  MirrorChannel? channelFor(String url) {
    for (final channel in _channels) {
      if (channel.apply(url) != null) {
        return channel;
      }
    }
    return null;
  }
}

/// 内置镜像通道列表 —— **v6.4.3 起为空，且刻意保持为空**。
///
/// ## 这里曾经有什么
/// 两条把 GitHub 主机改写成第三方代理的规则（`ghproxy.net` 换
/// `raw.githubusercontent.com` / `api.github.com`）。它们默认关闭，可由
/// 主题包启用。
///
/// ## 为什么删掉
/// 它们是**内置的第三方代理地址**：一旦启用，你的仓库流量就经过一台与本项目
/// 无关的服务器，而它从哪来、由谁运营、是否记录请求，本项目都无从担保。
/// 本项目的定位是本地工具（不收集数据、令牌不出设备），把"某个第三方代理"
/// 预置进代码与这个定位相冲突 —— 即使它默认关闭，它仍然是**我们替你选的**。
///
/// 现在：**要加速就自己填通道地址**（见 `lib/surface/util/accel.dart` 的
/// 自定义加速通道）。选择权与知情权都在用户手上。
///
/// 镜像**机制**本身（[MirrorChannel] / [MirrorSelector]）予以保留：它是纯
/// 基础设施，不含任何具体地址；留着是为了不必在同一处改动里拆掉整条链路。
/// 但由于这里为空，它当前**完全不生效**。
final List<MirrorChannel> defaultMirrorChannels = <MirrorChannel>[];
