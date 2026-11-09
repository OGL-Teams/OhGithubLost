/// L3 展示级 · [web_install.dart] 的**非 Web 空实现**。
///
/// 非 Web 构建由条件导入选到本文件：所有函数都是"不生效"，且本文件
/// **不引用 `dart:js_interop`**——否则原生构建直接编译不过。
///
/// 注意：判定式（是否为 Web、是否 Chromium、是否 standalone）由
/// `web_install.dart` 门面统一收口，这里只提供"什么都不做"的底座。
library;

/// 非 Web：永远不是 Chromium 家族。
bool ogLWebInstallChromium() => false;

/// 非 Web：永远不是 standalone（没有"已安装的 Web 应用"这一说）。
bool ogLWebInstallStandalone() => false;

/// 非 Web：永远没有可用的安装事件。
bool ogLWebInstallCanPrompt() => false;

/// 非 Web：空操作，不注册任何监听（`onAvailable` 永不回调——原生平台没有
/// 浏览器安装事件，这正是"不生效的空实现"）。
void ogLWebInstallWatch(void Function() onAvailable) {}

/// 非 Web：没有安装提示可触发。
Future<String> ogLWebInstallPrompt() async => 'unavailable';
