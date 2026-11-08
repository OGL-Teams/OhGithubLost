# 第8批 · 视角B：安全与数据 审计（i18n 与门禁体系）

> 仓库：OhGithubLost v12.0.0 LTS · 只审不改 · 裁决依据：docs/QUALITY_STANDARD.md / AGENTS.md
> 审计范围：tool/boot_manifest.py、tool/inject_platform_spec.py、tool/pin_min_sdk.py、.github/workflows/build.yml、lib/surface/i18n/og_l_i18n.dart、assets/i18n/zh/shell.json、test/kernel/boot_release_chain_test.dart（另核对 lib/main.dart、lib/kernel/boot/boot_loader.dart、gh_oauth.dart 以确证后门与注入面）。

---

## 发现清单

### B8-B-01 【确证】boot manifest coreDigest 未覆盖 lib/platform 与 lib/main.dart
- 文件:行号：tool/boot_manifest.py:99-101（`build_payload`，`layer_dirs` 仅 kernel/base/domain/surface）
- 问题：签名聚合目录硬编码为四层，`lib/platform/` 与入口 `lib/main.dart`、`pubspec.yaml` 均不在指纹内。
- 用户可见后果：攻击面在 platform 层（平台判定门面）或组合根被篡改时，coreDigest 不变、验签通过，签名失去对全部代码的完整性承诺；与 AGENTS.md 门禁8「四层目录逐文件 sha256 聚合」字面一致但覆盖不完整。
- 等级：P1
- 原则：46（发布产物可追溯：指纹、签名缺一不可）、48
- 证据：`layer_dirs = ['lib/kernel', 'lib/base', 'lib/domain', 'lib/surface']`；且 `'modules': []` 恒空。

### B8-B-02 【确证】i18n t() 参数插值不转义，控制字符/错误原文可直入 UI
- 文件:行号：lib/surface/i18n/og_l_i18n.dart:185-201（`t()` 的 `out.replaceAll('{${entry.key}}', entry.value)`）
- 问题：插值值原样替换，未过滤控制字符、换行、占位符回串；Flutter `Text` 不解析 HTML，故无 HTML 注入，但 `\n`、`\t`、U+202E（RTL 覆盖符）等可被带进文案。
- 用户可见后果：`failedWith`（`{label}失败：{text}`）等以网络错误原文为参的文案，可被远端响应体内容（含换行/伪系统提示文本）伪装成系统消息欺骗用户（提示注入）；缺参时按设计保留 `{path}` 原样（符合原则36兜底，不算缺陷）。
- 等级：P2
- 原则：20（外部数据不可信）、38（错误信息面向用户）
- 证据：`t()` 实现仅 replaceAll；`assets/i18n/zh/shell.json:38` `failedWith: "{label}失败：{text}"`、`:70` `systemChannel: "[系统通道] {text}"` 均以外部错误文本为参。

### B8-B-03 【确证】开发旁路在生产构建已彻底关闭，但 profile 构建仍开放
- 文件:行号：lib/main.dart:196（`developmentBypass: !hasSignedManifest && !kReleaseMode`）；lib/kernel/boot/boot_loader.dart:179、280（旁路仅在 `!developmentBypass` 不成立时触发）
- 问题：release（kReleaseMode）下旁路恒关，清单缺失/签名无效即拒启 —— 主目标达成、确证关闭；但 `!kReleaseMode` 同样涵盖 profile 构建，profile 包允许无清单启动。
- 用户可见后果：release 无后门（好）；profile 构建若流入用户（性能测试产物外泄），等于一份跳过信任链的安装包。
- 等级：P2
- 原则：48（引导信任链不容旁路）、11（防线没有开关）
- 证据：boot_loader.dart 中旁路日志均标注「仅调试构建可用」，代码却未限定 `kDebugMode`。

### B8-B-04 【确证】签名私钥无泄漏面（正面确认 + 一处残留）
- 文件:行号：.github/workflows/build.yml:125-131（还原 OGL_BOOT_KEY → `$RUNNER_TEMP/ogl-boot-ed25519.key`）；tool/boot_manifest.py:118、154-157
- 问题：私钥经 env 还原到 runner 临时目录，`printf` 不回显；日志只打印 `signature=前24字符` 与 canonical 字节数，无密钥内容。正面确认。残留：脚本结束后未删除 `$RUNNER_TEMP` 下的密钥文件（runner 一次性，风险低）。
- 用户可见后果：正常构建无凭证泄漏；若未来在 manifest job 追加 `if: always()` 的诊断步骤 cat 临时目录，才会成泄漏点（现无此步骤）。
- 等级：P2（残留项）
- 原则：39（凭证永不进日志）、46
- 证据：boot_manifest.py `print('signature=%s...' % signature[:24])`；build.yml 无任何 cat/echo 密钥语句。

### B8-B-05 【确证】dart_define 注入值不会被日志打印（正面确认，含一处低危）
- 文件:行号：build.yml:133-156（注入 step）、:440-446（注入校验测试）
- 问题：`OGL_BOOT_MANIFEST`（公开清单）与 `OGL_GITHUB_CLIENT_ID`（公开 Client ID）均非机密，且流程未 echo 其值 —— 除注入校验测试把 manifest 作为 `--dart-define` 命令行参数（会出现在 CI 日志的 test 命令行中），该值本就是公开清单，不构成泄漏。
- 用户可见后果：无凭证风险；Client ID 被打包进所有平台产物属设计意图（公开标识，AGENTS.md 明示非密钥）。
- 等级：无缺陷（记录确认结论）
- 原则：39、45
- 证据：gh_oauth.dart:29 经 `String.fromEnvironment('OGL_GITHUB_CLIENT_ID')` 读取；build.yml 中无相关值打印。

### B8-B-06 【确证】CI 第三方 Action 全部按 tag 引用，未钉 commit SHA
- 文件:行号：build.yml 各处（`actions/checkout@v4`、`actions/upload-artifact@v4`、`actions/download-artifact@v4`、`subosito/flutter-action@v2`、`softprops/action-gh-release@v2`）
- 问题：全部第三方/官方 Action 用可变 tag 引用；tag 被劫持即可在 build/manifest job 内读到 `OGL_BOOT_KEY`、`OGL_ANDROID_KEYSTORE` 两个 Secret 并随产物外传。
- 用户可见后果：签名私钥、Android 签名证书存在供应链级泄漏路径（低概率高影响）；release job 持 `contents: write`，tag 劫持还可发布恶意 Release。
- 等级：P1
- 原则：46、48
- 证据：grep 确认五个 workflow 中无 `@<sha>` 形式引用。

### B8-B-07 【确证】Android 签名证书密码硬编码 `android` 且证书名为 debug.keystore
- 文件:行号：build.yml:323-333（还原步骤）、:453-465（`--ks-pass pass:android --key-pass pass:android`）
- 问题：发布签名证书的 store/key 密码以明文写死在 workflow 中且值为弱口令 `android`；证书安全完全依赖 Secret 本身不泄漏，等于单因子。
- 用户可见后果：Secret 一旦经 B8-B-06 之类的供应链途径泄漏，攻击者即刻可签出与官方证书一致的伪造包（覆盖安装、信任链旁路无补）。另外文件名 `debug.keystore` 有误导性，易被误当作可公开的调试证书处理。
- 等级：P1
- 原则：39、46、48
- 证据：`printf '%s' "$OGL_ANDROID_KEYSTORE" | base64 -d > "$HOME/.android/debug.keystore"` + `pass:android` 明文。

### B8-B-08 【确证】manifest/boot-manifest artifact 被所有构建腿无条件信任，缺完整性自证
- 文件:行号：build.yml:188-192（download-artifact）、:432-439（注入校验仅 Android·arm64-v8a 腿）
- 问题：各构建腿下载 `boot-manifest` artifact 后直接 `--dart-define-from-file` 注入，仅一条 Android 腿跑注入校验测试；artifact 在任务间传递若被损坏/替换（配合 B8-B-06 的 tag 劫持），Windows/Linux 腿无任何护栏即编译进产物。
- 用户可见后果：非 Android 产物可能携带损坏清单 → 装机后拒启（可用性问题）；或被替换清单 → 依赖签名验证兜底（若公钥被换则全链失守）。
- 等级：P2
- 原则：46、15（静默降级）
- 证据：`if: matrix.label == 'Android · arm64-v8a'` 为唯一注入校验条件。

### B8-B-09 【待议】actions/cache 缓存投毒面评估
- 文件:行号：build.yml:228（subosito flutter-action `cache: true`）、ci.yml:33、release-verify.yml:419、web.yml:77
- 问题：缓存键由 action 内部按 Flutter 版本 + pubspec 哈希派生，可预测；但 GitHub Actions 缓存按分支隔离，fork PR 的缓存不可写入基础分支，主分支缓存仅同分支可读写 —— 实际投毒需先攻陷 main 分支工作流本身，此时缓存已非最短板。
- 用户可见后果：现配置下投毒链路被 GitHub 分支隔离机制阻断，风险低。
- 等级：P2（记录性）
- 原则：46、44（对外部目标保持怀疑）
- 证据：四个 workflow 均 `cache: true`，无自定义 `key`/`restore-keys`；未观察到跨分支 restore-keys。

### B8-B-10 【确证】inject_platform_spec.py 对 spec 值做 XML/Gradle 无转义拼接
- 文件:行号：inject_platform_spec.py:455-473（permissions 拼进 `<uses-permission android:name="%s" />`）、:478-490（label 正则替换 `android:label="%s"`）
- 问题：spec 值直接 `%s` 进 XML/属性，无转义；spec 为仓库内受控文件（每条强制 why），常规风险为零，但若 spec 被恶意 PR 注入引号/标签，可改写 AndroidManifest 任意属性。
- 用户可见后果：仅在恶意 PR 合入后可扩大权限面（如追加运行时权限）；CI 无对 spec 的变更评审护栏。
- 等级：P2
- 原则：44、20
- 证据：`'    <uses-permission android:name="%s" />' % perm` 无转义/白名单。

### B8-B-11 【确证】boot_release_chain_test 对 canonical 双实现一致性覆盖不足
- 文件:行号：test/kernel/boot_release_chain_test.dart:60-79（临时密钥对 签→验 全链）
- 问题：测试用 Dart 侧 canonicalJsonEncode 自签自验，只能锁 Dart 侧确定性；Python `boot_manifest.py:31`（`json.dumps(sort_keys=True, separators, ensure_ascii=False)`）与 Dart 的**逐字节一致**没有直接对照测试（现有固定签名样本测试可间接覆盖真实路径，但对数字转义、非 BMP 字符等边界无样本）。
- 用户可见后果：若两侧规范化在边界字符上分叉，CI 签出的清单在端上验签失败 → 全部用户拒绝启动（事故级）；现有测试可能拦不住此类回归。
- 等级：P2
- 原则：51（破坏性测试）、50（测契约不是巧合）
- 证据：测试文件无任何对 Python 产出样本的断言（仅 `release_key_signed_manifest.json` 固定样本，覆盖路径窄）。

### B8-B-12 【确证】release job 独享 contents:write，但全局无 workflow 级 permissions 收敛
- 文件:行号：build.yml:596-600（release job `permissions: contents: write`）
- 问题：仅在 release job 显式声明权限，manifest/build job 未声明，继承仓库默认 GITHUB_TOKEN 权限（可能为 read/write）。
- 用户可见后果：若 Action tag 被劫持（B8-B-06），build 腿内的恶意代码默认可能持有写权限，放大攻击半径。
- 等级：P2
- 原则：46、11
- 证据：无顶层 `permissions:` 块。

### B8-B-13 【确证】安全文案 accelLeakWarning 六语言齐备、无私钥/令牌话术泄漏（正面确认）
- 文件:行号：assets/i18n/zh/settings.json:6；en/de/fr/ru/zh_Hant settings.json:6；settings_page.dart:1501
- 问题：无缺陷。加速泄密警告在 6 种语言中均有真实译文（非英文占位），且文案只描述风险、不含任何凭证值。
- 用户可见后果：正面；符合原则37/35。
- 等级：无缺陷（记录）
- 原则：35、37
- 证据：grep 六语言文件均有 accelLeakWarning 且内容为逐句译文。

---

## 覆盖文件清单
- tool/boot_manifest.py（全读，142 行）
- tool/inject_platform_spec.py（全读，677 行）
- tool/pin_min_sdk.py（全读，73 行）
- .github/workflows/build.yml（全读，691 行）
- lib/surface/i18n/og_l_i18n.dart（全读，229 行）
- assets/i18n/zh/shell.json（全读，75 行）
- test/kernel/boot_release_chain_test.dart（全读，133 行）
- 裁决依据：docs/QUALITY_STANDARD.md（全读）、AGENTS.md（全读）
- 补充确证取证：lib/main.dart、lib/kernel/boot/boot_loader.dart、lib/kernel/boot/boot_manifest.dart、lib/domain/gh/gh_oauth.dart、六语言 settings.json（grep）、其余 4 个 workflow 的 cache 用法

## 整体评价
门禁体系的核心承诺基本兑现：签名私钥严格走 Secret 且不进日志/产物，release 构建的 developmentBypass 确证关闭，dart_define 注入值无敏感信息，安全文案完整本地化，`boot_release_chain_test` 的信任根锁定设计优秀。主要短板集中在**签名覆盖不完整（platform 层与组合根不在 coreDigest 内）**与**供应链加固缺失（Action 未钉 SHA、Android 签名密码硬编码、权限未最小化）**——单点概率低，但组合起来构成对"发布产物可追溯"（原则46）的实质威胁。i18n 插值无转义为低危提示注入面，建议在 t() 内过滤控制字符。共 13 条：P1×3（B8-B-01/06/07）、P2×8、无缺陷正面确认×2（B8-B-05/13），1 条标注待议（B8-B-09）。
