/// 展示层异步控制器的一致性协议检查。
///
/// 关键纪律：
/// 1. 空结果与"加载中"**严格区分**（空列出空态，不出转圈）；
/// 2. 失败**必带原因**（界面不允许只说"出错了"）；
/// 3. 刷新失败**不丢旧数据**（softError 提示，内容仍在）；
/// 4. 并发抑制：上一次没回来之前不重复发请求。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/async.dart';
import 'package:ohgithublost/surface/i18n/og_l_i18n.dart';

/// 把 zh 分片注入 i18n 内核（测试环境读不到 assets）。
void _loadZh() {
  final Map<String, Map<String, String>> pages =
      <String, Map<String, String>>{};
  for (final String page in <String>['shell', 'common']) {
    final Object? decoded =
        jsonDecode(File('assets/i18n/zh/$page.json').readAsStringSync());
    pages[page] = <String, String>{
      for (final MapEntry<Object?, Object?> e
          in (decoded as Map<Object?, Object?>).entries)
        '${e.key}': '${e.value}',
    };
  }
  OgLI18n.instance.debugInject('zh', pages);
}

void main() {
  setUpAll(_loadZh);
  test('成功：数据落定、非空、无错误', () async {
    final AsyncController<List<int>> c = AsyncController<List<int>>(
      label: '测试',
      loader: () async => <int>[1, 2, 3],
      isEmpty: (List<int> value) => value.isEmpty,
    );
    await c.load();
    expect(c.data, <int>[1, 2, 3]);
    expect(c.isEmptyResult, isFalse);
    expect(c.softError, isNull);
    expect(c.failureMessage, isNull);
  });

  test('空结果：isEmptyResult 为真（不是加载中）', () async {
    final AsyncController<List<int>> c = AsyncController<List<int>>(
      label: '测试',
      loader: () async => const <int>[],
      isEmpty: (List<int> value) => value.isEmpty,
    );
    await c.load();
    expect(c.isEmptyResult, isTrue);
    expect(c.isFirstLoading, isFalse);
    expect(c.data, isNotNull);
  });

  test('失败：带原因、可重试成功', () async {
    int calls = 0;
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () async {
        calls += 1;
        if (calls == 1) {
          throw Exception('网络断了');
        }
        return 7;
      },
      isEmpty: (int value) => false,
    );
    await c.load();
    expect(c.data, isNull);
    expect(c.failureMessage, isNotNull);
    // 用户提示只给可理解的原因，原始异常文本不外泄。
    expect(c.failureMessage, isNot(contains('网络断了')));
    expect(c.failureMessage, isNotEmpty);

    await c.load();
    expect(c.data, 7);
    expect(c.failureMessage, isNull);
  });

  test('刷新失败：保留旧数据（softError），可清除', () async {
    int calls = 0;
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () async {
        calls += 1;
        if (calls == 2) {
          throw Exception('刷新炸了');
        }
        return 1;
      },
      isEmpty: (int value) => false,
    );
    await c.load();
    expect(c.data, 1);

    await c.load();
    expect(c.data, 1, reason: '旧数据必须还在');
    expect(c.softError, isNotNull);

    c.dismissError();
    expect(c.softError, isNull);
  });

  test('并发抑制：重入不产生第二个请求', () async {
    int calls = 0;
    final Completer<int> gate = Completer<int>();
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () {
        calls += 1;
        return gate.future;
      },
      isEmpty: (int value) => false,
    );
    final Future<void> first = c.load();
    final Future<void> second = c.load();
    gate.complete(5);
    await Future.wait(<Future<void>>[first, second]);
    expect(calls, 1);
    expect(c.data, 5);
  });

  test('loadIfNeeded：已加载过不重复', () async {
    int calls = 0;
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () async {
        calls += 1;
        return 1;
      },
      isEmpty: (int value) => false,
    );
    await c.loadIfNeeded();
    await c.loadIfNeeded();
    expect(calls, 1);
  });

  test('dispose 后：在途请求回来不再通知（不触发 ChangeNotifier 断言）', () async {
    // 搜索页换模式 / gist 详情页退出时会 `dispose()` 旧控制器，而在途请求
    // 仍会走 `finally` 里的通知路径 —— 没有 `_disposed` 守卫时 debug 下
    // 直接断言崩溃（"A AsyncController was used after being disposed"）。
    final Completer<int> gate = Completer<int>();
    final AsyncController<int> c = AsyncController<int>(
      label: '测试',
      loader: () => gate.future,
      isEmpty: (int value) => false,
    );
    int notified = 0;
    c.addListener(() => notified += 1);
    final Future<void> pending = c.load();
    expect(c.isLoading, isTrue);
    c.dispose();
    gate.complete(42);
    // 不抛 = 通过：守卫拦住了 dispose 之后的 notifyListeners。
    await pending;
    expect(notified, 1, reason: '只有 dispose 前那次"加载中"通知');
    // 释放后也不该再发起新请求（load / loadIfNeeded 都是空操作）。
    await c.load();
    await c.loadIfNeeded();
    expect(notified, 1);
  });
}
