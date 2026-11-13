#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 四层分层审计（kernel / base / domain / surface，L0–L3）。

## 四层与允许的方向
    L0 kernel   —— 内核契约层：谁都不依赖它之外的层（契约）
    L1 base     —— 底座层：网络 + 硬盘（DnsService / DiskKv / RepositoryCache…）
    L2 domain   —— 逻辑层：API 与服务
    L3 surface  —— 展示层：UI 及其它

**依赖只能向下**（surface → domain → base → kernel）。

## 两个"合法性例外"（装配根 / 类型门面）
1. `domain/domain_bridge.dart`、`surface/surface_bridge.dart`：每层的**装配根**，
   职责就是把下层接到本层，允许 import 下层桥。
2. `surface/types.dart`：展示层的**类型门面**，唯一允许 re-export 逻辑层 DTO/异常
   的地方；页面只 import 它，从而拿不到 domain 的服务类。

另有**组合根例外**：`lib/main.dart` 不在四层目录内、不参与本审计（唯一装配点，
详见 AGENTS.md §1）。`lib/platform/` 由 contract_audit 的平台门面规则守
（平台判定必须经门面），且只许依赖 kernel —— 现状经 grep 复核成立。

## KNOWN 白名单（A-05 收紧）
按「解析后的规范化目标路径」匹配，不再按 import 原文字面匹配 ——
改写相对路径（如 `../../base/...` 换成别的写法）无法套用同一豁免，
且目标解析路径与登记不一致时**报违规**而非放行。

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
LAYER_LABEL = {'kernel': 'L0 kernel', 'base': 'L1 base',
               'domain': 'L2 domain', 'surface': 'L3 surface'}
RANK = {name: index for index, name in enumerate(LAYERS)}
# platform 层（非 L 编号的五层之一）：仅依赖 kernel（AGENTS §1）。
# 此前 platform 完全不入统计 —— 有人向 platform 引入 base/domain import
# 时无任何门禁拦截。现按「platform → 只许 kernel」单边规则守。
PLATFORM_ONLY_KERNEL = {'platform'}

# 允许跨层 import 自己的"装配根 / 门面"。
ALLOW = {
    'domain/domain_bridge.dart',
    'surface/surface_bridge.dart',
    'surface/types.dart',
}

# ★ 批 9 · X-03：export 与 import 同为依赖边。此前只匹配 import，
#   `export '../../domain/...' show X;` 能绕过唯一类型门面纪律。
IMPORT_RE = re.compile(r"^\s*(?:import|export)\s+'([^']+)'", re.M)

# ★ 全部收敛（批 11）：
#   · KNOWN #2 `gh_client.dart → net_bridge.dart`：`GhClient` 改依赖
#     L0 契约 `NetTransport`，`NetBridge implements NetTransport`。
#   · KNOWN #1 `gh_api.dart → disk_cache.dart`：`GhApi` 改依赖
#     L0 契约 `ConsistencyCache`（`kernel/contract/consistency_cache.dart`），
#     `RepositoryCache implements ConsistencyCache` + `DraftRepositoryAdapter`
#     把 D9 草稿仓储适配为只读视图。D1–D9 实现逻辑未动。
#   两处均由装配根注入 L1 实现，L2 不再认识任何底座实现类。
KNOWN: dict[str, set[str]] = {}


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
            # ★ 批 11：platform/ 文件此前因 `lay is None` 被整段跳过，
            #   "platform 只许依赖 kernel" 是**永不执行的死规则**。
            #   现在显式识别 platform 并纳入 total + 单边依赖检查。
            is_platform = rel.startswith('platform/')
            if lay is None and not is_platform:
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
                if is_platform:
                    # platform 只许依赖 kernel 契约；连 base/domain/surface
                    # 都不行（也不许反向被它们依赖的间接形式）。
                    if tlay is not None and tlay != 'kernel':
                        violations.append(
                            (rel, imp, 'platform 只许依赖 kernel，发现 %s' % tlay))
                    continue
                if tlay is None or tlay == lay or tlay == 'kernel':
                    continue  # 同层 / 内核契约：允许
                if RANK[tlay] > RANK[lay]:
                    violations.append((rel, imp, '向上依赖 %s' % tlay))
                elif rel in KNOWN and target in KNOWN[rel]:
                    # ★ A-05：按解析后的规范化路径比对；
                    #   不匹配的目标（如经中转文件重导出）落进下一分支报违规。
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
