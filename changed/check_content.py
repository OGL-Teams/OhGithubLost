#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查 _content/*.md 是否残留面向开发者的技术表述。

只做机械筛查，最终仍以人工判读为准。命中即打印，退出码非零表示需修。
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(HERE, '_content')

# 明显属于实现细节的词或标记
PATTERNS = [
    (r'`[^`]+`', '行内代码'),
    (r'\.dart\b', 'Dart 文件名'),
    (r'\blib/', '源码路径'),
    (r'\btest/', '测试路径'),
    (r'\b[A-Za-z]+_[a-z][A-Za-z_]*\b', '下划线标识符'),
    (r'\b[a-z]+[A-Z][A-Za-z]*\b', '驼峰标识符'),
    (r'\b(CI|CD|PR|commit|patch|refactor|merge)\b', '开发流程词'),
    (r'\b(isolate|pipeline|state machine|SSE|SDK|API|HTTP|JSON|URL|token|cache)\b',
     '内部机制词'),
    (r'\bv\d+\.', '版本号前缀'),
    (r'[!！]\s*$', '感叹号结尾'),
    (r'\b(我们|你|大家)\b', '人称'),
]

def main() -> int:
    problems = 0
    for path in sorted(glob.glob(os.path.join(CONTENT, '*.md'))):
        name = os.path.basename(path)
        if name.startswith('_'):
            continue
        text = open(path, encoding='utf-8').read()
        hits = []
        for pattern, label in PATTERNS:
            for match in re.finditer(pattern, text, re.M):
                hits.append((label, match.group(0)))
        if hits:
            print('%s: %d 处' % (name, len(hits)))
            seen = set()
            for label, found in hits:
                if found in seen:
                    continue
                seen.add(found)
                print('    [%s] %s' % (label, found))
            problems += 1
    print('---')
    print('检查 %d 篇，%d 篇有可疑表述' % (
        len([p for p in glob.glob(os.path.join(CONTENT, '*.md'))
             if not os.path.basename(p).startswith('_')]), problems))
    return 1 if problems else 0

if __name__ == '__main__':
    raise SystemExit(main())
