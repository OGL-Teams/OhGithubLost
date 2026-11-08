/// L2 中枢级 · OAuth Device Flow 契约回归（批8 交叉审计补充）。
///
/// 离线断言范围：Client ID 守卫与 GhOAuthCode 契约——端点常量为
/// gh_oauth_io.dart 文件级私有（不可直接断言），真实 HTTP 往返由登录页
/// 现场执行，端点语义以 GitHub 官方文档裁决。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/gh/gh_oauth.dart';
import 'package:ohgithublost/domain/gh/gh_oauth_types.dart';

void main() {
  group('Device Flow 契约', () {
    test('Client ID 为空 → ArgumentError（未注入构建参数时登录页隐藏入口）', () {
      expect(
        () => GhOAuthDeviceFlow(clientId: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Client ID 非空 → 构造成功且字段保留', () {
      final GhOAuthDeviceFlow flow = GhOAuthDeviceFlow(clientId: 'Ov23liTEST');
      expect(flow.clientId, 'Ov23liTEST');
    });

    test('GhOAuthCode 契约：授权页与轮询间隔', () {
      const GhOAuthCode code = GhOAuthCode(
        deviceCode: 'd',
        userCode: 'ABCD-1234',
        verificationUri: 'https://github.com/login/device',
      );
      expect(code.verificationUri, 'https://github.com/login/device');
      expect(code.interval, 5);
    });
  });
}
