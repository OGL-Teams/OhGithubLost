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
/// 3. **明暗自适应**：跟随系统 `platformBrightness`，避免深色系统下白屏刺眼；
/// 4. **不做假进度**：只显示不确定进度环——启动耗时无法预知，画百分比是撒谎。
library;

import 'package:flutter/material.dart';

import '../util/og_l_space.dart';

/// 启动占位屏。
class OgLBootSplash extends StatelessWidget {
  /// 创建。
  const OgLBootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    final bool dark = brightness == Brightness.dark;
    final Color bg = dark ? const Color(0xFF101418) : const Color(0xFFFBFCFE);
    final Color fg = dark ? const Color(0xFFCEDACD) : const Color(0xFF3A424C);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.hub_outlined, size: 56, color: fg),
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
