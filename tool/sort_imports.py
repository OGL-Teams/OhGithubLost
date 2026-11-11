#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · import 规范化：按 directives_ordering 分组排序并补空行。

分组顺序：`dart:` → `package:` → 相对路径；组间空一行，块后空一行。
同时在组内保持字母序，import 一律排在 export 之前。
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 同时整理 lib 与 test（测试也受 directives_ordering 约束，CI 会卡）。
LIB = os.path.join(ROOT, 'lib')
TEST = os.path.join(ROOT, 'test')

DIRECTIVE = re.compile(r"^(import|export|part)\s+'([^']+)'(?:\s+(?:as\s+\w+|show\s+[^;]+|hide\s+[^;]+))*\s*;")


def group_of(uri):
    if uri.startswith('dart:'):
        return 0
    if uri.startswith('package:'):
        return 1
    return 2


def sort_file(path, apply_changes):
    text = open(path, encoding='utf-8').read()
    lines = text.split('\n')
    idx = [i for i, line in enumerate(lines) if DIRECTIVE.match(line.strip())]
    if not idx:
        return 0
    start, end = idx[0], idx[-1]
    # 块内若夹着非指令、非空行（注释等），跳过，避免误删。
    for i in range(start, end + 1):
        stripped = lines[i].strip()
        if stripped and not DIRECTIVE.match(stripped):
            return 0
    block = [lines[i] for i in range(start, end + 1)
             if DIRECTIVE.match(lines[i].strip())]
    if not block:
        return 0

    entries = []
    for line in block:
        match = DIRECTIVE.match(line.strip())
        kind, uri = match.group(1), match.group(2)
        entries.append((group_of(uri), 0 if kind == 'import' else 1, uri,
                        line.strip()))

    seen = set()
    unique = []
    for entry in sorted(entries):
        if entry[3] in seen:
            continue
        seen.add(entry[3])
        unique.append(entry)

    out = []
    last_group = None
    for group, _, _, line in unique:
        if last_group is not None and group != last_group:
            out.append('')
        out.append(line)
        last_group = group

    # 块内原本可能夹着空行 / 注释（注释保留在块后），整体替换
    new_lines = lines[:start] + out + lines[end + 1:]
    new_text = '\n'.join(new_lines)
    if apply_changes and new_text != text:
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(new_text)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    # ★ C-12：CI 严格模式用 `--dry-run --fatal` 检测「有 import 块待排序」。
    #   此前脚本恒返回 0，接进 ci.yml 也是形同虚设——补上退出码语义。
    parser.add_argument('--fatal', action='store_true',
                        help='有待排序的 import 块时退出 1（供 CI 使用）')
    args = parser.parse_args()
    changed = 0
    for base in (LIB, TEST):
        if not os.path.isdir(base):
            continue
        for dirpath, _, filenames in os.walk(base):
            for name in sorted(filenames):
                if not name.endswith('.dart'):
                    continue
                path = os.path.join(dirpath, name)
                if sort_file(path, not args.dry_run):
                    changed += 1
                    print('sorted', os.path.relpath(path, ROOT))
    print('changed %d（%s）' % (changed, 'dry-run' if args.dry_run else '已写入'))
    return 1 if args.fatal and changed else 0


if __name__ == '__main__':
    sys.exit(main())