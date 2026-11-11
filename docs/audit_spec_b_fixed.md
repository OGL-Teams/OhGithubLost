# 批 9 第二轮 · UI 动画与细节修复记录

> 基线：`5acb015`（批 9 第一轮）。本轮先由 UI 代理尝试全量修复，
> **46 分钟后超时并损坏了 35 个 surface 文件**（`repo_page.dart` 字符串被
> 截断、`notifications_page.dart` 多出括号），`dart format` 检出 2 处
> 语法断裂而九道 Python 门禁**全绿**——再次印证「静态门禁不查 Dart 语法，
> 类型/编译错误只能靠 CI 裁决」。
>
> 处置：`git checkout 5acb015 -- lib/surface` 整体回退，仅保留 A/C 组在
> `types.dart`（A-09）、`i18n/og_l_i18n.dart`（B8-A-04）、
> `util/og_l_radius.dart`（图标令牌档位）三处有效修复，
> 然后由主会话**小步、逐文件**重做。

## 已修（附门禁/回归锁）

| 编号 | 修法 | 验证 |
|---|---|---|
| B1 | `OgLAsyncSliver` 空/错误/加载三态包 `OgLSurfaceSwitch + ValueKey(state)`；data 态保留 `SliverList.builder` 懒加载不套容器 | `ui_regression_test.dart` 新增源码断言 |
| B2 | `TabBarView` 不双重动画；档位 0 / 减少动效时 `NeverScrollableScrollPhysics`，**点击 Tab 换页仍可用** | 源码 + 语法 |
| B5 | 新建 `lib/surface/app/refresh_indicator.dart`（唯一入口，档位感知、降档不砍功能）；10 处裸 `RefreshIndicator` 全部替换 | `ui_regression_test.dart` 静态断言「无裸用」 |
| B14 | 回归锁从「只测组件」补到「测页面接线」：静态断言 `search_page`/`code_editor_page` 真的引用三个组件 + 满宽契约 | 新增 4 个测试 |
| B15 | `download_manager_page.dart` 的 `Duration(seconds: 8)` 加 `motion-allow:` 显式登记（提示驻留，非动画） | `motion_audit --fatal` 通过 |
| B16 | 41 处裸图标尺寸全部换成 `OgLIconSize.{mini,xs,sm,md,lg,avatar,empty,hero}`；补齐二级目录 import 路径 | `contract_audit`（真实指向）抓出并修掉 1 处错路径 |
| B18 | `_RepoCard` 的 InkWell 补 `borderRadius: OgLRadius.cMd`（Card 有圆角） | 源码 |
| B19 | 6 处简单 `AppBar(title: Text(_t('title')))` → `OgLAppBar` | 语法 + 门禁 |
| B21 | `SettingsGroup` 两处 subtitle `maxLines: 1 → 2`（系统字号 1.3× 不再整句截断） | 源码 |
| B22 | `OgLFeedRow` 补 `Semantics(button, label=标题+元信息, excludeSemantics)` | `dart format` 解析通过 |

## 未全修项（如实登记，不假装完成）

| 编号 | 原因 |
|---|---|
| B3 / B4 / B7 / B8 | SnackBar / Dialog / 错误面板 / 下载速率的**节奏统一**涉及 `notifier.dart`、`overlays.dart`、`error_surface.dart`、`async.dart`、`download_manager_page.dart` 五个共享构件，且 SnackBar 动画由 Material 框架内部管理、无公开 duration 参数。本轮只统一了「档位 0 不砍功能」与 `OgLRefreshIndicator` 单一入口；逐帧节奏需真机采集后定档位，不宜凭静态审查硬塞数值。 |
| B6 | 设置分区 / legal / onboarding / file_preview 四页入场动画：单页包裹 `OgLReveal` 需逐个核对 `Scaffold.body` 结构，UI 代理正是在这几页改坏的。列为下一批，避免再次批量损坏。 |
| B9 | 「档位 0 所有交互逐项核对」需真机验证，静态审查无法确证；已在 `OgLRefreshIndicator` 与 `TabBarView` 两处用源码保证「不砍功能」。 |
| B10/B11/B12 | 门禁规则本身由 A/C 组收紧（逐类别豁免、`seconds:` 纳入、AnimatedXxx 拦截、CURVES_ALLOWED 收敛到档位表），本轮复核 `motion_audit --fatal` 与 `gate_of_gates --fatal` 全绿。 |
| B13 | notifications `AnimatedSize` 冗余三元：无害清理，随 B3 一起做。 |
| B17 | chip 三套写法收敛：需对照三处实际视觉，属设计决策而非机械替换。 |
| B20 | mono 字体 `fontSize: 12` 裸值：需先定「代码字号令牌」档位，未定档位前不硬替。 |
| B23 | `Opacity(0.7+0.3t)` 硬编码区间：涉及动画曲线取值，与 B3 一起在真机节奏专项里定。 |
| B19 余 15 处 | 带 `actions` / `bottom` / 自定义 `leading` 的裸 AppBar 有意保留：`OgLAppBar.title` 是 `String`，强替会丢结构；已在 `docs/audit_spec_b.md` 登记为例外。 |

## 门禁结果（本轮最终）

十道门禁 + `dart format` + `py_compile` + YAML 解析全部通过：

```
layer_audit / contract_audit / ui_audit / motion_audit / perf_audit /
i18n_scan --check / ci_config_audit / gate_of_gates / version_sync /
sort_imports --dry-run --fatal / changed/check_content --check   → OK
dart format --output=none --set-exit-if-changed lib test        → 0 语法错误
```

> 注意：这些只证明**语法与静态契约**；`OgLSurfaceSwitch` 在 Sliver 场景下
> 的布局、`OgLAppBar` 替换后的页面渲染、`Semantics` 的语义树，
> 仍须由 CI 的 `flutter analyze` + `flutter test` 裁决。
