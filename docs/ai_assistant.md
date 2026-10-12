# AI 助手与 GitHub 效率工具

## 使用

1. 在侧栏底部打开 AI 助手，或从仓库右上角 AI 图标进入，自动带入仓库和当前分支。
2. 设置 → AI 设置：选择 DeepSeek、OpenAI 兼容服务、Claude 或 Gemini。自定义服务可选择这三种协议，填写 HTTPS 基础地址和对应密钥。
3. 点击「自动检测可用模型」，从服务返回的模型中选择，然后开启助手并保存。代码没有预设模型名；模型需支持工具调用，列表可见不代表具备该能力。
4. GitHub 操作默认使用软件当前登录账号的 token，无需额外填写。AI API key 与 GitHub token 分开，GitHub token 不发送给 AI 服务。
5. 可以说「切到 owner/repo」，或直接要求读取代码、修改功能、管理 Issue/PR、触发和查询 Actions。短名不能唯一确定时要求完整仓库名。
6. 修改前预览完整文件的前后内容及提交目标；确认后一次性提交。Issue/PR 和工作流触发同样需要确认。取消会终止本轮请求。
7. 聊天右上角可查看操作日志与回滚。文件回滚生成新的撤销提交；已有后续提交时拒绝覆盖。Issue/PR 更新恢复原字段，新建项目通过关闭撤销。已启动的工作流不能自动撤销。
8. 编译完成后结果写回发起操作的聊天，真实产物可加入下载队列。GitHub Actions 产物是 ZIP，可能包含 APK；不伪造不存在的 APK 下载链接。同一账号同时触发同一工作流而无法唯一关联时不会猜测，可在聊天中查询 Actions 运行状态。

## 其他入口

- 通知中心：GitHub 通知分页、已读管理；Issue/PR 在应用中查看，应用日志仍保留。
- Star 管理：本地标签、分类和搜索，数据按账号隔离；最多加载前 2,000 个 Star，并显示范围提示。
- 仓库铃铛：开启/取消默认分支提交和新 Release 提醒。运行时约每 5 分钟检查，恢复应用时补查；关闭或被系统终止后不保证实时提醒。
- 桌面快捷键：Ctrl+P 搜仓库，Ctrl+1 首页，Ctrl+2 搜索，Ctrl+, 设置，Ctrl+Shift+A 助手。聊天 Ctrl+Enter 发送。
- 主题配色与字体缩放沿用设置里已有控件。
- 月度贡献：显示当前账号可搜索的提交总数；增删行对最多 100 个提交逐个计算。采样、未索引数据或请求失败会明确标注，不等同于完整贡献日历。

## 数据与架构

AI 密钥、聊天、日志和构建跟踪使用现有安全存储（Android Keystore、Windows DPAPI、Linux libsecret），没有明文密钥回退。普通配置、Star 分类和关注基线使用现有 KV。

聊天及主动读取的仓库代码会发送到配置的 AI 服务，包括私有仓库，请选择可信服务。请求不跟随重定向；凭据文件、路径穿越、符号链接及二进制修改被拒绝。模型只有固定工具白名单，无任意 HTTP、Shell 或强推能力。

`base/net/ai_http_transport.dart` 负责传输，`domain/ai` 负责协议与操作编排，`domain/productivity` 负责 GitHub 效率工具；`surface` 通过桥和类型门面调用，遵守四层依赖方向。界面新增六种语言分片，包含中文和英文。

## 开发构建与验证

fork 的 `Preview builds` 工作流生成 Android、Windows、Linux debug 测试包（Artifacts 保留 14 天）。开发包不是签名正式发布包，沿用项目已有的调试启动旁路；正式发布仍需自行配置 `.github/signing/README.md` 中的签名密钥，release 校验未被放宽。

`flutter analyze --fatal-infos --fatal-warnings`、`flutter test` 和现有架构/多语言/动效/性能审计在 CI 执行。受限环境可运行 `dart tool/ai_safety_selftest.dart` 验证确认、账号、并发提交、回滚、服务协议与提醒基线。
