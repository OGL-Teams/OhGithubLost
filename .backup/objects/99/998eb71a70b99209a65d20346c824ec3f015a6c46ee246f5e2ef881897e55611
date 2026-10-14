#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清理 changed/ 下被误写入的畸形文件名（例如把内容当成文件名写进去的条目）。"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, 'changed')


def main() -> int:
    removed = []
    keep = {'_config.yml', '_posts', 'index.md', 'generate_posts.py'}
    for name in sorted(os.listdir(TARGET)):
        path = os.path.join(TARGET, name)
        if name in keep:
            continue
        if os.path.isdir(path):
            continue
        removed.append(name)
        os.remove(path)
    print('removed: %s' % removed)
    return 0


if __name__ == '__main__':
    sys.exit(main())