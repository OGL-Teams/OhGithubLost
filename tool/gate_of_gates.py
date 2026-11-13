#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · 门禁之门禁（gate-of-gates，批 9 交叉 X-01）。

## 为什么需要它
批 8 就点名过、批 9 三视角交叉再次确证：`layer_audit.py` 与
`i18n_scan.py` 曾依赖 CWD —— 在 /tmp 下跑 `--fatal` / `--check`
会输出「文件总数 0 / [check] 通过」并 exit 0。**门禁失去能力时
不是报错而是报绿**，直接违反「失败必须如实可见」。

本工具把「每支门禁确实扫到了东西」变成可执行契约：
1. 把 CWD 切到一个**临时空目录**，用绝对路径调用各门禁；
2. 断言退出码为 0 **且** 输出里出现非零的扫描对象计数
   （或在输出里明确声明自己的扫描范围）；
3. 对可以廉价注入的反例做**反向验证**：门禁必须能拦下。

用法：
    python3 tool/gate_of_gates.py            # 报告
    python3 tool/gate_of_gates.py --fatal    # CI：有问题退出 1
"""
from __future__ import annotations

import argparse
import io
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / 'tool'

# 每支门禁：命令、期望输出里必须出现的「确实扫到了东西」的证据。
# 括号里是脚本自报的扫描规模；数字会变，故用关键字而非精确值。
GATES: list[tuple[str, list[str], str]] = [
    ('layer_audit', ['--fatal'], '文件总数：'),
    ('contract_audit', ['--fatal'], '合计：'),
    ('ui_audit', ['--fatal'], '审计'),
    ('motion_audit', ['--fatal'], '扫描'),
    ('perf_audit', ['--fatal'], '审计'),
    ('ci_config_audit', ['--fatal'], 'workflow'),
    ('i18n_scan', ['--check'], '语言清单一致'),
    ('facade_audit', ['--fatal'], '门面类型面审计'),
    ('action_pin_audit', ['--fatal'], 'Action 版本守卫'),
    ('motion_coverage_audit', ['--fatal'], '动效档位覆盖守卫'),
]

# 期望「扫描对象数 > 0」的关键字。layer/i18n/motion 的输出里带数量，
# 其余至少要有「通过」以外的实质报告行。
POSITIVE_HINTS = ('文件总数：', '扫描', '审计', '合计', 'workflow', '语言清单一致')


def run_gate(name: str, extra: list[str], cwd: str) -> tuple[int, str]:
    script = TOOLS / (name + '.py')
    proc = subprocess.run(
        [sys.executable, str(script)] + extra,
        cwd=cwd, capture_output=True, text=True, timeout=180,
    )
    return proc.returncode, (proc.stdout + proc.stderr)


def negative_tests() -> list[str]:
    """反向验证：把一层门禁暂时弄瞎，它必须报错而不是报绿。

    用临时副本做，不碰仓库里的脚本。
    """
    problems: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        # 1) layer_audit：传入一个空的 --lib，必须失败（空扫即失败）
        empty = Path(tmp) / 'empty-lib'
        empty.mkdir()
        proc = subprocess.run(
            [sys.executable, str(TOOLS / 'layer_audit.py'), '--fatal',
             '--lib', str(empty)],
            cwd=tmp, capture_output=True, text=True, timeout=120,
        )
        if proc.returncode == 0:
            problems.append('layer_audit 空扫仍返回 0（空扫即失败规则失效）')

        # 2) i18n_scan：注入一个 dict 值，--check 必须失败
        shard = ROOT / 'assets' / 'i18n' / 'de' / 'common.json'
        original = shard.read_text(encoding='utf-8')
        fake = Path(tmp) / 'common.json'
        import json as _json
        data = _json.loads(original)
        data['__gate_negative__'] = {'de': 'x'}
        fake.write_text(_json.dumps(data, ensure_ascii=False), encoding='utf-8')
        # 用临时 i18n 目录，只放 zh 与 de 两个分片不足以跑全量对齐，
        # 故直接复制整棵 i18n 目录再替换一个分片。
        import shutil
        i18n_copy = Path(tmp) / 'i18n'
        shutil.copytree(ROOT / 'assets' / 'i18n', i18n_copy)
        (i18n_copy / 'de' / 'common.json').write_text(
            fake.read_text(encoding='utf-8'), encoding='utf-8')
        proc = subprocess.run(
            [sys.executable, str(TOOLS / 'i18n_scan.py'), '--check',
             '--lib', str(ROOT / 'lib'), '--i18n', str(i18n_copy)],
            cwd=tmp, capture_output=True, text=True, timeout=120,
        )
        if proc.returncode == 0:
            problems.append('i18n_scan 对 dict 值仍返回 0（值类型校验失效）')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--fatal', action='store_true')
    args = ap.parse_args()

    issues: list[str] = []
    with tempfile.TemporaryDirectory() as cwd:
        print('临时 CWD：%s（模拟 CI 参数/CWD 错位）\n' % cwd)
        for name, extra, need in GATES:
            code, out = run_gate(name, extra, cwd)
            ok = code == 0 and need in out
            # 空跑检测：输出里不能出现「0 个文件」这类静默空扫
            empty_sweep = ('文件总数：0' in out or '共 0 处（待本地化' in out
                           and '语言清单一致' not in out)
            if empty_sweep:
                ok = False
            print(' %-18s exit=%d  证据「%s」=%s  %s' % (
                name, code, need, '有' if need in out else '无',
                '✅' if ok else '❌'))
            if not ok:
                issues.append('%s 在临时 CWD 下未通过或缺少扫描证据' % name)

        print('\n反向验证（门禁必须能拦下人为注入的缺陷）：')
        for problem in negative_tests():
            issues.append(problem)
        if not issues:
            print(' ✅ 空扫即失败 / dict 值即失败 两条反向验证通过')

    if issues:
        print('\ngate-of-gates：发现 %d 处问题' % len(issues))
        for i in issues:
            print('  -', i)
        return 1 if args.fatal else 0
    print('\ngate-of-gates 通过：%d 支门禁在错误 CWD 下仍有能力，'
          '且反向验证能拦下注入缺陷' % len(GATES))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
