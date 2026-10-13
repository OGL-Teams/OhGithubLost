/// L3 展示级 · 返回键状态机检查（5.0 统一返回键的回归护栏）。
///
/// 用户在 5.0 明确要求：**返回键全局统一处理**（二级页 / 弹窗 / 抽屉 / tab / 退出）。
/// 这里把"按一次返回键应该发生什么"逐条固定，避免以后又出现
/// "有时直接退出、有时卡在 tab 里出不去"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/back_guard.dart';

void main() {
  final DateTime t0 = DateTime(2026, 10, 4, 12);

  test('抽屉打开：先关抽屉（不切 tab、不退出）', () {
    final OgLBackGuard guard = OgLBackGuard();
    expect(
      guard.decide(atHome: true, drawerOpen: true, now: t0),
      OgLBackAction.closeDrawer,
    );
    expect(guard.armed, isFalse);
  });

  test('不在首页：回到首页，而不是退出应用', () {
    final OgLBackGuard guard = OgLBackGuard();
    expect(
      guard.decide(atHome: false, now: t0),
      OgLBackAction.goHome,
    );
    expect(guard.armed, isFalse);
  });

  test('首页第一次按：提示「再按一次退出」（不退出）', () {
    final OgLBackGuard guard = OgLBackGuard();
    expect(guard.decide(atHome: true, now: t0), OgLBackAction.armExit);
    expect(guard.armed, isTrue);
  });

  test('首页窗口内第二次按：退出', () {
    final OgLBackGuard guard = OgLBackGuard();
    expect(guard.decide(atHome: true, now: t0), OgLBackAction.armExit);
    expect(
      guard.decide(
          atHome: true, now: t0.add(const Duration(milliseconds: 800))),
      OgLBackAction.exit,
    );
    // 退出后状态清空（再按一次又要重新提示）。
    expect(guard.armed, isFalse);
    expect(
      guard.decide(atHome: true, now: t0.add(const Duration(seconds: 1))),
      OgLBackAction.armExit,
    );
  });

  test('窗口过期：重新提示，不误退出', () {
    final OgLBackGuard guard = OgLBackGuard();
    expect(guard.decide(atHome: true, now: t0), OgLBackAction.armExit);
    expect(
      guard.decide(atHome: true, now: t0.add(const Duration(seconds: 3))),
      OgLBackAction.armExit,
    );
  });

  test('中途切过 tab / 关过抽屉：清掉待退出状态', () {
    final OgLBackGuard guard = OgLBackGuard();
    guard.decide(atHome: true, now: t0);
    expect(guard.armed, isTrue);
    guard.decide(atHome: false, now: t0.add(const Duration(seconds: 1)));
    expect(guard.armed, isFalse);
    guard.reset();
    expect(guard.armed, isFalse);
  });

  test('窗口边界：同一时刻（间隔 0）= 仍在窗口内 → 退出', () {
    final OgLBackGuard guard = OgLBackGuard(exitWindow: Duration.zero);
    expect(guard.decide(atHome: true, now: t0), OgLBackAction.armExit);
    expect(
      guard.decide(atHome: true, now: t0),
      OgLBackAction.exit,
      reason: '窗口判定是 <=（含边界）',
    );
  });

  test('窗口可配：1 秒窗口内第二次按退出、超时则重新提示', () {
    final OgLBackGuard guard =
        OgLBackGuard(exitWindow: const Duration(seconds: 1));
    expect(guard.decide(atHome: true, now: t0), OgLBackAction.armExit);
    expect(
      guard.decide(
          atHome: true, now: t0.add(const Duration(milliseconds: 400))),
      OgLBackAction.exit,
    );
  });
}
