/// L3 展示级 · 主题编译（Material 3 + **组件级设计令牌**）。
///
/// ## 为什么这里要写这么多
/// 此前本文件只有 73 行，`buildOgLTheme()` 只设置 `useMaterial3` / `colorScheme` /
/// `visualDensity` 三项 —— 所有组件（卡片、对话框、底部弹层、SnackBar、
/// 按钮、输入框、Chip、分割线、列表项）的**形状 / 内边距 / 高度 / 字号**
/// 全部沿用 Material 默认值。页面一旦偏离默认，就只能就地硬编码，
/// 于是演化出「卡片比弹层还方」「同一角色按钮两处圆角不同」这类问题。
///
/// 现在的原则：
/// 1. **组件级默认值集中在这里定义**，页面不再需要写 `shape` / `padding` / `fontSize`；
/// 2. 页面要偏离时，**改这里而不是改页面**（一处改动全站生效）；
/// 3. 颜色一律走 [ColorScheme] 或 [OgLSemanticColors]，页面不写字面色值。
///
/// ## 令牌来源
/// 圆角来自 [OgLRadius]（xs/sm/md/lg/xl/pill），间距来自 [OgLSpace]
/// （4/8/12/16/24/32/48/64）。两者是**唯二**的几何刻度来源。
library;

import 'package:flutter/material.dart';

import './util/og_l_radius.dart';
import './util/og_l_space.dart';
import 'i18n/og_l_i18n.dart';

/// 品牌种子色（GitHub 蓝）。
/// 等宽字体族（自包含打包 Ubuntu Mono；Linux 无默认等宽映射，
/// 三桌面平台观感一致）。全部代码 / 日志 / 文件名场景使用。
const String kOglMonoFamily = 'OgLMono';

const Color kOgLSeedColor = Color(0xFF0969DA);

/// 启动失败兜底主题的种子色（明确的"出错了"信号色）。
const Color kOgLErrorSeedColor = Color(0xFFB3261E);

/// 错误兜底主题的次级色/底色（og_l_app.dart 的 OgLBootFailureApp 专用）。
const Color kOgLErrorSecondary = Color(0xFF57606A);
const Color kOgLErrorSurface = Color(0xFF121212);

/// 可选主题色（id → 颜色 + 展示名）。
///
/// 集中在此，设置页只按 id 取用；`settings.dart` 只存 id，
/// 不依赖 Flutter —— 保持数据层与展示层解耦。
const Map<String, Color> kOgLSeedColors = <String, Color>{
  'github': kOgLSeedColor,
  'ocean': Color(0xFF0B6E99),
  'forest': Color(0xFF2E7D32),
  'grape': Color(0xFF7B3FE4),
  'sunset': Color(0xFFE06C00),
  'rose': Color(0xFFC2185B),
  'slate': Color(0xFF546E7A),
};

/// 主题色展示名（id → `common` 分片键）。
const Map<String, String> kOgLSeedColorLabelKeys = <String, String>{
  'github': 'seedGithub',
  'ocean': 'seedOcean',
  'forest': 'seedForest',
  'grape': 'seedGrape',
  'sunset': 'seedSunset',
  'rose': 'seedRose',
  'slate': 'seedSlate',
};

/// 按 id 取主题色展示名（未知 id 回落品牌色名）。
String ogLSeedColorLabel(String id) => OgLI18n.instance.t(
      'common',
      kOgLSeedColorLabelKeys[id] ?? 'seedGithub',
    );

/// 按 id 取主题色（未知 id 回落品牌色）。
Color ogLSeedColorOf(String id) => kOgLSeedColors[id] ?? kOgLSeedColor;

/// 界面密度（`compact` → 更紧凑）。
VisualDensity ogLDensityOf(String id) =>
    id == 'compact' ? VisualDensity.compact : VisualDensity.standard;

/// 语义色（Material 3 的 [ColorScheme] 只有 error，没有成功 / 警告 / 信息）。
///
/// 通过 [ThemeExtension] 挂到主题上，页面用
/// `Theme.of(context).extension<OgLSemanticColors>()!` 取用，
/// **不再**写 `Colors.green` / `Colors.orange` 这类字面色。
@immutable
class OgLSemanticColors extends ThemeExtension<OgLSemanticColors> {
  /// 创建语义色集合。
  const OgLSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
    required this.outlineVariantStrong,
  });

  /// 成功。
  final Color success;

  /// 成功色的前景色。
  final Color onSuccess;

  /// 警告。
  final Color warning;

  /// 警告色的前景色。
  final Color onWarning;

  /// 信息。
  final Color info;

  /// 信息色的前景色。
  final Color onInfo;

  /// 强描边色：分割线 / 卡片 / Chip / 输入框 / 分段控件的可见边界。
  ///
  /// [ColorScheme.outlineVariant] 对各级 surface 仅 1.3–2.0:1，形同虚设；
  /// 本色按 WCAG 2.1 校准，对 surface → surfaceVariant 明暗各级
  /// 均 ≥3:1；页面取用走
  /// `Theme.of(context).extension<OgLSemanticColors>()!.outlineVariantStrong`。
  final Color outlineVariantStrong;

  static const Color lightOutlineVariantStrong = Color(0xFF6B6A71);
  static const Color darkOutlineVariantStrong = Color(0xFF7F7E85);

  @override
  OgLSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
    Color? outlineVariantStrong,
  }) =>
      OgLSemanticColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        info: info ?? this.info,
        onInfo: onInfo ?? this.onInfo,
        outlineVariantStrong: outlineVariantStrong ?? this.outlineVariantStrong,
      );

  @override
  OgLSemanticColors lerp(ThemeExtension<OgLSemanticColors>? other, double t) {
    if (other is! OgLSemanticColors) {
      return this;
    }
    return OgLSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      outlineVariantStrong:
          Color.lerp(outlineVariantStrong, other.outlineVariantStrong, t)!,
    );
  }
}

/// 按明暗 + 主题色 + 密度编译主题。
///
/// 除 `ColorScheme` 外，这里**显式定义**十四类组件的形状 / 内边距 / 高度：
/// 卡片、对话框、底部弹层、SnackBar、应用栏、导航栏、列表项、分割线、
/// Chip、输入框、FilledButton、TextButton、OutlinedButton、IconButton。
///
/// [overrideScheme] 传入系统动态配色（Android 12+ Material You）时，
/// 整个 [ColorScheme] 用它替换 `fromSeed` 结果——组件主题全部照常生效，
/// 只是配色来源换成系统壁纸动态取色（MD3 dynamic color）。
ThemeData buildOgLTheme(
  Brightness brightness, {
  Color seedColor = kOgLSeedColor,
  VisualDensity density = VisualDensity.standard,
}) {
  // ★ MD2 迁移（M-1）：弃 fromSeed/tonal 体系，回传统 ColorScheme 角色。
  //   色板取 GitHub 实际用色（亮/暗两套），层级只靠 surface + 真投影表达。
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: const Color(0xFF0969DA),
    onPrimary: Colors.white,
    secondary: dark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
    onSecondary: Colors.white,
    error: dark ? const Color(0xFFF85149) : const Color(0xFFCF222E),
    onError: Colors.white,
    background: dark ? const Color(0xFF121212) : Colors.white,
    onBackground: dark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
    surface: dark ? const Color(0xFF121212) : Colors.white,
    onSurface: dark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
    surfaceVariant: dark ? const Color(0xFF1C2128) : const Color(0xFFF6F8FA),
    onSurfaceVariant: dark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
    outline: dark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
    shadow: Colors.black,
  );

  // 统一的边框形状（按组件体量分三档，与 OgLRadius 对齐）。
  final RoundedRectangleBorder shapeSm = RoundedRectangleBorder(
    borderRadius: OgLRadius.cSm,
  );
  final RoundedRectangleBorder shapeMd = RoundedRectangleBorder(
    borderRadius: OgLRadius.cMd,
  );
  final RoundedRectangleBorder shapeLg = RoundedRectangleBorder(
    borderRadius: OgLRadius.cLg,
  );
  final RoundedRectangleBorder shapePill = RoundedRectangleBorder(
    borderRadius: OgLRadius.cPill,
  );

  // ★ MD3 Typography：组件主题字号一律从 textTheme 派生（audit Fix #1），
  //   不写裸 fontSize —— 主题字体缩放调整时全站联动。
  //   映射：对话框标题=titleLarge、正文=bodyMedium；应用栏=titleLarge；
  //   SnackBar=bodyMedium；导航栏标签=labelMedium；Chip=labelSmall；
  //   按钮=labelLarge（M3 规范值）。
  final TextTheme tt = ThemeData(brightness: brightness).textTheme;

  // 触摸目标下限：48×48（MD3 / WCAG 2.1 推荐，audit Recommended Fix #3）。
  const Size minTouch = Size(48, 48);
  const Size minButton = Size(64, 48);

  // 强描边：outlineVariant 对任意底色仅 1.3–2.0:1，需按 WCAG 校准的
  // outlineVariantStrong（明/暗分档）承担所有边界角色；页面取用同一 token。
  final Color outlineStrong = brightness == Brightness.dark
      ? OgLSemanticColors.darkOutlineVariantStrong
      : OgLSemanticColors.lightOutlineVariantStrong;
  // ★ MD2：真实投影（黑影），层级靠 elevation 档位（卡2/AppBar4/菜单4/弹层16）。
  final Color md2Shadow = Colors.black.withValues(alpha: 0.26);

  return ThemeData(
    colorScheme: scheme.copyWith(shadow: md2Shadow),
    scaffoldBackgroundColor: scheme.surface,
    shadowColor: md2Shadow,
    visualDensity: density,
    extensions: <ThemeExtension<dynamic>>[
      OgLSemanticColors(
        success: const Color(0xFF2E7D32),
        onSuccess: const Color(0xFFFFFFFF),
        warning: const Color(0xFFB26A00),
        onWarning: const Color(0xFFFFFFFF),
        info: scheme.primary,
        onInfo: scheme.onPrimary,
        outlineVariantStrong: outlineStrong,
      ),
    ],

    // ── 卡片 ────────────────────────────────────────────────────────────
    // MD2：卡片层级 = surface 底 + 真投影 + 描边（无 tonal 分层）。
    cardTheme: CardThemeData(
      color: scheme.surface,
      shape: shapeLg.copyWith(
        side: BorderSide(color: outlineStrong),
      ),
      elevation: 1,
      margin: const EdgeInsets.symmetric(
        horizontal: OgLSpace.lg,
        vertical: OgLSpace.sm,
      ),
      clipBehavior: Clip.antiAlias,
    ),

    // ── 对话框 ──────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      shape: shapeMd,
      elevation: 3,
      backgroundColor: scheme.surfaceVariant,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.xl,
        vertical: OgLSpace.xl,
      ),
      titleTextStyle: tt.titleLarge?.copyWith(
        // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      contentTextStyle: tt.bodyMedium?.copyWith(
        // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
        color: scheme.onSurfaceVariant,
        height: 1.5,
      ),
    ),

    // ── 底部弹层 ────────────────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      shape:
          const RoundedRectangleBorder(borderRadius: OgLRadius.verticalTopXl),
      elevation: 1,
      backgroundColor: scheme.surfaceVariant,
      showDragHandle: true,
      dragHandleColor: outlineStrong,
      clipBehavior: Clip.antiAlias,
    ),

    // ── SnackBar ────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shapeMd,
      elevation: 3,
      backgroundColor: brightness == Brightness.dark
          ? scheme.surfaceVariant
          : scheme.inverseSurface,
      contentTextStyle: tt.bodyMedium?.copyWith(
        // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
        color: brightness == Brightness.dark
            ? scheme.onSurface
            : scheme.onInverseSurface,
        height: 1.4,
      ),
      insetPadding: const EdgeInsets.all(OgLSpace.md),
      // 暗色底色为 surfaceVariant（亮档），inversePrimary 仅 1.9:1；
      // 用 onSurface 达 9.5:1。浅色底色 inverseSurface 则沿用 inversePrimary。
      actionTextColor: brightness == Brightness.dark
          ? scheme.onSurface
          : scheme.inversePrimary,
    ),

    // ── 应用栏 ──────────────────────────────────────────────────────────
    // ★ AppBar 与内容分层：底色用 surface，滚动时
    //   scrolledUnderElevation=2 由 MD3 原生接管色阶显形（OgLAppBar 的连续
    //   渐变叠加其上），任何页面滚动态都出现可感知顶栏边界。
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: tt.titleLarge?.copyWith(
        // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),

    // ── 导航轨（宽屏 Rail，MD2 形态）─────────────────────────────────
    // 无 tonal 轨道底色/药丸指示器：选中 = primary 图标/标签，
    // 分层靠 elevation 真投影（与 AppBar 同语言）。
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      elevation: 4,
      labelType: NavigationRailLabelType.all,
      selectedIconTheme: const IconThemeData(color: Color(0xFF0969DA)),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: const TextStyle(color: Color(0xFF0969DA)),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),

    // ── 列表项 ──────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      shape: shapeMd,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.lg,
        vertical: OgLSpace.xxs,
      ),
      minVerticalPadding: OgLSpace.sm,
      horizontalTitleGap: OgLSpace.md,
      iconColor: scheme.onSurfaceVariant,
      // 选中行给主题色反馈（此前 selected 无任何视觉差异）。
      selectedColor: scheme.primary,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
    ),

    // ── 分割线 ──────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      thickness: 1,
      space: 1,
      color: outlineStrong,
    ),

    // ── Chip ────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      shape: shapeSm,
      backgroundColor: scheme.surfaceVariant,
      selectedColor: scheme.secondaryContainer,
      showCheckmark: false,
      side: BorderSide(color: outlineStrong),
      padding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.sm,
        vertical: OgLSpace.xxs,
      ),
      labelStyle: tt.labelSmall?.copyWith(
        // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    ),

    // ── 分段控件（M3 收敛：默认胶囊过高过圆，截图实证错位感）──────
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontWeight: FontWeight.w500),
        ),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: OgLRadius.cSm),
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: outlineStrong),
        ),
      ),
    ),

    // ── 输入框 ──────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceVariant,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.md,
        vertical: OgLSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide(color: outlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide(color: outlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      hintStyle: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),

    // ── 按钮 ────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shapePill,
        minimumSize: minButton,
        padding: const EdgeInsets.symmetric(horizontal: OgLSpace.xl),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.60),
        disabledBackgroundColor: scheme.surfaceVariant,
        textStyle: tt.labelLarge?.copyWith(
          // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shapePill,
        minimumSize: minTouch,
        padding: const EdgeInsets.symmetric(horizontal: OgLSpace.md),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.60),
        textStyle: tt.labelLarge?.copyWith(
          // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shapePill,
        minimumSize: minButton,
        padding: const EdgeInsets.symmetric(horizontal: OgLSpace.xl),
        side: BorderSide(color: scheme.outline),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.60),
        textStyle: tt.labelLarge?.copyWith(
          // fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）。
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: minTouch,
        iconSize: OgLIconSize.xl,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.60),
        shape: shapeSm,
      ),
    ),
  );
}
