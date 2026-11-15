# 05 · Delivery

**分支**：push `video` / `main` / `promo/**` 或 `workflow_dispatch` 触发；仅 `video` 分支成功时自动发布。`workflow_dispatch` 可勾选 `publish_release`。

**Tag**：`promo-<sha7>`，附注 tag 推送到 origin；已存在则复用。

**Release**：与 tag 同名，标题「OGL 片尾 · 2D 电影片尾」，notes 写明 2D 电影片尾 / 18 条里程碑 / 黑体居中上滚 / 零图纯文字 / Dream Aria 25% / 98.746s。

**Artifact**：`ogl-credits-2d-<ref>-<sha>`，保留 30 天；全部文件落在 `promo/final/`。

**文件清单**：`OGL-Credits.mp4`、`OGL-Credits-720p.mp4`、`contact-sheet.jpg`、`OGL-Credits.7z`（内含两个 mp4、联系表、`lint.json`、`check.json` 与 6 份 md：01/02/04/05/06/07；03 留在仓库随源码查阅）、`SHA256SUMS.txt`。

**已知限制**：音轨授权仅限内部样片，不可对外分发或商用；无配音、无字幕旁白；零图，任何视觉信息都由文字承担；成片时长与音轨严格绑定，音轨替换必须同步重算 `v` 与 `PROMO_DURATION`。
