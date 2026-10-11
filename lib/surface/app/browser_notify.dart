/// L3 展示级 · **浏览器通知门面**（本分支 = 纯 Web）。
///
/// ## 为什么单独一个门面
/// 浏览器里的通知权限与发送**只有** `Notification` 这一条路（`dart:io` 的
/// `HttpClient` / 插件都不在）。实现收敛到 `browser_notify_web.dart`
/// （`dart:js_interop`），门面只做转调。
///
/// ## 诚实原则
/// 所有函数**只报告真实结果**：浏览器不支持就说 `unsupported`，
/// 发送失败就返回 `false`，绝不把"没做到"报成"已发送"。
library;

import 'browser_notify_web.dart' as impl;

/// 当前环境是否提供浏览器通知能力（浏览器不支持时为 `false`）。
bool ogLBrowserNotifySupported() => impl.ogLBrowserNotifySupported();

/// 当前通知授权状态：`granted` / `denied` / `default` / `unsupported`。
String ogLBrowserNotifyPermission() => impl.ogLBrowserNotifyPermission();

/// 异步读取通知授权状态（走 `navigator.permissions.query`）。
///
/// 失败回退到 [ogLBrowserNotifyPermission]。见 `browser_notify_web.dart`。
Future<String> ogLBrowserNotifyPermissionAsync() =>
    impl.ogLBrowserNotifyPermissionAsync();

/// **真实申请**一次通知授权（浏览器会弹自己的授权条）。返回申请后的状态。
Future<String> ogLBrowserNotifyRequest() => impl.ogLBrowserNotifyRequest();

/// 发送一条浏览器通知；返回是否**确实**发出（不支持 / 未授权 / 失败 = `false`）。
bool ogLBrowserNotifyShow(String title, String? body) =>
    impl.ogLBrowserNotifyShow(title, body);
