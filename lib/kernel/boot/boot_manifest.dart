/// 引导清单（Boot Manifest）：模型、容错解析与**规范化序列化**。
///
/// 安全关键说明：
/// - 清单签名覆盖的是「去掉 `signature` 字段后的规范化 JSON」；
/// - [canonicalJsonEncode] 必须是**确定性**的（键按字典序、无空白、数字原样输出）；
/// - 任何修改本文件序列化行为的提交，都必须同步升级签名工具，否则将误伤全部正常安装；
/// - 解析遵循容错原则：缺字段给默认值，未知字段原样保留（`extra`），永不因协议演进崩溃。
library;

import 'dart:convert';

import '../contract/module.dart';

/// 当前支持的清单 schema 版本。
const int kSupportedManifestSchema = 1;

/// 规范化 JSON 编码（确定性）。
///
/// 规则：`null` → `null`；布尔 → `true/false`；数字 → `toString()`；
/// 字符串 → `jsonEncode` 转义；数组 → 保持顺序；对象 → 键按字典序排序。
String canonicalJsonEncode(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(value, buffer);
  return buffer.toString();
}

void _writeCanonical(Object? value, StringBuffer out) {
  if (value == null) {
    out.write('null');
    return;
  }
  if (value is bool) {
    out.write(value ? 'true' : 'false');
    return;
  }
  if (value is num) {
    if (value is double && !value.isFinite) {
      throw const FormatException('规范化 JSON 不支持 NaN / Infinity');
    }
    out.write(value.toString());
    return;
  }
  if (value is String) {
    out.write(jsonEncode(value));
    return;
  }
  if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) {
        out.write(',');
      }
      _writeCanonical(value[i], out);
    }
    out.write(']');
    return;
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) {
        out.write(',');
      }
      final key = keys[i];
      out.write(jsonEncode(key));
      out.write(':');
      _writeCanonical(value[key], out);
    }
    out.write('}');
    return;
  }
  throw FormatException('规范化 JSON 不支持的类型: ${value.runtimeType}');
}

/// 清单中的模块条目。
class BootModuleEntry {
  /// 创建条目。
  const BootModuleEntry({
    required this.id,
    required this.layer,
    required this.path,
    required this.sha256,
    required this.version,
    this.extra = const <String, Object?>{},
  });

  /// 模块 ID（`<layer>.<name>`）。
  final String id;

  /// 所属层级（解析失败为 `null`，由校验器判定为不合法）。
  final ModuleLayer? layer;

  /// 模块目录（相对应用根，如 `lib/base/net`）。
  final String path;

  /// 目录指纹（小写十六进制 SHA-256）。
  final String sha256;

  /// 模块版本。
  final String version;

  /// 未识别字段（向前兼容）。
  final Map<String, Object?> extra;

  /// 条目是否完整合法。
  bool get isWellFormed =>
      id.isNotEmpty &&
      layer != null &&
      path.isNotEmpty &&
      sha256.isNotEmpty &&
      version.isNotEmpty;

  /// 容错解析。
  factory BootModuleEntry.fromJson(Map<String, Object?> json) {
    const knownKeys = <String>{'id', 'layer', 'path', 'sha256', 'version'};
    final extra = <String, Object?>{};
    for (final entry in json.entries) {
      if (!knownKeys.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }
    return BootModuleEntry(
      id: _asString(json['id']),
      layer: ModuleLayer.fromKey(_asStringOrNull(json['layer'])),
      path: _asString(json['path']),
      sha256: _asString(json['sha256']).toLowerCase(),
      version: _asString(json['version']),
      extra: extra,
    );
  }

  /// 序列化（包含 `extra`，保证往返不丢字段）。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        if (layer != null) 'layer': layer!.key,
        'path': path,
        'sha256': sha256,
        'version': version,
        ...extra,
      };

  @override
  String toString() => 'BootModuleEntry($id @ $path, ${layer?.key ?? '?'})';
}

/// 引导清单。
class BootManifest {
  /// 创建清单（通常通过 [BootManifest.fromJson] 构造）。
  BootManifest({required this.payload, required this.signature})
      : modules = _parseModules(payload['modules']);

  /// 负载（**不含** `signature` 字段）。
  ///
  /// 签名校验与规范化序列化都基于它；未识别字段会被完整保留。
  final Map<String, Object?> payload;

  /// Ed25519 签名（base64）；未签名为 `null`。
  final String? signature;

  /// 模块条目列表。
  final List<BootModuleEntry> modules;

  /// schema 版本（缺失按 0 处理）。
  int get schema {
    final value = payload['schema'];
    return value is int ? value : 0;
  }

  /// 应用版本。
  String get appVersion => _asString(payload['appVersion']);

  /// 构建标识。
  String get buildId => _asString(payload['buildId']);

  /// 生成时间（ISO-8601）。
  String get generatedAt => _asString(payload['generatedAt']);

  /// 是否携带签名。
  bool get isSigned => signature != null && signature!.isNotEmpty;

  /// schema 版本是否受支持。
  bool get isSchemaSupported =>
      schema >= 1 && schema <= kSupportedManifestSchema;

  /// 不合法的条目数量（>0 视为清单损坏）。
  int get malformedModuleCount =>
      modules.where((module) => !module.isWellFormed).length;

  /// 未识别字段（清单级，向前兼容）。
  Map<String, Object?> get extra {
    const knownKeys = <String>{
      'schema',
      'appVersion',
      'buildId',
      'generatedAt',
      'modules',
    };
    return <String, Object?>{
      for (final entry in payload.entries)
        if (!knownKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// 按层级筛选模块条目。
  List<BootModuleEntry> modulesOfLayer(ModuleLayer layer) =>
      modules.where((module) => module.layer == layer).toList();

  /// 容错解析：剥离 `signature`，其余字段进入负载。
  factory BootManifest.fromJson(Map<String, Object?> json) {
    final payload = <String, Object?>{};
    String? signature;
    for (final entry in json.entries) {
      if (entry.key == 'signature') {
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          signature = value;
        }
        continue;
      }
      payload[entry.key] = entry.value;
    }
    return BootManifest(payload: payload, signature: signature);
  }

  /// 构造空清单（开发旁路与测试用）。
  factory BootManifest.empty() => BootManifest(
        payload: const <String, Object?>{
          'schema': kSupportedManifestSchema,
          'appVersion': 'dev',
          'buildId': 'dev',
          'generatedAt': '',
          'modules': <Object?>[],
        },
        signature: null,
      );

  /// 签名所覆盖的规范化字节。
  List<int> canonicalPayloadBytes() =>
      utf8.encode(canonicalJsonEncode(payload));

  /// 序列化（含签名）。
  Map<String, Object?> toJson() => <String, Object?>{
        ...payload,
        if (signature != null) 'signature': signature,
      };

  @override
  String toString() => 'BootManifest(schema=$schema, appVersion=$appVersion, '
      'buildId=$buildId, modules=${modules.length}, signed=$isSigned)';
}

List<BootModuleEntry> _parseModules(Object? value) {
  if (value is! List) {
    return const <BootModuleEntry>[];
  }
  final entries = <BootModuleEntry>[];
  for (final item in value) {
    if (item is Map) {
      entries.add(BootModuleEntry.fromJson(_asMap(item)));
    }
  }
  return entries;
}

String _asString(Object? value) {
  if (value is String) {
    return value;
  }
  if (value == null) {
    return '';
  }
  return '$value';
}

String? _asStringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    result[entry.key.toString()] = entry.value;
  }
  return result;
}
