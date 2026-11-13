/// L1 底座级 · 发布后复查回归锁（12.6.1）。
///
/// 1. 重定向守卫与 DNS 结果过滤共用同一份「禁止直连 IP」判定；
/// 2. 下载重名裁决后，页面名 / spec / 快照落盘路径三者必须一致
///    （只改显示名会覆盖用户既有文件）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/net_transport.dart';

void main() {
  group('ogLIsBlockedLiteralIp（私网 / 元数据 / 回环）', () {
    test('IPv4 禁止段全部拦下', () {
      const List<String> blocked = <String>[
        '10.0.0.1',
        '127.0.0.1',
        '0.0.0.0',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.1',
        '169.254.169.254',
        '100.64.0.1',
        '100.127.255.255',
      ];
      for (final String ip in blocked) {
        expect(ogLIsBlockedLiteralIp(ip), isTrue, reason: ip);
      }
    });

    test('IPv4 公网段放行', () {
      for (final String ip in <String>[
        '1.1.1.1',
        '8.8.8.8',
        '172.32.0.1',
        '100.128.0.1',
        '192.169.1.1'
      ]) {
        expect(ogLIsBlockedLiteralIp(ip), isFalse, reason: ip);
      }
    });

    test('IPv6 回环 / 链路本地 / 唯一本地 / IPv4 映射私网拦下', () {
      for (final String ip in <String>[
        '::1',
        '::',
        'fe80::1',
        'fc00::1',
        'fd00::1',
        '::ffff:192.168.1.1',
        '::ffff:169.254.169.254',
      ]) {
        expect(ogLIsBlockedLiteralIp(ip), isTrue, reason: ip);
      }
    });

    test('域名不是字面量 IP，交给 TLS 证书校验兜底', () {
      expect(ogLIsBlockedLiteralIp('api.github.com'), isFalse);
      expect(ogLIsBlockedLiteralIp('localhost.localdomain'), isFalse);
    });
  });
}
