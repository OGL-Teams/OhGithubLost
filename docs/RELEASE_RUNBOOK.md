# 发布运行手册 / Release Runbook

> 状态 / Status：操作型（How-to） · 面向技术人员 / For engineers
> 适用 / Applies to：`.github/workflows/build.yml`、`.github/workflows/release-verify.yml`、`tool/version_sync.py`、`changed/`

> **更新时间 / Last Updated**：2026-11-21 16:14:39　**对应版本 / Version**：v14.0.0

本手册按真实 workflow 步骤编写；命令均在仓库根执行（`cd /root/OhGithubLost`）。
Commands below are copied from the repository's workflows and tooling; run them from the repository root.

## 1. 前置条件 / Prerequisites

- Flutter `3.47.5`（`build.yml` 的 `FLUTTER_VERSION`），`flutter pub get` 成功。
- Actions Secrets 已配置：`OGL_BOOT_KEY`（Ed25519 seed base64）、`OGL_ANDROID_KEYSTORE`（JKS base64）、
  `OGL_GITHUB_CLIENT_ID`（公开 Client ID，非密钥；缺失仅隐藏登录授权按钮）。见 `.github/signing/README.md`。
- 目标版本号已定：`version_name`（形如 `2.0.0`，正则 `^[0-9]+\.[0-9]+(\.[0-9]+)?$`）与
  `version_number`（正整数，正则 `^[1-9][0-9]*$`）。
- 权限：触发 `workflow_dispatch` 的写权限；Release 创建需 `contents: write`。

## 2. 版本号四处同步 / Four version sites

| # | 文件 / File | 位置 / Location | 修改方式 / How |
| --- | --- | --- | --- |
| ① | `pubspec.yaml` | `version: 14.0.0+140000`（第 21 行） | 手工改为 `version: <name>+<number>` |
| ② | `lib/main.dart` | `const String kOgLAppVersion = '...'` | `python3 tool/version_sync.py --fix`（脚本用 pubspec 版本改写 main.dart） |
| ③ | `tool/boot_manifest.py` | `build_payload()` 读 `pubspec.yaml` 的 `version:`，CI 用 `--version "$VERSION_INPUT"` 覆盖 | 无需改脚本；dispatch 输入必须与 ① 一致 |
| ④ | `.github/workflows/build.yml` 的 `manifest` job | `VERSION_INPUT: ${{ inputs.version_name }}`；各构建腿 `--build-name` / `--build-number` 注入 | dispatch 表单填写，无需改文件 |

验证 / Verify：

```bash
python3 tool/version_sync.py
# 一致：<version>（文档头无写死版本）  → exit 0
# exit 1 = 不一致或 README/AGENTS 头部写死 vX.Y.Z；exit 2 = 读不到版本
```

`version_sync.py` 还检查 `README.md` / `AGENTS.md` 前 8 行不得出现 `v\d+\.\d+\.\d+`；
文档戳中的版本（如本文）不在其扫描范围。

## 3. 发布说明与内容三件套 / Release notes triple

涉及 / Files：`release_notes/v<version>.md`、`CHANGELOG.md`、`changed/_content/v<version>.md`。

1. 编写 `release_notes/v<version>.md`（体例见 `release_notes/README.md`；固定小节
   `新增 / Added` → `改进 / Improved` → `修复 / Fixed` → `变更 / Changed` → `已知限制 / Known limitations` → `产物 / Artifacts`，空节删除）。
   `build.yml` 的「生成发布说明」步骤按优先级读取：① dispatch 输入 `release_notes`；② `release_notes/v${VN}.md`；
   ③ `release_notes/v${VN}-${CH}.md`；④ 自动模板（**正经发版必须补 ②**）。
2. 更新根目录 `CHANGELOG.md`：贡献者向、中英对照要点、版本倒序。
3. 编写 `changed/_content/v<version>.md`：面向网站读者、中文书面语，规范见 `changed/_content/_STYLE.md`；
   不得含面向开发者的技术表述。
4. 内容门禁（CI 同款）：

```bash
python3 changed/check_content.py --check
# 或 --fatal（等价）：扫描 changed/_content/*.md（跳过 _ 开头文件）
# 命中行内代码 / .dart / lib/ / test/ / 驼峰或下划线标识符 / CI、PR、commit 等开发词 /
# vX. 版本前缀 / 感叹号结尾 / 「我们|你|大家」→ 打印并 exit 1；0 处 → exit 0
```

5. 归档站点（发布后执行，需先更新 `changed/releases.json`）：

```bash
python3 changed/generate_posts.py
# 参数：--content-dir（默认 changed/_content）、--releases（默认 changed/releases.json）
# 规则：只为 releases.json 中 starts with 'v' 的已发布版本生成 _posts/<date>-<tag>.md；
#       先清空 _posts/*.md；下载表只列 .zip（无 zip 才列全部）；正文缺失打 [缺失]；
#       已发布版本缺正文 → exit 1；全部生成 → exit 0
```

`releases.json` 条目结构：`{"v<tag>": {"assets": [{"name","size","url"}], "published_at": "...", "html_url": "..."}}`；
`published_at` 决定文章顺序，站点时区 UTC+8。

## 4. 触发构建与发布 / Dispatch build and release

GitHub UI：Actions → **Build** → Run workflow，参数：

- `channel`：`stable` / `beta` / `alpha`（默认 `stable`）；
- `version_number`：正整数（如 `140000`）；
- `version_name`：如 `14.0.0`；
- `release_notes`：可留空（留空走 §3 的 ② / ③ / ④ 优先级）。

等价 CLI（替换 `<OWNER>/<REPO>`）：

```bash
gh workflow run build.yml --repo <OWNER>/<REPO> \
  -f channel=stable -f version_number=140000 -f version_name=14.0.0
```

构建矩阵（`build.yml`，严格模式，任一腿失败即阻塞发布）：Android arm64-v8a / armeabi-v7a /
x86_64 / universal-APK / AAB；Windows x64 / arm64；Linux x64 / arm64。共 9 腿，每腿 `timeout-minutes: 45`。
macOS / iOS 自 5.6.0 起弃用（最后 v5.3.0）。

发布任务 `release`（仅 dispatch 且 `needs.build.result == 'success'`）：

- 标签计算 `tag`：stable → `v<version_name>`；beta/alpha → `v<version_name>-<channel>`（版本名已含通道则不重复）。
- `prerelease: ${{ inputs.channel != 'stable' }}`，`draft: false`，`body_path: notes.md`。
- 产物：Android 的 APK / AAB 加 `OGL-v<VN>-` 前缀原样上传；Linux deb / rpm / AppImage 裸放；
  其余每目录出 `OGL-v<VN>-<label>.zip`（`zip -9`）与 `.7z`（`7z -mx=9`）双份，极限压缩。
- Android 腿发布前重签：`zipalign -p -f 4` → `apksigner sign --v1-signing-enabled true --v2-signing-enabled true`，
  逐包跑 `python3 tool/verify_apk_cert.py --apk "$APK" --keystore "$KS"`；
  版本号护栏逐个 APK 比对 `aapt dump badging` 的 `versionName` 与 `inputs.version_name`。
- 引导清单注入校验（Android arm64-v8a 腿）：

```bash
flutter test --dart-define="OGL_BOOT_MANIFEST=$(python3 -c 'import json;print(json.load(open("dart_define.json"))["OGL_BOOT_MANIFEST"])')" \
  test/kernel/boot_define_injection_test.dart
```

## 5. Release 校验 / Post-release verification

手动触发 Actions → **Release Verify**（`release-verify.yml`），参数：`tag`（空=最新正式版）、
`source_ref`（默认 `main`）、`strict_apple_signed`（默认 false）、`include_ios`（默认 false）。

```bash
gh workflow run release-verify.yml --repo <OWNER>/<REPO> \
  -f tag=v14.0.0 -f source_ref=main
```

job 与判据 / Jobs and criteria：

| Job | 判据 / Criterion |
| --- | --- |
| `resolve` | `gh api repos/<repo>/releases/latest -q .tag_name` 或指定 tag；列出全部 assets |
| `android` | 4 个 APK + ≥1 AAB；证书 SHA256 `3fcadb03954d74a92b736ce66969c51fb1d9052f1ccbc6fb84fd00080e33ab0b`；`versionName` 等于 tag 去 `v`；含 `android.permission.INTERNET`；zip/AAB `testzip()` 为 None；AAB 含 `BundleConfig.pb` |
| `linux` | `Linux.x64.zip`（ELF machine=62）；arm64（=183）可缺；可执行文件名为 `ohgithublost` 且有执行位 |
| `windows` | `Windows.x64.zip`（PE machine=0x8664）；arm64（0xAA64）可缺；`ohgithublost.exe` |
| `macos` / `ios` | 历史产物核验：`.app` / `Info.plist` / `lipo -archs`；未签名属预期，`strict_apple_signed=true` 时未签名即失败；`include_ios` 默认跳过 |
| `ui-shots` | `flutter test --reporter expanded` 全量；`OGL_SCREENSHOTS=1 flutter test test/screenshots/screenshot_matrix_test.dart`；截屏 ≥ 2 张（竖屏 + 横屏）；产物 `ui-shots-<tag>` 保留 30 天 |

产物期望数 / Expected asset count：`resolve` 步骤打印 `产物共 N 个`，应与 `out/*` 上传清单一致；
历史核验基线为 **23 件**（双压缩格式、5 Android 包、Linux 三格式等）；若数量变化，
以 `gh release view <tag> --json assets -q '.assets[].name'` 实测为准。

## 6. 归档与失败处置 / Archiving and failure handling

1. 发布成功后导出 Releases 元数据到 `changed/releases.json`（字段见 §3），再跑 `python3 changed/generate_posts.py`。
2. 同步 `docs/DOCS_CONTENT_AUDIT.md` 等文档戳时以对应文件 git 最后提交时间为准（见 `docs/DOCUMENT_STYLE.md` §一）。
3. 失败处置：
   - `manifest` job 缺 `OGL_BOOT_KEY` → 按 `.github/signing/README.md` 从 Secret 恢复；缺私钥不可绕过。
   - `versionName` 护栏失败 → 核对 dispatch 的 `version_name` 与 `pubspec.yaml`；重跑 `version_sync.py --fix`。
   - 引导清单注入测试失败 → 检查 `dart_define.json` 的 `OGL_BOOT_MANIFEST` 非空、签名可被 `kOgLReleasePublicKey` 验证。
   - 发布正文用了自动模板 → 补 `release_notes/v<version>.md` 后用 `gh release edit <tag> --notes-file release_notes/v<version>.md` 修正。
   - Linux 安装包（deb/rpm/AppImage）未生成 → 检查 `tool/linux_packages.py` 存在且 `actions/checkout` 已执行。
4. 回滚：GitHub Release 本身不提供原子回滚；需删除错误 tag/Release 并重跑 dispatch。
   错误 tag 清理：`gh release delete <tag> --yes && git tag -d <tag> && git push --delete origin <tag>`（**破坏性操作**，先确认无用户已下载）。

## 7. 门禁前置检查 / Pre-flight gates

```bash
python3 tool/gate_of_gates.py --fatal
python3 tool/version_sync.py
python3 tool/i18n_scan.py --check
python3 changed/check_content.py --check
flutter analyze --fatal-infos --fatal-warnings
flutter test --reporter expanded
```

CI 的 quality job 还跑 `layer_audit / contract_audit / facade_audit / ui_audit / motion_audit /
motion_coverage_audit / perf_audit / action_pin_audit / ci_config_audit / contrast_audit /
sort_imports --dry-run --fatal / dart format --set-exit-if-changed`；全部门禁详见
[`GATES_REFERENCE.md`](GATES_REFERENCE.md)。
