/// L3 交互层 · **类型门面**（UI 唯一允许接触逻辑层类型的地方）。
///
/// ## 为什么需要它
/// 四层纪律里，交互层**不允许直接取用逻辑层的能力**（服务、客户端、缓存…），
/// 但页面确实需要**数据形状**（DTO）与**异常类型**才能渲染与提示。
/// 若页面直接 `import '../../domain/gh/gh_models.dart'`，纪律就变成"口头约定"，
/// 谁都能顺手把 `GhAuthService` 拽进页面。
///
/// 因此这里把"允许交互层看到的类型"**显式列出**：
/// - 保留：DTO / 枚举 / 异常；
/// - **隐藏**：一切服务与实现（`GhClient` / `GhAuthService` / `IxDownloadManager` …），
///   它们只能通过 `SurfaceBridge` 取用。
///
/// 新增页面若要暴露新的领域类型，**请改这个文件**，而不是把 domain 路径写进页面。
library;

/// 账户：仅暴露状态枚举与账户 DTO，**隐藏** `GhAuthService`。
export '../domain/gh/gh_auth.dart' hide GhAuthService;
/// 客户端：仅暴露异常类型，**隐藏** `GhClient` 与限流快照的内部构造。
export '../domain/gh/gh_client.dart' hide GhClient;
export '../domain/gh/gh_draft.dart';
export '../domain/gh/gh_models.dart';
/// 下载：暴露任务 / 分类 / 状态，**隐藏**下载管理器。
export '../domain/ix/ix_download.dart' hide IxDownloadManager;
/// 通知：暴露通知模型，**隐藏**通知中心实现。
export '../domain/ix/ix_notify.dart' hide IxNotificationCenter;

/// 第一跳解析：页面用它把「需认证的地址」换成短期签名地址（令牌不出设备）。
export '../domain/ix/ix_presign.dart' show IxPresign;
/// 会话与任务：只暴露状态模型。
export '../domain/ix/ix_session.dart' hide IxSession;
export '../domain/ix/ix_task.dart' hide IxTaskRunner;