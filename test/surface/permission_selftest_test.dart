/// L3 展示级 · 启动期权限自检的检查（**每次启动都跑**）。
///
/// 覆盖用户明确要求的行为：
/// 1. 每次启动都**实测**一遍（不是只在首次引导提示一次）；
/// 2. 缺权限时**不静默**：带事件码进诊断（warn → 通知中心）；
/// 3. 自检自身失败也要留痕（`OGL-PERM-000`），且**绝不抛**、不拖垮启动；
/// 4. 就绪项只留日志，不打扰用户（info 级不进通知中心）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';
import 'package:ohgithublost/surface/app/error_surface.dart';
import 'package:ohgithublost/surface/app/permission_selftest.dart';
import 'package:ohgithublost/surface/app/permissions.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';

/// 假网关：让自检逻辑可被单测（真网关依赖平台通道）。
class _FakeGateway implements OgLPermissionGateway {
  _FakeGateway(this._infos, {this.throws = false});

  final List<OgLPermissionInfo> _infos;
  final bool throws;

  @override
  String get platformLabel => 'FakeOS';

  @override
  bool get canOpenSettings => false;

  @override
  Future<List<OgLPermissionInfo>> describe() async {
    if (throws) {
      throw StateError('describe 失败演示');
    }
    return _infos;
  }

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async =>
      OgLPermissionStatus.granted;
}

OgLPermissionInfo _info(OgLPermission permission, OgLPermissionStatus status) =>
    OgLPermissionInfo(
      permission: permission,
      title: permission.name,
      rationale: 'rationale',
      status: status,
    );

/// 注入 zh 的 `shell` 分片（测试环境读不到 assets）。
void _loadZh() {
  final Object? decoded =
      jsonDecode(File('assets/i18n/zh/shell.json').readAsStringSync());
  OgLI18n.instance.debugInject('zh', <String, Map<String, String>>{
    'shell': <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (decoded as Map<Object?, Object?>).entries)
        '${e.key}': '${e.value}',
    },
  });
}

void main() {
  setUpAll(_loadZh);
  setUp(() {
    OgLNoticeCenter.instance.debugClear();
    OgLPermissionSelfTestReport.last = null;
  });

  test('全部就绪：allReady，且不产生告警（只留日志）', () async {
    final KernelDiagnostics diag = KernelDiagnostics();
    final OgLPermissionSelfTestReport report = await ogLRunPermissionSelfTest(
      diagnostics: diag,
      gateway: _FakeGateway(<OgLPermissionInfo>[
        _info(OgLPermission.storage, OgLPermissionStatus.granted),
        _info(OgLPermission.notifications, OgLPermissionStatus.notRequired),
      ]),
    );

    expect(report.allReady, isTrue);
    expect(report.readyCount, 2);
    expect(report.actionable, isEmpty);
    expect(report.platform, 'FakeOS');
    // 就绪项只走 info 级：通知中心不该被打扰。
    expect(
      diag.logTail.where((KernelLogEntry e) => e.level == KernelLogLevel.warn),
      isEmpty,
    );
    expect(OgLNoticeCenter.instance.history, isEmpty);
    expect(OgLPermissionSelfTestReport.last, same(report));
  });

  test('存储缺失：warn + 事件码 OGL-PERM-001（可检索），并给出修复指引', () async {
    final KernelDiagnostics diag = KernelDiagnostics()
      ..addSink(const OgLDiagnosticsNoticeSink());
    final OgLPermissionSelfTestReport report = await ogLRunPermissionSelfTest(
      diagnostics: diag,
      gateway: _FakeGateway(<OgLPermissionInfo>[
        _info(OgLPermission.storage, OgLPermissionStatus.needsUserAction),
      ]),
    );

    expect(report.allReady, isFalse);
    expect(report.actionable.single.permission, OgLPermission.storage);

    final Iterable<KernelLogEntry> warns = diag.logTail
        .where((KernelLogEntry e) => e.level == KernelLogLevel.warn);
    expect(warns.length, 1);
    expect(warns.single.code, kOgLPermStorageMissing);
    // 文案必须说清「影响什么 + 怎么修」，不能只说“没权限”。
    expect(warns.single.message, contains('文件访问'));
    expect(warns.single.message, contains('系统设置'));

    // 经 sink 进了通知中心（用户看得见），且带事件码。
    final List<OgLNotice> notices = OgLNoticeCenter.instance.history;
    expect(notices.length, 1);
    expect(notices.single.detail, contains(kOgLPermStorageMissing));
  });

  test('通知缺失：事件码 OGL-PERM-002', () async {
    final KernelDiagnostics diag = KernelDiagnostics();
    await ogLRunPermissionSelfTest(
      diagnostics: diag,
      gateway: _FakeGateway(<OgLPermissionInfo>[
        _info(OgLPermission.notifications, OgLPermissionStatus.needsUserAction),
      ]),
    );
    expect(
      diag.logTail
          .firstWhere((KernelLogEntry e) => e.level == KernelLogLevel.warn)
          .code,
      kOgLPermNotifyMissing,
    );
  });

  test('自检自身失败：error + OGL-PERM-000，且不抛异常', () async {
    final KernelDiagnostics diag = KernelDiagnostics();
    final OgLPermissionSelfTestReport report = await ogLRunPermissionSelfTest(
      diagnostics: diag,
      gateway: _FakeGateway(const <OgLPermissionInfo>[], throws: true),
    );

    expect(report.infos, isEmpty);
    expect(report.allReady, isTrue); // 没有实测结果 = 不误报
    final KernelLogEntry entry = diag.logTail
        .firstWhere((KernelLogEntry e) => e.level == KernelLogLevel.error);
    expect(entry.code, kOgLPermSelfTestFailed);
  });

  test('事件码映射稳定（可写进 issue / 可检索）', () {
    expect(OgLPermissionSelfTestReport.codeOf(OgLPermission.storage),
        'OGL-PERM-001');
    expect(OgLPermissionSelfTestReport.codeOf(OgLPermission.notifications),
        'OGL-PERM-002');
  });

  test('序列化进启动报告（关于页展示用）', () async {
    final KernelDiagnostics diag = KernelDiagnostics();
    final OgLPermissionSelfTestReport report = await ogLRunPermissionSelfTest(
      diagnostics: diag,
      gateway: _FakeGateway(<OgLPermissionInfo>[
        _info(OgLPermission.storage, OgLPermissionStatus.needsUserAction),
      ]),
    );
    final Map<String, Object?> json = report.toJson();
    expect(json['platform'], 'FakeOS');
    expect(json['allReady'], isFalse);
    expect((json['items']! as List<Object?>).length, 1);
  });
}
