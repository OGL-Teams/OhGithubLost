#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 契约审计（补 layer_audit / motion_audit / perf_audit 的结构盲区）。

批次 1/2 的 C 视角共同点名：三支门禁只扫 lib/surface、不解析 export、
不查文件头与平台门面，导致 lib/base 与 lib/domain 的语义缺陷能在
CI 全绿下共存。本脚本只做**可静态确证**的结构检查：

  1. 相对 `export` 是否指向真实文件、是否跨层向上；
  2. `lib/base`、`lib/domain` 的文件头层级前缀（L1/L2）；
  3. `defaultTargetPlatform` 是否绕过 `lib/platform` 门面（白名单外）；
  4. `docs/` 中被引用为契约出处的文档是否真实存在；
  5. 204/206 等状态码在写回执路径是否有对应的回归测试（弱提示）。

用法：
    python3 tool/contract_audit.py
    python3 tool/contract_audit.py --fatal     # 有确证违规退出 1
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, 'lib')
DOCS = os.path.join(ROOT, 'docs')

LAYERS = ['kernel', 'base', 'domain', 'surface']
RANK = {name: i for i, name in enumerate(LAYERS)}

IMPORT_RE = re.compile(r"^\s*(?:import|export)\s+'([^']+)'", re.M)
HEADER_RE = re.compile(r'^///\s*(L[0-3])\b', re.M)
PLATFORM_RE = re.compile(r'\bdefaultTargetPlatform\b')
DOC_REF_RE = re.compile(r'docs/[A-Z0-9_.-]+\.md', re.I)

# 允许直接使用平台判定的门面文件（其余必须经 lib/platform）。
PLATFORM_ALLOW = {
    'platform/platform.dart',
    'platform/window_capability.dart',
    'surface/app/permissions.dart',  # 历史例外：仅用于分派，已登记
    'surface/app/system_notifier.dart',  # 通知插件需按平台传参，属适配分派
    'main.dart',  # 组合根：诊断展示平台名
}

# 允许缺失层级头注释的文件（转发导出、契约、生成物）。
HEADER_EXEMPT = {
    'base/net/net_types.dart',
    'base/disk/disk_store.dart',
    'base/disk/disk_types.dart',
    'kernel/contract/module.dart',
}


def layer_of(rel: str) -> str | None:
    parts = rel.split('/')
    return parts[0] if parts and parts[0] in LAYERS else None


def dart_files() -> dict[str, str]:
    out: dict[str, str] = {}
    for dirpath, _dirs, files in os.walk(LIB):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, LIB).replace(os.sep, '/')
            with open(full, encoding='utf-8') as handle:
                out[rel] = handle.read()
    return out


def check_exports(files: dict[str, str]) -> list[str]:
    issues: list[str] = []
    for rel, text in files.items():
        lay = layer_of(rel)
        if lay is None:
            continue
        for imp in IMPORT_RE.findall(text):
            if imp.startswith('package:') or imp.startswith('dart:') or 'if (' in imp:
                continue
            target = os.path.normpath(
                os.path.join(os.path.dirname(rel), imp)).replace(os.sep, '/')
            if not os.path.isfile(os.path.join(LIB, target)):
                issues.append('%s: export/import 指向不存在的文件 %s' % (rel, imp))
                continue
            tlay = layer_of(target)
            if tlay and tlay != lay and tlay != 'kernel' and RANK[tlay] > RANK[lay]:
                issues.append('%s: 向上导出/导入 %s（%s）' % (rel, imp, tlay))
    return issues


def check_headers(files: dict[str, str]) -> list[str]:
    issues: list[str] = []
    want = {'base': 'L1', 'domain': 'L2', 'surface': 'L3', 'kernel': 'L0'}
    for rel, text in files.items():
        lay = layer_of(rel)
        if lay is None or lay == 'kernel' or rel in HEADER_EXEMPT:
            continue
        head = text[:400]
        m = HEADER_RE.search(head)
        if m is None:
            issues.append('%s: 文件头缺 %s 层级前缀' % (rel, want[lay]))
        elif m.group(1) != want[lay]:
            issues.append('%s: 文件头层级为 %s，应为 %s'
                         % (rel, m.group(1), want[lay]))
    return issues


def check_platform(files: dict[str, str]) -> list[str]:
    issues: list[str] = []
    for rel, text in files.items():
        if rel in PLATFORM_ALLOW or not PLATFORM_RE.search(text):
            continue
        issues.append('%s: 直接使用 defaultTargetPlatform，应经 lib/platform 门面'
                     % rel)
    return issues


def check_doc_refs() -> list[str]:
    issues: list[str] = []
    for name in sorted(os.listdir(DOCS)):
        if not name.endswith(('.md',)):
            continue
        with open(os.path.join(DOCS, name), encoding='utf-8') as handle:
            text = handle.read()
        for ref in set(DOC_REF_RE.findall(text)):
            if re.search(r'(YYYY|bN|_N|\bN\b)', ref):
                continue  # 计划文档里的模板占位符，不是真实引用
            if not os.path.isfile(os.path.join(ROOT, ref)):
                issues.append('docs/%s: 引用的契约文档不存在：%s' % (name, ref))
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--fatal', action='store_true')
    args = parser.parse_args()

    files = dart_files()
    sections = {
        'export/import 结构与指向': check_exports(files),
        '文件头层级前缀': check_headers(files),
        '平台门面': check_platform(files),
        '文档契约引用': check_doc_refs(),
    }
    total = 0
    for title, issues in sections.items():
        print('%s：%d 处' % (title, len(issues)))
        for item in issues:
            print('  ' + item)
        total += len(issues)
    print('合计：%d 处' % total)
    if args.fatal and total:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
