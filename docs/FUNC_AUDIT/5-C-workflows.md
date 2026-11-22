# 功能审计 5-C · workflow 与发布链路

> 文档戳：**更新时间 2026-11-23 07:11:52（Asia/Shanghai） · v15.0.0**
> 审计范围：`.github/workflows/` 全部 6 个 + `changed/` 归档链（generate_posts.py / check_content.py / releases.json）+ `release_notes/` 约定。
> 纪律：只读审计；每条问题 `file:line` 可 `rg` 复现；禁读 Flutter SDK（本席未触碰 `/root/flutter` 等路径；框架 API 事实按「待核实」处理）。

## 问题总览

| 级别 | 数量 | 主题 |
| --- | --- | --- |
| P0（数据丢失/失效/安全） | 2 | Release Verify 全线失效；dispatch 覆盖已发布 Release |
| P1（功能失效/不一致） | 4 | 23 产物无硬校验；prerelease/channel 不一致；Gradle 缓存饥饿；sync 双 v 前缀 |
| P2（打磨） | 6 | 文档陈旧、硬编码、健壮性、注入覆盖等 |

---

## P0-1 · Release Verify 与真实发布产物全面失配，核验形同虚设

**症状**：对线上最新 Release（如 `v15.0.0`，23 件产物）运行 `Release Verify`，Android / Linux / Windows / macOS 四个 job 100% 失败：

- Android：下载用 `--pattern 'OGL-*.apk' --pattern 'OGL-*.aab'`（`release-verify.yml:103`），但自 5.6.0「只发压缩包」后 Release 中**没有任何裸 `.apk`/`.aab`**（`changed/releases.json` 的 `v15.0.0.assets` 全为 `OGL-v15.0.0-*.zip/.7z` 与 deb/rpm）。`glob('dist/OGL-*.apk')`（`release-verify.yml:130`）为空 → `assert len(apks) >= 4`（`:133`）必失败。AAB 同理（`:146`）。
- Linux：`--pattern 'Linux.*.zip'`（`:159`）无法匹配带前缀的真实名 `OGL-v15.0.0-Linux.x64.zip`（fnmatch 要求以 `Linux` 开头）；`want` 表写的是 `Linux.arm64-best-effort.zip`（`:209`），该名字早已不存在（现在是 `Linux.arm64` 且裸放 deb/rpm）。`checked=0` → `assert checked >= 1`（`:222`）必失败。
- Windows：`--pattern 'Windows.*.zip'`（`:259`）同样不匹配 `OGL-v15.0.0-Windows.x64.zip`；`Windows.arm64-best-effort.zip`（`:276`）不存在。必失败。
- macOS：`check_one 'macOS.x64.zip' / 'macOS.arm64.zip'`（约 `:377-378`），但 build.yml 自 5.6.0 已弃用 Apple 平台，`releases.json` 无任何 macOS/iOS 产物 → 无条件运行的 macOS job 必失败。iOS job（`:384` 起，`if inputs.include_ios`）若开启亦必失败。

**根因**：5.6.0（`git log` 提交 `c1c7acb`）把发布形态改为「仅 zip+7z、弃用 Apple、arm64 腿由 best-effort 转正」，但 `release-verify.yml` 最后一次改动是 `e4775c2`，远早于该变更；产物命名、下载 pattern、校验清单全部停留在旧的「裸 APK + `*-best-effort.zip` + Apple 产物」时代。核验工作流从未随发布形态更新，等于长期空转。

**修复指令**：
1. 重写 `release-verify.yml` 下载 pattern 为当前命名：`--pattern 'OGL-*.zip'`（或 `'OGL-*Android*.zip'` 等按平台细分），去掉 `.apk`/`.aab`/`macOS.*`/`iOS.*` pattern。
2. Android job：从 `OGL-*-Android.*.zip` 解压后取内部 APK/AAB 再验签、验 `versionName`、验权限；版本期望应对 `tag` 去掉 `v` 并去掉 `-beta`/`-alpha` 后缀（当前 `re.sub(r'^v','',tag)` 在 prerelease tag 上会错）。
3. Linux/Windows 的 `want` 表改为 `OGL-<tag>-Linux.x64.zip` / `OGL-<tag>-Linux.arm64.zip` / `...-Windows.x64.zip` / `...-Windows.arm64.zip`（或从解压后 ELF/PE 架构反查，不硬编码文件名）；删除 `*-best-effort` 分支与「可缺」跳过逻辑——严格模式下缺件即失败。
4. 删除或改为 `if: false` 的 macOS/iOS job（除非恢复 Apple 构建）；Apple 相关输入 `strict_apple_signed` / `include_ios` 一并下线。
5. 加一条「产物总数 == 23（或按当前通道的期望数）」的汇总断言，作为核验总闸（可与 P1-1 共用判据）。

---

## P0-2 · dispatch 幂等性缺失：同一版本重复 dispatch 静默覆盖已发布 Release

**症状**：对同一 `version_name` 再次 `workflow_dispatch`，`release` job 无条件执行 `softprops/action-gh-release@v2`（`build.yml:802-811`）。该 action 对已存在的 tag 默认**更新**（改写 body、覆盖/追加同名 assets），不会失败。没有「tag 是否已存在」的前置检查，也没有 tag 冲突告警。结果是历史 Release 被静默改写、产物被覆盖、发布记录不可信。

**根因**：发布作业假设每个 tag 只发布一次；`concurrency.group` 仅保证同组串行（`build.yml:56-58`），`cancel-in-progress: false` 只防并跑，不防「先后两次均完整跑完并覆盖」。发布参数校验（`:88-96`）只校验格式，不校验 tag 是否已占用。

**修复指令**：在 `release` job「计算标签」（`build.yml:744`）之后、创建 Release 之前加硬守卫：用 `gh api repos/$GITHUB_REPOSITORY/git/ref/tags/<tag>`（或 `gh release view <tag>`）检测 tag 是否已存在；存在则 `echo "::error::tag 已存在，禁止覆盖" && exit 1`，除非显式传入 `allow_overwrite: true` 输入。对 `version_number` 递增但 `version_name` 不变的场景，要求改用新 `version_name` 或显式覆盖标志。将 `fail_on_unmatched_files` 改为 `true`（见 P1-1）以避免残缺覆盖。

---

## P1-1 · 发布无「23 产物」硬校验，残缺 Release 可正常发出

**症状**：`build.yml` 的 `release` job 用 `files: out/*`（`:809`）+ `fail_on_unmatched_files: false`（`:811`），即使期望产物缺失也只是少传几件、发布照常成功。Linux 打包失败仅 `|| echo '::warning::Linux 安装包未全部生成（见上方输出）'`（`:698`），deb/rpm/AppImage 全缺失也不阻塞。产物压缩用 `if-no-files-found: warn`（构建腿 `:620`）同样宽松。结果可发出远少于 23 件的 Release（历史数据已有 18/19/20/22 件的版本，见 `releases.json`）。

**根因**：发布链处处容错，缺少「本通道应产物数 / 必备产物清单」的最终断言；`fail_on_unmatched_files: false` 明确关闭了 action 自带的文件匹配校验。

**修复指令**：在「整理产物」步骤末尾（`build.yml:739` 后）加计数断言：`cnt=$(find out -maxdepth 1 -type f | wc -l)`，stable 通道要求 `== 23`（按当前矩阵 9 腿 × zip+7z + 3 个 Linux 包 = 实际 21+3=24 附近，按真实基线钉死一个常量并随矩阵更新），缺一即 `exit 1`；对 deb/rpm 三个包逐一 `[ -f ]` 校验，去掉 `:698` 的 `|| echo` 改为硬失败；将 `fail_on_unmatched_files` 设为 `true`。基线数字写入 `tool/ci_config_audit.py` 的断言，防止矩阵改动后断言漂移。

---

## P1-2 · prerelease 与 channel/tag 一致性可被破坏

**症状**：tag 计算（`build.yml:748-756`）中 `elif echo "$V" | grep -qi "$CH"`（`:752`）用**子串**匹配判断「版本名是否已含通道名」。若 `version_name` 含通道词（如 `2.0-beta.1` 配合 `channel=beta`），tag 不再追加 `-beta`（`:753` 走 `T="v$V"`），但 `prerelease: ${{ inputs.channel != 'stable' }}`（`:808`）仍为 true → tag 无通道后缀却被标为预发布。反向：`channel=stable` 但 `version_name=5.0.0-beta` 时，tag=`v5.0.0-beta` 而 `prerelease=false` → **带 `-beta` 的 tag 被标为正式版**，用户会把测试版当稳定版下载。`releases.json` 中已存在 `v4.0.0`/`v4.1.0`（tag 无后缀但 `prerelease: true`）这类历史不一致，佐证该规则长期不可靠。

**根因**：tag 后缀决策与 prerelease 标记来源不同（前者看版本名子串，后者只看 channel 输入），二者无统一判据；`grep -qi` 子串匹配过宽。

**修复指令**：统一以 `inputs.channel` 为唯一真相源：`T="v$V$([ "$CH" = stable ] || echo "-$CH")"`（仅在 stable 时不加后缀），并把 `prerelease` 与「tag 是否含 `-beta`/`-alpha`」绑定；丢弃 `grep -qi "$CH"` 分支。若必须兼容「版本名已含通道」的历史输入，则在参数校验阶段（`build.yml:88-96`）显式拒绝 `version_name` 含 `-alpha|-beta` 或要求 channel 与之匹配，避免二义性。

---

## P1-3 · Gradle 缓存「前缀回退 + cache-hit 跳过保存」导致新 key 永不写入

**症状**：`build.yml` 的 Gradle 缓存 key = `android-gradle-${FLUTTER_VERSION}-${hashFiles('pubspec.yaml')}`（`:300`），`restore-keys` 为前缀 `android-gradle-${FLUTTER_VERSION}-`（`:302-303`）；保存步骤条件是 `steps.android-cache.outputs.cache-hit != 'true'`（`:768`）。一旦存在任何旧 key 缓存，所有腿 restore 都会**部分命中**（`cache-hit=true`），AAB 腿因此永远跳过 save。后果：pubspec.yaml 变更后新 key 的缓存**永远不会被写入**，缓存冻结在首次那一版，依赖变更后的每次构建都冷启动（Gradle 下载重新发生），缓存策略名存实亡。

**根因**：`cache-hit` 对前缀回退命中也为 `true`，而保存条件把「部分命中」误当作「精确命中」，与 `restore-keys` 前缀回退组合产生饥饿。

**修复指令**：改用 `steps.android-cache.outputs.cache-matched-key`（ restore 步骤 id=`android-cache`）判断是否**精确命中**：保存条件改为 `cache-matched-key != 'android-gradle-${FLUTTER_VERSION}-${{ hashFiles('pubspec.yaml') }}'`（即仅当命中的不是当前 key 时才写当前 key）。保留「AAB 独占写 + success()」的并发写根治设计不变（该部分正确，`build.yml:762-775`）。

---

## P1-4 · sync_releases.py 生成 `vv<tag>.md` 双前缀文件名

**症状**：`release_notes/sync_releases.py:47` 取 `tag = rel['tag_name']`（线上 tag 形如 `v15.0.0`，见 `releases.json` 的 `html_url` 与 build.yml 生成的 `v$V`），`:51` 拼 `path = os.path.join(HERE, 'v%s.md' % tag)` → `vv15.0.0.md`。而仓库现有文件均为单前缀 `v15.0.0.md`。脚本运行会**新建**一批 `vv*` 文件而非更新既有笔记，造成 `release_notes/` 目录双份、正文分叉。

**根因**：假设 tag_name 不带 `v`，与 build.yml 实际 tag 约定相反。

**修复指令**：`:51` 改为 `tag if tag.startswith('v') else 'v' + tag` 后再拼 `.md`；加一条单测断言「同步后目录内不存在 `vv*.md`」。该脚本为手工工具（非自动链路），故列 P1 而非 P0。

---

## P2-1 · stats.yml 头部注释与实际产物格式不符

**症状**：`stats.yml:6` 注释写 `stats/star-history.svg 折线图（README 通过 raw 地址引用）`，但 `stats_chart.py` 实际产出 PNG（`tool/stats_chart.py:1079,1082`），workflow 提交与 CDN 清理也用 `.png`（`stats.yml:80,97`），README 引用的同样是 `.png`（`README.md:20-21`）。注释误导维护者，且标题行 `stats.yml:1` 末尾有多余字符 `o`（「每 10 分钟更新）o」）。

**根因**：图表实现从 SVG 迁到 PNG 后注释未同步。

**修复指令**：`stats.yml:6` 改为 `star-history.png / commit-history.png（README 经 jsDelivr 引用）`，删除 `stats.yml:1` 末尾的多余 `o`。不影响运行，纯文档。

## P2-2 · web.yml 仓库名硬编码，fork/迁移即失效

**症状**：`web.yml:210` `REPO = 'OGL-Teams/OhGithubLost'` 写死，与 `${{ github.repository }}`（脚本环境中为 `GITHUB_REPOSITORY`）本可自动获取。分支名 `web`、commit 讯息里的版本也多处硬编码（`:206` 等）。若 fork 或改名，REST 提交会打到别的仓库/路径错误。

**根因**：早期为绕分支保护写死，未随环境变量化改造。

**修复指令**：`:210` 改为 `REPO = os.environ['GITHUB_REPOSITORY']` 并在 env 中注入 `${{ github.repository }}`；分支名同理用 `${{ github.ref_name }}` 传入。

## P2-3 · web.yml 声明 `workflow_dispatch` 但无 inputs，版本号只取 pubspec

**症状**：`web.yml:36` 声明 `workflow_dispatch` 却无输入；生成清单步骤设 `VERSION_INPUT: ${{ inputs.version_name }}`（`:103`）但该 env 未被使用——真正版本来自 `${{ github.ref_name }}`（`:107`）和 `pubspec.yaml`（`:154-155`）。`VERSION_INPUT` 是死代码，且 `workflow_dispatch` 与 push 行为无差别（都能触发），手动触发无法指定发布版本。

**根因**：从 build.yml 复制注入逻辑时残留未用输入。

**修复指令**：删除 `:102-104` 的 `VERSION_INPUT` env；如需手动指定版本，为 `workflow_dispatch` 增加 `version` 输入并在 `:154` 优先使用，否则显式文档说明 Web 版本完全跟 pubspec/分支。

## P2-4 · 引导清单注入校验仅覆盖 1/9 腿（与 1-C 席同报，确证）

**症状**：`build.yml:608-613` 的「引导清单注入校验」带 `if: matrix.label == 'Android · arm64-v8a'`，9 腿只跑 1 腿；其余 8 腿仅靠 `--dart-define-from-file`（`:534,546`）注入，无运行前验签。若 manifest job 后 dart_define.json 被污染，8 腿照常出包，用户启动才拒绝启动（与 `FUNC_AUDIT/1-C-boot-trust.md` P0-1 同报）。

**根因**：校验步骤被人为限制到单腿以省时。

**修复指令**：将该校验改为对每腿产物的静态检查（在各自构建后校验二进制内嵌的 manifest 签名），或至少覆盖全部 Android 腿 + 每个平台各一腿；框架相关 API 若需 dart 层事实「待核实（交主会话/CI 裁决）」。

## P2-5 · generate_posts.py「从未发布版本并入后续版本」规则无实现

**症状**：`changed/generate_posts.py:11` 文档声明「从未发布的版本，其内容已按合并规则并入其后第一个已发布版本的正文，本脚本不单独成文」，但 `main()`（`:104-151`）逐 tag 直接读 `_content/<tag>.md`（`:115`），没有任何合并逻辑。现状恰好 `_content` 里 `v13.1.0/v13.2.0/v13.3.0`（正式 tag）**未发布**（releases.json 只有其 `-beta`），它们的正文被静默跳过（`:116-118` 打印「缺失」），**不会**并入对应的 `-beta` 版本。文档承诺与实际行为不符；若某版本正文写在该文件里而只发了 beta，用户看到的 beta 文章会缺内容。

**根因**：合并规则只写在注释，从未编码。

**修复指令**：要么实现「未发布 tag → 归入其后第一个已发布 tag 正文」的合并（按语义版本排序找后继），要么删除 `:11` 的承诺并在 `_content/_STYLE.md` 明确「正文文件名必须 == 已发布 tag 名，否则不生成」。`generate_posts.py:151` 的 `return 0 if written == len(published) else 1` 对缺失正文会返回 1（当前若有人跑该脚本会因 3 个缺失正式 tag 而失败）——确认该脚本是否在门禁中被调用，若被调用则现状会红，需一并处理。

## P2-6 · i18n_translate.yml「空 only」会全 24 语言翻译且 collect 在译失败时空跑提交

**症状**：`i18n_translate.yml:54` `if: inputs.only == '' || inputs.only == matrix.lang`，`only` 默认空（`:25`）→ 手动触发默认全 24 语言跑；与文件头「默认只维护中英双语、多语言仅重要版本手动触发」的使用纪律（`:2-4`）冲突——一旦误触就是全量 180 分钟矩阵。collect job `if: always()`（`:79`）在翻译 job 全部失败时仍执行，只下载到空 artifact，`git status` 无变化则跳过（`:99-101`），不会误写内容，但会显示「success」掩盖上游失败。

**根因**：`only` 默认空表示「全部」，与「默认保守」纪律不一致；collect 不看 needs 结果。

**修复指令**：将 `only` 默认值设为 `'ja'`（或强制必填），把 `description` 改为「留空=全部 24 语言（谨慎）」；collect 的 `if` 改为 `success() || failure()` 并在步骤内显式检查各翻译 job 结论，上游全失败时以 `::error` 标记，避免「假绿」。

---

## 已检查清单（全覆盖，逐文件/逐项）

| 检查对象 | 覆盖内容 | 结论 |
| --- | --- | --- |
| `.github/workflows/build.yml`（811 行） | 触发/path-ignore（19-40）、参数校验（84-96）、私钥注入（99-107）、manifest 生成与 dart-define（108-152）、9 腿矩阵定义（170-229）、Flutter 安装/脚手架（238-360）、Gradle 缓存 restore/save（300-303,762-775）、签名/重签/版本权限护栏（441-613）、release job 标签/正文/产物/创建（648-811）、9→8 腿历史 | P0-2、P1-1、P1-2、P1-3、P2-4 |
| `.github/workflows/ci.yml`（218 行） | 严格模式失败收集与终审（含 `touch`/`grep -c`/数字兜底 200-215）、21 个门禁步骤逐个 `if: always()`、pub get 失败记录、UI 快照上传 | 严格模式判据正确：`|| echo FAIL` 统一收集、终审稳健写法（无 `0\n0` 与覆盖计数缺陷），9+ 门禁全部执行且失败一起报——**未发现失效** |
| `.github/workflows/i18n_translate.yml`（105 行） | 24 语言矩阵/引号防 YAML bool、串行限流、only 过滤、collect 合并与 git push 防冲突设计 | 并发 push 冲突已根治（artifact 汇总）；P2-6 |
| `.github/workflows/release-verify.yml`（441 行） | resolve/Android/Linux/Windows/macOS/iOS/ui-shots 全 job、下载 pattern、校验断言、截图矩阵 | P0-1（全面失配） |
| `.github/workflows/stats.yml`（102 行） | 定时/推送触发、独立 stats 分支写、GITHUB_TOKEN 推送、图表自检、jsDelivr purge（失败不阻断）、与 main 解耦 | 不误触发 main 构建（写 stats 分支）；P2-1（注释陈旧），自动化本身正确 |
| `.github/workflows/web.yml`（291 行） | 仅 web 分支触发 + paths-ignore 防自触发、双构建 wasm/js、产物校验（148-158）、PAT REST 提交绕分支保护、CDN 预热、版本号来源 | 防自触发设计正确（未用 `[skip ci]`）；P2-2、P2-3 |
| `changed/generate_posts.py`（154 行） | releases.json 读取与 tag 过滤、published_at 排序、去重（清旧 posts 后重建）、下载区块只列 zip、assets.url 直用、缺失正文处理、退出码 | P2-5；去重与 url 字段使用正确 |
| `changed/check_content.py`（80 行） | PATTERNS/PROPER_NOUNS、`--check`/`--fatal` 等价、扫描 `_content/*.md`（跳过 `_` 前缀）；实测 `python3 changed/check_content.py --check` 退出 0（79 篇 0 命中） | 无问题，门禁有效（当前仓库内容干净） |
| `changed/releases.json`（352 KB，81 键） | 键结构 `tag/name/html_url/published_at/prerelease/assets[]`，asset 子键 `name/url/size`；76 个 v* 版本 + 5 个 CI-cat 项；asset 数分布 18/19/20/22/23；`v15.0.0` 含 23 件（5 Android×2 + boot-manifest×2 + Linux×2 + Windows×2 + 3 deb/rpm）；prerelease 与 tag 后缀一致性 | 结构正确（generate_posts 依赖字段齐全）；不一致样本佐证 P1-2；残缺样本佐证 P1-1 |
| `release_notes/`（README + sync_releases.py + 84 份 v*.md） | 约定「正文文件名 = tag 名」；sync 脚本拉 GitHub Release 写 `v<tag>.md`；build.yml 读 `release_notes/v${VN}.md` 作发布正文 | 历史坑（文件名≠tag）当前未复发（现有文件与 tag 对齐）；P1-4（sync 会制造双 v 前缀，是复发隐患） |
| `docs/CI_BUILD_BASELINE.md` / `RELEASE_RUNBOOK.md` / 其他 audit 报告 | 交叉核对「9 腿矩阵」表述与历史；确认 9→8 腿说法 | build.yml 实际 9 腿，文档一致；未见 8 腿迁移记录，历史变更一致（无遗留 8 腿引用） |

## 本席结论

发布主链（build.yml 的 9 腿构建 + 参数校验 + 缓存独占写 + CI 严格模式 + stats/web 防自触发）设计总体成立、历史踩坑（缓存并发写、CWD 依赖、0.1.0 默认值、Linux 打包吞错、tar SDK 越权）均已正确修复；但**核验链（release-verify.yml）已与发布形态完全脱节、长期不可用（P0-1）**，且**dispatch 无 tag 幂等守卫，会静默覆盖历史 Release（P0-2）**，二者为最高优先修复项。其次需补产物数硬校验（P1-1）、统一 channel/prerelease 判据（P1-2）、修 Gradle 缓存饥饿（P1-3）与 sync 双前缀（P1-4）。归档链（generate_posts/check_content/releases.json）当前数据自洽、门禁有效，但「未发布正文并入」承诺未实现（P2-5）需澄清。共 **12 条问题：P0×2 / P1×4 / P2×6**。
