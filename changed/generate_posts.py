#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `changed/_content/<tag>.md` 生成为 Jekyll _posts（更新日志站点用）。

输入：
  _content/<tag>.md     面向使用者的正文（写作规范见 _content/_STYLE.md）
  releases.json         已发布版本清单与产物（由 GitHub Releases 导出）

规则：
  1. 站点只收录**已发布**的版本（releases.json 中存在的版本）；
  2. 从未发布的版本，其内容已按合并规则并入其后第一个已发布版本的正文，
     本脚本不单独成文；
  3. 正文下方按平台追加该版本安装包的下载入口；
  4. 写入前清除同一版本的历史文章，避免同版本重复出现。
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re

CST = dt.timezone(dt.timedelta(hours=8))

HERE = os.path.dirname(os.path.abspath(__file__))

# 平台归类：按产物名中的平台关键字分组，顺序即展示顺序。
PLATFORMS = [
    ('Android', ('android',)),
    ('Windows', ('windows',)),
    ('Linux', ('linux',)),
]

CHANNEL = {
    'alpha': '内测版',
    'beta': '公测版',
}

def channel_of(tag: str) -> str:
    match = re.search(r'-(alpha|beta)$', tag)
    return CHANNEL[match.group(1)] if match else '正式版'

def version_label(tag: str) -> str:
    return re.sub(r'-(alpha|beta)$', '', tag.lstrip('v'))

def human_size(num: int) -> str:
    mb = num / (1024 * 1024)
    return ('%.0f MB' % mb) if mb >= 10 else ('%.1f MB' % mb)

def download_section(tag: str, info: dict) -> str:
    assets = info.get('assets') or []
    if not assets:
        return ''

    # 只列 zip：7z 与之内容相同，逐条罗列会让页面变成文件清单。
    zips = [a for a in assets if a['name'].lower().endswith('.zip')]
    if not zips:
        zips = assets

    lines = ['', '## 下载', '']
    for label, keys in PLATFORMS:
        items = sorted(
            (a for a in zips if any(k in a['name'].lower() for k in keys)),
            key=lambda a: a['name'])
        if not items:
            continue
        lines += ['**%s**' % label, '', '| 文件 | 大小 |', '| --- | ---: |']
        for a in items:
            lines.append('| [%s](%s) | %s |' % (a['name'], a['url'], human_size(a['size'])))
        lines.append('')

    lines.append('> 每个安装包另提供 7z 压缩格式；完整产物清单与校验信息见 '
                 '[发布页面](%s)。' % info.get('html_url', ''))
    return '\n'.join(lines)

def post_datetime(published_at: str) -> str:
    """把发布时刻换算成站点时区，同一时刻的先后决定列表顺序。"""
    moment = dt.datetime.fromisoformat(published_at.replace('Z', '+00:00'))
    return moment.astimezone(CST).strftime('%Y-%m-%d %H:%M:%S +0800')

def summary_of(body: str, limit: int = 90) -> str:
    for block in body.split('\n\n'):
        text = block.strip()
        if not text or text.startswith('#') or text.startswith('-'):
            continue
        text = re.sub(r'[`*_>]', '', text)
        text = re.sub(r'\s+', ' ', text)
        return text if len(text) <= limit else text[:limit - 1] + '…'
    return ''

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--content-dir', default=os.path.join(HERE, '_content'))
    parser.add_argument('--releases', default=os.path.join(HERE, 'releases.json'))
    args = parser.parse_args()

    with open(args.releases, encoding='utf-8') as handle:
        releases = json.load(handle)

    published = sorted(
        (tag for tag in releases if tag.startswith('v')),
        key=lambda tag: (releases[tag]['published_at'], tag))

    posts_dir = os.path.join(HERE, '_posts')
    os.makedirs(posts_dir, exist_ok=True)

    # 清掉所有旧文章：版本集合与合并规则都在本脚本里，残留即错误。
    for stale in glob.glob(os.path.join(posts_dir, '*.md')):
        os.remove(stale)

    written = 0
    for tag in published:
        body_path = os.path.join(args.content_dir, tag + '.md')
        if not os.path.isfile(body_path):
            print('[缺失] 无正文：%s' % tag)
            continue

        with open(body_path, encoding='utf-8') as handle:
            body = handle.read().strip()

        info = releases[tag]
        date = info['published_at'][:10]
        stamp = post_datetime(info['published_at'])
        title = '%s %s' % (version_label(tag), channel_of(tag))
        description = summary_of(body)

        front = (
            '---\n'
            'title: "%s"\n'
            'date: %s\n'
            'categories: [发布]\n'
            'version: %s\n'
            % (title, stamp, tag)
        )
        if description:
            front += 'description: "%s"\n' % description.replace('"', '\\"')
        front += '---\n\n'

        content = front + body + '\n' + download_section(tag, info) + '\n'

        out = os.path.join(posts_dir, '%s-%s.md' % (date, tag))
        with open(out, 'w', encoding='utf-8') as handle:
            handle.write(content)
        print('[ok] %s  %s' % (os.path.basename(out), title))
        written += 1

    print('生成 %d 篇日志（已发布版本 %d 个）' % (written, len(published)))
    return 0 if written == len(published) else 1

if __name__ == '__main__':
    raise SystemExit(main())
