#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把构建好的 Web 产物按版本发布到 `app/`，并重写 `app/index.html`。

## 目录约定
```
app/
  index.html          ← **入口**：一个 iframe 包裹当前版本（始终指向最新）
  versions.json       ← 已发布版本清单（新版本在前）
  v650/               ← 某个版本的完整 Web 产物
    index.html …
  v640/
    …
```

## 为什么用 iframe 而不是把产物直接铺在 `app/` 根下
版本目录并存时，根下只能放一份。用 iframe 包一层，好处是：
- **旧版本继续可访问**（`app/v640/…`），便于对比与回退；
- 入口地址 `app/` 永远不变，外部链接不需要跟着版本改；
- 版本切换只是改 iframe 的 `src`。

## 用法
    python3 tool/web_publish.py <构建产物目录> <版本号>
例：  python3 tool/web_publish.py build/web 6.5.0
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
  版式按屏幕自适应：iframe 占满可视区域（含移动端安全区），版本切换条在
  窄屏上仍可点（触控目标不小于 32px），横屏与小屏都不会溢出。
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
      /* 移动端安全区；桌面浏览器里 env() 取 0，不影响布局 */
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
    /* 用 dvh 而不是 vh：移动端地址栏收放时不会把底部内容顶出屏幕。
       不支持的浏览器回退到 100%（由 html/body 的高度兜住）。 */
    #app {
      position: fixed;
      top: 0; right: 0; bottom: 0; left: 0;
      width: 100%; height: 100%;
      height: 100dvh;
      border: 0;
      display: block;
      background: #171A21;
    }
    /* 版本切换：默认贴右下角，避开安全区 */
    #bar {
      position: fixed;
      right: calc(10px + var(--safe-right));
      bottom: calc(10px + var(--safe-bottom));
      z-index: 9;
      display: flex; flex-direction: column; align-items: flex-end;
      gap: 6px;
      max-width: min(60vw, 240px);
    }
    #toggle {
      min-height: 32px; min-width: 32px;
      padding: 6px 12px;
      background: var(--panel); color: var(--ink);
      border: 1px solid var(--line); border-radius: 8px;
      font: inherit; cursor: pointer;
      /* 触控反馈 */
      -webkit-tap-highlight-color: transparent;
    }
    #toggle:active { background: #2F3441; }
    #list {
      display: none;
      width: 100%;
      max-height: min(40vh, 320px);
      overflow: auto;
      background: var(--panel);
      border: 1px solid var(--line); border-radius: 8px;
      padding: 4px 0;
      -webkit-overflow-scrolling: touch;
    }
    #list a {
      display: block;
      padding: 8px 14px;
      color: var(--ink); text-decoration: none;
      white-space: nowrap;
      min-height: 32px;
    }
    #list a:hover, #list a:focus { background: #2F3441; }
    #list a.cur { color: #FFC93C; }
    /* 横屏（高度很小）时把切换条压得更扁，避免挡住应用内容 */
    @media (max-height: 420px) {
      #bar { bottom: calc(6px + var(--safe-bottom)); }
      #list { max-height: 60vh; }
    }
    /* 桌面：字号略大，切换条不贴着边缘 */
    @media (min-width: 900px) {
      #bar { right: calc(16px + var(--safe-right)); bottom: calc(16px + var(--safe-bottom)); }
    }
  </style>
</head>
<body>
  <iframe id="app" src="__CURRENT__/" title="OhGithubLost" allow="clipboard-write; fullscreen"></iframe>
  <div id="bar">
    <div id="list" role="menu" aria-label="版本列表"></div>
    <button id="toggle" type="button" aria-expanded="false" aria-controls="list">版本</button>
  </div>
  <script>
    (function () {
      var CUR = '__CURRENT__';
      var list = document.getElementById('list');
      var toggle = document.getElementById('toggle');
      var frame = document.getElementById('app');

      function setOpen(open) {
        list.style.display = open ? 'block' : 'none';
        toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
      }
      toggle.addEventListener('click', function () {
        setOpen(list.style.display !== 'block');
      });
      // 点空白处收起（iframe 内点击收不到事件，故只在文档区域生效）
      document.addEventListener('click', function (e) {
        if (!document.getElementById('bar').contains(e.target)) setOpen(false);
      });

      // 版本清单：versions.json；切换只改 iframe 的 src，不刷新外层
      fetch('versions.json', { cache: 'no-store' })
        .then(function (r) { return r.ok ? r.json() : []; })
        .then(function (items) {
          (items || []).forEach(function (v) {
            if (!v || !v.dir) return;
            var a = document.createElement('a');
            a.textContent = v.version || v.dir;
            a.href = v.dir + '/';
            if (v.dir === CUR) { a.className = 'cur'; a.setAttribute('aria-current', 'true'); }
            a.addEventListener('click', function (ev) {
              ev.preventDefault();
              frame.src = v.dir + '/';
              setOpen(false);
            });
            list.appendChild(a);
          });
          if (!list.childNodes.length) toggle.style.display = 'none';
        })
        .catch(function () { toggle.style.display = 'none'; });
    })();
  </script>
</body>
</html>
"""

def main() -> int:
    ap = argparse.ArgumentParser(description='把 Web 产物按版本发布到 app/')
    ap.add_argument('build_dir', help='构建产物目录（如 build/web）')
    ap.add_argument('version', help='版本号（如 6.5.0）')
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
    # 同版本重发：先清掉旧的，避免残留上一轮的文件。
    if os.path.isdir(target):
        shutil.rmtree(target)
    shutil.copytree(args.build_dir, target)
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
