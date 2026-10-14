#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `release_notes/<tag>.md` 生成为 Jekyll _posts（更新日志站点用）。

做三件事：
1. 统一标题格式：`OhGithubLost <版本号> · <渠道>`（正式版 / 预发布版）；
2. 正文下方按平台归类，追加该版本**全部产物**的下载链接（走加速域名）；
3. 去掉正文里各家格式不一的首个标题行，避免与页面标题重复。

用法：
    python3 generate_posts.py                     # 用产物清单里的线上日期
    python3 generate_posts.py --assets ../../_setup/release_assets.json
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))

# 下载加速域名：把 GitHub 的 assets 域名换成镜像，实测更快。
ACCEL_HOST = 'gh.344977.xyz'

# 版本 → 发布日期（读取产物清单的 published_at 更准，这里只作兜底）
FALLBACK_DATES = {
    'v0.1.0': '2026-10-01',
    'v0.2.0-beta': '2026-10-01',
    'v1.0.0': '2026-10-01',
    'v1.1.0': '2026-10-01',
    'v1.4': '2026-10-02',
    'v2.0.0': '2026-10-02',
    'v2.2.0': '2026-10-02',
    'v3.0.0': '2026-10-03',
    'v3.1.0': '2026-10-03',
    'v3.2.0': '2026-10-03',
    'v4.0.0': '2026-10-03',
    'v4.1.0': '2026-10-03',
    'v4.2.0-alpha': '2026-10-03',
    'v4.3.0': '2026-10-03',
    'v4.5.0-alpha': '2026-10-03',
    'v4.6.0-alpha': '2026-10-03',
    'v4.7.0': '2026-10-03',
    'v4.8.0': '2026-10-03',
    'v4.9.0-beta': '2026-10-04',
    'v5.0.0-beta': '2026-10-04',
    'v5.1.0': '2026-10-04',
    'v5.2.0': '2026-10-04',
    'v5.3.0': '2026-10-04',
    'v5.6.0': '2026-10-04',
    'v6.0.0': '2026-10-05',
}

# 平台归类：按资产名里的平台关键字，顺序即展示顺序。
PLATFORMS = [
    ('Android', ('android',)),
    ('Windows', ('windows',)),
    ('Linux', ('linux',)),
    ('macOS', ('macos',)),
    ('iOS', ('ios',)),
]


def channel_of(tag: str) -> str:
    return '预发布版 / Pre-release' if re.search(r'-(alpha|beta)', tag) \
        else '正式版 / Stable'


def version_label(tag: str) -> str:
    """展示用版本号：去掉 tag 的 v 前缀与渠道后缀。"""
    return re.sub(r'-(alpha|beta)$', '', tag.lstrip('v'))


def load_assets(path: str) -> dict:
    if not path or not os.path.isfile(path):
        return {}
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def accel_url(url: str) -> str:
    """把 github.com/... 换成加速域名。"""
    return re.sub(r'^https://github\.com/', 'https://%s/' % ACCEL_HOST, url)


def human_size(num: int) -> str:
    mb = num / (1024 * 1024)
    return '%.0f MB' % mb if mb >= 10 else '%.1f MB' % mb


def build_downloads(tag: str, assets_map: dict) -> list:
    """生成「全部产物」下载小节；无产物时返回空列表。"""
    info = assets_map.get(tag)
    if not info or not info.get('assets'):
        return []

    groups = []
    for label, keys in PLATFORMS:
        items = [a for a in info['assets']
                 if any(k in a['name'].lower() for k in keys)]
        if items:
            groups.append((label, sorted(items, key=lambda x: x['name'])))
    if not groups:
        return []

    out = ['', '---', '', '## 下载 / Download', '',
           '本版本共 %d 个构件产物。' % len(info['assets']), '']
    for label, items in groups:
        out.append('**%s**' % label)
        out.append('')
        out.append('| 文件 | 大小 |')
        out.append('| --- | ---: |')
        for a in items:
            out.append('| [%s](%s) | %s |' % (
                a['name'], accel_url(a['url']), human_size(a['size'])))
        out.append('')
    out.append('> 完整列表与校验信息见 [Releases %s](%s)。' % (
        tag, info.get('html_url', '')))
    return out


def strip_leading_title(body: str) -> str:
    """去掉正文首个标题行（各家写法不一：# / ## / 带 v 前缀）。"""
    lines = body.splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    if lines:
        first = lines[0].lstrip('#').strip()
        if re.match(r'^OhGithubLost\s', first):
            lines.pop(0)
    return '\n'.join(lines).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--release-notes-dir',
                    default=os.path.join(REPO, 'release_notes'))
    ap.add_argument('--assets',
                    default=os.path.join(REPO, '..', '_setup',
                                         'release_assets.json'),
                    help='产物清单 JSON（_setup/ogl_assets.py 生成）')
    args = ap.parse_args()

    assets_map = load_assets(args.assets)
    dates = {tag: info['published_at'][:10]
             for tag, info in assets_map.items() if info.get('published_at')}

    posts_dir = os.path.join(HERE, '_posts')
    os.makedirs(posts_dir, exist_ok=True)

    written = 0
    for path in sorted(glob.glob(os.path.join(args.release_notes_dir, 'v*.md'))):
        tag = os.path.basename(path)[:-3]
        body = open(path, encoding='utf-8').read().strip()
        date = dates.get(tag) or FALLBACK_DATES.get(tag)
        if not date:
            print('[skip] 无日期：%s' % tag)
            continue

        title = 'OhGithubLost %s · %s' % (version_label(tag), channel_of(tag))
        front = (
            '---\n'
            'layout: post\n'
            'title: "%s"\n'
            'date: %s\n'
            'categories: [release]\n'
            'version: %s\n'
            '---\n\n' % (title, date, tag)
        )
        tail = build_downloads(tag, assets_map)
        content = front + strip_leading_title(body) + '\n' + '\n'.join(tail) + '\n'

        out = os.path.join(posts_dir, '%s-%s.md' % (date, tag))
        with open(out, 'w', encoding='utf-8') as handle:
            handle.write(content)
        print('[ok] %s-%s.md  %s' % (date, tag, title))
        written += 1

    print('生成 %d 篇日志' % written)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())