/// L3 展示级 · 下载加速的**路由判定**（唯一定策处）。
///
/// ## 总开关与协议
/// 加速通道会把流量导向**应用之外的服务器**（地址由用户自行指定，本应用不再
/// 预置任何通道），属于信任边界外的行为，因此必须由用户显式开启并同意协议
/// （`util/accel.dart`，含版本号）。本文件只做**纯判定**，不碰 IO，便于单测。
///
/// ## 两条族：能不能加速，取决于「怎么拿到内容」
/// | 族       | 资源                              | 加速条件 |
/// |----------|-----------------------------------|---------|
/// | 签名族   | Release 附件 / Action 日志 / 产物 | 大小未知或超过阈值 |
/// | raw 族   | 仓库文件 / README 仓库内图片      | 公开仓库；私有需知情接受 |
///
/// raw 族走 `raw.githubusercontent.com`，该端点**没有签名机制**：私有内容必须
/// 直接带 `Authorization` 头。交给通道就等于把令牌送出去 —— 所以私有仓库**默认
/// 不加速**，只有用户知情接受后才放行（见 [privateAccelAccepted]）。
///
/// 反过来，**不加速时仓库文件也必须走 API**
/// （`/repos/{o}/{r}/contents/{path}` + `Accept: application/vnd.github.raw`）：
/// raw 直链对私有仓库根本取不到内容，而该 API 端点带上令牌就可用，且实测
/// 支持 Range（多连接分片不受影响）。
///
/// ## 为什么还要阈值
/// 小文件加速没有收益（延迟主导，多一跳反而更慢），却要多经一次第三方。
/// 阈值同时让「哪些内容会离开设备」的范围**可控可解释**。
library;

/// 大文件阈值：**小于等于 500KB 不加速**。
const int kOgLAccelMinBytes = 500 * 1024;

/// 资源族（决定能否加速）。
enum OgLAccelFamily {
  /// **签名族**：Release 附件、Action 运行日志、Action 构建产物。
  ///
  /// 三者都是「302 → 短期签名 URL」结构，且**公开与私有仓库都能取到签名**。
  /// 因此这一类始终按「先本地解出签名地址，再把签名地址交给加速通道」处理：
  /// 令牌不出设备，代理拿到的是一个**短期、无令牌**的地址。
  signed,

  /// **raw 族**（README 仓库内图片、仓库文件）：公开仓库可直接加速。
  ///
  /// 私有仓库**默认不加速**：raw 端点没有签名机制（实测：匿名 404；
  /// `?token=` 查询参数形式已被废弃、同样 404），要让它返回内容就必须带上
  /// `Authorization` 头，而带头的 URL 一旦交给通道就等于把令牌送出去。
  /// 只有在用户**显式知情接受**之后才放行 —— 关闭那个开关的语义是
  /// 「不再询问且不再加速」，不是「别问了但照旧送」。
  raw,
}

/// 判定某个资源走不走加速，并给出地址。
///
/// ## 返回语义（v6.4.3 起：**没有降级、没有兜底**）
/// 列表里**至多一项**：
/// - 不走加速 → 原始直连地址；
/// - 走加速 → `前缀 + 原始地址`，**就这一项**。
///
/// 此前这里返回「前缀 + 原址，再垫一个直连」，下载器逐个探测、静默降级。
/// 那有两层坏处：一是**用户以为在加速、其实走的直连**；二是"到底有没有经过
/// 代理"成了没人说得清的问题。现在加速开启且命中规则就是走通道，失败如实
/// 报错 —— 让结果与界面说法一致，比"总有一条路能通"重要。
///
/// ## 判定规则
/// - [prefixes] 为空（未启用、未同意当前版本协议、或**没有自定义通道**）→ 直连；
/// - **签名族**（Release 附件 / Action 日志 / 产物）：`bytes` 未知或超过
///   [kOgLAccelMinBytes] 即加速。未知时按「值得加速」处理 —— 这类资源本就是
///   大 blob，且大小要先下才知道；
/// - **raw 族**（仓库文件 / README 仓库内图片）：公开仓库直接加速；私有仓库
///   需要用户先**知情接受**「令牌会交给第三方通道」（[privateAccelAccepted]）。
///   理由：raw 端点没有签名机制，私有内容的 raw 必须带 `Authorization`，
///   交给通道就等于把令牌送出去 —— 所以默认不送，接受后才送。
/// - `bytes` 已知且 ≤ 阈值 → 不加速（小文件加速没有收益，却要多经一次第三方）。
List<String> ogLAccelCandidates({
  required String url,
  required List<String> prefixes,
  required OgLAccelFamily family,
  int? bytes,
  bool repoPrivate = false,

  /// [privateAccelAccepted]：私有仓库 + raw 族时，用户是否已**知情接受**
  /// 「令牌会交给第三方通道」。默认 `false` → 不加速（令牌不出设备）。
  bool privateAccelAccepted = false,
}) {
  if (url.isEmpty) {
    return const <String>[];
  }
  // ★ 非 http(s) 一律原样返回：加速前缀拼到 `file://` 之类地址上只会产出
  //   垃圾，且这里不做检查就等于把「协议白名单」的责任推给调用方。
  //   入队口另有 `ogLAssertDownloadUrl` 兜底，但**两层都要有**。
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return <String>[url];
  }
  final bool bigEnough = bytes == null || bytes > kOgLAccelMinBytes;
  // 私有 + raw：只有在用户知情接受后才放行（否则令牌绝不出设备）。
  final bool privateOk = !repoPrivate || privateAccelAccepted;
  final bool familyOk = family == OgLAccelFamily.signed || privateOk;
  if (prefixes.isEmpty || !familyOk || !bigEnough) {
    return <String>[url];
  }
  // ★ 只给一项：没有第二候选，也没有直连垫底（见上方说明）。
  final String base = prefixes.first;
  if (base.isEmpty || url.startsWith(base)) {
    return <String>[url];
  }
  return <String>['$base$url'];
}
