# 第7批 · 视角B：安全与数据审计 —— 主题与令牌警告子系统（v12.0.0 LTS）

> 审计对象：`/root/OhGithubLost` v12.0.0 LTS（基线 `8214fb7`，含批7交叉修复）。
> **只审不改**：未写 `lib/`、未写 `tool/`、未写 `assets/`；本报告为唯一产出，逐条追加写入。
> 范围（全部 `file_read` 完整读）：`lib/surface/app/font_loader.dart`（172 行，含 06:03 批7交叉修改后的**复读**）、`font_pick.dart`（67）、`token_exit_warning.dart`（170）、`lib/surface/settings.dart`（1058，分三段读全）、`lib/surface/util/download_proxy.dart`（118）、`assets/theme_packs/`（目录 + `.gitkeep`）。
> 裁决依据（全部完整读）：`docs/QUALITY_STANDARD.md`（59 条）、`AGENTS.md`（95 行）、`docs/NETWORK.md`（154 行）。
> 佐证代码以 `rg` + 定点片段复读核实，行号以当前工作区为准。每条给出「是否确证 + 代码证据」；需运行时实测的标「**待议**」。
> 优先级分布：P0×1 / P1×8 / P2×7 = 16 条。

---

## P0

### B7-B-01 · P0 · 令牌出设备的「图片渲染/预览」路径整条漏过 TOKEN-EXIT-01 门禁

- **文件:行号**：`lib/surface/pages/file_preview_page.dart:447-478`（`_rawView`）、`lib/surface/pages/repo_page.dart:2104-2143`（`_readmeImagePlan`）、`lib/surface/widgets/readme_view.dart:339-351` 与 `563-568`（`_ReadmeImage.net` / `_image`）、对照 `lib/surface/app/token_exit_warning.dart:1-5`（门禁全称承诺）与 `97-107`（唯一留痕点）。
- **问题一句话**：`ogLGuardTokenExitDownload` 全库只有 5 处调用，全部挂在「加入下载任务」按钮上；而私有仓库的图片预览与 README 图片渲染会把 `Authorization: Bearer` 直接交给**第三方加速通道地址**，不经过任何门禁、不弹警告、不写决策日志。
- **用户可见后果（注入/数据风险）**：用户打开一个私有仓库页（**无需点击任何下载按钮**），`_readmeImagePlan` 在 `accelPrivateRepoAccepted=true` 且 `readmeImage` 范围开启时返回 `proxy = prefixes.first`、`headers = downloadAuthHeaders()`；`readme_view.dart:344` 拼出 `'$proxy$raw'`，`readme_view.dart:563-568` 用 `Image.network(..., headers: headers)` 发出。预览页同理（`file_preview_page.dart:463-465` 对私有仓库取 `downloadAuthHeaders()`，`:474-477` 带头发 `Image.network`）。于是**每一张 README 图片都把 PAT 送给通道运营者**，通道可据此读取该用户全部有权限的私有仓库/组织数据；本机「关于页」与磁盘日志里**没有任何一条记录**说明这次令牌出设备（留痕只在 `token_exit_warning.dart:99-107` 的弹窗结果里）。单独看，用户曾在设置页做过一次 3 秒「知情接受」全局警告（`settings_page.dart:1678-1706`），这是缓解因素；但①那次同意的文案针对「私有仓库加速下载」，并未说明「浏览页面时每张图自动带令牌」；②与 B7-B-06 组合（安全设置明文可篡改）后，这次同意可能根本不是用户做的 —— 变成**零确认、零交互、零留痕**的令牌外发，故定 P0。
- **原则**：39（凭证不进第三方/不进日志）、40（令牌只在必要跳用一次）、12（危险操作显式确认）、15（不静默）、43（加速通道不预置、用户显式开启）。`NETWORK.md` §四 也把「令牌将离开设备」列为必须可见的事件。
- **是否确证 + 代码证据**：**确证（静态）**。门禁调用点全集：`rg -n 'ogLGuardTokenExitDownload' lib` → `repo_page.dart:291,1878`、`release_detail_page.dart:269`、`action_run_page.dart:408`、`file_preview_page.dart:590`，五处全在 `enqueue` 之前。图片路径 `Image.network` 的两处 `headers` 赋值均无门禁调用；`OgLAppLog.instance.add('下载', ...)` 只出现在 `token_exit_warning.dart:99`。`token_exit_warning.dart:3-5` 文件头声明「**凡是**『这次下载会把令牌发给非 GitHub 主机』的场景，必须先经用户显式确认」，与实现不符。
- **复验结论（批4 `_downloadZip` 之后是否所有入口都已覆盖）**：**入队入口 6/6 已覆盖** —— `repo_page.dart:306`（门禁 291）、`repo_page.dart:1892`（门禁 1878）、`release_detail_page.dart:283`（门禁 269）、`action_run_page.dart:424`（门禁 408）、`file_preview_page.dart:606`（门禁 590）五条带认证头路径全部先过门禁；第六条 `gist_detail_page.dart:308` 未接门禁但 `ogLAccelCandidates(..., repoPrivate: false)`（`gist_detail_page.dart:299-304`）且 `enqueue` 未传 `headers`，恒不带令牌，安全。**漏的是「非入队」的图片渲染/预览路径**，即本条。
- **备注**：无需运行时实测即可确证代码路径；「通道是否真的收到令牌」`NETWORK.md` §四已实测（通道原样转发 `Authorization`）。

---

## P1

### B7-B-02 · P1 · 私有字体下载 URL 零校验：`startsWith('http')` + 裸 `HttpClient.getUrl` 直连任意协议/内网/元数据地址（SSRF）

- **文件:行号**：`lib/surface/app/font_loader.dart:63`（`if (font.source.startsWith('http'))`）、`:74-95`（`HttpClient` + `getUrl(Uri.parse(font.source))` + 无上限字节累积）、`:58-61`（`bytesOf` 入口）、对照 `lib/surface/pages/settings_page.dart:818-860`（`_addFontFromUrl` 把用户手输的整个 `link` 原样塞进 `source`）。
- **问题一句话**：字体链接的协议/主机/重定向/响应体大小四类校验全部缺失，且刻意绕开了 AGENTS.md 声明的统一传输层（`NetBridge → ResilientTransport → IoNetTransport`）与 SSRF 防护。
- **用户可见后果（注入/数据风险）**：用户在「添加链接字体」里填（或被诱导粘贴）`http://127.0.0.1:8080/x.ttf`、`http://169.254.169.254/latest/meta-data/...`、`http://192.168.1.1/...?x=.ttf`，或 `httpfoo://…`：`startsWith('http')` 对 `httpevil://` 也为真；`HttpClient.getUrl` 默认 `followRedirects = true`，可自动跳到内网/云元数据地址。配合 `font.source` 落进 `ogl.settings`（`settings.dart:659` `uiFontId` / `customFonts`，`toJson` 里 `source` 明文）与外部主题包/导入配置的注入面，构成**由不可信配置触发的 SSRF**：能探测本机/内网服务、在云环境读元数据凭据；响应体经 `BytesBuilder` 无上限累积（`:83-86`）后交给 `FontLoader.load()` 解析引擎字体解析器（原生代码面），内存可被超大响应撑爆（原则 29）。
- **原则**：44（拒绝回环/私网/元数据地址是下限）、20（外部数据不可信）、29（资源有上限）、11（防线没有开关）、39/40（不得另开后门网络出口）。`AGENTS.md` §5 明确「**令牌安全：SSRF 防护（拒绝回环/私网/169.254.169.254）**」「所有请求统一走手动重定向守卫」；`NETWORK.md` 一、出口清单里**完全没有**「用户字体链接」这一目的地。
- **是否确证 + 代码证据**：**确证**。`font_loader.dart:63` 只判 `startsWith('http')`，无 `Uri.scheme == https`、无 `isForbiddenHost`（对比 `lib/domain/ix/ix_presign.dart:113-205` 的 `isForbiddenHost` 已实现并覆盖整数 IPv4 / IPv6 映射 / 私网 / 链路本地）、无 `followRedirects = false`（对比 `io_net_transport.dart:321`）。`bytesOf` 直接 `new HttpClient()`，不经过 `IoNetTransport._sendWithGuardedRedirect`（`io_net_transport.dart:315-390`），因此项目里全部重定向/降级/私网守卫在此**都不生效**。`BytesBuilder(copy: false)` 循环无字节上限。`settings_page.dart:853-856` 构造 `OgLCustomFont(source: link)` 前无任何 URL 校验（对比加速通道有 `ogLValidateAccelBaseUrl`，`accel.dart:226-252`）。
- **备注**：`Uri.parse` 抛 `FormatException`、`getUrl` 抛 `SocketException` 都由 `settings_page.dart:857-858` 兜底提示，不构成崩溃；风险在**请求本身被发出**。内置常量 `notoSerifScUrl`（`:33-35`）是硬编码 https 到 github.com，不在此条射程内。云端元数据是否可被本设备路由命中属环境相关，标「**待议（仅此子项）**」；私网/回环可达性为静态确证。

### B7-B-03 · P1 · `font_pick.dart` 手输路径无边界：可读本机任意文件并把字节注册进字体引擎

- **文件:行号**：`lib/surface/app/font_pick.dart:52-65`（`path = controller.text.trim()` → 仅 `endsWith('.ttf'/'.otf')` → `File(path).existsSync()` → `file.readAsBytes()`）、`:27-49`（`TextField` 示例直接给 `/storage/emulated/0/…` 绝对路径）、对照 `lib/surface/pages/settings_page.dart:805-813` 与 `:862-880`（`_registerPickedFont`）。
- **问题一句话**：唯一校验是「扩展名字符串」，不校验路径是否位于应用字体目录、不限制文件大小、不拒绝符号链接；用户（或诱导输入）可指向任意可读文件。
- **用户可见后果（注入/数据风险）**：输入 `/sdcard/…/secret.ttf`、`~/.ssh/id_ed25519.ttf`（拷贝/改名后）、`/proc/self/…ttf` 之类，字节被 `readAsBytes()` 一次性全读进内存，随后在 `settings_page.dart:869-872` 写入 `Directory.systemTemp/ogl-fonts/<sha1>.ttf` —— **把本机文件复制到全局临时目录**（见 B7-B-05），再由 `FontLoader.load()` 交给引擎字体解析器；超大文件直接 OOM（原则 29）。这不是「用户自己选自己的文件」就算数：该输入最终落在**共享临时目录**且被持久化 `filePath`（`settings.dart:659`），使「一次选择」变成持续可读的副本。
- **原则**：20（外部数据不可信）、29（所有资源有上限）、44（对外部目标保持怀疑）、12（危险操作显式确认）、8（数据无价）。
- **是否确证 + 代码证据**：**确证**。`font_pick.dart:58-59` 只有 `.ttf/.otf` 判断（大小写不敏感但仍只是字符串后缀，`.ttf/` 之后带 query 的路径不会被拒），`:62-65` 无任何 `canonicalize`/`isWithin`/`lengthSync` 上限/权限检查；`readAsBytes()` 无参数即整文件读入。`settings_page.dart:867-872` 用 `id = sha1(source)` 作文件名落盘，无覆盖前读取确认（原则 9）。符号链接是否被 `File.existsSync()` 解析跟随属平台行为，标「**待议（仅此子项）**」。
- **备注**：与 B7-B-02 同属「字体来源完全可信」这一根假设；两条分别是网络侧与本地侧。

### B7-B-04 · P1 · 字体字节注册进 `FontLoader` 后 `_loaded` 缓存无内容/内存/生命周期治理，删除字体不注销引擎资源

- **文件:行号**：`lib/surface/app/font_loader.dart:48-56`（`static final instance` + `final Set<String> _loaded`）、`:110-119` 与 `:138-145`（两处 `ByteData.view(bytes.buffer)` + `loader.load()`）、`:126-127`（`isLoaded` 幂等）；对照 `lib/surface/settings.dart:928-937`（`removeCustomFont` 只删清单/回落 `uiFontId`）、`lib/surface/surface_bridge.dart:546-555`（`_uiFontFamilyOf` 注释声称「未注册时回落」，实现无条件返回 `custom:<id>`）。
- **问题一句话**：`ensureLoaded` 只按 `id` 判断幂等，不校验字节内容/大小/签名，注册后字体由引擎长期持有且**无注销 API**；`_loaded` 是进程级单例集合，删除字体、换字体、清空设置都不会释放，`ByteData.view(bytes.buffer)` 还把整块缓冲区（含可能的外部视图偏移）原样交给引擎。
- **用户可见后果（注入/数据风险）**：① UGC 字体（B7-B-02/03 的字节）进入引擎字体解析器后常驻内存，无法回收；用户重复添加不同 `id` 的同源字节可无限累积（原则 24/29），大字体或恶意构造字体可持续吃内存。② `removeCustomFont` 后引擎里 `custom:<id>` 仍在，若其他路径仍持有该 `uiFontId`（或配置被回填），会继续用**已删除的字体**渲染而不留痕。③ `surface_bridge.dart:550-555` 的 doc 注释与实现相反 —— 注释承诺「未加载时回落系统字体」，代码却无条件 `return family` 并每次打一条 `ERR`「字体未注册，回落系统字体」，实际没回落（违反原则 57/15：日志说的与做的不一致，排障会被误导）。
- **原则**：24（注册了就要注销，生命周期对称）、29（内存有上限）、20（外部数据夹紧）、15/57（注释与实现一致）、28（缓存键覆盖差异维度 —— `id` 由 `sha1(source)` 派生，`source` 相同但内容被换时仍命中旧注册）。
- **是否确证 + 代码证据**：**确证**。`font_loader.dart:53` `_loaded` 只有 `add`（`:115`,`:144`），全文件无 `remove`/`clear`；`rg -n 'isLoaded\(' lib/surface` → 只有 `font_loader.dart:56` 定义与 `:126` 自用，`surface_bridge.dart` 的主题构建链**从不查询** `OgLFontLoader.instance.isLoaded`，因此「回落」分支根本不存在。`settings.dart:928-937` 的 `removeCustomFont` 只操作 `customFonts` 与 `uiFontId`。`ByteData.view(bytes.buffer)` 使用 `buffer` 而非 `sublist` 复制，无长度/魔数校验。
- **备注**：与视角 A 的 B7-A-03/04（落盘缓存/重复下载）是**不同问题**，本条聚焦内存安全与生命周期，且 A/C 未覆盖。

### B7-B-05 · P1 · 字体落盘目录用 `Directory.systemTemp/ogl-fonts`（全局可写），却声称「应用支持目录下 fonts/」

- **文件:行号**：`lib/surface/app/font_loader.dart:155-171`（`_privateFontsDir`：`final Directory base = Directory.systemTemp;` → `ogl-fonts`）、`:66-73`（缓存读取同一目录）、`:136-139`（`ensureNotoSerifSc` 再写一次）；对照 `lib/surface/pages/settings_page.dart:867-872`（用户字体写同一目录）、`lib/surface/settings.dart:91-101`（`filePath` 持久化绝对路径）、`lib/base/disk/app_dirs.dart:122-138`（本有 `root()/logging()/downloads()` 的唯一裁决处）。
- **问题一句话**：字体（含用户导入字节与 ~30MB 官方字体）落在一个**名字固定、跨用户共享、无权限收窄**的系统临时目录，且 doc 注释 `/// 私有字体落盘目录（应用支持目录下 `fonts/`）` 与实现不符。
- **用户可见后果（注入/数据风险）**：多用户桌面/共享临时目录环境下，其他进程可**预置或替换** `<tmp>/ogl-fonts/<id>.ttf`（`id` 可预测：内置 `noto-serif-sc.otf`、私有字体 `sha1(source)` 前 16 位）；`bytesOf` 的 cache-first（`:71-72`）会**直接读取该文件**并注册进引擎，无任何哈希/签名/来源校验 → 字体内容注入（渲染层被劫持、字形可用于欺骗性文案展示），且因为缓存优先，`ensureNotoSerifSc` 永不重新下载，污染是持久的。系统清理临时目录后 `filePath` 指向的文件消失，`bytesOf` 才回落到 `source` 重新下载（A/C 已记的静默失效面，本条不重复）；而 `OgLCustomFont.fromJson` 要求 `filePath` 非空（`settings.dart:93-95`），本地导入的字体在缓存被清后**没有任何恢复路径**（`source: 'local'`，不以 http 开头，`font_loader.dart:63` 直接落到 `StateError('字体文件不可读：…')`）。
- **原则**：8（数据无价）、20（外部数据不可信）、46（发布产物可追溯：指纹/签名校验）、44、57（文档引用符号/行为必须真实）、4（平台差异在唯一位置裁决 —— 这里绕开 `OgLAppDirs` 自行用 `systemTemp`）。
- **是否确证 + 代码证据**：**确证**。`font_loader.dart:164-167` 明确 `Directory.systemTemp` + 固定 `ogl-fonts`，`create(recursive: true)` 未指定权限；全仓 `rg -n 'privateFontsDirectory|_privateFontsDir'` 只在本文件与 `settings_page.dart:867`。`font_loader.dart:71-72` 的 `cached.existsSync() → cached.readAsBytes()` 无校验。`settings.dart:93-95` 的 `filePath.isEmpty → null` 使纯本地来源条目在清单里必然带一个可失效的绝对路径。AGENTS.md §1 要求 surface 不直接依赖 base/disk（本文件注释 `避免引入 base 层依赖` 自述），正确做法应经 `SurfaceBridge` 暴露的目录裁决，而非自己造一个全局临时目录。
- **备注**：视角 A 的 B7-A-03 / C 的 B7-C-03 记的是「名实不符 + 缓存失效」；本条新增**污染/注入**与**本地导入不可恢复**两个安全后果，故单列。

### B7-B-06 · P1 · 安全相关设置（`accelPrivateRepoAccepted` / 通道 / 同意版本）以明文 JSON 落盘且无完整性校验，篡改即可零确认开启「令牌出设备」

- **文件:行号**：`lib/surface/settings.dart:197-207`（`fromJson` 对 `releaseProxyEnabled` / `accelPrivateRepoAccepted` / `releaseProxyConsentVersion` / `releaseProxyChannels` / `releaseProxySelectedId` 仅做类型解析）、`:463-465`（`accelConsentCurrent => version >= 4`）、`:480-486`（`activeAccelPrefixes`）、`:616-660`（`toJson` 把上述字段与 `customFonts[].source/filePath` 全部明文写出）、`:270-283`（`_asAccelChannels` 未调 `ogLValidateAccelBaseUrl`）；对照 `lib/surface/surface_bridge.dart:566-583`（`KvSettingsPersistence` → `DiskKv`）、`lib/base/disk/platform_io_impl.dart:374-410`（`IoDiskKv`：`<root>/kv/<sha256(key)>.json` 明文 `{'k','v'}`）、`lib/base/disk/og_l_storage.dart:13`（`publicDir` = `/storage/emulated/0/ogl`，**用户可见**）、`lib/surface/util/accel.dart:185-200`（`OgLAccelChannel.fromJson` 只查非空）。
- **问题一句话**：`OgLSettings.fromJson` 把「用户是否知情接受令牌外发」「是否已同意协议」「加速总开关」「通道 URL」当作普通偏好读取，没有任何签名/MAC/来源校验，也不要求重新走一次 3 秒确认。
- **用户可见后果（注入/数据风险）**：在拿到「所有文件访问」的档位下，设置文件位于**用户可见的公共目录**（`og_l_storage.dart:13`），任何能写该目录的应用/备份恢复/导入配置/恶意主题包数据都可把 `accelPrivateRepoAccepted=true`、`releaseProxyEnabled=true`、`releaseProxyConsentVersion=4`、`releaseProxySelectedId` 指向自建的 `https://attacker.example/`，且 `baseUrl` 不经过 `ogLValidateAccelBaseUrl`（该函数唯一调用点是 `settings_page.dart:1920` 的**手工输入**路径）。结果：**用户从未点过那道 3 秒警告**，应用却把私有仓库的 `Authorization` 头送给攻击者通道（配合 B7-B-01，甚至无需点击下载）。`NETWORK.md` §四 与 `AGENTS.md` §5 声明的「用户显式知情接受」由此变成一条**可被配置篡改绕过的防线**（原则 11「防线没有开关」）。同一文件里 `customFonts[].source` 被 `font_loader.dart:63` 直接用作下载 URL（B7-B-02），`filePath` 被 `bytesOf` 直接 `File(...).readAsBytes()`（B7-B-03），构成「改配置 → 任意 URL 请求 + 任意文件读」的完整注入链。
- **原则**：11（防线没有开关）、12（危险操作确认在类型上表达）、39/40（凭证）、43（加速通道由用户显式开启，应用不预置）、20（外部数据不可信）、13（写入要么完整要么可恢复）、48（信任链不容旁路）。
- **是否确证 + 代码证据**：**确证**。`settings.dart:759` `load()` → `OgLSettings.fromJson(jsonDecode(raw))`，`raw` 来自 `KvSettingsPersistence.read()`；`IoDiskKv.read()`（`platform_io_impl.dart:385-401`）只校验 `decoded['k'] == key`（防摘要碰撞），**不校验 `v` 的完整性/签名**。`accelPrivateRepoAccepted` 在 `fromJson:198-199` 仅 `_asBool`，`setAccelPrivateRepoAccepted(true)` 的 3 秒确认只存在于 `settings_page.dart:1657-1706` 的 UI 路径，反序列化路径完全不触发。B1-B-08（`docs/audit_b1_b.md:57`）已记录「`fromJson` 不调 `ogLValidateAccelBaseUrl`」，本条是**在完整读完 `settings.load()` / `KvSettingsPersistence` / `IoDiskKv` 持久化链之后对该「待议」的坐实并升级**：持久化链确实没有第二道校验。
- **备注**：需真机确认公共目录档位是否命中（用户是否已授「所有文件访问」）标「**待议（仅环境子项）**」；代码层「无完整性校验」确证。令牌本身仍在系统密钥库（`SecureDiskVault`），本条不是令牌落盘泄露，而是**放行决策被篡改**。

### B7-B-07 · P1 · `download_proxy.dart` 对非 http(s) 地址「原样返回」，把协议白名单推给调用方（注释里承诺的两层守卫实际只有一层）

- **文件:行号**：`lib/surface/util/download_proxy.dart:97-104`（`if (!url.startsWith('http://') && !url.startsWith('https://')) return <String>[url];` 及注释「入队口另有 `ogLAssertDownloadUrl` 兜底，但**两层都要有**」）、`:113-117`（`'$base$url'` 无校验拼接）；对照 `lib/domain/ix/ix_download.dart:295-302` / `:636-640`（`ogLAssertDownloadUrl` 只在 `enqueue` 与 `fallbackUrls` 上）。
- **问题一句话**：`ogLAccelCandidates` 产出候选地址时不拒绝 `file://` / `javascript:` / `data:` / `httpx://`，也不校验前缀拼接结果的 scheme，只依赖「恰好有人调用 `enqueue`」这一层。
- **用户可见后果（注入/数据风险）**：`ogLAccelCandidates` 的返回值并非只流向 `enqueue`：
  - `lib/surface/pages/file_preview_page.dart:114-128,448-452` 把 `urls.first` 直接交给 `Image.network` / `_audioCard(rawUrl: url)`（后者 `openLinkOrCopy` 交给系统播放器，见 `:560-570`），**不经过 `ogLAssertDownloadUrl`**；
  - `lib/surface/widgets/readme_view.dart:344` 直接 `Uri.parse('$proxy$raw')` 交给 `Image.network`。
  因此一个被污染/注入的 `file.rawUrl`（Gist 原始 URL 来自 API 响应，见 `gist_detail_page.dart:299`）、或一个被篡改的 `baseUrl`（B7-B-06）可以产出非 http(s) 候选并在**没有入队断言**的路径上被消费；`'$base$url'` 拼接允许多次叠加前缀（如 `https://a/https://b/...`），使最终目标与「用户看到的主机」不一致。`startsWith('http://')` 亦放行明文 HTTP，与 `accel.dart:240-242` 明确拒绝 `http://` 的规则自相矛盾。
- **原则**：11（防线没有开关）、43/44（协议白名单、拒绝不可信目标）、57（注释宣称「两层都要有」与实现不符）、20；`NETWORK.md` 一、出口清单要求所有目的地可枚举。
- **是否确证 + 代码证据**：**确证**。`download_proxy.dart:101-103` 注释自述「不做检查就等于把协议白名单的责任推给调用方」，实现却正是「原样返回」；`rg -n 'ogLAssertDownloadUrl' lib` 只命中 `ix_download.dart:295/636/639`，`Image.network` 与 `openLinkOrCopy` 路径均无。`download_proxy.dart:113-117` 无 `Uri.tryParse` 复核。
- **备注**：`resolveReadmeImageUri`（`readme_view.dart:87-104`）对**图片 URI 本身**做了 http/https 白名单，是缓解因素；但 `'$proxy$raw'` 是在该校验之后拼接的，**拼接结果**不再复核，故外部代理仍可注入 `https://evil.example/http://...` 形态的地址。是否被系统播放器/图片加载器实际发起请求标「**待议（仅消费端子项）**」。

### B7-B-08 · P1 · `token_exit_warning.dart` 用小写硬编码键 + `Uri.tryParse` 失败静默放行判定，门禁可被大小写/畸形 URL 绕过

- **文件:行号**：`lib/surface/app/token_exit_warning.dart:82`（`final String? auth = headers['authorization'];`）、`:87-89`（`Uri.tryParse(url)` → `host` 空串 → 落到「非 GitHub 主机」）、`:58-64`（`ogLIsGitHubDownloadHost` 只认小写精确串）、`kOgLTokenSafeHosts:50-55`。
- **问题一句话**：门禁的「是否带令牌」判据只认一个字面量键；「是否 GitHub 主机」判据对大小写、尾点、端口、IPv6 字面量、百分号编码主机名没有归一化，且 `tryParse` 返回 `null` 时把原始 URL 当成 host 展示。
- **用户可见后果（注入/数据风险）**：① 任何调用点若写 `headers: {'Authorization': 'Bearer …'}`（Dart `Map` 大小写敏感；`gh_client.dart:609` 用的是小写，但 `ix_presign_io.dart:32` 的 `request.headers.set` 与第三方头文件习惯用大写），`carriesToken` 为假 → `return true` **无警告、无 TOKEN-EXIT-01 留痕**，令牌直发非 GitHub 主机。这正是原则 11 禁止的「靠调用方自觉」的门禁。② `ogLIsGitHubDownloadHost` 用 `h.endsWith('.github.com')` 放行 `evil.github.com.attacker.tld`？不会（后缀不匹配），但 `GITHUB.COM` 已由 `toLowerCase()` 覆盖；**尾点** `github.com.`、带端口形式（`Uri.host` 不含端口，此项无风险）、`github.com%2e` 等 mismatches 会走**警告**一侧（安全方向，不是绕过）。③ 真正的绕过在①；④ `tryParse` 失败时 `host.isEmpty` → 弹窗 `host` 参数被塞进整条 URL（`:94`），而 `OgLAppLog` 的 `args{'host'}` 同样塞整条 URL（`:104`）—— 若 URL 含查询串中的 `token=`、`X-Amz-Signature` 或用户私有路径，**凭证/签名会被写进磁盘日志与「关于页」**（原则 39：凭证不进日志）。
- **原则**：11（防线没有开关）、39（凭证不进日志/通知/序列化数据，脱敏从 toString 开始）、40、15（留痕要准确）、20。
- **是否确证 + 代码证据**：**确证**。`token_exit_warning.dart:82` 单键查找，无 `for (final e in headers.entries) if (e.key.toLowerCase() == 'authorization' …)`。当前生产头来源 `rg -n "authorization" lib/surface lib/domain` → `surface_bridge.dart:339`、`gh_client.dart:609`、`ix_action_logs.dart:72/127` 均小写；`ix_presign_io.dart:32` 用 `headers.set('authorization')` 亦小写 —— **现网路径不触发**，属防御性确证（与视角 A 的 B7-A-09 同点，但本条补充了「URL 全文进日志」这一独立数据风险，故保留并升级）。`:94/:104` 的 `host.isEmpty ? url : host` 明确把整条 URL 交给 i18n 模板并落盘（`error_surface.dart:251-275` `add` → `OgLLogFile.line`）。
- **备注**：现网危害为 0，标「**待议**」（需运行时/未来调用点验证是否出现大写键）；静态缺口与日志污染面确证。

### B7-B-09 · P1 · `theme_packs/` 只留占位却已在信任策略里「第三方主题 = open 级、免签名、免告警、免用户确认」

- **文件:行号**：`assets/theme_packs/.gitkeep:1`（`# 占位文件：内置主题包目录（M1 填充 JSON 主题包）`）、`pubspec.yaml:136-152`（`assets:` 清单**不含** `assets/theme_packs/`）、`assets/README.md:9`（`theme_packs/ | 主题包 | 可选外观扩展`）；对照 `lib/kernel/boot/trust_policy.dart:5-10,20-22,111-119`（`thirdPartyTheme → TrustTier.open / requireSignature: false / allowLoad: true / mustWarnBus: false / requiresUserConsent: false`）、`lib/kernel/boot/boot_loader.dart:353-365`（Stage 3 仅「登记」该策略，`detail` 里打印 tier）、`lib/base/net/net_mirror.dart:20-25,145-152`（`MirrorChannel.enabled`「主题包 / 设置可关闭」，注释称旧镜像规则「可由主题包启用」）。
- **问题一句话**：目录当前为空、**不存在加载外部代码/资源/JSON/网络请求的实现**（`rg -i 'theme_pack' lib` 零命中，全仓仅注释与占位文件），但引导信任链已经为「第三方主题包」预留了**最宽松的放行列**，且没有任何 schema 白名单解析器的落地代码。
- **用户可见后果（注入/数据风险）**：**当前运行时风险为 0**（确证：目录未进 pubspec、无加载代码、无远程 URL 读取），问题在**信任边界已被提前打开**：M1 一旦按 `.gitkeep` 的注释「填充 JSON 主题包」，按 `trust_policy.dart:111-119` 的策略，这些包将**免签名、免总线告警、免用户确认**直接装载；而 `net_mirror.dart` 的注释明确把「启用第三方镜像通道」列为主题包能力，`MirrorChannel.replacement` 是任意 URL 模板（`net_mirror.dart:15-18`）。于是「一个外观 JSON」可以顺带把 GitHub 流量改写到第三方主机 —— 与 `NETWORK.md` 一、「自 v6.4.3 起本应用不预置任何代理地址」、`QUALITY_STANDARD` 43「网络能力没有后门」直接冲突，也与 B7-B-06 的篡改链叠加。用户不会收到任何提示（原则 12/15）。`AGENTS.md` §4 声明「引导信任链一旦建立就不容旁路」（原则 48），`open` 级对**可影响网络出口**的扩展是过大的授权。
- **原则**：48（信任链不容旁路）、11（防线没有开关）、12（危险操作显式确认）、43（不预置代理、用户显式开启）、15（不静默）、55（过时白名单/占位是假情报）、57（文档与实现一致：`assets/README.md` 称「可选外观扩展」、`.gitkeep` 称「M1 填充」、代码里 `pubspec` 未声明）。
- **是否确证 + 代码证据**：**确证（现状 + 策略）**。`rg -n -i -uuu 'theme_pack'` 全仓命中仅 6 处（3 处注释、1 处 `.gitkeep`、1 处 `assets/README.md`、1 处 `audit_b7_cross.md`），`lib/` 内零代码引用；`pubspec.yaml` assets 清单逐项核对无该目录。`trust_policy.dart:111-119` 的 `TrustDecision` 字面量给出 `requireSignature: false, mustWarnBus: false, requiresUserConsent: false`。`boot_loader.dart:355-356` 只调用 `policy.evaluate(...)` 把结果写进 `BootStage.detail`，没有加载动作。
- **结论（针对重点项「theme_packs 是否加载外部代码/资源」）**：**否，当前不加载**。外部主题包的注入面目前是**策略级预留**而非实现级通路；建议把 `thirdPartyTheme` 至少提到 `warn` 级，或在 M1 落地时先补 schema 白名单与「不得影响网络出口」的约束。标「**待议**」（策略危害需 M1 实现后运行时坐实）。

## P2

### B7-B-10 · P2 · `fontScale` 边界：解析端与 UI setter 都夹紧，但 `fromJson` 的 NaN/Infinity 与 `copyWith` 直构仍可绕过；且边界值三处不一致

- **文件:行号**：`lib/surface/settings.dart:152-157`（`minFontScale=0.8 / maxFontScale=1.6`）、`:179-184`（`fromJson` → `_clampDouble`）、`:339-352`（`_clampDouble`）、`:893-899`（`setFontScale` 再夹一次）、`lib/surface/app/og_l_app.dart:94-97`（`(systemScale * fontScale).clamp(0.85, 2.0)`）。
- **问题一句话**：夹紧是「解析路径 + 便捷 setter」两层，但 `OgLSettings` 的公开 `const` 构造与 `copyWith` 不夹；最终 `MediaQuery.textScaler` 用的是第三套上下限 `[0.85, 2.0]`，且 `_clampDouble` 只挡 `isNaN` 不挡 `Infinity`（`double.infinity.clamp(0.8,1.6)` 返回 1.6，属安全方向，但负无穷/极大值语义不明）。
- **用户可见后果**：用户在设置页手改 `ogl.settings` 把 `fontScale` 写成 `10000` → `fromJson` 夹紧到 1.6，`og_l_app.dart:96` 再乘系统缩放（无障碍可到 2.0+）后夹到 2.0 —— **界面不会因超大 fontScale 崩溃/溢出**（这是对重点项「超大 fontScale」的正面结论）。但若配置里写 `fontScale: "1e308"`（字符串）→ 回落 1.0；写 `null`/对象 → 回落 1.0，均无「坏值被夹紧」的留痕（原则 20 要求「夹紧回默认值**并记录**」）。`copyWith(fontScale: 999)` 由代码内部调用时可绕过，而 `toJson` 会把 999 原样落盘，下次启动才被夹回 —— 存在一个进程内整页文字放大到不可读的窗口。三处边界常量不一致也让「到底上限是多少」没有单一真相（原则 34/45 的同源要求）。
- **原则**：20（坏数据夹紧回默认值**并记录**）、29（资源/边界有上限）、45（版本号/常量单一真相）、33（动效是刻度不是开关，字同）。
- **是否确证 + 代码证据**：**确证（静态）**。`settings.dart:179-184` 与 `og_l_app.dart:94-97` 各有一套 clamp；`_clampDouble:343-352` 仅 `if (v.isNaN) return fallback;`；`OgLSettings` 构造（`:110-149`）与 `copyWith:576-615` 无断言。设置页 `settings_page.dart:609-610` 用 Slider 传值，故 UI 路径不可越界。
- **结论**：**超大 fontScale 不能击穿界面**（正面确认）；缺口是「夹紧无留痕 + 常量三处 + 直构旁路」，定 P2。篡改配置到极端值是否会触发 Flutter 布局溢出标「**待议**」（需运行时/真机大字号实测）。

### B7-B-11 · P2 · `motionLevel` / `reduceMotion` 双字段落盘不一致：旧键为真可反悔，篡改档位可切到「全静默」但无日志

- **文件:行号**：`lib/surface/settings.dart:234`（`motionLevel: _motionLevelOf(raw)`）、`:248-266`（`_motionLevelOf`：`reduceMotion == true` 且无 `motionLevel` 键时返回 0）、`:624,655-656`（`toJson` 同时写 `reduceMotion` 与 `motionLevel`）、`:940-944`（`setMotionLevel` 夹到 0–3）、`lib/surface/app/motion.dart:300-304`（`disableAnimations`：`motionLevel <= 0` 或 `reduceMotion`）、`:183-189,266-290`（`OgLOAnimQuality.of` 的 `default` 分支把所有时长归零）。
- **问题一句话**：`reduceMotion` 与 `motionLevel` 是两个可独立篡改的持久化键，反序列化时「旧键优先」只在 `motionLevel` 缺失时生效；`OgLOAnimQuality.of` 对任何越界值（`_motionLevelOf` 已夹，但 `copyWith`/直构可绕过）静默落到 0 档全静默。
- **用户可见后果**：改 `ogl.settings` 里 `motionLevel: -1` 或 `999` → 夹到 0/3（安全方向）；改 `reduceMotion: true` 且保留 `motionLevel: 3` → 档位表仍按 3 拉满，但 `disableAnimations` 返回 true，动效时长与系统开关互相矛盾（原则 33「降档降质量，永不砍功能」被撕成两半）。两种情况都**没有任何用户可见提示或日志**说明「设置被夹紧/被覆盖」。
- **原则**：20（夹紧并记录）、33（动效是刻度不是开关）、15（不静默）、28（两个键表达同一状态，缓存/状态一致性）。
- **是否确证 + 代码证据**：**确证**。`_motionLevelOf:248-266` 的 `if (level is num) … return clamp; if (_asBool(raw['reduceMotion'])) return 0; return 1;` 与 `toJson` 双写并存；`motion.dart:266-290` 的 `case 0: default:` 合并分支把越界值当 0。正面确认：`_motionLevelOf:252-256` 已显式处理 `Infinity/NaN`（`if (!level.isFinite) return 1;`），比 `fontScale` 的 `_clampDouble` 更严，此处**无击穿**。
- **备注**：本条是数据/状态一致性，与视角 C 的 B7-C-10（「越界语义未测」）不同面：C 关注测试缺口，本条关注**双键可篡改 + 无留痕**。

### B7-B-12 · P2 · `reset()` 先写默认值再 `clear()`，两步之间失败会留下「已重置」的明文配置而不报错给 UI

- **文件:行号**：`lib/surface/settings.dart:1026-1037`（`reset()`）、对照 `:774-790`（`apply` 的写失败留痕）。
- **问题一句话**：`reset()` 内 `await apply(OgLSettings.defaults)` 先把默认设置写盘（`apply` 自己吞掉写失败只记 `_lastError`），再 `await _persistence.clear()`；`clear()` 抛错时只赋 `_lastError` 而**不调用 `notifyListeners()`**。
- **用户可见后果**：① `clear()` 失败 → 磁盘里留下一份「默认值」明文 JSON（其中 `accelPrivateRepoAccepted=false` 等安全项被重置，属于安全方向的收敛，但 `customFonts` 里可能残留的 `source`/`filePath` 注入项也一并被写回清掉，属正向）；② 更实际的是 `apply` 写盘失败时 `reset` 仍继续 `clear()`，若 `clear()` 成功则最终状态正确、但 `_lastError` 被 `apply` 设过又被 `apply` 成功分支清空逻辑不覆盖 —— 界面错误横幅可能不出现（原则 15）；③ 与 B7-B-06 组合：一次「重置」若被中断（进程被杀），`apply` 与 `clear` 之间无事务/意图落盘（原则 13/14：删除前落盘意图），重启后读到的是「默认值」而非「无记录」，语言首启跟随系统逻辑（`load():755-758`）被跳过，用户语言被静默改成 `zh`。
- **原则**：13（要么完整生效要么可恢复）、14（删除前落盘意图）、15（失败留痕且用户可见）、9（先读后写）。
- **是否确证 + 代码证据**：**确证**。`settings.dart:1027-1036` 中 `catch` 块只有 `_lastError = ...`，无 `notifyListeners()`（对比 `apply:785-789` 的 catch 明确 `notifyListeners()`）；`apply` 与 `clear` 是两个独立 `_persistence` 调用，无 journal/意图记录。
- **备注**：重启后语言被改写属于「配置语义」后果，需运行时确认 `ogLDetectDeviceLocale()` 返回值差异，标「**待议（仅此子项）**」。

### B7-B-13 · P2 · 私有字体清单反序列化不限制条目数/字段长度，`customFonts` 可无界增长

- **文件:行号**：`lib/surface/settings.dart:1041-1058`（`_customFontsOf`：逐条 `Map` → `OgLCustomFont.fromJson` → `out.add`）、`:91-101`（`fromJson` 只查 `id`/`filePath` 非空）、`:655-660`（`toJson` 原样回写）、`lib/surface/pages/settings_page.dart:661-665,744-760`（`customFonts` 全量渲染为选择项与 SimpleDialogOption）。
- **问题一句话**：`customFonts` 列表没有数量上限、每个 `id`/`name`/`source`/`filePath` 没有长度上限，也无重复 id 去重（`upsertCustomFont` 才按 id 去重，反序列化不）。
- **用户可见后果**：被篡改/膨胀的 `ogl.settings` 可塞入数万条字体（`source` 各带 `http://…`），`load()` 时全部进内存；设置页把每一条渲染成 `OgLSettingsChoice` 与 `ListTile`（`settings_page.dart:661-665,748-758`），长列表急加载导致设置页卡顿/ANR；若用户再选中其中一条，`OgLFontLoader.bytesOf` 会对其 `source` 发起请求（B7-B-02）。超大 `name` 字符串还会撑爆 `AlertDialog`/`Text`。
- **原则**：29（所有资源有上限：内存/磁盘/列表）、20（外部数据夹紧）、30（惰性构建 —— 设置页 for 循环全量建控件）。
- **是否确证 + 代码证据**：**确证**。`_customFontsOf` 无 `if (out.length >= N) break`、无 `id.length` / `source.length` 检查、无 `Set<String> seen`（对比 `_asAccelChannels:270-283` 有 `seen` 去重，`_asAccelScopes:289-301` 有白名单 —— 说明项目知道该做，只是字体清单漏了）。`settings_page.dart:661-665` 用 `for (final OgLCustomFont font in value.customFonts)` 直接建 options。
- **备注**：需真机 ANR 复现标「**待议（仅性能子项）**」；无上限本身确证。

### B7-B-14 · P2 · `seedColorId` / `dnsServerId` / `dnsCustomIp` / `dnsCustomDohUrl` 反序列化无白名单，坏值静默生效到网络层

- **文件:行号**：`lib/surface/settings.dart:178`（`seedColorId: seed is String && seed.isNotEmpty ? seed : 'github'`）、`:187-190`（`dnsServerId` 非空即接受）、`:191-194`（`dnsCustomIp` / `dnsCustomDohUrl` 任意字符串）、`:480-486`；对照 `lib/surface/theme.dart:46-66`（`ogLSeedColorOf` 未知 id 回落品牌色）、`lib/surface/surface_bridge.dart:622-623` → `lib/base/net/net_bridge.dart:65-90`（`customIp`/`customDohUrl` 直接构造 `DnsServer`）、`lib/base/net/net_dns.dart:70-93`（`ogLIsUsableDohEndpoint` 会挡非 https/localhost/私网）、`lib/base/net/net_dns.dart:107-125`（`ogLNormalizeDnsAddress` 剥协议/路径）。
- **问题一句话**：四个安全相邻字段只做类型检查，未知 id 由下游「静默回落」，与原则 20 要求的「夹紧回默认值**并记录**」不符；尤其 `dnsCustomIp` 未走白名单，可指向任意 IP。
- **用户可见后果**：篡改 `dnsCustomIp: "127.0.0.1"` / `dnsServerId: "custom"` 会把 DNS 解析器指向本机/内网（`net_dns.dart:89-91` 的 `_ipv4Shape` + `ogLIsSafeIpv4` 只守 DoH 端点，不守 `customServer.ip`；`net_bridge.dart:78-86` 的 `ip` 原样传入 `DnsServer`），后续所有 GitHub 域名解析可被劫持到攻击者 IP（TLS 证书校验是最后兜底，但 DoH 端点校验被绕过时仍有降级面）。`seedColorId` 未知值静默变回品牌色，用户看到「选了主题色没生效」且无日志/提示。`dnsCustomDohUrl` 已有 `ogLIsUsableDohEndpoint` 挡住 `http://`/localhost/私网（**正面确认**），但非法值被静默丢弃而非如实提示。
- **原则**：20（夹紧回默认并记录）、15（不静默降级）、44（对外部目标保持怀疑）、43（网络能力没有后门）、39（DNS 劫持可影响凭证去向）。
- **是否确证 + 代码证据**：**确证**。`settings.dart:178,187-194` 无 `languageCodes`/`codeThemePresetIds` 那样的白名单（对比 `:315-326` `_asLocale` / `_asPreset` 与 `:299-304` `_asAccelScopes` 都做了白名单，说明是选择性遗漏）。`net_bridge.dart:78-86` 的 `customServer.ip = ip` 无 `ogLIsSafeIpv4` 调用；`ogLIsUsableDohEndpoint` 只作用于 `dohUrl`。
- **备注**：DNS 被劫持后能否实际改变连接目标（TLS/SNI/证书链）标「**待议**」（需运行时实测）；字段无白名单与无留痕确证。

### B7-B-15 · P2 · `font_pick.dart` 的 `TextEditingController` 未 dispose；对话框取消/异常时泄漏，且异常文本内插用户路径

- **文件:行号**：`lib/surface/app/font_pick.dart:27`（`final TextEditingController controller = TextEditingController();`）、`:28-49`（`showDialog`）、`:50-66`（取消分支 `return null` 无 dispose；`throw StateError('仅支持 …')` / `StateError('文件不存在：$path')`）、对照 `lib/surface/pages/settings_page.dart:807-812`（catch 后 `_notifier.warning(_t('uiFontFailed', {'error': '$error'}))` 把异常文本上屏）。
- **问题一句话**：控制器无 `dispose()`，且抛出的 `StateError` 把用户输入的整个路径拼进消息，经设置页模板渲染到界面、并经 `OgLAppLog`/`OgLLogFile` 落盘。
- **用户可见后果（数据风险）**：每次打开「添加本地字体」对话框泄漏一个 `TextEditingController`（原则 24）；更重要的是路径若含敏感信息（用户名、企业目录、带 token 的查询串、SAF content:// 路径），会被**原样写进磁盘日志与界面提示**（原则 39 的近亲：不应把外部输入全文进日志；`error_surface.dart:251-275` 的 `add` 同步落盘）。`font_loader.dart:99` 的 `StateError('字体文件不可读：${font.filePath}')` 同样把绝对路径外泄到日志。
- **原则**：24（注册了就要注销）、39（脱敏/不把输入全文进日志）、38（错误信息面向用户）、20。
- **是否确证 + 代码证据**：**确证**。`font_pick.dart` 全文 67 行无 `dispose`；`showDialog` 的 `onPressed` 取消返回 `null`（`:40-42`）后 `:50-52` 直接 `return null`，控制器无释放。`:59,63` 与 `font_loader.dart:99` 的字符串插值直接进异常；`settings_page.dart:811` 的 `_t('uiFontFailed', {'error': '$error'})` 上屏。
- **备注**：`StateError` 文本是否同时进入 `OgLLogFile`（设置页只调 `_notifier.warning`）标「**待议（仅落盘子项）**」；泄漏与上屏确证。

### B7-B-16 · P2 · `token_exit_warning.dart` 白名单含 `github.com` 整域与其未覆盖的子域表述不一致；`OgLAppLog` 决策留痕用 `logLevel` 当事件码，与项目 `OGL-*` 编码体系不符

- **文件:行号**：`lib/surface/app/token_exit_warning.dart:45-64`（`kOgLTokenSafeHosts` 注释「`*.github.com` 整域放行」+ `ogLIsGitHubDownloadHost` 的 `endsWith('.github.com')`）、`:97-107`（`logLevel: 'TOKEN-EXIT-01'`）、`lib/surface/app/error_surface.dart:251-275`（`logLevel` 直接作为 `OgLLogFile.line(level:)` 写入）、对照 `AGENTS.md` §3（事件码 `OGL-BOOT-107`、`OGL-BASE-001` 带层标签）。
- **问题一句话**：`github.com` **整域**（含任意用户可控子域，如 GitHub Pages `*.github.io` 不在列但 `xxx.github.com`、以及任何未来被 GitHub 分配给用户内容的子域）被无条件判定为「令牌可直发」，且白名单只列 4 个字面量、与注释宣称的「`githubusercontent.com` 只放行官方三个子域」在 `gist.github.com` 上不一致（它命中 `*.github.com` 分支被放行，但注释把它算在 githubusercontent 三类里）；决策日志用 `TOKEN-EXIT-01` 作为 `level`，不是可枚举的 `OGL-*` 事件码，`level` 字段本应是 `INFO/WARN/ERR` 严重度。
- **用户可见后果**：① 令牌发往 `*.github.com` 任意子域时**不弹警告、无留痕**（`return true` 早于 `OgLAppLog.add`），若某子域承载用户可控内容/重定向，令牌可能落到非官方服务；与原则 40「只在必要的跳使用一次」不完全等价。② 日志检索按 `level` 过滤时，`TOKEN-EXIT-01` 混在 `WARN/ERR/INFO/STEP` 之间，事后回溯「这次令牌出设备的决策」无法用统一事件码聚合（原则 15 的留痕要求可追溯）。
- **原则**：40（令牌只在必要跳使用一次）、44（对外部目标保持怀疑）、39（脱敏从结构化记录开始）、15（留痕可回溯）、57（注释与列表一致）。
- **是否确证 + 代码证据**：**确证**。`token_exit_warning.dart:60-63`：`h.endsWith('.github.com')` 覆盖全子域；`:89-90` 命中即 `return true`，早于 `:99` 的日志。`error_surface.dart:269-275` 把 `logLevel ?? (按 severity 映射)` 传给 `OgLLogFile.line(level:)`，`OgLLogFile` 的 `level` 在 `:115` 的字体日志里用 `'INFO'`、`font_loader.dart:93` 用 `'ERR'`，佐证它是严重度槽位。
- **备注**：`*.github.com` 子域是否实际承载不可信内容标「**待议**」（需 DNS/产品实测）；白名单语义与日志编码两处确证。

---

## 重点项复验汇总

| 重点项 | 结论 | 证据位置 |
|---|---|---|
| 私有字体下载 URL 校验（SSRF/任意协议） | **不合格**：`startsWith('http')` + 裸 `HttpClient`，绕过项目统一 SSRF/重定向守卫；无大小上限 | B7-B-02（`font_loader.dart:63,74-95`） |
| 字体文件落盘路径 | **不合格**：`Directory.systemTemp/ogl-fonts` 全局可写、名字可预测、缓存直读无校验；本地导入源在缓存被清后不可恢复 | B7-B-05、B7-B-03 |
| `theme_packs/` 是否加载外部代码/资源 | **当前不加载**（目录仅 `.gitkeep`、未进 `pubspec.yaml`、`lib/` 零引用）→ 运行时注入面为 0；但 `trust_policy.dart:111-119` 已把第三方主题定为 `open`（免签名/免告警/免确认），且 `net_mirror.dart` 注释把它与「启用第三方镜像通道」绑定，属**策略级预留风险** | B7-B-09 |
| 用户字体在 `FontLoader` 注册后的内存安全 | **不合格**：无内容/大小校验、`_loaded` 只增不减、无注销、`ByteData.view(bytes.buffer)` 整块交引擎；删除字体后引擎资源仍驻留；`_uiFontFamilyOf` 注释承诺的「未注册回落」实现里并不存在 | B7-B-04 |
| 动效/主题设置被篡改时的边界（超大 `fontScale`） | **正面确认：击穿不了**。`fromJson`（`_clampDouble` 0.8–1.6）→ `setFontScale` 再夹 → `og_l_app.dart:96` 最终 `.clamp(0.85, 2.0)`，超大值不会导致无限缩放。缺口为：夹紧无留痕、三处常量不一致、构造/`copyWith` 可绕过、`reduceMotion`/`motionLevel` 双键矛盾 | B7-B-10、B7-B-11、B7-B-14 |
| `token_exit_warning` 绕过路径复验（批4 `_downloadZip` 之后） | **入队 6/6 已覆盖**（下表）；**非入队路径全漏**：图片预览与 README 图片渲染带 `Authorization` 直发第三方通道，不弹窗、不留痕（P0）。另三处防御性缺口：小写硬编码键、畸形 URL 全文进日志、`*.github.com` 整域免警告 | B7-B-01、B7-B-08、B7-B-16 |

### 批4 `_downloadZip` 修复后的入队入口逐条复验

| # | 入队点 | 门禁 | 认证头来源 | 判定 |
|---|---|---|---|---|
| 1 | `repo_page.dart:306`（`_downloadZip`，批4修的入口） | `:291` | `downloadAuthHeaders()` `:283` | ✅ 已覆盖（批4修复仍成立，`git log 64caf6d`） |
| 2 | `repo_page.dart:1892`（仓库文件下载） | `:1878` | `planRepoFileDownload` `headers` | ✅ 已覆盖 |
| 3 | `release_detail_page.dart:283`（Release 附件） | `:269` | 预签名失败时 `downloadAuthHeaders()` `:263-264` | ✅ 已覆盖；且签名成功时 `headers` 为空，令牌本就不出设备 |
| 4 | `action_run_page.dart:424`（Action 产物） | `:408` | 同上 `:402-403` | ✅ 已覆盖 |
| 5 | `file_preview_page.dart:606`（加入下载） | `:590` | `planRepoFileDownload` `headers` | ✅ 已覆盖 |
| 6 | `gist_detail_page.dart:308`（Gist raw） | 无 | `enqueue` 未传 `headers`；`repoPrivate: false` `:302` | ✅ 安全（恒不带令牌，门禁可省） |
| — | **非入队：`file_preview_page.dart:474-477` `Image.network`** | **无** | `downloadAuthHeaders()` `:463-465` | ❌ **B7-B-01 P0** |
| — | **非入队：`readme_view.dart:344-351` + `:563-568` `Image.network`** | **无** | `repo_page.dart:2142` `downloadAuthHeaders()` | ❌ **B7-B-01 P0** |
| — | 非入队：`file_preview_page.dart:560-570` `openLinkOrCopy(音频)` | 无 | 私有仓库不显示播放按钮（`:548-550` 注释 + `:558` 条件 `!widget.repoPrivate`） | ✅ 安全（私有不带令牌；公开无令牌） |
| — | 后端 `_fallbackToSingle` / `retry`（`ix_download.dart:977/1144`） | 无（直接 `_backend.enqueue`） | 复用**已入队时**存下的 `IxDownloadSpec.headers` | ✅ 复用既有决策，未新增外发面；但 `ogLAssertDownloadUrl` 不在 retry/fallback 路径上，若 spec.url 被内部改写则协议白名单不重跑（并入 B7-B-07） |

> 复验方法：`rg -n '\.enqueue\(' lib/surface` 得 6 处入队 + `rg -n 'ogLGuardTokenExitDownload' lib` 得 5 处门禁，逐一 `file_read` 上下文核对；再 `rg -n 'Image.network|downloadAuthHeaders|headers:' lib/surface` 找出所有「带令牌但非入队」的消费点。

---

## 覆盖文件清单

**范围文件（全部 `file_read` 完整读，行号以当前工作区为准）**

| 文件 | 行数 | 读法 | 本批结论 |
|---|---|---|---|
| `lib/surface/app/font_loader.dart` | 172 | 完整读 2 次（145 行版 + 06:03 批7交叉修改后的 172 行版） | B7-B-02/04/05/15 |
| `lib/surface/app/font_pick.dart` | 67 | 完整读 | B7-B-03/15 |
| `lib/surface/app/token_exit_warning.dart` | 170 | 完整读 | B7-B-01/08/16 + 全入口复验 |
| `lib/surface/settings.dart` | 1058 | 分 3 段完整读（1–858 / 640–1058 / 380–902 补读重叠校验） | B7-B-06/10/11/12/13/14 |
| `lib/surface/util/download_proxy.dart` | 118 | 完整读 | B7-B-07 |
| `assets/theme_packs/` | 目录 + `.gitkeep`(1) | `ls -laR` + 全文读 | B7-B-09（当前仅占位，无外部代码/资源） |
| `assets/theme_packs/.gitkeep` | 1 | 完整读 | B7-B-09 |

**裁决依据（全部完整读）**：`docs/QUALITY_STANDARD.md`(93)、`AGENTS.md`(95)、`docs/NETWORK.md`(154)。

**佐证代码（定点片段 `file_read` / `rg` 核实，未计入「范围文件」）**：`lib/surface/pages/settings_page.dart`（字体导入/私有加速 3 秒警告/通道输入校验）、`lib/surface/surface_bridge.dart`（`planRepoFileDownload` / `repoFileAccelerated` / `_uiFontFamilyOf` / `KvSettingsPersistence` / `themeFor`）、`lib/surface/pages/{repo_page,release_detail_page,action_run_page,file_preview_page,gist_detail_page}.dart`（6 个入队点 + 2 个图片渲染点）、`lib/surface/widgets/readme_view.dart`、`lib/surface/util/accel.dart`、`lib/surface/theme.dart`、`lib/surface/app/{og_l_app,motion,error_surface,overlays}.dart`、`lib/domain/ix/{ix_download,ix_presign,ix_download_backend_io}.dart`、`lib/base/net/{io_net_transport,net_dns,net_bridge,net_mirror}.dart`、`lib/base/disk/{platform_io_impl,og_l_storage,app_dirs}.dart`、`lib/kernel/boot/{trust_policy,boot_loader}.dart`、`pubspec.yaml`、`assets/README.md`、`docs/audit_b7_{a,c,cross}.md`、`docs/audit_b1_b.md`（B1-B-08 复核）。

**未覆盖/不在本次射程**：`lib/` 其余 150+ 文件未逐行复读；`test/` 仅 `rg` 定位（未跑测试，环境无 `dart`/`flutter`，`which dart flutter` → 无）；所有需真机/运行时的子项已在对应条目标「待议」。

---

## 整体评价

**主题与令牌警告子系统的「入队路径」是本项目里被审计得最扎实的一块**：批4 `_downloadZip` 的 P0 门禁缺口修复完整保留，六个 `enqueue` 入口逐个复验全部有 `ogLGuardTokenExitDownload` 前置（第六个 Gist 入口恒不带令牌，可正当省略）；`download_proxy.dart` 的「无降级、无兜底、私有 raw 默认不加速」、`settings.dart` 的 3 秒知情接受语义（`accelPrivateRepoAccepted` false = 不加速）、`accelScopes` 白名单与默认值、协议版本 `>= kOgLAccelConsentVersion` 闸门、`ogLAssertDownloadUrl` 的 http/https 断言、`IoNetTransport` 的手动重定向守卫与 `isForbiddenHost` 私网/元数据拒绝 —— 这些防线**单独看都成立且代码证据清楚**。

**但防线的「覆盖面」有一个系统性盲点：门禁被设计成「下载按钮的前置动作」，而不是「令牌出设备这件事的收口」**。凡是不经过 `downloads.enqueue` 而直接带 `Authorization` 发起请求的路径（图片预览、README 图片渲染）整条漏过（B7-B-01，P0）。这与 `token_exit_warning.dart` 文件头「**凡是**这次会把令牌发给非 GitHub 主机的场景」的承诺直接矛盾，也让 `NETWORK.md` §四 的「用户知情 + 可见」在浏览页面时失效。

**字体子系统是全批最弱的一环**，且是四层叠加的注入面：来源侧 URL 零校验（B7-B-02 SSRF）、输入侧路径零边界（B7-B-03 任意文件读）、落盘侧全局临时目录 + 缓存直读无校验（B7-B-05 内容注入/不可恢复）、注册侧无大小校验/无注销/无回落（B7-B-04 内存与生命周期）。`font_loader.dart` 用 `dart:io` 自建 `HttpClient` 绕过了 AGENTS.md 声明的统一传输层，等于在 L3 开了一条**不受任何 L1 安全策略约束的网络出口**；`NETWORK.md` 的出口清单里完全没有它，`ogLAssertDownloadUrl` / `isForbiddenHost` / `_sendWithGuardedRedirect` 三道既有防线在此全部失效。**这是原则 44「对外部目标保持怀疑」与原则 11「防线没有开关」最实质的破口**。

**设置持久化的威胁模型偏乐观**：`fromJson` 对偏好的容错设计（夹紧、白名单、世代作废）做得很细（尤其 `fontScale`/`motionLevel`/`accelScopes` 都夹紧），但把「安全决策」当成普通偏好来反序列化 —— `accelPrivateRepoAccepted`、`releaseProxyEnabled`、`releaseProxyConsentVersion`、通道 `baseUrl` 全部明文落盘、无完整性校验、反序列化时不重新确认（B7-B-06）。在 `publicDir` 档位下设置文件位于用户可见的公共目录，一旦被篡改，前面所有「3 秒警告 / 协议同意 / 默认关闭」都被一次性绕过，并与 B7-B-01 组合成「无需交互的令牌外发」。建议把安全决策从「可从 KV 恢复的偏好」提升为「带签名或需重新显式确认的授权」，并给 `customFonts` / 通道 `baseUrl` / 字体 `source` 加长度上限、白名单与来源校验。

**`theme_packs/` 的正面结论要明确**：目录当前只有 `.gitkeep`，未进 `pubspec.yaml` 的 assets 清单，`lib/` 里零代码引用 —— **不加载任何外部代码、资源或网络内容，当前运行时注入面为零**。风险仅存在于 `trust_policy.dart` 提前把第三方主题定为 `open` 级（免签名/免告警/免确认），而 `net_mirror.dart` 的文档把它与「启用第三方镜像通道」联系起来；这是未来 M1 落地前必须收紧的策略预留，不是现网漏洞。

**关于「超大 fontScale」的正面结论**：三道夹紧（解析 `0.8–1.6` / setter / `og_l_app.dart:96` 的 `0.85–2.0` 最终 `TextScaler`）使得配置被篡改到 `1e308` 也不可能把界面放大到崩溃，`_motionLevelOf` 还显式挡了 `Infinity/NaN`。**动效与字号边界没有击穿**，本批只对「夹紧无留痕 / 常量三处不一致 / 双键矛盾 / 相邻字段无白名单」记 P2。

**共 16 条**：P0×1 / P1×8 / P2×7。其中静态确证 16 条；含「待议」子项的 9 条（均为环境/运行时子项，静态缺口本身确证），已在各条内逐项标注。与视角 A（B7-A-09 小写键、A-03/04 字体缓存）和视角 C（B7-C-03/04/10）有交叉，本批已在对应条目注明**新增面**（图片路径绕过、SSRF、临时目录污染、完整性校验、生命周期），不与 A/C 重复计缺陷。

**只审不改声明**：本批未修改、未创建、未删除 `lib/`、`tool/`、`assets/` 下任何文件；未创建计划任务；未启动后台服务；未使用 `sleep`。唯一产出为本文件 `docs/audit_b7_b.md`（逐条追加写入）。审计期间 `lib/surface/app/font_loader.dart` 与 `lib/surface/surface_bridge.dart` 被**其他并行批次**（`git log 8214fb7 fix(ui): 批7交叉`）修改，本批已对修改后的 172 行版本重新完整复读并据现行代码出具结论。
