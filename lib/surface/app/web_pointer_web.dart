/// L3 展示级 · [web_pointer.dart] 的 **Web 实现**（只用 `dart:js_interop`，不引入第三方包）。
///
/// ## 为什么手写 extension type 而不用 `package:web`
/// 与 `web_install_web.dart` 同一套路：这里只用到 `window.matchMedia` 一个成员，
/// 手写最小视图比新增一个依赖更划算（新增依赖还会牵动九条构建腿）。
///
/// ## 失败一律"降级"而不是"谎报"
/// 判定读不到（浏览器不给 / 抛异常）时返回 `false`（按"没有鼠标"处理）：
/// 宁可不提示，也不在触摸设备上弹一段对不上的说明。
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

/// 全局 `window`。
@JS('window')
external _Window get _window;

/// `Window` 的最小视图（只声明本模块用到的成员）。
extension type _Window._(JSObject _) implements JSObject {
  /// `window.matchMedia(query)`。
  external _MediaQueryList matchMedia(String query);
}

/// `MediaQueryList` 的最小视图。
extension type _MediaQueryList._(JSObject _) implements JSObject {
  /// `MediaQueryList.matches`。
  external bool get matches;
}

/// `matchMedia('(pointer: fine)')`：精确指针（鼠标 / 触控板）为 `true`。
///
/// `(pointer: fine)` 的语义是"**主指针**精度高"：鼠标与触控板为真，
/// 触摸屏为假 —— 正是"要不要展示鼠标交互说明"的判据。
bool ogLWebFinePointer() {
  try {
    return _window.matchMedia('(pointer: fine)').matches;
  } catch (error) {
    debugPrint('OGL Web 指针：matchMedia 判定失败（按无鼠标处理）$error');
    return false;
  }
}
