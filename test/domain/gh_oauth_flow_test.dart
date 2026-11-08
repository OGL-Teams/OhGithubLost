/// L2 中枢级 · OAuth Device Flow 契约回归（批8 交叉审计补充）。
///
/// 离线断言范围：Client ID 守卫与 GhOAuthCode 契约——端点常量为
/// gh_oauth_io.dart 文件级私有（不可直接断言），真实 HTTP 往返由登录页
/// 现场执行，端点语义以 GitHub 官方文档裁决。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/gh/gh_oauth.dart';
