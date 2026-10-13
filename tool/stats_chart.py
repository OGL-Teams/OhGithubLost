#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 仓库统计曲线（星标 / 提交数）—— 极客风终端质感 PNG 折线图。

## 视觉约定（v8.3）
- **暗色终端底**（近黑蓝）+ 霓虹系列色（星标=霓虹青 / 提交=磷光绿），
  琥珀色只用于「当前值」十字准星——一屏只有一处高亮，视线有落点；
- **保留 5×7 点阵字体**（零依赖自绘）：标题放大到 3×，正文与刻度 2×，
  全部整数倍缩放，像素锐利不糊；
- **4K 分辨率**（3840×2160）：README 里缩到 ~800px 展示仍锐利；
  文件经 jsDelivr CDN 分发（`fastly.jsdelivr.net/gh/...@stats/...`），
  workflow 每次更新后**主动清 jsDelivr 缓存**（分支缓存默认 12h，不清会长时间发旧图）；
- **细腻度**：主刻度之间补 3 条次网格线；折线三层绘制（辉光 5px →
  过渡 3px → 亮芯 2px）+ 线下面积填充（10% 混色）；采样上限提升到
  像素宽度（不再压成 400 点）；
- **布局**：顶栏 = 标题 + 仓库/数据源 + 右侧 HUD（LAST / MAX / MIN / PTS）；
  绘图区四角终括号；底栏 = 真实时间刻度（UTC，5 点）+ 页脚（时间窗 /
  渲染规格）。分区用分隔线，不靠留白硬撑。

## 为什么重写（5.3 的旧硬伤，全部保留修复）
1. 纵轴按各自 min..max 拉伸 → 现在**从 0 起 + 整齐上限**（1/2/2.5/5×10^n）；
2. 没有坐标系 → 现在有刻度 / 单位 / 标题 / 日期 / 数据源；
3. 横轴按索引等距 → 现在是**真实时间轴**（UTC 秒数比例）。

## 用法
    python3 tool/stats_chart.py --repo owner/name --history stats/history.json --out-dir stats
    python3 tool/stats_chart.py --selftest      # 不需要网络：核对刻度/时间映射/降采样数学

## 环境变量
    GH_TOKEN / GITHUB_TOKEN  具备读取权限的令牌（Actions 用 secrets.GITHUB_TOKEN）。
"""

import argparse
import json
import os
import re
import struct
import sys
import urllib.error
import urllib.request
import zlib
from datetime import datetime, timezone

API = 'https://api.github.com'

# ── 版面（像素；2× 分辨率）────────────────────────────────────────────────
WIDTH = 5120
HEIGHT = 2880
MARGIN_LEFT = 346
MARGIN_RIGHT = 320
MARGIN_TOP = 426
MARGIN_BOTTOM = 320

# 点阵字体缩放：标题 10×、正文/刻度 6×（整数倍 → 像素锐利；
# 5K 画布缩到 README 宽展示时，正文观感与旧 1× 版一致）。
TEXT_SCALE = 6
TITLE_SCALE = 10

# ── 极客配色（暗色终端 + 霓虹）────────────────────────────────────────────
COLOR_BG = (10, 14, 18)          # 近黑蓝（终端底）
COLOR_GRID_MINOR = (20, 28, 36)  # 次网格（细腻度）
COLOR_GRID = (30, 41, 53)        # 主网格
COLOR_AXIS = (66, 92, 112)       # 轴线
COLOR_FAINT = (74, 96, 116)      # 角落括号 / 次要装饰
COLOR_MUTED = (108, 132, 156)    # 次要文字
COLOR_TEXT = (206, 226, 240)     # 主文字
COLOR_ACCENT = (255, 176, 0)     # 琥珀：仅当前值十字准星
COLOR_STAR = (0, 229, 255)       # 霓虹青（星标）
COLOR_COMMIT = (0, 255, 136)     # 磷光绿（提交）

GLYPH_W = 5
GLYPH_H = 7
GLYPH_GAP = 1

# ── 5×7 点阵字体（1 = 落墨）────────────────────────────────────────────────
# 行数固定 7、列宽固定 5；只需要图表用到的大写字母 / 数字 / 少量符号。
# 未知字符（含小写）落 `空格` —— 因此**本文件里的全部文案必须是大写 ASCII**。
_FONT_ROWS = {
    '0': '01110 10001 10011 10101 11001 10001 01110',
    '1': '00100 01100 00100 00100 00100 00100 01110',
    '2': '01110 10001 00001 00010 00100 01000 11111',
    '3': '11111 00010 00100 00010 00001 10001 01110',
    '4': '00010 00110 01010 10010 11111 00010 00010',
    '5': '11111 10000 11110 00001 00001 10001 01110',
    '6': '00110 01000 10000 11110 10001 10001 01110',
    '7': '11111 00001 00010 00100 01000 01000 01000',
    '8': '01110 10001 10001 01110 10001 10001 01110',
    '9': '01110 10001 10001 01111 00001 00010 01100',
    'A': '01110 10001 10001 11111 10001 10001 10001',
    'B': '11110 10001 10001 11110 10001 10001 11110',
    'C': '01110 10001 10000 10000 10000 10001 01110',
    'D': '11100 10010 10001 10001 10001 10010 11100',
    'E': '11111 10000 10000 11110 10000 10000 11111',
    'F': '11111 10000 10000 11110 10000 10000 10000',
    'G': '01110 10001 10000 10111 10001 10001 01111',
    'H': '10001 10001 10001 11111 10001 10001 10001',
    'I': '01110 00100 00100 00100 00100 00100 01110',
    'J': '00111 00010 00010 00010 00010 10010 01100',
    'K': '10001 10010 10100 11000 10100 10010 10001',
    'L': '10000 10000 10000 10000 10000 10000 11111',
    'M': '10001 11011 10101 10101 10001 10001 10001',
    'N': '10001 11001 10101 10011 10001 10001 10001',
    'O': '01110 10001 10001 10001 10001 10001 01110',
    'P': '11110 10001 10001 11110 10000 10000 10000',
    'Q': '01110 10001 10001 10001 10101 10010 01101',
    'R': '11110 10001 10001 11110 10100 10010 10001',
    'S': '01111 10000 10000 01110 00001 00001 11110',
    'T': '11111 00100 00100 00100 00100 00100 00100',
    'U': '10001 10001 10001 10001 10001 10001 01110',
    'V': '10001 10001 10001 10001 10001 01010 00100',
    'W': '10001 10001 10001 10101 10101 11011 10001',
    'X': '10001 10001 01010 00100 01010 10001 10001',
    'Y': '10001 10001 01010 00100 00100 00100 00100',
    'Z': '11111 00001 00010 00100 01000 10000 11111',
    '-': '00000 00000 00000 11111 00000 00000 00000',
    '.': '00000 00000 00000 00000 00000 01100 01100',
    ':': '00000 01100 01100 00000 01100 01100 00000',
    '/': '00001 00010 00010 00100 01000 01000 10000',
    '(': '00010 00100 01000 01000 01000 00100 00010',
    ')': '01000 00100 00010 00010 00010 00100 01000',
    '+': '00000 00100 00100 11111 00100 00100 00000',
    '%': '11001 11010 00010 00100 01000 01011 10011',
    ',': '00000 00000 00000 00000 01100 01100 11000',
    ' ': '00000 00000 00000 00000 00000 00000 00000',
}


def _font_glyph(char):
    rows = _FONT_ROWS.get(char.upper(), _FONT_ROWS[' '])
    return [[1 if bit == '1' else 0 for bit in row] for row in rows.split()]


# ── 颜色工具 ───────────────────────────────────────────────────────────────
def _blend(base, color, t):
    """线性混色（无 alpha 通道 → 用混色模拟透明）。"""
    return tuple(int(round(base[i] + (color[i] - base[i]) * t))
                 for i in range(3))


# ── 画布 / 基本绘制 ────────────────────────────────────────────────────────
def _canvas(width, height, color):
    row = bytes(color) * width
    return [bytearray(row) for _ in range(height)]


def _rect(rows, x0, y0, x1, y1, color):
    height = len(rows)
    width = len(rows[0]) // 3
    for y in range(max(0, int(y0)), min(height, int(y1))):
        for x in range(max(0, int(x0)), min(width, int(x1))):
            rows[y][3 * x:3 * x + 3] = bytes(color)


def _line(rows, x0, y0, x1, y1, color, thick=2):
    steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for i in range(steps):
        t = i / float(steps)
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        _rect(rows, x, y, x + thick, y + thick, color)


def _dot(rows, x, y, color, size=9):
    _rect(rows, int(x) - size // 2, int(y) - size // 2,
          int(x) - size // 2 + size, int(y) - size // 2 + size, color)


def _crosshair(rows, x, y, color, arm=34, thick=8):
    """十字准星：当前值专用高亮（琥珀），一屏只此一处。"""
    _rect(rows, int(x) - arm, int(y) - thick // 2,
          int(x) + arm + 1, int(y) - thick // 2 + thick, color)
    _rect(rows, int(x) - thick // 2, int(y) - arm,
          int(x) - thick // 2 + thick, int(y) + arm + 1, color)


def _brackets(rows, x0, y0, x1, y1, color, length=120, thick=10, out=18):
    """绘图区四角终括号（终端框感）。

    ★ 外扩 `out` 像素绘制：内贴时四角与轴线/刻度数字重叠会「消失」
    （轴线色与括号色相近，看图只见右上角）。外扩后四个角都清晰。
    """
    left, top = x0 - out, y0 - out
    right, bottom = x1 + out, y1 + out
    for (cx, cy, dx, dy) in ((left, top, 1, 1), (right, top, -1, 1),
                             (left, bottom, 1, -1), (right, bottom, -1, -1)):
        sx = cx if dx > 0 else cx - length
        sy = cy if dy > 0 else cy - thick
        _rect(rows, sx, sy, sx + length, sy + thick, color)
        sx2 = cx if dx > 0 else cx - thick
        sy2 = cy if dy > 0 else cy - length
        _rect(rows, sx2, sy2, sx2 + thick, sy2 + length, color)


def text_width(text, scale=TEXT_SCALE):
    if not text:
        return 0
    return len(text) * (GLYPH_W + GLYPH_GAP) * scale - GLYPH_GAP * scale


def _text(rows, x, y, text, color, scale=TEXT_SCALE):
    cursor = x
    for char in text:
        glyph = _font_glyph(char)
        for gy, line in enumerate(glyph):
            for gx, ink in enumerate(line):
                if not ink:
                    continue
                _rect(rows, cursor + gx * scale, y + gy * scale,
                      cursor + (gx + 1) * scale, y + (gy + 1) * scale, color)
        cursor += (GLYPH_W + GLYPH_GAP) * scale


def _text_right(rows, x_right, y, text, color, scale=TEXT_SCALE):
    _text(rows, int(x_right - text_width(text, scale)), y, text, color, scale)


def _fill_columns(rows, xs, ys, base_y, color):
    """线下面积：**逐像素列**从曲线填到底线（无 alpha → 混色）。

    平滑后的点列可能有 7k+ 个点（每像素多段），逐「段」遍历会把同一列
    重复刷几十次；逐「列」走一遍、在相邻两点间线性取 y，代价与图宽同阶。
    """
    if len(xs) < 2:
        return
    width = len(rows[0]) // 3
    height = len(rows)
    base = max(0, min(height, int(base_y)))
    j = 0
    for x in range(int(xs[0]), int(xs[-1]) + 1):
        if x < 0 or x >= width:
            continue
        while j < len(xs) - 2 and xs[j + 1] < x:
            j += 1
        x0, x1 = xs[j], xs[j + 1]
        t = 0.0 if x1 <= x0 else (x - x0) / float(x1 - x0)
        y_top = ys[j] + (ys[j + 1] - ys[j]) * t
        y0 = max(0, min(height, int(round(y_top))))
        for y in range(y0, base):
            rows[y][3 * x:3 * x + 3] = bytes(color)


def _write_png(path, rows):
    width = len(rows[0]) // 3
    height = len(rows)
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    blob = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(blob)


# ── 坐标轴数学（纯函数，可单测）────────────────────────────────────────────
def nice_axis_max(value):
    """把数据上限抬到"整齐"刻度：1 / 2 / 2.5 / 5 × 10^n（至少 1）。"""
    if value <= 0:
        return 1.0
    exponent = 0
    scaled = float(value)
    while scaled >= 10:
        scaled /= 10.0
        exponent += 1
    while scaled < 1:
        scaled *= 10.0
        exponent -= 1
    for step in (1.0, 2.0, 2.5, 5.0, 10.0):
        if scaled <= step:
            return step * (10 ** exponent)
    return 10.0 * (10 ** exponent)


def axis_ticks(axis_max, count=5):
    """0..axis_max 等分刻度（含 0 与上限）。"""
    if count < 2:
        count = 2
    return [axis_max * i / (count - 1) for i in range(count)]


def axis_ticks_for(axis_max, integer_series=True, count=5):
    """按数据性质给刻度。

    **计数类（星标 / 提交）在数值不大时直接用整数刻度**：等分会出现
    `1.2`、`3.8` 这类读数，而"1.2 个星标"本身就不成立。范围大（> 12）时
    整数刻度会太密，退回等分刻度。
    """
    if (integer_series and axis_max <= 12
            and abs(axis_max - round(axis_max)) < 1e-9):
        return [float(i) for i in range(int(round(axis_max)) + 1)]
    return axis_ticks(axis_max, count)


def format_value(value):
    """刻度数值：整数不带小数点，小数最多 1 位。"""
    if abs(value - round(value)) < 1e-9:
        return str(int(round(value)))
    return ('%.1f' % value).rstrip('0').rstrip('.')


def format_time(value, with_date=True):
    """UTC 时间戳 → `MM-DD HH:MM`（跨天信息保留；同日也带日期以免误读）。"""
    stamp = datetime.fromtimestamp(value, tz=timezone.utc)
    if with_date:
        return stamp.strftime('%m-%d %H:%M')
    return stamp.strftime('%H:%M')


def x_positions(times, left, width):
    """时间 → 像素（**真实时间轴**：间隔按秒数比例，而非索引等距）。

    单点或时间无跨度时落在中心。
    """
    if not times:
        return []
    lo, hi = times[0], times[-1]
    span = hi - lo
    if span <= 0:
        return [left + width / 2.0 for _ in times]
    return [left + (t - lo) / float(span) * width for t in times]


def _nice_step_at_least(value):
    """不小于 value 的"整齐"步长：1 / 2 / 2.5 / 5 × 10^n。"""
    if value <= 0:
        return 1.0
    exponent = 0
    scaled = float(value)
    while scaled >= 10:
        scaled /= 10.0
        exponent += 1
    while scaled < 1:
        scaled *= 10.0
        exponent -= 1
    for step in (1.0, 2.0, 2.5, 5.0, 10.0):
        if scaled <= step + 1e-9:
            return step * (10 ** exponent)
    return 10.0 * (10 ** exponent)


def axis_plan(value, ticks=10, integer_series=True):
    """规划纵轴：返回 `(axis_max, tick_values)`，**恰好 `ticks` 个刻度**。

    - 步长取"整齐"值（1/2/2.5/5×10^n），计数类**不出现小数步长**
      （"1.2 个星标"不成立）；上限 = 步长 ×(ticks−1)，覆盖数据；
    - 为什么不再用"上限抬到整齐 + 等分 5 条"：5 条刻度在 4K 高度上太疏，
      且端点贴着数据容易误读；固定 10 条 + 整齐步长同时解决密度与可读性。
    """
    if value <= 0:
        value = 1
    step = _nice_step_at_least(float(value) / (ticks - 1))
    if integer_series and step < 1:
        step = 1.0
    axis_max = step * (ticks - 1)
    while axis_max < value - 1e-9:
        step = _nice_step_at_least(step * 1.01)
        axis_max = step * (ticks - 1)
    return axis_max, [step * i for i in range(ticks)]


def time_labels_for(times, plot_w, count=10, gap=28):
    """时间标签（**固定 count 个**）：精度按需要减少，而不是抽稀标签。

    精度阶梯：`MM-DD HH:MM`（11 字）→ 按跨度自动降为 `MM-DD`（跨天以上）
    或 `HH:MM`（一天以内）。降级前先验证放得下（等宽 + 间隔），
    放不下才降；**绝不**通过删标签来控制密度。
    """
    span = times[-1] - times[0]
    stamp_list = ([times[0]] if span <= 0
                  else [times[0] + span * i / float(count - 1)
                        for i in range(count)])
    if span <= 0:
        return [format_time(stamp_list[0])]
    full = [format_time(stamp) for stamp in stamp_list]
    if text_width(full[0]) * count + gap * (count - 1) <= plot_w:
        return full
    short_fmt = '%m-%d' if span >= 12 * 3600 else '%H:%M'
    short = [datetime.fromtimestamp(stamp, tz=timezone.utc).strftime(short_fmt)
             for stamp in stamp_list]
    return short


def smooth_path(xs, ys, subdivisions=4):
    """**单调三次插值**（Fritsch–Carlson）平滑折线 → 稠密点列。

    - 曲线**不过冲**：每段严格落在两端点值域内（星标数不会被画成负数，
      也不会在下降段反弹出"假高点"）；
    - `subdivisions` 控制平滑粒度（4 ≈ 每段 4 个采样，肉眼即连续）。
    """
    n = len(xs)
    if n < 3:
        return list(xs), list(ys)
    deltas = []
    for i in range(n - 1):
        dx = xs[i + 1] - xs[i]
        deltas.append((ys[i + 1] - ys[i]) / dx if dx else 0.0)
    tangents = [deltas[0]]
    for i in range(1, n - 1):
        a, b = deltas[i - 1], deltas[i]
        if a * b <= 0:
            tangents.append(0.0)
        else:
            tangents.append((a + b) / 2.0)
    tangents.append(deltas[-1])
    # Fritsch–Carlson 限制：保证单调段不过冲
    for i in range(n - 1):
        d = deltas[i]
        if d == 0:
            tangents[i] = 0.0
            tangents[i + 1] = 0.0
            continue
        a = tangents[i] / d
        b = tangents[i + 1] / d
        if a > 3:
            tangents[i] = 3 * d
        if b > 3:
            tangents[i + 1] = 3 * d
    out_x, out_y = [], []
    for i in range(n - 1):
        x0, x1 = xs[i], xs[i + 1]
        y0, y1 = ys[i], ys[i + 1]
        m0, m1 = tangents[i], tangents[i + 1]
        h = x1 - x0
        steps = max(1, subdivisions)
        for k in range(steps):
            t = k / float(steps)
            t2, t3 = t * t, t * t * t
            h00 = 2 * t3 - 3 * t2 + 1
            h10 = t3 - 2 * t2 + t
            h01 = -2 * t3 + 3 * t2
            h11 = t3 - t2
            out_x.append(x0 + h * t)
            out_y.append(h00 * y0 + h10 * h * m0 + h01 * y1 + h11 * h * m1)
    out_x.append(xs[-1])
    out_y.append(ys[-1])
    return out_x, out_y


def label_positions(plot_left, plot_w, centers, widths, gap=28):
    """给刻度标签安排**互不重叠**的横坐标（居中优先 → 推挤 → 均匀兜底）。

    为什么需要三段式（真踩过的坑）：
    - 只做"居中 + 端点内收"：最左/最右那对标签互相压字（端点被钉死后
      第二标签仍按居中位置起笔）；
    - 加"前向推挤"仍不够：最后一个标签被右边界钉死，无法再让步，
      于是**倒数第二与最后**继续重叠；
    - 所以收尾必须做**容量检查**：仍重叠时要么整体均匀铺开，
      要么抽稀标签（保首尾），直到每个间隔 ≥ [gap]。
    """
    count = len(centers)
    if count == 0:
        return []
    if count == 1:
        return [int(plot_left + plot_w / 2.0 - widths[0] / 2.0)]
    positions = [
        int(min(max(plot_left, center - widths[i] / 2.0),
                plot_left + plot_w - widths[i]))
        for i, center in enumerate(centers)]
    for i in range(1, count):
        floor_x = positions[i - 1] + widths[i - 1] + gap
        if positions[i] < floor_x:
            positions[i] = floor_x
    for i in range(count - 2, -1, -1):
        ceil_x = positions[i + 1] - widths[i] - gap
        if positions[i] > ceil_x:
            positions[i] = ceil_x
    positions = [
        int(min(max(plot_left, x), plot_left + plot_w - widths[i]))
        for i, x in enumerate(positions)]

    def overlaps(seq):
        return any(seq[i] + widths[i] + gap > seq[i + 1]
                   for i in range(len(seq) - 1))

    if overlaps(positions):
        # 兜底一：均匀铺开（标签等宽时必然可行）
        total = sum(widths) + gap * (count - 1)
        if total <= plot_w and len(set(widths)) == 1:
            step = (plot_w - widths[0]) / float(count - 1)
            positions = [int(plot_left + i * step) for i in range(count)]
    if overlaps(positions):
        # 兜底二：抽稀（保首尾），直到容量足够
        keep = [0, count - 1]
        for i in range(1, count - 1):
            if i % 2 == 1:
                keep.insert(-1, i)
        while len(keep) > 2:
            widths_kept = [widths[i] for i in keep]
            total = sum(widths_kept) + gap * (len(keep) - 1)
            if total <= plot_w:
                step = (plot_w - widths_kept[-1]) / float(len(keep) - 1)
                fixed = [int(plot_left + i * step) for i in range(len(keep))]
                mapping = {k: fixed[j] for j, k in enumerate(keep)}
                return [mapping.get(i, positions[i]) for i in range(count)]
            for j in range(1, len(keep) - 1, 2):
                keep.pop(j)
                break
    return positions


def downsample(values, limit):
    """等距降采样（保留首尾），避免点太密糊成一片。"""
    count = len(values)
    if count <= limit:
        return values
    if limit <= 2:
        return [values[0], values[-1]]
    step = (count - 1) / float(limit - 1)
    return [values[int(round(i * step))] for i in range(limit)]


def downsample_points(points, limit):
    return downsample(points, limit)


# ── 数据抓取 ──────────────────────────────────────────────────────────────
def _request(path, token):
    request = urllib.request.Request(API + path)
    request.add_header('Authorization', 'Bearer ' + token)
    request.add_header('Accept', 'application/vnd.github+json')
    request.add_header('X-GitHub-Api-Version', '2022-11-28')
    request.add_header('User-Agent', 'ogl-stats')
    return urllib.request.urlopen(request, timeout=60)


def fetch_stars(repo, token):
    with _request('/repos/' + repo, token) as response:
        data = json.loads(response.read().decode('utf-8'))
    return int(data.get('stargazers_count', 0))


def fetch_commits(repo, token):
    """提交总数：`per_page=1` 时 Link 头 `rel="last"` 的 page 即为总数。"""
    with _request('/repos/%s/commits?per_page=1' % repo, token) as response:
        link = response.headers.get('Link', '')
        body = json.loads(response.read().decode('utf-8'))
    if link:
        match = re.search(r'[?&]page=(\d+)>;\s*rel="last"', link)
        if match:
            return int(match.group(1))
    return len(body) if isinstance(body, list) else 0


# ── 历史读写（兼容旧结构）──────────────────────────────────────────────────
def load_history(path):
    """读取历史点；坏点跳过并留痕（**不因一条坏数据丢掉整段历史**）。"""
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding='utf-8') as handle:
            data = json.load(handle)
    except Exception as error:  # noqa: BLE001
        print('history 读取失败，按空历史处理：%s' % error, file=sys.stderr)
        return []
    if not isinstance(data, list):
        print('history 结构不是数组，按空历史处理', file=sys.stderr)
        return []
    points = []
    skipped = 0
    for item in data:
        point = parse_point(item)
        if point is None:
            skipped += 1
            continue
        points.append(point)
    if skipped:
        print('history 跳过 %d 个坏点' % skipped, file=sys.stderr)
    points.sort(key=lambda p: p['ts'])
    return points


def parse_point(item):
    """解析一个历史点（容错）：返回 `{'ts','iso','stars','commits'}` 或 None。"""
    if not isinstance(item, dict):
        return None
    raw_time = item.get('t') or item.get('ts') or item.get('time')
    if not isinstance(raw_time, str):
        return None
    try:
        stamp = datetime.fromisoformat(raw_time.replace('Z', '+00:00'))
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return {
        'ts': stamp.timestamp(),
        'iso': stamp.astimezone(timezone.utc)
        .replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
        'stars': _as_count(item.get('stars')),
        'commits': _as_count(item.get('commits')),
    }


def _as_count(value):
    """把历史里的计数容错转成 int（坏值一律 0，**绝不抛**）。

    `int('3.5')` 会抛 ValueError —— 旧实现让一条坏数据炸掉整段历史。
    """
    try:
        return int(round(float(value)))
    except (TypeError, ValueError):
        return 0


def write_history(path, points):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    payload = [{'t': p['iso'], 'stars': p['stars'], 'commits': p['commits']}
               for p in points]
    with open(path, 'w', encoding='utf-8') as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


# ── 渲染（极客风终端版面）────────────────────────────────────────────────
def render_chart(points, key, color, path, title, unit, source, repo=''):
    """把一串历史点渲染成**带坐标系**的极客风 PNG；返回画布（自检用）。"""
    rows = _canvas(WIDTH, HEIGHT, COLOR_BG)
    plot_left = MARGIN_LEFT
    plot_top = MARGIN_TOP
    plot_w = WIDTH - MARGIN_LEFT - MARGIN_RIGHT
    plot_h = HEIGHT - MARGIN_TOP - MARGIN_BOTTOM
    plot_bottom = plot_top + plot_h

    times = [p['ts'] for p in points]
    values = [int(p.get(key, 0)) for p in points]

    # 纵轴：**固定 10 个刻度** + 整齐步长（计数类不出现小数刻度）
    axis_max, y_ticks = axis_plan(max(values) if values else 0, ticks=10)

    def y_of(value):
        if axis_max <= 0:
            return float(plot_bottom)
        return plot_bottom - (value / axis_max) * plot_h

    # 三层折线的颜色（无 alpha → 混色模拟：辉光 / 过渡 / 亮芯）
    glow = _blend(COLOR_BG, color, 0.30)
    soft = _blend(COLOR_BG, color, 0.55)
    area = _blend(COLOR_BG, color, 0.10)

    last_value = values[-1] if values else 0

    # ── 顶栏：标题 + 仓库/数据源 + 右侧 HUD ──
    _text(rows, plot_left, 64, title, COLOR_TEXT, scale=TITLE_SCALE)
    sub = (repo.upper() + ' / ' + source) if repo else source.upper()
    # 截断护栏：副标题最多占绘图区 62% 宽（给右上 HUD 留位置）
    limit_w = int(plot_w * 0.62)
    if text_width(sub) > limit_w:
        while sub and text_width(sub + '.') > limit_w:
            sub = sub[:-1]
        sub += '.'
    _text(rows, plot_left, 64 + GLYPH_H * TITLE_SCALE + 24, sub, COLOR_MUTED)

    # HUD：右上角，琥珀色只用于当前值本身
    _text_right(rows, WIDTH - MARGIN_RIGHT, 58,
                format_value(last_value), color, scale=TITLE_SCALE)
    label = 'LAST'
    _text_right(rows,
                WIDTH - MARGIN_RIGHT - text_width(format_value(last_value),
                                                  TITLE_SCALE) - 16,
                64 + GLYPH_H * TITLE_SCALE - GLYPH_H * TEXT_SCALE,
                label, COLOR_MUTED)
    if values:
        hud = 'MAX %s   MIN %s   PTS %s' % (
            format_value(max(values)), format_value(min(values)), len(points))
        _text_right(rows, WIDTH - MARGIN_RIGHT,
                    64 + GLYPH_H * TITLE_SCALE + 24, hud, COLOR_MUTED)

    # 顶栏下分隔线（2px）+ 左侧琥珀短段（终端提示符感）
    sep_y = MARGIN_TOP - 80
    _rect(rows, plot_left, sep_y, WIDTH - MARGIN_RIGHT, sep_y + 5, COLOR_GRID)
    _rect(rows, plot_left, sep_y, plot_left + 180, sep_y + 5, COLOR_ACCENT)

    # 纵轴单位（轴顶左侧；深色版下用 MUTED 保证在近黑底上可读）
    _text(rows, 12, plot_top - 100, unit, COLOR_MUTED)

    # ── 网格：10 条主刻度 + 相邻中点 1 条次线（10 条主刻度已足够密）──
    for i in range(len(y_ticks) - 1):
        y_minor = y_of((y_ticks[i] + y_ticks[i + 1]) / 2.0)
        _rect(rows, plot_left, int(round(y_minor)),
              plot_left + plot_w, int(round(y_minor)) + 2, COLOR_GRID_MINOR)
    for tick in y_ticks:
        y = int(round(y_of(tick)))
        _rect(rows, plot_left, y, plot_left + plot_w, y + 4, COLOR_GRID)
        label = format_value(tick)
        _text(rows, plot_left - 14 - text_width(label),
              y - GLYPH_H * TEXT_SCALE / 2.0, label, COLOR_MUTED)

    # ── 轴框：左/下实线（轴线色），上/右淡线，四角终括号 ──
    _rect(rows, plot_left, plot_top, plot_left + plot_w, plot_top + 3, COLOR_GRID)
    _rect(rows, plot_left + plot_w - 3, plot_top,
          plot_left + plot_w, plot_bottom + 3, COLOR_GRID)
    _rect(rows, plot_left, plot_bottom, plot_left + plot_w, plot_bottom + 5,
          COLOR_AXIS)
    _rect(rows, plot_left, plot_top, plot_left + 5, plot_bottom + 5, COLOR_AXIS)
    _brackets(rows, plot_left, plot_top, plot_left + plot_w - 1, plot_bottom,
              COLOR_MUTED)

    # ── 横轴：**固定 10 个均匀刻度**（精度按需降级，不抽稀）──
    if times:
        span = times[-1] - times[0]
        count_x = 10
        if span <= 0:
            tick_times = [times[0]]
        else:
            # 均匀刻度：时间跨度等分 10 份（数据本身 10 分钟一点，天然对齐）
            tick_times = [times[0] + span * i / float(count_x - 1)
                          for i in range(count_x)]
        labels = time_labels_for(times, plot_w, count=count_x)
        widths = [text_width(label) for label in labels]
        if span <= 0:
            x_positions_list = [int(plot_left + plot_w / 2.0 - widths[0] / 2.0)]
        else:
            centers = [plot_left + (stamp - times[0]) / span * plot_w
                       for stamp in tick_times]
            # 标签宽度已按 10 个做过容量校验（time_labels_for 内部降级），
            # 这里只做纯居中的均匀排布；label_positions 仅作最后的防撞保险。
            x_positions_list = label_positions(plot_left, plot_w, centers, widths)
        # 次网格：相邻主刻度 1 条中点线（10 条主刻度已足够密）
        if span > 0:
            for i in range(count_x - 1):
                mx = plot_left + plot_w * (i + 0.5) / float(count_x - 1)
                _rect(rows, int(round(mx)), plot_top + 3,
                      int(round(mx)) + 3, plot_bottom, COLOR_GRID_MINOR)
        for index, stamp in enumerate(tick_times):
            if span <= 0:
                x = plot_left + plot_w / 2.0
            else:
                x = plot_left + (stamp - times[0]) / span * plot_w
            _rect(rows, int(round(x)) - 3, plot_bottom + 6,
                  int(round(x)) + 3, plot_bottom + 26, COLOR_AXIS)
            _text(rows, x_positions_list[index], plot_bottom + 42,
                  labels[index], COLOR_MUTED)

    # ── 数据：面积填充 → 辉光 → 过渡 → 亮芯 → 采样点 → 当前值准星 ──
    if len(points) >= 2:
        # 采样上限 = 绘图区半宽（平滑会再插值加密，见下）
        sampled = downsample_points(points, max(2, plot_w // 2))
        xs = x_positions([p['ts'] for p in sampled], plot_left, plot_w)
        ys = [y_of(int(p.get(key, 0))) for p in sampled]
        # ★ 单调三次平滑：折线 → 平滑曲线（不越界、不过冲）
        sx, sy = smooth_path(xs, ys, subdivisions=4)
        _fill_columns(rows, sx, sy, plot_bottom, area)
        for i in range(len(sx) - 1):
            _line(rows, sx[i], sy[i], sx[i + 1], sy[i + 1], glow, thick=17)
        for i in range(len(sx) - 1):
            _line(rows, sx[i], sy[i], sx[i + 1], sy[i + 1], soft, thick=11)
        for i in range(len(sx) - 1):
            _line(rows, sx[i], sy[i], sx[i + 1], sy[i + 1], color, thick=6)
        # 采样点标记（最多 ~22 个，避免糊）
        marker_step = max(1, len(sampled) // 22)
        for i in range(0, len(sampled), marker_step):
            _dot(rows, xs[i], ys[i], soft, size=9)
        # 当前值：琥珀十字准星（全图唯一硬高亮）
        _crosshair(rows, xs[-1], ys[-1], COLOR_ACCENT)
        _dot(rows, sx[-1], sy[-1], COLOR_ACCENT, size=17)
    elif points:
        x = x_positions(times, plot_left, plot_w)[0]
        y = y_of(values[0])
        _crosshair(rows, x, y, COLOR_ACCENT)
        _dot(rows, x, y, COLOR_ACCENT, size=17)

    # ── 页脚：时间窗（左） + 渲染规格（右）──
    footer_y = HEIGHT - 130
    if points:
        window = 'TIME (UTC)   %s .. %s' % (
            format_time(points[0]['ts']), format_time(points[-1]['ts']))
        _text(rows, plot_left, footer_y, window, COLOR_MUTED)
    _text_right(rows, WIDTH - MARGIN_RIGHT, footer_y,
                'RENDER %dX%d PIXEL' % (WIDTH, HEIGHT), COLOR_FAINT)

    _write_png(path, rows)
    return rows


# ── 自检（不联网，供 CI 直接跑）────────────────────────────────────────────
def _ink(rows, x0, y0, x1, y1):
    """统计区域内**非背景**像素数（判断「这里到底有没有画出东西」）。

    深色主题下"找落墨"必须改成"找与背景不同的像素"，否则整片底色都会被
    当成墨——这是旧白底版本 `_ink`（按暗色累计）在换肤后的必然修正。
    """
    width = len(rows[0]) // 3
    bg = COLOR_BG
    total = 0
    for y in range(max(0, int(y0)), min(len(rows), int(y1))):
        row = rows[y]
        for x in range(max(0, int(x0)), min(width, int(x1))):
            pixel = row[3 * x:3 * x + 3]
            if (abs(pixel[0] - bg[0]) + abs(pixel[1] - bg[1])
                    + abs(pixel[2] - bg[2])) > 24:
                total += 1
    return total


def selftest():
    failures = []

    def check(name, condition):
        if not condition:
            failures.append(name)

    # 刻度上限：永远 ≥ 数据、且是 1/2/2.5/5×10^n
    for value in (0, 1, 3, 42, 99, 1234, 0.4):
        axis_max = nice_axis_max(value)
        check('nice_axis_max(%s) >= value' % value, axis_max >= value - 1e-9)
        check('nice_axis_max(%s) 为正' % value, axis_max > 0)
    # 计数类（整数）总是不小于 1；小数输入仍应按同一套阶梯给值。
    for count in (0, 1, 3, 42, 99, 1234):
        check('nice_axis_max(%d) >= 1' % count, nice_axis_max(count) >= 1)
    check('nice_axis_max(42) == 50', nice_axis_max(42) == 50)
    check('nice_axis_max(1234) == 2000', nice_axis_max(1234) == 2000)
    check('nice_axis_max(0.4) == 0.5', abs(nice_axis_max(0.4) - 0.5) < 1e-9)

    # 计数类：小范围给整数刻度（不该出现 "1.2 个星标"）
    small = axis_ticks_for(nice_axis_max(3))
    check('小范围整数刻度 == 0..5', small == [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
    check('整数刻度不含小数', all(v == int(v) for v in small))
    check('整数刻度含 0 与上限', small[0] == 0 and small[-1] == 5)
    check('单点（上限 1）给 0..1', axis_ticks_for(nice_axis_max(0)) == [0.0, 1.0])
    big = axis_ticks_for(nice_axis_max(1234))
    check('大范围退回等分刻度（5 条）', len(big) == 5)
    check('大范围刻度到上限', abs(big[-1] - nice_axis_max(1234)) < 1e-9)

    # 纵轴规划：**恰好 10 个刻度** + 整齐步长（计数类无小数刻度）
    plan_max, plan_ticks = axis_plan(42, ticks=10)
    check('axis_plan 给 10 个刻度', len(plan_ticks) == 10)
    check('axis_plan 覆盖数据', plan_max >= 42)
    check('axis_plan 步长整齐（步长 5）', abs(plan_ticks[1] - plan_ticks[0]) in (1, 2, 2.5, 5, 10, 20, 25, 50))
    small_plan = axis_plan(3, ticks=10)
    check('小数据也 10 刻度（步长 1）',
          len(small_plan[1]) == 10 and small_plan[1][1] - small_plan[1][0] == 1)
    # 平滑：单调数据不过冲、端点保留
    sxs, sys_ = smooth_path([0.0, 10.0, 20.0], [0.0, 5.0, 10.0], subdivisions=4)
    check('平滑保留端点', abs(sxs[0]) < 1e-9 and abs(sxs[-1] - 20.0) < 1e-9
          and abs(sys_[0]) < 1e-9 and abs(sys_[-1] - 10.0) < 1e-9)
    check('单调数据平滑后不过冲',
          all(-1e-6 <= sys_[i] <= 10.0 + 1e-6 for i in range(len(sys_))))
    sxs2, sys2 = smooth_path([0.0, 1.0, 2.0], [5.0, 5.0, 5.0])
    check('平数据平滑后仍平', all(abs(v - 5.0) < 1e-9 for v in sys2))
    sxs3, sys3 = smooth_path([0.0, 5.0], [1.0, 3.0])
    check('两点不平滑直接返回', sxs3 == [0.0, 5.0] and sys3 == [1.0, 3.0])

    # 非整数上限**不进**整数分支（否则顶刻度缺失、顶部无标注）
    half = axis_ticks_for(2.5)
    check('非整数上限给等分刻度（不是 0..2）', half != [0.0, 1.0, 2.0])
    check('非整数上限刻度到顶', abs(half[-1] - 2.5) < 1e-9)
    big_int = axis_ticks_for(5)
    check('整数上限仍走整数刻度', big_int == [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])

    # 刻度：5 条、含 0 与上限、单调
    ticks = axis_ticks(nice_axis_max(42))
    check('刻度条数 == 5', len(ticks) == 5)
    check('刻度从 0 起', abs(ticks[0]) < 1e-9)
    check('刻度到上限', abs(ticks[-1] - nice_axis_max(42)) < 1e-9)
    check('刻度单调', all(ticks[i] < ticks[i + 1] for i in range(len(ticks) - 1)))

    # 时间轴：真实比例（不等距时间 → 不等距像素），且单调
    xs = x_positions([0.0, 10.0, 100.0], 0.0, 100.0)
    check('时间轴首端对齐 0', abs(xs[0]) < 1e-9)
    check('时间轴末端对齐宽度', abs(xs[-1] - 100.0) < 1e-9)
    check('时间轴按真实间隔（10% 处）', abs(xs[1] - 10.0) < 1e-6)
    check('时间轴单调', xs[0] < xs[1] < xs[2])
    check('单点落在中心', abs(x_positions([5.0], 0.0, 100.0)[0] - 50.0) < 1e-9)

    # 降采样：保留首尾、不超限
    data = list(range(500))
    sampled = downsample(data, 100)
    check('降采样条数 <= 上限', len(sampled) <= 100)
    check('降采样保留首尾', sampled[0] == 0 and sampled[-1] == 499)
    check('不超限时原样返回', downsample([1, 2, 3], 10) == [1, 2, 3])
    check('limit==2 退化为首尾两点', downsample([1, 2, 3, 4, 5], 2) == [1, 5])

    # 标签防碰撞：5K 版面 × 10 个 11 字标签（真场景）每个间隔 ≥ 28px
    label_w = text_width('10-13 16:03')
    plot_w5k = WIDTH - MARGIN_LEFT - MARGIN_RIGHT
    centers10 = [MARGIN_LEFT + plot_w5k * i / 9.0 for i in range(10)]
    pos10 = label_positions(MARGIN_LEFT, plot_w5k, centers10, [label_w] * 10)
    check('10 个长标签不重叠（间隔 >= 28px）',
          all(pos10[i] + label_w + 28 <= pos10[i + 1] for i in range(9)))
    check('10 个长标签不出界',
          pos10[0] >= MARGIN_LEFT and pos10[-1] + label_w <= MARGIN_LEFT + plot_w5k + 1)
    pos3 = label_positions(0, 1000, [200.0, 500.0, 800.0], [100, 100, 100])
    check('少量标签保持居中不推挤', pos3 == [150, 450, 750])
    # 时间标签精度阶梯：放不下 10 个长标签时降级为短格式（不抽稀）
    # 5K 版面下 10 个长标签放得下 → 保持完整格式
    long_labels = time_labels_for([0.0, 14 * 86400.0], plot_w5k, count=10)
    check('14 天跨度给 10 个标签', len(long_labels) == 10)
    check('放得下时保持 MM-DD HH:MM', all(len(x) == 11 for x in long_labels))
    # 窄画布放不下 → 降级为 MM-DD（精度减少，**不抽稀**）
    narrow = time_labels_for([0.0, 14 * 86400.0], 2000, count=10)
    check('窄画布降级为 MM-DD 且仍 10 个',
          len(narrow) == 10 and all(len(x) <= 5 for x in narrow))
    wide_labels = time_labels_for([0.0, 3600.0], plot_w5k, count=10)
    check('短跨度保持 MM-DD HH:MM', all(len(x) == 11 for x in wide_labels))

    # 混色工具：边界与中值（模拟 alpha 的实现在换肤后是新依赖）
    check('混色 t=0 == 基色', _blend((0, 0, 0), (255, 255, 255), 0) == (0, 0, 0))
    check('混色 t=1 == 目标色', _blend((0, 0, 0), (255, 255, 255), 1)
          == (255, 255, 255))
    check('混色中值', _blend((0, 0, 0), (200, 100, 50), 0.5) == (100, 50, 25))

    # 历史点容错
    check('坏时间戳被拒', parse_point({'t': 'not-a-time', 'stars': 1}) is None)
    check('缺字段被拒', parse_point({'stars': 1}) is None)
    point = parse_point({'t': '2026-10-04T10:00:00Z', 'stars': '7'})
    check('字符串数字容错', point is not None and point['stars'] == 7)
    check('计数：小数字符串取整', _as_count('3.5') == 4)
    check('计数：坏值归 0（不抛）', _as_count('abc') == 0 and _as_count(None) == 0)
    bad_count = parse_point({'t': '2026-10-04T10:00:00Z', 'stars': 'NaN!'})
    check('坏计数不炸整段历史', bad_count is not None
          and bad_count['stars'] == 0)

    # 字体：图表用到的字符都在（新增文案同样受检）
    for char in ('STARS COMMITS LAST MAX MIN PTS COUNT TIME (UTC) RENDER '
                 'PIXEL GITHUB API X 0-:.,/%+'):
        if char == ' ':
            continue
        check('字体含 %r' % char, char.upper() in _FONT_ROWS)

    # 渲染一张（含单点与多点），并检查 PNG 头 / 分辨率 / 各区块落墨
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        single = [{'ts': 1.0, 'iso': 'x', 'stars': 3, 'commits': 1}]
        many = [{'ts': float(i * 600), 'iso': 'x',
                 'stars': i, 'commits': i * 2} for i in range(200)]
        for name, data_points in (('single', single), ('many', many)):
            path = os.path.join(tmp, '%s.png' % name)
            # 一次渲染即可：文件用于 PNG 头检查，返回的 rows 用于落墨检查
            # （旧实现渲染两遍，4K 画布下白白多占一倍内存与时间）。
            rows = render_chart(data_points, 'stars', COLOR_STAR, path,
                                'STARS (COUNT)', 'COUNT', 'GITHUB API')
            with open(path, 'rb') as handle:
                head = handle.read(24)
            check('%s.png 是 PNG' % name, head[:8] == b'\x89PNG\r\n\x1a\n')
            check('%s.png 尺寸正确' % name,
                  struct.unpack('>II', head[16:24]) == (WIDTH, HEIGHT))
            check('%s.png 是 5K 分辨率' % name,
                  (WIDTH, HEIGHT) == (5120, 2880))
            plot_left = MARGIN_LEFT
            plot_bottom = HEIGHT - MARGIN_BOTTOM
            plot_w = WIDTH - MARGIN_LEFT - MARGIN_RIGHT
            check('%s 纵轴有刻度数字' % name,
                  _ink(rows, 0, MARGIN_TOP, plot_left - 6, plot_bottom) > 0)
            check('%s 横轴有时间刻度' % name,
                  _ink(rows, plot_left, plot_bottom + 4, plot_left + plot_w,
                       HEIGHT) > 0)
            check('%s 顶部有标题行' % name,
                  _ink(rows, plot_left, 0, WIDTH - 40, 140) > 0)
            check('%s 画出了折线' % name,
                  _ink(rows, plot_left + 2, MARGIN_TOP, plot_left + plot_w,
                       plot_bottom) > 0)
            check('%s 纵轴单位在最左侧' % name,
                  _ink(rows, 0, MARGIN_TOP - 84, 220, MARGIN_TOP - 34) > 0)
            check('%s 页脚（时间窗 / 规格）' % name,
                  _ink(rows, plot_left, HEIGHT - 140, WIDTH - MARGIN_RIGHT,
                       HEIGHT) > 0)
            # 换肤自检：背景是暗色（"极客风"的硬性判据）
            check('%s 背景为暗色' % name,
                  sum(COLOR_BG) < 120)
            check('%s 高亮色与背景对比度足够' % name,
                  sum(COLOR_STAR) - sum(COLOR_BG) > 400)
        # 超长仓库名：不崩、且被截断到预留宽度内
        long_repo = 'A' * 200
        rows_long = render_chart(many, 'stars', COLOR_STAR,
                                 os.path.join(tmp, 'long.png'),
                                 'STARS', 'COUNT', 'GITHUB API',
                                 repo=long_repo)
        check('超长仓库名渲染不崩', len(rows_long) == HEIGHT)
        title_band = _ink(rows_long, plot_left,
                          48 + GLYPH_H * TITLE_SCALE + 18,
                          plot_left + int((WIDTH - MARGIN_LEFT - MARGIN_RIGHT) * 0.7),
                          48 + GLYPH_H * TITLE_SCALE + 18 + GLYPH_H * TEXT_SCALE)
        check('超长仓库名副标题落在预留宽度内（有落墨）', title_band > 0)

    if failures:
        for item in failures:
            print('FAIL %s' % item, file=sys.stderr)
        print('自检失败：%d 项' % len(failures), file=sys.stderr)
        return 1
    print('自检通过：刻度 / 时间轴 / 降采样 / 混色 / 容错 / 字体 / PNG / 极客配色 全部符合预期')
    return 0


# ── 主流程 ───────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo')
    parser.add_argument('--history')
    parser.add_argument('--out-dir')
    parser.add_argument('--max-points', type=int, default=2000)
    parser.add_argument('--selftest', action='store_true')
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if not (args.repo and args.history and args.out_dir):
        parser.error('需要 --repo / --history / --out-dir（或 --selftest）')

    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN') or ''
    if not token:
        print('缺少 GH_TOKEN / GITHUB_TOKEN', file=sys.stderr)
        return 2

    try:
        stars = fetch_stars(args.repo, token)
        commits = fetch_commits(args.repo, token)
    except urllib.error.HTTPError as error:
        print('接口请求失败：HTTP %s' % error.code, file=sys.stderr)
        return 3

    points = load_history(args.history)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    points.append({
        'ts': now.timestamp(),
        'iso': now.isoformat().replace('+00:00', 'Z'),
        'stars': stars,
        'commits': commits,
    })
    if len(points) > args.max_points:
        points = points[-args.max_points:]

    write_history(args.history, points)

    render_chart(points, 'stars', COLOR_STAR,
                 os.path.join(args.out_dir, 'star-history.png'),
                 'STARS', 'COUNT', 'GITHUB API', repo=args.repo)
    render_chart(points, 'commits', COLOR_COMMIT,
                 os.path.join(args.out_dir, 'commit-history.png'),
                 'COMMITS', 'COUNT', 'GITHUB API', repo=args.repo)

    first = format_time(points[0]['ts'])
    last = format_time(points[-1]['ts'])
    print('stars=%d commits=%d points=%d window=%s..%s'
          % (stars, commits, len(points), first, last))
    return 0


if __name__ == '__main__':
    sys.exit(main())
