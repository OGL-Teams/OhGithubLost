# GitHub OAuth App（Device Flow）配置指引

> ⚠️ **实测结论（2026-11-08）**：GitHub 的 **OAuth Apps 只能挂在个人账号下**，
> 组织设置页没有 OAuth Apps 入口（`organizations/<org>/settings/developers` 与
> `/applications` 均返回 404）；组织名下能创建的是 **GitHub Apps**
> （`organizations/<org>/settings/apps`），那是另一套体系（installation token、
> JWT、安装回调），**不适用于 Device Flow**。
> 此外 GitHub **没有创建／列出 OAuth App 的 REST API**
> （`/user/oauth_apps`、`/orgs/<org>/oauth_apps` 均为 404），只能经网页表单创建。
>
> 因此：用组织管理员的个人账号创建 App、把它登记在组织仓库的 Secrets 中，
> 是本项目当前唯一可行路径。Client ID 属公开标识，不属机密；Client Secret
> 不用于 Device Flow，**不得**写入仓库或注入客户端。

## 一、归属说明

- App 挂在创建者个人账号下，但 Client ID 由**组织级 Actions Secret** 持有并
  注入组织仓库的构建；成员变动不影响构建；
- 组织若启用「第三方应用访问限制」或 SAML SSO，管理员仍可批准／拒绝该应用，
  并能查阅组织审计日志中的授权事件（事件记录，不含令牌或仓库内容）；
- Client ID 所有者无法取得任何用户的访问令牌：Device Flow 的令牌仅返回至
  发起轮询的设备，GitHub 应用后台亦不展示或导出。

## 二、创建步骤（组织管理员执行）

1. 打开直达链接（个人 Developer settings）：
   **https://github.com/settings/applications/new**
   （列表页：https://github.com/settings/developers ）
2. `Application name`：`OhGithubLost`（确认页显示此名，须与应用内名称一致）；
3. `Homepage URL`：`https://github.com/OGL-Teams/OhGithubLost`；
4. `Authorization callback URL`：填同一仓库地址（Device Flow 不回调此地址，
   表单强制填写）；
5. 创建后进入应用 `Settings`，勾选 **Enable Device Flow** —— 未勾选时
   `POST /login/device/code` 必定失败；
6. 复制 **Client ID**（形如 `Ov23li…`）。**不要**生成或复制 Client Secret。

## 三、组织侧放行（若组织有限制）

- 组织若启用「第三方应用访问限制」或 SAML SSO，需由管理员批准该应用一次；
  成员首次授权时另需完成 SSO 授权；
- 本应用请求的范围为 `repo read:user`（仓库读写、账号资料读取），由代码
  `lib/domain/gh/gh_oauth_io.dart` 写死，应用所有者无法单方面扩大。

## 四、注入构建

1. 组织 `Settings` → `Secrets and variables` → `Actions` → `New organization secret`：
   - Name：`OGL_GITHUB_CLIENT_ID`
   - Value：上一步的 Client ID
   - Repository access：授予 `OGL-Teams/OhGithubLost`
2. `build.yml` 的「生成并注入 .dart_define.json」步骤会把它写入
   `dart_define.json`，各平台经 `--dart-define-from-file` 编译期注入；
   `boot_manifest.py` 的 Ed25519 签名载荷独立计算，不受此键影响。
3. 未配置该 Secret 时，步骤给出警告，登录页自动隐藏授权按钮；令牌登录不受影响。

## 五、验证

- 发布版登录页应出现「使用 GitHub 账号登录」；
- 点击后显示一次性代码与 `github.com/login/device`；在 GitHub 页面核对应用名、
  权限范围后确认；
- 登录后令牌仅入本机安全存储（`DiskVault`），退出登录即删除；
- Web 版为独立分支，`gh_oauth_stub.dart` 明确不支持，仍使用令牌登录。

## 六、声明

应用内「隐私与协议声明」§ 八 已载明：开发者无主观意愿植入后门或暗中提取、
回传用户资料之机制；此为对开发意图之说明，不构成担保，使用者可审阅公开的
源代码与构建配置自行核验。该声明为说明性文本，不产生法律效力；唯一具法律
效力之文件为随程序发布之 Apache License 2.0。
