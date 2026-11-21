# UI 稳定性修复 · 子代理强制纪律

## 绝对禁止（违反即取消 job + 全量清理产出）
- **禁止读取、下载、复制 Flutter SDK 源码**：`/root/flutter/`、`/opt/flutter/`、`/tmp/dart-sdk/`、`pub` 缓存包源码（如 `/opt/dart` 的包源码目录）、任何 `flutter/flutter` 仓库文件。
- 需要框架 API 事实时：只用**项目自身 `lib/` 已验证代码**，或跳过并标注「待核实（需主会话/CI 裁决）」。
- 本地 dart 仅允许 `/opt/dart/bin/dart format --language-version=3.6`（用户已认可）；不得用 dart 工具读 SDK 或做 analyze。

## 允许
- 读项目 `lib/`、`test/`、`tool/`、`docs/`、`assets/`。
- 用 `rg`/`file_read` 在项目内查符号。
- 改代码后用 `/opt/dart/bin/dart format` 对齐格式。

## 本轮任务
见各批次任务描述（docs/UX_STABILITY_PLAN.md）。每批范围收窄，避免超时；半成品不合并。
