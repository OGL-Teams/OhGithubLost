/// 展示层 · 页面过渡的性能约定（5.0 修「页面过渡卡顿」的回归护栏）。
///
/// 用户实测：**页面过渡**卡，而其它动画不卡。根因是整页缩放过渡
/// （Flutter 默认 `ZoomPageTransitionsBuilder`）要求整页在过渡期间反复
/// 重新光栅化。因此这里把两条约定固定成测试：
/// 1. 过渡必须包 `RepaintBoundary`（过渡期间只重合成，不重绘页面）；
/// 2. 过渡的**视觉窗口**：实际运动只占用路线时间线的前一段
///    （档位越高窗口越大，观感都很快）。
/// 3. 最保守的档位 1 **不带缩放**；档位 2 / 3 允许"极轻"缩放（≤1%），
///    且同样必须包在 `RepaintBoundary` 里。不得引用 Flutter 默认的整页缩放过渡。
///
/// 档位 `0`（关闭动画）例外：直接返回 child，不做任何包装。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/motion.dart';

/// 取某个档位在 Android 上实际生效的过渡构建器。
PageTransitionsBuilder _builderFor(int level) {
  final PageTransitionsTheme theme = OgLMotion.pageTransitions(level);
  return theme.builders[TargetPlatform.android]!;
}

/// 用构建器产出一次过渡的 widget 树（[t] 为动画进度）。
Widget _transition(
  PageTransitionsBuilder builder,
  BuildContext context,
  double t,
) {
  final MaterialPageRoute<void> route = MaterialPageRoute<void>(
    builder: (BuildContext _) => const SizedBox.shrink(),
  );
  return builder.buildTransitions<void>(
    route,
    context,
    AlwaysStoppedAnimation<double>(t),
    const AlwaysStoppedAnimation<double>(0),
    const Text('page'),
  );
}

void main() {
  testWidgets('档位 0：不做任何包装（回到 Flutter 之外的"瞬时切换"）', (WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final Widget result = _transition(_builderFor(0), context, 0.5);
    expect(result, isA<Text>(), reason: '档位 0 必须原样返回 child');
  });

  for (final int level in <int>[1, 2, 3]) {
    testWidgets('档位 $level：必须包 RepaintBoundary，缩放按档位分级',
        (WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final Widget result = _transition(_builderFor(level), context, 0.5);
      // ① 最外层就是 RepaintBoundary：过渡只做图层合成。
      expect(result, isA<RepaintBoundary>(),
          reason: '档位 $level 的过渡最外层必须是 RepaintBoundary');
      // ② 真的挂进树里跑一遍：最保守的档位 1 不缩放；2 / 3 允许极轻缩放。
      await tester.pumpWidget(MaterialApp(home: result));
      if (level == 1) {
        expect(find.byType(ScaleTransition), findsNothing,
            reason: '最保守的档位不做缩放（整页重光栅化的根源）');
      } else {
        expect(find.byType(ScaleTransition), findsOneWidget,
            reason: '档位 $level 允许极轻缩放（≤1%）');
      }
      expect(find.byType(RepaintBoundary), findsWidgets);
      // ③ 也不得回退到 Flutter 的整页缩放过渡。
      expect(_builderFor(level), isNot(isA<ZoomPageTransitionsBuilder>()));
    });
  }

  test('视觉窗口逐档增大，且都小于 1（"实际运动"一定比路线时间线短）', () {
    final double w1 = OgLOAnimQuality.of(1).transitionWindow;
    final double w2 = OgLOAnimQuality.of(2).transitionWindow;
    final double w3 = OgLOAnimQuality.of(3).transitionWindow;
    expect(w1 < w2, isTrue);
    expect(w2 < w3, isTrue);
    for (final double w in <double>[w1, w2, w3]) {
      expect(w > 0 && w < 1, isTrue, reason: '窗口必须在 (0,1) 内，实际窗口=$w');
    }
    // 档位 1 的全页运动要明显快于路线默认时长（300ms × 0.42 ≈ 126ms）。
    expect(w1 * 300, lessThan(150));
  });

  test('所有档位都覆盖全部平台（避免某平台漏配而回落到默认缩放过渡）', () {
    for (final int level in <int>[0, 1, 2, 3]) {
      final PageTransitionsTheme theme = OgLMotion.pageTransitions(level);
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(theme.builders.containsKey(platform), isTrue,
            reason: '档位 $level 缺少平台 $platform 的过渡配置');
      }
    }
  });
}
