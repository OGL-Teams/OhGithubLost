# MD2 迁移报告（M-1 · 主题层重写）

> 文档戳 v15.0.0 · 2026-11-28 · M-1 批次（主题层 + util），不 commit / 不 push。
> 规格依据：https://material.io/archive/design/ （网络受限时按任务书描述执行）。

## 一、ColorScheme 重写（lib/surface/theme.dart）
- `ColorScheme.fromSeed` 全部删除（主题 + boot_splash 兜底），改传统构造：
  - primary = `#0969DA`（GitHub 蓝）；onPrimary = 白
  - secondary = `#57606A`（灰蓝）；onSecondary = 白
  - surface = 白 `#FFFFFF` / 暗 `#121212`；onSurface = `#1F2328` / `#E6EDF2`
  - background = surface、onBackground = onSurface（MD2 兼容字段，显式给出）
  - error = `#B3261E`（亮）/ `#F85149`（暗）；onError = 白
  - outline = `#8C959F` / `#444C56`；inverseSurface / inversePrimary 仅 SnackBar 用
- `buildOgLTheme(brightness, {seedColor, density})`：多主题色改为对 primary 单字段覆盖
  （ColorScheme.copyWith(primary/onPrimary)），语义仍是「传统构造 + 局部覆盖」。
- kOgLSeedColors 六个备选色全保留（id 集不变，设置页无感）。

## 二、删除的 MD3 特性
1. **dynamic_color**：pubspec 删依赖；og_l_app.dart 删 import、DynamicColorBuilder、
   dynamicScheme 传递；surface_bridge.dart 删 dynamicOverride / harmonized /
   _themeCacheDynamic；settings.dart 删字段/fromJson 键/copyWith/setDynamicColor；
   settings_page.dart 删开关行；30 语言 settings.json 删 `dynamicColor` 键。
   （老配置文件里的 `dynamicColor` 键由 JSON 容错反序列化自然忽略。）
2. **tonal 分层**：`ColorScheme.fromSeed`、`surfaceContainer/Low/High/Highest` 在
   lib/ 全部删除；替代角色：
   - 输入框 / Chip / 骨架 / 代码块底 / 分支条 / 状态栏 / readme code / 弹层底 → `surface`
   - 卡片 → surface + elevation 2 + outlineStrong 描边（MD2 卡片形态）
   - 骨架块 / 禁用按钮底 / 进度条未达段 → `surfaceVariant`（MD2 传统角色，暗 #2A2D31、亮 #EFF2F5）
3. **primary/secondaryContainer、onPrimaryContainer、onSecondaryContainer、tertiary、
   surfaceTint、inversePrimary、outlineVariant、scrim**：ColorScheme 只显式给 MD2 角色；
   这些 M3 getter 全部从 lib/ 移除：
   - 通知语义底色 → OgLSemanticColors（success/info）/ warning（新增 warning 角色）
   - 选中态 / 高亮 / 撤销条 / tonal 按钮 → primary 或 surfaceVariant
4. **Elevation 回真实投影**：卡片 2、菜单级 4、弹层 8、对话框 16、appBar 4；
   shadowColor = Colors.black26；全部 `surfaceTint: Colors.transparent`、
   `scrolledUnderElevation` 删除（M-2 批次不再回访）。
5. **useMaterial3: true → false**（传统 Material 组件视觉）。

## 三、Shape（og_l_radius.dart + theme.dart）
- OgLRadius 六档 → `xs=2 / md=4 / lg=8 / pill`，**xl=28 删除**（连带 cXl、verticalTopXl）；
  verticalTopLg 保留（弹层上沿 8）。全 lib 只剩 theme.dart 一处引用（对话框 8）。

## 四、Typography（theme.dart）
- 组件字号按 MD2 档：按钮 14 / appBar 标题 20 / 对话框标题 20 / 正文 14 / caption 12 /
  Chip 12 / 导航标签 12；testTheme 字段保留，派生逻辑不变。

## 五、OgLSemanticColors
- 保留 success/warning/info；**outlineVariantStrong 字段删除**（原为补 M3
  outlineVariant 对比度不足——MD2 下分割线统一走 outline，取用点同步收编）。
- 明暗取值按 MD2 重校（对照 2018 色板 + WCAG）：亮 success `#1A7F37` / warning
  `#9A6700` / info `#0969DA`；暗 success `#3FB950` / warning `#D29922` / info `#58A6FF`；
  on* 全白（亮）/ #121212（暗）。

## 六、测试与门禁改动
- test/surface/code_editor_test.dart: `scheme.surfaceContainerHighest` → `scheme.surfaceVariant`。
- contrast_audit.py 暗色底色表改为 MD2 面（surface #121212 / variant #2A2D31），
  解析仍依赖 OgLSemanticColors 构造形态（结构未变），跑通。
- ui_audit.py 原白名单机制天然兼容（旧值从 lib/ 移除后不再需要豁免）。
- gate_of_gates 的 contrast_audit 门槛输出不变。

## 七、rg 验收证据（本仓库工作区实测）
```
rg "surfaceContainer" lib/        → 0 处
rg "fromSeed" lib/                → 0 处
rg "dynamic_color|DynamicColorBuilder" lib/ → 0 处
rg "OgLRadius.cXl" lib/           → 0 处
rg "useMaterial3: true" lib/      → 0 处
rg "dynamicColor" lib/            → 0 处
```

## 八、门禁结果
- dart format：0 changed
- layer_audit --fatal：0 违规
- gate_of_gates --fatal：全绿
- i18n_scan --check：通过（30 语言键集合一致）
- flutter analyze / flutter test：**本地无 Flutter SDK（禁读铁律），标待核实**

## 九、待核实项
1. M-2/M-3 批次尚未执行：`BottomNavigationBar` / `NavigationBar` 收编、
   `pageTransitionsTheme`、`motion.dart` Expressive 参数、82 页收尾扫描仍在。
2. `flutter analyze` / `flutter test` 未本地运行——traditional ColorScheme 参数名
   （background/onBackground、onPrimary 等新签名）、`DialogThemeData` / `CardThemeData`
   / `TabBarThemeData` 记录名是否与当前 Flutter 版本对齐，**待 CI 裁决**。
3. boot_splash 兜底界面的 MD2 化随 M-2 批次处理。
4. 老 JSON 配置遗留 `dynamicColor` 键：已验证 fromJson 容错忽略，不需迁移。
5. MD2 官方存档站点本轮网络不可达时，部分取值（#B3261E error 等）按任务书指定值执行。
