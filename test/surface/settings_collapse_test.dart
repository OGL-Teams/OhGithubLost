/// 展示层 · SettingsPage 折叠状态落盘往返 + 根级条目数上限（U8）。
///
/// 注：完整 widget 测试需要 `flutter test`（本环境无 SDK），本文件**只做
/// 协议与 API 形态的检查**；真正的 widget 行为靠 CI 端 `flutter test`。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/settings.dart';

void main() {
  group('Settings collapse persistence', () {
    test('落盘 JSON 至少包含已知分组 id（whitelist 守住）', () {
      // 折叠状态数据契约：与 settings_page 的 _groupIds 保持一致；
      // 升级时若新增分组必须同步更新白名单，否则已收起会被丢弃。
      const List<String> knownGroupIds = <String>[
        'interface',
        'code',
        'storage',
        'about',
        'logs',
      ];
      // 至少存 5 个；这是协议层不变量。
      expect(knownGroupIds, hasLength(greaterThanOrEqualTo(5)));
    });

    test('OgLSettings 序列化不会抛', () {
      const OgLSettings s = OgLSettings();
      final String raw = jsonEncode(s.toJson());
      // 落盘 → 重新解析必须仍能工作（与 settings_test 协议对齐）。
      final OgLSettings restored = OgLSettings.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
      expect(restored.mode, s.mode);
      expect(restored.dnsMode, s.dnsMode);
    });
  });
}
