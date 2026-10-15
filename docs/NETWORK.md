# 网络连接总览

> 本文回答三个问题：**应用向哪些主机发起请求**、**每类 GitHub 资源经何种途径获取**、
> **浏览器（web）端哪些途径可用**。
>
> 相关文档：[`docs/USAGE.md`](USAGE.md)（使用说明）· [`docs/I18N.md`](I18N.md)（多语言手册）
> · [`CHANGELOG.md`](../CHANGELOG.md)（版本历史）· [`release_notes/`](../release_notes)（发布说明）
>
> 维护要求：本文所引用的每个符号必须与代码一致且**真实存在**；符号改名或行为变更时
> 须一并更新，否则文档将失去准确性。

## 一、出口清单

| 目的地 | 何时 | 是否带令牌 | 代码位置 |
|---|---|---|---|
| `api.github.com` | 仓库元数据、文件内容、Action 日志 | 是（Bearer） | [`lib/domain/gh/gh_client.dart`](../lib/domain/gh/gh_client.dart) |
| `raw.githubusercontent.com` | raw 族 / 仓库内图片直链 | 私有时必须带 | [`SurfaceBridge.planRepoFileDownload`](../lib/surface/surface_bridge.dart) |
| `github.com` | 令牌校验、OAuth Device Flow | OAuth client_id | [`lib/domain/gh/gh_client.dart`](../lib/domain/gh/gh_client.dart) |
| `objects.githubusercontent.com` / `release-assets.githubusercontent.com` | Release 附件 / Action 产物 | 否（仅用签名） | [`lib/domain/ix/ix_presign.dart`](../lib/domain/ix/ix_presign.dart) |
| DoH 解析器 | DNS 被污染时的加密解析 | 否 | [`DnsService`](../lib/base/net/net_dns.dart) |
| **用户自备的加速通道** | **仅当用户自行添加通道、开启加速、且该类资源在适用范围内** | 见 §四 | [`ogLAccelCandidates`](../lib/surface/util/download_proxy.dart) |

**传输层**：[`NetTransport`](../lib/base/net/net_transport.dart)（抽象）
→ [`ResilientTransport`](../lib/base/net/net_transport.dart)（重试 / 主机冷却 / DoH 回落）
→ [`IoNetTransport`](../lib/base/net/io_net_transport.dart)（真实 HTTP）。
分片下载由 [`OgLRangeDownloader`](../lib/base/net/range_download.dart) 实现。

> **自 v6.4.3 起，本应用不预置任何代理地址。**
> 两处「内置代理」均已删除：下载加速的内置通道（原 `proxy.344977.xyz`）与网络
> 镜像（原 `ghproxy.net` 换主机规则）。[`defaultMirrorChannels`](../lib/base/net/net_mirror.dart)
> 现为空列表，镜像机制虽保留，但**当前完全不生效**。如需加速，须由用户自行提供通道地址。

## 二、加速适用范围（哪些资源会走通道）

**由用户逐项决定**。原因在于：前缀式代理开放的端点有限 —— 有的能转发 Release 附件，
却转发不了仓库内图片。若将「哪些资源加速」固化，必然有部分用户无法使用。

| 适用范围 | 资源 | 代码位置 | 资源族 |
|---|---|---|---|
| `releaseAsset` | Release 附件 | [`release_detail_page.dart`](../lib/surface/pages/release_detail_page.dart) | signed |
| `actionArtifact` | Action 构建产物 | [`action_run_page.dart`](../lib/surface/pages/action_run_page.dart) | signed |
| `repoFile` | 仓库文件（下载与预览） | [`surface_bridge.dart`](../lib/surface/surface_bridge.dart) · [`file_preview_page.dart`](../lib/surface/pages/file_preview_page.dart) | raw |
| `readmeImage` | README 仓库内图片 | [`repo_page.dart`](../lib/surface/pages/repo_page.dart) | raw |

- 枚举定义：[`OgLAccelScope`](../lib/surface/util/accel.dart)（**只有这 4 类**）。
- 默认**全开**（与历史行为一致），可逐项关闭；全关也合法（等于不加速）。
- **Action 运行日志不走加速**（[`ix_action_logs.dart`](../lib/domain/ix/ix_action_logs.dart)
  直接请求 `api.github.com`），因此没有对应开关 —— 上述清单以代码为准。
- 各调用点仅声明「我是哪一类」，是否加速统一由
  [`OgLSettings.accelPrefixesFor`](../lib/surface/settings.dart) 判定，
  保证同一资源不会出现两处不同结论。

## 三、资源取法

### 3.1 签名族 —— 公开与私有都能加速

Release 附件 / Action 构建产物结构相同：先拿 API 地址，**在设备本地**解 302 得到
带签名的直连地址，再把**签名地址**交给通道 —— 令牌不离开设备。私有仓库同样能解出
签名（经实测：私有仓库的 Action 产物 302 带 `X-Amz-Signature`），故这一族不受仓库公私限制。

签名解出：[`IxPresign.resolve`](../lib/domain/ix/ix_presign.dart) → `IxPresignResult`。

### 3.2 raw 族 —— 私有需知情接受

| 场景 | 取法 |
|---|---|
| 加速关 / 未同意协议 / 没有自建通道 / **该范围已关** | Contents API + Bearer（`Accept: application/vnd.github.raw`） |
| 加速开 + 公开仓库 | raw + 自备通道 |
| 加速开 + 私有仓库 | 默认仍走 API；用户**知情接受**后才走 raw + 通道 |

私有 raw 的实测依据如下：**匿名访问返回 404**；`?token=` 查询参数早已废弃、**同样返回 404**；
携带 `Authorization` 头才返回 200。而要取得内容就必须携带该头，交给通道即等于交出令牌 ——
因此默认不发送，用户显式接受后才发送。

### 3.3 无降级、无兜底

[`ogLAccelCandidates`](../lib/surface/util/download_proxy.dart) 现**至多返回一项**：
启用加速即 `前缀 + 原址`，不启用即原址。

此前实现会返回「前缀 + 原址，再追加一个直连」候选，下载器逐个探测、静默降级 —— 这使得
「是否经过通道」无从判定，也会让用户误以为加速正在生效。
当前行为：**启用即走通道，失败如实报错**。

## 四、私有仓库加速的用户知情豁免

1. 命中「私有仓库 + raw 族 + 加速开启」且用户尚未接受时，先弹出**警告弹窗**；
2. 弹窗须展示 **3 秒**后方可操作（防止误操作连续点击）；
3. 用户可在加速设置页永久关闭该问询 —— 关闭的语义为
   **不再询问且不再加速**，退回 API 直取；
4. 弹窗须说明：令牌将离开设备、进入第三方通道（经实测，通道会携带它请求 GitHub）。

> 第 3 条的语义至关重要：关闭询问即**拒绝**加速，而非「不再询问但照旧发送」。

实现位置：[`settings_page.dart`](../lib/surface/pages/settings_page.dart) 的
`_showPrivateAccelWarning` / `_setPrivateAccelAccepted`。

## 五、web（浏览器）端的限制 —— 均经实测

| 场景 | 结果 | 含义 |
|---|---|---|
| `api.github.com` GET | `ACAO=*` | 可 fetch |
| `api.github.com` 预检 | 204，allow-headers 含 `Authorization` | 带令牌可 fetch |
| `raw.githubusercontent.com` GET | `ACAO=*` | 公开仓库可 fetch |
| `raw` 预检 | **403** | 不能带 `Authorization`，私有 raw 不可取 |
| 加速通道 GET | `ACAO=*` | 可 fetch |
| 加速通道预检 | **308，无 CORS 头** | 带自定义头时通道不可用 |
| Release **签名地址** | **无 ACAO** | 签名地址无法 fetch（导航可用） |
| 通道 + Release 直链 | `ACAO=*` | 可 fetch |

结论（web 端）：
- 私有仓库的**文件内容**只能经 `api.github.com`（预检支持 `Authorization`）；
- 私有仓库的 raw 与「私有 + 加速」**均不可用**；
- Release 附件的**签名地址**因缺少 CORS 无法被脚本读取 —— 下载或交由浏览器导航
  （仅公开仓库），或经用户自备通道。

## 六、复现命令（排查用）

```bash
TOKEN=<PAT>

# 1) raw 是否支持断点续传（公开应 206）
curl -s -o /dev/null -w '%{http_code}\n' -H "Range: bytes=0-99" \
     https://raw.githubusercontent.com/<o>/<r>/HEAD/README.md

# 2) 私有 raw：匿名应 404，?token= 也应 404，带令牌才 200
curl -s -o /dev/null -w '%{http_code}\n' https://raw.githubusercontent.com/<o>/<r>/HEAD/<path>
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
     https://raw.githubusercontent.com/<o>/<r>/HEAD/<path>

# 3) 签名族：应 302 且 Location 含 X-Amz-Signature
curl -sI -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream" \
     "https://api.github.com/repos/<o>/<r>/releases/assets/<asset-id>"

# 4) CORS：带 Origin 看 ACAO
curl -sI -H "Origin: https://example.org" https://api.github.com/rate_limit
```

## 七、待办

- [ ] 同步脚本 [`_setup/ogl_sync.py`](../../../_setup/ogl_sync.py) 忽略 `web/` 与 `app/`：
      Flutter web 脚手架无法同步，需交由 CI 生成，或为 web 分支放开该忽略。
- [ ] [`i18n_scan.py`](../tool/i18n_scan.py) 的 UI/日志分类跨度偏宽：`settings_page.dart`
      里一句面向用户的文案曾被判成开发者日志而漏检。
- [ ] 镜像机制（`MirrorChannel` / `MirrorSelector`）已无内置通道、当前不生效，属死代码。
