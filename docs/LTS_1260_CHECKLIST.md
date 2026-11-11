# v12.6.0 LTS · 发布前验收清单

> 目标：**没有任何问题才发布**。本清单是发版门槛，逐项打勾后才允许
> 升版本号 → tag → dispatch 发布构建。
> 背景：用户判定下载系统不充分（重名覆盖 / 通知点查看返回 null /
> 进度模糊 / 多线程不充分），发现页仍有进步空间；此前 v12.5.x
> 连续三版都靠真机反馈返工，LTS 不允许再这样。

## 一、功能验收（真机必测）

### 下载（本轮改造重点）
- [ ] **重名不覆盖**：目标目录已有 `a.zip`，再下载同名附件 → 实际落盘 `a (1).zip`，原文件完好
- [ ] **同任务重试**：下载失败后重试 → 仍写原文件名，不产生 `a (1).zip`
- [ ] **通知点「查看下载」**：入队通知条点「查看下载」→ 打开下载管理页（不再返回 null / 空白）；在其它页面点也一样
- [ ] **进度可读**：任务行显示「已接收 / 总量 + 百分比 + 速率 + N 线程」，分片任务（多线程）数字持续前进
- [ ] **多线程真实生效**：设置里调连接数 >1 → 大文件（Release 附件）下载速率明显高于单连接（需真机对比）
- [ ] **失败不留半成品**：中途取消 → 无 `.partN` 残留、无坏文件
- [ ] **SAF / 公共目录两档**：存储权限开与关两种状态下，落盘位置都正确、重名逻辑都生效

### 发现页
- [ ] 三 tab（动态 / 推荐 / Issues）加载骨架与真实行对齐，不闪跳
- [ ] 下拉刷新三 tab 都可用（档位 0 / 减少动效时仍可刷新）
- [ ] Issues 行显示仓库名与 `#编号`
- [ ] 推荐卡：README 摘要、版本号、star 数正常；长按菜单可用
- [ ] 分类筛选五档窄屏不溢出
- [ ] 空 / 错误态文案六语言完整，重试可用

### 回归（此前真机反馈不得复发）
- [ ] 推荐选语言分类 → 立即加载（v12.5.1 修复）
- [ ] 动态 tab 有内容（v12.5.1/12.5.2 修复）
- [ ] 编辑器工具栏满宽无白缝（v12.5.2 修复）
- [ ] Issues 胶囊文字在胶囊内（v12.5.2 修复）

## 二、自动验证（CI 裁决）

- [ ] `flutter analyze --fatal-infos --fatal-warnings` 绿
- [ ] `flutter test` 全绿（含新增：重名改名 / 通知跳转 / 发现页接线）
- [ ] 十一道门禁绿（layer / contract / ui / motion / perf / i18n --check /
      ci_config / gate_of_gates / version_sync / sort_imports --fatal /
      check_content --check）
- [ ] `dart format --set-exit-if-changed` 无差异
- [ ] Build 矩阵 9 腿全绿（Gradle 缓存命中后 ~452s 墙钟）
- [ ] Release 23 产物齐全（zip + 7z 双份）

## 三、发布流程纪律

- [ ] 版本号 `pubspec.yaml` 与 `kOgLAppVersion` 一致（version_sync 把关），
      LTS 取 **12.6.0**（build 126000）
- [ ] `release_notes/v12.6.0.md` 正规来源就位（不再用自动模板）
- [ ] `changed/_content/v12.6.0.md` 按 `_STYLE.md`（350–700 字、面向用户）
- [ ] `CHANGELOG.md` 顶部 12.5.3(未发布) 条目改为 12.6.0 正式内容
- [ ] tag 指向 **CI 全绿提交**（历史上两次 tag 指向红提交导致发布构建失败）
- [ ] 发布后核对：Release 正文非模板、23 产物、`releases.json` 键名 url、
      `generate_posts.py` 生成日志、GitHub Pages 部署成功

## 四、已知未决项（不阻塞 LTS，但须登记在 Release 说明）

- 供应链：Action 未钉 SHA、Android 签名密码在构建配置（B8-B-06/07）
- 真机节奏类动效（B3/B4/B6–B8/B13/B17/B20/B23）待采集后定档
- 15 处带 actions/bottom 的裸 AppBar 有意保留（OgLAppBar.title 是 String）
- docs/ 历史审计报告内 17 处死链（只读原始记录，不追溯改写）
