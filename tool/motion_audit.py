#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 动效分级审计（CI 门禁）。

## 它守什么
用户要求：动画必须**严格按档位分级**（1 最保守 → 3 拉满），
"降档 = 降质量"而不是"各处自己写死时长/效果"。

因此本工具在 `lib/surface/**` 里禁止：

1. **硬编码时长**（`Duration(milliseconds:/seconds:/minutes:/hours:/days: …)`
   —— 时长只能来自 `OgLOAnimQuality` 的档位表（`app/motion.dart`），经
   `OgLAnim` 读取；等待语义（Timer/TTL/防抖/轮询周期）需同行提示词豁免；
2. **硬编码缩放 / 模糊 / 隐式动效组件**（`ScaleTransition(` / `AnimatedScale(`
   / `AnimatedOpacity|Size|Switcher|Rotation…(` / `BackdropFilter(` /
   `ImageFilter.blur`）—— 低档位下它们仍会播放动画，必须走档位表；
   这类规则**没有行内豁免**；
3. **匀速动画**（`Curves.linear`）—— 匀速运动"机械 / 死板"、不符合直觉；
   动画一律走**自然减速**（ease-out 阶梯），曲线只能来自档位表
   （`motion.dart` 的 `curve` / `largeCurve`）。

允许名单写在下方的 [ALLOW_FILES]；行内豁免（DURATION_HINTS）仅作用于
时长规则，且逐行精确匹配；隐式动效组件在其 duration/curve 走档位表
（`OgLAnim.*` 或 `Duration.zero` 关档）时放行；确属非动效的时长令牌
可用上方 2 行内的 `motion-allow:` 注释显式登记（理由写在注释里）。

## 用法
    python3 tool/motion_audit.py            # 打印报告
    python3 tool/motion_audit.py --fatal    # CI：有违规即退出码 1
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SURFACE = os.path.join(ROOT, 'lib', 'surface')

# 档位表 / 工具箱本身（唯一允许出现原始时长与缩放的地方）
ALLOW_FILES = {
    'lib/surface/app/motion.dart',
    'lib/surface/app/animations.dart',
}

# 行内例外：这些是"等待/节流"，不是动画。
# ★ B10 收紧：豁免按「规则类别 × 提示词」逐项匹配，不再整行子串放行
#   全部规则 —— 旧版一行里出现 `Cache` 会同时豁免该行的模糊/曲线检查，
#   这是把豁免放大成了白名单漏洞。时长类规则要求同一行内出现等待语义
#   提示词；缩放/模糊/曲线类规则**没有任何行内豁免**（它们只能是动画）。
DURATION_HINTS = (
    'Timer(',
    'throttle',
    'ttl',
    'debounce',
    'exitWindow',
    'Cache',
    'cache',
    'difference(',
    'delayed(',
    'Timeout(',
    'connectionTimeout',
    'progressPeriod',   # 下载管理器轮询周期（进度刷新节流，非动画）
)

PATTERNS = [
    # ★ B11：不只查 milliseconds —— seconds/minutes/hours/days 同样禁止
    #   硬编码（动画/等待时长一律走档位表或经白名单登记）。
    ('硬编码时长', re.compile(r'Duration\(\s*(?:milliseconds|seconds|minutes|hours|days):\s*\d')),
    # ★ B12：隐式动效组件（AnimatedOpacity/Size/Switcher/Rotation…）同样
    #   必须经档位表 —— 低档位下它们仍在播放动画。
    ('硬编码隐式动效', re.compile(
        r'\bAnimated(?:Scale|Slide|Opacity|Size|Switcher|Rotation|'
        r'Align|Container|CrossFade|Padding|Positioned|DefaultTextStyle|'
        r'Icon|ListTile|Modal|PhysicalModel|Theme|Wrap)\(')),
    ('硬编码缩放过渡', re.compile(r'\b(?:ScaleTransition|AnimatedScale)\(')),
    ('硬编码模糊', re.compile(r'(?:BackdropFilter|ImageFilter\.blur)\(')),
    ('匀速动画（死板）', re.compile(r'\bCurves\.linear\b')),
]


def audit():
    violations = []
    scanned = 0
    for dirpath, _dirs, files in os.walk(SURFACE):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT)
            scanned += 1
            if rel in ALLOW_FILES:
                continue
            with open(full, encoding='utf-8') as handle:
                lines = handle.readlines()
            for index, raw in enumerate(lines, start=1):
                stripped = raw.strip()
                if stripped.startswith('//') or stripped.startswith('///'):
                    continue
                # 构造调用的 duration 参数常写在后续行（AnimatedSize(
                # duration: OgLAnim.fast(...) ...)），故隐式动效组件的
                # 「已接档位表」判定向前看 3 行。
                ctx = '\n'.join(lines[index - 1:index + 2])
                for label, pattern in PATTERNS:
                    if not pattern.search(raw):
                        continue
                    # 仅「硬编码时长」接受等待语义提示词豁免，且要求
                    # 提示词在同一行（逐条规则判断，不再整行放行）。
                    # 上方 2 行内的 `motion-allow:` 注释是显式登记豁免
                    # （如「提示驻留时长」这类非动效令牌，理由写在注释里）。
                    if label == '硬编码时长' and any(
                            hint in raw for hint in DURATION_HINTS):
                        continue
                    if label == '硬编码时长' and 'motion-allow:' in \
                            '\n'.join(lines[max(0, index - 3):index - 1]):
                        continue
                    # 隐式动效组件：duration/curve 已走档位表（OgLAnim.*
                    # 或显式 Duration.zero 关档）即合规。
                    if label == '硬编码隐式动效' and (
                            'OgLAnim.' in ctx or 'Duration.zero' in ctx):
                        continue
                    violations.append((rel, index, label, stripped[:100]))
    return scanned, violations


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fatal', action='store_true',
                        help='有违规时退出码 1（供 CI 使用）')
    args = parser.parse_args()

    scanned, violations = audit()
    print('动效分级审计：扫描 %d 个文件（白名单 %d 个）'
          % (scanned, len(ALLOW_FILES)))
    if not violations:
        print('违规：0 处 —— 所有动画都走档位质量表 ✅')
        return 0
    print('违规：%d 处' % len(violations))
    for rel, line, label, text in violations:
        print('  %s:%d [%s] %s' % (rel, line, label, text))
    print('\n修法：时长 / 位移 / 缩放一律经 `OgLAnim`（读 `OgLOAnimQuality` 档位表）；'
          '确属等待（非动画）请加行内提示词或登记白名单。')
    return 1 if args.fatal else 0


if __name__ == '__main__':
    sys.exit(main())