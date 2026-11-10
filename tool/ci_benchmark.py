#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · CI/Build 耗时与缓存命中复测工具。

见 `docs/CI_BUILD_BASELINE.md`：**改 CI 配置前后都要用它复测**，
不要凭感觉加缓存或拆 job。

用法：
    python3 tool/ci_benchmark.py                 # 最近一次完成的 CI / Build
    python3 tool/ci_benchmark.py --run 123456   # 指定 run
    python3 tool/ci_benchmark.py --token XXX    # 指定 PAT（否则读环境变量）

只读取 GitHub Actions API，不修改仓库、不推送。
没有 token 时 gracefully 提示（不会打印 token 本身）。
"""
from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import re
import sys
import urllib.request
import zipfile

REPO = 'OGL-Teams/OhGithubLost'
API = 'https://api.github.com/repos/' + REPO


def get(url: str, token: str, raw: bool = False):
    req = urllib.request.Request(url, headers={
        'Authorization': 'token ' + token,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'OGL-CI-Benchmark',
    })
    data = urllib.request.urlopen(req, timeout=90).read()
    return data if raw else json.loads(data)


def secs(start: str | None, end: str | None) -> int:
    if not start or not end:
        return 0
    a = datetime.datetime.fromisoformat(start.replace('Z', '+00:00'))
    b = datetime.datetime.fromisoformat(end.replace('Z', '+00:00'))
    return int((b - a).total_seconds())


def cache_hits(run_id: int, token: str) -> str:
    """从 run 日志统计缓存命中 / 未命中 / 写入。"""
    try:
        data = get(f'{API}/actions/runs/{run_id}/logs', token, raw=True)
        archive = zipfile.ZipFile(io.BytesIO(data))
    except Exception as exc:  # noqa: BLE001
        return '日志不可用：%s' % exc
    hit = miss = saved = 0
    for name in archive.namelist():
        text = archive.read(name).decode('utf-8', 'replace')
        hit += len(re.findall(r'Cache hit for|Cache restored from', text))
        miss += len(re.findall(r'Cache not found for', text))
        saved += len(re.findall(r'Cache saved', text))
    return '命中/恢复 %d，未命中 %d，写入 %d' % (hit, miss, saved)


def report(run: dict, token: str) -> None:
    run_id = run['id']
    print('\n=== %s run %s (%s, %s, %s) ===' % (
        run['name'], run_id, run['head_sha'][:8], run['event'],
        run['conclusion'] or run['status']))
    print('墙钟: %ds' % secs(run['created_at'], run['updated_at']))
    if run['status'] != 'completed' or run['conclusion'] != 'success':
        print('⚠ 不是完整成功的 run —— 步骤耗时不可用于对比（可能被 cancel）')
    print('缓存: %s' % cache_hits(run_id, token))
    jobs = get(f'{API}/actions/runs/{run_id}/jobs?per_page=100', token)
    for job in jobs['jobs']:
        slow = sorted(
            [(secs(s['started_at'], s['completed_at']), s['name'])
             for s in job.get('steps', [])],
            reverse=True,
        )[:4]
        slow = [(d, n) for d, n in slow if d > 20]
        print('  %-28s %-10s %4ds  %s' % (
            job['name'][:28], job['conclusion'],
            secs(job['started_at'], job['completed_at']),
            ', '.join('%s %ds' % (n[:24], d) for d, n in slow)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--run', type=int, help='指定 run id')
    ap.add_argument('--token', default=os.environ.get('GITHUB_TOKEN', ''))
    args = ap.parse_args()
    if not args.token:
        print('需要 GitHub token：--token 或环境变量 GITHUB_TOKEN', file=sys.stderr)
        print('（只读 API，不需要写权限）', file=sys.stderr)
        return 2

    if args.run:
        run = get(f'{API}/actions/runs/{args.run}', args.token)
        report(run, args.token)
        return 0

    runs = get(f'{API}/actions/runs?per_page=20', args.token)['workflow_runs']
    for label in ('CI', 'Build'):
        found = [r for r in runs
                 if r['name'] == label and r['status'] == 'completed']
        if not found:
            print('\n%s: 暂无已完成 run' % label)
            continue
        report(found[0], args.token)

    print('\n优化前基线（2026-11-10 实测，见 docs/CI_BUILD_BASELINE.md）：')
    print('  CI     96s 步骤合计（analyze 15s + test 40s）')
    print('  Build  约 7min 墙钟；Android 腿 350~379s；发布压缩 85s')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
