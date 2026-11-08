/// L1 底座级 · 网络连接测试。
///
/// 覆盖：重试策略分支、镜像通道改写、韧性传输编排（重试 / 镜像回落 /
/// 不可重试直达）、观测计数、请求复制。
/// 全部离线运行——不发出任何真实请求。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/net_mirror.dart';
import 'package:ohgithublost/base/net/net_retry.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';

NetResponse _ok([String body = 'ok']) => NetResponse(
      statusCode: 200,
      body: body,
      duration: const Duration(milliseconds: 10),
    );

NetResponse _status(int code) => NetResponse(
      statusCode: code,
      body: 'body-$code',
      duration: const Duration(milliseconds: 5),
    );

NetRequest _request([String url = 'https://api.github.com/repos']) =>
    NetRequest(
      method: NetMethod.get,
      url: url,
    );

void main() {
  group('重试策略', () {
    const policy = RetryPolicy(
      maxAttempts: 3,
      baseDelay: Duration(milliseconds: 300),
      maxDelay: Duration(seconds: 8),
      jitterRatio: 0,
    );

    test('指数退避：300 → 600 → 放弃', () {
      expect(policy.delayFor(1), const Duration(milliseconds: 300));
      expect(policy.delayFor(2), const Duration(milliseconds: 600));
      expect(policy.delayFor(3), isNull);
    });

    test('超过上限时封顶', () {
      const long = RetryPolicy(
        maxAttempts: 10,
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 5),
        jitterRatio: 0,
      );
      expect(long.delayFor(4), const Duration(seconds: 5));
    });

    test('尊重服务端 Retry-After（并受本地上限约束）', () {
      expect(
        policy.delayFor(1, retryAfter: const Duration(seconds: 2)),
        const Duration(seconds: 2),
      );
      expect(
        policy.delayFor(1, retryAfter: const Duration(minutes: 10)),
        const Duration(seconds: 8),
      );
    });

    test('不可重试的类别直接返回 null', () {
      expect(policy.delayFor(1, kind: NetErrorKind.client), isNull);
      expect(policy.delayFor(1, kind: NetErrorKind.tls), isNull);
      expect(policy.delayFor(1, statusCode: 404), isNull);
      expect(policy.delayFor(1, statusCode: 503), isNotNull);
    });

    test('抖动落在 ±ratio 区间内', () {
      const jittered = RetryPolicy(
        jitterRatio: 0.25,
        baseDelay: Duration(milliseconds: 400),
        maxDelay: Duration(seconds: 8),
      );
      final low = jittered.delayFor(1, jitter: () => 0)!;
      final high = jittered.delayFor(1, jitter: () => 1)!;
      expect(low.inMilliseconds, 300);
      expect(high.inMilliseconds, 500);
    });
  });

  group('镜像通道', () {
    const channel = MirrorChannel(
      id: 'proxy',
      pattern: r'^https://api\.github\.com/(.*)$',
      replacement: r'https://proxy.example/https://api.github.com/$1',
    );

    test('命中时改写 URL，未命中返回 null', () {
      expect(
        channel.apply('https://api.github.com/repos/a/b'),
        'https://proxy.example/https://api.github.com/repos/a/b',
      );
      expect(channel.apply('https://example.com/x'), isNull);
    });

    test('禁用通道不生效', () {
      const disabled = MirrorChannel(
        id: 'off',
        pattern: r'^https://api\.github\.com/(.*)$',
        replacement: r'https://proxy/$1',
        enabled: false,
      );
      expect(disabled.apply('https://api.github.com/repos/a/b'), isNull);
    });

    test('选择器跳过已尝试通道', () {
      final selector = MirrorSelector(
        channels: <MirrorChannel>[
          const MirrorChannel(
            id: 'one',
            pattern: r'^https://api\.github\.com/(.*)$',
            replacement: r'https://one/$1',
          ),
          const MirrorChannel(
            id: 'two',
            pattern: r'^https://api\.github\.com/(.*)$',
            replacement: r'https://two/$1',
          ),
        ],
      );
      final first = selector.mirrorFor('https://api.github.com/x');
      expect(first?.id, 'one');
      final second = selector.mirrorFor(
        'https://api.github.com/x',
        skip: <String>{'one'},
      );
      expect(second?.id, 'two');
      final third = selector.mirrorFor(
        'https://api.github.com/x',
        skip: <String>{'one', 'two'},
      );
      expect(third, isNull);
      expect(selector.channelFor('https://api.github.com/x')?.id, 'one');
    });
  });

  group('韧性传输', () {
    test('503 后重试成功，并记录统计', () async {
      final inner = ScriptedTransport(<Object>[_status(503), _ok('done')]);
      final transport = ResilientTransport(
        inner: inner,
        policy: const RetryPolicy(jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      final response = await transport.send(_request());
      expect(response.statusCode, 200);
      expect(response.body, 'done');
      expect(inner.received.length, 2);

      final stats = transport.observer.snapshot();
      expect(stats.requests, 2);
      expect(stats.retries, 1);
      expect(stats.failures, 0);
    });

    test('连接异常时回落到镜像通道', () async {
      final mirror = MirrorSelector(
        channels: <MirrorChannel>[
          const MirrorChannel(
            id: 'proxy',
            pattern: r'^https://api\.github\.com/(.*)$',
            replacement: r'https://proxy.example/$1',
          ),
        ],
      );
      final inner = ScriptedTransport(<Object>[
        const NetException(NetErrorKind.connection, '断网'),
        _ok('mirrored'),
      ]);
      final transport = ResilientTransport(
        inner: inner,
        mirrors: mirror,
        policy: const RetryPolicy(jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      final response = await transport.send(_request());
      expect(response.body, 'mirrored');
      expect(inner.received.length, 2);
      expect(
        inner.received[1].url,
        'https://proxy.example/repos',
      );
      expect(transport.observer.snapshot().mirrorSwitches, 1);
    });

    test('不可重试错误直接抛出（不浪费尝试次数）', () async {
      final inner = ScriptedTransport(<Object>[
        const NetException(NetErrorKind.client, '未授权', statusCode: 401),
      ]);
      final transport = ResilientTransport(
        inner: inner,
        policy: const RetryPolicy(jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      await expectLater(
        transport.send(_request()),
        throwsA(isA<NetException>()),
      );
      expect(inner.received.length, 1);
      expect(transport.observer.snapshot().failures, 1);
    });

    test('重试耗尽后抛出最后一次错误', () async {
      final inner = ScriptedTransport(<Object>[
        const NetException(NetErrorKind.timeout, '超时'),
        const NetException(NetErrorKind.timeout, '超时'),
        const NetException(NetErrorKind.timeout, '超时'),
      ]);
      final transport = ResilientTransport(
        inner: inner,
        policy: const RetryPolicy(maxAttempts: 3, jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      await expectLater(
        transport.send(_request()),
        throwsA(isA<NetException>()),
      );
      expect(inner.received.length, 3);
    });
  });

  group('类型与观测', () {
    test('请求复制仅覆盖指定字段', () {
      const original = NetRequest(
        method: NetMethod.post,
        url: 'https://a',
        headers: <String, String>{'x': '1'},
        body: 'payload',
        label: 'POST /a',
      );
      final copy = original.copyWith(url: 'https://b');
      expect(copy.url, 'https://b');
      expect(copy.method, NetMethod.post);
      expect(copy.body, 'payload');
      expect(copy.label, 'POST /a');
      expect(copy.headers, original.headers);
    });

    test('响应判定与标签', () {
      expect(_ok().isSuccess, isTrue);
      expect(_status(404).isSuccess, isFalse);
      expect(
        const NetResponse(
          statusCode: 200,
          body: '',
          duration: Duration.zero,
          headers: <String, String>{'etag': 'W/"1"'},
        ).etag,
        'W/"1"',
      );
    });

    test('观测器累计并重置', () {
      final observer = NetObserver();
      observer.onRequest(_request());
      observer.onResponse(_ok('1234'));
      observer.onRetry(_request(), 1, 'boom');
      observer.onMirror(_request(), 'proxy');
      observer.onFailure(_request(), 'err');

      final stats = observer.snapshot();
      expect(stats.requests, 1);
      expect(stats.bytesIn, 4);
      expect(stats.retries, 1);
      expect(stats.mirrorSwitches, 1);
      expect(stats.failures, 1);
      expect(stats.averageLatency.inMilliseconds, 10);
      expect(stats.toJson()['requests'], 1);

      observer.reset();
      expect(observer.snapshot().requests, 0);
    });
  });

  group('安全铁律（幂等与显式失败）', () {
    test('POST 绝不自动重试（防重复创建），且失败必须显式抛出', () async {
      final inner = ScriptedTransport(<Object>[_status(503)]);
      final transport = ResilientTransport(
        inner: inner,
        policy: const RetryPolicy(jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      await expectLater(
        transport.send(
          const NetRequest(
            method: NetMethod.post,
            url: 'https://api.github.com/repos/o/r/releases',
          ),
        ),
        throwsA(isA<NetException>()),
      );
      expect(inner.received.length, 1, reason: '非幂等请求只能发出一次');
    });

    test('多镜像依次尝试，用尽后回落直连（换通道不吃重试预算）', () async {
      final inner = ScriptedTransport(<Object>[
        _status(503), // 直连失败 → 换 m1
        _status(503), // m1 失败 → 换 m2
        _status(503), // m2 失败 → 回落直连
        _ok('done'), // 直连成功
      ]);
      final observer = NetObserver();
      final transport = ResilientTransport(
        inner: inner,
        observer: observer,
        sleep: (Duration _) async {},
        mirrors: MirrorSelector(channels: const <MirrorChannel>[
          MirrorChannel(
            id: 'm1',
            pattern: r'^https://api\.github\.com/(.*)$',
            replacement: r'https://m1.example/$1',
          ),
          MirrorChannel(
            id: 'm2',
            pattern: r'^https://api\.github\.com/(.*)$',
            replacement: r'https://m2.example/$1',
          ),
        ]),
      );

      final response = await transport.send(
        NetRequest(url: 'https://api.github.com/user', method: NetMethod.get),
      );

      expect(response.statusCode, 200);
      expect(
        inner.received.map((NetRequest r) => r.url).toList(),
        <String>[
          'https://api.github.com/user',
          'https://m1.example/user',
          'https://m2.example/user',
          'https://api.github.com/user',
        ],
        reason: '必须走完所有通道并**回到直连**，不能卡在第一条镜像上',
      );
      expect(observer.snapshot().mirrorSwitches, 2);
    });

    test('GET 重试耗尽必须抛错，绝不把 503 当正常响应', () async {
      final inner = ScriptedTransport(<Object>[
        _status(503),
        _status(503),
        _status(503),
      ]);
      final transport = ResilientTransport(
        inner: inner,
        policy: const RetryPolicy(maxAttempts: 3, jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      await expectLater(
        transport.send(_request()),
        throwsA(
          isA<NetException>().having(
            (NetException error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
      expect(inner.received.length, 3);
    });

    test('语义性 4xx 原样返回（不重试、不抛错，交上层判断）', () async {
      final inner = ScriptedTransport(<Object>[_status(404)]);
      final transport = ResilientTransport(
        inner: inner,
        policy: const RetryPolicy(jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      final response = await transport.send(_request());
      expect(response.statusCode, 404);
      expect(inner.received.length, 1);
    });

    test('非幂等方法也不走镜像回落', () async {
      final inner = ScriptedTransport(<Object>[
        const NetException(NetErrorKind.connection, '断网'),
      ]);
      final transport = ResilientTransport(
        inner: inner,
        mirrors: MirrorSelector(
          channels: <MirrorChannel>[
            const MirrorChannel(
              id: 'proxy',
              pattern: r'^https://api\.github\.com/(.*)$',
              replacement: r'https://proxy.example/$1',
            ),
          ],
        ),
        policy: const RetryPolicy(jitterRatio: 0),
        sleep: (Duration _) async {},
      );

      await expectLater(
        transport.send(
          const NetRequest(
            method: NetMethod.patch,
            url: 'https://api.github.com/repos/o/r',
          ),
        ),
        throwsA(isA<NetException>()),
      );
      expect(inner.received.length, 1);
      expect(transport.observer.snapshot().mirrorSwitches, 0);
    });
  });
}
