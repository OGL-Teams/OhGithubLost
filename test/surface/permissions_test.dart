/// 展示层 · 权限网关检查（跨平台契约，不依赖具体主机）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/permissions.dart';

void main() {
  test('工厂返回可用网关（平台名非空）', () {
    final OgLPermissionGateway gateway = ogLPermissionGateway();
    expect(gateway.platformLabel, isNotEmpty);
  });

  test('describe 给出非空清单，且状态取值合法', () async {
    final OgLPermissionGateway gateway = ogLPermissionGateway();
    final List<OgLPermissionInfo> infos = await gateway.describe();
    expect(infos, isNotEmpty);
    for (final OgLPermissionInfo info in infos) {
      expect(info.title, isNotEmpty);
      expect(info.rationale, isNotEmpty);
      expect(OgLPermissionStatus.values, contains(info.status));
    }
  });

  test('request 返回值始终是合法状态（不会抛）', () async {
    final OgLPermissionGateway gateway = ogLPermissionGateway();
    final OgLPermissionStatus status =
        await gateway.request(OgLPermission.storage);
    expect(OgLPermissionStatus.values, contains(status));
  });

  test('actionable 只在 needsUserAction 时为真', () {
    const OgLPermissionInfo pending = OgLPermissionInfo(
      permission: OgLPermission.notifications,
      title: '通知',
      rationale: '原因',
      status: OgLPermissionStatus.needsUserAction,
    );
    expect(pending.actionable, isTrue);
    expect(
      pending.withStatus(OgLPermissionStatus.granted).actionable,
      isFalse,
    );
    expect(
      pending.withStatus(OgLPermissionStatus.notRequired).actionable,
      isFalse,
    );
  });
}
