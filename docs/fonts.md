# 字体现状决策 / Font Status Decision

> 状态 / Status：决策记录（现行） · 面向技术人员 / For engineers
> 范围 / Scope：`assets/fonts/`、`pubspec.yaml`、`lib/surface/theme.dart`

> **更新时间 / Last Updated**：2026-11-21 16:01:16　**对应版本 / Version**：v14.0.0

## 1. 现行结论 / Current decision

旧稿（v8.2.0 时代）称「`assets/fonts/` 目录不存在；仅 5 处 `fontFamily: 'monospace'`；
建议接入 google_fonts CDN」——该结论已被后续改动推翻，**整节作废**。
The earlier v8.2.0-era decision (no `assets/fonts/`, five `'monospace'` references,
google_fonts CDN recommendation) has been superseded and is void.

现行事实由以下命令实测 / Facts verified with these commands：

```bash
ls -la assets/fonts/                                   # UbuntuMono-Bold.ttf / UbuntuMono-Regular.ttf
rg -n "assets/fonts" pubspec.yaml                      # 第 129–130 行，两项字体资产声明
rg -n "monospace" lib/ -g '*.dart' | wc -l             # 0
rg -n "kOglMonoFamily" lib/ | wc -l                    # 多处引用
```

实测结果 / Measured results：

| 项 / Item | 现状 / Current state | 证据 / Evidence |
| --- | --- | --- |
| 字体文件 / Font files | `UbuntuMono-Regular.ttf`（205748 字节）、`UbuntuMono-Bold.ttf`（191400 字节） | `ls -la assets/fonts/` |
| 资产声明 / Asset declarations | `pubspec.yaml` 第 126–130 行 `flutter.fonts`，家族 `OgLMono`；Regular 无 weight，Bold 标 `weight: 700`（见 `lib/surface/theme.dart:29`） | `sed -n '124,134p' pubspec.yaml` |
| 等宽调用 / Mono call sites | `kOglMonoFamily`（`const String kOglMonoFamily = 'OgLMono'`，`theme.dart:29`）在 `about_page.dart`、`code_editor_page.dart`、`commit_page.dart`、`gist_detail_page.dart`、`repo_page.dart`、`settings_page.dart`、`workflow_dispatch_page.dart` 等处使用 | `rg -n "kOglMonoFamily" lib/` |
| `monospace` 字面量 / literal | 0 处 | `rg -n "monospace" lib/ -g '*.dart' \| wc -l` |
| 网络字体 / Web fonts | `google_fonts` / `fonts.gstatic` / `fonts.googleapis` 不在字体加载路径；字体随产物打包，不依赖 CDN | `rg -n "google_fonts\|fonts.gstatic\|fonts.googleapis" lib/ pubspec.yaml` |

## 2. 加载与调用 / Loading and usage

`pubspec.yaml` 的 `flutter.fonts` 段把两个 TTF 注册为家族 `OgLMono`；
`lib/surface/theme.dart` 第 29 行 `const String kOglMonoFamily = 'OgLMono'` 是展示层唯一入口常量。
代码编辑器、代码预览、日志、diff、令牌文本等通过该常量取等宽字体，字号经 `OgLFont.monoSm` /
`OgLFont.monoMd` 等令牌控制（见 `ui_audit.py` 的等宽上下文豁免）。

UI 正文字体由 `lib/surface/surface_bridge.dart` 的 `_uiFontFamilyOf(uiFontId)` 按用户外观设置选择，
`theme.dart` 多处注释明确「fontFamily 不覆写：UI 控件保持平台字体（外观字体只管正文阅读）」。
可选项包含系统字体与自托管等宽字体（`surface_bridge.dart:596` 返回 `kOglMonoFamily`）。

## 3. 为何不接 CDN / Why no CDN

1. 自托管 TTF 已随产物打包，离线可用；CDN 会引入网络依赖与不可用时的回退分叉。
2. 现有字体文件仅两份、体积合计约 400 KB，不构成包体瓶颈。
3. `monospace` 字面已在代码中归零，旧稿设想的「Web 端 monospace 映射不佳」问题不复存在。
4. 引入 `google_fonts` 会与 `kOglMonoFamily` 的既有调用面并存，产生两套等宽字体来源。

若未来确需新增字体（例如 CJK 统一字族），应：把 TTF 放入 `assets/fonts/`、
在 `pubspec.yaml` 的 `flutter.fonts` 注册、在 `theme.dart` 增加常量并经 `OgLFont` 令牌取字号；
不得直接引入 CDN 依赖绕过打包链路。

## 4. 历史记录 / History

旧稿「字体 CDN 加速（v8.2.0）」为当时事实记录，结论已被推翻，不再作为决策依据；
本次按实际字体目录重写。原始文本可从本文件 git 历史读取，不在本文复述。
The superseded v8.2.0 CDN note is retained only in git history and is not reproduced here.
