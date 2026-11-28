# MD2 全面迁移任务书（M 系列）

> 用户决策（2026-11-28）：**完全采用 MD2，不再保留任何 MD3 元素，应用布局形态也按 MD2 重构。**
> 最高原则：**代码标准、可靠**。不走 `useMaterial2` legacy 开关（冻结 API），不引僵尸包；
> 用官方维护的 widget + 我们自己的 ThemeData 按 MD2 权威规格实现，每一步门禁可验证。

## 权威规格依据（只认这两份，不凭记忆）
1. MD2 官方文档存档：https://material.io/archive/design/ （组件/动效/高度/色彩章节）
2. Flutter `ThemeData` 传统构造的现行 API（按项目内已有用法推断；无法核实处标「待核实」交 CI 裁决）

## 全局铁律（每席必带）
1. **禁读 Flutter SDK**：禁止读取/下载/复制 /root/flutter、/opt/flutter、/tmp/dart-sdk、pub 缓存包源码。
2. **层级原则**：L0 kernel → L1 base → L2 domain → L3 surface 单向；layer_audit --fatal 0 违规。
3. **代码洁癖**：不留死代码/空回调/注释掉的旧代码；MD3 痕迹删干净（surfaceContainer* 系、outlineVariantStrong、dynamic_color、Expressive 动效参数）；每个改动注释写为什么。
4. **不保留 MD3 语义**：删 `dynamic_color` 依赖与设置项；ColorScheme 回 primary/secondary/surface 传统角色；Elevation 回真实投影（黑影、2/4/8 档）；圆角 4/8；触控 48dp 保留（无障碍不降级）。
5. **30 语言 i18n、四层架构、runtime gate、全部功能库不动**。

## 迁移批次（严格顺序，依赖链）

### M-1 · 主题层重写（lib/surface/theme.dart + util/）
- ColorScheme：`ColorScheme.fromSeed` → 传统构造（primary=GitHub 蓝 #0969DA、secondary=灰蓝、surface=白/#121212、background/baseline 兼容字段）
- 删 `dynamic_color` import 与 DynamicColorBuilder（og_l_app.dart）、删设置页「跟随系统配色」开关行及其 i18n 键（30 语言同步删）
- 删 OgLSemanticColors 扩展？**不删**——success/warning/info 语义色保留（MD2 也有语义色需求），但明暗取值按 MD2 重校（对照 2018 色板）
- Elevation：全部改真实投影（shadowColor: Colors.black26 档位 2/4/8），删 surfaceContainer 依赖
- Shape：OgLRadius 改 4/8 两档 + pill，xl=28 删除；对话框 8、卡片 4、弹层 8
- Typography：字面用 MD2 档（headline1-6/subtitle/body/caption/overline），组件字号回传统档
- OgLSpace 8dp 体系保留（与设计系统无关）
- 验收：rg surfaceContainer* 全仓 0 处；rg fromSeed 0 处；rg dynamic_color 0 处；contrast_audit 重跑过

### M-2 · 布局形态重构（client_shell + og_l_app_bar + og_l_app）
- 底栏 NavigationBar（M3 组件）→ **BottomNavigationBar**（MD2 形态：固定 4-5 项、selectedFontSize 动画）
- NavigationRail → 保留组件但形态按 MD2（无 tonal 轨道底色、真投影、labelType 按宽度）
- AppBar：删 scrolledUnderElevation 语义，回 elevation 4 + 真投影；OgLAppBar 简化
- 切页透明度/位移等 M3 语义参数清理
- 验收：rg "NavigationBar(" 0 处（只剩 BottomNavigationBar）；外壳三态正常

### M-3 · 动效体系重写（motion.dart + animations.dart）
- 档位表按 MD2：线性/标准 easing（Curves.easeOut 300ms 标准）、**删弹簧物理/blur/stagger/revealScale 全套 Expressive 参数**
- 转场回 MaterialPageRoute 平台默认或简单 fade/slide；删 shared-axis 语义
- motion_audit / motion_coverage_audit / ui_audit / contrast_audit 判据同步重写（M2 规格）
- 验收：四支门禁重写后全绿；反向验证仍能拦缺陷

### M-4 · 页面与组件收编 + 清理
- 全 82 个 surface 文件 rg 扫描残留 MD3 痕迹（surfaceContainer*/outlineVariantStrong/动态色/大圆角）逐个收编
- settings_page 删「跟随系统配色」「动态色」UI；关于页 MD3 相关自检区文案调整
- 测试断言同步（theme/motion/page_transitions/ui_regression）
- 验收：全门禁绿 + rg MD3 痕迹 0 处 + i18n_scan 过

## 执行纪律
- 严格顺序 M-1 → M-2 → M-3 → M-4（依赖链，主题是地基）
- 每批：派代理（带铁律）→ 主会话核验（format 0 changed + layer_audit + gate_of_gates + i18n_scan + rg 验收标准）→ 本地提交 → CI 裁决（推送待新令牌）→ 下一批
- 四批完成后：MD2 迁移总报告 + 待推提交清单；推送/发版仍等新令牌
- 推送与 CI 验证在新令牌到位后一次性补做；迁移期间本地门禁是唯一裁决（Flutter 编译仍靠 CI，标注待核实项）
