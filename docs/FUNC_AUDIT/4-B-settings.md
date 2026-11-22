# 功能审计 4-B · 设置持久化

> 文档戳：**2026-11-23 07:04:56 +08:00 · v15.0.0**
> 审计范围：`lib/surface/settings.dart`（全文 1143 行）、`lib/surface/pages/settings_page.dart`（全文 2373 行）、`lib/surface/pages/settings_section_page.dart`（42 行）、`lib/surface/widgets/settings/settings_group.dart`（524 行）、`lib/base/disk/` 中 KV 存储部分（`platform_io_impl.dart:374-427` / `:115-134`、`disk_bridge.dart`、`kernel/contract/disk_store.dart`），并按需核对接线点 `surface_bridge.dart`、`theme.dart`、`net_dns.dart`、`net_bridge.dart`、`i18n/og_l_i18n.dart`、`app/motion.dart`、`app/font_loader.dart`、`test/surface/settings_test.dart`。
> 纪律：只读审计；每条问题 `file:line` 均可 `rg` 复现；本地仅用 `/opt/dart/bin/dart` 做类型复现，未读 Flutter SDK、未改代码、未 commit。

## 问题总览

| 级别 | 数量 | 编号 |
| --- | --- | --- |
| P0（数据丢失/崩溃/安全） | **1** | 4B-01 |
| P1（功能失效/不一致） | **4** | 4B-02 ~ 4B-05 |
| P2（打磨） | **4** | 4B-06 ~ 4B-09 |
| 合计 | **9** | |

---

## 严重（P0）

### 4B-01 `fromJson` 对 `tagsPerPage` 的 `contains` + `as int` 组合会抛异常，击穿「反序列化永不抛」纪律

- **file:line**：`lib/surface/settings.dart:250-251`
  ```dart
  tagsPerPage: <int>{20, 30, 50, 100}.contains(raw['tagsPerPage'])
      ? raw['tagsPerPage'] as int
      : 30,
  ```
- **症状**：手改配置（或任何把该字段写成 JSON 浮点 `30.0` / `20.0` 的旧版本、导入配置）时，`OgLSettings.fromJson` 抛 `_TypeError: type 'double' is not a subtype of type 'int'`。`load()` 的 catch 把**全部设置**回落 `OgLSettings.defaults`（`settings.dart:795-800`），磁盘上的坏文件不会被覆盖，于是**每次启动都失败**——语言、DNS、加速知情同意、字体等全部永久回到默认；用户只看到一条错误横幅。这是文件头 `:20-22` 明确承诺「坏字段回落默认、一处坏值不等于全部设置丢失」的反面。
- **根因**：Dart 的 `Set<int>.contains(30.0)` 为 `true`（`30 == 30.0` 成立），但随后的 `as int` 对 `double` 运行期失败。同一 bug 模式与 `_motionLevelOf`（`:243-250`）里专门注释挡掉 Infinity/NaN 的教训同类：判据与取值用的是两种类型语义。仓库测试「fromJson 永不抛」组（`test/surface/settings_test.dart:431+`）没有覆盖 `tagsPerPage` 的 double 输入，所以 CI 全绿。
- **复现**：`/opt/dart/bin/dart /tmp/verify_types.dart`（本次实测）：`raw=30.0 (double) contains=true result=THREW: _TypeError`。
- **修复指令**：`lib/surface/settings.dart:250-251` 改为复用已有容错助手写法，例如
  ```dart
  tagsPerPage: _asInt(raw['tagsPerPage'], fallback: 30) is int &&
          <int>{20, 30, 50, 100}.contains(_asInt(raw['tagsPerPage'], fallback: 30))
      ? _asInt(raw['tagsPerPage'], fallback: 30)
      : 30,
  ```
  更干净的做法是增加 `static int _asChoiceInt(Object? value, Set<int> allowed, int fallback)` 统一处理 int / 有限 num / 越界，并让 `tagsPerPage`、`downloadConnections`（`:263-266` 的 `_asDownloadConnections` 已有 `is int` 前置，本身安全）共用。同时在 `test/surface/settings_test.dart` 的「P1 回归 · fromJson 永不抛」组补一条 `OgLSettings.fromJson({'tagsPerPage': 30.0})` 不抛且回到 30 的断言。

---

## 中（P1）

### 4B-02 「恢复默认」不重载语言分片：显示语言与落盘值不一致，且要重启才生效

- **file:line**：`lib/surface/pages/settings_page.dart:281`（`await _settings.reset();`）、`lib/surface/settings.dart:1116-1121`（`reset()` 只 `apply(defaults)` + `clear()`）、`lib/surface/surface_bridge.dart:480-483`（**只有** `setLanguage` 会 `OgLI18n.instance.load(...)`）、`surface_bridge.dart:674`（启动时一次）
- **症状**：用户在德语/日语界面点「重置设置」→ `defaults.languageCode == 'zh'` 已写盘，但 `OgLI18n.instance.locale` 仍是旧语言：界面继续显示德/日文案，语言选择行的 `valueLabel`（读 `OgLI18n.instance.localeLabel`，`settings_page.dart:654`）也显示旧语言自称，与当前值 `zh` 不符；下次启动才变成中文。
- **根因**：i18n 的运行时加载被绑死在 `setLanguage` 这一条写入路径上，而 `reset()` 是另一条绕过它的写入口。全仓库 `OgLI18n.instance.load` 仅两处（启动 + setLanguage），无任何监听 `settings` 变化的自动同步。这正是维度⑥「显示值与实际值是否一致」的典型破口。
- **修复指令**：`lib/surface/surface_bridge.dart` 增加 `Future<void> resetSettings()`：先 `await settings.reset()`，再 `await OgLI18n.instance.load(settings.settings.languageCode)`（复用 `setLanguage` 的加载语义）；`settings_page.dart:281` 改为调 `widget.surface.resetSettings()`。或更彻底：在 `SurfaceLayerModule.onRegister` 给 `settings` 加 listener，检测到 `languageCode` 变化时统一触发 `OgLI18n.instance.load`，去掉 setLanguage 里的重复加载。

### 4B-03 `seedColorId` 无白名单：失效旧值残留，UI 显示的色点与勾选状态与落盘值不符

- **file:line**：`lib/surface/settings.dart:183`（`seed is String && seed.isNotEmpty ? seed : 'github'`——只查非空）、`lib/surface/theme.dart:40-47`（`kOgLSeedColors` 只有 7 个 id）、`theme.dart:62-68`（`ogLSeedColorLabel`/`ogLSeedColorOf` 未知 id 回落 github）、`settings_page.dart:578-591`（选择行 `current: value.seedColorId`）
- **症状**：配置里出现 `indigo`（旧版种子色 / 手改 / 迁移残留）时，存储值是 `indigo`，但色点画的是 GitHub 蓝、标签写「GitHub」，选择弹窗里**没有任何一项打勾**（`settings_group.dart:256` 的 `option.value == current` 恒 false）。用户看到「选了色却没选中」，且不知道磁盘里存的是无效值。测试 `test/surface/settings_test.dart:334` 甚至用 `seedColorId: 'indigo'` 构造 fixture，正说明这个值在测试里是合法的假象。
- **根因**：`OgLSettings.languageCodes` 为语言做了白名单（`:343-372`），`codeThemePreset` 有 `_asPreset`（`:334`），唯独 `seedColorId` / `uiFontId`（`:265-268`）/ `dnsServerId`（见 4B-04）只做非空检查。维度③「旧键值失效」没有对展示层枚举做校验。
- **修复指令**：`lib/surface/settings.dart` 增加 `static const List<String> seedColorIds`（从 `theme.dart:kOgLSeedColors.keys` 同步，或把 id 表下沉到共享常量避免两处清单），`fromJson` 改为 `seed is String && seedColorIds.contains(seed) ? seed : 'github'`；`setSeedColor`（`:918`）也用同一白名单。`uiFontId` 同理用 `OgLBuiltinFonts.isBuiltin(id) || customFonts` 校验。注释里写明与展示层同步，借鉴 `codeThemePresetIds`（`:318-320`）的写法。

### 4B-04 `dnsServerId` 无白名单：失效 id 导致「显示原文 id + DNS 实际未生效」

- **file:line**：`lib/surface/settings.dart:195-196`（只查非空）、`lib/base/net/net_dns.dart:200-231`（内置 5 家 id：`alidns/dnspod/dns114/cloudflare/google`）、`lib/surface/pages/settings_page.dart:1090-1093`（`dnsServerChoices[value.dnsServerId] ?? value.dnsServerId`）、`lib/base/net/net_bridge.dart:104-110`（`applySelection` 对无效 id 拒绝并只留诊断）
- **症状**：迁移/手改留下未知 `dnsServerId`（例如历史 id 被删）时，DNS  servers 选择行的值标签直接显示裸 id（如 `dns114` 若不在 choices 映射里），弹窗无勾选；`applyDnsSelection` 静默拒绝该选择（`net_bridge.dart` 注释称「不静默」，但那只是写诊断日志，UI 无任何提示），用户以为在用自定义 DNS 实则走系统解析。
- **根因**：与 4B-03 同源——持久化层不认识展示/底座层的合法值集合，坏值能穿过 `fromJson` 一直活到策略应用层。
- **修复指令**：把内置 DNS id 集合作为共享常量（可从 `net_dns.dart:builtinDnsServers` 派生）暴露给展示层；`settings.dart` 的 `fromJson` 与 `setDnsServer`（`:887-888`）统一校验 `id == 'custom' || builtinIds.contains(id)`，否则回落 `'alidns'`。同时在 `_storageSummary`（`settings_page.dart:135-139`）把无效 id 显示成「未生效」而不是裸 id。

### 4B-05 写盘无串行化、无失败回滚：连续快速改动可被旧快照覆盖，写失败后内存与磁盘长期分叉

- **file:line**：`lib/surface/settings.dart:841-860`（`apply`：`_settings = next; notifyListeners(); await _persistence.write(...)`）、`settings.dart:1116-1121`（`reset`：`apply(defaults)` 后再 `clear()`）、`lib/base/disk/platform_io_impl.dart:115-128`（单次 `writeText` 是原子的 tmp→fsync→rename，但**多次 write 之间没有队列**）
- **症状**：
  1. 两个开关被快速连拨时，`apply(A)` 与 `apply(B)` 的 `write` 并发；若 B 的 rename 先完成、A 后完成，磁盘最终是 A 的快照（较旧），而内存是 B。下次启动 B 的改动消失——**无提示、无错误横幅**。
  2. 写失败时实现刻意保留内存新值并弹横幅（`settings.dart:853-859`），但没有重试、没有回滚、也没有「未保存」持续标记：`clearLastError()` 一弹即清，用户此后以为已保存；重启后改动全部丢失。文件头注释「**先落盘**；失败保留内存新值」（`:841`）本身自相矛盾——实际是先改内存再落盘。
  3. 每次 `setXxx` 都 `next.encode()` **全量写整个 JSON**，没有任何合并/防抖。当前 UI 中滑杆已用 `onChangeEnd` 只提交一次（`settings_group.dart:415-419`），选择行也过滤了同值（`settings_group.dart:263`），所以正常操作不构成写风暴；但 `_editCustomDns`（`settings_page.dart:1216-1217`）一次保存连写两次（DoH + IP），批量 `setAccelScope` 若未来循环调用将 N 次全量写。
- **根因**：`OgLSettingsController.apply` 把「内存权威」与「落盘权威」视为可异步分叉而不加同步原语；`DiskKv.write` 只承诺单次原子，不承诺调用序列的顺序。
- **修复指令**：在 `OgLSettingsController` 内加串行写队列（`Future<void> _writeTail = Future.value();`，`apply` 中 `_writeTail = _writeTail.whenComplete(() => _persistence.write(snapshot))`，并把输入的 `next.encode()` 在入队**前**算成局部字符串，避免读到后续快照）；给待写计数/版本加标记，写失败时保留 `lastError` 直到下一次成功覆盖（不要一弹即清），并提供显式 `discardUnsaved()`/回滚到上一次成功快照；把 `:841` 注释改成「先改内存并通知，随后串行落盘」。批量场景（自定义 DNS 双写、加速范围批量开关）增加 `applyBatch(void Function(OgLSettings) mutate)` 合并为一次写。

---

## 轻（P2）

### 4B-06 `languageCodes` 注释停留在「6 种」，与 30 项真实清单矛盾（v10.3.0 踩坑的假情报残留）

- **file:line**：`lib/surface/settings.dart:338-341`
  ```
  /// v6.4.0 起收敛为 **6 种**（简中 / 繁中 / 英 / 德 / 法 / 俄）——
  /// 与 [OgLI18n.locales]、语言资源目录及 pubspec 声明保持一致。
  ```
  实际 `:343-372` 有 30 项；`docs/I18N.md:54` 也写「回落（第 377、1111 行）」行号已漂移。
- **症状**：维护者按注释以为白名单只有 6 种，新增/删语言时按错误基线改动，可能重演 v10.3.0「选择即失效」。
- **根因**：白名单本体已补到 30，注释未同步（QUALITY_STANDARD 55「过时的白名单/注释是假情报」）。
- **修复指令**：删除「6 种」句，改为「与 `OgLI18n.locales` / 语言目录 / pubspec 三处同步，当前 N 项由 `tool/i18n_scan.py --check` 保证」；同步修正 `docs/I18N.md:54` 的行号。
- **一致性结论**：本次用脚本实测 `languageCodes`(30) == `OgLI18n.locales`(30) == pubspec 声明(30) == `assets/i18n/` 目录(30)，**三处完全一致，v10.3.0 的选择即失效未复发**；`python3 tool/i18n_scan.py --check` 亦通过。`seedColors` 的 7 个 id 与 `kOgLSeedColorLabelKeys` 7 个键自身一致，缺口在 `fromJson` 未对齐（见 4B-03）。

### 4B-07 `_t('ok')` 取错分片：添加私有字体弹窗的确认按钮在所有 30 种语言下都显示裸 `ok`

- **file:line**：`lib/surface/pages/settings_page.dart:847`（`child: Text(_t('ok'))`，`_t` 固定取 `settings` 分片，见 `:305-309`）；`assets/i18n/en/common.json:42` 有 `"ok": "OK"`，但**全部 30 个** `assets/i18n/*/settings.json` 都没有 `ok` 键（已逐一核对）。
- **症状**：设置→界面→字体→管理→从链接添加，「取消」有本地化文案，「确定」按钮显示字面量 `ok`。
- **根因**：`_t`/`_tc` 是硬编码分片捷径；`i18n_scan.py --check` 只校验「各语言分片键集合与 zh 对齐」和「有无未本地化中文字面量」，**不校验 `_t('key')` 引用的键在分片中是否存在**（实测该工具检查通过），所以缺失键一路漏到运行时。
- **修复指令**：`settings_page.dart:847` 改为 `_tc('ok')`（`common` 分片已有该键且 30 语言齐全）；另在 `tool/i18n_scan.py` 增加「Dart 源码 `_t('k')`/`_tc('k')` 引用键必须存在于对应分片」的静态检查，避免同类复发。

### 4B-08 删除加速通道 / 私有字体无二次确认、无撤销路径

- **file:line**：`lib/surface/pages/settings_page.dart:1611-1615`（`removeAccelChannel` 的 `IconButton` 直接删除）、`settings_page.dart:803-810`（`_manageCustomFonts` 的 `del:` 分支直接 `removeCustomFont`）、`lib/surface/settings.dart:934-947`（删除当前选中通道还会顺带清空 `releaseProxySelectedId`）、`settings.dart:990-1001`（删除在用字体会回落 `system`）
- **症状**：用户在通道列表右侧点一下垃圾桶，通道连同选中状态立即消失且无确认；撤回只能重新手工填写 URL（地址已被删，无从找回）。这与同页「重置设置」有红色二次确认（`settings_page.dart:257-281`）、令牌移除用 `ogLDangerConfirm`（`profile_page.dart:136-143`）的口径不一致。
- **根因**：维度⑦所关注的「敏感项二次确认与撤销」只覆盖了重置与协议同意，未覆盖本地凭据类配置（代理地址含用户手工录入的 URL，删除即永久丢失）。
- **修复指令**：给 `removeAccelChannel` / `removeCustomFont` 入口加 `ogLDangerConfirm`（至少在删除的是**当前选中/在用**项时强制）；或在删除前把旧条目写入一个可恢复的 `lastDeleted` 缓存并提供 SnackBar「撤销」（恢复调用 `upsertAccelChannel` / `upsertCustomFont`）。

### 4B-09 `motionLevelIds` 成为只被注释引用的死常量

- **file:line**：`lib/surface/settings.dart:320-321`（`static const List<int> motionLevelIds = <int>[0, 1, 2, 3];`）；引用处 `settings_page.dart:624` 仅在文档注释里写「与 [OgLSettings.motionLevelIds] 一一对应」，`rg -rn motionLevelIds lib/ test/` 只有这两处。
- **症状**：档位真值其实由 `_motionShort.length`（`settings_page.dart:181-186`）与 `OgLOAnimQuality.of(level)`（`app/motion.dart`）决定，常量与实现可能各自漂移；违反 QUALITY_STANDARD 55。
- **根因**：重构（5.2 把档位语义从「最小/当前/标准/增强」改为质量描述）后旧常量未清理，也未改成真正的校验来源。
- **修复指令**：删除该常量，或让 `setMotionLevel`（`settings.dart:1003-1007`）用它做统一夹紧、并让 `_motionShort` 按该常量长度构建，使常量成为单一真相。

---

## 已检查清单（逐项，含无问题项）

| 文件 / 区域 | 行数 | 检查内容 | 结论 |
| --- | --- | --- | --- |
| `lib/surface/settings.dart:1-60` | 60 | 文件头纪律、`_asDownloadConnections`、`OgLThemeMode.parse`、`OgLCustomFont.fromJson` | ✅ 容错正确；`OgLCustomFont` 要求 id+filePath 非空，坏条目丢弃 |
| `settings.dart:110-176` | 67 | 构造器 40+ 字段默认值、保守默认语义 | ✅ 新字段均取「等于旧行为」的默认值 |
| `settings.dart:176-283` | 108 | `fromJson` 全部字段容错 | ❌ 4B-01（tagsPerPage）；其余 `_asBool/_asInt/_clampDouble/_asColorInt/_motionLevelOf` 对 bool/int/double/NaN/Infinity 处理正确，已逐条对照并用 dart 实测 |
| `settings.dart:290-377` | 88 | `_asAccelChannels`、`_asAccelScopes`、`_asAccelSelectedId`、`_asPreset`、`languageCodes`、`_asLocale`、`_clampDouble` | ⚠️ 白名单本体一致；注释漂移 4B-06；`codeThemePreset` 有白名单（对照出 seed/dns 缺口） |
| `settings.dart:377-579` | 203 | 各字段 getter、`activeAccelChannel`、`accelPrefixesFor`、`activeAccelPrefixes` 安全门（总开关/协议/通道/范围四重） | ✅ 无令牌误送路径；`activeAccelPrefixes` 任一不满足即空列表 |
| `settings.dart:579-741` | 163 | `copyWith` 全字段、`toJson`/`encode` 全字段往返 | ✅ 无漏字段；`tagDeleteConfirm` 因 `??` 不能写 false，setter 用 fromJson 重建（`:867-872`）是正确绕过 |
| `settings.dart:741-836` | 96 | `OgLSettingsPersistence` 接口、内存实现、控制器 load 世代 `_loadGen` | ✅ 迟到 load 不覆盖新值；错误不吞、可见 |
| `settings.dart:841-860` | 20 | `apply` 写盘 | ❌ 4B-05 |
| `settings.dart:860-1120` | 261 | 全部 `setXxx` / `upsert` / `remove` / `acceptAccelConsent` / `reset` | ⚠️ 4B-03/04（入口未校验）、4B-05、4B-02（reset）；滑杆与档位夹紧正确 |
| `lib/surface/pages/settings_page.dart:1-320` | 320 | 头部、`_pickCodeColor`、`_reset`、`_t/_tc`、`_setLanguage`、捐赠二次确认 | ⚠️ 4B-02；捐赠 `_donateStar`（`:332-388`）有二次确认+幂等检查，无问题 |
| `settings_page.dart:320-539` | 220 | `build` 全部入口、错误横幅、`_entry`/`_navTile` 路由 | ✅ 每个入口都有 onTap；错误横幅读 `lastError` |
| `settings_page.dart:540-899` | 360 | `_interfaceGroup` 全控件、`_applyUiFont`、字体增删 | ⚠️ 4B-03（种子色展示）、4B-07（ok）、4B-08（字体删除）；`onSelected/onChanged` 全部接到真实 setter，无空回调 |
| `settings_page.dart:900-1259` | 360 | `_codeGroup`、DNS/自定义 DNS 编辑 | ✅ `tagSort/tagsPerPage/tagDeleteConfirm/code*/foldersFirst` 全接 setter；`_editCustomDns` 双写顺序有注释防明文窗口（正确），但见 4B-05 |
| `settings_page.dart:1259-1430` | 172 | `_storageGroup`、权限/SAF 弹窗、下载并发入口 | ✅ 无持久化写入缺口；`setDownloadConnections` 同步推给下载管理器（`surface_bridge.dart:469-472`） |
| `settings_page.dart:1430-1709` | 280 | `_downloadTiles`、`_accelTiles`、协议同意弹窗、私有加速 3 秒冷静期警告 | ✅ 危险项二次确认/冷静期完整；`accelConsentVersion/At` 留痕落盘；`onChanged` 全接桥 |
| `settings_page.dart:1709-2038` | 330 | 警告倒计时、第三方协议勾选、添加通道 URL 校验 | ✅ `ogLValidateAccelBaseUrl` 校验、`agreed` 才落同意凭据；无空回调 |
| `settings_page.dart:2038-2373` | 336 | 账户行、关于/许可/日志、通用零件 | ✅ 全为只读/导航，无持久化需求；日志已订阅 `ListenableBuilder` |
| `lib/surface/pages/settings_section_page.dart` | 42 | 子页状态归属 | ✅ 无状态复制（`widget.surface.settings` 单点权威），无写入 |
| `lib/surface/widgets/settings/settings_group.dart:1-280` | 280 | `ogLShowSettingsChoice`（同值不回调）、`OgLSettingsGroup`、`OgLSettingsChoiceTile` | ✅ 选择行 `picked == current` 时跳过，天然防重复写 |
| `settings_group.dart:280-524` | 244 | `SwitchRow`、`SliderRow`（草稿值 + `onChangeEnd` 一次提交）、`DangerCard` | ✅ 防写风暴设计到位（与 4B-05 的控制器层缺口区分） |
| `lib/base/disk/platform_io_impl.dart:115-134` | 20 | `IoDiskFileStore.writeText` 原子性 | ✅ 唯一 temp 名 + `flush: true` + rename，并发不互踩 |
| `platform_io_impl.dart:374-427` | 54 | `IoDiskKv.read/write/remove/keys` | ✅ key 走 sha256 文件名；读时校验 `decoded['k'] == key`（防碰撞/脏数据）；损坏即自清；**单次写原子，但无跨调用排序**（4B-05 根因之一） |
| `lib/kernel/contract/disk_store.dart:12-78` | 67 | `DiskKv` 抽象与 `InMemoryKv` | ✅ 接口语义清晰，内存实现一致 |
| `lib/base/disk/disk_bridge.dart` | 160 | 门面装配 | ✅ `disk.kv` 经门面暴露，无旁路 |
| `lib/surface/surface_bridge.dart:236-310, 465-494, 605-674` | ~140 | DNS 五连 setter、`setLanguage`、`KvSettingsPersistence`、模块装配 | ⚠️ 4B-02（i18n 加载只在 setLanguage）；`KvSettingsPersistence` 直接转 `_kv.read/write/remove(key)`，正确 |
| `lib/surface/theme.dart:24-71` | 48 | 种子色表、标签表、未知 id 回落 | ⚠️ 4B-03；两张表自身 7↔7 一致 |
| `lib/base/net/net_dns.dart:199-231` / `net_bridge.dart:83-112` | 50 | 内置 DNS id、`applySelection` 对无效 id 的处理 | ⚠️ 4B-04 |
| `lib/surface/i18n/og_l_i18n.dart:97-127, 242-279` | 61 | `locales` 30 项、`t()` 缺失键回落键名 | ✅ 白名单一致；⚠️ 4B-07（缺键不报错） |
| `lib/surface/app/motion.dart:299-306` | 8 | `reduceMotion` 与 `motionLevel` 的合并语义 | ✅ `motionLevel<=0` 强制关，其余尊重旧键；`reduceMotion` 开关不是假选项 |
| `lib/surface/app/font_loader.dart:24-39` | 16 | `OgLBuiltinFonts` 三个 id | ✅ 与设置页选项一致；⚠️ 4B-03（fromJson 未校验） |
| `assets/i18n/{en,zh}/settings.json` + 全部 30 语言目录 | 201 键/份 | 设置页 147 个 `_t` 键、12 个 `_tc` 键逐键比对 | ⚠️ 仅 `ok` 缺失（4B-07）；`common` 分片 12 键全齐 |
| `test/surface/settings_test.dart` | 489 | 容错/往返/控制器/DNS 往返/「fromJson 永不抛」组 | ⚠️ 覆盖良好但漏 `tagsPerPage: 30.0`（4B-01）；fixture 用无效 `indigo`（4B-03 佐证） |
| `python3 tool/i18n_scan.py --check` | — | 仓库自带一致性门禁 | ✅ 通过（30 语言 × 28 分片键集合一致、三处语言清单一致），但不校验引用键是否存在（4B-07） |

---

## 本席结论

设置持久化的**主干是健康的**：`languageCodes` 30 项与 `OgLI18n.locales` / `pubspec` / 资源目录三处实测完全一致，v10.3.0「选了语言却存成 zh」的踩坑**未复发**；`fromJson` 对 bool/int/double/NaN/Infinity/颜色值的大多数分支、`copyWith`/`toJson` 全字段往返、写盘原子性（唯一临时名 + fsync + rename）、load 世代防回退、滑杆 `onChangeEnd` 防写风暴、危险项（重置 / 协议 / 私有仓库令牌警告）二次确认与冷静期，均有可核对的实现。

但存在 **1 个 P0**：`tagsPerPage` 的 `Set<int>.contains(double)` + `as int` 组合会让一次「看起来合法」的手改配置变成**每次启动全量设置丢失**（已用本地 Dart 实跑复现）。另有 4 个 P1：重置不 reload i18n 造成显示/落盘语言分叉、`seedColorId` 与 `dnsServerId` 缺白名单造成旧值失效却静默显示回落、以及 `apply` 写盘无串行化/无回滚造成快速连拨时旧快照可能覆盖新值且写失败后内存与磁盘长期不一致。4 个 P2 以注释漂移、i18n 引用键缺校验、删除无撤销、死常量为主。

建议修复顺序：**4B-01 → 4B-05 → 4B-02 → 4B-03/04 → P2**；其中 4B-01 与 4B-07 应同步补测试/门禁，否则同类缺陷仍会在 CI 全绿下复发。本轮仅审计，未改任何代码。
