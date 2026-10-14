/// L3 展示级 · 桌面窗口（**桥接**）。
///
/// ## 这一文件现在是"兼容层"，不再是实现
/// 实现已下沉到平台层 `lib/platform/`：
/// - 契约：`lib/platform/window_capability.dart`
/// - Windows / Linux / macOS：各自一份**纯 Dart** 实现
/// - 移动端 / Web / 未知：空操作实现
/// - 选平台：`lib/platform/platform.dart`（**全项目唯一** `Platform.isXxx`）
///
/// 这里**只保留**三件事，保证上层调用点零改动：
/// 1. 原有的函数名 / 枚举 / 常量（原样转发）；
/// 2. 标题栏与外框两个 Widget（纯展示，属展示层职责）；
/// 3. 静默降级（桌面环境千差万别，绝不外抛）。
///
/// ## 为什么原生标题不再需要 C++ 注入
/// 原先由 `tool/inject_desktop_shell.py` 改 `Runner.rc` / `main.cpp` 来设置
/// 任务栏标题。实际上 `windowManager.setTitle()` 写的**就是**窗口管理器读的
/// 那个标题，注入是重复劳动 —— 现已删除，标题由 Dart 唯一负责。
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../platform/platform.dart';
import '../../platform/window_capability.dart';

export '../../platform/window_capability.dart' show OgLWindowDecoration;

/// 当前是否为桌面平台（Windows / Linux / macOS）。
bool get ogLIsDesktopPlatform => ogLWindow.isDesktop;

/// 标题栏高度（自绘）。
const double kOgLTitleBarHeight = 38;

/// 首次初始化窗口：标题、装饰模式、最小尺寸。
Future<void> ogLInitDesktopWindow({
  OgLWindowDecoration decoration = OgLWindowDecoration.custom,
}) async {
  if (!ogLIsDesktopPlatform) {
    return;
  }
  // 桌面环境千差万别（平铺 WM / 精简会话可能不支持）→ 绝不外抛。
  await _guard(() => ogLWindow.init(decoration: decoration));
}

/// 应用（或回退）窗口装饰。切换即时生效。
Future<void> ogLApplyWindowDecoration(OgLWindowDecoration decoration) async {
  if (!ogLIsDesktopPlatform) {
    return;
  }
  await _guard(() => ogLWindow.applyDecoration(decoration));
}

/// 静默执行：把平台差异吞掉，只留日志。
Future<void> _guard(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    debugPrint('OGL 桌面窗口：操作失败（已降级为系统装饰）：$error');
  }
}

/// 自绘标题栏：拖拽区 + 应用名 + 最小化 / 最大化 / 关闭。
///
/// 用 Material 的 `InkWell` 提供反馈（不引入自定时长，动效门禁安全）。
class OgLTitleBar extends StatefulWidget implements PreferredSizeWidget {
  /// 创建标题栏。
  const OgLTitleBar({super.key, this.title = 'OhGithubLost'});

  /// 标题文案（原生标题由窗口管理器另设）。
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kOgLTitleBarHeight);

  @override
  State<OgLTitleBar> createState() => _OgLTitleBarState();
}

class _OgLTitleBarState extends State<OgLTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (ogLIsDesktopPlatform) {
      windowManager.addListener(this);
      _sync();
    }
  }

  @override
  void dispose() {
    if (ogLIsDesktopPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final bool value = await ogLWindow.isMaximized();
      if (mounted && value != _maximized) {
        setState(() => _maximized = value);
      }
    } catch (_) {
      // 取不到就保持原状。
    }
  }

  @override
  void onWindowMaximize() => _sync();

  @override
  void onWindowUnimize() => _sync();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SizedBox(
        height: kOgLTitleBarHeight,
        child: Row(
          children: <Widget>[
            // 拖拽区：按住标题栏任意空白处拖动窗口；双击切换最大化。
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => ogLWindow.startDragging(),
                onDoubleTap: () => _toggleMaximize(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      key: const ValueKey<String>('ogl_title_bar_title'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _button(
              context,
              icon: Icons.remove,
              onTap: ogLWindow.minimize,
            ),
            _button(
              context,
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              onTap: _toggleMaximize,
            ),
            _button(
              context,
              icon: Icons.close,
              onTap: ogLWindow.close,
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      await ogLWindow.setMaximized(!_maximized);
      await _sync();
    } catch (_) {
      // 忽略。
    }
  }

  Widget _button(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: kOgLTitleBarHeight,
        child: Icon(
          icon,
          size: 16,
          color: danger ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 桌面窗口外框：把**自绘标题栏**套在整棵界面之上。
///
/// - 非桌面平台 / 选择系统装饰时 → **原样返回**子组件（零开销、零影响）；
/// - 桌面 + 自绘 → `Column(标题栏, Expanded(内容))`。
class OgLWindowFrame extends StatefulWidget {
  /// 创建外框。
  const OgLWindowFrame({
    required this.child,
    this.decoration = OgLWindowDecoration.custom,
    super.key,
  });

  /// 内容。
  final Widget child;

  /// 装饰模式。
  final OgLWindowDecoration decoration;

  @override
  State<OgLWindowFrame> createState() => _OgLWindowFrameState();
}

class _OgLWindowFrameState extends State<OgLWindowFrame> {
  @override
  void initState() {
    super.initState();
    // 首次进入即把窗口设置落实（避免"先闪一下系统标题栏"）。
    ogLInitDesktopWindow(decoration: widget.decoration);
  }

  @override
  void didUpdateWidget(OgLWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decoration != widget.decoration) {
      ogLApplyWindowDecoration(widget.decoration);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ogLIsDesktopPlatform || widget.decoration != OgLWindowDecoration.custom) {
      return widget.child;
    }
    return Column(
      children: <Widget>[
        const OgLTitleBar(),
        Expanded(child: widget.child),
      ],
    );
  }
}