# MD1 经典（2014）UI 层完全重写规范

> 用户决策（2026-11-28）：放弃 MD2「换皮」路线，**所有控件用 CustomPainter 自行绘制**（不使用任何 Flutter Material 控件），按 MD1 经典 2014 规范，从当前 HEAD 增量重写表现层。

## 一、为什么这次是真的重写

- **不使用** `ElevatedButton` / `TextButton` / `ListTile` / `Card` / `AppBar` / `Scaffold` / `BottomNavigationBar` / `Dialog` / `SnackBar` / `Switch` / `Checkbox` / `TextField` 等任何 Material 控件作为可见控件。
- **不使用** `ThemeData` 的组件 theme 字段（buttonTheme/cardTheme/appBarTheme…）——它们只作为已迁移页面的临时兼容，每迁完一页就删。
- 允许使用的基础构件：`CustomPaint` + `CustomPainter`、`GestureDetector`、`RawKeyboardListener`/`Focus`、`Text`/`RichText`、`AnimationController`、`Row`/`Column`/`Stack`/`Padding`/`SizedBox`/`Expanded`/`SingleChildScrollView`/`ListView.builder`（布局原语，非控件）、`Navigator` 路由。
- 允许保留 `MaterialApp` 作路由/主题载体（不可见外壳）或替换为 `WidgetsApp`——最终目标 `WidgetsApp`。

## 二、MD1 经典 2014 权威规格（写死，代理不得发挥）

### 色彩（MD1 2014 原始色板）
| 角色 | 值 | 用途 |
|---|---|---|
| primary | `#3F51B5` | AppBar、主按钮、Tab 下划线、FAB |
| primaryDark | `#303F9F` | 状态栏深一档 |
| accent | `#FF4081` | FAB、开关激活、进度条 |
| background | `#FAFAFA` | 页面底 |
| card | `#FFFFFF` | 卡片/列表行底 |
| divider | `#E0E0E0` | 1px 分割线 |
| textPrimary | `rgba(0,0,0,.87)` | 正文 |
| textSecondary | `rgba(0,0,0,.54)` | 副文 |
| dark 模式 | primary `#3F51B5`、background `#303030`、card `#424242`、divider `#555555`、text `#FFFFFF`(.87/.54) | 明暗双主题 |

### 字阶（Roboto，MD1 2014）
| 档 | 字号 | 字重 | 用途 |
|---|---|---|---|
| display | 34 | 400 | 启动/空态大标题 |
| headline | 24 | 400 | 页面主标题 |
| title | 20 | 500 | 卡片标题 |
| subhead | 16 | 400 | 列表主文 |
| body | 14 | 400 | 正文 |
| caption | 12 | 400 | 副文/时间戳 |
| button | 14 | 500 | 按钮（全大写英文） |
| overline | 10 | 500 | 微标签 |

### 尺寸与形状
- AppBar 56dp（桌面 64）、elevation 4dp 真投影、纯色 primary、白字 20sp。
- FAB 56dp 直径、elevation 6dp、accent 色、居中 + icon。
- 卡片 2dp elevation、2dp 圆角（MD1 经典是 2dp，不是方角——修正：2014 规范卡角 2dp）。
- 按钮高度 36dp（MD1 flat/raised）、2dp 圆角、内边距 16dp；文字大写。
- 分割线 1px `#E0E0E0`。
- 触控目标 ≥48dp。
- 输入框 48dp 高、底边 1px（focus 2px primary）、无框、label 浮动 12sp。
- 列表行 72dp（双行）/ 56dp（单行）；leading 40dp 图标、title 16sp、subtitle 14sp。
- Tab 48dp 高、下划线 2px accent/white。
- 对话框 2dp 圆角、elevation 24dp、宽 ≥280dp。

### Elevation（MD1 2014 阴影值）
| 档 | 阴影 |
|---|---|
| 1dp | `0 1px 3px rgba(0,0,0,.24), 0 1px 2px rgba(0,0,0,.22)` |
| 2dp | `0 2px 5px rgba(0,0,0,.26)` |
| 4dp | `0 4px 8px rgba(0,0,0,.24), 0 1px 3px rgba(0,0,0,.22)` |
| 6dp | `0 6px 12px rgba(0,0,0,.24), 0 1px 3px rgba(0,0,0,.22)` |
| 8dp | `0 8px 16px rgba(0,0,0,.24), 0 1px 3px rgba(0,0,0,.22)` |
| 24dp | `0 11px 15px rgba(0,0,0,.20), 0 9px 46px rgba(0,0,0,.12)` |

## 三、控件清单（40+，全部 CustomPainter 自绘）

1. `OgMd1Button`（flat/raised） 2. `OgMd1Card` 3. `OgMd1ListRow` 4. `OgMd1Ripple` 5. `OgMd1AppBar` 6. `OgMd1BottomNav` 7. `OgMd1TabBar` 8. `OgMd1TextField` 9. `OgMd1Switch` 10. `OgMd1Checkbox` 11. `OgMd1Radio` 12. `OgMd1Slider` 13. `OgMd1Progress` 14. `OgMd1Dialog` 15. `OgMd1Snackbar` 16. `OgMd1Chip` 17. `OgMd1Badge` 18. `OgMd1Divider` 19. `OgMd1Avatar` 20. `OgMd1Tooltip` 21. `OgMd1Menu` 22. `OgMd1Dropdown` 23. `OgMd1ExpansionTile` 24. `OgMd1RefreshIndicator` 25. `OgMd1BottomSheet` 26. `OgMd1Drawer` 27. `OgMd1NavigationRail` 28. `OgMd1IconButton` 29. `OgMd1FAB` 30. `OgMd1Toolbar` 31. `OgMd1Breadcrumb` 32. `OgMd1Stepper` 33. `OgMd1DatePicker` 34. `OgMd1TimePicker` 35. `OgMd1SearchBar` 36. `OgMd1LoadingIndicator` 37. `OgMd1Elevation` 38. `OgMd1Scrollbar` 39. `OgMd1SnackbarAction` 40. `OgMd1ToggleButton` 41. `OgMd1SegmentedButton`

## 四、执行原则
- 每 5 个控件一批，每批 3 审计+3 修复（沿用十批机制）。
- 先建基础令牌层（颜色/字阶/尺寸/阴影/圆角），再建控件层，再逐页迁移。
- 每批全门禁+CI+截图核验（截图矩阵按 MD1 重录）。
- 页面迁移顺序：设置 → 关于 → 仓库 → 议题 → 内容页 → 其他。
- 老控件文件保留直到对应页面迁移完再删（避免半迁状态）。

## 五、验收标准
- `rg "ElevatedButton|TextButton|ListTile|Card\(|AppBar\(|Scaffold\(" lib/surface` 可见控件 0 处。
- 截图矩阵 122 张全部为 MD1 形态（紫蓝 AppBar、2dp 圆角、强阴影、FAB）。
- 门禁全绿、CI+Build 绿、30 语言不受影响。
