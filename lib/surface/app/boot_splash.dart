/// L3 · 启动占位屏（**冷启动首帧**）。
///
/// ## 为什么需要它
/// `main()` 在 `runApp` 之前必须完成若干 `await`：日志落盘初始化、平台存储
/// 解析、内核引导（信任链校验）、权限自检。这些合计可能几百毫秒到数秒——
/// 期间如果**不先渲染任何东西**，用户看到的是系统 splash 之后的一片空白
/// （或直接白屏），观感等同于"应用卡住了"。
///
/// 本组件在**第一帧**就渲染出来（不依赖 i18n 分片、不依赖内核/桥、不依赖
/// 任何磁盘资源），随后真正的 [OgLApp] 会通过第二次 `runApp` 顶替它。
///
/// ## 设计约束（务必遵守）
/// 1. **零依赖**：只 import `flutter/material.dart` 与 `theme.dart` 的顶层
///    const 令牌——不触发 i18n / 桥 / 磁盘加载；
/// 2. **零动效依赖**：不读档位质量表（那要内核），只用固定时长的
///    `CircularProgressIndicator`（框架自带）；
/// 4. **启动锚定色**：从 `theme.dart` 顶层常量取 surface / onSurfaceVariant，
///    与正式主题同源同值；用户强制亮/暗偏好在设置落盘后由正式主题接管。
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';

/// 启动占位屏。
class OgLBootSplash extends StatelessWidget {
  /// 创建。
  const OgLBootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    // ★ B-08：锚定色常量在 theme.dart 定义，buildOgLTheme 与首帧共用同一
    //   事实源；首帧按系统亮度，用户偏好落盘后由正式主题覆盖。
    final bool dark = brightness == Brightness.dark;
    final Color bg = dark ? kOgLSurfaceDark : kOgLSurfaceLight;
    final Color fg =
        dark ? kOgLOnSurfaceVariantDark : kOgLOnSurfaceVariantLight;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.hub_outlined, size: OgLIconSize.hero, color: fg),
              const SizedBox(height: OgLSpace.xl),
              Text(
                'OhGithubLost',
                style: TextStyle(
                  color: fg,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: OgLSpace.xxl),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
