/// [browser_notify.dart] 的 **Web 实现**：直接使用浏览器的 `Notification`。
///
/// ## 只用 `dart:js_interop`
/// 不引入 `package:web`（依赖清单纪律，见 `web_install_web.dart` 的说明）。
/// 选项对象用 `jsify()` 把 Dart `Map` 直接转成 JS 对象，避免再开一个 unsafe
/// 转义口。
///
/// ## 诚实原则
/// - 浏览器没有 `Notification` → `unsupported`（**不是** `denied`）；
/// - 申请授权返回什么就报什么；
/// - 构造通知抛异常 → 返回 `false`（"没发出去"），绝不假装成功。
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

/// 浏览器的 `Notification` 构造器视图。
///
/// 名称用 `@JS('Notification')` 映射到全局构造器；`external static` 成员对应
/// `Notification.permission` / `Notification.requestPermission()`。
@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  /// `new Notification(title, options)`。
  external factory _Notification(String title, JSObject options);

  /// `Notification.permission`：`granted` / `denied` / `default`。
  external static String get permission;

  /// `Notification.requestPermission()` → `Promise<string>`。
  external static JSPromise<JSString> requestPermission();
}

/// `navigator.permissions` 的最小视图（只声明 `query` 一个用到的成员）。
///
/// `query({name:'notifications'})` 返回 `Promise<PermissionStatus>`；
/// `PermissionStatus.state` 是 `'granted'` / `'denied'` / `'prompt'` 之一。
@JS('navigator.permissions')
external _NavigatorPermissions get _navigatorPermissions;

extension type _NavigatorPermissions._(JSObject _) implements JSObject {
  /// `navigator.permissions.query(permissionDescriptor)` → `Promise<PermissionStatus>`。
  external JSPromise<JSObject> query(JSObject permissionDescriptor);
}

/// 浏览器是否提供通知能力。
///
/// 判定方式是**直接读一次** `Notification.permission`（见
/// [ogLBrowserNotifyPermission]）：读不到（该浏览器没有 `Notification` 全局，
/// 例如 iOS Safari 16.4 之前）就如实报"不支持"——**不是**"已拒绝"。
bool ogLBrowserNotifySupported() =>
    ogLBrowserNotifyPermission() != 'unsupported';

/// 当前授权状态；读不到一律 `unsupported`（**绝不谎报为已拒绝**）。
String ogLBrowserNotifyPermission() {
  try {
    return _Notification.permission;
  } catch (error) {
    debugPrint('OGL 浏览器通知：读取授权状态失败（$error）');
    return 'unsupported';
  }
}

/// 通过 `navigator.permissions.query({name:'notifications'})` 读取授权状态。
///
/// 与 [ogLBrowserNotifyPermission] 的区别：
/// - **Permissions API**：返回状态对象（含 `state` 字段 `granted` /
///   `denied` / `prompt`），某些浏览器能给出更精确的判定（Safari 把
///   "用户已显式拒绝" 与 "从未问过" 区分得更清楚）；
/// - `Notification.permission` 兜底：Permissions API 不支持时回到
///   直接读 `Notification.permission` 的路径，**结果对齐**
///   [ogLBrowserNotifyPermission] 的命名（`granted` / `denied` /
///   `default` / `unsupported`）。
///
/// ## 失败一律"降级"
/// 浏览器没有 Permissions API、查询抛异常、`state` 字段读不到——
/// 都返回 `'unsupported'`。调用方据此把它当作"未知"，**绝不**谎报
/// 为 `granted` 或 `denied`。
///
/// 供 [system_notifier.dart] 在 Web 上做"用户曾经拒绝过通知"的判定，
/// 与 `Notification.permission` 互为冗余。
///
/// ## 为什么用 `dart:js_interop_unsafe`
/// 项目其余 Web 互操作收敛在 `dart:js_interop`（静态声明），但
/// Permissions API 的 `state` 是**动态读取**的字段 —— `state` 这个名字
/// 在编译期不存在（只活到 `Promise<PermissionStatus>` 这一层）。
/// `dart:js_interop_unsafe` 是 Dart 自带的 `Reflect.get` 出口，**不**引入
/// 第三方包；本项目把它限定在"读动态字段"这一条最小路径上。
Future<String> ogLBrowserNotifyPermissionAsync() async {
  try {
    final JSPromise<JSObject> request = _navigatorPermissions
        .query(<String, Object?>{'name': 'notifications'}.jsify()!
            as JSObject);
    final JSObject status = await request.toDart;
    // `state` 字段：`granted` / `denied` / `prompt`。
    final JSAny? raw = status.getProperty<JSAny?>('state'.toJS);
    final String state = raw?.toString() ?? '';
    switch (state) {
      case 'granted':
        return 'granted';
      case 'denied':
        return 'denied';
      case 'prompt':
        // "尚未问过用户"：与 `Notification.permission` 的 `default` 语义对齐。
        return 'default';
      default:
        return ogLBrowserNotifyPermission();
    }
  } catch (error) {
    debugPrint('OGL 浏览器通知：Permissions API 不可用（回退到 Notification.permission）$error');
    return ogLBrowserNotifyPermission();
  }
}

/// 真实申请一次授权（浏览器会弹自己的授权条）。
Future<String> ogLBrowserNotifyRequest() async {
  try {
    final JSString value = await _Notification.requestPermission().toDart;
    return value.toDart;
  } catch (error) {
    debugPrint('OGL 浏览器通知：申请授权失败（$error）');
    return 'unsupported';
  }
}

/// 发送一条浏览器通知。返回是否**确实**发出。
bool ogLBrowserNotifyShow(String title, String? body) {
  try {
    final JSObject options = <String, Object?>{
      if (body != null && body.isNotEmpty) 'body': body,
    }.jsify()! as JSObject;
    _Notification(title, options);
    return true;
  } catch (error) {
    debugPrint('OGL 浏览器通知：发送失败（$error）');
    return false;
  }
}
