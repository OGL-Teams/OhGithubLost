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
const Color kOgLSeedColor = Color(0xFF0969DA);

/// 启动失败兜底主题的种子色（明确的"出错了"信号色）。
const Color kOgLErrorSeedColor = Color(0xFFB3261E);

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

  @override
  OgLSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
  }) =>
      OgLSemanticColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        info: info ?? this.info,
        onInfo: onInfo ?? this.onInfo,
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
    );
  }
}

/// 按明暗 + 主题色 + 密度编译主题。
///
/// 除 `ColorScheme` 外，这里**显式定义**十四类组件的形状 / 内边距 / 高度：
/// 卡片、对话框、底部弹层、SnackBar、应用栏、导航栏、列表项、分割线、
/// Chip、输入框、FilledButton、TextButton、OutlinedButton、IconButton。
ThemeData buildOgLTheme(
  Brightness brightness, {
  Color seedColor = kOgLSeedColor,
  VisualDensity density = VisualDensity.standard,
}) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
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
  final RoundedRectangleBorder shapeXl = RoundedRectangleBorder(
    borderRadius: OgLRadius.cXl,
  );
  final RoundedRectangleBorder shapePill = RoundedRectangleBorder(
    borderRadius: OgLRadius.cPill,
  );

  // 触摸目标下限：44×44（Material 建议 48，视觉上 44 更紧凑且仍可点）。
  const Size minTouch = Size(44, 44);
  const Size minButton = Size(64, 44);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: density,
    extensions: <ThemeExtension<dynamic>>[
      OgLSemanticColors(
        success: const Color(0xFF2E7D32),
        onSuccess: const Color(0xFFFFFFFF),
        warning: const Color(0xFFB26A00),
        onWarning: const Color(0xFFFFFFFF),
        info: scheme.primary,
        onInfo: scheme.onPrimary,
      ),
    ],

    // ── 卡片 ────────────────────────────────────────────────────────────
    // Material 3 靠 tonal elevation 而非投影：elevation 0 + 描边，
    // 层级由 surfaceContainer 色阶表达。
    cardTheme: CardThemeData(
      shape: shapeLg,
      elevation: 0,
      margin: const EdgeInsets.symmetric(
        horizontal: OgLSpace.lg,
        vertical: OgLSpace.sm,
      ),
      clipBehavior: Clip.antiAlias,
    ),

    // ── 对话框 ──────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      shape: shapeXl,
      elevation: 0,
      backgroundColor: scheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.xl,
        vertical: OgLSpace.xl,
      ),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
        height: 1.5,
      ),
    ),

    // ── 底部弹层 ────────────────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      shape:
          const RoundedRectangleBorder(borderRadius: OgLRadius.verticalTopXl),
      elevation: 0,
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      clipBehavior: Clip.antiAlias,
    ),

    // ── SnackBar ────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shapeMd,
      elevation: 0,
      backgroundColor: brightness == Brightness.dark
          ? scheme.surfaceContainerHighest
          : scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: brightness == Brightness.dark
            ? scheme.onSurface
            : scheme.onInverseSurface,
        fontSize: 14,
        height: 1.4,
      ),
      insetPadding: const EdgeInsets.all(OgLSpace.md),
      actionTextColor: scheme.inversePrimary,
    ),

    // ── 应用栏 ──────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),

    // ── 导航栏 ──────────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
    ),

    // ── 分割线 ──────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      thickness: 1,
      space: 1,
      color: scheme.outlineVariant,
    ),

    // ── Chip ────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      shape: shapeSm,
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.sm,
        vertical: OgLSpace.xxs,
      ),
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),

    // ── 输入框 ──────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: OgLSpace.md,
        vertical: OgLSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: OgLRadius.cSm,
        borderSide: BorderSide.none,
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
      hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
    ),

    // ── 按钮 ────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shapePill,
        minimumSize: minButton,
        padding: const EdgeInsets.symmetric(horizontal: OgLSpace.xl),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shapePill,
        minimumSize: minTouch,
        padding: const EdgeInsets.symmetric(horizontal: OgLSpace.md),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shapePill,
        minimumSize: minButton,
        padding: const EdgeInsets.symmetric(horizontal: OgLSpace.xl),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: minTouch,
        iconSize: OgLIconSize.lg,
        shape: shapeSm,
      ),
    ),
  );
}
