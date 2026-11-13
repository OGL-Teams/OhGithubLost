#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 动效档位覆盖守卫（B9 静态可确证部分）。

真机逐交互核对仍留给用户；本门禁守住两条静态事实：
1. 禁止新增裸 AnimatedOpacity / AnimatedContainer / 自写 Opacity 补间；
2. 入口组件（OgLReveal / OgLSurfaceSwitch / OgLAnim.enabled）必须仍有
   消费点，防止「降档=降质量」制度被整体摘除。
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SURFACE = ROOT / 'lib' / 'surface'

BARE = re.compile(
    r'\b(?:AnimatedOpacity|AnimatedContainer|AnimatedSize|'
    r'AnimatedSwitcher|AnimatedAlign|AnimatedPadding)\s*\(')
# 允许的既有用法（每个都要登记理由）。
ALLOWED = {
    'lib/surface/app/animations.dart': '档位质量表实现本身',
}

CONSUMERS = ('OgLReveal(', 'OgLSurfaceSwitch(', 'OgLAnim.enabled(')
MIN_CONSUMERS = 10  # 实测 33 处；阈值留足余量，只防「整体摘除」


def audit() -> list[str]:
    issues: list[str] = []
    consumer_hits = 0
    for path in sorted(SURFACE.rglob('*.dart')):
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding='utf-8')
        lines = text.splitlines()
        for lineno, line in enumerate(lines, 1):
            if not BARE.search(line) or rel in ALLOWED:
                continue
            # 只看紧随其后的 3 行：duration 走 OgLAnim / Duration.zero 即合规
            # （降档时零时长）。硬编码 duration 才算裸动效。
            ctx = '\n'.join(lines[lineno - 1:lineno + 2])
            if 'OgLAnim.' in ctx or 'Duration.zero' in ctx:
                continue
            issues.append(f'{rel}:{lineno} 裸动效组件的 duration 未走 OgLAnim 档位表')
        consumer_hits += sum(text.count(c) for c in CONSUMERS)
    if consumer_hits < MIN_CONSUMERS:
        issues.append(
            f'档位消费点仅 {consumer_hits} 处（<{MIN_CONSUMERS}），'
            '「降档=降质量」疑似被整体摘除')
    return issues


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true')
    args = ap.parse_args()
    issues = audit()
    print('动效档位覆盖守卫：%d 处' % len(issues))
    for i in issues:
        print('  ' + i)
    if args.fatal and issues:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
