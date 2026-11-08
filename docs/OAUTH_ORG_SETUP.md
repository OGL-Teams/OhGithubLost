# 组织名下 GitHub OAuth App（Device Flow）配置指引

> Client ID 为公开标识，不属机密；Client Secret 不用于 Device Flow，**不得**
> 写入仓库或注入客户端。本应用仅使用 `client_id` 发起设备流，令牌只返回至
> 发起轮询的终端设备。

## 一、为何置于组织名下

- 授权确认页显示「by OGL-Teams」，而非个人用户名，可信度更高；
- 凭证归组织所有，与个人账号解耦；人员变动时只需在组织内管理应用；
- 组织自己拥有的 OAuth App 通常不受「第三方应用访问限制」的额外审批约束；
- Client ID 所有者无法取得任何用户的访问令牌：Device Flow 的令牌仅返回至
  发起轮询的设备，GitHub 应用后台亦不展示或导出；
- 依据 GitHub 官方文档「A user or organization can own up to 100 OAuth apps」，
  用户与组织均可拥有 OAuth App。

## 二、创建步骤（组织所有者／管理员执行）

1. 打开组织 Developer settings 的 OAuth Apps 列表：
   **https://github.com/organizations/OGL-Teams/settings/applications**
   点击 **New OAuth App**（首次创建时按钮为 Register a new application）。
   若该路径需登录后才可见，请先用组织管理员账号登录再访问。
2. `Application name`：`OhGithubLost`（确认页显示此名，须与应用内名称一致）；
3. `Homepage URL`：`https://github.com/OGL-Teams/OhGithubLost`；
4. `Authorization callback URL`：填同一仓库地址（Device Flow 不回调此地址，
   表单强制填写）；
5. **勾选 Enable Device Flow** —— 未勾选时 `POST /login/device/code` 必定失败；
6. 复制 **Client ID**（形如 `Ov23li…`）。**不要**生成或复制 Client Secret。

> 说明：GitHub 没有创建／列出 OAuth App 的 REST API，只能经网页表单创建；
> 组织名下另一入口 `settings/apps` 属于 **GitHub Apps**（installation token、
> JWT、安装回调），是另一套体系，不适用于 Device Flow。

## 三、多环境隔离

如同时维护 Staging 与 Production，应在组织下注册**两个独立的 OAuth App**，
各自持有 Client ID，避免测试环境配置影响线上。构建注入时按环境分别配置
同名组织级 Secret，或使用不同名称并在 workflow 中分派。

## 四、组织侧放行（若有限制）

- 组织若启用「OAuth App access restrictions」或 SAML SSO，管理员可批准该应用；
  组织自有的应用通常自动受信任；成员授权时按组织策略可能需要 SSO 授权；
- 本应用请求的范围为 `repo read:user`（仓库读写、账号资料读取），由代码
  `lib/domain/gh/gh_oauth_io.dart` 写死，应用所有者无法单方面扩大。

## 五、注入构建

1. 组织 `Settings` → `Secrets and variables` → `Actions` → `New organization secret`：
   - Name：`OGL_GITHUB_CLIENT_ID`
   - Value：上一步的 Client ID
   - Repository access：授予 `OGL-Teams/OhGithubLost`
2. `build.yml` 的「生成并注入 .dart_define.json」步骤会把它写入
   `dart_define.json`，各平台经 `--dart-define-from-file` 编译期注入；
   `boot_manifest.py` 的 Ed25519 签名载荷独立计算，不受此键影响。
3. 未配置该 Secret 时，步骤给出警告，登录页自动隐藏授权按钮；令牌登录不受影响。

## 六、验证

- 发布版登录页应出现「使用 GitHub 账号登录」；
- 点击后显示一次性代码与 `github.com/login/device`；在 GitHub 页面核对应用名、
  组织归属与权限范围后确认；
- 登录后令牌仅入本机安全存储（`DiskVault`），退出登录即删除；
- Web 版为独立分支，`gh_oauth_stub.dart` 明确不支持，仍使用令牌登录。

## 七、声明

应用内「隐私与协议声明」§ 八 已载明：开发者无主观意愿植入后门或暗中提取、
回传用户资料之机制；此为对开发意图之说明，不构成担保，使用者可审阅公开的
源代码与构建配置自行核验。该声明为说明性文本，不产生法律效力；唯一具法律
效力之文件为随程序发布之 Apache License 2.0。
