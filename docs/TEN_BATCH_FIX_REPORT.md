# 十批全面审计 · 批 1 UI 视觉与布局 · 修复报告

> 文档戳：更新时间 **2026-11-28 18:05:00 (Asia/Shanghai)** · 版本 `62c5383` · 批 1 三席



## 修复结果（三席）
- A 席（密度 P0）：profile/network 首屏改为常驻内容锚点 + 局部骨架；issue 压缩标签行/正文内滚；dashboard 骨架 topAligned。
- B 席（色彩 P1）：语义色明暗分档、errorContainer 显式定义、投影同源、elevation 2/16/8/6、锚定色统一；同步重写 contrast_audit 适配明暗分档结构。
- C 席（跨页 P1）：15 页原生 AppBar→OgLAppBar 统一；35/35 核心动作图标收编 OgLIcons；ui_audit 新增裸图标门禁；MD3 注释清理。

## 主会话收尾
- 修复 B 席 `sem.outlineStrong` 非法命名（批量回退为 outlineVariantStrong）
- contrast_audit 判据修正：on* 应对各自色块底而非页面容器底
- ui_audit 误报修正：OgLSemanticColors.dark/light 不再命中 Colors.* 字面色规则

## 验收
dart format 0 changed / ui_audit 0 / contrast_audit 0 / gate_of_gates 12 支全过 / i18n_scan 30 语言一致 / layer_audit 0 违规。
