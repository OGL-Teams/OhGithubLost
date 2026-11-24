# UI 打磨执行任务书（V2 复审后，7 批）

> 用户已确认执行（2026-11-24「OK」）。依据 docs/UI_AUDIT_V2_REPORT.md 的 7 批打磨计划。
> 全部子代理必须先读本文件。

## 绝对纪律
1. **禁读 Flutter SDK**：禁止读取/下载/复制 `/root/flutter`、`/opt/flutter`、`/tmp/dart-sdk`、pub 缓存包源码；只用项目自身 lib/ 已验证代码；需要框架 API 事实就跳过并标「待核实」；本地 dart 仅用 `/opt/dart/bin/dart format`。违反即取消+全量清理。
2. **每批独立提交**：CI 绿才进下一批。子代理只改本批清单内文件，完成后主会话核验（format 0 changed + 12 门禁 + 相关测试）再提交。
3. **i18n**：新增文案必须走键（30 语言同步），优先复用已有键；硬编码中文会被 i18n_scan 拦下。
4. **不新增 API/架构**：只做收编与接线，不改分层、不动 gate/diagnostics 机制。
5. **测试**：改动行为时同步更新受影响测试断言（v15 经验：断言与新行为不符会让 CI 红）。

## 批次清单（依据 docs/UI_AUDIT_V2_REPORT.md「打磨计划」节，每批开工前先读该节原文）
- 批 1：假门与裸转圈（4 处假 CTA 接真或删、16 处裸转圈→OgLAsyncSkeleton、首页 _checked 骨架化、游客 CTA 改「去登录」）
- 批 2：边框与 AppBar 统一（40 处裸 OutlineInputBorder 收编、15 页裸 AppBar→OgLAppBar、侧栏接地补 SafeArea/底座、顶栏两套色阶统一）
- 批 3：错误可恢复与提交闸（失败提示加重试出口、危险确认框收编 ogLDangerConfirm 剩余 7 处、提交闸前移、300ms 防抖位置修正、settings 弹窗不吞输入）
- 批 4：密度与效率（目录行补 meta、issue 首屏评论、评论输入固定栏、通知行降噪、列表行模板降高、空态 CTA 真实化）
- 批 5：表单与输入（47 字段 label 可见化、字段级 errorText、弹窗不吞输入、inputmode）
- 批 6：动效与一致性（路由/对话框/Hero 时长接档位、reduce-motion 全局生效、切 tab 竞态、图标语义层收编剩余 29 处、分页模式统一）
- 批 7：无障碍与收尾（Chip 48dp、焦点可达、读屏状态语义、对比度全量、宽屏限宽下沉）

## 主会话执行流程（每批）
派代理（带本纪律）→ 核验（format 0 changed / 12 门禁 / contrast_audit / i18n_scan，行为改动则跑相关测试）→ 提交推送 → CI 裁决定时器 → 绿后下一批。四批以上完成后发版（patch 递增），最后总汇报。
