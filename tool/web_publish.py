#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把构建好的 Web 产物按版本发布到 `app/`，并重写 `app/index.html`。

## 目录约定
```
app/
  index.html          ← **入口**：一个 iframe 包裹当前版本（始终指向最新）
  versions.json       ← 已发布版本清单（新版本在前）
  740/                ← 某个版本的完整 Web 产物
    index.html …
  722/
    …
```

## 为什么用 iframe 而不是把产物直接铺在 `app/` 根下
版本目录并存时，根下只能放一份。用 iframe 包一层，好处是：
- **旧版本继续可访问**（`app/740/…`），便于对比与回退；
- 入口地址 `app/` 永远不变，外部链接不需要跟着版本改；
- 版本切换只是改 iframe 的 `src`。

## 用法
    python3 tool/web_publish.py <构建产物目录> <版本号>
例：  python3 tool/web_publish.py build/web 7.4.0
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def version_dir_name(version: str) -> str:
    """版本号 → 目录名：**纯数字**（`7.1.0` → `710`）。

    目录名只保留数字，便于按顺序排列，也便于手工拼 URL。
    """
    digits = re.sub(r'[^0-9]', '', version)
    if not digits:
        raise ValueError('版本号里没有数字：%r' % version)
    return digits


WRAPPER = """<!DOCTYPE html>
<!--
  OGL Web · 入口页（**自动生成，请勿手改** —— 见 tool/web_publish.py）。

  作用：把当前版本的应用包在 iframe 里，使根地址长期不变、各版本目录并存。
  版式按屏幕自适应：iframe 占满可视区域（含移动端安全区）。
  加载期间显示进度条（loading → loaded 淡出）。
-->
<html lang="zh">
<head>
  <meta charset="UTF-8">
  <!-- viewport-fit=cover：让内容铺到刘海/圆角屏的安全区，再由 CSS 的 env() 让出边距 -->
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <title>OhGithubLost · Web</title>
  <meta name="theme-color" content="#171A21">
  <link rel="icon" type="image/png" href="__CURRENT__/favicon.png">
  <style>
    :root {
      --safe-top: env(safe-area-inset-top, 0px);
      --safe-right: env(safe-area-inset-right, 0px);
      --safe-bottom: env(safe-area-inset-bottom, 0px);
      --safe-left: env(safe-area-inset-left, 0px);
      --ink: #E6EDF3;
      --panel: #1E222B;
      --line: #454B5A;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0; padding: 0;
      width: 100%; height: 100%;
      background: #171A21; color: var(--ink);
      font: 13px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      overscroll-behavior: none;
    }
    #app {
      position: fixed;
      top: 0; right: 0; bottom: 0; left: 0;
      width: 100%; height: 100%;
      height: 100dvh;
      border: 0;
      display: block;
      background: #171A21;
    }
    /* 加载进度条：iframe 加载中显示，onload 后淡出 */
    #loader {
      position: fixed;
      top: 0; right: 0; bottom: 0; left: 0;
      z-index: 99;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      gap: 18px;
      background: #171A21;
      transition: opacity 0.4s ease;
    }
    #loader.hidden { opacity: 0; pointer-events: none; }
    #loader .logo {
      font: 600 22px system-ui, sans-serif;
      color: #E6EDF3;
      letter-spacing: 1px;
    }
    #loader .bar {
      width: min(240px, 60vw);
      height: 3px;
      background: #2F3441;
      border-radius: 2px;
      overflow: hidden;
      position: relative;
    }
    #loader .bar::after {
      content: '';
      position: absolute;
      top: 0; left: -60%;
      width: 60%; height: 100%;
      background: linear-gradient(90deg, transparent, #4B9FFF, transparent);
      animation: slide 1.4s ease-in-out infinite;
    }
    @keyframes slide {
      0% { left: -60%; }
      100% { left: 100%; }
    }
    #loader .hint {
      font: 12px system-ui, sans-serif;
      color: #454B5A;
    }
  </style>
</head>
<body>
  <div id="loader">
    <div class="logo">OGL</div>
    <div class="bar"></div>
    <div class="hint">加载中…</div>
  </div>
  <iframe id="app" src="__CURRENT__/" title="OhGithubLost" allow="clipboard-write; fullscreen"></iframe>
  <script>
    (function () {
      var loader = document.getElementById('loader');
      var frame = document.getElementById('app');
      // iframe onload = HTML 文档已加载完成（Flutter 引擎还在初始化，但基础资源没有 404）
      frame.addEventListener('load', function () {
        loader.classList.add('hidden');
        setTimeout(function () { loader.style.display = 'none'; }, 500);
      });
      // 超时兜底：20 秒后也淡出（不让进度条永远卡着）
      setTimeout(function () {
        loader.classList.add('hidden');
        setTimeout(function () { loader.style.display = 'none'; }, 500);
      }, 20000);
    })();
  </script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description='把 Web 产物按版本发布到 app/')
    ap.add_argument('build_dir', help='构建产物目录（如 build/web）')
    ap.add_argument('version', help='版本号（如 7.4.0）')
    ap.add_argument('--app-dir', default=os.path.join(ROOT, 'app'))
    args = ap.parse_args()

    if not os.path.isdir(args.build_dir):
        sys.stderr.write('构建产物目录不存在：%s\n' % args.build_dir)
        return 1
    if not os.path.isfile(os.path.join(args.build_dir, 'index.html')):
        sys.stderr.write('%s 里没有 index.html —— 看起来不是 Flutter Web 产物\n'
                         % args.build_dir)
        return 1

    app_dir = args.app_dir
    dir_name = version_dir_name(args.version)
    target = os.path.join(app_dir, dir_name)
    os.makedirs(app_dir, exist_ok=True)
    # ★ 版本目录策略：历史版本一律保留；同一版本重发只重建自己那一个目录。
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(args.build_dir, target)

    # ★ 修正 `<base href>`：`flutter build web` 默认写 `/`（域名根目录），
    #   但产物部署在 `app/<版本>/` 子路径下 —— 不改的话浏览器会去域名根
    #   目录找 `main.dart.js`（404 → 白屏）。
    #   改为 `./`（相对路径），无论部署在哪一层子路径都能正确解析。
    idx_html = os.path.join(target, 'index.html')
    if os.path.isfile(idx_html):
        with open(idx_html, encoding='utf-8') as fh:
            html = fh.read()
        fixed = html.replace('<base href="/">', '<base href="./">')
        if fixed != html:
            with open(idx_html, 'w', encoding='utf-8') as fh:
                fh.write(fixed)
            print('  [修正] index.html base href: / → ./')
        else:
            print('  [跳过] index.html 无 <base href="/"> 或已修正')
    print('已发布 %s → %s' % (args.version, os.path.relpath(target, ROOT)))

    # 版本清单（新版本在前；同版本去重）
    manifest_path = os.path.join(app_dir, 'versions.json')
    entries = []
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, encoding='utf-8') as fh:
                entries = [e for e in json.load(fh)
                           if isinstance(e, dict) and e.get('dir') != dir_name]
        except Exception:
            entries = []
    entries.insert(0, {'version': args.version, 'dir': dir_name})
    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=2)
        fh.write('\n')

    # 入口页：指向刚发布的版本
    with open(os.path.join(app_dir, 'index.html'), 'w', encoding='utf-8') as fh:
        fh.write(WRAPPER.replace('__CURRENT__', dir_name))
    print('已重写 app/index.html → iframe 指向 %s/' % dir_name)
    print('已更新 app/versions.json（共 %d 个版本）' % len(entries))
    return 0


if __name__ == '__main__':
    sys.exit(main())
