/// 不依赖第三方包的安全回归入口，便于受限环境离线验证。
library;

import '../test/support/ai_safety_cases.dart';

Future<void> main() async {
  var passed = 0;
  for (final entry in aiSafetyCases().entries) {
    await entry.value();
    passed++;
  }
  // 命令行自检需要输出结果，属于工具而不是产品日志。
  // ignore: avoid_print
  print('AI safety self-test: $passed passed');
}
