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
    # ★ 批 10：块内夹着**注释行**此前直接跳过整个文件（return 0）——
    #   但注释必须跟随它说明的那条 import（如 `// TOKEN-EXIT-01` 贴在
    #   token_exit_warning 的 import 上），文件于是永远不被整理，
    #   analyzer 的 directives_ordering 在 CI 报红而本地门禁报 0
    #   （CI 实证 5 处）。现在把注释**归属到其后第一条指令**一起排序。
    block: list[tuple[int, str]] = []  # (排序键顺序号, 行)
    comment: list[str] = []
    for i in range(start, end + 1):
        stripped = lines[i].strip()
        if not stripped:
            continue  # 块内空行丢弃（重排后由分组规则重建）
        if DIRECTIVE.match(stripped):
            block.append((len(block), stripped, list(comment)))
            comment = []
        elif stripped.startswith('//'):
            comment.append(lines[i])  # 原样保留缩进
        else:
            return 0  # 其它语句混进块内：不整理，保守跳过
    if not block:
        return 0

    entries = []
    for order, line, attached in block:
        match = DIRECTIVE.match(line)
        kind, uri = match.group(1), match.group(2)
        entries.append((group_of(uri), uri, 0 if kind == 'import' else 1,
                        order, line, attached))

    seen: set[str] = set()
    unique = []
    for entry in sorted(entries):
        if entry[4] in seen:
            continue
        seen.add(entry[4])
        unique.append(entry)

    out: list[str] = []
    last_group = None
    for group, _uri, _kind, _order, line, attached in unique:
        if last_group is not None and group != last_group:
            out.append('')
        out.extend(attached)  # 注释先于它说明的 import
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