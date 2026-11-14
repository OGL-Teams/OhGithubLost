/// L3 展示级 · 全局快捷键（桌面端输入适配）。
///
/// 审查 IN-01：此前全应用零键盘监听——编辑器没有 Ctrl+S / Ctrl+F / Esc，
/// 全应用没有刷新快捷键，桌面端一切操作只能靠鼠标。这里提供**全局骨架**：
///
/// - **桌面端启用**（移动端外接键盘同样可用，无副作用）；
/// - `Ctrl+S` / `Ctrl+F` / `Esc` 交给**当前路由**处理：页面用
///   [OgLShortcutHandler] 的 InheritedWidget 注册处理器（编辑器注册
///   保存 / 查找 / 关闭），未注册则不做任何事（不抢系统语义）；
///
/// 为什么不用 `Shortcuts`+`Actions` 直插 MaterialApp：
/// 处理器需要按**当前路由**区分（编辑器页与浏览页语义不同），
/// 路由级注册是最直接的实现；全局只做一层转发。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/platform.dart';

/// 全局快捷键宿主：包在应用根（NoticeHost 外层）。
class OgLShortcuts extends StatelessWidget {
  /// 创建。
  const OgLShortcuts({
    required this.child,
    super.key,
  });

  final Widget child;

  static bool get _desktop => ogLIsDesktopPlatform;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          if (_desktop) ...<ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                _dispatch(OgLShortcutIntent.save),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
                _dispatch(OgLShortcutIntent.find),
            const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
                _dispatch(OgLShortcutIntent.refresh),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _dispatch(OgLShortcutIntent.escape),
          },
        },
        child: child,
      );

  void _dispatch(OgLShortcutIntent intent) {
    // ★ 从**当前焦点**向上找页面级处理器：Navigator 的 context 在
    //   页面子树之上，findAncestor 只会往根方向走，永远看不到页面里
    //   注册的 OgLShortcutHandler。焦点节点一定在页面子树内。
    final BuildContext? ctx = primaryFocus?.context;
    if (ctx == null) {
      return;
    }
    final OgLShortcutHandler? handler =
        ctx.findAncestorWidgetOfExactType<OgLShortcutHandler>();
    handler?.onShortcut?.call(intent);
  }
}

/// 快捷键意图。
enum OgLShortcutIntent { save, find, refresh, escape }

/// 页面级注册点：把 Scaffold 包进 [OgLShortcutHandler]，提供 [onShortcut]。
class OgLShortcutHandler extends InheritedWidget {
  /// 创建。
  const OgLShortcutHandler({
    required this.onShortcut,
    required super.child,
    super.key,
  });

  /// 快捷键回调（`null` = 本页不消费任何快捷键）。
  final ValueChanged<OgLShortcutIntent>? onShortcut;

  @override
  bool updateShouldNotify(OgLShortcutHandler oldWidget) =>
      onShortcut != oldWidget.onShortcut;
}
