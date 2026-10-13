/// 展示层设置的一致性协议检查。
///
/// 关键纪律：
/// 1. 反序列化**永不抛**：坏数据回落默认值；
/// 2. 保存失败**不静默**：内存值仍生效但 lastError 必须可见；
/// 3. 存储键沿用 `ogl.settings`（老配置文件可平滑读取）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/settings.dart';
import 'package:ohgithublost/surface/util/accel.dart';

/// 读取必抛（模拟磁盘故障）。
class _ThrowingReadPersistence implements OgLSettingsPersistence {
  @override
  Future<String?> read() async => throw StateError('磁盘故障');

  @override
  Future<void> write(String raw) async {}

  @override
  Future<void> clear() async {}
}

/// 写入必抛（模拟只读磁盘）。
class _ThrowingWritePersistence implements OgLSettingsPersistence {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String raw) async => throw StateError('只读磁盘');

  @override
  Future<void> clear() async {}
}

void main() {
  group('OgLSettings 容错反序列化', () {
    test('null / 非 Map → 默认值', () {
      expect(OgLSettings.fromJson(null).mode, OgLThemeMode.system);
      expect(OgLSettings.fromJson(42).dnsMode, 'system');
      expect(OgLSettings.fromJson(<Object?>[]).dnsServerId, 'alidns');
    });

    test('坏字段逐个回落（不抛）', () {
      final OgLSettings s = OgLSettings.fromJson(<String, Object?>{
        'mode': 'bogus',
        'dnsMode': 'weird',
        'dnsServerId': 5,
        'dnsPreferDoh': 'x',
      });
      expect(s.mode, OgLThemeMode.system);
      expect(s.dnsMode, 'system');
      expect(s.dnsServerId, 'alidns');
      expect(s.dnsPreferDoh, isTrue);
    });

    test('往返一致', () {
      const OgLSettings s = OgLSettings(
        mode: OgLThemeMode.dark,
        dnsMode: 'custom',
        dnsServerId: 'cloudflare',
        dnsPreferDoh: false,
      );
      final OgLSettings back = OgLSettings.fromJson(s.toJson());
      expect(back.mode, OgLThemeMode.dark);
      expect(back.dnsMode, 'custom');
      expect(back.dnsServerId, 'cloudflare');
      expect(back.dnsPreferDoh, isFalse);
      final OgLSettings encoded = OgLSettings.fromJson(jsonDecode(s.encode()));
      expect(encoded.dnsServerId, 'cloudflare');
    });

    test('新增字段：缺失时回落保守默认', () {
      final OgLSettings s = OgLSettings.fromJson(<String, Object?>{
        'mode': 'dark',
      });
      expect(s.seedColorId, 'github');
      expect(s.fontScale, 1.0);
      expect(s.density, 'comfortable');
      expect(s.reduceMotion, isFalse);
      expect(s.foldersFirst, isTrue);
      expect(s.codeHighlight, isTrue);
      expect(s.codeFontSize, 13);
      expect(s.codeWrap, isFalse);
      expect(s.codeThemePreset, 'theme');
      expect(s.codeColorKeyword, 0xFF569CD6);
      expect(s.releaseProxyEnabled, isFalse);
      // ★ 默认必须 false：一旦改成 true，等于替所有私有仓库用户默认同意
      //   把令牌交给第三方代理。这条断言就是防那次改动。
      expect(s.accelPrivateRepoAccepted, isFalse);
      expect(s.onboardingDone, isFalse);
    });

    test('没有任何内置加速通道（v6.4.3）', () {
      // 默认：没有通道、没有选中、没有生效前缀。
      final OgLSettings s = OgLSettings.defaults;
      expect(s.allAccelChannels, isEmpty);
      expect(s.releaseProxySelectedId, isEmpty);
      expect(s.activeAccelChannel, isNull);
      expect(s.activeAccelPrefixes, isEmpty);
      // 即便有人把开关打开，没有通道仍然不产生任何前缀。
      final OgLSettings on = s.copyWith(
        releaseProxyEnabled: true,
        releaseProxyConsentVersion: 99,
      );
      expect(on.activeAccelPrefixes, isEmpty);
    });

    test('适用范围：默认全开；逐项可关；全关仍合法', () {
      final OgLSettings s = OgLSettings.defaults;
      for (final OgLAccelScope scope in OgLAccelScope.values) {
        expect(s.accelScopeEnabled(scope), isTrue, reason: scope.id);
      }
      // 往返 JSON 不丢。
      final OgLSettings off = s.copyWith(
        accelScopes: <String>[OgLAccelScope.releaseAsset.id],
      );
      expect(OgLSettings.fromJson(off.toJson()).accelScopes,
          <String>['releaseAsset']);
      // 坏值被过滤；显式空列表保持为空（= 全都关了），不回落成全开。
      expect(
          OgLSettings.fromJson(<String, Object?>{
            'accelScopes': <String>['releaseAsset', 'bogus'],
          }).accelScopes,
          <String>['releaseAsset']);
      expect(
          OgLSettings.fromJson(<String, Object?>{'accelScopes': <String>[]})
              .accelScopes,
          isEmpty);
      // 字段缺失 → 全开（老配置升级后行为不变）。
      expect(OgLSettings.fromJson(<String, Object?>{}).accelScopes,
          kOgLAccelAllScopeIds);
    });

    test('按范围取前缀：关掉的范围拿不到前缀', () {
      const OgLAccelChannel channel =
          OgLAccelChannel(id: 'c1', name: '我的', baseUrl: 'https://a.example/');
      final OgLSettings s = OgLSettings.defaults.copyWith(
        releaseProxyEnabled: true,
        releaseProxyConsentVersion: 99,
        releaseProxyChannels: <OgLAccelChannel>[channel],
        releaseProxySelectedId: 'c1',
        accelScopes: <String>[OgLAccelScope.releaseAsset.id],
      );
      expect(s.accelPrefixesFor(OgLAccelScope.releaseAsset),
          <String>['https://a.example/']);
      // 其余三类没有开 → 空（调用方据此走直连）。
      for (final OgLAccelScope scope in <OgLAccelScope>[
        OgLAccelScope.actionArtifact,
        OgLAccelScope.repoFile,
        OgLAccelScope.readmeImage,
      ]) {
        expect(s.accelPrefixesFor(scope), isEmpty, reason: scope.id);
      }
    });

    test('自建通道：选中后才有前缀（单个，不是链）', () {
      const OgLAccelChannel channel =
          OgLAccelChannel(id: 'c1', name: '我的', baseUrl: 'https://a.example/');
      final OgLSettings s = OgLSettings.defaults.copyWith(
        releaseProxyEnabled: true,
        releaseProxyConsentVersion: 99,
        releaseProxyChannels: <OgLAccelChannel>[channel],
        releaseProxySelectedId: 'c1',
      );
      expect(s.activeAccelChannel?.id, 'c1');
      expect(s.activeAccelPrefixes, <String>['https://a.example/']);
    });

    test('私有仓库加速：知情开关往返 JSON 不丢失', () {
      final OgLSettings on =
          OgLSettings.defaults.copyWith(accelPrivateRepoAccepted: true);
      final OgLSettings back = OgLSettings.fromJson(on.toJson());
      expect(back.accelPrivateRepoAccepted, isTrue);
      // 坏值回落到默认（安全侧），而不是落到 true。
      final OgLSettings junk = OgLSettings.fromJson(<String, Object?>{
        'accelPrivateRepoAccepted': 'yes',
      });
      expect(junk.accelPrivateRepoAccepted, isFalse);
    });

    test('新增字段：坏值与越界被修正（不抛）', () {
      final OgLSettings s = OgLSettings.fromJson(<String, Object?>{
        'seedColorId': '',
        'fontScale': 99,
        'density': 'weird',
        'reduceMotion': 'x',
        'foldersFirst': 1,
        'codeHighlight': 'no',
        'codeFontSize': -5,
        'codeWrap': 'x',
        'onboardingDone': 0,
      });
      expect(s.seedColorId, 'github');
      expect(s.fontScale, OgLSettings.maxFontScale);
      expect(s.density, 'comfortable');
      expect(s.reduceMotion, isFalse);
      expect(s.foldersFirst, isTrue);
      expect(s.codeHighlight, isTrue);
      expect(s.codeFontSize, OgLSettings.minCodeFontSize);
      expect(s.codeWrap, isFalse);
      expect(s.onboardingDone, isFalse);
    });

    test('新增字段往返一致', () {
      const OgLSettings s = OgLSettings(
        seedColorId: 'grape',
        fontScale: 1.2,
        density: 'compact',
        reduceMotion: true,
        foldersFirst: false,
        codeHighlight: false,
        codeFontSize: 18,
        codeWrap: true,
        codeThemePreset: 'custom',
        codeColorKeyword: 0xFF112233,
        onboardingDone: true,
      );
      final OgLSettings back = OgLSettings.fromJson(jsonDecode(s.encode()));
      expect(back.seedColorId, 'grape');
      expect(back.fontScale, 1.2);
      expect(back.density, 'compact');
      expect(back.reduceMotion, isTrue);
      expect(back.foldersFirst, isFalse);
      expect(back.codeHighlight, isFalse);
      expect(back.codeFontSize, 18);
      expect(back.codeWrap, isTrue);
      expect(back.codeThemePreset, 'custom');
      expect(back.codeColorKeyword, 0xFF112233);
      expect(back.onboardingDone, isTrue);
    });
  });

  group('OgLSettingsController', () {
    test('加载 → 修改 → 再加载（持久化往返）', () async {
      final OgLInMemorySettingsPersistence store =
          OgLInMemorySettingsPersistence();
      final OgLSettingsController a = OgLSettingsController(persistence: store);
      await a.load();
      expect(a.isLoaded, isTrue);
      await a.setMode(OgLThemeMode.light);

      final OgLSettingsController b = OgLSettingsController(persistence: store);
      await b.load();
      expect(b.settings.mode, OgLThemeMode.light);
      expect(b.lastError, isNull);
    });

    test('读取失败：回落默认并记录原因', () async {
      final OgLSettingsController c =
          OgLSettingsController(persistence: _ThrowingReadPersistence());
      await c.load();
      expect(c.settings.mode, OgLThemeMode.system);
      expect(c.lastError, isNotNull);
    });

    test('保存失败：内存值仍生效，错误必须可见', () async {
      final OgLSettingsController c =
          OgLSettingsController(persistence: _ThrowingWritePersistence());
      await c.load();
      await c.setDnsMode('custom');
      expect(c.settings.dnsMode, 'custom', reason: '本次点击必须立刻生效');
      expect(c.lastError, isNotNull, reason: '保存失败不许静默');
    });

    test('重置：回到默认值', () async {
      final OgLSettingsController c = OgLSettingsController();
      await c.load();
      await c.setMode(OgLThemeMode.dark);
      await c.reset();
      expect(c.settings.mode, OgLThemeMode.system);
    });
  });
}
