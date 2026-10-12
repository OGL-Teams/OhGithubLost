/// 安全回归：确认、账号隔离、冲突、原子提交、回滚与多 API 协议。
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/ai_safety_cases.dart';

void main() {
  for (final entry in aiSafetyCases().entries) {
    test(entry.key, entry.value);
  }
}
