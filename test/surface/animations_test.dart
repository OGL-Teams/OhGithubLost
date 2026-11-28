/// 展示层 · 动效分档与回退检查。
///
/// 覆盖两点：
/// 1. 档位越高，时长越长；
/// 2. 降到 `0` 时动画完全关闭（时长为零、`OgLReveal` 直接显示）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/animations.dart';
import 'package:ohgithublost/surface/app/motion.dart';

/// 用给定档位包一层作用域，并回传 context 供断言。
Future<BuildContext> _pumpAt(WidgetTester tester, int level) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: OgLMotionScope(
        level: level,
        child: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('档位 0：动画关闭、时长归零', (WidgetTester tester) async {
    final BuildContext context = await _pumpAt(tester, 0);
    expect(OgLAnim.enabled(context), isFalse);
    expect(OgLAnim.fast(context), Duration.zero);
    expect(OgLAnim.medium(context), Duration.zero);
    expect(OgLAnim.slow(context), Duration.zero);
    // 静默档：错峰返回 null（= 该项**不参与**入场动画），而不是"延迟 0"。
    expect(OgLAnim.staggerOf(context, 3), isNull);
  });

  testWidgets('档位 1 / 2 / 3：时长递增', (WidgetTester tester) async {
    final BuildContext c1 = await _pumpAt(tester, 1);
    final Duration m1 = OgLAnim.medium(c1);
    final BuildContext c2 = await _pumpAt(tester, 2);
    final Duration m2 = OgLAnim.medium(c2);
    final BuildContext c3 = await _pumpAt(tester, 3);
    final Duration m3 = OgLAnim.medium(c3);

    expect(OgLAnim.enabled(c1), isTrue);
    expect(m1.inMilliseconds, greaterThan(0));
    expect(m2.inMilliseconds, greaterThan(m1.inMilliseconds));
    expect(m3.inMilliseconds, greaterThan(m2.inMilliseconds));
  });

  testWidgets('从高档降到 0：时长即时回退为零', (WidgetTester tester) async {
    await _pumpAt(tester, 3);
    final BuildContext context = await _pumpAt(tester, 0);
    expect(OgLAnim.enabled(context), isFalse);
    expect(OgLAnim.medium(context), Duration.zero);
  });

  testWidgets('OgLReveal 按档位叠加效果（成本随档位增加）', (WidgetTester tester) async {
    Future<void> pumpAt(int level) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OgLMotionScope(
            level: level,
            child: const OgLReveal(delay: Duration.zero, child: Text('内容')),
          ),
        ),
      );
    }

    // 注意：`delay == null` 表示"该项不参与动画"（长列表尾部按档位限项）。
    // 这里显式给 Duration.zero 以验证**各档位的叠加效果**。

    // 档位 0：无动画层。
    await pumpAt(0);
    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsNothing);

    // 档位 1：仅淡入。
    await pumpAt(1);
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(find.byType(AnimatedSlide), findsNothing);

    // 档位 2（倒数第二档）：**最简全覆盖**——每个控件都动，但仍然只淡入。
    await pumpAt(2);
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(find.byType(AnimatedSlide), findsNothing);
    expect(find.byType(AnimatedScale), findsNothing);

    // 档位 3：MD2 全档无位移/缩放（revealOffset=0 / revealScaleFrom=1），
    // 拉满档也只有淡入；绘制边界仍然保留（不牵连整列表重绘）。
    await pumpAt(3);
    expect(find.byType(AnimatedSlide), findsNothing);
    expect(find.byType(AnimatedScale), findsNothing);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  group('档位质量表（降档 = 降质量，而不是砍掉效果）', () {
    test('逐级单调：1 不比 2 重、2 不比 3 重、0 不比 1 重', () {
      for (int level = 0; level <= 2; level++) {
        expect(
          OgLOAnimQuality.of(level)
              .isNotHeavierThan(OgLOAnimQuality.of(level + 1)),
          isTrue,
          reason: '档位 $level 应不比 ${level + 1} 更重',
        );
      }
    });

    test('时长逐档更长（严格递增，而不是"档位相同"）', () {
      final OgLOAnimQuality q1 = OgLOAnimQuality.of(1);
      final OgLOAnimQuality q2 = OgLOAnimQuality.of(2);
      final OgLOAnimQuality q3 = OgLOAnimQuality.of(3);
      expect(q1.medium < q2.medium, isTrue);
      expect(q2.medium < q3.medium, isTrue);
      // ★ MD2（M-3）：无错峰——staggerMaxIndex 全档为 0。
      expect(q1.staggerMaxIndex, 0);
      expect(q2.staggerMaxIndex, 0);
      expect(q3.staggerMaxIndex, 0);
      // ★ MD2：无转场位移（纯淡入/平台默认转场）。
      expect(q1.transitionOffset, 0);
      expect(q2.transitionOffset, 0);
      expect(q3.transitionOffset, 0);
    });

    test('大体积动画：时长逐档增加，但都**比 5.2 更快**', () {
      final OgLOAnimQuality q1 = OgLOAnimQuality.of(1);
      final OgLOAnimQuality q2 = OgLOAnimQuality.of(2);
      final OgLOAnimQuality q3 = OgLOAnimQuality.of(3);
      // 逐档更重（1 < 2 < 3）
      expect(q1.shellDuration < q2.shellDuration, isTrue);
      expect(q2.shellDuration < q3.shellDuration, isTrue);
      expect(q1.stateSwapDuration < q2.stateSwapDuration, isTrue);
      expect(q2.stateSwapDuration < q3.stateSwapDuration, isTrue);
      expect(q1.pageViewDuration < q2.pageViewDuration, isTrue);
      expect(q2.pageViewDuration < q3.pageViewDuration, isTrue);
      expect(q1.sheetDuration < q2.sheetDuration, isTrue);
      expect(q2.sheetDuration < q3.sheetDuration, isTrue);
      // 手感目标：全页 / 半页动画都在 250ms 以内（原先路由默认 300ms 起）
      for (final OgLOAnimQuality q in <OgLOAnimQuality>[q1, q2, q3]) {
        expect(q.shellDuration.inMilliseconds, lessThanOrEqualTo(200));
        expect(q.stateSwapDuration.inMilliseconds, lessThanOrEqualTo(200));
        expect(q.pageViewDuration.inMilliseconds, lessThanOrEqualTo(280));
        expect(q.sheetDuration.inMilliseconds, lessThanOrEqualTo(220));
      }
      // 静默档：全部为零（面板/翻页/memo 都"直接出现"）
      final OgLOAnimQuality q0 = OgLOAnimQuality.of(0);
      expect(q0.shellDuration, Duration.zero);
      expect(q0.stateSwapDuration, Duration.zero);
      expect(q0.pageViewDuration, Duration.zero);
      expect(q0.sheetDuration, Duration.zero);
      expect(q0.transitionWindow, 0);
    });

    test('MD2 曲线：标准档 easeOut、拉满档 fastOutSlowIn，绝不匀速', () {
      expect(OgLOAnimQuality.of(1).curve, Curves.easeOut);
      expect(OgLOAnimQuality.of(2).curve, Curves.easeOut);
      expect(OgLOAnimQuality.of(3).curve, Curves.fastOutSlowIn);
      expect(OgLOAnimQuality.of(1).largeCurve, Curves.easeOut);
      expect(OgLOAnimQuality.of(2).largeCurve, Curves.easeOut);
      expect(OgLOAnimQuality.of(3).largeCurve, Curves.fastOutSlowIn);
      for (int level = 1; level <= 3; level++) {
        expect(OgLOAnimQuality.of(level).curve, isNot(Curves.linear),
            reason: '档位 $level 的通用曲线不能是匀速（机械 / 死板）');
        expect(OgLOAnimQuality.of(level).largeCurve, isNot(Curves.linear),
            reason: '档位 $level 的大体积曲线不能是匀速（机械 / 死板）');
      }
      // 静默档（0）不做任何动画，曲线取值无关紧要。
      expect(OgLOAnimQuality.of(0).curve, Curves.linear);
    });

    test('MD2 覆盖面：无错峰、无 reveal 位移/缩放（纯淡入可选）', () {
      expect(OgLOAnimQuality.of(1).revealAll, isFalse);
      expect(OgLOAnimQuality.of(3).revealAll, isTrue);
      // MD2 全档：无位移 / 缩放（reveal 系列全归零）。
      for (int level = 1; level <= 3; level++) {
        expect(OgLOAnimQuality.of(level).revealOffset, 0,
            reason: '档位 $level 仍有 reveal 位移');
        expect(OgLOAnimQuality.of(level).revealScaleFrom, 1,
            reason: '档位 $level 仍有 reveal 缩放');
      }
    });

    test('MD2 无弹簧物理：全档 spring 为 null（stiffness 0）', () {
      // MD2（M-3）：弹簧/过冲是 Expressive 体系，全面移除。
      // 收尾一律用 ease-out 曲线（见"收尾曲线"测试）。
      for (int level = 0; level <= 3; level++) {
        expect(OgLOAnimQuality.of(level).springStiffness, 0,
            reason: '档位 $level 仍有弹簧刚度');
        expect(OgLOAnimQuality.of(level).spring, isNull,
            reason: '档位 $level 仍有弹簧');
      }
    });

    test('MD2 收尾曲线：全档纯减速（ease-out），无过冲', () {
      expect(OgLOAnimQuality.of(1).settleCurve, Curves.easeOut);
      expect(OgLOAnimQuality.of(2).settleCurve, Curves.easeOut);
      expect(OgLOAnimQuality.of(3).settleCurve, Curves.easeOut);
      // MD2 无回弹：纯减速曲线永远 ≤ 1。
      for (int level = 1; level <= 3; level++) {
        expect(OgLOAnimQuality.of(level).settleCurve.transform(0.8),
            lessThanOrEqualTo(1.0),
            reason: '档位 $level 收尾曲线有过冲（MD2 不允许）');
      }
    });

    testWidgets('共享元素（容器变换）只在标准档及以上启用', (WidgetTester tester) async {
      expect(OgLAnim.sharedElement(await _pumpAt(tester, 1)), isFalse);
      expect(OgLAnim.sharedElement(await _pumpAt(tester, 2)), isTrue);
      expect(OgLAnim.sharedElement(await _pumpAt(tester, 3)), isTrue);
    });

    testWidgets('OgLSpring.run：静默档直接落位（不产生动画）', (WidgetTester tester) async {
      final BuildContext ctx = await _pumpAt(tester, 0);
      final AnimationController c =
          AnimationController(vsync: const TestVSync(), value: 0);
      OgLSpring.run(c, ctx, from: 0);
      expect(c.value, 1);
      c.dispose();
    });

    test('整页缩放全面取消、模糊只在拉满档', () {
      // ★ 3-2：整页缩放（转场缩放）已全面取消——所有档位的
      //   transitionScaleFrom 都是 1，不再有"整页被缩放"的画面。
      for (int level = 0; level <= 3; level++) {
        expect(OgLOAnimQuality.of(level).transitionScaleFrom, 1,
            reason: '档位 $level 仍带整页缩放');
      }
      // 内容级缩放只有**拉满档**才有（档位 1 / 2 一律不缩放）。
      expect(OgLOAnimQuality.of(1).hasScale, isFalse, reason: '档位 1 不缩放');
      expect(OgLOAnimQuality.of(2).hasScale, isFalse,
          reason: '档位 2 也不缩放（整页缩放取消后只留淡入）');
      expect(OgLOAnimQuality.of(3).hasScale, isTrue, reason: '拉满档保留极轻的内容级缩放');
      // MD2：blur 是 Expressive 体系，全档移除。
      for (int level = 0; level <= 3; level++) {
        expect(OgLOAnimQuality.of(level).hasBlur, isFalse,
            reason: '档位 $level 仍有 blur');
      }
    });

    test('档位 0：全静默（时长零、无位移、无缩放）', () {
      final OgLOAnimQuality q0 = OgLOAnimQuality.of(0);
      expect(q0.fast, Duration.zero);
      expect(q0.medium, Duration.zero);
      expect(q0.slow, Duration.zero);
      expect(q0.hasScale, isFalse);
      expect(q0.revealOffset, 0);
      expect(q0.transitionOffset, 0);
    });

    testWidgets('MD2 错峰全档归零：staggerOf 恒为零延迟或 null（无错峰）', (WidgetTester tester) async {
      Future<BuildContext> pump(int level) => _pumpAt(tester, level);

      // MD2（M-3）：错峰是 Expressive 体系，全档移除——
      // staggerStep = 0 且 staggerMaxIndex = 0。
      for (int level = 1; level <= 3; level++) {
        final BuildContext ctx = await pump(level);
        expect(OgLAnim.staggerOf(ctx, 0), Duration.zero,
            reason: '档位 $level 首项应零延迟（无错峰）');
        if (level == 1) {
          // 档位 1 保守覆盖（revealAll=false）：尾部直接静态渲染。
          expect(OgLAnim.staggerOf(ctx, 200), isNull,
              reason: '档位 1 尾部不参与动画（保守覆盖）');
        } else {
          expect(OgLAnim.staggerOf(ctx, 200), Duration.zero,
              reason: '全覆盖档位：再靠后的项也有动画（无错峰）');
        }
      }

      final BuildContext c0 = await pump(0);
      expect(OgLAnim.staggerOf(c0, 0), isNull, reason: '静默档不参与任何入场动画');
    });
  });
}
