#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把构建好的 Web 产物按版本发布到 `app/`，并重写 `app/index.html`。

## 目录约定
```
app/
  index.html          ← **入口**：一个 iframe 包裹当前版本（始终指向最新）
  versions.json       ← 已发布版本清单（新版本在前）
  740/                ← 主版本（默认 variant=''）的产物
    index.html …
  722/
    …
  wasm/               ← --subdir wasm 时的产物桶
    740/
      …
  js/                 ← --subdir js 时的产物桶
    740/
      …
```

## 为什么用 iframe 而不是把产物直接铺在 `app/` 根下
版本目录并存时，根下只能放一份。用 iframe 包一层，好处是：
- **旧版本继续可访问**（`app/740/…`），便于对比与回退；
- 入口地址 `app/` 永远不变，外部链接不需要跟着版本改；
- 版本切换只是改 iframe 的 `src`。

## variant 桶（--subdir）
同一版本可能有多份产物（Flutter Web 的 wasm 编译、js 编译、canvaskit…），
用 ``--subdir <name>`` 分桶部署到 ``app/<name>/<version>/``：
- 默认（不传）→ ``app/<version>/``，并刷新 ``app/index.html`` 入口；
- ``--subdir wasm`` → ``app/wasm/<version>/``；
- ``--subdir js``   → ``app/js/<version>/``。

``versions.json`` 每条 entry 增加 ``'variant'`` 字段（默认空串），
旧 consumer 读不到字段用 ``.get('variant', '')`` 兜底，向后兼容。

## 入口页 wasm/js 嗅探分流
``app/index.html`` 不论传不传 ``--subdir`` 都会被重写。顶部 ``<script>``
同步嗅探 WebAssembly（含 GC 提案），把 ``window.__OGL_VARIANT__`` 写为
``'wasm'`` 或 ``'js'``，随后由底部脚本拼出
``./wasm/<版本>/`` 或 ``./js/<版本>/`` 作为 iframe 的 src。
模板里的 ``__CURRENT__`` 占位符被替换为版本纯数字目录名（供 favicon），
``__OGL_VERSION__`` 被替换为 ``args.version``（供底部 JS 做变体决定）。

## 用法
    python3 tool/web_publish.py <构建产物目录> <版本号> [--subdir wasm|js]
例：  python3 tool/web_publish.py build/web        7.4.0
     python3 tool/web_publish.py build/web-wasm    7.4.2 --subdir wasm
     python3 tool/web_publish.py build/web-js      7.4.2 --subdir js
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


def app_path_with_subdir(app_root: str, subdir: str, version_dir: str) -> str:
    """``app/<subdir>/<version>/`` —— 不传 ``subdir`` 则回落到 ``app/<version>/``。

    同一版本按 variant（wasm / js / …）分桶部署，互不覆盖。
    入口页 ``app/index.html`` 仍位于 ``app_root`` 本身，不会被推到 ``subdir`` 下。
    """
    if subdir:
        return os.path.join(app_root, subdir, version_dir)
    return os.path.join(app_root, version_dir)


def _read_manifest(manifest_path: str) -> list:
    """读取 ``versions.json``；不存在或解析失败 → 空列表。"""
    if not os.path.isfile(manifest_path):
        return []
    try:
        with open(manifest_path, encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception:
        return []
    return [e for e in data if isinstance(e, dict)]


def _dedupe(entries: list, *, dir_name: str, variant: str) -> list:
    """去重：同一 ``(dir, variant)`` 只留最新一条（保留列表里最靠前的）。"""
    seen = set()
    out = []
    for e in entries:
        key = (e.get('dir'), e.get('variant') or '')
        if key == (dir_name, variant):
            # 同 dir+variant 视为同一条：新发布优先
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(e)
    return out


# ── Netlify `_headers`（**必须放在发布根**）──────────────────────────────
# 关键：Netlify 只读取**发布根**（本站为 `app/`）下的 `_headers`。
# 把 `_headers` 放进各版本桶（`app/js/<v>/_headers`）**不会生效**——
# 站点曾因此对所有资源返回 `max-age=0, must-revalidate`，每次访问都要
# 回源校验（v7.4.3 上线时实测到的）。
#
# 策略：
#   · 入口与清单（`/`、`/index.html`、`/versions.json`）→ 每次校验，
#     保证发新版本后立刻可见；
#   · 版本化产物（`/wasm/**`、`/js/**`、`/7xx/**`）→ 目录名带版本号、
#     内容不随同名文件变化 → 一年 `immutable`，二次访问零请求。
ROOT_HEADERS = """\
# 入口与版本清单：始终回源校验（新版本要立刻可见）
/
  Cache-Control: public, max-age=0, must-revalidate
/index.html
  Cache-Control: public, max-age=0, must-revalidate
/versions.json
  Cache-Control: public, max-age=0, must-revalidate

# 版本化产物桶：目录名含版本号 → 内容不可变 → 强缓存一年
/wasm/*
  Cache-Control: public, max-age=31536000, immutable
/js/*
  Cache-Control: public, max-age=31536000, immutable

# 历史纯数字目录（7xx / v7xx）
/7*
  Cache-Control: public, max-age=31536000, immutable
/v7*
  Cache-Control: public, max-age=31536000, immutable
"""


WRAPPER = """<!DOCTYPE html>
<!--
  OGL Web · 入口页（**自动生成，请勿手改** —— 见 tool/web_publish.py）。

  作用：嗅探浏览器 WebAssembly（含 GC 提案）支持情况，按需把当前版本的
  应用包在 iframe 里：
    - 支持 → iframe → ./wasm/<版本>/index.html  （dart2wasm，体积极小、首屏快）
    - 不支持 → iframe → ./js/<版本>/index.html   （dart2js 兜底，兼容老 Safari）

  版式按屏幕自适应：iframe 占满可视区域（含移动端安全区）。
  加载期间显示进度条（loading → loaded 淡出）。

  iOS Safari 用户：若希望获得接近原生 App 的体验与全屏画板，请
  在浏览器中点击底部分享按钮 → "添加到主屏幕"。
-->
<html lang="zh">
<head>
  <meta charset="UTF-8">
  <!-- viewport-fit=cover：让内容铺到刘海/圆角屏的安全区，再由 CSS 的 env() 让出边距 -->
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <title>OhGithubLost · Web</title>
  <meta name="theme-color" content="#171A21">
  <link rel="icon" type="image/png" href="js/__CURRENT__/favicon.png">
  <!-- WebAssembly 嗅探：必须在 iframe 拿到 src 之前同步执行完毕；
       dart2wasm 需要 Wasm GC（struct/array ref）提案，旧 Safari 不支持。 -->
  <script>
    (function() {
      try {
        // 基础嗅探：WebAssembly 是否存在 + 最小模块验证
        // 字节序列：\\0asm\\1\\0\\0\\0\\1\\5\\1\\0\\5  (magic + version + 1 type + 1 func + 1 table)
        if (typeof WebAssembly === 'undefined' ||
            !WebAssembly.validate ||
            !WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,0,5]))) {
          window.__OGL_VARIANT__ = 'js';
          return;
        }
        // 二次探测：Wasm GC struct/array ref 提案（dart2wasm 必需）
        // 字节序列（参考 webassembly feature detect）：包含 (ref any) / (ref struct) 等类型
        if (!WebAssembly.validate(new Uint8Array([
          0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
          0x01, 0x0d, 0x03, 0x60, 0x01, 0x6e, 0x60, 0x00,
          0x60, 0x02, 0x6e, 0x6e, 0x01, 0x6e
        ]))) {
          window.__OGL_VARIANT__ = 'js';
          return;
        }
        window.__OGL_VARIANT__ = 'wasm';
      } catch (e) {
        window.__OGL_VARIANT__ = 'js';
      }
    })();
  </script>
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
    #ogl-frame {
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
  <!-- iOS Safari 提示：通过"添加到主屏幕"启动可获得全屏 + 离线缓存（更像原生 App） -->
  <noscript>
    <div style="position:fixed;top:env(safe-area-inset-top,8px);left:8px;right:8px;z-index:100;
                padding:10px 14px;border-radius:10px;background:#1E222B;color:#E6EDF3;
                font:13px/1.5 system-ui,-apple-system,sans-serif;">
      本页面需要启用 JavaScript 才能加载 OGL Web 应用。请在浏览器设置中开启 JS 后刷新页面。
    </div>
  </noscript>
  <div id="loader">
    <div class="logo">OGL</div>
    <div class="bar"></div>
    <div class="hint">加载中…</div>
  </div>
  <!-- ★ iframe 直接指向本版本的**默认目录**（`__CURRENT__/`），该目录已由 CI
       发布，**零 404、零额外探测请求**。
       为什么不在这里做 wasm/js 嗅探：iframe 即使加载到 404 页也只会触发
       `load`（不是 `error`），"嗅探失败再回退"在 iframe 上根本不可靠。
       等 wasm 桶真正上 CI 之后，改为服务端写死路径（或改用 fetch 预检），
       在此之前——稳定优先，直接命中 js 产物。 -->
  <iframe id="ogl-frame" src="about:blank" title="OhGithubLost" allow="clipboard-write; fullscreen; notifications"></iframe>
  <script>
    (function () {
      var f = document.getElementById('ogl-frame');
      var version = '__OGL_VERSION__';
      // 版本号 → 纯数字目录名（与 version_dir_name() 规则一致）：'7.4.2' → '742'
      var dir = version.replace(/[^0-9]/g, '');
      // 头部同步嗅探已把结果写入 window.__OGL_VARIANT__（'wasm' | 'js'）；
      // 两个桶都由 CI 发布：app/wasm/<dir>/ 与 app/js/<dir>/。
      var variant = window.__OGL_VARIANT__ || 'js';
      f.src = variant === 'wasm'
        ? './wasm/' + dir + '/'
        : './js/' + dir + '/';
      var loader = document.getElementById('loader');
      // iframe onload = HTML 文档已加载完成（Flutter 引擎还在初始化，但基础资源没有 404）
      f.addEventListener('load', function () {
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
    ap.add_argument('--subdir', default='',
                    help='variant 子目录（如 wasm / js），默认空串 ⇒ 部署到 app/<版本>/。'
                         '传 wasm ⇒ app/wasm/<版本>/；js ⇒ app/js/<版本>/。'
                         '入口页 app/index.html 始终在 app/ 根下，不受 --subdir 影响。')
    args = ap.parse_args()

    if not args.subdir == args.subdir.strip() or '/' in args.subdir or '\\' in args.subdir:
        sys.stderr.write('--subdir 不能含路径分隔符或首尾空白：%r\n' % args.subdir)
        return 1
    variant = args.subdir.strip()

    if not os.path.isdir(args.build_dir):
        sys.stderr.write('构建产物目录不存在：%s\n' % args.build_dir)
        return 1
    if not os.path.isfile(os.path.join(args.build_dir, 'index.html')):
        sys.stderr.write('%s 里没有 index.html —— 看起来不是 Flutter Web 产物\n'
                         % args.build_dir)
        return 1

    app_dir = args.app_dir
    dir_name = version_dir_name(args.version)
    target = app_path_with_subdir(app_dir, args.subdir, dir_name)
    # ★ 入口页始终在 app/ 根下；不同 variant 的产物推到各自子目录。
    os.makedirs(app_dir, exist_ok=True)
    if args.subdir:
        os.makedirs(os.path.dirname(target), exist_ok=True)
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

    # ★ 关闭 Flutter 的 service worker 注册。
    #   资源可能从镜像（fastly.jsdelivr.net 等）加载，而 Service Worker
    #   **必须是同源**才能注册 —— 跨源注册会抛错，Flutter 虽会捕获，但
    #   控制台噪音大、部分版本还会等它超时，拖慢启动。
    #   替代方案是强缓存：发布根 `_headers` 对 `/wasm/*`、`/js/*` 写了一年
    #   `immutable`，二次访问零请求，效果不比 SW 差。
    #   另外 Flutter 自己在生成代码里就标注了：
    #     "Flutter's service worker is deprecated and will be removed…"
    bs_path = os.path.join(target, 'flutter_bootstrap.js')
    if os.path.isfile(bs_path):
        with open(bs_path, encoding='utf-8') as fh:
            bs = fh.read()
        new_bs = re.sub(r'serviceWorkerSettings:\s*\{[^{}]*\}',
                        'serviceWorkerSettings: undefined', bs)
        if new_bs != bs:
            with open(bs_path, 'w', encoding='utf-8') as fh:
                fh.write(new_bs)
            print('  [修正] flutter_bootstrap.js 关闭 service worker（跨源注册必失败）')
        else:
            print('  [跳过] flutter_bootstrap.js 未找到 serviceWorkerSettings')

    print('已发布 %s → %s' % (args.version, os.path.relpath(target, ROOT)))

    # 版本清单（新版本在前；按 (dir, variant) 去重）
    #   entry = {'version': '7.4.2', 'dir': '742', 'variant': 'wasm' | 'js' | ''}
    #   variant 字段向后兼容：旧 consumer 读取时按 .get('variant', '') 不会 KeyError。
    #
    # 双桶各写各的 entry：`_dedupe` 按 `(dir, variant)` 去重，两条共存不互相
    # 覆盖。入口页 index.html 两次写入内容**完全相同**（都由 args.version +
    # 数字目录算出），无论先后都一致。
    manifest_path = os.path.join(app_dir, 'versions.json')
    entries = _read_manifest(manifest_path)
    entries = _dedupe(entries, dir_name=dir_name, variant=variant)
    entry = {'version': args.version, 'dir': dir_name, 'variant': variant}
    entries.insert(0, entry)
    with open(manifest_path, 'w', encoding='utf-8') as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=2)
        fh.write('\n')

    # 入口页：每次发布都重写 —— 它就是带 wasm/js 嗅探分流的统一入口页。
    #
    # 占位符约定：
    #   __CURRENT__       → 版本纯数字目录名（如 '742'），用于 <link rel="icon">
    #                        与旧版本兼容，仍指向默认部署目录（不带 variant 前缀）
    #   __OGL_VERSION__   → 原始版本号字符串（如 '7.4.2'），由底部 JS 做 wasm/js 分流
    wrapper = (WRAPPER
               .replace('__CURRENT__', dir_name)
               .replace('__OGL_VERSION__', args.version))
    with open(os.path.join(app_dir, 'index.html'), 'w', encoding='utf-8') as fh:
        fh.write(wrapper)
    print('已重写 app/index.html → wasm 嗅探分流 → 版本 %s (variant=wasm|js)'
          % args.version)
    print('已更新 app/versions.json（共 %d 个版本）' % len(entries))

    # ★ Netlify 缓存策略文件**必须写在发布根**（app/_headers），
    #   写在版本桶里不生效（详见 ROOT_HEADERS 注释）。
    headers_path = os.path.join(app_dir, '_headers')
    with open(headers_path, 'w', encoding='utf-8') as fh:
        fh.write(ROOT_HEADERS)
    print('已写入 app/_headers（Netlify 发布根缓存策略）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
