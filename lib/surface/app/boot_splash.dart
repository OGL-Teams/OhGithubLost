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
/// 1. **零依赖**：只 import `flutter/material.dart`——不能碰 i18n、桥、磁盘；
/// 2. **零动效依赖**：不读档位质量表（那要内核），只用固定时长的
///    `CircularProgressIndicator`（框架自带）；
/// 4. **启动锚定色**：不再用与主题脱节的纯黑/纯白——改用与 MD3 seed 色板同族的
///    中性 Surface 色，冷启动首帧 → [OgLApp] 顶替时不闪白（G-06）。
///    中性锚定色取 `ColorScheme.fromSeed` 的 surface（明/暗），与主题同源。
library;

import 'package:flutter/material.dart';

import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';

/// 启动占位屏。
class OgLBootSplash extends StatelessWidget {
  /// 创建。
  const OgLBootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    // ★ G-06 + MD2：锚定色直接取 MD2 色板（与 theme.dart 同源同值），
    //   冷启动首帧与 [OgLApp] 顶替帧不再"闪白/闪黑"。零依赖纯计算。
    final Color bg = brightness == Brightness.dark
        ? const Color(0xFF121212)
        : Colors.white;
    final Color fg = brightness == Brightness.dark
        ? const Color(0xFF8B949E)
        : const Color(0xFF57606A);

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
