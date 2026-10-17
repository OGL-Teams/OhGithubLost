/// L3 展示级 · 代码配色色板（**数据，不是主题**）。
///
/// 这些 ARGB 值是"可选的代码高亮底色/前景色"，属于用户可配置的外观数据，
/// 与主题的语义色无关，因此不适用 `colorScheme` 规则（ui_audit 白名单）。
///
/// 迁出原因：它原先内联在 `settings_page.dart` 里，与页面自身的颜色用法规
/// 混在一起，无法单独豁免 —— 要么豁免整页（掩盖真问题），要么每次误报。
library;

/// 自定义代码配色的可选色板（ARGB）。
const List<int> kOgLCodePalette = <int>[
  0xFF000000,
  0xFF101418,
  0xFF1E1E1E,
  0xFF2D333B,
  0xFFF6F8FA,
  0xFFFFFFFF,
  0xFFE6EDF3,
  0xFF24292F,
  0xFF79C0FF,
  0xFF0550AE,
  0xFF569CD6,
  0xFF4EC9B0,
  0xFF6A9955,
  0xFFCE9178,
  0xFF953800,
  0xFFFFA657,
  0xFFB5CEA8,
  0xFFCF222E,
  0xFFFF7B72,
  0xFF8250DF,
  0xFFBC8CFF,
  0xFF9BA7B4,
];
