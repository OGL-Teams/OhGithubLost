#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 门面类型面审计（批 11 · 架构报告 §8 反例守卫）。

layer_audit 守的是 import **边**，守不住「通过 export / 桥字段把实现类
递给上层」——只读专项报告 audit_layering_principles.md 的 4 个反例
注入全绿正是这个盲区。本门禁补上：

1. surface/types.dart 的 export 必须带 show/hide，且不得新增服务/实现类
   到白名单外；
2. surface_bridge.dart 不得新增 L1 具体类型的公开字段（既有 4 项
   以基线锁定，只防扩散）；
3. 反向验证：注入一个服务类 export 必须报错。

用法：python3 tool/facade_audit.py [--fatal]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPES = ROOT / 'lib' / 'surface' / 'types.dart'
BRIDGE = ROOT / 'lib' / 'surface' / 'surface_bridge.dart'

EXPORT_RE = re.compile(
    r"^export\s+'([^']+)'\s*(.*?);", re.M)

# 已知服务/管理器/实现类前缀（导出即违规，除非在 LEGACY 里）。
SERVICE_WORDS = ('Service', 'Manager', 'Bridge', 'Client', 'Cache',
                 'Store', 'Runner', 'Center', 'Engine', 'Backend')

# 基线：types.dart 里已存在的、经复核仍允许的服务类导出。
# 每多一条都要显式登记理由（防止无声扩散）。
LEGACY_TYPE_EXPORTS = {
    'IxPresign': '预签名能力门面（路线图第 1 步拟改为动作方法）',
}

# 基线：bridge 里已存在的 L1 具体类型公开字段。
# 只防新增，不在此处强删（删除需逐调用点改造，见路线图）。
LEGACY_BRIDGE_FIELDS = {'NetBridge', 'RepositoryCache', 'DiskKv', 'RepoFileService'}


def audit() -> list[str]:
    issues: list[str] = []
    types_text = TYPES.read_text(encoding='utf-8')
    for m in EXPORT_RE.finditer(types_text):
        uri, tail = m.group(1), m.group(2).strip()
        if not tail:
            # 纯 DTO 模块允许裸导出（gh_models.dart 全是数据形状）。
            if uri.endswith('gh_models.dart'):
                continue
            issues.append(f'types.dart: 裸 export {uri}（必须带 show/hide）')
            continue
        shown = re.search(r'\bshow\s+([^;]+)', tail)
        if shown:
            for name in (n.strip() for n in shown.group(1).split(',')):
                if not name:
                    continue
                if any(w in name for w in SERVICE_WORDS) and name not in LEGACY_TYPE_EXPORTS:
                    issues.append(
                        f'types.dart: show {name} 是服务/实现类，不得经门面暴露给 L3')
    bridge_text = BRIDGE.read_text(encoding='utf-8')
    field_re = re.compile(r'^\s*final\s+([A-Z]\w*)\??\s+\w+\s*;', re.M)
    found = {m.group(1) for m in field_re.finditer(bridge_text)}
    for cls in sorted(found):
        if cls in LEGACY_BRIDGE_FIELDS:
            continue
        if cls == 'DomainBridge':
            continue  # L2 装配桥是 L3 的合法入口
        if cls.endswith(tuple(SERVICE_WORDS)) or cls.startswith(('Disk', 'Net', 'Repo')):
            issues.append(
                f'surface_bridge.dart: 公开字段类型 {cls} 疑似 L1 实现，'
                f'不得新增（基线 {sorted(LEGACY_BRIDGE_FIELDS)} 之外的类型面）')
    return issues


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true')
    args = ap.parse_args()
    issues = audit()
    print('门面类型面审计：%d 处' % len(issues))
    for i in issues:
        print('  ' + i)
    if args.fatal and issues:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
