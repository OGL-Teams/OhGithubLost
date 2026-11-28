import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/base/net/net_read_cache.dart';
import 'package:ohgithublost/base/net/net_transport.dart';
import 'package:ohgithublost/base/net/net_types.dart';

NetRequest _get(String url, {Map<String, String> headers = const {}}) =>
    NetRequest(method: NetMethod.get, url: url, headers: headers);

void main() {
  test('同一 GET 第二次命中缓存，不打网络', () async {
    final inner = ScriptedTransport(<Object>[_ok('body-1')]);
    final transport = CacheTransport(inner: inner);

    final first = await transport.send(_get('https://api.github.com/x'));
    final second = await transport.send(_get('https://api.github.com/x'));

    expect(first.body, 'body-1');
    expect(second.body, 'body-1');
    expect(inner.received.length, 1, reason: '第二次必须命中缓存');
    expect(transport.entryCount, 1);
  });

  test('accept 头不同 → 不同缓存键（JSON 与 raw 不互相污染）', () async {
    final inner = ScriptedTransport(<Object>[_ok('json'), _ok('raw')]);
    final transport = CacheTransport(inner: inner);

    await transport.send(_get('https://api.github.com/x',
        headers: {'accept': 'application/vnd.github+json'}));
    final raw = await transport.send(_get('https://api.github.com/x',
        headers: {'accept': 'application/vnd.github.raw'}));

    expect(raw.body, 'raw', reason: '不同 accept 不得命中同一键');
    expect(inner.received.length, 2);
  });

  test('POST 直通且不入缓存', () async {
    final inner = ScriptedTransport(<Object>[
      _ok('a'),
      _ok('b'),
    ]);
    final transport = CacheTransport(inner: inner);
    final post = NetRequest(
      method: NetMethod.post,
      url: 'https://api.github.com/x',
      body: '{}',
    );

    expect((await transport.send(post)).body, 'a');
    expect((await transport.send(post)).body, 'b', reason: '写请求绝不缓存');
    expect(transport.entryCount, 0);
  });

  test('写操作后 invalidate，同 URL 重新回源', () async {
    final inner = ScriptedTransport(<Object>[_ok('old'), _ok('new')]);
    final transport = CacheTransport(inner: inner);

    await transport.send(_get('https://api.github.com/x'));
    transport.invalidate();
    final fresh = await transport.send(_get('https://api.github.com/x'));

    expect(fresh.body, 'new');
    expect(inner.received.length, 2);
  });

  test('带认证头的请求默认不入缓存（保守底线）', () async {
    final inner = ScriptedTransport(<Object>[_ok('a'), _ok('b')]);
    final transport = CacheTransport(inner: inner);
    final authed = _get('https://api.github.com/x',
        headers: {'authorization': 'Bearer t'});

    await transport.send(authed);
    final second = await transport.send(authed);

    expect(second.body, 'b', reason: '认证请求不得命中缓存');
    expect(transport.entryCount, 0);
  });

  test('超过 maxAge 后回源', () async {
    final inner = ScriptedTransport(<Object>[_ok('old'), _ok('new')]);
    final transport = CacheTransport(
      inner: inner,
      maxAge: const Duration(milliseconds: 1),
    );

    await transport.send(_get('https://api.github.com/x'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final fresh = await transport.send(_get('https://api.github.com/x'));

    expect(fresh.body, 'new');
  });

  test('LRU 有界：超出容量淘汰最久未使用', () async {
    final inner = ScriptedTransport(<Object>[
      for (int i = 0; i < 6; i++) _ok('v$i'),
    ]);
    final transport = CacheTransport(inner: inner, maxEntries: 2);

    await transport.send(_get('https://api.github.com/a'));
    await transport.send(_get('https://api.github.com/b'));
    await transport.send(_get('https://api.github.com/c'));

    expect(transport.entryCount, 2);
    // a 已被淘汰 → 回源。
    final again = await transport.send(_get('https://api.github.com/a'));
    expect(again.body, 'v4');
  });
}

NetResponse _ok(String body) => NetResponse(
      statusCode: 200,
      body: body,
      duration: Duration.zero,
    );
