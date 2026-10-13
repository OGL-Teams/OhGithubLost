/// L1 硬件层 · 分片规划（纯函数）检查。
///
/// 分片一旦算错（漏一段 / 重叠 / 越界），下载出来的文件就是**坏的**，
/// 所以这里把边界条件逐条钉死。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/range_download.dart';

void main() {
  group('OgLChunkPlan', () {
    test('非法输入：总长 <= 0 → 空计划（不编造分片）', () {
      expect(OgLChunkPlan.of(total: 0, connections: 4), isEmpty);
      expect(OgLChunkPlan.of(total: -5, connections: 4), isEmpty);
    });

    test('恰好整除：分片数 = 并发数，且首尾相接、不重不漏', () {
      final List<OgLByteRange> plan = OgLChunkPlan.of(
        total: 4 * 1024 * 1024,
        connections: 4,
        minChunkBytes: 1024,
      );
      expect(plan.length, 4);
      expect(plan.first.start, 0);
      expect(plan.last.end, 4 * 1024 * 1024 - 1);
      for (int i = 1; i < plan.length; i++) {
        expect(plan[i].start, plan[i - 1].end + 1, reason: '分片必须首尾相接');
      }
      final int sum =
          plan.fold<int>(0, (int acc, OgLByteRange r) => acc + r.length);
      expect(sum, 4 * 1024 * 1024, reason: '分片总长必须等于文件长度');
    });

    test('除不尽：余数补给最后一片（仍然不重不漏）', () {
      final List<OgLByteRange> plan =
          OgLChunkPlan.of(total: 10, connections: 3, minChunkBytes: 1);
      expect(plan.length, 3);
      expect(plan[0].length, 3);
      expect(plan[1].length, 3);
      expect(plan[2].length, 4, reason: '余数进最后一片');
      expect(
          plan
              .map((OgLByteRange r) => r.length)
              .reduce((int a, int b) => a + b),
          10);
    });

    test('不重叠且覆盖全部字节（逐字节校验）', () {
      const int total = 1000;
      final Set<int> covered = <int>{};
      for (final OgLByteRange range
          in OgLChunkPlan.of(total: total, connections: 7, minChunkBytes: 1)) {
        for (int i = range.start; i <= range.end; i++) {
          expect(covered.add(i), isTrue, reason: '字节 $i 被重复覆盖');
        }
      }
      expect(covered.length, total);
    });

    test('小文件不开一堆连接：每片不小于 minChunkBytes', () {
      final List<OgLByteRange> plan = OgLChunkPlan.of(
        total: 3 * 1024 * 1024,
        connections: 8,
        minChunkBytes: 1 << 20,
      );
      expect(plan.length, 3, reason: '3 MB / 1 MB = 3 片，不该开 8 个小分片');
    });

    test('并发越大片越多（但不超过并发数）', () {
      const int total = 100 * 1024 * 1024;
      for (final int connections in <int>[1, 2, 4, 8]) {
        final List<OgLByteRange> plan = OgLChunkPlan.of(
          total: total,
          connections: connections,
          minChunkBytes: 1 << 20,
        );
        expect(plan.length, lessThanOrEqualTo(connections));
        expect(plan.length, greaterThan(0));
      }
    });

    test('并发 <= 0 视为单分片（不崩）', () {
      final List<OgLByteRange> plan = OgLChunkPlan.of(
        total: 5 * 1024 * 1024,
        connections: 0,
        minChunkBytes: 1,
      );
      expect(plan.length, 1);
      expect(plan.single.start, 0);
      expect(plan.single.end, 5 * 1024 * 1024 - 1);
    });
  });

  group('OgLRangeCancelToken', () {
    test('取消后 isCancelled 为真（分片据此退出）', () {
      final OgLRangeCancelToken token = OgLRangeCancelToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });
}
