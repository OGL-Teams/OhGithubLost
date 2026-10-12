#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将线上 Release 正文同步为本地 release_notes/v<tag>.md（1:1 对齐）。

用法：
    python3 release_notes/sync_releases.py [--token-file 路径] [--dry-run]

行为：
  - 拉取线上全部 Release；
  - 每个 tag 写 release_notes/v<tag>.md（正文原样保存，含中英对照）；
  - 已存在且内容相同的跳过；
  - 不覆盖本地手工维护的 README.md。
"""
from __future__ import annotations

import argparse
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = 'https://api.github.com/repos/OGL-Teams/OhGithubLost/releases?per_page=50'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--token-file', default=os.path.join(HERE, '..', '..', '_setup', '.gh_token'))
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    try:
        token = open(args.token_file, encoding='utf-8').read().strip()
    except OSError as exc:
        print('无法读取 token：', exc)
        return 2

    req = urllib.request.Request(API, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ogl-release-notes-sync',
    })
    with urllib.request.urlopen(req, timeout=60) as resp:
        releases = json.loads(resp.read().decode('utf-8'))

    written = skipped = unchanged = 0
    for rel in releases:
        tag = rel['tag_name']
        body = rel.get('body') or ''
        if tag == 'README':  # 防误写
            continue
        path = os.path.join(HERE, 'v%s.md' % tag)
        if os.path.isfile(path):
            existing = open(path, encoding='utf-8').read()
            if existing == body:
                unchanged += 1
                continue
        if args.dry_run:
            print('[dry-run] 将写入', path)
            written += 1
            continue
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(body)
        print('[ok]', path, '(%dB)' % len(body))
        written += 1

    print('合计：线上 %d 个；新写 %d，跳过已存在 %d，内容未变 %d' % (
        len(releases), written, skipped, unchanged))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())