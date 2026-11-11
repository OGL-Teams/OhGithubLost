#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 四层分层审计（启动 / 硬件 / 逻辑 / 交互）。

## 四层与允许的方向
    L0 启动层 kernel   —— 谁都不依赖它之外的层：它可被任意层引用（契约）
    L1 硬件层 base     —— 网络 + 硬盘（DnsService / DiskKv / RepositoryCache…）
    L2 逻辑层 domain   —— API 与服务
    L3 交互层 surface  —— UI 及其它

**依赖只能向下**（surface → domain → base → kernel）。

## 两个"合法性例外"（装配根 / 类型门面）
1. `domain/domain_bridge.dart`、`surface/surface_bridge.dart`：每层的**装配根**，
   职责就是把下层接到本层，允许 import 下层桥。
2. `surface/types.dart`：交互层的**类型门面**，唯一允许 re-export 逻辑层 DTO/异常
   的地方；页面只 import 它，从而拿不到 domain 的服务类。

## 用法
    python3 tool/layer_audit.py            # 打印报告
    python3 tool/layer_audit.py --fatal    # 有违规即退出 1（供 CI 使用）
"""
import argparse
import os
import re
import sys
from pathlib import Path

# ★ 门禁定根（批 9 · X-01）：CI 里若 CWD 不在仓库根，
#   相对 'lib' 会扫到 0 文件却报「违规 0 处 / exit 0」——
#   门禁失去能力时不是报错而是报绿，直接违反「失败必须如实可见」。
REPO_ROOT = Path(__file__).resolve().parent.parent

LAYERS = ['kernel', 'base', 'domain', 'surface']
RANK = {name: index for index, name in enumerate(LAYERS)}

# 允许跨层 import 自己的"装配根 / 门面"。
ALLOW = {
    'domain/domain_bridge.dart',
    'surface/surface_bridge.dart',
    'surface/types.dart',
}

# ★ 批 9 · X-03：export 与 import 同为依赖边。此前只匹配 import，
#   `export '../../domain/...' show X;` 能绕过唯一类型门面纪律。
IMPORT_RE = re.compile(r"^\s*(?:import|export)\s+'([^']+)'", re.M)

# 已知的、待收敛项（下一批：为这两个**实现类**引入启动层契约接口）。
#
# 为什么还留着：`RepositoryCache`（D1–D7 一致性引擎）与 `NetBridge` 都是
# 硬件层的**实现**，逻辑层目前直接依赖它们的具体类型。正解是在
# `kernel/contract/` 定义 `ConsistencyCache` / `NetClient` 抽象，
# 由硬件层实现、逻辑层只依赖抽象。属独立批次，避免与 4.9 的结构改动混在一起。
KNOWN = {
    'domain/gh/gh_api.dart': {'../../base/disk/disk_cache.dart'},
    'domain/gh/gh_client.dart': {'../../base/net/net_bridge.dart'},
}


def layer_of(rel):
    parts = rel.split('/')
    return parts[0] if parts and parts[0] in LAYERS else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lib', default=str(REPO_ROOT / 'lib'))
    parser.add_argument('--fatal', action='store_true')
    args = parser.parse_args()

    violations = []
    known_hits = 0
    total = 0
    for dirpath, _dirs, files in os.walk(args.lib):
        for name in sorted(files):
            if not name.endswith('.dart'):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, args.lib).replace(os.sep, '/')
            lay = layer_of(rel)
            if lay is None:
                continue
            total += 1
            if rel in ALLOW:
                continue
            with open(full, encoding='utf-8') as handle:
                text = handle.read()
            for imp in IMPORT_RE.findall(text):
                if imp.startswith('package:'):
                    continue
                target = os.path.normpath(
                    os.path.join(os.path.dirname(rel), imp)).replace(os.sep, '/')
                tlay = layer_of(target)
                if tlay is None or tlay == lay or tlay == 'kernel':
                    continue  # 同层 / 内核契约：允许
                if RANK[tlay] > RANK[lay]:
                    violations.append((rel, imp, '向上依赖 %s' % tlay))
                elif rel in KNOWN and imp in KNOWN[rel]:
                    known_hits += 1
                else:
                    violations.append((rel, imp, '%s 应经桥/门面' % tlay))

    print('文件总数：%d' % total)
    # ★ 空扫即失败：参数错位 / 目录重构 / CWD 异常时，
    #   绝不允许「0 文件 → 0 违规 → 通过」这种假绿。
    if total == 0:
        print('::error::分层审计扫描到 0 个 Dart 文件（--lib=%s 无效？）' % args.lib)
        return 1
    print('已知待收敛（5.0 清单）：%d 处' % known_hits)
    print('违规：%d 处' % len(violations))
    for rel, imp, why in violations:
        print('  %-46s %-42s %s' % (rel, imp, why))
    if args.fatal and violations:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())