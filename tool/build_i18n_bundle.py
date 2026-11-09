#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Web Lite 性能：把每语言 i18n 分片合并为 1 个 bundle.json。

启动时 OgLI18n 只发 1 次 HTTP 请求（旧路径为 27~28 次）。
只合并 og_l_i18n.dart 的 pages 注册项；未注册的分片不进 bundle（Web
精简后残留的旧页分片由本脚本一并删除，减小发布包）。
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
I18N = ROOT / 'assets' / 'i18n'
I18N_DART = ROOT / 'lib' / 'surface' / 'i18n' / 'og_l_i18n.dart'


def registered_pages() -> list[str]:
    text = I18N_DART.read_text(encoding='utf-8')
    m = re.search(r'static const List<String> pages = <String>\[(.*?)\];',
                  text, re.S)
    if not m:
        raise SystemExit('无法从 og_l_i18n.dart 解析 pages 清单')
    return re.findall(r"'([^']+)'", m.group(1))


def main() -> int:
    pages = registered_pages()
    print(f'注册分片: {len(pages)}')
    for lang_dir in sorted(I18N.iterdir()):
        if not lang_dir.is_dir():
            continue
        bundle = {}
        for page in pages:
            shard = lang_dir / f'{page}.json'
            if not shard.exists():
                print(f'  [警告] {lang_dir.name}/{page}.json 缺失')
                continue
            with open(shard, encoding='utf-8') as fh:
                bundle[page] = json.load(fh)
        # 分片保留（i18n_scan 的权威源、bundle 缺失时的回退路径）；
        # 不进 bundle 的旧页分片不会被网络加载，仅占构建产物极小体积。
        out = lang_dir / 'bundle.json'
        with open(out, 'w', encoding='utf-8') as fh:
            json.dump(bundle, fh, ensure_ascii=False, indent=2, sort_keys=True)
            fh.write('\n')
        print(f'{lang_dir.name}: {len(bundle)} 页 -> bundle.json '
              f'({out.stat().st_size} bytes)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
