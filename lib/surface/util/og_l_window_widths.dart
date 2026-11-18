/// L3 展示级 · 窗口宽度断点（对齐 Material 3 WindowSizeClass）。
/// compact <600 ≤ medium <840 ≤ expanded <1200 ≤ large；本项目按需用
/// compact/medium/expanded 三档，600/840/1200 与 M3 canonical 断点一致。
abstract final class OgLWindowWidths {
  /// compact 上界：<600 为手机档（NavigationBar 底栏）。
  static const double compact = 600;

  /// 内容限宽：宽屏一级页内容最大宽度（medium 档阅读宽度）。
  static const double contentMax = 720;

  /// expanded 下界：≥1200 为展开档（extended rail）。
  static const double expanded = 1200;
}
