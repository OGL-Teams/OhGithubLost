/// L3 展示级 · [browser_notify.dart] 的**非 Web 空实现**。
///
/// 原生平台的通知走 `permission_handler` / `flutter_local_notifications`
/// （见 `permissions.dart` 与 `system_notifier.dart`），与浏览器通知无关；
/// 因此这里一律返回"不支持 / 不适用"，且**不引用任何 Web API**。
library;

/// 非 Web：没有浏览器通知能力。
bool ogLBrowserNotifySupported() => false;

/// 非 Web：不适用。
String ogLBrowserNotifyPermission() => 'unsupported';

/// 非 Web：不适用（原生平台的通知授权由 `permission_handler` 负责）。
Future<String> ogLBrowserNotifyRequest() async => 'unsupported';

/// 非 Web：不发送，并**如实**返回 `false`。
bool ogLBrowserNotifyShow(String title, String? body) => false;
