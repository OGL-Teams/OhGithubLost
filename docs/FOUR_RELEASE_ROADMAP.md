# 四步小版本路线（v13.x → v14.0.0 正式版）

> 用户指令（2026-11-19）：sota-ux-writing 读字典重写界面文案；sota-docs-workflow 重写技术文档；sota-copywriting 重写 README；三个 skill 交子代理执行审计+修改；计划书追加同时写入记忆；在 MD3 工作完成后，分四步（四个小版本）实现全部功能，发布 v14 正式版。

## 前置（已完成）
- MD3 全面执行：commit 0851f7f + 三轮 CI 修复（71ca2d4），CI 绿 / Build 收尾中。
- V2 审计 97/100（docs/MD3_AUDIT_V2.md，V1 90）。
- 30 语言 i18n、dynamic color、48dp、断点常量、原生组件替换全部落地。

## 第 1 步 · v13.1.0-beta —— 文案与文档（skill 代理批）✅ 已完成（Release v13.1.0-beta，prerelease=true，23 产物）
1. **sota-ux-writing**（子代理）：读 skill 字典，审计全 UI 文案（i18n zh 源 + 页面内文案），产出问题清单并重写（微文案/空态/错误/按钮标签）。30 语言键集合不动，只改 zh 源值 + en 对齐，其余语言由 i18n 增量管线跟进。
2. **sota-docs-workflow**（子代理）：审计 docs/ 与 AGENTS.md，重写技术文档（Diátaxis 结构、README、runbook）。
3. 门禁 + 提交 + 发 v13.1.0-beta（prerelease）。

## 第 2 步 · v13.2.0-beta —— README 与品牌（skill 代理批）✅ 已完成（Release v13.2.0-beta，prerelease=true，23 产物）
1. **sota-copywriting**（子代理）：按 skill 重写 README.md / README-en.md（定位/价值主张/首屏/CTA）。
2. 法律/声明文本与 README 一致性核对。
3. 发 v13.2.0-beta（prerelease）。

## 第 3 步 · v13.3.0-rc —— 功能收口（主会话 + 代理）✅ 已完成（Release v13.3.0-beta，prerelease=true，23 产物）
1. MD3_AUDIT_V2 未闭环项：Layout（WindowSizeClass 官方 API 或注释决策）、Navigation（list-detail 评估）、Accessibility（对比度自查工具）。
2. i18n：ux-writing 改动产生的 delta 走增量翻译管线（源值快照）。
3. 全门禁 + 全测试 + 发 v13.3.0-rc（prerelease）。

## 第 4 步 · v14.0.0 正式版
1. 回归总检：四层架构审计 + 十一门禁 + 元验证 + 全平台 Build。
2. release_notes / CHANGELOG / _content / 归档（releases.json + _posts）。
3. **发 v14.0.0 正式版（prerelease=false，23 产物）**。

## 纪律
- 三个 skill 均由子代理执行（先读 SKILL.md 再动手）；主会话核验 diff + 门禁。
- 每步一个版本号，走完整发布流程（dispatch build.yml + 归档）。
- prerelease 在第 4 步前为 true。
