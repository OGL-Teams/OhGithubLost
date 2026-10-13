# 字体 CDN 加速（fonts.md）

## 结论（Decision: 不需要 CDN 加速）

截至 **v8.2.0**，本项目 **没有自定义字体文件**：

- `find assets/fonts -type f` → 无结果（`assets/fonts/` 目录不存在）。
- `rg "google_fonts|fonts.gstatic|fonts.googleapis" lib/ pubspec.yaml` → 无匹配。
- 代码中仅出现 `fontFamily: 'monospace'`（5 处）——属于平台通用等宽字体族，
  **不带具体名称**，因此**不触发任何字体下载**。

所有正文走 Material 3 TextTheme 默认 Roboto（Android / 桌面 / iOS 自带；Web 端由浏览器提供）。

---

## 何时需要打开此方案

当出现以下任一情况，且仅当之一：

1. AI 聊天 / 代码显示 / 通知正文需要在 Web 端有更可读的等宽字体（如 JetBrains Mono、
   Fira Code），且当前 Web 端的 `monospace` 映射影响观感。
2. CJK 字符质量在某些平台（或 Web 端）需统一为 Noto Sans CJK 等开源字体族。

---

## 届时推荐做法（保留备查）

依赖：
```yaml
dependencies:
  google_fonts: ^6.2.1   # 见 pub.dev/google_fonts
```

代码：
```dart
import 'package:google_fonts/google_fonts.dart';

// 一次性获得（按需缓存到文件系统）
final TextStyle body = GoogleFonts.notoSansSc();    // 中文正文
final TextStyle mono = GoogleFonts.jetBrainsMono(); // 等宽
```

Web 端的 google_fonts 默认通过 `fonts.googleapis.com` 拉取；在中国大陆境内构建建议：

| 镜像 | 域名 | 备注 |
| --- | --- | --- |
| jsDelivr | `cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC[wght].ttf` | 同步 google/fonts 仓库，自动跟新版本 |
| 字节跳动 | `fonts.googleapis.cn` | 官方国内镜像，仅替换主域 |

切换：在 `MaterialApp` 之上挂一个 `Theme` 自定义，**不**进入 google_fonts 的 `request` 钩子。
也可在 `web/index.html` 里以 `<link rel="stylesheet" href="https://cdn.jsdelivr.net/...">` 一次性预取。

---

## 不阻塞本任务

- 本轮（8.2.0）**无任何字体改动**。
- 上述方案作为「未来工作」保留，不在 8.2.0 范围内执行。
