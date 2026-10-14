# tool · 工具目录

本目录全部为**仓库内工具**（随仓库分发，CI 依赖其中审计/构建脚本）。

| 工具 | 用途 |
| --- | --- |
| `desktop_icon.py` | 零依赖 SVG → PNG/ICO 光栅化（CI 用） |
| `inject_desktop_shell.py` | 桌面原生壳注入：Windows ICO + Runner.rc + 原生标题；Linux PNG 母版 + 原生标题 |
| `inject_android_gradle.py` | Android Gradle 注入（compileSdk / 架构产物） |
| `inject_android_manifest.py` | Android Manifest 注入（权限 / 长路径可选） |
| `inject_android_icon.py` | Android 图标注入（VectorDrawable + 自适应图标） |
| `inject_windows_cmake.py` | Windows CMake 兼容宏注入（permission_handler） |
| `linux_packages.py` | Linux 打包：deb / rpm / AppImage |
| `boot_manifest.py` | 引导清单生成与 Ed25519 签名 |
| `layer_audit.py` | CI 门禁：四层依赖只能向下 |
| `i18n_scan.py` | CI 门禁：界面文案零遗漏 / 分片键一致 |
| `i18n_wire.py` | 批量接线：中文字面量 → t() |
| `motion_audit.py` | CI 门禁：动画必须走档位质量表 |
| `perf_audit.py` | CI 门禁：反模式扫描 |
| `stats_chart.py` | 统计曲线自检（CI 门禁 selftest） |
| `sort_imports.py` | import 分组排序 |
| `verify_apk_cert.py` | APK 证书校验（发布后验收） |
| `web_build.py` | Web（wasm）：注入浏览器 API 守卫 → 校验产物 → 清空并重建 `app/` |

> 说明：本机运维脚本（推送 / CI 排障 / 发布触发）不入库，见本地 `_setup/`。
