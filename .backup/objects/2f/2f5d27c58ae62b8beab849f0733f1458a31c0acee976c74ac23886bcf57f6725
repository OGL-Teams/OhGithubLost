# tool · 工具目录

> 本目录全部为**仓库内工具**（随仓库分发，CI 依赖其中审计/构建脚本）。

## 平台能力的分工（别再往注入里塞 Dart 能写的东西）

| 类别 | 放哪 | 例 |
| --- | --- | --- |
| **能用 Dart 写的** | `lib/platform/`（每平台一份真实实现 + 门面选型） | 窗口标题、标题栏模式、最大化/最小化/关闭、权限网关、存储裁决 |
| **物理上写不了 Dart 的** | `tool/platform_spec.yaml` → `inject_platform_spec.py` 在构建期注入 | Android 安装期权限、compileSdk/desugaring、Windows 编译宏、ICO/PNG 图标、macOS entitlements |

注入**不是逃生舱**：`platform_spec.yaml` 的每一条都必须写 `why`（为什么不能
用 Dart），脚本会强制校验，缺 `why` 直接拒绝执行。

| 工具 | 用途 |
| --- | --- |
| `platform_spec.yaml` | 平台私有文件规格（`why` 必填，是这个文件存在的理由） |
| `inject_platform_spec.py` | 按 spec 注入（幂等；`--list` / `--target` / `--job`） |
| `inject_platform_spec_selftest.py` | 注入器自检（临时目录假脚手架，21 项，可挂 CI） |
| `desktop_icon.py` | 零依赖 SVG → PNG/ICO 光栅化（被上面的注入器调用） |
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

> 说明：本机运维脚本（推送 / CI 排障 / 发布触发）不入库，见本地 `_setup/`。
