/// L2 中枢级 · 列表响应严格解析回归（B3 交叉审计补充）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/gh/gh_client.dart';

GhResponse _resp(String body) => GhResponse(
      statusCode: 200,
      body: body,
      headers: const <String, String>{},
    );

void main() {
  test('合法数组正常解析', () {
    expect(_resp('[{"name":"a"},{"name":"b"}]').jsonList.length, 2);
  });

  test('非法 JSON 抛 FormatException，不再静默变空列表', () {
    expect(
      () => _resp('{"name":"a"').jsonList,
      throwsA(isA<FormatException>()),
    );
  });

  test('2xx 单对象不再被伪装成空列表（jsonList 严格拒绝）', () {
    expect(
      () => _resp('{"message":"Not Found"}').jsonList,
      throwsA(isA<FormatException>()),
    );
  });

  test('数组里混入非对象条目一律拒绝', () {
    expect(
      () => _resp('[{"name":"a"},3]').jsonList,
      throwsA(isA<FormatException>()),
    );
  });

  test('jsonAsList 单对象仍作为一条记录返回（合法形态）', () {
    expect(_resp('{"message":"Not Found"}').jsonAsList.length, 1);
  });
}
