# 第8批 · 视角A：i18n 门禁实现正确性审计（v12.0.0 LTS）

审计方式：范围内文件全部 `file_read` 完整读（含 677 行 `inject_platform_spec.py` 分两段读、134 行 common.json 全文读），未以 rg 正则代替阅读；裁决依据 `docs/QUALITY_STANDARD.md`（59 条原则）、`AGENTS.md`（95 行）均完整读。只审不改，**未写 lib/**；python 门禁与 CLI 探针只在 `/tmp` 或临时目录运行，未改动仓库任何受审文件。
实测环境：Alpine Linux aarch64 / Python 3；`dart`、`flutter` 均不在 PATH（`which` 返回空），故所有 Dart 运行时行为由源码静态推导，需运行时的条目一律标「待议」。

---

## 发现清单

### B8-A-01 · P0 · assets/i18n/{de,fr,ru,zh_Hant}/common.json:126-174 × lib/surface/i18n/og_l_i18n.dart:181-183,211-220 × lib/surface/app/token_exit_warning.dart:131,136,142（确证·代码证据＋实测）
**问题一句话**：4 个语言分片里 `tokenExitTitle/Body/Host/Confirm/Cancel/LogConfirmed/LogCancelled/Cancelled` 共 **32 个值不是字符串而是嵌套字典**（`{"de":…,"fr":…,"ru":…,"zh_Hant":…}`），`_loadPage` 用 `'${e.value}'` 把 map 转成非空字符串，于是 `_raw` 的 `isNotEmpty` 判定通过、**回落链被彻底短路**，令牌外泄确认对话框直接把字典的 `toString()` 渲染给用户。
**证据**：实测 `json.load` 全 162 个分片，`count=32  locales=Counter({'de':8,'fr':8,'ru':8,'zh_Hant':8})`，键恰为上述 8 个；`de/common.json:126-131` 原文 `"tokenExitTitle": { "de": "Dein Token verlässt dieses Gerät", "fr": "Votre jeton quitte cet appareil", … }`。`og_l_i18n.dart:181-183` `for (final MapEntry …) '${e.key}': '${e.value}'` 无类型判断；`:214-218` `if (current != null && current.isNotEmpty) return current;` 非空即返回，不再回落到 `en`（`en/common.json:126` 是正确的字符串）。`token_exit_warning.dart:131/136/140-145/152/159` 是 TOKEN-EXIT-01「令牌将离开设备」的**不可绕过**对话框（`canPop:false`、`barrierDismissible:false`）。`assets/i18n/zh/common.json:126-133`、`en/common.json:126-133` 是字符串，故 zh/en 用户正常、其余 4 语言用户中招。
**用户可见后果**：德语/法语/俄语/繁中用户在把 GitHub 令牌发给非官方主机前的**最后一道风险确认**上，看到的是形如 `{de: Dein Token verlässt dieses Gerät, fr: Votre jeton quitte cet appareil, ru: …, zh_Hant: …}` 的四国语言混杂乱码，标题、风险正文、目标主机、确认/取消按钮全部失效为字典串——用户无法理解「仍要下载」意味着把凭证交给第三方，直接构成安全知情同意失效（AGENTS.md §5「令牌安全」、QUALITY 第 38 条「错误信息面向用户」）。
**原则**：36、38、15、20、42。
**状态**：确证（JSON 值类型实测 + 渲染链路代码闭环；Flutter 真机未跑，Map.toString 的具体排版标「待议」，但「非空字符串被原样返回」由 Dart 语义确证）。

### B8-A-02 · P1 · tool/i18n_scan.py:224-242 × test/surface/i18n_test.dart:43-52 × assets/i18n/{zh,en}/common.json:2,87,115,126（确证·实测）
**问题一句话**：六语言键集合校验**只比 key 名**（`set(shard.keys())`），完全不校验值类型、空串、占位符集合、重复键、键排序与额外分片，于是 B8-A-01 的 32 个字典值在两套门禁下同时全绿。
**证据**：`i18n_scan.py:226` `zh_all = {page: set((load_shard(...) or {}).keys()) …}`；`:235-242` 只算 `missing/extra`；`--check`（`:301-321`）只吃 `ui_items / shard_problems / consistency` 三类。`i18n_test.dart:43-52` 同样 `data[page]!.keys.toSet() == en[page]!.keys.toSet()`。实测当前仓库 `python3 tool/i18n_scan.py --check` → `exit=0`、`分片校验：6 语言 × 27 页面，键集合与 zh 完全一致`、`[check] 通过`；`version_sync.py` 也 exit=0。另实测键排序：`zh/common.json`、`en/common.json` 等 **18/162 个分片键未排序**（`zh/common.json` 132 键中 130 个位置错序，首键 `accelThirdPartyBody` 应在 `accelLangNote` 之后；`openWith:87`、`guide:115`、`tokenExitTitle:126` 属后追加段），而 AGENTS.md §6 与 `docs/I18N.md:22` 明写「2 空格缩进 + **键排序** + 末尾换行」，门禁不检查。占位符集合实测 6 语言间为 0 差异，但这是数据凑巧，不是校验结果（把 `en/shell.json` 的 `home` 改成字典后 `--check` 仍 `exit=0`）。
**用户可见后果**：任何「键在、值是坏数据」的翻译错误都能过 CI 上线：界面出现字典串、`{}` 残留占位符、空标签；翻译合入时键序漂移产生整文件 diff 噪音，review 无法定位真实改动。`--check` 宣称的「分片键集合一致」被读成「分片数据正确」，是假绿灯。
**原则**：20、36、53、45。
**状态**：确证（构造坏值实测 `--check` 不拦截）。

### B8-A-03 · P1 · lib/surface/i18n/og_l_i18n.dart:134-144 × lib/surface/surface_bridge.dart:466-469 × lib/surface/pages/settings_page.dart:349-356（确证·代码证据；运行时表现待议）
**问题一句话**：`OgLI18n.load()` 作为 `ChangeNotifier` 全局单例，**既无世代号也无互斥/在途去重**，多个页面/多 tab 同时 `load()` 或用户快速连点语言时，`_locale` 由最后完成的加载决定，与 `settings.setLanguage` 的落盘顺序可能相反；`_data.containsKey` 与 `_data[code]=…` 之间无闸门，同一语言重复并发加载互相覆盖。
**证据**：`:134-144` 全部逻辑只有 `if (!_data.containsKey(...)) _loadLocale(...)` + `Future.wait` + `if (_locale != target) { _locale = target; notifyListeners(); }`，无 `gen`/`token`/`pending`；对比同仓库 `lib/surface/settings.dart:745-751` 已有正解 `final int gen = ++_loadGen; … if (gen != _loadGen) return;`（`load()`）与 `:775` `apply()` 的 `_loadGen++`——**同项目同一类风险，i18n 侧没有抄过来**。`surface_bridge.dart:466-469` `setLanguage` 是 `await settings.setLanguage(code); await OgLI18n.instance.load(...)` 两段 await，`:467` 与 `:627`（启动时）也是两个独立入口；`settings_page.dart:349-356` `_setLanguage` 无防重、无 `mounted`/世代校验，连点即并发。另 `:138-139` 的 `containsKey` 检查一旦 `_loadLocale` 抛异常就整批失败但不写 `_data`（可重试），而一旦**写入了残缺的 `_data[code]`**（B8-A-18），`containsKey` 恒真 → **同进程内永不重试**，只能重启。
**用户可见后果**：用户在设置页快速切 de→fr→ru 或桌面多窗口同时切语言，界面停在某个旧语言、下拉框显示另一个语言、重启后又变成第三个；分片读取失败后该语言在本次会话永久半残（大量裸键名），且无任何提示。这是「显示语言 ≠ 持久化语言」的不一致状态，会让用户以为设置没生效而反复操作。
**原则**：10、22、26、27、13。
**状态**：确证（并发入口与缺失闸门由代码闭环；「最后完成者获胜」的具体乱序表现需 Dart 运行时实测，标「待议」——本环境无 `flutter`）。

### B8-A-04 · P1 · lib/surface/i18n/og_l_i18n.dart:198-209 × assets/i18n/{zh,en}/shell.json:9,17,48,52-53（确证·实测）
**问题一句话**：`t()` 对缺参「保留原样」且**不报错不留痕**，UI 直接显示 `{count} 条`、`{error}` 这类生占位符；更严重的是 `for (args.entries) out = out.replaceAll(...)` 是**顺序替换**，参数值里若含 `{其它键}` 会被后续迭代二次展开，形成文案注入。
**证据**：`:198-203` `if (args == null || args.isEmpty) return raw;` —— 文案含占位符但 `args` 为 null 时**原样返回**，注释 `:195-196` 自认「缺参时保留原样」；`:205-208` `String out = raw; for (…) out = out.replaceAll('{${entry.key}}', entry.value);`。实测纯函数复现：`raw='{a} 与 {b}'`、`args={'a':'{b}注入','b':'X'}` → `'X注入 与 X'`（第一次把 `{a}` 换成 `{b}注入`，第二次把新引入的 `{b}` 也换掉）。真实可达面：`shell.json` 的 `failedWith: "{label}失败：{text}"`、`failedParen`、`systemNotifUnavailable: "{error}"`、`systemChannel: "[系统通道] {text}"`、`common.json` 的 `linkOpenFailedCopy: "{url}"`、`addDownloadFailed: "{error}"` 都把**外部/异常文本**当值传入；远端文件名、异常消息、URL 中出现花括号即触发。占位符缺失实测扫描全库 90 处字面量 `t()` 调用，9 处带占位符的调用中 `about_page.dart:311` 等由多行 map 传参（脚本平衡括号可完整解析，实际调用点无误），但 `i18n_test.dart` 对缺参行为**零断言**。
**用户可见后果**：① 漏传参数时用户看到 `{error}`、`{count} 条`，错误提示变成不可读的模板残片（第 38 条「错误信息说发生了什么」失效）；② 当错误文本/文件名含 `{host}` 等字样时，替换链会把无关字段的值插进句子，用户读到与事实不符的提示（例如把「目标主机」显示成别的内容），属于伪造的错误信息。
**原则**：36、38、15、20、42。
**状态**：确证（顺序替换实测可复现；仓库内是否已出现含花括号的错误文本未实测，标「待议」仅限该触发频率）。
