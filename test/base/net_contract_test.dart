/// L1 底座级 · 网络契约回归测试（B1 交叉审计补充）。
///
/// 三方命中（B1-A-03 / B1-B-12 / B1-C-09）：Retry-After 的 HTTP-date 旧实现
/// 用 `DateTime.parse` 必失败；`NetRequest.timeout` 是死字段。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/net_types.dart';

/// B1 交叉审计补充：Retry-After 的 HTTP-date 与 NetRequest.timeout 契约。
///
/// 三方命中（B1-A-03 / B1-B-12 / B1-C-09）：
/// - 旧实现用 `DateTime.parse` 解析 `Wed, 21 Oct 2015 07:28:00 GMT`
///   必抛 FormatException，Retry-After 分支完全失效；
/// - `NetRequest.timeout` 是死字段（调用方 30s 实际挂 60s）。
void main() {
  group('B1 交叉修复 · 契约生效', () {
    test('Retry-After: delta-seconds 原样解析', () {
      expect(parseRetryAfterHeader('60'), const Duration(seconds: 60));
      expect(parseRetryAfterHeader('0'), Duration.zero);
      expect(parseRetryAfterHeader(null), isNull);
      expect(parseRetryAfterHeader(''), isNull);
    });

    test('Retry-After: IMF-fixdate 能解析成非负等待', () {
      // 用未来时间点，断言不再是 null（旧实现恒为 null）。
      final DateTime future =
          DateTime.now().toUtc().add(const Duration(hours: 2));
      final String httpDate = _formatHttpDate(future);
      final Duration? delay = parseRetryAfterHeader(httpDate);
      expect(delay, isNotNull, reason: 'HTTP-date 必须能解析');
      expect(delay!.inMinutes, greaterThanOrEqualTo(115));
    });

    test('Retry-After: 非法值返回 null，不抛异常', () {
      expect(parseRetryAfterHeader('not-a-date'), isNull);
      expect(parseRetryAfterHeader('Wed, 99 Xxx 9999 99:99:99 GMT'), isNull);
    });

    test('NetRequest.timeout 由调用方决定，copyWith 保留', () {
      final NetRequest request = NetRequest(
        method: NetMethod.get,
        url: 'https://api.github.com/repos',
        timeout: Duration(seconds: 12),
      );
      expect(request.timeout, const Duration(seconds: 12));
      expect(request.copyWith().timeout, const Duration(seconds: 12));
    });
  });
}

/// 生成 IMF-fixdate（RFC 7231 §7.1.1.1），供测试构造未来时间。
String _formatHttpDate(DateTime utc) {
  const List<String> weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${weekdays[utc.weekday - 1]}, ${two(utc.day)} '
      '${months[utc.month - 1]} ${utc.year} '
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
}
