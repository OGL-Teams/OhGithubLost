/// L3 展示级 · 字号令牌（与 [OgLSpace] / [OgLIconSize] 同一体系）。
///
/// 审查 SZ-06：等宽正文 `fontSize: 12/13` 裸值散布 26 处，无语义、
/// 混用无依据。这里给两档**语义化**字号，替换后所有等宽文本随系统
/// TextScaler 缩放的行为不变（仍是抽象像素值），但有了唯一事实源。
library;

/// 等宽文本字号。
abstract final class OgLFont {
  /// 紧凑等宽：代码、哈希、日志、行号等辅助信息。
  static const double monoSm = 12;

  /// 常规等宽：代码正文、补丁行等需要长时间阅读的内容。
  static const double monoMd = 13;
}
