#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · workflow 第三方 Action 版本守卫（B8-B-06 收敛）。

真钉 40 位 commit SHA 需要逐个解析并 CI 实跑验证，属发布信任链专项；
本门禁先锁定**可机械确证**的部分：所有 `uses:` 必须带版本、
禁止浮动分支（@main/@master/@HEAD）、版本必须与已审基线一致。
新增/升级 Action 必须显式更新本文件的 ALLOWED，避免无声漂移。
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WF = ROOT / '.github' / 'workflows'

# 已审基线：action@版本（全部为官方 major tag，非浮动分支）。
ALLOWED = {
    'actions/cache@v4',
    'actions/cache/restore@v4',
    'actions/cache/save@v4',
    'actions/checkout@v4',
    'actions/download-artifact@v4',
    'actions/upload-artifact@v4',
    'softprops/action-gh-release@v2',
    'subosito/flutter-action@v2',
}
FLOATING = re.compile(r'@(main|master|HEAD|latest)\b')
USES = re.compile(r'^\s*-?\s*uses:\s*([^\s#]+)')


def audit() -> list[str]:
    issues: list[str] = []
    for path in sorted(WF.glob('*.yml')):
        for lineno, line in enumerate(
                path.read_text(encoding='utf-8').splitlines(), 1):
            m = USES.match(line)
            if not m:
                continue
            spec = m.group(1).strip().strip('"\'')
            if spec.startswith('./') or spec.startswith('docker://'):
                continue  # 本地 action / 容器镜像另论
            if '@' not in spec:
                issues.append(f'{path.name}:{lineno} {spec} 缺少版本')
            elif FLOATING.search(spec):
                issues.append(f'{path.name}:{lineno} {spec} 使用浮动分支')
            elif spec not in ALLOWED:
                issues.append(
                    f'{path.name}:{lineno} {spec} 不在已审基线（新增/升级需登记）')
    return issues


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true')
    args = ap.parse_args()
    issues = audit()
    print('Action 版本守卫：%d 处' % len(issues))
    for i in issues:
        print('  ' + i)
    if args.fatal and issues:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
