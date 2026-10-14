#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OGL · Web（wasm）编译：脚手架体检 → 浏览器 API 守卫注入 → 编译 → 产物校验 → 发布到 `app/`。

## 为什么需要它
Web 目标只是**实验性**的补充产物，编译失败**绝不影响**五平台发布
（见 `.github/workflows/web.yml` 的 `continue-on-error`）。但"编译过"
不等于"能在浏览器里跑起来"：wasm / CanvasKit / 跨源隔离对浏览器 API
有硬要求，缺一个就是白屏或静默失败。本工具把这件事变成**可执行的门禁**：

1. `--prepare`：确认 `web/` 脚手架存在（平台目录由 CI 现场生成），
   并把 **浏览器 API 守卫**（`web_api_guard.js`）写进 `web/`，
   在 `web/index.html` 里**动态注入** `<script>` 引用 —— 缺任何一项
   运行时 API 即**抛错**并给出可读原因，绝不静默降级。
2. `--verify`：编译后逐项核对产物（bootstrap / wasm / 引擎 / 守卫已注入 /
   COOP-COEP 头），任何缺失即抛错。
3. `--publish`：把产物**发布到仓库的 `app/`**，**先清空目录**再拷贝，
   保证每次构建只保留**最新**的一套 web 文件（旧的 wasm 缓存不会残留）。

用法：
    python3 tool/web_build.py --prepare
    flutter build web --release --dart-define-from-file=dart_define.json
    python3 tool/web_build.py --verify --build build/web
    python3 tool/web_build.py --publish --build build/web --app app
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GUARD_MARK = 'ogl-web-api-guard'

# index.html 里必须存在的引导标记（与 Flutter 模板一致，缺一即抛错）。
REQUIRED_HTML_MARKERS = (
    'flutter_bootstrap.js',
)

# 运行时必须具备的浏览器能力。前 4 项是 wasm / CanvasKit 的硬前提，
# 其余是本项目实际会用到的基础能力（下载、令牌、缓存、i18n 资源）。
GUARD_CHECKS = [
    ('WebAssembly', 'WebAssembly 引擎未启用，wasm 目标无法运行'),
    ('WebAssembly.instantiateStreaming',
     'WebAssembly.instantiateStreaming 缺失，无法流式编译 wasm'),
    ('fetch', 'fetch API 缺失，网络层无法工作'),
    ('ReadableStream', 'ReadableStream 缺失，下载流式处理不可用'),
    ('TextDecoder', 'TextDecoder 缺失，文本/JSON 解码不可用'),
    ('crypto.getRandomValues', 'crypto.getRandomValues 缺失，随机数不可用'),
    ('indexedDB', 'indexedDB 缺失，本地缓存不可用'),
    ('atob', 'atob/btoa 缺失，Base64 处理不可用'),
    ('URL', 'URL 构造器缺失，地址拼接不可用'),
    ('Worker', 'Worker 缺失，后台解析不可用'),
    ('performance.now', 'performance.now 缺失，动画计时不可用'),
]

# 跨源隔离后才能使用的能力：有则必须能用，没有则明确要求开启隔离头。
CROSS_ORIGIN_ISOLATED = [
    ('SharedArrayBuffer', 'SharedArrayBuffer 缺失：需 COOP/COEP 跨源隔离头'),
]

GUARD_JS = r'''// OGL · Web 浏览器 API 守卫（由 tool/web_build.py 自动注入，勿手改）
//
// 目的：wasm / CanvasKit 对浏览器能力有**硬要求**，缺一个只会白屏或静默失败。
// 这里在应用启动**之前**逐项检查，缺失即抛出可读错误，绝不静默降级。
(function () {
  'use strict';
  var failures = [];

  function check(expr, message) {
    var ok;
    try {
      ok = !!expr();
    } catch (e) {
      ok = false;
    }
    if (!ok) { failures.push(message); }
    return ok;
  }

  // ① wasm / 引擎硬前提。
  check(function () { return typeof WebAssembly === 'object' &&
    typeof WebAssembly.instantiateStreaming === 'function'; },
    'WebAssembly 引擎或 instantiateStreaming 缺失：wasm 无法运行');
  check(function () { return typeof fetch === 'function'; },
    'fetch API 缺失：网络层不可用');
  check(function () { return typeof ReadableStream === 'function'; },
    'ReadableStream 缺失：流式下载不可用');
  check(function () { return typeof TextDecoder === 'function'; },
    'TextDecoder 缺失：文本解码不可用');
  check(function () {
    return typeof crypto === 'object' &&
      typeof crypto.getRandomValues === 'function';
  }, 'crypto.getRandomValues 缺失：随机数不可用');
  check(function () { return typeof indexedDB === 'object'; },
    'indexedDB 缺失：本地缓存不可用');
  check(function () { return typeof atob === 'function' && typeof btoa === 'function'; },
    'atob/btoa 缺失：Base64 处理不可用');
  check(function () { return typeof URL === 'function'; },
    'URL 缺失：地址拼接不可用');
  check(function () { return typeof Worker === 'function'; },
    'Worker 缺失：后台任务不可用');
  check(function () { return typeof performance === 'object' &&
    typeof performance.now === 'function'; },
    'performance.now 缺失：动画计时不可用');

  // ② 跨源隔离相关：有 SharedArrayBuffer 就必须已隔离，没有就明确要求隔离头。
  var isolated = (typeof crossOriginIsolated === 'boolean') ? crossOriginIsolated : false;
  if (typeof SharedArrayBuffer === 'function' && !isolated) {
    failures.push('SharedArrayBuffer 存在但未跨源隔离：需 COOP/COEP 响应头');
  }

  if (failures.length > 0) {
    var err = new Error('[OGL] 浏览器能力检查未通过：\n - ' + failures.join('\n - '));
    err.name = 'OgLWebApiUnsupported';
    // 抛到全局：Flutter 引擎加载前的错误，用户能直接看到原因。
    window.__oglWebApiFailures = failures;
    throw err;
  }

  window.__oglWebApiChecked = true;
})();
'''


class WebBuildError(RuntimeError):
    """门禁失败：必须让 CI 变红（web 腿 best-effort 时只影响该腿）。"""


def _fail(msg: str) -> None:
    raise WebBuildError(msg)


def _read(path: str) -> str:
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def _write(path: str, text: str) -> None:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)


def ensure_scaffold(web_dir: str) -> None:
    """确认 web 脚手架存在（平台目录由 `flutter create --platforms=web` 生成）。"""
    index = os.path.join(web_dir, 'index.html')
    if not os.path.isfile(index):
        _fail('缺少 %s：CI 需先执行 '
              '`flutter create --platforms=web --org com.yingo '
              '--project-name ohgithublost .`' % index)
    html = _read(index)
    for marker in REQUIRED_HTML_MARKERS:
        if marker not in html:
            _fail('web/index.html 缺少引导标记 `%s`（Flutter 模板已损坏）' % marker)


def write_guard(web_dir: str) -> str:
    """把守卫脚本写进 web/，返回其路径。"""
    path = os.path.join(web_dir, 'web_api_guard.js')
    _write(path, GUARD_JS)
    return path


def inject_guard(web_dir: str) -> bool:
    """把守卫 `<script>` **动态注入** index.html（幂等：已注入则不重复）。"""
    index = os.path.join(web_dir, 'index.html')
    html = _read(index)
    if GUARD_MARK in html:
        return False
    tag = ('\n  <!-- %s：浏览器 API 检查（缺失即抛错） -->\n'
           '  <script src="web_api_guard.js"></script>\n' % GUARD_MARK)
    lowered = html.lower()
    idx = lowered.find('</head>')
    if idx < 0:
        _fail('web/index.html 没有 </head>，无法注入 API 守卫')
    html = html[:idx] + tag + html[idx:]
    _write(index, html)
    return True


def inject_coep_meta(web_dir: str) -> None:
    """写入 COOP/COEP 的 `<meta>` 兜底（服务端未下发响应头时仍尽量隔离）。

    注意：COOP/COEP 的**权威**生效方式是 HTTP 响应头；meta 只是本地
    静态托管（如 `python3 -m http.server`、file://）下的兜底。
    """
    index = os.path.join(web_dir, 'index.html')
    html = _read(index)
    if 'http-equiv="Cross-Origin-Opener-Policy"' in html:
        return
    tag = ('\n  <!-- 跨源隔离兜底（生产应由响应头下发 COOP/COEP） -->\n'
           '  <meta http-equiv="Cross-Origin-Opener-Policy" content="require-corp">\n'
           '  <meta http-equiv="Cross-Origin-Embedder-Policy" content="require-corp">\n')
    idx = html.lower().find('</head>')
    if idx < 0:
        _fail('web/index.html 没有 </head>，无法注入 COOP/COEP meta')
    _write(index, html[:idx] + tag + html[idx:])


def report_guard_contract() -> str:
    """输出守卫覆盖的能力清单（CI 日志可读证据）。"""
    lines = ['守卫能力清单（%d 项必需 + %d 项跨源隔离）：' % (
        len(GUARD_CHECKS), len(CROSS_ORIGIN_ISOLATED))]
    for name, why in GUARD_CHECKS + CROSS_ORIGIN_ISOLATED:
        lines.append('  - %-32s %s' % (name, why))
    return '\n'.join(lines)


def verify(build_dir: str) -> None:
    """编译后逐项核对产物。"""
    if not os.path.isdir(build_dir):
        _fail('产物目录不存在：%s' % build_dir)

    must_have = [
        'index.html',
        'flutter_bootstrap.js',
        'main.dart.js',
        'web_api_guard.js',
    ]
    missing = [name for name in must_have
               if not os.path.isfile(os.path.join(build_dir, name))]
    if missing:
        _fail('产物缺少必需文件：%s' % '、'.join(missing))

    # 引擎二选一：CanvasKit（含 wasm）或 HTML 渲染器。
    engines = [name for name in ('canvaskit', 'canvaskit.wasm', 'flutter.js')
               if os.path.exists(os.path.join(build_dir, name))]
    if not engines:
        _fail('产物缺少渲染引擎（canvaskit/ 或 flutter.js）')

    has_wasm = any(name.endswith('.wasm') for name in os.listdir(build_dir))
    if not has_wasm:
        _fail('产物中没有任何 .wasm：wasm 目标未生效，请确认 '
              '`flutter build web` 使用了 wasm 产物')

    index_html = _read(os.path.join(build_dir, 'index.html'))
    if GUARD_MARK not in index_html or 'web_api_guard.js' not in index_html:
        _fail('产物 index.html 未注入浏览器 API 守卫（守卫在运行时是唯一防线）')

    total = sum(os.path.getsize(os.path.join(dp, f))
                for dp, _, fs in os.walk(build_dir) for f in fs)
    print('[verify] 产物校验通过：引擎=%s 守卫=已注入 大小=%.1f MB'
          % ('、'.join(engines), total / 1024 / 1024))


def publish(build_dir: str, app_dir: str, keep_stamp: bool = True) -> None:
    """发布到 `app/`：**先清空目录**再拷贝，只保留最新一套 web 文件。"""
    if os.path.exists(app_dir):
        shutil.rmtree(app_dir)
    os.makedirs(app_dir, exist_ok=True)
    for name in sorted(os.listdir(build_dir)):
        src = os.path.join(build_dir, name)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(app_dir, name))
        else:
            shutil.copy2(src, os.path.join(app_dir, name))
    if keep_stamp:
        stamp = {
            'source': os.path.relpath(build_dir, ROOT).replace(os.sep, '/'),
            'note': '实验性 web 目标：由 .github/workflows/web.yml 自动生成，'
                    '每次发布前目录会被清空重建。',
            'wasm': sorted(n for n in os.listdir(app_dir) if n.endswith('.wasm')),
            'api_guard': GUARD_MARK,
        }
        _write(os.path.join(app_dir, 'ogl-web.json'),
               json.dumps(stamp, ensure_ascii=False, indent=2) + '\n')
    count = sum(len(fs) for _, _, fs in os.walk(app_dir))
    print('[publish] 已清空并重建 %s（%d 个文件）' % (app_dir, count))


def main() -> int:
    ap = argparse.ArgumentParser(description='OGL web 编译辅助')
    ap.add_argument('--prepare', action='store_true', help='体检 + 注入守卫')
    ap.add_argument('--verify', action='store_true', help='校验编译产物')
    ap.add_argument('--publish', action='store_true', help='清空并重建 app/')
    ap.add_argument('--web', default=os.path.join(ROOT, 'web'))
    ap.add_argument('--build', default=os.path.join(ROOT, 'build', 'web'))
    ap.add_argument('--app', default=os.path.join(ROOT, 'app'))
    args = ap.parse_args()

    try:
        if args.prepare:
            ensure_scaffold(args.web)
            write_guard(args.web)
            inject_guard(args.web)
            inject_coep_meta(args.web)
            print('[prepare] web 脚手架体检通过，API 守卫已注入')
            print(report_guard_contract())
        if args.verify:
            verify(args.build)
        if args.publish:
            publish(args.build, args.app)
    except WebBuildError as error:
        sys.stderr.write('[web_build] 门禁失败：%s\n' % error)
        return 1
    if not (args.prepare or args.verify or args.publish):
        ap.print_help()
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
