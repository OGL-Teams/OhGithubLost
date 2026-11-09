/// L3 展示级 · [web_install.dart] 的 **Web 实现**（只用 `dart:js_interop`，不引入第三方包）。
///
/// ## 为什么手写 extension type 而不用 `package:web`
/// 本项目依赖清单"只保留真的被 import 到的包"；这里只用到 `window` /
/// `navigator` / `matchMedia` / `beforeinstallprompt` 四个成员，手写最小视图
/// 比新增一个依赖更划算（新增依赖还会牵动九条构建腿）。
///
/// ## 失败一律"降级"而不是"谎报"
/// 任何一步 JS 读不到（浏览器不给、事件没派发、用户已经拒绝过）都返回
/// `false` / `unavailable`，绝不假装成功。
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

/// 全局 `window`。
@JS('window')
external _Window get _window;

/// 已捕获的 `beforeinstallprompt` 事件（**一次性**，用过即弃）。
_BeforeInstallPromptEvent? _deferredPrompt;

/// `Window` 的最小视图（只声明本模块用到的成员）。
extension type _Window._(JSObject _) implements JSObject {
  /// `window.navigator`。
  external _Navigator get navigator;

  /// `window.matchMedia(query)`。
  external _MediaQueryList matchMedia(String query);

  /// `window.addEventListener(type, listener)`。
  external void addEventListener(String type, JSFunction listener);
}

/// `Navigator` 的最小视图。
extension type _Navigator._(JSObject _) implements JSObject {
  /// `navigator.userAgent`。
  external String get userAgent;

  /// `navigator.standalone`：**只有 iOS Safari 有**，其它浏览器为 `undefined`。
  external bool? get standalone;
}

/// `MediaQueryList` 的最小视图。
extension type _MediaQueryList._(JSObject _) implements JSObject {
  /// `MediaQueryList.matches`。
  external bool get matches;
}

/// `BeforeInstallPromptEvent` 的最小视图。
extension type _BeforeInstallPromptEvent._(JSObject _) implements JSObject {
  /// 阻止浏览器自带的"迷你安装条"，改由我们自己的界面决定何时弹。
  external void preventDefault();

  /// `prompt()` → `Promise<{outcome, platform}>`。
  external JSPromise<_InstallChoice> prompt();
}

/// `prompt()` 的兑现值。
extension type _InstallChoice._(JSObject _) implements JSObject {
  /// `accepted` 或 `dismissed`。
  external String get outcome;
}

/// 浏览器是否为 **Chromium 家族**（`beforeinstallprompt` 只有它有）。
///
/// iOS 上的 Chrome（UA 含 `crios`）与 Firefox（`fxios`）**都不派发**该事件，
/// 因此这里明确排除——否则会给出一条根本弹不出来的提示。
bool ogLWebInstallChromium() {
  try {
    final String ua = _window.navigator.userAgent.toLowerCase();
    if (ua.contains('crios') || ua.contains('fxios')) {
      return false;
    }
    return ua.contains('chrome') ||
        ua.contains('chromium') ||
        ua.contains('edg/');
  } catch (error) {
    debugPrint('OGL Web 安装：读取 UA 失败（按非 Chromium 处理）$error');
    return false;
  }
}

/// 是否已作为"已安装应用"运行（standalone 显示模式，或 iOS 的 `navigator.standalone`）。
bool ogLWebInstallStandalone() {
  try {
    if (_window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    if (_window.navigator.standalone == true) {
      return true;
    }
  } catch (error) {
    // 读不到就按"未安装"处理：宁可多提示一次，也不谎报"已安装"而不再提示。
    debugPrint('OGL Web 安装：standalone 判定失败（按未安装处理）$error');
  }
  return false;
}

/// 是否已经抓到可用的安装事件。
bool ogLWebInstallCanPrompt() => _deferredPrompt != null;

/// 监听 `beforeinstallprompt`（**只派发一次，务必尽早挂**）。
void ogLWebInstallWatch(void Function() onAvailable) {
  try {
    _window.addEventListener(
      'beforeinstallprompt',
      ((JSObject event) {
        final _BeforeInstallPromptEvent prompt =
            _BeforeInstallPromptEvent._(event);
        try {
          // 桌面 Chromium 若不阻止，会同时弹出地址栏的安装图标提示。
          prompt.preventDefault();
        } catch (error) {
          debugPrint('OGL Web 安装：preventDefault 失败（继续）$error');
        }
        _deferredPrompt = prompt;
        onAvailable();
      }).toJS,
    );
  } catch (error) {
    // 挂不上监听 = 没有安装事件：不提示，也不谎报。
    debugPrint('OGL Web 安装：监听 beforeinstallprompt 失败$error');
  }
}

/// 触发浏览器安装提示。
///
/// 返回 `accepted` / `dismissed`（用户的选择）/ `unavailable`（没有可用事件）/
/// `error`（调用失败）。事件**只能用一次**，因此无论成败都先清掉它。
Future<String> ogLWebInstallPrompt() async {
  final _BeforeInstallPromptEvent? event = _deferredPrompt;
  if (event == null) {
    return 'unavailable';
  }
  _deferredPrompt = null;
  try {
    final _InstallChoice choice = await event.prompt().toDart;
    return choice.outcome;
  } catch (error) {
    debugPrint('OGL Web 安装：prompt() 调用失败$error');
    return 'error';
  }
}
