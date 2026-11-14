# OGL 宣传片 · 配乐方案（06-music-plan）

## 采用方向：Clean UI Demo Groove（已由代码合成，无需人工确认方向）

理由：全片是真实界面元素 + 架构/状态数据的连续演示，需要稳定律动托底，而不是大起大落的商业广告鼓点。

| 项 | 值 |
|---|---|
| BPM | 96 |
| 拍长 | 0.625 s |
| 时长 | 56.0 s（89 拍） |
| 和声 | Am – F – C – G，每 4 拍一小节 |
| 编制 | 四踩 kick、2/4 拍 clap、8 分 hat、8 分 bass、失谐 pad、后段 16 分 arp |
| 情绪曲线 | 0–19s 低密度（pad+bass 主导）→ 19–40s 加入 arp 与切分 kick → 40–56s 全编制 + 6 次冲击 |
| 输出 | `assets/audio/bgm.wav` 44.1kHz 16bit 立体声，9.4 MB，峰值 0.89 |

## Hit points（与 EDL 对齐）

| 时间 | 事件 | 画面对应 |
|---|---|---|
| 6.0 / 14.0 / 23.0 / 32.0 / 40.0 / 46.0 | impact（低频 boom + 噪声衰减） | 场景切换 |
| 4.6 / 12.6 / 21.6 / 30.6 / 38.6 / 44.6 | 1.4s riser | 切换前铺垫 |
| 52.0 | 末段 arp 收束 | End card |

## 生成方式

`python3 scripts/make_bgm.py`（numpy 波形合成 + wave 写盘），确定性种子 `20261114`，可重复生成逐字节一致的音轨。同时输出 `bgm-beats.json`，包含完整 beat 网格与转场点。

## 备选方向（未采用，保留作对比）

**Commercial Product Launch**：128 BPM，四踩大鼓 + 铜管式 stab + 明显 drop，3 段情绪爬升，尾段 2s 静音留白给 logo。适合 CTA 更强的投放广告；与本片"连续演示、不硬切"的流畅调性冲突。

## 第三方音乐 prompt（若日后要换真人编曲）

**English prompt**: "96 BPM clean UI demo groove, Am–F–C–G, tight dry kick, crisp 8th-note hats, warm detuned saw pad, muted picked bass, subtle 16th arpeggio entering at 40%, no vocals, no big drops, steady energy for a 56-second software product film, six soft impacts at scene cuts."
**Negative prompt**: "epic trailer, orchestral brass, EDM drop, vocal chops, reverb-heavy ambient wash, tempo changes, swing".

> 本次未调用任何在线音乐生成服务，也未消耗生成额度。
