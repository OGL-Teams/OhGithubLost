/// L1 硬件层 · `WindowListener` 的**平台隔离壳**。
///
/// ## 为什么需要这个文件
/// `window_manager` 的入口库**无条件 `import 'dart:io'`**，且它不声明
/// web 平台 —— Web 构建里只要有一处 `import 'package:window_manager/...'`
/// （哪怕运行时永远走不到），dart2wasm / dart2js 的编译就会因 `dart:io`
/// 不可用而直接失败。
///
/// ## 做法
/// 用条件导入把"有 window_manager 的平台"与"没有的平台"分开：
/// - 原生侧转出真实的 [WindowListener]；
/// - Web 侧给一个**同名同签名的空实现**（所有回调都是空方法），
///   调用点（自绘标题栏的最大化监听）在 Web 上永远不会被触发
///   （`ogLIsDesktopPlatform == false` 时调用点本身已短路），
///   所以空实现是安全的。
library;

/// 真实的 window_manager 入口（仅原生平台编译）。
export 'window_listener_native.dart'
    if (dart.library.js_interop) 'window_listener_web.dart';
