#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查 _content/*.md 是否残留面向开发者的技术表述。

只做机械筛查，最终仍以人工判读为准。命中即打印，退出码非零表示需修。
"""
import glob
import os
import re
import sys

import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(HERE, '_content')

# ★ C-17：平台/产品专名不是「驼峰标识符」，
#   此前 macOS / iOS / GitHub 等被机械正则误判为开发术语。
#   只豁免这些确证的专名，不放宽驼峰规则本身。
PROPER_NOUNS = frozenset((
    'macOS', 'iOS', 'iPadOS', 'watchOS', 'tvOS', 'GitHub', 'GitLab',
    'AppImage', 'TypeScript', 'JavaScript', 'OAuth', 'Web',
    # 文件名里合法的特殊字符：用户可见说明里用反引号标出，
    # 不是「行内代码」（讲的就是这两个字符本身）。
    '`#`', '`?`',
))

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
    # --fatal 与默认行为一致（脚本本就返回 1），显式参数只为让 CI 步骤
    # 与其它门禁写法统一；--check 是等价别名。
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.parse_args()

    problems = 0
    for path in sorted(glob.glob(os.path.join(CONTENT, '*.md'))):
        name = os.path.basename(path)
        if name.startswith('_'):
            continue
        text = open(path, encoding='utf-8').read()
        hits = []
        for pattern, label in PATTERNS:
            for match in re.finditer(pattern, text, re.M):
                if match.group(0) in PROPER_NOUNS:
                    continue
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
